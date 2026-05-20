# Requirements: Phase 6 — Notifications + Polish

## Introduction

Phase 6 closes out the v1 design docs. It schedules a local notification when a trip phase activates and routes the tap into the right trip with that phase expanded, then takes the timeline, tasks, packing rows, and packing sheet through the polish pass the UI design doc has carried since Phase 3: animated transitions on accordion/checkbox/sheet, the haptics matrix, VoiceOver labels and a "Why is this here?" accessibility action, Dynamic Type reflow up to AX2, and the deferred country-flag emoji on the Trip Detail header (Phase 1 Decision 5).

## Terminology

- **Activation date** — the calendar date on which a phase becomes "current" per `PhaseDateMapping.dateRange` (the first day of the phase's range, taken at the device's local-time `startOfDay`).
- **Eligible phase** — a phase that has a well-defined activation date and at least one day of duration for the trip in question. The two open-ended phases (`.weeksBefore`, `.afterTrip`) and the compressed `.duringTrip` case (`PhaseDateMapping.isCompressed == true`) are not eligible.
- **Activation notification** — a local notification scheduled to fire at 09:00 device-local time on an eligible phase's activation date for a given trip.
- **Notification identifier** — the string `scramble.activation.<tripID-UUID>.<phase-rawValue>` used as the `UNNotificationRequest.identifier` so a given `(tripID, phase)` is unique and replaceable.
- **Deep link** — the URL `scramble://trip/<trip-UUID>?phase=<phase-rawValue>` carried in the activation notification's `userInfo` for diagnostic logging and out-of-app testing. Tap routing itself uses `UNUserNotificationCenterDelegate.userNotificationCenter(_:didReceive:)` and the `userInfo` payload directly — not URL dispatch.
- **Haptics matrix** — the five-row table in `docs/scramble-ui-design-doc.md` §"Haptics".
- **Reduce Motion** — `UIAccessibility.isReduceMotionEnabled` and the SwiftUI `\.accessibilityReduceMotion` environment value.

## Non-Goals

