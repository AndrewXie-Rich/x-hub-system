import Foundation

struct SupervisorSkillFullRecord: Identifiable, Equatable, Sendable {
    var requestID: String
    var projectName: String
    var title: String
    var latestStatus: String
    var latestStatusLabel: String
    var requestMetadata: [ProjectSkillRecordField]
    var approvalFields: [ProjectSkillRecordField]
    var governanceFields: [ProjectSkillRecordField]
    var skillPayloadText: String?
    var toolArgumentsText: String?
    var resultFields: [ProjectSkillRecordField]
    var rawOutputPreview: String?
    var rawOutput: String?
    var evidenceFields: [ProjectSkillRecordField]
    var approvalHistory: [ProjectSkillRecordTimelineEntry]
    var timeline: [ProjectSkillRecordTimelineEntry]
    var uiReviewAgentEvidenceFields: [ProjectSkillRecordField] = []
    var uiReviewAgentEvidenceText: String? = nil
    var supervisorEvidenceJSON: String?
    var guidanceContract: SupervisorGuidanceContractSummary? = nil

    var id: String { "\(projectName):\(requestID)" }
}

enum SupervisorSkillActivityPresentation {
    static func title(for item: SupervisorManager.SupervisorRecentSkillActivity) -> String {
        switch normalizedStatus(item.status) {
        case "completed":
            return "技能调用已完成"
        case "failed":
            return "技能调用失败"
        case "blocked":
            return "技能调用受阻"
        case "awaiting_authorization":
            return item.requiredCapability.isEmpty
                ? "等待本地审批"
                : "等待 Hub 授权 · \(humanCapabilityLabel(item.requiredCapability))"
        case "running":
            return "技能调用进行中"
        case "queued":
            return "技能调用排队中"
        case "canceled":
            return "技能调用已取消"
        default:
            return "技能调用更新"
        }
    }

    static func statusLabel(for item: SupervisorManager.SupervisorRecentSkillActivity) -> String {
        statusLabel(for: item.status)
    }

    static func statusLabel(for rawStatus: String) -> String {
        switch normalizedStatus(rawStatus) {
        case "queued":
            return "排队中"
        case "running":
            return "进行中"
        case "awaiting_authorization":
            return "等待审批"
        case "completed":
            return "已完成"
        case "failed":
            return "失败"
        case "blocked":
            return "受阻"
        case "canceled":
            return "已取消"
        default:
            return rawStatus.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "未知" : rawStatus
        }
    }

    static func iconName(for item: SupervisorManager.SupervisorRecentSkillActivity) -> String {
        switch normalizedStatus(item.status) {
        case "queued":
            return "clock.fill"
        case "running":
            return "ellipsis.circle.fill"
        case "awaiting_authorization":
            return item.requiredCapability.isEmpty ? "hand.raised.fill" : "lock.shield.fill"
        case "completed":
            return "checkmark.circle.fill"
        case "failed":
            return "xmark.octagon.fill"
        case "blocked":
            return "lock.trianglebadge.exclamationmark.fill"
        case "canceled":
            return "slash.circle.fill"
        default:
            return "sparkles"
        }
    }

    static func toolBadge(for item: SupervisorManager.SupervisorRecentSkillActivity) -> String {
        displayToolName(item.toolName, tool: item.tool)
    }

    static func actionButtonTitle(for item: SupervisorManager.SupervisorRecentSkillActivity) -> String {
        switch normalizedStatus(item.status) {
        case "awaiting_authorization":
            return item.requiredCapability.isEmpty ? "打开审批" : "打开授权"
        default:
            if actionURLGovernanceDestination(item.actionURL) == .uiReview {
                return "打开 UI 审查"
            }
            return "打开项目"
        }
    }

    static func workflowLine(for item: SupervisorManager.SupervisorRecentSkillActivity) -> String? {
        let fields = [
            compactWorkflowToken(label: "job", value: item.record.jobId),
            compactWorkflowToken(label: "plan", value: item.record.planId),
            compactWorkflowToken(label: "step", value: item.record.stepId)
        ].compactMap { $0 }
        guard !fields.isEmpty else { return nil }
        return "工作流： " + fields.joined(separator: " · ")
    }

    static func routingLine(for item: SupervisorManager.SupervisorRecentSkillActivity) -> String? {
        routingLine(
            requestedSkillId: item.requestedSkillId,
            effectiveSkillId: item.skillId,
            payload: item.record.payload,
            routingReasonCode: item.record.routingReasonCode,
            routingExplanation: item.record.routingExplanation
        )
    }

    static func routingLine(
        requestedSkillId: String?,
        effectiveSkillId: String,
        payload: [String: JSONValue] = [:],
        routingReasonCode: String? = nil,
        routingExplanation: String? = nil
    ) -> String? {
        guard let summary = routingSummary(
            requestedSkillId: requestedSkillId,
            effectiveSkillId: effectiveSkillId,
            payload: payload,
            routingReasonCode: routingReasonCode,
            routingExplanation: routingExplanation
        ) else {
            return nil
        }
        return "路由： \(summary)"
    }

    static func routingSummary(
        requestedSkillId: String?,
        effectiveSkillId: String,
        payload: [String: JSONValue] = [:],
        routingReasonCode: String? = nil,
        routingExplanation: String? = nil
    ) -> String? {
        skillRoutingSummary(
            requestedSkillId: requestedSkillId,
            effectiveSkillId: effectiveSkillId,
            payload: payload,
            routingReasonCode: routingReasonCode,
            routingExplanation: routingExplanation
        )
    }

    static func displaySkillSummary(
        requestedSkillId: String?,
        effectiveSkillId: String,
        payload: [String: JSONValue] = [:],
        routingReasonCode: String? = nil,
        routingExplanation: String? = nil
    ) -> String {
        let effective = effectiveSkillId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !effective.isEmpty else { return "" }
        return routingSummary(
            requestedSkillId: requestedSkillId,
            effectiveSkillId: effective,
            payload: payload,
            routingReasonCode: routingReasonCode,
            routingExplanation: routingExplanation
        ) ?? effective
    }

    static func displaySkillSummary(
        for item: SupervisorManager.SupervisorRecentSkillActivity
    ) -> String {
        displaySkillSummary(
            requestedSkillId: item.requestedSkillId,
            effectiveSkillId: item.skillId,
            payload: item.record.payload,
            routingReasonCode: item.record.routingReasonCode,
            routingExplanation: item.record.routingExplanation
        )
    }

