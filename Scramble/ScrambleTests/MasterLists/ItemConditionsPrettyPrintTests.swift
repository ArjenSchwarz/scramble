import Foundation
import Testing

@testable import Scramble

@Suite("ItemConditions prettyPrinted(indent:)")
struct ItemConditionsPrettyPrintTests {

  @Test(".always prints as 'always'")
  func alwaysPrintsAsAlways() {
    #expect(ItemConditions.always.prettyPrinted() == "always")
  }

  @Test(".match single value")
  func matchSingleValue() {
    let cond: ItemConditions = .match(attribute: .scope, anyOf: ["international"])
    #expect(cond.prettyPrinted() == "scope is International")
  }

  @Test(".match multiple values joined with ' or '")
  func matchMultipleValues() {
    let cond: ItemConditions = .match(attribute: .weather, anyOf: ["rain", "cold"])
    #expect(cond.prettyPrinted() == "weather is Rain or Cold")
  }

  @Test(".all renders multi-line 'all of:' with two-space indented children")
  func allMultiLine() {
    let cond: ItemConditions = .all([
      .match(attribute: .weather, anyOf: ["rain"]),
      .match(attribute: .scope, anyOf: ["international"])
    ])
    let expected = """
      all of:
        weather is Rain
        scope is International
      """
    #expect(cond.prettyPrinted() == expected)
  }

  @Test("nested .any renders 'any of:' with indented children")
  func nestedAny() {
    let cond: ItemConditions = .all([
      .any([
        .match(attribute: .weather, anyOf: ["rain"]),
        .match(attribute: .weather, anyOf: ["cold"])
      ]),
      .match(attribute: .scope, anyOf: ["international"])
    ])
    let expected = """
      all of:
        any of:
          weather is Rain
          weather is Cold
        scope is International
      """
    #expect(cond.prettyPrinted() == expected)
  }

  @Test("indent parameter offsets every line")
  func indentOffset() {
    let cond: ItemConditions = .all([
      .match(attribute: .weather, anyOf: ["rain"])
    ])
    let expected = "  all of:\n    weather is Rain"
    #expect(cond.prettyPrinted(indent: 1) == expected)
  }

  @Test("standalone .any at top level prints with 'any of:'")
  func topLevelAny() {
    let cond: ItemConditions = .any([
      .match(attribute: .weather, anyOf: ["rain"]),
      .match(attribute: .weather, anyOf: ["cold"])
    ])
    let expected = """
      any of:
        weather is Rain
        weather is Cold
      """
    #expect(cond.prettyPrinted() == expected)
  }

  @Test("ZWJ-emoji in match value does not crash")
  func zwjEmojiDoesNotCrash() {
    let cond: ItemConditions = .match(attribute: .weather, anyOf: ["👨‍👩‍👦 family"])
    // Only assertion is that the call returns without trapping.
    let printed = cond.prettyPrinted()
    #expect(printed.contains("weather is"))
  }
}
