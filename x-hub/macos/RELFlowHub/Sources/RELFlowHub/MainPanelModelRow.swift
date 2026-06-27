import SwiftUI
import AppKit
import RELFlowHubCore

private struct LocalModelHealthStatusLine: View {
    let presentation: LocalModelHealthPresentation

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(presentation.badgeText)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(presentation.tint)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(presentation.tint.opacity(0.12))
                .clipShape(Capsule())
                .fixedSize()

            Text(presentation.detailText)
                .font(.caption2)
                .foregroundStyle(presentation.tint)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct ModelRow: View {
    let m: HubModel
    let cost: Double

    @State private var showEditRoles: Bool = false
    @State private var showRemoveDialog: Bool = false
    @EnvironmentObject private var store: HubStore
    @ObservedObject private var modelStore = ModelStore.shared

    var body: some View {
        let pending = modelStore.pendingAction(for: m.id)
        let lastErr = modelStore.lastError(for: m.id)
        let bench = modelStore.benchByModelId[m.id]
        let runtimePresentation = modelStore.localModelRuntimePresentation(for: m)
        let localHealthRecord = store.localModelHealth(for: m.id)
        let isRemote: Bool = {
            let mp = (m.modelPath ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !mp.isEmpty { return false }
            return m.backend.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() != "mlx"
        }()
        let canBench = (runtimePresentation?.supportsBench ?? false) && m.state == .loaded
        let canUnloadBeforeRemove = !isRemote && m.state == .loaded
        let localHealthScanInProgress = store.isLocalModelHealthScanInProgress(for: m.id)
        let canDeleteFiles: Bool = {
            guard let p = m.modelPath, !p.isEmpty else { return false }
            let base = SharedPaths.ensureHubDirectory()
            let managedRoot = base.appendingPathComponent("models", isDirectory: true).path
            return (m.note ?? "") == "managed_copy" || p.hasPrefix(managedRoot + "/")
        }()
        let trialStatus = store.localModelTrialStatus(for: m.id)
        let healthPresentation = isRemote ? nil : LocalModelHealthPresentationSupport.presentation(
            health: localHealthRecord,
            isScanning: localHealthScanInProgress
        )
        let showInlineHealthAction = !isRemote
        let supportedLocalRoutingDescriptors = LocalTaskRoutingCatalog.supportedDescriptors(in: m.taskKinds)
        let hubDefaultLocalTaskSummary = store.hubDefaultLocalTaskSummary(
            forModelId: m.id,
            taskKinds: supportedLocalRoutingDescriptors.map(\.taskKind)
        )

        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(m.name)
                    .font(.subheadline)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    ForEach(displayRoles(), id: \ .self) { r in
                        Text(r)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                    }
                }

                Text(subtitle())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if !isRemote, !supportedLocalRoutingDescriptors.isEmpty {
                    HStack(spacing: 8) {
                        localTaskRoutingMenu(supportedLocalRoutingDescriptors)

                        Text(hubDefaultLocalTaskSummary.isEmpty ? "Supports: \(supportedTaskSummary(supportedLocalRoutingDescriptors))" : "Hub default: \(hubDefaultLocalTaskSummary)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                if let runtimePresentation, !isRemote {
                    lifecycleBadge(runtimePresentation)
                }

                if let healthPresentation {
                    VStack(alignment: .leading, spacing: 4) {
                        LocalModelHealthStatusLine(presentation: healthPresentation)

                        if showInlineHealthAction {
                            localHealthActionButton(
                                disabled: pending != nil || localHealthScanInProgress || trialStatus?.isRunning == true
                            )
                        }
                    }
                } else if showInlineHealthAction {
                    localHealthActionButton(
                        disabled: pending != nil || localHealthScanInProgress || trialStatus?.isRunning == true
                    )
                }

                if let b = bench {
                    Text(benchLine(b))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if let e = lastErr, !e.isEmpty {
                    Text("Error: \(e)")
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .lineLimit(1)
                }

                if let trialStatus {
                    ModelTrialStatusLine(status: trialStatus)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 6) {
                CapacityGauge(percent: min(1.0, max(0.0, cost / 20.0)))
                    .frame(width: 86, height: 10)

                if isRemote {
                    HStack(spacing: 6) {
                        Image(systemName: "cloud")
                        Text("Remote")
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 8) {
                        switch runtimePresentation?.controlMode ?? .mlxLegacy {
                        case .mlxLegacy:
                            if m.state == .loaded {
                                // Icon-only keeps the row compact so actions never clip in the drawer.
                                miniIconButton("Sleep", systemName: "zzz", disabled: pending != nil) { act("sleep") }
                                miniIconButton("Unload", systemName: "eject", disabled: pending != nil) { act("unload") }
                                miniIconButton("Bench", systemName: "speedometer", disabled: pending != nil) { act("bench") }
                            } else {
                                miniIconButton("Load", systemName: "arrow.down.circle", disabled: pending != nil) { act("load") }
                            }
                        case .warmable:
                            if m.state == .loaded {
                                miniIconButton("Unload", systemName: "eject", disabled: pending != nil) { act("unload") }
                            } else if runtimePresentation?.supportsWarmup == true {
                                miniIconButton("Warmup", systemName: "flame", disabled: pending != nil) { act("warmup") }
                            } else {
                                lifecycleSummary(runtimePresentation)
                            }
                        case .ephemeralOnDemand:
                            if m.state == .loaded, runtimePresentation?.supportsUnload == true {
                                miniIconButton("Unload", systemName: "eject", disabled: pending != nil) { act("unload") }
                            } else {
                                lifecycleSummary(runtimePresentation)
                            }
                        }

                        miniIconButton(
                            HubUIStrings.Models.LocalHealth.preflightAction,
                            systemName: "heart.text.square",
                            disabled: pending != nil || localHealthScanInProgress || trialStatus?.isRunning == true
                        ) {
                            store.scanLocalModelHealth(for: [m.id])
                        }

                        if pending != nil || trialStatus?.isRunning == true || localHealthScanInProgress {
                            ProgressView()
                                .controlSize(.mini)
                        }
                    }
                }
            }
            .frame(width: 184, alignment: .trailing)
            .layoutPriority(1)
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button("Roles...") { showEditRoles = true }
            Divider()
            Button("Set Role: General") {
                ModelStore.shared.updateRoles(modelId: m.id, roles: ["general"])
            }
            Button("Set Role: Supervisor") {
                ModelStore.shared.updateRoles(modelId: m.id, roles: ["supervisor"])
            }
            Button("Set Role: Coder") {
                ModelStore.shared.updateRoles(modelId: m.id, roles: ["coder"])
            }
            Button("Set Role: Reviewer") {
                ModelStore.shared.updateRoles(modelId: m.id, roles: ["reviewer"])
            }
            if canBench {
                Divider()
                Button("Bench") { act("bench") }
            }
            Divider()
            Button("Remove...") { showRemoveDialog = true }
        }
        .confirmationDialog("Remove model", isPresented: $showRemoveDialog, titleVisibility: .visible) {
            Button("Remove from Hub", role: .destructive) {
                if m.state == .loaded, canUnloadBeforeRemove {
                    ModelStore.shared.enqueue(action: "unload", modelId: m.id)
                }
                ModelStore.shared.removeModel(modelId: m.id, deleteLocalFiles: false)
            }
            if canDeleteFiles {
                Button("Remove and Delete Local Copy", role: .destructive) {
                    if m.state == .loaded, canUnloadBeforeRemove {
                        ModelStore.shared.enqueue(action: "unload", modelId: m.id)
                    }
                    ModelStore.shared.removeModel(modelId: m.id, deleteLocalFiles: true)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if canDeleteFiles {
                Text("This removes the model from Hub. If you choose 'Delete Local Copy', Hub will delete only the Hub-managed model folder. It will NOT delete arbitrary user folders.")
            } else {
                Text("This removes the model from Hub. Local files will not be deleted.")
            }
        }
        .sheet(isPresented: $showEditRoles) {
            EditRolesSheet(model: m)
        }
    }

    private func displayRoles() -> [String] {
        var seen = Set<String>()
        let roles = (m.roles ?? [])
            .map(HubModelRolePresentation.canonicalRoleToken)
            .filter { !$0.isEmpty && seen.insert($0).inserted }
        if roles.isEmpty {
            return ["General"]
        }
        return Array(roles.prefix(3)).map(HubModelRolePresentation.displayName)
    }

    private func supportedTaskSummary(_ descriptors: [LocalTaskRoutingDescriptor]) -> String {
        descriptors.map(\.shortTitle).joined(separator: ", ")
    }

    private func localTaskRoutingMenu(_ descriptors: [LocalTaskRoutingDescriptor]) -> some View {
        Menu {
            ForEach(descriptors) { descriptor in
                let currentlyBound = store.hubDefaultRoutingModelId(taskType: descriptor.taskKind) == m.id
                Button(currentlyBound ? "Stop using for \(descriptor.title)" : "Use for \(descriptor.title)") {
                    store.setRoutingPreferredModel(
                        taskType: descriptor.taskKind,
                        modelId: currentlyBound ? nil : m.id
                    )
                }
            }
        } label: {
            Text("Use For…")
                .font(.caption2)
        }
        .controlSize(.mini)
    }

    private func miniIconButton(_ title: String, systemName: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .imageScale(.small)
                .frame(width: 18, height: 18)
        }
        .buttonStyle(.bordered)
        .controlSize(.mini)
        .help(title)
        .accessibilityLabel(Text(title))
        .disabled(disabled)
    }

    private func localHealthActionButton(disabled: Bool) -> some View {
        Button {
            store.scanLocalModelHealth(for: [m.id])
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "heart.text.square")
                    .imageScale(.small)
                    .frame(width: 12, height: 12)
                Text(HubUIStrings.Models.LocalHealth.preflightAction)
            }
            .font(.caption2.weight(.semibold))
            .fixedSize()
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .help(HubUIStrings.Models.LocalHealth.preflightAction)
        .accessibilityLabel(Text(HubUIStrings.Models.LocalHealth.preflightAction))
        .disabled(disabled)
    }

    private func lifecycleBadge(_ runtimePresentation: LocalModelRuntimePresentation) -> some View {
        HStack(spacing: 6) {
            Image(systemName: runtimePresentation.badgeSystemName)
            Text(runtimePresentation.badgeTitle)
        }
        .font(.caption2)
        .foregroundStyle(lifecycleBadgeColor(runtimePresentation))
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .help(lifecycleHelp(runtimePresentation))
    }

    @ViewBuilder
    private func lifecycleSummary(_ runtimePresentation: LocalModelRuntimePresentation?) -> some View {
        if let runtimePresentation {
            HStack(spacing: 6) {
                Image(systemName: runtimePresentation.badgeSystemName)
                Text(runtimePresentation.badgeTitle)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .help(lifecycleHelp(runtimePresentation))
        }
    }

    private func lifecycleBadgeColor(_ runtimePresentation: LocalModelRuntimePresentation) -> Color {
        switch runtimePresentation.controlMode {
        case .mlxLegacy:
            return .secondary
        case .warmable:
            return .orange
        case .ephemeralOnDemand:
            return .secondary
        }
    }

    private func lifecycleHelp(_ runtimePresentation: LocalModelRuntimePresentation) -> String {
        switch runtimePresentation.controlMode {
        case .mlxLegacy:
            return "Legacy MLX runtime controls are wired to resident load/sleep/unload/bench actions."
        case .warmable:
            return "This provider advertises explicit warmup/unload lifecycle semantics. Hub will only expose resident actions after the provider is wired to a real resident transport."
        case .ephemeralOnDemand:
            return "This provider runs on demand per request. Hub does not keep the model resident between requests yet."
        }
    }

    private func subtitle() -> String {
        let st: String
        switch m.state {
        case .loaded: st = "Loaded"
        case .sleeping: st = "Sleeping"
        case .available: st = "Available"
        }
        let mem: String
        if let b = m.memoryBytes {
            mem = " · \(formatBytes(b))"
        } else {
            mem = ""
        }

        let tps: String
        if let v = m.tokensPerSec {
            tps = String(format: " · %.1f tok/s", v)
        } else {
            tps = ""
        }

        return "\(st) · \(m.backend) · \(m.quant) · ctx \(m.contextLength)\(mem)\(tps)"
    }

    private func benchLine(_ b: ModelBenchResult) -> String {
        let gb = Double(b.peakMemoryBytes ?? 0) / 1_000_000_000.0
        return String(format: "Bench: %.1f tok/s · peak %.2f GB", b.generationTPS ?? 0, gb)
    }

    private func formatBytes(_ b: Int64) -> String {
        let u = ByteCountFormatter()
        u.allowedUnits = [.useGB]
        u.countStyle = .memory
        return u.string(fromByteCount: b)
    }

    private func act(_ action: String) {
        // Enqueue a command for the python runtime. UI updates only when models_state.json changes.
        ModelStore.shared.enqueue(action: action, modelId: m.id)
    }
}
