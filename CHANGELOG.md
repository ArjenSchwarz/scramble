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
- Phase 1 foundation spec under `specs/phase-1-foundation/`: requirements (56 acceptance criteria across data model, CloudKit container, theme, app shell, Trip List + auto-open, Trip Detail scaffold, Master Lists scaffold, Trip editor, people management, avatars), design (architecture, components, data model with SwiftData entities + inverse relationships + delete rules + Codable blobs + VersionedSchema, error handling, testing strategy), decision log (15 Nygard ADRs covering scope cut, global people, date semantics, theme/appearance, country-flag deferral, tab-bar hide on detail, no seeded people, CKShare-zone deferral, data-model integrity, VersionedSchema-from-day-one, behavioural test/preview rule, person duplicates, minimal phase-node states, string-raw enum bridges, cross-device person-delete tolerance), and 27-task implementation plan with TDD pairing and stable-ID dependencies (`tasks.md`).
