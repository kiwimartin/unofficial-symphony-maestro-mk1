import Foundation

/// One entry represents one *reported* position in an X-Symphony chain.
/// This is operator-supplied metadata, not an instruction to the driver.
public struct LegacyConverterAssignment: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var port: Int
    public var position: Int
    public var profileID: String?
    public var mode: LegacyConverterMode?
    /// Present only when obtained from a trusted, stable hardware identifier.
    /// A port/position label is never a stable hardware identifier.
    public var hardwareIdentity: String?

    public init(id: UUID = UUID(), port: Int, position: Int,
                profileID: String? = nil, mode: LegacyConverterMode? = nil,
                hardwareIdentity: String? = nil) {
        self.id = id
        self.port = port
        self.position = position
        self.profileID = profileID
        self.mode = mode
        self.hardwareIdentity = hardwareIdentity
    }

    public var isComplete: Bool { profileID != nil && mode != nil }
}

public struct LegacyManualConfiguration: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1
    public var schemaVersion: Int
    public var assignments: [LegacyConverterAssignment]

    public init(assignments: [LegacyConverterAssignment] = []) {
        self.schemaVersion = Self.currentSchemaVersion
        self.assignments = assignments
    }

    /// Do not silently discard duplicate or malformed assignments on loading.
    public func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw LegacyAssignmentError.unsupportedSchema(schemaVersion)
        }
        var ids = Set<UUID>()
        var positions = Set<String>()
        for item in assignments {
            guard (1...LegacyTopologyPlanner.portCount).contains(item.port), item.position > 0 else {
                throw LegacyAssignmentError.invalidLocation(port: item.port, position: item.position)
            }
            guard ids.insert(item.id).inserted else {
                throw LegacyAssignmentError.duplicateID(item.id)
            }
            guard positions.insert("\(item.port):\(item.position)").inserted else {
                throw LegacyAssignmentError.duplicatePosition(port: item.port, position: item.position)
            }
            if item.profileID?.isEmpty == true || item.hardwareIdentity?.isEmpty == true {
                throw LegacyAssignmentError.invalidIdentifier
            }
            guard (item.profileID == nil) == (item.mode == nil) else {
                throw LegacyAssignmentError.incompletePair(port: item.port, position: item.position)
            }
        }
    }
}

public enum LegacyAssignmentError: Error, Equatable, Sendable {
    case unsupportedSchema(Int)
    case invalidLocation(port: Int, position: Int)
    case duplicateID(UUID)
    case duplicatePosition(port: Int, position: Int)
    case invalidIdentifier
    case incompletePair(port: Int, position: Int)
    case malformedData
    case duplicateObservation(port: Int, position: Int)
}

/// Deliberately not Sendable; UserDefaults belongs to the UI/main-thread layer.
/// No device writes, XLink commands, or hardware clock changes.
public struct LegacyAssignmentStore {
    public static let storageKey = "maestro.legacyConverterAssignments.v1"
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = Self.storageKey) {
        self.defaults = defaults
        self.key = key
    }

    public func load() throws -> LegacyManualConfiguration {
        guard let data = defaults.data(forKey: key) else {
            return LegacyManualConfiguration()
        }
        do {
            let config = try JSONDecoder().decode(LegacyManualConfiguration.self, from: data)
            try config.validate()
            return config
        } catch let error as LegacyAssignmentError {
            throw error
        } catch {
            throw LegacyAssignmentError.malformedData
        }
    }

    public func save(_ configuration: LegacyManualConfiguration) throws {
        try configuration.validate()
        let data = try JSONEncoder().encode(configuration)
        defaults.set(data, forKey: key)
    }
}

/// A read-only observation from a future legacy XLink discovery implementation.
/// 'profileID' and 'mode' are only trusted when 'identityVerified' is true.
/// Current DriverKit does NOT provide these per-converter observations.
public struct LegacyConverterObservation: Equatable, Sendable {
    public let port: Int
    public let position: Int
    public let hardwareIdentity: String?
    public let profileID: String?
    public let mode: LegacyConverterMode?
    public let identityVerified: Bool

