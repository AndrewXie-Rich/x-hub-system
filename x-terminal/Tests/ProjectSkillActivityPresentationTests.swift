import Testing
@testable import XTerminal
import Foundation

struct ProjectSkillActivityPresentationTests {

    @Test
    func titleStatusAndToolBadgeUseLocalizedCopy() {
        let item = ProjectSkillActivityItem(
            requestID: "skill-localized-1",
            skillID: "agent-browser",
            toolName: ToolName.deviceBrowserControl.rawValue,
            status: "awaiting_approval",
            createdAt: 1.0,
            resolutionSource: "",
            toolArgs: [:],
            resultSummary: "",
            detail: "",
            denyCode: "",
            authorizationDisposition: ""
        )

        #expect(ProjectSkillActivityPresentation.title(for: item) == "待审批")
        #expect(ProjectSkillActivityPresentation.statusLabel(for: item) == "待审批")
        #expect(ProjectSkillActivityPresentation.toolBadge(for: item) == "浏览器控制")
    }

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

        #expect(body.contains("本地审批"))
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
            authorizationDisposition: "deny",
            policySource: "project_governance",
            policyReason: "execution_tier_missing_browser_runtime"
        )

        let diagnostics = ProjectSkillActivityPresentation.diagnostics(for: item)

        #expect(diagnostics.contains("request_id=skill-3"))
        #expect(diagnostics.contains("deny_code=trusted_automation_disabled"))
        #expect(diagnostics.contains("authorization_disposition=deny"))
        #expect(diagnostics.contains("policy_source=project_governance"))
        #expect(diagnostics.contains("policy_reason=execution_tier_missing_browser_runtime"))
        #expect(diagnostics.contains("tool_args="))
    }

    @Test
    func blockedGovernanceBodyUsesHumanGuidance() {
        let item = ProjectSkillActivityItem(
            requestID: "skill-3b",
            skillID: "agent-browser",
            toolName: ToolName.deviceBrowserControl.rawValue,
            status: "blocked",
            createdAt: 4.0,
            resolutionSource: "primary",
            toolArgs: ["action": .string("open_url")],
            resultSummary: "project governance blocks device.browser.control under execution tier a0_observe",
            detail: "project governance blocks device.browser.control under execution tier a0_observe",
            denyCode: "governance_capability_denied",
            authorizationDisposition: "deny",
            policySource: "project_governance",
            policyReason: "execution_tier_missing_browser_runtime"
        )

        let body = ProjectSkillActivityPresentation.body(for: item)

        #expect(body.contains("不允许浏览器自动化"))
        #expect(body.contains("打开项目设置 -> 执行档位"))
        #expect(body.contains("A4 Agent"))
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

        #expect(text.contains("请求单号：skill-5"))
        #expect(text.contains("== 事件时间线 =="))
        #expect(text.contains("status=resolved"))
        #expect(text.contains("status=completed"))
        #expect(text.contains("== 原始 JSON 事件 =="))
        #expect(text.contains("\"request_id\""))
    }

    @Test
    func fullRecordBuildsStructuredEvidenceSections() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt_project_skill_structured_record_\(UUID().uuidString)", isDirectory: true)
        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()

        let raw = """
        {"type":"project_skill_call","created_at":1.0,"status":"awaiting_approval","request_id":"skill-6","skill_id":"agent-browser","tool_name":"device.browser.control","tool_args":{"action":"open_url","url":"https://example.com"},"authorization_disposition":"ask","policy_source":"project_governance","policy_reason":"execution_tier_missing_browser_runtime","execution_tier":"\(AXProjectExecutionTier.a1Plan.rawValue)","effective_execution_tier":"\(AXProjectExecutionTier.a1Plan.rawValue)","supervisor_intervention_tier":"\(AXProjectSupervisorInterventionTier.s2PeriodicReview.rawValue)","effective_supervisor_intervention_tier":"\(AXProjectSupervisorInterventionTier.s2PeriodicReview.rawValue)","review_policy_mode":"\(AXProjectReviewPolicyMode.periodic.rawValue)","progress_heartbeat_sec":900,"review_pulse_sec":1800,"brainstorm_review_sec":0,"governance_compat_source":"\(AXProjectGovernanceCompatSource.explicitDualDial.rawValue)"}
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
        #expect(record.latestStatusLabel == "已完成")
        #expect(record.requestMetadata.contains(where: { $0.label == "project_id" && $0.value == "project-alpha" }))
        #expect(record.approvalFields.contains(where: { $0.label == "policy_source" && $0.value == "project_governance" }))
        #expect(record.approvalFields.contains(where: { $0.label == "policy_reason" && $0.value == "execution_tier_missing_browser_runtime" }))
        #expect(record.approvalFields.contains(where: { $0.label == "blocked_summary" && $0.value.contains("不允许浏览器自动化") }))
        #expect(record.approvalFields.contains(where: { $0.label == "governance_truth" && $0.value.contains("当前生效 A1/S2") }))
        #expect(record.approvalFields.contains(where: { $0.label == "grant_request_id" && $0.value == "grant-123" }))
        #expect(record.toolArgumentsText?.contains("\"url\"") == true)
        #expect(record.resultFields.contains(where: { $0.label == "result_summary" && $0.value == "Navigation completed" }))
        #expect(record.rawOutputPreview?.contains("screenshot.png") == true)
        #expect(record.evidenceFields.contains(where: { $0.label == "audit_ref" && $0.value == "audit-skill-6" }))
        #expect(record.approvalHistory.count == 1)
        #expect(record.timeline.count == 2)
        #expect(record.supervisorEvidenceJSON?.contains("\"trigger_source\"") == true)
    }

    @Test
    func displayTimelineDetailLocalizesKnownEngineeringFields() {
        let detail = ProjectSkillActivityPresentation.displayTimelineDetail(
            """
            policy_reason=execution_tier_missing_browser_runtime
            authorization_disposition=ask
            resolution_source=manual_retry
            """
        )

        #expect(detail?.contains("策略说明：execution_tier_missing_browser_runtime") == true)
        #expect(detail?.contains("审批结论：ask") == true)
        #expect(detail?.contains("处理来源：manual_retry") == true)
    }

    @Test
    func displayFullRecordTextUsesLocalizedLabelsForCopy() {
        let record = ProjectSkillFullRecord(
            requestID: "skill-display-1",
            title: "agent-browser",
            latestStatus: "awaiting_approval",
            latestStatusLabel: "待审批",
            requestMetadata: [
                ProjectSkillRecordField(label: "skill_id", value: "agent-browser"),
                ProjectSkillRecordField(label: "tool_name", value: "device.browser.control")
            ],
            approvalFields: [
                ProjectSkillRecordField(label: "policy_reason", value: "execution_tier_missing_browser_runtime"),
                ProjectSkillRecordField(label: "blocked_summary", value: "当前项目执行档位不允许浏览器自动化。"),
                ProjectSkillRecordField(label: "governance_truth", value: "当前生效 A1/S2 · 审查 Periodic。")
            ],
            toolArgumentsText: """
            {
              "url" : "https://example.com"
            }
            """,
            resultFields: [
                ProjectSkillRecordField(label: "result_summary", value: "Waiting for approval")
            ],
            rawOutputPreview: nil,
            rawOutput: nil,
            evidenceFields: [
                ProjectSkillRecordField(label: "audit_ref", value: "audit-skill-display-1")
            ],
            approvalHistory: [
                ProjectSkillRecordTimelineEntry(
                    id: "timeline-1",
                    status: "awaiting_approval",
                    statusLabel: "待审批",
                    timestamp: "2026-03-23T10:00:00.000Z",
                    summary: "等待本地审批",
                    detail: "policy_reason=execution_tier_missing_browser_runtime",
                    rawJSON: #"{"status":"awaiting_approval"}"#
                )
            ],
            timeline: [
                ProjectSkillRecordTimelineEntry(
                    id: "timeline-2",
                    status: "awaiting_approval",
                    statusLabel: "待审批",
                    timestamp: "2026-03-23T10:00:00.000Z",
                    summary: "等待本地审批",
                    detail: "resolution_source=manual_retry",
                    rawJSON: #"{"status":"awaiting_approval"}"#
                )
            ],
            supervisorEvidenceJSON: nil
        )

        let text = ProjectSkillActivityPresentation.displayFullRecordText(record)

        #expect(text.contains("最新状态：待审批"))
        #expect(text.contains("技能 ID：agent-browser"))
        #expect(text.contains("工具：device.browser.control"))
        #expect(text.contains("策略说明：execution_tier_missing_browser_runtime"))
        #expect(text.contains("阻塞说明：当前项目执行档位不允许浏览器自动化。"))
        #expect(text.contains("治理真相：当前生效 A1/S2 · 审查 Periodic。"))
        #expect(text.contains("状态：待审批"))
        #expect(text.contains("处理来源：manual_retry"))
        #expect(text.contains("== 原始 JSON 事件 =="))
    }
}
