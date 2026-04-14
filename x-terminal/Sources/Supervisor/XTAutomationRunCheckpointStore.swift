import Foundation

enum XTAutomationRunStepState: String, Codable, Equatable {
    case pending
    case inProgress = "in_progress"
    case verifying
    case blocked
    case retryWait = "retry_wait"
    case done

    var displayName: String {
        switch self {
        case .pending:
            return "待开始"
        case .inProgress:
            return "执行中"
        case .verifying:
            return "验证中"
        case .blocked:
            return "已阻塞"
        case .retryWait:
            return "等待重试"
        case .done:
            return "已完成"
        }
    }
}

struct XTAutomationRunCheckpoint: Codable, Equatable, Identifiable {
    static let currentSchemaVersion = "xt.automation_run_checkpoint.v1"

    let schemaVersion: String
    let runID: String
    let recipeID: String
    let state: XTAutomationRunState
    let attempt: Int
    let lastTransition: String
    let retryAfterSeconds: Int
    let resumeToken: String
    let checkpointRef: String
    let stableIdentity: Bool
    let currentStepID: String?
    let currentStepTitle: String?
    let currentStepState: XTAutomationRunStepState?
    let currentStepSummary: String?
    let auditRef: String

    var id: String { checkpointRef }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case runID = "run_id"
        case recipeID = "recipe_id"
        case state
        case attempt
        case lastTransition = "last_transition"
        case retryAfterSeconds = "retry_after_seconds"
        case resumeToken = "resume_token"
        case checkpointRef = "checkpoint_ref"
        case stableIdentity = "stable_identity"
        case currentStepID = "current_step_id"
        case currentStepTitle = "current_step_title"
        case currentStepState = "current_step_state"
        case currentStepSummary = "current_step_summary"
        case auditRef = "audit_ref"
    }

    init(
        schemaVersion: String,
        runID: String,
        recipeID: String,
        state: XTAutomationRunState,
        attempt: Int,
        lastTransition: String,
        retryAfterSeconds: Int,
        resumeToken: String,
        checkpointRef: String,
        stableIdentity: Bool,
        currentStepID: String? = nil,
        currentStepTitle: String? = nil,
        currentStepState: XTAutomationRunStepState? = nil,
        currentStepSummary: String? = nil,
        auditRef: String
    ) {
        self.schemaVersion = schemaVersion
        self.runID = runID
        self.recipeID = recipeID
        self.state = state
        self.attempt = attempt
        self.lastTransition = lastTransition
        self.retryAfterSeconds = retryAfterSeconds
        self.resumeToken = resumeToken
        self.checkpointRef = checkpointRef
        self.stableIdentity = stableIdentity
        self.currentStepID = xtAutomationNormalizedOptionalScalar(currentStepID)
        self.currentStepTitle = xtAutomationNormalizedOptionalScalar(currentStepTitle)
        self.currentStepState = currentStepState
        self.currentStepSummary = xtAutomationNormalizedOptionalScalar(currentStepSummary)
        self.auditRef = auditRef
    }
}

enum XTAutomationRestartRecoveryAction: String, Codable, Equatable {
    case resume
    case hold
    case scavenged
    case suppressed
}

enum XTAutomationRestartRecoveryMode: String, Codable, Equatable {
    case automatic
    case operatorOverride = "operator_override"

    var respectsRetryBackoff: Bool {
        switch self {
        case .automatic:
            return true
        case .operatorOverride:
            return false
        }
    }
}

struct XTAutomationRestartRecoveryDecision: Codable, Equatable {
    static let currentSchemaVersion = "xt.automation_restart_recovery_decision.v1"

    let schemaVersion: String
    let runID: String
    let recipeID: String
    let recoveredState: XTAutomationRunState
    let decision: XTAutomationRestartRecoveryAction
    let holdReason: String
    let stableIdentityPass: Bool
    let checkpointRef: String
    let resumeToken: String
    let auditRef: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case runID = "run_id"
        case recipeID = "recipe_id"
        case recoveredState = "recovered_state"
        case decision
        case holdReason = "hold_reason"
        case stableIdentityPass = "stable_identity_pass"
        case checkpointRef = "checkpoint_ref"
        case resumeToken = "resume_token"
        case auditRef = "audit_ref"
    }
}

