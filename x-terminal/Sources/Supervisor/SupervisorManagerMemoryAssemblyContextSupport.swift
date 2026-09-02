import Foundation

extension SupervisorManager {
    func supervisorMemoryCrossLinkRefs(
        projects: [AXProjectEntry],
        turnRoutingDecision: SupervisorTurnRoutingDecision
    ) -> String {
        let crossLinkSummary = SupervisorCrossLinkSummaryBuilder.build(
            snapshot: supervisorCrossLinkStore.snapshot,
            lastWriteObservation: supervisorCrossLinkStore.lastWriteObservation,
            projects: projects,
            focusedProjectId: turnRoutingDecision.focusedProjectId,
            focusedPersonName: turnRoutingDecision.focusedPersonName,
            focusedCommitmentId: turnRoutingDecision.focusedCommitmentId,
            turnMode: turnRoutingDecision.mode
        )
        return sanitizeSupervisorPromptIdentifiers(crossLinkSummary.promptContext)
    }

    func focusedSupervisorProjectGovernanceForMemory(
        selection: SupervisorFocusedProjectSelection?
    ) -> AXProjectResolvedGovernanceState? {
        selection.flatMap { selection in
            let ctx = supervisorMemoryContext(for: selection.project)
            return resolvedSupervisorProjectGovernanceState(
                projectId: selection.project.projectId,
                ctx: ctx
            )
        }
    }

    func supervisorSkillRegistrySnapshotForMemory(
        focusedProject: AXProjectEntry?
    ) async -> SupervisorSkillRegistrySnapshot? {
        guard let focusedProject else {
            return AXSkillsLibrary.supervisorGlobalSkillRegistrySnapshot(
                hubBaseDir: HubPaths.baseDir()
            )
        }

        let skillContext = supervisorMemoryContext(for: focusedProject)
        _ = await XTResolvedSkillsCacheStore.refreshFromHubIfPossible(
            projectId: focusedProject.projectId,
            projectName: focusedProject.displayName,
            context: skillContext,
            hubBaseDir: HubPaths.baseDir()
        )
        return AXSkillsLibrary.preferredSupervisorSkillRegistrySnapshot(
            projectId: focusedProject.projectId,
            projectName: focusedProject.displayName,
            projectRoot: skillContext.root,
            hubBaseDir: HubPaths.baseDir()
        )
    }

    func supervisorMemoryFocusedProjectFragments(
        projects: [AXProjectEntry],
        userMessage: String,
        projectDigests: [SupervisorMemoryProjectDigest],
        focusedProjectSelection: SupervisorFocusedProjectSelection?,
        servingProfile: XTMemoryServingProfile,
        reviewLevelHint: SupervisorReviewLevel
    ) async -> SupervisorMemoryFocusedProjectFragments {
        let workflowSlice = focusedSupervisorWorkflowMemorySlice(
            projects: projects,
            userMessage: userMessage,
            selection: focusedProjectSelection
        )
        let focusedProjectRetrieval = await focusedSupervisorProjectRetrievalBlock(
            selection: focusedProjectSelection,
            userMessage: userMessage,
            servingProfile: servingProfile
        )
        let includeLongtermOutline = shouldIncludeSupervisorLongtermOutline(servingProfile: servingProfile)
        let includeStrategicExpansion = servingProfile.rank >= XTMemoryServingProfile.m3DeepDive.rank
        let executionBrief = focusedProjectSelection.map {
            focusedSupervisorExecutionBrief(
                selection: $0,
                projectDigests: projectDigests,
                includeLongtermOutline: includeLongtermOutline,
                includeStrategicExpansion: includeStrategicExpansion
            )
        }
        let portfolioBrief = sanitizeSupervisorPromptIdentifiers(
            buildSupervisorPortfolioBrief(
                projects: projects,
                projectDigests: projectDigests,
                focusedSelection: focusedProjectSelection
            )
        )
        let focusedProjectAnchorPack = sanitizeSupervisorPromptIdentifiers(
            executionBrief?.anchorPackBody ?? ""
        )
        let longtermOutline = sanitizeSupervisorPromptIdentifiers(
            includeLongtermOutline ? (executionBrief?.longtermOutlineBody ?? "") : ""
        )
        let canonicalLayer = supervisorMemoryCanonicalLayer(
            projectDigests: projectDigests,
            workflowSlice: workflowSlice
        )
        let observationsLayer = supervisorMemoryObservationsLayer(
            projectDigests: projectDigests,
            focusedSelection: focusedProjectSelection,
            infrastructureObservationLines: supervisorInfrastructureObservationLines(),
            executionBrief: executionBrief,
            workflowSlice: workflowSlice
        )
        let deltaFeed = sanitizeSupervisorPromptIdentifiers(
            buildSupervisorDeltaFeed(
                userMessage: userMessage,
                projectDigests: projectDigests,
                focusedSelection: focusedProjectSelection,
                focusedExecutionBrief: executionBrief,
                workflowObservation: workflowSlice?.observation
            )
        )
        let servingContext = focusedSupervisorServingContext(
            selection: focusedProjectSelection,
            projectDigests: projectDigests,
            executionBrief: executionBrief,
            includeLongtermOutline: includeLongtermOutline,
            servingProfile: servingProfile,
            reviewLevelHint: reviewLevelHint
        )

        return SupervisorMemoryFocusedProjectFragments(
            workflowSlice: workflowSlice,
            focusedProjectRetrieval: focusedProjectRetrieval,
            includeLongtermOutline: includeLongtermOutline,
            executionBrief: executionBrief,
            portfolioBrief: portfolioBrief,
            focusedProjectAnchorPack: focusedProjectAnchorPack,
            longtermOutline: longtermOutline,
            canonicalLayer: canonicalLayer,
            observationsLayer: observationsLayer,
            deltaFeed: deltaFeed,
            servingContext: servingContext
        )
    }

