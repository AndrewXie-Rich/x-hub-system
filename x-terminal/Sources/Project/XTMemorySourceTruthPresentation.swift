import Foundation

enum XTMemorySourceTruthPresentation {
    static func normalized(_ raw: String?) -> String {
        let value = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !value.isEmpty else { return "" }

        switch value {
        case "hub", "hub_memory", "memory_v1":
            return XTProjectMemoryGovernance.hubMemoryContextSource
        case "hub_memory_v1":
            return XTProjectMemoryGovernance.hubMemoryContextSource
        case "hub_memory_v1_grpc", "hub_remote_snapshot":
            return XTProjectMemoryGovernance.hubSnapshotOverlaySource
        case "mixed":
            return XTProjectMemoryGovernance.hubSnapshotOverlaySource
        case "local":
            return XTProjectMemoryGovernance.localProjectMemorySource
        default:
            return value
        }
    }

    static func label(_ raw: String?) -> String {
        switch normalized(raw) {
        case "", "(none)":
            return "暂无"
        case XTProjectMemoryGovernance.hubMemoryContextSource:
            return "Hub 记忆"
        case "hub_thread":
            return "Hub 线程快照"
        case XTProjectMemoryGovernance.hubSnapshotOverlaySource:
            return "Hub 快照 + 本地 overlay"
        case XTProjectMemoryGovernance.localProjectMemorySource:
            return "本地项目记忆"
        case "local_overlay_only":
            return "仅本地 overlay"
        case XTProjectMemoryGovernance.localFallbackSource:
            return "本地 fallback"
        case "xt_cache":
            return "本地缓存"
        case "disabled":
            return "已禁用"
        case "not_required":
            return "未启用"
        case "unavailable":
            return "不可用"
        default:
            return humanizeToken(raw)
        }
    }

    static func sourceClass(_ raw: String?) -> String {
        switch normalized(raw) {
        case XTProjectMemoryGovernance.hubMemoryContextSource, "hub_thread":
            return "hub_truth"
        case XTProjectMemoryGovernance.hubSnapshotOverlaySource, "local_overlay_only":
            return "hub_snapshot_plus_local_overlay"
        case XTProjectMemoryGovernance.localProjectMemorySource:
            return "local_truth"
        case XTProjectMemoryGovernance.localFallbackSource:
            return "local_fallback"
        case "xt_cache":
            return "local_cache"
        case "disabled", "not_required":
            return "disabled"
        case "unavailable", "", "(none)":
            return "unavailable"
        default:
            return "unknown"
        }
    }

    static func humanizeToken(_ raw: String?) -> String {
        let value = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return "暂无" }
        return value.replacingOccurrences(of: "_", with: " ")
    }
}
