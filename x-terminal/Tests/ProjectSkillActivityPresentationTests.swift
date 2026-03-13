import Testing
@testable import XTerminal
import Foundation

struct ProjectSkillActivityPresentationTests {

    @Test
    func parseRecentActivitiesKeepsLatestEventPerRequest() {
        let raw = """
        {"type":"project_skill_call","created_at":1.0,"status":"resolved","request_id":"skill-1","skill_id":"find-skills","tool_name":"skills.search","tool_args":{"query":"browser automation"}}
        {"type":"project_skill_call","created_at":2.0,"status":"awaiting_approval","request_id":"skill-2","skill_id":"agent-browser","tool_name":"device.browser.control","tool_args":{"action":"open_url","url":"https://example.com"}}
        {"type":"project_skill_call","created_at":3.0,"status":"completed","request_id":"skill-1","skill_id":"find-skills","tool_name":"skills.search","result_summary":"Found 4 matching skills"}
        """

        let items = ProjectSkillActivityPresentation.parseRecentActivities(from: raw, limit: 8)

        #expect(items.count == 2)
        #expect(items[0].requestID == "skill-1")
        #expect(items[0].status == "completed")
        #expect(items[0].resultSummary == "Found 4 matching skills")
        #expect(items[1].requestID == "skill-2")
        #expect(items[1].status == "awaiting_approval")
    }

    @Test
    func awaitingApprovalBodyIncludesUsefulPreview() {
        let item = ProjectSkillActivityItem(
            requestID: "skill-2",
            skillID: "agent-browser",
            toolName: ToolName.deviceBrowserControl.rawValue,
            status: "awaiting_approval",
            createdAt: 2.0,
            resolutionSource: "",
            toolArgs: [
                "action": .string("open_url"),
                "url": .string("https://example.com")
            ],
            resultSummary: "",
            detail: "",
            denyCode: "",
            authorizationDisposition: ""
        )

        let body = ProjectSkillActivityPresentation.body(for: item)

        #expect(body.contains("waiting for approval"))
        #expect(body.contains("https://example.com"))
    }

    @Test
    func blockedActivityDiagnosticsIncludePolicyFields() {
        let item = ProjectSkillActivityItem(
            requestID: "skill-3",
            skillID: "agent-browser",
            toolName: ToolName.deviceBrowserControl.rawValue,
            status: "blocked",
            createdAt: 4.0,
            resolutionSource: "primary",
            toolArgs: ["action": .string("click")],
            resultSummary: "",
            detail: "Device automation is disabled by policy.",
            denyCode: "trusted_automation_disabled",
            authorizationDisposition: "deny"
        )

        let diagnostics = ProjectSkillActivityPresentation.diagnostics(for: item)

        #expect(diagnostics.contains("request_id=skill-3"))
        #expect(diagnostics.contains("deny_code=trusted_automation_disabled"))
        #expect(diagnostics.contains("authorization_disposition=deny"))
        #expect(diagnostics.contains("tool_args="))
    }

    @Test
    func toolCallForActivityReconstructsGovernedDispatch() {
        let item = ProjectSkillActivityItem(
            requestID: "skill-4",
            skillID: "agent-browser",
            toolName: ToolName.deviceBrowserControl.rawValue,
            status: "failed",
            createdAt: 5.0,
            resolutionSource: "manual_retry",
            toolArgs: [
                "action": .string("open_url"),
                "url": .string("https://example.com")
            ],
            resultSummary: "Navigation failed",
            detail: "",
            denyCode: "",
            authorizationDisposition: ""
        )

        let call = AXProjectSkillActivityStore.toolCall(
            for: item,
            requestID: "retry_request_1"
        )

        #expect(call?.id == "retry_request_1")
        #expect(call?.tool == .deviceBrowserControl)
        #expect(call?.args["url"]?.stringValue == "https://example.com")
    }

    @Test
    func fullRecordTextIncludesTimelineAndRawEvents() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt_project_skill_record_\(UUID().uuidString)", isDirectory: true)
        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()

