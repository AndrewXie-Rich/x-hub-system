import Foundation

private func xtProbeNormalizedNonEmpty(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

enum XTHubNetworkHandoffProbeResult: String, Codable, Equatable, Sendable {
    case observed
    case deferred
    case succeeded
    case failed
}

struct XTHubNetworkHandoffProbeEntry: Identifiable, Codable, Equatable, Sendable {
    static let currentSchemaVersion = "xt.network_handoff_probe_entry.v1"

    var schemaVersion: String
    var probeID: String
    var recordedAtMs: Int64
    var trigger: XTHubConnectivityDecisionTrigger
    var result: XTHubNetworkHandoffProbeResult
    var reconnectAttempted: Bool
    var allowBootstrap: Bool
    var decisionReasonCode: String
    var incidentReasonCode: String
    var summaryLine: String
    var pairedRouteReadiness: XTPairedRouteReadiness?
    var selectedRoute: String? = nil
    var candidateRoutes: [String]
    var attemptedRoutes: [String]? = nil
    var finalRoute: String? = nil
    var handoffReason: String? = nil
    var cooldownApplied: Bool
    var trustMutationAllowed: Bool
    var currentPath: XTHubConnectivityIncidentPathSnapshot? = nil
    var routeStatuses: [XTHubConnectivityRouteStatusSnapshot]? = nil
    var reportReasonCode: String? = nil
    var reportSummary: String? = nil

    var id: String { probeID }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case probeID = "probe_id"
        case recordedAtMs = "recorded_at_ms"
        case trigger
        case result
        case reconnectAttempted = "reconnect_attempted"
        case allowBootstrap = "allow_bootstrap"
        case decisionReasonCode = "decision_reason_code"
        case incidentReasonCode = "incident_reason_code"
        case summaryLine = "summary_line"
        case pairedRouteReadiness = "paired_route_readiness"
        case selectedRoute = "selected_route"
        case candidateRoutes = "candidate_routes"
        case attemptedRoutes = "attempted_routes"
        case finalRoute = "final_route"
        case handoffReason = "handoff_reason"
        case cooldownApplied = "cooldown_applied"
        case trustMutationAllowed = "trust_mutation_allowed"
        case currentPath = "current_path"
        case routeStatuses = "route_statuses"
        case reportReasonCode = "report_reason_code"
        case reportSummary = "report_summary"
    }
}

struct XTHubNetworkHandoffProbeLogSnapshot: Codable, Equatable, Sendable {
    static let currentSchemaVersion = "xt.network_handoff_probe_log.v1"

    var schemaVersion: String
    var updatedAtMs: Int64
    var entries: [XTHubNetworkHandoffProbeEntry]

    static let empty = XTHubNetworkHandoffProbeLogSnapshot(
        schemaVersion: currentSchemaVersion,
        updatedAtMs: 0,
        entries: []
    )

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case updatedAtMs = "updated_at_ms"
        case entries
    }
}

enum XTHubNetworkHandoffProbeLogStore {
    private static let fileName = "xt_network_handoff_probe_log.v1.json"
    private static let maxEntries = 40

    static func defaultURL(
        workspaceRoot: URL = XTUnifiedDoctorStore.workspaceRootFromEnvOrCWD()
    ) -> URL {
        workspaceRoot
            .appendingPathComponent(".axcoder", isDirectory: true)
            .appendingPathComponent("reports", isDirectory: true)
            .appendingPathComponent(fileName)
    }

    static func loadSnapshot(
        workspaceRoot: URL = XTUnifiedDoctorStore.workspaceRootFromEnvOrCWD()
    ) -> XTHubNetworkHandoffProbeLogSnapshot {
        loadSnapshot(from: defaultURL(workspaceRoot: workspaceRoot)) ?? .empty
    }

