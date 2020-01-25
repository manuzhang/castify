import SwiftUI

struct SearchView: View {
  @ObservedObject var viewModel = SearchViewModel()

  var body: some View {
    NavigationView {
      VStack {
        SearchBar(text: $viewModel.name) {
          self.viewModel.search()
        }

        List {
          ForEach(viewModel.podcasts, id: \.id) { podcast in
            NavigationLink(destination: PodcastView(podcast: podcast), label: {
              PodcastRow(podcast: podcast)
            })
          }
        }
      }.navigationBarTitle(Text("Search"))
    }
  }
}
