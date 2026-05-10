# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project status

Scramble is a native iOS app (macOS planned later) for trip planning, packing, and shared family coordination via CloudKit. The Xcode project exists but holds only template scaffolding (`Item`, `ContentView`); no real models, views, or rules engine have been written yet.

Stack: iOS 26+, Swift 6.0 language mode (Xcode 26 toolchain), SwiftUI, SwiftData, CloudKit (CKShare for per-trip sharing). Bundle ID `me.nore.ig.Scramble`, CloudKit container `iCloud.me.nore.ig.scramble`. Project lives at `Scramble/Scramble.xcodeproj` (nested folder, standard Xcode layout).

## Build, test, run

Use the Makefile — do not invoke `xcodebuild` directly. Common targets:

| Command | Purpose |
|---|---|
| `make` (or `make help`) | List all targets |
| `make build` | Build Debug for iOS Simulator |
| `make test-quick` | Unit tests only (`ScrambleTests`) — inner loop |
| `make test` | Full suite incl. UI tests — run before pushing |
| `make test-ui` | UI tests only (`ScrambleUITests`) |
| `make install` / `make run` | Build + install + launch on connected device |
| `make lint` / `make format` | swiftlint / swift-format (no-op if not installed) |
| `make clean` | Remove `./DerivedData` |

Overrides: `CONFIG=Release`, `SIMULATOR='iPhone 17'`, `DEVICE_MODEL='iPhone 16'`. Defaults are `iPhone 17 Pro` for both.

The Makefile pipes through `xcbeautify` if installed and uses repo-local `./DerivedData/` (gitignored) so install/run paths are predictable. Simulator tests run **serially** (`-parallel-testing-worker-count 1`) — parallel simulator clones race on launch and produce flakes; don't change this without good reason.

## Source of truth

Two design documents drive all implementation decisions. Read these before changing anything substantive:

- `docs/scramble-design-doc.md` — functional spec (data model, rules engine semantics, lifecycle, sharing model).
- `docs/scramble-ui-design-doc.md` — UI/UX spec (timeline navigation, packing sheet, theming, colour semantics, haptics, accessibility).

The React files in `docs/` (`direction-a.jsx`, `data.jsx`, `Scramble Directions.html`) are a **visual prototype only — not a port target**. Use them to understand intended look-and-feel; the Swift implementation must use a real `Theme` struct + SwiftUI environment, SwiftData, native transitions (`.matchedGeometryEffect`, `.transition`), and proper iOS chrome.

## Architecture essentials

These are the load-bearing decisions; getting them wrong will require reworking the data model.

### Rules engine is deterministic with diffing

The master lists (one for tasks, one for packing items per person) are the single source of reusability. On every relevant input change (trip attribute edit, master list edit, app launch, CloudKit sync), the engine recomputes the set of items that *should* exist and diffs against what's there:

- New matches → add automatically.
- No-longer-matching items → flag `currentlyMatchesRules = false` (visually dimmed, **not deleted**).
- User-pinned items → never removed or flagged.
- Already completed/packed items → never removed.

This determinism is what prevents drift across devices. Do not introduce non-deterministic shortcuts.

### Conditions storage must stay flexible

`MasterTaskItem.conditions` and `MasterPackingItem.conditions` should be stored as a flexible blob (JSON / Codable struct), **not rigid typed fields**. v1 evaluates simple AND/OR (OR within an attribute type, AND across attribute types) but the storage format must allow nested/grouped conditions later without a data migration.

### TripTask / TripPackingItem snapshot the name

Trip-level items hold `masterItemID: UUID?` (nil for one-offs) as a stable reference, but `name` is a **snapshot** copied at creation — not live-linked. Editing the master list does not retroactively rename items already on a trip.

### Explainability is computed on demand

Do not snapshot matched conditions at item creation. Compute on demand by intersecting the master item's current conditions with the trip's current attributes. Master conditions are stable references; trip attributes are the input.

### Trip-level edits do not modify the master list

Adding/removing/skipping items inside a trip is trip-specific. The master list has its own editing surface.

## UI architecture essentials

### No tabs inside a trip

Trip Detail is a single vertical timeline of seven phases. The only tab bar in the app is at the Trip List level (`Trips` / `Master Lists`).

### One-at-a-time accordion

Tapping a phase expands it and collapses any other expanded phase. Current phase auto-expands on launch. Phases with no content are non-expandable spine markers; packing phases (Departure, Day-before-return) are always expandable.

### Packing reached via bottom sheet, not navigation

Tapping a person row inside Departure/Day-before-return opens a `PackingSheet` over the timeline. The timeline is **not unmounted** — scroll position is preserved on dismiss.

### One SwiftUI view shared by Pack and Repack modes

`PackingSheet` is one component with a mode flag that determines group definitions, available actions, and counter text. Forking into divergent views is a deliberate non-goal.

### Liquid Glass is for floating chrome only

Use Liquid Glass on the Trip List bottom tab bar and the Packing Sheet header/handle. **Content cards do not use glass** — they use the `surface` colour as a near-solid tinted fill with a 1pt `surfaceBorder`. Glass-on-glass kills hierarchy.

### Theme architecture must support multiple themes from day one

v1 ships only Midnight Atlas, but `Theme` struct + SwiftUI environment injection must be in place so additional themes drop in without refactoring. Each theme defines a light and dark variant; user picks a theme, appearance follows iOS.

### Person colour is configurable, not hardcoded

Person colours come from a fixed per-theme palette (~8 colours), with defaults assigned on first creation but freely changeable. Avatars are circles with the person's initial in their colour — no emoji.

### Colour communicates context, not state

State (done / not done) is shown via fill vs outline, opacity, and strikethrough. Colour communicates *where you are* (phase colour in the timeline, person colour in the packing sheet). The pack-mode checkbox deliberately uses person colour when unchecked but check-green when checked — see "Checkbox colour rules" in the UI doc.

## Recommended implementation order

From the UI design doc — follow this sequence when starting:

1. Trip Detail scaffold + sticky header with attribute chips
2. `PhaseNode` component (circle + spine line + glow states)
3. Timeline composition with one-at-a-time accordion
4. Task row + checkbox + assignee avatar
5. `WhyDisclosure` (used by tasks AND packing items)
6. Packing summary block on Departure / Day-before-return phases
7. `PackingSheet` pack mode
8. `PackingSheet` repack mode (filter swap, read-only Left Behind group)
9. Rules engine: per-item matching condition exposure for explainability
10. Polish: transitions, haptics, VoiceOver, Dynamic Type

## Open questions

These remain undecided in the design docs — confirm with the user before implementing:

1. Sheet detents configuration (`.large` only, custom?).
2. Short-trip phase compression rule (collapse empty/zero-length phases to thin spine markers).
3. Notification deep-link behaviour (open trip with that phase auto-expanded).

## Out of scope for v1

Don't volunteer implementation for these unless asked: macOS app, copy-previous-trip, accommodation/activity attributes, user-configurable phases, App Store publishing, promote-to-master-list, linking Person to iCloud users, itinerary/activity planning, multi-leg trips. The v1 data model should avoid making multi-leg impossible but doesn't need to support it.
