import XCTest
@testable import Castify

final class EpisodeSummaryServiceTests: XCTestCase {
  private let fixture = EpisodeSummaryContent(
    overview: "Fixture summary from a test double, not AI output.",
    keyPoints: ["Fixture key point"]
  )

  func testRemoteAndLocalProvidersAreInterchangeableAndPreserveProvenance() throws {
    for local in [false, true] {
      for kind in [EpisodeSummarySourceKind.transcript, .showNotes] {
        let engine = ControlledSummaryEngine()
        let provider = makeProvider(local: local, engine: engine)
        let request = makeRequest(kind: kind)
        let completed = expectation(description: "Summary")
        EpisodeSummaryService(provider: provider).summarize(request) { result in
          XCTAssertTrue(Thread.isMainThread)
          switch result {
          case .success(let summary):
            XCTAssertEqual(summary.content, self.fixture)
            XCTAssertEqual(summary.episodeID, request.episodeID)
            XCTAssertEqual(summary.sourceKind, kind)
            XCTAssertEqual(summary.sourceURL, request.source.url)
            XCTAssertEqual(summary.outputLanguage, "zh-Hans")
            XCTAssertEqual(summary.providerID, provider.id)
          case .failure(let error): XCTFail("Unexpected error: \(error)")
          }
          completed.fulfill()
        }
        XCTAssertEqual(engine.requests, [request])
        engine.complete(.success(fixture))
        wait(for: [completed], timeout: 2)
      }
    }
  }

  func testUnconfiguredRemoteAdapterReturnsUnavailableWithoutProducingContent() {
    let provider = RemoteEpisodeSummaryProvider()
    XCTAssertEqual(provider.availability, .unavailable(.notConfigured))
    assertFailure(.unavailable(.notConfigured), provider: provider)
  }

  func testLocalAvailabilityIsReevaluatedWhenDeviceOrModelReadinessChanges() {
    let engine = ControlledSummaryEngine()
    var readiness = EpisodeSummaryAvailability.unavailable(.unsupportedDevice)
    let provider = LocalEpisodeSummaryProvider(availability: { readiness }, operation: engine.start)
    assertFailure(.unavailable(.unsupportedDevice), provider: provider)
    readiness = .unavailable(.modelNotReady)
    assertFailure(.unavailable(.modelNotReady), provider: provider)
    XCTAssertTrue(engine.requests.isEmpty)
    readiness = .available
    XCTAssertEqual(provider.availability, .available)
    let completed = expectation(description: "Ready model")
    EpisodeSummaryService(provider: provider).summarize(makeRequest()) { result in
      XCTAssertNotNil(try? result.get())
      completed.fulfill()
    }
    engine.complete(.success(fixture))
    wait(for: [completed], timeout: 2)
    XCTAssertEqual(engine.requests.count, 1)
  }

  func testInvalidInputDoesNotReachEitherProvider() {
    for local in [false, true] {
      let engine = ControlledSummaryEngine()
      let provider = makeProvider(local: local, engine: engine)
      for request in [makeRequest(text: " \n"), makeRequest(language: ""), makeRequest(episodeID: " ")] {
        assertFailure(.invalidInput, provider: provider, request: request)
      }
      XCTAssertTrue(engine.requests.isEmpty)
    }
  }

  func testCapabilitiesRejectUnsupportedSourceLanguageAndLengthBeforeExecution() {
    let capabilities = EpisodeSummaryCapabilities(
      sourceKinds: [.transcript], outputLanguages: ["en"], maximumInputCharacters: 5
    )
    for local in [false, true] {
      let engine = ControlledSummaryEngine()
      let provider = makeProvider(local: local, engine: engine, capabilities: capabilities)
      assertFailure(.unsupportedSource, provider: provider, request: makeRequest(kind: .showNotes, text: "Text", language: "en"))
      assertFailure(.unsupportedLanguage, provider: provider, request: makeRequest(text: "Text", language: "zh-Hans"))
      assertFailure(.inputTooLong(limit: 5), provider: provider, request: makeRequest(text: "Longer text", language: "en"))
      XCTAssertTrue(engine.requests.isEmpty)
    }
  }

  func testProviderFailuresUseTheSameErrorContract() {
    for local in [false, true] {
      for error in [EpisodeSummaryError.authenticationRequired, .rateLimited, .transportFailure, .generationFailed] {
        let engine = ControlledSummaryEngine()
        let provider = makeProvider(local: local, engine: engine)
        let completed = expectation(description: "Provider failure")
        EpisodeSummaryService(provider: provider).summarize(makeRequest()) { result in
          XCTAssertEqual(result, .failure(error))
          completed.fulfill()
        }
        engine.complete(.failure(error))
        wait(for: [completed], timeout: 2)
      }
    }
  }

  func testMalformedProviderOutputIsRejected() {
    let invalidContents = [
      EpisodeSummaryContent(overview: " ", keyPoints: ["Point"]),
      EpisodeSummaryContent(overview: "Overview", keyPoints: []),
      EpisodeSummaryContent(overview: "Overview", keyPoints: [" \n"])
    ]
    for local in [false, true] {
      for content in invalidContents {
        let engine = ControlledSummaryEngine()
        let completed = expectation(description: "Invalid response")
        EpisodeSummaryService(provider: makeProvider(local: local, engine: engine)).summarize(makeRequest()) { result in
          XCTAssertEqual(result, .failure(.invalidResponse))
          completed.fulfill()
        }
        engine.complete(.success(content))
        wait(for: [completed], timeout: 2)
      }
    }
  }

