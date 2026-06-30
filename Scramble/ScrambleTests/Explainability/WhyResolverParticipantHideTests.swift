import Foundation
import SwiftData
import Testing

@testable import Scramble

/// Phase 5 — verifies the participant-side hide behaviour the
/// WhyDisclosure affordance relies on
/// (Req [3.3](../../../specs/phase-5-cloudkit-sharing/requirements.md#3.3)).
///
/// When the current viewer is a participant on a shared trip,
/// rule-driven items whose master cannot be resolved against the
/// participant's globals zone must return `nil` (affordance hidden) —
/// not `.ruleMasterDeleted`, which is the owner-side fallback.
@Suite("WhyResolver — participant-side hide on unresolved master")
@MainActor
struct WhyResolverParticipantHideTests {

  // Returns the container (not the context) so the caller retains it. A
  // `ModelContext` does not keep its `ModelContainer` alive; returning a bare
  // context lets the container deallocate and the next model access traps
  // inside SwiftData (SIGTRAP).
  private func makeContainer() throws -> ModelContainer {
    let schema = Schema(versionedSchema: SchemaV3.self)
    let config = ModelConfiguration(
      schema: schema,
      isStoredInMemoryOnly: true,
      cloudKitDatabase: .none
    )
    return try ModelContainer(for: schema, configurations: [config])
  }

  // MARK: - TripTask

  @Test("Participant: rule-driven task with missing master returns nil")
  func participantTaskWithUnresolvedMasterIsHidden() throws {
    let container = try makeContainer()
    let context = ModelContext(container)
    let trip = Trip(name: "Trip", startDate: .now, endDate: .now)
    context.insert(trip)
    let task = TripTask(
      trip: trip,
      masterItemID: UUID(),  // master not in participant globals
      name: "Sunscreen reminder",
      phase: .dayBefore,
      source: .rule
    )
    context.insert(task)

    let reason = WhyResolver.reason(
      for: task,
      context: context,
      hideOnUnresolvedMaster: true
    )
    #expect(reason == nil, "Affordance must be hidden when master can't be resolved")
  }

  @Test("Owner: rule-driven task with missing master returns .ruleMasterDeleted")
  func ownerTaskWithUnresolvedMasterFallsBack() throws {
    let container = try makeContainer()
    let context = ModelContext(container)
    let trip = Trip(name: "Trip", startDate: .now, endDate: .now)
    context.insert(trip)
    let task = TripTask(
      trip: trip,
      masterItemID: UUID(),
      name: "Cabin charger",
      phase: .dayBefore,
      source: .rule
    )
    context.insert(task)

    let reason = WhyResolver.reason(for: task, context: context)
    #expect(reason == .ruleMasterDeleted)
  }

  @Test("Participant: manual tasks still resolve to .manual (no hide)")
  func participantManualTaskStillRenders() throws {
    let container = try makeContainer()
    let context = ModelContext(container)
    let trip = Trip(name: "Trip", startDate: .now, endDate: .now)
    context.insert(trip)
    let task = TripTask(
      trip: trip,
      masterItemID: nil,
      name: "Manual task",
      phase: .dayBefore,
      source: .manual
    )
    context.insert(task)

    let reason = WhyResolver.reason(
      for: task,
      context: context,
      hideOnUnresolvedMaster: true
    )
    #expect(reason == .manual)
  }

  // MARK: - TripPackingItem

  @Test("Participant: rule-driven packing item with missing master returns nil")
  func participantPackingItemWithUnresolvedMasterIsHidden() throws {
    let container = try makeContainer()
    let context = ModelContext(container)
    let trip = Trip(name: "Trip", startDate: .now, endDate: .now)
    context.insert(trip)
    let item = TripPackingItem(
      trip: trip,
      person: nil,
      masterItemID: UUID(),
      name: "Sunscreen",
      state: .unpacked,
      source: .rule
    )
    context.insert(item)

    let reason = WhyResolver.reason(
      for: item,
      context: context,
      hideOnUnresolvedMaster: true
    )
    #expect(reason == nil)
  }

  @Test("Owner: rule-driven packing item with missing master falls back to .ruleMasterDeleted")
  func ownerPackingItemWithUnresolvedMasterFallsBack() throws {
    let container = try makeContainer()
    let context = ModelContext(container)
    let trip = Trip(name: "Trip", startDate: .now, endDate: .now)
    context.insert(trip)
    let item = TripPackingItem(
      trip: trip,
      person: nil,
      masterItemID: UUID(),
      name: "Toothbrush",
      state: .unpacked,
      source: .rule
    )
    context.insert(item)

    let reason = WhyResolver.reason(for: item, context: context)
    #expect(reason == .ruleMasterDeleted)
  }
}
