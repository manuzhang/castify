import CryptoKit
import Foundation
import UserNotifications

protocol EpisodeNotificationCenter {
  func authorizationStatus(_ completion: @escaping (UNAuthorizationStatus) -> Void)
  func add(_ request: UNNotificationRequest, completion: @escaping (Error?) -> Void)
  func pendingRequests(_ completion: @escaping ([UNNotificationRequest]) -> Void)
  func removePending(prefix: String)
  func removePending(identifier: String)
}

struct LocalEpisodeNotificationCenter: EpisodeNotificationCenter {
  private let center = UNUserNotificationCenter.current()

  func authorizationStatus(_ completion: @escaping (UNAuthorizationStatus) -> Void) {
    center.getNotificationSettings { completion($0.authorizationStatus) }
  }

  func add(_ request: UNNotificationRequest, completion: @escaping (Error?) -> Void) {
    center.add(request, withCompletionHandler: completion)
  }

  func pendingRequests(_ completion: @escaping ([UNNotificationRequest]) -> Void) {
    center.getPendingNotificationRequests(completionHandler: completion)
  }

  func removePending(prefix: String) {
    // The prefix includes the old preference generation. A delayed lookup must
    // never remove alerts belonging to a subsequent opt-in.
    center.getPendingNotificationRequests { requests in
      self.center.removePendingNotificationRequests(withIdentifiers:
        requests.filter { $0.identifier.hasPrefix(prefix) }.map { $0.identifier })
    }
  }

  func removePending(identifier: String) {
    center.removePendingNotificationRequests(withIdentifiers: [identifier])
  }
}

/// Main-thread preferences and at-most-once local alerts from successful RSS refreshes.
final class PodcastEpisodeNotificationService {
  static let shared = PodcastEpisodeNotificationService()

  struct Refresh {
    fileprivate let feed: String
    fileprivate let generation: UUID
    fileprivate let sequence: Int
  }

  private struct Preference: Codable {
    var enabled = false
    var generation = UUID()
    var seen = Set<String>()
    var cutoff = Date.distantPast
    var hasBaseline = false
  }

  private struct Store: Codable {
    var version = 1
    var globalEnabled: Bool
    var preferences = [String: Preference]()
  }

  private let defaults: UserDefaults
  private let center: EpisodeNotificationCenter
  private let subscriptions: () -> [Podcast]
  private let now: () -> Date
  private let localization: LocalizationService
  private var store: Store
  private var sequence = 0
  private var latestRefresh = [String: Int]()

  init(userDefaults: UserDefaults = .standard,
       center: EpisodeNotificationCenter = LocalEpisodeNotificationCenter(),
       subscriptions: @escaping () -> [Podcast] = { PodcastsService().subscribedPodcasts },
       now: @escaping () -> Date = Date.init,
       localization: LocalizationService = .shared) {
    defaults = userDefaults
    self.center = center
    self.subscriptions = subscriptions
    self.now = now
    self.localization = localization
    let savedData = userDefaults.data(forKey: UserDefaults.podcastNotificationPreferencesKey)
    let saved = savedData.flatMap { try? JSONDecoder().decode(Store.self, from: $0) }
    if let saved = saved, saved.version == 1 {
      store = saved
    } else {
      store = Store(globalEnabled: userDefaults.bool(forKey: UserDefaults.notificationsEnabledKey))
    }
    // Prune legacy disabled records as well as removed subscriptions once.
    for feed in Array(store.preferences.keys) where !isSubscribed(feed) || store.preferences[feed]?.enabled != true {
      disable(feed)
    }
    globalPreferenceDidChange()
    if savedData != nil && saved?.version != 1 { cancelDiscardedStoreRequests() }
  }

