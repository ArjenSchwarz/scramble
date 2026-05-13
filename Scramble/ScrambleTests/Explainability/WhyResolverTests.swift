import Foundation
import SwiftData
import Testing

@testable import Scramble

@Suite("WhyResolver", .serialized)
@MainActor
struct WhyResolverTests {

  // MARK: - Container helper

  private static func makeContainer() throws -> ModelContainer {
    let schema = Schema(versionedSchema: SchemaV2.self)
    let config = ModelConfiguration(
      schema: schema,
      isStoredInMemoryOnly: true,
      cloudKitDatabase: .none
    )
    return try ModelContainer(for: schema, configurations: [config])
  }

  private static func rainyAttributes() -> TripAttributes {
    var a = TripAttributes()
    a.toggle(.weather, value: "rain")
    return a
  }

  private static func sunnyAttributes() -> TripAttributes {
    var a = TripAttributes()
    a.toggle(.weather, value: "sun")
    return a
  }

  // MARK: - .manual

  @Test("manual task → .manual reason")
  func manualReason() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext

    let trip = Trip(name: "T", startDate: .now, endDate: .now, attributes: Self.rainyAttributes())
    context.insert(trip)
    let task = TripTask(
      trip: trip,
      masterItemID: nil,
      name: "One-off",
      phase: .dayBefore,
      source: .manual
    )
    context.insert(task)
    try context.save()

    #expect(WhyResolver.reason(for: task, context: context) == .manual)
  }

  // MARK: - .ruleMasterDeleted

  @Test("rule task with nil masterItemID → .ruleMasterDeleted")
  func ruleMasterDeletedNilID() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext

    let trip = Trip(name: "T", startDate: .now, endDate: .now, attributes: Self.rainyAttributes())
    context.insert(trip)
    let task = TripTask(
      trip: trip,
      masterItemID: nil,
      name: "Orphan",
      phase: .dayBefore,
      source: .rule
    )
    context.insert(task)
    try context.save()

    #expect(WhyResolver.reason(for: task, context: context) == .ruleMasterDeleted)
  }

  @Test("rule task whose masterItemID resolves to nothing → .ruleMasterDeleted")
  func ruleMasterDeletedNotFound() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext

    let trip = Trip(name: "T", startDate: .now, endDate: .now, attributes: Self.rainyAttributes())
    context.insert(trip)
    let danglingID = UUID()
    let task = TripTask(
      trip: trip,
      masterItemID: danglingID,
      name: "Orphan",
      phase: .dayBefore,
      source: .rule
    )
    context.insert(task)
    try context.save()

    #expect(WhyResolver.reason(for: task, context: context) == .ruleMasterDeleted)
  }

  @Test("rule task whose master was deleted after save → .ruleMasterDeleted")
  func ruleMasterDeletedAfterCreation() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext

    let master = MasterTaskItem(
      name: "Pack umbrella",
      phase: .dayBefore,
      conditions: .match(attribute: .weather, anyOf: ["rain"])
    )
    context.insert(master)
    let trip = Trip(name: "T", startDate: .now, endDate: .now, attributes: Self.rainyAttributes())
    context.insert(trip)
    let task = TripTask(
      trip: trip,
      masterItemID: master.id,
      name: "Pack umbrella",
      phase: .dayBefore,
      source: .rule
    )
    context.insert(task)
    try context.save()

    context.delete(master)
    try context.save()

    #expect(WhyResolver.reason(for: task, context: context) == .ruleMasterDeleted)
  }

  // MARK: - .ruleMatched

  @Test("rule task with matching master + matching trip attrs → .ruleMatched with conditionsText")
  func ruleMatched() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext

    let master = MasterTaskItem(
      name: "Pack umbrella",
      phase: .dayBefore,
      conditions: .match(attribute: .weather, anyOf: ["rain"])
    )
    context.insert(master)
    let trip = Trip(name: "T", startDate: .now, endDate: .now, attributes: Self.rainyAttributes())
    context.insert(trip)
    let task = TripTask(
      trip: trip,
      masterItemID: master.id,
      name: "Pack umbrella",
      phase: .dayBefore,
      source: .rule
    )
    context.insert(task)
    try context.save()

    let reason = WhyResolver.reason(for: task, context: context)
    #expect(reason == .ruleMatched(conditionsText: "Rain"))
  }

  // MARK: - .ruleNoLongerMatches

  @Test("rule task with master present but conditions no longer match trip → .ruleNoLongerMatches")
  func ruleNoLongerMatches() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext

    let master = MasterTaskItem(
      name: "Pack umbrella",
      phase: .dayBefore,
      conditions: .match(attribute: .weather, anyOf: ["rain"])
    )
    context.insert(master)
    let trip = Trip(name: "T", startDate: .now, endDate: .now, attributes: Self.sunnyAttributes())
    context.insert(trip)
    let task = TripTask(
      trip: trip,
      masterItemID: master.id,
      name: "Pack umbrella",
      phase: .dayBefore,
      source: .rule
    )
    context.insert(task)
    try context.save()

    #expect(WhyResolver.reason(for: task, context: context) == .ruleNoLongerMatches)
  }

  // MARK: - Regression: resolver re-reads current trip attributes on each call

  @Test("Resolver reflects new trip attributes after mutation (no stale snapshot)")
  func reflectsMutatedAttributes() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext

    let master = MasterTaskItem(
      name: "Pack umbrella",
      phase: .dayBefore,
      conditions: .match(attribute: .weather, anyOf: ["rain"])
    )
    context.insert(master)
    let trip = Trip(name: "T", startDate: .now, endDate: .now, attributes: Self.rainyAttributes())
    context.insert(trip)
    let task = TripTask(
      trip: trip,
      masterItemID: master.id,
      name: "Pack umbrella",
      phase: .dayBefore,
      source: .rule
    )
    context.insert(task)
    try context.save()

    // First call: matches.
    #expect(WhyResolver.reason(for: task, context: context) == .ruleMatched(conditionsText: "Rain"))

    // Mutate trip attributes — switch to sunny.
    trip.attributes = Self.sunnyAttributes()
    try context.save()

    // Second call: same task, same context — should reflect new attrs.
    #expect(WhyResolver.reason(for: task, context: context) == .ruleNoLongerMatches)
  }
}
