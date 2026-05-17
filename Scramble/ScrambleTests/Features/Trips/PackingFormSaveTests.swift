import Foundation
import SwiftData
import Testing

@testable import Scramble

// MARK: - Contract for Task 10
//
// These tests assume Task 10's `PackingItemForm` exposes the save logic as
// pure static helpers so it can be unit-tested without driving a `View` body.
// SwiftUI views are awkward to instantiate from Swift Testing, and the save
// semantics (per `specs/phase-4-packing-sheet/design.md` §"PackingItemForm")
// are well-defined enough to live in helpers the form's body delegates to.
//
// Required API surface for Task 10:
//
//   extension PackingItemForm {
//     static func performAdd(
//       name: String,
//       person: Person,
//       trip: Trip,
//       context: ModelContext
//     ) throws -> TripPackingItem
//
//     static func performEdit(
//       item: TripPackingItem,
//       name: String,
//       context: ModelContext
//     ) throws
//
//     static func isSubmitEnabled(_ name: String) -> Bool
//     static func cappedName(_ input: String) -> String
//   }
//
// Save semantics implemented by these helpers (per design):
//
//   .add  → insert TripPackingItem(source: .manual, state: .unpacked,
//           currentlyMatchesRules: true, pinnedByUser: false,
//           masterItemID: nil, name: trimmed, person:, trip:); save throws
//           propagate, item is removed from context on failure.
//   .edit → mutate item.name = trimmed; save throws propagate AND
//           context.rollback() is invoked to restore the prior name.
//
// `cappedName` enforces the 200-character cap (Req 5.5).
// `isSubmitEnabled` returns false on whitespace-only/empty input (Req 5.4).
//
// If Task 10's implementer chooses a different API surface (e.g. instance
// methods on a view-model struct), these tests can be adjusted at
// implementation time — the *behaviour* under test is what matters, not the
// exact symbol names.

@Suite("PackingItemForm save semantics", .serialized)
@MainActor
struct PackingFormSaveTests {

  // MARK: - Container helper

  /// In-memory `ModelContainer`. Caller must retain the returned container in
  /// a local `let` for the duration of the test — SwiftData crashes if the
  /// container deallocates while a `ModelContext` is in use.
  private static func makeContainer() throws -> ModelContainer {
    let schema = Schema(versionedSchema: SchemaV3.self)
    let config = ModelConfiguration(
      schema: schema,
      isStoredInMemoryOnly: true,
      cloudKitDatabase: .none
    )
    return try ModelContainer(for: schema, configurations: [config])
  }

  /// Phase 5.1: the form's `performAdd` writes the V3 `personSnapshot`
  /// relationship by looking up the snapshot from
  /// `trip.participantSnapshots`. The seed therefore creates a snapshot
  /// on the trip instead of writing the deprecated V2 `participants`
  /// relationship.
  private static func seedTripWithPerson(in context: ModelContext) throws -> (Trip, Person) {
    let person = Person(name: "Arjen", colorKey: "blue")
    context.insert(person)
    let trip = Trip(name: "T", startDate: .now, endDate: .now)
    context.insert(trip)
    let snapshot = TripPersonSnapshot(
      personID: person.id,
      name: person.name,
      colourID: person.colorKey,
      initialSource: "name",
      isRosterMember: true,
      trip: trip
    )
    context.insert(snapshot)
    try context.save()
    return (trip, person)
  }

  // MARK: - Req 5.3 / 5.5 — .add inserts with documented field values

  @Test(".add inserts TripPackingItem with documented field values and trimmed name")
  func addInsertsWithDocumentedDefaults() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext
    let (trip, person) = try Self.seedTripWithPerson(in: context)

    let raw = "   Sunscreen   "
    let inserted = try PackingItemForm.performAdd(
      name: raw,
      person: person,
      trip: trip,
      context: context
    )

