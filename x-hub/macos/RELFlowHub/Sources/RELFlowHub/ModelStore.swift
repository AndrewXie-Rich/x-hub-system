import Foundation
import SwiftUI
import RELFlowHubCore

enum LocalModelRuntimeActionRoute: Equatable {
    case legacyModelCommand(action: String)
    case providerLifecycleCommand(action: String)
    case immediateFailure(message: String)
}

struct LocalModelRuntimePresentation: Equatable {
    var providerID: String
    var controlMode: AIRuntimeProviderHubControlMode
    var lifecycleMode: String
    var residencyScope: String
    var providerReady: Bool
    var supportsWarmup: Bool
    var supportsUnload: Bool
    var supportsBench: Bool

    var badgeTitle: String {
        switch controlMode {
        case .mlxLegacy:
            return HubUIStrings.Models.Runtime.ActionPlanner.mlxLegacyBadge
        case .warmable:
            return HubUIStrings.Models.Runtime.ActionPlanner.warmableBadge
        case .ephemeralOnDemand:
            return HubUIStrings.Models.Runtime.ActionPlanner.onDemandBadge
        }
    }

    var badgeSystemName: String {
        switch controlMode {
        case .mlxLegacy:
            return "cpu"
        case .warmable:
            return "flame"
        case .ephemeralOnDemand:
            return "bolt.horizontal"
        }
    }
}

struct LocalModelRuntimeTargetOption: Identifiable, Equatable {
    enum Kind: String, Equatable {
        case auto
        case pairedDevice = "paired_device"
        case loadedInstance = "loaded_instance"
    }

    var kind: Kind
    var deviceID: String
    var instanceKey: String
    var title: String
    var detail: String

    var id: String {
        "\(kind.rawValue)::\(deviceID)::\(instanceKey)"
    }

    var isAuto: Bool {
        kind == .auto
    }
}

struct LocalModelQuickBenchPreparationPlan: Equatable {
    var requestContext: LocalModelRuntimeRequestContext
    var requiresWarmup: Bool
}

enum LocalModelQuickBenchPlanner {
    static func prepare(
        model: HubModel,
        taskKind: String,
        runtimeStatus: AIRuntimeStatus?,
        requestContext: LocalModelRuntimeRequestContext
    ) -> LocalModelQuickBenchPreparationPlan {
        let providerID = LocalModelRuntimeActionPlanner.providerID(for: model)
        let providerStatus = runtimeStatus?.providerStatus(providerID)
        let controlMode = LocalRuntimeProviderPolicy.resolvedControlMode(
            providerID: providerID,
            taskKinds: model.taskKinds,
            providerStatus: providerStatus
        )
        guard controlMode == .warmable,
              let providerStatus,
              providerStatus.supportsWarmup(forModelTaskKinds: model.taskKinds),
              !matchesResidentTarget(
                modelID: model.id,
                taskKind: taskKind,
                requestContext: requestContext,
                loadedInstances: providerStatus.loadedInstances
              ) else {
            return LocalModelQuickBenchPreparationPlan(
                requestContext: requestContext,
                requiresWarmup: false
            )
        }

        return LocalModelQuickBenchPreparationPlan(
            requestContext: requestContext,
            requiresWarmup: true
        )
    }

