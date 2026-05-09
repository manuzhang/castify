import Foundation

struct EpisodePlaybackState: Codable, Equatable {
  static let minimumResumePosition: TimeInterval = 5

  let position: TimeInterval
  let duration: TimeInterval
  let played: Bool

  var hasResumePosition: Bool {
    !played && position >= Self.minimumResumePosition
  }

  var progress: Float {
    guard duration > 0 else {
      return 0
    }

    return Float(min(max(position / duration, 0), 1))
  }
}

final class PodcastsService {

  // MARK: - Properties
  var subscribedPodcasts: [Podcast] {
    fetchSavedPodcasts()
  }

  var downloadedEpisodes: [Episode] {
    fetchDownloadedEpisodes()
  }

}

// MARK: - Methods
extension PodcastsService {

  static func normalizedFeedUrl(_ feedUrl: String) -> String {
    let trimmed = feedUrl.trimmingCharacters(in: .whitespacesAndNewlines)

    guard var components = URLComponents(string: trimmed) else {
      return trimmed.lowercased()
    }

    components.scheme = components.scheme?.lowercased()
    components.host = components.host?.lowercased()
    if components.scheme == "http" {
      components.scheme = "https"
    }

    return components.string ?? trimmed.lowercased()
  }

  func containsPodcast(_ podcast: Podcast) -> Bool {
    subscribedPodcasts.contains { savedPodcast in
      matches(savedPodcast, podcast)
    }
  }

  @discardableResult
  func addPodcast(_ podcast: Podcast) -> Bool {
    var podcasts = subscribedPodcasts
    guard !podcasts.contains(where: { matches($0, podcast) }) else {
      return false
    }

    podcasts.append(podcast)

    do {
      let data = try JSONEncoder().encode(podcasts)
      UserDefaults.standard.set(data, forKey: UserDefaults.subscribedPodcastsKey)
      return true
    } catch let error {
      print("Failed to add podcast: " + podcast.trackName, error)
      return false
    }
  }

  @discardableResult
  func addPodcasts(_ podcasts: [Podcast]) -> Int {
    podcasts.reduce(0) { count, podcast in
      addPodcast(podcast) ? count + 1 : count
    }
  }

  func deletePodcast(_ podcast: Podcast) {
    let podcasts = subscribedPodcasts
    let filteredPodcasts = podcasts.filter { pod -> Bool in
      !matches(pod, podcast)
    }

    do {
      let data = try JSONEncoder().encode(filteredPodcasts)
      UserDefaults.standard.set(data, forKey: UserDefaults.subscribedPodcastsKey)
    } catch let error {
      print("Failed to delete podcast: " + podcast.trackName, error)
    }
  }

  func episodeDownloaded(_ episode: Episode) -> Bool {
    let episodes = downloadedEpisodes
    guard episodes.contains(episode) else {
      return false
    }

    guard let url = downloadedFileURL(for: episode) else {
      return false
    }

    return FileManager.default.fileExists(atPath: url.path)
  }

  func deleteEpisode(_ episode: Episode) {
    let fileManager = FileManager()
    if let url = downloadedFileURL(for: episode), fileManager.fileExists(atPath: url.path) {
      do {
        try fileManager.removeItem(at: url)
      } catch {
        print("Failed to delete episode file: " + url.path)
      }
    }

    let savedEpisodes = downloadedEpisodes
    let filteredEpisodes = savedEpisodes.filter { epi -> Bool in
      epi != episode
    }

    do {
      let data = try JSONEncoder().encode(filteredEpisodes)
      UserDefaults.standard.set(data, forKey: UserDefaults.downloadedEpisodesKey)
    } catch let encodeError {
      print("Failed to encode episode: ", encodeError)
    }
  }

  func playbackState(for episode: Episode) -> EpisodePlaybackState? {
    episodePlaybackStates()[playbackStateKey(for: episode)]
  }

  func resumePosition(for episode: Episode) -> TimeInterval {
    guard let state = playbackState(for: episode), state.hasResumePosition else {
      return 0
    }

    return state.position
  }

  func isEpisodePlayed(_ episode: Episode) -> Bool {
    playbackState(for: episode)?.played == true
  }

