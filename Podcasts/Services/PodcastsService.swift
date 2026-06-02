import Foundation

struct EpisodePlaybackState: Codable, Equatable {
  static let minimumResumePosition: TimeInterval = 5

  let position: TimeInterval
  let duration: TimeInterval
  let played: Bool
  let starred: Bool
  let updatedAt: Date

  init(position: TimeInterval,
       duration: TimeInterval,
       played: Bool,
       starred: Bool = false,
       updatedAt: Date = Date()) {
    self.position = position
    self.duration = duration
    self.played = played
    self.starred = starred
    self.updatedAt = updatedAt
  }

  enum CodingKeys: String, CodingKey {
    case position
    case duration
    case played
    case starred
    case updatedAt
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    position = try container.decode(TimeInterval.self, forKey: .position)
    duration = try container.decode(TimeInterval.self, forKey: .duration)
    played = try container.decode(Bool.self, forKey: .played)
    starred = try container.decodeIfPresent(Bool.self, forKey: .starred) ?? false
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

struct ListeningStats: Codable, Equatable {
  static let empty = ListeningStats(
    totalListeningTime: 0,
    finishedEpisodeCount: 0,
    lastListenedAt: nil
  )

  var totalListeningTime: TimeInterval
  var finishedEpisodeCount: Int
  var lastListenedAt: Date?
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

  var listeningStats: ListeningStats {
    fetchListeningStats()
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
    return saveSubscribedPodcasts(podcasts, failureMessage: "Failed to add podcast: " + podcast.trackName)
  }

  @discardableResult
  func addPodcasts(_ podcasts: [Podcast]) -> Int {
    var savedPodcasts = subscribedPodcasts
    var addedCount = 0

    podcasts.forEach { podcast in
      guard !savedPodcasts.contains(where: { matches($0, podcast) }) else {
        return
      }

      savedPodcasts.append(podcast)
      addedCount += 1
    }

    guard addedCount > 0 else {
      return 0
    }

    return saveSubscribedPodcasts(savedPodcasts, failureMessage: "Failed to add podcasts") ? addedCount : 0
  }

