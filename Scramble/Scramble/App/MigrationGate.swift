import Foundation
import SwiftData
import SwiftUI

/// Phase 5 — launch-time gate that blocks the UI while Stage A's
/// post-migration setup is in flight, then releases so the rest of the
/// app can mount (Reqs
/// [4.3](../../specs/phase-5-cloudkit-sharing/requirements.md#4.3),
/// [4.8](../../specs/phase-5-cloudkit-sharing/requirements.md#4.8)).
///
/// Stage A — the `SchemaV2 → SchemaV3` SwiftData migration — runs during
/// `ModelContainer` construction; by the time `MigrationGate` mounts the
/// SwiftData side is already finished. The gate's job is to:
///
/// 1. Run `ZoneMigrationCoordinator.enqueueAll()` so each existing trip
///    gets a `.pending` journal entry.
/// 2. If `isCloudAvailable` returns true, run `runStageB()` so every
///    `.pending` entry transitions to `.stageBInProgress` and the engine
///    starts pushing records up. The actual upload happens in the
///    background through `CKSyncEngine`; the gate does not wait for
///    `.completed`.
/// 3. Construct the `TripSyncEngine` after the journal has been
///    initialised (Stage A → engine startup ordering).
/// 4. Mount the wrapped content.
///
/// Signed-out users still get past the gate — Stage B is simply skipped
/// per Req [11.3](../../specs/phase-5-cloudkit-sharing/requirements.md#11.3),
/// and trips operate in the existing local-only Phase 1 fallback.
@MainActor
struct MigrationGate<Content: View>: View {
  /// Closure invoked once when the gate decides to release. The body
  /// runs every Phase 5 launch step that has to happen between Stage A
  /// (SwiftData migration) and the rest of the app — enqueue journal
  /// entries, run Stage B, hand the sync engine to its observers.
  let prepare: @MainActor () async -> Void

  @ViewBuilder let content: () -> Content

  @State private var hasReleased: Bool = false

  var body: some View {
    Group {
      if hasReleased {
        content()
      } else {
        MigrationGateSplash()
          .task {
            await prepare()
            hasReleased = true
          }
      }
    }
  }
}

/// Full-screen placeholder shown while `MigrationGate` is gating the UI.
/// Intentionally minimal — the gate releases in well under a second on
/// realistic stores so a busy indicator suffices.
private struct MigrationGateSplash: View {
  var body: some View {
    VStack(spacing: 16) {
      ProgressView()
      Text("Preparing your trips…")
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(.systemBackground))
  }
}
