import Foundation
import NaturalLanguage

/// Selects existing sentences. It never translates, rewrites, or accesses a network.
final class OfflineExtractiveSummarizer {
  static let maximumInputCharacters = 120_000
  static let maximumSentenceCharacters = 320
  static let maximumKeyPoints = 5
  static let capabilities = EpisodeSummaryCapabilities(
    sourceKinds: [.transcript, .showNotes], outputLanguages: nil,
    maximumInputCharacters: maximumInputCharacters
  )

  private let queue: DispatchQueue

  init(queue: DispatchQueue = DispatchQueue(label: "io.github.manuzhang.Castify.summary", qos: .userInitiated)) {
    self.queue = queue
  }

  func summarize(_ request: EpisodeSummaryRequest,
                 completion: @escaping (Result<EpisodeSummaryContent, EpisodeSummaryError>) -> Void)
    -> EpisodeSummaryCancellable {
    let task = ExtractiveSummaryTask(completion: completion)
    queue.async {
      do {
        task.finish(.success(try self.extract(request, task: task)))
      } catch let error as EpisodeSummaryError {
        task.finish(.failure(error))
      } catch {
        task.finish(.failure(.generationFailed))
      }
    }
    return task
  }

  private struct Sentence {
    let text: String
    let terms: Set<String>
    let position: Int
  }

  private func extract(_ request: EpisodeSummaryRequest, task: ExtractiveSummaryTask) throws -> EpisodeSummaryContent {
    try task.checkCancellation()
    guard !request.source.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw EpisodeSummaryError.invalidInput
    }
    guard request.source.text.count <= Self.maximumInputCharacters else {
      throw EpisodeSummaryError.inputTooLong(limit: Self.maximumInputCharacters)
    }

    var lines = [String]()
    for line in request.source.text.components(separatedBy: .newlines) {
      try task.checkCancellation()
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      if trimmed.isEmpty || trimmed == "WEBVTT" || trimmed.hasPrefix("NOTE ") ||
          trimmed.range(of: "^\\d+$|^https?://\\S+$|^.*\\d{2}:\\d{2}.*-->.*$", options: .regularExpression) != nil {
        continue
      }
      let normalized = trimmed.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
      if Self.noise.contains(String(String.UnicodeScalarView(normalized))) { continue }
      lines.append(trimmed)
    }
    let text = lines.joined(separator: "\n")
    guard text.unicodeScalars.contains(where: { CharacterSet.letters.contains($0) }) else {
      throw EpisodeSummaryError.insufficientContent
    }
    let recognizer = NLLanguageRecognizer()
    recognizer.processString(text)
    guard let language = recognizer.dominantLanguage,
          language == .english || language == .simplifiedChinese || language == .traditionalChinese,
          languageMatches(request.outputLanguage, detected: language) else {
      throw EpisodeSummaryError.unsupportedLanguage
    }
    try task.checkCancellation()

