import Foundation
import RELFlowHubCore

struct LocalLibraryRuntimeReadiness: Equatable {
    enum State: Equatable {
        case unavailable
        case ready
    }

    var state: State
    var detail: String

    static func unavailable(_ detail: String = "") -> LocalLibraryRuntimeReadiness {
        LocalLibraryRuntimeReadiness(state: .unavailable, detail: detail)
    }

    static func ready(_ detail: String = "") -> LocalLibraryRuntimeReadiness {
        LocalLibraryRuntimeReadiness(state: .ready, detail: detail)
    }
}

struct LocalLibraryRuntimeProviderProbe {
    var launchConfigAvailable: Bool
    var probeLaunchConfig: LocalRuntimePythonProbeLaunchConfig?
    var pythonPath: String?
}

enum LocalLibraryRuntimeReadinessResolver {
    typealias TTSReadinessEvaluator = (String) -> IPCVoiceTTSReadinessResult
    typealias LaunchConfigAvailabilityResolver = (String) -> Bool
    typealias CompatibilityEvaluator = (HubModel, String) -> String?
    typealias TrialSurfaceEvaluator = (HubModel, String) -> String?

    @MainActor
    static func readiness(
        for model: HubModel,
        ttsReadinessEvaluator: TTSReadinessEvaluator? = nil,
        commandLaunchConfigResolver: LaunchConfigAvailabilityResolver? = nil,
        compatibilityEvaluator: CompatibilityEvaluator? = nil,
        trialSurfaceEvaluator: TrialSurfaceEvaluator? = nil
    ) -> LocalLibraryRuntimeReadiness {
        let strings = HubUIStrings.Models.Library.RuntimeReadiness.self
        guard !LocalModelRuntimeActionPlanner.isRemoteModel(model) else {
            return .unavailable(strings.nonLocalModel)
        }

        let resolvedTTSReadinessEvaluator = ttsReadinessEvaluator ?? { modelID in
            HubVoiceTTSSynthesisService.playbackReadiness(
                IPCVoiceTTSReadinessRequestPayload(preferredModelID: modelID)
            )
        }
        let resolvedLaunchConfigResolver = commandLaunchConfigResolver ?? { preferredProviderID in
            HubStore.shared.canResolveLocalRuntimeCommandLaunchConfig(
                preferredProviderID: preferredProviderID
            )
        }
        let resolvedCompatibilityEvaluator = compatibilityEvaluator ?? { model, providerID in
            LocalModelRuntimeCompatibilityPolicy.blockedActionMessage(
                action: "load",
                model: model,
                probeLaunchConfig: HubStore.shared.localRuntimePythonProbeLaunchConfig(
                    preferredProviderID: providerID
                ),
                pythonPath: HubStore.shared.preferredLocalProviderPythonPath(
                    preferredProviderID: providerID
                )
            )
        }
        let resolvedTrialSurfaceEvaluator = trialSurfaceEvaluator ?? { model, providerID in
            let probeLaunchConfig = HubStore.shared.localRuntimePythonProbeLaunchConfig(
                preferredProviderID: providerID
            )
            return LocalModelTrialSupportResolver.unavailabilityMessage(
                for: model,
                runtimeStatus: AIRuntimeStatusStorage.load(),
                probeLaunchConfig: probeLaunchConfig,
                pythonPath: probeLaunchConfig?.resolvedPythonPath
                    ?? HubStore.shared.preferredLocalProviderPythonPath(
                        preferredProviderID: providerID
                    )
            )
        }

        if model.taskKinds.contains("text_to_speech") {
            let readiness = resolvedTTSReadinessEvaluator(model.id)
            if readiness.ok {
                return .ready(strings.voicePlaybackReady)
            }
            let readinessDetail = (readiness.detail ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let fallbackReason = LocalModelRuntimeErrorPresentation.humanized(
                (readiness.reasonCode ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            )
            let detail = collapsedDetail(readinessDetail.isEmpty ? fallbackReason : readinessDetail)
            return .unavailable(
                detail.isEmpty
                    ? strings.voicePlaybackUnavailable
                    : detail
            )
        }

        let providerID = LocalModelExecutionProviderResolver.preferredRuntimeProviderID(for: model)
        guard resolvedLaunchConfigResolver(providerID) else {
            return .unavailable(strings.launchConfigUnavailable(providerID))
        }

        if let blockedMessage = resolvedCompatibilityEvaluator(model, providerID) {
            return .unavailable(collapsedDetail(blockedMessage))
        }

        if let trialSurfaceMessage = resolvedTrialSurfaceEvaluator(model, providerID) {
            return .unavailable(collapsedDetail(trialSurfaceMessage))
        }

        return .ready(strings.localExecutionReady)
    }

    static func collapsedDetail(_ raw: String) -> String {
        raw
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

@MainActor
final class LocalLibraryRuntimeReadinessSession {
    typealias ProviderProbeResolver = (String) -> LocalLibraryRuntimeProviderProbe
    typealias TTSReadinessEvaluator = LocalLibraryRuntimeReadinessResolver.TTSReadinessEvaluator
    typealias CompatibilityEvaluator = (HubModel, LocalLibraryRuntimeProviderProbe) -> String?
    typealias TrialSurfaceEvaluator = (HubModel, LocalLibraryRuntimeProviderProbe) -> String?

    private let ttsReadinessEvaluator: TTSReadinessEvaluator?
    private let providerProbeResolver: ProviderProbeResolver
    private let compatibilityEvaluator: CompatibilityEvaluator
    private let trialSurfaceEvaluator: TrialSurfaceEvaluator
    private var providerProbeByID: [String: LocalLibraryRuntimeProviderProbe] = [:]

    init(
        ttsReadinessEvaluator: TTSReadinessEvaluator? = nil,
        providerProbeResolver: @escaping ProviderProbeResolver,
        compatibilityEvaluator: @escaping CompatibilityEvaluator = { model, providerProbe in
            LocalModelRuntimeCompatibilityPolicy.blockedActionMessage(
                action: "load",
                model: model,
                probeLaunchConfig: providerProbe.probeLaunchConfig,
                pythonPath: providerProbe.pythonPath
            )
        },
        trialSurfaceEvaluator: @escaping TrialSurfaceEvaluator = { model, providerProbe in
            LocalModelTrialSupportResolver.unavailabilityMessage(
                for: model,
                runtimeStatus: AIRuntimeStatusStorage.load(),
                probeLaunchConfig: providerProbe.probeLaunchConfig,
                pythonPath: providerProbe.pythonPath
            )
        }
    ) {
        self.ttsReadinessEvaluator = ttsReadinessEvaluator
        self.providerProbeResolver = providerProbeResolver
        self.compatibilityEvaluator = compatibilityEvaluator
        self.trialSurfaceEvaluator = trialSurfaceEvaluator
    }

    func readiness(for model: HubModel) -> LocalLibraryRuntimeReadiness {
        LocalLibraryRuntimeReadinessResolver.readiness(
            for: model,
            ttsReadinessEvaluator: ttsReadinessEvaluator,
            commandLaunchConfigResolver: { [weak self] providerID in
                self?.providerProbe(for: providerID).launchConfigAvailable ?? false
            },
            compatibilityEvaluator: { [weak self] model, providerID in
                guard let self else { return nil }
                return self.compatibilityEvaluator(model, self.providerProbe(for: providerID))
            },
            trialSurfaceEvaluator: { [weak self] model, providerID in
                guard let self else { return nil }
                return self.trialSurfaceEvaluator(model, self.providerProbe(for: providerID))
            }
        )
    }

    private func providerProbe(for providerID: String) -> LocalLibraryRuntimeProviderProbe {
        let normalizedProviderID = providerID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let cached = providerProbeByID[normalizedProviderID] {
            return cached
        }
        let resolved = providerProbeResolver(normalizedProviderID)
        providerProbeByID[normalizedProviderID] = resolved
        return resolved
    }
}
