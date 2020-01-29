//
// Created by doriadong on 2020/1/27.
// Copyright (c) 2020 com.github.albertopeam. All rights reserved.
//

import Foundation
import SwiftUI

struct PodcastsView: View {
  @ObservedObject var podcastsViewModel = PodcastsViewModel()

  var body: some View {
    NavigationView {
      List {
        ForEach(podcastsViewModel.podcasts, id: \.self) { podcast in
          NavigationLink(destination: PodcastView(podcast: podcast), label: {
            PodcastRow(podcast: podcast)
          })
        }
      }
      PlayerView()
    }.navigationBarTitle(Text("Podcasts"))
      .onAppear(perform: {
        self.podcastsViewModel.updatePodcasts()
      })
  }
}