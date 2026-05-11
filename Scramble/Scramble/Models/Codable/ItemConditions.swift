import Foundation

nonisolated indirect enum ItemConditions: Codable, Equatable, Sendable {
  case always
  case match(attribute: TripAttribute, anyOf: [String])
  case all([ItemConditions])
  case any([ItemConditions])

  func evaluate(against attributes: TripAttributes) -> Bool {
    switch self {
    case .always:
      return true
    case .match(let attribute, let anyOf):
      let selected = Set(attributes.selected(attribute))
      return anyOf.contains { selected.contains($0) }
    case .all(let children):
      return children.allSatisfy { $0.evaluate(against: attributes) }
    case .any(let children):
      return children.contains { $0.evaluate(against: attributes) }
    }
  }

  private enum CodingKeys: String, CodingKey {
    case type
    case attribute
    case anyOf
    case children
  }

  private enum Kind: String, Codable {
    case always
    case match
    case all
    case any
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let kind = try container.decode(Kind.self, forKey: .type)
    switch kind {
    case .always:
      self = .always
    case .match:
      let attribute = try container.decode(TripAttribute.self, forKey: .attribute)
      let anyOf = try container.decode([String].self, forKey: .anyOf)
      self = .match(attribute: attribute, anyOf: anyOf)
    case .all:
      let children = try container.decode([ItemConditions].self, forKey: .children)
      self = .all(children)
    case .any:
      let children = try container.decode([ItemConditions].self, forKey: .children)
      self = .any(children)
    }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .always:
      try container.encode(Kind.always, forKey: .type)
    case .match(let attribute, let anyOf):
      try container.encode(Kind.match, forKey: .type)
      try container.encode(attribute, forKey: .attribute)
      try container.encode(anyOf, forKey: .anyOf)
    case .all(let children):
      try container.encode(Kind.all, forKey: .type)
      try container.encode(children, forKey: .children)
    case .any(let children):
      try container.encode(Kind.any, forKey: .type)
      try container.encode(children, forKey: .children)
    }
  }
}
