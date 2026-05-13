import Foundation
import SwiftData
import Testing

@testable import Scramble

@Suite("Schema", .serialized)
@MainActor
struct SchemaTests {

  private static func makeContainer() throws -> ModelContainer {
    let schema = Schema(versionedSchema: SchemaV2.self)
    let config = ModelConfiguration(
      schema: schema,
      isStoredInMemoryOnly: true,
      cloudKitDatabase: .none
    )
    return try ModelContainer(for: schema, configurations: [config])
  }

  // MARK: - Container construction

  @Test("Container constructs from SchemaV2")
  func containerConstructs() throws {
    _ = try Self.makeContainer()
  }

  @Test("Container constructs with SchemaV2 + AppMigrationPlan")
  func containerConstructsWithMigrationPlan() throws {
    let schema = Schema(versionedSchema: SchemaV2.self)
    let config = ModelConfiguration(
      schema: schema,
      isStoredInMemoryOnly: true,
      cloudKitDatabase: .none
    )
    _ = try ModelContainer(
      for: schema,
      migrationPlan: AppMigrationPlan.self,
      configurations: [config]
    )
  }

  // MARK: - Round-trips

  @Test("Trip round-trips")
  func tripRoundTrip() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext

    var attributes = TripAttributes()
    attributes.setSingle(.duration, value: "weekend")
    attributes.toggle(.weather, value: "rain")

    let trip = Trip(
      name: "Test",
      startDate: Date(timeIntervalSince1970: 1_700_000_000),
      endDate: Date(timeIntervalSince1970: 1_700_086_400),
      attributes: attributes
    )
    context.insert(trip)
    try context.save()

