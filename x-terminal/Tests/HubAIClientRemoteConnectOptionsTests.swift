import Foundation
import Testing
@testable import XTerminal

@Suite(.serialized)
struct HubAIClientRemoteConnectOptionsTests {
    @Test
    func remoteConnectOptionsFallbackToCachedInternetHost() throws {
        let tempDir = try makeTempStateDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try writePairingEnv(
            at: tempDir,
            contents: """
            AXHUB_HUB_HOST='192.168.0.10'
            AXHUB_INTERNET_HOST='hub.tailnet.example'
            AXHUB_PAIRING_PORT='50052'
            AXHUB_GRPC_PORT='50051'
            """
        )

        try withHubRemoteDefaultsCleared {
            let options = HubAIClient.remoteConnectOptionsFromDefaults(stateDir: tempDir)
            #expect(options.internetHost == "hub.tailnet.example")
            #expect(options.pairingPort == 50052)
            #expect(options.grpcPort == 50051)
        }
    }

    @Test
    func remoteConnectOptionsDoNotInferRawIPv4AsReusableInternetHost() throws {
        let tempDir = try makeTempStateDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try writePairingEnv(
            at: tempDir,
            contents: """
            AXHUB_HUB_HOST='100.96.10.8'
            AXHUB_PAIRING_PORT='50052'
            AXHUB_GRPC_PORT='50051'
            """
        )

        try withHubRemoteDefaultsCleared {
            let options = HubAIClient.remoteConnectOptionsFromDefaults(stateDir: tempDir)
            #expect(options.internetHost.isEmpty)
        }
    }

    @Test
    func remoteConnectOptionsDoNotPromoteCorporateLanIpToInternetHostWhenHubIdentityWasDiscovered() throws {
        let tempDir = try makeTempStateDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try writePairingEnv(
            at: tempDir,
            contents: """
            AXHUB_HUB_HOST='17.81.12.12'
            AXHUB_HUB_INSTANCE_ID='hub_deadbeefcafefeed00'
            AXHUB_LAN_DISCOVERY_NAME='axhub-edge-bj'
            AXHUB_PAIRING_PORT='50053'
            AXHUB_GRPC_PORT='50052'
            """
        )

        try withHubRemoteDefaultsCleared {
            let options = HubAIClient.remoteConnectOptionsFromDefaults(stateDir: tempDir)
            #expect(options.internetHost.isEmpty)
            #expect(options.pairingPort == 50053)
            #expect(options.grpcPort == 50052)
        }
    }

    @Test
    func remoteConnectOptionsPreferCurrentConnectionStateOverStalePairingAndDefaults() throws {
        let tempDir = try makeTempStateDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try writePairingEnv(
            at: tempDir,
            contents: """
            AXHUB_HUB_HOST='17.81.10.243'
            AXHUB_INTERNET_HOST='17.81.10.243'
            AXHUB_HUB_INSTANCE_ID='hub_33bdbcae9a4fa1cb9c27'
            AXHUB_LAN_DISCOVERY_NAME='axhub-33bdbcae9a'
            AXHUB_PAIRING_PORT='50055'
            AXHUB_GRPC_PORT='50054'
            """
        )
        try writeHubEnv(
            at: tempDir,
            contents: """
            export HUB_HOST='17.81.11.116'
            export HUB_PORT='50053'
            export HUB_CLIENT_TOKEN='tok_current'
            """
        )
        try writeConnectionJSON(
            at: tempDir,
            contents: """
            {
              "schema_version": "axhub_connection.v1",
              "hub_host": "17.81.11.116",
              "grpc_port": 50053,
              "pairing_port": 50054
            }
            """
        )

        try withHubRemoteDefaultsCleared {
            let defaults = UserDefaults.standard
            defaults.set(50052, forKey: "xterminal_hub_pairing_port")
            defaults.set(50051, forKey: "xterminal_hub_grpc_port")
            defaults.set("17.81.11.116", forKey: "xterminal_hub_internet_host")

            let options = HubAIClient.remoteConnectOptionsFromDefaults(stateDir: tempDir)
            #expect(options.internetHost == "17.81.11.116")
            #expect(options.pairingPort == 50054)
            #expect(options.grpcPort == 50053)
        }
    }

