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
    func mapHumanizesActionScopedVerificationContract() {
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
            recipeVersion: 1,
            lifecycleState: .ready,
            goal: "Action scoped verify contract",
            triggerRefs: ["manual"],
            deliveryTargets: ["chat"],
            acceptancePackRef: "acceptance-pack",
            rolloutStatus: .active
        )
        let report = XTAutomationRunExecutionReport(
            runID: "run-beta",
            recipeRef: recipe.ref,
            totalActionCount: 1,
            executedActionCount: 1,
            succeededActionCount: 1,
            finalState: .delivered,
            holdReason: "",
            detail: "Execution delivered",
            actionResults: [],
            verificationReport: XTAutomationVerificationReport(
                required: true,
                executed: true,
                commandCount: 1,
                passedCommandCount: 1,
                holdReason: "",
                detail: "verify_passed:1/1",
                commandResults: [],
                contract: XTAutomationVerificationContract(
                    expectedState: "post_change_verification_passes",
                    verifyMethod: "recipe_action_verify_commands",
                    retryPolicy: "manual_retry_or_replan",
                    holdPolicy: "block_run_and_emit_structured_blocker",
                    evidenceRequired: true,
                    triggerActionIDs: ["write_file"],
                    verifyCommands: ["swift test --filter ActionScoped"]
                )
            ),
            workspaceDiffReport: nil,
            handoffArtifactPath: "build/reports/handoff.json",
            auditRef: "audit-report-beta"
        )
        let checkpoint = XTAutomationRunCheckpoint(
            schemaVersion: XTAutomationRunCheckpoint.currentSchemaVersion,
            runID: "run-beta",
            recipeID: recipe.recipeID,
            state: .delivered,
            attempt: 1,
            lastTransition: "running_to_delivered",
            retryAfterSeconds: 0,
            resumeToken: "",
            checkpointRef: "checkpoint-beta",
            stableIdentity: true,
            currentStepID: "verification",
            currentStepTitle: "Run project verification",
            currentStepState: .done,
            currentStepSummary: "verify_passed:1/1",
            auditRef: "audit-checkpoint-beta"
        )

        let presentation = SupervisorAutomationRuntimePresentationMapper.map(
            input: .init(
                project: project,
                recipe: recipe,
                statusLine: "automation runtime: delivered",
                lastLaunchRef: "run-beta",
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

        #expect(presentation.detailRows.contains { $0.id == "verify_contract" && $0.text.contains("步骤自带校验命令") })
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
            currentStepID: "step-verify-smoke",
            currentStepTitle: "Run focused smoke checks",
            currentStepState: .retryWait,
            currentStepSummary: "Waiting for the bounded retry window before re-running the reduced verify set.",
            auditRef: "audit-checkpoint"
        )
        let verification = XTAutomationVerificationReport(
            required: true,
            executed: true,
            commandCount: 2,
            passedCommandCount: 1,
            holdReason: "tests_failed",
            detail: "1 of 2 checks passed",
            commandResults: [],
            contract: XTAutomationVerificationContract(
                expectedState: "post_change_verification_passes",
                verifyMethod: "project_verify_commands",
                retryPolicy: "retry_failed_verify_commands_within_budget",
                holdPolicy: "block_run_and_emit_structured_blocker",
                evidenceRequired: true,
                triggerActionIDs: ["apply_patch"],
                verifyCommands: ["swift test --filter Smoke", "swift test --filter Verify"]
            )
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
            ,
            structuredBlocker: XTAutomationBlockerDescriptor(
                code: "automation_verify_failed",
                summary: "Verification narrowed to failing smoke checks",
                stage: .verification,
                detail: "1 of 2 checks passed",
                nextSafeAction: "rerun_focused_verification",
                retryEligible: true,
                currentStepID: "step-verify-smoke",
                currentStepTitle: "Run focused smoke checks",
                currentStepState: .retryWait,
                currentStepSummary: "Waiting for the bounded retry window before re-running the reduced verify set."
            )
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
            sourceBlocker: XTAutomationBlockerDescriptor(
                code: "automation_verify_failed",
                summary: "Verification narrowed to failing smoke checks",
                stage: .verification,
                detail: "1 of 2 checks passed",
                nextSafeAction: "rerun_focused_verification",
                retryEligible: true,
                currentStepID: "step-verify-smoke",
                currentStepTitle: "Run focused smoke checks",
                currentStepState: .retryWait,
                currentStepSummary: "Waiting for the bounded retry window before re-running the reduced verify set."
            ),
            retryStrategy: "bounded_self_iterate",
            retryReason: "verification_failed",
            retryReasonDescriptor: XTAutomationRetryReasonDescriptor(
                code: "automation_verify_failed",
                category: .verification,
                summary: "Retry only the failing smoke verification set",
                strategy: "bounded_self_iterate",
                blockerCode: "automation_verify_failed",
                planningMode: "overlay_only",
                currentStepID: "step-verify-smoke",
                currentStepTitle: "Run focused smoke checks",
                currentStepState: .retryWait,
                currentStepSummary: "Waiting for the bounded retry window before re-running the reduced verify set."
            ),
            suggestedNextActions: [],
            additionalEvidenceRefs: [],
            planningMode: "overlay_only",
            planningSummary: "Trim the verify commands and retry the safe subset.",
            runtimePatchOverlay: xtAutomationRuntimePatchOverlay(
                revisedActionGraph: nil,
                revisedVerifyCommands: ["swift test --filter Smoke"],
                revisedVerificationContract: XTAutomationVerificationContract(
                    expectedState: "post_change_verification_passes",
                    verifyMethod: "project_verify_commands_override",
                    retryPolicy: "retry_failed_verify_commands_within_budget",
                    holdPolicy: "block_run_and_emit_structured_blocker",
                    evidenceRequired: true,
                    triggerActionIDs: ["mutate-readme"],
                    verifyCommands: ["swift test --filter Smoke"]
                )
            ),
            revisedActionGraph: nil,
            revisedVerifyCommands: ["swift test --filter Smoke"],
            revisedVerificationContract: XTAutomationVerificationContract(
                expectedState: "post_change_verification_passes",
                verifyMethod: "project_verify_commands_override",
                retryPolicy: "retry_failed_verify_commands_within_budget",
                holdPolicy: "block_run_and_emit_structured_blocker",
                evidenceRequired: true,
                triggerActionIDs: ["mutate-readme"],
                verifyCommands: ["swift test --filter Smoke"]
            ),
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
        #expect(presentation.nextSafeActionText == "安全下一步： 先向用户确认")
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
        #expect(
            presentation.detailRows.contains {
                $0.text == "验证合同：项目校验命令 · 目标=变更后验证通过 · 失败后=预算内只重试失败验证 · 证据必需"
            }
        )
        #expect(
            presentation.detailRows.contains {
                $0.text == "当前步骤：Run focused smoke checks · 等待重试 · Waiting for the bounded retry window before re-running the reduced verify set."
                    && $0.tone == .warning
            }
        )
        #expect(
            presentation.detailRows.contains {
                $0.text == "结构化阻塞：Verification narrowed to failing smoke checks · verification · next=rerun_focused_verification"
            }
        )
        #expect(presentation.detailRows.contains { $0.text == "重试触发：自迭代" })
        #expect(
            presentation.detailRows.contains {
                $0.text == "重试原因：Retry only the failing smoke verification set · verification · strategy=bounded_self_iterate"
            }
        )
        #expect(
            presentation.detailRows.contains {
                $0.text == "重试验证合同：覆写校验命令 · 目标=变更后验证通过 · 失败后=预算内只重试失败验证 · 证据必需"
            }
        )
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
        #expect(presentation.nextSafeActionText == "安全下一步： 先检查当前异常，再决定是否重规划")
        #expect(presentation.detailRows.contains { $0.text == "检查点：可以用“状态”或“恢复”从最近日志重建最新状态" })
        #expect(presentation.detailRows.contains { $0.text == "可信设备权限：已阻塞" && $0.tone == .warning })
        #expect(presentation.detailRows.contains { $0.text == "缺少必需设备能力：UI 观察" && $0.tone == .warning })
        #expect(presentation.primaryActions.map(\.isEnabled) == [true, true, true])
    }

    @Test
    func mapSurfacesA4RuntimeReadinessHoldAndDisablesExecutionAdvancers() {
        let project = AXProjectEntry(
            projectId: "project-a4",
            rootPath: "/tmp/project-a4",
            displayName: "Project A4",
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
            recipeID: "recipe-a4",
            lifecycleState: .ready,
            goal: "Drive the governed A4 lane",
            triggerRefs: ["manual"],
            deliveryTargets: ["chat"],
            acceptancePackRef: "acceptance-pack"
        )

        let presentation = SupervisorAutomationRuntimePresentationMapper.map(
            input: .init(
                project: project,
                recipe: recipe,
                statusLine: "automation runtime: idle",
                lastLaunchRef: "run-a4-1",
                selfIterateEnabled: true,
                maxAutoRetryDepth: 3,
                currentCheckpoint: nil,
                latestExecutionReport: nil,
                latestRetryPackage: nil,
                recoveryDecision: nil,
                trustedStatus: AXTrustedAutomationProjectStatus(
                    mode: .trustedAutomation,
                    state: .blocked,
                    trustedAutomationReady: false,
                    permissionOwnerReady: false,
                    boundDeviceID: "device-a4",
                    workspaceBindingHash: "hash-a4",
                    expectedWorkspaceBindingHash: "hash-a4",
                    deviceToolGroups: ["device.browser.control"],
                    armedDeviceToolGroups: [],
                    requiredDeviceToolGroups: ["device.browser.control"],
                    missingRequiredDeviceToolGroups: ["device.browser.control"],
                    missingPrerequisites: ["trusted_automation_not_ready"]
                ),
                trustedRequiredPermissions: ["automation", "screen_recording"],
                retryTrigger: "",
                runtimeReadiness: makeBlockedA4RuntimeReadinessSnapshot()
            )
        )

        let primaryEnabled = presentation.primaryActions.map { $0.isEnabled }
        let hasReadinessLine = presentation.detailRows.contains {
            $0.id == "runtime_readiness"
                && $0.text == "A4 Agent 已配置，但 runtime ready 还没完成。"
                && $0.tone == .warning
        }
        let hasReadinessMissingLine = presentation.detailRows.contains {
            $0.id == "runtime_readiness_missing"
                && $0.text == "缺口：执行面被收束到 guided / 受治理自动化未就绪"
                && $0.tone == .warning
        }

        #expect(presentation.contractText == "合同： 故障恢复 · A4 Agent 已配置，但 runtime ready 还没完成。")
        #expect(presentation.nextSafeActionText == "安全下一步： 先检查当前异常，再决定是否重规划")
        #expect(primaryEnabled == [false, false, true])
        #expect(presentation.advanceActions.allSatisfy { $0.isEnabled == false })
        #expect(hasReadinessLine)
        #expect(hasReadinessMissingLine)
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
        #expect(presentation.nextSafeActionText == "安全下一步： 打开 Hub 授权面板")
    }
}

