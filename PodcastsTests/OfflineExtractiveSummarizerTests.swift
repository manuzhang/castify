import XCTest
@testable import Castify

final class OfflineExtractiveSummarizerTests: XCTestCase {
  private let english = """
  Good morning everyone.
  Battery storage makes renewable power more reliable.
  Solar panels produce power during daylight hours.
  Battery storage preserves surplus solar power for evening demand.
  Better battery chemistry increases storage capacity.
  Battery recycling recovers valuable materials for new storage systems.
  Grid operators use battery storage to balance power demand.
  Our guest enjoys hiking on weekends.
  """
  private let chinese = """
  今天我们讨论城市的公共交通。
  公共交通可以减少城市道路上的车辆。
  地铁和公交车帮助乘客节省通勤时间。
  完善的公共交通网络让居民更容易到达学校和医院。
  电动公交车能够减少空气污染。
  城市规划应该重视公共交通与步行道路的连接。
  社区居民也关心附近公园的开放时间。
  """
  private let traditional = """
  今天我們討論公共交通與城市發展。
  公共交通讓居民更容易到達學校和醫院。
  電動公車可以減少空氣污染。
  完善的交通網絡幫助乘客節省通勤時間。
  """

  func testDefaultServiceIsAvailableOfflineAndPreservesSourceProvenance() throws {
    let service = EpisodeSummaryService()
    XCTAssertEqual(service.provider.id, "local-extractive")
    XCTAssertEqual(service.provider.availability, .available)
    for kind in [EpisodeSummarySourceKind.transcript, .showNotes] {
      let request = makeRequest(english, kind: kind)
      let result = try summarize(request, service: service).get()
      XCTAssertEqual(result.providerID, "local-extractive")
      XCTAssertEqual(result.episodeID, request.episodeID)
      XCTAssertEqual(result.sourceKind, kind)
      XCTAssertEqual(result.sourceURL, request.source.url)
      XCTAssertEqual(result.outputLanguage, "en")
      XCTAssertEqual(result.content.method, .extractive)
      assertOriginalWording(result.content, in: english)
    }
    XCTAssertEqual(RemoteEpisodeSummaryProvider().availability, .unavailable(.notConfigured))
  }

  func testEnglishTranscriptSelectsTopicSentencesRatherThanUnrelatedGreeting() throws {
    let result = try summarize(makeRequest(english)).get()
    XCTAssertTrue(result.content.overview.lowercased().contains("battery"))
    XCTAssertFalse(result.content.keyPoints.contains("Good morning everyone."))
    XCTAssertFalse(result.content.keyPoints.contains("Our guest enjoys hiking on weekends."))
    assertOriginalWording(result.content, in: english)
  }

  func testChineseTranscriptRetainsChineseSentencesAndOriginalOrder() throws {
    let result = try summarize(makeRequest(chinese, language: "zh-Hans")).get()
    XCTAssertEqual(result.outputLanguage, "zh-Hans")
    XCTAssertEqual(result.content.method, .extractive)
    assertOriginalWording(result.content, in: chinese)
    let positions = result.content.keyPoints.compactMap { chinese.range(of: $0)?.lowerBound }
    XCTAssertEqual(positions, positions.sorted())
  }

  func testTraditionalChineseIsNotConvertedToSimplified() throws {
    let result = try summarize(makeRequest(traditional, language: "zh-Hant")).get()
    assertOriginalWording(result.content, in: traditional)
    XCTAssertEqual(result.outputLanguage, "zh-Hant")
    XCTAssertEqual(summarize(makeRequest(traditional, language: "zh-Hans")), .failure(.unsupportedLanguage))
  }

  func testShortInputReturnsTheWholeOriginalSentence() throws {
    let text = "Regular exercise improves sleep."
    let content = try summarize(makeRequest(text, language: "en-US")).get().content
    XCTAssertEqual(content.overview, text)
    XCTAssertEqual(content.keyPoints, [text])
    XCTAssertEqual(content.method, .extractive)
  }

  func testEmptyAndNoiseOnlyTextDoNotProduceAnInventedSummary() {
    XCTAssertEqual(summarize(makeRequest(" \n\t")), .failure(.invalidInput))
    let noise = "WEBVTT\n1\n00:00:01.000 --> 00:00:02.000\n[Music]\nhttps://example.invalid\n!!!"
    XCTAssertEqual(summarize(makeRequest(noise)), .failure(.insufficientContent))
  }

  func testCaptionMetadataAndStageCuesAreExcluded() throws {
    let text = "WEBVTT\n1\n00:00:01.000 --> 00:00:02.000\n[Music]\n" + english + "\nhttps://example.invalid\n[Applause]"
    let content = try summarize(makeRequest(text)).get().content
    assertOriginalWording(content, in: english)
    XCTAssertFalse(content.overview.contains("WEBVTT"))
    XCTAssertFalse(content.keyPoints.contains(where: { $0.contains("-->") || $0.contains("[Music]") }))
  }

