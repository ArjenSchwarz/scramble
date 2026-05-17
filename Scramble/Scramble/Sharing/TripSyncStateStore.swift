import CloudKit
import Foundation
import os

/// Persistence seam for `CKSyncEngine.State` blobs (Decision 13). Production
/// is `FileTripSyncStateStore`; tests inject `InMemoryTripSyncStateStore`
/// or a corruption-injecting subclass.
@MainActor
protocol TripSyncStateStore: AnyObject {
  func loadState(for scope: CKDatabase.Scope) -> Data?
  func saveState(_ data: Data, for scope: CKDatabase.Scope) throws
  func clearState(for scope: CKDatabase.Scope) throws
}

/// File-backed state store. Stores blobs at
/// `~/Library/Application Support/Scramble/CKSync/{private,shared}.state`
/// with `isExcludedFromBackupKey = true` so iCloud Backup doesn't grow
/// unboundedly with sync state.
@MainActor
final class FileTripSyncStateStore: TripSyncStateStore {
  let baseURL: URL

  init(baseURL: URL? = nil) {
    if let baseURL {
      self.baseURL = baseURL
    } else {
      let support =
        FileManager.default.urls(
          for: .applicationSupportDirectory,
          in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
      self.baseURL =
        support
        .appendingPathComponent("Scramble", isDirectory: true)
        .appendingPathComponent("CKSync", isDirectory: true)
    }
  }

  func loadState(for scope: CKDatabase.Scope) -> Data? {
    let url = fileURL(for: scope)
    return try? Data(contentsOf: url)
  }

  func saveState(_ data: Data, for scope: CKDatabase.Scope) throws {
    try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
    let url = fileURL(for: scope)
    try data.write(to: url, options: .atomic)
    try excludeFromBackup(url)
  }

  func clearState(for scope: CKDatabase.Scope) throws {
    let url = fileURL(for: scope)
    if FileManager.default.fileExists(atPath: url.path) {
      try FileManager.default.removeItem(at: url)
    }
  }

  func fileURL(for scope: CKDatabase.Scope) -> URL {
    baseURL.appendingPathComponent("\(filename(for: scope)).state")
  }

  private func filename(for scope: CKDatabase.Scope) -> String {
    switch scope {
    case .private: return "private"
    case .shared: return "shared"
    case .public: return "public"
    @unknown default: return "unknown"
    }
  }

  private func excludeFromBackup(_ url: URL) throws {
    var mutable = url
    var resourceValues = URLResourceValues()
    resourceValues.isExcludedFromBackup = true
    try mutable.setResourceValues(resourceValues)
  }
}

/// In-memory state store for tests. Optionally returns corrupt data to
/// exercise the recovery path (`returnCorruptDataForScopes`).
@MainActor
final class InMemoryTripSyncStateStore: TripSyncStateStore {
  var blobs: [CKDatabase.Scope: Data] = [:]
  var returnCorruptDataForScopes: Set<CKDatabase.Scope> = []
  private(set) var clearedScopes: [CKDatabase.Scope] = []

  func loadState(for scope: CKDatabase.Scope) -> Data? {
    if returnCorruptDataForScopes.contains(scope) {
      return Data([0x00, 0xff, 0x42])  // intentionally non-decodable
    }
    return blobs[scope]
  }

  func saveState(_ data: Data, for scope: CKDatabase.Scope) throws {
    blobs[scope] = data
  }

  func clearState(for scope: CKDatabase.Scope) throws {
    blobs.removeValue(forKey: scope)
    clearedScopes.append(scope)
  }
}
