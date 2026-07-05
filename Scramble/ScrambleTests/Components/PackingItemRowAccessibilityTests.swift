import Foundation
import SwiftData
import Testing

@testable import Scramble

/// Phase 6 Req 9.3 — `PackingItemRow.composedAccessibilityLabel`.
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

  @Test("A note is appended to the combined label (Req 8.1)")
  func labelIncludesNote() throws {
    let setup = try Self.makeSetup()
    let trip = Trip(name: "T", startDate: .now, endDate: .now)
    setup.context.insert(trip)
    let item = TripPackingItem(
      trip: trip, name: "Toys", state: .unpacked, note: "keep batteries out"
    )
    setup.context.insert(item)
    try setup.context.save()

    let label = PackingItemRow.composedAccessibilityLabel(
      item: item, group: .stillNeedToPack, note: item.note
    )
    #expect(label == "Toys, not packed, note: keep batteries out")
  }

  @Test("No note clause when the item has none")
  func labelOmitsAbsentNote() throws {
    let setup = try Self.makeSetup()
    let (item, _) = try Self.makeItem(state: .unpacked, owner: "Alice", in: setup.context)
    let label = PackingItemRow.composedAccessibilityLabel(
      item: item, group: .stillNeedToPack, note: nil
    )
    #expect(label == "Socks, not packed, owned by Alice")
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

  // MARK: - Helpers

  struct Setup {
    /// Retains the container for the setup's lifetime. A `ModelContext` does
    /// not keep its `ModelContainer` alive, so without this the container
    /// deallocates when the helper returns and any later model access traps
    /// inside SwiftData (SIGTRAP).
    let container: ModelContainer
    let context: ModelContext
  }

  static func makeSetup() throws -> Setup {
    let schema = Schema(versionedSchema: SchemaV3.self)
    let config = ModelConfiguration(
      schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none
    )
    let container = try ModelContainer(for: schema, configurations: [config])
    return Setup(container: container, context: container.mainContext)
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
