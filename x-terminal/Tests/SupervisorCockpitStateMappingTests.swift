import Foundation
import Testing
@testable import XTerminal

struct SupervisorCockpitStateMappingTests {
    @Test
    func grantRequiredMapsToExplainableBlockerAndValidatedScope() {
        let presentation = SupervisorCockpitPresentation.map(
            input: SupervisorCockpitPresentationInput(
                isProcessing: false,
                pendingGrantCount: 1,
                hasFreshPendingGrantSnapshot: true,
                doctorStatusLine: "Doctor 已通过（0 个告警）",
                doctorSuggestionCount: 0,
                releaseBlockedByDoctorWithoutReport: 0,
                laneSummary: .empty,
                abnormalLaneStatus: nil,
                abnormalLaneRecommendation: nil,
                xtReadyStatus: "awaiting_grant",
                xtReadyStrictE2EReady: true,
                xtReadyIssueCount: 0,
                xtReadyReportPath: "build/xt_ready_gate_e2e_report.json"
            )
        )

        #expect(presentation.intakeStatus.state == .grantRequired)
        #expect(presentation.blockerStatus.headline.contains("grant_required"))
        #expect(presentation.releaseFreezeStatus.state == .releaseFrozen)
        #expect(presentation.actions.first?.id == "submit_intake")
        #expect(presentation.consumedFrozenFields.contains("xt.one_shot_run_state.v1.state"))
    }

    @Test
    func blockedAndReadyStatesPreservePlannerExplainAndNextAction() {
        let blocked = SupervisorCockpitPresentation.map(
            input: SupervisorCockpitPresentationInput(
                isProcessing: false,
                pendingGrantCount: 0,
                hasFreshPendingGrantSnapshot: true,
                doctorStatusLine: "Doctor 已通过（0 个告警）",
                doctorSuggestionCount: 0,
                releaseBlockedByDoctorWithoutReport: 0,
                laneSummary: LaneHealthSummary(
                    total: 3,
                    running: 0,
                    blocked: 1,
                    stalled: 1,
                    failed: 0,
                    waiting: 1,
                    recovering: 0,
                    completed: 0
                ),
                abnormalLaneStatus: "blocked",
                abnormalLaneRecommendation: "先处理上游授权，再按 next action 续推。",
                xtReadyStatus: "blocked_waiting_upstream",
                xtReadyStrictE2EReady: true,
                xtReadyIssueCount: 0,
                xtReadyReportPath: "build/xt_ready_gate_e2e_report.json"
            )
        )
        #expect(blocked.intakeStatus.state == .blockedWaitingUpstream)
        #expect(blocked.blockerStatus.userAction.contains("续推"))
        #expect(blocked.plannerExplain.contains("blocked_waiting_upstream"))

        let ready = SupervisorCockpitPresentation.map(
            input: SupervisorCockpitPresentationInput(
                isProcessing: false,
                pendingGrantCount: 0,
                hasFreshPendingGrantSnapshot: true,
                doctorStatusLine: "Doctor 已通过（0 个告警）",
                doctorSuggestionCount: 0,
                releaseBlockedByDoctorWithoutReport: 0,
                laneSummary: .empty,
                abnormalLaneStatus: nil,
                abnormalLaneRecommendation: nil,
                xtReadyStatus: "ready",
                xtReadyStrictE2EReady: true,
                xtReadyIssueCount: 0,
                xtReadyReportPath: "build/xt_ready_gate_e2e_report.json"
            )
        )
        #expect(ready.intakeStatus.state == .ready)
        #expect(ready.blockerStatus.headline == "Top blocker: none")
        #expect(ready.plannerExplain.contains("当前处于 ready"))
    }


