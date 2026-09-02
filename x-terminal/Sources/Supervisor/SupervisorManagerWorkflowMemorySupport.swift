import Foundation

extension SupervisorManager {
    func supervisorWorkflowState(
        project: AXProjectEntry,
        ctx: AXProjectContext,
        preferredJobId: String?,
        preferredPlanId: String?,
        preferredRequestId: String?
    ) -> (job: SupervisorJobRecord, plan: SupervisorPlanRecord?, skillCall: SupervisorSkillCallRecord?)? {
        let jobSnapshot = SupervisorProjectJobStore.load(for: ctx)
        let normalizedJobId = preferredJobId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let activeJob = jobSnapshot.jobs.first(where: { !$0.jobId.isEmpty && $0.jobId == normalizedJobId })
            ?? jobSnapshot.jobs.first
        guard let activeJob else { return nil }

        let planSnapshot = SupervisorProjectPlanStore.load(for: ctx)
        let normalizedPlanId = preferredPlanId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let activePlan = planSnapshot.plans.first(where: { !$0.planId.isEmpty && $0.planId == normalizedPlanId && $0.jobId == activeJob.jobId })
            ?? planSnapshot.plans.first(where: { $0.planId == activeJob.activePlanId && !$0.planId.isEmpty })
            ?? planSnapshot.plans.first(where: { $0.jobId == activeJob.jobId })

        let skillCallSnapshot = SupervisorProjectSkillCallStore.load(for: ctx)
        let normalizedRequestId = preferredRequestId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let activeSkillCall = skillCallSnapshot.calls.first(where: { !$0.requestId.isEmpty && $0.requestId == normalizedRequestId })
            ?? skillCallSnapshot.calls.first(where: { $0.jobId == activeJob.jobId })
            ?? skillCallSnapshot.calls.first(where: { $0.projectId == project.projectId })
        return (activeJob, activePlan, activeSkillCall)
    }

