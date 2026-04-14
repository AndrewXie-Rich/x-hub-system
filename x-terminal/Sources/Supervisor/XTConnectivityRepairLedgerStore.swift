import Foundation

enum XTConnectivityRepairTrigger: String, Codable, Equatable, Sendable {
    case networkChanged = "network_changed"
    case backgroundKeepalive = "background_keepalive"
    case appBecameActive = "app_became_active"
    case systemWoke = "system_woke"
    case hubReachabilityChanged = "hub_reachability_changed"
    case manualReconnect = "manual_reconnect"
    case manualOneClickSetup = "manual_one_click_setup"
    case startupAutoConnect = "startup_auto_connect"
    case freshPairReconnectSmoke = "fresh_pair_reconnect_smoke"
    case remoteShadowReconnectSmoke = "remote_shadow_reconnect_smoke"
}

enum XTConnectivityRepairOwner: String, Codable, Equatable, Sendable {
    case xtRuntime = "xt_runtime"
    case user = "user"
}

enum XTConnectivityRepairAction: String, Codable, Equatable, Sendable {
    case remoteReconnect = "remote_reconnect"
    case bootstrapReconnect = "bootstrap_reconnect"
    case waitForNetwork = "wait_for_network"
    case waitForPairingRepair = "wait_for_pairing_repair"
    case waitForRouteReady = "wait_for_route_ready"
}

enum XTConnectivityRepairResult: String, Codable, Equatable, Sendable {
    case deferred
    case succeeded
    case failed
}

struct XTConnectivityRepairLedgerEntry: Identifiable, Codable, Equatable, Sendable {
    static let currentSchemaVersion = "xt.connectivity_repair_ledger_entry.v1"

    var schemaVersion: String
    var entryID: String
    var recordedAtMs: Int64
    var trigger: XTConnectivityRepairTrigger
    var failureCode: String
    var reasonFamily: String
    var action: XTConnectivityRepairAction
    var owner: XTConnectivityRepairOwner
    var result: XTConnectivityRepairResult
    var verifyResult: String
    var finalRoute: String
    var decisionReasonCode: String?
    var incidentReasonCode: String
    var summaryLine: String
    var selectedRoute: String? = nil
    var attemptedRoutes: [String]? = nil
    var handoffReason: String? = nil
    var cooldownApplied: Bool? = nil

    var id: String { entryID }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case entryID = "entry_id"
        case recordedAtMs = "recorded_at_ms"
        case trigger
        case failureCode = "failure_code"
        case reasonFamily = "reason_family"
        case action
        case owner
        case result
        case verifyResult = "verify_result"
        case finalRoute = "final_route"
        case decisionReasonCode = "decision_reason_code"
        case incidentReasonCode = "incident_reason_code"
        case summaryLine = "summary_line"
        case selectedRoute = "selected_route"
        case attemptedRoutes = "attempted_routes"
        case handoffReason = "handoff_reason"
        case cooldownApplied = "cooldown_applied"
    }
}

struct XTConnectivityRepairLedgerSnapshot: Codable, Equatable, Sendable {
    static let currentSchemaVersion = "xt.connectivity_repair_ledger_snapshot.v1"

    var schemaVersion: String
    var updatedAtMs: Int64
    var entries: [XTConnectivityRepairLedgerEntry]

