import Foundation
import Testing
@testable import MaestroCore

@Suite("Passive legacy dual-port discovery (simulator; no hardware proof)")
struct LegacyXLinkDiscoveryTests {
    private struct Source: LegacyXLinkDiagnosticSource {
        let evidence: LegacyXLinkEvidence
        func readLegacyXLinkEvidence() throws -> LegacyXLinkEvidence { evidence }
    }
    private struct Missing: LegacyXLinkDiagnosticSource {
        func readLegacyXLinkEvidence() throws -> LegacyXLinkEvidence {
            throw LegacyXLinkDiagnosticError.driverStatus(1)
        }
    }
    private func packet(clock: UInt32 = 0x01020101) -> [UInt32] {
        var words = [UInt32](repeating: 0, count: 26)
        words[1] = 1; words[2] = 26; words[3] = 0xFFFF; words[4] = 0x220019C2
        words[6] = clock
        return words
    }
    private func refresh(_ words: [UInt32], observations: [LegacyConverterObservation] = [],
                         saved: LegacyManualConfiguration = .init(), enumeration: Bool = true)
        throws -> LegacyXLinkDiscoveryResult {
        try LegacyXLinkDiscovery().refresh(source: Source(evidence: .init(
            snapshot: LegacyXLinkSnapshot(words: words), observations: observations,
            enumerationSupported: enumeration)), saved: saved)
    }

