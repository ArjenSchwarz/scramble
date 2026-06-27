import Foundation

/// Pure value logic for packing-item categories: normalization, the grouping key,
/// and the locale-independent ordering shared by the Packing Sheet and Master Lists.
///
/// No SwiftData, no persistence. The *stored* form keeps the user's spelling
/// (trimmed, internal whitespace collapsed, case preserved); the *normalized key*
/// additionally case-folds and decides whether two categories are the same for
/// grouping, suggestions, and sort. Ordering is by Unicode-scalar lexicographic
/// order — a fixed, locale-independent total order — so a shared trip renders the
/// same section order on every device regardless of locale.
nonisolated enum PackingCategory {

  /// The stored form: leading/trailing whitespace trimmed and internal runs of
  /// whitespace collapsed to a single space, case preserved. Returns `nil` for
  /// `nil`, empty, or whitespace-only input. (Req 1.2/1.3)
  static func storageValue(_ raw: String?) -> String? {
    guard let raw else { return nil }
    let collapsed = raw.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    return collapsed.isEmpty ? nil : collapsed
  }

  /// The grouping / suggestion-match key: the case-folded `storageValue` using
  /// non-localized `lowercased()` (NOT `localizedLowercase`, which is locale-sensitive
  /// — e.g. Turkish dotless-i — and would break cross-device determinism). `nil` ⇒
  /// uncategorised. Diacritics are not folded ("Café" ≠ "Cafe"). (Req 1.5)
  static func normalizedKey(_ raw: String?) -> String? {
    storageValue(raw)?.lowercased()
  }

  /// Orders two normalized keys by Unicode-scalar lexicographic order, with `nil`
  /// (uncategorised) sorting last. Suitable as a `<`-style comparator for `sorted(by:)`.
  /// (Req 5.2)
  static func keyOrder(_ lhs: String?, _ rhs: String?) -> Bool {
    switch (lhs, rhs) {
    case (nil, _): false
    case (_, nil): true
    case (let l?, let r?): scalarOrder(l, r)
    }
  }

  /// Total order over RAW (non-case-folded) `storageValue`s by Unicode-scalar order.
  /// The disambiguator behind `displayLabel`. (Req 5.6)
  static func rawOrder(_ lhs: String, _ rhs: String) -> Bool {
    scalarOrder(lhs, rhs)
  }

  /// Among `storageValue`s sharing a normalized key, the deterministic display label:
  /// the variant that sorts first under `rawOrder`. Uses `rawOrder`, NOT `keyOrder` —
  /// `keyOrder` case-folds, so all spelling variants tie under it and it cannot pick a
  /// spelling. The same rule selects the stored spelling for a deduped suggestion.
  /// (Req 5.6, Req 2.4)
  static func displayLabel(_ variants: [String]) -> String {
    variants.min(by: rawOrder) ?? ""
  }

  /// Strict Unicode-scalar lexicographic order (compares scalar code points). A fixed,
  /// locale-independent total order over distinct scalar sequences.
  private static func scalarOrder(_ lhs: String, _ rhs: String) -> Bool {
    lhs.unicodeScalars.lexicographicallyPrecedes(rhs.unicodeScalars) { $0.value < $1.value }
  }
}
