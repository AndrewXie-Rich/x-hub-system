import Foundation
import Testing
@testable import XTerminal

@MainActor
struct SupervisorPendingSkillApprovalRoutingTextTests {

    @Test
    @MainActor
    func displaySkillPrefersWrapperToBuiltinRoutingSummary() {
        let manager = SupervisorManager.makeForTesting()
        let approval = makeApproval(
            requestId: "req-routing-display",
            projectName: "Project Alpha",
            skillId: "guarded-automation",
            requestedSkillId: "browser.open"
        )

        let summary = manager.pendingSupervisorSkillApprovalDisplaySkillForTesting(approval)

        #expect(summary == "browser.open -> guarded-automation")
    }

    @Test
    @MainActor
    func displaySkillUsesGovernedSummaryWhenApprovalHasReadinessContext() {
        let manager = SupervisorManager.makeForTesting()
        let approval = makeApproval(
            requestId: "req-routing-governed",
            projectName: "Project Alpha",
            skillId: "guarded-automation",
            requestedSkillId: "browser.open",
            deltaApproval: XTSkillProfileDeltaApproval(
                schemaVersion: XTSkillProfileDeltaApproval.currentSchemaVersion,
                requestId: "req-routing-governed",
                projectId: "project-req-routing-governed",
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
                auditRef: "audit-routing-governed"
            ),
            readiness: XTSkillExecutionReadiness(
                schemaVersion: XTSkillExecutionReadiness.currentSchemaVersion,
                projectId: "project-req-routing-governed",
                skillId: "guarded-automation",
                packageSHA256: String(repeating: "g", count: 64),
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
                auditRef: "audit-routing-governed-readiness",
                doctorAuditRef: "",
                vetterAuditRef: "",
                resolvedSnapshotId: "snapshot-routing-governed",
                grantSnapshotRef: ""
            )
        )

        let summary = manager.pendingSupervisorSkillApprovalDisplaySkillForTesting(approval)

        #expect(summary == "browser.open -> guarded-automation · 等待本地审批")
    }

    @Test
    @MainActor
    func genericDisplaySummaryIncludesNormalizedActionWhenPayloadProvidesIt() {
        let manager = SupervisorManager.makeForTesting()

        let summary = manager.supervisorSkillDisplaySummaryForTesting(
            requestedSkillId: "browser.open",
            effectiveSkillId: "guarded-automation",
            payload: ["action": .string("open")]
        )

        #expect(summary == "browser.open -> guarded-automation · action=open")
    }

    @Test
    @MainActor
    func ambiguityReplyUsesRequestedWrapperWhenBuiltinRoutingIsActive() {
        let manager = SupervisorManager.makeForTesting()
        let approvals = [
            makeApproval(
                requestId: "req-routing-1",
                projectName: "Project Alpha",
                skillId: "guarded-automation",
                requestedSkillId: "browser.open",
                toolSummary: "open https://example.com/login",
                reason: "browser control touches login flow"
            ),
            makeApproval(
                requestId: "req-routing-2",
                projectName: "Project Beta",
                skillId: "guarded-automation",
                requestedSkillId: "browser.runtime.inspect",
                toolSummary: "inspect checkout page",
                reason: "browser snapshot touches checkout surface"
            )
        ]

        let reply = manager.pendingSupervisorSkillApprovalAmbiguityReplyForTesting(approvals)

        #expect(reply.contains("Project Alpha / browser.open -> guarded-automation /"))
        #expect(reply.contains("Project Beta / browser.runtime.inspect -> guarded-automation /"))
    }

    @Test
    @MainActor
    func voiceAnnouncementUsesRequestedWrapperWhenBuiltinRoutingIsActive() {
        let manager = SupervisorManager.makeForTesting()
        let approval = makeApproval(
            requestId: "req-routing-voice",
            projectName: "Project Alpha",
            skillId: "guarded-automation",
            requestedSkillId: "browser.open",
            toolSummary: "open https://example.com/login",
            reason: "browser control touches login flow"
        )

        let text = manager.pendingSupervisorSkillApprovalVoiceAnnouncementTextForTesting(
            approval: approval,
            pendingCount: 1
        )

        #expect(text.contains("《Project Alpha》现在有一条待处理的本地技能调用：browser.open -> guarded-automation。"))
        #expect(text.contains("路由说明：浏览器入口会先收敛到受治理内建 guarded-automation 再执行"))
        #expect(text.contains("目标：open https://example.com/login"))
    }