    let fetched = try context.fetch(FetchDescriptor<Trip>())
    #expect(fetched.count == 1)
    let stored = try #require(fetched.first)
    #expect(stored.name == "Test")
    #expect(stored.attributes.selected(.duration) == ["weekend"])
    #expect(stored.attributes.selected(.weather) == ["rain"])
  }

  @Test("Person round-trips")
  func personRoundTrip() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext

    let person = Person(name: "Arjen", colorKey: "cyan")
    context.insert(person)
    try context.save()

    let fetched = try context.fetch(FetchDescriptor<Person>())
    #expect(fetched.count == 1)
    #expect(fetched.first?.name == "Arjen")
    #expect(fetched.first?.colorKey == "cyan")
  }

  @Test("MasterTaskItem round-trips with phase + conditions")
  func masterTaskItemRoundTrip() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext

    let item = MasterTaskItem(
      name: "Book flights",
      phase: .weeksBefore,
      conditions: .match(attribute: .transport, anyOf: ["plane"])
    )
    context.insert(item)
    try context.save()

    let fetched = try context.fetch(FetchDescriptor<MasterTaskItem>())
    #expect(fetched.count == 1)
    let stored = try #require(fetched.first)
    #expect(stored.name == "Book flights")
    #expect(stored.phase == .weeksBefore)
    if case .match(let attribute, let anyOf) = stored.conditions {
      #expect(attribute == .transport)
      #expect(anyOf == ["plane"])
    } else {
      Issue.record("Expected .match condition")
    }
  }

  @Test("MasterPackingItem round-trips and references its Person")
  func masterPackingItemRoundTrip() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext

    let person = Person(name: "Kelsey", colorKey: "green")
    context.insert(person)
    let item = MasterPackingItem(name: "Toothbrush", person: person, conditions: .always)
    context.insert(item)
    try context.save()

    let fetched = try context.fetch(FetchDescriptor<MasterPackingItem>())
    #expect(fetched.count == 1)
    #expect(fetched.first?.name == "Toothbrush")
    #expect(fetched.first?.person?.id == person.id)
  }

  @Test("TripTask round-trips with phase + source + flags")
  func tripTaskRoundTrip() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext

    let trip = Trip(name: "Test", startDate: .now, endDate: .now)
    context.insert(trip)
    let task = TripTask(
      trip: trip,
      masterItemID: nil,
      name: "Pack snacks",
      phase: .dayBefore,
      isCompleted: true,
      source: .manual,
      currentlyMatchesRules: false,
      pinnedByUser: true
    )
    context.insert(task)
    try context.save()

    let fetched = try context.fetch(FetchDescriptor<TripTask>())
    #expect(fetched.count == 1)
    let stored = try #require(fetched.first)
    #expect(stored.name == "Pack snacks")
    #expect(stored.phase == .dayBefore)
    #expect(stored.source == .manual)
    #expect(stored.isCompleted == true)
    #expect(stored.currentlyMatchesRules == false)
    #expect(stored.pinnedByUser == true)
  }

  @Test("TripPackingItem round-trips with state + source")
  func tripPackingItemRoundTrip() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext

    let trip = Trip(name: "Test", startDate: .now, endDate: .now)
    let person = Person(name: "Rigel", colorKey: "orange")
    context.insert(trip)
    context.insert(person)
    let item = TripPackingItem(
      trip: trip,
      person: person,
      name: "Toothbrush",
      state: .packed,
      source: .rule
    )
    context.insert(item)
    try context.save()

    let fetched = try context.fetch(FetchDescriptor<TripPackingItem>())
    #expect(fetched.count == 1)
    let stored = try #require(fetched.first)
    #expect(stored.state == .packed)
    #expect(stored.source == .rule)
    #expect(stored.person?.id == person.id)
    #expect(stored.trip?.id == trip.id)
  }

  // MARK: - Inverse relationships

  @Test("Trip.tasks ↔ TripTask.trip inverse exposed both directions")
  func tripTasksInverseBothDirections() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext

    let trip = Trip(name: "Test", startDate: .now, endDate: .now)
    context.insert(trip)
    let task = TripTask(trip: trip, name: "Pack")
    context.insert(task)
    try context.save()

    let trips = try context.fetch(FetchDescriptor<Trip>())
    #expect(trips.first?.tasks?.count == 1)
    #expect(trips.first?.tasks?.first?.name == "Pack")

    let tasks = try context.fetch(FetchDescriptor<TripTask>())
    #expect(tasks.first?.trip?.id == trip.id)
  }

  @Test("Trip.packingItems ↔ TripPackingItem.trip inverse exposed both directions")
  func tripPackingItemsInverseBothDirections() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext

    let trip = Trip(name: "Test", startDate: .now, endDate: .now)
    context.insert(trip)
    let item = TripPackingItem(trip: trip, name: "Toothbrush")
    context.insert(item)
    try context.save()

    let trips = try context.fetch(FetchDescriptor<Trip>())
    #expect(trips.first?.packingItems?.count == 1)

    let items = try context.fetch(FetchDescriptor<TripPackingItem>())
    #expect(items.first?.trip?.id == trip.id)
  }

  @Test("Trip.participants ↔ Person.trips many-to-many")
  func tripParticipantsBothDirections() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext

    let trip = Trip(name: "Test", startDate: .now, endDate: .now)
    let p1 = Person(name: "Arjen", colorKey: "cyan")
    let p2 = Person(name: "Kelsey", colorKey: "green")
    context.insert(trip)
    context.insert(p1)
    context.insert(p2)
    trip.participants = [p1, p2]
    try context.save()

    let trips = try context.fetch(FetchDescriptor<Trip>())
    #expect(trips.first?.participants?.count == 2)

    let people = try context.fetch(FetchDescriptor<Person>())
    for person in people {
      #expect((person.trips ?? []).contains { $0.id == trip.id })
    }
  }

  @Test("Person.tripPackingItems inverse")
  func personTripPackingItemsInverse() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext

    let person = Person(name: "Arjen", colorKey: "cyan")
    let trip = Trip(name: "Test", startDate: .now, endDate: .now)
    context.insert(person)
    context.insert(trip)
    let item = TripPackingItem(trip: trip, person: person, name: "Toothbrush")
    context.insert(item)
    try context.save()

    let people = try context.fetch(FetchDescriptor<Person>())
    #expect(people.first?.tripPackingItems?.count == 1)
  }

  @Test("Person.masterPackingItems inverse")
  func personMasterPackingItemsInverse() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext

    let person = Person(name: "Arjen", colorKey: "cyan")
    context.insert(person)
    let item = MasterPackingItem(name: "Toothbrush", person: person)
    context.insert(item)
    try context.save()

    let people = try context.fetch(FetchDescriptor<Person>())
    #expect(people.first?.masterPackingItems?.count == 1)
  }

  // MARK: - Delete rules

  @Test("Cascade Trip → TripTask")
  func cascadeTripToTasks() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext

    let trip = Trip(name: "Test", startDate: .now, endDate: .now)
    context.insert(trip)
    context.insert(TripTask(trip: trip, name: "T1"))
    context.insert(TripTask(trip: trip, name: "T2"))
    try context.save()

    context.delete(trip)
    try context.save()

    let remaining = try context.fetch(FetchDescriptor<TripTask>())
    #expect(remaining.isEmpty)
  }

  @Test("Cascade Trip → TripPackingItem")
  func cascadeTripToPackingItems() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext

    let trip = Trip(name: "Test", startDate: .now, endDate: .now)
    context.insert(trip)
    context.insert(TripPackingItem(trip: trip, name: "I1"))
    context.insert(TripPackingItem(trip: trip, name: "I2"))
    try context.save()

    context.delete(trip)
    try context.save()

    let remaining = try context.fetch(FetchDescriptor<TripPackingItem>())
    #expect(remaining.isEmpty)
  }

  // CloudKit does not support `.deny`; the delete rule on
  // `Person.tripPackingItems` and `Person.masterPackingItems` is `.nullify`.
  // Person-delete enforcement happens in the UI layer (`PersonDeleteBlocker`)
  // per requirement 9.7. The tests below verify the inverse traversal that the
  // UI uses to detect references before allowing a person delete — see
  // `personTripPackingItemsInverse` and `personMasterPackingItemsInverse`.

  @Test("Person.tripPackingItems references survive a save and remain queryable")
  func personTripPackingItemReferencesQueryable() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext

    let person = Person(name: "Arjen", colorKey: "cyan")
    let trip = Trip(name: "Test", startDate: .now, endDate: .now)
    context.insert(person)
    context.insert(trip)
    context.insert(TripPackingItem(trip: trip, person: person, name: "Toothbrush"))
    try context.save()

    let people = try context.fetch(FetchDescriptor<Person>())
    let p = try #require(people.first)
    #expect(p.tripPackingItems?.count == 1)
    #expect(p.tripPackingItems?.first?.name == "Toothbrush")
  }

  @Test("Person.masterPackingItems references survive a save and remain queryable")
  func personMasterPackingItemReferencesQueryable() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext

    let person = Person(name: "Arjen", colorKey: "cyan")
    context.insert(person)
    context.insert(MasterPackingItem(name: "Toothbrush", person: person))
    try context.save()

    let people = try context.fetch(FetchDescriptor<Person>())
    let p = try #require(people.first)
    #expect(p.masterPackingItems?.count == 1)
  }

  @Test("Nullify Trip.participants on Person delete")
  func nullifyOnPersonDelete() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext

    let p1 = Person(name: "Arjen", colorKey: "cyan")
    let p2 = Person(name: "Kelsey", colorKey: "green")
    let trip = Trip(name: "Test", startDate: .now, endDate: .now)
    context.insert(p1)
    context.insert(p2)
    context.insert(trip)
    trip.participants = [p1, p2]
    try context.save()

    context.delete(p1)
    try context.save()

    let trips = try context.fetch(FetchDescriptor<Trip>())
    let participants = trips.first?.participants ?? []
    #expect(participants.count == 1)
    #expect(participants.first?.id == p2.id)
  }

  // MARK: - Person.initial

  @Test("Person.initial: simple letter uppercased")
  func initialSimpleLetter() {
    #expect(Person(name: "arjen").initial == "A")
    #expect(Person(name: "Bob").initial == "B")
    #expect(Person(name: "z").initial == "Z")
  }

  @Test("Person.initial: accented letter preserved + uppercased")
  func initialAccented() {
    #expect(Person(name: "édouard").initial == "É")
    #expect(Person(name: "Ångström").initial == "Å")
    #expect(Person(name: "ñoño").initial == "Ñ")
  }

  @Test("Person.initial: empty name returns ?")
  func initialEmpty() {
    #expect(Person(name: "").initial == "?")
  }

  @Test("Person.initial: ZWJ-joined emoji is a single grapheme")
  func initialZWJ() {
    let family = "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}\u{200D}\u{1F466}"
    #expect(Person(name: family + " Family").initial == family)
  }

  // MARK: - Codable bridges

  @Test("attributesData ↔ attributes bridge round-trip")
  func attributesBridgeRoundTrip() {
    let trip = Trip(name: "Test", startDate: .now, endDate: .now)
    var attrs = TripAttributes()
    attrs.setSingle(.transport, value: "plane")
    attrs.toggle(.weather, value: "rain")
    attrs.toggle(.weather, value: "cold")
    trip.attributes = attrs

    let stored = trip.attributes
    #expect(stored.selected(.transport) == ["plane"])
    #expect(Set(stored.selected(.weather)) == Set(["rain", "cold"]))
  }

  @Test("MasterTaskItem.conditions bridge round-trip")
  func masterTaskConditionsBridgeRoundTrip() {
    let item = MasterTaskItem(name: "Test")
    item.conditions = .all([
      .match(attribute: .weather, anyOf: ["rain"]),
      .match(attribute: .duration, anyOf: ["week"]),
    ])
    if case .all(let children) = item.conditions {
      #expect(children.count == 2)
    } else {
      Issue.record("Expected .all conditions")
    }
  }

  @Test("MasterPackingItem.conditions bridge round-trip")
  func masterPackingConditionsBridgeRoundTrip() {
    let item = MasterPackingItem(name: "Test")
    item.conditions = .match(attribute: .scope, anyOf: ["international"])
    if case .match(let attribute, let anyOf) = item.conditions {
      #expect(attribute == .scope)
      #expect(anyOf == ["international"])
    } else {
      Issue.record("Expected .match conditions")
    }
  }

  @Test("phaseRaw bridge: TripTask")
  func phaseBridgeTripTask() {
    let task = TripTask(name: "Test")
    task.phase = .duringTrip
    #expect(task.phaseRaw == Phase.duringTrip.rawValue)
    task.phaseRaw = Phase.returnDay.rawValue
    #expect(task.phase == .returnDay)
  }

  @Test("phaseRaw bridge: MasterTaskItem")
  func phaseBridgeMaster() {
    let item = MasterTaskItem(name: "Test")
    item.phase = .afterTrip
    #expect(item.phaseRaw == Phase.afterTrip.rawValue)
    item.phaseRaw = Phase.dayBefore.rawValue
    #expect(item.phase == .dayBefore)
  }

  @Test("sourceRaw bridge: TripTask")
  func sourceBridgeTripTask() {
    let task = TripTask(name: "Test")
    task.source = .rule
    #expect(task.sourceRaw == ItemSource.rule.rawValue)
    task.sourceRaw = ItemSource.manual.rawValue
    #expect(task.source == .manual)
  }

  @Test("sourceRaw bridge: TripPackingItem")
  func sourceBridgeTripPackingItem() {
    let item = TripPackingItem(name: "Test")
    item.source = .rule
    #expect(item.sourceRaw == ItemSource.rule.rawValue)
    item.sourceRaw = ItemSource.manual.rawValue
    #expect(item.source == .manual)
  }

  @Test("stateRaw bridge: TripPackingItem")
  func stateBridge() {
    let item = TripPackingItem(name: "Test")
    item.state = .packed
    #expect(item.stateRaw == PackingState.packed.rawValue)
    item.stateRaw = PackingState.repacked.rawValue
    #expect(item.state == .repacked)
  }

  @Test("phase bridge: unknown rawValue falls back to default")
  func phaseBridgeUnknownFallback() {
    let task = TripTask(name: "Test")
    task.phaseRaw = "totallyUnknown"
    #expect(task.phase == .weeksBefore)
  }

  @Test("source bridge: unknown rawValue falls back to default")
  func sourceBridgeUnknownFallback() {
    let task = TripTask(name: "Test")
    task.sourceRaw = "totallyUnknown"
    #expect(task.source == .manual)
  }

  @Test("state bridge: unknown rawValue falls back to default")
  func stateBridgeUnknownFallback() {
    let item = TripPackingItem(name: "Test")
    item.stateRaw = "totallyUnknown"
    #expect(item.state == .unpacked)
  }

  // MARK: - Dangling masterItemID

  @Test("Dangling masterItemID is tolerated on TripTask")
  func danglingMasterItemIDTripTask() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext

    let master = MasterTaskItem(name: "Original")
    context.insert(master)
    let masterID = master.id
    let trip = Trip(name: "Test", startDate: .now, endDate: .now)
    context.insert(trip)
    let task = TripTask(trip: trip, masterItemID: masterID, name: "Snapshot name")
    context.insert(task)
    try context.save()

    context.delete(master)
    try context.save()

    let fetched = try context.fetch(FetchDescriptor<TripTask>())
    #expect(fetched.count == 1)
    #expect(fetched.first?.masterItemID == masterID)
    #expect(fetched.first?.name == "Snapshot name")
    let masters = try context.fetch(FetchDescriptor<MasterTaskItem>())
    #expect(masters.isEmpty)
  }

  @Test("Dangling masterItemID is tolerated on TripPackingItem")
  func danglingMasterItemIDPackingItem() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext

    let person = Person(name: "Arjen", colorKey: "cyan")
    context.insert(person)
    let master = MasterPackingItem(name: "Original", person: person)
    context.insert(master)
    let masterID = master.id
    let trip = Trip(name: "Test", startDate: .now, endDate: .now)
    context.insert(trip)
    // Replace the master's person link so we can delete the master without triggering the
    // .deny rule on the master→person side (this test focuses on dangling masterItemID).
    let item = TripPackingItem(trip: trip, person: person, masterItemID: masterID, name: "Snapshot")
    context.insert(item)
    try context.save()

    master.person = nil
    try context.save()
    context.delete(master)
    try context.save()

    let fetched = try context.fetch(FetchDescriptor<TripPackingItem>())
    #expect(fetched.count == 1)
    #expect(fetched.first?.masterItemID == masterID)
    #expect(fetched.first?.name == "Snapshot")
  }
}
