import Foundation
import Testing
@testable import XTerminal

struct SupervisorAutomationRuntimePresentationTests {

    @Test
    func mapBuildsEmptyStateWithoutSelectedProject() {
        let presentation = SupervisorAutomationRuntimePresentationMapper.map(
            input: .init(
                project: nil,
                recipe: nil,
                statusLine: "automation runtime: idle",
                lastLaunchRef: "",
                selfIterateEnabled: false,
                maxAutoRetryDepth: 2,
                currentCheckpoint: nil,
                latestExecutionReport: nil,
                latestRetryPackage: nil,
                recoveryDecision: nil,
                trustedStatus: nil,
                trustedRequiredPermissions: [],
                retryTrigger: ""
            )
        )

        #expect(presentation.iconName == "bolt.slash.circle")
        #expect(presentation.iconTone == .neutral)
        #expect(presentation.contractText == nil)
        #expect(presentation.nextSafeActionText == nil)
        #expect(presentation.statusAction.isEnabled == false)
        #expect(presentation.projectLine == nil)
        #expect(presentation.controls == nil)
        #expect(presentation.detailRows.isEmpty)
        #expect(presentation.emptyStateText == "先选中一个具体项目，再查看自动化执行。当前 Home 视图不会直接启动项目级运行。")
        #expect(presentation.primaryActions.map(\.isEnabled) == [false, false, false])
        #expect(presentation.advanceActions.allSatisfy { $0.isEnabled == false })
    }

