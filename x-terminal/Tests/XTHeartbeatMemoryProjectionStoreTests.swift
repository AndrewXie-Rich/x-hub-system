import Foundation
import Testing
@testable import XTerminal

struct XTHeartbeatMemoryProjectionStoreTests {
    @Test
    func stableHeartbeatStaysOutOfWorkingSetAndLongtermWhileStillProjectingCanonicalState() throws {
        let fixture = ToolExecutorProjectFixture(name: "heartbeat-memory-projection-stable")
        defer { fixture.cleanup() }

        let ctx = AXProjectContext(root: fixture.root)
        try ctx.ensureDirs()

        let schedule = SupervisorReviewScheduleState(
            schemaVersion: SupervisorReviewScheduleState.currentSchemaVersion,
            projectId: "project-stable",
            updatedAtMs: 1_778_810_120_000,
            lastHeartbeatAtMs: 1_778_810_120_000,
            lastObservedProgressAtMs: 1_778_810_100_000,
            lastPulseReviewAtMs: 0,
            lastBrainstormReviewAtMs: 0,
            lastTriggerReviewAtMs: [:],
            nextHeartbeatDueAtMs: 1_778_810_420_000,
            nextPulseReviewDueAtMs: 1_778_811_020_000,
            nextBrainstormReviewDueAtMs: 1_778_811_920_000,
            latestQualitySnapshot: nil,
            openAnomalies: [],
            lastHeartbeatFingerprint: "hb-stable",
            lastHeartbeatRepeatCount: 0,
            latestProjectPhase: .build,
            latestExecutionStatus: .active,
            latestRiskTier: .low
        )
        let snapshot = XTProjectHeartbeatGovernanceDoctorSnapshot(
            projectId: "project-stable",
            projectName: "Stable Project",
            statusDigest: "build continues with fresh evidence",
            currentStateSummary: "Build is active",
            nextStepSummary: "Continue current implementation slice",
            blockerSummary: "",
            lastHeartbeatAtMs: schedule.lastHeartbeatAtMs,
            latestQualityBand: .strong,
            latestQualityScore: 91,
            weakReasons: [],
            openAnomalyTypes: [],
            projectPhase: .build,
            executionStatus: .active,
            riskTier: .low,
            cadence: makeCadence(),
            digestExplainability: XTHeartbeatDigestExplainability(
                visibility: .suppressed,
                reasonCodes: ["stable_runtime_update_suppressed"],
                whatChangedText: "系统继续按当前节奏推进。",
                whyImportantText: "",
                systemNextStepText: ""
            ),
            recoveryDecision: nil,
            projectMemoryReadiness: nil
        )
        let canonical = SupervisorProjectHeartbeatCanonicalSync.record(
            snapshot: snapshot,
            generatedAtMs: schedule.updatedAtMs
        )

        let artifact = try #require(
            XTHeartbeatMemoryProjectionStore.record(
                ctx: ctx,
                snapshot: snapshot,
                schedule: schedule,
                canonicalRecord: canonical,
                generatedAtMs: schedule.updatedAtMs
            )
        )

        #expect(FileManager.default.fileExists(atPath: ctx.heartbeatMemoryProjectionURL.path))
        #expect(artifact.workingSetProjection.eligible == false)
        #expect(artifact.workingSetProjection.reasonCodes.contains("digest_suppressed"))
        #expect(artifact.longtermProjection.promotionEligible == false)
        #expect(artifact.longtermProjection.reasonCodes == ["routine_heartbeat_not_promoted"])
        #expect(artifact.canonicalProjection.latestQualityBand == .strong)
        #expect(artifact.observationFacts.contains { $0.contains("heartbeat_quality band=strong") })

        let latestData = try Data(contentsOf: ctx.heartbeatMemoryProjectionURL)
        let decoded = try JSONDecoder().decode(XTHeartbeatMemoryProjectionArtifact.self, from: latestData)
        #expect(decoded.projectId == "project-stable")
        #expect(decoded.refs.contains("hub://project/project-stable/canonical/xterminal.project.heartbeat.summary_json"))

