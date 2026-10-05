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
  var deferPendingLookup = false
  var deferPrefixRemoval = false
  var prefixRemovals: [() -> Void] = []
  var pendingLookups: [([UNNotificationRequest]) -> Void] = []
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

  func pendingRequests(_ completion: @escaping ([UNNotificationRequest]) -> Void) {
    if deferPendingLookup { pendingLookups.append(completion) } else { completion(Array(pending.values)) }
  }

  func removePending(prefix: String) {
    removals.append(prefix)
    let finish = { self.pending = self.pending.filter { !$0.key.hasPrefix(prefix) } }
    if deferPrefixRemoval { prefixRemovals.append(finish) } else { finish() }
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
    disabled.removeValue(forKey: "submittedIdentifiers")
    disabled.removeValue(forKey: "unconfirmedIdentifiers")
    disabled.removeValue(forKey: "hasUntrackedRequests")
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

  func testDelayedBaselineKeepsEpisodesPublishedDuringFetchEligible() {
    enable()
    let first = service.beginRefresh(feedURL: podcast.feedUrl)
    fixture.time = Date(timeIntervalSince1970: 120)
    service.completeRefresh(first, episodes: [episode("old", at: 50)])
    XCTAssertTrue(center.requests.isEmpty)
    fixture.time = Date(timeIntervalSince1970: 140)
    refresh([episode("old", at: 50), episode("during-fetch", at: 110)])
    XCTAssertEqual(center.requests.count, 1)
    XCTAssertEqual(center.requests.first?.content.body, "Episode during-fetch")
  }

  func testLaterDelayedSnapshotPreservesUncoveredIntervalAfterRestart() {
    baseline()
    fixture.time = Date(timeIntervalSince1970: 120)
    let delayed = service.beginRefresh(feedURL: podcast.feedUrl)
    fixture.time = Date(timeIntervalSince1970: 140)
    service.completeRefresh(delayed, episodes: [episode("old", at: 50)])
    service = makeService()
    fixture.time = Date(timeIntervalSince1970: 160)
    refresh([episode("inserted-history", at: 80), episode("during-fetch", at: 130)])
    XCTAssertEqual(center.requests.count, 1)
    XCTAssertEqual(center.requests.first?.content.body, "Episode during-fetch")
  }

  func testCachedSnapshotDateKeepsUncoveredEpisodesEligible() {
    baseline()
    fixture.time = Date(timeIntervalSince1970: 140)
    let cached = service.beginRefresh(feedURL: podcast.feedUrl)
    service.completeRefresh(cached, episodes: [episode("old", at: 50)], responseDate: Date(timeIntervalSince1970: 110))
    fixture.time = Date(timeIntervalSince1970: 160)
    refresh([episode("after-cache", at: 130)])
    XCTAssertEqual(center.requests.first?.content.body, "Episode after-cache")
  }

  func testCacheAgeWithoutDateKeepsUncoveredEpisodesEligible() {
    baseline()
    fixture.time = Date(timeIntervalSince1970: 140)
    let cached = service.beginRefresh(feedURL: podcast.feedUrl)
    service.completeRefresh(cached, episodes: [episode("old", at: 50)], responseAge: 30)
    fixture.time = Date(timeIntervalSince1970: 160)
    refresh([episode("after-cache", at: 130)])
    XCTAssertEqual(center.requests.first?.content.body, "Episode after-cache")
  }

  func testChangedBrowseRefreshUsesSavedPreferenceAndInvalidatesOnDisable() {
    let browse = makePodcast("https://example.test/changed-feed")
    enable()
    service.completeRefresh(service.beginRefresh(feedURL: browse.feedUrl, podcast: browse), episodes: [episode("old", at: 50)])
    fixture.time = Date(timeIntervalSince1970: 120)
    service.completeRefresh(service.beginRefresh(feedURL: browse.feedUrl, podcast: browse), episodes: [episode("new", at: 110)])
    XCTAssertEqual(center.requests.count, 1)
    XCTAssertEqual(center.requests.first?.content.userInfo["feedURL"] as? String, podcast.feedUrl)
    fixture.time = Date(timeIntervalSince1970: 140)
    let pending = service.beginRefresh(feedURL: browse.feedUrl, podcast: browse)
    service.setEnabled(false, for: browse)
    service.completeRefresh(pending, episodes: [episode("disabled", at: 130)])
    XCTAssertEqual(center.requests.count, 1)
    XCTAssertTrue(center.pending.isEmpty)
    fixture.podcasts = []
    XCTAssertNil(service.beginRefresh(feedURL: browse.feedUrl, podcast: browse))
  }

  func testRefreshContextHandlesHTTPSUpgradeAndRejectsUnrelatedZeroID() {
    let saved = makePodcast("http://example.test/feed")
    fixture.podcasts = [saved]
    service.setEnabled(true, for: saved)
    XCTAssertNotNil(service.beginRefresh(feedURL: "https://example.test/feed", podcast: saved))
    let unrelated = makePodcast("https://example.test/other", trackId: 0)
    XCTAssertNil(service.beginRefresh(feedURL: unrelated.feedUrl, podcast: unrelated))
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

  func testAcceptedDiscoverySurvivesNewRefreshDuringAuthorization() {
    for newerSucceeds in [false, true] {
      service.setEnabled(false, for: podcast)
      center.deferAuthorization = true
      baseline()
      newRefresh()
      let committed = center.authorizations.removeFirst()
      let newer = service.beginRefresh(feedURL: podcast.feedUrl)
      if newerSucceeds {
        fixture.time.addTimeInterval(10)
        service.completeRefresh(newer, episodes: [episode("new", at: fixture.time.timeIntervalSince1970 - 20)])
      }
      // With no completion the newer request represents a failed refresh.
      XCTAssertNotNil(newer)
      let count = center.requests.count
      committed(.authorized)
      XCTAssertEqual(center.requests.count, count + 1)
      XCTAssertEqual(center.requests.last?.content.body, "Episode new")
      fixture.time.addTimeInterval(10)
      refresh([episode("new", at: fixture.time.timeIntervalSince1970 - 30)])
      XCTAssertTrue(center.authorizations.isEmpty)
    }
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

  func testSeenHistoryIsBoundedAndRecentGUIDsRemainDeduplicatedAfterRestart() throws {
    baseline()
    let limit = PodcastEpisodeNotificationService.retainedIdentityLimit
    for batch in 0...2 {
      fixture.time.addTimeInterval(20)
      refresh((0..<(limit * 2)).map { episode("history-\(batch)-\($0)", at: 50) })
      XCTAssertLessThanOrEqual(try storedSeenHistory().count, limit)
      XCTAssertTrue(center.requests.isEmpty)
    }
    fixture.time.addTimeInterval(20)
    let recent = episode("recent", at: fixture.time.timeIntervalSince1970 - 5)
    refresh([recent])
    XCTAssertEqual(center.requests.count, 1)
    XCTAssertTrue(try storedSeenHistory().contains(XCTUnwrap(PodcastEpisodeNotificationService.identity(recent))))
    service = makeService()
    fixture.time.addTimeInterval(20)
    refresh([episode("recent", at: fixture.time.timeIntervalSince1970 - 5)]) // Same GUID with edited date.
    XCTAssertEqual(center.requests.count, 1)
    XCTAssertLessThanOrEqual(try storedSeenHistory().count, limit)
    XCTAssertLessThan(try XCTUnwrap(defaults.data(forKey: UserDefaults.podcastNotificationPreferencesKey)).count, 200_000)
  }

  func testOversizedLegacySeenArraysCompactOnceDuringStartup() throws {
    baseline()
    let limit = PodcastEpisodeNotificationService.retainedIdentityLimit
    var store = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(defaults.data(forKey: UserDefaults.podcastNotificationPreferencesKey))) as? [String: Any])
    var preferences = try storedPreferences()
    var legacy = try XCTUnwrap(preferences[podcast.feedUrl] as? [String: Any])
    legacy["seen"] = (0..<(limit * 2)).compactMap { PodcastEpisodeNotificationService.identity(episode("legacy-\($0)", at: 50)) }
    preferences[podcast.feedUrl] = legacy
    store["preferences"] = preferences
    defaults.set(try JSONSerialization.data(withJSONObject: store), forKey: UserDefaults.podcastNotificationPreferencesKey)
    service = makeService()
    XCTAssertTrue(service.isEnabled(for: podcast))
    XCTAssertEqual(try storedSeenHistory().count, limit)
    let compacted = defaults.data(forKey: UserDefaults.podcastNotificationPreferencesKey)
    service = makeService()
    XCTAssertEqual(defaults.data(forKey: UserDefaults.podcastNotificationPreferencesKey), compacted)
  }

  func testKnownRequestCancellationDoesNotWaitForPendingLookup() {
    center.deferPendingLookup = true
    center.deferPrefixRemoval = true
    for action in 0...2 {
      baseline()
      newRefresh()
      XCTAssertEqual(center.pending.count, 1)
      if action == 0 {
        service.setEnabled(false, for: podcast)
      } else if action == 1 {
        fixture.podcasts = []
        service.subscriptionRemoved(podcast)
        fixture.podcasts = [podcast]
      } else {
        defaults.set(false, forKey: UserDefaults.notificationsEnabledKey)
        service.globalPreferenceDidChange()
      }
      XCTAssertTrue(center.pending.isEmpty)
      XCTAssertTrue(center.pendingLookups.isEmpty)
      XCTAssertTrue(center.prefixRemovals.isEmpty)
    }
  }

  func testPersistedIdentifiersAllowDirectCancellationAfterRestart() throws {
    baseline()
    newRefresh()
    let identifier = try XCTUnwrap(center.requests.last?.identifier)
    XCTAssertEqual(try storedIdentifiers(), [identifier])
    center.deferPendingLookup = true
    center.deferPrefixRemoval = true
    service = makeService()
    service.setEnabled(false, for: podcast)
    XCTAssertTrue(center.pending.isEmpty)
    XCTAssertTrue(center.pendingLookups.isEmpty)
    XCTAssertTrue(center.prefixRemovals.isEmpty)
  }

  func testIdentifierPruningPreservesSubmissionsNewerThanSnapshot() throws {
    baseline()
    newRefresh()
    center.pending.removeAll() // OS already delivered this completed request.
    center.deferPendingLookup = true
    let refresh = service.beginRefresh(feedURL: podcast.feedUrl)
    let finishLookup = center.pendingLookups.removeFirst()
    fixture.time = Date(timeIntervalSince1970: 140)
    service.completeRefresh(refresh, episodes: [episode("later", at: 130)])
    let replacement = try XCTUnwrap(center.requests.last)
    finishLookup([]) // Snapshot predates replacement submission.
    XCTAssertEqual(try storedIdentifiers(), [replacement.identifier])
    XCTAssertEqual(Set(center.pending.keys), [replacement.identifier])
    service.setEnabled(false, for: podcast)
    XCTAssertTrue(center.pending.isEmpty)
  }

  func testInFlightIdentifiersAreNotPrunedBeforeAddCompletion() throws {
    baseline()
    center.deferAdd = true
    center.deferPendingLookup = true
    newRefresh()
    let identifier = try XCTUnwrap(center.requests.last?.identifier)
    _ = service.beginRefresh(feedURL: podcast.feedUrl)
    XCTAssertTrue(center.pendingLookups.isEmpty)
    XCTAssertEqual(try storedIdentifiers(), [identifier])
    service.setEnabled(false, for: podcast)
    XCTAssertTrue(center.removals.contains(identifier))
    center.additions.removeFirst()()
    XCTAssertTrue(center.pending.isEmpty)
  }

  func testUnconfirmedIdentifiersSurviveRestartAndRemainDirectlyCancellable() throws {
    baseline()
    center.deferAdd = true
    newRefresh()
    let identifier = try XCTUnwrap(center.requests.last?.identifier)
    service = makeService()
    center.deferPendingLookup = true
    _ = service.beginRefresh(feedURL: podcast.feedUrl)
    XCTAssertTrue(center.pendingLookups.isEmpty)
    XCTAssertEqual(try storedIdentifiers(), [identifier])
    center.additions.removeFirst()()
    XCTAssertEqual(Set(center.pending.keys), [identifier])
    service.setEnabled(false, for: podcast)
    XCTAssertTrue(center.pending.isEmpty)
    XCTAssertTrue(center.pendingLookups.isEmpty)
  }

  func testLegacyUnknownIdentifiersUseFallbackAlongsideDirectNewRemoval() throws {
    baseline()
    newRefresh()
    let old = try XCTUnwrap(center.requests.last)
    var store = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(defaults.data(forKey: UserDefaults.podcastNotificationPreferencesKey))) as? [String: Any])
    var preferences = try storedPreferences()
    var legacy = try XCTUnwrap(preferences[podcast.feedUrl] as? [String: Any])
    legacy.removeValue(forKey: "submittedIdentifiers")
    legacy.removeValue(forKey: "unconfirmedIdentifiers")
    legacy.removeValue(forKey: "hasUntrackedRequests")
    preferences[podcast.feedUrl] = legacy
    store["preferences"] = preferences
    defaults.set(try JSONSerialization.data(withJSONObject: store), forKey: UserDefaults.podcastNotificationPreferencesKey)
    service = makeService()
    center.deferPrefixRemoval = true
    fixture.time = Date(timeIntervalSince1970: 140)
    refresh([episode("later", at: 130)])
    service.setEnabled(false, for: podcast)
    XCTAssertEqual(Set(center.pending.keys), [old.identifier])
    XCTAssertEqual(center.prefixRemovals.count, 1)
    center.prefixRemovals.removeFirst()()
    XCTAssertTrue(center.pending.isEmpty)
  }

  func testInvalidStoreRecoveryCancelsOnlyAppOwnedPendingAlerts() throws {
    let unrelated = UNNotificationRequest(identifier: "unrelated.reminder", content: UNMutableNotificationContent(), trigger: nil)
    center.pending[unrelated.identifier] = unrelated
    for data in [Data("corrupt".utf8), Data("{\"version\":99,\"globalEnabled\":true,\"preferences\":{}}".utf8)] {
      baseline()
      newRefresh()
      XCTAssertEqual(center.pending.count, 2)
      defaults.set(data, forKey: UserDefaults.podcastNotificationPreferencesKey)
      service = makeService()
      XCTAssertFalse(service.isEnabled(for: podcast))
      XCTAssertTrue(defaults.bool(forKey: UserDefaults.notificationsEnabledKey))
      XCTAssertEqual(Set(center.pending.keys), [unrelated.identifier])
      XCTAssertTrue(try storedPreferences().isEmpty)
    }
  }

  func testDelayedInvalidStoreCleanupPreservesReplacementGeneration() throws {
    baseline()
    newRefresh()
    let old = try XCTUnwrap(center.requests.last)
    center.deferPendingLookup = true
    defaults.set(Data("corrupt".utf8), forKey: UserDefaults.podcastNotificationPreferencesKey)
    service = makeService()
    XCTAssertEqual(center.pendingLookups.count, 1)
    baseline()
    newRefresh()
    let replacement = try XCTUnwrap(center.requests.last)
    XCTAssertNotEqual(old.identifier, replacement.identifier)
    let finishLookup = center.pendingLookups.removeFirst()
    finishLookup(Array(center.pending.values))
    XCTAssertEqual(Set(center.pending.keys), [replacement.identifier])
    XCTAssertTrue(service.shouldPresent(replacement))
    service = makeService()
    XCTAssertTrue(service.isEnabled(for: podcast))
    XCTAssertTrue(center.pendingLookups.isEmpty)
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

  private func storedSeenHistory() throws -> [String] {
    let preference = try XCTUnwrap(try storedPreferences()[podcast.feedUrl] as? [String: Any])
    return try XCTUnwrap(preference["seen"] as? [String])
  }

  private func storedIdentifiers() throws -> Set<String> {
    let preference = try XCTUnwrap(try storedPreferences()[podcast.feedUrl] as? [String: Any])
    return Set(try XCTUnwrap(preference["submittedIdentifiers"] as? [String]))
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

  func testRFC822DatesWithoutSecondsHaveKnownPublicationTimes() throws {
    let expected = try XCTUnwrap(ISO8601DateFormatter().date(from: "2002-10-02T08:00:00Z"))
    for date in ["Wed, 02 Oct 2002 08:00 +0000", "Wed, 2 Oct 2002 08:00 +0000",
                 "02 Oct 2002 08:00 +0000", "2 Oct 2002 10:00 +0200", "Wed, 2 Oct 2002 08:00 GMT"] {
      let item = try XCTUnwrap(parse("<title>Valid</title><pubDate>\(date)</pubDate>").episodes.first)
      XCTAssertEqual(item.notificationPublicationDate, expected, date)
      XCTAssertEqual(item.publicationDateIsKnown, true)
    }
  }

  func testRFC822TwoDigitYearsUseFixedCenturyRules() throws {
    for (shortYear, fullYear) in [("00", "2000"), ("26", "2026"), ("49", "2049"), ("50", "1950"), ("99", "1999")] {
      let expected = try XCTUnwrap(ISO8601DateFormatter().date(from: "\(fullYear)-10-02T08:00:00Z"))
      for date in ["2 Oct \(shortYear) 08:00 +0000", "02 Oct \(shortYear) 10:00:00 +0200"] {
        let item = try XCTUnwrap(parse("<title>Valid</title><pubDate>\(date)</pubDate>").episodes.first)
        XCTAssertEqual(item.notificationPublicationDate, expected, date)
      }
    }
    let expected = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-02T08:00:00Z"))
    for date in ["Fri, 2 Oct 26 08:00 GMT", "Fri, 02 Oct 26 08:00:00 +0000", "2 Oct 2026 08:00 +0000", "2026-10-02T08:00:00Z"] {
      XCTAssertEqual(try parse("<title>Valid</title><pubDate>\(date)</pubDate>").episodes.first?.notificationPublicationDate, expected, date)
    }
    let distant = try XCTUnwrap(ISO8601DateFormatter().date(from: "2050-10-02T08:00:00Z"))
    XCTAssertEqual(try parse("<title>Valid</title><pubDate>2 Oct 2050 08:00 +0000</pubDate>").episodes.first?.notificationPublicationDate, distant)
  }

  func testRFC822NamedZonesUseFixedOffsetsWithBothYearFormats() throws {
    let utc = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-02T08:00:00Z"))
    for (zone, hours) in [("UT", 0), ("GMT", 0), ("EST", 5), ("EDT", 4), ("CST", 6),
                          ("CDT", 5), ("MST", 7), ("MDT", 6), ("PST", 8), ("PDT", 7)] {
      for date in ["Fri, 02 Oct 2026 08:00:00 \(zone)", "2 Oct 26 08:00 \(zone)"] {
        let item = try XCTUnwrap(parse("<title>Named zone</title><pubDate>\(date)</pubDate>").episodes.first)
        XCTAssertEqual(item.notificationPublicationDate, utc.addingTimeInterval(Double(hours) * 3600), date)
        XCTAssertEqual(item.publicationDateIsKnown, true)
      }
    }
    XCTAssertNil(try parse("<title>Unknown zone</title><pubDate>2 Oct 26 08:00 UNKNOWN</pubDate>").episodes.first?.notificationPublicationDate)
  }

  func testRFC822MilitaryZonesUseLegacyRSSOffsetsAndRejectJ() throws {
    let utc = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-02T08:00:00Z"))
    let zones = [("A", 1), ("B", 2), ("C", 3), ("D", 4), ("E", 5), ("F", 6),
                 ("G", 7), ("H", 8), ("I", 9), ("K", 10), ("L", 11), ("M", 12),
                 ("N", -1), ("O", -2), ("P", -3), ("Q", -4), ("R", -5), ("S", -6),
                 ("T", -7), ("U", -8), ("V", -9), ("W", -10), ("X", -11), ("Y", -12), ("Z", 0)]
    for (zone, hours) in zones {
      for date in ["Fri, 02 Oct 2026 08:00:00 \(zone)", "2 Oct 26 08:00 \(zone.lowercased())"] {
        let item = try XCTUnwrap(parse("<title>Military zone</title><pubDate>\(date)</pubDate>").episodes.first)
        XCTAssertEqual(item.notificationPublicationDate, utc.addingTimeInterval(Double(hours) * 3600), date)
        XCTAssertEqual(item.publicationDateIsKnown, true)
      }
    }
    XCTAssertNil(try parse("<title>Unused zone</title><pubDate>2 Oct 26 08:00 J</pubDate>").episodes.first?.notificationPublicationDate)
  }

  func testParserRejectsNonRSSDocumentsAndAllowsEmptyChannels() throws {
    let parser = PodcastFeedParser()
    for xml in ["<error/>", "<html><body>Unavailable</body></html>", "<rss/>",
                "<wrapper><rss><channel/></rss></wrapper>", "<rss><channel/><channel/></rss>"] {
      XCTAssertThrowsError(try parser.parse(data: Data(xml.utf8)), xml)
    }
    XCTAssertTrue(try parser.parse(data: Data("<rss><channel/></rss>".utf8)).episodes.isEmpty)
  }

  func testRSS1RDFParsesSiblingItemsAndAlternateNamespacePrefixes() throws {
    for (rdf, rss) in [("rdf", ""), ("graph", "rss:")] {
      let rssNamespace = rss.isEmpty ? "xmlns='http://purl.org/rss/1.0/'" : "xmlns:rss='http://purl.org/rss/1.0/'"
      let xml = """
      <\(rdf):RDF xmlns:\(rdf)='http://www.w3.org/1999/02/22-rdf-syntax-ns#' \(rssNamespace)>
      <\(rss)channel><\(rss)description>RDF feed</\(rss)description></\(rss)channel>
      <\(rss)item><\(rss)title>RDF episode</\(rss)title><\(rss)guid>rdf-guid</\(rss)guid>
      <\(rss)pubDate>Wed, 02 Oct 2002 08:00 +0000</\(rss)pubDate>
      <\(rss)enclosure url='https://example.test/rdf.mp3'/></\(rss)item></\(rdf):RDF>
      """
      let feed = try PodcastFeedParser().parse(data: Data(xml.utf8))
      XCTAssertEqual(feed.description, "RDF feed")
      let episode = try XCTUnwrap(feed.episodes.first)
      XCTAssertEqual(feed.episodes.count, 1)
      XCTAssertEqual(episode.title, "RDF episode")
      XCTAssertEqual(episode.guid, "rdf-guid")
      XCTAssertEqual(episode.streamUrl, "https://example.test/rdf.mp3")
      XCTAssertNotNil(episode.notificationPublicationDate)
    }
    for xml in ["<rdf:RDF xmlns:rdf='urn:unrelated'><channel/><item><title>Invalid</title></item></rdf:RDF>",
                "<rdf:RDF xmlns:rdf='http://www.w3.org/1999/02/22-rdf-syntax-ns#'><channel/></rdf:RDF>"] {
      XCTAssertThrowsError(try PodcastFeedParser().parse(data: Data(xml.utf8)))
    }
  }

  func testRSS1DublinCoreDatesCreateReliableMetadataIdentities() throws {
    for prefix in ["dc", "metadata"] {
      for (value, expectedValue) in [("2002-10-02T08:00:00Z", "2002-10-02T08:00:00Z"),
                                     ("2002-10-02T10:00+02:00", "2002-10-02T08:00:00Z"),
                                     ("2002-10-02", "2002-10-02T00:00:00Z")] {
        let xml = """
        <rdf:RDF xmlns:rdf='http://www.w3.org/1999/02/22-rdf-syntax-ns#' xmlns='http://purl.org/rss/1.0/' xmlns:\(prefix)='http://purl.org/dc/elements/1.1/'>
        <channel/><item><title>DC episode</title><link>https://example.test/item</link>
        <\(prefix):date>\(value)</\(prefix):date><\(prefix):creator>Author</\(prefix):creator></item></rdf:RDF>
        """
        let item = try XCTUnwrap(PodcastFeedParser().parse(data: Data(xml.utf8)).episodes.first)
        XCTAssertNil(item.guid)
        XCTAssertTrue(item.streamUrl.isEmpty)
        XCTAssertEqual(item.author, "Author")
        XCTAssertEqual(item.notificationPublicationDate, ISO8601DateFormatter().date(from: expectedValue))
        XCTAssertNotNil(PodcastEpisodeNotificationService.identity(item))
      }
    }
    for (uri, value) in [("urn:unrelated", "2002-10-02T08:00:00Z"),
                         ("http://purl.org/dc/elements/1.1/", "invalid"),
                         ("http://purl.org/dc/elements/1.1/", "2002"),
                         ("http://purl.org/dc/elements/1.1/", "2002-10") ] {
      let xml = "<rdf:RDF xmlns:rdf='http://www.w3.org/1999/02/22-rdf-syntax-ns#' xmlns='http://purl.org/rss/1.0/' xmlns:dc='\(uri)'><channel/><item><title>Invalid date</title><dc:date>\(value)</dc:date></item></rdf:RDF>"
      let item = try XCTUnwrap(PodcastFeedParser().parse(data: Data(xml.utf8)).episodes.first)
      XCTAssertNil(item.notificationPublicationDate)
      XCTAssertNil(PodcastEpisodeNotificationService.identity(item))
    }
  }

  func testNamespaceProcessingPreservesRSS2ITunesMetadata() throws {
    let xml = """
    <rss xmlns:itunes='http://www.itunes.com/dtds/podcast-1.0.dtd'><channel>
    <itunes:image href='https://example.test/feed.jpg'/><item><title>Episode</title>
    <itunes:author>Author</itunes:author><itunes:subtitle>Subtitle</itunes:subtitle>
    <itunes:duration>01:30</itunes:duration><itunes:image href='https://example.test/episode.jpg'/>
    </item></channel></rss>
    """
    let feed = try PodcastFeedParser().parse(data: Data(xml.utf8))
    let episode = try XCTUnwrap(feed.episodes.first)
    XCTAssertEqual(feed.imageUrl, "https://example.test/feed.jpg")
    XCTAssertEqual(episode.imageUrl, "https://example.test/episode.jpg")
    XCTAssertEqual(episode.author, "Author")
    XCTAssertEqual(episode.description, "Subtitle")
    XCTAssertEqual(episode.duration, 90)
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
  static var headers = [String: String]()
  static var requests = [URLRequest]()
  private static let lock = NSLock()

  override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "feed-alert-tests.invalid" }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    Self.lock.lock()
    let result = Self.responses.removeFirst()
    let headers = Self.headers
    Self.requests.append(request)
    Self.lock.unlock()
    switch result {
    case .success(let data):
      client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: headers)!, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: data)
      client?.urlProtocolDidFinishLoading(self)
    case .failure(let error):
      client?.urlProtocol(self, didFailWithError: error)
    }
  }

  override func stopLoading() {}
}

