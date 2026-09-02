import Foundation

extension SupervisorManager {
    func enqueueSupervisorSkillRetry(
        _ resolution: SupervisorSkillCallResolution
    ) {
        let nowMs = Int64((Date().timeIntervalSince1970 * 1000.0).rounded())
        let retryRequestId = "retry-\(nowMs)-\(String(UUID().uuidString.lowercased().prefix(8)))"
        var retried = resolution.record
        retried.requestId = retryRequestId
        retried.status = .queued
        retried.resultSummary = ""
        retried.denyCode = ""
        retried.policySource = nil
        retried.policyReason = nil
        retried.resultEvidenceRef = nil
        retried.profileDeltaRef = nil
        retried.deltaApproval = nil
        retried.readinessRef = nil
        retried.readiness = nil
        retried.grantRequestId = nil
        retried.grantId = nil
        retried.createdAtMs = nowMs
        retried.updatedAtMs = nowMs
        retried.auditRef = "audit-xt-supervisor-skill-\(String(retryRequestId.suffix(12)))"

        guard let toolCall = resolvedSupervisorToolCallForRecord(retried) else {
            retried.status = .blocked
            retried.resultSummary = "retry failed: skill mapping unavailable"
            retried.denyCode = "skill_mapping_missing"
            hydrateSupervisorSkillGovernanceSnapshot(
                &retried,
                project: resolution.project,
                ctx: resolution.ctx,
                toolCall: nil
            )
            retried.resultEvidenceRef = SupervisorSkillResultEvidenceStore.write(
                record: retried,
                toolCall: nil,
                rawOutput: nil,
                triggerSource: SupervisorCommandTriggerSource.userTurn.rawValue,
                ctx: resolution.ctx
            )
            try? SupervisorProjectSkillCallStore.upsert(retried, for: resolution.ctx)
            _ = updateSupervisorWorkflowStepState(
                ctx: resolution.ctx,
                project: resolution.project,
                jobId: retried.jobId,
                planId: retried.planId,
                stepId: retried.stepId,
                status: .blocked,
                detail: retried.resultSummary,
                owner: retried.currentOwner,
                updatedAtMs: nowMs
            )
            appendSupervisorSkillCallRawLog(
                action: "blocked",
                record: retried,
                toolCall: nil,
                triggerSource: .userTurn,
                ctx: resolution.ctx
            )
            appendSupervisorSkillResultRawLog(
                record: retried,
                toolCall: nil,
                rawOutput: nil,
                triggerSource: .userTurn,
                ctx: resolution.ctx
            )
            scheduleSupervisorSkillCallbackFollowUp(
                record: retried,
                project: resolution.project,
                ctx: resolution.ctx,
                status: .blocked,
                reason: retried.resultSummary
            )
            addProjectScopedSystemMessageIfVisible(
                "❌ 无法重试项目 \(resolution.project.displayName) 的技能调用：\(supervisorSkillDisplaySummary(resolution.record))（\(userFacingRequestIdentifier(resolution.record.requestId))）",
                project: resolution.project
            )
            return
        }

        let registryItem = resolvedSupervisorRegistryItem(
            skillId: retried.skillId,
            projectId: resolution.project.projectId,
            projectName: resolution.project.displayName,
            projectRoot: resolution.ctx.root
        )
        let projectConfig = supervisorProjectConfig(ctx: resolution.ctx)
        let preflightVerdict = SupervisorSkillPreflightGate.evaluate(
            skillId: retried.skillId,
            projectId: resolution.project.projectId,
            projectName: resolution.project.displayName,
            registryItem: registryItem,
            toolCall: toolCall,
            projectRoot: resolution.ctx.root,
            config: projectConfig,
            hasExplicitGrant: supervisorToolCallHasExplicitGrant(toolCall),
            hubBaseDir: HubPaths.baseDir()
        )
        if preflightVerdict.isBlocked,
           !supervisorShouldBypassPolicyClampedPreflight(
            verdict: preflightVerdict,
            toolCall: toolCall
           ) {
            retried.status = .blocked
            retried.resultSummary = preflightVerdict.summary
            retried.denyCode = preflightVerdict.denyCode
            retried.policySource = "skill_preflight"
            retried.policyReason = preflightVerdict.preflightResult
            retried.updatedAtMs = nowMs
            hydrateSupervisorSkillGovernanceSnapshot(
                &retried,
                project: resolution.project,
                ctx: resolution.ctx,
                toolCall: toolCall,
                config: projectConfig,
                registryItem: registryItem
            )
            retried.resultEvidenceRef = SupervisorSkillResultEvidenceStore.write(
                record: retried,
                toolCall: toolCall,
                rawOutput: nil,
                triggerSource: SupervisorCommandTriggerSource.userTurn.rawValue,
                ctx: resolution.ctx
            )

            do {
                try SupervisorProjectSkillCallStore.upsert(retried, for: resolution.ctx)
            } catch {
                addSystemMessage(
                    "❌ 重试技能调用落盘失败（skill_call_store_write_failed: \(error.localizedDescription)）"
                )
                return
            }

            _ = updateSupervisorWorkflowStepState(
                ctx: resolution.ctx,
                project: resolution.project,
                jobId: retried.jobId,
                planId: retried.planId,
                stepId: retried.stepId,
                status: .blocked,
                detail: retried.resultSummary,
                owner: retried.currentOwner,
                updatedAtMs: nowMs
            )
            appendSupervisorSkillCallRawLog(
                action: "blocked",
                record: retried,
                toolCall: toolCall,
                triggerSource: .userTurn,
                ctx: resolution.ctx
            )
            appendSupervisorSkillResultRawLog(
                record: retried,
                toolCall: toolCall,
                rawOutput: nil,
                triggerSource: .userTurn,
                ctx: resolution.ctx
            )
            scheduleSupervisorSkillCallbackFollowUp(
                record: retried,
                project: resolution.project,
                ctx: resolution.ctx,
                status: .blocked,
                reason: retried.resultSummary
            )
            addProjectScopedSystemMessageIfVisible(
                supervisorSkillPreflightFailureMessage(
                    displaySkill: supervisorSkillDisplaySummary(retried),
                    verdict: preflightVerdict
                ),
                project: resolution.project
            )
            return
        }
        let requiredCapability = supervisorRequiredHubCapability(for: toolCall)
        let requiresGrant =
            preflightVerdict.requiresGrantBeforeRun ||
            registryItem?.requiresGrant == true ||
            requiredCapability != nil
        let requiresLocalApproval = preflightVerdict.requiresLocalApprovalBeforeRun
        let canBypassLocalGrantWait =
            requiredCapability == nil &&
            xtProjectGovernedAutoApprovalConfigured(
                projectRoot: resolution.ctx.root,
                config: projectConfig
            ) &&
            !ToolPolicy.isAlwaysConfirm(call: toolCall)
        let requiresWaitingAuthorization =
            (requiresGrant &&
                !supervisorToolCallHasExplicitGrant(toolCall) &&
                !canBypassLocalGrantWait)
            || requiresLocalApproval
        let awaitingResultSummary: String = {
            guard requiresWaitingAuthorization else { return "queued governed dispatch" }
            if let requiredCapability, !requiredCapability.isEmpty {
                return XTHubGrantPresentation.awaitingStateSummary(
                    capability: requiredCapability,
                    modelId: "",
                    grantRequestId: nil
                )
            }
            return "waiting for local governed approval"
        }()
        let awaitingDenyCode: String = {
            guard requiresWaitingAuthorization else { return "" }
            if let requiredCapability, !requiredCapability.isEmpty {
                return "grant_required"
            }
            return "local_approval_required"
        }()

        retried.requiredCapability = requiredCapability
        retried.status = requiresWaitingAuthorization ? .awaitingAuthorization : .queued
        retried.resultSummary = awaitingResultSummary
        retried.denyCode = awaitingDenyCode
        hydrateSupervisorSkillGovernanceSnapshot(
            &retried,
            project: resolution.project,
            ctx: resolution.ctx,
            toolCall: toolCall,
            config: projectConfig,
            registryItem: registryItem
        )
        retried.resultEvidenceRef = SupervisorSkillResultEvidenceStore.write(
            record: retried,
            toolCall: toolCall,
            rawOutput: nil,
            triggerSource: SupervisorCommandTriggerSource.userTurn.rawValue,
            ctx: resolution.ctx
        )

        do {
            try SupervisorProjectSkillCallStore.upsert(retried, for: resolution.ctx)
        } catch {
            addSystemMessage(
                "❌ 重试技能调用落盘失败（skill_call_store_write_failed: \(error.localizedDescription)）"
            )
            return
        }

        _ = updateSupervisorWorkflowStepState(
            ctx: resolution.ctx,
            project: resolution.project,
            jobId: retried.jobId,
            planId: retried.planId,
            stepId: retried.stepId,
            status: requiresWaitingAuthorization ? .awaitingAuthorization : .pending,
            detail: retried.resultSummary,
            owner: retried.currentOwner,
            updatedAtMs: nowMs
        )
        appendSupervisorSkillCallRawLog(
            action: requiresWaitingAuthorization ? "awaiting_authorization" : "dispatch",
            record: retried,
            toolCall: toolCall,
            triggerSource: .userTurn,
            ctx: resolution.ctx
        )
        appendSupervisorSkillResultRawLog(
            record: retried,
            toolCall: toolCall,
            rawOutput: nil,
            triggerSource: .userTurn,
            ctx: resolution.ctx
        )

        if requiresWaitingAuthorization {
            appendRecentEvent(
                "skill_result: \(resolution.project.displayName) -> \(retried.skillId) \(retried.status.rawValue)",
                project: resolution.project
            )
            if let requiredCapability,
               supervisorHubGrantPreflightEnabled {
                let requestedSeconds = supervisorRequestedGrantWindowSeconds(payload: retried.payload)
                let reason = "retry supervisor skill \(retried.skillId) for project \(resolution.project.displayName) requires \(requiredCapability)"
                let hubBaseDir = HubPaths.baseDir()
                let task = Task { [weak self] in
                    await HubPaths.withPinnedBaseDirOverride(hubBaseDir) {
                        guard let self else { return }
                        await self.requestSupervisorHubGrantForSkillCall(
                            requestId: retryRequestId,
                            project: resolution.project,
                            ctx: resolution.ctx,
                            toolCall: toolCall,
                            requiredCapability: requiredCapability,
                            requestedSeconds: requestedSeconds,
                            reason: reason,
                            remoteStateDirPath: retried.hubStateDirPath
                        )
                    }
                }
                supervisorSkillExecutionTasks[retryRequestId] = task
                addProjectScopedSystemMessageIfVisible(
                    "⏸️ 已为项目 \(resolution.project.displayName) 重新登记技能调用：\(supervisorSkillDisplaySummary(retried))（\(userFacingRequestIdentifier(retryRequestId))），正在向 Hub 申请\(grantCapabilityText(capability: requiredCapability, modelId: ""))授权。",
                    project: resolution.project
                )
                return
            }

            let message: String
            if let requiredCapability, !requiredCapability.isEmpty {
                message = "⏸️ 已为项目 \(resolution.project.displayName) 重新登记技能调用：\(supervisorSkillDisplaySummary(retried))（\(userFacingRequestIdentifier(retryRequestId))），正在向 Hub 申请\(grantCapabilityText(capability: requiredCapability, modelId: ""))授权。"
            } else {
                message = "⏸️ 已为项目 \(resolution.project.displayName) 重新登记技能调用：\(supervisorSkillDisplaySummary(retried))（\(userFacingRequestIdentifier(retryRequestId))），\(pendingSupervisorSkillPendingRequirementText(readiness: retried.readiness, requiredCapability: requiredCapability))"
            }
            addProjectScopedSystemMessageIfVisible(message, project: resolution.project)
            return
        }

        let hubBaseDir = HubPaths.baseDir()
        let task = Task { [weak self] in
            await HubPaths.withPinnedBaseDirOverride(hubBaseDir) {
                guard let self else { return }
                await self.executeSupervisorSkillCall(
                    requestId: retryRequestId,
                    project: resolution.project,
                    ctx: resolution.ctx,
                    toolCall: toolCall,
                    triggerSource: .userTurn
                )
            }
        }
        supervisorSkillExecutionTasks[retryRequestId] = task
        addProjectScopedSystemMessageIfVisible(
            "✅ 已为项目 \(resolution.project.displayName) 重新排队技能调用：\(supervisorSkillDisplaySummary(retried))（\(userFacingRequestIdentifier(retryRequestId))）",
            project: resolution.project
        )
    }

