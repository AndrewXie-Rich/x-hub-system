import Foundation

extension SupervisorManager {
    func requestSupervisorHubGrantForSkillCall(
        requestId: String,
        project: AXProjectEntry,
        ctx: AXProjectContext,
        toolCall: ToolCall,
        requiredCapability: String,
        requestedSeconds: Int,
        reason: String,
        remoteStateDirPath: String? = nil
    ) async {
        if isSupervisorSkillCanceled(requestId: requestId, ctx: ctx) {
            supervisorSkillExecutionTasks.removeValue(forKey: requestId)
            return
        }

        let access: HubIPCClient.NetworkAccessResult
        if let override = supervisorNetworkAccessRequestOverride {
            access = await override(ctx.root, requestedSeconds, reason)
        } else {
            access = await HubIPCClient.requestNetworkAccess(
                root: ctx.root,
                seconds: requestedSeconds,
                reason: reason
            )
        }

        if isSupervisorSkillCanceled(requestId: requestId, ctx: ctx) {
            supervisorSkillExecutionTasks.removeValue(forKey: requestId)
            return
        }

        let nowMs = Int64((Date().timeIntervalSince1970 * 1000.0).rounded())
        let normalizedGrantRequestId = access.grantRequestId?.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackSeconds = max(120, access.remainingSeconds ?? requestedSeconds)

        switch access.state {
        case .enabled, .autoApproved:
            let activatedGrantId = await ToolExecutor.activateHighRiskGrantForSupervisor(
                projectRoot: ctx.root,
                capability: requiredCapability,
                grantRequestId: normalizedGrantRequestId,
                approvedGrantId: nil,
                fallbackSeconds: fallbackSeconds
            )
            let resumeGrantId = activatedGrantId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !resumeGrantId.isEmpty else {
                if let blocked = applySupervisorSkillCallStatus(
                    requestId: requestId,
                    ctx: ctx,
                    project: project,
                    status: .blocked,
                    stepStatus: .blocked,
                    resultSummary: "Hub grant 已通过，但恢复这次受治理技能调用时未能激活执行 grant。",
                    denyCode: "grant_activation_failed",
                    requiredCapability: requiredCapability,
                    grantRequestId: normalizedGrantRequestId,
                    grantId: nil,
                    updatedAtMs: nowMs,
                    triggerSource: .grantResolution,
                    toolCall: toolCall
                ) {
                    scheduleSupervisorGrantResolutionFollowUp(
                        record: blocked,
                        project: project,
                        reasonCode: blocked.denyCode,
                        summary: blocked.resultSummary
                    )
                }
                supervisorSkillExecutionTasks.removeValue(forKey: requestId)
                return
            }
            let resumeToolCall = injectSupervisorGrant(
                into: toolCall,
                grantId: resumeGrantId,
                capability: requiredCapability
            )
            let resumedRecord = applySupervisorSkillCallStatus(
                requestId: requestId,
                ctx: ctx,
                project: project,
                status: .queued,
                stepStatus: .pending,
                resultSummary: "Hub grant 已通过，正在恢复这次受治理技能调用。",
                denyCode: "",
                requiredCapability: requiredCapability,
                grantRequestId: normalizedGrantRequestId,
                grantId: resumeGrantId.isEmpty ? nil : resumeGrantId,
                updatedAtMs: nowMs,
                triggerSource: .grantResolution,
                toolCall: resumeToolCall
            )
            await refreshResolvedSkillsCacheIfPossible(
                project: project,
                ctx: ctx,
                remoteStateDirPath: remoteStateDirPath
            )
            let hubBaseDir = HubPaths.baseDir()
            let executeTask = Task { [weak self] in
                await HubPaths.withPinnedBaseDirOverride(hubBaseDir) {
                    guard let self else { return }
                    await self.executeSupervisorSkillCall(
                        requestId: requestId,
                        project: project,
                        ctx: ctx,
                        toolCall: resumeToolCall,
                        allowPreviouslyApprovedAuthorization: true,
                        triggerSource: .grantResolution
                    )
                }
            }
            supervisorSkillExecutionTasks[requestId] = executeTask
            let displaySkill = resumedRecord.map(supervisorSkillDisplaySummary) ?? "技能调用"
            addProjectScopedSystemMessageIfVisible(
                "✅ 已为项目 \(project.displayName) 取得 Hub 授权并恢复技能调用：\(displaySkill)（\(userFacingRequestIdentifier(requestId))）",
                project: project
            )
            return

        case .queued:
            _ = applySupervisorSkillCallStatus(
                requestId: requestId,
                ctx: ctx,
                project: project,
                status: .awaitingAuthorization,
                stepStatus: .awaitingAuthorization,
                resultSummary: XTHubGrantPresentation.awaitingStateSummary(
                    capability: requiredCapability,
                    modelId: "",
                    grantRequestId: normalizedGrantRequestId
                ),
                denyCode: "grant_required",
                requiredCapability: requiredCapability,
                grantRequestId: normalizedGrantRequestId,
                grantId: nil,
                updatedAtMs: nowMs,
                triggerSource: .grantResolution,
                toolCall: toolCall
            )
            if let normalizedGrantRequestId, !normalizedGrantRequestId.isEmpty {
                addProjectScopedSystemMessageIfVisible(
                    "⏸️ 已向 Hub 提交授权请求（\(userFacingGrantIdentifier(normalizedGrantRequestId))）。",
                    project: project
                )
            }
            await refreshSchedulerSnapshot(force: true)
            supervisorSkillExecutionTasks.removeValue(forKey: requestId)

        case .denied:
            if let blocked = applySupervisorSkillCallStatus(
                requestId: requestId,
                ctx: ctx,
                project: project,
                status: .blocked,
                stepStatus: .blocked,
                resultSummary: XTHubGrantPresentation.deniedStateSummary(
                    capability: requiredCapability,
                    modelId: "",
                    deniedByUser: false
                ),
                denyCode: access.reasonCode?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "grant_denied",
                requiredCapability: requiredCapability,
                grantRequestId: normalizedGrantRequestId,
                grantId: nil,
                updatedAtMs: nowMs,
                triggerSource: .grantResolution,
                toolCall: toolCall
            ) {
                scheduleSupervisorGrantResolutionFollowUp(
                    record: blocked,
                    project: project,
                    reasonCode: blocked.denyCode,
                    summary: blocked.resultSummary
                )
            }
            supervisorSkillExecutionTasks.removeValue(forKey: requestId)

        case .failed:
            if let blocked = applySupervisorSkillCallStatus(
                requestId: requestId,
                ctx: ctx,
                project: project,
                status: .blocked,
                stepStatus: .blocked,
                resultSummary: access.reasonCode?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                    ? "Hub 授权请求失败：\(access.reasonCode!.trimmingCharacters(in: .whitespacesAndNewlines))"
                    : "Hub 授权请求失败",
                denyCode: access.reasonCode?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "grant_request_failed",
                requiredCapability: requiredCapability,
                grantRequestId: normalizedGrantRequestId,
                grantId: nil,
                updatedAtMs: nowMs,
                triggerSource: .grantResolution,
                toolCall: toolCall
            ) {
                scheduleSupervisorGrantResolutionFollowUp(
                    record: blocked,
                    project: project,
                    reasonCode: blocked.denyCode,
                    summary: blocked.resultSummary
                )
            }
            supervisorSkillExecutionTasks.removeValue(forKey: requestId)
        }
    }

