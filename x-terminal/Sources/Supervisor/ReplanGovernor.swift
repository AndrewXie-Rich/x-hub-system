import Foundation

enum ReplanTaskPriority: String, Codable, Equatable, Comparable {
    case p0ReleaseBlocker = "P0_RELEASE_BLOCKER"
    case p0 = "P0"
    case p1 = "P1"
    case p2 = "P2"

    private var rank: Int {
        switch self {
        case .p0ReleaseBlocker: return 0
        case .p0: return 1
        case .p1: return 2
        case .p2: return 3
        }
    }

    static func < (lhs: ReplanTaskPriority, rhs: ReplanTaskPriority) -> Bool {
        lhs.rank < rhs.rank
    }
}

enum ReplanImpactArea: String, Codable, Equatable {
    case lane
    case pool
    case global
}

enum CRDecisionVerdict: String, Codable, Equatable {
    case accepted
    case queued
    case rejected
}

struct ReplanTaskSnapshot: Codable, Equatable, Identifiable {
    let taskID: String
    let priority: ReplanTaskPriority
    let isReleaseBlocker: Bool
    let freezeWindowActive: Bool
    let ownerLane: String

    var id: String { taskID }

    enum CodingKeys: String, CodingKey {
        case taskID = "task_id"
        case priority
        case isReleaseBlocker = "is_release_blocker"
        case freezeWindowActive = "freeze_window_active"
        case ownerLane = "owner_lane"
    }
}

struct ReplanBoardSnapshot: Codable, Equatable {
    let boardSnapshotID: String
    let activeTaskID: String?
    let freezeWindowActive: Bool
    let tasks: [ReplanTaskSnapshot]

    enum CodingKeys: String, CodingKey {
        case boardSnapshotID = "board_snapshot_id"
        case activeTaskID = "active_task_id"
        case freezeWindowActive = "freeze_window_active"
        case tasks
    }
}

struct ChangeRequestProposal: Codable, Equatable, Identifiable {
    let crID: String
    let summary: String
    let targetTaskID: String
    let priority: ReplanTaskPriority
    let impactArea: ReplanImpactArea
    let requestedPreemption: Bool
    let replayToken: String?
    let evidenceRefs: [String]

    var id: String { crID }

    enum CodingKeys: String, CodingKey {
        case crID = "cr_id"
        case summary
        case targetTaskID = "target_task_id"
        case priority
        case impactArea = "impact_area"
        case requestedPreemption = "requested_preemption"
        case replayToken = "replay_token"
        case evidenceRefs = "evidence_refs"
    }
    var requiresReplayableChain: Bool {
        impactArea != .lane || requestedPreemption
    }

    var hasReplayableChain: Bool {
        guard let replayToken, !replayToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        return !evidenceRefs.isEmpty
    }
}

struct ReplanReplayContext: Codable, Equatable {
    let boardSnapshotID: String
    let activeTaskID: String?
    let activeTaskPriority: ReplanTaskPriority?
    let activeTaskFreezeWindowActive: Bool
    let activeReleaseBlockerTaskID: String?
    let activeReleaseBlockerPriority: ReplanTaskPriority?
    let targetTaskID: String
    let targetTaskPriority: ReplanTaskPriority?
    let targetTaskFreezeWindowActive: Bool
    let boardFreezeWindowActive: Bool

    enum CodingKeys: String, CodingKey {
        case boardSnapshotID = "board_snapshot_id"
        case activeTaskID = "active_task_id"
        case activeTaskPriority = "active_task_priority"
        case activeTaskFreezeWindowActive = "active_task_freeze_window_active"
        case activeReleaseBlockerTaskID = "active_release_blocker_task_id"
        case activeReleaseBlockerPriority = "active_release_blocker_priority"
        case targetTaskID = "target_task_id"
        case targetTaskPriority = "target_task_priority"
        case targetTaskFreezeWindowActive = "target_task_freeze_window_active"
        case boardFreezeWindowActive = "board_freeze_window_active"
    }
}

struct ReplanDecisionAuditRecord: Codable, Equatable, Identifiable {
    let auditID: String
    let createdAtMS: Int64
    let governorID: String
    let changeRequest: ChangeRequestProposal
    let replayContext: ReplanReplayContext
    let verdict: CRDecisionVerdict
    let reasonCode: String
    let explanation: String
    let queueAfterTaskID: String?
    let protectedTaskID: String?
    let decisionFingerprint: String

    var id: String { auditID }

    enum CodingKeys: String, CodingKey {
        case auditID = "audit_id"
        case createdAtMS = "created_at_ms"
        case governorID = "governor_id"
        case changeRequest = "change_request"
        case replayContext = "replay_context"
        case verdict
        case reasonCode = "reason_code"
        case explanation
        case queueAfterTaskID = "queue_after_task_id"
        case protectedTaskID = "protected_task_id"
        case decisionFingerprint = "decision_fingerprint"
    }
}

