import Foundation
import RELFlowHubCore

extension LocalModelRuntimeActionPlanner {
    static func actionDisplayName(
        _ action: String,
        controlMode: AIRuntimeProviderHubControlMode
    ) -> String {
        let normalized = action.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "load":
            return controlMode == .mlxLegacy
                ? HubUIStrings.Models.Runtime.ActionPlanner.load
                : HubUIStrings.Models.Runtime.ActionPlanner.warmup
        case "warmup":
            return HubUIStrings.Models.Runtime.ActionPlanner.warmup
        case "sleep":
            return HubUIStrings.Models.Runtime.ActionPlanner.sleep
        case "unload":
            return HubUIStrings.Models.Runtime.ActionPlanner.unload
        case "bench":
            return HubUIStrings.Models.Runtime.ActionPlanner.bench
        case "evict":
            return HubUIStrings.Models.Runtime.ActionPlanner.evict
        default:
            return normalized.isEmpty ? HubUIStrings.Models.Runtime.ActionPlanner.defaultAction : normalized
        }
    }

    static func providerUnavailableMessage(
        providerID: String,
        runtimeStatus: AIRuntimeStatus
    ) -> String {
        let providerStatus = runtimeStatus.providerStatus(providerID)
        let reason = (providerStatus?.reasonCode ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let importError = (providerStatus?.importError ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let detail = LocalModelRuntimeErrorPresentation.humanized(
            !importError.isEmpty ? importError : reason
        )
        let extra = detail.isEmpty ? "" : " (\(detail))"
        return HubUIStrings.Models.Runtime.ActionPlanner.providerUnavailable(
            providerID: providerID,
            extra: extra
        )
    }

    static func warmableActionUnsupportedMessage(
        action: String,
        providerID: String,
        controlMode: AIRuntimeProviderHubControlMode
    ) -> String {
        let displayAction = actionDisplayName(action, controlMode: controlMode)
        return HubUIStrings.Models.Runtime.ActionPlanner.warmableActionUnsupported(
            providerID: providerID,
            actionTitle: displayAction
        )
    }

    static func onDemandActionBlockedMessage(
        action: String,
        providerID: String,
        residencyScope: String,
        lifecycleMode: String,
        controlMode: AIRuntimeProviderHubControlMode
    ) -> String {
        let displayAction = actionDisplayName(action, controlMode: controlMode)
        let scope = residencyScope.isEmpty ? "process_local" : residencyScope
        let lifecycle = lifecycleMode.isEmpty ? "ephemeral_on_demand" : lifecycleMode
        return HubUIStrings.Models.Runtime.ActionPlanner.onDemandActionBlocked(
            providerID: providerID,
            lifecycle: lifecycle,
            scope: scope,
            actionTitle: displayAction
        )
    }
}
