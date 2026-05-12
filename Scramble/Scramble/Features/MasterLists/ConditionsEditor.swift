import SwiftUI

/// Per-attribute chip-multiselect conditions editor. One row per `TripAttribute`
/// in declaration order; selections within an attribute combine as OR, across
/// attributes as AND (per AC 3.2). The binding is `AttributeSelections`; the
/// caller bridges to `ItemConditions` via `selections.toConditions()`.
@MainActor struct ConditionsEditor: View {
  @Binding var selections: AttributeSelections

  @Environment(\.theme) private var theme
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    let variant = theme.variant(for: colorScheme)
    ForEach(TripAttribute.allCases, id: \.self) { attribute in
      Section(attribute.displayName) {
        LazyVGrid(
          columns: [GridItem(.adaptive(minimum: 88), spacing: 8)],
          spacing: 8
        ) {
          ForEach(TripAttributeOptions.values(for: attribute), id: \.self) { value in
            chip(attribute: attribute, value: value, variant: variant)
          }
        }
        .padding(.vertical, 4)
      }
    }
  }

  private func chip(
    attribute: TripAttribute,
    value: String,
    variant: ThemeVariant
  ) -> some View {
    let isSelected = selections.byAttribute[attribute]?.contains(value) ?? false
    return Button {
      toggle(attribute: attribute, value: value)
    } label: {
      Text(value.attributeValueDisplay)
        .font(.subheadline)
        .foregroundStyle(isSelected ? Color.white : variant.textPrimary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(
          Capsule().fill(isSelected ? variant.accent : variant.surface)
        )
        .overlay(
          Capsule().strokeBorder(
            isSelected ? variant.accent : variant.surfaceBorder,
            lineWidth: 1
          )
        )
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }

  private func toggle(attribute: TripAttribute, value: String) {
    var values = selections.byAttribute[attribute] ?? []
    if values.contains(value) {
      values.remove(value)
    } else {
      values.insert(value)
    }
    if values.isEmpty {
      selections.byAttribute.removeValue(forKey: attribute)
    } else {
      selections.byAttribute[attribute] = values
    }
  }
}
