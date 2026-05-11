import Foundation

nonisolated struct EnvironmentProbe: Sendable {
  let environment: [String: String]
  let arguments: [String]

  init(environment: [String: String], arguments: [String]) {
    self.environment = environment
    self.arguments = arguments
  }

  nonisolated static var production: EnvironmentProbe {
    let info = ProcessInfo.processInfo
    return EnvironmentProbe(environment: info.environment, arguments: info.arguments)
  }

  var isTest: Bool {
    environment["XCTestConfigurationFilePath"] != nil
  }

  var isUITestHost: Bool {
    guard let idx = arguments.firstIndex(of: "-uitest") else { return false }
    let next = arguments.index(after: idx)
    return next < arguments.endIndex && arguments[next] == "1"
  }

  var isPreview: Bool {
    environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
  }
}
