import Foundation
import SwiftData

@Model
final class MasterPackingItem {
  var id: UUID = UUID()
  var name: String = ""

  @Relationship var person: Person?

  var conditionsData: Data = Data()

  /// Optional free-text category (feature `packing-item-categories`). `nil`
  /// or empty ⇒ uncategorised. Stored trimmed + internal-whitespace-collapsed
  /// with case preserved; normalization lives in the `PackingCategory`
  /// namespace, not here. Optional with a `nil` default so it rides on the
  /// existing `SchemaV3` via lightweight inference — a property-only addition
  /// to a shared top-level class cannot be a distinct `SchemaV4` (see
  /// `persistence.md`). This is the source value re-stamped onto derived
  /// trip items (Decision 2).
  var category: String?

  init(
    id: UUID = UUID(),
    name: String = "",
    person: Person? = nil,
    conditions: ItemConditions = .always,
    category: String? = nil
  ) {
    self.id = id
    self.name = name
    self.person = person
    self.conditionsData = CodableBridge.encode(conditions, label: "MasterPackingItem.conditions")
    self.category = category
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
