import Foundation

/// Value-type editor state for the master-task create/edit screen.
nonisolated struct MasterTaskDraft: Equatable, Sendable {
  var name: String
  var phase: Phase
  var conditions: ItemConditions

  nonisolated enum Field: Hashable, Sendable {
    case name
  }

  func validate() -> [Field: String] {
    var errors: [Field: String] = [:]
    if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      errors[.name] = "Name is required"
    }
    return errors
  }
}

extension MasterTaskDraft {
  nonisolated static func newDraft() -> MasterTaskDraft {
    MasterTaskDraft(name: "", phase: .weeksBefore, conditions: .always)
  }

  @MainActor
  init(from master: MasterTaskItem) {
    self.name = master.name
    self.phase = master.phase
    self.conditions = master.conditions
  }
}
