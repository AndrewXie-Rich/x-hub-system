import Foundation

enum SupervisorRhythmRecommendationType: String, Codable, Sendable {
    case steadyState = "steady_state"
    case decisionRequired = "decision_required"
    case decisionRailCleanup = "decision_rail_cleanup"
    case unblockRequired = "unblock_required"
    case defineNextStep = "define_next_step"
    case keepMomentum = "keep_momentum"
    case closeOut = "close_out"
    case archiveState = "archive_state"
    case intakeReview = "intake_review"
}

struct SupervisorRhythmRecommendation: Equatable, Codable, Sendable {
    static let schemaVersion = "xt.supervisor_rhythm_recommendation.v1"

    var schemaVersion: String
    var projectId: String
    var projectName: String
    var eventId: String
    var eventType: SupervisorProjectActionEventType
    var severity: SupervisorProjectActionSeverity
    var recommendationType: SupervisorRhythmRecommendationType
    var isSubstantiveChange: Bool
    var whatChanged: String
    var whyItMatters: String
    var waitingOn: String
    var recommendedNextAction: String
    var nextUpdateEta: String
    var evidenceRefs: [String]
    var dedupeKey: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case projectId = "project_id"
        case projectName = "project_name"
        case eventId = "event_id"
        case eventType = "event_type"
        case severity
        case recommendationType = "recommendation_type"
        case isSubstantiveChange = "is_substantive_change"
        case whatChanged = "what_changed"
        case whyItMatters = "why_it_matters"
        case waitingOn = "waiting_on"
        case recommendedNextAction = "recommended_next_action"
        case nextUpdateEta = "next_update_eta"
        case evidenceRefs = "evidence_refs"
        case dedupeKey = "dedupe_key"
    }
}

enum SupervisorRhythmRecommendationEngine {
    static func recommendation(for event: SupervisorProjectActionEvent) -> SupervisorRhythmRecommendation {
        let whatChanged = normalizedDisplayText(event.actionSummary, fallback: event.actionTitle)
        let whyItMatters = normalizedDisplayText(
            event.whyItMatters,
            fallback: defaultWhyItMatters(for: event)
        )
        let recommendedNextAction = normalizedDisplayText(
            resolvedNextAction(for: event),
            fallback: "Continue with the next checkpoint."
        )
        let recommendationType = recommendationType(for: event, recommendedNextAction: recommendedNextAction)
        let isSubstantiveChange = substantiveChange(for: event, recommendedNextAction: recommendedNextAction)
        let waitingOn = waitingOnText(for: event)
        let nextUpdateEta = nextUpdateEta(for: event, substantiveChange: isSubstantiveChange)
        let evidenceRefs = ["supervisor_project_action_event:\(event.eventId)"]
        let dedupeKey = dedupeKey(
            for: event,
            recommendationType: recommendationType,
            substantiveChange: isSubstantiveChange,
            waitingOn: waitingOn,
            recommendedNextAction: recommendedNextAction,
            whatChanged: whatChanged
        )

        return SupervisorRhythmRecommendation(
            schemaVersion: SupervisorRhythmRecommendation.schemaVersion,
            projectId: event.projectId,
            projectName: event.projectName,
            eventId: event.eventId,
            eventType: event.eventType,
            severity: event.severity,
            recommendationType: recommendationType,
            isSubstantiveChange: isSubstantiveChange,
            whatChanged: whatChanged,
            whyItMatters: whyItMatters,
            waitingOn: waitingOn,
            recommendedNextAction: recommendedNextAction,
            nextUpdateEta: nextUpdateEta,
            evidenceRefs: evidenceRefs,
            dedupeKey: dedupeKey
        )
    }

    private static func recommendationType(
        for event: SupervisorProjectActionEvent,
        recommendedNextAction: String
    ) -> SupervisorRhythmRecommendationType {
        switch event.eventType {
        case .awaitingAuthorization:
            return .decisionRequired
        case .blocked:
            if looksDecisionShaped(event.actionSummary + " " + event.nextAction) {
                return .decisionRequired
            }
            if looksLikeMissingNextStep(recommendedNextAction) {
                return .defineNextStep
            }
            return .unblockRequired
        case .created:
            return .intakeReview
        case .completed:
            return .closeOut
        case .archived:
            return .archiveState
        case .progressed:
            if looksLikeDecisionRailCleanup(event.actionSummary + " " + event.whyItMatters + " " + event.nextAction) {
                return .decisionRailCleanup
            }
            let isSubstantive = substantiveChange(for: event, recommendedNextAction: recommendedNextAction)
            guard isSubstantive else { return .steadyState }
            if looksLikeMissingNextStep(recommendedNextAction) {
                return .defineNextStep
            }
            return .keepMomentum
        }
    }

