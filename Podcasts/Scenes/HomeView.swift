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
      SettingsView()
        .tabItem {
          Image(systemName: "gearshape")
          Text("Settings")
        }.tag(2)
    }
  }
}
