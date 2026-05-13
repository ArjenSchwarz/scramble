import Foundation

/// Renders an `ItemConditions` tree as a human-readable explanation of which
/// trip attributes currently match.
///
/// Walks the tree, collects every `.match(attribute:, anyOf:)` leaf, and
/// for each `TripAttribute.allCases` intersects the union of the master's
/// allowed values for that attribute with the trip's currently selected
/// values. Each intersected value is rendered via `attributeValueDisplay`
/// (so output matches the chips and pickers elsewhere in the UI); the
/// per-attribute matched values are joined with `" or "`, and the
/// non-empty per-attribute strings are joined with `" + "` in
/// `TripAttribute.allCases` order.
///
/// `.always` and any condition whose `.match` leaves do not intersect the
/// trip's attributes return the empty string. The structure of `.all` /
/// `.any` does not influence the output — the formatter explains *which
/// attribute values currently overlap with the trip*, not the boolean shape
/// of the master rule.
enum ConditionsFormatter {

  nonisolated static func format(
    _ conditions: ItemConditions,
    against attributes: TripAttributes
  ) -> String {
    // Collect master-side allowed values per attribute (union across all
    // `.match` leaves in the tree).
    var masterValuesByAttribute: [TripAttribute: Set<String>] = [:]
    collect(conditions, into: &masterValuesByAttribute)

    // For each attribute (in canonical order), keep only values currently
    // selected on the trip, preserving the trip's selection order so the
    // output is stable and predictable.
    var groups: [String] = []
    for attribute in TripAttribute.allCases {
      guard let allowed = masterValuesByAttribute[attribute], !allowed.isEmpty else { continue }
      let selected = attributes.selected(attribute)
      let intersected = selected.filter { allowed.contains($0) }
      guard !intersected.isEmpty else { continue }
      groups.append(intersected.map(\.attributeValueDisplay).joined(separator: " or "))
    }
    return groups.joined(separator: " + ")
  }

  private nonisolated static func collect(
    _ conditions: ItemConditions,
    into bucket: inout [TripAttribute: Set<String>]
  ) {
    switch conditions {
    case .always:
      return
    case .match(let attribute, let anyOf):
      bucket[attribute, default: []].formUnion(anyOf)
    case .all(let children), .any(let children):
      for child in children { collect(child, into: &bucket) }
    }
  }
}
