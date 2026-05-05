import Foundation
import UserNotifications

final class SettingsViewModel: ObservableObject {

  @Published private(set) var importMessage: String?
  @Published private(set) var isImporting = false
  @Published private(set) var notificationStatus: UNAuthorizationStatus = .notDetermined
  @Published private(set) var notificationsEnabled = false
  @Published private(set) var subscriptionCount = 0

  private let podcastsService: PodcastsService
  private let opmlImportService: OPMLImportService
  private let notificationCenter: UNUserNotificationCenter
  private let userDefaults: UserDefaults
  private let localization: LocalizationService

  init(podcastsService: PodcastsService = PodcastsService(),
       opmlImportService: OPMLImportService = OPMLImportService(),
       notificationCenter: UNUserNotificationCenter = .current(),
       userDefaults: UserDefaults = .standard,
       localization: LocalizationService = .shared) {
    self.podcastsService = podcastsService
    self.opmlImportService = opmlImportService
    self.notificationCenter = notificationCenter
    self.userDefaults = userDefaults
    self.localization = localization
    self.notificationsEnabled = userDefaults.bool(forKey: UserDefaults.notificationsEnabledKey)
    refresh()
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
    guard enabled else {
      saveNotificationsEnabled(false)
      notificationCenter.removeAllPendingNotificationRequests()
      notificationCenter.removeAllDeliveredNotifications()
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
}
