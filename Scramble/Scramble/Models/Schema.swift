import Foundation
import SwiftData
import os

// MARK: - SchemaV1 (pre-Phase-3, frozen)

/// Pre-Phase-3 shape. `SchemaV1.TripTask` is frozen here so the migration into
/// `SchemaV2` is a real SwiftData diff (lightweight stage) rather than a
/// metadata-identical no-op.
nonisolated enum SchemaV1: VersionedSchema {
  nonisolated static var versionIdentifier: Schema.Version {
    Schema.Version(1, 0, 0)
  }

  nonisolated static var models: [any PersistentModel.Type] {
    [
      Trip.self,
      Person.self,
      MasterTaskItem.self,
      MasterPackingItem.self,
      SchemaV1.TripTask.self,
      TripPackingItem.self,
      // V3 introduces TripPersonSnapshot but the top-level `Trip` and
      // `TripPackingItem` classes (shared across all schema versions)
      // hold relationships to it. SwiftData crashes during schema
      // construction if a referenced @Model isn't listed in the
      // schema's `models` array. Pre-V3 stores leave the
      // `TripPersonSnapshot` table empty.
      SchemaV3.TripPersonSnapshot.self,
    ]
  }

  @Model
  final class TripTask {
    var id: UUID = UUID()
    @Relationship var trip: Trip?
    var masterItemID: UUID?
    var name: String = ""
    var phaseRaw: String = Phase.weeksBefore.rawValue
    var isCompleted: Bool = false
    var sourceRaw: String = ItemSource.manual.rawValue
    var currentlyMatchesRules: Bool = true
    var pinnedByUser: Bool = false

    init() {}
  }
}

// MARK: - SchemaV2 (Phase 3 — adds assigneePersonID and userDeletedOnThisTrip)

/// Phase 3 schema. `assigneePersonID` (Req 9.1, Decision 9) and
/// `userDeletedOnThisTripRaw` (Req 9.1, Decision 7) were the original V2
/// additions; the SwiftData lightweight diff between V1 and V2 still relies
/// on `SchemaV1.TripTask` being a frozen separate class. From V2 onwards the
/// `TripTask` class is the single top-level definition shared across V2 and
/// V3 — having two `@Model` types named `"TripTask"` (`SchemaV2.TripTask`
/// alongside `SchemaV3.TripTask`) coexist in the same test process panics
/// SwiftData's cascade traversal on iOS 26.4, so `ckRecordSystemFields` is
/// added to the same class instead of a forked V3 variant. The V2 → V3
/// lightweight diff for `TripTask` becomes a metadata-identical no-op;
/// SwiftData adds the column on first open via Core Data's automatic
/// inference because it is `Optional` with a `nil` default.
nonisolated enum SchemaV2: VersionedSchema {
  nonisolated static var versionIdentifier: Schema.Version {
    Schema.Version(2, 0, 0)
  }

  nonisolated static var models: [any PersistentModel.Type] {
    [
      Trip.self,
      Person.self,
      MasterTaskItem.self,
      MasterPackingItem.self,
      TripTask.self,
      TripPackingItem.self,
      SchemaV3.TripPersonSnapshot.self,
    ]
  }
}

// MARK: - SchemaV3 (Phase 5 — CloudKit sharing additions)

