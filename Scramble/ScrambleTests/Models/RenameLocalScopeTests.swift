import Foundation
import SwiftData
import Testing

@testable import Scramble

/// Renaming a rule-driven `TripTask` on a trip is local to that record
/// (Req 7.6). The source `MasterTaskItem.name` is the snapshot origin and must
/// not be retroactively edited.
@Suite("Rename rule-driven TripTask is trip-local", .serialized)
@MainActor
struct RenameLocalScopeTests {

  private static func makeContainer() throws -> ModelContainer {
    let schema = Schema(versionedSchema: SchemaV2.self)
    let config = ModelConfiguration(
      schema: schema,
      isStoredInMemoryOnly: true,
      cloudKitDatabase: .none
    )
    return try ModelContainer(for: schema, configurations: [config])
  }

  @Test("Renaming a rule-driven TripTask does not alter the source MasterTaskItem.name")
  func renamingTripTaskDoesNotMutateMaster() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext

    let master = MasterTaskItem(
      name: "Pack umbrella",
      phase: .dayBefore,
      conditions: .match(attribute: .weather, anyOf: ["rain"])
    )
    context.insert(master)
    let trip = Trip(name: "T", startDate: .now, endDate: .now)
    context.insert(trip)
    let task = TripTask(
      trip: trip,
      masterItemID: master.id,
      name: master.name,
      phase: .dayBefore,
      source: .rule
    )
    context.insert(task)
    try context.save()

    // Rename the trip-level task.
    task.name = "renamed"
    try context.save()

    let masters = try context.fetch(FetchDescriptor<MasterTaskItem>())
    #expect(masters.count == 1)
    #expect(
      masters.first?.name == "Pack umbrella", "Master name must not change when TripTask is renamed"
    )

    let tasks = try context.fetch(FetchDescriptor<TripTask>())
    #expect(tasks.count == 1)
    #expect(tasks.first?.name == "renamed")
    #expect(tasks.first?.masterItemID == master.id)
  }
}