    func supervisorWorkflowMemorySlice(
        project: AXProjectEntry,
        ctx: AXProjectContext,
        preferredJobId: String?,
        preferredPlanId: String?,
        preferredRequestId: String?
    ) -> SupervisorWorkflowMemorySlice? {
        guard let state = supervisorWorkflowState(
            project: project,
            ctx: ctx,
            preferredJobId: preferredJobId,
            preferredPlanId: preferredPlanId,
            preferredRequestId: preferredRequestId
        ) else {
            return nil
        }
        let activeJob = state.job
        let activePlan = state.plan
        let activeSkillCall = state.skillCall
        let activePlanId = (activePlan?.planId ?? activeJob.activePlanId).trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedActivePlanId = activePlanId.isEmpty ? "(none)" : activePlanId
        let activeSkillSummary = activeSkillCall.map { call in
            """
active_skill_request_id: \(call.requestId)
active_skill_id: \(call.skillId)
active_skill_step_id: \(call.stepId)
active_skill_tool_name: \(call.toolName.isEmpty ? "(none)" : call.toolName)
active_skill_profile_summary: \(call.deltaApproval?.summary.isEmpty == false ? call.deltaApproval!.summary : "(none)")
active_skill_execution_readiness: \(call.readiness?.executionReadiness.isEmpty == false ? call.readiness!.executionReadiness : "(none)")
active_skill_readiness_reason: \(call.readiness?.reasonCode.isEmpty == false ? call.readiness!.reasonCode : "(none)")
active_skill_requested_profiles: \(supervisorWorkflowSkillListSummary(call.deltaApproval?.requestedProfiles ?? []))
active_skill_delta_profiles: \(supervisorWorkflowSkillListSummary(call.deltaApproval?.deltaProfiles ?? []))
active_skill_requested_capability_families: \(supervisorWorkflowSkillListSummary(call.deltaApproval?.requestedCapabilityFamilies ?? []))
active_skill_delta_capability_families: \(supervisorWorkflowSkillListSummary(call.deltaApproval?.deltaCapabilityFamilies ?? []))
active_skill_unblock_actions: \(supervisorWorkflowSkillListSummary(call.readiness?.unblockActions ?? []))
active_skill_required_capability: \(call.requiredCapability?.isEmpty == false ? call.requiredCapability! : "(none)")
active_skill_grant_request_id: \(call.grantRequestId?.isEmpty == false ? call.grantRequestId! : "(none)")
active_skill_grant_id: \(call.grantId?.isEmpty == false ? call.grantId! : "(none)")
active_skill_status: \(call.status.rawValue)
active_skill_result_ref: \(call.resultEvidenceRef?.isEmpty == false ? call.resultEvidenceRef! : "(none)")
active_skill_result_summary: \(call.resultSummary.isEmpty ? "(none)" : call.resultSummary)
"""
        } ?? """
active_skill_request_id: (none)
active_skill_id: (none)
active_skill_step_id: (none)
active_skill_tool_name: (none)
active_skill_profile_summary: (none)
active_skill_execution_readiness: (none)
active_skill_readiness_reason: (none)
active_skill_requested_profiles: (none)
active_skill_delta_profiles: (none)
active_skill_requested_capability_families: (none)
active_skill_delta_capability_families: (none)
active_skill_unblock_actions: (none)
active_skill_required_capability: (none)
active_skill_grant_request_id: (none)
active_skill_grant_id: (none)
active_skill_status: (none)
active_skill_result_ref: (none)
active_skill_result_summary: (none)
"""

        let canonical = """
[supervisor_workflow]
project: \(project.displayName) (\(project.projectId))
active_job_id: \(activeJob.jobId)
active_job_goal: \(activeJob.goal)
active_job_priority: \(activeJob.priority.rawValue)
active_job_status: \(activeJob.status.rawValue)
active_plan_id: \(resolvedActivePlanId)
active_plan_status: \(activePlan?.status.rawValue ?? "(none)")
active_plan_steps:
\(activePlan.map(workflowPlanStepsDigest) ?? "(none)")
\(activeSkillSummary)
[/supervisor_workflow]
"""
        let observation = "supervisor_workflow_active: project=\(project.projectId) job=\(activeJob.jobId) status=\(activeJob.status.rawValue) plan=\(activePlan?.planId ?? "(none)") steps=\(activePlan?.steps.count ?? 0) skill=\(activeSkillCall?.skillId ?? "(none)") skill_status=\(activeSkillCall?.status.rawValue ?? "(none)")"
        let workingSet = """
job \(activeJob.jobId) goal=\(activeJob.goal)
status=\(activeJob.status.rawValue) priority=\(activeJob.priority.rawValue) owner=\(activeJob.currentOwner)
plan=\(activePlan?.planId ?? "(none)") plan_status=\(activePlan?.status.rawValue ?? "(none)")
steps:
\(activePlan.map(workflowPlanStepsDigest) ?? "(none)")
active_skill:
\(activeSkillCall.map { call in
    "request_id=\(call.requestId) skill=\(call.skillId) status=\(call.status.rawValue) tool=\(call.toolName.isEmpty ? "(none)" : call.toolName) readiness=\(call.readiness?.executionReadiness.isEmpty == false ? call.readiness!.executionReadiness : "(none)") requested_profiles=\(supervisorWorkflowSkillListSummary(call.deltaApproval?.requestedProfiles ?? [])) delta_profiles=\(supervisorWorkflowSkillListSummary(call.deltaApproval?.deltaProfiles ?? [])) requested_families=\(supervisorWorkflowSkillListSummary(call.deltaApproval?.requestedCapabilityFamilies ?? [])) delta_families=\(supervisorWorkflowSkillListSummary(call.deltaApproval?.deltaCapabilityFamilies ?? [])) unblock_actions=\(supervisorWorkflowSkillListSummary(call.readiness?.unblockActions ?? [])) capability=\(call.requiredCapability?.isEmpty == false ? call.requiredCapability! : "(none)") grant_request_id=\(call.grantRequestId?.isEmpty == false ? call.grantRequestId! : "(none)") grant_id=\(call.grantId?.isEmpty == false ? call.grantId! : "(none)") result_ref=\(call.resultEvidenceRef?.isEmpty == false ? call.resultEvidenceRef! : "(none)")\nsummary=\(call.resultSummary.isEmpty ? "(none)" : call.resultSummary)"
} ?? "(none)")
"""
        return SupervisorWorkflowMemorySlice(
            canonical: canonical,
            observation: observation,
            workingSet: workingSet
        )
    }

