import Foundation

enum SupervisorProjectDrillDownStatus: String, Codable, Sendable {
    case allowed
    case deniedProjectInvisible = "denied_project_invisible"
    case deniedScope = "denied_scope"
    case projectNotFound = "project_not_found"
}

struct SupervisorProjectDrillDownSnapshot: Equatable, Codable, Sendable {
    var updatedAt: Double
    var projectId: String
    var projectName: String
    var openedReason: String
    var status: SupervisorProjectDrillDownStatus
    var requestedScope: SupervisorProjectDrillDownScope
    var grantedScope: SupervisorProjectDrillDownScope?
    var capsule: SupervisorPortfolioProjectCard?
    var specCapsule: SupervisorProjectSpecCapsule?
    var decisionRails: SupervisorProjectDecisionRails?
    var workflow: SupervisorProjectWorkflowSnapshot?
    var recentMessages: [AXRecentContextMessage]
    var denyReason: String?
    var refs: [String]

    static func denied(
        projectId: String,
        projectName: String,
        openedReason: String = "explicit_portfolio_drilldown",
        status: SupervisorProjectDrillDownStatus,
        requestedScope: SupervisorProjectDrillDownScope,
        denyReason: String,
        updatedAt: Double = Date().timeIntervalSince1970
    ) -> SupervisorProjectDrillDownSnapshot {
        SupervisorProjectDrillDownSnapshot(
            updatedAt: updatedAt,
            projectId: projectId,
            projectName: projectName,
            openedReason: openedReason,
            status: status,
            requestedScope: requestedScope,
            grantedScope: nil,
            capsule: nil,
            specCapsule: nil,
            decisionRails: nil,
            workflow: nil,
            recentMessages: [],
            denyReason: denyReason,
            refs: []
        )
    }
}

enum SupervisorProjectDrillDownRefsBuilder {
    static func build(
        projectId: String,
        ctx: AXProjectContext,
        requestedScope: SupervisorProjectDrillDownScope,
        specCapsule: SupervisorProjectSpecCapsule?,
        decisionRails: SupervisorProjectDecisionRails?,
        workflow: SupervisorProjectWorkflowSnapshot?
    ) -> [String] {
        var refs = [
            ctx.memoryJSONURL.path,
            hubSnapshotRef(projectId: projectId),
            hubCapsuleSummaryRef(projectId: projectId)
        ]

        if specCapsule != nil {
            refs.append(ctx.xterminalDir.appendingPathComponent("supervisor_project_spec_capsule.json").path)
        }
        if let decisionRails {
            if !decisionRails.decisionTrack.isEmpty {
                refs.append(ctx.xterminalDir.appendingPathComponent("supervisor_decision_track.json").path)
            }
            if !decisionRails.backgroundPreferenceTrack.isEmpty {
                refs.append(ctx.xterminalDir.appendingPathComponent("supervisor_background_preference_track.json").path)
            }
            refs.append(contentsOf: decisionRails.decisionTrack.flatMap(\.evidenceRefs))
        }
        if let workflow {
            refs.append(ctx.supervisorJobsURL.path)
            refs.append(ctx.supervisorPlansURL.path)
            refs.append(ctx.supervisorSkillCallsURL.path)
            if let resultRef = workflow.activeSkillCall?.resultEvidenceRef {
                refs.append(resultRef)
            }
        }
        if let specCapsule {
            refs.append(contentsOf: specCapsule.sourceRefs)
        }

        if requestedScope == .capsulePlusRecent {
            refs.append(AXRecentContextStore.jsonURL(for: ctx).path)
            refs.append(hubProjectActionSummaryRef(projectId: projectId))
        }

        var seen = Set<String>()
        return refs.filter { ref in
            guard !ref.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
            return seen.insert(ref).inserted
        }
    }

    private static func hubSnapshotRef(projectId: String) -> String {
        "hub://project/\(projectId)/snapshot/xterminal.project.snapshot"
    }

    private static func hubCapsuleSummaryRef(projectId: String) -> String {
        "hub://project/\(projectId)/canonical/xterminal.project.capsule.summary_json"
    }

    private static func hubProjectActionSummaryRef(projectId: String) -> String {
        "hub://project/\(projectId)/canonical/xterminal.project.action.summary_json"
    }
}