  private func cancelDiscardedStoreRequests() {
    // The discarded generations cannot be decoded. Inspect only app-owned
    // requests, then recheck current preferences on main so a delayed lookup
    // cannot cancel alerts from a new opt-in during recovery.
    center.pendingRequests { requests in
      Self.onMain {
        for request in requests where request.identifier.hasPrefix("castify.episodes.") && !self.shouldPresent(request) {
          self.center.removePending(identifier: request.identifier)
        }
        self.save()
      }
    }
  }

  func isEnabled(for podcast: Podcast) -> Bool {
    guard let subscription = subscription(matching: podcast) else { return false }
    return store.preferences[Self.feedKey(subscription.feedUrl)]?.enabled ?? false
  }

  func setEnabled(_ enabled: Bool, for podcast: Podcast) {
    // Browse may return a changed URL for the same track ID. Use the saved
    // subscription's feed so both screens control the same refresh generation.
    guard let subscription = subscription(matching: podcast) else { return }
    let feed = Self.feedKey(subscription.feedUrl)
    guard !feed.isEmpty else { return }
    guard enabled else { disable(feed); return }
    guard store.preferences[feed]?.enabled != true else { return }
    if let previous = store.preferences[feed] {
      center.removePending(prefix: prefix(feed: feed, generation: previous.generation))
    }
    // Each new opt-in needs a fresh network snapshot, even if the screen already
    // has cached episodes. Neither toggling nor migration requests permission.
    store.preferences[feed] = Preference(enabled: enabled, cutoff: now())
    latestRefresh.removeValue(forKey: feed)
    save()
  }

  func subscriptionRemoved(_ podcast: Podcast) {
    disable(Self.feedKey(podcast.feedUrl))
  }

  func globalPreferenceDidChange() {
    let enabled = defaults.bool(forKey: UserDefaults.notificationsEnabledKey)
    guard enabled != store.globalEnabled else { return }
    store.globalEnabled = enabled
    for feed in Array(store.preferences.keys) {
      guard let previous = store.preferences[feed] else { continue }
      center.removePending(prefix: prefix(feed: feed, generation: previous.generation))
      store.preferences[feed] = Preference(enabled: previous.enabled, cutoff: now())
    }
    latestRefresh.removeAll()
    save()
  }

  func beginRefresh(feedURL: String) -> Refresh? {
    globalPreferenceDidChange()
    let feed = Self.feedKey(feedURL)
    guard isSubscribed(feed), let preference = store.preferences[feed], preference.enabled else { return nil }
    sequence += 1
    latestRefresh[feed] = sequence
    return Refresh(feed: feed, generation: preference.generation, sequence: sequence)
  }

