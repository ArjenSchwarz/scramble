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
      case masterTaskAdvancedConditions = "master-task-advanced-conditions"
      case phase2RulesFixture = "phase2-rules-fixture"
      case phase2RulesFixtureSunTrip = "phase2-rules-fixture-sun-trip"
      case phase2RulesColdLaunch = "phase2-rules-cold-launch"
      case personWithMasterPackingOnly = "person-with-master-packing-only"
      /// Phase 3: trip currently in `.duringTrip` with one manual task in
      /// `.duringTrip` and one rule-driven task in `.dayBefore`. The trip
      /// auto-opens (single qualifying trip; today is mid-trip).
      case phase3TripWithTasks = "phase3-trip-with-tasks"
      /// Phase 3: one-day trip (start == end) so `.duringTrip` compresses.
      case phase3OneDayTrip = "phase3-one-day-trip"
      /// Phase 3: trip with no participants for the assignee-picker placeholder.
      case phase3TripNoParticipants = "phase3-trip-no-participants"
      /// Phase 4: trip currently on `.departureDay` (today == start, end ==
      /// today+5) with two participants and a mix of packing item states. Used
      /// by pack-mode UI tests covering the summary block, sheet groups,
      /// checkbox toggle, Skip/Restore, manual add, dimmed-row counting, and
      /// `WhyDisclosure` for rule-driven items.
      case phase4PackModeTrip = "phase4-pack-mode-trip"
      /// Phase 4: trip currently on `.dayBeforeReturn` (today == end-1, start
      /// == today-3) with two participants and a mix of packed/repacked/
      /// unpacked/excluded items. Used by repack-mode UI tests covering the
      /// "Left behind" group, read-only checkboxes, and `WhyDisclosure` on
      /// read-only rows.
      case phase4PackModeTripRepack = "phase4-repack-mode-trip"
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

    static func parseFixture(from arguments: [String]) -> Fixture? {
      guard let idx = arguments.firstIndex(of: launchArgKey) else { return nil }
      let next = arguments.index(after: idx)
      guard next < arguments.endIndex else { return nil }
      return Fixture(rawValue: arguments[next])
    }

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
        .phase4PackModeTripRepack:
        seedPhase4(fixture: fixture, in: context, day: day, calendar: calendar)
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
        // Trip on `.departureDay` (today == start, end == today+5). Two
        // participants, each with a mix of packing item states. Includes a
        // dimmed (`currentlyMatchesRules == false`, `pinnedByUser == false`)
        // row to exercise the dimmed-counts path. Single qualifying trip so
        // it auto-opens; `.departureDay` auto-expands per Phase 3 rules.
        let start = day
        let end = calendar.date(byAdding: .day, value: 5, to: day) ?? day
        let trip = Trip(name: "Beach Trip", startDate: start, endDate: end)
        context.insert(trip)

        let arjen = Person(name: "Arjen", colorKey: "Cyan")
        context.insert(arjen)
        trip.participants = (trip.participants ?? []) + [arjen]

        let sam = Person(name: "Sam", colorKey: "Red")
        context.insert(sam)
        trip.participants = (trip.participants ?? []) + [sam]

        // Master item used by the rule-driven "Toothbrush" entry; gives
        // `WhyDisclosureView` a `.ruleMatched` reason to render.
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
      case .phase4PackModeTripRepack:
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

        // Master item for the rule-driven "Boots" entry so a `WhyDisclosure`
        // long-press on a left-behind row renders a real reason.
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
  }
#endif
