# Design: Packing Item Sub-items

> **Implementation note (2026-06-24): UI reworked post-design.** The note/sub-item
> *interaction* below (the "＋ add item" reveal-on-tap row and editing the note
> through `PackingItemForm`) was superseded after on-device review by trailing
> **note (`note.text`) and list (`list.bullet`) glyphs** with **inline note
> editing** via `PackingItemGroup.saveNote`. See **Decision 14** in
> `decision_log.md` for what changed and why. The data model, sync/translator,
> migration, and `PackingSubItems` helper sections below are unchanged and
> remain accurate.

## Overview

Add an optional per-trip free-form note and an appendable sub-item list to `TripPackingItem`, displayed inline on the packing-sheet row and edited while packing. Two new Optional properties ride on `SchemaV3`; sync flows through the existing `TripPackingItemRecordTranslator`.

## Architecture

### What changes

| Layer | File | Change |
|---|---|---|
| Model | `Models/TripPackingItem.swift` | Add `note: String?`, `subItemsData: Data?`, and a `subItems: [String]` Codable bridge. |
| Domain | `Models/PackingSubItems.swift` (new) | Pure, testable validation/mutation helpers + caps. |
| Sync | `Sharing/Translators/TripPackingItemRecordTranslator.swift` | Encode/decode `note` + `subItemsData`, following the `countryCode` clear-propagation precedent. |
| UI (display+edit) | `Components/PackingSubItemsView.swift` (new) | Renders the note + sub-item list + inline quick-add/remove. |
| UI (host) | `Components/PackingItemRow.swift` | Embed `PackingSubItemsView`; thread add/remove closures + accessibility actions. |
| UI (mutations) | `Features/Trips/PackingSheet.swift` (`PackingItemGroup`) | `addSubItem` / `removeSubItem` methods that mutate and `save(_:)` through the existing `hook.commit` chokepoint. |
| UI (note edit) | `Features/Trips/PackingItemForm.swift` | Add a note field to the existing add/edit form. |
| Migration | `Persistence/Migrations/ZoneMigrationCoordinator.swift` | The `relocateTrip` clone (≈line 360) must copy `note` + `subItemsData` onto the relocated item. |

No new schema version. No changes to the rules engine, counts, groups, or `PackingListHelpers` (Req 7.3).

### Integration points

- **Display**: `PackingSubItemsView` mounts inside `PackingItemRow`'s existing name/disclosure `VStack`, below the name and above the `WhyDisclosureView`. It renders in every group (Req 5.1); the `SheetGroup.isReadOnly` flag (defined on the `SheetGroup` enum in `PackingItemRow.swift`) gates the add/remove affordances (Req 5.2). `PackingItemRow.body` MUST read `item.note` and `item.subItems` directly (not only inside the child) so SwiftData establishes observation on `note`/`subItemsData` — that is what makes an inbound sync re-render the row. `PackingSubItemsView` itself is purely presentational (plain-value params, no `@Model` reference); its only refresh trigger is the parent re-rendering.
- **Sub-item writes** funnel through `PackingItemGroup.save(_:)` — the same `hook.commit(modelContext)` path the checkbox/skip mutations already use. No new `tripsLocal` save site.
- **Note writes** funnel through `PackingItemForm.performAdd/performEdit`, which already commit via `hook.commit` with rollback-on-failure.
- **Sync**: only the two translator methods change; `LocalWriteHook` already marks the item dirty on any field change, so no dirty-marking changes.

### Pattern parity audit

`TripPackingItem` field handling appears in exactly these places; each new field must be handled in the same set:

| Site | Needs note + subItems? | Notes |
|---|---|---|
| `TripPackingItem.init` | yes | New optional params, defaulting nil. |
| `TripPackingItemRecordTranslator.toRecord` | yes | Encode both; blob-cap check on `subItemsData`. |
| `TripPackingItemRecordTranslator.from` | yes | Unconditional assignment (clear-propagation). |
| `PackingItemForm.performAdd` | note only | New items can carry a note; sub-items start empty. |
| Rules engine `Apply.insertAddedPacking` (≈line 71) | no | Fresh-create from a newly-matched master — no prior per-trip item to carry fields from. |
| Rules engine `Apply.flagPacking` (≈line 134) | no | Mutates `currentlyMatchesRules` only on existing instances; never recreates (verified). |
| `PackingListHelpers` (counts/sort, PR #10) | no | Pure read/query helper; never constructs an item (Req 7.3). |
| `SchemaV3MigrationStage` | no | Mutates `personSnapshotID` in place; never recreates. |
| **`ZoneMigrationCoordinator.relocateTrip` (≈line 360)** | **yes — clone** | Builds a new `TripPackingItem` from an existing one (copies id/name/state/source/flags/`personSnapshot`/`ckRecordSystemFields`). MUST also copy `note` + `subItemsData`, or the V2→V3 zone relocation silently drops them. |
| `MasterPersistence.copyPacking` (PR #9) | no | Constructs `MasterPackingItem`, not `TripPackingItem`. |
| `SnapshotMaintenance` / `TripDeletion` | no | Fields live on the item; deletion cascades with the item (Req 7.4). |

## Data Models

Two Optional stored properties on the existing shared `TripPackingItem` (MUST be Optional with `nil` default so they ride on `SchemaV3` via lightweight inference — a property-only addition to a shared top-level class cannot be a new `SchemaV4`; see `persistence.md` "Shared top-level classes can't express property-only schema bumps").

```swift
// stored
var note: String?            // nil or empty ⇒ no note
var subItemsData: Data?      // nil/empty ⇒ no sub-items; JSON-encoded [String] otherwise

// bridge (extension, never a stored relationship)
var subItems: [String] {
  get {
    guard let data = subItemsData, !data.isEmpty else { return [] }   // empty Data() ⇒ []
    return CodableBridge.decode(data, as: [String].self, default: [], label: "TripPackingItem.subItems")
  }
  set { subItemsData = newValue.isEmpty ? nil : CodableBridge.encode(newValue, label: "TripPackingItem.subItems") }
}
```

**Invariant**: empty list ⇒ no sub-items, treated identically whether `subItemsData` is `nil` or a non-nil empty `Data()`. The getter normalises empty `Data()` to `[]` because `CodableBridge.encode` returns empty `Data()` (never nil) on its degrade path — so the "empty ⇒ nil" setter guarantee is reinforced on read. The translator's clear check (below) tests `data.isEmpty`, not just nil, for the same reason. Order is array order (Req 1.3).

Why a `Data?` blob rather than a native `[String]` SwiftData/CKRecord list: it adopts the `CodableBridge` blob pattern used on `Trip.attributesData` / `MasterPackingItem.conditionsData` and the `kRecordBlobSizeCap` guard from `TripRecordTranslator`. Note this is the **first** Codable blob on `TripPackingItem` and its translator — the pattern is imported here, not pre-existing on this model — so the cap check is net-new code, not a reused call.

## Components and Interfaces

### `PackingSubItems` (pure helpers)

All validation/mutation logic lives here so it is unit-testable without a view or a `ModelContext`.

```swift
enum PackingSubItems {
  static let maxCount = 50            // Req 2.7
  static let maxItemLength = 200      // Req 2.4 (grapheme clusters)
  static let maxNoteLength = 500      // Req 4.4 (grapheme clusters)

  enum AddOutcome: Equatable { case added([String]), rejectedEmpty, rejectedFull }

  static func sanitizedEntry(_ raw: String) -> String          // trim, cap to maxItemLength graphemes
  static func appending(_ raw: String, to list: [String]) -> AddOutcome
  static func removing(at index: Int, from list: [String]) -> [String]   // bounds-checked no-op if OOR
  static func sanitizedNote(_ raw: String) -> String?          // trim, cap maxNoteLength; nil if empty
}
```

- `appending`: trims+caps; `rejectedEmpty` if blank; `rejectedFull` if already at `maxCount`; otherwise `added(list + [entry])`. Duplicates are kept (Req 2.6) — no de-dup.
- `removing`: by **index**, not value, because duplicates are allowed and removal must target a position.

### `PackingSubItemsView` (new)

```swift
struct PackingSubItemsView: View {
  let note: String?
  let subItems: [String]
  let isInteractive: Bool          // == !SheetGroup.isReadOnly
  let accent: Color                // person colour
  let onAdd: (String) -> Void      // → PackingItemGroup.addSubItem
  let onRemove: (Int) -> Void      // → PackingItemGroup.removeSubItem (by list index)
  let onEditNote: () -> Void       // opens PackingItemForm in edit mode
}
```

Renders, top to bottom: the note, the sub-item rows, then — `isInteractive` only — a compact add affordance. Empty + non-interactive ⇒ renders nothing (Req 5.3: row unchanged).

**List identity (resolves the `ForEach`-over-`[String]` hazard).** A flat `[String]` with duplicates (Req 2.6) has no natural stable id, and `id: \.self` would collapse/mis-target duplicate rows. The view holds a row-local mirror `@State private var drafts: [SubItemDraft]` where `struct SubItemDraft: Identifiable { let id = UUID(); let text: String }`, seeded from `subItems` and re-seeded on `.onChange(of: subItems)` (e.g. an inbound sync). `ForEach` iterates `drafts` by `id`; a remove maps the draft's current position → index and calls `onRemove(index)`. The stored model stays `[String]` — no persisted ids, no schema impact. There is no inline rename, so re-seeding on sync never discards an in-progress edit of an existing entry.

**Density (open point 1).** The add affordance is a compact "＋ add item" control, not a persistent field. Tapping it reveals an inline `TextField` bound to a row-local `@FocusState`; it appends on submit and stays open for rapid multi-add. The 200-grapheme cap is enforced live via `.onChange` (mirrors `PackingItemForm.cappedName`). Hidden when `subItems.count == maxCount` (Req 2.7). Empty rows show only the light "＋ add item" control. Visual: person-colour accent referencing the sheet-level `DashedAddButton` (a styling cue, not a component being extended). Each sub-item row's remove control matches the existing inline `Skip`/`Restore` button styling and is ≥44×44 (Req 8.3).

**Focus / keyboard / dismissal.** On reveal, the row scrolls above the keyboard via the sheet's existing `ScrollViewReader` proxy (`proxy.scrollTo(row, anchor:)`). Opening the add field first closes any open `WhyDisclosure` for that row — one inline expansion at a time. Outside-tap dismissal: the sheet's existing background tap-catcher (today gated on `openDisclosureItemID != nil`) is widened to also clear the active add-field focus. Empty submit or blur dismisses the field.

**Note display + edit (resolves open point 2 / the discoverability concern).** The note renders as secondary text, visually distinct from the list. When present and the row is interactive, the note text is tappable and calls `onEditNote` (opens `PackingItemForm`, which now carries the Note field). When absent, there is **no** dedicated inline "add note" control — a second per-row affordance would worsen the density this design protects; notes are reached via the row's existing Edit affordance, whose form now shows a labelled Note field, making the path self-revealing once Edit is opened for any reason. On read-only rows the note displays but is not tappable (no edit), consistent with sub-items.

**Accessibility tree.** `PackingItemRow` currently uses `.accessibilityElement(children: .combine)`, which flattens the row into one element — incompatible with per-sub-item addressable elements (Req 8.2). Restructure: the name + state + checkbox stay one combined "row" element carrying the row-level **Add sub-item** custom action (Req 8.2) and the note in its label (Req 8.1); the sub-item list becomes a sibling container (`.accessibilityElement(children: .contain)`) whose entries are individually focusable, each exposing a **Remove** action. Dynamic Type: each sub-item wraps (no truncation, per `accessibility.md`'s row convention); the row's `minHeight: 44` and top-aligned checkbox hold as the VStack grows. A 50-entry row at AX sizes is an accepted rare worst case (Decision 8 bounds it).

### `PackingItemGroup` mutations (in `PackingSheet.swift`)

```swift
private func addSubItem(_ item: TripPackingItem, _ raw: String) {
  switch PackingSubItems.appending(raw, to: item.subItems) {
  case .added(let list): item.subItems = list; save("addSubItem")
  case .rejectedEmpty, .rejectedFull: return       // pre-save guard; no write
  }
}
private func removeSubItem(_ item: TripPackingItem, at index: Int) {
  item.subItems = PackingSubItems.removing(at: index, from: item.subItems)
  save("removeSubItem")
}
```

Mirrors the existing `toggleState`/`skipOrRestore` shape. `save(_:)` keeps the existing log-and-swallow behaviour for transient commit failures (Decision 9: validation is pre-save; only the cap/empty guards reject, and they reject *before* any write).

### `PackingItemForm` note field

Add an optional note `TextField(axis: .vertical)` below the name field, capped via `PackingSubItems.sanitizedNote` semantics (live cap to 500 graphemes). `performAdd`/`performEdit` set `item.note = PackingSubItems.sanitizedNote(note)`. Clearing the field to empty sets `nil` (Req 4.3). Shown in both add and edit modes.

### Translator changes

```swift
// toRecord
record["note"] = item.note as CKRecordValue?          // nil clears (masterItemID precedent)
if let data = item.subItemsData, !data.isEmpty {      // empty Data() also clears
  guard data.count <= kRecordBlobSizeCap else {
    throw TranslatorError.blobTooLarge(field: "subItemsData", size: data.count)
  }
  record["subItemsData"] = data as CKRecordValue
} else {
  record["subItemsData"] = nil                        // clear
}

// from  — unconditional, so a clear on the wire reaches this device (Req 6.5)
// Contract: requires a FULL server snapshot. Never pass a partial /
// desiredKeys record here — an absent data field is read as "cleared",
// so a partial record would wipe local note/subItems. CKSyncEngine's
// fetch path delivers full records; this holds today (verified) and the
// `from` doc comment must state it so no future desiredKeys path regresses it.
item.note = record["note"] as? String
item.subItemsData = record["subItemsData"] as? Data
```

**Convention note**: this is a *deliberate divergence* from the sibling fields in the same translator. `personSnapshotID` and `tripID` use conservative `if let` ("absent = no change, can't distinguish omitted from cleared"); the new fields instead use **unconditional** assignment so a clear propagates (Req 6.5). The in-file precedent for unconditional/nil-clears is `masterItemID` (already decoded this way); `countryCode` in `TripRecordTranslator` is the cross-file precedent. The rationale for choosing clear-propagation over the conservative model: full-snapshot `CKSyncEngine` delivery means absent genuinely == cleared, and a user deleting a note expects it gone everywhere. Trade-off: an older client that omits these fields would clear them on its writes — acceptable (single-developer app, devices update together; same trade-off Phase 6 took for `countryCode`). The count + length caps keep `subItemsData` far under `kRecordBlobSizeCap`, so `blobTooLarge` is effectively unreachable but retained as defence.

## Error Handling

| Condition | Handling | Req |
|---|---|---|
| Empty / whitespace sub-item submitted | `appending` returns `rejectedEmpty`; no write, field stays open | 2.3 |
| 51st sub-item | add control hidden at 50; `appending` returns `rejectedFull` as a backstop | 2.7 |
| Over-length entry/note | capped live at input (`.onChange`); no explicit user feedback, matching the existing silent `cappedName` name-field behaviour | 2.4, 4.4, 6.4 |
| Transient `hook.commit` failure (sub-item) | logged, swallowed; SwiftData re-emits prior state on next body eval (existing packing-sheet pattern) | — |
| Transient save failure (note, via form) | form rollback + inline error (existing `PackingItemForm` pattern) | — |
| `subItemsData` exceeds 256 KB | `blobTooLarge` thrown at encode (unreachable given caps) | 6.4 |

## Concurrency and resolved open points

- **Edit-during-sync race**: the inline add field holds its in-progress text in row-local `@State`, independent of the `@Model` until submit. If a remote sync re-emits the item mid-typing, the visible `subItems` list re-renders but the unsaved field text is untouched; on submit the entry is appended to the *current* list. Resolution: incoming sync never discards typed-but-unsubmitted text, and the last submitted entry wins. No locking, no merge.
- **Whole-record LWW (not just whole-list)**: `TripSyncEngine` has no field-level dirty tracking — every save rebuilds the entire `CKRecord` via `toRecord` and pushes it (verified in `TripSyncEngine.swift`). So `note`, `subItemsData`, and every other field on `TripPackingItem` share **one** LWW conflict domain (the record). A note-only edit re-sends a then-current `subItemsData`; if a concurrent remote sub-item add hasn't been fetched yet, that add is overwritten. This is the accepted Decision 6 trade-off, now stated at record granularity.
- **Rapid multi-add framing (corrected)**: each submit issues one whole-record push. For a *single* writer this narrows each individual conflict window; for *concurrent* writers on the same item it multiplies overwrite events during the shared typing window. Per-entry save is kept for durability (an entry survives an app kill), not sold as a conflict mitigation. Batching on field-dismiss was considered and rejected (loses entries on kill).
- **CKShare permissions**: confirmed out of scope — v1 has no read-only participant tier. "Interactive" means `SheetGroup.isReadOnly`, never share permission, so no participant-permission mapping is needed.
- **CloudKit schema promotion**: the two new record fields appear automatically in the Development environment but must be promoted to Production before release — handled by the existing release-prep CloudKit-schema-promotion checklist (CLAUDE.md / Phase 5 release prep). Flagged here so the fields ship deployed.

## Testing Strategy

**Model bridge (`ScrambleTests`, Swift Testing, `@MainActor`)**
- `subItems` get/set round-trip; `subItems = []` ⇒ `subItemsData == nil`; a non-nil empty `Data()` reads back as `[]` (the `CodableBridge.encode` degrade edge); garbage `Data` decodes to `[]`; `note` set/clear.

**Pure helpers (`PackingSubItemsTests`)**
- `sanitizedEntry` trims and caps at 200 grapheme clusters (multi-scalar emoji survive intact at the boundary).
- `appending`: rejects empty; rejects at 50; appends otherwise; preserves duplicates and order.
- `removing`: removes only the indexed entry, preserves order, OOR index is a no-op.
- `sanitizedNote`: trims, caps 500 graphemes, nil on empty.

**Translator (`TripPackingItemRecordTranslatorTests`)** — extend existing suite
- Round-trip: note + sub-items survive `toRecord → from` without loss or reorder (Req 6.2).
- Clear matrix (gap #1): for note and sub-items, each of {nil, empty, non-empty} → encode → decode reproduces the cleared/empty/populated state; a populated→cleared sequence yields `nil`/`[]` on the receiver (Req 6.5). Include the non-nil empty `Data()` case (must serialise as an absent field, not a present empty blob).
- `blobTooLarge` thrown when `subItemsData` is forced over the cap.

**Lifecycle (`ScrambleTests`)**
- Skip→restore: toggling `state` to `.excluded` and back leaves `note`/`subItems` unchanged (Req 7.5).
- Zone relocation: `ZoneMigrationCoordinator.relocateTrip` carries `note`/`subItemsData` onto the relocated item, and an item with both `nil` relocates as still-`nil` (not an empty blob) — regression guard for the clone site found in the parity audit.
- Migration materialization: opening a store seeded at pre-feature `SchemaV3` shape surfaces the two new columns as `nil` (lightweight inference), confirming no `SchemaV4` and no duplicate-checksum crash.

**Property-based (parameterised, matching the repo's existing `@Test(arguments:)` PBT style)**
- Round-trip identity: for generated `[String]` (incl. duplicates, empty, unicode, boundary-length entries within caps), `decode(encode(xs)) == xs`. Justified: the bridge is a serializer with a universal round-trip guarantee.
- `appending` invariants over a generated sequence of adds/removes: count never exceeds 50; a successful add increases length by exactly 1; `removing` decreases by exactly 1.

**UI test (`ScrambleUITests`)** — one path
- In pack mode: reveal inline add, type a sub-item, submit, assert it renders on the row; remove it; switch the item to Not bringing and assert the sub-item shows but no add/remove control appears.

**Accessibility**
- Each sub-item is its own accessibility element labelled "sub-item: {text}"; interactive rows expose per-element "Remove" actions and a row-level "Add sub-item" custom action (Req 8.1, 8.2).