final class PodcastNotificationRefreshTests: XCTestCase {
  override func tearDown() {
    StubAlertFeedProtocol.responses = []
    StubAlertFeedProtocol.headers = [:]
    StubAlertFeedProtocol.requests = []
    super.tearDown()
  }

  func testChangedBrowseURLNetworkRefreshEstablishesSavedBaselineAndAlerts() throws {
    try withNetworking { networking, _, center, fixture, saved in
      let browse = Podcast(trackId: saved.trackId, trackName: saved.trackName, trackCount: 0,
        artistName: saved.artistName, artworkUrl100: "", feedUrl: "https://feed-alert-tests.invalid/changed")
      let url = try XCTUnwrap(URL(string: browse.feedUrl))
      load(networking, url: url, podcast: browse, guid: "baseline", timestamp: 50)
      XCTAssertTrue(center.requests.isEmpty)
      fixture.time = Date(timeIntervalSince1970: 120)
      load(networking, url: url, podcast: browse, guid: "new", timestamp: 110)
      XCTAssertEqual(center.requests.count, 1)
      XCTAssertEqual(center.requests.first?.content.userInfo["feedURL"] as? String, saved.feedUrl)
      XCTAssertEqual(StubAlertFeedProtocol.requests.map { $0.url }, [url, url])
      XCTAssertTrue(StubAlertFeedProtocol.requests.allSatisfy { $0.cachePolicy == .reloadIgnoringLocalCacheData })
    }
  }

