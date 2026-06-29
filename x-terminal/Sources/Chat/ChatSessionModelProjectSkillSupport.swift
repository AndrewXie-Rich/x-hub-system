import Foundation

extension ChatSessionModel {
    func projectSkillProgressLine(for dispatch: XTProjectMappedSkillDispatch) -> String {
        let skillId = truncateProgressToken(dispatch.skillId, max: 40)
        switch dispatch.toolCall.tool {
        case .browser_read:
            return "我在通过技能 \(skillId) 读取网页内容。"
        case .skills_search:
            return "我在通过技能 \(skillId) 查询技能目录。"
        case .skills_pin:
            return "我在通过技能 \(skillId) 固定技能依赖。"
        case .summarize:
            return "我在通过技能 \(skillId) 总结内容。"
        case .supervisorVoicePlayback:
            return "我在通过技能 \(skillId) 处理 Supervisor 语音播放。"
        case .run_local_task:
            let canonicalSkillId = AXSkillsLibrary.canonicalSupervisorSkillID(dispatch.skillId).lowercased()
            switch canonicalSkillId {
            case "local-embeddings":
                return "我在通过技能 \(skillId) 生成向量嵌入。"
            case "local-transcribe":
                return "我在通过技能 \(skillId) 转写音频内容。"
            case "local-vision":
                return "我在通过技能 \(skillId) 理解图片内容。"
            case "local-ocr":
                return "我在通过技能 \(skillId) 提取图片里的文字。"
            case "local-tts":
                return "我在通过技能 \(skillId) 合成本地语音。"
            default:
                switch dispatch.toolCall.args["task_kind"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
                case "embedding":
                    return "我在通过技能 \(skillId) 生成向量嵌入。"
                case "speech_to_text":
                    return "我在通过技能 \(skillId) 转写音频内容。"
                case "text_to_speech":
                    return "我在通过技能 \(skillId) 合成本地语音。"
                case "vision_understand":
                    return "我在通过技能 \(skillId) 理解图片内容。"
                case "ocr":
                    return "我在通过技能 \(skillId) 提取图片里的文字。"
                default:
                    return "我在通过技能 \(skillId) 执行本地模型任务。"
                }
            }
        case .deviceBrowserControl:
            return "我在通过技能 \(skillId) 操作浏览器。"
        case .web_fetch, .web_search:
            return "我在通过技能 \(skillId) 获取联网信息。"
        default:
            return "我在通过技能 \(skillId) 调用 \(dispatch.toolName)。"
        }
    }

    func recordProjectSkillResolvedDispatches(
        ctx: AXProjectContext,
        dispatches: [XTProjectMappedSkillDispatch],
        resolutionSource: String
    ) {
        guard !dispatches.isEmpty else { return }
        let now = Date().timeIntervalSince1970
        for dispatch in dispatches {
            AXProjectStore.appendRawLog(
                appendProjectSkillDispatchMetadata(
                    to: [
                    "type": "project_skill_call",
                    "created_at": now,
                    "status": "resolved",
                    "resolution_source": resolutionSource,
                    "request_id": dispatch.toolCall.id,
                    "skill_id": dispatch.skillId,
                    "tool_name": dispatch.toolName,
                    "tool_args": jsonArgs(dispatch.toolCall.args)
                    ],
                    dispatch: dispatch,
                    ctx: ctx
                ),
                for: ctx
            )
        }
    }

    func recordProjectSkillAuthorizationOutcome(
        ctx: AXProjectContext,
        dispatch: XTProjectMappedSkillDispatch,
        config: AXProjectConfig,
        decision: XTToolAuthorizationDecision
    ) {
        let resultSummary = xtToolAuthorizationDeniedSummaryText(
            call: dispatch.toolCall,
            decision: decision
        )
        var row = appendProjectSkillDispatchMetadata(
            to: [
            "type": "project_skill_call",
            "created_at": Date().timeIntervalSince1970,
            "status": "blocked",
            "request_id": dispatch.toolCall.id,
            "skill_id": dispatch.skillId,
            "tool_name": dispatch.toolName,
            "tool_args": jsonArgs(dispatch.toolCall.args),
            "result_summary": resultSummary,
            "authorization_disposition": decision.disposition.rawValue,
            "deny_code": decision.denyCode,
            "detail": decision.detail,
            "policy_source": decision.policySource,
            "policy_reason": decision.policyReason
            ],
            dispatch: dispatch,
            ctx: ctx
        )
        let readiness = projectSkillExecutionReadiness(ctx: ctx, dispatch: dispatch)
        appendProjectSkillReadiness(to: &row, readiness: readiness)
        if let runtimeDecision = decision.runtimePolicyDecision {
            let summary = xtToolRuntimePolicyDeniedSummary(
                call: dispatch.toolCall,
                projectRoot: ctx.root,
                config: config,
                decision: runtimeDecision,
                effectiveRuntimeSurface: decision.runtimeEffectiveSurface
            )
            appendGovernanceTruthSnapshot(to: &row, from: summary)
        }
        AXProjectStore.appendRawLog(row, for: ctx)
    }

