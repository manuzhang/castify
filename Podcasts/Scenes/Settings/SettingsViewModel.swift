import Foundation
import UserNotifications

final class SettingsViewModel: ObservableObject {

  @Published private(set) var importMessage: String?
  @Published private(set) var isImporting = false
  @Published private(set) var notificationMessage: String?
  @Published private(set) var notificationStatus: UNAuthorizationStatus = .notDetermined
  @Published private(set) var notificationsEnabled = false
  @Published private(set) var subscriptionCount = 0

  private let podcastsService: PodcastsService
  private let opmlImportService: OPMLImportService
  private let notificationCenter: UNUserNotificationCenter
  private let userDefaults: UserDefaults

  init(podcastsService: PodcastsService = PodcastsService(),
       opmlImportService: OPMLImportService = OPMLImportService(),
       notificationCenter: UNUserNotificationCenter = .current(),
       userDefaults: UserDefaults = .standard) {
    self.podcastsService = podcastsService
    self.opmlImportService = opmlImportService
    self.notificationCenter = notificationCenter
    self.userDefaults = userDefaults
    self.notificationsEnabled = userDefaults.bool(forKey: UserDefaults.notificationsEnabledKey)
    refresh()
  }

  var notificationStatusTitle: String {
    switch notificationStatus {
    case .notDetermined:
      return "Not Set"
    case .denied:
      return "Off"
    case .authorized:
      return "On"
    case .provisional:
      return "Quiet"
    case .ephemeral:
      return "Temporary"
    @unknown default:
      return "Unknown"
    }
  }

  func refresh() {
    subscriptionCount = podcastsService.subscribedPodcasts.count
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
    notificationMessage = nil

    guard enabled else {
      saveNotificationsEnabled(false)
      notificationCenter.removeAllPendingNotificationRequests()
      notificationCenter.removeAllDeliveredNotifications()
      notificationMessage = "Notifications are disabled in Castify"
      return
    }

    enableNotifications()
  }

  private func enableNotifications() {
    switch notificationStatus {
    case .notDetermined:
      requestNotificationAuthorization()
    case .denied:
      saveNotificationsEnabled(false)
      notificationMessage = "System notification permission is off"
    case .authorized, .provisional, .ephemeral:
      saveNotificationsEnabled(true)
      notificationMessage = "Notifications are enabled in Castify"
    @unknown default:
      saveNotificationsEnabled(false)
      notificationMessage = "Notification status is unknown"
    }
  }

  private func requestNotificationAuthorization() {
    notificationCenter.requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] granted, error in
      DispatchQueue.main.async {
        if let error = error {
          self?.notificationMessage = error.localizedDescription
        } else {
          self?.saveNotificationsEnabled(granted)
          self?.notificationMessage = granted ? "Notifications are enabled in Castify" : "Notifications are disabled"
        }

        self?.refreshNotificationStatus()
      }
    }
  }

  private func message(addedCount: Int, totalCount: Int) -> String {
    if totalCount == 0 {
      return "No podcast feeds found"
    }

    if addedCount == 0 {
      return "All \(totalCount) podcasts were already subscribed"
    }

    return "Imported \(addedCount) of \(totalCount) podcasts"
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
}
