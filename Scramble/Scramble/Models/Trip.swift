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
