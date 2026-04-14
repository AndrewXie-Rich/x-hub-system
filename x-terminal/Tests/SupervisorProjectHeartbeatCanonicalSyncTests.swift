import Foundation
import Testing
@testable import XTerminal

struct SupervisorProjectHeartbeatCanonicalSyncTests {
    @Test
    func itemsExposeHeartbeatGovernanceProjectionAndRecoveryFields() throws {
        let cadence = makeCadence()
        let recovery = HeartbeatRecoveryDecision(
            action: .repairRoute,
            urgency: .urgent,
            reasonCode: "route_health_regressed",
            summary: "Repair the runtime route before the next execution attempt.",
            sourceSignals: ["lane_stalled", "route_flaky"],
            anomalyTypes: [.routeFlaky, .queueStall],
            blockedLaneReasons: [.runtimeError],
            blockedLaneCount: 1,
            stalledLaneCount: 1,
            failedLaneCount: 0,
            recoveringLaneCount: 0,
            requiresUserAction: false
        )
        let snapshot = XTProjectHeartbeatGovernanceDoctorSnapshot(
            projectId: "project-1",
            projectName: "Project One",
            statusDigest: "verify stalled on route recovery",
            currentStateSummary: "Verification is waiting on route repair",
            nextStepSummary: "Repair route and retry smoke suite",
            blockerSummary: "runtime route unhealthy",
            lastHeartbeatAtMs: 1_778_800_120_000,
            latestQualityBand: .weak,
            latestQualityScore: 41,
            weakReasons: ["evidence_weak", "next_action_blurry"],
            openAnomalyTypes: [.routeFlaky, .queueStall],
            projectPhase: .verify,
            executionStatus: .blocked,
            riskTier: .high,
            cadence: cadence,
            digestExplainability: XTHeartbeatDigestExplainability(
                visibility: .shown,
                reasonCodes: ["open_anomalies_present", "recovery_decision_active"],
                whatChangedText: "系统检测到 route 健康下降，验证没有继续推进。",
                whyImportantText: "如果不先修 route，后续验证结论不可信。",
                systemNextStepText: "系统会先修复 route / dispatch 健康，再尝试恢复执行。"
            ),
            recoveryDecision: recovery,
            projectMemoryReadiness: nil
        )

        let record = SupervisorProjectHeartbeatCanonicalSync.record(
            snapshot: snapshot,
            generatedAtMs: 1_778_800_130_000
        )
        let items = SupervisorProjectHeartbeatCanonicalSync.items(record: record)
        let lookup: [String: String] = Dictionary(uniqueKeysWithValues: items.map { ($0.key, $0.value) })

        #expect(lookup["xterminal.project.heartbeat.latest_quality_band"] == "weak")
        #expect(lookup["xterminal.project.heartbeat.open_anomaly_types"]?.contains("route_flaky") == true)
        #expect(lookup["xterminal.project.heartbeat.next_review_kind"] == "review_pulse")
        #expect(lookup["xterminal.project.heartbeat.digest_visibility"] == "shown")
        #expect(lookup["xterminal.project.heartbeat.recovery_action"] == "repair_route")
        #expect(lookup["xterminal.project.heartbeat.recovery_reason_code"] == "route_health_regressed")

        let summary = try #require(lookup["xterminal.project.heartbeat.summary_json"])
        let summaryData = try #require(summary.data(using: String.Encoding.utf8))
        let decoded = try JSONDecoder().decode(SupervisorProjectHeartbeatCanonicalRecord.self, from: summaryData)
        #expect(decoded.projectPhase == HeartbeatProjectPhase.verify)
        #expect(decoded.executionStatus == HeartbeatExecutionStatus.blocked)
        #expect(decoded.nextReviewKind == SupervisorCadenceDimension.reviewPulse)
        #expect(decoded.recoveryDecision?.action == HeartbeatRecoveryAction.repairRoute)
    }

