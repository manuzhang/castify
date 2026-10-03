import Foundation
import SwiftUI
import UIKit
import UserNotifications
import XCTest
@testable import Castify

private final class AlertFixtures {
  var time = Date(timeIntervalSince1970: 100)
  var podcasts: [Podcast] = []
}

private final class RecordingAlertCenter: EpisodeNotificationCenter {
  var status: UNAuthorizationStatus = .authorized
  var deferAuthorization = false
  var deferAdd = false
  var addError: Error?
  var statusCalls = 0
  var requests: [UNNotificationRequest] = []
  var pending: [String: UNNotificationRequest] = [:]
  var authorizations: [(UNAuthorizationStatus) -> Void] = []
  var additions: [() -> Void] = []
  var removals: [String] = []

  func authorizationStatus(_ completion: @escaping (UNAuthorizationStatus) -> Void) {
    statusCalls += 1
    if deferAuthorization { authorizations.append(completion) } else { completion(status) }
  }

  func add(_ request: UNNotificationRequest, completion: @escaping (Error?) -> Void) {
    requests.append(request)
    let finish = {
      if self.addError == nil { self.pending[request.identifier] = request }
      completion(self.addError)
    }
    if deferAdd { additions.append(finish) } else { finish() }
  }

  func removePending(prefix: String) {
    removals.append(prefix)
    pending = pending.filter { !$0.key.hasPrefix(prefix) }
  }

  func removePending(identifier: String) {
    removals.append(identifier)
    pending.removeValue(forKey: identifier)
  }
}

final class PodcastEpisodeNotificationTests: XCTestCase {
  private var defaults: UserDefaults!
  private var suite: String!
  private var fixture: AlertFixtures!
  private var center: RecordingAlertCenter!
  private var service: PodcastEpisodeNotificationService!
  private var podcast: Podcast!

  override func setUp() {
    super.setUp()
    suite = "Castify.NotificationTests." + UUID().uuidString
    defaults = UserDefaults(suiteName: suite)
    fixture = AlertFixtures()
    center = RecordingAlertCenter()
    podcast = makePodcast("https://example.test/feed")
    fixture.podcasts = [podcast]
    service = makeService()
  }

  override func tearDown() {
    service = nil
    defaults.removePersistentDomain(forName: suite)
    super.tearDown()
  }

  func testLegacyGlobalOffMigratesWithPerPodcastOffAndNoAPICalls() {
    XCTAssertFalse(service.isEnabled(for: podcast))
    XCTAssertNil(service.beginRefresh(feedURL: podcast.feedUrl))
    XCTAssertFalse(defaults.bool(forKey: UserDefaults.notificationsEnabledKey))
    XCTAssertEqual(center.statusCalls, 0)
    XCTAssertTrue(center.requests.isEmpty)
  }

  func testLegacyGlobalOnRemainsOnButDoesNotOptInPodcasts() {
    defaults.set(true, forKey: UserDefaults.notificationsEnabledKey)
    service = makeService()
    XCTAssertTrue(defaults.bool(forKey: UserDefaults.notificationsEnabledKey))
    XCTAssertFalse(service.isEnabled(for: podcast))
    XCTAssertNil(service.beginRefresh(feedURL: podcast.feedUrl))
    XCTAssertEqual(center.statusCalls, 0)
  }

  func testPerPodcastOptInDoesNotEnableGlobalOrQueryPermission() {
    service.setEnabled(true, for: podcast)
    XCTAssertTrue(service.isEnabled(for: podcast))
    XCTAssertFalse(defaults.bool(forKey: UserDefaults.notificationsEnabledKey))
    XCTAssertEqual(center.statusCalls, 0)
    refresh([episode("old", at: 50)])
    fixture.time = Date(timeIntervalSince1970: 120)
    refresh([episode("new", at: 110)])
    XCTAssertTrue(center.requests.isEmpty)
    XCTAssertEqual(center.statusCalls, 0)
  }

  func testFirstSuccessfulRefreshNeverAnnouncesHistoricalEpisodes() {
    enable()
    refresh((1...100).map { episode("history-\($0)", at: Double($0)) })
    XCTAssertTrue(center.requests.isEmpty)
    XCTAssertEqual(center.statusCalls, 0)
  }

