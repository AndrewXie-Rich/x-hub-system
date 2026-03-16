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
    var supervisorEvidenceJSON: String?

    var id: String { "\(projectName):\(requestID)" }
}

enum SupervisorSkillActivityPresentation {
    static func title(for item: SupervisorManager.SupervisorRecentSkillActivity) -> String {
        switch normalizedStatus(item.status) {
        case "completed":
            return "Supervisor skill completed"
        case "failed":
            return "Supervisor skill failed"
        case "blocked":
            return "Supervisor skill blocked"
        case "awaiting_authorization":
            return item.requiredCapability.isEmpty
                ? "Supervisor approval required"
                : "Hub grant required · \(humanCapabilityLabel(item.requiredCapability))"
        case "running":
            return "Supervisor skill running"
        case "queued":
            return "Supervisor skill queued"
        case "canceled":
            return "Supervisor skill canceled"
        default:
            return "Supervisor skill activity"
        }
    }

    static func statusLabel(for item: SupervisorManager.SupervisorRecentSkillActivity) -> String {
        statusLabel(for: item.status)
    }

    static func statusLabel(for rawStatus: String) -> String {
        switch normalizedStatus(rawStatus) {
        case "queued":
            return "Queued"
        case "running":
            return "Running"
        case "awaiting_authorization":
            return "Awaiting Approval"
        case "completed":
            return "Completed"
        case "failed":
            return "Failed"
        case "blocked":
            return "Blocked"
        case "canceled":
            return "Canceled"
        default:
            return rawStatus.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Unknown" : rawStatus
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
            return item.requiredCapability.isEmpty ? "Open Approval" : "Open Grant"
        default:
            return "Open Project"
        }
    }

    static func workflowLine(for item: SupervisorManager.SupervisorRecentSkillActivity) -> String? {
        let fields = [
            compactWorkflowToken(label: "job", value: item.record.jobId),
            compactWorkflowToken(label: "plan", value: item.record.planId),
            compactWorkflowToken(label: "step", value: item.record.stepId)
        ].compactMap { $0 }
        guard !fields.isEmpty else { return nil }
        return "workflow: " + fields.joined(separator: " · ")
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
        return "governance: " + parts.joined(separator: " · ")
    }

    static func followUpRhythmLine(for item: SupervisorManager.SupervisorRecentSkillActivity) -> String? {
        guard let governance = item.governance else { return nil }
        guard let summary = nonEmpty(governance.followUpRhythmSummary) else { return nil }
        return "follow-up: \(summary)"
    }

    static func pendingGuidanceLine(for item: SupervisorManager.SupervisorRecentSkillActivity) -> String? {
        guard let governance = item.governance else { return nil }
        guard let ackStatus = governance.pendingGuidanceAckStatus else { return nil }
        var parts = ["guidance: \(ackStatus.displayName)"]
        parts.append(governance.pendingGuidanceRequired ? "required" : "optional")
        if let latestDelivery = governance.latestGuidanceDeliveryMode?.displayName {
            parts.append(latestDelivery)
        }
        let guidanceId = nonEmpty(governance.pendingGuidanceId) ?? nonEmpty(governance.latestGuidanceId)
        if let guidanceId {
            parts.append("id=\(guidanceId)")
        }
        return parts.joined(separator: " · ")
    }

    static func body(for item: SupervisorManager.SupervisorRecentSkillActivity) -> String {
        let skillLabel = item.skillId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "This supervisor skill"
            : "Skill \(item.skillId)"
        let toolLabel = toolBadge(for: item)
        let target = item.toolSummary.trimmingCharacters(in: .whitespacesAndNewlines)

        switch normalizedStatus(item.status) {
        case "queued":
            if !item.resultSummary.isEmpty { return item.resultSummary }
            return target.isEmpty
                ? "\(skillLabel) is queued for \(toolLabel)."
                : "\(skillLabel) is queued for \(toolLabel) on \(target)."
        case "running":
            if !item.resultSummary.isEmpty { return item.resultSummary }
            return target.isEmpty
                ? "\(skillLabel) is running via \(toolLabel)."
                : "\(skillLabel) is running via \(toolLabel) on \(target)."
        case "awaiting_authorization":
            return XTGuardrailMessagePresentation.awaitingApprovalBody(
                toolLabel: toolLabel,
                target: target,
                requiredCapability: item.requiredCapability,
                denyCode: item.denyCode
            )
        case "completed":
            if !item.resultSummary.isEmpty { return item.resultSummary }
            return "\(skillLabel) completed via \(toolLabel)."
        case "failed":
            if !item.resultSummary.isEmpty { return item.resultSummary }
            return "\(skillLabel) failed while running \(toolLabel)."
        case "blocked":
            return XTGuardrailMessagePresentation.blockedBody(
                tool: item.tool,
                toolLabel: toolLabel,
                denyCode: item.denyCode,
                requiredCapability: item.requiredCapability,
                fallbackSummary: item.resultSummary
            )
        case "canceled":
            if !item.resultSummary.isEmpty { return item.resultSummary }
            return "\(skillLabel) was canceled."
        default:
            if !item.resultSummary.isEmpty { return item.resultSummary }
            return "\(skillLabel) activity updated."
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
        if !record.toolName.isEmpty { lines.append("tool_name=\(record.toolName)") }
        if !record.status.rawValue.isEmpty { lines.append("status=\(record.status.rawValue)") }
        if !record.currentOwner.isEmpty { lines.append("current_owner=\(record.currentOwner)") }
        if !item.requiredCapability.isEmpty { lines.append("required_capability=\(item.requiredCapability)") }
        if !item.grantRequestId.isEmpty { lines.append("grant_request_id=\(item.grantRequestId)") }
        if !item.grantId.isEmpty { lines.append("grant_id=\(item.grantId)") }
        if !item.resultEvidenceRef.isEmpty { lines.append("result_evidence_ref=\(item.resultEvidenceRef)") }
        if !item.resultSummary.isEmpty { lines.append("result_summary=\(item.resultSummary)") }
        if !item.denyCode.isEmpty { lines.append("deny_code=\(item.denyCode)") }
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
        let latestReview = SupervisorReviewNoteStore.latest(for: ctx)
        let latestGuidance = SupervisorGuidanceInjectionStore.latest(for: ctx)
        let pendingGuidance = SupervisorGuidanceInjectionStore.latestPendingAck(for: ctx)
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
        let title = firstNonEmpty(record?.skillId, evidence?.skillId) ?? "Supervisor Skill Record"
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
            ("skill_id", firstNonEmpty(record?.skillId, evidence?.skillId, events.last?.skillId)),
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
            supervisorEvidenceJSON: evidence.map(encodedJSONText)
        )
    }