    func recordProjectSkillManualRejection(
        ctx: AXProjectContext,
        dispatch: XTProjectMappedSkillDispatch
    ) {
        AXProjectStore.appendRawLog(
            appendProjectSkillDispatchMetadata(
                to: [
                "type": "project_skill_call",
                "created_at": Date().timeIntervalSince1970,
                "status": "blocked",
                "request_id": dispatch.toolCall.id,
                "skill_id": dispatch.skillId,
                "tool_name": dispatch.toolName,
                "tool_args": jsonArgs(dispatch.toolCall.args),
                "authorization_disposition": XTToolAuthorizationDisposition.deny.rawValue,
                "deny_code": "user_rejected_pending_tool_approval",
                "detail": "User rejected the pending approval before execution.",
                "policy_source": "user_decision",
                "policy_reason": "manual_reject"
                ],
                dispatch: dispatch,
                ctx: ctx
            ),
            for: ctx
        )
    }

    func recordProjectSkillAwaitingApproval(
        ctx: AXProjectContext,
        dispatchesByCallID: [String: XTProjectMappedSkillDispatch],
        toolCalls: [ToolCall]
    ) {
        let now = Date().timeIntervalSince1970
        let config = (try? AXProjectStore.loadOrCreateConfig(for: ctx)) ?? .default(forProjectRoot: ctx.root)
        let projectId = AXProjectRegistryStore.projectId(forRoot: ctx.root)
        let projectName = currentProjectDisplayName(ctx: ctx)
        refreshResolvedSkillsCacheSynchronouslyIfPossible(
            ctx: ctx,
            projectId: projectId,
            projectName: projectName,
            remoteStateDirPath: dispatchesByCallID.values.compactMap(\.hubStateDirPath).first
        )
        let profileSnapshot = AXSkillsLibrary.projectEffectiveSkillProfileSnapshot(
            projectId: projectId,
            projectName: projectName,
            projectRoot: ctx.root,
            config: config,
            hubBaseDir: HubPaths.baseDir()
        )
        for call in toolCalls {
            guard let dispatch = dispatchesByCallID[call.id] else { continue }
            let readiness = trustedAutomationLocalApprovalReadinessIfNeeded(
                projectSkillExecutionReadiness(
                    ctx: ctx,
                    dispatch: dispatch,
                    config: config
                ),
                call: call,
                ctx: ctx,
                config: config
            )
            let deltaApproval = XTSkillCapabilityProfileSupport.deltaApproval(
                requestId: dispatch.toolCall.id,
                projectId: projectId,
                projectName: projectName,
                requestedSkillId: dispatch.requestedSkillId?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                    ? dispatch.requestedSkillId ?? dispatch.skillId
                    : dispatch.skillId,
                effectiveSkillId: dispatch.skillId,
                toolName: dispatch.toolName,
                requestedCapabilityFamilies: dispatch.capabilityFamilies.isEmpty
                    ? readiness?.capabilityFamilies ?? []
                    : dispatch.capabilityFamilies,
                currentSnapshot: profileSnapshot,
                reason: readiness?.reasonCode.isEmpty == false
                    ? readiness?.reasonCode ?? ""
                    : "waiting for local governed approval"
            )
            var row = appendProjectSkillDispatchMetadata(
                to: [
                    "type": "project_skill_call",
                    "created_at": now,
                    "status": "awaiting_approval",
                    "request_id": dispatch.toolCall.id,
                    "skill_id": dispatch.skillId,
                    "tool_name": dispatch.toolName,
                    "tool_args": jsonArgs(dispatch.toolCall.args)
                ],
                dispatch: dispatch,
                ctx: ctx
            )
            appendProjectSkillReadiness(to: &row, readiness: readiness)
            appendProjectSkillDeltaApproval(to: &row, deltaApproval: deltaApproval)
            AXProjectStore.appendRawLog(
                row,
                for: ctx
            )
        }
    }

