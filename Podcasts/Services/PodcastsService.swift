import Foundation

struct EpisodePlaybackState: Codable, Equatable {
  static let minimumResumePosition: TimeInterval = 5

  let position: TimeInterval
  let duration: TimeInterval
  let played: Bool
  let updatedAt: Date

  init(position: TimeInterval,
       duration: TimeInterval,
       played: Bool,
       updatedAt: Date = Date()) {
    self.position = position
    self.duration = duration
    self.played = played
    self.updatedAt = updatedAt
  }

  enum CodingKeys: String, CodingKey {
    case position
    case duration
    case played
    case updatedAt
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    position = try container.decode(TimeInterval.self, forKey: .position)
    duration = try container.decode(TimeInterval.self, forKey: .duration)
    played = try container.decode(Bool.self, forKey: .played)
    updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .distantPast
  }

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

  static let defaultAutoDownloadEpisodeLimit = 3
  static let autoDownloadEpisodeLimitRange = 1...10

  // MARK: - Properties
  var subscribedPodcasts: [Podcast] {
    fetchSavedPodcasts()
  }

  var downloadedEpisodes: [Episode] {
    fetchDownloadedEpisodes()
  }

  var autoDownloadEnabled: Bool {
    get {
      UserDefaults.standard.bool(forKey: UserDefaults.autoDownloadEnabledKey)
    }
    set {
      UserDefaults.standard.set(newValue, forKey: UserDefaults.autoDownloadEnabledKey)
    }
  }

  var autoDownloadEpisodeLimit: Int {
    get {
      let savedLimit = UserDefaults.standard.integer(forKey: UserDefaults.autoDownloadEpisodeLimitKey)
      guard Self.autoDownloadEpisodeLimitRange.contains(savedLimit) else {
        return Self.defaultAutoDownloadEpisodeLimit
      }

      return savedLimit
    }
    set {
      let clampedLimit = min(
        max(newValue, Self.autoDownloadEpisodeLimitRange.lowerBound),
        Self.autoDownloadEpisodeLimitRange.upperBound
      )
      UserDefaults.standard.set(clampedLimit, forKey: UserDefaults.autoDownloadEpisodeLimitKey)
    }
  }

