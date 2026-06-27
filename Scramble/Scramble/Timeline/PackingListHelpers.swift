import Foundation

/// Which packing surface is active. `pack` is opened from the Departure phase
/// and operates over `unpacked` / `packed` / `excluded`. `repack` is opened
/// from Day-before-return and operates over `packed` / `repacked` plus a
/// read-only "Left behind" group of `unpacked` ∪ `excluded`.
nonisolated enum PackingMode: Sendable {
  case pack
  case repack
}

/// Per-person tally of `TripPackingItem.state`. Pure value type; constructed
/// by `PackingListHelpers.counts(for:in:)` and consumed by status / progress
/// helpers without further store access.
nonisolated struct PackingCounts: Sendable, Equatable {
  let toPack: Int
  let packed: Int
  let repacked: Int
  let excluded: Int
}

/// One category sub-group produced by `PackingListHelpers.categorySections`.
/// `key` is the normalized category key (`nil` ⇒ uncategorised); `label` is the
/// deterministic display spelling (`nil` ⇒ uncategorised). A result of a single
/// section with `key == nil` is the flat-when-none signal both surfaces use to
/// render rows without a sub-header (Req 5.5 / 6.2).
nonisolated struct CategorySection<Item> {
  let label: String?
  let key: String?
  let items: [Item]
}

/// Pure helpers used by `PackingSummarySection`, `PackingSheet`, and
/// `AccordionTimeline`. Mirrors the shape of `TaskListHelpers` but operates
/// over `TripPackingItem`. `@MainActor` because the helpers traverse
/// SwiftData `@Model` collections (`trip.packingItems`,
/// `trip.participantSnapshots`) whose ownership is tied to the main
/// `ModelContext`.
@MainActor enum PackingListHelpers {

  /// Items belonging to `person` on `trip`, unfiltered by group/state.
  /// Matches via the V3 `personSnapshot` reference (Decision 7) — the
  /// deprecated `TripPackingItem.person` relationship is unwritten on every
  /// production path, so the owner is carried by `personSnapshotID` whose
  /// snapshot's `personID` is the owning `Person.id`.
  static func itemsForPerson(_ trip: Trip, person: Person) -> [TripPackingItem] {
    let snapshotIDs = Set(
      (trip.participantSnapshots ?? [])
        .filter { $0.personID == person.id }
        .map(\.id))
    return (trip.packingItems ?? []).filter { item in
      guard let snapshotID = item.personSnapshotID else { return false }
      return snapshotIDs.contains(snapshotID)
    }
  }

  /// Per-state counts for `person` on `trip`. Includes both active and dimmed
  /// items per Req 1.6.
  static func counts(for person: Person, in trip: Trip) -> PackingCounts {
    var toPack = 0
    var packed = 0
    var repacked = 0
    var excluded = 0
    for item in itemsForPerson(trip, person: person) {
      switch item.state {
      case .unpacked: toPack += 1
      case .packed: packed += 1
      case .repacked: repacked += 1
      case .excluded: excluded += 1
      }
    }
    return PackingCounts(toPack: toPack, packed: packed, repacked: repacked, excluded: excluded)
  }

  /// Status label per Req 1.3 (pack) / 1.4 (repack).
  static func summaryStatus(_ counts: PackingCounts, mode: PackingMode) -> String {
    switch mode {
    case .pack:
      let active = counts.toPack + counts.packed
      if active == 0 && counts.excluded == 0 { return "No items" }
      if active == 0 { return "—" }
      if counts.toPack == 0 { return "✓ ready" }
      return "\(counts.toPack) to pack"
    case .repack:
      let total = counts.toPack + counts.packed + counts.repacked + counts.excluded
      let active = counts.packed + counts.repacked
      if total == 0 { return "No items" }
      if active == 0 { return "—" }
      if counts.packed == 0 { return "✓ all back in" }
      return "\(counts.packed) to repack"
    }
  }

  /// Progress fill ratio per Req 1.5. Returns 0.0 when the denominator is
  /// zero; otherwise `numerator / denominator`. Always in `[0.0, 1.0]`.
  static func progressRatio(_ counts: PackingCounts, mode: PackingMode) -> Double {
    switch mode {
    case .pack:
      let denom = counts.toPack + counts.packed
      guard denom > 0 else { return 0.0 }
      return Double(counts.packed) / Double(denom)
    case .repack:
      let denom = counts.packed + counts.repacked
      guard denom > 0 else { return 0.0 }
      return Double(counts.repacked) / Double(denom)
    }
  }

