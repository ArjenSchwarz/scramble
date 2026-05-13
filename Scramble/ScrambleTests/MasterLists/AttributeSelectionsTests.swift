import Foundation
import Testing

@testable import Scramble

@Suite("AttributeSelections ↔ ItemConditions bridge")
struct AttributeSelectionsTests {

  // MARK: - Empty / .always round-trip

  @Test("AttributeSelections.empty.toConditions() == .always")
  func emptyToAlways() {
    #expect(AttributeSelections.empty.toConditions() == .always)
  }

  @Test("from(.always) returns .empty")
  func fromAlwaysReturnsEmpty() {
    #expect(AttributeSelections.from(.always) == AttributeSelections.empty)
  }

  // MARK: - v1 shape round-trip

  @Test("from(.all([.match(.weather, [rain, cold])])) produces matching chip selections")
  func fromSingleAttribute() {
    let cond: ItemConditions = .all([.match(attribute: .weather, anyOf: ["rain", "cold"])])
    let sel = AttributeSelections.from(cond)
    #expect(sel?.byAttribute[.weather] == Set(["rain", "cold"]))
    #expect(sel?.byAttribute.keys.contains(.duration) == false)
  }

  @Test("toConditions sorts match values alphabetically for stable encoding")
  func toConditionsSortsValuesAlphabetically() {
    var sel = AttributeSelections.empty
    sel.byAttribute[.weather] = Set(["rain", "cold"])
    #expect(sel.toConditions() == .all([.match(attribute: .weather, anyOf: ["cold", "rain"])]))
  }

  @Test("from then toConditions round-trip yields sorted-values .all shape")
  func fromThenToConditionsRoundTrip() {
    let cond: ItemConditions = .all([.match(attribute: .weather, anyOf: ["rain", "cold"])])
    let sel = AttributeSelections.from(cond)
    #expect(sel?.toConditions() == .all([.match(attribute: .weather, anyOf: ["cold", "rain"])]))
  }

  @Test("toConditions emits matches in TripAttribute declaration order")
  func toConditionsEmitsDeclarationOrder() {
    var sel = AttributeSelections.empty
    // Insert out-of-order to prove iteration order is driven by TripAttribute.allCases.
    sel.byAttribute[.weather] = Set(["rain"])
    sel.byAttribute[.duration] = Set(["short"])
    sel.byAttribute[.scope] = Set(["international"])
    let conds = sel.toConditions()
    let expected: ItemConditions = .all([
      .match(attribute: .duration, anyOf: ["short"]),
      .match(attribute: .scope, anyOf: ["international"]),
      .match(attribute: .weather, anyOf: ["rain"]),
    ])
    #expect(conds == expected)
  }

  @Test("from(.all([.match...])) preserves multiple attributes")
  func fromMultipleAttributes() {
    let cond: ItemConditions = .all([
      .match(attribute: .weather, anyOf: ["cold", "rain"]),
      .match(attribute: .scope, anyOf: ["international"]),
    ])
    let sel = AttributeSelections.from(cond)
    #expect(sel?.byAttribute[.weather] == Set(["rain", "cold"]))
    #expect(sel?.byAttribute[.scope] == Set(["international"]))
  }

  // MARK: - Non-v1 shapes return nil

  @Test("from(.any(...)) at top level returns nil")
  func fromTopLevelAnyIsNil() {
    let cond: ItemConditions = .any([.match(attribute: .weather, anyOf: ["rain"])])
    #expect(AttributeSelections.from(cond) == nil)
  }

  @Test("from(.all([.all([...])])) returns nil — nested .all inside .all child")
  func fromNestedAllInsideAllIsNil() {
    let cond: ItemConditions = .all([
      .all([.match(attribute: .weather, anyOf: ["rain"])])
    ])
    #expect(AttributeSelections.from(cond) == nil)
  }

  @Test("from(.all([.any([...])])) returns nil — nested .any inside .all child")
  func fromNestedAnyInsideAllIsNil() {
    let cond: ItemConditions = .all([
      .any([.match(attribute: .weather, anyOf: ["rain"])])
    ])
    #expect(AttributeSelections.from(cond) == nil)
  }

  @Test("from(.match with out-of-domain anyOf value) returns nil")
  func fromOutOfDomainValueIsNil() {
    let cond: ItemConditions = .all([
      .match(attribute: .weather, anyOf: ["rain", "snowstorm"])
    ])
    #expect(AttributeSelections.from(cond) == nil)
  }

  @Test("from(.match with empty anyOf) returns nil")
  func fromEmptyAnyOfIsNil() {
    let cond: ItemConditions = .all([
      .match(attribute: .weather, anyOf: [])
    ])
    #expect(AttributeSelections.from(cond) == nil)
  }

  @Test("from(.all([.always])) returns nil — non-.match child")
  func fromAlwaysInsideAllIsNil() {
    let cond: ItemConditions = .all([.always])
    #expect(AttributeSelections.from(cond) == nil)
  }

  // MARK: - isInDomain

  @Test("isInDomain true for empty selections")
  func isInDomainEmpty() {
    #expect(AttributeSelections.empty.isInDomain())
  }

  @Test("isInDomain true for all valid domain values")
  func isInDomainValid() {
    var sel = AttributeSelections.empty
    sel.byAttribute[.weather] = Set(["rain", "cold"])
    sel.byAttribute[.scope] = Set(["international"])
    #expect(sel.isInDomain())
  }

  @Test("isInDomain false when any value falls outside the attribute's domain")
  func isInDomainInvalid() {
    var sel = AttributeSelections.empty
    sel.byAttribute[.weather] = Set(["rain", "snowstorm"])
    #expect(!sel.isInDomain())
  }

  // MARK: - PBT: random v1-shaped conditions round-trip

  @Test(
    "PBT: random v1-shaped conditions round-trip equal",
    arguments: AttributeSelectionsTests.v1Samples()
  )
  func v1RoundTripProperty(selection: AttributeSelections) {
    let conds = selection.toConditions()
    let recovered = AttributeSelections.from(conds)
    #expect(recovered == selection)
  }

  /// Generate a variety of v1-shaped `AttributeSelections` covering empty,
  /// single-attribute single-value, single-attribute multi-value, and
  /// multi-attribute combinations. Values are drawn from
  /// `TripAttributeOptions.values(for:)` so every generated case is in-domain.
  static func v1Samples() -> [AttributeSelections] {
    var seeds: [AttributeSelections] = [.empty]

    for attr in TripAttribute.allCases {
      let domain = TripAttributeOptions.values(for: attr)
      // Single-value
      for v in domain {
        var s = AttributeSelections.empty
        s.byAttribute[attr] = [v]
        seeds.append(s)
      }
      // All values for that attribute
      if domain.count >= 2 {
        var s = AttributeSelections.empty
        s.byAttribute[attr] = Set(domain)
        seeds.append(s)
      }
    }

    // Multi-attribute combinations
    let combos: [(TripAttribute, TripAttribute)] = [
      (.weather, .scope), (.duration, .transport), (.weather, .purpose),
    ]
    for (a, b) in combos {
      var s = AttributeSelections.empty
      s.byAttribute[a] = Set(TripAttributeOptions.values(for: a))
      s.byAttribute[b] = Set([TripAttributeOptions.values(for: b).first!])
      seeds.append(s)
    }
    return seeds
  }
}
