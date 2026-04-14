import Foundation

struct ProjectSkillRecordField: Identifiable, Equatable, Sendable {
    var label: String
    var value: String

    var id: String { label }
}

struct ProjectSkillRecordTimelineEntry: Identifiable, Equatable, Sendable {
    var id: String
    var status: String
    var statusLabel: String
    var timestamp: String
    var summary: String
    var detail: String?
    var rawJSON: String
}

struct ProjectSkillFullRecord: Identifiable, Equatable, Sendable {
    var requestID: String
    var title: String
    var latestStatus: String
    var latestStatusLabel: String
    var requestMetadata: [ProjectSkillRecordField]
    var approvalFields: [ProjectSkillRecordField]
    var governanceFields: [ProjectSkillRecordField]
    var toolArgumentsText: String?
    var resultFields: [ProjectSkillRecordField]
    var rawOutputPreview: String?
    var rawOutput: String?
    var evidenceFields: [ProjectSkillRecordField]
    var approvalHistory: [ProjectSkillRecordTimelineEntry]
    var timeline: [ProjectSkillRecordTimelineEntry]
    var supervisorEvidenceJSON: String?

    var id: String { requestID }
}

enum ProjectSkillActivityPresentation {
    private struct AwaitingApprovalPresentationState {
        var title: String
        var statusLabel: String
        var iconName: String
    }

    static func loadRecentActivities(
        ctx: AXProjectContext,
        limit: Int = 8
    ) -> [ProjectSkillActivityItem] {
        AXProjectSkillActivityStore.loadRecentActivities(
            ctx: ctx,
            limit: limit
        )
    }

    static func parseRecentActivities(
        from raw: String,
        limit: Int = 8
    ) -> [ProjectSkillActivityItem] {
        AXProjectSkillActivityStore.parseRecentActivities(
            from: raw,
            limit: limit
        )
    }

    static func title(for item: ProjectSkillActivityItem) -> String {
        switch normalizedStatus(item.status) {
        case "completed":
            return "技能已完成"
        case "failed":
            return "技能失败"
        case "blocked":
            return "技能受阻"
        case "awaiting_approval":
            return awaitingApprovalPresentation(for: item)?.title ?? "待审批"
        case "resolved":
            return "技能已路由"
        default:
            return "技能动态"
        }
    }

    static func statusLabel(for item: ProjectSkillActivityItem) -> String {
        statusLabel(
            for: item.status,
            executionReadiness: item.executionReadiness,
            requiredCapability: item.requiredCapability
        )
    }

    static func iconName(for item: ProjectSkillActivityItem) -> String {
        switch normalizedStatus(item.status) {
        case "completed":
            return "checkmark.circle.fill"
        case "failed":
            return "xmark.octagon.fill"
        case "blocked":
            return "lock.trianglebadge.exclamationmark.fill"
        case "awaiting_approval":
            return awaitingApprovalPresentation(for: item)?.iconName ?? "hand.raised.fill"
        case "resolved":
            return "point.3.connected.trianglepath.dotted"
        default:
            return "sparkles"
        }
    }

    static func toolBadge(for item: ProjectSkillActivityItem) -> String {
        displayToolName(item.toolName)
    }

    static func skillBadgeText(for item: ProjectSkillActivityItem) -> String {
        skillLabelText(
            requestedSkillID: item.requestedSkillID,
            effectiveSkillID: item.skillID
        ) ?? ""
    }

    static func body(for item: ProjectSkillActivityItem) -> String {
        body(
            for: item,
            includeGovernanceTruthPrefix: true
        )
    }

    static func timelineBody(for item: ProjectSkillActivityItem) -> String {
        body(
            for: item,
            includeGovernanceTruthPrefix: false
        )
    }

    private static func body(
        for item: ProjectSkillActivityItem,
        includeGovernanceTruthPrefix: Bool
    ) -> String {
        let displaySkill = skillBadgeText(for: item)
        let skillLabel = displaySkill.isEmpty
            ? "这个技能"
            : "技能 \(displaySkill)"
        let toolLabel = displayToolName(item.toolName)

        switch normalizedStatus(item.status) {
        case "completed":
            if !item.resultSummary.isEmpty { return item.resultSummary }
            return "\(skillLabel) 已通过\(toolLabel)完成。"
        case "failed":
            if !item.resultSummary.isEmpty { return item.resultSummary }
            if !item.detail.isEmpty { return item.detail }
            return "\(skillLabel) 在执行\(toolLabel)时失败。"
        case "blocked":
            let blockedBody = XTGuardrailMessagePresentation.blockedBody(
                tool: ToolName(rawValue: item.toolName),
                toolLabel: toolLabel,
                denyCode: item.denyCode,
                policySource: item.policySource,
                policyReason: item.policyReason,
                requiredCapability: item.requiredCapability,
                fallbackSummary: item.resultSummary,
                fallbackDetail: item.detail
            )
            if includeGovernanceTruthPrefix,
               let governanceTruth = displayGovernanceTruthLine(for: item) {
                return "\(governanceTruth) \(blockedBody)"
            }
            return blockedBody
        case "awaiting_approval":
            let message = XTPendingApprovalPresentation.approvalMessage(
                toolName: item.toolName,
                tool: ToolName(rawValue: item.toolName),
                toolSummary: requestPreview(for: item) ?? "",
                activity: item
            )
            if let nextStep = nonEmpty(message.nextStep) {
                return "\(message.summary) \(nextStep)"
            }
            return message.summary
        case "resolved":
            if let preview = requestPreview(for: item), !preview.isEmpty {
                return "\(skillLabel) 已路由到\(toolLabel)，目标：\(preview)。"
            }
            return "\(skillLabel) 已路由到\(toolLabel)。"
        default:
            if !item.resultSummary.isEmpty { return item.resultSummary }
            if !item.detail.isEmpty { return item.detail }
            return "\(skillLabel) 有新动态。"
        }
    }