private func makeBlockedA4RuntimeReadinessSnapshot() -> AXProjectGovernanceRuntimeReadinessSnapshot {
    let detailLines = [
        "project_governance_runtime_readiness_schema_version=\(AXProjectGovernanceRuntimeReadinessSnapshot.currentSchemaVersion)",
        "project_governance_configured_execution_tier=\(AXProjectExecutionTier.a4OpenClaw.rawValue)",
        "project_governance_effective_execution_tier=\(AXProjectExecutionTier.a4OpenClaw.rawValue)",
        "project_governance_configured_runtime_surface_mode=\(AXProjectRuntimeSurfaceMode.trustedOpenClawMode.rawValue)",
        "project_governance_effective_runtime_surface_mode=\(AXProjectRuntimeSurfaceMode.guided.rawValue)",
        "project_governance_runtime_surface_override_mode=\(AXProjectRuntimeSurfaceHubOverrideMode.clampGuided.rawValue)",
        "project_governance_trusted_automation_state=\(AXTrustedAutomationProjectState.blocked.rawValue)",
        "project_governance_requires_a4_runtime_ready=true",
        "project_governance_runtime_ready=false",
        "project_governance_runtime_readiness_state=\(AXProjectGovernanceRuntimeReadinessState.blocked.rawValue)",
        "project_governance_runtime_readiness_summary=A4 Agent 已配置，但 runtime ready 还没完成。",
        "project_governance_missing_readiness=runtime_surface_clamped_guided,trusted_automation_not_ready",
        "project_governance_runtime_readiness_missing_summary=缺口：执行面被收束到 guided / 受治理自动化未就绪"
    ]
    return AXProjectGovernanceRuntimeReadinessSnapshot(detailLines: detailLines)!
}
