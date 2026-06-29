import Foundation
import RELFlowHubCore

extension ModelStore {
    func shouldAttemptRuntimeRecovery(
        action: String,
        model: HubModel,
        providerID: String,
        runtimeStatus: AIRuntimeStatus?
    ) -> Bool {
        guard !isRemoteModel(model) else { return false }
        let controlMode = LocalRuntimeProviderPolicy.resolvedControlMode(
            providerID: providerID,
            taskKinds: model.taskKinds,
            providerStatus: runtimeStatus?.providerStatus(providerID)
        )
        guard controlMode != .mlxLegacy else { return false }
        guard action == "load" || action == "warmup" else { return false }
        guard !runtimeRecoveryInFlightModelIds.contains(model.id) else { return false }
        return HubStore.shared.canAutoRecoverRuntime(for: providerID, runtimeStatus: runtimeStatus)
    }

    func recoverRuntimeAndRetry(action: String, model: HubModel, providerID: String) {
        let requestID = UUID().uuidString
        runtimeRecoveryInFlightModelIds.insert(model.id)
        pendingByModelId[model.id] = PendingCommand(
            reqId: requestID,
            action: action,
            requestedAt: Date().timeIntervalSince1970
        )

        Task { @MainActor in
            let recovered = await HubStore.shared.ensureRuntimeReady(for: providerID)
            self.runtimeRecoveryInFlightModelIds.remove(model.id)
            self.pendingByModelId.removeValue(forKey: model.id)

            if recovered {
                self.enqueue(
                    action: action,
                    modelId: model.id,
                    allowRuntimeRecovery: false,
                    targetPreferenceOverride: nil
                )
                return
            }

            let providerHint = (HubStore.shared.aiRuntimeProviderHelpTextByProvider[providerID] ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let fallback = HubUIStrings.Models.Runtime.ActionPlanner.runtimeRecoveryStillUnavailable(
                providerID: providerID,
                providerHint: providerHint
            )
            self.recordImmediateFailure(action: action, modelId: model.id, msg: fallback)
        }
    }
}
