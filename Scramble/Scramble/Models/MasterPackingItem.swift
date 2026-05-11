import Foundation
import SwiftData

@Model
final class MasterPackingItem {
  var id: UUID = UUID()
  var name: String = ""

  @Relationship var person: Person?

  var conditionsData: Data = Data()

  init(
    id: UUID = UUID(),
    name: String = "",
    person: Person? = nil,
    conditions: ItemConditions = .always
  ) {
    self.id = id
    self.name = name
    self.person = person
    self.conditionsData = CodableBridge.encode(conditions, label: "MasterPackingItem.conditions")
  }
}

extension MasterPackingItem {
  var conditions: ItemConditions {
    get {
      CodableBridge.decode(
        conditionsData,
        as: ItemConditions.self,
        default: .always,
        label: "MasterPackingItem.conditions"
      )
    }
    set {
      conditionsData = CodableBridge.encode(newValue, label: "MasterPackingItem.conditions")
    }
  }
}
