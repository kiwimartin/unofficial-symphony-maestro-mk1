import Foundation

public enum LegacyXLinkDiagnosticError: Error, Equatable, Sendable {
    case invalidPacket
    case driverStatus(UInt32)
    case unsupportedSchema(UInt32)
    case incompatibleCard
}

/// Selector 6 only. No vendor opcode, FIFO read, or recovery fallback.
public struct LegacyXLinkSnapshot: Codable, Equatable, Sendable {
    public static let selector: UInt32 = 6
    public static let wordCount = 26
    public let words: [UInt32]

    public init(words: [UInt32]) throws {
        guard words.count == Self.wordCount else { throw LegacyXLinkDiagnosticError.invalidPacket }
        guard words[0] == 0 else { throw LegacyXLinkDiagnosticError.driverStatus(words[0]) }
        guard words[1] == 1 else { throw LegacyXLinkDiagnosticError.unsupportedSchema(words[1]) }
        guard words[2] == UInt32(Self.wordCount), words[3] & 0xFFFF0000 == 0,
              words[25] == 0 else { throw LegacyXLinkDiagnosticError.invalidPacket }
        guard words[4] == 0x220019C2 else { throw LegacyXLinkDiagnosticError.incompatibleCard }
        self.words = words
    }

    // Validate on JSON decode too; saved packets must never bypass the wire gate.
    private enum CodingKeys: String, CodingKey { case words }
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(words: container.decode([UInt32].self, forKey: .words))
    }

    public func register(_ index: Int) -> UInt32? {
        guard (0..<16).contains(index), words[3] & (1 << index) != 0,
              words[5 + index] != UInt32.max else { return nil }
        return words[5 + index]
    }

    public var irqCount: UInt64 { UInt64(words[21]) | UInt64(words[22]) << 32 }
    public var port1WrapCount: UInt64 { UInt64(words[23]) | UInt64(words[24]) << 32 }
}

public enum LegacyXLinkDataState: String, Codable, Sendable {
    case unknown, down, slipping, up
}

public struct LegacyXLinkPortDiagnostics: Encodable, Equatable, Sendable {
    public let port: Int
    public let dataState: LegacyXLinkDataState
    public let clockDetected: Bool?
    public let detectedSampleRate: UInt32?
    /// RX clock detect is NOT proof of word-clock/PLL lock.
    public let clockLock: Bool? = nil
    public let gcsr: UInt32?
    public let xlinkStatus: UInt32?
    public let captureBufferWords: UInt32?
    public let playbackBufferWords: UInt32?
    public let captureCurrentAddress: UInt32?
    public let playbackCurrentAddress: UInt32?
    /// Per-port underrun/overrun counts are not maintained by the current driver.
    public let dmaErrorCount: UInt64? = nil
}

/// The live source currently provides NO individual converter observations.
/// Future enumerators may return observations only for reliably located units;
/// ambiguous model/mode reads must leave identityVerified false. No saved values.
public struct LegacyXLinkEvidence: Sendable {
    public let snapshot: LegacyXLinkSnapshot
    public let observations: [LegacyConverterObservation]
    public let enumerationSupported: Bool

    public init(snapshot: LegacyXLinkSnapshot,
                observations: [LegacyConverterObservation] = [],
                enumerationSupported: Bool = false) {
        self.snapshot = snapshot
        self.observations = observations
        self.enumerationSupported = enumerationSupported
    }
}

/// Intentionally exposes a read operation only; no clock, routing or mode writes.
public protocol LegacyXLinkDiagnosticSource {
    func readLegacyXLinkEvidence() throws -> LegacyXLinkEvidence
}

public struct LegacyXLinkDiscoveryResult: Sendable {
    public let snapshot: LegacyXLinkSnapshot
    public let ports: [LegacyXLinkPortDiagnostics]
    public let enumerationSupported: Bool
    public let observations: [LegacyConverterObservation]
    public let resolutions: [LegacyConverterResolution]
}

/// Stateless refresh: unavailable reads throw, so old observations cannot be
/// reported as a new discovery. The caller must clear a previous result on error.
public struct LegacyXLinkDiscovery {
    public init() {}

    public func refresh(source: any LegacyXLinkDiagnosticSource,
                        saved: LegacyManualConfiguration = .init(),
                        profiles: [LegacyConverterProfile] = [.ad16x, .da16x, .rosetta200, .rosetta800])
        throws -> LegacyXLinkDiscoveryResult {
        let evidence = try source.readLegacyXLinkEvidence()
        let ports = Self.ports(from: evidence.snapshot)
        // Validate all locations (including those on a port that is now down).
        _ = try LegacyAssignmentResolver.resolve(observations: evidence.observations,
                                                 saved: saved, profiles: profiles)
        let observations = evidence.enumerationSupported ? evidence.observations.filter { observation in
            // No promotion of buffered identities on a failed/unknown data link.
            ports.first { $0.port == observation.port }?.dataState == .up &&
                ports.first { $0.port == observation.port }?.clockDetected == true
        } : []
        let resolutions = try LegacyAssignmentResolver.resolve(observations: observations,
                                                               saved: saved, profiles: profiles)
        return .init(snapshot: evidence.snapshot, ports: ports,
                     enumerationSupported: evidence.enumerationSupported,
                     observations: observations, resolutions: resolutions)
    }

    public static func ports(from snapshot: LegacyXLinkSnapshot) -> [LegacyXLinkPortDiagnostics] {
        (1...2).map { port in
            let base = port == 1 ? 4 : 10
            let status = snapshot.register(base + 1)
            let clock = snapshot.register(1)
            let shift = port == 1 ? 0 : 16
            let detected = clock.map { $0 & (UInt32(0x100) << shift) != 0 }
            let rateBits = clock.map { ($0 >> shift) & 0x3F }
            let rates: [UInt32: UInt32] = [1: 44100, 2: 48000, 4: 88200,
                                          8: 96000, 16: 176400, 32: 192000]
            let rate = detected == true ? rateBits.flatMap { rates[$0] } : nil
            let state: LegacyXLinkDataState
            if let status {
                if status & (1 << 14) != 0 { state = .down }
                else if status & (1 << 19) != 0 { state = .slipping }
                else { state = .up }
            } else { state = .unknown }
            return .init(port: port, dataState: state, clockDetected: detected,
                         detectedSampleRate: rate, gcsr: snapshot.register(base),
                         xlinkStatus: status, captureBufferWords: snapshot.register(base + 2),
                         playbackBufferWords: snapshot.register(base + 3),
                         captureCurrentAddress: snapshot.register(base + 4),
                         playbackCurrentAddress: snapshot.register(base + 5))
        }
    }
}
