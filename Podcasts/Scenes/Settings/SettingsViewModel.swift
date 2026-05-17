import Combine
import Foundation
import UserNotifications

final class SettingsViewModel: ObservableObject {

  @Published private(set) var importMessage: String?
  @Published private(set) var isImporting = false
  @Published private(set) var notificationStatus: UNAuthorizationStatus = .notDetermined
  @Published private(set) var notificationsEnabled = false
  @Published private(set) var subscriptionCount = 0
  @Published var githubTokenInput = ""
  @Published private(set) var githubTokenSaved = false
  @Published private(set) var githubSyncMessage: String?
  @Published private(set) var githubAutoSyncEnabled = false
  @Published private(set) var githubLastSyncText = ""
  @Published private(set) var autoDownloadEnabled = false
  @Published private(set) var autoDownloadEpisodeLimit = PodcastsService.defaultAutoDownloadEpisodeLimit
  @Published private(set) var autoDownloadWifiOnly = false
  @Published private(set) var downloadedEpisodeCount = 0
  @Published private(set) var storageUsedText = ByteCountFormatter.string(fromByteCount: 0, countStyle: .file)
  @Published private(set) var totalListeningTimeText = ""
  @Published private(set) var finishedEpisodeCount = 0
  @Published private(set) var lastListenedText = ""

  private let podcastsService: PodcastsService
  private let networkingService: NetworkingService
  private let opmlImportService: OPMLImportService
  private let keychainService: KeychainService
  private let autoGitHubSubscriptionSyncService: AutoGitHubSubscriptionSyncService
  private let notificationCenter: UNUserNotificationCenter
  private let eventCenter: NotificationCenter
  private let userDefaults: UserDefaults
  private let localization: LocalizationService
  private var downloadCompleteObserver: NSObjectProtocol?
  private var listeningStatsObserver: NSObjectProtocol?
  private var githubSyncObserver: NSObjectProtocol?
  private var languageObserver: AnyCancellable?

  init(podcastsService: PodcastsService = PodcastsService(),
       networkingService: NetworkingService = NetworkingService(),
       opmlImportService: OPMLImportService = OPMLImportService(),
       keychainService: KeychainService = KeychainService(),
       autoGitHubSubscriptionSyncService: AutoGitHubSubscriptionSyncService = .shared,
       notificationCenter: UNUserNotificationCenter = .current(),
       eventCenter: NotificationCenter = .default,
       userDefaults: UserDefaults = .standard,
       localization: LocalizationService = .shared) {
    self.podcastsService = podcastsService
    self.networkingService = networkingService
    self.opmlImportService = opmlImportService
    self.keychainService = keychainService
    self.autoGitHubSubscriptionSyncService = autoGitHubSubscriptionSyncService
    self.notificationCenter = notificationCenter
    self.eventCenter = eventCenter
    self.userDefaults = userDefaults
    self.localization = localization
    self.notificationsEnabled = userDefaults.bool(forKey: UserDefaults.notificationsEnabledKey)
    self.githubAutoSyncEnabled = userDefaults.bool(forKey: UserDefaults.githubAutoSyncEnabledKey)
    refresh()
    observeDownloads()
    observeListeningStats()
    observeGitHubSync()
    observeLanguageChanges()
  }

  deinit {
    if let downloadCompleteObserver = downloadCompleteObserver {
      eventCenter.removeObserver(downloadCompleteObserver)
    }
    if let listeningStatsObserver = listeningStatsObserver {
      eventCenter.removeObserver(listeningStatsObserver)
    }
    if let githubSyncObserver = githubSyncObserver {
      eventCenter.removeObserver(githubSyncObserver)
    }
    languageObserver?.cancel()
  }

  var notificationStatusMessage: String? {
    guard notificationsEnabled else {
      return nil
    }

    switch notificationStatus {
    case .notDetermined:
      return localization.text(.notificationsNeedPermission)
    case .denied:
      return localization.text(.notificationsBlocked)
    case .authorized, .provisional, .ephemeral:
      return nil
    @unknown default:
      return localization.text(.notificationPermissionUnknown)
    }
  }

  func refresh() {
    subscriptionCount = podcastsService.subscribedPodcasts.count
    refreshGitHubTokenState()
    refreshGitHubLastSync()
    autoDownloadEnabled = podcastsService.autoDownloadEnabled
    autoDownloadEpisodeLimit = podcastsService.autoDownloadEpisodeLimit
    autoDownloadWifiOnly = podcastsService.autoDownloadWifiOnly
    downloadedEpisodeCount = podcastsService.downloadedEpisodeCount()
    refreshListeningStats()
    storageUsedText = ByteCountFormatter.string(
      fromByteCount: podcastsService.downloadedEpisodesStorageSize(),
      countStyle: .file
    )
    refreshNotificationStatus()
  }

  func importOPML(from url: URL) {
    guard !isImporting else {
      return
    }

    isImporting = true
    importMessage = nil

    DispatchQueue.global(qos: .userInitiated).async {
      let shouldStopAccessing = url.startAccessingSecurityScopedResource()
      defer {
        if shouldStopAccessing {
          url.stopAccessingSecurityScopedResource()
        }
      }

      do {
        let data = try Data(contentsOf: url)
        let feeds = try self.opmlImportService.parse(data: data)
        let podcasts = self.opmlImportService.podcasts(from: feeds)

        DispatchQueue.main.async {
          let addedCount = self.podcastsService.addPodcasts(podcasts)
          if addedCount > 0 && self.podcastsService.autoDownloadEnabled {
            self.queueAutoDownloads(for: podcasts)
          }
          self.importMessage = self.message(addedCount: addedCount, totalCount: podcasts.count)
          self.isImporting = false
          self.refresh()
        }
      } catch {
        DispatchQueue.main.async {
          self.importMessage = error.localizedDescription
          self.isImporting = false
          self.refresh()
        }
      }
    }
  }

