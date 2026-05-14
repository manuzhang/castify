# AGENTS.md

This file applies to the whole repository.

## Project

Castify is a SwiftUI podcast player for iOS. The app target is `Podcasts`,
the built app is `Castify`, and the bundle identifier is
`io.github.manuzhang.Castify`.

Primary code lives under `Podcasts/`:

- `Podcasts/Scenes/` contains SwiftUI screens and view models.
- `Podcasts/Services/` contains app services for podcasts, networking,
  localization, OPML import, and persistence.
- `Podcasts/Core/Podcasts/Models/` contains podcast data models.
- `Podcasts/Extensions/` contains shared extensions and app constants.
- `Podcasts.xcodeproj` is the Xcode project to build and run.

## Branching

Start each independent task from a fresh branch based on `origin/main` unless
the user explicitly asks to continue an existing branch:

```sh
git fetch origin
git checkout -b codex/<short-task-name> origin/main
```

Before editing, inspect `git status --short --branch`. Do not revert,
overwrite, or clean up unrelated local changes. Leave unrelated untracked files
alone.

Keep each branch focused on one feature or fix. Do not stack new work on a PR
branch unless the user asks for follow-up work on that PR.

## Build And Run

Use this command as the default verification:

```sh
xcodebuild -project Podcasts.xcodeproj -scheme Podcasts -destination 'generic/platform=iOS Simulator' build
```

There is currently no dedicated test target. A successful simulator build is
the baseline verification unless a task adds tests or the user asks for more.

To refresh the booted simulator with the current branch:

```sh
xcodebuild -project Podcasts.xcodeproj -scheme Podcasts -destination 'generic/platform=iOS Simulator' -derivedDataPath /private/tmp/castify-derived build
xcrun simctl terminate booted io.github.manuzhang.Castify
xcrun simctl install booted /private/tmp/castify-derived/Build/Products/Debug-iphonesimulator/Castify.app
xcrun simctl launch booted io.github.manuzhang.Castify
```

If no simulator is booted, open Simulator first and boot a device before
installing.

## Coding Guidelines

Follow existing patterns instead of introducing new architecture:

- Add user-visible strings to `LocalizationService` in both English and Chinese.
- Add new `UserDefaults` keys to `UserDefaultsExtensions.swift`; access them
  through service or view-model APIs instead of scattering raw keys.
- Keep podcast library, playback state, downloads, and listening data in
  `PodcastsService` unless a narrower existing service owns the behavior.
- Keep playback behavior in `Scenes/Player/Player.swift`.
- Keep Settings UI in `Scenes/Settings/SettingsView.swift` and state/actions in
  `Scenes/Settings/SettingsViewModel.swift`.
- Keep Browse/search behavior in `Scenes/Browse/`.
- Prefer small, scoped changes over broad refactors.
- Use SF Symbols for simple SwiftUI row/button icons when the app already uses
  them nearby.

## Git And PRs

Use conventional commit subjects such as `feat:`, `fix:`, `docs:`, or
`chore:`. If Codex authors a commit, append this trailer as the final paragraph:

```text
Co-authored-by: Codex <codex@openai.com>
```

Before creating a PR, run the simulator build command above and include the
verification command in the PR body.
