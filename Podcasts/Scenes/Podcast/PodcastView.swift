//
//  PodcastView.swift
//  Podcasts
//
//  Created by Alberto on 08/06/2019.
//  Copyright © 2019 com.github.albertopeam. All rights reserved.
//

//TODO: como gestionar esta inyeccion: `PodcastViewModel` ????, con un var tal vez????
import SwiftUI

struct PodcastView : View {
    
    @ObservedObject var podcastViewModel: PodcastViewModel
    @ObservedObject var imageLoader: ImageLoader
    @ObservedObject var player: Player
    
    init(podcast: Podcast,
         imageLoader: ImageLoader = ImageLoader(),
         player: Player = Container.player) {
        self.podcastViewModel = PodcastViewModel(podcast: podcast)
        self.imageLoader = imageLoader
        self.player = player
    }
    
    var body: some View {
        VStack {
            List {
                PodcastHeaderView(podcast: podcastViewModel.podcast, imageLoader: imageLoader)
                if podcastViewModel.episodes.isEmpty {
                    Spinner()
                } else {
                    HStack {
                        Spacer()
                        Button(action: {
                            self.player.setup(for: self.podcastViewModel.episodes)
                        }, label: {
                            Text("Prepare to play")
                        }).foregroundColor(.green)
                        Spacer()
                    }
                    ForEach(podcastViewModel.episodes, id: \.id) { episode in
                        NavigationLink(destination: EpisodeView(episode: episode)) {
                            EpisodeRow(episode: episode)
                        }
                    }
                }
            }
            PlayerView()
            }.navigationBarTitle(Text(podcastViewModel.podcast.title))
            .onAppear(perform: {
                self.podcastViewModel.loadEpisodes()
            })
    }
}

#if DEBUG
struct PodcastView_Previews : PreviewProvider {
    static var previews: some View {
        PodcastView(podcast: podcasts.first!)
    }
}
#endif
