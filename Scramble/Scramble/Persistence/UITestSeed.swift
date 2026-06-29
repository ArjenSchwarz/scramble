#if DEBUG
  import Foundation
  import SwiftData

  /// Pre-seeds the in-memory `ModelContainer` with a known fixture before the
  /// SwiftUI view tree first renders. Triggered by the launch argument
  /// `-seed-fixture <name>` set on `XCUIApplication.launchArguments` by UI tests.
  ///
  /// Only compiled in DEBUG builds; production binaries cannot be seeded.
  @MainActor
  enum UITestSeed {
    static let launchArgKey = UITestArguments.seedFixtureKey

    enum Fixture: String {
      case oneQualifyingTrip = "one-qualifying-trip"
      case oneNonQualifyingTrip = "one-non-qualifying-trip"
      case twoQualifyingTrips = "two-qualifying-trips"
      case singleEditableTrip = "single-editable-trip"
      case masterListsEmptyWithPerson = "master-lists-empty-with-person"
      /// Copy feature: two people ("Alex" owns a "Socks" master packing item,
      /// "Sam" owns nothing) so the per-row "Copy to people…" action is eligible
      /// (>= 2 people) and Sam is an eligible copy target.
      case masterPackingCopyTwoPeople = "master-packing-copy-two-people"
      case masterTaskAdvancedConditions = "master-task-advanced-conditions"
      case phase2RulesFixture = "phase2-rules-fixture"
      case phase2RulesFixtureSunTrip = "phase2-rules-fixture-sun-trip"
      case phase2RulesColdLaunch = "phase2-rules-cold-launch"
      case personWithMasterPackingOnly = "person-with-master-packing-only"
      /// Phase 5: owner-side shared trip with two participants — one
      /// pending invite ("alice@example.com"), one accepted ("Bob").
      /// Use to assert Share toolbar button visible + Participants
      /// section pending/accepted distinction.
      case phase5SharedTripOwner = "phase5-shared-trip-owner"
      /// Phase 5: participant-side shared trip. Share button hidden;
      /// Participants section read-only. Trip's `TripZoneState`
      /// reports `zoneOwnerName != CKCurrentUserDefaultName`.
      case phase5SharedTripParticipant = "phase5-shared-trip-participant"
      /// Phase 5: Trip List with one trip whose `MigrationJournalEntry`
      /// is `.failed` (retry banner visible) and one whose entry is
      /// `.stageBInProgress` (Syncing badge visible).
      case phase5MigrationStates = "phase5-migration-states"
      /// Phase 3: trip currently in `.duringTrip` with one manual task in
      /// `.duringTrip` and one rule-driven task in `.dayBefore`. The trip
      /// auto-opens (single qualifying trip; today is mid-trip).
      case phase3TripWithTasks = "phase3-trip-with-tasks"
      /// Phase 3: one-day trip (start == end) so `.duringTrip` compresses.
      case phase3OneDayTrip = "phase3-one-day-trip"
      /// Phase 3: trip with no participants for the assignee-picker placeholder.
      case phase3TripNoParticipants = "phase3-trip-no-participants"
      /// Phase 4: trip currently on `.dayBefore` (today == start - 1, end ==
      /// today+6) with two participants and a mix of packing item states. Used
      /// by pack-mode UI tests covering the summary block, sheet groups,
      /// checkbox toggle, Skip/Restore, manual add, and dimmed-row counting
      /// (including rule-driven items).
      case phase4PackModeTrip = "phase4-pack-mode-trip"
      /// Phase 4: trip currently on `.dayBeforeReturn` (today == end-1, start
      /// == today-3) with two participants and a mix of packed/repacked/
      /// unpacked/excluded items. Used by repack-mode UI tests covering the
      /// "Left behind" group and read-only checkboxes.
      case phase4RepackModeTrip = "phase4-repack-mode-trip"
    }

    static func applyIfRequested(
      to container: ModelContainer,
      arguments: [String] = ProcessInfo.processInfo.arguments,
      today: Date = .now,
      calendar: Calendar = .current
    ) {
      guard let fixture = parseFixture(from: arguments) else { return }
      seed(fixture: fixture, in: container.mainContext, today: today, calendar: calendar)
    }

    /// Dual-container variant added in Phase 5. Phase 5 fixtures touch
    /// both the globals container (`MigrationJournalEntry`) and the
    /// tripsLocal container (`Trip`, `TripZoneState`); legacy fixtures
    /// continue to seed into globals only.
    static func applyIfRequested(
      globalsContainer: ModelContainer,
      tripsLocalContainer: ModelContainer,
      arguments: [String] = ProcessInfo.processInfo.arguments,
      today: Date = .now,
      calendar: Calendar = .current
    ) {
      guard let fixture = parseFixture(from: arguments) else { return }
      UITestSharingService.reset()
      switch fixture {
      case .phase5SharedTripOwner,
        .phase5SharedTripParticipant,
        .phase5MigrationStates:
        seedPhase5(
          fixture: fixture,
          globalsContext: globalsContainer.mainContext,
          tripsLocalContext: tripsLocalContainer.mainContext,
          day: calendar.startOfDay(for: today),
          calendar: calendar
        )
      default:
        seed(
          fixture: fixture,
          in: globalsContainer.mainContext,
          today: today,
          calendar: calendar
        )
      }
    }

    static func parseFixture(from arguments: [String]) -> Fixture? {
      guard let idx = arguments.firstIndex(of: launchArgKey) else { return nil }
      let next = arguments.index(after: idx)
      guard next < arguments.endIndex else { return nil }
      return Fixture(rawValue: arguments[next])
    }

    // swiftlint:disable:next function_body_length
    static func seed(
      fixture: Fixture,
      in context: ModelContext,
      today: Date,
      calendar: Calendar
    ) {
      let day = calendar.startOfDay(for: today)
      switch fixture {
      case .oneQualifyingTrip:
        context.insert(
          Trip(
            name: "Active Trip",
            startDate: day,
            endDate: calendar.date(byAdding: .day, value: 5, to: day) ?? day
          )
        )
      case .oneNonQualifyingTrip:
        let start = calendar.date(byAdding: .day, value: 30, to: day) ?? day
        let end = calendar.date(byAdding: .day, value: 35, to: day) ?? day
        context.insert(Trip(name: "Future Trip", startDate: start, endDate: end))
      case .twoQualifyingTrips:
        context.insert(
          Trip(
            name: "Trip A",
            startDate: day,
            endDate: calendar.date(byAdding: .day, value: 5, to: day) ?? day
          )
        )
        context.insert(
          Trip(
            name: "Trip B",
            startDate: calendar.date(byAdding: .day, value: 1, to: day) ?? day,
            endDate: calendar.date(byAdding: .day, value: 10, to: day) ?? day
          )
        )
      case .singleEditableTrip:
        // Far-future start so this trip never auto-opens (start > today + 2 days),
        // letting the CRUD tests start from the Trip List and tap into detail
        // explicitly.
        let start = calendar.date(byAdding: .day, value: 30, to: day) ?? day
        let end = calendar.date(byAdding: .day, value: 35, to: day) ?? day
        context.insert(Trip(name: "Sample Trip", startDate: start, endDate: end))
      case .masterListsEmptyWithPerson,
        .masterPackingCopyTwoPeople,
        .masterTaskAdvancedConditions,
        .phase2RulesFixture,
        .phase2RulesFixtureSunTrip,
        .phase2RulesColdLaunch,
        .personWithMasterPackingOnly:
        seedPhase2(fixture: fixture, in: context, day: day, calendar: calendar)
      case .phase3TripWithTasks,
        .phase3OneDayTrip,
        .phase3TripNoParticipants:
        seedPhase3(fixture: fixture, in: context, day: day, calendar: calendar)
      case .phase4PackModeTrip,
        .phase4RepackModeTrip:
        seedPhase4(fixture: fixture, in: context, day: day, calendar: calendar)
      case .phase5SharedTripOwner,
        .phase5SharedTripParticipant,
        .phase5MigrationStates:
        // Phase 5 fixtures require the dual-container entry point; the
        // legacy single-container call is treated as a no-op here so the
        // pre-Phase-5 fixtures keep working. The `applyIfRequested`
        // overload that takes both containers is the supported path.
        break
      }
      try? context.save()
    }

    // swiftlint:disable:next function_body_length
    private static func seedPhase2(
      fixture: Fixture,
      in context: ModelContext,
      day: Date,
      calendar: Calendar
    ) {
      switch fixture {
      case .masterListsEmptyWithPerson:
        let alex = Person(name: "Alex", colorKey: "blue")
        context.insert(alex)
        // Seeded item lets packing CRUD tests exercise edit + delete paths
        // without driving the Picker(.menu) UI (XCTest can't open it reliably
        // under iOS 26); MasterPersistenceTests covers the create path.
        context.insert(
          MasterPackingItem(name: "Seeded item", person: alex, conditions: .always)
        )
      case .masterPackingCopyTwoPeople:
        // Two people so the copy action is eligible (Req 1.3 needs >= 2).
        // Alex owns "Socks"; Sam owns nothing → Sam is an eligible target.
        let alex = Person(name: "Alex", colorKey: "blue")
        let sam = Person(name: "Sam", colorKey: "red")
        context.insert(alex)
        context.insert(sam)
        context.insert(
          MasterPackingItem(name: "Socks", person: alex, conditions: .always)
        )
      case .masterTaskAdvancedConditions:
        // Out-of-domain weather value forces AdvancedConditionView per AC 3.7a.
        context.insert(Person(name: "Alex", colorKey: "blue"))
        context.insert(
          MasterTaskItem(
            name: "Snow boots check",
            phase: .weeksBefore,
            conditions: .all([.match(attribute: .weather, anyOf: ["snow"])])
          )
        )
      case .phase2RulesFixture:
        let person = Person(name: "Alex", colorKey: "blue")
        context.insert(person)
        context.insert(
          MasterPackingItem(
            name: "Rain jacket",
            person: person,
            conditions: .all([.match(attribute: .weather, anyOf: ["rain"])])
          )
        )
      case .phase2RulesFixtureSunTrip:
        let person = Person(name: "Alex", colorKey: "blue")
        context.insert(person)
        context.insert(
          MasterPackingItem(
            name: "Rain jacket",
            person: person,
            conditions: .all([.match(attribute: .weather, anyOf: ["rain"])])
          )
        )
        var attrs = TripAttributes()
        attrs.toggle(.weather, value: "sun")
        let start = calendar.date(byAdding: .day, value: 30, to: day) ?? day
        let end = calendar.date(byAdding: .day, value: 35, to: day) ?? day
        context.insert(
          Trip(name: "Sunny Trip", startDate: start, endDate: end, attributes: attrs)
        )
      case .phase2RulesColdLaunch:
        // Qualifying trip + always-matching master proves ScrambleApp.init()
        // scan finishes before TripsTab's auto-open task fires.
        context.insert(
          Trip(
            name: "Active Trip",
            startDate: day,
            endDate: calendar.date(byAdding: .day, value: 5, to: day) ?? day
          )
        )
        context.insert(
          MasterTaskItem(name: "Charge devices", phase: .dayBefore, conditions: .always)
        )
      case .personWithMasterPackingOnly:
        // Person owns one MasterPackingItem AND zero TripPackingItem refs,
        // plus an editable trip so PersonDeleteBlocker can surface the
        // master-list reference (Phase 2 contribution to AC 8.2).
        let person = Person(name: "Alex", colorKey: "blue")
        context.insert(person)
        context.insert(
          MasterPackingItem(name: "Toothbrush", person: person, conditions: .always)
        )
        let start = calendar.date(byAdding: .day, value: 30, to: day) ?? day
        let end = calendar.date(byAdding: .day, value: 35, to: day) ?? day
        let trip = Trip(name: "Sample Trip", startDate: start, endDate: end)
        trip.participants = (trip.participants ?? []) + [person]
        context.insert(trip)
      default:
        break
      }
    }

    private static func seedPhase3(
      fixture: Fixture,
      in context: ModelContext,
      day: Date,
      calendar: Calendar
    ) {
      switch fixture {
      case .phase3TripWithTasks:
        // Trip currently in `.duringTrip` (start = day-1, end = day+3) with one
        // rule task in `.dayBefore` and one manual task in `.duringTrip`. The
        // trip is the single qualifying trip so it auto-opens.
        let start = calendar.date(byAdding: .day, value: -1, to: day) ?? day
        let end = calendar.date(byAdding: .day, value: 3, to: day) ?? day
        let trip = Trip(name: "Active Trip", startDate: start, endDate: end)
        context.insert(trip)

        let person = Person(name: "Alex", colorKey: "Cyan")
        context.insert(person)
        trip.participants = (trip.participants ?? []) + [person]

        let masterTask = MasterTaskItem(
          name: "Charge devices",
          phase: .dayBefore,
          conditions: .always
        )
        context.insert(masterTask)

        let ruleTask = TripTask(
          trip: trip,
          masterItemID: masterTask.id,
          name: masterTask.name,
          phase: .dayBefore,
          isCompleted: false,
          source: .rule,
          currentlyMatchesRules: true,
          pinnedByUser: false
        )
        context.insert(ruleTask)

        let manualTask = TripTask(
          trip: trip,
          masterItemID: nil,
          name: "Check the weather",
          phase: .duringTrip,
          isCompleted: false,
          source: .manual,
          currentlyMatchesRules: true,
          pinnedByUser: false
        )
        context.insert(manualTask)
      case .phase3OneDayTrip:
        // Single-day trip — start == end. `.duringTrip` duration is
        // max(0, (E-S)-1) = max(0, -1) = 0, so it compresses (Req 3.1).
        let trip = Trip(name: "Day Trip", startDate: day, endDate: day)
        context.insert(trip)
      case .phase3TripNoParticipants:
        // Trip currently in `.duringTrip` with NO participants. Used to
        // verify the assignee-picker empty-state placeholder.
        let start = calendar.date(byAdding: .day, value: -1, to: day) ?? day
        let end = calendar.date(byAdding: .day, value: 3, to: day) ?? day
        let trip = Trip(name: "Solo Trip", startDate: start, endDate: end)
        context.insert(trip)
      default:
        break
      }
    }

    // swiftlint:disable:next function_body_length
    private static func seedPhase4(
      fixture: Fixture,
      in context: ModelContext,
      day: Date,
      calendar: Calendar
    ) {
      switch fixture {
      case .phase4PackModeTrip:
        // Trip on `.dayBefore` (today == start - 1, end == today+6). Two
        // participants, each with a mix of packing item states. Includes a
        // dimmed (`currentlyMatchesRules == false`, `pinnedByUser == false`)
        // row to exercise the dimmed-counts path. Single qualifying trip so
        // it auto-opens; `.dayBefore` (the pack-mode packing phase)
        // auto-expands per Phase 3 rules.
        let start = calendar.date(byAdding: .day, value: 1, to: day)!
        let end = calendar.date(byAdding: .day, value: 6, to: day)!
        let trip = Trip(name: "Beach Trip", startDate: start, endDate: end)
        context.insert(trip)

        let arjen = Person(name: "Arjen", colorKey: "Cyan")
        context.insert(arjen)
        trip.participants = (trip.participants ?? []) + [arjen]

        let sam = Person(name: "Sam", colorKey: "Red")
        context.insert(sam)
        trip.participants = (trip.participants ?? []) + [sam]

        // Master item backing the rule-driven "Toothbrush" entry (`source: .rule`).
        let masterToothbrush = MasterPackingItem(
          name: "Toothbrush",
          person: arjen,
          conditions: .always
        )
        context.insert(masterToothbrush)

        // Arjen — unpacked, packed (rule-driven), excluded, dimmed-packed.
        context.insert(
          TripPackingItem(
            trip: trip,
            person: arjen,
            masterItemID: nil,
            name: "Sunscreen",
            state: .unpacked,
            source: .manual,
            currentlyMatchesRules: true,
            pinnedByUser: false
          )
        )
        context.insert(
          TripPackingItem(
            trip: trip,
            person: arjen,
            masterItemID: masterToothbrush.id,
            name: "Toothbrush",
            state: .packed,
            source: .rule,
            currentlyMatchesRules: true,
            pinnedByUser: false
          )
        )
        context.insert(
          TripPackingItem(
            trip: trip,
            person: arjen,
            masterItemID: nil,
            name: "Book",
            state: .excluded,
            source: .manual,
            currentlyMatchesRules: true,
            pinnedByUser: false
          )
        )
        context.insert(
          TripPackingItem(
            trip: trip,
            person: arjen,
            masterItemID: nil,
            name: "Stale Item",
            state: .packed,
            source: .rule,
            currentlyMatchesRules: false,
            pinnedByUser: false
          )
        )

        // Sam — one unpacked, one packed.
        context.insert(
          TripPackingItem(
            trip: trip,
            person: sam,
            masterItemID: nil,
            name: "Sandals",
            state: .unpacked,
            source: .manual,
            currentlyMatchesRules: true,
            pinnedByUser: false
          )
        )
        context.insert(
          TripPackingItem(
            trip: trip,
            person: sam,
            masterItemID: nil,
            name: "Hat",
            state: .packed,
            source: .manual,
            currentlyMatchesRules: true,
            pinnedByUser: false
          )
        )
      case .phase4RepackModeTrip:
        // Trip on `.dayBeforeReturn` (start == today-3, end == today+1). Two
        // participants with a mix of states populating the three repack-mode
        // groups: still-in-suitcase (`.packed`), back-in-suitcase
        // (`.repacked`), left-behind (`.unpacked` ∪ `.excluded`).
        let start = calendar.date(byAdding: .day, value: -3, to: day) ?? day
        let end = calendar.date(byAdding: .day, value: 1, to: day) ?? day
        let trip = Trip(name: "Mountain Trip", startDate: start, endDate: end)
        context.insert(trip)

        let arjen = Person(name: "Arjen", colorKey: "Cyan")
        context.insert(arjen)
        trip.participants = (trip.participants ?? []) + [arjen]

        let sam = Person(name: "Sam", colorKey: "Red")
        context.insert(sam)
        trip.participants = (trip.participants ?? []) + [sam]

        // Master item backing the rule-driven "Boots" entry (`source: .rule`).
        let masterBoots = MasterPackingItem(
          name: "Boots",
          person: arjen,
          conditions: .always
        )
        context.insert(masterBoots)

        // Arjen — packed (still-in-suitcase), repacked (back-in-suitcase),
        // unpacked + excluded (left-behind, including a rule-driven one).
        context.insert(
          TripPackingItem(
            trip: trip,
            person: arjen,
            masterItemID: nil,
            name: "Jacket",
            state: .packed,
            source: .manual,
            currentlyMatchesRules: true,
            pinnedByUser: false
          )
        )
        context.insert(
          TripPackingItem(
            trip: trip,
            person: arjen,
            masterItemID: nil,
            name: "Gloves",
            state: .repacked,
            source: .manual,
            currentlyMatchesRules: true,
            pinnedByUser: false
          )
        )
        context.insert(
          TripPackingItem(
            trip: trip,
            person: arjen,
            masterItemID: masterBoots.id,
            name: "Boots",
            state: .unpacked,
            source: .rule,
            currentlyMatchesRules: true,
            pinnedByUser: false
          )
        )
        context.insert(
          TripPackingItem(
            trip: trip,
            person: arjen,
            masterItemID: nil,
            name: "Old Map",
            state: .excluded,
            source: .manual,
            currentlyMatchesRules: true,
            pinnedByUser: false
          )
        )

        // Sam — one packed, one repacked.
        context.insert(
          TripPackingItem(
            trip: trip,
            person: sam,
            masterItemID: nil,
            name: "Compass",
            state: .packed,
            source: .manual,
            currentlyMatchesRules: true,
            pinnedByUser: false
          )
        )
        context.insert(
          TripPackingItem(
            trip: trip,
            person: sam,
            masterItemID: nil,
            name: "Camera",
            state: .repacked,
            source: .manual,
            currentlyMatchesRules: true,
            pinnedByUser: false
          )
        )
      default:
        break
      }
    }

    // MARK: - Phase 5 fixtures

    private static func seedPhase5(
      fixture: Fixture,
      globalsContext: ModelContext,
      tripsLocalContext: ModelContext,
      day: Date,
      calendar: Calendar
    ) {
      let start = calendar.date(byAdding: .day, value: 30, to: day) ?? day
      let end = calendar.date(byAdding: .day, value: 35, to: day) ?? day
      switch fixture {
      case .phase5SharedTripOwner:
        seedPhase5SharedTripOwner(
          globals: globalsContext, tripsLocal: tripsLocalContext,
          start: start, end: end
        )
      case .phase5SharedTripParticipant:
        seedPhase5SharedTripParticipant(
          globals: globalsContext, tripsLocal: tripsLocalContext,
          start: start, end: end
        )
      case .phase5MigrationStates:
        seedPhase5MigrationStates(
          globals: globalsContext, start: start, end: end, updatedAt: day
        )
      default:
        break
      }
      try? tripsLocalContext.save()
      try? globalsContext.save()
    }

    private static func seedPhase5SharedTripOwner(
      globals: ModelContext, tripsLocal: ModelContext, start: Date, end: Date
    ) {
      let trip = Trip(name: "Shared Trip", startDate: start, endDate: end)
      // Trip lives in globals until Stage B (pre-Phase-5 convention);
      // TripZoneState lives in tripsLocal where the sharing service
      // reads it.
      globals.insert(trip)
      let zoneState = TripZoneState(
        tripID: trip.id,
        zoneOwnerName: "__defaultOwner__",
        zoneScope: "private",
        shareID: "share-\(trip.id.uuidString)"
      )
      tripsLocal.insert(zoneState)
      trip.tripZoneID = trip.id
      UITestSharingService.ownerIdentitiesByTrip[trip.id] = .currentUser
      UITestSharingService.participantsByTrip[trip.id] = [
        ShareParticipant(
          id: "owner-self", displayName: "You",
          acceptanceState: .accepted, isCurrentUser: true
        ),
        ShareParticipant(
          id: "participant-bob", displayName: "Bob",
          acceptanceState: .accepted, isCurrentUser: false
        ),
        ShareParticipant(
          id: "participant-alice", displayName: "alice@example.com",
          acceptanceState: .pending, isCurrentUser: false
        ),
      ]
    }

    private static func seedPhase5SharedTripParticipant(
      globals: ModelContext, tripsLocal: ModelContext, start: Date, end: Date
    ) {
      let trip = Trip(name: "Their Trip", startDate: start, endDate: end)
      globals.insert(trip)
      let zoneState = TripZoneState(
        tripID: trip.id,
        zoneOwnerName: "remote-owner-id",
        zoneScope: "shared",
        shareID: "share-\(trip.id.uuidString)"
      )
      tripsLocal.insert(zoneState)
      trip.tripZoneID = trip.id
      UITestSharingService.ownerIdentitiesByTrip[trip.id] = .otherUser(
        displayName: "Charlie"
      )
      UITestSharingService.participantsByTrip[trip.id] = [
        ShareParticipant(
          id: "owner-charlie", displayName: "Charlie",
          acceptanceState: .accepted, isCurrentUser: false
        ),
        ShareParticipant(
          id: "participant-self", displayName: "You",
          acceptanceState: .accepted, isCurrentUser: true
        ),
      ]
    }

    private static func seedPhase5MigrationStates(
      globals: ModelContext, start: Date, end: Date, updatedAt: Date
    ) {
      let failedTrip = Trip(name: "Failed Trip", startDate: start, endDate: end)
      let syncingTrip = Trip(name: "Syncing Trip", startDate: start, endDate: end)
      globals.insert(failedTrip)
      globals.insert(syncingTrip)
      globals.insert(
        MigrationJournalEntry(
          tripID: failedTrip.id,
          stateRaw: MigrationStageState.failed.rawValue,
          errorMessage: "Network unavailable",
          updatedAt: updatedAt
        )
      )
      globals.insert(
        MigrationJournalEntry(
          tripID: syncingTrip.id,
          stateRaw: MigrationStageState.stageBInProgress.rawValue,
          updatedAt: updatedAt
        )
      )
    }
  }
#endif
