import SwiftUI

struct EpisodeView: View {

  let episode: Episode
  let episodes: [Episode]
  let networkingService = NetworkingService()
  let podcastsService = PodcastsService()
  @ObservedObject var viewModel = EpisodeViewModel()
  @ObservedObject var player: Player
  @EnvironmentObject var localization: LocalizationService
  @State private var playbackState: EpisodePlaybackState?

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
              Text(playbackButtonTitle)
                .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .foregroundColor(.white)
            .background(Color.blue)
            .cornerRadius(8)
          }

          playbackStateSection

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
    .onAppear {
      self.refreshPlaybackState()
    }
    .onReceive(player.$state) { _ in
      self.refreshPlaybackState()
    }
  }

  private var playbackStateSection: some View {
    HStack(spacing: 8) {
      Image(systemName: playbackStatusIconName)
        .foregroundColor(playbackState?.played == true ? .green : .blue)
      Text(playbackStatusText)
        .foregroundColor(.secondary)
      Spacer()
      Button(action: togglePlayedState) {
        Text(localization.text(playbackState?.played == true ? .markAsUnplayed : .markAsPlayed))
      }
    }
    .font(.subheadline)
  }

  private var downloadSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      if podcastsService.episodeDownloaded(episode) {
        HStack {
          Image(systemName: "checkmark.circle.fill")
          Text(localization.text(.downloaded))
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
              Text(localization.text(.download))
            }
          })
      }
    }
  }

  private var isCurrentEpisodePlaying: Bool {
    player.current == episode && player.isPlaying
  }

  private var playbackButtonTitle: String {
    if isCurrentEpisodePlaying {
      return localization.text(.pause)
    }

    if playbackState?.hasResumePosition == true {
      return localization.text(.resumeEpisode)
    }

    return localization.text(.playEpisode)
  }

  private var playbackStatusIconName: String {
    if playbackState?.played == true {
      return "checkmark.circle.fill"
    }

    if playbackState?.hasResumePosition == true {
      return "play.circle.fill"
    }

    return "circle"
  }

  private var playbackStatusText: String {
    if playbackState?.played == true {
      return localization.text(.played)
    }

    if let state = playbackState, state.hasResumePosition {
      return "\(localization.text(.resumeAt)) \(formatTimestamp(state.position))"
    }

    return localization.text(.unplayed)
  }

  private func togglePlayback() {
    if isCurrentEpisodePlaying {
      player.pause()
    } else {
      player.play(episode: episode, in: episodes)
    }
  }

  private func togglePlayedState() {
    if playbackState?.played == true {
      podcastsService.markEpisodeUnplayed(episode)
    } else {
      podcastsService.markEpisodePlayed(episode)
    }

    refreshPlaybackState()
  }

  private func refreshPlaybackState() {
    playbackState = podcastsService.playbackState(for: episode)
  }

  private func formatTimestamp(_ time: TimeInterval) -> String {
    let totalSeconds = max(0, Int(time))
    let hours = totalSeconds / 3600
    let minutes = (totalSeconds % 3600) / 60
    let seconds = totalSeconds % 60

    if hours > 0 {
      return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    }

    return String(format: "%d:%02d", minutes, seconds)
  }
}