    @Test
    func remoteConnectOptionsPreserveExplicitEndpointOverrideWhileRepairIsPending() throws {
        let tempDir = try makeTempStateDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try writePairingEnv(
            at: tempDir,
            contents: """
            AXHUB_HUB_HOST='ortdemac-mini.local'
            AXHUB_INTERNET_HOST='192.168.10.101'
            AXHUB_PAIRING_PORT='50053'
            AXHUB_GRPC_PORT='50052'
            """
        )
        try writeConnectionJSON(
            at: tempDir,
            contents: """
            {
              "schema_version": "axhub_connection.v1",
              "hub_host": "192.168.10.101",
              "grpc_port": 50052,
              "pairing_port": 50053
            }
            """
        )

        try withHubRemoteDefaultsCleared {
            let defaults = UserDefaults.standard
            defaults.set(50054, forKey: "xterminal_hub_pairing_port")
            defaults.set(50053, forKey: "xterminal_hub_grpc_port")
            defaults.set("17.81.11.116", forKey: "xterminal_hub_internet_host")
            defaults.set(true, forKey: "xterminal_hub_remote_endpoint_override_pending")

            let options = HubAIClient.remoteConnectOptionsFromDefaults(stateDir: tempDir)
            #expect(options.internetHost == "17.81.11.116")
            #expect(options.pairingPort == 50054)
            #expect(options.grpcPort == 50053)
            #expect(options.configuredEndpointIsAuthoritative == true)
        }
    }

    @Test
    func remoteConnectOptionsPreserveStableNamedInternetHostAcrossConnectionHostChanges() throws {
        let tempDir = try makeTempStateDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try writePairingEnv(
            at: tempDir,
            contents: """
            AXHUB_HUB_HOST='192.168.0.10'
            AXHUB_INTERNET_HOST='hub.tailnet.example'
            AXHUB_HUB_INSTANCE_ID='hub_33bdbcae9a4fa1cb9c27'
            AXHUB_PAIRING_PORT='50054'
            AXHUB_GRPC_PORT='50053'
            """
        )
        try writeConnectionJSON(
            at: tempDir,
            contents: """
            {
              "schema_version": "axhub_connection.v1",
              "hub_host": "100.96.10.8",
              "grpc_port": 50053,
              "pairing_port": 50054
            }
            """
        )

        try withHubRemoteDefaultsCleared {
            let options = HubAIClient.remoteConnectOptionsFromDefaults(stateDir: tempDir)
            #expect(options.internetHost == "hub.tailnet.example")
            #expect(options.pairingPort == 50054)
            #expect(options.grpcPort == 50053)
        }
    }

    @Test
    func remoteConnectOptionsLoadInviteTokenFromDefaults() throws {
        let tempDir = try makeTempStateDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try withHubRemoteDefaultsCleared {
            let defaults = UserDefaults.standard
            defaults.set("axhub_invite_test_123", forKey: "xterminal_hub_invite_token")

            let options = HubAIClient.remoteConnectOptionsFromDefaults(stateDir: tempDir)
            #expect(options.inviteToken == "axhub_invite_test_123")
        }
    }

    @Test
    func remoteConnectOptionsLoadInviteIdentityHintsFromDefaults() throws {
        let tempDir = try makeTempStateDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try withHubRemoteDefaultsCleared {
            let defaults = UserDefaults.standard
            defaults.set("ops-main", forKey: "xterminal_hub_invite_alias")
            defaults.set("hub_deadbeefcafefeed00", forKey: "xterminal_hub_invite_instance_id")

            let options = HubAIClient.remoteConnectOptionsFromDefaults(stateDir: tempDir)
            #expect(options.inviteAlias == "ops-main")
            #expect(options.inviteInstanceID == "hub_deadbeefcafefeed00")
        }
    }

