import Foundation

struct AXRouteRepairLogEvent: Codable, Equatable, Identifiable, Sendable {
    static let currentSchemaVersion = "xt.route_repair_log_event.v1"

    var schemaVersion: String
    var createdAt: Double
    var projectId: String
    var projectDisplayName: String
    var actionId: String
    var outcome: String
    var requestedModelId: String
    var actualModelId: String
    var fallbackReasonCode: String
    var repairReasonCode: String
    var note: String

    var id: String {
        [
            projectId,
            actionId,
            outcome,
            String(Int((createdAt * 1000).rounded()))
        ]
        .filter { !$0.isEmpty }
        .joined(separator: ":")
    }

    func summaryLine(includeProject: Bool = false) -> String {
        var parts: [String] = []
        if includeProject {
            let display = projectDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
            parts.append("project=\(display.isEmpty ? projectId : display)")
        }
        parts.append("action=\(actionId)")
        parts.append("outcome=\(outcome)")
        if !requestedModelId.isEmpty {
            parts.append("requested=\(requestedModelId)")
        }
        if !actualModelId.isEmpty {
            parts.append("actual=\(actualModelId)")
        }
        if !fallbackReasonCode.isEmpty {
            parts.append("route_reason=\(fallbackReasonCode)")
        }
        if !repairReasonCode.isEmpty {
            parts.append("repair_reason=\(repairReasonCode)")
        }
        if !note.isEmpty {
            parts.append("note=\(note)")
        }
        return parts.joined(separator: " ")
    }
}

enum AXRouteRepairLogStore {
    static func record(
        actionId: String,
        outcome: String,
        latestEvent: AXModelRouteDiagnosticEvent?,
        repairReasonCode: String? = nil,
        note: String? = nil,
        createdAt: Double = Date().timeIntervalSince1970,
        for ctx: AXProjectContext
    ) {
        let normalizedActionId = normalizedText(actionId)
        let normalizedOutcome = normalizedText(outcome)
        guard !normalizedActionId.isEmpty, !normalizedOutcome.isEmpty else { return }
        try? ctx.ensureDirs()

        let event = AXRouteRepairLogEvent(
            schemaVersion: AXRouteRepairLogEvent.currentSchemaVersion,
            createdAt: createdAt,
            projectId: AXProjectRegistryStore.projectId(forRoot: ctx.root),
            projectDisplayName: AXProjectRegistryStore.displayName(
                forRoot: ctx.root,
                preferredDisplayName: ctx.projectName()
            ),
            actionId: normalizedActionId,
            outcome: normalizedOutcome,
            requestedModelId: normalizedText(latestEvent?.requestedModelId),
            actualModelId: normalizedText(latestEvent?.actualModelId),
            fallbackReasonCode: normalizedText(latestEvent?.fallbackReasonCode),
            repairReasonCode: normalizedText(repairReasonCode),
            note: normalizedText(note)
        )
        guard let data = try? JSONEncoder().encode(event) else { return }
        appendJSONLLine(data, to: ctx.routeRepairLogURL)
    }

    static func recentEvents(for ctx: AXProjectContext, limit: Int = 20) -> [AXRouteRepairLogEvent] {
        guard FileManager.default.fileExists(atPath: ctx.routeRepairLogURL.path),
              let data = try? Data(contentsOf: ctx.routeRepairLogURL),
              let text = String(data: data, encoding: .utf8) else {
            return []
        }

        let events = text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { line -> AXRouteRepairLogEvent? in
                guard let data = line.data(using: .utf8) else { return nil }
                return try? JSONDecoder().decode(AXRouteRepairLogEvent.self, from: data)
            }
            .sorted { lhs, rhs in
                if lhs.createdAt != rhs.createdAt {
                    return lhs.createdAt > rhs.createdAt
                }
                return lhs.id > rhs.id
            }
        return Array(events.prefix(limit))
    }

    static func summaryLines(for ctx: AXProjectContext, limit: Int = 5) -> [String] {
        recentEvents(for: ctx, limit: limit).map { $0.summaryLine(includeProject: false) }
    }

    private static func normalizedText(_ raw: String?) -> String {
        (raw ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
    }

    private static func appendJSONLLine(_ json: Data, to url: URL) {
        var line = json
        line.append(0x0A)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? line.write(to: url, options: .atomic)
            return
        }
        do {
            let fh = try FileHandle(forWritingTo: url)
            defer { try? fh.close() }
            try fh.seekToEnd()
            try fh.write(contentsOf: line)
        } catch {
            // Best-effort only.
        }
    }
}
