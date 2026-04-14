import Foundation

enum SupervisorAuditDrillDownResolver {
    struct Context: Equatable {
        var officialSkillsStatusLine: String
        var officialSkillsTransitionLine: String
        var officialSkillsDetailLine: String
        var officialSkillsTopBlockerSummaries: [AXOfficialSkillBlockerSummaryItem] = []
        var builtinGovernedSkills: [AXBuiltinGovernedSkillSummary] = []
        var managedSkillsStatusLine: String = ""
        var eventLoopStatusLine: String
        var pendingHubGrants: [SupervisorManager.SupervisorPendingGrant]
        var pendingSupervisorSkillApprovals: [SupervisorManager.SupervisorPendingSkillApproval]
        var candidateReviews: [HubIPCClient.SupervisorCandidateReviewItem] = []
        var candidateReviewProjectNamesByID: [String: String] = [:]
        var recentSupervisorSkillActivities: [SupervisorManager.SupervisorRecentSkillActivity]
        var recentSupervisorEventLoopActivities: [SupervisorManager.SupervisorEventLoopActivity]
    }

    typealias FullRecordLoader = (_ projectId: String, _ projectName: String, _ requestId: String) -> SupervisorSkillFullRecord?

    static func refreshFingerprint(
        context: Context
    ) -> String {
        let blockerFingerprintValue = context.officialSkillsTopBlockerSummaries
            .map(Self.blockerFingerprint)
            .joined(separator: "||")

        let builtinSkillsFingerprintValue = context.builtinGovernedSkills
            .map(Self.builtinSkillFingerprint)
            .joined(separator: "||")

        let grantFingerprintValue = context.pendingHubGrants
            .map(Self.grantFingerprint)
            .joined(separator: "||")

        let approvalFingerprintValue = context.pendingSupervisorSkillApprovals
            .map(Self.approvalFingerprint)
            .joined(separator: "||")

        let candidateReviewFingerprintValue = context.candidateReviews
            .map(Self.candidateReviewFingerprint)
            .joined(separator: "||")

        let skillActivityFingerprintValue = context.recentSupervisorSkillActivities
            .map(Self.skillActivityFingerprint)
            .joined(separator: "||")

        let eventLoopFingerprintValue = context.recentSupervisorEventLoopActivities
            .map(Self.eventLoopFingerprint)
            .joined(separator: "||")

        let components = [
            context.officialSkillsStatusLine,
            context.officialSkillsTransitionLine,
            context.officialSkillsDetailLine,
            context.managedSkillsStatusLine,
            context.eventLoopStatusLine,
            blockerFingerprintValue,
            builtinSkillsFingerprintValue,
            grantFingerprintValue,
            approvalFingerprintValue,
            candidateReviewFingerprintValue,
            skillActivityFingerprintValue,
            eventLoopFingerprintValue
        ]

        return components.joined(separator: "\n--\n")
    }

    static func selectionForOfficialSkillsChannel(
        context: Context
    ) -> SupervisorAuditDrillDownSelection {
        .officialSkillsChannel(
            statusLine: context.officialSkillsStatusLine,
            transitionLine: context.officialSkillsTransitionLine,
            detailLine: context.officialSkillsDetailLine,
            blockerSummaries: context.officialSkillsTopBlockerSummaries,
            eventLoopStatusLine: context.eventLoopStatusLine
        )
    }

    static func selection(
        for item: SupervisorManager.SupervisorPendingGrant,
        recentSkillActivities: [SupervisorManager.SupervisorRecentSkillActivity] = []
    ) -> SupervisorAuditDrillDownSelection {
        let requestId = normalizedScalar(item.requestId)
        let relatedSkillActivity: SupervisorManager.SupervisorRecentSkillActivity?
        if let requestId {
            relatedSkillActivity = SupervisorFocusPresentation.matchingRecentSkillActivity(
                projectId: normalizedScalar(item.projectId),
                requestId: requestId,
                recentActivities: recentSkillActivities
            )
        } else {
            relatedSkillActivity = nil
        }

        return .pendingHubGrant(
            item,
            relatedSkillActivity: relatedSkillActivity
        )
    }

    static func selection(
        for item: SupervisorManager.SupervisorPendingSkillApproval
    ) -> SupervisorAuditDrillDownSelection {
        .pendingSkillApproval(item)
    }

    static func selection(
        for item: HubIPCClient.SupervisorCandidateReviewItem,
        projectNamesByID: [String: String]
    ) -> SupervisorAuditDrillDownSelection {
        .candidateReview(item, projectNamesByID: projectNamesByID)
    }

    static func selection(
        for item: SupervisorManager.SupervisorRecentSkillActivity,
        loadFullRecord: FullRecordLoader
    ) -> SupervisorAuditDrillDownSelection {
        let fullRecord = loadFullRecord(item.projectId, item.projectName, item.requestId)
        return .recentSkillActivity(item, fullRecord: fullRecord)
    }

