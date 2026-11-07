import SwiftUI
import MaestroCore

/// Manual fallback for legacy X-Symphony converter identities.
/// The current ThunderBridge dext cannot enumerate individual 16X units:
/// observations remain empty until a trustworthy read-only probe is available.
/// This UI only saves local metadata. It NEVER changes converter hardware.
struct LegacyConverterConfigurationView: View {
    let observations: [LegacyConverterObservation]

    @State private var configuration = LegacyManualConfiguration()
    @State private var confirmedThisSession = Set<UUID>()
    @State private var skippedThisSession = Set<UUID>()
    @State private var automaticThisSession = Set<UUID>()
    @State private var loadingFailed = false
    @State private var didLoad = false
    @State private var errorMessage: String?
    @State private var editorID: UUID?
    @State private var editorProfileID = ""
    @State private var editorMode: LegacyConverterMode = .standard
    @State private var showingEditor = false

    // Extend by registering supported converter capabilities, not changing this
    // view for a particular rack or hard-coding a device count or channel order.
    private let profiles: [LegacyConverterProfile] = [
        .ad16x, .da16x, .rosetta800, .rosetta200
    ]

    private var observationByPosition: [String: LegacyConverterObservation] {
        Dictionary(observations.map { (key($0.port, $0.position), $0) },
                   uniquingKeysWith: { first, _ in first })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Manuelle Zuordnung für Legacy-Wandler (AD/DA/Rosetta). Diese Einstellungen ändern noch kein Hardware-Routing.",
                  systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)

            if observations.isEmpty {
                Text("Die aktuelle ThunderBridge-Treiberversion erkennt einzelne Legacy-Wandler noch nicht automatisch. Geräte können hier pro Port manuell eingetragen werden; die Angaben gelten bis zu einer Hardwareprüfung als unbestätigt.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            ForEach(1...LegacyTopologyPlanner.portCount, id: \.self) { port in
                VStack(alignment: .leading, spacing: 8) {
                    Text("Symphony Port \(port)").font(.headline)
                    let portDevices = configuration.assignments
                        .filter { $0.port == port }.sorted { $0.position < $1.position }
                    if portDevices.isEmpty {
                        Text("Keine Gerätezuordnung vorhanden")
                            .foregroundStyle(.tertiary)
                    }
                    ForEach(portDevices) { slot in
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Gerät \(slot.position): \(profileName(for: slot))")
                                    .font(.body)
                                Text(statusLabel(for: slot))
                                    .font(.caption)
                                    .foregroundStyle(confirmedThisSession.contains(slot.id)
                                        ? Color.green : Color.secondary)
                            }
                            Spacer()
                            Button("Zuordnen…") { edit(slot.id) }
                                .controlSize(.small)
                            Button {
                                remove(slot)
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                            .help("Nur lokale Zuordnung entfernen")
                        }
                    }
                    Button {
                        appendUnknown(to: port)
                    } label: {
                        Label("Wandler hinzufügen…", systemImage: "plus.circle")
                    }
                    .disabled(loadingFailed)
                    .controlSize(.small)
                }
            }

