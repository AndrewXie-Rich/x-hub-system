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
                    timelineLine: "last_blocked=2026-03-19T12:00:00Z",
                    whyNotRunnable: "waiting for hub grant",
                    unblockActions: ["request_hub_grant", "open_skill_governance_surface"]
                ),
                AXOfficialSkillBlockerSummaryItem(
                    packageSHA256: "sha-calendar-sync",
                    title: "Calendar Skill",
                    subtitle: "calendar-sync",
                    stateLabel: "not installed",
                    summaryLine: "version=1.5.0 package=missing risk=medium grant=none",
                    timelineLine: "updated=2026-03-19T10:00:00Z",
                    whyNotRunnable: "package not pinned into runtime surface",
                    unblockActions: ["install_baseline", "pin_package_project", "pin_package_global"]
                )
            ],
            eventLoopStatusLine: "idle"
        )

        #expect(presentation.title == "官方技能通道")
        #expect(presentation.statusLabel == "降级")
        #expect(presentation.tone == .critical)
        #expect(presentation.summary.contains("Agent Browser"))
        #expect(presentation.summary.contains("Hub Grant"))
        #expect(presentation.detail.contains("下一步：处理授权阻塞"))
        #expect(presentation.sections.count == 4)
        #expect(presentation.actionLabel == "处理授权阻塞")
        #expect(presentation.actionURL?.contains("hub-setup") == true)
        #expect(presentation.actionURL?.contains("section_id=troubleshoot") == true)
        #expect(presentation.secondaryActions.count == 1)
        #expect(presentation.secondaryActions[0].label == "查看 Calendar Skill")
        #expect(presentation.secondaryActions[0].url.contains("settings") == true)
        #expect(presentation.sections[0].fields.contains(where: {
            $0.label == "首要 blocker" && $0.value == "Agent Browser"
        }))
        #expect(presentation.sections[0].fields.contains(where: {
            $0.label == "当前判断" && $0.value.contains("Hub Grant")
        }))
        #expect(presentation.sections[1].fields.contains(where: {
            $0.label == "最近切换" && $0.value.contains("current snapshot restored")
        }))
        #expect(presentation.sections[1].fields.contains(where: {
            $0.label == "包就绪度" && $0.value.contains("problem_skills=agent-browser,calendar-sync")
        }))
        #expect(presentation.sections[3].fields.contains(where: {
            $0.label == "安全边界" && $0.value.contains("最终权威")
        }))
        #expect(presentation.sections[2].fields.contains(where: {
            $0.label == "Agent Browser" && $0.value.contains("下一步=处理授权阻塞")
        }))
        #expect(presentation.sections[2].fields.contains(where: {
            $0.label == "Calendar Skill" && $0.value.contains("解阻=安装 Baseline")
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
        let relatedSkillActivity = relatedHubGrantActivity(
            requestId: "req-1",
            grantRequestId: "grant-1"
        )

        let presentation = SupervisorAuditDrillDownPresentation.pendingHubGrant(
            grant,
            relatedSkillActivity: relatedSkillActivity
        )

        #expect(presentation.title == "Hub 授权待处理")
        #expect(presentation.statusLabel == "待处理")
        #expect(presentation.tone == .attention)
        #expect(presentation.actionLabel == "打开授权")
        #expect(presentation.requestId == "req-1")
        #expect(presentation.detail.contains("能力增量：新增放开：browser_operator"))
        #expect(presentation.sections.count == 3)
        #expect(presentation.sections[0].fields.contains(where: {
            $0.label == "请求技能" && $0.value == "browser.open"
        }))
        #expect(presentation.sections[0].fields.contains(where: {
            $0.label == "生效技能" && $0.value == "guarded-automation"
        }))
        #expect(presentation.sections[0].fields.contains(where: {
            $0.label == "能力" && !$0.value.isEmpty
        }))
        #expect(presentation.sections[1].fields.contains(where: {
            $0.label == "能力增量" && $0.value == "新增放开：browser_operator"
        }))
        #expect(presentation.sections[1].fields.contains(where: {
            $0.label == "执行就绪" && $0.value == "等待 Hub grant"
        }))
        #expect(presentation.sections[1].fields.contains(where: {
            $0.label == "授权门槛" && $0.value == "高权限 grant"
        }))
        #expect(presentation.sections[1].fields.contains(where: {
            $0.label == "审批门槛" && $0.value == "Hub grant"
        }))
        #expect(presentation.sections[1].fields.contains(where: {
            $0.label == "运行面" && $0.value == "受治理浏览器运行面（managed_browser_runtime）"
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
        let deltaApproval = XTSkillProfileDeltaApproval(
            schemaVersion: XTSkillProfileDeltaApproval.currentSchemaVersion,
            requestId: "req-approval-1",
            projectId: "project-alpha",
            projectName: "Project Alpha",
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
            reason: "browser control touches login flow",
            summary: "当前可直接运行：observe_only；本次请求：observe_only, browser_operator；新增放开：browser_operator；grant=privileged；approval=local_approval",
            disposition: "pending",
            auditRef: "audit-approval-1"
        )
        let readiness = XTSkillExecutionReadiness(
            schemaVersion: XTSkillExecutionReadiness.currentSchemaVersion,
            projectId: "project-alpha",
            skillId: "guarded-automation",
            packageSHA256: String(repeating: "a", count: 64),
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
            stateLabel: XTSkillCapabilityProfileSupport.readinessLabel(
                XTSkillExecutionReadinessState.localApprovalRequired.rawValue
            ),
            installHint: "",
            unblockActions: ["request_local_approval"],
            auditRef: "audit-approval-1-readiness",
            doctorAuditRef: "",
            vetterAuditRef: "",
            resolvedSnapshotId: "snapshot-approval-1",
            grantSnapshotRef: ""
        )
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
            routingExplanation: "requested entrypoint browser.open converged to preferred builtin guarded-automation · resolved action open",
            deltaApproval: deltaApproval,
            readiness: readiness
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
            $0.label == "路由" && $0.value == "browser.open -> guarded-automation · 等待本地审批"
        }))
        #expect(presentation.sections[1].fields.contains(where: {
            $0.label == "能力增量" && $0.value == "新增放开：browser_operator"
        }))
        #expect(presentation.sections[1].fields.contains(where: {
            $0.label == "授权门槛" && $0.value == "高权限 grant"
        }))
        #expect(presentation.sections[1].fields.contains(where: {
            $0.label == "审批门槛" && $0.value == "本地审批"
        }))
        #expect(presentation.sections[1].fields.contains(where: {
            $0.label == "执行就绪" && $0.value == "等待本地审批"
        }))
        #expect(presentation.sections[1].fields.contains(where: {
            $0.label == "运行面" && $0.value == "受治理浏览器运行面（managed_browser_runtime）"
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
            $0.label == "路由原文" && $0.value.contains("requested entrypoint browser.open converged to preferred builtin guarded-automation")
        }))
    }

    @Test
    func pendingSkillApprovalUsesGrantTitleAndActionLabelWhenReadinessRequiresGrant() {
        let approval = pendingSkillApprovalFixture(
            requestId: "req-approval-grant-1",
            executionReadiness: XTSkillExecutionReadinessState.grantRequired.rawValue,
            approvalFloor: XTSkillApprovalFloor.hubGrant.rawValue,
            requiredGrantCapabilities: ["browser.interact"],
            unblockActions: ["request_hub_grant"]
        )

        let presentation = SupervisorAuditDrillDownPresentation.pendingSkillApproval(approval)

        #expect(presentation.title == "技能授权待处理")
        #expect(presentation.actionLabel == "打开授权")
        #expect(presentation.summary.contains("Hub 授权"))
        #expect(presentation.detail.contains("先完成 Hub grant"))
        #expect(presentation.sections[1].fields.contains(where: {
            $0.label == "执行就绪" && $0.value == "等待 Hub grant"
        }))
        #expect(presentation.sections[1].fields.contains(where: {
            $0.label == "解阻动作" && $0.value == "请求 Hub grant（request_hub_grant）"
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
    func candidateReviewMapsDirectSupervisorFocusAction() {
        let item = HubIPCClient.SupervisorCandidateReviewItem(
            schemaVersion: "v1",
            reviewId: "review-1",
            requestId: "req-review-1",
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
            candidateCount: 2,
            summaryLine: "归并了 2 条候选记忆",
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
            latestEmittedAtMs: 1_000,
            createdAtMs: 900,
            updatedAtMs: 1_000
        )

        let presentation = SupervisorAuditDrillDownPresentation.candidateReview(
            item,
            projectNamesByID: ["project-alpha": "Project Alpha"]
        )

        #expect(presentation.title == "候选记忆审查")
        #expect(presentation.statusLabel == "待转入审查")
        #expect(presentation.actionLabel == "打开 Supervisor")
        #expect(presentation.actionURL?.contains("xterminal://supervisor") == true)
        #expect(presentation.actionURL?.contains("focus=candidate_review") == true)
        #expect(presentation.actionURL?.contains("request_id=req-review-1") == true)
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
            $0.label == "关联技能" && $0.value.contains("browser.open -> guarded-automation · 已完成")
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
        let deltaApproval = XTSkillProfileDeltaApproval(
            schemaVersion: XTSkillProfileDeltaApproval.currentSchemaVersion,
            requestId: "req-routing-1",
            projectId: "project-alpha",
            projectName: "Project Alpha",
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
            reason: "browser control touches login flow",
            summary: "当前可直接运行：observe_only；本次请求：observe_only, browser_operator；新增放开：browser_operator；grant=privileged；approval=local_approval",
            disposition: "pending",
            auditRef: "audit-routing-1-delta"
        )
        let readiness = XTSkillExecutionReadiness(
            schemaVersion: XTSkillExecutionReadiness.currentSchemaVersion,
            projectId: "project-alpha",
            skillId: "guarded-automation",
            packageSHA256: String(repeating: "r", count: 64),
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
            stateLabel: XTSkillCapabilityProfileSupport.readinessLabel(
                XTSkillExecutionReadinessState.localApprovalRequired.rawValue
            ),
            installHint: "",
            unblockActions: ["request_local_approval"],
            auditRef: "audit-routing-1-readiness",
            doctorAuditRef: "",
            vetterAuditRef: "",
            resolvedSnapshotId: "snapshot-routing-1",
            grantSnapshotRef: ""
        )
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
                status: .awaitingAuthorization,
                payload: [
                    "action": .string("open"),
                    "url": .string("https://example.com/login")
                ],
                currentOwner: "supervisor",
                resultSummary: "",
                denyCode: "local_approval_required",
                resultEvidenceRef: "evidence-routing-1",
                profileDeltaRef: "delta://routing-1",
                deltaApproval: deltaApproval,
                readinessRef: "readiness://routing-1",
                readiness: readiness,
                requiredCapability: "web.fetch",
                grantRequestId: nil,
                grantId: nil,
                hubStateDirPath: "/tmp/hub-state-routing-1",
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
            $0.label == "路由" && $0.value == "browser.open -> guarded-automation · 等待本地审批"
        }))
        #expect(presentation.sections[2].fields.contains(where: {
            $0.label == "能力增量" && $0.value == "新增放开：browser_operator"
        }))
        #expect(presentation.sections[2].fields.contains(where: {
            $0.label == "执行就绪" && $0.value == "等待本地审批"
        }))
        #expect(presentation.sections[2].fields.contains(where: {
            $0.label == "运行面" && $0.value == "受治理浏览器运行面（managed_browser_runtime）"
        }))
        #expect(presentation.sections[2].fields.contains(where: {
            $0.label == "恢复上下文" && $0.value.contains("已保存 Hub 执行上下文")
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
            $0.label == "路由原文" && $0.value.contains("requested entrypoint browser.open converged to preferred builtin guarded-automation")
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
            $0.label == "安全下一步" && $0.value == "打开 Hub 授权面板"
        }))
        #expect(governanceSection.fields.contains(where: {
            $0.label == "建议动作" && $0.value.contains("Approve the pending hub grant")
        }))
    }

    @Test
    func recentSkillActivityGovernanceTruthFallsBackToActivityGovernanceWhenFullRecordMissing() throws {
        let item = SupervisorManager.SupervisorRecentSkillActivity(
            projectId: "project-alpha",
            projectName: "Project Alpha",
            record: SupervisorSkillCallRecord(
                schemaVersion: SupervisorSkillCallRecord.currentSchemaVersion,
                requestId: "req-governance-fallback-1",
                projectId: "project-alpha",
                jobId: "job-4",
                planId: "plan-4",
                stepId: "step-4",
                skillId: "agent-browser",
                toolName: ToolName.deviceBrowserControl.rawValue,
                status: .blocked,
                payload: [:],
                currentOwner: "supervisor",
                resultSummary: "browser automation blocked by governance",
                denyCode: "governance_capability_denied",
                policySource: "project_governance",
                policyReason: "execution_tier_missing_browser_runtime",
                resultEvidenceRef: "evidence-governance-fallback-1",
                requiredCapability: nil,
                grantRequestId: nil,
                grantId: nil,
                createdAtMs: 1_000,
                updatedAtMs: 2_000,
                auditRef: "audit-governance-fallback-1"
            ),
            tool: .deviceBrowserControl,
            toolCall: nil,
            toolSummary: "open project dashboard",
            actionURL: nil,
            governance: .init(
                configuredExecutionTier: .a1Plan,
                effectiveExecutionTier: .a1Plan,
                configuredSupervisorTier: .s2PeriodicReview,
                effectiveSupervisorTier: .s2PeriodicReview,
                reviewPolicyMode: .periodic,
                progressHeartbeatSeconds: 900,
                reviewPulseSeconds: 1800,
                brainstormReviewSeconds: 0,
                latestGuidanceSummary: "先核对浏览器证据，再推进下一步。",
                pendingGuidanceId: "guidance-fallback-1",
                pendingGuidanceAckStatus: .pending,
                pendingGuidanceRequired: true,
                pendingGuidanceSummary: "先核对浏览器证据，再推进下一步。"
            )
        )

        let presentation = SupervisorAuditDrillDownPresentation.recentSkillActivity(
            item,
            fullRecord: nil
        )

        let governanceSection = try #require(presentation.sections.first(where: { $0.title == "治理" }))
        #expect(governanceSection.fields.contains(where: {
            $0.label == "治理真相" && $0.value == "当前生效 A1/S2 · 审查 周期 · 节奏 心跳 15m / 脉冲 30m / 脑暴 关闭"
        }))
        #expect(governanceSection.fields.contains(where: {
            $0.label == "指导摘要" && $0.value == "先核对浏览器证据，再推进下一步。"
        }))
    }

    @Test
    func recentSkillActivityExecutionAndGovernanceSurfaceBlockedSummaryAndTruth() throws {
        let item = SupervisorManager.SupervisorRecentSkillActivity(
            projectId: "project-alpha",
            projectName: "Project Alpha",
            record: SupervisorSkillCallRecord(
                schemaVersion: SupervisorSkillCallRecord.currentSchemaVersion,
                requestId: "req-governance-truth-1",
                projectId: "project-alpha",
                jobId: "job-7",
                planId: "plan-7",
                stepId: "step-7",
                skillId: "agent-browser",
                toolName: ToolName.deviceBrowserControl.rawValue,
                status: .blocked,
                payload: [:],
                currentOwner: "supervisor",
                resultSummary: "browser automation blocked by governance",
                denyCode: "governance_capability_denied",
                policySource: "project_governance",
                policyReason: "execution_tier_missing_browser_runtime",
                resultEvidenceRef: "evidence-governance-truth-1",
                requiredCapability: nil,
                grantRequestId: nil,
                grantId: nil,
                createdAtMs: 1_000,
                updatedAtMs: 2_000,
                auditRef: "audit-governance-truth-1"
            ),
            tool: .deviceBrowserControl,
            toolCall: nil,
            toolSummary: "open login page",
            actionURL: nil,
            governance: nil
        )
        let fullRecord = SupervisorSkillFullRecord(
            requestID: "req-governance-truth-1",
            projectName: "Project Alpha",
            title: "Supervisor skill blocked",
            latestStatus: "blocked",
            latestStatusLabel: "Blocked",
            requestMetadata: [],
            approvalFields: [
                ProjectSkillRecordField(label: "blocked_summary", value: "legacy blocked summary"),
                ProjectSkillRecordField(label: "policy_reason", value: "legacy_policy_reason"),
                ProjectSkillRecordField(label: "governance_reason", value: "legacy governance reason")
            ],
            governanceFields: [
                ProjectSkillRecordField(label: "policy_source", value: "project_governance"),
                ProjectSkillRecordField(label: "policy_reason", value: "execution_tier_missing_browser_runtime"),
                ProjectSkillRecordField(label: "governance_reason", value: "当前项目 A-Tier 不允许浏览器自动化。"),
                ProjectSkillRecordField(label: "blocked_summary", value: "当前项目 A-Tier 不允许浏览器自动化。"),
                ProjectSkillRecordField(label: "governance_truth", value: "当前生效 A1/S2 · 审查 Periodic · 节奏 心跳 15m / 脉冲 30m / 脑暴 off"),
                ProjectSkillRecordField(label: "repair_action", value: "打开 A-Tier：在项目设置里切到 A2 Repo Auto 或更高，再重试这次浏览器自动化。")
            ],
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

        let presentation = SupervisorAuditDrillDownPresentation.recentSkillActivity(
            item,
            fullRecord: fullRecord
        )

        let executionSection = try #require(presentation.sections.first(where: { $0.title == "执行" }))
        #expect(executionSection.fields.contains(where: {
            $0.label == "策略来源" && $0.value == "project_governance"
        }))
        #expect(executionSection.fields.contains(where: {
            $0.label == "策略原因" && $0.value == "execution_tier_missing_browser_runtime"
        }))
        #expect(executionSection.fields.contains(where: {
            $0.label == "阻塞说明" && $0.value == "当前项目 A-Tier 不允许浏览器自动化。"
        }))
        #expect(executionSection.fields.contains(where: {
            $0.label == "治理原因" && $0.value == "当前项目 A-Tier 不允许浏览器自动化。"
        }))
        #expect(executionSection.fields.contains(where: {
            $0.label == "修复动作" &&
            $0.value == "打开 A-Tier：在项目设置里切到 A2 Repo Auto 或更高，再重试这次浏览器自动化。"
        }))

        let governanceSection = try #require(presentation.sections.first(where: { $0.title == "治理" }))
        #expect(governanceSection.fields.contains(where: {
            $0.label == "治理真相" && $0.value.contains("当前生效 A1/S2")
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
    func eventLoopResultSectionFallsBackToRelatedSkillGovernanceTruthWhenFullRecordMissing() throws {
        let activity = SupervisorManager.SupervisorEventLoopActivity(
            id: "evt-governance-fallback-1",
            createdAt: 10,
            updatedAt: 20,
            triggerSource: "skill_callback",
            status: "queued",
            reasonCode: "blocked_skill_followup",
            dedupeKey: "skill_callback:req-governance-fallback-2:blocked",
            projectId: "project-alpha",
            projectName: "Project Alpha",
            triggerSummary: "blocked skill follow up",
            resultSummary: "needs governance repair",
            policySummary: "policy=retry_once"
        )
        let relatedSkill = SupervisorManager.SupervisorRecentSkillActivity(
            projectId: "project-alpha",
            projectName: "Project Alpha",
            record: SupervisorSkillCallRecord(
                schemaVersion: SupervisorSkillCallRecord.currentSchemaVersion,
                requestId: "req-governance-fallback-2",
                projectId: "project-alpha",
                jobId: "job-5",
                planId: "plan-5",
                stepId: "step-5",
                skillId: "agent-browser",
                toolName: ToolName.deviceBrowserControl.rawValue,
                status: .blocked,
                payload: [:],
                currentOwner: "supervisor",
                resultSummary: "browser automation blocked by governance",
                denyCode: "governance_capability_denied",
                policySource: "project_governance",
                policyReason: "execution_tier_missing_browser_runtime",
                resultEvidenceRef: "evidence-governance-fallback-2",
                requiredCapability: nil,
                grantRequestId: nil,
                grantId: nil,
                createdAtMs: 1_000,
                updatedAtMs: 2_000,
                auditRef: "audit-governance-fallback-2"
            ),
            tool: .deviceBrowserControl,
            toolCall: nil,
            toolSummary: "open project dashboard",
            actionURL: nil,
            governance: .init(
                configuredExecutionTier: .a1Plan,
                effectiveExecutionTier: .a1Plan,
                configuredSupervisorTier: .s2PeriodicReview,
                effectiveSupervisorTier: .s2PeriodicReview,
                reviewPolicyMode: .periodic,
                progressHeartbeatSeconds: 900,
                reviewPulseSeconds: 1800,
                brainstormReviewSeconds: 0
            )
        )

        let presentation = SupervisorAuditDrillDownPresentation.eventLoopActivity(
            activity,
            relatedSkillActivity: relatedSkill,
            fullRecord: nil
        )

        let resultSection = try #require(presentation.sections.first(where: { $0.title == "结果" }))
        #expect(resultSection.fields.contains(where: {
            $0.label == "阻塞说明" && $0.value.contains("当前项目 A-Tier 不允许浏览器自动化。")
        }))
        #expect(resultSection.fields.contains(where: {
            $0.label == "治理真相" && $0.value == "当前生效 A1/S2 · 审查 周期 · 节奏 心跳 15m / 脉冲 30m / 脑暴 关闭"
        }))
        #expect(resultSection.fields.contains(where: {
            $0.label == "治理原因" && $0.value == "当前项目 A-Tier 不允许浏览器自动化。"
        }))
    }

    @Test
    func eventLoopResultSectionIncludesBlockedSummaryAndGovernanceTruthFromFullRecord() throws {
        let activity = SupervisorManager.SupervisorEventLoopActivity(
            id: "evt-governance-1",
            createdAt: 10,
            updatedAt: 20,
            triggerSource: "skill_callback",
            status: "queued",
            reasonCode: "blocked_follow_up",
            dedupeKey: "skill_callback:req-governance-evt-1:blocked",
            projectId: "project-alpha",
            projectName: "Project Alpha",
            triggerSummary: "skill callback blocked",
            resultSummary: "follow up required",
            policySummary: "policy=retry_once"
        )
        let relatedSkill = SupervisorManager.SupervisorRecentSkillActivity(
            projectId: "project-alpha",
            projectName: "Project Alpha",
            record: SupervisorSkillCallRecord(
                schemaVersion: SupervisorSkillCallRecord.currentSchemaVersion,
                requestId: "req-governance-evt-1",
                projectId: "project-alpha",
                jobId: "job-9",
                planId: "plan-9",
                stepId: "step-9",
                skillId: "agent-browser",
                toolName: ToolName.deviceBrowserControl.rawValue,
                status: .blocked,
                payload: [:],
                currentOwner: "supervisor",
                resultSummary: "browser automation blocked by governance",
                denyCode: "governance_capability_denied",
                policySource: "project_governance",
                policyReason: "execution_tier_missing_browser_runtime",
                resultEvidenceRef: "evidence-evt-governance-1",
                requiredCapability: nil,
                grantRequestId: nil,
                grantId: nil,
                createdAtMs: 1_000,
                updatedAtMs: 2_000,
                auditRef: "audit-evt-governance-1"
            ),
            tool: .deviceBrowserControl,
            toolCall: nil,
            toolSummary: "open login page",
            actionURL: nil,
            governance: nil
        )
        let fullRecord = SupervisorSkillFullRecord(
            requestID: "req-governance-evt-1",
            projectName: "Project Alpha",
            title: "Supervisor skill blocked",
            latestStatus: "blocked",
            latestStatusLabel: "Blocked",
            requestMetadata: [],
            approvalFields: [
                ProjectSkillRecordField(label: "blocked_summary", value: "legacy blocked summary"),
                ProjectSkillRecordField(label: "policy_reason", value: "legacy_policy_reason"),
                ProjectSkillRecordField(label: "governance_reason", value: "legacy governance reason")
            ],
            governanceFields: [
                ProjectSkillRecordField(label: "policy_source", value: "project_governance"),
                ProjectSkillRecordField(label: "policy_reason", value: "execution_tier_missing_browser_runtime"),
                ProjectSkillRecordField(label: "governance_reason", value: "当前项目 A-Tier 不允许浏览器自动化。"),
                ProjectSkillRecordField(label: "blocked_summary", value: "当前项目 A-Tier 不允许浏览器自动化。"),
                ProjectSkillRecordField(label: "governance_truth", value: "当前生效 A1/S2 · 审查 Periodic。"),
                ProjectSkillRecordField(label: "repair_action", value: "打开 A-Tier：在项目设置里切到 A2 Repo Auto 或更高，再重试这次浏览器自动化。")
            ],
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
            relatedSkillActivity: relatedSkill,
            fullRecord: fullRecord
        )

        let resultSection = try #require(presentation.sections.first(where: { $0.title == "结果" }))
        #expect(resultSection.fields.contains(where: {
            $0.label == "策略来源" && $0.value == "project_governance"
        }))
        #expect(resultSection.fields.contains(where: {
            $0.label == "阻塞说明" && $0.value == "当前项目 A-Tier 不允许浏览器自动化。"
        }))
        #expect(resultSection.fields.contains(where: {
            $0.label == "治理真相" && $0.value == "当前生效 A1/S2 · 审查 周期。"
        }))
        #expect(resultSection.fields.contains(where: {
            $0.label == "策略原因" && $0.value == "execution_tier_missing_browser_runtime"
        }))
        #expect(resultSection.fields.contains(where: {
            $0.label == "治理原因" && $0.value == "当前项目 A-Tier 不允许浏览器自动化。"
        }))
        #expect(resultSection.fields.contains(where: {
            $0.label == "修复动作" &&
            $0.value == "打开 A-Tier：在项目设置里切到 A2 Repo Auto 或更高，再重试这次浏览器自动化。"
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

    @Test
    func fullRecordFallbackIncludesGovernanceTruthAndBlockedSummaryWhenPresent() throws {
        let record = SupervisorSkillFullRecord(
            requestID: "req-fallback-governance-1",
            projectName: "Project Gamma",
            title: "Supervisor skill blocked",
            latestStatus: "blocked",
            latestStatusLabel: "Blocked",
            requestMetadata: [],
            approvalFields: [
                ProjectSkillRecordField(label: "blocked_summary", value: "legacy blocked summary"),
                ProjectSkillRecordField(label: "policy_reason", value: "legacy_policy_reason"),
                ProjectSkillRecordField(label: "governance_reason", value: "legacy governance reason")
            ],
            governanceFields: [
                ProjectSkillRecordField(label: "policy_source", value: "project_governance"),
                ProjectSkillRecordField(label: "policy_reason", value: "execution_tier_missing_browser_runtime"),
                ProjectSkillRecordField(label: "governance_reason", value: "当前项目 A-Tier 不允许浏览器自动化。"),
                ProjectSkillRecordField(label: "blocked_summary", value: "当前项目 A-Tier 不允许浏览器自动化。"),
                ProjectSkillRecordField(label: "governance_truth", value: "当前生效 A1/S2 · 审查 Periodic。"),
                ProjectSkillRecordField(label: "repair_action", value: "打开 A-Tier：在项目设置里切到 A2 Repo Auto 或更高，再重试这次浏览器自动化。")
            ],
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

        let presentation = SupervisorAuditDrillDownPresentation.fullRecordFallback(
            projectId: "project-gamma",
            projectName: "Project Gamma",
            record: record
        )

        let governanceSection = try #require(presentation.sections.first(where: { $0.title == "治理" }))
        #expect(governanceSection.fields.contains(where: {
            $0.label == "策略来源" && $0.value == "project_governance"
        }))
        #expect(governanceSection.fields.contains(where: {
            $0.label == "策略原因" && $0.value == "execution_tier_missing_browser_runtime"
        }))
        #expect(governanceSection.fields.contains(where: {
            $0.label == "治理原因" && $0.value == "当前项目 A-Tier 不允许浏览器自动化。"
        }))
        #expect(governanceSection.fields.contains(where: {
            $0.label == "阻塞说明" && $0.value == "当前项目 A-Tier 不允许浏览器自动化。"
        }))
        #expect(governanceSection.fields.contains(where: {
            $0.label == "治理真相" && $0.value == "当前生效 A1/S2 · 审查 周期。"
        }))
        #expect(governanceSection.fields.contains(where: {
            $0.label == "修复动作" &&
            $0.value == "打开 A-Tier：在项目设置里切到 A2 Repo Auto 或更高，再重试这次浏览器自动化。"
        }))
    }

    @Test
    func fullRecordFallbackKeepsLegacyApprovalFieldFallbackForGovernanceData() throws {
        let record = SupervisorSkillFullRecord(
            requestID: "req-fallback-governance-legacy-1",
            projectName: "Project Gamma",
            title: "Supervisor skill blocked",
            latestStatus: "blocked",
            latestStatusLabel: "Blocked",
            requestMetadata: [],
            approvalFields: [
                ProjectSkillRecordField(label: "blocked_summary", value: "legacy blocked summary"),
                ProjectSkillRecordField(label: "policy_reason", value: "legacy_policy_reason"),
                ProjectSkillRecordField(label: "governance_reason", value: "legacy governance reason")
            ],
            governanceFields: [
                ProjectSkillRecordField(label: "governance_truth", value: "当前生效 A1/S2 · 审查 Periodic。")
            ],
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

        let presentation = SupervisorAuditDrillDownPresentation.fullRecordFallback(
            projectId: "project-gamma",
            projectName: "Project Gamma",
            record: record
        )

        let governanceSection = try #require(presentation.sections.first(where: { $0.title == "治理" }))
        #expect(governanceSection.fields.contains(where: {
            $0.label == "阻塞说明" && $0.value == "legacy blocked summary"
        }))
        #expect(governanceSection.fields.contains(where: {
            $0.label == "策略原因" && $0.value == "legacy_policy_reason"
        }))
        #expect(governanceSection.fields.contains(where: {
            $0.label == "治理原因" && $0.value == "legacy governance reason"
        }))
    }

    private func pendingSkillApprovalFixture(
        requestId: String,
        executionReadiness: String,
        approvalFloor: String,
        requiredGrantCapabilities: [String],
        unblockActions: [String]
    ) -> SupervisorManager.SupervisorPendingSkillApproval {
        let deltaApproval = XTSkillProfileDeltaApproval(
            schemaVersion: XTSkillProfileDeltaApproval.currentSchemaVersion,
            requestId: requestId,
            projectId: "project-alpha",
            projectName: "Project Alpha",
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
            approvalFloor: approvalFloor,
            requestedTTLSeconds: 900,
            reason: "browser control touches live login flow",
            summary: "当前可直接运行：observe_only；本次请求：observe_only, browser_operator；新增放开：browser_operator",
            disposition: "pending",
            auditRef: "audit-\(requestId)"
        )
        let readiness = XTSkillExecutionReadiness(
            schemaVersion: XTSkillExecutionReadiness.currentSchemaVersion,
            projectId: "project-alpha",
            skillId: "guarded-automation",
            packageSHA256: "pkg-1",
            publisherID: "xt_builtin",
            policyScope: "xt_builtin",
            intentFamilies: ["browser.navigate"],
            capabilityFamilies: ["repo.read", "browser.interact"],
            capabilityProfiles: ["observe_only", "browser_operator"],
            discoverabilityState: "discoverable",
            installabilityState: "installable",
            pinState: "xt_builtin",
            resolutionState: "resolved",
            executionReadiness: executionReadiness,
            runnableNow: false,
            denyCode: executionReadiness == XTSkillExecutionReadinessState.grantRequired.rawValue
                ? "grant_required"
                : "local_approval_required",
            reasonCode: executionReadiness == XTSkillExecutionReadinessState.grantRequired.rawValue
                ? "grant floor privileged requires hub grant"
                : "approval floor local_approval requires local confirmation",
            grantFloor: XTSkillGrantFloor.privileged.rawValue,
            approvalFloor: approvalFloor,
            requiredGrantCapabilities: requiredGrantCapabilities,
            requiredRuntimeSurfaces: ["managed_browser_runtime"],
            stateLabel: executionReadiness == XTSkillExecutionReadinessState.grantRequired.rawValue
                ? "awaiting_hub_grant"
                : XTSkillCapabilityProfileSupport.readinessLabel(
                    XTSkillExecutionReadinessState.localApprovalRequired.rawValue
                ),
            installHint: "",
            unblockActions: unblockActions,
            auditRef: "audit-\(requestId)-readiness",
            doctorAuditRef: "",
            vetterAuditRef: "",
            resolvedSnapshotId: "snapshot-\(requestId)",
            grantSnapshotRef: executionReadiness == XTSkillExecutionReadinessState.grantRequired.rawValue
                ? "grant-\(requestId)"
                : ""
        )

        return SupervisorManager.SupervisorPendingSkillApproval(
            id: "approval-\(requestId)",
            requestId: requestId,
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
            actionURL: "x-terminal://approval/\(requestId)",
            routingReasonCode: "preferred_builtin_selected",
            routingExplanation: "requested entrypoint browser.open converged to preferred builtin guarded-automation · resolved action open",
            deltaApproval: deltaApproval,
            readiness: readiness
        )
    }

    private func relatedHubGrantActivity(
        requestId: String,
        grantRequestId: String
    ) -> SupervisorManager.SupervisorRecentSkillActivity {
        let deltaApproval = XTSkillProfileDeltaApproval(
            schemaVersion: XTSkillProfileDeltaApproval.currentSchemaVersion,
            requestId: requestId,
            projectId: "project-alpha",
            projectName: "Project Alpha",
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
            approvalFloor: XTSkillApprovalFloor.hubGrant.rawValue,
            requestedTTLSeconds: 3600,
            reason: "browser fetch for live verification",
            summary: "当前可直接运行：observe_only；本次请求：observe_only, browser_operator；新增放开：browser_operator",
            disposition: "pending",
            auditRef: "audit-delta-1"
        )
        let readiness = XTSkillExecutionReadiness(
            schemaVersion: XTSkillExecutionReadiness.currentSchemaVersion,
            projectId: "project-alpha",
            skillId: "guarded-automation",
            packageSHA256: "pkg-1",
            publisherID: "xt_builtin",
            policyScope: "xt_builtin",
            intentFamilies: ["browser.observe", "browser.interact"],
            capabilityFamilies: ["browser.observe", "browser.interact"],
            capabilityProfiles: ["observe_only", "browser_operator"],
            discoverabilityState: "discoverable",
            installabilityState: "installable",
            pinState: "xt_builtin",
            resolutionState: "resolved",
            executionReadiness: XTSkillExecutionReadinessState.grantRequired.rawValue,
            runnableNow: false,
            denyCode: "grant_required",
            reasonCode: "grant floor privileged requires hub grant",
            grantFloor: XTSkillGrantFloor.privileged.rawValue,
            approvalFloor: XTSkillApprovalFloor.hubGrant.rawValue,
            requiredGrantCapabilities: ["browser.interact"],
            requiredRuntimeSurfaces: ["managed_browser_runtime"],
            stateLabel: "awaiting_hub_grant",
            installHint: "",
            unblockActions: ["request_hub_grant"],
            auditRef: "audit-readiness-1",
            doctorAuditRef: "",
            vetterAuditRef: "",
            resolvedSnapshotId: "snapshot-1",
            grantSnapshotRef: "grant-1"
        )
        let record = SupervisorSkillCallRecord(
            schemaVersion: SupervisorSkillCallRecord.currentSchemaVersion,
            requestId: requestId,
            projectId: "project-alpha",
            jobId: "job-1",
            planId: "plan-1",
            stepId: "step-1",
            skillId: "guarded-automation",
            requestedSkillId: "browser.open",
            toolName: ToolName.deviceBrowserControl.rawValue,
            status: .awaitingAuthorization,
            payload: [:],
            currentOwner: "supervisor",
            resultSummary: "",
            denyCode: "grant_required",
            resultEvidenceRef: nil,
            profileDeltaRef: "delta://1",
            deltaApproval: deltaApproval,
            readinessRef: "readiness://1",
            readiness: readiness,
            requiredCapability: "web.fetch",
            grantRequestId: grantRequestId,
            grantId: nil,
            hubStateDirPath: "/tmp/hub-state",
            createdAtMs: 10_000,
            updatedAtMs: 10_000,
            auditRef: "audit-1"
        )

        return SupervisorManager.SupervisorRecentSkillActivity(
            projectId: "project-alpha",
            projectName: "Project Alpha",
            record: record,
            tool: .deviceBrowserControl,
            toolCall: nil,
            toolSummary: "browser fetch for live verification",
            actionURL: "x-terminal://project/project-alpha"
        )
    }
}
