import Foundation
import Testing
@testable import XTerminal

struct HeartbeatGovernanceDoctorSnapshotTests {

    @Test
    func buildHumanizesQueuedGovernanceReviewForDigestWithoutMutatingRecoveryTruth() throws {
        let root = try makeProjectRoot("governed-review-digest")
        defer { try? FileManager.default.removeItem(at: root) }

        let nowMs: Int64 = 1_773_900_000_000
        let snapshot = try governedReviewSnapshot(root: root, nowMs: nowMs)

        #expect(snapshot.recoveryDecision?.action == .queueStrategicReview)
        #expect(snapshot.recoveryDecision?.summary == "Queue a deeper governance review before resuming autonomous execution.")
        #expect(snapshot.digestExplainability.whatChangedText == "项目已接近完成，但完成声明证据偏弱。")
        #expect(snapshot.digestExplainability.systemNextStepText.contains("救援复盘"))
        #expect(snapshot.digestExplainability.systemNextStepText.contains("safe point"))
        #expect(snapshot.digestExplainability.systemNextStepText.contains("事件触发"))
        #expect(!snapshot.digestExplainability.systemNextStepText.contains("Queue a deeper governance review"))
        #expect(
            snapshot.detailLines().contains(where: {
                $0.contains("heartbeat_recovery_summary=Queue a deeper governance review before resuming autonomous execution.")
            })
        )
    }

    @Test
    func unifiedDoctorProjectionCarriesLocalizedDigestNextStepFromGovernedReviewSnapshot() throws {
        let root = try makeProjectRoot("governed-review-projection")
        defer { try? FileManager.default.removeItem(at: root) }

        let snapshot = try governedReviewSnapshot(
            root: root,
            nowMs: 1_773_920_000_000
        )
        let projection = XTUnifiedDoctorHeartbeatGovernanceProjection(snapshot: snapshot)

        #expect(projection.digestSystemNextStepText.contains("救援复盘"))
        #expect(projection.digestSystemNextStepText.contains("safe point"))
        #expect(!projection.digestSystemNextStepText.contains("Queue a deeper governance review"))
        #expect(projection.recoveryDecision?.summary == "Queue a deeper governance review before resuming autonomous execution.")
    }

    @Test
    func buildCarriesProjectMemoryReadinessIntoHeartbeatSnapshotAndProjection() throws {
        let root = try makeProjectRoot("heartbeat-memory-readiness")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()

        let projectId = AXProjectRegistryStore.projectId(forRoot: root)
        let nowMs: Int64 = 1_773_930_000_000
        let config = AXProjectConfig.default(forProjectRoot: root)
        let readiness = XTProjectMemoryAssemblyReadiness(
            ready: false,
            statusLine: "attention:project_memory_usage_missing",
            issues: [
                XTProjectMemoryAssemblyIssue(
                    code: "project_memory_usage_missing",
                    severity: .warning,
                    summary: "尚未捕获 Project AI 的最近一次 memory 装配真相",
                    detail: "Doctor 当前只能看到配置基线，还没有 recent coder usage 来证明 Project AI 最近一轮真正吃到了哪些 memory objects / planes。"
                )
            ]
        )

        let snapshot = XTProjectHeartbeatGovernanceDoctorBuilder.build(
            project: projectEntry(
                projectId: projectId,
                root: root,
                displayName: "Memory",
                statusDigest: "active",
                currentStateSummary: "Execution is active",
                nextStepSummary: "Continue coding",
                blockerSummary: nil
            ),
            context: ctx,
            config: config,
            projectMemoryReadiness: readiness,
            laneSnapshot: nil,
            now: Date(timeIntervalSince1970: Double(nowMs) / 1000.0)
        )
        let projection = XTUnifiedDoctorHeartbeatGovernanceProjection(snapshot: snapshot)

        #expect(snapshot.projectMemoryReadiness == readiness)
        #expect(snapshot.weakReasons.contains("project_memory_attention"))
        #expect(snapshot.detailLines().contains("heartbeat_project_memory_ready=false"))
        #expect(snapshot.detailLines().contains("heartbeat_project_memory_issue_codes=project_memory_usage_missing"))
        #expect(snapshot.detailLines().contains("heartbeat_quality_weak_reasons=project_memory_attention"))
        #expect(snapshot.digestExplainability.reasonCodes.contains("project_memory_attention"))
        #expect(snapshot.digestExplainability.whyImportantText.contains("memory assembly truth"))
        #expect(snapshot.digestExplainability.systemNextStepText == "Continue coding")
        #expect(projection.projectMemoryReady == false)
        #expect(projection.projectMemoryIssueCodes == ["project_memory_usage_missing"])
        #expect(projection.digestReasonCodes.contains("project_memory_attention"))
        #expect(projection.projectMemoryTopIssueSummary?.contains("最近一次 memory 装配真相") == true)
    }

    @Test
    func buildMakesGovernedReviewDigestMemoryTruthAwareWhenLatestCoderUsageExists() throws {
        let root = try makeProjectRoot("heartbeat-memory-truth-aware")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()

        let projectId = AXProjectRegistryStore.projectId(forRoot: root)
        let nowMs: Int64 = 1_773_935_000_000
        let config = AXProjectConfig.default(forProjectRoot: root).settingProjectGovernance(
            executionTier: .a3DeliverAuto,
            supervisorInterventionTier: .s3StrategicCoach,
            reviewPolicyMode: .hybrid,
            progressHeartbeatSeconds: 180,
            reviewPulseSeconds: 600,
            brainstormReviewSeconds: 1_200,
            eventDrivenReviewEnabled: true,
            eventReviewTriggers: [.preDoneSummary, .blockerDetected, .manualRequest]
        )
        let schedule = SupervisorReviewScheduleState(
            schemaVersion: SupervisorReviewScheduleState.currentSchemaVersion,
            projectId: projectId,
            updatedAtMs: nowMs,
            lastHeartbeatAtMs: nowMs,
            lastObservedProgressAtMs: nowMs - 300_000,
            lastPulseReviewAtMs: 0,
            lastBrainstormReviewAtMs: 0,
            lastTriggerReviewAtMs: [:],
            nextHeartbeatDueAtMs: nowMs + 180_000,
            nextPulseReviewDueAtMs: nowMs + 600_000,
            nextBrainstormReviewDueAtMs: nowMs + 1_200_000,
            latestQualitySnapshot: qualitySnapshot(
                overallBand: .weak,
                overallScore: 38,
                computedAtMs: nowMs
            ),
            openAnomalies: [
                anomaly(
                    id: "anomaly-weak-done-memory",
                    projectId: projectId,
                    type: .weakDoneClaim,
                    severity: .high,
                    detectedAtMs: nowMs,
                    escalation: .rescueReview
                )
            ],
            lastHeartbeatFingerprint: "done candidate with memory truth",
            lastHeartbeatRepeatCount: 0,
            latestProjectPhase: .release,
            latestExecutionStatus: .doneCandidate,
            latestRiskTier: .high
        )
        try writeSchedule(schedule, for: ctx)

        let snapshot = XTProjectHeartbeatGovernanceDoctorBuilder.build(
            project: projectEntry(
                projectId: projectId,
                root: root,
                displayName: "Gamma",
                statusDigest: "Done candidate waiting for review",
                currentStateSummary: "Validation is wrapping up for release",
                nextStepSummary: nil,
                blockerSummary: nil
            ),
            context: ctx,
            config: config,
            projectMemoryContext: XTHeartbeatProjectMemoryContextSnapshot(
                diagnosticsSource: "latest_coder_usage",
                projectMemoryPolicy: nil,
                policyMemoryAssemblyResolution: memoryResolution(
                    effectiveDepth: "deep"
                ),
                memoryAssemblyResolution: memoryResolution(
                    effectiveDepth: "deep"
                ),
                heartbeatDigestWorkingSetPresent: true,
                heartbeatDigestVisibility: "shown",
                heartbeatDigestReasonCodes: ["review_candidate_active"]
            ),
            laneSnapshot: nil,
            now: Date(timeIntervalSince1970: Double(nowMs) / 1000.0)
        )

        #expect(snapshot.digestExplainability.reasonCodes.contains("project_memory_truth_latest_coder_usage"))
        #expect(snapshot.digestExplainability.reasonCodes.contains("project_memory_digest_in_project_ai"))
        #expect(snapshot.digestExplainability.whyImportantText.contains("latest coder usage"))
        #expect(snapshot.digestExplainability.systemNextStepText.contains("safe point"))
        #expect(snapshot.digestExplainability.systemNextStepText.contains("不再额外重复灌入同一份 heartbeat digest"))
    }

    @Test
    func buildHumanizesGrantFollowUpRecoveryForDigestWithoutMutatingRecoveryTruth() throws {
        let root = try makeProjectRoot("hold-for-user-digest")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()

        let projectId = AXProjectRegistryStore.projectId(forRoot: root)
        let nowMs: Int64 = 1_773_910_000_000
        let config = AXProjectConfig.default(forProjectRoot: root).settingProjectGovernance(
            executionTier: .a2RepoAuto,
            supervisorInterventionTier: .s2PeriodicReview,
            reviewPolicyMode: .periodic,
            progressHeartbeatSeconds: 300,
            reviewPulseSeconds: 900,
            brainstormReviewSeconds: 1_800,
            eventDrivenReviewEnabled: true,
            eventReviewTriggers: [.blockerDetected, .manualRequest]
        )
        let schedule = SupervisorReviewScheduleState(
            schemaVersion: SupervisorReviewScheduleState.currentSchemaVersion,
            projectId: projectId,
            updatedAtMs: nowMs,
            lastHeartbeatAtMs: nowMs,
            lastObservedProgressAtMs: nowMs - 60_000,
            lastPulseReviewAtMs: 0,
            lastBrainstormReviewAtMs: 0,
            lastTriggerReviewAtMs: [:],
            nextHeartbeatDueAtMs: nowMs + 300_000,
            nextPulseReviewDueAtMs: nowMs + 900_000,
            nextBrainstormReviewDueAtMs: nowMs + 1_800_000,
            latestQualitySnapshot: qualitySnapshot(
                overallBand: .usable,
                overallScore: 71,
                computedAtMs: nowMs
            ),
            openAnomalies: [],
            lastHeartbeatFingerprint: "grant pending wait",
            lastHeartbeatRepeatCount: 0,
            latestProjectPhase: .build,
            latestExecutionStatus: .blocked,
            latestRiskTier: .medium
        )
        try writeSchedule(schedule, for: ctx)

        let laneState = LaneRuntimeState(
            laneID: "lane-grant",
            taskId: UUID(),
            projectId: nil,
            agentProfile: "coder",
            status: .blocked,
            blockedReason: .grantPending,
            nextActionRecommendation: "notify_user"
        )
        let laneSnapshot = SupervisorLaneHealthSnapshot(
            generatedAtMs: nowMs,
            summary: LaneHealthSummary(
                total: 1,
                running: 0,
                blocked: 1,
                stalled: 0,
                failed: 0,
                waiting: 0,
                recovering: 0,
                completed: 0
            ),
            lanes: [SupervisorLaneHealthLaneState(state: laneState)]
        )

        let snapshot = XTProjectHeartbeatGovernanceDoctorBuilder.build(
            project: projectEntry(
                projectId: projectId,
                root: root,
                displayName: "Beta",
                statusDigest: "Waiting for repo write grant",
                currentStateSummary: "Automation is paused on grant review",
                nextStepSummary: nil,
                blockerSummary: nil
            ),
            context: ctx,
            config: config,
            laneSnapshot: laneSnapshot,
            now: Date(timeIntervalSince1970: Double(nowMs) / 1000.0)
        )

        #expect(snapshot.recoveryDecision?.action == .requestGrantFollowUp)
        #expect(snapshot.recoveryDecision?.summary == "Request the required grant follow-up before resuming autonomous execution.")
        #expect(snapshot.digestExplainability.systemNextStepText.contains("grant 跟进"))
        #expect(snapshot.digestExplainability.systemNextStepText.contains("恢复执行"))
        #expect(!snapshot.digestExplainability.systemNextStepText.contains("Request the required grant follow-up"))
        #expect(
            snapshot.detailLines().contains(where: {
                $0.contains("heartbeat_recovery_summary=Request the required grant follow-up before resuming autonomous execution.")
            })
        )
    }

    @Test
    func buildHumanizesReplayFollowUpRecoveryForDigestWithoutMutatingRecoveryTruth() throws {
        let root = try makeProjectRoot("replay-follow-up-digest")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()

        let projectId = AXProjectRegistryStore.projectId(forRoot: root)
        let nowMs: Int64 = 1_773_915_000_000
        let config = AXProjectConfig.default(forProjectRoot: root).settingProjectGovernance(
            executionTier: .a2RepoAuto,
            supervisorInterventionTier: .s2PeriodicReview,
            reviewPolicyMode: .hybrid,
            progressHeartbeatSeconds: 300,
            reviewPulseSeconds: 900,
            brainstormReviewSeconds: 1_800,
            eventDrivenReviewEnabled: true,
            eventReviewTriggers: [.blockerDetected, .manualRequest]
        )
        let schedule = SupervisorReviewScheduleState(
            schemaVersion: SupervisorReviewScheduleState.currentSchemaVersion,
            projectId: projectId,
            updatedAtMs: nowMs,
            lastHeartbeatAtMs: nowMs,
            lastObservedProgressAtMs: nowMs - 120_000,
            lastPulseReviewAtMs: 0,
            lastBrainstormReviewAtMs: 0,
            lastTriggerReviewAtMs: [:],
            nextHeartbeatDueAtMs: nowMs + 300_000,
            nextPulseReviewDueAtMs: nowMs + 900_000,
            nextBrainstormReviewDueAtMs: nowMs + 1_800_000,
            latestQualitySnapshot: qualitySnapshot(
                overallBand: .weak,
                overallScore: 54,
                computedAtMs: nowMs
            ),
            openAnomalies: [
                anomaly(
                    id: "anomaly-queue-stall",
                    projectId: projectId,
                    type: .queueStall,
                    severity: .concern,
                    detectedAtMs: nowMs,
                    escalation: .strategicReview
                )
            ],
            lastHeartbeatFingerprint: "queue stalled waiting for drain replay",
            lastHeartbeatRepeatCount: 1,
            latestProjectPhase: .verify,
            latestExecutionStatus: .blocked,
            latestRiskTier: .medium
        )
        try writeSchedule(schedule, for: ctx)

        let laneState = LaneRuntimeState(
            laneID: "lane-replay",
            taskId: UUID(),
            projectId: nil,
            agentProfile: "coder",
            status: .blocked,
            blockedReason: .restartDrain,
            nextActionRecommendation: "wait_drain_recover"
        )
        let laneSnapshot = SupervisorLaneHealthSnapshot(
            generatedAtMs: nowMs,
            summary: LaneHealthSummary(
                total: 1,
                running: 0,
                blocked: 1,
                stalled: 0,
                failed: 0,
                waiting: 0,
                recovering: 0,
                completed: 0
            ),
            lanes: [SupervisorLaneHealthLaneState(state: laneState)]
        )

        let snapshot = XTProjectHeartbeatGovernanceDoctorBuilder.build(
            project: projectEntry(
                projectId: projectId,
                root: root,
                displayName: "Replay",
                statusDigest: "queue stalled",
                currentStateSummary: "Execution queue is stalled during drain recovery",
                nextStepSummary: nil,
                blockerSummary: "Drain replay pending"
            ),
            context: ctx,
            config: config,
            laneSnapshot: laneSnapshot,
            now: Date(timeIntervalSince1970: Double(nowMs) / 1000.0)
        )

        #expect(snapshot.recoveryDecision?.action == .replayFollowUp)
        #expect(snapshot.recoveryDecision?.summary == "Replay the pending follow-up or recovery chain after the current drain finishes.")
        #expect(snapshot.digestExplainability.systemNextStepText.contains("重放挂起的 follow-up"))
        #expect(snapshot.digestExplainability.systemNextStepText.contains("drain"))
        #expect(!snapshot.digestExplainability.systemNextStepText.contains("Replay the pending follow-up"))
        #expect(
            snapshot.detailLines().contains(where: {
                $0.contains("heartbeat_recovery_summary=Replay the pending follow-up or recovery chain after the current drain finishes.")
            })
        )
    }

    private func makeProjectRoot(_ name: String) throws -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("heartbeat-governance-doctor-tests", isDirectory: true)
            .appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private func governedReviewSnapshot(
        root: URL,
        nowMs: Int64
    ) throws -> XTProjectHeartbeatGovernanceDoctorSnapshot {
        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()

        let projectId = AXProjectRegistryStore.projectId(forRoot: root)
        let config = AXProjectConfig.default(forProjectRoot: root).settingProjectGovernance(
            executionTier: .a3DeliverAuto,
            supervisorInterventionTier: .s3StrategicCoach,
            reviewPolicyMode: .hybrid,
            progressHeartbeatSeconds: 180,
            reviewPulseSeconds: 600,
            brainstormReviewSeconds: 1_200,
            eventDrivenReviewEnabled: true,
            eventReviewTriggers: [.preDoneSummary, .blockerDetected, .manualRequest]
        )
        let schedule = SupervisorReviewScheduleState(
            schemaVersion: SupervisorReviewScheduleState.currentSchemaVersion,
            projectId: projectId,
            updatedAtMs: nowMs,
            lastHeartbeatAtMs: nowMs,
            lastObservedProgressAtMs: nowMs - 300_000,
            lastPulseReviewAtMs: 0,
            lastBrainstormReviewAtMs: 0,
            lastTriggerReviewAtMs: [:],
            nextHeartbeatDueAtMs: nowMs + 180_000,
            nextPulseReviewDueAtMs: nowMs + 600_000,
            nextBrainstormReviewDueAtMs: nowMs + 1_200_000,
            latestQualitySnapshot: qualitySnapshot(
                overallBand: .weak,
                overallScore: 38,
                computedAtMs: nowMs
            ),
            openAnomalies: [
                anomaly(
                    id: "anomaly-weak-done",
                    projectId: projectId,
                    type: .weakDoneClaim,
                    severity: .high,
                    detectedAtMs: nowMs,
                    escalation: .rescueReview
                )
            ],
            lastHeartbeatFingerprint: "done candidate waiting for review",
            lastHeartbeatRepeatCount: 0,
            latestProjectPhase: .release,
            latestExecutionStatus: .doneCandidate,
            latestRiskTier: .high
        )
        try writeSchedule(schedule, for: ctx)

        return XTProjectHeartbeatGovernanceDoctorBuilder.build(
            project: projectEntry(
                projectId: projectId,
                root: root,
                displayName: "Alpha",
                statusDigest: "Done candidate waiting for review",
                currentStateSummary: "Validation is wrapping up for release",
                nextStepSummary: nil,
                blockerSummary: nil
            ),
            context: ctx,
            config: config,
            laneSnapshot: nil,
            now: Date(timeIntervalSince1970: Double(nowMs) / 1000.0)
        )
    }

    private func writeSchedule(
        _ schedule: SupervisorReviewScheduleState,
        for ctx: AXProjectContext
    ) throws {
        let data = try JSONEncoder().encode(schedule)
        try data.write(
            to: ctx.xterminalDir.appendingPathComponent("supervisor_review_schedule.json"),
            options: .atomic
        )
    }

    private func projectEntry(
        projectId: String,
        root: URL,
        displayName: String,
        statusDigest: String?,
        currentStateSummary: String?,
        nextStepSummary: String?,
        blockerSummary: String?
    ) -> AXProjectEntry {
        AXProjectEntry(
            projectId: projectId,
            rootPath: AXProjectRegistryStore.normalizedRootPath(root),
            displayName: displayName,
            lastOpenedAt: 0,
            manualOrderIndex: nil,
            pinned: false,
            statusDigest: statusDigest,
            currentStateSummary: currentStateSummary,
            nextStepSummary: nextStepSummary,
            blockerSummary: blockerSummary,
            lastSummaryAt: nil,
            lastEventAt: nil
        )
    }

    private func qualitySnapshot(
        overallBand: HeartbeatQualityBand,
        overallScore: Int,
        computedAtMs: Int64
    ) -> HeartbeatQualitySnapshot {
        HeartbeatQualitySnapshot(
            overallScore: overallScore,
            overallBand: overallBand,
            freshnessScore: overallScore,
            deltaSignificanceScore: overallScore,
            evidenceStrengthScore: overallScore,
            blockerClarityScore: overallScore,
            nextActionSpecificityScore: overallScore,
            executionVitalityScore: overallScore,
            completionConfidenceScore: overallScore,
            weakReasons: [],
            computedAtMs: computedAtMs
        )
    }

    private func memoryResolution(
        effectiveDepth: String
    ) -> XTMemoryAssemblyResolution {
        XTMemoryAssemblyResolution(
            role: .projectAI,
            trigger: "heartbeat_review",
            configuredDepth: effectiveDepth,
            recommendedDepth: effectiveDepth,
            effectiveDepth: effectiveDepth,
            ceilingFromTier: effectiveDepth,
            ceilingHit: false,
            selectedSlots: ["workflow"],
            selectedPlanes: ["project"],
            selectedServingObjects: ["focused_project_anchor_pack", "heartbeat_projection"],
            excludedBlocks: [],
            budgetSummary: "\(effectiveDepth) profile"
        )
    }

    private func anomaly(
        id: String,
        projectId: String,
        type: HeartbeatAnomalyType,
        severity: HeartbeatAnomalySeverity,
        detectedAtMs: Int64,
        escalation: HeartbeatAnomalyEscalation
    ) -> HeartbeatAnomalyNote {
        HeartbeatAnomalyNote(
            anomalyId: id,
            projectId: projectId,
            anomalyType: type,
            severity: severity,
            confidence: 0.95,
            reason: type.rawValue,
            evidenceRefs: [],
            detectedAtMs: detectedAtMs,
            recommendedEscalation: escalation
        )
    }
}
