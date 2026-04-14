import Foundation
import Testing
@testable import XTerminal

struct SupervisorInfrastructureFeedPresentationTests {

    @Test
    func mapPrioritizesOfficialStatusPendingApprovalsAndActiveInfraEvents() {
        let input = SupervisorInfrastructureFeedInput(
            officialSkillsStatusLine: "official failed skills=12 auto=env err=index_missing",
            officialSkillsTransitionLine: "status_changed: healthy -> failed via env",
            officialSkillsTopBlockersLine: "Top blockers: Secondary Skill (skill.secondary) [blocked]; Agent Browser (agent-browser) [blocked]",
            officialSkillsTopBlockerSummaries: [
                AXOfficialSkillBlockerSummaryItem(
                    packageSHA256: "sha-secondary",
                    title: "Secondary Skill",
                    subtitle: "skill.secondary",
                    stateLabel: "blocked",
                    summaryLine: "version=2.0.0 package=ready risk=medium grant=none",
                    timelineLine: "last_blocked=2026-03-19T11:00:00Z"
                ),
                AXOfficialSkillBlockerSummaryItem(
                    packageSHA256: "sha-agent-browser",
                    title: "Agent Browser",
                    subtitle: "agent-browser",
                    stateLabel: "blocked",
                    summaryLine: "version=2.0.0 package=ready risk=high grant=required",
                    timelineLine: "last_blocked=2026-03-19T12:00:00Z"
                )
            ],
            eventLoopStatusLine: "queued 1",
            pendingHubGrants: [
                SupervisorManager.SupervisorPendingGrant(
                    id: "grant-1",
                    dedupeKey: "grant-1",
                    grantRequestId: "grant-1",
                    requestId: "req-1",
                    projectId: "project-alpha",
                    projectName: "Project Alpha",
                    capability: "web.fetch",
                    modelId: "gpt-5.4",
                    reason: "browser fetch",
                    requestedTtlSec: 3600,
                    requestedTokenCap: 8000,
                    createdAt: 10,
                    actionURL: "x-terminal://grant/grant-1",
                    priorityRank: 1,
                    priorityReason: "active",
                    nextAction: "approve hub grant"
                )
            ],
            pendingSupervisorSkillApprovals: [
                SupervisorManager.SupervisorPendingSkillApproval(
                    id: "approval-1",
                    requestId: "approval-1",
                    projectId: "project-beta",
                    projectName: "Project Beta",
                    jobId: "job-1",
                    planId: "plan-1",
                    stepId: "step-1",
                    skillId: "guarded-automation",
                    requestedSkillId: "browser.open",
                    toolName: ToolName.deviceBrowserControl.rawValue,
                    tool: .deviceBrowserControl,
                    toolSummary: "open https://example.com",
                    reason: "browser open",
                    createdAt: 12,
                    actionURL: "x-terminal://approval/approval-1",
                    routingReasonCode: "preferred_builtin_selected",
                    routingExplanation: "requested entrypoint browser.open converged to preferred builtin guarded-automation · resolved action open",
                    deltaApproval: XTSkillProfileDeltaApproval(
                        schemaVersion: XTSkillProfileDeltaApproval.currentSchemaVersion,
                        requestId: "approval-1",
                        projectId: "project-beta",
                        projectName: "Project Beta",
                        requestedSkillId: "browser.open",
                        effectiveSkillId: "guarded-automation",
                        toolName: ToolName.deviceBrowserControl.rawValue,
                        currentRunnableProfiles: ["observe_only"],
                        requestedProfiles: ["observe_only", "browser_operator"],
                        deltaProfiles: ["browser_operator"],
                        currentRunnableCapabilityFamilies: ["repo.read"],
                        requestedCapabilityFamilies: ["repo.read", "browser.interact"],
                        deltaCapabilityFamilies: ["browser.interact"],
                        grantFloor: XTSkillGrantFloor.privileged.rawValue,
                        approvalFloor: XTSkillApprovalFloor.localApproval.rawValue,
                        requestedTTLSeconds: 900,
                        reason: "browser open",
                        summary: "当前可直接运行：observe_only；本次请求：observe_only, browser_operator；新增放开：browser_operator；grant=privileged；approval=local_approval",
                        disposition: "pending",
                        auditRef: "audit-infra-approval-1"
                    ),
                    readiness: XTSkillExecutionReadiness(
                        schemaVersion: XTSkillExecutionReadiness.currentSchemaVersion,
                        projectId: "project-beta",
                        skillId: "guarded-automation",
                        packageSHA256: String(repeating: "f", count: 64),
                        publisherID: "xt_builtin",
                        policyScope: "xt_builtin",
                        intentFamilies: ["browser.navigate"],
                        capabilityFamilies: ["repo.read", "browser.interact"],
                        capabilityProfiles: ["observe_only", "browser_operator"],
                        discoverabilityState: "discoverable",
                        installabilityState: "installable",
                        pinState: "xt_builtin",
                        resolutionState: "resolved",
                        executionReadiness: XTSkillExecutionReadinessState.localApprovalRequired.rawValue,
                        runnableNow: false,
                        denyCode: "local_approval_required",
                        reasonCode: "approval floor local_approval requires local confirmation",
                        grantFloor: XTSkillGrantFloor.privileged.rawValue,
                        approvalFloor: XTSkillApprovalFloor.localApproval.rawValue,
                        requiredGrantCapabilities: [],
                        requiredRuntimeSurfaces: ["managed_browser_runtime"],
                        stateLabel: XTSkillCapabilityProfileSupport.readinessLabel(XTSkillExecutionReadinessState.localApprovalRequired.rawValue),
                        installHint: "",
                        unblockActions: ["request_local_approval"],
                        auditRef: "audit-infra-readiness-1",
                        doctorAuditRef: "",
                        vetterAuditRef: "",
                        resolvedSnapshotId: "snapshot-infra-approval-1",
                        grantSnapshotRef: ""
                    )
                )
            ],
            recentEventLoopActivities: [
                SupervisorManager.SupervisorEventLoopActivity(
                    id: "loop-1",
                    createdAt: 20,
                    updatedAt: 24,
                    triggerSource: "official_skills_channel",
                    status: "completed",
                    reasonCode: "ok",
                    dedupeKey: "official-1",
                    projectId: "",
                    projectName: "Official Skills Channel",
                    triggerSummary: "blocker_detected · failed · status_changed: healthy -> failed via env",
                    resultSummary: "handled official channel failed",
                    policySummary: "review=Blocker Detected"
                ),
                SupervisorManager.SupervisorEventLoopActivity(
                    id: "loop-2",
                    createdAt: 22,
                    updatedAt: 26,
                    triggerSource: "grant_resolution",
                    status: "queued",
                    reasonCode: "grant_pending",
                    dedupeKey: "grant_resolution:req-1:grant_pending",
                    projectId: "project-alpha",
                    projectName: "Project Alpha",
                    triggerSummary: "user_override · grant approved",
                    resultSummary: "",
                    policySummary: "review=User Override"
                ),
                SupervisorManager.SupervisorEventLoopActivity(
                    id: "loop-3",
                    createdAt: 23,
                    updatedAt: 27,
                    triggerSource: "official_skills_channel",
                    status: "deduped",
                    reasonCode: "duplicate_trigger",
                    dedupeKey: "official-duplicate",
                    projectId: "",
                    projectName: "Official Skills Channel",
                    triggerSummary: "duplicate",
                    resultSummary: "",
                    policySummary: ""
                )
            ]
        )

        let presentation = SupervisorInfrastructureFeedPresentation.map(input: input)

        #expect(presentation.summaryLine.contains("需关注 4 项"))
        #expect(presentation.summaryLine.contains("排队中 1"))
        #expect(presentation.items.count == 5)
        #expect(presentation.items.map(\.kind) == [
            .officialSkillsChannel,
            .pendingHubGrant,
            .pendingSkillApproval,
            .eventLoop,
            .eventLoop
        ])
        #expect(presentation.items[0].badgeText == "降级")
        #expect(presentation.items[0].tone == .critical)
        #expect(presentation.items[0].detail.contains("Top blockers: Secondary Skill (skill.secondary) [blocked]"))
        #expect(presentation.items[0].actionLabel == "处理授权阻塞")
        #expect(presentation.items[0].actionURL?.contains("hub-setup") == true)
        #expect(presentation.items[0].actionURL?.contains("section_id=troubleshoot") == true)
        #expect(presentation.items[1].actionLabel == "打开授权")
        #expect(presentation.items[1].detail.contains("Project Alpha"))
        #expect(presentation.items[1].contractText == "合同： 授权处理 · blocker=web.fetch")
        #expect(presentation.items[1].nextSafeActionText == "安全下一步： 打开 Hub 授权面板 · 建议动作：处理当前 Hub 授权")
        #expect(presentation.items[2].actionLabel == "打开审批")
        #expect(presentation.items[2].detail.contains("browser.open -> guarded-automation · 等待本地审批"))
        #expect(presentation.items[2].contractText?.contains("浏览器入口会先收敛到受治理内建 guarded-automation 再执行") == true)
        #expect(presentation.items[3].title == "授权处理")
        #expect(presentation.items[3].badgeText == "排队中")
        #expect(presentation.items[3].contractText == "合同： 授权处理 · blocker=grant_pending")
        #expect(presentation.items[3].nextSafeActionText == "安全下一步： 打开 Hub 授权面板")
        #expect(presentation.items[3].actionLabel == "打开记录")
        #expect(presentation.items[3].actionURL?.contains("focus=skill_record") == true)
        #expect(presentation.items[4].title == "官方技能跟进")
        #expect(presentation.items[4].summary.contains("blocker_detected"))
        #expect(presentation.items[4].contractText == nil)
        #expect(presentation.items[4].nextSafeActionText == nil)
        #expect(presentation.items[4].actionLabel == "打开 Supervisor")
    }

    @Test
    func mapLabelsGrantBlockedPendingSkillApprovalAsAuthorizationWork() {
        let input = SupervisorInfrastructureFeedInput(
            officialSkillsStatusLine: "",
            officialSkillsTransitionLine: "",
            officialSkillsTopBlockersLine: "",
            eventLoopStatusLine: "idle",
            pendingHubGrants: [],
            pendingSupervisorSkillApprovals: [
                SupervisorManager.SupervisorPendingSkillApproval(
                    id: "approval-grant-1",
                    requestId: "approval-grant-1",
                    projectId: "project-gamma",
                    projectName: "Project Gamma",
                    jobId: "job-grant-1",
                    planId: "plan-grant-1",
                    stepId: "step-grant-1",
                    skillId: "agent-browser",
                    requestedSkillId: "agent-browser.search",
                    toolName: ToolName.deviceBrowserControl.rawValue,
                    tool: .deviceBrowserControl,
                    toolSummary: "open https://example.com",
                    reason: "browser search requires governed authorization",
                    createdAt: 30,
                    actionURL: "x-terminal://approval/approval-grant-1",
                    routingReasonCode: "",
                    routingExplanation: "",
                    deltaApproval: nil,
                    readiness: XTSkillExecutionReadiness(
                        schemaVersion: XTSkillExecutionReadiness.currentSchemaVersion,
                        projectId: "project-gamma",
                        skillId: "agent-browser",
                        packageSHA256: String(repeating: "a", count: 64),
                        publisherID: "official",
                        policyScope: "hub_governed",
                        intentFamilies: ["browser.search"],
                        capabilityFamilies: ["browser.interact"],
                        capabilityProfiles: ["browser_operator"],
                        discoverabilityState: "discoverable",
                        installabilityState: "installable",
                        pinState: "project",
                        resolutionState: "resolved",
                        executionReadiness: XTSkillExecutionReadinessState.grantRequired.rawValue,
                        runnableNow: false,
                        denyCode: "grant_required",
                        reasonCode: "hub grant required before execution",
                        grantFloor: XTSkillGrantFloor.privileged.rawValue,
                        approvalFloor: XTSkillApprovalFloor.none.rawValue,
                        requiredGrantCapabilities: ["device.browser.control"],
                        requiredRuntimeSurfaces: ["managed_browser_runtime"],
                        stateLabel: XTSkillCapabilityProfileSupport.readinessLabel(
                            XTSkillExecutionReadinessState.grantRequired.rawValue
                        ),
                        installHint: "",
                        unblockActions: ["request_hub_grant"],
                        auditRef: "audit-infra-grant-1",
                        doctorAuditRef: "",
                        vetterAuditRef: "",
                        resolvedSnapshotId: "snapshot-infra-grant-1",
                        grantSnapshotRef: "grant-snapshot-infra-1"
                    )
                )
            ],
            recentEventLoopActivities: []
        )

        let presentation = SupervisorInfrastructureFeedPresentation.map(input: input)

        #expect(presentation.summaryLine == "需关注 1 项 · 空闲")
        #expect(presentation.items.count == 1)
        #expect(presentation.items[0].kind == .pendingSkillApproval)
        #expect(presentation.items[0].title == "技能授权待处理")
        #expect(presentation.items[0].badgeText == "待授权")
        #expect(presentation.items[0].detail.contains("Project Gamma"))
        #expect(presentation.items[0].detail.contains("先通过 Hub 授权"))
        #expect(presentation.items[0].contractText == "执行就绪：等待 Hub grant")
        #expect(presentation.items[0].nextSafeActionText == "安全下一步： 先完成 Hub grant，再恢复这次受治理技能调用。")
        #expect(presentation.items[0].actionLabel == "打开授权")
        #expect(presentation.items[0].actionURL?.contains("approval-grant-1") == true)
    }

    @Test
    func mapKeepsHealthyOfficialStatusPassiveWithoutFabricatingAlerts() {
        let input = SupervisorInfrastructureFeedInput(
            officialSkillsStatusLine: "official healthy skills=24 auto=persisted",
            officialSkillsTransitionLine: "current_snapshot_repaired: current snapshot restored via persisted",
            officialSkillsTopBlockersLine: "",
            eventLoopStatusLine: "idle",
            pendingHubGrants: [],
            pendingSupervisorSkillApprovals: [],
            recentEventLoopActivities: []
        )

        let presentation = SupervisorInfrastructureFeedPresentation.map(input: input)

        #expect(presentation.summaryLine.contains("官方技能健康"))
        #expect(presentation.items.count == 1)
        #expect(presentation.items[0].kind == .officialSkillsChannel)
        #expect(presentation.items[0].tone == .success)
        #expect(presentation.items[0].detail.contains("current snapshot restored via persisted"))
        #expect(presentation.items[0].actionLabel == "打开就绪检查")
        #expect(presentation.items[0].actionURL?.contains("hub-setup") == true)
    }

    @Test
    func mapIncludesBuiltinGovernedSkillsItemWhenAvailable() {
        let input = SupervisorInfrastructureFeedInput(
            officialSkillsStatusLine: "",
            officialSkillsTransitionLine: "",
            officialSkillsTopBlockersLine: "",
            builtinGovernedSkills: [
                AXBuiltinGovernedSkillSummary(
                    skillID: "guarded-automation",
                    displayName: "Guarded Automation",
                    summary: "Inspect trusted automation readiness and route governed browser automation through XT gates.",
                    capabilitiesRequired: ["project.snapshot", "browser.read", "device.browser.control"],
                    sideEffectClass: "external_side_effect",
                    riskLevel: "high",
                    policyScope: "xt_builtin"
                ),
                AXBuiltinGovernedSkillSummary(
                    skillID: "supervisor-voice",
                    displayName: "Supervisor Voice",
                    summary: "Inspect and control local supervisor playback.",
                    capabilitiesRequired: ["supervisor.voice.playback"],
                    sideEffectClass: "local_side_effect",
                    riskLevel: "low",
                    policyScope: "xt_builtin"
                )
            ],
            managedSkillsStatusLine: "skills ok",
            eventLoopStatusLine: "idle",
            pendingHubGrants: [],
            pendingSupervisorSkillApprovals: [],
            recentEventLoopActivities: []
        )

        let presentation = SupervisorInfrastructureFeedPresentation.map(input: input)

        #expect(presentation.summaryLine == "被动观察 · 空闲")
        #expect(presentation.items.count == 1)
        #expect(presentation.items[0].kind == .xtBuiltinGovernedSkills)
        #expect(presentation.items[0].title == "XT 内建技能")
        #expect(presentation.items[0].summary == "已就绪 2 个")
        #expect(presentation.items[0].detail.contains("重点技能=guarded-automation, supervisor-voice"))
        #expect(presentation.items[0].detail.contains("托管技能=skills ok"))
        #expect(presentation.items[0].badgeText == "内建")
        #expect(presentation.items[0].tone == .success)
        #expect(presentation.items[0].actionLabel == "打开诊断")
        #expect(presentation.items[0].actionURL?.contains("settings") == true)
        #expect(presentation.items[0].actionURL?.contains("section_id=diagnostics") == true)
    }

    @Test
    func mapIncludesCandidateReviewItemWhenReviewQueueExists() {
        let input = SupervisorInfrastructureFeedInput(
            officialSkillsStatusLine: "",
            officialSkillsTransitionLine: "",
            officialSkillsTopBlockersLine: "",
            eventLoopStatusLine: "idle",
            pendingHubGrants: [],
            pendingSupervisorSkillApprovals: [],
            candidateReviews: [
                HubIPCClient.SupervisorCandidateReviewItem(
                    schemaVersion: "v1",
                    reviewId: "review-1",
                    requestId: "req-1",
                    evidenceRef: "audit://candidate/1",
                    reviewState: "pending_review",
                    durablePromotionState: "candidate_only",
                    promotionBoundary: "project",
                    deviceId: "device-1",
                    userId: "user-1",
                    appId: "xt",
                    threadId: "thread-1",
                    threadKey: "thread-key-1",
                    projectId: "project-alpha",
                    projectIds: [],
                    scopes: ["project_memory"],
                    recordTypes: ["canonical"],
                    auditRefs: [],
                    idempotencyKeys: [],
                    candidateCount: 3,
                    summaryLine: "归并了 3 条候选记忆",
                    mirrorTarget: "xt_local_store",
                    localStoreRole: "cache",
                    carrierKind: "review_bundle",
                    carrierSchemaVersion: "v1",
                    pendingChangeId: "",
                    pendingChangeStatus: "",
                    editSessionId: "",
                    docId: "",
                    writebackRef: "",
                    stageCreatedAtMs: 0,
                    stageUpdatedAtMs: 0,
                    latestEmittedAtMs: 20_000,
                    createdAtMs: 18_000,
                    updatedAtMs: 20_000
                )
            ],
            candidateReviewProjectNamesByID: ["project-alpha": "Project Alpha"],
            recentEventLoopActivities: []
        )

        let presentation = SupervisorInfrastructureFeedPresentation.map(input: input)

        #expect(presentation.summaryLine == "需关注 1 项 · 空闲")
        #expect(presentation.items.count == 1)
        #expect(presentation.items[0].kind == .candidateReview)
        #expect(presentation.items[0].title == "候选记忆审查")
        #expect(presentation.items[0].summary == "待处理 1 项")
        #expect(presentation.items[0].detail.contains("Project Alpha"))
        #expect(presentation.items[0].detail.contains("状态=待转入审查"))
        #expect(presentation.items[0].detail.contains("候选=3"))
        #expect(presentation.items[0].badgeText == "待审查")
        #expect(presentation.items[0].tone == .attention)
        #expect(presentation.items[0].contractText == "合同： 候选记忆审查 · blocker=pending_review")
        #expect(presentation.items[0].nextSafeActionText == "安全下一步： 打开候选记忆审查面板 · 建议动作：转入审查")
        #expect(presentation.items[0].actionLabel == "打开 Supervisor")
        #expect(presentation.items[0].actionURL?.contains("xterminal://supervisor") == true)
        #expect(presentation.items[0].actionURL?.contains("focus=candidate_review") == true)
        #expect(presentation.items[0].actionURL?.contains("request_id=req-1") == true)
    }

    @Test
    func mapIncludesHistoricalProjectBoundaryRepairItemWithSupervisorRerunAction() {
        let input = SupervisorInfrastructureFeedInput(
            officialSkillsStatusLine: "",
            officialSkillsTransitionLine: "",
            officialSkillsTopBlockersLine: "",
            historicalProjectBoundaryRepairStatusLine: "historical_project_boundary_repair=partial reason=load_registry scanned=4 repaired_config=1 repaired_memory=2 failed=1",
            eventLoopStatusLine: "idle",
            pendingHubGrants: [],
            pendingSupervisorSkillApprovals: [],
            recentEventLoopActivities: []
        )

        let presentation = SupervisorInfrastructureFeedPresentation.map(input: input)

        #expect(presentation.summaryLine == "需关注 1 项 · 空闲")
        #expect(presentation.items.count == 1)
        #expect(presentation.items[0].kind == .historicalProjectBoundaryRepair)
        #expect(presentation.items[0].title == "历史项目修复")
        #expect(presentation.items[0].summary == "已补齐 3 处，仍有 1 个项目失败")
        #expect(presentation.items[0].detail.contains("原因=启动时加载项目注册表"))
        #expect(presentation.items[0].detail.contains("扫描=4"))
        #expect(presentation.items[0].detail.contains("补齐 config=1"))
        #expect(presentation.items[0].detail.contains("补齐 memory=2"))
        #expect(presentation.items[0].detail.contains("失败=1"))
        #expect(presentation.items[0].badgeText == "部分完成")
        #expect(presentation.items[0].tone == .attention)
        #expect(presentation.items[0].actionLabel == "重跑修复")
        #expect(presentation.items[0].actionURL?.contains("settings") == true)
        #expect(presentation.items[0].actionURL?.contains("section_id=diagnostics") == true)
        #expect(presentation.items[0].actionURL?.contains("refresh_action=repair_historical_project_boundaries") == true)
        #expect(presentation.items[0].actionURL?.contains("refresh_reason=supervisor_historical_project_boundary_repair") == true)
    }

    @Test
    func mapIncludesGenericHiddenProjectMemoryAssemblyItemWithoutLeakingProjectIdentity() {
        let input = SupervisorInfrastructureFeedInput(
            officialSkillsStatusLine: "",
            officialSkillsTransitionLine: "",
            officialSkillsTopBlockersLine: "",
            historicalProjectBoundaryRepairStatusLine: "",
            memoryReadiness: SupervisorMemoryAssemblyReadiness(
                ready: false,
                statusLine: "underfed:memory_scoped_hidden_project_recovery_missing",
                issues: [
                    SupervisorMemoryAssemblyIssue(
                        code: "memory_scoped_hidden_project_recovery_missing",
                        severity: .blocking,
                        summary: "显式 hidden project 聚焦时没有补回项目范围上下文",
                        detail: "focus=project-hidden"
                    )
                ]
            ),
            memoryAssemblySnapshot: SupervisorMemoryAssemblySnapshot(
                source: "hub",
                resolutionSource: "hub",
                updatedAt: 1,
                reviewLevelHint: SupervisorReviewLevel.r2Strategic.rawValue,
                requestedProfile: XTMemoryServingProfile.m3DeepDive.rawValue,
                profileFloor: XTMemoryServingProfile.m3DeepDive.rawValue,
                resolvedProfile: XTMemoryServingProfile.m3DeepDive.rawValue,
                attemptedProfiles: [XTMemoryServingProfile.m3DeepDive.rawValue],
                progressiveUpgradeCount: 0,
                focusedProjectId: "project-hidden",
                selectedSections: ["l1_canonical", "l2_observations", "l3_working_set", "dialogue_window"],
                omittedSections: [],
                contextRefsSelected: 1,
                contextRefsOmitted: 0,
                evidenceItemsSelected: 1,
                evidenceItemsOmitted: 0,
                budgetTotalTokens: 1200,
                usedTotalTokens: 640,
                truncatedLayers: [],
                freshness: "fresh_remote",
                cacheHit: false,
                denyCode: nil,
                downgradeCode: nil,
                reasonCode: nil,
                compressionPolicy: "balanced",
                scopedPromptRecoveryMode: "explicit_hidden_project_focus",
                scopedPromptRecoverySections: []
            ),
            eventLoopStatusLine: "idle",
            pendingHubGrants: [],
            pendingSupervisorSkillApprovals: [],
            recentEventLoopActivities: []
        )

        let presentation = SupervisorInfrastructureFeedPresentation.map(input: input)

        #expect(presentation.summaryLine == "需关注 1 项 · 空闲")
        #expect(presentation.items.count == 1)
        #expect(presentation.items[0].kind == SupervisorInfrastructureFeedPresentation.Item.Kind.memoryAssembly)
        #expect(presentation.items[0].title == "记忆装配提醒")
        #expect(presentation.items[0].summary == "显式 hidden project 聚焦时没有补回项目范围上下文")
        #expect(presentation.items[0].detail.contains("显式 hidden focus 后仍未补回项目范围上下文"))
        #expect(!presentation.items[0].detail.contains("project-hidden"))
        #expect(presentation.items[0].badgeText == "阻断")
        #expect(presentation.items[0].tone == SupervisorInfrastructureFeedPresentation.Tone.critical)
        #expect(presentation.items[0].contractText == "合同： memory_assembly · blocker=memory_scoped_hidden_project_recovery_missing")
        #expect(presentation.items[0].nextSafeActionText == "安全下一步： 打开诊断并重建 hidden project 记忆")
        #expect(presentation.items[0].actionLabel == "打开诊断")
        #expect(presentation.items[0].actionURL?.contains("section_id=diagnostics") == true)
        #expect(presentation.items[0].actionURL?.contains("refresh_reason=supervisor_infra_hidden_project_scoped_recovery") == true)
    }
}