    @Test
    func cachedRemoteProfileCarriesPairingEpochAndRoutePackVersionIntoPairedRouteSet() throws {
        let tempDir = try makeTempStateDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try writePairingEnv(
            at: tempDir,
            contents: """
            AXHUB_HUB_HOST='192.168.0.10'
            AXHUB_INTERNET_HOST='hub.tailnet.example'
            AXHUB_PAIRING_PORT='50052'
            AXHUB_GRPC_PORT='50051'
            AXHUB_HUB_INSTANCE_ID='hub_epoch_route'
            AXHUB_LAN_DISCOVERY_NAME='axhub-lan'
            AXHUB_PAIRING_PROFILE_EPOCH='7'
            AXHUB_ROUTE_PACK_VERSION='route_pack_old'
            """
        )
        try writeConnectionJSON(
            at: tempDir,
            contents: """
            {
              "schema_version": "axhub_connection.v1",
              "hub_host": "192.168.0.10",
              "grpc_port": 50051,
              "pairing_port": 50052,
              "pairing_profile_epoch": 11,
              "route_pack_version": "route_pack_live"
            }
            """
        )

        let cached = HubAIClient.cachedRemoteProfile(stateDir: tempDir)
        #expect(cached.pairingProfileEpoch == 11)
        #expect(cached.routePackVersion == "route_pack_live")

        let snapshot = XTPairedRouteSetSnapshotBuilder.build(
            input: makePairedRouteSetBuildInput(cachedProfile: cached)
        )

        #expect(snapshot.pairingProfileEpoch == 11)
        #expect(snapshot.routePackVersion == "route_pack_live")
    }

    @Test
    func pairedRouteSetMarksStableNamedEntryAsRemoteReadyAfterRemoteSmokePass() {
        let snapshot = XTPairedRouteSetSnapshotBuilder.build(
            input: makePairedRouteSetBuildInput(
                cachedProfile: HubAIClient.CachedRemoteProfile(
                    host: "192.168.0.10",
                    internetHost: "hub.tailnet.example",
                    pairingPort: 50052,
                    grpcPort: 50051,
                    hubInstanceID: "hub_abc123",
                    lanDiscoveryName: "axhub-lan"
                ),
                freshPairReconnectSmokeSnapshot: makeReconnectSmokeSnapshot(
                    status: .succeeded,
                    route: .internet,
                    reasonCode: nil
                )
            )
        )

        #expect(snapshot.readiness == .remoteReady)
        #expect(snapshot.readinessReasonCode == "cached_remote_reconnect_smoke_verified")
        #expect(snapshot.summaryLine == "正式异网入口已验证，切网后可继续重连。")
        #expect(snapshot.stableRemoteRoute?.host == "hub.tailnet.example")
        #expect(snapshot.lastKnownGoodRoute?.routeKind == .internet)
    }

    @Test
    func pairedRouteSetKeepsLanOnlyProfilesAtLocalReady() {
        let snapshot = XTPairedRouteSetSnapshotBuilder.build(
            input: makePairedRouteSetBuildInput(
                cachedProfile: HubAIClient.CachedRemoteProfile(
                    host: "192.168.0.10",
                    internetHost: nil,
                    pairingPort: 50052,
                    grpcPort: 50051,
                    hubInstanceID: "hub_lanonly",
                    lanDiscoveryName: "axhub-lan"
                ),
                freshPairReconnectSmokeSnapshot: makeReconnectSmokeSnapshot(
                    status: .succeeded,
                    route: .lan,
                    reasonCode: nil
                )
            )
        )

        #expect(snapshot.readiness == .localReady)
        #expect(snapshot.readinessReasonCode == "local_pairing_ready")
        #expect(snapshot.summaryLine == "当前已完成同网首配，但还没有正式异网入口。")
        #expect(snapshot.lanRoute?.host == "192.168.0.10")
        #expect(snapshot.stableRemoteRoute == nil)
    }

    @Test
    func pairedRouteSetMarksStableNamedEntryAsRemoteBlockedForInviteTokenInvalid() {
        let snapshot = XTPairedRouteSetSnapshotBuilder.build(
            input: makePairedRouteSetBuildInput(
                cachedProfile: HubAIClient.CachedRemoteProfile(
                    host: "192.168.0.10",
                    internetHost: "hub.tailnet.example",
                    pairingPort: 50052,
                    grpcPort: 50051,
                    hubInstanceID: "hub_blocked",
                    lanDiscoveryName: "axhub-lan"
                ),
                failureCode: "invite_token_invalid"
            )
        )

        #expect(snapshot.readiness == .remoteBlocked)
        #expect(snapshot.readinessReasonCode == "remote_pairing_or_identity_blocked")
        #expect(snapshot.summaryLine == "正式异网入口已存在，但当前被配对/身份边界阻断。")
        #expect(snapshot.stableRemoteRoute?.host == "hub.tailnet.example")
    }

