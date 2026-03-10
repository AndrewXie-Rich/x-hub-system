import Foundation

enum OneShotRunStateStatus: String, Codable, Equatable, CaseIterable {
    case intakeNormalized = "intake_normalized"
    case planning = "planning"
    case awaitingGrant = "awaiting_grant"
    case launching = "launching"
    case running = "running"
    case blocked = "blocked"
    case resuming = "resuming"
    case mergeback = "mergeback"
    case deliveryFreeze = "delivery_freeze"
    case completed = "completed"
    case failedClosed = "failed_closed"
}

enum OneShotRunOwner: String, Codable, Equatable, CaseIterable {
    case supervisor = "Supervisor"
    case xtL2 = "XT-L2"
    case hubL5 = "Hub-L5"
    case qa = "QA"
}

struct OneShotRunStateSnapshot: Codable, Equatable {
    let schemaVersion: String
    let projectID: String
    let requestID: String
    let runID: String
    let state: OneShotRunStateStatus
    let currentOwner: OneShotRunOwner
    let activePools: [String]
    let activeLanes: [String]
    let topBlocker: String
    let nextDirectedTarget: String
    let userVisibleSummary: String
    let evidenceRefs: [String]
    let auditRef: String

    static let frozenFieldOrder = [
        "schema_version",
        "project_id",
        "request_id",
        "run_id",
        "state",
        "current_owner",
        "active_pools",
        "active_lanes",
        "top_blocker",
        "next_directed_target",
        "user_visible_summary",
        "evidence_refs",
        "audit_ref"
    ]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case projectID = "project_id"
        case requestID = "request_id"
        case runID = "run_id"
        case state
        case currentOwner = "current_owner"
        case activePools = "active_pools"
        case activeLanes = "active_lanes"
        case topBlocker = "top_blocker"
        case nextDirectedTarget = "next_directed_target"
        case userVisibleSummary = "user_visible_summary"
        case evidenceRefs = "evidence_refs"
        case auditRef = "audit_ref"
    }
}

struct OneShotFieldFreeze: Codable, Equatable {
    let schemaVersion: String
    let intakeRequestFields: [String]
    let plannerDecisionFields: [String]
    let seatGovernorFields: [String]
    let runStateFields: [String]

    static let ai1Core = OneShotFieldFreeze(
        schemaVersion: "xt.one_shot_field_freeze.v1",
        intakeRequestFields: SupervisorOneShotIntakeRequest.frozenFieldOrder,
        plannerDecisionFields: AdaptivePoolPlanDecision.frozenFieldOrder,
        seatGovernorFields: OneShotSeatGovernorDecision.frozenFieldOrder,
        runStateFields: OneShotRunStateSnapshot.frozenFieldOrder
    )

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case intakeRequestFields = "intake_request_fields"
        case plannerDecisionFields = "planner_decision_fields"
        case seatGovernorFields = "seat_governor_fields"
        case runStateFields = "run_state_fields"
    }
}

struct OneShotControlPlaneSnapshot: Codable, Equatable {
    let schemaVersion: String
    let normalization: OneShotIntakeNormalizationResult
    let planDecision: AdaptivePoolPlanDecision
    let seatGovernor: OneShotSeatGovernorDecision
    let runState: OneShotRunStateSnapshot
    let fieldFreeze: OneShotFieldFreeze

    static func defaultEvidenceRefs() -> [String] {
        [
            "build/reports/xt_w3_26_a_one_shot_intake_evidence.v1.json",
            "build/reports/xt_w3_26_b_adaptive_pool_plan_evidence.v1.json",
            "build/reports/xt_w3_26_c_concurrency_governor_evidence.v1.json",
            "build/reports/xt_w3_26_d_run_state_machine_evidence.v1.json",
            "build/reports/xt_w3_26_ai1_handoff.v1.json"
        ]
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case normalization
        case planDecision = "plan_decision"
        case seatGovernor = "seat_governor"
        case runState = "run_state"
        case fieldFreeze = "field_freeze"
    }
}

struct OneShotVerificationResult: Codable, Equatable, Identifiable {
    let name: String
    let status: String
    let detail: String

    var id: String { name }
}

struct OneShotAIHandoffPacket: Codable, Equatable {
    let schemaVersion: String
    let producer: String
    let claimScope: [String]
    let fieldFreeze: OneShotFieldFreeze
    let runStateEnum: [String]
    let plannerExplainExample: [String]
    let verificationResults: [OneShotVerificationResult]
    let evidenceRefs: [String]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case producer
        case claimScope = "claim_scope"
        case fieldFreeze = "field_freeze"
        case runStateEnum = "run_state_enum"
        case plannerExplainExample = "planner_explain_example"
        case verificationResults = "verification_results"
        case evidenceRefs = "evidence_refs"
    }
}

struct XTW326RunStateMachineEvidence: Codable, Equatable {
    let schemaVersion: String
    let runState: OneShotRunStateSnapshot
    let sourceRefs: [String]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case runState = "run_state"
        case sourceRefs = "source_refs"
    }
}

