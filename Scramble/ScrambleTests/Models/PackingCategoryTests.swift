import Foundation
import Testing

@testable import Scramble

@Suite("PackingCategory")
struct PackingCategoryTests {

  // MARK: - Representative inputs (property-based parameterization)

  /// A spread of representative category strings: case variants, whitespace
  /// variants, diacritics, empties, and embedded tabs/newlines.
  static let sampleStrings: [String] = [
    "Clothes", "clothes", " clothes ", "Clothes ", "  CLOTHES  ",
    "Toiletries", "toiletries", "First Aid", "first  aid", "  first\taid  ",
    "Café", "Cafe", "café", "Électronique", "electronique",
    "A", "a", "Z", "z", "MixedCase Word", "  multi   space   word  ",
    "", "   ", "\t\n", "Tech Gadgets", "tech gadgets",
    "Über", "über", "naïve", "Naive", "first\n\naid",
  ]

  /// Distinct normalized keys derived from `sampleStrings`, with `nil` (uncategorised)
  /// included. Used to exercise `keyOrder` as a total order.
  static let distinctKeys: [String?] = {
    var seen = Set<String>()
    var result: [String?] = [nil]
    for raw in sampleStrings {
      if let key = PackingCategory.normalizedKey(raw), seen.insert(key).inserted {
        result.append(key)
      }
    }
    return result
  }()

  // MARK: - storageValue

  @Test("storageValue returns nil for nil input")
  func storageValueNilInput() {
    #expect(PackingCategory.storageValue(nil) == nil)
  }

  @Test("storageValue returns nil for empty input")
  func storageValueEmpty() {
    #expect(PackingCategory.storageValue("") == nil)
  }

  @Test("storageValue returns nil for whitespace-only input")
  func storageValueWhitespaceOnly() {
    #expect(PackingCategory.storageValue("   ") == nil)
    #expect(PackingCategory.storageValue("\t\n  ") == nil)
  }

  @Test("storageValue trims leading and trailing whitespace")
  func storageValueTrims() {
    #expect(PackingCategory.storageValue("  Clothes  ") == "Clothes")
  }

  @Test("storageValue collapses internal runs of whitespace to a single space")
  func storageValueCollapsesInternal() {
    #expect(PackingCategory.storageValue("First    Aid") == "First Aid")
  }

  @Test("storageValue collapses tabs and newlines to a single space")
  func storageValueCollapsesTabsNewlines() {
    #expect(PackingCategory.storageValue("a\t\nb") == "a b")
    #expect(PackingCategory.storageValue("first\n\naid") == "first aid")
  }

  @Test("storageValue preserves case")
  func storageValuePreservesCase() {
    #expect(PackingCategory.storageValue("CamelCase WORD") == "CamelCase WORD")
  }

  @Test("storageValue trims and collapses together")
  func storageValueTrimAndCollapse() {
    #expect(PackingCategory.storageValue("  First   Aid  Kit ") == "First Aid Kit")
  }

  @Test("storageValue preserves diacritics")
  func storageValuePreservesDiacritics() {
    #expect(PackingCategory.storageValue("  Café ") == "Café")
  }

  // MARK: - normalizedKey

  @Test("normalizedKey case-folds via non-localized lowercased")
  func normalizedKeyLowercases() {
    #expect(PackingCategory.normalizedKey("CLOTHES") == "clothes")
    #expect(PackingCategory.normalizedKey("MixedCase WORD") == "mixedcase word")
  }

  @Test("normalizedKey trims, collapses, then lowercases")
  func normalizedKeyTrimCollapseLower() {
    #expect(PackingCategory.normalizedKey("  First   AID ") == "first aid")
  }

  @Test("normalizedKey returns nil for nil, empty, and whitespace-only input")
  func normalizedKeyNil() {
    #expect(PackingCategory.normalizedKey(nil) == nil)
    #expect(PackingCategory.normalizedKey("") == nil)
    #expect(PackingCategory.normalizedKey("  \t ") == nil)
  }

  @Test("normalizedKey does not fold diacritics")
  func normalizedKeyKeepsDiacritics() {
    #expect(PackingCategory.normalizedKey("Café") == "café")
    #expect(PackingCategory.normalizedKey("Café") != PackingCategory.normalizedKey("Cafe"))
  }

  @Test("case/whitespace variants share a normalized key")
  func normalizedKeyVariantsMatch() {
    let a = PackingCategory.normalizedKey("Clothes")
    let b = PackingCategory.normalizedKey("  clothes  ")
    let c = PackingCategory.normalizedKey("CLOTHES")
    #expect(a == b)
    #expect(b == c)
  }

  @Test(
    "normalizedKey equals lowercased storageValue",
    arguments: PackingCategoryTests.sampleStrings
  )
  func normalizedKeyMatchesLoweredStorage(_ raw: String) {
    #expect(PackingCategory.normalizedKey(raw) == PackingCategory.storageValue(raw)?.lowercased())
  }

  // MARK: - keyOrder

  @Test("keyOrder places a non-nil key before nil")
  func keyOrderNonNilBeforeNil() {
    #expect(PackingCategory.keyOrder("clothes", nil))
  }

