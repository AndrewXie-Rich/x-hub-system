import Foundation
import Testing
@testable import XTerminal

@MainActor
struct SupervisorEventLoopFollowUpTests {
    actor Recorder {
        private var values: [String] = []

        func append(_ value: String) {
            values.append(value)
        }

        func snapshot() -> [String] {
            values
        }
    }

    @Test
    func queuedFollowUpsDrainInOrderWithoutDroppingEarlierTriggers() async {
        let manager = SupervisorManager.makeForTesting(
            enableSupervisorEventLoopAutoFollowUp: true
        )
        let recorder = Recorder()

        manager.setSupervisorEventLoopResponseOverrideForTesting { userMessage, triggerSource in
            let marker = supervisorEventLoopLineValue("summary", in: userMessage)
            await recorder.append("\(triggerSource):\(marker)")
            try? await Task.sleep(nanoseconds: 20_000_000)
            return "handled \(marker)"
        }

        manager.queueSupervisorEventLoopTurnForTesting(
            userMessage: """
project_ref=Project Alpha
project_id=project-alpha
summary=alpha
""",
            triggerSource: "skill_callback",
            dedupeKey: "event-loop-alpha"
        )
        manager.queueSupervisorEventLoopTurnForTesting(
            userMessage: """
project_ref=Project Beta
project_id=project-beta
summary=beta
""",
            triggerSource: "incident",
            dedupeKey: "event-loop-beta"
        )
        manager.queueSupervisorEventLoopTurnForTesting(
            userMessage: """
project_ref=Project Gamma
project_id=project-gamma
summary=gamma
""",
            triggerSource: "grant_resolution",
            dedupeKey: "event-loop-gamma"
        )

        await manager.waitForSupervisorEventLoopForTesting()

        #expect(await recorder.snapshot() == [
            "skill_callback:alpha",
            "incident:beta",
            "grant_resolution:gamma"
        ])

        let activities = manager.recentSupervisorEventLoopActivitiesForTesting()
            .filter { $0.dedupeKey.hasPrefix("event-loop-") && $0.status != "deduped" }
        #expect(activities.count == 3)
        #expect(activities.map(\.status) == ["completed", "completed", "completed"])
        #expect(activities.map(\.triggerSummary) == ["alpha", "beta", "gamma"])
        #expect(activities.map(\.resultSummary) == ["handled alpha", "handled beta", "handled gamma"])
        #expect(manager.supervisorEventLoopStatusLine == "idle · recent activity")
    }

    @Test
    func duplicateDedupeKeyDoesNotReexecuteButLeavesAuditTrace() async {
        let manager = SupervisorManager.makeForTesting(
            enableSupervisorEventLoopAutoFollowUp: true
        )
        let recorder = Recorder()

        manager.setSupervisorEventLoopResponseOverrideForTesting { userMessage, _ in
            let marker = supervisorEventLoopLineValue("summary", in: userMessage)
            await recorder.append(marker)
            try? await Task.sleep(nanoseconds: 10_000_000)
            return "handled \(marker)"
        }

        manager.queueSupervisorEventLoopTurnForTesting(
            userMessage: """
project_ref=Project Delta
project_id=project-delta
summary=delta
""",
            triggerSource: "heartbeat",
            dedupeKey: "event-loop-delta"
        )
        manager.queueSupervisorEventLoopTurnForTesting(
            userMessage: """
project_ref=Project Delta
project_id=project-delta
summary=delta duplicate
""",
            triggerSource: "heartbeat",
            dedupeKey: "event-loop-delta"
        )

        await manager.waitForSupervisorEventLoopForTesting()

        #expect(await recorder.snapshot() == ["delta"])

        let activities = manager.recentSupervisorEventLoopActivitiesForTesting()
            .filter { $0.dedupeKey == "event-loop-delta" }
        #expect(activities.count == 2)
        #expect(activities.contains(where: { $0.status == "completed" }))
        let deduped = activities.first(where: { $0.status == "deduped" })
        #expect(deduped?.reasonCode == "duplicate_trigger")
        #expect(deduped?.triggerSummary == "delta duplicate")
        #expect(deduped?.resultSummary.isEmpty == true)
    }

    @Test
    func queuedFollowUpCarriesPolicySummaryWhenGovernanceHintsArePresent() async {
        let manager = SupervisorManager.makeForTesting(
            enableSupervisorEventLoopAutoFollowUp: true
        )

        manager.setSupervisorEventLoopResponseOverrideForTesting { _, _ in
            "handled policy-carry"
        }

        manager.queueSupervisorEventLoopTurnForTesting(
            userMessage: """
project_ref=Project Sigma
project_id=project-sigma
summary=sigma follow-up
review_trigger=blocker_detected
event_followup_rhythm=cadence=active · blocker cooldown≈180s
effective_supervisor_tier=s3_strategic_coach
effective_work_order_depth=execution_ready
project_ai_strength_band=capable
""",
            triggerSource: "heartbeat",
            dedupeKey: "event-loop-sigma"
        )

        await manager.waitForSupervisorEventLoopForTesting()

        guard let activity = manager.recentSupervisorEventLoopActivitiesForTesting()
            .last(where: { $0.dedupeKey == "event-loop-sigma" && $0.status == "completed" }) else {
            Issue.record("Expected a completed supervisor event-loop activity for event-loop-sigma.")
            return
        }

        #expect(activity.policySummary.contains("review=Blocker Detected"))
        #expect(activity.policySummary.contains("cadence=active"))
        #expect(activity.policySummary.contains("tier=S3 Strategic Coach"))
        #expect(activity.policySummary.contains("depth=Execution Ready"))
        #expect(activity.policySummary.contains("strength=Capable"))
        #expect(activity.triggerSummary == "blocker_detected · sigma follow-up")
        #expect(activity.resultSummary == "handled policy-carry")
    }

    @Test
    func heartbeatGrantRecoveryFollowUpUsesLocalDirectReplyAndKeepsGrantFocusMetadata() async throws {
        let manager = SupervisorManager.makeForTesting(
            enableSupervisorEventLoopAutoFollowUp: true
        )

        manager.queueSupervisorEventLoopTurnForTesting(
            userMessage: """
project_ref=Project Grant
project_id=project-grant
summary=Project Grant 需要 grant / 授权跟进
recovery_action=request_grant_follow_up
grant_request_id=grant-heartbeat-1
grant_capability=ai.generate.paid
blocked_summary=补齐 grant 后恢复执行
""",
            triggerSource: "heartbeat",
            dedupeKey: "event-loop-heartbeat-grant"
        )

        await manager.waitForSupervisorEventLoopForTesting()

        guard let activity = manager.recentSupervisorEventLoopActivitiesForTesting()
            .last(where: { $0.dedupeKey == "event-loop-heartbeat-grant" && $0.status == "completed" }) else {
            Issue.record("Expected a completed heartbeat recovery grant follow-up activity.")
            return
        }

        #expect(manager.lastSupervisorReplyExecutionMode == "local_direct_reply")
        #expect(activity.grantRequestId == "grant-heartbeat-1")
        #expect(activity.grantCapability == "ai.generate.paid")
        #expect(activity.resultSummary.contains("已为《Project Grant》排队 grant / 授权跟进"))
        #expect(activity.resultSummary.contains("授权单号：grant-heartbeat-1"))
        #expect(activity.resultSummary.contains("系统不会代你审批"))

        let action = try #require(SupervisorEventLoopActionPresentation.action(for: activity))
        let url = try #require(URL(string: action.url))
        let route = try #require(XTDeepLinkParser.parse(url))

        #expect(action.label == "打开授权")
        #expect(
            route == .project(
                XTDeepLinkProjectRoute(
                    projectId: "project-grant",
                    pane: .chat,
                    openTarget: .supervisor,
                    focusTarget: .grant,
                    requestId: nil,
                    grantRequestId: "grant-heartbeat-1",
                    grantCapability: "ai.generate.paid",
                    grantReason: nil,
                    resumeRequested: false
                )
            )
        )
    }

    @Test
    func heartbeatReplayRecoveryFollowUpUsesLocalDirectReply() async {
        let manager = SupervisorManager.makeForTesting(
            enableSupervisorEventLoopAutoFollowUp: true
        )

        manager.queueSupervisorEventLoopTurnForTesting(
            userMessage: """
project_ref=Project Replay
project_id=project-replay
summary=Project Replay 需要重放 follow-up / 续跑链
recovery_action=replay_follow_up
queue_depth=3
blocked_summary=drain 收口后仍需续跑
""",
            triggerSource: "heartbeat",
            dedupeKey: "event-loop-heartbeat-replay"
        )

        await manager.waitForSupervisorEventLoopForTesting()

        guard let activity = manager.recentSupervisorEventLoopActivitiesForTesting()
            .last(where: { $0.dedupeKey == "event-loop-heartbeat-replay" && $0.status == "completed" }) else {
            Issue.record("Expected a completed heartbeat recovery replay follow-up activity.")
            return
        }

        #expect(manager.lastSupervisorReplyExecutionMode == "local_direct_reply")
        #expect(activity.resultSummary.contains("已为《Project Replay》排队 replay follow-up / 续跑链跟进"))
        #expect(activity.resultSummary.contains("当前队列里还有 3 个待处理项"))
        #expect(activity.resultSummary.contains("resume / replan"))
    }

    @Test
    func completedFollowUpPreservesTriggerSummaryAndStoresResultSummarySeparately() async {
        let manager = SupervisorManager.makeForTesting(
            enableSupervisorEventLoopAutoFollowUp: true
        )

        manager.setSupervisorEventLoopResponseOverrideForTesting { _, _ in
            """
handled strategic reroute
queued next review
"""
        }

        manager.queueSupervisorEventLoopTurnForTesting(
            userMessage: """
project_ref=Project Omega
project_id=project-omega
summary=omega queue drift detected
""",
            triggerSource: "incident",
            dedupeKey: "event-loop-omega"
        )

        await manager.waitForSupervisorEventLoopForTesting()

        guard let activity = manager.recentSupervisorEventLoopActivitiesForTesting()
            .last(where: { $0.dedupeKey == "event-loop-omega" && $0.status == "completed" }) else {
            Issue.record("Expected a completed supervisor event-loop activity for event-loop-omega.")
            return
        }

        #expect(activity.triggerSummary == "omega queue drift detected")
        #expect(activity.resultSummary == "handled strategic reroute\nqueued next review")
    }

    @Test
    func officialSkillsChannelFailureQueuesGlobalEventLoopFollowUp() async {
        let manager = SupervisorManager.makeForTesting(
            enableSupervisorEventLoopAutoFollowUp: true
        )
        let recorder = Recorder()
        let appModel = AppModel()

        manager.setSupervisorEventLoopResponseOverrideForTesting { userMessage, triggerSource in
            let status = supervisorEventLoopLineValue("channel_status", in: userMessage)
            let transition = supervisorEventLoopLineValue("transition_kind", in: userMessage)
            await recorder.append("\(triggerSource):\(status):\(transition)")
            return "handled official channel \(status)"
        }
        manager.setAppModel(appModel)

        var snapshot = AXSkillsDoctorSnapshot.empty
        snapshot.officialChannelID = "official-stable"
        snapshot.officialChannelStatus = "failed"
        snapshot.officialChannelUpdatedAtMs = 500
        snapshot.officialChannelSkillCount = 12
        snapshot.officialChannelErrorCode = "index_missing"
        snapshot.officialChannelMaintenanceEnabled = true
        snapshot.officialChannelMaintenanceSourceKind = "env"
        snapshot.officialChannelLastTransitionAtMs = 500
        snapshot.officialChannelLastTransitionKind = "status_changed"
        snapshot.officialChannelLastTransitionSummary = "healthy -> failed via env"
        appModel.skillsCompatibilitySnapshot = snapshot

        await manager.waitForSupervisorEventLoopForTesting()

        let recordedCalls = await recorder.snapshot()
        let officialCalls = recordedCalls.filter { $0.hasPrefix("official_skills_channel:") }
        #expect(officialCalls == ["official_skills_channel:failed:status_changed"])
        #expect(manager.supervisorOfficialSkillsChannelStatusLine == "official failed skills=12 auto=env err=index_missing")
        #expect(manager.supervisorOfficialSkillsChannelTransitionLine == "status_changed: healthy -> failed via env")

        guard let activity = manager.recentSupervisorEventLoopActivitiesForTesting()
            .last(where: {
                $0.triggerSource == "official_skills_channel" && $0.status == "completed"
            }) else {
            Issue.record("Expected a completed official skills channel event-loop activity.")
            return
        }

        #expect(activity.projectName == "Official Skills Channel")
        #expect(activity.triggerSummary.contains("blocker_detected"))
        #expect(activity.triggerSummary.contains("failed"))
        #expect(activity.resultSummary == "handled official channel failed")

        let memory = await manager.buildSupervisorLocalMemoryV1ForTesting("检查官方技能通道")
        #expect(memory.contains("official_skills_channel: status=official failed skills=12 auto=env err=index_missing"))
        #expect(memory.contains("latest_transition=status_changed: healthy -> failed via env"))
    }

    @Test
    func officialSkillsChannelHealthyRepairStaysPassiveButWritesIntoMemory() async {
        let manager = SupervisorManager.makeForTesting(
            enableSupervisorEventLoopAutoFollowUp: true
        )
        let recorder = Recorder()
        let appModel = AppModel()

        manager.setSupervisorEventLoopResponseOverrideForTesting { _, _ in
            await recorder.append("called")
            return "unexpected"
        }
        manager.setAppModel(appModel)

        var snapshot = AXSkillsDoctorSnapshot.empty
        snapshot.officialChannelID = "official-stable"
        snapshot.officialChannelStatus = "healthy"
        snapshot.officialChannelUpdatedAtMs = 900
        snapshot.officialChannelSkillCount = 24
        snapshot.officialChannelMaintenanceEnabled = true
        snapshot.officialChannelMaintenanceSourceKind = "persisted"
        snapshot.officialChannelLastTransitionAtMs = 900
        snapshot.officialChannelLastTransitionKind = "current_snapshot_repaired"
        snapshot.officialChannelLastTransitionSummary = "current snapshot restored via persisted"
        appModel.skillsCompatibilitySnapshot = snapshot

        await manager.waitForSupervisorEventLoopForTesting()

        let passiveCalls = await recorder.snapshot()
        #expect(passiveCalls.isEmpty)
        #expect(manager.recentSupervisorEventLoopActivitiesForTesting().contains(where: {
            $0.triggerSource == "official_skills_channel"
        }) == false)
        #expect(manager.supervisorOfficialSkillsChannelStatusLine == "official healthy skills=24 auto=persisted")
        #expect(manager.supervisorOfficialSkillsChannelTransitionLine == "current_snapshot_repaired: current snapshot restored via persisted")

        let memory = await manager.buildSupervisorLocalMemoryV1ForTesting("检查官方技能通道")
        #expect(memory.contains("official_skills_channel: status=official healthy skills=24 auto=persisted"))
        #expect(memory.contains("latest_transition=current_snapshot_repaired: current snapshot restored via persisted"))
    }

    @Test
    func missingScopedHiddenProjectRecoveryQueuesGenericDiagnosticsFollowUpWithoutLeakingIdentity() async {
        let manager = SupervisorManager.makeForTesting(
            enableSupervisorEventLoopAutoFollowUp: true
        )
        let recorder = Recorder()
        let hiddenProjectId = "hidden-project-alpha"

        manager.setSupervisorEventLoopResponseOverrideForTesting { userMessage, triggerSource in
            await recorder.append("\(triggerSource)|\(userMessage)")
            return "open diagnostics"
        }

        manager.setSupervisorMemoryAssemblySnapshotForTesting(
            hiddenProjectRecoveryMissingSnapshot(projectId: hiddenProjectId)
        )

        await manager.waitForSupervisorEventLoopForTesting()

        let recordedCalls = await recorder.snapshot()
        #expect(recordedCalls.count == 1)
        #expect(recordedCalls[0].contains("incident|"))
        #expect(recordedCalls[0].contains("reason_code=memory_scoped_hidden_project_recovery_missing"))
        #expect(recordedCalls[0].contains("next_safe_action=open_diagnostics"))
        #expect(recordedCalls[0].contains(hiddenProjectId) == false)

        guard let activity = manager.recentSupervisorEventLoopActivitiesForTesting()
            .last(where: {
                $0.dedupeKey.hasPrefix("memory_assembly:hidden_project_scoped_recovery:")
                    && $0.status == "completed"
            }) else {
            Issue.record("Expected a completed memory assembly follow-up activity.")
            return
        }

        #expect(activity.projectId.isEmpty)
        #expect(activity.projectName == "Memory Assembly")
        #expect(activity.triggerSummary.contains("显式 hidden project 聚焦时"))
        #expect(activity.triggerSummary.contains(hiddenProjectId) == false)
        #expect(activity.resultSummary == "open diagnostics")
    }

    @Test
    func unchangedHiddenProjectRecoveryIssueDoesNotQueueDuplicateFollowUp() async {
        let manager = SupervisorManager.makeForTesting(
            enableSupervisorEventLoopAutoFollowUp: true
        )
        let recorder = Recorder()
        let snapshot = hiddenProjectRecoveryMissingSnapshot(projectId: "hidden-project-beta")

        manager.setSupervisorEventLoopResponseOverrideForTesting { userMessage, triggerSource in
            await recorder.append("\(triggerSource):\(supervisorEventLoopLineValue("reason_code", in: userMessage))")
            return "open diagnostics"
        }

        manager.setSupervisorMemoryAssemblySnapshotForTesting(snapshot)
        await manager.waitForSupervisorEventLoopForTesting()

        manager.setSupervisorMemoryAssemblySnapshotForTesting(snapshot)
        await manager.waitForSupervisorEventLoopForTesting()

        #expect(await recorder.snapshot() == [
            "incident:memory_scoped_hidden_project_recovery_missing"
        ])

        let activities = manager.recentSupervisorEventLoopActivitiesForTesting()
            .filter { $0.dedupeKey.hasPrefix("memory_assembly:hidden_project_scoped_recovery:") }
        #expect(activities.count == 1)
        #expect(activities.first?.status == "completed")
    }

    @Test
    func hiddenProjectRecoveryIssueReschedulesAfterIssueClears() async {
        let manager = SupervisorManager.makeForTesting(
            enableSupervisorEventLoopAutoFollowUp: true
        )
        let recorder = Recorder()
        let snapshot = hiddenProjectRecoveryMissingSnapshot(projectId: "hidden-project-gamma")

        manager.setSupervisorEventLoopResponseOverrideForTesting { userMessage, triggerSource in
            await recorder.append("\(triggerSource):\(supervisorEventLoopLineValue("reason_code", in: userMessage))")
            return "open diagnostics"
        }

        manager.setSupervisorMemoryAssemblySnapshotForTesting(snapshot)
        await manager.waitForSupervisorEventLoopForTesting()

        manager.setSupervisorMemoryAssemblySnapshotForTesting(nil)
        manager.setSupervisorMemoryAssemblySnapshotForTesting(snapshot)
        await manager.waitForSupervisorEventLoopForTesting()

        let recorded = await recorder.snapshot()
        #expect(recorded.count == 2)
        #expect(recorded.allSatisfy { $0 == "incident:memory_scoped_hidden_project_recovery_missing" })

        let activities = manager.recentSupervisorEventLoopActivitiesForTesting()
            .filter {
                $0.dedupeKey.hasPrefix("memory_assembly:hidden_project_scoped_recovery:")
                    && $0.status == "completed"
            }
        #expect(activities.count == 2)
    }
}

