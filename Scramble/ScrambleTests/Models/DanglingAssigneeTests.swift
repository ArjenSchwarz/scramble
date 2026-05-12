import Foundation
import SwiftData
import Testing

@testable import Scramble

/// `TripTask.assigneePersonID` is stored as a plain `UUID?` (Decision 9), not a
/// SwiftData `@Relationship`, so deleting the referenced `Person` must leave the
/// UUID intact on the task. The row will render without an avatar (Req 4.8 / 9.4).
@Suite("Dangling assigneePersonID", .serialized)
@MainActor
struct DanglingAssigneeTests {

  private static func makeContainer() throws -> ModelContainer {
    let schema = Schema(versionedSchema: SchemaV2.self)
    let config = ModelConfiguration(
      schema: schema,
      isStoredInMemoryOnly: true,
      cloudKitDatabase: .none
    )
    return try ModelContainer(for: schema, configurations: [config])
  }

  @Test(
    "Deleting Person referenced by assigneePersonID leaves TripTask intact with the UUID preserved")
  func deletingAssigneePersonLeavesTaskWithDanglingID() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext

    let person = Person(name: "Arjen", colorKey: "cyan")
    context.insert(person)
    let personID = person.id
    let trip = Trip(name: "T", startDate: .now, endDate: .now)
    context.insert(trip)
    let task = TripTask(
      trip: trip,
      name: "Pack umbrella",
      phase: .dayBefore,
      source: .rule,
      assigneePersonID: personID
    )
    context.insert(task)
    try context.save()

    // Sanity: assignee is set up-front.
    let initial = try context.fetch(FetchDescriptor<TripTask>())
    #expect(initial.first?.assigneePersonID == personID)

    // Delete the Person.
    context.delete(person)
    try context.save()

    let fetched = try context.fetch(FetchDescriptor<TripTask>())
    #expect(fetched.count == 1)
    let stored = try #require(fetched.first)
    #expect(stored.name == "Pack umbrella")
    #expect(stored.assigneePersonID == personID, "Dangling assignee UUID must be preserved")
    // And the Person really is gone.
    let people = try context.fetch(FetchDescriptor<Person>())
    #expect(people.isEmpty)
  }

  @Test("Removing Person from trip.participants does not modify task.assigneePersonID")
  func removingFromParticipantsLeavesAssigneeIntact() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext

    let person = Person(name: "Kelsey", colorKey: "green")
    context.insert(person)
    let trip = Trip(name: "T", startDate: .now, endDate: .now)
    context.insert(trip)
    trip.participants = [person]
    let task = TripTask(
      trip: trip,
      name: "Buy tickets",
      source: .rule,
      assigneePersonID: person.id
    )
    context.insert(task)
    try context.save()

    trip.participants.removeAll(where: { $0.id == person.id })
    try context.save()

    let fetched = try context.fetch(FetchDescriptor<TripTask>())
    #expect(fetched.first?.assigneePersonID == person.id)
  }
}
