import Foundation
import Combine

struct PodcastBrowseCategory: Identifiable, Hashable {
  let id: String
  let title: String
  let genreId: String?
}

extension PodcastBrowseCategory {

  static let defaults: [PodcastBrowseCategory] = [
    PodcastBrowseCategory(id: "all", title: "Top", genreId: nil),
    PodcastBrowseCategory(id: "news", title: "News", genreId: "1311"),
    PodcastBrowseCategory(id: "comedy", title: "Comedy", genreId: "1303"),
    PodcastBrowseCategory(id: "business", title: "Business", genreId: "1321"),
    PodcastBrowseCategory(id: "technology", title: "Technology", genreId: "1318"),
    PodcastBrowseCategory(id: "sports", title: "Sports", genreId: "1316"),
    PodcastBrowseCategory(id: "true-crime", title: "True Crime", genreId: "1488"),
    PodcastBrowseCategory(id: "society", title: "Society", genreId: "1324"),
    PodcastBrowseCategory(id: "education", title: "Education", genreId: "1304"),
    PodcastBrowseCategory(id: "health", title: "Health", genreId: "1307")
  ]
}

final class PodcastBrowserViewModel: ObservableObject {

  @Published var searchText = ""
  @Published private(set) var categories = PodcastBrowseCategory.defaults
  @Published var selectedCategory = PodcastBrowseCategory.defaults[0]
  @Published private(set) var podcasts = [Podcast]()
  @Published private(set) var searchResults = [Podcast]()
  @Published private(set) var isBrowseLoading = false
  @Published private(set) var isSearchLoading = false
  @Published private(set) var browseErrorMessage: String?
  @Published private(set) var searchErrorMessage: String?
  @Published private(set) var subscribedPodcastIds = Set<Int>()

  private let networkingService: NetworkingService
  private let podcastsService: PodcastsService
  private var latestSearchQuery = ""
  private var cancellables = Set<AnyCancellable>()

  var isSearchActive: Bool {
    !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  var displayedPodcasts: [Podcast] {
    isSearchActive ? searchResults : podcasts
  }

  var isLoading: Bool {
    isSearchActive ? isSearchLoading : isBrowseLoading
  }

  var errorMessage: String? {
    isSearchActive ? searchErrorMessage : browseErrorMessage
  }

  init(networkingService: NetworkingService = NetworkingService(),
       podcastsService: PodcastsService = PodcastsService()) {
    self.networkingService = networkingService
    self.podcastsService = podcastsService
    refreshSubscriptions()
    bindSearch()
  }

  func loadPodcasts(force: Bool = false) {
    guard force || podcasts.isEmpty else {
      return
    }

    let category = selectedCategory
    isBrowseLoading = true
    browseErrorMessage = nil
    networkingService.fetchTopPodcasts(genreId: category.genreId) { [weak self] podcasts in
      guard let self = self else {
        return
      }
      guard self.selectedCategory == category else {
        return
      }

      self.isBrowseLoading = false
      self.podcasts = podcasts
      self.browseErrorMessage = podcasts.isEmpty ? "Unable to load podcasts" : nil
      self.refreshSubscriptions()
    }
  }

  func select(_ category: PodcastBrowseCategory) {
    guard category != selectedCategory else {
      return
    }

    selectedCategory = category
    podcasts = []
    loadPodcasts(force: true)
  }

  func isSubscribed(_ podcast: Podcast) -> Bool {
    subscribedPodcastIds.contains(podcast.trackId)
  }

  func toggleSubscription(for podcast: Podcast) {
    if isSubscribed(podcast) {
      podcastsService.deletePodcast(podcast)
    } else {
      podcastsService.addPodcast(podcast)
    }

    refreshSubscriptions()
  }

  func refreshSubscriptions() {
    subscribedPodcastIds = Set(podcastsService.subscribedPodcasts.map { $0.trackId })
  }

  private func bindSearch() {
    $searchText
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .removeDuplicates()
      .sink { [weak self] query in
        self?.prepareSearch(query: query)
      }
      .store(in: &cancellables)

    $searchText
      .debounce(for: .milliseconds(350), scheduler: RunLoop.main)
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .removeDuplicates()
      .sink { [weak self] query in
        self?.search(query: query)
      }
      .store(in: &cancellables)
  }

  private func prepareSearch(query: String) {
    latestSearchQuery = query
    guard !query.isEmpty else {
      searchResults = []
      searchErrorMessage = nil
      isSearchLoading = false
      return
    }

    searchResults = []
    searchErrorMessage = nil
    isSearchLoading = true
  }

  private func search(query: String) {
    guard !query.isEmpty else {
      return
    }

    networkingService.fetchPodcasts(searchText: query) { [weak self] podcasts in
      guard let self = self else {
        return
      }
      guard self.latestSearchQuery == query else {
        return
      }

      self.isSearchLoading = false
      self.searchResults = podcasts
      self.searchErrorMessage = podcasts.isEmpty ? "No podcasts found" : nil
      self.refreshSubscriptions()
    }
  }
}