    static func selection(
        for item: SupervisorManager.SupervisorEventLoopActivity,
        recentSkillActivities: [SupervisorManager.SupervisorRecentSkillActivity],
        loadFullRecord: FullRecordLoader
    ) -> SupervisorAuditDrillDownSelection {
        let requestId = SupervisorEventLoopActionPresentation.requestId(for: item)
        let relatedSkillActivity = requestId.flatMap {
            SupervisorFocusPresentation.matchingRecentSkillActivity(
                projectId: normalizedScalar(item.projectId),
                requestId: $0,
                recentActivities: recentSkillActivities
            )
        }

        let fullRecord: SupervisorSkillFullRecord?
        if let requestId,
           let resolvedProjectId = normalizedScalar(relatedSkillActivity?.projectId ?? item.projectId) {
            let resolvedProjectName = normalizedScalar(relatedSkillActivity?.projectName ?? item.projectName) ?? resolvedProjectId
            fullRecord = loadFullRecord(resolvedProjectId, resolvedProjectName, requestId)
        } else {
            fullRecord = nil
        }

        return .eventLoop(
            item,
            relatedSkillActivity: relatedSkillActivity,
            fullRecord: fullRecord
        )
    }

    static func selection(
        for item: SupervisorInfrastructureFeedPresentation.Item,
        context: Context,
        loadFullRecord: FullRecordLoader
    ) -> SupervisorAuditDrillDownSelection? {
        switch item.kind {
        case .officialSkillsChannel:
            return selectionForOfficialSkillsChannel(context: context)
        case .xtBuiltinGovernedSkills:
            return .xtBuiltinGovernedSkills(
                items: context.builtinGovernedSkills,
                managedStatusLine: context.managedSkillsStatusLine
            )
        case .historicalProjectBoundaryRepair:
            return nil
        case .memoryAssembly:
            return nil
        case .pendingHubGrant:
            guard let grant = context.pendingHubGrants.first else { return nil }
            return selection(
                for: grant,
                recentSkillActivities: context.recentSupervisorSkillActivities
            )
        case .pendingSkillApproval:
            guard let approval = context.pendingSupervisorSkillApprovals.first else { return nil }
            return selection(for: approval)
        case .candidateReview:
            let candidateRequestID = candidateReviewRequestID(fromInfrastructureItemID: item.id)
            guard let candidate = context.candidateReviews.first(where: {
                let requestId = normalizedScalar($0.requestId)
                let reviewId = normalizedScalar($0.reviewId)
                return requestId == candidateRequestID || reviewId == candidateRequestID
            }) ?? context.candidateReviews.first else {
                return nil
            }
            return selection(
                for: candidate,
                projectNamesByID: context.candidateReviewProjectNamesByID
            )
        case .eventLoop:
            let activityID = eventLoopActivityID(fromInfrastructureItemID: item.id)
            guard let activity = context.recentSupervisorEventLoopActivities.first(where: { $0.id == activityID }) else {
                return nil
            }
            return selection(
                for: activity,
                recentSkillActivities: context.recentSupervisorSkillActivities,
                loadFullRecord: loadFullRecord
            )
        }
    }

    private static func eventLoopActivityID(fromInfrastructureItemID itemID: String) -> String {
        let prefix = "event-loop-"
        guard itemID.hasPrefix(prefix) else { return itemID }
        return String(itemID.dropFirst(prefix.count))
    }

    private static func candidateReviewRequestID(fromInfrastructureItemID itemID: String) -> String {
        let prefix = "candidate-review-"
        guard itemID.hasPrefix(prefix) else { return itemID }
        return String(itemID.dropFirst(prefix.count))
    }

    private static func blockerFingerprint(
        _ item: AXOfficialSkillBlockerSummaryItem
    ) -> String {
        [
            item.id,
            item.stateLabel,
            item.summaryLine,
            item.timelineLine
        ].joined(separator: "|")
    }

    private static func builtinSkillFingerprint(
        _ item: AXBuiltinGovernedSkillSummary
    ) -> String {
        [
            item.skillID,
            item.displayName,
            item.summary,
            item.capabilitiesRequired.joined(separator: ","),
            item.sideEffectClass,
            item.riskLevel,
            item.policyScope
        ].joined(separator: "|")
    }

    private static func grantFingerprint(
        _ grant: SupervisorManager.SupervisorPendingGrant
    ) -> String {
        [
            grant.id,
            grant.grantRequestId,
            grant.requestId,
            grant.nextAction,
            grant.reason
        ].joined(separator: "|")
    }

    private static func approvalFingerprint(
        _ approval: SupervisorManager.SupervisorPendingSkillApproval
    ) -> String {
        [
            approval.id,
            approval.requestId,
            approval.tool?.rawValue ?? approval.toolName,
            approval.reason,
            approval.toolSummary
        ].joined(separator: "|")
    }

    private static func candidateReviewFingerprint(
        _ item: HubIPCClient.SupervisorCandidateReviewItem
    ) -> String {
        [
            item.id,
            item.requestId,
            item.reviewId,
            item.reviewState,
            item.pendingChangeId,
            item.pendingChangeStatus,
            item.summaryLine
        ].joined(separator: "|")
    }

    private static func skillActivityFingerprint(
        _ activity: SupervisorManager.SupervisorRecentSkillActivity
    ) -> String {
        [
            activity.projectId,
            activity.requestId,
            activity.status,
            activity.resultSummary,
            activity.denyCode,
            activity.grantRequestId,
            activity.grantId,
            activity.resultEvidenceRef,
            String(activity.record.updatedAtMs)
        ].joined(separator: "|")
    }

    private static func eventLoopFingerprint(
        _ activity: SupervisorManager.SupervisorEventLoopActivity
    ) -> String {
        [
            activity.id,
            activity.status,
            activity.reasonCode,
            activity.dedupeKey,
            activity.resultSummary,
            String(activity.updatedAt)
        ].joined(separator: "|")
    }

    private static func normalizedScalar(_ raw: String?) -> String? {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
