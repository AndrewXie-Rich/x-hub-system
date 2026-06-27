import Foundation
import RELFlowHubCore

extension ModelStore {
    func shouldPrepareManagedLocalModel(
        action: String,
        model: HubModel
    ) -> Bool {
        guard SharedPaths.isSandboxedProcess() else { return false }
        guard !isRemoteModel(model) else { return false }
        guard ["load", "warmup", "bench"].contains(action) else { return false }
        guard !localModelPreparationInFlightModelIds.contains(model.id) else { return false }
        return LocalModelManagedStorage.needsManagedPreparation(
            modelPath: model.modelPath ?? ""
        )
    }

    func prepareManagedLocalModelAndRetry(
        action: String,
        model: HubModel,
        allowRuntimeRecovery: Bool,
        targetPreferenceOverride: LocalModelRuntimeTargetPreference?
    ) {
        guard let sourceEntry = catalogEntry(for: model) else {
            recordImmediateFailure(
                action: action,
                modelId: model.id,
                msg: HubUIStrings.Models.Runtime.ActionPlanner.unresolvedLocalModelPath(model.name)
            )
            return
        }

        let requestID = UUID().uuidString
        localModelPreparationInFlightModelIds.insert(model.id)
        pendingByModelId[model.id] = PendingCommand(
            reqId: requestID,
            action: "prepare_local_model",
            requestedAt: Date().timeIntervalSince1970
        )

        Task { @MainActor in
            do {
                let baseDir = SharedPaths.ensureHubDirectory()
                let preparedEntry = try await Task.detached(priority: .userInitiated) {
                    try LocalModelManagedStorage.preparedCatalogEntryIfNeeded(
                        sourceEntry,
                        sandboxed: SharedPaths.isSandboxedProcess(),
                        baseDir: baseDir
                    )
                }.value
                self.applyPreparedCatalogEntry(preparedEntry)
                self.localModelPreparationInFlightModelIds.remove(model.id)
                self.pendingByModelId.removeValue(forKey: model.id)
                self.enqueue(
                    action: action,
                    modelId: model.id,
                    allowRuntimeRecovery: allowRuntimeRecovery,
                    targetPreferenceOverride: targetPreferenceOverride
                )
            } catch {
                self.localModelPreparationInFlightModelIds.remove(model.id)
                self.pendingByModelId.removeValue(forKey: model.id)
                self.recordImmediateFailure(
                    action: action,
                    modelId: model.id,
                    msg: HubUIStrings.Models.Runtime.ActionPlanner.prepareLocalModelFailed(error.localizedDescription)
                )
            }
        }
    }

}
