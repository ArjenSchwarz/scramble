# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added

- Phase 1 theme system: `Theme` (id, displayName, dark/light `ThemeVariant`s, `PersonPalette`) and `ThemeVariant` (background `Gradient`, accent, surface, surfaceBorder, textPrimary, textSecondary, checkColour, warnColour, 7-entry `phaseColours`) value types under `Scramble/Scramble/Theme/Theme.swift`, plus `ThemeKey: EnvironmentKey` + `EnvironmentValues.theme` extension for SwiftUI environment injection. All theme types are `Sendable` and `nonisolated` so they cross task/actor boundaries safely.
- `PersonPalette` + `PaletteEntry` (`Theme/PersonPalette.swift`) with `entry(forKey:)` lookup and `nextUnusedKey(among:)` that always returns a non-optional entry (first canonical entry when the taken set is full, per design — the editor surfaces the duplicate-color advisory in that case).
- `MidnightAtlas` namespace (`Theme/MidnightAtlas.swift`) holding the dark and light variants per the UI design doc colour table, the 8-entry person palette (Cyan, Pink, Yellow, Green, Purple, Orange, Red, Teal) with hex values for both schemes, and the canonical `paletteKeys` order. `Theme.midnightAtlas` static instance wires it all together. Private `Color.hex6` / `Color.rgba` helpers are `nonisolated` for use in static initializers.
- Swift Testing suite `ThemeTests` (`ScrambleTests/Theme/ThemeTests.swift`) covering `variant(for:)` selection across dark/light, `personColor(key:in:)` resolution for every palette key in both schemes, unknown-key nil returns, `PersonPalette.entry(forKey:)` hits and case-sensitive misses, palette canonical order, and `nextUnusedKey` behaviour across empty / partial / sparse / full / unknown-key-tainted taken sets.
- Phase 1 persistence layer: SwiftData `@Model` entities `Trip`, `Person`, `MasterTaskItem`, `MasterPackingItem`, `TripTask`, `TripPackingItem` under `Scramble/Scramble/Models/`, all CloudKit-safe (default values on every property, no `@Attribute(.unique)`, client-assigned `id: UUID`).
- `SchemaV1` (VersionedSchema) and `AppMigrationPlan` (empty stages) in `Models/Schema.swift`, plus a shared `modelLogger` for persistence-layer logging.
- Inverse relationships with delete rules colocated on the owning side: `Trip.participants` (`.nullify`), `Trip.tasks` / `Trip.packingItems` (`.cascade`), `Person.tripPackingItems` / `Person.masterPackingItems` (`.deny`).
- Codable-bridge computed extensions on entities: `Trip.attributes`, `MasterTaskItem.conditions` / `phase`, `MasterPackingItem.conditions`, `TripTask.phase` / `source`, `TripPackingItem.state` / `source`. Decode failures log via `os.Logger` and fall back to defaults rather than crash.
- `Person.initial` computed extension returning the first grapheme uppercased (or `"?"` on empty), correct across simple letters, accented letters, and ZWJ-joined emoji.
- `EnvironmentProbe` value type (`Persistence/EnvironmentProbe.swift`) with injectable `environment` / `arguments` and a `production` factory reading `ProcessInfo.processInfo`. Branches: `isTest` (XCTestConfigurationFilePath), `isUITestHost` (`-uitest 1`), `isPreview` (XCODE_RUNNING_FOR_PREVIEWS=1).
- `ModelStore` (`Persistence/ModelStore.swift`) as `@MainActor enum`: `shared` evaluates `makeContainer(probe: .production)` once at first access; `configuration(probe:)` is `nonisolated` and unit-testable; CloudKit private container (`iCloud.me.nore.ig.scramble`) with `SchemaV1` + `AppMigrationPlan` in production; in-memory + `.none` in tests/UI tests/previews; silent local-only fallback on CloudKit throw logged with `[ModelStore.fallback]`; `fatalError` if local fallback also throws.
- Swift Testing suites for persistence: `SchemaTests` (container construction including with migration plan, six entity round-trips, inverse relationships in both directions, cascade rules, nullify on Person delete, `Person.initial` grapheme behaviour, Codable-blob and raw-enum bridges with unknown-value fallback, dangling `masterItemID` tolerance), and `ModelStoreEnvironmentTests` (each probe branch returns the expected `ModelConfiguration` shape; probe `isTest`/`isUITestHost`/`isPreview` flags; strict UI-test detection).
- `docs/agent-notes/persistence.md` capturing relationship layout, Codable-bridge contract, environment-detection branches, and gotchas (MainActor isolation, Schema construction, file-scope `nonisolated` for shared logger).
- `.swiftlint.yml` opting out of `inclusive_language` (the domain requires "master" terminology) and relaxing length/identifier rules for the schema test suite.