- Notifications for task assignment, packing progress, share invitations, or any trigger other than phase activation.
- User-configurable notification time-of-day, snooze, quiet-hours, mark-done from the lock screen, or per-trip mute toggle.
- Notification interruption levels beyond the iOS default (no `.timeSensitive`, no `.critical`, no `.provisional`).
- Communication notifications, custom notification categories with actions, notification attachments (images, sounds beyond the default).
- A Settings screen for notification permission management beyond a one-tap affordance that opens iOS Settings → Scramble → Notifications.
- Push notifications via APNs. Phase 6 schedules local notifications only; CloudKit silent pushes from Phase 5 remain untouched.
- Widgets, Live Activities, or Dynamic Island integration for phase countdowns.
- Apple Watch or iPad-specific layouts.
- Full localisation. Strings remain English; Dynamic Type reflow is the only layout-direction-adjacent work.
- Custom Focus Mode filters.
- A country picker UI in the trip editor as part of Phase 6 — see Req [5](#5-country-flag-emoji-on-trip-detail-header) for what is in scope. Adding the picker is deferred until the typed-attributes work the design doc anticipates.
- Visual / theme changes. Polish is animation, haptics, and accessibility; colours and component visuals are unchanged.
- AX3, AX4, AX5 design adjustments. Phase 6 ships AX2-correct reflow and a documented AX5 sanity pass; any layout breakage at AX5 is recorded for a follow-up, not fixed.
- Performance instrumentation, energy profiling, or launch-time targets.

## Constraints / Invariants

These hold for the lifetime of Phase 6 and beyond. They are not event-driven and therefore not in EARS form.

- <a name="C1"></a>**C1** At most one pending activation notification per `(tripID, phase)` exists on the device. Uniqueness is enforced by the notification identifier defined in Terminology.
- <a name="C2"></a>**C2** No activation notification is scheduled whose activation date is on or before the device's current local calendar day at the time the scheduling call is made. ("Current local calendar day" means `Calendar.current.startOfDay(for: Date())`.) This implements Decision 3 unambiguously: a phase whose activation is today or in the past is skipped, regardless of the wall-clock time at scheduling.
- <a name="C3"></a>**C3** When notification authorization is `denied` or `notDetermined`, the system has zero pending activation notifications on the device.
- <a name="C4"></a>**C4** Deep-link / notification-tap handling never creates state that survives a failed lookup: if the referenced trip does not exist on the device, navigation state is unchanged.
- <a name="C5"></a>**C5** Trip Detail SwiftUI reads (including the country-code-derived flag emoji) consume `Trip` from the `tripsLocal` container, consistent with Phase 5.1's container topology. The `globals` container is not read for Trip-domain attributes.
- <a name="C6"></a>**C6** The polish workstreams (transitions, haptics, VoiceOver, Dynamic Type) introduce no behaviour change observable to existing automated tests. Existing test suites continue to pass without modification.

## Requirements

### 1. Activation notifications fire on the day a phase becomes current

**User Story:** As a trip owner, I want the app to remind me when a planning phase begins, so I can act on outstanding tasks without checking the app daily.

**Acceptance Criteria:**

1. <a name="1.1"></a>WHEN a trip exists with `startDate` and `endDate` set and notification authorization is `authorized`, the system SHALL have a pending local notification (registered with `UNUserNotificationCenter`) for each eligible phase's activation date for that trip, using a calendar-based `UNCalendarNotificationTrigger` set to 09:00 device-local time so daylight-saving transitions and time-zone changes resolve through the system calendar rather than an absolute timestamp.  
2. <a name="1.2"></a>The activation notification body SHALL include the trip name and the phase's display name; WHEN the outstanding (incomplete) task count for that phase at scheduling time is greater than zero, the body SHALL include that count using the format `"{N} outstanding task(s) for '{phase display name}'"`; WHEN the count is zero, the body SHALL be `"'{phase display name}' has started"` and SHALL NOT include a count.  
3. <a name="1.3"></a>WHEN the device's local date reaches a scheduled activation date at 09:00, iOS SHALL deliver the notification through its standard alert/banner path; WHEN the app is in the foreground at delivery time, the system SHALL present the notification via `UNUserNotificationCenterDelegate.userNotificationCenter(_:willPresent:withCompletionHandler:)` with `.banner` and `.sound` so foreground delivery is visible rather than silently dropped.  
4. <a name="1.4"></a>The system SHALL NOT schedule activation notifications for the `.weeksBefore` phase, the `.afterTrip` phase, or any `.duringTrip` phase for which `PhaseDateMapping.isCompressed` returns true.  
5. <a name="1.5"></a>The system SHALL NOT schedule an activation notification whose activation date is on or before the device's current local calendar day at the time of the scheduling call. ("Current local calendar day" matches the [C2](#C2) definition.)  
6. <a name="1.6"></a>WHEN the same trip is visible on multiple devices via CloudKit sharing, each device SHALL schedule its own activation notifications using its own local clock, authorization state, and locally-visible task counts. Notifications SHALL NOT be propagated through CloudKit, and the owner-side and participant-side notification bodies MAY differ in task count if the two devices have different visibility into the trip's tasks at scheduling time.  

### 2. Activation notifications respect the per-app pending budget

**User Story:** As a power user with many active trips, I want notifications scheduled deterministically when the trip count exceeds iOS's notification budget, so I always see reminders for the trips most relevant right now.

**Acceptance Criteria:**

1. <a name="2.1"></a>The system SHALL treat an effective per-app cap of 60 pending activation notifications as the upper bound on scheduled requests (4 notifications under iOS's documented 64-pending limit, reserved for headroom and future categories).  
2. <a name="2.2"></a>WHEN the eligible-phase activations across all trips on the device exceed the cap from [2.1](#2.1), the system SHALL select for scheduling the 60 activations whose fire date is soonest, breaking ties by trip `startDate` ascending, then trip `id` ascending, so two devices observing the same set of trips choose the same set of scheduled notifications.  
3. <a name="2.3"></a>The notification identifier scheme SHALL be `scramble.activation.<tripID-UUID>.<phase-rawValue>` so the system can replace a pending notification by re-adding a request with the same identifier (per `UNUserNotificationCenter` semantics) and so [C1](#C1) is mechanically enforced.  
4. <a name="2.4"></a>Each activation notification request SHALL set `threadIdentifier` to `scramble.trip.<tripID-UUID>` so Notification Center groups all of one trip's pending and delivered notifications together.  
5. <a name="2.5"></a>WHEN scheduling fails (e.g., `UNUserNotificationCenter.add` returns an error), the system SHALL log the failure and SHALL NOT retry within the same scheduling pass; the next reconciliation pass (Req [4.5](#4.5)) is the recovery point.  

### 3. Notification authorization is requested in context

**User Story:** As a user, I want the app to ask for notification permission only when notifications would actually be useful, so I'm not prompted before I understand what they're for.

**Acceptance Criteria:**

1. <a name="3.1"></a>WHEN the user saves a new trip whose dates would produce at least one eligible phase activation in the future AND notification authorization is `notDetermined`, the system SHALL request notification authorization via `UNUserNotificationCenter.requestAuthorization` with `.alert` and `.sound` options.  
2. <a name="3.2"></a>The system SHALL NOT request notification authorization at app launch, during onboarding, or before the user has saved a trip.  
3. <a name="3.3"></a>WHEN authorization is `authorized` after the request in [3.1](#3.1), the system SHALL schedule activation notifications for the just-saved trip per Req [1](#1-activation-notifications-fire-on-the-day-a-phase-becomes-current) and Req [2](#2-activation-notifications-respect-the-per-app-pending-budget).  
4. <a name="3.4"></a>WHEN authorization is `denied` (the user declined the prompt or revoked it in Settings), the system SHALL NOT request authorization again from within the app, SHALL NOT schedule any activation notifications, and SHALL remove any previously-scheduled activation notifications.  
5. <a name="3.5"></a>The app SHALL surface authorization status in a way that a user who has previously denied permission can reach: a one-tap affordance that calls `UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)`. Placement of this affordance is deferred to the design phase; the requirement is that it exists and is reachable from a screen the user already knows about.  
6. <a name="3.6"></a>WHEN the app returns to the foreground, the system SHALL re-read authorization status via `UNUserNotificationCenter.getNotificationSettings`; IF the status has flipped from `authorized` to `denied`, the system SHALL cancel all pending activation notifications; IF the status has flipped from `denied`/`notDetermined` to `authorized`, the system SHALL run a full reconciliation pass per Req [4.5](#4.5) so existing trips backfill their notifications without requiring a new trip save.  

### 4. Notifications stay aligned with the trip's current state

**User Story:** As a trip owner editing trip details, I want notifications to follow my changes, so I don't get reminded for dates I've already moved past.

**Acceptance Criteria:**

1. <a name="4.1"></a>WHEN a trip's `startDate` or `endDate` changes, the system SHALL cancel any pending activation notifications associated with that trip and reschedule per the new dates, applying [1.5](#1.5) so phases whose new activation dates have already passed are not rescheduled.  
2. <a name="4.2"></a>WHEN a trip is deleted, the system SHALL cancel all pending activation notifications associated with that trip via `removePendingNotificationRequests(withIdentifiers:)` keyed by the [2.3](#2.3) identifier scheme.  
3. <a name="4.3"></a>WHEN a `TripTask`'s phase, assignment, or completion state changes such that the outstanding-task count for one of the trip's not-yet-fired eligible phases changes, the system SHALL recompute and re-add the pending notification for that `(tripID, phase)` using the same identifier so the body reflects the new count. This recompute SHALL be coalesced — multiple task edits within a 2-second window MAY collapse into a single re-add — so per-tap UI interactions do not each fire a synchronous `UNUserNotificationCenter` call.  
4. <a name="4.4"></a>WHEN a trip-domain change arrives via CloudKit sync and is applied to `tripsLocal`, the system SHALL trigger the same reconciliation path as a local edit. The trigger fires after the change is durably persisted locally; it does not depend on receipt of a silent push.  
5. <a name="4.5"></a>WHEN the app launches (`Scene.onChange(of:newPhase: .active)` from `.background` or initial launch) AND notification authorization is `authorized`, the system SHALL run a reconciliation pass: enumerate all trips, build the expected set of `(tripID, phase)` activations per Reqs [1](#1-activation-notifications-fire-on-the-day-a-phase-becomes-current) and [2](#2-activation-notifications-respect-the-per-app-pending-budget), enumerate `UNUserNotificationCenter.pendingNotificationRequests`, cancel any pending request whose identifier is not in the expected set, and add requests for expected activations not present.  

### 5. Tapping a notification opens the trip with the phase expanded

**User Story:** As a user tapping a notification, I want to land on the timeline with the right phase already expanded, so I can act without extra taps.

**Acceptance Criteria:**

1. <a name="5.1"></a>WHEN the user taps an activation notification while the app is running (foreground or background), `UNUserNotificationCenterDelegate.userNotificationCenter(_:didReceive:withCompletionHandler:)` SHALL extract the `tripID` and `phase` from the notification's `userInfo` and route the app to the referenced trip's Trip Detail with the referenced phase expanded.  
2. <a name="5.2"></a>WHEN the user taps an activation notification while the app is not running, the launch SHALL queue the same route information so that once the SwiftUI scene and SwiftData containers are ready, navigation completes to the same destination as [5.1](#5.1). The queue holds at most one pending tap; later taps received before the queue is drained replace the prior entry.  
3. <a name="5.3"></a>WHEN a modal sheet (`PackingSheet`, Trip Editor, `UICloudSharingController` wrapper, country-code editor) is presented at the time the tap is received, the system SHALL dismiss the topmost sheet before routing. Sheets that were dismissed for routing SHALL NOT be re-presented after navigation completes.  
4. <a name="5.4"></a>WHEN the routed `tripID` names a trip that exists on the device, the system SHALL display its Trip Detail regardless of which screen the user was previously on. WHEN the routed `tripID` names no trip on the device, the system SHALL discard the route and SHALL NOT modify the current navigation state.  
5. <a name="5.5"></a>WHEN the routed `tripID` matches an existing trip but the routed phase is now ineligible for that trip (e.g., the user shortened the trip and the phase no longer applies), the system SHALL open the trip and apply the existing auto-expand-current-phase rule from Phase 3 instead of expanding the routed phase.  
6. <a name="5.6"></a>The `scramble://` URL scheme SHALL be registered as a custom URL type in the app's `Info.plist` so the URL embedded in `userInfo` is testable from Safari and `xcrun simctl openurl`. This is a debug/test affordance; production routing SHALL use the `userInfo` payload directly, not URL parsing.  

### 6. Country flag emoji on Trip Detail header

**User Story:** As a user, I want a visual cue of where I'm going at the top of the trip screen, so I can recognise a trip by destination at a glance.

**Acceptance Criteria:**

1. <a name="6.1"></a>The `Trip` SwiftData model SHALL gain an optional `countryCode: String?` property in the `tripsLocal`-resident schema, default `nil`, persisted on the same `Trip` record that participates in `TripSyncEngine` so the field replicates via the existing `TripRecordTranslator` (or its successor) without a new sync path.  
2. <a name="6.2"></a>A SwiftData schema migration SHALL accompany the field's introduction so existing on-device stores upgrade without data loss; the migration SHALL be a lightweight one (additive property only) and SHALL be covered by a unit test that opens a store created by the previous schema and confirms it loads with all `Trip` rows intact and `countryCode == nil`.  
3. <a name="6.3"></a>WHEN a trip has a non-nil `countryCode` matching the ISO 3166-1 alpha-2 shape (exactly two ASCII letters), the Trip Detail header SHALL render the corresponding flag emoji (derived from the two regional-indicator scalars `U+1F1E6..U+1F1FF` for the uppercase code) to the left of the trip name.  
4. <a name="6.4"></a>WHEN a trip has a `nil` or non-conforming `countryCode`, the Trip Detail header SHALL render exactly as it does today; no placeholder SHALL occupy the flag's space.  
5. <a name="6.5"></a>The Trip Editor SHALL provide a way to set and clear `countryCode`. The specific UI affordance is deferred to the design phase. The validator SHALL accept exactly two ASCII letters (case-insensitive, normalised to uppercase on save) and SHALL reject any other input — empty/clear input is treated as "set to nil", not as invalid. Validation against the ISO 3166-1 official list is non-goaled in this phase; a typo like `"XZ"` will render an empty flag rather than be rejected.  

### 7. Animated transitions on key interactions

**User Story:** As a user, I want the UI to react with motion that reinforces what just happened, so the app feels coherent rather than abrupt.

**Acceptance Criteria:**

1. <a name="7.1"></a>WHEN the user expands or collapses a phase in the timeline, the change SHALL animate via a single SwiftUI `withAnimation` block whose duration is the same constant across both directions and whose curve is non-linear (ease-in-out or system default), affecting both the spine-line height and the content area opacity/offset.  
2. <a name="7.2"></a>WHEN the user toggles a `TaskRow` or `PackingItemRow` checkbox, the checkbox SHALL animate between filled and outlined states inside a single `withAnimation` block; the row's opacity and strikethrough SHALL animate inside the same block so the visual change is atomic.  
3. <a name="7.3"></a>WHEN the `PackingSheet` is presented or dismissed, the transition SHALL use the iOS sheet-present animation with no additional overrides.  
4. <a name="7.4"></a>WHEN `accessibilityReduceMotion` is true, the transitions in [7.1](#7.1) and [7.2](#7.2) SHALL be replaced with `.opacity` cross-fades; no parallax, scale, or geometric morph SHALL be applied, and the animation duration SHALL match the non-reduce-motion path.  

### 8. Haptic feedback on five interactions

**User Story:** As a user, I want a tactile confirmation on key actions, so I feel the app's response without watching the screen.

**Acceptance Criteria:**

1. <a name="8.1"></a>WHEN the user toggles a `TaskRow` or `PackingItemRow` checkbox, the system SHALL trigger a light-impact haptic via SwiftUI's `sensoryFeedback` modifier (or `UIImpactFeedbackGenerator(style: .light)`) on the same view event that performs the toggle.  
2. <a name="8.2"></a>WHEN the user taps a `PhaseRow`, the system SHALL trigger a medium-impact haptic on the same view event that initiates expand/collapse.  
3. <a name="8.3"></a>WHEN the `PackingSheet` is presented (`.onAppear` of the sheet's root content view fires), the system SHALL trigger a soft-impact haptic.  
4. <a name="8.4"></a>WHEN the user skips or restores a packing item, the system SHALL trigger a light-impact haptic on the same view event that performs the state change.  
5. <a name="8.5"></a>WHEN the user long-presses to reveal a `WhyDisclosure`, the system SHALL trigger a light-impact haptic at the moment the disclosure becomes visible.  
6. <a name="8.6"></a>Haptic invocations SHALL use the standard `UIFeedbackGenerator`-family APIs (or their SwiftUI `sensoryFeedback` equivalent) without additional code paths to read or override system haptic settings; the suppression behaviour when the user disables system haptics is whatever those APIs natively provide.  

### 9. VoiceOver labels and a "Why is this here?" accessibility action

**User Story:** As a VoiceOver user, I want every meaningful element on the timeline and in the packing sheet to be spoken with the right label and to expose explainability without a long-press gesture, so I can use the app fluently.

**Acceptance Criteria:**

1. <a name="9.1"></a>Each `PhaseRow` SHALL expose a combined accessibility label of the form `"{phase display name}, {state description}, {N of M tasks complete}"`, where state is one of "past", "current phase", "upcoming", and the task count is omitted for phases with zero tasks. The action hint SHALL be "double tap to expand" when collapsed and "double tap to collapse" when expanded.  
2. <a name="9.2"></a>Each `TaskRow` SHALL expose a combined accessibility label that includes the task name, completion state, assigned person name (if any), and phase. The default activation SHALL toggle completion; the hint SHALL reflect the current state.  
3. <a name="9.3"></a>Each `PackingItemRow` SHALL expose a combined accessibility label that includes the item name, current `PackingState`, and owning person name. Excluded items SHALL be labelled "not bringing"; items in the repack-mode Left Behind group SHALL be labelled "left behind".  
4. <a name="9.4"></a>Each per-person packing progress bar SHALL expose `accessibilityValue` of the form `"{name}'s packing, {packed} of {total} packed"`.  
5. <a name="9.5"></a>Every `TaskRow` and `PackingItemRow` whose underlying item has a non-empty `WhyDisclosure` justification SHALL expose an accessibility custom action (`accessibilityActions { Button("Why is this here?") { … } }`) that surfaces the same disclosure content as a long-press; rows whose items are manual one-offs (`masterItemID == nil`) or otherwise have no rule justification SHALL NOT expose this action.  
6. <a name="9.6"></a>The country flag emoji from Req [6](#6-country-flag-emoji-on-trip-detail-header) SHALL be hidden from VoiceOver (`.accessibilityHidden(true)`); the trip name already carries the destination semantically.  

### 10. Dynamic Type reflow up to AX2

**User Story:** As a user with larger text settings, I want trip and packing screens to remain usable at AX2, so I can read and act on every element without truncation.

**Acceptance Criteria:**

1. <a name="10.1"></a>WHEN the device's content size category is any value from `.xSmall` through `.accessibilityMedium` (AX2), the Trip List, Trip Detail timeline (each of the seven phases expanded individually), Trip Editor, Master Lists, and `PackingSheet` (both pack and repack modes) SHALL render on iPhone SE 3rd gen (smallest supported simulator) with every interactive element fully visible — no clipping, no truncation that loses required text content (action labels, task names, person names, item names, counts), and no positioning outside the visible safe area beyond the layout's existing scrollable regions.  
2. <a name="10.2"></a>Phase node diameter SHALL remain fixed across content size categories (per UI design doc §"Dynamic Type"); surrounding text SHALL scale around it.  
3. <a name="10.3"></a>WHEN a `TaskRow` or `PackingItemRow` label exceeds one line at the current content size category, the row SHALL grow vertically rather than truncate, and the checkbox SHALL remain top-aligned with the first line of the label.  
4. <a name="10.4"></a>All interactive elements SHALL retain a minimum 44pt × 44pt hit target regardless of content size category, using invisible padding where the visual size is smaller.  
5. <a name="10.5"></a>An AX5 sanity pass SHALL be performed on the same surfaces as [10.1](#10.1); any layout failures discovered SHALL be recorded in `specs/phase-6-notifications-polish/implementation.md` as known limitations under a "Known limitations at AX5" heading. The pass itself is a one-time verification — it is not an ongoing acceptance criterion.  