    static func routingNarrative(
        requestedSkillId: String?,
        effectiveSkillId: String,
        payload: [String: JSONValue] = [:],
        routingReasonCode: String? = nil,
        routingExplanation: String? = nil
    ) -> String? {
        let effective = effectiveSkillId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !effective.isEmpty else { return nil }
        guard let resolution = resolvedRoutingResolution(
            requestedSkillId: requestedSkillId,
            effectiveSkillId: effective,
            payload: payload,
            routingReasonCode: routingReasonCode,
            routingExplanation: routingExplanation
        ) else {
            return nil
        }

        let requested = nonEmpty(requestedSkillId)
        let reasonCode = nonEmpty(resolution.reasonCode)

        switch reasonCode {
        case "requested_alias_normalized":
            guard let requested else { return nil }
            return "系统先把 \(requested) 规范成 \(effective)"
        case "preferred_builtin_selected":
            if isBrowserEntrypoint(requested) {
                return "浏览器入口会先收敛到受治理内建 \(effective) 再执行"
            }
            if isBrowserWrapper(requested) {
                return "浏览器 wrapper 会优先切到受治理内建 \(effective) 再执行"
            }
            return "系统会优先切到受治理内建 \(effective) 再执行"
        case "compatible_builtin_selected":
            return "当前由兼容内建 \(effective) 承接这个技能请求"
        case "requested_skill_routed":
            guard let requested else { return nil }
            return "系统已把 \(requested) 路由到 \(effective)"
        default:
            if let requested, requested.caseInsensitiveCompare(effective) != .orderedSame {
                return "系统会把 \(requested) 交给 \(effective) 执行"
            }
            if nonEmpty(resolution.explanation) != nil {
                return "系统已按当前兼容路由执行"
            }
            return nil
        }
    }

    static func routingReasonText(_ rawReasonCode: String?) -> String? {
        switch nonEmpty(rawReasonCode) {
        case "requested_alias_normalized":
            return "请求技能先归一到标准技能"
        case "preferred_builtin_selected":
            return "系统优先切到受治理内建"
        case "compatible_builtin_selected":
            return "系统改由兼容内建承接"
        case "requested_skill_routed":
            return "系统把请求路由到兼容技能"
        default:
            return nil
        }
    }

    static func displayRequestMetadataFields(
        _ fields: [ProjectSkillRecordField]
    ) -> [ProjectSkillRecordField] {
        let requestedSkillId = fields.first(where: { $0.label == "requested_skill_id" })?.value
        let effectiveSkillId = fields.first(where: { $0.label == "skill_id" })?.value ?? ""
        let routingReasonCode = fields.first(where: { $0.label == "routing_reason_code" })?.value
        let routingExplanation = fields.first(where: { $0.label == "routing_explanation" })?.value
        let routingNarrative = routingNarrative(
            requestedSkillId: requestedSkillId,
            effectiveSkillId: effectiveSkillId,
            routingReasonCode: routingReasonCode,
            routingExplanation: routingExplanation
        )

        return fields.map { field in
            switch field.label {
            case "requested_skill_id":
                return ProjectSkillRecordField(label: "请求技能", value: field.value)
            case "skill_id":
                return ProjectSkillRecordField(label: "生效技能", value: field.value)
            case "routing_resolution":
                return ProjectSkillRecordField(label: "路由", value: field.value)
            case "routing_reason_code":
                return ProjectSkillRecordField(
                    label: "路由判定",
                    value: routingReasonText(field.value) ?? field.value
                )
            case "routing_explanation":
                return ProjectSkillRecordField(
                    label: "路由说明",
                    value: routingNarrative ?? field.value
                )
            default:
                return field
            }
        }
    }

    static func governanceLine(for item: SupervisorManager.SupervisorRecentSkillActivity) -> String? {
        guard let governance = item.governance else { return nil }
        var parts: [String] = []
        if let verdict = governance.latestReviewVerdict?.displayName {
            parts.append(verdict)
        }
        if let level = governance.latestReviewLevel?.displayName {
            parts.append(level)
        }
        if let tier = governance.effectiveSupervisorTier?.displayName {
            parts.append(tier)
        }
        if let depth = governance.effectiveWorkOrderDepth?.displayName {
            parts.append(depth)
        }
        let workOrderRef = nonEmpty(governance.workOrderRef)
        if let workOrderRef {
            parts.append("work_order=\(workOrderRef)")
        }
        guard !parts.isEmpty else { return nil }
        return "治理： " + parts.joined(separator: " · ")
    }

    static func followUpRhythmLine(for item: SupervisorManager.SupervisorRecentSkillActivity) -> String? {
        guard let governance = item.governance else { return nil }
        guard let summary = nonEmpty(governance.followUpRhythmSummary) else { return nil }
        return "跟进节奏： \(summary)"
    }

    static func pendingGuidanceLine(for item: SupervisorManager.SupervisorRecentSkillActivity) -> String? {
        guard let governance = item.governance else { return nil }
        guard let ackStatus = governance.pendingGuidanceAckStatus else { return nil }
        var parts = ["指导： \(ackStatus.displayName)"]
        parts.append(governance.pendingGuidanceRequired ? "必答" : "可选")
        if let latestDelivery = governance.latestGuidanceDeliveryMode?.displayName {
            parts.append(latestDelivery)
        }
        let guidanceId = nonEmpty(governance.pendingGuidanceId) ?? nonEmpty(governance.latestGuidanceId)
        if let guidanceId {
            parts.append("id=\(guidanceId)")
        }
        return parts.joined(separator: " · ")
    }

    static func guidanceContractLine(for item: SupervisorManager.SupervisorRecentSkillActivity) -> String? {
        guard let contract = item.governance?.guidanceContract else { return nil }
        return SupervisorGuidanceContractLinePresentation.contractLine(for: contract)
    }

    static func guidanceNextSafeActionLine(for item: SupervisorManager.SupervisorRecentSkillActivity) -> String? {
        guard let contract = item.governance?.guidanceContract else { return nil }
        return SupervisorGuidanceContractLinePresentation.nextSafeActionLine(for: contract)
    }

