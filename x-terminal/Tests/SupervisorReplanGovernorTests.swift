import Foundation
import Testing
@testable import XTerminal

struct SupervisorReplanGovernorTests {

    @Test
    func p1CRCannotPreemptP0ReleaseBlocker() {
        let governor = ReplanGovernor()
        let decision = governor.decide(
            proposal: releaseBlockerProposal(),
            board: releaseBlockerBoard(),
            now: Date(timeIntervalSince1970: 1_730_500_000)
        )

        #expect(decision.verdict == .queued)
        #expect(decision.reasonCode == "release_blocker_protected")
        #expect(decision.releaseBlockerProtectionApplied)
        #expect(decision.protectedTaskID == "XT-REL-01")
        #expect(decision.queueAfterTaskID == "XT-REL-01")
    }

    @Test
    func freezeWindowQueuesCRByPolicy() {
        let governor = ReplanGovernor()
        let decision = governor.decide(
            proposal: freezeWindowProposal(),
            board: freezeWindowBoard(),
            now: Date(timeIntervalSince1970: 1_730_500_010)
        )

        #expect(decision.verdict == .queued)
        #expect(decision.reasonCode == "freeze_window_queue_enforced")
        #expect(decision.freezeWindowApplied)
        #expect(decision.queueAfterTaskID == "XT-FREEZE-01")
    }

    @Test
    func acceptedCRPassesWhenNoReleaseRiskExists() {
        let governor = ReplanGovernor()
        let decision = governor.decide(
            proposal: acceptedProposal(),
            board: acceptedBoard(),
            now: Date(timeIntervalSince1970: 1_730_500_020)
        )

        #expect(decision.verdict == .accepted)
        #expect(decision.reasonCode == "accepted_replan")
        #expect(decision.releaseBlockerProtectionApplied == false)
        #expect(decision.freezeWindowApplied == false)
        #expect(decision.replayableDecisionChain)
    }

    @Test
    func highImpactCRWithoutReplayChainIsRejected() {
        let governor = ReplanGovernor()
        let decision = governor.decide(
            proposal: rejectedProposal(),
            board: acceptedBoard(),
            now: Date(timeIntervalSince1970: 1_730_500_030)
        )

        #expect(decision.verdict == .rejected)
        #expect(decision.reasonCode == "replay_chain_incomplete")
        #expect(decision.replayableDecisionChain == false)
    }

    @Test
    func replanAuditTrailReplaysConsistently() {
        let arbiter = CRArbiter()
        let decisions = [
            arbiter.evaluate(proposals: [acceptedProposal()], board: acceptedBoard(), now: Date(timeIntervalSince1970: 1_730_500_040)).first,
            arbiter.evaluate(proposals: [releaseBlockerProposal()], board: releaseBlockerBoard(), now: Date(timeIntervalSince1970: 1_730_500_041)).first,
            arbiter.evaluate(proposals: [freezeWindowProposal()], board: freezeWindowBoard(), now: Date(timeIntervalSince1970: 1_730_500_042)).first,
            arbiter.evaluate(proposals: [rejectedProposal()], board: acceptedBoard(), now: Date(timeIntervalSince1970: 1_730_500_043)).first,
        ].compactMap { $0 }

        let replay = arbiter.replay(auditTrail: decisions.map(\.auditRecord))

        #expect(replay.pass)
        #expect(replay.replayedCount == decisions.count)
        #expect(replay.mismatchedAuditIDs.isEmpty)
        #expect(Set(replay.replayedFingerprints) == Set(decisions.map(\.decisionFingerprint)))
    }

