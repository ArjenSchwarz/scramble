import CloudKit
import Foundation
import SwiftData
import Testing
import UserNotifications

@testable import Scramble

/// Phase 6 — `NotificationsService` integration coverage (Reqs 1.6, 3.1,
/// 3.3, 3.4, 3.6, 4.1, 4.2, 4.3, 4.4, 4.5).
///
/// The service is exercised end-to-end against a `StubNotificationCenter`
/// recording every call. `tripContext` is an in-memory SwiftData
/// container so `Trip` rows can be inserted/deleted realistically.
/// `coalesceWindow` is overridden to 100 ms so the tests don't wait the
/// production 2 s window.
@Suite("NotificationsService", .serialized)
@MainActor
struct NotificationsServiceTests {

  // MARK: - Auth gate on insert (Req 3.1, 3.3)

  @Test("Insert + notDetermined + future eligible phases → requestAuthorization is called")
  func authPromptedOnEligibleInsert() async throws {
    let setup = try makeSetup()
    setup.stub.stubbedAuthorizationStatus = .notDetermined
    setup.stub.authorizationGrantResult = true

    let trip = Self.makeTrip()
    setup.context.insert(trip)
    try setup.context.save()

    await setup.service.requestAuthorizationIfNeeded(forTrip: trip)

    #expect(setup.stub.snapshot.requestedAuthorization == [[.alert, .sound]])
    #expect(setup.service.authStatus == .authorized)
    // Reconcile ran — pending list now reflects the trip.
    #expect(!setup.stub.pending.isEmpty)
  }

  @Test("Insert + notDetermined + no eligible phases → no auth prompt")
  func authNotPromptedWhenNoEligiblePlans() async throws {
    let setup = try makeSetup()
    setup.stub.stubbedAuthorizationStatus = .notDetermined
    let now = Self.now
    let pastStart = setup.calendar.date(byAdding: .day, value: -10, to: now)!
    let pastEnd = setup.calendar.date(byAdding: .day, value: -5, to: now)!
    let trip = Trip(name: "Past", startDate: pastStart, endDate: pastEnd)
    setup.context.insert(trip)
    try setup.context.save()

    await setup.service.requestAuthorizationIfNeeded(forTrip: trip)
    #expect(setup.stub.snapshot.requestedAuthorization.isEmpty)
  }

  @Test("Insert + denied → no auth prompt re-attempt (Req 3.4)")
  func deniedSkipsRePrompt() async throws {
    let setup = try makeSetup()
    setup.stub.stubbedAuthorizationStatus = .denied
    let trip = Self.makeTrip()
    setup.context.insert(trip)
    try setup.context.save()

    await setup.service.requestAuthorizationIfNeeded(forTrip: trip)
    #expect(setup.stub.snapshot.requestedAuthorization.isEmpty)
  }

  // MARK: - Coalesce window (Req 4.3)

  @Test("Two .localWrite calls inside the window collapse into a single reconcile")
  func coalesceCollapsesBursts() async throws {
    let setup = try makeSetup()
    setup.stub.stubbedAuthorizationStatus = .authorized
    let trip = Self.makeTrip()
    setup.context.insert(trip)
    try setup.context.save()

    setup.service.requestReschedule(reason: .localWrite)
    setup.service.requestReschedule(reason: .localWrite)
    // Wait past the coalesce window.
    try await Task.sleep(for: .milliseconds(200))

    // Only one pendingListReads from the reconcile.
    #expect(setup.stub.snapshot.pendingListReads == 1)
  }

  // MARK: - Immediate-flush reasons bypass coalesce

  @Test(".tripDeleted is immediate (cancels pending + removes delivered)")
  func tripDeletedIsImmediate() async throws {
    let setup = try makeSetup()
    setup.stub.stubbedAuthorizationStatus = .authorized
    let trip = Self.makeTrip()
    setup.context.insert(trip)
    try setup.context.save()

    // Schedule first.
    setup.service.requestReschedule(reason: .appActivation)
    // Let appActivation reconcile run.
    try await Task.sleep(for: .milliseconds(50))
    #expect(!setup.stub.pending.isEmpty)
    let preDeleteCount = setup.stub.pending.count

    setup.service.requestReschedule(reason: .tripDeleted(tripID: trip.id))
    try await Task.sleep(for: .milliseconds(50))

    // Removes for that trip's identifiers fired immediately.
    let removed = setup.stub.snapshot.removedPending.flatMap { $0 }
    let removedForTrip = removed.filter { identifier in
      NotificationIdentifier.parse(identifier)?.tripID == trip.id
    }
    #expect(removedForTrip.count >= preDeleteCount)
  }

