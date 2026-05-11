import Foundation
import SwiftUI
import Testing

@testable import Scramble

@Suite("Theme")
struct ThemeTests {

  // MARK: - variant(for:)

  @Test("variant(for: .dark) returns the dark variant")
  func variantDark() {
    let theme = Theme.midnightAtlas
    #expect(theme.variant(for: .dark) == theme.dark)
  }

  @Test("variant(for: .light) returns the light variant")
  func variantLight() {
    let theme = Theme.midnightAtlas
    #expect(theme.variant(for: .light) == theme.light)
  }

  // MARK: - phaseColours length

  @Test("dark variant exposes 7 phase colours")
  func darkPhaseColoursCount() {
    #expect(Theme.midnightAtlas.dark.phaseColours.count == Phase.allCases.count)
  }

  @Test("light variant exposes 7 phase colours")
  func lightPhaseColoursCount() {
    #expect(Theme.midnightAtlas.light.phaseColours.count == Phase.allCases.count)
  }

  // MARK: - personColor(key:in:)

  @Test(
    "personColor resolves every Midnight Atlas palette key (dark)",
    arguments: MidnightAtlas.paletteKeys
  )
  func personColorDark(key: String) {
    let theme = Theme.midnightAtlas
    let color = theme.personColor(key: key, in: .dark)
    let expected = theme.personPalette.entry(forKey: key)?.dark
    #expect(color != nil)
    #expect(color == expected)
  }

  @Test(
    "personColor resolves every Midnight Atlas palette key (light)",
    arguments: MidnightAtlas.paletteKeys
  )
  func personColorLight(key: String) {
    let theme = Theme.midnightAtlas
    let color = theme.personColor(key: key, in: .light)
    let expected = theme.personPalette.entry(forKey: key)?.light
    #expect(color != nil)
    #expect(color == expected)
  }

  @Test("personColor returns nil for an unknown key")
  func personColorUnknownKey() {
    let theme = Theme.midnightAtlas
    #expect(theme.personColor(key: "Mauve", in: .dark) == nil)
    #expect(theme.personColor(key: "", in: .light) == nil)
  }

  // MARK: - PersonPalette.entry(forKey:)

  @Test("entry(forKey:) hits every canonical key")
  func paletteEntryHits() {
    let palette = Theme.midnightAtlas.personPalette
    for key in MidnightAtlas.paletteKeys {
      #expect(palette.entry(forKey: key)?.key == key)
    }
  }

  @Test("entry(forKey:) misses on unknown key")
  func paletteEntryMisses() {
    let palette = Theme.midnightAtlas.personPalette
    #expect(palette.entry(forKey: "Mauve") == nil)
    #expect(palette.entry(forKey: "") == nil)
    #expect(palette.entry(forKey: "cyan") == nil)  // case-sensitive
  }

  @Test("PersonPalette exposes 8 entries in canonical order")
  func paletteEightEntries() {
    let palette = Theme.midnightAtlas.personPalette
    #expect(palette.entries.count == 8)
    #expect(palette.entries.map(\.key) == MidnightAtlas.paletteKeys)
  }

  // MARK: - nextUnusedKey

  @Test("nextUnusedKey on empty taken set returns the first canonical entry")
  func nextUnusedEmpty() {
    let palette = Theme.midnightAtlas.personPalette
    let entry = palette.nextUnusedKey(among: [])
    #expect(entry.key == MidnightAtlas.paletteKeys.first)
  }

  @Test("nextUnusedKey skips taken keys and returns first unused in canonical order")
  func nextUnusedPartial() {
    let palette = Theme.midnightAtlas.personPalette
    let taken: Set<String> = ["Cyan", "Pink"]
    let entry = palette.nextUnusedKey(among: taken)
    #expect(entry.key == "Yellow")
  }

  @Test("nextUnusedKey skips contiguous gap and finds first unused")
  func nextUnusedSparse() {
    let palette = Theme.midnightAtlas.personPalette
    let taken: Set<String> = ["Cyan", "Pink", "Yellow", "Green"]
    let entry = palette.nextUnusedKey(among: taken)
    #expect(entry.key == "Purple")
  }

  @Test("nextUnusedKey with all 8 taken returns the first canonical entry")
  func nextUnusedFull() {
    let palette = Theme.midnightAtlas.personPalette
    let taken = Set(MidnightAtlas.paletteKeys)
    let entry = palette.nextUnusedKey(among: taken)
    #expect(entry.key == MidnightAtlas.paletteKeys.first)
  }

  @Test("nextUnusedKey ignores unknown keys in the taken set")
  func nextUnusedIgnoresUnknown() {
    let palette = Theme.midnightAtlas.personPalette
    let taken: Set<String> = ["Mauve", "Beige", "Cyan"]
    let entry = palette.nextUnusedKey(among: taken)
    #expect(entry.key == "Pink")
  }
}
