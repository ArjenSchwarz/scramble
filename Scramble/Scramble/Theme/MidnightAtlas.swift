import SwiftUI

nonisolated enum MidnightAtlas {

  static let id = "midnight-atlas"
  static let displayName = "Midnight Atlas"

  /// Canonical order of person palette keys. Tests and `nextUnusedKey` both
  /// depend on this ordering.
  static let paletteKeys: [String] = [
    "Cyan", "Pink", "Yellow", "Green", "Purple", "Orange", "Red", "Teal"
  ]

  static let palette = PersonPalette(entries: [
    PaletteEntry(key: "Cyan", displayName: "Cyan", dark: .hex6(0x64D2FF), light: .hex6(0x0A84FF)),
    PaletteEntry(key: "Pink", displayName: "Pink", dark: .hex6(0xFF6EB4), light: .hex6(0xD9508E)),
    PaletteEntry(
      key: "Yellow", displayName: "Yellow", dark: .hex6(0xFFD60A), light: .hex6(0xC09000)),
    PaletteEntry(key: "Green", displayName: "Green", dark: .hex6(0x30D158), light: .hex6(0x28A745)),
    PaletteEntry(
      key: "Purple", displayName: "Purple", dark: .hex6(0xBF5AF2), light: .hex6(0x9B40D0)),
    PaletteEntry(
      key: "Orange", displayName: "Orange", dark: .hex6(0xFF9F0A), light: .hex6(0xE08600)),
    PaletteEntry(key: "Red", displayName: "Red", dark: .hex6(0xFF6961), light: .hex6(0xE04848)),
    PaletteEntry(key: "Teal", displayName: "Teal", dark: .hex6(0x00C7BE), light: .hex6(0x00A0A0))
  ])

  static let dark = ThemeVariant(
    background: Gradient(colors: [.hex6(0x0A0E1A), .hex6(0x1A1F35)]),
    accent: .hex6(0x64D2FF),
    surface: .rgba(255, 255, 255, 0.05),
    surfaceBorder: .rgba(255, 255, 255, 0.10),
    textPrimary: .hex6(0xE8ECF4),
    textSecondary: .hex6(0x7A8299),
    checkColour: .hex6(0x30D158),
    warnColour: .hex6(0xFF9F0A),
    phaseColours: [
      .hex6(0x9B7EFF),  // weeksBefore
      .hex6(0x64D2FF),  // dayBefore
      .hex6(0x30D158),  // departureDay
      .hex6(0xFFD60A),  // duringTrip
      .hex6(0xFF9F0A),  // dayBeforeReturn
      .hex6(0xFF6961),  // returnDay
      .hex6(0x7A8299)   // afterTrip
    ]
  )

  static let light = ThemeVariant(
    background: Gradient(colors: [.hex6(0xF2F6FA), .hex6(0xE4E9F2)]),
    accent: .hex6(0x0A84FF),
    surface: .rgba(255, 255, 255, 0.70),
    surfaceBorder: .rgba(60, 80, 120, 0.12),
    textPrimary: .hex6(0x1C2333),
    textSecondary: .hex6(0x6B7A8D),
    checkColour: .hex6(0x28A745),
    warnColour: .hex6(0xE08600),
    phaseColours: [
      .hex6(0x7A5AE0),  // weeksBefore  — darkened purple
      .hex6(0x0A84FF),  // dayBefore    — matches accent light
      .hex6(0x28A745),  // departureDay — matches checkColour light
      .hex6(0xC09000),  // duringTrip   — matches Yellow light
      .hex6(0xE08600),  // dayBeforeReturn — matches warnColour light
      .hex6(0xE04848),  // returnDay    — matches Red light
      .hex6(0x6B7A8D)   // afterTrip    — matches textSecondary light
    ]
  )
}

extension Theme {
  nonisolated static let midnightAtlas: Theme = Theme(
    id: MidnightAtlas.id,
    displayName: MidnightAtlas.displayName,
    dark: MidnightAtlas.dark,
    light: MidnightAtlas.light,
    personPalette: MidnightAtlas.palette
  )
}

extension Color {
  fileprivate nonisolated static func hex6(_ value: UInt32) -> Color {
    let r = Double((value >> 16) & 0xFF) / 255.0
    let g = Double((value >> 8) & 0xFF) / 255.0
    let b = Double(value & 0xFF) / 255.0
    return Color(.sRGB, red: r, green: g, blue: b, opacity: 1.0)
  }

  fileprivate nonisolated static func rgba(
    _ r: Double, _ g: Double, _ b: Double, _ a: Double
  ) -> Color {
    Color(.sRGB, red: r / 255.0, green: g / 255.0, blue: b / 255.0, opacity: a)
  }
}