private func supervisorEventLoopLineValue(
    _ key: String,
    in text: String
) -> String {
    let needle = key + "="
    for rawLine in text.split(whereSeparator: \.isNewline) {
        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard line.hasPrefix(needle) else { continue }
        return String(line.dropFirst(needle.count)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    return ""
}

private func hiddenProjectRecoveryMissingSnapshot(
    projectId: String
) -> SupervisorMemoryAssemblySnapshot {
    SupervisorMemoryAssemblySnapshot(
        source: "xt_cache",
        resolutionSource: "local_only",
        updatedAt: 1_775_000_100,
        reviewLevelHint: SupervisorReviewLevel.r2Strategic.rawValue,
        requestedProfile: XTMemoryServingProfile.m3DeepDive.rawValue,
        profileFloor: XTMemoryServingProfile.m2PlanReview.rawValue,
        resolvedProfile: XTMemoryServingProfile.m3DeepDive.rawValue,
        attemptedProfiles: [XTMemoryServingProfile.m3DeepDive.rawValue],
        progressiveUpgradeCount: 0,
        focusedProjectId: projectId,
        rawWindowProfile: XTSupervisorRecentRawContextProfile.defaultProfile.rawValue,
        rawWindowFloorPairs: XTSupervisorRecentRawContextProfile.hardFloorPairs,
        rawWindowCeilingPairs: XTSupervisorRecentRawContextProfile.defaultProfile.windowCeilingPairs,
        rawWindowSelectedPairs: XTSupervisorRecentRawContextProfile.hardFloorPairs,
        eligibleMessages: 12,
        lowSignalDroppedMessages: 1,
        rawWindowSource: "xt_cache",
        rollingDigestPresent: true,
        continuityFloorSatisfied: true,
        truncationAfterFloor: false,
        continuityTraceLines: ["continuity ok"],
        lowSignalDropSampleLines: ["noise sample"],
        selectedSections: ["l1_canonical", "l2_observations", "l3_working_set", "dialogue_window"],
        omittedSections: ["focused_project_anchor_pack"],
        contextRefsSelected: 2,
        contextRefsOmitted: 0,
        evidenceItemsSelected: 1,
        evidenceItemsOmitted: 0,
        truncatedLayers: [],
        compressionPolicy: "balanced",
        scopedPromptRecoveryMode: "explicit_hidden_project_focus",
        scopedPromptRecoverySections: []
    )
}