    func resumeSupervisorSkillCallAfterLocalApproval(
        _ resolution: SupervisorSkillCallResolution
    ) {
        guard let toolCall = resolvedSupervisorToolCallForRecord(resolution.record) else {
            let nowMs = Int64((Date().timeIntervalSince1970 * 1000.0).rounded())
            if let blocked = applySupervisorSkillCallStatus(
                requestId: resolution.record.requestId,
                ctx: resolution.ctx,
                project: resolution.project,
                status: .blocked,
                stepStatus: .blocked,
                resultSummary: "本地审批已通过，但恢复这次受治理技能调用时缺少可执行映射。",
                denyCode: "skill_mapping_missing",
                updatedAtMs: nowMs,
                triggerSource: .approvalResolution,
                toolCall: nil
            ) {
                scheduleSupervisorApprovalResolutionFollowUp(
                    record: blocked,
                    project: resolution.project,
                    reasonCode: blocked.denyCode,
                    summary: blocked.resultSummary
                )
            }
            addProjectScopedSystemMessageIfVisible(
                "❌ 无法恢复项目 \(resolution.project.displayName) 的技能调用：\(supervisorSkillDisplaySummary(resolution.record))（\(userFacingRequestIdentifier(resolution.record.requestId))）",
                project: resolution.project
            )
            return
        }

        let nowMs = Int64((Date().timeIntervalSince1970 * 1000.0).rounded())
        _ = applySupervisorSkillCallStatus(
            requestId: resolution.record.requestId,
            ctx: resolution.ctx,
            project: resolution.project,
            status: .queued,
            stepStatus: .pending,
            resultSummary: "本地审批已通过，正在恢复这次受治理技能调用。",
            denyCode: "",
            updatedAtMs: nowMs,
            triggerSource: .approvalResolution,
            toolCall: toolCall
        )

        let hubBaseDir = HubPaths.baseDir()
        let task = Task { [weak self] in
            await HubPaths.withPinnedBaseDirOverride(hubBaseDir) {
                guard let self else { return }
                await self.executeSupervisorSkillCall(
                    requestId: resolution.record.requestId,
                    project: resolution.project,
                    ctx: resolution.ctx,
                    toolCall: toolCall,
                    allowPreviouslyApprovedAuthorization: true,
                    triggerSource: .approvalResolution
                )
            }
        }
        supervisorSkillExecutionTasks[resolution.record.requestId] = task
        addProjectScopedSystemMessageIfVisible(
            "✅ 已批准项目 \(resolution.project.displayName) 的技能调用：\(supervisorSkillDisplaySummary(resolution.record))（\(userFacingRequestIdentifier(resolution.record.requestId))）",
            project: resolution.project
        )
    }

