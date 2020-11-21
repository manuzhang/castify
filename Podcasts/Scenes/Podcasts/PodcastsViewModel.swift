import Foundation

final class PodcastsViewModel: ObservableObject {

  @Published private(set) var podcasts = [Podcast]()
  fileprivate let podcastsService = PodcastsService()

  func updatePodcasts() {
    let pods = podcastsService.subscribedPodcasts
    self.podcasts = pods.sorted(by: {$0.trackName < $1.trackName})
  }
}