        let raw = """
        {"type":"project_skill_call","created_at":1.0,"status":"resolved","request_id":"skill-5","skill_id":"find-skills","tool_name":"skills.search","tool_args":{"query":"browser automation"},"resolution_source":"primary"}
        {"type":"project_skill_call","created_at":2.0,"status":"completed","request_id":"skill-5","skill_id":"find-skills","tool_name":"skills.search","tool_args":{"query":"browser automation"},"result_summary":"Found 4 matching skills"}
        """
        let data = try #require(raw.data(using: .utf8))
        try data.write(to: ctx.rawLogURL, options: .atomic)

        let text = ProjectSkillActivityPresentation.fullRecordText(
            ctx: ctx,
            requestID: "skill-5"
        )

        #expect(text.contains("== Event Timeline =="))
        #expect(text.contains("status=resolved"))
        #expect(text.contains("status=completed"))
        #expect(text.contains("== Raw JSON Events =="))
        #expect(text.contains("\"request_id\""))
    }

    @Test
    func fullRecordBuildsStructuredEvidenceSections() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt_project_skill_structured_record_\(UUID().uuidString)", isDirectory: true)
        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()

        let raw = """
        {"type":"project_skill_call","created_at":1.0,"status":"awaiting_approval","request_id":"skill-6","skill_id":"agent-browser","tool_name":"device.browser.control","tool_args":{"action":"open_url","url":"https://example.com"}}
        {"type":"project_skill_call","created_at":2.0,"status":"completed","request_id":"skill-6","skill_id":"agent-browser","tool_name":"device.browser.control","tool_args":{"action":"open_url","url":"https://example.com"},"result_summary":"Navigation completed"}
        """
        let data = try #require(raw.data(using: .utf8))
        try data.write(to: ctx.rawLogURL, options: .atomic)

        let call = SupervisorSkillCallRecord(
            schemaVersion: SupervisorSkillCallRecord.currentSchemaVersion,
            requestId: "skill-6",
            projectId: "project-alpha",
            jobId: "job-1",
            planId: "plan-1",
            stepId: "step-1",
            skillId: "agent-browser",
            toolName: ToolName.deviceBrowserControl.rawValue,
            status: .completed,
            payload: ["url": .string("https://example.com")],
            currentOwner: "project_ai",
            resultSummary: "Navigation completed",
            denyCode: "",
            resultEvidenceRef: nil,
            requiredCapability: "device.browser.control",
            grantRequestId: "grant-123",
            grantId: "grant-decision-1",
            createdAtMs: 1_000,
            updatedAtMs: 2_000,
            auditRef: "audit-skill-6"
        )
        try SupervisorProjectSkillCallStore.upsert(call, for: ctx)

        let toolCall = ToolCall(
            id: "skill-6",
            tool: .deviceBrowserControl,
            args: [
                "action": .string("open_url"),
                "url": .string("https://example.com")
            ]
        )
        _ = SupervisorSkillResultEvidenceStore.write(
            record: call,
            toolCall: toolCall,
            rawOutput: "Opened https://example.com and captured screenshot.png",
            triggerSource: "manual_retry",
            ctx: ctx
        )

        let record = try #require(
            ProjectSkillActivityPresentation.fullRecord(
                ctx: ctx,
                requestID: "skill-6"
            )
        )

        #expect(record.title == "agent-browser")
        #expect(record.latestStatusLabel == "Completed")
        #expect(record.requestMetadata.contains(where: { $0.label == "project_id" && $0.value == "project-alpha" }))
        #expect(record.approvalFields.contains(where: { $0.label == "grant_request_id" && $0.value == "grant-123" }))
        #expect(record.toolArgumentsText?.contains("\"url\"") == true)
        #expect(record.resultFields.contains(where: { $0.label == "result_summary" && $0.value == "Navigation completed" }))
        #expect(record.rawOutputPreview?.contains("screenshot.png") == true)
        #expect(record.evidenceFields.contains(where: { $0.label == "audit_ref" && $0.value == "audit-skill-6" }))
        #expect(record.approvalHistory.count == 1)
        #expect(record.timeline.count == 2)
        #expect(record.supervisorEvidenceJSON?.contains("\"trigger_source\"") == true)
    }
}
