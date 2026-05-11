import SwiftUI

nonisolated struct PaletteEntry: Equatable, Identifiable, Sendable {
  var id: String { key }
  let key: String
  let displayName: String
  let dark: Color
  let light: Color
}

nonisolated struct PersonPalette: Equatable, Sendable {
  let entries: [PaletteEntry]

  func entry(forKey key: String) -> PaletteEntry? {
    entries.first { $0.key == key }
  }

  /// Returns the first canonical entry whose key is not in `taken`.
  /// When every entry is taken, returns the first canonical entry — callers
  /// surface the duplicate-color advisory from AC 9.4 in that case.
  func nextUnusedKey(among taken: Set<String>) -> PaletteEntry {
    if let unused = entries.first(where: { !taken.contains($0.key) }) {
      return unused
    }
    return entries[0]
  }
}
