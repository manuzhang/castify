import Foundation

enum EpisodeSummarySourceKind: String, Hashable {
  case transcript
  case showNotes
}

/// Describes the supplied text, not a claim that it covers the entire recording.
struct EpisodeSummarySource: Equatable {
  let kind: EpisodeSummarySourceKind
  let text: String
  let url: URL?
}

struct EpisodeSummaryRequest: Equatable {
  let episodeID: String
  let source: EpisodeSummarySource
  /// Language code, such as "en" or "zh-Hans".
  let outputLanguage: String
}

enum EpisodeSummaryMethod: String {
  case extractive
  case unspecified
}

struct EpisodeSummaryContent: Equatable {
  let overview: String
  let keyPoints: [String]
  let method: EpisodeSummaryMethod

  init(overview: String, keyPoints: [String], method: EpisodeSummaryMethod = .unspecified) {
    self.overview = overview
    self.keyPoints = keyPoints
    self.method = method
  }
}

struct EpisodeSummary: Equatable {
  let content: EpisodeSummaryContent
  let episodeID: String
  let sourceKind: EpisodeSummarySourceKind
  let sourceURL: URL?
  let outputLanguage: String
  let providerID: String
}

enum EpisodeSummaryError: Error, Equatable {
  enum UnavailableReason: Equatable {
    case notConfigured
    case unsupportedDevice
    case modelNotReady
  }

  case invalidInput
  case insufficientContent
  case unsupportedSource
  case unsupportedLanguage
  case inputTooLong(limit: Int)
  case unavailable(UnavailableReason)
  case authenticationRequired
  case rateLimited
  case transportFailure
  case generationFailed
  case invalidResponse
  case cancelled
}

enum EpisodeSummaryAvailability: Equatable {
  case available
  case unavailable(EpisodeSummaryError.UnavailableReason)
}

struct EpisodeSummaryCapabilities {
  let sourceKinds: Set<EpisodeSummarySourceKind>
  /// nil means that the provider imposes no language allowlist.
  let outputLanguages: Set<String>?
  let maximumInputCharacters: Int?

  static let text = EpisodeSummaryCapabilities(
    sourceKinds: [.transcript, .showNotes],
    outputLanguages: nil,
    maximumInputCharacters: nil
  )
}

protocol EpisodeSummaryCancellable {
  func cancel()
}

protocol EpisodeSummaryProvider {
  var id: String { get }
  var capabilities: EpisodeSummaryCapabilities { get }
  /// Reevaluate device/model/configuration readiness for each request.
  var availability: EpisodeSummaryAvailability { get }

  /// An implementation may complete on any queue. Map vendor errors to this contract.
  @discardableResult
  func summarize(_ request: EpisodeSummaryRequest,
                 completion: @escaping (Result<EpisodeSummaryContent, EpisodeSummaryError>) -> Void)
    -> EpisodeSummaryCancellable
}

final class EpisodeSummaryService {
  let provider: EpisodeSummaryProvider

  init(provider: EpisodeSummaryProvider = LocalEpisodeSummaryProvider()) {
    self.provider = provider
  }

  /// Completes asynchronously on the main queue, exactly once. The first terminal
  /// result or cancellation wins; cancellation also stops the underlying operation.
  @discardableResult
  func summarize(_ request: EpisodeSummaryRequest,
                 completion: @escaping (Result<EpisodeSummary, EpisodeSummaryError>) -> Void)
    -> EpisodeSummaryCancellable {
    let task = EpisodeSummaryTask(completion: completion)
    let capabilities = provider.capabilities
    let trimmed: (String) -> String = { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    guard !trimmed(request.episodeID).isEmpty,
          !trimmed(request.source.text).isEmpty,
          !trimmed(request.outputLanguage).isEmpty else {
      task.finish(.failure(.invalidInput))
      return task
    }
    if case .unavailable(let reason) = provider.availability {
      task.finish(.failure(.unavailable(reason)))
      return task
    }
    guard capabilities.sourceKinds.contains(request.source.kind) else {
      task.finish(.failure(.unsupportedSource))
      return task
    }
    if let languages = capabilities.outputLanguages, !languages.contains(request.outputLanguage) {
      task.finish(.failure(.unsupportedLanguage))
      return task
    }
    if let limit = capabilities.maximumInputCharacters, request.source.text.count > limit {
      task.finish(.failure(.inputTooLong(limit: limit)))
      return task
    }

    let providerID = provider.id
    let operation = provider.summarize(request) { result in
      switch result {
      case .success(let content):
        guard !trimmed(content.overview).isEmpty,
              !content.keyPoints.isEmpty,
              content.keyPoints.allSatisfy({ !trimmed($0).isEmpty }) else {
          task.finish(.failure(.invalidResponse))
          return
        }
        task.finish(.success(EpisodeSummary(
          content: content,
          episodeID: request.episodeID,
          sourceKind: request.source.kind,
          sourceURL: request.source.url,
          outputLanguage: request.outputLanguage,
          providerID: providerID
        )))
      case .failure(let error):
        task.finish(.failure(error))
      }
    }
    task.setOperation(operation)
    return task
  }
}

private final class EpisodeSummaryTask: EpisodeSummaryCancellable {
  private let lock = NSLock()
  private var completion: ((Result<EpisodeSummary, EpisodeSummaryError>) -> Void)?
  private var operation: EpisodeSummaryCancellable?
  private var cancelled = false

  init(completion: @escaping (Result<EpisodeSummary, EpisodeSummaryError>) -> Void) {
    self.completion = completion
  }

  func setOperation(_ operation: EpisodeSummaryCancellable) {
    lock.lock()
    let shouldCancel = cancelled
    if completion != nil { self.operation = operation }
    lock.unlock()
    if shouldCancel { operation.cancel() }
  }

  func finish(_ result: Result<EpisodeSummary, EpisodeSummaryError>) {
    lock.lock()
    let callback = completion
    completion = nil
    operation = nil
    lock.unlock()
    if let callback = callback {
      DispatchQueue.main.async { callback(result) }
    }
  }

  func cancel() {
    lock.lock()
    guard let callback = completion else {
      lock.unlock()
      return
    }
    cancelled = true
    completion = nil
    let operation = self.operation
    self.operation = nil
    lock.unlock()
    operation?.cancel()
    DispatchQueue.main.async { callback(.failure(.cancelled)) }
  }
}
