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
  var initial: String {
    guard let first = name.first else { return "?" }
    return String(first).uppercased()
  }
}