        let rawLog = try String(contentsOf: ctx.rawLogURL, encoding: .utf8)
        #expect(rawLog.contains("\"type\":\"heartbeat_memory_projection\""))
        #expect(rawLog.contains("\"longterm_promotion_eligible\":false"))
    }

    @Test
    func recurringAnomalousHeartbeatPromotesWorkingSetAndLongtermPatternCandidates() throws {
        let fixture = ToolExecutorProjectFixture(name: "heartbeat-memory-projection-recurring")
        defer { fixture.cleanup() }

        let ctx = AXProjectContext(root: fixture.root)
        try ctx.ensureDirs()

        let schedule = SupervisorReviewScheduleState(
            schemaVersion: SupervisorReviewScheduleState.currentSchemaVersion,
            projectId: "project-recurring",
            updatedAtMs: 1_778_820_120_000,
            lastHeartbeatAtMs: 1_778_820_120_000,
            lastObservedProgressAtMs: 1_778_819_000_000,
            lastPulseReviewAtMs: 0,
            lastBrainstormReviewAtMs: 0,
            lastTriggerReviewAtMs: [:],
            nextHeartbeatDueAtMs: 1_778_820_420_000,
            nextPulseReviewDueAtMs: 1_778_820_300_000,
            nextBrainstormReviewDueAtMs: 1_778_820_300_000,
            latestQualitySnapshot: nil,
            openAnomalies: [],
            lastHeartbeatFingerprint: "hb-recurring",
            lastHeartbeatRepeatCount: 3,
            latestProjectPhase: .verify,
            latestExecutionStatus: .blocked,
            latestRiskTier: .high
        )
        let recovery = HeartbeatRecoveryDecision(
            action: .repairRoute,
            urgency: .urgent,
            reasonCode: "route_health_regressed",
            summary: "Repair route before retrying verification.",
            sourceSignals: ["route_flaky", "queue_stall"],
            anomalyTypes: [.routeFlaky, .queueStall],
            blockedLaneReasons: [.runtimeError],
            blockedLaneCount: 1,
            stalledLaneCount: 1,
            failedLaneCount: 0,
            recoveringLaneCount: 0,
            requiresUserAction: false
        )
        let snapshot = XTProjectHeartbeatGovernanceDoctorSnapshot(
            projectId: "project-recurring",
            projectName: "Recurring Project",
            statusDigest: "verification stalled with repeated route issues",
            currentStateSummary: "Verify is blocked on route instability",
            nextStepSummary: "Repair route then retry smoke suite",
            blockerSummary: "route keeps degrading during verify",
            lastHeartbeatAtMs: schedule.lastHeartbeatAtMs,
            latestQualityBand: .hollow,
            latestQualityScore: 18,
            weakReasons: ["evidence_weak", "hollow_progress"],
            openAnomalyTypes: [.routeFlaky, .queueStall],
            projectPhase: .verify,
            executionStatus: .blocked,
            riskTier: .high,
            cadence: makeCadence(),
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
            generatedAtMs: schedule.updatedAtMs
        )

        let artifact = try #require(
            XTHeartbeatMemoryProjectionStore.record(
                ctx: ctx,
                snapshot: snapshot,
                schedule: schedule,
                canonicalRecord: canonical,
                generatedAtMs: schedule.updatedAtMs
            )
        )

        #expect(artifact.workingSetProjection.eligible == true)
        #expect(artifact.workingSetProjection.digest?.visibility == .shown)
        #expect(artifact.longtermProjection.promotionEligible == true)
        #expect(artifact.longtermProjection.patternCodes.contains("recurring_hollow_progress"))
        #expect(artifact.longtermProjection.patternCodes.contains("recurring_route_flaky"))
        #expect(artifact.longtermProjection.patternCodes.contains("verify_phase_recurring_anomalies"))
    }

    @Test
    func sparseHeartbeatCandidateDoesNotOverwriteExistingMeaningfulProjection() throws {
        let fixture = ToolExecutorProjectFixture(name: "heartbeat-memory-projection-preserve-rich")
        defer { fixture.cleanup() }

        let ctx = AXProjectContext(root: fixture.root)
        try ctx.ensureDirs()

        let richSchedule = SupervisorReviewScheduleState(
            schemaVersion: SupervisorReviewScheduleState.currentSchemaVersion,
            projectId: "project-preserve",
            updatedAtMs: 1_778_840_120_000,
            lastHeartbeatAtMs: 1_778_840_120_000,
            lastObservedProgressAtMs: 1_778_840_000_000,
            lastPulseReviewAtMs: 0,
            lastBrainstormReviewAtMs: 0,
            lastTriggerReviewAtMs: [:],
            nextHeartbeatDueAtMs: 1_778_840_420_000,
            nextPulseReviewDueAtMs: 1_778_841_020_000,
            nextBrainstormReviewDueAtMs: 1_778_841_920_000,
            latestQualitySnapshot: nil,
            openAnomalies: [],
            lastHeartbeatFingerprint: "hb-preserve-rich",
            lastHeartbeatRepeatCount: 2,
            latestProjectPhase: .verify,
            latestExecutionStatus: .blocked,
            latestRiskTier: .high
        )
        let richSnapshot = XTProjectHeartbeatGovernanceDoctorSnapshot(
            projectId: "project-preserve",
            projectName: "Preserve Project",
            statusDigest: "verification stalled with repeated route issues",
            currentStateSummary: "Verify is blocked on route instability",
            nextStepSummary: "Repair route then retry smoke suite",
            blockerSummary: "route keeps degrading during verify",
            lastHeartbeatAtMs: richSchedule.lastHeartbeatAtMs,
            latestQualityBand: .hollow,
            latestQualityScore: 18,
            weakReasons: ["evidence_weak", "hollow_progress"],
            openAnomalyTypes: [.routeFlaky, .queueStall],
            projectPhase: .verify,
            executionStatus: .blocked,
            riskTier: .high,
            cadence: makeCadence(),
            digestExplainability: XTHeartbeatDigestExplainability(
                visibility: .shown,
                reasonCodes: ["open_anomalies_present", "recovery_decision_active"],
                whatChangedText: "验证连续多次停在 route 健康问题。",
                whyImportantText: "这已经不是单次抖动，继续重试只会重复空转。",
                systemNextStepText: "系统会先修复 route / dispatch 健康，再尝试恢复执行。"
            ),
            recoveryDecision: nil,
            projectMemoryReadiness: nil
        )
        let richCanonical = SupervisorProjectHeartbeatCanonicalSync.record(
            snapshot: richSnapshot,
            generatedAtMs: richSchedule.updatedAtMs
        )
        let richArtifact = try #require(
            XTHeartbeatMemoryProjectionStore.record(
                ctx: ctx,
                snapshot: richSnapshot,
                schedule: richSchedule,
                canonicalRecord: richCanonical,
                generatedAtMs: richSchedule.updatedAtMs
            )
        )

        let sparseSchedule = SupervisorReviewScheduleState(
            schemaVersion: SupervisorReviewScheduleState.currentSchemaVersion,
            projectId: "project-preserve",
            updatedAtMs: 1_778_840_180_000,
            lastHeartbeatAtMs: 1_778_840_180_000,
            lastObservedProgressAtMs: 1_778_840_000_000,
            lastPulseReviewAtMs: 0,
            lastBrainstormReviewAtMs: 0,
            lastTriggerReviewAtMs: [:],
            nextHeartbeatDueAtMs: 1_778_840_480_000,
            nextPulseReviewDueAtMs: 1_778_841_080_000,
            nextBrainstormReviewDueAtMs: 1_778_841_980_000,
            latestQualitySnapshot: nil,
            openAnomalies: [],
            lastHeartbeatFingerprint: "hb-preserve-sparse",
            lastHeartbeatRepeatCount: 0,
            latestProjectPhase: .build,
            latestExecutionStatus: .active,
            latestRiskTier: .low
        )
        let sparseSnapshot = XTProjectHeartbeatGovernanceDoctorSnapshot(
            projectId: "project-preserve",
            projectName: "Preserve Project",
            statusDigest: "",
            currentStateSummary: "   ",
            nextStepSummary: "",
            blockerSummary: "\n",
            lastHeartbeatAtMs: sparseSchedule.lastHeartbeatAtMs,
            latestQualityBand: .strong,
            latestQualityScore: 92,
            weakReasons: [],
            openAnomalyTypes: [],
            projectPhase: .build,
            executionStatus: .active,
            riskTier: .low,
            cadence: makeCadence(),
            digestExplainability: XTHeartbeatDigestExplainability(
                visibility: .suppressed,
                reasonCodes: ["stable_runtime_update_suppressed"],
                whatChangedText: "系统继续按当前节奏推进。",
                whyImportantText: "",
                systemNextStepText: ""
            ),
            recoveryDecision: nil,
            projectMemoryReadiness: nil
        )
        let sparseCanonical = SupervisorProjectHeartbeatCanonicalSync.record(
            snapshot: sparseSnapshot,
            generatedAtMs: sparseSchedule.updatedAtMs
        )
        let preservedArtifact = try #require(
            XTHeartbeatMemoryProjectionStore.record(
                ctx: ctx,
                snapshot: sparseSnapshot,
                schedule: sparseSchedule,
                canonicalRecord: sparseCanonical,
                generatedAtMs: sparseSchedule.updatedAtMs
            )
        )

        let latestData = try Data(contentsOf: ctx.heartbeatMemoryProjectionURL)
        let decoded = try JSONDecoder().decode(XTHeartbeatMemoryProjectionArtifact.self, from: latestData)

        #expect(sparseCanonical.statusDigest.isEmpty)
        #expect(sparseCanonical.currentStateSummary.isEmpty)
        #expect(preservedArtifact == richArtifact)
        #expect(decoded == richArtifact)
        #expect(decoded.canonicalProjection.statusDigest == richArtifact.canonicalProjection.statusDigest)
        #expect(decoded.canonicalProjection.currentStateSummary == richArtifact.canonicalProjection.currentStateSummary)
        #expect(decoded.rawPayload.statusDigest == richArtifact.rawPayload.statusDigest)
        #expect(decoded.canonicalProjection.auditRef == richArtifact.canonicalProjection.auditRef)
        #expect(decoded.createdAtMs == richArtifact.createdAtMs)
    }

    @Test
    func projectionCarriesProjectMemoryAdvisoryIntoRawPayloadAndObservationFacts() throws {
        let fixture = ToolExecutorProjectFixture(name: "heartbeat-memory-projection-project-memory")
        defer { fixture.cleanup() }

        let ctx = AXProjectContext(root: fixture.root)
        try ctx.ensureDirs()

        let schedule = SupervisorReviewScheduleState(
            schemaVersion: SupervisorReviewScheduleState.currentSchemaVersion,
            projectId: "project-memory",
            updatedAtMs: 1_778_830_120_000,
            lastHeartbeatAtMs: 1_778_830_120_000,
            lastObservedProgressAtMs: 1_778_830_000_000,
            lastPulseReviewAtMs: 0,
            lastBrainstormReviewAtMs: 0,
            lastTriggerReviewAtMs: [:],
            nextHeartbeatDueAtMs: 1_778_830_420_000,
            nextPulseReviewDueAtMs: 1_778_830_900_000,
            nextBrainstormReviewDueAtMs: 1_778_831_800_000,
            latestQualitySnapshot: nil,
            openAnomalies: [],
            lastHeartbeatFingerprint: "hb-project-memory",
            lastHeartbeatRepeatCount: 1,
            latestProjectPhase: .build,
            latestExecutionStatus: .active,
            latestRiskTier: .low
        )
        let projectMemoryReadiness = XTProjectMemoryAssemblyReadiness(
            ready: false,
            statusLine: "attention:project_memory_usage_missing",
            issues: [
                XTProjectMemoryAssemblyIssue(
                    code: "project_memory_usage_missing",
                    severity: .warning,
                    summary: "尚未捕获 Project AI 的最近一次 memory 装配真相",
                    detail: "Doctor 当前只有配置基线，还没有 recent coder usage 来证明本轮 Project AI 实际拿到了哪些 memory objects / planes。"
                )
            ]
        )
        let projectMemoryContext = XTHeartbeatProjectMemoryContextSnapshot(
            diagnosticsSource: "latest_coder_usage",
            projectMemoryPolicy: XTProjectMemoryPolicySnapshot(
                configuredRecentProjectDialogueProfile: .standard12Pairs,
                configuredProjectContextDepth: .balanced,
                recommendedRecentProjectDialogueProfile: .deep20Pairs,
                recommendedProjectContextDepth: .deep,
                effectiveRecentProjectDialogueProfile: .deep20Pairs,
                effectiveProjectContextDepth: .deep,
                aTierMemoryCeiling: .m3DeepDive,
                auditRef: "audit://policy/project-memory"
            ),
            policyMemoryAssemblyResolution: XTMemoryAssemblyResolution(
                role: .projectAI,
                dominantMode: "project_execution",
                trigger: "config_policy",
                configuredDepth: "balanced",
                recommendedDepth: "deep",
                effectiveDepth: "deep",
                ceilingFromTier: XTMemoryServingProfile.m3DeepDive.rawValue,
                ceilingHit: false,
                selectedSlots: ["recent_project_dialogue", "project_anchor_pack"],
                selectedPlanes: ["project_execution", "workflow"],
                selectedServingObjects: ["recent_project_dialogue", "project_anchor_pack"],
                excludedBlocks: ["personal_memory"],
                budgetSummary: "project_memory_budget=ok",
                auditRef: "audit://policy-resolution/project-memory"
            ),
            memoryAssemblyResolution: XTMemoryAssemblyResolution(
                role: .projectAI,
                dominantMode: "project_execution",
                trigger: "review_guidance_follow_up",
                configuredDepth: "balanced",
                recommendedDepth: "deep",
                effectiveDepth: "deep",
                ceilingFromTier: XTMemoryServingProfile.m3DeepDive.rawValue,
                ceilingHit: false,
                selectedSlots: ["recent_project_dialogue", "project_anchor_pack", "workflow"],
                selectedPlanes: ["project_execution", "workflow", "evidence"],
                selectedServingObjects: ["recent_project_dialogue", "project_anchor_pack", "workflow_summary"],
                excludedBlocks: ["personal_memory"],
                budgetSummary: "project_memory_budget=fit",
                auditRef: "audit://resolution/project-memory"
            ),
            heartbeatDigestWorkingSetPresent: true,
            heartbeatDigestVisibility: "shown",
            heartbeatDigestReasonCodes: ["project_memory_attention", "recovery_decision_active"]
        )
        let snapshot = XTProjectHeartbeatGovernanceDoctorSnapshot(
            projectId: "project-memory",
            projectName: "Memory Project",
            statusDigest: "runtime stable but coder memory truth is still sparse",
            currentStateSummary: "Build is active",
            nextStepSummary: "Wait for the next coder usage sync",
            blockerSummary: "",
            lastHeartbeatAtMs: schedule.lastHeartbeatAtMs,
            latestQualityBand: .strong,
            latestQualityScore: 88,
            weakReasons: ["project_memory_attention"],
            openAnomalyTypes: [],
            projectPhase: .build,
            executionStatus: .active,
            riskTier: .low,
            cadence: makeCadence(),
            digestExplainability: XTHeartbeatDigestExplainability(
                visibility: .shown,
                reasonCodes: ["project_memory_attention"],
                whatChangedText: "Project AI memory truth still needs attention.",
                whyImportantText: "Doctor 还不能确认最近一轮 coder 真正吃到了哪些 project memory。",
                systemNextStepText: "系统会继续等待下一轮 recent coder usage 补齐 machine-readable truth。"
            ),
            recoveryDecision: nil,
            projectMemoryReadiness: projectMemoryReadiness,
            projectMemoryContext: projectMemoryContext
        )
        let canonical = SupervisorProjectHeartbeatCanonicalSync.record(
            snapshot: snapshot,
            generatedAtMs: schedule.updatedAtMs
        )

        let artifact = try #require(
            XTHeartbeatMemoryProjectionStore.record(
                ctx: ctx,
                snapshot: snapshot,
                schedule: schedule,
                canonicalRecord: canonical,
                generatedAtMs: schedule.updatedAtMs
            )
        )

        #expect(artifact.rawPayload.projectMemoryReadiness == projectMemoryReadiness)
        #expect(artifact.rawPayload.projectMemoryContext == projectMemoryContext)
        #expect(artifact.workingSetProjection.reasonCodes.contains("project_memory_attention"))
        #expect(artifact.observationFacts.contains("heartbeat_project_memory_source=latest_coder_usage"))
        #expect(artifact.observationFacts.contains(where: { $0.contains("heartbeat_project_memory_policy_context_depth=") && $0.contains("effective:deep") }))
        #expect(artifact.observationFacts.contains("heartbeat_project_memory_actual_resolution trigger=review_guidance_follow_up effective_depth=deep ceiling=m3_deep_dive ceiling_hit=false"))
        #expect(artifact.observationFacts.contains(where: { $0.contains("heartbeat_project_memory_actual_selection") && $0.contains("workflow_summary") }))
        #expect(artifact.observationFacts.contains("heartbeat_project_memory_heartbeat_digest_present=true"))
        #expect(artifact.observationFacts.contains("heartbeat_project_memory_heartbeat_digest_visibility=shown"))
        #expect(artifact.observationFacts.contains("heartbeat_project_memory_heartbeat_digest_reason_codes=project_memory_attention,recovery_decision_active"))
        #expect(artifact.observationFacts.contains("heartbeat_project_memory_ready=false"))
        #expect(artifact.observationFacts.contains("heartbeat_project_memory_issue_codes=project_memory_usage_missing"))
        #expect(artifact.observationFacts.contains(where: { $0.contains("heartbeat_project_memory_top_issue_summary=") && $0.contains("Project AI") }))

        let latestData = try Data(contentsOf: ctx.heartbeatMemoryProjectionURL)
        let decoded = try JSONDecoder().decode(XTHeartbeatMemoryProjectionArtifact.self, from: latestData)
        #expect(decoded.rawPayload.projectMemoryReadiness?.issueCodes == ["project_memory_usage_missing"])
        #expect(decoded.rawPayload.projectMemoryContext?.diagnosticsSource == "latest_coder_usage")
        #expect(decoded.rawPayload.projectMemoryContext?.memoryAssemblyResolution?.selectedPlanes == ["project_execution", "workflow", "evidence"])
        #expect(decoded.rawPayload.projectMemoryContext?.heartbeatDigestReasonCodes == ["project_memory_attention", "recovery_decision_active"])

        let rawLog = try String(contentsOf: ctx.rawLogURL, encoding: .utf8)
        #expect(rawLog.contains("\"project_memory_ready\":false"))
        #expect(rawLog.contains("\"project_memory_issue_codes\":[\"project_memory_usage_missing\"]"))
        #expect(rawLog.contains("\"project_memory_diagnostics_source\":\"latest_coder_usage\""))
        #expect(rawLog.contains("\"project_memory_effective_depth\":\"deep\""))
        #expect(rawLog.contains("\"project_memory_resolution_trigger\":\"review_guidance_follow_up\""))
        #expect(rawLog.contains("\"project_memory_selected_serving_objects\":[\"recent_project_dialogue\",\"project_anchor_pack\",\"workflow_summary\"]"))
        #expect(rawLog.contains("\"project_memory_heartbeat_digest_present\":true"))
    }

    private func makeCadence() -> SupervisorCadenceExplainability {
        SupervisorCadenceExplainability(
            progressHeartbeat: SupervisorCadenceDimensionExplainability(
                dimension: .progressHeartbeat,
                configuredSeconds: 300,
                recommendedSeconds: 300,
                effectiveSeconds: 300,
                effectiveReasonCodes: ["configured"],
                nextDueAtMs: 1_778_820_420_000,
                nextDueReasonCodes: ["heartbeat_active"],
                isDue: false
            ),
            reviewPulse: SupervisorCadenceDimensionExplainability(
                dimension: .reviewPulse,
                configuredSeconds: 900,
                recommendedSeconds: 900,
                effectiveSeconds: 900,
                effectiveReasonCodes: ["configured"],
                nextDueAtMs: 1_778_820_300_000,
                nextDueReasonCodes: ["pulse_pending"],
                isDue: true
            ),
            brainstormReview: SupervisorCadenceDimensionExplainability(
                dimension: .brainstormReview,
                configuredSeconds: 1800,
                recommendedSeconds: 1800,
                effectiveSeconds: 1800,
                effectiveReasonCodes: ["configured"],
                nextDueAtMs: 1_778_820_300_000,
                nextDueReasonCodes: ["brainstorm_due"],
                isDue: true
            ),
            eventFollowUpCooldownSeconds: 120
        )
    }
}
