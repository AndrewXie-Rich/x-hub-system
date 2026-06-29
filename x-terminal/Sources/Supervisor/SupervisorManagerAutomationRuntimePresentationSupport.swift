import Foundation

extension SupervisorManager {
    func renderAutomationRuntimeStatus(
        for project: AXProjectEntry,
        ctx: AXProjectContext
    ) throws -> String {
        let statusNow = Date().timeIntervalSince1970
        let config = try AXProjectStore.loadOrCreateConfig(for: ctx)
        let activeRecipeRef = config.activeAutomationRecipeRef.trimmingCharacters(in: .whitespacesAndNewlines)
        let persistedLastLaunchRef = config.lastAutomationLaunchRef.trimmingCharacters(in: .whitespacesAndNewlines)
        let lastLaunchRef = effectiveAutomationRunRefForPresentation(for: ctx) ?? persistedLastLaunchRef
        let continuitySnapshot = xtAutomationLatestProjectContinuitySnapshot(
            for: ctx,
            projectID: project.projectId,
            now: Date(timeIntervalSince1970: statusNow)
        )
        let recoveryCandidate = automationRecoveryCandidateForPresentation(
            ctx: ctx,
            now: statusNow
        )
        let deliveryClosureProjection = continuitySnapshot?.deliveryClosure
            ?? automationDeliveryClosureProjection(
                for: project,
                ctx: ctx,
                preferredRunID: firstNonEmpty(lastLaunchRef, recoveryCandidate?.runID),
                now: Date(timeIntervalSince1970: statusNow)
            )
        let persistedRecoveryAction = continuitySnapshot?.persistedRecoveryAction
            ?? xtAutomationLatestPersistedRecoveryActionSummary(
                for: ctx,
                preferredRunID: firstNonEmpty(lastLaunchRef, recoveryCandidate?.runID)
            )
        refreshAutomationRuntimeSnapshotForPresentation(
            project: project,
            ctx: ctx,
            lastLaunchRef: lastLaunchRef
        )
        let activeRecipe = config.activeAutomationRecipe
        let permissionReadiness = AXTrustedAutomationPermissionOwnerReadiness.current()
        let trustedAutomationStatus = config.trustedAutomationStatus(
            forProjectRoot: ctx.root,
            permissionReadiness: permissionReadiness,
            requiredDeviceToolGroups: activeRecipe?.requiredDeviceToolGroups ?? []
        )
        let trustedRequiredPermissions = AXTrustedAutomationPermissionOwnerReadiness.requiredPermissionKeys(
            forDeviceToolGroups: trustedAutomationStatus.deviceToolGroups
        )
        let trustedRepairActions = permissionReadiness.suggestedOpenSettingsActions(
            forDeviceToolGroups: trustedAutomationStatus.deviceToolGroups
        )

        var lines: [String] = []
        prependAutomationProjectGovernanceBriefIfAvailable(for: project, to: &lines)
        lines.append("🤖 Automation Runtime 状态")
        lines.append("项目: \(project.displayName) (\(project.projectId))")
        lines.append("recipe: \(activeRecipeRef.isEmpty ? "(未激活)" : activeRecipeRef)")
        lines.append("trusted_automation: \(trustedAutomationStatus.state.rawValue)")
        if !trustedRequiredPermissions.isEmpty {
            lines.append("trusted_required_permissions: \(trustedRequiredPermissions.joined(separator: ","))")
        }
        if let activeRecipe {
            lines.append("goal: \(activeRecipe.goal.isEmpty ? "(未填写)" : activeRecipe.goal)")
            if !activeRecipe.requiredToolGroups.isEmpty {
                lines.append("required_tool_groups: \(activeRecipe.requiredToolGroups.joined(separator: ","))")
            }
            if !activeRecipe.requiredDeviceToolGroups.isEmpty {
                lines.append("required_device_tool_groups: \(activeRecipe.requiredDeviceToolGroups.joined(separator: ","))")
            }
        }
        lines.append("self_iterate_mode: \(config.automationSelfIterateEnabled ? "enabled" : "disabled")")
        lines.append("self_iterate_max_auto_retry_depth: \(config.automationMaxAutoRetryDepth)")
        if !trustedAutomationStatus.armedDeviceToolGroups.isEmpty {
            lines.append("trusted_armed_device_tool_groups: \(trustedAutomationStatus.armedDeviceToolGroups.joined(separator: ","))")
        }
        lines.append("last_launch: \(lastLaunchRef.isEmpty ? "(none)" : lastLaunchRef)")
        if !lastLaunchRef.isEmpty,
           lastLaunchRef != persistedLastLaunchRef {
            lines.append("last_launch_source: checkpoint_fallback")
        }
        if let continuitySnapshot {
            lines.append("continuity_context_source: \(continuitySnapshot.contextSource)")
            if let effectiveRunID = continuitySnapshot.effectiveRunID {
                lines.append("continuity_effective_run_id: \(effectiveRunID)")
            }
        }
        if let recoveryCandidate {
            lines.append("recovery_candidate_run: \(recoveryCandidate.runID)")
            lines.append("recovery_candidate_state: \(recoveryCandidate.state.rawValue)")
            lines.append("recovery_candidate_selection: \(recoveryCandidate.selection.rawValue)")
            lines.append("recovery_candidate_reason: \(recoveryCandidate.reason.rawValue)")
            lines.append("recovery_candidate_checkpoint_age_seconds: \(recoveryCandidate.checkpointAgeSeconds)")
            lines.append("recovery_candidate_automatic_decision: \(recoveryCandidate.automaticDecision.rawValue)")
            if let deliveryRef = recoveryCandidate.deliveryRef,
               !deliveryRef.isEmpty {
                lines.append("recovery_candidate_delivery_ref: \(deliveryRef)")
            }
            if let resumeMode = recoveryCandidate.automaticResumeMode {
                lines.append("recovery_candidate_resume_mode: \(resumeMode.rawValue)")
            }
            if let retryStrategy = recoveryCandidate.automaticRetryStrategy,
               !retryStrategy.isEmpty {
                lines.append("recovery_candidate_retry_strategy: \(retryStrategy)")
            }
            if let retryReason = recoveryCandidate.automaticRetryReason,
               !retryReason.isEmpty {
                lines.append("recovery_candidate_retry_reason: \(retryReason)")
            }
            if let retryPlanningMode = recoveryCandidate.automaticRetryPlanningMode,
               !retryPlanningMode.isEmpty {
                lines.append("recovery_candidate_retry_planning_mode: \(retryPlanningMode)")
            }
            if let sourceHandoffArtifactPath = recoveryCandidate.automaticRetrySourceHandoffArtifactPath,
               !sourceHandoffArtifactPath.isEmpty {
                lines.append("recovery_candidate_retry_source_handoff: \(sourceHandoffArtifactPath)")
            }
            if !recoveryCandidate.automaticHoldReason.isEmpty {
                lines.append("recovery_candidate_automatic_hold_reason: \(recoveryCandidate.automaticHoldReason)")
            }
            if recoveryCandidate.retryAfterSeconds > 0 {
                lines.append("recovery_candidate_retry_after_seconds: \(recoveryCandidate.retryAfterSeconds)")
            }
            if let retryAfterRemainingSeconds = recoveryCandidate.retryAfterRemainingSeconds {
                lines.append("recovery_candidate_retry_after_remaining_seconds: \(retryAfterRemainingSeconds)")
            }
            if recoveryCandidate.latestVisibleRunID != recoveryCandidate.runID {
                lines.append("recovery_visible_latest_run: \(recoveryCandidate.latestVisibleRunID)")
                lines.append("recovery_visible_latest_state: \(recoveryCandidate.latestVisibleState.rawValue)")
            }
            if let supersededRunID = recoveryCandidate.supersededRunID {
                lines.append("recovery_superseded_run: \(supersededRunID)")
            }
            if let supersededByRunID = recoveryCandidate.supersededByRunID {
                lines.append("recovery_superseded_by_run: \(supersededByRunID)")
            }
        }
        appendAutomationDeliveryClosureLines(
            deliveryClosureProjection,
            to: &lines
        )
        appendPersistedAutomationRecoveryLines(
            persistedRecoveryAction,
            to: &lines
        )
        if let report = automationLatestExecutionReport,
           report.runID == lastLaunchRef {
            lines.append("last_execution_state: \(report.finalState.rawValue)")
            lines.append("last_execution_actions: \(report.executedActionCount)/\(report.totalActionCount)")
            if let lineage = report.lineage {
                lines.append("last_execution_lineage: \(lineage.lineageID)")
                lines.append("last_execution_root_run: \(lineage.rootRunID)")
                if !lineage.parentRunID.isEmpty {
                    lines.append("last_execution_parent_run: \(lineage.parentRunID)")
                }
                lines.append("last_execution_retry_depth: \(lineage.retryDepth)")
            }
            if let handoffPath = report.handoffArtifactPath,
               !handoffPath.isEmpty {
                lines.append("last_execution_handoff: \(handoffPath)")
            }
            if let deliveryRef = report.deliveryRef?.trimmingCharacters(in: .whitespacesAndNewlines),
               !deliveryRef.isEmpty {
                lines.append("last_execution_delivery_ref: \(deliveryRef)")
            }
            if let diff = report.workspaceDiffReport,
               diff.attempted {
                lines.append("last_execution_diff: \(diff.fileCount) files / \(diff.diffChars) chars")
                lines.append("last_execution_diff_detail: \(diff.detail)")
            }
            if let verification = report.verificationReport,
               verification.required {
                lines.append("last_execution_verify: \(verification.passedCommandCount)/\(verification.commandCount)")
                if !verification.holdReason.isEmpty {
                    lines.append("last_execution_verify_hold_reason: \(verification.holdReason)")
                }
                lines.append("last_execution_verify_detail: \(verification.detail)")
            }
            if !report.holdReason.isEmpty {
                lines.append("last_execution_hold_reason: \(report.holdReason)")
            }
            lines.append("last_execution_detail: \(report.detail)")
        }
        if let retryPackage = automationLatestRetryPackage,
           retryPackage.projectID == project.projectId {
            lines.append("retry_attempt_from_run: \(retryPackage.sourceRunID)")
            lines.append("retry_strategy: \(retryPackage.retryStrategy)")
            lines.append("retry_trigger: \(automationRetryTrigger(from: retryPackage))")
            if let lineage = retryPackage.lineage {
                lines.append("retry_lineage: \(lineage.lineageID)")
                lines.append("retry_root_run: \(lineage.rootRunID)")
                if !lineage.parentRunID.isEmpty {
                    lines.append("retry_parent_run: \(lineage.parentRunID)")
                }
                lines.append("retry_depth: \(lineage.retryDepth)")
            }
            if let planningMode = retryPackage.planningMode,
               !planningMode.isEmpty {
                lines.append("retry_planning_mode: \(planningMode)")
            }
            if let planningSummary = retryPackage.planningSummary,
               !planningSummary.isEmpty {
                lines.append("retry_planning_summary: \(planningSummary)")
            }
            if let revisedActionGraph = retryPackage.revisedActionGraph,
               !revisedActionGraph.isEmpty {
                lines.append("retry_revised_action_graph_count: \(revisedActionGraph.count)")
            }
            if let revisedVerifyCommands = retryPackage.revisedVerifyCommands,
               !revisedVerifyCommands.isEmpty {
                lines.append("retry_revised_verify_commands: \(revisedVerifyCommands.joined(separator: " || "))")
            }
            if let revisedVerificationContract = retryPackage.revisedVerificationContract {
                lines.append("retry_revised_verification_method: \(revisedVerificationContract.verifyMethod)")
                lines.append("retry_revised_verification_expected_state: \(revisedVerificationContract.expectedState)")
            }
            let runtimePatchOverlayKeys = xtAutomationRuntimePatchOverlayKeys(retryPackage.runtimePatchOverlay)
            if !runtimePatchOverlayKeys.isEmpty {
                lines.append("retry_runtime_patch_overlay_keys: \(runtimePatchOverlayKeys.joined(separator: ","))")
            }
            if let recipeProposalArtifactPath = retryPackage.recipeProposalArtifactPath?.trimmingCharacters(in: .whitespacesAndNewlines),
               !recipeProposalArtifactPath.isEmpty {
                lines.append("retry_recipe_proposal_artifact: \(recipeProposalArtifactPath)")
            }
            if let planningArtifactPath = retryPackage.planningArtifactPath?.trimmingCharacters(in: .whitespacesAndNewlines),
               !planningArtifactPath.isEmpty {
                lines.append("retry_planning_artifact: \(planningArtifactPath)")
            }
            lines.append("last_retry_source_handoff: \(retryPackage.sourceHandoffArtifactPath)")
            if !retryPackage.retryRunID.isEmpty {
                lines.append("retry_run_id: \(retryPackage.retryRunID)")
                if let retryDeliveryRef = retryPackage.deliveryRef?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !retryDeliveryRef.isEmpty {
                    lines.append("retry_delivery_ref: \(retryDeliveryRef)")
                } else if let retryDeliveryRef = xtAutomationPersistedRunDeliveryRef(
                    for: retryPackage.retryRunID,
                    ctx: ctx
                ) {
                    lines.append("retry_delivery_ref: \(retryDeliveryRef)")
                }
            }
        }
        if !trustedAutomationStatus.missingPrerequisites.isEmpty {
            lines.append("trusted_missing: \(trustedAutomationStatus.missingPrerequisites.joined(separator: ","))")
        }
        if !trustedAutomationStatus.missingRequiredDeviceToolGroups.isEmpty {
            lines.append("trusted_missing_required_device_groups: \(trustedAutomationStatus.missingRequiredDeviceToolGroups.joined(separator: ","))")
        }
        if !trustedRepairActions.isEmpty {
            lines.append("trusted_repair_actions: \(trustedRepairActions.joined(separator: ","))")
        }

        if !lastLaunchRef.isEmpty,
           let checkpoint = automationCheckpointForPresentation(runID: lastLaunchRef, ctx: ctx) {
            lines.append("state: \(checkpoint.state.rawValue)")
            lines.append("attempt: \(checkpoint.attempt)")
            lines.append("last_transition: \(checkpoint.lastTransition)")
            lines.append("retry_after_seconds: \(checkpoint.retryAfterSeconds)")
            lines.append("checkpoint_ref: \(checkpoint.checkpointRef)")
            if automationCurrentCheckpoint?.runID == checkpoint.runID,
               let decision = automationRecoveryDecision {
                let holdReason = decision.holdReason.isEmpty ? "none" : decision.holdReason
                lines.append("recovery: \(decision.decision.rawValue) (\(holdReason))")
            }
        } else {
            lines.append("state: idle")
        }

        lines.append("manager_status: \(automationStatusLine)")
        return lines.joined(separator: "\n")
    }

