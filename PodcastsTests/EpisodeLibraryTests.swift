import SwiftUI
import XCTest
@testable import Castify

final class EpisodeFilterTests: XCTestCase {
  func testDurationBoundariesAndUnknownValues() {
    let cases: [(TimeInterval?, EpisodeDurationFilter)] = [
      (nil, .unknown), (0, .unknown), (-1, .unknown), (.nan, .unknown), (.infinity, .unknown),
      (1, .under15Minutes), (899, .under15Minutes), (900, .minutes15To30),
      (1799, .minutes15To30), (1800, .minutes30To60), (3599, .minutes30To60), (3600, .hourOrMore)
    ]
    for (duration, expected) in cases {
      XCTAssertTrue(EpisodeDurationFilter.any.matches(duration))
      XCTAssertEqual(EpisodeDurationFilter.allCases.filter { $0 != .any && $0.matches(duration) }, [expected])
    }
  }

  func testFiltersCombineUsingFeedOwnershipAndIncludePartiallyPlayedEpisodes() {
    let first = fixturePodcast(1)
    let second = fixturePodcast(2)
    let episode = Episode(title: "Shared title", streamUrl: "https://example.test/item.mp3", duration: 1200)
    let inProgress = EpisodePlaybackState(position: 120, duration: 1200, played: false, starred: false)
    let played = EpisodePlaybackState(position: 0, duration: 1200, played: true, starred: false)
    let entries = [
      LibraryEpisode(podcast: first, episode: episode, playbackState: inProgress, isDownloaded: true),
      LibraryEpisode(podcast: second, episode: episode, playbackState: nil, isDownloaded: true),
      LibraryEpisode(podcast: first, episode: episode, playbackState: played, isDownloaded: true),
      LibraryEpisode(podcast: first, episode: episode, playbackState: nil, isDownloaded: false)
    ]
    let filters = EpisodeFilters(unplayedOnly: true, downloadedOnly: true,
      podcastFeedURL: PodcastsService.normalizedFeedUrl(first.feedUrl), duration: .minutes15To30)
    XCTAssertEqual(entries.filter(filters.matches).count, 1)
    XCTAssertTrue(filters.matches(entries[0]))
    XCTAssertNotEqual(entries[0].id, entries[1].id)
    XCTAssertEqual(entries.filter(EpisodeFilters().matches).count, 4)
  }
}

final class EpisodeLibraryTests: XCTestCase {
  private var savedDefaults = [String: Any]()
  private let keys = [UserDefaults.subscribedPodcastsKey, UserDefaults.episodeLibraryKey,
    UserDefaults.episodePlaybackStatesKey, UserDefaults.downloadedEpisodesKey,
    UserDefaults.inProgressEpisodesKey, UserDefaults.inProgressEpisodeOrderKey,
    UserDefaults.starredEpisodesKey, UserDefaults.notificationsEnabledKey,
    UserDefaults.podcastNotificationPreferencesKey, UserDefaults.githubAutoSyncEnabledKey]
  private let service = PodcastsService()

  override func setUpWithError() throws {
    try super.setUpWithError()
    for key in keys {
      savedDefaults[key] = UserDefaults.standard.object(forKey: key)
      UserDefaults.standard.removeObject(forKey: key)
    }
    try subscribe([fixturePodcast(1), fixturePodcast(2)])
  }

  override func tearDownWithError() throws {
    for key in keys { UserDefaults.standard.set(savedDefaults[key], forKey: key) }
    savedDefaults = [:]
    try super.tearDownWithError()
  }

  func testCacheSurvivesServiceRecreationNormalizesFeedAndRemovesDuplicates() {
    let podcast = fixturePodcast(1)
    let episode = fixtureEpisode("cached", date: 10)
    service.cacheEpisodes([episode, episode], for: podcast)
    let alias = Podcast(trackId: podcast.trackId, trackName: podcast.trackName, trackCount: 0,
      artistName: "", artworkUrl100: "", feedUrl: "HTTP://EXAMPLE.TEST/1.xml")
    XCTAssertEqual(PodcastsService().cachedEpisodes(for: alias), [episode])
    service.cacheEpisodes([fixtureEpisode("ignored")], for: fixturePodcast(99))
    XCTAssertTrue(service.cachedEpisodes(for: fixturePodcast(99)).isEmpty)
  }

