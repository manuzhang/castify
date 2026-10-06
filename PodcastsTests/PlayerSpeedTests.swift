import AVFoundation
import MediaPlayer
import SwiftUI
import UIKit
import XCTest
@testable import Castify

final class PlayerSpeedTests: XCTestCase {
  private var defaults: UserDefaults!
  private var suiteName: String!

  override func setUp() {
    super.setUp()
    suiteName = "Castify.PlayerSpeedTests." + UUID().uuidString
    defaults = UserDefaults(suiteName: suiteName)
  }

  override func tearDown() {
    defaults.removePersistentDomain(forName: suiteName)
    defaults = nil
    super.tearDown()
  }

  func testSpeedDefaultsToNormalAndInvalidSavedSelectionFallsBack() {
    XCTAssertEqual(Player(userDefaults: defaults).playbackSpeed, .normal)
    for invalid in [0, -1, 2.25] {
      defaults.set(invalid, forKey: UserDefaults.playbackSpeedKey)
      let avPlayer = AVPlayer()
      let player = Player(avPlayer: avPlayer, userDefaults: defaults)
      XCTAssertEqual(player.playbackSpeed, .normal)
      XCTAssertFalse(player.isPlaying)
      XCTAssertEqual(avPlayer.rate, 0)
    }
  }

  func testSelectionPersistsAcrossPlayersWithoutStartingAudio() {
    let avPlayer = AVPlayer()
    let player = Player(avPlayer: avPlayer, userDefaults: defaults)
    player.setPlaybackSpeed(.oneAndThreeQuarters)
    XCTAssertEqual(defaults.float(forKey: UserDefaults.playbackSpeedKey), 1.75)
    XCTAssertEqual(avPlayer.rate, 0)
    let restoredAVPlayer = AVPlayer()
    let restored = Player(avPlayer: restoredAVPlayer, userDefaults: defaults)
    XCTAssertEqual(restored.playbackSpeed, .oneAndThreeQuarters)
    XCTAssertEqual(restoredAVPlayer.rate, 0)
    XCTAssertFalse(restored.isPlaying)
  }

  func testSpeedChangesApplyWhilePlayingAndPauseResumeRetainSelection() throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let avPlayer = AVPlayer()
    let player = Player(avPlayer: avPlayer, userDefaults: defaults)
    defer { player.pause(); avPlayer.replaceCurrentItem(with: nil) }
    player.setup(for: fixture.episodes)
    waitUntilReady(avPlayer)
    player.setPlaybackSpeed(.threeQuarters)
    XCTAssertEqual(avPlayer.rate, 0)
    player.play()
    waitForPlayback(avPlayer, speed: 0.75)
    player.setPlaybackSpeed(.double)
    XCTAssertEqual(avPlayer.rate, 2)
    XCTAssertTrue(player.isPlaying)
    XCTAssertEqual(avPlayer.currentItem?.audioTimePitchAlgorithm, .timeDomain)

