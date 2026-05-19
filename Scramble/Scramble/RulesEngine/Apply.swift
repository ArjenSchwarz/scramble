import Foundation
import SwiftData
import os

@MainActor
func apply(plan: Plan, context: ModelContext, hook: LocalWriteHook) throws {
  guard !plan.isEmpty else { return }

  let tripID = plan.tripID
  let tripDescriptor = FetchDescriptor<Trip>(predicate: #Predicate { $0.id == tripID })
  guard let trip = try context.fetch(tripDescriptor).first else {
    modelLogger.info("[RulesEngine.skip-trip] tripID=\(tripID, privacy: .public) not found")
    return
  }

  insertAddedTasks(plan.toAddTasks, on: trip, context: context)
  insertAddedPacking(plan.toAddPacking, on: trip, context: context)
  try applyFlags(plan, context: context)

  do {
    try hook.commit(context)
  } catch {
    modelLogger.error(
      "[RulesEngine.save-failed] tripID=\(tripID, privacy: .public) error=\(String(describing: error), privacy: .public)"
    )
    throw error
  }
}

@MainActor
private func insertAddedTasks(
  _ masters: [MasterTaskSnapshot], on trip: Trip, context: ModelContext
) {
  for master in masters {
    let task = TripTask(
      trip: trip,
      masterItemID: master.id,
      name: master.name,
      phase: master.phase,
      isCompleted: false,
      source: .rule,
      currentlyMatchesRules: true,
      pinnedByUser: false
    )
    context.insert(task)
  }
}

@MainActor
private func insertAddedPacking(
  _ masters: [MasterPackingSnapshot], on trip: Trip, context: ModelContext
) {
  guard !masters.isEmpty else { return }
  // Phase 5.1: look up the trip's `TripPersonSnapshot` rather than
  // fetching `Person` from the (now tripsLocal-bound) context. Master
  // items reference a `personID`; the snapshot is the in-zone source
  // of identity and a one-hop read that doesn't cross containers.
  let snapshotsByPersonID = Dictionary(
    uniqueKeysWithValues: (trip.participantSnapshots ?? []).map { ($0.personID, $0) }
  )
  for master in masters {
    guard let snapshot = snapshotsByPersonID[master.personID] else {
      modelLogger.info(
        """
        [RulesEngine.skip-packing-orphan] master=\(master.id, privacy: .public) \
        personID=\(master.personID, privacy: .public) snapshot not found on trip
        """
      )
      continue
    }
    let item = TripPackingItem(
      trip: trip,
      masterItemID: master.id,
      name: master.name,
      state: .unpacked,
      source: .rule,
      currentlyMatchesRules: true,
      pinnedByUser: false,
      personSnapshot: snapshot
    )
    context.insert(item)
  }
}

@MainActor
private func applyFlags(_ plan: Plan, context: ModelContext) throws {
  let taskUnmatch = plan.toFlagUnmatched.compactMap { $0.kind == .task ? $0.id : nil }
  let taskMatch = plan.toFlagMatched.compactMap { $0.kind == .task ? $0.id : nil }
  let packUnmatch = plan.toFlagUnmatched.compactMap { $0.kind == .packing ? $0.id : nil }
  let packMatch = plan.toFlagMatched.compactMap { $0.kind == .packing ? $0.id : nil }
  try flagTasks(ids: taskUnmatch, to: false, context: context)
  try flagTasks(ids: taskMatch, to: true, context: context)
  try flagPacking(ids: packUnmatch, to: false, context: context)
  try flagPacking(ids: packMatch, to: true, context: context)
}

@MainActor
private func flagTasks(ids: [UUID], to value: Bool, context: ModelContext) throws {
  guard !ids.isEmpty else { return }
  let idSet = Set(ids)
  let descriptor = FetchDescriptor<TripTask>(predicate: #Predicate { idSet.contains($0.id) })
  let fetched = try context.fetch(descriptor)
  let foundIDs = Set(fetched.map(\.id))
  for missing in idSet.subtracting(foundIDs) {
    modelLogger.info(
      "[RulesEngine.skip-flag-orphan] kind=task id=\(missing, privacy: .public) not found")
  }
  for task in fetched {
    // Phase 3 / Decision 7: belt-and-braces — if a sync arrival flipped the
    // deletion flag after the snapshot was captured, do not overwrite the
    // user's deletion choice.
    if task.userDeletedOnThisTrip {
      modelLogger.info(
        "[RulesEngine.skip-flag-userDeleted] id=\(task.id, privacy: .public) — userDeletedOnThisTrip=true"
      )
      continue
    }
    task.currentlyMatchesRules = value
  }
}

@MainActor
private func flagPacking(ids: [UUID], to value: Bool, context: ModelContext) throws {
  guard !ids.isEmpty else { return }
  let idSet = Set(ids)
  let descriptor = FetchDescriptor<TripPackingItem>(predicate: #Predicate { idSet.contains($0.id) })
  let fetched = try context.fetch(descriptor)
  let foundIDs = Set(fetched.map(\.id))
  for missing in idSet.subtracting(foundIDs) {
    modelLogger.info(
      "[RulesEngine.skip-flag-orphan] kind=packing id=\(missing, privacy: .public) not found")
  }
  for item in fetched {
    item.currentlyMatchesRules = value
  }
}
