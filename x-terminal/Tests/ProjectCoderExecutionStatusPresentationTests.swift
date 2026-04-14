import Foundation
import Testing
@testable import XTerminal

struct ProjectCoderExecutionStatusPresentationTests {
    @Test
    func offlineWithoutExecutionRecordShowsHubOffline() {
        let presentation = ProjectCoderExecutionStatusResolver.map(
            configuredModelId: "openai/gpt-5.4",
            snapshot: .empty(role: .coder, source: "test"),
            hubConnected: false
        )

        #expect(presentation.titleText == "Coder · gpt-5.4")
        #expect(presentation.statusText == "Hub 离线")
        #expect(presentation.tone == .danger)
        #expect(presentation.detailBadge == nil)
    }

    @Test
    func downgradedExecutionShowsActualLocalModelCompactBadge() throws {
        let originalMode = HubAIClient.transportMode()
        defer { HubAIClient.setTransportMode(originalMode) }
        HubAIClient.setTransportMode(.grpc)

        let snapshot = AXRoleExecutionSnapshot(
            role: .coder,
            updatedAt: 42,
            stage: "reply",
            requestedModelId: "openai/gpt-5.4",
            actualModelId: "qwen3-17b-mlx-bf16",
            runtimeProvider: "Hub (Local)",
            executionPath: "hub_downgraded_to_local",
            fallbackReasonCode: "model_not_found",
            auditRef: "audit-route-project-chat",
            denyCode: "",
            remoteRetryAttempted: false,
            remoteRetryFromModelId: "",
            remoteRetryToModelId: "",
            remoteRetryReasonCode: "",
            source: "test"
        )

        let presentation = ProjectCoderExecutionStatusResolver.map(
            configuredModelId: "openai/gpt-5.4",
            snapshot: snapshot,
            hubConnected: true
        )

        let detailBadge = try #require(presentation.detailBadge)
        let interpretationBadge = try #require(presentation.interpretationBadge)
        #expect(presentation.titleText == "Coder · gpt-5.4")
        #expect(presentation.statusText == "Downgraded")
        #expect(presentation.tone == .warning)
        #expect(detailBadge.text == "Local qwen3-17b-mlx-bf16")
        #expect(detailBadge.tone == .warning)
        #expect(interpretationBadge.text == "Hub Downgrade")
        #expect(interpretationBadge.tone == .warning)
        #expect(presentation.summaryText == "这更像是 Hub 在执行阶段把远端请求降到了本地，不是 XT 静默改路由。")
        #expect(presentation.helpText.contains("actual route=Hub (Local) -> qwen3-17b-mlx-bf16 [hub_downgraded_to_local]"))
        #expect(presentation.helpText.contains("grpc-only 提示：这次落到本地更像 Hub 执行阶段降级或 export gate 生效"))
    }

    @Test
    func verifiedRemoteExecutionKeepsHeaderCompact() {
        let snapshot = AXRoleExecutionSnapshot(
            role: .coder,
            updatedAt: 42,
            stage: "reply",
            requestedModelId: "openai/gpt-5.4",
            actualModelId: "openai/gpt-5.4",
            runtimeProvider: "Hub (Remote)",
            executionPath: "remote_model",
            fallbackReasonCode: "",
            auditRef: "audit-route-project-chat-remote",
            denyCode: "",
            remoteRetryAttempted: false,
            remoteRetryFromModelId: "",
            remoteRetryToModelId: "",
            remoteRetryReasonCode: "",
            source: "test"
        )

        let presentation = ProjectCoderExecutionStatusResolver.map(
            configuredModelId: "openai/gpt-5.4",
            snapshot: snapshot,
            hubConnected: true
        )

        #expect(presentation.titleText == "Coder · gpt-5.4")
        #expect(presentation.statusText == "Remote")
        #expect(presentation.tone == .success)
        #expect(presentation.detailBadge == nil)
        #expect(presentation.interpretationBadge == nil)
        #expect(presentation.summaryText == nil)
    }