    static func updatedRequestContext(
        fromWarmupPayload payload: [String: Any],
        fallback: LocalModelRuntimeRequestContext
    ) -> LocalModelRuntimeRequestContext {
        let resolvedInstanceKey = (payload["instanceKey"] as? String ?? payload["instance_key"] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedLoadProfileHash = (payload["loadProfileHash"] as? String ?? payload["load_profile_hash"] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedContextLength = max(
            0,
            payload["effectiveContextLength"] as? Int
                ?? payload["effective_context_length"] as? Int
                ?? fallback.effectiveContextLength
        )
        return LocalModelRuntimeRequestContext(
            providerID: fallback.providerID,
            modelID: fallback.modelID,
            deviceID: fallback.deviceID,
            instanceKey: resolvedInstanceKey,
            loadProfileHash: resolvedLoadProfileHash,
            predictedLoadProfileHash: !resolvedLoadProfileHash.isEmpty
                ? resolvedLoadProfileHash
                : fallback.predictedLoadProfileHash,
            effectiveContextLength: resolvedContextLength,
            loadProfileOverride: fallback.loadProfileOverride,
            effectiveLoadProfile: updatedEffectiveLoadProfile(
                fallback.effectiveLoadProfile,
                contextLength: resolvedContextLength
            ),
            source: "bench_auto_warmup"
        )
    }

    private static func updatedEffectiveLoadProfile(
        _ profile: LocalModelLoadProfile?,
        contextLength: Int
    ) -> LocalModelLoadProfile? {
        guard let profile else {
            guard contextLength > 0 else { return nil }
            return LocalModelLoadProfile(contextLength: contextLength)
        }
        let resolvedContextLength = contextLength > 0 ? contextLength : profile.contextLength
        return LocalModelLoadProfile(
            contextLength: resolvedContextLength,
            gpuOffloadRatio: profile.gpuOffloadRatio,
            ropeFrequencyBase: profile.ropeFrequencyBase,
            ropeFrequencyScale: profile.ropeFrequencyScale,
            evalBatchSize: profile.evalBatchSize,
            ttl: profile.ttl,
            parallel: profile.parallel,
            identifier: profile.identifier,
            vision: profile.vision
        )
    }

    private static func matchesResidentTarget(
        modelID: String,
        taskKind: String,
        requestContext: LocalModelRuntimeRequestContext,
        loadedInstances: [AIRuntimeLoadedInstance]
    ) -> Bool {
        let normalizedTaskKind = taskKind.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return loadedInstances.contains { loaded in
            guard loaded.modelId == modelID else { return false }
            if !normalizedTaskKind.isEmpty,
               !loaded.taskKinds.isEmpty,
               !loaded.taskKinds.contains(normalizedTaskKind) {
                return false
            }
            if !requestContext.instanceKey.isEmpty {
                return loaded.instanceKey == requestContext.instanceKey
            }
            if !requestContext.preferredBenchHash.isEmpty,
               !loaded.loadProfileHash.isEmpty {
                return loaded.loadProfileHash == requestContext.preferredBenchHash
            }
            if requestContext.effectiveContextLength > 0,
               loaded.effectiveContextLength > 0 {
                return loaded.effectiveContextLength == requestContext.effectiveContextLength
            }
            return true
        }
    }
}

enum LocalModelRuntimeActionPlanner {
    static let runtimeStartMessage = HubUIStrings.Models.Runtime.ActionPlanner.runtimeStartMessage

    static func isRemoteModel(_ model: HubModel) -> Bool {
        let modelPath = (model.modelPath ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !modelPath.isEmpty {
            return false
        }
        return providerID(for: model) != "mlx"
    }

    static func providerID(for model: HubModel) -> String {
        LocalModelExecutionProviderResolver.preferredRuntimeProviderID(for: model)
    }

    static func presentation(
        for model: HubModel,
        runtimeStatus: AIRuntimeStatus? = nil
    ) -> LocalModelRuntimePresentation? {
        guard !isRemoteModel(model) else { return nil }
        let providerID = providerID(for: model)
        let providerStatus = runtimeStatus?.providerStatus(providerID)
        let controlMode = LocalRuntimeProviderPolicy.resolvedControlMode(
            providerID: providerID,
            taskKinds: model.taskKinds,
            providerStatus: providerStatus
        )
        let providerReady = runtimeStatus?.isProviderReady(providerID, ttl: AIRuntimeStatus.recommendedHeartbeatTTL) ?? false
        let supportsWarmup = controlMode == .warmable && (providerStatus?.supportsWarmup(forModelTaskKinds: model.taskKinds) ?? false)
        let supportsUnload = LocalRuntimeProviderPolicy.supportsUnload(
            providerID: providerID,
            taskKinds: model.taskKinds,
            providerStatus: providerStatus
        )
        let supportsBench = !LocalModelBenchCapabilityPolicy.benchableDescriptors(
            for: model,
            runtimeStatus: runtimeStatus
        ).isEmpty
        return LocalModelRuntimePresentation(
            providerID: providerID,
            controlMode: controlMode,
            lifecycleMode: providerStatus?.lifecycleMode ?? "",
            residencyScope: providerStatus?.residencyScope ?? "",
            providerReady: providerReady,
            supportsWarmup: supportsWarmup,
            supportsUnload: supportsUnload,
            supportsBench: supportsBench
        )
    }

    static func plan(
        action: String,
        model: HubModel,
        runtimeStatus: AIRuntimeStatus?
    ) -> LocalModelRuntimeActionRoute {
        guard !isRemoteModel(model) else {
            return .immediateFailure(message: HubUIStrings.Models.Runtime.ActionPlanner.remoteModelControlUnsupported)
        }
        guard let runtimeStatus else {
            return .immediateFailure(message: runtimeStartMessage)
        }
        guard runtimeStatus.isAlive(ttl: AIRuntimeStatus.recommendedHeartbeatTTL) else {
            return .immediateFailure(message: runtimeStartMessage)
        }

        let providerID = providerID(for: model)
        let resolvedControlMode = LocalRuntimeProviderPolicy.resolvedControlMode(
            providerID: providerID,
            taskKinds: model.taskKinds,
            providerStatus: runtimeStatus.providerStatus(providerID)
        )
        let presentation = presentation(for: model, runtimeStatus: runtimeStatus)
            ?? LocalModelRuntimePresentation(
                providerID: providerID,
                controlMode: resolvedControlMode,
                lifecycleMode: "",
                residencyScope: "",
                providerReady: false,
                supportsWarmup: false,
                supportsUnload: LocalRuntimeProviderPolicy.supportsUnload(
                    providerID: providerID,
                    taskKinds: model.taskKinds,
                    providerStatus: runtimeStatus.providerStatus(providerID)
                ),
                supportsBench: !LocalModelBenchCapabilityPolicy.benchableDescriptors(for: model).isEmpty
            )

        guard runtimeStatus.isProviderReady(providerID, ttl: AIRuntimeStatus.recommendedHeartbeatTTL) else {
            return .immediateFailure(message: providerUnavailableMessage(providerID: providerID, runtimeStatus: runtimeStatus))
        }

        switch presentation.controlMode {
        case .mlxLegacy:
            return .legacyModelCommand(action: legacyCommandAction(for: action))
        case .warmable:
            guard let lifecycleAction = providerLifecycleAction(for: action) else {
                return .immediateFailure(
                    message: warmableActionUnsupportedMessage(
                        action: action,
                        providerID: providerID,
                        controlMode: presentation.controlMode
                    )
                )
            }
            return .providerLifecycleCommand(action: lifecycleAction)
        case .ephemeralOnDemand:
            if action.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "unload",
               presentation.supportsUnload,
               let lifecycleAction = providerLifecycleAction(for: action) {
                return .providerLifecycleCommand(action: lifecycleAction)
            }
            return .immediateFailure(
                message: onDemandActionBlockedMessage(
                    action: action,
                    providerID: providerID,
                    residencyScope: presentation.residencyScope,
                    lifecycleMode: presentation.lifecycleMode,
                    controlMode: presentation.controlMode
                )
            )
        }
    }

    private static func legacyCommandAction(for action: String) -> String {
        let normalized = action.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized == "warmup" {
            return "load"
        }
        return normalized
    }

    private static func providerLifecycleAction(for action: String) -> String? {
        let normalized = action.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "load", "warmup":
            return "warmup_local_model"
        case "unload":
            return "unload_local_model"
        case "evict":
            return "evict_local_instance"
        default:
            return nil
        }
    }

    private static func actionDisplayName(
        _ action: String,
        controlMode: AIRuntimeProviderHubControlMode
    ) -> String {
        let normalized = action.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "load":
            return controlMode == .mlxLegacy
                ? HubUIStrings.Models.Runtime.ActionPlanner.load
                : HubUIStrings.Models.Runtime.ActionPlanner.warmup
        case "warmup":
            return HubUIStrings.Models.Runtime.ActionPlanner.warmup
        case "sleep":
            return HubUIStrings.Models.Runtime.ActionPlanner.sleep
        case "unload":
            return HubUIStrings.Models.Runtime.ActionPlanner.unload
        case "bench":
            return HubUIStrings.Models.Runtime.ActionPlanner.bench
        case "evict":
            return HubUIStrings.Models.Runtime.ActionPlanner.evict
        default:
            return normalized.isEmpty ? HubUIStrings.Models.Runtime.ActionPlanner.defaultAction : normalized
        }
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

    private static func warmableActionUnsupportedMessage(
        action: String,
        providerID: String,
        controlMode: AIRuntimeProviderHubControlMode
    ) -> String {
        let displayAction = actionDisplayName(action, controlMode: controlMode)
        return HubUIStrings.Models.Runtime.ActionPlanner.warmableActionUnsupported(
            providerID: providerID,
            actionTitle: displayAction
        )
    }

    private static func onDemandActionBlockedMessage(
        action: String,
        providerID: String,
        residencyScope: String,
        lifecycleMode: String,
        controlMode: AIRuntimeProviderHubControlMode
    ) -> String {
        let displayAction = actionDisplayName(action, controlMode: controlMode)
        let scope = residencyScope.isEmpty ? "process_local" : residencyScope
        let lifecycle = lifecycleMode.isEmpty ? "ephemeral_on_demand" : lifecycleMode
        return HubUIStrings.Models.Runtime.ActionPlanner.onDemandActionBlocked(
            providerID: providerID,
            lifecycle: lifecycle,
            scope: scope,
            actionTitle: displayAction
        )
    }
}

@MainActor
final class ModelStore: ObservableObject {
    static let shared = ModelStore()
    nonisolated private static let successfulLifecycleActionGraceSec: TimeInterval = 8.0

    private struct OptionalRuntimePresentationCacheEntry {
        let value: LocalModelRuntimePresentation?
    }

    private struct OptionalStringCacheEntry {
        let value: String?
    }

    private struct LocalRuntimeSupportInputs {
        let providerID: String
        let probeLaunchConfig: LocalRuntimePythonProbeLaunchConfig?
        let pythonPath: String?
    }

    private struct CommandResultFile: Sendable {
        let url: URL
        let result: ModelCommandResult
    }

    private struct RefreshComputation: Sendable {
        let baseSnapshot: ModelStateSnapshot
        let reconciledSnapshot: ModelStateSnapshot
        let runtimeStatus: AIRuntimeStatus?
        let benchSnapshot: ModelsBenchSnapshot
        let pairedProfilesSnapshot: HubPairedTerminalLocalModelProfilesSnapshot
        let targetPreferenceByModelId: [String: LocalModelRuntimeTargetPreference]
        let requestContextByModelId: [String: LocalModelRuntimeRequestContext]
        let benchByModelId: [String: ModelBenchResult]
        let decodedCommandResults: [CommandResultFile]
        let invalidCommandResultURLs: [URL]
    }

    @Published private(set) var snapshot: ModelStateSnapshot = .empty()
    @Published private(set) var benchSnapshot: ModelsBenchSnapshot = .empty()
    @Published private(set) var benchByModelId: [String: ModelBenchResult] = [:]
    @Published private(set) var currentLocalRuntimeRequestContextByModelId: [String: LocalModelRuntimeRequestContext] = [:]
    @Published private(set) var pendingByModelId: [String: PendingCommand] = [:]
    @Published private(set) var lastResultByModelId: [String: ModelCommandResult] = [:]

    private var timer: Timer?
    private var runtimeRecoveryInFlightModelIds: Set<String> = []
    private var localModelPreparationInFlightModelIds: Set<String> = []
    private var localRuntimeSupportInputsCache: [String: LocalRuntimeSupportInputs] = [:]
    private var localRuntimePresentationCache: [String: OptionalRuntimePresentationCacheEntry] = [:]
    private var localRuntimeActionBlockedMessageCache: [String: OptionalStringCacheEntry] = [:]
    private var availableBenchTaskDescriptorsCache: [String: [LocalTaskRoutingDescriptor]] = [:]
    private var availableLocalRuntimeTargetOptionsCache: [String: [LocalModelRuntimeTargetOption]] = [:]
    private var currentRuntimeStatus: AIRuntimeStatus?
    private var currentPairedProfilesSnapshot: HubPairedTerminalLocalModelProfilesSnapshot = .empty()
    private var currentTargetPreferenceByModelId: [String: LocalModelRuntimeTargetPreference] = [:]
    private var successfulLocalLifecycleActionsByModelId: [String: SuccessfulLocalLifecycleAction] = [:]
    private var refreshTask: Task<Void, Never>?
    private var refreshRequestedRevision: UInt64 = 0

    private init() {
        migrateLegacyHomeModelsIfNeeded()
        backfillRuntimeProviderIDsIfNeeded()
        relinkManagedLocalModelsIfNeeded()
        pruneMissingManagedLocalModelsIfNeeded()
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }

        // Remove legacy demo models (note="demo", no modelPath) so the UI only shows real models.
        pruneLegacyDemoModels()
    }

    func refresh() {
        refreshRequestedRevision &+= 1
        scheduleRefreshIfNeeded()
    }

    private func resetDerivedUICaches() {
        localRuntimeSupportInputsCache.removeAll(keepingCapacity: true)
        localRuntimePresentationCache.removeAll(keepingCapacity: true)
        localRuntimeActionBlockedMessageCache.removeAll(keepingCapacity: true)
        availableBenchTaskDescriptorsCache.removeAll(keepingCapacity: true)
        availableLocalRuntimeTargetOptionsCache.removeAll(keepingCapacity: true)
    }

    private func scheduleRefreshIfNeeded() {
        guard refreshTask == nil else { return }

        let revision = refreshRequestedRevision
        let pendingSnapshot = pendingByModelId
        let lifecycleSnapshot = successfulLocalLifecycleActionsByModelId
        refreshTask = Task { [weak self] in
            let computation = await Task.detached(priority: .utility) {
                Self.buildRefreshComputation(
                    pendingByModelId: pendingSnapshot,
                    successfulLocalLifecycleActionsByModelId: lifecycleSnapshot
                )
            }.value
            self?.finishRefresh(
                revision: revision,
                computation: computation
            )
        }
    }

    private func finishRefresh(
        revision: UInt64,
        computation: RefreshComputation
    ) {
        refreshTask = nil

        if revision == refreshRequestedRevision {
            applyRefreshComputation(computation)
        } else {
            applyCommandResults(
                computation.decodedCommandResults,
                invalidURLs: computation.invalidCommandResultURLs
            )
            scheduleRefreshIfNeeded()
        }
    }

    private func applyRefreshComputation(_ computation: RefreshComputation) {
        resetDerivedUICaches()
        currentRuntimeStatus = computation.runtimeStatus
        snapshot = computation.reconciledSnapshot
        if computation.reconciledSnapshot != computation.baseSnapshot {
            ModelStateStorage.save(computation.reconciledSnapshot)
        }
        benchSnapshot = computation.benchSnapshot
        currentPairedProfilesSnapshot = computation.pairedProfilesSnapshot
        currentTargetPreferenceByModelId = computation.targetPreferenceByModelId
        benchByModelId = computation.benchByModelId
        currentLocalRuntimeRequestContextByModelId = computation.requestContextByModelId

        reconcilePendingWithState()
        reconcileSuccessfulLifecycleActionsWithRuntimeStatus()
        applyCommandResults(
            computation.decodedCommandResults,
            invalidURLs: computation.invalidCommandResultURLs
        )
        lastResultByModelId = Self.reconciledLastCommandResults(
            lastResultByModelId,
            snapshot: snapshot,
            runtimeStatus: currentRuntimeStatus
        )
    }

    private func applyCommandResults(
        _ decodedResults: [CommandResultFile],
        invalidURLs: [URL]
    ) {
        for entry in decodedResults {
            lastResultByModelId[entry.result.modelId] = entry.result
            if let pending = pendingByModelId[entry.result.modelId],
               pending.reqId == entry.result.reqId {
                pendingByModelId.removeValue(forKey: entry.result.modelId)
            }
            try? FileManager.default.removeItem(at: entry.url)
        }

        for url in invalidURLs {
            try? FileManager.default.removeItem(at: url)
        }
    }

    nonisolated private static func buildRefreshComputation(
        pendingByModelId: [String: PendingCommand],
        successfulLocalLifecycleActionsByModelId: [String: SuccessfulLocalLifecycleAction]
    ) -> RefreshComputation {
        let base = ModelStateStorage.load()
        let merged = mergeRemoteModels(base)
        let runtimeStatus = AIRuntimeStatusStorage.load()
        let reconciled = reconciledLocalRuntimeState(
            merged,
            runtimeStatus: runtimeStatus,
            pendingByModelId: pendingByModelId,
            successfulLocalLifecycleActionsByModelId: successfulLocalLifecycleActionsByModelId
        )
        let benchSnapshot = ModelBenchStorage.load()
        let pairedProfilesSnapshot = HubPairedTerminalLocalModelProfilesStorage.load()
        let targetPreferencesSnapshot = LocalModelRuntimeTargetPreferencesStorage.load()
        let targetPreferenceByModelId = Dictionary(
            uniqueKeysWithValues: targetPreferencesSnapshot.preferences.map { ($0.modelId, $0) }
        )
        let requestContextByModelId = buildRequestContextMap(
            models: reconciled.models,
            runtimeStatus: runtimeStatus,
            pairedProfilesSnapshot: pairedProfilesSnapshot,
            targetPreferenceByModelId: targetPreferenceByModelId
        )
        let benchByModelId = buildBenchMap(
            models: reconciled.models,
            benchSnapshot: benchSnapshot,
            requestContextByModelId: requestContextByModelId
        )
        let commandResults = collectCommandResults()
        return RefreshComputation(
            baseSnapshot: base,
            reconciledSnapshot: reconciled,
            runtimeStatus: runtimeStatus,
            benchSnapshot: benchSnapshot,
            pairedProfilesSnapshot: pairedProfilesSnapshot,
            targetPreferenceByModelId: targetPreferenceByModelId,
            requestContextByModelId: requestContextByModelId,
            benchByModelId: benchByModelId,
            decodedCommandResults: commandResults.decoded,
            invalidCommandResultURLs: commandResults.invalid
        )
    }

    nonisolated private static func buildRequestContextMap(
        models: [HubModel],
        runtimeStatus: AIRuntimeStatus?,
        pairedProfilesSnapshot: HubPairedTerminalLocalModelProfilesSnapshot,
        targetPreferenceByModelId: [String: LocalModelRuntimeTargetPreference]
    ) -> [String: LocalModelRuntimeRequestContext] {
        var map: [String: LocalModelRuntimeRequestContext] = [:]
        for model in models where !LocalModelRuntimeActionPlanner.isRemoteModel(model) {
            map[model.id] = LocalModelRuntimeRequestContextResolver.resolve(
                model: model,
                runtimeStatus: runtimeStatus,
                pairedProfilesSnapshot: pairedProfilesSnapshot,
                targetPreference: targetPreferenceByModelId[model.id]
            )
        }
        return map
    }

    nonisolated private static func buildBenchMap(
        models: [HubModel],
        benchSnapshot: ModelsBenchSnapshot,
        requestContextByModelId: [String: LocalModelRuntimeRequestContext]
    ) -> [String: ModelBenchResult] {
        var map: [String: ModelBenchResult] = [:]
        let benchByModel = Dictionary(grouping: benchSnapshot.results, by: \.modelId)
        for model in models {
            let rows = benchByModel[model.id] ?? []
            guard !rows.isEmpty else { continue }

            if let requestContext = requestContextByModelId[model.id],
               let matching = rows
                .filter({ requestContext.matchesBenchResult($0) })
                .sorted(by: isNewerBenchResult)
                .first {
                map[model.id] = matching
                continue
            }

            if let latest = rows.sorted(by: isNewerBenchResult).first {
                map[model.id] = latest
            }
        }
        return map
    }

    nonisolated private static func collectCommandResults() -> (decoded: [CommandResultFile], invalid: [URL]) {
        let directories = commandResultDirectoryCandidates()
        guard !directories.isEmpty else { return ([], []) }

        let decoder = JSONDecoder()
        let fileManager = FileManager.default
        var decoded: [CommandResultFile] = []
        var invalid: [URL] = []
        var seenFiles: Set<String> = []

        for directory in directories {
            guard let files = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            ) else {
                continue
            }

            for url in files where url.pathExtension.lowercased() == "json" {
                let standardizedPath = url.standardizedFileURL.path
                guard seenFiles.insert(standardizedPath).inserted else { continue }
                guard let data = try? Data(contentsOf: url) else {
                    invalid.append(url)
                    continue
                }
                guard let result = try? decoder.decode(ModelCommandResult.self, from: data) else {
                    invalid.append(url)
                    continue
                }
                decoded.append(CommandResultFile(url: url, result: result))
            }
        }

        return (decoded, invalid)
    }

    nonisolated private static func commandResultDirectoryCandidates() -> [URL] {
        var out: [URL] = []
        var seen: Set<String> = []

        func append(_ url: URL?) {
            guard let url else { return }
            let standardizedPath = url.standardizedFileURL.path
            guard seen.insert(standardizedPath).inserted else { return }
            out.append(url)
        }

        append(SharedPaths.appGroupDirectory()?.appendingPathComponent("model_results", isDirectory: true))
        for base in SharedPaths.hubDirectoryCandidates() {
            append(base.appendingPathComponent("model_results", isDirectory: true))
        }
        return out
    }

