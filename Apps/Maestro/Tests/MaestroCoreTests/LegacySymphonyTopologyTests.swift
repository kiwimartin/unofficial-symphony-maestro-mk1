import Foundation
import Testing
@testable import MaestroCore

@Suite("Legacy X-Symphony topology: logical model only")
struct LegacySymphonyTopologyTests {
    @Test func arbitraryMixedProfilesAcrossPorts() throws {
        // The input inventory comes from the caller, not the production code.
        let custom = LegacyConverterProfile(
            id: "custom.4x4", name: "Configurable 4-in / 4-out",
            standard: .init(analogInputs: 4, analogOutputs: 4))
        let setup = LegacyTopology(ports: [
            LegacyPort(number: 1, chain: [
                .init(id: "p1-a", profile: .rosetta800, identification: .detected),
                .init(id: "p1-b", profile: .da16x, mode: .advanced, identification: .manual)
            ]),
            LegacyPort(number: 2, chain: [
                .init(id: "p2-a", profile: .ad16x, identification: .detected),
                .init(id: "p2-b", profile: custom, identification: .manual)
            ])
        ])
        let plan = try LegacyTopologyPlanner.plan(setup)
        #expect(plan.ports.map(\.port) == [1, 2])
        #expect(plan.usedInputs == 44)
        #expect(plan.usedOutputs == 28)
        #expect(plan.ports[0].usedInputs == 24)
        #expect(plan.ports[0].usedOutputs == 24)
        #expect(plan.ports[1].usedInputs == 20)
        #expect(plan.ports[1].usedOutputs == 4)
        #expect(plan.ports[0].devices[0].inputs == LegacyChannelRange(first: 1, count: 8))
        #expect(plan.ports[0].devices[0].outputs == LegacyChannelRange(first: 1, count: 8))
        #expect(plan.ports[0].devices[1].inputs == LegacyChannelRange(first: 9, count: 16))
        #expect(plan.ports[0].devices[1].outputs == LegacyChannelRange(first: 9, count: 16))
        #expect(plan.ports[1].devices[0].inputs == LegacyChannelRange(first: 33, count: 16))
        #expect(plan.ports[1].devices[1].inputs == LegacyChannelRange(first: 49, count: 4))
        #expect(plan.ports[1].devices[1].outputs == LegacyChannelRange(first: 33, count: 4))
        #expect(plan.ports[0].devices[1].identification == .manual)
        #expect(plan.ports[1].devices[0].identification == .detected)
        #expect(plan.warnings.isEmpty)
        #expect(plan.requiresHardwareValidation)
    }

    @Test func portsAreOrderedByNumberNotInputOrder() throws {
        let setup = LegacyTopology(ports: [
            LegacyPort(number: 2, chain: [
                .init(id: "p2", profile: .rosetta200, identification: .detected)
            ]),
            LegacyPort(number: 1, chain: [
                .init(id: "p1", profile: .da16x, identification: .detected)
            ])
        ])
        let plan = try LegacyTopologyPlanner.plan(setup)
        #expect(plan.ports.map(\.port) == [1, 2])
        #expect(plan.ports[0].devices[0].outputs == LegacyChannelRange(first: 1, count: 16))
        #expect(plan.ports[1].devices[0].inputs == LegacyChannelRange(first: 33, count: 2))
        #expect(plan.ports[1].devices[0].outputs == LegacyChannelRange(first: 33, count: 2))
    }

    @Test func clockIsOptionalAndRoundTrips() throws {
        var setup = LegacyTopology(ports: [
            LegacyPort(number: 2, chain: [
                .init(id: "clock-example", profile: .rosetta200, identification: .manual)
            ])
        ])
        #expect(setup.clockPreference == .internalClock)
        setup.clockPreference = .externalWordClock
        let data = try JSONEncoder().encode(setup)
        let decoded = try JSONDecoder().decode(LegacyTopology.self, from: data)
        #expect(decoded == setup)
        #expect(try LegacyTopologyPlanner.plan(decoded).clockPreference == .externalWordClock)
    }

