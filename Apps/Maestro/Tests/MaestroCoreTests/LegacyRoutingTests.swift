import Foundation
import Testing
@testable import MaestroCore
@Suite("Legacy physical endpoints and explicit slot routing")
struct LegacyRoutingTests {
    let profiles: [LegacyConverterProfile] = [.ad16x, .da16x, .rosetta200]
    func inventory(_ config: LegacyManualConfiguration) throws -> LegacyRoutingInventory {
        try .init(configuration: config, profiles: profiles)
    }
    func fixture() throws -> (LegacyManualConfiguration, LegacyRoutingInventory, LegacySlotMap) {
        let config = LegacyManualConfiguration(assignments: [
            .init(port: 2, position: 1, profileID: "apogee.da16x", mode: .advanced)
        ])
        let catalog = try inventory(config)
        let entries = catalog.endpoints.map { LegacySlotEntry(endpointID: $0.id, xlinkSlot: 31 - ($0.channel - 1)) }
        return (config, catalog, try .init(entries: entries, inventory: catalog, sampleRate: 48000,
                                          evidenceReference: "synthetic-test-only"))
    }
    @Test func explicitNonContiguousSlotsAndAdvancedDigitalInputs() throws {
        let (_, catalog, map) = try fixture()
        #expect(catalog.endpoints.count == 32)
        #expect(catalog.endpoints.filter { $0.media == .digital && $0.direction == .input }.count == 16)
        #expect(map.hostChannel(for: catalog.endpoints[0]) == 64)
        #expect(map.hostChannel(for: catalog.endpoints[15]) == 49)
        #expect(try inventory(.init(assignments: [.init(port: 1, position: 1)])).endpoints.isEmpty)
    }
    @Test func rejectsDuplicateOrOutOfRangeSlotsAndMissingEndpoints() throws {
        let (_, catalog, _) = try fixture()
        for entries in [[LegacySlotEntry(endpointID: "missing", xlinkSlot: 0)],
                        [.init(endpointID: catalog.endpoints[0].id, xlinkSlot: 32)],
                        [.init(endpointID: catalog.endpoints[0].id, xlinkSlot: 0),
                         .init(endpointID: catalog.endpoints[1].id, xlinkSlot: 0)]] {
            #expect(throws: LegacyRoutingError.self) {
                try LegacySlotMap(entries: entries, inventory: catalog, sampleRate: 48000, evidenceReference: "test")
            }
        }
    }
    @Test func presetRoundTripAndExplicitOverwrite() throws {
        let (_, catalog, map) = try fixture()
        let route = LegacyRoute(endpointID: catalog.endpoints.last!.id, hostChannel: 7)
        let preset = LegacyRoutingPreset(name: "test", inventory: catalog, map: map, routes: [route])
        let decoded = try JSONDecoder().decode(LegacyRoutingPreset.self, from: JSONEncoder().encode(preset))
        #expect(decoded == preset)
        #expect(try decoded.restorePlan(inventory: catalog, map: map, existing: [], confirmed: true) == [route])
        #expect(throws: LegacyRoutingError.unconfirmedRestore) {
            try decoded.restorePlan(inventory: catalog, map: map, existing: [], confirmed: false)
        }
        let current = [LegacyRoute(endpointID: route.endpointID, hostChannel: 8)]
        #expect(throws: LegacyRoutingError.conflictingRoutes) {
            try decoded.restorePlan(inventory: catalog, map: map, existing: current, confirmed: true)
        }
        #expect(try decoded.restorePlan(inventory: catalog, map: map, existing: current,
                                        confirmed: true, replaceExisting: true) == [route])
    }
    @Test func changedModeOrderIdentityOrRateInvalidatesPreset() throws {
        let (config, catalog, map) = try fixture()
        let preset = LegacyRoutingPreset(name: "test", inventory: catalog, map: map, routes: [])
        var changed = config; changed.assignments[0].mode = .standard
        let newCatalog = try inventory(changed)
        #expect(throws: LegacyRoutingError.changedConfiguration) {
            try preset.restorePlan(inventory: newCatalog, map: map, existing: [], confirmed: true)
        }
        let newRate = try LegacySlotMap(entries: map.entries, inventory: catalog, sampleRate: 96000, evidenceReference: "test")
        #expect(throws: LegacyRoutingError.changedConfiguration) {
            try preset.restorePlan(inventory: catalog, map: newRate, existing: [], confirmed: true)
        }
    }
    @Test func corruptSavedDataIsNotOverwritten() throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let key = "presets"; let bad = Data("not-json".utf8)
        defaults.set(bad, forKey: key)
        let store = LegacyRoutingPresetStore(defaults: defaults, key: key)
        #expect(throws: (any Error).self) { try store.load() }
        #expect(defaults.data(forKey: key) == bad)
        let (_, catalog, map) = try fixture()
        let preset = LegacyRoutingPreset(name: "saved", inventory: catalog, map: map, routes: [])
        try store.save([preset]); #expect(try store.load() == [preset])
        defaults.removeObject(forKey: key)
    }
}
