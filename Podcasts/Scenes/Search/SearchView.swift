import SwiftUI

struct SearchView: View {
  @ObservedObject var viewModel = SearchViewModel()

  var body: some View {
    NavigationView {
      VStack {
        SearchBar(text: $viewModel.name)

        List {
          ForEach(viewModel.podcasts, id: \.self) { podcast in
            NavigationLink(destination: PodcastView(podcast: podcast), label: {
              PodcastRow(podcast: podcast)
            })
          }
        }
          .gesture(DragGesture().onChanged { _ in
            UIApplication.shared.endEditing(true)
          })
        PlayerView()
      }.navigationBarTitle(Text("Search"))
    }
  }
}