    func injectSupervisorGrant(
        into toolCall: ToolCall,
        grantId: String,
        capability: String
    ) -> ToolCall {
        guard !grantId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return toolCall
        }
        guard capability.lowercased().contains("web.fetch") else {
            return toolCall
        }
        var args = toolCall.args
        args["grant_id"] = .string(grantId.trimmingCharacters(in: .whitespacesAndNewlines))
        return ToolCall(id: toolCall.id, tool: toolCall.tool, args: args)
    }

    func resumeSupervisorSkillCallsAfterGrantAction(
        grant: SupervisorPendingGrant,
        approve: Bool,
        result: HubIPCClient.PendingGrantActionResult
    ) async {
        let projectId = grant.projectId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !projectId.isEmpty else { return }
        guard let project = knownProjects().first(where: { $0.projectId == projectId }),
              let ctx = appModel?.projectContext(for: projectId) else {
            return
        }

        let capability = grant.capability.trimmingCharacters(in: .whitespacesAndNewlines)
        let grantRequestId = grant.grantRequestId.trimmingCharacters(in: .whitespacesAndNewlines)
        let snapshot = SupervisorProjectSkillCallStore.load(for: ctx)
        let matches = snapshot.calls.filter { record in
            guard record.status == .awaitingAuthorization else { return false }
            if !grantRequestId.isEmpty,
               record.grantRequestId?.trimmingCharacters(in: .whitespacesAndNewlines) == grantRequestId {
                return true
            }
            guard record.projectId == projectId else { return false }
            return record.requiredCapability?.trimmingCharacters(in: .whitespacesAndNewlines) == capability
        }
        guard !matches.isEmpty else { return }
        let remoteStateDirPath = matches.compactMap { record in
            normalizedSupervisorHubStateDirPath(record.hubStateDirPath)
        }.first
        await refreshResolvedSkillsCacheIfPossible(
            project: project,
            ctx: ctx,
            remoteStateDirPath: remoteStateDirPath
        )

        if !approve {
            let updatedAtMs = Int64((Date().timeIntervalSince1970 * 1000.0).rounded())
            for record in matches {
                if let blocked = applySupervisorSkillCallStatus(
                    requestId: record.requestId,
                    ctx: ctx,
                    project: project,
                    status: .blocked,
                    stepStatus: .blocked,
                    resultSummary: XTHubGrantPresentation.deniedStateSummary(
                        capability: capability.isEmpty ? (record.requiredCapability ?? "") : capability,
                        modelId: "",
                        deniedByUser: true
                    ),
                    denyCode: "grant_denied",
                    requiredCapability: capability.isEmpty ? record.requiredCapability : capability,
                    grantRequestId: grantRequestId.isEmpty ? record.grantRequestId : grantRequestId,
                    grantId: nil,
                    updatedAtMs: updatedAtMs,
                    triggerSource: .grantResolution,
                    toolCall: nil
                ) {
                    scheduleSupervisorGrantResolutionFollowUp(
                        record: blocked,
                        project: project,
                        reasonCode: blocked.denyCode,
                        summary: blocked.resultSummary
                    )
                }
            }
            return
        }

        guard result.ok else { return }
        let normalizedGrantRequestId = [
            result.grantRequestId,
            grant.grantRequestId
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .first(where: { !$0.isEmpty }) ?? ""
        let approvedGrantId = result.grantId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let nowMs = Int64((Date().timeIntervalSince1970 * 1000.0).rounded())
        let fallbackSeconds: Int = {
            guard let expiresAtMs = result.expiresAtMs, expiresAtMs > 0 else {
                return max(120, grant.requestedTtlSec > 0 ? grant.requestedTtlSec : 900)
            }
            let remaining = Int(((expiresAtMs / 1000.0) - Date().timeIntervalSince1970).rounded(.up))
            return max(120, remaining)
        }()

        var activatedGrantId = approvedGrantId
        if !capability.isEmpty {
            activatedGrantId = await ToolExecutor.activateHighRiskGrantForSupervisor(
                projectRoot: ctx.root,
                capability: capability,
                grantRequestId: normalizedGrantRequestId.isEmpty ? nil : normalizedGrantRequestId,
                approvedGrantId: approvedGrantId.isEmpty ? nil : approvedGrantId,
                fallbackSeconds: fallbackSeconds
            )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
        let resolvedGrantId = firstNonEmpty(
            activatedGrantId,
            approvedGrantId
        ) ?? ""

        if !capability.isEmpty, resolvedGrantId.isEmpty {
            for record in matches {
                if let blocked = applySupervisorSkillCallStatus(
                    requestId: record.requestId,
                    ctx: ctx,
                    project: project,
                    status: .blocked,
                    stepStatus: .blocked,
                    resultSummary: "Hub grant 已通过，但恢复这次受治理技能调用时未能激活执行 grant。",
                    denyCode: "grant_activation_failed",
                    requiredCapability: capability.isEmpty ? record.requiredCapability : capability,
                    grantRequestId: normalizedGrantRequestId.isEmpty ? record.grantRequestId : normalizedGrantRequestId,
                    grantId: nil,
                    updatedAtMs: nowMs,
                    triggerSource: .grantResolution,
                    toolCall: nil
                ) {
                    scheduleSupervisorGrantResolutionFollowUp(
                        record: blocked,
                        project: project,
                        reasonCode: blocked.denyCode,
                        summary: blocked.resultSummary
                    )
                }
            }
            return
        }

        for record in matches {
            switch mapSupervisorSkillToToolCall(
                skillId: record.skillId,
                payload: record.payload,
                requestId: record.requestId,
                projectId: project.projectId,
                projectName: project.displayName,
                projectRoot: ctx.root
            ) {
            case .failure:
                if let blocked = applySupervisorSkillCallStatus(
                    requestId: record.requestId,
                    ctx: ctx,
                    project: project,
                    status: .blocked,
                    stepStatus: .blocked,
                    resultSummary: "Hub grant 已通过，但恢复这次受治理技能调用时缺少可执行映射。",
                    denyCode: "skill_mapping_missing",
                    requiredCapability: capability.isEmpty ? record.requiredCapability : capability,
                    grantRequestId: normalizedGrantRequestId.isEmpty ? record.grantRequestId : normalizedGrantRequestId,
                    grantId: resolvedGrantId.isEmpty ? record.grantId : resolvedGrantId,
                    updatedAtMs: nowMs,
                    triggerSource: .grantResolution,
                    toolCall: nil
                ) {
                    scheduleSupervisorGrantResolutionFollowUp(
                        record: blocked,
                        project: project,
                        reasonCode: blocked.denyCode,
                        summary: blocked.resultSummary
                    )
                }

            case .success(let mapped):
                let resumedToolCall = injectSupervisorGrant(
                    into: mapped.toolCall,
                    grantId: resolvedGrantId,
                    capability: capability.isEmpty ? (record.requiredCapability ?? "") : capability
                )
                let resumedRecord = applySupervisorSkillCallStatus(
                    requestId: record.requestId,
                    ctx: ctx,
                    project: project,
                    status: .queued,
                    stepStatus: .pending,
                    resultSummary: "Hub grant 已通过，正在恢复这次受治理技能调用。",
                    denyCode: "",
                    requiredCapability: capability.isEmpty ? record.requiredCapability : capability,
                    grantRequestId: normalizedGrantRequestId.isEmpty ? record.grantRequestId : normalizedGrantRequestId,
                    grantId: resolvedGrantId.isEmpty ? record.grantId : resolvedGrantId,
                    updatedAtMs: nowMs,
                    triggerSource: .grantResolution,
                    toolCall: resumedToolCall
                )

                let hubBaseDir = HubPaths.baseDir()
                let task = Task { [weak self] in
                    await HubPaths.withPinnedBaseDirOverride(hubBaseDir) {
                        guard let self else { return }
                        await self.executeSupervisorSkillCall(
                            requestId: record.requestId,
                            project: project,
                            ctx: ctx,
                            toolCall: resumedToolCall,
                            allowPreviouslyApprovedAuthorization: true,
                            triggerSource: .grantResolution
                        )
                    }
                }
                supervisorSkillExecutionTasks[record.requestId] = task
                let displaySkill = resumedRecord.map(supervisorSkillDisplaySummary) ?? "技能调用"
                addProjectScopedSystemMessageIfVisible(
                    "✅ 已为项目 \(project.displayName) 取得 Hub 授权并恢复技能调用：\(displaySkill)（\(userFacingRequestIdentifier(record.requestId))）",
                    project: project
                )
            }
        }
    }
}
