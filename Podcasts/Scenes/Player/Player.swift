import Foundation
import AVFoundation
import MediaPlayer
import Combine

class Player: ObservableObject {

  enum State {
    case empty
    case idle(episodes: [Episode])
    case playing(episode: Episode, progress: Float)
    case paused(episode: Episode, progress: Float)
    case finish(episodes: [Episode])
  }

  @Published var state: State = .empty
  @Published var progress: Float = 0
  @Published var elapsedTime: TimeInterval = 0
  @Published var duration: TimeInterval = 0

  var current: Episode?
  private var episodes: [Episode] = []
  private let avPlayer: AVPlayer
  private let avSession: AVAudioSession
  private let notificationCenter: NotificationCenter
  private let systemPlayer: MPNowPlayingInfoCenter
  private let commandCenter: MPRemoteCommandCenter
  private let podcastsService: PodcastsService
  private var timeObserverToken: Any?

  init(avPlayer: AVPlayer = AVPlayer(),
       avSession: AVAudioSession = AVAudioSession.sharedInstance(),
       notificationCenter: NotificationCenter = .default,
       systemPlayer: MPNowPlayingInfoCenter = MPNowPlayingInfoCenter.default(),
       commandCenter: MPRemoteCommandCenter = MPRemoteCommandCenter.shared(),
       podcastsService: PodcastsService = PodcastsService()) {
    self.avPlayer = avPlayer
    self.avSession = avSession
    self.notificationCenter = notificationCenter
    self.systemPlayer = systemPlayer
    self.commandCenter = commandCenter
    self.podcastsService = podcastsService
    self.notificationCenter.addObserver(self, selector: #selector(self.didPlayToEnd),
      name: .AVPlayerItemDidPlayToEndTime, object: nil)
    let interval = CMTime(seconds: 1, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
    self.timeObserverToken = self.avPlayer.addPeriodicTimeObserver(forInterval: interval, queue: DispatchQueue.main,
      using: didUpdatedPlayer)
    try? avSession.setCategory(AVAudioSession.Category.playback,
      mode: AVAudioSession.Mode.default,
      options: [.allowBluetooth, .allowAirPlay, .defaultToSpeaker])
    configureRemoteCommands()
  }

  deinit {
    notificationCenter.removeObserver(self)
    if let token = timeObserverToken {
      avPlayer.removeTimeObserver(token)
    }
    commandCenter.playCommand.removeTarget(nil)
    commandCenter.pauseCommand.removeTarget(nil)
    commandCenter.togglePlayPauseCommand.removeTarget(nil)
    commandCenter.nextTrackCommand.removeTarget(nil)
    commandCenter.previousTrackCommand.removeTarget(nil)
    commandCenter.skipForwardCommand.removeTarget(nil)
    commandCenter.skipBackwardCommand.removeTarget(nil)
    commandCenter.changePlaybackPositionCommand.removeTarget(nil)
  }

  // MARK: Player

  func setup(for episodes: [Episode]) {
    let newEpisodes = episodes.filter({ playbackURL(for: $0) != nil })
    guard let first = newEpisodes.first else {
      if !isPlayingNow() {
        reset()
      }
      return
    }

    if self.episodes.isEmpty || (!isPlayingNow() && self.episodes != newEpisodes) {
      load(first, in: newEpisodes, autoplay: false)
    }
  }

  var hasEpisodes: Bool {
    current != nil
  }

  var isPlaying: Bool {
    if case .playing = state {
      return true
    }
    return false
  }

  func play() {
    guard let episode = current else {
      return
    }
    playNow(next: episode)
  }

  func play(episode: Episode, in episodes: [Episode]) {
    let playableEpisodes = episodes.filter({ playbackURL(for: $0) != nil })
    var queue = playableEpisodes

    guard playbackURL(for: episode) != nil else {
      return
    }

    if !queue.contains(episode) {
      queue.insert(episode, at: 0)
    }

    load(episode, in: queue, autoplay: true)
  }

  func pause() {
    pauseNow()
  }

  func previous() {
    guard let previousEpisode = previousEpisode() else {
      return
    }
    playNow(next: previousEpisode)
  }

  func next() {
    guard let nextEpisode = nextEpisode() else {
      return
    }
    self.playNow(next: nextEpisode)
  }

  func seek(to progress: Float) {
    guard let currentItem = avPlayer.currentItem else {
      return
    }

    let totalTime = validSeconds(from: currentItem.duration)
    guard totalTime > 0 else {
      return
    }

    let nextProgress = min(max(progress, 0), 1)
    let seconds = totalTime * TimeInterval(nextProgress)
    let time = CMTime(seconds: seconds, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
    avPlayer.seek(to: time) { [weak self] _ in
      guard let self = self else {
        return
      }
      DispatchQueue.main.async {
        self.updateProgress(time: time)
        if let episode = self.current {
          self.podcastsService.savePlaybackPosition(
            for: episode,
            elapsedTime: self.elapsedTime,
            duration: self.duration
          )
        }
        self.notifySystemPlayer(episode: self.current)
      }
    }
  }

  func seek(by seconds: TimeInterval) {
    guard let currentItem = avPlayer.currentItem else {
      return
    }

    let currentSeconds = validSeconds(from: avPlayer.currentTime())
    let totalTime = validSeconds(from: currentItem.duration)
    guard totalTime > 0 else {
      return
    }

    let targetSeconds = min(max(currentSeconds + seconds, 0), totalTime)
    let targetProgress = Float(targetSeconds / totalTime)
    seek(to: targetProgress)
  }

  func getProgress(time: CMTime) -> Float {
    guard let playerDuration = avPlayer.currentItem?.duration else {
      return 0
    }

    let totalTime = validSeconds(from: playerDuration)
    guard totalTime > 0 else {
      return 0
    }

    let currentTime = validSeconds(from: time)
    return Float(currentTime / totalTime)
  }

  // MARK: NotificationCenter

  @objc private func didPlayToEnd() {
    if let episode = current {
      podcastsService.markEpisodePlayed(episode)
    }

    guard let next = nextEpisode() else {
      if let first = episodes.first {
        load(first, in: episodes, autoplay: false)
      }
      state = .finish(episodes: episodes)
      return
    }
    playNow(next: next)
  }

  // MARK: Player

  @objc private func didUpdatedPlayer(time: CMTime) {
    switch state {
    case .empty, .paused, .finish, .idle:
      return
    case .playing:
      break
    }
    guard let episode = current else {
      return
    }
    updateProgress(time: time)
    episode.setProgress(progress: progress)
    podcastsService.savePlaybackPosition(
      for: episode,
      elapsedTime: elapsedTime,
      duration: duration
    )
    state = .playing(episode: episode, progress: progress)
    notifySystemPlayer(episode: episode)
  }

  // MARK: Private

  private func previousEpisode() -> Episode? {
    guard let current = self.current else {
      return nil
    }
    guard let curIndex = episodes.firstIndex(of: current) else {
      return nil
    }
    let target = curIndex - 1
    guard target >= 0 else {
      return self.current
    }
    return episodes[target]
  }

  private func nextEpisode() -> Episode? {
    guard let current = self.current else {
      return nil
    }
    guard let curIndex = episodes.firstIndex(of: current) else {
      return nil
    }
    let target = curIndex + 1
    guard target < episodes.count else {
      return nil
    }
    return episodes[target]
  }

  private func playNow(next: Episode) {
    guard let url = playbackURL(for: next) else {
      return
    }
    if current != next {
      self.avPlayer.replaceCurrentItem(with: AVPlayerItem(url: url))
      restorePlaybackPosition(for: next)
    }
    current = next
    avPlayer.play()
    try? avSession.setActive(true)
    self.notificationCenter.removeObserver(self, name: AVAudioSession.interruptionNotification, object: nil)
    notificationCenter.addObserver(self, selector: #selector(self.didArriveInterruption),
      name: AVAudioSession.interruptionNotification, object: nil)
    notifySystemPlayer(episode: next)
    state = .playing(episode: next, progress: progress)
  }

  private func pauseNow() {
    guard let episode = current else {
      return
    }
    updateProgress(time: avPlayer.currentTime())
    podcastsService.savePlaybackPosition(
      for: episode,
      elapsedTime: elapsedTime,
      duration: duration
    )
    self.avPlayer.pause()
    self.notificationCenter.removeObserver(self, name: AVAudioSession.interruptionNotification, object: nil)
    notifySystemPlayer(episode: episode)
    state = .paused(episode: episode, progress: progress)
  }

  private func isPlayingNow() -> Bool {
    avPlayer.rate > 0
  }

  private func notifySystemPlayer(episode: Episode?) {
    guard let episode = episode else {
      systemPlayer.nowPlayingInfo = nil
      return
    }

    let info: [String: Any] = [
      MPMediaItemPropertyTitle: episode.title,
      MPMediaItemPropertyArtist: episode.author,
      MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsedTime,
      MPNowPlayingInfoPropertyPlaybackRate: isPlayingNow() ? 1 : 0,
      MPMediaItemPropertyPlaybackDuration: duration,
    ]
    systemPlayer.nowPlayingInfo = info
  }

  private func load(_ episode: Episode, in episodes: [Episode], autoplay: Bool) {
    guard let url = playbackURL(for: episode) else {
      return
    }

    self.episodes = episodes
    let isNewEpisode = current != episode
    current = episode

    if isNewEpisode || avPlayer.currentItem == nil {
      avPlayer.replaceCurrentItem(with: AVPlayerItem(url: url))
      restorePlaybackPosition(for: episode)
    }

    if autoplay {
      playNow(next: episode)
    } else {
      state = .idle(episodes: episodes)
    }
  }

  private func reset() {
    avPlayer.pause()
    avPlayer.replaceCurrentItem(with: nil)
    current = nil
    episodes = []
    resetProgress(duration: 0)
    notifySystemPlayer(episode: nil)
    state = .empty
  }

  private func resetProgress(duration: TimeInterval) {
    progress = 0
    elapsedTime = 0
    self.duration = duration
  }

  private func restorePlaybackPosition(for episode: Episode) {
    let state = podcastsService.playbackState(for: episode)
    let knownDuration = max(episode.duration ?? 0, state?.duration ?? 0)
    resetProgress(duration: knownDuration)

    guard let state = state, state.hasResumePosition else {
      return
    }

    let targetTime = CMTime(seconds: state.position, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
    elapsedTime = state.position
    if duration > 0 {
      progress = state.progress
    }

    avPlayer.seek(to: targetTime) { [weak self] _ in
      DispatchQueue.main.async {
        guard let self = self else {
          return
        }
        self.elapsedTime = state.position
        if self.duration > 0 {
          self.progress = state.progress
        }
        self.notifySystemPlayer(episode: episode)
      }
    }
  }

  private func updateProgress(time: CMTime) {
    elapsedTime = validSeconds(from: time)

    if let playerDuration = avPlayer.currentItem?.duration {
      duration = validSeconds(from: playerDuration)
    }

    progress = getProgress(time: time)
  }

  private func validSeconds(from time: CMTime) -> TimeInterval {
    let seconds = CMTimeGetSeconds(time)
    guard seconds.isFinite && !seconds.isNaN else {
      return 0
    }
    return max(0, seconds)
  }

  private func playbackURL(for episode: Episode) -> URL? {
    if let fileUrl = episode.fileUrl {
      if let url = URL(string: fileUrl), url.isFileURL, FileManager.default.fileExists(atPath: url.path) {
        return url
      }

      if FileManager.default.fileExists(atPath: fileUrl) {
        return URL(fileURLWithPath: fileUrl)
      }
    }

    return episode.audio
  }

  private func configureRemoteCommands() {
    commandCenter.playCommand.isEnabled = true
    commandCenter.playCommand.addTarget { [weak self] _ in
      self?.play()
      return .success
    }

    commandCenter.pauseCommand.isEnabled = true
    commandCenter.pauseCommand.addTarget { [weak self] _ in
      self?.pause()
      return .success
    }

    commandCenter.togglePlayPauseCommand.isEnabled = true
    commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
      guard let self = self else {
        return .commandFailed
      }
      self.isPlaying ? self.pause() : self.play()
      return .success
    }

    commandCenter.nextTrackCommand.isEnabled = true
    commandCenter.nextTrackCommand.addTarget { [weak self] _ in
      self?.next()
      return .success
    }

    commandCenter.previousTrackCommand.isEnabled = true
    commandCenter.previousTrackCommand.addTarget { [weak self] _ in
      self?.previous()
      return .success
    }

    commandCenter.skipForwardCommand.isEnabled = true
    commandCenter.skipForwardCommand.preferredIntervals = [NSNumber(value: 30)]
    commandCenter.skipForwardCommand.addTarget { [weak self] _ in
      self?.seek(by: 30)
      return .success
    }

    commandCenter.skipBackwardCommand.isEnabled = true
    commandCenter.skipBackwardCommand.preferredIntervals = [NSNumber(value: 15)]
    commandCenter.skipBackwardCommand.addTarget { [weak self] _ in
      self?.seek(by: -15)
      return .success
    }

    commandCenter.changePlaybackPositionCommand.isEnabled = true
    commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
      guard let event = event as? MPChangePlaybackPositionCommandEvent,
            let self = self,
            self.duration > 0 else {
        return .commandFailed
      }
      self.seek(to: Float(event.positionTime / self.duration))
      return .success
    }
  }

  // MARK: Interruptions

  @objc private func didArriveInterruption(notification: NSNotification) {
    if let value = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? NSNumber,
       let type = AVAudioSession.InterruptionType(rawValue: value.uintValue) {
      switch type {
      case .began:
        pause()
      case .ended:
        play()
      @unknown default:
        break
      }
    }
  }

}
