import CloudKit
import SwiftUI
import UIKit

/// SwiftUI wrapper around `UICloudSharingController` so the share-invite
/// and manage-participants sheets can be presented from a SwiftUI view
/// hierarchy (Reqs 5, 7).
///
/// Construction takes the `CKShare` to surface plus the `CKContainer`
/// owning the share. Lifecycle callbacks fire `onDismiss` so callers can
/// release any pending state, and `onSaveFailure` so the surrounding view
/// can surface a non-blocking error toast per Req 11.4.
@MainActor
struct UICloudSharingControllerRepresentable: UIViewControllerRepresentable {
  let share: CKShare
  let container: CKContainer
  var onDismiss: () -> Void = {}
  var onSaveFailure: (any Error) -> Void = { _ in }

  func makeUIViewController(context: Context) -> UICloudSharingController {
    let controller = UICloudSharingController(share: share, container: container)
    controller.delegate = context.coordinator
    controller.availablePermissions = [.allowReadWrite, .allowPrivate]
    return controller
  }

  func updateUIViewController(_ uiViewController: UICloudSharingController, context: Context) {
    // No dynamic updates — the controller is configured at construction.
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(onDismiss: onDismiss, onSaveFailure: onSaveFailure)
  }

  final class Coordinator: NSObject, UICloudSharingControllerDelegate {
    private let onDismiss: () -> Void
    private let onSaveFailure: (any Error) -> Void

    init(
      onDismiss: @escaping () -> Void,
      onSaveFailure: @escaping (any Error) -> Void
    ) {
      self.onDismiss = onDismiss
      self.onSaveFailure = onSaveFailure
    }

    nonisolated func cloudSharingController(
      _ csc: UICloudSharingController,
      failedToSaveShareWithError error: any Error
    ) {
      Task { @MainActor in
        self.onSaveFailure(error)
      }
    }

    nonisolated func itemTitle(for csc: UICloudSharingController) -> String? {
      // CloudKit fills in a sensible default; subtitle on Trip Detail
      // handles the trip name in the share sheet preview.
      nil
    }

    nonisolated func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
      Task { @MainActor in
        self.onDismiss()
      }
    }

    nonisolated func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
      // CKSyncEngine confirms the save via sentRecordZoneChanges, but the
      // SwiftUI parent's sheet binding does not observe UIKit's internal
      // dismissal — without `onDismiss` the `isPresented` binding stays
      // true and re-tapping Share won't re-present the sheet.
      Task { @MainActor in
        self.onDismiss()
      }
    }
  }
}
