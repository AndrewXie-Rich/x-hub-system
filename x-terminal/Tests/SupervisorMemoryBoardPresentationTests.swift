import Foundation
import Testing
@testable import XTerminal

struct SupervisorMemoryBoardPresentationTests {

    @Test
    func mapBuildsReadyBoardWithRowsAndPreviewExcerpt() {
        let readiness = SupervisorMemoryAssemblyReadiness(
            ready: true,
            statusLine: "ready · enough context",
            issues: []
        )
        let snapshot = SupervisorMemoryAssemblySnapshot(
            source: "hub",
            resolutionSource: "hub_memory",
            updatedAt: 1,
            reviewLevelHint: "r2_strategic",
            requestedProfile: "balanced",
            profileFloor: "balanced",
            resolvedProfile: "balanced",
            attemptedProfiles: ["balanced"],
            progressiveUpgradeCount: 0,
            focusedProjectId: "project-alpha",
            selectedSections: ["l1_canonical", "l3_working_set"],
            omittedSections: [],
            contextRefsSelected: 2,
            contextRefsOmitted: 0,
            evidenceItemsSelected: 1,
            evidenceItemsOmitted: 0,
            budgetTotalTokens: 1200,
            usedTotalTokens: 600,
            truncatedLayers: [],
            freshness: "fresh",
            cacheHit: false,
            denyCode: nil,
            downgradeCode: nil,
            reasonCode: nil,
            compressionPolicy: "balanced"
        )
        let registryItem = SupervisorSkillRegistryItem(
            skillId: "agent-browser",
            displayName: "Agent Browser",
            description: "Drive the browser for navigation and form filling",
            capabilitiesRequired: ["browser.control"],
            governedDispatch: nil,
            governedDispatchVariants: [],
            governedDispatchNotes: [],
            inputSchemaRef: "schema://in",
            outputSchemaRef: "schema://out",
            sideEffectClass: "browser",
            riskLevel: .high,
            requiresGrant: true,
            policyScope: "project",
            timeoutMs: 30000,
            maxRetries: 2,
            available: true
        )
        let registrySnapshot = SupervisorSkillRegistrySnapshot(
            schemaVersion: SupervisorSkillRegistrySnapshot.currentSchemaVersion,
            projectId: "project-alpha",
            projectName: "Project Alpha",
            updatedAtMs: 1_000,
            memorySource: "hub",
            items: [registryItem],
            auditRef: "audit-1"
        )
        let digest = SupervisorManager.SupervisorMemoryProjectDigest(
            projectId: "project-alpha",
            displayName: "Project Alpha",
            runtimeState: "active",
            source: "hub",
            goal: "Build a governed agent system",
            currentState: "planning",
            nextStep: "Ship the memory board",
            blocker: "(无)",
            updatedAt: 42,
            recentMessageCount: 7
        )
        let preview = String(repeating: "A", count: 820)

        let presentation = SupervisorMemoryBoardPresentationMapper.map(
            statusLine: "memory=hub · projects=1",
            memorySource: "hub",
            replyExecutionMode: "remote_model",
            requestedModelId: "openai/gpt-5.4",
            actualModelId: "openai/gpt-5.4",
            failureReasonCode: "",
            readiness: readiness,
            rawAssemblyStatusLine: "assembly ok",
            afterTurnSummary: nil,
            pendingFollowUpQuestion: "",
            assemblySnapshot: snapshot,
            skillRegistryStatusLine: "registry ok",
            skillRegistrySnapshot: registrySnapshot,
            digests: [digest],
            preview: preview
        )

        #expect(presentation.iconName == "internaldrive.fill")
        #expect(presentation.iconTone == .accent)
        #expect(presentation.statusLine == "已接入 1 个项目摘要 · 来源 Hub 记忆")
        #expect(presentation.modeSourceText == "当前记忆来源：Hub 记忆（Hub durable truth） · 用途：Supervisor 编排")
        #expect(presentation.continuityStatusLine == "本轮已接上连续对话与背景记忆")
        #expect(presentation.continuityDetailLine?.contains("本轮从Hub 记忆（Hub durable truth）带入连续对话与背景记忆。") == true)
        #expect(presentation.continuityDetailLine?.contains("背景深度为 Balanced") == true)
        #expect(presentation.readinessIconName == "checkmark.seal.fill")
        #expect(presentation.readinessTone == .success)
        #expect(presentation.readinessHeadline == "战略复盘记忆已就绪")
        #expect(presentation.followUp == nil)
        #expect(presentation.assemblyDetailLine == "上下文预算：600/1200 tokens")
        #expect(presentation.skillRegistrySectionTitle == "当前项目技能表")
        #expect(presentation.skillRegistryRows.count == 1)
        #expect(presentation.skillRegistryRows[0].badgeText == "grant")
        #expect(presentation.skillRegistryRows[0].routingHintText == "兼容内建：guarded-automation")
        #expect(presentation.digestRows.count == 1)
        #expect(presentation.digestRows[0].updatedText == "更新时间 42")
        #expect(presentation.digestRows[0].blockerText == nil)
        #expect(presentation.previewExcerpt?.count == 801)
        #expect(presentation.emptyStateText == nil)
    }

