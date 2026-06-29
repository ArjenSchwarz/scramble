import Foundation
import SwiftData
import Testing

@testable import Scramble

/// Phase 6 Req 9.2 — TaskRow combined accessibility label.
@Suite("TaskRow accessibility", .serialized)
@MainActor
struct TaskRowAccessibilityTests {

  // MARK: - Combined label (Req 9.2)

  @Test("Label includes name, completion state, and phase")
  func labelBasic() throws {
    let trip = Trip(name: "T", startDate: .now, endDate: .now)
    let task = TripTask(
      trip: trip, name: "Pack socks", phase: .departureDay, isCompleted: false
    )
    let label = TaskRow.accessibilityLabel(for: task)
    #expect(label.contains("Pack socks"))
    #expect(label.contains("not completed"))
    #expect(label.contains("Departure day"))
  }

  @Test("Completed task speaks as 'completed'")
  func labelCompleted() throws {
    let trip = Trip(name: "T", startDate: .now, endDate: .now)
    let task = TripTask(
      trip: trip, name: "Boarding pass", phase: .dayBefore, isCompleted: true
    )
    let label = TaskRow.accessibilityLabel(for: task)
    #expect(label.contains("completed"))
    #expect(!label.contains("not completed"))
  }

  @Test("Assigned task includes the assignee snapshot name")
  func labelIncludesAssignee() throws {
    let setup = try Self.makeSetup()
    let assigneeID = UUID()
    let trip = Trip(name: "T", startDate: .now, endDate: .now)
    setup.context.insert(trip)
    let snapshot = TripPersonSnapshot(
      personID: assigneeID,
      name: "Alice",
      colourID: "cyan",
      initialSource: "manual",
      isRosterMember: true,
      trip: trip
    )
    setup.context.insert(snapshot)
    let task = TripTask(
      trip: trip,
      name: "Pack socks",
      phase: .departureDay,
      isCompleted: false,
      assigneePersonID: assigneeID
    )
    setup.context.insert(task)
    try setup.context.save()

    let label = TaskRow.accessibilityLabel(for: task)
    #expect(label.contains("assigned to Alice"))
  }

  // MARK: - Helpers

  struct Setup {
    // Retain the container for the test's lifetime; a `ModelContext` does not
    // keep its `ModelContainer` alive, so returning only the context lets the
    // container deallocate out from under it and crashes the test host.
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
}