    static func body(for item: SupervisorManager.SupervisorRecentSkillActivity) -> String {
        let displaySkill = displaySkillSummary(for: item)
        let skillLabel = displaySkill.isEmpty
            ? "这次技能调用"
            : "技能 \(displaySkill)"
        let toolLabel = toolBadge(for: item)
        let target = item.toolSummary.trimmingCharacters(in: .whitespacesAndNewlines)

        switch normalizedStatus(item.status) {
        case "queued":
            if !item.resultSummary.isEmpty { return item.resultSummary }
            return target.isEmpty
                ? "\(skillLabel)已进入队列，等待执行\(toolLabel)。"
                : "\(skillLabel)已进入队列，等待对 \(target) 执行\(toolLabel)。"
        case "running":
            if !item.resultSummary.isEmpty { return item.resultSummary }
            return target.isEmpty
                ? "\(skillLabel)正在执行\(toolLabel)。"
                : "\(skillLabel)正在对 \(target) 执行\(toolLabel)。"
        case "awaiting_authorization":
            return XTGuardrailMessagePresentation.awaitingApprovalBody(
                toolLabel: toolLabel,
                target: target,
                requiredCapability: item.requiredCapability,
                denyCode: item.denyCode
            )
        case "completed":
            if !item.resultSummary.isEmpty { return item.resultSummary }
            return "\(skillLabel)已通过\(toolLabel)完成。"
        case "failed":
            if !item.denyCode.isEmpty || !item.policySource.isEmpty {
                return XTGuardrailMessagePresentation.blockedBody(
                    tool: item.tool,
                    toolLabel: toolLabel,
                    denyCode: item.denyCode,
                    policySource: item.policySource,
                    policyReason: item.policyReason,
                    requiredCapability: item.requiredCapability,
                    fallbackSummary: item.resultSummary
                )
            }
            if !item.resultSummary.isEmpty { return item.resultSummary }
            return "\(skillLabel)在执行\(toolLabel)时失败。"
        case "blocked":
            return XTGuardrailMessagePresentation.blockedBody(
                tool: item.tool,
                toolLabel: toolLabel,
                denyCode: item.denyCode,
                policySource: item.policySource,
                policyReason: item.policyReason,
                requiredCapability: item.requiredCapability,
                fallbackSummary: item.resultSummary
            )
        case "canceled":
            if !item.resultSummary.isEmpty { return item.resultSummary }
            return "\(skillLabel)已取消。"
        default:
            if !item.denyCode.isEmpty || !item.policySource.isEmpty {
                return XTGuardrailMessagePresentation.blockedBody(
                    tool: item.tool,
                    toolLabel: toolLabel,
                    denyCode: item.denyCode,
                    policySource: item.policySource,
                    policyReason: item.policyReason,
                    requiredCapability: item.requiredCapability,
                    fallbackSummary: item.resultSummary
                )
            }
            if !item.resultSummary.isEmpty { return item.resultSummary }
            return "\(skillLabel)已有更新。"
        }
    }

    static func diagnostics(for item: SupervisorManager.SupervisorRecentSkillActivity) -> String {
        var lines: [String] = [
            "project_id=\(item.projectId)",
            "project_name=\(item.projectName)",
            "request_id=\(item.requestId)"
        ]
        let record = item.record
        if !record.jobId.isEmpty { lines.append("job_id=\(record.jobId)") }
        if !record.planId.isEmpty { lines.append("plan_id=\(record.planId)") }
        if !record.stepId.isEmpty { lines.append("step_id=\(record.stepId)") }
        if !record.skillId.isEmpty { lines.append("skill_id=\(record.skillId)") }
        if !item.requestedSkillId.isEmpty { lines.append("requested_skill_id=\(item.requestedSkillId)") }
        if let routingLine = routingLine(for: item) {
            lines.append(routingLine)
        }
        if let routingReasonCode = nonEmpty(record.routingReasonCode) {
            lines.append("routing_reason_code=\(routingReasonCode)")
        }
        if let routingExplanation = nonEmpty(record.routingExplanation) {
            lines.append("routing_explanation=\(routingExplanation)")
        }
        if !record.toolName.isEmpty { lines.append("tool_name=\(record.toolName)") }
        if !record.status.rawValue.isEmpty { lines.append("status=\(record.status.rawValue)") }
        if !record.currentOwner.isEmpty { lines.append("current_owner=\(record.currentOwner)") }
        if !item.requiredCapability.isEmpty { lines.append("required_capability=\(item.requiredCapability)") }
        if !item.grantRequestId.isEmpty { lines.append("grant_request_id=\(item.grantRequestId)") }
        if !item.grantId.isEmpty { lines.append("grant_id=\(item.grantId)") }
        if !item.resultEvidenceRef.isEmpty { lines.append("result_evidence_ref=\(item.resultEvidenceRef)") }
        if !item.resultSummary.isEmpty { lines.append("result_summary=\(item.resultSummary)") }
        if !item.denyCode.isEmpty { lines.append("deny_code=\(item.denyCode)") }
        if !item.policySource.isEmpty { lines.append("policy_source=\(item.policySource)") }
        if !item.policyReason.isEmpty { lines.append("policy_reason=\(item.policyReason)") }
        if let guidanceContract = item.governance?.guidanceContract {
            lines.append("guidance_contract=\(guidanceContract.kind.rawValue)")
            if !guidanceContract.primaryBlocker.isEmpty {
                lines.append("primary_blocker=\(guidanceContract.primaryBlocker)")
            }
            if let uiReview = guidanceContract.uiReviewRepair {
                if !uiReview.repairAction.isEmpty {
                    lines.append("repair_action=\(uiReview.repairAction)")
                }
                if !uiReview.repairFocus.isEmpty {
                    lines.append("repair_focus=\(uiReview.repairFocus)")
                }
            }
            if guidanceContract.nextSafeActionText != "(none)" {
                lines.append("next_safe_action=\(guidanceContract.nextSafeActionText)")
            }
            if let actions = nonEmpty(guidanceContract.recommendedActionsText) {
                lines.append("recommended_actions=\(actions)")
            }
        }
        if let toolCall = item.toolCall,
           let data = try? JSONEncoder().encode(toolCall.args),
           let text = String(data: data, encoding: .utf8) {
            lines.append("tool_args=\(text)")
        }
        return lines.joined(separator: "\n")
    }

    static func isAwaitingLocalApproval(_ item: SupervisorManager.SupervisorRecentSkillActivity) -> Bool {
        normalizedStatus(item.status) == "awaiting_authorization" && item.requiredCapability.isEmpty
    }

    static func canRetry(_ item: SupervisorManager.SupervisorRecentSkillActivity) -> Bool {
        switch normalizedStatus(item.status) {
        case "failed", "blocked", "canceled":
            return true
        default:
            return false
        }
    }

