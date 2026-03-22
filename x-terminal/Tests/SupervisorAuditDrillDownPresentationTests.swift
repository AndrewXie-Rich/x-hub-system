import Foundation
import Testing
@testable import XTerminal

struct SupervisorAuditDrillDownPresentationTests {

    @Test
    func officialChannelMapsSnapshotAndSafetyContext() {
        let presentation = SupervisorAuditDrillDownPresentation.officialSkillsChannel(
            statusLine: "official healthy skills=24 auto=persisted",
            transitionLine: "current_snapshot_repaired: current snapshot restored via persisted",
            detailLine: "pkg=4 ready=2 blocked=1 not_installed=1 active=2 problem_skills=agent-browser,calendar-sync Top blockers: Agent Browser (agent-browser) [blocked]; Calendar Skill (calendar-sync) [not installed]",
            blockerSummaries: [
                AXOfficialSkillBlockerSummaryItem(
                    packageSHA256: "sha-agent-browser",
                    title: "Agent Browser",
                    subtitle: "agent-browser",
                    stateLabel: "blocked",
                    summaryLine: "version=2.0.0 package=ready risk=high grant=required",
                    timelineLine: "last_blocked=2026-03-19T12:00:00Z"
                ),
                AXOfficialSkillBlockerSummaryItem(
                    packageSHA256: "sha-calendar-sync",
                    title: "Calendar Skill",
                    subtitle: "calendar-sync",
                    stateLabel: "not installed",
                    summaryLine: "version=1.5.0 package=missing risk=medium grant=none",
                    timelineLine: "updated=2026-03-19T10:00:00Z"
                )
            ],
            eventLoopStatusLine: "idle"
        )

        #expect(presentation.title == "官方技能通道")
        #expect(presentation.statusLabel == "健康")
        #expect(presentation.tone == .success)
        #expect(presentation.summary.contains("official healthy"))
        #expect(presentation.sections.count == 3)
        #expect(presentation.actionLabel == "处理授权阻塞")
        #expect(presentation.actionURL?.contains("hub-setup") == true)
        #expect(presentation.actionURL?.contains("section_id=troubleshoot") == true)
        #expect(presentation.secondaryActions.count == 1)
        #expect(presentation.secondaryActions[0].label == "查看 Calendar Skill")
        #expect(presentation.secondaryActions[0].url.contains("settings") == true)
        #expect(presentation.sections[0].fields.contains(where: {
            $0.label == "最近切换" && $0.value.contains("current snapshot restored")
        }))
        #expect(presentation.sections[0].fields.contains(where: {
            $0.label == "包就绪度" && $0.value.contains("problem_skills=agent-browser,calendar-sync")
        }))
        #expect(presentation.sections[1].fields.contains(where: {
            $0.label == "安全边界" && $0.value.contains("最终权威")
        }))
        #expect(presentation.sections[2].fields.contains(where: {
            $0.label == "Agent Browser" && $0.value.contains("状态=blocked")
        }))
        #expect(presentation.sections[2].fields.contains(where: {
            $0.label == "Calendar Skill" && $0.value.contains("状态=not installed")
        }))
    }

    @Test
    func pendingHubGrantMapsScopeDecisionAndOpenAction() {
        let grant = SupervisorManager.SupervisorPendingGrant(
            id: "grant-1",
            dedupeKey: "grant:web.fetch:project-alpha",
            grantRequestId: "grant-1",
            requestId: "req-1",
            projectId: "project-alpha",
            projectName: "Project Alpha",
            capability: "web.fetch",
            modelId: "gpt-5.4",
            reason: "browser fetch for live verification",
            requestedTtlSec: 3600,
            requestedTokenCap: 8000,
            createdAt: 10,
            actionURL: "x-terminal://grant/grant-1",
            priorityRank: 1,
            priorityReason: "project blocked",
            nextAction: "approve hub grant"
        )

        let presentation = SupervisorAuditDrillDownPresentation.pendingHubGrant(grant)

        #expect(presentation.title == "Hub 授权待处理")
        #expect(presentation.statusLabel == "待处理")
        #expect(presentation.tone == .attention)
        #expect(presentation.actionLabel == "打开授权")
        #expect(presentation.requestId == "req-1")
        #expect(presentation.sections.count == 3)
        #expect(presentation.sections[0].fields.contains(where: {
            $0.label == "能力" && !$0.value.isEmpty
        }))
        #expect(presentation.sections[1].fields.contains(where: {
            $0.label == "请求时长" && $0.value == "1h"
        }))
        #expect(presentation.sections[2].fields.contains(where: {
            $0.label == "下一步" && $0.value == "approve hub grant"
        }))
    }

    @Test
    func pendingSkillApprovalShowsRequestedWrapperAndBuiltinRouting() {
        let approval = SupervisorManager.SupervisorPendingSkillApproval(
            id: "approval-1",
            requestId: "req-approval-1",
            projectId: "project-alpha",
            projectName: "Project Alpha",
            jobId: "job-1",
            planId: "plan-1",
            stepId: "step-1",
            skillId: "guarded-automation",
            requestedSkillId: "browser.open",
            toolName: ToolName.deviceBrowserControl.rawValue,
            tool: .deviceBrowserControl,
            toolSummary: "Open https://example.com/login",
            reason: "browser control touches live login flow",
            createdAt: 10,
            actionURL: "x-terminal://approval/req-approval-1",
            routingReasonCode: "preferred_builtin_selected",
            routingExplanation: "requested entrypoint browser.open converged to preferred builtin guarded-automation · resolved action open"
        )

        let presentation = SupervisorAuditDrillDownPresentation.pendingSkillApproval(approval)

        #expect(presentation.title == "本地技能审批待处理")
        #expect(presentation.statusLabel == "待处理")
        #expect(presentation.actionLabel == "打开审批")
        #expect(presentation.sections[0].fields.contains(where: {
            $0.label == "请求技能" && $0.value == "browser.open"
        }))
        #expect(presentation.sections[0].fields.contains(where: {
            $0.label == "生效技能" && $0.value == "guarded-automation"
        }))
        #expect(!presentation.sections[0].fields.contains(where: { $0.label == "技能" }))
        #expect(presentation.sections[1].fields.contains(where: {
            $0.label == "路由" && $0.value.contains("browser.open -> guarded-automation")
        }))
        #expect(presentation.sections[1].fields.contains(where: {
            $0.label == "路由判定" && $0.value == "系统优先切到受治理内建"
        }))
        #expect(presentation.sections[1].fields.contains(where: {
            $0.label == "路由代码" && $0.value == "preferred_builtin_selected"
        }))
        #expect(presentation.sections[1].fields.contains(where: {
            $0.label == "路由说明" && $0.value.contains("浏览器入口会先收敛到受治理内建 guarded-automation 再执行")
        }))
        #expect(presentation.sections[1].fields.contains(where: {
            $0.label == "路由解释" && $0.value.contains("requested entrypoint browser.open converged to preferred builtin guarded-automation")
        }))
    }

    @Test
    func builtinGovernedSkillsMapsBuiltinLifecycleAndDiagnosticsAction() {
        let presentation = SupervisorAuditDrillDownPresentation.xtBuiltinGovernedSkills(
            items: [
                AXBuiltinGovernedSkillSummary(
                    skillID: "guarded-automation",
                    displayName: "Guarded Automation",
                    summary: "Inspect trusted automation readiness.",
                    capabilitiesRequired: ["project.snapshot", "browser.read", "device.browser.control"],
                    sideEffectClass: "external_side_effect",
                    riskLevel: "high",
                    policyScope: "xt_builtin"
                ),
                AXBuiltinGovernedSkillSummary(
                    skillID: "supervisor-voice",
                    displayName: "Supervisor Voice",
                    summary: "Inspect and control local playback.",
                    capabilitiesRequired: ["supervisor.voice.playback"],
                    sideEffectClass: "local_side_effect",
                    riskLevel: "low",
                    policyScope: "xt_builtin"
                )
            ],
            managedStatusLine: "skills ok"
        )

        #expect(presentation.title == "XT 内建受治理技能")
        #expect(presentation.statusLabel == "内建")
        #expect(presentation.tone == .success)
        #expect(presentation.summary.contains("已登记 2 个 XT 本地受治理技能"))
        #expect(presentation.detail.contains("托管技能：skills ok"))
        #expect(presentation.actionLabel == "打开诊断")
        #expect(presentation.actionURL?.contains("settings") == true)
        #expect(presentation.actionURL?.contains("section_id=diagnostics") == true)
        #expect(presentation.sections.count == 3)
        #expect(presentation.sections[0].fields.contains(where: {
            $0.label == "生命周期" && $0.value.contains("不能通过 Hub 安装或移除")
        }))
        #expect(presentation.sections[1].fields.contains(where: {
            $0.label == "Guarded Automation" && $0.value.contains("风险=high")
        }))
        #expect(presentation.sections[1].fields.contains(where: {
            $0.label == "Supervisor Voice" && $0.value.contains("风险=low")
        }))
    }

    @Test
    func eventLoopMapsRequestScopedFollowUpAndEmbeddedRecordHint() {
        let activity = SupervisorManager.SupervisorEventLoopActivity(
            id: "evt-1",
            createdAt: 10,
            updatedAt: 20,
            triggerSource: "grant_resolution",
            status: "queued",
            reasonCode: "grant_pending",
            dedupeKey: "grant_resolution:req-42:grant_approved",
            projectId: "project-alpha",
            projectName: "Project Alpha",
            triggerSummary: "grant approved",
            resultSummary: "rerun supervisor skill",
            policySummary: "policy=retry_once"
        )
        let recent = SupervisorManager.SupervisorRecentSkillActivity(
            projectId: "project-alpha",
            projectName: "Project Alpha",
            record: SupervisorSkillCallRecord(
                schemaVersion: SupervisorSkillCallRecord.currentSchemaVersion,
                requestId: "req-42",
                projectId: "project-alpha",
                jobId: "job-1",
                planId: "plan-1",
                stepId: "step-1",
                skillId: "guarded-automation",
                requestedSkillId: "browser.open",
                toolName: ToolName.deviceBrowserControl.rawValue,
                status: .completed,
                payload: ["action": .string("open")],
                currentOwner: "supervisor",
                resultSummary: "completed browser task",
                denyCode: "",
                resultEvidenceRef: "evidence-1",
                requiredCapability: nil,
                grantRequestId: "grant-1",
                grantId: "grant-live-1",
                createdAtMs: 1_000,
                updatedAtMs: 2_000,
                auditRef: "audit-1"
            ),
            tool: .deviceBrowserControl,
            toolCall: nil,
            toolSummary: "open project dashboard",
            actionURL: "x-terminal://project/project-alpha?focus=skill_record&request_id=req-42",
            governance: nil
        )
        let fullRecord = SupervisorSkillFullRecord(
            requestID: "req-42",
            projectName: "Project Alpha",
            title: "Supervisor skill completed",
            latestStatus: "completed",
            latestStatusLabel: "Completed",
            requestMetadata: [],
            approvalFields: [],
            governanceFields: [],
            skillPayloadText: nil,
            toolArgumentsText: nil,
            resultFields: [],
            rawOutputPreview: nil,
            rawOutput: nil,
            evidenceFields: [],
            approvalHistory: [],
            timeline: [],
            supervisorEvidenceJSON: nil
        )

        let presentation = SupervisorAuditDrillDownPresentation.eventLoopActivity(
            activity,
            relatedSkillActivity: recent,
            fullRecord: fullRecord
        )

        #expect(presentation.title == "授权处理")
        #expect(presentation.statusLabel == "排队中")
        #expect(presentation.tone == .attention)
        #expect(presentation.requestId == "req-42")
        #expect(presentation.actionLabel == "打开记录")
        #expect(presentation.actionURL?.contains("focus=skill_record") == true)
        #expect(presentation.includesEmbeddedSkillRecord)
        #expect(presentation.sections[1].fields.contains(where: {
            $0.label == "关联技能" && $0.value.contains("browser.open -> guarded-automation")
        }))
    }

    @Test
    func fullRecordFallbackPreservesUnifiedAuditSurfaceWithoutRecentActivity() {
        let record = SupervisorSkillFullRecord(
            requestID: "req-fallback-1",
            projectName: "Project Gamma",
            title: "Supervisor skill completed",
            latestStatus: "completed",
            latestStatusLabel: "Completed",
            requestMetadata: [
                ProjectSkillRecordField(label: "Skill", value: "summarize")
            ],
            approvalFields: [],
            governanceFields: [],
            skillPayloadText: nil,
            toolArgumentsText: nil,
            resultFields: [
                ProjectSkillRecordField(label: "Result", value: "summary delivered")
            ],
            rawOutputPreview: nil,
            rawOutput: nil,
            evidenceFields: [],
            approvalHistory: [],
            timeline: [],
            supervisorEvidenceJSON: nil
        )

        let presentation = SupervisorAuditDrillDownPresentation.fullRecordFallback(
            projectId: "project-gamma",
            projectName: "Project Gamma",
            record: record
        )

        #expect(presentation.title == "Supervisor skill completed")
        #expect(presentation.statusLabel == "Completed")
        #expect(presentation.tone == .success)
        #expect(presentation.requestId == "req-fallback-1")
        #expect(presentation.includesEmbeddedSkillRecord)
        #expect(presentation.summary == "summary delivered")
        #expect(presentation.sections.count == 1)
        #expect(presentation.sections[0].fields.contains(where: {
            $0.label == "项目 ID" && $0.value == "project-gamma"
        }))
    }

    @Test
    func recentSkillActivityShowsRequestedWrapperAndBuiltin路由() {
        let item = SupervisorManager.SupervisorRecentSkillActivity(
            projectId: "project-alpha",
            projectName: "Project Alpha",
            record: SupervisorSkillCallRecord(
                schemaVersion: SupervisorSkillCallRecord.currentSchemaVersion,
                requestId: "req-routing-1",
                projectId: "project-alpha",
                jobId: "job-2",
                planId: "plan-2",
                stepId: "step-2",
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
                resultEvidenceRef: "evidence-routing-1",
                requiredCapability: nil,
                grantRequestId: nil,
                grantId: nil,
                createdAtMs: 1_000,
                updatedAtMs: 2_000,
                auditRef: "audit-routing-1"
            ),
            tool: .deviceBrowserControl,
            toolCall: ToolCall(
                id: "req-routing-1",
                tool: .deviceBrowserControl,
                args: [
                    "action": .string("open_url"),
                    "url": .string("https://example.com/login")
                ]
            ),
            toolSummary: "https://example.com/login",
            actionURL: "x-terminal://project/project-alpha?focus=skill_record&request_id=req-routing-1",
            governance: nil
        )

        let presentation = SupervisorAuditDrillDownPresentation.recentSkillActivity(
            item,
            fullRecord: nil
        )

        #expect(presentation.sections[0].fields.contains(where: {
            $0.label == "请求技能" && $0.value == "browser.open"
        }))
        #expect(presentation.sections[0].fields.contains(where: {
            $0.label == "生效技能" && $0.value == "guarded-automation"
        }))
        #expect(!presentation.sections[0].fields.contains(where: { $0.label == "技能" }))
        #expect(presentation.sections[2].fields.contains(where: {
            $0.label == "路由" && $0.value.contains("browser.open -> guarded-automation")
        }))
        #expect(presentation.sections[2].fields.contains(where: {
            $0.label == "路由判定" && $0.value == "系统优先切到受治理内建"
        }))
        #expect(presentation.sections[2].fields.contains(where: {
            $0.label == "路由代码" && $0.value == "preferred_builtin_selected"
        }))
        #expect(presentation.sections[2].fields.contains(where: {
            $0.label == "路由说明" && $0.value.contains("浏览器入口会先收敛到受治理内建 guarded-automation 再执行")
        }))
        #expect(presentation.sections[2].fields.contains(where: {
            $0.label == "路由解释" && $0.value.contains("requested entrypoint browser.open converged to preferred builtin guarded-automation")
        }))
    }

    @Test
    func recentSkillActivityGovernanceSectionIncludesStructuredGuidanceContract() throws {
        let item = SupervisorManager.SupervisorRecentSkillActivity(
            projectId: "project-alpha",
            projectName: "Project Alpha",
            record: SupervisorSkillCallRecord(
                schemaVersion: SupervisorSkillCallRecord.currentSchemaVersion,
                requestId: "req-governance-1",
                projectId: "project-alpha",
                jobId: "job-3",
                planId: "plan-3",
                stepId: "step-3",
                skillId: "find-skills",
                requestedSkillId: "find-skills",
                toolName: ToolName.skills_search.rawValue,
                status: .blocked,
                payload: [:],
                currentOwner: "supervisor",
                resultSummary: "Blocked on hub grant approval",
                denyCode: "",
                resultEvidenceRef: "evidence-governance-1",
                requiredCapability: nil,
                grantRequestId: nil,
                grantId: nil,
                createdAtMs: 1_000,
                updatedAtMs: 2_000,
                auditRef: "audit-governance-1"
            ),
            tool: .skills_search,
            toolCall: nil,
            toolSummary: "search official skills catalog",
            actionURL: nil,
            governance: nil
        )
        let fullRecord = SupervisorSkillFullRecord(
            requestID: "req-governance-1",
            projectName: "Project Alpha",
            title: "Supervisor skill blocked",
            latestStatus: "blocked",
            latestStatusLabel: "Blocked",
            requestMetadata: [],
            approvalFields: [],
            governanceFields: [],
            skillPayloadText: nil,
            toolArgumentsText: nil,
            resultFields: [],
            rawOutputPreview: nil,
            rawOutput: nil,
            evidenceFields: [],
            approvalHistory: [],
            timeline: [],
            supervisorEvidenceJSON: nil,
            guidanceContract: SupervisorGuidanceContractSummary(
                kind: .grantResolution,
                trigger: "Grant Resolution",
                reviewLevel: "R2 Strategic",
                verdict: "Watch",
                summary: "Hub grant must be approved before the skill can continue.",
                primaryBlocker: "Hub grant pending",
                currentState: "skill blocked",
                nextStep: "approve the grant",
                nextSafeAction: "open_hub_grants",
                recommendedActions: ["Approve the pending hub grant", "Retry the blocked skill"],
                workOrderRef: "plan:grant-resolution-1",
                effectiveSupervisorTier: "S3 Strategic Coach",
                effectiveWorkOrderDepth: "Execution Ready"
            )
        )

        let presentation = SupervisorAuditDrillDownPresentation.recentSkillActivity(
            item,
            fullRecord: fullRecord
        )

        let governanceSection = try #require(presentation.sections.first(where: { $0.title == "治理" }))
        #expect(governanceSection.fields.contains(where: {
            $0.label == "指导合同" && $0.value == "授权处理"
        }))
        #expect(governanceSection.fields.contains(where: {
            $0.label == "主要阻塞" && $0.value == "Hub grant pending"
        }))
        #expect(governanceSection.fields.contains(where: {
            $0.label == "安全下一步" && $0.value == "open_hub_grants"
        }))
        #expect(governanceSection.fields.contains(where: {
            $0.label == "建议动作" && $0.value.contains("Approve the pending hub grant")
        }))
    }

    @Test
    func recentSkillActivityDrillDownSurfacesCompactUIReviewEvidenceSection() {
        let item = SupervisorManager.SupervisorRecentSkillActivity(
            projectId: "project-alpha",
            projectName: "Project Alpha",
            record: SupervisorSkillCallRecord(
                schemaVersion: SupervisorSkillCallRecord.currentSchemaVersion,
                requestId: "req-ui-review-1",
                projectId: "project-alpha",
                jobId: "job-ui-1",
                planId: "plan-ui-1",
                stepId: "step-ui-1",
                skillId: "agent-browser",
                toolName: ToolName.deviceBrowserControl.rawValue,
                status: .completed,
                payload: [:],
                currentOwner: "supervisor",
                resultSummary: "Snapshot completed",
                denyCode: "",
                resultEvidenceRef: "local://supervisor_skill_results/req-ui-review-1.json",
                requiredCapability: nil,
                grantRequestId: nil,
                grantId: nil,
                createdAtMs: 1_000,
                updatedAtMs: 2_000,
                auditRef: "audit-ui-review-1"
            ),
            tool: .deviceBrowserControl,
            toolCall: nil,
            toolSummary: "browser snapshot",
            actionURL: nil,
            governance: nil
        )
        let fullRecord = SupervisorSkillFullRecord(
            requestID: "req-ui-review-1",
            projectName: "Project Alpha",
            title: "Supervisor skill completed",
            latestStatus: "completed",
            latestStatusLabel: "Completed",
            requestMetadata: [],
            approvalFields: [],
            governanceFields: [],
            skillPayloadText: nil,
            toolArgumentsText: nil,
            resultFields: [],
            rawOutputPreview: nil,
            rawOutput: nil,
            evidenceFields: [],
            approvalHistory: [],
            timeline: [],
            uiReviewAgentEvidenceFields: [
                ProjectSkillRecordField(label: "summary", value: "Primary CTA visible and ready."),
                ProjectSkillRecordField(label: "verdict", value: "ready"),
                ProjectSkillRecordField(label: "confidence", value: "high"),
                ProjectSkillRecordField(label: "objective_ready", value: "true"),
                ProjectSkillRecordField(label: "issue_codes", value: "critical_action_visible"),
                ProjectSkillRecordField(
                    label: "ui_review_agent_evidence_ref",
                    value: "local://.xterminal/ui_review/agent_evidence/review-ui-1.json"
                )
            ],
            uiReviewAgentEvidenceText: "verdict=ready",
            supervisorEvidenceJSON: nil
        )

        let presentation = SupervisorAuditDrillDownPresentation.recentSkillActivity(
            item,
            fullRecord: fullRecord
        )

        guard let uiReviewSection = presentation.sections.first(where: { $0.title == "UI 审查证据" }) else {
            Issue.record("Expected UI 审查证据 section in recent skill activity drill-down")
            return
        }
        #expect(uiReviewSection.fields.contains(where: {
            $0.label == "结论" && $0.value == "ready"
        }))
        #expect(uiReviewSection.fields.contains(where: {
            $0.label == "证据引用" && $0.value.contains("agent_evidence")
        }))
        #expect(!uiReviewSection.fields.contains(where: {
            $0.label == "建议修复" && !$0.value.isEmpty
        }))
    }

    @Test
    func recentSkillActivityUnsafeUIReviewPromotesOpenUIReviewAction() {
        let item = SupervisorManager.SupervisorRecentSkillActivity(
            projectId: "project-alpha",
            projectName: "Project Alpha",
            record: SupervisorSkillCallRecord(
                schemaVersion: SupervisorSkillCallRecord.currentSchemaVersion,
                requestId: "req-ui-review-unsafe-1",
                projectId: "project-alpha",
                jobId: "job-ui-unsafe-1",
                planId: "plan-ui-unsafe-1",
                stepId: "step-ui-unsafe-1",
                skillId: "agent-browser",
                toolName: ToolName.deviceBrowserControl.rawValue,
                status: .completed,
                payload: [:],
                currentOwner: "supervisor",
                resultSummary: "Snapshot completed",
                denyCode: "",
                resultEvidenceRef: "local://supervisor_skill_results/req-ui-review-unsafe-1.json",
                requiredCapability: nil,
                grantRequestId: nil,
                grantId: nil,
                createdAtMs: 1_000,
                updatedAtMs: 2_000,
                auditRef: "audit-ui-review-unsafe-1"
            ),
            tool: .deviceBrowserControl,
            toolCall: nil,
            toolSummary: "browser snapshot",
            actionURL: XTDeepLinkURLBuilder.projectURL(
                projectId: "project-alpha",
                pane: .chat
            )?.absoluteString,
            governance: nil
        )
        let fullRecord = SupervisorSkillFullRecord(
            requestID: "req-ui-review-unsafe-1",
            projectName: "Project Alpha",
            title: "Supervisor skill completed",
            latestStatus: "completed",
            latestStatusLabel: "Completed",
            requestMetadata: [],
            approvalFields: [],
            governanceFields: [],
            skillPayloadText: nil,
            toolArgumentsText: nil,
            resultFields: [],
            rawOutputPreview: nil,
            rawOutput: nil,
            evidenceFields: [],
            approvalHistory: [],
            timeline: [],
            uiReviewAgentEvidenceFields: [
                ProjectSkillRecordField(label: "summary", value: "Primary CTA missing."),
                ProjectSkillRecordField(label: "verdict", value: "attention_needed"),
                ProjectSkillRecordField(label: "confidence", value: "high"),
                ProjectSkillRecordField(label: "sufficient_evidence", value: "true"),
                ProjectSkillRecordField(label: "objective_ready", value: "false"),
                ProjectSkillRecordField(label: "issue_codes", value: "critical_action_not_visible"),
                ProjectSkillRecordField(
                    label: "ui_review_agent_evidence_ref",
                    value: "local://.xterminal/ui_review/agent_evidence/review-ui-unsafe-1.json"
                )
            ],
            uiReviewAgentEvidenceText: "trend:\n- status=regressed",
            supervisorEvidenceJSON: nil
        )

        let presentation = SupervisorAuditDrillDownPresentation.recentSkillActivity(
            item,
            fullRecord: fullRecord
        )

        #expect(presentation.actionLabel == "打开 UI 审查")
        #expect(presentation.actionURL?.contains("governance_destination=ui_review") == true)
        #expect(presentation.secondaryActions.map(\.label) == ["打开项目"])
        guard let uiReviewSection = presentation.sections.first(where: { $0.title == "UI 审查证据" }) else {
            Issue.record("Expected UI 审查证据 section in recent skill activity unsafe drill-down")
            return
        }
        #expect(uiReviewSection.fields.contains(where: {
            $0.label == "建议修复" &&
            $0.value == "Repair primary CTA visibility before continuing browser automation."
        }))
    }

    @Test
    func eventLoopUnsafeUIReviewPrefersOpenUIReviewAndKeepsRecordShortcut() {
        let activity = SupervisorManager.SupervisorEventLoopActivity(
            id: "evt-ui-review-1",
            createdAt: 10,
            updatedAt: 20,
            triggerSource: "skill_callback",
            status: "queued",
            reasonCode: "ui_review_attention",
            dedupeKey: "skill_callback:req-ui-review-2:completed",
            projectId: "project-alpha",
            projectName: "Project Alpha",
            triggerSummary: "skill callback completed",
            resultSummary: "follow up required",
            policySummary: "policy=retry_once"
        )
        let fullRecord = SupervisorSkillFullRecord(
            requestID: "req-ui-review-2",
            projectName: "Project Alpha",
            title: "Supervisor skill completed",
            latestStatus: "completed",
            latestStatusLabel: "Completed",
            requestMetadata: [],
            approvalFields: [],
            governanceFields: [],
            skillPayloadText: nil,
            toolArgumentsText: nil,
            resultFields: [],
            rawOutputPreview: nil,
            rawOutput: nil,
            evidenceFields: [],
            approvalHistory: [],
            timeline: [],
            uiReviewAgentEvidenceFields: [
                ProjectSkillRecordField(label: "summary", value: "Primary CTA hidden."),
                ProjectSkillRecordField(label: "verdict", value: "attention_needed"),
                ProjectSkillRecordField(label: "confidence", value: "high"),
                ProjectSkillRecordField(label: "sufficient_evidence", value: "true"),
                ProjectSkillRecordField(label: "objective_ready", value: "false"),
                ProjectSkillRecordField(label: "issue_codes", value: "interactive_target_missing")
            ],
            uiReviewAgentEvidenceText: nil,
            supervisorEvidenceJSON: nil
        )

        let presentation = SupervisorAuditDrillDownPresentation.eventLoopActivity(
            activity,
            relatedSkillActivity: nil,
            fullRecord: fullRecord
        )

        #expect(presentation.actionLabel == "打开 UI 审查")
        #expect(presentation.actionURL?.contains("governance_destination=ui_review") == true)
        #expect(presentation.secondaryActions.map(\.label).contains("打开记录"))
        guard let uiReviewSection = presentation.sections.first(where: { $0.title == "UI 审查证据" }) else {
            Issue.record("Expected UI 审查证据 section in event loop unsafe drill-down")
            return
        }
        #expect(uiReviewSection.fields.contains(where: {
            $0.label == "建议修复" &&
            $0.value == "Expose the missing interactive target before continuing browser automation."
        }))
    }

    @Test
    func fullRecordFallbackUnsafeUIReviewExposesOpenUIReviewAction() {
        let record = SupervisorSkillFullRecord(
            requestID: "req-fallback-ui-review-1",
            projectName: "Project Gamma",
            title: "Supervisor skill completed",
            latestStatus: "completed",
            latestStatusLabel: "Completed",
            requestMetadata: [],
            approvalFields: [],
            governanceFields: [],
            skillPayloadText: nil,
            toolArgumentsText: nil,
            resultFields: [
                ProjectSkillRecordField(label: "Result", value: "summary delivered")
            ],
            rawOutputPreview: nil,
            rawOutput: nil,
            evidenceFields: [],
            approvalHistory: [],
            timeline: [],
            uiReviewAgentEvidenceFields: [
                ProjectSkillRecordField(label: "summary", value: "Critical CTA missing."),
                ProjectSkillRecordField(label: "verdict", value: "attention_needed"),
                ProjectSkillRecordField(label: "confidence", value: "medium"),
                ProjectSkillRecordField(label: "sufficient_evidence", value: "true"),
                ProjectSkillRecordField(label: "objective_ready", value: "false"),
                ProjectSkillRecordField(label: "issue_codes", value: "critical_action_not_visible")
            ],
            uiReviewAgentEvidenceText: nil,
            supervisorEvidenceJSON: nil
        )

        let presentation = SupervisorAuditDrillDownPresentation.fullRecordFallback(
            projectId: "project-gamma",
            projectName: "Project Gamma",
            record: record
        )

        #expect(presentation.actionLabel == "打开 UI 审查")
        #expect(presentation.actionURL?.contains("project_id=project-gamma") == true)
        #expect(presentation.actionURL?.contains("governance_destination=ui_review") == true)
    }
}
