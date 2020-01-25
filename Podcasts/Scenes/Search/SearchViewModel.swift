import SwiftUI
import Combine

final class SearchViewModel: ObservableObject {

  @Published var name = ""

  @Published private(set) var podcasts = [Podcast]()

  // @Published private(set) var podcastImages = [Podcast: UIImage]()

  private var searchCancellable: Cancellable? {
    didSet {
      oldValue?.cancel()
    }
  }

  deinit {
    searchCancellable?.cancel()
  }

  func search() {
    guard !name.isEmpty else {
      return podcasts = []
    }

    let networkingService = NetworkingService()
    networkingService.fetchPodcasts(searchText: name) { [weak self] podcasts in
      guard let self = self else {
        return
      }
      self.podcasts = podcasts
    }
  }
}