    func blockSupervisorSkillCallAfterLocalApprovalDenial(
        _ resolution: SupervisorSkillCallResolution
    ) {
        let nowMs = Int64((Date().timeIntervalSince1970 * 1000.0).rounded())
        let toolCall = resolvedSupervisorToolCallForRecord(resolution.record)
        let denialContext = pendingSupervisorSkillDenialContext(for: resolution.record)
        if let blocked = applySupervisorSkillCallStatus(
            requestId: resolution.record.requestId,
            ctx: resolution.ctx,
            project: resolution.project,
            status: .blocked,
            stepStatus: .blocked,
            resultSummary: denialContext.resultSummary,
            denyCode: denialContext.denyCode,
            requiredCapability: denialContext.requiredCapability,
            updatedAtMs: nowMs,
            triggerSource: .approvalResolution,
            toolCall: toolCall
        ) {
            scheduleSupervisorApprovalResolutionFollowUp(
                record: blocked,
                project: resolution.project,
                reasonCode: blocked.denyCode,
                summary: blocked.resultSummary
            )
        }
    }

    func pendingSupervisorSkillDenialContext(
        for record: SupervisorSkillCallRecord
    ) -> (
        resultSummary: String,
        denyCode: String,
        requiredCapability: String?
    ) {
        let readinessState = record.readiness?.executionReadiness
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if readinessState == XTSkillExecutionReadinessState.grantRequired.rawValue {
            let directCapability = record.requiredCapability?.trimmingCharacters(
                in: .whitespacesAndNewlines
            ) ?? ""
            let readinessCapability = record.readiness?.requiredGrantCapabilities
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first(where: { !$0.isEmpty }) ?? ""
            let requiredCapability = directCapability.isEmpty ? readinessCapability : directCapability
            return (
                XTHubGrantPresentation.deniedStateSummary(
                    capability: requiredCapability,
                    modelId: "",
                    deniedByUser: true
                ),
                "grant_denied",
                requiredCapability.isEmpty ? nil : requiredCapability
            )
        }

        return (
            "本地审批已被你拒绝，这次受治理技能调用不会继续执行。",
            "local_approval_denied",
            nil
        )
    }
}

