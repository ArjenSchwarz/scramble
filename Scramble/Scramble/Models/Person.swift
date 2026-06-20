import Foundation
import SwiftData

@Model
final class Person {
  var id: UUID = UUID()
  var name: String = ""
  var colorKey: String = ""

  // CloudKit-compatible: to-many relationships must be Optional and use a
  // non-`.deny` delete rule. `.deny` is unsupported by CloudKit; the actual
  // delete-guard for People is enforced at the UI layer via
  // `PersonDeleteBlocker`, so `.nullify` here is safe.
  @Relationship var trips: [Trip]? = []

  @Relationship(deleteRule: .nullify, inverse: \TripPackingItem.person)
  var tripPackingItems: [TripPackingItem]? = []

  @Relationship(deleteRule: .nullify, inverse: \MasterPackingItem.person)
  var masterPackingItems: [MasterPackingItem]? = []

  init(id: UUID = UUID(), name: String = "", colorKey: String = "") {
    self.id = id
    self.name = name
    self.colorKey = colorKey
  }
}

extension Person {
  var initial: String { name.firstGraphemeUppercased }

  /// Display-safe name: the person's `name`, or `"Unnamed"` when it is empty.
  /// `nonisolated` to match the other pure derivations in this extension (the
  /// file inherits `MainActor` isolation but this is a pure `String`
  /// derivation).
  nonisolated var displayName: String { name.isEmpty ? "Unnamed" : name }

  /// Short-form name derivation per Phase 4 design §"Short-form name
  /// derivation". Trims whitespace, returns the first space-separated token,
  /// or the full trimmed name when there is no space, or `"?"` when the name
  /// is empty/whitespace-only. `nonisolated` because the file inherits
  /// `MainActor` isolation but this is a pure `String` derivation.
  nonisolated var shortDisplayName: String {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    if let first = trimmed.split(separator: " ").first, !first.isEmpty {
      return String(first)
    }
    return trimmed.isEmpty ? "?" : trimmed
  }
}

extension String {
  /// First grapheme of the string, uppercased; falls back to "?" when empty.
  /// Used by `Person.initial` and `PersonAvatar` to render the same letter
  /// from a name. Returns the full grapheme cluster (e.g. ZWJ-joined emoji);
  /// `.uppercased()` is a no-op for those. `nonisolated` because the file
  /// inherits `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` but this is a pure
  /// `String` helper safe to call from any context.
  nonisolated var firstGraphemeUppercased: String {
    guard let first = first else { return "?" }
    return String(first).uppercased()
  }
}
