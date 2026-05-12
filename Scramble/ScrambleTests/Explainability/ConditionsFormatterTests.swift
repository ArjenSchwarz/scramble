import Foundation
import Testing

@testable import Scramble

@Suite("ConditionsFormatter")
struct ConditionsFormatterTests {

  // MARK: - Helpers

  private static func attrs(_ pairs: [(TripAttribute, [String])]) -> TripAttributes {
    var a = TripAttributes()
    for (attr, vals) in pairs {
      for v in vals { a.toggle(attr, value: v) }
    }
    return a
  }

  // MARK: - AND across attribute types ('+')

  @Test("AND across attribute types joined with ' + '")
  func andAcrossAttributeTypes() {
    let cond: ItemConditions = .all([
      .match(attribute: .weather, anyOf: ["rain"]),
      .match(attribute: .duration, anyOf: ["week"])
    ])
    let trip = Self.attrs([(.weather, ["rain"]), (.duration, ["week"])])
    // TripAttribute.allCases order is: duration, transport, scope, weather, purpose
    #expect(ConditionsFormatter.format(cond, against: trip) == "Week + Rain")
  }

  // MARK: - OR within attribute type ('or')

  @Test("OR within attribute type joined with ' or '")
  func orWithinAttributeType() {
    let cond: ItemConditions = .match(attribute: .weather, anyOf: ["rain", "snow"])
    let trip = Self.attrs([(.weather, ["rain", "snow"])])
    #expect(ConditionsFormatter.format(cond, against: trip) == "Rain or Snow")
  }

  @Test("OR within attribute type returns only intersected values")
  func orWithinReturnsIntersection() {
    let cond: ItemConditions = .match(attribute: .weather, anyOf: ["rain", "snow", "sun"])
    // Trip only has rain selected — sun and snow are not in the trip's attrs.
    let trip = Self.attrs([(.weather, ["rain"])])
    #expect(ConditionsFormatter.format(cond, against: trip) == "Rain")
  }

  // MARK: - Iteration order matches TripAttribute.allCases

  @Test("Iteration order follows TripAttribute.allCases regardless of insertion order")
  func iterationOrderDeterministic() {
    // Build the same logical condition with attribute types in reversed order.
    // Order in source: purpose, weather, scope, transport, duration (reverse of allCases)
    let cond: ItemConditions = .all([
      .match(attribute: .purpose, anyOf: ["leisure"]),
      .match(attribute: .weather, anyOf: ["rain"]),
      .match(attribute: .scope, anyOf: ["domestic"]),
      .match(attribute: .transport, anyOf: ["car"]),
      .match(attribute: .duration, anyOf: ["week"])
    ])
    let trip = Self.attrs([
      (.purpose, ["leisure"]),
      (.weather, ["rain"]),
      (.scope, ["domestic"]),
      (.transport, ["car"]),
      (.duration, ["week"])
    ])
    // Expected order matches TripAttribute.allCases:
    // duration, transport, scope, weather, purpose
    #expect(
      ConditionsFormatter.format(cond, against: trip) == "Week + Car + Domestic + Rain + Leisure")
  }

  // MARK: - Empty intersection

  @Test("Empty intersection (master conditions match nothing on trip) returns empty string")
  func emptyIntersection() {
    let cond: ItemConditions = .match(attribute: .weather, anyOf: ["snow"])
    let trip = Self.attrs([(.weather, ["rain"])])
    #expect(ConditionsFormatter.format(cond, against: trip) == "")
  }

  @Test("Empty intersection when trip has no selected attributes returns empty string")
  func emptyIntersectionNoTripAttrs() {
    let cond: ItemConditions = .match(attribute: .weather, anyOf: ["rain"])
    let trip = TripAttributes()
    #expect(ConditionsFormatter.format(cond, against: trip) == "")
  }

  // MARK: - .always

  @Test(".always returns empty string (no matched values)")
  func alwaysReturnsEmpty() {
    let trip = Self.attrs([(.weather, ["rain"]), (.duration, ["week"])])
    #expect(ConditionsFormatter.format(.always, against: trip) == "")
  }

  // MARK: - Nested / .any / .all combinations

  @Test(".all of two matches yields the same output as a top-level AND across types")
  func allOfTwoMatches() {
    let cond: ItemConditions = .all([
      .match(attribute: .weather, anyOf: ["rain"]),
      .match(attribute: .transport, anyOf: ["car"])
    ])
    let trip = Self.attrs([(.weather, ["rain"]), (.transport, ["car"])])
    // TripAttribute.allCases puts transport before weather.
    #expect(ConditionsFormatter.format(cond, against: trip) == "Car + Rain")
  }

  @Test(".any across types collapses to per-attribute OR groups joined by ' + '")
  func anyAcrossTypes() {
    let cond: ItemConditions = .any([
      .match(attribute: .weather, anyOf: ["rain"]),
      .match(attribute: .duration, anyOf: ["week"])
    ])
    let trip = Self.attrs([(.weather, ["rain"]), (.duration, ["week"])])
    // Both branches contribute distinct attribute types — duration first, then weather.
    #expect(ConditionsFormatter.format(cond, against: trip) == "Week + Rain")
  }

  @Test("Multiple .match branches on the same attribute type collapse to a single OR group")
  func sameAttributeRepeated() {
    let cond: ItemConditions = .any([
      .match(attribute: .weather, anyOf: ["rain"]),
      .match(attribute: .weather, anyOf: ["snow"])
    ])
    let trip = Self.attrs([(.weather, ["rain", "snow"])])
    // Both values match within weather — they are joined by ' or ' under a single group.
    let out = ConditionsFormatter.format(cond, against: trip)
    #expect(
      out == "Rain or Snow" || out == "Snow or Rain",
      "Got unexpected value: \(out)")
  }

  // MARK: - Partial matches across multiple attributes

  @Test("Partial trip attribute selection only outputs the attributes that actually overlap")
  func partialMatch() {
    let cond: ItemConditions = .all([
      .match(attribute: .weather, anyOf: ["rain"]),
      .match(attribute: .duration, anyOf: ["week"])
    ])
    // Trip selects only weather; duration not selected.
    let trip = Self.attrs([(.weather, ["rain"])])
    #expect(ConditionsFormatter.format(cond, against: trip) == "Rain")
  }
}