    let tokenizer = NLTokenizer(unit: .sentence)
    tokenizer.setLanguage(language)
    tokenizer.string = text
    var sentences = [Sentence]()
    var seen = Set<String>()
    tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
      if task.isCancelled { return false }
      let sentence = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
      // Skip oversized sentences instead of truncating their wording.
      guard sentence.count <= Self.maximumSentenceCharacters else { return true }
      let key = sentence.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
      let normalized = String(String.UnicodeScalarView(key))
      guard !normalized.isEmpty, !Self.noise.contains(normalized), seen.insert(normalized).inserted else { return true }
      let terms = self.terms(in: sentence, language: language)
      guard !terms.isEmpty else { return true }
      // Do not label a sentence from another script as translated output.
      let containsHan = sentence.unicodeScalars.contains { (0x3400...0x9FFF).contains($0.value) }
      if (language == .english && containsHan) || (language != .english && !containsHan) { return true }
      sentences.append(Sentence(text: sentence, terms: terms, position: sentences.count))
      return true
    }
    try task.checkCancellation()
    guard !sentences.isEmpty else { throw EpisodeSummaryError.insufficientContent }

    // Count each term once per unique sentence so repeated captions/filler cannot
    // inflate importance. Stable ties use original order.
    var frequencies = [String: Int]()
    for sentence in sentences {
      try task.checkCancellation()
      for term in sentence.terms { frequencies[term, default: 0] += 1 }
    }
    var ranked = [(sentence: Sentence, score: Double)]()
    for sentence in sentences {
      try task.checkCancellation()
      var weight = 0.0
      for term in sentence.terms.sorted() {
        weight += Double(frequencies[term, default: 0])
      }
      let averageWeight = weight / Double(sentence.terms.count)
      let positionBonus = 0.05 / Double(sentence.position + 1)
      ranked.append((sentence: sentence, score: averageWeight + positionBonus))
    }
    ranked.sort {
      if $0.score != $1.score { return $0.score > $1.score }
      return $0.sentence.position < $1.sentence.position
    }
    try task.checkCancellation()
    let selected = ranked.prefix(Self.maximumKeyPoints).map { $0.sentence }
    let points = selected.sorted { $0.position < $1.position }.map { $0.text }
    return EpisodeSummaryContent(overview: ranked[0].sentence.text, keyPoints: points, method: .extractive)
  }

  private func terms(in text: String, language: NLLanguage) -> Set<String> {
    let tokenizer = NLTokenizer(unit: .word)
    tokenizer.setLanguage(language)
    tokenizer.string = text
    var terms = Set<String>()
    tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
      let term = text[range].lowercased()
      if term.unicodeScalars.contains(where: { CharacterSet.letters.contains($0) }) && !Self.stopWords.contains(term) {
        terms.insert(term)
      }
      return true
    }
    return terms
  }

  private func languageMatches(_ code: String, detected: NLLanguage) -> Bool {
    let parts = code.lowercased().replacingOccurrences(of: "_", with: "-").split(separator: "-").map(String.init)
    if detected == .english { return parts.first == "en" }
    guard parts.first == "zh" else { return false }
    if parts.contains("hans") || parts.contains("cn") || parts.contains("sg") { return detected == .simplifiedChinese }
    if parts.contains("hant") || parts.contains("tw") || parts.contains("hk") || parts.contains("mo") { return detected == .traditionalChinese }
    return true
  }

  private static let noise: Set<String> = ["music", "laughter", "applause", "silence", "um", "uh", "音乐", "笑声", "掌声", "嗯"]
  private static let stopWords: Set<String> = [
    "a", "an", "the", "and", "or", "but", "to", "of", "in", "on", "at", "for", "from", "with", "as",
    "is", "are", "was", "were", "be", "been", "it", "this", "that", "we", "you", "i", "they", "he", "she",
    "our", "your", "their", "have", "has", "had", "do", "does", "did", "um", "uh",
    "的", "了", "和", "是", "在", "也", "就", "都", "我们", "你", "我", "他们", "这个", "那个", "一个", "嗯"
  ]
}

private final class ExtractiveSummaryTask: EpisodeSummaryCancellable {
  private let lock = NSLock()
  private var cancelled = false
  private var completion: ((Result<EpisodeSummaryContent, EpisodeSummaryError>) -> Void)?

  init(completion: @escaping (Result<EpisodeSummaryContent, EpisodeSummaryError>) -> Void) {
    self.completion = completion
  }

  var isCancelled: Bool {
    lock.lock()
    defer { lock.unlock() }
    return cancelled
  }

  func checkCancellation() throws {
    if isCancelled { throw EpisodeSummaryError.cancelled }
  }

  func finish(_ result: Result<EpisodeSummaryContent, EpisodeSummaryError>) {
    lock.lock()
    let callback = completion
    completion = nil
    lock.unlock()
    callback?(result)
  }

  func cancel() {
    lock.lock()
    cancelled = true
    let callback = completion
    completion = nil
    lock.unlock()
    callback?(.failure(.cancelled))
  }
}