  func testRepeatedSentencesDoNotFillTheSummaryOrInflateRanking() throws {
    let sentence = "Battery storage stabilizes renewable power."
    let text = Array(repeating: sentence, count: 30).joined(separator: "\n") + "\n" +
      "BATTERY STORAGE STABILIZES RENEWABLE POWER!\n" + "Solar panels supply daytime electricity."
    let content = try summarize(makeRequest(text)).get().content
    XCTAssertEqual(content.keyPoints.count, 2)
    XCTAssertEqual(content.keyPoints.first, sentence)
    XCTAssertFalse(content.keyPoints.contains("BATTERY STORAGE STABILIZES RENEWABLE POWER!"))
    assertOriginalWording(content, in: text)
  }

  func testOutputIsBoundedWithoutTruncatingSentences() throws {
    let oversized = "Battery " + String(repeating: "storage ", count: 100) + "helps."
    let text = oversized + "\n" + english
    let content = try summarize(makeRequest(text)).get().content
    XCTAssertLessThanOrEqual(content.keyPoints.count, 5)
    XCTAssertLessThanOrEqual(content.overview.count, 320)
    XCTAssertTrue(content.keyPoints.allSatisfy { $0.count <= 320 })
    XCTAssertFalse(content.keyPoints.contains(oversized))
    assertOriginalWording(content, in: text)
    XCTAssertEqual(summarize(makeRequest(oversized)), .failure(.insufficientContent))
  }

  func testOversizedInputReportsTheLimit() {
    XCTAssertEqual(
      summarize(makeRequest(String(repeating: "x", count: 120_001))),
      .failure(.inputTooLong(limit: 120_000))
    )
  }

  func testLanguageChangesAreRejectedInsteadOfPretendingToTranslate() {
    XCTAssertEqual(summarize(makeRequest(english, language: "zh")), .failure(.unsupportedLanguage))
    XCTAssertEqual(summarize(makeRequest(chinese, language: "en")), .failure(.unsupportedLanguage))
    XCTAssertEqual(summarize(makeRequest(english, language: "fr")), .failure(.unsupportedLanguage))
  }

  func testRepeatedRequestsAreDeterministic() throws {
    let request = makeRequest(english)
    let first = try summarize(request).get()
    for _ in 0..<3 {
      XCTAssertEqual(try summarize(request).get(), first)
    }
  }

  func testRealExtractiveOperationCanBeCancelledBeforeExecution() {
    let queue = DispatchQueue(label: "test.extractive.suspended")
    queue.suspend()
    let summarizer = OfflineExtractiveSummarizer(queue: queue)
    let provider = LocalEpisodeSummaryProvider(operation: summarizer.summarize)
    let completed = expectation(description: "Cancelled extraction")
    let drained = expectation(description: "Worker drained")
    var completions = 0
    let task = EpisodeSummaryService(provider: provider).summarize(makeRequest(english)) { result in
      XCTAssertTrue(Thread.isMainThread)
      XCTAssertEqual(result, .failure(.cancelled))
      completions += 1
      completed.fulfill()
    }
    task.cancel()
    task.cancel()
    queue.async { DispatchQueue.main.async { drained.fulfill() } }
    queue.resume()
    wait(for: [completed, drained], timeout: 3)
    XCTAssertEqual(completions, 1)
  }

  private func makeRequest(_ text: String, language: String = "en", kind: EpisodeSummarySourceKind = .transcript) -> EpisodeSummaryRequest {
    EpisodeSummaryRequest(
      episodeID: "offline-fixture",
      source: EpisodeSummarySource(kind: kind, text: text, url: URL(string: "https://example.invalid/transcript")),
      outputLanguage: language
    )
  }

  private func summarize(_ request: EpisodeSummaryRequest, service: EpisodeSummaryService = EpisodeSummaryService()) -> Result<EpisodeSummary, EpisodeSummaryError> {
    let completed = expectation(description: "Offline summary")
    var result: Result<EpisodeSummary, EpisodeSummaryError>?
    service.summarize(request) { summary in
      XCTAssertTrue(Thread.isMainThread)
      result = summary
      completed.fulfill()
    }
    wait(for: [completed], timeout: 3)
    return result ?? .failure(.generationFailed)
  }

  private func assertOriginalWording(_ content: EpisodeSummaryContent, in text: String, file: StaticString = #file, line: UInt = #line) {
    XCTAssertTrue(text.contains(content.overview), file: file, line: line)
    XCTAssertFalse(content.keyPoints.isEmpty, file: file, line: line)
    for point in content.keyPoints {
      XCTAssertTrue(text.contains(point), file: file, line: line)
    }
    XCTAssertEqual(Set(content.keyPoints).count, content.keyPoints.count, file: file, line: line)
  }
}
