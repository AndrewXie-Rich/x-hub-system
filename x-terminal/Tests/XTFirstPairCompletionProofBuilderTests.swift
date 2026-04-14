import Foundation
import Testing
@testable import XTerminal

struct XTFirstPairCompletionProofBuilderTests {
    @Test
    func localReadyProofStaysConservativeUntilRemoteShadowRuns() {
        let snapshot = XTFirstPairCompletionProofBuilder.build(
            input: XTFirstPairCompletionProofBuildInput(
                generatedAt: Date(timeIntervalSince1970: 1_741_300_300),
                localConnected: false,
                remoteConnected: false,
                remoteRoute: .none,
                cachedProfile: sampleCachedRemoteProfile(),
                freshPairReconnectSmokeSnapshot: XTFreshPairReconnectSmokeSnapshot(
                    source: .manualOneClickSetup,
                    status: .succeeded,
                    triggeredAtMs: 1_741_300_100_000,
                    completedAtMs: 1_741_300_110_000,
                    route: .lan,
                    reasonCode: nil,
                    summary: "cached route verified"
                ),
                remoteShadowReconnectSmokeSnapshot: nil,
                pairedRouteSetSnapshot: samplePairedRouteSetSnapshot(readiness: .localReady)
            )
        )

        #expect(snapshot.readiness == .localReady)
        #expect(snapshot.sameLanVerified == true)
        #expect(snapshot.ownerLocalApprovalVerified == true)
        #expect(snapshot.pairingMaterialIssued == true)
        #expect(snapshot.cachedReconnectSmokePassed == true)
        #expect(snapshot.stableRemoteRoutePresent == true)
        #expect(snapshot.remoteShadowSmokeStatus == .notRun)
        #expect(snapshot.remoteShadowSmokePassed == false)
    }

    @Test
    func remoteShadowProofPassesWhenValidatedRemoteRouteIsLive() {
        let snapshot = XTFirstPairCompletionProofBuilder.build(
            input: XTFirstPairCompletionProofBuildInput(
                generatedAt: Date(timeIntervalSince1970: 1_741_300_320),
                localConnected: false,
                remoteConnected: true,
                remoteRoute: .internet,
                cachedProfile: sampleCachedRemoteProfile(),
                freshPairReconnectSmokeSnapshot: nil,
                remoteShadowReconnectSmokeSnapshot: nil,
                pairedRouteSetSnapshot: samplePairedRouteSetSnapshot(readiness: .remoteReady)
            )
        )

        #expect(snapshot.readiness == .remoteReady)
        #expect(snapshot.remoteShadowSmokeStatus == .passed)
        #expect(snapshot.remoteShadowSmokePassed == true)
        #expect(snapshot.remoteShadowSmokeSource == .liveRemoteRoute)
        #expect(snapshot.remoteShadowRoute == .internet)
    }

    @Test
    func degradedRemoteRouteMarksRemoteShadowAsFailed() {
        let snapshot = XTFirstPairCompletionProofBuilder.build(
            input: XTFirstPairCompletionProofBuildInput(
                generatedAt: Date(timeIntervalSince1970: 1_741_300_340),
                localConnected: false,
                remoteConnected: false,
                remoteRoute: .none,
                cachedProfile: sampleCachedRemoteProfile(),
                freshPairReconnectSmokeSnapshot: XTFreshPairReconnectSmokeSnapshot(
                    source: .startupAutomaticFirstPair,
                    status: .failed,
                    triggeredAtMs: 1_741_300_200_000,
                    completedAtMs: 1_741_300_210_000,
                    route: .none,
                    reasonCode: "grpc_unavailable",
                    summary: "cached route degraded"
                ),
                remoteShadowReconnectSmokeSnapshot: XTRemoteShadowReconnectSmokeSnapshot(
                    source: .dedicatedStableRemoteProbe,
                    status: .failed,
                    triggeredAtMs: 1_741_300_220_000,
                    completedAtMs: 1_741_300_221_000,
                    route: .internet,
                    reasonCode: "grpc_unavailable",
                    summary: "stable remote route shadow verification failed."
                ),
                pairedRouteSetSnapshot: samplePairedRouteSetSnapshot(readiness: .remoteDegraded)
            )
        )

        #expect(snapshot.readiness == .remoteDegraded)
        #expect(snapshot.remoteShadowSmokeStatus == .failed)
        #expect(snapshot.remoteShadowSmokePassed == false)
        #expect(snapshot.remoteShadowSmokeSource == .dedicatedStableRemoteProbe)
        #expect(snapshot.remoteShadowReasonCode == "grpc_unavailable")
        #expect(snapshot.remoteShadowSummary == "stable remote route shadow verification failed.")
    }