    private static func substantiveChange(
        for event: SupervisorProjectActionEvent,
        recommendedNextAction: String
    ) -> Bool {
        switch event.eventType {
        case .awaitingAuthorization, .blocked, .created, .completed, .archived:
            return true
        case .progressed:
            if looksLikeDecisionRailCleanup(event.actionSummary + " " + event.whyItMatters + " " + event.nextAction) {
                return true
            }
            if event.severity == .interruptNow || event.severity == .authorizationRequired || event.severity == .briefCard {
                return true
            }
            let merged = [recommendedNextAction, event.whyItMatters, event.actionSummary].joined(separator: " ")
            return hasUrgentRecommendationSignal(merged)
        }
    }

    private static func waitingOnText(for event: SupervisorProjectActionEvent) -> String {
        switch event.eventType {
        case .awaitingAuthorization:
            return "user / Hub authorization"
        case .blocked:
            if looksDecisionShaped(event.actionSummary + " " + event.nextAction) {
                return "a portfolio-level decision"
            }
            return "blocker resolution"
        case .completed, .archived:
            return "none"
        case .created:
            return "first concrete triage step"
        case .progressed:
            if looksLikeDecisionRailCleanup(event.actionSummary + " " + event.whyItMatters + " " + event.nextAction) {
                return SupervisorDecisionRailMessaging.waitingOnText
            }
            return substantiveChange(for: event, recommendedNextAction: resolvedNextAction(for: event))
                ? "the recommended next action"
                : "none"
        }
    }

    private static func resolvedNextAction(for event: SupervisorProjectActionEvent) -> String {
        let eventNextAction = normalizedDisplayText(event.nextAction, fallback: "")
        if !eventNextAction.isEmpty, !looksLikeMissingNextStep(eventNextAction) {
            switch event.eventType {
            case .completed:
                if looksLikeArchiveReviewAction(eventNextAction) {
                    return eventNextAction
                }
                return "Review completion evidence, then archive or close out the project."
            case .archived:
                return "Keep the project archived unless new scope is explicitly approved."
            default:
                return eventNextAction
            }
        }

        switch event.eventType {
        case .awaitingAuthorization:
            return "Review the pending approval and record a decision before asking the project to continue."
        case .blocked:
            if looksDecisionShaped(event.actionSummary + " " + event.whyItMatters) {
                return "Choose or approve the next safe path before routing more work."
            }
            return "Resolve the blocker or choose an explicit fallback before the next checkpoint."
        case .created:
            return "Review the new project and confirm one concrete next step."
        case .progressed:
            if looksLikeDecisionRailCleanup(event.actionSummary + " " + event.whyItMatters + " " + event.nextAction) {
                let eventNextAction = normalizedDisplayText(event.nextAction, fallback: "")
                if !eventNextAction.isEmpty, !looksLikeMissingNextStep(eventNextAction) {
                    return eventNextAction
                }
                return "Review the decision/background boundary and either formalize the preference or keep it explicitly non-binding."
            }
            return "Wait for the next material change; do not interrupt on status churn."
        case .completed:
            return "Review completion evidence, then archive or close out the project."
        case .archived:
            return "Keep the project archived unless new scope is explicitly approved."
        }
    }

    private static func nextUpdateEta(
        for event: SupervisorProjectActionEvent,
        substantiveChange: Bool
    ) -> String {
        switch event.eventType {
        case .awaitingAuthorization:
            return "after the authorization decision is recorded"
        case .blocked:
            return "after blocker resolution or the next checkpoint"
        case .created:
            return "after the first portfolio check-in"
        case .completed:
            return "after archive or close-out is confirmed"
        case .archived:
            return "only if new scope is explicitly reopened"
        case .progressed:
            return substantiveChange
                ? "at the next checkpoint or when the recommendation changes"
                : "only when the recommendation changes"
        }
    }