    @Test
    @MainActor
    func voiceAnnouncementUsesGrantWordingWhenReadinessRequiresHubGrant() {
        let manager = SupervisorManager.makeForTesting()
        let approval = makeApproval(
            requestId: "req-routing-grant-voice",
            projectName: "Project Alpha",
            skillId: "guarded-automation",
            requestedSkillId: "browser.open",
            toolSummary: "open https://example.com/login",
            reason: "browser control touches login flow",
            readiness: XTSkillExecutionReadiness(
                schemaVersion: XTSkillExecutionReadiness.currentSchemaVersion,
                projectId: "project-req-routing-grant-voice",
                skillId: "guarded-automation",
                packageSHA256: String(repeating: "g", count: 64),
                publisherID: "xt_builtin",
                policyScope: "xt_builtin",
                intentFamilies: ["browser.navigate"],
                capabilityFamilies: ["repo.read", "browser.interact"],
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
                auditRef: "audit-routing-grant-voice",
                doctorAuditRef: "",
                vetterAuditRef: "",
                resolvedSnapshotId: "snapshot-routing-grant-voice",
                grantSnapshotRef: "grant-routing-grant-voice"
            )
        )

        let text = manager.pendingSupervisorSkillApprovalVoiceAnnouncementTextForTesting(
            approval: approval,
            pendingCount: 1
        )

        #expect(text.contains("检测到新的技能授权待处理"))
        #expect(text.contains("《Project Alpha》现在有一条待处理的技能授权：browser.open -> guarded-automation · 等待 Hub grant。"))
    }

    @Test
    @MainActor
    func ambiguityReplyUsesGrantWordingWhenAllCandidatesNeedHubGrant() {
        let manager = SupervisorManager.makeForTesting()
        let approvals = [
            makeApproval(
                requestId: "req-routing-grant-1",
                projectName: "Project Alpha",
                skillId: "guarded-automation",
                requestedSkillId: "browser.open",
                toolSummary: "open https://example.com/login",
                reason: "browser control touches login flow",
                readiness: XTSkillExecutionReadiness(
                    schemaVersion: XTSkillExecutionReadiness.currentSchemaVersion,
                    projectId: "project-req-routing-grant-1",
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
                    auditRef: "audit-routing-grant-1",
                    doctorAuditRef: "",
                    vetterAuditRef: "",
                    resolvedSnapshotId: "snapshot-routing-grant-1",
                    grantSnapshotRef: "grant-routing-grant-1"
                )
            ),
            makeApproval(
                requestId: "req-routing-grant-2",
                projectName: "Project Beta",
                skillId: "guarded-automation",
                requestedSkillId: "browser.runtime.inspect",
                toolSummary: "inspect checkout page",
                reason: "browser snapshot touches checkout surface",
                readiness: XTSkillExecutionReadiness(
                    schemaVersion: XTSkillExecutionReadiness.currentSchemaVersion,
                    projectId: "project-req-routing-grant-2",
                    skillId: "guarded-automation",
                    packageSHA256: String(repeating: "b", count: 64),
                    publisherID: "xt_builtin",
                    policyScope: "xt_builtin",
                    intentFamilies: ["browser.navigate"],
                    capabilityFamilies: ["repo.read", "browser.interact"],
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
                    auditRef: "audit-routing-grant-2",
                    doctorAuditRef: "",
                    vetterAuditRef: "",
                    resolvedSnapshotId: "snapshot-routing-grant-2",
                    grantSnapshotRef: "grant-routing-grant-2"
                )
            ),
        ]

        let reply = manager.pendingSupervisorSkillApprovalAmbiguityReplyForTesting(approvals)

        #expect(reply.contains("当前有多条待处理的技能授权，我不想替你盲选。"))
    }

    private func makeApproval(
        requestId: String,
        projectName: String,
        skillId: String,
        requestedSkillId: String?,
        toolSummary: String = "Open dashboard",
        reason: String = "browser control touches live admin surface",
        deltaApproval: XTSkillProfileDeltaApproval? = nil,
        readiness: XTSkillExecutionReadiness? = nil
    ) -> SupervisorManager.SupervisorPendingSkillApproval {
        SupervisorManager.SupervisorPendingSkillApproval(
            id: "approval-\(requestId)",
            requestId: requestId,
            projectId: "project-\(requestId)",
            projectName: projectName,
            jobId: "job-\(requestId)",
            planId: "plan-\(requestId)",
            stepId: "step-\(requestId)",
            skillId: skillId,
            requestedSkillId: requestedSkillId,
            toolName: ToolName.deviceBrowserControl.rawValue,
            tool: .deviceBrowserControl,
            toolSummary: toolSummary,
            reason: reason,
            createdAt: 10,
            actionURL: "x-terminal://approval/\(requestId)",
            deltaApproval: deltaApproval,
            readiness: readiness
        )
    }
}
