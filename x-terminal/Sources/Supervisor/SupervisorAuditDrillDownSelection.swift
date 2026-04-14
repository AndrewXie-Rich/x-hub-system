import Foundation

struct SupervisorAuditDrillDownSelection: Equatable, Identifiable {
    enum Source: Equatable {
        case officialSkillsChannel
        case xtBuiltinGovernedSkills([AXBuiltinGovernedSkillSummary])
        case candidateReview(HubIPCClient.SupervisorCandidateReviewItem)
        case pendingGrant(SupervisorManager.SupervisorPendingGrant)
        case pendingSkillApproval(SupervisorManager.SupervisorPendingSkillApproval)
        case recentSkillActivity(SupervisorManager.SupervisorRecentSkillActivity)
        case eventLoop(SupervisorManager.SupervisorEventLoopActivity)
        case fullRecordFallback(projectId: String, projectName: String, record: SupervisorSkillFullRecord)
    }

    let source: Source
    let presentation: SupervisorAuditDrillDownPresentation
    let fullRecord: SupervisorSkillFullRecord?

    var id: String { presentation.id }

    static func officialSkillsChannel(
        statusLine: String,
        transitionLine: String,
        detailLine: String,
        blockerSummaries: [AXOfficialSkillBlockerSummaryItem] = [],
        eventLoopStatusLine: String
    ) -> SupervisorAuditDrillDownSelection {
        SupervisorAuditDrillDownSelection(
            source: .officialSkillsChannel,
            presentation: .officialSkillsChannel(
                statusLine: statusLine,
                transitionLine: transitionLine,
                detailLine: detailLine,
                blockerSummaries: blockerSummaries,
                eventLoopStatusLine: eventLoopStatusLine
            ),
            fullRecord: nil
        )
    }

    static func pendingHubGrant(
        _ grant: SupervisorManager.SupervisorPendingGrant,
        relatedSkillActivity: SupervisorManager.SupervisorRecentSkillActivity? = nil
    ) -> SupervisorAuditDrillDownSelection {
        SupervisorAuditDrillDownSelection(
            source: .pendingGrant(grant),
            presentation: .pendingHubGrant(
                grant,
                relatedSkillActivity: relatedSkillActivity
            ),
            fullRecord: nil
        )
    }

    static func candidateReview(
        _ item: HubIPCClient.SupervisorCandidateReviewItem,
        projectNamesByID: [String: String]
    ) -> SupervisorAuditDrillDownSelection {
        SupervisorAuditDrillDownSelection(
            source: .candidateReview(item),
            presentation: .candidateReview(item, projectNamesByID: projectNamesByID),
            fullRecord: nil
        )
    }

    static func xtBuiltinGovernedSkills(
        items: [AXBuiltinGovernedSkillSummary],
        managedStatusLine: String
    ) -> SupervisorAuditDrillDownSelection {
        SupervisorAuditDrillDownSelection(
            source: .xtBuiltinGovernedSkills(items),
            presentation: .xtBuiltinGovernedSkills(
                items: items,
                managedStatusLine: managedStatusLine
            ),
            fullRecord: nil
        )
    }

    static func pendingSkillApproval(
        _ approval: SupervisorManager.SupervisorPendingSkillApproval
    ) -> SupervisorAuditDrillDownSelection {
        SupervisorAuditDrillDownSelection(
            source: .pendingSkillApproval(approval),
            presentation: .pendingSkillApproval(approval),
            fullRecord: nil
        )
    }

    static func recentSkillActivity(
        _ item: SupervisorManager.SupervisorRecentSkillActivity,
        fullRecord: SupervisorSkillFullRecord?
    ) -> SupervisorAuditDrillDownSelection {
        SupervisorAuditDrillDownSelection(
            source: .recentSkillActivity(item),
            presentation: .recentSkillActivity(item, fullRecord: fullRecord),
            fullRecord: fullRecord
        )
    }

    static func fullRecordFallback(
        projectId: String,
        projectName: String,
        record: SupervisorSkillFullRecord
    ) -> SupervisorAuditDrillDownSelection {
        SupervisorAuditDrillDownSelection(
            source: .fullRecordFallback(
                projectId: projectId,
                projectName: projectName,
                record: record
            ),
            presentation: .fullRecordFallback(
                projectId: projectId,
                projectName: projectName,
                record: record
            ),
            fullRecord: record
        )
    }

    static func eventLoop(
        _ item: SupervisorManager.SupervisorEventLoopActivity,
        relatedSkillActivity: SupervisorManager.SupervisorRecentSkillActivity?,
        fullRecord: SupervisorSkillFullRecord?
    ) -> SupervisorAuditDrillDownSelection {
        SupervisorAuditDrillDownSelection(
            source: .eventLoop(item),
            presentation: .eventLoopActivity(
                item,
                relatedSkillActivity: relatedSkillActivity,
                fullRecord: fullRecord
            ),
            fullRecord: fullRecord
        )
    }
}
