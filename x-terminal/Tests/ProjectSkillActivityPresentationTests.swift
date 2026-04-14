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
    func parseRecentActivitiesPreservesPersistedGovernanceEvidence() throws {
        let raw = """
        {"type":"project_skill_call","created_at":2.0,"status":"blocked","request_id":"skill-persisted-item","skill_id":"agent-browser","tool_name":"device.browser.control","tool_args":{"action":"open_url"},"deny_code":"governance_capability_denied","authorization_disposition":"deny","policy_source":"project_governance","policy_reason":"execution_tier_missing_browser_runtime","governance_reason":"persisted governance reason","blocked_summary":"persisted blocked summary","governance_truth":"persisted governance truth","repair_action":"persisted repair action"}
        """

        let item = try #require(
            ProjectSkillActivityPresentation.parseRecentActivities(from: raw, limit: 1).first
        )

        #expect(ProjectSkillActivityPresentation.governanceReason(for: item) == "persisted governance reason")
        #expect(ProjectSkillActivityPresentation.blockedSummary(for: item) == "persisted blocked summary")
        #expect(ProjectSkillActivityPresentation.governanceTruthLine(for: item) == "persisted governance truth")
        #expect(ProjectSkillActivityPresentation.repairActionSummary(for: item) == "persisted repair action")
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
    func blockedGrantRequiredBodyUsesHubAuthorizationGuidance() {
        let item = ProjectSkillActivityItem(
            requestID: "skill-grant-1",
            skillID: "tavily-websearch",
            toolName: ToolName.web_search.rawValue,
            status: "blocked",
            createdAt: 2.5,
            resolutionSource: "",
            toolArgs: [
                "query": .string("OpenAI GPT-5.4 release notes")
            ],
            requiredCapability: "web.fetch",
            resultSummary: "",
            detail: "",
            denyCode: "grant_required",
            authorizationDisposition: "deny"
        )

        let body = ProjectSkillActivityPresentation.body(for: item)

        #expect(body.contains("联网访问"))
        #expect(body.contains("Hub 授权"))
        #expect(body.contains("先在 Hub 或 Supervisor 里批准授权，再重试。"))
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
        #expect(diagnostics.contains("repair_action=打开 A-Tier：") == true)
        #expect(diagnostics.contains("tool_args="))
    }

    @Test
    func awaitingApprovalDiagnosticsIncludeRoutingReadinessAndDeltaFields() {
        let item = ProjectSkillActivityItem(
            requestID: "skill-awaiting-delta-1",
            skillID: "guarded-automation",
            requestedSkillID: "browser.open",
            intentFamilies: [],
            capabilityFamilies: [],
            capabilityProfiles: [],
            requiredRuntimeSurfaces: ["managed_browser_runtime"],
            unblockActions: ["request_local_approval"],
            toolName: ToolName.deviceBrowserControl.rawValue,
            status: "awaiting_approval",
            createdAt: 4.5,
            resolutionSource: "primary",
            toolArgs: [
                "action": .string("open_url"),
                "url": .string("https://example.com/dashboard")
            ],
            routingReasonCode: "preferred_builtin_selected",
            routingExplanation: "requested entrypoint browser.open converged to guarded-automation",
            executionReadiness: XTSkillExecutionReadinessState.localApprovalRequired.rawValue,
            approvalSummary: "新增放开：browser_operator",
            currentRunnableProfiles: ["observe_only"],
            requestedProfiles: ["observe_only", "browser_operator"],
            deltaProfiles: ["browser_operator"],
            currentRunnableCapabilityFamilies: ["repo.read"],
            requestedCapabilityFamilies: ["repo.read", "browser.interact"],
            deltaCapabilityFamilies: ["browser.interact"],
            grantFloor: XTSkillGrantFloor.privileged.rawValue,
            approvalFloor: XTSkillApprovalFloor.localApproval.rawValue,
            resultSummary: "",
            detail: "",
            denyCode: "",
            authorizationDisposition: ""
        )

        let diagnostics = ProjectSkillActivityPresentation.diagnostics(for: item)
        let body = ProjectSkillActivityPresentation.body(for: item)

        #expect(diagnostics.contains("requested_skill_id=browser.open"))
        #expect(diagnostics.contains("routing_reason_code=preferred_builtin_selected"))
        #expect(diagnostics.contains("routing_explanation=requested entrypoint browser.open converged to guarded-automation"))
        #expect(diagnostics.contains("execution_readiness=local_approval_required"))
        #expect(diagnostics.contains("required_runtime_surfaces=managed_browser_runtime"))
        #expect(diagnostics.contains("unblock_actions=request_local_approval"))
        #expect(diagnostics.contains("current_runnable_capability_families=repo.read"))
        #expect(diagnostics.contains("requested_capability_families=repo.read,browser.interact"))
        #expect(diagnostics.contains("delta_capability_families=browser.interact"))
        #expect(diagnostics.contains("approval_floor=local_approval"))
        #expect(body.contains("新增放开：browser_operator"))
        #expect(body.contains("这次审批通过后，会按当前受治理路径继续执行。"))
    }

    @Test
    func cardGovernedDetailLinesPrioritizeReadinessAndActionableBlockers() {
        let item = ProjectSkillActivityItem(
            requestID: "skill-card-governed-1",
            skillID: "guarded-automation",
            requestedSkillID: "browser.open",
            requiredRuntimeSurfaces: ["managed_browser_runtime"],
            unblockActions: ["request_local_approval"],
            toolName: ToolName.deviceBrowserControl.rawValue,
            status: "awaiting_approval",
            createdAt: 4.6,
            resolutionSource: "primary",
            toolArgs: [
                "url": .string("https://example.com/dashboard")
            ],
            executionReadiness: XTSkillExecutionReadinessState.localApprovalRequired.rawValue,
            approvalSummary: "新增放开：browser_operator",
            grantFloor: XTSkillGrantFloor.privileged.rawValue,
            approvalFloor: XTSkillApprovalFloor.localApproval.rawValue,
            resultSummary: "",
            detail: "",
            denyCode: "",
            authorizationDisposition: ""
        )

        let lines = ProjectSkillActivityPresentation.cardGovernedDetailLines(for: item)

        #expect(lines == [
            "执行就绪：等待本地审批",
            "运行面：受治理浏览器运行面（managed_browser_runtime）；解阻动作：请求本地审批（request_local_approval）"
        ])
    }

    @Test
    func awaitingApprovalStatusCopyUsesGovernedReadinessBeforeCapabilityFallback() {
        let hubGrantItem = ProjectSkillActivityItem(
            requestID: "skill-awaiting-grant-1",
            skillID: "tavily-websearch",
            toolName: ToolName.web_search.rawValue,
            status: "awaiting_approval",
            createdAt: 4.8,
            resolutionSource: "primary",
            toolArgs: [
                "query": .string("governed skills")
            ],
            executionReadiness: XTSkillExecutionReadinessState.grantRequired.rawValue,
            resultSummary: "",
            detail: "",
            denyCode: "",
            authorizationDisposition: ""
        )
        let localApprovalItem = ProjectSkillActivityItem(
            requestID: "skill-awaiting-local-1",
            skillID: "guarded-automation",
            toolName: ToolName.deviceBrowserControl.rawValue,
            status: "awaiting_approval",
            createdAt: 4.9,
            resolutionSource: "primary",
            toolArgs: [
                "url": .string("https://example.com")
            ],
            executionReadiness: XTSkillExecutionReadinessState.localApprovalRequired.rawValue,
            resultSummary: "",
            detail: "",
            denyCode: "",
            authorizationDisposition: ""
        )

        #expect(ProjectSkillActivityPresentation.title(for: hubGrantItem) == "等待 Hub 授权")
        #expect(ProjectSkillActivityPresentation.statusLabel(for: hubGrantItem) == "待授权")
        #expect(ProjectSkillActivityPresentation.iconName(for: hubGrantItem) == "lock.shield.fill")

        #expect(ProjectSkillActivityPresentation.title(for: localApprovalItem) == "等待本地审批")
        #expect(ProjectSkillActivityPresentation.statusLabel(for: localApprovalItem) == "待审批")
        #expect(ProjectSkillActivityPresentation.iconName(for: localApprovalItem) == "hand.raised.fill")
    }

    @Test
    func awaitingApprovalBodyUsesGovernedReadinessBeforeCapabilityFallback() {
        let hubGrantItem = ProjectSkillActivityItem(
            requestID: "skill-awaiting-grant-body-1",
            skillID: "tavily-websearch",
            toolName: ToolName.web_search.rawValue,
            status: "awaiting_approval",
            createdAt: 4.81,
            resolutionSource: "primary",
            toolArgs: [
                "query": .string("governed skill chain")
            ],
            executionReadiness: XTSkillExecutionReadinessState.grantRequired.rawValue,
            resultSummary: "",
            detail: "",
            denyCode: "",
            authorizationDisposition: ""
        )
        let localApprovalItem = ProjectSkillActivityItem(
            requestID: "skill-awaiting-local-body-1",
            skillID: "guarded-automation",
            toolName: ToolName.deviceBrowserControl.rawValue,
            status: "awaiting_approval",
            createdAt: 4.82,
            resolutionSource: "primary",
            toolArgs: [
                "url": .string("https://example.com/admin")
            ],
            executionReadiness: XTSkillExecutionReadinessState.localApprovalRequired.rawValue,
            requiredCapability: "browser.interact",
            resultSummary: "",
            detail: "",
            denyCode: "",
            authorizationDisposition: ""
        )

        let hubGrantBody = ProjectSkillActivityPresentation.body(for: hubGrantItem)
        let localApprovalBody = ProjectSkillActivityPresentation.body(for: localApprovalItem)

        #expect(hubGrantBody.contains("Hub 授权"))
        #expect(hubGrantBody.contains("本地审批") == false)
        #expect(hubGrantBody.contains("先完成 Hub grant，再恢复这次受治理技能调用。"))
        #expect(localApprovalBody.contains("本地审批"))
        #expect(localApprovalBody.contains("Hub 授权") == false)
        #expect(localApprovalBody.contains("这次审批通过后，会按当前受治理路径继续执行。"))
    }

    @Test
    func resolvedBodyUsesGovernedRouteSummary() {
        let item = ProjectSkillActivityItem(
            requestID: "skill-route-1",
            skillID: "guarded-automation",
            requestedSkillID: "browser.open",
            toolName: ToolName.deviceBrowserControl.rawValue,
            status: "resolved",
            createdAt: 4.95,
            resolutionSource: "primary",
            toolArgs: [
                "url": .string("https://example.com/dashboard")
            ],
            routingReasonCode: "preferred_builtin_selected",
            routingExplanation: "requested entrypoint browser.open converged to preferred builtin guarded-automation",
            resultSummary: "",
            detail: "",
            denyCode: "",
            authorizationDisposition: ""
        )

        let body = ProjectSkillActivityPresentation.body(for: item)

        #expect(ProjectSkillActivityPresentation.skillBadgeText(for: item) == "browser.open -> guarded-automation")
        #expect(body.contains("技能 browser.open -> guarded-automation 已路由到浏览器控制") == true)
        #expect(body.contains("https://example.com/dashboard") == true)
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
            resultSummary: "project governance blocks device.browser.control under A-Tier a0_observe",
            detail: "project governance blocks device.browser.control under A-Tier a0_observe",
            denyCode: "governance_capability_denied",
            authorizationDisposition: "deny",
            policySource: "project_governance",
            policyReason: "execution_tier_missing_browser_runtime"
        )

        let body = ProjectSkillActivityPresentation.body(for: item)

        #expect(body.contains("不允许浏览器自动化"))
        #expect(body.contains("打开项目设置 -> A-Tier"))
        #expect(body.contains("A4 Agent"))
    }

    @Test
    func blockedGovernanceBodyPrefixesGovernanceTruthWhenPresent() {
        let item = ProjectSkillActivityItem(
            requestID: "skill-3c",
            skillID: "agent-browser",
            toolName: ToolName.deviceBrowserControl.rawValue,
            status: "blocked",
            createdAt: 4.0,
            resolutionSource: "primary",
            toolArgs: ["action": .string("open_url")],
            resultSummary: "",
            detail: "",
            denyCode: "governance_capability_denied",
            authorizationDisposition: "deny",
            policySource: "project_governance",
            policyReason: "execution_tier_missing_browser_runtime",
            governanceTruth: "治理真相：当前生效 A1/S2 · 审查 Periodic。"
        )

        let body = ProjectSkillActivityPresentation.body(for: item)

        #expect(body.contains("治理真相：当前生效 A1/S2 · 审查 周期。") == true)
        #expect(body.contains("当前项目 A-Tier 不允许浏览器自动化。") == true)
    }

    @Test
    func blockedGovernanceTimelineBodyExcludesGovernanceTruthPrefix() {
        let item = ProjectSkillActivityItem(
            requestID: "skill-3c-timeline",
            skillID: "agent-browser",
            toolName: ToolName.deviceBrowserControl.rawValue,
            status: "blocked",
            createdAt: 4.0,
            resolutionSource: "primary",
            toolArgs: ["action": .string("open_url")],
            resultSummary: "",
            detail: "",
            denyCode: "governance_capability_denied",
            authorizationDisposition: "deny",
            policySource: "project_governance",
            policyReason: "execution_tier_missing_browser_runtime",
            governanceTruth: "治理真相：当前生效 A1/S2 · 审查 Periodic。"
        )

        let body = ProjectSkillActivityPresentation.timelineBody(for: item)

        #expect(body.contains("治理真相：") == false)
        #expect(body.contains("当前项目 A-Tier 不允许浏览器自动化。") == true)
    }

    @Test
    func blockedActivityDiagnosticsIncludeGovernanceFields() {
        let item = ProjectSkillActivityItem(
            requestID: "skill-3d",
            skillID: "agent-browser",
            toolName: ToolName.deviceBrowserControl.rawValue,
            status: "blocked",
            createdAt: 4.0,
            resolutionSource: "primary",
            toolArgs: ["action": .string("open_url")],
            resultSummary: "",
            detail: "",
            denyCode: "governance_capability_denied",
            authorizationDisposition: "deny",
            policySource: "project_governance",
            policyReason: "execution_tier_missing_browser_runtime",
            governanceTruth: "治理真相：当前生效 A1/S2 · 审查 Periodic。"
        )

        let diagnostics = ProjectSkillActivityPresentation.diagnostics(for: item)

        #expect(diagnostics.contains("blocked_summary=当前项目 A-Tier 不允许浏览器自动化。 打开项目设置 -> A-Tier，把档位提升到 A4 Agent 或更高后，再使用浏览器自动化。") == true)
        #expect(diagnostics.contains("governance_reason=当前项目 A-Tier 不允许浏览器自动化。") == true)
        #expect(diagnostics.contains("governance_truth=治理真相：当前生效 A1/S2 · 审查 Periodic。") == true)
        #expect(diagnostics.contains("repair_action=打开 A-Tier：") == true)
    }

    @Test
    func blockedSummaryUsesHumanGovernanceRepairCopy() {
        let item = ProjectSkillActivityItem(
            requestID: "skill-3e",
            skillID: "agent-browser",
            toolName: ToolName.deviceBrowserControl.rawValue,
            status: "blocked",
            createdAt: 4.0,
            resolutionSource: "primary",
            toolArgs: ["action": .string("open_url")],
            resultSummary: "",
            detail: "",
            denyCode: "governance_capability_denied",
            authorizationDisposition: "deny",
            policySource: "project_governance",
            policyReason: "execution_tier_missing_browser_runtime",
            governanceTruth: "治理真相：当前生效 A1/S2 · 审查 Periodic。"
        )

        let blockedSummary = ProjectSkillActivityPresentation.blockedSummary(for: item)
        let policyReason = ProjectSkillActivityPresentation.policyReason(for: item)

        #expect(blockedSummary?.contains("当前项目 A-Tier 不允许浏览器自动化。") == true)
        #expect(blockedSummary?.contains("打开项目设置 -> A-Tier") == true)
        #expect(policyReason == "execution_tier_missing_browser_runtime")
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
        #expect(record.approvalFields.contains(where: { $0.label == "required_capability" && $0.value == "device.browser.control" }))
        #expect(record.approvalFields.contains(where: { $0.label == "grant_request_id" && $0.value == "grant-123" }))
        #expect(record.governanceFields.contains(where: { $0.label == "policy_source" && $0.value == "project_governance" }))
        #expect(record.governanceFields.contains(where: { $0.label == "policy_reason" && $0.value == "execution_tier_missing_browser_runtime" }))
        #expect(record.governanceFields.contains(where: { $0.label == "governance_reason" && $0.value.contains("不允许浏览器自动化") }))
        #expect(record.governanceFields.contains(where: { $0.label == "blocked_summary" && $0.value.contains("不允许浏览器自动化") }))
        #expect(record.governanceFields.contains(where: { $0.label == "governance_truth" && $0.value.contains("当前生效 A1/S2") }))
        #expect(record.governanceFields.contains(where: { $0.label == "repair_action" && $0.value.contains("打开 A-Tier：") }))
        #expect(record.toolArgumentsText?.contains("\"url\"") == true)
        #expect(record.resultFields.contains(where: { $0.label == "result_summary" && $0.value == "Navigation completed" }))
        #expect(record.rawOutputPreview?.contains("screenshot.png") == true)
        #expect(record.evidenceFields.contains(where: { $0.label == "audit_ref" && $0.value == "audit-skill-6" }))
        #expect(record.approvalHistory.count == 1)
        #expect(record.timeline.count == 2)
        #expect(record.timeline.contains(where: { !$0.summary.contains("治理真相：") }))
        #expect(record.supervisorEvidenceJSON?.contains("\"trigger_source\"") == true)
    }

    @Test
    func fullRecordPrefersPersistedGovernanceEvidenceFromRawLog() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt_project_skill_persisted_governance_\(UUID().uuidString)", isDirectory: true)
        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()

        let raw = """
        {"type":"project_skill_call","created_at":1.0,"status":"blocked","request_id":"skill-persisted-1","skill_id":"agent-browser","tool_name":"device.browser.control","tool_args":{"action":"open_url"},"authorization_disposition":"deny","deny_code":"governance_capability_denied","policy_source":"project_governance","policy_reason":"execution_tier_missing_browser_runtime","governance_reason":"persisted governance reason","blocked_summary":"persisted blocked summary","governance_truth":"persisted governance truth","repair_action":"persisted repair action"}
        """
        try #require(raw.data(using: .utf8)).write(to: ctx.rawLogURL, options: .atomic)

        let record = try #require(
            ProjectSkillActivityPresentation.fullRecord(
                ctx: ctx,
                requestID: "skill-persisted-1"
            )
        )

        #expect(record.governanceFields.contains(where: { $0.label == "governance_reason" && $0.value == "persisted governance reason" }))
        #expect(record.governanceFields.contains(where: { $0.label == "blocked_summary" && $0.value == "persisted blocked summary" }))
        #expect(record.governanceFields.contains(where: { $0.label == "governance_truth" && $0.value == "persisted governance truth" }))
        #expect(record.governanceFields.contains(where: { $0.label == "repair_action" && $0.value == "persisted repair action" }))
    }

    @Test
    func fullRecordUsesPersistedRequiredCapabilityFromProjectActivityRawLog() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt_project_skill_required_capability_\(UUID().uuidString)", isDirectory: true)
        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()

        let raw = """
        {"type":"project_skill_call","created_at":1.0,"status":"blocked","request_id":"skill-required-cap-1","skill_id":"tavily-websearch","tool_name":"web_search","tool_args":{"query":"OpenAI GPT-5.4 release notes"},"required_capability":"web.fetch","deny_code":"grant_required","authorization_disposition":"deny"}
        """
        try #require(raw.data(using: .utf8)).write(to: ctx.rawLogURL, options: .atomic)

        let record = try #require(
            ProjectSkillActivityPresentation.fullRecord(
                ctx: ctx,
                requestID: "skill-required-cap-1"
            )
        )

        #expect(record.approvalFields.contains(where: {
            $0.label == "required_capability" && $0.value == "web.fetch"
        }))

        let text = ProjectSkillActivityPresentation.displayFullRecordText(record)
        #expect(text.contains("所需能力：联网访问（web.fetch）"))
        #expect(text.contains("拒绝原因：继续这个动作前，仍然需要先通过 联网访问 的 Hub 授权。（grant_required）"))
    }

    @Test
    func fullRecordRetainsGovernedRoutingAndApprovalContextAcrossLifecycle() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt_project_skill_governed_lifecycle_\(UUID().uuidString)", isDirectory: true)
        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()

        let raw = """
        {"type":"project_skill_call","created_at":1.0,"status":"awaiting_approval","request_id":"skill-governed-chain-1","skill_id":"guarded-automation","requested_skill_id":"browser.open","tool_name":"device.browser.control","tool_args":{"action":"open_url","url":"https://example.com"},"routing_reason_code":"preferred_builtin_selected","routing_explanation":"requested entrypoint browser.open converged to preferred builtin guarded-automation","intent_families":["browser.navigate"],"capability_families":["repo.read","browser.interact"],"capability_profiles":["observe_only","browser_operator"],"required_runtime_surfaces":["managed_browser_runtime"],"unblock_actions":["request_local_approval"],"execution_readiness":"local_approval_required","approval_summary":"新增放开：browser_operator","current_runnable_profiles":["observe_only"],"requested_profiles":["observe_only","browser_operator"],"delta_profiles":["browser_operator"],"current_runnable_capability_families":["repo.read"],"requested_capability_families":["repo.read","browser.interact"],"delta_capability_families":["browser.interact"],"grant_floor":"privileged","approval_floor":"local_approval"}
        {"type":"project_skill_call","created_at":2.0,"status":"completed","request_id":"skill-governed-chain-1","skill_id":"guarded-automation","tool_name":"device.browser.control","tool_args":{"action":"open_url","url":"https://example.com"},"result_summary":"Navigation completed"}
        """
        try #require(raw.data(using: .utf8)).write(to: ctx.rawLogURL, options: .atomic)

        let record = try #require(
            ProjectSkillActivityPresentation.fullRecord(
                ctx: ctx,
                requestID: "skill-governed-chain-1"
            )
        )

        #expect(record.title == "browser.open -> guarded-automation")
        #expect(record.requestMetadata.contains(where: {
            $0.label == "requested_skill_id" && $0.value == "browser.open"
        }))
        #expect(record.requestMetadata.contains(where: {
            $0.label == "routing_reason_code" && $0.value == "preferred_builtin_selected"
        }))
        #expect(record.requestMetadata.contains(where: {
            $0.label == "routing_explanation"
                && $0.value == "requested entrypoint browser.open converged to preferred builtin guarded-automation"
        }))
        #expect(record.approvalFields.contains(where: {
            $0.label == "execution_readiness"
                && $0.value == XTSkillExecutionReadinessState.localApprovalRequired.rawValue
        }))
        #expect(record.approvalFields.contains(where: {
            $0.label == "required_runtime_surfaces" && $0.value == "managed_browser_runtime"
        }))
        #expect(record.approvalFields.contains(where: {
            $0.label == "unblock_actions" && $0.value == "request_local_approval"
        }))
        #expect(record.approvalFields.contains(where: {
            $0.label == "requested_profiles" && $0.value == "observe_only, browser_operator"
        }))
        #expect(record.approvalFields.contains(where: {
            $0.label == "delta_capability_families" && $0.value == "browser.interact"
        }))

        let approvalEntry = try #require(record.approvalHistory.first)
        #expect(approvalEntry.summary.contains("这次审批通过后，会按当前受治理路径继续执行。"))
        #expect(approvalEntry.detail?.contains("current_runnable_capability_families=repo.read") == true)
        #expect(approvalEntry.detail?.contains("requested_capability_families=repo.read,browser.interact") == true)
        #expect(approvalEntry.detail?.contains("delta_capability_families=browser.interact") == true)

        let text = ProjectSkillActivityPresentation.displayFullRecordText(record)
        #expect(text.contains("路由判定：系统优先切到受治理内建") == true)
        #expect(text.contains("路由说明：浏览器入口会先收敛到受治理内建 guarded-automation 再执行") == true)
        #expect(text.contains("执行就绪：等待本地审批") == true)
        #expect(text.contains("运行面：受治理浏览器运行面（managed_browser_runtime）") == true)
        #expect(text.contains("解阻动作：请求本地审批（request_local_approval）") == true)
        #expect(text.contains("本次请求档位：observe_only、browser_operator") == true)
    }

    @Test
    func displayTimelineDetailLocalizesKnownEngineeringFields() {
        let detail = ProjectSkillActivityPresentation.displayTimelineDetail(
            """
            policy_reason=execution_tier_missing_browser_runtime
            repair_action=打开 A-Tier：把项目 A-Tier 提升到 A4 Agent。
            authorization_disposition=ask
            deny_code=local_approval_required
            required_capability=web.fetch
            resolution_source=manual_retry
            """
        )

        #expect(detail?.contains("策略原因：execution_tier_missing_browser_runtime") == true)
        #expect(detail?.contains("修复动作：打开 A-Tier：把项目 A-Tier 提升到 A4 Agent。") == true)
        #expect(detail?.contains("审批结论：ask") == true)
        #expect(detail?.contains("拒绝原因：继续这个动作前，仍然需要本地审批。（local_approval_required）") == true)
        #expect(detail?.contains("所需能力：联网访问（web.fetch）") == true)
        #expect(detail?.contains("处理来源：manual_retry") == true)
    }

    @Test
    func displayTimelineDetailLocalizesGrantRequiredDenyCode() {
        let detail = ProjectSkillActivityPresentation.displayTimelineDetail(
            """
            deny_code=grant_required
            authorization_disposition=deny
            resolution_source=project_skill_authorization
            """
        )

        #expect(detail?.contains("拒绝原因：继续这个动作前，仍然需要先通过 Hub 授权。（grant_required）") == true)
        #expect(detail?.contains("审批结论：deny") == true)
        #expect(detail?.contains("处理来源：project_skill_authorization") == true)
    }

    @Test
    func displayTimelineDetailUsesRequiredCapabilityWhenGrantRequirementIsPresent() {
        let detail = ProjectSkillActivityPresentation.displayTimelineDetail(
            """
            deny_code=grant_required
            authorization_disposition=deny
            required_capability=web.fetch
            """
        )

        #expect(detail?.contains("拒绝原因：继续这个动作前，仍然需要先通过 联网访问 的 Hub 授权。（grant_required）") == true)
        #expect(detail?.contains("所需能力：联网访问（web.fetch）") == true)
    }

    @Test
    func displayTimelineDetailLocalizesGovernedSkillReadinessAndCapabilityFields() {
        let detail = ProjectSkillActivityPresentation.displayTimelineDetail(
            """
            requested_skill_id=browser.open
            intent_families=browser.navigate,research.lookup
            capability_families=repo.read,browser.interact
            capability_profiles=observe_only,browser_operator
            execution_readiness=local_approval_required
            required_runtime_surfaces=managed_browser_runtime,hub_bridge_network
            unblock_actions=request_local_approval,request_hub_grant
            current_runnable_profiles=observe_only
            requested_profiles=observe_only,browser_operator
            delta_profiles=browser_operator
            current_runnable_capability_families=repo.read
            requested_capability_families=repo.read,browser.interact
            delta_capability_families=browser.interact
            grant_floor=privileged
            approval_floor=local_approval
            """
        )

        #expect(detail?.contains("请求技能 ID：browser.open") == true)
        #expect(detail?.contains("意图族：browser.navigate、research.lookup") == true)
        #expect(detail?.contains("能力族：") == true)
        #expect(detail?.contains("repo.read") == true)
        #expect(detail?.contains("browser.interact") == true)
        #expect(detail?.contains("能力档位：observe_only、browser_operator") == true)
        #expect(detail?.contains("执行就绪：等待本地审批") == true)
        #expect(detail?.contains("运行面：受治理浏览器运行面（managed_browser_runtime）、Hub 桥接网络（hub_bridge_network）") == true)
        #expect(detail?.contains("解阻动作：请求本地审批（request_local_approval）、请求 Hub grant（request_hub_grant）") == true)
        #expect(detail?.contains("当前可直接运行档位：observe_only") == true)
        #expect(detail?.contains("本次请求档位：observe_only、browser_operator") == true)
        #expect(detail?.contains("新增放开档位：browser_operator") == true)
        #expect(detail?.contains("当前可直接运行能力族：") == true)
        #expect(detail?.contains("本次请求能力族：") == true)
        #expect(detail?.contains("新增放开能力族：") == true)
        #expect(detail?.contains("授权门槛：高权限 grant") == true)
        #expect(detail?.contains("审批门槛：本地审批") == true)
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
                ProjectSkillRecordField(label: "requested_skill_id", value: "browser.open"),
                ProjectSkillRecordField(label: "intent_families", value: "browser.navigate, research.lookup"),
                ProjectSkillRecordField(label: "capability_families", value: "repo.read, browser.interact"),
                ProjectSkillRecordField(label: "capability_profiles", value: "observe_only, browser_operator"),
                ProjectSkillRecordField(label: "tool_name", value: "device.browser.control")
            ],
            approvalFields: [
                ProjectSkillRecordField(label: "deny_code", value: "local_approval_required"),
                ProjectSkillRecordField(label: "execution_readiness", value: "local_approval_required"),
                ProjectSkillRecordField(label: "required_runtime_surfaces", value: "managed_browser_runtime, hub_bridge_network"),
                ProjectSkillRecordField(label: "unblock_actions", value: "request_local_approval, request_hub_grant"),
                ProjectSkillRecordField(label: "current_runnable_profiles", value: "observe_only"),
                ProjectSkillRecordField(label: "requested_profiles", value: "observe_only, browser_operator"),
                ProjectSkillRecordField(label: "delta_profiles", value: "browser_operator"),
                ProjectSkillRecordField(label: "requested_capability_families", value: "repo.read, browser.interact"),
                ProjectSkillRecordField(label: "grant_floor", value: "privileged"),
                ProjectSkillRecordField(label: "approval_floor", value: "local_approval"),
                ProjectSkillRecordField(label: "required_capability", value: "web.fetch")
            ],
            governanceFields: [
                ProjectSkillRecordField(label: "policy_reason", value: "execution_tier_missing_browser_runtime"),
                ProjectSkillRecordField(label: "blocked_summary", value: "当前项目 A-Tier 不允许浏览器自动化。"),
                ProjectSkillRecordField(label: "governance_truth", value: "当前生效 A1/S2 · 审查 Periodic。"),
                ProjectSkillRecordField(label: "repair_action", value: "打开 A-Tier：把项目 A-Tier 提升到 A4 Agent。")
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
        #expect(text.contains("请求技能 ID：browser.open"))
        #expect(text.contains("意图族：browser.navigate、research.lookup"))
        #expect(text.contains("能力族：") == true)
        #expect(text.contains("repo.read"))
        #expect(text.contains("browser.interact"))
        #expect(text.contains("能力档位：observe_only、browser_operator"))
        #expect(text.contains("工具：device.browser.control"))
        #expect(text.contains("拒绝原因：继续这个动作前，仍然需要本地审批。（local_approval_required）"))
        #expect(text.contains("执行就绪：等待本地审批"))
        #expect(text.contains("运行面：受治理浏览器运行面（managed_browser_runtime）、Hub 桥接网络（hub_bridge_network）"))
        #expect(text.contains("解阻动作：请求本地审批（request_local_approval）、请求 Hub grant（request_hub_grant）"))
        #expect(text.contains("当前可直接运行档位：observe_only"))
        #expect(text.contains("本次请求档位：observe_only、browser_operator"))
        #expect(text.contains("新增放开档位：browser_operator"))
        #expect(text.contains("本次请求能力族：") == true)
        #expect(text.contains("授权门槛：高权限 grant"))
        #expect(text.contains("审批门槛：本地审批"))
        #expect(text.contains("所需能力：联网访问（web.fetch）"))
        #expect(text.contains("== 治理上下文 =="))
        #expect(text.contains("策略原因：execution_tier_missing_browser_runtime"))
        #expect(text.contains("阻塞说明：当前项目 A-Tier 不允许浏览器自动化。"))
        #expect(text.contains("治理真相：当前生效 A1/S2 · 审查 周期。"))
        #expect(text.contains("修复动作：打开 A-Tier：把项目 A-Tier 提升到 A4 Agent。"))
        #expect(text.contains("状态：待审批"))
        #expect(text.contains("处理来源：manual_retry"))
        #expect(text.contains("== 原始 JSON 事件 =="))
    }
}
