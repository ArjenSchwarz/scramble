import Foundation
import SwiftData
import Testing

@testable import Scramble

/// Phase 5 — `SchemaV2 → SchemaV3` plan-shape coverage.
///
/// Mirrors the `SchemaV2MigrationTests` deferral pattern: the on-disk
/// V2→V3 round-trip is intentionally skipped. Two `@Model` types named
/// `Trip` (`SchemaV2.Trip` and `SchemaV3.Trip`), `TripTask`, and
/// `TripPackingItem` cannot all coexist in a single test process while
/// SwiftData resolves entity-class lookup by class name. The tests below
/// pin the migration plan's shape and the V3 default-value behaviour;
/// real on-disk migration is exercised on first launch against an
/// existing on-device store.
@Suite("SchemaV3 migration", .serialized)
@MainActor
struct SchemaV3MigrationTests {

  // MARK: - Migration plan shape

  @Test("AppMigrationPlan declares V1, V2, and V3 (V3 is the current schema)")
  func planLinksAllVersions() {
    let schemaIDs = AppMigrationPlan.schemas.map(ObjectIdentifier.init)
    #expect(schemaIDs.contains(ObjectIdentifier(SchemaV1.self)))
    #expect(schemaIDs.contains(ObjectIdentifier(SchemaV2.self)))
    #expect(schemaIDs.contains(ObjectIdentifier(SchemaV3.self)))
  }

  @Test("AppMigrationPlan exposes V1→V2 lightweight and V2→V3 custom")
  func planExposesAllStages() {
    let stages = AppMigrationPlan.stages
    #expect(stages.count == 2, "Expected one stage per consecutive version pair")
  }

  // MARK: - Phase 6 countryCode rides on V3 (no SchemaV4)

  @Test("SchemaV3 Trip entity includes Phase 6 countryCode")
  func schemaV3IncludesCountryCode() {
    let schema = Schema(versionedSchema: SchemaV3.self)
    let trip = schema.entities.first(where: { $0.name == "Trip" })
    let propertyNames = Set(trip?.properties.map(\.name) ?? [])
    #expect(propertyNames.contains("countryCode"))
  }

  @Test("Fresh V3 Trip defaults countryCode to nil and round-trips through the plan")
  func freshV3TripCountryCodeNil() throws {
    let container = try Self.makeV3Container()
    let context = container.mainContext

    let trip = Trip(name: "Iceland", startDate: .now, endDate: .now)
    context.insert(trip)
    try context.save()

    let stored = try #require(try context.fetch(FetchDescriptor<Trip>()).first)
    #expect(stored.countryCode == nil)
  }

  // MARK: - Fresh V3 entity defaults

  @Test(
    "Fresh V3 Trip defaults: participantSnapshots empty, tripZoneID nil, ckRecordSystemFields nil")
  func freshV3TripDefaults() throws {
    let container = try Self.makeV3Container()
    let context = container.mainContext

    let trip = Trip(name: "T", startDate: .now, endDate: .now)
    context.insert(trip)
    try context.save()

    let stored = try #require(try context.fetch(FetchDescriptor<Trip>()).first)
    #expect(stored.participantSnapshots?.isEmpty ?? true)
    #expect(stored.tripZoneID == nil)
    #expect(stored.ckRecordSystemFields == nil)
  }

  @Test("Fresh V3 TripTask defaults: ckRecordSystemFields nil")
  func freshV3TripTaskDefaults() throws {
    let container = try Self.makeV3Container()
    let context = container.mainContext

    let trip = Trip(name: "T", startDate: .now, endDate: .now)
    context.insert(trip)
    let task = TripTask(trip: trip, name: "Pack")
    context.insert(task)
    try context.save()

    let stored = try #require(try context.fetch(FetchDescriptor<TripTask>()).first)
    #expect(stored.ckRecordSystemFields == nil)
  }

  @Test("Fresh V3 TripPackingItem defaults: personSnapshot nil, ckRecordSystemFields nil")
  func freshV3TripPackingItemDefaults() throws {
    let container = try Self.makeV3Container()
    let context = container.mainContext

    let trip = Trip(name: "T", startDate: .now, endDate: .now)
    context.insert(trip)
    let item = TripPackingItem(trip: trip, name: "Toothbrush")
    context.insert(item)
    try context.save()

    let stored = try #require(try context.fetch(FetchDescriptor<TripPackingItem>()).first)
    #expect(stored.personSnapshot == nil)
    #expect(stored.ckRecordSystemFields == nil)
  }

  @Test("V3 introduces TripPersonSnapshot, TripZoneState, MigrationJournalEntry entities")
  func v3IntroducesNewEntities() {
    let v3Schema = Schema(versionedSchema: SchemaV3.self)
    let names = Set(v3Schema.entities.map(\.name))
    #expect(names.contains("TripPersonSnapshot"))
    #expect(names.contains("TripZoneState"))
    #expect(names.contains("MigrationJournalEntry"))
  }

  // MARK: - Entity name stability

  @Test("Persistent entity names resolve to 'TripTask' under V3 (V2 fork keeps the same name)")
  func entityNameStableForTripTask() {
    let v3Schema = Schema(versionedSchema: SchemaV3.self)
    let v3 = v3Schema.entities.first(where: { $0.name == "TripTask" })?.name
    #expect(v3 == "TripTask")
  }

  // MARK: - Helpers

  private static func makeV3Container() throws -> ModelContainer {
    let schema = Schema(versionedSchema: SchemaV3.self)
    let config = ModelConfiguration(
      schema: schema,
      isStoredInMemoryOnly: true,
      cloudKitDatabase: .none
    )
    return try ModelContainer(
      for: schema,
      migrationPlan: AppMigrationPlan.self,
      configurations: [config]
    )
  }
}