final class XTAutomationRunCheckpointStore {
    static let recoverableStates: Set<XTAutomationRunState> = [.blocked, .takeover, .downgraded]

    let maxAttempts: Int

    private(set) var current: XTAutomationRunCheckpoint?
    private(set) var history: [XTAutomationRunCheckpoint] = []
    private(set) var cancelled = false
    private(set) var cancelAuditRef = ""

    init(maxAttempts: Int = 3) {
        self.maxAttempts = max(1, maxAttempts)
    }

    var latestRecoverableCheckpoint: XTAutomationRunCheckpoint? {
        history.last(where: { Self.recoverableStates.contains($0.state) })
    }

    @discardableResult
    func bootstrap(
        runID: String,
        recipeID: String,
        initialState: XTAutomationRunState = .queued,
        retryAfterSeconds: Int = 0,
        currentStepID: String? = nil,
        currentStepTitle: String? = nil,
        currentStepState: XTAutomationRunStepState? = nil,
        currentStepSummary: String? = nil,
        auditRef: String
    ) -> XTAutomationRunCheckpoint {
        let checkpoint = makeCheckpoint(
            runID: runID,
            recipeID: recipeID,
            previous: nil,
            nextState: initialState,
            retryAfterSeconds: retryAfterSeconds,
            currentStepID: currentStepID,
            currentStepTitle: currentStepTitle,
            currentStepState: currentStepState,
            currentStepSummary: currentStepSummary,
            auditRef: auditRef
        )
        current = checkpoint
        history = [checkpoint]
        cancelled = false
        cancelAuditRef = ""
        return checkpoint
    }

    @discardableResult
    func transition(
        to nextState: XTAutomationRunState,
        retryAfterSeconds: Int = 0,
        currentStepID: String? = nil,
        currentStepTitle: String? = nil,
        currentStepState: XTAutomationRunStepState? = nil,
        currentStepSummary: String? = nil,
        auditRef: String
    ) -> XTAutomationRunCheckpoint {
        guard let current else {
            let failed = makeFailureCheckpoint(
                runID: "run-unbootstrapped",
                recipeID: "unknown",
                auditRef: auditRef
            )
            self.current = failed
            self.history = [failed]
            return failed
        }

        let checkpoint = makeCheckpoint(
            runID: current.runID,
            recipeID: current.recipeID,
            previous: current,
            nextState: nextState,
            retryAfterSeconds: retryAfterSeconds,
            currentStepID: currentStepID,
            currentStepTitle: currentStepTitle,
            currentStepState: currentStepState,
            currentStepSummary: currentStepSummary,
            auditRef: auditRef
        )
        self.current = checkpoint
        self.history.append(checkpoint)
        return checkpoint
    }

    @discardableResult
    func restore(
        checkpoints: [XTAutomationRunCheckpoint],
        wasCancelled: Bool = false,
        cancelAuditRef: String = ""
    ) -> XTAutomationRunCheckpoint? {
        guard let latestCheckpoint = checkpoints.last else {
            current = nil
            history = []
            cancelled = wasCancelled
            self.cancelAuditRef = wasCancelled
                ? cancelAuditRef.trimmingCharacters(in: .whitespacesAndNewlines)
                : ""
            return nil
        }

        // Persisted checkpoint reconstruction must preserve the original truth
        // instead of re-deriving identity and attempt metadata.
        current = latestCheckpoint
        history = checkpoints
        cancelled = wasCancelled
        self.cancelAuditRef = wasCancelled
            ? cancelAuditRef.trimmingCharacters(in: .whitespacesAndNewlines)
            : ""
        return latestCheckpoint
    }

