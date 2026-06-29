import Foundation
import RELFlowHubCore

extension ModelStore {
    func lifecycleDisplayAction(_ action: String) -> String {
        let normalized = action.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "warmup_local_model":
            return "warmup"
        case "unload_local_model":
            return "unload"
        case "evict_local_instance":
            return "evict"
        default:
            return normalized.isEmpty ? "action" : normalized
        }
    }

    func lifecycleStatusLine(_ payload: [String: Any], action: String) -> String {
        let ok = payload["ok"] as? Bool ?? false
        let normalizedAction = action.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let verb = localizedLifecycleActionTitle(normalizedAction)

        if ok {
            if normalizedAction == "warmup", payload["alreadyLoaded"] as? Bool == true {
                return HubUIStrings.Models.Runtime.ActionPlanner.lifecycleAlreadyLoaded(verb)
            }
            return HubUIStrings.Models.Runtime.ActionPlanner.lifecycleCompleted(verb)
        }

        let detail = LocalModelRuntimeErrorPresentation.humanized(
            (payload["errorDetail"] as? String ?? payload["error"] as? String ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        )
        return detail.isEmpty
            ? HubUIStrings.Models.Runtime.ActionPlanner.lifecycleFailed(verb)
            : HubUIStrings.Models.Runtime.ActionPlanner.lifecycleFailed(actionTitle: verb, detail: detail)
    }

    private func localizedBenchVerdict(_ verdict: String) -> String {
        HubUIStrings.Models.Review.Bench.localizedVerdict(verdict)
    }

    func localizedLifecycleActionTitle(_ action: String) -> String {
        switch action.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "warmup", "warmup_local_model":
            return HubUIStrings.Models.Runtime.ActionPlanner.warmup
        case "unload", "unload_local_model":
            return HubUIStrings.Models.Runtime.ActionPlanner.unload
        case "evict", "evict_local_instance":
            return HubUIStrings.Models.Runtime.ActionPlanner.evict
        default:
            return action.trimmingCharacters(in: .whitespacesAndNewlines).capitalized
        }
    }

    func lifecycleFailureReasonCode(_ payload: [String: Any]) -> String? {
        let candidates = [
            payload["error"] as? String,
            payload["reasonCode"] as? String,
            payload["reason_code"] as? String,
            payload["runtimeReasonCode"] as? String,
            payload["runtime_reason_code"] as? String,
        ]
        for candidate in candidates {
            let token = (candidate ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !token.isEmpty {
                return token
            }
        }
        return nil
    }
}