/// Phase 5 schema. Adds the per-trip person snapshot, trip-zone state, and
/// migration journal entities introduced for CloudKit sharing (Decision 7,
/// Decision 10, Decision 13). The trip-owned classes (`Trip`, `TripTask`,
/// `TripPackingItem`) are top-level and shared across V2 and V3 — see
/// `SchemaV2`'s declaration for why the additive V3 fields are not put on
/// forked subclasses.
nonisolated enum SchemaV3: VersionedSchema {
  nonisolated static var versionIdentifier: Schema.Version {
    Schema.Version(3, 0, 0)
  }

  nonisolated static var models: [any PersistentModel.Type] {
    [
      Trip.self,
      Person.self,
      MasterTaskItem.self,
      MasterPackingItem.self,
      TripTask.self,
      TripPackingItem.self,
      SchemaV3.TripPersonSnapshot.self,
      SchemaV3.TripZoneState.self,
      SchemaV3.MigrationJournalEntry.self,
    ]
  }

  /// V3 — denormalised per-trip identity for a `Person` who participates in
  /// the trip. Lives inside the trip zone so participants render the trip
  /// without consulting the owner's `Person` registry (Decision 7).
  ///
  /// `personID` is the owner-side `Person.id`; opaque to participants.
  /// `isRosterMember` flips false when the person is removed from the trip
  /// roster — the snapshot remains until every `TripPackingItem` referencing
  /// it has been removed (Req 2.4).
  @Model
  final class TripPersonSnapshot {
    var id: UUID = UUID()
    var personID: UUID = UUID()
    var name: String = ""
    var colourID: String = ""
    var initialSource: String = ""
    var isRosterMember: Bool = true

    /// One-way reference back to the owning trip. The inverse on
    /// `Trip.participantSnapshots` is intentionally unpaired (see Trip's
    /// declaration) because SwiftData's cascade-traversal panics on iOS
    /// 26.4 when the trip-deletion path reaches the snapshot ↔
    /// packing-item nullify chain. Maintaining trip ↔ snapshot
    /// consistency on both sides is the writer's responsibility.
    @Relationship var trip: Trip?

    var ckRecordSystemFields: Data?

    init(
      id: UUID = UUID(),
      personID: UUID = UUID(),
      name: String = "",
      colourID: String = "",
      initialSource: String = "",
      isRosterMember: Bool = true,
      trip: Trip? = nil
    ) {
      self.id = id
      self.personID = personID
      self.name = name
      self.colourID = colourID
      self.initialSource = initialSource
      self.isRosterMember = isRosterMember
      self.trip = trip
    }
  }

  /// V3 — per-trip CloudKit zone state. Tracks which records are dirty
  /// for the next `CKSyncEngine.sendChanges()` and which zone scope this
  /// trip lives in. `tripID` matches the corresponding `Trip.tripZoneID`
  /// (Decision 13).
  @Model
  final class TripZoneState {
    var tripID: UUID = UUID()
    var zoneOwnerName: String = ""
    var zoneScope: String = ""
    var shareID: String?
    var pendingUploadFlags: Data = Data()
    var ckRecordSystemFields: Data?

    init(
      tripID: UUID = UUID(),
      zoneOwnerName: String = "",
      zoneScope: String = "",
      shareID: String? = nil,
      pendingUploadFlags: Data = Data()
    ) {
      self.tripID = tripID
      self.zoneOwnerName = zoneOwnerName
      self.zoneScope = zoneScope
      self.shareID = shareID
      self.pendingUploadFlags = pendingUploadFlags
    }
  }

  /// V3 — journal of in-progress and completed Stage B (per-trip zone)
  /// migrations. Read on launch to resume `.stageBInProgress` rows;
  /// preserved as audit data after `.completed` (Decision 10).
  ///
  /// Completion correlation (design § "Stage B"): a trip's entry is
  /// `.completed` when (a) every expected record ID has appeared in
  /// cumulative `sentRecordNames`, AND (b) `zoneSaved == true`. The
  /// expected/sent fields are JSON-encoded `Set<String>` blobs so the
  /// columns stay Optional (Core Data 1570 rule on iOS 26.4).
  @Model
  final class MigrationJournalEntry {
    var tripID: UUID = UUID()
    var stateRaw: String = ""
    var errorMessage: String?
    var updatedAt: Date = Date.distantPast

    /// JSON-encoded `Set<String>` of record names expected to upload for
    /// this trip's zone migration. Captured at Stage B start so resume
    /// can re-evaluate completion against a stable set.
    var expectedRecordNamesData: Data?

    /// JSON-encoded `Set<String>` of record names confirmed sent across
    /// `sentRecordZoneChanges` events. Grows monotonically until
    /// matches `expectedRecordNames`.
    var sentRecordNamesData: Data?

    /// Whether the zone-save event for this trip's zone succeeded.
    /// Stored as Optional `Bool` so SwiftData's automatic column
    /// inference can add the column to V2-era stores at first V3 open
    /// without tripping the Core Data 1570 validation path.
    var zoneSavedFlag: Bool?

    init(
      tripID: UUID = UUID(),
      stateRaw: String = "",
      errorMessage: String? = nil,
      updatedAt: Date = .distantPast,
      expectedRecordNamesData: Data? = nil,
      sentRecordNamesData: Data? = nil,
      zoneSavedFlag: Bool? = nil
    ) {
      self.tripID = tripID
      self.stateRaw = stateRaw
      self.errorMessage = errorMessage
      self.updatedAt = updatedAt
      self.expectedRecordNamesData = expectedRecordNamesData
      self.sentRecordNamesData = sentRecordNamesData
      self.zoneSavedFlag = zoneSavedFlag
    }
  }
}

