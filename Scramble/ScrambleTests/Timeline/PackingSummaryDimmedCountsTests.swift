import Foundation
import SwiftData
import Testing

@testable import Scramble

@Suite("Packing summary counts include dimmed items (Req 1.6)", .serialized)
@MainActor
struct PackingSummaryDimmedCountsTests {

  private static func makeContainer() throws -> ModelContainer {
    let schema = Schema(versionedSchema: SchemaV3.self)
    let config = ModelConfiguration(
      schema: schema,
      isStoredInMemoryOnly: true,
      cloudKitDatabase: .none
    )
    return try ModelContainer(for: schema, configurations: [config])
  }

  private struct Seed {
    let container: ModelContainer
    let trip: Trip
    let person: Person
  }

  private static func seed(
    states: [PackingState],
    matches: [Bool],
    pinned: [Bool]
  ) throws -> Seed {
    let container = try makeContainer()
    let context = container.mainContext
    let trip = Trip(name: "T", startDate: .now, endDate: .now)
    context.insert(trip)
    let person = Person(name: "Alice", colorKey: "blue")
    context.insert(person)
    let snapshot = TripPersonSnapshot(personID: person.id, name: person.name, trip: trip)
    context.insert(snapshot)
    trip.participantSnapshots = [snapshot]
    for (idx, state) in states.enumerated() {
      context.insert(
        TripPackingItem(
          trip: trip,
          name: "item-\(idx)",
          state: state,
          source: .rule,
          currentlyMatchesRules: matches[idx],
          pinnedByUser: pinned[idx],
          personSnapshot: snapshot
        ))
    }
    try context.save()
    return Seed(container: container, trip: trip, person: person)
  }

  @Test("A dimmed (unmatched-non-pinned) packed item still counts in 'packed'")
  func dimmedPackedCounted() throws {
    let seed = try Self.seed(
      states: [.packed, .packed, .unpacked],
      matches: [false, true, true],
      pinned: [false, false, false]
    )
    let counts = PackingListHelpers.counts(for: seed.person, in: seed.trip)
    #expect(counts.packed == 2)
    #expect(counts.toPack == 1)
    _ = seed.container
  }

  @Test("A dimmed unpacked item still counts in 'toPack'")
  func dimmedUnpackedCounted() throws {
    let seed = try Self.seed(
      states: [.unpacked, .unpacked, .packed],
      matches: [false, true, true],
      pinned: [false, false, false]
    )
    let counts = PackingListHelpers.counts(for: seed.person, in: seed.trip)
    #expect(counts.toPack == 2)
    #expect(counts.packed == 1)
    _ = seed.container
  }

  @Test("A dimmed repacked item still counts in 'repacked'")
  func dimmedRepackedCounted() throws {
    let seed = try Self.seed(
      states: [.repacked, .packed],
      matches: [false, true],
      pinned: [false, false]
    )
    let counts = PackingListHelpers.counts(for: seed.person, in: seed.trip)
    #expect(counts.repacked == 1)
    #expect(counts.packed == 1)
    _ = seed.container
  }

  @Test("Pack-mode progress ratio reflects dimmed items in numerator/denominator")
  func packRatioWithDimmed() throws {
    let seed = try Self.seed(
      states: [.packed, .unpacked],
      matches: [false, true],
      pinned: [false, false]
    )
    let counts = PackingListHelpers.counts(for: seed.person, in: seed.trip)
    let ratio = PackingListHelpers.progressRatio(counts, mode: .pack)
    #expect(ratio == 0.5)
    _ = seed.container
  }
}
