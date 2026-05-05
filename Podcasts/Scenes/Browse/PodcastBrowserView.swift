import SwiftUI

struct PodcastBrowserView: View {

  @ObservedObject var viewModel = PodcastBrowserViewModel()
  @EnvironmentObject var localization: LocalizationService

  var body: some View {
    NavigationView {
      VStack(spacing: 0) {
        SearchBar(text: $viewModel.searchText)

        if !viewModel.isSearchActive {
          categoryPicker
        }

        if viewModel.isLoading {
          Spacer()
          Spinner()
          Spacer()
        } else if let message = viewModel.errorMessage {
          Spacer()
          Text(message)
            .font(.subheadline)
            .foregroundColor(.secondary)
          Spacer()
        } else {
          List {
            ForEach(viewModel.displayedPodcasts, id: \.self) { podcast in
              BrowsePodcastRow(
                podcast: podcast,
                isSubscribed: self.viewModel.isSubscribed(podcast),
                toggleSubscription: {
                  self.viewModel.toggleSubscription(for: podcast)
                }
              )
            }
          }
          .listStyle(PlainListStyle())
          .gesture(DragGesture().onChanged { _ in
            UIApplication.shared.endEditing(true)
          })
        }

        PlayerView()
      }
      .navigationBarTitle(Text(localization.text(.browse)))
      .onAppear {
        self.viewModel.refreshSubscriptions()
        self.viewModel.loadPodcasts()
      }
      .onReceive(localization.$language) { language in
        self.viewModel.reloadForLanguageChange(to: language)
      }
    }
  }

  private var categoryPicker: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 8) {
        ForEach(viewModel.categories) { category in
          Button(action: {
            self.viewModel.select(category)
          }, label: {
            Text(localization.text(category.titleKey))
              .font(.subheadline)
              .fontWeight(category == self.viewModel.selectedCategory ? .semibold : .regular)
              .padding(.horizontal, 12)
              .padding(.vertical, 8)
              .foregroundColor(category == self.viewModel.selectedCategory ? .white : .primary)
              .background(category == self.viewModel.selectedCategory ? Color.blue : Color(.secondarySystemFill))
              .cornerRadius(8)
          })
        }
      }
      .padding(.horizontal)
      .padding(.vertical, 10)
    }
    .background(Color(.systemBackground))
  }
}

private struct BrowsePodcastRow: View {

  let podcast: Podcast
  let isSubscribed: Bool
  let toggleSubscription: () -> Void
  @EnvironmentObject var localization: LocalizationService

  var body: some View {
    HStack(spacing: 10) {
      NavigationLink(destination: PodcastView(podcast: podcast), label: {
        PodcastRow(podcast: podcast)
      })

      Button(action: toggleSubscription, label: {
        Image(systemName: isSubscribed ? "checkmark.circle.fill" : "plus.circle")
          .font(.system(size: 22, weight: .semibold))
          .foregroundColor(isSubscribed ? .green : .blue)
          .frame(width: 36, height: 36)
      })
      .buttonStyle(BorderlessButtonStyle())
      .accessibility(label: Text(localization.text(isSubscribed ? .unsubscribe : .subscribe)))
    }
  }
}