// MARK: - MigrationJournalEntry bridges

/// Stage B lifecycle states stored in `MigrationJournalEntry.stateRaw`.
/// `.pending` means the trip has been queued for Stage B but the
/// coordinator has not yet started the upload; `MigrationGate` blocks the
/// UI while any entry is in this state. The other three are terminal or
/// in-progress states the coordinator transitions through.
enum MigrationStageState: String, Sendable {
  case pending
  case stageBInProgress
  case completed
  case failed
}

extension MigrationJournalEntry {
  var state: MigrationStageState {
    get { MigrationStageState(rawValue: stateRaw) ?? .pending }
    set { stateRaw = newValue.rawValue }
  }

  var expectedRecordNames: Set<String> {
    get {
      guard let data = expectedRecordNamesData, !data.isEmpty else { return [] }
      return (try? JSONDecoder().decode(Set<String>.self, from: data)) ?? []
    }
    set {
      expectedRecordNamesData = (try? JSONEncoder().encode(newValue)) ?? Data()
    }
  }

  var sentRecordNames: Set<String> {
    get {
      guard let data = sentRecordNamesData, !data.isEmpty else { return [] }
      return (try? JSONDecoder().decode(Set<String>.self, from: data)) ?? []
    }
    set {
      sentRecordNamesData = (try? JSONEncoder().encode(newValue)) ?? Data()
    }
  }

  var zoneSaved: Bool {
    get { zoneSavedFlag ?? false }
    set { zoneSavedFlag = newValue }
  }

  /// True when every expected record name has been confirmed sent AND the
  /// zone-save event has succeeded — the design's completion correlation.
  var isStageBComplete: Bool {
    zoneSaved && !expectedRecordNames.isEmpty
      && expectedRecordNames.isSubset(of: sentRecordNames)
  }
}

// MARK: - Top-level current types

/// `TripTask` is a single top-level `@Model` shared by `SchemaV2` and
/// `SchemaV3`. Forking the class per schema version is the persistence-note
/// pattern, but having two `@Model` types with the same simple name in one
/// test process panics SwiftData's cascade traversal on iOS 26.4 (only
/// surfaces in suite mode; isolated tests pass). The `ckRecordSystemFields`
/// field added in V3 is `Optional` with `nil` default, so SwiftData's
/// automatic column inference adds it to V2-era stores at first V3 open.
@Model
final class TripTask {
  var id: UUID = UUID()
  @Relationship var trip: Trip?
  var masterItemID: UUID?
  var name: String = ""
  var phaseRaw: String = Phase.weeksBefore.rawValue
  var isCompleted: Bool = false
  var sourceRaw: String = ItemSource.manual.rawValue
  var currentlyMatchesRules: Bool = true
  var pinnedByUser: Bool = false
  /// Decision 9 — value reference, dangling references tolerated.
  var assigneePersonID: UUID?
  /// Decision 7 — set by Phase 3 delete affordance; never set by the engine.
  ///
  /// Stored as `Bool?` so SwiftData's lightweight migration can backfill old
  /// records with a NULL column without tripping the Core Data validation
  /// path (`Code=1570 ... is a required value`). The public API on the model
  /// remains non-Optional via the `userDeletedOnThisTrip` computed bridge
  /// below, which treats `nil` as `false`. The storage default is `nil`,
  /// not `false`, because SwiftData/CoreData on iOS 26.4 asserts when a
  /// nullable column also declares a non-nil Swift default. `private(set)`
  /// keeps the bridge as the single mutation path; SwiftData still
  /// observes writes from inside the `userDeletedOnThisTrip` setter.
  private(set) var userDeletedOnThisTripRaw: Bool?

