import Foundation
import SwiftUI
import RELFlowHubCore

@MainActor
final class ModelStore: ObservableObject {
    static let shared = ModelStore()
    nonisolated static let successfulLifecycleActionGraceSec: TimeInterval = 8.0
    nonisolated static let managedModelReconcileInterval: TimeInterval = 60.0
    nonisolated static let systemVoiceTTSModelID = "system-voice-tts"
    nonisolated static let systemVoiceTTSDefaultBinaryPath = "/usr/bin/say"
    nonisolated static let systemVoiceTTSNote = "system_voice_compatibility; uses macOS system voice; no model download required"

    @Published var snapshot: ModelStateSnapshot = .empty()
    @Published var benchSnapshot: ModelsBenchSnapshot = .empty()
    @Published var benchByModelId: [String: ModelBenchResult] = [:]
    @Published var currentLocalRuntimeRequestContextByModelId: [String: LocalModelRuntimeRequestContext] = [:]
    @Published var pendingByModelId: [String: PendingCommand] = [:]
    @Published var lastResultByModelId: [String: ModelCommandResult] = [:]

    private var timer: Timer?
    var runtimeRecoveryInFlightModelIds: Set<String> = []
    var localModelPreparationInFlightModelIds: Set<String> = []
    var localRuntimeSupportInputsCache: [String: LocalRuntimeSupportInputs] = [:]
    var localRuntimePresentationCache: [String: OptionalRuntimePresentationCacheEntry] = [:]
    var localRuntimeActionBlockedMessageCache: [String: OptionalStringCacheEntry] = [:]
    var availableBenchTaskDescriptorsCache: [String: [LocalTaskRoutingDescriptor]] = [:]
    var availableLocalRuntimeTargetOptionsCache: [String: [LocalModelRuntimeTargetOption]] = [:]
    var currentRuntimeStatus: AIRuntimeStatus?
    var currentPairedProfilesSnapshot: HubPairedTerminalLocalModelProfilesSnapshot = .empty()
    var currentTargetPreferenceByModelId: [String: LocalModelRuntimeTargetPreference] = [:]
    var successfulLocalLifecycleActionsByModelId: [String: SuccessfulLocalLifecycleAction] = [:]
    var refreshTask: Task<Void, Never>?
    var refreshRequestedRevision: UInt64 = 0
    var forceManagedModelReconcileOnNextRefresh: Bool = true
    var lastManagedModelReconcileAt: TimeInterval = 0
    var remoteModelExportCache: RemoteModelExportCache?
    let refreshBaseDir = SharedPaths.ensureHubDirectory()
    let commandResultDirectories = ModelStore.commandResultDirectoryCandidates()

    private init() {
        migrateLegacyHomeModelsIfNeeded()
        backfillRuntimeProviderIDsIfNeeded()
        relinkManagedLocalModelsIfNeeded()
        pruneMissingManagedLocalModelsIfNeeded()
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh(reconcileManagedModels: false)
            }
        }

        // Remove legacy demo models (note="demo", no modelPath) so the UI only shows real models.
        pruneLegacyDemoModels()
    }

    func pendingAction(for modelId: String) -> String? {
        pendingByModelId[modelId]?.action
    }

    func lastError(for modelId: String) -> String? {
        guard let r = lastResultByModelId[modelId] else { return nil }
        if r.ok { return nil }
        return r.msg
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

    func reconcilePendingWithState() {
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

    func reconcileSuccessfulLifecycleActionsWithRuntimeStatus(
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

    func applySuccessfulLocalLifecycleAction(
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
