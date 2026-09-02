import Foundation

extension SupervisorManager {
    func refreshSupervisorDoctorReport() {
        _ = runSupervisorDoctorPreflight(reason: "manual_refresh", emitSystemMessage: true)
    }

    func refreshPendingHubGrantSnapshotNow() {
        Task { @MainActor in
            await refreshSchedulerSnapshot(force: true)
        }
    }

    func refreshSupervisorCandidateReviewSnapshotNow() {
        Task { @MainActor in
            await refreshSchedulerSnapshot(force: true)
        }
    }

    func restartSchedulerPollTimer() {
        schedulerPollTimer?.invalidate()
        schedulerPollTimer = Timer.scheduledTimer(withTimeInterval: schedulerPollIntervalSec, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.refreshSchedulerSnapshot(force: false)
            }
        }
        RunLoop.main.add(schedulerPollTimer!, forMode: .common)
    }

    func refreshSchedulerSnapshot(force: Bool) async {
        if let override = schedulerSnapshotRefreshOverride {
            await override(force)
            return
        }
        if schedulerRefreshInFlight, !force {
            return
        }
        let now = Date().timeIntervalSince1970
        if !force, (now - schedulerLastRefreshAt) < max(0.8, schedulerPollIntervalSec * 0.8) {
            return
        }
        schedulerRefreshInFlight = true
        defer {
            schedulerRefreshInFlight = false
            schedulerLastRefreshAt = Date().timeIntervalSince1970
        }

        async let schedulerSnapshotRequest = HubIPCClient.requestSchedulerStatus(includeQueueItems: true, queueItemsLimit: 120)
        async let pendingGrantsRequest = HubIPCClient.requestPendingGrantRequests(projectId: nil, limit: 240)
        async let supervisorCandidateReviewRequest = HubIPCClient.requestSupervisorCandidateReviewSnapshot(projectId: nil, limit: 260)
        async let connectorIngressRequest = HubIPCClient.requestConnectorIngressReceipts(projectId: nil, limit: 240)
        async let operatorChannelXTCommandsRequest = HubIPCClient.requestOperatorChannelXTCommands(projectId: nil, limit: 240)

        let snapshot = await schedulerSnapshotRequest
        if let snapshot {
            schedulerSnapshot = snapshot
            schedulerLastSuccessAt = Date().timeIntervalSince1970
        } else if force || (schedulerLastSuccessAt > 0 && (now - schedulerLastSuccessAt) >= schedulerSnapshotStaleSec) {
            schedulerSnapshot = nil
        }

        let pendingGrants = await pendingGrantsRequest
        if let pendingGrants {
            pendingGrantSnapshot = pendingGrants
            pendingGrantLastSuccessAt = Date().timeIntervalSince1970
        } else if force || (pendingGrantLastSuccessAt > 0 && (now - pendingGrantLastSuccessAt) >= schedulerSnapshotStaleSec) {
            pendingGrantSnapshot = nil
        }

        let supervisorCandidateReview = await supervisorCandidateReviewRequest
        if let supervisorCandidateReview {
            supervisorCandidateReviewSnapshot = supervisorCandidateReview
            supervisorCandidateReviewLastSuccessAt = Date().timeIntervalSince1970
        } else if force || (supervisorCandidateReviewLastSuccessAt > 0 && (now - supervisorCandidateReviewLastSuccessAt) >= schedulerSnapshotStaleSec) {
            supervisorCandidateReviewSnapshot = nil
        }

        let connectorIngress = await connectorIngressRequest
        if let connectorIngress {
            connectorIngressSnapshot = connectorIngress
            connectorIngressLastSuccessAt = Date().timeIntervalSince1970
        } else if force || (connectorIngressLastSuccessAt > 0 && (now - connectorIngressLastSuccessAt) >= schedulerSnapshotStaleSec) {
            connectorIngressSnapshot = nil
        }
        let operatorChannelXTCommands = await operatorChannelXTCommandsRequest
        var operatorChannelXTCommandResults: HubIPCClient.OperatorChannelXTCommandResultSnapshot?
        if operatorChannelXTCommands?.items.isEmpty == false {
            operatorChannelXTCommandResults = await HubIPCClient.requestOperatorChannelXTCommandResults(projectId: nil, limit: 400)
        }
        let refreshCompletedAt = Date()
        rebuildPendingHubGrantViewState(now: refreshCompletedAt.timeIntervalSince1970)
        rebuildSupervisorCandidateReviewViewState(now: refreshCompletedAt.timeIntervalSince1970)
        rebuildPendingSupervisorSkillApprovalViewState(
            force: force,
            reason: "scheduler_poll",
            now: refreshCompletedAt.timeIntervalSince1970
        )
        _ = serviceHubConnectorIngressReceipts(now: refreshCompletedAt, emitSystemMessage: false)
        _ = serviceAutomationScheduleTriggers(now: refreshCompletedAt, emitSystemMessage: false)
        if let operatorChannelXTCommands {
            _ = serviceOperatorChannelXTCommands(
                operatorChannelXTCommands,
                resultsSnapshot: operatorChannelXTCommandResults,
                now: refreshCompletedAt
            )
        }
    }

    func schedulerSignal(
        for projectId: String,
        now: TimeInterval = Date().timeIntervalSince1970
    ) -> (inFlight: Int, queued: Int, oldestQueuedMs: Int)? {
        let pid = projectId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pid.isEmpty else { return nil }
        guard let snapshot = schedulerSnapshot else { return nil }

        let updatedAtSec: Double = {
            let ms = max(0, snapshot.updatedAtMs)
            if ms > 0 {
                return ms / 1000.0
            }
            return schedulerLastSuccessAt
        }()
        if updatedAtSec > 0, now - updatedAtSec > schedulerSnapshotStaleSec {
            return nil
        }

        let scopeKey = "project:\(pid)"
        let inFlight = snapshot.inFlightByScope.first(where: { $0.scopeKey == scopeKey })?.count ?? 0
        let queued = snapshot.queuedByScope.first(where: { $0.scopeKey == scopeKey })?.count ?? 0
        let oldestQueuedMs = snapshot.queueItems
            .filter { $0.scopeKey == scopeKey }
            .map(\.queuedMs)
            .max() ?? (queued > 0 ? snapshot.oldestQueuedMs : 0)
        return (max(0, inFlight), max(0, queued), max(0, oldestQueuedMs))
    }
}
