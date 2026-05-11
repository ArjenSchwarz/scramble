import SwiftUI

/// Self-dismissing toast banner used for non-blocking notifications (e.g. orphaned
/// participants on trip save). Pass `nil` to dismiss; pass a non-nil message to show
/// for `duration` seconds and then clear itself.
struct TransientToastModifier: ViewModifier {
  @Binding var message: String?
  var duration: TimeInterval = 3.0

  @Environment(\.theme) private var theme
  @Environment(\.colorScheme) private var colorScheme

  func body(content: Content) -> some View {
    content
      .overlay(alignment: .bottom) {
        if let message {
          let variant = theme.variant(for: colorScheme)
          Text(message)
            .font(.subheadline)
            .foregroundStyle(variant.textPrimary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
              RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(variant.surface)
            )
            .overlay(
              RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(variant.surfaceBorder, lineWidth: 1)
            )
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .task(id: message) {
              try? await Task.sleep(for: .seconds(duration))
              guard !Task.isCancelled else { return }
              withAnimation { self.message = nil }
            }
        }
      }
      .animation(.easeInOut(duration: 0.2), value: message)
  }
}

extension View {
  func transientToast(message: Binding<String?>, duration: TimeInterval = 3.0) -> some View {
    modifier(TransientToastModifier(message: message, duration: duration))
  }
}
