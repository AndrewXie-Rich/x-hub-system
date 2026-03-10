import Foundation

enum DeliveryParticipationMode: String, Codable, Equatable, CaseIterable {
    case zeroTouch = "zero_touch"
    case criticalTouch = "critical_touch"
    case guidedTouch = "guided_touch"

    init(policyToken: String) {
        switch policyToken.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "hands_off", "zero_touch":
            self = .zeroTouch
        case "critical_only", "critical_touch":
            self = .criticalTouch
        default:
            self = .guidedTouch
        }
    }
}

enum DeliveryTemplateKind: String, Codable, Equatable {
    case silent
    case summary
    case full
}

enum DeliveryNotificationEventKind: String, Codable, Equatable {
    case completion
    case critical
    case nonCritical
}

enum DeliveryNotificationStatus: String, Codable, Equatable {
    case sent
    case blocked
    case suppressed
}

struct DeliveryNotificationPayload: Codable, Equatable {
    let taskID: String
    let eventKind: DeliveryNotificationEventKind
    let deliverySummary: String
    let riskSummary: [String]
    let evidenceRefs: [String]
    let rollbackPoint: String
    let nextStepSuggestion: String

    enum CodingKeys: String, CodingKey {
        case taskID = "task_id"
        case eventKind = "event_kind"
        case deliverySummary = "delivery_summary"
        case riskSummary = "risk_summary"
        case evidenceRefs = "evidence_refs"
        case rollbackPoint = "rollback_point"
        case nextStepSuggestion = "next_step_suggestion"
    }
}

struct DeliveryNotificationAudit: Codable, Equatable {
    let schemaVersion: String
    let generatedAtMs: Int64
    let taskID: String
    let participationMode: DeliveryParticipationMode
    let templateKind: DeliveryTemplateKind
    let eventKind: DeliveryNotificationEventKind
    let status: DeliveryNotificationStatus
    let deliveryNotificationCompleteness: Double
    let evidenceLinkIntegrity: Bool
    let rollbackPointIncluded: Bool
    let nextStepSuggestionIncluded: Bool
    let evidenceLinkCount: Int
    let includedSections: [String]
    let blockedReason: String?

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case generatedAtMs = "generated_at_ms"
        case taskID = "task_id"
        case participationMode = "participation_mode"
        case templateKind = "template_kind"
        case eventKind = "event_kind"
        case status
        case deliveryNotificationCompleteness = "delivery_notification_completeness"
        case evidenceLinkIntegrity = "evidence_link_integrity"
        case rollbackPointIncluded = "rollback_point_included"
        case nextStepSuggestionIncluded = "next_step_suggestion_included"
        case evidenceLinkCount = "evidence_link_count"
        case includedSections = "included_sections"
        case blockedReason = "blocked_reason"
    }
}

struct DeliveryNotificationAttempt: Codable, Equatable {
    let schemaVersion: String
    let generatedAtMs: Int64
    let taskID: String
    let participationMode: DeliveryParticipationMode
    let templateKind: DeliveryTemplateKind
    let eventKind: DeliveryNotificationEventKind
    let status: DeliveryNotificationStatus
    let subject: String
    let bodySections: [String]
    let audit: DeliveryNotificationAudit

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case generatedAtMs = "generated_at_ms"
        case taskID = "task_id"
        case participationMode = "participation_mode"
        case templateKind = "template_kind"
        case eventKind = "event_kind"
        case status
        case subject
        case bodySections = "body_sections"
        case audit
    }
}

/// XT-W3-19: emit auditable delivery notifications with evidence-link guardrails.
final class DeliveryNotifier {
    private let schemaVersion = "xterminal.delivery_notifier_attempt.v1"
    private let auditSchemaVersion = "xterminal.delivery_notifier_audit.v1"

