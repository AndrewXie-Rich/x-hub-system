import Foundation

extension SupervisorManager {
    func callSupervisorSkill(
        from payload: SupervisorCallSkillPayload,
        userMessage: String,
        triggerSource: SupervisorCommandTriggerSource
    ) -> (ok: Bool, reasonCode: String, message: String, projectId: String?, projectName: String?) {
        let jobId = payload.jobId.trimmingCharacters(in: .whitespacesAndNewlines)
        let stepId = payload.stepId.trimmingCharacters(in: .whitespacesAndNewlines)
        let requestedSkillId = payload.skillId.trimmingCharacters(in: .whitespacesAndNewlines)
        let canonicalRequestedSkillId = AXSkillsLibrary.canonicalSupervisorSkillID(requestedSkillId)
        guard !jobId.isEmpty else {
            let message = "❌ CALL_SKILL 失败：job_id 不能为空（job_id_missing）"
            addSystemMessage(message)
            return (false, "job_id_missing", message, nil, nil)
        }
        guard !stepId.isEmpty else {
            let message = "❌ CALL_SKILL 失败：step_id 不能为空（step_id_missing）"
            addSystemMessage(message)
            return (false, "step_id_missing", message, nil, nil)
        }
        guard !canonicalRequestedSkillId.isEmpty else {
            let message = "❌ CALL_SKILL 失败：skill_id 不能为空（skill_id_missing）"
            addSystemMessage(message)
            return (false, "skill_id_missing", message, nil, nil)
        }

        let workflow: SupervisorWorkflowStepResolution
        switch resolveSupervisorWorkflowStep(
            projectRef: payload.projectRef,
            jobId: jobId,
            stepId: stepId,
            skillId: requestedSkillId,
            commandName: "CALL_SKILL",
            userMessage: userMessage,
            triggerSource: triggerSource
        ) {
        case .failure(let failure):
            addSystemMessage(failure.message)
            return (false, failure.reasonCode, failure.message, failure.projectId, failure.projectName)
        case .success(let resolved):
            workflow = resolved
        }

        let nowMs = Int64((Date().timeIntervalSince1970 * 1000.0).rounded())
        let requestId = "skill-\(nowMs)-\(String(UUID().uuidString.lowercased().prefix(8)))"
        let owner = workflow.step.currentOwner.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? (workflow.job.currentOwner.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "supervisor" : workflow.job.currentOwner)
            : workflow.step.currentOwner
        let rawPayloadObject = payload.payload ?? [:]

        guard let initialRegistrySnapshot = AXSkillsLibrary.preferredSupervisorSkillRegistrySnapshot(
            projectId: workflow.project.projectId,
            projectName: workflow.project.displayName,
            projectRoot: workflow.ctx.root,
            hubBaseDir: HubPaths.baseDir()
        ) else {
            let displaySkill = supervisorSkillDisplaySummary(
                requestedSkillId: nil,
                effectiveSkillId: requestedSkillId,
                payload: rawPayloadObject
            )
            let summary = "Hub skill registry 当前不可用，技能 \(displaySkill) 暂时无法解析。"
            let message = "❌ CALL_SKILL 失败：\(summary)（skill_registry_unavailable）"
            _ = persistBlockedSupervisorSkillCall(
                requestId: requestId,
                project: workflow.project,
                ctx: workflow.ctx,
                jobId: workflow.job.jobId,
                planId: workflow.plan.planId,
                stepId: workflow.step.stepId,
                skillId: requestedSkillId,
                payload: rawPayloadObject,
                currentOwner: owner,
                resultSummary: summary,
                denyCode: "skill_registry_unavailable",
                triggerSource: triggerSource,
                updatedAtMs: nowMs
            )
            addProjectScopedSystemMessageIfVisible(message, project: workflow.project)
            return (false, "skill_registry_unavailable", message, workflow.project.projectId, workflow.project.displayName)
        }
        warmResolvedSkillsCacheIfPossible(for: workflow.project)

        var registrySnapshot = initialRegistrySnapshot
        var effectiveSkillId = effectiveSupervisorSkillID(
            requestedSkillId: requestedSkillId,
            projectId: workflow.project.projectId,
            projectName: workflow.project.displayName,
            projectRoot: workflow.ctx.root,
            registrySnapshot: registrySnapshot
        )
        let initialRegistryItem = registrySnapshot.items.first(where: {
            AXSkillsLibrary.canonicalSupervisorSkillID($0.skillId) == effectiveSkillId
        })

        if initialRegistryItem == nil,
           let remoteStateDirPath = supervisorRecordedRemoteStateDirPath(
            ctx: workflow.ctx
           ) {
            refreshResolvedSkillsCacheSynchronouslyIfPossible(
                project: workflow.project,
                ctx: workflow.ctx,
                remoteStateDirPath: remoteStateDirPath
            )
            if let refreshedRegistrySnapshot = AXSkillsLibrary.preferredSupervisorSkillRegistrySnapshot(
                projectId: workflow.project.projectId,
                projectName: workflow.project.displayName,
                projectRoot: workflow.ctx.root,
                hubBaseDir: HubPaths.baseDir()
            ) {
                registrySnapshot = refreshedRegistrySnapshot
                effectiveSkillId = effectiveSupervisorSkillID(
                    requestedSkillId: requestedSkillId,
                    projectId: workflow.project.projectId,
                    projectName: workflow.project.displayName,
                    projectRoot: workflow.ctx.root,
                    registrySnapshot: registrySnapshot
                )
            }
        }

        let payloadObject = normalizedSupervisorSkillPayload(
            requestedSkillId: requestedSkillId,
            effectiveSkillId: effectiveSkillId,
            payload: payload.payload ?? [:]
        )
        let routedRequestedSkillId = requestedSkillId == effectiveSkillId ? nil : requestedSkillId
        let routingResolution = SupervisorSkillRoutingCompatibilityHint.routingResolution(
            requestedSkillId: routedRequestedSkillId,
            effectiveSkillId: effectiveSkillId,
            payload: payloadObject,
            registryItems: registrySnapshot.items
        )
        let displaySkill = supervisorSkillDisplaySummary(
            requestedSkillId: routedRequestedSkillId,
            effectiveSkillId: effectiveSkillId,
            payload: payloadObject
        )
        let registryItem = registrySnapshot.items.first(where: {
            AXSkillsLibrary.canonicalSupervisorSkillID($0.skillId) == effectiveSkillId
        }) ?? persistedRemoteRegistryFallbackItem(
            skillId: effectiveSkillId,
            project: workflow.project,
            ctx: workflow.ctx
        )
        guard let registryItem else {
            let hubRegistryAvailable = supervisorSkillRegistryIncludesHubTruth(registrySnapshot)
            let denyCode = hubRegistryAvailable ? "skill_not_registered" : "skill_registry_unavailable"
            let summary = hubRegistryAvailable
                ? "技能 \(displaySkill) 不在当前 project scope 的 Hub registry 中。"
                : "Hub skill registry 当前不可用，技能 \(displaySkill) 暂时无法解析。"
            let recoveryMessage = denyCode == "skill_not_registered"
                ? supervisorMissingMultimodalWrapperRecoveryMessage(
                    requestedSkillId: requestedSkillId,
                    effectiveSkillId: effectiveSkillId
                )
                : nil
            let fullSummary = [summary, recoveryMessage]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            let message = "❌ CALL_SKILL 失败：\(fullSummary)（\(denyCode)）"
            _ = persistBlockedSupervisorSkillCall(
                requestId: requestId,
                project: workflow.project,
                ctx: workflow.ctx,
                jobId: workflow.job.jobId,
                planId: workflow.plan.planId,
                stepId: workflow.step.stepId,
                skillId: effectiveSkillId,
                requestedSkillId: routedRequestedSkillId,
                routingReasonCode: routingResolution?.reasonCode,
                routingExplanation: routingResolution?.explanation,
                payload: payloadObject,
                currentOwner: owner,
                resultSummary: fullSummary,
                denyCode: denyCode,
                triggerSource: triggerSource,
                updatedAtMs: nowMs
            )
            addProjectScopedSystemMessageIfVisible(message, project: workflow.project)
            return (false, denyCode, message, workflow.project.projectId, workflow.project.displayName)
        }

        let mapped: SupervisorMappedSkillDispatch
        switch mapSupervisorSkillToToolCall(
            skillId: effectiveSkillId,
            payload: payloadObject,
            requestId: requestId,
            projectId: workflow.project.projectId,
            projectName: workflow.project.displayName,
            projectRoot: workflow.ctx.root,
            registryItem: registryItem
        ) {
        case .success(let dispatch):
            mapped = dispatch
        case .failure(let failure):
            let blockedSummary = supervisorSkillMappingFailureSummary(failure)
            let blockedDenyCode = failure.reasonCode == "unsupported_skill_id"
                ? "skill_mapping_missing"
                : failure.reasonCode
            var blocked = SupervisorSkillCallRecord(
                schemaVersion: SupervisorSkillCallRecord.currentSchemaVersion,
                requestId: requestId,
                projectId: workflow.project.projectId,
                jobId: workflow.job.jobId,
                planId: workflow.plan.planId,
                stepId: workflow.step.stepId,
                skillId: effectiveSkillId,
                requestedSkillId: routedRequestedSkillId,
                routingReasonCode: routingResolution?.reasonCode,
                routingExplanation: routingResolution?.explanation,
                toolName: "",
                status: .blocked,
                payload: payloadObject,
                currentOwner: owner,
                resultSummary: blockedSummary,
                denyCode: blockedDenyCode,
                resultEvidenceRef: nil,
                requiredCapability: nil,
                grantRequestId: nil,
                grantId: nil,
                hubStateDirPath: supervisorRecordedRemoteStateDirPath(
                    ctx: workflow.ctx,
                    registryItem: registryItem
                ),
                createdAtMs: nowMs,
                updatedAtMs: nowMs,
                auditRef: "audit-xt-supervisor-skill-\(String(requestId.suffix(12)))"
            )
            hydrateSupervisorSkillGovernanceSnapshot(
                &blocked,
                project: workflow.project,
                ctx: workflow.ctx,
                toolCall: nil,
                registryItem: registryItem
            )
            blocked.resultEvidenceRef = SupervisorSkillResultEvidenceStore.write(
                record: blocked,
                toolCall: nil,
                rawOutput: nil,
                triggerSource: triggerSource.rawValue,
                ctx: workflow.ctx
            )
            try? SupervisorProjectSkillCallStore.upsert(blocked, for: workflow.ctx)
            _ = updateSupervisorWorkflowStepState(
                ctx: workflow.ctx,
                project: workflow.project,
                jobId: workflow.job.jobId,
                planId: workflow.plan.planId,
                stepId: workflow.step.stepId,
                status: .blocked,
                detail: blocked.resultSummary,
                owner: blocked.currentOwner,
                updatedAtMs: nowMs
            )
            appendSupervisorSkillCallRawLog(
                action: "blocked",
                record: blocked,
                toolCall: nil,
                triggerSource: triggerSource,
                ctx: workflow.ctx
            )
            appendSupervisorSkillResultRawLog(
                record: blocked,
                toolCall: nil,
                rawOutput: nil,
                triggerSource: triggerSource,
                ctx: workflow.ctx
            )
            appendRecentEvent(
                "skill_result: \(workflow.project.displayName) -> \(blocked.skillId) \(blocked.status.rawValue)",
                project: workflow.project
            )
            let message = supervisorSkillMappingFailureMessage(displaySkill: displaySkill, failure: failure)
            addProjectScopedSystemMessageIfVisible(message, project: workflow.project)
            return (false, blockedDenyCode, message, workflow.project.projectId, workflow.project.displayName)
        }

        let projectConfig = (try? AXProjectStore.loadOrCreateConfig(for: workflow.ctx))
            ?? .default(forProjectRoot: workflow.ctx.root)
        let preflightVerdict = SupervisorSkillPreflightGate.evaluate(
            skillId: effectiveSkillId,
            projectId: workflow.project.projectId,
            projectName: workflow.project.displayName,
            registryItem: registryItem,
            toolCall: mapped.toolCall,
            projectRoot: workflow.ctx.root,
            config: projectConfig,
            hasExplicitGrant: supervisorToolCallHasExplicitGrant(mapped.toolCall),
            hubBaseDir: HubPaths.baseDir()
        )
        if preflightVerdict.isBlocked,
           !supervisorShouldBypassPolicyClampedPreflight(
            verdict: preflightVerdict,
            toolCall: mapped.toolCall
           ) {
            let message = supervisorSkillPreflightFailureMessage(
                displaySkill: displaySkill,
                verdict: preflightVerdict
            )
            var blocked = SupervisorSkillCallRecord(
                schemaVersion: SupervisorSkillCallRecord.currentSchemaVersion,
                requestId: requestId,
                projectId: workflow.project.projectId,
                jobId: workflow.job.jobId,
                planId: workflow.plan.planId,
                stepId: workflow.step.stepId,
                skillId: effectiveSkillId,
                requestedSkillId: routedRequestedSkillId,
                routingReasonCode: routingResolution?.reasonCode,
                routingExplanation: routingResolution?.explanation,
                toolName: mapped.toolName,
                status: .blocked,
                payload: payloadObject,
                currentOwner: owner,
                resultSummary: preflightVerdict.summary,
                denyCode: preflightVerdict.denyCode,
                policySource: "skill_preflight",
                policyReason: preflightVerdict.preflightResult,
                resultEvidenceRef: nil,
                requiredCapability: nil,
                grantRequestId: nil,
                grantId: nil,
                hubStateDirPath: supervisorRecordedRemoteStateDirPath(
                    ctx: workflow.ctx,
                    registryItem: registryItem
                ),
                createdAtMs: nowMs,
                updatedAtMs: nowMs,
                auditRef: "audit-xt-supervisor-skill-\(String(requestId.suffix(12)))"
            )
            hydrateSupervisorSkillGovernanceSnapshot(
                &blocked,
                project: workflow.project,
                ctx: workflow.ctx,
                toolCall: mapped.toolCall,
                config: projectConfig,
                registryItem: registryItem
            )
            blocked.resultEvidenceRef = SupervisorSkillResultEvidenceStore.write(
                record: blocked,
                toolCall: mapped.toolCall,
                rawOutput: nil,
                triggerSource: triggerSource.rawValue,
                ctx: workflow.ctx
            )
            try? SupervisorProjectSkillCallStore.upsert(blocked, for: workflow.ctx)
            _ = updateSupervisorWorkflowStepState(
                ctx: workflow.ctx,
                project: workflow.project,
                jobId: workflow.job.jobId,
                planId: workflow.plan.planId,
                stepId: workflow.step.stepId,
                status: .blocked,
                detail: blocked.resultSummary,
                owner: blocked.currentOwner,
                updatedAtMs: nowMs
            )
            appendSupervisorSkillCallRawLog(
                action: "blocked",
                record: blocked,
                toolCall: mapped.toolCall,
                triggerSource: triggerSource,
                ctx: workflow.ctx
            )
            appendSupervisorSkillResultRawLog(
                record: blocked,
                toolCall: mapped.toolCall,
                rawOutput: nil,
                triggerSource: triggerSource,
                ctx: workflow.ctx
            )
            appendRecentEvent(
                "skill_result: \(workflow.project.displayName) -> \(blocked.skillId) \(blocked.status.rawValue)",
                project: workflow.project
            )
            addProjectScopedSystemMessageIfVisible(message, project: workflow.project)
            return (false, blocked.denyCode, message, workflow.project.projectId, workflow.project.displayName)
        }

        let requiredCapability = supervisorRequiredHubCapability(for: mapped.toolCall)
        let requiresGrant =
            preflightVerdict.requiresGrantBeforeRun ||
            registryItem.requiresGrant ||
            requiredCapability != nil
        let requiresLocalApproval = preflightVerdict.requiresLocalApprovalBeforeRun
        let canBypassLocalGrantWait =
            requiredCapability == nil &&
            xtProjectGovernedAutoApprovalConfigured(
                projectRoot: workflow.ctx.root,
                config: projectConfig
            ) &&
            !ToolPolicy.isAlwaysConfirm(call: mapped.toolCall)
        let requiresWaitingAuthorization =
            (requiresGrant &&
                !supervisorToolCallHasExplicitGrant(mapped.toolCall) &&
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
            if requiresLocalApproval {
                return "waiting for local governed approval"
            }
            return "waiting for local governed approval"
        }()
        let awaitingDenyCode: String = {
            guard requiresWaitingAuthorization else { return "" }
            if let requiredCapability, !requiredCapability.isEmpty {
                return "grant_required"
            }
            if requiresLocalApproval {
                return "local_approval_required"
            }
            return "local_approval_required"
        }()
        var record = SupervisorSkillCallRecord(
            schemaVersion: SupervisorSkillCallRecord.currentSchemaVersion,
            requestId: requestId,
            projectId: workflow.project.projectId,
            jobId: workflow.job.jobId,
            planId: workflow.plan.planId,
            stepId: workflow.step.stepId,
            skillId: effectiveSkillId,
            requestedSkillId: routedRequestedSkillId,
            routingReasonCode: routingResolution?.reasonCode,
            routingExplanation: routingResolution?.explanation,
            toolName: mapped.toolName,
            status: requiresWaitingAuthorization ? .awaitingAuthorization : .queued,
            payload: payloadObject,
            currentOwner: owner,
            resultSummary: awaitingResultSummary,
            denyCode: awaitingDenyCode,
            resultEvidenceRef: nil,
            requiredCapability: requiredCapability,
            grantRequestId: nil,
            grantId: nil,
            hubStateDirPath: supervisorRecordedRemoteStateDirPath(
                ctx: workflow.ctx,
                registryItem: registryItem
            ),
            createdAtMs: nowMs,
            updatedAtMs: nowMs,
            auditRef: "audit-xt-supervisor-skill-\(String(requestId.suffix(12)))"
        )
        hydrateSupervisorSkillGovernanceSnapshot(
            &record,
            project: workflow.project,
            ctx: workflow.ctx,
            toolCall: mapped.toolCall,
            config: projectConfig,
            registryItem: registryItem
        )
        record.resultEvidenceRef = SupervisorSkillResultEvidenceStore.write(
            record: record,
            toolCall: mapped.toolCall,
            rawOutput: nil,
            triggerSource: triggerSource.rawValue,
            ctx: workflow.ctx
        )

        do {
            try SupervisorProjectSkillCallStore.upsert(record, for: workflow.ctx)
        } catch {
            let message = "❌ CALL_SKILL 失败：技能调用落盘失败（skill_call_store_write_failed: \(error.localizedDescription))"
            addProjectScopedSystemMessageIfVisible(message, project: workflow.project)
            return (false, "skill_call_store_write_failed", message, workflow.project.projectId, workflow.project.displayName)
        }

        _ = updateSupervisorWorkflowStepState(
            ctx: workflow.ctx,
            project: workflow.project,
            jobId: workflow.job.jobId,
            planId: workflow.plan.planId,
            stepId: workflow.step.stepId,
            status: requiresWaitingAuthorization ? .awaitingAuthorization : .running,
            detail: record.resultSummary,
            owner: record.currentOwner,
            updatedAtMs: nowMs
        )
        appendSupervisorSkillCallRawLog(
            action: requiresWaitingAuthorization ? "awaiting_authorization" : "dispatch",
            record: record,
            toolCall: mapped.toolCall,
            triggerSource: triggerSource,
            ctx: workflow.ctx
        )
        appendSupervisorSkillResultRawLog(
            record: record,
            toolCall: mapped.toolCall,
            rawOutput: nil,
            triggerSource: triggerSource,
            ctx: workflow.ctx
        )

        if requiresWaitingAuthorization {
            appendRecentEvent(
                "skill_result: \(workflow.project.displayName) -> \(record.skillId) \(record.status.rawValue)",
                project: workflow.project
            )
            if let requiredCapability,
               supervisorHubGrantPreflightEnabled {
                let requestedSeconds = supervisorRequestedGrantWindowSeconds(payload: payloadObject)
                let reason = supervisorGrantReason(
                    project: workflow.project,
                    job: workflow.job,
                    skillId: effectiveSkillId,
                    capability: requiredCapability
                )
                let hubBaseDir = HubPaths.baseDir()
                let task = Task { [weak self] in
                    await HubPaths.withPinnedBaseDirOverride(hubBaseDir) {
                        guard let self else { return }
                        await self.requestSupervisorHubGrantForSkillCall(
                            requestId: requestId,
                            project: workflow.project,
                            ctx: workflow.ctx,
                            toolCall: mapped.toolCall,
                            requiredCapability: requiredCapability,
                            requestedSeconds: requestedSeconds,
                            reason: reason,
                            remoteStateDirPath: record.hubStateDirPath
                        )
                    }
                }
                supervisorSkillExecutionTasks[requestId] = task
                let message = "⏸️ 已为项目 \(workflow.project.displayName) 登记技能调用：\(displaySkill)（\(userFacingRequestIdentifier(requestId))），正在向 Hub 申请\(grantCapabilityText(capability: requiredCapability, modelId: ""))授权。"
                addProjectScopedSystemMessageIfVisible(message, project: workflow.project)
                return (true, "awaiting_authorization", message, workflow.project.projectId, workflow.project.displayName)
            }

            let message: String
            if let requiredCapability, !requiredCapability.isEmpty {
                message = "⏸️ 已为项目 \(workflow.project.displayName) 登记技能调用：\(displaySkill)（\(userFacingRequestIdentifier(requestId))），正在向 Hub 申请\(grantCapabilityText(capability: requiredCapability, modelId: ""))授权。"
            } else {
                message = "⏸️ 已为项目 \(workflow.project.displayName) 登记技能调用：\(displaySkill)（\(userFacingRequestIdentifier(requestId))），\(pendingSupervisorSkillPendingRequirementText(readiness: record.readiness, requiredCapability: requiredCapability))"
            }
            addProjectScopedSystemMessageIfVisible(message, project: workflow.project)
            return (true, "awaiting_authorization", message, workflow.project.projectId, workflow.project.displayName)
        }

        let hubBaseDir = HubPaths.baseDir()
        let task = Task { [weak self] in
            await HubPaths.withPinnedBaseDirOverride(hubBaseDir) {
                guard let self else { return }
                if let remoteStateDirPath = self.normalizedSupervisorHubStateDirPath(
                    record.hubStateDirPath
                ) {
                    await self.refreshResolvedSkillsCacheIfPossible(
                        project: workflow.project,
                        ctx: workflow.ctx,
                        remoteStateDirPath: remoteStateDirPath
                    )
                }
                await self.executeSupervisorSkillCall(
                    requestId: requestId,
                    project: workflow.project,
                    ctx: workflow.ctx,
                    toolCall: mapped.toolCall,
                    triggerSource: triggerSource
                )
            }
        }
        supervisorSkillExecutionTasks[requestId] = task

        let message = "✅ 已为项目 \(workflow.project.displayName) 排队技能调用：\(displaySkill)（\(userFacingRequestIdentifier(requestId))）"
        addProjectScopedSystemMessageIfVisible(message, project: workflow.project)
        return (true, "ok", message, workflow.project.projectId, workflow.project.displayName)
    }

