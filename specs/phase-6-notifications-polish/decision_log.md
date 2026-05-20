# Decision Log: Phase 6 — Notifications + Polish

## Decision 1: Workflow path

**Date**: 2026-05-19
**Status**: accepted

### Context

Phase 6 covers seven workstreams (activation notifications, deep linking, country flag, transitions, haptics, VoiceOver, Dynamic Type). The spec workflow asks first whether to go full-spec or smolspec.

### Decision

Use the full spec workflow (requirements → design → tasks) for a single Phase 6 spec covering all seven workstreams.

### Rationale

Estimated 600–900 LOC across 12–15 existing files plus 3–5 new files. Notifications alone need real requirements work (permission denial, timezone, past-phase handling). Cross-cutting accessibility risk across every interactive surface justifies a design pass before implementation.

### Alternatives Considered

- **Smolspec**: Rejected — well above the smolspec thresholds on LOC, file count, and cross-cutting concerns.
- **Split into Phase 6 (notifications) + Phase 7 (polish)**: Rejected — the user picked the bundled path, and the two halves share the same accessibility audit and the same Trip-Detail header surface (flag emoji), so splitting would duplicate review effort.

### Consequences

**Positive:**
- Single review pass covers both notification correctness and polish coverage.
- Country flag, deep-link, and accessibility live next to each other on the Trip Detail header, so they get designed together.

**Negative:**
- Larger spec than recent phases. Manageable because notifications and polish are largely independent within the implementation.

---

## Decision 2: Notification permission requested in context, not at launch

**Date**: 2026-05-19
**Status**: accepted

### Context

iOS requires user authorization for local notifications. The prompt can fire at app launch, during onboarding, or contextually at the moment notifications would matter to the user.

### Decision

Request notification authorization the first time the user saves a trip whose dates produce at least one eligible future-phase activation. Do not prompt at app launch.

### Rationale

A user who has just configured trip dates has obvious context for why notifications are useful. Asking at launch — before the user has any data in the app — risks a denial that the app then cannot recover from without a Settings detour.

### Alternatives Considered

- **Onboarding / launch prompt**: Rejected — low context, higher denial rate, and Scramble has no real onboarding flow today.
- **Opt-in toggle only, never auto-prompt**: Rejected — most users will never find a buried setting; the headline notification feature would silently never fire.

### Consequences

**Positive:**
- Higher likely authorization rate.
- Users who never create a trip are never prompted.

