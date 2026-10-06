import Foundation

final class PodcastsViewModel: ObservableObject {

  @Published private(set) var podcasts = [Podcast]()
  @Published private(set) var upNextEpisodes = [Episode]()
  fileprivate let podcastsService = PodcastsService()
  fileprivate let networkingService = NetworkingService()
  private var isRefreshingUpNextFeeds = false

  func updatePodcasts() {
    let pods = podcastsService.subscribedPodcasts
    self.podcasts = pods.sorted(by: {$0.trackName < $1.trackName})
    self.updateUpNextEpisodes()
    self.refreshUpNextEpisodesFromFeeds(pods)
  }

  func updateUpNextEpisodes() {
    upNextEpisodes = podcastsService.inProgressEpisodes()
  }

  func reorderUpNextEpisodes(_ episodes: [Episode]) {
    podcastsService.reorderInProgressEpisodes(episodes)
    upNextEpisodes = podcastsService.inProgressEpisodes()
  }

  func playbackState(for episode: Episode) -> EpisodePlaybackState? {
    podcastsService.playbackState(for: episode)
  }

  private func refreshUpNextEpisodesFromFeeds(_ podcasts: [Podcast]) {
    let feeds = podcasts.compactMap { podcast in
      URL(string: podcast.feedUrl.httpsUrlString).map { (podcast: podcast, url: $0) }
    }
    guard !feeds.isEmpty && !isRefreshingUpNextFeeds else {
      return
    }

    isRefreshingUpNextFeeds = true
    var remainingFeeds = feeds.count
    feeds.forEach { feed in
      networkingService.fetchPodcastFeed(url: feed.url, podcast: feed.podcast) { [weak self] result in
        guard let self = self else {
          return
        }

        if case .success(let feed) = result {
          self.podcastsService.cacheInProgressEpisodes(feed.episodes)
          self.podcastsService.cacheStarredEpisodes(feed.episodes)
        }

        remainingFeeds -= 1
        if remainingFeeds == 0 {
          self.isRefreshingUpNextFeeds = false
          self.updateUpNextEpisodes()
        }
      }
    }
  }
}