    func executeSupervisorSkillCall(
        requestId: String,
        project: AXProjectEntry,
        ctx: AXProjectContext,
        toolCall: ToolCall,
        allowPreviouslyApprovedAuthorization: Bool = false,
        triggerSource: SupervisorCommandTriggerSource
    ) async {
        defer { supervisorSkillExecutionTasks.removeValue(forKey: requestId) }

        if isSupervisorSkillCanceled(requestId: requestId, ctx: ctx) {
            return
        }

        let existingRecord = SupervisorProjectSkillCallStore.load(for: ctx)
            .calls
            .first(where: { $0.requestId == requestId })
        let skillIdForPreflight = existingRecord?.skillId ?? ""
        let preflightRegistryItem = resolvedSupervisorRegistryItem(
            skillId: skillIdForPreflight,
            projectId: project.projectId,
            projectName: project.displayName,
            projectRoot: ctx.root
        )
        let displaySkillForPreflight = supervisorSkillDisplaySummary(
            requestedSkillId: existingRecord?.requestedSkillId,
            effectiveSkillId: skillIdForPreflight,
            payload: existingRecord?.payload ?? [:]
        )
        let config = (try? AXProjectStore.loadOrCreateConfig(for: ctx)) ?? .default(forProjectRoot: ctx.root)
        let preflightVerdict = SupervisorSkillPreflightGate.evaluate(
            skillId: skillIdForPreflight,
            projectId: project.projectId,
            projectName: project.displayName,
            registryItem: preflightRegistryItem,
            toolCall: toolCall,
            projectRoot: ctx.root,
            config: config,
            hasExplicitGrant: supervisorToolCallHasExplicitGrant(toolCall),
            hubBaseDir: HubPaths.baseDir()
        )
        if preflightVerdict.isBlocked,
           !supervisorShouldBypassPolicyClampedPreflight(
            verdict: preflightVerdict,
            toolCall: toolCall
           ) {
            let nowMs = Int64((Date().timeIntervalSince1970 * 1000.0).rounded())
            if let blocked = applySupervisorSkillCallStatus(
                requestId: requestId,
                ctx: ctx,
                project: project,
                status: .blocked,
                stepStatus: .blocked,
                resultSummary: preflightVerdict.summary,
                denyCode: preflightVerdict.denyCode,
                policySource: "skill_preflight",
                policyReason: preflightVerdict.preflightResult,
                updatedAtMs: nowMs,
                triggerSource: triggerSource,
                toolCall: toolCall
            ) {
                scheduleSupervisorSkillCallbackFollowUp(
                    record: blocked,
                    project: project,
                    ctx: ctx,
                    status: .blocked,
                    reason: blocked.resultSummary
                )
            }
            addProjectScopedSystemMessageIfVisible(
                supervisorSkillPreflightFailureMessage(
                    displaySkill: displaySkillForPreflight.isEmpty ? "技能调用" : displaySkillForPreflight,
                    verdict: preflightVerdict
                ),
                project: project
            )
            return
        }

        let decision = await xtToolAuthorizationDecision(
            call: toolCall,
            config: config,
            projectRoot: ctx.root
        )

        if isSupervisorSkillCanceled(requestId: requestId, ctx: ctx) {
            return
        }

        let nowMs = Int64((Date().timeIntervalSince1970 * 1000.0).rounded())
        if decision.isDenied,
           !supervisorShouldBypassGovernedNetworkToolPolicyDeny(
            decision: decision,
            toolCall: toolCall
           ) {
            let blockedSummary = xtToolAuthorizationDeniedSummaryText(
                call: toolCall,
                decision: decision
            )
            if let blocked = applySupervisorSkillCallStatus(
                requestId: requestId,
                ctx: ctx,
                project: project,
                status: .blocked,
                stepStatus: .blocked,
                resultSummary: blockedSummary,
                denyCode: decision.denyCode,
                policySource: decision.policySource,
                policyReason: decision.policyReason,
                updatedAtMs: nowMs,
                triggerSource: triggerSource,
                toolCall: toolCall
            ) {
                scheduleSupervisorSkillCallbackFollowUp(
                    record: blocked,
                    project: project,
                    ctx: ctx,
                    status: .blocked,
                    reason: blocked.resultSummary
                )
            }
            return
        }

        if decision.needsApproval, !allowPreviouslyApprovedAuthorization {
            _ = applySupervisorSkillCallStatus(
                requestId: requestId,
                ctx: ctx,
                project: project,
                status: .awaitingAuthorization,
                stepStatus: .awaitingAuthorization,
                resultSummary: decision.policyReason.isEmpty ? "tool confirmation required" : "tool confirmation required: \(decision.policyReason)",
                denyCode: "",
                policySource: decision.policySource,
                policyReason: decision.policyReason,
                updatedAtMs: nowMs,
                triggerSource: triggerSource,
                toolCall: toolCall
            )
            return
        }

        _ = applySupervisorSkillCallStatus(
            requestId: requestId,
            ctx: ctx,
            project: project,
            status: .running,
            stepStatus: .running,
            resultSummary: "executing \(toolCall.tool.rawValue)",
            denyCode: "",
            updatedAtMs: nowMs,
            triggerSource: triggerSource,
            toolCall: toolCall
        )

        do {
            let result: ToolResult
            if let override = supervisorToolExecutorOverride {
                result = try await override(toolCall, ctx.root)
            } else {
                result = try await ToolExecutor.execute(
                    call: toolCall,
                    projectRoot: ctx.root,
                    extraReadableRoots: supervisorAttachmentReadableRoots()
                )
            }
            if isSupervisorSkillCanceled(requestId: requestId, ctx: ctx) {
                return
            }
            AXProjectStore.appendToolLog(
                action: toolCall.tool.rawValue,
                input: foundationJSONObject(from: toolCall.args),
                output: result.output,
                ok: result.ok,
                for: ctx
            )
            let finalStatus = result.ok ? SupervisorSkillCallStatus.completed : .failed
            let resultPolicyContext: (denyCode: String, policySource: String, policyReason: String) = result.ok
                ? (denyCode: "", policySource: "", policyReason: "")
                : supervisorToolResultPolicyContext(from: result.output)
            if let updated = applySupervisorSkillCallStatus(
                requestId: requestId,
                ctx: ctx,
                project: project,
                status: finalStatus,
                stepStatus: result.ok ? .completed : .failed,
                resultSummary: summarizedSupervisorSkillOutput(
                    result.output,
                    ok: result.ok,
                    toolCall: toolCall
                ),
                denyCode: resultPolicyContext.denyCode,
                policySource: resultPolicyContext.policySource,
                policyReason: resultPolicyContext.policyReason,
                rawOutput: result.output,
                updatedAtMs: Int64((Date().timeIntervalSince1970 * 1000.0).rounded()),
                triggerSource: triggerSource,
                toolCall: toolCall
            ) {
                scheduleSupervisorSkillCallbackFollowUp(
                    record: updated,
                    project: project,
                    ctx: ctx,
                    status: finalStatus,
                    reason: updated.resultSummary
                )
            }
        } catch {
            if isSupervisorSkillCanceled(requestId: requestId, ctx: ctx) {
                return
            }
            if let failed = applySupervisorSkillCallStatus(
                requestId: requestId,
                ctx: ctx,
                project: project,
                status: .failed,
                stepStatus: .failed,
                resultSummary: capped(String(describing: error), maxChars: 320),
                denyCode: "tool_execution_failed",
                rawOutput: String(describing: error),
                updatedAtMs: Int64((Date().timeIntervalSince1970 * 1000.0).rounded()),
                triggerSource: triggerSource,
                toolCall: toolCall
            ) {
                scheduleSupervisorSkillCallbackFollowUp(
                    record: failed,
                    project: project,
                    ctx: ctx,
                    status: .failed,
                    reason: failed.resultSummary
                )
            }
        }
    }

