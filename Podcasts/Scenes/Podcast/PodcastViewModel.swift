import Foundation
import FeedKit

final class PodcastViewModel: ObservableObject {

  // MARK: - Private
  fileprivate let networkingService = NetworkingService()
  fileprivate let podcastsService   = PodcastsService()

  // MARK: - Properties
  let podcast: Podcast
  var description: String = ""
  var subscribed: Bool
  @Published private(set) var episodes = [Episode]()
  // var dataSource: TableViewDataSource<Episode, EpisodeCell>?

  init(podcast: Podcast) {
    self.podcast = podcast
    self.subscribed = podcastsService.subscribedPodcasts.contains(self.podcast)
  }
}

extension PodcastViewModel {

  func fetchEpisodes(_ completion: @escaping () -> Void) {
    print("Looking for episodes at feed url:", podcast.feedUrl)
    guard let url = URL(string: podcast.feedUrl.httpsUrlString) else {
      return
    }

    let parser = FeedParser(URL: url)
    DispatchQueue.main.async {
      parser.parse().map { result in
        result.rssFeed.map { feed in
          self.description = feed.description?.replacingOccurrences(
              of: "\\s*<[^>]+>\\s*", with: "", options: .regularExpression, range: nil) ?? ""
          self.episodes = feed.toEpisodes()
          completion()
        }
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