    @Test
    func mapBuildsActiveProjectRuntimeRows() {
        let project = AXProjectEntry(
            projectId: "project-alpha",
            rootPath: "/tmp/project-alpha",
            displayName: "Project Alpha",
            lastOpenedAt: 10,
            manualOrderIndex: nil,
            pinned: false,
            statusDigest: nil,
            currentStateSummary: nil,
            nextStepSummary: nil,
            blockerSummary: nil,
            lastSummaryAt: nil,
            lastEventAt: nil
        )
        let recipe = AXAutomationRecipeRuntimeBinding(
            recipeID: "recipe-alpha",
            recipeVersion: 3,
            lifecycleState: .ready,
            goal: "Ship the next automation slice",
            triggerRefs: ["manual"],
            deliveryTargets: ["chat"],
            acceptancePackRef: "acceptance-pack",
            requiredDeviceToolGroups: ["device.ui.observe", "device.browser.control"],
            requiresTrustedAutomation: true,
            trustedDeviceID: "device-1",
            rolloutStatus: .active
        )
        let checkpoint = XTAutomationRunCheckpoint(
            schemaVersion: XTAutomationRunCheckpoint.currentSchemaVersion,
            runID: "run-1",
            recipeID: recipe.recipeID,
            state: .blocked,
            attempt: 2,
            lastTransition: "running_to_blocked",
            retryAfterSeconds: 45,
            resumeToken: "resume-token",
            checkpointRef: "checkpoint-1",
            stableIdentity: true,
            auditRef: "audit-checkpoint"
        )
        let verification = XTAutomationVerificationReport(
            required: true,
            executed: true,
            commandCount: 2,
            passedCommandCount: 1,
            holdReason: "tests_failed",
            detail: "1 of 2 checks passed",
            commandResults: []
        )
        let report = XTAutomationRunExecutionReport(
            runID: "run-1",
            lineage: XTAutomationRunLineage(
                lineageID: "lineage-1",
                rootRunID: "run-root",
                parentRunID: "run-parent",
                retryDepth: 1
            ),
            recipeRef: recipe.ref,
            totalActionCount: 4,
            executedActionCount: 3,
            succeededActionCount: 2,
            finalState: .blocked,
            holdReason: "needs_input",
            detail: "Execution paused for review",
            actionResults: [],
            verificationReport: verification,
            workspaceDiffReport: nil,
            handoffArtifactPath: "build/reports/handoff.json",
            auditRef: "audit-report"
        )
        let retryPackage = XTAutomationRetryPackage(
            schemaVersion: XTAutomationRetryPackage.currentSchemaVersion,
            generatedAt: 100,
            projectID: project.projectId,
            lineage: XTAutomationRunLineage(
                lineageID: "lineage-1",
                rootRunID: "run-root",
                parentRunID: "run-1",
                retryDepth: 2
            ),
            sourceRunID: "run-1",
            sourceFinalState: .blocked,
            sourceHoldReason: "needs_input",
            sourceHandoffArtifactPath: "build/reports/handoff.json",
            retryStrategy: "bounded_self_iterate",
            retryReason: "verification_failed",
            suggestedNextActions: [],
            additionalEvidenceRefs: [],
            planningMode: "overlay_only",
            planningSummary: "Trim the verify commands and retry the safe subset.",
            runtimePatchOverlay: xtAutomationRuntimePatchOverlay(
                revisedActionGraph: nil,
                revisedVerifyCommands: ["swift test --filter Smoke"]
            ),
            revisedActionGraph: nil,
            revisedVerifyCommands: ["swift test --filter Smoke"],
            planningArtifactPath: "build/reports/retry-plan.json",
            recipeProposalArtifactPath: "build/reports/retry-recipe.json",
            retryRunID: "run-2",
            retryArtifactPath: "build/reports/retry-package.json"
        )
        let recoveryDecision = XTAutomationRestartRecoveryDecision(
            schemaVersion: "xt.automation_restart_recovery_decision.v1",
            runID: "run-1",
            recipeID: recipe.recipeID,
            recoveredState: .blocked,
            decision: .resume,
            holdReason: "",
            stableIdentityPass: true,
            checkpointRef: checkpoint.checkpointRef,
            resumeToken: checkpoint.resumeToken,
            auditRef: "audit-recovery"
        )
        let trustedStatus = AXTrustedAutomationProjectStatus(
            mode: .trustedAutomation,
            state: .active,
            trustedAutomationReady: true,
            permissionOwnerReady: true,
            boundDeviceID: "device-1",
            workspaceBindingHash: "hash-1",
            expectedWorkspaceBindingHash: "hash-1",
            deviceToolGroups: ["device.ui.observe", "device.browser.control"],
            armedDeviceToolGroups: ["device.ui.observe", "device.browser.control"],
            requiredDeviceToolGroups: ["device.ui.observe", "device.browser.control"],
            missingRequiredDeviceToolGroups: [],
            missingPrerequisites: []
        )

        let presentation = SupervisorAutomationRuntimePresentationMapper.map(
            input: .init(
                project: project,
                recipe: recipe,
                statusLine: "automation runtime: run-1 -> blocked",
                lastLaunchRef: "run-1",
                selfIterateEnabled: true,
                maxAutoRetryDepth: 4,
                currentCheckpoint: checkpoint,
                latestExecutionReport: report,
                latestRetryPackage: retryPackage,
                recoveryDecision: recoveryDecision,
                trustedStatus: trustedStatus,
                trustedRequiredPermissions: ["accessibility", "automation"],
                retryTrigger: "self_iterate"
            )
        )

        #expect(presentation.iconName == "bolt.circle.fill")
        #expect(presentation.iconTone == .warning)
        #expect(presentation.title == "自动化执行")
        #expect(presentation.contractText == "合同： 等待指令 · blocker=needs_input")
        #expect(presentation.nextSafeActionText == "安全下一步： clarify_with_user")
        #expect(presentation.projectLine?.text == "项目：Project Alpha (project-alpha)")
        #expect(presentation.recipeLine?.text == "执行配方：recipe-alpha@v3")
        #expect(presentation.goalLine?.text == "目标：Ship the next automation slice")
        #expect(presentation.controls?.selfIterateEnabled == true)
        #expect(presentation.controls?.maxAutoRetryDepth == 4)
        #expect(presentation.controls?.summaryLine.tone == .warning)
        #expect(presentation.controls?.summaryLine.text == "自动自迭代：已开启 · 最大自动重试深度 4")
        #expect(presentation.statusAction.isEnabled)
        #expect(presentation.primaryActions.map(\.isEnabled) == [true, true, true])
        #expect(presentation.advanceActions.allSatisfy { $0.isEnabled })
        #expect(presentation.detailRows.contains { $0.text == "可信设备权限：已生效" && $0.tone == .success })
        #expect(presentation.detailRows.contains { $0.text == "执行状态：受阻 · 已执行 3/4" })
        #expect(presentation.detailRows.contains { $0.text == "验证：1/2 · 1 of 2 checks passed" && $0.tone == .warning })
        #expect(presentation.detailRows.contains { $0.text == "重试触发：自迭代" })
        #expect(presentation.detailRows.contains { $0.text == "恢复决策：继续（无）" })
        #expect(presentation.emptyStateText == nil)
    }