    func renderAutomationStartSummary(
        project: AXProjectEntry,
        prepared: XTAutomationPreparedRun
    ) -> String {
        let launchDecision = prepared.verticalSlice.eventRunner.launchDecision.decision.rawValue
        var lines: [String] = []
        prependAutomationProjectGovernanceBriefIfAvailable(for: project, to: &lines)
        lines.append("✅ automation 已启动准备")
        lines.append("项目: \(project.displayName) (\(project.projectId))")
        lines.append("recipe: \(prepared.recipeRef)")
        lines.append("run_id: \(prepared.launchRef)")
        lines.append("state: \(prepared.currentCheckpoint.state.rawValue)")
        lines.append("launch_decision: \(launchDecision)")
        return lines.joined(separator: "\n")
    }

    func renderAutomationRecoverySummary(
        project: AXProjectEntry,
        ctx: AXProjectContext,
        decision: XTAutomationRestartRecoveryDecision?,
        retryPackage: XTAutomationRetryPackage?,
        recoveryCandidate: XTAutomationRecoveryCandidate?
    ) -> String {
        var lines: [String] = []
        prependAutomationProjectGovernanceBriefIfAvailable(for: project, to: &lines)

        guard let decision else {
            lines.append("ℹ️ automation 无可恢复运行")
            lines.append("项目: \(project.displayName) (\(project.projectId))")
            return lines.joined(separator: "\n")
        }

        let holdReason = decision.holdReason.isEmpty ? "none" : decision.holdReason
        let deliveryClosureProjection = automationDeliveryClosureProjection(
            for: project,
            ctx: ctx,
            preferredRunID: firstNonEmpty(
                retryPackage?.retryRunID,
                decision.runID,
                recoveryCandidate?.runID
            ),
            now: Date()
        )
        let retryLines: [String] = {
            guard let retryPackage,
                  retryPackage.projectID == project.projectId else {
                return []
            }
            var lines: [String] = [
                "retry_attempt_from_run: \(retryPackage.sourceRunID)",
                "retry_strategy: \(retryPackage.retryStrategy)",
                "last_retry_source_handoff: \(retryPackage.sourceHandoffArtifactPath)"
            ]
            if let planningMode = retryPackage.planningMode,
               !planningMode.isEmpty {
                lines.append("retry_planning_mode: \(planningMode)")
            }
            if let planningSummary = retryPackage.planningSummary,
               !planningSummary.isEmpty {
                lines.append("retry_planning_summary: \(planningSummary)")
            }
            if let planningArtifactPath = retryPackage.planningArtifactPath?.trimmingCharacters(in: .whitespacesAndNewlines),
               !planningArtifactPath.isEmpty {
                lines.append("retry_planning_artifact: \(planningArtifactPath)")
            }
            let runtimePatchOverlayKeys = xtAutomationRuntimePatchOverlayKeys(retryPackage.runtimePatchOverlay)
            if !runtimePatchOverlayKeys.isEmpty {
                lines.append("retry_runtime_patch_overlay_keys: \(runtimePatchOverlayKeys.joined(separator: ","))")
            }
            if let recipeProposalArtifactPath = retryPackage.recipeProposalArtifactPath?.trimmingCharacters(in: .whitespacesAndNewlines),
               !recipeProposalArtifactPath.isEmpty {
                lines.append("retry_recipe_proposal_artifact: \(recipeProposalArtifactPath)")
            }
            if !retryPackage.retryRunID.isEmpty {
                lines.append("retry_run_id: \(retryPackage.retryRunID)")
                if let retryDeliveryRef = retryPackage.deliveryRef?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !retryDeliveryRef.isEmpty {
                    lines.append("retry_delivery_ref: \(retryDeliveryRef)")
                } else if let retryDeliveryRef = xtAutomationPersistedRunDeliveryRef(
                    for: retryPackage.retryRunID,
                    ctx: ctx
                ) {
                    lines.append("retry_delivery_ref: \(retryDeliveryRef)")
                }
            }
            return lines
        }()
        lines.append("♻️ automation 恢复判定")
        lines.append("项目: \(project.displayName) (\(project.projectId))")
        lines.append("run_id: \(decision.runID)")
        lines.append("state: \(decision.recoveredState.rawValue)")
        lines.append("decision: \(decision.decision.rawValue)")
        lines.append("hold_reason: \(holdReason)")
        appendAutomationDeliveryClosureLines(
            deliveryClosureProjection,
            to: &lines
        )
        if let recoveryCandidate {
            lines.append("candidate_run_id: \(recoveryCandidate.runID)")
            lines.append("candidate_state: \(recoveryCandidate.state.rawValue)")
            lines.append("candidate_selection: \(recoveryCandidate.selection.rawValue)")
            lines.append("candidate_reason: \(recoveryCandidate.reason.rawValue)")
            lines.append("candidate_checkpoint_age_seconds: \(recoveryCandidate.checkpointAgeSeconds)")
            lines.append("candidate_automatic_decision: \(recoveryCandidate.automaticDecision.rawValue)")
            if let deliveryRef = recoveryCandidate.deliveryRef,
               !deliveryRef.isEmpty {
                lines.append("candidate_delivery_ref: \(deliveryRef)")
            }
            if let resumeMode = recoveryCandidate.automaticResumeMode {
                lines.append("candidate_resume_mode: \(resumeMode.rawValue)")
            }
            if let retryStrategy = recoveryCandidate.automaticRetryStrategy,
               !retryStrategy.isEmpty {
                lines.append("candidate_retry_strategy: \(retryStrategy)")
            }
            if let retryReason = recoveryCandidate.automaticRetryReason,
               !retryReason.isEmpty {
                lines.append("candidate_retry_reason: \(retryReason)")
            }
            if let retryPlanningMode = recoveryCandidate.automaticRetryPlanningMode,
               !retryPlanningMode.isEmpty {
                lines.append("candidate_retry_planning_mode: \(retryPlanningMode)")
            }
            if let sourceHandoffArtifactPath = recoveryCandidate.automaticRetrySourceHandoffArtifactPath,
               !sourceHandoffArtifactPath.isEmpty {
                lines.append("candidate_retry_source_handoff: \(sourceHandoffArtifactPath)")
            }
            if !recoveryCandidate.automaticHoldReason.isEmpty {
                lines.append("candidate_automatic_hold_reason: \(recoveryCandidate.automaticHoldReason)")
            }
            if recoveryCandidate.retryAfterSeconds > 0 {
                lines.append("candidate_retry_after_seconds: \(recoveryCandidate.retryAfterSeconds)")
            }
            if let retryAfterRemainingSeconds = recoveryCandidate.retryAfterRemainingSeconds {
                lines.append("candidate_retry_after_remaining_seconds: \(retryAfterRemainingSeconds)")
            }
            if recoveryCandidate.latestVisibleRunID != recoveryCandidate.runID {
                lines.append("visible_latest_run_id: \(recoveryCandidate.latestVisibleRunID)")
                lines.append("visible_latest_state: \(recoveryCandidate.latestVisibleState.rawValue)")
            }
            if let supersededRunID = recoveryCandidate.supersededRunID {
                lines.append("candidate_superseded_run_id: \(supersededRunID)")
            }
            if let supersededByRunID = recoveryCandidate.supersededByRunID {
                lines.append("candidate_superseded_by_run_id: \(supersededByRunID)")
            }
        }
        lines.append(contentsOf: retryLines)
        return lines.joined(separator: "\n")
    }

