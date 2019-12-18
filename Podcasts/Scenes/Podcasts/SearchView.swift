import SwiftUI

struct SearchView: View {
    @ObservedObject var viewModel = SearchViewModel()

    var body: some View {
        NavigationView {
            VStack {
                SearchBar(text: $viewModel.name) {
                    self.viewModel.search()
                }

                List(viewModel.podcasts) { podcast in
                    SearchRow(viewModel: self.viewModel, podcast: podcast)
                       // .onAppear { self.viewModel.fetchImage(for: podcast) }
                }
                }
                .navigationBarTitle(Text("Search"))
        }
    }
}
