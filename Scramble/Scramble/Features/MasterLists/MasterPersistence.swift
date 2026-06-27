import Foundation
import SwiftData
import os

/// Outcome of `MasterPersistence.copyPacking`. Value-only — it carries no
/// `@Model` instances out of the helper, so it crosses isolation boundaries
/// freely and feeds `copyToastMessage` from any context.
nonisolated struct CopyResult: Sendable {
  /// Copies inserted into the context, NOT yet saved.
  var createdCount: Int
  /// Names of the target people that received a copy.
  var copiedNames: [String]
  /// Names of the target people skipped because they already owned a
  /// same-name item.
  var skippedNames: [String]
}

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
      conditions: draft.conditions,
      category: PackingCategory.storageValue(draft.category)
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
    item.category = PackingCategory.storageValue(draft.category)
  }

  static func deletePacking(_ item: MasterPackingItem, in context: ModelContext) {
    context.delete(item)
  }

  // MARK: - Copy master packing to people

  /// Trimmed + case-insensitive key for same-name detection (Req 2.3 / 3.5).
  /// `nonisolated` because `MasterPersistence` is a `@MainActor` enum but this
  /// is a pure `String` derivation safe to call from any context (and from
  /// unit tests without `await`).
  nonisolated static func normalizedName(_ raw: String) -> String {
    raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
  }

  /// Builds the 5.1 / 5.2 / 3.7 confirmation strings from the plain name
  /// arrays (not the `@Model`-bearing `CopyResult`) so it stays `nonisolated`
  /// and unit-testable. Three outcomes:
  /// - copied-only: lists the people who received the item;
  /// - copied-with-skips: lists copied people and notes who was skipped;
  /// - all-skipped (empty `copiedNames`): states everyone already had it.
  nonisolated static func copyToastMessage(
    copiedNames: [String],
    skippedNames: [String]
  ) -> String {
    let copied = formatNames(copiedNames)
    let skipped = formatNames(skippedNames)

    if copiedNames.isEmpty {
      return "Everyone already had this item — skipped \(skipped)."
    }
    if skippedNames.isEmpty {
      return "Copied to \(copied)."
    }
    return "Copied to \(copied). Skipped \(skipped) — already had it."
  }

  /// Inserts one copy per target person that does not already own a same-name
  /// item. De-duplicates `toPersonIDs` (it is the sole authority on what gets
  /// created). Does NOT call `save()` — the caller owns the
  /// mutate → save → run-engine sequence, per the `MasterPersistence`
  /// convention. The same-name check covers Req 3.5 (a target that became a
  /// same-name owner since the picker opened).
  @discardableResult
  static func copyPacking(
    source: MasterPackingItem,
    toPersonIDs: [UUID],
    in context: ModelContext
  ) -> CopyResult {
    let trimmedName = source.name.trimmingCharacters(in: .whitespacesAndNewlines)
    let sourceConditions = source.conditions
    let sourceCategory = PackingCategory.storageValue(source.category)
    let sourceKey = normalizedName(trimmedName)

    var result = CopyResult(createdCount: 0, copiedNames: [], skippedNames: [])
    var seen = Set<UUID>()

    for id in toPersonIDs {
      guard seen.insert(id).inserted else { continue }
      guard let target = resolvePerson(id: id, in: context) else { continue }

      let alreadyOwns = (target.masterPackingItems ?? []).contains {
        normalizedName($0.name) == sourceKey
      }
      if alreadyOwns {
        result.skippedNames.append(target.name)
        continue
      }

      let copy = MasterPackingItem(
        name: trimmedName,
        person: target,
        conditions: sourceConditions,
        category: sourceCategory
      )
      context.insert(copy)
      result.createdCount += 1
      result.copiedNames.append(target.name)
    }

    return result
  }

  /// Joins names with commas and a trailing "and" for the final element so the
  /// toast reads naturally for one, two, or many people.
  private nonisolated static func formatNames(_ names: [String]) -> String {
    switch names.count {
    case 0:
      return ""
    case 1:
      return names[0]
    case 2:
      return "\(names[0]) and \(names[1])"
    default:
      let head = names.dropLast().joined(separator: ", ")
      return "\(head), and \(names[names.count - 1])"
    }
  }

  // MARK: - Internal

  private static func resolvePerson(id: UUID?, in context: ModelContext) -> Person? {
    guard let id else { return nil }
    let descriptor = FetchDescriptor<Person>(
      predicate: #Predicate<Person> { $0.id == id }
    )
    do {
      return try context.fetch(descriptor).first
    } catch {
      modelLogger.error(
        "[MasterPersistence.resolvePerson] id=\(id, privacy: .public) error=\(String(describing: error), privacy: .public)"
      )
      return nil
    }
  }
}
