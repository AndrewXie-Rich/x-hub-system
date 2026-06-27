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
            switch LocalModelRuntimeActionPlanner.plan(action: "bench", model: model, runtimeStatus: runtimeStatus) {
            case .legacyModelCommand(let routedAction):
                enqueueLegacyModelCommand(
                    action: routedAction,
                    model: model,
                    runtimeStatus: runtimeStatus,
                    targetPreferenceOverride: nil
                )
            case .providerLifecycleCommand:
                recordImmediateFailure(
                    action: "bench",
                    modelId: modelId,
                    msg: HubUIStrings.Models.Review.QuickBenchRunner.lifecycleNotImplemented
                )
            case .immediateFailure(let message):
                recordImmediateFailure(action: "bench", modelId: modelId, msg: message)
            }
            return
        }

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
        let fixture = LocalBenchFixtureCatalog.fixture(id: normalizedFixtureProfile)
        let fixtureTitle = fixture?.title ?? ""
        let benchPlan = LocalModelQuickBenchPlanner.prepare(
            model: model,
            taskKind: normalizedTaskKind,
            runtimeStatus: runtimeStatus,
            requestContext: initialRequestContext
        )

        if benchPlan.requiresWarmup {
            dispatchBenchWarmupThenRun(
                modelId: modelId,
                providerID: providerID,
                taskKind: normalizedTaskKind,
                fixtureProfile: normalizedFixtureProfile,
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
            taskKind: normalizedTaskKind,
            fixtureProfile: normalizedFixtureProfile,
            fixtureTitle: fixtureTitle,
            requestContext: benchPlan.requestContext,
            launchConfig: launchConfig,
            requestID: requestID
        )
    }

    func startDefaultBench(for model: HubModel) {
        let providerID = LocalModelRuntimeActionPlanner.providerID(for: model)
        let probeLaunchConfig = HubStore.shared.localRuntimePythonProbeLaunchConfig(
            preferredProviderID: providerID
        )
        let pythonPath = probeLaunchConfig?.resolvedPythonPath
            ?? HubStore.shared.preferredLocalProviderPythonPath(preferredProviderID: providerID)
        switch LocalModelTrialSupportResolver.resolveDefaultBenchSelection(
            for: model,
            runtimeStatus: AIRuntimeStatusStorage.load(),
            probeLaunchConfig: probeLaunchConfig,
            pythonPath: pythonPath
        ) {
        case .success(let selection):
            runBench(
                modelId: model.id,
                taskKind: selection.taskKind,
                fixtureProfile: selection.fixtureProfile
            )
        case .failure(let error):
            recordImmediateFailure(
                action: "bench",
                modelId: model.id,
                msg: error.message
            )
        }
    }


}
