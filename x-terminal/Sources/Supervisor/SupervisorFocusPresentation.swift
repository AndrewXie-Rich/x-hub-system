import Foundation

enum SupervisorFocusPresentation {
    static let runtimeActivityBoardAnchorID =
        "supervisor.dashboard.runtimeActivityBoard"
    static let automationRuntimeBoardAnchorID =
        "supervisor.dashboard.automationRuntimeBoard"
    static let laneHealthBoardAnchorID =
        "supervisor.dashboard.laneHealthBoard"
    static let pendingSupervisorSkillApprovalBoardAnchorID =
        "supervisor.dashboard.pendingSupervisorSkillApprovalBoard"
    static let pendingHubGrantBoardAnchorID =
        "supervisor.dashboard.pendingHubGrantBoard"
    static let recentSupervisorSkillActivityBoardAnchorID =
        "supervisor.dashboard.recentSupervisorSkillActivityBoard"

    struct BoardResolution: Equatable {
        var selectedProjectId: String?
        var boardAnchorID: String
    }

    struct ApprovalResolution: Equatable {
        var selectedProjectId: String?
        var boardAnchorID: String
        var highlightedApprovalAnchor: String?
        var matchedApproval: SupervisorManager.SupervisorPendingSkillApproval?
        var refreshPendingApprovals: Bool
    }

    struct GrantResolution: Equatable {
        var selectedProjectId: String?
        var boardAnchorID: String
        var highlightedGrantAnchor: String?
        var matchedGrant: SupervisorManager.SupervisorPendingGrant?
        var refreshPendingHubGrants: Bool
    }

    struct SkillRecordResolution: Equatable {
        var selectedProjectId: String?
        var boardAnchorID: String
        var highlightedSkillActivityRequestId: String?
        var matchedActivity: SupervisorManager.SupervisorRecentSkillActivity?
        var fallbackProjectId: String?
        var fallbackRequestId: String
        var refreshRecentSkillActivities: Bool
    }

    static func resolveApproval(
        request: AXSupervisorFocusRequest,
        requestId: String,
        pendingApprovals: [SupervisorManager.SupervisorPendingSkillApproval]
    ) -> ApprovalResolution {
        let resolvedProjectId = resolvedProjectIdForApprovalFocus(
            explicitProjectId: request.projectId,
            requestId: requestId,
            pendingApprovals: pendingApprovals
        )
        let matchedApproval = matchingPendingSupervisorSkillApproval(
            projectId: resolvedProjectId ?? request.projectId,
            requestId: requestId,
            pendingApprovals: pendingApprovals
        )
        return ApprovalResolution(
            selectedProjectId: normalizedFocusToken(resolvedProjectId),
            boardAnchorID: pendingSupervisorSkillApprovalBoardAnchorID,
            highlightedApprovalAnchor: matchedApproval.map(pendingSupervisorSkillApprovalRowAnchor),
            matchedApproval: matchedApproval,
            refreshPendingApprovals: pendingApprovals.isEmpty
        )
    }

    static func resolveGrant(
        request: AXSupervisorFocusRequest,
        grantRequestId: String?,
        capability: String?,
        pendingHubGrants: [SupervisorManager.SupervisorPendingGrant]
    ) -> GrantResolution {
        let resolvedProjectId = resolvedProjectIdForGrantFocus(
            explicitProjectId: request.projectId,
            grantRequestId: grantRequestId,
            capability: capability,
            pendingHubGrants: pendingHubGrants
        )
        let matchedGrant = matchingPendingHubGrant(
            projectId: resolvedProjectId ?? request.projectId,
            grantRequestId: grantRequestId,
            capability: capability,
            pendingHubGrants: pendingHubGrants
        )
        return GrantResolution(
            selectedProjectId: normalizedFocusToken(resolvedProjectId),
            boardAnchorID: pendingHubGrantBoardAnchorID,
            highlightedGrantAnchor: matchedGrant.map(pendingHubGrantRowAnchor),
            matchedGrant: matchedGrant,
            refreshPendingHubGrants: pendingHubGrants.isEmpty
        )
    }

    static func resolveBoard(
        request: AXSupervisorFocusRequest,
        anchorID: String
    ) -> BoardResolution {
        BoardResolution(
            selectedProjectId: normalizedFocusToken(request.projectId),
            boardAnchorID: normalizedFocusToken(anchorID) ?? runtimeActivityBoardAnchorID
        )
    }

    static func resolveSkillRecord(
        request: AXSupervisorFocusRequest,
        requestId: String,
        recentActivities: [SupervisorManager.SupervisorRecentSkillActivity]
    ) -> SkillRecordResolution {
        let resolvedProjectId = resolvedProjectIdForSkillRecordFocus(
            explicitProjectId: request.projectId,
            requestId: requestId,
            recentActivities: recentActivities
        )
        let matchedActivity = matchingRecentSupervisorSkillActivity(
            projectId: resolvedProjectId ?? request.projectId,
            requestId: requestId,
            recentActivities: recentActivities
        )
        return SkillRecordResolution(
            selectedProjectId: normalizedFocusToken(resolvedProjectId),
            boardAnchorID: recentSupervisorSkillActivityBoardAnchorID,
            highlightedSkillActivityRequestId: normalizedFocusToken(
                matchedActivity?.requestId ?? requestId
            ),
            matchedActivity: matchedActivity,
            fallbackProjectId: matchedActivity == nil
                ? normalizedFocusToken(resolvedProjectId ?? request.projectId)
                : nil,
            fallbackRequestId: requestId,
            refreshRecentSkillActivities: recentActivities.isEmpty
        )
    }