    func trustedAutomationLocalApprovalReadinessIfNeeded(
        _ readiness: XTSkillExecutionReadiness?,
        call: ToolCall,
        ctx: AXProjectContext,
        config: AXProjectConfig
    ) -> XTSkillExecutionReadiness? {
        guard var updated = readiness else { return nil }
        let requiredGroups = xtTrustedAutomationRequiredDeviceToolGroups(for: [call])
        guard !requiredGroups.isEmpty else { return readiness }

        let permissionReadiness = AXTrustedAutomationPermissionOwnerReadiness.current()
        let status = config.trustedAutomationStatus(
            forProjectRoot: ctx.root,
            permissionReadiness: permissionReadiness,
            requiredDeviceToolGroups: requiredGroups
        )
        guard trustedAutomationProjectApprovalShouldUpdate(status: status) else {
            return readiness
        }

        updated.executionReadiness = XTSkillExecutionReadinessState.localApprovalRequired.rawValue
        updated.runnableNow = false
        updated.denyCode = xtTrustedAutomationLocalApprovalRequiredDenyCode
        updated.reasonCode = "local approval will bind the current trusted automation device and enable requested device tool groups"
        updated.stateLabel = XTSkillCapabilityProfileSupport.readinessLabel(
            XTSkillExecutionReadinessState.localApprovalRequired.rawValue
        )
        if updated.approvalFloor.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || updated.approvalFloor == XTSkillApprovalFloor.none.rawValue {
            updated.approvalFloor = XTSkillApprovalFloor.localApproval.rawValue
        }
        updated.requiredRuntimeSurfaces = XTSkillCapabilityProfileSupport.normalizedStrings(
            updated.requiredRuntimeSurfaces + ["trusted_device_runtime"]
        )
        updated.unblockActions = XTSkillCapabilityProfileSupport.normalizedUnblockActions(
            updated.unblockActions + ["request_local_approval", "open_trusted_automation_doctor"]
        )
        return updated
    }

    func recordProjectSkillExecutionResult(
        ctx: AXProjectContext,
        dispatch: XTProjectMappedSkillDispatch,
        result: ToolResult
    ) {
        var entry = appendProjectSkillDispatchMetadata(
            to: [
            "type": "project_skill_call",
            "created_at": Date().timeIntervalSince1970,
            "status": result.ok ? "completed" : "failed",
            "request_id": dispatch.toolCall.id,
            "skill_id": dispatch.skillId,
            "tool_name": dispatch.toolName,
            "tool_args": jsonArgs(dispatch.toolCall.args),
            "ok": result.ok,
            "result_summary": ToolResultHumanSummary.body(for: result)
            ],
            dispatch: dispatch,
            ctx: ctx
        )
        appendProjectSkillReadiness(
            to: &entry,
            readiness: projectSkillExecutionReadiness(ctx: ctx, dispatch: dispatch)
        )
        if let structured = ToolResultHumanSummary.structuredSummary(for: result) {
            entry["result_structured_summary"] = jsonArgs(structured)
        }
        AXProjectStore.appendRawLog(entry, for: ctx)
    }

