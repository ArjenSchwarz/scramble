import SwiftUI

struct PersonAvatar: View {
  enum Size: Hashable, Sendable {
    case compact
    case standard
    case large

    var diameter: CGFloat {
      switch self {
      case .compact: 14
      case .standard: 26
      case .large: 36
      }
    }
  }

  let name: String
  let colorKey: String
  var size: Size = .standard
  var isActive: Bool = false

  @Environment(\.theme) private var theme
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    let color = theme.personColor(key: colorKey, in: colorScheme) ?? .gray
    let diameter = size.diameter
    let borderOpacity: Double = isActive ? 1.0 : 0.33

    Circle()
      .fill(color.opacity(0.16))
      .overlay(
        Circle().strokeBorder(color.opacity(borderOpacity), lineWidth: 1.5)
      )
      .overlay(
        Text(initial)
          .font(.system(size: diameter * 0.42, weight: .heavy))
          .foregroundStyle(color)
      )
      .frame(width: diameter, height: diameter)
  }

  private var initial: String {
    guard let first = name.first else { return "?" }
    return String(first).uppercased()
  }
}