  func testNewEpisodeSchedulesLocalRequestWithPodcastAndEpisodeNames() {
    baseline()
    newRefresh()
    XCTAssertEqual(center.requests.count, 1)
    XCTAssertEqual(center.requests.first?.content.title, podcast.trackName)
    XCTAssertEqual(center.requests.first?.content.body, "Episode new")
    XCTAssertEqual(center.requests.first?.content.userInfo["feedURL"] as? String, podcast.feedUrl)
    XCTAssertEqual((center.requests.first?.trigger as? UNTimeIntervalNotificationTrigger)?.timeInterval, 1)
  }

  func testRepeatedRefreshAndRepeatedGUIDWithinFeedDoNotDuplicateAlerts() {
    baseline()
    fixture.time = Date(timeIntervalSince1970: 120)
    refresh([episode("new", at: 110), episode("new", at: 110)])
    fixture.time = Date(timeIntervalSince1970: 130)
    refresh([episode("new", at: 110)])
    XCTAssertEqual(center.requests.count, 1)
  }

  func testSeenIdentitiesAndOptInPersistAcrossServiceRecreation() {
    baseline()
    newRefresh()
    service = makeService()
    XCTAssertTrue(service.isEnabled(for: podcast))
    fixture.time = Date(timeIntervalSince1970: 130)
    refresh([episode("new", at: 110)])
    XCTAssertEqual(center.requests.count, 1)
    fixture.time = Date(timeIntervalSince1970: 140)
    refresh([episode("another", at: 135)])
    XCTAssertEqual(center.requests.count, 2)
  }

  func testDeniedAndUndeterminedPermissionDoNotScheduleOrReplay() {
    for status in [UNAuthorizationStatus.denied, .notDetermined] {
      service.setEnabled(false, for: podcast)
      baseline()
      center.status = status
      fixture.time.addTimeInterval(20)
      let item = episode(UUID().uuidString, at: fixture.time.timeIntervalSince1970 - 5)
      refresh([item])
      center.status = .authorized
      fixture.time.addTimeInterval(20)
      refresh([item])
    }
    XCTAssertTrue(center.requests.isEmpty)
  }

  func testProvisionalAndEphemeralAuthorizationAreRespected() {
    baseline()
    var statuses = [UNAuthorizationStatus.provisional]
    if #available(iOS 14.0, *) { statuses.append(.ephemeral) }
    for status in statuses {
      center.status = status
      fixture.time.addTimeInterval(20)
      refresh([episode(UUID().uuidString, at: fixture.time.timeIntervalSince1970 - 5)])
    }
    XCTAssertEqual(center.requests.count, statuses.count)
  }

  func testGlobalOffCancelsPendingAndGlobalOnNeedsFreshBaseline() {
    baseline()
    newRefresh()
    XCTAssertEqual(center.pending.count, 1)
    defaults.set(false, forKey: UserDefaults.notificationsEnabledKey)
    service.globalPreferenceDidChange()
    XCTAssertTrue(center.pending.isEmpty)
    XCTAssertTrue(service.isEnabled(for: podcast))
    defaults.set(true, forKey: UserDefaults.notificationsEnabledKey)
    service.globalPreferenceDidChange()
    fixture.time = Date(timeIntervalSince1970: 150)
    refresh([episode("new", at: 110), episode("while-off", at: 140)])
    XCTAssertEqual(center.requests.count, 1)
    fixture.time = Date(timeIntervalSince1970: 170)
    refresh([episode("after-baseline", at: 160)])
    XCTAssertEqual(center.requests.count, 2)
  }

  func testGlobalChangesWhileNotObservedAreReconciledOnRefresh() {
    baseline()
    newRefresh()
    defaults.set(false, forKey: UserDefaults.notificationsEnabledKey)
    fixture.time = Date(timeIntervalSince1970: 140)
    refresh([episode("off", at: 130)])
    XCTAssertTrue(center.pending.isEmpty)
    XCTAssertEqual(center.requests.count, 1)
  }

