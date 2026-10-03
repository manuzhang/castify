import AVFoundation
import MediaPlayer
import SwiftUI
import UIKit
import XCTest
@testable import Castify

private final class TimerClock {
  var time: TimeInterval = 100
}

private final class TimerScheduler {
  var callbacks: [() -> Void] = []
  var cancelled: Set<Int> = []

  func schedule(_ callback: @escaping () -> Void) -> (() -> Void) {
    let index = callbacks.count
    callbacks.append(callback)
    return { [weak self] in self?.cancelled.insert(index) }
  }

  // Deliberately deliver cancelled callbacks to exercise late delivery.
  func fire(_ index: Int? = nil) {
    callbacks[index ?? callbacks.count - 1]()
  }
}

final class PlayerSleepTimerEngineTests: XCTestCase {
  private var clock: TimerClock!
  private var scheduler: TimerScheduler!
  private var timer: PlayerSleepTimer!
  private var remaining: TimeInterval?
  private var expirations = 0

  override func setUp() {
    super.setUp()
    clock = TimerClock()
    scheduler = TimerScheduler()
    timer = PlayerSleepTimer(now: { [clock] in clock!.time }, schedule: scheduler.schedule)
    timer.onUpdate = { [weak self] _, remaining in self?.remaining = remaining }
    timer.onExpiry = { [weak self] in self?.expirations += 1 }
  }

  func testEveryPresetUsesElapsedRealSeconds() {
    for duration in SleepTimerDuration.allCases {
      timer.start(duration)
      XCTAssertEqual(remaining, TimeInterval(duration.rawValue * 60))
      clock.time += 10
      scheduler.fire()
      XCTAssertEqual(remaining, duration.seconds - 10)
    }
    XCTAssertEqual(expirations, 0)
  }

  func testCountdownRoundsUpAndExpiresAtExactDeadlineOnlyOnce() {
    timer.start(.fifteenMinutes)
    clock.time += 899.2
    scheduler.fire()
    XCTAssertEqual(remaining, 1)
    XCTAssertEqual(expirations, 0)
    clock.time += 0.8
    XCTAssertTrue(timer.reconcile())
    XCTAssertNil(remaining)
    XCTAssertEqual(expirations, 1)
    XCTAssertTrue(scheduler.cancelled.contains(0))
    scheduler.fire(0)
    XCTAssertFalse(timer.reconcile())
    XCTAssertEqual(expirations, 1)
  }

  func testCancellationInvalidatesAlreadyQueuedTicks() {
    timer.start(.fifteenMinutes)
    timer.cancel()
    clock.time += 1000
    scheduler.fire(0)
    XCTAssertNil(remaining)
    XCTAssertEqual(expirations, 0)
    XCTAssertTrue(scheduler.cancelled.contains(0))
  }

  func testReplacementIgnoresOldDeadlineAndStartsFullNewDuration() {
    timer.start(.fifteenMinutes)
    clock.time += 800
    timer.start(.thirtyMinutes)
    clock.time += 100
    scheduler.fire(0)
    XCTAssertEqual(remaining, 1800)
    XCTAssertEqual(expirations, 0)
    scheduler.fire(1)
    XCTAssertEqual(remaining, 1700)
    clock.time += 1700
    scheduler.fire(1)
    XCTAssertEqual(expirations, 1)
    XCTAssertNil(remaining)
  }

  func testRepeatedStartCancelAndExpireCyclesRemainIndependent() {
    for _ in 0..<3 {
      timer.start(.fifteenMinutes)
      timer.cancel()
      timer.start(.fortyFiveMinutes)
      clock.time += 2700
      scheduler.fire()
    }
    for index in scheduler.callbacks.indices { scheduler.fire(index) }
    XCTAssertEqual(expirations, 3)
    XCTAssertEqual(scheduler.cancelled.count, 6)
  }

  func testDeinitializationCancelsScheduledWork() {
    timer.start(.sixtyMinutes)
    weak var weakTimer = timer
    timer = nil
    XCTAssertNil(weakTimer)
    XCTAssertTrue(scheduler.cancelled.contains(0))
    scheduler.fire(0)
    XCTAssertEqual(expirations, 0)
  }

  func testSynchronousSchedulerExpiryStillCancelsReturnedSubscription() {
    var cancelled = false
    let timer = PlayerSleepTimer(now: { self.clock.time }, schedule: { callback in
      self.clock.time += 900
      callback()
      return { cancelled = true }
    })
    timer.onExpiry = { self.expirations += 1 }
    timer.start(.fifteenMinutes)
    XCTAssertEqual(expirations, 1)
    XCTAssertTrue(cancelled)
  }