    @Test
    func skillRegistryRoutingHintSurfacesAliasAndPreferredBuiltinContext() {
        let guarded = SupervisorSkillRegistryItem(
            skillId: "guarded-automation",
            displayName: "Guarded Automation",
            description: "Governed browser automation",
            capabilitiesRequired: ["device.browser.control"],
            governedDispatch: nil,
            governedDispatchVariants: [],
            governedDispatchNotes: [],
            inputSchemaRef: "schema://guarded-in",
            outputSchemaRef: "schema://guarded-out",
            sideEffectClass: "browser",
            riskLevel: .high,
            requiresGrant: true,
            policyScope: "xt_builtin",
            timeoutMs: 30000,
            maxRetries: 2,
            available: true
        )
        let alias = SupervisorSkillRegistryItem(
            skillId: "trusted-automation",
            displayName: "Trusted Automation",
            description: "Alias entry",
            capabilitiesRequired: ["device.browser.control"],
            governedDispatch: nil,
            governedDispatchVariants: [],
            governedDispatchNotes: [],
            inputSchemaRef: "schema://alias-in",
            outputSchemaRef: "schema://alias-out",
            sideEffectClass: "browser",
            riskLevel: .high,
            requiresGrant: true,
            policyScope: "project",
            timeoutMs: 30000,
            maxRetries: 2,
            available: true
        )
        let agentBrowser = SupervisorSkillRegistryItem(
            skillId: "agent-browser",
            displayName: "Agent Browser",
            description: "Wrapper entry",
            capabilitiesRequired: ["device.browser.control"],
            governedDispatch: nil,
            governedDispatchVariants: [],
            governedDispatchNotes: [],
            inputSchemaRef: "schema://agent-in",
            outputSchemaRef: "schema://agent-out",
            sideEffectClass: "browser",
            riskLevel: .high,
            requiresGrant: true,
            policyScope: "project",
            timeoutMs: 30000,
            maxRetries: 2,
            available: true
        )

        let guardedRow = SupervisorMemoryBoardPresentationMapper.skillRegistryRow(guarded)
        let aliasRow = SupervisorMemoryBoardPresentationMapper.skillRegistryRow(alias)
        let agentBrowserRow = SupervisorMemoryBoardPresentationMapper.skillRegistryRow(
            agentBrowser,
            registryItems: [agentBrowser, guarded]
        )

        #expect(guardedRow.routingHintText?.contains("trusted-automation") == true)
        #expect(guardedRow.routingHintText?.contains("browser.open") == true)
        #expect(aliasRow.routingHintText == "别名归一：trusted-automation -> guarded-automation")
        #expect(agentBrowserRow.routingHintText == "优先内建：guarded-automation")
    }

    @Test
    func digestRowHumanizesKnownBlockerCodes() {
        let digest = SupervisorManager.SupervisorMemoryProjectDigest(
            projectId: "project-auth",
            displayName: "Auth Project",
            runtimeState: "blocked",
            source: "hub",
            goal: "Ship remote feature",
            currentState: "waiting",
            nextStep: "Approve grant",
            blocker: "grant_required",
            updatedAt: 10,
            recentMessageCount: 2
        )

        let row = SupervisorMemoryBoardPresentationMapper.digestRow(digest)

        #expect(row.blockerText == "阻塞：Hub 授权未完成（grant_required）")
    }

    @Test
    func mapBuildsUnderfedBoardWithFollowUpIssuesAndEmptyState() {
        let readiness = SupervisorMemoryAssemblyReadiness(
            ready: false,
            statusLine: "underfed:missing_anchor",
            issues: [
                SupervisorMemoryAssemblyIssue(
                    code: "missing_anchor",
                    severity: .blocking,
                    summary: "Missing strategic anchor",
                    detail: "focused review omitted the longterm outline"
                ),
                SupervisorMemoryAssemblyIssue(
                    code: "missing_evidence",
                    severity: .warning,
                    summary: "Missing evidence",
                    detail: "no evidence refs selected"
                )
            ]
        )

        let presentation = SupervisorMemoryBoardPresentationMapper.map(
            statusLine: "memory=(none)",
            memorySource: "",
            replyExecutionMode: "local_direct_reply",
            requestedModelId: "",
            actualModelId: "",
            failureReasonCode: "",
            readiness: readiness,
            rawAssemblyStatusLine: "assembly degraded",
            afterTurnSummary: nil,
            pendingFollowUpQuestion: "核心业务目标是什么？",
            assemblySnapshot: nil,
            skillRegistryStatusLine: "registry unavailable",
            skillRegistrySnapshot: nil,
            digests: [],
            preview: ""
        )

        #expect(presentation.iconName == "memorychip")
        #expect(presentation.iconTone == .neutral)
        #expect(presentation.modeSourceText == "当前记忆来源：暂无 · 用途：Supervisor 编排")
        #expect(presentation.continuityStatusLine == "本轮走本地直答，没有调用远端模型")
        #expect(presentation.continuityDetailLine == "这一轮没有把连续对话记忆送进主模型。")
        #expect(presentation.readinessIconName == "exclamationmark.triangle.fill")
        #expect(presentation.readinessTone == .danger)
        #expect(presentation.readinessHeadline == "战略复盘记忆还差 2 项")
        #expect(presentation.followUp?.questionText == "还缺这项项目背景：核心业务目标是什么？")
        #expect(presentation.issueSectionTitle == "需要补的背景")
        #expect(presentation.issues.map(\.severityText) == ["BLOCKING", "WARNING"])
        #expect(presentation.issues.map(\.severityTone) == [.danger, .warning])
        #expect(presentation.skillRegistryRows.isEmpty)
        #expect(presentation.digestRows.isEmpty)
        #expect(presentation.emptyStateText == "当前还没有可展示的项目记忆摘要。创建项目或等待系统完成第一次记忆同步后，这里会显示项目总览。")
        #expect(presentation.previewExcerpt == nil)
    }

    @Test
    func previewExcerptAndUpdatedTextHelpersBehaveDeterministically() {
        #expect(SupervisorMemoryBoardPresentationMapper.previewExcerpt("   ") == nil)
        #expect(SupervisorMemoryBoardPresentationMapper.previewExcerpt("abc", maxChars: 5) == "abc")
        #expect(SupervisorMemoryBoardPresentationMapper.previewExcerpt("abcdef", maxChars: 5) == "abcde…")
        #expect(SupervisorMemoryBoardPresentationMapper.updatedText(0) == "updated=(none)")
        #expect(SupervisorMemoryBoardPresentationMapper.updatedText(12.9) == "updated=12")
    }

