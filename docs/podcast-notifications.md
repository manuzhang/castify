# Per-podcast new-episode alerts

Open a subscribed podcast and turn on **New episode alerts**. The switch defaults
to off for every existing and new subscription. It does not enable the global
Notifications setting, change OS authorization, or request permission. Enable the
global setting explicitly in Settings and allow notifications in iOS if desired.
English and Chinese labels and explanatory text are provided.

Alerts are driven by the existing successful RSS refreshes: the Podcasts library,
a podcast's first episode load, or an auto-download feed lookup. There is no
remote push service, background fetch registration, periodic polling, or guarantee
of discovering releases while the app is closed. Foreground presentation uses the
notification delegate and rechecks the current global/subscription preference.

## Discovery and delivery

- An opt-in establishes its baseline from the next successful network refresh;
  cached screen contents are not used. That first snapshot is never announced.
- Subsequent snapshots identify episodes by RSS GUID, then enclosure URL, then
  reliably parsed publication date/title/author. RFC 822 dates may omit seconds;
  RSS 1.0 Dublin Core dates are resolved by namespace and parsed as ISO timestamps
  or UTC calendar dates. Identities are SHA-256 hashes
  scoped to a normalized subscription feed URL. Added optional episode fields
  remain compatible with old cached JSON; playback equality is unchanged.
- An episode must be unseen and have a valid publication date later than the
  previous successful snapshot and no later than the current time. Missing/invalid
  dates, historical insertions, future-dated items and unidentified items are not
  announced. RSS display-date fallback behavior is retained. Feeds that change all
  identities or omit reliable dates may miss alerts; publisher timestamps are not
  an independent proof of release time.
- Discovery state is persisted before the asynchronous authorization/scheduling
  calls. Repeated refreshes and restarts do not replay those discoveries. An
  authorization denial or scheduling failure consumes the discovery rather than
  retrying it later. This conservative at-most-once policy may miss an alert if
  the app exits between persistence and scheduling.
- At most one local request is submitted per accepted refresh, summarizing the
  new count and latest episode if there are several. Authorization must already
  be authorized, provisional, or (on iOS 14+) ephemeral; OS settings determine
  actual display/sound. Requests use a one-second trigger and do not change badge
  counts. Tapping one uses the OS's normal app-opening behavior.

## Preference changes and races

Membership uses the library's existing matching rules: a shared nonzero track ID,
then a normalized feed URL. A Browse result with an updated URL controls the saved
subscription's preference; library refreshes continue using that saved feed URL.

Seen hashes retain at most 2,048 identities per active feed, prioritizing the current
snapshot's newest publication dates and then prior recent identities. Oversized
legacy arrays are compacted once at startup; the JSON representation is compatible
with old encoded sets. Cutoff checks prevent historical replay with unchanged
dates even after eviction. Deduplication of GUIDs whose dates are edited forward
is limited to this retained window; it is not an unlimited identity archive.

Active per-feed preferences, seen hashes, baseline cutoff and generation are stored in
one versioned `UserDefaults` record. Existing global values are retained. A missing,
corrupt or unknown-version record defaults all per-podcast settings off; there is
no migration that opts anyone in or requests permission. Discarding a corrupt or
unknown-version record cancels app-owned pending episode requests and persists
the recovered preference store. A delayed cleanup rechecks current generations so it
preserves new alerts enabled during recovery and leaves unrelated requests alone.

Submitted request identifiers are persisted before scheduling. Disabling a podcast
removes its stored record, directly cancels known identifiers without awaiting a
pending-request lookup, and invalidates refreshes,
authorization lookups and additions already in flight. Unsubscribe does the same;
resubscription defaults off. Startup also prunes legacy disabled records and records
for absent subscriptions, so inactive feeds do not accumulate across launches. Re-enabling starts a fresh baseline, suppressing
releases from the disabled period. Global preference changes preserve per-podcast
opt-ins but cancel pending requests and start fresh baselines. Existing Settings
behavior for explicitly requesting permission and clearing delivered notifications
on global disable remains in place. Per-podcast disable leaves already delivered
notifications in notification history.