### Changed

- `specs/phase-1-foundation/decision_log.md`: added Decision 16 documenting that SwiftData iOS 26.4 does not reliably enforce `.deny` at save time on in-memory stores. The rule remains declared on `Person.tripPackingItems` and `Person.masterPackingItems` as defense-in-depth; primary enforcement is the UI guard in task 22 per requirement 9.7. SchemaTests replace runtime-throw assertions with inverse-traversal queryability tests.

- Phase 1 foundation types: `Phase`, `ItemSource`, `PackingState`, `TripAttribute` enums (`Models/Enums.swift`); `TripAttributes` Codable struct with `setSingle`/`toggle`/`selected` helpers and deterministic on-disk ordering (`Models/Codable/TripAttributes.swift`); `ItemConditions` indirect enum (`.always`/`.match`/`.all`/`.any`) with discriminator-keyed custom Codable and pure `evaluate(against:)` (`Models/Codable/ItemConditions.swift`); `TripStatus` enum (`upcoming`/`inProgress`/`returningSoon`/`completed`) with pure `compute(startDate:endDate:today:calendar:)` honouring calendar-day granularity and a 2-day `returningSoon` threshold, plus `LocalizedTripStatus` display formatter (`Features/Trips/TripStatus.swift`).
- Swift Testing suites covering all foundation types: `TripAttributesTests` (helpers + Codable round-trip property test across 240 generated samples + corrupt-blob fallback), `ItemConditionsTests` (evaluator table including vacuous empty `.all`/`.any` + idempotence + distributive equivalence + depth-bounded round-trip), `TripStatusTests` (every status case + midnight/timezone boundaries).

### Changed

- `ScrambleApp.sharedModelContainer`: switched the template scaffold to an in-memory store under XCTest and added a local-only fallback on container construction failure so tests can run before `ModelStore` (task 11) replaces this code path.

- Xcode project (`Scramble/Scramble.xcodeproj`) generated from the iOS App template: SwiftUI + SwiftData, iOS 26.4 deployment target, Swift 6 language mode, MainActor-default actor isolation, approachable concurrency.
- CloudKit capability wired to container `iCloud.me.nore.ig.scramble` (entitlements + `UIBackgroundModes: remote-notification` for silent push).
- `Makefile` wrapping `xcodebuild` with help/build/test/install/run/lint/format targets, conditional `xcbeautify`/`swiftlint`/`swift-format` detection, repo-local `./DerivedData`, and serial simulator execution to avoid flakes. Defaults: `SIMULATOR=iPhone 17 Pro`, `DEVICE_MODEL=iPhone 17 Pro`, `CONFIG=Debug`.
- `.gitignore` covering Xcode user state, build output, SPM, and common third-party tool directories.
- Functional design document (`docs/scramble-design-doc.md`) covering trips, phases, tasks, packing lists, the rules engine, CloudKit sharing, and the conceptual data model.
- UI/UX design document (`docs/scramble-ui-design-doc.md`) covering the timeline-based Trip Detail screen, packing sheet (pack/repack modes), explainability long-press, Midnight Atlas theme, person colour palette, colour semantics, haptics, and accessibility.
- React/HTML visual prototype (`docs/data.jsx`, `docs/direction-a.jsx`, `docs/Scramble Directions.html`) as reference for the intended look-and-feel — not a port target.
- `CLAUDE.md` orienting future Claude Code sessions to the design docs, load-bearing architectural decisions, the recommended implementation order, and the Makefile-driven build/test workflow.
- Phase 1 foundation spec under `specs/phase-1-foundation/`: requirements (56 acceptance criteria across data model, CloudKit container, theme, app shell, Trip List + auto-open, Trip Detail scaffold, Master Lists scaffold, Trip editor, people management, avatars), design (architecture, components, data model with SwiftData entities + inverse relationships + delete rules + Codable blobs + VersionedSchema, error handling, testing strategy), decision log (15 Nygard ADRs covering scope cut, global people, date semantics, theme/appearance, country-flag deferral, tab-bar hide on detail, no seeded people, CKShare-zone deferral, data-model integrity, VersionedSchema-from-day-one, behavioural test/preview rule, person duplicates, minimal phase-node states, string-raw enum bridges, cross-device person-delete tolerance), and 27-task implementation plan with TDD pairing and stable-ID dependencies (`tasks.md`).
