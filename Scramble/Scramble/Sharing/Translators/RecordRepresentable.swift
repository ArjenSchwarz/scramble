import CloudKit
import Foundation
import SwiftData

/// Phase 5 translator contract — maps a `tripsLocal` `@Model` to/from a
/// `CKRecord`. One translator per entity (Decision 13 design § "@Model ↔
/// CKRecord translation"). Implementations live in
/// `Sharing/Translators/`.
///
/// Translator rules (uniform across every entity):
///
/// - Relationships and snapshot references are stored as UUID-valued
///   record fields, **not** `CKRecord.Reference`. A `TripPackingItem`'s
///   `personSnapshotID` is encoded as `personSnapshotID: String` on the
///   `CKRecord`; the bare ID is stored back on decode (dangling references
///   tolerated). This avoids cross-record dependency ordering inside
///   `CKSyncEngine` batches.
/// - System fields are preserved on every write. `existing: CKRecord?` is
///   constructed by decoding the entity's `ckRecordSystemFields` blob via
///   `CKRecord(coder:)`. After every send/fetch, the translator re-encodes
///   system fields back into the entity.
/// - Codable blob fields (`TripAttributes`, `ItemConditions`) are encoded
///   with `JSONEncoder` into `Data` fields on the record. Hard size cap of
///   256 KB per blob — exceeded blobs throw a translator error and surface
///   as a save failure.
/// - Enum-valued fields continue to use the Phase 1 raw-string convention
///   (`stateRaw`, `phaseRaw`, etc.).
/// - Optional → Optional maps directly. Non-Optional Swift fields with no
///   record value (e.g., default-only fields added in V3 against a
///   `CKRecord` written by an older client) decode to the Swift default.
@MainActor
protocol RecordRepresentable {
  static var recordType: String { get }

  /// CloudKit record identifier for the model. Composed from the model's
  /// `id` and the trip's zone (resolved through the translator's wrapper
  /// when not directly stored on the entity).
  func recordID(in zoneID: CKRecordZone.ID) -> CKRecord.ID

  /// Encode the entity into a `CKRecord`. When `existing` is supplied, the
  /// new record is built on top of it so server change tags / sharing
  /// metadata roundtrip correctly. Throws `TranslatorError.blobTooLarge`
  /// when a Codable blob field exceeds the 256 KB cap.
  func toRecord(in zoneID: CKRecordZone.ID, existing: CKRecord?) throws -> CKRecord

  /// Apply a fetched record to the local `tripsLocal` store. Inserts a
  /// new entity when no matching row exists, or merges fields into the
  /// existing row using last-writer-wins per attribute. Re-encodes the
  /// record's system fields back into the entity's
  /// `ckRecordSystemFields` blob.
  static func from(_ record: CKRecord, into context: ModelContext) throws
}

/// Errors raised by translator implementations.
enum TranslatorError: Error, Equatable {
  /// A Codable blob field exceeded the 256 KB size cap.
  case blobTooLarge(field: String, size: Int)
  /// The fetched record's `recordType` did not match the translator's
  /// declared type.
  case recordTypeMismatch(expected: String, actual: String)
  /// A required UUID-valued relationship field was missing from the
  /// fetched record. Translators tolerate optional relationships gracefully
  /// but raise this when the field is required by the entity's
  /// non-Optional Swift model.
  case missingRequiredRelationship(field: String)
}

/// Maximum size (in bytes) of any Codable blob field encoded onto a
/// `CKRecord`. Larger payloads throw `TranslatorError.blobTooLarge`.
let kRecordBlobSizeCap: Int = 256 * 1024
