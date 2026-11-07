import Foundation

public struct LegacyClockPreset: Codable, Equatable, Sendable {
    public var schemaVersion = 1
    public var source: LegacyClockPreference
    public var sampleRate: UInt32?
    public init(source: LegacyClockPreference = .internalClock, sampleRate: UInt32? = nil) {
        self.source = source; self.sampleRate = sampleRate
    }
    public func validate() throws {
        guard schemaVersion == 1, sampleRate != 0 else { throw LegacyClockError.invalidPreset }
    }
}
public enum LegacyClockError: Error, Equatable, Sendable {
    case invalidPreset, invalidPorts, unsupportedRate, confirmationRequired, hardwareControlUnavailable
}
public enum LegacyClockHealth: String, Sendable {
    case unknown, unverified, clockMissing, unlocked, rateMismatch, locked
}
public struct LegacyClockPortObservation: Equatable, Sendable {
    public let port: Int
    public let clockDetected: Bool?
    public let measuredRate: UInt32?
    public let verifiedLock: Bool?
    public init(port: Int, clockDetected: Bool?, measuredRate: UInt32?, verifiedLock: Bool? = nil) {
        self.port = port; self.clockDetected = clockDetected
        self.measuredRate = measuredRate; self.verifiedLock = verifiedLock
    }
}
/// Capability evidence must come from independently verified hardware support,
/// not a global list of conventional sample rates. Unknown ports expose no rates.
public struct LegacyClockCapabilities: Sendable {
    public let ratesByPort: [Int: Set<UInt32>]
    public init(ratesByPort: [Int: Set<UInt32>] = [:]) { self.ratesByPort = ratesByPort }
    public func commonRates(requiredPorts: Set<Int>) -> [UInt32] {
        guard !requiredPorts.isEmpty, requiredPorts.isSubset(of: [1, 2]) else { return [] }
        var common: Set<UInt32>?
        for port in requiredPorts {
            guard let rates = ratesByPort[port], !rates.contains(0) else { return [] }
            common = common.map { $0.intersection(rates) } ?? rates
        }
        return (common ?? []).sorted()
    }
}
/// Desired source is local intent. No MK I ClockMode/Loop Sync opcode is reused.
public struct LegacyClockManagement: Sendable {
    public private(set) var preference: LegacyClockPreset
    public private(set) var health: LegacyClockHealth = .unknown
    public private(set) var observations: [LegacyClockPortObservation] = []
    public private(set) var generation: UInt64 = 0
    public let hardwareControlAvailable = false
    public init(preference: LegacyClockPreset = .init()) { self.preference = preference }
    public mutating func setLocalPreference(_ preset: LegacyClockPreset) throws {
        try preset.validate(); preference = preset; generation &+= 1
        health = .unknown // New intent is not a report that hardware applied it.
    }
    public mutating func invalidate() {
        observations = []; health = .unknown; generation &+= 1
    }
    public mutating func observe(_ ports: [LegacyClockPortObservation], requiredPorts: Set<Int>) throws {
        guard !requiredPorts.isEmpty, requiredPorts.isSubset(of: [1, 2]),
              ports.allSatisfy({ (1...2).contains($0.port) }),
              Set(ports.map(\.port)).count == ports.count else { throw LegacyClockError.invalidPorts }
        observations = ports; generation &+= 1
        let required = ports.filter { requiredPorts.contains($0.port) }
        guard required.count == requiredPorts.count,
              required.allSatisfy({ $0.clockDetected != nil }) else { health = .unknown; return }
        if required.contains(where: { $0.clockDetected == false }) { health = .clockMissing; return }
        if required.contains(where: { $0.verifiedLock == false }) { health = .unlocked; return }
        guard required.allSatisfy({ $0.verifiedLock == true && ($0.measuredRate ?? 0) > 0 }) else {
            health = .unverified; return
        }
        let rates = Set(required.compactMap(\.measuredRate))
        guard rates.count == 1, preference.sampleRate == nil || rates.first == preference.sampleRate else {
            health = .rateMismatch; return
        }
        health = .locked
        // Never change preference.source or select Internal on External failure.
    }
    public mutating func observePassive(_ result: LegacyXLinkDiscoveryResult, requiredPorts: Set<Int>) throws {
        try observe(result.ports.map { .init(port: $0.port, clockDetected: $0.clockDetected,
                                            measuredRate: $0.detectedSampleRate) }, requiredPorts: requiredPorts)
    }
    public func validateHardwareRequest(capabilities: LegacyClockCapabilities,
                                        requiredPorts: Set<Int>, confirmed: Bool) throws {
        guard confirmed else { throw LegacyClockError.confirmationRequired }
        try preference.validate()
        guard let rate = preference.sampleRate,
              capabilities.commonRates(requiredPorts: requiredPorts).contains(rate) else {
            throw LegacyClockError.unsupportedRate
        }
        // Remains closed even for a conventional rate until a verified legacy
        // transport exists. No caller flag or saved preset can bypass this.
        throw LegacyClockError.hardwareControlUnavailable
    }
}
public struct LegacyClockPresetStore {
    private let defaults: UserDefaults
    public static let key = "maestro.legacyClockPreference.v1"
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    public func load() throws -> LegacyClockPreset {
        guard let data = defaults.data(forKey: Self.key) else { return .init() }
        let preset = try JSONDecoder().decode(LegacyClockPreset.self, from: data)
        try preset.validate(); return preset
    }
    public func save(_ preset: LegacyClockPreset) throws {
        try preset.validate(); defaults.set(try JSONEncoder().encode(preset), forKey: Self.key)
    }
}
