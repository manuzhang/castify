import Foundation
import UserNotifications

final class SettingsViewModel: ObservableObject {

  @Published private(set) var importMessage: String?
  @Published private(set) var isImporting = false
  @Published private(set) var notificationMessage: String?
  @Published private(set) var notificationStatus: UNAuthorizationStatus = .notDetermined
  @Published private(set) var subscriptionCount = 0

  private let podcastsService: PodcastsService
  private let opmlImportService: OPMLImportService
  private let notificationCenter: UNUserNotificationCenter

  init(podcastsService: PodcastsService = PodcastsService(),
       opmlImportService: OPMLImportService = OPMLImportService(),
       notificationCenter: UNUserNotificationCenter = .current()) {
    self.podcastsService = podcastsService
    self.opmlImportService = opmlImportService
    self.notificationCenter = notificationCenter
    refresh()
  }

  var notificationActionTitle: String {
    notificationStatus == .notDetermined ? "Allow Notifications" : "Refresh Status"
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

  func manageNotifications() {
    notificationMessage = nil

    guard notificationStatus == .notDetermined else {
      refreshNotificationStatus()
      notificationMessage = notificationMessage(for: notificationStatus)
      return
    }

    notificationCenter.requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] granted, error in
      DispatchQueue.main.async {
        if let error = error {
          self?.notificationMessage = error.localizedDescription
        } else {
          self?.notificationMessage = granted ? "Notifications are enabled" : "Notifications are disabled"
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
      }
    }
  }

  private func notificationMessage(for status: UNAuthorizationStatus) -> String {
    switch status {
    case .notDetermined:
      return "Notification permission has not been requested"
    case .denied:
      return "Notifications are disabled"
    case .authorized:
      return "Notifications are enabled"
    case .provisional:
      return "Notifications are delivered quietly"
    case .ephemeral:
      return "Notifications are temporarily enabled"
    @unknown default:
      return "Notification status is unknown"
    }
  }
}