    @Test
    func continuityHelpersExplainFallbackAndFailureReason() {
        let snapshot = SupervisorMemoryAssemblySnapshot(
            source: "local_fallback",
            resolutionSource: "local",
            updatedAt: 1,
            reviewLevelHint: "r1_pulse",
            requestedProfile: "m1_execute",
            profileFloor: "m1_execute",
            resolvedProfile: "m1_execute",
            attemptedProfiles: ["m1_execute"],
            progressiveUpgradeCount: 0,
            focusedProjectId: nil,
            selectedSections: ["portfolio_brief", "l3_working_set"],
            omittedSections: [],
            contextRefsSelected: 0,
            contextRefsOmitted: 0,
            evidenceItemsSelected: 0,
            evidenceItemsOmitted: 0,
            budgetTotalTokens: nil,
            usedTotalTokens: nil,
            truncatedLayers: [],
            freshness: nil,
            cacheHit: nil,
            denyCode: nil,
            downgradeCode: nil,
            reasonCode: nil,
            compressionPolicy: "protect_anchor_then_delta_then_portfolio"
        )

        let status = SupervisorMemoryBoardPresentationMapper.continuityStatusLine(
            replyExecutionMode: "local_fallback_after_remote_error"
        )
        let detail = SupervisorMemoryBoardPresentationMapper.continuityDetailLine(
            memorySource: "local_fallback",
            replyExecutionMode: "local_fallback_after_remote_error",
            requestedModelId: "openai/gpt-5.4",
            actualModelId: "",
            failureReasonCode: "runtime_not_running",
            assemblySnapshot: snapshot
        )

        #expect(status == "远端失败后，已带着记忆回退到本地回复")
        #expect(detail?.contains("本轮从本地 fallback（Hub 不可用时兜底）带入连续对话与背景记忆。") == true)
        #expect(detail?.contains("背景深度为 Execute") == true)
        #expect(detail?.contains("远端模型当前未运行") == true)
    }

    @Test
    func continuityHelpersExplainHubSideDowngradeToLocal() {
        let snapshot = SupervisorMemoryAssemblySnapshot(
            source: "hub",
            resolutionSource: "hub",
            updatedAt: 1,
            reviewLevelHint: "r1_pulse",
            requestedProfile: "m1_execute",
            profileFloor: "m1_execute",
            resolvedProfile: "m1_execute",
            attemptedProfiles: ["m1_execute"],
            progressiveUpgradeCount: 0,
            focusedProjectId: nil,
            selectedSections: ["portfolio_brief", "l3_working_set"],
            omittedSections: [],
            contextRefsSelected: 0,
            contextRefsOmitted: 0,
            evidenceItemsSelected: 0,
            evidenceItemsOmitted: 0,
            budgetTotalTokens: nil,
            usedTotalTokens: nil,
            truncatedLayers: [],
            freshness: nil,
            cacheHit: nil,
            denyCode: nil,
            downgradeCode: nil,
            reasonCode: nil,
            compressionPolicy: "protect_anchor_then_delta_then_portfolio"
        )

        let status = SupervisorMemoryBoardPresentationMapper.continuityStatusLine(
            replyExecutionMode: "hub_downgraded_to_local"
        )
        let detail = SupervisorMemoryBoardPresentationMapper.continuityDetailLine(
            memorySource: "hub",
            replyExecutionMode: "hub_downgraded_to_local",
            requestedModelId: "openai/gpt-5.4",
            actualModelId: "qwen3-14b-mlx",
            failureReasonCode: "downgrade_to_local",
            assemblySnapshot: snapshot
        )

        #expect(status == "远端请求被降到本地，但仍带着记忆继续回复")
        #expect(detail?.contains("本轮从Hub 记忆（Hub durable truth）带入连续对话与背景记忆。") == true)
        #expect(detail?.contains("背景深度为 Execute") == true)
        #expect(detail?.contains("Hub 在执行阶段把远端请求降到了本地") == true)
    }

    @Test
    func continuityHelpersExplainRemoteSnapshotCacheProvenance() {
        let snapshot = SupervisorMemoryAssemblySnapshot(
            source: "hub",
            resolutionSource: "hub",
            updatedAt: 1,
            reviewLevelHint: "r1_pulse",
            requestedProfile: "m1_execute",
            profileFloor: "m1_execute",
            resolvedProfile: "m1_execute",
            attemptedProfiles: ["m1_execute"],
            progressiveUpgradeCount: 0,
            focusedProjectId: nil,
            rawWindowFloorPairs: 8,
            rawWindowSelectedPairs: 10,
            continuityFloorSatisfied: true,
            selectedSections: ["dialogue_window", "portfolio_brief"],
            omittedSections: [],
            contextRefsSelected: 0,
            contextRefsOmitted: 0,
            evidenceItemsSelected: 0,
            evidenceItemsOmitted: 0,
            budgetTotalTokens: nil,
            usedTotalTokens: nil,
            truncatedLayers: [],
            freshness: "ttl_cache",
            cacheHit: true,
            remoteSnapshotCacheScope: "mode=supervisor_orchestration project_id=(none)",
            remoteSnapshotAgeMs: 6_000,
            remoteSnapshotTTLRemainingMs: 9_000,
            denyCode: nil,
            downgradeCode: nil,
            reasonCode: nil,
            compressionPolicy: "protect_anchor_then_delta_then_portfolio"
        )

        let detail = SupervisorMemoryBoardPresentationMapper.continuityDetailLine(
            memorySource: "hub",
            replyExecutionMode: "remote_model",
            requestedModelId: "openai/gpt-5.4",
            actualModelId: "openai/gpt-5.4",
            failureReasonCode: "",
            assemblySnapshot: snapshot
        )

        #expect(detail?.contains("连续性快照：remote snapshot TTL cache") == true)
        #expect(detail?.contains("age 6s") == true)
        #expect(detail?.contains("ttl_left 9s") == true)
        #expect(detail?.contains("mode=supervisor_orchestration project_id=(none)") == true)
    }