    @Test
    func governanceInterceptionExtendsSummaryAndTooltip() throws {
        let snapshot = AXRoleExecutionSnapshot(
            role: .coder,
            updatedAt: 42,
            stage: "reply",
            requestedModelId: "openai/gpt-5.4",
            actualModelId: "openai/gpt-5.4",
            runtimeProvider: "Hub (Remote)",
            executionPath: "remote_model",
            fallbackReasonCode: "",
            auditRef: "audit-route-project-chat-remote-governance",
            denyCode: "",
            remoteRetryAttempted: false,
            remoteRetryFromModelId: "",
            remoteRetryToModelId: "",
            remoteRetryReasonCode: "",
            source: "test"
        )
        let governancePresentation = ProjectGovernancePresentation(
            executionTier: .a1Plan,
            supervisorInterventionTier: .s2PeriodicReview,
            reviewPolicyMode: .periodic,
            progressHeartbeatSeconds: 900,
            reviewPulseSeconds: 1800,
            brainstormReviewSeconds: 0,
            eventDrivenReviewEnabled: false,
            compatSource: AXProjectGovernanceCompatSource.explicitDualDial.rawValue
        )
        let interception = try #require(
            ProjectGovernanceInterceptionPresentation.make(
                from: ProjectSkillActivityItem(
                    requestID: "skill-governance-1",
                    skillID: "agent-browser",
                    toolName: "device.browser.control",
                    status: "blocked",
                    createdAt: 42,
                    resolutionSource: "test",
                    toolArgs: [:],
                    resultSummary: "",
                    detail: "",
                    denyCode: "governance_capability_denied",
                    authorizationDisposition: "deny",
                    policySource: "project_governance",
                    policyReason: "execution_tier_missing_browser_runtime",
                    governanceTruth: "治理真相：当前生效 A1/S2 · 审查 周期。",
                    governanceReason: "当前项目 A-Tier 不允许浏览器自动化。",
                    blockedSummary: "当前项目 A-Tier 不允许浏览器自动化。 打开项目设置 -> A-Tier，把档位提升到 A4 Agent 或更高后，再使用浏览器自动化。",
                    repairAction: "打开 A-Tier：把项目 A-Tier 提升到 A4 Agent。"
                )
            )
        )

        let presentation = ProjectCoderExecutionStatusResolver.map(
            configuredModelId: "openai/gpt-5.4",
            snapshot: snapshot,
            hubConnected: true,
            governancePresentation: governancePresentation,
            governanceInterception: interception
        )

