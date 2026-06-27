# Packing sheet (Phase 4)

The per-person packing surface presented from the Departure and Day-before-return phases. Pack mode operates over `unpacked / packed / excluded`; repack mode operates over `packed / repacked` with a read-only "Left behind" group of `unpacked ∪ excluded`.

## Files

- `Scramble/Scramble/Timeline/PackingListHelpers.swift` — `PackingMode`, `PackingCounts`, and the helpers (`counts`, `countsByPerson`, `summaryStatus`, `progressRatio`, `phaseSubline`, `sorted`, `itemsForPerson`). The enum is `@MainActor` because the helpers traverse SwiftData `@Model` relationship arrays (`trip.packingItems`, `trip.participants`) whose ownership is tied to the main `ModelContext`. `PackingMode` and `PackingCounts` are `nonisolated` value types.
- `Scramble/Scramble/Components/PackingSummarySection.swift` — `PackingSummarySection`, `PackingSummaryRow`, and the private `PackingProgressBar`. Rendered inside the Departure / Day-before-return phase content slot, below `TaskListSection`.
- `Scramble/Scramble/Components/PackingItemRow.swift` — Single row inside the sheet plus the file-scope `SheetGroup` enum (referenced from both `PackingItemRow` and `PackingSheet`). The enum carries its own `headerTitle`, `scrollAnchor`, `matches(_:)`, and `isReadOnly`.
- `Scramble/Scramble/Features/Trips/PackingSheet.swift` — `PackingSheet`, `PackingSheetState`, and the private `PackingSheetHeader` and `PackingItemGroup`.
- `Scramble/Scramble/Features/Trips/PackingItemForm.swift` — Sheet-on-sheet form for manual-add and rename. Carries static testable helpers (`performAdd`, `performEdit`, `isSubmitEnabled`, `cappedName`).

## Counts and the timeline subline

`AccordionTimeline.row(for:variant:proxy:)` calls `PackingListHelpers.phaseSubline(trip, mode:)` for `.departureDay` and `.dayBeforeReturn`. The helper does **one** pass over `trip.packingItems` — earlier versions did O(participants × items) via per-person `counts(for:in:)` calls in a loop; do not regress.

Similarly `PackingSummarySection.body` calls `PackingListHelpers.countsByPerson(trip)` **once** and then looks up each row's `PackingCounts` by `Person.id` rather than re-scanning per row. `counts(for:in:)` still exists for single-person callers and tests, but the multi-person fanout is the one to use inside `body`.

`PackingItemGroup` receives the pre-filtered per-person item list from `PackingSheet.body` rather than re-filtering `trip.packingItems` per group. Three groups × one filter per body = one scan, not three.

## Save-failure UX differs from `TaskForm`

`PackingItemForm` deliberately diverges from `TaskForm`'s "dismiss-on-save-failure" behaviour. On `try modelContext.save()` throwing:

- `.add` — `modelContext.delete(item)` rolls back the in-memory insert; form remains presented with the user's typed name intact; an inline error string (`"Couldn't save — try again."`) appears beneath the save button. Avoids silently destroying typed input on transient save failure.
- `.edit` — `modelContext.rollback()` restores the prior `name` on the `@Model` instance (SwiftData does not auto-revert uncommitted in-memory edits); form remains presented with the user's typed name.

Decision 9 in `specs/phase-4-packing-sheet/decision_log.md` documents the intent to retrofit `TaskForm` to the same pattern in a follow-up.

`PackingSheet`'s state-mutation save (checkbox toggle, Skip, Restore) follows the Phase 3 pattern: log `[PackingSheet.save-failed] <marker>: <error>` via `modelLogger.error` and rely on SwiftData re-emitting the prior state on the next body evaluation. No alert / banner in v1.

## Participant-removal auto-dismiss

`PackingSheet.body` carries `.task(id: participantIDSignature)` where `participantIDSignature` is `Set<UUID>` of `trip.participants` ids. Set keying — **not** array — because SwiftData's `@Relationship` array surface does not guarantee stable ordering across re-faults or CloudKit sync arrivals; an array key would re-fire on every reorder even when membership is unchanged. The watcher calls `onDismiss()` when the bound person is no longer in the set.

Focus restoration on auto-dismiss runs from `TripDetailView.handlePackingSheetDismiss`:

- **Originating person still present** — set the `@AccessibilityFocusState` binding to the person's id; SwiftUI lands VoiceOver focus on the summary row.
- **Originating person absent** — set the binding to `nil` and post `UIAccessibility.Notification.layoutChanged`. Explicit focus targeting on a removed row is silently a no-op; `.layoutChanged` is the iOS-standard fallback.

`TripDetailView` keeps `lastOpenedPackingPerson` as an auxiliary `@State` because `.sheet(item:)` clears `packingSheetState` to nil **before** `onDismiss` fires, so the originating person must be remembered separately.

## VoiceOver focus on present

`PackingSheet.body.task` runs `try? await Task.sleep(for: .milliseconds(500))` before setting `headerFocused = true`. Setting the focus inside `.onAppear` is too early on real devices — the a11y frame for the sheet has not been built yet and the focus binding silently fails. 500ms matches Apple's WWDC guidance for cross-context VoiceOver focus handoff.

## Packing WhyDisclosure removed (long-press)

Packing rows **no longer** surface the "why is this here?" explainability panel. The long-press gesture, the inline `WhyDisclosureView`, the `openDisclosureItemID` sheet state + background dismiss-tap target, and the VoiceOver "Why is this here?" custom action were all removed from `PackingItemRow` / `PackingSheet` — the owner found it unused and the long-press made the row interaction noisy. This is a deliberate divergence from phase-4 Req 6.5 / 7.10 and phase-6 Req 9.5 (which were packing-specific).