    public init(port: Int, position: Int, hardwareIdentity: String? = nil,
                profileID: String? = nil, mode: LegacyConverterMode? = nil,
                identityVerified: Bool = false) {
        self.port = port
        self.position = position
        self.hardwareIdentity = hardwareIdentity
        self.profileID = profileID
        self.mode = mode
        self.identityVerified = identityVerified
    }
}

public enum LegacyResolutionStatus: Equatable, Sendable {
    /// Both model and mode are reliably reported by the hardware.
    case automaticallyIdentified
    /// A previous manual choice is offered, but must be confirmed again.
    case requiresConfirmation
    /// No appropriate saved choice is available for this position.
    case requiresSelection
}

public struct LegacyConverterResolution: Equatable, Sendable {
    public let observation: LegacyConverterObservation
    public let status: LegacyResolutionStatus
    /// A prefill for the dialog, NEVER proof that the device has this identity.
    public let proposedProfileID: String?
    public let proposedMode: LegacyConverterMode?

    public var needsUserInput: Bool { status != .automaticallyIdentified }
}

/// A device-specific fallback mechanism. No hard-coded chain layouts.
/// IMPORTANT: without a reliable mode read, a saved Advanced/Standard setting
/// must be confirmed every session, even if the device has the same serial ID.
public enum LegacyAssignmentResolver {
    public static func resolve(
        observations: [LegacyConverterObservation],
        saved: LegacyManualConfiguration,
        profiles: [LegacyConverterProfile]
    ) throws -> [LegacyConverterResolution] {
        try saved.validate()
        let known = Dictionary(profiles.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let previous = Dictionary(
            uniqueKeysWithValues: saved.assignments.map { ("\($0.port):\($0.position)", $0) })
        var keys = Set<String>()
        var result: [LegacyConverterResolution] = []
        for item in observations.sorted(by: {
            $0.port == $1.port ? $0.position < $1.position : $0.port < $1.port
        }) {
            guard (1...LegacyTopologyPlanner.portCount).contains(item.port), item.position > 0 else {
                throw LegacyAssignmentError.invalidLocation(port: item.port, position: item.position)
            }
            let key = "\(item.port):\(item.position)"
            guard keys.insert(key).inserted else {
                throw LegacyAssignmentError.duplicateObservation(port: item.port, position: item.position)
            }
            if item.identityVerified, let id = item.profileID, let mode = item.mode,
               let profile = known[id], profile.channels(for: mode) != nil {
                result.append(.init(observation: item, status: .automaticallyIdentified,
                                    proposedProfileID: id, proposedMode: mode))
                continue
            }
            let prior = previous[key]
            let mismatch = prior?.hardwareIdentity != nil && item.hardwareIdentity != nil
                && prior?.hardwareIdentity != item.hardwareIdentity
            let usable = prior.flatMap { item -> LegacyConverterAssignment? in
                guard !mismatch, let id = item.profileID, let mode = item.mode,
                      let profile = known[id], profile.channels(for: mode) != nil else {
                    return nil
                }
                return item
            }
            // A trusted partial read can prefill the device type/mode even when
            // the other is missing. Both still require explicit confirmation.
            let identifiedProfile = item.identityVerified && known[item.profileID ?? ""] != nil
                ? item.profileID : nil
            let identifiedMode = item.identityVerified ? item.mode : nil
            let candidateID = identifiedProfile ?? usable?.profileID
            let candidateMode = identifiedMode ?? usable?.mode
            let prefillIsValid = candidateID.flatMap { known[$0] }?.channels(for: candidateMode ?? .standard) != nil
            let status: LegacyResolutionStatus = candidateID == nil || !prefillIsValid
                ? .requiresSelection : .requiresConfirmation
            result.append(.init(observation: item, status: status,
                                proposedProfileID: candidateID, proposedMode: candidateMode))
        }
        return result
    }
}