    func focusedSupervisorServingContext(
        selection: SupervisorFocusedProjectSelection?,
        projectDigests: [SupervisorMemoryProjectDigest],
        executionBrief: SupervisorFocusedProjectExecutionBrief?,
        includeLongtermOutline: Bool,
        servingProfile: XTMemoryServingProfile,
        reviewLevelHint: SupervisorReviewLevel
    ) -> SupervisorFocusedProjectServingContext? {
        guard let selection else { return nil }

        let project = selection.project
        let ctx = supervisorMemoryContext(for: project)
        let digest = projectDigests.first(where: { $0.projectId == project.projectId }) ?? supervisorMemoryDigest(project)
        let governance = loadSupervisorProjectDigestGovernanceContext(projectId: project.projectId, ctx: ctx)
        let config = (try? AXProjectStore.loadOrCreateConfig(for: ctx)) ?? .default(forProjectRoot: ctx.root)
        let effectiveRuntimeSurface = config.effectiveRuntimeSurfacePolicy()
        let workflowState = supervisorWorkflowState(
            project: project,
            ctx: ctx,
            preferredJobId: currentTask?.projectId == project.projectId ? currentTask?.id : nil,
            preferredPlanId: nil,
            preferredRequestId: nil
        )
        let activeJob = workflowState?.job
        let activePlan = workflowState?.plan
        let activeSkillCall = workflowState?.skillCall
        let doneDefinition = firstMeaningfulDigestValue([
            governance.specCapsule?.mvpDefinition,
            activeJob?.goal
        ])
        let currentConstraints = focusedSupervisorReviewConstraintItems(
            specCapsule: governance.specCapsule,
            config: config,
            effectiveRuntimeSurface: effectiveRuntimeSurface
        )
        let longtermOutlineBody: String
        let decisionLineageDigest: String
        let blockerLineageDigest: String
        if includeLongtermOutline {
            if let executionBrief, !executionBrief.longtermOutlineBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                longtermOutlineBody = executionBrief.longtermOutlineBody
                decisionLineageDigest = executionBrief.decisionLineageBody
                blockerLineageDigest = executionBrief.blockerLineageBody
            } else {
                let approvedDecisions = focusedSupervisorApprovedDecisionDigest(governance.hardDecisions)
                let backgroundHint = governance.backgroundShadowHint.trimmingCharacters(in: .whitespacesAndNewlines)
                decisionLineageDigest = focusedSupervisorDecisionLineageDigest(
                    governance.hardDecisions,
                    expanded: servingProfile.rank >= XTMemoryServingProfile.m3DeepDive.rank
                )
                blockerLineageDigest = focusedSupervisorBlockerLineageDigest(
                    digest: digest,
                    latestReview: SupervisorReviewNoteStore.latest(for: ctx),
                    latestGuidance: SupervisorGuidanceInjectionStore.latest(for: ctx),
                    pendingAckGuidance: SupervisorGuidanceInjectionStore.latestPendingAck(for: ctx),
                    activeSkillCall: activeSkillCall,
                    decisionAssist: governance.decisionAssist,
                    nextPendingStepsDigest: activePlan.map {
                        workflowPlanFilteredStepsDigest($0, statuses: [.pending])
                    } ?? "(none)",
                    attentionStepsDigest: activePlan.map {
                        workflowPlanFilteredStepsDigest(
                            $0,
                            statuses: [.running, .blocked, .awaitingAuthorization]
                        )
                    } ?? "(none)",
                    expanded: servingProfile.rank >= XTMemoryServingProfile.m3DeepDive.rank
                )
                longtermOutlineBody = focusedSupervisorLongtermOutlineDigest(
                    project: project,
                    digest: digest,
                    governance: governance,
                    doneDefinition: doneDefinition,
                    approvedDecisions: approvedDecisions,
                    backgroundHint: backgroundHint,
                    decisionLineage: decisionLineageDigest
                )
            }
        } else {
            longtermOutlineBody = ""
            decisionLineageDigest = executionBrief?.decisionLineageBody ?? ""
            blockerLineageDigest = executionBrief?.blockerLineageBody ?? ""
        }

