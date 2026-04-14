import Foundation

private func xtNormalizedNonEmpty(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

enum XTHubConnectivityIncidentState: String, Codable, Equatable, Sendable {
    case none
    case retrying
    case waiting
    case blocked
}

struct XTHubConnectivityIncidentPathSnapshot: Codable, Equatable, Sendable {
    var statusKey: String
    var usesWiFi: Bool
    var usesWiredEthernet: Bool
    var usesCellular: Bool
    var isExpensive: Bool
    var isConstrained: Bool

    init(_ fingerprint: HubNetworkPathFingerprint) {
        self.statusKey = fingerprint.statusKey
        self.usesWiFi = fingerprint.usesWiFi
        self.usesWiredEthernet = fingerprint.usesWiredEthernet
        self.usesCellular = fingerprint.usesCellular
        self.isExpensive = fingerprint.isExpensive
        self.isConstrained = fingerprint.isConstrained
    }

    var detailLine: String {
        [
            "connectivity_incident_path_status=\(statusKey)",
            "wifi=\(usesWiFi)",
            "wired=\(usesWiredEthernet)",
            "cellular=\(usesCellular)",
            "expensive=\(isExpensive)",
            "constrained=\(isConstrained)"
        ].joined(separator: " ")
    }
}

struct XTHubConnectivityIncidentSnapshot: Codable, Equatable, Sendable {
    static let currentSchemaVersion = "xt.hub_connectivity_incident.v1"

    var schemaVersion: String = currentSchemaVersion
    var incidentState: XTHubConnectivityIncidentState
    var reasonCode: String
    var summaryLine: String
    var trigger: XTHubConnectivityDecisionTrigger
    var decisionReasonCode: String
    var pairedRouteReadiness: XTPairedRouteReadiness?
    var stableRemoteRouteHost: String?
    var currentFailureCode: String?
    var currentPath: XTHubConnectivityIncidentPathSnapshot?
    var lastUpdatedAtMs: Int64
    var selectedRoute: XTHubRouteCandidate? = nil
    var candidatesTried: [XTHubRouteCandidate]? = nil
    var handoffReason: String? = nil
    var cooldownApplied: Bool? = nil
    var routeStatuses: [XTHubConnectivityRouteStatusSnapshot]? = nil

    func detailLines() -> [String] {
        var lines = [
            [
                "connectivity_incident",
                "state=\(incidentState.rawValue)",
                "trigger=\(trigger.rawValue)",
                "reason=\(reasonCode)",
                "decision_reason=\(decisionReasonCode)",
                "updated_at_ms=\(lastUpdatedAtMs)"
            ].joined(separator: " "),
            "connectivity_incident_summary=\(summaryLine)"
        ]
        if let pairedRouteReadiness {
            lines.append("connectivity_incident_paired_route_readiness=\(pairedRouteReadiness.rawValue)")
        }
        if let stableRemoteRouteHost = xtNormalizedNonEmpty(stableRemoteRouteHost) {
            lines.append("connectivity_incident_stable_remote_host=\(stableRemoteRouteHost)")
        }
        if let currentFailureCode = xtNormalizedNonEmpty(currentFailureCode) {
            lines.append("connectivity_incident_failure_code=\(currentFailureCode)")
        }
        if let selectedRoute {
            lines.append("connectivity_incident_selected_route=\(selectedRoute.rawValue)")
        }
        if let candidatesTried, !candidatesTried.isEmpty {
            lines.append(
                "connectivity_incident_candidates_tried=\(candidatesTried.map(\.rawValue).joined(separator: ","))"
            )
        }
        if let handoffReason = xtNormalizedNonEmpty(handoffReason) {
            lines.append("connectivity_incident_handoff_reason=\(handoffReason)")
        }
        if cooldownApplied == true {
            lines.append("connectivity_incident_cooldown_applied=true")
        }
        if let routeStatuses {
            lines.append(contentsOf: routeStatuses.map { routeStatus in
                var parts = [
                    "connectivity_incident_route_status",
                    "route=\(routeStatus.route.rawValue)",
                    "health_score=\(routeStatus.healthScore)",
                    "recent_success_count=\(routeStatus.recentSuccessCount)",
                    "recent_failure_count=\(routeStatus.recentFailureCount)"
                ]
                if let cooldownUntilMs = routeStatus.cooldownUntilMs {
                    parts.append("cooldown_until_ms=\(cooldownUntilMs)")
                }
                return parts.joined(separator: " ")
            })
        }
        if let currentPath {
            lines.append(currentPath.detailLine)
        }
        return lines
    }
}

struct XTHubConnectivityIncidentInput: Sendable {
    var trigger: XTHubConnectivityDecisionTrigger
    var decision: XTHubConnectivityDecision
    var currentPath: HubNetworkPathFingerprint?
    var pairedRouteSetSnapshot: XTPairedRouteSetSnapshot
    var localConnected: Bool
    var remoteConnected: Bool
    var remoteRoute: HubRemoteRoute
    var currentFailureCode: String
    var updatedAt: Date
}

enum XTHubConnectivityIncidentSnapshotBuilder {
    static func build(input: XTHubConnectivityIncidentInput) -> XTHubConnectivityIncidentSnapshot {
        let normalizedFailureCode = UITroubleshootKnowledgeBase.normalizedFailureCode(input.currentFailureCode)
        let pairedRouteReadiness = input.pairedRouteSetSnapshot.readiness
        let stableRemoteRouteHost = xtNormalizedNonEmpty(input.pairedRouteSetSnapshot.stableRemoteRoute?.host)
        let currentPath = input.currentPath.map(XTHubConnectivityIncidentPathSnapshot.init)
        let lastUpdatedAtMs = Int64(input.updatedAt.timeIntervalSince1970 * 1000)

        if input.localConnected {
            return XTHubConnectivityIncidentSnapshot(
                incidentState: .none,
                reasonCode: "local_hub_active",
                summaryLine: "local hub is active; no connectivity repair is needed.",
                trigger: input.trigger,
                decisionReasonCode: input.decision.reasonCode,
                pairedRouteReadiness: pairedRouteReadiness,
                stableRemoteRouteHost: stableRemoteRouteHost,
                currentFailureCode: xtNormalizedNonEmpty(normalizedFailureCode),
                currentPath: currentPath,
                lastUpdatedAtMs: lastUpdatedAtMs,
                selectedRoute: input.decision.selectedRoute,
                candidatesTried: input.decision.candidatesTried.isEmpty ? nil : input.decision.candidatesTried,
                handoffReason: input.decision.handoffReason,
                cooldownApplied: input.decision.cooldownApplied,
                routeStatuses: input.decision.routeStatuses
            )
        }

        if input.remoteConnected,
           input.remoteRoute != .none,
           input.currentPath?.isSatisfied != false {
            return XTHubConnectivityIncidentSnapshot(
                incidentState: .none,
                reasonCode: "remote_route_active",
                summaryLine: "validated remote route is active; no connectivity repair is needed.",
                trigger: input.trigger,
                decisionReasonCode: input.decision.reasonCode,
                pairedRouteReadiness: pairedRouteReadiness,
                stableRemoteRouteHost: stableRemoteRouteHost,
                currentFailureCode: xtNormalizedNonEmpty(normalizedFailureCode),
                currentPath: currentPath,
                lastUpdatedAtMs: lastUpdatedAtMs,
                selectedRoute: input.decision.selectedRoute,
                candidatesTried: input.decision.candidatesTried.isEmpty ? nil : input.decision.candidatesTried,
                handoffReason: input.decision.handoffReason,
                cooldownApplied: input.decision.cooldownApplied,
                routeStatuses: input.decision.routeStatuses
            )
        }

        let context = incidentContext(
            input: input,
            normalizedFailureCode: normalizedFailureCode
        )

        return XTHubConnectivityIncidentSnapshot(
            incidentState: context.state,
            reasonCode: context.reasonCode,
            summaryLine: context.summaryLine,
            trigger: input.trigger,
            decisionReasonCode: input.decision.reasonCode,
            pairedRouteReadiness: pairedRouteReadiness,
            stableRemoteRouteHost: stableRemoteRouteHost,
            currentFailureCode: xtNormalizedNonEmpty(normalizedFailureCode),
            currentPath: currentPath,
            lastUpdatedAtMs: lastUpdatedAtMs,
            selectedRoute: input.decision.selectedRoute,
            candidatesTried: input.decision.candidatesTried.isEmpty ? nil : input.decision.candidatesTried,
            handoffReason: input.decision.handoffReason,
            cooldownApplied: input.decision.cooldownApplied,
            routeStatuses: input.decision.routeStatuses
        )
    }

    private struct IncidentContext {
        var state: XTHubConnectivityIncidentState
        var reasonCode: String
        var summaryLine: String
    }

    private static func incidentContext(
        input: XTHubConnectivityIncidentInput,
        normalizedFailureCode: String
    ) -> IncidentContext {
        let pairedReason = xtNormalizedNonEmpty(input.pairedRouteSetSnapshot.readinessReasonCode)
            ?? "paired_route_readiness_unknown"
        let decisionSummary = xtNormalizedNonEmpty(input.decision.summaryLine)

        switch input.decision.reasonCode {
        case "local_hub_active":
            return IncidentContext(
                state: .none,
                reasonCode: "local_hub_active",
                summaryLine: "local hub is active; no connectivity repair is needed."
            )
        case "remote_route_already_active":
            return IncidentContext(
                state: .none,
                reasonCode: "remote_route_active",
                summaryLine: "validated remote route is active; no connectivity repair is needed."
            )
        case "network_unavailable":
            return IncidentContext(
                state: .waiting,
                reasonCode: "network_unavailable",
                summaryLine: decisionSummary ?? "network unavailable"
            )
        case "remote_route_blocked_waiting_for_repair":
            return IncidentContext(
                state: .blocked,
                reasonCode: xtNormalizedNonEmpty(normalizedFailureCode) ?? pairedReason,
                summaryLine: decisionSummary ?? "saved remote route is blocked by pairing/identity repair; waiting for repair."
            )
        case "waiting_for_same_lan_or_formal_remote_route", "local_pairing_only_waiting_for_route":
            return IncidentContext(
                state: .waiting,
                reasonCode: pairedReason,
                summaryLine: decisionSummary ?? "waiting for a LAN-capable path or a formal remote route."
            )
        case "retry_degraded_remote_route":
            return IncidentContext(
                state: .retrying,
                reasonCode: xtNormalizedNonEmpty(normalizedFailureCode) ?? pairedReason,
                summaryLine: decisionSummary ?? "retrying degraded remote route ..."
            )
        case "refresh_validated_remote_route",
             "verify_formal_remote_route",
             "retry_same_lan_paired_route",
             "probe_paired_route":
            return IncidentContext(
                state: .retrying,
                reasonCode: pairedReason,
                summaryLine: decisionSummary ?? "probing paired hub route ..."
            )
        default:
            return IncidentContext(
                state: input.decision.shouldAttemptReconnect ? .retrying : .waiting,
                reasonCode: xtNormalizedNonEmpty(normalizedFailureCode) ?? pairedReason,
                summaryLine: decisionSummary ?? input.pairedRouteSetSnapshot.summaryLine
            )
        }
    }
}
