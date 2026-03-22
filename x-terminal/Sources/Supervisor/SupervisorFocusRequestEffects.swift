import Foundation

enum SupervisorFocusRequestEffects {
    struct Context: Equatable {
        var pendingHubGrants: [SupervisorManager.SupervisorPendingGrant]
        var pendingSupervisorSkillApprovals: [SupervisorManager.SupervisorPendingSkillApproval]
        var recentSupervisorSkillActivities: [SupervisorManager.SupervisorRecentSkillActivity]
    }

    struct Highlights: Equatable {
        var pendingHubGrantAnchor: String?
        var pendingSupervisorSkillApprovalAnchor: String?
        var recentSkillActivityRequestId: String?
    }

    enum Refresh: Equatable {
        case pendingHubGrants
        case pendingSupervisorSkillApprovals
        case recentSupervisorSkillActivities
    }

    struct FallbackSkillRecord: Equatable {
        var projectName: String
        var record: SupervisorSkillFullRecord
    }

    struct Plan: Equatable {
        var selectedProjectId: String?
        var boardAnchorID: String
        var rowAnchorID: String?
        var highlights: Highlights
        var auditDrillDown: SupervisorAuditDrillDownSelection?
        var refresh: Refresh?
    }

    typealias RecentSkillRecordLoader =
        (_ projectId: String, _ projectName: String, _ requestId: String) -> SupervisorSkillFullRecord?
    typealias FallbackSkillRecordLoader =
        (_ projectId: String, _ requestId: String) -> FallbackSkillRecord?

    static func resolve(
        request: AXSupervisorFocusRequest,
        context: Context,
        loadRecentSkillRecord: RecentSkillRecordLoader,
        loadFallbackSkillRecord: FallbackSkillRecordLoader
    ) -> Plan {
        switch request.subject {
        case let .board(anchorID):
            return board(
                request: request,
                anchorID: anchorID
            )
        case let .grant(grantRequestId, capability):
            return grant(
                request: request,
                grantRequestId: grantRequestId,
                capability: capability,
                pendingHubGrants: context.pendingHubGrants
            )
        case let .approval(requestId):
            return approval(
                request: request,
                requestId: requestId,
                pendingApprovals: context.pendingSupervisorSkillApprovals
            )
        case let .skillRecord(requestId):
            return skillRecord(
                request: request,
                requestId: requestId,
                recentActivities: context.recentSupervisorSkillActivities,
                loadRecentSkillRecord: loadRecentSkillRecord,
                loadFallbackSkillRecord: loadFallbackSkillRecord
            )
        }
    }

    static func board(
        request: AXSupervisorFocusRequest,
        anchorID: String
    ) -> Plan {
        let resolution = SupervisorFocusPresentation.resolveBoard(
            request: request,
            anchorID: anchorID
        )

        return Plan(
            selectedProjectId: resolution.selectedProjectId,
            boardAnchorID: resolution.boardAnchorID,
            rowAnchorID: nil,
            highlights: Highlights(
                pendingHubGrantAnchor: nil,
                pendingSupervisorSkillApprovalAnchor: nil,
                recentSkillActivityRequestId: nil
            ),
            auditDrillDown: nil,
            refresh: nil
        )
    }

    static func approval(
        request: AXSupervisorFocusRequest,
        requestId: String,
        pendingApprovals: [SupervisorManager.SupervisorPendingSkillApproval]
    ) -> Plan {
        let resolution = SupervisorFocusPresentation.resolveApproval(
            request: request,
            requestId: requestId,
            pendingApprovals: pendingApprovals
        )

        return Plan(
            selectedProjectId: resolution.selectedProjectId,
            boardAnchorID: resolution.boardAnchorID,
            rowAnchorID: resolution.matchedApproval.map(
                SupervisorFocusPresentation.pendingSupervisorSkillApprovalRowAnchor
            ),
            highlights: Highlights(
                pendingHubGrantAnchor: nil,
                pendingSupervisorSkillApprovalAnchor: resolution.highlightedApprovalAnchor,
                recentSkillActivityRequestId: nil
            ),
            auditDrillDown: nil,
            refresh: resolution.matchedApproval == nil && resolution.refreshPendingApprovals
                ? .pendingSupervisorSkillApprovals
                : nil
        )
    }