    player.pause()
    player.setPlaybackSpeed(.oneAndAHalf)
    XCTAssertEqual(avPlayer.rate, 0)
    XCTAssertFalse(player.isPlaying)
    XCTAssertEqual(player.playbackSpeed, .oneAndAHalf)
    player.play()
    waitForPlayback(avPlayer, speed: 1.5)
    XCTAssertTrue(player.isPlaying)
  }

  func testPausedEpisodeNavigationAndSeekDoNotStartPlayback() throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let avPlayer = AVPlayer()
    let player = Player(avPlayer: avPlayer, userDefaults: defaults)
    defer { player.pause(); avPlayer.replaceCurrentItem(with: nil) }
    player.setup(for: fixture.episodes)
    waitUntilReady(avPlayer)
    player.play()
    waitForPlayback(avPlayer, speed: 1)
    player.pause()
    player.setPlaybackSpeed(.double)
    player.next()
    waitUntilReady(avPlayer)
    XCTAssertEqual(player.current, fixture.episodes[1])
    XCTAssertEqual(player.playbackSpeed, .double)
    XCTAssertFalse(player.isPlaying)
    XCTAssertEqual(avPlayer.rate, 0)
    player.seek(to: 0.5)
    let sought = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
      abs(avPlayer.currentTime().seconds - 30) < 0.1
    }, object: nil)
    wait(for: [sought], timeout: 10)
    XCTAssertEqual(avPlayer.rate, 0)
    player.previous()
    waitUntilReady(avPlayer)
    XCTAssertEqual(player.current, fixture.episodes[0])
    XCTAssertEqual(player.playbackSpeed, .double)
    XCTAssertFalse(player.isPlaying)
    XCTAssertEqual(avPlayer.rate, 0)
    player.play()
    waitForPlayback(avPlayer, speed: 2)
  }

  func testPlayingNavigationAndExplicitEpisodeSelectionRetainSpeed() throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let avPlayer = AVPlayer()
    let player = Player(avPlayer: avPlayer, userDefaults: defaults)
    defer { player.pause(); avPlayer.replaceCurrentItem(with: nil) }
    player.setPlaybackSpeed(.oneAndAQuarter)
    player.play(episode: fixture.episodes[0], in: fixture.episodes)
    waitUntilReady(avPlayer)
    waitForPlayback(avPlayer, speed: 1.25)
    player.next()
    waitUntilReady(avPlayer)
    XCTAssertEqual(player.current, fixture.episodes[1])
    waitForPlayback(avPlayer, speed: 1.25)
    player.previous()
    waitUntilReady(avPlayer)
    XCTAssertEqual(player.current, fixture.episodes[0])
    waitForPlayback(avPlayer, speed: 1.25)
    player.pause()
    player.playQueue([fixture.episodes[1], fixture.episodes[0]])
    waitUntilReady(avPlayer)
    XCTAssertEqual(player.current, fixture.episodes[1])
    waitForPlayback(avPlayer, speed: 1.25)
  }

  func testNowPlayingReportsSelectedSpeedAndZeroWhilePaused() throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let avPlayer = AVPlayer()
    let center = MPNowPlayingInfoCenter.default()
    let player = Player(avPlayer: avPlayer, systemPlayer: center, userDefaults: defaults)
    defer { player.pause(); avPlayer.replaceCurrentItem(with: nil) }
    player.setup(for: fixture.episodes)
    waitUntilReady(avPlayer)
    player.setPlaybackSpeed(.double)
    XCTAssertEqual((center.nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackRate] as? NSNumber)?.floatValue, 0)
    XCTAssertEqual((center.nowPlayingInfo?[MPNowPlayingInfoPropertyDefaultPlaybackRate] as? NSNumber)?.floatValue, 2)
    player.play()
    waitForPlayback(avPlayer, speed: 2)
    player.setPlaybackSpeed(.oneAndThreeQuarters)
    XCTAssertEqual((center.nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackRate] as? NSNumber)?.floatValue, 1.75)
    player.pause()
    XCTAssertEqual((center.nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackRate] as? NSNumber)?.floatValue, 0)
    XCTAssertEqual((center.nowPlayingInfo?[MPNowPlayingInfoPropertyDefaultPlaybackRate] as? NSNumber)?.floatValue, 1.75)
  }

  func testListeningTimeNormalizesFastAndSlowPlaybackAndExcludesPausedChanges() throws {
    let savedStats = UserDefaults.standard.data(forKey: UserDefaults.listeningStatsKey)
    defer { UserDefaults.standard.set(savedStats, forKey: UserDefaults.listeningStatsKey) }
    let service = PodcastsService()
    for speed in [PlaybackSpeed.double, .threeQuarters] {
      let fixture = try makeFixture()
      defer { try? FileManager.default.removeItem(at: fixture.directory) }
      let avPlayer = AVPlayer()
      let player = Player(avPlayer: avPlayer, podcastsService: service, userDefaults: defaults)
      defer { player.pause(); avPlayer.replaceCurrentItem(with: nil) }
      player.setup(for: fixture.episodes)
      waitUntilReady(avPlayer)
      player.setPlaybackSpeed(speed)
      let initial = service.listeningStats.totalListeningTime
      player.play()
      waitUntilElapsed(player, reaches: 3)
      player.pause()
      let listened = service.listeningStats.totalListeningTime - initial
      XCTAssertEqual(listened, player.elapsedTime / Double(speed.rawValue), accuracy: 0.05)
      let pausedStats = service.listeningStats.totalListeningTime
      player.setPlaybackSpeed(speed == .double ? .threeQuarters : .double)
      XCTAssertEqual(avPlayer.rate, 0)
      XCTAssertEqual(service.listeningStats.totalListeningTime, pausedStats)
    }
  }

  func testListeningTimeSplitsIntervalsAtSpeedChangesAndEpisodeSwitches() throws {
    let savedStats = UserDefaults.standard.data(forKey: UserDefaults.listeningStatsKey)
    defer { UserDefaults.standard.set(savedStats, forKey: UserDefaults.listeningStatsKey) }
    let service = PodcastsService()
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let avPlayer = AVPlayer()
    let player = Player(avPlayer: avPlayer, podcastsService: service, userDefaults: defaults)
    defer { player.pause(); avPlayer.replaceCurrentItem(with: nil) }
    player.setup(for: fixture.episodes)
    waitUntilReady(avPlayer)
    player.setPlaybackSpeed(.double)
    let initial = service.listeningStats.totalListeningTime
    player.play()
    waitUntilElapsed(player, reaches: 3)
    player.setPlaybackSpeed(.threeQuarters)
    let speedBoundary = player.elapsedTime
    XCTAssertEqual(service.listeningStats.totalListeningTime - initial, speedBoundary / 2, accuracy: 0.05)
    // Cross the production resume threshold so shared fixture identities cannot
    // accidentally pass by staying below the point at which a position is saved.
    waitUntilElapsed(player, reaches: max(speedBoundary + 2, 6))
    XCTAssertGreaterThan(service.resumePosition(for: fixture.episodes[0]), 5)
    XCTAssertEqual(service.resumePosition(for: fixture.episodes[1]), 0)
    let episodeBoundary = avPlayer.currentTime().seconds
    player.next()
    XCTAssertEqual(player.current, fixture.episodes[1])
    let firstListening = speedBoundary / 2 + (episodeBoundary - speedBoundary) / 0.75
    XCTAssertEqual(service.listeningStats.totalListeningTime - initial, firstListening, accuracy: 0.1)
    waitUntilReady(avPlayer)
    waitUntilElapsed(player, reaches: 2)
    player.pause()
    XCTAssertEqual(service.listeningStats.totalListeningTime - initial,
                   firstListening + player.elapsedTime / 0.75, accuracy: 0.1)
  }

  func testPlayerControlRendersIdlePlayingAndPausedInEnglishAndChinese() throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let avPlayer = AVPlayer()
    let player = Player(avPlayer: avPlayer, userDefaults: defaults)
    defer { player.pause(); avPlayer.replaceCurrentItem(with: nil) }
    player.setup(for: fixture.episodes)
    waitUntilReady(avPlayer)
    let localization = LocalizationService(userDefaults: defaults)
    for language in [AppLanguage.english, .chinese] {
      localization.setLanguage(language)
      player.pause()
      player.setup(for: [])
      player.setup(for: fixture.episodes)
      waitUntilReady(avPlayer)
      player.setPlaybackSpeed(.threeQuarters)
      attachPlayerImage(player, localization: localization, name: "\(language.rawValue)-idle-0.75x", width: 320)
      player.play()
      waitForPlayback(avPlayer, speed: 0.75)
      player.setPlaybackSpeed(.double)
      attachPlayerImage(player, localization: localization, name: "\(language.rawValue)-playing-2x", width: 320)
      player.pause()
      player.setPlaybackSpeed(.oneAndAHalf)
      attachPlayerImage(player, localization: localization, name: "\(language.rawValue)-paused-1.5x", width: 320)
      XCTAssertEqual(avPlayer.rate, 0)
    }
  }

  private func makeFixture() throws -> (directory: URL, episodes: [Episode]) {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    do {
      let firstURL = directory.appendingPathComponent("first.caf")
      let secondURL = directory.appendingPathComponent("second.caf")
      let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1))
      let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44100 * 60))
      buffer.frameLength = buffer.frameCapacity
      try XCTUnwrap(buffer.floatChannelData)[0].initialize(repeating: 0, count: Int(buffer.frameLength))
      do {
        let file = try AVAudioFile(forWriting: firstURL, settings: format.settings)
        try file.write(from: buffer)
      }
      try FileManager.default.copyItem(at: firstURL, to: secondURL)
      // Playback state is keyed by media URL, so distinct test episodes need
      // distinct files even when their synthetic audio content is identical.
      return (directory, [
        Episode(title: "Playback speed regression first episode", author: "Castify Test", streamUrl: firstURL.absoluteString, duration: 60),
        Episode(title: "Playback speed regression second episode", author: "Castify Test", streamUrl: secondURL.absoluteString, duration: 60)
      ])
    } catch {
      try? FileManager.default.removeItem(at: directory)
      throw error
    }
  }

  private func waitUntilReady(_ player: AVPlayer) {
    let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
      player.currentItem?.status == .readyToPlay
    }, object: nil)
    wait(for: [ready], timeout: 15)
  }

  private func waitForPlayback(_ player: AVPlayer, speed: Float) {
    let playing = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
      player.rate == speed && player.currentTime().seconds > 0.1
    }, object: nil)
    wait(for: [playing], timeout: 15)
  }

  private func waitUntilElapsed(_ player: Player, reaches seconds: TimeInterval) {
    let elapsed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
      player.elapsedTime >= seconds
    }, object: nil)
    wait(for: [elapsed], timeout: 15)
  }

  private func attachPlayerImage(_ player: Player, localization: LocalizationService, name: String, width: CGFloat) {
    let view = VStack(spacing: 0) {
      Spacer()
      PlayerView(player: player)
    }.environmentObject(localization)
    let hosting = UIHostingController(rootView: view)
    let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
    let previous = scene?.windows.first(where: { $0.isKeyWindow })
    let window = scene.map(UIWindow.init(windowScene:)) ?? UIWindow()
    window.frame = CGRect(x: 0, y: 0, width: width, height: 568)
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
    attachment.name = "player-speed-" + name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
