import Foundation
import SwiftData
import Testing

@testable import Scramble

/// Phase 6 Req 9.3 + 9.5 — `PackingItemRow.composedAccessibilityLabel`
/// and the gated "Why is this here?" custom action.
@Suite("PackingItemRow accessibility", .serialized)
@MainActor
struct PackingItemRowAccessibilityTests {

  // MARK: - Combined label (Req 9.3)

  @Test("Pack-mode unpacked item speaks name + 'not packed' + owner")
  func packModeUnpackedLabel() throws {
    let setup = try Self.makeSetup()
    let (item, _) = try Self.makeItem(state: .unpacked, owner: "Alice", in: setup.context)

    let label = PackingItemRow.composedAccessibilityLabel(
      item: item, group: .stillNeedToPack
    )
    #expect(label == "Socks, not packed, owned by Alice")
  }

  @Test("Packed item in the Packed group speaks 'packed'")
  func packedGroup() throws {
    let setup = try Self.makeSetup()
    let (item, _) = try Self.makeItem(state: .packed, owner: "Alice", in: setup.context)
    let label = PackingItemRow.composedAccessibilityLabel(item: item, group: .packed)
    #expect(label.contains("packed"))
  }

  @Test("Repack-mode Left Behind group speaks 'left behind' regardless of underlying state")
  func leftBehindLabel() throws {
    let setup = try Self.makeSetup()
    let (item, _) = try Self.makeItem(state: .unpacked, owner: "Bob", in: setup.context)
    let label = PackingItemRow.composedAccessibilityLabel(item: item, group: .leftBehind)
    #expect(label == "Socks, left behind, owned by Bob")
  }

  @Test("Excluded item in the Not Bringing group speaks 'not bringing'")
  func notBringingLabel() throws {
    let setup = try Self.makeSetup()
    let (item, _) = try Self.makeItem(state: .excluded, owner: "Bob", in: setup.context)
    let label = PackingItemRow.composedAccessibilityLabel(item: item, group: .notBringing)
    #expect(label == "Socks, not bringing, owned by Bob")
  }

  @Test("Item without an owner snapshot omits the 'owned by' clause")
  func unownedLabel() throws {
    let setup = try Self.makeSetup()
    let trip = Trip(name: "T", startDate: .now, endDate: .now)
    setup.context.insert(trip)
    let item = TripPackingItem(trip: trip, name: "Socks", state: .unpacked)
    setup.context.insert(item)
    try setup.context.save()

    let label = PackingItemRow.composedAccessibilityLabel(
      item: item, group: .stillNeedToPack
    )
    #expect(label == "Socks, not packed")
  }

  // MARK: - Why action gate (Req 9.5)

  @Test("Manual one-off item exposes the Why action")
  func manualHasWhy() throws {
    let setup = try Self.makeSetup()
    let trip = Trip(name: "T", startDate: .now, endDate: .now)
    setup.context.insert(trip)
    let item = TripPackingItem(trip: trip, name: "Manual", source: .manual)
    setup.context.insert(item)
    try setup.context.save()

    let hasWhy = PackingItemRow.hasWhyJustification(
      item: item, context: setup.context, hideOnUnresolvedMaster: false
    )
    #expect(hasWhy)
  }

  @Test("Participant-side unresolved-master rule item hides the Why action")
  func participantUnresolvedHidesWhy() throws {
    let setup = try Self.makeSetup()
    let trip = Trip(name: "T", startDate: .now, endDate: .now)
    setup.context.insert(trip)
    let item = TripPackingItem(
      trip: trip, masterItemID: UUID(), name: "Rule", source: .rule
    )
    setup.context.insert(item)
    try setup.context.save()

    let hasWhy = PackingItemRow.hasWhyJustification(
      item: item, context: setup.context, hideOnUnresolvedMaster: true
    )
    #expect(!hasWhy)
  }

  // MARK: - Helpers

  struct Setup {
    let context: ModelContext
  }

  static func makeSetup() throws -> Setup {
    let schema = Schema(versionedSchema: SchemaV3.self)
    let config = ModelConfiguration(
      schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none
    )
    let container = try ModelContainer(for: schema, configurations: [config])
    return Setup(context: container.mainContext)
  }

  static func makeItem(
    state: PackingState, owner: String, in context: ModelContext
  ) throws -> (TripPackingItem, TripPersonSnapshot) {
    let trip = Trip(name: "T", startDate: .now, endDate: .now)
    context.insert(trip)
    let snapshot = TripPersonSnapshot(
      personID: UUID(),
      name: owner,
      colourID: "cyan",
      initialSource: "manual",
      isRosterMember: true,
      trip: trip
    )
    context.insert(snapshot)
    let item = TripPackingItem(
      trip: trip, name: "Socks", state: state, personSnapshot: snapshot
    )
    context.insert(item)
    try context.save()
    return (item, snapshot)
  }
}
