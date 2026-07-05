# Decision Log: Task Row Text Alignment

## Decision 1: No automated test for the alignment change

**Date**: 2026-06-29
**Status**: accepted

### Context

T-1619 vertically centres the task name with its checkbox in `TaskRow` by
adding `minHeight: 44` to the name `Text`'s frame. This is a pure layout-constant
change with no branching logic. The project tests view-driving logic, not view
bodies (see the Swift testing rules: "Test the logic that drives the view, not
the view body"), and has no snapshot/pixel-comparison test infrastructure.

### Decision

Ship the change without a dedicated automated test. Verify by building, passing
swiftlint / swift-format, and a manual visual check in the simulator that the
task name centres with the checkbox and matches `PackingItemRow`.

### Rationale

There is no unit-testable behaviour: the change is a single layout modifier.
A UI test cannot meaningfully assert sub-pixel vertical centring, and adding
snapshot-test tooling for a one-line cosmetic change is disproportionate. The
identical treatment already shipped untested for `PackingItemRow` in T-1587,
so this is consistent with the established precedent.

### Alternatives Considered

- **Add a snapshot test**: Would catch a future regression that drops the
  `minHeight` - Rejected because the project has no snapshot infrastructure and
  introducing it for one cosmetic line is out of proportion to the change.
- **Assert layout frame in a UI test**: Inspect the rendered row geometry -
  Rejected because XCUITest exposes element frames unreliably for this purpose
  and the assertion would be brittle against theme/Dynamic-Type variation.

### Consequences

**Positive:**
- Keeps the change minimal and consistent with the T-1587 packing-row precedent.
- No new test tooling or maintenance burden.

**Negative:**
- A future refactor could remove `minHeight: 44` without any failing test;
  regression would only surface on visual inspection.

---
