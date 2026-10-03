# Sleep timer

Tap **Sleep timer** in the player and choose 15, 30, 45, or 60 minutes. The player
shows the remaining time and a **Cancel timer** button. Choosing another preset
starts a fresh countdown; cancellation leaves playback as it is.

The deadline measures elapsed real time, including device sleep. Playback speed,
seeking, manual pause, and episode/queue changes do not reset it. The countdown
continues while paused. It is kept only for the current app process and is not
restored after quitting or restarting the app.

Expiry follows the existing pause path: audio stops, playback position and
listening statistics are saved, and Now Playing reports a zero playback rate.
Delayed timer and episode-end callbacks cannot automatically restart audio.
Pressing Play after expiry deliberately starts playback again at the selected
speed, with the old timer cleared.

## Implementation and verification

`PlayerSleepTimer` uses `mach_continuous_time` (available before the iOS 13 minimum)
for its deadline and a one-second main-run-loop timer to request updates. A
generation token invalidates callbacks belonging to cancelled/replaced timers.
Player lifecycle notifications, playback updates, navigation, and explicit Play
reconcile the deadline when a timer callback was delayed.

Regression tests inject a clock and scheduler, including cancelled callbacks.
They cover expiry, rounding, replacement/cancellation, repeated timers,
reentrant publication, cleanup, real run-loop scheduling, pause/position/stats/
Now Playing, speed/seek/queue changes, episode-end races, lifecycle reconciliation,
explicit Play after expiry, interruption resume before expiry and suppression after
expiry/manual pause, and 320-point English/Chinese player renderings.
Run `bash scripts/run-tests.sh`; images and logs are in its `.xcresult` bundle.

The OS must allow execution for audio to stop at the deadline. Background audio
normally allows the timer/playback updates to run; if iOS suspends the process,
execution waits until it resumes and the deadline is then reconciled. Simulator
tests model missed callbacks and lifecycle events, but do not prove physical-device
lock-screen/background timing. Validate those cases on an iPhone before release.

## Local validation — 2026-10-03

Validated locally on `codex/sleep-timer`, based on `62fd675`. The original
checkout and summary worktree were left untouched.

- `sh scripts/generate-project.sh`: checksum-verified XcodeGen 2.46.0; generated
  project unchanged. The deployment target remains iOS 13.0.
- `xcodebuild -project Podcasts.xcodeproj -scheme Podcasts -destination
  'generic/platform=iOS Simulator' build`: **BUILD SUCCEEDED**.
- `bash scripts/run-tests.sh`: **42 passed, 0 failed, 0 skipped** on the arm64
  iPhone Air simulator, iOS 26.4.1. Counts: 11 timer-engine, 16 timer/playback
  integration, 9 playback-speed, 1 local-playback, and 5 artwork tests.
- Final results: `build/test-results/run.r2FJPd/Tests.xcresult`; the runner's log
  is `build/test-results/run.r2FJPd/xcodebuild.log`. Additional build/test logs and
  the exported summary are in `/tmp/castify-sleep-timer-validation-build.log`,
  `/tmp/castify-sleep-timer-validation-final.log`, and
  `/tmp/castify-sleep-timer-validation-final-summary.json`.
- Eight 320-point, default-text-size player images cover timer off, active at
  60:00, 00:01, and expired in both languages. The timer text, countdown, and
  cancellation control fit without clipping. Final attachments were exported to
  `/tmp/castify-sleep-timer-validation-final-ui/`.

Validation corrected a playing-seek test that could miss its one-second media
window while polling once per second at 2x. The wider window still distinguishes
successful seeking from unseeked playback. It also corrected interruption observer
lifetime: the observer now remains registered across a pause so the end event can
resume previously active playback before expiry. Expiry or manual pause clears
that resume intention. Three regression tests cover these cases.

The old final-run log ended mid-test and its bundle was incomplete. The first
recovery run reproduced the seek timeout and was explicitly interrupted during
XCTest's stalled failure reporting; its result is not a passing validation. The
42-test final run above completed normally and supersedes it.

Remaining checks before release: physical-device background/lock-screen timing,
real OS suspension/interruption and remote-control delivery, actual 15–60-minute
wall-clock runs, iOS 13 runtime behavior, live taps through the preset/cancellation
sheets, VoiceOver, larger Dynamic Type, landscape, and dark mode. The available
computer-control interface was unavailable, so interactive UI taps were not
performed. Injected-clock integration tests and renderings do not prove these
physical or interactive cases.
