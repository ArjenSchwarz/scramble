import Foundation
import Testing

@testable import Scramble

/// Phase 6 — `CountryFlag.emoji(for:)` regional-indicator scalar arithmetic
/// (Req 6.3, 6.4). Returns the flag emoji for any two-ASCII-letter code,
/// `nil` for nil / wrong-length / non-letter input. Validation against the
/// ISO list is non-goal (Req 6.5); "XZ" returns a "(blank)" flag rather
/// than `nil`.
@Suite("CountryFlag")
struct CountryFlagTests {

  @Test(
    "Valid alpha-2 codes return the correct regional-indicator flag",
    arguments: [
      ("NL", "🇳🇱"),
      ("JP", "🇯🇵"),
      ("IS", "🇮🇸"),
      ("US", "🇺🇸"),
      ("nl", "🇳🇱"),  // lowercase normalised
      ("Jp", "🇯🇵"),  // mixed case normalised
    ])
  func validAlpha2(code: String, expected: String) {
    #expect(CountryFlag.emoji(for: code) == expected)
  }

  @Test(
    "Invalid input returns nil",
    arguments: [
      String?.none,
      "",
      "N",
      "NLD",
      "12",
      "N1",
      "  ",
      "NL ",
    ])
  func invalidInput(code: String?) {
    #expect(CountryFlag.emoji(for: code) == nil)
  }
}
