import Foundation
import SwiftData
import os

@MainActor
struct RulesEngineRunner {
  let context: ModelContext

  @discardableResult
  func runForTrip(_ trip: Trip) throws -> Plan {
    let masterTasks = try fetchMasterTaskSnapshots()
    let masterPacking = try fetchMasterPackingSnapshots()
    return try runForTrip(trip, masterTasks: masterTasks, masterPacking: masterPacking)
  }

  @discardableResult
  func runForAllNonPastTrips(
    today: Date = .now,
    calendar: Calendar = .current
  ) throws -> [Plan] {
    let cutoff = calendar.startOfDay(for: today)
    // Push the cutoff into the predicate so past trips are skipped at the
    // SQLite layer rather than materialised then filtered in memory.
    let tripDescriptor = FetchDescriptor<Trip>(predicate: #Predicate { $0.endDate >= cutoff })
    let trips = try context.fetch(tripDescriptor)
    // Hoist the master snapshot fetches out of the per-trip loop. With 20
    // non-past trips × 200 masters the prior shape was 8,000 model
    // materialisations; one shared fetch keeps the AC 5.5 budget safe.
    let masterTasks = try fetchMasterTaskSnapshots()
    let masterPacking = try fetchMasterPackingSnapshots()
    var plans: [Plan] = []
    for trip in trips {
      do {
        let plan = try runForTrip(trip, masterTasks: masterTasks, masterPacking: masterPacking)
        plans.append(plan)
      } catch {
        // Drop any partial inserts/changes from the failed trip so the next
        // iteration's save() doesn't silently persist orphaned rows.
        context.rollback()
        modelLogger.error(
          "[RulesEngine.run-failed] tripID=\(trip.id, privacy: .public) error=\(String(describing: error), privacy: .public)"
        )
      }
    }
    return plans
  }

  private func runForTrip(
    _ trip: Trip,
    masterTasks: [MasterTaskSnapshot],
    masterPacking: [MasterPackingSnapshot]
  ) throws -> Plan {
    let snapshot = TripSnapshot.capture(from: trip)
    let plan = compute(
      trip: snapshot,
      masterTasks: masterTasks,
      masterPacking: masterPacking
    )
    try apply(plan: plan, context: context)
    return plan
  }

  private func fetchMasterTaskSnapshots() throws -> [MasterTaskSnapshot] {
    try context.fetch(FetchDescriptor<MasterTaskItem>()).map { master in
      MasterTaskSnapshot(
        id: master.id,
        name: master.name,
        phase: master.phase,
        conditions: master.conditions
      )
    }
  }

  private func fetchMasterPackingSnapshots() throws -> [MasterPackingSnapshot] {
    var snapshots: [MasterPackingSnapshot] = []
    for master in try context.fetch(FetchDescriptor<MasterPackingItem>()) {
      guard let person = master.person else {
        modelLogger.info(
          "[RulesEngine.skip-orphan-master] master=\(master.id, privacy: .public) person=nil"
        )
        continue
      }
      snapshots.append(
        MasterPackingSnapshot(
          id: master.id,
          name: master.name,
          personID: person.id,
          conditions: master.conditions
        )
      )
    }
    return snapshots
  }
}

@MainActor
extension TripSnapshot {
  static func capture(from trip: Trip) -> TripSnapshot {
    let taskRefs = trip.tasks.map { task in
      TripTaskRef(
        id: task.id,
        masterItemID: task.masterItemID,
        currentlyMatchesRules: task.currentlyMatchesRules,
        pinnedByUser: task.pinnedByUser,
        source: task.source,
        isCompleted: task.isCompleted
      )
    }
    let packingRefs = trip.packingItems.map { item in
      TripPackingItemRef(
        id: item.id,
        masterItemID: item.masterItemID,
        currentlyMatchesRules: item.currentlyMatchesRules,
        pinnedByUser: item.pinnedByUser,
        source: item.source,
        state: item.state
      )
    }
    return TripSnapshot(
      id: trip.id,
      attributes: trip.attributes,
      existingTasks: taskRefs,
      existingPacking: packingRefs
    )
  }
}
