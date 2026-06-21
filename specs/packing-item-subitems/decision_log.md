# Decision Log: Packing Item Sub-items

## Decision 1: Store both a free-form note and a sub-item list

**Date**: 2026-06-21
**Status**: accepted

### Context

T-1587 asks for per-trip notes and sub-items on packing items so a generic item ("toys", "books") can record exactly which specific things to bring. The content could be modelled as a single free-form note, a structured list of sub-items, or both.

### Decision

Each packing item carries an optional free-form note plus an ordered, appendable list of sub-item entries, both scoped to the trip.

### Rationale

The ticket language ("exactly which ones", "add to while packing") points at a discrete, appendable list. The "notes" half of the ticket title covers detail that isn't a discrete item (e.g. "keep batteries out of the toys"), which a flat list can't express well. Supporting both matches the user's selection and the dual phrasing of the ticket.

### Alternatives Considered

- **Single free-form note only**: Simplest model and sync surface - rejected because it can't render "add to while packing" as discrete, individually removable entries.
- **Sub-item list only**: Structured and appendable - rejected because the note use case ("keep batteries out") has no natural home as a list entry.

### Consequences

**Positive:**
- Covers both the "which ones" and "extra detail" use cases.
- Sub-items are individually removable; the note is a single editable blob.

**Negative:**
- Two pieces of content to model, render, and sync rather than one.

---

## Decision 2: Sub-item status is not tracked

**Date**: 2026-06-21
**Status**: accepted

### Context

The ticket states sub-item status does not need tracking. The app's packing items already carry a `PackingState` (unpacked / packed / repacked / excluded).

### Decision

Sub-items are reference text only. They have no packed/unpacked state and do not participate in counts, progress, or group membership.

### Rationale

Tracking per-sub-item state would multiply the state machine and the packing-sheet UI for no stated benefit. The user packs the parent item ("toys") as a unit; the sub-items just remind them what to put in.

### Consequences

**Positive:**
- No new state machine, no impact on the existing pack/repack counters.

**Negative:**
- A user wanting to tick off individual sub-items is not served (explicit non-goal).

---

## Decision 3: Inline display on the row with quick-add

**Date**: 2026-06-21
**Status**: accepted

### Context

Three surfaces were considered for showing and editing sub-items: inline on the packing row, the existing long-press disclosure (shared with "Why is this here?"), or a dedicated editor sheet.

### Decision

Existing note and sub-items render inline under the item name on its packing row. Adding a sub-item uses an inline quick-add affordance on interactive rows.

### Rationale

"Easy to see them and add to while packing" favours always-visible content over a disclosure or sheet that must be opened first. Inline keeps the information in view during the packing flow.

### Alternatives Considered

- **Long-press disclosure**: Reuses an existing region - rejected because content is hidden until opened, working against "easy to see".
- **Dedicated editor sheet**: More room for editing - rejected as too many taps for the quick "add as you think of it" flow.

### Consequences

**Positive:**
- Content and the add affordance are visible during packing.

**Negative:**
- Adds vertical weight to every interactive row; the add affordance must stay visually light. Density to be validated in design (see open point).

---

## Decision 4: View everywhere, edit only on interactive rows

**Date**: 2026-06-21
**Status**: accepted

### Context

Packing rows appear in interactive groups (Still need to pack, Packed, Still in suitcase, Back in suitcase) and read-only groups (Not bringing, Left behind), across pack and repack modes.

### Decision

Existing note and sub-items are visible on every row in every mode and group. Add and remove affordances appear only on interactive (non-read-only) rows.

### Rationale

The information is useful for reference when repacking or reviewing what was left behind, so it should always be visible. Editing affordances follow the existing read-only convention (`SheetGroup.isReadOnly`), which already suppresses the checkbox, Skip/Restore, and Edit on those groups.

### Consequences

**Positive:**
- Consistent with the established read-only-group behaviour.

**Negative:**
- A user cannot tidy sub-items on an excluded/left-behind item without first restoring it.

---

## Decision 5: Per-entry character limits (sub-item 200, note 500)

**Date**: 2026-06-21
**Status**: accepted

### Context

The existing item name is capped at 200 graphemes (`PackingItemForm.nameLimit`). Notes and sub-items need bounds to keep within the per-blob sync size cap (`kRecordBlobSizeCap`, 256 KB) and to keep rows renderable.

### Decision

A single sub-item entry is limited to 200 characters (matching the item-name cap); the note is limited to 500 characters. No hard cap on the number of sub-items beyond the per-blob size limit.

### Rationale

