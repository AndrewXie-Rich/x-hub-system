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
            if isAwaitingRequestScopedLocalApproval(item) {
                return "等待本地审批"
            }
            let capability = item.requiredCapability.trimmingCharacters(in: .whitespacesAndNewlines)
            return capability.isEmpty
                ? "等待 Hub 授权"
                : "等待 Hub 授权 · \(humanCapabilityLabel(capability))"
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
            if isAwaitingRequestScopedLocalApproval(item) {
                return "hand.raised.fill"
            }
            return "lock.shield.fill"
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
            if isAwaitingRequestScopedLocalApproval(item) {
                return "打开审批"
            }
            return "打开授权"
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
                return ProjectSkillRecordField(
                    label: displayFieldLabel(field.label),
                    value: displayFieldValue(field.label, field.value)
                )
            }
        }
    }

    static func displayMetadataFields(
        _ fields: [ProjectSkillRecordField]
    ) -> [ProjectSkillRecordField] {
        let context = Dictionary(uniqueKeysWithValues: fields.map { ($0.label, $0.value) })
        return fields.map { field in
            ProjectSkillRecordField(
                label: displayFieldLabel(field.label),
                value: displayFieldValue(
                    field.label,
                    field.value,
                    context: context
                )
            )
        }
    }

    static func governanceLine(for item: SupervisorManager.SupervisorRecentSkillActivity) -> String? {
        guard let governance = item.governance else { return nil }
        let hasGovernanceTruth = governanceTruthLine(for: item) != nil
        var parts: [String] = []
        if let verdict = governance.latestReviewVerdict?.displayName {
            parts.append(displayFieldValue("review_verdict", verdict))
        }
        if let level = governance.latestReviewLevel?.displayName {
            parts.append(displayFieldValue("review_level", level))
        }
        if !hasGovernanceTruth, let tier = governance.effectiveSupervisorTier?.displayName {
            parts.append(displayFieldValue("supervisor_tier", tier))
        }
        if !hasGovernanceTruth, let depth = governance.effectiveWorkOrderDepth?.displayName {
            parts.append(displayFieldValue("work_order_depth", depth))
        }
        let workOrderRef = nonEmpty(governance.workOrderRef)
        if let workOrderRef {
            parts.append("work_order=\(workOrderRef)")
        }
        guard !parts.isEmpty else { return nil }
        return "治理： " + parts.joined(separator: " · ")
    }

    static func governanceTruthLine(for item: SupervisorManager.SupervisorRecentSkillActivity) -> String? {
        if let persisted = nonEmpty(item.governanceTruth) {
            return persisted
        }
        guard let governance = item.governance else { return nil }
        return XTGovernanceTruthPresentation.truthLine(
            configuredExecutionTier: governance.configuredExecutionTier?.rawValue,
            effectiveExecutionTier: governance.effectiveExecutionTier?.rawValue,
            configuredSupervisorTier: governance.configuredSupervisorTier?.rawValue,
            effectiveSupervisorTier: governance.effectiveSupervisorTier?.rawValue,
            reviewPolicyMode: governance.reviewPolicyMode?.rawValue,
            progressHeartbeatSeconds: governance.progressHeartbeatSeconds,
            reviewPulseSeconds: governance.reviewPulseSeconds,
            brainstormReviewSeconds: governance.brainstormReviewSeconds,
            compatSource: governance.compatSource?.rawValue
        )
    }

    static func displayGovernanceTruthLine(
        for item: SupervisorManager.SupervisorRecentSkillActivity
    ) -> String? {
        governanceTruthLine(for: item).map(XTGovernanceTruthPresentation.displayText)
    }

    static func blockedSummaryLine(for item: SupervisorManager.SupervisorRecentSkillActivity) -> String? {
        guard let summary = blockedSummaryText(for: item) else { return nil }
        return "阻塞说明： \(summary)"
    }

    static func blockedSummaryText(for item: SupervisorManager.SupervisorRecentSkillActivity) -> String? {
        if let persisted = nonEmpty(item.blockedSummary) {
            return persisted
        }
        let toolLabel = toolBadge(for: item)
        let target = item.toolSummary.trimmingCharacters(in: .whitespacesAndNewlines)

        switch normalizedStatus(item.status) {
        case "awaiting_authorization":
            return XTGuardrailMessagePresentation.awaitingApprovalMessage(
                toolLabel: toolLabel,
                target: target,
                requiredCapability: isAwaitingRequestScopedLocalApproval(item) ? "" : item.requiredCapability,
                denyCode: item.denyCode
            ).summary
        case "blocked":
            return XTGuardrailMessagePresentation.blockedSummary(
                tool: item.tool,
                toolLabel: toolLabel,
                denyCode: item.denyCode,
                policySource: item.policySource,
                policyReason: item.policyReason,
                requiredCapability: item.requiredCapability,
                fallbackSummary: item.resultSummary
            ) ?? nonEmpty(item.resultSummary)
        case "failed":
            if !item.denyCode.isEmpty || !item.policySource.isEmpty || !item.policyReason.isEmpty {
                return XTGuardrailMessagePresentation.blockedSummary(
                    tool: item.tool,
                    toolLabel: toolLabel,
                    denyCode: item.denyCode,
                    policySource: item.policySource,
                    policyReason: item.policyReason,
                    requiredCapability: item.requiredCapability,
                    fallbackSummary: item.resultSummary
                ) ?? nonEmpty(item.resultSummary)
            }
            return nil
        default:
            return nil
        }
    }

    static func followUpRhythmLine(for item: SupervisorManager.SupervisorRecentSkillActivity) -> String? {
        guard let governance = item.governance else { return nil }
        guard let summary = nonEmpty(governance.followUpRhythmSummary) else { return nil }
        return "跟进节奏： \(displayFieldValue("follow_up_rhythm", summary))"
    }

    static func pendingGuidanceLine(for item: SupervisorManager.SupervisorRecentSkillActivity) -> String? {
        guard let governance = item.governance else { return nil }
        guard let ackStatus = governance.pendingGuidanceAckStatus else { return nil }
        var parts = [
            displayFieldValue(
                "pending_guidance_ack",
                "\(ackStatus.displayName) · \(governance.pendingGuidanceRequired ? "required" : "optional")"
            )
        ]
        if let latestDelivery = governance.latestGuidanceDeliveryMode?.displayName {
            parts.append(displayFieldValue("latest_guidance_delivery", latestDelivery))
        }
        if let guidanceSummary = activeGuidanceSummary(for: governance) {
            parts.append(guidanceSummary)
        }
        let guidanceId = nonEmpty(governance.pendingGuidanceId) ?? nonEmpty(governance.latestGuidanceId)
        if let guidanceId {
            parts.append("id=\(guidanceId)")
        }
        return "指导： " + parts.joined(separator: " · ")
    }

    static func guidanceContractLine(for item: SupervisorManager.SupervisorRecentSkillActivity) -> String? {
        guard let contract = item.governance?.guidanceContract else { return nil }
        return SupervisorGuidanceContractLinePresentation.contractLine(for: contract)
    }

    static func guidanceNextSafeActionLine(for item: SupervisorManager.SupervisorRecentSkillActivity) -> String? {
        guard let contract = item.governance?.guidanceContract else { return nil }
        return SupervisorGuidanceContractLinePresentation.nextSafeActionLine(for: contract)
    }

    static func governedShortSummary(
        for item: SupervisorManager.SupervisorRecentSkillActivity
    ) -> String? {
        XTPendingApprovalPresentation.governedSkillShortSummary(
            for: governedSkillPresentationItem(for: item)
        )
    }

    static func governedShortSummary(
        for approval: SupervisorManager.SupervisorPendingSkillApproval
    ) -> String? {
        XTPendingApprovalPresentation.governedSkillShortSummary(
            for: governedSkillPresentationItem(for: approval)
        )
    }

    static func governedDetailLines(
        for item: SupervisorManager.SupervisorRecentSkillActivity
    ) -> [String] {
        XTPendingApprovalPresentation.governedSkillDetailLines(
            for: governedSkillPresentationItem(for: item)
        )
    }

    static func governedDetailLines(
        for approval: SupervisorManager.SupervisorPendingSkillApproval
    ) -> [String] {
        XTPendingApprovalPresentation.governedSkillDetailLines(
            for: governedSkillPresentationItem(for: approval)
        )
    }

    static func preferredCardSummary(
        for item: SupervisorManager.SupervisorRecentSkillActivity
    ) -> String {
        if shouldPreferGovernedCardSummary(item),
           let governedSummary = governedShortSummary(for: item) {
            return governedSummary
        }

        let displaySkill = displaySkillSummary(for: item)
        if !displaySkill.isEmpty {
            return displaySkill
        }

        return governedShortSummary(for: item) ?? ""
    }

    static func cardGovernedDetailLines(
        for item: SupervisorManager.SupervisorRecentSkillActivity,
        limit: Int = 2
    ) -> [String] {
        guard limit > 0, shouldPreferGovernedCardSummary(item) else { return [] }

        switch normalizedStatus(item.status) {
        case "awaiting_authorization", "failed", "blocked":
            return []
        default:
            break
        }

        let lines = governedDetailLines(for: item)
            .filter(shouldDisplayCardGovernedDetailLine)
        guard !lines.isEmpty else { return [] }

        return prioritizedCardGovernedDetailLines(lines)
            .prefix(limit)
            .map { $0 }
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
            return appendCapabilityContext(
                XTGuardrailMessagePresentation.awaitingApprovalBody(
                    toolLabel: toolLabel,
                    target: target,
                    requiredCapability: isAwaitingRequestScopedLocalApproval(item) ? "" : item.requiredCapability,
                    denyCode: item.denyCode
                ),
                item: item
            )
        case "completed":
            if !item.resultSummary.isEmpty { return item.resultSummary }
            return "\(skillLabel)已通过\(toolLabel)完成。"
        case "failed":
            if !item.denyCode.isEmpty || !item.policySource.isEmpty {
                let body = blockedSummaryText(for: item) ?? XTGuardrailMessagePresentation.blockedBody(
                    tool: item.tool,
                    toolLabel: toolLabel,
                    denyCode: item.denyCode,
                    policySource: item.policySource,
                    policyReason: item.policyReason,
                    requiredCapability: item.requiredCapability,
                    fallbackSummary: item.resultSummary
                )
                return appendCapabilityContext(
                    prefixGovernanceTruthIfNeeded(body: body, item: item),
                    item: item
                )
            }
            if !item.resultSummary.isEmpty { return item.resultSummary }
            return "\(skillLabel)在执行\(toolLabel)时失败。"
        case "blocked":
            let body = blockedSummaryText(for: item) ?? XTGuardrailMessagePresentation.blockedBody(
                tool: item.tool,
                toolLabel: toolLabel,
                denyCode: item.denyCode,
                policySource: item.policySource,
                policyReason: item.policyReason,
                requiredCapability: item.requiredCapability,
                fallbackSummary: item.resultSummary
            )
            return appendCapabilityContext(
                prefixGovernanceTruthIfNeeded(body: body, item: item),
                item: item
            )
        case "canceled":
            if !item.resultSummary.isEmpty { return item.resultSummary }
            return "\(skillLabel)已取消。"
        default:
            if !item.denyCode.isEmpty || !item.policySource.isEmpty {
                let body = blockedSummaryText(for: item) ?? XTGuardrailMessagePresentation.blockedBody(
                    tool: item.tool,
                    toolLabel: toolLabel,
                    denyCode: item.denyCode,
                    policySource: item.policySource,
                    policyReason: item.policyReason,
                    requiredCapability: item.requiredCapability,
                    fallbackSummary: item.resultSummary
                )
                return appendCapabilityContext(
                    prefixGovernanceTruthIfNeeded(body: body, item: item),
                    item: item
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
        if let profileDeltaRef = nonEmpty(record.profileDeltaRef) {
            lines.append("profile_delta_ref=\(profileDeltaRef)")
        }
        if let readinessRef = nonEmpty(record.readinessRef) {
            lines.append("readiness_ref=\(readinessRef)")
        }
        if !item.resultSummary.isEmpty { lines.append("result_summary=\(item.resultSummary)") }
        if !item.denyCode.isEmpty { lines.append("deny_code=\(item.denyCode)") }
        if !item.policySource.isEmpty { lines.append("policy_source=\(item.policySource)") }
        if !item.policyReason.isEmpty { lines.append("policy_reason=\(item.policyReason)") }
        if let deltaApproval = record.deltaApproval {
            lines.append("approval_summary=\(deltaApproval.summary)")
            lines.append("current_runnable_profiles=\(deltaApproval.currentRunnableProfiles.joined(separator: ","))")
            lines.append("requested_profiles=\(deltaApproval.requestedProfiles.joined(separator: ","))")
            lines.append("delta_profiles=\(deltaApproval.deltaProfiles.joined(separator: ","))")
            lines.append("current_runnable_capability_families=\(deltaApproval.currentRunnableCapabilityFamilies.joined(separator: ","))")
            lines.append("requested_capability_families=\(deltaApproval.requestedCapabilityFamilies.joined(separator: ","))")
            lines.append("delta_capability_families=\(deltaApproval.deltaCapabilityFamilies.joined(separator: ","))")
            lines.append("grant_floor=\(deltaApproval.grantFloor)")
            lines.append("approval_floor=\(deltaApproval.approvalFloor)")
        }
        if let readiness = record.readiness {
            lines.append("execution_readiness=\(readiness.executionReadiness)")
            lines.append("state_label=\(readiness.stateLabel)")
            lines.append("readiness_reason_code=\(readiness.reasonCode)")
            lines.append("required_runtime_surfaces=\(readiness.requiredRuntimeSurfaces.joined(separator: ","))")
            lines.append("unblock_actions=\(readiness.unblockActions.joined(separator: ","))")
            if record.deltaApproval == nil {
                lines.append("grant_floor=\(readiness.grantFloor)")
                lines.append("approval_floor=\(readiness.approvalFloor)")
            }
        }
        if let governanceReason = governanceReasonText(for: item) {
            lines.append("governance_reason=\(governanceReason)")
        }
        if let blockedSummary = blockedSummaryText(for: item) {
            lines.append("blocked_summary=\(blockedSummary)")
        }
        if let governanceTruth = governanceTruthLine(for: item) {
            lines.append("governance_truth=\(governanceTruth)")
        }
        if let repairAction = repairActionText(for: item) {
            lines.append("repair_action=\(repairAction)")
        }
        if let guidanceSummary = item.governance.flatMap(activeGuidanceSummary(for:)) {
            lines.append("guidance_summary=\(guidanceSummary)")
        }
        if let guidanceContract = item.governance?.guidanceContract {
            lines.append("guidance_contract=\(guidanceContract.kind.rawValue)")
            if !guidanceContract.primaryBlocker.isEmpty {
                lines.append("primary_blocker=\(guidanceContract.primaryBlocker)")
            }
            if let uiReview = guidanceContract.uiReviewRepair {
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
        normalizedStatus(item.status) == "awaiting_authorization" && isAwaitingRequestScopedLocalApproval(item)
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
        let approvalDenyCode = firstNonEmpty(record?.denyCode, evidence?.denyCode, events.last?.denyCode)
        let approvalPolicySource = firstNonEmpty(record?.policySource, evidence?.policySource, events.last?.policySource)
        let approvalPolicyReason = firstNonEmpty(record?.policyReason, evidence?.policyReason, events.last?.policyReason)
        let approvalRequiredCapability = firstNonEmpty(record?.requiredCapability, events.last?.requiredCapability)
        let latestResultSummary = firstNonEmpty(evidence?.resultSummary, record?.resultSummary, events.last?.resultSummary)
        let persistedDeltaApproval = record?.deltaApproval ?? evidence?.deltaApproval
        let persistedReadiness = record?.readiness ?? evidence?.readiness
        let profileDeltaRef = firstNonEmpty(
            record?.profileDeltaRef,
            evidence?.profileDeltaRef,
            latestRawEventScalar("profile_delta_ref", from: events)
        )
        let readinessRef = firstNonEmpty(
            record?.readinessRef,
            evidence?.readinessRef,
            latestRawEventScalar("readiness_ref", from: events)
        )
        let approvalSummary = firstNonEmpty(
            persistedDeltaApproval?.summary,
            latestRawEventScalar("approval_summary", from: events)
        )
        let currentRunnableProfiles = firstNonEmptyStringArray(
            persistedDeltaApproval?.currentRunnableProfiles ?? [],
            latestRawEventStringArray("current_runnable_profiles", from: events)
        )
        let requestedProfiles = firstNonEmptyStringArray(
            persistedDeltaApproval?.requestedProfiles ?? [],
            latestRawEventStringArray("requested_profiles", from: events)
        )
        let deltaProfiles = firstNonEmptyStringArray(
            persistedDeltaApproval?.deltaProfiles ?? [],
            latestRawEventStringArray("delta_profiles", from: events)
        )
        let currentRunnableFamilies = firstNonEmptyStringArray(
            persistedDeltaApproval?.currentRunnableCapabilityFamilies ?? [],
            latestRawEventStringArray("current_runnable_capability_families", from: events)
        )
        let requestedFamilies = firstNonEmptyStringArray(
            persistedDeltaApproval?.requestedCapabilityFamilies ?? [],
            latestRawEventStringArray("requested_capability_families", from: events)
        )
        let deltaFamilies = firstNonEmptyStringArray(
            persistedDeltaApproval?.deltaCapabilityFamilies ?? [],
            latestRawEventStringArray("delta_capability_families", from: events)
        )
        let intentFamilies = firstNonEmptyStringArray(
            persistedReadiness?.intentFamilies ?? [],
            latestRawEventStringArray("intent_families", from: events)
        )
        let capabilityFamilies = firstNonEmptyStringArray(
            persistedReadiness?.capabilityFamilies ?? [],
            latestRawEventStringArray("capability_families", from: events)
        )
        let capabilityProfiles = firstNonEmptyStringArray(
            persistedReadiness?.capabilityProfiles ?? [],
            latestRawEventStringArray("capability_profiles", from: events)
        )
        let executionReadiness = firstNonEmpty(
            persistedReadiness?.executionReadiness,
            latestRawEventScalar("execution_readiness", from: events)
        )
        let readinessStateLabel = firstNonEmpty(
            persistedReadiness?.stateLabel,
            latestRawEventScalar("state_label", from: events)
        )
        let readinessReasonCode = firstNonEmpty(
            persistedReadiness?.reasonCode,
            latestRawEventScalar("readiness_reason_code", from: events)
        )
        let requiredRuntimeSurfaces = firstNonEmptyStringArray(
            persistedReadiness?.requiredRuntimeSurfaces ?? [],
            latestRawEventStringArray("required_runtime_surfaces", from: events)
        )
        let unblockActions = firstNonEmptyStringArray(
            persistedReadiness?.unblockActions ?? [],
            latestRawEventStringArray("unblock_actions", from: events)
        )
        let grantFloor = firstNonEmpty(
            persistedDeltaApproval?.grantFloor,
            persistedReadiness?.grantFloor,
            latestRawEventScalar("grant_floor", from: events)
        )
        let approvalFloor = firstNonEmpty(
            persistedDeltaApproval?.approvalFloor,
            persistedReadiness?.approvalFloor,
            latestRawEventScalar("approval_floor", from: events)
        )
        let resolvedToolName = firstNonEmpty(record?.toolName, evidence?.toolName, events.last?.toolName) ?? ""
        let resolvedTool = ToolName(rawValue: resolvedToolName)
        let approvalGovernanceReason = firstNonEmpty(
            latestRawEventScalar("governance_reason", from: events),
            XTGuardrailMessagePresentation.governanceReasonSummary(
                tool: resolvedTool,
                toolLabel: displayToolName(
                    resolvedToolName,
                    tool: resolvedTool
                ),
                denyCode: approvalDenyCode ?? "",
                policySource: approvalPolicySource ?? "",
                policyReason: approvalPolicyReason ?? "",
                requiredCapability: approvalRequiredCapability ?? ""
            )
        )
        let approvalBlockedSummary = firstNonEmpty(
            latestRawEventScalar("blocked_summary", from: events),
            XTGuardrailMessagePresentation.blockedSummary(
                tool: resolvedTool,
                toolLabel: displayToolName(
                    resolvedToolName,
                    tool: resolvedTool
                ),
                denyCode: approvalDenyCode ?? "",
                policySource: approvalPolicySource ?? "",
                policyReason: approvalPolicyReason ?? "",
                requiredCapability: approvalRequiredCapability ?? "",
                fallbackSummary: latestResultSummary ?? "",
                fallbackDetail: ""
            )
        )
        let approvalRepairAction = firstNonEmpty(
            latestRawEventScalar("repair_action", from: events),
            repairActionSummary(
                denyCode: approvalDenyCode ?? "",
                policySource: approvalPolicySource ?? "",
                policyReason: approvalPolicyReason ?? ""
            )
        )
        let activeGuidanceSummary = activeGuidance.map {
            SupervisorGuidanceTextPresentation.summary($0.guidanceText, maxChars: 220)
        }

        let requestMetadata = recordFields([
            ("project_name", projectName),
            ("request_id", requestID),
            ("project_id", firstNonEmpty(record?.projectId, evidence?.projectId, events.last?.projectId)),
            ("job_id", firstNonEmpty(record?.jobId, evidence?.jobId, events.last?.jobId)),
            ("plan_id", firstNonEmpty(record?.planId, evidence?.planId, events.last?.planId)),
            ("step_id", firstNonEmpty(record?.stepId, evidence?.stepId, events.last?.stepId)),
            ("requested_skill_id", firstNonEmpty(record?.requestedSkillId, evidence?.requestedSkillId, events.last?.requestedSkillId)),
            ("skill_id", firstNonEmpty(record?.skillId, evidence?.skillId, events.last?.skillId)),
            ("intent_families", joinedListText(intentFamilies)),
            ("capability_families", joinedListText(capabilityFamilies)),
            ("capability_profiles", joinedListText(capabilityProfiles)),
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
            ("required_capability", approvalRequiredCapability),
            ("grant_request_id", firstNonEmpty(record?.grantRequestId, events.last?.grantRequestId)),
            ("grant_id", firstNonEmpty(record?.grantId, events.last?.grantId)),
            ("profile_delta_ref", profileDeltaRef),
            ("approval_summary", approvalSummary),
            ("current_runnable_profiles", joinedListText(currentRunnableProfiles)),
            ("requested_profiles", joinedListText(requestedProfiles)),
            ("delta_profiles", joinedListText(deltaProfiles)),
            ("current_runnable_capability_families", joinedListText(currentRunnableFamilies)),
            ("requested_capability_families", joinedListText(requestedFamilies)),
            ("delta_capability_families", joinedListText(deltaFamilies)),
            ("grant_floor", grantFloor),
            ("approval_floor", approvalFloor),
            ("deny_code", approvalDenyCode),
            ("trigger_source", firstNonEmpty(evidence?.triggerSource, events.last?.triggerSource))
        ])
        let governanceTruth = firstNonEmpty(
            latestRawEventScalar("governance_truth", from: events),
            events
                .reversed()
                .compactMap { XTGovernanceTruthPresentation.effectiveTierSummary(from: $0.rawObject) }
                .first
        )

        let governanceFields = recordFields([
            ("policy_source", approvalPolicySource),
            ("policy_reason", approvalPolicyReason),
            ("governance_reason", approvalGovernanceReason),
            ("blocked_summary", approvalBlockedSummary),
            ("governance_truth", governanceTruth),
            ("repair_action", approvalRepairAction),
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
            ("guidance_summary", activeGuidanceSummary),
            ("follow_up_rhythm", SupervisorReviewPolicyEngine.eventFollowUpCadenceLabel(governance: resolvedGovernance))
        ])

        let resultFields = recordFields([
            ("result_status", firstNonEmpty(evidence?.status, record?.status.rawValue, events.last?.status)),
            ("result_summary", latestResultSummary),
            ("readiness_ref", readinessRef),
            ("execution_readiness", executionReadiness),
            ("state_label", readinessStateLabel),
            ("readiness_reason_code", readinessReasonCode),
            ("required_runtime_surfaces", joinedListText(requiredRuntimeSurfaces)),
            ("unblock_actions", joinedListText(unblockActions)),
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
                lines.append(displayFormattedTimelineEntry(entry))
            }
        }

        if !record.timeline.isEmpty {
            lines.append("")
            lines.append("== 事件时间线 ==")
            for entry in record.timeline {
                lines.append(displayFormattedTimelineEntry(entry))
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

    static func displayFullRecordText(_ record: SupervisorSkillFullRecord) -> String {
        var lines: [String] = [
            "Supervisor 技能完整记录",
            "项目：\(record.projectName)",
            "请求单号：\(record.requestID)"
        ]

        let displayStatus = nonEmpty(record.latestStatusLabel) ?? statusLabel(for: record.latestStatus)
        if !displayStatus.isEmpty {
            lines.append("最新状态：\(displayStatus)")
        }

        appendDisplayRecordSection(
            "请求信息",
            fields: displayRequestMetadataFields(record.requestMetadata),
            into: &lines
        )
        appendDisplayRecordSection(
            "审批状态",
            fields: displayMetadataFields(record.approvalFields),
            into: &lines
        )
        appendDisplayRecordSection(
            "治理上下文",
            fields: displayMetadataFields(record.governanceFields),
            into: &lines
        )

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

        appendDisplayRecordSection(
            "执行结果",
            fields: displayMetadataFields(record.resultFields),
            into: &lines
        )

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

        appendDisplayRecordSection(
            "证据引用",
            fields: displayMetadataFields(record.evidenceFields),
            into: &lines
        )

        appendDisplayRecordSection(
            "UI 审查代理证据",
            fields: displayMetadataFields(record.uiReviewAgentEvidenceFields),
            into: &lines
        )

        if let uiReviewAgentEvidenceText = nonEmpty(record.uiReviewAgentEvidenceText) {
            lines.append("")
            lines.append("== UI 审查代理证据详情 ==")
            lines.append(uiReviewAgentEvidenceText)
        }

        if !record.approvalHistory.isEmpty {
            lines.append("")
            lines.append("== 审批记录 ==")
            for entry in record.approvalHistory {
                lines.append(displayFormattedTimelineEntry(entry))
            }
        }

        if !record.timeline.isEmpty {
            lines.append("")
            lines.append("== 事件时间线 ==")
            for entry in record.timeline {
                lines.append(displayFormattedTimelineEntry(entry))
            }
        }

        let routingDiagnostics = record.requestMetadata.filter {
            $0.label == "routing_reason_code" || $0.label == "routing_explanation"
        }
        if !routingDiagnostics.isEmpty {
            lines.append("")
            lines.append("== 路由诊断原文 ==")
            for field in routingDiagnostics {
                lines.append("\(field.label)=\(field.value)")
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

    static func governanceReasonText(
        for item: SupervisorManager.SupervisorRecentSkillActivity
    ) -> String? {
        if let persisted = nonEmpty(item.governanceReason) {
            return persisted
        }
        return XTGuardrailMessagePresentation.governanceReasonSummary(
            tool: item.tool,
            toolLabel: displayToolName(item.toolName, tool: item.tool),
            denyCode: item.denyCode,
            policySource: item.policySource,
            policyReason: item.policyReason,
            requiredCapability: item.requiredCapability
        )
    }

    private static func governanceReasonText(
        for event: SupervisorSkillRawEvent
    ) -> String? {
        let tool = ToolName(rawValue: event.toolName)
        return XTGuardrailMessagePresentation.governanceReasonSummary(
            tool: tool,
            toolLabel: displayToolName(event.toolName, tool: tool),
            denyCode: event.denyCode,
            policySource: event.policySource,
            policyReason: event.policyReason,
            requiredCapability: event.requiredCapability
        )
    }

    private static func repairActionSummary(
        denyCode: String,
        policySource: String,
        policyReason: String
    ) -> String? {
        guard let repairHint = XTGuardrailMessagePresentation.repairHint(
            denyCode: denyCode,
            policySource: policySource,
            policyReason: policyReason
        ) else {
            return nil
        }
        return "\(repairHint.buttonTitle)：\(repairHint.helpText)"
    }

    private static func repairActionText(
        for item: SupervisorManager.SupervisorRecentSkillActivity
    ) -> String? {
        if let persisted = nonEmpty(item.repairAction) {
            return persisted
        }
        if let uiReviewAction = item.governance?.guidanceContract?.uiReviewRepair?.repairAction,
           let normalized = nonEmpty(uiReviewAction) {
            return normalized
        }
        return repairActionSummary(
            denyCode: item.denyCode,
            policySource: item.policySource,
            policyReason: item.policyReason
        )
    }

    private static func prefixGovernanceTruthIfNeeded(
        body: String,
        item: SupervisorManager.SupervisorRecentSkillActivity
    ) -> String {
        guard XTGuardrailMessagePresentation.shouldShowGovernanceTruth(
            denyCode: item.denyCode,
            policySource: item.policySource
        ),
        let governanceTruth = displayGovernanceTruthLine(for: item) else {
            return body
        }
        return "\(governanceTruth) \(body)"
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
            policyReason: resolvedPolicyReason(object),
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

    private static func resolvedPolicyReason(
        _ object: [String: JSONValue]
    ) -> String {
        let policySource = stringValue(object["policy_source"]) ?? ""
        if policySource == "project_autonomy_policy",
           let runtimeSurfacePolicyReason = stringValue(object["runtime_surface_policy_reason"]) {
            return runtimeSurfacePolicyReason
        }
        return stringValue(object["policy_reason"]) ?? ""
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
            return "等待本地审批"
        case "queued":
            return "已进入受治理执行队列"
        case "running":
            return "正在执行\(displayToolName(event.toolName, tool: nil))"
        case "completed":
            return "Supervisor 技能已完成"
        case "failed":
            return "Supervisor 技能失败"
        case "blocked":
            return "Supervisor 技能受阻"
        case "canceled":
            return "Supervisor 技能已取消"
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
        if let intentFamilies = joinedListText(stringArrayValue(event.rawObject["intent_families"])) {
            lines.append("intent_families=\(intentFamilies)")
        }
        if let capabilityFamilies = joinedListText(stringArrayValue(event.rawObject["capability_families"])) {
            lines.append("capability_families=\(capabilityFamilies)")
        }
        if let capabilityProfiles = joinedListText(stringArrayValue(event.rawObject["capability_profiles"])) {
            lines.append("capability_profiles=\(capabilityProfiles)")
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
        if let profileDeltaRef = stringValue(event.rawObject["profile_delta_ref"]) {
            lines.append("profile_delta_ref=\(profileDeltaRef)")
        }
        if let readinessRef = stringValue(event.rawObject["readiness_ref"]) {
            lines.append("readiness_ref=\(readinessRef)")
        }
        if let approvalSummary = stringValue(event.rawObject["approval_summary"]) {
            lines.append("approval_summary=\(approvalSummary)")
        }
        if let currentRunnableProfiles = joinedListText(stringArrayValue(event.rawObject["current_runnable_profiles"])) {
            lines.append("current_runnable_profiles=\(currentRunnableProfiles)")
        }
        if let requestedProfiles = joinedListText(stringArrayValue(event.rawObject["requested_profiles"])) {
            lines.append("requested_profiles=\(requestedProfiles)")
        }
        if let deltaProfiles = joinedListText(stringArrayValue(event.rawObject["delta_profiles"])) {
            lines.append("delta_profiles=\(deltaProfiles)")
        }
        if let currentFamilies = joinedListText(stringArrayValue(event.rawObject["current_runnable_capability_families"])) {
            lines.append("current_runnable_capability_families=\(currentFamilies)")
        }
        if let requestedFamilies = joinedListText(stringArrayValue(event.rawObject["requested_capability_families"])) {
            lines.append("requested_capability_families=\(requestedFamilies)")
        }
        if let deltaFamilies = joinedListText(stringArrayValue(event.rawObject["delta_capability_families"])) {
            lines.append("delta_capability_families=\(deltaFamilies)")
        }
        if let executionReadiness = stringValue(event.rawObject["execution_readiness"]) {
            lines.append("execution_readiness=\(executionReadiness)")
        }
        if let readinessReasonCode = stringValue(event.rawObject["readiness_reason_code"]) {
            lines.append("readiness_reason_code=\(readinessReasonCode)")
        }
        if let grantFloor = stringValue(event.rawObject["grant_floor"]) {
            lines.append("grant_floor=\(grantFloor)")
        }
        if let approvalFloor = stringValue(event.rawObject["approval_floor"]) {
            lines.append("approval_floor=\(approvalFloor)")
        }
        if let requiredRuntimeSurfaces = joinedListText(stringArrayValue(event.rawObject["required_runtime_surfaces"])) {
            lines.append("required_runtime_surfaces=\(requiredRuntimeSurfaces)")
        }
        if let unblockActions = joinedListText(stringArrayValue(event.rawObject["unblock_actions"])) {
            lines.append("unblock_actions=\(unblockActions)")
        }
        if !event.policySource.isEmpty {
            lines.append("policy_source=\(event.policySource)")
        }
        if !event.policyReason.isEmpty {
            lines.append("policy_reason=\(event.policyReason)")
        }
        if let governanceReason = governanceReasonText(for: event) {
            lines.append("governance_reason=\(governanceReason)")
        }
        if let governanceTruth = XTGuardrailMessagePresentation.governanceTruthLine(
            from: event.rawObject,
            denyCode: event.denyCode,
            policySource: event.policySource
        ) {
            lines.append("governance_truth=\(governanceTruth)")
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

    private static func appendDisplayRecordSection(
        _ title: String,
        fields: [ProjectSkillRecordField],
        into lines: inout [String]
    ) {
        guard !fields.isEmpty else { return }
        lines.append("")
        lines.append("== \(title) ==")
        for field in fields {
            lines.append("\(field.label)：\(field.value)")
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

    private static func displayFormattedTimelineEntry(
        _ entry: ProjectSkillRecordTimelineEntry
    ) -> String {
        var lines: [String] = [
            "[\(entry.timestamp)] 状态：\(entry.statusLabel.isEmpty ? "未知" : entry.statusLabel)"
        ]
        if !entry.summary.isEmpty {
            lines.append("摘要：\(entry.summary)")
        }
        if let detail = displayTimelineDetail(entry.detail) {
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

    private static func activeGuidanceSummary(
        for governance: SupervisorManager.SupervisorRecentSkillActivity.GovernanceSummary
    ) -> String? {
        nonEmpty(governance.activeGuidanceSummary)
    }

    private static func displayFieldLabel(_ rawLabel: String) -> String {
        switch rawLabel {
        case "project_name":
            return "项目"
        case "request_id":
            return "请求"
        case "project_id":
            return "项目 ID"
        case "job_id":
            return "任务"
        case "plan_id":
            return "计划"
        case "step_id":
            return "步骤"
        case "requested_skill_id":
            return "请求技能"
        case "skill_id":
            return "生效技能"
        case "intent_families":
            return "意图族"
        case "capability_families":
            return "能力族"
        case "capability_profiles":
            return "能力档位"
        case "routing_resolution":
            return "路由"
        case "routing_reason_code":
            return "路由判定"
        case "routing_explanation":
            return "路由说明"
        case "tool_name":
            return "工具"
        case "latest_status":
            return "最新状态"
        case "current_owner":
            return "当前负责人"
        case "created_at":
            return "创建时间"
        case "updated_at":
            return "更新时间"
        case "required_capability":
            return "所需能力"
        case "profile_delta_ref":
            return "能力增量引用"
        case "approval_summary":
            return "能力增量摘要"
        case "current_runnable_profiles":
            return "当前可直接运行档位"
        case "requested_profiles":
            return "本次请求档位"
        case "delta_profiles":
            return "新增放开档位"
        case "current_runnable_capability_families":
            return "当前可直接运行能力族"
        case "requested_capability_families":
            return "本次请求能力族"
        case "delta_capability_families":
            return "新增放开能力族"
        case "grant_floor":
            return "授权门槛"
        case "approval_floor":
            return "审批门槛"
        case "readiness_ref":
            return "执行就绪引用"
        case "execution_readiness":
            return "执行就绪"
        case "state_label":
            return "状态标签"
        case "readiness_reason_code":
            return "就绪原因"
        case "required_runtime_surfaces":
            return "所需运行面"
        case "unblock_actions":
            return "解阻动作"
        case "grant_request_id":
            return "授权请求"
        case "grant_id":
            return "授权"
        case "deny_code":
            return "拒绝原因"
        case "policy_source":
            return "策略来源"
        case "policy_reason":
            return "策略原因"
        case "governance_reason":
            return "治理原因"
        case "blocked_summary":
            return "阻塞说明"
        case "governance_truth":
            return "治理真相"
        case "trigger_source":
            return "触发源"
        case "latest_review_id":
            return "最新审查"
        case "review_verdict":
            return "审查结论"
        case "review_level":
            return "审查层级"
        case "supervisor_tier":
            return "Supervisor 层级"
        case "work_order_depth":
            return "工单深度"
        case "work_order_ref":
            return "工单"
        case "latest_guidance_id":
            return "最新指导"
        case "latest_guidance_delivery":
            return "最新指导交付"
        case "pending_guidance_id":
            return "待确认指导"
        case "pending_guidance_ack":
            return "待确认指导状态"
        case "guidance_summary":
            return "指导摘要"
        case "follow_up_rhythm":
            return "跟进节奏"
        case "result_status":
            return "结果状态"
        case "result_summary":
            return "结果摘要"
        case "raw_output_chars":
            return "原始输出字符数"
        case "result_evidence_ref":
            return "结果证据引用"
        case "raw_output_ref":
            return "原始输出引用"
        case "audit_ref":
            return "审计引用"
        case "ui_review_agent_evidence_ref":
            return "UI 审查代理证据引用"
        case "review_ref":
            return "审查引用"
        case "bundle_ref":
            return "观测包引用"
        case "verdict":
            return "结论"
        case "confidence":
            return "置信度"
        case "sufficient_evidence":
            return "证据充分"
        case "objective_ready":
            return "目标就绪"
        case "issue_codes":
            return "问题代码"
        case "summary":
            return "摘要"
        default:
            return rawLabel
        }
    }

    private static func displayTimelineDetail(
        _ detail: String?
    ) -> String? {
        guard let detail = nonEmpty(detail) else { return nil }
        let context = fieldContext(from: detail)
        let lines = detail
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { displayTimelineDetailLine(String($0), context: context) }
        return lines.joined(separator: "\n")
    }

    private static func displayTimelineDetailLine(
        _ line: String,
        context: [String: String]
    ) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        guard let separatorIndex = trimmed.firstIndex(of: "=") else {
            return trimmed
        }
        let rawLabel = String(trimmed[..<separatorIndex])
        let rawValue = String(trimmed[trimmed.index(after: separatorIndex)...])
        let value = displayFieldValue(rawLabel, rawValue, context: context)
        return "\(displayFieldLabel(rawLabel))：\(value)"
    }

    private static func displayFieldValue(
        _ rawLabel: String,
        _ rawValue: String,
        context: [String: String] = [:]
    ) -> String {
        let baseValue = ProjectSkillActivityPresentation.displayFieldValue(
            rawLabel,
            rawValue,
            context: context
        )
        let trimmedLabel = rawLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedValue = baseValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else { return baseValue }

        switch trimmedLabel {
        case "routing_reason_code":
            return routingReasonText(trimmedValue) ?? baseValue
        case "review_verdict":
            return localizedReviewVerdict(trimmedValue)
        case "review_level":
            return localizedReviewLevel(trimmedValue)
        case "supervisor_tier":
            return localizedSupervisorTier(trimmedValue)
        case "work_order_depth":
            return localizedWorkOrderDepth(trimmedValue)
        case "latest_guidance_delivery":
            return localizedGuidanceDeliveryMode(trimmedValue)
        case "pending_guidance_ack":
            return localizedGuidanceAck(trimmedValue)
        case "follow_up_rhythm":
            return ProjectGovernanceActivityDisplay.displayValue(
                label: "follow_up_rhythm",
                value: trimmedValue
            )
        case "result_status", "latest_status":
            return statusLabel(for: trimmedValue)
        default:
            return baseValue
        }
    }

    private static func fieldContext(
        from detail: String
    ) -> [String: String] {
        var context: [String: String] = [:]
        for line in detail.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  let separatorIndex = trimmed.firstIndex(of: "=") else {
                continue
            }
            let key = String(trimmed[..<separatorIndex])
            let value = String(trimmed[trimmed.index(after: separatorIndex)...])
            context[key] = value
        }
        return context
    }

    private static func localizedReviewVerdict(_ value: String) -> String {
        switch normalizedDisplayToken(value) {
        case "on_track":
            return "进展正常"
        case "watch":
            return "需要关注"
        case "better_path_found":
            return "发现更优路径"
        case "wrong_direction":
            return "方向错误"
        case "high_risk":
            return "高风险"
        default:
            return ProjectGovernanceActivityDisplay.displayValue(label: "verdict", value: value)
        }
    }

    private static func localizedReviewLevel(_ value: String) -> String {
        switch normalizedDisplayToken(value) {
        case "r1_pulse":
            return "R1 脉冲"
        case "r2_strategic":
            return "R2 战略"
        case "r3_rescue":
            return "R3 救援"
        default:
            return ProjectGovernanceActivityDisplay.displayValue(label: "level", value: value)
        }
    }

    private static func localizedSupervisorTier(_ value: String) -> String {
        switch normalizedDisplayToken(value) {
        case "s0_silent_audit":
            return "S0 静默审计"
        case "s1_milestone_review":
            return "S1 里程碑审查"
        case "s2_periodic_review":
            return "S2 周期审查"
        case "s3_strategic_coach":
            return "S3 战略教练"
        case "s4_tight_supervision":
            return "S4 紧密监督"
        default:
            return ProjectGovernanceActivityDisplay.displayValue(label: "supervisor_tier", value: value)
        }
    }

    private static func localizedWorkOrderDepth(_ value: String) -> String {
        switch normalizedDisplayToken(value) {
        case "none":
            return "无"
        case "brief":
            return "简要"
        case "milestone_contract":
            return "里程碑合同"
        case "execution_ready":
            return "执行就绪"
        case "step_locked_rescue":
            return "锁步救援"
        default:
            return ProjectGovernanceActivityDisplay.displayValue(label: "work_order_depth", value: value)
        }
    }

    private static func localizedGuidanceDeliveryMode(_ value: String) -> String {
        switch normalizedDisplayToken(value) {
        case "context_append":
            return "上下文追加"
        case "priority_insert":
            return "优先插入"
        case "replan_request":
            return "请求重规划"
        case "stop_signal":
            return "停止信号"
        default:
            return ProjectGovernanceActivityDisplay.displayValue(label: "delivery", value: value)
        }
    }

    private static func localizedGuidanceAck(_ value: String) -> String {
        let components = value
            .split(separator: "·", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !components.isEmpty else { return value }

        let localized = components.map { component in
            switch normalizedDisplayToken(component) {
            case "pending":
                return "待确认"
            case "accepted":
                return "已接受"
            case "deferred":
                return "已暂缓"
            case "rejected":
                return "已拒绝"
            case "required":
                return "必答"
            case "optional":
                return "可选"
            default:
                return component
            }
        }
        return localized.joined(separator: " · ")
    }

    private static func normalizedDisplayToken(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
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
        case .skills_pin:
            return "更新技能可用性"
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

    private static func appendCapabilityContext(
        _ body: String,
        item: SupervisorManager.SupervisorRecentSkillActivity
    ) -> String {
        var lines: [String] = [body]
        lines.append(
            contentsOf: governedApprovalContextLines(
                requestID: item.requestId,
                skillID: item.skillId,
                requestedSkillID: item.requestedSkillId,
                toolName: item.toolName,
                status: item.status,
                deltaApproval: item.record.deltaApproval,
                readiness: item.record.readiness,
                hubStateDirPath: item.record.hubStateDirPath
            )
        )
        return lines.joined(separator: "\n")
    }

    static func governedApprovalContextLines(
        requestID: String,
        skillID: String,
        requestedSkillID: String?,
        toolName: String,
        status: String,
        deltaApproval: XTSkillProfileDeltaApproval?,
        readiness: XTSkillExecutionReadiness?,
        hubStateDirPath: String? = nil
    ) -> [String] {
        let activityItem = governedSkillPresentationItem(
            requestID: requestID,
            skillID: skillID,
            requestedSkillID: requestedSkillID,
            toolName: toolName,
            status: status,
            deltaApproval: deltaApproval,
            readiness: readiness,
            hubStateDirPath: hubStateDirPath
        )

        let deltaLines = XTPendingApprovalPresentation.approvalProfileDeltaLines(for: activityItem)
        var lines: [String] = []

        if let headline = preferredGovernedDeltaHeadline(from: deltaLines) {
            lines.append("能力增量：\(headline)")
        }
        if let gateLine = deltaLines.first(where: { $0.hasPrefix("授权门槛：") }) {
            lines.append(gateLine)
        }

        let runtimeSurfaces = readiness?.requiredRuntimeSurfaces ?? []
        let unblockActions = readiness?.unblockActions ?? []
        let readinessText = nonEmpty(activityItem.executionReadiness).map {
            XTPendingApprovalPresentation.displayExecutionReadiness($0)
        }
        if readinessText != nil || !runtimeSurfaces.isEmpty || !unblockActions.isEmpty {
            var parts: [String] = []
            if let readinessText {
                parts.append("执行就绪：\(readinessText)")
            }
            if !runtimeSurfaces.isEmpty {
                parts.append(
                    "运行面：\(XTPendingApprovalPresentation.displayRuntimeSurfaceList(runtimeSurfaces))"
                )
            }
            if !unblockActions.isEmpty {
                parts.append(
                    "解阻动作：\(XTPendingApprovalPresentation.displayUnblockActionList(unblockActions))"
                )
            }
            lines.append(parts.joined(separator: "；"))
        }

        return lines
    }

    static func governedSkillPresentationItem(
        for item: SupervisorManager.SupervisorRecentSkillActivity
    ) -> ProjectSkillActivityItem {
        governedSkillPresentationItem(
            requestID: item.requestId,
            skillID: item.skillId,
            requestedSkillID: item.requestedSkillId,
            toolName: item.toolName,
            status: item.status,
            deltaApproval: item.record.deltaApproval,
            readiness: item.record.readiness,
            hubStateDirPath: item.record.hubStateDirPath
        )
    }

    static func governedSkillPresentationItem(
        for approval: SupervisorManager.SupervisorPendingSkillApproval
    ) -> ProjectSkillActivityItem {
        governedSkillPresentationItem(
            requestID: approval.requestId,
            skillID: approval.skillId,
            requestedSkillID: approval.requestedSkillId,
            toolName: approval.toolName,
            status: SupervisorSkillCallStatus.awaitingAuthorization.rawValue,
            deltaApproval: approval.deltaApproval,
            readiness: approval.readiness
        )
    }

    static func governedSkillPresentationItem(
        requestID: String,
        skillID: String,
        requestedSkillID: String?,
        toolName: String,
        status: String,
        deltaApproval: XTSkillProfileDeltaApproval?,
        readiness: XTSkillExecutionReadiness?,
        hubStateDirPath: String? = nil
    ) -> ProjectSkillActivityItem {
        ProjectSkillActivityItem(
            requestID: requestID,
            skillID: skillID,
            requestedSkillID: requestedSkillID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            intentFamilies: readiness?.intentFamilies ?? [],
            capabilityFamilies: readiness?.capabilityFamilies ?? [],
            capabilityProfiles: readiness?.capabilityProfiles ?? [],
            toolName: toolName,
            status: status,
            createdAt: 0,
            resolutionSource: "",
            toolArgs: [:],
            routingReasonCode: "",
            routingExplanation: "",
            hubStateDirPath: hubStateDirPath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            executionReadiness: readiness?.executionReadiness ?? "",
            approvalSummary: deltaApproval?.summary ?? "",
            currentRunnableProfiles: deltaApproval?.currentRunnableProfiles ?? [],
            requestedProfiles: deltaApproval?.requestedProfiles ?? [],
            deltaProfiles: deltaApproval?.deltaProfiles ?? [],
            currentRunnableCapabilityFamilies: deltaApproval?.currentRunnableCapabilityFamilies ?? [],
            requestedCapabilityFamilies: deltaApproval?.requestedCapabilityFamilies ?? [],
            deltaCapabilityFamilies: deltaApproval?.deltaCapabilityFamilies ?? [],
            grantFloor: deltaApproval?.grantFloor ?? readiness?.grantFloor ?? "",
            approvalFloor: deltaApproval?.approvalFloor ?? readiness?.approvalFloor ?? "",
            requiredCapability: "",
            resultSummary: "",
            detail: "",
            denyCode: "",
            authorizationDisposition: ""
        )
    }

    private static func isAwaitingRequestScopedLocalApproval(
        _ item: SupervisorManager.SupervisorRecentSkillActivity
    ) -> Bool {
        if item.record.readiness?.executionReadiness == XTSkillExecutionReadinessState.localApprovalRequired.rawValue {
            return true
        }
        if item.record.readiness?.executionReadiness == XTSkillExecutionReadinessState.grantRequired.rawValue {
            return false
        }
        return item.requiredCapability.isEmpty
    }

    private static func normalizedStatus(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func shouldPreferGovernedCardSummary(
        _ item: SupervisorManager.SupervisorRecentSkillActivity
    ) -> Bool {
        if normalizedStatus(item.status) == "awaiting_authorization" {
            return true
        }
        if item.record.deltaApproval != nil || item.record.readiness != nil {
            return true
        }
        return nonEmpty(item.record.hubStateDirPath) != nil
    }

    private static func shouldDisplayCardGovernedDetailLine(
        _ line: String
    ) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return !trimmed.hasPrefix("生效技能：")
            && !trimmed.hasPrefix("请求技能：")
    }

    private static func prioritizedCardGovernedDetailLines(
        _ lines: [String]
    ) -> [String] {
        lines.enumerated()
            .sorted { lhs, rhs in
                let leftPriority = cardGovernedDetailPriority(lhs.element)
                let rightPriority = cardGovernedDetailPriority(rhs.element)
                if leftPriority != rightPriority {
                    return leftPriority < rightPriority
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    private static func cardGovernedDetailPriority(
        _ line: String
    ) -> Int {
        if line.hasPrefix("执行就绪：") { return 0 }
        if line.hasPrefix("治理闸门：") { return 1 }
        if line.hasPrefix("恢复上下文：") { return 2 }
        if line.hasPrefix("能力档位：") { return 3 }
        if line.hasPrefix("能力族：") { return 4 }
        if line.hasPrefix("意图族：") { return 5 }
        return 6
    }

    private static func preferredGovernedDeltaHeadline(
        from lines: [String]
    ) -> String? {
        lines.first(where: { $0.hasPrefix("新增放开：") })
            ?? lines.first(where: { $0.hasPrefix("本次请求：") })
            ?? lines.first(where: { $0.hasPrefix("当前可直接运行：") })
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

    private static func latestRawEventScalar(
        _ key: String,
        from events: [SupervisorSkillRawEvent]
    ) -> String? {
        for event in events.reversed() {
            if let value = nonEmpty(event.rawObject[key]?.stringValue) {
                return value
            }
        }
        return nil
    }

    private static func latestRawEventStringArray(
        _ key: String,
        from events: [SupervisorSkillRawEvent]
    ) -> [String] {
        for event in events.reversed() {
            let values = stringArrayValue(event.rawObject[key])
            if !values.isEmpty {
                return values
            }
        }
        return []
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

    private static func stringArrayValue(_ value: JSONValue?) -> [String] {
        switch value {
        case .array(let values):
            return values.compactMap {
                $0.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }
        case .string(let text):
            return text
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        default:
            return []
        }
    }

    private static func firstNonEmptyStringArray(
        _ arrays: [String]...
    ) -> [String] {
        for array in arrays where !array.isEmpty {
            return array
        }
        return []
    }

    private static func joinedListText(
        _ values: [String]
    ) -> String? {
        let normalized = values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return normalized.isEmpty ? nil : normalized.joined(separator: ", ")
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
