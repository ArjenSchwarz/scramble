import CloudKit
import Foundation
import SwiftData
import Testing

@testable import Scramble

/// Phase 5.1 — property-based tests for the migration coordinator's
/// cross-store consistency boundary ([C2](../requirements.md#C2)) and
/// idempotence ([Req 4.6](../requirements.md#4.6)).
///
/// Parameterised over the cross-product of:
///   - `InterruptionPoint`: where in the 15-step algorithm the prior run
///     was killed (simulated by setting up the persisted state that the
///     resume would observe).
///   - `resumeCount`: how many times `enqueueAll() + runStageB()` is
///     invoked after the interruption.
///
/// Terminal invariant: the trip lives in exactly ONE of the two stores
/// (tripsLocal-only or globals-only) and the journal entry has converged
/// to a terminal-ish state (.completed, .failed, or .stageBInProgress
/// waiting on engine events).
@Suite("ZoneMigrationCoordinator PBT", .serialized)
@MainActor
struct ZoneMigrationCoordinatorPBT {

  struct Scenario: Sendable, CustomStringConvertible {
    let point: InterruptionPoint
    let resumeCount: Int
    var description: String { "\(point)x\(resumeCount)" }
  }

  static let crossProduct: [Scenario] = InterruptionPoint.allCases.flatMap { point in
    [1, 2, 5].map { Scenario(point: point, resumeCount: $0) }
  }

  enum InterruptionPoint: Sendable, CaseIterable {
    /// Fresh launch — trip in globals, no journal, no zone state.
    case fresh
    /// Resume after step 10's clear ran but the saves were never
    /// committed. We mimic this by leaving the journal at
    /// `.stageBInProgress` with empty `sentRecordNames` and
    /// `zoneSaved == false`.
    case afterStep10Clear
    /// Resume after step 14a (tripsLocal save committed) but step 14b
    /// (globals delete) was killed. Trip present in BOTH stores.
    case afterTripsLocalSave
    /// Resume after step 14b (globals delete committed) so the trip
    /// lives in tripsLocal only. Journal `.stageBInProgress` already.
    case afterGlobalsDelete
    /// Resume after a fully completed prior run. Re-running should be a
    /// no-op.
    case afterCompletion
  }

  @Test(
    "PBT — cross-store consistency holds across interruption × resume count",
    arguments: Self.crossProduct
  )
  func crossStoreConsistency(scenario: Scenario) throws {
    let (point, resumeCount) = (scenario.point, scenario.resumeCount)
    let setup = try ZoneMigrationCoordinatorTests.makeSetup()
    let tripID = UUID()
    let zoneID = CKRecordZone.ID(
      zoneName: "trip-\(tripID.uuidString)",
      ownerName: CKCurrentUserDefaultName
    )

    try seedState(
      for: point,
      tripID: tripID,
      zoneID: zoneID,
      globals: setup.globalsContext,
      tripsLocal: setup.tripsLocalContext
    )

    for _ in 0..<resumeCount {
      try setup.coordinator.enqueueAll()
      try setup.coordinator.runStageB()
    }

    let globalsTrips = try setup.globalsContext.fetch(FetchDescriptor<Trip>())
    let tripsLocalTrips = try setup.tripsLocalContext.fetch(FetchDescriptor<Trip>())
    let inGlobals = globalsTrips.contains { $0.id == tripID }
    let inTripsLocal = tripsLocalTrips.contains { $0.id == tripID }

    #expect(
      !(inGlobals && inTripsLocal),
      "Cross-store consistency: trip never lives in both stores after convergence"
    )

    let journals = try setup.globalsContext.fetch(FetchDescriptor<MigrationJournalEntry>())
    if point == .afterCompletion {
      #expect(journals.first?.state == .completed)
      // The seed leaves the trip in tripsLocal; resume must not touch
      // either store.
      #expect(inTripsLocal && !inGlobals)
    } else {
      // For every other interruption, the trip must end up in
      // tripsLocal only (the destination). The journal converges to a
      // terminal-ish state.
      #expect(inTripsLocal, "Trip relocated to tripsLocal")
      #expect(!inGlobals, "Trip removed from globals")
      let terminal: Set<MigrationStageState> = [.stageBInProgress, .completed, .failed]
      let state = try #require(journals.first?.state)
      #expect(terminal.contains(state))
    }

    // No journal duplication across N resumes.
    #expect(journals.count == 1)
  }

  // MARK: - Seeding helpers

  // swiftlint:disable function_body_length
  private func seedState(
    for point: InterruptionPoint,
    tripID: UUID,
    zoneID: CKRecordZone.ID,
    globals: ModelContext,
    tripsLocal: ModelContext
  ) throws {
    switch point {
    case .fresh:
      let trip = Trip(id: tripID, name: "T", startDate: .now, endDate: .now)
      globals.insert(trip)
      try globals.save()
    case .afterStep10Clear:
      // Journal `.stageBInProgress`, expectedRecordNames seeded, but
      // sentRecordNames + zoneSaved cleared as step 10 leaves them.
      // Trip lives in tripsLocal (relocation completed prior run).
      let trip = Trip(id: tripID, name: "T", startDate: .now, endDate: .now)
      tripsLocal.insert(trip)
      let state = TripZoneState(
        tripID: tripID,
        zoneOwnerName: CKCurrentUserDefaultName,
        zoneScope: "private"
      )
      tripsLocal.insert(state)
      let journal = MigrationJournalEntry(
        tripID: tripID,
        stateRaw: MigrationStageState.stageBInProgress.rawValue
      )
      journal.expectedRecordNames = [tripID.uuidString]
      journal.sentRecordNames = []
      journal.zoneSaved = false
      globals.insert(journal)
      try tripsLocal.save()
      try globals.save()
    case .afterTripsLocalSave:
      // Trip present in BOTH stores — resume must finish the delete-from-globals step.
      let tripGlobals = Trip(id: tripID, name: "T", startDate: .now, endDate: .now)
      let tripLocal = Trip(id: tripID, name: "T", startDate: .now, endDate: .now)
      globals.insert(tripGlobals)
      tripsLocal.insert(tripLocal)
      let journal = MigrationJournalEntry(
        tripID: tripID,
        stateRaw: MigrationStageState.stageBInProgress.rawValue
      )
      globals.insert(journal)
      try globals.save()
      try tripsLocal.save()
    case .afterGlobalsDelete:
      // Trip in tripsLocal only; journal stageBInProgress (zone not yet confirmed).
      let trip = Trip(id: tripID, name: "T", startDate: .now, endDate: .now)
      tripsLocal.insert(trip)
      let state = TripZoneState(
        tripID: tripID,
        zoneOwnerName: CKCurrentUserDefaultName,
        zoneScope: "private"
      )
      tripsLocal.insert(state)
      let journal = MigrationJournalEntry(
        tripID: tripID,
        stateRaw: MigrationStageState.stageBInProgress.rawValue
      )
      globals.insert(journal)
      try tripsLocal.save()
      try globals.save()
    case .afterCompletion:
      // Trip in tripsLocal only, journal completed.
      let trip = Trip(id: tripID, name: "T", startDate: .now, endDate: .now)
      tripsLocal.insert(trip)
      let state = TripZoneState(
        tripID: tripID,
        zoneOwnerName: CKCurrentUserDefaultName,
        zoneScope: "private"
      )
      tripsLocal.insert(state)
      let journal = MigrationJournalEntry(
        tripID: tripID,
        stateRaw: MigrationStageState.completed.rawValue
      )
      globals.insert(journal)
      try tripsLocal.save()
      try globals.save()
    }
  }
  // swiftlint:enable function_body_length
}
