import Foundation
import SwiftUI

struct PodcastsView: View {
  @ObservedObject var podcastsViewModel = PodcastsViewModel()

  var body: some View {
    NavigationView {
      VStack {
        if podcastsViewModel.podcasts.isEmpty {
          Spacer()
          VStack(spacing: 10) {
            Image(systemName: "dot.radiowaves.left.and.right")
              .font(.system(size: 40))
              .foregroundColor(.secondary)
            Text("No saved podcasts")
              .font(.headline)
            Text("Search for shows to build your library")
              .font(.subheadline)
              .foregroundColor(.secondary)
          }
          .multilineTextAlignment(.center)
          .padding()
          Spacer()
        } else {
          List {
            ForEach(podcastsViewModel.podcasts, id: \.self) { podcast in
              NavigationLink(destination: PodcastView(podcast: podcast), label: {
                PodcastRow(podcast: podcast)
              })
            }
          }
          .listStyle(PlainListStyle())
        }

        PlayerView()
      }
      .navigationBarTitle(Text("Podcasts"))
      .onAppear(perform: {
        self.podcastsViewModel.updatePodcasts()
      })
    }
  }
}