    static func diagnostics(for item: ProjectSkillActivityItem) -> String {
        var lines: [String] = []
        lines.append("request_id=\(item.requestID)")
        if !item.skillID.isEmpty {
            lines.append("skill_id=\(item.skillID)")
        }
        if !item.requestedSkillID.isEmpty {
            lines.append("requested_skill_id=\(item.requestedSkillID)")
        }
        if !item.routingReasonCode.isEmpty {
            lines.append("routing_reason_code=\(item.routingReasonCode)")
        }
        if !item.routingExplanation.isEmpty {
            lines.append("routing_explanation=\(item.routingExplanation)")
        }
        if !item.toolName.isEmpty {
            lines.append("tool_name=\(item.toolName)")
        }
        if !item.status.isEmpty {
            lines.append("status=\(item.status)")
        }
        if !item.executionReadiness.isEmpty {
            lines.append("execution_readiness=\(item.executionReadiness)")
        }
        if !item.requiredRuntimeSurfaces.isEmpty {
            lines.append("required_runtime_surfaces=\(item.requiredRuntimeSurfaces.joined(separator: ","))")
        }
        if !item.unblockActions.isEmpty {
            lines.append("unblock_actions=\(item.unblockActions.joined(separator: ","))")
        }
        if !item.requiredCapability.isEmpty {
            lines.append("required_capability=\(item.requiredCapability)")
        }
        if !item.authorizationDisposition.isEmpty {
            lines.append("authorization_disposition=\(item.authorizationDisposition)")
        }
        if !item.denyCode.isEmpty {
            lines.append("deny_code=\(item.denyCode)")
        }
        if !item.policySource.isEmpty {
            lines.append("policy_source=\(item.policySource)")
        }
        if !item.policyReason.isEmpty {
            lines.append("policy_reason=\(item.policyReason)")
        }
        if let blockedSummary = blockedSummary(for: item) {
            lines.append("blocked_summary=\(blockedSummary)")
        }
        if let governanceReason = governanceReason(for: item) {
            lines.append("governance_reason=\(governanceReason)")
        }
        if let governanceTruth = governanceTruthLine(for: item) {
            lines.append("governance_truth=\(governanceTruth)")
        }
        if let repairAction = repairActionSummary(for: item) {
            lines.append("repair_action=\(repairAction)")
        }
        if !item.approvalSummary.isEmpty {
            lines.append("approval_summary=\(item.approvalSummary)")
        }
        if !item.currentRunnableProfiles.isEmpty {
            lines.append("current_runnable_profiles=\(item.currentRunnableProfiles.joined(separator: ","))")
        }
        if !item.requestedProfiles.isEmpty {
            lines.append("requested_profiles=\(item.requestedProfiles.joined(separator: ","))")
        }
        if !item.deltaProfiles.isEmpty {
            lines.append("delta_profiles=\(item.deltaProfiles.joined(separator: ","))")
        }
        if !item.currentRunnableCapabilityFamilies.isEmpty {
            lines.append(
                "current_runnable_capability_families=\(item.currentRunnableCapabilityFamilies.joined(separator: ","))"
            )
        }
        if !item.requestedCapabilityFamilies.isEmpty {
            lines.append(
                "requested_capability_families=\(item.requestedCapabilityFamilies.joined(separator: ","))"
            )
        }
        if !item.deltaCapabilityFamilies.isEmpty {
            lines.append(
                "delta_capability_families=\(item.deltaCapabilityFamilies.joined(separator: ","))"
            )
        }
        if !item.grantFloor.isEmpty {
            lines.append("grant_floor=\(item.grantFloor)")
        }
        if !item.approvalFloor.isEmpty {
            lines.append("approval_floor=\(item.approvalFloor)")
        }
        if !item.resolutionSource.isEmpty {
            lines.append("resolution_source=\(item.resolutionSource)")
        }
        if !item.resultSummary.isEmpty {
            lines.append("result_summary=\(item.resultSummary)")
        }
        if !item.detail.isEmpty {
            lines.append("detail=\(item.detail)")
        }
        if !item.toolArgs.isEmpty,
           let data = try? JSONEncoder().encode(item.toolArgs),
           let text = String(data: data, encoding: .utf8) {
            lines.append("tool_args=\(text)")
        }
        return lines.joined(separator: "\n")
    }

    static func isAwaitingApproval(_ item: ProjectSkillActivityItem) -> Bool {
        normalizedStatus(item.status) == "awaiting_approval"
    }

    static func canRetry(_ item: ProjectSkillActivityItem) -> Bool {
        switch normalizedStatus(item.status) {
        case "failed", "blocked":
            return true
        default:
            return false
        }
    }

