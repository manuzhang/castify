import Foundation

final class SettingsViewModel: ObservableObject {

  @Published private(set) var importMessage: String?
  @Published private(set) var isImporting = false
  @Published private(set) var subscriptionCount = 0

  private let podcastsService: PodcastsService
  private let opmlImportService: OPMLImportService

  init(podcastsService: PodcastsService = PodcastsService(),
       opmlImportService: OPMLImportService = OPMLImportService()) {
    self.podcastsService = podcastsService
    self.opmlImportService = opmlImportService
    refresh()
  }

  func refresh() {
    subscriptionCount = podcastsService.subscribedPodcasts.count
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

  private func message(addedCount: Int, totalCount: Int) -> String {
    if totalCount == 0 {
      return "No podcast feeds found"
    }

    if addedCount == 0 {
      return "All \(totalCount) podcasts were already subscribed"
    }

    return "Imported \(addedCount) of \(totalCount) podcasts"
  }
}
