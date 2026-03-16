import Foundation

struct XTProjectCanonicalMemoryItem: Codable, Equatable, Sendable {
    var key: String
    var value: String
}

enum XTProjectCanonicalMemorySync {
    static let schemaVersion = "xt.project_canonical_memory.v1"
    static let keyPrefix = "xterminal.project.memory"

    private static let maxScalarChars = 2_000
    private static let maxListItems = 16
    private static let maxListItemChars = 400

    static func items(memory: AXMemory, preferredProjectName: String? = nil) -> [XTProjectCanonicalMemoryItem] {
        let projectName = resolvedProjectName(
            memory.projectName,
            preferredProjectName: preferredProjectName
        )
        let pairs: [(String, String)] = [
            ("schema_version", schemaVersion),
            ("project_name", normalizedScalar(projectName, maxChars: 240)),
            ("project_root", normalizedScalar(memory.projectRoot, maxChars: 1_200)),
            ("updated_at", isoTimestamp(memory.updatedAt)),
            ("goal", normalizedScalar(memory.goal, maxChars: maxScalarChars)),
            ("requirements", normalizedList(memory.requirements)),
            ("current_state", normalizedList(memory.currentState)),
            ("decisions", normalizedList(memory.decisions)),
            ("next_steps", normalizedList(memory.nextSteps)),
            ("open_questions", normalizedList(memory.openQuestions)),
            ("risks", normalizedList(memory.risks)),
            ("recommendations", normalizedList(memory.recommendations)),
            ("summary_json", summaryJSON(memory: memory, projectName: projectName))
        ]

        return pairs.compactMap { suffix, rawValue in
            let key = "\(keyPrefix).\(suffix)"
            let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, !value.isEmpty else { return nil }
            return XTProjectCanonicalMemoryItem(key: key, value: value)
        }
    }

    private static func normalizedScalar(_ raw: String, maxChars: Int) -> String {
        let trimmed = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        guard trimmed.count > maxChars else { return trimmed }
        let end = trimmed.index(trimmed.startIndex, offsetBy: maxChars)
        return String(trimmed[..<end]) + "..."
    }

    private static func normalizedList(_ rawItems: [String]) -> String {
        let cleaned = rawItems
            .map { normalizedScalar($0, maxChars: maxListItemChars) }
            .filter { !$0.isEmpty }
        guard !cleaned.isEmpty else { return "" }

        return cleaned
            .prefix(maxListItems)
            .enumerated()
            .map { index, item in
                "\(index + 1). \(item)"
            }
            .joined(separator: "\n")
    }

    private static func resolvedProjectName(
        _ memoryProjectName: String,
        preferredProjectName: String?
    ) -> String {
        let preferred = normalizedScalar(preferredProjectName ?? "", maxChars: 240)
        if !preferred.isEmpty {
            return preferred
        }
        return normalizedScalar(memoryProjectName, maxChars: 240)
    }

    private static func summaryJSON(memory: AXMemory, projectName: String) -> String {
        struct Summary: Codable {
            var schemaVersion: String
            var projectName: String
            var projectRoot: String
            var goal: String
            var requirements: [String]
            var currentState: [String]
            var decisions: [String]
            var nextSteps: [String]
            var openQuestions: [String]
            var risks: [String]
            var recommendations: [String]
            var updatedAt: Double

            enum CodingKeys: String, CodingKey {
                case schemaVersion = "schema_version"
                case projectName = "project_name"
                case projectRoot = "project_root"
                case goal
                case requirements
                case currentState = "current_state"
                case decisions
                case nextSteps = "next_steps"
                case openQuestions = "open_questions"
                case risks
                case recommendations
                case updatedAt = "updated_at"
            }
        }

        let payload = Summary(
            schemaVersion: schemaVersion,
            projectName: projectName,
            projectRoot: memory.projectRoot,
            goal: memory.goal,
            requirements: memory.requirements,
            currentState: memory.currentState,
            decisions: memory.decisions,
            nextSteps: memory.nextSteps,
            openQuestions: memory.openQuestions,
            risks: memory.risks,
            recommendations: memory.recommendations,
            updatedAt: memory.updatedAt
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(payload),
              let text = String(data: data, encoding: .utf8) else {
            return ""
        }
        return text
    }

    private static func isoTimestamp(_ ts: Double) -> String {
        guard ts > 0 else { return "" }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date(timeIntervalSince1970: ts))
    }
}