    func appendProjectSkillDispatchMetadata(
        to row: [String: Any],
        dispatch: XTProjectMappedSkillDispatch,
        ctx: AXProjectContext
    ) -> [String: Any] {
        var out = row
        if let requestedSkillId = dispatch.requestedSkillId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !requestedSkillId.isEmpty {
            out["requested_skill_id"] = requestedSkillId
        }
        if !dispatch.intentFamilies.isEmpty {
            out["intent_families"] = dispatch.intentFamilies
        }
        if !dispatch.capabilityFamilies.isEmpty {
            out["capability_families"] = dispatch.capabilityFamilies
        }
        if !dispatch.capabilityProfiles.isEmpty {
            out["capability_profiles"] = dispatch.capabilityProfiles
        }
        if !dispatch.grantFloor.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            out["grant_floor"] = dispatch.grantFloor
        }
        if !dispatch.approvalFloor.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            out["approval_floor"] = dispatch.approvalFloor
        }
        if let routingReasonCode = dispatch.routingReasonCode?.trimmingCharacters(in: .whitespacesAndNewlines),
           !routingReasonCode.isEmpty {
            out["routing_reason_code"] = routingReasonCode
        }
        if let routingExplanation = dispatch.routingExplanation?.trimmingCharacters(in: .whitespacesAndNewlines),
           !routingExplanation.isEmpty {
            out["routing_explanation"] = routingExplanation
        }
        if let hubStateDirPath = projectSkillHubStateDirPath(ctx: ctx, dispatch: dispatch) {
            out["hub_state_dir_path"] = hubStateDirPath
        }
        if let requiredCapability = projectSkillRequiredHubCapability(for: dispatch.toolCall),
           !requiredCapability.isEmpty {
            out["required_capability"] = requiredCapability
        }
        return out
    }

    func appendProjectSkillReadiness(
        to row: inout [String: Any],
        readiness: XTSkillExecutionReadiness?
    ) {
        guard let readiness else { return }
        if (row["deny_code"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false,
           !readiness.denyCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            row["deny_code"] = readiness.denyCode
        }
        row["execution_readiness"] = readiness.executionReadiness
        row["state_label"] = readiness.stateLabel
        row["grant_floor"] = readiness.grantFloor
        row["approval_floor"] = readiness.approvalFloor
        row["required_runtime_surfaces"] = readiness.requiredRuntimeSurfaces
        row["unblock_actions"] = readiness.unblockActions
        if !readiness.reasonCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            row["readiness_reason_code"] = readiness.reasonCode
        }
    }

    func appendProjectSkillDeltaApproval(
        to row: inout [String: Any],
        deltaApproval: XTSkillProfileDeltaApproval?
    ) {
        guard let deltaApproval else { return }
        row["approval_summary"] = deltaApproval.summary
        row["current_runnable_profiles"] = deltaApproval.currentRunnableProfiles
        row["requested_profiles"] = deltaApproval.requestedProfiles
        row["delta_profiles"] = deltaApproval.deltaProfiles
        row["current_runnable_capability_families"] = deltaApproval.currentRunnableCapabilityFamilies
        row["requested_capability_families"] = deltaApproval.requestedCapabilityFamilies
        row["delta_capability_families"] = deltaApproval.deltaCapabilityFamilies
        row["grant_floor"] = deltaApproval.grantFloor
        row["approval_floor"] = deltaApproval.approvalFloor
    }

    func projectSkillExecutionReadiness(
        ctx: AXProjectContext,
        dispatch: XTProjectMappedSkillDispatch,
        config: AXProjectConfig? = nil
    ) -> XTSkillExecutionReadiness? {
        let skillId = dispatch.skillId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !skillId.isEmpty else { return nil }
        let projectId = AXProjectRegistryStore.projectId(forRoot: ctx.root)
        let projectName = currentProjectDisplayName(ctx: ctx)
        let resolvedConfig = config ?? ((try? AXProjectStore.loadOrCreateConfig(for: ctx)) ?? .default(forProjectRoot: ctx.root))
        refreshResolvedSkillsCacheSynchronouslyIfPossible(
            ctx: ctx,
            projectId: projectId,
            projectName: projectName,
            remoteStateDirPath: dispatch.hubStateDirPath
        )
        let registryItem = AXSkillsLibrary.preferredSupervisorSkillRegistrySnapshot(
            projectId: projectId,
            projectName: projectName,
            projectRoot: ctx.root,
            hubBaseDir: HubPaths.baseDir()
        )?.items.first(where: {
            AXSkillsLibrary.canonicalSupervisorSkillID($0.skillId) == skillId
        })
        let baseReadiness = AXSkillsLibrary.skillExecutionReadiness(
            skillId: skillId,
            projectId: projectId,
            projectName: projectName,
            projectRoot: ctx.root,
            config: resolvedConfig,
            registryItem: registryItem,
            hubBaseDir: HubPaths.baseDir()
        )
        let hasExplicitGrant = dispatch.toolCall.args["grant_id"]?.stringValue?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty == false
        return XTSkillCapabilityProfileSupport.effectiveReadinessForRequestScopedGrantOverride(
            readiness: baseReadiness,
            registryItem: registryItem,
            toolCall: dispatch.toolCall,
            hasExplicitGrant: hasExplicitGrant,
            localAutoApproveEnabled: resolvedConfig.governedAutoApproveLocalToolCalls
        )
    }

    func projectSkillRequiredHubCapability(
        for toolCall: ToolCall
    ) -> String? {
        switch toolCall.tool {
        case .web_fetch, .web_search, .browser_read:
            return "web.fetch"
        case .deviceBrowserControl:
            if let action = toolCall.args["action"]?.stringValue?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased(),
               action == "extract" {
                return "web.fetch"
            }
            return nil
        case .summarize:
            if let url = toolCall.args["url"]?.stringValue?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !url.isEmpty {
                return "web.fetch"
            }
            return nil
        default:
            return nil
        }
    }
}
