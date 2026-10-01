# Castify

Castify is a SwiftUI podcast player for iOS. It supports podcast search through the iTunes API, podcast subscriptions, RSS episode browsing, streaming playback, local episode downloads, background audio, and lock-screen playback controls.

## Run

1. Open `Podcasts.xcodeproj` in Xcode.
2. Select the `Podcasts` scheme and run on an iOS simulator or device.

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
