import Foundation
import RELFlowHubCore

extension ModelStore {
    func enqueueProviderLifecycleCommand(
        action: String,
        model: HubModel,
        targetPreferenceOverride: LocalModelRuntimeTargetPreference?
    ) {
        let providerID = LocalModelRuntimeActionPlanner.providerID(for: model)
        guard let launchConfig = HubStore.shared.localRuntimeCommandLaunchConfig(
            preferredProviderID: providerID
        ) else {
            recordImmediateFailure(
                action: lifecycleDisplayAction(action),
                modelId: model.id,
                msg: LocalRuntimeCommandError.runtimeLaunchConfigUnavailable.localizedDescription
            )
            return
        }

        let requestContext = localRuntimeRequestContext(
            for: model,
            runtimeStatus: AIRuntimeStatusStorage.load(),
            targetPreference: targetPreferenceOverride
        )
        let baseRequest: [String: Any] = [
            "action": action,
            "provider": providerID,
            "model_id": model.id,
        ]
        let request = requestContext.applying(to: baseRequest)
        guard JSONSerialization.isValidJSONObject(request),
              let requestData = try? JSONSerialization.data(withJSONObject: request, options: []) else {
            recordImmediateFailure(
                action: lifecycleDisplayAction(action),
                modelId: model.id,
                msg: LocalRuntimeCommandError.invalidRequestPayload.localizedDescription
            )
            return
        }

        let requestID = UUID().uuidString
        let uiAction = lifecycleDisplayAction(action)
        pendingByModelId[model.id] = PendingCommand(
            reqId: requestID,
            action: uiAction,
            requestedAt: Date().timeIntervalSince1970
        )

        Task.detached(priority: .userInitiated) { [requestData, launchConfig] in
            do {
                let payloadData = try LocalRuntimeCommandRunner.run(
                    command: "manage-local-model",
                    requestData: requestData,
                    launchConfig: launchConfig,
                    timeoutSec: 60.0
                )
                await MainActor.run {
                    self.finishProviderLifecycleCommand(
                        payloadData: payloadData,
                        modelId: model.id,
                        action: uiAction,
                        requestID: requestID
                    )
                }
            } catch {
                await MainActor.run {
                    self.finishProviderLifecycleCommandWithError(
                        error.localizedDescription,
                        modelId: model.id,
                        action: uiAction,
                        requestID: requestID
                    )
                }
            }
        }
    }
}
