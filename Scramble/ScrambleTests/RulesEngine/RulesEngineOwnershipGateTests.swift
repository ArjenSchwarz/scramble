import CloudKit
import Foundation
import SwiftData
import Testing

@testable import Scramble

/// Phase 5 — engine ownership gate + echo-suppression coverage
/// (Reqs [8.3](../../../specs/phase-5-cloudkit-sharing/requirements.md#8.3),
/// [8.4](../../../specs/phase-5-cloudkit-sharing/requirements.md#8.4),
/// [8.5](../../../specs/phase-5-cloudkit-sharing/requirements.md#8.5),
/// [8.6](../../../specs/phase-5-cloudkit-sharing/requirements.md#8.6)).
///
/// The rules engine `compute → diff → apply` step is owner-only — for
/// trips the current user does not own, the runner must be a no-op
/// (Decision 3). Echo suppression is the corollary: a `.zoneChanged`
/// event the current device just sent (`isSelfOriginated == true`) must
/// not re-trigger the engine.
@Suite("RulesEngineOwnershipGate", .serialized)
@MainActor
struct RulesEngineOwnershipGateTests {

  // MARK: - runForTrip

  @Test("Engine no-ops for trips owned by another user")
  func skipsForParticipantTrips() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext

    let trip = try Self.seedRainyTripWithMaster(in: context)
    let resolver = StaticOwnerResolver(owner: .otherUser(displayName: "Friend"))

    let runner = RulesEngineRunner(context: context, ownerIdentity: resolver.ownerIdentity)
    let plan = try runner.runForTrip(trip)

