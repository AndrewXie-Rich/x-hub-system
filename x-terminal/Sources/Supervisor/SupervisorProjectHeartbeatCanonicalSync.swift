import Foundation

struct SupervisorProjectHeartbeatCanonicalRecord: Codable, Equatable, Sendable {
    static let schemaVersion = "xt.project_heartbeat.v1"

    var schemaVersion: String
    var projectId: String
    var projectName: String
    var updatedAtMs: Int64
    var lastHeartbeatAtMs: Int64
    var statusDigest: String
    var currentStateSummary: String
    var nextStepSummary: String
    var blockerSummary: String
    var latestQualityBand: HeartbeatQualityBand?
    var latestQualityScore: Int?
    var weakReasons: [String]
    var openAnomalyTypes: [HeartbeatAnomalyType]
    var projectPhase: HeartbeatProjectPhase?
    var executionStatus: HeartbeatExecutionStatus?
    var riskTier: HeartbeatRiskTier?
    var cadence: SupervisorCadenceExplainability
    var nextReviewKind: SupervisorCadenceDimension?
    var nextReviewDueAtMs: Int64
    var nextReviewDue: Bool
    var digestExplainability: XTHeartbeatDigestExplainability
    var recoveryDecision: HeartbeatRecoveryDecision?
    var auditRef: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case projectId = "project_id"
        case projectName = "project_name"
        case updatedAtMs = "updated_at_ms"
        case lastHeartbeatAtMs = "last_heartbeat_at_ms"
        case statusDigest = "status_digest"
        case currentStateSummary = "current_state_summary"
        case nextStepSummary = "next_step_summary"
        case blockerSummary = "blocker_summary"
        case latestQualityBand = "latest_quality_band"
        case latestQualityScore = "latest_quality_score"
        case weakReasons = "weak_reasons"
        case openAnomalyTypes = "open_anomaly_types"
        case projectPhase = "project_phase"
        case executionStatus = "execution_status"
        case riskTier = "risk_tier"
        case cadence
        case nextReviewKind = "next_review_kind"
        case nextReviewDueAtMs = "next_review_due_at_ms"
        case nextReviewDue = "next_review_due"
        case digestExplainability = "digest_explainability"
        case recoveryDecision = "recovery_decision"
        case auditRef = "audit_ref"
    }
}

enum SupervisorProjectHeartbeatCanonicalSync {
    static let schemaVersion = SupervisorProjectHeartbeatCanonicalRecord.schemaVersion
    static let keyPrefix = "xterminal.project.heartbeat"

    private static let maxScalarChars = 1_200
    private static let maxListItems = 12
    private static let maxListItemChars = 220

    static func record(
        snapshot: XTProjectHeartbeatGovernanceDoctorSnapshot,
        generatedAtMs: Int64
    ) -> SupervisorProjectHeartbeatCanonicalRecord {
        let nextReview = nextReview(from: snapshot.cadence)
        return SupervisorProjectHeartbeatCanonicalRecord(
            schemaVersion: schemaVersion,
            projectId: snapshot.projectId,
            projectName: snapshot.projectName,
            updatedAtMs: max(0, generatedAtMs),
            lastHeartbeatAtMs: max(0, snapshot.lastHeartbeatAtMs),
            statusDigest: normalizedScalar(snapshot.statusDigest),
            currentStateSummary: normalizedScalar(snapshot.currentStateSummary),
            nextStepSummary: normalizedScalar(snapshot.nextStepSummary),
            blockerSummary: normalizedScalar(snapshot.blockerSummary),
            latestQualityBand: snapshot.latestQualityBand,
            latestQualityScore: snapshot.latestQualityScore,
            weakReasons: normalizedTokens(snapshot.weakReasons),
            openAnomalyTypes: snapshot.openAnomalyTypes,
            projectPhase: snapshot.projectPhase,
            executionStatus: snapshot.executionStatus,
            riskTier: snapshot.riskTier,
            cadence: snapshot.cadence,
            nextReviewKind: nextReview.kind,
            nextReviewDueAtMs: nextReview.atMs,
            nextReviewDue: nextReview.isDue,
            digestExplainability: snapshot.digestExplainability,
            recoveryDecision: snapshot.recoveryDecision,
            auditRef: "supervisor_project_heartbeat:\(snapshot.projectId):\(max(0, generatedAtMs))"
        )
    }