All notification state is handled on the main thread. The newest-started refresh
for a feed wins; out-of-order responses, including an older response after a newer
failure, cannot establish a baseline or schedule an alert. Failed refreshes do not
advance a cutoff. Non-RSS XML payloads are rejected before changing alert state;
valid empty RSS channels remain successful snapshots. RSS 1.0/RDF channels and
sibling items are also recognized by namespace, preserving prior feed support. A late permission callback
rechecks the refresh generation, subscription and global preference. Once a
discovery is committed, a later refresh does not discard its pending delivery. A late add completion cancels its
own obsolete identifier. Cancellation queries include the old generation so they
cannot cancel alerts from a replacement opt-in. Prefix lookup is a fallback only
for pre-upgrade records with untracked identifiers. Completed identifiers no
longer pending are pruned on later refreshes; in-flight/newer submissions are
protected from stale lookup snapshots.

## Validation

The notification API is injected in tests. Its interface has no permission-request
method. Tests use isolated preference suites, synthetic feeds, a controllable clock,
delayed authorization/addition callbacks, background-to-main delivery, and
stubbed URLSession responses that exercise successful/failed RSS refreshes. No real notification is scheduled,
no OS permission is requested, and no user notification preference is enabled by
validation. UI renderings cover English/Chinese off/on controls at 320-point width.

Run:

```sh
sh scripts/generate-project.sh
xcodebuild -project Podcasts.xcodeproj -scheme Podcasts -destination 'generic/platform=iOS Simulator' build
bash scripts/run-tests.sh
```

Physical-device delivery, notification-center presentation, OS authorization
changes, app suspension/background execution, live UI taps, VoiceOver, larger
Dynamic Type, landscape, dark mode, and an iOS 13 runtime require separate device/UI
checks. Simulator tests and component screenshots do not establish those behaviors.

## Local results — 2026-10-03

Worktree: `castify-podcast-notifications`, branch `codex/podcast-notifications`,
based on main `62fd675`. The sleep-timer and summary worktrees remain untouched.

- Checksum-verified XcodeGen 2.46.0 generation passed; regeneration produced no
  project drift. No package/version/spec changes; the deployment target is iOS 13.
- The generic iOS Simulator build command above passed for the completed source.
- `bash scripts/run-tests.sh` passed **52 tests, 0 failures, 0 skips** on the arm64
  iPhone Air simulator, iOS 26.4.1: 30 notification preference/delivery/race tests,
  4 parser/identity/cache tests, 2 stubbed-network refresh tests, 1 bilingual UI
  rendering test, and the existing 1 playback, 9 speed, and 5 artwork tests.
- Final bundle/log: `build/test-results/run.3XmRtQ/Tests.xcresult` and
  `build/test-results/run.3XmRtQ/xcodebuild.log`. Exported summary:
  `/tmp/castify-podcast-notifications-test-summary.json`. Build log:
  `/tmp/castify-podcast-notifications-build-final.log`.
- Four 320-point, default-text-size renderings show opt-in off/on in English and
  Chinese. The label, toggle and explanatory text fit without clipping. Images
  are retained in the result bundle and exported to
  `/tmp/castify-podcast-notifications-ui/`.

Earlier complete suites passed 48 and 49 tests before the final three integration/
threading checks were added. Simulator boot logs reported a migration failure,
but the test hosts launched and the full suites completed successfully. All three
runner-created simulators were removed; existing simulator data was preserved.
Actual OS display/permission/background behavior and live UI tapping remain
unverified as described above. No notification permission prompt, remote feed
request from the new tests, push or PR publication was performed.

## Review-fix validation — 2026-10-03

Both review findings are addressed: Browse uses the saved subscription matched by
the library's track-ID/feed rules, and disabled/unsubscribed preferences are
removed rather than retained. Startup prunes legacy disabled records once.
Four added regressions cover changed Browse feeds, zero-ID imports, repeated
disabling without preference growth, and one-time legacy cleanup; unsubscribe
and startup tests also assert removal. Existing delayed-callback and replacement
generation tests continue to pass.

- XcodeGen regeneration passed without project drift; the generic iOS Simulator
  build passed. iOS 13 deployment and dependency versions are unchanged.
- The full serial runner passed **56 tests, 0 failures, 0 skips** on iPhone Air,
  iOS 26.4.1, including 34 preference/delivery/race tests.
- Results: `build/test-results/run.SG1WYO/Tests.xcresult` and `xcodebuild.log`;
  build log: `/tmp/castify-podcast-notifications-review-build.log`; exported
  summary: `/tmp/castify-podcast-notifications-review-test-summary.json`.
- The same physical-device/OS delivery and UI limitations above still apply.

The subsequent invalid-store recovery review is also addressed: corrupt or
unknown-version preferences cancel only obsolete app-owned pending episode
requests. Main-thread generation rechecks preserve new opt-ins even when the
lookup completes late, and the recovered store is persisted. Two added
regressions cover invalid-record cleanup with unrelated requests and delayed
cleanup with a replacement generation.

