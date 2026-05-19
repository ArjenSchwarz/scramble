---
references:
    - specs/phase-6-notifications-polish/requirements.md
    - specs/phase-6-notifications-polish/design.md
    - specs/phase-6-notifications-polish/decision_log.md
---
# Phase 6 — Notifications + Polish

## Phase 1: Schema V4 + Trip model

- [x] 1. [test] TripRecordTranslator round-trips countryCode (set, unset, toggle) <!-- id:mwaej38 -->
  - Stream: 1
  - Requirements: [5.5](requirements.md#5.5), [6.1](requirements.md#6.1), [6.5](requirements.md#6.5)

- [x] 2. Add countryCode property on Trip, define SchemaV4, register V3→V4 lightweight migration, update TripRecordTranslator encode/decode <!-- id:mwaej39 -->
  - Blocked-by: mwaej38 ([test] TripRecordTranslator round-trips countryCode (set, unset, toggle))
  - Stream: 1
  - Requirements: [6.1](requirements.md#6.1), [6.2](requirements.md#6.2), [6.5](requirements.md#6.5)

- [x] 3. [test] V3→V4 lightweight migration preserves existing trips and sets countryCode = nil on both containers <!-- id:mwaej3a -->
  - Blocked-by: mwaej39 (Add countryCode property on Trip, define SchemaV4, register V3→V4 lightweight migration, update TripRecordTranslator encode/decode)
  - Stream: 1
  - Requirements: [6.2](requirements.md#6.2)

## Phase 2: Notification pure primitives

- [x] 4. [test] NotificationIdentifier round-trip + parse rejects malformed inputs <!-- id:mwaej3b -->
  - Stream: 2
  - Requirements: [2.3](requirements.md#2.3), [2.4](requirements.md#2.4)

- [x] 5. Implement NotificationIdentifier.make / parse / threadID <!-- id:mwaej3c -->
  - Blocked-by: mwaej3b ([test] NotificationIdentifier round-trip + parse rejects malformed inputs)
  - Stream: 2
  - Requirements: [2.3](requirements.md#2.3), [2.4](requirements.md#2.4)

- [x] 6. [test] NotificationPlanner table-driven cases: eligibility, past-day skip, ordering, 60-cap, tie-break, body text <!-- id:mwaej3d -->
  - Stream: 2
  - Requirements: [1.2](requirements.md#1.2), [1.4](requirements.md#1.4), [1.5](requirements.md#1.5), [2.1](requirements.md#2.1), [2.2](requirements.md#2.2)

- [x] 7. [test] NotificationPlanner property test: no plan has fire-date ≤ now's calendar day <!-- id:mwaej3e -->
  - Stream: 2
  - Requirements: [1.5](requirements.md#1.5)

- [x] 8. Implement NotificationPlanner.plan + body helper <!-- id:mwaej3f -->
  - Blocked-by: mwaej3d ([test] NotificationPlanner table-driven cases: eligibility, past-day skip, ordering, 60-cap, tie-break, body text), mwaej3e ([test] NotificationPlanner property test: no plan has fire-date ≤ now's calendar day)
  - Stream: 2
  - Requirements: [1.1](requirements.md#1.1), [1.2](requirements.md#1.2), [1.4](requirements.md#1.4), [1.5](requirements.md#1.5), [2.1](requirements.md#2.1), [2.2](requirements.md#2.2)

- [x] 9. [test] NotificationReconciler diff: add/remove/no-op including body-match no-op detection <!-- id:mwaej3g -->
  - Blocked-by: mwaej3f (Implement NotificationPlanner.plan + body helper)
  - Stream: 2
  - Requirements: [2.3](requirements.md#2.3)

- [x] 10. Implement NotificationReconciler.diff <!-- id:mwaej3h -->
  - Blocked-by: mwaej3g ([test] NotificationReconciler diff: add/remove/no-op including body-match no-op detection)
  - Stream: 2
  - Requirements: [2.3](requirements.md#2.3)

## Phase 3: Notification service + router + broadcaster

- [x] 11. Define NotificationCenterProtocol and UNUserNotificationCenter conformance extension <!-- id:mwaej3i -->
  - Blocked-by: mwaej3h (Implement NotificationReconciler.diff)
  - Stream: 2
  - Requirements: [1.1](requirements.md#1.1), [1.3](requirements.md#1.3), [2.3](requirements.md#2.3), [3.1](requirements.md#3.1)

- [x] 12. [test] StubNotificationCenter records calls; production conformance bridges to UNUserNotificationCenter <!-- id:mwaej3j -->
  - Blocked-by: mwaej3i (Define NotificationCenterProtocol and UNUserNotificationCenter conformance extension)
  - Stream: 2
  - Requirements: [1.1](requirements.md#1.1)

- [x] 13. [test] PendingChangeBroadcaster forwards to all children in registration order; one child throwing does not block others <!-- id:mwaej3k -->
  - Stream: 2
  - Requirements: [1.1](requirements.md#1.1), [4.3](requirements.md#4.3), [4.4](requirements.md#4.4)

- [x] 14. Implement PendingChangeBroadcaster <!-- id:mwaej3l -->
  - Blocked-by: mwaej3k ([test] PendingChangeBroadcaster forwards to all children in registration order; one child throwing does not block others)
  - Stream: 2
  - Requirements: [4.3](requirements.md#4.3), [4.4](requirements.md#4.4)

- [x] 15. [test] NotificationRouter consumeRoute is atomic; willPresent returns [.banner, .sound]; userInfo extraction handles malformed payload <!-- id:mwaej3m -->
  - Stream: 2
  - Requirements: [1.3](requirements.md#1.3), [5.1](requirements.md#5.1), [5.2](requirements.md#5.2)

- [x] 16. Implement NotificationRouter (@Observable, UNUserNotificationCenterDelegate, async willPresent/didReceive) <!-- id:mwaej3n -->
  - Blocked-by: mwaej3m ([test] NotificationRouter consumeRoute is atomic; willPresent returns [.banner, .sound]; userInfo extraction handles malformed payload)
  - Stream: 2
  - Requirements: [1.3](requirements.md#1.3), [5.1](requirements.md#5.1), [5.2](requirements.md#5.2)

- [x] 17. [test] NotificationsService — coalesce window collapses bursts; immediate-flush reasons (.tripDeleted, .scenePhaseBackground, .authChanged, .appActivation) bypass coalesce; auth gate + backfill; trip-delete cancels pending and removes delivered <!-- id:mwaej3o -->
  - Blocked-by: mwaej3h (Implement NotificationReconciler.diff), mwaej3i (Define NotificationCenterProtocol and UNUserNotificationCenter conformance extension), mwaej3l (Implement PendingChangeBroadcaster), mwaej3n (Implement NotificationRouter (@Observable, UNUserNotificationCenterDelegate, async willPresent/didReceive))
  - Stream: 2
  - Requirements: [1.6](requirements.md#1.6), [3.1](requirements.md#3.1), [3.3](requirements.md#3.3), [3.4](requirements.md#3.4), [3.6](requirements.md#3.6), [4.1](requirements.md#4.1), [4.2](requirements.md#4.2), [4.3](requirements.md#4.3), [4.4](requirements.md#4.4), [4.5](requirements.md#4.5)

- [x] 18. Implement NotificationsService (PendingChangeNotifier conformance, ReschedReason dispatch, coalesce task, requestAuthorizationIfNeeded, handleScenePhase, reconcile loop) <!-- id:mwaej3p -->
  - Blocked-by: mwaej3o ([test] NotificationsService — coalesce window collapses bursts; immediate-flush reasons (.tripDeleted, .scenePhaseBackground, .authChanged, .appActivation) bypass coalesce; auth gate + backfill; trip-delete cancels pending and removes delivered), cancels, pending, removes, cancels, pending, removes, cancels, pending, removes, cancels, pending, removes, cancels, pending, removes, cancels, pending, removes, cancels, pending, removes, cancels, pending, removes, cancels, pending, removes, cancels, pending, removes, cancels, pending, removes, cancels, pending, removes, cancels, pending, removes, cancels, pending, removes, cancels, pending, removes, cancels, pending, removes, cancels, pending, removes, cancels, pending, removes, cancels, pending, removes, cancels, pending, removes, cancels, pending, removes, cancels, pending, removes, cancels, pending, removes, cancels, pending, removes, cancels, pending, removes, cancels, pending, removes, cancels, pending, removes, cancels, pending, removes, cancels, pending, removes, cancels, pending, removes, cancels, pending, removes, cancels, pending, removes, cancels, pending, removes, cancels, pending, removes, cancels, pending, removes, cancels, pending, removes, cancels, pending, removes, cancels, pending, removes, cancels, pending, removes, cancels, pending, removes, cancels, pending, removes, cancels, pending, removes, cancels, pending, removes, cancels, pending, removes, cancels, pending, removes, cancels, pending, removes
  - Stream: 2
  - Requirements: [1.1](requirements.md#1.1), [1.6](requirements.md#1.6), [3.1](requirements.md#3.1), [3.3](requirements.md#3.3), [3.4](requirements.md#3.4), [3.6](requirements.md#3.6), [4.1](requirements.md#4.1), [4.2](requirements.md#4.2), [4.3](requirements.md#4.3), [4.4](requirements.md#4.4), [4.5](requirements.md#4.5)

## Phase 4: App-level wiring

- [x] 19. Extend AppDelegate.Environment with notificationRouter slot; install UNUserNotificationCenter.delegate in ScrambleApp.init <!-- id:mwaej3q -->
  - Blocked-by: mwaej3n (Implement NotificationRouter (@Observable, UNUserNotificationCenterDelegate, async willPresent/didReceive))
  - Stream: 2
  - Requirements: [5.1](requirements.md#5.1), [5.2](requirements.md#5.2)

- [x] 20. Wire PendingChangeBroadcaster(children: [tripSyncEngine, notificationsService]) into LocalWriteHook construction in ScrambleApp <!-- id:mwaej3r -->
  - Blocked-by: mwaej3l (Implement PendingChangeBroadcaster), mwaej3p (Implement NotificationsService (PendingChangeNotifier conformance, ReschedReason dispatch, coalesce task, requestAuthorizationIfNeeded, handleScenePhase, reconcile loop))
  - Stream: 2
  - Requirements: [4.3](requirements.md#4.3), [4.4](requirements.md#4.4)

- [x] 21. Add ScenePhase observer at WindowGroup level → notificationsService.handleScenePhase(previous:current:) <!-- id:mwaej3s -->
  - Blocked-by: mwaej3p (Implement NotificationsService (PendingChangeNotifier conformance, ReschedReason dispatch, coalesce task, requestAuthorizationIfNeeded, handleScenePhase, reconcile loop))
  - Stream: 2
  - Requirements: [3.6](requirements.md#3.6), [4.5](requirements.md#4.5)

- [x] 22. Add onOpenURL handler in ScrambleApp parsing scramble://trip/<UUID>?phase=<raw> into NotificationRouter.enqueue; register scramble URL scheme in Info.plist <!-- id:mwaej3t -->
  - Blocked-by: mwaej3n (Implement NotificationRouter (@Observable, UNUserNotificationCenterDelegate, async willPresent/didReceive))
  - Stream: 2
  - Requirements: [5.6](requirements.md#5.6)

- [x] 23. Call notificationsService.requestAuthorizationIfNeeded in TripListView's create onSave closure (TripListView.swift:99) <!-- id:mwaej3u -->
  - Blocked-by: mwaej3p (Implement NotificationsService (PendingChangeNotifier conformance, ReschedReason dispatch, coalesce task, requestAuthorizationIfNeeded, handleScenePhase, reconcile loop))
  - Stream: 2
  - Requirements: [3.1](requirements.md#3.1), [3.2](requirements.md#3.2), [3.3](requirements.md#3.3)

- [x] 24. Call notificationsService.requestReschedule(.tripDeleted(tripID)) inside TripDeletion.delete after commitDeletion succeeds <!-- id:mwaej3v -->
  - Blocked-by: mwaej3p (Implement NotificationsService (PendingChangeNotifier conformance, ReschedReason dispatch, coalesce task, requestAuthorizationIfNeeded, handleScenePhase, reconcile loop))
  - Stream: 2
  - Requirements: [4.2](requirements.md#4.2)

- [x] 25. Add 'Open Settings' affordance reading NotificationsService.authStatus; shown when authStatus == .denied on a Trips-tab surface the user already visits (Trip List or Trip Detail). Tap calls UIApplication.shared.open(openSettingsURLString). <!-- id:mwaej4q -->
  - Blocked-by: mwaej3p (Implement NotificationsService (PendingChangeNotifier conformance, ReschedReason dispatch, coalesce task, requestAuthorizationIfNeeded, handleScenePhase, reconcile loop))
  - Stream: 2
  - Requirements: [3.5](requirements.md#3.5)

## Phase 5: Routing state machine

- [x] 26. [test] RootView routing state machine: pendingRoute → dismissingSheets → navigating; nonexistent trip drops route; ineligible phase falls back to autoExpandPhase <!-- id:mwaej3w -->
  - Blocked-by: mwaej3n (Implement NotificationRouter (@Observable, UNUserNotificationCenterDelegate, async willPresent/didReceive))
  - Stream: 2
  - Requirements: [5.1](requirements.md#5.1), [5.2](requirements.md#5.2), [5.3](requirements.md#5.3), [5.4](requirements.md#5.4), [5.5](requirements.md#5.5)

- [x] 27. Implement RoutingState on RootView, observe NotificationRouter.pendingRoute, dismiss SwiftUI sheet bindings + UICloudSharingController via dismiss(animated:false), one Task.yield before navigating <!-- id:mwaej3x -->
  - Blocked-by: mwaej3w ([test] RootView routing state machine: pendingRoute → dismissingSheets → navigating; nonexistent trip drops route; ineligible phase falls back to autoExpandPhase)
  - Stream: 2
  - Requirements: [5.1](requirements.md#5.1), [5.2](requirements.md#5.2), [5.3](requirements.md#5.3), [5.4](requirements.md#5.4), [5.5](requirements.md#5.5)

## Phase 6: Country flag UI

- [x] 28. [test] CountryFlag.emoji: valid alpha-2 returns flag emoji; nil / wrong length / non-letters returns nil <!-- id:mwaej3y -->
  - Stream: 3
  - Requirements: [6.3](requirements.md#6.3), [6.4](requirements.md#6.4)

- [x] 29. Implement CountryFlag.emoji via regional-indicator scalar arithmetic <!-- id:mwaej3z -->
  - Blocked-by: mwaej3y ([test] CountryFlag.emoji: valid alpha-2 returns flag emoji; nil / wrong length / non-letters returns nil)
  - Stream: 3
  - Requirements: [6.3](requirements.md#6.3)

- [x] 30. Render flag emoji to the left of trip name on Trip Detail header; hidden from VoiceOver <!-- id:mwaej40 -->
  - Blocked-by: mwaej39 (Add countryCode property on Trip, define SchemaV4, register V3→V4 lightweight migration, update TripRecordTranslator encode/decode), mwaej3z (Implement CountryFlag.emoji via regional-indicator scalar arithmetic)
  - Stream: 3
  - Requirements: [6.2](requirements.md#6.2), [6.4](requirements.md#6.4), [9.6](requirements.md#9.6)

- [x] 31. [test] TripEditor country-code field: accepts two ASCII letters, normalises to uppercase on save, rejects other input, empty clears countryCode <!-- id:mwaej41 -->
  - Stream: 3
  - Requirements: [6.5](requirements.md#6.5)

- [x] 32. Add country-code text field + live flag preview to TripEditorView <!-- id:mwaej42 -->
  - Blocked-by: mwaej39 (Add countryCode property on Trip, define SchemaV4, register V3→V4 lightweight migration, update TripRecordTranslator encode/decode), mwaej3z (Implement CountryFlag.emoji via regional-indicator scalar arithmetic), mwaej41 ([test] TripEditor country-code field: accepts two ASCII letters, normalises to uppercase on save, rejects other input, empty clears countryCode)
  - Stream: 3
  - Requirements: [6.5](requirements.md#6.5)

## Phase 7: Polish — animations

- [x] 33. Add Animation.scrambleStandard constant in Theme/Animations.swift <!-- id:mwaej43 -->
  - Stream: 4
  - Requirements: [7.1](requirements.md#7.1)

- [x] 34. [test] Accordion expand/collapse uses single withAnimation block; reduce-motion swaps to opacity cross-fade <!-- id:mwaej44 -->
  - Blocked-by: mwaej43 (Add Animation.scrambleStandard constant in Theme/Animations.swift)
  - Stream: 4
  - Requirements: [7.1](requirements.md#7.1), [7.4](requirements.md#7.4)

- [x] 35. Wrap AccordionTimeline phase toggle in withAnimation(.scrambleStandard); read accessibilityReduceMotion to swap to .opacity transition <!-- id:mwaej45 -->
  - Blocked-by: mwaej43 (Add Animation.scrambleStandard constant in Theme/Animations.swift), mwaej44 ([test] Accordion expand/collapse uses single withAnimation block; reduce-motion swaps to opacity cross-fade)
  - Stream: 4
  - Requirements: [7.1](requirements.md#7.1), [7.4](requirements.md#7.4)

- [x] 36. [test] TaskRow + PackingItemRow checkbox toggle animates fill↔outline and row opacity/strikethrough atomically <!-- id:mwaej46 -->
  - Blocked-by: mwaej43 (Add Animation.scrambleStandard constant in Theme/Animations.swift)
  - Stream: 4
  - Requirements: [7.2](requirements.md#7.2), [7.4](requirements.md#7.4)

- [x] 37. Wrap TaskRow and PackingItemRow checkbox toggle in withAnimation(.scrambleStandard); apply reduce-motion swap <!-- id:mwaej47 -->
  - Blocked-by: mwaej43 (Add Animation.scrambleStandard constant in Theme/Animations.swift), mwaej46 ([test] TaskRow + PackingItemRow checkbox toggle animates fill↔outline and row opacity/strikethrough atomically)
  - Stream: 4
  - Requirements: [7.2](requirements.md#7.2), [7.4](requirements.md#7.4)

## Phase 8: Polish — haptics

- [x] 38. Add sensoryFeedback(.impact(weight:.light)) modifier on TaskRow checkbox toggle and on PackingItemRow checkbox + skip/restore action events <!-- id:mwaej48 -->
  - Stream: 5
  - Requirements: [8.1](requirements.md#8.1), [8.4](requirements.md#8.4)

- [x] 39. Add sensoryFeedback(.impact(weight:.medium)) on PhaseRow tap <!-- id:mwaej49 -->
  - Stream: 5
  - Requirements: [8.2](requirements.md#8.2)

- [x] 40. Add sensoryFeedback(.impact(weight:.soft)) on PackingSheet root .onAppear <!-- id:mwaej4a -->
  - Stream: 5
  - Requirements: [8.3](requirements.md#8.3)

- [x] 41. Add sensoryFeedback(.impact(weight:.light)) when WhyDisclosure becomes visible (on isDisclosureOpen toggle) <!-- id:mwaej4b -->
  - Stream: 5
  - Requirements: [8.5](requirements.md#8.5)

## Phase 9: Polish — VoiceOver

- [ ] 42. [test] PhaseRow accessibility label: '{display name}, {state}, {N of M tasks complete}'; hint reflects expand/collapse state <!-- id:mwaej4c -->
  - Stream: 6
  - Requirements: [9.1](requirements.md#9.1)

- [ ] 43. Update PhaseRow combined accessibility label + dynamic hint <!-- id:mwaej4d -->
  - Blocked-by: mwaej4c ([test] PhaseRow accessibility label: '{display name}, {state}, {N of M tasks complete}'; hint reflects expand/collapse state)
  - Stream: 6
  - Requirements: [9.1](requirements.md#9.1)

- [ ] 44. [test] TaskRow accessibility label includes name + completion + assignee + phase; custom 'Why is this here?' accessibility action present only when justification is non-nil <!-- id:mwaej4e -->
  - Stream: 6
  - Requirements: [9.2](requirements.md#9.2), [9.5](requirements.md#9.5)

- [ ] 45. Update TaskRow combined label + accessibilityActions { Button("Why is this here?") }, gated by WhyResolver result <!-- id:mwaej4f -->
  - Blocked-by: mwaej4e ([test] TaskRow accessibility label includes name + completion + assignee + phase; custom 'Why is this here?' accessibility action present only when justification is non-nil)
  - Stream: 6
  - Requirements: [9.2](requirements.md#9.2), [9.5](requirements.md#9.5)

- [ ] 46. [test] PackingItemRow accessibility label includes name + state + owner; 'not bringing' / 'left behind' labels for excluded and Left Behind groups; Why action gated by justification <!-- id:mwaej4g -->
  - Stream: 6
  - Requirements: [9.3](requirements.md#9.3), [9.5](requirements.md#9.5)

- [ ] 47. Update PackingItemRow combined label + Why custom action across pack and repack modes <!-- id:mwaej4h -->
  - Blocked-by: mwaej4g ([test] PackingItemRow accessibility label includes name + state + owner; 'not bringing' / 'left behind' labels for excluded and Left Behind groups; Why action gated by justification)
  - Stream: 6
  - Requirements: [9.3](requirements.md#9.3), [9.5](requirements.md#9.5)

- [ ] 48. [test] Per-person packing progress bar accessibilityValue: '{name}'s packing, {packed} of {total} packed' <!-- id:mwaej4i -->
  - Stream: 6
  - Requirements: [9.4](requirements.md#9.4)

- [ ] 49. Update PackingSummarySection progress bar accessibilityValue <!-- id:mwaej4j -->
  - Blocked-by: mwaej4i ([test] Per-person packing progress bar accessibilityValue: '{name}'s packing, {packed} of {total} packed')
  - Stream: 6
  - Requirements: [9.4](requirements.md#9.4)

## Phase 10: Polish — Dynamic Type

- [ ] 50. [test] Snapshot or layout-assertion tests across xSmall → AX2 on Trip List, Trip Detail (each phase expanded), Trip Editor, Master Lists, PackingSheet on iPhone SE <!-- id:mwaej4k -->
  - Stream: 7
  - Requirements: [10.1](requirements.md#10.1), [10.3](requirements.md#10.3)

- [ ] 51. Apply AX2 reflow fixes: label wrapping, top-aligned checkbox on multi-line rows, invisible-padding hit targets, fixed phase-node diameter <!-- id:mwaej4l -->
  - Blocked-by: mwaej4k ([test] Snapshot or layout-assertion tests across xSmall → AX2 on Trip List, Trip Detail (each phase expanded), Trip Editor, Master Lists, PackingSheet on iPhone SE)
  - Stream: 7
  - Requirements: [10.1](requirements.md#10.1), [10.2](requirements.md#10.2), [10.3](requirements.md#10.3), [10.4](requirements.md#10.4)

- [ ] 52. Run AX5 sanity pass and append 'Known limitations at AX5' section to specs/phase-6-notifications-polish/implementation.md <!-- id:mwaej4m -->
  - Blocked-by: mwaej4l (Apply AX2 reflow fixes: label wrapping, top-aligned checkbox on multi-line rows, invisible-padding hit targets, fixed phase-node diameter)
  - Stream: 7
  - Requirements: [10.5](requirements.md#10.5)

## Phase 11: Documentation

- [x] 53. Add docs/agent-notes/notifications.md (service topology, broadcaster, identifier scheme, 60-cap, deep-link routing, foreground delivery) <!-- id:mwaej4n -->
  - Blocked-by: mwaej3p (Implement NotificationsService (PendingChangeNotifier conformance, ReschedReason dispatch, coalesce task, requestAuthorizationIfNeeded, handleScenePhase, reconcile loop)), mwaej3w ([test] RootView routing state machine: pendingRoute → dismissingSheets → navigating; nonexistent trip drops route; ineligible phase falls back to autoExpandPhase)
  - Stream: 8
  - Requirements: [1.1](requirements.md#1.1), [2.3](requirements.md#2.3), [5.1](requirements.md#5.1)

- [x] 54. Add docs/agent-notes/accessibility.md (VoiceOver label conventions, custom actions, Dynamic Type AX2 boundaries, AX5 known limitations link) <!-- id:mwaej4o -->
  - Blocked-by: mwaej4i ([test] Per-person packing progress bar accessibilityValue: '{name}'s packing, {packed} of {total} packed'), mwaej4l (Apply AX2 reflow fixes: label wrapping, top-aligned checkbox on multi-line rows, invisible-padding hit targets, fixed phase-node diameter)
  - Stream: 8
  - Requirements: [9.1](requirements.md#9.1), [9.5](requirements.md#9.5), [10.5](requirements.md#10.5)

- [x] 55. Update CHANGELOG.md and CLAUDE.md project-status sentence to mark Phase 6 shipped <!-- id:mwaej4p -->
  - Blocked-by: mwaej4l (Apply AX2 reflow fixes: label wrapping, top-aligned checkbox on multi-line rows, invisible-padding hit targets, fixed phase-node diameter), mwaej4m (Run AX5 sanity pass and append 'Known limitations at AX5' section to specs/phase-6-notifications-polish/implementation.md), mwaej4n (Add docs/agent-notes/notifications.md (service topology, broadcaster, identifier scheme, 60-cap, deep-link routing, foreground delivery)), service, routing, service, routing, service, routing, service, routing, service, routing, service, routing, service, routing, service, routing, service, routing, service, routing, service, routing, service, routing, service, routing, service, routing, service, routing, service, routing, service, routing, service, routing, service, routing, service, routing, service, routing, service, routing, service, routing, service, routing, service, routing, service, routing, service, routing, service, routing, service, routing, service, routing, service, routing, service, routing, service, routing, service, routing, service, routing, service, routing, service, routing, service, routing, service, routing, service, routing, service, routing, service, routing, service, routing, service, routing, service, routing, service, routing
  - Stream: 8
