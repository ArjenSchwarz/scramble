# Implementation: Task Row Text Alignment

Ticket: T-1619. Commit: `0a98d89`.

## Beginner

**What changed:** In the trip timeline, each task is a row with a round checkbox
on the left and the task's name next to it. Before this change a short task name
sat a little higher than the centre of the checkbox, so they didn't look lined
up. We told the name to be at least as tall as the checkbox's tap area (44
points), which makes a one-line name sit level with the checkbox.

**Why it matters:** It's a small visual tidy-up so the task list matches the
packing list, which already had this fix.

**Key concept:** In SwiftUI a row lays its items out from the top. The checkbox
is centred inside a 44pt box, so to line the text up we give the text box the
same 44pt minimum height — now both boxes are the same height and their centres
meet.

## Intermediate

The task name `Text` in `TaskRow` lives in an `HStack(alignment: .top)`
alongside the `checkbox`. The checkbox glyph is a 24pt circle centred inside a
`.frame(width: 44, height: 44)` tap target. The name previously had only
`.frame(maxWidth: .infinity, alignment: .leading)`, so within a top-aligned
HStack a single-line name (~20pt tall) hugged the top while the checkbox's
visual centre sat ~10pt lower.

Adding `minHeight: 44` to the name's frame makes its box the same height as the
checkbox's box. Two equal-height, top-aligned boxes share a vertical centre, so
the single-line name now renders level with the checkbox circle. Taller content
(multi-line names, large Dynamic Type) grows past 44pt and the `minHeight`
becomes a no-op, falling back to top-alignment — identical to `PackingItemRow`.

This is the same fix `PackingItemRow.nameColumn` received in T-1587; the task
row simply hadn't had it applied yet.

## Expert

The alignment is purely a function of box geometry under `HStack(alignment:
.top)`: equalising the intrinsic-or-minimum heights of two top-aligned siblings
co-locates their centres. No alignment guide, custom `Layout`, or
`alignmentGuide(_:)` is needed — `minHeight` is the minimal lever.

The `minHeight` is applied to the inner `Text(task.name)` rather than the
enclosing `VStack` that also holds the conditional `WhyDisclosureView`. This is
deliberate: sizing the `Text`'s own box leaves the disclosure (a separate
`VStack` child laid out beneath) unaffected, so opening the disclosure does not
shift the name. Placing `minHeight` on the `VStack` would have stretched the
whole column and changed disclosure spacing.

Edge cases:
- **Multi-line / large Dynamic Type:** `minHeight` is dominated by intrinsic
  height; layout reverts to top-alignment. Matches `PackingItemRow`, so the two
  surfaces stay visually consistent at every type size.
- **Tap target:** unchanged — the row already has its own `.frame(minHeight:
  44)` (the name's `minHeight` is about visual centring, not hit area).
- **Strikethrough/opacity for completed/ghosted rows:** untouched; this only
  affects the name box's height.

## Completeness Assessment

- **Fully implemented:** Single-line task name vertically centred with the
  checkbox (smolspec Req 1); alignment behaviour matches `PackingItemRow` at all
  type sizes (Req 2); `WhyDisclosure`, assignee avatar, and tap targets
  unchanged (Req 3). Verified by `make build`, `make test-quick`, `make lint`,
  `make format` — all green — and code inspection against the proven
  `PackingItemRow` pattern.
- **Partially implemented:** None.
- **Missing / deferred:** Manual visual confirmation in the running app (tasks.md
  task 3) is intentionally deferred to the author. There is no automated
  alignment test by design — see `decision_log.md` Decision 1.