    static func fullRecord(
        ctx: AXProjectContext,
        projectName: String,
        requestID: String
    ) -> SupervisorSkillFullRecord? {
        let snapshot = SupervisorProjectSkillCallStore.load(for: ctx)
        let record = snapshot.calls.first(where: {
            $0.requestId.trimmingCharacters(in: .whitespacesAndNewlines) == requestID.trimmingCharacters(in: .whitespacesAndNewlines)
        })
        let evidence = SupervisorSkillResultEvidenceStore.load(requestId: requestID, for: ctx)
        let events = loadEvents(ctx: ctx, requestID: requestID)
        let reviewSnapshot = SupervisorReviewNoteStore.load(for: ctx)
        let latestReview = reviewSnapshot.notes.first
        let latestGuidance = SupervisorGuidanceInjectionStore.latest(for: ctx)
        let pendingGuidance = SupervisorGuidanceInjectionStore.latestPendingAck(for: ctx)
        let activeGuidance = pendingGuidance ?? latestGuidance
        let guidanceReviewNote = activeGuidance.flatMap { guidance in
            reviewSnapshot.notes.first { $0.reviewId == guidance.reviewId }
        } ?? latestReview
        let guidanceContract = activeGuidance.flatMap { guidance in
            SupervisorGuidanceContractResolver.resolve(
                guidance: guidance,
                reviewNote: guidanceReviewNote
            )
        }
        let config = (try? AXProjectStore.loadOrCreateConfig(for: ctx)) ?? .default(forProjectRoot: ctx.root)
        let adaptationPolicy = AXProjectSupervisorAdaptationPolicy.default
        let strengthProfile = AXProjectAIStrengthAssessor.assess(
            ctx: ctx,
            adaptationPolicy: adaptationPolicy
        )
        let resolvedGovernance = xtResolveProjectGovernance(
            projectRoot: ctx.root,
            config: config,
            projectAIStrengthProfile: strengthProfile,
            adaptationPolicy: adaptationPolicy,
            permissionReadiness: .current()
        )

        guard record != nil || evidence != nil || !events.isEmpty else {
            return nil
        }

        let latestStatus = firstNonEmpty(
            record?.status.rawValue,
            events.last?.status,
            evidence?.status
        ) ?? ""
        let title = firstNonEmpty(
            displaySkillSummary(
                requestedSkillId: firstNonEmpty(record?.requestedSkillId, evidence?.requestedSkillId, events.last?.requestedSkillId),
                effectiveSkillId: firstNonEmpty(record?.skillId, evidence?.skillId, events.last?.skillId) ?? "",
                payload: record?.payload
                    ?? evidence?.toolArgs
                    ?? events.reversed().first(where: { !$0.toolArgs.isEmpty })?.toolArgs
                    ?? [:]
            ),
            firstNonEmpty(record?.skillId, evidence?.skillId)
        ) ?? "Supervisor Skill Record"
        let skillPayloadText: String? = {
            guard let record, !record.payload.isEmpty else { return nil }
            return AXProjectSkillActivityStore.prettyJSONString(for: record.payload)
        }()
        let toolArgumentsText = preferredToolArgumentsText(
            evidenceToolArgs: evidence?.toolArgs,
            eventToolArgs: events.reversed().first(where: { !$0.toolArgs.isEmpty })?.toolArgs
        )

        let requestMetadata = recordFields([
            ("project_name", projectName),
            ("request_id", requestID),
            ("project_id", firstNonEmpty(record?.projectId, evidence?.projectId, events.last?.projectId)),
            ("job_id", firstNonEmpty(record?.jobId, evidence?.jobId, events.last?.jobId)),
            ("plan_id", firstNonEmpty(record?.planId, evidence?.planId, events.last?.planId)),
            ("step_id", firstNonEmpty(record?.stepId, evidence?.stepId, events.last?.stepId)),
            ("requested_skill_id", firstNonEmpty(record?.requestedSkillId, evidence?.requestedSkillId, events.last?.requestedSkillId)),
            ("skill_id", firstNonEmpty(record?.skillId, evidence?.skillId, events.last?.skillId)),
            (
                "routing_resolution",
                resolvedRoutingResolution(
                    requestedSkillId: firstNonEmpty(record?.requestedSkillId, evidence?.requestedSkillId, events.last?.requestedSkillId),
                    effectiveSkillId: firstNonEmpty(record?.skillId, evidence?.skillId, events.last?.skillId) ?? "",
                    payload: record?.payload ?? [:],
                    routingReasonCode: firstNonEmpty(record?.routingReasonCode, evidence?.routingReasonCode, events.last?.routingReasonCode),
                    routingExplanation: firstNonEmpty(record?.routingExplanation, evidence?.routingExplanation, events.last?.routingExplanation)
                )?.summary
            ),
            ("routing_reason_code", firstNonEmpty(record?.routingReasonCode, evidence?.routingReasonCode, events.last?.routingReasonCode)),
            ("routing_explanation", firstNonEmpty(record?.routingExplanation, evidence?.routingExplanation, events.last?.routingExplanation)),
            ("tool_name", firstNonEmpty(record?.toolName, evidence?.toolName, events.last?.toolName)),
            ("latest_status", latestStatus),
            ("current_owner", record?.currentOwner),
            ("created_at", createdAtText(record: record, events: events)),
            ("updated_at", updatedAtText(record: record, evidence: evidence, events: events))
        ])

        let approvalFields = recordFields([
            ("required_capability", firstNonEmpty(record?.requiredCapability, events.last?.requiredCapability)),
            ("grant_request_id", firstNonEmpty(record?.grantRequestId, events.last?.grantRequestId)),
            ("grant_id", firstNonEmpty(record?.grantId, events.last?.grantId)),
            ("deny_code", firstNonEmpty(record?.denyCode, evidence?.denyCode, events.last?.denyCode)),
            ("policy_source", firstNonEmpty(record?.policySource, evidence?.policySource, events.last?.policySource)),
            ("policy_reason", firstNonEmpty(record?.policyReason, evidence?.policyReason, events.last?.policyReason)),
            ("trigger_source", firstNonEmpty(evidence?.triggerSource, events.last?.triggerSource))
        ])

        let governanceFields = recordFields([
            ("latest_review_id", latestReview?.reviewId),
            ("review_verdict", latestReview?.verdict.displayName),
            ("review_level", latestReview?.reviewLevel.displayName),
            (
                "supervisor_tier",
                latestReview?.effectiveSupervisorTier?.displayName
                    ?? pendingGuidance?.effectiveSupervisorTier?.displayName
                    ?? latestGuidance?.effectiveSupervisorTier?.displayName
            ),
            (
                "work_order_depth",
                latestReview?.effectiveWorkOrderDepth?.displayName
                    ?? pendingGuidance?.effectiveWorkOrderDepth?.displayName
                    ?? latestGuidance?.effectiveWorkOrderDepth?.displayName
            ),
            ("work_order_ref", firstNonEmpty(latestReview?.workOrderRef, pendingGuidance?.workOrderRef, latestGuidance?.workOrderRef)),
            ("latest_guidance_id", latestGuidance?.injectionId),
            ("latest_guidance_delivery", latestGuidance?.deliveryMode.displayName),
            ("pending_guidance_id", pendingGuidance?.injectionId),
            (
                "pending_guidance_ack",
                pendingGuidance.map {
                    "\($0.ackStatus.displayName) · \($0.ackRequired ? "required" : "optional")"
                }
            ),
            ("follow_up_rhythm", SupervisorReviewPolicyEngine.eventFollowUpCadenceLabel(governance: resolvedGovernance))
        ])

        let resultFields = recordFields([
            ("result_status", firstNonEmpty(evidence?.status, record?.status.rawValue, events.last?.status)),
            ("result_summary", firstNonEmpty(evidence?.resultSummary, record?.resultSummary, events.last?.resultSummary)),
            ("raw_output_chars", evidence.flatMap { $0.rawOutputChars > 0 ? String($0.rawOutputChars) : nil })
        ])

        let evidenceFields = recordFields([
            ("result_evidence_ref", firstNonEmpty(evidence?.resultEvidenceRef, record?.resultEvidenceRef, events.last?.resultEvidenceRef)),
            ("raw_output_ref", evidence?.rawOutputRef),
            ("audit_ref", firstNonEmpty(evidence?.auditRef, record?.auditRef, events.last?.auditRef))
        ])
        let uiReviewAgentEvidence = resolvedUIReviewAgentEvidence(
            ctx: ctx,
            evidence: evidence,
            events: events
        )
        let uiReviewAgentEvidenceFields = uiReviewAgentEvidence.map { snapshot in
            recordFields([
                ("ui_review_agent_evidence_ref", resolvedUIReviewAgentEvidenceRef(evidence: evidence, events: events)),
                ("review_ref", snapshot.reviewRef),
                ("bundle_ref", snapshot.bundleRef),
                ("verdict", snapshot.verdict.rawValue),
                ("confidence", snapshot.confidence.rawValue),
                ("sufficient_evidence", snapshot.sufficientEvidence ? "true" : "false"),
                ("objective_ready", snapshot.objectiveReady ? "true" : "false"),
                ("issue_codes", compactIssueCodesText(snapshot.issueCodes)),
                ("summary", snapshot.summary),
                ("audit_ref", snapshot.auditRef)
            ])
        } ?? []

        let timeline = events.enumerated().map { index, event in
            timelineEntry(for: event, fallbackIndex: index)
        }
        let approvalHistory = timeline.filter { entry in
            let normalized = normalizedStatus(entry.status)
            return normalized == "awaiting_authorization" || normalized == "blocked"
        }

        return SupervisorSkillFullRecord(
            requestID: requestID,
            projectName: projectName,
            title: title,
            latestStatus: latestStatus,
            latestStatusLabel: statusLabel(for: latestStatus),
            requestMetadata: requestMetadata,
            approvalFields: approvalFields,
            governanceFields: governanceFields,
            skillPayloadText: skillPayloadText,
            toolArgumentsText: toolArgumentsText,
            resultFields: resultFields,
            rawOutputPreview: nonEmpty(evidence?.rawOutputPreview),
            rawOutput: nonEmpty(evidence?.rawOutput),
            evidenceFields: evidenceFields,
            approvalHistory: approvalHistory,
            timeline: timeline,
            uiReviewAgentEvidenceFields: uiReviewAgentEvidenceFields,
            uiReviewAgentEvidenceText: uiReviewAgentEvidence?.renderedText(),
            supervisorEvidenceJSON: evidence.map(encodedJSONText),
            guidanceContract: guidanceContract
        )
    }

