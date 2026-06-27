import Foundation
import RELFlowHubCore

extension ModelStore {
    func modelsLoaded() -> [HubModel] {
        snapshot.models.filter { $0.state == .loaded }
    }

    func modelsAvailable() -> [HubModel] {
        snapshot.models.filter { $0.state != .loaded }
    }

    func isRemoteModel(_ m: HubModel) -> Bool {
        LocalModelRuntimeActionPlanner.isRemoteModel(m)
    }

    // MVP "explainable" capacity: sum model costs (paramsB + ctx + quant) normalized to 100.
    func capacityPercent() -> Double {
        capacitySnapshot().percent
    }

    func capacitySnapshot(runtimeStatus: AIRuntimeStatus? = AIRuntimeStatusStorage.load()) -> ModelCapacitySnapshot {
        ModelCapacitySnapshot(
            usedMemoryBytes: usedMemoryBytes(runtimeStatus: runtimeStatus),
            budgetMemoryBytes: resolvedBudgetMemoryBytes()
        )
    }

    func usedMemoryBytes() -> Int64 {
        usedMemoryBytes(runtimeStatus: AIRuntimeStatusStorage.load())
    }

    private func usedMemoryBytes(runtimeStatus: AIRuntimeStatus?) -> Int64 {
        // Prefer runtime-reported active MLX memory for accuracy.
        if let st = runtimeStatus,
           st.isAlive(ttl: AIRuntimeStatus.recommendedHeartbeatTTL),
           st.isProviderReady("mlx", ttl: AIRuntimeStatus.recommendedHeartbeatTTL),
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
        resolvedBudgetMemoryBytes()
    }

    private func resolvedBudgetMemoryBytes() -> Int64 {
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

}
