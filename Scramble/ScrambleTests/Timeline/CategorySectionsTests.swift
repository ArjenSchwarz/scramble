import Foundation
import Testing

@testable import Scramble

/// `PackingListHelpers.categorySections(_:category:sortWithin:)` is the generic
/// grouping helper shared by the Packing Sheet and Master Lists. It partitions
/// items by `PackingCategory.normalizedKey`, orders sections via
/// `PackingCategory.keyOrder` (uncategorised/nil last), sorts within each group
/// with the supplied comparator, and resolves each section's label via
/// `PackingCategory.displayLabel`. These tests pin the partition invariant, the
/// flat-when-none signal (single `key == nil` section), within-section order,
/// and label determinism — independent of input order.
@Suite("PackingListHelpers.categorySections")
@MainActor
struct CategorySectionsTests {

  /// Minimal generic payload — only a name (for ordering) and a raw category.
  private struct Item: Hashable {
    let name: String
    let category: String?
  }

  /// Deterministic, seedable PRNG so the order-independence property reproduces.
  private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { self.state = seed == 0 ? 0xDEAD_BEEF_CAFE_BABE : seed }
    mutating func next() -> UInt64 {
      // SplitMix64
      state &+= 0x9E37_79B9_7F4A_7C15
      var z = state
      z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
      z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
      return z ^ (z >> 31)
    }
  }

  /// Groups via `categorySections` with a case-insensitive ascending-name
  /// comparator as `sortWithin`, so within-section order is unambiguous.
  private static func sections(_ items: [Item]) -> [CategorySection<Item>] {
    PackingListHelpers.categorySections(
      items,
      category: \.category,
      sortWithin: {
        $0.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
      }
    )
  }

  /// Distinct normalized keys present in `items`, uncategorised represented as `nil`.
  private static func distinctKeys(_ items: [Item]) -> Set<String?> {
    Set(items.map { PackingCategory.normalizedKey($0.category) })
  }

  // MARK: - Partition invariant

  @Test("Every item appears in exactly one section; one section per distinct normalized key")
  func partition() {
    let items = [
      Item(name: "Shirt", category: "Clothes"),
      Item(name: "Jacket", category: "clothes"),  // same key as "Clothes"
      Item(name: "Soap", category: "Toiletries"),
      Item(name: "Passport", category: nil),  // uncategorised
      Item(name: "Wallet", category: "  "),  // blank → uncategorised
    ]
    let result = Self.sections(items)

    // distinct keys: "clothes", "toiletries", nil → 3 sections.
    #expect(result.count == Self.distinctKeys(items).count)
    #expect(result.count == 3)

    let flattened = result.flatMap(\.items)
    #expect(flattened.count == items.count)  // no duplication, no loss
    #expect(Set(flattened) == Set(items))
  }

  @Test("Empty input yields no sections")
  func emptyInput() {
    #expect(Self.sections([]).isEmpty)
  }

  // MARK: - Uncategorised sorts last

  @Test("Uncategorised (nil) section sorts last with nil key and nil label")
  func uncategorisedLast() {
    let items = [
      Item(name: "Passport", category: nil),
      Item(name: "Soap", category: "Toiletries"),
      Item(name: "Shirt", category: "Clothes"),
    ]
    let result = Self.sections(items)
    #expect(result.map(\.key) == ["clothes", "toiletries", nil])
    #expect(result.last?.key == nil)
    #expect(result.last?.label == nil)
  }

  // MARK: - Within-section order

  @Test("Within a section, order follows the supplied comparator")
  func withinSectionOrder() {
    let items = [
      Item(name: "Trousers", category: "Clothes"),
      Item(name: "Belt", category: "Clothes"),
      Item(name: "shirt", category: "Clothes"),
    ]
    let result = Self.sections(items)
    #expect(result.count == 1)
    #expect(result[0].items.map(\.name) == ["Belt", "shirt", "Trousers"])
  }

  // MARK: - Flat-when-none signal

  @Test("All-uncategorised input yields exactly one section with key == nil (the flat signal)")
  func singleUncategorised() {
    let items = [
      Item(name: "Passport", category: nil),
      Item(name: "Wallet", category: "   "),  // blank → uncategorised
      Item(name: "Keys", category: ""),  // empty → uncategorised
    ]
    let result = Self.sections(items)
    #expect(result.count == 1)
    #expect(result[0].key == nil)
    #expect(result[0].label == nil)
    #expect(result[0].items.count == 3)
  }

  // MARK: - Deterministic label

  @Test("Section label is the displayLabel (rawOrder-first) of the variants sharing a key")
  func deterministicLabel() {
    let items = [
      Item(name: "A", category: "clothes"),
      Item(name: "B", category: "Clothes"),
      Item(name: "C", category: "CLOTHES"),
    ]
    let result = Self.sections(items)
    #expect(result.count == 1)
    #expect(result[0].key == "clothes")
    // rawOrder is Unicode-scalar order: uppercase precedes lowercase, so the
    // all-caps "CLOTHES" sorts first among the variants.
    #expect(result[0].label == "CLOTHES")
  }

  @Test("Label uses the trimmed/collapsed spelling, not the raw whitespace form")
  func labelUsesTrimmedSpelling() {
    let items = [
      Item(name: "A", category: "  Clothes  "),  // storageValue → "Clothes"
      Item(name: "B", category: "clothes"),
    ]
    let result = Self.sections(items)
    #expect(result.count == 1)
    // Without trimming, the leading-space form would sort first (space < letters);
    // applying storageValue first makes "Clothes" the rawOrder-first variant.
    #expect(result[0].label == "Clothes")
  }

  // MARK: - Property: order-independence

  @Test("Section structure and partition are stable regardless of input order")
  func orderIndependent() {
    let items = [
      Item(name: "Shirt", category: "Clothes"),
      Item(name: "Jacket", category: "clothes"),
      Item(name: "Soap", category: "Toiletries"),
      Item(name: "Brush", category: "toiletries"),
      Item(name: "Passport", category: nil),
      Item(name: "Plasters", category: "First Aid"),
      Item(name: "Wallet", category: "   "),  // uncategorised
    ]
    let reference = Self.sections(items)

    // Reference structure: 4 distinct keys (first aid, clothes, toiletries, nil).
    #expect(reference.count == Self.distinctKeys(items).count)
    #expect(reference.map(\.key) == ["clothes", "first aid", "toiletries", nil])

    var rng = SeededGenerator(seed: 0xABC_DEF)
    for _ in 0..<30 {
      let shuffled = items.shuffled(using: &rng)
      let result = Self.sections(shuffled)

      // Same ordered keys and labels regardless of input order.
      #expect(result.map(\.key) == reference.map(\.key))
      #expect(result.map(\.label) == reference.map(\.label))

      // Partition holds: identical multiset of items across all sections.
      #expect(Set(result.flatMap(\.items)) == Set(items))

      // Within-section order is fixed by the comparator, not input order.
      for (lhs, rhs) in zip(result, reference) {
        #expect(lhs.items.map(\.name) == rhs.items.map(\.name))
      }
    }
  }
}
