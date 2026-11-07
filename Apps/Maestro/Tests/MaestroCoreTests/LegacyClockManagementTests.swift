import Foundation
import Testing
@testable import MaestroCore
@Suite("Independent legacy clock management; no hardware writes")
struct LegacyClockManagementTests {
    @Test func ratesRequireEvidenceForEveryPort() {
        let caps = LegacyClockCapabilities(ratesByPort: [1: [44100, 48000, 96000], 2: [48000]])
        #expect(caps.commonRates(requiredPorts: [1, 2]) == [48000])
        #expect(LegacyClockCapabilities().commonRates(requiredPorts: [1]).isEmpty)
        #expect(caps.commonRates(requiredPorts: [3]).isEmpty)
    }
    @Test func clockPresenceNeverBecomesLockAndExternalNeverFallsBack() throws {
        var manager = LegacyClockManagement(preference: .init(source: .externalWordClock, sampleRate: 48000))
        try manager.observe([.init(port: 1, clockDetected: true, measuredRate: 48000)], requiredPorts: [1])
        #expect(manager.health == .unverified)
        try manager.observe([.init(port: 1, clockDetected: false, measuredRate: nil)], requiredPorts: [1])
        #expect(manager.health == .clockMissing)
        #expect(manager.preference.source == .externalWordClock)
        manager.invalidate(); #expect(manager.health == .unknown && manager.observations.isEmpty)
    }
    @Test func verifiedLockRateMismatchAndRecovery() throws {
        var manager = LegacyClockManagement(preference: .init(sampleRate: 48000))
        try manager.observe([.init(port: 1, clockDetected: true, measuredRate: 48000, verifiedLock: true),
                             .init(port: 2, clockDetected: true, measuredRate: 96000, verifiedLock: true)], requiredPorts: [1, 2])
        #expect(manager.health == .rateMismatch)
        try manager.observe([.init(port: 1, clockDetected: true, measuredRate: 48000, verifiedLock: false)], requiredPorts: [1])
        #expect(manager.health == .unlocked)
        try manager.observe([.init(port: 1, clockDetected: true, measuredRate: 48000, verifiedLock: true)], requiredPorts: [1])
        #expect(manager.health == .locked)
        try manager.setLocalPreference(.init(source: .externalWordClock))
        #expect(manager.health == .unknown)
    }
    @Test func hardwareApplyRemainsClosedAndPresetRoundTrips() throws {
        let preset = LegacyClockPreset(source: .externalWordClock, sampleRate: 48000)
        let manager = LegacyClockManagement(preference: preset)
        let caps = LegacyClockCapabilities(ratesByPort: [1: [48000]])
        #expect(throws: LegacyClockError.confirmationRequired) {
            try manager.validateHardwareRequest(capabilities: caps, requiredPorts: [1], confirmed: false)
        }
        #expect(throws: LegacyClockError.hardwareControlUnavailable) {
            try manager.validateHardwareRequest(capabilities: caps, requiredPorts: [1], confirmed: true)
        }
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let store = LegacyClockPresetStore(defaults: defaults)
        try store.save(preset); #expect(try store.load() == preset)
        defaults.removeObject(forKey: LegacyClockPresetStore.key)
        #expect(try store.load().source == .internalClock)
    }
    @Test func profileCapabilityChangeInvalidatesRoutingInventory() throws {
        let custom = LegacyConverterProfile(id: "dynamic", name: "Dynamic", standard: .init(analogInputs: 2))
        let updated = LegacyConverterProfile(id: "dynamic", name: "Dynamic", standard: .init(analogInputs: 4))
        let config = LegacyManualConfiguration(assignments: [.init(port: 1, position: 1, profileID: "dynamic", mode: .standard)])
        let before = try LegacyRoutingInventory(configuration: config, profiles: [custom])
        let after = try LegacyRoutingInventory(configuration: config, profiles: [updated])
        #expect(before.signature != after.signature)
    }
}
