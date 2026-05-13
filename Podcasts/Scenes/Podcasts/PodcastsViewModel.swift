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
    let feedUrls = podcasts.compactMap { URL(string: $0.feedUrl.httpsUrlString) }
    guard !feedUrls.isEmpty && !isRefreshingUpNextFeeds else {
      return
    }

    isRefreshingUpNextFeeds = true
    var remainingFeeds = feedUrls.count
    feedUrls.forEach { url in
      networkingService.fetchPodcastFeed(url: url) { [weak self] result in
        guard let self = self else {
          return
        }

        if case .success(let feed) = result {
          self.podcastsService.cacheInProgressEpisodes(feed.episodes)
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
