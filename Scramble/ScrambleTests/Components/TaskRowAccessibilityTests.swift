import Foundation
import SwiftData
import Testing

@testable import Scramble

/// Phase 6 Req 9.2 + 9.5 — TaskRow combined accessibility label and the
/// "Why is this here?" custom action gate.
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

  // MARK: - Why action gate (Req 9.5)

  @Test("Manual one-off task exposes the Why action (returns .manual reason)")
  func manualTaskHasWhy() throws {
    let setup = try Self.makeSetup()
    let trip = Trip(name: "T", startDate: .now, endDate: .now)
    setup.context.insert(trip)
    let task = TripTask(
      trip: trip,
      name: "Manual",
      phase: .departureDay,
      isCompleted: false,
      source: .manual
    )
    setup.context.insert(task)
    try setup.context.save()

    let hasWhy = TaskRow.hasWhyJustification(
      task: task, context: setup.context, hideOnUnresolvedMaster: false
    )
    #expect(hasWhy)
  }

  @Test("Rule task with no master and hideOnUnresolvedMaster=true omits the Why action")
  func participantUnresolvedMasterHidesWhy() throws {
    let setup = try Self.makeSetup()
    let trip = Trip(name: "T", startDate: .now, endDate: .now)
    setup.context.insert(trip)
    let task = TripTask(
      trip: trip,
      masterItemID: UUID(),  // master not present in this context
      name: "Rule",
      phase: .departureDay,
      isCompleted: false,
      source: .rule
    )
    setup.context.insert(task)
    try setup.context.save()

    let hasWhy = TaskRow.hasWhyJustification(
      task: task, context: setup.context, hideOnUnresolvedMaster: true
    )
    #expect(!hasWhy)
  }

  @Test("Owner view of rule task with deleted master still exposes Why (.ruleMasterDeleted)")
  func ownerUnresolvedMasterShowsWhy() throws {
    let setup = try Self.makeSetup()
    let trip = Trip(name: "T", startDate: .now, endDate: .now)
    setup.context.insert(trip)
    let task = TripTask(
      trip: trip,
      masterItemID: UUID(),
      name: "Rule",
      phase: .departureDay,
      isCompleted: false,
      source: .rule
    )
    setup.context.insert(task)
    try setup.context.save()

    let hasWhy = TaskRow.hasWhyJustification(
      task: task, context: setup.context, hideOnUnresolvedMaster: false
    )
    #expect(hasWhy)
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
}
