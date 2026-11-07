import SwiftUI
import AppKit
import MaestroCore
import LegacyDiagnosticTransport
import CryptoKit

/// Legacy-only workspace. All edits are local; hardware controls remain closed.
public struct LegacyControlWorkspaceView: View {
    let observations: [LegacyConverterObservation]
    private let profiles: [LegacyConverterProfile] = [.ad16x, .da16x, .rosetta200, .rosetta800]
    @State private var configuration = LegacyManualConfiguration()
    @State private var cards: [LegacyDiagnosticCardReport] = []
    @State private var reading = false
    @State private var diagnosticError: String?
    @State private var error: String?
    @State private var slots: [String: Int] = [:]
    @State private var hosts: [String: Int] = [:]
    @State private var mapRate = "48000"
    @State private var clock = LegacyClockPreset()
    @State private var presets: [LegacyRoutingPreset] = []
    @State private var presetName = ""
    @State private var selectedPreset = -1
    @State private var restoreConfirmation = false
    @State private var storeAvailable = false
    @State private var clockStoreAvailable = false
    /// Local presentation only, scoped to the exact converter inventory.
    @State private var stereoLinks = Set<String>()
    @State private var stereoLinkScope: String?
    @State private var stereoLinkStoreAvailable = false

    private var inventory: LegacyRoutingInventory? {
        try? LegacyRoutingInventory(configuration: configuration, profiles: profiles)
    }
    public init(observations: [LegacyConverterObservation] = []) { self.observations = observations }
    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Legacy-Konfiguration · Hardware-Unterstützung noch nicht freigegeben")
                .font(.headline)
            Text("Wandler, Slots, Routing und Clock-Vorgaben werden lokal gespeichert. Sie ändern keine Hardware-Einstellung. Die lokale Konfiguration ist keiner automatisch erkannten Wandlerkette zugeordnet.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button(reading ? "Diagnose läuft…" : "Beide Ports lesen") { refresh() }.disabled(reading)
                Button("Diagnose exportieren…") { exportReport() }.disabled(cards.isEmpty || reading)
            }
            if let diagnosticError { Text(diagnosticError).foregroundStyle(.orange).font(.caption) }
            ForEach(cards) { card in
                VStack(alignment: .leading, spacing: 4) {
                    Text("ThunderBridge \(card.registryID) · Treiber \(card.driverVersion ?? "unbekannt")").font(.subheadline)
                    if let failure = card.error { Text(failure).foregroundStyle(.orange).font(.caption) }
                    ForEach(card.ports, id: \.port) { port in
                        Text("Port \(port.port): Datenstatus \(port.dataState.rawValue), RX-Clock \(clockLabel(port.clockDetected)), Rate \(port.detectedSampleRate.map { "\($0) Hz" } ?? "unbekannt"), PLL-Lock unbekannt")
                            .font(.caption).textSelection(.enabled)
                    }
                    if let snapshot = card.snapshot, snapshot.countersAvailable {
                        Text("IRQ gesamt: \(snapshot.irqCount) · Audio-Wraps Port 1: \(snapshot.port1WrapCount) · Port-2-Fehlerzähler unbekannt")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            DisclosureGroup("Wandler je Port zuordnen") {
                LegacyConverterConfigurationView(observations: observations) { updated in
                    if updated != configuration {
                        configuration = updated; slots = [:]; hosts = [:]
                        loadStereoLinks()
                    }
                }
            }
            DisclosureGroup("Physische Kanäle und 64-Kanal-Routingentwurf") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Slot-Zuordnungen sind manuelle Entwürfe und kein Hardware-Nachweis. DAW 1–32: Port 1; DAW 33–64: Port 2. Der laufende Audiotreiber bleibt bei 32 Kanälen.")
                        .font(.caption).foregroundStyle(.orange)
                    TextField("Sample-Rate des Mapping-Entwurfs", text: $mapRate).frame(maxWidth: 280)
                    if let inventory, !inventory.endpoints.isEmpty {
                        ScrollView([.horizontal, .vertical]) {
                            VStack(alignment: .leading) {
                                ForEach(routingRows(in: inventory)) { row in
                                    routingRow(row, inventory: inventory)
                                }
                            }
                        }.frame(maxHeight: 300)
                    } else {
                        Text("Keine konfigurierten physischen Kanäle. Unbekannte Wandler erhalten keine erfundenen Kanäle.")
                            .font(.caption)
                    }
                    HStack {
                        TextField("Preset-Name", text: $presetName)
                        Button("Entwurf speichern") { saveRouting() }.disabled(!storeAvailable || presetName.isEmpty)
                    }
                    HStack {
                        Picker("Routing-Preset", selection: $selectedPreset) {
                            Text("Auswählen…").tag(-1)
                            ForEach(presets.indices, id: \.self) { Text(presets[$0].name).tag($0) }
                        }
                        Button("Entwurf wiederherstellen…") { restoreConfirmation = true }
                            .disabled(!presets.indices.contains(selectedPreset))
                    }
                    Button("Auf Hardware anwenden – noch nicht freigegeben") {}.disabled(true)
                }
            }
            DisclosureGroup("Legacy-Clock Internal / External") {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Lokale Clock-Vorgabe", selection: $clock.source) {
                        Text("Internal").tag(LegacyClockPreference.internalClock)
                        Text("External Word Clock").tag(LegacyClockPreference.externalWordClock)
                    }
                    Text("Big Ben ist optional. Unterstützte Sample-Rates und tatsächlicher Lock sind noch nicht verifiziert. RX-Clock-Erkennung bestätigt keinen PLL-Lock. Bei Clock-Verlust erfolgt keine automatische Quellenumschaltung.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Clock-Vorgabe lokal speichern") { saveClock() }.disabled(!clockStoreAvailable)
                    Button("Hardware-Clock umschalten – noch nicht freigegeben") {}.disabled(true)
                }
            }
            if let error { Text(error).foregroundStyle(.red).font(.caption).textSelection(.enabled) }
        }
        .onAppear { loadPresets(); loadStereoLinks() }
        .confirmationDialog("Bestehenden lokalen Routingentwurf ersetzen?", isPresented: $restoreConfirmation) {
            Button("Lokalen Entwurf ersetzen") { restoreRouting() }
            Button("Abbrechen", role: .cancel) {}
        } message: { Text("Hardware-Routing wird nicht verändert. Die Wandlerkonfiguration muss zum Preset passen.") }
    }
    private struct RoutingRow: Identifiable {
        let left: LegacyPhysicalEndpoint
        let right: LegacyPhysicalEndpoint?
        var id: String { left.id }
    }

    /// Pair by physical channel numbering, never by XLink slot or host route.
    /// A converter/port/direction/media boundary is never crossed.
    private func stereoPartner(for left: LegacyPhysicalEndpoint,
                               in inventory: LegacyRoutingInventory) -> LegacyPhysicalEndpoint? {
        guard left.channel > 0, !left.channel.isMultiple(of: 2) else { return nil }
        return inventory.endpoints.first {
            $0.deviceID == left.deviceID && $0.port == left.port &&
            $0.direction == left.direction && $0.media == left.media &&
            $0.channel == left.channel + 1
        }
    }

    private func routingRows(in inventory: LegacyRoutingInventory) -> [RoutingRow] {
        var consumed = Set<String>()
        return inventory.endpoints.compactMap { endpoint in
            guard !consumed.contains(endpoint.id) else { return nil }
            consumed.insert(endpoint.id)
            if stereoLinks.contains(endpoint.id), let right = stereoPartner(for: endpoint, in: inventory),
               !consumed.contains(right.id) {
                consumed.insert(right.id)
                return RoutingRow(left: endpoint, right: right)
            }
            return RoutingRow(left: endpoint, right: nil)
        }
    }

    @ViewBuilder
    private func routingRow(_ row: RoutingRow, inventory: LegacyRoutingInventory) -> some View {
        if let right = row.right {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Port \(row.left.port) · \(row.left.profileID) · \(row.left.media.rawValue) \(row.left.direction.rawValue) \(row.left.channel)/\(right.channel) · Stereo")
                        .font(.caption.bold())
                    Spacer()
                    Button("Trennen") { setStereoLink(row.left, enabled: false, inventory: inventory) }
                        .disabled(!stereoLinkStoreAvailable)
                }
                Text("Routingentwurf ohne Hardwarepegel: Pegelangleichung ist hier nicht verfügbar.")
                    .font(.caption2).foregroundStyle(.secondary)
                Picker(row.left.direction == .output ? "DAW-Stereoquelle" : "DAW-Stereoziel",
                       selection: stereoHostBinding(left: row.left, right: right)) {
                    Text("Individuelle L/R-Routen").tag(-1)
                    Text("Keine Route").tag(0)
                    ForEach(Array(stride(from: 1, through: 63, by: 2)), id: \.self) { first in
                        Text("DAW \(first)/\(first + 1)").tag(first)
                    }
                }
                .frame(width: 300)
                .disabled(!hasExplicitSlot(row.left.id) || !hasExplicitSlot(right.id))
                .help("Ändert nur den lokalen Routingentwurf für L und R. Beide XLink-Slots müssen ausdrücklich zugeordnet sein.")
                endpointControls(row.left, side: "L")
                endpointControls(right, side: "R")
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(0.08)))
        } else {
            HStack {
                endpointControls(row.left)
                if let right = stereoPartner(for: row.left, in: inventory) {
                    Button("Stereo \(row.left.channel)/\(right.channel)") {
                        setStereoLink(row.left, enabled: true, inventory: inventory)
                    }
                    .disabled(!stereoLinkStoreAvailable)
                    .help("Verbindet nur die Darstellung. Einzelne Slots und Routen bleiben erhalten; Hardwarepegel sind in dieser Ansicht unbekannt.")
                }
            }
        }
    }

    private func endpointControls(_ endpoint: LegacyPhysicalEndpoint, side: String? = nil) -> some View {
        HStack {
            Text(side.map { "\($0) · \(endpoint.label)" } ?? endpoint.label)
                .frame(width: 330, alignment: .leading)
            Picker("XLink-Slot", selection: slotBinding(endpoint.id)) {
                Text("Unbekannt").tag(-1)
                ForEach(0..<32, id: \.self) { Text("Slot \($0 + 1)").tag($0) }
            }.frame(width: 170)
            Picker(endpoint.direction == .output ? "DAW-Quelle" : "DAW-Ziel", selection: hostBinding(endpoint.id)) {
                Text("Keine Route").tag(0)
                ForEach(1...64, id: \.self) { Text("DAW \($0)").tag($0) }
            }.frame(width: 180).disabled(!hasExplicitSlot(endpoint.id))
        }.font(.caption)
    }

    private func hasExplicitSlot(_ id: String) -> Bool {
        slots[id].map { (0..<32).contains($0) } ?? false
    }

    private func stereoHostBinding(left: LegacyPhysicalEndpoint, right: LegacyPhysicalEndpoint) -> Binding<Int> {
        Binding(get: {
            let first = hosts[left.id] ?? 0
            let second = hosts[right.id] ?? 0
            if first == 0 && second == 0 { return 0 }
            return (1...63).contains(first) && !first.isMultiple(of: 2) && second == first + 1 ? first : -1
        }, set: { first in
            // Linking never calls this setter. Only an explicit DAW-pair choice
            // can replace the two intended host routes; slots remain untouched.
            guard hasExplicitSlot(left.id), hasExplicitSlot(right.id) else { return }
            if first == 0 {
                hosts[left.id] = nil; hosts[right.id] = nil
            } else if (1...63).contains(first), !first.isMultiple(of: 2) {
                hosts[left.id] = first; hosts[right.id] = first + 1
            }
        })
    }

    private func stereoScope(for inventory: LegacyRoutingInventory) -> String {
        let digest = SHA256.hash(data: Data(inventory.signature.utf8))
            .map { String(format: "%02x", $0) }.joined()
        return "maestro.legacyStereoLinks.v1.\(digest)"
    }

    private func loadStereoLinks() {
        guard let inventory else {
            stereoLinks = []; stereoLinkScope = nil; stereoLinkStoreAvailable = false
            return
        }
        let key = stereoScope(for: inventory)
        guard key != stereoLinkScope || !stereoLinkStoreAvailable else { return }
        stereoLinkScope = key
        do {
            let saved: [String]
            if let stored = UserDefaults.standard.object(forKey: key) {
                guard let data = stored as? Data, data.count <= 1_048_576 else {
                    throw LegacyRoutingError.invalidInventory
                }
                saved = try JSONDecoder().decode([String].self, from: data)
            } else { saved = [] }
            let eligible = Set(inventory.endpoints.filter { stereoPartner(for: $0, in: inventory) != nil }.map(\.id))
            stereoLinks = Set(saved).intersection(eligible)
            stereoLinkStoreAvailable = true
        } catch {
            stereoLinks = []; stereoLinkStoreAvailable = false
            self.error = "Stereo-Verknüpfungen nicht lesbar; nichts überschrieben: \(error)"
        }
    }

    private func setStereoLink(_ left: LegacyPhysicalEndpoint, enabled: Bool, inventory: LegacyRoutingInventory) {
        guard stereoLinkStoreAvailable, stereoScope(for: inventory) == stereoLinkScope,
              stereoPartner(for: left, in: inventory) != nil else { return }
        var updated = stereoLinks
        if enabled { updated.insert(left.id) } else { updated.remove(left.id) }
        let eligible = Set(inventory.endpoints.filter { stereoPartner(for: $0, in: inventory) != nil }.map(\.id))
        updated.formIntersection(eligible)
        do {
            let data = try JSONEncoder().encode(updated.sorted())
            UserDefaults.standard.set(data, forKey: stereoScope(for: inventory))
            stereoLinks = updated
        } catch {
            self.error = "Stereo-Verknüpfung nicht gespeichert: \(error)"
        }
    }

    private func slotBinding(_ id: String) -> Binding<Int> {
        Binding(get: { slots[id] ?? -1 }, set: { value in slots[id] = value; if value < 0 { hosts[id] = nil } })
    }
    private func hostBinding(_ id: String) -> Binding<Int> {
        Binding(get: { hosts[id] ?? 0 }, set: { hosts[id] = $0 })
    }
    private func clockLabel(_ value: Bool?) -> String { value.map { $0 ? "erkannt" : "fehlt" } ?? "unbekannt" }
    private func refresh() {
        reading = true; cards = []; diagnosticError = nil
        Task { @MainActor in
            do {
                cards = try await Task.detached { try LegacyPassiveDiagnostics.collect() }.value
                if cards.isEmpty { diagnosticError = "Kein erreichbarer ThunderBridge-Diagnosedienst gefunden." }
            } catch { diagnosticError = "Diagnose fehlgeschlagen: \(error)" }
            reading = false
        }
    }
    private func exportReport() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "legacy-dual-port-report.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(cards).write(to: url, options: .atomic)
        } catch { self.error = "Export fehlgeschlagen: \(error)" }
    }
    private func loadPresets() {
        do { presets = try LegacyRoutingPresetStore().load(); storeAvailable = true }
        catch { storeAvailable = false; self.error = "Routing-Presets nicht lesbar; nichts überschrieben: \(error)" }
        do { clock = try LegacyClockPresetStore().load(); clockStoreAvailable = true }
        catch { clockStoreAvailable = false; self.error = "Clock-Preset nicht lesbar; nichts überschrieben: \(error)" }
    }
    private func localMap(_ inventory: LegacyRoutingInventory) throws -> LegacySlotMap {
        guard let rate = UInt32(mapRate) else { throw LegacyRoutingError.unsupportedRate }
        return try .init(entries: slots.filter { $0.value >= 0 }.map { .init(endpointID: $0.key, xlinkSlot: $0.value) },
                         inventory: inventory, sampleRate: rate, evidenceReference: "operator draft; not hardware-verified")
    }
    private func saveRouting() {
        do {
            guard storeAvailable, let inventory, !presets.contains(where: { $0.name == presetName }) else {
                throw LegacyRoutingError.conflictingRoutes
            }
            let map = try localMap(inventory)
            let routes = hosts.filter { $0.value > 0 }.map { LegacyRoute(endpointID: $0.key, hostChannel: $0.value) }
                .sorted { $0.endpointID < $1.endpointID }
            let preset = LegacyRoutingPreset(name: presetName, inventory: inventory, map: map, routes: routes)
            _ = try preset.restorePlan(inventory: inventory, map: map, existing: [], confirmed: true)
            var updated = presets; updated.append(preset)
            try LegacyRoutingPresetStore().save(updated); presets = updated; error = nil
        } catch { self.error = "Routingentwurf nicht gespeichert: \(error)" }
    }
    private func restoreRouting() {
        do {
            guard presets.indices.contains(selectedPreset), let inventory else { throw LegacyRoutingError.invalidInventory }
            let preset = presets[selectedPreset]
            let map = try LegacySlotMap(entries: preset.slotEntries, inventory: inventory, sampleRate: preset.sampleRate,
                                        evidenceReference: "restored local draft; not hardware-verified")
            let routes = try preset.restorePlan(inventory: inventory, map: map, existing: [], confirmed: true, replaceExisting: true)
            slots = Dictionary(uniqueKeysWithValues: map.entries.map { ($0.endpointID, $0.xlinkSlot) })
            hosts = Dictionary(uniqueKeysWithValues: routes.map { ($0.endpointID, $0.hostChannel) })
            mapRate = String(preset.sampleRate); error = nil
        } catch { self.error = "Preset passt nicht zur aktuellen Konfiguration: \(error)" }
    }
    private func saveClock() {
        do { try LegacyClockPresetStore().save(clock); error = nil }
        catch { self.error = "Clock-Vorgabe nicht gespeichert: \(error)" }
    }
}
