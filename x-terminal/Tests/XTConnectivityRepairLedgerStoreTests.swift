import Foundation
import Testing
@testable import XTerminal

@Suite(.serialized)
struct XTConnectivityRepairLedgerStoreTests {
    @Test
    func appendsAndDedupesConnectivityRepairEntries() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt_connectivity_repair_ledger_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }

        let waitingIncident = XTHubConnectivityIncidentSnapshot(
            incidentState: .waiting,
            reasonCode: "local_pairing_ready",
            summaryLine: "waiting to return to LAN or add a formal remote route.",
            trigger: .backgroundKeepalive,
            decisionReasonCode: "waiting_for_same_lan_or_formal_remote_route",
            pairedRouteReadiness: .localReady,
            stableRemoteRouteHost: nil,
            currentFailureCode: nil,
            currentPath: nil,
            lastUpdatedAtMs: 1_741_300_030_000
        )
        XTConnectivityRepairLedgerStore.append(
            XTConnectivityRepairLedgerStore.deferredEntry(
                trigger: .backgroundKeepalive,
                incidentSnapshot: waitingIncident
            )!,
            workspaceRoot: base
        )

        let waitingIncidentRefreshed = XTHubConnectivityIncidentSnapshot(
            incidentState: .waiting,
            reasonCode: "local_pairing_ready",
            summaryLine: "waiting to return to LAN or add a formal remote route.",
            trigger: .backgroundKeepalive,
            decisionReasonCode: "waiting_for_same_lan_or_formal_remote_route",
            pairedRouteReadiness: .localReady,
            stableRemoteRouteHost: nil,
            currentFailureCode: nil,
            currentPath: nil,
            lastUpdatedAtMs: 1_741_300_031_000
        )
        XTConnectivityRepairLedgerStore.append(
            XTConnectivityRepairLedgerStore.deferredEntry(
                trigger: .backgroundKeepalive,
                incidentSnapshot: waitingIncidentRefreshed
            )!,
            workspaceRoot: base
        )

        let recoveredIncident = XTHubConnectivityIncidentSnapshot(
            incidentState: .none,
            reasonCode: "remote_route_active",
            summaryLine: "validated remote route is active; no connectivity repair is needed.",
            trigger: .backgroundKeepalive,
            decisionReasonCode: "remote_route_already_active",
            pairedRouteReadiness: .remoteReady,
            stableRemoteRouteHost: "hub.tailnet.example",
            currentFailureCode: nil,
            currentPath: nil,
            lastUpdatedAtMs: 1_741_300_032_000
        )
        XTConnectivityRepairLedgerStore.append(
            XTConnectivityRepairLedgerStore.outcomeEntry(
                trigger: .backgroundKeepalive,
                owner: .xtRuntime,
                allowBootstrap: false,
                decisionReasonCode: "retry_degraded_remote_route",
                report: HubRemoteConnectReport(
                    ok: true,
                    route: .internet,
                    summary: "remote route verified",
                    logLines: [],
                    reasonCode: nil
                ),
                incidentSnapshot: recoveredIncident,
                recordedAtMs: 1_741_300_032_000
            ),
            workspaceRoot: base
        )

        let snapshot = XTConnectivityRepairLedgerStore.loadSnapshot(workspaceRoot: base)
        let summary = XTConnectivityRepairLedgerStore.summary(snapshot)

        #expect(snapshot.entries.count == 2)
        #expect(snapshot.entries.first?.result == .deferred)
        #expect(snapshot.entries.first?.action == .waitForRouteReady)
        #expect(snapshot.entries.first?.recordedAtMs == 1_741_300_031_000)
        #expect(snapshot.entries.last?.result == .succeeded)
        #expect(snapshot.entries.last?.action == .remoteReconnect)
        #expect(snapshot.entries.last?.verifyResult == "remote_route_active")
        #expect(snapshot.entries.last?.finalRoute == HubRemoteRoute.internet.rawValue)
        #expect(summary?.statusLine == "recent=2 · owner=xt_runtime · action=remote_reconnect · result=succeeded · verify=remote_route_active · route=internet")
        #expect(summary?.detailLine == "trail=wait_for_route_ready:deferred -> remote_reconnect:succeeded")
    }

    @Test
    func derivesRouteCooldownAndHealthFromFallbackHistory() {
        let snapshot = XTConnectivityRepairLedgerSnapshot(
            schemaVersion: XTConnectivityRepairLedgerSnapshot.currentSchemaVersion,
            updatedAtMs: 1_741_300_160_000,
            entries: [
                XTConnectivityRepairLedgerEntry(
                    schemaVersion: XTConnectivityRepairLedgerEntry.currentSchemaVersion,
                    entryID: "route-health-1",
                    recordedAtMs: 1_741_300_100_000,
                    trigger: .backgroundKeepalive,
                    failureCode: "grpc_unavailable",
                    reasonFamily: "route_connectivity",
                    action: .remoteReconnect,
                    owner: .xtRuntime,
                    result: .succeeded,
                    verifyResult: "repair_completed",
                    finalRoute: HubRemoteRoute.internetTunnel.rawValue,
                    decisionReasonCode: "retry_degraded_remote_route",
                    incidentReasonCode: "grpc_unavailable",
                    summaryLine: "tunnel fallback recovered the session",
                    selectedRoute: XTHubRouteCandidate.stableNamedRemote.rawValue,
                    attemptedRoutes: [
                        XTHubRouteCandidate.stableNamedRemote.rawValue,
                        XTHubRouteCandidate.managedTunnelFallback.rawValue
                    ],
                    handoffReason: nil,
                    cooldownApplied: false
                ),
                XTConnectivityRepairLedgerEntry(
                    schemaVersion: XTConnectivityRepairLedgerEntry.currentSchemaVersion,
                    entryID: "route-health-2",
                    recordedAtMs: 1_741_300_160_000,
                    trigger: .backgroundKeepalive,
                    failureCode: "grpc_unavailable",
                    reasonFamily: "route_connectivity",
                    action: .remoteReconnect,
                    owner: .xtRuntime,
                    result: .succeeded,
                    verifyResult: "repair_completed",
                    finalRoute: HubRemoteRoute.internetTunnel.rawValue,
                    decisionReasonCode: "retry_degraded_remote_route",
                    incidentReasonCode: "grpc_unavailable",
                    summaryLine: "tunnel fallback recovered the session",
                    selectedRoute: XTHubRouteCandidate.stableNamedRemote.rawValue,
                    attemptedRoutes: [
                        XTHubRouteCandidate.stableNamedRemote.rawValue,
                        XTHubRouteCandidate.managedTunnelFallback.rawValue
                    ],
                    handoffReason: nil,
                    cooldownApplied: false
                )
            ]
        )

        let routeStatuses = XTConnectivityRepairLedgerStore.routeStatusSnapshots(
            snapshot,
            now: Date(timeIntervalSince1970: 1_741_300_190)
        )
        let stableRemote = routeStatuses.first { $0.route == .stableNamedRemote }
        let tunnel = routeStatuses.first { $0.route == .managedTunnelFallback }

        #expect(stableRemote?.recentFailureCount == 2)
        #expect(stableRemote?.cooldownUntilMs != nil)
        #expect(tunnel?.recentSuccessCount == 2)
        #expect((tunnel?.healthScore ?? 0) > (stableRemote?.healthScore ?? 0))
    }
}
