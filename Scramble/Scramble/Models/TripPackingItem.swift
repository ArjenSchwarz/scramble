import Foundation
import SwiftData

@Model
final class TripPackingItem {
  var id: UUID = UUID()
  @Relationship var trip: Trip?
  @Relationship var person: Person?

  var masterItemID: UUID?
  var name: String = ""
  var stateRaw: String = PackingState.unpacked.rawValue
  var sourceRaw: String = ItemSource.manual.rawValue
  var currentlyMatchesRules: Bool = true
  var pinnedByUser: Bool = false

  init(
    id: UUID = UUID(),
    trip: Trip? = nil,
    person: Person? = nil,
    masterItemID: UUID? = nil,
    name: String = "",
    state: PackingState = .unpacked,
    source: ItemSource = .manual,
    currentlyMatchesRules: Bool = true,
    pinnedByUser: Bool = false
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