extension SupervisorManager {
    func approvePendingSupervisorSkillApproval(_ approval: SupervisorPendingSkillApproval) {
        performPendingSupervisorSkillApprovalAction(approval, approve: true)
    }

    func denyPendingSupervisorSkillApproval(_ approval: SupervisorPendingSkillApproval) {
        performPendingSupervisorSkillApprovalAction(approval, approve: false)
    }

    func approveSupervisorSkillActivity(_ activity: SupervisorRecentSkillActivity) {
        performLocalSupervisorSkillAuthorizationAction(
            requestId: activity.requestId,
            projectRef: activity.projectId,
            approve: true,
            commandName: "APPROVE_SUPERVISOR_SKILL_ACTIVITY",
            lookupTriggerSource: .approvalResolution
        )
    }

    func denySupervisorSkillActivity(_ activity: SupervisorRecentSkillActivity) {
        performLocalSupervisorSkillAuthorizationAction(
            requestId: activity.requestId,
            projectRef: activity.projectId,
            approve: false,
            commandName: "DENY_SUPERVISOR_SKILL_ACTIVITY",
            lookupTriggerSource: .approvalResolution
        )
    }

    func retrySupervisorSkillActivity(_ activity: SupervisorRecentSkillActivity) {
        let requestId = activity.requestId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !requestId.isEmpty else { return }

        let resolution: SupervisorSkillCallResolution
        switch locateSupervisorSkillCall(
            requestId: requestId,
            projectRef: activity.projectId,
            commandName: "RETRY_SUPERVISOR_SKILL",
            triggerSource: .skillCallback
        ) {
        case .failure(let failure):
            addSystemMessage(failure.message)
            rebuildPendingSupervisorSkillApprovalViewState()
            return
        case .success(let resolved):
            resolution = resolved
        }

        guard [.failed, .blocked, .canceled].contains(resolution.record.status) else {
            addSystemMessage(
                "ℹ️ \(userFacingRequestIdentifier(requestId)) 当前状态为 \(resolution.record.status.rawValue)，暂不需要重试。"
            )
            rebuildPendingSupervisorSkillApprovalViewState()
            return
        }

        guard let remoteStateDirPath = normalizedSupervisorHubStateDirPath(
            resolution.record.hubStateDirPath
        ) else {
            enqueueSupervisorSkillRetry(resolution)
            return
        }

        let taskKey = "prepare_retry:\(requestId)"
        let hubBaseDir = HubPaths.baseDir()
        let task = Task { @MainActor [weak self] in
            await HubPaths.withPinnedBaseDirOverride(hubBaseDir) {
                guard let self else { return }
                defer { self.supervisorSkillExecutionTasks.removeValue(forKey: taskKey) }
                await self.refreshResolvedSkillsCacheIfPossible(
                    project: resolution.project,
                    ctx: resolution.ctx,
                    remoteStateDirPath: remoteStateDirPath
                )
                self.enqueueSupervisorSkillRetry(resolution)
            }
        }
        supervisorSkillExecutionTasks[taskKey] = task
    }

