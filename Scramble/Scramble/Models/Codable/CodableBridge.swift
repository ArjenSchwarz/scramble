import Foundation
import os

/// Generic decode/encode helpers used by the `@Model` extensions that bridge
/// `Data`-backed JSON blobs to typed Codable values (see design.md "Codable
/// blobs"). Decode failures log via `modelLogger` and fall back to the
/// caller-supplied default; encode failures log and return empty `Data` so
/// the next successful save overwrites the corrupt blob.
nonisolated enum CodableBridge {
  static func decode<T: Decodable>(
    _ data: Data,
    as type: T.Type,
    default defaultValue: @autoclosure () -> T,
    label: StaticString
  ) -> T {
    guard !data.isEmpty else { return defaultValue() }
    do {
      return try JSONDecoder().decode(T.self, from: data)
    } catch {
      modelLogger.error(
        "\(label, privacy: .public) decode failed: \(error.localizedDescription, privacy: .public)"
      )
      return defaultValue()
    }
  }

  static func encode<T: Encodable>(
    _ value: T,
    label: StaticString
  ) -> Data {
    do {
      return try JSONEncoder().encode(value)
    } catch {
      modelLogger.error(
        "\(label, privacy: .public) encode failed: \(error.localizedDescription, privacy: .public)"
      )
      return Data()
    }
  }
}