Reusing the 200 cap for sub-items keeps the input rules consistent with item names. 500 for the note gives room for a sentence or two without approaching the blob cap. Counts are bounded implicitly by the existing blob-size guard.

### Alternatives Considered

- **No per-entry limits**: Simplest - rejected because unbounded text risks the blob-size cap and unbounded row height.

### Consequences

**Positive:**
- Concrete, testable bounds consistent with existing input handling.

**Negative:**
- The 500 note cap is a judgement call and may need adjustment after use.

### Note (amended after review)

The unit is **grapheme clusters**, not "characters" — the existing `PackingItemForm.nameLimit` uses `String.prefix(200)`, which counts grapheme clusters. Requirements 2.4 / 4.4 were corrected to say "grapheme clusters" so the test asserts what the implementation enforces. A separate sub-item **count** cap was added — see Decision 9.

---

## Decision 6: Last-writer-wins sync, consistent with existing fields

**Date**: 2026-06-21
**Status**: accepted

### Context

`TripPackingItem` syncs through `TripSyncEngine` / `TripPackingItemRecordTranslator`. Codable blob fields (e.g. `Trip.attributesData`) resolve concurrent edits per-field as last-writer-wins.

### Decision

Notes and sub-items sync as item fields and resolve concurrent cross-device edits with the same last-writer-wins semantics as the item's other attributes. The sub-item list is treated as one field for conflict purposes.

### Rationale

Matching the established blob/field behaviour avoids inventing merge logic. Concurrent sub-item additions from two devices may lose one side's change; this is acceptable for v1 and consistent with how the app already handles concurrent attribute edits.

### Alternatives Considered