  func testReplacementDuringInitialPublicationCannotScheduleObsoleteTimer() {
    timer.onUpdate = { [weak self] duration, remaining in
      self?.remaining = remaining
      if duration == .fifteenMinutes { self?.timer.start(.thirtyMinutes) }
    }
    timer.start(.fifteenMinutes)
    XCTAssertEqual(scheduler.callbacks.count, 1)
    XCTAssertEqual(remaining, 1800)
  }

  func testReplacementDuringExpiryPublicationCannotExpireNewTimer() {
    timer.start(.fifteenMinutes)
    timer.onUpdate = { [weak self] duration, remaining in
      self?.remaining = remaining
      if duration == nil { self?.timer.start(.sixtyMinutes) }
    }
    clock.time += 900
    scheduler.fire(0)
    XCTAssertEqual(expirations, 0)
    XCTAssertEqual(remaining, 3600)
    scheduler.fire(0)
    XCTAssertEqual(remaining, 3600)
  }

  func testCancellationDuringExpiryPublicationSuppressesObsoleteExpiry() {
    timer.start(.fifteenMinutes)
    var cancelled = false
    timer.onUpdate = { [weak self] duration, remaining in
      self?.remaining = remaining
      if duration == nil && !cancelled {
        cancelled = true
        self?.timer.cancel()
      }
    }
    clock.time += 900
    scheduler.fire(0)
    XCTAssertEqual(expirations, 0)
    XCTAssertNil(remaining)
  }

  func testProductionRunLoopSchedulerReconcilesDeadline() {
    let timer = PlayerSleepTimer(now: { self.clock.time })
    let expired = expectation(description: "Production timer tick")
    timer.onExpiry = { expired.fulfill() }
    timer.start(.fifteenMinutes)
    clock.time += 900
    wait(for: [expired], timeout: 3)
  }
}

final class PlayerSleepTimerTests: XCTestCase {
  private var defaults: UserDefaults!
  private var suiteName: String!
  private var clock: TimerClock!
  private var scheduler: TimerScheduler!
  private var notifications: NotificationCenter!
  private var avPlayer: AVPlayer!
  private var player: Player!
  private var service: PodcastsService!
  private var audioURL: URL!
  private var episodes: [Episode] = []
  private var savedStats: Data?

