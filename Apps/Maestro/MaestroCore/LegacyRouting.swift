import Foundation

public enum LegacySignalDirection: String, Codable, Sendable { case input, output }
public enum LegacySignalMedia: String, Codable, Sendable { case analog, digital }
public struct LegacyPhysicalEndpoint: Codable, Equatable, Identifiable, Sendable {
    public let deviceID: UUID
    public let port: Int
    public let profileID: String
    public let mode: LegacyConverterMode
    public let direction: LegacySignalDirection
    public let media: LegacySignalMedia
    public let channel: Int
    public var id: String { "\(deviceID)/\(direction.rawValue)/\(media.rawValue)/\(channel)" }
    public var label: String { "Port \(port) · \(profileID) · \(media.rawValue) \(direction.rawValue) \(channel)" }
}
public enum LegacyRoutingError: Error, Equatable, Sendable {
    case invalidInventory, invalidMap, duplicateSlot, unsupportedRate
    case unsupportedSchema, changedConfiguration, unconfirmedRestore, conflictingRoutes
}
public struct LegacyRoutingInventory: Equatable, Sendable {
    public let endpoints: [LegacyPhysicalEndpoint]
    public let signature: String
    public init(configuration: LegacyManualConfiguration, profiles: [LegacyConverterProfile]) throws {
        try configuration.validate()
        var endpoints: [LegacyPhysicalEndpoint] = []
        var ports: [LegacyPort] = []
        for port in 1...2 {
            var chain: [LegacyChainDevice] = []
            for device in configuration.assignments.filter({ $0.port == port }).sorted(by: { $0.position < $1.position }) {
                guard device.isComplete else { continue } // Unknown devices expose no invented channels.
                guard let profile = profiles.first(where: { $0.id == device.profileID }),
                      let mode = device.mode, let caps = profile.channels(for: mode), caps.isValid else {
                    throw LegacyRoutingError.invalidInventory
                }
                chain.append(.init(id: device.id.uuidString, profile: profile, mode: mode, identification: .manual))
                let groups: [(LegacySignalDirection, LegacySignalMedia, Int)] = [
                    (.input, .analog, caps.analogInputs), (.input, .digital, caps.digitalInputs),
                    (.output, .analog, caps.analogOutputs), (.output, .digital, caps.digitalOutputs)
                ]
                // Bounded before constructing ranges, even for runtime-supplied profiles.
                guard groups.allSatisfy({ (0...32).contains($0.2) }) else { throw LegacyRoutingError.invalidInventory }
                for (direction, media, count) in groups where count > 0 {
                    for channel in 1...count {
                        endpoints.append(.init(deviceID: device.id, port: port, profileID: profile.id,
                                               mode: mode, direction: direction, media: media, channel: channel))
                    }
                }
            }
            ports.append(.init(number: port, chain: chain))
        }
        _ = try LegacyTopologyPlanner.plan(.init(ports: ports))
        self.endpoints = endpoints
        // Includes order, mode, identity and unknown entries: a changed chain
        // cannot silently reuse a previous slot map or routing preset.
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let ordered = configuration.assignments.sorted { $0.port == $1.port ? $0.position < $1.position : $0.port < $1.port }
        self.signature = try encoder.encode(ordered).base64EncodedString() + "." + encoder.encode(endpoints).base64EncodedString()
    }
}
public struct LegacySlotEntry: Codable, Equatable, Sendable {
    public let endpointID: String
    /// Zero-based slot within its endpoint's port. Never derived by adding device channel counts.
    public let xlinkSlot: Int
    public init(endpointID: String, xlinkSlot: Int) { self.endpointID = endpointID; self.xlinkSlot = xlinkSlot }
}
public struct LegacySlotMap: Equatable, Sendable {
    public let entries: [LegacySlotEntry]
    public let inventorySignature: String
    public let sampleRate: UInt32
    public let evidenceReference: String
    public let signature: String
    public init(entries: [LegacySlotEntry], inventory: LegacyRoutingInventory,
                sampleRate: UInt32, evidenceReference: String) throws {
        guard sampleRate > 0 else { throw LegacyRoutingError.unsupportedRate }
        guard !evidenceReference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LegacyRoutingError.invalidMap
        }
        var endpointIDs = Set<String>(), slots = Set<String>()
        for entry in entries {
            guard let endpoint = inventory.endpoints.first(where: { $0.id == entry.endpointID }),
                  (0..<32).contains(entry.xlinkSlot), endpointIDs.insert(entry.endpointID).inserted else {
                throw LegacyRoutingError.invalidMap
            }
            guard slots.insert("\(endpoint.port)/\(endpoint.direction.rawValue)/\(entry.xlinkSlot)").inserted else {
                throw LegacyRoutingError.duplicateSlot
            }
        }
        self.entries = entries; self.inventorySignature = inventory.signature
        self.sampleRate = sampleRate; self.evidenceReference = evidenceReference
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        self.signature = try encoder.encode(entries.sorted { $0.endpointID < $1.endpointID }).base64EncodedString()
    }
    /// One-based host label. This is not an FPGA routing register write.
    public func hostChannel(for endpoint: LegacyPhysicalEndpoint) -> Int? {
        entries.first { $0.endpointID == endpoint.id }.map { (endpoint.port - 1) * 32 + $0.xlinkSlot + 1 }
    }
}
public struct LegacyRoute: Codable, Equatable, Sendable {
    public let endpointID: String
    /// Playback source for output endpoints; capture destination for input endpoints.
    public let hostChannel: Int
    public init(endpointID: String, hostChannel: Int) { self.endpointID = endpointID; self.hostChannel = hostChannel }
}
public struct LegacyRoutingPreset: Codable, Equatable, Sendable {
    public var schemaVersion = 1
    public var name: String
    public let inventorySignature: String
    public let mapSignature: String
    public let sampleRate: UInt32
    public let slotEntries: [LegacySlotEntry]
    public var routes: [LegacyRoute]
    public init(name: String, inventory: LegacyRoutingInventory, map: LegacySlotMap, routes: [LegacyRoute]) {
        self.name = name; self.inventorySignature = inventory.signature
        self.mapSignature = map.signature; self.sampleRate = map.sampleRate
        self.slotEntries = map.entries; self.routes = routes
    }
    /// Returns local intended routes only. No hardware executor exists until the
    /// legacy routing protocol is verified. Saved data never grants write access.
    public func restorePlan(inventory: LegacyRoutingInventory, map: LegacySlotMap,
                            existing: [LegacyRoute], confirmed: Bool,
                            replaceExisting: Bool = false) throws -> [LegacyRoute] {
        guard schemaVersion == 1 else { throw LegacyRoutingError.unsupportedSchema }
        guard confirmed else { throw LegacyRoutingError.unconfirmedRestore }
        guard inventorySignature == inventory.signature, map.inventorySignature == inventory.signature,
              mapSignature == map.signature, sampleRate == map.sampleRate else {
            throw LegacyRoutingError.changedConfiguration
        }
        var destinations = Set<String>(), captureChannels = Set<Int>()
        for route in routes {
            guard (1...64).contains(route.hostChannel), destinations.insert(route.endpointID).inserted,
                  let endpoint = inventory.endpoints.first(where: { $0.id == route.endpointID }),
                  map.hostChannel(for: endpoint) != nil else { throw LegacyRoutingError.invalidMap }
            if endpoint.direction == .input, !captureChannels.insert(route.hostChannel).inserted {
                throw LegacyRoutingError.conflictingRoutes
            }
        }
        if !replaceExisting, !existing.isEmpty, existing != routes { throw LegacyRoutingError.conflictingRoutes }
        return routes
    }
}
public struct LegacyRoutingPresetStore {
    private let defaults: UserDefaults
    private let key: String
    public init(defaults: UserDefaults = .standard, key: String = "maestro.legacyRoutingPresets.v1") {
        self.defaults = defaults; self.key = key
    }
    public func load() throws -> [LegacyRoutingPreset] {
        guard let data = defaults.data(forKey: key) else { return [] }
        guard data.count <= 1_048_576 else { throw LegacyRoutingError.invalidMap }
        let presets = try JSONDecoder().decode([LegacyRoutingPreset].self, from: data)
        guard presets.allSatisfy({ $0.schemaVersion == 1 }) else { throw LegacyRoutingError.unsupportedSchema }
        return presets
    }
    public func save(_ presets: [LegacyRoutingPreset]) throws {
        guard presets.allSatisfy({ $0.schemaVersion == 1 }) else { throw LegacyRoutingError.unsupportedSchema }
        let data = try JSONEncoder().encode(presets)
        guard data.count <= 1_048_576 else { throw LegacyRoutingError.invalidMap }
        defaults.set(data, forKey: key)
    }
}