  func saveGitHubToken() {
    let token = githubTokenInput.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !token.isEmpty else {
      githubSyncMessage = localization.text(.githubTokenRequired)
      return
    }

    do {
      try keychainService.saveToken(token)
      githubTokenInput = ""
      githubTokenSaved = true
      setGitHubAutoSyncEnabled(true)
      githubSyncMessage = localization.text(.githubTokenSaved)
    } catch {
      githubSyncMessage = error.localizedDescription
      refreshGitHubTokenState()
    }
  }

  func setGitHubAutoSyncEnabled(_ enabled: Bool) {
    guard githubTokenSaved || !enabled else {
      githubSyncMessage = localization.text(.githubTokenRequired)
      return
    }

    githubAutoSyncEnabled = enabled
    userDefaults.set(enabled, forKey: UserDefaults.githubAutoSyncEnabledKey)

    if enabled {
      autoGitHubSubscriptionSyncService.syncSoon()
    }
  }

  func setNotificationsEnabled(_ enabled: Bool) {
    guard enabled else {
      saveNotificationsEnabled(false)
      notificationCenter.removeAllPendingNotificationRequests()
      notificationCenter.removeAllDeliveredNotifications()
      return
    }

    enableNotifications()
  }

  func setAutoDownloadEnabled(_ enabled: Bool) {
    podcastsService.autoDownloadEnabled = enabled
    autoDownloadEnabled = enabled

    guard enabled else {
      return
    }

    queueAutoDownloads(for: podcastsService.subscribedPodcasts)
  }

  func setAutoDownloadWifiOnly(_ wifiOnly: Bool) {
    podcastsService.autoDownloadWifiOnly = wifiOnly
    autoDownloadWifiOnly = wifiOnly

    guard autoDownloadEnabled else {
      return
    }

    queueAutoDownloads(for: podcastsService.subscribedPodcasts)
  }

  func setAutoDownloadEpisodeLimit(_ limit: Int) {
    podcastsService.autoDownloadEpisodeLimit = limit
    autoDownloadEpisodeLimit = podcastsService.autoDownloadEpisodeLimit

    guard autoDownloadEnabled else {
      return
    }

    queueAutoDownloads(for: podcastsService.subscribedPodcasts)
  }

  func clearDownloads() {
    podcastsService.clearDownloadedEpisodes()
    refresh()
  }

  private func enableNotifications() {
    switch notificationStatus {
    case .notDetermined:
      requestNotificationAuthorization()
    case .denied:
      saveNotificationsEnabled(false)
    case .authorized, .provisional, .ephemeral:
      saveNotificationsEnabled(true)
    @unknown default:
      saveNotificationsEnabled(false)
    }
  }

  private func requestNotificationAuthorization() {
    notificationCenter.requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] granted, error in
      DispatchQueue.main.async {
        if let error = error {
          print("Failed to request notifications:", error)
        } else {
          self?.saveNotificationsEnabled(granted)
        }

        self?.refreshNotificationStatus()
      }
    }
  }

  private func message(addedCount: Int, totalCount: Int) -> String {
    localization.importMessage(addedCount: addedCount, totalCount: totalCount)
  }

  private func refreshNotificationStatus() {
    notificationCenter.getNotificationSettings { [weak self] settings in
      DispatchQueue.main.async {
        self?.notificationStatus = settings.authorizationStatus
        if settings.authorizationStatus == .denied {
          self?.saveNotificationsEnabled(false)
        }
      }
    }
  }

  private func refreshGitHubTokenState() {
    githubTokenSaved = (try? keychainService.loadToken()) != nil
    if !githubTokenSaved && githubAutoSyncEnabled {
      setGitHubAutoSyncEnabled(false)
    }
  }

  private func saveNotificationsEnabled(_ enabled: Bool) {
    notificationsEnabled = enabled
    userDefaults.set(enabled, forKey: UserDefaults.notificationsEnabledKey)
  }

  private func refreshListeningStats() {
    let stats = podcastsService.listeningStats
    totalListeningTimeText = localization.listeningDuration(seconds: stats.totalListeningTime)
    finishedEpisodeCount = stats.finishedEpisodeCount
    lastListenedText = stats.lastListenedAt?.formatMedium ?? localization.text(.never)
  }

  private func refreshGitHubLastSync() {
    let lastSyncAt = userDefaults.object(forKey: UserDefaults.githubLastSyncAtKey) as? Date
    githubLastSyncText = lastSyncAt?.formatMediumDateTime ?? localization.text(.never)
  }

  private func queueAutoDownloads(for podcasts: [Podcast]) {
    let limit = podcastsService.autoDownloadEpisodeLimit
    podcasts.forEach { podcast in
      networkingService.autoDownloadEpisodes(for: podcast, limit: limit) { [weak self] _ in
        self?.refresh()
      }
    }
  }

  private func observeDownloads() {
    downloadCompleteObserver = eventCenter.addObserver(
      forName: .downloadComplete,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      self?.refresh()
    }
  }

  private func observeListeningStats() {
    listeningStatsObserver = eventCenter.addObserver(
      forName: .listeningStatsDidChange,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      self?.refreshListeningStats()
    }
  }

  private func observeGitHubSync() {
    githubSyncObserver = eventCenter.addObserver(
      forName: .githubSubscriptionSyncDidComplete,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      self?.refreshGitHubLastSync()
    }
  }

  private func observeLanguageChanges() {
    languageObserver = localization.$language
      .dropFirst()
      .sink { [weak self] _ in
        DispatchQueue.main.async {
          self?.refreshListeningStats()
          self?.refreshGitHubLastSync()
        }
      }
  }
}
