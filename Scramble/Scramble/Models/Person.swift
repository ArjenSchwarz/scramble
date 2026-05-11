import Foundation
import SwiftData

@Model
final class Person {
  var id: UUID = UUID()
  var name: String = ""
  var colorKey: String = ""

  @Relationship var trips: [Trip] = []

  @Relationship(deleteRule: .deny, inverse: \TripPackingItem.person)
  var tripPackingItems: [TripPackingItem] = []

  @Relationship(deleteRule: .deny, inverse: \MasterPackingItem.person)
  var masterPackingItems: [MasterPackingItem] = []

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
  /// `.uppercased()` is a no-op for those.
  var firstGraphemeUppercased: String {
    guard let first = first else { return "?" }
    return String(first).uppercased()
  }
}