    static func fullRecordText(_ record: SupervisorSkillFullRecord) -> String {
        var lines: [String] = [
            "Supervisor 技能完整记录",
            "project_name=\(record.projectName)",
            "request_id=\(record.requestID)"
        ]

        if !record.latestStatus.isEmpty {
            lines.append("latest_status=\(record.latestStatus)")
        }

        appendRecordSection("请求信息", fields: record.requestMetadata, into: &lines)
        appendRecordSection("审批状态", fields: record.approvalFields, into: &lines)
        appendRecordSection("治理上下文", fields: record.governanceFields, into: &lines)

        if let payload = nonEmpty(record.skillPayloadText) {
            lines.append("")
            lines.append("== 技能载荷 ==")
            lines.append(payload)
        }

        if let toolArgs = nonEmpty(record.toolArgumentsText) {
            lines.append("")
            lines.append("== 工具参数 ==")
            lines.append(toolArgs)
        }

        appendRecordSection("执行结果", fields: record.resultFields, into: &lines)

        if let rawOutputPreview = nonEmpty(record.rawOutputPreview) {
            lines.append("")
            lines.append("== 原始输出预览 ==")
            lines.append(rawOutputPreview)
        }

        if let rawOutput = nonEmpty(record.rawOutput) {
            lines.append("")
            lines.append("== 完整原始输出 ==")
            lines.append(rawOutput)
        }

        appendRecordSection("证据引用", fields: record.evidenceFields, into: &lines)

        appendRecordSection("UI 审查代理证据", fields: record.uiReviewAgentEvidenceFields, into: &lines)

        if let uiReviewAgentEvidenceText = nonEmpty(record.uiReviewAgentEvidenceText) {
            lines.append("")
            lines.append("== UI 审查代理证据详情 ==")
            lines.append(uiReviewAgentEvidenceText)
        }

        if !record.approvalHistory.isEmpty {
            lines.append("")
            lines.append("== 审批记录 ==")
            for entry in record.approvalHistory {
                lines.append(formattedTimelineEntry(entry))
            }
        }

        if !record.timeline.isEmpty {
            lines.append("")
            lines.append("== 事件时间线 ==")
            for entry in record.timeline {
                lines.append(formattedTimelineEntry(entry))
            }
        }

        if let evidence = nonEmpty(record.supervisorEvidenceJSON) {
            lines.append("")
            lines.append("== 执行证据 ==")
            lines.append(evidence)
        }

        if !record.timeline.isEmpty {
            lines.append("")
            lines.append("== 原始 JSON 事件 ==")
            for entry in record.timeline {
                lines.append(entry.rawJSON)
            }
        }

        return lines.joined(separator: "\n")
    }