  /// Phase subline packing clause per Req 1.10. Returns `"packing ready"` /
  /// `"all back in"` when nothing is pending; otherwise `"{S} to pack"` /
  /// `"{S} to repack"` summed across participants. Caller composes the leading
  /// " · " when a tasks clause precedes it.
  static func phaseSubline(_ trip: Trip, mode: PackingMode) -> String {
    let snapshotPersonID = snapshotPersonIDMap(trip)
    var sum = 0
    for item in trip.packingItems ?? [] {
      guard let snapshotID = item.personSnapshotID,
        snapshotPersonID[snapshotID] != nil
      else { continue }
      switch (mode, item.state) {
      case (.pack, .unpacked): sum += 1
      case (.repack, .packed): sum += 1
      default: break
      }
    }
    if sum == 0 {
      return mode == .pack ? "packing ready" : "all back in"
    }
    return mode == .pack ? "\(sum) to pack" : "\(sum) to repack"
  }

  /// Per-person counts for every participant on `trip` in a single pass. Used
  /// by `PackingSummarySection` to avoid an O(participants × packingItems)
  /// fan-out where one pass suffices.
  static func countsByPerson(_ trip: Trip) -> [UUID: PackingCounts] {
    let snapshotPersonID = snapshotPersonIDMap(trip)
    var toPack: [UUID: Int] = [:]
    var packed: [UUID: Int] = [:]
    var repacked: [UUID: Int] = [:]
    var excluded: [UUID: Int] = [:]
    for item in trip.packingItems ?? [] {
      guard let snapshotID = item.personSnapshotID,
        let personID = snapshotPersonID[snapshotID]
      else { continue }
      switch item.state {
      case .unpacked: toPack[personID, default: 0] += 1
      case .packed: packed[personID, default: 0] += 1
      case .repacked: repacked[personID, default: 0] += 1
      case .excluded: excluded[personID, default: 0] += 1
      }
    }
    var result: [UUID: PackingCounts] = [:]
    for personID in Set(snapshotPersonID.values) {
      result[personID] = PackingCounts(
        toPack: toPack[personID] ?? 0,
        packed: packed[personID] ?? 0,
        repacked: repacked[personID] ?? 0,
        excluded: excluded[personID] ?? 0
      )
    }
    return result
  }

  /// Sort items per Req 3.8 / 4.7: active-before-dimmed, then case-insensitive
  /// ascending name, then `id` tiebreak.
  static func sorted(_ items: [TripPackingItem]) -> [TripPackingItem] {
    items.sorted { lhs, rhs in
      let la = isActive(lhs)
      let ra = isActive(rhs)
      if la != ra { return la && !ra }
      let nameOrder = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
      if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
      return lhs.id.uuidString < rhs.id.uuidString
    }
  }

  /// Generic category grouping shared by the Packing Sheet and Master Lists.
  /// Partitions `items` by `PackingCategory.normalizedKey`, orders the resulting
  /// sections via `PackingCategory.keyOrder` (uncategorised/nil last, Req 5.2),
  /// sorts within each group with `sortWithin` (Req 5.3), and resolves each
  /// section's label via `PackingCategory.displayLabel` of that group's stored
  /// spellings (Req 5.6; `nil` for the uncategorised group). When no item is
  /// categorised the result is a single section with `key == nil` — the
  /// flat-when-none signal callers use to drop sub-headers (Req 5.5 / 6.2).
  ///
  /// One pass over `items` builds the buckets and the per-key spelling variants,
  /// so a caller renders a body without re-scanning per row (Req 5.7). The
  /// closures are `@MainActor` because both call sites pass actor-isolated
  /// values (`\.category` / `\.name` on `@Model` items, `sorted`).
  static func categorySections<Item>(
    _ items: [Item],
    category: @MainActor (Item) -> String?,
    sortWithin: @MainActor ([Item]) -> [Item]
  ) -> [CategorySection<Item>] {
    var itemsByKey: [String?: [Item]] = [:]
    var variantsByKey: [String: [String]] = [:]
    for item in items {
      let raw = category(item)
      let key = PackingCategory.normalizedKey(raw)
      itemsByKey[key, default: []].append(item)
      // A non-nil key always has a non-nil storageValue spelling.
      if let key, let spelling = PackingCategory.storageValue(raw) {
        variantsByKey[key, default: []].append(spelling)
      }
    }

    return itemsByKey.keys
      .sorted(by: PackingCategory.keyOrder)
      .map { key in
        CategorySection(
          label: key.map { PackingCategory.displayLabel(variantsByKey[$0] ?? []) },
          key: key,
          items: sortWithin(itemsByKey[key] ?? [])
        )
      }
  }

  // MARK: - Private

  /// Maps each participant snapshot's `id` to its owner `personID`. Built once
  /// per call so the aggregate helpers stay single-pass (avoiding the
  /// O(participants × packingItems) fan-out `countsByPerson` exists to prevent).
  private static func snapshotPersonIDMap(_ trip: Trip) -> [UUID: UUID] {
    var map: [UUID: UUID] = [:]
    for snapshot in trip.participantSnapshots ?? [] {
      map[snapshot.id] = snapshot.personID
    }
    return map
  }

  private static func isActive(_ item: TripPackingItem) -> Bool {
    item.currentlyMatchesRules || item.pinnedByUser
  }
}
