import Foundation

final class PodcastViewModel: ObservableObject {

  // MARK: - Private
  fileprivate let networkingService = NetworkingService()
  fileprivate let podcastsService   = PodcastsService()

  // MARK: - Properties
  let podcast: Podcast
  @Published private(set) var description: String = ""
  @Published private(set) var subscribed: Bool
  @Published private(set) var isLoading: Bool = false
  @Published private(set) var errorMessage: String?
  @Published private(set) var episodes = [Episode]()
  // var dataSource: TableViewDataSource<Episode, EpisodeCell>?

  init(podcast: Podcast) {
    self.podcast = podcast
    self.subscribed = podcastsService.subscribedPodcasts.contains(self.podcast)
  }
}

extension PodcastViewModel {

  func fetchEpisodes(_ completion: @escaping () -> Void) {
    guard episodes.isEmpty && !isLoading else {
      completion()
      return
    }

    print("Looking for episodes at feed url:", podcast.feedUrl)
    guard let url = URL(string: podcast.feedUrl.httpsUrlString) else {
      errorMessage = "Invalid feed URL"
      completion()
      return
    }

    isLoading = true
    errorMessage = nil
    networkingService.fetchPodcastFeed(url: url) { result in
      self.isLoading = false

      switch result {
      case .success(let feed):
        self.description = feed.description
        self.episodes = feed.episodes
        completion()
      case .failure(let error):
        self.errorMessage = error.localizedDescription
        completion()
      }
    }
  }

  func isSubscribed() -> Bool {
    subscribed
  }
  
  func subscribe() {
    podcastsService.addPodcast(self.podcast)
    self.subscribed = true
  }

  func unsubscribe() {
    podcastsService.deletePodcast(podcast)
    self.subscribed = false
  }

  func episode(for indexPath: IndexPath) -> Episode {
    episodes[indexPath.row]
  }

  func checkIfPodcastHasFavorited() -> Bool {
    let savedPodcasts = podcastsService.subscribedPodcasts
    let hasFavorited = savedPodcasts
      .firstIndex(where: { $0.trackName  == self.podcast.trackName &&
      $0.artistName == self.podcast.artistName }) != nil
    return hasFavorited
  }

  fileprivate func episodesDidLoad(_ episodes: [Episode]) {
    self.episodes = episodes
    // dataSource = .make(for: episodes)
  }
}
