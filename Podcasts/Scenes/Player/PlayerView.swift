import Foundation
import SwiftUI

struct PlayerView: View {

  @ObservedObject var player: Player
  @EnvironmentObject var localization: LocalizationService
  @State private var isShowingQueue = false
  @State private var queueEpisodes = [Episode]()
  private let podcastsService = PodcastsService()

  init(player: Player = Container.player) {
    self.player = player
  }

  var body: some View {
    Group {
      if player.hasEpisodes {
        VStack(spacing: 10) {
          Slider(
            value: Binding(
              get: { Double(min(max(self.player.progress, 0), 1)) },
              set: { self.player.progress = Float($0) }
            ),
            in: 0...1,
            onEditingChanged: { editing in
              if !editing {
                self.player.seek(to: self.player.progress)
              }
            }
          )
          .accentColor(.blue)

          HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
              Text(player.current?.title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .lineLimit(1)
              Text(player.current?.author)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text(timeSummary)
              .font(.caption)
              .foregroundColor(.secondary)
              .lineLimit(1)

            Button(action: showQueue) {
              Image(systemName: "list.bullet")
                .frame(width: 32, height: 32)
            }
            .accessibility(label: Text(localization.text(.upNext)))
          }

          HStack(spacing: 24) {
            Button(action: {
              self.player.previous()
            }) {
              Image(systemName: "backward.end.fill")
            }
            .accessibility(label: Text(localization.text(.previousEpisode)))

            Button(action: {
              self.player.seek(by: -15)
            }) {
              Image(systemName: "gobackward.15")
            }
            .accessibility(label: Text(localization.text(.back15Seconds)))

            Button(action: togglePlayback) {
              Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                .font(.system(size: 44, weight: .regular))
            }
            .accessibility(label: Text(localization.text(player.isPlaying ? .pause : .play)))

            Button(action: {
              self.player.seek(by: 30)
            }) {
              Image(systemName: "goforward.30")
            }
            .accessibility(label: Text(localization.text(.forward30Seconds)))

            Button(action: {
              self.player.next()
            }) {
              Image(systemName: "forward.end.fill")
            }
            .accessibility(label: Text(localization.text(.nextEpisode)))
          }
          .font(.system(size: 18, weight: .semibold))
          .foregroundColor(.primary)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(Color(.secondarySystemBackground))
        .sheet(isPresented: $isShowingQueue) {
          UpNextQueueSheet(
            episodes: self.queueEpisodes,
            current: self.currentEpisode,
            headerEpisode: self.currentEpisode,
            isPlaying: self.player.isPlaying,
            onTogglePlayback: {
              self.togglePlayback()
            },
            onPlayAll: { episodes in
              self.queueEpisodes = episodes
              self.player.playQueue(episodes)
              self.isShowingQueue = false
            },
            onEpisodeSelected: { episode, episodes in
              self.queueEpisodes = episodes
              self.player.play(episode: episode, in: episodes)
              self.isShowingQueue = false
            },
            onReorder: reorderQueue,
            onDismiss: {
              self.isShowingQueue = false
            }
          )
          .environmentObject(self.localization)
        }
      }
    }
  }

  private var timeSummary: String {
    guard player.duration > 0 else {
      return formatTime(player.elapsedTime)
    }

    return "\(formatTime(player.elapsedTime)) / \(formatTime(player.duration))"
  }

  private var currentEpisode: Episode? {
    switch player.state {
    case .playing(let episode, _), .paused(let episode, _):
      return episode
    case .empty, .finish, .idle:
      return player.current
    }
  }

  private func togglePlayback() {
    switch player.state {
    case .empty:
      break
    case .idle, .paused, .finish:
      player.play()
    case .playing:
      player.pause()
    }
  }

  private func formatTime(_ time: TimeInterval) -> String {
    guard time.isFinite && !time.isNaN else {
      return "0:00"
    }

    let totalSeconds = max(0, Int(time))
    let hours = totalSeconds / 3600
    let minutes = (totalSeconds % 3600) / 60
    let seconds = totalSeconds % 60

    if hours > 0 {
      return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    }

    return String(format: "%d:%02d", minutes, seconds)
  }

  private func showQueue() {
    let inProgressEpisodes = podcastsService.inProgressEpisodes()
    queueEpisodes = inProgressEpisodes.isEmpty ? player.queueEpisodes : inProgressEpisodes
    isShowingQueue = !queueEpisodes.isEmpty
  }

  private func reorderQueue(_ episodes: [Episode]) {
    queueEpisodes = episodes
    podcastsService.reorderInProgressEpisodes(episodes)

    if let current = player.current, episodes.contains(current) {
      player.updateQueue(episodes)
    }
  }

}

extension Text {
  init(_ string: String?) {
    self.init(verbatim: string ?? "")
  }
}

struct UpNextQueueSheet: View {

