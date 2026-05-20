# Design: Phase 6 — Notifications + Polish

## Overview

Two largely independent workstreams ship in one phase. The notifications workstream adds a `NotificationsService` actor that owns all `UNUserNotificationCenter` interactions and reconciles pending requests against the current set of trips on every relevant trigger. The polish workstream extends the existing inline-SwiftUI patterns for transitions, haptics, VoiceOver, and Dynamic Type without introducing new components, plus a `SchemaV4` lightweight migration that adds `Trip.countryCode`.

## Architecture

### Notifications subsystem — placement and data flow

New files under `Scramble/Scramble/Notifications/` (new directory):

- `NotificationsService.swift` — `@MainActor` final class holding the single `UNUserNotificationCenter` reference and the in-flight reconcile task.
- `NotificationPlanner.swift` — pure (testable) functions: trip-set → expected `[ActivationPlan]` with 60-cap + tie-break + body text applied.
- `NotificationReconciler.swift` — diffs expected vs. `pendingNotificationRequests()`, computes add/remove sets.
- `NotificationRouter.swift` — `UNUserNotificationCenterDelegate` implementation; holds the cold-launch deep-link slot.
- `NotificationIdentifier.swift` — `enum` with the identifier scheme and parser.
- `PendingChangeBroadcaster.swift` — multicast wrapper over `PendingChangeNotifier` (see below).

The service is owned by `ScrambleApp` and injected via the existing `AppDelegate.Environment` slot (extended), so test harnesses can replace it.

```
ScenePhase → .active ─┐
Trip save closures ───┤
Trip delete path ─────┼──► NotificationsService.requestReschedule(reason:)
Auth state flip ──────┤            │     (single global coalesce task; flush carve-outs)
LocalWriteHook ───────┘            ▼
   ↓ via                      NotificationPlanner.plan(trips, tasks, now, calendar, cap) → [ActivationPlan]
PendingChangeBroadcaster              │
                              NotificationReconciler.diff(plan, pending) → (add, remove)
                                      │
                              UNUserNotificationCenter.add / removePendingNotificationRequests
```

Trigger sources and the reason they carry:

| Source | Reason | Flush behaviour |
|---|---|---|
| `ScenePhase` → `.active` (launch or foregrounded) | `.appActivation` | Immediate (flushes any pending coalesce) |
| `ScenePhase` → `.background` | `.scenePhaseBackground` | Immediate (flushes any pending coalesce so the OS doesn't suspend a stale reconcile) |
| `TripDeletion.delete` invocation | `.tripDeleted(tripID)` | Immediate (cancellations cannot wait) |
| Authorization status flip on foreground re-read | `.authChanged(newStatus)` | Immediate |
| `PendingChangeBroadcaster` callback (every `LocalWriteHook.commit`) | `.localWrite` | 2s coalesce |

> **Implementation note:** A `.tripSaved(tripID, wasInsert)` case was sketched
> in this design table for the trip-editor save path, but the broadcaster
> wiring made it redundant — every save funnels through `LocalWriteHook.commit`
> which already fires `.localWrite`. The case was dropped from `ReschedReason`
> during PR review iteration 4.

#### Why the broadcaster rather than `TripSyncEventBus`

`TripSyncEventBus` is documented as a fixed two-slot router with `assertionFailure` on a third subscriber (see `TripSyncEventBus.swift` lines 35–39). The bus is not extensible without changing Phase 5.1 contracts. Instead, Phase 6 introduces a `PendingChangeBroadcaster` that conforms to the existing `PendingChangeNotifier` protocol (`LocalWriteHook.swift:229`) and forwards every call to N children. `ScrambleApp.init` wires:

```swift
let broadcaster = PendingChangeBroadcaster(children: [tripSyncEngine, notificationsService])
let writeHook = LocalWriteHook(notifier: broadcaster)
```

`NotificationsService` conforms to `PendingChangeNotifier` and treats every `notifyPendingChanges(savedRecordIDs:deletedRecordIDs:in:)` call as a `.localWrite` reschedule trigger. The service does not inspect record IDs — it always runs a full reconcile. This trades some redundant reconciler work (packing-item edits that don't affect notifications still trigger a reconcile) for not having to classify writes per record type; the reconciler is cheap and the coalesce window absorbs bursts.

Remote-change application via `CKSyncEngine` ultimately writes through `tripsLocal.save()` calls inside the engine's event handlers. Those engine-internal saves don't go through `LocalWriteHook.commit` (they would create an upload loop), so the broadcaster doesn't fire for remote changes. The `.appActivation` reconcile on next foreground is the recovery path — adequate because cross-device task-count drift surfaces on next app open, which is when notifications matter.

#### Coalesce mechanics

A single global `Task<Void, Never>?` field on the service holds the pending coalesce. `requestReschedule` with a non-immediate reason:

1. Cancels the existing pending task (if any).
2. Starts a new task: `try? await Task.sleep(for: .seconds(2)); await runReconcile()`.

`requestReschedule` with an immediate-flush reason:

1. Cancels the existing pending task.
2. Synchronously awaits `runReconcile()` (the call site is already async or wraps in `Task { @MainActor in ... }`).

Cancellation of a sleeping `Task` returns from the sleep with a cancellation error which the `try?` swallows; no reconcile runs from the cancelled task. The next trigger creates a fresh task. There is no per-`tripID` bookkeeping because the reconciler is full-fleet.

### Authorization wiring

`TripEditorView` has a single closure `onSave: (TripDraft) -> Bool` (`Features/Trips/TripEditorView.swift:20`). Two parents own a concrete `onSave` block:

| Parent | Call site | Save semantics |
|---|---|---|
| `TripListView` | `Features/Trips/TripListView.swift:99` (`TripEditorView(mode: .create) { draft in ... }`) | Insert a new `Trip`, route through `LocalWriteHook.commit`. After the commit, call `notificationsService.requestAuthorizationIfNeeded(forTrip: trip)`. |
| `TripDetailView` | `Features/Trips/TripDetailView.swift:180` (`TripEditorView(mode: .edit(trip), ...) { draft in ... }`) | Edit existing `Trip`, route through `LocalWriteHook.commit`. After the commit, the broadcaster path already triggers a `.localWrite` coalesced reconcile; no explicit auth call is needed (auth is only requested on insert). |

Eligibility is computed inside `requestAuthorizationIfNeeded`:

```swift
@MainActor
func requestAuthorizationIfNeeded(forTrip trip: Trip) async {
  guard await center.notificationSettings().authorizationStatus == .notDetermined else { return }
  let plans = NotificationPlanner.plan(
    trips: [trip], tripTasksByTripID: [:], now: now(), calendar: calendar, cap: 60
  )
  guard !plans.isEmpty else { return }
  let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
  if granted { await runReconcile() }
}
```

The eligibility gate is "would produce at least one plan" — same predicate as the reconciler, so insert + edit + create-trip-during-current-phase all behave consistently. The save closure does not `await` this call's outcome; UI feedback for a denied prompt comes from the same Settings affordance described in Req 3.5, surfaced via an observable `authStatus` property on the service (see Components).

`ScenePhase` observation lands at `ScrambleApp.body`'s `WindowGroup` root. `@Environment(\.scenePhase)` already exists for transition resets in `RootView`; Phase 6 adds a sibling observer at the `WindowGroup` level so the service receives both `.active` and `.background` transitions without depending on a specific child view being on screen. The service compares the new authorization status against its last-seen value and dispatches: `.denied → .authorized` runs a reconcile (backfill, Decision 10); `.authorized → .denied` cancels all.

### Deep-link routing and modal sheet dismissal

`NotificationRouter` is the single `UNUserNotificationCenterDelegate` and is `@Observable` (iOS 26 convention; works on `NSObject` subclasses). It is installed by extending `AppDelegate.Environment` with a `notificationRouter: NotificationRouter` field and calling `UNUserNotificationCenter.current().delegate = router` inside `ScrambleApp.init` — same pattern as `RemoteNotificationRouter` already uses.

The router holds one piece of state: `private(set) var pendingRoute: ActivationRoute?`. Two callers fill it:

1. `userNotificationCenter(_:didReceive:)` — taps received while the app is running and the cold-launch tap (iOS calls `didReceive` once the delegate is installed, including for taps that woke the app from terminated state).
2. `onOpenURL(_:)` in `ScrambleApp` — the debug URL path; parses `scramble://trip/<id>?phase=<raw>` and writes the same `ActivationRoute`. Production routing does not depend on URL parsing (Decision 9).

The 1-slot queue from Req 5.2 is `pendingRoute` itself — a later tap overwrites an earlier unprocessed one. The cold-launch sequencing works because `UNUserNotificationCenter` buffers the tap event until a delegate is installed; `ScrambleApp.init` sets the delegate synchronously, before any view appears.

#### Consumer state machine

`RootView` observes `pendingRoute` via `onChange(of:)`. On a non-nil value it transitions through:

```
.idle ──pendingRoute set──► .dismissingSheets ──all sheets closed──► .navigating ──nav complete──► .idle
```

`.dismissingSheets` sets every known sheet binding to `false`/`nil` (`pendingForm`, `pendingEditAttribute`, packing-sheet item, sharing-controller binding, and the new country-code editor binding if presented) and calls `dismiss(animated: false)` on the `SharingControllerHost`'s `UIViewController`. Non-animated dismissal is intentional — the user's notification tap is an explicit "go elsewhere" signal; animated dismissal fights the navigation push. With `animated: false`, the SwiftUI sheet bindings flip in the same render cycle and the `UIViewController` dismisses on the next runloop turn.

`.navigating` is entered via `Task { @MainActor in await Task.yield(); ... }` — a single yield is enough because every sheet dismissal we trigger is non-animated and resolves within one runloop iteration. The yield then performs the `Trip` lookup against the `tripsLocal` container (C5), updates the navigation path, sets `expandedPhase`, and clears `pendingRoute`. If the lookup fails, the state machine returns to `.idle` without changing navigation (Req 5.4).

`pendingRoute` is cleared by the router via `consumeRoute() -> ActivationRoute?` (atomic read+clear); the consumer calls this exactly once per route, at the start of `.navigating`.

The route machine is hosted as a `@State private var routingState: RoutingState` on `RootView` and observed by the same view's `.sheet`/`.fullScreenCover` bindings. There is no new global state; the `NotificationRouter` only owns the inbound queue.

### Polish workstream — placement

Polish is local edits to existing components, no new directories:

- Transitions: `withAnimation` blocks in `AccordionTimeline.toggle(_:)`, `TaskRow.toggle()`, and `PackingItemRow.toggle()`. A new helper `Animation.scrambleStandard(reduceMotion: Bool)` in a new file `Scramble/Scramble/Theme/Animations.swift` returns the right curve+duration constants.
- Haptics: `sensoryFeedback(.impact(weight:))` modifiers attached to the same `Button`s / `onTapGesture`s that already invoke the action closures. No new haptic generator file — the SwiftUI iOS 17+ modifier is sufficient.
- VoiceOver: extend inline `.accessibilityLabel(_:)` / `.accessibilityValue(_:)` on `PhaseRow`, `TaskRow`, `PackingItemRow`, and the per-person progress bar; add `.accessibilityAction(named:)` for "Why is this here?" with the same gating as the existing long-press exposure.
- Dynamic Type: layout audits in existing views; `Layout` containers (`Grid`, `ViewThatFits`, `HStack` → `VStack` swap with `@ScaledMetric` thresholds) where needed.

### Country flag — SchemaV4, translator update, and Trip Editor field

`SchemaV4` is a lightweight migration: clone `SchemaV3`'s `versionedSchema` enum's `models` list, add `countryCode: String?` (default `nil`) on `Trip`. Extend `ModelStore.makeContainers` to register the V3→V4 stage as `MigrationStage.lightweight(fromVersion: SchemaV3.self, toVersion: SchemaV4.self)`. Both the `tripsLocal` and `globals` containers register the same schema, so both run through the V3→V4 migration; only `tripsLocal` has `Trip` rows to migrate, but the `globals` container's schema still updates so the `Trip` model type stays consistent across containers. The Phase-5.1 `globals` container is CloudKit-backed, but the additive optional field is safe under CloudKit's lightweight-migration semantics (nullable additive columns do not push a CKRecord schema change).

`TripRecordTranslator` (`Sharing/Translators/TripRecordTranslator.swift`) is hand-written explicit-field encode/decode — not key-path driven. Adding `countryCode` requires two edits to the translator:

```swift
// In toRecord(_:in:existing:)
record["countryCode"] = trip.countryCode as CKRecordValue?

// In from(_:into:)
if let value = record["countryCode"] as? String { trip.countryCode = value }
```

The encode is `as CKRecordValue?` rather than `as CKRecordValue` because `nil` must overwrite a previously-set value when a user clears the country code; assigning `CKRecordValue?(nil)` to a `CKRecord` field deletes the field. The decode treats a missing field as "leave existing value alone", matching the existing pattern for `name`/`startDate`/`endDate`.

A translator unit test in `ScrambleTests/TripRecordTranslatorTests.swift` covers round-tripping `countryCode` through `toRecord` and back via `from(_:into:)` for set, unset, and toggle (set → unset → set) cases.

A pure helper `func flagEmoji(for code: String) -> String?` in a new file `Scramble/Scramble/Theme/CountryFlag.swift` derives the emoji via the regional-indicator scalar arithmetic (`U+1F1E6 + (letter - 'A')` for each of the two letters). Returns `nil` if the code is not exactly two ASCII letters.

`TripEditorView` gains a single text field labelled "Country code" with `.textInputAutocapitalization(.characters)` and a 2-character limit applied in `onChange`. Validation: trims, uppercases, accepts empty (clears `countryCode`) or exactly two letters; rejects anything else by reverting to the previously-valid value. The text field appears live-preview-style: as soon as a valid two-letter code is entered, the flag emoji renders next to the field. This is the minimum UI that satisfies Req 6.5 without becoming a country picker.

### Pattern extension audit — `PendingChangeNotifier` consumers

`LocalWriteHook(notifier:)` accepts a single `PendingChangeNotifier`. Today's only production consumer is `TripSyncEngine`. Phase 6 introduces a second consumer (`NotificationsService`) via `PendingChangeBroadcaster`. Call sites to audit:

| Call site | File:Line | Needs change for Phase 6? | Why |
|---|---|---|---|
| Production `LocalWriteHook` construction | `ScrambleApp.swift:~190` (today binds `TripSyncEngine` directly) | Yes — wrap with `PendingChangeBroadcaster(children: [engine, notificationsService])` | Multicast to both engine and notifications |
| Fallback notifier (no-op for previews / SwiftUI canvas) | `Persistence/LocalWriteHookEnvironmentKey.swift:47` (`FallbackPendingChangeNotifier`) | No | Already a no-op; broadcaster path only runs in `ScrambleApp.init`-wired contexts |
| Test target injection | `ScrambleTests/...` (existing recording fake) | No new injection point | Tests can wrap with their own broadcaster if needed |

### Pattern extension audit — `TripRecordTranslator` field list

`TripRecordTranslator` uses hand-written `record["name"] = ...` and `if let name = record["name"] as? String { ... }` — not key-path enumeration. Audit of fields added or changed by Phase 6:

| Field | Encode in `toRecord` | Decode in `from(_:into:)` | Tested |
|---|---|---|---|
| `countryCode: String?` | Add: `record["countryCode"] = trip.countryCode as CKRecordValue?` | Add: `if let value = record["countryCode"] as? String { trip.countryCode = value }` | Yes — `TripRecordTranslatorTests` round-trip cases |

No other translators need changes — `TripTask`, `TripPackingItem`, and `TripPersonSnapshot` are unchanged.

### Pattern extension audit — `WhyDisclosure` exposure

The existing `WhyResolver.reason(for:context:hideOnUnresolvedMaster:)` returns `nil` for items that have no rule justification (manual one-offs, items whose master was deleted under certain conditions). The `WhyDisclosure` long-press in `TaskRow` and `PackingItemRow` is gated on this `nil` check (`if resolvedReason != nil`).

For Req 9.5, the accessibility custom action must use the same gate. Call sites for the action:

| Row type | File:Line | Gate |
|---|---|---|
| `TaskRow` | `Components/TaskRow.swift` ~94 | reuse `resolvedReason != nil` |
| `PackingItemRow` (pack mode) | `Components/PackingItemRow.swift` action accessor | reuse `resolvedReason != nil` |
| `PackingItemRow` (repack: still-in-suitcase, back-in-suitcase) | same | reuse `resolvedReason != nil` |
| `PackingItemRow` (repack: Left Behind) | same | gate is the same; Left Behind has no special path |
| `PackingItemRow` (excluded / not bringing) | same | gate is the same |

No additional call sites — the polish change is a single accessibility-action modifier wrapped around the same gate as the existing long-press, applied in two row components.

## Components and Interfaces

```swift
// Notifications/NotificationsService.swift
@MainActor
@Observable
final class NotificationsService: NSObject, PendingChangeNotifier {
  // PendingChangeNotifier conformance — broadcaster forwards every commit here.
  func notifyPendingChanges(
    savedRecordIDs: [CKRecord.ID],
    deletedRecordIDs: [CKRecord.ID],
    in zoneID: CKRecordZone.ID
  )

  init(
    center: NotificationCenterProtocol = UNUserNotificationCenter.current(),
    router: NotificationRouter,
    tripContext: () -> ModelContext,           // Returns tripsLocal context on demand.
    calendar: Calendar = .autoupdatingCurrent,
    now: @escaping () -> Date = Date.init,
    coalesceWindow: Duration = .seconds(2)
  )

  /// Observable, surfaced to UI for the "Settings" affordance from Req 3.5.
  private(set) var authStatus: UNAuthorizationStatus = .notDetermined

  func start() async                            // Reads initial authStatus, sets delegate.
  func requestAuthorizationIfNeeded(forTrip: Trip) async
  func handleScenePhase(previous: ScenePhase?, current: ScenePhase) async
  func requestReschedule(reason: ReschedReason)  // Entry for all triggers.

  enum ReschedReason: Hashable {
    case appActivation                          // Immediate flush
    case scenePhaseBackground                   // Immediate flush
    case tripDeleted(tripID: UUID)              // Immediate flush
    case authChanged(UNAuthorizationStatus)     // Immediate flush
    case localWrite                             // 2s coalesce
    // The `.tripSaved` case sketched here was dropped during PR review
    // iteration 4 — every save funnels through `LocalWriteHook.commit`
    // which fires `.localWrite`, so the separate case was redundant.
  }
}

// Notifications/NotificationCenterProtocol.swift
@MainActor
protocol NotificationCenterProtocol {
  func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
  func notificationSettings() async -> UNNotificationSettings
  func add(_ request: UNNotificationRequest) async throws
  func pendingNotificationRequests() async -> [UNNotificationRequest]
  func removePendingNotificationRequests(withIdentifiers: [String])
  func removeDeliveredNotifications(withIdentifiers: [String])
  func setDelegate(_ delegate: UNUserNotificationCenterDelegate?)
}
// `UNUserNotificationCenter` gains a small extension marking conformance;
// methods bridge to the concrete `UNUserNotificationCenter` API.

// Notifications/PendingChangeBroadcaster.swift
@MainActor
final class PendingChangeBroadcaster: PendingChangeNotifier {
  init(children: [PendingChangeNotifier])
  func add(_ child: PendingChangeNotifier)
  // Forwards `notifyPendingChanges(...)` to every child in registration order.
  // Errors / throws from a child are caught and logged so one child's
  // failure does not block others. Children are weakly held to avoid
  // retain cycles with the engine.
}

// Notifications/NotificationPlanner.swift
struct ActivationPlan: Equatable {
  let tripID: UUID
  let phase: Phase
  /// Components carry an explicit `calendar` and `timeZone` so the
  /// resulting `UNCalendarNotificationTrigger` resolves predictably.
  let fireDateComponents: DateComponents
  let outstandingTaskCount: Int
  /// Rendered notification body. Captured at plan time so the reconciler
  /// can no-op when the existing pending request's body matches.
  let body: String
  /// Title rendered in the notification banner; always the trip name.
  let title: String
}

enum NotificationPlanner {
  static func plan(
    trips: [Trip],
    tripTasksByTripID: [UUID: [TripTask]],
    now: Date,
    calendar: Calendar,
    cap: Int = 60
  ) -> [ActivationPlan]
  // - Skips weeksBefore, afterTrip, compressed duringTrip (Req 1.4)
  // - Skips phases whose calendar-day activation is on or before now's calendar day (Req 1.5)
  // - Returns up to `cap` plans sorted by fire date ascending,
  //   tie-break by Trip.startDate then Trip.id (Req 2.2).
  // - Body strings rendered per Req 1.2 by an internal pure helper.

  static func body(tripName: String, phase: Phase, outstandingTasks: Int) -> String
  // Exposed for the reconciler to compare against `request.content.body`
  // without re-doing the full plan call.
}

// Notifications/NotificationReconciler.swift
enum NotificationReconciler {
  struct Diff { let toAdd: [ActivationPlan]; let toRemove: [String /* identifier */] }
  /// Computes (add, remove) from the planner's output and the live
  /// pending list. A pending request whose identifier is in the plan AND
  /// whose body matches the plan's `body` is treated as already-correct
  /// and excluded from both sets (no-op).
  static func diff(plan: [ActivationPlan], pending: [UNNotificationRequest]) -> Diff
}

// Notifications/NotificationIdentifier.swift
enum NotificationIdentifier {
  static func make(tripID: UUID, phase: Phase) -> String  // "scramble.activation.<UUID>.<rawValue>"
  static func parse(_ raw: String) -> (tripID: UUID, phase: Phase)?
  static func threadID(for tripID: UUID) -> String        // "scramble.trip.<UUID>"
}

// Notifications/NotificationRouter.swift
@MainActor
@Observable
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate {
  private(set) var pendingRoute: ActivationRoute?
  func consumeRoute() -> ActivationRoute?       // Atomically reads + clears.

  // userNotificationCenter(_:didReceive:withCompletionHandler:) extracts
  // tripID + phase from userInfo and writes pendingRoute on @MainActor.
  // userNotificationCenter(_:willPresent:withCompletionHandler:) returns
  // [.banner, .sound] so foreground delivery is visible (Req 1.3).
  // Both delegate methods use the iOS 26 `async` variants.
}

struct ActivationRoute: Equatable {
  let tripID: UUID
  let phase: Phase
}

// Theme/Animations.swift
extension Animation {
  /// Reads `@Environment(\.accessibilityReduceMotion)` via a small helper
  /// view modifier; callers don't pass the flag explicitly.
  static let scrambleStandard: Animation                  // ease-in-out, fixed duration constant.
}

// Theme/CountryFlag.swift
enum CountryFlag {
  static func emoji(for code: String?) -> String?
}
```

### Behavioural notes that are not obvious from the signatures

- `NotificationsService.requestReschedule` is **non-blocking** for coalesced reasons. Immediate-flush reasons run synchronously inside the calling task on `@MainActor`. Callers awaiting tight ordering should pass an immediate reason.
- `NotificationPlanner.plan` is pure and synchronous. The body string is captured at plan time; the public `body(tripName:phase:outstandingTasks:)` helper is the same function the planner uses internally, exposed for the reconciler's no-op detection.
- `NotificationReconciler.diff` is order-stable: items in `toRemove` are returned in `pending`'s order, items in `toAdd` are returned in `plan`'s order.
- `NotificationRouter.pendingRoute` may be set from either the delegate callback or `onOpenURL`. Both paths run on `@MainActor`; the delegate method asserts main-thread.
- `PendingChangeBroadcaster.notifyPendingChanges` is called on every successful `LocalWriteHook.commit`, including writes the broadcaster's children may not care about. `NotificationsService` treats any call as a `.localWrite` reschedule trigger.

## Data Models

### `SchemaV4` — additive

```swift
// Models/Schema.swift  (extended)
enum SchemaV4: VersionedSchema {
  static var versionIdentifier = Schema.Version(4, 0, 0)
  static var models: [any PersistentModel.Type] = [
    Trip.self, Person.self, MasterTaskItem.self, MasterPackingItem.self,
    TripTask.self, TripPackingItem.self, TripPersonSnapshot.self,
    TripZoneState.self, MigrationJournalEntry.self,
  ]
}
```

`Trip` gains:

```swift
var countryCode: String?    // ISO 3166-1 alpha-2 uppercase, or nil
```

`countryCode` is plain `String?` — no separate Codable struct, no nested `Trip.attributes` redirect. Storing on `Trip` directly (not on `TripAttributes.values`) is deliberate: the field is presentation metadata, not a rules-engine input, and putting it on `TripAttributes` would distort the engine's per-attribute multiset contract for an unrelated feature (per Decision 5).

`MigrationPlan` extension (registered for both containers in `ModelStore.makeContainers`):

```swift
MigrationStage.lightweight(
  fromVersion: SchemaV3.self,
  toVersion: SchemaV4.self
)
```

`MigrationJournalEntry` is unchanged; the V3→V4 lightweight stage runs entirely inside SwiftData with no journal involvement. The `globals` container runs the stage but has no `Trip` rows in production (Phase 5.1 moved them all to `tripsLocal`), so the data effect on `globals` is zero. The translator change in the Country flag section above is what actually carries `countryCode` across CKShare zones.

## Error Handling

| Failure | Handling |
|---|---|
| `UNUserNotificationCenter.add` throws | Logged via existing `os_log` channel; no retry inside the same reconcile pass. The next reconcile pass (next `ScenePhase` → active or next sync event) re-attempts. |
| `requestAuthorization` throws (offline, system error) | Treated as `notDetermined` for this session; no notifications scheduled. Re-attempted on the next eligible trip save. |
| Deep link with malformed `userInfo` (missing keys, non-UUID `tripID`, non-matching `phase` rawValue) | Drop silently; log at `.debug`. Navigation state unchanged. |
| Deep link names a deleted trip (Req 5.4) | Drop silently; log at `.info`. The router's `pendingRoute` is cleared by the consumer regardless. |
| `SchemaV4` lightweight migration fails | Existing failure path: `ModelContainer` initialization throws; the `MigrationGate` already in `ScrambleApp` surfaces this as a startup error. No new code path. |
| `countryCode` set to invalid value via direct CloudKit sync from a future schema | The field is `String?` with no DB-level validation; `CountryFlag.emoji(for:)` returns `nil` for non-conforming values, the header renders unchanged. No crash, no exception. |
| Foreground delivery while a sheet is presented | Treated like any other foreground delivery — `willPresent` returns `.banner + .sound`. Sheet remains visible behind the banner; tapping the banner runs the standard tap path (Req 5.3 dismisses the sheet then navigates). |

## Testing Strategy

### Unit tests — `NotificationPlanner`

Pure functions. Property-style table-driven tests in `ScrambleTests/NotificationPlannerTests.swift`:

- Trip with all 7 phases produces exactly 4 plans (excluded: weeksBefore, afterTrip, compressed duringTrip if applicable).
- 1-day trip (`startDate == endDate`) skips `.duringTrip` (compressed) — 3 plans.
- Phase whose activation date equals `now`'s calendar day is skipped (Req 1.5 / C2 boundary).
- Tie-breaking: two trips with same start date produce stable order by `Trip.id`.
- 60-cap: 13-trip × 5-phase fixture (65 plans) clamps to 60; the 5 dropped are the ones with latest fire dates.

PBT candidate (Swift Testing `@Test`): "given any set of trips and any `now`, no returned plan has a fire-date components that, when resolved against the test `Calendar`, falls on or before `now`'s `startOfDay`." Use `swift-testing`'s parameterised inputs with a small set of randomised trip-date generators. Justification: the past-phase rule is a universal guarantee easy to violate during refactor.

### Unit tests — `NotificationReconciler`

- Empty plan, empty pending → empty diff.
- Plan with N items, pending with same N (same identifiers, different bodies) → empty `toRemove`, `toAdd` includes all N (re-add replaces by identifier; iOS handles the body update).
- Plan with N items, pending with M extra items whose identifiers do not match the scheme → `toRemove` contains the M, `toAdd` contains the N. (Defensive cleanup of stray identifiers.)
- Plan with N items, pending with N items at identical identifiers AND identical bodies → `toRemove` empty, `toAdd` empty. (Avoid no-op writes when nothing changed.)

### Unit tests — `NotificationIdentifier`

- Round-trip: `parse(make(tripID, phase)) == (tripID, phase)` for every `Phase` case.
- `parse` returns `nil` for malformed strings (wrong prefix, missing components, non-UUID, unknown phase raw).

### Integration tests — `NotificationsService`

`NotificationCenterProtocol` (full method list in Components and Interfaces) is implemented by a stub in `ScrambleTests/Doubles/StubNotificationCenter.swift`. Production `UNUserNotificationCenter` gains a small extension declaring conformance. Tests cover:

- New trip save with future eligible phases and `notDetermined` auth: service calls `requestAuthorization`. If granted, service schedules N requests. If denied, service schedules zero.
- `ScenePhase` → `.active` with previous auth `.denied` and current `.authorized`: full reconcile runs (backfill, Decision 10).
- `ScenePhase` → `.background` flushes any pending coalesce immediately.
- Coalescing: two `requestReschedule(.localWrite)` calls within 2s produce one reconcile.
- `.tripDeleted(tripID)`: pending requests for that trip removed without coalesce delay; delivered notifications for that trip also removed via `removeDeliveredNotifications`.
- No-op detection: a planner output identical to the existing pending state (same identifiers, same bodies) produces an empty `Diff`.

### Integration tests — `PendingChangeBroadcaster`

- `notifyPendingChanges` forwards to every child in registration order.
- A child that throws (logged internally) does not block subsequent children.
- Removing the engine child and re-adding it leaves the notification child receiving calls uninterrupted (covers the test-harness recomposition pattern).

### Unit tests — `TripRecordTranslator` countryCode round-trip

`ScrambleTests/TripRecordTranslatorTests.swift`:

- `toRecord` writes `countryCode` to the CKRecord when set; sets the field to `nil` (overwriting any prior value) when `trip.countryCode == nil`.
- `from(record, into:)` writes a non-nil incoming value to `trip.countryCode`; leaves the value unchanged when the field is missing from the record.
- Set → unset → set toggle preserves CKRecord system fields across the cycle (uses existing `encodeSystemFields`/`decodeSystemFields` helpers).

### UI tests — `ScrambleUITests`

Notification delivery cannot be tested end-to-end without a live simulator clock advance. Coverage is limited to:

- Trip Editor "country code" field accepts "NL", renders flag emoji adjacent.
- Trip Detail header shows the flag emoji for a trip created with `countryCode == "JP"`.
- Reduce Motion enabled: accordion expand uses an opacity transition (asserted via a snapshot of the accordion at mid-animation, or via the existing `AccessibilityFeatures` test-injection seam — to be picked in task planning).

VoiceOver labels are tested via the existing UI-test rotor inspection pattern (used in Phase 4): inspect the accessibility tree, assert label strings on `PhaseRow`, `TaskRow`, `PackingItemRow`, and the per-person progress bar.

### Manual tests

Recorded in a new `specs/phase-6-notifications-polish/manual-test-plan.md` (created during implementation, not in this spec):

- Schedule a notification with `xcrun simctl push` + a pre-prepared payload, confirm delivery at 09:00 device-local on the activation date.
- Tap the notification from cold-launch, background, and foreground; confirm navigation to the correct trip + phase in all three cases.
- Tap a notification while `PackingSheet` is open; confirm sheet dismisses then navigates.
- Verify foreground delivery banner appears (Req 1.3 — `willPresent`).
- AX5 sanity pass; record findings per Req 10.5.
- DST boundary: schedule a notification for a date past the next DST transition; verify it fires at 09:00 destination-local time.