    @Test
    func runningRemoteShadowSmokeStaysInProgress() {
        let snapshot = XTFirstPairCompletionProofBuilder.build(
            input: XTFirstPairCompletionProofBuildInput(
                generatedAt: Date(timeIntervalSince1970: 1_741_300_360),
                localConnected: false,
                remoteConnected: false,
                remoteRoute: .none,
                cachedProfile: sampleCachedRemoteProfile(),
                freshPairReconnectSmokeSnapshot: XTFreshPairReconnectSmokeSnapshot(
                    source: .startupAutomaticFirstPair,
                    status: .succeeded,
                    triggeredAtMs: 1_741_300_300_000,
                    completedAtMs: 1_741_300_310_000,
                    route: .lan,
                    reasonCode: nil,
                    summary: "cached route verified"
                ),
                remoteShadowReconnectSmokeSnapshot: XTRemoteShadowReconnectSmokeSnapshot(
                    source: .dedicatedStableRemoteProbe,
                    status: .running,
                    triggeredAtMs: 1_741_300_320_000,
                    completedAtMs: 0,
                    route: .internet,
                    reasonCode: nil,
                    summary: "verifying stable remote route shadow path ..."
                ),
                pairedRouteSetSnapshot: samplePairedRouteSetSnapshot(readiness: .localReady)
            )
        )

        #expect(snapshot.readiness == .localReady)
        #expect(snapshot.remoteShadowSmokeStatus == .running)
        #expect(snapshot.remoteShadowSmokePassed == false)
        #expect(snapshot.remoteShadowSmokeSource == .dedicatedStableRemoteProbe)
    }
}

private func sampleCachedRemoteProfile() -> HubAIClient.CachedRemoteProfile {
    HubAIClient.CachedRemoteProfile(
        host: "10.0.0.8",
        internetHost: "hub.tailnet.example",
        pairingPort: 50052,
        grpcPort: 50051,
        hubInstanceID: "hub-1",
        lanDiscoveryName: "Hub"
    )
}

private func samplePairedRouteSetSnapshot(readiness: XTPairedRouteReadiness) -> XTPairedRouteSetSnapshot {
    XTPairedRouteSetSnapshot(
        readiness: readiness,
        readinessReasonCode: readiness.rawValue,
        summaryLine: "paired route set",
        hubInstanceID: "hub-1",
        activeRoute: nil,
        lanRoute: XTPairedRouteTargetSnapshot(
            routeKind: .lan,
            host: "10.0.0.8",
            pairingPort: 50052,
            grpcPort: 50051,
            hostKind: "private_ipv4",
            source: .cachedProfileHost
        ),
        stableRemoteRoute: XTPairedRouteTargetSnapshot(
            routeKind: .internet,
            host: "hub.tailnet.example",
            pairingPort: 50052,
            grpcPort: 50051,
            hostKind: "stable_named",
            source: .cachedProfileInternetHost
        ),
        lastKnownGoodRoute: XTPairedRouteTargetSnapshot(
            routeKind: .lan,
            host: "10.0.0.8",
            pairingPort: 50052,
            grpcPort: 50051,
            hostKind: "private_ipv4",
            source: .cachedProfileHost
        ),
        cachedReconnectSmokeStatus: nil,
        cachedReconnectSmokeReasonCode: nil,
        cachedReconnectSmokeSummary: nil
    )
}
