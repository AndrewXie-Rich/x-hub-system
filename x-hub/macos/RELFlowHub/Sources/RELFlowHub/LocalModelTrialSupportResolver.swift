import Foundation
import RELFlowHubCore

enum LocalModelTrialRoute: Equatable {
    case textGenerate
    case quickBench(taskKind: String, fixtureProfile: String)
}

struct LocalModelTrialSupportError: LocalizedError, Equatable {
    let message: String

    var errorDescription: String? { message }
}

struct LocalModelDefaultBenchSelection: Equatable {
    let taskKind: String
    let fixtureProfile: String
}

enum LocalModelTrialSupportResolver {
    static func resolveTrialRoute(
        for model: HubModel,
        runtimeStatus: AIRuntimeStatus?,
        probeLaunchConfig: LocalRuntimePythonProbeLaunchConfig?,
        pythonPath: String?
    ) -> Result<LocalModelTrialRoute, LocalModelTrialSupportError> {
        if let failure = blockedMessage(
            for: model,
            runtimeStatus: runtimeStatus,
            probeLaunchConfig: probeLaunchConfig,
            pythonPath: pythonPath
        ) {
            return .failure(LocalModelTrialSupportError(message: failure))
        }

        if LocalTaskRoutingCatalog.supportedTaskKinds(in: model.taskKinds).contains("text_generate") {
            return .success(.textGenerate)
        }

        switch resolveDefaultBenchSelection(
            for: model,
            runtimeStatus: runtimeStatus,
            probeLaunchConfig: probeLaunchConfig,
            pythonPath: pythonPath
        ) {
        case .success(let selection):
            return .success(
                .quickBench(
                    taskKind: selection.taskKind,
                    fixtureProfile: selection.fixtureProfile
                )
            )
        case .failure(let message):
            return .failure(message)
        }
    }

    static func resolveDefaultBenchSelection(
        for model: HubModel,
        runtimeStatus: AIRuntimeStatus?,
        probeLaunchConfig: LocalRuntimePythonProbeLaunchConfig?,
        pythonPath: String?
    ) -> Result<LocalModelDefaultBenchSelection, LocalModelTrialSupportError> {
        if let failure = blockedMessage(
            for: model,
            runtimeStatus: runtimeStatus,
            probeLaunchConfig: probeLaunchConfig,
            pythonPath: pythonPath
        ) {
            return .failure(LocalModelTrialSupportError(message: failure))
        }

        let providerID = LocalModelRuntimeActionPlanner.providerID(for: model)
        let descriptors = LocalModelBenchCapabilityPolicy.benchableDescriptors(
            for: model,
            runtimeStatus: runtimeStatus,
            probeLaunchConfig: probeLaunchConfig,
            pythonPath: pythonPath
        )
        if let taskKind = descriptors.first?.taskKind {
            guard let fixtureProfile = LocalBenchFixtureCatalog.defaultFixtureID(
                for: taskKind,
                providerID: providerID
            ) else {
                return .failure(
                    LocalModelTrialSupportError(
                        message: HubUIStrings.Models.Review.Bench.fixtureUnavailable(
                            LocalTaskRoutingCatalog.title(for: taskKind)
                        )
                    )
                )
            }
            return .success(
                LocalModelDefaultBenchSelection(
                    taskKind: taskKind,
                    fixtureProfile: fixtureProfile
                )
            )
        }

        let supportedTaskKinds = LocalTaskRoutingCatalog.supportedTaskKinds(in: model.taskKinds)
        guard !supportedTaskKinds.isEmpty else {
            return .failure(
                LocalModelTrialSupportError(
                    message: HubUIStrings.Models.Review.CapabilityPolicy.missingTaskKind
                )
            )
        }

        for taskKind in supportedTaskKinds {
            if let message = LocalModelBenchCapabilityPolicy.unsupportedTaskMessage(
                for: model,
                taskKind: taskKind,
                runtimeStatus: runtimeStatus,
                probeLaunchConfig: probeLaunchConfig,
                pythonPath: pythonPath
            ) {
                return .failure(LocalModelTrialSupportError(message: message))
            }
            if LocalBenchFixtureCatalog.defaultFixtureID(
                for: taskKind,
                providerID: providerID
            ) == nil {
                return .failure(
                    LocalModelTrialSupportError(
                        message: HubUIStrings.Models.Review.Bench.fixtureUnavailable(
                            LocalTaskRoutingCatalog.title(for: taskKind)
                        )
                    )
                )
            }
        }

        return .failure(
            LocalModelTrialSupportError(
                message: HubUIStrings.Models.Review.Bench.noRegisteredTasks
            )
        )
    }

    static func unavailabilityMessage(
        for model: HubModel,
        runtimeStatus: AIRuntimeStatus?,
        probeLaunchConfig: LocalRuntimePythonProbeLaunchConfig?,
        pythonPath: String?
    ) -> String? {
        switch resolveTrialRoute(
            for: model,
            runtimeStatus: runtimeStatus,
            probeLaunchConfig: probeLaunchConfig,
            pythonPath: pythonPath
        ) {
        case .success:
            return nil
        case .failure(let error):
            return error.message
        }
    }

    private static func blockedMessage(
        for model: HubModel,
        runtimeStatus: AIRuntimeStatus?,
        probeLaunchConfig: LocalRuntimePythonProbeLaunchConfig?,
        pythonPath: String?
    ) -> String? {
        let modelPath = (model.modelPath ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !modelPath.isEmpty else {
            return HubUIStrings.Models.RuntimeError.missingModelPath
        }

        if let compatibilityBlock = LocalModelRuntimeCompatibilityPolicy.blockedActionMessage(
            action: "load",
            model: model,
            probeLaunchConfig: probeLaunchConfig,
            pythonPath: pythonPath
        ) {
            return compatibilityBlock
        }

        guard let runtimeStatus,
              runtimeStatus.isAlive(ttl: AIRuntimeStatus.recommendedHeartbeatTTL) else {
            return LocalModelRuntimeActionPlanner.runtimeStartMessage
        }

        let providerID = LocalModelRuntimeActionPlanner.providerID(for: model)
        guard runtimeStatus.isProviderReady(providerID, ttl: AIRuntimeStatus.recommendedHeartbeatTTL) else {
            return providerUnavailableMessage(
                providerID: providerID,
                runtimeStatus: runtimeStatus
            )
        }

        return nil
    }

    private static func providerUnavailableMessage(
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
}
