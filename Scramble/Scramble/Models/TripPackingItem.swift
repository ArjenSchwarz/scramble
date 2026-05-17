import Foundation
import SwiftData

@Model
final class TripPackingItem {
  var id: UUID = UUID()
  @Relationship var trip: Trip?

  /// Deprecated in V3, removed in V4. New code reads `personSnapshot`
  /// (Decision 7) so a shared trip renders without crossing into the
  /// owner's globals zone.
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
  @Relationship var personSnapshot: TripPersonSnapshot?

  /// V3 — see `Trip.ckRecordSystemFields`.
  var ckRecordSystemFields: Data?

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
    personSnapshot: TripPersonSnapshot? = nil
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
    self.personSnapshot = personSnapshot
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
}