  func testPerPodcastDisableCancelsPendingAndReenableDoesNotReplay() {
    baseline()
    newRefresh()
    service.setEnabled(false, for: podcast)
    XCTAssertFalse(service.isEnabled(for: podcast))
    XCTAssertTrue(center.pending.isEmpty)
    service.setEnabled(true, for: podcast)
    fixture.time = Date(timeIntervalSince1970: 150)
    refresh([episode("new", at: 110), episode("off", at: 140)])
    XCTAssertEqual(center.requests.count, 1)
  }

  func testUnsubscribeCancelsPendingAndResubscriptionDefaultsOff() throws {
    baseline()
    newRefresh()
    let outstanding = service.beginRefresh(feedURL: podcast.feedUrl)
    fixture.podcasts = []
    service.subscriptionRemoved(podcast)
    service.completeRefresh(outstanding, episodes: [episode("late", at: 115)])
    XCTAssertTrue(center.pending.isEmpty)
    XCTAssertTrue(try storedPreferences().isEmpty)
    fixture.podcasts = [podcast]
    XCTAssertFalse(service.isEnabled(for: podcast))
    XCTAssertNil(service.beginRefresh(feedURL: podcast.feedUrl))
    XCTAssertEqual(center.requests.count, 1)
  }

  func testStartupRemovesPreferencesForAbsentSubscriptions() throws {
    baseline()
    newRefresh()
    fixture.podcasts = []
    service = makeService()
    XCTAssertTrue(center.pending.isEmpty)
    XCTAssertTrue(try storedPreferences().isEmpty)
    let cancellationCount = center.removals.count
    service = makeService()
    XCTAssertEqual(center.removals.count, cancellationCount)
    fixture.podcasts = [podcast]
    XCTAssertFalse(service.isEnabled(for: podcast))
  }

  func testUnsubscribedPodcastCannotOptIn() {
    fixture.podcasts = []
    service.setEnabled(true, for: podcast)
    XCTAssertFalse(service.isEnabled(for: podcast))
    XCTAssertNil(defaults.data(forKey: UserDefaults.podcastNotificationPreferencesKey))
  }

  func testNormalizedFeedURLAliasesSharePreferenceAndDeduplication() {
    baseline()
    let alias = makePodcast("  HTTP://EXAMPLE.TEST/feed  ")
    XCTAssertTrue(service.isEnabled(for: alias))
    fixture.time = Date(timeIntervalSince1970: 120)
    let ticket = service.beginRefresh(feedURL: alias.feedUrl)
    service.completeRefresh(ticket, episodes: [episode("new", at: 110)])
    refresh([episode("new", at: 110)])
    XCTAssertEqual(center.requests.count, 1)
  }

  func testChangedBrowseFeedUsesSavedSubscriptionPreferenceAndRefresh() throws {
    let browsePodcast = makePodcast("https://example.test/changed-feed")
    defaults.set(true, forKey: UserDefaults.notificationsEnabledKey)
    service.globalPreferenceDidChange()
    service.setEnabled(true, for: browsePodcast)
    XCTAssertTrue(service.isEnabled(for: browsePodcast))
    XCTAssertTrue(service.isEnabled(for: podcast))
    XCTAssertEqual(Set(try storedPreferences().keys), [podcast.feedUrl])
    refresh([episode("old", at: 50)])
    newRefresh()
    XCTAssertEqual(center.pending.count, 1)
    service = makeService()
    XCTAssertTrue(service.isEnabled(for: browsePodcast))
    service.setEnabled(false, for: browsePodcast)
    XCTAssertFalse(service.isEnabled(for: podcast))
    XCTAssertTrue(center.pending.isEmpty)
    XCTAssertTrue(try storedPreferences().isEmpty)
  }

  func testZeroTrackIDsRequireMatchingFeedsAndDoNotSharePreferences() {
    let imported = makePodcast("https://example.test/imported", trackId: 0)
    let unrelated = makePodcast("https://example.test/unrelated", trackId: 0)
    fixture.podcasts = [imported]
    service.setEnabled(true, for: unrelated)
    XCTAssertFalse(service.isEnabled(for: unrelated))
    XCTAssertFalse(service.isEnabled(for: imported))
    let alias = makePodcast("HTTP://EXAMPLE.TEST/imported", trackId: 0)
    service.setEnabled(true, for: alias)
    XCTAssertTrue(service.isEnabled(for: imported))
    XCTAssertFalse(service.isEnabled(for: unrelated))
  }