  var autoDownloadWifiOnly: Bool {
    get {
      UserDefaults.standard.bool(forKey: UserDefaults.autoDownloadWifiOnlyKey)
    }
    set {
      UserDefaults.standard.set(newValue, forKey: UserDefaults.autoDownloadWifiOnlyKey)
    }
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

  func downloadedPlaybackURL(for episode: Episode) -> URL? {
    guard let url = downloadedFileURL(for: episode),
          FileManager.default.fileExists(atPath: url.path) else {
      return nil
    }

    return url
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

  func clearDownloadedEpisodes() {
    let fileManager = FileManager.default
    let episodesDirectory = Self.downloadedEpisodesDirectoryURL()

    if fileManager.fileExists(atPath: episodesDirectory.path) {
      do {
        try fileManager.removeItem(at: episodesDirectory)
      } catch {
        print("Failed to delete downloaded episodes directory: " + episodesDirectory.path, error)
      }
    }

    UserDefaults.standard.removeObject(forKey: UserDefaults.downloadedEpisodesKey)
  }

  func downloadedEpisodeCount() -> Int {
    downloadedEpisodes.filter { episodeDownloaded($0) }.count
  }

  func downloadedEpisodesStorageSize() -> Int64 {
    let fileManager = FileManager.default
    let episodesDirectory = Self.downloadedEpisodesDirectoryURL()

    guard let enumerator = fileManager.enumerator(
      at: episodesDirectory,
      includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
      options: [.skipsHiddenFiles]
    ) else {
      return 0
    }

    return enumerator.compactMap { item -> Int64? in
      guard let url = item as? URL,
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
            values.isRegularFile == true else {
        return nil
      }

      return Int64(values.fileSize ?? 0)
    }.reduce(0, +)
  }

  func inProgressEpisodes() -> [Episode] {
    let cachedEpisodes = fetchInProgressEpisodes()
    let states = episodePlaybackStates()
    let filteredEpisodes = uniqueEpisodes(cachedEpisodes).filter { episode in
      states[playbackStateKey(for: episode)]?.hasResumePosition == true
    }

    if filteredEpisodes.count != cachedEpisodes.count {
      saveInProgressEpisodes(filteredEpisodes)
      cleanInProgressEpisodeOrder(for: filteredEpisodes)
    }

    return orderedInProgressEpisodes(filteredEpisodes, states: states)
  }

  func reorderInProgressEpisodes(_ episodes: [Episode]) {
    let orderedEpisodes = uniqueEpisodes(episodes)
    cacheInProgressEpisodes(orderedEpisodes)
    saveInProgressEpisodeOrder(orderedEpisodes.map { playbackStateKey(for: $0) })
  }

  func cacheInProgressEpisodes(_ episodes: [Episode]) {
    let states = episodePlaybackStates()
    let resumableEpisodes = episodes.filter { episode in
      states[playbackStateKey(for: episode)]?.hasResumePosition == true
    }
    guard !resumableEpisodes.isEmpty else {
      return
    }

    var cachedEpisodes = fetchInProgressEpisodes()
    resumableEpisodes.forEach { episode in
      cachedEpisodes.removeAll(where: { $0 == episode })
      cachedEpisodes.append(episode)
    }
    saveInProgressEpisodes(cachedEpisodes)
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
    updateInProgressEpisode(episode, state: state)
  }

  func markEpisodePlayed(_ episode: Episode) {
    var states = episodePlaybackStates()
    let key = playbackStateKey(for: episode)
    let duration = playbackState(for: episode)?.duration ?? episode.duration ?? 0
    states[key] = EpisodePlaybackState(position: 0, duration: duration, played: true)
    saveEpisodePlaybackStates(states)
    removeInProgressEpisode(episode)
  }

  func markEpisodeUnplayed(_ episode: Episode) {
    var states = episodePlaybackStates()
    states.removeValue(forKey: playbackStateKey(for: episode))
    saveEpisodePlaybackStates(states)
    removeInProgressEpisode(episode)
  }

}

// MARK: - Matching
extension PodcastsService {

  static func downloadedEpisodesDirectoryURL() -> URL {
    let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    return documentsURL.appendingPathComponent("Episodes", isDirectory: true)
  }

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

  fileprivate func fetchInProgressEpisodes() -> [Episode] {
    guard let data = UserDefaults.standard.data(forKey: UserDefaults.inProgressEpisodesKey) else {
      return []
    }

    do {
      return try JSONDecoder().decode([Episode].self, from: data)
    } catch let decodeError {
      print("Failed to decode in-progress episodes:", decodeError)
      return []
    }
  }

  fileprivate func fetchInProgressEpisodeOrder() -> [String] {
    UserDefaults.standard.stringArray(forKey: UserDefaults.inProgressEpisodeOrderKey) ?? []
  }

  fileprivate func saveInProgressEpisodeOrder(_ order: [String]) {
    UserDefaults.standard.set(uniqueKeys(order), forKey: UserDefaults.inProgressEpisodeOrderKey)
  }

  fileprivate func cleanInProgressEpisodeOrder(for episodes: [Episode]) {
    let validKeys = Set(episodes.map { playbackStateKey(for: $0) })
    let order = fetchInProgressEpisodeOrder()
    let cleanedOrder = order.filter { validKeys.contains($0) }
    if cleanedOrder != order {
      saveInProgressEpisodeOrder(cleanedOrder)
    }
  }

  fileprivate func orderedInProgressEpisodes(
    _ episodes: [Episode],
    states: [String: EpisodePlaybackState]
  ) -> [Episode] {
    let order = fetchInProgressEpisodeOrder()
    let episodesByKey = episodes.reduce(into: [String: Episode]()) { result, episode in
      result[playbackStateKey(for: episode)] = episode
    }

    guard !order.isEmpty else {
      return episodes.sorted { lhs, rhs in
        let lhsState = states[playbackStateKey(for: lhs)]
        let rhsState = states[playbackStateKey(for: rhs)]

        if lhsState?.updatedAt != rhsState?.updatedAt {
          return (lhsState?.updatedAt ?? .distantPast) > (rhsState?.updatedAt ?? .distantPast)
        }

        return lhs.pubDate > rhs.pubDate
      }
    }

    let orderedEpisodes = order.compactMap { episodesByKey[$0] }
    let orderedKeys = Set(order)
    let remainingEpisodes = episodes.filter { !orderedKeys.contains(playbackStateKey(for: $0)) }
      .sorted { lhs, rhs in
        let lhsState = states[playbackStateKey(for: lhs)]
        let rhsState = states[playbackStateKey(for: rhs)]

        if lhsState?.updatedAt != rhsState?.updatedAt {
          return (lhsState?.updatedAt ?? .distantPast) > (rhsState?.updatedAt ?? .distantPast)
        }

        return lhs.pubDate > rhs.pubDate
      }

    return orderedEpisodes + remainingEpisodes
  }

  fileprivate func saveInProgressEpisodes(_ episodes: [Episode]) {
    do {
      let data = try JSONEncoder().encode(uniqueEpisodes(episodes))
      UserDefaults.standard.set(data, forKey: UserDefaults.inProgressEpisodesKey)
    } catch let encodeError {
      print("Failed to encode in-progress episodes:", encodeError)
    }
  }

  fileprivate func updateInProgressEpisode(_ episode: Episode, state: EpisodePlaybackState) {
    let cachedEpisodes = fetchInProgressEpisodes()
    var updatedEpisodes = cachedEpisodes.filter { $0 != episode }

    if state.hasResumePosition {
      updatedEpisodes.append(episode)
    }

    if updatedEpisodes != cachedEpisodes {
      saveInProgressEpisodes(updatedEpisodes)
    }
  }

  fileprivate func removeInProgressEpisode(_ episode: Episode) {
    let cachedEpisodes = fetchInProgressEpisodes()
    let updatedEpisodes = cachedEpisodes.filter { $0 != episode }
    if updatedEpisodes != cachedEpisodes {
      saveInProgressEpisodes(updatedEpisodes)
    }
    cleanInProgressEpisodeOrder(for: updatedEpisodes)
  }

  fileprivate func uniqueEpisodes(_ episodes: [Episode]) -> [Episode] {
    episodes.reduce(into: [Episode]()) { result, episode in
      if !result.contains(episode) {
        result.append(episode)
      }
    }
  }

  fileprivate func uniqueKeys(_ keys: [String]) -> [String] {
    keys.reduce(into: [String]()) { result, key in
      if !result.contains(key) {
        result.append(key)
      }
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
