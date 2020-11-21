import SwiftUI

struct EpisodeView: View {

  let episode: Episode
  let networkingService = NetworkingService()
  let podcastsService = PodcastsService()
  @ObservedObject var viewModel = EpisodeViewModel()

  var body: some View {
    VStack {
      Text(episode.title)
        .font(.headline)
      Text(episode.description)
        .font(.body)
      if !podcastsService.episodeDownloaded(episode) {
        ProgressView(progress: self.viewModel.progress)
        Button(
          action: {
            self.networkingService.downloadEpisode(self.episode) { progress in
              let pro = progress as Progress
              self.viewModel.progress = Float(pro.fractionCompleted)
            }
          },
          label: {
            Text("Download")
          })
      } else {
        Text("Downloaded")
      }
      PlayerView()
    }.navigationBarTitle(Text(episode.title))
  }
}