    private struct SupervisorSkillRawEvent: Equatable, Sendable {
        var type: String
        var action: String
        var requestID: String
        var projectId: String
        var jobId: String
        var planId: String
        var stepId: String
        var skillId: String
        var requestedSkillId: String
        var routingReasonCode: String
        var routingExplanation: String
        var toolName: String
        var status: String
        var resultSummary: String
        var denyCode: String
        var policySource: String
        var policyReason: String
        var requiredCapability: String
        var grantRequestId: String
        var grantId: String
        var resultEvidenceRef: String
        var triggerSource: String
        var auditRef: String
        var toolArgs: [String: JSONValue]
        var timestampMs: Int64
        var rawObject: [String: JSONValue]
        var lineIndex: Int
    }

    private static func compactWorkflowToken(label: String, value: String?) -> String? {
        guard let value = nonEmpty(value) else { return nil }
        return "\(label)=\(value)"
    }

    private static func loadEvents(
        ctx: AXProjectContext,
        requestID: String
    ) -> [SupervisorSkillRawEvent] {
        guard FileManager.default.fileExists(atPath: ctx.rawLogURL.path),
              let data = try? Data(contentsOf: ctx.rawLogURL),
              let raw = String(data: data, encoding: .utf8) else {
            return []
        }
        let normalizedRequestID = requestID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedRequestID.isEmpty else { return [] }

        return raw.split(separator: "\n", omittingEmptySubsequences: true)
            .enumerated()
            .compactMap { index, line in
                guard let data = line.data(using: .utf8),
                      let value = try? JSONDecoder().decode(JSONValue.self, from: data),
                      case .object(let object) = value,
                      let event = parsedEvent(object, lineIndex: index) else {
                    return nil
                }
                return event.requestID == normalizedRequestID ? event : nil
            }
            .sorted { lhs, rhs in
                if lhs.timestampMs != rhs.timestampMs {
                    return lhs.timestampMs < rhs.timestampMs
                }
                return lhs.lineIndex < rhs.lineIndex
            }
    }

    private static func parsedEvent(
        _ object: [String: JSONValue],
        lineIndex: Int
    ) -> SupervisorSkillRawEvent? {
        let type = stringValue(object["type"]) ?? ""
        guard type == "supervisor_skill_call" || type == "supervisor_skill_result" else { return nil }
        let requestID = stringValue(object["request_id"]) ?? ""
        guard !requestID.isEmpty else { return nil }

        let timestampMs = int64Value(object["timestamp_ms"])
            ?? int64Value(object["updated_at_ms"])
            ?? Int64((numberValue(object["created_at"]) ?? 0) * 1000.0)

        return SupervisorSkillRawEvent(
            type: type,
            action: stringValue(object["action"]) ?? "",
            requestID: requestID,
            projectId: stringValue(object["project_id"]) ?? "",
            jobId: stringValue(object["job_id"]) ?? "",
            planId: stringValue(object["plan_id"]) ?? "",
            stepId: stringValue(object["step_id"]) ?? "",
            skillId: stringValue(object["skill_id"]) ?? "",
            requestedSkillId: stringValue(object["requested_skill_id"]) ?? "",
            routingReasonCode: stringValue(object["routing_reason_code"]) ?? "",
            routingExplanation: stringValue(object["routing_explanation"]) ?? "",
            toolName: stringValue(object["tool_name"]) ?? "",
            status: stringValue(object["status"]) ?? "",
            resultSummary: stringValue(object["result_summary"]) ?? "",
            denyCode: stringValue(object["deny_code"]) ?? "",
            policySource: stringValue(object["policy_source"]) ?? "",
            policyReason: stringValue(object["policy_reason"]) ?? "",
            requiredCapability: stringValue(object["required_capability"]) ?? "",
            grantRequestId: stringValue(object["grant_request_id"]) ?? "",
            grantId: stringValue(object["grant_id"]) ?? "",
            resultEvidenceRef: stringValue(object["result_evidence_ref"]) ?? "",
            triggerSource: stringValue(object["trigger_source"]) ?? "",
            auditRef: stringValue(object["audit_ref"]) ?? "",
            toolArgs: jsonObjectValue(object["tool_args"]),
            timestampMs: timestampMs,
            rawObject: object,
            lineIndex: lineIndex
        )
    }

    private static func timelineEntry(
        for event: SupervisorSkillRawEvent,
        fallbackIndex: Int
    ) -> ProjectSkillRecordTimelineEntry {
        ProjectSkillRecordTimelineEntry(
            id: "\(event.requestID)-\(fallbackIndex)-\(event.timestampMs)",
            status: event.status,
            statusLabel: statusLabel(for: event.status),
            timestamp: formattedTimestampMs(event.timestampMs),
            summary: timelineSummary(for: event),
            detail: timelineDetail(for: event),
            rawJSON: AXProjectSkillActivityStore.prettyJSONString(for: event.rawObject)
        )
    }

    private static func timelineSummary(
        for event: SupervisorSkillRawEvent
    ) -> String {
        if !event.resultSummary.isEmpty {
            return event.resultSummary
        }

        switch normalizedStatus(event.status) {
        case "awaiting_authorization":
            if !event.requiredCapability.isEmpty {
                return XTHubGrantPresentation.awaitingStateSummary(
                    capability: event.requiredCapability,
                    modelId: "",
                    grantRequestId: event.grantRequestId
                )
            }
            return "Waiting for local approval"
        case "queued":
            return "Queued governed dispatch"
        case "running":
            return "Executing \(displayToolName(event.toolName, tool: nil))"
        case "completed":
            return "Supervisor skill completed"
        case "failed":
            return "Supervisor skill failed"
        case "blocked":
            return "Supervisor skill blocked"
        case "canceled":
            return "Supervisor skill canceled"
        default:
            if !event.action.isEmpty {
                return "\(event.type) action=\(event.action)"
            }
            return event.type
        }
    }

