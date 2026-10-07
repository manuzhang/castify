# Castify

Castify is a SwiftUI podcast player for iOS. It supports podcast search through the iTunes API, podcast subscriptions, RSS episode browsing, streaming playback, local episode downloads, background audio, and lock-screen playback controls.

## Run

1. Run `sh scripts/generate-project.sh` after checkout or project-setting changes.
2. Open `Podcasts.xcodeproj` in Xcode.
3. Select the `Podcasts` scheme and run on an iOS simulator or device.

## Project Configuration

Edit `project.yml` for targets, source/resource membership, build settings,
schemes, and package dependencies. `Podcasts.xcodeproj` is generated and committed
for convenient opening in Xcode; do not edit it independently. Source files are
discovered from the configured directories when the project is regenerated.

The generation script downloads XcodeGen 2.46.0 to a temporary cache and verifies
the pinned official release checksum. No global installation is required.
The first run needs internet access. Set `XCODEGEN_CACHE_DIR` to choose the cache
location. CI regenerates the project and fails if the committed output differs.

The only dependency lockfile is
`Podcasts.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`.
It records Xcode's resolution; it is generated data, not another configuration.
There is no separate root Swift package. To update Sentry, change its version in
`project.yml`, regenerate, then resolve and commit the resulting project/lockfile:

```sh
sh scripts/generate-project.sh
xcodebuild -resolvePackageDependencies -project Podcasts.xcodeproj -scheme Podcasts
```

Dependabot continues updating GitHub Actions. Swift dependency updates are made
through `project.yml` so they cannot change an unused root package independently.

## Playback Speed

The player speed button offers 0.75×, 1×, 1.25×, 1.5×, 1.75×, and 2×. Selection
is saved across launches and applied on play/resume and episode changes while
preserving audio pitch. Changing speed while idle/paused does not start playback;
Next/Previous also keep paused audio paused. Lock-screen playback metadata
reports the selected speed and a zero current rate while paused.
Listening statistics count time spent listening, normalized for playback speed,
including intervals across speed changes, pauses, and episode switches.

## New Episode Alerts

Each subscribed podcast has an opt-in alert toggle. Alerts require the global
Notifications setting and iOS authorization, and are checked when RSS feeds
refresh. The first refresh establishes a baseline without historical alerts;
closed-app discovery is not guaranteed. See [notification behavior and testing](docs/podcast-notifications.md).

## Episode Filters

Open **Podcasts → All Episodes** to browse episodes from subscribed feeds, newest
first. Combine **Unplayed only**, **Downloaded only**, **Podcast**, and **Duration**
filters; **Reset filters** restores the full list. Partially listened episodes
remain unplayed until marked or completed. Duration ranges are under 15 minutes,
15–30, 30–60, and 60 or more, with a separate unknown-duration option. Boundaries
belong to the longer range. Filters apply to reported episode duration, not time
remaining, and last while the screen remains open.

Feed metadata is cached on successful refreshes. The first visit refreshes
subscriptions, and the refresh button checks again. Once cached, episodes remain
visible offline and failed feeds retain their previous snapshot. Older cached
items with available downloads are retained even if a feed drops them; missing
download files do not match the download filter. Existing downloads acquire feed
ownership when their metadata is first fetched, so a first visit offline may have
no cached episodes. Unsubscribing removes that feed's cached library metadata.
Select a result to open its existing episode/playback controls; its queue uses
the filtered results. Long-press a result to mark it played or unplayed.

## Tests

The shared `Podcasts` scheme runs `PodcastsTests`, covering solid-color artwork
placeholders and local playback (play, pause, seek, and queue navigation).
Speed tests cover saved/default selections, paused changes, resume, episode
switches, rate-correct listening statistics, playback metadata, and
English/Chinese player renderings.
Episode filter tests cover combined criteria, duration boundaries, persistent
feed ownership, offline/partial refreshes, missing download files, unsubscribe
races, and English/Chinese narrow-screen and large-text renderings.
Use the same runner as CI:

```sh
sh scripts/generate-project.sh
bash scripts/run-tests.sh
```

The runner selects an available iPhone type from the newest installed iOS
runtime, creates a fresh simulator, runs tests serially, and removes that
simulator afterward. It does not use existing simulator app data. Results and
logs stay in `build/test-results/run.*/`; open `Tests.xcresult` in Xcode to inspect
failures. The playback fixture uses local audio and makes no network requests.

GitHub Actions runs the tests after generation/drift and build checks. It uploads
the `castify-regression-results` artifact even when tests fail, if results exist,
and keeps it for seven days. The test process's failure status is preserved.

## Crash Reporting

Castify initializes Sentry at launch when the `SENTRY_DSN` build setting is set.
Leave it empty for local builds that should not send crash reports.

Sentry is pinned to 8.58.3 in `project.yml` to preserve Castify's iOS 13 support.
[Sentry 9.29.2 requires iOS 15](https://github.com/getsentry/sentry-cocoa/blob/9.29.2/Package.swift),
so an upgrade requires a deliberate minimum-iOS decision. No crash-reporting API
changes are needed for 8.58.3.
