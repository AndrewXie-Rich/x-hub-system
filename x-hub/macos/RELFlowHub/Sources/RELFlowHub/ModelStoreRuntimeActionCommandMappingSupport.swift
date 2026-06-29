import Foundation

extension LocalModelRuntimeActionPlanner {
    static func legacyCommandAction(for action: String) -> String {
        let normalized = action.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized == "warmup" {
            return "load"
        }
        return normalized
    }

    static func providerLifecycleAction(for action: String) -> String? {
        let normalized = action.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "load", "warmup":
            return "warmup_local_model"
        case "unload":
            return "unload_local_model"
        case "evict":
            return "evict_local_instance"
        default:
            return nil
        }
    }
}