    static func matchingRecentSkillActivity(
        projectId: String?,
        requestId: String,
        recentActivities: [SupervisorManager.SupervisorRecentSkillActivity]
    ) -> SupervisorManager.SupervisorRecentSkillActivity? {
        matchingRecentSupervisorSkillActivity(
            projectId: projectId,
            requestId: requestId,
            recentActivities: recentActivities
        )
    }

    static func pendingHubGrantRowAnchor(
        _ grant: SupervisorManager.SupervisorPendingGrant
    ) -> String {
        let token = normalizedFocusToken(grant.grantRequestId) ?? grant.id
        return "supervisor.pendingHubGrant.\(token)"
    }

    static func pendingSupervisorSkillApprovalRowAnchor(
        _ approval: SupervisorManager.SupervisorPendingSkillApproval
    ) -> String {
        "supervisor.pendingSupervisorSkillApproval.\(approval.requestId)"
    }

    static func recentSkillActivityRowAnchor(
        _ item: SupervisorManager.SupervisorRecentSkillActivity
    ) -> String {
        "supervisor.recentSkillActivity.\(item.requestId)"
    }

    static func normalizedFocusToken(_ raw: String?) -> String? {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func resolvedProjectIdForApprovalFocus(
        explicitProjectId: String?,
        requestId: String,
        pendingApprovals: [SupervisorManager.SupervisorPendingSkillApproval]
    ) -> String? {
        let explicit = normalizedFocusToken(explicitProjectId)
        if let explicit, !explicit.isEmpty {
            return explicit
        }
        return matchingPendingSupervisorSkillApproval(
            projectId: nil,
            requestId: requestId,
            pendingApprovals: pendingApprovals
        )?.projectId
    }

    private static func resolvedProjectIdForGrantFocus(
        explicitProjectId: String?,
        grantRequestId: String?,
        capability: String?,
        pendingHubGrants: [SupervisorManager.SupervisorPendingGrant]
    ) -> String? {
        let explicit = normalizedFocusToken(explicitProjectId)
        if let explicit, !explicit.isEmpty {
            return explicit
        }
        return matchingPendingHubGrant(
            projectId: nil,
            grantRequestId: grantRequestId,
            capability: capability,
            pendingHubGrants: pendingHubGrants
        )?.projectId
    }

    private static func resolvedProjectIdForSkillRecordFocus(
        explicitProjectId: String?,
        requestId: String,
        recentActivities: [SupervisorManager.SupervisorRecentSkillActivity]
    ) -> String? {
        let explicit = normalizedFocusToken(explicitProjectId)
        if let explicit, !explicit.isEmpty {
            return explicit
        }
        return matchingRecentSupervisorSkillActivity(
            projectId: nil,
            requestId: requestId,
            recentActivities: recentActivities
        )?.projectId
    }

    private static func matchingPendingSupervisorSkillApproval(
        projectId: String?,
        requestId: String,
        pendingApprovals: [SupervisorManager.SupervisorPendingSkillApproval]
    ) -> SupervisorManager.SupervisorPendingSkillApproval? {
        let normalizedProjectId = normalizedFocusToken(projectId)
        let normalizedRequestId = normalizedFocusToken(requestId)
        guard let normalizedRequestId, !normalizedRequestId.isEmpty else {
            return nil
        }

        return pendingApprovals.first { approval in
            let projectMatches = normalizedProjectId == nil
                || approval.projectId.trimmingCharacters(in: .whitespacesAndNewlines) == normalizedProjectId
            return projectMatches
                && approval.requestId.trimmingCharacters(in: .whitespacesAndNewlines) == normalizedRequestId
        }
    }

    private static func matchingPendingHubGrant(
        projectId: String?,
        grantRequestId: String?,
        capability: String?,
        pendingHubGrants: [SupervisorManager.SupervisorPendingGrant]
    ) -> SupervisorManager.SupervisorPendingGrant? {
        let normalizedProjectId = normalizedFocusToken(projectId)
        let normalizedGrantId = normalizedFocusToken(grantRequestId)
        let normalizedCapability = normalizedFocusToken(capability)?.lowercased()

        if let normalizedGrantId, !normalizedGrantId.isEmpty {
            return pendingHubGrants.first { grant in
                let projectMatches = normalizedProjectId == nil
                    || grant.projectId.trimmingCharacters(in: .whitespacesAndNewlines) == normalizedProjectId
                return projectMatches
                    && grant.grantRequestId.trimmingCharacters(in: .whitespacesAndNewlines) == normalizedGrantId
            }
        }

        guard let normalizedCapability, !normalizedCapability.isEmpty else {
            return nil
        }

        let candidates = pendingHubGrants.filter { grant in
            let projectMatches = normalizedProjectId == nil
                || grant.projectId.trimmingCharacters(in: .whitespacesAndNewlines) == normalizedProjectId
            return projectMatches
                && grant.capability.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    == normalizedCapability
        }
        return candidates.count == 1 ? candidates[0] : nil
    }

    private static func matchingRecentSupervisorSkillActivity(
        projectId: String?,
        requestId: String,
        recentActivities: [SupervisorManager.SupervisorRecentSkillActivity]
    ) -> SupervisorManager.SupervisorRecentSkillActivity? {
        let normalizedProjectId = normalizedFocusToken(projectId)
        let normalizedRequestId = normalizedFocusToken(requestId)
        guard let normalizedRequestId, !normalizedRequestId.isEmpty else {
            return nil
        }

        return recentActivities.first { item in
            let projectMatches = normalizedProjectId == nil
                || item.projectId.trimmingCharacters(in: .whitespacesAndNewlines) == normalizedProjectId
            return projectMatches
                && item.requestId.trimmingCharacters(in: .whitespacesAndNewlines) == normalizedRequestId
        }
    }
}