- **Union / append-merge of the sub-item list**: Suggested in review to avoid dropping concurrent additions - rejected. Union without tombstones resurrects deleted sub-items (device A removes "socks", device B's blob still contains it, the merge brings it back), which is a persistent, confusing failure worse than the rare dropped add. Correct union needs per-entry IDs + tombstones + GC (an OR-Set CRDT), breaking the app's uniform "Codable blob, LWW per field" model and the stated simplicity value. Two external reviewers (Codex, Kiro) independently reached the same conclusion.

### Consequences

**Positive:**
- No new conflict-resolution machinery; reuses the proven translator pattern.

**Negative:**
- Simultaneous edits to the **same item's** list on two devices can drop one side's addition. Acceptable for the expected low-contention family packing flow; Req 6.3 now states this consequence explicitly rather than leaving it silent.

### Escalation path (if concurrent-add loss bites)

If real usage shows lost concurrent additions, the non-CRDT escalation is **one CKRecord per sub-item** (child records): appends never conflict, deletes become real tombstones, and it also removes the `ForEach`-identity problem. Rejected for v1 (new record type + ordering + relationship handling; contradicts the uniform-blob model), but it is the cleaner-than-CRDT next step.

---

## Decision 7: Store note and sub-items as two separate fields

**Date**: 2026-06-21
**Status**: accepted

### Context

The note and the sub-item list are logically independent pieces of content. They could share one Codable blob field on `TripPackingItem` or be two separate stored fields. CloudKit/`TripPackingItem` syncs with last-writer-wins at the **field** granularity (Decision 6).

### Decision

Store the note as its own `String?` field and the sub-item list as its own `Data?` field — not a single combined blob.

### Rationale

The note is naturally a scalar string (human-readable on the CKRecord, one translator line) and the sub-items a list blob; folding the note into the sub-items blob would needlessly bury it in JSON. Two fields is the cleaner representation at no cost.

**Correction (post design-phase review):** an earlier draft of this decision justified the split by claiming it gives *cross-field conflict independence* (a note-only edit wouldn't clobber a concurrent sub-item add). **That is false in this codebase.** `TripSyncEngine` has no field-level dirty tracking — every save rebuilds the entire `CKRecord` via `toRecord` and pushes all fields (verified in `TripSyncEngine.swift`). The whole record is one LWW conflict domain regardless of field count, so a note-only edit re-sends a then-current `subItemsData` and can overwrite a concurrent remote add. The two-field split is kept for representational cleanliness only; it provides **no** conflict-isolation benefit. Genuine note/sub-item independence would require separate *records* (child records), rejected for v1 (see Decision 6 escalation note).

### Alternatives Considered

- **Combined Codable struct (`{note, subItems}`) in one field**: Slightly fewer stored properties - rejected for burying the note in a blob; no conflict-domain difference either way (whole-record LWW).
- **Separate child records per sub-item**: would give real append-without-conflict + real tombstones - rejected for v1 (new record type, ordering, relationship handling; contradicts the uniform-blob model). Recorded as the escalation path.

### Consequences

**Positive:**
- Note is a readable scalar field; clean translator code.

**Negative:**
- No cross-field conflict isolation (whole-record LWW) — do not assume otherwise.
- Two stored properties + two translator fields instead of one.

---

## Decision 8: Explicit sub-item count cap of 50

**Date**: 2026-06-21
**Status**: accepted

### Context

Decision 5 set per-entry length caps but declined a cap on the *number* of sub-items, deferring to the 256 KB per-blob sync cap (`kRecordBlobSizeCap`). Review showed that cap is enforced only on the encode/send path — and `TripPackingItemRecordTranslator` has no cap check at all today — so an over-large list saves locally and only fails later, asynchronously, at sync upload, far from the inline editor. ~256 KB also allows ~1,300 entries, giving an unbounded row height.

### Decision

Cap a packing item at 50 sub-items. Adding past the cap is prevented inline at the point of entry.

### Rationale

A small, explicit cap makes the limit testable, bounds row height by design, and keeps the blob at tens of KB — far under 256 KB, which makes the blob-overflow path effectively unreachable and defuses the AC 6.4 failure-surfacing problem. 50 is a judgement call (well above any realistic "which toys" list), not a load-bearing constant.

### Alternatives Considered

- **No count cap (rely on blob size)**: Untestable ("the right number of entries"), produces a cliff-edge sync failure mid-packing, and leaves row height unbounded - rejected.

### Consequences

**Positive:**
- Predictable "list full" state instead of a late sync failure; bounded row height; one change defuses several findings.

**Negative:**
- 50 is arbitrary and may need tuning (cheap to change).

---

## Decision 9: Pre-save inline validation, not a sync-time failure alert

**Date**: 2026-06-21
**Status**: accepted

### Context

The original AC 6.4 said the system should "surface a save failure" when content exceeds the blob cap. But the packing-sheet state-mutation save path (`PackingSheet.save(_:)`) logs-and-swallows errors with no alert (`packing-sheet.md`: "No alert / banner in v1"), and the blob cap is only checked at sync-upload time. Honouring 6.4 literally would need new sync-time UI that contradicts the established pattern.

### Decision

Enforce length and count limits as a client-side guard **before** save (reject the input inline at the point of entry, like `PackingItemForm` does for the item name). Do not add a sync-time failure alert.

### Rationale

Validating at entry is consistent with the existing form's inline-error pattern, keeps the swallow-on-save behaviour of the packing sheet intact, and — combined with the count cap (Decision 8) — means the blob cap is never reached in practice. AC 6.4 was rewritten accordingly.

### Consequences

**Positive:**
- Consistent with existing input handling; no new sync-error UI; the over-limit path is caught where the user is typing.

**Negative:**
- The guard logic must live at every entry point (inline quick-add and, if used, the form).

---

## Decision 10: Note-clear must propagate as a clear across devices

**Date**: 2026-06-21
**Status**: accepted

### Context

`TripPackingItemRecordTranslator.from(_:)` follows the convention "absent key on the inbound record = no change" (it only assigns when the key resolves). For a brand-new field, *clearing* a note to nil/empty could be read by other devices as "no change" and lose to a stale non-empty value under LWW — a silent, confusing data issue. Surfaced as a new gap by external review.

### Decision

Clearing a note or sub-item list on one device propagates the cleared (empty) value to other devices, rather than being indistinguishable from "field unchanged". Round-trip tests cover nil / empty / non-empty.

### Rationale

A user who deletes a note expects it gone everywhere. The encode/decode contract for the new fields must distinguish "cleared" from "absent" so a clear survives sync. This is the same class of deliberate handling already applied to `countryCode` and `personSnapshotID`.

### Consequences

**Positive:**
- Deletes behave predictably across devices.

**Negative:**
- The translator needs explicit empty-vs-absent handling for the two new fields, with tests — slightly more than the default `if let` pattern.

---

## Decision 11: Sub-items as a Codable `Data?` blob, not a native list field

**Date**: 2026-06-21
**Status**: accepted

### Context

Sub-items (`[String]`) could be stored as a native SwiftData `[String]` (encoded as a CKRecord string-list field by the translator) or as a JSON-encoded `Data?` blob via the existing `CodableBridge`, like `Trip.attributesData` and `MasterPackingItem.conditionsData`.

### Decision

Store sub-items as `subItemsData: Data?`, exposed through a `subItems: [String]` `CodableBridge` extension. The note is a plain `String?`.

### Rationale

Matches the established blob-field convention, reuses `CodableBridge` and the `kRecordBlobSizeCap` check, and keeps one uniform field-encoding path in `TripPackingItemRecordTranslator`. The 50-item × 200-char caps bound the blob to ~10 KB, far under the 256 KB cap.

### Alternatives Considered

- **Native `[String]` / CKRecord string-list**: Slightly less code (no bridge) - rejected for diverging from the codebase's uniform blob pattern and its size-cap handling.

### Consequences

**Positive:** uniform with existing blob fields; one encoding path. **Negative:** a JSON encode/decode per read/write of the list (negligible at these sizes).

---

## Decision 12: Unconditional translator assignment (clear-propagation), per the `countryCode` precedent

**Date**: 2026-06-21
**Status**: accepted

### Context

Decision 10 requires note/sub-item clears to propagate across devices. `TripPackingItemRecordTranslator.from` currently uses conservative `if let` assignment for `personSnapshotID` ("absent = no change") to avoid clobbering from older clients, but `TripRecordTranslator` uses **unconditional** assignment for `countryCode` ("full snapshot ⇒ absent = cleared").

### Decision

Decode `note` and `subItemsData` with unconditional assignment (`item.note = record["note"] as? String`) so a cleared value reaches other devices. This is a deliberate divergence from the sibling fields `personSnapshotID`/`tripID` in the same translator, which use conservative `if let` ("absent = no change").

### Rationale

`CKSyncEngine` delivers full record snapshots, so an absent field genuinely means "cleared". Unconditional assignment is the only way to satisfy Req 6.5. The **in-file precedent** is `masterItemID`, already decoded unconditionally (nil-clears) in this same translator; `countryCode` in `TripRecordTranslator` is the cross-file precedent. `personSnapshotID`/`tripID` chose the conservative model to tolerate a dangling/omitted reference, which doesn't apply to user content that must clear. The trade-off — an older client that doesn't write these fields would clear them on its writes — is acceptable for a single-developer app whose devices update together, the same trade-off Phase 6 accepted for `countryCode`.

### Consequences

**Positive:** deletes propagate correctly. **Negative:** mixed-client-version coexistence on one shared trip could clear the fields; out of scope for v1.

---

## Decision 13: Note edited in `PackingItemForm`; sub-items added inline (resolves open points 1 & 2)

**Date**: 2026-06-21
**Status**: accepted

### Context

Open points from the requirements phase: where the note is edited, and how to avoid the inline add affordance cluttering long packing lists.

### Decision

The **note** is edited in the existing `PackingItemForm` (add a note field), reusing its rollback-on-save-failure path. **Sub-items** use an inline reveal-on-tap quick-add on the row: a compact "＋ add item" control that reveals a focused `TextField` on tap, appends on submit, stays open for rapid multi-add. Both note and sub-items display inline on the row (read).

### Rationale

Multiline note editing belongs in the form (which already handles name + save-failure UX); a sheet-on-sheet for sub-items would be too many taps for "add as you think of it". Reveal-on-tap keeps empty rows visually light (just a small control, no persistent field), addressing the density risk without losing one-tap add.

### Consequences

**Positive:** empty rows stay light; note gets a proper error path; sub-item add is one tap. **Negative:** the note is one extra step (open Edit) rather than inline.

### Note discoverability (post-review refinement)

The design-critic flagged that form-only note editing has no inline signal and no path on read-only rows. Resolution: an **existing** note renders inline and is tappable to open the edit form; the form now carries a labelled Note field, so the path is self-revealing once Edit is opened. A dedicated inline "add note" control for the empty case was rejected — a second per-row affordance fights the density this design protects. The rationale is therefore a deliberate density trade-off, not merely "notes are less frequent." Read-only rows display the note without an edit path, consistent with sub-items (Decision 4).

---

## Carried into implementation / still open

- **Edit-during-sync race**: behaviour when a remote record re-materialises the `@Model` mid sub-item add (local unsaved text vs incoming sync on the same device). Non-goal for guaranteed merge; the reveal-on-tap field's local `@State` text is independent of the model until submit, which bounds the exposure.
- **Migration constraint**: both new properties are Optional on the existing shared `TripPackingItem`, riding on `SchemaV3` — **no `SchemaV4`** (avoids the "Duplicate version checksums" crash; see `persistence.md`).
- **CKShare participant permissions**: v1 has no read-only participant tier ("interactive" means the `SheetGroup.isReadOnly`, not share permission), so no mapping is needed.