    @Test
    func continuityHelpersSurfaceLowSignalDropsAndRollingDigest() {
        let snapshot = SupervisorMemoryAssemblySnapshot(
            source: "hub",
            resolutionSource: "hub",
            updatedAt: 1,
            reviewLevelHint: "r1_pulse",
            requestedProfile: "m1_execute",
            profileFloor: "m1_execute",
            resolvedProfile: "m1_execute",
            attemptedProfiles: ["m1_execute"],
            progressiveUpgradeCount: 0,
            focusedProjectId: nil,
            rawWindowProfile: "standard_12_pairs",
            rawWindowFloorPairs: 8,
            rawWindowCeilingPairs: 12,
            rawWindowSelectedPairs: 12,
            eligibleMessages: 24,
            lowSignalDroppedMessages: 4,
            rawWindowSource: "xt_cache",
            rollingDigestPresent: true,
            continuityFloorSatisfied: true,
            truncationAfterFloor: false,
            continuityTraceLines: [
                "remote_continuity=fallback reason=remote_route_not_preferred assembled_source=xt_cache",
                "selection raw_profile=standard_12_pairs available_eligible=24 selected_eligible=24 selected_pairs=12 floor_pairs=8 ceiling_pairs=12"
            ],
            lowSignalDropSampleLines: [
                "role=user reason=pure_ack_or_greeting text=你好",
                "role=assistant reason=pure_ack_or_greeting text=收到"
            ],
            selectedSections: ["dialogue_window", "personal_capsule"],
            omittedSections: [],
            contextRefsSelected: 0,
            contextRefsOmitted: 0,
            evidenceItemsSelected: 0,
            evidenceItemsOmitted: 0,
            budgetTotalTokens: nil,
            usedTotalTokens: nil,
            truncatedLayers: [],
            freshness: nil,
            cacheHit: nil,
            denyCode: nil,
            downgradeCode: nil,
            reasonCode: nil,
            compressionPolicy: "protect_anchor_then_delta_then_portfolio"
        )

        let detail = SupervisorMemoryBoardPresentationMapper.continuityDetailLine(
            memorySource: "hub",
            replyExecutionMode: "remote_model",
            requestedModelId: "openai/gpt-5.4",
            actualModelId: "openai/gpt-5.4",
            failureReasonCode: "",
            assemblySnapshot: snapshot
        )
        let presentation = SupervisorMemoryBoardPresentationMapper.map(
            statusLine: "memory=hub",
            memorySource: "hub",
            replyExecutionMode: "remote_model",
            requestedModelId: "openai/gpt-5.4",
            actualModelId: "openai/gpt-5.4",
            failureReasonCode: "",
            readiness: SupervisorMemoryAssemblyReadiness(ready: true, statusLine: "ready", issues: []),
            rawAssemblyStatusLine: "assembly ok",
            afterTurnSummary: nil,
            pendingFollowUpQuestion: "",
            assemblySnapshot: snapshot,
            skillRegistryStatusLine: "skills=none",
            skillRegistrySnapshot: nil,
            digests: [],
            preview: ""
        )

        #expect(detail?.contains("最近原始对话保留 12 组") == true)
        #expect(detail?.contains("背景深度为 Execute") == true)
        #expect(snapshot.continuityDrillDownLines.contains(where: { $0.contains("low_signal_samples:") }))
        #expect(presentation.continuityDrillDownLines.contains(where: { $0.contains("最近原始对话保留 12 组") }))
        #expect(presentation.continuityDrillDownLines.contains(where: { $0.contains("过滤了 4 条低信号寒暄") }))
        #expect(presentation.continuityDrillDownLines.contains(where: { $0.contains("保留了滚动摘要") }))
    }

    @Test
    func continuityHelpersSurfaceScopedHiddenProjectRecovery() {
        let snapshot = SupervisorMemoryAssemblySnapshot(
            source: "hub",
            resolutionSource: "hub",
            updatedAt: 1,
            reviewLevelHint: "r2_strategic",
            requestedProfile: "m3_deep_dive",
            profileFloor: "m3_deep_dive",
            resolvedProfile: "m3_deep_dive",
            attemptedProfiles: ["m3_deep_dive"],
            progressiveUpgradeCount: 0,
            focusedProjectId: "project-hidden",
            rawWindowProfile: "standard_12_pairs",
            rawWindowFloorPairs: 8,
            rawWindowCeilingPairs: 12,
            rawWindowSelectedPairs: 8,
            eligibleMessages: 16,
            lowSignalDroppedMessages: 0,
            rawWindowSource: "mixed",
            rollingDigestPresent: false,
            continuityFloorSatisfied: true,
            truncationAfterFloor: false,
            continuityTraceLines: [],
            lowSignalDropSampleLines: [],
            selectedSections: ["dialogue_window", "focused_project_anchor_pack", "l2_observations", "l3_working_set"],
            omittedSections: [],
            contextRefsSelected: 1,
            contextRefsOmitted: 0,
            evidenceItemsSelected: 1,
            evidenceItemsOmitted: 0,
            budgetTotalTokens: 1200,
            usedTotalTokens: 700,
            truncatedLayers: [],
            freshness: "fresh_remote",
            cacheHit: false,
            denyCode: nil,
            downgradeCode: nil,
            reasonCode: nil,
            compressionPolicy: "balanced",
            scopedPromptRecoveryMode: "explicit_hidden_project_focus",
            scopedPromptRecoverySections: [
                "l1_canonical.focused_project_anchor_pack",
                "l2_observations.project_recent_events",
                "l3_working_set.project_activity_memory",
                "dialogue_window.project_recent_context"
            ]
        )

        let detail = SupervisorMemoryBoardPresentationMapper.continuityDetailLine(
            memorySource: "hub",
            replyExecutionMode: "remote_model",
            requestedModelId: "openai/gpt-5.4",
            actualModelId: "openai/gpt-5.4",
            failureReasonCode: "",
            assemblySnapshot: snapshot
        )
        let presentation = SupervisorMemoryBoardPresentationMapper.map(
            statusLine: "memory=hub",
            memorySource: "hub",
            replyExecutionMode: "remote_model",
            requestedModelId: "openai/gpt-5.4",
            actualModelId: "openai/gpt-5.4",
            failureReasonCode: "",
            readiness: SupervisorMemoryAssemblyReadiness(ready: true, statusLine: "ready", issues: []),
            rawAssemblyStatusLine: "assembly ok",
            afterTurnSummary: nil,
            pendingFollowUpQuestion: "",
            assemblySnapshot: snapshot,
            skillRegistryStatusLine: "skills=none",
            skillRegistrySnapshot: nil,
            digests: [],
            preview: ""
        )

        #expect(snapshot.scopedPromptRecoveryHumanLine?.contains("显式 hidden project 恢复") == true)
        #expect(snapshot.continuityDrillDownLines.contains(where: { $0.contains("scoped_prompt_recovery:") }))
        #expect(detail?.contains("显式 hidden project 恢复") == true)
        #expect(detail?.contains("当前项目摘要") == true)
        #expect(presentation.assemblyDetailLine?.contains("显式 hidden project 恢复") == true)
        #expect(presentation.continuityDrillDownLines.contains(where: { $0.contains("显式 hidden project 恢复") }))
    }