    func renderAutomationCancelSummary(
        project: AXProjectEntry,
        decision: XTAutomationRestartRecoveryDecision
    ) -> String {
        let holdReason = decision.holdReason.isEmpty ? "none" : decision.holdReason
        var lines: [String] = []
        prependAutomationProjectGovernanceBriefIfAvailable(for: project, to: &lines)
        lines.append("🛑 automation 已取消")
        lines.append("项目: \(project.displayName) (\(project.projectId))")
        lines.append("run_id: \(decision.runID)")
        lines.append("decision: \(decision.decision.rawValue)")
        lines.append("hold_reason: \(holdReason)")
        return lines.joined(separator: "\n")
    }

    func renderAutomationAdvanceSummary(
        project: AXProjectEntry,
        checkpoint: XTAutomationRunCheckpoint
    ) -> String {
        var lines: [String] = []
        prependAutomationProjectGovernanceBriefIfAvailable(for: project, to: &lines)
        lines.append("➡️ automation 状态已推进")
        lines.append("项目: \(project.displayName) (\(project.projectId))")
        lines.append("run_id: \(checkpoint.runID)")
        lines.append("state: \(checkpoint.state.rawValue)")
        lines.append("attempt: \(checkpoint.attempt)")
        lines.append("last_transition: \(checkpoint.lastTransition)")
        return lines.joined(separator: "\n")
    }

