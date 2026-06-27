import Foundation

// Pure, value-type rules engine compute step. No `ModelContext` access, no shared state.
// `currentlyMatchesRules` is undefined for `source == .manual` refs — they are skipped entirely.
// `.match(_, anyOf: [])` evaluates `false` (defensive against corrupt blobs; the chip editor
// cannot produce that shape).

nonisolated func compute(
  trip: TripSnapshot,
  masterTasks: [MasterTaskSnapshot],
  masterPacking: [MasterPackingSnapshot]
) -> Plan {
  // `uniquingKeysWith` rather than `uniqueKeysWithValues` so a CloudKit
  // merge that briefly surfaces two masters with the same UUID does not
  // trap. Duplicates are tolerated; we keep the first.
  let taskMap = Dictionary(masterTasks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
  let packingMap = Dictionary(
    masterPacking.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
  let referenced = referencedMasterIDs(in: trip)

  let toAddTasks = masterTasks.filter { master in
    !referenced.contains(master.id) && master.conditions.evaluate(against: trip.attributes)
  }
  let toAddPacking = masterPacking.filter { master in
    !referenced.contains(master.id) && master.conditions.evaluate(against: trip.attributes)
  }

  var toFlagUnmatched: [TripItemRef] = []
  var toFlagMatched: [TripItemRef] = []

  classifyTaskRefs(
    trip.existingTasks,
    attributes: trip.attributes,
    taskMap: taskMap,
    unmatched: &toFlagUnmatched,
    matched: &toFlagMatched
  )
  classifyPackingRefs(
    trip.existingPacking,
    attributes: trip.attributes,
    packingMap: packingMap,
    unmatched: &toFlagUnmatched,
    matched: &toFlagMatched
  )

  let toRestampCategory = computeCategoryRestamps(trip.existingPacking, packingMap: packingMap)

  return Plan(
    tripID: trip.id,
    toAddTasks: toAddTasks,
    toAddPacking: toAddPacking,
    toFlagUnmatched: toFlagUnmatched,
    toFlagMatched: toFlagMatched,
    toRestampCategory: toRestampCategory
  )
}

/// Category re-stamp diff (feature `packing-item-categories`, Decision 2/6).
/// Manual items are excluded outright (`source == .manual`, mirroring
/// `classifyPackingRefs`) so a manual one-off owns its category even with a
/// stray non-nil `masterItemID` (Req 4.3). For master-derived items it branches
/// on the master's **presence** in the packing map, not on the value: a master
/// that is absent — deleted, or a `nil` `masterItemID` — is skipped entirely,
/// freezing the trip item's last category (Req 3.6). When the master is present,
/// an exact-string compare (including the present-with-`nil` clear case) emits a
/// re-stamp only when the values differ (compare-before-write). Category is not a
/// matching input, so this is independent of the four-way flag classification above.
private nonisolated func computeCategoryRestamps(
  _ refs: [TripPackingItemRef],
  packingMap: [UUID: MasterPackingSnapshot]
) -> [PackingCategoryRestamp] {
  var restamps: [PackingCategoryRestamp] = []
  for ref in refs {
    guard ref.source != .manual, let masterID = ref.masterItemID, let master = packingMap[masterID]
    else { continue }
    if master.category != ref.category {
      restamps.append(PackingCategoryRestamp(id: ref.id, category: master.category))
    }
  }
  return restamps
}

private nonisolated func referencedMasterIDs(in trip: TripSnapshot) -> Set<UUID> {
  var ids: Set<UUID> = []
  for ref in trip.existingTasks {
    if let id = ref.masterItemID { ids.insert(id) }
  }
  for ref in trip.existingPacking {
    if let id = ref.masterItemID { ids.insert(id) }
  }
  return ids
}

private nonisolated func classifyTaskRefs(
  _ refs: [TripTaskRef],
  attributes: TripAttributes,
  taskMap: [UUID: MasterTaskSnapshot],
  unmatched: inout [TripItemRef],
  matched: inout [TripItemRef]
) {
  for ref in refs {
    // Phase 3 / Decision 7: a user-deleted rule task is inert — neither
    // re-matched nor un-matched by subsequent compute runs.
    guard !ref.userDeletedOnThisTrip else { continue }
    guard ref.source != .manual, let masterID = ref.masterItemID else { continue }
    let matches = taskMap[masterID]?.conditions.evaluate(against: attributes) ?? false
    switch (ref.currentlyMatchesRules, matches) {
    case (true, false):
      if ref.pinnedByUser || ref.isCompleted { continue }
      unmatched.append(TripItemRef(kind: .task, id: ref.id))
    case (false, true):
      matched.append(TripItemRef(kind: .task, id: ref.id))
    default:
      continue
    }
  }
}

private nonisolated func classifyPackingRefs(
  _ refs: [TripPackingItemRef],
  attributes: TripAttributes,
  packingMap: [UUID: MasterPackingSnapshot],
  unmatched: inout [TripItemRef],
  matched: inout [TripItemRef]
) {
  let engaged: Set<PackingState> = [.packed, .repacked, .excluded]
  for ref in refs {
    guard ref.source != .manual, let masterID = ref.masterItemID else { continue }
    let matches = packingMap[masterID]?.conditions.evaluate(against: attributes) ?? false
    switch (ref.currentlyMatchesRules, matches) {
    case (true, false):
      if ref.pinnedByUser || engaged.contains(ref.state) { continue }
      unmatched.append(TripItemRef(kind: .packing, id: ref.id))
    case (false, true):
      matched.append(TripItemRef(kind: .packing, id: ref.id))
    default:
      continue
    }
  }
}
