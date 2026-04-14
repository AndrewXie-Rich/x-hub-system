import Foundation

struct SupervisorGuidanceContractSummary: Equatable, Sendable {
    enum Kind: String, Equatable, Sendable {
        case uiReviewRepair = "ui_review_repair"
        case grantResolution = "grant_resolution"
        case awaitingInstruction = "awaiting_instruction"
        case incidentRecovery = "incident_recovery"
        case supervisorReplan = "supervisor_replan"

        var displayName: String {
            switch self {
            case .uiReviewRepair:
                return "UI 审查修复"
            case .grantResolution:
                return "授权处理"
            case .awaitingInstruction:
                return "等待指令"
            case .incidentRecovery:
                return "故障恢复"
            case .supervisorReplan:
                return "监督重规划"
            }
        }
    }

    struct UIReviewRepairDetails: Equatable, Sendable {
        var instruction: String
        var repairAction: String
        var repairFocus: String
        var nextSafeAction: String
        var uiReviewRef: String
        var uiReviewReviewId: String
        var uiReviewVerdict: String
        var uiReviewIssueCodes: String
        var uiReviewSummary: String
        var skillResultSummary: String
    }

    var kind: Kind
    var trigger: String
    var reviewLevel: String
    var verdict: String
    var summary: String
    var primaryBlocker: String
    var currentState: String
    var nextStep: String
    var nextSafeAction: String
    var recommendedActions: [String]
    var workOrderRef: String
    var effectiveSupervisorTier: String
    var effectiveWorkOrderDepth: String
    var uiReviewRepair: UIReviewRepairDetails? = nil

    var kindText: String { kind.displayName }

    var summaryText: String {
        firstNonEmpty([
            summary,
            uiReviewRepair?.uiReviewSummary,
            uiReviewRepair?.skillResultSummary,
            primaryBlocker,
            currentState,
            nextStep,
            nextSafeAction
        ]) ?? "(none)"
    }

    var primaryFocusText: String {
        if let uiReviewRepair {
            return joinedSummary([
                uiReviewRepair.repairAction.isEmpty ? nil : "repair_action=\(uiReviewRepair.repairAction)",
                uiReviewRepair.repairFocus.isEmpty ? nil : "repair_focus=\(uiReviewRepair.repairFocus)"
            ]) ?? "(none)"
        }
        return normalized(primaryBlocker) ?? "(none)"
    }

    var recommendedActionsText: String? {
        let actions = recommendedActions
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !actions.isEmpty else { return nil }
        return actions.joined(separator: " | ")
    }

    var userVisibleRecommendedActionsText: String? {
        SupervisorGuidanceTextPresentation.actionsDisplayText(recommendedActions)
    }

    var nextSafeActionText: String {
        normalized(nextSafeAction) ?? "(none)"
    }

    var userVisibleNextSafeActionText: String {
        SupervisorGuidanceTextPresentation.actionDisplayText(nextSafeAction) ?? "(none)"
    }

    private func normalized(_ value: String?) -> String? {
        let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func firstNonEmpty(_ values: [String?]) -> String? {
        for value in values {
            if let normalized = normalized(value) {
                return normalized
            }
        }
        return nil
    }

    private func joinedSummary(_ parts: [String?]) -> String? {
        let normalizedParts = parts.compactMap { normalized($0) }
        guard !normalizedParts.isEmpty else { return nil }
        return normalizedParts.joined(separator: " · ")
    }
}

enum SupervisorGuidanceContractLinePresentation {
    static func contractLine(
        for contract: SupervisorGuidanceContractSummary
    ) -> String {
        if let uiReview = contract.uiReviewRepair {
            let repair = [
                uiReview.repairAction.isEmpty ? nil : "repair_action=\(uiReview.repairAction)",
                uiReview.repairFocus.isEmpty ? nil : "repair_focus=\(uiReview.repairFocus)"
            ]
            .compactMap { $0 }
            .joined(separator: " · ")
            guard !repair.isEmpty else {
                return "合同： \(contract.kindText)"
            }
            return "合同： \(contract.kindText) · \(repair)"
        }

        if !contract.primaryBlocker.isEmpty {
            return "合同： \(contract.kindText) · blocker=\(contract.primaryBlocker)"
        }

        let summary = contract.summaryText
        guard summary != "(none)" else {
            return "合同： \(contract.kindText)"
        }
        return "合同： \(contract.kindText) · \(summary)"
    }