struct ReplanDecision: Codable, Equatable {
    let crID: String
    let verdict: CRDecisionVerdict
    let reasonCode: String
    let explanation: String
    let queueAfterTaskID: String?
    let protectedTaskID: String?
    let freezeWindowApplied: Bool
    let releaseBlockerProtectionApplied: Bool
    let replayableDecisionChain: Bool
    let latencyMS: Double
    let decisionFingerprint: String
    let auditRecord: ReplanDecisionAuditRecord

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
        case latencyMS = "latency_ms"
        case decisionFingerprint = "decision_fingerprint"
        case auditRecord = "audit_record"
    }
}

struct ReplanReplayCheck: Codable, Equatable {
    let pass: Bool
    let replayedCount: Int
    let mismatchedAuditIDs: [String]
    let replayedFingerprints: [String]

    enum CodingKeys: String, CodingKey {
        case pass
        case replayedCount = "replayed_count"
        case mismatchedAuditIDs = "mismatched_audit_ids"
        case replayedFingerprints = "replayed_fingerprints"
    }
}

final class ReplanGovernor {
    private let governorID = "xterminal.replan_governor.v1"

    func decide(
        proposal: ChangeRequestProposal,
        board: ReplanBoardSnapshot,
        now: Date = Date()
    ) -> ReplanDecision {
        let context = makeReplayContext(proposal: proposal, board: board)
        return decide(proposal: proposal, context: context, now: now)
    }

    func replayDecision(from auditRecord: ReplanDecisionAuditRecord) -> ReplanDecision {
        decide(proposal: auditRecord.changeRequest, context: auditRecord.replayContext, now: Date(timeIntervalSince1970: Double(auditRecord.createdAtMS) / 1000.0), latencyMS: 0)
    }

    private func decide(
        proposal: ChangeRequestProposal,
        context: ReplanReplayContext,
        now: Date,
        latencyMS forcedLatencyMS: Double? = nil
    ) -> ReplanDecision {
        let latencyStart = ProcessInfo.processInfo.systemUptime
        let outcome = evaluate(proposal: proposal, context: context)
        let latencyMS = forcedLatencyMS ?? ((ProcessInfo.processInfo.systemUptime - latencyStart) * 1000.0)
        let fingerprint = Self.makeFingerprint(
            crID: proposal.crID,
            verdict: outcome.verdict,
            reasonCode: outcome.reasonCode,
            queueAfterTaskID: outcome.queueAfterTaskID,
            protectedTaskID: outcome.protectedTaskID,
            freezeWindowApplied: outcome.freezeWindowApplied,
            releaseBlockerProtectionApplied: outcome.releaseBlockerProtectionApplied,
            replayableDecisionChain: outcome.replayableDecisionChain
        )
        let createdAtMS = Int64((now.timeIntervalSince1970 * 1000.0).rounded())
        let auditRecord = ReplanDecisionAuditRecord(
            auditID: "audit_\(proposal.crID)_\(createdAtMS)",
            createdAtMS: createdAtMS,
            governorID: governorID,
            changeRequest: proposal,
            replayContext: context,
            verdict: outcome.verdict,
            reasonCode: outcome.reasonCode,
            explanation: outcome.explanation,
            queueAfterTaskID: outcome.queueAfterTaskID,
            protectedTaskID: outcome.protectedTaskID,
            decisionFingerprint: fingerprint
        )
        return ReplanDecision(
            crID: proposal.crID,
            verdict: outcome.verdict,
            reasonCode: outcome.reasonCode,
            explanation: outcome.explanation,
            queueAfterTaskID: outcome.queueAfterTaskID,
            protectedTaskID: outcome.protectedTaskID,
            freezeWindowApplied: outcome.freezeWindowApplied,
            releaseBlockerProtectionApplied: outcome.releaseBlockerProtectionApplied,
            replayableDecisionChain: outcome.replayableDecisionChain,
            latencyMS: latencyMS,
            decisionFingerprint: fingerprint,
            auditRecord: auditRecord
        )
    }

