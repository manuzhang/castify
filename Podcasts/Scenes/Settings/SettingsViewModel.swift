import Foundation
import UserNotifications

final class SettingsViewModel: ObservableObject {

  @Published private(set) var importMessage: String?
  @Published private(set) var isImporting = false
  @Published private(set) var notificationStatus: UNAuthorizationStatus = .notDetermined
  @Published private(set) var notificationsEnabled = false
  @Published private(set) var subscriptionCount = 0
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
  private let notificationCenter: UNUserNotificationCenter
  private let eventCenter: NotificationCenter
  private let userDefaults: UserDefaults
  private let localization: LocalizationService
  private var downloadCompleteObserver: NSObjectProtocol?
  private var listeningStatsObserver: NSObjectProtocol?

  init(podcastsService: PodcastsService = PodcastsService(),
       networkingService: NetworkingService = NetworkingService(),
       opmlImportService: OPMLImportService = OPMLImportService(),
       notificationCenter: UNUserNotificationCenter = .current(),
       eventCenter: NotificationCenter = .default,
       userDefaults: UserDefaults = .standard,
       localization: LocalizationService = .shared) {
    self.podcastsService = podcastsService
    self.networkingService = networkingService
    self.opmlImportService = opmlImportService
    self.notificationCenter = notificationCenter
    self.eventCenter = eventCenter
    self.userDefaults = userDefaults
    self.localization = localization
    self.notificationsEnabled = userDefaults.bool(forKey: UserDefaults.notificationsEnabledKey)
    refresh()
    observeDownloads()
    observeListeningStats()
  }

  deinit {
    if let downloadCompleteObserver = downloadCompleteObserver {
      eventCenter.removeObserver(downloadCompleteObserver)
    }
    if let listeningStatsObserver = listeningStatsObserver {
      eventCenter.removeObserver(listeningStatsObserver)
    }
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
}
