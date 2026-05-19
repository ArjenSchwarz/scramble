import Foundation
import Testing

@testable import Scramble

/// Phase 6 — `TripDraft.normaliseCountryCode` validation (Req 6.5).
///
/// Empty input is `.clear` (treat as "set countryCode to nil"). Two ASCII
/// letters in any case are `.set(<uppercase>)`. Anything else — including
/// digits, single letter, three letters, whitespace inside the code — is
/// `.invalid` and the editor reverts to the previously-valid value.
@Suite("TripDraft countryCode normalisation")
struct TripDraftCountryCodeTests {

  @Test("Empty / whitespace input is .clear")
  func emptyIsClear() {
    #expect(TripDraft.normaliseCountryCode("") == .clear)
    #expect(TripDraft.normaliseCountryCode("   ") == .clear)
    #expect(TripDraft.normaliseCountryCode("\t\n") == .clear)
  }

  @Test(
    "Two ASCII letters are accepted and uppercased",
    arguments: [
      ("nl", "NL"),
      ("NL", "NL"),
      ("Jp", "JP"),
      ("uS", "US"),
    ])
  func twoLettersAccepted(input: String, expected: String) {
    #expect(TripDraft.normaliseCountryCode(input) == .set(expected))
  }

  @Test(
    "Non-two-letter input is .invalid",
    arguments: [
      "N",
      "NLD",
      "12",
      "N1",
      "1N",
      "N L",
      "🇳🇱",
    ])
  func nonAlphaIsInvalid(input: String) {
    #expect(TripDraft.normaliseCountryCode(input) == .invalid)
  }
}
