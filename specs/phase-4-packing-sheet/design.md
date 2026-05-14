# Design: Phase 4 — Packing Sheet

## Overview

Adds the per-person packing summary block on the Departure and Day-before-return phases, the `PackingSheet` bottom sheet with two modes, and the person-coloured variant of `WhyDisclosure`. No schema change. Touches `WhyResolver`, `AccordionTimeline`, and `PhaseRow` minimally; all new UI lives in new files.

## Architecture

### State ownership

Top-level packing-sheet state lives in `TripDetailView`:

```swift
@State private var packingSheetState: PackingSheetState?

struct PackingSheetState: Identifiable {
  let person: Person
  let mode: PackingMode
  var id: UUID { person.id }
}
```

`PackingSheetState?` is bound to `.sheet(item:)` on `TripDetailView`. The sheet's body reads `trip` from a captured reference and `person`/`mode` from the state. The sheet owns its inner state — disclosure ID, manual-item form presentation, scroll position — none of which leak back to `TripDetailView`. Dismissal clears `packingSheetState` and SwiftUI restores focus to the summary row that originated it (Req [9.7](requirements.md#9.7)) via `AccessibilityFocusState` (see §"VoiceOver focus" below).

### Integration with AccordionTimeline

`AccordionTimeline` gains one new callback and one branching content site:

```swift
struct AccordionTimeline: View {
  // existing parameters …
  let onOpenPackingSheet: (Person, PackingMode) -> Void
}
```

Inside `row(for:variant:proxy:)`, the content `@ViewBuilder` branches on `phase`:

- `departureDay` → `TaskListSection` then `PackingSummarySection(mode: .pack)` as siblings inside the existing content slot
- `dayBeforeReturn` → `TaskListSection` then `PackingSummarySection(mode: .repack)` as siblings
- all other phases → `TaskListSection` only (unchanged)

The two sections are HStack siblings with the existing 12pt vertical rhythm; the packing summary block sits beneath the tasks list. The composition is inlined into `AccordionTimeline.row(for:variant:proxy:)` rather than extracted into a `PackingPhaseContent` wrapper — there is no shared logic worth abstracting, and the branching site already exists.

### Subline composition (Req [1.10](requirements.md#1.10))

`PhaseRow` gains an optional `packingSubline: String?` parameter. When non-nil, the row's existing `sublineText` is composed as:

```text
{tasks clause} · {packing clause}     // when both present
{packing clause}                       // when no tasks
{tasks clause}                         // when not a packing phase (unchanged)
```

`AccordionTimeline` computes the packing clause via `PackingListHelpers.phaseSubline(trip:mode:)` and passes it only for `departureDay`/`dayBeforeReturn`. Wrapping behaviour from Phase 3 Req 5.4 is preserved by `fixedSize(horizontal: false, vertical: true)` (already on the subline).

### Integration with WhyDisclosure

`WhyDisclosureView` adds a `Style` enum to handle the task vs packing visual treatment without forking the view:

```swift
enum WhyDisclosure {
  enum Style: Sendable {
    case tasks(phaseColour: Color)
    case packing(personColour: Color)
  }
  // existing Reason enum unchanged
}

struct WhyDisclosureView: View {
  let reason: WhyDisclosure.Reason
  let style: WhyDisclosure.Style
}
```

Internally, `Style` resolves to `(tint: Color, backgroundOpacity: Double, borderOpacity: Double?)`:

| Case | tint | background | border |
|---|---|---|---|
| `.tasks` | phase colour | 0.08 | 0.20 |
| `.packing` | person colour | 0.06 | `nil` (no border) |