  /// Failed refreshes do not call this method, so cannot clear a baseline.
  func completeRefresh(_ refresh: Refresh?, episodes: [Episode]) {
    guard let refresh = refresh else { return }
    globalPreferenceDidChange()
    guard isCurrent(refresh), var preference = store.preferences[refresh.feed] else { return }
    let timestamp = now()
    var candidates = [Episode]()
    for episode in episodes {
      guard let identity = Self.identity(episode) else { continue }
      let inserted = preference.seen.insert(identity).inserted
      if inserted && preference.hasBaseline, let publishedAt = episode.notificationPublicationDate,
         publishedAt > preference.cutoff && publishedAt <= timestamp {
        candidates.append(episode)
      }
    }
    preference.hasBaseline = true
    preference.cutoff = max(preference.cutoff, timestamp)
    store.preferences[refresh.feed] = preference
    // Persist discovery before any asynchronous API call. Denial, errors or a
    // process exit must not replay these episodes on a later refresh.
    guard save(), store.globalEnabled, !candidates.isEmpty else { return }
    guard let newest = candidates.max(by: { $0.pubDate < $1.pubDate }) else { return }
    let identities = candidates.compactMap(Self.identity).sorted().joined(separator: "\n")
    let identifier = prefix(feed: refresh.feed, generation: refresh.generation) + Self.digest(identities)
    center.authorizationStatus { [weak self] status in
      Self.onMain {
        guard let self = self else { return }
        self.globalPreferenceDidChange()
        guard self.isCurrent(refresh), self.store.globalEnabled,
              Self.allowsAlerts(status),
              let podcast = self.subscriptions().first(where: { Self.feedKey($0.feedUrl) == refresh.feed }) else { return }
        let content = UNMutableNotificationContent()
        content.title = podcast.trackName
        content.body = candidates.count == 1 ? newest.title : String(format:
          self.localization.text(.newEpisodeAlertBody), candidates.count, newest.title)
        content.sound = .default
        content.userInfo = ["feedURL": refresh.feed]
        let request = UNNotificationRequest(identifier: identifier, content: content,
          trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false))
        self.center.add(request) { [weak self] error in
          Self.onMain {
            guard let self = self else { return }
            self.globalPreferenceDidChange()
            // add() may finish after a disable/unsubscribe. Cancel its own old
            // identifier, rather than touching any replacement-generation alert.
            if error != nil || !self.isEligible(refresh) || !self.store.globalEnabled {
              self.center.removePending(identifier: identifier)
            }
          }
        }
      }
    }
  }

  func shouldPresent(_ request: UNNotificationRequest) -> Bool {
    globalPreferenceDidChange()
    guard store.globalEnabled, let feed = request.content.userInfo["feedURL"] as? String,
          isSubscribed(feed), let preference = store.preferences[feed], preference.enabled else { return false }
    return request.identifier.hasPrefix(prefix(feed: feed, generation: preference.generation))
  }

  static func identity(_ episode: Episode) -> String? {
    if let guid = episode.guid?.trimmingCharacters(in: .whitespacesAndNewlines), !guid.isEmpty {
      return digest("guid:" + guid)
    }
    let enclosure = episode.streamUrl.trimmingCharacters(in: .whitespacesAndNewlines)
    if !enclosure.isEmpty { return digest("url:" + enclosure) }
    guard let publishedAt = episode.notificationPublicationDate, !episode.title.isEmpty else { return nil }
    return digest("metadata:" + String(publishedAt.timeIntervalSince1970) + "\n" + episode.title + "\n" + episode.author)
  }

  private func isCurrent(_ refresh: Refresh) -> Bool {
    isEligible(refresh) && latestRefresh[refresh.feed] == refresh.sequence
  }

  private func isEligible(_ refresh: Refresh) -> Bool {
    isSubscribed(refresh.feed) && store.preferences[refresh.feed]?.enabled == true &&
      store.preferences[refresh.feed]?.generation == refresh.generation
  }

  private func subscription(matching podcast: Podcast) -> Podcast? {
    subscriptions().first { PodcastsService.matches($0, podcast) }
  }

  private func isSubscribed(_ feed: String) -> Bool {
    subscriptions().contains { Self.feedKey($0.feedUrl) == feed }
  }

  private func disable(_ feed: String) {
    guard let previous = store.preferences[feed] else { return }
    center.removePending(prefix: prefix(feed: feed, generation: previous.generation))
    store.preferences.removeValue(forKey: feed)
    latestRefresh.removeValue(forKey: feed)
    save()
  }

  @discardableResult
  private func save() -> Bool {
    guard let data = try? JSONEncoder().encode(store) else { return false }
    defaults.set(data, forKey: UserDefaults.podcastNotificationPreferencesKey)
    return true
  }

  private func prefix(feed: String, generation: UUID) -> String {
    "castify.episodes." + Self.digest(feed) + "." + generation.uuidString + "."
  }

  private static func feedKey(_ url: String) -> String { PodcastsService.normalizedFeedUrl(url) }
  private static func digest(_ value: String) -> String {
    SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
  }

  private static func allowsAlerts(_ status: UNAuthorizationStatus) -> Bool {
    if status == .authorized || status == .provisional { return true }
    if #available(iOS 14.0, *) { return status == .ephemeral }
    return false
  }

  private static func onMain(_ action: @escaping () -> Void) {
    if Thread.isMainThread { action() } else { DispatchQueue.main.async(execute: action) }
  }
}
