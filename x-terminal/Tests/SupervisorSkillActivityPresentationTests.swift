import Testing
@testable import XTerminal
import Foundation

struct SupervisorSkillActivityPresentationTests {

    @Test
    func awaitingAuthorizationBodyDistinguishesHubGrantAndLocalApproval() {
        let hubGrantRecord = SupervisorSkillCallRecord(
            schemaVersion: SupervisorSkillCallRecord.currentSchemaVersion,
            requestId: "skill-hub-1",
            projectId: "project-alpha",
            jobId: "job-1",
            planId: "plan-1",
            stepId: "step-1",
            skillId: "agent-browser",
            toolName: ToolName.deviceBrowserControl.rawValue,
            status: .awaitingAuthorization,
            payload: ["url": .string("https://example.com")],
            currentOwner: "supervisor",
            resultSummary: "",
            denyCode: "grant_required",
            resultEvidenceRef: nil,
            requiredCapability: "web.fetch",
            grantRequestId: "grant-1",
            grantId: nil,
            createdAtMs: 1_000,
            updatedAtMs: 2_000,
            auditRef: "audit-hub"
        )
        let localApprovalRecord = SupervisorSkillCallRecord(
            schemaVersion: SupervisorSkillCallRecord.currentSchemaVersion,
            requestId: "skill-local-1",
            projectId: "project-alpha",
            jobId: "job-1",
            planId: "plan-1",
            stepId: "step-2",
            skillId: "code-review",
            toolName: ToolName.run_command.rawValue,
            status: .awaitingAuthorization,
            payload: ["command": .string("swift test")],
            currentOwner: "supervisor",
            resultSummary: "",
            denyCode: "local_approval_required",
            resultEvidenceRef: nil,
            requiredCapability: nil,
            grantRequestId: nil,
            grantId: nil,
            createdAtMs: 1_000,
            updatedAtMs: 2_000,
            auditRef: "audit-local"
        )

        let hubGrantItem = SupervisorManager.SupervisorRecentSkillActivity(
            projectId: "project-alpha",
            projectName: "Project Alpha",
            record: hubGrantRecord,
            tool: .deviceBrowserControl,
            toolCall: ToolCall(
                id: "skill-hub-1",
                tool: .deviceBrowserControl,
                args: ["url": .string("https://example.com")]
            ),
            toolSummary: "https://example.com",
            actionURL: "x-terminal://project/project-alpha"
        )
        let localApprovalItem = SupervisorManager.SupervisorRecentSkillActivity(
            projectId: "project-alpha",
            projectName: "Project Alpha",
            record: localApprovalRecord,
            tool: .run_command,
            toolCall: ToolCall(
                id: "skill-local-1",
                tool: .run_command,
                args: ["command": .string("swift test")]
            ),
            toolSummary: "swift test",
            actionURL: "x-terminal://project/project-alpha"
        )

        let hubBody = SupervisorSkillActivityPresentation.body(for: hubGrantItem)
        let localBody = SupervisorSkillActivityPresentation.body(for: localApprovalItem)

        #expect(hubBody.contains("Hub grant approval"))
        #expect(localBody.contains("local approval"))
        #expect(!SupervisorSkillActivityPresentation.isAwaitingLocalApproval(hubGrantItem))
        #expect(SupervisorSkillActivityPresentation.isAwaitingLocalApproval(localApprovalItem))
    }

    @Test
    func fullRecordBuildsStructuredSupervisorEvidenceSections() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt_supervisor_skill_record_\(UUID().uuidString)", isDirectory: true)
        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()