    @Test
    func assemblyDetailLineSurfacesActualizedServingObjectsAndContractScopedGaps() {
        let snapshot = SupervisorMemoryAssemblySnapshot(
            source: "hub",
            resolutionSource: "hub",
            updatedAt: 1,
            reviewLevelHint: "r2_strategic",
            requestedProfile: "m3_deep_dive",
            profileFloor: "m2_plan_review",
            resolvedProfile: "m3_deep_dive",
            attemptedProfiles: ["m3_deep_dive"],
            progressiveUpgradeCount: 0,
            focusedProjectId: "project-alpha",
            selectedSections: [
                "dialogue_window",
                "focused_project_anchor_pack",
                "cross_link_refs",
            ],
            omittedSections: ["evidence_pack"],
            servingObjectContract: [
                "dialogue_window",
                "focused_project_anchor_pack",
                "cross_link_refs",
                "evidence_pack",
            ],
            contextRefsSelected: 1,
            contextRefsOmitted: 0,
            evidenceItemsSelected: 0,
            evidenceItemsOmitted: 2,
            budgetTotalTokens: 1200,
            usedTotalTokens: 640,
            truncatedLayers: [],
            freshness: "fresh_remote",
            cacheHit: false,
            denyCode: nil,
            downgradeCode: nil,
            reasonCode: nil,
            compressionPolicy: "balanced",
            memoryAssemblyResolution: XTMemoryAssemblyResolution(
                role: .supervisor,
                dominantMode: SupervisorTurnMode.hybrid.rawValue,
                trigger: "heartbeat_no_progress_review",
                configuredDepth: XTSupervisorReviewMemoryDepthProfile.auto.rawValue,
                recommendedDepth: XTSupervisorReviewMemoryDepthProfile.deepDive.rawValue,
                effectiveDepth: XTSupervisorReviewMemoryDepthProfile.deepDive.rawValue,
                ceilingFromTier: XTMemoryServingProfile.m3DeepDive.rawValue,
                ceilingHit: false,
                selectedSlots: [
                    "recent_raw_dialogue_window",
                    "focused_project_anchor_pack",
                    "delta_feed",
                    "evidence_pack",
                ],
                selectedPlanes: ["continuity_lane", "project_plane", "cross_link_plane"],
                selectedServingObjects: [
                    "recent_raw_dialogue_window",
                    "focused_project_anchor_pack",
                    "delta_feed",
                    "evidence_pack",
                ],
                excludedBlocks: []
            )
        )

        let detail = SupervisorMemoryBoardPresentationMapper.map(
            statusLine: "memory=hub",
            memorySource: "hub",
            replyExecutionMode: "remote_model",
            requestedModelId: "openai/gpt-5.4",
            actualModelId: "openai/gpt-5.4",
            failureReasonCode: "",
            readiness: SupervisorMemoryAssemblyReadiness(ready: true, statusLine: "ready", issues: []),
            rawAssemblyStatusLine: "assembly ok",
            afterTurnSummary: nil,
            pendingFollowUpQuestion: "",
            assemblySnapshot: snapshot,
            skillRegistryStatusLine: "skills=none",
            skillRegistrySnapshot: nil,
            digests: [],
            preview: ""
        ).assemblyDetailLine

        #expect(detail?.contains("实际带入：最近对话、当前项目摘要、关联线索") == true)
        #expect(detail?.contains("本轮缺口：执行证据") == true)
        #expect(detail?.contains("未带入：执行证据") == true)
    }

    @Test
    func afterTurnPresentationMapsTrendAndDetails() {
        let summary = SupervisorManager.SupervisorAfterTurnDerivedSummary(
            replySource: "personal_memory_capture",
            trend: .increased,
            hasOverdueItems: false,
            reviewDueCount: 1,
            reviewOverdueCount: 0,
            followUpOpenCount: 2,
            followUpOverdueCount: 0,
            statusLine: "Latest after-turn: reviews 1 due (+1) · follow-ups 2 open (+1) · backlog increased",
            detailLines: [
                "New reviews: Morning Brief (2026-03-17)",
                "New follow-ups: Reply to Alex · Alex"
            ],
            debugLine: "trend=increased"
        )

        let presentation = SupervisorMemoryBoardPresentationMapper.afterTurnPresentation(summary)

        #expect(presentation?.iconName == "arrow.up.right.circle.fill")
        #expect(presentation?.tone == .warning)
        #expect(presentation?.title == "回合后整理")
        #expect(presentation?.statusLine.contains("backlog increased") == true)
        #expect(presentation?.detailLines == summary.detailLines)
    }

