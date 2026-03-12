import Foundation

enum SupervisorProjectCapsuleState: String, Codable, Sendable {
    case idle
    case active
    case blocked
    case awaitingAuthorization = "awaiting_authorization"
    case completed
    case archived
}

struct SupervisorProjectCapsule: Equatable, Codable, Sendable {
    static let schemaVersion = "xt.supervisor_project_capsule.v1"

    var schemaVersion: String
    var projectId: String
    var projectName: String
    var projectState: SupervisorProjectCapsuleState
    var goal: String
    var currentPhase: String
    var currentAction: String
    var topBlocker: String
    var nextStep: String
    var memoryFreshness: SupervisorPortfolioMemoryFreshness
    var updatedAtMs: Int64
    var statusDigest: String
    var evidenceRefs: [String]
    var auditRef: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case projectId = "project_id"
        case projectName = "project_name"
        case projectState = "project_state"
        case goal
        case currentPhase = "current_phase"
        case currentAction = "current_action"
        case topBlocker = "top_blocker"
        case nextStep = "next_step"
        case memoryFreshness = "memory_freshness"
        case updatedAtMs = "updated_at_ms"
        case statusDigest = "status_digest"
        case evidenceRefs = "evidence_refs"
        case auditRef = "audit_ref"
    }
}