    static func nextSafeActionLine(
        for contract: SupervisorGuidanceContractSummary
    ) -> String {
        nextSafeActionLine(
            nextSafeAction: contract.nextSafeAction,
            recommendedActions: contract.recommendedActions
        )
    }

    static func nextSafeActionLine(
        nextSafeAction: String,
        recommendedActions: [String] = []
    ) -> String {
        let visibleNextSafeAction = SupervisorGuidanceTextPresentation.actionDisplayText(nextSafeAction) ?? "(none)"
        var parts = ["安全下一步： \(visibleNextSafeAction)"]
        if let actions = SupervisorGuidanceTextPresentation.actionsDisplayText(recommendedActions) {
            parts.append("建议动作：\(actions)")
        }
        return parts.joined(separator: " · ")
    }

    private static func normalized(_ value: String?) -> String? {
        let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

enum SupervisorGuidanceContractResolver {
    static func resolve(
        guidance: SupervisorGuidanceInjectionRecord,
        reviewNote: SupervisorReviewNoteRecord? = nil
    ) -> SupervisorGuidanceContractSummary? {
        let (parsedSummary, fields) = parsedGuidanceText(guidance.guidanceText)

        if fields["source"]?.lowercased() == SupervisorGuidanceContractSummary.Kind.uiReviewRepair.rawValue {
            return uiReviewRepairContract(
                guidance: guidance,
                reviewNote: reviewNote,
                parsedSummary: parsedSummary,
                fields: fields
            )
        }

        return replanContract(
            guidance: guidance,
            reviewNote: reviewNote,
            parsedSummary: parsedSummary,
            fields: fields
        )
    }

    private static func uiReviewRepairContract(
        guidance: SupervisorGuidanceInjectionRecord,
        reviewNote: SupervisorReviewNoteRecord?,
        parsedSummary: String,
        fields: [String: String]
    ) -> SupervisorGuidanceContractSummary? {
        let repairAction = normalized(fields["repair_action"]) ?? ""
        let repairFocus = normalized(fields["repair_focus"]) ?? ""
        let nextSafeAction = firstNonEmpty([
            fields["next_safe_action"],
            inferredNextSafeAction(kind: .uiReviewRepair, reviewNote: reviewNote)
        ]) ?? ""
        let summary = firstNonEmpty([
            fields["summary"],
            parsedSummary,
            fields["ui_review_summary"],
            fields["skill_result_summary"]
        ]) ?? ""

        guard !summary.isEmpty || !repairAction.isEmpty || !repairFocus.isEmpty || !nextSafeAction.isEmpty else {
            return nil
        }

        return SupervisorGuidanceContractSummary(
            kind: .uiReviewRepair,
            trigger: firstNonEmpty([reviewNote?.trigger.displayName, fields["trigger"]]) ?? "",
            reviewLevel: firstNonEmpty([reviewNote?.reviewLevel.displayName, fields["review_level"]]) ?? "",
            verdict: firstNonEmpty([reviewNote?.verdict.displayName, fields["verdict"]]) ?? "",
            summary: summary,
            primaryBlocker: "",
            currentState: firstNonEmpty([reviewNote?.currentState, fields["current_state"]]) ?? "",
            nextStep: firstNonEmpty([reviewNote?.nextStep, fields["next_step"]]) ?? "",
            nextSafeAction: nextSafeAction,
            recommendedActions: recommendedActions(reviewNote: reviewNote, parsedFields: fields),
            workOrderRef: firstNonEmpty([reviewNote?.workOrderRef, guidance.workOrderRef, fields["work_order_ref"]]) ?? "",
            effectiveSupervisorTier: firstNonEmpty([
                reviewNote?.effectiveSupervisorTier?.displayName,
                guidance.effectiveSupervisorTier?.displayName,
                fields["effective_supervisor_tier"]
            ]) ?? "",
            effectiveWorkOrderDepth: firstNonEmpty([
                reviewNote?.effectiveWorkOrderDepth?.displayName,
                guidance.effectiveWorkOrderDepth?.displayName,
                fields["effective_work_order_depth"]
            ]) ?? "",
            uiReviewRepair: SupervisorGuidanceContractSummary.UIReviewRepairDetails(
                instruction: normalized(fields["instruction"]) ?? "",
                repairAction: repairAction,
                repairFocus: repairFocus,
                nextSafeAction: nextSafeAction,
                uiReviewRef: normalized(fields["ui_review_ref"]) ?? "",
                uiReviewReviewId: normalized(fields["ui_review_review_id"]) ?? "",
                uiReviewVerdict: normalized(fields["ui_review_verdict"]) ?? "",
                uiReviewIssueCodes: normalized(fields["ui_review_issue_codes"]) ?? "",
                uiReviewSummary: normalized(fields["ui_review_summary"]) ?? "",
                skillResultSummary: normalized(fields["skill_result_summary"]) ?? ""
            )
        )
    }

    private static func replanContract(
        guidance: SupervisorGuidanceInjectionRecord,
        reviewNote: SupervisorReviewNoteRecord?,
        parsedSummary: String,
        fields: [String: String]
    ) -> SupervisorGuidanceContractSummary? {
        let summary = firstNonEmpty([
            reviewNote?.summary,
            fields["summary"],
            parsedSummary
        ]) ?? ""
        let primaryBlocker = firstNonEmpty([
            reviewNote?.blocker,
            fields["primary_blocker"],
            fields["blocker"]
        ]) ?? ""
        let currentState = firstNonEmpty([
            reviewNote?.currentState,
            fields["current_state"]
        ]) ?? ""
        let nextStep = firstNonEmpty([
            reviewNote?.nextStep,
            fields["next_step"]
        ]) ?? ""
        let actions = recommendedActions(reviewNote: reviewNote, parsedFields: fields)
        let kind = resolvedKind(
            guidance: guidance,
            reviewNote: reviewNote,
            fields: fields,
            summary: summary,
            primaryBlocker: primaryBlocker
        )
        let nextSafeAction = firstNonEmpty([
            fields["next_safe_action"],
            inferredNextSafeAction(kind: kind, reviewNote: reviewNote)
        ]) ?? ""

        guard !summary.isEmpty || !primaryBlocker.isEmpty || !actions.isEmpty || !nextStep.isEmpty else {
            return nil
        }

        return SupervisorGuidanceContractSummary(
            kind: kind,
            trigger: firstNonEmpty([reviewNote?.trigger.displayName, fields["trigger"]]) ?? "",
            reviewLevel: firstNonEmpty([reviewNote?.reviewLevel.displayName, fields["review_level"]]) ?? "",
            verdict: firstNonEmpty([reviewNote?.verdict.displayName, fields["verdict"]]) ?? "",
            summary: summary,
            primaryBlocker: primaryBlocker,
            currentState: currentState,
            nextStep: nextStep,
            nextSafeAction: nextSafeAction,
            recommendedActions: actions,
            workOrderRef: firstNonEmpty([reviewNote?.workOrderRef, guidance.workOrderRef, fields["work_order_ref"]]) ?? "",
            effectiveSupervisorTier: firstNonEmpty([
                reviewNote?.effectiveSupervisorTier?.displayName,
                guidance.effectiveSupervisorTier?.displayName,
                fields["effective_supervisor_tier"]
            ]) ?? "",
            effectiveWorkOrderDepth: firstNonEmpty([
                reviewNote?.effectiveWorkOrderDepth?.displayName,
                guidance.effectiveWorkOrderDepth?.displayName,
                fields["effective_work_order_depth"]
            ]) ?? ""
        )
    }

    private static func parsedGuidanceText(
        _ text: String
    ) -> (summary: String, fields: [String: String]) {
        let normalized = SupervisorGuidanceTextPresentation.normalizedText(text)
        let lines = normalized
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let fields = SupervisorGuidanceTextPresentation.fields(normalized)
        let summary = firstNonEmpty([
            fields["summary"],
            lines.first(where: { !$0.contains("=") })
        ]) ?? ""

        return (summary, fields)
    }

    private static func recommendedActions(
        reviewNote: SupervisorReviewNoteRecord?,
        parsedFields: [String: String]
    ) -> [String] {
        if let reviewNote, !reviewNote.recommendedActions.isEmpty {
            return reviewNote.recommendedActions
        }
        let raw = firstNonEmpty([
            parsedFields["recommended_actions"],
            parsedFields["actions"]
        ]) ?? ""
        guard !raw.isEmpty else { return [] }
        return raw
            .split(separator: "|")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func resolvedKind(
        guidance: SupervisorGuidanceInjectionRecord,
        reviewNote: SupervisorReviewNoteRecord?,
        fields: [String: String],
        summary: String,
        primaryBlocker: String
    ) -> SupervisorGuidanceContractSummary.Kind {
        if let explicit = normalized(fields["contract_kind"]),
           let kind = kind(from: explicit) {
            return kind
        }

        let haystack = [
            guidance.guidanceText,
            summary,
            primaryBlocker,
            reviewNote?.summary ?? "",
            reviewNote?.blocker ?? "",
            reviewNote?.nextStep ?? "",
            reviewNote?.recommendedActions.joined(separator: " | ") ?? "",
            fields["summary"] ?? "",
            fields["blocker"] ?? ""
        ]
        .joined(separator: "\n")
        .lowercased()

        if haystack.contains("grant_required")
            || haystack.contains("grant_pending")
            || haystack.contains("pending grant")
            || haystack.contains("等待授权")
            || haystack.contains("需要授权")
            || haystack.contains("审批")
            || haystack.contains("authorize")
            || haystack.contains("approval") {
            return .grantResolution
        }
        if haystack.contains("awaiting instruction")
            || haystack.contains("awaiting_instruction")
            || haystack.contains("clarify")
            || haystack.contains("需要确认")
            || haystack.contains("等待指令") {
            return .awaitingInstruction
        }
        if haystack.contains("runtime_error")
            || haystack.contains("incident")
            || haystack.contains("failure")
            || haystack.contains("failed")
            || haystack.contains("blocked") {
            return .incidentRecovery
        }
        return .supervisorReplan
    }

    private static func kind(
        from raw: String
    ) -> SupervisorGuidanceContractSummary.Kind? {
        let normalized = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")
        return SupervisorGuidanceContractSummary.Kind(rawValue: normalized)
    }

    private static func inferredNextSafeAction(
        kind: SupervisorGuidanceContractSummary.Kind,
        reviewNote: SupervisorReviewNoteRecord?
    ) -> String {
        switch kind {
        case .uiReviewRepair:
            return "repair_before_execution"
        case .grantResolution:
            return "open_hub_grants"
        case .awaitingInstruction:
            return "clarify_with_user"
        case .incidentRecovery:
            return "inspect_incident_and_replan"
        case .supervisorReplan:
            if reviewNote?.deliveryMode == .stopSignal {
                return "replan_before_execution"
            }
            return "apply_supervisor_replan"
        }
    }

    private static func normalized(_ value: String?) -> String? {
        let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func firstNonEmpty(_ values: [String?]) -> String? {
        for value in values {
            if let normalized = normalized(value) {
                return normalized
            }
        }
        return nil
    }
}