    func approvePendingHubGrant(_ grant: SupervisorPendingGrant) {
        performPendingHubGrantAction(grant, approve: true)
    }

    func denyPendingHubGrant(_ grant: SupervisorPendingGrant) {
        performPendingHubGrantAction(grant, approve: false)
    }

    func performPendingSupervisorSkillApprovalAction(
        _ approval: SupervisorPendingSkillApproval,
        approve: Bool
    ) {
        performLocalSupervisorSkillAuthorizationAction(
            requestId: approval.requestId,
            projectRef: approval.projectId,
            approve: approve,
            commandName: approve ? "APPROVE_SUPERVISOR_SKILL" : "DENY_SUPERVISOR_SKILL",
            lookupTriggerSource: .approvalResolution
        )
    }

    func performLocalSupervisorSkillAuthorizationAction(
        requestId: String,
        projectRef: String,
        approve: Bool,
        commandName: String,
        lookupTriggerSource: SupervisorCommandTriggerSource = .userTurn
    ) {
        let normalizedRequestId = requestId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedRequestId.isEmpty else { return }

        let resolution: SupervisorSkillCallResolution
        switch locateSupervisorSkillCall(
            requestId: normalizedRequestId,
            projectRef: projectRef,
            commandName: commandName,
            triggerSource: lookupTriggerSource
        ) {
        case .failure(let failure):
            addSystemMessage(failure.message)
            rebuildPendingSupervisorSkillApprovalViewState()
            return
        case .success(let resolved):
            resolution = resolved
        }

        guard resolution.record.status == .awaitingAuthorization else {
            rebuildPendingSupervisorSkillApprovalViewState()
            return
        }

        let capability = resolution.record.requiredCapability?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let authorizationMode = pendingSupervisorSkillAuthorizationMode(
            readiness: resolution.record.readiness,
            requiredCapability: capability
        )
        if approve {
            switch authorizationMode {
            case .localApproval:
                break
            case .hubGrant:
                addSystemMessage(
                    "ℹ️ \(userFacingRequestIdentifier(normalizedRequestId)) 当前正在等待 Hub 授权，请在 Hub 授权面板处理。"
                )
                rebuildPendingSupervisorSkillApprovalViewState()
                return
            case .blocked:
                addSystemMessage(
                    "ℹ️ \(userFacingRequestIdentifier(normalizedRequestId)) 当前仍受技能治理限制，请先按阻塞提示处理。"
                )
                rebuildPendingSupervisorSkillApprovalViewState()
                return
            }
        }

        if approve {
            guard let remoteStateDirPath = normalizedSupervisorHubStateDirPath(
                resolution.record.hubStateDirPath
            ) else {
                resumeSupervisorSkillCallAfterLocalApproval(resolution)
                return
            }

            let taskKey = "prepare_local_approval_resume:\(normalizedRequestId)"
            let hubBaseDir = HubPaths.baseDir()
            let task = Task { @MainActor [weak self] in
                await HubPaths.withPinnedBaseDirOverride(hubBaseDir) {
                    guard let self else { return }
                    defer { self.supervisorSkillExecutionTasks.removeValue(forKey: taskKey) }
                    await self.refreshResolvedSkillsCacheIfPossible(
                        project: resolution.project,
                        ctx: resolution.ctx,
                        remoteStateDirPath: remoteStateDirPath
                    )
                    self.resumeSupervisorSkillCallAfterLocalApproval(resolution)
                }
            }
            supervisorSkillExecutionTasks[taskKey] = task
        } else {
            blockSupervisorSkillCallAfterLocalApprovalDenial(resolution)
        }
    }

