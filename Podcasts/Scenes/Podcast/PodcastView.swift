import Foundation
import SwiftUI

struct PodcastView: View {

  @ObservedObject var player: Player
  @ObservedObject var viewModel: PodcastViewModel
  @EnvironmentObject var localization: LocalizationService

  init(podcast: Podcast,
       player: Player = Container.player) {
    let viewModel = PodcastViewModel(podcast: podcast)
    self.viewModel = viewModel
    self.player = player
  }

  var body: some View {
    VStack {
      List {
        PodcastHeaderView(podcast: viewModel.podcast)

        if !viewModel.description.isEmpty {
          Text(viewModel.description)
            .font(.subheadline)
            .foregroundColor(.secondary)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
        }

        Button(action: toggleSubscription) {
          HStack {
            Image(systemName: viewModel.isSubscribed() ? "checkmark.circle.fill" : "plus.circle")
            Text(localization.text(viewModel.isSubscribed() ? .subscribed : .subscribe))
          }
          .font(.headline)
        }

        if viewModel.isLoading {
          HStack {
            Spacer()
            Spinner()
            Spacer()
          }
        } else if let message = viewModel.errorMessage {
          Text(message)
            .font(.subheadline)
            .foregroundColor(.secondary)
        } else if viewModel.episodes.isEmpty {
          Text(localization.text(.noEpisodesAvailable))
            .font(.subheadline)
            .foregroundColor(.secondary)
        } else {
          ForEach(viewModel.episodes, id: \.self) { episode in
            NavigationLink(destination: EpisodeView(episode: episode, episodes: self.viewModel.episodes)) {
              EpisodeRow(episode: episode)
            }
          }
        }
      }
      .listStyle(PlainListStyle())

      PlayerView()
    }
    .navigationBarTitle(Text(viewModel.podcast.trackName), displayMode: .inline)
    .onAppear(perform: {
      self.viewModel.fetchEpisodes {
        self.player.setup(for: self.viewModel.episodes)
      }
    })
  }

  private func toggleSubscription() {
    if self.viewModel.isSubscribed() {
      self.viewModel.unsubscribe()
    } else {
      self.viewModel.subscribe()
    }
  }
}
