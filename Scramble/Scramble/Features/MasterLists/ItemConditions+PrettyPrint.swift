import Foundation

extension ItemConditions {
  /// Multi-line textual rendering used by `AdvancedConditionView` to preview
  /// non-v1-shape conditions the chip editor cannot represent. Lives outside
  /// `Models/Codable/` so the persisted model file stays CloudKit-pure.
  nonisolated func prettyPrinted(indent: Int = 0) -> String {
    let pad = String(repeating: "  ", count: indent)
    switch self {
    case .always:
      return pad + "always"
    case .match(let attribute, let anyOf):
      let values = anyOf.map(\.attributeValueDisplay).joined(separator: " or ")
      return pad + "\(attribute.rawValue) is \(values)"
    case .all(let children):
      let header = pad + "all of:"
      let body = children.map { $0.prettyPrinted(indent: indent + 1) }
      return ([header] + body).joined(separator: "\n")
    case .any(let children):
      let header = pad + "any of:"
      let body = children.map { $0.prettyPrinted(indent: indent + 1) }
      return ([header] + body).joined(separator: "\n")
    }
  }
}
