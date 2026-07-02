# Testing notes

## The unit suite's "flaky crash" was non-retained `ModelContainer`s (NOT a toolchain bug)

**Symptom.** Running `make test-quick` (or `make test`) intermittently crashed
mid-run: ~80–100 tests passed, then the test host died with an
`EXC_BREAKPOINT` (`SIGTRAP`) raised inside SwiftData, every remaining test in
that process reported as a `0.000s` "crash," and xcodebuild relaunched on a
fresh simulator clone and often crashed again. Which test "crashed" differed
run to run, so it read as flaky.

**Root cause (confirmed June 2026 via crash reports).** Several test helpers
built a SwiftData `ModelContainer` as a local, derived a `ModelContext` (and
sometimes `@Model` objects) from it, and returned only the context — not the
container:

```swift
// BUG: container is a temporary; nothing the caller holds retains it.
private static func makeContext() throws -> ModelContext {
  let schema = Schema(versionedSchema: SchemaV3.self)
  let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
  return try ModelContainer(for: schema, configurations: [config]).mainContext
}
```

A `ModelContext` does **not** keep its `ModelContainer` alive. The container
deallocates when the helper returns; the next model access/mutation through the
orphaned context traps inside SwiftData (`_assertionFailure` → `SIGTRAP`). It
manifests as "flaky" because ARC dealloc timing is non-deterministic — under
simulator load it sometimes collects the container mid-test, sometimes not, and
a different orphaned suite loses the race each run.

The earlier theory in this note — "Xcode 26.5 multi-container toolchain bug" —
was **wrong**. The crash reports
(`~/Library/Logs/DiagnosticReports/Scramble-*.ips`) show a use-after-dealloc
from a model setter called directly from the test, e.g.:

```
libswiftCore  _assertionFailure
SwiftData     …
Scramble      TripPackingItem.note.setter        ← mutate through orphaned context
ScrambleTests RulesEngineRunnerTests.deletingItemRemovesNoteAndSubItems()
```

The note's own "evidence" for a toolchain bug (e.g. `TripPackingItemBridgeTests`
crashing 0/N when run alone) was just that suite's own non-retained helper.
Repeated multi-container creation is **not** the problem — creating many
in-memory containers is fine; only dropping one while its context is still in
use is fatal.

**How to diagnose.** Run the suite, then read the newest
`~/Library/Logs/DiagnosticReports/Scramble-*.ips`. Parse the faulting thread:
`SIGTRAP` + `SwiftData` + `_assertionFailure` + a frame in the test that mutates
a model = a non-retained container. Different `.ips` files naming different
tests across one run confirms the non-determinism.

**The fix / the rule.** Every helper that vends a `ModelContext` or `@Model`
must keep the container alive for as long as the caller uses it:

- Helper returns a struct → add a `container: ModelContainer` field (it never
  needs to be read; it exists to retain).
- Helper returns a bare context → return the `ModelContainer` instead and let
  the caller derive `container.mainContext` / `ModelContext(container)`.
- Helper used inside one test body → bind `let container = …; let context =
  container.mainContext` (already-scoped is fine).

This is the same rule as `rules/language-rules/swift.md` → "Retain the
ModelContainer in tests — never use a temporary." Fixed across all seven
affected suites (`NotificationsServiceTests`, `RulesEngineRunnerTests`,
`PackingItemContentBridgeTests`, `TripPackingItemBridgeTests`,
`PackingItemRowAccessibilityTests`, `TaskRowAccessibilityTests`,
`WhyResolverParticipantHideTests`); the earlier T-1605 commit (`d663be1`) had
fixed the same pattern in two category suites but missed the rest. Verified by a
full clean run (single host PID, zero `0.000s` crashes) plus repeated runs of
the SwiftData-heavy suites.

## A second, independent flake: async-cancellation race in `TripSyncEventBus`

Once the crash was fixed and the suite ran to completion,
`TripSyncEventBusTests.stopCancelsIteration()` showed up as genuinely flaky
(passed one run, failed the next). `start()` spawns a `@MainActor` iteration
task; the test calls `start()` then `stop()` (which cancels it) with no
suspension between, so the task only runs when the test next awaits — by which
point an event has already been yielded into the `AsyncStream` buffer. Whether a
cancelled `for await` delivers that buffered element before observing
cancellation is timing-dependent. Fix was in production
(`TripSyncEventBus.start`): check `Task.isCancelled` at the top of the loop
before dispatching, so a stopped bus deterministically never dispatches —
honouring `stop()`'s documented contract.

Lesson: tests that assert the **absence** of an effect after a fixed
`Task.sleep` are inherently racy (you can't poll for "nothing happened"). The
other `TripSyncEventBus` tests use a `waitFor`-style condition poll, which is the
robust pattern for asserting presence.

## Operational cautions (still valid)

- Simulator tests run **serially** (`-parallel-testing-worker-count 1`);
  parallel simulator clones race on launch and produce different flakes. Don't
  change this.
- Do not run two `xcodebuild test` invocations against the same simulator
  concurrently (e.g. parallel worktrees) — they race and can wedge
  CoreSimulator.
- Scope any `pkill` to Scramble (`pkill -f "xcodebuild.*Scramble"`), never a
  blanket `pkill -f xcodebuild`, which kills unrelated projects' runs.
- There are two simulators named "iPhone 17 Pro"; `name=`-based destinations are
  ambiguous but resolve deterministically in practice — prefer a UDID if a run
  ever picks the wrong one.

See `persistence.md` for the SchemaV3 / no-SchemaV4 model rules.
