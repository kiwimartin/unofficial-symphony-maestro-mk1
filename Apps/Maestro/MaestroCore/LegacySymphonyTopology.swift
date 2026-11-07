import Foundation

/// Read-only logical topology for legacy X-Symphony devices.
/// This model NEVER enumerates XLink hardware, changes clock sources,
/// sends device commands, or establishes that a physical chain is supported.
public struct LegacyChannelCapabilities: Codable, Equatable, Sendable {
    public let analogInputs: Int
    public let digitalInputs: Int
    public let analogOutputs: Int
    public let digitalOutputs: Int

    public init(analogInputs: Int = 0, digitalInputs: Int = 0,
                analogOutputs: Int = 0, digitalOutputs: Int = 0) {
        self.analogInputs = analogInputs
        self.digitalInputs = digitalInputs
        self.analogOutputs = analogOutputs
        self.digitalOutputs = digitalOutputs
    }

    public var inputs: Int { analogInputs + digitalInputs }
    public var outputs: Int { analogOutputs + digitalOutputs }
    public var isValid: Bool {
        [analogInputs, digitalInputs, analogOutputs, digitalOutputs].allSatisfy { $0 >= 0 }
    }
}

public enum LegacyConverterMode: String, Codable, Sendable {
    case standard
    case advanced
}

public enum LegacyIdentificationSource: String, Codable, Sendable {
    case detected
    case manual
    case unverified
}

/// Extensible device profile. The planner doesn't need modification to add
/// a different converter or new supported channel configuration.
public struct LegacyConverterProfile: Codable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let standard: LegacyChannelCapabilities
    public let advanced: LegacyChannelCapabilities?

    public init(id: String, name: String, standard: LegacyChannelCapabilities,
                advanced: LegacyChannelCapabilities? = nil) {
        self.id = id
        self.name = name
        self.standard = standard
        self.advanced = advanced
    }

    public func channels(for mode: LegacyConverterMode) -> LegacyChannelCapabilities? {
        mode == .standard ? standard : advanced
    }

    public static let ad16x = LegacyConverterProfile(
        id: "apogee.ad16x", name: "Apogee AD-16X",
        standard: .init(analogInputs: 16),
        advanced: .init(analogInputs: 16, digitalOutputs: 16))

    public static let da16x = LegacyConverterProfile(
        id: "apogee.da16x", name: "Apogee DA-16X",
        standard: .init(analogOutputs: 16),
        advanced: .init(digitalInputs: 16, analogOutputs: 16))

    // The Rosetta profiles intentionally model analog capacity only;
    // any additional digital-mode behavior still needs hardware verification.
    public static let rosetta800 = LegacyConverterProfile(
        id: "apogee.rosetta800", name: "Apogee Rosetta 800",
        standard: .init(analogInputs: 8, analogOutputs: 8))
    public static let rosetta200 = LegacyConverterProfile(
        id: "apogee.rosetta200", name: "Apogee Rosetta 200",
        standard: .init(analogInputs: 2, analogOutputs: 2))
}

public struct LegacyChainDevice: Codable, Equatable, Sendable {
    public let id: String
    public var profile: LegacyConverterProfile
    public var mode: LegacyConverterMode
    public var identification: LegacyIdentificationSource

    public init(id: String, profile: LegacyConverterProfile,
                mode: LegacyConverterMode = .standard,
                identification: LegacyIdentificationSource = .unverified) {
        self.id = id
        self.profile = profile
        self.mode = mode
        self.identification = identification
    }
}

public struct LegacyPort: Codable, Equatable, Sendable {
    /// Port 1 uses host channels 1–32; port 2 uses 33–64.
    public let number: Int
    /// Order supplied by the operator; not necessarily the verified cable order.
    public var chain: [LegacyChainDevice]

    public init(number: Int, chain: [LegacyChainDevice]) {
        self.number = number
        self.chain = chain
    }
}

public enum LegacyClockPreference: String, Codable, Sendable {
    case internalClock = "internal"
    case externalWordClock
}

/// Requested clock mode is not a report of real hardware lock state.
public struct LegacyTopology: Codable, Equatable, Sendable {
    public var ports: [LegacyPort]
    public var clockPreference: LegacyClockPreference

    public init(ports: [LegacyPort], clockPreference: LegacyClockPreference = .internalClock) {
        self.ports = ports
        self.clockPreference = clockPreference
    }

    /// User-supplied inventory. Within-port physical chain order is still unverified.
    public static func referenceStudio() -> LegacyTopology {
        LegacyTopology(ports: [
            LegacyPort(number: 1, chain: [
                .init(id: "p1-ad16x", profile: .ad16x, identification: .manual),
                .init(id: "p1-da16x-a", profile: .da16x, identification: .manual),
                .init(id: "p1-da16x-b", profile: .da16x, identification: .manual)
            ]),
            LegacyPort(number: 2, chain: [
                .init(id: "p2-da16x", profile: .da16x, identification: .manual),
                .init(id: "p2-da16x-advanced", profile: .da16x,
                      mode: .advanced, identification: .manual)
            ])
        ])
    }
}