    private static func timelineDetail(
        for event: SupervisorSkillRawEvent
    ) -> String? {
        var lines: [String] = []
        if !event.action.isEmpty {
            lines.append("action=\(event.action)")
        }
        if !event.requestedSkillId.isEmpty {
            lines.append("requested_skill_id=\(event.requestedSkillId)")
        }
        let routingPayload = (!event.routingReasonCode.isEmpty || !event.routingExplanation.isEmpty)
            ? [String: JSONValue]()
            : event.toolArgs
        if let routing = skillRoutingSummary(
            requestedSkillId: event.requestedSkillId,
            effectiveSkillId: event.skillId,
            payload: routingPayload,
            routingReasonCode: event.routingReasonCode,
            routingExplanation: event.routingExplanation
        ) {
            lines.append("routing=\(routing)")
        }
        if !event.routingReasonCode.isEmpty {
            lines.append("routing_reason_code=\(event.routingReasonCode)")
        }
        if !event.routingExplanation.isEmpty {
            lines.append("routing_explanation=\(event.routingExplanation)")
        }
        if !event.denyCode.isEmpty {
            lines.append("deny_code=\(event.denyCode)")
        }
        if !event.policySource.isEmpty {
            lines.append("policy_source=\(event.policySource)")
        }
        if !event.policyReason.isEmpty {
            lines.append("policy_reason=\(event.policyReason)")
        }
        if !event.requiredCapability.isEmpty {
            lines.append("required_capability=\(event.requiredCapability)")
        }
        if !event.grantRequestId.isEmpty {
            lines.append("grant_request_id=\(event.grantRequestId)")
        }
        if !event.grantId.isEmpty {
            lines.append("grant_id=\(event.grantId)")
        }
        if !event.resultEvidenceRef.isEmpty {
            lines.append("result_evidence_ref=\(event.resultEvidenceRef)")
        }
        if let uiReviewAgentEvidenceRef = firstNonEmpty(
            stringValue(event.rawObject["ui_review_agent_evidence_ref"]),
            stringValue(event.rawObject["browser_runtime_ui_review_agent_evidence_ref"])
        ) {
            lines.append("ui_review_agent_evidence_ref=\(uiReviewAgentEvidenceRef)")
        }
        if !event.triggerSource.isEmpty {
            lines.append("trigger_source=\(event.triggerSource)")
        }
        if !event.toolArgs.isEmpty,
           let data = try? JSONEncoder().encode(event.toolArgs),
           let text = String(data: data, encoding: .utf8) {
            lines.append("tool_args=\(text)")
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    private static func appendRecordSection(
        _ title: String,
        fields: [ProjectSkillRecordField],
        into lines: inout [String]
    ) {
        guard !fields.isEmpty else { return }
        lines.append("")
        lines.append("== \(title) ==")
        for field in fields {
            lines.append("\(field.label)=\(field.value)")
        }
    }

    private static func formattedTimelineEntry(
        _ entry: ProjectSkillRecordTimelineEntry
    ) -> String {
        var lines: [String] = [
            "[\(entry.timestamp)] status=\(entry.status.isEmpty ? "unknown" : entry.status)"
        ]
        if !entry.summary.isEmpty {
            lines.append("summary=\(entry.summary)")
        }
        if let detail = nonEmpty(entry.detail) {
            lines.append(detail)
        }
        return lines.joined(separator: "\n")
    }

    private static func recordFields(
        _ pairs: [(String, String?)]
    ) -> [ProjectSkillRecordField] {
        pairs.compactMap { label, value in
            guard let value = nonEmpty(value) else { return nil }
            return ProjectSkillRecordField(label: label, value: value)
        }
    }

    private static func skillRoutingSummary(
        requestedSkillId: String?,
        effectiveSkillId: String,
        payload: [String: JSONValue],
        routingReasonCode: String?,
        routingExplanation: String?
    ) -> String? {
        resolvedRoutingResolution(
            requestedSkillId: requestedSkillId,
            effectiveSkillId: effectiveSkillId,
            payload: payload,
            routingReasonCode: routingReasonCode,
            routingExplanation: routingExplanation
        )?.summary
    }

    private static func resolvedRoutingResolution(
        requestedSkillId: String?,
        effectiveSkillId: String,
        payload: [String: JSONValue],
        routingReasonCode: String?,
        routingExplanation: String?
    ) -> SupervisorSkillRoutingResolution? {
        let inferred = SupervisorSkillRoutingCompatibilityHint.routingResolution(
            requestedSkillId: requestedSkillId,
            effectiveSkillId: effectiveSkillId,
            payload: payload
        )
        let resolvedReasonCode = nonEmpty(routingReasonCode) ?? inferred?.reasonCode
        let resolvedExplanation = nonEmpty(routingExplanation) ?? inferred?.explanation
        let resolvedSummary = inferred?.summary

        if resolvedSummary == nil, resolvedReasonCode == nil, resolvedExplanation == nil {
            return nil
        }
        return SupervisorSkillRoutingResolution(
            summary: resolvedSummary,
            reasonCode: resolvedReasonCode,
            explanation: resolvedExplanation
        )
    }

    private static func preferredToolArgumentsText(
        evidenceToolArgs: [String: JSONValue]?,
        eventToolArgs: [String: JSONValue]?
    ) -> String? {
        if let evidenceToolArgs, !evidenceToolArgs.isEmpty {
            return AXProjectSkillActivityStore.prettyJSONString(for: evidenceToolArgs)
        }
        if let eventToolArgs, !eventToolArgs.isEmpty {
            return AXProjectSkillActivityStore.prettyJSONString(for: eventToolArgs)
        }
        return nil
    }

    private static func compactIssueCodesText(_ issueCodes: [String]) -> String {
        let cleaned = issueCodes
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return cleaned.isEmpty ? "(none)" : cleaned.joined(separator: ",")
    }

    private static func isBrowserEntrypoint(_ requestedSkillId: String?) -> Bool {
        guard let requestedSkillId else { return false }
        let normalized = requestedSkillId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "browser.open", "browser_open",
             "browser.navigate", "browser_navigate",
             "browser.runtime.inspect", "browser_runtime.inspect":
            return true
        default:
            return false
        }
    }

    private static func isBrowserWrapper(_ requestedSkillId: String?) -> Bool {
        guard let requestedSkillId else { return false }
        let normalized = requestedSkillId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "agent-browser", "agent_browser", "agent.browser":
            return true
        default:
            return false
        }
    }

