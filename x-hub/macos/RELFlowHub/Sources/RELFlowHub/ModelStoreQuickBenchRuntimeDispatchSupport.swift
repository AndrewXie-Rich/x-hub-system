import Foundation
import RELFlowHubCore

extension ModelStore {
    func dispatchRuntimeQuickBench(
        modelId: String,
        model: HubModel,
        providerID: String,
        taskKind: String,
        runtimeStatus: AIRuntimeStatus?,
        fixtureProfile: String,
        fixtureTitle: String
    ) {
        guard let launchConfig = HubStore.shared.localRuntimeCommandLaunchConfig(
            preferredProviderID: providerID
        ) else {
            recordImmediateFailure(
                action: "bench",
                modelId: modelId,
                msg: LocalRuntimeCommandError.runtimeLaunchConfigUnavailable.localizedDescription
            )
            return
        }

        let requestID = UUID().uuidString
        pendingByModelId[modelId] = PendingCommand(
            reqId: requestID,
            action: "bench",
            requestedAt: Date().timeIntervalSince1970
        )
        let initialRequestContext = localRuntimeRequestContext(
            for: model,
            runtimeStatus: runtimeStatus
        )
        let benchPlan = LocalModelQuickBenchPlanner.prepare(
            model: model,
            taskKind: taskKind,
            runtimeStatus: runtimeStatus,
            requestContext: initialRequestContext
        )

        if benchPlan.requiresWarmup {
            dispatchBenchWarmupThenRun(
                modelId: modelId,
                providerID: providerID,
                taskKind: taskKind,
                fixtureProfile: fixtureProfile,
                fixtureTitle: fixtureTitle,
                requestContext: benchPlan.requestContext,
                launchConfig: launchConfig,
                requestID: requestID
            )
            return
        }

        dispatchQuickBenchCommand(
            modelId: modelId,
            providerID: providerID,
            taskKind: taskKind,
            fixtureProfile: fixtureProfile,
            fixtureTitle: fixtureTitle,
            requestContext: benchPlan.requestContext,
            launchConfig: launchConfig,
            requestID: requestID
        )
    }
}