  func testDisablingManyFeedsDoesNotAccumulateStoredPreferences() throws {
    baseline()
    for index in 2...25 {
      let other = makePodcast("https://example.test/feed-\(index)", trackId: index)
      fixture.podcasts.append(other)
      service.setEnabled(true, for: other)
      service.setEnabled(false, for: other)
    }
    XCTAssertEqual(Set(try storedPreferences().keys), [podcast.feedUrl])
    service.setEnabled(false, for: podcast)
    XCTAssertTrue(try storedPreferences().isEmpty)
    let cancellationCount = center.removals.count
    service = makeService()
    XCTAssertEqual(center.removals.count, cancellationCount)
  }

  func testLegacyDisabledRecordsArePrunedOnceAtStartup() throws {
    service.setEnabled(true, for: podcast)
    let data = try XCTUnwrap(defaults.data(forKey: UserDefaults.podcastNotificationPreferencesKey))
    var store = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    var preferences = try storedPreferences()
    var disabled = try XCTUnwrap(preferences[podcast.feedUrl] as? [String: Any])
    disabled["enabled"] = false
    preferences[podcast.feedUrl] = disabled
    store["preferences"] = preferences
    defaults.set(try JSONSerialization.data(withJSONObject: store), forKey: UserDefaults.podcastNotificationPreferencesKey)
    center.removals.removeAll()
    service = makeService()
    XCTAssertFalse(service.isEnabled(for: podcast))
    XCTAssertTrue(try storedPreferences().isEmpty)
    XCTAssertEqual(center.removals.count, 1)
    let cleaned = defaults.data(forKey: UserDefaults.podcastNotificationPreferencesKey)
    service = makeService()
    XCTAssertEqual(center.removals.count, 1)
    XCTAssertEqual(defaults.data(forKey: UserDefaults.podcastNotificationPreferencesKey), cleaned)
  }

  func testNewestStartedRefreshWinsOverOutOfOrderResponses() {
    baseline()
    let older = service.beginRefresh(feedURL: podcast.feedUrl)
    let newer = service.beginRefresh(feedURL: podcast.feedUrl)
    fixture.time = Date(timeIntervalSince1970: 120)
    service.completeRefresh(newer, episodes: [episode("new", at: 110)])
    service.completeRefresh(older, episodes: [episode("stale", at: 105)])
    XCTAssertEqual(center.requests.count, 1)
    XCTAssertEqual(center.requests.first?.content.body, "Episode new")
  }

  func testFailedInitialRefreshLeavesNextSuccessAsBaseline() {
    enable()
    _ = service.beginRefresh(feedURL: podcast.feedUrl) // Failed request has no success callback.
    fixture.time = Date(timeIntervalSince1970: 120)
    refresh([episode("first-snapshot", at: 110)])
    XCTAssertTrue(center.requests.isEmpty)
  }

  func testOlderResponseAfterNewerFailureCannotEstablishBaselineOrReplay() {
    enable()
    let older = service.beginRefresh(feedURL: podcast.feedUrl)
    _ = service.beginRefresh(feedURL: podcast.feedUrl) // Newer fetch fails.
    fixture.time = Date(timeIntervalSince1970: 120)
    service.completeRefresh(older, episodes: [episode("old", at: 110)])
    fixture.time = Date(timeIntervalSince1970: 150)
    refresh([episode("old", at: 110), episode("snapshot", at: 140)])
    XCTAssertTrue(center.requests.isEmpty)
  }

  func testReenabledPreferenceRejectsRefreshStartedBeforeDisable() {
    baseline()
    let old = service.beginRefresh(feedURL: podcast.feedUrl)
    service.setEnabled(false, for: podcast)
    service.setEnabled(true, for: podcast)
    fixture.time = Date(timeIntervalSince1970: 120)
    service.completeRefresh(old, episodes: [episode("old-generation", at: 110)])
    refresh([episode("baseline", at: 110)])
    XCTAssertTrue(center.requests.isEmpty)
  }

  func testDisableWhilePermissionLookupPendingPreventsSubmission() {
    baseline()
    center.deferAuthorization = true
    newRefresh()
    service.setEnabled(false, for: podcast)
    center.authorizations[0](.authorized)
    XCTAssertTrue(center.requests.isEmpty)
  }