  func testCancellationStopsEitherOperationAndIgnoresLateCallbacks() {
    for local in [false, true] {
      let engine = ControlledSummaryEngine()
      let completed = expectation(description: "Cancelled")
      var completions = 0
      let task = EpisodeSummaryService(provider: makeProvider(local: local, engine: engine)).summarize(makeRequest()) { result in
        XCTAssertTrue(Thread.isMainThread)
        XCTAssertEqual(result, .failure(.cancelled))
        completions += 1
        completed.fulfill()
      }
      // A cancelled transport may itself report failure synchronously.
      engine.operation.onCancel = { [weak engine] in engine?.complete(.failure(.transportFailure)) }
      task.cancel()
      task.cancel()
      engine.complete(.success(fixture))
      waitForCallbacks(completed)
      XCTAssertEqual(engine.operation.cancellations, 1)
      XCTAssertEqual(completions, 1)
    }
  }

  func testFirstProviderCompletionWinsOverDuplicateAndLaterCancellation() {
    for local in [false, true] {
      let engine = ControlledSummaryEngine()
      let completed = expectation(description: "First result")
      var completions = 0
      let task = EpisodeSummaryService(provider: makeProvider(local: local, engine: engine)).summarize(makeRequest()) { result in
        XCTAssertEqual(result, .failure(.rateLimited))
        completions += 1
        completed.fulfill()
      }
      engine.complete(.failure(.rateLimited))
      engine.complete(.success(fixture))
      task.cancel()
      waitForCallbacks(completed)
      XCTAssertEqual(completions, 1)
      XCTAssertEqual(engine.operation.cancellations, 0)
    }
  }

  func testSynchronousProviderCompletionIsDeliveredAsynchronously() {
    let operation = ControlledSummaryOperation()
    let provider = LocalEpisodeSummaryProvider(operation: { _, completion in
      completion(.success(self.fixture))
      return operation
    })
    var returned = false
    let completed = expectation(description: "Synchronous provider")
    let task = EpisodeSummaryService(provider: provider).summarize(makeRequest()) { result in
      XCTAssertTrue(returned)
      XCTAssertTrue(Thread.isMainThread)
      XCTAssertNotNil(try? result.get())
      completed.fulfill()
    }
    returned = true
    task.cancel()
    wait(for: [completed], timeout: 2)
    XCTAssertEqual(operation.cancellations, 0)
  }

  func testBackgroundProviderCompletionIsDeliveredOnMainQueue() {
    let completed = expectation(description: "Main queue delivery")
    let provider = RemoteEpisodeSummaryProvider(operation: { _, completion in
      DispatchQueue.global().async { completion(.success(self.fixture)) }
      return ControlledSummaryOperation()
    })
    EpisodeSummaryService(provider: provider).summarize(makeRequest()) { result in
      XCTAssertTrue(Thread.isMainThread)
      XCTAssertNotNil(try? result.get())
      completed.fulfill()
    }
    wait(for: [completed], timeout: 2)
  }

  private func makeRequest(kind: EpisodeSummarySourceKind = .transcript,
                           text: String = "Fixture episode text",
                           language: String = "zh-Hans",
                           episodeID: String = "fixture-episode") -> EpisodeSummaryRequest {
    EpisodeSummaryRequest(
      episodeID: episodeID,
      source: EpisodeSummarySource(kind: kind, text: text, url: URL(string: "https://example.invalid/transcript")),
      outputLanguage: language
    )
  }

  private func waitForCallbacks(_ completed: XCTestExpectation) {
    // Drain deliveries queued before this marker so duplicate callbacks cannot
    // hide behind the first expectation completing.
    let drained = expectation(description: "Callback queue drained")
    DispatchQueue.main.async { drained.fulfill() }
    wait(for: [completed, drained], timeout: 2)
  }

  private func makeProvider(local: Bool,
                            engine: ControlledSummaryEngine,
                            capabilities: EpisodeSummaryCapabilities = .text) -> EpisodeSummaryProvider {
    if local {
      return LocalEpisodeSummaryProvider(id: "local-test-double", capabilities: capabilities, operation: engine.start)
    }
    return RemoteEpisodeSummaryProvider(id: "remote-test-double", capabilities: capabilities, operation: engine.start)
  }

  private func assertFailure(_ error: EpisodeSummaryError,
                             provider: EpisodeSummaryProvider,
                             request: EpisodeSummaryRequest? = nil) {
    let completed = expectation(description: "Rejected request")
    EpisodeSummaryService(provider: provider).summarize(request ?? makeRequest()) { result in
      XCTAssertTrue(Thread.isMainThread)
      XCTAssertEqual(result, .failure(error))
      completed.fulfill()
    }
    wait(for: [completed], timeout: 2)
  }
}

private final class ControlledSummaryEngine {
  var requests = [EpisodeSummaryRequest]()
  let operation = ControlledSummaryOperation()
  private var completion: ((Result<EpisodeSummaryContent, EpisodeSummaryError>) -> Void)?

  func start(_ request: EpisodeSummaryRequest,
             completion: @escaping (Result<EpisodeSummaryContent, EpisodeSummaryError>) -> Void)
    -> EpisodeSummaryCancellable {
    requests.append(request)
    self.completion = completion
    return operation
  }

  func complete(_ result: Result<EpisodeSummaryContent, EpisodeSummaryError>) {
    completion?(result)
  }
}

private final class ControlledSummaryOperation: EpisodeSummaryCancellable {
  private(set) var cancellations = 0
  var onCancel: (() -> Void)?
  func cancel() {
    cancellations += 1
    onCancel?()
  }
}