All call sites of `WhyDisclosureView(reason:, phaseColour:)` are migrated to the new initializer (only `TaskRow`). The Phase 3 string strings in `Reason` are reused verbatim per Phase 4 Req [7.4](requirements.md#7.4) – [7.7](requirements.md#7.7) — no new `Reason` cases.

### Integration with WhyResolver

`WhyResolver` gains a second static function `@MainActor static func reason(for: TripPackingItem, context: ModelContext) -> WhyDisclosure.Reason` with the same four-case mapping:

| `item.source` | `masterItemID` lookup (`MasterPackingItem`) | `master.conditions.evaluate(against: trip.attributes)` | Reason |
|---|---|---|---|
| `.manual` | — | — | `.manual` |
| `.rule` | nil or not found | — | `.ruleMasterDeleted` |
| `.rule` | found, true | true | `.ruleMatched(text)` |
| `.rule` | found, false | false | `.ruleNoLongerMatches` |

`@MainActor` is explicit on the new overload (matching the existing task overload's enclosing `@MainActor enum`). The function body is a near-copy of the existing task overload; the only diff is the entity type. The duplication is ~30 lines bounded by a four-row mapping table both functions implement identically. Refactoring into a generic over a shared `Whyable` protocol with `var source: ItemSource`, `var masterItemID: UUID?`, and a `master(in:) -> MasterConditionsBearing?` closure is rejected for v1 only because the Phase 3 overload is already shipped and adding the protocol would re-touch its tests; if the duplication drifts (e.g., Phase 5 sync introduces a fifth case), revisit the abstraction then.

### Integration with TripDetailView

```swift
// before
AccordionTimeline(
  trip: trip,
  today: today,
  expandedPhase: $expandedPhase,
  openDisclosureTaskID: $openDisclosureTaskID,
  onAddTaskInPhase: { … },
  onEditTask: { … }
)

// after
AccordionTimeline(
  trip: trip,
  today: today,
  expandedPhase: $expandedPhase,
  openDisclosureTaskID: $openDisclosureTaskID,
  onAddTaskInPhase: { … },
  onEditTask: { … },
  onOpenPackingSheet: { person, mode in
    packingSheetState = PackingSheetState(person: person, mode: mode)
  }
)
```

`TripDetailView.body` adds a single `.sheet(item: $packingSheetState)` block at the same level as the existing `.sheet(item: $pendingForm)` for tasks. Mode is determined at the call site (in `PackingSummaryRow`) so the sheet itself receives an already-resolved mode and does not introspect the source phase.

### File / module placement

| Component | File |
|---|---|
| `PackingMode`, `PackingCounts`, sort/filter/group helpers | `Scramble/Timeline/PackingListHelpers.swift` (parallel to existing `TaskListHelpers.swift`) |
| `PackingSummarySection`, `PackingSummaryRow`, `PackingProgressBar` | `Scramble/Components/PackingSummarySection.swift` (one file; the three views are tightly coupled) |
| `PackingItemRow` | `Scramble/Components/PackingItemRow.swift` |
| `PackingSheet`, `PackingSheetState`, `PackingSheetHeader` | `Scramble/Features/Trips/PackingSheet.swift` |
| `PackingItemForm`, `PackingItemFormPresentation` | `Scramble/Features/Trips/PackingItemForm.swift` |

`PackingProgressBar` is co-located with `PackingSummarySection` because nothing else renders it. Promote to its own file if a second consumer ever appears.

### Pattern extension audit (WhyDisclosure → packing)

Parallel surfaces Phase 4 must add to match the Phase 3 task patterns:

| Surface | Parallel for packing |
|---|---|
| `WhyDisclosure.Reason` enum | Reuse verbatim — same strings (Req [7.4](requirements.md#7.4) – [7.7](requirements.md#7.7)) |
| `WhyDisclosureView` initializer | Migrate from `phaseColour:` to `style:` (API break) |
| `WhyResolver.reason` | Add `@MainActor` overload for `TripPackingItem` |
| `TaskRow` `.onChange` cache invalidations on `trip?.attributesData` / `currentlyMatchesRules` / `name` | Same triggers on `PackingItemRow` |
| Rotor action `"Why is this here?"` | Same rotor action on `PackingItemRow` |

`ConditionsFormatter` is unchanged — both master types use the same `ItemConditions` value type.

The `WhyDisclosureView` API break has a wider surface than "one caller migrates": `TaskRow` itself is a Phase 3 shipped component with passing UI tests that instantiate it and assert on the `tripDetail.whyDisclosure.{taskName}` accessibility ID. The id pattern is unchanged, but the `Style` migration touches `TaskRow`'s body and therefore its UI test stability. The Phase 4 implementation MUST re-run the Phase 3 `WhyDisclosure*` UI tests (`testLongPressOpensWhyDisclosure`, `testOnlyOneDisclosureOpenAtATime`, `testTapElsewhereDismissesDisclosure`) and confirm they pass post-migration. No deprecated `phaseColour:` overload is provided; in-tree migration is straightforward enough that a deprecation surface is unjustified.

### Engine integration

Phase 4 makes no changes to `Snapshots.swift`, `Compute.swift`, `Apply.swift`, or `RulesEngineRunner`. Req [10](requirements.md#10) documents the existing engine contract that Phase 4 depends on — a forward-pointer for Phase 5 (CKShare) sync triggers, not a new code path.

## Components and Interfaces

### `PackingMode`

```swift
nonisolated enum PackingMode: Sendable {
  case pack       // opened from .departureDay
  case repack     // opened from .dayBeforeReturn
}
```

### `PackingCounts`

```swift
nonisolated struct PackingCounts: Sendable {
  let toPack: Int          // count of .unpacked
  let packed: Int          // count of .packed
  let repacked: Int        // count of .repacked
  let excluded: Int        // count of .excluded
}
```

Constructed by `PackingListHelpers.counts(for: Person, in: Trip)`. Pure function; testable without a `ModelContainer`.

### `PackingListHelpers`

```swift
nonisolated enum PackingListHelpers {
  static func itemsForPerson(_ trip: Trip, person: Person) -> [TripPackingItem]
  static func counts(for person: Person, in trip: Trip) -> PackingCounts
  static func summaryStatus(_ counts: PackingCounts, mode: PackingMode) -> String
  static func progressRatio(_ counts: PackingCounts, mode: PackingMode) -> Double
  static func phaseSubline(_ trip: Trip, mode: PackingMode) -> String
  static func sorted(_ items: [TripPackingItem]) -> [TripPackingItem]   // active-first, then case-insensitive name, then id
}
```

`summaryStatus` and `progressRatio` implement Req [1.3](requirements.md#1.3)–[1.5](requirements.md#1.5) verbatim. `phaseSubline` sums per-person `N`-to-pack / `N`-to-repack across `trip.participants`, producing the strings defined in Req [1.10](requirements.md#1.10).

### `PackingSummarySection`

```swift
struct PackingSummarySection: View {
  let trip: Trip
  let mode: PackingMode
  let onOpenSheet: (Person, PackingMode) -> Void
}
```

Renders one `PackingSummaryRow` per `Person` in `trip.participants` (sorted by `name` case-insensitive, then `id`). When `trip.participants` is empty, renders the Req [1.8](requirements.md#1.8) placeholder line.

### `PackingSummaryRow`

```swift
struct PackingSummaryRow: View {
  let person: Person
  let counts: PackingCounts
  let mode: PackingMode
  @AccessibilityFocusState.Binding var focusOnDismiss: UUID?  // wired by parent
  let onOpen: () -> Void
}
```

Layout: 26pt `PersonAvatar` (active-style), name (13pt weight 600), `PackingProgressBar` (3pt height), status label, trailing chevron. Tap handler on the entire row (44pt min height) fires `onOpen` and emits the soft-impact "Sheet present" haptic per Req [1.7](requirements.md#1.7).

`focusOnDismiss` is a `@AccessibilityFocusState.Binding` to a `UUID?` keyed by `Person.id`. When the sheet dismisses, the parent sets this binding to the originating person's id; the row's `.accessibilityFocused($focusOnDismiss, equals: person.id)` restores focus per Req [9.7](requirements.md#9.7).

VoiceOver label construction (Req [9.1](requirements.md#9.1)) is built by a private helper:

```swift
private var accessibilityLabel: String {
  let action = (mode == .pack) ? "packed" : "repacked"
  let denominator: Int = (mode == .pack)
    ? counts.toPack + counts.packed
    : counts.packed + counts.repacked
  let numerator: Int = (mode == .pack) ? counts.packed : counts.repacked
  if denominator == 0 {
    return "\(person.name)'s packing, no items, double tap to open packing sheet"
  }
  return "\(person.name)'s packing, \(numerator) of \(denominator) \(action), double tap to open packing sheet"
}
```

Attached via `.accessibilityElement(children: .combine)` plus `.accessibilityLabel(accessibilityLabel)`.

### `PackingProgressBar`

```swift
private struct PackingProgressBar: View {
  let ratio: Double           // 0.0…1.0, clamped
  let personColour: Color
}
```

3pt height, 2pt radius. Track: person colour at 12% opacity. Fill: person colour at full opacity for `ratio in [0, 1)`, `checkColour` at `ratio == 1.0` per Req [1.5](requirements.md#1.5).

### `PackingSheet`

```swift
struct PackingSheet: View {
  let trip: Trip
  let person: Person
  let mode: PackingMode
  let onDismiss: () -> Void

  @Environment(\.modelContext) private var modelContext
  @Environment(\.theme) private var theme
  @Environment(\.colorScheme) private var colorScheme
  @State private var openDisclosureItemID: UUID?
  @State private var pendingForm: PackingItemFormPresentation?
  @AccessibilityFocusState private var headerFocused: Bool
}
```

Body composition: a `NavigationStack` (for the inner manual-add form to push into when needed) wraps a `ScrollViewReader`-wrapped vertical scroll of `PackingSheetHeader`, three `PackingItemGroup`s (defined per mode), and the pack-mode-only `DashedAddButton`. Modifiers: `.presentationDetents([.large])` and `.presentationDragIndicator(.visible)` per Req [2.1](requirements.md#2.1).

Each `PackingItemGroup` exposes its section-header view via `.id(group.scrollAnchor)`. On sheet appear, the `ScrollViewReader.proxy.scrollTo(firstGroup.scrollAnchor, anchor: .top)` is invoked inside the same `.task` that sets `headerFocused`, satisfying Req [2.6](requirements.md#2.6) by placing the first group's header at the top of the scrollable region on every open.

`PackingSheetHeader` is a private subview owning the close button. Escape is bound on the close button via `.keyboardShortcut(.escape, modifiers: [])`; its action checks `openDisclosureItemID` first and, when non-nil, dismisses the disclosure instead of the sheet (single branch — no duplicate registrations on Escape). Req [9.9](requirements.md#9.9).

The header takes `trip: Trip` and `person: Person` directly (not pre-computed counts), and reads `PackingListHelpers.counts(for: person, in: trip)` inside its body. Because `Trip` is a `@Model` and SwiftUI observes its mutations through the parent view's `@Bindable`/relationship subscription, the header re-renders on any `TripPackingItem.state` change. A snapshot-via-closure would freeze the counter at sheet-open time, which would diverge from the body's current contents.

`headerFocused` is set to `true` inside a `.task` (not `.onAppear`) with a small `Task.sleep` delay so the binding fires after iOS has built the sheet's accessibility tree (Req [9.7](requirements.md#9.7)):

```swift
.task {
  try? await Task.sleep(for: .milliseconds(500))
  headerFocused = true
}
```

`.onAppear` runs too early on real devices — the a11y frame for the sheet has not been built yet and the focus binding silently fails. The 500ms delay matches Apple's WWDC guidance for cross-context VoiceOver focus handoff.

#### Group definitions

```swift
private enum SheetGroup {
  case stillNeedToPack, packed, notBringing   // pack mode
  case stillInSuitcase, backInSuitcase, leftBehind  // repack mode
}
```

A `SheetGroup` knows its filter, its header text, its header colour (`warn`/`check`/`textSecondary`), and the per-row affordance (Skip/Restore/none). `PackingSheet` enumerates the right three groups for the active mode and renders each via a `PackingItemGroup` view.

#### Participant-removal dismissal (Req 2.8)

```swift
private var participantIDSignature: Set<UUID> {
  Set((trip.participants ?? []).map(\.id))
}

.task(id: participantIDSignature) {
  if !participantIDSignature.contains(person.id) {
    onDismiss()
  }
}
```

`Set<UUID>` keying is deliberate: SwiftData's `@Relationship` array surface does not guarantee stable ordering across re-faults or CloudKit sync arrivals, so an array-based id (`[UUID]`) would re-fire the task on every re-order even when membership is unchanged. `Set<UUID>` compares by membership and is `Hashable`, which is what `.task(id:)` needs.

Focus restoration on auto-dismiss is driven entirely by `TripDetailView`'s single `.sheet(item: $packingSheetState, onDismiss: …)` closure — no separate `pendingFocus` enum, no second `@AccessibilityFocusState`. The `onDismiss` closure inspects whether the originating person still exists in `trip.participants`:

- **Originating person present** (normal close, swipe-down, or close-button): set the summary-row focus binding to the person's id; SwiftUI lands focus on the row when the next a11y frame is built.
- **Originating person absent** (participant removed mid-sheet): set the focus binding to `nil` and post a `UIAccessibility.Notification.layoutChanged` so VoiceOver picks the section header heuristically. Explicit focus targeting on a removed row is silently a no-op; using `.layoutChanged` is the iOS-standard fallback.

### `PackingItemGroup`

```swift
private struct PackingItemGroup: View {
  let trip: Trip
  let person: Person
  let group: SheetGroup
  let mode: PackingMode
  @Binding var openDisclosureItemID: UUID?
}
```

Filters per-person items by the group's predicate, sorts via `PackingListHelpers.sorted`, and renders a section header + a `ForEach` of `PackingItemRow`. Empty groups render the header only (Req [3.2](requirements.md#3.2)).

### `PackingItemRow`

```swift
struct PackingItemRow: View {
  let item: TripPackingItem
  let group: SheetGroup
  let mode: PackingMode
  let personColour: Color
  let isDisclosureOpen: Bool
  let onToggleState: () -> Void          // unpacked↔packed or packed↔repacked
  let onSkipOrRestore: () -> Void        // mode/group dependent
  let onLongPress: () -> Void
  let onEdit: () -> Void

  @Environment(\.modelContext) private var modelContext
  @State private var resolvedReason: WhyDisclosure.Reason?
}
```

Layout: checkbox / dashed-placeholder (24pt) on the leading edge, item name + italic condition tags + inline `WhyDisclosureView`, inline action button (`Skip` / `Restore` / none) at the trailing edge. Mirrors `TaskRow`'s structure verbatim except for the trailing avatar (no assignee here — the sheet is already person-scoped).

`.swipeActions(edge: .trailing)` exposes Edit when the row has a checkbox; `.contextMenu` mirrors Edit. Body long-press toggles disclosure, spatially constrained per Req [6.5](requirements.md#6.5):

- **Active groups** (checkbox-bearing rows): long-press attached to the `Text(item.name)` + condition-tags region; `.contextMenu` attached to the trailing inline-action region (Skip/Restore button or its leading padding). The two attached views are HStack siblings; no overlap.
- **Read-only groups** (`notBringing` / `leftBehind`, dashed-placeholder rows): long-press attached to the row's name + tags region (the placeholder area is excluded from the long-press recognizer). `.contextMenu` is not attached on read-only rows (no Edit affordance). The dashed placeholder remains a visual element with no gesture.

Inline Skip / Restore button: a `Button` (not just a tap-gesture-on-Text) with `.buttonStyle(.plain)`, an explicit `.accessibilityLabel("Skip")` or `.accessibilityLabel("Restore")`, and `.frame(minWidth: 44, minHeight: 44)` for the touch-target requirement. The same action is exposed via the row's `.accessibilityAction(named: …)` rotor entry per Req [9.3](requirements.md#9.3); the inline button and the rotor action share a single handler closure.

Disclosure caching mirrors `TaskRow`:

```swift
.onChange(of: isDisclosureOpen)   { _, open in refreshReason(open: open) }
.onChange(of: item.trip?.attributesData)  { _, _ in if isDisclosureOpen { … } }
.onChange(of: item.currentlyMatchesRules) { _, _ in if isDisclosureOpen { … } }
.onChange(of: item.name)                  { _, _ in if isDisclosureOpen { … } }
```

#### Checkbox

Per UI doc §"Checkbox colour rules":

- **Pack mode, active groups** (`stillNeedToPack` / `packed`): unchecked uses person colour at 67%, checked uses `checkColour` solid.
- **Repack mode, active groups** (`stillInSuitcase` / `backInSuitcase`): unchecked uses `checkColour` at 67%, checked uses `checkColour` solid.
- **Read-only / excluded groups** (`notBringing` / `leftBehind`): dashed border in `textSecondary`; no checked state.

Items rendered in the `packed` or `backInSuitcase` group show as already-checked (they reached the group via a prior toggle); tapping them un-packs / un-repacks.

#### Group-move announcement (Req 9.8)

```swift
private func announce(_ targetGroupTitle: String) {
  #if canImport(UIKit)
    UIAccessibility.post(notification: .announcement, argument: "Moved to \(targetGroupTitle)")
  #endif
}
```

Called after the state mutation commits. Group titles are the localised section header strings.

#### Dimmed rendering (Req 3.9 / 4.8)

```swift
private var rowOpacity: Double {
  (item.currentlyMatchesRules || item.pinnedByUser) ? 1.0 : 0.5
}
```

Single `.opacity(rowOpacity)` modifier on the row, matching the TaskRow pattern's "single multiplier, never chained" guidance (`TaskRow.rowOpacity` in Phase 3). Packing rows have no `isCompleted` field, so the 0.45-vs-0.5 trade-off Phase 3 made does not arise; flat 0.5 applies.

### `PackingItemForm`

```swift
enum PackingItemFormPresentation: Identifiable {
  case add(person: Person, trip: Trip)
  case edit(item: TripPackingItem)
  var id: String { /* … */ }
}

struct PackingItemForm: View {
  let mode: PackingItemFormPresentation
  let onSave: () -> Void
  let onCancel: () -> Void
}
```

Single name field (200-char cap enforced via `.onChange`), no assignee picker (active person implied per Req [5.2](requirements.md#5.2)), no conditions field. Form-on-sheet presentation per Decision 9.

Save semantics:

| Mode | Save action |
|---|---|
| `.add(person, trip)` | Insert `TripPackingItem(source: .manual, name: trimmed, person: person, trip: trip, state: .unpacked, currentlyMatchesRules: true, pinnedByUser: false, masterItemID: nil)`; call `try modelContext.save()` |
| `.edit(item)` | Set `item.name = trimmed`; call `try modelContext.save()` |

On save failure: log via `modelLogger.error` with `[PackingSheet.save-failed]` marker. **Form behaviour on save failure differs from `TaskForm`**: the form remains open with the user's input intact and a non-modal inline error string (`"Couldn't save — try again."`) appears beneath the save button. Rationale: dismissing the form on save failure silently destroys the typed input — a real UX defect Phase 3 has been carrying. Phase 4 takes the opportunity to fix the pattern; a follow-up should retrofit `TaskForm`.

For `.edit` failures, the mutation has already been applied to the `@Model` instance before `save()` was called. SwiftData does not auto-rollback uncommitted in-memory edits; the design calls `modelContext.rollback()` before logging, which restores the prior name on the `@Model` instance.

### Sheet-on-sheet presentation

`PackingSheet` presents `PackingItemForm` via `.sheet(item: $pendingForm)` on its own body. iOS 17.0 – 17.2 had documented regressions in nested-sheet swipe-down handling (the outer sheet could dismiss alongside the inner) and iOS 18 changed nested detent inheritance; Phase 4's target is iOS 26 where these are reportedly resolved. The behaviour is verified by `testInnerFormSwipeDownKeepsPackingSheet` (automated UI test, not manual) so a regression on a future iOS update would surface in CI.

If the UI test reveals a regression on the target iOS version, the fallback is to push the form via `NavigationLink` inside the outer sheet's `NavigationStack`. Decision 9 rejected `NavigationLink` for the v1 default because of the back-chevron affordance, but the rejection is reversible if the sheet-on-sheet path proves unstable on the device — the back chevron can be hidden via `.toolbar(.hidden, for: .navigationBar)` plus an explicit Cancel button matching the current form's toolbar.

### Short-form name derivation (Req 5.1)

```swift
extension Person {
  var shortDisplayName: String {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    if let first = trimmed.split(separator: " ").first, !first.isEmpty {
      return String(first)
    }
    return trimmed.isEmpty ? "?" : trimmed
  }
}
```

The space-split is a deliberate v1 simplification. Names lacking a space-separated first token fall through to the full name. Internationalisation of name forms is out of scope (per Non-Goals in requirements.md and the project's stated v1 user base).

## Error Handling

| Failure mode | Surface | Behaviour |
|---|---|---|
| `modelContext.save()` throws on state mutation | `PackingItemRow` checkbox / Skip / Restore | Log `[PackingSheet.save-failed]`; SwiftData reverts on next body eval (Req [8.4](requirements.md#8.4)) |
| `modelContext.save()` throws on manual add | `PackingItemForm` | Log; form dismisses regardless (matches `TaskForm` precedent) |
| `modelContext.save()` throws on rename | `PackingItemForm` | Same as add — log + dismiss |
| `masterItemID` references missing `MasterPackingItem` | `WhyDisclosureView` | `.ruleMasterDeleted` reason (Req [7.6](requirements.md#7.6)) |
| `Person` referenced by `item.person` disappears | `PackingItemRow` | Row remains in the sheet body (the sheet's bound `Person` is the active person, not `item.person`); a stale `item.person == nil` for an item that should belong here is a degenerate state — the engine guard logs `[RulesEngine.skip-orphan-master]`. UI shows the item with no avatar; this is the existing dangling-reference precedent. |
| `trip.participants` removes the active person mid-sheet | `PackingSheet` | Auto-dismiss via `.task(id:)` watcher (Req [2.8](requirements.md#2.8)) |
| Concurrent engine apply during user gesture | `PackingItemRow` | The engine writes `currentlyMatchesRules`; the user's gesture writes `state`. The fields do not conflict, so both writes commit. Body re-eval after the engine apply re-renders the row with the new `currentlyMatchesRules` (e.g., dimmed treatment may appear) while the user's `state` change remains. Req [8.5](requirements.md#8.5) framed as "engine write wins": correctly stated for the field the engine touches; the user's gesture is not aborted. |
| Engine deletes `TripPackingItem` mid-gesture | `PackingItemRow` mutation handler | Phase 4's engine never deletes — it only flags (`currentlyMatchesRules`). True deletion only occurs via master-list editor (`MasterPackingItem` removal cascades through the engine's `apply` to flag, not delete). The only deletion path Phase 4 exposes is `modelContext.delete(item)` for failed-save rollback in the manual-add flow, which the form owns. `PackingItemRow` mutations therefore never operate on a deleted `@Model` instance. If a future phase adds a deletion path, the handler should guard via `item.modelContext == nil` before mutating. |
| Empty `trip.participants` on packing phase | `PackingSummarySection` | Placeholder row per Req [1.8](requirements.md#1.8) |
| `Person.name` empty | `PersonAvatar` / `Person.shortDisplayName` | Avatar shows `"?"` (existing helper); `shortDisplayName` returns `"?"` |

No new alert dialogs or error banners are introduced. Save-failure surfacing is the same silent-log pattern Phase 3 chose; revisit when error UI is in scope across the app.

## Testing Strategy

### Unit tests (Swift Testing, `ScrambleTests/`)

| Suite | Coverage |
|---|---|
| `PackingCountsTests` | `PackingListHelpers.counts(for:in:)` over fixture trips: empty participants, person with all states populated, person with only `.excluded`, person with zero items. PBT candidate: property "denominator + numerator never exceeds total items for that person" over randomly-generated `TripPackingItem` arrays |
| `PackingStatusTests` | `summaryStatus` returns exactly `"No items"` / `"—"` / `"✓ ready"` / `"{N} to pack"` for pack mode and the four repack analogues; one row per Req 1.3 / 1.4 branch, including the disambiguation between "no items" and "all excluded" |
| `PackingProgressRatioTests` | `progressRatio` returns 0.0 when denominator zero; 1.0 only when every counted item is in the goal state; intermediate ratios match `numerator / denominator`. PBT candidate over random counts: `ratio ∈ [0.0, 1.0]` always |
| `PackingPhaseSublineTests` | `phaseSubline` aggregates across participants for both modes; produces `"all back in"`, `"packing ready"`, and `"{S} to pack"` / `"{S} to repack"` per Req [1.10](requirements.md#1.10) |
| `PackingListHelpersSortedTests` | `sorted(_:)` returns active-before-dimmed, then case-insensitive ascending name, then id tiebreak (Req [3.8](requirements.md#3.8) / [4.7](requirements.md#4.7)). Uses mixed-case fixtures including non-ASCII letters |
| `WhyResolverPackingTests` | All four `Reason` branches for `TripPackingItem`: manual; rule with nil `masterItemID`; rule with `masterItemID` not in store; rule with matching/non-matching conditions. Mirrors `WhyResolverTests` from Phase 3 |
| `PackingSummaryDimmedCountsTests` | Req [1.6](requirements.md#1.6): a dimmed (unmatched-non-pinned) item still counts toward `packed` / `unpacked` / `repacked` totals |
| `PersonShortDisplayNameTests` | `shortDisplayName` on `"Arjen"`, `"Mary Jane Watson"`, `""`, `"   "`, single-CJK-character names; documents the v1 space-split behaviour |
| `PackingFormSaveTests` | Manual-add via `PackingItemForm.save` creates a `TripPackingItem` with the documented field values (Req [5.3](requirements.md#5.3)); edit-mode rename leaves all other fields unchanged including `masterItemID`, `currentlyMatchesRules`, `pinnedByUser`, `source` |
| `WhyDisclosureStyleTests` | The new `Style` enum maps correctly: `.tasks` produces 8% background + 20% border; `.packing` produces 6% background + no border. Driven by snapshot fixtures, not pixel comparison |

PBT framework: same hand-rolled `@Test(arguments:)` approach Phase 3 uses; SwiftCheck is still not a project dependency.

### UI tests (XCTest, `ScrambleUITests/`)

Accessibility IDs extend the existing pattern:

- `tripDetail.packingSummary.{personId}` — row tap target per person
- `packingSheet.header` — sheet header element
- `packingSheet.counter` — counter text
- `packingSheet.itemRow.{itemName}` — per-item row
- `packingSheet.addItemButton` — pack-mode add affordance
- `packingSheet.whyDisclosure.{itemName}` — visible iff disclosure open
- `packingSheet.section.{stillNeedToPack|packed|notBringing|stillInSuitcase|backInSuitcase|leftBehind}` — section header tap target for layout assertions

Scenarios:

| Test | Path |
|---|---|
| `testPackingSummaryRendersInDeparturePhase` | Seed trip with two participants; expand Departure; assert two summary rows present with correct counts |
| `testTappingSummaryRowOpensSheet` | Tap row; assert `packingSheet.header` present and counter reflects expected pack-mode numbers |
| `testPackModeCheckboxTogglesState` | Toggle an `unpacked` item; assert it moves from `stillNeedToPack` to `packed` section (visibility change via accessibility id) |
| `testSkipMovesItemToNotBringing` | Tap Skip on an `unpacked` row; assert row appears in `notBringing` section, dashed border via state property |
| `testRestoreReverses` | Skip then Restore the same item; assert row is back under `stillNeedToPack` |
| `testRepackOpensFromDayBeforeReturn` | Day-before-return phase tap; assert sheet counter uses "repacked" terminology |
| `testLeftBehindRowIsReadOnly` | Repack mode; long-press a `leftBehind` row; assert disclosure opens; tap checkbox region; assert state unchanged |
| `testAddManualItemAppearsInUnpacked` | Pack mode; tap "+ Add item for Arjen"; submit name "Sunscreen"; dismiss form; assert row present in `stillNeedToPack` |
| `testRenameViaSwipe` | Trailing swipe on packed item; tap Edit; submit new name; assert row label updated; assert master not renamed (via a debug marker on master row count, or a follow-up master-list inspection) |
| `testWhyDisclosurePackingMatched` | Long-press a rule-driven item; assert `packingSheet.whyDisclosure.{name}` visible with the matched-conditions text |
| `testWhyDisclosurePersonColouredBackground` | Long-press; assert disclosure background reflects the active person's colour at 6% (via a `_accessibility` debug marker exposing the colour key — same pattern as Phase 3) |
| `testSheetDismissOnParticipantRemoval` | Open sheet for person A; from another tab, remove person A from trip; return to trip; assert sheet auto-dismissed |
| `testDimmedItemCountsInProgressBar` | Seed a participant with one `currentlyMatchesRules == false && !pinned` item in `packed`; assert progress bar fill ratio reflects it (via a debug marker exposing `progressRatio`) |
| `testSheetSubsetOfCounterIncludesDimmed` | Open sheet; assert counter denominator includes dimmed items per Req [1.6](requirements.md#1.6) |
| `testEscapeDismissesSheet` | External keyboard fixture; open sheet; press Escape; assert sheet dismissed |
| `testEscapeDismissesDisclosureFirst` | Open disclosure inside sheet; press Escape; assert disclosure dismissed but sheet still present; press Escape again; assert sheet dismissed |
| `testPhaseSublineCombined` | Expand Departure; assert subline contains both `"{C}/{T} tasks"` and `"{S} to pack"` clauses joined with `" · "` |
| `testInnerFormSwipeDownKeepsPackingSheet` | Open packing sheet → tap "+ Add item" → swipe down on the inner form; assert `packingSheet.header` still present and `packingSheet.addItemButton` still visible |
| `testManualAddSaveFailureKeepsFormOpen` | Inject a `modelContext.save()` failure via the existing test fixture; submit Add Item form; assert the form remains presented with the entered name intact (Req [8.4](requirements.md#8.4) applied to add) |
| `testParticipantRemovalDismissalLandsLayoutChanged` | Open sheet for person A; from a launch-arg-controlled hook, remove person A; assert sheet dismissed and the timeline regains focus (the `layoutChanged` fallback path) |
| `testParticipantReorderDoesNotDismiss` | Open sheet for person A; force a participant-array reorder via the existing seed mechanism; assert sheet remains presented (set-keyed `.task(id:)` does not refire) |
| `testConcurrentEngineFlagDuringToggle` | Open sheet; trigger an engine apply that flips `currentlyMatchesRules` on the row the user is about to toggle; toggle; assert both writes commit and the row reflects the engine's flag in addition to the user's state change |
| `testLeftBehindRowLongPressShowsWhy` | Repack mode; long-press a `leftBehind` row; assert `WhyDisclosure` appears (Req [7.10](requirements.md#7.10) clarification) |

UI tests run serially per existing Makefile setting.

### Manual verification

- Reduce Motion on: confirm sheet present/dismiss does not slide; falls back to system crossfade
- VoiceOver: confirm focus moves to sheet header on present (after the 500ms delay), returns to originating row on dismiss, and announces "Moved to {group}" on toggle
- Dynamic Type AX2: confirm sheet content reflows without truncation
