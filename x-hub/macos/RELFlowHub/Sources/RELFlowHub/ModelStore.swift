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
}