    static func fullRecord(
        ctx: AXProjectContext,
        requestID: String
    ) -> ProjectSkillFullRecord? {
        let events = AXProjectSkillActivityStore.loadEvents(
            ctx: ctx,
            requestID: requestID
        )
        let supervisorCall = SupervisorProjectSkillCallStore.load(for: ctx)
            .calls
            .first(where: { $0.requestId == requestID })
        let evidence = SupervisorSkillResultEvidenceStore.load(
            requestId: requestID,
            for: ctx
        )

        guard !events.isEmpty || evidence != nil || supervisorCall != nil else {
            return nil
        }

        let latest = events.last?.item
        let skillID = firstNonEmpty(
            latest?.skillID,
            evidence?.skillId,
            supervisorCall?.skillId
        )
        let requestedSkillID = firstNonEmpty(
            latest?.requestedSkillID,
            latestRawEventScalar("requested_skill_id", from: events),
            evidence?.requestedSkillId,
            supervisorCall?.requestedSkillId
        )
        let toolName = firstNonEmpty(
            latest?.toolName,
            evidence?.toolName,
            supervisorCall?.toolName
        )
        let latestStatus = firstNonEmpty(
            latest?.status,
            evidence?.status,
            supervisorCall?.status.rawValue
        ) ?? ""
        let latestPolicySource = firstNonEmpty(
            events
                .reversed()
                .compactMap { nonEmpty($0.item.policySource) }
                .first,
            evidence?.policySource,
            supervisorCall?.policySource
        )
        let latestDenyCode = firstNonEmpty(
            latest?.denyCode,
            evidence?.denyCode,
            supervisorCall?.denyCode
        )
        let latestResolutionSource = firstNonEmpty(
            latest?.resolutionSource,
            latestRawEventScalar("resolution_source", from: events)
        )
        let latestRoutingReasonCode = firstNonEmpty(
            latest?.routingReasonCode,
            latestRawEventScalar("routing_reason_code", from: events),
            evidence?.routingReasonCode,
            supervisorCall?.routingReasonCode
        )
        let latestRoutingExplanation = firstNonEmpty(
            latest?.routingExplanation,
            latestRawEventScalar("routing_explanation", from: events),
            evidence?.routingExplanation,
            supervisorCall?.routingExplanation
        )
        let latestPolicyReason = firstNonEmpty(
            events
                .reversed()
                .compactMap { nonEmpty($0.item.policyReason) }
                .first,
            evidence?.policyReason,
            supervisorCall?.policyReason
        )
        let persistedDeltaApproval = evidence?.deltaApproval ?? supervisorCall?.deltaApproval
        let persistedReadiness = evidence?.readiness ?? supervisorCall?.readiness
        let latestIntentFamilies = firstNonEmptyStringArray(
            latest?.intentFamilies ?? [],
            latestRawEventStringArray("intent_families", from: events),
            persistedReadiness?.intentFamilies ?? []
        )
        let latestCapabilityFamilies = firstNonEmptyStringArray(
            latest?.capabilityFamilies ?? [],
            latestRawEventStringArray("capability_families", from: events),
            persistedReadiness?.capabilityFamilies ?? []
        )
        let latestCapabilityProfiles = firstNonEmptyStringArray(
            latest?.capabilityProfiles ?? [],
            latestRawEventStringArray("capability_profiles", from: events),
            persistedReadiness?.capabilityProfiles ?? []
        )
        let latestRequiredCapability = firstNonEmpty(
            latest?.requiredCapability,
            latestRawEventScalar("required_capability", from: events),
            supervisorCall?.requiredCapability
        )
        let latestAuthorizationDisposition = firstNonEmpty(
            latest?.authorizationDisposition,
            latestRawEventScalar("authorization_disposition", from: events)
        )
        let latestExecutionReadiness = firstNonEmpty(
            latest?.executionReadiness,
            latestRawEventScalar("execution_readiness", from: events),
            persistedReadiness?.executionReadiness
        )
        let latestRequiredRuntimeSurfaces = firstNonEmptyStringArray(
            latest?.requiredRuntimeSurfaces ?? [],
            latestRawEventStringArray("required_runtime_surfaces", from: events),
            persistedReadiness?.requiredRuntimeSurfaces ?? []
        )
        let latestUnblockActions = firstNonEmptyStringArray(
            latest?.unblockActions ?? [],
            latestRawEventStringArray("unblock_actions", from: events),
            persistedReadiness?.unblockActions ?? []
        )
        let latestApprovalSummary = firstNonEmpty(
            latest?.approvalSummary,
            latestRawEventScalar("approval_summary", from: events),
            persistedDeltaApproval?.summary
        )
        let latestCurrentRunnableProfiles = firstNonEmptyStringArray(
            latest?.currentRunnableProfiles ?? [],
            latestRawEventStringArray("current_runnable_profiles", from: events),
            persistedDeltaApproval?.currentRunnableProfiles ?? []
        )
        let latestRequestedProfiles = firstNonEmptyStringArray(
            latest?.requestedProfiles ?? [],
            latestRawEventStringArray("requested_profiles", from: events),
            persistedDeltaApproval?.requestedProfiles ?? []
        )
        let latestDeltaProfiles = firstNonEmptyStringArray(
            latest?.deltaProfiles ?? [],
            latestRawEventStringArray("delta_profiles", from: events),
            persistedDeltaApproval?.deltaProfiles ?? []
        )
        let latestCurrentRunnableCapabilityFamilies = firstNonEmptyStringArray(
            latest?.currentRunnableCapabilityFamilies ?? [],
            latestRawEventStringArray("current_runnable_capability_families", from: events),
            persistedDeltaApproval?.currentRunnableCapabilityFamilies ?? []
        )
        let latestRequestedCapabilityFamilies = firstNonEmptyStringArray(
            latest?.requestedCapabilityFamilies ?? [],
            latestRawEventStringArray("requested_capability_families", from: events),
            persistedDeltaApproval?.requestedCapabilityFamilies ?? []
        )
        let latestDeltaCapabilityFamilies = firstNonEmptyStringArray(
            latest?.deltaCapabilityFamilies ?? [],
            latestRawEventStringArray("delta_capability_families", from: events),
            persistedDeltaApproval?.deltaCapabilityFamilies ?? []
        )
        let latestGrantFloor = firstNonEmpty(
            latest?.grantFloor,
            latestRawEventScalar("grant_floor", from: events),
            persistedDeltaApproval?.grantFloor,
            persistedReadiness?.grantFloor
        )
        let latestApprovalFloor = firstNonEmpty(
            latest?.approvalFloor,
            latestRawEventScalar("approval_floor", from: events),
            persistedDeltaApproval?.approvalFloor,
            persistedReadiness?.approvalFloor
        )
        let approvalGovernanceReason = firstNonEmpty(
            latestRawEventScalar("governance_reason", from: events),
            XTGuardrailMessagePresentation.governanceReasonSummary(
                tool: toolName.flatMap(ToolName.init(rawValue:)),
                toolLabel: displayToolName(toolName ?? ""),
                denyCode: latestDenyCode ?? "",
                policySource: latestPolicySource ?? "",
                policyReason: latestPolicyReason ?? "",
                requiredCapability: latestRequiredCapability ?? ""
            )
        )
        let latestResultSummary = firstNonEmpty(
            evidence?.resultSummary,
            latest?.resultSummary,
            supervisorCall?.resultSummary
        )
        let approvalBlockedSummary = firstNonEmpty(
            latestRawEventScalar("blocked_summary", from: events),
            XTGuardrailMessagePresentation.blockedSummary(
                tool: toolName.flatMap(ToolName.init(rawValue:)),
                toolLabel: displayToolName(toolName ?? ""),
                denyCode: latestDenyCode ?? "",
                policySource: latestPolicySource ?? "",
                policyReason: latestPolicyReason ?? "",
                requiredCapability: latestRequiredCapability ?? "",
                fallbackSummary: latestResultSummary ?? "",
                fallbackDetail: latest?.detail ?? ""
            )
        )
        let approvalGovernanceTruth = firstNonEmpty(
            latestRawEventScalar("governance_truth", from: events),
            events
                .reversed()
                .compactMap { XTGovernanceTruthPresentation.effectiveTierSummary(from: $0.rawObject) }
                .first
        )
        let latestRepairAction = firstNonEmpty(
            latestRawEventScalar("repair_action", from: events),
            events
                .reversed()
                .compactMap { repairActionSummary(for: $0.item) }
                .first
        )
        let toolArgsText = preferredToolArgumentsText(
            latestToolArgs: latest?.toolArgs ?? [:],
            evidenceToolArgs: evidence?.toolArgs
        )
        let title = firstNonEmpty(
            skillLabelText(
                requestedSkillID: requestedSkillID,
                effectiveSkillID: skillID
            ),
            skillID
        ) ?? "技能记录"

        let requestMetadata = recordFields([
            ("request_id", requestID),
            ("skill_id", skillID),
            ("requested_skill_id", requestedSkillID),
            ("intent_families", joinedListText(latestIntentFamilies)),
            ("capability_families", joinedListText(latestCapabilityFamilies)),
            ("capability_profiles", joinedListText(latestCapabilityProfiles)),
            ("tool_name", toolName),
            ("latest_status", latestStatus),
            ("resolution_source", latestResolutionSource),
            ("routing_reason_code", latestRoutingReasonCode),
            ("routing_explanation", latestRoutingExplanation),
            ("project_id", firstNonEmpty(evidence?.projectId, supervisorCall?.projectId)),
            ("job_id", firstNonEmpty(evidence?.jobId, supervisorCall?.jobId)),
            ("plan_id", firstNonEmpty(evidence?.planId, supervisorCall?.planId)),
            ("step_id", firstNonEmpty(evidence?.stepId, supervisorCall?.stepId)),
            ("current_owner", supervisorCall?.currentOwner),
            ("trigger_source", evidence?.triggerSource),
            ("created_at", createdAtText(events: events, supervisorCall: supervisorCall)),
            ("updated_at", updatedAtText(evidence: evidence, supervisorCall: supervisorCall))
        ])

        let approvalFields = recordFields([
            ("authorization_disposition", latestAuthorizationDisposition),
            ("deny_code", latestDenyCode),
            ("execution_readiness", latestExecutionReadiness),
            ("required_runtime_surfaces", joinedListText(latestRequiredRuntimeSurfaces)),
            ("unblock_actions", joinedListText(latestUnblockActions)),
            ("approval_summary", latestApprovalSummary),
            ("current_runnable_profiles", joinedListText(latestCurrentRunnableProfiles)),
            ("requested_profiles", joinedListText(latestRequestedProfiles)),
            ("delta_profiles", joinedListText(latestDeltaProfiles)),
            ("current_runnable_capability_families", joinedListText(latestCurrentRunnableCapabilityFamilies)),
            ("requested_capability_families", joinedListText(latestRequestedCapabilityFamilies)),
            ("delta_capability_families", joinedListText(latestDeltaCapabilityFamilies)),
            ("grant_floor", latestGrantFloor),
            ("approval_floor", latestApprovalFloor),
            ("required_capability", latestRequiredCapability),
            ("grant_request_id", supervisorCall?.grantRequestId),
            ("grant_id", supervisorCall?.grantId)
        ])

        let governanceFields = recordFields([
            ("policy_source", latestPolicySource),
            ("policy_reason", latestPolicyReason),
            ("governance_reason", approvalGovernanceReason),
            ("blocked_summary", approvalBlockedSummary),
            ("governance_truth", approvalGovernanceTruth),
            ("repair_action", latestRepairAction)
        ])

        let resultFields = recordFields([
            ("result_status", firstNonEmpty(evidence?.status, latest?.status, supervisorCall?.status.rawValue)),
            ("result_summary", latestResultSummary),
            ("detail", latest?.detail),
            ("raw_output_chars", evidence.flatMap { $0.rawOutputChars > 0 ? String($0.rawOutputChars) : nil })
        ])

        let evidenceFields = recordFields([
            ("result_evidence_ref", firstNonEmpty(evidence?.resultEvidenceRef, supervisorCall?.resultEvidenceRef)),
            ("raw_output_ref", evidence?.rawOutputRef),
            ("audit_ref", firstNonEmpty(evidence?.auditRef, supervisorCall?.auditRef))
        ])

        let timeline = events.enumerated().map { offset, event in
            timelineEntry(for: event, fallbackIndex: offset)
        }
        let approvalHistory = timeline.filter { entry in
            isApprovalTimelineStatus(entry.status)
        }

        return ProjectSkillFullRecord(
            requestID: requestID,
            title: title,
            latestStatus: latestStatus,
            latestStatusLabel: statusLabel(
                for: latestStatus,
                executionReadiness: latestExecutionReadiness ?? "",
                requiredCapability: latestRequiredCapability ?? ""
            ),
            requestMetadata: requestMetadata,
            approvalFields: approvalFields,
            governanceFields: governanceFields,
            toolArgumentsText: toolArgsText,
            resultFields: resultFields,
            rawOutputPreview: nonEmpty(evidence?.rawOutputPreview),
            rawOutput: nonEmpty(evidence?.rawOutput),
            evidenceFields: evidenceFields,
            approvalHistory: approvalHistory,
            timeline: timeline,
            supervisorEvidenceJSON: evidence.map(encodedJSONText)
        )
    }

