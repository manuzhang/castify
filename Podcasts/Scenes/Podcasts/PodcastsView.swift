import Foundation
import SwiftUI

struct PodcastsView: View {
  @ObservedObject var podcastsViewModel = PodcastsViewModel()

  var body: some View {
    NavigationView {
      VStack {
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
}
