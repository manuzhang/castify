import SwiftUI

struct HomeView: View {
  @EnvironmentObject var localization: LocalizationService

  var body: some View {
    TabView {
      PodcastsView()
        .tabItem {
          Image(systemName: "square.stack")
          Text(localization.text(.podcasts))
        }.tag(0)
      PodcastBrowserView()
        .tabItem {
          Image(systemName: "safari")
          Text(localization.text(.browse))
        }.tag(1)
      SettingsView()
        .tabItem {
          Image(systemName: "gearshape")
          Text(localization.text(.settings))
        }.tag(2)
    }
  }
}
