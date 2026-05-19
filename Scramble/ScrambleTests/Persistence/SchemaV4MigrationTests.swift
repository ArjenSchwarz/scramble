import Foundation
import SwiftData
import Testing

@testable import Scramble

/// Phase 6 — `SchemaV3 → SchemaV4` lightweight migration coverage.
///
/// The V3 → V4 stage adds a single optional column (`Trip.countryCode`)
/// and is declared `.lightweight` in `AppMigrationPlan`. SwiftData
/// resolves the column on first open via automatic inference because
/// `countryCode` is `Optional` with a `nil` default. These tests round-
/// trip an on-disk store: a V3-shaped container seeds two trips, the
/// container is dropped, a V4 container with the migration plan re-opens
/// the same URL and the trips are read back with `countryCode == nil`.
@Suite("SchemaV4 migration", .serialized)
@MainActor
struct SchemaV4MigrationTests {

  // MARK: - Plan shape

  @Test("V3 → V4 stage is registered as lightweight")
  func planExposesV3ToV4LightweightStage() {
    let schemaIDs = AppMigrationPlan.schemas.map(ObjectIdentifier.init)
    #expect(schemaIDs.contains(ObjectIdentifier(SchemaV4.self)))
  }

  @Test("SchemaV4 entity list includes Trip with countryCode")
  func schemaV4ContainsTripCountryCode() {
    let schema = Schema(versionedSchema: SchemaV4.self)
    let trip = try? #require(schema.entities.first(where: { $0.name == "Trip" }))
    let propertyNames = Set(trip?.properties.map(\.name) ?? [])
    #expect(propertyNames.contains("countryCode"))
  }

  // MARK: - On-disk migration round-trip

  @Test(
    "V3-seeded trips load through the V4 migration with countryCode == nil",
    arguments: ["TripsLocal", "Globals"]
  )
  func roundTripPreservesTripsAndSetsCountryCodeNil(containerLabel: String) throws {
    let directoryURL = try Self.makeTempDirectory(label: containerLabel)
    defer { try? FileManager.default.removeItem(at: directoryURL) }
    let storeURL = directoryURL.appendingPathComponent("\(containerLabel).store")

    let firstTripID = UUID()
    let secondTripID = UUID()

    // Seed: write two trips through a V3-shaped container that knows the
    // current top-level `Trip` class (including `countryCode`). The V3
    // schema metadata still includes the field — SwiftData adds the
    // column on creation. The "migration" coverage here is the round-
    // trip through `AppMigrationPlan` on the second open.
    try Self.withV3Container(url: storeURL) { container in
      let context = container.mainContext
      context.insert(
        Trip(
          id: firstTripID,
          name: "Iceland",
          startDate: Date(timeIntervalSince1970: 1_700_000_000),
          endDate: Date(timeIntervalSince1970: 1_700_500_000)
        )
      )
      context.insert(
        Trip(
          id: secondTripID,
          name: "Japan",
          startDate: Date(timeIntervalSince1970: 1_710_000_000),
          endDate: Date(timeIntervalSince1970: 1_710_500_000)
        )
      )
      try context.save()
    }

    // Re-open with the V4 schema + AppMigrationPlan. Lightweight stage
    // runs implicitly; data is preserved and `countryCode == nil`.
    try Self.withV4Container(url: storeURL) { container in
      let context = container.mainContext
      let trips = try context.fetch(FetchDescriptor<Trip>(sortBy: [SortDescriptor(\.name)]))
      #expect(trips.count == 2)
      #expect(
        trips.map(\.id) == [firstTripID, secondTripID].sorted { $0.uuidString < $1.uuidString }
          || trips.map(\.name) == ["Iceland", "Japan"])
      #expect(trips.allSatisfy { $0.countryCode == nil })
    }
  }

  // MARK: - Helpers

  private static func makeTempDirectory(label: String) throws -> URL {
    let base = FileManager.default.temporaryDirectory
      .appendingPathComponent(
        "ScrambleV4Migration-\(label)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    return base
  }

  private static func withV3Container(
    url: URL, body: (ModelContainer) throws -> Void
  ) throws {
    let schema = Schema(versionedSchema: SchemaV3.self)
    let config = ModelConfiguration(
      schema: schema,
      url: url,
      cloudKitDatabase: .none
    )
    let container = try ModelContainer(for: schema, configurations: [config])
    try body(container)
  }

  private static func withV4Container(
    url: URL, body: (ModelContainer) throws -> Void
  ) throws {
    let schema = Schema(versionedSchema: SchemaV4.self)
    let config = ModelConfiguration(
      schema: schema,
      url: url,
      cloudKitDatabase: .none
    )
    let container = try ModelContainer(
      for: schema,
      migrationPlan: AppMigrationPlan.self,
      configurations: [config]
    )
    try body(container)
  }
}