/// One-based channel labels for the host. NOT FPGA routing-register addresses.
public struct LegacyChannelRange: Codable, Equatable, Sendable {
    public let first: Int
    public let count: Int
    public var last: Int { first + count - 1 }
}

public struct LegacyDeviceAssignment: Equatable, Sendable {
    public let deviceID: String
    public let profileID: String
    public let mode: LegacyConverterMode
    public let channels: LegacyChannelCapabilities
    public let inputs: LegacyChannelRange?
    public let outputs: LegacyChannelRange?
}

public struct LegacyPortPlan: Equatable, Sendable {
    public let port: Int
    public let devices: [LegacyDeviceAssignment]
    public let usedInputs: Int
    public let usedOutputs: Int
}

public struct LegacyTopologyPlan: Equatable, Sendable {
    public let ports: [LegacyPortPlan]
    public let warnings: [String]
    public let clockPreference: LegacyClockPreference
    public var usedInputs: Int { ports.reduce(0) { $0 + $1.usedInputs } }
    public var usedOutputs: Int { ports.reduce(0) { $0 + $1.usedOutputs } }

    /// The planning model is untested on hardware even if warnings are empty.
    public var requiresHardwareValidation: Bool { true }
}

public enum LegacyPlannerError: Error, Equatable, Sendable {
    case invalidPort(Int)
    case duplicatePort(Int)
    case duplicateDevice(String)
    case invalidProfile(String)
    case unsupportedMode(String)
    case invalidChannelCounts(String)
    case exceedsPortCapacity(port: Int, direction: String, count: Int)
}

/// Deterministic channel allocation. All effects are confined to memory.
public enum LegacyTopologyPlanner {
    public static let channelsPerPort = 32
    public static let portCount = 2

    public static func plan(_ topology: LegacyTopology) throws -> LegacyTopologyPlan {
        var seenPorts = Set<Int>()
        var seenDevices = Set<String>()
        var plannedPorts: [LegacyPortPlan] = []
        var warnings: [String] = []

        for port in topology.ports.sorted(by: { $0.number < $1.number }) {
            guard (1...portCount).contains(port.number) else {
                throw LegacyPlannerError.invalidPort(port.number)
            }
            guard seenPorts.insert(port.number).inserted else {
                throw LegacyPlannerError.duplicatePort(port.number)
            }

            var inputs = 0
            var outputs = 0
            var mappedDevices: [LegacyDeviceAssignment] = []

            for device in port.chain {
                guard !device.id.isEmpty, !device.profile.id.isEmpty,
                      !device.profile.name.isEmpty else {
                    throw LegacyPlannerError.invalidProfile(device.id)
                }
                guard seenDevices.insert(device.id).inserted else {
                    throw LegacyPlannerError.duplicateDevice(device.id)
                }
                guard let capabilities = device.profile.channels(for: device.mode) else {
                    throw LegacyPlannerError.unsupportedMode(device.id)
                }
                guard capabilities.isValid else {
                    throw LegacyPlannerError.invalidChannelCounts(device.id)
                }

                let base = (port.number - 1) * channelsPerPort + 1
                let assignedInputs = capabilities.inputs == 0 ? nil :
                    LegacyChannelRange(first: base + inputs, count: capabilities.inputs)
                let assignedOutputs = capabilities.outputs == 0 ? nil :
                    LegacyChannelRange(first: base + outputs, count: capabilities.outputs)

                inputs += capabilities.inputs
                outputs += capabilities.outputs
                mappedDevices.append(LegacyDeviceAssignment(
                    deviceID: device.id, profileID: device.profile.id, mode: device.mode,
                    channels: capabilities, inputs: assignedInputs, outputs: assignedOutputs))

                if device.identification == .unverified {
                    warnings.append("\(device.id): identity not verified")
                }
            }

            guard inputs <= channelsPerPort else {
                throw LegacyPlannerError.exceedsPortCapacity(
                    port: port.number, direction: "inputs", count: inputs)
            }
            guard outputs <= channelsPerPort else {
                throw LegacyPlannerError.exceedsPortCapacity(
                    port: port.number, direction: "outputs", count: outputs)
            }

            let adCount = port.chain.filter { $0.profile.id == "apogee.ad16x" }.count
            let da = port.chain.filter { $0.profile.id == "apogee.da16x" }
            if adCount == 1 && da.count == 2 {
                warnings.append("Port \(port.number): AD-16X plus two DA-16X not explicitly in Apogee's supported combinations")
            }
            if da.count == 2 && Set(da.map(\.mode)).count == 2 {
                warnings.append("Port \(port.number): mixed Standard/Advanced DA-16X configuration requires verification")
            }

            plannedPorts.append(LegacyPortPlan(
                port: port.number, devices: mappedDevices,
                usedInputs: inputs, usedOutputs: outputs))
        }

        return LegacyTopologyPlan(ports: plannedPorts, warnings: warnings,
                                  clockPreference: topology.clockPreference)
    }
}