    @Test
    func runtimeContractsMapPermissionDenyScopeFreezeAndReplay() {
        let presentation = SupervisorCockpitPresentation.map(
            input: SupervisorCockpitPresentationInput(
                isProcessing: false,
                pendingGrantCount: 0,
                hasFreshPendingGrantSnapshot: true,
                doctorStatusLine: "Doctor 已通过（0 个告警）",
                doctorSuggestionCount: 0,
                releaseBlockedByDoctorWithoutReport: 0,
                laneSummary: .empty,
                abnormalLaneStatus: nil,
                abnormalLaneRecommendation: nil,
                xtReadyStatus: "ready",
                xtReadyStrictE2EReady: true,
                xtReadyIssueCount: 0,
                xtReadyReportPath: "build/xt_ready_gate_e2e_report.json",
                autoConfirmPolicy: "safe_plus_low_risk",
                autoLaunchPolicy: "mainline_only",
                grantGateMode: "fail_closed",
                humanTouchpointCount: 3,
                directedUnblockBatonCount: 1,
                nextDirectedResumeAction: "continue_current_task_only",
                nextDirectedResumeLane: "XT-W3-26-F",
                scopeFreezeDecision: "no_go",
                scopeFreezeValidatedScope: ["XT-W3-23", "XT-W3-24", "XT-W3-25"],
                allowedPublicStatementCount: 3,
                scopeFreezeBlockedExpansionItems: ["future_ui_productization"],
                scopeFreezeNextActions: ["drop_scope_expansion"],
                deniedLaunchCount: 1,
                topLaunchDenyCode: "permission_denied",
                replayPass: false,
                replayScenarioCount: 4,
                replayFailClosedScenarioCount: 4,
                replayEvidenceRefs: ["build/reports/xt_w3_26_h_replay_regression_evidence.v1.json"]
            )
        )

        #expect(presentation.intakeStatus.state == .permissionDenied)
        #expect(presentation.blockerStatus.headline.contains("permission_denied"))
        #expect(presentation.releaseFreezeStatus.state == .blockedWaitingUpstream)
        #expect(presentation.plannerExplain.contains("auto_launch=mainline_only"))
        #expect(presentation.plannerExplain.contains("freeze=no_go"))
        #expect(presentation.consumedFrozenFields.contains("xt.unblock_baton.v1.next_action"))
        #expect(presentation.consumedFrozenFields.contains("xt.one_shot_replay_regression.v1.scenarios"))
    }

    @Test
    func runtimeCaptureWritesXTW327DEvidenceWhenRequested() throws {
        guard let captureDir = ProcessInfo.processInfo.environment["XT_W3_27_CAPTURE_DIR"], !captureDir.isEmpty else {
            return
        }

        let base = URL(fileURLWithPath: captureDir)
        let input = SupervisorCockpitPresentationInput(
            isProcessing: true,
            pendingGrantCount: 0,
            hasFreshPendingGrantSnapshot: true,
            doctorStatusLine: "Doctor 已通过（0 个告警）",
            doctorSuggestionCount: 0,
            releaseBlockedByDoctorWithoutReport: 0,
            laneSummary: LaneHealthSummary(
                total: 2,
                running: 1,
                blocked: 0,
                stalled: 0,
                failed: 0,
                waiting: 0,
                recovering: 1,
                completed: 0
            ),
            abnormalLaneStatus: nil,
            abnormalLaneRecommendation: nil,
            xtReadyStatus: "running",
            xtReadyStrictE2EReady: true,
            xtReadyIssueCount: 0,
            xtReadyReportPath: "build/xt_ready_gate_e2e_report.json"
        )
        let evidence = XTW327DSupervisorCockpitEvidence(
            claim: "XT-W3-27-D",
            input: input,
            presentation: SupervisorCockpitPresentation.map(input: input)
        )

        try writeJSON(evidence, to: base.appendingPathComponent("xt_w3_27_d_supervisor_cockpit_evidence.v1.json"))
        #expect(FileManager.default.fileExists(atPath: base.appendingPathComponent("xt_w3_27_d_supervisor_cockpit_evidence.v1.json").path))
    }

    private struct XTW327DSupervisorCockpitEvidence: Codable, Equatable {
        let claim: String
        let input: SupervisorCockpitPresentationInput
        let presentation: SupervisorCockpitPresentation
    }

    private func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        try data.write(to: url)
    }
}
