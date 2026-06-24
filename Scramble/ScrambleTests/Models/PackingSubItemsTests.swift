import Foundation
import Testing

@testable import Scramble

/// Unit + property-based coverage for the pure `PackingSubItems` validation /
/// mutation helpers (design § "Components and Interfaces → PackingSubItems").
/// No view, `@Model`, or `ModelContext` dependency — these are value-level
/// helpers, so the suite is plain (not `@MainActor`).
///
/// Caps under test: `maxItemLength = 200` (Req 2.4), `maxNoteLength = 500`
/// (Req 4.4), `maxCount = 50` (Req 2.7 / Decision 8). All length caps count
/// grapheme clusters via `String.prefix`, so multi-scalar emoji survive
/// intact at the boundary (matches `PackingItemForm.cappedName`).
@Suite("PackingSubItems")
struct PackingSubItemsTests {

  // MARK: - sanitizedEntry

  @Test("sanitizedEntry trims leading / trailing whitespace and newlines")
  func sanitizedEntryTrims() {
    #expect(PackingSubItems.sanitizedEntry("  socks  ") == "socks")
    #expect(PackingSubItems.sanitizedEntry("\n\ttoys\n") == "toys")
    #expect(PackingSubItems.sanitizedEntry("books") == "books")
  }

  @Test("sanitizedEntry returns empty for whitespace-only input")
  func sanitizedEntryWhitespaceOnly() {
    #expect(PackingSubItems.sanitizedEntry("   ").isEmpty)
    #expect(PackingSubItems.sanitizedEntry("\n\t ").isEmpty)
    #expect(PackingSubItems.sanitizedEntry("").isEmpty)
  }

  @Test("sanitizedEntry caps at 200 grapheme clusters")
  func sanitizedEntryCaps() {
    let over = String(repeating: "a", count: PackingSubItems.maxItemLength + 50)
    let capped = PackingSubItems.sanitizedEntry(over)
    #expect(capped.count == PackingSubItems.maxItemLength)
  }

  @Test("sanitizedEntry leaves under-cap input at its own length")
  func sanitizedEntryUnderCap() {
    let entry = String(repeating: "x", count: 10)
    #expect(PackingSubItems.sanitizedEntry(entry).count == 10)
  }

  /// Multi-scalar emoji (ZWJ family, flag, skin-tone) must never be split at
  /// the grapheme boundary. `String.prefix` counts grapheme clusters, so a
  /// string of N identical emoji caps to exactly `maxItemLength` clusters with
  /// every cluster intact.
  @Test(
    "sanitizedEntry keeps multi-scalar emoji intact at the cap boundary",
    arguments: ["👨‍👩‍👧‍👦", "🇳🇱", "👍🏽", "🏳️‍🌈"]
  )
  func sanitizedEntryEmojiBoundary(emoji: String) {
    // One extra cluster beyond the cap, all identical emoji.
    let over = String(repeating: emoji, count: PackingSubItems.maxItemLength + 1)
    let capped = PackingSubItems.sanitizedEntry(over)
    #expect(capped.count == PackingSubItems.maxItemLength)
    // Every retained cluster is the whole emoji — none was split mid-scalar.
    #expect(capped.allSatisfy { String($0) == emoji })
  }

  // MARK: - appending

  @Test("appending rejects empty / whitespace-only input")
  func appendingRejectsEmpty() {
    #expect(PackingSubItems.appending("", to: []) == .rejectedEmpty)
    #expect(PackingSubItems.appending("   ", to: ["a"]) == .rejectedEmpty)
    #expect(PackingSubItems.appending("\n\t", to: ["a", "b"]) == .rejectedEmpty)
  }

