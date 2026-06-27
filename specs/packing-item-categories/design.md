# Design: Packing Item Categories

## Overview

Add an optional `category: String?` to `MasterPackingItem` and `TripPackingItem`, group the Packing Sheet and Master Lists by category, and offer previously-used category names as autocomplete suggestions. Category is a managed projection: stored on each item, re-applied onto master-derived trip items by the deterministic rules engine, and synced like other trip-item fields.

## Architecture

### Data model

Both models gain one stored property, optional with a `nil` default, riding on `SchemaV3` via lightweight inference — exactly the precedent set by `TripPackingItem.note` (no `SchemaV4`; see `docs/agent-notes/persistence.md`). No `VersionedSchema.models` change is needed (the classes are already registered).

```swift
// MasterPackingItem.swift — source of truth, globals container (CloudKit-mirrored)
var category: String?            // + init param, default nil

// TripPackingItem.swift — managed projection, tripsLocal container
var category: String?            // + init param, default nil (mirrors `note`)
```

Stored form is always trimmed and internal-whitespace-collapsed, case preserved (Req 1.2, 1.3). The case-folded *normalized key* used for grouping/suggestions/sort is computed on demand, never stored.

### Category re-stamping rides the existing deterministic engine (invariant narrowing)

Decision 2/6 calls for re-applying a master's category onto existing derived trip items, owner-only and compare-before-write. Rather than a separate subsystem, this extends the existing pure `compute` → `apply` pipeline, which already runs owner-gated at all 8 engine triggers and commits through `LocalWriteHook` so `TripSyncEngine` propagates the change.

This **narrows** the engine invariant "never rewrites existing trip items": the engine may rewrite the `category` projection field (and only that) on existing items. It still never rewrites `name` or any identity/state field. The re-stamp is computed as a diff and emitted in the `Plan`, keeping the engine deterministic and pure.

Reconciliation runs wherever the engine runs and inherits each trigger's scope. The master-category-edit trigger uses `runForAllNonPastTrips`, so editing a master re-stamps derived items on **active (non-past) trips** (Req 3.2). The `runForTrip` triggers (launch, foreground, trip open, remote sync of an owned zone) have no past-trip cutoff, so a past trip can still be re-stamped when it is individually opened or receives a remote change — this is harmless (it only keeps the category current). There is therefore no guaranteed "freeze" for past trips; freeze applies only to the master-deleted case (Req 3.6), which holds regardless of trigger because no master is found to re-stamp from.

Why this is owner-only without a new gate: `compute`/`apply` run behind `RulesEngineRunner.isOwned`, and a participant's `globals` store does not contain the trip owner's `MasterPackingItem`, so even if reached, no master would match and nothing would be re-stamped. A participant who edits a master-derived category writes a trip-item record that syncs to the owner; the orchestrator re-runs `runForTrip` on that remote change and re-stamps it back to the master value (self-correcting; the UI read-only gate below removes the transient flicker).

### Pattern-extension touch-point audit

The master→trip snapshot/`name` pattern and the record translator are extended to carry `category`. Every call site:

| Site | File | Change | Needs equivalent? |
|---|---|---|---|
| Master model field | `Models/MasterPackingItem.swift` | add `category` + init param | yes |
| Trip model field | `Models/TripPackingItem.swift` | add `category` + init param | yes |
| Master snapshot | `RulesEngine/Snapshots.swift` `MasterPackingSnapshot` | add `category` | yes |
| Snapshot capture | `RulesEngineRunner.fetchMasterPackingSnapshots` | capture `master.category` | yes |
| Trip item ref | `RulesEngine/Snapshots.swift` `TripPackingItemRef` | add `category` (for diff) | yes |
| Ref capture | `RulesEngineRunner` `TripSnapshot.capture` | capture `item.category` | yes |
| Add path | `RulesEngine/Apply.swift` `insertAddedPacking` | stamp `category: master.category` at creation (Req 3.1) | yes |
| Plan | `RulesEngine/Plan.swift` | add `toRestampCategory`, include in `isEmpty` | yes |
| Compute | `RulesEngine/Compute.swift` | emit re-stamp diffs (compare-before-write) | yes |
| Apply | `RulesEngine/Apply.swift` | write re-stamps before `hook.commit` | yes |
| Sync write/read | `Sharing/Translators/TripPackingItemRecordTranslator.swift` | guarded read + write (Req 7.2/7.3) | yes |
| Master create/edit/copy | `Features/MasterLists/MasterPersistence.swift` | carry `category` through `createPacking`/`applyPacking`/`copyPacking` | yes — all 3 |
| Master draft | `Features/MasterLists/MasterPackingDraft.swift` | add `category`; set in `newDraft` + `init(from:)` | yes |
| Master editor | `Features/MasterLists/MasterPackingEditor.swift` | category Section + suggestions | yes |
| Manual add/edit | `Features/Trips/PackingItemForm.swift` | category field + suggestions; read-only gate; **inject `\.globalsContainer` (for cross-container suggestions) and `\.isParticipantViewingSharedTrip` (re-inject at the sheet presentation site — a `.sheet` does not inherit custom env keys)** | yes |
| Packing sheet display | `Features/Trips/PackingSheet.swift` `PackingItemGroup` | category sub-grouping | yes |
| Master list display | `Features/MasterLists/MasterPackingList.swift` | category sub-grouping within person | yes |
| Grouping/sort helper | `Timeline/PackingListHelpers.swift` + new `Models/PackingCategory.swift` | normalization + grouping | yes |
| CloudKit schema promotion | `docs/release-prep.md` + CloudKit Dashboard | promote `MasterPackingItem.category` (auto-mirrored — easy to miss, no hand-written code) **and** `TripPackingItem.category` to Production; update the checklist | yes — **release ship gate** |

`Compute` matching logic does **not** change — category is not a rules condition (Non-Goal). The same-name dedup key in `copyPacking` stays name-only; category does not participate.

## Components and Interfaces

### `PackingCategory` (new, `Models/PackingCategory.swift`)

Pure value logic, no SwiftData. Single home for the normalization/sort rules so every surface agrees.

```swift
nonisolated enum PackingCategory {
  /// Trimmed + internal-whitespace-collapsed, case preserved; nil if empty. The stored form. (Req 1.2/1.3)
  static func storageValue(_ raw: String?) -> String?
  /// Case-folded form of storageValue; the grouping/suggestion-match key. nil ⇒ uncategorised. (Req 1.5)
  static func normalizedKey(_ raw: String?) -> String?
  /// Orders two normalized keys for deterministic cross-device section order. (Req 5.2)
  static func keyOrder(_ lhs: String?, _ rhs: String?) -> Bool   // nil sorts last
  /// Among storageValues sharing a normalized key, the deterministic display label. (Req 5.6)
  /// Uses `rawOrder` (NOT keyOrder) — keyOrder case-folds, so all variants tie under it
  /// and it cannot disambiguate spelling. The same rule picks the stored spelling for a
  /// deduped suggestion (Req 2.4).
  static func displayLabel(_ variants: [String]) -> String
  /// Total order over RAW (non-case-folded) storageValues; the disambiguator behind displayLabel.
  static func rawOrder(_ lhs: String, _ rhs: String) -> Bool
}
```

Normalization detail: `storageValue` trims and collapses runs of whitespace, case preserved; `normalizedKey` additionally applies non-localized `lowercased()` (NOT `localizedLowercase` — that is locale-sensitive, e.g. Turkish dotless-i, and would break cross-device determinism). Diacritics are **not** folded ("Café" ≠ "Cafe") — accepted for v1 (Decision 5). Both `keyOrder` and `rawOrder` compare by Unicode-scalar lexicographic order (a fixed, locale-independent total order), so a shared trip orders identically on every device regardless of locale.

### Re-stamp pipeline (engine)

```swift
// Plan.swift — payload MUST carry the value, including nil for a clear.
struct PackingCategoryRestamp: Equatable, Sendable { let id: UUID; let category: String? }
// Plan gains: let toRestampCategory: [PackingCategoryRestamp]   // sorted by id; included in isEmpty
```

`compute` branches on master **presence**, not value:

- master **absent** from `packingMap` (deleted, or manual one-off `masterItemID == nil`) → emit nothing → freeze (Req 3.6, Req 4.3).
- master **present** and `master.category != ref.category` (exact-string compare-before-write, including the present-with-`nil` case) → emit `PackingCategoryRestamp(id: ref.id, category: master.category)`. A present master with `nil` category therefore re-stamps a non-nil trip item to `nil` (clear); equal values emit nothing.

`apply` fetches each id and assigns `item.category` (re-checking inequality for idempotency). Compare-before-write keeps reconciliation a no-op when nothing changed, bounding writes; a one-line breadcrumb log of re-stamp decisions (applied/skipped + value) aids convergence debugging under eventual consistency.

### Grouped display

A generic grouping helper produces ordered sections; both surfaces render sub-headers from it.

```swift
struct CategorySection<Item> { let label: String?; let key: String?; let items: [Item] }
// in PackingListHelpers (or PackingCategory): groups by normalizedKey, orders via keyOrder
// (uncategorised last), sorts within each group with the supplied comparator, and resolves
// the deterministic label.
static func categorySections<Item>(
  _ items: [Item], category: (Item) -> String?, sortWithin: ([Item]) -> [Item]
) -> [CategorySection<Item>]
```

- **Packing Sheet** (`PackingItemGroup.body`): replace `sorted(personItems.filter(group.matches))` with `categorySections(filtered, category: \.category, sortWithin: PackingListHelpers.sorted)`. Render the existing state header, then: if the result is a single uncategorised section, render its rows flat with no sub-header (Req 5.5); otherwise render each section's sub-header + rows. Applies to all `groups` in both modes, including read-only repack sections (Req 5.4). One pass over `personItems` per `PackingItemGroup` preserves the performance budget (Req 5.7).
- **Master Lists** (`MasterPackingList`): inside each existing per-person `Section`, replace the flat `ForEach(items)` with `categorySections(items, category: \.category, sortWithin: byName)`; same flat-when-none rule (Req 6.2).

Category sub-headers reuse the existing `PackingItemGroup` header `Text` style (`PackingSheet.swift:269`) and add `.accessibilityAddTraits(.isHeader)` (Req 5.8). No `.isHeader` exists in the codebase today; this is a small, scoped new convention applied only to the new sub-headers.

### Suggestions (autocomplete)

No `.searchable`/`searchSuggestions`/combo-box pattern exists; this is net-new. Suggestions are the distinct categories present on the device, from **both** containers — `MasterPackingItem` (globals) and `TripPackingItem` (tripsLocal) — deduped by normalized key and ordered via `keyOrder` (Req 2.2, 2.5). A single `@Query` cannot span containers, so each surface reads its own context plus the sibling container's `.mainContext` (established pattern: `MasterPackingEditor` already holds both `modelContext` and `\.tripsLocalContainer`).

```swift
// helper, given both contexts available to the surface:
static func distinctCategories(globals: ModelContext, tripsLocal: ModelContext) -> [String]
```

`distinctCategories` dedupes by normalized key, picking each key's canonical spelling via `PackingCategory.displayLabel` (so `Req 2.4`'s stored spelling matches the section header), and is computed **once when the editor opens** (or memoized) — never per keystroke — and always from current item categories, so a cleared category does not resurrect as a suggestion (Non-Goal: no persistent vocabulary).

UI: a `TextField` bound to the draft category plus a tappable suggestion list (e.g. a `Menu` of existing names, or chips below the field) that, when chosen, stores that canonical spelling (Req 2.4). A participant device, lacking the owner's masters, naturally yields a smaller set (Req 2.5).

### Read-only rule for participants (Req 3.5)

