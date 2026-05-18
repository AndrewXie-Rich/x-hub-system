import Foundation
import Combine

@MainActor
final class HubModelManager: ObservableObject {
    static let shared = HubModelManager()

    @Published var availableModels: [HubModel] = []
    @Published private(set) var latestSnapshot: ModelStateSnapshot = .empty()
    @Published private(set) var latestRustInventoryProjection: XTRustModelInventoryProjection?
    @Published private(set) var hasFetchedAuthoritativeSnapshot: Bool = false
    @Published var isLoading: Bool = false
    @Published var error: String?

    private var cancellables = Set<AnyCancellable>()
    private var appModel: AppModel?
    private var fetchGeneration: UInt64 = 0

    init() {}

    func setAppModel(_ appModel: AppModel?) {
        self.appModel = appModel
    }

    func fetchModels() async {
        fetchGeneration &+= 1
        let generation = fetchGeneration
        let fallbackSnapshot = currentFallbackSnapshot()
        let hadVisibleModels = !visibleSnapshot(fallback: fallbackSnapshot).models.isEmpty

        isLoading = !hadVisibleModels
        error = nil

        // Keep the Models page local-first so stale pairing state never blocks the
        // Hub control surface from rendering its own inventory.
        let rustInventoryResult = await XTRustModelInventoryLiveBridge.loadIfEnabled(
            runtimeBaseDir: HubPaths.baseDir()
        )
        let rustInventoryProjection: XTRustModelInventoryProjection?
        let localSnapshot: ModelStateSnapshot
        switch rustInventoryResult {
        case .loaded(let snapshot):
            rustInventoryProjection = snapshot.projection
            localSnapshot = snapshot.projection.snapshot
        case .disabled, .unavailable:
            rustInventoryProjection = nil
            localSnapshot = await HubAIClient.shared.loadModelsState(transportOverride: .fileIPC)
        }
        let hasRemoteProfile = await HubPairingCoordinator.shared.hasHubEnv(stateDir: nil)
        // Reconcile against authoritative Hub inventory whenever a remote profile
        // exists, even if the last connect probe state in AppModel is stale.
        let shouldAttemptBackgroundAuthoritativeRefresh =
            HubAIClient.transportMode() != .fileIPC
            && hasRemoteProfile
            && rustInventoryProjection == nil
        guard isCurrentFetch(generation) else { return }

        if !localSnapshot.models.isEmpty || !hadVisibleModels {
            applyFetchedSnapshot(
                localSnapshot,
                rustInventoryProjection: rustInventoryProjection
            )
        }

        if hasRemoteProfile {
            let remotePaidAccessSnapshot = await HubAIClient.shared.currentRemotePaidAccessSnapshot(
                refreshIfNeeded: false
            )
            guard isCurrentFetch(generation) else { return }
            appModel?.hubRemotePaidAccessSnapshot = remotePaidAccessSnapshot
        } else {
            appModel?.hubRemotePaidAccessSnapshot = nil
        }
        guard isCurrentFetch(generation) else { return }
        isLoading = false

        guard shouldAttemptBackgroundAuthoritativeRefresh else {
            return
        }

        let remoteSnapshot = await HubAIClient.shared.loadAuthoritativeModelsState()
        guard isCurrentFetch(generation) else { return }

        if !remoteSnapshot.models.isEmpty || localSnapshot.models.isEmpty {
            applyFetchedSnapshot(remoteSnapshot)
        }

        let remotePaidAccessSnapshot = await HubAIClient.shared.currentRemotePaidAccessSnapshot(
            refreshIfNeeded: false
        )
        guard isCurrentFetch(generation) else { return }
        appModel?.hubRemotePaidAccessSnapshot = remotePaidAccessSnapshot
    }

    func visibleSnapshot(fallback: ModelStateSnapshot) -> ModelStateSnapshot {
        hasFetchedAuthoritativeSnapshot ? latestSnapshot : fallback
    }

    func visibleModels(fallback: [HubModel]) -> [HubModel] {
        visibleSnapshot(
            fallback: ModelStateSnapshot(
                models: fallback,
                updatedAt: latestSnapshot.updatedAt
            )
        ).models
    }

    func getPreferredModel(for role: AXRole) -> String? {
        guard let appModel = appModel else { return nil }
        let settings = appModel.settingsStore.settings
        let route = settings.modelRoute(for: role)

        return route.primaryModelId
    }

    func getPaidBackupModel(for role: AXRole) -> String? {
        guard let appModel = appModel else { return nil }
        return appModel.settingsStore.settings.modelRoute(for: role).paidBackupModelId
    }

    func setModel(for role: AXRole, modelId: String?) {
        guard let appModel = appModel else { return }
        let settings = appModel.settingsStore.settings
        let currentAssignment = settings.assignment(for: role)
        guard currentAssignment.providerKind != .hub
                || normalizedModelId(currentAssignment.model) != normalizedModelId(modelId) else {
            return
        }
        let newSettings = settings.settingRolePrimaryModel(role: role, modelId: modelId)
        appModel.settingsStore.settings = newSettings
        appModel.settingsStore.save()
        objectWillChange.send()
    }

    func setPaidBackupModel(for role: AXRole, modelId: String?) {
        guard let appModel = appModel else { return }
        let settings = appModel.settingsStore.settings
        let currentRoute = settings.modelRoute(for: role)
        guard normalizedModelId(currentRoute.paidBackupModelId) != normalizedModelId(modelId) else {
            return
        }
        appModel.settingsStore.settings = settings.settingRolePaidBackupModel(role: role, modelId: modelId)
        appModel.settingsStore.save()
        objectWillChange.send()
    }

    func setLocalFallbackMode(
        for role: AXRole,
        mode: LocalModelFallbackMode,
        modelId: String? = nil
    ) {
        guard let appModel = appModel else { return }
        let settings = appModel.settingsStore.settings
        let currentRoute = settings.modelRoute(for: role)
        guard currentRoute.localFallbackMode != mode
                || normalizedModelId(currentRoute.localFallbackModelId) != normalizedModelId(modelId) else {
            return
        }
        appModel.settingsStore.settings = settings.settingRoleLocalFallback(
            role: role,
            mode: mode,
            modelId: modelId
        )
        appModel.settingsStore.save()
        objectWillChange.send()
    }

    private func normalizedModelId(_ raw: String?) -> String {
        (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func currentFallbackSnapshot() -> ModelStateSnapshot {
        if let appModel {
            return appModel.modelsState
        }
        return latestSnapshot
    }

    private func applyFetchedSnapshot(
        _ snapshot: ModelStateSnapshot,
        rustInventoryProjection: XTRustModelInventoryProjection? = nil
    ) {
        latestSnapshot = snapshot
        latestRustInventoryProjection = rustInventoryProjection
        availableModels = snapshot.models
        hasFetchedAuthoritativeSnapshot = true
        appModel?.modelsState = snapshot
    }

    private func isCurrentFetch(_ generation: UInt64) -> Bool {
        generation == fetchGeneration
    }
}
