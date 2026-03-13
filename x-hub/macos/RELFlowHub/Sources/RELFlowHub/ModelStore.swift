import Foundation
import SwiftUI
import RELFlowHubCore

enum LocalModelRuntimeActionRoute: Equatable {
    case legacyModelCommand(action: String)
    case immediateFailure(message: String)
}

struct LocalModelRuntimePresentation: Equatable {
    var providerID: String
    var controlMode: AIRuntimeProviderHubControlMode
    var lifecycleMode: String
    var residencyScope: String
    var providerReady: Bool
    var supportsWarmup: Bool
    var supportsUnload: Bool
    var supportsBench: Bool

    var badgeTitle: String {
        switch controlMode {
        case .mlxLegacy:
            return "MLX Legacy"
        case .warmable:
            return "Warmable"
        case .ephemeralOnDemand:
            return "On-Demand"
        }
    }

    var badgeSystemName: String {
        switch controlMode {
        case .mlxLegacy:
            return "cpu"
        case .warmable:
            return "flame"
        case .ephemeralOnDemand:
            return "bolt.horizontal"
        }
    }
}

enum LocalModelRuntimeActionPlanner {
    static let runtimeStartMessage = "AI runtime is not running. Open Settings -> AI Runtime -> Start."

    static func isRemoteModel(_ model: HubModel) -> Bool {
        let modelPath = (model.modelPath ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !modelPath.isEmpty {
            return false
        }
        return providerID(for: model) != "mlx"
    }

    static func providerID(for model: HubModel) -> String {
        let token = model.backend.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return token.isEmpty ? "unknown" : token
    }

    static func presentation(
        for model: HubModel,
        runtimeStatus: AIRuntimeStatus? = nil
    ) -> LocalModelRuntimePresentation? {
        guard !isRemoteModel(model) else { return nil }
        let providerID = providerID(for: model)
        let providerStatus = runtimeStatus?.providerStatus(providerID)
        let controlMode = providerStatus?.hubControlMode(forModelTaskKinds: model.taskKinds)
            ?? (providerID == "mlx" ? .mlxLegacy : .ephemeralOnDemand)
        let providerReady = runtimeStatus?.isProviderReady(providerID, ttl: 3.0) ?? false
        let supportsWarmup = controlMode == .warmable && (providerStatus?.supportsWarmup(forModelTaskKinds: model.taskKinds) ?? false)
        let supportsUnload = controlMode == .mlxLegacy
            || (controlMode == .warmable && (providerStatus?.supportsLifecycleAction(.unloadLocalModel) ?? false))
        let supportsBench = controlMode == .mlxLegacy
        return LocalModelRuntimePresentation(
            providerID: providerID,
            controlMode: controlMode,
            lifecycleMode: providerStatus?.lifecycleMode ?? "",
            residencyScope: providerStatus?.residencyScope ?? "",
            providerReady: providerReady,
            supportsWarmup: supportsWarmup,
            supportsUnload: supportsUnload,
            supportsBench: supportsBench
        )
    }

    static func plan(
        action: String,
        model: HubModel,
        runtimeStatus: AIRuntimeStatus?
    ) -> LocalModelRuntimeActionRoute {
        guard !isRemoteModel(model) else {
            return .immediateFailure(message: "Remote models do not use the local runtime model controls.")
        }
        guard let runtimeStatus else {
            return .immediateFailure(message: runtimeStartMessage)
        }
        guard runtimeStatus.isAlive(ttl: 3.0) else {
            return .immediateFailure(message: runtimeStartMessage)
        }

        let providerID = providerID(for: model)
        let presentation = presentation(for: model, runtimeStatus: runtimeStatus)
            ?? LocalModelRuntimePresentation(
                providerID: providerID,
                controlMode: providerID == "mlx" ? .mlxLegacy : .ephemeralOnDemand,
                lifecycleMode: "",
                residencyScope: "",
                providerReady: false,
                supportsWarmup: false,
                supportsUnload: providerID == "mlx",
                supportsBench: providerID == "mlx"
            )

        guard runtimeStatus.isProviderReady(providerID, ttl: 3.0) else {
            return .immediateFailure(message: providerUnavailableMessage(providerID: providerID, runtimeStatus: runtimeStatus))
        }

        switch presentation.controlMode {
        case .mlxLegacy:
            return .legacyModelCommand(action: legacyCommandAction(for: action))
        case .warmable:
            return .immediateFailure(message: warmableActionBlockedMessage(action: action, providerID: providerID))
        case .ephemeralOnDemand:
            return .immediateFailure(
                message: onDemandActionBlockedMessage(
                    action: action,
                    providerID: providerID,
                    residencyScope: presentation.residencyScope,
                    lifecycleMode: presentation.lifecycleMode
                )
            )
        }
    }

    private static func legacyCommandAction(for action: String) -> String {
        let normalized = action.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized == "warmup" {
            return "load"
        }
        return normalized
    }

    private static func actionDisplayName(_ action: String, providerID: String) -> String {
        let normalized = action.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "load":
            return providerID == "mlx" ? "Load" : "Warmup"
        case "warmup":
            return "Warmup"
        case "sleep":
            return "Sleep"
        case "unload":
            return "Unload"
        case "bench":
            return "Bench"
        default:
            return normalized.isEmpty ? "Action" : normalized.capitalized
        }
    }

