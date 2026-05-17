import CloudKit
import SwiftUI
import os

/// Phase 5 — Trip Detail Participants section. Lists every member of
/// the trip's `CKShare`
/// (Req [7.1](../../../specs/phase-5-cloudkit-sharing/requirements.md#7.1)),
/// distinguishes pending vs accepted state visibly
/// (Req [7.2](../../../specs/phase-5-cloudkit-sharing/requirements.md#7.2)),
/// and is read-only for participants
/// (Req [7.4](../../../specs/phase-5-cloudkit-sharing/requirements.md#7.4)).
///
/// Visually separate from the Phase 1 trip people roster
/// (Req [7.7](../../../specs/phase-5-cloudkit-sharing/requirements.md#7.7),
/// Req [8.9](../../../specs/phase-5-cloudkit-sharing/requirements.md#8.9)) — the
/// trip people roster is the avatar strip in the header, this section
/// lives between the chip row and the timeline.
@MainActor
struct ParticipantsSection: View {
  let trip: Trip
  let isOwner: Bool
  let sharingService: any SharingService

  @Environment(\.theme) private var theme
  @Environment(\.colorScheme) private var colorScheme

  @State private var participants: [ShareParticipant] = []
  @State private var manageParticipant: ManagePresentation?

  var body: some View {
    let variant = theme.variant(for: colorScheme)

    VStack(alignment: .leading, spacing: 8) {
      if !participants.isEmpty {
        Text("Participants")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(variant.textPrimary)
          .accessibilityIdentifier("tripDetail.participantsSection.heading")

        VStack(alignment: .leading, spacing: 4) {
          ForEach(participants) { participant in
            row(for: participant, variant: variant)
          }
        }
      }
    }
    .padding(.horizontal, participants.isEmpty ? 0 : 16)
    .task { await loadParticipants() }
    .sheet(item: $manageParticipant) { presented in
      UICloudSharingControllerRepresentable(
        share: presented.share,
        container: CKContainer(identifier: ModelStore.cloudKitContainerIdentifier),
        onDismiss: { manageParticipant = nil }
      )
    }
  }

  @ViewBuilder
  private func row(
    for participant: ShareParticipant,
    variant: ThemeVariant
  ) -> some View {
    let rowContent = HStack(spacing: 12) {
      Image(systemName: "person.crop.circle")
        .foregroundStyle(variant.textSecondary)
      VStack(alignment: .leading, spacing: 2) {
        Text(participant.displayName)
          .font(.body)
          .foregroundStyle(variant.textPrimary)
          .accessibilityIdentifier(
            "tripDetail.participantsSection.row.\(participant.displayName)"
          )
        Text(acceptanceLabel(for: participant))
          .font(.caption)
          .foregroundStyle(variant.textSecondary)
          .accessibilityIdentifier(
            "tripDetail.participantsSection.state.\(participant.displayName)"
          )
      }
      Spacer()
    }
    .padding(.vertical, 4)

    if isOwner {
      Button {
        Task { await openManageSheet() }
      } label: {
        rowContent
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier(
        "tripDetail.participantsSection.tap.\(participant.displayName)"
      )
      .accessibilityLabel("Manage \(participant.displayName)")
    } else {
      rowContent
    }
  }

  private func acceptanceLabel(for participant: ShareParticipant) -> String {
    switch participant.acceptanceState {
    case .pending: return "Pending invitation"
    case .accepted: return "Accepted"
    case .removed: return "Removed"
    case .unknown: return "Status unknown"
    }
  }

  private func loadParticipants() async {
    do {
      let fetched = try await sharingService.participants(forTrip: trip.id)
      participants = fetched
    } catch {
      let tripID = trip.id
      let message = error.localizedDescription
      modelLogger.error(
        "[ParticipantsSection.participants-failed] tripID=\(tripID, privacy: .public) error=\(message, privacy: .public)"
      )
    }
  }

  private func openManageSheet() async {
    do {
      let share = try await sharingService.createShare(forTrip: trip.id)
      manageParticipant = ManagePresentation(share: share)
    } catch {
      let tripID = trip.id
      let message = error.localizedDescription
      modelLogger.error(
        "[ParticipantsSection.manage-failed] tripID=\(tripID, privacy: .public) error=\(message, privacy: .public)"
      )
    }
  }

  private struct ManagePresentation: Identifiable {
    let share: CKShare
    var id: String { share.recordID.recordName }
  }
}