    @Test
    func pairedRouteSetMarksStableNamedEntryAsRemoteBlockedForStalePairingMetadata() {
        let snapshot = XTPairedRouteSetSnapshotBuilder.build(
            input: makePairedRouteSetBuildInput(
                cachedProfile: HubAIClient.CachedRemoteProfile(
                    host: "192.168.0.10",
                    internetHost: "hub.tailnet.example",
                    pairingPort: 50052,
                    grpcPort: 50051,
                    hubInstanceID: "hub_blocked",
                    lanDiscoveryName: "axhub-lan",
                    pairingProfileEpoch: 7,
                    routePackVersion: "route_pack_old"
                ),
                failureCode: "pairing_profile_epoch_stale"
            )
        )

        #expect(snapshot.readiness == .remoteBlocked)
        #expect(snapshot.readinessReasonCode == "remote_pairing_or_identity_blocked")
        #expect(snapshot.stableRemoteRoute?.host == "hub.tailnet.example")
    }

    @Test
    func pairedRouteSetMarksStableNamedEntryAsRemoteDegradedAfterShadowSmokeFailure() {
        let snapshot = XTPairedRouteSetSnapshotBuilder.build(
            input: makePairedRouteSetBuildInput(
                cachedProfile: HubAIClient.CachedRemoteProfile(
                    host: "192.168.0.10",
                    internetHost: "hub.tailnet.example",
                    pairingPort: 50052,
                    grpcPort: 50051,
                    hubInstanceID: "hub_degraded",
                    lanDiscoveryName: "axhub-lan"
                ),
                freshPairReconnectSmokeSnapshot: makeReconnectSmokeSnapshot(
                    status: .succeeded,
                    route: .lan,
                    reasonCode: nil
                ),
                remoteShadowReconnectSmokeSnapshot: makeRemoteShadowSmokeSnapshot(
                    status: .failed,
                    route: .internet,
                    reasonCode: "grpc_unavailable"
                )
            )
        )

        #expect(snapshot.readiness == .remoteDegraded)
        #expect(snapshot.readinessReasonCode == "remote_shadow_smoke_failed")
        #expect(snapshot.summaryLine == "正式异网入口已存在，但最近一次异网验证未通过。")
    }

    @Test
    func pairedRouteSetMarksStableNamedEntryAsRemoteBlockedWhenShadowSmokeHitsBoundary() {
        let snapshot = XTPairedRouteSetSnapshotBuilder.build(
            input: makePairedRouteSetBuildInput(
                cachedProfile: HubAIClient.CachedRemoteProfile(
                    host: "192.168.0.10",
                    internetHost: "hub.tailnet.example",
                    pairingPort: 50052,
                    grpcPort: 50051,
                    hubInstanceID: "hub_shadow_blocked",
                    lanDiscoveryName: "axhub-lan"
                ),
                freshPairReconnectSmokeSnapshot: makeReconnectSmokeSnapshot(
                    status: .succeeded,
                    route: .lan,
                    reasonCode: nil
                ),
                remoteShadowReconnectSmokeSnapshot: makeRemoteShadowSmokeSnapshot(
                    status: .failed,
                    route: .internet,
                    reasonCode: "mtls_client_certificate_required"
                )
            )
        )

        #expect(snapshot.readiness == .remoteBlocked)
        #expect(snapshot.readinessReasonCode == "remote_pairing_or_identity_blocked")
    }

    @Test
    func pairedRouteSetDoesNotPromoteRawIPv4ToStableRemoteRoute() {
        let snapshot = XTPairedRouteSetSnapshotBuilder.build(
            input: makePairedRouteSetBuildInput(
                cachedProfile: HubAIClient.CachedRemoteProfile(
                    host: "17.81.10.243",
                    internetHost: nil,
                    pairingPort: 50052,
                    grpcPort: 50051,
                    hubInstanceID: "hub_rawip",
                    lanDiscoveryName: nil
                ),
                configuredInternetHost: "17.81.10.243"
            )
        )

        #expect(snapshot.stableRemoteRoute == nil)
        #expect(snapshot.readiness == .unknown)
        #expect(snapshot.summaryLine == "尚未拿到可判定的已配对路径集合。")
    }

