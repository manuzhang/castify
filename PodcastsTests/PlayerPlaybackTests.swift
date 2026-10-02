import AVFoundation
import XCTest
@testable import Castify

final class PlayerPlaybackTests: XCTestCase {
  func testLocalPlaybackWithMissingArtworkSupportsPauseSeekAndQueueNavigation() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".caf")
    defer { try? FileManager.default.removeItem(at: url) }
    // Keep the fixture playing beyond the polling deadline on a busy CI runner.
    let fixtureDuration: TimeInterval = 30
    let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1))
    let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(44100 * fixtureDuration)))
    buffer.frameLength = buffer.frameCapacity
    let samples = try XCTUnwrap(buffer.floatChannelData)[0]
    samples.initialize(repeating: 0, count: Int(buffer.frameLength))
    do {
      let file = try AVAudioFile(forWriting: url, settings: format.settings)
      try file.write(from: buffer)
    }

    let first = Episode(title: "Regression first", streamUrl: url.absoluteString, duration: fixtureDuration)
    let second = Episode(title: "Regression second", streamUrl: url.absoluteString, duration: fixtureDuration)
    let avPlayer = AVPlayer()
    let player = Player(avPlayer: avPlayer)
    defer {
      player.pause()
      avPlayer.replaceCurrentItem(with: nil)
    }

    XCTAssertNotNil(ImagesLoader().image(for: first.imageURL()).cgImage)
    player.setup(for: [first, second])
    XCTAssertEqual(player.current, first)
    XCTAssertEqual(player.queueEpisodes, [first, second])
    let item = try XCTUnwrap(avPlayer.currentItem)
    let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
      item.status == .readyToPlay
    }, object: nil)
    wait(for: [ready], timeout: 15)

    player.play()
    let advanced = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
      avPlayer.currentTime().seconds > 0.1 && avPlayer.rate > 0
    }, object: nil)
    wait(for: [advanced], timeout: 15)
    XCTAssertTrue(player.isPlaying)

    player.pause()
    XCTAssertFalse(player.isPlaying)
    XCTAssertEqual(avPlayer.rate, 0)
    player.seek(to: 0.5)
    let sought = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
      abs(avPlayer.currentTime().seconds - fixtureDuration / 2) < 0.1
    }, object: nil)
    wait(for: [sought], timeout: 10)

    player.next()
    XCTAssertEqual(player.current, second)
    player.previous()
    XCTAssertEqual(player.current, first)
    XCTAssertEqual(player.queueEpisodes, [first, second])
  }
}