    private static func resolvedUIReviewAgentEvidence(
        ctx: AXProjectContext,
        evidence: SupervisorSkillResultEvidence?,
        events: [SupervisorSkillRawEvent]
    ) -> XTUIReviewAgentEvidenceSnapshot? {
        guard let ref = resolvedUIReviewAgentEvidenceRef(evidence: evidence, events: events),
              let url = XTUIObservationStore.resolveLocalRef(ref, for: ctx),
              let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(XTUIReviewAgentEvidenceSnapshot.self, from: data) else {
            return nil
        }
        return snapshot
    }

    private static func resolvedUIReviewAgentEvidenceRef(
        evidence: SupervisorSkillResultEvidence?,
        events: [SupervisorSkillRawEvent]
    ) -> String? {
        let candidates = [
            uiReviewAgentEvidenceRef(fromOutputText: evidence?.rawOutput),
            uiReviewAgentEvidenceRef(fromOutputText: evidence?.rawOutputPreview)
        ] + events.reversed().compactMap { event in
            uiReviewAgentEvidenceRef(fromJSONObject: event.rawObject)
        }
        for candidate in candidates {
            if let candidate = nonEmpty(candidate) {
                return candidate
            }
        }
        return nil
    }

    private static func uiReviewAgentEvidenceRef(
        fromOutputText raw: String?
    ) -> String? {
        guard let raw = nonEmpty(raw),
              let data = raw.data(using: .utf8),
              let value = try? JSONDecoder().decode(JSONValue.self, from: data),
              case .object(let object) = value else {
            return nil
        }
        return uiReviewAgentEvidenceRef(fromJSONObject: object)
    }

    private static func uiReviewAgentEvidenceRef(
        fromJSONObject object: [String: JSONValue]
    ) -> String? {
        let uiReview = jsonObjectValue(object["ui_review"])
        let browserRuntime = jsonObjectValue(object["browser_runtime"])
        return firstNonEmpty(
            stringValue(object["ui_review_agent_evidence_ref"]),
            stringValue(object["browser_runtime_ui_review_agent_evidence_ref"]),
            stringValue(uiReview["agent_evidence_ref"]),
            stringValue(browserRuntime["ui_review_agent_evidence_ref"])
        )
    }

    private static func createdAtText(
        record: SupervisorSkillCallRecord?,
        events: [SupervisorSkillRawEvent]
    ) -> String? {
        if let createdAtMs = record?.createdAtMs, createdAtMs > 0 {
            return formattedTimestampMs(createdAtMs)
        }
        guard let first = events.first?.timestampMs, first > 0 else { return nil }
        return formattedTimestampMs(first)
    }

    private static func updatedAtText(
        record: SupervisorSkillCallRecord?,
        evidence: SupervisorSkillResultEvidence?,
        events: [SupervisorSkillRawEvent]
    ) -> String? {
        if let updatedAtMs = evidence?.updatedAtMs, updatedAtMs > 0 {
            return formattedTimestampMs(updatedAtMs)
        }
        if let updatedAtMs = record?.updatedAtMs, updatedAtMs > 0 {
            return formattedTimestampMs(updatedAtMs)
        }
        guard let last = events.last?.timestampMs, last > 0 else { return nil }
        return formattedTimestampMs(last)
    }

    private static func formattedTimestampMs(_ value: Int64) -> String {
        guard value > 0 else { return "(unknown)" }
        let date = Date(timeIntervalSince1970: Double(value) / 1000.0)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private static func displayToolName(
        _ raw: String,
        tool: ToolName?
    ) -> String {
        let resolvedTool = tool ?? ToolName(rawValue: raw)
        guard let resolvedTool else {
            return raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "工具运行时" : raw
        }

        switch resolvedTool {
        case .read_file:
            return "读取文件"
        case .write_file:
            return "写入文件"
        case .delete_path:
            return "删除路径"
        case .move_path:
            return "移动路径"
        case .run_command:
            return "运行命令"
        case .process_start:
            return "启动进程"
        case .process_status:
            return "进程状态"
        case .process_logs:
            return "进程日志"
        case .process_stop:
            return "停止进程"
        case .git_commit:
            return "Git 提交"
        case .git_push:
            return "Git 推送"
        case .pr_create:
            return "创建 Pull Request"
        case .ci_read:
            return "读取 CI"
        case .ci_trigger:
            return "触发 CI"
        case .search:
            return "搜索"
        case .skills_search:
            return "搜索技能"
        case .summarize:
            return "总结内容"
        case .supervisorVoicePlayback:
            return "Supervisor 语音"
        case .web_fetch:
            return "抓取网页"
        case .web_search:
            return "网页搜索"
        case .browser_read:
            return "浏览器读取"
        case .deviceBrowserControl:
            return "浏览器控制"
        case .agentImportRecord:
            return "导入代理记录"
        default:
            return resolvedTool.rawValue.replacingOccurrences(of: "_", with: " ")
        }
    }

    private static func humanCapabilityLabel(_ capability: String) -> String {
        XTHubGrantPresentation.capabilityLabel(
            capability: capability,
            modelId: ""
        )
    }

    private static func encodedJSONText<T: Encodable>(
        _ value: T
    ) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(value),
              let text = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return text
    }

    private static func normalizedStatus(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func actionURLGovernanceDestination(
        _ raw: String?
    ) -> XTProjectGovernanceDestination? {
        guard let raw = nonEmpty(raw),
              let components = URLComponents(string: raw),
              let destination = components.queryItems?.first(where: { $0.name == "governance_destination" })?.value else {
            return nil
        }
        return XTProjectGovernanceDestination.parse(destination)
    }

    private static func firstNonEmpty(
        _ values: String?...
    ) -> String? {
        for value in values {
            if let value = nonEmpty(value) {
                return value
            }
        }
        return nil
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }

    private static func stringValue(_ value: JSONValue?) -> String? {
        value?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func numberValue(_ value: JSONValue?) -> Double? {
        switch value {
        case .number(let number):
            return number
        case .string(let text):
            return Double(text)
        default:
            return nil
        }
    }

    private static func int64Value(_ value: JSONValue?) -> Int64? {
        switch value {
        case .number(let number):
            return Int64(number.rounded())
        case .string(let text):
            return Int64(text)
        default:
            return nil
        }
    }

    private static func jsonObjectValue(_ value: JSONValue?) -> [String: JSONValue] {
        guard case .object(let object)? = value else {
            return [:]
        }
        return object
    }

    private static func issueCodesText(_ issueCodes: [String]) -> String {
        let cleaned = issueCodes
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return cleaned.isEmpty ? "(none)" : cleaned.joined(separator: ",")
    }
}