        let record = SupervisorSkillCallRecord(
            schemaVersion: SupervisorSkillCallRecord.currentSchemaVersion,
            requestId: "skill-7",
            projectId: "project-alpha",
            jobId: "job-1",
            planId: "plan-1",
            stepId: "step-1",
            skillId: "agent-browser",
            toolName: ToolName.deviceBrowserControl.rawValue,
            status: .completed,
            payload: [
                "action": .string("open_url"),
                "url": .string("https://example.com")
            ],
            currentOwner: "supervisor",
            resultSummary: "Navigation completed",
            denyCode: "",
            resultEvidenceRef: nil,
            requiredCapability: nil,
            grantRequestId: nil,
            grantId: nil,
            createdAtMs: 1_000,
            updatedAtMs: 3_000,
            auditRef: "audit-skill-7"
        )
        try SupervisorProjectSkillCallStore.upsert(record, for: ctx)

        let toolCall = ToolCall(
            id: "skill-7",
            tool: .deviceBrowserControl,
            args: [
                "action": .string("open_url"),
                "url": .string("https://example.com")
            ]
        )
        _ = SupervisorSkillResultEvidenceStore.write(
            record: record,
            toolCall: toolCall,
            rawOutput: "Opened https://example.com and captured screenshot.png",
            triggerSource: "user_turn",
            ctx: ctx
        )

        let raw = """
        {"type":"supervisor_skill_call","action":"dispatch","request_id":"skill-7","project_id":"project-alpha","job_id":"job-1","plan_id":"plan-1","step_id":"step-1","skill_id":"agent-browser","tool_name":"device.browser.control","status":"queued","tool":"device.browser.control","tool_args":{"action":"open_url","url":"https://example.com"},"timestamp_ms":1000,"audit_ref":"audit-skill-7","trigger_source":"user_turn"}
        {"type":"supervisor_skill_call","action":"completed","request_id":"skill-7","project_id":"project-alpha","job_id":"job-1","plan_id":"plan-1","step_id":"step-1","skill_id":"agent-browser","tool_name":"device.browser.control","status":"completed","result_summary":"Navigation completed","result_evidence_ref":"local://supervisor_skill_results/skill-7.json","tool":"device.browser.control","tool_args":{"action":"open_url","url":"https://example.com"},"timestamp_ms":3000,"audit_ref":"audit-skill-7","trigger_source":"user_turn"}
        {"type":"supervisor_skill_result","request_id":"skill-7","project_id":"project-alpha","job_id":"job-1","plan_id":"plan-1","step_id":"step-1","skill_id":"agent-browser","tool_name":"device.browser.control","status":"completed","result_summary":"Navigation completed","result_evidence_ref":"local://supervisor_skill_results/skill-7.json","raw_output_ref":"local://supervisor_skill_results/skill-7.json#raw_output","raw_output_chars":55,"tool":"device.browser.control","tool_args":{"action":"open_url","url":"https://example.com"},"updated_at_ms":3000,"audit_ref":"audit-skill-7","trigger_source":"user_turn"}
        """
        try #require(raw.data(using: .utf8)).write(to: ctx.rawLogURL, options: .atomic)

        let fullRecord = try #require(
            SupervisorSkillActivityPresentation.fullRecord(
                ctx: ctx,
                projectName: "Project Alpha",
                requestID: "skill-7"
            )
        )

        #expect(fullRecord.title == "agent-browser")
        #expect(fullRecord.latestStatusLabel == "Completed")
        #expect(fullRecord.requestMetadata.contains(where: { $0.label == "project_name" && $0.value == "Project Alpha" }))
        #expect(fullRecord.toolArgumentsText?.contains("\"url\"") == true)
        #expect(fullRecord.skillPayloadText?.contains("\"action\"") == true)
        #expect(fullRecord.resultFields.contains(where: { $0.label == "result_summary" && $0.value == "Navigation completed" }))
        #expect(fullRecord.rawOutputPreview?.contains("screenshot.png") == true)
        #expect(fullRecord.evidenceFields.contains(where: { $0.label == "audit_ref" && $0.value == "audit-skill-7" }))
        #expect(fullRecord.timeline.count == 3)
        #expect(fullRecord.supervisorEvidenceJSON?.contains("\"trigger_source\"") == true)
        #expect(SupervisorSkillActivityPresentation.fullRecordText(fullRecord).contains("== Skill Payload =="))
    }
}
