import CloudKit
import SwiftUI
import os

/// Phase 5 — Trip Detail header trailing toolbar item that presents the
/// system share / manage-participants sheet for the trip's `CKShare`.
/// Visible only when the current user owns the trip's zone
/// (Reqs [5.1](../../../specs/phase-5-cloudkit-sharing/requirements.md#5.1),
/// [5.2](../../../specs/phase-5-cloudkit-sharing/requirements.md#5.2),
/// [5.3](../../../specs/phase-5-cloudkit-sharing/requirements.md#5.3)).
///
/// Stays headless: the button calls `SharingService.createShare` and
/// hands the resulting `CKShare` to `UICloudSharingControllerRepresentable`
/// in a sheet. Network errors surface via a non-blocking transient toast.
@MainActor
struct ShareToolbarButton: View {
  let trip: Trip
  let sharingService: any SharingService

  @State private var presentedShare: PresentedShare?
  @State private var errorMessage: String?

  var body: some View {
    Button {
      Task { await presentShareSheet() }
    } label: {
      Image(systemName: "person.crop.circle.badge.plus")
        .accessibilityLabel("Share trip")
    }
    .accessibilityIdentifier("tripDetail.shareButton")
    .sheet(item: $presentedShare) { presented in
      UICloudSharingControllerRepresentable(
        share: presented.share,
        container: CKContainer(identifier: ModelStore.cloudKitContainerIdentifier),
        onDismiss: { presentedShare = nil },
        onSaveFailure: { error in
          errorMessage = error.localizedDescription
          presentedShare = nil
        }
      )
    }
    .transientToast(message: $errorMessage)
  }

  private func presentShareSheet() async {
    do {
      let share = try await sharingService.createShare(forTrip: trip.id)
      presentedShare = PresentedShare(share: share)
    } catch {
      modelLogger.error(
        "[ShareToolbarButton] createShare failed for tripID=\(trip.id, privacy: .public): \(error.localizedDescription, privacy: .public)"
      )
      errorMessage = "Couldn't open share sheet."
    }
  }

  private struct PresentedShare: Identifiable {
    let share: CKShare
    var id: String { share.recordID.recordName }
  }
}
