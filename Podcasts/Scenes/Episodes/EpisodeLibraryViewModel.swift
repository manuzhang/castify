import Foundation

enum EpisodeDurationFilter: String, CaseIterable {
  case any, under15Minutes, minutes15To30, minutes30To60, hourOrMore, unknown

  var text: AppText {
    switch self {
    case .any: return .anyDuration
    case .under15Minutes: return .under15Minutes
    case .minutes15To30: return .minutes15To30
    case .minutes30To60: return .minutes30To60
    case .hourOrMore: return .hourOrMore
    case .unknown: return .unknownDuration
    }
  }

  func matches(_ duration: TimeInterval?) -> Bool {
    if self == .any { return true }
    guard let duration = duration, duration.isFinite, duration > 0 else {
      return self == .unknown
    }
    switch self {
    case .any: return true
    case .under15Minutes: return duration < 900
    case .minutes15To30: return duration >= 900 && duration < 1800
    case .minutes30To60: return duration >= 1800 && duration < 3600
    case .hourOrMore: return duration >= 3600
    case .unknown: return false
    }
  }
}

struct LibraryEpisode: Identifiable {
  let podcast: Podcast
  let episode: Episode
  let playbackState: EpisodePlaybackState?
  let isDownloaded: Bool

  // Include feed ownership, even when two shows publish the same audio item.
  var id: String {
    [PodcastsService.normalizedFeedUrl(podcast.feedUrl), episode.title,
     episode.author, episode.streamUrl].map { "\($0.utf8.count):\($0)" }.joined()
  }
}

struct EpisodeFilters: Equatable {
  var unplayedOnly = false
  var downloadedOnly = false
  var podcastFeedURL = ""
  var duration = EpisodeDurationFilter.any

  func matches(_ item: LibraryEpisode) -> Bool {
    (!unplayedOnly || item.playbackState?.played != true) &&
      (!downloadedOnly || item.isDownloaded) &&
      (podcastFeedURL.isEmpty || podcastFeedURL == PodcastsService.normalizedFeedUrl(item.podcast.feedUrl)) &&
      duration.matches(item.episode.duration)
  }
}

final class EpisodeLibraryViewModel: ObservableObject {
  typealias FeedLoader = (Podcast, @escaping (Result<[Episode], Error>) -> Void) -> Void

  @Published var filters = EpisodeFilters()
  @Published private(set) var podcasts = [Podcast]()
  @Published private(set) var entries = [LibraryEpisode]()
  @Published private(set) var isRefreshing = false
  @Published private(set) var failedPodcasts = [String]()
  private let podcastsService: PodcastsService
  private let loadFeed: FeedLoader
  private var hasAppeared = false

  init(podcastsService: PodcastsService = .init(), loadFeed: FeedLoader? = nil) {
    self.podcastsService = podcastsService
    let networking = NetworkingService(podcastsService: podcastsService)
    self.loadFeed = loadFeed ?? { podcast, completion in
      guard let url = URL(string: podcast.feedUrl.httpsUrlString) else {
        completion(.failure(PodcastFeedParserError.invalidFeed))
        return
      }
      networking.fetchPodcastFeed(url: url, podcast: podcast) { result in
        completion(result.map { $0.episodes })
      }
    }
    reloadCachedEpisodes()
  }

  var filteredEntries: [LibraryEpisode] { entries.filter(filters.matches) }

  func appear() {
    reloadCachedEpisodes()
    if !hasAppeared {
      hasAppeared = true
      refresh()
    }
  }

  func reloadCachedEpisodes() {
    podcasts = podcastsService.subscribedPodcasts.sorted { $0.trackName < $1.trackName }
    if !filters.podcastFeedURL.isEmpty && !podcasts.contains(where: {
      PodcastsService.normalizedFeedUrl($0.feedUrl) == filters.podcastFeedURL
    }) {
      filters.podcastFeedURL = ""
    }
    var loaded = [LibraryEpisode]()
    for item in podcastsService.cachedEpisodeSnapshot(for: podcasts) {
      loaded.append(LibraryEpisode(podcast: item.podcast, episode: item.episode,
        playbackState: item.playbackState, isDownloaded: item.isDownloaded))
    }
    entries = loaded.sorted { first, second in
      if first.episode.pubDate == second.episode.pubDate { return first.id < second.id }
      return first.episode.pubDate > second.episode.pubDate
    }
  }

  func refresh() {
    guard !isRefreshing else { return }
    reloadCachedEpisodes()
    failedPodcasts = []
    guard !podcasts.isEmpty else { return }
    isRefreshing = true
    var remaining = podcasts.count
    for podcast in podcasts {
      loadFeed(podcast) { [weak self] result in
        guard let self = self else { return }
        // Network callbacks and state updates follow the app's main-thread convention.
        switch result {
        case .success(let episodes):
          self.podcastsService.cacheEpisodes(episodes, for: podcast)
          self.podcastsService.cacheInProgressEpisodes(episodes)
          self.podcastsService.cacheStarredEpisodes(episodes)
        case .failure:
          if self.podcastsService.containsPodcast(podcast) {
            self.failedPodcasts.append(podcast.trackName)
          }
        }
        remaining -= 1
        self.reloadCachedEpisodes()
        if remaining == 0 { self.isRefreshing = false }
      }
    }
  }

  func togglePlayed(_ item: LibraryEpisode) {
    if item.playbackState?.played == true {
      podcastsService.markEpisodeUnplayed(item.episode)
    } else {
      podcastsService.markEpisodePlayed(item.episode)
    }
    reloadCachedEpisodes()
  }
}
