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

## Tests

The shared `Podcasts` scheme runs `PodcastsTests`, covering solid-color artwork
placeholders and local playback (play, pause, seek, and queue navigation).
Choose an installed simulator, for example:

```sh
xcodebuild -project Podcasts.xcodeproj -scheme Podcasts -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

## Crash Reporting

Castify initializes Sentry at launch when the `SENTRY_DSN` build setting is set.
Leave it empty for local builds that should not send crash reports.

Sentry is pinned to 8.58.3 in `project.yml` to preserve Castify's iOS 13 support.
[Sentry 9.29.2 requires iOS 15](https://github.com/getsentry/sentry-cocoa/blob/9.29.2/Package.swift),
so an upgrade requires a deliberate minimum-iOS decision. No crash-reporting API
changes are needed for 8.58.3.