    private func evaluate(
        proposal: ChangeRequestProposal,
        context: ReplanReplayContext
    ) -> ReplanOutcome {
        let replayableDecisionChain = proposal.hasReplayableChain || !proposal.requiresReplayableChain
        if proposal.requiresReplayableChain && !proposal.hasReplayableChain {
            return ReplanOutcome(
                verdict: .rejected,
                reasonCode: "replay_chain_incomplete",
                explanation: "rejected: impact=\(proposal.impactArea.rawValue) requires replay token + evidence refs before CR arbitration can proceed",
                queueAfterTaskID: nil,
                protectedTaskID: nil,
                freezeWindowApplied: false,
                releaseBlockerProtectionApplied: false,
                replayableDecisionChain: false
            )
        }

        if proposal.requestedPreemption,
           let blockerTaskID = context.activeReleaseBlockerTaskID,
           let blockerPriority = context.activeReleaseBlockerPriority,
           proposal.priority > blockerPriority {
            return ReplanOutcome(
                verdict: .queued,
                reasonCode: "release_blocker_protected",
                explanation: "queued: \(proposal.priority.rawValue) CR cannot preempt active \(blockerPriority.rawValue) release blocker \(blockerTaskID)",
                queueAfterTaskID: blockerTaskID,
                protectedTaskID: blockerTaskID,
                freezeWindowApplied: false,
                releaseBlockerProtectionApplied: true,
                replayableDecisionChain: replayableDecisionChain
            )
        }

        let freezeWindowApplies = context.boardFreezeWindowActive || context.activeTaskFreezeWindowActive || context.targetTaskFreezeWindowActive
        if freezeWindowApplies {
            return ReplanOutcome(
                verdict: .queued,
                reasonCode: "freeze_window_queue_enforced",
                explanation: "queued: freeze window is active, CR must wait behind \(context.activeTaskID ?? context.targetTaskID)",
                queueAfterTaskID: context.activeTaskID ?? context.targetTaskID,
                protectedTaskID: nil,
                freezeWindowApplied: true,
                releaseBlockerProtectionApplied: false,
                replayableDecisionChain: replayableDecisionChain
            )
        }

        return ReplanOutcome(
            verdict: .accepted,
            reasonCode: "accepted_replan",
            explanation: "accepted: no active release blocker conflict and freeze window is inactive for target \(context.targetTaskID)",
            queueAfterTaskID: nil,
            protectedTaskID: nil,
            freezeWindowApplied: false,
            releaseBlockerProtectionApplied: false,
            replayableDecisionChain: replayableDecisionChain
        )
    }

    private func makeReplayContext(
        proposal: ChangeRequestProposal,
        board: ReplanBoardSnapshot
    ) -> ReplanReplayContext {
        let activeTask = board.tasks.first(where: { $0.taskID == board.activeTaskID })
        let activeReleaseBlocker = board.tasks
            .filter(\.isReleaseBlocker)
            .sorted { $0.priority < $1.priority }
            .first
        let targetTask = board.tasks.first(where: { $0.taskID == proposal.targetTaskID })
        return ReplanReplayContext(
            boardSnapshotID: board.boardSnapshotID,
            activeTaskID: activeTask?.taskID,
            activeTaskPriority: activeTask?.priority,
            activeTaskFreezeWindowActive: activeTask?.freezeWindowActive ?? false,
            activeReleaseBlockerTaskID: activeReleaseBlocker?.taskID,
            activeReleaseBlockerPriority: activeReleaseBlocker?.priority,
            targetTaskID: proposal.targetTaskID,
            targetTaskPriority: targetTask?.priority,
            targetTaskFreezeWindowActive: targetTask?.freezeWindowActive ?? false,
            boardFreezeWindowActive: board.freezeWindowActive
        )
    }

    private static func makeFingerprint(
        crID: String,
        verdict: CRDecisionVerdict,
        reasonCode: String,
        queueAfterTaskID: String?,
        protectedTaskID: String?,
        freezeWindowApplied: Bool,
        releaseBlockerProtectionApplied: Bool,
        replayableDecisionChain: Bool
    ) -> String {
        [
            crID,
            verdict.rawValue,
            reasonCode,
            queueAfterTaskID ?? "none",
            protectedTaskID ?? "none",
            freezeWindowApplied ? "freeze" : "no_freeze",
            releaseBlockerProtectionApplied ? "rb_guard" : "no_rb_guard",
            replayableDecisionChain ? "replayable" : "non_replayable"
        ].joined(separator: "|")
    }
}

final class CRArbiter {
    private let governor = ReplanGovernor()

    func evaluate(
        proposals: [ChangeRequestProposal],
        board: ReplanBoardSnapshot,
        now: Date = Date()
    ) -> [ReplanDecision] {
        proposals.map { governor.decide(proposal: $0, board: board, now: now) }
    }

    func replay(auditTrail: [ReplanDecisionAuditRecord]) -> ReplanReplayCheck {
        var mismatchedAuditIDs: [String] = []
        var fingerprints: [String] = []
        for audit in auditTrail {
            let replayed = governor.replayDecision(from: audit)
            fingerprints.append(replayed.decisionFingerprint)
            if replayed.decisionFingerprint != audit.decisionFingerprint {
                mismatchedAuditIDs.append(audit.auditID)
            }
        }
        return ReplanReplayCheck(
            pass: mismatchedAuditIDs.isEmpty,
            replayedCount: auditTrail.count,
            mismatchedAuditIDs: mismatchedAuditIDs,
            replayedFingerprints: fingerprints
        )
    }
}

private struct ReplanOutcome {
    let verdict: CRDecisionVerdict
    let reasonCode: String
    let explanation: String
    let queueAfterTaskID: String?
    let protectedTaskID: String?
    let freezeWindowApplied: Bool
    let releaseBlockerProtectionApplied: Bool
    let replayableDecisionChain: Bool
}