    static func grant(
        request: AXSupervisorFocusRequest,
        grantRequestId: String?,
        capability: String?,
        pendingHubGrants: [SupervisorManager.SupervisorPendingGrant]
    ) -> Plan {
        let resolution = SupervisorFocusPresentation.resolveGrant(
            request: request,
            grantRequestId: grantRequestId,
            capability: capability,
            pendingHubGrants: pendingHubGrants
        )

        return Plan(
            selectedProjectId: resolution.selectedProjectId,
            boardAnchorID: resolution.boardAnchorID,
            rowAnchorID: resolution.matchedGrant.map(
                SupervisorFocusPresentation.pendingHubGrantRowAnchor
            ),
            highlights: Highlights(
                pendingHubGrantAnchor: resolution.highlightedGrantAnchor,
                pendingSupervisorSkillApprovalAnchor: nil,
                recentSkillActivityRequestId: nil
            ),
            auditDrillDown: nil,
            refresh: resolution.matchedGrant == nil && resolution.refreshPendingHubGrants
                ? .pendingHubGrants
                : nil
        )
    }

    static func skillRecord(
        request: AXSupervisorFocusRequest,
        requestId: String,
        recentActivities: [SupervisorManager.SupervisorRecentSkillActivity],
        loadRecentSkillRecord: RecentSkillRecordLoader,
        loadFallbackSkillRecord: FallbackSkillRecordLoader
    ) -> Plan {
        let resolution = SupervisorFocusPresentation.resolveSkillRecord(
            request: request,
            requestId: requestId,
            recentActivities: recentActivities
        )

        let highlights = Highlights(
            pendingHubGrantAnchor: nil,
            pendingSupervisorSkillApprovalAnchor: nil,
            recentSkillActivityRequestId: resolution.highlightedSkillActivityRequestId
        )

        let fallbackProjectId = resolution.fallbackProjectId
        let fallbackRecord = fallbackProjectId.flatMap {
            loadFallbackSkillRecord($0, resolution.fallbackRequestId)
        }

        switch SupervisorSkillRecordFocusDrillDownPresentation.resolve(
            resolution: resolution,
            fallbackProjectName: fallbackRecord?.projectName,
            fallbackRecord: fallbackRecord?.record
        ) {
        case .recentActivity(let item):
            return Plan(
                selectedProjectId: resolution.selectedProjectId,
                boardAnchorID: resolution.boardAnchorID,
                rowAnchorID: SupervisorFocusPresentation.recentSkillActivityRowAnchor(item),
                highlights: highlights,
                auditDrillDown: SupervisorAuditDrillDownResolver.selection(
                    for: item,
                    loadFullRecord: loadRecentSkillRecord
                ),
                refresh: nil
            )
        case .fallbackRecord(let projectId, let projectName, let record):
            return Plan(
                selectedProjectId: resolution.selectedProjectId,
                boardAnchorID: resolution.boardAnchorID,
                rowAnchorID: nil,
                highlights: highlights,
                auditDrillDown: .fullRecordFallback(
                    projectId: projectId,
                    projectName: projectName,
                    record: record
                ),
                refresh: nil
            )
        case .refreshNeeded:
            return Plan(
                selectedProjectId: resolution.selectedProjectId,
                boardAnchorID: resolution.boardAnchorID,
                rowAnchorID: nil,
                highlights: highlights,
                auditDrillDown: nil,
                refresh: .recentSupervisorSkillActivities
            )
        case .noMatch:
            return Plan(
                selectedProjectId: resolution.selectedProjectId,
                boardAnchorID: resolution.boardAnchorID,
                rowAnchorID: nil,
                highlights: highlights,
                auditDrillDown: nil,
                refresh: nil
            )
        }
    }
}
