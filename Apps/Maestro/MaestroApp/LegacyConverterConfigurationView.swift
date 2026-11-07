import SwiftUI
import MaestroCore

/// Manual fallback for legacy X-Symphony converter identities.
/// The current ThunderBridge dext cannot enumerate individual 16X units:
/// observations remain empty until a trustworthy read-only probe is available.
/// This UI only saves local metadata. It NEVER changes converter hardware.
struct LegacyConverterConfigurationView: View {
    let observations: [LegacyConverterObservation]
    var onConfigurationChange: (LegacyManualConfiguration) -> Void = { _ in }

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
            Label("Assign legacy converters (AD/DA/Rosetta). This configuration does not change hardware routing.",
                  systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)

            if observations.isEmpty {
                Text("This ThunderBridge driver does not yet enumerate individual legacy converters. You can enter them manually for each port. Entries are unverified until hardware discovery becomes available.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            ForEach(1...LegacyTopologyPlanner.portCount, id: \.self) { port in
                VStack(alignment: .leading, spacing: 8) {
                    Text("Symphony Port \(port)").font(.headline)
                    let portDevices = configuration.assignments
                        .filter { $0.port == port }.sorted { $0.position < $1.position }
                    if portDevices.isEmpty {
                        Text("No converter assignments")
                            .foregroundStyle(.tertiary)
                    }
                    ForEach(portDevices) { slot in
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Converter \(slot.position): \(profileName(for: slot))")
                                    .font(.body)
                                Text(statusLabel(for: slot))
                                    .font(.caption)
                                    .foregroundStyle(confirmedThisSession.contains(slot.id)
                                        ? Color.green : Color.secondary)
                            }
                            Spacer()
                            Button("Assign…") { edit(slot.id) }
                                .controlSize(.small)
                            Button {
                                remove(slot)
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                            .help("Remove this local assignment only")
                        }
                    }
                    Button {
                        appendUnknown(to: port)
                    } label: {
                        Label("Add converter…", systemImage: "plus.circle")
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
                    Label("\(pending.count) assignment(s) need confirmation this session",
                          systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Spacer()
                    Button("Review next") {
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
                Text("Assign converter").font(.title3.bold())
                if let slot = currentEditedSlot() {
                    Text("Port \(slot.port) · Converter \(slot.position)")
                        .foregroundStyle(.secondary)
                }
                Text("If identification is ambiguous, select the converter model and operating mode. Advanced mode is configured on the physical converter; this panel cannot switch it.")
                    .font(.caption)
                Picker("Converter model", selection: $editorProfileID) {
                    Text("Unknown").tag("")
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
                Picker("Operating mode", selection: $editorMode) {
                    Text("Standard").tag(LegacyConverterMode.standard)
                    if profiles.first(where: { $0.id == editorProfileID })?.advanced != nil {
                        Text("Advanced").tag(LegacyConverterMode.advanced)
                    }
                }
                .disabled(editorProfileID.isEmpty)
                HStack {
                    Button("Later") {
                        if let editorID { skippedThisSession.insert(editorID) }
                        showingEditor = false
                    }
                    Spacer()
                    Button("Save local assignment") { saveEditedSelection() }
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
            return "Unknown"
        }
        return profile.name + (slot.mode == .advanced ? " (Advanced)" : "")
    }

    private func statusLabel(for slot: LegacyConverterAssignment) -> String {
        if automaticThisSession.contains(slot.id) { return "Automatically identified (current session)" }
        if confirmedThisSession.contains(slot.id) { return "Manually confirmed (not hardware-verified)" }
        if !slot.isComplete { return "Assignment required" }
        return "Saved choice – confirm again"
    }

    private func currentEditedSlot() -> LegacyConverterAssignment? {
        guard let editorID else { return nil }
        return configuration.assignments.first { $0.id == editorID }
    }

    private func load() {
        do {
            configuration = try LegacyAssignmentStore().load()
            onConfigurationChange(configuration)
            didLoad = true
            loadingFailed = false
        } catch {
            loadingFailed = true
            didLoad = true
            errorMessage = "Saved legacy assignments could not be read (\(error)). No data was overwritten."
        }
    }

    @discardableResult
    private func commit(_ updated: LegacyManualConfiguration) -> Bool {
        do {
            // Reject invalid 32-channel-per-port plans BEFORE persisting them.
            _ = try LegacyTopologyPlanner.plan(topology(from: updated))
            try LegacyAssignmentStore().save(updated)
            configuration = updated
            onConfigurationChange(updated)
            errorMessage = nil
            return true
        } catch {
            errorMessage = "Could not save assignment: \(error)"
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
            observationByPosition[key(slot.port, slot.position)].flatMap { observation in
                observation.identityVerified ? observation.hardwareIdentity : nil
            }
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
                    let newID = resolution.observation.identityVerified
                        ? resolution.observation.hardwareIdentity : nil
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
                        hardwareIdentity: resolution.observation.identityVerified
                            ? resolution.observation.hardwareIdentity : nil)
                    updated.assignments.append(newSlot)
                    if resolution.status == .automaticallyIdentified {
                        automaticThisSession.insert(newSlot.id)
                    }
                }
            }
            guard updated == configuration || commit(updated) else { return }
            promptNextObservedAmbiguity()
        } catch {
            errorMessage = "Converter discovery error: \(error)"
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

    private func topology(from config: LegacyManualConfiguration) -> LegacyTopology {
        let ports = (1...LegacyTopologyPlanner.portCount).map { port in
            LegacyPort(number: port, chain: config.assignments
                .filter { $0.port == port && $0.isComplete }
                .sorted { $0.position < $1.position }
                .compactMap { slot in
                    guard let id = slot.profileID, let mode = slot.mode,
                          let profile = profiles.first(where: { $0.id == id }) else { return nil }
                    return LegacyChainDevice(id: slot.id.uuidString, profile: profile,
                                             mode: mode, identification: .manual)
                })
        }
        return LegacyTopology(ports: ports)
    }

    private func channelSummary() -> String? {
        let unresolved = configuration.assignments.filter { !$0.isComplete }.count
        do {
            let plan = try LegacyTopologyPlanner.plan(topology(from: configuration))
            return "Logical preview only: \(plan.usedInputs) inputs / \(plan.usedOutputs) outputs" +
                (unresolved == 0 ? "" : " (\(unresolved) unknown)") +
                ". 64-channel audio is not enabled."
        } catch {
            return "Invalid channel allocation: \(error). No hardware changes made."
        }
    }
}