  /// V3 — cached `CKRecord` system fields so writes preserve
  /// serverChangeTag / share state across saves.
  var ckRecordSystemFields: Data?

  init(
    id: UUID = UUID(),
    trip: Trip? = nil,
    masterItemID: UUID? = nil,
    name: String = "",
    phase: Phase = .weeksBefore,
    isCompleted: Bool = false,
    source: ItemSource = .manual,
    currentlyMatchesRules: Bool = true,
    pinnedByUser: Bool = false,
    assigneePersonID: UUID? = nil,
    userDeletedOnThisTrip: Bool = false
  ) {
    self.id = id
    self.trip = trip
    self.masterItemID = masterItemID
    self.name = name
    self.phaseRaw = phase.rawValue
    self.isCompleted = isCompleted
    self.sourceRaw = source.rawValue
    self.currentlyMatchesRules = currentlyMatchesRules
    self.pinnedByUser = pinnedByUser
    self.assigneePersonID = assigneePersonID
    self.userDeletedOnThisTripRaw = userDeletedOnThisTrip
  }
}

typealias TripPersonSnapshot = SchemaV3.TripPersonSnapshot
typealias TripZoneState = SchemaV3.TripZoneState
typealias MigrationJournalEntry = SchemaV3.MigrationJournalEntry

// MARK: - TripTask bridges

extension TripTask {
  var phase: Phase {
    get { Phase(rawValue: phaseRaw) ?? .weeksBefore }
    set { phaseRaw = newValue.rawValue }
  }

  var source: ItemSource {
    get { ItemSource(rawValue: sourceRaw) ?? .manual }
    set { sourceRaw = newValue.rawValue }
  }

  /// Non-Optional bridge over `userDeletedOnThisTripRaw`. See the storage
  /// declaration on `TripTask` for why the underlying column is nullable;
  /// callers should treat this property as the canonical surface.
  var userDeletedOnThisTrip: Bool {
    get { userDeletedOnThisTripRaw ?? false }
    set { userDeletedOnThisTripRaw = newValue }
  }
}

// MARK: - Migration plan

nonisolated enum AppMigrationPlan: SchemaMigrationPlan {
  nonisolated static var schemas: [any VersionedSchema.Type] {
    [SchemaV1.self, SchemaV2.self, SchemaV3.self]
  }

  nonisolated static var stages: [MigrationStage] {
    [
      // V1 → V2: lightweight column additions only
      // (`assigneePersonID`, `userDeletedOnThisTripRaw`).
      .lightweight(fromVersion: SchemaV1.self, toVersion: SchemaV2.self),
      // V2 → V3: lightweight schema diff is metadata-identical for the
      // shared top-level entities; SwiftData adds the new
      // `ckRecordSystemFields` columns on first open via automatic
      // inference (every new V3 column is `Optional` with `nil`
      // default). The custom `didMigrate` step then backfills
      // `TripPersonSnapshot` rows from existing `Person` references and
      // wires `TripPackingItem.personSnapshot`. Custom is required
      // because the backfill reads V2 trip-roster relationships and
      // writes V3 snapshot rows in a single transaction. Offline-safe —
      // no CloudKit calls; runs unconditionally even when signed out.
      .custom(
        fromVersion: SchemaV2.self,
        toVersion: SchemaV3.self,
        willMigrate: nil,
        didMigrate: { context in
          try SchemaV3MigrationStage.backfillSnapshots(in: context)
        }
      ),
    ]
  }
}

// MARK: - Logger

nonisolated let modelLogger = Logger(
  subsystem: "me.nore.ig.Scramble",
  category: "models"
)