  override func setUpWithError() throws {
    try super.setUpWithError()
    suiteName = "Castify.PlayerSleepTimerTests." + UUID().uuidString
    defaults = UserDefaults(suiteName: suiteName)
    savedStats = UserDefaults.standard.data(forKey: UserDefaults.listeningStatsKey)
    clock = TimerClock()
    scheduler = TimerScheduler()
    notifications = NotificationCenter()
    avPlayer = AVPlayer()
    service = PodcastsService()
    let timer = PlayerSleepTimer(now: { [clock] in clock!.time }, schedule: scheduler.schedule)
    player = Player(avPlayer: avPlayer, notificationCenter: notifications,
                    podcastsService: service, userDefaults: defaults, sleepTimer: timer)
    audioURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".caf")
    let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1))
    let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44100 * 60))
    buffer.frameLength = buffer.frameCapacity
    try XCTUnwrap(buffer.floatChannelData)[0].initialize(repeating: 0, count: Int(buffer.frameLength))
    do {
      let file = try AVAudioFile(forWriting: audioURL, settings: format.settings)
      try file.write(from: buffer)
    }
    episodes = ["First sleep timer episode", "Second sleep timer episode"].map {
      Episode(title: $0, author: "Castify Test", streamUrl: audioURL.absoluteString, duration: 60)
    }
    player.setup(for: episodes)
    waitUntilReady()
  }

  override func tearDownWithError() throws {
    player?.pause()
    player?.cancelSleepTimer()
    avPlayer?.replaceCurrentItem(with: nil)
    player = nil
    try? FileManager.default.removeItem(at: audioURL)
    defaults.removePersistentDomain(forName: suiteName)
    UserDefaults.standard.set(savedStats, forKey: UserDefaults.listeningStatsKey)
    try super.tearDownWithError()
  }

  func testStartingReplacingAndCancellingWhileIdleDoesNotStartAudio() {
    player.setSleepTimer(.sixtyMinutes)
    XCTAssertEqual(player.sleepTimerCountdown, "60:00")
    player.setSleepTimer(.thirtyMinutes)
    XCTAssertEqual(player.sleepTimerDuration, .thirtyMinutes)
    XCTAssertEqual(player.sleepTimerCountdown, "30:00")
    player.cancelSleepTimer()
    XCTAssertNil(player.sleepTimerRemaining)
    XCTAssertNil(player.sleepTimerCountdown)
    XCTAssertNil(player.sleepTimerDuration)
    XCTAssertFalse(player.isPlaying)
    XCTAssertEqual(avPlayer.rate, 0)
  }

  func testExpiryUsesPausePositionStatisticsAndNowPlayingPaths() {
    player.setPlaybackSpeed(.double)
    let initialStats = service.listeningStats.totalListeningTime
    player.play()
    // The app deliberately stores no resume position below five seconds.
    waitUntilElapsed(6)
    player.setSleepTimer(.fifteenMinutes)
    clock.time += 900
    scheduler.fire()
    XCTAssertFalse(player.isPlaying)
    XCTAssertEqual(avPlayer.rate, 0)
    XCTAssertEqual(player.current, episodes[0])
    XCTAssertEqual(player.playbackSpeed, .double)
    XCTAssertNil(player.sleepTimerRemaining)
    XCTAssertEqual(service.playbackState(for: episodes[0])?.position ?? -1, player.elapsedTime, accuracy: 0.1)
    XCTAssertEqual(service.listeningStats.totalListeningTime - initialStats, player.elapsedTime / 2, accuracy: 0.1)
    XCTAssertEqual((MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackRate] as? NSNumber)?.floatValue, 0)
    let finalStats = service.listeningStats.totalListeningTime
    scheduler.fire()
    XCTAssertEqual(service.listeningStats.totalListeningTime, finalStats)
  }

  func testCountdownContinuesDuringManualPauseAndExpiresWithoutResuming() {
    player.play()
    player.setSleepTimer(.fifteenMinutes)
    player.pause()
    clock.time += 600
    scheduler.fire()
    XCTAssertEqual(player.sleepTimerCountdown, "05:00")
    clock.time += 300
    scheduler.fire()
    XCTAssertNil(player.sleepTimerRemaining)
    XCTAssertFalse(player.isPlaying)
    XCTAssertEqual(avPlayer.rate, 0)
  }

  func testSpeedChangesAndSeekDoNotChangeDeadline() {
    player.setSleepTimer(.fifteenMinutes)
    player.play()
    player.setPlaybackSpeed(.double)
    player.seek(toTime: 30)
    // Polling runs once per second; at 2x a successful playing seek has already
    // advanced beyond a one-second window. Unseeked playback cannot reach 30
    // during this ten-second wait, so the wider window still verifies the seek.
    let sought = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
      let position = self.avPlayer.currentTime().seconds
      return position >= 29 && position < 45
    }, object: nil)
    wait(for: [sought], timeout: 10)
    XCTAssertEqual(player.sleepTimerRemaining, 900)
    player.setPlaybackSpeed(.threeQuarters)
    clock.time += 100
    scheduler.fire()
    XCTAssertEqual(player.sleepTimerRemaining, 800)
    player.pause()
    player.seek(by: -15)
    XCTAssertEqual(player.sleepTimerRemaining, 800)
    clock.time += 800
    scheduler.fire()
    XCTAssertFalse(player.isPlaying)
    XCTAssertEqual(avPlayer.rate, 0)
  }

  func testEpisodeAndQueueChangesPreserveOriginalDeadline() {
    player.setSleepTimer(.thirtyMinutes)
    player.play()
    clock.time += 20
    player.next()
    XCTAssertEqual(player.current, episodes[1])
    XCTAssertEqual(player.sleepTimerRemaining, 1780)
    player.previous()
    player.play(episode: episodes[1], in: episodes, at: 10)
    player.playQueue(episodes.reversed())
    clock.time += 10
    scheduler.fire()
    XCTAssertEqual(player.sleepTimerRemaining, 1770)
    player.pause()
    player.updateQueue(episodes)
    XCTAssertEqual(player.sleepTimerDuration, .thirtyMinutes)
    clock.time += 1770
    scheduler.fire()
    XCTAssertFalse(player.isPlaying)
  }

  func testOverdueNavigationReconcilesBeforeChoosingAutoplay() {
    for navigate in [player.next, player.previous] {
      player.play()
      player.setSleepTimer(.fifteenMinutes)
      clock.time += 900
      navigate()
      XCTAssertFalse(player.isPlaying)
      XCTAssertEqual(avPlayer.rate, 0)
      XCTAssertNil(player.sleepTimerRemaining)
    }
  }

  func testOverdueAndLateEpisodeEndCallbacksCannotRestartPlayback() throws {
    player.play()
    player.setSleepTimer(.fifteenMinutes)
    let item = try XCTUnwrap(avPlayer.currentItem)
    clock.time += 900
    notifications.post(name: .AVPlayerItemDidPlayToEndTime, object: item)
    XCTAssertEqual(player.current, episodes[0])
    XCTAssertFalse(player.isPlaying)
    XCTAssertEqual(avPlayer.rate, 0)
    let delivered = expectation(description: "Late end delivered from another queue")
    DispatchQueue.global().async {
      self.notifications.post(name: .AVPlayerItemDidPlayToEndTime, object: item)
      DispatchQueue.main.async { delivered.fulfill() }
    }
    wait(for: [delivered], timeout: 3)
    XCTAssertEqual(player.current, episodes[0])
    XCTAssertFalse(player.isPlaying)
  }

  func testAutomaticQueueAdvanceRetainsTimerAndIgnoresOtherItems() throws {
    player.play()
    player.setSleepTimer(.fifteenMinutes)
    clock.time += 10
    notifications.post(name: .AVPlayerItemDidPlayToEndTime, object: AVPlayerItem(url: audioURL))
    XCTAssertEqual(player.current, episodes[0])
    notifications.post(name: .AVPlayerItemDidPlayToEndTime, object: try XCTUnwrap(avPlayer.currentItem))
    XCTAssertEqual(player.current, episodes[1])
    XCTAssertTrue(player.isPlaying)
    XCTAssertEqual(player.sleepTimerRemaining, 890)
    XCTAssertEqual(player.sleepTimerDuration, .fifteenMinutes)
  }

  func testReplacementCancellationAndExplicitPlayIgnoreLateTimerCallbacks() {
    player.play()
    player.setSleepTimer(.fifteenMinutes)
    clock.time += 800
    player.setSleepTimer(.thirtyMinutes)
    clock.time += 100
    scheduler.fire(0)
    XCTAssertTrue(player.isPlaying)
    XCTAssertEqual(player.sleepTimerRemaining, 1800)
    player.cancelSleepTimer()
    clock.time += 2000
    scheduler.fire(1)
    XCTAssertTrue(player.isPlaying)
    player.setSleepTimer(.fifteenMinutes)
    clock.time += 900
    scheduler.fire(2)
    XCTAssertFalse(player.isPlaying)
    player.setPlaybackSpeed(.oneAndAHalf)
    player.play()
    scheduler.fire(0)
    scheduler.fire(1)
    scheduler.fire(2)
    XCTAssertTrue(player.isPlaying)
    XCTAssertEqual(avPlayer.rate, 1.5)
    XCTAssertNil(player.sleepTimerRemaining)
  }

  func testLifecycleReconcilesMissedTicksOnBackgroundAndForeground() {
    player.play()
    player.setSleepTimer(.fifteenMinutes)
    clock.time += 600
    notifications.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
    XCTAssertEqual(player.sleepTimerRemaining, 300)
    clock.time += 320
    notifications.post(name: UIScene.willEnterForegroundNotification, object: nil)
    notifications.post(name: UIApplication.didBecomeActiveNotification, object: nil)
    XCTAssertNil(player.sleepTimerRemaining)
    XCTAssertFalse(player.isPlaying)
    XCTAssertEqual(avPlayer.rate, 0)
  }

  func testInterruptionBeforeDeadlineResumesAndPreservesTimerAndSpeed() {
    player.setPlaybackSpeed(.oneAndAHalf)
    player.play()
    player.setSleepTimer(.fifteenMinutes)
    postInterruption(.began)
    XCTAssertFalse(player.isPlaying)
    clock.time += 100
    postInterruption(.ended)
    XCTAssertTrue(player.isPlaying)
    XCTAssertEqual(avPlayer.rate, 1.5)
    XCTAssertEqual(player.sleepTimerRemaining, 800)
  }

  func testInterruptionEndingAfterMissedDeadlineCannotResumePlayback() {
    player.play()
    player.setSleepTimer(.fifteenMinutes)
    postInterruption(.began)
    clock.time += 910
    postInterruption(.ended)
    XCTAssertFalse(player.isPlaying)
    XCTAssertEqual(avPlayer.rate, 0)
    XCTAssertNil(player.sleepTimerRemaining)
    player.play()
    scheduler.fire(0)
    postInterruption(.ended)
    XCTAssertTrue(player.isPlaying)
  }

  func testManualPauseAndDeliveredExpirySuppressInterruptionResume() {
    player.play()
    postInterruption(.began)
    player.pause()
    postInterruption(.ended)
    XCTAssertFalse(player.isPlaying)
    XCTAssertEqual(avPlayer.rate, 0)

    player.play()
    player.setSleepTimer(.fifteenMinutes)
    postInterruption(.began)
    clock.time += 900
    scheduler.fire()
    postInterruption(.ended)
    XCTAssertFalse(player.isPlaying)
    XCTAssertEqual(avPlayer.rate, 0)
    XCTAssertNil(player.sleepTimerRemaining)
  }

  private func postInterruption(_ type: AVAudioSession.InterruptionType) {
    notifications.post(name: AVAudioSession.interruptionNotification, object: nil,
                       userInfo: [AVAudioSessionInterruptionTypeKey: NSNumber(value: type.rawValue)])
  }

  func testExplicitPlayAfterMissedDeadlineExpiresOldTimerThenResumesIntentionally() {
    player.setSleepTimer(.fifteenMinutes)
    clock.time += 910
    player.play(episode: episodes[1], in: episodes)
    XCTAssertTrue(player.isPlaying)
    XCTAssertEqual(player.current, episodes[1])
    XCTAssertNil(player.sleepTimerRemaining)
    scheduler.fire(0)
    XCTAssertTrue(player.isPlaying)
  }

  func testPlayerReleaseCancelsTimerAndNewPlayerDoesNotRestoreTimer() {
    player.setSleepTimer(.sixtyMinutes)
    weak var weakPlayer = player
    player = nil
    XCTAssertNil(weakPlayer)
    XCTAssertTrue(scheduler.cancelled.contains(0))
    let restored = Player(userDefaults: defaults)
    XCTAssertNil(restored.sleepTimerRemaining)
    scheduler.fire(0)
    XCTAssertFalse(restored.isPlaying)
  }

  func testNarrowPlayerRendersInactiveActiveAndExpiredInBothLanguages() {
    let localization = LocalizationService(userDefaults: defaults)
    for language in [AppLanguage.english, .chinese] {
      localization.setLanguage(language)
      XCTAssertEqual(String(format: localization.text(.sleepTimerMinutes), 15), language == .english ? "15 minutes" : "15 分钟")
      player.cancelSleepTimer()
      attachPlayerImage(localization: localization, name: "\(language.rawValue)-off")
      player.setSleepTimer(.sixtyMinutes)
      player.play()
      XCTAssertTrue(player.isPlaying)
      attachPlayerImage(localization: localization, name: "\(language.rawValue)-active-60min")
      clock.time += 3599.2
      scheduler.fire()
      XCTAssertEqual(player.sleepTimerCountdown, "00:01")
      attachPlayerImage(localization: localization, name: "\(language.rawValue)-last-second")
      clock.time += 0.81
      scheduler.fire()
      attachPlayerImage(localization: localization, name: "\(language.rawValue)-expired")
    }
  }

  private func waitUntilReady() {
    let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
      self.avPlayer.currentItem?.status == .readyToPlay
    }, object: nil)
    wait(for: [ready], timeout: 15)
  }

  private func waitUntilElapsed(_ seconds: TimeInterval) {
    let elapsed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
      self.player.elapsedTime >= seconds
    }, object: nil)
    wait(for: [elapsed], timeout: 15)
  }

  private func attachPlayerImage(localization: LocalizationService, name: String) {
    let view = VStack(spacing: 0) {
      Spacer()
      PlayerView(player: player)
    }.environmentObject(localization)
    let hosting = UIHostingController(rootView: view)
    let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
    let previous = scene?.windows.first(where: { $0.isKeyWindow })
    let window = scene.map(UIWindow.init(windowScene:)) ?? UIWindow()
    window.frame = CGRect(x: 0, y: 0, width: 320, height: 568)
    window.rootViewController = hosting
    window.makeKeyAndVisible()
    defer { window.isHidden = true; previous?.makeKey() }
    hosting.view.layoutIfNeeded()
    let drawn = expectation(description: "SwiftUI render")
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { drawn.fulfill() }
    wait(for: [drawn], timeout: 3)
    let image = UIGraphicsImageRenderer(bounds: hosting.view.bounds).image { _ in
      hosting.view.drawHierarchy(in: hosting.view.bounds, afterScreenUpdates: true)
    }
    let attachment = XCTAttachment(image: image)
    attachment.name = "player-sleep-timer-" + name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