    @Test
    func replanCaptureEmitsMachineReadableSamples() throws {
        let accepted = ReplanGovernor().decide(
            proposal: acceptedProposal(),
            board: acceptedBoard(),
            now: Date(timeIntervalSince1970: 1_730_500_050)
        )
        let releaseBlocked = ReplanGovernor().decide(
            proposal: releaseBlockerProposal(),
            board: releaseBlockerBoard(),
            now: Date(timeIntervalSince1970: 1_730_500_051)
        )
        let freezeQueued = ReplanGovernor().decide(
            proposal: freezeWindowProposal(),
            board: freezeWindowBoard(),
            now: Date(timeIntervalSince1970: 1_730_500_052)
        )
        let rejected = ReplanGovernor().decide(
            proposal: rejectedProposal(),
            board: acceptedBoard(),
            now: Date(timeIntervalSince1970: 1_730_500_053)
        )

        let samples = [accepted, releaseBlocked, freezeQueued, rejected]
        let arbiter = CRArbiter()
        let replay = arbiter.replay(auditTrail: samples.map(\.auditRecord))

        var latencySamplesMS: [Double] = []
        latencySamplesMS.reserveCapacity(1600)
        for iteration in 0..<400 {
            let tick = TimeInterval(1_730_500_100 + iteration)
            latencySamplesMS.append(ReplanGovernor().decide(proposal: acceptedProposal(), board: acceptedBoard(), now: Date(timeIntervalSince1970: tick)).latencyMS)
            latencySamplesMS.append(ReplanGovernor().decide(proposal: releaseBlockerProposal(), board: releaseBlockerBoard(), now: Date(timeIntervalSince1970: tick + 0.001)).latencyMS)
            latencySamplesMS.append(ReplanGovernor().decide(proposal: freezeWindowProposal(), board: freezeWindowBoard(), now: Date(timeIntervalSince1970: tick + 0.002)).latencyMS)
            latencySamplesMS.append(ReplanGovernor().decide(proposal: rejectedProposal(), board: acceptedBoard(), now: Date(timeIntervalSince1970: tick + 0.003)).latencyMS)
        }

        let p95 = percentile95(latencySamplesMS)
        #expect(p95 <= 3000)
        #expect(samples.contains(where: { $0.verdict == .accepted }))
        #expect(samples.filter { $0.verdict == .queued }.count == 2)
        #expect(samples.contains(where: { $0.verdict == .rejected }))
        #expect(releaseBlocked.releaseBlockerProtectionApplied)
        #expect(freezeQueued.freezeWindowApplied)
        #expect(replay.pass)

        if ProcessInfo.processInfo.environment["XT_W3_20_CAPTURE"] == "1" {
            let payload = ReplanRuntimeCapture(
                schemaVersion: "xterminal.xt_w3_20.replan_runtime_capture.v1",
                sampleWindow: "xt_w3_20_g1_g3_g5_first_probe_v1",
                replanLatencyP95MS: p95,
                decisionSamples: samples.map(ReplanRuntimeDecisionSample.init),
                acceptedCount: samples.filter { $0.verdict == .accepted }.count,
                queuedCount: samples.filter { $0.verdict == .queued }.count,
                rejectedCount: samples.filter { $0.verdict == .rejected }.count,
                releaseBlockerProtectionResult: ReplanRuntimeReleaseBlockerProtection(
                    pass: releaseBlocked.verdict == .queued && releaseBlocked.protectedTaskID == "XT-REL-01",
                    protectedTaskID: releaseBlocked.protectedTaskID,
                    blockedPreemptionCRID: releaseBlocked.crID,
                    queueAfterTaskID: releaseBlocked.queueAfterTaskID
                ),
                freezeWindowQueueSemantics: ReplanRuntimeFreezeQueueSemantics(
                    pass: freezeQueued.verdict == .queued && freezeQueued.queueAfterTaskID == "XT-FREEZE-01",
                    queuedCRID: freezeQueued.crID,
                    queueAfterTaskID: freezeQueued.queueAfterTaskID,
                    policyReasonCode: freezeQueued.reasonCode
                ),
                replayabilityCheck: replay,
                sourceRefs: [
                    "x-terminal/Sources/Supervisor/ReplanGovernor.swift",
                    "x-terminal/Tests/SupervisorReplanGovernorTests.swift"
                ]
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let json = try String(decoding: encoder.encode(payload), as: UTF8.self)
            print("XT_W3_20_CAPTURE_JSON=\(json)")
        }
    }

    private func acceptedBoard() -> ReplanBoardSnapshot {
        ReplanBoardSnapshot(
            boardSnapshotID: "board-accepted-v1",
            activeTaskID: "XT-W3-20",
            freezeWindowActive: false,
            tasks: [
                ReplanTaskSnapshot(
                    taskID: "XT-W3-20",
                    priority: .p1,
                    isReleaseBlocker: false,
                    freezeWindowActive: false,
                    ownerLane: "XT-L2"
                ),
                ReplanTaskSnapshot(
                    taskID: "XT-W3-19-S1",
                    priority: .p1,
                    isReleaseBlocker: false,
                    freezeWindowActive: false,
                    ownerLane: "XT-L2"
                )
            ]
        )
    }

    private func releaseBlockerBoard() -> ReplanBoardSnapshot {
        ReplanBoardSnapshot(
            boardSnapshotID: "board-release-blocker-v1",
            activeTaskID: "XT-REL-01",
            freezeWindowActive: false,
            tasks: [
                ReplanTaskSnapshot(
                    taskID: "XT-REL-01",
                    priority: .p0ReleaseBlocker,
                    isReleaseBlocker: true,
                    freezeWindowActive: false,
                    ownerLane: "XT-L2"
                ),
                ReplanTaskSnapshot(
                    taskID: "XT-W3-20",
                    priority: .p1,
                    isReleaseBlocker: false,
                    freezeWindowActive: false,
                    ownerLane: "XT-L2"
                )
            ]
        )
    }

    private func freezeWindowBoard() -> ReplanBoardSnapshot {
        ReplanBoardSnapshot(
            boardSnapshotID: "board-freeze-window-v1",
            activeTaskID: "XT-FREEZE-01",
            freezeWindowActive: true,
            tasks: [
                ReplanTaskSnapshot(
                    taskID: "XT-FREEZE-01",
                    priority: .p0,
                    isReleaseBlocker: false,
                    freezeWindowActive: true,
                    ownerLane: "XT-L2"
                ),
                ReplanTaskSnapshot(
                    taskID: "XT-W3-20",
                    priority: .p1,
                    isReleaseBlocker: false,
                    freezeWindowActive: false,
                    ownerLane: "XT-L2"
                )
            ]
        )
    }

    private func acceptedProposal() -> ChangeRequestProposal {
        ChangeRequestProposal(
            crID: "CR-ACCEPT-01",
            summary: "accept lane-local doc refinement after current delivery closes",
            targetTaskID: "XT-W3-20",
            priority: .p1,
            impactArea: .lane,
            requestedPreemption: false,
            replayToken: "replay-accept-01",
            evidenceRefs: ["build/reports/xt_w3_19_s1_delivery_economics_evidence.v2.json"]
        )
    }

    private func releaseBlockerProposal() -> ChangeRequestProposal {
        ChangeRequestProposal(
            crID: "CR-QUEUE-REL-01",
            summary: "P1 copy tweak requests immediate preemption during release blocker window",
            targetTaskID: "XT-W3-20",
            priority: .p1,
            impactArea: .pool,
            requestedPreemption: true,
            replayToken: "replay-queue-rel-01",
            evidenceRefs: ["build/reports/xt_w3_19_delivery_notify_evidence.v1.json"]
        )
    }

    private func freezeWindowProposal() -> ChangeRequestProposal {
        ChangeRequestProposal(
            crID: "CR-QUEUE-FREEZE-01",
            summary: "queue policy change inside freeze window without preemption",
            targetTaskID: "XT-W3-20",
            priority: .p1,
            impactArea: .pool,
            requestedPreemption: false,
            replayToken: "replay-queue-freeze-01",
            evidenceRefs: ["build/reports/xt_w3_18_integration_evidence.v2.json"]
        )
    }

    private func rejectedProposal() -> ChangeRequestProposal {
        ChangeRequestProposal(
            crID: "CR-REJECT-01",
            summary: "global reprioritization request without replay chain",
            targetTaskID: "XT-W3-20",
            priority: .p1,
            impactArea: .global,
            requestedPreemption: true,
            replayToken: nil,
            evidenceRefs: []
        )
    }

    private func percentile95(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let index = Int(ceil(Double(sorted.count) * 0.95)) - 1
        return sorted[max(0, min(index, sorted.count - 1))]
    }
}

private struct ReplanRuntimeCapture: Codable {
    let schemaVersion: String
    let sampleWindow: String
    let replanLatencyP95MS: Double
    let decisionSamples: [ReplanRuntimeDecisionSample]
    let acceptedCount: Int
    let queuedCount: Int
    let rejectedCount: Int
    let releaseBlockerProtectionResult: ReplanRuntimeReleaseBlockerProtection
    let freezeWindowQueueSemantics: ReplanRuntimeFreezeQueueSemantics
    let replayabilityCheck: ReplanReplayCheck
    let sourceRefs: [String]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case sampleWindow = "sample_window"
        case replanLatencyP95MS = "replan_latency_p95_ms"
        case decisionSamples = "decision_samples"
        case acceptedCount = "accepted_count"
        case queuedCount = "queued_count"
        case rejectedCount = "rejected_count"
        case releaseBlockerProtectionResult = "release_blocker_protection_result"
        case freezeWindowQueueSemantics = "freeze_window_queue_semantics"
        case replayabilityCheck = "replayability_check"
        case sourceRefs = "source_refs"
    }
}

