import Foundation
import RELFlowHubCore

enum LocalRuntimeProviderPolicy {
    static func resolvedControlMode(
        providerID: String,
        taskKinds: [String],
        providerStatus: AIRuntimeProviderStatus?
    ) -> AIRuntimeProviderHubControlMode {
        if let providerStatus {
            return providerStatus.hubControlMode(forModelTaskKinds: taskKinds)
        }
        return normalizedProviderID(providerID) == "mlx" ? .mlxLegacy : .ephemeralOnDemand
    }

    static func supportsUnload(
        providerID: String,
        taskKinds: [String],
        providerStatus: AIRuntimeProviderStatus?,
        residencyScope: String = "",
        residency: String = ""
    ) -> Bool {
        if let providerStatus {
            let explicitUnload = providerStatus.supportsLifecycleAction(.unloadLocalModel)
            switch resolvedControlMode(
                providerID: providerID,
                taskKinds: taskKinds,
                providerStatus: providerStatus
            ) {
            case .mlxLegacy:
                return true
            case .warmable:
                return explicitUnload
            case .ephemeralOnDemand:
                return explicitUnload
            }
        }

        if normalizedProviderID(providerID) == "mlx" {
            return true
        }
        return isRuntimeResident(
            residencyScope: residencyScope,
            residency: residency
        )
    }

    static func allowsDaemonProxy(
        providerID: String,
        runtimeStatus: AIRuntimeStatus?,
        requestContext: LocalModelRuntimeRequestContext
    ) -> Bool {
        if normalizedProviderID(providerID) == "mlx" {
            return true
        }
        if runtimeStatus?.isProviderReady(
            providerID,
            ttl: AIRuntimeStatus.recommendedHeartbeatTTL
        ) == true {
            return true
        }
        return !requestContext.instanceKey
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
    }

    private static func isRuntimeResident(
        residencyScope: String,
        residency: String
    ) -> Bool {
        let normalizedScope = residencyScope
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        switch normalizedScope {
        case "process_local":
            return false
        case "runtime_process", "provider_runtime", "provider_local", "service_runtime":
            return true
        default:
            break
        }

        let normalizedResidency = residency
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return normalizedResidency == "resident" && !normalizedScope.isEmpty
    }

    private static func normalizedProviderID(_ providerID: String) -> String {
        providerID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
