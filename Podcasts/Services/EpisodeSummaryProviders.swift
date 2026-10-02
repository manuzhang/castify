import Foundation

/// Injection boundary for a remote transport or a local inference engine.
/// Remote operations are opt-in; the local adapter defaults to offline extraction.
typealias EpisodeSummaryOperation = (
  EpisodeSummaryRequest,
  @escaping (Result<EpisodeSummaryContent, EpisodeSummaryError>) -> Void
) -> EpisodeSummaryCancellable

struct RemoteEpisodeSummaryProvider: EpisodeSummaryProvider {
  let id: String
  let capabilities: EpisodeSummaryCapabilities
  private let adapter: EpisodeSummaryAdapter
  var availability: EpisodeSummaryAvailability { adapter.availability }

  init(id: String = "remote",
       capabilities: EpisodeSummaryCapabilities = .text,
       availability: @escaping () -> EpisodeSummaryAvailability = { .available },
       operation: EpisodeSummaryOperation? = nil) {
    self.id = id
    self.capabilities = capabilities
    adapter = EpisodeSummaryAdapter(availability: availability, operation: operation)
  }

  func summarize(_ request: EpisodeSummaryRequest,
                 completion: @escaping (Result<EpisodeSummaryContent, EpisodeSummaryError>) -> Void)
    -> EpisodeSummaryCancellable {
    adapter.summarize(request, completion: completion)
  }
}

struct LocalEpisodeSummaryProvider: EpisodeSummaryProvider {
  let id: String
  let capabilities: EpisodeSummaryCapabilities
  private let adapter: EpisodeSummaryAdapter
  var availability: EpisodeSummaryAvailability { adapter.availability }

  init(id: String? = nil,
       capabilities: EpisodeSummaryCapabilities = OfflineExtractiveSummarizer.capabilities,
       availability: @escaping () -> EpisodeSummaryAvailability = { .available },
       operation: EpisodeSummaryOperation? = nil) {
    self.id = id ?? (operation == nil ? "local-extractive" : "local")
    self.capabilities = operation == nil ? OfflineExtractiveSummarizer.capabilities : capabilities
    let summarizer = OfflineExtractiveSummarizer()
    adapter = EpisodeSummaryAdapter(availability: availability, operation: operation ?? summarizer.summarize)
  }

  func summarize(_ request: EpisodeSummaryRequest,
                 completion: @escaping (Result<EpisodeSummaryContent, EpisodeSummaryError>) -> Void)
    -> EpisodeSummaryCancellable {
    adapter.summarize(request, completion: completion)
  }
}

private struct EpisodeSummaryAdapter {
  let availabilityCheck: () -> EpisodeSummaryAvailability
  let operation: EpisodeSummaryOperation?

  init(availability: @escaping () -> EpisodeSummaryAvailability,
       operation: EpisodeSummaryOperation?) {
    availabilityCheck = availability
    self.operation = operation
  }

  var availability: EpisodeSummaryAvailability {
    operation == nil ? .unavailable(.notConfigured) : availabilityCheck()
  }

  func summarize(_ request: EpisodeSummaryRequest,
                 completion: @escaping (Result<EpisodeSummaryContent, EpisodeSummaryError>) -> Void)
    -> EpisodeSummaryCancellable {
    if case .unavailable(let reason) = availability {
      completion(.failure(.unavailable(reason)))
      return InactiveEpisodeSummaryOperation()
    }
    guard let operation = operation else {
      completion(.failure(.unavailable(.notConfigured)))
      return InactiveEpisodeSummaryOperation()
    }
    return operation(request, completion)
  }
}

private struct InactiveEpisodeSummaryOperation: EpisodeSummaryCancellable {
  func cancel() {}
}
