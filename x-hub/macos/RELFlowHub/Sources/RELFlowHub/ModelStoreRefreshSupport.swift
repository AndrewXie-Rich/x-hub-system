import Foundation
import RELFlowHubCore
struct FileStamp: Equatable, Sendable {
    let path: String
    let exists: Bool
    let modifiedAt: TimeInterval
    let size: Int64
}

struct RemoteModelExportCache {
    let remoteModelsStamp: FileStamp
    let remoteKeyHealthStamp: FileStamp
    let models: [RemoteModelEntry]
}

struct CommandResultFile: Sendable {
    let url: URL
    let result: ModelCommandResult
}

struct RefreshComputation: Sendable {
    let baseCatalogSnapshot: ModelCatalogSnapshot
    let reconciledCatalogSnapshot: ModelCatalogSnapshot
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

extension ModelStore {
    func refresh(reconcileManagedModels: Bool = true) {
        if reconcileManagedModels {
            forceManagedModelReconcileOnNextRefresh = true
        }
        refreshRequestedRevision &+= 1
        scheduleRefreshIfNeeded()
    }

    func resetDerivedUICaches() {
        localRuntimeSupportInputsCache.removeAll(keepingCapacity: true)
        localRuntimePresentationCache.removeAll(keepingCapacity: true)
        localRuntimeActionBlockedMessageCache.removeAll(keepingCapacity: true)
        availableBenchTaskDescriptorsCache.removeAll(keepingCapacity: true)
        availableLocalRuntimeTargetOptionsCache.removeAll(keepingCapacity: true)
    }

    func scheduleRefreshIfNeeded() {
        guard refreshTask == nil else { return }

        let revision = refreshRequestedRevision
        let scheduledAt = HubPerformanceTrace.now()
        let pendingSnapshot = pendingByModelId
        let lifecycleSnapshot = successfulLocalLifecycleActionsByModelId
        let baseDir = refreshBaseDir
        let commandResultDirectories = commandResultDirectories
        let reconcileManagedModels = shouldReconcileManagedModels(now: Date().timeIntervalSince1970)
        let exportableRemoteModels = cachedExportableRemoteModels()
        refreshTask = Task { [weak self] in
            let computeStartedAt = HubPerformanceTrace.now()
            let computation = await Task.detached(priority: .utility) {
                Self.buildRefreshComputation(
                    pendingByModelId: pendingSnapshot,
                    successfulLocalLifecycleActionsByModelId: lifecycleSnapshot,
                    baseDir: baseDir,
                    commandResultDirectories: commandResultDirectories,
                    reconcileManagedLocalModels: reconcileManagedModels,
                    exportableRemoteModels: exportableRemoteModels
                )
            }.value
            HubPerformanceTrace.logSlow(
                "models.refresh.compute",
                startedAt: computeStartedAt,
                thresholdMs: 120,
                details: "revision=\(revision) reconcile_managed=\(reconcileManagedModels ? 1 : 0) pending=\(pendingSnapshot.count)"
            )
            HubPerformanceTrace.logSlow(
                "models.refresh.end_to_end_before_apply",
                startedAt: scheduledAt,
                thresholdMs: 180,
                details: "revision=\(revision)"
            )
            self?.finishRefresh(
                revision: revision,
                computation: computation
            )
        }
    }

    func shouldReconcileManagedModels(now: TimeInterval) -> Bool {
        if forceManagedModelReconcileOnNextRefresh {
            forceManagedModelReconcileOnNextRefresh = false
            lastManagedModelReconcileAt = now
            return true
        }

        guard lastManagedModelReconcileAt > 0 else {
            lastManagedModelReconcileAt = now
            return true
        }

        if now - lastManagedModelReconcileAt >= Self.managedModelReconcileInterval {
            lastManagedModelReconcileAt = now
            return true
        }
        return false
    }

    func finishRefresh(
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

    func applyRefreshComputation(_ computation: RefreshComputation) {
        let startedAt = HubPerformanceTrace.now()
        let runtimeStatusChanged = currentRuntimeStatus != computation.runtimeStatus
        let snapshotChanged = snapshot != computation.reconciledSnapshot
        let benchSnapshotChanged = benchSnapshot != computation.benchSnapshot
        let pairedProfilesChanged = currentPairedProfilesSnapshot != computation.pairedProfilesSnapshot
        let targetPreferencesChanged = currentTargetPreferenceByModelId != computation.targetPreferenceByModelId
        let requestContextsChanged = currentLocalRuntimeRequestContextByModelId != computation.requestContextByModelId
        let benchMapChanged = benchByModelId != computation.benchByModelId
        let shouldResetUICaches = runtimeStatusChanged
            || snapshotChanged
            || pairedProfilesChanged
            || targetPreferencesChanged
            || requestContextsChanged
            || benchSnapshotChanged

        if shouldResetUICaches {
            resetDerivedUICaches()
        }
        if runtimeStatusChanged {
            currentRuntimeStatus = computation.runtimeStatus
        }
        if snapshotChanged {
            snapshot = computation.reconciledSnapshot
        }
        if computation.reconciledCatalogSnapshot != computation.baseCatalogSnapshot {
            ModelCatalogStorage.save(computation.reconciledCatalogSnapshot)
        }
        if computation.reconciledSnapshot != computation.baseSnapshot {
            ModelStateStorage.save(computation.reconciledSnapshot)
        }
        if benchSnapshotChanged {
            benchSnapshot = computation.benchSnapshot
        }
        if pairedProfilesChanged {
            currentPairedProfilesSnapshot = computation.pairedProfilesSnapshot
        }
        if targetPreferencesChanged {
            currentTargetPreferenceByModelId = computation.targetPreferenceByModelId
        }
        if benchMapChanged {
            benchByModelId = computation.benchByModelId
        }
        if requestContextsChanged {
            currentLocalRuntimeRequestContextByModelId = computation.requestContextByModelId
        }

        reconcilePendingWithState()
        reconcileSuccessfulLifecycleActionsWithRuntimeStatus()
        applyCommandResults(
            computation.decodedCommandResults,
            invalidURLs: computation.invalidCommandResultURLs
        )
        let reconciledResults = Self.reconciledLastCommandResults(
            lastResultByModelId,
            snapshot: snapshot,
            runtimeStatus: currentRuntimeStatus
        )
        if lastResultByModelId != reconciledResults {
            lastResultByModelId = reconciledResults
        }
        HubPerformanceTrace.logSlow(
            "models.refresh.apply",
            startedAt: startedAt,
            thresholdMs: 40,
            details: "models=\(snapshot.models.count) bench=\(benchSnapshot.results.count) pending=\(pendingByModelId.count) results=\(lastResultByModelId.count) cache_reset=\(shouldResetUICaches ? 1 : 0) snapshot_changed=\(snapshotChanged ? 1 : 0) runtime_changed=\(runtimeStatusChanged ? 1 : 0)"
        )
    }

}