  func testCachedHTTPResponseDoesNotSkipEpisodesMissingFromSnapshot() throws {
    try withNetworking { networking, _, center, fixture, podcast in
      let url = try XCTUnwrap(URL(string: podcast.feedUrl))
      load(networking, url: url, podcast: podcast, guid: "baseline", timestamp: 50)
      fixture.time = Date(timeIntervalSince1970: 140)
      StubAlertFeedProtocol.headers = ["Date": "Thu, 01 Jan 1970 00:01:50 GMT", "Age": "30"]
      load(networking, url: url, podcast: podcast, guid: "baseline", timestamp: 50)
      XCTAssertTrue(center.requests.isEmpty)
      fixture.time = Date(timeIntervalSince1970: 160)
      StubAlertFeedProtocol.headers = [:]
      load(networking, url: url, podcast: podcast, guid: "after-cache", timestamp: 130)
      XCTAssertEqual(center.requests.count, 1)
      XCTAssertEqual(center.requests.first?.content.body, "Stub after-cache")
    }
  }

  func testNamedZoneNetworkRefreshDiscoversAnEligibleEpisode() throws {
    try withNetworking { networking, _, center, fixture, podcast in
      let url = try XCTUnwrap(URL(string: podcast.feedUrl))
      load(networking, url: url, podcast: podcast, guid: "baseline", timestamp: 50)
      fixture.time = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-02T13:01:00Z"))
      load(networking, url: url, podcast: podcast, guid: "named-zone", publicationDate: "Fri, 2 Oct 26 08:00 EST")
      XCTAssertEqual(center.requests.count, 1)
      XCTAssertEqual(center.requests.first?.content.body, "Stub named-zone")
    }
  }

