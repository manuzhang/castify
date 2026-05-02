import SwiftUI

struct HomeView: View {

  var body: some View {
    TabView {
      PodcastsView()
        .tabItem {
          Image(systemName: "square.stack")
          Text("Podcasts")
        }.tag(0)
      PodcastBrowserView()
        .tabItem {
          Image(systemName: "safari")
          Text("Browse")
        }.tag(1)
    }
  }
}