  @Test("appending adds a sanitized entry to the end")
  func appendingAdds() {
    #expect(PackingSubItems.appending("  socks ", to: []) == .added(["socks"]))
    #expect(
      PackingSubItems.appending("books", to: ["socks"]) == .added(["socks", "books"])
    )
  }

  @Test("appending preserves existing order and the new entry goes last")
  func appendingPreservesOrder() {
    let list = ["a", "b", "c"]
    #expect(PackingSubItems.appending("d", to: list) == .added(["a", "b", "c", "d"]))
  }

  @Test("appending keeps duplicates — no silent de-dup (Req 2.6)")
  func appendingKeepsDuplicates() {
    #expect(PackingSubItems.appending("socks", to: ["socks"]) == .added(["socks", "socks"]))
    let list = ["x", "x"]
    #expect(PackingSubItems.appending("x", to: list) == .added(["x", "x", "x"]))
  }

  @Test("appending caps the new entry at 200 graphemes before adding")
  func appendingCapsEntry() {
    let over = String(repeating: "z", count: PackingSubItems.maxItemLength + 5)
    guard case .added(let list) = PackingSubItems.appending(over, to: []) else {
      Issue.record("expected .added")
      return
    }
    #expect(list.count == 1)
    #expect(list[0].count == PackingSubItems.maxItemLength)
  }

  @Test("appending rejects when the list already holds 50 entries (Req 2.7)")
  func appendingRejectsFull() {
    let full = (0..<PackingSubItems.maxCount).map { "item-\($0)" }
    #expect(full.count == PackingSubItems.maxCount)
    #expect(PackingSubItems.appending("one-more", to: full) == .rejectedFull)
  }

  @Test("appending succeeds at exactly one below the cap (49 → 50)")
  func appendingSucceedsAtBoundary() {
    let almost = (0..<(PackingSubItems.maxCount - 1)).map { "item-\($0)" }
    guard case .added(let list) = PackingSubItems.appending("last", to: almost) else {
      Issue.record("expected .added")
      return
    }
    #expect(list.count == PackingSubItems.maxCount)
  }

  @Test("appending checks empty before full — blank input at the cap is rejectedEmpty")
  func appendingEmptyBeatsFull() {
    let full = (0..<PackingSubItems.maxCount).map { "item-\($0)" }
    #expect(PackingSubItems.appending("   ", to: full) == .rejectedEmpty)
  }

  // MARK: - removing

  @Test("removing deletes only the indexed entry and keeps order")
  func removingDeletesIndex() {
    #expect(PackingSubItems.removing(at: 1, from: ["a", "b", "c"]) == ["a", "c"])
    #expect(PackingSubItems.removing(at: 0, from: ["a", "b", "c"]) == ["b", "c"])
    #expect(PackingSubItems.removing(at: 2, from: ["a", "b", "c"]) == ["a", "b"])
  }

  @Test("removing targets the position, not the value, when duplicates exist")
  func removingTargetsPosition() {
    // Remove the middle "x"; the other two stay.
    #expect(PackingSubItems.removing(at: 1, from: ["x", "x", "x"]) == ["x", "x"])
  }

  @Test(
    "removing is a no-op for an out-of-range index",
    arguments: [-1, 3, 99, Int.max]
  )
  func removingOutOfRangeNoOp(index: Int) {
    let list = ["a", "b", "c"]
    #expect(PackingSubItems.removing(at: index, from: list) == list)
  }

  @Test("removing from an empty list is a no-op")
  func removingFromEmpty() {
    #expect(PackingSubItems.removing(at: 0, from: []).isEmpty)
  }

  // MARK: - sanitizedNote

  @Test("sanitizedNote trims and returns the trimmed text")
  func sanitizedNoteTrims() {
    #expect(PackingSubItems.sanitizedNote("  keep batteries out  ") == "keep batteries out")
  }

  @Test("sanitizedNote returns nil for empty / whitespace-only input (Req 4.3)")
  func sanitizedNoteNilOnEmpty() {
    #expect(PackingSubItems.sanitizedNote("") == nil)
    #expect(PackingSubItems.sanitizedNote("   ") == nil)
    #expect(PackingSubItems.sanitizedNote("\n\t ") == nil)
  }

  @Test("sanitizedNote caps at 500 grapheme clusters")
  func sanitizedNoteCaps() {
    let over = String(repeating: "n", count: PackingSubItems.maxNoteLength + 100)
    let capped = PackingSubItems.sanitizedNote(over)
    #expect(capped?.count == PackingSubItems.maxNoteLength)
  }

  @Test("sanitizedNote keeps multi-scalar emoji intact at the cap boundary")
  func sanitizedNoteEmojiBoundary() {
    let emoji = "👨‍👩‍👧‍👦"
    let over = String(repeating: emoji, count: PackingSubItems.maxNoteLength + 1)
    let capped = PackingSubItems.sanitizedNote(over)
    #expect(capped?.count == PackingSubItems.maxNoteLength)
    #expect(capped?.allSatisfy { String($0) == emoji } == true)
  }

  @Test("cappedNote caps at 500 graphemes without trimming")
  func cappedNoteCaps() {
    let over = String(repeating: "n", count: PackingSubItems.maxNoteLength + 100)
    #expect(PackingSubItems.cappedNote(over).count == PackingSubItems.maxNoteLength)
  }

  @Test("cappedNote preserves interior/trailing whitespace while composing")
  func cappedNotePreservesWhitespace() {
    // Unlike sanitizedNote, the live cap must not trim — the user may still be
    // typing spaces between words.
    let composing = "two words "
    #expect(PackingSubItems.cappedNote(composing) == composing)
  }

  // MARK: - Property-based: encode/decode round-trip

  /// The `subItems` model bridge serialises `[String]` through `CodableBridge`
  /// (design § "Data Models"). The round-trip is a universal serializer
  /// guarantee: `decode(encode(xs)) == xs` for any `[String]`, including
  /// duplicates, empty entries, unicode, and boundary-length entries within
  /// the caps. This locks the bridge encoding stream 2 / stream 1 must share.
  @Test(
    "PBT — decode(encode(xs)) == xs over generated [String]",
    arguments: PackingSubItemsTests.generatedLists()
  )
  func roundTripIdentity(list: [String]) {
    let data = CodableBridge.encode(list, label: "PackingSubItemsTests.roundTrip")
    let decoded = CodableBridge.decode(
      data, as: [String].self, default: [], label: "PackingSubItemsTests.roundTrip"
    )
    #expect(decoded == list)
  }

  // MARK: - Property-based: add / remove length invariants

  /// Over a generated sequence of add / remove operations applied to a
  /// generated starting list, the structural invariants hold:
  ///   - count never exceeds `maxCount` (Req 2.7),
  ///   - a successful `.added` increases length by exactly 1,
  ///   - a non-empty `removing` decreases length by exactly 1 (and is a no-op
  ///     when the index is out of range).
  @Test(
    "PBT — add / remove preserve the length invariants",
    arguments: PackingSubItemsTests.operationSequences()
  )
  func addRemoveInvariants(sequence: OperationSequence) {
    var list = sequence.start
    for op in sequence.ops {
      switch op {
      case .add(let raw):
        let before = list.count
        switch PackingSubItems.appending(raw, to: list) {
        case .added(let next):
          #expect(next.count == before + 1)
          list = next
        case .rejectedEmpty:
          #expect(PackingSubItems.sanitizedEntry(raw).isEmpty)
        case .rejectedFull:
          #expect(before >= PackingSubItems.maxCount)
        }
      case .remove(let index):
        let before = list.count
        let next = PackingSubItems.removing(at: index, from: list)
        if index >= 0 && index < before {
          #expect(next.count == before - 1)
        } else {
          #expect(next == list)
        }
        list = next
      }
      // The cap is never breached, whatever the operation.
      #expect(list.count <= PackingSubItems.maxCount)
    }
  }

  // MARK: - Generators

  /// A spread of `[String]` covering the round-trip edge cases the design
  /// calls out: duplicates, empty strings, unicode / multi-scalar emoji, and
  /// boundary-length entries within the caps.
  static func generatedLists() -> [[String]] {
    let boundary = String(repeating: "a", count: PackingSubItems.maxItemLength)
    let emoji = "👨‍👩‍👧‍👦"
    return [
      [],
      [""],
      ["socks"],
      ["socks", "socks"],
      ["", "", ""],
      ["a", "b", "a", "b"],
      ["café", "naïve", "Zürich"],
      [emoji, "🇳🇱", "👍🏽"],
      [boundary],
      [boundary, "x", boundary],
      ["line1\nline2", "tab\tsep"],
      (0..<PackingSubItems.maxCount).map { "item-\($0)" },
    ]
  }

  enum Operation: Sendable {
    case add(String)
    case remove(Int)
  }

  struct OperationSequence: Sendable, CustomStringConvertible {
    let start: [String]
    let ops: [Operation]
    let label: String

    var description: String { label }
  }

  /// Generated add / remove sequences exercised against several starting
  /// lists, including a list already at the cap so `rejectedFull` is hit.
  static func operationSequences() -> [OperationSequence] {
    let full = (0..<PackingSubItems.maxCount).map { "f-\($0)" }
    let nearFull = (0..<(PackingSubItems.maxCount - 1)).map { "n-\($0)" }
    return [
      OperationSequence(
        start: [],
        ops: [.add("a"), .add("b"), .add("  "), .remove(0), .remove(5)],
        label: "empty-start mixed"
      ),
      OperationSequence(
        start: ["x", "y", "z"],
        ops: [.remove(1), .add("dup"), .add("dup"), .remove(-1), .remove(99)],
        label: "dups + OOR removes"
      ),
      OperationSequence(
        start: full,
        ops: [.add("overflow"), .add("still-full"), .remove(0), .add("now-fits")],
        label: "at-cap rejects then fits after remove"
      ),
      OperationSequence(
        start: nearFull,
        ops: [.add("fills-to-cap"), .add("overflow"), .remove(10)],
        label: "near-cap fills then rejects"
      ),
      OperationSequence(
        start: ["only"],
        ops: [.remove(0), .remove(0), .add("again")],
        label: "drain to empty then add"
      ),
    ]
  }
}
