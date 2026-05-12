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
  let taskMap = Dictionary(uniqueKeysWithValues: masterTasks.map { ($0.id, $0) })
  let packingMap = Dictionary(uniqueKeysWithValues: masterPacking.map { ($0.id, $0) })
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

  return Plan(
    tripID: trip.id,
    toAddTasks: toAddTasks,
    toAddPacking: toAddPacking,
    toFlagUnmatched: toFlagUnmatched,
    toFlagMatched: toFlagMatched
  )
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
