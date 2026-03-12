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
    var status: SupervisorProjectDrillDownStatus
    var requestedScope: SupervisorProjectDrillDownScope
    var grantedScope: SupervisorProjectDrillDownScope?
    var capsule: SupervisorPortfolioProjectCard?
    var recentMessages: [AXRecentContextMessage]
    var denyReason: String?
    var refs: [String]

    static func denied(
        projectId: String,
        projectName: String,
        status: SupervisorProjectDrillDownStatus,
        requestedScope: SupervisorProjectDrillDownScope,
        denyReason: String,
        updatedAt: Double = Date().timeIntervalSince1970
    ) -> SupervisorProjectDrillDownSnapshot {
        SupervisorProjectDrillDownSnapshot(
            updatedAt: updatedAt,
            projectId: projectId,
            projectName: projectName,
            status: status,
            requestedScope: requestedScope,
            grantedScope: nil,
            capsule: nil,
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
        requestedScope: SupervisorProjectDrillDownScope
    ) -> [String] {
        var refs = [
            ctx.memoryJSONURL.path,
            hubSnapshotRef(projectId: projectId),
            hubCapsuleSummaryRef(projectId: projectId)
        ]

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