  @Test("keyOrder never places nil before anything (nil sorts last)")
  func keyOrderNilSortsLast() {
    #expect(!PackingCategory.keyOrder(nil, "clothes"))
    #expect(!PackingCategory.keyOrder(nil, nil))
  }

  @Test("keyOrder uses Unicode-scalar order on non-nil keys")
  func keyOrderScalarOrder() {
    #expect(PackingCategory.keyOrder("clothes", "toiletries"))
    #expect(!PackingCategory.keyOrder("toiletries", "clothes"))
  }

  @Test("sorting normalized keys via keyOrder places uncategorised (nil) last")
  func keyOrderSortsNilLast() {
    let keys: [String?] = ["toiletries", nil, "clothes", "first aid"]
    let sorted = keys.sorted(by: PackingCategory.keyOrder)
    #expect(sorted == ["clothes", "first aid", "toiletries", nil])
  }

  @Test("keyOrder cannot disambiguate case variants (both case-fold equal)")
  func keyOrderTiesCaseVariants() {
    let a = PackingCategory.normalizedKey("Clothes")
    let b = PackingCategory.normalizedKey("clothes")
    #expect(a == b)
    #expect(!PackingCategory.keyOrder(a, b))
    #expect(!PackingCategory.keyOrder(b, a))
  }

  @Test("keyOrder is irreflexive", arguments: PackingCategoryTests.distinctKeys)
  func keyOrderIrreflexive(_ key: String?) {
    #expect(!PackingCategory.keyOrder(key, key))
  }

  @Test("keyOrder is asymmetric and total (trichotomy) over all distinct-key pairs")
  func keyOrderTrichotomy() {
    let keys = Self.distinctKeys
    for lhs in keys {
      for rhs in keys {
        let forward = PackingCategory.keyOrder(lhs, rhs)
        let backward = PackingCategory.keyOrder(rhs, lhs)
        if lhs == rhs {
          #expect(!forward && !backward)
        } else {
          // Exactly one direction holds for distinct keys.
          #expect(forward != backward)
        }
      }
    }
  }

  @Test("keyOrder is transitive over all distinct-key triples")
  func keyOrderTransitive() {
    let keys = Self.distinctKeys
    for a in keys {
      for b in keys where PackingCategory.keyOrder(a, b) {
        for c in keys where PackingCategory.keyOrder(b, c) {
          #expect(PackingCategory.keyOrder(a, c))
        }
      }
    }
  }

  // MARK: - rawOrder

  @Test("rawOrder uses Unicode-scalar order: uppercase before lowercase")
  func rawOrderUppercaseFirst() {
    #expect(PackingCategory.rawOrder("Apple", "apple"))
    #expect(!PackingCategory.rawOrder("apple", "Apple"))
  }

  @Test("rawOrder compares lexicographically by scalar")
  func rawOrderLexicographic() {
    #expect(PackingCategory.rawOrder("abc", "abd"))
    #expect(PackingCategory.rawOrder("abc", "abca"))  // proper prefix sorts first
    #expect(!PackingCategory.rawOrder("abc", "abc"))  // irreflexive
  }

  @Test("rawOrder distinguishes case where keyOrder would tie")
  func rawOrderDistinguishesCase() {
    // keyOrder case-folds, so "Clothes"/"clothes" tie; rawOrder separates them.
    #expect(PackingCategory.rawOrder("Clothes", "clothes"))
    #expect(!PackingCategory.rawOrder("clothes", "Clothes"))
  }

  // MARK: - displayLabel

  @Test("displayLabel picks the rawOrder-first variant (uppercase before lowercase)")
  func displayLabelPicksRawOrderFirst() {
    #expect(PackingCategory.displayLabel(["clothes", "Clothes"]) == "Clothes")
    #expect(PackingCategory.displayLabel(["clothes", "Clothes", "CLOTHES"]) == "CLOTHES")
  }

  @Test("displayLabel is independent of input order")
  func displayLabelOrderIndependent() {
    #expect(PackingCategory.displayLabel(["clothes", "Clothes"]) == "Clothes")
    #expect(PackingCategory.displayLabel(["Clothes", "clothes"]) == "Clothes")
  }

  @Test("displayLabel returns the sole variant unchanged")
  func displayLabelSingle() {
    #expect(PackingCategory.displayLabel(["First Aid"]) == "First Aid")
  }

  // MARK: - Property-based: idempotence / stability

  @Test("storageValue is idempotent", arguments: PackingCategoryTests.sampleStrings)
  func storageValueIdempotent(_ raw: String) {
    let once = PackingCategory.storageValue(raw)
    let twice = PackingCategory.storageValue(once)
    #expect(once == twice)
  }

  @Test(
    "normalizedKey is stable under re-application", arguments: PackingCategoryTests.sampleStrings)
  func normalizedKeyStable(_ raw: String) {
    let once = PackingCategory.normalizedKey(raw)
    let twice = PackingCategory.normalizedKey(once)
    #expect(once == twice)
  }
}
