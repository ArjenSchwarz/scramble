import SwiftUI

/// Dashed-outline "+" affordance shared by Trip-list, Master-tasks-list, and
/// Master-packing-list "create" rows. Renders inside a `List` cell with a
/// transparent row background.
@MainActor struct DashedAddButton: View {
  let title: String
  let accent: Color
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 8) {
        Image(systemName: "plus")
        Text(title)
      }
      .font(.headline)
      .foregroundStyle(accent)
      .frame(maxWidth: .infinity)
      .padding(.vertical, 12)
      .overlay(
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .strokeBorder(
            accent.opacity(0.6),
            style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
          )
      )
    }
    .buttonStyle(.borderless)
    .listRowBackground(Color.clear)
    .listRowSeparator(.hidden)
  }
}
