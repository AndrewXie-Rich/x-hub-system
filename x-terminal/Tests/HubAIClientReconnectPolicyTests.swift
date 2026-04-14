import Testing
@testable import XTerminal

struct HubAIClientReconnectPolicyTests {
    @Test
    func doesNotReconnectRouteForSlowRemoteTimeouts() {
        #expect(
            HubAIClient.shouldAttemptRemoteRouteReconnect(
                afterRemoteReasonCode: "timeout",
                transportMode: .grpc
            ) == false
        )
        #expect(
            HubAIClient.shouldAttemptRemoteRouteReconnect(
                afterRemoteReasonCode: "remote_timeout",
                transportMode: .auto
            ) == false
        )
    }

    @Test
    func reconnectsRouteForConnectivityBreaks() {
        #expect(
            HubAIClient.shouldAttemptRemoteRouteReconnect(
                afterRemoteReasonCode: "connection_refused",
                transportMode: .grpc
            )
        )
        #expect(
            HubAIClient.shouldAttemptRemoteRouteReconnect(
                afterRemoteReasonCode: "grpc_unavailable",
                transportMode: .auto
            )
        )
        #expect(
            HubAIClient.shouldAttemptRemoteRouteReconnect(
                afterRemoteReasonCode: "tcp_timeout",
                transportMode: .auto
            )
        )
        #expect(
            HubAIClient.shouldAttemptRemoteRouteReconnect(
                afterRemoteReasonCode: "hub_unreachable",
                transportMode: .grpc
            )
        )
    }

    @Test
    func neverReconnectsRouteInFileIPCMode() {
        #expect(
            HubAIClient.shouldAttemptRemoteRouteReconnect(
                afterRemoteReasonCode: "connection_refused",
                transportMode: .fileIPC
            ) == false
        )
    }

    @Test
    func remoteReconnectCandidatesStayOnLanAndStableNamedRoutes() {
        #expect(
            HubAIClient.automaticRemoteReconnectCandidateRoutes(
                internetHost: "hub.tailnet.example"
            ) == [.lanDirect, .stableNamedRemote]
        )
        #expect(
            HubAIClient.automaticRemoteReconnectCandidateRoutes(
                internetHost: ""
            ) == [.lanDirect]
        )
    }

    @Test
    func reconnectPlanPrefersStableRemoteWhenCurrentConnectionUsesStableHost() {
        let plan = HubAIClient.automaticRemoteReconnectPlan(
            cachedProfile: HubAIClient.CachedRemoteProfile(
                host: "hub.tailnet.example",
                internetHost: "hub.tailnet.example",
                pairingPort: 50052,
                grpcPort: 50051,
                hubInstanceID: "hub-1",
                lanDiscoveryName: "Hub"
            ),
            internetHost: "hub.tailnet.example"
        )

        #expect(plan.preferredRoute == .stableNamedRemote)
        #expect(plan.candidateRoutes == [.stableNamedRemote, .lanDirect])
        #expect(plan.handoffReason == "remote_generate_reconnect_prefer_stable_remote")
    }

    @Test
    func reconnectPlanNormalizesLoopbackTunnelProfileToStableRemote() {
        let plan = HubAIClient.automaticRemoteReconnectPlan(
            cachedProfile: HubAIClient.CachedRemoteProfile(
                host: "127.0.0.1",
                internetHost: "hub.tailnet.example",
                pairingPort: 50052,
                grpcPort: 50051,
                hubInstanceID: "hub-1",
                lanDiscoveryName: "Hub"
            ),
            internetHost: "hub.tailnet.example"
        )

        #expect(plan.preferredRoute == .stableNamedRemote)
        #expect(plan.candidateRoutes == [.stableNamedRemote, .lanDirect])
        #expect(plan.handoffReason == "remote_generate_reconnect_prefer_stable_remote")
    }

    @Test
    func reconnectPlanFallsBackToStableRemoteFromFormalInternetHostHint() {
        let plan = HubAIClient.automaticRemoteReconnectPlan(
            cachedProfile: HubAIClient.CachedRemoteProfile(
                host: nil,
                internetHost: nil,
                pairingPort: 50052,
                grpcPort: 50051,
                hubInstanceID: "hub-1",
                lanDiscoveryName: "Hub"
            ),
            internetHost: "hub.tailnet.example"
        )

        #expect(plan.preferredRoute == .stableNamedRemote)
        #expect(plan.candidateRoutes == [.stableNamedRemote, .lanDirect])
    }

    @Test
    func reconnectPlanKeepsLanFirstWhenCurrentConnectionLooksLanLocal() {
        let plan = HubAIClient.automaticRemoteReconnectPlan(
            cachedProfile: HubAIClient.CachedRemoteProfile(
                host: "192.168.0.12",
                internetHost: "hub.tailnet.example",
                pairingPort: 50052,
                grpcPort: 50051,
                hubInstanceID: "hub-1",
                lanDiscoveryName: "Hub"
            ),
            internetHost: "hub.tailnet.example"
        )

        #expect(plan.preferredRoute == .lanDirect)
        #expect(plan.candidateRoutes == [.lanDirect, .stableNamedRemote])
        #expect(plan.handoffReason == "remote_generate_reconnect_prefer_lan_route")
    }

    @Test
    func preflightRepairTargetsRawPublicIPv4ProfileWithoutStableRemoteHost() {
        let shouldRepair = HubAIClient.requiresRemoteRoutePreflightRepairForTesting(
            cachedProfile: HubAIClient.CachedRemoteProfile(
                host: "17.81.11.116",
                internetHost: nil,
                pairingPort: 50052,
                grpcPort: 50051,
                hubInstanceID: "hub-1",
                lanDiscoveryName: "Hub"
            ),
            internetHost: ""
        )

        #expect(shouldRepair)
    }

    @Test
    func preflightRepairSkipsStableNamedRemoteProfiles() {
        let shouldRepair = HubAIClient.requiresRemoteRoutePreflightRepairForTesting(
            cachedProfile: HubAIClient.CachedRemoteProfile(
                host: "17.81.11.116",
                internetHost: "hub.tailnet.example",
                pairingPort: 50052,
                grpcPort: 50051,
                hubInstanceID: "hub-1",
                lanDiscoveryName: "Hub"
            ),
            internetHost: "hub.tailnet.example"
        )

        #expect(shouldRepair == false)
    }

    @Test
    func preflightRepairSkipsPrivateLanProfiles() {
        let shouldRepair = HubAIClient.requiresRemoteRoutePreflightRepairForTesting(
            cachedProfile: HubAIClient.CachedRemoteProfile(
                host: "192.168.0.12",
                internetHost: nil,
                pairingPort: 50052,
                grpcPort: 50051,
                hubInstanceID: "hub-1",
                lanDiscoveryName: "Hub"
            ),
            internetHost: ""
        )

        #expect(shouldRepair == false)
    }

    @Test
    func followupReconnectPlanDropsPreviouslyAttemptedPrimaryRoute() {
        let primaryPlan = HubAIClient.RemoteReconnectPlan(
            preferredRoute: .stableNamedRemote,
            candidateRoutes: [.stableNamedRemote, .lanDirect],
            handoffReason: "remote_generate_reconnect_prefer_stable_remote"
        )
        let reconnectReport = HubRemoteConnectReport(
            ok: true,
            route: .internet,
            summary: "connected_internet",
            logLines: [],
            reasonCode: nil,
            selectedRoute: .stableNamedRemote,
            attemptedRoutes: [.stableNamedRemote]
        )

        let followupPlan = HubAIClient.followupRemoteReconnectPlan(
            after: reconnectReport,
            primaryPlan: primaryPlan
        )

        #expect(followupPlan?.preferredRoute == .lanDirect)
        #expect(followupPlan?.candidateRoutes == [.lanDirect])
        #expect(followupPlan?.handoffReason == "remote_generate_retry_after_route_attempts:stable_named_remote")
    }

    @Test
    func followupReconnectPlanReturnsNilWhenNoAlternativeRoutesRemain() {
        let primaryPlan = HubAIClient.RemoteReconnectPlan(
            preferredRoute: .stableNamedRemote,
            candidateRoutes: [.stableNamedRemote],
            handoffReason: "remote_generate_reconnect_prefer_stable_remote"
        )
        let reconnectReport = HubRemoteConnectReport(
            ok: true,
            route: .internet,
            summary: "connected_internet",
            logLines: [],
            reasonCode: nil,
            selectedRoute: .stableNamedRemote,
            attemptedRoutes: [.stableNamedRemote]
        )

        #expect(
            HubAIClient.followupRemoteReconnectPlan(
                after: reconnectReport,
                primaryPlan: primaryPlan
            ) == nil
        )
    }
}
