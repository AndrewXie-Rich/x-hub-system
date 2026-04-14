import Foundation
import Testing
@testable import XTerminal

@Suite(.serialized)
struct XTHubNetworkHandoffProbeLogStoreTests {
    @Test
    func appendsAndDedupesProbeEntries() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt_handoff_probe_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }

        let path = XTHubConnectivityIncidentPathSnapshot(
            HubNetworkPathFingerprint(
                statusKey: "satisfied",
                usesWiFi: false,
                usesWiredEthernet: false,
                usesCellular: true,
                isExpensive: true,
                isConstrained: false
            )
        )
        let routeStatuses = [
            XTHubConnectivityRouteStatusSnapshot(
                route: .stableNamedRemote,
                healthScore: 24,
                cooldownUntilMs: 1_741_300_260_000,
                recentSuccessCount: 0,
                recentFailureCount: 2
            ),
            XTHubConnectivityRouteStatusSnapshot(
                route: .managedTunnelFallback,
                healthScore: 82,
                cooldownUntilMs: nil,
                recentSuccessCount: 2,
                recentFailureCount: 0
            )
        ]

        let waitingDecision = XTHubConnectivityDecision(
            shouldAttemptReconnect: false,
            allowBootstrap: false,
            summaryLine: "waiting to return to LAN or add a formal remote route.",
            reasonCode: "waiting_for_same_lan_or_formal_remote_route",
            selectedRoute: nil,
            candidatesTried: [.lanDirect],
            handoffReason: nil,
            cooldownApplied: false,
            routeStatuses: routeStatuses
        )
        let waitingIncident = XTHubConnectivityIncidentSnapshot(
            incidentState: .waiting,
            reasonCode: "local_pairing_ready",
            summaryLine: "waiting to return to LAN or add a formal remote route.",
            trigger: .systemWoke,
            decisionReasonCode: "waiting_for_same_lan_or_formal_remote_route",
            pairedRouteReadiness: .localReady,
            stableRemoteRouteHost: nil,
            currentFailureCode: nil,
            currentPath: path,
            lastUpdatedAtMs: 1_741_300_200_000
        )

        XTHubNetworkHandoffProbeLogStore.append(
            XTHubNetworkHandoffProbeLogStore.noAttemptEntry(
                trigger: .systemWoke,
                allowBootstrap: false,
                decision: waitingDecision,
                incidentSnapshot: waitingIncident,
                recordedAtMs: 1_741_300_200_000
            ),
            workspaceRoot: base
        )
        XTHubNetworkHandoffProbeLogStore.append(
            XTHubNetworkHandoffProbeLogStore.noAttemptEntry(
                trigger: .systemWoke,
                allowBootstrap: false,
                decision: waitingDecision,
                incidentSnapshot: waitingIncident,
                recordedAtMs: 1_741_300_210_000
            ),
            workspaceRoot: base
        )

        let retryDecision = XTHubConnectivityDecision(
            shouldAttemptReconnect: true,
            allowBootstrap: false,
            summaryLine: "system woke from sleep; retrying degraded remote route ...",
            reasonCode: "retry_degraded_remote_route",
            selectedRoute: .managedTunnelFallback,
            candidatesTried: [.stableNamedRemote, .managedTunnelFallback],
            handoffReason: "stable_named_remote_cooldown",
            cooldownApplied: true,
            routeStatuses: routeStatuses
        )
        let retryIncident = XTHubConnectivityIncidentSnapshot(
            incidentState: .retrying,
            reasonCode: "cached_remote_reconnect_smoke_failed",
            summaryLine: "system woke from sleep; retrying degraded remote route ...",
            trigger: .systemWoke,
            decisionReasonCode: "retry_degraded_remote_route",
            pairedRouteReadiness: .remoteDegraded,
            stableRemoteRouteHost: "hub.tailnet.example",
            currentFailureCode: "grpc_unavailable",
            currentPath: path,
            lastUpdatedAtMs: 1_741_300_240_000
        )
        let report = HubRemoteConnectReport(
            ok: true,
            route: .internetTunnel,
            summary: "managed tunnel route verified",
            logLines: [],
            reasonCode: nil,
            selectedRoute: .managedTunnelFallback,
            attemptedRoutes: [.stableNamedRemote, .managedTunnelFallback],
            handoffReason: "stable_named_remote_cooldown",
            cooldownApplied: true
        )

        XTHubNetworkHandoffProbeLogStore.append(
            XTHubNetworkHandoffProbeLogStore.outcomeEntry(
                trigger: .systemWoke,
                allowBootstrap: false,
                decision: retryDecision,
                incidentSnapshot: retryIncident,
                report: report,
                recordedAtMs: 1_741_300_240_000
            ),
            workspaceRoot: base
        )

        let snapshot = XTHubNetworkHandoffProbeLogStore.loadSnapshot(workspaceRoot: base)

        #expect(snapshot.schemaVersion == XTHubNetworkHandoffProbeLogSnapshot.currentSchemaVersion)
        #expect(snapshot.entries.count == 2)
        #expect(snapshot.entries.first?.result == .deferred)
        #expect(snapshot.entries.first?.recordedAtMs == 1_741_300_210_000)
        #expect(snapshot.entries.first?.currentPath?.usesCellular == true)
        #expect(snapshot.entries.first?.candidateRoutes == [XTHubRouteCandidate.lanDirect.rawValue])
        #expect(snapshot.entries.last?.result == .succeeded)
        #expect(snapshot.entries.last?.selectedRoute == XTHubRouteCandidate.managedTunnelFallback.rawValue)
        #expect(snapshot.entries.last?.attemptedRoutes == [
            XTHubRouteCandidate.stableNamedRemote.rawValue,
            XTHubRouteCandidate.managedTunnelFallback.rawValue
        ])
        #expect(snapshot.entries.last?.finalRoute == HubRemoteRoute.internetTunnel.rawValue)
        #expect(snapshot.entries.last?.handoffReason == "stable_named_remote_cooldown")
        #expect(snapshot.entries.last?.cooldownApplied == true)
        #expect(snapshot.entries.last?.trustMutationAllowed == false)
    }

    @Test
    func classifiesActiveLocalHubAsObserved() {
        let decision = XTHubConnectivityDecision(
            shouldAttemptReconnect: false,
            allowBootstrap: false,
            summaryLine: "",
            reasonCode: "local_hub_active",
            selectedRoute: nil,
            candidatesTried: [],
            handoffReason: nil,
            cooldownApplied: false,
            routeStatuses: []
        )
        let incident = XTHubConnectivityIncidentSnapshot(
            incidentState: .none,
            reasonCode: "local_hub_active",
            summaryLine: "local hub is active; no connectivity repair is needed.",
            trigger: .hubReachabilityChanged,
            decisionReasonCode: "local_hub_active",
            pairedRouteReadiness: .localReady,
            stableRemoteRouteHost: nil,
            currentFailureCode: nil,
            currentPath: nil,
            lastUpdatedAtMs: 1_741_300_260_000
        )

        let entry = XTHubNetworkHandoffProbeLogStore.noAttemptEntry(
            trigger: .hubReachabilityChanged,
            allowBootstrap: false,
            decision: decision,
            incidentSnapshot: incident,
            recordedAtMs: 1_741_300_260_000
        )

        #expect(entry.result == .observed)
        #expect(entry.reconnectAttempted == false)
        #expect(entry.trustMutationAllowed == false)
    }
}
