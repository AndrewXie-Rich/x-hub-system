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
            return "Skill completed"
        case "failed":
            return "Skill failed"
        case "blocked":
            return "Skill blocked"
        case "awaiting_approval":
            return "Approval required"
        case "resolved":
            return "Skill routed"
        default:
            return "Skill activity"
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
            ? "This skill"
            : "Skill \(item.skillID)"
        let toolLabel = displayToolName(item.toolName)

        switch normalizedStatus(item.status) {
        case "completed":
            if !item.resultSummary.isEmpty { return item.resultSummary }
            return "\(skillLabel) completed via \(toolLabel)."
        case "failed":
            if !item.resultSummary.isEmpty { return item.resultSummary }
            if !item.detail.isEmpty { return item.detail }
            return "\(skillLabel) failed while running \(toolLabel)."
        case "blocked":
            if !item.detail.isEmpty { return item.detail }
            if !item.denyCode.isEmpty {
                return "\(skillLabel) was blocked before \(toolLabel) could run (\(item.denyCode))."
            }
            return "\(skillLabel) was blocked before \(toolLabel) could run."
        case "awaiting_approval":
            if let preview = requestPreview(for: item), !preview.isEmpty {
                return "\(skillLabel) is waiting for approval to run \(toolLabel) for \(preview)."
            }
            return "\(skillLabel) is waiting for approval to run \(toolLabel)."
        case "resolved":
            if let preview = requestPreview(for: item), !preview.isEmpty {
                return "\(skillLabel) was routed to \(toolLabel) for \(preview)."
            }
            return "\(skillLabel) was routed to \(toolLabel)."
        default:
            if !item.resultSummary.isEmpty { return item.resultSummary }
            if !item.detail.isEmpty { return item.detail }
            return "\(skillLabel) activity updated."
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
        let toolArgsText = preferredToolArgumentsText(
            latestToolArgs: latest?.toolArgs ?? [:],
            evidenceToolArgs: evidence?.toolArgs
        )
        let title = skillID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? skillID ?? "Skill Record"
            : "Skill Record"

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
            return "No skill record was found for request_id=\(requestID)."
        }
        return fullRecordText(record)
    }

    static func fullRecordText(
        _ record: ProjectSkillFullRecord
    ) -> String {
        var lines: [String] = [
            "Project Skill Full Record",
            "request_id=\(record.requestID)"
        ]

        if !record.latestStatus.isEmpty {
            lines.append("latest_status=\(record.latestStatus)")
        }

        appendRecordSection("Request Metadata", fields: record.requestMetadata, into: &lines)
        appendRecordSection("Approval Status", fields: record.approvalFields, into: &lines)

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

    private static func requestPreview(for item: ProjectSkillActivityItem) -> String? {
        let preferredKeys = ["url", "query", "path", "selector", "command", "action"]
        for key in preferredKeys {
            let value = item.toolArgs[key]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !value.isEmpty else { continue }
            switch key {
            case "url":
                return value
            case "query":
                return "query '\(value)'"
            case "path":
                return "path \(value)"
            case "selector":
                return "selector \(value)"
            case "command":
                return "command \(value)"
            case "action":
                return "action \(value)"
            default:
                return value
            }
        }
        return nil
    }

    private static func displayToolName(_ raw: String) -> String {
        guard let tool = ToolName(rawValue: raw) else {
            return raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "tool runtime" : raw
        }

        switch tool {
        case .skills_search:
            return "skills search"
        case .summarize:
            return "summarize"
        case .browser_read:
            return "browser read"
        case .web_fetch:
            return "web fetch"
        case .web_search:
            return "web search"
        case .deviceBrowserControl:
            return "browser control"
        case .agentImportRecord:
            return "agent import record"
        default:
            return tool.rawValue.replacingOccurrences(of: "_", with: " ")
        }
    }

    private static func normalizedStatus(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func statusLabel(for rawStatus: String) -> String {
        switch normalizedStatus(rawStatus) {
        case "completed":
            return "Completed"
        case "failed":
            return "Failed"
        case "blocked":
            return "Blocked"
        case "awaiting_approval":
            return "Awaiting Approval"
        case "resolved":
            return "Resolved"
        default:
            return rawStatus.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Unknown" : rawStatus
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
            lines.append("\(field.label)=\(field.value)")
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
