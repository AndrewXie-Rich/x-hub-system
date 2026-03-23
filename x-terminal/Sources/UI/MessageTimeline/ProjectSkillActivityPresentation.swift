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
            return "待审批"
        case "resolved":
            return "技能已路由"
        default:
            return "技能动态"
        }
    }

    static func statusLabel(for item: ProjectSkillActivityItem) -> String {
        statusLabel(for: item.status)
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
            return "hand.raised.fill"
        case "resolved":
            return "point.3.connected.trianglepath.dotted"
        default:
            return "sparkles"
        }
    }

    static func toolBadge(for item: ProjectSkillActivityItem) -> String {
        displayToolName(item.toolName)
    }

    static func body(for item: ProjectSkillActivityItem) -> String {
        let skillLabel = item.skillID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "这个技能"
            : "技能 \(item.skillID)"
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
            return XTGuardrailMessagePresentation.blockedBody(
                tool: ToolName(rawValue: item.toolName),
                toolLabel: toolLabel,
                denyCode: item.denyCode,
                policySource: item.policySource,
                policyReason: item.policyReason,
                fallbackSummary: item.resultSummary,
                fallbackDetail: item.detail
            )
        case "awaiting_approval":
            return XTGuardrailMessagePresentation.awaitingApprovalBody(
                toolLabel: toolLabel,
                target: requestPreview(for: item),
                denyCode: item.denyCode
            )
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
        if !item.toolName.isEmpty {
            lines.append("tool_name=\(item.toolName)")
        }
        if !item.status.isEmpty {
            lines.append("status=\(item.status)")
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
        let latestPolicySource = events
            .reversed()
            .compactMap { nonEmpty($0.item.policySource) }
            .first
        let latestPolicyReason = events
            .reversed()
            .compactMap { nonEmpty($0.item.policyReason) }
            .first
        let toolArgsText = preferredToolArgumentsText(
            latestToolArgs: latest?.toolArgs ?? [:],
            evidenceToolArgs: evidence?.toolArgs
        )
        let title = skillID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? skillID ?? "技能记录"
            : "技能记录"

        let requestMetadata = recordFields([
            ("request_id", requestID),
            ("skill_id", skillID),
            ("tool_name", toolName),
            ("latest_status", latestStatus),
            ("resolution_source", latest?.resolutionSource),
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
            ("authorization_disposition", latest?.authorizationDisposition),
            ("deny_code", firstNonEmpty(latest?.denyCode, evidence?.denyCode, supervisorCall?.denyCode)),
            ("policy_source", latestPolicySource),
            ("policy_reason", latestPolicyReason),
            ("required_capability", supervisorCall?.requiredCapability),
            ("grant_request_id", supervisorCall?.grantRequestId),
            ("grant_id", supervisorCall?.grantId)
        ])

        let resultFields = recordFields([
            ("result_status", firstNonEmpty(evidence?.status, latest?.status, supervisorCall?.status.rawValue)),
            ("result_summary", firstNonEmpty(evidence?.resultSummary, latest?.resultSummary, supervisorCall?.resultSummary)),
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
            latestStatusLabel: statusLabel(for: latestStatus),
            requestMetadata: requestMetadata,
            approvalFields: approvalFields,
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
        humanRecordFieldLabel(raw)
    }

    static func displayTimelineDetail(_ detail: String?) -> String? {
        guard let detail = nonEmpty(detail) else { return nil }
        let lines = detail
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { displayTimelineDetailLine(String($0)) }
        return lines.joined(separator: "\n")
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

    private static func statusLabel(for rawStatus: String) -> String {
        switch normalizedStatus(rawStatus) {
        case "completed":
            return "已完成"
        case "failed":
            return "失败"
        case "blocked":
            return "受阻"
        case "awaiting_approval":
            return "待审批"
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
            statusLabel: statusLabel(for: event.item.status),
            timestamp: formattedTimestamp(event.item.createdAt),
            summary: body(for: event.item),
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
        if !event.item.detail.isEmpty {
            lines.append("detail=\(event.item.detail)")
        }
        if !event.item.denyCode.isEmpty {
            lines.append("deny_code=\(event.item.denyCode)")
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
        if !event.item.resolutionSource.isEmpty {
            lines.append("resolution_source=\(event.item.resolutionSource)")
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
        lines.append("")
        lines.append("== \(title) ==")
        for field in fields {
            lines.append("\(displayFieldLabel(field.label))：\(field.value)")
        }
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

    private static func humanRecordFieldLabel(_ raw: String) -> String {
        switch raw {
        case "request_id":
            return "请求单号"
        case "skill_id":
            return "技能 ID"
        case "tool_name":
            return "工具"
        case "latest_status":
            return "最新状态"
        case "resolution_source":
            return "处理来源"
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
        case "policy_source":
            return "策略来源"
        case "policy_reason":
            return "策略说明"
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
        _ line: String
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
            value = rawValue
        }
        return "\(displayFieldLabel(rawLabel))：\(value)"
    }

    private static func formattedTimestamp(_ createdAt: Double) -> String {
        let date = Date(timeIntervalSince1970: createdAt)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
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