    func executeGlobalSupervisorSkillCall(
        requestId: String,
        displaySkill: String,
        toolCall: ToolCall,
        triggerSource: SupervisorCommandTriggerSource
    ) async {
        defer { supervisorSkillExecutionTasks.removeValue(forKey: requestId) }

        let executionRoot = HubPaths.baseDir()
        do {
            let result: ToolResult
            if let override = supervisorToolExecutorOverride {
                result = try await override(toolCall, executionRoot)
            } else {
                result = try await ToolExecutor.execute(
                    call: toolCall,
                    projectRoot: executionRoot,
                    extraReadableRoots: supervisorAttachmentReadableRoots()
                )
            }

            let parsed = ToolExecutor.parseStructuredToolOutput(result.output)
            let structuredBody = parsed.body.trimmingCharacters(in: .whitespacesAndNewlines)
            let humanBody = ToolResultHumanSummary.body(for: result)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let body: String = {
                if result.ok {
                    if !structuredBody.isEmpty {
                        return structuredBody
                    }
                    return humanBody
                }
                if !humanBody.isEmpty {
                    return humanBody
                }
                return structuredBody
            }()
            let requestLabel = userFacingRequestIdentifier(requestId)
            let message = body.isEmpty
                ? "\(result.ok ? "✅" : "❌") 全局技能调用\(result.ok ? "完成" : "失败")：\(displaySkill)（\(requestLabel)）"
                : "\(result.ok ? "✅" : "❌") 全局技能调用\(result.ok ? "完成" : "失败")：\(displaySkill)（\(requestLabel)）\n\(body)"
            appendRecentEvent("global_skill_result: \(displaySkill) \(result.ok ? "completed" : "failed")")
            addSystemMessage(message)
        } catch {
            let detail = capped(String(describing: error), maxChars: 320)
            appendRecentEvent("global_skill_result: \(displaySkill) failed")
            addSystemMessage("❌ 全局技能调用失败：\(displaySkill)（\(userFacingRequestIdentifier(requestId))）\n\(detail)")
        }
    }
}
