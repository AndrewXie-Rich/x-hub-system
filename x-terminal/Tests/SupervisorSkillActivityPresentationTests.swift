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
        #expect(hubBody.contains("联网访问"))
        #expect(localBody.contains("local approval"))
        #expect(!SupervisorSkillActivityPresentation.isAwaitingLocalApproval(hubGrantItem))
        #expect(SupervisorSkillActivityPresentation.isAwaitingLocalApproval(localApprovalItem))
    }

    @Test
    func awaitingAuthorizationTitleUsesHumanCapabilityLabel() {
        let hubGrantRecord = SupervisorSkillCallRecord(
            schemaVersion: SupervisorSkillCallRecord.currentSchemaVersion,
            requestId: "skill-hub-title-1",
            projectId: "project-alpha",
            jobId: "job-1",
            planId: "plan-1",
            stepId: "step-1",
            skillId: "agent-browser",
            toolName: ToolName.deviceBrowserControl.rawValue,
            status: .awaitingAuthorization,
            payload: [:],
            currentOwner: "supervisor",
            resultSummary: "",
            denyCode: "grant_required",
            resultEvidenceRef: nil,
            requiredCapability: "web.fetch",
            grantRequestId: "grant-title-1",
            grantId: nil,
            createdAtMs: 1_000,
            updatedAtMs: 2_000,
            auditRef: "audit-title"
        )
        let item = SupervisorManager.SupervisorRecentSkillActivity(
            projectId: "project-alpha",
            projectName: "Project Alpha",
            record: hubGrantRecord,
            tool: .deviceBrowserControl,
            toolCall: nil,
            toolSummary: "https://example.com",
            actionURL: nil
        )

        let title = SupervisorSkillActivityPresentation.title(for: item)

        #expect(title.contains("Hub grant required"))
        #expect(title.contains("联网访问"))
    }

    @Test
    func workflowAndGovernanceSummariesAreStructuredAndActionLabelTracksState() {
        let record = SupervisorSkillCallRecord(
            schemaVersion: SupervisorSkillCallRecord.currentSchemaVersion,
            requestId: "skill-governance-1",
            projectId: "project-alpha",
            jobId: "job-7",
            planId: "plan-9",
            stepId: "step-3",
            skillId: "self-improving-agent",
            toolName: ToolName.run_command.rawValue,
            status: .completed,
            payload: [:],
            currentOwner: "supervisor",
            resultSummary: "Applied the next guarded iteration.",
            denyCode: "",
            resultEvidenceRef: nil,
            requiredCapability: nil,
            grantRequestId: nil,
            grantId: nil,
            createdAtMs: 1_000,
            updatedAtMs: 2_000,
            auditRef: "audit-governance-1"
        )
        let item = SupervisorManager.SupervisorRecentSkillActivity(
            projectId: "project-alpha",
            projectName: "Project Alpha",
            record: record,
            tool: .run_command,
            toolCall: nil,
            toolSummary: "swift test --filter smoke",
            actionURL: "x-terminal://project/project-alpha",
            governance: .init(
                latestReviewId: "review-9",
                latestReviewVerdict: .betterPathFound,
                latestReviewLevel: .r2Strategic,
                effectiveSupervisorTier: .s3StrategicCoach,
                effectiveWorkOrderDepth: .executionReady,
                followUpRhythmSummary: "cadence=active · blocker cooldown≈180s",
                workOrderRef: "wo-9",
                latestGuidanceId: "guidance-9",
                latestGuidanceDeliveryMode: .priorityInsert,
                pendingGuidanceId: "guidance-9",
                pendingGuidanceAckStatus: .pending,
                pendingGuidanceRequired: true
            )
        )
        let approvalRecord = SupervisorSkillCallRecord(
            schemaVersion: SupervisorSkillCallRecord.currentSchemaVersion,
            requestId: "skill-governance-2",
            projectId: "project-alpha",
            jobId: "",
            planId: "",
            stepId: "",
            skillId: "agent-browser",
            toolName: ToolName.deviceBrowserControl.rawValue,
            status: .awaitingAuthorization,
            payload: [:],
            currentOwner: "supervisor",
            resultSummary: "",
            denyCode: "grant_required",
            resultEvidenceRef: nil,
            requiredCapability: "web.fetch",
            grantRequestId: "grant-2",
            grantId: nil,
            createdAtMs: 1_000,
            updatedAtMs: 2_000,
            auditRef: "audit-governance-2"
        )
        let approvalItem = SupervisorManager.SupervisorRecentSkillActivity(
            projectId: "project-alpha",
            projectName: "Project Alpha",
            record: approvalRecord,
            tool: .deviceBrowserControl,
            toolCall: nil,
            toolSummary: "",
            actionURL: "x-terminal://supervisor"
        )

        let workflowLine = SupervisorSkillActivityPresentation.workflowLine(for: item)
        let governanceLine = SupervisorSkillActivityPresentation.governanceLine(for: item)
        let followUpLine = SupervisorSkillActivityPresentation.followUpRhythmLine(for: item)
        let guidanceLine = SupervisorSkillActivityPresentation.pendingGuidanceLine(for: item)

        #expect(workflowLine?.contains("job=job-7") == true)
        #expect(workflowLine?.contains("plan=plan-9") == true)
        #expect(governanceLine?.contains("S3 Strategic Coach") == true)
        #expect(governanceLine?.contains("work_order=wo-9") == true)
        #expect(followUpLine?.contains("blocker cooldown≈180s") == true)
        #expect(guidanceLine?.contains("Pending") == true)
        #expect(guidanceLine?.contains("required") == true)
        #expect(SupervisorSkillActivityPresentation.actionButtonTitle(for: item) == "Open Project")
        #expect(SupervisorSkillActivityPresentation.actionButtonTitle(for: approvalItem) == "Open Grant")
    }

    @Test
    func fullRecordBuildsStructuredSupervisorEvidenceSections() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt_supervisor_skill_record_\(UUID().uuidString)", isDirectory: true)
        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()
        var config = AXProjectConfig.default(forProjectRoot: root)
        config = config.settingProjectGovernance(
            executionTier: .a3DeliverAuto,
            supervisorInterventionTier: .s3StrategicCoach,
            reviewPolicyMode: .hybrid,
            progressHeartbeatSeconds: 600,
            reviewPulseSeconds: 1200,
            brainstormReviewSeconds: 2400,
            eventDrivenReviewEnabled: true,
            eventReviewTriggers: [.blockerDetected, .planDrift, .preDoneSummary]
        )
        try AXProjectStore.saveConfig(config, for: ctx)
        try SupervisorReviewNoteStore.upsert(
            SupervisorReviewNoteBuilder.build(
                reviewId: "review-7",
                projectId: "project-alpha",
                trigger: .manualRequest,
                reviewLevel: .r2Strategic,
                verdict: .betterPathFound,
                targetRole: .supervisor,
                deliveryMode: .replanRequest,
                ackRequired: true,
                effectiveSupervisorTier: .s3StrategicCoach,
                effectiveWorkOrderDepth: .executionReady,
                projectAIStrengthBand: .strong,
                projectAIStrengthConfidence: 0.91,
                projectAIStrengthAuditRef: "audit-strength-7",
                workOrderRef: "wo-7",
                summary: "Keep the browser skill aligned with the guarded work order.",
                recommendedActions: ["Verify the browser result before expanding scope."],
                anchorGoal: "Capture browser evidence safely",
                anchorDoneDefinition: "The run stores evidence and links back to governance.",
                anchorConstraints: ["No raw secret leakage."],
                currentState: "Browser automation just completed.",
                nextStep: "Inspect the structured evidence record.",
                blocker: "",
                createdAtMs: 2_000,
                auditRef: "audit-review-7"
            ),
            for: ctx
        )
        try SupervisorGuidanceInjectionStore.upsert(
            SupervisorGuidanceInjectionBuilder.build(
                injectionId: "guidance-7",
                reviewId: "review-7",
                projectId: "project-alpha",
                targetRole: .supervisor,
                deliveryMode: .priorityInsert,
                interventionMode: .replanNextSafePoint,
                safePointPolicy: .nextStepBoundary,
                guidanceText: "Review the browser evidence before dispatching another navigation step.",
                ackStatus: .pending,
                ackRequired: true,
                effectiveSupervisorTier: .s3StrategicCoach,
                effectiveWorkOrderDepth: .executionReady,
                workOrderRef: "wo-7",
                ackNote: "",
                injectedAtMs: 2_200,
                ackUpdatedAtMs: 2_200,
                expiresAtMs: 4_000_000_000_000,
                retryAtMs: 0,
                retryCount: 0,
                maxRetryCount: 0,
                auditRef: "audit-guidance-7"
            ),
            for: ctx
        )

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
        #expect(fullRecord.governanceFields.contains(where: { $0.label == "supervisor_tier" && $0.value == "S3 Strategic Coach" }))
        #expect(fullRecord.governanceFields.contains(where: { $0.label == "work_order_ref" && $0.value == "wo-7" }))
        #expect(fullRecord.governanceFields.contains(where: { $0.label == "pending_guidance_id" && $0.value == "guidance-7" }))
        #expect(fullRecord.governanceFields.contains(where: { $0.label == "follow_up_rhythm" && $0.value.contains("blocker cooldown") }))
        #expect(fullRecord.resultFields.contains(where: { $0.label == "result_summary" && $0.value == "Navigation completed" }))
        #expect(fullRecord.rawOutputPreview?.contains("screenshot.png") == true)
        #expect(fullRecord.evidenceFields.contains(where: { $0.label == "audit_ref" && $0.value == "audit-skill-7" }))
        #expect(fullRecord.timeline.count == 3)
        #expect(fullRecord.supervisorEvidenceJSON?.contains("\"trigger_source\"") == true)
        #expect(SupervisorSkillActivityPresentation.fullRecordText(fullRecord).contains("== Governance Context =="))
        #expect(SupervisorSkillActivityPresentation.fullRecordText(fullRecord).contains("== Skill Payload =="))
    }

    @Test
    func blockedPayloadAllowlistBodyUsesHumanGuidance() {
        let record = SupervisorSkillCallRecord(
            schemaVersion: SupervisorSkillCallRecord.currentSchemaVersion,
            requestId: "skill-blocked-1",
            projectId: "project-alpha",
            jobId: "job-1",
            planId: "plan-1",
            stepId: "step-1",
            skillId: "agent-backup",
            toolName: ToolName.run_command.rawValue,
            status: .blocked,
            payload: ["command": .string("rm -rf . && tar czf backup.tgz .")],
            currentOwner: "supervisor",
            resultSummary: "repo command rejected by governed allowlist",
            denyCode: "payload.command_not_allowed",
            resultEvidenceRef: nil,
            requiredCapability: nil,
            grantRequestId: nil,
            grantId: nil,
            createdAtMs: 1_000,
            updatedAtMs: 2_000,
            auditRef: "audit-blocked-1"
        )
        let item = SupervisorManager.SupervisorRecentSkillActivity(
            projectId: "project-alpha",
            projectName: "Project Alpha",
            record: record,
            tool: .run_command,
            toolCall: ToolCall(
                id: "skill-blocked-1",
                tool: .run_command,
                args: ["command": .string("rm -rf . && tar czf backup.tgz .")]
            ),
            toolSummary: "rm -rf . && tar czf backup.tgz .",
            actionURL: nil
        )

        let body = SupervisorSkillActivityPresentation.body(for: item)

        #expect(body.contains("outside the governed allowlist"))
        #expect(body.contains("update the skill contract"))
    }
}