    func markCancelled(auditRef: String) {
        cancelled = true
        cancelAuditRef = auditRef.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func recoverAfterRestart(
        checkpointAgeSeconds: Int,
        recoveryMode: XTAutomationRestartRecoveryMode = .automatic,
        staleAfterSeconds: Int = 900,
        auditRef: String
    ) -> XTAutomationRestartRecoveryDecision {
        guard let checkpoint = current else {
            return XTAutomationRestartRecoveryDecision(
                schemaVersion: XTAutomationRestartRecoveryDecision.currentSchemaVersion,
                runID: "run-missing",
                recipeID: "unknown",
                recoveredState: .failed,
                decision: .hold,
                holdReason: "checkpoint_missing",
                stableIdentityPass: false,
                checkpointRef: "",
                resumeToken: "",
                auditRef: auditRef
            )
        }

        return Self.recoveryDecision(
            for: checkpoint,
            wasCancelled: cancelled,
            checkpointAgeSeconds: checkpointAgeSeconds,
            recoveryMode: recoveryMode,
            staleAfterSeconds: staleAfterSeconds,
            maxAttempts: maxAttempts,
            auditRef: auditRef
        )
    }

    static func recoveryDecision(
        for checkpoint: XTAutomationRunCheckpoint,
        wasCancelled: Bool,
        checkpointAgeSeconds: Int,
        recoveryMode: XTAutomationRestartRecoveryMode = .automatic,
        staleAfterSeconds: Int = 900,
        maxAttempts: Int = 3,
        auditRef: String
    ) -> XTAutomationRestartRecoveryDecision {
        let stableIdentityPass = checkpoint.stableIdentity && !checkpoint.runID.isEmpty
        let normalizedCheckpointAgeSeconds = max(0, checkpointAgeSeconds)
        let retryBackoffPending =
            recoveryMode.respectsRetryBackoff
            && recoverableStates.contains(checkpoint.state)
            && checkpoint.retryAfterSeconds > 0
            && normalizedCheckpointAgeSeconds < checkpoint.retryAfterSeconds

        let decision: XTAutomationRestartRecoveryAction
        let holdReason: String

        if wasCancelled {
            decision = .suppressed
            holdReason = "manual_cancelled"
        } else if normalizedCheckpointAgeSeconds > staleAfterSeconds
                    && checkpoint.state != .delivered
                    && checkpoint.state != .failed {
            decision = .scavenged
            holdReason = "stale_run_scavenged"
        } else if !stableIdentityPass {
            decision = .hold
            holdReason = "stable_identity_failed"
        } else if checkpoint.attempt > max(1, maxAttempts) {
            decision = .hold
            holdReason = "retry_budget_exhausted"
        } else if retryBackoffPending {
            decision = .hold
            holdReason = "retry_after_not_elapsed"
        } else if recoverableStates.contains(checkpoint.state) {
            decision = .resume
            holdReason = ""
        } else {
            decision = .hold
            holdReason = checkpoint.state == .delivered ? "run_already_delivered" : "state_not_restartable"
        }

        return XTAutomationRestartRecoveryDecision(
            schemaVersion: XTAutomationRestartRecoveryDecision.currentSchemaVersion,
            runID: checkpoint.runID,
            recipeID: checkpoint.recipeID,
            recoveredState: checkpoint.state,
            decision: decision,
            holdReason: holdReason,
            stableIdentityPass: stableIdentityPass,
            checkpointRef: checkpoint.checkpointRef,
            resumeToken: checkpoint.resumeToken,
            auditRef: auditRef
        )
    }

    private func makeCheckpoint(
        runID: String,
        recipeID: String,
        previous: XTAutomationRunCheckpoint?,
        nextState: XTAutomationRunState,
        retryAfterSeconds: Int,
        currentStepID: String?,
        currentStepTitle: String?,
        currentStepState: XTAutomationRunStepState?,
        currentStepSummary: String?,
        auditRef: String
    ) -> XTAutomationRunCheckpoint {
        let nextIndex = (history.count + 1)
        let previousAttempt = previous?.attempt ?? 1
        let attempt = xtAutomationCheckpointAttempt(
            from: previous?.state,
            to: nextState,
            currentAttempt: previousAttempt
        )
        let lastTransition = previous.map { "\($0.state.rawValue)_to_\(nextState.rawValue)" }
            ?? "bootstrap_to_\(nextState.rawValue)"
        let resolvedStepID = xtAutomationNormalizedOptionalScalar(currentStepID) ?? previous?.currentStepID
        let resolvedStepTitle = xtAutomationNormalizedOptionalScalar(currentStepTitle) ?? previous?.currentStepTitle
        let resolvedStepSummary = xtAutomationNormalizedOptionalScalar(currentStepSummary) ?? previous?.currentStepSummary
        let hasStepContext =
            resolvedStepID != nil ||
            resolvedStepTitle != nil ||
            resolvedStepSummary != nil ||
            previous?.currentStepState != nil
        let resolvedStepState = currentStepState
            ?? (hasStepContext
                ? xtAutomationDerivedStepState(
                    for: nextState,
                    retryAfterSeconds: retryAfterSeconds,
                    previous: previous?.currentStepState
                )
                : nil)
        return XTAutomationRunCheckpoint(
            schemaVersion: XTAutomationRunCheckpoint.currentSchemaVersion,
            runID: runID,
            recipeID: recipeID,
            state: nextState,
            attempt: attempt,
            lastTransition: lastTransition,
            retryAfterSeconds: max(0, retryAfterSeconds),
            resumeToken: xtAutomationResumeToken(runID: runID, attempt: attempt, state: nextState),
            checkpointRef: xtAutomationCheckpointRef(index: nextIndex),
            stableIdentity: previous?.runID == nil || previous?.runID == runID,
            currentStepID: resolvedStepID,
            currentStepTitle: resolvedStepTitle,
            currentStepState: resolvedStepState,
            currentStepSummary: resolvedStepSummary,
            auditRef: auditRef
        )
    }

    private func makeFailureCheckpoint(runID: String, recipeID: String, auditRef: String) -> XTAutomationRunCheckpoint {
        XTAutomationRunCheckpoint(
            schemaVersion: XTAutomationRunCheckpoint.currentSchemaVersion,
            runID: runID,
            recipeID: recipeID,
            state: .failed,
            attempt: 1,
            lastTransition: "bootstrap_missing",
            retryAfterSeconds: 0,
            resumeToken: xtAutomationResumeToken(runID: runID, attempt: 1, state: .failed),
            checkpointRef: xtAutomationCheckpointRef(index: 1),
            stableIdentity: false,
            currentStepID: nil,
            currentStepTitle: nil,
            currentStepState: nil,
            currentStepSummary: nil,
            auditRef: auditRef
        )
    }
}

private func xtAutomationCheckpointAttempt(
    from currentState: XTAutomationRunState?,
    to nextState: XTAutomationRunState,
    currentAttempt: Int
) -> Int {
    guard let currentState else { return 1 }
    if nextState == .running && currentState != .running {
        return currentAttempt + 1
    }
    return currentAttempt
}

private func xtAutomationResumeToken(runID: String, attempt: Int, state: XTAutomationRunState) -> String {
    let normalizedRunID = xtAutomationNormalizedRunToken(runID)
    return "resume-\(normalizedRunID)-a\(max(1, attempt))-\(state.rawValue)"
}

private func xtAutomationCheckpointRef(index: Int) -> String {
    let normalizedIndex = String(format: "%03d", max(1, index))
    return "build/reports/xt_w3_25_run_checkpoint_\(normalizedIndex).v1.json"
}

private func xtAutomationDerivedStepState(
    for runState: XTAutomationRunState,
    retryAfterSeconds: Int,
    previous: XTAutomationRunStepState?
) -> XTAutomationRunStepState {
    switch runState {
    case .queued:
        return .pending
    case .running:
        return previous == .verifying ? .verifying : .inProgress
    case .blocked, .takeover, .downgraded, .failed:
        return retryAfterSeconds > 0 ? .retryWait : .blocked
    case .delivered:
        return .done
    }
}

func xtAutomationNormalizedOptionalScalar(_ rawValue: String?) -> String? {
    let trimmed = (rawValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

private func xtAutomationNormalizedRunToken(_ runID: String) -> String {
    var token = ""
    var lastWasSeparator = false
    for scalar in runID.unicodeScalars {
        if CharacterSet.alphanumerics.contains(scalar) {
            token.unicodeScalars.append(scalar)
            lastWasSeparator = false
        } else if !lastWasSeparator {
            token.append("-")
            lastWasSeparator = true
        }
    }
    let trimmed = token.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    return trimmed.isEmpty ? "run" : trimmed
}
