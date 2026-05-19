import Foundation
import SwiftData
import Testing

@testable import Scramble

@Suite("TaskRow.assigneeSnapshot(for:)")
@MainActor
struct TaskRowAssigneeTests {

  private static func makeContainer() throws -> ModelContainer {
    let schema = Schema(versionedSchema: SchemaV3.self)
    let config = ModelConfiguration(
      schema: schema,
      isStoredInMemoryOnly: true,
      cloudKitDatabase: .none
    )
    return try ModelContainer(for: schema, configurations: [config])
  }

  @discardableResult
  private static func makeSnapshot(
    personID: UUID,
    name: String,
    trip: Trip,
    in context: ModelContext
  ) -> TripPersonSnapshot {
    let snapshot = TripPersonSnapshot(
      personID: personID,
      name: name,
      colourID: "cyan",
      initialSource: "name",
      isRosterMember: true,
      trip: trip
    )
    context.insert(snapshot)
    return snapshot
  }

  @Test("Returns the snapshot whose personID matches task.assigneePersonID")
  func returnsMatchingSnapshot() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext

    let trip = Trip(name: "Trip", startDate: .now, endDate: .now)
    context.insert(trip)
    let personID = UUID()
    let snapshot = Self.makeSnapshot(personID: personID, name: "Alice", trip: trip, in: context)
    _ = Self.makeSnapshot(personID: UUID(), name: "Bob", trip: trip, in: context)
    let task = TripTask(trip: trip, name: "Pack", assigneePersonID: personID)
    context.insert(task)
    try context.save()

    let resolved = TaskRow.assigneeSnapshot(for: task)
    #expect(resolved?.id == snapshot.id)
  }

  @Test("Returns nil when no participantSnapshot matches assigneePersonID")
  func returnsNilWhenNoMatchingSnapshot() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext

    let trip = Trip(name: "Trip", startDate: .now, endDate: .now)
    context.insert(trip)
    _ = Self.makeSnapshot(personID: UUID(), name: "Alice", trip: trip, in: context)
    let task = TripTask(trip: trip, name: "Pack", assigneePersonID: UUID())
    context.insert(task)
    try context.save()

    #expect(TaskRow.assigneeSnapshot(for: task) == nil)
  }

  @Test("Returns nil when task.assigneePersonID is nil")
  func returnsNilWhenAssigneeIsNil() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext

    let trip = Trip(name: "Trip", startDate: .now, endDate: .now)
    context.insert(trip)
    _ = Self.makeSnapshot(personID: UUID(), name: "Alice", trip: trip, in: context)
    let task = TripTask(trip: trip, name: "Pack", assigneePersonID: nil)
    context.insert(task)
    try context.save()

    #expect(TaskRow.assigneeSnapshot(for: task) == nil)
  }

  @Test("Returns nil when trip has no participantSnapshots")
  func returnsNilWhenTripHasNoSnapshots() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext

    let trip = Trip(name: "Trip", startDate: .now, endDate: .now)
    context.insert(trip)
    let task = TripTask(trip: trip, name: "Pack", assigneePersonID: UUID())
    context.insert(task)
    try context.save()

    #expect(TaskRow.assigneeSnapshot(for: task) == nil)
  }
}
