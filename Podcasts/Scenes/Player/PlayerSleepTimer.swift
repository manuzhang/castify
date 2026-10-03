import Darwin
import Foundation

enum SleepTimerDuration: Int, CaseIterable {
  case fifteenMinutes = 15
  case thirtyMinutes = 30
  case fortyFiveMinutes = 45
  case sixtyMinutes = 60

  var seconds: TimeInterval { TimeInterval(rawValue * 60) }
}

/// Main-thread timer state; scheduling is only a wake-up, never the time source.
final class PlayerSleepTimer {
  typealias Schedule = (@escaping () -> Void) -> (() -> Void)

  var onUpdate: ((SleepTimerDuration?, TimeInterval?) -> Void)?
  var onExpiry: (() -> Void)?

  private let now: () -> TimeInterval
  private let schedule: Schedule
  private var deadline: TimeInterval?
  private var duration: SleepTimerDuration?
  private var generation = UUID()
  private var cancelScheduledTick: (() -> Void)?

  init(now: @escaping () -> TimeInterval = PlayerSleepTimer.continuousTime,
       schedule: @escaping Schedule = PlayerSleepTimer.scheduleTicks) {
    self.now = now
    self.schedule = schedule
  }

  deinit { cancelScheduledTick?() }

  func start(_ duration: SleepTimerDuration) {
    clear()
    self.duration = duration
    deadline = now() + duration.seconds
    let token = generation
    onUpdate?(duration, duration.seconds)
    guard generation == token else { return }
    let cancellation = schedule { [weak self] in
      guard let self = self, self.generation == token else { return }
      self.reconcile()
    }
    if generation == token {
      cancelScheduledTick = cancellation
    } else {
      cancellation()
    }
  }

  func cancel() {
    clear()
    onUpdate?(nil, nil)
  }

  /// Returns true only when this call expires the current timer.
  @discardableResult
  func reconcile() -> Bool {
    guard let deadline = deadline, let duration = duration else { return false }
    let remaining = min(duration.seconds, max(0, deadline - now()))
    if remaining > 0 {
      onUpdate?(duration, ceil(remaining))
      return false
    }
    clear()
    let token = generation
    onUpdate?(nil, nil)
    // An observer may have replaced/cancelled the timer during publication.
    guard generation == token else { return false }
    onExpiry?()
    return true
  }

  private func clear() {
    generation = UUID()
    cancelScheduledTick?()
    cancelScheduledTick = nil
    deadline = nil
    duration = nil
  }

  private static let secondsPerTick: Double = {
    var timebase = mach_timebase_info_data_t()
    mach_timebase_info(&timebase)
    return Double(timebase.numer) / Double(timebase.denom) / 1_000_000_000
  }()

  // Available since iOS 10; unlike mach_absolute_time, advances during sleep.
  static func continuousTime() -> TimeInterval {
    Double(mach_continuous_time()) * secondsPerTick
  }

  static func scheduleTicks(_ tick: @escaping () -> Void) -> (() -> Void) {
    let timer = Timer(timeInterval: 1, repeats: true) { _ in tick() }
    RunLoop.main.add(timer, forMode: .common)
    return { timer.invalidate() }
  }
}
