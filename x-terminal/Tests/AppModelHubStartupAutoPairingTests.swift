import Testing
@testable import XTerminal

struct AppModelHubStartupAutoPairingTests {
    @Test
    func startupStaysIdleForFreshInstallUntilUserStartsPairing() {
        let disposition = AppModel.startupAutomaticConnectDisposition(
            hasHubEnv: false,
            internetHost: "",
            inviteToken: "",
            inviteAlias: "",
            inviteInstanceID: ""
        )

        #expect(disposition == .none)
    }

    @Test
    func startupUsesConnectOnlyRecoveryWhenHubEnvExists() {
        let disposition = AppModel.startupAutomaticConnectDisposition(
            hasHubEnv: true,
            internetHost: "",
            inviteToken: "",
            inviteAlias: "",
            inviteInstanceID: ""
        )

        #expect(disposition == .recoverExistingProfile(allowBootstrap: false))
    }

    @Test
    func startupUsesAutomaticFirstPairWhenInviteTokenAndInternetHostExist() {
        let disposition = AppModel.startupAutomaticConnectDisposition(
            hasHubEnv: false,
            internetHost: "hub.tailnet.example",
            inviteToken: "axhub_invite_test_123",
            inviteAlias: "",
            inviteInstanceID: ""
        )

        #expect(disposition == .firstPairNearby)
    }

    @Test
    func startupUsesAutomaticFirstPairWhenInviteTokenAndHubIdentityHintsExist() {
        let disposition = AppModel.startupAutomaticConnectDisposition(
            hasHubEnv: false,
            internetHost: "",
            inviteToken: "axhub_invite_test_123",
            inviteAlias: "ops-main",
            inviteInstanceID: "hub_deadbeefcafefeed00"
        )

        #expect(disposition == .firstPairNearby)
    }

    @Test
    func startupDoesNotAutoBootstrapFromPartialInviteMetadataWithoutHubEnv() {
        let hostOnlyDisposition = AppModel.startupAutomaticConnectDisposition(
            hasHubEnv: false,
            internetHost: "hub.tailnet.example",
            inviteToken: "",
            inviteAlias: "",
            inviteInstanceID: ""
        )
        let tokenOnlyDisposition = AppModel.startupAutomaticConnectDisposition(
            hasHubEnv: false,
            internetHost: "",
            inviteToken: "axhub_invite_test_123",
            inviteAlias: "",
            inviteInstanceID: ""
        )

        #expect(hostOnlyDisposition == .none)
        #expect(tokenOnlyDisposition == .none)
    }

    @Test
    func automaticFirstPairRepairContextUsesApprovalSpecificCopyForTimeout() {
        let context = AppModel.automaticFirstPairRepairContext(for: "pairing_approval_timeout")

        #expect(context.title == "在 Hub 上批准这次首次配对")
        #expect(context.detail.contains("等待本机 owner 批准时超时"))
    }

    @Test
    func automaticFirstPairRepairContextUsesOwnerAuthSpecificCopyForCancelledApproval() {
        let context = AppModel.automaticFirstPairRepairContext(for: "pairing_owner_auth_cancelled")

        #expect(context.title == "回到 Hub 重新确认首次配对")
        #expect(context.detail.contains("本机 owner 验证被取消"))
    }

    @Test
    func automaticFirstPairRepairContextExplainsMissingFormalRemoteEntry() {
        let context = AppModel.automaticFirstPairRepairContext(
            for: "grpc_unavailable",
            internetHost: ""
        )

        #expect(context.title == "先补正式远端入口，再继续连接")
        #expect(context.detail.contains("正式 Internet Host"))
        #expect(context.detail.contains("同一 Wi‑Fi"))
    }

    @Test
    func automaticFirstPairRepairContextExplainsRawIPAndStableNamedFailuresDifferently() {
        let rawIPContext = AppModel.automaticFirstPairRepairContext(
            for: "grpc_unavailable",
            internetHost: "17.81.11.116"
        )
        let stableNamedContext = AppModel.automaticFirstPairRepairContext(
            for: "grpc_unavailable",
            internetHost: "hub.tailnet.example"
        )

        #expect(rawIPContext.title == "先替换临时 raw IP 入口")
        #expect(rawIPContext.detail.contains("17.81.11.116"))
        #expect(rawIPContext.detail.contains("raw IP"))

        #expect(stableNamedContext.title == "Hub 远端入口已配置，先检查服务是否在线")
        #expect(stableNamedContext.detail.contains("hub.tailnet.example"))
        #expect(stableNamedContext.detail.contains("pairing / gRPC"))
    }

    @Test
    func automaticFirstPairRepairContextExplainsLocalNetworkDiscoveryBlock() {
        let context = AppModel.automaticFirstPairRepairContext(
            for: "local_network_permission_required",
            internetHost: ""
        )

        #expect(context.title == "先允许 XT 访问本地网络")
        #expect(context.detail.contains("本地网络"))
        #expect(context.detail.contains("client isolation"))
    }

    @Test
    func automaticFirstPairReconnectSmokeOnlyRunsAfterFreshPairSuccess() {
        #expect(
            AppModel.shouldRunAutomaticFirstPairReconnectSmoke(
                after: HubRemoteConnectReport(
                    ok: true,
                    route: .lan,
                    summary: "connected",
                    logLines: [],
                    reasonCode: nil,
                    completedFreshPairing: true
                )
            )
        )

