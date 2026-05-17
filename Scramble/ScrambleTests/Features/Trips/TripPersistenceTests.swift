import Foundation
import SwiftData
import Testing

@testable import Scramble

@Suite("TripPersistence snapshot diff (Phase 5.1)", .serialized)
@MainActor
struct TripPersistenceTests {

  private static func makeContainer() throws -> ModelContainer {
    let schema = Schema(versionedSchema: SchemaV3.self)
    let config = ModelConfiguration(
      schema: schema,
      isStoredInMemoryOnly: true,
      cloudKitDatabase: .none
    )
    return try ModelContainer(for: schema, configurations: [config])
  }

  private static func seedGlobals(_ peopleByName: [String: String]) throws -> (
    ModelContainer, [String: Person]
  ) {
    let container = try makeContainer()
    let context = container.mainContext
    var people: [String: Person] = [:]
    for (name, colorKey) in peopleByName {
      let person = Person(name: name, colorKey: colorKey)
      context.insert(person)
      people[name] = person
    }
    try context.save()
    return (container, people)
  }

  // MARK: - create

  @Test(
    """
    create: inserts a Trip + a TripZoneState row + TripPersonSnapshot per resolved \
    participant. Does NOT write to the V2 trip.participants relationship.
    """
  )
  func createInsertsTripZoneStateAndSnapshots() throws {
    let (globalsContainer, people) = try Self.seedGlobals(["Alice": "cyan", "Bob": "violet"])
    let globalsContext = globalsContainer.mainContext

    let tripsLocalContainer = try Self.makeContainer()
    let tripsLocal = tripsLocalContainer.mainContext

    let alice = people["Alice"]!
    let bob = people["Bob"]!
    let draft = TripDraft(
      name: "Trip",
      startDate: .now,
      endDate: .now,
      attributes: TripAttributes(),
      participantIDs: [alice.id, bob.id]
    )

    let (trip, missing) = TripPersistence.create(
      from: draft, in: tripsLocal, globals: globalsContext
    )

    #expect(missing.isEmpty)

    let snapshots = trip.participantSnapshots ?? []
    let byPersonID = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.personID, $0) })
    let aliceSnap = try #require(byPersonID[alice.id])
    let bobSnap = try #require(byPersonID[bob.id])
    #expect(aliceSnap.name == "Alice")
    #expect(aliceSnap.colourID == "cyan")
    #expect(aliceSnap.isRosterMember)
    #expect(bobSnap.name == "Bob")
    #expect(bobSnap.colourID == "violet")

    // TripZoneState row was inserted up-front so the first edit's hook
    // commit has somewhere to record dirty flags (Req 1.5).
    let zoneStates = try tripsLocal.fetch(FetchDescriptor<TripZoneState>())
    #expect(zoneStates.contains { $0.tripID == trip.id })

    // V2 participants relationship is NOT written (constraint C3).
    let participantIDs = (trip.participants ?? []).map(\.id)
    #expect(participantIDs.isEmpty)
  }

  @Test("create: unresolved participant IDs are returned in the missing list")
  func createReturnsMissingIDsForUnresolvedParticipants() throws {
    let (globalsContainer, _) = try Self.seedGlobals(["Alice": "cyan"])
    let globalsContext = globalsContainer.mainContext

    let tripsLocalContainer = try Self.makeContainer()
    let tripsLocal = tripsLocalContainer.mainContext

    let ghost = UUID()
    let draft = TripDraft(
      name: "Trip",
      startDate: .now,
      endDate: .now,
      attributes: TripAttributes(),
      participantIDs: [ghost]
    )

    let (_, missing) = TripPersistence.create(
      from: draft, in: tripsLocal, globals: globalsContext
    )

    #expect(missing == [ghost])
  }

  // MARK: - apply

  @Test(
    """
    apply: inserts new TripPersonSnapshot for added IDs; calls \
    SnapshotMaintenance.handleRosterRemoval for removed IDs; updates name/colour \
    in-place for kept IDs whose Person changed.
    """
  )
  func applyProducesAddUpdateRemoveDiff() throws {
    let (globalsContainer, people) = try Self.seedGlobals([
      "Alice": "cyan", "Bob": "violet", "Carol": "amber",
    ])
    let globalsContext = globalsContainer.mainContext

    let tripsLocalContainer = try Self.makeContainer()
    let tripsLocal = tripsLocalContainer.mainContext

    let alice = people["Alice"]!
    let bob = people["Bob"]!
    let carol = people["Carol"]!

    // Seed initial trip with Alice + Bob.
    let initialDraft = TripDraft(
      name: "Trip",
      startDate: .now,
      endDate: .now,
      attributes: TripAttributes(),
      participantIDs: [alice.id, bob.id]
    )
    let (trip, _) = TripPersistence.create(
      from: initialDraft, in: tripsLocal, globals: globalsContext
    )
    // Commit before mutating; apply's roster-removal helper fetches
    // snapshots from the store, so the seed snapshots must be persisted.
    try tripsLocal.save()

    // Mutate Alice in globals; remove Bob; add Carol.
    alice.name = "Alicia"
    alice.colorKey = "violet"
    try globalsContext.save()

    let nextDraft = TripDraft(
      name: "Trip",
      startDate: .now,
      endDate: .now,
      attributes: TripAttributes(),
      participantIDs: [alice.id, carol.id]
    )
    let missing = TripPersistence.apply(
      nextDraft, to: trip, in: tripsLocal, globals: globalsContext
    )
    #expect(missing.isEmpty)

    // Persist apply's pending mutations so subsequent reads see the
    // committed state. Production flow commits via LocalWriteHook.commit
    // immediately after apply; the test mirrors that boundary.
    try tripsLocal.save()

    // Bob's snapshot is gone (handleRosterRemoval removed the unreferenced row).
    let snapshots = trip.participantSnapshots ?? []
    let byPersonID = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.personID, $0) })
    #expect(byPersonID[bob.id] == nil)

    // Alice's snapshot was updated in place.
    let aliceSnap = try #require(byPersonID[alice.id])
    #expect(aliceSnap.name == "Alicia")
    #expect(aliceSnap.colourID == "violet")

    // Carol's snapshot was inserted.
    let carolSnap = try #require(byPersonID[carol.id])
    #expect(carolSnap.name == "Carol")
    #expect(carolSnap.colourID == "amber")

    // V2 participants stays empty.
    #expect((trip.participants ?? []).isEmpty)
  }

  @Test(
    "apply: roster removal preserves the snapshot when a TripPackingItem still references it"
  )
  func applyKeepsSnapshotWhenReferencedByPackingItem() throws {
    let (globalsContainer, people) = try Self.seedGlobals(["Alice": "cyan"])
    let globalsContext = globalsContainer.mainContext

    let tripsLocalContainer = try Self.makeContainer()
    let tripsLocal = tripsLocalContainer.mainContext

    let alice = people["Alice"]!
    let initialDraft = TripDraft(
      name: "Trip",
      startDate: .now,
      endDate: .now,
      attributes: TripAttributes(),
      participantIDs: [alice.id]
    )
    let (trip, _) = TripPersistence.create(
      from: initialDraft, in: tripsLocal, globals: globalsContext
    )
    let aliceSnap = try #require(
      trip.participantSnapshots?.first { $0.personID == alice.id }
    )
    let item = TripPackingItem(trip: trip, name: "Socks", personSnapshot: aliceSnap)
    tripsLocal.insert(item)
    // Commit before exercising roster removal; the helper fetches from
    // the store, so the seed must be persisted.
    try tripsLocal.save()

    // Remove Alice from the roster — snapshot must remain because the
    // packing item still references it, but be flagged non-roster.
    let emptyDraft = TripDraft(
      name: "Trip",
      startDate: .now,
      endDate: .now,
      attributes: TripAttributes(),
      participantIDs: []
    )
    _ = TripPersistence.apply(
      emptyDraft, to: trip, in: tripsLocal, globals: globalsContext
    )

    let remaining = trip.participantSnapshots ?? []
    #expect(remaining.count == 1)
    #expect(remaining.first?.isRosterMember == false)
  }
}