private struct ReplanRuntimeDecisionSample: Codable {
    let crID: String
    let verdict: String
    let reasonCode: String
    let explanation: String
    let queueAfterTaskID: String?
    let protectedTaskID: String?
    let freezeWindowApplied: Bool
    let releaseBlockerProtectionApplied: Bool
    let replayableDecisionChain: Bool
    let decisionFingerprint: String

    init(_ decision: ReplanDecision) {
        crID = decision.crID
        verdict = decision.verdict.rawValue
        reasonCode = decision.reasonCode
        explanation = decision.explanation
        queueAfterTaskID = decision.queueAfterTaskID
        protectedTaskID = decision.protectedTaskID
        freezeWindowApplied = decision.freezeWindowApplied
        releaseBlockerProtectionApplied = decision.releaseBlockerProtectionApplied
        replayableDecisionChain = decision.replayableDecisionChain
        decisionFingerprint = decision.decisionFingerprint
    }

    enum CodingKeys: String, CodingKey {
        case crID = "cr_id"
        case verdict
        case reasonCode = "reason_code"
        case explanation
        case queueAfterTaskID = "queue_after_task_id"
        case protectedTaskID = "protected_task_id"
        case freezeWindowApplied = "freeze_window_applied"
        case releaseBlockerProtectionApplied = "release_blocker_protection_applied"
        case replayableDecisionChain = "replayable_decision_chain"
        case decisionFingerprint = "decision_fingerprint"
    }
}

private struct ReplanRuntimeReleaseBlockerProtection: Codable {
    let pass: Bool
    let protectedTaskID: String?
    let blockedPreemptionCRID: String
    let queueAfterTaskID: String?

    enum CodingKeys: String, CodingKey {
        case pass
        case protectedTaskID = "protected_task_id"
        case blockedPreemptionCRID = "blocked_preemption_cr_id"
        case queueAfterTaskID = "queue_after_task_id"
    }
}

private struct ReplanRuntimeFreezeQueueSemantics: Codable {
    let pass: Bool
    let queuedCRID: String
    let queueAfterTaskID: String?
    let policyReasonCode: String

    enum CodingKeys: String, CodingKey {
        case pass
        case queuedCRID = "queued_cr_id"
        case queueAfterTaskID = "queue_after_task_id"
        case policyReasonCode = "policy_reason_code"
    }
}
