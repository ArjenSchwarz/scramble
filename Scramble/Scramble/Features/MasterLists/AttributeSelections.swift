import Foundation

/// Editor-side representation of the v1 conditions shape: a per-attribute set of
/// selected chip values. Bridges to/from `ItemConditions` via `toConditions()` /
/// `from(_:)`. The chip editor cannot produce out-of-domain values; `from(_:)`
/// rejects them (returns nil) so the editor falls back to the read-only
/// "Advanced condition" placeholder per AC 3.7.
nonisolated struct AttributeSelections: Equatable, Sendable {
  var byAttribute: [TripAttribute: Set<String>]

  static let empty = AttributeSelections(byAttribute: [:])

  /// Encode the current selections as the v1 `ItemConditions` shape:
  /// - all attributes empty → `.always`
  /// - otherwise → `.all([.match(attr, sortedValues), …])` in
  ///   `TripAttribute.allCases` declaration order. Values within each match
  ///   are sorted alphabetically so the encoded form is stable.
  func toConditions() -> ItemConditions {
    var matches: [ItemConditions] = []
    for attr in TripAttribute.allCases {
      guard let values = byAttribute[attr], !values.isEmpty else { continue }
      matches.append(.match(attribute: attr, anyOf: values.sorted()))
    }
    return matches.isEmpty ? .always : .all(matches)
  }

  /// Decode an `ItemConditions` value into chip selections. Returns nil when
  /// the conditions cannot be expressed in the v1 shape (nested groups,
  /// top-level `.any`, non-`.match` children, empty `anyOf`, or values outside
  /// the attribute's current domain). The editor renders
  /// `AdvancedConditionView` in that case.
  static func from(_ conditions: ItemConditions) -> AttributeSelections? {
    switch conditions {
    case .always:
      return .empty
    case .all(let children):
      guard !children.isEmpty else { return nil }
      var out: [TripAttribute: Set<String>] = [:]
      for child in children {
        guard case .match(let attribute, let anyOf) = child else { return nil }
        guard !anyOf.isEmpty else { return nil }
        let domain = Set(TripAttributeOptions.values(for: attribute))
        guard anyOf.allSatisfy(domain.contains) else { return nil }
        out[attribute, default: []].formUnion(anyOf)
      }
      return AttributeSelections(byAttribute: out)
    case .any, .match:
      return nil
    }
  }

  /// Defensive guard for code paths outside the chip editor. Returns false if
  /// any selected value is outside its attribute's `TripAttributeOptions`
  /// domain.
  func isInDomain() -> Bool {
    for (attr, values) in byAttribute {
      let domain = Set(TripAttributeOptions.values(for: attr))
      if !values.isSubset(of: domain) { return false }
    }
    return true
  }
}