    static func fullRecordText(
        ctx: AXProjectContext,
        requestID: String
    ) -> String {
        guard let record = fullRecord(ctx: ctx, requestID: requestID) else {
            return "没有找到请求单号为 \(requestID) 的技能记录。"
        }
        return fullRecordText(record)
    }

    static func displayFullRecordText(
        _ record: ProjectSkillFullRecord
    ) -> String {
        var lines: [String] = [
            "项目技能完整记录",
            "请求单号：\(record.requestID)"
        ]

        if !record.latestStatusLabel.isEmpty {
            lines.append("最新状态：\(record.latestStatusLabel)")
        }

        appendDisplayRecordSection("请求信息", fields: record.requestMetadata, into: &lines)
        appendDisplayRecordSection("审批状态", fields: record.approvalFields, into: &lines)
        appendDisplayRecordSection("治理上下文", fields: record.governanceFields, into: &lines)

        if let toolArgs = nonEmpty(record.toolArgumentsText) {
            lines.append("")
            lines.append("== 工具参数 ==")
            lines.append(toolArgs)
        }

        appendDisplayRecordSection("执行结果", fields: record.resultFields, into: &lines)

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

        appendDisplayRecordSection("证据引用", fields: record.evidenceFields, into: &lines)

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

    static func fullRecordText(
        _ record: ProjectSkillFullRecord
    ) -> String {
        var lines: [String] = [
            "项目技能完整记录",
            "请求单号：\(record.requestID)"
        ]

        if !record.latestStatus.isEmpty {
            lines.append("latest_status=\(record.latestStatus)")
        }

        appendRecordSection("请求信息", fields: record.requestMetadata, into: &lines)
        appendRecordSection("审批状态", fields: record.approvalFields, into: &lines)
        appendRecordSection("治理上下文", fields: record.governanceFields, into: &lines)

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

    static func displayFieldLabel(_ raw: String) -> String {
        switch raw {
        case "deny_code":
            return "拒绝原因"
        case "routing_reason_code":
            return "路由判定"
        default:
            break
        }
        return humanRecordFieldLabel(raw)
    }

    static func displayFieldValue(
        _ rawLabel: String,
        _ rawValue: String,
        context: [String: String] = [:]
    ) -> String {
        let cleanedLabel = rawLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        switch cleanedLabel {
        case "deny_code", "拒绝码", "拒绝原因", "拒绝原因码":
            return XTGuardrailMessagePresentation.displayDenyCode(
                rawValue,
                requiredCapability: context["required_capability"] ?? ""
            )
        case "execution_readiness", "执行就绪":
            return XTPendingApprovalPresentation.displayExecutionReadiness(rawValue)
        case "grant_floor", "授权门槛":
            return XTPendingApprovalPresentation.displayGrantFloor(rawValue)
        case "approval_floor", "审批门槛":
            return XTPendingApprovalPresentation.displayApprovalFloor(rawValue)
        case "required_capability", "所需能力":
            return XTGuardrailMessagePresentation.displayCapability(rawValue)
        case "required_runtime_surfaces", "运行面", "所需运行面":
            return XTPendingApprovalPresentation.displayRuntimeSurfaceList(rawValue)
        case "unblock_actions", "解阻动作":
            return XTPendingApprovalPresentation.displayUnblockActionList(rawValue)
        case "capability_families", "能力族",
            "current_runnable_capability_families", "当前可直接运行能力族",
            "requested_capability_families", "本次请求能力族",
            "delta_capability_families", "新增放开能力族":
            return XTPendingApprovalPresentation.displayCapabilityFamilies(rawValue)
        case "intent_families", "意图族",
            "capability_profiles", "能力档位",
            "current_runnable_profiles", "当前可直接运行档位",
            "requested_profiles", "本次请求档位",
            "delta_profiles", "新增放开档位":
            return XTPendingApprovalPresentation.displayIdentifierList(rawValue)
        case "governance_truth", "治理真相":
            return XTGovernanceTruthPresentation.displayText(rawValue)
        case "routing_reason_code", "路由判定", "路由原因码":
            return routingReasonText(rawValue) ?? rawValue
        case "routing_explanation", "路由说明":
            return routingNarrative(
                requestedSkillId: context["requested_skill_id"],
                effectiveSkillId: context["skill_id"] ?? "",
                routingReasonCode: context["routing_reason_code"],
                routingExplanation: rawValue
            ) ?? rawValue
        default:
            return rawValue
        }
    }

    static func displayTimelineDetail(_ detail: String?) -> String? {
        guard let detail = nonEmpty(detail) else { return nil }
        let context = fieldContext(from: detail)
        let lines = detail
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { displayTimelineDetailLine(String($0), context: context) }
        return lines.joined(separator: "\n")
    }

    static func governanceTruthLine(
        for item: ProjectSkillActivityItem
    ) -> String? {
        nonEmpty(item.governanceTruth)
    }

    static func displayGovernanceTruthLine(
        for item: ProjectSkillActivityItem
    ) -> String? {
        governanceTruthLine(for: item).map(XTGovernanceTruthPresentation.displayText)
    }

    static func blockedSummary(
        for item: ProjectSkillActivityItem
    ) -> String? {
        if let persisted = nonEmpty(item.blockedSummary) {
            return persisted
        }
        switch normalizedStatus(item.status) {
        case "blocked":
            return XTGuardrailMessagePresentation.blockedSummary(
                tool: ToolName(rawValue: item.toolName),
                toolLabel: displayToolName(item.toolName),
                denyCode: item.denyCode,
                policySource: item.policySource,
                policyReason: item.policyReason,
                requiredCapability: item.requiredCapability,
                fallbackSummary: item.resultSummary,
                fallbackDetail: item.detail
            ) ?? firstNonEmpty(item.resultSummary, item.detail)
        case "failed":
            guard !item.denyCode.isEmpty || !item.policySource.isEmpty || !item.policyReason.isEmpty else {
                return nil
            }
            return XTGuardrailMessagePresentation.blockedSummary(
                tool: ToolName(rawValue: item.toolName),
                toolLabel: displayToolName(item.toolName),
                denyCode: item.denyCode,
                policySource: item.policySource,
                policyReason: item.policyReason,
                requiredCapability: item.requiredCapability,
                fallbackSummary: item.resultSummary,
                fallbackDetail: item.detail
            ) ?? firstNonEmpty(item.resultSummary, item.detail)
        default:
            return nil
        }
    }

    static func policyReason(
        for item: ProjectSkillActivityItem
    ) -> String? {
        nonEmpty(item.policyReason)
    }

    static func governanceReason(
        for item: ProjectSkillActivityItem
    ) -> String? {
        if let persisted = nonEmpty(item.governanceReason) {
            return persisted
        }
        return XTGuardrailMessagePresentation.governanceReasonSummary(
            tool: ToolName(rawValue: item.toolName),
            toolLabel: displayToolName(item.toolName),
            denyCode: item.denyCode,
            policySource: item.policySource,
            policyReason: item.policyReason,
            requiredCapability: item.requiredCapability
        )
    }

    static func repairActionSummary(
        for item: ProjectSkillActivityItem
    ) -> String? {
        if let persisted = nonEmpty(item.repairAction) {
            return persisted
        }
        guard let repairHint = XTGuardrailMessagePresentation.repairHint(
            denyCode: item.denyCode,
            policySource: item.policySource,
            policyReason: item.policyReason
        ) else {
            return nil
        }
        return "\(repairHint.buttonTitle)：\(repairHint.helpText)"
    }

    static func governedShortSummary(
        for item: ProjectSkillActivityItem
    ) -> String? {
        XTPendingApprovalPresentation.governedSkillShortSummary(for: item)
    }

    static func governedDetailLines(
        for item: ProjectSkillActivityItem
    ) -> [String] {
        XTPendingApprovalPresentation.governedSkillDetailLines(for: item)
    }

    static func cardGovernedDetailLines(
        for item: ProjectSkillActivityItem,
        limit: Int = 2
    ) -> [String] {
        guard limit > 0 else { return [] }
        let requestedSkillID = item.requestedSkillID.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveSkillID = item.skillID.trimmingCharacters(in: .whitespacesAndNewlines)
        let shouldShow = normalizedStatus(item.status) == "awaiting_approval"
            || !item.approvalSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !item.executionReadiness.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !item.hubStateDirPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || (!requestedSkillID.isEmpty && requestedSkillID != effectiveSkillID)
        guard shouldShow else { return [] }

        var lines: [String] = []
        if let readiness = nonEmpty(item.executionReadiness) {
            lines.append("执行就绪：\(XTPendingApprovalPresentation.displayExecutionReadiness(readiness))")
        }

        var blockerParts: [String] = []
        if !item.requiredRuntimeSurfaces.isEmpty {
            blockerParts.append(
                "运行面：\(XTPendingApprovalPresentation.displayRuntimeSurfaceList(item.requiredRuntimeSurfaces))"
            )
        }
        if !item.unblockActions.isEmpty {
            blockerParts.append(
                "解阻动作：\(XTPendingApprovalPresentation.displayUnblockActionList(item.unblockActions))"
            )
        }
        if !blockerParts.isEmpty {
            lines.append(blockerParts.joined(separator: "；"))
        }

        let detailLines = governedDetailLines(for: item).filter { line in
            !line.hasPrefix("生效技能：")
                && !line.hasPrefix("请求技能：")
                && !line.hasPrefix("执行就绪：")
                && !line.hasPrefix("运行面：")
                && !line.hasPrefix("解阻动作：")
        }

        if let gateLine = detailLines.first(where: { $0.hasPrefix("治理闸门：") }) {
            lines.append(gateLine)
        }
        if let approvalSummary = nonEmpty(item.approvalSummary) {
            lines.append("能力增量：\(approvalSummary)")
        }
        lines.append(contentsOf: detailLines.filter { line in
            !line.hasPrefix("治理闸门：")
        })

        return Array(uniqueDisplayLines(lines).prefix(limit))
    }

    private static func requestPreview(for item: ProjectSkillActivityItem) -> String? {
        let preferredKeys = ["url", "query", "path", "selector", "command", "action"]
        for key in preferredKeys {
            let value = item.toolArgs[key]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !value.isEmpty else { continue }
        switch key {
        case "url":
            return value
        case "query":
            return "查询 '\(value)'"
        case "path":
            return "路径 \(value)"
        case "selector":
            return "选择器 \(value)"
        case "command":
            return "命令 \(value)"
        case "action":
            return "动作 \(value)"
        default:
            return value
        }
        }
        return nil
    }

    private static func displayToolName(_ raw: String) -> String {
        XTPendingApprovalPresentation.displayToolName(
            raw: raw,
            tool: ToolName(rawValue: raw)
        )
    }

    private static func normalizedStatus(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func uniqueDisplayLines(
        _ lines: [String]
    ) -> [String] {
        var seen: Set<String> = []
        var output: [String] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if seen.insert(trimmed).inserted {
                output.append(trimmed)
            }
        }
        return output
    }

    private static func statusLabel(
        for rawStatus: String,
        executionReadiness: String = "",
        requiredCapability: String = ""
    ) -> String {
        switch normalizedStatus(rawStatus) {
        case "completed":
            return "已完成"
        case "failed":
            return "失败"
        case "blocked":
            return "受阻"
        case "awaiting_approval":
            return awaitingApprovalPresentation(
                executionReadiness: executionReadiness,
                requiredCapability: requiredCapability
            )?.statusLabel ?? "待审批"
        case "resolved":
            return "已路由"
        default:
            return rawStatus.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "未知" : rawStatus
        }
    }

    private static func formattedTimelineEntry(
        _ event: AXProjectSkillActivityEvent
    ) -> String {
        formattedTimelineEntry(
            timelineEntry(for: event, fallbackIndex: event.lineIndex)
        )
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

    private static func timelineEntry(
        for event: AXProjectSkillActivityEvent,
        fallbackIndex: Int
    ) -> ProjectSkillRecordTimelineEntry {
        ProjectSkillRecordTimelineEntry(
            id: "\(event.item.requestID)-\(fallbackIndex)-\(Int((event.item.createdAt * 1000.0).rounded()))",
            status: event.item.status,
            statusLabel: statusLabel(for: event.item),
            timestamp: formattedTimestamp(event.item.createdAt),
            summary: timelineBody(for: event.item),
            detail: timelineDetail(event),
            rawJSON: AXProjectSkillActivityStore.prettyJSONString(for: event.rawObject)
        )
    }

    private static func timelineDetail(
        _ event: AXProjectSkillActivityEvent
    ) -> String? {
        var lines: [String] = []
        if !event.item.resultSummary.isEmpty {
            lines.append("result_summary=\(event.item.resultSummary)")
        }
        if !event.item.approvalSummary.isEmpty {
            lines.append("approval_summary=\(event.item.approvalSummary)")
        }
        if !event.item.detail.isEmpty {
            lines.append("detail=\(event.item.detail)")
        }
        if !event.item.denyCode.isEmpty {
            lines.append("deny_code=\(event.item.denyCode)")
        }
        if !event.item.requiredCapability.isEmpty {
            lines.append("required_capability=\(event.item.requiredCapability)")
        }
        if !event.item.authorizationDisposition.isEmpty {
            lines.append("authorization_disposition=\(event.item.authorizationDisposition)")
        }
        if !event.item.policySource.isEmpty {
            lines.append("policy_source=\(event.item.policySource)")
        }
        if !event.item.policyReason.isEmpty {
            lines.append("policy_reason=\(event.item.policyReason)")
        }
        if let governanceReason = governanceReason(for: event.item) {
            lines.append("governance_reason=\(governanceReason)")
        }
        if let governanceTruth = governanceTruthLine(for: event.item) {
            lines.append("governance_truth=\(governanceTruth)")
        }
        if let repairAction = repairActionSummary(for: event.item) {
            lines.append("repair_action=\(repairAction)")
        }
        if !event.item.resolutionSource.isEmpty {
            lines.append("resolution_source=\(event.item.resolutionSource)")
        }
        if !event.item.requestedSkillID.isEmpty {
            lines.append("requested_skill_id=\(event.item.requestedSkillID)")
        }
        if !event.item.intentFamilies.isEmpty {
            lines.append("intent_families=\(event.item.intentFamilies.joined(separator: ","))")
        }
        if !event.item.capabilityFamilies.isEmpty {
            lines.append("capability_families=\(event.item.capabilityFamilies.joined(separator: ","))")
        }
        if !event.item.capabilityProfiles.isEmpty {
            lines.append("capability_profiles=\(event.item.capabilityProfiles.joined(separator: ","))")
        }
        if !event.item.routingReasonCode.isEmpty {
            lines.append("routing_reason_code=\(event.item.routingReasonCode)")
        }
        if !event.item.routingExplanation.isEmpty {
            lines.append("routing_explanation=\(event.item.routingExplanation)")
        }
        if !event.item.executionReadiness.isEmpty {
            lines.append("execution_readiness=\(event.item.executionReadiness)")
        }
        if !event.item.requiredRuntimeSurfaces.isEmpty {
            lines.append("required_runtime_surfaces=\(event.item.requiredRuntimeSurfaces.joined(separator: ","))")
        }
        if !event.item.unblockActions.isEmpty {
            lines.append("unblock_actions=\(event.item.unblockActions.joined(separator: ","))")
        }
        if !event.item.currentRunnableProfiles.isEmpty {
            lines.append("current_runnable_profiles=\(event.item.currentRunnableProfiles.joined(separator: ","))")
        }
        if !event.item.requestedProfiles.isEmpty {
            lines.append("requested_profiles=\(event.item.requestedProfiles.joined(separator: ","))")
        }
        if !event.item.deltaProfiles.isEmpty {
            lines.append("delta_profiles=\(event.item.deltaProfiles.joined(separator: ","))")
        }
        if !event.item.currentRunnableCapabilityFamilies.isEmpty {
            lines.append(
                "current_runnable_capability_families=\(event.item.currentRunnableCapabilityFamilies.joined(separator: ","))"
            )
        }
        if !event.item.requestedCapabilityFamilies.isEmpty {
            lines.append(
                "requested_capability_families=\(event.item.requestedCapabilityFamilies.joined(separator: ","))"
            )
        }
        if !event.item.deltaCapabilityFamilies.isEmpty {
            lines.append(
                "delta_capability_families=\(event.item.deltaCapabilityFamilies.joined(separator: ","))"
            )
        }
        if !event.item.grantFloor.isEmpty {
            lines.append("grant_floor=\(event.item.grantFloor)")
        }
        if !event.item.approvalFloor.isEmpty {
            lines.append("approval_floor=\(event.item.approvalFloor)")
        }
        if !event.item.toolArgs.isEmpty,
           let data = try? JSONEncoder().encode(event.item.toolArgs),
           let text = String(data: data, encoding: .utf8) {
            lines.append("tool_args=\(text)")
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    private static func isApprovalTimelineStatus(
        _ rawStatus: String
    ) -> Bool {
        switch normalizedStatus(rawStatus) {
        case "awaiting_approval", "blocked":
            return true
        default:
            return false
        }
    }

    private static func recordFields(
        _ pairs: [(String, String?)]
    ) -> [ProjectSkillRecordField] {
        pairs.compactMap { label, value in
            guard let text = nonEmpty(value) else { return nil }
            return ProjectSkillRecordField(label: label, value: text)
        }
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
            lines.append("\(humanRecordFieldLabel(field.label))：\(field.value)")
        }
    }

    private static func appendDisplayRecordSection(
        _ title: String,
        fields: [ProjectSkillRecordField],
        into lines: inout [String]
    ) {
        guard !fields.isEmpty else { return }
        let context = Dictionary(uniqueKeysWithValues: fields.map { ($0.label, $0.value) })
        lines.append("")
        lines.append("== \(title) ==")
        for field in fields {
            lines.append(
                "\(displayFieldLabel(field.label))：\(displayFieldValue(field.label, field.value, context: context))"
            )
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

    private static func preferredToolArgumentsText(
        latestToolArgs: [String: JSONValue],
        evidenceToolArgs: [String: JSONValue]?
    ) -> String? {
        if let evidenceToolArgs, !evidenceToolArgs.isEmpty {
            return AXProjectSkillActivityStore.prettyJSONString(for: evidenceToolArgs)
        }
        guard !latestToolArgs.isEmpty else { return nil }
        return AXProjectSkillActivityStore.prettyJSONString(for: latestToolArgs)
    }

    private static func createdAtText(
        events: [AXProjectSkillActivityEvent],
        supervisorCall: SupervisorSkillCallRecord?
    ) -> String? {
        if let first = events.first?.item.createdAt, first > 0 {
            return formattedTimestamp(first)
        }
        guard let createdAtMs = supervisorCall?.createdAtMs, createdAtMs > 0 else { return nil }
        return formattedTimestamp(Double(createdAtMs) / 1000.0)
    }

    private static func updatedAtText(
        evidence: SupervisorSkillResultEvidence?,
        supervisorCall: SupervisorSkillCallRecord?
    ) -> String? {
        if let updatedAtMs = evidence?.updatedAtMs, updatedAtMs > 0 {
            return formattedTimestamp(Double(updatedAtMs) / 1000.0)
        }
        guard let updatedAtMs = supervisorCall?.updatedAtMs, updatedAtMs > 0 else { return nil }
        return formattedTimestamp(Double(updatedAtMs) / 1000.0)
    }

    private static func nonEmpty(
        _ value: String?
    ) -> String? {
        guard let text = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            return nil
        }
        return text
    }

    private static func firstNonEmpty(
        _ candidates: String?...
    ) -> String? {
        for candidate in candidates {
            if let value = nonEmpty(candidate) {
                return value
            }
        }
        return nil
    }

    private static func latestRawEventScalar(
        _ key: String,
        from events: [AXProjectSkillActivityEvent]
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
        from events: [AXProjectSkillActivityEvent]
    ) -> [String] {
        for event in events.reversed() {
            let values = stringArrayValue(event.rawObject[key])
            if !values.isEmpty {
                return values
            }
        }
        return []
    }

    private static func humanRecordFieldLabel(_ raw: String) -> String {
        switch raw {
        case "request_id":
            return "请求单号"
        case "skill_id":
            return "技能 ID"
        case "requested_skill_id":
            return "请求技能 ID"
        case "intent_families":
            return "意图族"
        case "capability_families":
            return "能力族"
        case "capability_profiles":
            return "能力档位"
        case "tool_name":
            return "工具"
        case "latest_status":
            return "最新状态"
        case "resolution_source":
            return "处理来源"
        case "routing_reason_code":
            return "路由判定"
        case "routing_explanation":
            return "路由说明"
        case "project_id":
            return "项目 ID"
        case "job_id":
            return "任务 ID"
        case "plan_id":
            return "计划 ID"
        case "step_id":
            return "步骤 ID"
        case "current_owner":
            return "当前执行方"
        case "trigger_source":
            return "触发来源"
        case "created_at":
            return "创建时间"
        case "updated_at":
            return "更新时间"
        case "authorization_disposition":
            return "审批结论"
        case "deny_code":
            return "拒绝原因码"
        case "execution_readiness":
            return "执行就绪"
        case "approval_summary":
            return "审批摘要"
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
        case "required_runtime_surfaces":
            return "运行面"
        case "unblock_actions":
            return "解阻动作"
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
        case "repair_action":
            return "修复动作"
        case "required_capability":
            return "所需能力"
        case "grant_request_id":
            return "授权单号"
        case "grant_id":
            return "授权 ID"
        case "result_status":
            return "结果状态"
        case "result_summary":
            return "结果摘要"
        case "detail":
            return "详细说明"
        case "tool_args":
            return "工具参数"
        case "raw_output_chars":
            return "原始输出字符数"
        case "result_evidence_ref":
            return "结果证据引用"
        case "raw_output_ref":
            return "原始输出引用"
        case "audit_ref":
            return "审计引用"
        case "status":
            return "状态"
        default:
            return raw
        }
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
        let value: String
        if rawLabel == "status" {
            value = statusLabel(for: rawValue)
        } else {
            value = displayFieldValue(rawLabel, rawValue, context: context)
        }
        return "\(displayFieldLabel(rawLabel))：\(value)"
    }

    private static func formattedTimestamp(_ createdAt: Double) -> String {
        let date = Date(timeIntervalSince1970: createdAt)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private static func governedSkillLabel(
        for item: ProjectSkillActivityItem
    ) -> String? {
        XTPendingApprovalPresentation.governedSkillLabel(for: item)
    }

    private static func skillLabelText(
        requestedSkillID: String?,
        effectiveSkillID: String?
    ) -> String? {
        let item = ProjectSkillActivityItem(
            requestID: "",
            skillID: effectiveSkillID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            requestedSkillID: requestedSkillID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            toolName: "",
            status: "",
            createdAt: 0,
            resolutionSource: "",
            toolArgs: [:],
            resultSummary: "",
            detail: "",
            denyCode: "",
            authorizationDisposition: ""
        )
        return governedSkillLabel(for: item)
    }

    private static func awaitingApprovalPresentation(
        for item: ProjectSkillActivityItem
    ) -> AwaitingApprovalPresentationState? {
        awaitingApprovalPresentation(
            executionReadiness: item.executionReadiness,
            requiredCapability: item.requiredCapability
        )
    }

    private static func awaitingApprovalPresentation(
        executionReadiness: String,
        requiredCapability: String
    ) -> AwaitingApprovalPresentationState? {
        let readiness = executionReadiness.trimmingCharacters(in: .whitespacesAndNewlines)
        let capability = requiredCapability.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayCapability = XTGuardrailMessagePresentation.displayCapability(capability)

        if readiness == XTSkillExecutionReadinessState.grantRequired.rawValue
            || (!capability.isEmpty && readiness != XTSkillExecutionReadinessState.localApprovalRequired.rawValue) {
            let title = displayCapability.isEmpty
                ? "等待 Hub 授权"
                : "等待 Hub 授权 · \(displayCapability)"
            return AwaitingApprovalPresentationState(
                title: title,
                statusLabel: "待授权",
                iconName: "lock.shield.fill"
            )
        }

        if readiness == XTSkillExecutionReadinessState.localApprovalRequired.rawValue {
            return AwaitingApprovalPresentationState(
                title: "等待本地审批",
                statusLabel: "待审批",
                iconName: "hand.raised.fill"
            )
        }

        return nil
    }

    private static func routingReasonText(
        _ rawReasonCode: String?
    ) -> String? {
        SupervisorSkillActivityPresentation.routingReasonText(rawReasonCode)
    }

    private static func routingNarrative(
        requestedSkillId: String?,
        effectiveSkillId: String,
        routingReasonCode: String?,
        routingExplanation: String?
    ) -> String? {
        SupervisorSkillActivityPresentation.routingNarrative(
            requestedSkillId: requestedSkillId,
            effectiveSkillId: effectiveSkillId,
            routingReasonCode: routingReasonCode,
            routingExplanation: routingExplanation
        )
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
}
