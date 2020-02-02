//
//  PodcastView.swift
//  Search
//
//  Created by Alberto on 08/06/2019.
//  Copyright © 2019 com.github.albertopeam. All rights reserved.
//

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
      List {
        PodcastHeaderView(podcast: viewModel.podcast)
        Button(
          action: {
            self.viewModel.subscribe()
          },
          label: { Text("Subscribe") }
        )
        Button(
          action: {
            self.viewModel.unsubscribe()
          },
          label: { Text("Unsubscribe") }
        )
        if viewModel.episodes.isEmpty {
          Spinner()
        } else {
          ForEach(viewModel.episodes, id: \.self) { episode in
            NavigationLink(destination: EpisodeView(episode: episode)) {
              EpisodeRow(episode: episode)
            }
          }
        }
      }
      PlayerView()
    }.navigationBarTitle(Text(viewModel.podcast.trackName))
      .onAppear(perform: {
        self.viewModel.fetchEpisodes {
          self.player.setup(for: self.viewModel.episodes)
        }
      })
  }
}