    #expect(inserted.name == "Sunscreen")
    #expect(inserted.source == .manual)
    #expect(inserted.state == .unpacked)
    #expect(inserted.currentlyMatchesRules == true)
    #expect(inserted.pinnedByUser == false)
    #expect(inserted.masterItemID == nil)
    // Phase 5.1: assignee identity is the V3 personSnapshot relationship.
    #expect(inserted.personSnapshot?.personID == person.id)
    #expect(inserted.trip?.id == trip.id)

    // Item is reachable from the trip's packing relationship.
    let onTrip = trip.packingItems ?? []
    #expect(onTrip.contains { $0.id == inserted.id })
  }

  @Test(".add with whitespace-only name is a programmer error — guarded by isSubmitEnabled")
  func addRejectsWhitespaceViaSubmitGuard() throws {
    // The form's Save button is disabled on whitespace-only input
    // (Req 5.4); `performAdd` itself does not need to re-validate. This test
    // documents the invariant: the gate is `isSubmitEnabled`, not
    // `performAdd`. We assert the gate here; behaviour of `performAdd`
    // when called with whitespace is undefined and not part of the contract.
    #expect(PackingItemForm.isSubmitEnabled("   ") == false)
    #expect(PackingItemForm.isSubmitEnabled("\n\t") == false)
    #expect(PackingItemForm.isSubmitEnabled("") == false)
  }

  // MARK: - Req 6.2 / 6.3 — .edit updates name only

  @Test(".edit updates name only; source / masterItemID / flags unchanged")
  func editUpdatesNameOnly() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext
    let (trip, person) = try Self.seedTripWithPerson(in: context)

    let originalMasterID = UUID()
    let item = TripPackingItem(
      trip: trip,
      person: person,
      masterItemID: originalMasterID,
      name: "Toothbrush",
      state: .packed,
      source: .rule,
      currentlyMatchesRules: true,
      pinnedByUser: true
    )
    context.insert(item)
    try context.save()

    try PackingItemForm.performEdit(
      item: item,
      name: "  Electric toothbrush  ",
      context: context
    )

    #expect(item.name == "Electric toothbrush")
    #expect(item.source == .rule)
    #expect(item.masterItemID == originalMasterID)
    #expect(item.currentlyMatchesRules == true)
    #expect(item.pinnedByUser == true)
    #expect(item.state == .packed)
    #expect(item.person?.id == person.id)
    #expect(item.trip?.id == trip.id)
  }

  @Test(".edit on a rule-driven item leaves masterItemID intact (Req 6.3)")
  func editPreservesMasterItemID() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext
    let (trip, person) = try Self.seedTripWithPerson(in: context)

    let masterID = UUID()
    let item = TripPackingItem(
      trip: trip,
      person: person,
      masterItemID: masterID,
      name: "Umbrella",
      source: .rule
    )
    context.insert(item)
    try context.save()

    try PackingItemForm.performEdit(item: item, name: "Big umbrella", context: context)

    #expect(item.masterItemID == masterID)
    #expect(item.source == .rule)
  }

  // MARK: - Req 8.4 — save-failure semantics

  @Test(
    ".add save failure: form retains entered name AND item is NOT inserted",
    .disabled(
      """
      Requires a save-failure injection seam on ModelContext (no public hook in \
      SwiftData). Re-enable when test infra exposes one — likely via a \
      protocol-based ModelContext wrapper introduced in Phase 5.
      """
    )
  )
  func addSaveFailureKeepsFormStateAndDoesNotInsert() throws {
    // Behavioural contract documented for Task 10:
    //   1. `try PackingItemForm.performAdd(…)` propagates the underlying
    //      SwiftData error to the caller (the form body).
    //   2. The form body's catch block:
    //        - logs `[PackingSheet.save-failed]` via `modelLogger.error`
    //        - leaves `name` state untouched (the user's typing survives)
    //        - surfaces an inline error string `"Couldn't save — try again."`
    //        - does NOT dismiss the sheet (differs from `TaskForm`)
    //   3. The would-be `TripPackingItem` is not present in the context's
    //      registered models (either never inserted, or inserted-then-deleted
    //      by `performAdd`'s catch).
    //
    // This is the contract Task 10 must satisfy. Once a SwiftData save-failure
    // injection seam exists, expand this test to cover all three points.
  }

  @Test(
    ".edit save failure: modelContext.rollback() invoked AND item.name restored",
    .disabled(
      """
      Requires a save-failure injection seam on ModelContext (no public hook in \
      SwiftData). Re-enable when test infra exposes one — likely via a \
      protocol-based ModelContext wrapper introduced in Phase 5.
      """
    )
  )
  func editSaveFailureRollsBackName() throws {
    // Behavioural contract documented for Task 10:
    //   1. `try PackingItemForm.performEdit(…)` mutates `item.name` to the
    //      trimmed input, then calls `try context.save()`. On throw the catch
    //      block calls `context.rollback()` and re-raises (or wraps) the
    //      error.
    //   2. After the throw, `item.name` is back to its pre-edit value because
    //      `rollback()` restores the in-memory `@Model` instance from the
    //      persistent store snapshot.
    //   3. The form body's catch leaves `name` state untouched, surfaces the
    //      inline error string, and does NOT dismiss the sheet.
    //
    // SwiftData does not auto-rollback uncommitted in-memory edits, which is
    // why the explicit `rollback()` call is part of the contract. Once a
    // save-failure injection seam exists, expand to assert
    //   #expect(item.name == originalName)
    // after the throw.
  }

  // MARK: - Req 5.4 — Submit disabled when trimmed name empty

  @Test("isSubmitEnabled returns false on whitespace-only or empty input")
  func isSubmitEnabledFalseOnEmpty() {
    #expect(PackingItemForm.isSubmitEnabled("") == false)
    #expect(PackingItemForm.isSubmitEnabled(" ") == false)
    #expect(PackingItemForm.isSubmitEnabled("    ") == false)
    #expect(PackingItemForm.isSubmitEnabled("\t\n") == false)
    #expect(PackingItemForm.isSubmitEnabled("\u{2003}\u{2003}") == false)  // em-spaces
  }

  @Test("isSubmitEnabled returns true on non-empty trimmed input")
  func isSubmitEnabledTrueOnContent() {
    #expect(PackingItemForm.isSubmitEnabled("a") == true)
    #expect(PackingItemForm.isSubmitEnabled(" a ") == true)
    #expect(PackingItemForm.isSubmitEnabled("Sunscreen") == true)
    #expect(PackingItemForm.isSubmitEnabled("   Toothbrush   ") == true)
  }

  // MARK: - Req 5.5 — 200-char cap enforced at input

  @Test("cappedName returns input unchanged when at or below 200 characters")
  func cappedNamePassesThroughShortInputs() {
    #expect(PackingItemForm.cappedName("") == "")
    #expect(PackingItemForm.cappedName("Sunscreen") == "Sunscreen")
    let exact = String(repeating: "a", count: 200)
    #expect(PackingItemForm.cappedName(exact) == exact)
    #expect(PackingItemForm.cappedName(exact).count == 200)
  }

  @Test("cappedName truncates input longer than 200 characters")
  func cappedNameTruncatesLongInputs() {
    let long = String(repeating: "x", count: 250)
    let capped = PackingItemForm.cappedName(long)
    #expect(capped.count == 200)
    #expect(capped == String(repeating: "x", count: 200))
  }

  @Test("cappedName preserves grapheme clusters at the boundary")
  func cappedNameRespectsGraphemeBoundary() {
    // 199 ASCII + a single multi-scalar emoji as the 200th grapheme. The cap
    // is by `String.prefix(200)` which counts graphemes, not UTF-16/UTF-8
    // units, so the emoji should survive intact.
    let prefix = String(repeating: "a", count: 199)
    let input = prefix + "👨‍👩‍👧"  // single grapheme cluster
    let capped = PackingItemForm.cappedName(input)
    #expect(capped.count == 200)
    #expect(capped.hasSuffix("👨‍👩‍👧"))
  }
}