enum SupervisorProjectCapsuleBuilder {
    static func build(
        from digest: SupervisorManager.SupervisorMemoryProjectDigest,
        now: Double = Date().timeIntervalSince1970,
        evidenceRefs: [String] = []
    ) -> SupervisorProjectCapsule {
        let currentAction = normalizedNonPlaceholder(
            digest.currentState,
            fallback: normalizedNonPlaceholder(digest.runtimeState, fallback: "继续当前任务")
        )
        let topBlocker = normalizedNonPlaceholder(digest.blocker, fallback: "(无)")
        let nextStep = normalizedNonPlaceholder(digest.nextStep, fallback: "继续当前任务")
        let currentPhase = normalizedNonPlaceholder(digest.runtimeState, fallback: "unknown")
        let goal = normalizedNonPlaceholder(digest.goal, fallback: "(暂无)")
        let freshness = memoryFreshness(updatedAt: digest.updatedAt, now: now)

        let capsule = SupervisorProjectCapsule(
            schemaVersion: SupervisorProjectCapsule.schemaVersion,
            projectId: digest.projectId,
            projectName: digest.displayName,
            projectState: capsuleState(from: projectState(from: digest)),
            goal: goal,
            currentPhase: currentPhase,
            currentAction: currentAction,
            topBlocker: topBlocker,
            nextStep: nextStep,
            memoryFreshness: freshness,
            updatedAtMs: max(0, Int64((digest.updatedAt * 1000.0).rounded())),
            statusDigest: statusDigest(
                goal: goal,
                currentAction: currentAction,
                topBlocker: topBlocker,
                nextStep: nextStep
            ),
            evidenceRefs: evidenceRefs.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty },
            auditRef: auditRef(projectId: digest.projectId, updatedAt: digest.updatedAt)
        )
        return capsule
    }

    static func card(
        from capsule: SupervisorProjectCapsule,
        recentMessageCount: Int
    ) -> SupervisorPortfolioProjectCard {
        SupervisorPortfolioProjectCard(
            projectId: capsule.projectId,
            displayName: capsule.projectName,
            projectState: portfolioState(from: capsule.projectState),
            runtimeState: capsule.currentPhase,
            currentAction: capsule.currentAction,
            topBlocker: capsule.topBlocker == "(无)" ? "" : capsule.topBlocker,
            nextStep: capsule.nextStep,
            memoryFreshness: capsule.memoryFreshness,
            updatedAt: Double(capsule.updatedAtMs) / 1000.0,
            recentMessageCount: recentMessageCount
        )
    }

    static func projectState(
        from digest: SupervisorManager.SupervisorMemoryProjectDigest
    ) -> SupervisorPortfolioProjectState {
        let currentAction = normalizedNonPlaceholder(
            digest.currentState,
            fallback: normalizedNonPlaceholder(digest.runtimeState, fallback: "继续当前任务")
        )
        let blocker = normalizedNonPlaceholder(digest.blocker, fallback: "")
        let nextStep = normalizedNonPlaceholder(digest.nextStep, fallback: "继续当前任务")
        return projectState(
            runtimeState: digest.runtimeState,
            currentAction: currentAction,
            blocker: blocker,
            nextStep: nextStep
        )
    }

    static func projectState(
        runtimeState: String,
        currentAction: String,
        blocker: String,
        nextStep: String
    ) -> SupervisorPortfolioProjectState {
        let joined = [runtimeState, currentAction, blocker, nextStep]
            .joined(separator: " ")
            .lowercased()
        if looksLikeAuthorization(joined) {
            return .awaitingAuthorization
        }
        if !blocker.isEmpty {
            return .blocked
        }
        if looksLikeCompleted(joined) {
            return .completed
        }
        if looksLikeIdle(joined) {
            return .idle
        }
        if looksLikeActive(joined) {
            return .active
        }
        return .idle
    }

    static func memoryFreshness(updatedAt: Double, now: Double) -> SupervisorPortfolioMemoryFreshness {
        let age = max(0, now - updatedAt)
        if age <= 5 * 60 { return .fresh }
        if age <= 30 * 60 { return .ttlCached }
        return .stale
    }

    private static func capsuleState(from state: SupervisorPortfolioProjectState) -> SupervisorProjectCapsuleState {
        switch state {
        case .active:
            return .active
        case .blocked:
            return .blocked
        case .awaitingAuthorization:
            return .awaitingAuthorization
        case .completed:
            return .completed
        case .idle:
            return .idle
        }
    }

    private static func portfolioState(from state: SupervisorProjectCapsuleState) -> SupervisorPortfolioProjectState {
        switch state {
        case .idle:
            return .idle
        case .active:
            return .active
        case .blocked:
            return .blocked
        case .awaitingAuthorization:
            return .awaitingAuthorization
        case .completed, .archived:
            return .completed
        }
    }

    private static func statusDigest(
        goal: String,
        currentAction: String,
        topBlocker: String,
        nextStep: String
    ) -> String {
        [
            "goal=\(goal)",
            "action=\(currentAction)",
            "blocker=\(topBlocker)",
            "next=\(nextStep)"
        ].joined(separator: "; ")
    }

    private static func auditRef(projectId: String, updatedAt: Double) -> String {
        "supervisor_project_capsule:\(normalizedToken(projectId)):\(max(0, Int64((updatedAt * 1000.0).rounded())))"
    }

    private static func looksLikeAuthorization(_ text: String) -> Bool {
        let tokens = ["grant_required", "awaiting authorization", "等待授权", "需要授权", "approve"]
        return tokens.contains { text.contains($0) }
    }

    private static func looksLikeCompleted(_ text: String) -> Bool {
        let tokens = ["已完成", "completed", "done", "release_ready", "shipped"]
        return tokens.contains { text.contains($0) }
    }

    private static func looksLikeActive(_ text: String) -> Bool {
        let tokens = ["进行中", "implement", "running", "推进", "active", "working"]
        return tokens.contains { text.contains($0) }
    }

    private static func looksLikeIdle(_ text: String) -> Bool {
        let tokens = ["暂停", "待命", "waiting", "paused", "idle", "排队中", "queued", "queue"]
        return tokens.contains { text.contains($0) }
    }

    private static func normalizedNonPlaceholder(_ value: String?, fallback: String) -> String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty { return fallback }
        let placeholders = ["(暂无)", "(none)", "none", "(无)"]
        if placeholders.contains(trimmed.lowercased()) {
            return fallback
        }
        return trimmed
    }

    private static func normalizedToken(_ text: String) -> String {
        let folded = text.lowercased()
        let scalars = folded.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
        return String(String.UnicodeScalarView(scalars))
    }
}
