import Foundation
import SwiftData
import Testing

@testable import Scramble

@Suite("ModelStoreEnvironment")
struct ModelStoreEnvironmentTests {

  @Test("Unit-test env → in-memory, no CloudKit")
  func unitTestEnvironment() {
    let probe = EnvironmentProbe(
      environment: ["XCTestConfigurationFilePath": "/tmp/whatever.xctestconfig"],
      arguments: []
    )
    let config = ModelStore.configuration(probe: probe)
    #expect(config.isStoredInMemoryOnly)
    #expect(config.cloudKitContainerIdentifier == nil)
  }

  @Test("UI-test launch arg (-uitest 1) → in-memory, no CloudKit")
  func uiTestLaunchArg() {
    let probe = EnvironmentProbe(
      environment: [:],
      arguments: ["/path/Scramble.app", "-uitest", "1"]
    )
    let config = ModelStore.configuration(probe: probe)
    #expect(config.isStoredInMemoryOnly)
    #expect(config.cloudKitContainerIdentifier == nil)
  }

  @Test("Preview env → in-memory, no CloudKit")
  func previewEnvironment() {
    let probe = EnvironmentProbe(
      environment: ["XCODE_RUNNING_FOR_PREVIEWS": "1"],
      arguments: []
    )
    let config = ModelStore.configuration(probe: probe)
    #expect(config.isStoredInMemoryOnly)
    #expect(config.cloudKitContainerIdentifier == nil)
  }

  @Test("Production fallthrough → persistent, CloudKit private with bundled identifier")
  func productionFallthrough() {
    let probe = EnvironmentProbe(environment: [:], arguments: [])
    let config = ModelStore.configuration(probe: probe)
    #expect(config.isStoredInMemoryOnly == false)
    #expect(config.cloudKitContainerIdentifier == "iCloud.me.nore.ig.scramble")
  }

  @Test("Probe branches: isTest")
  func probeIsTest() {
    let probe = EnvironmentProbe(
      environment: ["XCTestConfigurationFilePath": "/path"],
      arguments: []
    )
    #expect(probe.isTest)
    #expect(!probe.isUITestHost)
    #expect(!probe.isPreview)
  }

  @Test("Probe branches: isUITestHost")
  func probeIsUITestHost() {
    let probe = EnvironmentProbe(
      environment: [:],
      arguments: ["-uitest", "1"]
    )
    #expect(!probe.isTest)
    #expect(probe.isUITestHost)
    #expect(!probe.isPreview)
  }

  @Test("Probe branches: isPreview")
  func probeIsPreview() {
    let probe = EnvironmentProbe(
      environment: ["XCODE_RUNNING_FOR_PREVIEWS": "1"],
      arguments: []
    )
    #expect(!probe.isTest)
    #expect(!probe.isUITestHost)
    #expect(probe.isPreview)
  }

  @Test("Probe branches: production (none set)")
  func probeIsProduction() {
    let probe = EnvironmentProbe(environment: [:], arguments: [])
    #expect(!probe.isTest)
    #expect(!probe.isUITestHost)
    #expect(!probe.isPreview)
  }

  @Test("UI-test detection ignores 'uitest' without leading dash")
  func uiTestStrictMatch() {
    let probe = EnvironmentProbe(environment: [:], arguments: ["uitest", "1"])
    #expect(!probe.isUITestHost)
  }

  @Test("Preview detection requires value '1', not just presence")
  func previewRequiresOne() {
    let probe = EnvironmentProbe(
      environment: ["XCODE_RUNNING_FOR_PREVIEWS": "0"],
      arguments: []
    )
    #expect(!probe.isPreview)
  }

  // MARK: - Strategy decision (pure function)

  @Test("strategy: unit-test env → .inMemory(.unitTest)")
  func strategyUnitTest() {
    let probe = EnvironmentProbe(
      environment: ["XCTestConfigurationFilePath": "/tmp/whatever.xctestconfig"],
      arguments: []
    )
    #expect(ModelStore.strategy(probe: probe) == .inMemory(reason: .unitTest))
  }

  @Test("strategy: UI-test launch arg → .inMemory(.uiTest)")
  func strategyUITest() {
    let probe = EnvironmentProbe(
      environment: [:],
      arguments: ["/path/Scramble.app", "-uitest", "1"]
    )
    #expect(ModelStore.strategy(probe: probe) == .inMemory(reason: .uiTest))
  }

  @Test("strategy: preview env → .inMemory(.preview)")
  func strategyPreview() {
    let probe = EnvironmentProbe(
      environment: ["XCODE_RUNNING_FOR_PREVIEWS": "1"],
      arguments: []
    )
    #expect(ModelStore.strategy(probe: probe) == .inMemory(reason: .preview))
  }

  @Test("strategy: clean probe → .productionCloudKit")
  func strategyProduction() {
    let probe = EnvironmentProbe(environment: [:], arguments: [])
    #expect(ModelStore.strategy(probe: probe) == .productionCloudKit)
  }

  @Test("strategy: unit-test wins over UI-test when both signals present")
  func strategyUnitTestBeatsUITest() {
    let probe = EnvironmentProbe(
      environment: ["XCTestConfigurationFilePath": "/tmp/whatever"],
      arguments: ["-uitest", "1"]
    )
    #expect(ModelStore.strategy(probe: probe) == .inMemory(reason: .unitTest))
  }

  // MARK: - Phase 5 dual-container API

  @Test("Globals config: unit-test env → in-memory, no CloudKit")
  func globalsConfigInTestEnv() {
    let probe = EnvironmentProbe(
      environment: ["XCTestConfigurationFilePath": "/tmp/x.xctestconfig"],
      arguments: []
    )
    let config = ModelStore.globalsConfiguration(probe: probe)
    #expect(config.isStoredInMemoryOnly)
    #expect(config.cloudKitContainerIdentifier == nil)
  }

  @Test("Globals config: production → CloudKit private with bundled identifier")
  func globalsConfigProduction() {
    let probe = EnvironmentProbe(environment: [:], arguments: [])
    let config = ModelStore.globalsConfiguration(probe: probe)
    #expect(config.isStoredInMemoryOnly == false)
    #expect(config.cloudKitContainerIdentifier == "iCloud.me.nore.ig.scramble")
  }

  @Test("TripsLocal config: unit-test env → in-memory, no CloudKit")
  func tripsLocalConfigInTestEnv() {
    let probe = EnvironmentProbe(
      environment: ["XCTestConfigurationFilePath": "/tmp/x.xctestconfig"],
      arguments: []
    )
    let config = ModelStore.tripsLocalConfiguration(probe: probe)
    #expect(config.isStoredInMemoryOnly)
    #expect(config.cloudKitContainerIdentifier == nil)
  }

  @Test("TripsLocal config: production → on-disk, no CloudKit (CKSyncEngine drives sync)")
  func tripsLocalConfigProduction() {
    let probe = EnvironmentProbe(environment: [:], arguments: [])
    let config = ModelStore.tripsLocalConfiguration(probe: probe)
    #expect(config.isStoredInMemoryOnly == false)
    #expect(config.cloudKitContainerIdentifier == nil)
  }

  @MainActor
  @Test("makeContainers builds both containers in test env")
  func makeContainersInTestEnv() {
    let probe = EnvironmentProbe(
      environment: ["XCTestConfigurationFilePath": "/tmp/x.xctestconfig"],
      arguments: []
    )
    let containers = ModelStore.makeContainers(probe: probe)
    #expect(containers.globals !== containers.tripsLocal)
  }
}