    static func append(
        _ entry: XTHubNetworkHandoffProbeEntry,
        workspaceRoot: URL = XTUnifiedDoctorStore.workspaceRootFromEnvOrCWD()
    ) {
        let url = defaultURL(workspaceRoot: workspaceRoot)
        let current = loadSnapshot(from: url) ?? .empty
        let entries = mergedEntries(current.entries, appending: entry)
        let snapshot = XTHubNetworkHandoffProbeLogSnapshot(
            schemaVersion: XTHubNetworkHandoffProbeLogSnapshot.currentSchemaVersion,
            updatedAtMs: max(entry.recordedAtMs, current.updatedAtMs),
            entries: entries
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(snapshot) else { return }
        try? XTStoreWriteSupport.writeSnapshotData(data, to: url)
    }

    static func noAttemptEntry(
        trigger: XTHubConnectivityDecisionTrigger,
        allowBootstrap: Bool,
        decision: XTHubConnectivityDecision,
        incidentSnapshot: XTHubConnectivityIncidentSnapshot,
        recordedAtMs: Int64
    ) -> XTHubNetworkHandoffProbeEntry {
        XTHubNetworkHandoffProbeEntry(
            schemaVersion: XTHubNetworkHandoffProbeEntry.currentSchemaVersion,
            probeID: "xt-handoff-probe-\(recordedAtMs)-\(UUID().uuidString)",
            recordedAtMs: recordedAtMs,
            trigger: trigger,
            result: incidentSnapshot.incidentState == .none ? .observed : .deferred,
            reconnectAttempted: false,
            allowBootstrap: allowBootstrap,
            decisionReasonCode: decision.reasonCode,
            incidentReasonCode: incidentSnapshot.reasonCode,
            summaryLine: incidentSnapshot.summaryLine,
            pairedRouteReadiness: incidentSnapshot.pairedRouteReadiness,
            selectedRoute: decision.selectedRoute?.rawValue,
            candidateRoutes: decision.candidatesTried.map(\.rawValue),
            attemptedRoutes: nil,
            finalRoute: nil,
            handoffReason: xtProbeNormalizedNonEmpty(decision.handoffReason),
            cooldownApplied: decision.cooldownApplied,
            trustMutationAllowed: false,
            currentPath: incidentSnapshot.currentPath,
            routeStatuses: decision.routeStatuses.isEmpty ? nil : decision.routeStatuses,
            reportReasonCode: nil,
            reportSummary: nil
        )
    }

    static func outcomeEntry(
        trigger: XTHubConnectivityDecisionTrigger,
        allowBootstrap: Bool,
        decision: XTHubConnectivityDecision,
        incidentSnapshot: XTHubConnectivityIncidentSnapshot,
        report: HubRemoteConnectReport,
        recordedAtMs: Int64
    ) -> XTHubNetworkHandoffProbeEntry {
        let attemptedRoutes = report.attemptedRoutes.isEmpty
            ? decision.candidatesTried.map(\.rawValue)
            : report.attemptedRoutes.map(\.rawValue)
        return XTHubNetworkHandoffProbeEntry(
            schemaVersion: XTHubNetworkHandoffProbeEntry.currentSchemaVersion,
            probeID: "xt-handoff-probe-\(recordedAtMs)-\(UUID().uuidString)",
            recordedAtMs: recordedAtMs,
            trigger: trigger,
            result: report.ok ? .succeeded : .failed,
            reconnectAttempted: true,
            allowBootstrap: allowBootstrap,
            decisionReasonCode: decision.reasonCode,
            incidentReasonCode: incidentSnapshot.reasonCode,
            summaryLine: report.summary,
            pairedRouteReadiness: incidentSnapshot.pairedRouteReadiness,
            selectedRoute: report.selectedRoute?.rawValue ?? decision.selectedRoute?.rawValue,
            candidateRoutes: decision.candidatesTried.map(\.rawValue),
            attemptedRoutes: attemptedRoutes.isEmpty ? nil : attemptedRoutes,
            finalRoute: report.route == .none ? nil : report.route.rawValue,
            handoffReason: xtProbeNormalizedNonEmpty(report.handoffReason ?? decision.handoffReason),
            cooldownApplied: report.cooldownApplied || decision.cooldownApplied,
            trustMutationAllowed: false,
            currentPath: incidentSnapshot.currentPath,
            routeStatuses: decision.routeStatuses.isEmpty ? nil : decision.routeStatuses,
            reportReasonCode: xtProbeNormalizedNonEmpty(report.reasonCode),
            reportSummary: xtProbeNormalizedNonEmpty(report.summary)
        )
    }

    private static func loadSnapshot(from url: URL) -> XTHubNetworkHandoffProbeLogSnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(XTHubNetworkHandoffProbeLogSnapshot.self, from: data)
    }

    private static func mergedEntries(
        _ existing: [XTHubNetworkHandoffProbeEntry],
        appending entry: XTHubNetworkHandoffProbeEntry
    ) -> [XTHubNetworkHandoffProbeEntry] {
        guard var last = existing.last else {
            return [entry]
        }

        if entry.recordedAtMs < last.recordedAtMs {
            return existing
        }

        var entries = existing
        if last.dedupeKey == entry.dedupeKey {
            last = entry
            entries[entries.count - 1] = last
            return Array(entries.suffix(maxEntries))
        }

        entries.append(entry)
        return Array(entries.suffix(maxEntries))
    }
}

private extension XTHubNetworkHandoffProbeEntry {
    var routeStatusSignature: String {
        (routeStatuses ?? []).map { status in
            [
                status.route.rawValue,
                String(status.healthScore),
                status.cooldownUntilMs.map(String.init) ?? "",
                String(status.recentSuccessCount),
                String(status.recentFailureCount)
            ].joined(separator: ":")
        }.joined(separator: ",")
    }

    var pathSignature: String {
        guard let currentPath else { return "" }
        return [
            currentPath.statusKey,
            currentPath.usesWiFi ? "wifi" : "no_wifi",
            currentPath.usesWiredEthernet ? "wired" : "no_wired",
            currentPath.usesCellular ? "cellular" : "no_cellular",
            currentPath.isExpensive ? "expensive" : "not_expensive",
            currentPath.isConstrained ? "constrained" : "not_constrained"
        ].joined(separator: ":")
    }

    var dedupeKey: String {
        [
            trigger.rawValue,
            result.rawValue,
            reconnectAttempted ? "attempted" : "not_attempted",
            allowBootstrap ? "bootstrap" : "connect_only",
            decisionReasonCode,
            incidentReasonCode,
            summaryLine,
            pairedRouteReadiness?.rawValue ?? "",
            selectedRoute ?? "",
            candidateRoutes.joined(separator: ","),
            (attemptedRoutes ?? []).joined(separator: ","),
            finalRoute ?? "",
            handoffReason ?? "",
            cooldownApplied ? "cooldown" : "no_cooldown",
            trustMutationAllowed ? "trust_mutation_allowed" : "trust_mutation_locked",
            pathSignature,
            routeStatusSignature,
            reportReasonCode ?? "",
            reportSummary ?? ""
        ].joined(separator: "|")
    }
}