    func prepareNotification(
        mode: DeliveryParticipationMode,
        payload: DeliveryNotificationPayload,
        now: Date = Date()
    ) -> DeliveryNotificationAttempt {
        let nowMs = Int64((now.timeIntervalSince1970 * 1000.0).rounded())
        let template = templateKind(for: mode)
        let evidenceLinks = payload.evidenceRefs.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let evidenceLinkIntegrity = !evidenceLinks.isEmpty && evidenceLinks.allSatisfy { !$0.isEmpty }
        let rollbackPointIncluded = !payload.rollbackPoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let nextStepIncluded = !payload.nextStepSuggestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        if payload.eventKind == .nonCritical && mode == .zeroTouch {
            let audit = DeliveryNotificationAudit(
                schemaVersion: auditSchemaVersion,
                generatedAtMs: nowMs,
                taskID: payload.taskID,
                participationMode: mode,
                templateKind: template,
                eventKind: payload.eventKind,
                status: .suppressed,
                deliveryNotificationCompleteness: 0,
                evidenceLinkIntegrity: evidenceLinkIntegrity,
                rollbackPointIncluded: rollbackPointIncluded,
                nextStepSuggestionIncluded: nextStepIncluded,
                evidenceLinkCount: evidenceLinks.count,
                includedSections: [],
                blockedReason: "zero_touch_suppresses_noncritical_delivery_notifications"
            )
            return DeliveryNotificationAttempt(
                schemaVersion: schemaVersion,
                generatedAtMs: nowMs,
                taskID: payload.taskID,
                participationMode: mode,
                templateKind: template,
                eventKind: payload.eventKind,
                status: .suppressed,
                subject: "suppressed delivery notification",
                bodySections: [],
                audit: audit
            )
        }

        if payload.eventKind == .completion && !evidenceLinkIntegrity {
            let audit = DeliveryNotificationAudit(
                schemaVersion: auditSchemaVersion,
                generatedAtMs: nowMs,
                taskID: payload.taskID,
                participationMode: mode,
                templateKind: template,
                eventKind: payload.eventKind,
                status: .blocked,
                deliveryNotificationCompleteness: 0,
                evidenceLinkIntegrity: false,
                rollbackPointIncluded: rollbackPointIncluded,
                nextStepSuggestionIncluded: nextStepIncluded,
                evidenceLinkCount: evidenceLinks.count,
                includedSections: [],
                blockedReason: "missing_evidence_links_for_completion_notification"
            )
            return DeliveryNotificationAttempt(
                schemaVersion: schemaVersion,
                generatedAtMs: nowMs,
                taskID: payload.taskID,
                participationMode: mode,
                templateKind: template,
                eventKind: payload.eventKind,
                status: .blocked,
                subject: "blocked completion notification",
                bodySections: [],
                audit: audit
            )
        }

        let sections = buildBodySections(template: template, payload: payload)
        let completenessChecks = [
            !payload.deliverySummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            !payload.riskSummary.isEmpty,
            evidenceLinkIntegrity,
            rollbackPointIncluded,
            nextStepIncluded
        ]
        let completeness = Double(completenessChecks.filter { $0 }.count) / Double(completenessChecks.count)

        let audit = DeliveryNotificationAudit(
            schemaVersion: auditSchemaVersion,
            generatedAtMs: nowMs,
            taskID: payload.taskID,
            participationMode: mode,
            templateKind: template,
            eventKind: payload.eventKind,
            status: .sent,
            deliveryNotificationCompleteness: completeness,
            evidenceLinkIntegrity: evidenceLinkIntegrity,
            rollbackPointIncluded: rollbackPointIncluded,
            nextStepSuggestionIncluded: nextStepIncluded,
            evidenceLinkCount: evidenceLinks.count,
            includedSections: sections,
            blockedReason: nil
        )
        return DeliveryNotificationAttempt(
            schemaVersion: schemaVersion,
            generatedAtMs: nowMs,
            taskID: payload.taskID,
            participationMode: mode,
            templateKind: template,
            eventKind: payload.eventKind,
            status: .sent,
            subject: subject(for: template, taskID: payload.taskID),
            bodySections: sections,
            audit: audit
        )
    }

    private func templateKind(for mode: DeliveryParticipationMode) -> DeliveryTemplateKind {
        switch mode {
        case .zeroTouch:
            return .silent
        case .criticalTouch:
            return .summary
        case .guidedTouch:
            return .full
        }
    }

    private func subject(for template: DeliveryTemplateKind, taskID: String) -> String {
        switch template {
        case .silent:
            return "delivery ready: \(taskID)"
        case .summary:
            return "delivery summary: \(taskID)"
        case .full:
            return "delivery complete with evidence: \(taskID)"
        }
    }

    private func buildBodySections(template: DeliveryTemplateKind, payload: DeliveryNotificationPayload) -> [String] {
        switch template {
        case .silent:
            return [
                "result",
                "evidence_links",
                "rollback_point",
                "next_step"
            ]
        case .summary:
            return [
                "result",
                "risk_summary",
                "evidence_links",
                "rollback_point",
                "next_step"
            ]
        case .full:
            return [
                "result",
                "risk_summary",
                "evidence_links",
                "rollback_point",
                "next_step",
                "participation_policy",
                "audit_trail"
            ]
        }
    }
}