    static let empty = XTConnectivityRepairLedgerSnapshot(
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

struct XTConnectivityRepairLedgerSummary: Equatable, Sendable {
    var entryCount: Int
    var statusLine: String
    var detailLine: String?
}

enum XTConnectivityRepairLedgerStore {
    private static let fileName = "xt_connectivity_repair_ledger.json"
    private static let maxEntries = 24

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
    ) -> XTConnectivityRepairLedgerSnapshot {
        loadSnapshot(from: defaultURL(workspaceRoot: workspaceRoot)) ?? .empty
    }

    static func append(
        _ entry: XTConnectivityRepairLedgerEntry,
        workspaceRoot: URL = XTUnifiedDoctorStore.workspaceRootFromEnvOrCWD()
    ) {
        let url = defaultURL(workspaceRoot: workspaceRoot)
        let current = loadSnapshot(from: url) ?? .empty
        let entries = mergedEntries(current.entries, appending: entry)
        let snapshot = XTConnectivityRepairLedgerSnapshot(
            schemaVersion: XTConnectivityRepairLedgerSnapshot.currentSchemaVersion,
            updatedAtMs: max(entry.recordedAtMs, current.updatedAtMs),
            entries: entries
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(snapshot) else { return }
        try? XTStoreWriteSupport.writeSnapshotData(data, to: url)
    }

    static func deferredEntry(
        trigger: XTConnectivityRepairTrigger,
        incidentSnapshot: XTHubConnectivityIncidentSnapshot,
        owner: XTConnectivityRepairOwner = .xtRuntime
    ) -> XTConnectivityRepairLedgerEntry? {
        guard let action = deferredAction(for: incidentSnapshot) else {
            return nil
        }
        let failureCode = normalizedNonEmpty(
            UITroubleshootKnowledgeBase.normalizedFailureCode(incidentSnapshot.currentFailureCode ?? "")
        ) ?? incidentSnapshot.reasonCode
        return XTConnectivityRepairLedgerEntry(
            schemaVersion: XTConnectivityRepairLedgerEntry.currentSchemaVersion,
            entryID: "xt-connectivity-repair-\(incidentSnapshot.lastUpdatedAtMs)-\(UUID().uuidString)",
            recordedAtMs: incidentSnapshot.lastUpdatedAtMs,
            trigger: trigger,
            failureCode: failureCode,
            reasonFamily: reasonFamily(
                failureCode: failureCode,
                decisionReasonCode: incidentSnapshot.decisionReasonCode,
                incidentReasonCode: incidentSnapshot.reasonCode
            ),
            action: action,
            owner: owner,
            result: .deferred,
            verifyResult: verifyResult(for: incidentSnapshot, reportOK: false),
            finalRoute: HubRemoteRoute.none.rawValue,
            decisionReasonCode: incidentSnapshot.decisionReasonCode,
            incidentReasonCode: incidentSnapshot.reasonCode,
            summaryLine: incidentSnapshot.summaryLine
        )
    }

    static func outcomeEntry(
        trigger: XTConnectivityRepairTrigger,
        owner: XTConnectivityRepairOwner,
        allowBootstrap: Bool,
        decisionReasonCode: String?,
        report: HubRemoteConnectReport,
        incidentSnapshot: XTHubConnectivityIncidentSnapshot,
        recordedAtMs: Int64
    ) -> XTConnectivityRepairLedgerEntry {
        let fallbackFailure = normalizedNonEmpty(
            UITroubleshootKnowledgeBase.normalizedFailureCode(incidentSnapshot.currentFailureCode ?? "")
        )
        let failureCode = normalizedNonEmpty(
            UITroubleshootKnowledgeBase.normalizedFailureCode(report.reasonCode ?? "")
        ) ?? fallbackFailure ?? incidentSnapshot.reasonCode
        return XTConnectivityRepairLedgerEntry(
            schemaVersion: XTConnectivityRepairLedgerEntry.currentSchemaVersion,
            entryID: "xt-connectivity-repair-\(recordedAtMs)-\(UUID().uuidString)",
            recordedAtMs: recordedAtMs,
            trigger: trigger,
            failureCode: failureCode,
            reasonFamily: reasonFamily(
                failureCode: failureCode,
                decisionReasonCode: decisionReasonCode ?? incidentSnapshot.decisionReasonCode,
                incidentReasonCode: incidentSnapshot.reasonCode
            ),
            action: allowBootstrap ? .bootstrapReconnect : .remoteReconnect,
            owner: owner,
            result: report.ok ? .succeeded : .failed,
            verifyResult: verifyResult(for: incidentSnapshot, reportOK: report.ok),
            finalRoute: report.route.rawValue,
            decisionReasonCode: decisionReasonCode ?? incidentSnapshot.decisionReasonCode,
            incidentReasonCode: incidentSnapshot.reasonCode,
            summaryLine: report.summary,
            selectedRoute: report.route == .none ? nil : report.route.rawValue,
            attemptedRoutes: report.route == .none ? nil : [report.route.rawValue]
        )
    }

    static func summary(
        _ snapshot: XTConnectivityRepairLedgerSnapshot
    ) -> XTConnectivityRepairLedgerSummary? {
        guard let latest = snapshot.entries.last else { return nil }
        let statusLine = [
            "recent=\(snapshot.entries.count)",
            "owner=\(latest.owner.rawValue)",
            "action=\(latest.action.rawValue)",
            "result=\(latest.result.rawValue)",
            "verify=\(latest.verifyResult)",
            "route=\(latest.finalRoute)"
        ].joined(separator: " · ")
        let trail = snapshot.entries.suffix(3).map { entry in
            "\(entry.action.rawValue):\(entry.result.rawValue)"
        }.joined(separator: " -> ")
        let detail = trail.isEmpty ? nil : "trail=\(trail)"
        return XTConnectivityRepairLedgerSummary(
            entryCount: snapshot.entries.count,
            statusLine: statusLine,
            detailLine: detail
        )
    }

    static func routeStatusSnapshots(
        _ snapshot: XTConnectivityRepairLedgerSnapshot,
        now: Date = Date()
    ) -> [XTHubConnectivityRouteStatusSnapshot] {
        let nowMs = Int64((now.timeIntervalSince1970 * 1000).rounded())
        let newestFirst = Array(snapshot.entries.reversed())

        return XTHubRouteCandidate.allCases.map { route in
            let recentSuccessCount = snapshot.entries.filter { $0.countsSuccess(for: route) }.count
            let recentFailureCount = snapshot.entries.filter { $0.countsFailure(for: route) }.count
            let consecutiveFailures = newestFirst.consecutiveFailures(for: route)
            let lastFailureAtMs = newestFirst.first { $0.countsFailure(for: route) }?.recordedAtMs
            let cooldownUntilMs: Int64?

            if consecutiveFailures >= 2, let lastFailureAtMs {
                let cooldownWindowMs = min(Int64(10 * 60_000), Int64(consecutiveFailures) * 90_000)
                let candidate = lastFailureAtMs + cooldownWindowMs
                cooldownUntilMs = candidate > nowMs ? candidate : nil
            } else {
                cooldownUntilMs = nil
            }

            var healthScore = 70
            healthScore += recentSuccessCount * 10
            healthScore -= recentFailureCount * 18
            healthScore -= consecutiveFailures * 10
            if cooldownUntilMs != nil {
                healthScore -= 15
            }

            return XTHubConnectivityRouteStatusSnapshot(
                route: route,
                healthScore: max(0, min(100, healthScore)),
                cooldownUntilMs: cooldownUntilMs,
                recentSuccessCount: recentSuccessCount,
                recentFailureCount: recentFailureCount
            )
        }
    }

    private static func loadSnapshot(from url: URL) -> XTConnectivityRepairLedgerSnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(XTConnectivityRepairLedgerSnapshot.self, from: data)
    }

    private static func mergedEntries(
        _ existing: [XTConnectivityRepairLedgerEntry],
        appending entry: XTConnectivityRepairLedgerEntry
    ) -> [XTConnectivityRepairLedgerEntry] {
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

    private static func deferredAction(
        for snapshot: XTHubConnectivityIncidentSnapshot
    ) -> XTConnectivityRepairAction? {
        switch snapshot.decisionReasonCode {
        case "network_unavailable":
            return .waitForNetwork
        case "remote_route_blocked_waiting_for_repair":
            return .waitForPairingRepair
        case "waiting_for_same_lan_or_formal_remote_route",
             "local_pairing_only_waiting_for_route":
            return .waitForRouteReady
        default:
            return nil
        }
    }

    private static func verifyResult(
        for snapshot: XTHubConnectivityIncidentSnapshot,
        reportOK: Bool
    ) -> String {
        if reportOK {
            switch snapshot.reasonCode {
            case "local_hub_active":
                return "local_hub_active"
            case "remote_route_active":
                return "remote_route_active"
            default:
                return "repair_completed"
            }
        }
        switch snapshot.incidentState {
        case .blocked:
            return "blocked_waiting_for_repair"
        case .waiting:
            return snapshot.reasonCode
        case .retrying:
            return "retrying_remote_route"
        case .none:
            return snapshot.reasonCode
        }
    }

    private static func reasonFamily(
        failureCode: String,
        decisionReasonCode: String?,
        incidentReasonCode: String
    ) -> String {
        let combined = [
            failureCode,
            decisionReasonCode ?? "",
            incidentReasonCode
        ]
            .joined(separator: " ")
            .lowercased()

        if combined.contains("pair")
            || combined.contains("identity")
            || combined.contains("certificate")
            || combined.contains("mtls") {
            return "pairing_identity"
        }
        if combined.contains("network") {
            return "network"
        }
        if combined.contains("grpc")
            || combined.contains("route")
            || combined.contains("connect")
            || combined.contains("discover") {
            return "route_connectivity"
        }
        if combined.contains("runtime")
            || combined.contains("local_service") {
            return "runtime"
        }
        return "connectivity"
    }

    private static func normalizedNonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension XTConnectivityRepairLedgerEntry {
    var selectedRouteCandidate: XTHubRouteCandidate? {
        selectedRoute.flatMap(XTHubRouteCandidate.init(rawValue:))
    }

    var attemptedRouteCandidates: [XTHubRouteCandidate] {
        (attemptedRoutes ?? []).compactMap(XTHubRouteCandidate.init(rawValue:))
    }

    var finalRouteCandidate: XTHubRouteCandidate? {
        HubRemoteRoute(rawValue: finalRoute).flatMap(XTHubRouteCandidate.from(remoteRoute:))
    }

    func referencesRoute(_ route: XTHubRouteCandidate) -> Bool {
        if selectedRouteCandidate == route {
            return true
        }
        if attemptedRouteCandidates.contains(route) {
            return true
        }
        return finalRouteCandidate == route
    }

    func countsSuccess(for route: XTHubRouteCandidate) -> Bool {
        guard result == .succeeded else { return false }
        return finalRouteCandidate == route
    }

    func countsFailure(for route: XTHubRouteCandidate) -> Bool {
        switch result {
        case .deferred:
            return false
        case .failed:
            return referencesRoute(route)
        case .succeeded:
            guard referencesRoute(route) else { return false }
            return finalRouteCandidate != route
        }
    }

    var dedupeKey: String {
        [
            trigger.rawValue,
            failureCode,
            reasonFamily,
            action.rawValue,
            owner.rawValue,
            result.rawValue,
            verifyResult,
            finalRoute,
            decisionReasonCode ?? "",
            incidentReasonCode,
            selectedRoute ?? "",
            (attemptedRoutes ?? []).joined(separator: ","),
            handoffReason ?? "",
            cooldownApplied == true ? "cooldown" : "no_cooldown"
        ].joined(separator: "|")
    }
}

private extension Array where Element == XTConnectivityRepairLedgerEntry {
    func consecutiveFailures(for route: XTHubRouteCandidate) -> Int {
        var count = 0
        for entry in self {
            if entry.countsSuccess(for: route) {
                break
            }
            if entry.countsFailure(for: route) {
                count += 1
            }
        }
        return count
    }
}
