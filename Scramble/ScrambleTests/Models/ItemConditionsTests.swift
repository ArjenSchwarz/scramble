import Foundation
import Testing

@testable import Scramble

@Suite("ItemConditions")
struct ItemConditionsTests {

  // MARK: - Evaluator semantics

  private static func tripWith(weather: [String] = [], duration: String? = nil) -> TripAttributes {
    var attrs = TripAttributes()
    for value in weather { attrs.toggle(.weather, value: value) }
    if let duration { attrs.setSingle(.duration, value: duration) }
    return attrs
  }

  @Test("always evaluates true")
  func alwaysTrue() {
    let attrs = TripAttributes()
    #expect(ItemConditions.always.evaluate(against: attrs))
  }

  @Test("match hit when any value overlaps")
  func matchHit() {
    let attrs = Self.tripWith(weather: ["rain", "cold"])
    let cond: ItemConditions = .match(attribute: .weather, anyOf: ["rain"])
    #expect(cond.evaluate(against: attrs))
  }

  @Test("match hit with multiple anyOf values")
  func matchHitMultiAnyOf() {
    let attrs = Self.tripWith(weather: ["rain"])
    let cond: ItemConditions = .match(attribute: .weather, anyOf: ["sunny", "rain"])
    #expect(cond.evaluate(against: attrs))
  }

  @Test("match miss when no value overlaps")
  func matchMiss() {
    let attrs = Self.tripWith(weather: ["cold"])
    let cond: ItemConditions = .match(attribute: .weather, anyOf: ["rain", "sunny"])
    #expect(!cond.evaluate(against: attrs))
  }

  @Test("match miss when attribute unset on trip")
  func matchMissAttributeUnset() {
    let attrs = TripAttributes()
    let cond: ItemConditions = .match(attribute: .weather, anyOf: ["rain"])
    #expect(!cond.evaluate(against: attrs))
  }

  @Test("all true when every child true")
  func allTrue() {
    let attrs = Self.tripWith(weather: ["rain"], duration: "week")
    let cond: ItemConditions = .all([
      .match(attribute: .weather, anyOf: ["rain"]),
      .match(attribute: .duration, anyOf: ["week"]),
    ])
    #expect(cond.evaluate(against: attrs))
  }

  @Test("all false when any child false")
  func allFalseOneChildFalse() {
    let attrs = Self.tripWith(weather: ["rain"], duration: "weekend")
    let cond: ItemConditions = .all([
      .match(attribute: .weather, anyOf: ["rain"]),
      .match(attribute: .duration, anyOf: ["week"]),
    ])
    #expect(!cond.evaluate(against: attrs))
  }

  @Test("any true when any child true")
  func anyTrue() {
    let attrs = Self.tripWith(weather: ["rain"])
    let cond: ItemConditions = .any([
      .match(attribute: .duration, anyOf: ["week"]),
      .match(attribute: .weather, anyOf: ["rain"]),
    ])
    #expect(cond.evaluate(against: attrs))
  }

  @Test("any false when all children false")
  func anyFalseAllChildrenFalse() {
    let attrs = Self.tripWith(weather: ["cold"])
    let cond: ItemConditions = .any([
      .match(attribute: .duration, anyOf: ["week"]),
      .match(attribute: .weather, anyOf: ["rain"]),
    ])
    #expect(!cond.evaluate(against: attrs))
  }

  @Test("empty all is vacuously true")
  func emptyAllVacuouslyTrue() {
    let attrs = TripAttributes()
    #expect(ItemConditions.all([]).evaluate(against: attrs))
  }

  @Test("empty any is vacuously false")
  func emptyAnyVacuouslyFalse() {
    let attrs = TripAttributes()
    #expect(!ItemConditions.any([]).evaluate(against: attrs))
  }

  @Test("evaluate is idempotent (deterministic)")
  func evaluateIdempotent() {
    let attrs = Self.tripWith(weather: ["rain"], duration: "week")
    let cond: ItemConditions = .all([
      .match(attribute: .weather, anyOf: ["rain"]),
      .any([
        .match(attribute: .duration, anyOf: ["week"]),
        .match(attribute: .duration, anyOf: ["weekend"]),
      ]),
    ])
    let first = cond.evaluate(against: attrs)
    let second = cond.evaluate(against: attrs)
    #expect(first == second)
  }

  @Test("distributive equivalence: .all([.match(x)]) == .match(x)")
  func distributiveEquivalence() {
    for trip in Self.equivalenceTrips() {
      let single: ItemConditions = .match(attribute: .weather, anyOf: ["rain"])
      let wrapped: ItemConditions = .all([single])
      #expect(single.evaluate(against: trip) == wrapped.evaluate(against: trip))
    }
  }

  private static func equivalenceTrips() -> [TripAttributes] {
    [
      TripAttributes(),
      tripWith(weather: ["rain"]),
      tripWith(weather: ["cold"]),
      tripWith(weather: ["rain", "cold"]),
    ]
  }

  // MARK: - Codable round-trip

  @Test(
    "round-trip property: decode(encode(c)) == c (depth ≤ 3)",
    arguments: ItemConditionsTests.generatedSamples()
  )
  func roundTripProperty(sample: ItemConditions) throws {
    let data = try JSONEncoder().encode(sample)
    let decoded = try JSONDecoder().decode(ItemConditions.self, from: data)
    #expect(decoded == sample)
  }

  @Test("decode-failure: corrupt blob throws")
  func decodeCorrupt() {
    let corrupt = Data([0x00, 0xFF, 0x42])
    #expect(throws: (any Error).self) {
      _ = try JSONDecoder().decode(ItemConditions.self, from: corrupt)
    }
  }

  static func generatedSamples() -> [ItemConditions] {
    let leaves: [ItemConditions] = [
      .always,
      .match(attribute: .weather, anyOf: ["rain"]),
      .match(attribute: .duration, anyOf: ["week", "two-weeks"]),
      .match(attribute: .scope, anyOf: []),
    ]
    // Depth 2 wrappers
    let depth2All: [ItemConditions] = [
      .all([]),
      .all([.always]),
      .all(leaves),
    ]
    let depth2Any: [ItemConditions] = [
      .any([]),
      .any([.always]),
      .any(leaves),
    ]
    // Depth 3 wrappers
    let depth3: [ItemConditions] = [
      .all([.any(leaves), .all([.match(attribute: .weather, anyOf: ["cold"])])]),
      .any([.all(leaves), .match(attribute: .transport, anyOf: ["car"])]),
    ]
    return leaves + depth2All + depth2Any + depth3
  }
}