  func testMilitaryZoneNetworkRefreshDiscoversAnEligibleEpisode() throws {
    try withNetworking { networking, _, center, fixture, podcast in
      let url = try XCTUnwrap(URL(string: podcast.feedUrl))
      load(networking, url: url, podcast: podcast, guid: "baseline", timestamp: 50)
      fixture.time = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-02T09:01:00Z"))
      load(networking, url: url, podcast: podcast, guid: "military-zone", publicationDate: "Fri, 2 Oct 26 08:00 A")
      XCTAssertEqual(center.requests.count, 1)
      XCTAssertEqual(center.requests.first?.content.body, "Stub military-zone")
    }
  }

  private func withNetworking(_ body: (NetworkingService, PodcastEpisodeNotificationService, RecordingAlertCenter, AlertFixtures, Podcast) throws -> Void) throws {
    let suite = "Castify.NotificationRefreshTests." + UUID().uuidString
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
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
    try body(NetworkingService(notificationService: service, feedSession: session), service, center, fixture, podcast)
  }

  private func load(_ networking: NetworkingService, url: URL, podcast: Podcast, guid: String, timestamp: TimeInterval = 0, publicationDate: String? = nil) {
    let date = publicationDate ?? ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: timestamp))
    let xml = "<rss><channel><item><title>Stub \(guid)</title><guid>\(guid)</guid><pubDate>\(date)</pubDate></item></channel></rss>"
    StubAlertFeedProtocol.responses = [.success(Data(xml.utf8))]
    let loaded = expectation(description: "Feed \(guid)")
    networking.fetchPodcastFeed(url: url, podcast: podcast) { result in
      if case .failure(let error) = result { XCTFail("Unexpected feed failure: \(error)") }
      loaded.fulfill()
    }
    wait(for: [loaded], timeout: 5)
  }

  func testSuccessfulNetworkRefreshParsesIdentityAndSchedulesOnlyAfterBaseline() throws {
    try verifyRefreshes(firstFails: false)
  }

  func testFailedNetworkRefreshDoesNotAnnounceFirstSuccessfulSnapshot() throws {
    try verifyRefreshes(firstFails: true)
  }

  func testInvalidXMLPayloadCannotEstablishOrAdvanceNotificationBaseline() throws {
    try verifyRefreshes(firstFails: true, invalidPayload: true)
  }

  func testRSS1NetworkRefreshPreservesEpisodeLoadingAndAlertDiscovery() throws {
    try verifyRefreshes(firstFails: false, rss1: true)
  }

  func testRSS1DublinCoreNetworkRefreshAlertsWithoutGUIDOrEnclosure() throws {
    try verifyRefreshes(firstFails: false, rss1: true, dublinCore: true)
  }

  private func verifyRefreshes(firstFails: Bool, invalidPayload: Bool = false, rss1: Bool = false, dublinCore: Bool = false) throws {
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
      StubAlertFeedProtocol.responses = invalidPayload ? [.success(Data("<error/>".utf8))] :
        [.failure(NSError(domain: "stub-feed", code: 1))]
      let failed = expectation(description: "Feed error")
      networking.fetchPodcastFeed(url: url) { result in
        if case .success = result { XCTFail("Expected stubbed error") }
        failed.fulfill()
      }
      wait(for: [failed], timeout: 5)
    }
    for (guid, timestamp) in [("baseline", 50.0), ("new", 110.0)] {
      fixture.time = Date(timeIntervalSince1970: guid == "baseline" ? 100 : 120)
      if invalidPayload && guid == "new" {
        fixture.time = Date(timeIntervalSince1970: 150)
        StubAlertFeedProtocol.responses = [.success(Data("<error/>".utf8))]
        let rejected = expectation(description: "Invalid document after baseline")
        networking.fetchPodcastFeed(url: url) { result in
          if case .success = result { XCTFail("Expected invalid RSS rejection") }
          rejected.fulfill()
        }
        wait(for: [rejected], timeout: 5)
        fixture.time = Date(timeIntervalSince1970: 160)
      }
      let date = ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: timestamp))
      let item = dublinCore ? "<item><title>Stub \(guid)</title><link>https://feed-alert-tests.invalid/\(guid)</link><dc:date>\(date)</dc:date></item>" :
        "<item><title>Stub \(guid)</title><guid>\(guid)</guid><pubDate>\(date)</pubDate><enclosure url='https://feed-alert-tests.invalid/\(guid).mp3'/></item>"
      let xml = rss1 ? "<rdf:RDF xmlns:rdf='http://www.w3.org/1999/02/22-rdf-syntax-ns#' xmlns='http://purl.org/rss/1.0/' xmlns:dc='http://purl.org/dc/elements/1.1/'><channel/>\(item)</rdf:RDF>" :
        "<rss><channel>\(item)</channel></rss>"
      StubAlertFeedProtocol.responses = [.success(Data(xml.utf8))]
      let loaded = expectation(description: "Feed success")
      networking.fetchPodcastFeed(url: url) { result in
        if case .success(let feed) = result {
          if dublinCore {
            XCTAssertNil(feed.episodes.first?.guid)
            XCTAssertNotNil(feed.episodes.first.flatMap(PodcastEpisodeNotificationService.identity))
          } else { XCTAssertEqual(feed.episodes.first?.guid, guid) }
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
