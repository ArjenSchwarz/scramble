import SwiftData
import SwiftUI
import os

/// Phase 5 — inline banner above the Trip List that surfaces every
/// `MigrationJournalEntry.state == .failed` row (Req
/// [4.4](../../../specs/phase-5-cloudkit-sharing/requirements.md#4.4)).
/// Tapping a row re-runs Stage B for that trip via the supplied
/// `onRetry` closure (production wires it to
/// `ZoneMigrationCoordinator.retry(tripID:)`).
@MainActor
struct MigrationRetryBanner: View {
  let onRetry: (UUID) -> Void

  @Query(
    filter: #Predicate<MigrationJournalEntry> {
      $0.stateRaw == "failed"
    },
    sort: \MigrationJournalEntry.updatedAt,
    order: .reverse
  )
  private var failedEntries: [MigrationJournalEntry]

  @Environment(\.theme) private var theme
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    if failedEntries.isEmpty {
      EmptyView()
    } else {
      let variant = theme.variant(for: colorScheme)
      VStack(spacing: 0) {
        ForEach(failedEntries) { entry in
          Button {
            onRetry(entry.tripID)
          } label: {
            row(for: entry, variant: variant)
          }
          .buttonStyle(.plain)
          .accessibilityIdentifier("tripList.migrationRetry.\(entry.tripID.uuidString)")
        }
      }
      .accessibilityIdentifier("tripList.migrationRetryBanner")
    }
  }

  private func row(
    for entry: MigrationJournalEntry,
    variant: ThemeVariant
  ) -> some View {
    HStack(spacing: 12) {
      Image(systemName: "exclamationmark.triangle.fill")
        .foregroundStyle(.orange)
      VStack(alignment: .leading, spacing: 2) {
        Text("Sync failed")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(variant.textPrimary)
        Text(entry.errorMessage ?? "Tap to retry.")
          .font(.caption)
          .foregroundStyle(variant.textSecondary)
      }
      Spacer()
      Text("Retry")
        .font(.caption.weight(.semibold))
        .foregroundStyle(variant.accent)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
    .background(variant.surface)
    .overlay(
      Rectangle()
        .fill(Color.orange.opacity(0.4))
        .frame(height: 2),
      alignment: .top
    )
  }
}