    @Test func rejectsOutputOverflow() {
        let setup = LegacyTopology(ports: [
            LegacyPort(number: 1, chain: (0..<3).map {
                LegacyChainDevice(id: "da-\($0)", profile: .da16x)
            })
        ])
        #expect(throws: LegacyPlannerError.exceedsPortCapacity(port: 1, direction: "outputs", count: 48)) {
            try LegacyTopologyPlanner.plan(setup)
        }
    }

    @Test func rejectsInputOverflow() {
        let setup = LegacyTopology(ports: [
            LegacyPort(number: 2, chain: (0..<3).map {
                LegacyChainDevice(id: "ad-\($0)", profile: .ad16x)
            })
        ])
        #expect(throws: LegacyPlannerError.exceedsPortCapacity(port: 2, direction: "inputs", count: 48)) {
            try LegacyTopologyPlanner.plan(setup)
        }
    }

    @Test func rejectsInvalidPort() {
        #expect(throws: LegacyPlannerError.invalidPort(3)) {
            try LegacyTopologyPlanner.plan(LegacyTopology(ports: [LegacyPort(number: 3, chain: [])]))
        }
    }

    @Test func rejectsDuplicatePort() {
        #expect(throws: LegacyPlannerError.duplicatePort(1)) {
            try LegacyTopologyPlanner.plan(LegacyTopology(ports: [
                LegacyPort(number: 1, chain: []), LegacyPort(number: 1, chain: [])
            ]))
        }
    }

    @Test func rejectsDuplicateDeviceAcrossPorts() {
        #expect(throws: LegacyPlannerError.duplicateDevice("same")) {
            try LegacyTopologyPlanner.plan(LegacyTopology(ports: [
                LegacyPort(number: 1, chain: [.init(id: "same", profile: .ad16x)]),
                LegacyPort(number: 2, chain: [.init(id: "same", profile: .da16x)])
            ]))
        }
    }

    @Test func advancedModeNeedsAnExplicitProfile() {
        let setup = LegacyTopology(ports: [
            LegacyPort(number: 1, chain: [
                .init(id: "rosetta", profile: .rosetta800, mode: .advanced)
            ])
        ])
        #expect(throws: LegacyPlannerError.unsupportedMode("rosetta")) {
            try LegacyTopologyPlanner.plan(setup)
        }
    }

    @Test func unknownIdentityIsNotSilentlyTrusted() throws {
        let setup = LegacyTopology(ports: [
            LegacyPort(number: 2, chain: [.init(id: "unknown", profile: .da16x)])
        ])
        let plan = try LegacyTopologyPlanner.plan(setup)
        #expect(plan.warnings.contains { $0.contains("identity not verified") })
        #expect(plan.requiresHardwareValidation)
    }

    @Test func extensibleCustomProfile() throws {
        let profile = LegacyConverterProfile(
            id: "custom.test", name: "Custom 4-in 8-out",
            standard: .init(analogInputs: 4, analogOutputs: 8))
        let setup = LegacyTopology(ports: [
            LegacyPort(number: 2, chain: [
                .init(id: "custom", profile: profile, identification: .manual)
            ])
        ])
        let plan = try LegacyTopologyPlanner.plan(setup)
        #expect(plan.usedInputs == 4)
        #expect(plan.usedOutputs == 8)
        #expect(plan.ports[0].devices[0].inputs == LegacyChannelRange(first: 33, count: 4))
    }

    @Test func standardDAHasNoDigitalInput() throws {
        let setup = LegacyTopology(ports: [
            LegacyPort(number: 1, chain: [.init(id: "da", profile: .da16x)])
        ])
        let plan = try LegacyTopologyPlanner.plan(setup)
        #expect(plan.usedInputs == 0)
        #expect(plan.usedOutputs == 16)
    }

    @Test func evenSimplePlanRequiresHardwareValidation() throws {
        let setup = LegacyTopology(ports: [
            LegacyPort(number: 1, chain: [
                .init(id: "known", profile: .da16x, identification: .manual)
            ])
        ])
        let plan = try LegacyTopologyPlanner.plan(setup)
        #expect(plan.warnings.isEmpty)
        #expect(plan.requiresHardwareValidation)
    }

    @Test func rejectsNegativeChannels() {
        let profile = LegacyConverterProfile(
            id: "test.bad", name: "Bad", standard: .init(analogInputs: -1))
        let setup = LegacyTopology(ports: [
            LegacyPort(number: 1, chain: [.init(id: "bad", profile: profile)])
        ])
        #expect(throws: LegacyPlannerError.invalidChannelCounts("bad")) {
            try LegacyTopologyPlanner.plan(setup)
        }
    }
}