        #expect(
            !AppModel.shouldRunAutomaticFirstPairReconnectSmoke(
                after: HubRemoteConnectReport(
                    ok: true,
                    route: .lan,
                    summary: "connected",
                    logLines: [],
                    reasonCode: nil,
                    completedFreshPairing: false
                )
            )
        )

        #expect(
            !AppModel.shouldRunAutomaticFirstPairReconnectSmoke(
                after: HubRemoteConnectReport(
                    ok: false,
                    route: .none,
                    summary: "failed",
                    logLines: [],
                    reasonCode: "grpc_unavailable",
                    completedFreshPairing: true
                )
            )
        )
    }

    @Test
    func freshPairReconnectSmokeUsesSharedEligibilityForManualAndStartupFlows() {
        let report = HubRemoteConnectReport(
            ok: true,
            route: .lan,
            summary: "connected",
            logLines: [],
            reasonCode: nil,
            completedFreshPairing: true
        )

        #expect(AppModel.shouldRunFreshPairReconnectSmoke(after: report))
        #expect(AppModel.shouldRunAutomaticFirstPairReconnectSmoke(after: report))
    }

    @Test
    func remoteShadowReconnectSmokeRequiresFreshPairSuccessAndStableRemoteRoute() {
        let report = HubRemoteConnectReport(
            ok: true,
            route: .lan,
            summary: "connected",
            logLines: [],
            reasonCode: nil,
            completedFreshPairing: true
        )
        let pairedRouteSet = XTPairedRouteSetSnapshot(
            readiness: .localReady,
            readinessReasonCode: "local_pairing_ready_remote_unverified",
            summaryLine: "local ready",
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
            lastKnownGoodRoute: nil,
            cachedReconnectSmokeStatus: "succeeded",
            cachedReconnectSmokeReasonCode: nil,
            cachedReconnectSmokeSummary: "cached route verified"
        )

        #expect(
            AppModel.shouldRunRemoteShadowReconnectSmoke(
                after: report,
                pairedRouteSetSnapshot: pairedRouteSet,
                existingSnapshot: nil
            )
        )
        #expect(
            !AppModel.shouldRunRemoteShadowReconnectSmoke(
                after: nil,
                pairedRouteSetSnapshot: pairedRouteSet,
                existingSnapshot: nil
            )
        )
        #expect(
            !AppModel.shouldRunRemoteShadowReconnectSmoke(
                after: report,
                pairedRouteSetSnapshot: XTPairedRouteSetSnapshot(
                    readiness: .localReady,
                    readinessReasonCode: "local_pairing_ready",
                    summaryLine: "local ready",
                    hubInstanceID: "hub-1",
                    activeRoute: nil,
                    lanRoute: pairedRouteSet.lanRoute,
                    stableRemoteRoute: nil,
                    lastKnownGoodRoute: nil,
                    cachedReconnectSmokeStatus: nil,
                    cachedReconnectSmokeReasonCode: nil,
                    cachedReconnectSmokeSummary: nil
                ),
                existingSnapshot: nil
            )
        )
    }

    @Test
    func remoteShadowReconnectSmokeSkipsWhenAlreadyRunningOrPassed() {
        let report = HubRemoteConnectReport(
            ok: true,
            route: .lan,
            summary: "connected",
            logLines: [],
            reasonCode: nil,
            completedFreshPairing: true
        )
        let pairedRouteSet = XTPairedRouteSetSnapshot(
            readiness: .localReady,
            readinessReasonCode: "local_pairing_ready_remote_unverified",
            summaryLine: "local ready",
            hubInstanceID: "hub-1",
            activeRoute: nil,
            lanRoute: nil,
            stableRemoteRoute: XTPairedRouteTargetSnapshot(
                routeKind: .internet,
                host: "hub.tailnet.example",
                pairingPort: 50052,
                grpcPort: 50051,
                hostKind: "stable_named",
                source: .cachedProfileInternetHost
            ),
            lastKnownGoodRoute: nil,
            cachedReconnectSmokeStatus: nil,
            cachedReconnectSmokeReasonCode: nil,
            cachedReconnectSmokeSummary: nil
        )

        #expect(
            !AppModel.shouldRunRemoteShadowReconnectSmoke(
                after: report,
                pairedRouteSetSnapshot: pairedRouteSet,
                existingSnapshot: XTRemoteShadowReconnectSmokeSnapshot(
                    source: .dedicatedStableRemoteProbe,
                    status: .running,
                    triggeredAtMs: 1_741_300_100_000,
                    completedAtMs: 0,
                    route: .internet,
                    reasonCode: nil,
                    summary: "running"
                )
            )
        )
        #expect(
            !AppModel.shouldRunRemoteShadowReconnectSmoke(
                after: report,
                pairedRouteSetSnapshot: pairedRouteSet,
                existingSnapshot: XTRemoteShadowReconnectSmokeSnapshot(
                    source: .dedicatedStableRemoteProbe,
                    status: .succeeded,
                    triggeredAtMs: 1_741_300_100_000,
                    completedAtMs: 1_741_300_101_000,
                    route: .internet,
                    reasonCode: nil,
                    summary: "passed"
                )
            )
        )
    }
}
