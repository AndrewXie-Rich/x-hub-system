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
    var toolName: String
    var status: String
    var resultSummary: String
    var denyCode: String
    var resultEvidenceRef: String
    var rawOutputRef: String?
    var rawOutputPreview: String
    var rawOutputChars: Int
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
        case toolName = "tool_name"
        case status
        case resultSummary = "result_summary"
        case denyCode = "deny_code"
        case resultEvidenceRef = "result_evidence_ref"
        case rawOutputRef = "raw_output_ref"
        case rawOutputPreview = "raw_output_preview"
        case rawOutputChars = "raw_output_chars"
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

        let evidence = SupervisorSkillResultEvidence(
            schemaVersion: SupervisorSkillResultEvidence.currentSchemaVersion,
            requestId: record.requestId,
            projectId: record.projectId,
            jobId: record.jobId,
            planId: record.planId,
            stepId: record.stepId,
            skillId: record.skillId,
            toolName: record.toolName,
            status: record.status.rawValue,
            resultSummary: record.resultSummary,
            denyCode: record.denyCode,
            resultEvidenceRef: resultEvidenceRef,
            rawOutputRef: rawOutputRef,
            rawOutputPreview: rawOutputPreview,
            rawOutputChars: trimmedOutput.count,
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
        try? data.write(to: url, options: Data.WritingOptions.atomic)
        return resultEvidenceRef
    }

    static func load(requestId: String, for ctx: AXProjectContext) -> SupervisorSkillResultEvidence? {
        let url = ctx.supervisorSkillResultEvidenceURL(requestId: requestId)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(SupervisorSkillResultEvidence.self, from: data)
    }
}
