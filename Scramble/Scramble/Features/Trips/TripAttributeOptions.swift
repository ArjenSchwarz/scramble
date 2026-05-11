import Foundation

/// Canonical attribute values offered by the v1 trip editor. Storage in
/// `TripAttributes` is per Decision 10 a blob of arrays so additional values
/// can be added later without a schema change. v1 enforces single-select on
/// Duration / Transport / Scope / Purpose and multi-select on Weather at the
/// editor level (per Requirement 1.11).
nonisolated enum TripAttributeOptions {
  static let duration: [String] = ["short", "long"]
  static let transport: [String] = ["car", "plane", "train"]
  static let scope: [String] = ["domestic", "international"]
  static let weather: [String] = ["sun", "rain", "cold", "hot"]
  static let purpose: [String] = ["work", "leisure"]

  static func values(for attribute: TripAttribute) -> [String] {
    switch attribute {
    case .duration: duration
    case .transport: transport
    case .scope: scope
    case .weather: weather
    case .purpose: purpose
    }
  }
}

extension TripAttribute {
  var displayName: String {
    switch self {
    case .duration: "Duration"
    case .transport: "Transport"
    case .scope: "Scope"
    case .weather: "Weather"
    case .purpose: "Purpose"
    }
  }

  /// `true` for Weather only. Drives the editor's picker variant (single vs multi).
  var isMultiSelect: Bool { self == .weather }
}

extension String {
  /// Display form for an attribute value used by chips and pickers ("plane" → "Plane").
  var attributeValueDisplay: String {
    self.prefix(1).uppercased() + self.dropFirst()
  }
}