    func renderAutomationSelfIterateSummary(
        project: AXProjectEntry,
        config: AXProjectConfig,
        headline: String
    ) -> String {
        var lines: [String] = []
        prependAutomationProjectGovernanceBriefIfAvailable(for: project, to: &lines)
        lines.append(headline)
        lines.append("项目: \(project.displayName) (\(project.projectId))")
        lines.append("self_iterate_mode: \(config.automationSelfIterateEnabled ? "enabled" : "disabled")")
        lines.append("self_iterate_max_auto_retry_depth: \(config.automationMaxAutoRetryDepth)")
        lines.append("behavior: bounded_auto_retry_only")
        lines.append("proposal_mode: controlled_runtime_patch_overlay")
        return lines.joined(separator: "\n")
    }

    func renderAutomationExecutionSummary(
        project: AXProjectEntry,
        report: XTAutomationRunExecutionReport
    ) -> String {
        let holdReason = report.holdReason.isEmpty ? "none" : report.holdReason
        let diffText: String = {
            guard let diff = report.workspaceDiffReport,
                  diff.attempted else {
                return "diff: skipped"
            }
            return "diff: \(diff.fileCount) files / \(diff.diffChars) chars (\(diff.detail))"
        }()
        let handoffText: String = {
            let path = (report.handoffArtifactPath ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return path.isEmpty ? "handoff: skipped" : "handoff: \(path)"
        }()
        let deliveryText: String = {
            let path = (report.deliveryRef ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return path.isEmpty ? "delivery: skipped" : "delivery: \(path)"
        }()
        let verificationText: String = {
            guard let verification = report.verificationReport,
                  verification.required else {
                return "verify: skipped"
            }
            let verifyHoldReason = verification.holdReason.isEmpty ? "none" : verification.holdReason
            return "verify: \(verification.passedCommandCount)/\(verification.commandCount) (\(verifyHoldReason))"
        }()
        var lines: [String] = []
        prependAutomationProjectGovernanceBriefIfAvailable(for: project, to: &lines)
        lines.append("⚙️ automation 自动执行完成")
        lines.append("项目: \(project.displayName)")
        lines.append("run_id: \(report.runID)")
        lines.append("state: \(report.finalState.rawValue)")
        lines.append("executed_actions: \(report.executedActionCount)/\(report.totalActionCount)")
        lines.append(deliveryText)
        lines.append(handoffText)
        lines.append(diffText)
        lines.append(verificationText)
        lines.append("hold_reason: \(holdReason)")
        lines.append("detail: \(report.detail)")
        return lines.joined(separator: "\n")
    }

    func renderAutomationRuntimeError(_ error: Error) -> String {
        if let runtimeError = error as? SupervisorAutomationRuntimeError {
            switch runtimeError {
            case .projectContextMissing(let projectID):
                return "❌ automation 失败：项目上下文不可用（project_id=\(projectID)）"
            case .projectSelectionMissing:
                return "❌ automation 失败：未选择项目。请先在 UI 中选中项目，或在命令里显式传入 projectRef\(automationRuntimeProjectHintSuffix())"
            case .projectNotFound(let projectRef):
                return "❌ automation 失败：找不到项目 \(projectRef)\(automationRuntimeProjectHintSuffix())"
            case .projectAmbiguous(let projectRef, let candidates):
                let suffix = candidates.isEmpty ? "" : "。候选：\(candidates.joined(separator: "、"))"
                return "⚠️ automation 失败：项目引用不唯一 \(projectRef)\(suffix)"
            }
        }

        if let coordinatorError = error as? XTAutomationRunCoordinatorError {
            switch coordinatorError {
            case .activeRecipeMissing:
                return "❌ automation 失败：当前项目没有激活的 automation recipe。请先把 recipe 配成 ready + active。"
            case .triggerSeedsMissing:
                return "❌ automation 失败：trigger seed 为空，无法创建 run。"
            case .triggerIngressNotAllowed(let triggerID):
                return "❌ automation 失败：外部触发 \(triggerID) 不在当前 recipe 的 allowlist 内，已 fail-closed。"
            case .triggerIngressReplayDetected(let token):
                return "❌ automation 失败：外部触发 dedupe/replay guard 命中（\(token)），已阻止重复 run。"
            case .triggerIngressPolicyMissing(let triggerID):
                return "❌ automation 失败：外部触发 \(triggerID) 缺少 grant/policy 绑定，已 fail-closed。"
            case .runNotFound(let runID):
                return "❌ automation 失败：找不到运行记录（run_id=\(runID)）。"
            }
        }

        return "❌ automation 失败：\(error.localizedDescription)"
    }
}
