import Foundation

/// Pure, value-level validation / mutation helpers for a packing item's
/// free-form note and appendable sub-item list (design § "Components and
/// Interfaces → PackingSubItems"). Deliberately free of any view or
/// `ModelContext` dependency so the rules are unit-testable in isolation and
/// reused identically by the inline quick-add (`PackingItemGroup`) and the
/// note field (`PackingItemForm`).
///
/// Caps:
///   - `maxItemLength` (200) — one sub-item entry (Req 2.4), matching the
///     existing `PackingItemForm.nameLimit` item-name cap.
///   - `maxNoteLength` (500) — the note (Req 4.4).
///   - `maxCount` (50) — sub-items per item (Req 2.7 / Decision 8), enforced
///     inline at the point of entry so the over-limit case is never deferred
///     to a sync-time blob-size failure (Decision 9).
///
/// All length caps count grapheme clusters via `String.prefix`, so
/// multi-scalar emoji (ZWJ families, flags, skin-tone) survive intact at the
/// boundary — the same convention as `PackingItemForm.cappedName`.
nonisolated enum PackingSubItems {
  static let maxCount = 50  // Req 2.7 / Decision 8
  static let maxItemLength = 200  // Req 2.4 (grapheme clusters)
  static let maxNoteLength = 500  // Req 4.4 (grapheme clusters)

  /// The outcome of attempting to append a sub-item. The `.added` payload is
  /// the new list (existing entries unchanged, the sanitized entry appended);
  /// the rejection cases carry no payload — the caller leaves the list as-is
  /// and performs no write (Decision 9).
  enum AddOutcome: Equatable {
    case added([String])
    case rejectedEmpty
    case rejectedFull
  }

  /// Trims surrounding whitespace / newlines and caps to `maxItemLength`
  /// grapheme clusters. Returns an empty string for blank input.
  static func sanitizedEntry(_ raw: String) -> String {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    return String(trimmed.prefix(maxItemLength))
  }

  /// Live length cap for the inline add field: caps to `maxItemLength`
  /// grapheme clusters *without* trimming, so the user can still type interior
  /// or trailing spaces while composing an entry. Mirrors
  /// `PackingItemForm.cappedName` (prefix-only). The trimming happens later in
  /// `appending`/`sanitizedEntry` at submit time.
  static func cappedEntry(_ raw: String) -> String {
    String(raw.prefix(maxItemLength))
  }

  /// Live length cap for the inline note field: caps to `maxNoteLength`
  /// grapheme clusters without trimming, so interior / trailing spaces survive
  /// while composing. Trimming + nil-on-empty happens in `sanitizedNote` at
  /// save time.
  static func cappedNote(_ raw: String) -> String {
    String(raw.prefix(maxNoteLength))
  }

  /// Appends a sanitized entry to `list`. Returns `.rejectedEmpty` if the
  /// input is blank, `.rejectedFull` if `list` already holds `maxCount`
  /// entries, otherwise `.added` with the entry appended. Empty is checked
  /// before full so blank input at the cap reports `.rejectedEmpty`.
  /// Duplicates are preserved — no de-dup (Req 2.6).
  static func appending(_ raw: String, to list: [String]) -> AddOutcome {
    let entry = sanitizedEntry(raw)
    guard !entry.isEmpty else { return .rejectedEmpty }
    guard list.count < maxCount else { return .rejectedFull }
    return .added(list + [entry])
  }

  /// Removes the entry at `index`, preserving the order of the rest. Removal
  /// is by position, not value, because duplicates are allowed (Req 2.6). An
  /// out-of-range index is a no-op (returns `list` unchanged).
  static func removing(at index: Int, from list: [String]) -> [String] {
    guard list.indices.contains(index) else { return list }
    var copy = list
    copy.remove(at: index)
    return copy
  }

  /// Trims surrounding whitespace / newlines and caps to `maxNoteLength`
  /// grapheme clusters. Returns `nil` for blank input so a cleared note
  /// stores no value (Req 4.3).
  static func sanitizedNote(_ raw: String) -> String? {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    return String(trimmed.prefix(maxNoteLength))
  }
}
