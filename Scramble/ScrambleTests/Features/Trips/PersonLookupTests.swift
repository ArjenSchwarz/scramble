import Foundation
import SwiftData
import Testing

@testable import Scramble

@Suite("PersonLookup.person(for:in:)")
@MainActor
struct PersonLookupTests {

  private static func makeGlobalsContainer() throws -> ModelContainer {
    let schema = Schema(versionedSchema: SchemaV3.self)
    let config = ModelConfiguration(
      schema: schema,
      isStoredInMemoryOnly: true,
      cloudKitDatabase: .none
    )
    return try ModelContainer(for: schema, configurations: [config])
  }

  @Test("returns the Person whose id matches the supplied UUID")
  func resolvesExistingPerson() throws {
    let container = try Self.makeGlobalsContainer()
    let context = container.mainContext

    let person = Person(name: "Arjen", colorKey: "blue")
    context.insert(person)
    try context.save()

    let resolved = PersonLookup.person(for: person.id, in: context)
    #expect(resolved?.id == person.id)
    #expect(resolved?.name == "Arjen")
  }

  @Test("returns nil for a UUID not present in the globals context")
  func returnsNilForMissingPerson() throws {
    let container = try Self.makeGlobalsContainer()
    let context = container.mainContext

    let other = Person(name: "Other", colorKey: "red")
    context.insert(other)
    try context.save()

    let unknown = UUID()
    let resolved = PersonLookup.person(for: unknown, in: context)
    #expect(resolved == nil)
  }

  @Test("does not mutate the supplied context")
  func hasNoSideEffectsOnContext() throws {
    let container = try Self.makeGlobalsContainer()
    let context = container.mainContext

    let person = Person(name: "Arjen", colorKey: "blue")
    context.insert(person)
    try context.save()

    #expect(context.hasChanges == false)
    _ = PersonLookup.person(for: person.id, in: context)
    _ = PersonLookup.person(for: UUID(), in: context)
    #expect(context.hasChanges == false)
  }
}
