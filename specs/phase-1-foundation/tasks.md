---
references:
    - specs/phase-1-foundation/requirements.md
    - specs/phase-1-foundation/design.md
    - specs/phase-1-foundation/decision_log.md
---
# Phase 1 Foundation Implementation

## Foundation types

- [x] 1. Define core enums <!-- id:1n8gan0 -->
  - Add Models/Enums.swift with Phase, ItemSource, PackingState, TripAttribute (all String-rawValue Codable enums).
  - Pure types, no behavior — exempt from preceding test task per TDD rule.
  - Phase: weeksBefore, dayBefore, departureDay, duringTrip, dayBeforeReturn, returnDay, afterTrip.
  - ItemSource: rule, manual.
  - PackingState: unpacked, packed, repacked, excluded.
  - TripAttribute: duration, transport, scope, weather, purpose.
  - Stream: 1
  - Requirements: [1.10](requirements.md#1.10), [1.11](requirements.md#1.11)

- [x] 2. Tests: TripAttributes Codable round-trip + helpers <!-- id:1n8gan1 -->
  - Add ScrambleTests/Models/TripAttributesTests.swift covering empty, single-value, multi-value (weather), and helpers setSingle/toggle/selected.
  - Include a Swift Testing parameterized test for round-trip property (decode(encode(x)) == x) with a generator over arbitrary attribute selections (single-select for D/T/S/P, 0–4 weather values).
  - Cover decode-failure fallback returns .init() (corrupt blob).
  - Blocked-by: 1n8gan0 (Define core enums)
  - Stream: 1
  - Requirements: [1.6](requirements.md#1.6), [1.11](requirements.md#1.11)

- [x] 3. Implement TripAttributes <!-- id:1n8gan2 -->
  - Add Models/Codable/TripAttributes.swift with the struct + Codable + helpers (selected, setSingle, toggle).
  - Blocked-by: 1n8gan1 (Tests: TripAttributes Codable round-trip + helpers)
  - Stream: 1
  - Requirements: [1.6](requirements.md#1.6), [1.11](requirements.md#1.11)

- [x] 4. Tests: ItemConditions Codable + evaluator <!-- id:1n8gan3 -->
  - Add ScrambleTests/Models/ItemConditionsTests.swift, table-driven across always/match/all/any.
  - Table cases for evaluator: .always, .match hit, .match miss, nested .all all-true, nested .all with one false, nested .any any-true, nested .any all-false, empty .all (vacuous true), empty .any (vacuous false).
  - Add a Swift Testing parameterized round-trip test (depth-bounded recursive generator, max depth 3): decode(encode(c)) == c.
  - Idempotence: c.evaluate(against:a) == c.evaluate(against:a) on second call.
  - Distributive equivalence: .all([.match(.weather,[x])]).evaluate == .match(.weather,[x]).evaluate.
  - Blocked-by: 1n8gan0 (Define core enums)
  - Stream: 1
  - Requirements: [1.7](requirements.md#1.7)

- [x] 5. Implement ItemConditions <!-- id:1n8gan4 -->
  - Add Models/Codable/ItemConditions.swift with the indirect enum + custom Codable using a discriminator key + evaluate(against:).
  - Blocked-by: 1n8gan3 (Tests: ItemConditions Codable + evaluator)
  - Stream: 1
  - Requirements: [1.7](requirements.md#1.7)

- [x] 6. Tests: TripStatus.compute table-driven <!-- id:1n8gan5 -->
  - Add ScrambleTests/TripStatusTests.swift covering upcoming/inProgress/returningSoon/completed across edge cases (today=start, today=end, midnight boundary, time-zone shift).
  - Status enum cases per design.md: upcoming(daysAway), inProgress(currentDay,totalDays), returningSoon(daysUntilEnd), completed(daysSinceEnd).
  - 'returning soon' threshold: within 2 days of trip end.
  - Use injected Calendar + today: Date for determinism.
  - Blocked-by: 1n8gan0 (Define core enums)
  - Stream: 1
  - Requirements: [5.4](requirements.md#5.4)

- [x] 7. Implement TripStatus + LocalizedTripStatus <!-- id:1n8gan6 -->
  - Add Features/Trips/TripStatus.swift with the enum + pure compute(trip:today:calendar:) function + a separate LocalizedTripStatus(_:) formatter.
  - Blocked-by: 1n8gan5 (Tests: TripStatus.compute table-driven)
  - Stream: 1
  - Requirements: [5.4](requirements.md#5.4)

## Persistence

- [x] 8. Tests: SwiftData schema + entities + relationships + delete rules <!-- id:1n8gan7 -->
  - Add ScrambleTests/Persistence/SchemaTests.swift covering: container constructs with SchemaV1, all 6 entities round-trip, inverse relationships work both directions, cascade Trip→TripTask + Trip→TripPackingItem, deny Person→TripPackingItem and Person→MasterPackingItem (assert save throws), nullify on Person delete from Trip.participants, Person.initial extraction (first grapheme uppercased, '?' on empty), Codable bridge round-trip via attributesData↔attributes and conditionsData↔conditions, phaseRaw/sourceRaw/stateRaw bridge round-trip, masterItemID dangling reference tolerated.
  - Use in-memory ModelContainer (cloudKitDatabase:.none) constructed directly, not ModelStore.shared.
  - Person.initial test cases pin grapheme behavior across simple letters, accented letters, empty string, and ZWJ-joined emoji.
  - Blocked-by: 1n8gan0 (Define core enums), 1n8gan2 (Implement TripAttributes), 1n8gan4 (Implement ItemConditions)
  - Stream: 1
  - Requirements: [1.1](requirements.md#1.1), [1.2](requirements.md#1.2), [1.3](requirements.md#1.3), [1.4](requirements.md#1.4), [1.5](requirements.md#1.5), [1.8](requirements.md#1.8), [1.9](requirements.md#1.9), [1.10](requirements.md#1.10), [1.12](requirements.md#1.12), [1.13](requirements.md#1.13), [9.6](requirements.md#9.6), [9.7](requirements.md#9.7)

- [x] 9. Implement SwiftData entities + SchemaV1 + AppMigrationPlan <!-- id:1n8gan8 -->
  - Add Models/Trip.swift, Models/Person.swift, Models/MasterTaskItem.swift, Models/MasterPackingItem.swift, Models/TripTask.swift, Models/TripPackingItem.swift, Models/Schema.swift (VersionedSchema + empty SchemaMigrationPlan).
  - Inverse declared on owning side only: Trip.participants(inverse:\Person.trips), Trip.tasks(inverse:\TripTask.trip), Trip.packingItems(inverse:\TripPackingItem.trip), TripPackingItem.person(inverse:\Person.tripPackingItems), MasterPackingItem.person(inverse:\Person.masterPackingItems).
  - Non-owning side: plain @Relationship var (no inverse argument).
  - Delete rules: cascade Trip→tasks/packing, deny Person→TripPackingItem, deny Person→MasterPackingItem, nullify Person→Trip via Trip.participants.
  - Codable bridges as computed extensions: attributes (TripAttributes), conditions (ItemConditions), phase, source, state — log decode failures via os_log(.error).
  - Person.initial computed extension.
  - All entities expose id: UUID = UUID() set client-side. Default values on every property; no @Attribute(.unique).
  - Blocked-by: 1n8gan7 (Tests: SwiftData schema + entities + relationships + delete rules)
  - Stream: 1
  - Requirements: [1.1](requirements.md#1.1), [1.2](requirements.md#1.2), [1.3](requirements.md#1.3), [1.4](requirements.md#1.4), [1.5](requirements.md#1.5), [1.8](requirements.md#1.8), [1.10](requirements.md#1.10), [1.12](requirements.md#1.12), [1.13](requirements.md#1.13)

- [x] 10. Tests: ModelStore EnvironmentProbe selector branches <!-- id:1n8gan9 -->
  - Add ScrambleTests/Persistence/ModelStoreEnvironmentTests.swift covering each branch (unit-test env, UI-test launch arg, preview env, production fallthrough) returns the expected ModelConfiguration shape using injected EnvironmentProbe.
  - Probe takes injected EnvironmentProbe(environment:[String:String], arguments:[String]).
  - Real ProcessInfo.processInfo cannot be mocked — assertions must be over the probe-derived configuration, not the real shared container.
  - Blocked-by: 1n8gan8 (Implement SwiftData entities + SchemaV1 + AppMigrationPlan)
  - Stream: 1
  - Requirements: [2.1](requirements.md#2.1), [2.2](requirements.md#2.2)

- [x] 11. Implement EnvironmentProbe + ModelStore <!-- id:1n8gana -->
  - Add Persistence/EnvironmentProbe.swift and Persistence/ModelStore.swift.
  - ModelStore.shared is @MainActor static let; production tries CloudKit .private then silently falls back to local-only on throw, logging via os_log(.error) with a distinctive marker string.
  - Detection: XCTestConfigurationFilePath env var, -uitest 1 arg, XCODE_RUNNING_FOR_PREVIEWS env var.
  - Three branches return in-memory container (cloudKitDatabase:.none) per design.md.
  - Production CloudKit container uses .private('iCloud.me.nore.ig.scramble') with SchemaV1 + AppMigrationPlan.
  - Local fallback uses default location, .none database; if local fallback also throws → fatalError.
  - Blocked-by: 1n8gan9 (Tests: ModelStore EnvironmentProbe selector branches)
  - Stream: 1
  - Requirements: [2.1](requirements.md#2.1), [2.2](requirements.md#2.2), [2.3](requirements.md#2.3), [2.4](requirements.md#2.4)

## Theme

- [x] 12. Tests: Theme + PersonPalette behaviour <!-- id:1n8ganb -->
  - Add ScrambleTests/Theme/ThemeTests.swift covering: variant(for:.dark) and variant(for:.light) return the right ThemeVariant; personColor(key:in:) resolves all 8 Midnight Atlas palette keys for both schemes; PersonPalette.entry(forKey:) hit/miss; PersonPalette.nextUnusedKey behavior across empty / partial / full(8) sets (returns first canonical entry on full per design.md).
  - Stream: 1
  - Requirements: [3.1](requirements.md#3.1), [3.2](requirements.md#3.2), [3.3](requirements.md#3.3), [3.4](requirements.md#3.4), [3.5](requirements.md#3.5), [3.6](requirements.md#3.6)

- [x] 13. Implement Theme + ThemeVariant + PaletteEntry + PersonPalette + MidnightAtlas + ThemeKey <!-- id:1n8ganc -->
  - Add Theme/Theme.swift (struct definitions, Sendable conformance, EnvironmentKey, EnvironmentValues.theme extension), Theme/MidnightAtlas.swift (color/gradient constants per UI design doc table), Theme/PersonPalette.swift (palette types + nextUnusedKey).
  - Blocked-by: 1n8ganb (Tests: Theme + PersonPalette behaviour)
  - Stream: 1
  - Requirements: [3.1](requirements.md#3.1), [3.2](requirements.md#3.2), [3.3](requirements.md#3.3), [3.4](requirements.md#3.4), [3.5](requirements.md#3.5), [3.6](requirements.md#3.6)

## UI components

- [x] 14. Implement PersonAvatar view <!-- id:1n8gand -->
  - Add Components/PersonAvatar.swift. Reads theme from environment to resolve color from colorKey.
  - Three sizes (compact 14, standard 26, large 36). isActive flag affects border opacity.
  - Pure SwiftUI render component — visual contract validated via UI tests in later tasks.
  - Initial extraction lives on Person entity (covered by SchemaTests in task 8).
  - PersonAvatar.Size enum nested inside PersonAvatar.
  - Blocked-by: 1n8ganc (Implement Theme + ThemeVariant + PaletteEntry + PersonPalette + MidnightAtlas + ThemeKey)
  - Stream: 1
  - Requirements: [10.1](requirements.md#10.1), [10.2](requirements.md#10.2), [10.3](requirements.md#10.3)

- [x] 15. Implement PhaseNodeMarker view <!-- id:1n8gane -->
  - Add Components/PhaseNodeMarker.swift with PhaseNodeState enum (past, current, future) and the marker view.
  - Past = filled circle in phaseColor with white SF Symbol checkmark; Current = filled circle in phaseColor (no glow ring per Decision 13); Future = clear circle with 1.5pt stroke in phaseColor.
  - Full PhaseNode visual treatment (glow ring, NOW pill) is out of scope per Non-Goals; ship only the three distinct states.
  - Blocked-by: 1n8ganc (Implement Theme + ThemeVariant + PaletteEntry + PersonPalette + MidnightAtlas + ThemeKey)
  - Stream: 1
  - Requirements: [6.4](requirements.md#6.4)

## App shell

- [x] 16. Refactor app shell: replace template, wire RootView + ModelStore + theme env <!-- id:1n8ganf -->
  - Delete Models/Item.swift (template), replace ContentView.swift (or delete and reference RootView from ScrambleApp).
  - Update ScrambleApp.swift to use ModelStore.shared and inject .environment(\.theme, .midnightAtlas).
  - Add Features/Root/RootView.swift with TabView containing two tabs (Trips, Master Lists; Liquid Glass treatment is system-applied to root TabView in iOS 26).
  - Add empty Features/Trips/TripsTab.swift and Features/MasterLists/MasterListsTab.swift placeholders.
  - Tab labels: 'Trips' (suitcase symbol) and 'Master Lists' (list.bullet.rectangle symbol). Default selected tab: Trips.
  - Wiring task — exempt from preceding test. Project must build after this task.
  - Blocked-by: 1n8gana (Implement EnvironmentProbe + ModelStore), 1n8ganc (Implement Theme + ThemeVariant + PaletteEntry + PersonPalette + MidnightAtlas + ThemeKey)
  - Stream: 1
  - Requirements: [4.1](requirements.md#4.1), [4.2](requirements.md#4.2), [4.4](requirements.md#4.4), [4.5](requirements.md#4.5)

## Trip surfaces

- [ ] 17. Implement MasterListsTab placeholder <!-- id:1n8gang -->
  - Replace placeholder in Features/MasterLists/MasterListsTab.swift with segmented control (Packing Items / Tasks) and per-segment empty-state placeholder explaining master-list editing arrives in a later phase.
  - No item creation, editing, or deletion affordances per AC 7.3.
  - Blocked-by: 1n8ganf (Refactor app shell: replace template, wire RootView + ModelStore + theme env)
  - Stream: 1
  - Requirements: [7.1](requirements.md#7.1), [7.2](requirements.md#7.2), [7.3](requirements.md#7.3)

- [ ] 18. Implement TripListView <!-- id:1n8ganh -->
  - Add Features/Trips/TripListView.swift with @Query-driven Active and Previous sections (calendar-day comparison via Calendar.current.startOfDay).
  - '+ New Trip' dashed-border button below Active section opens TripEditorView in create mode.
  - Each row shows name + date range + LocalizedTripStatus.
  - Tap pushes Trip onto navigation path. Previous section collapsed by default.
  - Blocked-by: 1n8gan6 (Implement TripStatus + LocalizedTripStatus), 1n8ganf (Refactor app shell: replace template, wire RootView + ModelStore + theme env)
  - Stream: 1
  - Requirements: [5.1](requirements.md#5.1), [5.2](requirements.md#5.2), [5.3](requirements.md#5.3), [5.4](requirements.md#5.4), [5.5](requirements.md#5.5)

- [ ] 19. Implement TripDetailView scaffold <!-- id:1n8gani -->
  - Add Features/Trips/TripDetailView.swift with sticky header (trip name + date range + status line per task 7), attribute chip row tappable to open editor scrolled to that attribute, vertical 2pt spine with 7 PhaseNodeMarker instances labelled with phase names, Edit affordance opens TripEditorView in edit mode, Delete affordance with confirmation dialog removes trip and pops back.
  - Apply .toolbar(.hidden, for: .tabBar).
  - Phase node state computed from today vs trip date range (calendar-day) — past, current, future.
  - Use phase colors from active theme.phaseColours indexed by Phase.allCases.
  - Confirmation dialog for delete; on confirm, modelContext.delete(trip) and dismiss.
  - Blocked-by: 1n8gane (Implement PhaseNodeMarker view), 1n8ganf (Refactor app shell: replace template, wire RootView + ModelStore + theme env)
  - Stream: 1
  - Requirements: [4.3](requirements.md#4.3), [6.1](requirements.md#6.1), [6.2](requirements.md#6.2), [6.3](requirements.md#6.3), [6.4](requirements.md#6.4), [6.5](requirements.md#6.5), [6.6](requirements.md#6.6)

## Editor + People

- [ ] 20. Tests: TripDraft.validate <!-- id:1n8ganj -->
  - Add ScrambleTests/Features/TripDraftTests.swift table-driven over: empty name, end < start, both invalid, all valid.
  - Blocked-by: 1n8gan0 (Define core enums)
  - Stream: 1
  - Requirements: [8.1](requirements.md#8.1), [8.6](requirements.md#8.6)

- [ ] 21. Implement TripDraft + TripEditorView + PersonEditor <!-- id:1n8gank -->
  - Add Features/Trips/TripDraft.swift (value-type draft + validate()).
  - Add Features/Trips/TripEditorView.swift (Form sections: name+dates, attribute pickers (4 single-select, 1 multi-select for weather), people add/remove with PersonAvatar rows, inline create affordance).
  - Add Features/People/PersonEditor.swift (sheet with name + palette picker showing 8 colors + duplicate-color advisory using nextUnusedKey result).
  - Blocked-by: 1n8gand (Implement PersonAvatar view), 1n8ganj (Tests: TripDraft.validate)
  - Stream: 1
  - Requirements: [8.1](requirements.md#8.1), [8.2](requirements.md#8.2), [8.3](requirements.md#8.3), [8.4](requirements.md#8.4), [8.5](requirements.md#8.5), [8.6](requirements.md#8.6), [9.1](requirements.md#9.1), [9.3](requirements.md#9.3), [9.4](requirements.md#9.4), [9.5](requirements.md#9.5)

- [ ] 22. Wire trip create/edit/delete + orphan-participant resolution <!-- id:1n8ganl -->
  - Hook TripEditorView from TripListView (create) and TripDetailView (edit) including the orphanedParticipants toast: on save, resolve participantIDs via FetchDescriptor<Person>(predicate: #Predicate { ids.contains($0.id) }), drop missing IDs silently, surface a transient toast naming them.
  - Wire delete with confirmation from TripDetailView.
  - Wire person delete denial alert (catch SwiftData throw on .deny, list referencing trips/items).
  - Blocked-by: 1n8ganh (Implement TripListView), 1n8gani (Implement TripDetailView scaffold), 1n8gank (Implement TripDraft + TripEditorView + PersonEditor)
  - Stream: 1
  - Requirements: [8.5](requirements.md#8.5), [9.7](requirements.md#9.7)

## Auto-open

- [ ] 23. Tests: singleQualifyingTrip predicate <!-- id:1n8ganm -->
  - Add ScrambleTests/Features/TripsTabPredicateTests.swift table-driven over: empty trips→nil, one qualifying→that trip, one non-qualifying (start > today+2d, or end < today)→nil, two qualifying→nil, edge cases (start = today+2d, end = today).
  - Blocked-by: 1n8gan8 (Implement SwiftData entities + SchemaV1 + AppMigrationPlan)
  - Stream: 1
  - Requirements: [5.6](requirements.md#5.6)

- [ ] 24. Implement TripsTab auto-open + predicate <!-- id:1n8gann -->
  - Add singleQualifyingTrip(in:today:calendar:) helper.
  - Implement TripsTab.swift fully: NavigationStack(path:), @Query private var trips, @State path: NavigationPath, @State didAttemptAutoOpen = false (NOT @SceneStorage), .task(id: 'trips-tab-mount') runs once and sets didAttemptAutoOpen = true BEFORE appending to path, navigationDestination(for: Trip.self) renders TripDetailView with .toolbar(.hidden, for: .tabBar).
  - Use @State NOT @SceneStorage — code-review-visible comment per design.
  - Guard ordering: set flag before path mutation.
  - Blocked-by: 1n8ganh (Implement TripListView), 1n8gani (Implement TripDetailView scaffold), 1n8ganm (Tests: singleQualifyingTrip predicate)
  - Stream: 1
  - Requirements: [4.3](requirements.md#4.3), [5.6](requirements.md#5.6), [5.7](requirements.md#5.7)

## UI tests

- [ ] 25. AppLaunchUITests <!-- id:1n8gano -->
  - Add ScrambleUITests/AppLaunchUITests.swift. setUp constructs XCUIApplication, sets app.launchArguments = ['-uitest', '1'] BEFORE app.launch().
  - One test asserts the app launched with the in-memory container (via a debug-only accessibility identifier on RootView, e.g. 'modelStore.in-memory').
  - Add the debug-only accessibility identifier to RootView in this task (under #if DEBUG) since it is the test hook.
  - Blocked-by: 1n8ganf (Refactor app shell: replace template, wire RootView + ModelStore + theme env)
  - Stream: 1
  - Requirements: [2.2](requirements.md#2.2)

- [ ] 26. RootNavigationUITests <!-- id:1n8ganp -->
  - Add ScrambleUITests/RootNavigationUITests.swift covering: cold launch with zero trips → Trip List; cold launch with one qualifying trip → Trip Detail; cold launch with one non-qualifying trip → Trip List; cold launch with two qualifying trips → Trip List; tab bar hidden on Trip Detail and restored on pop; testAutoOpenDoesNotRefireOnTabSwitch (switch to Master Lists and back, assert auto-opened detail does not re-push).
  - Test fixtures use the in-memory container; pre-seed via a debug-only test-data launch argument (e.g., -seed-fixture 'one-qualifying-trip') that the app reads under #if DEBUG.
  - Blocked-by: 1n8gann (Implement TripsTab auto-open + predicate)
  - Stream: 1
  - Requirements: [4.3](requirements.md#4.3), [5.6](requirements.md#5.6), [5.7](requirements.md#5.7)

- [ ] 27. TripCRUDUITests <!-- id:1n8ganq -->
  - Add ScrambleUITests/TripCRUDUITests.swift covering: create trip (tap +New, fill name+dates+attributes, save, verify in list); edit trip attributes (open detail, edit, change weather to multi-select, save, verify chips updated); delete trip (open detail, delete, confirm, verify trip disappears from list).
  - Blocked-by: 1n8ganl (Wire trip create/edit/delete + orphan-participant resolution)
  - Stream: 1
  - Requirements: [5.3](requirements.md#5.3), [6.5](requirements.md#6.5), [6.6](requirements.md#6.6), [8.1](requirements.md#8.1), [8.2](requirements.md#8.2), [8.3](requirements.md#8.3), [8.5](requirements.md#8.5)