  let current: Episode?
  let headerEpisode: Episode?
  let isPlaying: Bool
  let onTogglePlayback: () -> Void
  let onPlayAll: ([Episode]) -> Void
  let onEpisodeSelected: (Episode, [Episode]) -> Void
  let onReorder: ([Episode]) -> Void
  let onDismiss: () -> Void

  @EnvironmentObject var localization: LocalizationService
  @State private var episodes: [Episode]
  private let podcastsService = PodcastsService()

  init(episodes: [Episode],
       current: Episode?,
       headerEpisode: Episode?,
       isPlaying: Bool,
       onTogglePlayback: @escaping () -> Void,
       onPlayAll: @escaping ([Episode]) -> Void,
       onEpisodeSelected: @escaping (Episode, [Episode]) -> Void,
       onReorder: @escaping ([Episode]) -> Void,
       onDismiss: @escaping () -> Void) {
    self.current = current
    self.headerEpisode = headerEpisode
    self.isPlaying = isPlaying
    self.onTogglePlayback = onTogglePlayback
    self.onPlayAll = onPlayAll
    self.onEpisodeSelected = onEpisodeSelected
    self.onReorder = onReorder
    self.onDismiss = onDismiss
    _episodes = State(initialValue: episodes)
  }

  var body: some View {
    NavigationView {
      VStack(spacing: 0) {
        if let headerEpisode = headerEpisode {
          QueueNowPlayingHeader(
            episode: headerEpisode,
            isPlaying: isPlaying,
            onTogglePlayback: onTogglePlayback
          )
          .environmentObject(localization)
        }

        List {
          Button(action: {
            self.onPlayAll(self.episodes)
          }) {
            HStack {
              Image(systemName: "play.fill")
              Text(localization.text(.playAll))
                .fontWeight(.semibold)
            }
          }

          ForEach(episodes, id: \.self) { episode in
            Button(action: {
              self.onEpisodeSelected(episode, self.episodes)
            }) {
              HStack(spacing: 10) {
                EpisodeRow(
                  episode: episode,
                  playbackState: self.podcastsService.playbackState(for: episode)
                )

                if self.current == episode {
                  Image(systemName: "speaker.wave.2.fill")
                    .foregroundColor(.blue)
                }
              }
            }
            .buttonStyle(PlainButtonStyle())
          }
          .onMove(perform: moveEpisodes)
        }
        .environment(\.editMode, .constant(EditMode.active))
        .listStyle(PlainListStyle())
      }
      .navigationBarTitle(Text(localization.text(.upNext)), displayMode: .inline)
      .navigationBarItems(
        trailing: Button(localization.text(.cancel), action: onDismiss)
      )
    }
  }

  private func moveEpisodes(from source: IndexSet, to destination: Int) {
    episodes.move(fromOffsets: source, toOffset: destination)
    onReorder(episodes)
  }
}

private struct QueueNowPlayingHeader: View {

  let episode: Episode
  let isPlaying: Bool
  let onTogglePlayback: () -> Void
  @EnvironmentObject var localization: LocalizationService

  var body: some View {
    HStack(spacing: 12) {
      Button(action: onTogglePlayback) {
        Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
          .font(.system(size: 34, weight: .regular))
      }
      .accessibility(label: Text(localization.text(isPlaying ? .pause : .play)))

      VStack(alignment: .leading, spacing: 3) {
        Text(episode.title)
          .font(.subheadline)
          .fontWeight(.semibold)
          .lineLimit(1)
        Text(episode.author)
          .font(.caption)
          .foregroundColor(.secondary)
          .lineLimit(1)
      }

      Spacer(minLength: 8)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
    .frame(maxWidth: .infinity)
    .background(Color(.secondarySystemBackground))
    .foregroundColor(.primary)
  }
}
