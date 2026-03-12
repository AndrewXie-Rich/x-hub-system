import Foundation
import CryptoKit

struct SupervisorPortfolioSnapshotCanonicalRecord: Codable, Equatable, Sendable {
    static let schemaVersion = "xt.supervisor_portfolio_snapshot.v1"

    var schemaVersion: String
    var supervisorId: String
    var updatedAtMs: Int64
    var projectCounts: SupervisorPortfolioProjectCounts
    var criticalQueue: [SupervisorPortfolioCriticalQueueItem]
    var projects: [SupervisorPortfolioProjectCard]
    var statusLine: String
    var auditRef: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case supervisorId = "supervisor_id"
        case updatedAtMs = "updated_at_ms"
        case projectCounts = "project_counts"
        case criticalQueue = "critical_queue"
        case projects
        case statusLine = "status_line"
        case auditRef = "audit_ref"
    }
}

enum SupervisorPortfolioSnapshotCanonicalSync {
    static let schemaVersion = SupervisorPortfolioSnapshotCanonicalRecord.schemaVersion
    static let keyPrefix = "xterminal.supervisor.portfolio"

    private static let maxScalarChars = 1_200
    private static let maxDigestLines = 8
    private static let maxDigestChars = 240

    static func record(
        snapshot: SupervisorPortfolioSnapshot,
        supervisorId rawSupervisorId: String
    ) -> SupervisorPortfolioSnapshotCanonicalRecord {
        let supervisorId = normalizedSupervisorId(rawSupervisorId)
        let seed = seedRecord(snapshot: snapshot, supervisorId: supervisorId)
        let fingerprintValue = fingerprint(record: seed)
        let auditRef = "supervisor_portfolio_snapshot:\(normalizedToken(supervisorId)):\(String(fingerprintValue.prefix(16)))"

        return SupervisorPortfolioSnapshotCanonicalRecord(
            schemaVersion: schemaVersion,
            supervisorId: supervisorId,
            updatedAtMs: max(0, Int64((snapshot.updatedAt * 1000.0).rounded())),
            projectCounts: snapshot.counts,
            criticalQueue: snapshot.criticalQueue,
            projects: snapshot.projects,
            statusLine: normalizedScalar(snapshot.statusLine),
            auditRef: auditRef
        )
    }

    static func fingerprint(
        snapshot: SupervisorPortfolioSnapshot,
        supervisorId: String
    ) -> String {
        fingerprint(record: seedRecord(snapshot: snapshot, supervisorId: normalizedSupervisorId(supervisorId)))
    }

    static func items(
        snapshot: SupervisorPortfolioSnapshot,
        supervisorId: String
    ) -> [XTProjectCanonicalMemoryItem] {
        items(record: record(snapshot: snapshot, supervisorId: supervisorId))
    }

    static func items(record: SupervisorPortfolioSnapshotCanonicalRecord) -> [XTProjectCanonicalMemoryItem] {
        let projectCountTotal = max(
            0,
            record.projectCounts.active
                + record.projectCounts.blocked
                + record.projectCounts.awaitingAuthorization
                + record.projectCounts.completed
                + record.projectCounts.idle
        )

        let pairs: [(String, String)] = [
            ("schema_version", normalizedScalar(record.schemaVersion)),
            ("supervisor_id", normalizedScalar(record.supervisorId)),
            ("updated_at_ms", String(max(Int64(0), record.updatedAtMs))),
            ("status_line", normalizedScalar(record.statusLine)),
            ("project_count_total", String(projectCountTotal)),
            ("project_counts.active", String(max(0, record.projectCounts.active))),
            ("project_counts.blocked", String(max(0, record.projectCounts.blocked))),
            ("project_counts.awaiting_authorization", String(max(0, record.projectCounts.awaitingAuthorization))),
            ("project_counts.completed", String(max(0, record.projectCounts.completed))),
            ("project_counts.idle", String(max(0, record.projectCounts.idle))),
            ("project_counts_json", jsonString(record.projectCounts)),
            ("critical_queue_count", String(max(0, record.criticalQueue.count))),
            ("critical_queue_digest", criticalQueueDigest(record.criticalQueue)),
            ("projects_digest", projectsDigest(record.projects)),
            ("audit_ref", normalizedScalar(record.auditRef)),
            ("summary_json", jsonString(record))
        ]

        return pairs.compactMap { suffix, rawValue in
            let key = "\(keyPrefix).\(suffix)"
            let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, !value.isEmpty else { return nil }
            return XTProjectCanonicalMemoryItem(key: key, value: value)
        }
    }

    private static func seedRecord(
        snapshot: SupervisorPortfolioSnapshot,
        supervisorId: String
    ) -> SupervisorPortfolioSnapshotCanonicalRecord {
        SupervisorPortfolioSnapshotCanonicalRecord(
            schemaVersion: schemaVersion,
            supervisorId: supervisorId,
            updatedAtMs: 0,
            projectCounts: snapshot.counts,
            criticalQueue: snapshot.criticalQueue,
            projects: snapshot.projects,
            statusLine: normalizedScalar(snapshot.statusLine),
            auditRef: ""
        )
    }

    private static func criticalQueueDigest(_ items: [SupervisorPortfolioCriticalQueueItem]) -> String {
        items.prefix(maxDigestLines).map { item in
            let reason = normalizedScalar(String(item.reason.prefix(maxDigestChars)))
            let next = normalizedScalar(String(item.nextAction.prefix(maxDigestChars)))
            return "\(item.projectId) | \(reason) | next=\(next)"
        }.joined(separator: "\n")
    }

    private static func projectsDigest(_ items: [SupervisorPortfolioProjectCard]) -> String {
        items.prefix(maxDigestLines).map { item in
            let action = normalizedScalar(String(item.currentAction.prefix(maxDigestChars)))
            let blocker = normalizedScalar(String(item.topBlocker.prefix(maxDigestChars)))
            let next = normalizedScalar(String(item.nextStep.prefix(maxDigestChars)))
            return "\(item.projectId) | \(item.projectState.rawValue) | action=\(action) | blocker=\(blocker) | next=\(next)"
        }.joined(separator: "\n")
    }

    private static func jsonString<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(value),
              let text = String(data: data, encoding: .utf8) else {
            return ""
        }
        return text
    }

    private static func fingerprint(record: SupervisorPortfolioSnapshotCanonicalRecord) -> String {
        let text = jsonString(record)
        guard let data = text.data(using: .utf8) else { return "" }
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func normalizedSupervisorId(_ raw: String) -> String {
        let trimmed = normalizedScalar(raw)
        return trimmed.isEmpty ? "supervisor-main" : trimmed
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

    private static func normalizedToken(_ text: String) -> String {
        let folded = text.lowercased()
        let scalars = folded.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
        let token = String(String.UnicodeScalarView(scalars))
        return token.isEmpty ? "supervisormain" : token
    }
}