  func testRefreshRetainsOnlyOlderDownloadsWithFilesAndUpdatesMetadata() throws {
    let podcast = fixturePodcast(1)
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try Data([0]).write(to: file)
    defer { try? FileManager.default.removeItem(at: file) }
    let retained = fixtureEpisode("retained", fileURL: file.path)
    let missing = fixtureEpisode("missing", fileURL: file.path + "-missing")
    let dropped = fixtureEpisode("dropped")
    UserDefaults.standard.set(try JSONEncoder().encode([retained, missing]), forKey: UserDefaults.downloadedEpisodesKey)
    service.cacheEpisodes([retained, missing, dropped], for: podcast)
    let fresh = fixtureEpisode("fresh", date: 20)
    service.cacheEpisodes([fresh], for: podcast)
    XCTAssertEqual(service.cachedEpisodes(for: podcast), [fresh, retained])
    let updated = fixtureEpisode("fresh", date: 20, duration: 3600)
    service.cacheEpisodes([updated], for: podcast)
    XCTAssertEqual(service.cachedEpisodes(for: podcast).first?.duration, 3600)
    let model = EpisodeLibraryViewModel(podcastsService: service, loadFeed: { _, _ in })
    model.filters.downloadedOnly = true
    XCTAssertEqual(model.filteredEntries.map { $0.episode }, [retained])
    try FileManager.default.removeItem(at: file)
    model.reloadCachedEpisodes()
    XCTAssertTrue(model.filteredEntries.isEmpty, "Stale metadata must not count as an available download")
  }

  func testRefreshShowsCachedEpisodesOfflineAndCombinesPartialSuccessWithoutOverlappingRequests() {
    let old = fixtureEpisode("old", date: 10)
    service.cacheEpisodes([old], for: fixturePodcast(1))
    var pending = [(Podcast, (Result<[Episode], Error>) -> Void)]()
    let model = EpisodeLibraryViewModel(podcastsService: service) { podcast, completion in
      pending.append((podcast, completion))
    }
    XCTAssertEqual(model.entries.map { $0.episode }, [old])
    model.refresh()
    model.refresh()
    XCTAssertTrue(model.isRefreshing)
    XCTAssertEqual(pending.count, 2)
    let fresh = fixtureEpisode("fresh", date: 20)
    pending[1].1(.success([fresh]))
    XCTAssertTrue(model.isRefreshing)
    pending[0].1(.failure(NSError(domain: "offline", code: 1)))
    XCTAssertFalse(model.isRefreshing)
    XCTAssertEqual(model.failedPodcasts, [fixturePodcast(1).trackName])
    XCTAssertEqual(model.entries.map { $0.episode }, [fresh, old])
    XCTAssertEqual(PodcastsService().cachedEpisodes(for: fixturePodcast(1)), [old])
    XCTAssertEqual(PodcastsService().cachedEpisodes(for: fixturePodcast(2)), [fresh])
  }

  func testUnsubscribeDuringRefreshDoesNotRestoreRemovedFeedAndResetsSelection() {
    let removed = fixturePodcast(1)
    service.cacheEpisodes([fixtureEpisode("old")], for: removed)
    var pending = [(Podcast, (Result<[Episode], Error>) -> Void)]()
    let model = EpisodeLibraryViewModel(podcastsService: service) { podcast, completion in
      pending.append((podcast, completion))
    }
    model.filters.podcastFeedURL = PodcastsService.normalizedFeedUrl(removed.feedUrl)
    model.refresh()
    service.deletePodcast(removed)
    model.reloadCachedEpisodes()
    XCTAssertTrue(model.filters.podcastFeedURL.isEmpty)
    pending[0].1(.success([fixtureEpisode("late")]))
    pending[1].1(.success([]))
    XCTAssertTrue(model.entries.isEmpty)
    XCTAssertTrue(service.cachedEpisodes(for: removed).isEmpty)
    XCTAssertFalse(model.isRefreshing)
  }

  func testPlayedChangesImmediatelyUpdateUnplayedResultsAndResetRestoresAll() {
    let episode = fixtureEpisode("playable")
    service.cacheEpisodes([episode], for: fixturePodcast(1))
    let model = EpisodeLibraryViewModel(podcastsService: service, loadFeed: { _, _ in })
    model.filters.unplayedOnly = true
    model.togglePlayed(model.filteredEntries[0])
    XCTAssertTrue(model.filteredEntries.isEmpty)
    model.filters = EpisodeFilters()
    XCTAssertEqual(model.filteredEntries.count, 1)
    model.togglePlayed(model.filteredEntries[0])
    model.filters.unplayedOnly = true
    XCTAssertEqual(model.filteredEntries.count, 1)
  }

  func testEmptyLibraryDoesNotStartNetworkRequestsAndCorruptCacheIsRecoverable() throws {
    try subscribe([])
    UserDefaults.standard.set(Data("invalid".utf8), forKey: UserDefaults.episodeLibraryKey)
    var calls = 0
    let model = EpisodeLibraryViewModel(podcastsService: service) { _, _ in calls += 1 }
    model.refresh()
    XCTAssertEqual(calls, 0)
    XCTAssertFalse(model.isRefreshing)
    XCTAssertTrue(model.entries.isEmpty)
    try subscribe([fixturePodcast(1)])
    let episode = fixtureEpisode("recovered")
    service.cacheEpisodes([episode], for: fixturePodcast(1))
    model.reloadCachedEpisodes()
    XCTAssertEqual(model.entries.map { $0.episode }, [episode])
  }

