import Foundation

enum SupervisorProjectCapsuleCanonicalSync {
    static let schemaVersion = SupervisorProjectCapsule.schemaVersion
    static let keyPrefix = "xterminal.project.capsule"

    private static let maxScalarChars = 1_200
    private static let maxEvidenceRefs = 8
    private static let maxEvidenceRefChars = 240

    static func items(capsule: SupervisorProjectCapsule) -> [XTProjectCanonicalMemoryItem] {
        let pairs: [(String, String)] = [
            ("schema_version", normalizedScalar(capsule.schemaVersion)),
            ("project_id", normalizedScalar(capsule.projectId)),
            ("project_name", normalizedScalar(capsule.projectName)),
            ("project_state", normalizedScalar(capsule.projectState.rawValue)),
            ("goal", normalizedScalar(capsule.goal)),
            ("current_phase", normalizedScalar(capsule.currentPhase)),
            ("current_action", normalizedScalar(capsule.currentAction)),
            ("top_blocker", normalizedScalar(capsule.topBlocker)),
            ("next_step", normalizedScalar(capsule.nextStep)),
            ("memory_freshness", normalizedScalar(capsule.memoryFreshness.rawValue)),
            ("updated_at_ms", String(max(Int64(0), capsule.updatedAtMs))),
            ("status_digest", normalizedScalar(capsule.statusDigest)),
            ("evidence_refs", normalizedEvidenceRefs(capsule.evidenceRefs)),
            ("audit_ref", normalizedScalar(capsule.auditRef)),
            ("summary_json", summaryJSON(capsule: capsule))
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

    private static func normalizedEvidenceRefs(_ refs: [String]) -> String {
        let cleaned = refs
            .map { normalizedScalar(String($0.prefix(maxEvidenceRefChars))) }
            .filter { !$0.isEmpty }
        guard !cleaned.isEmpty else { return "" }
        return cleaned.prefix(maxEvidenceRefs).enumerated().map { index, item in
            "\(index + 1). \(item)"
        }.joined(separator: "\n")
    }

    private static func summaryJSON(capsule: SupervisorProjectCapsule) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(capsule),
              let text = String(data: data, encoding: .utf8) else {
            return ""
        }
        return text
    }
}
