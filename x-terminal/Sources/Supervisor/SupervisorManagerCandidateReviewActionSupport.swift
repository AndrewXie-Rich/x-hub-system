import Foundation

extension SupervisorManager {
    func stageSupervisorCandidateReview(_ item: HubIPCClient.SupervisorCandidateReviewItem) {
        let requestId = item.requestId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !requestId.isEmpty else { return }
        guard !supervisorCandidateReviewActionsInFlight.contains(requestId) else { return }

        let projectId = resolvedProjectIdForSupervisorCandidateReview(item)
        guard let projectId else {
            addSystemMessage("Supervisor candidate review 转入审查失败：缺少项目绑定。")
            return
        }

        supervisorCandidateReviewActionsInFlight.insert(requestId)

        Task { [weak self] in
            guard let self else { return }
            let result = await self.stageSupervisorCandidateReviewRequest(
                candidateRequestId: requestId,
                projectId: projectId
            )
            await self.completeSupervisorCandidateReviewStageAction(
                requestId: requestId,
                item: item,
                result: result
            )
        }
    }

    func stageSupervisorCandidateReviewRequest(
        candidateRequestId: String,
        projectId: String
    ) async -> HubIPCClient.SupervisorCandidateReviewStageResult {
        if let override = stageSupervisorCandidateReviewRequestOverride {
            return await override(candidateRequestId, projectId)
        }
        return await HubIPCClient.stageSupervisorCandidateReview(
            candidateRequestId: candidateRequestId,
            projectId: projectId
        )
    }

    func completeSupervisorCandidateReviewStageAction(
        requestId: String,
        item: HubIPCClient.SupervisorCandidateReviewItem,
        result: HubIPCClient.SupervisorCandidateReviewStageResult
    ) async {
        supervisorCandidateReviewActionsInFlight.remove(requestId)

        let reviewSummary = supervisorCandidateReviewSummaryLine(item)
        if result.ok {
            let state = result.reviewState.trimmingCharacters(in: .whitespacesAndNewlines)
            let draft = result.pendingChangeId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let detail = draft.isEmpty ? "" : " · draft=\(draft)"
            let stateText = state.isEmpty ? "" : " · state=\(state)"
            addSystemMessage("已把 Supervisor candidate review 转入审查：\(reviewSummary)\(stateText)\(detail)")
        } else {
            let reason = result.reasonCode?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown"
            let reasonText = annotatedUserVisibleReason(
                raw: reason,
                display: SupervisorBlockerPresentation.displayText(reason)
            )
            addSystemMessage("Supervisor candidate review 转入审查失败：\(reviewSummary)。原因：\(reasonText)。")
        }

        await refreshSchedulerSnapshot(force: true)
    }

    func resolvedProjectIdForSupervisorCandidateReview(
        _ item: HubIPCClient.SupervisorCandidateReviewItem
    ) -> String? {
        let projectId = item.projectId.trimmingCharacters(in: .whitespacesAndNewlines)
        if !projectId.isEmpty {
            return projectId
        }
        return supervisorCandidateReviewProjectIDs(item).first
    }

    func supervisorCandidateReviewSummaryLine(
        _ item: HubIPCClient.SupervisorCandidateReviewItem
    ) -> String {
        let requestId = item.requestId.trimmingCharacters(in: .whitespacesAndNewlines)
        let projectIds = supervisorCandidateReviewProjectIDs(item)
        let projectNames = projectIds.map { frontstageSupervisorCandidateReviewProjectNames[$0] ?? $0 }
        let projectText: String = {
            if let first = projectNames.first, projectNames.count == 1 { return first }
            if !projectNames.isEmpty { return projectNames.joined(separator: "、") }
            return "未绑定项目"
        }()
        let summary = item.summaryLine.trimmingCharacters(in: .whitespacesAndNewlines)
        let countText = "\(max(0, item.candidateCount)) 条候选记忆"
        if !summary.isEmpty {
            return "\(projectText) · \(countText) · \(summary) · handoff=\(requestId)"
        }
        return "\(projectText) · \(countText) · handoff=\(requestId)"
    }
}
