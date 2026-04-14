import Foundation
import Testing
@testable import XTerminal

struct AXProjectResumeBriefBuilderTests {
    @Test
    func returnsFallbackWhenProjectHasNoDurableArtifacts() throws {
        let root = try makeProjectRoot(named: "resume-empty")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        let rendered = AXProjectResumeBriefBuilder.render(ctx: ctx)

        #expect(rendered.contains("当前项目还没有足够的持久记忆"))
    }

    @Test
    func prefersSessionSummaryStateButKeepsCanonicalGoalAndDecisions() throws {
        let root = try makeProjectRoot(named: "resume-summary-preferred")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()
        let projectId = AXProjectRegistryStore.projectId(forRoot: root)

        var memory = AXMemory.new(projectName: "resume-summary-preferred", projectRoot: root.path)
        memory.goal = "Preserve precise project handoff quality across AI switches."
        memory.currentState = ["Canonical memory exists"]
        memory.decisions = ["Keep resume summary local-only even when tokens are cheap."]
        memory.nextSteps = ["Old next step from canonical memory"]
        try AXProjectStore.saveMemory(memory, for: ctx)

        let summary = AXSessionSummaryCapsule(
            schemaVersion: AXSessionSummaryCapsule.schemaVersion,
            phase: .sessionResetOrSwitch,
            projectId: projectId,
            projectRoot: root.path,
            reason: "project_switch",
            createdAtMs: 300_000,
            memorySummary: AXMemoryLifecycleMemorySummary(
                goal: "",
                currentState: "Blocked on validating the resume entry route.",
                blocker: "Need to verify the summary stays out of the main prompt.",
                nextStep: "Land /resume and natural-language resume trigger."
            ),
            workingSetSummary: AXMemoryLifecycleWorkingSetSummary(
                recentMessageCount: 2,
                recentUserTurnCount: 1,
                latestUserMessage: "Please give me a clean handoff summary next time.",
                latestAssistantMessage: "I will build a dedicated local-only resume entry.",
                resumeSummary: "latest_user=Please give me a clean handoff summary next time.",
                refs: []
            ),
            refs: [ctx.memoryJSONURL.path]
        )

        try FileManager.default.createDirectory(
            at: ctx.sessionSummariesDir,
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(summary)
        try data.write(to: ctx.latestSessionSummaryURL, options: .atomic)

        let rendered = AXProjectResumeBriefBuilder.render(ctx: ctx)

        #expect(rendered.contains("当前目标：Preserve precise project handoff quality across AI switches."))
        #expect(rendered.contains("当前状态：Blocked on validating the resume entry route."))
        #expect(rendered.contains("当前阻塞：Need to verify the summary stays out of the main prompt."))
        #expect(rendered.contains("建议下一步：Land /resume and natural-language resume trigger."))
        #expect(rendered.contains("Keep resume summary local-only even when tokens are cheap."))
        #expect(rendered.contains("最后一条用户信息"))
        #expect(rendered.contains("来源：canonical memory / latest session summary"))
    }

    @Test
    func includesLatestUIReviewWhenPresent() throws {
        let root = try makeProjectRoot(named: "resume-ui-review")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()

        var memory = AXMemory.new(projectName: "resume-ui-review", projectRoot: root.path)
        memory.goal = "Keep local handoff quality high after browser observations."
        memory.currentState = ["Browser observation pipeline is active"]
        memory.nextSteps = ["Use latest UI review in the resume brief"]
        try AXProjectStore.saveMemory(memory, for: ctx)

        try writeSampleUIReview(
            ctx: ctx,
            projectId: AXProjectRegistryStore.projectId(forRoot: root),
            reviewID: "uir-resume-test",
            verdict: .attentionNeeded,
            confidence: .medium,
            sufficientEvidence: true,
            objectiveReady: false,
            issueCodes: ["critical_action_not_visible"],
            summary: "attention needed; confidence=medium; issues=critical_action_not_visible"
        )

        let rendered = AXProjectResumeBriefBuilder.render(ctx: ctx)

        #expect(rendered.contains("最近一次 UI review："))
        #expect(rendered.contains("verdict=attention_needed"))
        #expect(rendered.contains("issues=critical_action_not_visible"))
        #expect(rendered.contains("来源：canonical memory"))
        #expect(rendered.contains("latest ui review"))
    }

    @Test
    func humanizesRouteFailureReasonsInExecutionAndRouteMemorySections() throws {
        let root = try makeProjectRoot(named: "resume-route-reason-humanized")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()

        let usageEntry: [String: Any] = [
            "type": "ai_usage",
            "role": AXRole.coder.rawValue,
            "created_at": 123.0,
            "stage": "reply",
            "requested_model_id": "openai/gpt-5.4",
            "actual_model_id": "qwen3-14b-mlx",
            "runtime_provider": "Hub (Local)",
            "execution_path": "local_fallback_after_remote_error",
            "fallback_reason_code": "grant_required;deny_code=remote_export_blocked",
            "deny_code": "remote_export_blocked"
        ]
        let usageData = try JSONSerialization.data(withJSONObject: usageEntry)
        let usageLine = try #require(String(data: usageData, encoding: .utf8))
        try (usageLine + "\n").write(to: ctx.usageLogURL, atomically: true, encoding: .utf8)

        let rendered = AXProjectResumeBriefBuilder.render(ctx: ctx)

        #expect(rendered.contains("最近一次 coder 执行：本地 qwen3-14b-mlx 兜底（远端首选 openai/gpt-5.4，原因：Hub remote export gate 阻断了远端请求（remote_export_blocked））"))
        #expect(rendered.contains("路由记忆："))
        #expect(rendered.contains("最近实际落点是 qwen3-14b-mlx"))
        #expect(rendered.contains("最近失败原因是 Hub remote export gate 阻断了远端请求（remote_export_blocked）"))
    }

    @Test
    func humanizesKnownBlockerCodesInResumeSummary() throws {
        let root = try makeProjectRoot(named: "resume-blocker-humanized")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()
        let projectId = AXProjectRegistryStore.projectId(forRoot: root)

        let summary = AXSessionSummaryCapsule(
            schemaVersion: AXSessionSummaryCapsule.schemaVersion,
            phase: .sessionResetOrSwitch,
            projectId: projectId,
            projectRoot: root.path,
            reason: "project_switch",
            createdAtMs: 300_100,
            memorySummary: AXMemoryLifecycleMemorySummary(
                goal: "Keep remote execution unblocked.",
                currentState: "Authorization path needs review.",
                blocker: "grant_required;deny_code=remote_export_blocked",
                nextStep: "Review Hub remote export gate."
            ),
            workingSetSummary: AXMemoryLifecycleWorkingSetSummary(
                recentMessageCount: 1,
                recentUserTurnCount: 1,
                latestUserMessage: "Why did remote execution stop?",
                latestAssistantMessage: "I will summarize the blocker locally.",
                resumeSummary: "latest_user=Why did remote execution stop?",
                refs: []
            ),
            refs: []
        )

        try FileManager.default.createDirectory(
            at: ctx.sessionSummariesDir,
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(summary)
        try data.write(to: ctx.latestSessionSummaryURL, options: .atomic)

        let rendered = AXProjectResumeBriefBuilder.render(ctx: ctx)

        #expect(rendered.contains("当前阻塞：Hub remote export gate 阻断了远端请求（remote_export_blocked）"))
    }

    @Test
    func includesAutomationCheckpointStepContextWhenRecentRunExists() throws {
        let root = try makeProjectRoot(named: "resume-automation-checkpoint")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()

        AXProjectStore.appendRawLog(
            [
                "type": "automation_checkpoint",
                "created_at": 500_000,
                "run_id": "run-checkpoint-1",
                "recipe_id": "recipe-runtime",
                "state": XTAutomationRunState.blocked.rawValue,
                "attempt": 2,
                "last_transition": "running_to_blocked",
                "retry_after_seconds": 45,
                "resume_token": "resume-token",
                "checkpoint_ref": "checkpoint-ref",
                "stable_identity": true,
                "current_step_id": "step-verify",
                "current_step_title": "Verify focused smoke tests",
                "current_step_state": XTAutomationRunStepState.retryWait.rawValue,
                "current_step_summary": "Waiting for the bounded retry window before retrying the verify set.",
                "audit_ref": "audit-checkpoint"
            ],
            for: ctx
        )

        let rendered = AXProjectResumeBriefBuilder.render(ctx: ctx)

        #expect(rendered.contains("自动化接续来源：本地 checkpoint 重新水化（仅用于恢复接续，不替代 durable truth）"))
        #expect(rendered.contains("自动化检查点：run run-checkpoint-1 · 受阻 · 第 2 次"))
        #expect(rendered.contains("Verify focused smoke tests · 等待重试"))
        #expect(rendered.contains("Waiting for the bounded retry window before retrying the verify set."))
        #expect(rendered.contains("来源：automation checkpoint"))
    }

    @Test
    func includesAutomationVerificationBlockerAndRetryContextInResumeBrief() throws {
        let root = try makeProjectRoot(named: "resume-automation-continuity")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()
        let sourceLineage = XTAutomationRunLineage.root(runID: "run-step-memory-1")
        let retryLineage = sourceLineage.retryChild(parentRunID: "run-step-memory-1")

        AXProjectStore.appendRawLog(
            [
                "type": "automation_checkpoint",
                "created_at": 510_000,
                "run_id": "run-step-memory-1",
                "recipe_id": "recipe-step-memory",
                "state": XTAutomationRunState.blocked.rawValue,
                "attempt": 2,
                "last_transition": "running_to_blocked",
                "retry_after_seconds": 45,
                "resume_token": "resume-step-memory",
                "checkpoint_ref": "checkpoint-step-memory",
                "stable_identity": true,
                "current_step_id": "step-verify",
                "current_step_title": "Verify focused smoke tests",
                "current_step_state": XTAutomationRunStepState.retryWait.rawValue,
                "current_step_summary": "Waiting before retrying the reduced verify set.",
                "audit_ref": "audit-step-memory-checkpoint"
            ],
            for: ctx
        )
        AXProjectStore.appendRawLog(
            [
                "type": "automation_execution",
                "phase": "completed",
                "created_at": 510_001,
                "run_id": "run-step-memory-1",
                "recipe_ref": "recipe-step-memory",
                "final_state": XTAutomationRunState.blocked.rawValue,
                "hold_reason": "automation_verify_failed",
                "detail": "Smoke tests are still red.",
                "executed_action_count": 2,
                "succeeded_action_count": 1,
                "total_action_count": 2,
                "current_step_id": "step-verify",
                "current_step_title": "Verify focused smoke tests",
                "current_step_state": XTAutomationRunStepState.retryWait.rawValue,
                "current_step_summary": "Waiting before retrying the reduced verify set.",
                "verification": [
                    "required": true,
                    "executed": true,
                    "command_count": 3,
                    "passed_command_count": 1,
                    "hold_reason": "automation_verify_failed",
                    "detail": "Smoke tests are still red."
                ],
                "blocker": [
                    "code": "automation_verify_failed",
                    "summary": "Smoke tests are still red.",
                    "stage": XTAutomationBlockerStage.verification.rawValue,
                    "detail": "Focused smoke tests failed during retry.",
                    "next_safe_action": "shrink verify scope and retry",
                    "retry_eligible": true
                ],
                "audit_ref": "audit-step-memory-execution"
            ],
            for: ctx
        )
        AXProjectStore.appendRawLog(
            [
                "type": "automation_retry",
                "status": "scheduled",
                "created_at": 510_002,
                "source_run_id": "run-step-memory-1",
                "retry_run_id": "run-step-memory-2",
                "lineage_id": retryLineage.lineageID,
                "root_run_id": retryLineage.rootRunID,
                "parent_run_id": retryLineage.parentRunID,
                "retry_depth": retryLineage.retryDepth,
                "retry_strategy": "shrink_verify_scope",
                "retry_reason": "retry_verify_scope",
                "retry_reason_descriptor": [
                    "code": "retry_verify_scope",
                    "category": XTAutomationRetryReasonCategory.verification.rawValue,
                    "summary": "Retry with a reduced verify set",
                    "strategy": "shrink_verify_scope",
                    "blocker_code": "automation_verify_failed"
                ]
            ],
            for: ctx
        )
        AXProjectStore.appendRawLog(
            [
                "type": "automation_run_recovery",
                "created_at": 510_003,
                "run_id": "run-step-memory-1",
                "recipe_id": "recipe-step-memory",
                "recovered_state": XTAutomationRunState.blocked.rawValue,
                "decision": XTAutomationRestartRecoveryAction.resume.rawValue,
                "hold_reason": NSNull(),
                "stable_identity_pass": true,
                "checkpoint_ref": "checkpoint-step-memory",
                "resume_token": "resume-step-memory",
                "recovery_mode": XTAutomationRestartRecoveryMode.operatorOverride.rawValue,
                "resume_mode": XTAutomationRecoveryResumeMode.retryPackage.rawValue,
                "retry_run_id": "run-step-memory-2",
                "retry_strategy": "shrink_verify_scope",
                "retry_reason": "retry_verify_scope",
                "delivery_closure_source": XTAutomationDeliveryClosureProjectionSource.retryPackage.rawValue,
                "delivery_closure_run_id": "run-step-memory-2",
                "lineage_id": retryLineage.lineageID,
                "root_run_id": retryLineage.rootRunID,
                "parent_run_id": retryLineage.parentRunID,
                "retry_depth": retryLineage.retryDepth,
                "audit_ref": "audit-step-memory-recovery"
            ],
            for: ctx
        )

        let rendered = AXProjectResumeBriefBuilder.render(ctx: ctx)

        #expect(rendered.contains("自动化接续来源：本地 checkpoint + execution report + retry package 重新水化（仅用于恢复接续，不替代 durable truth）"))
        #expect(rendered.contains("自动化检查点：run run-step-memory-1 · 接续 run run-step-memory-2 · 受阻 · 第 2 次"))
        #expect(rendered.contains("接续 run run-step-memory-2"))
        #expect(rendered.contains("自动化恢复落点：最近恢复继续 · resume retry package · 策略 shrink_verify_scope · retry run run-step-memory-2"))
        #expect(rendered.contains("Verify focused smoke tests · 等待重试"))
        #expect(rendered.contains("验证通过 1/3"))
        #expect(rendered.contains("验证阻塞：Smoke tests are still red."))
        #expect(rendered.contains("重试原因：Retry with a reduced verify set；策略 shrink_verify_scope"))
        #expect(rendered.contains("45 秒后可重试"))
        #expect(rendered.contains("阶段概览：自动化停在"))
    }

    @Test
    func includesStableIdentityFailureInAutomationResumeBrief() throws {
        let root = try makeProjectRoot(named: "resume-automation-stable-identity")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()
        let baseNow = Date().timeIntervalSince1970

        AXProjectStore.appendRawLog(
            [
                "type": "automation_checkpoint",
                "created_at": baseNow - 5,
                "run_id": "run-identity-drift",
                "recipe_id": "recipe-step-memory",
                "state": XTAutomationRunState.blocked.rawValue,
                "attempt": 2,
                "last_transition": "running_to_blocked",
                "retry_after_seconds": 0,
                "resume_token": "resume-identity-drift",
                "checkpoint_ref": "checkpoint-identity-drift",
                "stable_identity": false,
                "current_step_id": "step-verify",
                "current_step_title": "Verify focused smoke tests",
                "current_step_state": XTAutomationRunStepState.blocked.rawValue,
                "current_step_summary": "Stable identity drifted before restart recovery.",
                "audit_ref": "audit-identity-drift-checkpoint"
            ],
            for: ctx
        )

        let rendered = AXProjectResumeBriefBuilder.render(ctx: ctx)

        #expect(rendered.contains("自动化检查点：run run-identity-drift · 受阻 · 第 2 次"))
        #expect(rendered.contains("恢复身份校验失败"))
        #expect(rendered.contains("stable_identity_failed"))
    }

    @Test
    func includesHeartbeatRecoveryProjectionWhenGovernanceRecoveryIsActive() throws {
        let root = try makeProjectRoot(named: "resume-heartbeat-recovery")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()

        let generatedAtMs: Int64 = 1_778_820_120_000
        let schedule = SupervisorReviewScheduleState(
            schemaVersion: SupervisorReviewScheduleState.currentSchemaVersion,
            projectId: AXProjectRegistryStore.projectId(forRoot: root),
            updatedAtMs: generatedAtMs,
            lastHeartbeatAtMs: generatedAtMs,
            lastObservedProgressAtMs: generatedAtMs - 1_200_000,
            lastPulseReviewAtMs: 0,
            lastBrainstormReviewAtMs: 0,
            lastTriggerReviewAtMs: [:],
            nextHeartbeatDueAtMs: generatedAtMs + 300_000,
            nextPulseReviewDueAtMs: generatedAtMs + 180_000,
            nextBrainstormReviewDueAtMs: generatedAtMs + 180_000,
            latestQualitySnapshot: nil,
            openAnomalies: [],
            lastHeartbeatFingerprint: "hb-resume-recovery",
            lastHeartbeatRepeatCount: 2,
            latestProjectPhase: .verify,
            latestExecutionStatus: .blocked,
            latestRiskTier: .high
        )
        let recovery = HeartbeatRecoveryDecision(
            action: .repairRoute,
            urgency: .urgent,
            reasonCode: "route_health_regressed",
            summary: "Repair route before retrying verification.",
            sourceSignals: ["route_flaky"],
            anomalyTypes: [.routeFlaky],
            blockedLaneReasons: [.runtimeError],
            blockedLaneCount: 1,
            stalledLaneCount: 1,
            failedLaneCount: 0,
            recoveringLaneCount: 0,
            requiresUserAction: false
        )
        let snapshot = XTProjectHeartbeatGovernanceDoctorSnapshot(
            projectId: AXProjectRegistryStore.projectId(forRoot: root),
            projectName: "resume-heartbeat-recovery",
            statusDigest: "verification stalled with repeated route issues",
            currentStateSummary: "Verify is blocked on route instability",
            nextStepSummary: "Repair route then retry smoke suite",
            blockerSummary: "route keeps degrading during verify",
            lastHeartbeatAtMs: generatedAtMs,
            latestQualityBand: .hollow,
            latestQualityScore: 18,
            weakReasons: ["evidence_weak", "hollow_progress"],
            openAnomalyTypes: [.routeFlaky],
            projectPhase: .verify,
            executionStatus: .blocked,
            riskTier: .high,
            cadence: makeCadence(baseMs: generatedAtMs),
            digestExplainability: XTHeartbeatDigestExplainability(
                visibility: .shown,
                reasonCodes: ["open_anomalies_present", "recovery_decision_active"],
                whatChangedText: "验证连续多次停在 route 健康问题。",
                whyImportantText: "这已经不是单次抖动，继续重试只会重复空转。",
                systemNextStepText: "系统会先修复 route / dispatch 健康，再尝试恢复执行。"
            ),
            recoveryDecision: recovery,
            projectMemoryReadiness: nil
        )
        let canonical = SupervisorProjectHeartbeatCanonicalSync.record(
            snapshot: snapshot,
            generatedAtMs: generatedAtMs
        )
        _ = XTHeartbeatMemoryProjectionStore.record(
            ctx: ctx,
            snapshot: snapshot,
            schedule: schedule,
            canonicalRecord: canonical,
            generatedAtMs: generatedAtMs
        )

        let rendered = AXProjectResumeBriefBuilder.render(ctx: ctx)

        #expect(rendered.contains("治理恢复：Repair route before retrying verification."))
        #expect(rendered.contains("下一步 系统会先修复 route / dispatch 健康，再尝试恢复执行。"))
        #expect(rendered.contains("来源：heartbeat memory projection"))
    }

    private func makeProjectRoot(named name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "xt_resume_brief_\(name)_\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func writeSampleUIReview(
        ctx: AXProjectContext,
        projectId: String,
        reviewID: String,
        verdict: XTUIReviewVerdict,
        confidence: XTUIReviewConfidence,
        sufficientEvidence: Bool,
        objectiveReady: Bool,
        issueCodes: [String],
        summary: String
    ) throws {
        let review = XTUIReviewRecord(
            schemaVersion: XTUIReviewRecord.currentSchemaVersion,
            reviewID: reviewID,
            projectID: projectId,
            bundleID: "bundle-\(reviewID)",
            bundleRef: "local://.xterminal/ui_observation/bundles/bundle-\(reviewID).json",
            surfaceType: .browserPage,
            probeDepth: .standard,
            objective: "browser_page_actionability",
            verdict: verdict,
            confidence: confidence,
            sufficientEvidence: sufficientEvidence,
            objectiveReady: objectiveReady,
            interactiveTargetCount: 0,
            criticalActionExpected: true,
            criticalActionVisible: false,
            issueCodes: issueCodes,
            checks: [
                XTUIReviewCheck(
                    code: "critical_action_not_visible",
                    status: .warning,
                    detail: "A likely primary action was not visible in the current browser page."
                )
            ],
            summary: summary,
            createdAtMs: 400_000,
            auditRef: "audit-\(reviewID)"
        )
        _ = try XTUIReviewStore.writeReview(review, for: ctx)
    }

    private func makeCadence(baseMs: Int64) -> SupervisorCadenceExplainability {
        SupervisorCadenceExplainability(
            progressHeartbeat: SupervisorCadenceDimensionExplainability(
                dimension: .progressHeartbeat,
                configuredSeconds: 300,
                recommendedSeconds: 300,
                effectiveSeconds: 300,
                effectiveReasonCodes: ["configured"],
                nextDueAtMs: baseMs + 300_000,
                nextDueReasonCodes: ["heartbeat_active"],
                isDue: false
            ),
            reviewPulse: SupervisorCadenceDimensionExplainability(
                dimension: .reviewPulse,
                configuredSeconds: 900,
                recommendedSeconds: 900,
                effectiveSeconds: 900,
                effectiveReasonCodes: ["configured"],
                nextDueAtMs: baseMs + 180_000,
                nextDueReasonCodes: ["pulse_pending"],
                isDue: true
            ),
            brainstormReview: SupervisorCadenceDimensionExplainability(
                dimension: .brainstormReview,
                configuredSeconds: 1800,
                recommendedSeconds: 1800,
                effectiveSeconds: 1800,
                effectiveReasonCodes: ["configured"],
                nextDueAtMs: baseMs + 180_000,
                nextDueReasonCodes: ["brainstorm_due"],
                isDue: true
            ),
            eventFollowUpCooldownSeconds: 120
        )
    }
}
