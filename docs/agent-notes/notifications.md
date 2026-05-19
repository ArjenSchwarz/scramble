# Notifications

Phase 6 added a local-notification subsystem for "phase activation" alerts:
when a trip's `dayBefore`, `departureDay`, `duringTrip`, `dayBeforeReturn`,
or `returnDay` phase first becomes current, the app fires a local
notification at 09:00 device-local time. Tapping the notification routes
the app into the relevant trip with that phase expanded.

This is local-only. Phase 5's silent-push CloudKit machinery is untouched
— the two notification namespaces (`scramble.activation.<...>` vs.
CloudKit's anonymous record-zone notifications) do not overlap.

## Topology

```
ScenePhase → .active ─┐
Trip save closures ───┤
Trip delete path ─────┼──► NotificationsService.requestReschedule(reason:)
Auth flip ────────────┤
LocalWriteHook.commit ┘   (every commit, via PendingChangeBroadcaster)
                              │
                              ▼
                       NotificationPlanner.plan(...)        → [ActivationPlan]
                              │
                              ▼
                       NotificationReconciler.diff(...)     → (toAdd, toRemove)
                              │
                              ▼
                       UNUserNotificationCenter.add / remove
```

Trigger sources and reasons:

| Source | Reason | Flush |
|---|---|---|
| `ScenePhase` → `.active` (`ScrambleApp.body`'s `.onChange`) | `.appActivation` | Immediate |
| `ScenePhase` → `.background` | `.scenePhaseBackground` | Immediate |
| `TripDeletion.delete` | `.tripDeleted(tripID)` | Immediate (also cancels delivered) |
| Authorization status flipped on foreground re-read | `.authChanged(...)` | Immediate |
| `LocalWriteHook.commit` via `PendingChangeBroadcaster` | `.localWrite` | 2 s coalesce |
| `TripListView` create save closure | implicit — calls `requestAuthorizationIfNeeded` | n/a |

## Module map

- `Notifications/NotificationIdentifier.swift` — identifier scheme
  `scramble.activation.<UUID>.<phase-rawValue>`. `make`, `parse`,
  `threadID(for:)`. Parser rejects malformed input (wrong prefix, missing
  parts, non-UUID, unknown phase).
- `Notifications/NotificationPlanner.swift` — pure function
  `plan(trips:tripTasksByTripID:now:calendar:cap:) -> [ActivationPlan]`.
  Skips ineligible phases (`weeksBefore`, `afterTrip`, compressed
  `duringTrip`), skips phases whose activation day ≤ today, sorts by
  fire date with `Trip.startDate → Trip.id` tie-break, clamps to 60.
  Body strings rendered by `body(tripName:phase:outstandingTasks:)`.
- `Notifications/NotificationReconciler.swift` — diffs planner output
  vs. `UNUserNotificationCenter.pendingNotificationRequests()`. Body-
  match no-op detection so an identical reconcile run doesn't re-add
  requests. Pending requests outside the `scramble.activation.`
  namespace are ignored.
- `Notifications/NotificationCenterProtocol.swift` — test seam over
  `UNUserNotificationCenter`. Returns `UNAuthorizationStatus` directly
  (not `UNNotificationSettings`) so tests can stub without keyed-
  archiver synthesis.
- `Notifications/PendingChangeBroadcaster.swift` — multicasts
  `PendingChangeNotifier` to N children (currently `[TripSyncEngine,
  NotificationsService]`). Strong references — both children are
  app-lifetime owned (Decision 12).
- `Notifications/NotificationRouter.swift` —
  `UNUserNotificationCenterDelegate`. 1-slot `pendingRoute`
  consumed by `RootView`. Parses both notification `userInfo` and the
  debug `scramble://trip/<UUID>?phase=<raw>` URL into the same
  `ActivationRoute`. `willPresent` returns `[.banner, .sound]`.
- `Notifications/NotificationsService.swift` — orchestrator.
  `requestReschedule(reason:)` is the single funnel.
  Immediate-flush reasons (`.appActivation`, `.scenePhaseBackground`,
  `.tripDeleted`, `.authChanged`) bypass the 2 s coalesce window.
  `handleScenePhase` takes a local `.becameActive` /
  `.enteredBackground` enum so the service file doesn't import SwiftUI.
  `requestAuthorizationIfNeeded(forTrip:)` is the in-context auth
  gate; short-circuits when status != `.notDetermined` or when the
  trip yields zero plans.

## Identifier scheme

Activation notification identifier — `UNNotificationRequest.identifier`:
```
scramble.activation.<UUID>.<phase-rawValue>
```

Thread identifier — `UNNotificationRequest.content.threadIdentifier`:
```
scramble.trip.<UUID>
```

The activation identifier is contractual: adding a request with the same
identifier replaces the existing one (mechanically enforced by iOS), so
body changes do not need a separate `remove` step. The thread identifier
groups all of one trip's pending and delivered notifications together in
Notification Center.

## 60-cap and tie-break

iOS limits the app to ~64 pending local notifications. We cap at 60 (4
under the limit, reserved for headroom). When the eligible activations
exceed the cap, the planner sorts by:

1. Fire date ascending
2. `Trip.startDate` ascending
3. `Trip.id.uuidString` ascending

…and truncates to 60. The tie-break is deterministic across devices so
the same user's phone and iPad pick the same set to schedule.

## Deep-link routing

Production routing: `UNUserNotificationCenterDelegate.userNotificationCenter(_:didReceive:)`
extracts `tripID` and `phase` from the notification's `userInfo` and
writes the result to `NotificationRouter.pendingRoute`. The debug
`scramble://` URL scheme is registered (Info.plist `CFBundleURLTypes`)
and parsed by `NotificationRouter.route(from url:)` — useful for
`xcrun simctl openurl` and Safari testing, not the production path.

The 1-slot queue holds at most one tap. A later tap before the consumer
has drained the slot overwrites the earlier one (last write wins). The
consumer (`RootView.consumeActivationRoute()`) calls `consumeRoute()`
which is an atomic read + clear.

## Foreground delivery

`UNUserNotificationCenterDelegate.userNotificationCenter(_:willPresent:)`
returns `[.banner, .sound]` so foreground delivery is visible rather
than silently suppressed (Req 1.3).

## Authorization flow

- Permission requested in-context only — first save of a trip whose
  dates would produce at least one eligible phase (Decision 2).
- Denied → no re-prompt from inside the app. The "Notifications are
  off — open Settings" affordance in `TripDetailView` opens iOS
  Settings via `UIApplication.openSettingsURLString`.
- `denied → authorized` on foreground re-entry runs a full
  reconciliation pass (backfill, Decision 10).
- `authorized → denied` on foreground re-entry cancels every pending
  activation request.

## Limitations

- The `NotificationsService` is intentionally not `@Observable` yet.
  Marking it `@Observable` while it owns a SwiftData `ModelContext`
  accessor crashes SwiftUI's AttributeGraph layout-descriptor
  traversal under Swift Testing's parameter machinery (`Test crashed
  with signal trap`). The "Open Settings" affordance reads `authStatus`
  on every body re-evaluation, which is sufficient for the affordance
  to appear/disappear when the status flips after a foreground
  reconcile.
- `NotificationRouter` is `@Observable` and exposes `pendingRoute`. The
  `RootView` consumer uses `.onChange(of: activationRouter?.pendingRoute)`
  to drain it.
- The full routing state machine from design.md
  (`.idle → .dismissingSheets → .navigating → .idle`, dismissal of
  `UICloudSharingController` via `dismiss(animated: false)`, the
  `Task.yield` bridge) is deferred — the current consumer flips the
  tab and resets/appends the navigation stack, which lands the user
  on the correct trip. Sheet-dismissal-before-routing is polish, not a
  correctness blocker.
