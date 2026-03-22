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
                    routingExplanation: "requested entrypoint browser.open converged to preferred builtin guarded-automation · resolved action open"
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
        #expect(presentation.items[1].nextSafeActionText == "安全下一步： open_hub_grants · actions=approve hub grant")
        #expect(presentation.items[2].actionLabel == "打开审批")
        #expect(presentation.items[2].detail.contains("browser.open -> guarded-automation"))
        #expect(presentation.items[2].contractText?.contains("浏览器入口会先收敛到受治理内建 guarded-automation 再执行") == true)
        #expect(presentation.items[3].title == "授权处理")
        #expect(presentation.items[3].badgeText == "排队中")
        #expect(presentation.items[3].contractText == "合同： 授权处理 · blocker=grant_pending")
        #expect(presentation.items[3].nextSafeActionText == "安全下一步： open_hub_grants")
        #expect(presentation.items[3].actionLabel == "打开记录")
        #expect(presentation.items[3].actionURL?.contains("focus=skill_record") == true)
        #expect(presentation.items[4].title == "官方技能跟进")
        #expect(presentation.items[4].summary.contains("blocker_detected"))
        #expect(presentation.items[4].contractText == nil)
        #expect(presentation.items[4].nextSafeActionText == nil)
        #expect(presentation.items[4].actionLabel == "打开 Supervisor")
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
}
