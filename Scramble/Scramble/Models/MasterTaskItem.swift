import Foundation
import SwiftData

@Model
final class MasterTaskItem {
  var id: UUID = UUID()
  var name: String = ""
  var phaseRaw: String = Phase.weeksBefore.rawValue
  var conditionsData: Data = Data()

  init(
    id: UUID = UUID(),
    name: String = "",
    phase: Phase = .weeksBefore,
    conditions: ItemConditions = .always
  ) {
    self.id = id
    self.name = name
    self.phaseRaw = phase.rawValue
    self.conditionsData = CodableBridge.encode(conditions, label: "MasterTaskItem.conditions")
  }
}

extension MasterTaskItem {
  var phase: Phase {
    get { Phase(rawValue: phaseRaw) ?? .weeksBefore }
    set { phaseRaw = newValue.rawValue }
  }

  var conditions: ItemConditions {
    get {
      CodableBridge.decode(
        conditionsData,
        as: ItemConditions.self,
        default: .always,
        label: "MasterTaskItem.conditions"
      )
    }
    set {
      conditionsData = CodableBridge.encode(newValue, label: "MasterTaskItem.conditions")
    }
  }
}
