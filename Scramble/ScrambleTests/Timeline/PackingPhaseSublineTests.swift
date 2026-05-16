import Foundation
import SwiftData
import Testing

@testable import Scramble

@Suite("PackingListHelpers.phaseSubline", .serialized)
@MainActor
struct PackingPhaseSublineTests {

  // MARK: - Container helper

  private static func makeContainer() throws -> ModelContainer {
    let schema = Schema(versionedSchema: SchemaV3.self)
    let config = ModelConfiguration(
      schema: schema,
      isStoredInMemoryOnly: true,
      cloudKitDatabase: .none
    )
    return try ModelContainer(for: schema, configurations: [config])
  }

  private static func seed(
    perPersonStates: [[PackingState]]
  ) throws -> (ModelContainer, Trip) {
    let container = try makeContainer()
    let context = container.mainContext
    let trip = Trip(name: "T", startDate: .now, endDate: .now)
    context.insert(trip)
    var participants: [Person] = []
    for (idx, states) in perPersonStates.enumerated() {
      let person = Person(name: "P\(idx)", colorKey: "blue")
      context.insert(person)
      participants.append(person)
      for (i, state) in states.enumerated() {
        context.insert(
          TripPackingItem(
            trip: trip,
            person: person,
            name: "p\(idx)-i\(i)",
            state: state,
            source: .rule
          ))
      }
    }
    trip.participants = participants
    try context.save()
    return (container, trip)
  }

  // MARK: - Pack mode

  @Test("Pack: empty participants → 'packing ready'")
  func packEmptyParticipants() throws {
    let (container, trip) = try Self.seed(perPersonStates: [])
    #expect(PackingListHelpers.phaseSubline(trip, mode: .pack) == "packing ready")
    _ = container
  }

  @Test("Pack: every person zero unpacked → 'packing ready'")
  func packAllReady() throws {
    let (container, trip) = try Self.seed(perPersonStates: [
      [.packed, .packed],
      [.packed, .excluded],
      [],
    ])
    #expect(PackingListHelpers.phaseSubline(trip, mode: .pack) == "packing ready")
    _ = container
  }

  @Test("Pack: sums per-person 'to pack' counts across participants")
  func packSums() throws {
    let (container, trip) = try Self.seed(perPersonStates: [
      [.unpacked, .unpacked, .packed],  // 2 to pack
      [.unpacked, .packed],  // 1 to pack
      [.packed, .excluded],  // 0 to pack
    ])
    #expect(PackingListHelpers.phaseSubline(trip, mode: .pack) == "3 to pack")
    _ = container
  }

  @Test("Pack: single person, single unpacked → '1 to pack'")
  func packOne() throws {
    let (container, trip) = try Self.seed(perPersonStates: [[.unpacked]])
    #expect(PackingListHelpers.phaseSubline(trip, mode: .pack) == "1 to pack")
    _ = container
  }

  // MARK: - Repack mode

  @Test("Repack: empty participants → 'all back in'")
  func repackEmptyParticipants() throws {
    let (container, trip) = try Self.seed(perPersonStates: [])
    #expect(PackingListHelpers.phaseSubline(trip, mode: .repack) == "all back in")
    _ = container
  }

  @Test("Repack: every person zero packed → 'all back in'")
  func repackAllBackIn() throws {
    let (container, trip) = try Self.seed(perPersonStates: [
      [.repacked, .repacked],
      [.repacked, .unpacked],  // unpacked = left behind, not pending repack
      [],
    ])
    #expect(PackingListHelpers.phaseSubline(trip, mode: .repack) == "all back in")
    _ = container
  }

  @Test("Repack: sums per-person 'to repack' counts across participants")
  func repackSums() throws {
    let (container, trip) = try Self.seed(perPersonStates: [
      [.packed, .packed, .repacked],  // 2 to repack
      [.packed],  // 1 to repack
      [.repacked, .unpacked],  // 0 to repack
    ])
    #expect(PackingListHelpers.phaseSubline(trip, mode: .repack) == "3 to repack")
    _ = container
  }

  @Test("Repack: single packed item → '1 to repack'")
  func repackOne() throws {
    let (container, trip) = try Self.seed(perPersonStates: [[.packed]])
    #expect(PackingListHelpers.phaseSubline(trip, mode: .repack) == "1 to repack")
    _ = container
  }
}