    private func localRuntimeSupportInputs(for model: HubModel) -> LocalRuntimeSupportInputs {
        let providerID = LocalModelRuntimeActionPlanner.providerID(for: model)
        if let cached = localRuntimeSupportInputsCache[providerID] {
            return cached
        }

        let cached = LocalRuntimeSupportInputs(
            providerID: providerID,
            probeLaunchConfig: HubStore.shared.localRuntimePythonProbeLaunchConfig(
                preferredProviderID: providerID
            ),
            pythonPath: HubStore.shared.preferredLocalProviderPythonPath(
                preferredProviderID: providerID
            )
        )
        // Probe/config resolution is provider-scoped, so sharing it across models
        // on the same provider avoids repeated Python subprocess probes when the
        // Models drawer renders many rows at once.
        localRuntimeSupportInputsCache[providerID] = cached
        return cached
    }

    func modelsLoaded() -> [HubModel] {
        snapshot.models.filter { $0.state == .loaded }
    }

    func modelsAvailable() -> [HubModel] {
        snapshot.models.filter { $0.state != .loaded }
    }

    nonisolated private static func mergeRemoteModels(_ base: ModelStateSnapshot) -> ModelStateSnapshot {
        let remote = RemoteModelStorage.exportableEnabledModels()

        // Keep local models (with a modelPath). Remove stale remote entries before re-adding.
        let localOnly = base.models.filter { !LocalModelRuntimeActionPlanner.isRemoteModel($0) }

        if remote.isEmpty {
            if localOnly.count == base.models.count {
                return base
            }
            return ModelStateSnapshot(models: localOnly, updatedAt: Date().timeIntervalSince1970)
        }

        var merged = localOnly
        for r in remote {
            if merged.contains(where: { $0.id == r.id }) {
                continue
            }
            let m = HubModel(
                id: r.id,
                name: r.name,
                backend: r.backend,
                quant: "remote",
                contextLength: max(512, r.contextLength),
                paramsB: 0.0,
                roles: nil,
                state: .loaded,
                memoryBytes: nil,
                tokensPerSec: nil,
                modelPath: nil,
                note: r.note
            )
            merged.append(m)
        }

        if merged == base.models {
            return base
        }
        return ModelStateSnapshot(models: merged, updatedAt: Date().timeIntervalSince1970)
    }

    nonisolated static func reconciledLocalRuntimeState(
        _ snapshot: ModelStateSnapshot,
        runtimeStatus: AIRuntimeStatus?,
        pendingByModelId: [String: PendingCommand],
        successfulLocalLifecycleActionsByModelId: [String: SuccessfulLocalLifecycleAction] = [:],
        now: TimeInterval = Date().timeIntervalSince1970
    ) -> ModelStateSnapshot {
        guard !snapshot.models.isEmpty else { return snapshot }

        let loadedByProvider = loadedLocalModelIDsByProvider(runtimeStatus)
        var models = snapshot.models
        var changed = false

        for index in models.indices {
            let model = models[index]
            guard !LocalModelRuntimeActionPlanner.isRemoteModel(model) else { continue }

            let providerID = LocalModelExecutionProviderResolver.preferredRuntimeProviderID(for: model)
            let runtimeLoaded = loadedByProvider[providerID]?.contains(model.id) ?? false
            let pendingAction = pendingByModelId[model.id]?.action
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased() ?? ""
            let shouldHoldLoadedState = ["load", "warmup", "bench", "prepare_local_model"].contains(pendingAction)
            let lifecycleHint = activeLifecycleStateHint(
                successfulLocalLifecycleActionsByModelId[model.id],
                runtimeStatus: runtimeStatus,
                now: now
            )
            let shouldPreferLoadedState = lifecycleHint == "load" || lifecycleHint == "warmup"
            let shouldPreferAvailableState = lifecycleHint == "unload" || lifecycleHint == "evict"

            if runtimeLoaded, !shouldPreferAvailableState {
                if models[index].state != .loaded {
                    models[index].state = .loaded
                    changed = true
                }
                continue
            }

            if shouldPreferLoadedState {
                if models[index].state != .loaded {
                    models[index].state = .loaded
                    changed = true
                }
                continue
            }

            guard models[index].state == .loaded, !shouldHoldLoadedState else { continue }
            models[index].state = .available
            models[index].memoryBytes = nil
            models[index].tokensPerSec = nil
            changed = true
        }

        guard changed else { return snapshot }
        return ModelStateSnapshot(
            models: models,
            updatedAt: Date().timeIntervalSince1970
        )
    }

    nonisolated private static func activeLifecycleStateHint(
        _ action: SuccessfulLocalLifecycleAction?,
        runtimeStatus: AIRuntimeStatus?,
        now: TimeInterval
    ) -> String? {
        guard let action else { return nil }
        let normalizedAction = action.action
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard ["load", "warmup", "unload", "evict"].contains(normalizedAction) else { return nil }
        guard (now - action.finishedAt) <= successfulLifecycleActionGraceSec else { return nil }
        if let runtimeStatus, runtimeStatus.updatedAt >= action.finishedAt {
            return nil
        }
        return normalizedAction
    }

    nonisolated private static func loadedLocalModelIDsByProvider(
        _ runtimeStatus: AIRuntimeStatus?
    ) -> [String: Set<String>] {
        guard let runtimeStatus, runtimeStatus.isAlive(ttl: AIRuntimeStatus.recommendedHeartbeatTTL) else { return [:] }

        var loadedByProvider: [String: Set<String>] = [:]
        for providerStatus in runtimeStatus.providers.values {
            let providerID = providerStatus.provider
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            guard !providerID.isEmpty else { continue }

            var loaded = Set(
                providerStatus.loadedModels
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            )
            for instance in providerStatus.loadedInstances {
                let modelID = instance.modelId.trimmingCharacters(in: .whitespacesAndNewlines)
                if !modelID.isEmpty {
                    loaded.insert(modelID)
                }
            }
            loadedByProvider[providerID] = loaded
        }
        return loadedByProvider
    }

    private func isRemoteModel(_ m: HubModel) -> Bool {
        LocalModelRuntimeActionPlanner.isRemoteModel(m)
    }

    // MVP "explainable" capacity: sum model costs (paramsB + ctx + quant) normalized to 100.
    func capacityPercent() -> Double {
        // Prefer runtime-reported MLX active memory; fallback to per-model sum.
        let used = Double(max(0, usedMemoryBytes()))
        let budget = Double(max(1, budgetMemoryBytes()))
        return max(0.0, min(1.0, used / budget))
    }

    func usedMemoryBytes() -> Int64 {
        // Prefer runtime-reported active MLX memory for accuracy.
        if let st = AIRuntimeStatusStorage.load(),
           st.isAlive(ttl: AIRuntimeStatus.recommendedHeartbeatTTL),
           st.isProviderReady("mlx", ttl: AIRuntimeStatus.recommendedHeartbeatTTL),
           let b = st.providerStatus("mlx")?.activeMemoryBytes ?? st.activeMemoryBytes,
           b > 0 {
            return b
        }

        // Fallback: sum per-model measured values; then a conservative estimate.
        var total: Int64 = 0
        for m in modelsLoaded() {
            if isRemoteModel(m) {
                continue
            }
            if let b = m.memoryBytes, b > 0 {
                total += b
            } else {
                total += estimateMemoryBytes(m)
            }
        }
        return max(0, total)
    }

    func budgetMemoryBytes() -> Int64 {
        // Conservative budget: keep headroom so the machine stays responsive.
        // Avoid a fixed 4GB reserve because it makes 8GB Macs show 100% too easily.
        let phys = Double(ProcessInfo.processInfo.physicalMemory)
        let gb = 1024.0 * 1024.0 * 1024.0

        // Reserve at least 2GB, or 25% of physical memory.
        let reserve = max(2.0 * gb, phys * 0.25)
        // Budget is what's left after reserve, but don't exceed 85% of total.
        let budget = max(1.0, min(phys * 0.85, max(0.0, phys - reserve)))
        return Int64(budget)
    }

    func cost(_ m: HubModel) -> Double {
        if isRemoteModel(m) {
            return 0.0
        }
        // params drive baseline.
        let base = max(0.1, m.paramsB)
        let q = m.quant.lowercased()
        let quantFactor: Double
        if q.contains("int4") || q.contains("4") {
            quantFactor = 0.45
        } else if q.contains("int8") || q.contains("8") {
            quantFactor = 0.65
        } else {
            quantFactor = 1.0
        }
        // Context increases KV cache; keep gentle.
        let ctxFactor = 1.0 + min(1.0, Double(max(0, m.contextLength - 2048)) / 8192.0) * 0.35
        return base * quantFactor * ctxFactor
    }

    func enqueue(action: String, modelId: String) {
        enqueue(
            action: action,
            modelId: modelId,
            allowRuntimeRecovery: true,
            targetPreferenceOverride: nil
        )
    }

    func enqueueRuntimeLifecycleAction(
        action: String,
        modelId: String,
        targetPreference: LocalModelRuntimeTargetPreference
    ) {
        enqueue(
            action: action,
            modelId: modelId,
            allowRuntimeRecovery: true,
            targetPreferenceOverride: targetPreference
        )
    }

    private func enqueue(
        action: String,
        modelId: String,
        allowRuntimeRecovery: Bool,
        targetPreferenceOverride: LocalModelRuntimeTargetPreference?
    ) {
        guard let model = snapshot.models.first(where: { $0.id == modelId }) else { return }
        let normalizedAction = action.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        lastResultByModelId.removeValue(forKey: modelId)
        if ["load", "warmup", "unload", "evict"].contains(normalizedAction) {
            successfulLocalLifecycleActionsByModelId.removeValue(forKey: modelId)
        }
        if shouldPrepareManagedLocalModel(
            action: normalizedAction,
            model: model
        ) {
            prepareManagedLocalModelAndRetry(
                action: normalizedAction,
                model: model,
                allowRuntimeRecovery: allowRuntimeRecovery,
                targetPreferenceOverride: targetPreferenceOverride
            )
            return
        }
        let providerID = LocalModelRuntimeActionPlanner.providerID(for: model)
        let probeLaunchConfig = HubStore.shared.localRuntimePythonProbeLaunchConfig(
            preferredProviderID: providerID
        )
        let pythonPath = HubStore.shared.preferredLocalProviderPythonPath(
            preferredProviderID: providerID
        )
        if normalizedAction == "bench" {
            startDefaultBench(for: model)
            return
        }
        let runtimeStatus = AIRuntimeStatusStorage.load()
        if allowRuntimeRecovery,
           shouldAttemptRuntimeRecovery(
                action: normalizedAction,
                model: model,
                providerID: providerID,
                runtimeStatus: runtimeStatus
           ) {
            recoverRuntimeAndRetry(action: normalizedAction, model: model, providerID: providerID)
            return
        }
        if let blockedMessage = LocalModelRuntimeCompatibilityPolicy.blockedActionMessage(
            action: action,
            model: model,
            probeLaunchConfig: probeLaunchConfig,
            pythonPath: pythonPath
        ) {
            recordImmediateFailure(action: action, modelId: modelId, msg: blockedMessage)
            return
        }
        switch LocalModelRuntimeActionPlanner.plan(action: action, model: model, runtimeStatus: runtimeStatus) {
        case .immediateFailure(let message):
            recordImmediateFailure(action: action, modelId: modelId, msg: message)
            return
        case .legacyModelCommand(let routedAction):
            enqueueLegacyModelCommand(
                action: routedAction,
                model: model,
                runtimeStatus: runtimeStatus,
                targetPreferenceOverride: targetPreferenceOverride
            )
        case .providerLifecycleCommand(let routedAction):
            enqueueProviderLifecycleCommand(
                action: routedAction,
                model: model,
                targetPreferenceOverride: targetPreferenceOverride
            )
        }
    }

