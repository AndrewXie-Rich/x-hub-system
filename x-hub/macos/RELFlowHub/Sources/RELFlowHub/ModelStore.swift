import Foundation
import SwiftUI
import RELFlowHubCore

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
        let mp = (m.modelPath ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !mp.isEmpty { return false }
        return m.backend.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() != "mlx"
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
           st.mlxOk,
           let b = st.activeMemoryBytes,
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
        // If the runtime isn't alive, don't enqueue a command that will never be consumed.
        // This prevents the UI from showing an infinite spinner with no explanation.
        if let st = AIRuntimeStatusStorage.load() {
            if !st.isAlive(ttl: 3.0) {
                recordImmediateFailure(action: action, modelId: modelId, msg: "AI runtime is not running. Open Settings -> AI Runtime -> Start.")
                return
            }
            if !st.mlxOk {
                let extra = (st.importError ?? "").isEmpty ? "" : " (\(st.importError ?? ""))"
                recordImmediateFailure(
                    action: action,
                    modelId: modelId,
                    msg:
                        "AI runtime is running but MLX is unavailable\(extra).\n\n" +
                            "Fix: open Settings -> AI Runtime (it will show the import error + install hints)."
                )
                return
            }
        } else {
            recordImmediateFailure(action: action, modelId: modelId, msg: "AI runtime is not running. Open Settings -> AI Runtime -> Start.")
            return
        }

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
                    note: entry.note
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
            note: m.note
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