    func performPendingHubGrantAction(
        _ grant: SupervisorPendingGrant,
        approve: Bool
    ) {
        let grantId = grant.grantRequestId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !grantId.isEmpty else { return }
        guard !pendingHubGrantActionsInFlight.contains(grantId) else { return }

        pendingHubGrantActionsInFlight.insert(grantId)
        let projectId = grant.projectId.trimmingCharacters(in: .whitespacesAndNewlines)
        let hubBaseDir = HubPaths.baseDir()

        Task { [weak self] in
            await HubPaths.withPinnedBaseDirOverride(hubBaseDir) {
                guard let self else { return }

                let result: HubIPCClient.PendingGrantActionResult
                if approve {
                    let ttlOverride = grant.requestedTtlSec > 0 ? grant.requestedTtlSec : nil
                    let tokenOverride = grant.requestedTokenCap > 0 ? grant.requestedTokenCap : nil
                    result = await self.approvePendingHubGrantRequest(
                        grantRequestId: grantId,
                        projectId: projectId.isEmpty ? nil : projectId,
                        requestedTtlSec: ttlOverride,
                        requestedTokenCap: tokenOverride,
                        note: "x_terminal_supervisor_quick_approve"
                    )
                } else {
                    result = await self.denyPendingHubGrantRequest(
                        grantRequestId: grantId,
                        projectId: projectId.isEmpty ? nil : projectId,
                        reason: "user_denied_from_supervisor"
                    )
                }

                await self.completePendingHubGrantAction(
                    grantId: grantId,
                    grant: grant,
                    approve: approve,
                    result: result
                )
            }
        }
    }