  func deletePodcast(_ podcast: Podcast) {
    let podcasts = subscribedPodcasts
    let filteredPodcasts = podcasts.filter { pod -> Bool in
      !matches(pod, podcast)
    }

    guard filteredPodcasts.count != podcasts.count else {
      return
    }

    _ = saveSubscribedPodcasts(filteredPodcasts, failureMessage: "Failed to delete podcast: " + podcast.trackName)
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

  func starredEpisodes() -> [Episode] {
    let cachedEpisodes = fetchStarredEpisodes()
    let states = episodePlaybackStates()
    let filteredEpisodes = uniqueEpisodes(cachedEpisodes).filter { episode in
      states[playbackStateKey(for: episode)]?.starred == true
    }

    if filteredEpisodes.count != cachedEpisodes.count {
      saveStarredEpisodes(filteredEpisodes)
    }

    return orderedStarredEpisodes(filteredEpisodes, states: states)
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

  func cacheStarredEpisodes(_ episodes: [Episode]) {
    let states = episodePlaybackStates()
    let starredEpisodes = episodes.filter { episode in
      states[playbackStateKey(for: episode)]?.starred == true
    }
    guard !starredEpisodes.isEmpty else {
      return
    }

    var cachedEpisodes = fetchStarredEpisodes()
    starredEpisodes.forEach { episode in
      cachedEpisodes.removeAll(where: { $0 == episode })
      cachedEpisodes.append(episode)
    }
    saveStarredEpisodes(cachedEpisodes)
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

  func isEpisodeStarred(_ episode: Episode) -> Bool {
    playbackState(for: episode)?.starred == true
  }

  func savePlaybackPosition(for episode: Episode,
                            elapsedTime: TimeInterval,
                            duration: TimeInterval) {
    guard duration > 0 else {
      return
    }

    var states = episodePlaybackStates()
    let key = playbackStateKey(for: episode)
    let existingState = states[key]
    let clampedPosition = min(max(elapsedTime, 0), duration)
    let played = existingState?.played == true || isPlayed(position: clampedPosition, duration: duration)
    let resumablePosition = played || clampedPosition < EpisodePlaybackState.minimumResumePosition ? 0 : clampedPosition
    let state = EpisodePlaybackState(
      position: resumablePosition,
      duration: duration,
      played: played,
      starred: existingState?.starred == true
    )

    states[key] = state
    saveEpisodePlaybackStates(states)
    updateStarredEpisodeIfNeeded(episode, state: state)
    updateInProgressEpisode(episode, state: state)
  }

  func recordListeningTime(_ seconds: TimeInterval) {
    guard seconds.isFinite && !seconds.isNaN && seconds > 0 else {
      return
    }

    var stats = fetchListeningStats()
    stats.totalListeningTime += seconds
    stats.lastListenedAt = Date()
    saveListeningStats(stats)
  }

  func recordFinishedEpisode() {
    var stats = fetchListeningStats()
    stats.finishedEpisodeCount += 1
    stats.lastListenedAt = Date()
    saveListeningStats(stats)
  }

  func markEpisodePlayed(_ episode: Episode) {
    var states = episodePlaybackStates()
    let key = playbackStateKey(for: episode)
    let existingState = states[key]
    let duration = existingState?.duration ?? episode.duration ?? 0
    states[key] = EpisodePlaybackState(
      position: 0,
      duration: duration,
      played: true,
      starred: existingState?.starred == true
    )
    saveEpisodePlaybackStates(states)
    updateStarredEpisodeIfNeeded(episode, state: states[key])
    removeInProgressEpisode(episode)
    NotificationCenter.default.post(name: .episodePlaybackStateDidChange, object: self)
  }

  func markEpisodeUnplayed(_ episode: Episode) {
    var states = episodePlaybackStates()
    let key = playbackStateKey(for: episode)
    if let existingState = states[key], existingState.starred {
      states[key] = EpisodePlaybackState(
        position: 0,
        duration: existingState.duration,
        played: false,
        starred: true
      )
    } else {
      states.removeValue(forKey: key)
    }
    saveEpisodePlaybackStates(states)
    updateStarredEpisodeIfNeeded(episode, state: states[key])
    removeInProgressEpisode(episode)
    NotificationCenter.default.post(name: .episodePlaybackStateDidChange, object: self)
  }

  func setEpisodeStarred(_ episode: Episode, starred: Bool) {
    var states = episodePlaybackStates()
    let key = playbackStateKey(for: episode)
    let existingState = states[key]
    let state = EpisodePlaybackState(
      position: existingState?.position ?? 0,
      duration: existingState?.duration ?? episode.duration ?? 0,
      played: existingState?.played == true,
      starred: starred
    )

    if shouldPersist(state) {
      states[key] = state
    } else {
      states.removeValue(forKey: key)
    }

    saveEpisodePlaybackStates(states)
    updateStarredEpisodeIfNeeded(episode, state: state)

    if state.hasResumePosition {
      updateInProgressEpisode(episode, state: state)
    } else {
      removeInProgressEpisode(episode)
    }

    NotificationCenter.default.post(name: .episodePlaybackStateDidChange, object: self)
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

  fileprivate func fetchStarredEpisodes() -> [Episode] {
    guard let data = UserDefaults.standard.data(forKey: UserDefaults.starredEpisodesKey) else {
      return []
    }

    do {
      return try JSONDecoder().decode([Episode].self, from: data)
    } catch let decodeError {
      print("Failed to decode starred episodes:", decodeError)
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

  fileprivate func fetchListeningStats() -> ListeningStats {
    guard let data = UserDefaults.standard.data(forKey: UserDefaults.listeningStatsKey) else {
      return .empty
    }

    do {
      return try JSONDecoder().decode(ListeningStats.self, from: data)
    } catch let decodeError {
      print("Failed to decode listening stats:", decodeError)
      return .empty
    }
  }

  fileprivate func saveListeningStats(_ stats: ListeningStats) {
    do {
      let data = try JSONEncoder().encode(stats)
      UserDefaults.standard.set(data, forKey: UserDefaults.listeningStatsKey)
      NotificationCenter.default.post(name: .listeningStatsDidChange, object: self)
    } catch let encodeError {
      print("Failed to encode listening stats:", encodeError)
    }
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

  fileprivate func orderedStarredEpisodes(
    _ episodes: [Episode],
    states: [String: EpisodePlaybackState]
  ) -> [Episode] {
    episodes.sorted { lhs, rhs in
      let lhsState = states[playbackStateKey(for: lhs)]
      let rhsState = states[playbackStateKey(for: rhs)]

      if lhsState?.updatedAt != rhsState?.updatedAt {
        return (lhsState?.updatedAt ?? .distantPast) > (rhsState?.updatedAt ?? .distantPast)
      }

      return lhs.pubDate > rhs.pubDate
    }
  }

  fileprivate func saveInProgressEpisodes(_ episodes: [Episode]) {
    do {
      let data = try JSONEncoder().encode(uniqueEpisodes(episodes))
      UserDefaults.standard.set(data, forKey: UserDefaults.inProgressEpisodesKey)
    } catch let encodeError {
      print("Failed to encode in-progress episodes:", encodeError)
    }
  }

  fileprivate func saveStarredEpisodes(_ episodes: [Episode]) {
    do {
      let data = try JSONEncoder().encode(uniqueEpisodes(episodes))
      UserDefaults.standard.set(data, forKey: UserDefaults.starredEpisodesKey)
    } catch let encodeError {
      print("Failed to encode starred episodes:", encodeError)
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

  fileprivate func updateStarredEpisodeIfNeeded(_ episode: Episode, state: EpisodePlaybackState?) {
    guard state?.starred == true else {
      removeStarredEpisode(episode)
      return
    }

    let cachedEpisodes = fetchStarredEpisodes()
    var updatedEpisodes = cachedEpisodes.filter { $0 != episode }
    updatedEpisodes.append(episode)

    if updatedEpisodes != cachedEpisodes {
      saveStarredEpisodes(updatedEpisodes)
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

  fileprivate func removeStarredEpisode(_ episode: Episode) {
    let cachedEpisodes = fetchStarredEpisodes()
    let updatedEpisodes = cachedEpisodes.filter { $0 != episode }
    if updatedEpisodes != cachedEpisodes {
      saveStarredEpisodes(updatedEpisodes)
    }
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

  fileprivate func shouldPersist(_ state: EpisodePlaybackState) -> Bool {
    state.played || state.starred || state.hasResumePosition
  }

  private func saveSubscribedPodcasts(_ podcasts: [Podcast], failureMessage: String) -> Bool {
    do {
      let data = try JSONEncoder().encode(podcasts)
      UserDefaults.standard.set(data, forKey: UserDefaults.subscribedPodcastsKey)
      NotificationCenter.default.post(name: .subscribedPodcastsDidChange, object: self)
      return true
    } catch let error {
      print(failureMessage, error)
      return false
    }
  }

}
