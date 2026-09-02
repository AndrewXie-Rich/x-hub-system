import Foundation

extension SupervisorManager {
    func focusedSupervisorExecutionBrief(
        selection: SupervisorFocusedProjectSelection,
        projectDigests: [SupervisorMemoryProjectDigest],
        includeLongtermOutline: Bool = false,
        includeStrategicExpansion: Bool = false,
        recentMessageLimit: Int = 4
    ) -> SupervisorFocusedProjectExecutionBrief {
        let project = selection.project
        let digest = projectDigests.first(where: { $0.projectId == project.projectId }) ??
            supervisorMemoryDigest(project)
        let ctx = supervisorMemoryContext(for: project)
        let recent = AXRecentContextStore.load(for: ctx)
        let governance = loadSupervisorProjectDigestGovernanceContext(projectId: project.projectId, ctx: ctx)
        let specCapsule = governance.specCapsule
        let config = (try? AXProjectStore.loadOrCreateConfig(for: ctx)) ?? .default(forProjectRoot: ctx.root)
        let effectiveRuntimeSurface = config.effectiveRuntimeSurfacePolicy()
        let state = supervisorWorkflowState(
            project: project,
            ctx: ctx,
            preferredJobId: currentTask?.projectId == project.projectId ? currentTask?.id : nil,
            preferredPlanId: nil,
            preferredRequestId: nil
        )

        let activeJob = state?.job
        let activePlan = state?.plan
        let activeSkillCall = state?.skillCall
        let planSteps = activePlan.map(workflowPlanStepsDigest) ?? "(none)"
        let nextPendingSteps = activePlan.map {
            workflowPlanFilteredStepsDigest($0, statuses: [.pending])
        } ?? "(none)"
        let attentionSteps = activePlan.map {
            workflowPlanFilteredStepsDigest(
                $0,
                statuses: [.running, .blocked, .awaitingAuthorization]
            )
        } ?? "(none)"
        let recentMessages = focusedSupervisorRecentMessagesDigest(
            recent,
            limit: recentMessageLimit
        )
        let activeJobGoal = activeJob?.goal.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let activeSkillResult = activeSkillCall?.resultSummary.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let doneDefinition = firstMeaningfulDigestValue([
            specCapsule?.mvpDefinition,
            activeJobGoal
        ])
        let reviewConstraints = focusedSupervisorReviewConstraintDigest(
            specCapsule: specCapsule,
            config: config,
            effectiveRuntimeSurface: effectiveRuntimeSurface
        )
        let approvedDecisions = focusedSupervisorApprovedDecisionDigest(governance.hardDecisions)
        let decisionLineageBody = focusedSupervisorDecisionLineageDigest(
            governance.hardDecisions,
            expanded: includeStrategicExpansion
        )
        let backgroundHint = governance.backgroundShadowHint.trimmingCharacters(in: .whitespacesAndNewlines)
        let latestReview = SupervisorReviewNoteStore.latest(for: ctx)
        let latestUIReview = XTUIReviewStore.loadLatestBrowserPageReference(for: ctx)
        let latestGuidance = SupervisorGuidanceInjectionStore.latest(for: ctx)
        let pendingAckGuidance = SupervisorGuidanceInjectionStore.latestPendingAck(for: ctx)
        let blockerLineageBody = focusedSupervisorBlockerLineageDigest(
            digest: digest,
            latestReview: latestReview,
            latestGuidance: latestGuidance,
            pendingAckGuidance: pendingAckGuidance,
            activeSkillCall: activeSkillCall,
            decisionAssist: governance.decisionAssist,
            nextPendingStepsDigest: nextPendingSteps,
            attentionStepsDigest: attentionSteps,
            expanded: includeStrategicExpansion
        )
        let longtermOutlineBody = focusedSupervisorLongtermOutlineDigest(
            project: project,
            digest: digest,
            governance: governance,
            doneDefinition: doneDefinition,
            approvedDecisions: approvedDecisions,
            backgroundHint: backgroundHint,
            decisionLineage: decisionLineageBody
        )
        let longtermOutlineAnchor = includeLongtermOutline ? longtermOutlineBody : "(not_loaded)"
        let longtermOutlineInline = includeLongtermOutline
            ? focusedSupervisorLongtermOutlineInlineDigest(longtermOutlineBody)
            : "(not_loaded)"
        let latestReviewCanonical = focusedSupervisorLatestReviewCanonical(note: latestReview)
        let latestReviewInline = focusedSupervisorLatestReviewInline(note: latestReview)
        let latestUIReviewCanonical = focusedSupervisorLatestUIReviewCanonical(
            ctx: ctx,
            item: latestUIReview
        )
        let latestUIReviewInline = focusedSupervisorLatestUIReviewInline(item: latestUIReview)
        let latestGuidanceCanonical = focusedSupervisorLatestGuidanceCanonical(item: latestGuidance)
        let latestGuidanceInline = focusedSupervisorLatestGuidanceInline(item: latestGuidance)
        let pendingAckGuidanceCanonical = focusedSupervisorLatestGuidanceCanonical(item: pendingAckGuidance)
        let pendingAckGuidanceInline = focusedSupervisorLatestGuidanceInline(item: pendingAckGuidance)
        let heartbeatProjection = XTHeartbeatMemoryAssemblySupport.loadProjection(for: ctx)
        let heartbeatAnchorLines = XTHeartbeatMemoryAssemblySupport.anchorLines(from: heartbeatProjection)
        let heartbeatObservationLines = XTHeartbeatMemoryAssemblySupport.observationLines(
            from: heartbeatProjection
        )
        let decisionLineageInline = focusedSupervisorLineageInlineDigest(decisionLineageBody)
        let blockerLineageInline = focusedSupervisorLineageInlineDigest(blockerLineageBody)
        let pendingHubGrantsDigest = focusedSupervisorPendingGrantDigest(projectId: project.projectId)
        let pendingSkillApprovalsDigest = focusedSupervisorPendingSkillApprovalDigest(
            projectId: project.projectId
        )
        let recentSkillActivities = normalizedRecentSupervisorSkillActivities(
            projects: [project],
            limit: 3
        )
        let recentSkillActivitiesDigest = focusedSupervisorRecentSkillActivityDigest(
            recentSkillActivities
        )
        let recentEventLoopActivities = recentSupervisorEventLoopActivities.filter {
            $0.projectId.trimmingCharacters(in: .whitespacesAndNewlines)
                .compare(project.projectId, options: .caseInsensitive) == .orderedSame
        }
        let recentEventLoopActivitiesDigest = focusedSupervisorRecentEventLoopActivityDigest(
            recentEventLoopActivities
        )
        let recentIncidents = supervisorIncidentLedger.filter { incident in
            guard let incidentProjectId = incident.projectID?.uuidString.trimmingCharacters(
                in: .whitespacesAndNewlines
            ), !incidentProjectId.isEmpty else {
                return false
            }
            return incidentProjectId.compare(project.projectId, options: .caseInsensitive) == .orderedSame
        }
        let recentIncidentsDigest = focusedSupervisorRecentIncidentDigest(recentIncidents)
        let recentProjectNotificationsDigest = focusedSupervisorRecentProjectNotificationDigest(
            projectId: project.projectId
        )
        let recentRuntimeActivitiesDigest = focusedSupervisorRecentRuntimeActivityDigest(
            project: project
        )
        let pendingHubGrantCount = pendingHubGrants.filter {
            $0.projectId.trimmingCharacters(in: .whitespacesAndNewlines)
                .compare(project.projectId, options: .caseInsensitive) == .orderedSame
        }.count
        let pendingSkillApprovalCount = pendingSupervisorSkillApprovals.filter {
            $0.projectId.trimmingCharacters(in: .whitespacesAndNewlines)
                .compare(project.projectId, options: .caseInsensitive) == .orderedSame
        }.count
        let recentSkillActivityCount = recentSkillActivities.count
        let recentEventLoopActivityCount = recentEventLoopActivities.count
        let recentIncidentCount = recentIncidents.count
        let recentProjectNotificationCount = supervisorProjectNotificationRecords.filter {
            $0.projectId.trimmingCharacters(in: .whitespacesAndNewlines)
                .compare(project.projectId, options: .caseInsensitive) == .orderedSame
        }.count
        let recentRuntimeActivityCount = runtimeActivityEntries.filter {
            runtimeActivityEntry($0, matches: project)
        }.count
        let governanceSummary = focusedSupervisorRuntimeGovernanceDigest(
            governance: governance,
            config: config,
            effectiveRuntimeSurface: effectiveRuntimeSurface
        )
        let governanceInline = focusedSupervisorRuntimeGovernanceInlineDigest(
            governance: governance,
            config: config,
            effectiveRuntimeSurface: effectiveRuntimeSurface
        )
        let governanceReasonsInline = focusedSupervisorRuntimeGovernanceReasonsInlineDigest(governance)
        let missingAnchorFields = governance.missingSpecFields.isEmpty
            ? "(none)"
            : governance.missingSpecFields.map(\.rawValue).joined(separator: ", ")

        let canonicalBase = """
focus_source: \(selection.source)
project: \(project.displayName) (\(project.projectId))
memory_source: \(digest.source)
runtime_state: \(digest.runtimeState)
goal: \(digest.goal)
done_definition: \(doneDefinition.isEmpty ? "(none)" : doneDefinition)
constraints:
\(reviewConstraints)
approved_decisions:
\(approvedDecisions)
decision_lineage:
\(decisionLineageBody)
longterm_outline:
\(longtermOutlineAnchor)
background_hints:
\(backgroundHint.isEmpty ? "(none)" : backgroundHint)
blocker_lineage:
\(blockerLineageBody)
governance:
\(governanceSummary)
latest_ui_review:
\(latestUIReviewCanonical)
latest_review_note:
\(latestReviewCanonical)
latest_guidance_injection:
\(latestGuidanceCanonical)
pending_ack_guidance:
\(pendingAckGuidanceCanonical)
pending_hub_grants:
\(pendingHubGrantsDigest)
pending_skill_approvals:
\(pendingSkillApprovalsDigest)
recent_skill_activities:
\(recentSkillActivitiesDigest)
recent_event_loop_activities:
\(recentEventLoopActivitiesDigest)
recent_incidents:
\(recentIncidentsDigest)
recent_project_notifications:
\(recentProjectNotificationsDigest)
recent_runtime_activities:
\(recentRuntimeActivitiesDigest)
missing_anchor_fields: \(missingAnchorFields)
current_state: \(digest.currentState)
next_step: \(digest.nextStep)
blocker: \(digest.blocker)
active_job_id: \(activeJob?.jobId ?? "(none)")
active_job_goal: \(activeJobGoal.isEmpty ? "(none)" : activeJobGoal)
active_job_status: \(activeJob?.status.rawValue ?? "(none)")
active_plan_id: \(activePlan?.planId ?? "(none)")
active_plan_status: \(activePlan?.status.rawValue ?? "(none)")
active_plan_steps:
\(planSteps)
next_pending_steps:
\(nextPendingSteps)
attention_steps:
\(attentionSteps)
active_skill_request_id: \(activeSkillCall?.requestId ?? "(none)")
active_skill_id: \(activeSkillCall?.skillId ?? "(none)")
active_skill_status: \(activeSkillCall?.status.rawValue ?? "(none)")
active_skill_profile_summary: \(activeSkillCall?.deltaApproval?.summary.isEmpty == false ? activeSkillCall!.deltaApproval!.summary : "(none)")
active_skill_execution_readiness: \(activeSkillCall?.readiness?.executionReadiness.isEmpty == false ? activeSkillCall!.readiness!.executionReadiness : "(none)")
active_skill_requested_profiles: \(supervisorWorkflowSkillListSummary(activeSkillCall?.deltaApproval?.requestedProfiles ?? []))
active_skill_delta_profiles: \(supervisorWorkflowSkillListSummary(activeSkillCall?.deltaApproval?.deltaProfiles ?? []))
active_skill_requested_capability_families: \(supervisorWorkflowSkillListSummary(activeSkillCall?.deltaApproval?.requestedCapabilityFamilies ?? []))
active_skill_delta_capability_families: \(supervisorWorkflowSkillListSummary(activeSkillCall?.deltaApproval?.deltaCapabilityFamilies ?? []))
active_skill_unblock_actions: \(supervisorWorkflowSkillListSummary(activeSkillCall?.readiness?.unblockActions ?? []))
active_skill_result_summary: \(activeSkillResult.isEmpty ? "(none)" : activeSkillResult)
recent_relevant_messages:
\(recentMessages)
"""
        let canonicalBody = heartbeatAnchorLines.isEmpty
            ? canonicalBase
            : "\(canonicalBase)\n\(heartbeatAnchorLines.joined(separator: "\n"))"
        let canonical = """
[FOCUSED_PROJECT_ANCHOR_PACK]
\(canonicalBody)
[/FOCUSED_PROJECT_ANCHOR_PACK]
"""
        let observationBase = "focused_project_anchor_pack: source=\(selection.source) project=\(project.projectId) job=\(activeJob?.jobId ?? "(none)") plan=\(activePlan?.planId ?? "(none)") blocker=\(capped(digest.blocker, maxChars: 80)) next=\(capped(digest.nextStep, maxChars: 80))"
        let observation = heartbeatObservationLines.isEmpty
            ? observationBase
            : ([observationBase] + heartbeatObservationLines).joined(separator: "\n")
        let workingSet = """
focus_source=\(selection.source)
project=\(project.displayName) (\(project.projectId))
goal=\(digest.goal)
done_definition=\(doneDefinition.isEmpty ? "(none)" : capped(doneDefinition, maxChars: 160))
constraints=\(focusedSupervisorInlineConstraintDigest(specCapsule: specCapsule, config: config, effectiveRuntimeSurface: effectiveRuntimeSurface))
approved_decisions=\(focusedSupervisorInlineDecisionDigest(governance.hardDecisions))
decision_lineage=\(decisionLineageInline)
longterm_outline=\(longtermOutlineInline)
background_hints=\(backgroundHint.isEmpty ? "(none)" : backgroundHint)
blocker_lineage=\(blockerLineageInline)
latest_ui_review=\(latestUIReviewInline)
latest_review_note=\(latestReviewInline)
latest_guidance_injection=\(latestGuidanceInline)
pending_ack_guidance=\(pendingAckGuidanceInline)
pending_hub_grant_count=\(pendingHubGrantCount)
pending_hub_grants:
\(pendingHubGrantsDigest)
pending_skill_approval_count=\(pendingSkillApprovalCount)
pending_skill_approvals:
\(pendingSkillApprovalsDigest)
recent_skill_activity_count=\(recentSkillActivityCount)
recent_skill_activities:
\(recentSkillActivitiesDigest)
recent_event_loop_activity_count=\(recentEventLoopActivityCount)
recent_event_loop_activities:
\(recentEventLoopActivitiesDigest)
recent_incident_count=\(recentIncidentCount)
recent_incidents:
\(recentIncidentsDigest)
recent_project_notification_count=\(recentProjectNotificationCount)
recent_project_notifications:
\(recentProjectNotificationsDigest)
recent_runtime_activity_count=\(recentRuntimeActivityCount)
recent_runtime_activities:
\(recentRuntimeActivitiesDigest)
governance=\(governanceInline)
governance_reasons=\(governanceReasonsInline)
current_state=\(digest.currentState)
next_step=\(digest.nextStep)
blocker=\(digest.blocker)
active_job=\(activeJob?.jobId ?? "(none)") status=\(activeJob?.status.rawValue ?? "(none)")
active_plan=\(activePlan?.planId ?? "(none)") status=\(activePlan?.status.rawValue ?? "(none)")
next_pending_steps:
\(nextPendingSteps)
attention_steps:
\(attentionSteps)
recent_relevant_messages:
\(recentMessages)
"""
        return SupervisorFocusedProjectExecutionBrief(
            anchorPackBody: canonicalBody,
            longtermOutlineBody: longtermOutlineBody,
            decisionLineageBody: decisionLineageBody,
            blockerLineageBody: blockerLineageBody,
            canonical: canonical,
            observation: observation,
            workingSet: workingSet
        )
    }
}