    @Test
    func itemsSkipOptionalRecoveryAndDigestFieldsWhenTheyAreEmpty() {
        let snapshot = XTProjectHeartbeatGovernanceDoctorSnapshot(
            projectId: "project-2",
            projectName: "Project Two",
            statusDigest: "steady build progress",
            currentStateSummary: "Build is active",
            nextStepSummary: "Keep progressing",
            blockerSummary: "",
            lastHeartbeatAtMs: 1_778_800_220_000,
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

        let record = SupervisorProjectHeartbeatCanonicalSync.record(
            snapshot: snapshot,
            generatedAtMs: 1_778_800_230_000
        )
        let keys = Set(SupervisorProjectHeartbeatCanonicalSync.items(record: record).map(\.key))

        #expect(!keys.contains("xterminal.project.heartbeat.recovery_action"))
        #expect(!keys.contains("xterminal.project.heartbeat.recovery_urgency"))
        #expect(keys.contains("xterminal.project.heartbeat.digest_visibility"))
    }

    @Test
    func itemsPreserveProjectMemoryAttentionAsAdvisoryHeartbeatTruth() throws {
        let readiness = XTProjectMemoryAssemblyReadiness(
            ready: false,
            statusLine: "attention:project_memory_usage_missing",
            issues: [
                XTProjectMemoryAssemblyIssue(
                    code: "project_memory_usage_missing",
                    severity: .warning,
                    summary: "尚未捕获 Project AI 的最近一次 memory 装配真相",
                    detail: "Doctor 还没有 recent coder usage 可用于验证本轮 Project AI 实际吃到的 memory objects / planes。"
                )
            ]
        )
        let snapshot = XTProjectHeartbeatGovernanceDoctorSnapshot(
            projectId: "project-3",
            projectName: "Project Three",
            statusDigest: "runtime is stable but project memory truth is still sparse",
            currentStateSummary: "Build remains active",
            nextStepSummary: "Wait for the next coder usage sync",
            blockerSummary: "",
            lastHeartbeatAtMs: 1_778_800_320_000,
            latestQualityBand: .strong,
            latestQualityScore: 86,
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
            projectMemoryReadiness: readiness
        )

        let record = SupervisorProjectHeartbeatCanonicalSync.record(
            snapshot: snapshot,
            generatedAtMs: 1_778_800_330_000
        )
        let lookup = Dictionary(
            uniqueKeysWithValues: SupervisorProjectHeartbeatCanonicalSync.items(record: record).map { ($0.key, $0.value) }
        )

        #expect(lookup["xterminal.project.heartbeat.weak_reasons"]?.contains("project_memory_attention") == true)
        #expect(lookup["xterminal.project.heartbeat.digest_reason_codes"]?.contains("project_memory_attention") == true)

        let summary = try #require(lookup["xterminal.project.heartbeat.summary_json"])
        let summaryData = try #require(summary.data(using: .utf8))
        let decoded = try JSONDecoder().decode(SupervisorProjectHeartbeatCanonicalRecord.self, from: summaryData)
        #expect(decoded.weakReasons.contains("project_memory_attention"))
        #expect(decoded.digestExplainability.reasonCodes.contains("project_memory_attention"))
    }

    private func makeCadence() -> SupervisorCadenceExplainability {
        SupervisorCadenceExplainability(
            progressHeartbeat: SupervisorCadenceDimensionExplainability(
                dimension: .progressHeartbeat,
                configuredSeconds: 300,
                recommendedSeconds: 300,
                effectiveSeconds: 300,
                effectiveReasonCodes: ["configured"],
                nextDueAtMs: 1_778_800_420_000,
                nextDueReasonCodes: ["heartbeat_active"],
                isDue: false
            ),
            reviewPulse: SupervisorCadenceDimensionExplainability(
                dimension: .reviewPulse,
                configuredSeconds: 900,
                recommendedSeconds: 900,
                effectiveSeconds: 900,
                effectiveReasonCodes: ["configured"],
                nextDueAtMs: 1_778_800_300_000,
                nextDueReasonCodes: ["pulse_pending"],
                isDue: false
            ),
            brainstormReview: SupervisorCadenceDimensionExplainability(
                dimension: .brainstormReview,
                configuredSeconds: 1800,
                recommendedSeconds: 1800,
                effectiveSeconds: 1800,
                effectiveReasonCodes: ["configured"],
                nextDueAtMs: 1_778_800_900_000,
                nextDueReasonCodes: ["brainstorm_waiting_progress_window"],
                isDue: false
            ),
            eventFollowUpCooldownSeconds: 120
        )
    }
}
