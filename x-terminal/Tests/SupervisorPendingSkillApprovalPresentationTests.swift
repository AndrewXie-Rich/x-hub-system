import Foundation
import Testing
@testable import XTerminal

struct SupervisorPendingSkillApprovalPresentationTests {

    @Test
    func boardBuildsEmptyState() {
        let presentation = SupervisorPendingSkillApprovalPresentation.board(
            approvals: [],
            focusedRowAnchor: nil
        )

        #expect(presentation.iconName == "checkmark.shield")
        #expect(presentation.iconTone == .neutral)
        #expect(presentation.title == "待审批技能：0")
        #expect(presentation.modeText == "本地审批")
        #expect(presentation.emptyStateText == "当前没有待审批的 Supervisor 高风险技能。")
        #expect(presentation.isEmpty)
    }

    @Test
    func rowBuildsMessageIconFocusAndActions() {
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
            toolSummary: "Open dashboard and click submit",
            reason: "browser control touches live admin surface",
            createdAt: 940,
            actionURL: "x-terminal://supervisor?approval=req-approval-1",
            routingReasonCode: "preferred_builtin_selected",
            routingExplanation: "requested entrypoint browser.open converged to preferred builtin guarded-automation · resolved action open",
            deltaApproval: XTSkillProfileDeltaApproval(
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
                reason: "browser control touches live admin surface",
                summary: "当前可直接运行：observe_only；本次请求：observe_only, browser_operator；新增放开：browser_operator；grant=privileged；approval=local_approval",
                disposition: "pending",
                auditRef: "audit-approval-1"
            ),
            readiness: XTSkillExecutionReadiness(
                schemaVersion: XTSkillExecutionReadiness.currentSchemaVersion,
                projectId: "project-alpha",
                skillId: "guarded-automation",
                packageSHA256: "pkg-1",
                publisherID: "xt_builtin",
                policyScope: "xt_builtin",
                intentFamilies: ["browser.observe", "browser.interact"],
                capabilityFamilies: ["browser.observe", "browser.interact"],
                capabilityProfiles: ["observe_only", "browser_research", "browser_operator"],
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
                requiredGrantCapabilities: ["browser.interact"],
                requiredRuntimeSurfaces: ["managed_browser_runtime"],
                stateLabel: "awaiting_local_approval",
                installHint: "",
                unblockActions: ["request_local_approval"],
                auditRef: "audit-readiness-1",
                doctorAuditRef: "",
                vetterAuditRef: "",
                resolvedSnapshotId: "snapshot-1",
                grantSnapshotRef: "grant-1"
            )
        )

        let row = SupervisorPendingSkillApprovalPresentation.row(
            approval,
            isFocused: true
        )

        #expect(row.anchorID == SupervisorFocusPresentation.pendingSupervisorSkillApprovalRowAnchor(approval))
        #expect(row.iconName == "safari")
        #expect(row.title == "Project Alpha · browser.open -> guarded-automation · 等待本地审批")
        #expect(row.ageText.isEmpty == false)
        #expect(row.summary.isEmpty == false)
        #expect(row.routingText == nil)
        #expect(row.routingExplanationText?.contains("浏览器入口会先收敛到受治理内建 guarded-automation 再执行") == true)
        #expect(row.noteText?.contains("能力增量：新增放开：browser_operator") == true)
        #expect(row.noteText?.contains("授权门槛：高权限 grant · 审批门槛：本地审批") == true)
        #expect(row.noteText?.contains("执行就绪：等待本地审批") == true)
        #expect(row.noteText?.contains("运行面：受治理浏览器运行面（managed_browser_runtime）") == true)
        #expect(row.requestIdentifierText == "请求单号：req-approval-1")
        #expect(row.isFocused)
        #expect(row.actionDescriptors.map(\.label) == ["详情", "打开", "批准", "拒绝"])
    }

    @Test
    func rowUsesHubGrantMessagingAndOpenGrantActionWhenReadinessRequiresGrant() {
        let approval = makeApproval(
            requestId: "req-approval-grant-1",
            executionReadiness: XTSkillExecutionReadinessState.grantRequired.rawValue,
            approvalFloor: XTSkillApprovalFloor.hubGrant.rawValue,
            unblockActions: ["request_hub_grant"],
            requiredGrantCapabilities: ["browser.interact"]
        )

        let row = SupervisorPendingSkillApprovalPresentation.row(
            approval,
            isFocused: false
        )
        let board = SupervisorPendingSkillApprovalPresentation.board(
            approvals: [approval],
            focusedRowAnchor: nil
        )

        #expect(row.summary.contains("Hub 授权"))
        #expect(row.summary.contains("本地审批") == false)
        #expect(row.nextStepText == "先完成 Hub grant，再恢复这次受治理技能调用。")
        #expect(row.noteText?.contains("授权门槛：高权限 grant · 审批门槛：Hub grant") == true)
        #expect(row.noteText?.contains("执行就绪：等待 Hub grant") == true)
        #expect(row.noteText?.contains("运行面：受治理浏览器运行面（managed_browser_runtime）") == true)
        #expect(row.actionDescriptors.map(\.label) == ["详情", "打开", "打开授权", "拒绝"])
        #expect(board.modeText == "等待 Hub grant")
    }

    @Test
    func boardModeTextShowsMixedLocalApprovalAndHubGrant() {
        let localApproval = makeApproval(
            requestId: "req-approval-local-1",
            executionReadiness: XTSkillExecutionReadinessState.localApprovalRequired.rawValue,
            approvalFloor: XTSkillApprovalFloor.localApproval.rawValue,
            unblockActions: ["request_local_approval"]
        )
        let grantApproval = makeApproval(
            requestId: "req-approval-grant-2",
            executionReadiness: XTSkillExecutionReadinessState.grantRequired.rawValue,
            approvalFloor: XTSkillApprovalFloor.hubGrant.rawValue,
            unblockActions: ["request_hub_grant"],
            requiredGrantCapabilities: ["browser.interact"]
        )

        let board = SupervisorPendingSkillApprovalPresentation.board(
            approvals: [localApproval, grantApproval],
            focusedRowAnchor: nil
        )

        #expect(board.modeText == "本地审批 + Hub grant")
    }
}

private func makeApproval(
    requestId: String,
    executionReadiness: String,
    approvalFloor: String,
    unblockActions: [String],
    requiredGrantCapabilities: [String] = []
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
        reason: "browser control touches live admin surface",
        summary: "当前可直接运行：observe_only；本次请求：observe_only, browser_operator；新增放开：browser_operator；grant=privileged；approval=\(approvalFloor)",
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
        intentFamilies: ["browser.observe", "browser.interact"],
        capabilityFamilies: ["browser.observe", "browser.interact"],
        capabilityProfiles: ["observe_only", "browser_research", "browser_operator"],
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
            : "awaiting_local_approval",
        installHint: "",
        unblockActions: unblockActions,
        auditRef: "audit-readiness-\(requestId)",
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
        toolSummary: "Open dashboard and click submit",
        reason: "browser control touches live admin surface",
        createdAt: 940,
        actionURL: "x-terminal://supervisor?approval=\(requestId)",
        routingReasonCode: "preferred_builtin_selected",
        routingExplanation: "requested entrypoint browser.open converged to preferred builtin guarded-automation · resolved action open",
        deltaApproval: deltaApproval,
        readiness: readiness
    )
}