    private static func providerUnavailableMessage(
        providerID: String,
        runtimeStatus: AIRuntimeStatus
    ) -> String {
        let providerStatus = runtimeStatus.providerStatus(providerID)
        let reason = (providerStatus?.reasonCode ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let importError = (providerStatus?.importError ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let detail = !importError.isEmpty ? importError : reason
        let extra = detail.isEmpty ? "" : " (\(detail))"
        return
            "AI runtime is running but the \(providerID) provider is unavailable\(extra).\n\n" +
            "Fix: open Settings -> AI Runtime (it will show provider import errors and install hints)."
    }

    private static func warmableActionBlockedMessage(action: String, providerID: String) -> String {
        let displayAction = actionDisplayName(action, providerID: providerID)
        return
            "Provider '\(providerID)' advertises a resident lifecycle, but Hub's model list is not yet wired to a resident transport for this provider.\n\n" +
            "\(displayAction) is intentionally blocked here so the UI does not fake persistence before the runtime loop can actually keep the instance warm."
    }

    private static func onDemandActionBlockedMessage(
        action: String,
        providerID: String,
        residencyScope: String,
        lifecycleMode: String
    ) -> String {
        let displayAction = actionDisplayName(action, providerID: providerID)
        let scope = residencyScope.isEmpty ? "process_local" : residencyScope
        let lifecycle = lifecycleMode.isEmpty ? "ephemeral_on_demand" : lifecycleMode
        return
            "Provider '\(providerID)' is available, but this model currently runs on demand (`\(lifecycle)` / `\(scope)`).\n\n" +
            "Hub does not keep it resident between requests yet, so \(displayAction) is not available from the model list. Use task routing or direct execution instead."
    }
}

@MainActor
final class ModelStore: ObservableObject {
    static let shared = ModelStore()

    @Published private(set) var snapshot: ModelStateSnapshot = .empty()
    @Published private(set) var benchByModelId: [String: ModelBenchResult] = [:]
    @Published private(set) var pendingByModelId: [String: PendingCommand] = [:]
    @Published private(set) var lastResultByModelId: [String: ModelCommandResult] = [:]

    private var timer: Timer?

    private init() {
        migrateLegacyHomeModelsIfNeeded()
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }

        // Remove legacy demo models (note="demo", no modelPath) so the UI only shows real models.
        pruneLegacyDemoModels()
    }

    func refresh() {
        let base = ModelStateStorage.load()
        let merged = mergeRemoteModels(base)
        snapshot = merged
        if merged.models != base.models {
            ModelStateStorage.save(merged)
        }
        let bench = ModelBenchStorage.load()
        var map: [String: ModelBenchResult] = [:]
        for r in bench.results {
            map[r.modelId] = r
        }
        benchByModelId = map

        // Clear pending commands that have already reflected in the state snapshot.
        reconcilePendingWithState()
        // Drain command result files so we can surface failures.
        drainCommandResults()
    }

    func modelsLoaded() -> [HubModel] {
        snapshot.models.filter { $0.state == .loaded }
    }

    func modelsAvailable() -> [HubModel] {
        snapshot.models.filter { $0.state != .loaded }
    }

    private func mergeRemoteModels(_ base: ModelStateSnapshot) -> ModelStateSnapshot {
        let remote = RemoteModelStorage.exportableEnabledModels()

        // Keep local models (with a modelPath). Remove stale remote entries before re-adding.
        let localOnly = base.models.filter { !(isRemoteModel($0)) }

        if remote.isEmpty {
            if localOnly.count == base.models.count {
                return base
            }
            return ModelStateSnapshot(models: localOnly, updatedAt: Date().timeIntervalSince1970)
        }

        var merged = localOnly
        for r in remote {
            if merged.contains(where: { $0.id == r.id }) {
                continue
            }
            let m = HubModel(
                id: r.id,
                name: r.name,
                backend: r.backend,
                quant: "remote",
                contextLength: max(512, r.contextLength),
                paramsB: 0.0,
                roles: nil,
                state: .loaded,
                memoryBytes: nil,
                tokensPerSec: nil,
                modelPath: nil,
                note: r.note
            )
            merged.append(m)
        }

        if merged == base.models {
            return base
        }
        return ModelStateSnapshot(models: merged, updatedAt: Date().timeIntervalSince1970)
    }

    private func isRemoteModel(_ m: HubModel) -> Bool {
        LocalModelRuntimeActionPlanner.isRemoteModel(m)
    }

    // MVP "explainable" capacity: sum model costs (paramsB + ctx + quant) normalized to 100.
    func capacityPercent() -> Double {
        // Prefer runtime-reported MLX active memory; fallback to per-model sum.
        let used = Double(max(0, usedMemoryBytes()))
        let budget = Double(max(1, budgetMemoryBytes()))
        return max(0.0, min(1.0, used / budget))
    }

    func usedMemoryBytes() -> Int64 {
        // Prefer runtime-reported active MLX memory for accuracy.
        if let st = AIRuntimeStatusStorage.load(),
           st.isAlive(ttl: 3.0),
           st.isProviderReady("mlx", ttl: 3.0),
           let b = st.providerStatus("mlx")?.activeMemoryBytes ?? st.activeMemoryBytes,
           b > 0 {
            return b
        }

        // Fallback: sum per-model measured values; then a conservative estimate.
        var total: Int64 = 0
        for m in modelsLoaded() {
            if isRemoteModel(m) {
                continue
            }
            if let b = m.memoryBytes, b > 0 {
                total += b
            } else {
                total += estimateMemoryBytes(m)
            }
        }
        return max(0, total)
    }

    func budgetMemoryBytes() -> Int64 {
        // Conservative budget: keep headroom so the machine stays responsive.
        // Avoid a fixed 4GB reserve because it makes 8GB Macs show 100% too easily.
        let phys = Double(ProcessInfo.processInfo.physicalMemory)
        let gb = 1024.0 * 1024.0 * 1024.0

        // Reserve at least 2GB, or 25% of physical memory.
        let reserve = max(2.0 * gb, phys * 0.25)
        // Budget is what's left after reserve, but don't exceed 85% of total.
        let budget = max(1.0, min(phys * 0.85, max(0.0, phys - reserve)))
        return Int64(budget)
    }

    func cost(_ m: HubModel) -> Double {
        if isRemoteModel(m) {
            return 0.0
        }
        // params drive baseline.
        let base = max(0.1, m.paramsB)
        let q = m.quant.lowercased()
        let quantFactor: Double
        if q.contains("int4") || q.contains("4") {
            quantFactor = 0.45
        } else if q.contains("int8") || q.contains("8") {
            quantFactor = 0.65
        } else {
            quantFactor = 1.0
        }
        // Context increases KV cache; keep gentle.
        let ctxFactor = 1.0 + min(1.0, Double(max(0, m.contextLength - 2048)) / 8192.0) * 0.35
        return base * quantFactor * ctxFactor
    }

    func enqueue(action: String, modelId: String) {
        guard let model = snapshot.models.first(where: { $0.id == modelId }) else { return }
        let runtimeStatus = AIRuntimeStatusStorage.load()
        switch LocalModelRuntimeActionPlanner.plan(action: action, model: model, runtimeStatus: runtimeStatus) {
        case .immediateFailure(let message):
            recordImmediateFailure(action: action, modelId: modelId, msg: message)
            return
        case .legacyModelCommand(let routedAction):
            enqueueLegacyModelCommand(action: routedAction, modelId: modelId)
        }
    }

    func localModelRuntimePresentation(for model: HubModel) -> LocalModelRuntimePresentation? {
        LocalModelRuntimeActionPlanner.presentation(for: model, runtimeStatus: AIRuntimeStatusStorage.load())
    }

    private func enqueueLegacyModelCommand(action: String, modelId: String) {
        let base = SharedPaths.ensureHubDirectory()
        let dir = base.appendingPathComponent("model_commands", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let reqId = UUID().uuidString
        let cmd: [String: Any] = [
            "type": "model_command",
            "req_id": reqId,
            "action": action,
            "model_id": modelId,
            "requested_at": Date().timeIntervalSince1970,
        ]

        let tmp = dir.appendingPathComponent(".cmd_\(UUID().uuidString).tmp")
        let out = dir.appendingPathComponent("cmd_\(UUID().uuidString).json")
        if let data = try? JSONSerialization.data(withJSONObject: cmd, options: []) {
            try? data.write(to: tmp, options: .atomic)
            try? FileManager.default.moveItem(at: tmp, to: out)
        }

        // Track pending so the UI doesn't optimistically lie about loaded state.
        pendingByModelId[modelId] = PendingCommand(reqId: reqId, action: action, requestedAt: Date().timeIntervalSince1970)
    }

    private func recordImmediateFailure(action: String, modelId: String, msg: String) {
        let reqId = UUID().uuidString
        lastResultByModelId[modelId] = ModelCommandResult(
            type: "model_result",
            reqId: reqId,
            action: action,
            modelId: modelId,
            ok: false,
            msg: msg,
            finishedAt: Date().timeIntervalSince1970
        )
        pendingByModelId.removeValue(forKey: modelId)
    }

    func pendingAction(for modelId: String) -> String? {
        pendingByModelId[modelId]?.action
    }

    func lastError(for modelId: String) -> String? {
        guard let r = lastResultByModelId[modelId] else { return nil }
        if r.ok { return nil }
        return r.msg
    }

    func upsertCatalogModel(_ entry: ModelCatalogEntry) {
        var cur = ModelStateStorage.load()
        if let idx = cur.models.firstIndex(where: { $0.id == entry.id }) {
            // Keep state/memory/tps; update metadata.
            cur.models[idx].name = entry.name
            cur.models[idx].backend = entry.backend
            cur.models[idx].quant = entry.quant
            cur.models[idx].contextLength = entry.contextLength
            cur.models[idx].paramsB = entry.paramsB
            cur.models[idx].modelPath = entry.modelPath
            cur.models[idx].roles = entry.roles
            cur.models[idx].note = entry.note
            cur.models[idx].modelFormat = entry.modelFormat
            cur.models[idx].taskKinds = entry.taskKinds
            cur.models[idx].inputModalities = entry.inputModalities
            cur.models[idx].outputModalities = entry.outputModalities
            cur.models[idx].offlineReady = entry.offlineReady
            cur.models[idx].resourceProfile = entry.resourceProfile
            cur.models[idx].trustProfile = entry.trustProfile
            cur.models[idx].processorRequirements = entry.processorRequirements
        } else {
            cur.models.append(
                HubModel(
                    id: entry.id,
                    name: entry.name,
                    backend: entry.backend,
                    quant: entry.quant,
                    contextLength: entry.contextLength,
                    paramsB: entry.paramsB,
                    roles: entry.roles,
                    state: .available,
                    modelPath: entry.modelPath,
                    note: entry.note,
                    modelFormat: entry.modelFormat,
                    taskKinds: entry.taskKinds,
                    inputModalities: entry.inputModalities,
                    outputModalities: entry.outputModalities,
                    offlineReady: entry.offlineReady,
                    resourceProfile: entry.resourceProfile,
                    trustProfile: entry.trustProfile,
                    processorRequirements: entry.processorRequirements
                )
            )
        }
        cur.updatedAt = Date().timeIntervalSince1970
        ModelStateStorage.save(cur)
        snapshot = cur
    }

    func updateRoles(modelId: String, roles: [String]) {
        let rid = modelId
        let cleaned: [String] = {
            var out: [String] = []
            var seen: Set<String> = []
            for r0 in roles {
                let r = r0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if r.isEmpty { continue }
                if seen.contains(r) { continue }
                seen.insert(r)
                out.append(r)
            }
            return out
        }()

        // Update catalog (for routing/runtime).
        var cat = ModelCatalogStorage.load()
        if let idx = cat.models.firstIndex(where: { $0.id == rid }) {
            cat.models[idx].roles = cleaned
            ModelCatalogStorage.save(cat)
            upsertCatalogModel(cat.models[idx])
            return
        }

        // If not in catalog yet, best-effort synthesize an entry from the current state.
        let cur = ModelStateStorage.load()
        guard let m = cur.models.first(where: { $0.id == rid }) else {
            return
        }
        guard let mp = m.modelPath, !mp.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            // No model path means runtime can't load it anyway.
            var cur2 = cur
            if let idx = cur2.models.firstIndex(where: { $0.id == rid }) {
                cur2.models[idx].roles = cleaned
                cur2.updatedAt = Date().timeIntervalSince1970
                ModelStateStorage.save(cur2)
                snapshot = cur2
            }
            return
        }

        let entry = ModelCatalogEntry(
            id: m.id,
            name: m.name,
            backend: m.backend,
            quant: m.quant,
            contextLength: m.contextLength,
            paramsB: m.paramsB,
            modelPath: mp,
            roles: cleaned,
            note: m.note,
            modelFormat: m.modelFormat,
            taskKinds: m.taskKinds,
            inputModalities: m.inputModalities,
            outputModalities: m.outputModalities,
            offlineReady: m.offlineReady,
            resourceProfile: m.resourceProfile,
            trustProfile: m.trustProfile,
            processorRequirements: m.processorRequirements
        )
        cat.models.append(entry)
        ModelCatalogStorage.save(cat)
        upsertCatalogModel(entry)
    }

    func removeModel(modelId: String, deleteLocalFiles: Bool) {
        let rid = modelId

        // Capture current info before mutation.
        let curBefore = ModelStateStorage.load()
        let stateModel = curBefore.models.first(where: { $0.id == rid })

        // 1) Remove from catalog.
        var cat = ModelCatalogStorage.load()
        let removedEntry = cat.models.first(where: { $0.id == rid })
        cat.models.removeAll { $0.id == rid }
        ModelCatalogStorage.save(cat)

        // 2) Remove from state snapshot.
        var cur = curBefore
        cur.models.removeAll { $0.id == rid }
        cur.updatedAt = Date().timeIntervalSince1970
        ModelStateStorage.save(cur)
        snapshot = cur

        // 3) Clear pending/result UI state.
        pendingByModelId.removeValue(forKey: rid)
        lastResultByModelId.removeValue(forKey: rid)

        guard deleteLocalFiles else { return }

        // Only delete when we are confident it's a Hub-managed copy. Never delete arbitrary user paths.
        let base = SharedPaths.ensureHubDirectory()
        let managedRoot = base.appendingPathComponent("models", isDirectory: true)

        let path = (removedEntry?.modelPath ?? stateModel?.modelPath ?? "")
        let note = (removedEntry?.note ?? stateModel?.note ?? "")
        let looksManaged = note == "managed_copy" || path.hasPrefix(managedRoot.path + "/")
        if looksManaged {
            let managedDir = managedRoot.appendingPathComponent(rid, isDirectory: true)
            try? FileManager.default.removeItem(at: managedDir)
        }
    }

    private func estimateMemoryBytes(_ m: HubModel) -> Int64 {
        // Rough, explainable estimate for UI until a real model runtime reports measured values.
        let q = m.quant.lowercased()
        let bytesPerParam: Double
        if q.contains("int4") || q == "4" {
            bytesPerParam = 0.5
        } else if q.contains("int8") || q == "8" {
            bytesPerParam = 1.0
        } else {
            bytesPerParam = 2.0
        }

        let weights = m.paramsB * 1_000_000_000.0 * bytesPerParam
        let overhead = 0.35 * 1_000_000_000.0
        let kv = min(0.8 * 1_000_000_000.0, (Double(m.contextLength) / 8192.0) * 0.25 * 1_000_000_000.0)
        let total = max(50_000_000.0, weights + overhead + kv)
        return Int64(total)
    }

    private func estimateTokensPerSec(_ m: HubModel) -> Double {
        // Placeholder until real benchmarking is integrated.
        let params = max(0.1, m.paramsB)
        let q = m.quant.lowercased()
        let quantBoost: Double
        if q.contains("int4") || q == "4" {
            quantBoost = 1.25
        } else if q.contains("int8") || q == "8" {
            quantBoost = 1.1
        } else {
            quantBoost = 0.85
        }
        let tps = (42.0 / pow(params, 0.6)) * quantBoost
        return max(1.0, min(80.0, tps))
    }


    private func pruneLegacyDemoModels() {
        var cur = ModelStateStorage.load()
        let before = cur.models.count
        cur.models.removeAll { m in
            (m.note ?? "") == "demo" && (m.modelPath == nil || (m.modelPath ?? "").isEmpty)
        }
        if cur.models.count != before {
            cur.updatedAt = Date().timeIntervalSince1970
            ModelStateStorage.save(cur)
            snapshot = cur
        }
    }

    private func reconcilePendingWithState() {
        if pendingByModelId.isEmpty { return }
        var toRemove: [String] = []
        for (mid, p) in pendingByModelId {
            guard let m = snapshot.models.first(where: { $0.id == mid }) else {
                // Model removed.
                toRemove.append(mid)
                continue
            }
            let st = m.state
            switch p.action {
            case "load":
                if st == .loaded { toRemove.append(mid) }
            case "unload":
                if st == .available { toRemove.append(mid) }
            case "sleep":
                if st == .sleeping { toRemove.append(mid) }
            default:
                break
            }
        }
        for mid in toRemove {
            pendingByModelId.removeValue(forKey: mid)
        }
    }

    private func drainCommandResults() {
        let base = SharedPaths.ensureHubDirectory()
        let dir = base.appendingPathComponent("model_results", isDirectory: true)
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return
        }
        if files.isEmpty { return }
        let dec = JSONDecoder()
        for url in files {
            if url.pathExtension.lowercased() != "json" { continue }
            guard let data = try? Data(contentsOf: url) else {
                try? FileManager.default.removeItem(at: url)
                continue
            }
            guard let obj = try? dec.decode(ModelCommandResult.self, from: data) else {
                try? FileManager.default.removeItem(at: url)
                continue
            }
            lastResultByModelId[obj.modelId] = obj
            if let p = pendingByModelId[obj.modelId], p.reqId == obj.reqId {
                pendingByModelId.removeValue(forKey: obj.modelId)
            }
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func migrateLegacyHomeModelsIfNeeded() {
        // If we are using a sandbox container base dir, migrate any previously copied
        // ~/RELFlowHub/*.json into the container so the UI can see them.
        let base = SharedPaths.ensureHubDirectory()
        let legacy = SharedPaths.realHomeDirectory().appendingPathComponent("RELFlowHub", isDirectory: true)
        if base.path == legacy.path {
            return
        }

        let fm = FileManager.default
        let names = ["models_state.json", "models_catalog.json"]
        for n in names {
            let src = legacy.appendingPathComponent(n)
            let dst = base.appendingPathComponent(n)
            if fm.fileExists(atPath: dst.path) {
                continue
            }
            if !fm.fileExists(atPath: src.path) {
                continue
            }
            try? fm.createDirectory(at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? fm.copyItem(at: src, to: dst)
        }
    }
}

struct PendingCommand: Equatable, Sendable {
    var reqId: String
    var action: String
    var requestedAt: Double
}

struct ModelCommandResult: Codable, Equatable, Sendable {
    var type: String
    var reqId: String
    var action: String
    var modelId: String
    var ok: Bool
    var msg: String
    var finishedAt: Double

    enum CodingKeys: String, CodingKey {
        case type
        case reqId = "req_id"
        case action
        case modelId = "model_id"
        case ok
        case msg
        case finishedAt = "finished_at"
    }
}