    @Test
    func mapBuildsTaskRouteExplainabilityCardWhenRouteContextExists() {
        let readiness = SupervisorMemoryAssemblyReadiness(
            ready: true,
            statusLine: "ready",
            issues: []
        )

        let routeContext = SupervisorModelRouteContext(
            projectName: "Alpha",
            decision: SupervisorModelRouteDecision(
                projectID: "proj-alpha",
                role: .coder,
                taskTags: ["codegen", "runtime_fix"],
                risk: .medium,
                sideEffect: .localMutation,
                codeExecution: true,
                preferredModelClasses: [.paidCoder, .localCodegen],
                fallbackOrder: [.paidCoder, .localReasoner],
                grantPolicy: .projectPolicyRequired,
                hubPolicyRequired: false,
                matchedRouteTags: ["codegen"],
                projectModelHints: ["openai/gpt-coder", "local/writer"],
                explainability: SupervisorModelRouteExplainability(
                    whyRole: "Matched codegen to coder.",
                    whyPreferredModelClasses: "Coder route prefers coding models.",
                    whyHubStillDecides: "Hub still arbitrates concrete model selection.",
                    matchedSignals: ["task_tag:codegen", "code_exec:true"],
                    classifierReasons: ["matched_explicit_role_tags:coder"]
                )
            )
        )

        let presentation = SupervisorMemoryBoardPresentationMapper.map(
            statusLine: "memory=hub · projects=1",
            memorySource: "hub",
            replyExecutionMode: "remote_model",
            requestedModelId: "openai/gpt-5.4",
            actualModelId: "openai/gpt-5.4",
            failureReasonCode: "",
            readiness: readiness,
            rawAssemblyStatusLine: "assembly ok",
            afterTurnSummary: nil,
            pendingFollowUpQuestion: "",
            assemblySnapshot: nil,
            skillRegistryStatusLine: "skills: none",
            skillRegistrySnapshot: nil,
            modelRouteContext: routeContext,
            digests: [],
            preview: ""
        )

        let route = presentation.modelRoute
        #expect(route?.iconName == "curlybraces.square.fill")
        #expect(route?.tone == .warning)
        #expect(route?.statusLine.contains("任务路由：编码 / 实现") == true)
        #expect(route?.statusLine.contains("项目：Alpha") == true)
        #expect(route?.statusLine.contains("授权：需项目治理") == true)
        #expect(route?.detailLines.contains("任务角色：编码 / 实现") == true)
        #expect(route?.detailLines.contains("项目：Alpha") == true)
        #expect(route?.detailLines.contains("命中角色标签：codegen") == true)
        #expect(route?.detailLines.contains("优先模型类：付费编码、本地代码生成") == true)
        #expect(route?.detailLines.contains("回退顺序：付费编码、本地推理") == true)
        #expect(route?.detailLines.contains("授权策略：需项目治理") == true)
        #expect(route?.detailLines.contains("项目模型提示：openai/gpt-coder、local/writer") == true)
        #expect(route?.detailLines.last?.contains("具体模型仍由 Hub") == true)
    }

    @Test
    func mapBuildsTurnExplainabilityWhenRoutingAssemblyAndWritebackExist() {
        let readiness = SupervisorMemoryAssemblyReadiness(
            ready: true,
            statusLine: "ready",
            issues: []
        )

        let presentation = SupervisorMemoryBoardPresentationMapper.map(
            statusLine: "memory=hub · projects=1",
            memorySource: "hub",
            replyExecutionMode: "remote_model",
            requestedModelId: "openai/gpt-5.4",
            actualModelId: "openai/gpt-5.4",
            failureReasonCode: "",
            readiness: readiness,
            rawAssemblyStatusLine: "assembly ok",
            afterTurnSummary: nil,
            pendingFollowUpQuestion: "",
            assemblySnapshot: nil,
            skillRegistryStatusLine: "skills: none",
            skillRegistrySnapshot: nil,
            turnRoutingDecision: SupervisorTurnRoutingDecision(
                mode: .hybrid,
                focusedProjectId: "proj-liangliang",
                focusedProjectName: "亮亮",
                focusedPersonName: "Alex",
                focusedCommitmentId: nil,
                confidence: 0.95,
                routingReasons: ["explicit_project_mention:亮亮", "explicit_person_mention:Alex"]
            ),
            turnContextAssembly: SupervisorTurnContextAssemblyResult(
                turnMode: .hybrid,
                focusPointers: SupervisorFocusPointerState.ActivePointers(
                    currentProjectId: "proj-liangliang",
                    currentPersonName: "Alex",
                    currentCommitmentId: nil,
                    lastTurnMode: .hybrid
                ),
                requestedSlots: [.dialogueWindow, .personalCapsule, .focusedProjectCapsule, .portfolioBrief, .crossLinkRefs, .evidencePack],
                requestedRefs: ["dialogue_window", "personal_capsule", "focused_project_capsule", "portfolio_brief", "cross_link_refs", "evidence_pack"],
                selectedSlots: [.dialogueWindow, .personalCapsule, .focusedProjectCapsule, .portfolioBrief, .crossLinkRefs, .evidencePack],
                selectedRefs: ["dialogue_window", "personal_capsule", "focused_project_capsule", "portfolio_brief", "cross_link_refs", "evidence_pack"],
                omittedSlots: [],
                assemblyReason: ["hybrid_requires_cross_link_refs"],
                dominantPlane: "assistant_plane + project_plane",
                supportingPlanes: ["cross_link_plane", "portfolio_brief"],
                continuityLaneDepth: .full,
                assistantPlaneDepth: .medium,
                projectPlaneDepth: .medium,
                crossLinkPlaneDepth: .full
            ),
            writebackClassification: SupervisorAfterTurnWritebackClassification(
                turnMode: .hybrid,
                candidates: [
                    SupervisorAfterTurnWritebackCandidate(
                        scope: .crossLinkScope,
                        recordType: "person_waiting_on_project",
                        confidence: 0.93,
                        whyPromoted: "person-project dependency is explicit in the current turn",
                        sourceRef: "user_message",
                        auditRef: "audit-cross"
                    )
                ],
                summaryLine: "cross_link_scope"
            ),
            digests: [],
            preview: ""
        )

        #expect(presentation.turnExplainability?.iconName == "link.circle.fill")
        #expect(presentation.turnExplainability?.tone == .warning)
        #expect(presentation.turnExplainability?.statusLine.contains("主要参考：个人记忆 + 项目记忆") == true)
        #expect(presentation.turnExplainability?.statusLine.contains("聚焦项目：亮亮") == true)
        #expect(presentation.turnExplainability?.statusLine.contains("聚焦对象：Alex") == true)
        #expect(presentation.turnExplainability?.detailLines.contains("聚焦项目：亮亮") == true)
        #expect(presentation.turnExplainability?.detailLines.contains("聚焦对象：Alex") == true)
        #expect(presentation.turnExplainability?.detailLines.contains("对话模式：个人 + 项目混合") == true)
        #expect(presentation.turnExplainability?.detailLines.contains("背景重心：个人与项目背景并重") == true)
        #expect(presentation.turnExplainability?.detailLines.contains("背景深度：连续对话 完整 · 个人 中等 · 项目 中等 · 关联 完整") == true)
        #expect(presentation.turnExplainability?.detailLines.contains("预计写回：跨域关联") == true)
        #expect(presentation.turnExplainability?.detailLines.contains("优先写回候选：跨域关联（人物依赖项目）") == true)
        #expect(presentation.turnExplainability?.detailLines.contains("已带入：最近对话、个人摘要、当前项目摘要、项目总览、关联线索、执行证据") == true)
    }