Consequences:
- `WhyDisclosureView` and `WhyResolver` still exist — the **task** surface (`TaskRow` / `TaskListSection`) keeps long-press WhyDisclosure unchanged.
- `WhyResolver.reason(for: TripPackingItem, …)` now has no production caller; it stays in place (and is still covered by `WhyResolverPackingTests` / `WhyResolverParticipantHideTests`) rather than being torn out, since it's a pure function and removing it would churn the shared resolver the task path depends on. The `WhyDisclosure.Style.packing(personColour:)` case is likewise now test-only.

## Gotcha: `PackingItemRowAccessibilityTests` crashes when run in isolation

`PackingItemRowAccessibilityTests` (and likely other `@MainActor .serialized` suites that build a fresh `ModelContainer(for: SchemaV3)` per test) **crashes the xctest process when run via a narrow `-only-testing` selection** — every test reports `failed (0.000 seconds)` and the suite re-runs (xcodebuild relaunches after a crash). This is **pre-existing and not a logic failure**: an individual test (`-only-testing:…/unownedLabel`) passes, and the full `make test-quick` (whole `ScrambleTests` target) passes too. The crash is the repeated CloudKit-schema `ModelContainer` creation issue (see `rules/language-rules/swift.md` → "Shared ModelContainer Initialization in Tests").

Practical consequence: **verify these suites with the full `make test-quick`, not a hand-picked `-only-testing` subset.** A green/red from a small subset run is unreliable for the container-creating suites. (Confirmed by stashing all changes and reproducing the identical crash on unmodified `main`.)

## WhyDisclosure `Style` migration

`WhyDisclosureView` migrated from `init(reason:, phaseColour:)` to `init(reason:, style:)` where `style` is a `WhyDisclosure.Style` enum with `.tasks(phaseColour:)` and `.packing(personColour:)` cases. The case resolves internally to `(tint: Color, backgroundOpacity: Double, borderOpacity: Double?)`:

| Case | tint | background | border |
|---|---|---|---|
| `.tasks` | phase colour | 0.08 | 0.20 |
| `.packing` | person colour | 0.06 | nil (no border) |

`TaskRow.swift` is the only Phase 3 call site that migrated. No deprecated overload — in-tree migration was small enough that a deprecation surface wasn't worth carrying.

## WhyResolver overload — no protocol abstraction

`WhyResolver.reason(for:context:)` has two `@MainActor` overloads — one for `TripTask`, one for `TripPackingItem`. They share ~30 lines of identical four-branch logic (manual → manual; rule with missing master → ruleMasterDeleted; rule with matching/non-matching conditions). The duplication is deliberate (`specs/phase-4-packing-sheet/design.md` §"Integration with WhyResolver"): abstracting into a `Whyable` protocol would re-touch Phase 3's shipped task overload + tests for an ~30-line saving. Revisit if a third overload or a fifth branch appears.

## Sheet-on-sheet manual-add

`PackingItemForm` is presented from `PackingSheet` via an inner `.sheet(item: $pendingForm)`. iOS 17.0 – 17.2 had documented nested-sheet regressions; the target is iOS 26 where these are resolved. UI test `testInnerFormSwipeDownKeepsPackingSheet` exercises the path so a regression on a future iOS update surfaces in CI. Fallback if iOS regresses: push the form via `NavigationLink` inside the outer sheet's `NavigationStack` with `.toolbar(.hidden, for: .navigationBar)` plus an explicit Cancel button.

## Dimmed items count in progress (Decision 5)

A dimmed (`!currentlyMatchesRules && !pinnedByUser`) item that is `packed` is **physically in the suitcase** and still counts toward `packed / (unpacked + packed)`. This diverges from Phase 3's task counts (which exclude dimmed via `+N inactive` suffix) on purpose: tasks are required-vs-not state; packing is physical state. See `PackingListHelpers.counts(for:in:)` — no filtering on `currentlyMatchesRules` / `pinnedByUser`.

## Per-trip note + sub-items inline editors (T-1587, Decision 14)

`PackingItemRow` hosts **two mutually-exclusive inline editors** — a note editor and a sub-item add field — revealed by trailing **note (`note.text`) / list (`list.bullet`) glyphs** left of Skip. Gotchas:

- The reveal state (`isAddingSubItem` / `isEditingNote`) is **owned by `PackingItemRow`** and passed as bindings into `PackingSubItemsView`; the row reports "any editor open" to `PackingSheet` from a **single** `onChange(of: isAddingSubItem || isEditingNote)` (not per-binding) so a direct switch between the two editors never momentarily reads as closed and drops the sheet's background dismiss tap-catcher (`activeAddFieldItemID`).
- `PackingItemRow.body` must read `item.note` / `item.subItems` **directly** (hoisted into locals, then threaded into `rowContent`) so SwiftData establishes observation — that is what makes an inbound sync re-render the row. `item.subItems` decodes its JSON blob on each access, so read it once.
- Inline note editing commits through `PackingItemGroup.saveNote` → the same `hook.commit` chokepoint as sub-item add/remove; it saves on blur **and** on `PackingSubItemsView.onDisappear` (a native sheet swipe-down isn't guaranteed to fire `@FocusState` blur before teardown). `saveNote` no-ops on an unchanged value so the two paths never double-write or push a spurious CKRecord. The edit form (`PackingItemForm`) still has a note field as the full-edit path.
- **Known a11y limitation:** the VoiceOver "Add sub-item" custom action (`AddSubItemAccessibilityAction`) inserts a fixed placeholder (`"New sub-item"`) because there is no inline VoiceOver rename — the sighted path is the reveal field. Accepted for v1 (Req 8.2); a VoiceOver-friendly add/rename flow is a follow-up.
