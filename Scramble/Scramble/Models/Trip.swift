import Foundation
import SwiftData

@Model
final class Trip {
  var id: UUID = UUID()
  var name: String = ""
  var startDate: Date = Date.distantPast
  var endDate: Date = Date.distantPast
  var attributesData: Data = Data()

  // CloudKit-compatible: to-many relationships must be Optional arrays.
  @Relationship(deleteRule: .nullify, inverse: \Person.trips)
  var participants: [Person]? = []

  @Relationship(deleteRule: .cascade, inverse: \TripTask.trip)
  var tasks: [TripTask]? = []

  @Relationship(deleteRule: .cascade, inverse: \TripPackingItem.trip)
  var packingItems: [TripPackingItem]? = []

  /// V3 — denormalised person identity carried inside the trip zone so
  /// participants can render the trip without access to the owner's
  /// globals zone (Req 2.2, Decision 7). One-way relationship without an
  /// `inverse:` declaration: SwiftData's bidirectional cascade traversal
  /// on iOS 26.4 panics when the chain reaches the snapshot ↔
  /// packing-item nullify pair, so trip-deletion clean-up is performed
  /// explicitly by the snapshot maintenance routine instead of relying
  /// on the relationship rule. The `TripPersonSnapshot.trip` back-link
  /// is the canonical navigation direction; this property exists for
  /// convenience reads on the trip side.
  @Relationship(deleteRule: .nullify)
  var participantSnapshots: [TripPersonSnapshot]? = []

  /// V3 — links to `TripZoneState.tripID` for trips that have been moved
  /// into their per-trip CloudKit zone (Req 4.1, Decision 13). `nil` for
  /// trips still in the default zone or running offline.
  var tripZoneID: UUID?

  /// V3 — cached `CKRecord` system fields for the trip's record so writes
  /// preserve serverChangeTag / share state across saves (design.md
  /// "system fields are preserved on every write"). Optional because
  /// pre-Phase-5 records and freshly created trips have no cache yet.
  var ckRecordSystemFields: Data?

  init(
    id: UUID = UUID(),
    name: String = "",
    startDate: Date = .distantPast,
    endDate: Date = .distantPast,
    attributes: TripAttributes = TripAttributes()
  ) {
    self.id = id
    self.name = name
    self.startDate = startDate
    self.endDate = endDate
    self.attributesData = CodableBridge.encode(attributes, label: "Trip.attributes")
  }
}

extension Trip {
  var attributes: TripAttributes {
    get {
      CodableBridge.decode(
        attributesData,
        as: TripAttributes.self,
        default: TripAttributes(),
        label: "Trip.attributes"
      )
    }
    set {
      attributesData = CodableBridge.encode(newValue, label: "Trip.attributes")
    }
  }
}
