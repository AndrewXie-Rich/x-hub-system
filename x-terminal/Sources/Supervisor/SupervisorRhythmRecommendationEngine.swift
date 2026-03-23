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
                return "先核对完成证据，再归档或正式关闭项目。"
            case .archived:
                return "除非明确重新开启 scope，否则保持归档。"
            default:
                return eventNextAction
            }
        }

        switch event.eventType {
        case .awaitingAuthorization:
            return "先审查待批事项并记录决定，再让项目继续。"
        case .blocked:
            if looksDecisionShaped(event.actionSummary + " " + event.whyItMatters) {
                return "先选择或批准下一条安全路径，再继续分发工作。"
            }
            return "先解除阻塞，或在下一个检查点前选择一个明确兜底方案。"
        case .created:
            return "先审查新项目，并确认一个明确的下一步。"
        case .progressed:
            if looksLikeDecisionRailCleanup(event.actionSummary + " " + event.whyItMatters + " " + event.nextAction) {
                let eventNextAction = normalizedDisplayText(event.nextAction, fallback: "")
                if !eventNextAction.isEmpty, !looksLikeMissingNextStep(eventNextAction) {
                    return eventNextAction
                }
                return "检查决策 / 背景边界，决定是转成正式规则，还是继续明确保持非约束。"
            }
            return "等待下一次实质变化；不要因为状态噪音打断。"
        case .completed:
            return "先核对完成证据，再归档或正式关闭项目。"
        case .archived:
            return "除非明确重新开启 scope，否则保持归档。"
        }
    }

    private static func nextUpdateEta(
        for event: SupervisorProjectActionEvent,
        substantiveChange: Bool
    ) -> String {
        switch event.eventType {
        case .awaitingAuthorization:
            return "在授权决定记录后"
        case .blocked:
            return "在阻塞解除或下一个检查点后"
        case .created:
            return "在第一次项目集检视后"
        case .completed:
            return "在确认归档或正式收尾后"
        case .archived:
            return "仅当 scope 被明确重新开启时"
        case .progressed:
            return substantiveChange
                ? "在下一个检查点或建议变化时"
                : "仅当建议发生变化时"
        }
    }

    private static func defaultWhyItMatters(for event: SupervisorProjectActionEvent) -> String {
        switch event.eventType {
        case .awaitingAuthorization:
            return "项目在授权决定落地前不能继续。"
        case .blocked:
            return "这个阻塞正在阻止项目继续前进。"
        case .created:
            return "新项目需要一个明确的第一步，而不是再来一条状态广播。"
        case .completed:
            return "已完成工作应该离开活跃队列，让首页继续保持行动优先。"
        case .archived:
            return "已归档工作应保持安静，除非 scope 被明确重新开启。"
        case .progressed:
            if looksLikeDecisionRailCleanup(event.actionSummary + " " + event.whyItMatters + " " + event.nextAction) {
                return "决策 / 背景优先级漂移应先清理，避免弱偏好重新渗回执行。"
            }
            return "只有会改变建议的进展，才值得打断 Supervisor。"
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
            "决策护栏",
            "被遮蔽背景",
            "弱约束偏好",
            "非约束",
            "只作为背景",
            "优先级边界",
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
            "等待下一次实质变化；不要因为状态噪音打断。",
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