    func approvePendingHubGrantRequest(
        grantRequestId: String,
        projectId: String?,
        requestedTtlSec: Int?,
        requestedTokenCap: Int?,
        note: String
    ) async -> HubIPCClient.PendingGrantActionResult {
        if let override = approvePendingHubGrantRequestOverride {
            return await override(
                grantRequestId,
                projectId,
                requestedTtlSec,
                requestedTokenCap,
                note
            )
        }
        return await HubIPCClient.approvePendingGrantRequest(
            grantRequestId: grantRequestId,
            projectId: projectId,
            requestedTtlSec: requestedTtlSec,
            requestedTokenCap: requestedTokenCap,
            note: note
        )
    }

    func denyPendingHubGrantRequest(
        grantRequestId: String,
        projectId: String?,
        reason: String
    ) async -> HubIPCClient.PendingGrantActionResult {
        if let override = denyPendingHubGrantRequestOverride {
            return await override(
                grantRequestId,
                projectId,
                reason
            )
        }
        return await HubIPCClient.denyPendingGrantRequest(
            grantRequestId: grantRequestId,
            projectId: projectId,
            reason: reason
        )
    }

    func completePendingHubGrantAction(
        grantId: String,
        grant: SupervisorPendingGrant,
        approve: Bool,
        result: HubIPCClient.PendingGrantActionResult
    ) async {
        pendingHubGrantActionsInFlight.remove(grantId)

        if result.ok {
            pendingHubGrants.removeAll { $0.grantRequestId == grantId }
            let action = approve ? "通过" : "拒绝"
            let summary = pendingGrantSummaryLine(
                grant,
                includeGrantToken: true,
                includeScope: true,
                includeReason: false
            )
            addSystemMessage("已\(action) Hub 授权：\(summary)")
            await resumeSupervisorSkillCallsAfterGrantAction(
                grant: grant,
                approve: approve,
                result: result
            )
        } else {
            let action = approve ? "通过" : "拒绝"
            let reason = result.reasonCode?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown"
            let summary = pendingGrantSummaryLine(
                grant,
                includeGrantToken: true,
                includeScope: false,
                includeReason: false
            )
            let reasonText = annotatedUserVisibleReason(
                raw: reason,
                display: SupervisorBlockerPresentation.displayText(reason)
            )
            addSystemMessage("Hub 授权\(action)失败：\(summary)。原因：\(reasonText)。")
        }

        await refreshSchedulerSnapshot(force: true)
    }
}