Final recovery validation passed XcodeGen regeneration without drift, the
generic simulator build, and **58 tests, 0 failures, 0 skips** (36 notification
preference/delivery/race tests). Bundle/log: `build/test-results/run.GAQcH9/Tests.xcresult`
and `xcodebuild.log`; build log: `/tmp/castify-podcast-notifications-recovery-build.log`;
summary: `/tmp/castify-podcast-notifications-recovery-test-summary.json`.

The next RSS/discovery review findings are addressed too: valid RSS dates without
seconds retain known publication times; committed discoveries remain eligible
for delivery if a later refresh begins during authorization lookup; and non-RSS
XML cannot establish or advance the notification baseline. Empty RSS channels
remain accepted. Four added regressions cover date variants/time zones, successful
and failed later refreshes, structural payload validation, and stubbed 2xx error
payloads before and after a baseline.

This validation passed drift-free XcodeGen generation, the generic simulator
build, and **62 tests, 0 failures, 0 skips**: 37 notification-state tests, 6 parser/
identity/cache tests, 3 stub-network refresh tests, 1 bilingual UI render test, and
15 existing playback/speed/artwork tests. Bundle/log:
`build/test-results/run.k1NVNc/Tests.xcresult` and `xcodebuild.log`; build log:
`/tmp/castify-podcast-notifications-feed-review-build.log`; summary:
`/tmp/castify-podcast-notifications-feed-review-test-summary.json`. Device/UI
limitations documented above are unchanged.

The RSS 1.0/cancellation follow-up is addressed: structural checks also recognize
RSS 1.0 channels and sibling items by RDF/RSS namespace, including alternate
prefixes. RSS 2.0 iTunes metadata parsing is preserved. Submitted identifiers and
registration confirmation are persisted before scheduling, so per-podcast disable,
unsubscribe and global changes request immediate known-ID removal, even after
restart. Pre-upgrade unknown IDs retain the old generation-scoped lookup fallback.
Completed IDs are pruned against later pending-request snapshots without dropping
in-flight, unconfirmed-after-restart, or newly submitted IDs.

Nine added regressions cover RDF parsing/network delivery, iTunes metadata, direct
cancellation in all three paths, persistence/restart, delayed pruning, in-flight
and unconfirmed requests, and legacy fallback. Final validation passed generation
without drift, the generic simulator build, and **71 tests, 0 failures, 0 skips**
(43 notification-state, 8 parser/identity/cache, 4 stub-network, 1 bilingual UI,
and 15 existing playback/speed/artwork tests). Bundle/log:
`build/test-results/run.HtqFyY/Tests.xcresult` and `xcodebuild.log`; build log:
`/tmp/castify-podcast-notifications-direct-cancel-build-final.log`; summary:
`/tmp/castify-podcast-notifications-direct-cancel-test-summary-final.json`.
An earlier complete 70-test suite also passed before the confirmation-state
restart regression was added. Physical-device/OS presentation and other UI limits
remain as documented above.

The Dublin Core/history review is addressed: `dc:date` is resolved by namespace
(including alternate prefixes), supports ISO second/minute timestamps and UTC
calendar dates, and supplies reliable metadata identity when GUID/enclosure are
absent. Invalid namespaces or insufficient date granularity remain unknown.
Seen history is now an ordered, compatible JSON array capped at 2,048 hashes per
feed. Current newest publication dates are prioritized, and oversized legacy
arrays are compacted once on load. Cutoffs suppress unchanged historical dates;
GUID deduplication after a publisher edits dates forward is limited to the
retained window, as documented above.

Four new regressions cover DC date/creator variants and invalid metadata, a
standard RSS 1.0 title/link/date network flow, rotating GUID histories and recent
GUID edits after restart, and one-time legacy compaction. Final validation passed
XcodeGen generation without drift, the generic simulator build, and **75 tests,
0 failures, 0 skips** (45 notification-state, 9 parser/identity/cache, 5 stub-network,
1 bilingual UI and 15 existing playback/speed/artwork tests). Bundle/log:
`build/test-results/run.xVWvbc/Tests.xcresult` and `xcodebuild.log`; build log:
`/tmp/castify-podcast-notifications-bounded-history-build.log`; summary:
`/tmp/castify-podcast-notifications-bounded-history-test-summary.json`. The Mac
connection dropped during the run; after recovery, the existing completed bundle
was verified without launching a duplicate runner.
