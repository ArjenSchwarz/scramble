import Foundation
import SwiftData
import Testing

@testable import Scramble

@Suite("RulesEngine apply(plan:context:)", .serialized)
@MainActor
struct ApplyTests {

  private static func makeContainer() throws -> ModelContainer {
    let schema = Schema(versionedSchema: SchemaV3.self)
    let config = ModelConfiguration(
      schema: schema,
      isStoredInMemoryOnly: true,
      cloudKitDatabase: .none
    )
    return try ModelContainer(for: schema, configurations: [config])
  }

  // MARK: - Empty plan short-circuit

  @Test("Empty plan: no save, no changes")
  func emptyPlanShortCircuits() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext

    let trip = Trip(name: "Test", startDate: .now, endDate: .now)
    context.insert(trip)
    try context.save()
    #expect(context.hasChanges == false)

    let plan = Plan(
      tripID: trip.id,
      toAddTasks: [],
      toAddPacking: [],
      toFlagUnmatched: [],
      toFlagMatched: []
    )
    try apply(plan: plan, context: context, hook: LocalWriteHook(notifier: RecordingNotifier()))
    #expect(context.hasChanges == false)
  }

  // MARK: - toAddTasks

  @Test("toAddTasks inserts TripTask with snapshotted fields and rule defaults")
  func toAddTasksInsertsCorrectly() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext

    let trip = Trip(name: "Test", startDate: .now, endDate: .now)
    context.insert(trip)
    try context.save()

    let masterID = UUID()
    let master = MasterTaskSnapshot(
      id: masterID,
      name: "Book flights",
      phase: .weeksBefore,
      conditions: .always
    )
    let plan = Plan(
      tripID: trip.id,
      toAddTasks: [master],
      toAddPacking: [],
      toFlagUnmatched: [],
      toFlagMatched: []
    )
    try apply(plan: plan, context: context, hook: LocalWriteHook(notifier: RecordingNotifier()))

    let tasks = try context.fetch(FetchDescriptor<TripTask>())
    #expect(tasks.count == 1)
    let inserted = try #require(tasks.first)
    #expect(inserted.name == "Book flights")
    #expect(inserted.phase == .weeksBefore)
    #expect(inserted.masterItemID == masterID)
    #expect(inserted.source == .rule)
    #expect(inserted.currentlyMatchesRules == true)
    #expect(inserted.pinnedByUser == false)
    #expect(inserted.isCompleted == false)
    #expect(inserted.trip?.id == trip.id)
  }

  // MARK: - toAddPacking

  @Test("toAddPacking inserts TripPackingItem with snapshotted fields and resolved person")
  func toAddPackingInsertsCorrectly() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext

    let person = Person(name: "Arjen", colorKey: "cyan")
    context.insert(person)
    let trip = Trip(name: "Test", startDate: .now, endDate: .now)
    context.insert(trip)
    // Phase 5.1: rule-driven packing items resolve identity through the
    // trip's `TripPersonSnapshot`, not the V2 `Person` relationship. Seed
    // a snapshot for the master's `personID`.
    let snapshot = TripPersonSnapshot(
      personID: person.id,
      name: person.name,
      colourID: person.colorKey,
      initialSource: "name",
      isRosterMember: true,
      trip: trip
    )
    context.insert(snapshot)
    try context.save()

    let masterID = UUID()
    let master = MasterPackingSnapshot(
      id: masterID,
      name: "Rain jacket",
      personID: person.id,
      conditions: .always
    )
    let plan = Plan(
      tripID: trip.id,
      toAddTasks: [],
      toAddPacking: [master],
      toFlagUnmatched: [],
      toFlagMatched: []
    )
    try apply(plan: plan, context: context, hook: LocalWriteHook(notifier: RecordingNotifier()))

    let items = try context.fetch(FetchDescriptor<TripPackingItem>())
    #expect(items.count == 1)
    let inserted = try #require(items.first)
    #expect(inserted.name == "Rain jacket")
    #expect(inserted.masterItemID == masterID)
    #expect(inserted.source == .rule)
    #expect(inserted.currentlyMatchesRules == true)
    #expect(inserted.pinnedByUser == false)
    #expect(inserted.state == .unpacked)
    // Phase 5.1: assignee identity is via the V3 personSnapshot.
    #expect(inserted.personSnapshot?.personID == person.id)
    #expect(inserted.trip?.id == trip.id)
  }

  @Test("toAddPacking with missing person: insert skipped, no throw")
  func toAddPackingMissingPersonSkips() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext

    let trip = Trip(name: "Test", startDate: .now, endDate: .now)
    context.insert(trip)
    try context.save()

    let plan = Plan(
      tripID: trip.id,
      toAddTasks: [],
      toAddPacking: [
        MasterPackingSnapshot(
          id: UUID(), name: "Orphan", personID: UUID(), conditions: .always)
      ],
      toFlagUnmatched: [],
      toFlagMatched: []
    )
    try apply(plan: plan, context: context, hook: LocalWriteHook(notifier: RecordingNotifier()))

    let items = try context.fetch(FetchDescriptor<TripPackingItem>())
    #expect(items.isEmpty)
  }

  // MARK: - toFlagUnmatched / toFlagMatched

  @Test("toFlagUnmatched flips TripTask.currentlyMatchesRules to false; other fields untouched")
  func toFlagUnmatchedTask() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext

    let trip = Trip(name: "Test", startDate: .now, endDate: .now)
    context.insert(trip)
    let task = TripTask(
      trip: trip,
      masterItemID: UUID(),
      name: "Existing",
      phase: .dayBefore,
      isCompleted: false,
      source: .rule,
      currentlyMatchesRules: true,
      pinnedByUser: false
    )
    context.insert(task)
    try context.save()

    let plan = Plan(
      tripID: trip.id,
      toAddTasks: [],
      toAddPacking: [],
      toFlagUnmatched: [TripItemRef(kind: .task, id: task.id)],
      toFlagMatched: []
    )
    try apply(plan: plan, context: context, hook: LocalWriteHook(notifier: RecordingNotifier()))

    let fetched = try context.fetch(FetchDescriptor<TripTask>())
    let updated = try #require(fetched.first)
    #expect(updated.currentlyMatchesRules == false)
    #expect(updated.name == "Existing")
    #expect(updated.phase == .dayBefore)
  }

  @Test("toFlagMatched flips TripPackingItem.currentlyMatchesRules to true; state untouched")
  func toFlagMatchedPacking() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext

    let person = Person(name: "P", colorKey: "blue")
    context.insert(person)
    let trip = Trip(name: "Test", startDate: .now, endDate: .now)
    context.insert(trip)
    let item = TripPackingItem(
      trip: trip,
      person: person,
      masterItemID: UUID(),
      name: "Pack item",
      state: .packed,
      source: .rule,
      currentlyMatchesRules: false,
      pinnedByUser: false
    )
    context.insert(item)
    try context.save()

    let plan = Plan(
      tripID: trip.id,
      toAddTasks: [],
      toAddPacking: [],
      toFlagUnmatched: [],
      toFlagMatched: [TripItemRef(kind: .packing, id: item.id)]
    )
    try apply(plan: plan, context: context, hook: LocalWriteHook(notifier: RecordingNotifier()))

    let fetched = try context.fetch(FetchDescriptor<TripPackingItem>())
    let updated = try #require(fetched.first)
    #expect(updated.currentlyMatchesRules == true)
    #expect(updated.state == .packed)
    #expect(updated.person?.id == person.id)
  }

  // MARK: - userDeletedOnThisTrip — apply carve-out (Req 7.4)

  @Test("toFlagMatched on a userDeleted TripTask: flagTasks must not write currentlyMatchesRules")
  func userDeletedTaskIsNotFlaggedMatched() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext

    let trip = Trip(name: "Test", startDate: .now, endDate: .now)
    context.insert(trip)
    let task = TripTask(
      trip: trip,
      masterItemID: UUID(),
      name: "Deleted ruling",
      phase: .dayBefore,
      isCompleted: false,
      source: .rule,
      currentlyMatchesRules: false,
      pinnedByUser: false,
      userDeletedOnThisTrip: true
    )
    context.insert(task)
    try context.save()

    let plan = Plan(
      tripID: trip.id,
      toAddTasks: [],
      toAddPacking: [],
      toFlagUnmatched: [],
      toFlagMatched: [TripItemRef(kind: .task, id: task.id)]
    )
    try apply(plan: plan, context: context, hook: LocalWriteHook(notifier: RecordingNotifier()))

    let fetched = try context.fetch(FetchDescriptor<TripTask>())
    let stored = try #require(fetched.first)
    #expect(stored.userDeletedOnThisTrip == true)
    #expect(
      stored.currentlyMatchesRules == false,
      "currentlyMatchesRules must not be flipped on a deleted record")
  }

  @Test("toFlagUnmatched on a userDeleted TripTask: flagTasks must not write currentlyMatchesRules")
  func userDeletedTaskIsNotFlaggedUnmatched() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext

    let trip = Trip(name: "Test", startDate: .now, endDate: .now)
    context.insert(trip)
    let task = TripTask(
      trip: trip,
      masterItemID: UUID(),
      name: "Deleted ruling",
      phase: .dayBefore,
      isCompleted: false,
      source: .rule,
      currentlyMatchesRules: true,
      pinnedByUser: false,
      userDeletedOnThisTrip: true
    )
    context.insert(task)
    try context.save()

    let plan = Plan(
      tripID: trip.id,
      toAddTasks: [],
      toAddPacking: [],
      toFlagUnmatched: [TripItemRef(kind: .task, id: task.id)],
      toFlagMatched: []
    )
    try apply(plan: plan, context: context, hook: LocalWriteHook(notifier: RecordingNotifier()))

    let fetched = try context.fetch(FetchDescriptor<TripTask>())
    let stored = try #require(fetched.first)
    #expect(stored.userDeletedOnThisTrip == true)
    #expect(
      stored.currentlyMatchesRules == true,
      "currentlyMatchesRules must not be flipped on a deleted record")
  }

  // MARK: - Missing trip (cross-device delete race)

  @Test("Missing trip: apply returns without throwing and writes nothing")
  func missingTripNoThrow() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext

    let plan = Plan(
      tripID: UUID(),
      toAddTasks: [
        MasterTaskSnapshot(
          id: UUID(), name: "Phantom", phase: .weeksBefore, conditions: .always)
      ],
      toAddPacking: [],
      toFlagUnmatched: [],
      toFlagMatched: []
    )
    try apply(plan: plan, context: context, hook: LocalWriteHook(notifier: RecordingNotifier()))

    let tasks = try context.fetch(FetchDescriptor<TripTask>())
    #expect(tasks.isEmpty)
  }

  // MARK: - Missing trip-level item

  @Test("Missing TripTask referenced by toFlagUnmatched: skipped, no throw")
  func missingTripTaskSkips() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext

    let trip = Trip(name: "Test", startDate: .now, endDate: .now)
    context.insert(trip)
    try context.save()

    let plan = Plan(
      tripID: trip.id,
      toAddTasks: [],
      toAddPacking: [],
      toFlagUnmatched: [TripItemRef(kind: .task, id: UUID())],
      toFlagMatched: []
    )
    try apply(plan: plan, context: context, hook: LocalWriteHook(notifier: RecordingNotifier()))
    // No throw; nothing to assert beyond that.
  }

  @Test("Missing TripPackingItem referenced by toFlagMatched: skipped, no throw")
  func missingTripPackingSkips() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext

    let trip = Trip(name: "Test", startDate: .now, endDate: .now)
    context.insert(trip)
    try context.save()

    let plan = Plan(
      tripID: trip.id,
      toAddTasks: [],
      toAddPacking: [],
      toFlagUnmatched: [],
      toFlagMatched: [TripItemRef(kind: .packing, id: UUID())]
    )
    try apply(plan: plan, context: context, hook: LocalWriteHook(notifier: RecordingNotifier()))
  }

  // MARK: - Multi-section plan

  @Test("Mixed plan: toAdd + toFlag operations all apply in one save")
  func mixedPlanFullPath() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext
    let (trip, person) = try Self.seedMixedPlanFixture(in: context)
    let existingMatched = TripTask(
      trip: trip,
      masterItemID: UUID(),
      name: "Existing matched",
      currentlyMatchesRules: true
    )
    let existingUnmatched = TripPackingItem(
      trip: trip,
      person: person,
      masterItemID: UUID(),
      name: "Existing unmatched",
      currentlyMatchesRules: false
    )
    context.insert(existingMatched)
    context.insert(existingUnmatched)
    try context.save()

    let addedTaskID = UUID()
    let addedPackID = UUID()
    let plan = Plan(
      tripID: trip.id,
      toAddTasks: [
        MasterTaskSnapshot(
          id: addedTaskID, name: "Added task", phase: .weeksBefore, conditions: .always)
      ],
      toAddPacking: [
        MasterPackingSnapshot(
          id: addedPackID, name: "Added pack", personID: person.id, conditions: .always)
      ],
      toFlagUnmatched: [TripItemRef(kind: .task, id: existingMatched.id)],
      toFlagMatched: [TripItemRef(kind: .packing, id: existingUnmatched.id)]
    )
    try apply(plan: plan, context: context, hook: LocalWriteHook(notifier: RecordingNotifier()))

    let tasks = try context.fetch(FetchDescriptor<TripTask>()).sorted { $0.name < $1.name }
    #expect(tasks.count == 2)
    let unmatchedTask = try #require(tasks.first { $0.id == existingMatched.id })
    #expect(unmatchedTask.currentlyMatchesRules == false)
    let added = try #require(tasks.first { $0.masterItemID == addedTaskID })
    #expect(added.name == "Added task")

    let packs = try context.fetch(FetchDescriptor<TripPackingItem>())
    #expect(packs.count == 2)
    let matchedPack = try #require(packs.first { $0.id == existingUnmatched.id })
    #expect(matchedPack.currentlyMatchesRules == true)
    let addedPack = try #require(packs.first { $0.masterItemID == addedPackID })
    #expect(addedPack.personSnapshot?.personID == person.id)
  }

  // MARK: - Category re-stamp (packing-item-categories, Decision 2/6)

  @Test("Re-stamp: apply writes only category on the targeted item; no other field touched")
  func restampWritesOnlyCategory() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext

    let person = Person(name: "P", colorKey: "blue")
    context.insert(person)
    let trip = Trip(name: "Test", startDate: .now, endDate: .now)
    context.insert(trip)
    let masterID = UUID()
    let item = TripPackingItem(
      trip: trip,
      person: person,
      masterItemID: masterID,
      name: "Rain jacket",
      state: .packed,
      source: .rule,
      currentlyMatchesRules: true,
      pinnedByUser: true,
      note: "keep dry",
      category: nil
    )
    context.insert(item)
    try context.save()

    let plan = Plan(
      tripID: trip.id,
      toAddTasks: [],
      toAddPacking: [],
      toFlagUnmatched: [],
      toFlagMatched: [],
      toRestampCategory: [PackingCategoryRestamp(id: item.id, category: "Clothes")]
    )
    try apply(plan: plan, context: context, hook: LocalWriteHook(notifier: RecordingNotifier()))

    let updated = try #require(try context.fetch(FetchDescriptor<TripPackingItem>()).first)
    #expect(updated.category == "Clothes")
    // Every other field is untouched (Req 3.3) — especially the snapshotted name.
    #expect(updated.name == "Rain jacket")
    #expect(updated.state == .packed)
    #expect(updated.source == .rule)
    #expect(updated.currentlyMatchesRules == true)
    #expect(updated.pinnedByUser == true)
    #expect(updated.masterItemID == masterID)
    #expect(updated.note == "keep dry")
  }

  @Test("Re-stamp: apply clears category to nil when the restamp value is nil")
  func restampClearsCategory() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext

    let trip = Trip(name: "Test", startDate: .now, endDate: .now)
    context.insert(trip)
    let item = TripPackingItem(
      trip: trip,
      masterItemID: UUID(),
      name: "Rain jacket",
      source: .rule,
      category: "Clothes"
    )
    context.insert(item)
    try context.save()

    let plan = Plan(
      tripID: trip.id,
      toAddTasks: [],
      toAddPacking: [],
      toFlagUnmatched: [],
      toFlagMatched: [],
      toRestampCategory: [PackingCategoryRestamp(id: item.id, category: nil)]
    )
    try apply(plan: plan, context: context, hook: LocalWriteHook(notifier: RecordingNotifier()))

    let updated = try #require(try context.fetch(FetchDescriptor<TripPackingItem>()).first)
    #expect(updated.category == nil)
    #expect(updated.name == "Rain jacket")
  }

  @Test("Re-stamp: empty toRestampCategory leaves existing categories untouched")
  func restampEmptyDoesNotWrite() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext

    let trip = Trip(name: "Test", startDate: .now, endDate: .now)
    context.insert(trip)
    let item = TripPackingItem(
      trip: trip,
      masterItemID: UUID(),
      name: "Existing",
      source: .rule,
      category: "Original"
    )
    context.insert(item)
    try context.save()

    // Plan does other work (adds a task) but carries no re-stamps, so the
    // item's category must be left as-is.
    let plan = Plan(
      tripID: trip.id,
      toAddTasks: [
        MasterTaskSnapshot(id: UUID(), name: "Added", phase: .weeksBefore, conditions: .always)
      ],
      toAddPacking: [],
      toFlagUnmatched: [],
      toFlagMatched: [],
      toRestampCategory: []
    )
    try apply(plan: plan, context: context, hook: LocalWriteHook(notifier: RecordingNotifier()))

    let updated = try #require(try context.fetch(FetchDescriptor<TripPackingItem>()).first)
    #expect(updated.category == "Original")
  }

  @Test("Add path: insertAddedPacking stamps master.category at creation (Req 3.1)")
  func insertAddedPackingStampsCategory() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext

    let person = Person(name: "Arjen", colorKey: "cyan")
    context.insert(person)
    let trip = Trip(name: "Test", startDate: .now, endDate: .now)
    context.insert(trip)
    let snapshot = TripPersonSnapshot(
      personID: person.id,
      name: person.name,
      colourID: person.colorKey,
      initialSource: "name",
      isRosterMember: true,
      trip: trip
    )
    context.insert(snapshot)
    try context.save()

    let master = MasterPackingSnapshot(
      id: UUID(),
      name: "Rain jacket",
      personID: person.id,
      conditions: .always,
      category: "Outerwear"
    )
    let plan = Plan(
      tripID: trip.id,
      toAddTasks: [],
      toAddPacking: [master],
      toFlagUnmatched: [],
      toFlagMatched: []
    )
    try apply(plan: plan, context: context, hook: LocalWriteHook(notifier: RecordingNotifier()))

    let inserted = try #require(try context.fetch(FetchDescriptor<TripPackingItem>()).first)
    #expect(inserted.category == "Outerwear")
  }

  /// Phase 5.1: rule-driven packing inserts look up the trip's
  /// `TripPersonSnapshot` for the master's `personID`. The shared seed
  /// keeps `mixedPlanFullPath` under the function-length limit.
  private static func seedMixedPlanFixture(in context: ModelContext) throws -> (Trip, Person) {
    let person = Person(name: "P", colorKey: "blue")
    context.insert(person)
    let trip = Trip(name: "Test", startDate: .now, endDate: .now)
    context.insert(trip)
    let snapshot = TripPersonSnapshot(
      personID: person.id,
      name: person.name,
      colourID: person.colorKey,
      initialSource: "name",
      isRosterMember: true,
      trip: trip
    )
    context.insert(snapshot)
    return (trip, person)
  }
}