    private func makeTempStateDir() throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("hub_ai_client_remote_options_tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func writePairingEnv(at dir: URL, contents: String) throws {
        try contents.write(
            to: dir.appendingPathComponent("pairing.env"),
            atomically: true,
            encoding: .utf8
        )
    }

    private func writeHubEnv(at dir: URL, contents: String) throws {
        try contents.write(
            to: dir.appendingPathComponent("hub.env"),
            atomically: true,
            encoding: .utf8
        )
    }

    private func writeConnectionJSON(at dir: URL, contents: String) throws {
        try contents.write(
            to: dir.appendingPathComponent("connection.json"),
            atomically: true,
            encoding: .utf8
        )
    }

    private func withHubRemoteDefaultsCleared(_ body: () throws -> Void) throws {
        let defaults = UserDefaults.standard
        let keys = [
            "xterminal_hub_pairing_port",
            "xterminal_hub_grpc_port",
            "xterminal_hub_internet_host",
            "xterminal_hub_remote_endpoint_override_pending",
            "xterminal_hub_invite_token",
            "xterminal_hub_axhubctl_path",
        ]
        let previous = keys.reduce(into: [String: Any?]()) { partialResult, key in
            partialResult[key] = defaults.object(forKey: key)
            defaults.removeObject(forKey: key)
        }
        defer {
            for key in keys {
                if let value = previous[key] ?? nil {
                    defaults.set(value, forKey: key)
                } else {
                    defaults.removeObject(forKey: key)
                }
            }
        }
        try body()
    }

    private func makePairedRouteSetBuildInput(
        cachedProfile: HubAIClient.CachedRemoteProfile,
        configuredInternetHost: String = "",
        failureCode: String = "",
        freshPairReconnectSmokeSnapshot: XTFreshPairReconnectSmokeSnapshot? = nil,
        remoteShadowReconnectSmokeSnapshot: XTRemoteShadowReconnectSmokeSnapshot? = nil
    ) -> XTPairedRouteSetBuildInput {
        XTPairedRouteSetBuildInput(
            cachedProfile: cachedProfile,
            configuredInternetHost: configuredInternetHost,
            configuredHubInstanceID: cachedProfile.hubInstanceID,
            pairingPort: cachedProfile.pairingPort ?? 50052,
            grpcPort: cachedProfile.grpcPort ?? 50051,
            localConnected: false,
            remoteConnected: false,
            remoteRoute: .none,
            linking: false,
            failureCode: failureCode,
            freshPairReconnectSmokeSnapshot: freshPairReconnectSmokeSnapshot,
            remoteShadowReconnectSmokeSnapshot: remoteShadowReconnectSmokeSnapshot
        )
    }

    private func makeReconnectSmokeSnapshot(
        status: XTFreshPairReconnectSmokeStatus,
        route: HubRemoteRoute,
        reasonCode: String?
    ) -> XTFreshPairReconnectSmokeSnapshot {
        XTFreshPairReconnectSmokeSnapshot(
            source: .manualOneClickSetup,
            status: status,
            triggeredAtMs: 1_741_300_010_000,
            completedAtMs: 1_741_300_011_000,
            route: route,
            reasonCode: reasonCode,
            summary: reasonCode ?? status.rawValue
        )
    }

    private func makeRemoteShadowSmokeSnapshot(
        status: XTRemoteShadowReconnectSmokeStatus,
        route: HubRemoteRoute,
        reasonCode: String?
    ) -> XTRemoteShadowReconnectSmokeSnapshot {
        XTRemoteShadowReconnectSmokeSnapshot(
            source: .dedicatedStableRemoteProbe,
            status: status,
            triggeredAtMs: 1_741_300_012_000,
            completedAtMs: status == .running ? 0 : 1_741_300_013_000,
            route: route,
            reasonCode: reasonCode,
            summary: reasonCode ?? status.rawValue
        )
    }
}
