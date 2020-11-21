import Foundation
import SwiftUI

struct PodcastView: View {

  @ObservedObject var player: Player
  @ObservedObject var viewModel: PodcastViewModel
  @State var label: String = ""

  init(podcast: Podcast,
       player: Player = Container.player) {
    let viewModel = PodcastViewModel(podcast: podcast)
    self.viewModel = viewModel
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
                self.label = "Subscribe"
            },
              label: { Text(self.label) }
            )
          } else {
            Button(
              action: {
                self.viewModel.subscribe()
                self.label = "Unsubscribe"
            },
              label: {
                Text(self.label)
              }
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
      self.label = self.getLabel()
      self.viewModel.fetchEpisodes {
        self.player.setup(for: self.viewModel.episodes)
      }
    })
  }

  private func getLabel() -> String {
    if self.viewModel.isSubscribed() {
      return "Unsubscribe"
    } else {
      return "Subscribe"
    }
  }
}

