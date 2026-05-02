import SwiftUI

struct EpisodeView: View {

  let episode: Episode
  let episodes: [Episode]
  let networkingService = NetworkingService()
  let podcastsService = PodcastsService()
  @ObservedObject var viewModel = EpisodeViewModel()
  @ObservedObject var player: Player

  init(episode: Episode,
       episodes: [Episode] = [],
       player: Player = Container.player) {
    self.episode = episode
    self.episodes = episodes.isEmpty ? [episode] : episodes
    self.player = player
  }

  var body: some View {
    VStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          HStack(alignment: .top, spacing: 16) {
            RemoteImage(url: episode.imageURL())
              .frame(width: 112, height: 112)
              .background(Color(.tertiarySystemFill))
              .cornerRadius(8)
              .clipped()

            VStack(alignment: .leading, spacing: 8) {
              Text(episode.title)
                .font(.headline)
                .lineLimit(nil)
              Text(episode.author)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineLimit(2)
              Text(episode.pubDate.formatMedium)
                .font(.caption)
                .foregroundColor(.secondary)
            }
          }

          Button(action: togglePlayback) {
            HStack {
              Image(systemName: isCurrentEpisodePlaying ? "pause.fill" : "play.fill")
              Text(isCurrentEpisodePlaying ? "Pause" : "Play Episode")
                .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .foregroundColor(.white)
            .background(Color.blue)
            .cornerRadius(8)
          }

          downloadSection

          Text(episode.cleanDescription)
            .font(.body)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
      }

      PlayerView()
    }
    .navigationBarTitle(Text(episode.title), displayMode: .inline)
  }

  private var downloadSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      if podcastsService.episodeDownloaded(episode) {
        HStack {
          Image(systemName: "checkmark.circle.fill")
          Text("Downloaded")
        }
        .font(.subheadline)
        .foregroundColor(.secondary)
      } else {
        DownloadProgressView(progress: self.viewModel.progress)

        Button(
          action: {
            self.networkingService.downloadEpisode(self.episode) { progress in
              self.viewModel.progress = Float(progress.fractionCompleted)
            }
          },
          label: {
            HStack {
              Image(systemName: "arrow.down.circle")
              Text("Download")
            }
          })
      }
    }
  }

  private var isCurrentEpisodePlaying: Bool {
    player.current == episode && player.isPlaying
  }

  private func togglePlayback() {
    if isCurrentEpisodePlaying {
      player.pause()
    } else {
      player.play(episode: episode, in: episodes)
    }
  }
}
