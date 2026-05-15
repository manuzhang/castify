import Foundation

final class AutoGitHubSubscriptionSyncService {

  static let shared = AutoGitHubSubscriptionSyncService()

  private let podcastsService: PodcastsService
  private let opmlExportService: OPMLExportService
  private let githubSyncService: GitHubSyncService
  private let keychainService: KeychainService
  private let userDefaults: UserDefaults
  private let queue = DispatchQueue(label: "com.castify.github-auto-sync")
  private var observer: NSObjectProtocol?
  private var pendingWorkItem: DispatchWorkItem?
  private var syncing = false
  private var syncPendingAfterCurrentRun = false

  init(podcastsService: PodcastsService = PodcastsService(),
       opmlExportService: OPMLExportService = OPMLExportService(),
       githubSyncService: GitHubSyncService = GitHubSyncService(),
       keychainService: KeychainService = KeychainService(),
       userDefaults: UserDefaults = .standard) {
    self.podcastsService = podcastsService
    self.opmlExportService = opmlExportService
    self.githubSyncService = githubSyncService
    self.keychainService = keychainService
    self.userDefaults = userDefaults
  }

  func start() {
    guard observer == nil else {
      return
    }

    observer = NotificationCenter.default.addObserver(
      forName: .subscribedPodcastsDidChange,
      object: nil,
      queue: nil
    ) { [weak self] _ in
      self?.scheduleSync()
    }
  }

  func stop() {
    if let observer = observer {
      NotificationCenter.default.removeObserver(observer)
    }

    observer = nil
    pendingWorkItem?.cancel()
    pendingWorkItem = nil
  }

  func syncSoon() {
    scheduleSync()
  }

  private func scheduleSync() {
    queue.async {
      guard self.userDefaults.bool(forKey: UserDefaults.githubAutoSyncEnabledKey) else {
        self.pendingWorkItem?.cancel()
        self.pendingWorkItem = nil
        return
      }

      self.pendingWorkItem?.cancel()

      let workItem = DispatchWorkItem { [weak self] in
        self?.syncNow()
      }
      self.pendingWorkItem = workItem
      self.queue.asyncAfter(deadline: .now() + 2, execute: workItem)
    }
  }

  private func syncNow() {
    guard userDefaults.bool(forKey: UserDefaults.githubAutoSyncEnabledKey) else {
      return
    }

    if syncing {
      syncPendingAfterCurrentRun = true
      return
    }

    guard let token = try? keychainService.loadToken(), !token.isEmpty else {
      return
    }

    let opmlData: Data
    do {
      opmlData = try opmlExportService.export(podcasts: podcastsService.subscribedPodcasts)
    } catch {
      print("Automatic GitHub subscription sync skipped:", error.localizedDescription)
      return
    }

    syncing = true
    githubSyncService.sync(opmlData: opmlData, token: token) { [weak self] result in
      guard let self = self else {
        return
      }

      self.queue.async {
        self.syncing = false

        switch result {
        case .success:
          print("Automatic GitHub subscription sync completed")
        case .failure(let error):
          print("Automatic GitHub subscription sync failed:", error.localizedDescription)
        }

        if self.syncPendingAfterCurrentRun {
          self.syncPendingAfterCurrentRun = false
          self.scheduleSync()
        }
      }
    }
  }
}
