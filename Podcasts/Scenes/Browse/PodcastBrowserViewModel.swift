import Foundation
import Combine

struct PodcastBrowseCategory: Identifiable, Hashable {
  let id: String
  let titleKey: AppText
  let genreId: String?
}

extension PodcastBrowseCategory {

  static let defaults: [PodcastBrowseCategory] = [
    PodcastBrowseCategory(id: "all", titleKey: .top, genreId: nil),
    PodcastBrowseCategory(id: "arts", titleKey: .arts, genreId: "1301"),
    PodcastBrowseCategory(id: "business", titleKey: .business, genreId: "1321"),
    PodcastBrowseCategory(id: "comedy", titleKey: .comedy, genreId: "1303"),
    PodcastBrowseCategory(id: "education", titleKey: .education, genreId: "1304"),
    PodcastBrowseCategory(id: "leisure", titleKey: .leisure, genreId: "1502"),
    PodcastBrowseCategory(id: "news", titleKey: .news, genreId: "1489"),
    PodcastBrowseCategory(id: "society", titleKey: .society, genreId: "1324"),
    PodcastBrowseCategory(id: "technology", titleKey: .technology, genreId: "1318"),
    PodcastBrowseCategory(id: "health", titleKey: .health, genreId: "1512"),
    PodcastBrowseCategory(id: "sports", titleKey: .sports, genreId: "1545"),
    PodcastBrowseCategory(id: "true-crime", titleKey: .trueCrime, genreId: "1488")
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
  @Published private(set) var browseErrorMessageKey: AppText?
  @Published private(set) var searchErrorMessageKey: AppText?
  @Published private(set) var subscribedPodcastIds = Set<Int>()
  @Published private(set) var subscribedPodcastFeedUrls = Set<String>()

  private let networkingService: NetworkingService
  private let podcastsService: PodcastsService
  private var latestSearchQuery = ""
  private var loadedBrowseLanguage: AppLanguage?
  private var requestedBrowseLanguage: AppLanguage?
  private var requestedBrowseCategory: PodcastBrowseCategory?
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
    guard let key = isSearchActive ? searchErrorMessageKey : browseErrorMessageKey else {
      return nil
    }

    return LocalizationService.shared.text(key)
  }

  init(networkingService: NetworkingService = NetworkingService(),
       podcastsService: PodcastsService = PodcastsService()) {
    self.networkingService = networkingService
    self.podcastsService = podcastsService
    refreshSubscriptions()
    bindSearch()
  }

  func loadPodcasts(force: Bool = false,
                    language: AppLanguage = LocalizationService.shared.language) {
    let category = selectedCategory
    if isBrowseLoading,
       requestedBrowseLanguage == language,
       requestedBrowseCategory == category {
      return
    }

    guard force || podcasts.isEmpty || loadedBrowseLanguage != language else {
      return
    }

    requestedBrowseLanguage = language
    requestedBrowseCategory = category
    isBrowseLoading = true
    browseErrorMessageKey = nil
    networkingService.fetchTopPodcasts(genreId: category.genreId, language: language) { [weak self] podcasts in
      guard let self = self else {
        return
      }
      guard self.selectedCategory == category else {
        return
      }
      guard LocalizationService.shared.language == language else {
        return
      }

      self.isBrowseLoading = false
      self.loadedBrowseLanguage = language
      self.podcasts = podcasts
      self.browseErrorMessageKey = podcasts.isEmpty ? .unableToLoadPodcasts : nil
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
    if podcast.trackId != 0 && subscribedPodcastIds.contains(podcast.trackId) {
      return true
    }

    let feedUrl = PodcastsService.normalizedFeedUrl(podcast.feedUrl)
    return !feedUrl.isEmpty && subscribedPodcastFeedUrls.contains(feedUrl)
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
    let subscribedPodcasts = podcastsService.subscribedPodcasts
    subscribedPodcastIds = Set(subscribedPodcasts.compactMap { podcast in
      podcast.trackId == 0 ? nil : podcast.trackId
    })
    subscribedPodcastFeedUrls = Set(subscribedPodcasts.compactMap { podcast in
      let feedUrl = PodcastsService.normalizedFeedUrl(podcast.feedUrl)
      return feedUrl.isEmpty ? nil : feedUrl
    })
  }

  func reloadForLanguageChange(to language: AppLanguage) {
    if isBrowseLoading && requestedBrowseLanguage == language {
      return
    }

    guard loadedBrowseLanguage != language else {
      return
    }

    podcasts = []
    browseErrorMessageKey = nil
    loadPodcasts(force: true, language: language)

    guard isSearchActive else {
      searchResults = []
      searchErrorMessageKey = nil
      isSearchLoading = false
      return
    }

    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    prepareSearch(query: query)
    search(query: query, language: language)
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
      searchErrorMessageKey = nil
      isSearchLoading = false
      return
    }

    searchResults = []
    searchErrorMessageKey = nil
    isSearchLoading = true
  }

  private func search(query: String,
                      language: AppLanguage = LocalizationService.shared.language) {
    guard !query.isEmpty else {
      return
    }

    networkingService.fetchPodcasts(searchText: query, language: language) { [weak self] podcasts in
      guard let self = self else {
        return
      }
      guard self.latestSearchQuery == query else {
        return
      }
      guard LocalizationService.shared.language == language else {
        return
      }

      self.isSearchLoading = false
      self.searchResults = podcasts
      self.searchErrorMessageKey = podcasts.isEmpty ? .noPodcastsFound : nil
      self.refreshSubscriptions()
    }
  }
}
