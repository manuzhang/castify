//
//  ContentView.swift
//  Podcasts
//
//  Created by Alberto on 07/06/2019.
//  Copyright © 2019 com.github.albertopeam. All rights reserved.
//

import SwiftUI

struct PodcastsView : View {
    
    @ObjectBinding var podcastViewModel: PodcastsViewModel
    //@EnvironmentObject var player: Player
    
    init(podcastViewModel: PodcastsViewModel = PodcastsViewModel()) {
        self.podcastViewModel = podcastViewModel
    }
    
    var body: some View {
        NavigationView() {
            if podcastViewModel.podcasts.isEmpty {
                Spinner()
            } else {
                List(podcastViewModel.podcasts.identified(by: \.id)) { podcast in
                    NavigationButton(destination: PodcastView(podcast: podcast), label: {
                        PodcastRow(podcast: podcast)
                        })
                    }
                    .navigationBarTitle(Text("Best Podcasts"), displayMode: NavigationBarItem.TitleDisplayMode.inline)
                }
            }.onAppear(perform: {
                self.podcastViewModel.bestPodcasts()
            })
    }
    
}

#if DEBUG
struct ContentView_Previews : PreviewProvider {
    static var previews: some View {
        PodcastsView()
    }
}
#endif
