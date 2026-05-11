import Foundation
import SwiftData
import Testing

@testable import Scramble

/// Pure-function coverage for the AC 9.7 / Decision 16 person-delete guard.
/// `PersonDeleteBlocker.make` is the authoritative gate (SwiftData's `.deny`
/// rule does not throw on iOS 26), so these tests pin its behaviour without
/// instantiating a `ModelContainer` or driving the editor UI.
@MainActor
@Suite("PersonDeleteBlocker.make")
struct PersonDeleteBlockerTests {

  @Test("no references → nil (delete is allowed)")
  func noReferencesReturnsNil() {
    let person = Person(name: "Solo", colorKey: "cyan")
    let blocker = PersonDeleteBlocker.make(
      for: person,
      tripPacking: [],
      masterPacking: []
    )
    #expect(blocker == nil)
  }

  @Test("trip-packing reference blocks delete and surfaces trip name")
  func tripPackingBlocks() throws {
    let person = Person(name: "Arjen", colorKey: "cyan")
    let trip = Trip(name: "Italy 2026", startDate: .now, endDate: .now)
    let item = TripPackingItem(trip: trip, person: person, name: "Passport")
    let blocker = PersonDeleteBlocker.make(
      for: person,
      tripPacking: [item],
      masterPacking: []
    )
    let unwrapped = try #require(blocker)
    #expect(unwrapped.personName == "Arjen")
    #expect(unwrapped.referencingTripNames == ["Italy 2026"])
    #expect(unwrapped.referencingMasterItemNames.isEmpty)
  }

  @Test("master-packing reference blocks delete and surfaces item name")
  func masterPackingBlocks() throws {
    let person = Person(name: "Kelsey", colorKey: "pink")
    let master = MasterPackingItem(name: "Toothbrush", person: person)
    let blocker = PersonDeleteBlocker.make(
      for: person,
      tripPacking: [],
      masterPacking: [master]
    )
    let unwrapped = try #require(blocker)
    #expect(unwrapped.personName == "Kelsey")
    #expect(unwrapped.referencingTripNames.isEmpty)
    #expect(unwrapped.referencingMasterItemNames == ["Toothbrush"])
  }

  @Test("duplicate trip references collapse and sort alphabetically")
  func duplicateTripsAreUnique() throws {
    let person = Person(name: "Pacifica", colorKey: "green")
    let tripA = Trip(name: "Iceland", startDate: .now, endDate: .now)
    let tripB = Trip(name: "Belgium", startDate: .now, endDate: .now)
    let packA = TripPackingItem(trip: tripA, person: person, name: "Coat")
    let packB = TripPackingItem(trip: tripA, person: person, name: "Boots")
    let packC = TripPackingItem(trip: tripB, person: person, name: "Hat")
    let blocker = PersonDeleteBlocker.make(
      for: person,
      tripPacking: [packA, packB, packC],
      masterPacking: []
    )
    let unwrapped = try #require(blocker)
    #expect(unwrapped.referencingTripNames == ["Belgium", "Iceland"])
  }

  @Test("anonymous person falls back to placeholder name")
  func anonymousPersonPlaceholder() throws {
    let person = Person(name: "", colorKey: "yellow")
    let master = MasterPackingItem(name: "Sunglasses", person: person)
    let blocker = PersonDeleteBlocker.make(
      for: person,
      tripPacking: [],
      masterPacking: [master]
    )
    let unwrapped = try #require(blocker)
    #expect(unwrapped.personName == "This person")
  }

  @Test("untitled trip and unnamed item names get placeholders")
  func emptyNamesGetPlaceholders() throws {
    let person = Person(name: "Alex", colorKey: "blue")
    let trip = Trip(name: "", startDate: .now, endDate: .now)
    let pack = TripPackingItem(trip: trip, person: person, name: "Camera")
    let master = MasterPackingItem(name: "", person: person)
    let blocker = PersonDeleteBlocker.make(
      for: person,
      tripPacking: [pack],
      masterPacking: [master]
    )
    let unwrapped = try #require(blocker)
    #expect(unwrapped.referencingTripNames == ["Untitled trip"])
    #expect(unwrapped.referencingMasterItemNames == ["Unnamed item"])
  }

  @Test("blocker message lists every referenced surface")
  func blockerMessageIncludesAllSources() throws {
    let person = Person(name: "Arjen", colorKey: "cyan")
    let trip = Trip(name: "Italy 2026", startDate: .now, endDate: .now)
    let tripPack = TripPackingItem(trip: trip, person: person, name: "Passport")
    let masterPack = MasterPackingItem(name: "Toothbrush", person: person)
    let blocker = try #require(
      PersonDeleteBlocker.make(
        for: person,
        tripPacking: [tripPack],
        masterPacking: [masterPack]
      )
    )
    let message = blocker.message
    #expect(message.contains("Arjen"))
    #expect(message.contains("Italy 2026"))
    #expect(message.contains("Toothbrush"))
    #expect(message.contains("Remove the references"))
  }
}