  func testUnsubscribeAndGlobalOffWhilePermissionLookupPendingPreventSubmission() {
    baseline()
    center.deferAuthorization = true
    newRefresh()
    defaults.set(false, forKey: UserDefaults.notificationsEnabledKey)
    center.authorizations[0](.authorized)
    XCTAssertTrue(center.requests.isEmpty)
    defaults.set(true, forKey: UserDefaults.notificationsEnabledKey)
    service.globalPreferenceDidChange()
    baseline()
    newRefresh()
    fixture.podcasts = []
    service.subscriptionRemoved(podcast)
    center.authorizations[1](.authorized)
    XCTAssertTrue(center.requests.isEmpty)
  }

  func testLateAddCompletionCancelsOnlyOldGenerationAfterReenable() {
    baseline()
    center.deferAdd = true
    newRefresh()
    service.setEnabled(false, for: podcast)
    service.setEnabled(true, for: podcast)
    fixture.time = Date(timeIntervalSince1970: 140)
    refresh([episode("baseline", at: 130)])
    fixture.time = Date(timeIntervalSince1970: 160)
    refresh([episode("replacement", at: 150)])
    center.additions[1]()
    center.additions[0]()
    XCTAssertEqual(center.pending.count, 1)
    XCTAssertEqual(center.pending.values.first?.content.body, "Episode replacement")
  }

  func testAddFailureDoesNotReplayOnNextRefresh() {
    baseline()
    center.addError = NSError(domain: "notification-test", code: 1)
    newRefresh()
    center.addError = nil
    fixture.time = Date(timeIntervalSince1970: 140)
    refresh([episode("new", at: 110)])
    XCTAssertEqual(center.requests.count, 1)
    XCTAssertTrue(center.pending.isEmpty)
  }

  func testNewHistoricalInsertMissingDateAndFutureDateDoNotAlert() {
    baseline()
    fixture.time = Date(timeIntervalSince1970: 120)
    refresh([episode("inserted-history", at: 80), episode("missing-date", at: Date.distantPast.timeIntervalSince1970),
             episode("future-date", at: 200)])
    XCTAssertTrue(center.requests.isEmpty)
  }

  func testBatchRefreshUsesOneLocalizedNotification() {
    let localization = LocalizationService(userDefaults: defaults)
    localization.setLanguage(.chinese)
    service = makeService(localization: localization)
    baseline()
    fixture.time = Date(timeIntervalSince1970: 120)
    refresh([episode("one", at: 105), episode("two", at: 110)])
    XCTAssertEqual(center.requests.count, 1)
    XCTAssertEqual(center.requests.first?.content.body, "2 个新单集。最新：Episode two")
  }

  func testIdenticalGUIDsInDifferentPodcastsAreIndependentAndCancellationIsScoped() {
    let other = makePodcast("https://example.test/other", trackId: 2)
    fixture.podcasts.append(other)
    baseline()
    service.setEnabled(true, for: other)
    service.completeRefresh(service.beginRefresh(feedURL: other.feedUrl), episodes: [episode("old", at: 50)])
    fixture.time = Date(timeIntervalSince1970: 120)
    newRefresh()
    service.completeRefresh(service.beginRefresh(feedURL: other.feedUrl), episodes: [episode("new", at: 110)])
    XCTAssertEqual(center.pending.count, 2)
    service.setEnabled(false, for: podcast)
    XCTAssertEqual(center.pending.count, 1)
  }

  func testAuthorizationCallbackFromBackgroundQueueSchedulesOnMain() {
    baseline()
    center.deferAuthorization = true
    newRefresh()
    let callback = center.authorizations[0]
    let delivered = expectation(description: "Main-thread authorization reconciliation")
    DispatchQueue.global().async {
      callback(.authorized)
      DispatchQueue.main.async { delivered.fulfill() }
    }
    wait(for: [delivered], timeout: 3)
    XCTAssertEqual(center.requests.count, 1)
  }