    @Test
    func mapKeepsTurnExplainabilityVisibleDuringLocalFallbackAfterRemoteError() {
        let readiness = SupervisorMemoryAssemblyReadiness(
            ready: true,
            statusLine: "ready",
            issues: []
        )

        let presentation = SupervisorMemoryBoardPresentationMapper.map(
            statusLine: "memory=local_fallback · projects=1",
            memorySource: "local_fallback",
            replyExecutionMode: "local_fallback_after_remote_error",
            requestedModelId: "openai/gpt-5.4",
            actualModelId: "",
            failureReasonCode: "runtime_not_running",
            readiness: readiness,
            rawAssemblyStatusLine: "assembly ok",
            afterTurnSummary: nil,
            pendingFollowUpQuestion: "",
            assemblySnapshot: nil,
            skillRegistryStatusLine: "skills: none",
            skillRegistrySnapshot: nil,
            turnRoutingDecision: SupervisorTurnRoutingDecision(
                mode: .personalFirst,
                focusedProjectId: nil,
                focusedProjectName: nil,
                focusedPersonName: nil,
                focusedCommitmentId: nil,
                confidence: 0.88,
                routingReasons: ["personal_planning_language", "portfolio_review_language"]
            ),
            turnContextAssembly: SupervisorTurnContextAssemblyResult(
                turnMode: .personalFirst,
                focusPointers: SupervisorFocusPointerState.ActivePointers(
                    currentProjectId: nil,
                    currentPersonName: nil,
                    currentCommitmentId: nil,
                    lastTurnMode: .personalFirst
                ),
                requestedSlots: [.dialogueWindow, .personalCapsule, .portfolioBrief],
                requestedRefs: ["dialogue_window", "personal_capsule", "portfolio_brief"],
                selectedSlots: [.dialogueWindow, .personalCapsule, .portfolioBrief],
                selectedRefs: ["dialogue_window", "personal_capsule", "portfolio_brief"],
                omittedSlots: [],
                assemblyReason: ["personal_first_requires_personal_capsule"],
                dominantPlane: "assistant_plane",
                supportingPlanes: ["project_plane", "cross_link_plane(on_demand)", "portfolio_brief"],
                continuityLaneDepth: .full,
                assistantPlaneDepth: .full,
                projectPlaneDepth: .light,
                crossLinkPlaneDepth: .onDemand
            ),
            writebackClassification: SupervisorAfterTurnWritebackClassification(
                turnMode: .personalFirst,
                candidates: [
                    SupervisorAfterTurnWritebackCandidate(
                        scope: .userScope,
                        recordType: "preferred_user_name",
                        confidence: 0.9,
                        whyPromoted: "explicit first-person preference statement",
                        sourceRef: "user_message",
                        auditRef: "audit-user"
                    )
                ],
                summaryLine: "user_scope"
            ),
            digests: [],
            preview: ""
        )

        #expect(presentation.continuityStatusLine == "远端失败后，已带着记忆回退到本地回复")
        #expect(presentation.continuityDetailLine?.contains("远端模型当前未运行") == true)
        #expect(presentation.turnExplainability?.statusLine.contains("主要参考：个人记忆") == true)
        #expect(presentation.turnExplainability?.detailLines.contains("对话模式：个人优先") == true)
        #expect(presentation.turnExplainability?.detailLines.contains("背景重心：个人背景主导") == true)
        #expect(presentation.turnExplainability?.detailLines.contains("背景深度：连续对话 完整 · 个人 完整 · 项目 轻量 · 关联 按需") == true)
        #expect(presentation.turnExplainability?.detailLines.contains("预计写回：个人长期记忆") == true)
        #expect(presentation.turnExplainability?.detailLines.contains("优先写回候选：个人长期记忆（偏好称呼）") == true)
        #expect(presentation.turnExplainability?.detailLines.contains("已带入：最近对话、个人摘要、项目总览") == true)
    }