    func supervisorWorkflowSkillListSummary(
        _ values: [String]
    ) -> String {
        let normalized = values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return normalized.isEmpty ? "(none)" : normalized.joined(separator: ", ")
    }

    func workflowPlanFilteredStepsDigest(
        _ plan: SupervisorPlanRecord,
        statuses: Set<SupervisorPlanStepStatus>,
        excludingStepId: String? = nil,
        limit: Int = 4
    ) -> String {
        let excluded = excludingStepId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let rows = plan.steps
            .sorted { lhs, rhs in
                if lhs.orderIndex != rhs.orderIndex {
                    return lhs.orderIndex < rhs.orderIndex
                }
                return lhs.stepId < rhs.stepId
            }
            .filter { step in
                statuses.contains(step.status) &&
                    (excluded.isEmpty || step.stepId != excluded)
            }
            .prefix(limit)
            .map { step in
                let skill = step.skillId.trimmingCharacters(in: .whitespacesAndNewlines)
                let suffix = skill.isEmpty ? "" : " skill=\(skill)"
                return "\(step.orderIndex + 1). \(step.stepId) | \(step.status.rawValue) | \(step.kind.rawValue) | \(capped(step.title, maxChars: 120))\(suffix)"
            }
        return rows.isEmpty ? "(none)" : rows.joined(separator: "\n")
    }

    func supervisorEventLoopWorkflowContext(
        project: AXProjectEntry,
        record: SupervisorSkillCallRecord
    ) -> String {
        supervisorEventLoopWorkflowContext(
            project: project,
            preferredJobId: record.jobId,
            preferredPlanId: record.planId,
            preferredRequestId: record.requestId,
            excludingStepId: record.stepId
        )
    }

    func supervisorEventLoopWorkflowContext(
        project: AXProjectEntry,
        preferredJobId: String?,
        preferredPlanId: String?,
        preferredRequestId: String?,
        excludingStepId: String?
    ) -> String {
        guard let ctx = appModel?.projectContext(for: project.projectId),
              let state = supervisorWorkflowState(
                project: project,
                ctx: ctx,
                preferredJobId: preferredJobId,
                preferredPlanId: preferredPlanId,
                preferredRequestId: preferredRequestId
              ) else {
            return ""
        }

        let nextPendingSteps = state.plan.map {
            workflowPlanFilteredStepsDigest(
                $0,
                statuses: [.pending],
                excludingStepId: excludingStepId
            )
        } ?? "(none)"
        let attentionSteps = state.plan.map {
            workflowPlanFilteredStepsDigest(
                $0,
                statuses: [.running, .blocked, .awaitingAuthorization],
                excludingStepId: nil
            )
        } ?? "(none)"
        let planSteps = state.plan.map(workflowPlanStepsDigest) ?? "(none)"
        let planStatus = state.plan?.status.rawValue ?? "(none)"
        let jobGoal = capped(state.job.goal, maxChars: 220)

        return """
workflow_focus:
active_job_goal=\(jobGoal.isEmpty ? "(none)" : jobGoal)
active_job_status=\(state.job.status.rawValue)
active_plan_id=\(state.plan?.planId ?? "(none)")
active_plan_status=\(planStatus)
active_plan_steps:
\(planSteps)
next_pending_steps:
\(nextPendingSteps)
attention_steps:
\(attentionSteps)
"""
    }

    func workflowPlanStepsDigest(_ plan: SupervisorPlanRecord) -> String {
        let rows = plan.steps
            .sorted { lhs, rhs in
                if lhs.orderIndex != rhs.orderIndex {
                    return lhs.orderIndex < rhs.orderIndex
                }
                return lhs.stepId < rhs.stepId
            }
            .prefix(8)
            .map { step in
                let skill = step.skillId.trimmingCharacters(in: .whitespacesAndNewlines)
                let suffix = skill.isEmpty ? "" : " skill=\(skill)"
                return "\(step.orderIndex + 1). \(step.stepId) | \(step.status.rawValue) | \(step.kind.rawValue) | \(capped(step.title, maxChars: 120))\(suffix)"
            }
        return rows.isEmpty ? "(none)" : rows.joined(separator: "\n")
    }
}