    #expect(plan.isEmpty, "Engine must produce an empty plan for non-owned trips")
    let tasks = try context.fetch(FetchDescriptor<TripTask>())
    #expect(tasks.isEmpty, "No TripTask should be applied")
  }

  @Test("Engine runs for trips owned by the current user")
  func runsForCurrentUserTrips() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext

    let trip = try Self.seedRainyTripWithMaster(in: context)
    let resolver = StaticOwnerResolver(owner: .currentUser)

    let runner = RulesEngineRunner(context: context, ownerIdentity: resolver.ownerIdentity)
    _ = try runner.runForTrip(trip)

    let tasks = try context.fetch(FetchDescriptor<TripTask>())
    #expect(tasks.count == 1)
  }

  @Test("Engine runs when ownerIdentity returns nil (Phase 1 trips without TripZoneState)")
  func runsForPhase1TripsWithoutOwnerIdentity() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext

    let trip = try Self.seedRainyTripWithMaster(in: context)
    let resolver = StaticOwnerResolver(owner: nil)

    let runner = RulesEngineRunner(context: context, ownerIdentity: resolver.ownerIdentity)
    _ = try runner.runForTrip(trip)

    let tasks = try context.fetch(FetchDescriptor<TripTask>())
    #expect(tasks.count == 1, "nil owner identity must run the engine (Phase 1 legacy trips)")
  }

  // MARK: - runForAllNonPastTrips fan-out

  @Test("Master-item edit fan-out filters to owner-owned trips only")
  func fanOutSkipsParticipantTrips() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext

    // Two trips with identical inputs but different ownership.
    let master = MasterTaskItem(
      name: "Bring umbrella",
      phase: .dayBefore,
      conditions: .match(attribute: .weather, anyOf: ["rain"])
    )
    context.insert(master)

    let ownedTrip = Trip(
      name: "Owned",
      startDate: .now,
      endDate: .now,
      attributes: Self.rainyAttributes()
    )
    let sharedTrip = Trip(
      name: "Shared",
      startDate: .now,
      endDate: .now,
      attributes: Self.rainyAttributes()
    )
    context.insert(ownedTrip)
    context.insert(sharedTrip)
    try context.save()

    let ownedID = ownedTrip.id
    let sharedID = sharedTrip.id
    let resolver = PerTripOwnerResolver(
      identities: [
        ownedID: .currentUser,
        sharedID: .otherUser(displayName: "Friend"),
      ]
    )

    let runner = RulesEngineRunner(context: context, ownerIdentity: resolver.ownerIdentity)
    _ = try runner.runForAllNonPastTrips()

    let tasks = try context.fetch(FetchDescriptor<TripTask>())
    let tripIDsForTasks = Set(tasks.compactMap { $0.trip?.id })
    #expect(tripIDsForTasks == [ownedID], "Only owned trip should have an applied plan")
  }

  // MARK: - CloudKit-received-change trigger (echo suppression)

  @Test("Trigger orchestrator ignores zoneChanged where isSelfOriginated == true")
  func orchestratorIgnoresSelfOriginatedEvents() async throws {
    let container = try Self.makeContainer()
    let context = container.mainContext
    let trip = try Self.seedRainyTripWithMaster(in: context)

    var ranForTrips: [UUID] = []
    let orchestrator = RulesEngineTriggerOrchestrator(
      run: { tripID in ranForTrips.append(tripID) }
    )

    let zoneID = CKRecordZone.ID(
      zoneName: "trip-\(trip.id.uuidString)",
      ownerName: CKCurrentUserDefaultName
    )
    orchestrator.handle(
      event: .zoneChanged(zoneID, scope: .private, isSelfOriginated: true)
    )

    #expect(ranForTrips.isEmpty, "Self-originated zoneChanged must be filtered out")
  }

  @Test("Trigger orchestrator runs engine for non-self-originated zoneChanged events")
  func orchestratorRunsOnRemoteZoneChange() async throws {
    let container = try Self.makeContainer()
    let context = container.mainContext
    let trip = try Self.seedRainyTripWithMaster(in: context)

    var ranForTrips: [UUID] = []
    let orchestrator = RulesEngineTriggerOrchestrator(
      run: { tripID in ranForTrips.append(tripID) }
    )

    let zoneID = CKRecordZone.ID(
      zoneName: "trip-\(trip.id.uuidString)",
      ownerName: CKCurrentUserDefaultName
    )
    orchestrator.handle(
      event: .zoneChanged(zoneID, scope: .private, isSelfOriginated: false)
    )

    #expect(ranForTrips == [trip.id], "Remote zoneChanged triggers an engine run for this trip")
  }

  @Test("Trigger orchestrator ignores events with malformed zone names")
  func orchestratorIgnoresMalformedZones() async throws {
    var ranForTrips: [UUID] = []
    let orchestrator = RulesEngineTriggerOrchestrator(
      run: { tripID in ranForTrips.append(tripID) }
    )

    let zoneID = CKRecordZone.ID(zoneName: "not-a-trip", ownerName: CKCurrentUserDefaultName)
    orchestrator.handle(
      event: .zoneChanged(zoneID, scope: .private, isSelfOriginated: false)
    )
    #expect(ranForTrips.isEmpty)
  }

  // MARK: - Helpers

  private static func makeContainer() throws -> ModelContainer {
    let schema = Schema(versionedSchema: SchemaV3.self)
    let config = ModelConfiguration(
      schema: schema,
      isStoredInMemoryOnly: true,
      cloudKitDatabase: .none
    )
    return try ModelContainer(for: schema, configurations: [config])
  }

  private static func rainyAttributes() -> TripAttributes {
    var a = TripAttributes()
    a.toggle(.weather, value: "rain")
    return a
  }

  private static func seedRainyTripWithMaster(in context: ModelContext) throws -> Trip {
    let master = MasterTaskItem(
      name: "Bring umbrella",
      phase: .dayBefore,
      conditions: .match(attribute: .weather, anyOf: ["rain"])
    )
    context.insert(master)
    let trip = Trip(
      name: "Beach",
      startDate: .now,
      endDate: .now,
      attributes: rainyAttributes()
    )
    context.insert(trip)
    try context.save()
    return trip
  }
}

@MainActor
private struct StaticOwnerResolver {
  let owner: OwnerIdentity?
  func ownerIdentity(forTrip _: UUID) -> OwnerIdentity? { owner }
}

@MainActor
private struct PerTripOwnerResolver {
  let identities: [UUID: OwnerIdentity]
  func ownerIdentity(forTrip tripID: UUID) -> OwnerIdentity? { identities[tripID] }
}
