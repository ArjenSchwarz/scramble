import Foundation
import SwiftData
import os

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
    self.conditionsData = (try? JSONEncoder().encode(conditions)) ?? Data()
  }
}

extension MasterPackingItem {
  var conditions: ItemConditions {
    get {
      guard !conditionsData.isEmpty else { return .always }
      do {
        return try JSONDecoder().decode(ItemConditions.self, from: conditionsData)
      } catch {
        modelLogger.error(
          "MasterPackingItem.conditions decode failed: \(error.localizedDescription, privacy: .public)"
        )
        return .always
      }
    }
    set {
      do {
        conditionsData = try JSONEncoder().encode(newValue)
      } catch {
        modelLogger.error(
          "MasterPackingItem.conditions encode failed: \(error.localizedDescription, privacy: .public)"
        )
        conditionsData = Data()
      }
    }
  }
}