**Negative:**
- Notifications do not work for trips created on a device that already had permission denied; recovery requires the user to find the Settings affordance described in Req [2.5](requirements.md#2.5).

---

## Decision 3: Past and currently-active phases are skipped at scheduling

**Date**: 2026-05-19
**Status**: accepted

### Context

A trip created or edited during its own lifetime will have phases whose activation dates are already in the past. iOS will fire any scheduled notification whose date is in the past as soon as it is delivered to `UNUserNotificationCenter`, which would produce a burst of overdue notifications immediately after editing trip dates.

### Decision

Activation notifications are scheduled only for phases whose activation date is strictly after the device's current local date at scheduling time. Past phases and the phase that is currently active are both skipped.

### Rationale

Avoids notification spam on trip creation, edit, and CloudKit sync. The currently-active phase is by definition something the user is already inside the app for or will be shortly; firing a "phase has started" notification mid-phase is redundant.

### Alternatives Considered

- **Fire current-phase notification on save**: Rejected — confuses "the trip just got created" with "the phase just activated".
- **Schedule everything, let iOS dedupe**: Rejected — iOS does not dedupe based on activation semantics; overdue notifications fire on delivery.

### Consequences

**Positive:**
- Editing a trip in-progress is silent on the notification side.
- Trip created mid-phase produces notifications only for future phases.

**Negative:**
- A user who creates a trip the morning the day-before phase activates will not be notified for that phase. Acceptable — they were already in the app to create the trip.

---

## Decision 4: Notification fires at 09:00 device-local time

**Date**: 2026-05-19
**Status**: accepted

### Context

Notifications need a time of day, not just a date. Options range from "fire at midnight" to "let the user configure it".

### Decision

Fire at 09:00 local time on the activation date. Time-of-day configuration is non-goaled.

### Rationale

09:00 is a defensible default that hits most users' morning rather than overnight. Per-user configuration adds a settings screen this phase deliberately does not introduce.

### Alternatives Considered

- **08:00 / 10:00**: Rejected — no meaningful difference; pick one and commit.
- **User-configurable time**: Rejected — non-goal; would need a Settings screen we have no other reason to build.
- **Fire at trip creation time-of-day**: Rejected — creation time is arbitrary and tells us nothing about when the user wants to be reminded.

### Consequences

**Positive:**
- Predictable, testable behaviour.

**Negative:**
- A user travelling across time zones sees notifications fire at 09:00 in whatever zone the device is currently in, which may not align with the trip's destination. Acceptable in v1.

---

## Decision 5: Country code stored as ISO 3166-1 alpha-2 on `Trip`

**Date**: 2026-05-19
**Status**: accepted

### Context

The deferred Phase 1 Decision 5 promised a country flag emoji on the Trip Detail header. `TripAttributes` currently has no destination or country attribute; there is nowhere to derive a flag from today.

### Decision

Add an optional `countryCode: String?` field to `Trip`. Treat it as ISO 3166-1 alpha-2 (e.g., "NL", "JP"). The flag emoji is derived at render time by combining the two regional-indicator scalars.

### Rationale

ISO codes are tiny (2 bytes), stable, language-neutral, and trivially map to flag emoji on every iOS version we support. Storing the emoji directly would couple the data model to Unicode emoji updates and complicate future use of the country code for non-emoji purposes (rule conditions, formatters, weather lookups).

### Alternatives Considered

- **Store the emoji directly**: Rejected — data couples to presentation.
- **Add a typed `destination` attribute to `TripAttributes`**: Rejected — `TripAttributes` is a free-form rules-engine input keyed by string values; conflating it with a typed country field would distort the engine's contract for an unrelated header decoration.
- **Defer again**: Rejected — Phase 6 is the explicit follow-up phase; deferring twice is bad faith.

### Consequences

**Positive:**
- Future features (region-aware rules, weather, currency) can reuse the same code.
- Cheap to migrate (nullable column).

**Negative:**
- Editor UI for setting the country still needs to exist. The Non-Goals list specifically rules out a full country picker for this phase; the design phase will pick between a minimal alpha-2 text entry vs. a system picker.

---

## Decision 6: Deep-link URL scheme `scramble://`

**Date**: 2026-05-19
**Status**: accepted

### Context

Notification taps need to route iOS into the app and tell us which trip + phase to open.

### Decision

Register `scramble://` as a custom URL type for the app bundle. Activation notifications carry a `scramble://trip/<UUID>?phase=<rawValue>` URL in their `userInfo`.

### Rationale

Custom scheme is the lowest-friction option for an app that already has a CloudKit container and no public web presence to attach Universal Links to. The URL surface is internal only; nobody else will be generating these.

### Alternatives Considered

- **Universal Links** (`https://`): Rejected — requires a hosted apple-app-site-association file at a domain we do not own for this app.
- **Notification `userInfo` dictionary with raw IDs**: Rejected — works, but a URL is the canonical iOS pattern and gives us a debuggable representation.

### Consequences

**Positive:**
- Trivial to test (paste `scramble://trip/<id>?phase=departureDay` into Safari address bar in the simulator).
- Reusable for future deep-link cases (notifications, shortcuts, share-extension follow-up).

**Negative:**
- Custom schemes can collide with other apps; the `scramble://` namespace is unowned and we are squatting on it. Low risk in practice.

---

## Decision 7: Trigger is calendar-based, not timestamp-based

**Date**: 2026-05-19
**Status**: accepted

### Context

`UNUserNotificationCenter` supports two trigger types for date-bound delivery: `UNTimeIntervalNotificationTrigger` (fires after an absolute interval from now) and `UNCalendarNotificationTrigger` (fires when a `DateComponents` match in the current calendar). A user who schedules a notification then travels across a DST boundary or a time zone will see different fire times depending on which trigger type is used.

### Decision

Use `UNCalendarNotificationTrigger` with `DateComponents(year, month, day, hour: 9, minute: 0)` for each activation. The trigger evaluates against the device's current calendar at fire time, so DST transitions and time-zone changes resolve correctly.

### Rationale

A trip that starts three months out crosses at least one DST boundary in most regions. A timestamp-based trigger frozen at scheduling time would drift by an hour after DST. Calendar-based triggers are the platform's intended primitive for "fire at 09:00 on this date".

### Alternatives Considered

- **Absolute `Date` via `UNTimeIntervalNotificationTrigger`**: Rejected — drifts on DST and time-zone changes.
- **Daily `UNCalendarNotificationTrigger` that the app cancels on the wrong days**: Rejected — over-complex, race-prone.

### Consequences

**Positive:**
- DST-correct without per-trip recomputation logic.
- Travelling to a new time zone fires at 09:00 in the destination zone.

**Negative:**
- A user travelling across time zones may receive a notification at 09:00 destination-time even though it was originally scheduled for 09:00 home-time. Acceptable; arguably more useful.

---

## Decision 8: 60-pending-notification cap with deterministic selection

**Date**: 2026-05-19
**Status**: accepted

### Context

iOS limits an app to ~64 pending local notifications. A user with 13 trips × 5 eligible phases = 65 requests exceeds the limit; iOS silently drops requests beyond the cap, and the dropped subset is not deterministic.

### Decision

Cap activation notifications at 60 pending requests (4 under the iOS limit, reserved for headroom). When the eligible activations exceed the cap, schedule the 60 activations whose fire date is soonest, breaking ties by trip `startDate` ascending then trip `id` ascending. Apply this cap in the reconciliation pass.

### Rationale

A deterministic cap means two devices observing the same trip set choose the same 60 to schedule, so a user with the app on iPhone and iPad sees consistent behaviour without needing to sync notification state. Soonest-first matches user expectation that the most-imminent reminders are the ones that matter.

### Alternatives Considered

- **No cap, rely on iOS to drop**: Rejected — iOS's drop order is undocumented and not deterministic across devices.
- **Per-trip cap (e.g., one notification per trip — the next phase)**: Rejected — under-uses the budget for users with few trips and complicates the reschedule logic for trip-date changes.
- **Cap by trip recency**: Rejected — "most recently edited trip" is unstable across devices.

### Consequences

**Positive:**
- Deterministic across devices.
- Reconciliation logic stays simple.

**Negative:**
- A user with >12 active trips will not see notifications for the farthest-out phases until earlier ones fire and free slots. Acceptable; messaging in `implementation.md` will note the limit.

---

## Decision 9: Notification tap routing via `UNUserNotificationCenterDelegate`, not URL dispatch

**Date**: 2026-05-19
**Status**: accepted

### Context

Initial requirements draft assumed the custom `scramble://` URL scheme was the routing mechanism. Peer review (Codex) flagged that local-notification taps arrive through `UNUserNotificationCenterDelegate.userNotificationCenter(_:didReceive:)` — iOS does not auto-open the embedded URL. The URL is useful for diagnostics and external testing but is not the production routing path.

### Decision

Route notification taps via the `UNUserNotificationCenterDelegate` callback, extracting `tripID` and `phase` from the notification's `userInfo` dictionary. Register `scramble://` as a debug/test affordance only.

### Rationale

Matches iOS's actual local-notification routing path. Avoids parsing URL strings on the hot path. Keeps the `scramble://` URL available for `xcrun simctl openurl` and Safari testing without coupling it to production routing.

### Alternatives Considered

- **URL-based routing via `onOpenURL`**: Rejected — does not match the platform contract for local notifications; would silently fail.
- **Drop the URL scheme entirely**: Rejected — being able to paste a `scramble://trip/...` URL into Safari and have it route is useful for QA.

### Consequences

**Positive:**
- Routing matches the iOS-intended path.
- Debug URL remains testable.

**Negative:**
- Two code paths (delegate + onOpenURL) must converge on the same navigation logic. Mitigated by extracting routing into a single function.

---

## Decision 10: Authorization recovery (denied → authorized) backfills via reconciliation

**Date**: 2026-05-19
**Status**: accepted

### Context

If a user denies notification permission, then later grants it via iOS Settings and returns to the app, existing trips should start producing notifications without requiring the user to re-save each trip.

### Decision

On foreground re-entry, the app re-reads authorization status. A flip from `denied`/`notDetermined` to `authorized` triggers a full reconciliation pass, which schedules notifications for all eligible phases of all existing trips per Req [4.5](requirements.md#4.5).

### Rationale

Backfill is the user expectation. Reconciliation is already a required code path (app launch); reusing it on authorization-state changes avoids a second mechanism.

### Alternatives Considered

- **No backfill (user must re-save each trip)**: Rejected — terrible UX.
- **Backfill only on next trip save**: Rejected — leaves existing trips silent indefinitely.

### Consequences

**Positive:**
- Authorization recovery is transparent to the user.
- Single reconciliation algorithm covers launch and authorization-state-flip cases.

**Negative:**
- A user toggling notifications on/off rapidly in Settings will trigger a reconciliation pass each time. Acceptable; the pass is cheap.

---

## Decision 11: Modal sheets dismissed before deep-link routing

**Date**: 2026-05-19
**Status**: accepted

### Context

If a notification tap arrives while the user has `PackingSheet`, Trip Editor, or `UICloudSharingController` presented, the app must choose between routing through (potentially leaving the sheet up), dismissing the sheet, or queuing the route until the sheet closes.

### Decision

Dismiss the topmost sheet, then route. Dismissed sheets are not re-presented after navigation completes.

### Rationale

The notification tap is the user's explicit intent to navigate. Honouring that intent immediately matches platform conventions for app activation via notification. Re-presenting the dismissed sheet would be confusing and produces hard-to-test interaction state.

### Alternatives Considered

- **Queue the route until sheet dismisses**: Rejected — user has to dismiss the sheet themselves before the routing happens; surprising delay.
- **Ignore the route if a sheet is up**: Rejected — silently dropping the user's tap is worse than dismissing a sheet.

### Consequences

**Positive:**
- Deterministic behaviour.
- Single navigation path on resume.

**Negative:**
- A user mid-edit in the Trip Editor loses unsaved draft state. Acceptable; existing Trip Editor save model already discards unsaved changes on dismiss.

---

## Decision 12: Event source is `PendingChangeBroadcaster` over `LocalWriteHook`, not `TripSyncEventBus`

**Date**: 2026-05-19
**Status**: accepted

### Context

The notifications subsystem needs a signal whenever Trip-domain state changes locally (insert, edit, delete) and after CloudKit-arrived changes have been persisted. The first design draft routed through `TripSyncEventBus`, but the bus is a fixed two-slot router (`subscribeOrchestrator` / `subscribeCoordinator`), with `assertionFailure` on a third subscriber. Adding a third slot would change Phase 5.1's bus contract.

### Decision

Introduce `PendingChangeBroadcaster` — a `PendingChangeNotifier` that wraps N children. `ScrambleApp.init` wires `LocalWriteHook(notifier: PendingChangeBroadcaster(children: [tripSyncEngine, notificationsService]))`. `NotificationsService` conforms to `PendingChangeNotifier` and treats every `notifyPendingChanges` call as a `.localWrite` reschedule trigger.

### Rationale

`LocalWriteHook.commit` is already the universal chokepoint for `tripsLocal` writes (Phase 5.1 invariant). Multicasting at the notifier seam is a small, additive change — no Phase 5.1 contract is modified. The broadcaster decorator pattern is well-known and reads cleanly. The reconciler being full-fleet means we don't need to classify writes; firing on every commit is acceptable.

### Alternatives Considered

- **Widen `TripSyncEventBus` to N subscribers**: Rejected — changes Phase 5.1's documented two-slot contract and complicates the bus's ordering guarantees.
- **Hook the orchestrator and have it re-emit**: Rejected — gives the orchestrator a responsibility unrelated to its rules-engine job.
- **`NotificationCenter` (`Foundation`, not `UN`) broadcast pattern**: Rejected — adds an untyped Notification post path orthogonal to the existing typed notifier protocol.
- **No event source; rely on `.appActivation` reconcile only**: Rejected — Req 4.3 requires task-edit-driven notification updates within the session.

### Consequences

**Positive:**
- Phase 5.1's bus contract is untouched.
- Single chokepoint (`LocalWriteHook.commit`) carries all local writes — no risk of a missed call site as long as the chokepoint invariant holds.
- Test injection is straightforward (the broadcaster takes a child list).

**Negative:**
- Remote-applied changes that bypass `LocalWriteHook` (CKSyncEngine internal saves) don't trigger the broadcaster. Mitigated by the `.appActivation` reconcile catching up on next foreground.
- The broadcaster fires for non-notification-relevant writes (packing items, attribute edits). Reconciler work is wasted on those; coalesce window absorbs the cost.

---

## Decision 13: Sheet dismissal uses non-animated dismiss + one yield, not animation completion

**Date**: 2026-05-19
**Status**: accepted

### Context

A notification tap that arrives while a modal sheet is presented must dismiss the sheet before navigating. SwiftUI `.sheet` bindings dismiss in the next render cycle; `UICloudSharingController` (presented via `SharingControllerHost`) dismisses asynchronously via `UIViewController.dismiss(animated:)`. Animation-completion handlers add complexity to the routing path.

### Decision

Set every known sheet binding to `false`/`nil` and call `dismiss(animated: false)` on the sharing controller. Then `Task { @MainActor in await Task.yield(); ... }` once before navigating. No completion handlers, no animation timing dependencies.

### Rationale

The notification tap is an explicit user intent to navigate elsewhere; animated dismissal of the sheet is a cosmetic concern that conflicts with that intent. Non-animated dismissal of UIKit-presented controllers is deterministic and finishes within one runloop iteration. SwiftUI sheet bindings flip in the same render cycle they are set. A single `Task.yield()` is sufficient to let SwiftUI process the binding change before the navigation push.

### Alternatives Considered

- **Animated dismissal + completion-handler wait**: Rejected — adds a callback dependency and a multi-state machine for sheet types that share no dismissal API.
- **No dismissal — let the sheet stay up over the navigation**: Rejected — `PackingSheet` and the sharing controller cover the timeline entirely; the user wouldn't see they're now on a different trip.
- **Queue the route until the sheet closes naturally**: Rejected — surprising delay; user already tapped the notification.

### Consequences

**Positive:**
- Deterministic timing.
- Single yield bridges all sheet types.

**Negative:**
- A user mid-edit in `TripEditorView` loses unsaved draft state without animation. Acceptable; existing editor save model already discards on dismiss.
- The dismissal is visually abrupt. Acceptable given the explicit-navigation context.

---

## Decision 14: AX5 is a sanity pass, not a design target

**Date**: 2026-05-19
**Status**: accepted

### Context

The UI design doc says "Test at AX5 (largest accessibility size)". Fully supporting AX5 across every screen is a significant layout investment that competes with shipping the rest of Phase 6.

### Decision

Phase 6 ships AX2-correct reflow across all listed surfaces and performs an AX5 sanity pass on the same surfaces. Any AX5 layout breakage discovered is recorded in `implementation.md` as known limitations rather than fixed in this phase.

### Rationale

AX2 covers the vast majority of users who change Dynamic Type. AX5 is a stress test that the design doc itself frames as a verification step, not a design target. Recording rather than fixing AX5 issues keeps Phase 6 scoped while leaving an honest record.

### Alternatives Considered

- **Skip AX5 entirely**: Rejected — the design doc references it; the sanity pass costs little.
- **Make AX5 a hard requirement**: Rejected — open-ended layout work, hard to scope.

### Consequences

**Positive:**
- Scoped, finishable phase.
- Documented AX5 state, not an unknown.

**Negative:**
- Users at AX5 still see layout issues until a future phase addresses them.

---

## Decision 15: `NotificationsService` is not `@Observable`

**Date**: 2026-05-20
**Status**: accepted

### Context

`design.md` §"Notifications service" specifies `@Observable` on `NotificationsService` so SwiftUI surfaces (the "Open Settings" affordance) can re-render when `authStatus` flips. During implementation the `@Observable` macro was applied, then removed.

### Decision

`NotificationsService` is a plain `@MainActor final class` with `private(set) var authStatus`. SwiftUI surfaces re-read `authStatus` at body re-evaluation time rather than subscribing to property changes.

### Rationale

Marking the class `@Observable` while it owns a SwiftData `ModelContext`-returning closure (`tripContext: @MainActor () -> ModelContext`) crashed SwiftUI's AttributeGraph layout-descriptor traversal under Swift Testing's parameter machinery — every `NotificationsServiceTests` case failed before its body ran. Dropping the macro is the smallest change that lets the test suite run; the affordance still flips on the next foreground because `handleScenePhase(.becameActive)` re-reads `authStatus` and SwiftUI re-evaluates the body whenever `TripDetailView`'s parent state changes.

### Alternatives Considered

- **Keep `@Observable` and split out the `ModelContext` closure into a separate non-observable holder**: Rejected — pushes the indirection through every call site for what is effectively one screen's flicker.
- **Wrap `authStatus` in a separate `@Observable AuthStatusHolder`**: Rejected — adds a class for a single property; not worth the indirection for v1.

### Consequences

**Positive:**
- Test suite runs without an AttributeGraph crash.
- Surface area of the service stays small.

**Negative:**
- The "Open Settings" affordance does not animate as `authStatus` flips; it only updates on the next render the host SwiftUI tree triggers.
- If a future surface needs reactive binding to `authStatus` (e.g. a settings screen), this trade-off has to be revisited.

---

## Decision 16: Routing state machine ships as minimum viable; sheet-dismissal deferred

**Date**: 2026-05-20
**Status**: accepted (partial implementation of Decision 11)

### Context

[Decision 11](#decision-11-modal-sheets-dismissed-before-deep-link-routing) and [Decision 13](#decision-13-sheet-dismissal-uses-non-animated-dismiss--one-yield-not-animation-completion) describe a four-state machine `.idle → .dismissingSheets → .navigating → .idle` that dismisses every known SwiftUI sheet binding plus the `UICloudSharingController` wrapper before pushing the routed trip.

### Decision

`RootView.consumeActivationRoute` (`Features/Root/RootView.swift:108`) flips the tab, resets `tripsPath` to root, and pushes the routed trip in a single transaction. It does *not* dismiss currently-presented sheets. The routed phase is consumed by `TripDetailView` (`Features/Trips/TripDetailView.swift`) on appear via `.task` + `.onChange(of: activationRouter?.pendingRoute)` and applied to `expandedPhase` (with eligibility fallback per Req 5.5).

### Rationale

End-state navigation is correct: the routed trip becomes the front-most navigation stack, with the correct phase expanded once the user dismisses any pre-existing sheet. The dismiss-before-navigate polish would require enumerating every sheet binding (`pendingForm`, `packingSheetState`, `showEditor`, the `UICloudSharingController` host, `editAttributeFocus`-driven sheets) and threading a `Task.yield()` so SwiftUI completes one render cycle before path replacement. That is straightforward in isolation but does not change the eventual navigation destination — only the *transition* to it. Shipping the rest of Phase 6 takes priority.

### Alternatives Considered

- **Implement the full state machine now**: Rejected for scope reasons; the destination is correct in the minimum viable path.
- **Block on the sheet dismissal — pause routing until the user dismisses manually**: Rejected — that breaks Req 5.4 (route lookup that misses should leave navigation untouched, but the route is consumed by RootView immediately on tap).

### Consequences

**Positive:**
- Phase 6 ships with notification taps reaching the right trip+phase end-state.
- Smaller surface to test in this phase.

**Negative:**
- Req 5.3 is not strictly satisfied; a sheet up when a notification is tapped remains visible until the user dismisses it.
- A follow-up phase has to wire the full state machine to satisfy Req 5.3 verbatim.

### Impact

Affects `RootView.consumeActivationRoute` and the documented behaviour of notification-tap routing. The `pendingRoute` slot semantics are unchanged.

---

## Decision 17: `NotificationCenterProtocol.authorizationStatus()` returns `UNAuthorizationStatus` only

**Date**: 2026-05-20
**Status**: accepted

### Context

`design.md` §"`NotificationCenterProtocol`" sketches a protocol that mirrors the `UNUserNotificationCenter` surface area the service uses, including a `notificationSettings() async -> UNNotificationSettings` method.

### Decision

The protocol exposes `authorizationStatus() async -> UNAuthorizationStatus` instead. The service does not consume any other field from `UNNotificationSettings`.

### Rationale

`UNNotificationSettings` has no public initializer, so a test stub cannot construct one to return. Returning just the `UNAuthorizationStatus` enum keeps the protocol stub-friendly and exposes exactly what the service needs (the auth state). If a future feature needs to read e.g. `alertSetting` or `lockScreenSetting`, the protocol can be extended then.

### Alternatives Considered

- **Add `UNNotificationSettings` extension that exposes only what's needed via a protocol of our own** — Rejected as over-engineered for the single field the service consumes.
- **Bridge to a homegrown `NotificationSettings` value type** — Rejected — adds a translation layer for one property.

### Consequences

**Positive:**
- Test stub is one line per call.
- Service code is straightforward (`status == .authorized` everywhere).

**Negative:**
- A future field (e.g. quiet-hours setting) requires extending the protocol.

---
