import Foundation

nonisolated struct TripAttributes: Codable, Equatable, Sendable {
  var values: [TripAttribute: [String]] = [:]

  init() {}

  func selected(_ attribute: TripAttribute) -> [String] {
    values[attribute] ?? []
  }

  mutating func setSingle(_ attribute: TripAttribute, value: String?) {
    if let value {
      values[attribute] = [value]
    } else {
      values[attribute] = nil
    }
  }

  mutating func toggle(_ attribute: TripAttribute, value: String) {
    var current = values[attribute] ?? []
    if let index = current.firstIndex(of: value) {
      current.remove(at: index)
    } else {
      current.append(value)
    }
    values[attribute] = current.isEmpty ? nil : current
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: AttributeKey.self)
    var decoded: [TripAttribute: [String]] = [:]
    for key in container.allKeys {
      guard let attribute = TripAttribute(rawValue: key.stringValue) else { continue }
      decoded[attribute] = try container.decode([String].self, forKey: key)
    }
    self.values = decoded
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: AttributeKey.self)
    // Sort by raw value for deterministic on-disk ordering.
    let sorted = values.sorted { $0.key.rawValue < $1.key.rawValue }
    for (attribute, vals) in sorted {
      try container.encode(vals, forKey: AttributeKey(attribute.rawValue))
    }
  }

  private struct AttributeKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }
    init(_ stringValue: String) { self.stringValue = stringValue }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
  }
}