            let pending = configuration.assignments.filter {
                !$0.isComplete || !confirmedThisSession.contains($0.id) && !automaticThisSession.contains($0.id)
            }
            if !pending.isEmpty {
                HStack {
                    Label("\(pending.count) Zuordnung(en) für diese Sitzung unbestätigt",
                          systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Spacer()
                    Button("Nächsten prüfen") {
                        if let next = pending.first { edit(next.id) }
                    }
                    .controlSize(.small)
                }
            }
            if let summary = channelSummary() {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .sheet(isPresented: $showingEditor, onDismiss: {
            if !observations.isEmpty {
                Task { @MainActor in
                    await Task.yield()
                    promptNextObservedAmbiguity()
                }
            }
        }) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Wandler zuordnen").font(.title3.bold())
                if let slot = currentEditedSlot() {
                    Text("Port \(slot.port) · Gerät \(slot.position)")
                        .foregroundStyle(.secondary)
                }
                Text("Wenn der Wandler nicht eindeutig erkannt werden kann, Gerätetyp und Betriebsart manuell auswählen. Der Advanced-Modus wird am Gerät eingestellt, nicht hier umgeschaltet.")
                    .font(.caption)
                Picker("Gerätetyp", selection: $editorProfileID) {
                    Text("Unbekannt").tag("")
                    ForEach(profiles, id: \.id) { profile in
                        Text(profile.name).tag(profile.id)
                    }
                }
                .onChange(of: editorProfileID) { _, selected in
                    if let profile = profiles.first(where: { $0.id == selected }),
                       profile.advanced == nil {
                        editorMode = .standard
                    }
                }
                Picker("Betriebsmodus", selection: $editorMode) {
                    Text("Standard").tag(LegacyConverterMode.standard)
                    if profiles.first(where: { $0.id == editorProfileID })?.advanced != nil {
                        Text("Advanced").tag(LegacyConverterMode.advanced)
                    }
                }
                .disabled(editorProfileID.isEmpty)
                HStack {
                    Button("Später") {
                        if let editorID { skippedThisSession.insert(editorID) }
                        showingEditor = false
                    }
                    Spacer()
                    Button("Zuordnung bestätigen") { saveEditedSelection() }
                        .buttonStyle(.borderedProminent)
                        .disabled(editorProfileID.isEmpty || loadingFailed)
                }
            }
            .padding(24)
            .frame(width: 480)
        }
        .onAppear {
            guard !didLoad else { return }
            load()
            processObservations()
        }
        .onChange(of: observations) { _, _ in
            guard didLoad && !loadingFailed else { return }
            confirmedThisSession.removeAll()
            skippedThisSession.removeAll()
            automaticThisSession.removeAll()
            processObservations()
        }
    }

    private func key(_ port: Int, _ position: Int) -> String { "\(port):\(position)" }

    private func profileName(for slot: LegacyConverterAssignment) -> String {
        guard let id = slot.profileID, let profile = profiles.first(where: { $0.id == id }) else {
            return "Unbekannt"
        }
        return profile.name + (slot.mode == .advanced ? " (Advanced)" : "")
    }

    private func statusLabel(for slot: LegacyConverterAssignment) -> String {
        if automaticThisSession.contains(slot.id) { return "Automatisch identifiziert (diese Sitzung)" }
        if confirmedThisSession.contains(slot.id) { return "Manuell bestätigt (nicht hardwaregeprüft)" }
        if !slot.isComplete { return "Zuordnung erforderlich" }
        return "Gespeicherte Auswahl – erneut bestätigen"
    }

    private func currentEditedSlot() -> LegacyConverterAssignment? {
        guard let editorID else { return nil }
        return configuration.assignments.first { $0.id == editorID }
    }

    private func load() {
        do {
            configuration = try LegacyAssignmentStore().load()
            didLoad = true
            loadingFailed = false
        } catch {
            loadingFailed = true
            didLoad = true
            errorMessage = "Gespeicherte Legacy-Zuordnungen können nicht gelesen werden (\(error)). Nichts wurde überschrieben."
        }
    }

    @discardableResult
    private func commit(_ updated: LegacyManualConfiguration) -> Bool {
        do {
            try LegacyAssignmentStore().save(updated)
            configuration = updated
            errorMessage = nil
            return true
        } catch {
            errorMessage = "Zuordnung konnte nicht gespeichert werden: \(error)"
            return false
        }
    }

    private func appendUnknown(to port: Int) {
        guard !loadingFailed else { return }
        var updated = configuration
        let index = (updated.assignments.filter { $0.port == port }.map(\.position).max() ?? 0) + 1
        let slot = LegacyConverterAssignment(port: port, position: index)
        updated.assignments.append(slot)
        guard commit(updated) else { return }
        edit(slot.id)
    }

    private func edit(_ id: UUID) {
        guard let slot = configuration.assignments.first(where: { $0.id == id }) else { return }
        editorID = id
        editorProfileID = slot.profileID ?? ""
        editorMode = slot.mode ?? .standard
        showingEditor = true
    }

    private func saveEditedSelection() {
        guard let id = editorID,
              let i = configuration.assignments.firstIndex(where: { $0.id == id }),
              let profile = profiles.first(where: { $0.id == editorProfileID }),
              profile.channels(for: editorMode) != nil else { return }
        var updated = configuration
        updated.assignments[i].profileID = editorProfileID
        updated.assignments[i].mode = editorMode
        let slot = updated.assignments[i]
        // Identity is never invented. Only a trusted live read can attach it.
        updated.assignments[i].hardwareIdentity =
            observationByPosition[key(slot.port, slot.position)]?.hardwareIdentity
        guard commit(updated) else { return }
        confirmedThisSession.insert(id)
        skippedThisSession.remove(id)
        showingEditor = false
    }

    private func remove(_ slot: LegacyConverterAssignment) {
        var updated = configuration
        updated.assignments.removeAll { $0.id == slot.id }
        for i in updated.assignments.indices where updated.assignments[i].port == slot.port &&
                updated.assignments[i].position > slot.position {
            updated.assignments[i].position -= 1
        }
        guard commit(updated) else { return }
        confirmedThisSession.removeAll()
        automaticThisSession.removeAll()
        skippedThisSession.removeAll()
    }

    private func processObservations() {
        guard !loadingFailed && !observations.isEmpty else { return }
        do {
            let resolutions = try LegacyAssignmentResolver.resolve(
                observations: observations, saved: configuration, profiles: profiles)
            var updated = configuration
            for resolution in resolutions {
                let port = resolution.observation.port
                let position = resolution.observation.position
                if let i = updated.assignments.firstIndex(where: {
                    $0.port == port && $0.position == position
                }) {
                    let oldID = updated.assignments[i].hardwareIdentity
                    let newID = resolution.observation.hardwareIdentity
                    if oldID != nil && newID != nil && oldID != newID {
                        updated.assignments[i].profileID = nil
                        updated.assignments[i].mode = nil
                        updated.assignments[i].hardwareIdentity = newID
                    }
                    if resolution.status == .automaticallyIdentified {
                        updated.assignments[i].profileID = resolution.proposedProfileID
                        updated.assignments[i].mode = resolution.proposedMode
                        updated.assignments[i].hardwareIdentity = newID
                        automaticThisSession.insert(updated.assignments[i].id)
                    }
                } else {
                    let newSlot = LegacyConverterAssignment(
                        port: port, position: position,
                        profileID: resolution.status == .automaticallyIdentified
                            ? resolution.proposedProfileID : nil,
                        mode: resolution.status == .automaticallyIdentified
                            ? resolution.proposedMode : nil,
                        hardwareIdentity: resolution.observation.hardwareIdentity)
                    updated.assignments.append(newSlot)
                    if resolution.status == .automaticallyIdentified {
                        automaticThisSession.insert(newSlot.id)
                    }
                }
            }
            guard updated == configuration || commit(updated) else { return }
            promptNextObservedAmbiguity()
        } catch {
            errorMessage = "Fehler bei der Geräteerkennung: \(error)"
        }
    }

    private func promptNextObservedAmbiguity() {
        guard !showingEditor && !observations.isEmpty else { return }
        guard let result = try? LegacyAssignmentResolver.resolve(
            observations: observations, saved: configuration, profiles: profiles) else { return }
        for item in result where item.needsUserInput {
            guard let slot = configuration.assignments.first(where: {
                $0.port == item.observation.port && $0.position == item.observation.position
            }), !confirmedThisSession.contains(slot.id), !skippedThisSession.contains(slot.id) else {
                continue
            }
            edit(slot.id)
            if let proposed = item.proposedProfileID { editorProfileID = proposed }
            if let proposed = item.proposedMode { editorMode = proposed }
            break
        }
    }

    private func channelSummary() -> String? {
        let unresolved = configuration.assignments.filter { !$0.isComplete }.count
        let ports = (1...LegacyTopologyPlanner.portCount).map { port in
            LegacyPort(number: port, chain: configuration.assignments
                .filter { $0.port == port && $0.isComplete }
                .sorted { $0.position < $1.position }
                .compactMap { slot in
                    guard let id = slot.profileID, let mode = slot.mode,
                          let profile = profiles.first(where: { $0.id == id }) else { return nil }
                    return LegacyChainDevice(id: slot.id.uuidString, profile: profile,
                                             mode: mode, identification: .manual)
                })
        }
        do {
            let plan = try LegacyTopologyPlanner.plan(.init(ports: ports))
            return "Nur logische Vorschau: \(plan.usedInputs) Eingänge / \(plan.usedOutputs) Ausgänge" +
                (unresolved == 0 ? "" : " (\(unresolved) unbekannt)") +
                ". Noch keine 64-Kanal-Audiofreigabe."
        } catch {
            return "Ungültige Kanalbelegung: \(error). Keine Hardwareänderung ausgeführt."
        }
    }
}
