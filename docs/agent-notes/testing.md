# Testing notes

## Xcode 26.5 — SwiftData multi-container crash in the test suite

**Symptom.** Running `make test-quick` (or `make test`, or any `xcodebuild test`
covering more than a handful of SwiftData suites) crashes mid-run with a cascade
of `0.000s` failures attributed to "Test crashed with signal trap" /
`Crash: Scramble at <SomeSwiftDataTest>`. ~80–100 tests pass first, then the
host process dies and every remaining test in that process reports as crashed;
xcodebuild retries on a fresh simulator clone and crashes again. The crash is an
`EXC_BREAKPOINT` (`SIGTRAP`) raised **inside SwiftData**, not an assertion
failure.

**Root cause.** Every SwiftData test suite builds its own in-memory container
with a freshly-derived schema:

```swift
let schema = Schema(versionedSchema: SchemaV3.self)   // re-derived per container
let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
return try ModelContainer(for: schema, configurations: [config])
```

Under the Xcode 26.5 toolchain, creating a **2nd+ `ModelContainer` for the same
`SchemaV3`** within a single test process traps. It is **not** caused by any
feature code — proven by:
- a pre-existing, untouched suite (`TripPackingItemBridgeTests`) crashing 0/N
  when run alone, and
- the same crash reproducing at the pre-feature baseline commit.

It surfaced with the Xcode 26.5 upgrade (June 2026); earlier toolchains
tolerated the repeated-container pattern.

**What still works.**
- `make build` — fine.
- `xcodebuild build-for-testing` — fine (both unit + UI targets compile).
- `make lint` / `make format` — fine.
- A **single** test in its own process (`-only-testing:Suite/func`) sometimes
  runs and reports; often the runner instead reports `0 tests` with scrambled
  output (`"Testing started"` printed after `** TEST SUCCEEDED **`). Either way
  it does not crash — but you cannot rely on it for a clean red/green signal.
- Reusing one shared `Schema` instance across containers avoided the crash in a
  minimal 8-container diagnostic, but **did not** fix a real multi-test suite —
  so schema-sharing is a clue, not the whole fix.

**Recovery that does NOT help:** `simctl shutdown all`, deleting
`~/Library/Developer/XCTestDevices` clones, restarting
`com.apple.CoreSimulator.CoreSimulatorService`, `simctl erase all`, device
reboot. A separate, worse "wedge" (stuck `launchd_sim` surviving `kill -9`) is
cleared by a **machine reboot**, but the reboot does **not** fix the
multi-container `SIGTRAP` above — that is a toolchain regression, not a wedged
service.

**Until it's fixed (proper fix is out of scope of any one feature — it's a
project-wide test-harness change):** verify SwiftData-touching work with
`make build` + `build-for-testing` + `make lint`, and treat a full-suite/whole-
suite crash as the toolchain, not a code failure. Do **not** burn time fighting
the simulator. A real fix likely means a shared test-support container/schema
factory used by every suite (and confirming it survives multi-suite runs).

**Operational caution:** do not run two `xcodebuild test` invocations against the
same simulator concurrently (parallel worktrees) — they race and can wedge
CoreSimulator. Also scope any `pkill` to Scramble (`pkill -f "xcodebuild.*Scramble"`),
not a blanket `pkill -f xcodebuild`, which will kill unrelated projects' test runs
on a shared machine.

See `persistence.md` for the SchemaV3 / no-SchemaV4 model rules.