  func testForegroundPresentationRechecksGlobalSubscriptionAndGeneration() throws {
    baseline()
    newRefresh()
    let request = try XCTUnwrap(center.requests.first)
    XCTAssertTrue(service.shouldPresent(request))
    service.setEnabled(false, for: podcast)
    XCTAssertFalse(service.shouldPresent(request))
    service.setEnabled(true, for: podcast)
    XCTAssertFalse(service.shouldPresent(request))
    let foreign = UNNotificationRequest(identifier: "unrelated", content: request.content, trigger: nil)
    XCTAssertFalse(service.shouldPresent(foreign))
    fixture.time.addTimeInterval(20)
    refresh([episode("baseline", at: fixture.time.timeIntervalSince1970 - 5)])
    newRefresh()
    let current = try XCTUnwrap(center.requests.last)
    XCTAssertTrue(service.shouldPresent(current))
    defaults.set(false, forKey: UserDefaults.notificationsEnabledKey)
    XCTAssertFalse(service.shouldPresent(current))
  }

  func testCorruptOrUnknownPreferenceVersionFailsClosedWithoutChangingGlobalChoice() throws {
    defaults.set(true, forKey: UserDefaults.notificationsEnabledKey)
    for data in [Data("corrupt".utf8), Data("{\"version\":99,\"globalEnabled\":true,\"preferences\":{}}".utf8)] {
      defaults.set(data, forKey: UserDefaults.podcastNotificationPreferencesKey)
      service = makeService()
      XCTAssertFalse(service.isEnabled(for: podcast))
      XCTAssertTrue(defaults.bool(forKey: UserDefaults.notificationsEnabledKey))
    }
    XCTAssertTrue(center.requests.isEmpty)
  }

  private func makeService(localization: LocalizationService? = nil) -> PodcastEpisodeNotificationService {
    PodcastEpisodeNotificationService(userDefaults: defaults, center: center,
      subscriptions: { [fixture] in fixture!.podcasts }, now: { [fixture] in fixture!.time },
      localization: localization ?? LocalizationService(userDefaults: defaults))
  }

  private func enable() {
    defaults.set(true, forKey: UserDefaults.notificationsEnabledKey)
    service.globalPreferenceDidChange()
    service.setEnabled(true, for: podcast)
    XCTAssertTrue(service.isEnabled(for: podcast))
  }

  private func baseline() {
    enable()
    refresh([episode("old", at: 50)])
  }

  private func newRefresh() {
    fixture.time.addTimeInterval(20)
    refresh([episode("new", at: fixture.time.timeIntervalSince1970 - 10)])
  }

  private func refresh(_ episodes: [Episode]) {
    service.completeRefresh(service.beginRefresh(feedURL: podcast.feedUrl), episodes: episodes)
  }

  private func episode(_ guid: String, at time: TimeInterval) -> Episode {
    Episode(title: "Episode " + guid, pubDate: Date(timeIntervalSince1970: time),
            streamUrl: "https://example.test/\(guid).mp3", guid: guid, publicationDateIsKnown: true)
  }

  private func storedPreferences() throws -> [String: Any] {
    let data = try XCTUnwrap(defaults.data(forKey: UserDefaults.podcastNotificationPreferencesKey))
    let store = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    return try XCTUnwrap(store["preferences"] as? [String: Any])
  }

  private func makePodcast(_ feed: String, trackId: Int = 1) -> Podcast {
    Podcast(trackId: trackId, trackName: "Example Podcast", trackCount: 0, artistName: "Test", artworkUrl100: "", feedUrl: feed)
  }
}

final class PodcastNotificationIdentityTests: XCTestCase {
  func testParserPreservesGUIDAndIdentityIgnoresTitleAndEnclosureChanges() throws {
    let feed = try parse("<title>First</title><guid> stable-id </guid><enclosure url='https://example.test/one.mp3'/>")
    let changed = Episode(title: "Edited", streamUrl: "https://example.test/two.mp3", guid: "stable-id")
    XCTAssertEqual(feed.episodes.first?.guid, "stable-id")
    XCTAssertEqual(PodcastEpisodeNotificationService.identity(try XCTUnwrap(feed.episodes.first)), PodcastEpisodeNotificationService.identity(changed))
  }

