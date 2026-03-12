import Foundation

enum SupervisorSkillRiskLevel: String, Codable, CaseIterable, Sendable {
    case low
    case medium
    case high
    case critical
}

struct SupervisorSkillRegistryItem: Identifiable, Codable, Equatable, Sendable {
    var skillId: String
    var displayName: String
    var description: String
    var inputSchemaRef: String
    var outputSchemaRef: String
    var sideEffectClass: String
    var riskLevel: SupervisorSkillRiskLevel
    var requiresGrant: Bool
    var policyScope: String
    var timeoutMs: Int
    var maxRetries: Int
    var available: Bool

    var id: String { skillId }

    enum CodingKeys: String, CodingKey {
        case skillId = "skill_id"
        case displayName = "display_name"
        case description
        case inputSchemaRef = "input_schema_ref"
        case outputSchemaRef = "output_schema_ref"
        case sideEffectClass = "side_effect_class"
        case riskLevel = "risk_level"
        case requiresGrant = "requires_grant"
        case policyScope = "policy_scope"
        case timeoutMs = "timeout_ms"
        case maxRetries = "max_retries"
        case available
    }
}

struct SupervisorSkillRegistrySnapshot: Codable, Equatable, Sendable {
    static let currentSchemaVersion = "xt.supervisor_skill_registry_view.v1"

    var schemaVersion: String
    var projectId: String
    var projectName: String?
    var updatedAtMs: Int64
    var memorySource: String
    var items: [SupervisorSkillRegistryItem]
    var auditRef: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case projectId = "project_id"
        case projectName = "project_name"
        case updatedAtMs = "updated_at_ms"
        case memorySource = "memory_source"
        case items
        case auditRef = "audit_ref"
    }
}

extension SupervisorSkillRegistrySnapshot {
    var statusLine: String {
        let projectLabel = (projectName ?? projectId).trimmingCharacters(in: .whitespacesAndNewlines)
        let sourceLabel = memorySource.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "unknown" : memorySource
        return "skills=\(items.count) · project=\(projectLabel) · source=\(sourceLabel)"
    }

    func memorySummary(maxItems: Int = 6, maxChars: Int = 1_000) -> String {
        let projectLabel = (projectName ?? projectId).trimmingCharacters(in: .whitespacesAndNewlines)
        var lines = ["project=\(projectLabel) id=\(projectId)"]
        for (index, item) in items.prefix(max(1, maxItems)).enumerated() {
            let grant = item.requiresGrant ? "grant=yes" : "grant=no"
            let headline = "\(index + 1). \(item.skillId) | risk=\(item.riskLevel.rawValue) | \(grant) | scope=\(item.policyScope) | timeout_ms=\(item.timeoutMs) | retries=\(item.maxRetries) | side_effect=\(item.sideEffectClass)"
            lines.append(headline)
            let description = item.description.trimmingCharacters(in: .whitespacesAndNewlines)
            if !description.isEmpty {
                lines.append("   \(description)")
            }
        }

        let joined = lines.joined(separator: "\n")
        guard joined.count > maxChars else { return joined }
        let end = joined.index(joined.startIndex, offsetBy: maxChars)
        return String(joined[..<end]) + "..."
    }
}