final class OneShotRunStateStore {
    private static let allowedTransitions: [OneShotRunStateStatus: Set<OneShotRunStateStatus>] = [
        .intakeNormalized: [.planning, .failedClosed],
        .planning: [.awaitingGrant, .launching, .blocked, .failedClosed],
        .awaitingGrant: [.launching, .blocked, .failedClosed],
        .launching: [.running, .blocked, .failedClosed],
        .running: [.blocked, .mergeback, .deliveryFreeze, .failedClosed],
        .blocked: [.resuming, .failedClosed],
        .resuming: [.running, .mergeback, .failedClosed],
        .mergeback: [.deliveryFreeze, .failedClosed],
        .deliveryFreeze: [.completed, .failedClosed],
        .completed: [],
        .failedClosed: []
    ]

    private(set) var current: OneShotRunStateSnapshot?
    private(set) var history: [OneShotRunStateSnapshot] = []

    @discardableResult
    func bootstrap(
        request: SupervisorOneShotIntakeRequest,
        planDecision: AdaptivePoolPlanDecision? = nil,
        owner: OneShotRunOwner = .supervisor,
        evidenceRefs: [String] = OneShotControlPlaneSnapshot.defaultEvidenceRefs()
    ) -> OneShotRunStateSnapshot {
        let runID = oneShotDeterministicUUIDString(seed: "run|\(request.projectID)|\(request.requestID)|\(request.auditRef)")
        let snapshot = OneShotRunStateSnapshot(
            schemaVersion: "xt.one_shot_run_state.v1",
            projectID: request.projectID,
            requestID: request.requestID,
            runID: runID,
            state: .intakeNormalized,
            currentOwner: owner,
            activePools: planDecision?.poolPlan.map(\ .poolID) ?? [],
            activeLanes: planDecision?.poolPlan.flatMap(\ .laneIDs) ?? [],
            topBlocker: "none",
            nextDirectedTarget: owner.rawValue,
            userVisibleSummary: "one-shot intake normalized",
            evidenceRefs: evidenceRefs,
            auditRef: request.auditRef
        )
        current = snapshot
        history = [snapshot]
        return snapshot
    }

    @discardableResult
    func transition(
        to nextState: OneShotRunStateStatus,
        owner: OneShotRunOwner,
        activePools: [String]? = nil,
        activeLanes: [String]? = nil,
        topBlocker: String? = nil,
        nextDirectedTarget: String? = nil,
        userVisibleSummary: String,
        evidenceRefs: [String],
        auditRef: String
    ) -> OneShotRunStateSnapshot {
        guard let current else {
            let failed = OneShotRunStateSnapshot(
                schemaVersion: "xt.one_shot_run_state.v1",
                projectID: "unknown",
                requestID: "unknown",
                runID: oneShotDeterministicUUIDString(seed: "run_state_not_bootstrapped"),
                state: .failedClosed,
                currentOwner: owner,
                activePools: activePools ?? [],
                activeLanes: activeLanes ?? [],
                topBlocker: "run_state_not_bootstrapped",
                nextDirectedTarget: owner.rawValue,
                userVisibleSummary: "failed closed: run state store not bootstrapped",
                evidenceRefs: evidenceRefs,
                auditRef: auditRef
            )
            self.current = failed
            history.append(failed)
            return failed
        }

        let allowed = Self.allowedTransitions[current.state] ?? []
        guard allowed.contains(nextState) else {
            let failed = OneShotRunStateSnapshot(
                schemaVersion: current.schemaVersion,
                projectID: current.projectID,
                requestID: current.requestID,
                runID: current.runID,
                state: .failedClosed,
                currentOwner: owner,
                activePools: activePools ?? current.activePools,
                activeLanes: activeLanes ?? current.activeLanes,
                topBlocker: "invalid_transition_\(current.state.rawValue)_to_\(nextState.rawValue)",
                nextDirectedTarget: owner.rawValue,
                userVisibleSummary: "failed closed: invalid transition \(current.state.rawValue) -> \(nextState.rawValue)",
                evidenceRefs: evidenceRefs,
                auditRef: auditRef
            )
            self.current = failed
            history.append(failed)
            return failed
        }

        let snapshot = OneShotRunStateSnapshot(
            schemaVersion: current.schemaVersion,
            projectID: current.projectID,
            requestID: current.requestID,
            runID: current.runID,
            state: nextState,
            currentOwner: owner,
            activePools: activePools ?? current.activePools,
            activeLanes: activeLanes ?? current.activeLanes,
            topBlocker: topBlocker ?? current.topBlocker,
            nextDirectedTarget: nextDirectedTarget ?? owner.rawValue,
            userVisibleSummary: userVisibleSummary,
            evidenceRefs: evidenceRefs,
            auditRef: auditRef
        )
        self.current = snapshot
        history.append(snapshot)
        return snapshot
    }
}