    @Test func independentPortsAndClockDetectionDoNotImplyLock() throws {
        var words = packet()
        words[21] = 7; words[22] = 2; words[23] = 8; words[24] = 1
        let report = try refresh(words)
        #expect(report.ports.map(\.detectedSampleRate) == [44100, 48000])
        #expect(report.ports.allSatisfy { $0.clockLock == nil && $0.dmaErrorCount == nil })
        #expect(report.snapshot.countersAvailable)
        var passive = words; passive[25] = 1
        #expect(try !LegacyXLinkSnapshot(words: passive).countersAvailable)
        #expect(report.snapshot.irqCount == (UInt64(2) << 32) + 7)
        #expect(report.snapshot.port1WrapCount == (UInt64(1) << 32) + 8)
    }
    @Test func missingPort2DoesNotFabricateAnEmptyOrDetectedConverter() throws {
        var words = packet()
        words[3] &= ~(UInt32(0x3F) << 10)
        let saved = LegacyManualConfiguration(assignments: [
            .init(port: 2, position: 1, profileID: "apogee.da16x", mode: .advanced)
        ])
        let report = try refresh(words, saved: saved, enumeration: false)
        #expect(report.ports[0].dataState == .up)
        #expect(report.ports[1].dataState == .unknown)
        #expect(report.ports[1].xlinkStatus == nil)
        #expect(report.observations.isEmpty && report.resolutions.isEmpty)
        #expect(!report.enumerationSupported)
    }
    @Test(arguments: [(UInt32(1), UInt32(44100)), (2, 48000), (4, 88200),
                      (8, 96000), (16, 176400), (32, 192000)])
    func rateChangesOnEitherPort(rate: (UInt32, UInt32)) throws {
        let report = try refresh(packet(clock: 0x01000100 | rate.0 | (rate.0 << 16)))
        #expect(report.ports.map(\.detectedSampleRate) == [rate.1, rate.1])
    }
    @Test func ambiguousRatesAndAbsentClockStayUnknown() throws {
        #expect(try refresh(packet(clock: 0x01030103)).ports.allSatisfy { $0.detectedSampleRate == nil })
        #expect(try refresh(packet(clock: 0x00020001)).ports.allSatisfy {
            $0.clockDetected == false && $0.detectedSampleRate == nil
        })
    }
    @Test func unknownAndAmbiguousDevicesUseIndividualManualFallback() throws {
        let observations: [LegacyConverterObservation] = [
            .init(port: 2, position: 3, profileID: "apogee.ad16x", mode: .standard),
            .init(port: 1, position: 1)
        ]
        let saved = LegacyManualConfiguration(assignments: [
            .init(port: 2, position: 3, profileID: "apogee.da16x", mode: .advanced)
        ])
        let report = try refresh(packet(), observations: observations, saved: saved)
        #expect(report.resolutions.map(\.status) == [.requiresSelection, .requiresConfirmation])
        #expect(report.resolutions[1].proposedProfileID == "apogee.da16x")
        #expect(report.resolutions[1].proposedMode == .advanced)
    }
    @Test func reliableFutureEvidenceCanResolveButUnknownProfilesCannot() throws {
        let report = try refresh(packet(), observations: [
            .init(port: 1, position: 4, profileID: "apogee.rosetta200", mode: .standard,
                  identityVerified: true),
            .init(port: 2, position: 8, profileID: "unknown", mode: .standard,
                  identityVerified: true)
        ])
        #expect(report.resolutions.map(\.status) == [.automaticallyIdentified, .requiresSelection])
    }
    @Test func powerCycleClockLossAndSlipDiscardStaleIdentities() throws {
        let observations: [LegacyConverterObservation] = [
            .init(port: 2, position: 1, hardwareIdentity: "old", profileID: "apogee.ad16x",
                  mode: .standard, identityVerified: true)
        ]
        #expect(try refresh(packet(), observations: observations).resolutions.count == 1)
        for status in [UInt32(1 << 14), UInt32(1 << 19), UInt32.max] {
            var words = packet(); words[16] = status
            #expect(try refresh(words, observations: observations).observations.isEmpty)
        }
        #expect(try refresh(packet(clock: 0x00020101), observations: observations).observations.isEmpty)
        #expect(throws: LegacyXLinkDiagnosticError.self) {
            try LegacyXLinkDiscovery().refresh(source: Missing())
        }
        let changed = LegacyConverterObservation(port: 2, position: 1, hardwareIdentity: "new")
        let saved = LegacyManualConfiguration(assignments: [
            .init(port: 2, position: 1, profileID: "apogee.da16x", mode: .advanced,
                  hardwareIdentity: "old")
        ])
        let reconnected = try refresh(packet(), observations: [changed], saved: saved)
        #expect(reconnected.resolutions[0].status == .requiresSelection)
        #expect(reconnected.resolutions[0].proposedProfileID == nil)
    }
    @Test func rejectsInvalidObservationsEvenWhenPortDown() throws {
        let duplicate = LegacyConverterObservation(port: 2, position: 1)
        #expect(throws: LegacyAssignmentError.self) {
            try refresh(packet(), observations: [duplicate, duplicate])
        }
        #expect(throws: LegacyAssignmentError.self) {
            try refresh(packet(), observations: [.init(port: 3, position: 1)])
        }
    }
    @Test func rejectsTruncatedFailedIncompatibleAndFuturePackets() throws {
        #expect(throws: LegacyXLinkDiagnosticError.self) { try LegacyXLinkSnapshot(words: []) }
        let invalidFields: [(Int, UInt32)] = [(0, 1), (1, 2), (2, 25), (3, 0x10000), (4, 0x210019C2), (25, 2)]
        for (index, value) in invalidFields {
            var words = packet(); words[index] = value
            #expect(throws: LegacyXLinkDiagnosticError.self) { try LegacyXLinkSnapshot(words: words) }
        }
        var words = packet(); words[1] = 2
        let data = try JSONEncoder().encode(["words": words])
        #expect(throws: LegacyXLinkDiagnosticError.self) {
            try JSONDecoder().decode(LegacyXLinkSnapshot.self, from: data)
        }
    }
    @Test func snapshotJSONRoundTripPreservesRawEvidence() throws {
        let snapshot = try LegacyXLinkSnapshot(words: packet())
        #expect(try JSONDecoder().decode(LegacyXLinkSnapshot.self,
                                        from: JSONEncoder().encode(snapshot)) == snapshot)
    }
}
