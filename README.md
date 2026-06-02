# Castify

Castify is a SwiftUI podcast player for iOS. It supports podcast search through the iTunes API, podcast subscriptions, RSS episode browsing, streaming playback, local episode downloads, background audio, and lock-screen playback controls.

## Run

1. Open `Podcasts.xcodeproj` in Xcode.
2. Select the `Podcasts` scheme and run on an iOS simulator or device.

## Crash Reporting

Castify initializes Sentry at launch when the `SENTRY_DSN` build setting is set.
Leave it empty for local builds that should not send crash reports.
