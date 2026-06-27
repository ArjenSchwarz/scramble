import Foundation

/// Value-type editor state for the master-packing create/edit screen.
nonisolated struct MasterPackingDraft: Equatable, Sendable {
  var name: String
  var personID: UUID?
  var conditions: ItemConditions
  /// Raw, unnormalized category text as typed in the editor. `nil`/empty ⇒
  /// uncategorised. Normalization (`PackingCategory.storageValue`) is applied
  /// at the persistence boundary, not here, so the field round-trips the user's
  /// in-progress edit verbatim. Declared last with a `nil` default so the
  /// synthesized memberwise initializer stays source-compatible with existing
  /// `MasterPackingDraft(name:personID:conditions:)` call sites — the synthesized
  /// memberwise init defaults optional properties to `nil` without an explicit
  /// initializer. (Req 1.1/2.1)
  var category: String?

  nonisolated enum Field: Hashable, Sendable {
    case name
    case person
  }

  func validate() -> [Field: String] {
    var errors: [Field: String] = [:]
    if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      errors[.name] = "Name is required"
    }
    if personID == nil {
      errors[.person] = "Choose a person"
    }
    return errors
  }
}

extension MasterPackingDraft {
  nonisolated static func newDraft(personID: UUID? = nil) -> MasterPackingDraft {
    MasterPackingDraft(name: "", personID: personID, conditions: .always, category: nil)
  }

  @MainActor
  init(from master: MasterPackingItem) {
    self.name = master.name
    self.personID = master.person?.id
    self.conditions = master.conditions
    self.category = master.category
  }
}