  func testIdentityUsesEnclosureThenDatedMetadataAndRejectsUnidentifiedItems() {
    let date = Date(timeIntervalSince1970: 100)
    XCTAssertEqual(PodcastEpisodeNotificationService.identity(Episode(title: "First", streamUrl: "https://example.test/one.mp3")),
                   PodcastEpisodeNotificationService.identity(Episode(title: "Edited", streamUrl: "https://example.test/one.mp3")))
    XCTAssertEqual(PodcastEpisodeNotificationService.identity(Episode(title: "Same", pubDate: date, publicationDateIsKnown: true)),
                   PodcastEpisodeNotificationService.identity(Episode(title: "Same", pubDate: date, publicationDateIsKnown: true)))
    XCTAssertNotEqual(PodcastEpisodeNotificationService.identity(Episode(title: "Same", pubDate: date, publicationDateIsKnown: true)),
                      PodcastEpisodeNotificationService.identity(Episode(title: "Same", pubDate: date.addingTimeInterval(1), publicationDateIsKnown: true)))
    XCTAssertNil(PodcastEpisodeNotificationService.identity(Episode(title: "No ID", pubDate: .distantPast)))
  }

  func testMissingAndInvalidDatesStayStableAndCannotMasqueradeAsNewEpisodes() throws {
    for item in ["<title>Missing</title>", "<title>Invalid</title><pubDate>not-a-date</pubDate>"] {
      let episode = try XCTUnwrap(parse(item).episodes.first)
      XCTAssertNil(episode.notificationPublicationDate)
      XCTAssertEqual(episode.publicationDateIsKnown, false)
    }
  }

  func testOlderEpisodeCacheDecodesWithoutGUID() throws {
    let episode = Episode(title: "Legacy", streamUrl: "https://example.test/one.mp3")
    var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(episode)) as? [String: Any])
    object.removeValue(forKey: "guid")
    object.removeValue(forKey: "publicationDateIsKnown")
    let decoded = try JSONDecoder().decode(Episode.self, from: JSONSerialization.data(withJSONObject: object))
    XCTAssertNil(decoded.guid)
    XCTAssertNil(decoded.notificationPublicationDate)
    XCTAssertEqual(decoded, episode)
  }

  private func parse(_ item: String) throws -> ParsedPodcastFeed {
    try PodcastFeedParser().parse(data: Data("<rss><channel><item>\(item)</item></channel></rss>".utf8))
  }
}

final class PodcastNotificationUITests: XCTestCase {
  func testLocalizedOptInControlsRenderOffAndOnAtNarrowWidth() throws {
    let suite = "Castify.NotificationUITests." + UUID().uuidString
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let podcast = Podcast(trackId: 123, trackName: "Test", trackCount: 0, artistName: "Test", artworkUrl100: "", feedUrl: "https://example.test/ui-feed")
    let saved = UserDefaults.standard.data(forKey: UserDefaults.subscribedPodcastsKey)
    UserDefaults.standard.set(try JSONEncoder().encode([podcast]), forKey: UserDefaults.subscribedPodcastsKey)
    defer { UserDefaults.standard.set(saved, forKey: UserDefaults.subscribedPodcastsKey) }
    let center = RecordingAlertCenter()
    let localization = LocalizationService(userDefaults: defaults)
    let service = PodcastEpisodeNotificationService(userDefaults: defaults, center: center, subscriptions: { [podcast] }, localization: localization)
    let model = PodcastViewModel(podcast: podcast, notificationService: service)
    XCTAssertTrue(model.isSubscribed())
    for language in [AppLanguage.english, .chinese] {
      localization.setLanguage(language)
      XCTAssertEqual(localization.text(.podcastEpisodeAlerts), language == .english ? "New episode alerts" : "新单集提醒")
      for enabled in [false, true] {
        model.setEpisodeAlertsEnabled(enabled)
        XCTAssertEqual(model.episodeAlertsEnabled, enabled)
        let view = List { PodcastNotificationSettingsView(viewModel: model) }.environmentObject(localization)
        let host = UIHostingController(rootView: view)
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let previous = scene?.windows.first(where: { $0.isKeyWindow })
        let window = scene.map(UIWindow.init(windowScene:)) ?? UIWindow()
        window.frame = CGRect(x: 0, y: 0, width: 320, height: 568)
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()
        let rendered = expectation(description: "SwiftUI draw")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { rendered.fulfill() }
        wait(for: [rendered], timeout: 3)
        let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image { _ in
          host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = "podcast-alerts-\(language.rawValue)-\(enabled ? "on" : "off")"
        attachment.lifetime = .keepAlways
        add(attachment)
        window.isHidden = true
        previous?.makeKey()
      }
    }
    XCTAssertFalse(defaults.bool(forKey: UserDefaults.notificationsEnabledKey))
    XCTAssertEqual(center.statusCalls, 0)
    XCTAssertTrue(center.requests.isEmpty)
  }
}

private final class StubAlertFeedProtocol: URLProtocol {
  static var responses = [Result<Data, Error>]()
  private static let lock = NSLock()

