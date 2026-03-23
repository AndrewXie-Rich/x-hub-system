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

        #expect(hubBody.contains("Hub 授权"))
        #expect(hubBody.contains("联网访问"))
        #expect(localBody.contains("本地审批"))
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

        #expect(title.contains("等待 Hub 授权"))
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
        #expect(guidanceLine?.contains("必答") == true)
        #expect(SupervisorSkillActivityPresentation.actionButtonTitle(for: item) == "打开项目")
        #expect(SupervisorSkillActivityPresentation.actionButtonTitle(for: approvalItem) == "打开授权")
    }

    @Test
    func guidanceContractLinesExposeBlockerAndNextSafeAction() {
        let record = SupervisorSkillCallRecord(
            schemaVersion: SupervisorSkillCallRecord.currentSchemaVersion,
            requestId: "skill-contract-1",
            projectId: "project-alpha",
            jobId: "job-11",
            planId: "plan-11",
            stepId: "step-11",
            skillId: "agent-browser",
            toolName: ToolName.deviceBrowserControl.rawValue,
            status: .blocked,
            payload: [:],
            currentOwner: "supervisor",
            resultSummary: "Blocked pending governance resolution.",
            denyCode: "grant_required",
            resultEvidenceRef: nil,
            requiredCapability: "web.fetch",
            grantRequestId: "grant-11",
            grantId: nil,
            createdAtMs: 1_000,
            updatedAtMs: 2_000,
            auditRef: "audit-contract-1"
        )
        let item = SupervisorManager.SupervisorRecentSkillActivity(
            projectId: "project-alpha",
            projectName: "Project Alpha",
            record: record,
            tool: .deviceBrowserControl,
            toolCall: nil,
            toolSummary: "open project dashboard",
            actionURL: nil,
            governance: .init(
                latestReviewId: "review-11",
                latestReviewVerdict: .watch,
                latestReviewLevel: .r2Strategic,
                effectiveSupervisorTier: .s3StrategicCoach,
                effectiveWorkOrderDepth: .executionReady,
                followUpRhythmSummary: "cadence=active",
                workOrderRef: "wo-11",
                latestGuidanceId: "guidance-11",
                latestGuidanceDeliveryMode: .priorityInsert,
                pendingGuidanceId: "guidance-11",
                pendingGuidanceAckStatus: .pending,
                pendingGuidanceRequired: true,
                guidanceContract: SupervisorGuidanceContractSummary(
                    kind: .grantResolution,
                    trigger: "Grant Resolution",
                    reviewLevel: "R2 Strategic",
                    verdict: "Watch",
                    summary: "Hub grant is still pending.",
                    primaryBlocker: "Hub grant pending",
                    currentState: "device action paused",
                    nextStep: "approve grant",
                    nextSafeAction: "open_hub_grants",
                    recommendedActions: ["Approve the pending hub grant", "Retry the blocked skill"],
                    workOrderRef: "wo-11",
                    effectiveSupervisorTier: "S3 Strategic Coach",
                    effectiveWorkOrderDepth: "Execution Ready"
                )
            )
        )

        let contractLine = SupervisorSkillActivityPresentation.guidanceContractLine(for: item)
        let nextSafeActionLine = SupervisorSkillActivityPresentation.guidanceNextSafeActionLine(for: item)
        let diagnostics = SupervisorSkillActivityPresentation.diagnostics(for: item)

        #expect(contractLine == "合同： 授权处理 · blocker=Hub grant pending")
        #expect(nextSafeActionLine?.contains("安全下一步： open_hub_grants") == true)
        #expect(nextSafeActionLine?.contains("Approve the pending hub grant") == true)
        #expect(diagnostics.contains("guidance_contract=grant_resolution"))
        #expect(diagnostics.contains("primary_blocker=Hub grant pending"))
        #expect(diagnostics.contains("next_safe_action=open_hub_grants"))
    }

    @Test
    func uiReviewGuidanceContractLineUsesRepairSummary() {
        let record = SupervisorSkillCallRecord(
            schemaVersion: SupervisorSkillCallRecord.currentSchemaVersion,
            requestId: "skill-contract-ui-1",
            projectId: "project-alpha",
            jobId: "job-12",
            planId: "plan-12",
            stepId: "step-12",
            skillId: "agent-browser",
            toolName: ToolName.deviceBrowserControl.rawValue,
            status: .blocked,
            payload: [:],
            currentOwner: "supervisor",
            resultSummary: "UI repair required before continuing.",
            denyCode: "",
            resultEvidenceRef: nil,
            requiredCapability: nil,
            grantRequestId: nil,
            grantId: nil,
            createdAtMs: 1_000,
            updatedAtMs: 2_000,
            auditRef: "audit-contract-ui-1"
        )
        let item = SupervisorManager.SupervisorRecentSkillActivity(
            projectId: "project-alpha",
            projectName: "Project Alpha",
            record: record,
            tool: .deviceBrowserControl,
            toolCall: nil,
            toolSummary: "browser snapshot",
            actionURL: nil,
            governance: .init(
                guidanceContract: SupervisorGuidanceContractSummary(
                    kind: .uiReviewRepair,
                    trigger: "",
                    reviewLevel: "",
                    verdict: "",
                    summary: "Primary CTA is missing from the current screen.",
                    primaryBlocker: "",
                    currentState: "",
                    nextStep: "",
                    nextSafeAction: "repair_before_execution",
                    recommendedActions: [],
                    workOrderRef: "wo-ui-1",
                    effectiveSupervisorTier: "S4 Tight Supervision",
                    effectiveWorkOrderDepth: "Execution Ready",
                    uiReviewRepair: .init(
                        instruction: "Fix the CTA before continuing automation.",
                        repairAction: "Expose the primary CTA",
                        repairFocus: "Landing hero actions",
                        nextSafeAction: "repair_before_execution",
                        uiReviewRef: "local://.xterminal/ui_review/reviews/project-alpha-latest.json",
                        uiReviewReviewId: "ui-review-1",
                        uiReviewVerdict: "attention_needed",
                        uiReviewIssueCodes: "critical_action_not_visible",
                        uiReviewSummary: "Primary CTA is missing from the current screen.",
                        skillResultSummary: "Browser snapshot captured."
                    )
                )
            )
        )

        let contractLine = SupervisorSkillActivityPresentation.guidanceContractLine(for: item)
        let nextSafeActionLine = SupervisorSkillActivityPresentation.guidanceNextSafeActionLine(for: item)
        let diagnostics = SupervisorSkillActivityPresentation.diagnostics(for: item)

        #expect(contractLine?.contains("合同： UI 审查修复") == true)
        #expect(contractLine?.contains("repair_action=Expose the primary CTA") == true)
        #expect(contractLine?.contains("repair_focus=Landing hero actions") == true)
        #expect(nextSafeActionLine == "安全下一步： repair_before_execution")
        #expect(diagnostics.contains("guidance_contract=ui_review_repair"))
        #expect(diagnostics.contains("repair_action=Expose the primary CTA"))
        #expect(diagnostics.contains("repair_focus=Landing hero actions"))
    }

    @Test
    func routingLineAndDiagnosticsExposeRequestedWrapperBuiltinResolution() {
        let record = SupervisorSkillCallRecord(
            schemaVersion: SupervisorSkillCallRecord.currentSchemaVersion,
            requestId: "skill-routing-1",
            projectId: "project-alpha",
            jobId: "job-8",
            planId: "plan-5",
            stepId: "step-4",
            skillId: "guarded-automation",
            requestedSkillId: "browser.runtime.inspect",
            routingReasonCode: "preferred_builtin_selected",
            routingExplanation: "requested entrypoint browser.runtime.inspect converged to preferred builtin guarded-automation · resolved action snapshot",
            toolName: ToolName.deviceBrowserControl.rawValue,
            status: .completed,
            payload: [
                "action": .string("snapshot"),
                "url": .string("https://example.com/dashboard")
            ],
            currentOwner: "supervisor",
            resultSummary: "Captured runtime snapshot",
            denyCode: "",
            resultEvidenceRef: nil,
            requiredCapability: nil,
            grantRequestId: nil,
            grantId: nil,
            createdAtMs: 1_000,
            updatedAtMs: 2_000,
            auditRef: "audit-routing-1"
        )
        let item = SupervisorManager.SupervisorRecentSkillActivity(
            projectId: "project-alpha",
            projectName: "Project Alpha",
            record: record,
            tool: .deviceBrowserControl,
            toolCall: ToolCall(
                id: "skill-routing-1",
                tool: .deviceBrowserControl,
                args: [
                    "action": .string("snapshot"),
                    "url": .string("https://example.com/dashboard")
                ]
            ),
            toolSummary: "https://example.com/dashboard",
            actionURL: nil
        )

        let routingLine = SupervisorSkillActivityPresentation.routingLine(for: item)
        let diagnostics = SupervisorSkillActivityPresentation.diagnostics(for: item)

        #expect(routingLine?.contains("browser.runtime.inspect -> guarded-automation") == true)
        #expect(routingLine?.contains("action=snapshot") == true)
        #expect(diagnostics.contains("requested_skill_id=browser.runtime.inspect"))
        #expect(diagnostics.contains("路由： browser.runtime.inspect -> guarded-automation"))
        #expect(diagnostics.contains("routing_reason_code=preferred_builtin_selected"))
        #expect(diagnostics.contains("routing_explanation=requested entrypoint browser.runtime.inspect converged to preferred builtin guarded-automation"))
    }

    @Test
    func routingNarrativeUsesGovernedBuiltinLanguageWhenPreferredBuiltinSelected() {
        let narrative = SupervisorSkillActivityPresentation.routingNarrative(
            requestedSkillId: "browser.open",
            effectiveSkillId: "guarded-automation",
            payload: ["action": .string("open")],
            routingReasonCode: "preferred_builtin_selected",
            routingExplanation: "requested entrypoint browser.open converged to preferred builtin guarded-automation · resolved action open"
        )

        #expect(narrative == "浏览器入口会先收敛到受治理内建 guarded-automation 再执行")
    }

    @Test
    func routingNarrativeUsesCanonicalizationLanguageWhenAliasNormalized() {
        let narrative = SupervisorSkillActivityPresentation.routingNarrative(
            requestedSkillId: "trusted-automation",
            effectiveSkillId: "guarded-automation",
            routingReasonCode: "requested_alias_normalized",
            routingExplanation: "alias trusted-automation normalized to guarded-automation"
        )

        #expect(narrative == "系统先把 trusted-automation 规范成 guarded-automation")
    }

    @Test
    func routingReasonTextLocalizesKnownReasonCodes() {
        #expect(
            SupervisorSkillActivityPresentation.routingReasonText("preferred_builtin_selected")
                == "系统优先切到受治理内建"
        )
        #expect(
            SupervisorSkillActivityPresentation.routingReasonText("requested_alias_normalized")
                == "请求技能先归一到标准技能"
        )
        #expect(
            SupervisorSkillActivityPresentation.routingReasonText("compatible_builtin_selected")
                == "系统改由兼容内建承接"
        )
        #expect(
            SupervisorSkillActivityPresentation.routingReasonText("requested_skill_routed")
                == "系统把请求路由到兼容技能"
        )
    }

    @Test
    func displayRequestMetadataFieldsLocalizeRoutingFieldsForUserFacingSections() {
        let fields = [
            ProjectSkillRecordField(label: "requested_skill_id", value: "browser.open"),
            ProjectSkillRecordField(label: "skill_id", value: "guarded-automation"),
            ProjectSkillRecordField(label: "routing_resolution", value: "browser.open -> guarded-automation"),
            ProjectSkillRecordField(label: "routing_reason_code", value: "preferred_builtin_selected"),
            ProjectSkillRecordField(
                label: "routing_explanation",
                value: "requested entrypoint browser.open converged to preferred builtin guarded-automation · resolved action open"
            ),
            ProjectSkillRecordField(label: "tool_name", value: "device.browser.control")
        ]

        let localized = SupervisorSkillActivityPresentation.displayRequestMetadataFields(fields)

        #expect(localized.contains(where: { $0.label == "请求技能" && $0.value == "browser.open" }))
        #expect(localized.contains(where: { $0.label == "生效技能" && $0.value == "guarded-automation" }))
        #expect(localized.contains(where: { $0.label == "路由" && $0.value == "browser.open -> guarded-automation" }))
        #expect(localized.contains(where: { $0.label == "路由判定" && $0.value == "系统优先切到受治理内建" }))
        #expect(localized.contains(where: {
            $0.label == "路由说明" && $0.value == "浏览器入口会先收敛到受治理内建 guarded-automation 再执行"
        }))
        #expect(localized.contains(where: { $0.label == "工具" && $0.value == "device.browser.control" }))
    }

    @Test
    func displayMetadataFieldsLocalizeCommonSupervisorFieldLabels() {
        let fields = [
            ProjectSkillRecordField(label: "policy_reason", value: "execution_tier_missing_browser_runtime"),
            ProjectSkillRecordField(label: "work_order_depth", value: "execution_ready"),
            ProjectSkillRecordField(label: "result_evidence_ref", value: "local://supervisor_skill_results/skill-1.json"),
            ProjectSkillRecordField(label: "audit_ref", value: "audit-skill-1")
        ]

        let localized = SupervisorSkillActivityPresentation.displayMetadataFields(fields)

        #expect(localized.contains(where: { $0.label == "策略原因" && $0.value == "execution_tier_missing_browser_runtime" }))
        #expect(localized.contains(where: { $0.label == "工单深度" && $0.value == "execution_ready" }))
        #expect(localized.contains(where: { $0.label == "结果证据引用" && $0.value == "local://supervisor_skill_results/skill-1.json" }))
        #expect(localized.contains(where: { $0.label == "审计引用" && $0.value == "audit-skill-1" }))
    }

    @Test
    func displayFullRecordTextUsesLocalizedRoutingSummaryAndKeepsRawRoutingAppendix() {
        let record = SupervisorSkillFullRecord(
            requestID: "req-routing-copy-1",
            projectName: "Project Alpha",
            title: "browser.open -> guarded-automation · action=open",
            latestStatus: "completed",
            latestStatusLabel: "已完成",
            requestMetadata: [
                ProjectSkillRecordField(label: "requested_skill_id", value: "browser.open"),
                ProjectSkillRecordField(label: "skill_id", value: "guarded-automation"),
                ProjectSkillRecordField(label: "routing_resolution", value: "browser.open -> guarded-automation"),
                ProjectSkillRecordField(label: "routing_reason_code", value: "preferred_builtin_selected"),
                ProjectSkillRecordField(
                    label: "routing_explanation",
                    value: "requested entrypoint browser.open converged to preferred builtin guarded-automation · resolved action open"
                )
            ],
            approvalFields: [
                ProjectSkillRecordField(label: "policy_reason", value: "execution_tier_missing_browser_runtime")
            ],
            governanceFields: [
                ProjectSkillRecordField(label: "work_order_depth", value: "execution_ready")
            ],
            skillPayloadText: nil,
            toolArgumentsText: nil,
            resultFields: [
                ProjectSkillRecordField(label: "result_summary", value: "Opened login page")
            ],
            rawOutputPreview: nil,
            rawOutput: nil,
            evidenceFields: [
                ProjectSkillRecordField(label: "result_evidence_ref", value: "local://supervisor_skill_results/skill-routing-copy-1.json")
            ],
            approvalHistory: [],
            timeline: [],
            uiReviewAgentEvidenceFields: [],
            uiReviewAgentEvidenceText: nil,
            supervisorEvidenceJSON: nil,
            guidanceContract: nil
        )

        let text = SupervisorSkillActivityPresentation.displayFullRecordText(record)

        #expect(text.contains("请求技能=browser.open"))
        #expect(text.contains("生效技能=guarded-automation"))
        #expect(text.contains("路由判定=系统优先切到受治理内建"))
        #expect(text.contains("路由说明=浏览器入口会先收敛到受治理内建 guarded-automation 再执行"))
        #expect(text.contains("策略原因=execution_tier_missing_browser_runtime"))
        #expect(text.contains("工单深度=execution_ready"))
        #expect(text.contains("结果摘要=Opened login page"))
        #expect(text.contains("结果证据引用=local://supervisor_skill_results/skill-routing-copy-1.json"))
        #expect(text.contains("== 路由诊断原文 =="))
        #expect(text.contains("routing_reason_code=preferred_builtin_selected"))
        #expect(text.contains("routing_explanation=requested entrypoint browser.open converged to preferred builtin guarded-automation"))
    }

    @Test
    func queuedBodyUsesRequestedWrapperBuiltinDisplaySummary() {
        let record = SupervisorSkillCallRecord(
            schemaVersion: SupervisorSkillCallRecord.currentSchemaVersion,
            requestId: "skill-routing-body-1",
            projectId: "project-alpha",
            jobId: "job-12",
            planId: "plan-12",
            stepId: "step-12",
            skillId: "guarded-automation",
            requestedSkillId: "browser.open",
            toolName: ToolName.deviceBrowserControl.rawValue,
            status: .queued,
            payload: [
                "action": .string("open"),
                "url": .string("https://example.com/login")
            ],
            currentOwner: "supervisor",
            resultSummary: "",
            denyCode: "",
            resultEvidenceRef: nil,
            requiredCapability: nil,
            grantRequestId: nil,
            grantId: nil,
            createdAtMs: 1_000,
            updatedAtMs: 2_000,
            auditRef: "audit-routing-body-1"
        )
        let item = SupervisorManager.SupervisorRecentSkillActivity(
            projectId: "project-alpha",
            projectName: "Project Alpha",
            record: record,
            tool: .deviceBrowserControl,
            toolCall: ToolCall(
                id: "skill-routing-body-1",
                tool: .deviceBrowserControl,
                args: [
                    "action": .string("open"),
                    "url": .string("https://example.com/login")
                ]
            ),
            toolSummary: "https://example.com/login",
            actionURL: nil
        )

        let displaySkill = SupervisorSkillActivityPresentation.displaySkillSummary(for: item)
        let body = SupervisorSkillActivityPresentation.body(for: item)

        #expect(displaySkill == "browser.open -> guarded-automation · action=open")
        #expect(body.contains("技能 browser.open -> guarded-automation · action=open"))
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
        #expect(fullRecord.latestStatusLabel == "已完成")
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
        #expect(SupervisorSkillActivityPresentation.fullRecordText(fullRecord).contains("Supervisor 技能完整记录"))
        #expect(SupervisorSkillActivityPresentation.fullRecordText(fullRecord).contains("== 治理上下文 =="))
        #expect(SupervisorSkillActivityPresentation.fullRecordText(fullRecord).contains("== 技能载荷 =="))
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

        #expect(body.contains("不在受治理白名单里"))
        #expect(body.contains("更新技能契约"))
    }

    @Test
    func blockedGovernanceBodyAndDiagnosticsUsePolicyContext() {
        let record = SupervisorSkillCallRecord(
            schemaVersion: SupervisorSkillCallRecord.currentSchemaVersion,
            requestId: "skill-blocked-2",
            projectId: "project-alpha",
            jobId: "job-9",
            planId: "plan-4",
            stepId: "step-2",
            skillId: "open-index-html",
            toolName: ToolName.process_start.rawValue,
            status: .blocked,
            payload: ["name": .string("open-index-html")],
            currentOwner: "supervisor",
            resultSummary: "project governance blocks process_start under execution tier a0_observe",
            denyCode: "governance_capability_denied",
            policySource: "project_governance",
            policyReason: "execution_tier_missing_managed_processes",
            resultEvidenceRef: nil,
            requiredCapability: nil,
            grantRequestId: nil,
            grantId: nil,
            createdAtMs: 1_000,
            updatedAtMs: 2_000,
            auditRef: "audit-blocked-2"
        )
        let item = SupervisorManager.SupervisorRecentSkillActivity(
            projectId: "project-alpha",
            projectName: "Project Alpha",
            record: record,
            tool: .process_start,
            toolCall: ToolCall(
                id: "skill-blocked-2",
                tool: .process_start,
                args: ["name": .string("open-index-html")]
            ),
            toolSummary: "open-index-html",
            actionURL: nil
        )

        let body = SupervisorSkillActivityPresentation.body(for: item)
        let diagnostics = SupervisorSkillActivityPresentation.diagnostics(for: item)

        #expect(body.contains("不允许受治理的后台进程"))
        #expect(body.contains("打开项目设置 -> 执行档位"))
        #expect(body.contains("A2 Repo Auto"))
        #expect(diagnostics.contains("policy_source=project_governance"))
        #expect(diagnostics.contains("policy_reason=execution_tier_missing_managed_processes"))
    }

    @Test
    func fullRecordRetainsPolicyContextForBlockedSkill() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt_supervisor_skill_policy_record_\(UUID().uuidString)", isDirectory: true)
        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()

        let record = SupervisorSkillCallRecord(
            schemaVersion: SupervisorSkillCallRecord.currentSchemaVersion,
            requestId: "skill-policy-1",
            projectId: "project-alpha",
            jobId: "job-3",
            planId: "plan-2",
            stepId: "step-8",
            skillId: "agent-browser",
            toolName: ToolName.deviceBrowserControl.rawValue,
            status: .blocked,
            payload: ["action": .string("open_url")],
            currentOwner: "supervisor",
            resultSummary: "browser automation blocked by governance",
            denyCode: "governance_capability_denied",
            policySource: "project_governance",
            policyReason: "execution_tier_missing_browser_runtime",
            resultEvidenceRef: nil,
            requiredCapability: nil,
            grantRequestId: nil,
            grantId: nil,
            createdAtMs: 1_000,
            updatedAtMs: 2_000,
            auditRef: "audit-policy-1"
        )
        try SupervisorProjectSkillCallStore.upsert(record, for: ctx)
        _ = SupervisorSkillResultEvidenceStore.write(
            record: record,
            toolCall: ToolCall(
                id: "skill-policy-1",
                tool: .deviceBrowserControl,
                args: ["action": .string("open_url")]
            ),
            rawOutput: nil,
            triggerSource: "user_turn",
            ctx: ctx
        )

        let fullRecord = try #require(
            SupervisorSkillActivityPresentation.fullRecord(
                ctx: ctx,
                projectName: "Project Alpha",
                requestID: "skill-policy-1"
            )
        )

        #expect(fullRecord.approvalFields.contains(where: { $0.label == "policy_source" && $0.value == "project_governance" }))
        #expect(fullRecord.approvalFields.contains(where: { $0.label == "policy_reason" && $0.value == "execution_tier_missing_browser_runtime" }))
        #expect(SupervisorSkillActivityPresentation.fullRecordText(fullRecord).contains("policy_reason=execution_tier_missing_browser_runtime"))
    }

    @Test
    func fullRecordIncludesRequestedSkillAndRoutingResolution() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt_supervisor_skill_routing_record_\(UUID().uuidString)", isDirectory: true)
        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()

        let record = SupervisorSkillCallRecord(
            schemaVersion: SupervisorSkillCallRecord.currentSchemaVersion,
            requestId: "skill-routing-record-1",
            projectId: "project-alpha",
            jobId: "job-10",
            planId: "plan-10",
            stepId: "step-1",
            skillId: "guarded-automation",
            requestedSkillId: "browser.open",
            routingReasonCode: "preferred_builtin_selected",
            routingExplanation: "requested entrypoint browser.open converged to preferred builtin guarded-automation · resolved action open",
            toolName: ToolName.deviceBrowserControl.rawValue,
            status: .completed,
            payload: [
                "action": .string("open"),
                "url": .string("https://example.com/login")
            ],
            currentOwner: "supervisor",
            resultSummary: "Opened login page",
            denyCode: "",
            resultEvidenceRef: nil,
            requiredCapability: nil,
            grantRequestId: nil,
            grantId: nil,
            createdAtMs: 1_000,
            updatedAtMs: 2_000,
            auditRef: "audit-routing-record-1"
        )
        try SupervisorProjectSkillCallStore.upsert(record, for: ctx)
        _ = SupervisorSkillResultEvidenceStore.write(
            record: record,
            toolCall: ToolCall(
                id: "skill-routing-record-1",
                tool: .deviceBrowserControl,
                args: [
                    "action": .string("open_url"),
                    "url": .string("https://example.com/login")
                ]
            ),
            rawOutput: "Opened login page",
            triggerSource: "user_turn",
            ctx: ctx
        )

        let raw = """
        {"type":"supervisor_skill_call","action":"dispatch","request_id":"skill-routing-record-1","project_id":"project-alpha","job_id":"job-10","plan_id":"plan-10","step_id":"step-1","requested_skill_id":"browser.open","skill_id":"guarded-automation","routing_reason_code":"preferred_builtin_selected","routing_explanation":"requested entrypoint browser.open converged to preferred builtin guarded-automation · resolved action open","tool_name":"device.browser.control","status":"queued","tool":"device.browser.control","tool_args":{"action":"open_url","url":"https://example.com/login"},"timestamp_ms":1000,"audit_ref":"audit-routing-record-1","trigger_source":"user_turn"}
        {"type":"supervisor_skill_result","request_id":"skill-routing-record-1","project_id":"project-alpha","job_id":"job-10","plan_id":"plan-10","step_id":"step-1","requested_skill_id":"browser.open","skill_id":"guarded-automation","routing_reason_code":"preferred_builtin_selected","routing_explanation":"requested entrypoint browser.open converged to preferred builtin guarded-automation · resolved action open","tool_name":"device.browser.control","status":"completed","result_summary":"Opened login page","result_evidence_ref":"local://supervisor_skill_results/skill-routing-record-1.json","tool":"device.browser.control","tool_args":{"action":"open_url","url":"https://example.com/login"},"updated_at_ms":2000,"audit_ref":"audit-routing-record-1","trigger_source":"user_turn"}
        """
        try #require(raw.data(using: .utf8)).write(to: ctx.rawLogURL, options: .atomic)

        let fullRecord = try #require(
            SupervisorSkillActivityPresentation.fullRecord(
                ctx: ctx,
                projectName: "Project Alpha",
                requestID: "skill-routing-record-1"
            )
        )

        #expect(fullRecord.title == "browser.open -> guarded-automation · action=open")
        #expect(fullRecord.requestMetadata.contains(where: { $0.label == "requested_skill_id" && $0.value == "browser.open" }))
        #expect(fullRecord.requestMetadata.contains(where: {
            $0.label == "routing_resolution" && $0.value.contains("browser.open -> guarded-automation")
        }))
        #expect(fullRecord.requestMetadata.contains(where: { $0.label == "routing_reason_code" && $0.value == "preferred_builtin_selected" }))
        #expect(fullRecord.requestMetadata.contains(where: {
            $0.label == "routing_explanation" && $0.value.contains("requested entrypoint browser.open converged to preferred builtin guarded-automation")
        }))
        #expect(SupervisorSkillActivityPresentation.fullRecordText(fullRecord).contains("requested_skill_id=browser.open"))
        #expect(SupervisorSkillActivityPresentation.fullRecordText(fullRecord).contains("routing_resolution=browser.open -> guarded-automation"))
        #expect(SupervisorSkillActivityPresentation.fullRecordText(fullRecord).contains("routing_reason_code=preferred_builtin_selected"))
        #expect(SupervisorSkillActivityPresentation.fullRecordText(fullRecord).contains("routing_explanation=requested entrypoint browser.open converged to preferred builtin guarded-automation"))
    }

    @Test
    func fullRecordLoadsUIReviewAgentEvidenceFromToolResultOutput() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt_supervisor_skill_ui_review_evidence_\(UUID().uuidString)", isDirectory: true)
        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()

        let snapshot = XTUIReviewAgentEvidenceSnapshot(
            schemaVersion: XTUIReviewAgentEvidenceSnapshot.currentSchemaVersion,
            reviewID: "review-ui-1",
            projectID: "project-alpha",
            bundleID: "bundle-ui-1",
            auditRef: "audit-ui-review-1",
            reviewRef: "local://.xterminal/ui_review/reviews/review-ui-1.json",
            bundleRef: "local://.xterminal/ui_observation/bundles/bundle-ui-1.json",
            updatedAtMs: 3_000,
            verdict: .ready,
            confidence: .high,
            sufficientEvidence: true,
            objectiveReady: true,
            issueCodes: ["critical_action_visible"],
            summary: "Primary CTA is visible and the browser state is ready for the next agent step.",
            artifactRefs: ["screenshot_ref=local://.xterminal/ui_observation/artifacts/bundle-ui-1/full.png"],
            artifactPaths: ["/tmp/bundle-ui-1/full.png"],
            checks: ["critical_action=pass :: Primary CTA visible above the fold."],
            trend: ["status=stable"],
            comparison: ["critical_action_visible=stable"],
            recentHistory: ["review_id=review-ui-0 verdict=ready"]
        )
        try XTUIReviewAgentEvidenceStore.write(snapshot, for: ctx)
        let evidenceRef = XTUIReviewAgentEvidenceStore.reviewRef(reviewID: snapshot.reviewID)

        let record = SupervisorSkillCallRecord(
            schemaVersion: SupervisorSkillCallRecord.currentSchemaVersion,
            requestId: "skill-ui-review-1",
            projectId: "project-alpha",
            jobId: "job-ui-1",
            planId: "plan-ui-1",
            stepId: "step-ui-1",
            skillId: "agent-browser",
            toolName: ToolName.deviceBrowserControl.rawValue,
            status: .completed,
            payload: ["action": .string("snapshot")],
            currentOwner: "supervisor",
            resultSummary: "Captured a governed browser snapshot.",
            denyCode: "",
            resultEvidenceRef: nil,
            requiredCapability: nil,
            grantRequestId: nil,
            grantId: nil,
            createdAtMs: 1_000,
            updatedAtMs: 3_000,
            auditRef: "audit-skill-ui-review-1"
        )
        try SupervisorProjectSkillCallStore.upsert(record, for: ctx)

        _ = SupervisorSkillResultEvidenceStore.write(
            record: record,
            toolCall: ToolCall(
                id: "skill-ui-review-1",
                tool: .deviceBrowserControl,
                args: ["action": .string("snapshot")]
            ),
            rawOutput: """
            {"ok":true,"ui_review_agent_evidence_ref":"\(evidenceRef)","ui_review_summary":"Primary CTA visible and ready"}
            """,
            triggerSource: "user_turn",
            ctx: ctx
        )

        let fullRecord = try #require(
            SupervisorSkillActivityPresentation.fullRecord(
                ctx: ctx,
                projectName: "Project Alpha",
                requestID: "skill-ui-review-1"
            )
        )

        #expect(fullRecord.uiReviewAgentEvidenceFields.contains(where: {
            $0.label == "ui_review_agent_evidence_ref" && $0.value == evidenceRef
        }))
        #expect(fullRecord.uiReviewAgentEvidenceFields.contains(where: {
            $0.label == "verdict" && $0.value == "ready"
        }))
        #expect(fullRecord.uiReviewAgentEvidenceFields.contains(where: {
            $0.label == "summary" && $0.value.contains("Primary CTA is visible")
        }))
        #expect(fullRecord.uiReviewAgentEvidenceText?.contains("verdict=ready") == true)
        #expect(fullRecord.uiReviewAgentEvidenceText?.contains("issue_codes=critical_action_visible") == true)
        #expect(SupervisorSkillActivityPresentation.fullRecordText(fullRecord).contains("== UI 审查代理证据 =="))
        #expect(SupervisorSkillActivityPresentation.fullRecordText(fullRecord).contains("== UI 审查代理证据详情 =="))
    }
}