    private func shouldAttemptRuntimeRecovery(
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

    private func recoverRuntimeAndRetry(action: String, model: HubModel, providerID: String) {
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

    func localModelRuntimePresentation(for model: HubModel) -> LocalModelRuntimePresentation? {
        guard !isRemoteModel(model) else { return nil }
        if let cached = localRuntimePresentationCache[model.id] {
            return cached.value
        }

        let runtimeStatus = currentRuntimeStatus
        let providerID = LocalModelRuntimeActionPlanner.providerID(for: model)
        let providerStatus = runtimeStatus?.providerStatus(providerID)
        let controlMode = LocalRuntimeProviderPolicy.resolvedControlMode(
            providerID: providerID,
            taskKinds: model.taskKinds,
            providerStatus: providerStatus
        )
        let providerReady = runtimeStatus?.isProviderReady(providerID, ttl: AIRuntimeStatus.recommendedHeartbeatTTL) ?? false
        let supportsWarmup = controlMode == .warmable
            && (providerStatus?.supportsWarmup(forModelTaskKinds: model.taskKinds) ?? false)
        let supportsUnload = LocalRuntimeProviderPolicy.supportsUnload(
            providerID: providerID,
            taskKinds: model.taskKinds,
            providerStatus: providerStatus
        )
        let supportsBench = !(
            availableBenchTaskDescriptorsCache[model.id]
            ?? LocalModelBenchCapabilityPolicy.benchableDescriptors(
                for: model,
                runtimeStatus: runtimeStatus
            )
        ).isEmpty
        let presentation = LocalModelRuntimePresentation(
            providerID: providerID,
            controlMode: controlMode,
            lifecycleMode: providerStatus?.lifecycleMode ?? "",
            residencyScope: providerStatus?.residencyScope ?? "",
            providerReady: providerReady,
            supportsWarmup: supportsWarmup,
            supportsUnload: supportsUnload,
            supportsBench: supportsBench
        )
        localRuntimePresentationCache[model.id] = OptionalRuntimePresentationCacheEntry(value: presentation)
        return presentation
    }

    func localRuntimeActionBlockedMessage(for model: HubModel, action: String) -> String? {
        guard !isRemoteModel(model) else { return nil }
        let normalizedAction = action.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let cacheKey = "\(model.id)|\(normalizedAction)"
        if let cached = localRuntimeActionBlockedMessageCache[cacheKey] {
            return cached.value
        }
        let inputs = localRuntimeSupportInputs(for: model)
        let blockedMessage = LocalModelRuntimeCompatibilityPolicy.blockedActionMessage(
            action: action,
            model: model,
            probeLaunchConfig: inputs.probeLaunchConfig,
            pythonPath: inputs.pythonPath
        )
        localRuntimeActionBlockedMessageCache[cacheKey] = OptionalStringCacheEntry(value: blockedMessage)
        return blockedMessage
    }

    func currentLocalRuntimeRequestContext(for model: HubModel) -> LocalModelRuntimeRequestContext? {
        guard !isRemoteModel(model) else { return nil }
        if let cached = currentLocalRuntimeRequestContextByModelId[model.id] {
            return cached
        }
        return localRuntimeRequestContext(
            for: model,
            runtimeStatus: currentRuntimeStatus,
            pairedProfilesSnapshot: currentPairedProfilesSnapshot,
            targetPreference: currentTargetPreferenceByModelId[model.id]
        )
    }

    func currentLocalRuntimeTargetPreference(for model: HubModel) -> LocalModelRuntimeTargetPreference? {
        guard !isRemoteModel(model) else { return nil }
        return currentTargetPreferenceByModelId[model.id]
    }

    private func shouldPrepareManagedLocalModel(
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

    private func prepareManagedLocalModelAndRetry(
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

    func availableLocalRuntimeTargetOptions(for model: HubModel) -> [LocalModelRuntimeTargetOption] {
        guard !isRemoteModel(model) else { return [] }
        if let cached = availableLocalRuntimeTargetOptionsCache[model.id] {
            return cached
        }
        let runtimeStatus = currentRuntimeStatus
        let pairedProfilesSnapshot = currentPairedProfilesSnapshot
        let targetPreference = currentTargetPreferenceByModelId[model.id]
        let inputs = localRuntimeSupportInputs(for: model)

        var options: [LocalModelRuntimeTargetOption] = []
        let autoContext = localRuntimeRequestContext(
            for: model,
            runtimeStatus: runtimeStatus,
            pairedProfilesSnapshot: pairedProfilesSnapshot,
            targetPreference: nil
        )
        options.append(
            LocalModelRuntimeTargetOption(
                kind: .auto,
                deviceID: "",
                instanceKey: "",
                title: HubUIStrings.Models.Runtime.ActionPlanner.automaticTarget,
                detail: autoContext.uiSummary
            )
        )

        let pairedProfiles = pairedProfilesSnapshot.profiles
            .filter { $0.modelId == model.id && !$0.deviceId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { lhs, rhs in
                if lhs.deviceId == rhs.deviceId {
                    return lhs.updatedAtMs > rhs.updatedAtMs
                }
                if lhs.deviceId == LocalModelRuntimeRequestContextResolver.defaultPairedDeviceID {
                    return true
                }
                if rhs.deviceId == LocalModelRuntimeRequestContextResolver.defaultPairedDeviceID {
                    return false
                }
                return lhs.deviceId.localizedCaseInsensitiveCompare(rhs.deviceId) == .orderedAscending
            }
        for profile in pairedProfiles {
            let context = localRuntimeRequestContext(
                for: model,
                runtimeStatus: runtimeStatus,
                pairedProfilesSnapshot: pairedProfilesSnapshot,
                targetPreference: LocalModelRuntimeTargetPreference(
                    modelId: model.id,
                    targetKind: .pairedDevice,
                    deviceId: profile.deviceId
                )
            )
            options.append(
                LocalModelRuntimeTargetOption(
                    kind: .pairedDevice,
                    deviceID: profile.deviceId,
                    instanceKey: "",
                    title: profile.deviceId == LocalModelRuntimeRequestContextResolver.defaultPairedDeviceID
                        ? HubUIStrings.Models.Runtime.ActionPlanner.pairedTerminalTarget
                        : profile.deviceId,
                    detail: context.uiSummary
                )
            )
        }

        let loadedInstances = runtimeStatus?
            .providerStatus(inputs.providerID)?
            .loadedInstances
            .filter { $0.modelId == model.id }
            .sorted {
                if $0.lastUsedAt == $1.lastUsedAt {
                    if $0.loadedAt == $1.loadedAt {
                        return $0.instanceKey < $1.instanceKey
                    }
                    return $0.loadedAt > $1.loadedAt
                }
                return $0.lastUsedAt > $1.lastUsedAt
            } ?? []
        for loaded in loadedInstances {
            let context = localRuntimeRequestContext(
                for: model,
                runtimeStatus: runtimeStatus,
                pairedProfilesSnapshot: pairedProfilesSnapshot,
                targetPreference: LocalModelRuntimeTargetPreference(
                    modelId: model.id,
                    targetKind: .loadedInstance,
                    instanceKey: loaded.instanceKey
                )
            )
            let shortInstance = String(
                String(loaded.instanceKey.split(separator: ":").last ?? Substring("")).prefix(8)
            )
            options.append(
                LocalModelRuntimeTargetOption(
                    kind: .loadedInstance,
                    deviceID: "",
                    instanceKey: loaded.instanceKey,
                    title: HubUIStrings.Models.Runtime.Operations.instanceTitle(shortInstance),
                    detail: context.technicalSummary
                )
            )
        }

        var deduped: [LocalModelRuntimeTargetOption] = []
        var seen = Set<String>()
        for option in options {
            guard seen.insert(option.id).inserted else { continue }
            deduped.append(option)
        }

        if let targetPreference,
           targetPreference.isValid,
           !deduped.contains(where: { option in
               switch option.kind {
               case .auto:
                   return false
               case .pairedDevice:
                   return targetPreference.kind == .pairedDevice && option.deviceID == targetPreference.deviceId
               case .loadedInstance:
                   return targetPreference.kind == .loadedInstance && option.instanceKey == targetPreference.instanceKey
               }
           }) {
            deduped.insert(
                LocalModelRuntimeTargetOption(
                    kind: .auto,
                    deviceID: "",
                    instanceKey: "",
                    title: HubUIStrings.Models.Runtime.ActionPlanner.automaticTarget,
                    detail: autoContext.uiSummary
                ),
                at: 0
            )
        }

        availableLocalRuntimeTargetOptionsCache[model.id] = deduped
        return deduped
    }

    func setLocalRuntimeTargetOption(_ option: LocalModelRuntimeTargetOption, for model: HubModel) {
        guard !isRemoteModel(model) else { return }
        switch option.kind {
        case .auto:
            LocalModelRuntimeTargetPreferencesStorage.remove(modelId: model.id)
        case .pairedDevice:
            LocalModelRuntimeTargetPreferencesStorage.upsert(
                LocalModelRuntimeTargetPreference(
                    modelId: model.id,
                    targetKind: .pairedDevice,
                    deviceId: option.deviceID
                )
            )
        case .loadedInstance:
            LocalModelRuntimeTargetPreferencesStorage.upsert(
                LocalModelRuntimeTargetPreference(
                    modelId: model.id,
                    targetKind: .loadedInstance,
                    instanceKey: option.instanceKey
                )
            )
        }
        refresh()
    }

    func preferredBenchResult(for model: HubModel) -> ModelBenchResult? {
        currentTargetBenchResults(for: model).first
    }

    func currentTargetBenchResult(for model: HubModel, taskKind: String) -> ModelBenchResult? {
        let normalizedTaskKind = taskKind.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return currentTargetBenchResults(for: model).first {
            normalizedTaskKind.isEmpty || $0.taskKind == normalizedTaskKind
        }
    }

    func currentTargetBenchResults(for model: HubModel) -> [ModelBenchResult] {
        let rows = benchResults(for: model.id)
        guard let requestContext = currentLocalRuntimeRequestContext(for: model) else {
            return rows
        }
        let matching = rows.filter { requestContext.matchesBenchResult($0) }
        return matching.isEmpty ? rows : matching
    }

    func canEvictCurrentLocalRuntimeInstance(for model: HubModel) -> Bool {
        guard !isRemoteModel(model) else { return false }
        guard let requestContext = currentLocalRuntimeRequestContext(for: model) else {
            return false
        }
        guard !requestContext.instanceKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        let providerID = LocalModelRuntimeActionPlanner.providerID(for: model)
        return currentRuntimeStatus?
            .providerStatus(providerID)?
            .supportsLifecycleAction(.evictLocalInstance) == true
    }

    func quickBenchMonitorExplanation(for model: HubModel, taskKind: String) -> LocalModelBenchMonitorExplanation? {
        guard !isRemoteModel(model) else { return nil }
        return LocalModelBenchMonitorExplanationBuilder.build(
            model: model,
            taskKind: taskKind,
            requestContext: currentLocalRuntimeRequestContext(for: model),
            benchResult: currentTargetBenchResult(for: model, taskKind: taskKind),
            runtimeStatus: currentRuntimeStatus
        )
    }

    func availableBenchTaskDescriptors(for model: HubModel) -> [LocalTaskRoutingDescriptor] {
        guard !isRemoteModel(model) else { return [] }
        if let cached = availableBenchTaskDescriptorsCache[model.id] {
            return cached
        }
        let inputs = localRuntimeSupportInputs(for: model)
        let descriptors = LocalModelBenchCapabilityPolicy.benchableDescriptors(
            for: model,
            runtimeStatus: currentRuntimeStatus,
            probeLaunchConfig: inputs.probeLaunchConfig,
            pythonPath: inputs.pythonPath
        )
        availableBenchTaskDescriptorsCache[model.id] = descriptors
        return descriptors
    }

    func availableBenchFixtures(for model: HubModel, taskKind: String) -> [LocalBenchFixtureDescriptor] {
        guard !isRemoteModel(model) else { return [] }
        return LocalBenchFixtureCatalog.fixtures(
            for: taskKind,
            providerID: LocalModelRuntimeActionPlanner.providerID(for: model)
        )
    }

    func benchResults(for modelId: String) -> [ModelBenchResult] {
        benchSnapshot.results.filter { $0.modelId == modelId }.sorted {
            if $0.measuredAt == $1.measuredAt {
                return $0.id < $1.id
            }
            return $0.measuredAt > $1.measuredAt
        }
    }

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

    private func dispatchQuickBenchCommand(
        modelId: String,
        providerID: String,
        taskKind: String,
        fixtureProfile: String,
        fixtureTitle: String,
        requestContext: LocalModelRuntimeRequestContext,
        launchConfig: LocalRuntimeCommandLaunchConfig,
        requestID: String
    ) {
        let runtimeStatus = AIRuntimeStatusStorage.load()
        let packURL = LocalBenchFixtureCatalog.packURL()
        let baseRequest: [String: Any] = [
            "provider": providerID,
            "model_id": modelId,
            "task_kind": taskKind,
            "fixture_profile": fixtureProfile,
            "fixture_pack_path": packURL?.path ?? "",
            "allow_bench_fallback": true,
            "allow_daemon_proxy": LocalRuntimeProviderPolicy.allowsDaemonProxy(
                providerID: providerID,
                runtimeStatus: runtimeStatus,
                requestContext: requestContext
            ),
        ]
        let request = requestContext.applying(to: baseRequest)
        guard JSONSerialization.isValidJSONObject(request),
              let requestData = try? JSONSerialization.data(withJSONObject: request, options: []) else {
            recordImmediateFailure(
                action: "bench",
                modelId: modelId,
                msg: LocalRuntimeCommandError.invalidRequestPayload.localizedDescription
            )
            pendingByModelId.removeValue(forKey: modelId)
            return
        }

        Task.detached(priority: .userInitiated) { [requestData, launchConfig] in
            do {
                let payloadData = try LocalRuntimeCommandRunner.run(
                    command: "run-local-bench",
                    requestData: requestData,
                    launchConfig: launchConfig,
                    timeoutSec: 45.0
                )
                await MainActor.run {
                    self.finishQuickBench(
                        payloadData: payloadData,
                        modelId: modelId,
                        providerID: providerID,
                        requestID: requestID,
                        fixtureTitle: fixtureTitle
                    )
                }
            } catch {
                await MainActor.run {
                    self.finishQuickBenchWithError(
                        error.localizedDescription,
                        modelId: modelId,
                        providerID: providerID,
                        taskKind: taskKind,
                        fixtureProfile: fixtureProfile,
                        fixtureTitle: fixtureTitle,
                        requestContext: requestContext,
                        requestID: requestID
                    )
                }
            }
        }
    }

    private func dispatchBenchWarmupThenRun(
        modelId: String,
        providerID: String,
        taskKind: String,
        fixtureProfile: String,
        fixtureTitle: String,
        requestContext: LocalModelRuntimeRequestContext,
        launchConfig: LocalRuntimeCommandLaunchConfig,
        requestID: String
    ) {
        let baseRequest: [String: Any] = [
            "action": "warmup_local_model",
            "provider": providerID,
            "model_id": modelId,
            "task_kind": taskKind,
        ]
        let request = requestContext.applying(to: baseRequest)
        guard JSONSerialization.isValidJSONObject(request),
              let requestData = try? JSONSerialization.data(withJSONObject: request, options: []) else {
            finishQuickBenchWithError(
                LocalRuntimeCommandError.invalidRequestPayload.localizedDescription,
                modelId: modelId,
                providerID: providerID,
                taskKind: taskKind,
                fixtureProfile: fixtureProfile,
                fixtureTitle: fixtureTitle,
                requestContext: requestContext,
                requestID: requestID,
                reasonCode: "warmup_request_invalid"
            )
            return
        }

        Task.detached(priority: .userInitiated) { [requestData, launchConfig] in
            do {
                let warmupPayloadData = try LocalRuntimeCommandRunner.run(
                    command: "manage-local-model",
                    requestData: requestData,
                    launchConfig: launchConfig,
                    timeoutSec: 60.0
                )
                let payload = (try? JSONSerialization.jsonObject(with: warmupPayloadData, options: [])) as? [String: Any] ?? [:]
                let ok = payload["ok"] as? Bool ?? false
                if !ok {
                    await MainActor.run {
                        let reasonCode = self.lifecycleFailureReasonCode(payload) ?? "warmup_failed"
                        let message = self.lifecycleStatusLine(payload, action: "warmup")
                        self.finishQuickBenchWithError(
                            message,
                            modelId: modelId,
                            providerID: providerID,
                            taskKind: taskKind,
                            fixtureProfile: fixtureProfile,
                            fixtureTitle: fixtureTitle,
                            requestContext: requestContext,
                            requestID: requestID,
                            reasonCode: reasonCode
                        )
                    }
                    return
                }

                let warmedRequestContext = LocalModelQuickBenchPlanner.updatedRequestContext(
                    fromWarmupPayload: payload,
                    fallback: requestContext
                )
                await MainActor.run {
                    self.refresh()
                    self.dispatchQuickBenchCommand(
                        modelId: modelId,
                        providerID: providerID,
                        taskKind: taskKind,
                        fixtureProfile: fixtureProfile,
                        fixtureTitle: fixtureTitle,
                        requestContext: warmedRequestContext,
                        launchConfig: launchConfig,
                        requestID: requestID
                    )
                }
            } catch {
                await MainActor.run {
                    self.finishQuickBenchWithError(
                        error.localizedDescription,
                        modelId: modelId,
                        providerID: providerID,
                        taskKind: taskKind,
                        fixtureProfile: fixtureProfile,
                        fixtureTitle: fixtureTitle,
                        requestContext: requestContext,
                        requestID: requestID,
                        reasonCode: "warmup_command_failed"
                    )
                }
            }
        }
    }

    private func enqueueLegacyModelCommand(
        action: String,
        model: HubModel,
        runtimeStatus: AIRuntimeStatus?,
        targetPreferenceOverride: LocalModelRuntimeTargetPreference?
    ) {
        let base = SharedPaths.ensureHubDirectory()
        let dir = base.appendingPathComponent("model_commands", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let reqId = UUID().uuidString
        let requestContext = localRuntimeRequestContext(
            for: model,
            runtimeStatus: runtimeStatus,
            targetPreference: targetPreferenceOverride
        )
        let baseCommand: [String: Any] = [
            "type": "model_command",
            "req_id": reqId,
            "action": action,
            "model_id": model.id,
            "requested_at": Date().timeIntervalSince1970,
        ]
        let cmd = Self.legacyModelCommandPayload(
            action: action,
            requestContext: requestContext,
            baseCommand: baseCommand
        )

        let tmp = dir.appendingPathComponent(".cmd_\(UUID().uuidString).tmp")
        let out = dir.appendingPathComponent("cmd_\(UUID().uuidString).json")
        if let data = try? JSONSerialization.data(withJSONObject: cmd, options: []) {
            try? data.write(to: tmp, options: .atomic)
            try? FileManager.default.moveItem(at: tmp, to: out)
        }

        // Track pending so the UI doesn't optimistically lie about loaded state.
        pendingByModelId[model.id] = PendingCommand(reqId: reqId, action: action, requestedAt: Date().timeIntervalSince1970)
    }

    nonisolated static func legacyModelCommandPayload(
        action: String,
        requestContext: LocalModelRuntimeRequestContext,
        baseCommand: [String: Any]
    ) -> [String: Any] {
        var command = requestContext.applying(to: baseCommand)
        let normalizedAction = action.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalizedAction == "sleep" || normalizedAction == "unload" else {
            return command
        }

        // Model-row sleep/unload is model-scoped. Dropping route-specific targeting
        // avoids "unload succeeded but old instance still loaded" when the selected
        // route/profile no longer matches the resident MLX instance identity.
        let scopedKeys = [
            "device_id",
            "instance_key",
            "load_profile_hash",
            "load_config_hash",
            "effective_context_length",
            "current_context_length",
            "load_profile_override",
        ]
        for key in scopedKeys {
            command.removeValue(forKey: key)
        }
        return command
    }

    private func enqueueProviderLifecycleCommand(
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

    private func startDefaultBench(for model: HubModel) {
        guard let task = availableBenchTaskDescriptors(for: model).first?.taskKind else {
            recordImmediateFailure(
                action: "bench",
                modelId: model.id,
                msg: HubUIStrings.Models.Review.Bench.noRegisteredTasks
            )
            return
        }
        guard let fixtureID = LocalBenchFixtureCatalog.defaultFixtureID(
            for: task,
            providerID: LocalModelRuntimeActionPlanner.providerID(for: model)
        ) else {
            recordImmediateFailure(
                action: "bench",
                modelId: model.id,
                msg: HubUIStrings.Models.Review.Bench.fixtureUnavailable(LocalTaskRoutingCatalog.title(for: task))
            )
            return
        }
        runBench(modelId: model.id, taskKind: task, fixtureProfile: fixtureID)
    }

    private func finishProviderLifecycleCommand(
        payloadData: Data,
        modelId: String,
        action: String,
        requestID: String
    ) {
        let payload = (try? JSONSerialization.jsonObject(with: payloadData, options: [])) as? [String: Any] ?? [:]
        let ok = payload["ok"] as? Bool ?? false
        let message = lifecycleStatusLine(payload, action: action)
        let finishedAt = Date().timeIntervalSince1970
        if ok {
            applySuccessfulLocalLifecycleAction(
                action: action,
                modelId: modelId,
                finishedAt: finishedAt
            )
        }
        refresh()
        lastResultByModelId[modelId] = ModelCommandResult(
            type: "model_result",
            reqId: requestID,
            action: action,
            modelId: modelId,
            ok: ok,
            msg: message,
            finishedAt: finishedAt
        )
        if let pending = pendingByModelId[modelId], pending.reqId == requestID {
            pendingByModelId.removeValue(forKey: modelId)
        }
    }

    private func finishProviderLifecycleCommandWithError(
        _ message: String,
        modelId: String,
        action: String,
        requestID: String
    ) {
        let actionTitle = localizedLifecycleActionTitle(action)
        successfulLocalLifecycleActionsByModelId.removeValue(forKey: modelId)
        refresh()
        lastResultByModelId[modelId] = ModelCommandResult(
            type: "model_result",
            reqId: requestID,
            action: action,
            modelId: modelId,
            ok: false,
            msg: message.isEmpty
                ? HubUIStrings.Models.Runtime.ActionPlanner.lifecycleFailed(actionTitle)
                : HubUIStrings.Models.Runtime.ActionPlanner.lifecycleFailed(actionTitle: actionTitle, detail: message),
            finishedAt: Date().timeIntervalSince1970
        )
        if let pending = pendingByModelId[modelId], pending.reqId == requestID {
            pendingByModelId.removeValue(forKey: modelId)
        }
    }

    private func finishQuickBench(
        payloadData: Data,
        modelId: String,
        providerID: String,
        requestID: String,
        fixtureTitle: String
    ) {
        let result = decodeBenchResult(
            payloadData,
            modelId: modelId,
            providerID: providerID,
            fallbackFixtureTitle: fixtureTitle
        )
        _ = ModelBenchStorage.upsert(result)
        refresh()
        lastResultByModelId[modelId] = ModelCommandResult(
            type: "model_result",
            reqId: requestID,
            action: "bench",
            modelId: modelId,
            ok: result.ok,
            msg: result.ok ? benchStatusLine(result) : benchFailureLine(result),
            finishedAt: Date().timeIntervalSince1970
        )
        if let pending = pendingByModelId[modelId], pending.reqId == requestID {
            pendingByModelId.removeValue(forKey: modelId)
        }
    }

    private func finishQuickBenchWithError(
        _ message: String,
        modelId: String,
        providerID: String,
        taskKind: String,
        fixtureProfile: String,
        fixtureTitle: String,
        requestContext: LocalModelRuntimeRequestContext,
        requestID: String,
        reasonCode: String = "runtime_command_failed"
    ) {
        let normalizedReasonCode = reasonCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let note = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let result = ModelBenchResult(
            modelId: modelId,
            providerID: providerID,
            taskKind: taskKind,
            loadProfileHash: requestContext.preferredBenchHash,
            fixtureProfile: fixtureProfile,
            fixtureTitle: fixtureTitle,
            measuredAt: Date().timeIntervalSince1970,
            runtimeVersion: AIRuntimeStatusStorage.load()?.runtimeVersion,
            schemaVersion: ModelBenchResult.schemaVersion,
            resultKind: ModelBenchResult.quickBenchKind,
            ok: false,
            reasonCode: normalizedReasonCode.isEmpty ? "runtime_command_failed" : normalizedReasonCode,
            verdict: "",
            fallbackMode: "",
            notes: note.isEmpty ? [] : [note],
            effectiveContextLength: requestContext.effectiveContextLength > 0
                ? requestContext.effectiveContextLength
                : nil
        )
        _ = ModelBenchStorage.upsert(result)
        refresh()
        lastResultByModelId[modelId] = ModelCommandResult(
            type: "model_result",
            reqId: requestID,
            action: "bench",
            modelId: modelId,
            ok: false,
            msg: benchFailureLine(result),
            finishedAt: Date().timeIntervalSince1970
        )
        if let pending = pendingByModelId[modelId], pending.reqId == requestID {
            pendingByModelId.removeValue(forKey: modelId)
        }
    }

    private func decodeBenchResult(
        _ payloadData: Data,
        modelId: String,
        providerID: String,
        fallbackFixtureTitle: String
    ) -> ModelBenchResult {
        if let decoded = try? JSONDecoder().decode(ModelBenchResult.self, from: payloadData) {
            if !fallbackFixtureTitle.isEmpty, decoded.fixtureTitle.isEmpty {
                return ModelBenchResult(
                    resultID: decoded.resultID,
                    modelId: decoded.modelId,
                    providerID: decoded.providerID,
                    taskKind: decoded.taskKind,
                    loadProfileHash: decoded.loadProfileHash,
                    fixtureProfile: decoded.fixtureProfile,
                    fixtureTitle: fallbackFixtureTitle,
                    measuredAt: decoded.measuredAt,
                    runtimeVersion: decoded.runtimeVersion,
                    schemaVersion: decoded.schemaVersion,
                    resultKind: decoded.resultKind,
                    ok: decoded.ok,
                    reasonCode: decoded.reasonCode,
                    runtimeSource: decoded.runtimeSource,
                    runtimeSourcePath: decoded.runtimeSourcePath,
                    runtimeResolutionState: decoded.runtimeResolutionState,
                    runtimeReasonCode: decoded.runtimeReasonCode,
                    fallbackUsed: decoded.fallbackUsed,
                    runtimeHint: decoded.runtimeHint,
                    runtimeMissingRequirements: decoded.runtimeMissingRequirements,
                    runtimeMissingOptionalRequirements: decoded.runtimeMissingOptionalRequirements,
                    verdict: decoded.verdict,
                    fallbackMode: decoded.fallbackMode,
                    notes: decoded.notes,
                    coldStartMs: decoded.coldStartMs,
                    latencyMs: decoded.latencyMs,
                    peakMemoryBytes: decoded.peakMemoryBytes,
                    throughputValue: decoded.throughputValue,
                    throughputUnit: decoded.throughputUnit,
                    effectiveContextLength: decoded.effectiveContextLength,
                    promptTokens: decoded.promptTokens,
                    generationTokens: decoded.generationTokens,
                    promptTPS: decoded.promptTPS,
                    generationTPS: decoded.generationTPS
                )
            }
            return decoded
        }

        guard let raw = try? JSONSerialization.jsonObject(with: payloadData, options: []),
              let payload = raw as? [String: Any] else {
            return ModelBenchResult(
                modelId: modelId,
                providerID: providerID,
                taskKind: "",
                loadProfileHash: "",
                fixtureProfile: "",
                fixtureTitle: fallbackFixtureTitle,
                measuredAt: Date().timeIntervalSince1970,
                runtimeVersion: AIRuntimeStatusStorage.load()?.runtimeVersion,
                schemaVersion: ModelBenchResult.schemaVersion,
                resultKind: ModelBenchResult.quickBenchKind,
                ok: false,
                reasonCode: "bench_decode_failed",
                verdict: "",
                fallbackMode: "",
                notes: ["bench_decode_failed"]
            )
        }

        let taskKind = (payload["taskKind"] as? String ?? payload["task_kind"] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let fixtureProfile = (payload["fixtureProfile"] as? String ?? payload["fixture_profile"] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let reasonCode = (payload["reasonCode"] as? String ?? payload["reason_code"] as? String ?? payload["error"] as? String ?? "bench_decode_failed")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return ModelBenchResult(
            modelId: modelId,
            providerID: providerID,
            taskKind: taskKind,
            loadProfileHash: (payload["loadProfileHash"] as? String ?? payload["load_profile_hash"] as? String ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines),
            fixtureProfile: fixtureProfile,
            fixtureTitle: fallbackFixtureTitle,
            measuredAt: Date().timeIntervalSince1970,
            runtimeVersion: payload["runtimeVersion"] as? String ?? payload["runtime_version"] as? String,
            schemaVersion: ModelBenchResult.schemaVersion,
            resultKind: payload["resultKind"] as? String ?? payload["result_kind"] as? String ?? ModelBenchResult.quickBenchKind,
            ok: payload["ok"] as? Bool ?? false,
            reasonCode: reasonCode,
            runtimeSource: (payload["runtimeSource"] as? String ?? payload["runtime_source"] as? String ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines),
            runtimeSourcePath: (payload["runtimeSourcePath"] as? String ?? payload["runtime_source_path"] as? String ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines),
            runtimeResolutionState: (payload["runtimeResolutionState"] as? String ?? payload["runtime_resolution_state"] as? String ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines),
            runtimeReasonCode: (payload["runtimeReasonCode"] as? String ?? payload["runtime_reason_code"] as? String ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines),
            fallbackUsed: payload["fallbackUsed"] as? Bool ?? payload["fallback_used"] as? Bool ?? false,
            runtimeHint: (payload["runtimeHint"] as? String ?? payload["runtime_hint"] as? String ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines),
            runtimeMissingRequirements: payload["runtimeMissingRequirements"] as? [String]
                ?? payload["runtime_missing_requirements"] as? [String]
                ?? [],
            runtimeMissingOptionalRequirements: payload["runtimeMissingOptionalRequirements"] as? [String]
                ?? payload["runtime_missing_optional_requirements"] as? [String]
                ?? [],
            verdict: (payload["verdict"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            fallbackMode: (payload["fallbackMode"] as? String ?? payload["fallback_mode"] as? String ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines),
            notes: [reasonCode]
        )
    }

    private func benchStatusLine(_ result: ModelBenchResult) -> String {
        if !result.verdict.isEmpty {
            return HubUIStrings.Models.Review.Bench.statusLine(result.verdict)
        }
        return HubUIStrings.Models.Review.Bench.completed
    }

    private func benchFailureLine(_ result: ModelBenchResult) -> String {
        let reason = LocalModelRuntimeErrorPresentation.humanized(result.reasonCode)
        let note = LocalModelRuntimeErrorPresentation.humanized(result.notes.first ?? "")

        if !reason.isEmpty {
            let genericReasonCodes: Set<String> = [
                "runtime_command_failed",
                "warmup_command_failed",
                "warmup_request_invalid",
                "warmup_failed",
            ]
            if genericReasonCodes.contains(result.reasonCode),
               !note.isEmpty,
               note != reason {
                return HubUIStrings.Models.Review.Bench.failedReasonAndNote(reason: reason, note: note)
            }
            return HubUIStrings.Models.Review.Bench.failedReason(reason)
        }
        if !note.isEmpty {
            return HubUIStrings.Models.Review.Bench.failedNote(note)
        }
        return HubUIStrings.Models.Review.Bench.failedPrefix
    }

    private func lifecycleDisplayAction(_ action: String) -> String {
        let normalized = action.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "warmup_local_model":
            return "warmup"
        case "unload_local_model":
            return "unload"
        case "evict_local_instance":
            return "evict"
        default:
            return normalized.isEmpty ? "action" : normalized
        }
    }

    private func lifecycleStatusLine(_ payload: [String: Any], action: String) -> String {
        let ok = payload["ok"] as? Bool ?? false
        let normalizedAction = action.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let verb = localizedLifecycleActionTitle(normalizedAction)

        if ok {
            if normalizedAction == "warmup", payload["alreadyLoaded"] as? Bool == true {
                return HubUIStrings.Models.Runtime.ActionPlanner.lifecycleAlreadyLoaded(verb)
            }
            return HubUIStrings.Models.Runtime.ActionPlanner.lifecycleCompleted(verb)
        }

        let detail = LocalModelRuntimeErrorPresentation.humanized(
            (payload["errorDetail"] as? String ?? payload["error"] as? String ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        )
        return detail.isEmpty
            ? HubUIStrings.Models.Runtime.ActionPlanner.lifecycleFailed(verb)
            : HubUIStrings.Models.Runtime.ActionPlanner.lifecycleFailed(actionTitle: verb, detail: detail)
    }

    private func localizedBenchVerdict(_ verdict: String) -> String {
        HubUIStrings.Models.Review.Bench.localizedVerdict(verdict)
    }

    private func localizedLifecycleActionTitle(_ action: String) -> String {
        switch action.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "warmup", "warmup_local_model":
            return HubUIStrings.Models.Runtime.ActionPlanner.warmup
        case "unload", "unload_local_model":
            return HubUIStrings.Models.Runtime.ActionPlanner.unload
        case "evict", "evict_local_instance":
            return HubUIStrings.Models.Runtime.ActionPlanner.evict
        default:
            return action.trimmingCharacters(in: .whitespacesAndNewlines).capitalized
        }
    }

    private func lifecycleFailureReasonCode(_ payload: [String: Any]) -> String? {
        let candidates = [
            payload["error"] as? String,
            payload["reasonCode"] as? String,
            payload["reason_code"] as? String,
            payload["runtimeReasonCode"] as? String,
            payload["runtime_reason_code"] as? String,
        ]
        for candidate in candidates {
            let token = (candidate ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !token.isEmpty {
                return token
            }
        }
        return nil
    }

    private func recordImmediateFailure(action: String, modelId: String, msg: String) {
        let reqId = UUID().uuidString
        successfulLocalLifecycleActionsByModelId.removeValue(forKey: modelId)
        lastResultByModelId[modelId] = ModelCommandResult(
            type: "model_result",
            reqId: reqId,
            action: action,
            modelId: modelId,
            ok: false,
            msg: msg,
            finishedAt: Date().timeIntervalSince1970
        )
        pendingByModelId.removeValue(forKey: modelId)
    }

    private func localRuntimeRequestContext(
        for model: HubModel,
        runtimeStatus: AIRuntimeStatus?,
        pairedProfilesSnapshot: HubPairedTerminalLocalModelProfilesSnapshot? = nil,
        targetPreference: LocalModelRuntimeTargetPreference? = nil
    ) -> LocalModelRuntimeRequestContext {
        LocalModelRuntimeRequestContextResolver.resolve(
            model: model,
            runtimeStatus: runtimeStatus,
            pairedProfilesSnapshot: pairedProfilesSnapshot ?? currentPairedProfilesSnapshot,
            targetPreference: targetPreference ?? currentTargetPreferenceByModelId[model.id]
        )
    }

    nonisolated private static func isNewerBenchResult(_ lhs: ModelBenchResult, _ rhs: ModelBenchResult) -> Bool {
        if lhs.measuredAt == rhs.measuredAt {
            return lhs.id < rhs.id
        }
        return lhs.measuredAt > rhs.measuredAt
    }

    func pendingAction(for modelId: String) -> String? {
        pendingByModelId[modelId]?.action
    }

    func lastError(for modelId: String) -> String? {
        guard let r = lastResultByModelId[modelId] else { return nil }
        if r.ok { return nil }
        return r.msg
    }

    func importCatalogEntries(
        _ entries: [ModelCatalogEntry],
        autoBenchNewModels: Bool
    ) async -> [String] {
        guard !entries.isEmpty else { return [] }

        let preparedEntries = await Task.detached(priority: .utility) {
            let sandboxed = SharedPaths.isSandboxedProcess()
            let baseDir = SharedPaths.ensureHubDirectory()
            var prepared: [ModelCatalogEntry] = []
            prepared.reserveCapacity(entries.count)
            for entry in entries {
                do {
                    let resolved = try LocalModelManagedStorage.preparedCatalogEntryIfNeeded(
                        entry,
                        sandboxed: sandboxed,
                        baseDir: baseDir
                    )
                    prepared.append(resolved)
                } catch {
                    HubDiagnostics.log("local_model_prepare_failed model=\(entry.id) error=\(error.localizedDescription)")
                }
            }
            return prepared
        }.value
        guard !preparedEntries.isEmpty else { return [] }

        var catalog = ModelCatalogStorage.load()
        var newModelIDs: [String] = []
        let helperBinaryPath = LocalHelperBridgeDiscovery.discoverHelperBinary()

        for rawEntry in preparedEntries {
            let entry = LocalModelExecutionProviderResolver.backfilled(
                rawEntry,
                helperBinaryPath: helperBinaryPath
            )
            if let existingIndex = catalog.models.firstIndex(where: { $0.id == entry.id }) {
                catalog.models[existingIndex] = entry
            } else {
                catalog.models.append(entry)
                newModelIDs.append(entry.id)
            }
            upsertCatalogModel(entry)
        }

        catalog.updatedAt = Date().timeIntervalSince1970
        ModelCatalogStorage.save(catalog)

        let base = SharedPaths.appGroupDirectory() ?? SharedPaths.ensureHubDirectory()
        _ = LocalProviderPackRegistry.syncAutoManagedPacks(
            baseDir: base,
            catalog: catalog,
            helperBinaryPath: helperBinaryPath
        )

        if autoBenchNewModels {
            for modelID in newModelIDs {
                scheduleDefaultBenchIfNeeded(forModelId: modelID)
            }
        }

        return newModelIDs
    }

    func scheduleDefaultBenchIfNeeded(forModelId modelId: String) {
        guard let model = snapshot.models.first(where: { $0.id == modelId }) else { return }
        if preferredBenchResult(for: model) != nil {
            return
        }
        enqueue(action: "bench", modelId: modelId)
    }

    func upsertCatalogModel(_ entry: ModelCatalogEntry) {
        var cur = ModelStateStorage.load()
        if let idx = cur.models.firstIndex(where: { $0.id == entry.id }) {
            // Keep state/memory/tps; update metadata.
            cur.models[idx].name = entry.name
            cur.models[idx].backend = entry.backend
            cur.models[idx].runtimeProviderID = entry.runtimeProviderID
            cur.models[idx].quant = entry.quant
            cur.models[idx].contextLength = entry.contextLength
            cur.models[idx].paramsB = entry.paramsB
            cur.models[idx].modelPath = entry.modelPath
            cur.models[idx].roles = entry.roles
            cur.models[idx].note = entry.note
            cur.models[idx].modelFormat = entry.modelFormat
            cur.models[idx].taskKinds = entry.taskKinds
            cur.models[idx].inputModalities = entry.inputModalities
            cur.models[idx].outputModalities = entry.outputModalities
            cur.models[idx].offlineReady = entry.offlineReady
            cur.models[idx].voiceProfile = entry.voiceProfile
            cur.models[idx].resourceProfile = entry.resourceProfile
            cur.models[idx].trustProfile = entry.trustProfile
            cur.models[idx].processorRequirements = entry.processorRequirements
        } else {
            cur.models.append(
                HubModel(
                    id: entry.id,
                    name: entry.name,
                    backend: entry.backend,
                    runtimeProviderID: entry.runtimeProviderID,
                    quant: entry.quant,
                    contextLength: entry.contextLength,
                    paramsB: entry.paramsB,
                    roles: entry.roles,
                    state: .available,
                    modelPath: entry.modelPath,
                    note: entry.note,
                    modelFormat: entry.modelFormat,
                    taskKinds: entry.taskKinds,
                    inputModalities: entry.inputModalities,
                    outputModalities: entry.outputModalities,
                    offlineReady: entry.offlineReady,
                    voiceProfile: entry.voiceProfile,
                    resourceProfile: entry.resourceProfile,
                    trustProfile: entry.trustProfile,
                    processorRequirements: entry.processorRequirements
                )
            )
        }
        cur.updatedAt = Date().timeIntervalSince1970
        ModelStateStorage.save(cur)
        snapshot = cur
    }

    func updateRoles(modelId: String, roles: [String]) {
        let rid = modelId
        let cleaned: [String] = {
            var out: [String] = []
            var seen: Set<String> = []
            for r0 in roles {
                let r = r0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if r.isEmpty { continue }
                if seen.contains(r) { continue }
                seen.insert(r)
                out.append(r)
            }
            return out
        }()

        // Update catalog (for routing/runtime).
        var cat = ModelCatalogStorage.load()
        if let idx = cat.models.firstIndex(where: { $0.id == rid }) {
            cat.models[idx].roles = cleaned
            ModelCatalogStorage.save(cat)
            upsertCatalogModel(cat.models[idx])
            return
        }

        // If not in catalog yet, best-effort synthesize an entry from the current state.
        let cur = ModelStateStorage.load()
        guard let m = cur.models.first(where: { $0.id == rid }) else {
            return
        }
        guard let mp = m.modelPath, !mp.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            // No model path means runtime can't load it anyway.
            var cur2 = cur
            if let idx = cur2.models.firstIndex(where: { $0.id == rid }) {
                cur2.models[idx].roles = cleaned
                cur2.updatedAt = Date().timeIntervalSince1970
                ModelStateStorage.save(cur2)
                snapshot = cur2
            }
            return
        }

        let entry = ModelCatalogEntry(
            id: m.id,
            name: m.name,
            backend: m.backend,
            runtimeProviderID: m.runtimeProviderID,
            quant: m.quant,
            contextLength: m.contextLength,
            paramsB: m.paramsB,
            modelPath: mp,
            roles: cleaned,
            note: m.note,
            modelFormat: m.modelFormat,
            taskKinds: m.taskKinds,
            inputModalities: m.inputModalities,
            outputModalities: m.outputModalities,
            offlineReady: m.offlineReady,
            voiceProfile: m.voiceProfile,
            resourceProfile: m.resourceProfile,
            trustProfile: m.trustProfile,
            processorRequirements: m.processorRequirements
        )
        cat.models.append(entry)
        ModelCatalogStorage.save(cat)
        upsertCatalogModel(entry)
    }

    private func catalogEntry(for model: HubModel) -> ModelCatalogEntry? {
        if let catalogModel = ModelCatalogStorage.load().models.first(where: { $0.id == model.id }) {
            return catalogModel
        }
        return Self.synthesizedCatalogEntry(from: model)
    }

    private static func synthesizedCatalogEntry(from model: HubModel) -> ModelCatalogEntry? {
        let modelPath = (model.modelPath ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !modelPath.isEmpty else { return nil }
        return ModelCatalogEntry(
            id: model.id,
            name: model.name,
            backend: model.backend,
            runtimeProviderID: model.runtimeProviderID,
            quant: model.quant,
            contextLength: model.contextLength,
            maxContextLength: model.maxContextLength,
            paramsB: model.paramsB,
            modelPath: modelPath,
            roles: model.roles,
            note: model.note,
            modelFormat: model.modelFormat,
            defaultLoadProfile: model.defaultLoadProfile,
            taskKinds: model.taskKinds,
            inputModalities: model.inputModalities,
            outputModalities: model.outputModalities,
            offlineReady: model.offlineReady,
            voiceProfile: model.voiceProfile,
            resourceProfile: model.resourceProfile,
            trustProfile: model.trustProfile,
            processorRequirements: model.processorRequirements
        )
    }

    private func applyPreparedCatalogEntry(_ entry: ModelCatalogEntry) {
        var catalog = ModelCatalogStorage.load()
        if let index = catalog.models.firstIndex(where: { $0.id == entry.id }) {
            catalog.models[index] = entry
        } else {
            catalog.models.append(entry)
        }
        ModelCatalogStorage.save(catalog)
        upsertCatalogModel(entry)
    }

    private func backfillRuntimeProviderIDsIfNeeded() {
        let helperBinaryPath = LocalHelperBridgeDiscovery.discoverHelperBinary()

        var catalog = ModelCatalogStorage.load()
        let updatedCatalogModels = catalog.models.map {
            LocalModelExecutionProviderResolver.backfilled($0, helperBinaryPath: helperBinaryPath)
        }
        if updatedCatalogModels != catalog.models {
            catalog.models = updatedCatalogModels
            catalog.updatedAt = Date().timeIntervalSince1970
            ModelCatalogStorage.save(catalog)
        }

        var state = ModelStateStorage.load()
        let updatedStateModels = state.models.map {
            LocalModelExecutionProviderResolver.backfilled($0, helperBinaryPath: helperBinaryPath)
        }
        if updatedStateModels != state.models {
            state.models = updatedStateModels
            state.updatedAt = Date().timeIntervalSince1970
            ModelStateStorage.save(state)
        }
    }

    func removeModel(modelId: String, deleteLocalFiles: Bool) {
        let rid = modelId

        // Capture current info before mutation.
        let curBefore = ModelStateStorage.load()
        let stateModel = curBefore.models.first(where: { $0.id == rid })
        let localDeletionURL = deleteLocalFiles
            ? Self.deletableLocalModelURL(
                modelPath: removedModelPath(
                    removedEntry: nil,
                    stateModel: stateModel
                ),
                note: removedModelNote(
                    removedEntry: nil,
                    stateModel: stateModel
                )
            )
            : nil

        // 1) Remove from catalog.
        var cat = ModelCatalogStorage.load()
        let removedEntry = cat.models.first(where: { $0.id == rid })
        cat.models.removeAll { $0.id == rid }
        ModelCatalogStorage.save(cat)

        // 2) Remove from state snapshot.
        var cur = curBefore
        cur.models.removeAll { $0.id == rid }
        cur.updatedAt = Date().timeIntervalSince1970
        ModelStateStorage.save(cur)
        snapshot = cur

        // 3) Clear pending/result UI state.
        pendingByModelId.removeValue(forKey: rid)
        lastResultByModelId.removeValue(forKey: rid)
        successfulLocalLifecycleActionsByModelId.removeValue(forKey: rid)
        currentLocalRuntimeRequestContextByModelId.removeValue(forKey: rid)
        LocalModelRuntimeTargetPreferencesStorage.remove(modelId: rid)

        if benchSnapshot.results.contains(where: { $0.modelId == rid }) {
            benchSnapshot = ModelsBenchSnapshot(
                schemaVersion: benchSnapshot.schemaVersion,
                results: benchSnapshot.results.filter { $0.modelId != rid },
                updatedAt: Date().timeIntervalSince1970
            )
            ModelBenchStorage.save(benchSnapshot)
        }

        guard deleteLocalFiles else { return }
        let finalDeletionURL = localDeletionURL
            ?? Self.deletableLocalModelURL(
                modelPath: removedModelPath(removedEntry: removedEntry, stateModel: stateModel),
                note: removedModelNote(removedEntry: removedEntry, stateModel: stateModel)
            )
        if let finalDeletionURL {
            try? FileManager.default.removeItem(at: finalDeletionURL)
        }
    }

    func canDeleteLocalFiles(for model: HubModel) -> Bool {
        Self.deletableLocalModelURL(modelPath: model.modelPath ?? "", note: model.note ?? "") != nil
    }

    private func removedModelPath(
        removedEntry: ModelCatalogEntry?,
        stateModel: HubModel?
    ) -> String {
        (removedEntry?.modelPath ?? stateModel?.modelPath ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func removedModelNote(
        removedEntry: ModelCatalogEntry?,
        stateModel: HubModel?
    ) -> String {
        (removedEntry?.note ?? stateModel?.note ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func deletableLocalModelURL(
        modelPath: String,
        note: String
    ) -> URL? {
        let trimmedPath = modelPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else { return nil }

        let url = URL(fileURLWithPath: trimmedPath).standardizedFileURL
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        guard url.path != "/" else { return nil }
        guard url.path != SharedPaths.realHomeDirectory().standardizedFileURL.path else { return nil }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return nil }

        if isDirectory.boolValue {
            guard directoryLooksLikeLocalModel(url, note: note, fileManager: fileManager) else {
                return nil
            }
            return url
        }

        let ext = url.pathExtension.lowercased()
        return ["gguf", "safetensors", "bin"].contains(ext) ? url : nil
    }

    private static func directoryLooksLikeLocalModel(
        _ url: URL,
        note: String,
        fileManager: FileManager
    ) -> Bool {
        let normalizedNote = note.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalizedNote == "managed_copy"
            || normalizedNote == "lmstudio_managed"
            || normalizedNote == "lmstudio_managed_copy" {
            return true
        }

        guard let entries = try? fileManager.contentsOfDirectory(atPath: url.path) else {
            return false
        }
        let lowered = Set(entries.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })

        let markerFiles: Set<String> = [
            "config.json",
            "xhub_model_manifest.json",
            "model.safetensors.index.json",
            "consolidated.safetensors.index.json",
            "weights.npz",
            "processor_config.json",
            "preprocessor_config.json",
            "tokenizer.json",
            "tokenizer_config.json",
        ]
        if !lowered.isDisjoint(with: markerFiles) {
            return true
        }

        return lowered.contains(where: { name in
            name.hasSuffix(".gguf") || name.hasSuffix(".safetensors")
        })
    }

    private func estimateMemoryBytes(_ m: HubModel) -> Int64 {
        // Rough, explainable estimate for UI until a real model runtime reports measured values.
        let q = m.quant.lowercased()
        let bytesPerParam: Double
        if q.contains("int4") || q == "4" {
            bytesPerParam = 0.5
        } else if q.contains("int8") || q == "8" {
            bytesPerParam = 1.0
        } else {
            bytesPerParam = 2.0
        }

        let weights = m.paramsB * 1_000_000_000.0 * bytesPerParam
        let overhead = 0.35 * 1_000_000_000.0
        let kv = min(0.8 * 1_000_000_000.0, (Double(m.contextLength) / 8192.0) * 0.25 * 1_000_000_000.0)
        let total = max(50_000_000.0, weights + overhead + kv)
        return Int64(total)
    }

    private func estimateTokensPerSec(_ m: HubModel) -> Double {
        // Placeholder until real benchmarking is integrated.
        let params = max(0.1, m.paramsB)
        let q = m.quant.lowercased()
        let quantBoost: Double
        if q.contains("int4") || q == "4" {
            quantBoost = 1.25
        } else if q.contains("int8") || q == "8" {
            quantBoost = 1.1
        } else {
            quantBoost = 0.85
        }
        let tps = (42.0 / pow(params, 0.6)) * quantBoost
        return max(1.0, min(80.0, tps))
    }


    private func pruneLegacyDemoModels() {
        var cur = ModelStateStorage.load()
        let before = cur.models.count
        cur.models.removeAll { m in
            (m.note ?? "") == "demo" && (m.modelPath == nil || (m.modelPath ?? "").isEmpty)
        }
        if cur.models.count != before {
            cur.updatedAt = Date().timeIntervalSince1970
            ModelStateStorage.save(cur)
            snapshot = cur
        }
    }

    private func reconcilePendingWithState() {
        if pendingByModelId.isEmpty { return }
        var toRemove: [String] = []
        for (mid, p) in pendingByModelId {
            guard let m = snapshot.models.first(where: { $0.id == mid }) else {
                // Model removed.
                toRemove.append(mid)
                continue
            }
            let st = m.state
            switch p.action {
            case "load":
                if st == .loaded { toRemove.append(mid) }
            case "warmup":
                if st == .loaded { toRemove.append(mid) }
            case "unload":
                if st == .available { toRemove.append(mid) }
            case "sleep":
                if st == .sleeping { toRemove.append(mid) }
            default:
                break
            }
        }
        for mid in toRemove {
            pendingByModelId.removeValue(forKey: mid)
        }
    }

    private func reconcileSuccessfulLifecycleActionsWithRuntimeStatus(
        now: TimeInterval = Date().timeIntervalSince1970
    ) {
        guard !successfulLocalLifecycleActionsByModelId.isEmpty else { return }

        let liveModelIDs = Set(snapshot.models.map(\.id))
        successfulLocalLifecycleActionsByModelId = successfulLocalLifecycleActionsByModelId.filter { modelId, action in
            guard liveModelIDs.contains(modelId) else { return false }
            return Self.activeLifecycleStateHint(
                action,
                runtimeStatus: currentRuntimeStatus,
                now: now
            ) != nil
        }
    }

    private func applySuccessfulLocalLifecycleAction(
        action: String,
        modelId: String,
        finishedAt: TimeInterval
    ) {
        let normalizedAction = action
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        successfulLocalLifecycleActionsByModelId[modelId] = SuccessfulLocalLifecycleAction(
            action: normalizedAction,
            finishedAt: finishedAt
        )

        guard let index = snapshot.models.firstIndex(where: { $0.id == modelId }) else { return }
        switch normalizedAction {
        case "warmup", "load":
            snapshot.models[index].state = .loaded
        case "unload", "evict":
            snapshot.models[index].state = .available
            snapshot.models[index].memoryBytes = nil
            snapshot.models[index].tokensPerSec = nil
        default:
            return
        }
        snapshot.updatedAt = finishedAt
        ModelStateStorage.save(snapshot)
    }

    nonisolated static func reconciledLastCommandResults(
        _ results: [String: ModelCommandResult],
        snapshot: ModelStateSnapshot,
        runtimeStatus: AIRuntimeStatus?
    ) -> [String: ModelCommandResult] {
        guard !results.isEmpty,
              let runtimeStatus,
              runtimeStatus.isAlive(ttl: AIRuntimeStatus.recommendedHeartbeatTTL) else {
            return results
        }

        let modelByID = Dictionary(uniqueKeysWithValues: snapshot.models.map { ($0.id, $0) })
        return results.filter { modelId, result in
            !shouldClearRecoveredRuntimeFailure(
                result,
                model: modelByID[modelId],
                runtimeStatus: runtimeStatus
            )
        }
    }

    nonisolated static func shouldClearRecoveredRuntimeFailure(
        _ result: ModelCommandResult,
        model: HubModel?,
        runtimeStatus: AIRuntimeStatus
    ) -> Bool {
        guard !result.ok else { return false }

        let action = result.action
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard ["load", "warmup", "unload", "evict", "bench"].contains(action) else {
            return false
        }

        let message = result.msg.trimmingCharacters(in: .whitespacesAndNewlines)
        if message == LocalModelRuntimeActionPlanner.runtimeStartMessage {
            return true
        }

        guard let model else { return false }
        let providerID = LocalModelRuntimeActionPlanner.providerID(for: model)
        guard runtimeStatus.isProviderReady(providerID, ttl: AIRuntimeStatus.recommendedHeartbeatTTL) else {
            return false
        }

        let providerUnavailablePrefix = "AI 运行时已启动，但 \(providerID) provider 当前不可用"
        return message.hasPrefix(providerUnavailablePrefix)
    }

    private func relinkManagedLocalModelsIfNeeded() {
        guard SharedPaths.isSandboxedProcess() else { return }

        let baseDir = SharedPaths.ensureHubDirectory()
        let fileManager = FileManager.default

        var catalog = ModelCatalogStorage.load()
        var catalogChanged = false
        for index in catalog.models.indices {
            guard let updated = LocalModelManagedStorage.relinkedCatalogEntryIfManagedCopyExists(
                catalog.models[index],
                baseDir: baseDir,
                fileManager: fileManager
            ) else {
                continue
            }
            catalog.models[index] = updated
            catalogChanged = true
        }
        if catalogChanged {
            ModelCatalogStorage.save(catalog)
        }

        var state = ModelStateStorage.load()
        var stateChanged = false
        let catalogByID = Dictionary(uniqueKeysWithValues: catalog.models.map { ($0.id, $0) })
        for index in state.models.indices {
            let model = state.models[index]
            if let catalogEntry = catalogByID[model.id] {
                let updatedPath = catalogEntry.modelPath.trimmingCharacters(in: .whitespacesAndNewlines)
                if !updatedPath.isEmpty, updatedPath != (model.modelPath ?? "") {
                    state.models[index].modelPath = updatedPath
                    stateChanged = true
                }
                if catalogEntry.note != model.note {
                    state.models[index].note = catalogEntry.note
                    stateChanged = true
                }
                continue
            }
            guard let synthesized = Self.synthesizedCatalogEntry(from: model),
                  let updated = LocalModelManagedStorage.relinkedCatalogEntryIfManagedCopyExists(
                    synthesized,
                    baseDir: baseDir,
                    fileManager: fileManager
                  ) else {
                continue
            }
            state.models[index].modelPath = updated.modelPath
            state.models[index].note = updated.note
            stateChanged = true
        }
        if stateChanged {
            state.updatedAt = Date().timeIntervalSince1970
            ModelStateStorage.save(state)
        }
    }

    private func pruneMissingManagedLocalModelsIfNeeded() {
        guard SharedPaths.isSandboxedProcess() else { return }

        let catalog = ModelCatalogStorage.load()
        let state = ModelStateStorage.load()
        let reconciled = Self.reconciledManagedLocalModelSnapshots(
            catalog: catalog,
            state: state,
            baseDir: SharedPaths.ensureHubDirectory(),
            fileManager: .default
        )
        if reconciled.catalog.models != catalog.models {
            ModelCatalogStorage.save(reconciled.catalog)
        }
        if reconciled.state.models != state.models {
            ModelStateStorage.save(reconciled.state)
        }
    }

    static func reconciledManagedLocalModelSnapshots(
        catalog: ModelCatalogSnapshot,
        state: ModelStateSnapshot,
        baseDir: URL = SharedPaths.ensureHubDirectory(),
        fileManager: FileManager = .default
    ) -> (catalog: ModelCatalogSnapshot, state: ModelStateSnapshot, removedModelIDs: Set<String>) {
        var removedModelIDs: Set<String> = []

        let reconciledCatalogModels = catalog.models.compactMap { entry -> ModelCatalogEntry? in
            if let updated = LocalModelManagedStorage.relinkedCatalogEntryIfManagedCopyExists(
                entry,
                baseDir: baseDir,
                fileManager: fileManager
            ) {
                return updated
            }
            if shouldPruneMissingManagedLocalModel(
                modelPath: entry.modelPath,
                baseDir: baseDir,
                fileManager: fileManager
            ) {
                removedModelIDs.insert(entry.id)
                return nil
            }
            return entry
        }

        var reconciledCatalog = catalog
        if reconciledCatalogModels != catalog.models {
            reconciledCatalog.models = reconciledCatalogModels
            reconciledCatalog.updatedAt = Date().timeIntervalSince1970
        }

        let catalogByID = Dictionary(uniqueKeysWithValues: reconciledCatalog.models.map { ($0.id, $0) })
        var reconciledStateModels: [HubModel] = []
        reconciledStateModels.reserveCapacity(state.models.count)

        for model in state.models {
            if removedModelIDs.contains(model.id) {
                continue
            }
            if let catalogEntry = catalogByID[model.id] {
                var updatedModel = model
                updatedModel.name = catalogEntry.name
                updatedModel.backend = catalogEntry.backend
                updatedModel.runtimeProviderID = catalogEntry.runtimeProviderID
                updatedModel.quant = catalogEntry.quant
                updatedModel.contextLength = catalogEntry.contextLength
                updatedModel.maxContextLength = catalogEntry.maxContextLength
                updatedModel.paramsB = catalogEntry.paramsB
                updatedModel.roles = catalogEntry.roles
                updatedModel.modelPath = catalogEntry.modelPath
                updatedModel.note = catalogEntry.note
                updatedModel.modelFormat = catalogEntry.modelFormat
                updatedModel.defaultLoadProfile = catalogEntry.defaultLoadProfile
                updatedModel.taskKinds = catalogEntry.taskKinds
                updatedModel.inputModalities = catalogEntry.inputModalities
                updatedModel.outputModalities = catalogEntry.outputModalities
                updatedModel.offlineReady = catalogEntry.offlineReady
                updatedModel.voiceProfile = catalogEntry.voiceProfile
                updatedModel.resourceProfile = catalogEntry.resourceProfile
                updatedModel.trustProfile = catalogEntry.trustProfile
                updatedModel.processorRequirements = catalogEntry.processorRequirements
                reconciledStateModels.append(updatedModel)
                continue
            }
            if let synthesized = Self.synthesizedCatalogEntry(from: model),
               let updated = LocalModelManagedStorage.relinkedCatalogEntryIfManagedCopyExists(
                    synthesized,
                    baseDir: baseDir,
                    fileManager: fileManager
               ) {
                var updatedModel = model
                updatedModel.modelPath = updated.modelPath
                updatedModel.note = updated.note
                reconciledStateModels.append(updatedModel)
                continue
            }
            if shouldPruneMissingManagedLocalModel(
                modelPath: model.modelPath ?? "",
                baseDir: baseDir,
                fileManager: fileManager
            ) {
                removedModelIDs.insert(model.id)
                continue
            }
            reconciledStateModels.append(model)
        }

        var reconciledState = state
        if reconciledStateModels != state.models {
            reconciledState.models = reconciledStateModels
            reconciledState.updatedAt = Date().timeIntervalSince1970
        }

        return (reconciledCatalog, reconciledState, removedModelIDs)
    }

    private static func shouldPruneMissingManagedLocalModel(
        modelPath: String,
        baseDir: URL,
        fileManager: FileManager
    ) -> Bool {
        let trimmedPath = modelPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else { return false }
        guard LocalModelManagedStorage.isManagedPath(trimmedPath, baseDir: baseDir) else {
            return false
        }

        let candidateURL = URL(fileURLWithPath: trimmedPath).standardizedFileURL
        let managedRoot = LocalModelManagedStorage.managedModelsDirectory(baseDir: baseDir).standardizedFileURL
        guard candidateURL.path != managedRoot.path else { return false }
        return !fileManager.fileExists(atPath: candidateURL.path)
    }

    private func migrateLegacyHomeModelsIfNeeded() {
        // If we are using a sandbox container base dir, migrate any previously copied
        // ~/RELFlowHub/*.json into the container so the UI can see them.
        let base = SharedPaths.ensureHubDirectory()
        let legacy = SharedPaths.realHomeDirectory().appendingPathComponent("RELFlowHub", isDirectory: true)
        if base.path == legacy.path {
            return
        }

        let fm = FileManager.default
        let names = ["models_state.json", "models_catalog.json"]
        for n in names {
            let src = legacy.appendingPathComponent(n)
            let dst = base.appendingPathComponent(n)
            if fm.fileExists(atPath: dst.path) {
                continue
            }
            if !fm.fileExists(atPath: src.path) {
                continue
            }
            try? fm.createDirectory(at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? fm.copyItem(at: src, to: dst)
        }
    }
}

struct PendingCommand: Equatable, Sendable {
    var reqId: String
    var action: String
    var requestedAt: Double
}

struct SuccessfulLocalLifecycleAction: Equatable, Sendable {
    var action: String
    var finishedAt: Double
}

struct ModelCommandResult: Codable, Equatable, Sendable {
    var type: String
    var reqId: String
    var action: String
    var modelId: String
    var ok: Bool
    var msg: String
    var finishedAt: Double

    enum CodingKeys: String, CodingKey {
        case type
        case reqId = "req_id"
        case action
        case modelId = "model_id"
        case ok
        case msg
        case finishedAt = "finished_at"
    }
}
