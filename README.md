# Castify

Castify is a SwiftUI podcast player for iOS 13 and later.

## Features

- Podcast search, subscriptions, and RSS episode browsing.
- Streaming and offline downloads, background audio, and lock-screen controls.
- Up Next queue, resume positions, played/unplayed state, and starred episodes.
- Saved playback speed from 0.75× to 2×.
- Auto-download and Wi-Fi settings, storage controls, and listening statistics.
- English/Chinese interface, OPML import, and GitHub OPML sync.

## Get started

Use Xcode with an installed iOS Simulator runtime. Generate the project first
(the initial generation needs internet access):

```sh
sh scripts/generate-project.sh
```

Open `Podcasts.xcodeproj`, select the `Podcasts` scheme, and run on a simulator.
Browse or search for a podcast, subscribe, and choose an episode to play or
download. Use the player controls for the queue, seek, and playback speed;
changing speed while paused keeps audio paused.

## Build and test

```sh
xcodebuild -project Podcasts.xcodeproj -scheme Podcasts -configuration Debug \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
bash scripts/run-tests.sh
```

## More information

- [Development](docs/development.md): project generation, dependencies, test results,
  playback behavior, and crash reporting.
- [Summary providers](docs/summary-providers.md): developer API and offline extraction.
  Summaries currently require supplied text and are not connected to an episode UI.
  They select original sentences in English or Chinese; they do not translate text
  or guarantee full-episode coverage.
