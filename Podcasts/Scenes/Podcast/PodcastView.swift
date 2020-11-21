import Foundation
import SwiftUI

struct PodcastView: View {

  @ObservedObject var player: Player
  @ObservedObject var viewModel: PodcastViewModel
  
  init(podcast: Podcast,
       player: Player = Container.player) {
    self.viewModel = PodcastViewModel(podcast: podcast)
    self.player = player
  }
  
  var body: some View {
    VStack {
      if viewModel.episodes.isEmpty {
        Spinner()
      } else {
        List {
          PodcastHeaderView(podcast: viewModel.podcast)
          Text(viewModel.description)
          if (self.viewModel.isSubscribed()) {
            Button(
              action: {
                self.viewModel.unsubscribe()
            },
              label: { Text("Unsubscribe") }
            )
          } else {
            Button(
              action: {
                self.viewModel.subscribe()
            },
              label: { Text("Subscribe") }
            )
          }
          
          ForEach(viewModel.episodes, id: \.self) { episode in
            NavigationLink(destination: EpisodeView(episode: episode)) {
              EpisodeRow(episode: episode)
            }
          }
        }
        PlayerView()
      }
    }.onAppear(perform: {
      self.viewModel.fetchEpisodes {
        self.player.setup(for: self.viewModel.episodes)
      }
    })
  }
}