  func testNetworkRefreshPopulatesLibraryAndInvalidResponseKeepsSnapshot() throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [LibraryFeedURLProtocol.self]
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel() }
    let networking = NetworkingService(podcastsService: service, feedSession: session)
    let podcast = fixturePodcast(1)
    let url = try XCTUnwrap(URL(string: podcast.feedUrl))
    for valid in [true, false] {
      LibraryFeedURLProtocol.responseData = Data((valid ? """
        <rss xmlns:itunes='http://www.itunes.com/dtds/podcast-1.0.dtd'><channel><item>
        <title>Network episode</title><enclosure url='https://example.test/audio.mp3'/>
        <itunes:duration>20:00</itunes:duration></item></channel></rss>
        """ : "<error/>").utf8)
      let loaded = expectation(description: "Stubbed network refresh")
      networking.fetchPodcastFeed(url: url, podcast: podcast) { result in
        switch result {
        case .success: XCTAssertTrue(valid)
        case .failure: XCTAssertFalse(valid)
        }
        loaded.fulfill()
      }
      wait(for: [loaded], timeout: 5)
      let cached = PodcastsService().cachedEpisodes(for: podcast)
      XCTAssertEqual(cached.count, 1)
      XCTAssertEqual(cached.first?.title, "Network episode")
      XCTAssertEqual(cached.first?.duration, 1200)
    }
  }

  func testLocalizedFilterScreenRendersAtNarrowWidthAndWithLargeText() throws {
    let podcast = fixturePodcast(1)
    let episode = fixtureEpisode("A cached episode with a long title for the library", duration: 1200)
    service.cacheEpisodes([episode], for: podcast)
    let suite = "Castify.EpisodeFilterUITests." + UUID().uuidString
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let localization = LocalizationService(userDefaults: defaults)
    for language in [AppLanguage.english, .chinese] {
      localization.setLanguage(language)
      XCTAssertEqual(localization.text(.allEpisodes), language == .english ? "All Episodes" : "全部单集")
      for scenario in ["standard", "large-text", "results"] {
        let model = EpisodeLibraryViewModel(podcastsService: service, loadFeed: { requested, completion in
          if scenario == "results" {
            completion(.success(requested.trackId == podcast.trackId ? [episode] : []))
          } else {
            completion(.failure(NSError(domain: "offline", code: 1)))
          }
        })
        model.filters.unplayedOnly = true
        model.filters.duration = .minutes15To30
        let view = NavigationView { EpisodeLibraryView(viewModel: model) }
          .navigationViewStyle(StackNavigationViewStyle())
          .environmentObject(localization)
          .environment(\.sizeCategory, scenario == "large-text" ? .accessibilityExtraExtraExtraLarge : .large)
        let host = UIHostingController(rootView: view)
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let previous = scene?.windows.first(where: { $0.isKeyWindow })
        let window = scene.map(UIWindow.init(windowScene:)) ?? UIWindow()
        window.frame = CGRect(x: 0, y: 0, width: scenario == "results" ? 390 : 320,
          height: scenario == "results" ? 844 : 568)
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()
        let rendered = expectation(description: "SwiftUI filter screen")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { rendered.fulfill() }
        wait(for: [rendered], timeout: 3)
        let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image { _ in
          host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }
        XCTAssertEqual(model.filteredEntries.count, 1)
        let attachment = XCTAttachment(image: image)
        attachment.name = "episode-filters-\(language.rawValue)-\(scenario)"
        attachment.lifetime = .keepAlways
        add(attachment)
        window.isHidden = true
        previous?.makeKey()
      }
    }
  }

  private func subscribe(_ podcasts: [Podcast]) throws {
    UserDefaults.standard.set(try JSONEncoder().encode(podcasts), forKey: UserDefaults.subscribedPodcastsKey)
  }
}

private func fixturePodcast(_ id: Int) -> Podcast {
  Podcast(trackId: id, trackName: "Show \(id)", trackCount: 0, artistName: "Shared author",
    artworkUrl100: "", feedUrl: "https://example.test/\(id).xml")
}

private func fixtureEpisode(_ title: String, date: TimeInterval = 0,
                            duration: TimeInterval = 1200, fileURL: String? = nil) -> Episode {
  Episode(title: title, pubDate: Date(timeIntervalSince1970: date),
    streamUrl: "https://example.test/\(title.fileSystemSafeName).mp3", duration: duration, fileUrl: fileURL)
}

private final class LibraryFeedURLProtocol: URLProtocol {
  static var responseData = Data()
  override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "example.test" }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Self.responseData)
    client?.urlProtocolDidFinishLoading(self)
  }
  override func stopLoading() {}
}