The category control in `PackingItemForm` reads `@Environment(\.isParticipantViewingSharedTrip)`. This key is set in `TripDetailView` and currently consumed by `TaskRow` (not `PackingItemRow` — the env-key file's doc comment listing other consumers is stale). Because a `.sheet` does not inherit a custom environment key from its presenter, the value must be **re-injected** where `PackingItemForm` is presented (from `PackingSheet`). When `true` **and** the edited item is master-derived (`item.masterItemID != nil`), the category field renders read-only (shown, not editable). One-off items (`masterItemID == nil`) remain editable by whoever can edit the trip item (Req 4.1). The engine `isOwned` gate is the real enforcement (a participant write syncs to the owner, whose remote-change `runForTrip` re-stamps it back); this UI gate removes the confusing transient where a participant edit is visibly reverted.

### Sync translator (`TripPackingItemRecordTranslator`)

Use the **unconditional** decode (the `note`/`countryCode` precedent), not the guarded `personSnapshotID` pattern:

```swift
// toRecord:
record["category"] = item.category as CKRecordValue?
// from:
item.category = record["category"] as? String
```

A clear-to-`nil` encodes as an *absent* CKRecord field; guarded decode could not represent a clear at all, so it would silently drop category clears — fatal for manual one-off items, which are never reconciled (Req 4.3) and have no re-stamp backstop. Unconditional decode propagates clears for both item kinds and matches the field two lines above it (`note`). It carries the same accepted mixed-fleet wipe risk as `note`/`subItems`/`countryCode` (see Error Handling).

## Data Models

Only the two `category: String?` additions above. No new entities (Non-Goal: no category entity).

## Error Handling

- **Inbound record without `category`** (older app version, or pre-feature record): unconditional decode reads the absent field as `nil` ⇒ uncategorised, no error (Req 7.3).
- **Mixed-fleet wipe (accepted):** because decode is unconditional, a device on an older build that writes a `TripPackingItem` record omits `category`, and a newer device reading it will set the local value to `nil`. This is the same accepted v1 posture as `note`/`subItems`/`countryCode`. For master-derived items it self-heals — the owner's next rules-engine run re-stamps from the master and re-syncs. Manual one-off items have no backstop, so a wipe during the rollout window is permanent for them; acceptable for a personal/family fleet that updates together.
- **Master deleted:** `compute` finds no master in `packingMap`, emits no re-stamp; the derived item keeps its last category (Req 3.6, freeze).
- **Multi-device recency (Req 3.7, eventual consistency):** no version guard in v1 (deliberate — Decision 9). Owner devices re-stamp from their own master, which converges via the globals CloudKit mirror; compare-before-write quiesces once converged. While the globals and trip-sync pipelines are mid-convergence, a device with a stale master can transiently re-stamp an older value; same-device echo is suppressed by the orchestrator, and the value self-heals once the master syncs. The breadcrumb log of re-stamp decisions is the observability for distinguishing "still converging" from "stuck".
- **Fresh upgrade:** post-update every item's `category` is `nil` on both models, so the first rules-engine run computes equal values everywhere and emits no re-stamps — no first-launch write storm.

## Testing Strategy

Example-based (Swift Testing, `@Test`):
- **Model/migration**: an existing store opens with `category == nil` on all items; new optional rides `SchemaV3` (no `SchemaV4`).
- **Compute** (`ComputeTests`): master-derived item with differing category emits one re-stamp; equal category emits none (compare-before-write); manual item (`masterItemID == nil`) never re-stamped; deleted master (absent from map) emits none.
- **Apply** (`ApplyTests`): re-stamp writes `category` and touches no other field (Req 3.3); empty `toRestampCategory` ⇒ no write.
- **Add path**: `insertAddedPacking` stamps `master.category` (Req 3.1).
- **Translator round-trip**: `category` survives `toRecord`→`from`; absent inbound key preserves local value (guarded read); nil category round-trips.
- **Grouping/sort**: variants differing only in case/whitespace land in one section with a deterministic label; uncategorised sorts last; single-uncategorised input ⇒ flat (no sub-header); within-section order matches existing `sorted`.
- **Suggestions**: distinct categories merge across both containers and dedupe by normalized key.
- **Persistence**: `createPacking`/`applyPacking`/`copyPacking` carry category through (copy path included).

Property-based candidates (universal guarantees; use `swift-testing` parameterized inputs over generated strings):
- **Normalization idempotence**: `storageValue(storageValue(x)) == storageValue(x)`; `normalizedKey` stable under re-application.
- **Grouping partition invariant**: every input item appears in exactly one section; section count == distinct normalized keys; ordering is a total order (deterministic regardless of input order).
- **Re-stamp idempotence**: running `compute`+`apply` twice with an unchanged master yields no writes on the second pass.
