import Foundation

/// Phase 6 — ISO 3166-1 alpha-2 → flag emoji helper (Decision 5, Req 6.3).
///
/// Maps each uppercase ASCII letter to its regional-indicator scalar
/// (`A` → `U+1F1E6`, `Z` → `U+1F1FF`) and concatenates the two scalars.
/// Returns `nil` for `nil`, empty, wrong-length, or non-letter inputs.
/// Validation against the official ISO 3166-1 list is non-goal — `"XZ"`
/// renders as an empty flag rather than rejecting (Req 6.5).
nonisolated enum CountryFlag {

  static func emoji(for code: String?) -> String? {
    guard let code else { return nil }
    let normalised = code.uppercased()
    guard normalised.count == 2 else { return nil }

    let asciiUppercaseA: UInt8 = 0x41
    let regionalIndicatorA: Int = 0x1F1E6
    var scalars: [Unicode.Scalar] = []
    for character in normalised {
      guard
        character.isASCII,
        let asciiValue = character.asciiValue,
        ("A"...("Z" as Character)).contains(character),
        let scalar = Unicode.Scalar(regionalIndicatorA + Int(asciiValue - asciiUppercaseA))
      else {
        return nil
      }
      scalars.append(scalar)
    }
    return scalars.reduce(into: "") { partial, scalar in
      partial.append(String(scalar))
    }
  }
}
