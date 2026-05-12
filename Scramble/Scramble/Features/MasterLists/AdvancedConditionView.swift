import SwiftUI

/// Read-only placeholder shown when stored conditions cannot round-trip into
/// `AttributeSelections` (nested groups, top-level `.any`, out-of-domain
/// values). Per AC 3.7 the placeholder prints a textual rendering and exposes
/// a "Reset to simple" affordance that replaces the conditions with `.always`.
@MainActor struct AdvancedConditionView: View {
  let conditions: ItemConditions
  let onReset: () -> Void

  @State private var confirmingReset = false

  var body: some View {
    Section("Conditions") {
      VStack(alignment: .leading, spacing: 12) {
        Label("Advanced condition", systemImage: "lock")
          .font(.subheadline.weight(.semibold))
        Text(conditions.prettyPrinted())
          .font(.system(.footnote, design: .monospaced))
          .foregroundStyle(.secondary)
          .textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .leading)
        Text(
          "This item uses a conditions shape the v1 editor cannot represent. "
            + "Editing chips is disabled. Name, phase, and person remain editable."
        )
        .font(.footnote)
        .foregroundStyle(.secondary)
        Button(role: .destructive) {
          confirmingReset = true
        } label: {
          Label("Reset to simple", systemImage: "arrow.counterclockwise")
        }
      }
      .padding(.vertical, 4)
    }
    .confirmationDialog(
      "Reset conditions to empty?",
      isPresented: $confirmingReset,
      titleVisibility: .visible
    ) {
      Button("Reset", role: .destructive) { onReset() }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text(
        "On the next re-evaluation this item will match every non-past trip "
          + "until you save new conditions."
      )
    }
  }
}
