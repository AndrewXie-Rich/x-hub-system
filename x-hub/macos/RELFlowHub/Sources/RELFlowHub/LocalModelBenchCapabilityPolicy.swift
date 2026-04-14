import Foundation
import RELFlowHubCore

enum LocalModelBenchCapabilityPolicy {
    static func benchableTaskKinds(
        for model: HubModel,
        runtimeStatus: AIRuntimeStatus? = nil,
        probeLaunchConfig: LocalRuntimePythonProbeLaunchConfig? = nil,
        pythonPath: String? = nil
    ) -> [String] {
        let providerID = normalizedProviderID(for: model)
        if LocalModelRuntimeCompatibilityPolicy.blockedActionMessage(
            action: "load",
            model: model,
            probeLaunchConfig: probeLaunchConfig,
            pythonPath: pythonPath
        ) != nil {
            return []
        }
        let modelTaskKinds = LocalTaskRoutingCatalog.supportedTaskKinds(in: model.taskKinds)
        guard !modelTaskKinds.isEmpty else { return [] }

        let providerTaskFilter = providerSupportedTaskKinds(
            for: model,
            runtimeStatus: runtimeStatus
        )

        return modelTaskKinds.filter { taskKind in
            if let providerTaskFilter, !providerTaskFilter.contains(taskKind) {
                return false
            }
            return !LocalBenchFixtureCatalog.fixtures(for: taskKind, providerID: providerID).isEmpty
        }
    }

    static func benchableDescriptors(
        for model: HubModel,
        runtimeStatus: AIRuntimeStatus? = nil,
        probeLaunchConfig: LocalRuntimePythonProbeLaunchConfig? = nil,
        pythonPath: String? = nil
    ) -> [LocalTaskRoutingDescriptor] {
        benchableTaskKinds(
            for: model,
            runtimeStatus: runtimeStatus,
            probeLaunchConfig: probeLaunchConfig,
            pythonPath: pythonPath
        ).compactMap(LocalTaskRoutingCatalog.descriptor(for:))
    }

    static func unsupportedTaskMessage(
        for model: HubModel,
        taskKind: String,
        runtimeStatus: AIRuntimeStatus? = nil,
        probeLaunchConfig: LocalRuntimePythonProbeLaunchConfig? = nil,
        pythonPath: String? = nil
    ) -> String? {
        let strings = HubUIStrings.Models.Review.CapabilityPolicy.self
        let normalizedTaskKind = taskKind.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedTaskKind.isEmpty else {
            return strings.missingTaskKind
        }
        guard !benchableTaskKinds(
            for: model,
            runtimeStatus: runtimeStatus,
            probeLaunchConfig: probeLaunchConfig,
            pythonPath: pythonPath
        ).contains(normalizedTaskKind) else {
            return nil
        }
        if let blockedMessage = LocalModelRuntimeCompatibilityPolicy.blockedActionMessage(
            action: "load",
            model: model,
            probeLaunchConfig: probeLaunchConfig,
            pythonPath: pythonPath
        ) {
            return blockedMessage
        }

        let providerID = normalizedProviderID(for: model)
        let taskTitle = LocalTaskRoutingCatalog.title(for: normalizedTaskKind)

        if resolvedControlMode(for: model, runtimeStatus: runtimeStatus) == .mlxLegacy,
           normalizedTaskKind != "text_generate" {
            if model.backend.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "mlx" {
                return strings.mlxUnsupportedTask(taskTitle)
            }
            return strings.legacyTextOnlyUnsupported(
                runtimeLabel: providerID,
                taskTitle: taskTitle
            )
        }

        return strings.providerUnsupported(providerID: providerID, taskTitle: taskTitle)
    }

    private static func normalizedProviderID(for model: HubModel) -> String {
        LocalModelRuntimeActionPlanner.providerID(for: model)
    }

    private static func providerSupportedTaskKinds(
        for model: HubModel,
        runtimeStatus: AIRuntimeStatus?
    ) -> Set<String>? {
        if resolvedControlMode(for: model, runtimeStatus: runtimeStatus) == .mlxLegacy {
            return ["text_generate"]
        }
        let providerID = normalizedProviderID(for: model)
        if let monitorProvider = runtimeStatus?.monitorSnapshot?.providers.first(where: { $0.provider == providerID }) {
            let advertisedMonitorTaskKinds = LocalTaskRoutingCatalog.supportedTaskKinds(
                in: monitorProvider.availableTaskKinds
            )
            if !advertisedMonitorTaskKinds.isEmpty || !monitorProvider.unavailableTaskKinds.isEmpty {
                return Set(advertisedMonitorTaskKinds)
            }
        }
        guard let providerStatus = runtimeStatus?.providerStatus(providerID) else {
            return nil
        }
        let advertisedTaskKinds = LocalTaskRoutingCatalog.supportedTaskKinds(in: providerStatus.availableTaskKinds)
        guard !advertisedTaskKinds.isEmpty else {
            return nil
        }
        return Set(advertisedTaskKinds)
    }

    private static func resolvedControlMode(
        for model: HubModel,
        runtimeStatus: AIRuntimeStatus?
    ) -> AIRuntimeProviderHubControlMode {
        let providerID = normalizedProviderID(for: model)
        return LocalRuntimeProviderPolicy.resolvedControlMode(
            providerID: providerID,
            taskKinds: model.taskKinds,
            providerStatus: runtimeStatus?.providerStatus(providerID)
        )
    }
}