  // MARK: - Auth flip on foreground (Req 3.6 / Decision 10)

  @Test("denied → authorized on .active flip runs a backfill reconcile")
  func deniedToAuthorizedTriggersBackfill() async throws {
    let setup = try makeSetup()
    setup.stub.stubbedAuthorizationStatus = .denied
    await setup.service.start()
    let trip = Self.makeTrip()
    setup.context.insert(trip)
    try setup.context.save()

    // Become authorized in iOS Settings; user returns to foreground.
    setup.stub.stubbedAuthorizationStatus = .authorized
    await setup.service.handleScenePhase(.becameActive)

    #expect(setup.service.authStatus == .authorized)
    #expect(!setup.stub.pending.isEmpty, "Backfill should have populated pending requests")
  }

  // MARK: - Authorized → denied cancels pending (Req 3.4 / 3.6)

  @Test("authorized → denied on foreground re-read cancels all activation notifications")
  func authorizedToDeniedCancelsAll() async throws {
    let setup = try makeSetup()
    setup.stub.stubbedAuthorizationStatus = .authorized
    await setup.service.start()
    let trip = Self.makeTrip()
    setup.context.insert(trip)
    try setup.context.save()

    setup.service.requestReschedule(reason: .appActivation)
    try await Task.sleep(for: .milliseconds(50))
    #expect(!setup.stub.pending.isEmpty)

    setup.stub.stubbedAuthorizationStatus = .denied
    await setup.service.handleScenePhase(.becameActive)

    #expect(setup.stub.pending.isEmpty)
    #expect(setup.service.authStatus == .denied)
  }

  // MARK: - No-op detection (Req 2.3 via reconciler)

  @Test("Identical reconcile twice does not re-add identical requests")
  func identicalReconcileIsNoOp() async throws {
    let setup = try makeSetup()
    setup.stub.stubbedAuthorizationStatus = .authorized
    let trip = Self.makeTrip()
    setup.context.insert(trip)
    try setup.context.save()

    setup.service.requestReschedule(reason: .appActivation)
    try await Task.sleep(for: .milliseconds(50))
    let firstAddCount = setup.stub.snapshot.added.count
    #expect(firstAddCount > 0)

    setup.service.requestReschedule(reason: .appActivation)
    try await Task.sleep(for: .milliseconds(50))
    // No new adds — body matches.
    #expect(setup.stub.snapshot.added.count == firstAddCount)
  }

  // MARK: - Helpers

  struct Setup {
    // Retain the container; a `ModelContext` does not keep its
    // `ModelContainer` alive, so dropping it crashes the test host.
    let container: ModelContainer
    let stub: StubNotificationCenter
    let service: NotificationsService
    let context: ModelContext
    let calendar: Calendar
  }

  /// Pinned "now" so the test trips activate in the future deterministically.
  static let now: Date = {
    var comps = DateComponents()
    comps.year = 2026
    comps.month = 6
    comps.day = 1
    comps.timeZone = TimeZone(secondsFromGMT: 0)
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
    return cal.date(from: comps) ?? Date.distantPast
  }()

  static func makeTrip() -> Trip {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
    let start = cal.date(byAdding: .day, value: 30, to: now)!
    let end = cal.date(byAdding: .day, value: 35, to: now)!
    return Trip(name: "T", startDate: start, endDate: end)
  }

  func makeSetup() throws -> Setup {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
    let schema = Schema(versionedSchema: SchemaV3.self)
    let config = ModelConfiguration(
      schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none
    )
    let container = try ModelContainer(for: schema, configurations: [config])
    let context = container.mainContext
    let stub = StubNotificationCenter()
    let now = Self.now
    let service = NotificationsService(
      center: stub,
      tripContext: { context },
      calendar: cal,
      now: { now },
      coalesceWindow: .milliseconds(100)
    )
    return Setup(
      container: container, stub: stub, service: service, context: context, calendar: cal
    )
  }
}