    static func items(record: SupervisorProjectHeartbeatCanonicalRecord) -> [XTProjectCanonicalMemoryItem] {
        let pairs: [(String, String)] = [
            ("schema_version", normalizedScalar(record.schemaVersion)),
            ("project_id", normalizedScalar(record.projectId)),
            ("project_name", normalizedScalar(record.projectName)),
            ("updated_at_ms", String(max(Int64(0), record.updatedAtMs))),
            ("last_heartbeat_at_ms", String(max(Int64(0), record.lastHeartbeatAtMs))),
            ("status_digest", normalizedScalar(record.statusDigest)),
            ("current_state_summary", normalizedScalar(record.currentStateSummary)),
            ("next_step_summary", normalizedScalar(record.nextStepSummary)),
            ("blocker_summary", normalizedScalar(record.blockerSummary)),
            ("latest_quality_band", normalizedScalar(record.latestQualityBand?.rawValue ?? "")),
            ("latest_quality_score", record.latestQualityScore.map(String.init) ?? ""),
            ("weak_reasons", normalizedList(record.weakReasons)),
            ("open_anomaly_types", normalizedList(record.openAnomalyTypes.map(\.rawValue))),
            ("project_phase", normalizedScalar(record.projectPhase?.rawValue ?? "")),
            ("execution_status", normalizedScalar(record.executionStatus?.rawValue ?? "")),
            ("risk_tier", normalizedScalar(record.riskTier?.rawValue ?? "")),
            ("progress_heartbeat_effective_seconds", String(max(0, record.cadence.progressHeartbeat.effectiveSeconds))),
            ("review_pulse_effective_seconds", String(max(0, record.cadence.reviewPulse.effectiveSeconds))),
            ("brainstorm_review_effective_seconds", String(max(0, record.cadence.brainstormReview.effectiveSeconds))),
            ("next_review_kind", normalizedScalar(record.nextReviewKind?.rawValue ?? "")),
            ("next_review_due_at_ms", String(max(Int64(0), record.nextReviewDueAtMs))),
            ("next_review_due", String(record.nextReviewDue)),
            ("digest_visibility", normalizedScalar(record.digestExplainability.visibility.rawValue)),
            ("digest_reason_codes", normalizedList(record.digestExplainability.reasonCodes)),
            ("digest_what_changed_text", normalizedScalar(record.digestExplainability.whatChangedText)),
            ("digest_why_important_text", normalizedScalar(record.digestExplainability.whyImportantText)),
            ("digest_system_next_step_text", normalizedScalar(record.digestExplainability.systemNextStepText)),
            ("recovery_action", normalizedScalar(record.recoveryDecision?.action.rawValue ?? "")),
            ("recovery_urgency", normalizedScalar(record.recoveryDecision?.urgency.rawValue ?? "")),
            ("recovery_reason_code", normalizedScalar(record.recoveryDecision?.reasonCode ?? "")),
            ("recovery_summary", normalizedScalar(record.recoveryDecision?.summary ?? "")),
            ("audit_ref", normalizedScalar(record.auditRef)),
            ("summary_json", summaryJSON(record))
        ]

        return pairs.compactMap { suffix, rawValue in
            let key = "\(keyPrefix).\(suffix)"
            let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, !value.isEmpty else { return nil }
            return XTProjectCanonicalMemoryItem(key: key, value: value)
        }
    }

    static func roleTurnMessage(
        record: SupervisorProjectHeartbeatCanonicalRecord
    ) -> XTProjectConversationMirrorMessage? {
        let projectId = normalizedScalar(record.projectId)
        guard !projectId.isEmpty else { return nil }
        let createdAtMs = max(record.updatedAtMs, record.lastHeartbeatAtMs)
        let createdAt = Double(max(Int64(0), createdAtMs)) / 1000.0
        let threadKey = XTProjectConversationMirror.projectThreadKey(projectId: projectId)
        return XTProjectConversationMirror.roleEventMessage(
            role: "system",
            projectId: projectId,
            threadKey: threadKey,
            content: roleTurnContent(record: record),
            createdAt: createdAt,
            sourceRole: "hub",
            targetRole: "all",
            dispatchKind: "heartbeat",
            status: "observed",
            dispatchId: roleTurnDispatchID(record: record, createdAtMs: createdAtMs),
            evidenceRefs: ["heartbeat_projection:\(projectId):\(max(Int64(0), createdAtMs))"],
            auditRefs: [record.auditRef],
            tags: ["xt_heartbeat_governance", "heartbeat_memory_projection"]
        )
    }

