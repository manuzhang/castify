//
// Created by doriadong on 2020/1/26.
// Copyright (c) 2020 com.github.albertopeam. All rights reserved.
//

import Foundation
import FeedKit

final class PodcastViewModel: ObservableObject {

  // MARK: - Private
  fileprivate let networkingService = NetworkingService()
  fileprivate let podcastsService   = PodcastsService()

  // MARK: - Properties
  let podcast: Podcast
  var description: String = ""
  @Published private(set) var episodes = [Episode]()
  // var dataSource: TableViewDataSource<Episode, EpisodeCell>?

  init(podcast: Podcast) {
    self.podcast = podcast
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
    podcastsService.subscribedPodcasts.contains(self.podcast)
  }
  
  func subscribe() {
    var pods = podcastsService.subscribedPodcasts
    pods.append(podcast)
    let data = try! NSKeyedArchiver.archivedData(
      withRootObject: PropertyListEncoder().encode(pods),
      requiringSecureCoding: false)
    UserDefaults.standard.set(data, forKey: UserDefaults.subscribedPodcastsKey)
  }

  func unsubscribe() {
    podcastsService.deletePodcast(podcast)
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