        let interpretationBadge = try #require(presentation.interpretationBadge)
        let summaryText = try #require(presentation.summaryText)
        #expect(presentation.statusText == "Blocked")
        #expect(presentation.tone == .warning)
        #expect(interpretationBadge.text == "A-Tier Gate")
        #expect(interpretationBadge.tone == .warning)
        #expect(summaryText.contains("最近治理拦截：当前项目 A-Tier 不允许浏览器自动化。") == true)
        #expect(summaryText.contains("治理真相：当前生效 A1/S2") == true)
        #expect(presentation.helpText.contains("policy_reason=execution_tier_missing_browser_runtime"))
        #expect(presentation.helpText.contains("repair_action=打开 A-Tier："))
    }

    @Test
    func runtimeClampPromotesStatusAndBadge() throws {
        let snapshot = AXRoleExecutionSnapshot(
            role: .coder,
            updatedAt: 42,
            stage: "reply",
            requestedModelId: "openai/gpt-5.4",
            actualModelId: "openai/gpt-5.4",
            runtimeProvider: "Hub (Remote)",
            executionPath: "remote_model",
            fallbackReasonCode: "",
            auditRef: "audit-route-project-chat-runtime-clamp",
            denyCode: "",
            remoteRetryAttempted: false,
            remoteRetryFromModelId: "",
            remoteRetryToModelId: "",
            remoteRetryReasonCode: "",
            source: "test"
        )
        let interception = try #require(
            ProjectGovernanceInterceptionPresentation.make(
                from: ProjectSkillActivityItem(
                    requestID: "skill-governance-runtime-clamp-1",
                    skillID: "agent-browser",
                    toolName: "device.browser.control",
                    status: "failed",
                    createdAt: 42,
                    resolutionSource: "test",
                    toolArgs: [:],
                    resultSummary: "",
                    detail: "",
                    denyCode: "autonomy_policy_denied",
                    authorizationDisposition: "deny",
                    policySource: "project_autonomy_policy",
                    policyReason: "runtime_surface_ttl_expired",
                    governanceTruth: "治理真相：当前生效 A4/S3 · 审查 混合。",
                    governanceReason: "当前运行面的 TTL 已过期，所以这次自动化没有继续执行。",
                    blockedSummary: "当前运行面的 TTL 已过期，所以这次自动化没有继续执行。 打开项目设置 -> 项目治理，检查当前运行面限制、可信自动化状态和生效策略。",
                    repairAction: "打开治理设置：打开项目设置 -> 项目治理，检查当前运行面限制、可信自动化状态和生效策略。"
                )
            )
        )

        let presentation = ProjectCoderExecutionStatusResolver.map(
            configuredModelId: "openai/gpt-5.4",
            snapshot: snapshot,
            hubConnected: true,
            governanceInterception: interception
        )

        let interpretationBadge = try #require(presentation.interpretationBadge)
        #expect(presentation.statusText == "Clamped")
        #expect(presentation.tone == .danger)
        #expect(interpretationBadge.text == "TTL Expired")
        #expect(interpretationBadge.tone == .danger)
        #expect(presentation.helpText.contains("policy_reason=runtime_surface_ttl_expired"))
    }

    @Test
    func governanceTruthEntersTooltipWithoutDuplicatingSummary() {
        let snapshot = AXRoleExecutionSnapshot(
            role: .coder,
            updatedAt: 42,
            stage: "reply",
            requestedModelId: "openai/gpt-5.4",
            actualModelId: "openai/gpt-5.4",
            runtimeProvider: "Hub (Remote)",
            executionPath: "remote_model",
            fallbackReasonCode: "",
            auditRef: "audit-route-project-chat-remote-governance-truth",
            denyCode: "",
            remoteRetryAttempted: false,
            remoteRetryFromModelId: "",
            remoteRetryToModelId: "",
            remoteRetryReasonCode: "",
            source: "test"
        )
        let governancePresentation = ProjectGovernancePresentation(
            executionTier: .a3DeliverAuto,
            supervisorInterventionTier: .s3StrategicCoach,
            reviewPolicyMode: .hybrid,
            progressHeartbeatSeconds: 300,
            reviewPulseSeconds: 600,
            brainstormReviewSeconds: 1800,
            eventDrivenReviewEnabled: true,
            compatSource: AXProjectGovernanceCompatSource.explicitDualDial.rawValue
        )

        let presentation = ProjectCoderExecutionStatusResolver.map(
            configuredModelId: "openai/gpt-5.4",
            snapshot: snapshot,
            hubConnected: true,
            governancePresentation: governancePresentation
        )

        #expect(presentation.summaryText == nil)
        #expect(presentation.helpText.contains("治理真相：当前生效 A3/S3") == true)
        #expect(presentation.helpText.contains("审查 混合") == true)
    }

    @Test
    func remoteFailureShowsHumanizedCompactReasonBadge() throws {
        let snapshot = AXRoleExecutionSnapshot(
            role: .coder,
            updatedAt: 42,
            stage: "reply",
            requestedModelId: "openai/gpt-5.4",
            actualModelId: "",
            runtimeProvider: "Hub (Remote)",
            executionPath: "remote_error",
            fallbackReasonCode: "",
            auditRef: "audit-route-project-chat-remote-failure",
            denyCode: "remote_export_blocked",
            remoteRetryAttempted: false,
            remoteRetryFromModelId: "",
            remoteRetryToModelId: "",
            remoteRetryReasonCode: "",
            source: "test"
        )

        let presentation = ProjectCoderExecutionStatusResolver.map(
            configuredModelId: "openai/gpt-5.4",
            snapshot: snapshot,
            hubConnected: true
        )

        let detailBadge = try #require(presentation.detailBadge)
        #expect(presentation.statusText == "Failed")
        #expect(presentation.tone == .danger)
        #expect(detailBadge.text == "Reason Hub remote export gate 阻断了远端请求")
        #expect(detailBadge.tone == .danger)
    }

    @Test
    func grpcFallbackShowsUpstreamInterpretationBadge() throws {
        let originalMode = HubAIClient.transportMode()
        defer { HubAIClient.setTransportMode(originalMode) }
        HubAIClient.setTransportMode(.grpc)

        let snapshot = AXRoleExecutionSnapshot(
            role: .coder,
            updatedAt: 42,
            stage: "reply",
            requestedModelId: "openai/gpt-5.4",
            actualModelId: "qwen3-17b-mlx-bf16",
            runtimeProvider: "Hub (Local)",
            executionPath: "local_fallback_after_remote_error",
            fallbackReasonCode: "provider_not_ready",
            auditRef: "audit-route-project-chat-upstream-fallback",
            denyCode: "",
            remoteRetryAttempted: false,
            remoteRetryFromModelId: "",
            remoteRetryToModelId: "",
            remoteRetryReasonCode: "",
            source: "test"
        )

        let presentation = ProjectCoderExecutionStatusResolver.map(
            configuredModelId: "openai/gpt-5.4",
            snapshot: snapshot,
            hubConnected: true
        )

        let interpretationBadge = try #require(presentation.interpretationBadge)
        #expect(interpretationBadge.text == "Upstream Issue")
        #expect(interpretationBadge.tone == .warning)
    }

    @Test
    func localRuntimeMismatchShowsProjectLevelTakeoverSummary() throws {
        let snapshot = AXRoleExecutionSnapshot(
            role: .coder,
            updatedAt: 42,
            stage: "reply",
            requestedModelId: "qwen3-14b-mlx",
            actualModelId: "qwen3-14b-mlx",
            runtimeProvider: "Hub (Local)",
            executionPath: "local_runtime",
            fallbackReasonCode: "",
            auditRef: "audit-route-project-chat-local-runtime",
            denyCode: "",
            remoteRetryAttempted: false,
            remoteRetryFromModelId: "",
            remoteRetryToModelId: "",
            remoteRetryReasonCode: "",
            source: "test"
        )

        let presentation = ProjectCoderExecutionStatusResolver.map(
            configuredModelId: "openai/gpt-5.4",
            snapshot: snapshot,
            hubConnected: true
        )

        let summaryText = try #require(presentation.summaryText)
        #expect(summaryText.contains("项目级本地锁"))
        #expect(summaryText.contains("本地接管"))
    }

    @Test
    func governanceSummaryPrecedesRouteSummaryWhenBothExist() throws {
        let snapshot = AXRoleExecutionSnapshot(
            role: .coder,
            updatedAt: 42,
            stage: "reply",
            requestedModelId: "qwen3-14b-mlx",
            actualModelId: "qwen3-14b-mlx",
            runtimeProvider: "Hub (Local)",
            executionPath: "local_runtime",
            fallbackReasonCode: "",
            auditRef: "audit-route-project-chat-local-runtime-governance",
            denyCode: "",
            remoteRetryAttempted: false,
            remoteRetryFromModelId: "",
            remoteRetryToModelId: "",
            remoteRetryReasonCode: "",
            source: "test"
        )
        let governancePresentation = ProjectGovernancePresentation(
            executionTier: .a1Plan,
            supervisorInterventionTier: .s2PeriodicReview,
            reviewPolicyMode: .periodic,
            progressHeartbeatSeconds: 900,
            reviewPulseSeconds: 1800,
            brainstormReviewSeconds: 0,
            eventDrivenReviewEnabled: false,
            compatSource: AXProjectGovernanceCompatSource.explicitDualDial.rawValue
        )
        let interception = try #require(
            ProjectGovernanceInterceptionPresentation.make(
                from: ProjectSkillActivityItem(
                    requestID: "skill-governance-summary-order-1",
                    skillID: "agent-browser",
                    toolName: "device.browser.control",
                    status: "blocked",
                    createdAt: 42,
                    resolutionSource: "test",
                    toolArgs: [:],
                    resultSummary: "",
                    detail: "",
                    denyCode: "governance_capability_denied",
                    authorizationDisposition: "deny",
                    policySource: "project_governance",
                    policyReason: "execution_tier_missing_browser_runtime",
                    governanceTruth: "治理真相：当前生效 A1/S2 · 审查 周期。",
                    governanceReason: "当前项目 A-Tier 不允许浏览器自动化。",
                    blockedSummary: "当前项目 A-Tier 不允许浏览器自动化。 打开项目设置 -> A-Tier，把档位提升到 A4 Agent 或更高后，再使用浏览器自动化。",
                    repairAction: "打开 A-Tier：把项目 A-Tier 提升到 A4 Agent。"
                )
            )
        )

        let presentation = ProjectCoderExecutionStatusResolver.map(
            configuredModelId: "openai/gpt-5.4",
            snapshot: snapshot,
            hubConnected: true,
            governancePresentation: governancePresentation,
            governanceInterception: interception
        )

        let summaryText = try #require(presentation.summaryText)
        let lines = summaryText.split(separator: "\n").map(String.init)
        let firstLine = try #require(lines.first)
        #expect(firstLine.contains("最近治理拦截："))
        #expect(lines.contains(where: { $0.contains("项目级本地锁") }))
    }

    @Test
    func primaryActionRoutesRemoteExportGateToHubRecovery() throws {
        let snapshot = AXRoleExecutionSnapshot(
            role: .coder,
            updatedAt: 42,
            stage: "reply",
            requestedModelId: "openai/gpt-5.4",
            actualModelId: "qwen3-17b-mlx-bf16",
            runtimeProvider: "Hub (Local)",
            executionPath: "local_fallback_after_remote_error",
            fallbackReasonCode: "remote_export_blocked",
            auditRef: "audit-primary-action-gate",
            denyCode: "",
            remoteRetryAttempted: false,
            remoteRetryFromModelId: "",
            remoteRetryToModelId: "",
            remoteRetryReasonCode: "",
            source: "test"
        )

        let action = try #require(
            ProjectCoderExecutionStatusPrimaryActionResolver.resolve(
                configuredModelId: "openai/gpt-5.4",
                snapshot: snapshot,
                hubConnected: true,
                language: .simplifiedChinese
            )
        )

        #expect(action.kind == .openHubRecovery)
        #expect(action.title == "Hub 诊断与恢复")
        #expect(action.helpText.contains("远端导出闸门"))
    }

    @Test
    func primaryActionPrefersGovernanceRepairWhenRecentInterceptionExists() throws {
        let snapshot = AXRoleExecutionSnapshot(
            role: .coder,
            updatedAt: 42,
            stage: "reply",
            requestedModelId: "openai/gpt-5.4",
            actualModelId: "openai/gpt-5.4",
            runtimeProvider: "Hub (Remote)",
            executionPath: "remote_model",
            fallbackReasonCode: "",
            auditRef: "audit-primary-action-governance",
            denyCode: "",
            remoteRetryAttempted: false,
            remoteRetryFromModelId: "",
            remoteRetryToModelId: "",
            remoteRetryReasonCode: "",
            source: "test"
        )
        let governanceInterception = try #require(
            ProjectGovernanceInterceptionPresentation.make(
                from: ProjectSkillActivityItem(
                    requestID: "skill-governance-action-1",
                    skillID: "agent-browser",
                    toolName: "device.browser.control",
                    status: "blocked",
                    createdAt: 42,
                    resolutionSource: "test",
                    toolArgs: [:],
                    resultSummary: "",
                    detail: "",
                    denyCode: "governance_capability_denied",
                    authorizationDisposition: "deny",
                    policySource: "project_governance",
                    policyReason: "execution_tier_missing_browser_runtime",
                    governanceTruth: "治理真相：当前生效 A1/S2 · 审查 周期。",
                    governanceReason: "当前项目 A-Tier 不允许浏览器自动化。",
                    blockedSummary: "当前项目 A-Tier 不允许浏览器自动化。 打开项目设置 -> A-Tier，把档位提升到 A4 Agent 或更高后，再使用浏览器自动化。",
                    repairAction: "打开 A-Tier：把项目 A-Tier 提升到 A4 Agent。"
                )
            )
        )

        let action = try #require(
            ProjectCoderExecutionStatusPrimaryActionResolver.resolve(
                configuredModelId: "openai/gpt-5.4",
                snapshot: snapshot,
                hubConnected: true,
                governanceInterception: governanceInterception,
                language: .simplifiedChinese
            )
        )

        #expect(action.kind == .openExecutionTier)
        #expect(action.title == "A-Tier")
        #expect(action.helpText.contains("被治理拦下了"))
    }

    @Test
    func primaryActionRoutesModelNotFoundToAIModels() throws {
        let snapshot = AXRoleExecutionSnapshot(
            role: .coder,
            updatedAt: 42,
            stage: "reply",
            requestedModelId: "openai/gpt-5.4",
            actualModelId: "qwen3-17b-mlx-bf16",
            runtimeProvider: "Hub (Local)",
            executionPath: "hub_downgraded_to_local",
            fallbackReasonCode: "model_not_found",
            auditRef: "audit-primary-action-model",
            denyCode: "",
            remoteRetryAttempted: false,
            remoteRetryFromModelId: "",
            remoteRetryToModelId: "",
            remoteRetryReasonCode: "",
            source: "test"
        )

        let action = try #require(
            ProjectCoderExecutionStatusPrimaryActionResolver.resolve(
                configuredModelId: "openai/gpt-5.4",
                snapshot: snapshot,
                hubConnected: true,
                language: .simplifiedChinese
            )
        )

        #expect(action.kind == .openModelSettings)
        #expect(action.title == "AI 模型")
    }

    @Test
    func primaryActionRoutesHubDowngradeToHubLogs() throws {
        let snapshot = AXRoleExecutionSnapshot(
            role: .coder,
            updatedAt: 42,
            stage: "reply",
            requestedModelId: "openai/gpt-5.4",
            actualModelId: "qwen3-17b-mlx-bf16",
            runtimeProvider: "Hub (Local)",
            executionPath: "hub_downgraded_to_local",
            fallbackReasonCode: "downgrade_to_local",
            auditRef: "audit-primary-action-downgrade",
            denyCode: "",
            remoteRetryAttempted: false,
            remoteRetryFromModelId: "",
            remoteRetryToModelId: "",
            remoteRetryReasonCode: "",
            source: "test"
        )

        let action = try #require(
            ProjectCoderExecutionStatusPrimaryActionResolver.resolve(
                configuredModelId: "openai/gpt-5.4",
                snapshot: snapshot,
                hubConnected: true,
                language: .simplifiedChinese
            )
        )

        #expect(action.kind == .openHubConnectionLog)
        #expect(action.title == "Hub 日志")
    }

    @Test
    func primaryActionRoutesRemoteFailureToDiagnostics() throws {
        let snapshot = AXRoleExecutionSnapshot(
            role: .coder,
            updatedAt: 42,
            stage: "reply",
            requestedModelId: "openai/gpt-5.4",
            actualModelId: "",
            runtimeProvider: "Hub (Remote)",
            executionPath: "remote_error",
            fallbackReasonCode: "provider_not_ready",
            auditRef: "audit-primary-action-diagnostics",
            denyCode: "",
            remoteRetryAttempted: false,
            remoteRetryFromModelId: "",
            remoteRetryToModelId: "",
            remoteRetryReasonCode: "",
            source: "test"
        )

        let action = try #require(
            ProjectCoderExecutionStatusPrimaryActionResolver.resolve(
                configuredModelId: "openai/gpt-5.4",
                snapshot: snapshot,
                hubConnected: true,
                language: .simplifiedChinese
            )
        )

        #expect(action.kind == .openDiagnostics)
        #expect(action.title == "XT Diagnostics")
    }

    @Test
    func primaryActionRoutesSupervisorGrantBlockerToGovernanceOverview() throws {
        let snapshot = AXRoleExecutionSnapshot(
            role: .coder,
            updatedAt: 42,
            stage: "reply",
            requestedModelId: "openai/gpt-5.4",
            actualModelId: "qwen3-17b-mlx-bf16",
            runtimeProvider: "Hub (Local)",
            executionPath: "local_fallback_after_remote_error",
            fallbackReasonCode: "provider_not_ready",
            auditRef: "audit-primary-action-supervisor-grant",
            denyCode: "device_permission_owner_missing",
            remoteRetryAttempted: false,
            remoteRetryFromModelId: "",
            remoteRetryToModelId: "",
            remoteRetryReasonCode: "",
            source: "test"
        )

        let action = try #require(
            ProjectCoderExecutionStatusPrimaryActionResolver.resolve(
                configuredModelId: "openai/gpt-5.4",
                snapshot: snapshot,
                hubConnected: true,
                language: .simplifiedChinese
            )
        )

        #expect(action.kind == .openGovernanceOverview)
        #expect(action.title == "治理总览")
        #expect(action.helpText.contains("grant / governance 面还没就绪"))
        #expect(action.helpText.contains("修复方向：先检查 trusted automation、permission owner、kill-switch、TTL 和当前项目绑定。"))
    }

    @Test
    func primaryActionKeepsOfflineSupervisorRouteBlockerOnDiagnostics() throws {
        let snapshot = AXRoleExecutionSnapshot(
            role: .coder,
            updatedAt: 42,
            stage: "reply",
            requestedModelId: "openai/gpt-5.4",
            actualModelId: "",
            runtimeProvider: "Hub (Remote)",
            executionPath: "remote_error",
            fallbackReasonCode: "preferred_device_offline",
            auditRef: "audit-primary-action-supervisor-route",
            denyCode: "",
            remoteRetryAttempted: false,
            remoteRetryFromModelId: "",
            remoteRetryToModelId: "",
            remoteRetryReasonCode: "",
            source: "test"
        )

        let action = try #require(
            ProjectCoderExecutionStatusPrimaryActionResolver.resolve(
                configuredModelId: "openai/gpt-5.4",
                snapshot: snapshot,
                hubConnected: false,
                language: .simplifiedChinese
            )
        )

        #expect(action.kind == .openDiagnostics)
        #expect(action.title == "XT Diagnostics")
    }

    @Test
    func primaryActionRoutesOfflineNoRecordToDiagnostics() throws {
        let action = try #require(
            ProjectCoderExecutionStatusPrimaryActionResolver.resolve(
                configuredModelId: "openai/gpt-5.4",
                snapshot: .empty(role: .coder, source: "test"),
                hubConnected: false,
                language: .simplifiedChinese
            )
        )

        #expect(action.kind == .openDiagnostics)
        #expect(action.title == "XT Diagnostics")
    }

    @Test
    func governanceOpenDetailIncludesSupervisorGrantExplainability() throws {
        let snapshot = AXRoleExecutionSnapshot(
            role: .coder,
            updatedAt: 42,
            stage: "reply",
            requestedModelId: "openai/gpt-5.4",
            actualModelId: "qwen3-17b-mlx-bf16",
            runtimeProvider: "Hub (Local)",
            executionPath: "local_fallback_after_remote_error",
            fallbackReasonCode: "provider_not_ready",
            auditRef: "audit-primary-action-supervisor-grant-detail",
            denyCode: "device_permission_owner_missing",
            remoteRetryAttempted: false,
            remoteRetryFromModelId: "",
            remoteRetryToModelId: "",
            remoteRetryReasonCode: "",
            source: "test"
        )

        let detail = try #require(
            ProjectCoderExecutionStatusPrimaryActionResolver.governanceOpenDetail(
                snapshot: snapshot,
                governanceInterception: nil,
                language: .simplifiedChinese
            )
        )

        #expect(detail.contains("grant / governance 面还没就绪"))
        #expect(detail.contains("blocked_plane=grant_ready"))
        #expect(detail.contains("deny_code=device_permission_owner_missing"))
        #expect(detail.contains("audit_ref=audit-primary-action-supervisor-grant-detail"))
        #expect(detail.contains("repair_direction=先检查 trusted automation、permission owner、kill-switch、TTL 和当前项目绑定。"))
    }

    @Test
    func governanceOpenDetailPreservesInterceptionEvidenceWhenSupervisorHintExists() throws {
        let snapshot = AXRoleExecutionSnapshot(
            role: .coder,
            updatedAt: 42,
            stage: "reply",
            requestedModelId: "openai/gpt-5.4",
            actualModelId: "qwen3-17b-mlx-bf16",
            runtimeProvider: "Hub (Local)",
            executionPath: "local_fallback_after_remote_error",
            fallbackReasonCode: "provider_not_ready",
            auditRef: "audit-primary-action-governance-merge",
            denyCode: "device_permission_owner_missing",
            remoteRetryAttempted: false,
            remoteRetryFromModelId: "",
            remoteRetryToModelId: "",
            remoteRetryReasonCode: "",
            source: "test"
        )
        let governanceInterception = try #require(
            ProjectGovernanceInterceptionPresentation.make(
                from: ProjectSkillActivityItem(
                    requestID: "skill-governance-action-merge-1",
                    skillID: "agent-browser",
                    toolName: "device.browser.control",
                    status: "blocked",
                    createdAt: 42,
                    resolutionSource: "test",
                    toolArgs: [:],
                    resultSummary: "",
                    detail: "",
                    denyCode: "governance_capability_denied",
                    authorizationDisposition: "deny",
                    policySource: "project_governance",
                    policyReason: "execution_tier_missing_browser_runtime",
                    governanceTruth: "治理真相：当前生效 A1/S2 · 审查 周期。",
                    governanceReason: "当前项目 A-Tier 不允许浏览器自动化。",
                    blockedSummary: "当前项目 A-Tier 不允许浏览器自动化。 打开项目设置 -> A-Tier，把档位提升到 A4 Agent 或更高后，再使用浏览器自动化。",
                    repairAction: "打开 A-Tier：把项目 A-Tier 提升到 A4 Agent。"
                )
            )
        )

        let detail = try #require(
            ProjectCoderExecutionStatusPrimaryActionResolver.governanceOpenDetail(
                snapshot: snapshot,
                governanceInterception: governanceInterception,
                language: .simplifiedChinese
            )
        )

        #expect(detail.contains("最近治理拦截：当前项目 A-Tier 不允许浏览器自动化。") == true)
        #expect(detail.contains("治理真相：当前生效 A1/S2 · 审查 周期。") == true)
        #expect(detail.contains("policy_reason=execution_tier_missing_browser_runtime") == true)
        #expect(detail.contains("repair_action=打开 A-Tier"))
        #expect(detail.contains("blocked_plane=grant_ready"))
        #expect(detail.contains("deny_code=device_permission_owner_missing"))
        #expect(detail.contains("repair_direction=先检查 trusted automation、permission owner、kill-switch、TTL 和当前项目绑定。"))
    }
}
