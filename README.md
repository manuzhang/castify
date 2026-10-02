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

## Tests

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

## Episode Summary Provider Interface

`EpisodeSummaryService` accepts an injected `EpisodeSummaryProvider`. Both
`RemoteEpisodeSummaryProvider` and `LocalEpisodeSummaryProvider` implement that
contract. A request contains an episode ID, supplied transcript/show-notes text,
an optional source URL, and an output language code. A successful result contains
an overview, key points, and the input's provenance plus the provider ID.
Transcript provenance does not imply that the supplied text covers the full episode.

Providers report current availability and supported source types, optional
language restrictions, and optional input-length limits. The service validates
inputs/results and delivers exactly one asynchronous main-queue completion.
Its cancellation handle forwards cancellation to the injected operation and
reports `.cancelled`; whichever terminal result arrives first wins. Adapters
map transport/model failures to the shared `EpisodeSummaryError` cases.

`EpisodeSummaryService()` defaults to `LocalEpisodeSummaryProvider`, backed by
`OfflineExtractiveSummarizer`. It runs entirely on-device with the operating
system's NaturalLanguage sentence/word tokenization and language detection.
There are no credentials, network calls, model downloads, or external services.
`RemoteEpisodeSummaryProvider` remains opt-in and unavailable (`notConfigured`)
until an operation is injected. Other local engines can also be injected with
their own readiness checks and capabilities. Foundation callbacks and
NaturalLanguage APIs preserve the iOS 13 deployment target.

The offline method removes common caption metadata and isolated stage cues,
deduplicates sentences, and ranks sentences by average term frequency across
unique sentences, excluding common stop words. A small earlier-position bonus
breaks similar scores; exact ties follow source order. The overview is the
highest-ranked whole sentence; up to five key sentences follow source order.
Each sentence is limited to 320 characters, and input to 120,000 characters.
Long sentences are skipped rather than truncated; no usable sentence produces
`insufficientContent`. Results explicitly report the `extractive` method.

English and simplified/traditional Chinese are supported. Text is preserved,
not rewritten or translated. Requested language must match the detected source
language; Chinese script changes and other language requests return
`unsupportedLanguage`. Language detection can be uncertain for very short or
mixed-language text. Sentences in another script are omitted, and repeated
wording, stop-word heuristics, or long sentences can affect coverage. Selection
is deterministic for the same system tokenizer/input and is not a guarantee of
full transcript or audio coverage. Cancellation stops work between processing
stages and during sentence enumeration; individual system NLP calls are bounded
by the input limit.

Tests inject explicitly marked fixture output to verify interchangeable
providers, provenance, readiness, validation, errors, cancellation, and callback
delivery. Fixture summaries are test-only and never displayed by the app.
Additional tests exercise the real offline implementation with English/Chinese,
noise, repetition, bounds, language mismatches, determinism, and cancellation.
Remote provider/model selection and credentials/backend, transcript discovery
and fetching, caching, and episode UI integration remain follow-up work.

## Crash Reporting

Castify initializes Sentry at launch when the `SENTRY_DSN` build setting is set.
Leave it empty for local builds that should not send crash reports.

Sentry is pinned to 8.58.3 in `project.yml` to preserve Castify's iOS 13 support.
[Sentry 9.29.2 requires iOS 15](https://github.com/getsentry/sentry-cocoa/blob/9.29.2/Package.swift),
so an upgrade requires a deliberate minimum-iOS decision. No crash-reporting API
changes are needed for 8.58.3.
