# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added

- Xcode project (`Scramble/Scramble.xcodeproj`) generated from the iOS App template: SwiftUI + SwiftData, iOS 26.4 deployment target, Swift 6 language mode, MainActor-default actor isolation, approachable concurrency.
- CloudKit capability wired to container `iCloud.me.nore.ig.scramble` (entitlements + `UIBackgroundModes: remote-notification` for silent push).
- `Makefile` wrapping `xcodebuild` with help/build/test/install/run/lint/format targets, conditional `xcbeautify`/`swiftlint`/`swift-format` detection, repo-local `./DerivedData`, and serial simulator execution to avoid flakes. Defaults: `SIMULATOR=iPhone 17 Pro`, `DEVICE_MODEL=iPhone 17 Pro`, `CONFIG=Debug`.
- `.gitignore` covering Xcode user state, build output, SPM, and common third-party tool directories.
- Functional design document (`docs/scramble-design-doc.md`) covering trips, phases, tasks, packing lists, the rules engine, CloudKit sharing, and the conceptual data model.
- UI/UX design document (`docs/scramble-ui-design-doc.md`) covering the timeline-based Trip Detail screen, packing sheet (pack/repack modes), explainability long-press, Midnight Atlas theme, person colour palette, colour semantics, haptics, and accessibility.
- React/HTML visual prototype (`docs/data.jsx`, `docs/direction-a.jsx`, `docs/Scramble Directions.html`) as reference for the intended look-and-feel — not a port target.
- `CLAUDE.md` orienting future Claude Code sessions to the design docs, load-bearing architectural decisions, the recommended implementation order, and the Makefile-driven build/test workflow.
