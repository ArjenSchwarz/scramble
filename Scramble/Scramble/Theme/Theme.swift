import SwiftUI

nonisolated struct Theme: Equatable, Identifiable, Sendable {
  let id: String
  let displayName: String
  let dark: ThemeVariant
  let light: ThemeVariant
  let personPalette: PersonPalette

  func variant(for scheme: ColorScheme) -> ThemeVariant {
    switch scheme {
    case .light: light
    case .dark: dark
    @unknown default: dark
    }
  }

  func personColor(key: String, in scheme: ColorScheme) -> Color? {
    guard let entry = personPalette.entry(forKey: key) else { return nil }
    switch scheme {
    case .light: return entry.light
    case .dark: return entry.dark
    @unknown default: return entry.dark
    }
  }
}

nonisolated struct ThemeVariant: Equatable, Sendable {
  let background: Gradient
  let accent: Color
  let surface: Color
  let surfaceBorder: Color
  let textPrimary: Color
  let textSecondary: Color
  let checkColour: Color
  let warnColour: Color
  let phaseColours: [Color]

  /// Looks up the colour for a `Phase` by its position in `Phase.allCases`.
  /// Falls back to `textSecondary` if a theme variant supplies fewer entries
  /// than there are phases — avoids a crash if a future theme is misconfigured.
  func phaseColour(for phase: Phase) -> Color {
    guard let index = Phase.allCases.firstIndex(of: phase),
      phaseColours.indices.contains(index)
    else { return textSecondary }
    return phaseColours[index]
  }
}

struct ThemeKey: EnvironmentKey {
  nonisolated static let defaultValue: Theme = .midnightAtlas
}

extension EnvironmentValues {
  var theme: Theme {
    get { self[ThemeKey.self] }
    set { self[ThemeKey.self] = newValue }
  }
}