        let recent = AXRecentContextStore.load(for: ctx)
        let recentMessagesDigest = focusedSupervisorRecentMessagesDigest(recent, limit: 4)
        let nextPendingStepsDigest = activePlan.map {
            workflowPlanFilteredStepsDigest($0, statuses: [.pending])
        } ?? "(none)"
        let attentionStepsDigest = activePlan.map {
            workflowPlanFilteredStepsDigest(
                $0,
                statuses: [.running, .blocked, .awaitingAuthorization]
            )
        } ?? "(none)"

        return SupervisorFocusedProjectServingContext(
            project: project,
            ctx: ctx,
            digest: digest,
            governance: governance,
            recent: recent,
            latestReview: SupervisorReviewNoteStore.latest(for: ctx),
            latestGuidance: SupervisorGuidanceInjectionStore.latest(for: ctx),
            pendingAckGuidance: SupervisorGuidanceInjectionStore.latestPendingAck(for: ctx),
            activeJob: activeJob,
            activePlan: activePlan,
            activeSkillCall: activeSkillCall,
            servingProfile: servingProfile,
            reviewLevelHint: reviewLevelHint,
            doneDefinition: doneDefinition,
            currentConstraints: currentConstraints,
            longtermOutlineBody: longtermOutlineBody,
            decisionLineageDigest: decisionLineageDigest,
            blockerLineageDigest: blockerLineageDigest,
            recentMessagesDigest: recentMessagesDigest,
            nextPendingStepsDigest: nextPendingStepsDigest,
            attentionStepsDigest: attentionStepsDigest
        )
    }

    func shouldIncludeSupervisorLongtermOutline(
        servingProfile: XTMemoryServingProfile?
    ) -> Bool {
        guard let servingProfile else { return false }
        return servingProfile.rank >= XTMemoryServingProfile.m2PlanReview.rank
    }

    func supervisorCrossProjectDrillDownWorkingSet(
        excludingProjectId focusedProjectId: String?
    ) -> String {
        guard let snapshot = supervisorLastProjectDrillDownSnapshot,
              snapshot.status == .allowed else {
            return ""
        }
        if let focusedProjectId,
           snapshot.projectId == focusedProjectId {
            return ""
        }

        var lines: [String] = [
            "view=drilldown",
            "mode=explicit_structured_drilldown",
            "reason=\(snapshot.openedReason)",
            "project=\(snapshot.projectName) (\(snapshot.projectId))",
            "requested_scope=\(snapshot.requestedScope.rawValue)",
            "granted_scope=\(snapshot.grantedScope?.rawValue ?? "(none)")",
            "refs_count=\(snapshot.refs.count)"
        ]

        if let capsule = snapshot.capsule {
            lines.append("current_action=\(capped(capsule.currentAction, maxChars: 160))")
            lines.append("next_step=\(capped(capsule.nextStep, maxChars: 160))")
            if !capsule.topBlocker.isEmpty {
                lines.append("blocker=\(capped(capsule.topBlocker, maxChars: 160))")
            }
        }

        if let spec = snapshot.specCapsule {
            lines.append("spec_goal=\(capped(spec.goal, maxChars: 180))")
            lines.append("spec_mvp=\(capped(spec.mvpDefinition, maxChars: 180))")
            if !spec.approvedTechStack.isEmpty {
                lines.append("approved_tech_stack=\(capped(spec.approvedTechStack.joined(separator: ", "), maxChars: 180))")
            }
            if !spec.missingRequiredFields.isEmpty {
                lines.append("missing_spec_fields=\(spec.missingRequiredFields.map(\.rawValue).joined(separator: ","))")
            }
        }

        if let rails = snapshot.decisionRails {
            let approvedDecisions = rails.decisionTrack.prefix(3).map { decision in
                "\(decision.category.rawValue)=\(capped(firstNonEmptyLine(in: decision.statement), maxChars: 120))"
            }
            if !approvedDecisions.isEmpty {
                lines.append("approved_decisions:")
                lines.append(contentsOf: approvedDecisions.map { "- \($0)" })
            }

            let backgroundSummaries = rails.resolutions.compactMap { resolution -> String? in
                if let note = resolution.preferredBackgroundNote {
                    return "\(resolution.domain.rawValue)=\(capped(firstNonEmptyLine(in: note.statement), maxChars: 120)) [weak]"
                }
                if let note = resolution.shadowedBackgroundNotes.first {
                    return "\(resolution.domain.rawValue)=\(capped(firstNonEmptyLine(in: note.statement), maxChars: 120)) [shadowed]"
                }
                return nil
            }
            if !backgroundSummaries.isEmpty {
                lines.append("background_summary:")
                lines.append(contentsOf: backgroundSummaries.prefix(3).map { "- \($0)" })
            }
        }

        if let workflow = snapshot.workflow,
           let activeJob = workflow.activeJob {
            lines.append("active_job=\(activeJob.jobId) status=\(activeJob.status.rawValue)")
            lines.append("active_job_goal=\(capped(activeJob.goal, maxChars: 180))")
            if let activePlan = workflow.activePlan {
                lines.append("active_plan=\(activePlan.planId) status=\(activePlan.status.rawValue)")
                let steps = activePlan.steps
                    .sorted { lhs, rhs in
                        if lhs.orderIndex != rhs.orderIndex {
                            return lhs.orderIndex < rhs.orderIndex
                        }
                        return lhs.stepId < rhs.stepId
                    }
                    .prefix(4)
                    .map { step in
                        "\(step.orderIndex + 1). \(step.status.rawValue) | \(capped(step.title, maxChars: 120))"
                    }
                if !steps.isEmpty {
                    lines.append("active_plan_steps:")
                    lines.append(contentsOf: steps.map { "- \($0)" })
                }
            }
            if let activeSkillCall = workflow.activeSkillCall {
                lines.append("active_skill=\(activeSkillCall.skillId) status=\(activeSkillCall.status.rawValue)")
            }
        }

        if !snapshot.recentMessages.isEmpty {
            lines.append("recent_short_context:")
            lines.append(contentsOf: snapshot.recentMessages.prefix(4).map { message in
                "- \(message.role): \(capped(message.content, maxChars: 160))"
            })
        }

        if !snapshot.refs.isEmpty {
            lines.append("scope_safe_refs:")
            lines.append(contentsOf: snapshot.refs.prefix(6).map { "- \($0)" })
        }

        return lines.joined(separator: "\n")
    }
}
