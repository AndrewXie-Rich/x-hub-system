import Foundation
import RELFlowHubCore

extension ModelStore {
    func runBench(modelId: String, taskKind: String, fixtureProfile: String) {
        guard let model = snapshot.models.first(where: { $0.id == modelId }) else { return }
        guard !isRemoteModel(model) else {
            recordImmediateFailure(
                action: "bench",
                modelId: modelId,
                msg: HubUIStrings.Models.Review.QuickBenchRunner.remoteModelUnsupported
            )
            return
        }

        let normalizedTaskKind = taskKind.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedFixtureProfile = fixtureProfile.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTaskKind.isEmpty else {
            recordImmediateFailure(
                action: "bench",
                modelId: modelId,
                msg: HubUIStrings.Models.Review.CapabilityPolicy.missingTaskKind
            )
            return
        }
        guard !normalizedFixtureProfile.isEmpty else {
            recordImmediateFailure(
                action: "bench",
                modelId: modelId,
                msg: HubUIStrings.Models.Review.QuickBenchRunner.missingFixtureProfile
            )
            return
        }

        let providerID = LocalModelRuntimeActionPlanner.providerID(for: model)
        let runtimeStatus = AIRuntimeStatusStorage.load()
        if let unsupportedMessage = LocalModelBenchCapabilityPolicy.unsupportedTaskMessage(
            for: model,
            taskKind: normalizedTaskKind,
            runtimeStatus: runtimeStatus,
            probeLaunchConfig: HubStore.shared.localRuntimePythonProbeLaunchConfig(
                preferredProviderID: providerID
            ),
            pythonPath: HubStore.shared.preferredLocalProviderPythonPath(
                preferredProviderID: providerID
            )
        ) {
            recordImmediateFailure(action: "bench", modelId: modelId, msg: unsupportedMessage)
            return
        }

        let controlMode = LocalRuntimeProviderPolicy.resolvedControlMode(
            providerID: providerID,
            taskKinds: model.taskKinds,
            providerStatus: runtimeStatus?.providerStatus(providerID)
        )
        if controlMode == .mlxLegacy {
            dispatchLegacyQuickBenchRoute(
                modelId: modelId,
                model: model,
                runtimeStatus: runtimeStatus
            )
            return
        }

        dispatchRuntimeQuickBench(
            modelId: modelId,
            model: model,
            providerID: providerID,
            taskKind: normalizedTaskKind,
            runtimeStatus: runtimeStatus,
            fixtureProfile: normalizedFixtureProfile,
            fixtureTitle: LocalBenchFixtureCatalog.fixture(id: normalizedFixtureProfile)?.title ?? ""
        )
    }
}
