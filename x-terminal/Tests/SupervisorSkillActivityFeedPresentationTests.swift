import Foundation
import Testing
@testable import XTerminal

struct SupervisorSkillActivityFeedPresentationTests {

    @Test
    func mapPrioritizesActionableItemsAndBuildsStructuredSummary() {
        let completed = activity(
            requestId: "completed",
            skillId: "summarize",
            status: .completed,
            updatedAtMs: 1_000
        )
        let running = activity(
            requestId: "running",
            skillId: "agent-browser",
            status: .running,
            updatedAtMs: 2_000
        )
        let failed = activity(
            requestId: "failed",
            skillId: "self-improving-agent",
            status: .failed,
            updatedAtMs: 4_000
        )
        let blocked = activity(
            requestId: "blocked",
            skillId: "code-review",
            status: .blocked,
            updatedAtMs: 3_500
        )
        let hubGrant = activity(
            requestId: "grant",
            skillId: "agent-browser",
            status: .awaitingAuthorization,
            requiredCapability: "web.fetch",
            updatedAtMs: 3_000
        )
        let localApproval = activity(
            requestId: "local",
            skillId: "skill-creator",
            status: .awaitingAuthorization,
            updatedAtMs: 2_500
        )

        let presentation = SupervisorSkillActivityFeedPresentation.map(
            items: [completed, running, failed, blocked, hubGrant, localApproval]
        )

        #expect(presentation.summaryLine.contains("可处理 4"))
        #expect(presentation.summaryLine.contains("本地审批 1"))
        #expect(presentation.summaryLine.contains("Hub 授权 1"))
        #expect(presentation.summaryLine.contains("待恢复 2"))
        #expect(presentation.summaryLine.contains("进行中 1"))
        #expect(presentation.actionableCount == 4)
        #expect(presentation.items.map(\.requestId) == [
            "local",
            "grant",
            "failed",
            "blocked",
            "running",
            "completed"
        ])
    }

    @Test
    func mapFallsBackToQueuedAndCompletedWhenNoActionableItemsExist() {
        let queued = activity(
            requestId: "queued",
            skillId: "find-skills",
            status: .queued,
            updatedAtMs: 5_000
        )
        let completedNew = activity(
            requestId: "completed-new",
            skillId: "summarize",
            status: .completed,
            updatedAtMs: 4_000
        )
        let completedOld = activity(
            requestId: "completed-old",
            skillId: "summarize",
            status: .completed,
            updatedAtMs: 2_000
        )

        let presentation = SupervisorSkillActivityFeedPresentation.map(
            items: [completedOld, queued, completedNew]
        )

        #expect(presentation.summaryLine == "排队中 1 · 已完成 2")
        #expect(presentation.actionableCount == 0)
        #expect(presentation.items.map(\.requestId) == [
            "queued",
            "completed-new",
            "completed-old"
        ])
    }

    @Test
    func mapKeepsEmptyStateNeutral() {
        let presentation = SupervisorSkillActivityFeedPresentation.map(items: [])

        #expect(presentation.summaryLine == "最近活动")
        #expect(presentation.items.isEmpty)
        #expect(presentation.isEmpty)
        #expect(presentation.actionableCount == 0)
    }

    @Test
    func mapClassifiesAwaitingAuthorizationUsingGovernedReadinessBeforeCapabilityFallback() {
        let localApproval = activity(
            requestId: "local-readiness",
            skillId: "guarded-automation",
            status: .awaitingAuthorization,
            requiredCapability: "web.fetch",
            readinessState: .localApprovalRequired,
            updatedAtMs: 4_000
        )
        let hubGrant = activity(
            requestId: "grant-readiness",
            skillId: "agent-browser",
            status: .awaitingAuthorization,
            requiredCapability: nil,
            readinessState: .grantRequired,
            updatedAtMs: 3_000
        )

        let presentation = SupervisorSkillActivityFeedPresentation.map(
            items: [hubGrant, localApproval]
        )

        #expect(presentation.summaryLine.contains("可处理 2"))
        #expect(presentation.summaryLine.contains("本地审批 1"))
        #expect(presentation.summaryLine.contains("Hub 授权 1"))
        #expect(presentation.items.map(\.requestId) == [
            "local-readiness",
            "grant-readiness"
        ])
    }

    private func activity(
        requestId: String,
        skillId: String,
        status: SupervisorSkillCallStatus,
        requiredCapability: String? = nil,
        readinessState: XTSkillExecutionReadinessState? = nil,
        updatedAtMs: Int64
    ) -> SupervisorManager.SupervisorRecentSkillActivity {
        let readiness = readinessState.map { state in
            XTSkillExecutionReadiness(
                schemaVersion: XTSkillExecutionReadiness.currentSchemaVersion,
                projectId: "project-alpha",
                skillId: skillId,
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
                executionReadiness: state.rawValue,
                runnableNow: false,
                denyCode: state == .grantRequired ? "grant_required" : "local_approval_required",
                reasonCode: state == .grantRequired
                    ? "grant floor privileged requires hub grant"
                    : "approval floor local_approval requires local confirmation",
                grantFloor: XTSkillGrantFloor.privileged.rawValue,
                approvalFloor: state == .grantRequired
                    ? XTSkillApprovalFloor.hubGrant.rawValue
                    : XTSkillApprovalFloor.localApproval.rawValue,
                requiredGrantCapabilities: state == .grantRequired ? ["browser.interact"] : [],
                requiredRuntimeSurfaces: ["managed_browser_runtime"],
                stateLabel: XTSkillCapabilityProfileSupport.readinessLabel(state.rawValue),
                installHint: "",
                unblockActions: state == .grantRequired ? ["request_hub_grant"] : ["request_local_approval"],
                auditRef: "audit-readiness-\(requestId)",
                doctorAuditRef: "",
                vetterAuditRef: "",
                resolvedSnapshotId: "snapshot-\(requestId)",
                grantSnapshotRef: ""
            )
        }
        let record = SupervisorSkillCallRecord(
            schemaVersion: SupervisorSkillCallRecord.currentSchemaVersion,
            requestId: requestId,
            projectId: "project-alpha",
            jobId: "job-1",
            planId: "plan-1",
            stepId: "step-1",
            skillId: skillId,
            toolName: ToolName.run_command.rawValue,
            status: status,
            payload: [:],
            currentOwner: "supervisor",
            resultSummary: "",
            denyCode: "",
            resultEvidenceRef: nil,
            readiness: readiness,
            requiredCapability: requiredCapability,
            grantRequestId: requiredCapability == nil ? nil : "grant-\(requestId)",
            grantId: nil,
            createdAtMs: updatedAtMs - 500,
            updatedAtMs: updatedAtMs,
            auditRef: "audit-\(requestId)"
        )

        return SupervisorManager.SupervisorRecentSkillActivity(
            projectId: "project-alpha",
            projectName: "Project Alpha",
            record: record,
            tool: .run_command,
            toolCall: nil,
            toolSummary: "swift test",
            actionURL: "x-terminal://project/project-alpha"
        )
    }
}
