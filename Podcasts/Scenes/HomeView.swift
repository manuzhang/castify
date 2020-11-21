import SwiftUI

struct HomeView: View {

  var body: some View {
    TabView {
      PodcastsView()
        .tabItem {
          Image(systemName: "list.dash")
          Text("Podcasts")
        }.tag(0)
      SearchView()
        .tabItem {
          Image(systemName: "magnifyingglass")
          Text("Search")
        }.imageScale(.large).tag(1)
    }.font(.headline)
  }
}

