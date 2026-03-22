import Foundation

struct SupervisorSkillResultEvidence: Codable, Equatable, Sendable {
    static let currentSchemaVersion = "xt.supervisor_skill_result_evidence.v1"

    var schemaVersion: String
    var requestId: String
    var projectId: String
    var jobId: String
    var planId: String
    var stepId: String
    var skillId: String
    var requestedSkillId: String? = nil
    var routingReasonCode: String? = nil
    var routingExplanation: String? = nil
    var toolName: String
    var status: String
    var resultSummary: String
    var denyCode: String
    var policySource: String? = nil
    var policyReason: String? = nil
    var resultEvidenceRef: String
    var rawOutputRef: String?
    var rawOutputPreview: String
    var rawOutputChars: Int
    var uiReviewAgentEvidenceRef: String?
    var triggerSource: String
    var auditRef: String
    var updatedAtMs: Int64
    var tool: String?
    var toolArgs: [String: JSONValue]?
    var rawOutput: String?

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case requestId = "request_id"
        case projectId = "project_id"
        case jobId = "job_id"
        case planId = "plan_id"
        case stepId = "step_id"
        case skillId = "skill_id"
        case requestedSkillId = "requested_skill_id"
        case routingReasonCode = "routing_reason_code"
        case routingExplanation = "routing_explanation"
        case toolName = "tool_name"
        case status
        case resultSummary = "result_summary"
        case denyCode = "deny_code"
        case policySource = "policy_source"
        case policyReason = "policy_reason"
        case resultEvidenceRef = "result_evidence_ref"
        case rawOutputRef = "raw_output_ref"
        case rawOutputPreview = "raw_output_preview"
        case rawOutputChars = "raw_output_chars"
        case uiReviewAgentEvidenceRef = "ui_review_agent_evidence_ref"
        case triggerSource = "trigger_source"
        case auditRef = "audit_ref"
        case updatedAtMs = "updated_at_ms"
        case tool
        case toolArgs = "tool_args"
        case rawOutput = "raw_output"
    }
}

enum SupervisorSkillResultEvidenceStore {
    static func write(
        record: SupervisorSkillCallRecord,
        toolCall: ToolCall?,
        rawOutput: String?,
        triggerSource: String,
        ctx: AXProjectContext
    ) -> String? {
        try? ctx.ensureDirs()
        try? FileManager.default.createDirectory(
            at: ctx.supervisorSkillResultsDir,
            withIntermediateDirectories: true
        )

        let url = ctx.supervisorSkillResultEvidenceURL(requestId: record.requestId)
        let fileName = url.lastPathComponent
        let resultEvidenceRef = "local://supervisor_skill_results/\(fileName)"
        let trimmedOutput = rawOutput?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let previewLimit = 1_200
        let rawOutputPreview: String = {
            guard !trimmedOutput.isEmpty else { return "" }
            guard trimmedOutput.count > previewLimit else { return trimmedOutput }
            let end = trimmedOutput.index(trimmedOutput.startIndex, offsetBy: previewLimit)
            return String(trimmedOutput[..<end]) + "..."
        }()
        let rawOutputRef = trimmedOutput.isEmpty ? nil : "\(resultEvidenceRef)#raw_output"
        let uiReviewAgentEvidenceRef = resolvedUIReviewAgentEvidenceRef(from: trimmedOutput)

        let evidence = SupervisorSkillResultEvidence(
            schemaVersion: SupervisorSkillResultEvidence.currentSchemaVersion,
            requestId: record.requestId,
            projectId: record.projectId,
            jobId: record.jobId,
            planId: record.planId,
            stepId: record.stepId,
            skillId: record.skillId,
            requestedSkillId: record.requestedSkillId,
            routingReasonCode: record.routingReasonCode,
            routingExplanation: record.routingExplanation,
            toolName: record.toolName,
            status: record.status.rawValue,
            resultSummary: record.resultSummary,
            denyCode: record.denyCode,
            policySource: record.policySource,
            policyReason: record.policyReason,
            resultEvidenceRef: resultEvidenceRef,
            rawOutputRef: rawOutputRef,
            rawOutputPreview: rawOutputPreview,
            rawOutputChars: trimmedOutput.count,
            uiReviewAgentEvidenceRef: uiReviewAgentEvidenceRef,
            triggerSource: triggerSource,
            auditRef: record.auditRef,
            updatedAtMs: record.updatedAtMs,
            tool: toolCall?.tool.rawValue,
            toolArgs: toolCall?.args,
            rawOutput: trimmedOutput.isEmpty ? nil : trimmedOutput
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(evidence) else { return nil }
        try? SupervisorStoreWriteSupport.writeSnapshotData(data, to: url)
        return resultEvidenceRef
    }

    static func load(requestId: String, for ctx: AXProjectContext) -> SupervisorSkillResultEvidence? {
        let url = ctx.supervisorSkillResultEvidenceURL(requestId: requestId)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(SupervisorSkillResultEvidence.self, from: data)
    }

    private static func resolvedUIReviewAgentEvidenceRef(
        from rawOutput: String
    ) -> String? {
        let normalized = rawOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }

        let parsed = ToolExecutor.parseStructuredToolOutput(normalized)
        if case .object(let summary)? = parsed.summary,
           let candidate = uiReviewAgentEvidenceRef(from: summary) {
            return candidate
        }

        guard let data = normalized.data(using: .utf8),
              let value = try? JSONDecoder().decode(JSONValue.self, from: data),
              case .object(let object) = value else {
            return nil
        }
        return uiReviewAgentEvidenceRef(from: object)
    }

    private static func uiReviewAgentEvidenceRef(
        from object: [String: JSONValue]
    ) -> String? {
        let uiReview = jsonObjectValue(object["ui_review"])
        let browserRuntime = jsonObjectValue(object["browser_runtime"])
        return [
            stringValue(object["ui_review_agent_evidence_ref"]),
            stringValue(object["browser_runtime_ui_review_agent_evidence_ref"]),
            stringValue(uiReview["agent_evidence_ref"]),
            stringValue(browserRuntime["ui_review_agent_evidence_ref"])
        ]
        .compactMap { normalizedScalar($0) }
        .first
    }

    private static func stringValue(_ value: JSONValue?) -> String? {
        value?.stringValue
    }

    private static func jsonObjectValue(_ value: JSONValue?) -> [String: JSONValue] {
        guard case .object(let object)? = value else { return [:] }
        return object
    }

    private static func normalizedScalar(_ raw: String?) -> String? {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
