# Development

## Project configuration

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

## Build and regression validation

The shared `Podcasts` scheme runs `PodcastsTests`, covering solid-color artwork
placeholders, local playback (play, pause, seek, and queue navigation), and the
episode-summary provider contract using test doubles.
Speed tests cover saved/default selections, paused changes, resume, episode
switches, rate-correct listening statistics, playback metadata, and
English/Chinese player renderings.
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

For a build using only the committed dependency lockfile:

```sh
xcodebuild -project Podcasts.xcodeproj -scheme Podcasts -configuration Debug \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath build/DerivedData \
  -onlyUsePackageVersionsFromResolvedFile CODE_SIGNING_ALLOWED=NO build
```

After regeneration, check for generated-project drift with
`git diff --exit-code -- Podcasts.xcodeproj`.

## Playback behavior

The player speed button offers 0.75×, 1×, 1.25×, 1.5×, 1.75×, and 2×. Selection
is saved across launches and applied on play/resume and episode changes while
preserving audio pitch. Changing speed while idle/paused does not start playback;
Next/Previous also keep paused audio paused. Lock-screen playback metadata
reports the selected speed and a zero current rate while paused.
Listening statistics count time spent listening, normalized for playback speed,
including intervals across speed changes, pauses, and episode switches.

## Crash reporting and iOS compatibility

Castify initializes Sentry at launch when the `SENTRY_DSN` build setting is set.
Leave it empty for local builds that should not send crash reports.

Sentry is pinned to 8.58.3 in `project.yml` to preserve Castify's iOS 13 support.
[Sentry 9.29.2 requires iOS 15](https://github.com/getsentry/sentry-cocoa/blob/9.29.2/Package.swift),
so an upgrade requires a deliberate minimum-iOS decision. No crash-reporting API
changes are needed for 8.58.3.

[Back to README](../README.md)