    static func fullRecordText(_ record: SupervisorSkillFullRecord) -> String {
        var lines: [String] = [
            "Supervisor Skill Full Record",
            "project_name=\(record.projectName)",
            "request_id=\(record.requestID)"
        ]

        if !record.latestStatus.isEmpty {
            lines.append("latest_status=\(record.latestStatus)")
        }

        appendRecordSection("Request Metadata", fields: record.requestMetadata, into: &lines)
        appendRecordSection("Approval Status", fields: record.approvalFields, into: &lines)
        appendRecordSection("Governance Context", fields: record.governanceFields, into: &lines)

        if let payload = nonEmpty(record.skillPayloadText) {
            lines.append("")
            lines.append("== Skill Payload ==")
            lines.append(payload)
        }

        if let toolArgs = nonEmpty(record.toolArgumentsText) {
            lines.append("")
            lines.append("== Tool Arguments ==")
            lines.append(toolArgs)
        }

        appendRecordSection("Result Summary", fields: record.resultFields, into: &lines)

        if let rawOutputPreview = nonEmpty(record.rawOutputPreview) {
            lines.append("")
            lines.append("== Raw Output Preview ==")
            lines.append(rawOutputPreview)
        }

        if let rawOutput = nonEmpty(record.rawOutput) {
            lines.append("")
            lines.append("== Raw Output Full ==")
            lines.append(rawOutput)
        }

        appendRecordSection("Evidence Refs", fields: record.evidenceFields, into: &lines)

        if !record.approvalHistory.isEmpty {
            lines.append("")
            lines.append("== Approval History ==")
            for entry in record.approvalHistory {
                lines.append(formattedTimelineEntry(entry))
            }
        }

        if !record.timeline.isEmpty {
            lines.append("")
            lines.append("== Event Timeline ==")
            for entry in record.timeline {
                lines.append(formattedTimelineEntry(entry))
            }
        }

        if let evidence = nonEmpty(record.supervisorEvidenceJSON) {
            lines.append("")
            lines.append("== Result Evidence ==")
            lines.append(evidence)
        }

        if !record.timeline.isEmpty {
            lines.append("")
            lines.append("== Raw JSON Events ==")
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
        var toolName: String
        var status: String
        var resultSummary: String
        var denyCode: String
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
            toolName: stringValue(object["tool_name"]) ?? "",
            status: stringValue(object["status"]) ?? "",
            resultSummary: stringValue(object["result_summary"]) ?? "",
            denyCode: stringValue(object["deny_code"]) ?? "",
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
        if !event.denyCode.isEmpty {
            lines.append("deny_code=\(event.denyCode)")
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
            return raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "tool runtime" : raw
        }

        switch resolvedTool {
        case .read_file:
            return "read file"
        case .write_file:
            return "write file"
        case .delete_path:
            return "delete path"
        case .move_path:
            return "move path"
        case .run_command:
            return "run command"
        case .process_start:
            return "start process"
        case .process_status:
            return "process status"
        case .process_logs:
            return "process logs"
        case .process_stop:
            return "stop process"
        case .git_commit:
            return "git commit"
        case .git_push:
            return "git push"
        case .pr_create:
            return "create pull request"
        case .ci_read:
            return "read ci"
        case .ci_trigger:
            return "trigger ci"
        case .search:
            return "search"
        case .skills_search:
            return "skills search"
        case .summarize:
            return "summarize"
        case .web_fetch:
            return "web fetch"
        case .web_search:
            return "web search"
        case .browser_read:
            return "browser read"
        case .deviceBrowserControl:
            return "browser control"
        case .agentImportRecord:
            return "agent import record"
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
}
