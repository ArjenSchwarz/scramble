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
