import Foundation
import SwiftData

/// Helpers for applying master drafts to the model context. Mirrors
/// `TripPersistence`: the helpers mutate but do NOT call `context.save()` —
/// the master editor closure owns the mutate → save → run-engine sequence
/// per design Error Handling.
@MainActor enum MasterPersistence {

  // MARK: - Master tasks

  @discardableResult
  static func createTask(
    from draft: MasterTaskDraft,
    in context: ModelContext
  ) -> MasterTaskItem {
    let item = MasterTaskItem(
      name: draft.name.trimmingCharacters(in: .whitespacesAndNewlines),
      phase: draft.phase,
      conditions: draft.conditions
    )
    context.insert(item)
    return item
  }

  static func applyTask(
    _ draft: MasterTaskDraft,
    to item: MasterTaskItem,
    in context: ModelContext
  ) {
    item.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
    item.phase = draft.phase
    item.conditions = draft.conditions
  }

  static func deleteTask(_ item: MasterTaskItem, in context: ModelContext) {
    context.delete(item)
  }

  // MARK: - Master packing

  @discardableResult
  static func createPacking(
    from draft: MasterPackingDraft,
    in context: ModelContext
  ) -> MasterPackingItem {
    let person = resolvePerson(id: draft.personID, in: context)
    let item = MasterPackingItem(
      name: draft.name.trimmingCharacters(in: .whitespacesAndNewlines),
      person: person,
      conditions: draft.conditions
    )
    context.insert(item)
    return item
  }

  static func applyPacking(
    _ draft: MasterPackingDraft,
    to item: MasterPackingItem,
    in context: ModelContext
  ) {
    item.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
    item.person = resolvePerson(id: draft.personID, in: context)
    item.conditions = draft.conditions
  }

  static func deletePacking(_ item: MasterPackingItem, in context: ModelContext) {
    context.delete(item)
  }

  // MARK: - Internal

  private static func resolvePerson(id: UUID?, in context: ModelContext) -> Person? {
    guard let id else { return nil }
    let descriptor = FetchDescriptor<Person>(
      predicate: #Predicate<Person> { $0.id == id }
    )
    return try? context.fetch(descriptor).first
  }
}
