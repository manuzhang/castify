import Foundation
import SwiftUI

struct PodcastsView: View {
  @ObservedObject var podcastsViewModel = PodcastsViewModel()
  @ObservedObject var player: Player
  @EnvironmentObject var localization: LocalizationService
  @State private var isShowingUpNextQueue = false
  @State private var queueEpisodes = [Episode]()
  @State private var isShowingInProgressQueue = false

  init(player: Player = Container.player) {
    self.player = player
  }

  var body: some View {
    NavigationView {
      VStack {
        if podcastsViewModel.podcasts.isEmpty {
          Spacer()
          VStack(spacing: 10) {
            Image(systemName: "dot.radiowaves.left.and.right")
              .font(.system(size: 40))
              .foregroundColor(.secondary)
            Text(localization.text(.noSavedPodcasts))
              .font(.headline)
            Text(localization.text(.searchForShows))
              .font(.subheadline)
              .foregroundColor(.secondary)
          }
          .multilineTextAlignment(.center)
          .padding()
          Spacer()
        } else {
          List {
            Section(header: Text(localization.text(.subscriptions))) {
              ForEach(podcastsViewModel.podcasts, id: \.self) { podcast in
                NavigationLink(destination: PodcastView(podcast: podcast), label: {
                  PodcastRow(podcast: podcast)
                })
              }
            }
          }
          .listStyle(PlainListStyle())
        }

        bottomQueueButton
      }
      .navigationBarTitle(Text(localization.text(.podcasts)))
      .onAppear(perform: {
        self.podcastsViewModel.updatePodcasts()
      })
      .onReceive(player.$state) { _ in
        self.podcastsViewModel.updateUpNextEpisodes()
      }
      .sheet(isPresented: $isShowingUpNextQueue) {
        UpNextQueueSheet(
          episodes: self.queueEpisodes,
          current: self.currentEpisode,
          headerEpisode: self.currentEpisode ?? self.queueEpisodes.first,
          isPlaying: self.isDisplayedEpisodePlaying,
          onTogglePlayback: {
            self.togglePlayback(for: self.currentEpisode ?? self.queueEpisodes.first)
          },
          onPlayAll: { episodes in
            self.queueEpisodes = episodes
            self.player.playQueue(episodes)
            self.isShowingUpNextQueue = false
          },
          onEpisodeSelected: { episode, episodes in
            self.queueEpisodes = episodes
            self.player.play(episode: episode, in: episodes)
            self.isShowingUpNextQueue = false
          },
          onReorder: reorderUpNextQueue,
          onDismiss: {
            self.isShowingUpNextQueue = false
          }
        )
        .environmentObject(self.localization)
      }
    }
  }

  @ViewBuilder
  private var bottomQueueButton: some View {
    if let episode = displayedEpisode {
      HStack(spacing: 12) {
        Button(action: {
          self.togglePlayback(for: episode)
        }) {
          Image(systemName: isDisplayedEpisodePlaying ? "pause.circle.fill" : "play.circle.fill")
            .font(.system(size: 34, weight: .regular))
        }
        .accessibility(label: Text(localization.text(isDisplayedEpisodePlaying ? .pause : .play)))

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

        Button(action: showUpNextQueue) {
          Image(systemName: "list.bullet")
            .frame(width: 34, height: 34)
        }
        .accessibility(label: Text(localization.text(.upNext)))
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 10)
      .frame(maxWidth: .infinity)
      .background(Color(.secondarySystemBackground))
      .foregroundColor(.primary)
    } else if !podcastsViewModel.upNextEpisodes.isEmpty {
      Button(action: showUpNextQueue) {
        HStack(spacing: 10) {
          Image(systemName: "list.bullet")
            .font(.system(size: 16, weight: .semibold))

          Text(localization.text(.upNext))
            .font(.subheadline)
            .fontWeight(.semibold)

          Spacer()

          Text("\(podcastsViewModel.upNextEpisodes.count) \(localization.text(.episodes))")
            .font(.caption)
            .foregroundColor(.secondary)

          Image(systemName: "chevron.up")
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemBackground))
      }
      .foregroundColor(.primary)
      .accessibility(label: Text(localization.text(.upNext)))
    }
  }

  private var currentEpisode: Episode? {
    switch player.state {
    case .playing(let episode, _), .paused(let episode, _):
      return episode
    case .empty, .finish, .idle:
      return player.current
    }
  }

  private var displayedEpisode: Episode? {
    currentEpisode ?? player.queueEpisodes.first ?? podcastsViewModel.upNextEpisodes.first
  }

  private var isDisplayedEpisodePlaying: Bool {
    currentEpisode != nil && player.isPlaying
  }

  private func showUpNextQueue() {
    podcastsViewModel.updateUpNextEpisodes()
    let activeQueue = player.queueEpisodes
    if !activeQueue.isEmpty {
      queueEpisodes = activeQueue
      isShowingInProgressQueue = false
    } else {
      queueEpisodes = podcastsViewModel.upNextEpisodes
      isShowingInProgressQueue = true
    }
    isShowingUpNextQueue = !queueEpisodes.isEmpty
  }

  private func reorderUpNextQueue(_ episodes: [Episode]) {
    queueEpisodes = episodes

    if isShowingInProgressQueue {
      podcastsViewModel.reorderUpNextEpisodes(episodes)
    }

    player.updateQueue(episodes)
  }

  private func togglePlayback(for episode: Episode? = nil) {
    switch player.state {
    case .empty:
      if let episode = episode {
        playFromQueue(episode)
      }
    case .idle, .paused, .finish:
      if currentEpisode == nil, let episode = episode {
        playFromQueue(episode)
      } else {
        player.play()
      }
    case .playing:
      player.pause()
    }
  }

  private func playFromQueue(_ episode: Episode) {
    let episodes = player.queueEpisodes.isEmpty
      ? podcastsViewModel.upNextEpisodes
      : player.queueEpisodes
    player.play(episode: episode, in: episodes.isEmpty ? [episode] : episodes)
  }
}