    private static func nextReview(
        from cadence: SupervisorCadenceExplainability
    ) -> (kind: SupervisorCadenceDimension?, atMs: Int64, isDue: Bool) {
        let candidates = [cadence.reviewPulse, cadence.brainstormReview]
            .filter { $0.effectiveSeconds > 0 }
        guard let next = candidates.min(by: compareDue(lhs:rhs:)) else {
            return (nil, 0, false)
        }
        return (next.dimension, max(0, next.nextDueAtMs), next.isDue)
    }

    private static func compareDue(
        lhs: SupervisorCadenceDimensionExplainability,
        rhs: SupervisorCadenceDimensionExplainability
    ) -> Bool {
        if lhs.isDue != rhs.isDue {
            return lhs.isDue && !rhs.isDue
        }
        if lhs.nextDueAtMs != rhs.nextDueAtMs {
            return lhs.nextDueAtMs < rhs.nextDueAtMs
        }
        return lhs.dimension.rawValue < rhs.dimension.rawValue
    }

    private static func normalizedList(_ rawItems: [String]) -> String {
        let cleaned = normalizedTokens(rawItems)
        guard !cleaned.isEmpty else { return "" }
        return cleaned
            .prefix(maxListItems)
            .enumerated()
            .map { index, item in
                "\(index + 1). \(item)"
            }
            .joined(separator: "\n")
    }

    private static func normalizedTokens(_ rawItems: [String]) -> [String] {
        rawItems
            .map { normalizedScalar($0, maxChars: maxListItemChars) }
            .filter { !$0.isEmpty }
    }

    private static func normalizedScalar(
        _ raw: String,
        maxChars: Int = maxScalarChars
    ) -> String {
        let trimmed = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        guard trimmed.count > maxChars else { return trimmed }
        let end = trimmed.index(trimmed.startIndex, offsetBy: maxChars)
        return String(trimmed[..<end]) + "..."
    }

    private static func summaryJSON(_ record: SupervisorProjectHeartbeatCanonicalRecord) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(record),
              let text = String(data: data, encoding: .utf8) else {
            return ""
        }
        return text
    }

    private static func roleTurnDispatchID(
        record: SupervisorProjectHeartbeatCanonicalRecord,
        createdAtMs: Int64
    ) -> String {
        AXChatMessageLineageMetadata.makeDispatchId(
            projectId: "heartbeat_\(record.projectId)",
            createdAtMs: max(0, createdAtMs)
        )
    }

    private static func roleTurnContent(record: SupervisorProjectHeartbeatCanonicalRecord) -> String {
        var lines = [
            "Heartbeat governance projection observed.",
            "project_id=\(normalizedScalar(record.projectId))",
            "last_heartbeat_at_ms=\(max(Int64(0), record.lastHeartbeatAtMs))",
            "updated_at_ms=\(max(Int64(0), record.updatedAtMs))"
        ]
        appendLine("status_digest", record.statusDigest, to: &lines)
        appendLine("current_state", record.currentStateSummary, to: &lines)
        appendLine("next_step", record.nextStepSummary, to: &lines)
        appendLine("blocker", record.blockerSummary, to: &lines)
        appendLine("latest_quality_band", record.latestQualityBand?.rawValue ?? "", to: &lines)
        if let score = record.latestQualityScore {
            lines.append("latest_quality_score=\(score)")
        }
        appendLine("open_anomaly_types", record.openAnomalyTypes.map(\.rawValue).joined(separator: ","), to: &lines)
        appendLine("next_review_kind", record.nextReviewKind?.rawValue ?? "", to: &lines)
        lines.append("next_review_due=\(record.nextReviewDue ? "true" : "false")")
        appendLine("recovery_action", record.recoveryDecision?.action.rawValue ?? "", to: &lines)
        appendLine("recovery_reason_code", record.recoveryDecision?.reasonCode ?? "", to: &lines)
        appendLine("audit_ref", record.auditRef, to: &lines)
        return lines.joined(separator: "\n")
    }

    private static func appendLine(_ key: String, _ rawValue: String, to lines: inout [String]) {
        let value = normalizedScalar(rawValue)
        guard !value.isEmpty else { return }
        lines.append("\(key)=\(value)")
    }
}