    @Test
    func mapBuildsCheckpointHintWhenCurrentCheckpointDoesNotMatchSelection() {
        let project = AXProjectEntry(
            projectId: "project-beta",
            rootPath: "/tmp/project-beta",
            displayName: "Project Beta",
            lastOpenedAt: 10,
            manualOrderIndex: nil,
            pinned: false,
            statusDigest: nil,
            currentStateSummary: nil,
            nextStepSummary: nil,
            blockerSummary: nil,
            lastSummaryAt: nil,
            lastEventAt: nil
        )
        let recipe = AXAutomationRecipeRuntimeBinding(
            recipeID: "recipe-beta",
            lifecycleState: .ready,
            goal: "Keep project moving",
            triggerRefs: ["manual"],
            deliveryTargets: ["chat"],
            acceptancePackRef: "acceptance-pack"
        )
        let trustedStatus = AXTrustedAutomationProjectStatus(
            mode: .trustedAutomation,
            state: .blocked,
            trustedAutomationReady: false,
            permissionOwnerReady: false,
            boundDeviceID: "device-2",
            workspaceBindingHash: "hash-a",
            expectedWorkspaceBindingHash: "hash-b",
            deviceToolGroups: ["device.ui.observe"],
            armedDeviceToolGroups: [],
            requiredDeviceToolGroups: ["device.ui.observe"],
            missingRequiredDeviceToolGroups: ["device.ui.observe"],
            missingPrerequisites: ["trusted_automation_workspace_mismatch"]
        )

        let presentation = SupervisorAutomationRuntimePresentationMapper.map(
            input: .init(
                project: project,
                recipe: recipe,
                statusLine: "automation runtime: stale",
                lastLaunchRef: "run-stale",
                selfIterateEnabled: false,
                maxAutoRetryDepth: 2,
                currentCheckpoint: XTAutomationRunCheckpoint(
                    schemaVersion: XTAutomationRunCheckpoint.currentSchemaVersion,
                    runID: "run-other",
                    recipeID: recipe.recipeID,
                    state: .running,
                    attempt: 1,
                    lastTransition: "bootstrap_to_running",
                    retryAfterSeconds: 0,
                    resumeToken: "resume-token",
                    checkpointRef: "checkpoint-2",
                    stableIdentity: true,
                    auditRef: "audit-checkpoint"
                ),
                latestExecutionReport: nil,
                latestRetryPackage: nil,
                recoveryDecision: nil,
                trustedStatus: trustedStatus,
                trustedRequiredPermissions: ["accessibility"],
                retryTrigger: ""
            )
        )

        #expect(presentation.iconName == "bolt.circle")
        #expect(presentation.iconTone == .accent)
        #expect(presentation.contractText == "合同： 故障恢复 · blocker=trusted_automation_workspace_mismatch")
        #expect(presentation.nextSafeActionText == "安全下一步： inspect_incident_and_replan")
        #expect(presentation.detailRows.contains { $0.text == "检查点：可以用“状态”或“恢复”从最近日志重建最新状态" })
        #expect(presentation.detailRows.contains { $0.text == "可信设备权限：已阻塞" && $0.tone == .warning })
        #expect(presentation.detailRows.contains { $0.text == "缺少必需设备能力：UI 观察" && $0.tone == .warning })
        #expect(presentation.primaryActions.map(\.isEnabled) == [true, true, true])
    }

    @Test
    func mapBuildsGrantResolutionContractWhenAutomationBlockedByGrant() {
        let project = AXProjectEntry(
            projectId: "project-gamma",
            rootPath: "/tmp/project-gamma",
            displayName: "Project Gamma",
            lastOpenedAt: 10,
            manualOrderIndex: nil,
            pinned: false,
            statusDigest: nil,
            currentStateSummary: nil,
            nextStepSummary: nil,
            blockerSummary: nil,
            lastSummaryAt: nil,
            lastEventAt: nil
        )
        let recipe = AXAutomationRecipeRuntimeBinding(
            recipeID: "recipe-gamma",
            lifecycleState: .ready,
            goal: "Deliver the next connector action",
            triggerRefs: ["manual"],
            deliveryTargets: ["chat"],
            acceptancePackRef: "acceptance-pack"
        )
        let checkpoint = XTAutomationRunCheckpoint(
            schemaVersion: XTAutomationRunCheckpoint.currentSchemaVersion,
            runID: "run-gamma-1",
            recipeID: recipe.recipeID,
            state: .blocked,
            attempt: 1,
            lastTransition: "running_to_blocked",
            retryAfterSeconds: 120,
            resumeToken: "resume-token",
            checkpointRef: "checkpoint-gamma",
            stableIdentity: true,
            auditRef: "audit-gamma"
        )
        let report = XTAutomationRunExecutionReport(
            runID: "run-gamma-1",
            lineage: nil,
            recipeRef: recipe.ref,
            totalActionCount: 1,
            executedActionCount: 0,
            succeededActionCount: 0,
            finalState: .blocked,
            holdReason: "grant_pending_connector_side_effect",
            detail: "Blocked by Hub grant boundary",
            actionResults: [],
            verificationReport: nil,
            workspaceDiffReport: nil,
            handoffArtifactPath: "",
            auditRef: "audit-gamma-report"
        )

        let presentation = SupervisorAutomationRuntimePresentationMapper.map(
            input: .init(
                project: project,
                recipe: recipe,
                statusLine: "automation runtime: run-gamma-1 -> blocked",
                lastLaunchRef: "run-gamma-1",
                selfIterateEnabled: false,
                maxAutoRetryDepth: 2,
                currentCheckpoint: checkpoint,
                latestExecutionReport: report,
                latestRetryPackage: nil,
                recoveryDecision: nil,
                trustedStatus: nil,
                trustedRequiredPermissions: [],
                retryTrigger: ""
            )
        )

        #expect(presentation.contractText == "合同： 授权处理 · blocker=grant_pending_connector_side_effect")
        #expect(presentation.nextSafeActionText == "安全下一步： open_hub_grants")
    }
}
