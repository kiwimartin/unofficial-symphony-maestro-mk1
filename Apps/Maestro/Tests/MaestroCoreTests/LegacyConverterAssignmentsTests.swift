import Foundation
import Testing
@testable import MaestroCore

@Suite("Legacy converter manual fallback")
struct LegacyConverterAssignmentsTests {
    let profiles: [LegacyConverterProfile] = [.ad16x, .da16x, .rosetta200]

    private func observation(_ port: Int, _ position: Int, serial: String? = nil,
                             model: String? = nil, mode: LegacyConverterMode? = nil,
                             verified: Bool = false) -> LegacyConverterObservation {
        .init(port: port, position: position, hardwareIdentity: serial,
              profileID: model, mode: mode, identityVerified: verified)
    }

    @Test func unresolvedConvertersPromptIndividually() throws {
        let observed = [observation(2, 2), observation(1, 1), observation(2, 1)]
        let result = try LegacyAssignmentResolver.resolve(
            observations: observed, saved: .init(), profiles: profiles)
        #expect(result.map(\.observation.port) == [1, 2, 2])
        #expect(result.map(\.observation.position) == [1, 1, 2])
        #expect(result.allSatisfy { $0.needsUserInput })
        #expect(result.allSatisfy { $0.status == .requiresSelection })
    }

    @Test func verifiedCompleteIdentityDoesNotPrompt() throws {
        let observed = [observation(2, 1, serial: "ser1", model: "apogee.ad16x",
                                    mode: .standard, verified: true)]
        let result = try LegacyAssignmentResolver.resolve(
            observations: observed, saved: .init(), profiles: profiles)
        #expect(result[0].status == .automaticallyIdentified)
        #expect(!result[0].needsUserInput)
    }

    @Test func savedManualAdvancedMustBeConfirmedWithoutModeRead() throws {
        let stored = LegacyManualConfiguration(assignments: [
            .init(port: 2, position: 2, profileID: "apogee.da16x", mode: .advanced,
                  hardwareIdentity: "serial-77")
        ])
        let observed = [observation(2, 2, serial: "serial-77")]
        let result = try LegacyAssignmentResolver.resolve(
            observations: observed, saved: stored, profiles: profiles)
        #expect(result[0].status == .requiresConfirmation)
        #expect(result[0].proposedProfileID == "apogee.da16x")
        #expect(result[0].proposedMode == .advanced)
        #expect(result[0].needsUserInput)
    }

    @Test func staleFingerprintMustNotPrefillPreviousUnit() throws {
        let stored = LegacyManualConfiguration(assignments: [
            .init(port: 2, position: 2, profileID: "apogee.da16x", mode: .advanced,
                  hardwareIdentity: "previous-serial")
        ])
        let observed = [observation(2, 2, serial: "replacement-serial")]
        let result = try LegacyAssignmentResolver.resolve(
            observations: observed, saved: stored, profiles: profiles)
        #expect(result[0].status == .requiresSelection)
        #expect(result[0].proposedProfileID == nil)
        #expect(result[0].proposedMode == nil)
    }

    @Test func unknownHardwareIDIsNotConsideredAMatch() throws {
        let stored = LegacyManualConfiguration(assignments: [
            .init(port: 1, position: 1, profileID: "apogee.da16x", mode: .standard)
        ])
        let result = try LegacyAssignmentResolver.resolve(
            observations: [observation(1, 1)], saved: stored, profiles: profiles)
        #expect(result[0].status == .requiresConfirmation)
        #expect(result[0].needsUserInput)
    }

    @Test func partialVerifiedDetectionAsksForMode() throws {
        let observed = [observation(1, 1, model: "apogee.da16x", verified: true)]
        let result = try LegacyAssignmentResolver.resolve(
            observations: observed, saved: .init(), profiles: profiles)
        #expect(result[0].status == .requiresConfirmation)
        #expect(result[0].proposedProfileID == "apogee.da16x")
        #expect(result[0].proposedMode == nil)
    }

    @Test func invalidDetectedProfileCannotBecomeAutomatic() throws {
        let observed = [observation(1, 1, model: "unknown.model", mode: .advanced,
                                    verified: true)]
        let result = try LegacyAssignmentResolver.resolve(
            observations: observed, saved: .init(), profiles: profiles)
        #expect(result[0].status == .requiresSelection)
    }

    @Test func cannotUseAdvancedModeForProfileWithoutAdvanced() throws {
        let stored = LegacyManualConfiguration(assignments: [
            .init(port: 1, position: 1, profileID: "apogee.rosetta200", mode: .advanced)
        ])
        let result = try LegacyAssignmentResolver.resolve(
            observations: [observation(1, 1)], saved: stored, profiles: profiles)
        #expect(result[0].status == .requiresSelection)
    }

    @Test func duplicateObservationsAreRejected() {
        #expect(throws: LegacyAssignmentError.duplicateObservation(port: 1, position: 1)) {
            try LegacyAssignmentResolver.resolve(
                observations: [observation(1, 1), observation(1, 1)],
                saved: .init(), profiles: profiles)
        }
    }

    @Test func configurationValidatesDuplicatesAndPartialFields() {
        let config = LegacyManualConfiguration(assignments: [
            .init(port: 1, position: 1), .init(port: 1, position: 1)
        ])
        #expect(throws: LegacyAssignmentError.duplicatePosition(port: 1, position: 1)) {
            try config.validate()
        }
        let partial = LegacyManualConfiguration(assignments: [
            .init(port: 2, position: 1, profileID: "apogee.ad16x")
        ])
        #expect(throws: LegacyAssignmentError.incompletePair(port: 2, position: 1)) {
            try partial.validate()
        }
    }

    @Test func saveRestoreAndCorruptDataAreDistinct() throws {
        let suite = "LegacyConverterAssignmentsTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = LegacyAssignmentStore(defaults: defaults)
        #expect(try store.load().assignments.isEmpty)
        let config = LegacyManualConfiguration(assignments: [
            .init(port: 1, position: 1, profileID: "apogee.ad16x", mode: .standard)
        ])
        try store.save(config)
        #expect(try store.load() == config)
        defaults.set(Data("broken".utf8), forKey: LegacyAssignmentStore.storageKey)
        #expect(throws: LegacyAssignmentError.malformedData) {
            try store.load()
        }
    }

    @Test func noObservationsMeansNoFabricatedPhysicalDevices() throws {
        let saved = LegacyManualConfiguration(assignments: [
            .init(port: 2, position: 1, profileID: "apogee.da16x", mode: .standard)
        ])
        let result = try LegacyAssignmentResolver.resolve(
            observations: [], saved: saved, profiles: profiles)
        #expect(result.isEmpty)
    }
}
