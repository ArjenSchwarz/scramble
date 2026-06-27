import Foundation
import SwiftData

/// SwiftData-backed suggestion gathering for packing categories. Lives apart
/// from the pure `PackingCategory.swift` so that namespace stays free of
/// persistence; this extension is the one place that touches `ModelContext`.
extension PackingCategory {

  /// The distinct categories present on the device, drawn from BOTH containers
  /// (`MasterPackingItem` in globals + `TripPackingItem` in tripsLocal), deduped
  /// by normalized key, each key rendered with its canonical spelling
  /// (`displayLabel`) and ordered by `keyOrder`. A participant device, lacking
  /// the owner's masters, naturally yields a smaller set (Req 2.2 / 2.4 / 2.5).
  ///
  /// Reads each container's `mainContext` synchronously; intended to be called
  /// once when an editor appears (or memoized), never per keystroke, and always
  /// derives from the current item categories so a cleared category does not
  /// resurrect as a suggestion (Non-Goal: no persistent vocabulary). `@MainActor`
  /// because `ModelContext` is bound to the main context on every call site.
  @MainActor
  static func distinctCategories(globals: ModelContext, tripsLocal: ModelContext) -> [String] {
    var rawValues: [String] = []

    let masters = (try? globals.fetch(FetchDescriptor<MasterPackingItem>())) ?? []
    rawValues.append(contentsOf: masters.compactMap { storageValue($0.category) })

    let tripItems = (try? tripsLocal.fetch(FetchDescriptor<TripPackingItem>())) ?? []
    rawValues.append(contentsOf: tripItems.compactMap { storageValue($0.category) })

    // Group the spelling variants under their normalized key.
    var variantsByKey: [String: [String]] = [:]
    for value in rawValues {
      guard let key = normalizedKey(value) else { continue }
      variantsByKey[key, default: []].append(value)
    }

    // Order keys deterministically, then render each with its canonical spelling.
    return variantsByKey.keys
      .sorted { keyOrder($0, $1) }
      .compactMap { key in variantsByKey[key].map(displayLabel) }
  }
}
