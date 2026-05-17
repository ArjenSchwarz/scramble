import Foundation

/// Codable representation of `TripZoneState.pendingUploadFlags`. Tracks
/// which records inside a trip's zone have unsaved local changes that
/// `TripSyncEngine` still needs to upload (Decision 13).
///
/// Backed by a `Set<String>` of record names (UUID strings) keyed off
/// `Trip.id`, `TripTask.id`, `TripPackingItem.id`, and
/// `TripPersonSnapshot.id`. The set form is denser than a bitset for the
/// expected per-trip record counts (low tens to low hundreds) and survives
/// renumbering as new entities are added.
nonisolated struct PendingUploadFlags: Codable, Equatable, Sendable {
  // Reused per call — every local save in the chokepoint round-trips
  // through these; per-call allocation is unnecessary churn.
  private static let encoder = JSONEncoder()
  private static let decoder = JSONDecoder()

  var dirtyRecordNames: Set<String>
  var deletedRecordNames: Set<String>

  init(
    dirtyRecordNames: Set<String> = [],
    deletedRecordNames: Set<String> = []
  ) {
    self.dirtyRecordNames = dirtyRecordNames
    self.deletedRecordNames = deletedRecordNames
  }

  /// Decode from raw `Data`. An empty buffer decodes to an empty value.
  static func decode(_ data: Data) -> PendingUploadFlags {
    guard !data.isEmpty else { return PendingUploadFlags() }
    return (try? decoder.decode(PendingUploadFlags.self, from: data))
      ?? PendingUploadFlags()
  }

  /// Encode to raw `Data`. Encode failures fall back to empty `Data` to
  /// match `CodableBridge.encode`'s behaviour.
  func encode() -> Data {
    (try? Self.encoder.encode(self)) ?? Data()
  }

  var isEmpty: Bool {
    dirtyRecordNames.isEmpty && deletedRecordNames.isEmpty
  }

  mutating func markDirty(recordName: String) {
    dirtyRecordNames.insert(recordName)
    deletedRecordNames.remove(recordName)
  }

  mutating func markDeleted(recordName: String) {
    deletedRecordNames.insert(recordName)
    dirtyRecordNames.remove(recordName)
  }

  mutating func clear(recordName: String) {
    dirtyRecordNames.remove(recordName)
    deletedRecordNames.remove(recordName)
  }
}
