import Foundation

enum XTFreshPairReconnectSmokeSource: String, Codable, Equatable, Sendable {
    case startupAutomaticFirstPair = "startup_automatic_first_pair"
    case manualOneClickSetup = "manual_one_click_setup"

    var doctorLabel: String {
        switch self {
        case .startupAutomaticFirstPair:
            return "启动自动首配"
        case .manualOneClickSetup:
            return "手动一键连接"
        }
    }
}

enum XTFreshPairReconnectSmokeStatus: String, Codable, Equatable, Sendable {
    case running
    case succeeded
    case failed
}

struct XTFreshPairReconnectSmokeSnapshot: Codable, Equatable, Sendable {
    var source: XTFreshPairReconnectSmokeSource
    var status: XTFreshPairReconnectSmokeStatus
    var triggeredAtMs: Int64
    var completedAtMs: Int64
    var route: HubRemoteRoute
    var reasonCode: String?
    var summary: String

    func detailLines() -> [String] {
        var lines = [
            "fresh_pair_reconnect_smoke status=\(status.rawValue) source=\(source.rawValue) route=\(route.rawValue) triggered_at_ms=\(triggeredAtMs) completed_at_ms=\(completedAtMs)"
        ]
        let normalizedReason = reasonCode?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !normalizedReason.isEmpty {
            lines.append("fresh_pair_reconnect_smoke_reason=\(normalizedReason)")
        }
        let normalizedSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalizedSummary.isEmpty {
            lines.append("fresh_pair_reconnect_smoke_summary=\(normalizedSummary)")
        }
        return lines
    }

    static func from(doctorDetailLines: [String]) -> XTFreshPairReconnectSmokeSnapshot? {
        guard let line = doctorDetailLines.first(where: { $0.hasPrefix("fresh_pair_reconnect_smoke ") }) else {
            return nil
        }
        let fields = doctorDetailLinesMap(from: line)
        guard let rawStatus = fields["status"],
              let status = XTFreshPairReconnectSmokeStatus(rawValue: rawStatus),
              let rawSource = fields["source"],
              let source = XTFreshPairReconnectSmokeSource(rawValue: rawSource) else {
            return nil
        }
        let route = HubRemoteRoute(rawValue: fields["route"] ?? "") ?? .none
        let triggeredAtMs = Int64(fields["triggered_at_ms"] ?? "") ?? 0
        let completedAtMs = Int64(fields["completed_at_ms"] ?? "") ?? 0
        let reasonCode = doctorDetailLines.first(where: { $0.hasPrefix("fresh_pair_reconnect_smoke_reason=") })
            .map { String($0.dropFirst("fresh_pair_reconnect_smoke_reason=".count)) }
        let summary = doctorDetailLines.first(where: { $0.hasPrefix("fresh_pair_reconnect_smoke_summary=") })
            .map { String($0.dropFirst("fresh_pair_reconnect_smoke_summary=".count)) } ?? ""
        return XTFreshPairReconnectSmokeSnapshot(
            source: source,
            status: status,
            triggeredAtMs: triggeredAtMs,
            completedAtMs: completedAtMs,
            route: route,
            reasonCode: reasonCode,
            summary: summary
        )
    }

    private static func doctorDetailLinesMap(from line: String) -> [String: String] {
        let rawFields = line.dropFirst("fresh_pair_reconnect_smoke ".count)
        var fields: [String: String] = [:]
        for token in rawFields.split(separator: " ") {
            let parts = token.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            fields[String(parts[0])] = String(parts[1])
        }
        return fields
    }
}