  func savePlaybackPosition(for episode: Episode,
                            elapsedTime: TimeInterval,
                            duration: TimeInterval) {
    guard duration > 0 else {
      return
    }

    var states = episodePlaybackStates()
    let key = playbackStateKey(for: episode)
    let clampedPosition = min(max(elapsedTime, 0), duration)
    let played = states[key]?.played == true || isPlayed(position: clampedPosition, duration: duration)
    let resumablePosition = played || clampedPosition < EpisodePlaybackState.minimumResumePosition ? 0 : clampedPosition
    let state = EpisodePlaybackState(
      position: resumablePosition,
      duration: duration,
      played: played
    )

    states[key] = state
    saveEpisodePlaybackStates(states)
  }

  func markEpisodePlayed(_ episode: Episode) {
    var states = episodePlaybackStates()
    let key = playbackStateKey(for: episode)
    let duration = playbackState(for: episode)?.duration ?? episode.duration ?? 0
    states[key] = EpisodePlaybackState(position: 0, duration: duration, played: true)
    saveEpisodePlaybackStates(states)
  }

  func markEpisodeUnplayed(_ episode: Episode) {
    var states = episodePlaybackStates()
    states.removeValue(forKey: playbackStateKey(for: episode))
    saveEpisodePlaybackStates(states)
  }

}

// MARK: - Matching
extension PodcastsService {

  fileprivate func matches(_ lhs: Podcast, _ rhs: Podcast) -> Bool {
    if lhs.trackId != 0 && lhs.trackId == rhs.trackId {
      return true
    }

    guard !lhs.feedUrl.isEmpty, !rhs.feedUrl.isEmpty else {
      return false
    }

    return Self.normalizedFeedUrl(lhs.feedUrl) == Self.normalizedFeedUrl(rhs.feedUrl)
  }

}

// MARK: - Private
extension PodcastsService {

  fileprivate func fetchSavedPodcasts() -> [Podcast] {
    guard let data = UserDefaults.standard.data(forKey: UserDefaults.subscribedPodcastsKey) else {
      return []
    }

    do {
      return try JSONDecoder().decode([Podcast].self, from: data)
    } catch {
      return []
    }
  }

  fileprivate func fetchDownloadedEpisodes() -> [Episode] {
    guard let data = UserDefaults.standard.data(forKey: UserDefaults.downloadedEpisodesKey) else {
      return []
    }

    do {
      return try JSONDecoder().decode([Episode].self, from: data)
    } catch let decodeError {
      print("Failed to decode:", decodeError)
      return []
    }
  }

  fileprivate func downloadedFileURL(for episode: Episode) -> URL? {
    let storedEpisode = downloadedEpisodes.first(where: { $0 == episode }) ?? episode
    guard let fileUrl = storedEpisode.fileUrl else {
      return nil
    }

    if let url = URL(string: fileUrl), url.isFileURL {
      return url
    }

    return URL(fileURLWithPath: fileUrl)
  }

  fileprivate func episodePlaybackStates() -> [String: EpisodePlaybackState] {
    guard let data = UserDefaults.standard.data(forKey: UserDefaults.episodePlaybackStatesKey) else {
      return [:]
    }

    do {
      return try JSONDecoder().decode([String: EpisodePlaybackState].self, from: data)
    } catch let decodeError {
      print("Failed to decode episode playback states:", decodeError)
      return [:]
    }
  }

  fileprivate func saveEpisodePlaybackStates(_ states: [String: EpisodePlaybackState]) {
    do {
      let data = try JSONEncoder().encode(states)
      UserDefaults.standard.set(data, forKey: UserDefaults.episodePlaybackStatesKey)
    } catch let encodeError {
      print("Failed to encode episode playback states:", encodeError)
    }
  }

  fileprivate func playbackStateKey(for episode: Episode) -> String {
    let streamUrl = episode.streamUrl.trimmingCharacters(in: .whitespacesAndNewlines)
    if !streamUrl.isEmpty {
      return streamUrl
    }

    let timestamp = Int(episode.pubDate.timeIntervalSince1970)
    return [episode.author, episode.title, String(timestamp)].joined(separator: "|")
  }

  fileprivate func isPlayed(position: TimeInterval, duration: TimeInterval) -> Bool {
    guard duration > 0 else {
      return false
    }

    let remaining = duration - position
    return remaining <= 30 || position / duration >= 0.95
  }

}
