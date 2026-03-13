import Foundation

struct SupervisorProjectWorkflowSnapshot: Codable, Equatable, Sendable {
    static let schemaVersion = "xt.supervisor_project_workflow.v1"

    var schemaVersion: String
    var projectId: String
    var projectName: String
    var updatedAtMs: Int64
    var activeJob: SupervisorJobRecord?
    var activePlan: SupervisorPlanRecord?
    var activeSkillCall: SupervisorSkillCallRecord?
    var auditRef: String

    init(
        projectId: String,
        projectName: String,
        updatedAtMs: Int64,
        activeJob: SupervisorJobRecord?,
        activePlan: SupervisorPlanRecord?,
        activeSkillCall: SupervisorSkillCallRecord?,
        auditRef: String
    ) {
        self.schemaVersion = Self.schemaVersion
        self.projectId = projectId
        self.projectName = projectName
        self.updatedAtMs = updatedAtMs
        self.activeJob = activeJob
        self.activePlan = activePlan
        self.activeSkillCall = activeSkillCall
        self.auditRef = auditRef
    }
}

enum SupervisorProjectWorkflowCanonicalSync {
    static let keyPrefix = "xterminal.project.supervisor_workflow"
    private static let maxScalarChars = 1_600
    private static let maxStepItems = 8
    private static let maxStepTitleChars = 180

    static func snapshot(
        projectId: String,
        projectName: String,
        jobSnapshot: SupervisorProjectJobSnapshot,
        planSnapshot: SupervisorProjectPlanSnapshot,
        skillCallSnapshot: SupervisorProjectSkillCallSnapshot
    ) -> SupervisorProjectWorkflowSnapshot? {
        let activeJob = jobSnapshot.jobs.first
        guard let activeJob else { return nil }
        let activePlan = planSnapshot.plans.first(where: { $0.planId == activeJob.activePlanId && !$0.planId.isEmpty })
            ?? planSnapshot.plans.first(where: { $0.jobId == activeJob.jobId })
        let activeSkillCall = skillCallSnapshot.calls.first(where: { $0.jobId == activeJob.jobId })
        let updatedAtMs = max(
            activeJob.updatedAtMs,
            activePlan?.updatedAtMs ?? 0,
            activeSkillCall?.updatedAtMs ?? 0,
            jobSnapshot.updatedAtMs,
            planSnapshot.updatedAtMs,
            skillCallSnapshot.updatedAtMs
        )
        return SupervisorProjectWorkflowSnapshot(
            projectId: projectId,
            projectName: projectName,
            updatedAtMs: updatedAtMs,
            activeJob: activeJob,
            activePlan: activePlan,
            activeSkillCall: activeSkillCall,
            auditRef: "supervisor_project_workflow:\(projectId):\(updatedAtMs)"
        )
    }

    static func items(snapshot: SupervisorProjectWorkflowSnapshot) -> [XTProjectCanonicalMemoryItem] {
        let stepsDigest = snapshot.activePlan.map(normalizedStepsDigest) ?? ""
        let summaryJSON = summaryJSON(snapshot)
        let pairs: [(String, String)] = [
            ("schema_version", normalizedScalar(snapshot.schemaVersion)),
            ("project_id", normalizedScalar(snapshot.projectId)),
            ("project_name", normalizedScalar(snapshot.projectName)),
            ("updated_at_ms", String(max(Int64(0), snapshot.updatedAtMs))),
            ("active_job_id", normalizedScalar(snapshot.activeJob?.jobId ?? "")),
            ("active_job_goal", normalizedScalar(snapshot.activeJob?.goal ?? "")),
            ("active_job_status", normalizedScalar(snapshot.activeJob?.status.rawValue ?? "")),
            ("active_job_priority", normalizedScalar(snapshot.activeJob?.priority.rawValue ?? "")),
            ("active_job_owner", normalizedScalar(snapshot.activeJob?.currentOwner ?? "")),
            ("active_plan_id", normalizedScalar(snapshot.activePlan?.planId ?? snapshot.activeJob?.activePlanId ?? "")),
            ("active_plan_status", normalizedScalar(snapshot.activePlan?.status.rawValue ?? "")),
            ("active_plan_step_count", String(snapshot.activePlan?.steps.count ?? 0)),
            ("active_plan_steps_digest", stepsDigest),
            ("active_skill_request_id", normalizedScalar(snapshot.activeSkillCall?.requestId ?? "")),
            ("active_skill_step_id", normalizedScalar(snapshot.activeSkillCall?.stepId ?? "")),
            ("active_skill_id", normalizedScalar(snapshot.activeSkillCall?.skillId ?? "")),
            ("active_skill_tool_name", normalizedScalar(snapshot.activeSkillCall?.toolName ?? "")),
            ("active_skill_required_capability", normalizedScalar(snapshot.activeSkillCall?.requiredCapability ?? "")),
            ("active_skill_grant_request_id", normalizedScalar(snapshot.activeSkillCall?.grantRequestId ?? "")),
            ("active_skill_grant_id", normalizedScalar(snapshot.activeSkillCall?.grantId ?? "")),
            ("active_skill_status", normalizedScalar(snapshot.activeSkillCall?.status.rawValue ?? "")),
            ("active_skill_result_summary", normalizedScalar(snapshot.activeSkillCall?.resultSummary ?? "")),
            ("last_skill_status", normalizedScalar(snapshot.activeSkillCall?.status.rawValue ?? "")),
            ("last_skill_result_ref", normalizedScalar(snapshot.activeSkillCall?.resultEvidenceRef ?? "")),
            ("audit_ref", normalizedScalar(snapshot.auditRef)),
            ("summary_json", summaryJSON)
        ]

        return pairs.compactMap { suffix, rawValue in
            let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { return nil }
            return XTProjectCanonicalMemoryItem(key: "\(keyPrefix).\(suffix)", value: value)
        }
    }

    private static func normalizedScalar(_ raw: String) -> String {
        let trimmed = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        guard trimmed.count > maxScalarChars else { return trimmed }
        let end = trimmed.index(trimmed.startIndex, offsetBy: maxScalarChars)
        return String(trimmed[..<end]) + "..."
    }

    private static func normalizedStepsDigest(_ plan: SupervisorPlanRecord) -> String {
        let lines = plan.steps
            .sorted { lhs, rhs in
                if lhs.orderIndex != rhs.orderIndex {
                    return lhs.orderIndex < rhs.orderIndex
                }
                return lhs.stepId < rhs.stepId
            }
            .prefix(maxStepItems)
            .map { step in
                let title = normalizedScalar(String(step.title.prefix(maxStepTitleChars)))
                return "\(step.orderIndex + 1). \(step.stepId) | \(step.status.rawValue) | \(step.kind.rawValue) | \(title)"
            }
        return lines.joined(separator: "\n")
    }

    private static func summaryJSON(_ snapshot: SupervisorProjectWorkflowSnapshot) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(snapshot),
              let text = String(data: data, encoding: .utf8) else {
            return ""
        }
        return text
    }
}