    @Test
    func continuityDrillDownSurfacesDurableCandidateMirrorState() {
        let snapshot = SupervisorMemoryAssemblySnapshot(
            source: "hub",
            resolutionSource: "hub_memory",
            updatedAt: 1,
            reviewLevelHint: "r2_strategic",
            requestedProfile: "balanced",
            profileFloor: "balanced",
            resolvedProfile: "balanced",
            attemptedProfiles: ["balanced"],
            progressiveUpgradeCount: 0,
            focusedProjectId: "project-alpha",
            rawWindowProfile: "standard_12_pairs",
            rawWindowFloorPairs: 8,
            rawWindowCeilingPairs: 12,
            rawWindowSelectedPairs: 12,
            eligibleMessages: 24,
            lowSignalDroppedMessages: 1,
            rawWindowSource: "mixed",
            rollingDigestPresent: true,
            continuityFloorSatisfied: true,
            truncationAfterFloor: false,
            continuityTraceLines: [],
            lowSignalDropSampleLines: [],
            selectedSections: ["dialogue_window", "focused_project_anchor_pack"],
            omittedSections: [],
            contextRefsSelected: 1,
            contextRefsOmitted: 0,
            evidenceItemsSelected: 1,
            evidenceItemsOmitted: 0,
            budgetTotalTokens: 1200,
            usedTotalTokens: 640,
            truncatedLayers: [],
            freshness: "fresh",
            cacheHit: false,
            denyCode: nil,
            downgradeCode: nil,
            reasonCode: nil,
            compressionPolicy: "balanced",
            durableCandidateMirrorStatus: .hubMirrorFailed,
            durableCandidateMirrorTarget: XTSupervisorDurableCandidateMirror.mirrorTarget,
            durableCandidateMirrorAttempted: true,
            durableCandidateMirrorErrorCode: "remote_route_not_preferred",
            durableCandidateLocalStoreRole: XTSupervisorDurableCandidateMirror.localStoreRole
        )

        let presentation = SupervisorMemoryBoardPresentationMapper.map(
            statusLine: "memory=hub",
            memorySource: "hub",
            replyExecutionMode: "remote_model",
            requestedModelId: "openai/gpt-5.4",
            actualModelId: "openai/gpt-5.4",
            failureReasonCode: "",
            readiness: SupervisorMemoryAssemblyReadiness(ready: true, statusLine: "ready", issues: []),
            rawAssemblyStatusLine: "assembly ok",
            afterTurnSummary: nil,
            pendingFollowUpQuestion: "",
            assemblySnapshot: snapshot,
            skillRegistryStatusLine: "skills=none",
            skillRegistrySnapshot: nil,
            digests: [],
            preview: ""
        )

        #expect(
            snapshot.continuityDrillDownLines.contains {
                $0.contains("durable_candidate_mirror status=hub_mirror_failed")
                    && $0.contains("reason=remote_route_not_preferred")
            }
        )
        #expect(
            presentation.continuityDrillDownLines.contains {
                $0.contains("Hub durable candidate mirror：Hub 镜像失败")
                    && $0.contains("mirror reason：当前远端路由不是首选（remote_route_not_preferred）")
            }
        )
    }

    @Test
    func assemblyDetailShowsRoleAwarePolicyTriplesWhenPresent() throws {
        let snapshot = SupervisorMemoryAssemblySnapshot(
            source: "hub",
            resolutionSource: "hub_memory",
            updatedAt: 1,
            assemblyPurpose: XTSupervisorMemoryAssemblyPurpose.governanceReview.rawValue,
            dominantMode: SupervisorTurnMode.projectFirst.rawValue,
            memoryResolutionTrigger: "manual_full_scan_request",
            triggerSource: "heartbeat",
            governanceReviewTrigger: SupervisorReviewTrigger.periodicPulse.rawValue,
            governanceReviewRunKind: SupervisorReviewRunKind.pulse.rawValue,
            reviewLevelHint: SupervisorReviewLevel.r2Strategic.rawValue,
            requestedProfile: XTMemoryServingProfile.m4FullScan.rawValue,
            profileFloor: XTMemoryServingProfile.m2PlanReview.rawValue,
            resolvedProfile: XTMemoryServingProfile.m2PlanReview.rawValue,
            attemptedProfiles: [XTMemoryServingProfile.m4FullScan.rawValue, XTMemoryServingProfile.m2PlanReview.rawValue],
            progressiveUpgradeCount: 1,
            focusedProjectId: "project-alpha",
            configuredRawWindowProfile: XTSupervisorRecentRawContextProfile.autoMax.rawValue,
            recommendedRawWindowProfile: XTSupervisorRecentRawContextProfile.extended40Pairs.rawValue,
            effectiveRawWindowProfile: XTSupervisorRecentRawContextProfile.extended40Pairs.rawValue,
            configuredReviewMemoryDepth: XTSupervisorReviewMemoryDepthProfile.auto.rawValue,
            recommendedReviewMemoryDepth: XTSupervisorReviewMemoryDepthProfile.deepDive.rawValue,
            effectiveReviewMemoryDepth: XTSupervisorReviewMemoryDepthProfile.planReview.rawValue,
            sTierReviewMemoryCeiling: XTMemoryServingProfile.m2PlanReview.rawValue,
            reviewMemoryCeilingHit: true,
            selectedSections: ["dialogue_window", "portfolio_brief", "focused_project_anchor_pack"],
            omittedSections: [],
            contextRefsSelected: 0,
            contextRefsOmitted: 0,
            evidenceItemsSelected: 0,
            evidenceItemsOmitted: 0,
            budgetTotalTokens: 1200,
            usedTotalTokens: 600,
            truncatedLayers: [],
            freshness: "fresh",
            cacheHit: false,
            denyCode: nil,
            downgradeCode: nil,
            reasonCode: nil,
            compressionPolicy: "balanced"
        )

        let detail = try #require(
            SupervisorMemoryBoardPresentationMapper.map(
                statusLine: "memory=hub · projects=1",
                memorySource: "hub",
                replyExecutionMode: "remote_model",
                requestedModelId: "openai/gpt-5.4",
                actualModelId: "openai/gpt-5.4",
                failureReasonCode: "",
                readiness: .init(ready: true, statusLine: "ready", issues: []),
                rawAssemblyStatusLine: "assembly ok",
                afterTurnSummary: nil,
                pendingFollowUpQuestion: "",
                assemblySnapshot: snapshot,
                skillRegistryStatusLine: "",
                skillRegistrySnapshot: nil,
                digests: [],
                preview: ""
            ).assemblyDetailLine
        )

        #expect(detail.contains("Assembly Purpose"))
        #expect(detail.contains("Governance Review"))
        #expect(detail.contains("source Heartbeat"))
        #expect(detail.contains("trigger Periodic Pulse"))
        #expect(detail.contains("run kind Pulse"))
        #expect(detail.contains("Recent Raw Context"))
        #expect(detail.contains("configured Auto Max"))
        #expect(detail.contains("Review Memory Depth"))
        #expect(detail.contains("ceiling m2_plan_review"))
        #expect(detail.contains("ceiling hit"))
        #expect(
            snapshot.continuityDrillDownLines.contains {
                $0 == "trigger_source=heartbeat"
            }
        )
        #expect(
            snapshot.continuityDrillDownLines.contains {
                $0 == "governance_review_trigger=periodic_pulse"
            }
        )
        #expect(
            snapshot.continuityDrillDownLines.contains {
                $0 == "governance_review_run_kind=pulse"
            }
        )
    }
}
