import Foundation
import SwiftData
import os

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
    self.conditionsData = (try? JSONEncoder().encode(conditions)) ?? Data()
  }
}

extension MasterTaskItem {
  var phase: Phase {
    get { Phase(rawValue: phaseRaw) ?? .weeksBefore }
    set { phaseRaw = newValue.rawValue }
  }

  var conditions: ItemConditions {
    get {
      guard !conditionsData.isEmpty else { return .always }
      do {
        return try JSONDecoder().decode(ItemConditions.self, from: conditionsData)
      } catch {
        modelLogger.error(
          "MasterTaskItem.conditions decode failed: \(error.localizedDescription, privacy: .public)"
        )
        return .always
      }
    }
    set {
      do {
        conditionsData = try JSONEncoder().encode(newValue)
      } catch {
        modelLogger.error(
          "MasterTaskItem.conditions encode failed: \(error.localizedDescription, privacy: .public)"
        )
        conditionsData = Data()
      }
    }
  }
}