  override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "feed-alert-tests.invalid" }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    Self.lock.lock()
    let result = Self.responses.removeFirst()
    Self.lock.unlock()
    switch result {
    case .success(let data):
      client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: data)
      client?.urlProtocolDidFinishLoading(self)
    case .failure(let error):
      client?.urlProtocol(self, didFailWithError: error)
    }
  }

  override func stopLoading() {}
}

final class PodcastNotificationRefreshTests: XCTestCase {
  func testSuccessfulNetworkRefreshParsesIdentityAndSchedulesOnlyAfterBaseline() throws {
    try verifyRefreshes(firstFails: false)
  }

  func testFailedNetworkRefreshDoesNotAnnounceFirstSuccessfulSnapshot() throws {
    try verifyRefreshes(firstFails: true)
  }

  private func verifyRefreshes(firstFails: Bool) throws {
    let suite = "Castify.NotificationRefreshTests." + UUID().uuidString
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite); StubAlertFeedProtocol.responses = [] }
    defaults.set(true, forKey: UserDefaults.notificationsEnabledKey)
    let podcast = Podcast(trackId: 123, trackName: "Stub Podcast", trackCount: 0, artistName: "Test", artworkUrl100: "", feedUrl: "https://feed-alert-tests.invalid/rss")
    let fixture = AlertFixtures()
    fixture.podcasts = [podcast]
    let center = RecordingAlertCenter()
    let service = PodcastEpisodeNotificationService(userDefaults: defaults, center: center,
      subscriptions: { fixture.podcasts }, now: { fixture.time }, localization: LocalizationService(userDefaults: defaults))
    service.setEnabled(true, for: podcast)
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubAlertFeedProtocol.self]
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel() }
    let networking = NetworkingService(notificationService: service, feedSession: session)
    let url = try XCTUnwrap(URL(string: podcast.feedUrl))
    if firstFails {
      StubAlertFeedProtocol.responses = [.failure(NSError(domain: "stub-feed", code: 1))]
      let failed = expectation(description: "Feed error")
      networking.fetchPodcastFeed(url: url) { result in
        if case .success = result { XCTFail("Expected stubbed error") }
        failed.fulfill()
      }
      wait(for: [failed], timeout: 5)
    }
    for (guid, timestamp) in [("baseline", 50.0), ("new", 110.0)] {
      fixture.time = Date(timeIntervalSince1970: guid == "baseline" ? 100 : 120)
      let date = ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: timestamp))
      StubAlertFeedProtocol.responses = [.success(Data("<rss><channel><item><title>Stub \(guid)</title><guid>\(guid)</guid><pubDate>\(date)</pubDate><enclosure url='https://feed-alert-tests.invalid/\(guid).mp3'/></item></channel></rss>".utf8))]
      let loaded = expectation(description: "Feed success")
      networking.fetchPodcastFeed(url: url) { result in
        if case .success(let feed) = result {
          XCTAssertEqual(feed.episodes.first?.guid, guid)
          XCTAssertEqual(feed.episodes.first?.publicationDateIsKnown, true)
        } else { XCTFail("Expected stubbed success") }
        loaded.fulfill()
      }
      wait(for: [loaded], timeout: 5)
      XCTAssertEqual(center.requests.count, guid == "baseline" ? 0 : 1)
    }
    XCTAssertEqual(center.requests.first?.content.body, "Stub new")
    XCTAssertTrue(StubAlertFeedProtocol.responses.isEmpty)
  }
}
