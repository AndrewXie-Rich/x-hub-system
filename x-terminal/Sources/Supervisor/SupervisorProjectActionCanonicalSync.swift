import Foundation

struct SupervisorProjectActionCanonicalRecord: Codable, Equatable, Sendable {
    var schemaVersion: String
    var eventId: String
    var projectId: String
    var projectName: String
    var eventType: String
    var severity: String
    var actionTitle: String
    var actionSummary: String
    var whyItMatters: String
    var nextAction: String
    var occurredAtMs: Int64
    var deliveryChannel: String
    var deliveryStatus: String
    var jurisdictionRole: String?
    var grantedScope: String?
    var auditRef: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case eventId = "event_id"
        case projectId = "project_id"
        case projectName = "project_name"
        case eventType = "event_type"
        case severity
        case actionTitle = "action_title"
        case actionSummary = "action_summary"
        case whyItMatters = "why_it_matters"
        case nextAction = "next_action"
        case occurredAtMs = "occurred_at_ms"
        case deliveryChannel = "delivery_channel"
        case deliveryStatus = "delivery_status"
        case jurisdictionRole = "jurisdiction_role"
        case grantedScope = "granted_scope"
        case auditRef = "audit_ref"
    }
}

enum SupervisorProjectActionCanonicalSync {
    static let schemaVersion = "xt.project_action_event.v1"
    static let keyPrefix = "xterminal.project.action"

    private static let maxScalarChars = 1_200

    static func items(record: SupervisorProjectActionCanonicalRecord) -> [XTProjectCanonicalMemoryItem] {
        let pairs: [(String, String)] = [
            ("schema_version", normalizedScalar(record.schemaVersion)),
            ("event_id", normalizedScalar(record.eventId)),
            ("project_id", normalizedScalar(record.projectId)),
            ("project_name", normalizedScalar(record.projectName)),
            ("event_type", normalizedScalar(record.eventType)),
            ("severity", normalizedScalar(record.severity)),
            ("action_title", normalizedScalar(record.actionTitle)),
            ("action_summary", normalizedScalar(record.actionSummary)),
            ("why_it_matters", normalizedScalar(record.whyItMatters)),
            ("next_action", normalizedScalar(record.nextAction)),
            ("occurred_at_ms", String(max(Int64(0), record.occurredAtMs))),
            ("delivery_channel", normalizedScalar(record.deliveryChannel)),
            ("delivery_status", normalizedScalar(record.deliveryStatus)),
            ("jurisdiction_role", normalizedScalar(record.jurisdictionRole ?? "")),
            ("granted_scope", normalizedScalar(record.grantedScope ?? "")),
            ("audit_ref", normalizedScalar(record.auditRef)),
            ("summary_json", summaryJSON(record: record))
        ]

        return pairs.compactMap { suffix, rawValue in
            let key = "\(keyPrefix).\(suffix)"
            let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, !value.isEmpty else { return nil }
            return XTProjectCanonicalMemoryItem(key: key, value: value)
        }
    }

    private static func normalizedScalar(_ raw: String) -> String {
        let trimmed = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        guard trimmed.count > maxScalarChars else { return trimmed }
        let end = trimmed.index(trimmed.startIndex, offsetBy: maxScalarChars)
        return String(trimmed[..<end]) + "..."
    }

    private static func summaryJSON(record: SupervisorProjectActionCanonicalRecord) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(record),
              let text = String(data: data, encoding: .utf8) else {
            return ""
        }
        return text
    }
}
