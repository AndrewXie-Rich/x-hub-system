import Foundation
import Testing
@testable import XTerminal

struct SupervisorPendingHubGrantPresentationTests {

    @Test
    func boardBuildsSnapshotSummaryAndEmptyState() {
        let presentation = SupervisorPendingHubGrantPresentation.board(
            grants: [],
            source: "",
            hasFreshSnapshot: false,
            updatedAt: 0,
            inFlightGrantIDs: [],
            hubInteractive: false,
            focusedRowAnchor: nil,
            now: 1_000
        )

        #expect(presentation.iconName == "checkmark.shield")
        #expect(presentation.iconTone == .neutral)
        #expect(presentation.title == "Hub 待处理授权：0")
        #expect(presentation.snapshotText == "来源：Hub · 快照偏旧")
        #expect(presentation.freshnessWarningText?.isEmpty == false)
        #expect(presentation.footerNote == nil)
        #expect(presentation.emptyStateText == "当前没有待审批的 Hub 授权。")
        #expect(presentation.isEmpty)
    }

    @Test
    func rowBuildsFocusInflightAndActions() {
        let grant = SupervisorManager.SupervisorPendingGrant(
            id: "grant-1",
            dedupeKey: "grant:key",
            grantRequestId: "req-1",
            requestId: "skill-1",
            projectId: "project-alpha",
            projectName: "Project Alpha",
            capability: "browser.control",
            modelId: "gpt-5.4",
            reason: "browser automation requested",
            requestedTtlSec: 600,
            requestedTokenCap: 4000,
            createdAt: 940,
            actionURL: "x-terminal://supervisor?grant=req-1",
            priorityRank: 1,
            priorityReason: "critical path",
            nextAction: "approve now"
        )
        let relatedSkillActivity = relatedHubGrantActivity(requestId: "skill-1")

        let row = SupervisorPendingHubGrantPresentation.row(
            grant,
            relatedSkillActivity: relatedSkillActivity,
            inFlightGrantIDs: ["req-1"],
            hubInteractive: true,
            isFocused: true,
            now: 1_000
        )

        #expect(row.anchorID == SupervisorFocusPresentation.pendingHubGrantRowAnchor(grant))
        #expect(row.title.contains("P1"))
        #expect(row.title.contains("Project Alpha"))
        #expect(row.ageText == "刚刚")
        #expect(row.summary.isEmpty == false)
        #expect(row.governedContextLines.contains("能力增量：新增放开：browser_operator"))
        #expect(row.governedContextLines.contains("授权门槛：高权限 grant · 审批门槛：Hub grant"))
        #expect(
            row.governedContextLines.contains(
                "执行就绪：等待 Hub grant；运行面：受治理浏览器运行面（managed_browser_runtime）；解阻动作：请求 Hub grant（request_hub_grant）"
            )
        )
        #expect(row.supplementaryReasonText?.contains("原因：") == true)
        #expect(row.priorityReasonText == "优先级解释：critical path")
        #expect(row.nextActionText == "建议动作：approve now")
        #expect(row.scopeSummaryText?.isEmpty == false)
        #expect(row.grantIdentifierText == "授权单号：req-1")
        #expect(row.isFocused)
        #expect(row.isInFlight)
        #expect(row.actionDescriptors.map(\.label) == ["详情", "打开", "批准", "拒绝"])
        #expect(row.actionDescriptors[2].isEnabled == false)
    }

    @Test
    func snapshotTextIncludesUpdatedAgeWhenPresent() {
        let text = SupervisorPendingHubGrantPresentation.snapshotText(
            source: "hub-live",
            hasFreshSnapshot: true,
            updatedAt: 940,
            now: 1_000
        )

        #expect(text == "来源：hub-live · 更新 刚刚 · 快照新鲜")
    }

    private func relatedHubGrantActivity(
        requestId: String
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
            requestedTTLSeconds: 600,
            reason: "browser automation requested",
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
            requiredCapability: "browser.control",
            grantRequestId: "req-1",
            grantId: nil,
            hubStateDirPath: "/tmp/hub-state",
            createdAtMs: 940_000,
            updatedAtMs: 940_000,
            auditRef: "audit-1"
        )

        return SupervisorManager.SupervisorRecentSkillActivity(
            projectId: "project-alpha",
            projectName: "Project Alpha",
            record: record,
            tool: .deviceBrowserControl,
            toolCall: nil,
            toolSummary: "Open dashboard and click submit",
            actionURL: "x-terminal://project/project-alpha"
        )
    }
}