    private static func defaultWhyItMatters(for event: SupervisorProjectActionEvent) -> String {
        switch event.eventType {
        case .awaitingAuthorization:
            return "The project cannot continue until the authorization decision is made."
        case .blocked:
            return "The blocker is preventing forward progress."
        case .created:
            return "New portfolio entries need a concrete first move, not another status broadcast."
        case .completed:
            return "Completed work should leave the active queue so the homepage stays action-first."
        case .archived:
            return "Archived work should stay quiet unless scope is explicitly reopened."
        case .progressed:
            if looksLikeDecisionRailCleanup(event.actionSummary + " " + event.whyItMatters + " " + event.nextAction) {
                return "Decision/background precedence drift should be cleaned up before weak preferences leak back into execution."
            }
            return "Only recommendation-changing progress should interrupt the supervisor."
        }
    }

    private static func dedupeKey(
        for event: SupervisorProjectActionEvent,
        recommendationType: SupervisorRhythmRecommendationType,
        substantiveChange: Bool,
        waitingOn: String,
        recommendedNextAction: String,
        whatChanged: String
    ) -> String {
        let seed: [String]
        if substantiveChange {
            seed = [
                event.projectId,
                event.eventType.rawValue,
                recommendationType.rawValue,
                normalizeToken(whatChanged),
                normalizeToken(waitingOn),
                normalizeToken(recommendedNextAction),
            ]
        } else {
            seed = [
                event.projectId,
                "quiet",
                recommendationType.rawValue,
                normalizeToken(recommendedNextAction),
            ]
        }
        return seed.joined(separator: "|")
    }

    private static func looksDecisionShaped(_ text: String) -> Bool {
        let lowered = text.lowercased()
        let tokens = [
            "decision",
            "approve",
            "approval",
            "authorization",
            "grant_required",
            "review_required",
            "needs review",
            "needs approval",
            "sign off",
            "policy",
            "决策",
            "审批",
            "授权",
            "确认",
            "拍板",
            "定案",
        ]
        return tokens.contains { lowered.contains($0) }
    }

    private static func looksLikeDecisionRailCleanup(_ text: String) -> Bool {
        let lowered = text.lowercased()
        let tokens = [
            "decision rail",
            "decision_rail",
            "shadowed background",
            "shadowed_background",
            "weak-only",
            "weak only",
            "non-binding",
            "background-only",
            "precedence boundary",
        ]
        return tokens.contains { lowered.contains($0) }
    }

    private static func looksLikeArchiveReviewAction(_ text: String) -> Bool {
        let lowered = text.lowercased()
        let tokens = [
            "archive",
            "archived",
            "close out",
            "close-out",
            "closeout",
            "rollup",
            "compaction",
            "review completion evidence",
            "收口",
            "归档",
            "结项",
            "归档候选",
        ]
        return tokens.contains { lowered.contains($0) }
    }

    private static func looksLikeMissingNextStep(_ text: String) -> Bool {
        let normalized = normalizeToken(text)
        let placeholders = [
            "",
            "继续当前任务",
            "continue_current_task",
            "wait_for_the_next_material_change;_do_not_interrupt_on_status_churn.",
            "wait_for_the_next_material_change;_do_not_interrupt_on_status_churn",
            "unknown",
            "n/a",
        ]
        return placeholders.contains(normalized)
    }

    private static func hasUrgentRecommendationSignal(_ text: String) -> Bool {
        let lowered = text.lowercased()
        let tokens = [
            "approve",
            "review",
            "resolve",
            "unblock",
            "run",
            "verify",
            "archive",
            "ship",
            "escalate",
            "confirm",
            "handoff",
            "retry",
            "fix",
            "authorize",
            "决策",
            "审批",
            "授权",
            "确认",
            "归档",
            "升级",
            "验证",
            "解阻",
        ]
        return tokens.contains { lowered.contains($0) }
    }

    private static func normalizedDisplayText(_ text: String, fallback: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "(无)" || trimmed == "(暂无)" || trimmed == "(none)" {
            return fallback.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return trimmed
    }

    private static func normalizeToken(_ text: String) -> String {
        text
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: "_", options: .regularExpression)
    }
}
