import Foundation
import SwiftData

@Model
final class TripPackingItem {
  var id: UUID = UUID()
  @Relationship var trip: Trip?

  /// Deprecated in V3. New code reads `personSnapshot` (Decision 7) so a
  /// shared trip renders without crossing into the owner's globals zone.
  /// The planned V4 removal was folded into V3 — the shared top-level
  /// class pattern makes a property-only V4 indistinguishable from V3 —
  /// so this field is still present but unused on read paths.
  @Relationship var person: Person?

  var masterItemID: UUID?
  var name: String = ""
  var stateRaw: String = PackingState.unpacked.rawValue
  var sourceRaw: String = ItemSource.manual.rawValue
  var currentlyMatchesRules: Bool = true
  var pinnedByUser: Bool = false

  /// V3 — replaces `person` for read paths; resolved through the trip
  /// zone so participants render without crossing into the owner's
  /// globals zone (Req 2.5).
  ///
  /// Stored as a `UUID?` value reference rather than a `@Relationship`.
  /// The globals container's SwiftData CloudKit mirror rejects any
  /// relationship without an inverse, and the snapshot↔item inverse is
  /// exactly the pair that panics SwiftData's cascade traversal on iOS
  /// 26.4 (see `Trip.participantSnapshots`). A value reference satisfies
  /// CloudKit, sidesteps that cascade, and matches
  /// `TripTask.assigneePersonID`'s dangling-reference tolerance. Read it
  /// through the `personSnapshot` computed bridge below.
  var personSnapshotID: UUID?

  /// V3 — see `Trip.ckRecordSystemFields`.
  var ckRecordSystemFields: Data?

  /// Per-trip free-form note (feature `packing-item-subitems`). `nil` or
  /// empty ⇒ no note. Optional with a `nil` default so it rides on the
  /// existing `SchemaV3` via lightweight inference — a property-only
  /// addition to a shared top-level class cannot be a distinct
  /// `SchemaV4` (see `persistence.md`).
  var note: String?

  /// Per-trip sub-item list (feature `packing-item-subitems`), JSON-encoded
  /// `[String]`. `nil`/empty ⇒ no sub-items. Optional with a `nil` default
  /// so it rides on `SchemaV3` (same reason as `note`). Read/write through
  /// the `subItems` `CodableBridge` extension below — never as a stored
  /// relationship.
  var subItemsData: Data?

  /// Managed category projection (feature `packing-item-categories`). `nil`
  /// or empty ⇒ uncategorised. For master-derived items the owner's device
  /// re-stamps this from the master's current category; manual one-off items
  /// (`masterItemID == nil`) own their value and are never re-stamped
  /// (Decision 2). Stored trimmed + internal-whitespace-collapsed with case
  /// preserved; normalization lives in the `PackingCategory` namespace.
  /// Optional with a `nil` default so it rides on `SchemaV3` (same reason as
  /// `note`).
  var category: String?

  init(
    id: UUID = UUID(),
    trip: Trip? = nil,
    person: Person? = nil,
    masterItemID: UUID? = nil,
    name: String = "",
    state: PackingState = .unpacked,
    source: ItemSource = .manual,
    currentlyMatchesRules: Bool = true,
    pinnedByUser: Bool = false,
    personSnapshot: TripPersonSnapshot? = nil,
    note: String? = nil,
    category: String? = nil
  ) {
    self.id = id
    self.trip = trip
    self.person = person
    self.masterItemID = masterItemID
    self.name = name
    self.stateRaw = state.rawValue
    self.sourceRaw = source.rawValue
    self.currentlyMatchesRules = currentlyMatchesRules
    self.pinnedByUser = pinnedByUser
    self.personSnapshotID = personSnapshot?.id
    self.note = note
    self.category = category
  }
}

extension TripPackingItem {
  var state: PackingState {
    get { PackingState(rawValue: stateRaw) ?? .unpacked }
    set { stateRaw = newValue.rawValue }
  }

  var source: ItemSource {
    get { ItemSource(rawValue: sourceRaw) ?? .manual }
    set { sourceRaw = newValue.rawValue }
  }

  /// Bridge over the `subItemsData` JSON blob (feature
  /// `packing-item-subitems`). Lives in an extension so the `@Model` macro
  /// never treats it as a stored relationship. Invariant: an empty list ⇒
  /// no sub-items, treated identically whether `subItemsData` is `nil` or a
  /// non-nil empty `Data()` — the getter normalises empty `Data()` to `[]`
  /// (`CodableBridge.encode` returns empty `Data()`, never nil, on its
  /// degrade path), and the setter stores `nil` for an empty list. Order is
  /// array order (Req 1.3).
  var subItems: [String] {
    get {
      guard let data = subItemsData, !data.isEmpty else { return [] }
      return CodableBridge.decode(
        data,
        as: [String].self,
        default: [],
        label: "TripPackingItem.subItems"
      )
    }
    set {
      subItemsData =
        newValue.isEmpty
        ? nil
        : CodableBridge.encode(newValue, label: "TripPackingItem.subItems")
    }
  }

  /// Bridge over the `personSnapshotID` value reference. Lives in an
  /// extension so the `@Model` macro never treats it as a stored
  /// relationship (it has no inverse to CloudKit — that is the whole
  /// point of the value reference). Resolves the snapshot in-memory via
  /// the owning trip's `participantSnapshots`, falling back to a fetch
  /// from the item's `modelContext` when the trip-side array isn't wired
  /// (e.g. a freshly decoded CloudKit record, or a snapshot attached via
  /// the unpaired `TripPersonSnapshot.trip` back-link only). The item and
  /// its snapshot are both trip-zone records in `tripsLocal`, so the
  /// fallback fetches from that store — the bridge never crosses into the
  /// owner's `globals` zone (the reason snapshots exist; Decision 7).
  /// Returns `nil` for a dangling ID — references are tolerated, not enforced.
  var personSnapshot: TripPersonSnapshot? {
    get {
      guard let snapshotID = personSnapshotID else { return nil }
      let onTrip = (trip?.participantSnapshots ?? []).first { $0.id == snapshotID }
      if let onTrip { return onTrip }
      guard let modelContext else { return nil }
      let descriptor = FetchDescriptor<TripPersonSnapshot>(
        predicate: #Predicate { $0.id == snapshotID }
      )
      return try? modelContext.fetch(descriptor).first
    }
    set { personSnapshotID = newValue?.id }
  }
}
