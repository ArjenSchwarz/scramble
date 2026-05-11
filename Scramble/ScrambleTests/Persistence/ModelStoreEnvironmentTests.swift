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
}
