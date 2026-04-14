import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
import Testing
@testable import XTerminal

struct HubPairingCoordinatorTests {
    @Test
    func normalizedRemoteReasonCodeCollapsesRawGRPCUnavailable() {
        let reason = HubPairingCoordinator.normalizedRemoteReasonCodeForTesting(
            "14_UNAVAILABLE:_No_connection_established._Last_error:_null._Resolution_note:"
        )

        #expect(reason == "grpc_unavailable")
    }

    @Test
    func normalizedRemoteReasonCodePreservesCanonicalTokens() {
        let reason = HubPairingCoordinator.normalizedRemoteReasonCodeForTesting("grant_required")
        #expect(reason == "grant_required")
    }

    @Test
    func inferFailureCodeMapsPairingApprovalTimeout() {
        let reason = HubPairingCoordinator.inferFailureCodeForTesting(
            from: "axhubctl: timeout waiting for approval (900s)",
            fallback: "bootstrap_failed"
        )

        #expect(reason == "pairing_approval_timeout")
    }

    @Test
    func inferFailureCodeMapsOwnerAuthCancelled() {
        let reason = HubPairingCoordinator.inferFailureCodeForTesting(
            from: "Local owner approval was cancelled. The pairing request stays pending.",
            fallback: "bootstrap_failed"
        )

        #expect(reason == "pairing_owner_auth_cancelled")
    }

    @Test
    func inferFailureCodeMapsOwnerAuthFailure() {
        let reason = HubPairingCoordinator.inferFailureCodeForTesting(
            from: "Local owner authentication failed. The pairing request stays pending.",
            fallback: "bootstrap_failed"
        )

        #expect(reason == "pairing_owner_auth_failed")
    }

    @Test
    func inferFailureCodeMapsChineseExpiredProviderToken() {
        let reason = HubPairingCoordinator.inferFailureCodeForTesting(
            from: "[done] ok=false reason=该令牌已过期 (request id: 2026032417115184017227795754592)",
            fallback: "remote_chat_failed"
        )

        #expect(reason == "provider_token_expired")
    }

    @Test
    func inferFailureCodeMapsConnectETimedOutToTCPTimeout() {
        let reason = HubPairingCoordinator.inferFailureCodeForTesting(
            from: "Probe error: list-models failed: 14 UNAVAILABLE: No connection established. Last error: Error: connect ETIMEDOUT 17.81.11.116:50053.",
            fallback: "connect_failed"
        )

        #expect(reason == "tcp_timeout")
    }

    @Test
    func inferFailureCodeMapsConnectECONNREFUSEDToConnectionRefused() {
        let reason = HubPairingCoordinator.inferFailureCodeForTesting(
            from: "Probe error: list-models failed: 14 UNAVAILABLE: No connection established. Last error: Error: connect ECONNREFUSED 127.0.0.1:50053.",
            fallback: "connect_failed"
        )

        #expect(reason == "connection_refused")
    }

    @Test
    func inferFailureCodeMapsLocalNetworkPermissionFailure() {
        let reason = HubPairingCoordinator.inferFailureCodeForTesting(
            from: "[lan-discover] local network access denied; X-Terminal needs Local Network permission to probe Hub endpoints.",
            fallback: "discover_failed"
        )

        #expect(reason == "local_network_permission_required")
    }

    @Test
    func fetchRemoteModelsUsesAuthoritativeInternetHostWhenHubEnvHostIsStale() async throws {
        let stateDir = try makeTempStateDir(prefix: "hub_remote_models_authoritative_host")
        defer { try? FileManager.default.removeItem(at: stateDir) }

        try writeFile(
            stateDir.appendingPathComponent("hub.env"),
            """
            export HUB_HOST='ortdemac-mini.local'
            export HUB_PORT='50052'
            export HUB_CLIENT_TOKEN='tok_current'
            """
        )

        let clientKitSrc = stateDir
            .appendingPathComponent("client_kit", isDirectory: true)
            .appendingPathComponent("hub_grpc_server", isDirectory: true)
            .appendingPathComponent("src", isDirectory: true)
        try FileManager.default.createDirectory(at: clientKitSrc, withIntermediateDirectories: true)
        try writeFile(
            clientKitSrc.appendingPathComponent("list_models_client.js"),
            """
            const fs = require('node:fs');
            const path = require('node:path');
            const stateDir = process.env.AXHUBCTL_STATE_DIR || process.cwd();
            fs.writeFileSync(
              path.join(stateDir, 'node_env.log'),
              `HUB_HOST=${process.env.HUB_HOST || ''}\\nHUB_PORT=${process.env.HUB_PORT || ''}\\n`
            );
            console.log(`Hub connected: ${process.env.HUB_HOST || 'unknown'}:${process.env.HUB_PORT || '0'}`);
            console.log('[paid-access] trust_profile_present=true paid_model_policy_mode=allow_all daily_token_limit=12000 single_request_token_limit=4000');
            console.log('Models: 2');
            console.log('- GLM 4.5 | glm/4.5 | MODEL_KIND_PAID_ONLINE | openai_compatible | MODEL_VISIBILITY_AVAILABLE');
            console.log('- Kimi K2 | kimi/k2 | MODEL_KIND_PAID_ONLINE | openai_compatible | MODEL_VISIBILITY_AVAILABLE');
            """
        )

        let result = await HubPairingCoordinator.shared.fetchRemoteModels(
            options: HubRemoteConnectOptions(
                grpcPort: 50052,
                pairingPort: 50053,
                deviceName: "Andrew.Xie Laptop",
                internetHost: "192.168.10.109",
                axhubctlPath: "",
                configuredEndpointIsAuthoritative: true,
                stateDir: stateDir
            )
        )

        #expect(result.ok == true)
        #expect(result.models.map(\.id) == ["glm/4.5", "kimi/k2"])

        let envLog = try String(
            contentsOf: stateDir.appendingPathComponent("node_env.log"),
            encoding: .utf8
        )
        #expect(envLog.contains("HUB_HOST=192.168.10.109"))
        #expect(envLog.contains("HUB_PORT=50052"))
    }

    @Test
    func synchronizeAuthoritativeRemoteEndpointArtifactsRealignsStaleStateFiles() async throws {
        let stateDir = try makeTempStateDir(prefix: "hub_remote_authoritative_sync")
        defer { try? FileManager.default.removeItem(at: stateDir) }

        try writeFile(
            stateDir.appendingPathComponent("pairing.env"),
            """
            AXHUB_HUB_HOST='ortdemac-mini.local'
            AXHUB_PAIRING_PORT='50053'
            AXHUB_GRPC_PORT='50052'
            AXHUB_APP_ID='x_terminal'
            AXHUB_DEVICE_NAME='Andrew.Xie Laptop'
            AXHUB_PAIRING_REQUEST_ID='req-1'
            AXHUB_PAIRING_SECRET='secret-1'
            AXHUB_INTERNET_HOST='192.168.10.109'
            AXHUB_HUB_INSTANCE_ID='hub_33bdbcae9a4fa1cb9c27'
            AXHUB_LAN_DISCOVERY_NAME='axhub-33bdbcae9a'
            AXHUB_PAIRING_PROFILE_EPOCH='13'
            AXHUB_ROUTE_PACK_VERSION='route_pack_live'
            """
        )
        try writeFile(
            stateDir.appendingPathComponent("hub.env"),
            """
            export HUB_HOST='ortdemac-mini.local'
            export HUB_PORT='50052'
            export HUB_CLIENT_TOKEN='tok_current'
            export HUB_DEVICE_ID='dev-1'
            export HUB_USER_ID='user-1'
            export HUB_APP_ID='x_terminal'
            export HUB_GRPC_TLS_MODE='tls'
            export HUB_GRPC_TLS_SERVER_NAME='axhub'
            export HUB_GRPC_TLS_CA_CERT_PATH='/tmp/ca.pem'
            """
        )
        try writeFile(
            stateDir.appendingPathComponent("connection.json"),
            """
            {
              "schema_version": "axhub_connection.v1",
              "hub_host": "ortdemac-mini.local",
              "grpc_port": 50052,
              "pairing_port": 50053,
              "pairing_profile_epoch": 13,
              "route_pack_version": "route_pack_live"
            }
            """
        )

        let logLines = await HubPairingCoordinator.shared.synchronizeAuthoritativeRemoteEndpointArtifactsForTesting(
            stateDir: stateDir,
            host: "192.168.10.109",
            pairingPort: 50053,
            grpcPort: 50052
        )

        #expect(logLines.contains { $0.contains("realigned to authoritative remote endpoint 192.168.10.109:50052") })

        let pairingEnv = try String(
            contentsOf: stateDir.appendingPathComponent("pairing.env"),
            encoding: .utf8
        )
        let hubEnv = try String(
            contentsOf: stateDir.appendingPathComponent("hub.env"),
            encoding: .utf8
        )
        let connectionJSON = try String(
            contentsOf: stateDir.appendingPathComponent("connection.json"),
            encoding: .utf8
        )

        #expect(pairingEnv.contains("AXHUB_HUB_HOST='192.168.10.109'"))
        #expect(pairingEnv.contains("AXHUB_INTERNET_HOST='192.168.10.109'"))
        #expect(pairingEnv.contains("AXHUB_PAIRING_SECRET='secret-1'"))
        #expect(hubEnv.contains("export HUB_HOST='192.168.10.109'"))
        #expect(hubEnv.contains("export HUB_GRPC_TLS_CA_CERT_PATH='/tmp/ca.pem'"))
        #expect(connectionJSON.contains("\"hub_host\": \"192.168.10.109\""))
        #expect(connectionJSON.contains("\"pairing_profile_epoch\": 13"))
    }

    @Test
    func persistDirectRemoteRouteStateRealignsConnectedHostAndPreservesTLS() async throws {
        let stateDir = try makeTempStateDir(prefix: "hub_direct_route_state")
        defer { try? FileManager.default.removeItem(at: stateDir) }

        try writeFile(
            stateDir.appendingPathComponent("pairing.env"),
            """
            AXHUB_HUB_HOST='ortdemac-mini.local'
            AXHUB_PAIRING_PORT='50053'
            AXHUB_GRPC_PORT='50052'
            AXHUB_APP_ID='x_terminal'
            AXHUB_DEVICE_NAME='Andrew.Xie Laptop'
            AXHUB_PAIRING_REQUEST_ID='req-1'
            AXHUB_PAIRING_SECRET='secret-1'
            AXHUB_INTERNET_HOST='192.168.10.109'
            AXHUB_HUB_INSTANCE_ID='hub_33bdbcae9a4fa1cb9c27'
            AXHUB_LAN_DISCOVERY_NAME='axhub-33bdbcae9a'
            AXHUB_PAIRING_PROFILE_EPOCH='13'
            AXHUB_ROUTE_PACK_VERSION='route_pack_live'
            """
        )
        try writeFile(
            stateDir.appendingPathComponent("hub.env"),
            """
            export HUB_HOST='ortdemac-mini.local'
            export HUB_PORT='50052'
            export HUB_CLIENT_TOKEN='tok_current'
            export HUB_DEVICE_ID='dev-1'
            export HUB_USER_ID='user-1'
            export HUB_APP_ID='x_terminal'
            export HUB_GRPC_TLS_MODE='tls'
            export HUB_GRPC_TLS_SERVER_NAME='axhub'
            export HUB_GRPC_TLS_CA_CERT_PATH='/tmp/ca.pem'
            """
        )
        try writeFile(
            stateDir.appendingPathComponent("connection.json"),
            """
            {
              "schema_version": "axhub_connection.v1",
              "hub_host": "ortdemac-mini.local",
              "grpc_port": 50052,
              "pairing_port": 50053,
              "pairing_profile_epoch": 13,
              "route_pack_version": "route_pack_live"
            }
            """
        )

        try await HubPairingCoordinator.shared.persistDirectRemoteRouteStateForTesting(
            stateDir: stateDir,
            host: "192.168.10.109",
            internetHost: "192.168.10.109",
            pairingPort: 50053,
            grpcPort: 50052
        )

        let pairingEnv = try String(
            contentsOf: stateDir.appendingPathComponent("pairing.env"),
            encoding: .utf8
        )
        let hubEnv = try String(
            contentsOf: stateDir.appendingPathComponent("hub.env"),
            encoding: .utf8
        )
        let connectionJSON = try String(
            contentsOf: stateDir.appendingPathComponent("connection.json"),
            encoding: .utf8
        )

        #expect(pairingEnv.contains("AXHUB_HUB_HOST='192.168.10.109'"))
        #expect(pairingEnv.contains("AXHUB_INTERNET_HOST='192.168.10.109'"))
        #expect(hubEnv.contains("export HUB_HOST='192.168.10.109'"))
        #expect(hubEnv.contains("export HUB_GRPC_TLS_MODE='tls'"))
        #expect(hubEnv.contains("export HUB_GRPC_TLS_SERVER_NAME='axhub'"))
        #expect(connectionJSON.contains("\"hub_host\": \"192.168.10.109\""))
    }

    @Test
    func loopbackOnlyDiscoveryReasonRequiresNoAuthoritativeLocalProfile() {
        #expect(
            HubPairingCoordinator.loopbackOnlyDiscoveryFailureReasonForTesting(
                ignoredLoopbackCandidate: true,
                hasAuthoritativeLocalProfile: false
            ) == "local_network_discovery_blocked"
        )
        #expect(
            HubPairingCoordinator.loopbackOnlyDiscoveryFailureReasonForTesting(
                ignoredLoopbackCandidate: true,
                hasAuthoritativeLocalProfile: true
            ) == nil
        )
    }

    @Test
    func pairingMetadataRepairDetectsHubInstanceMismatch() {
        let reason = HubPairingCoordinator.pairingMetadataRepairReasonForTesting(
            cachedHubInstanceID: "hub_cached",
            discoveredHubInstanceID: "hub_live",
            cachedPairingProfileEpoch: 7,
            discoveredPairingProfileEpoch: 9,
            cachedRoutePackVersion: "route_pack_old",
            discoveredRoutePackVersion: "route_pack_live"
        )

        #expect(reason == "hub_instance_mismatch")
    }

    @Test
    func pairingMetadataRepairDetectsStalePairingEpochOnSameHub() {
        let reason = HubPairingCoordinator.pairingMetadataRepairReasonForTesting(
            cachedHubInstanceID: "hub_live",
            discoveredHubInstanceID: "hub_live",
            cachedPairingProfileEpoch: 7,
            discoveredPairingProfileEpoch: 9,
            cachedRoutePackVersion: "route_pack_live",
            discoveredRoutePackVersion: "route_pack_live"
        )

        #expect(reason == "pairing_profile_epoch_stale")
    }

    @Test
    func pairingMetadataRepairDetectsOutdatedRoutePackWithoutEpochChange() {
        let reason = HubPairingCoordinator.pairingMetadataRepairReasonForTesting(
            cachedHubInstanceID: "hub_live",
            discoveredHubInstanceID: "hub_live",
            cachedPairingProfileEpoch: 9,
            discoveredPairingProfileEpoch: 9,
            cachedRoutePackVersion: "route_pack_old",
            discoveredRoutePackVersion: "route_pack_live"
        )

        #expect(reason == "route_pack_outdated")
    }

    @Test
    func pairingMetadataRepairSkipsLegacyUpgradeWhenCachedMetadataIsMissing() {
        let missingEpochReason = HubPairingCoordinator.pairingMetadataRepairReasonForTesting(
            cachedHubInstanceID: "hub_live",
            discoveredHubInstanceID: "hub_live",
            cachedPairingProfileEpoch: nil,
            discoveredPairingProfileEpoch: 9,
            cachedRoutePackVersion: "route_pack_live",
            discoveredRoutePackVersion: "route_pack_live"
        )
        let missingRoutePackReason = HubPairingCoordinator.pairingMetadataRepairReasonForTesting(
            cachedHubInstanceID: "hub_live",
            discoveredHubInstanceID: "hub_live",
            cachedPairingProfileEpoch: 9,
            discoveredPairingProfileEpoch: 9,
            cachedRoutePackVersion: nil,
            discoveredRoutePackVersion: "route_pack_live"
        )

        #expect(missingEpochReason == nil)
        #expect(missingRoutePackReason == nil)
    }

    @Test
    func ensureConnectedFailsClosedOnDiscoveredStaleEpochBeforeBootstrapOrConnect() async throws {
        let stateDir = try makeTempStateDir(prefix: "hub_pairing_stale_epoch_connect")
        defer { try? FileManager.default.removeItem(at: stateDir) }

        try writeFile(
            stateDir.appendingPathComponent("pairing.env"),
            """
            AXHUB_APP_ID='x_terminal'
            AXHUB_DEVICE_NAME='X-Terminal'
            AXHUB_PAIRING_PROFILE_EPOCH='7'
            AXHUB_ROUTE_PACK_VERSION='route_pack_live'
            """
        )
        try writeFile(
            stateDir.appendingPathComponent("hub.env"),
            """
            export HUB_CLIENT_TOKEN='tok_current'
            """
        )
        let fakeAxhubctl = try writeFakeAxhubctl(
            in: stateDir,
            discoverOutput: """
            host: hub.test.invalid
            pairing_port: 50052
            grpc_port: 50051
            internet_host: hub.test.invalid
            pairing_profile_epoch: 9
            route_pack_version: route_pack_live
            """
        )

        let report = await HubPairingCoordinator.shared.ensureConnected(
            options: HubRemoteConnectOptions(
                grpcPort: 50051,
                pairingPort: 50052,
                deviceName: "X-Terminal",
                internetHost: "hub.test.invalid",
                inviteToken: "",
                axhubctlPath: fakeAxhubctl.path,
                stateDir: stateDir
            ),
            allowBootstrap: true
        )

        #expect(report.ok == false)
        #expect(report.reasonCode == "pairing_profile_epoch_stale")
        #expect(report.summary == "pairing_profile_epoch_stale")
        let invocations = readAxhubctlInvocationLog(from: stateDir)
        #expect(invocations.isEmpty || invocations == ["discover"])
    }

    @Test
    func ensureConnectedFailsClosedOnDiscoveredHubInstanceMismatchBeforeBootstrapOrConnect() async throws {
        let stateDir = try makeTempStateDir(prefix: "hub_pairing_instance_mismatch_connect")
        defer { try? FileManager.default.removeItem(at: stateDir) }

        try writeFile(
            stateDir.appendingPathComponent("pairing.env"),
            """
            AXHUB_APP_ID='x_terminal'
            AXHUB_DEVICE_NAME='X-Terminal'
            AXHUB_HUB_INSTANCE_ID='hub_cached'
            AXHUB_PAIRING_PROFILE_EPOCH='7'
            AXHUB_ROUTE_PACK_VERSION='route_pack_live'
            """
        )
        try writeFile(
            stateDir.appendingPathComponent("hub.env"),
            """
            export HUB_CLIENT_TOKEN='tok_current'
            """
        )
        let fakeAxhubctl = try writeFakeAxhubctl(
            in: stateDir,
            discoverOutput: """
            host: hub.test.invalid
            pairing_port: 50052
            grpc_port: 50051
            internet_host: hub.test.invalid
            hub_instance_id: hub_live
            pairing_profile_epoch: 9
            route_pack_version: route_pack_live
            """
        )

        let report = await HubPairingCoordinator.shared.ensureConnected(
            options: HubRemoteConnectOptions(
                grpcPort: 50051,
                pairingPort: 50052,
                deviceName: "X-Terminal",
                internetHost: "hub.test.invalid",
                inviteToken: "",
                axhubctlPath: fakeAxhubctl.path,
                stateDir: stateDir
            ),
            allowBootstrap: true
        )

        #expect(report.ok == false)
        #expect(report.reasonCode == "hub_instance_mismatch")
        #expect(report.summary == "hub_instance_mismatch")
        let invocations = readAxhubctlInvocationLog(from: stateDir)
        #expect(invocations.isEmpty || invocations == ["discover"])
    }

    @Test
    func detectPortsFailsClosedOnDiscoveredOutdatedRoutePack() async throws {
        let stateDir = try makeTempStateDir(prefix: "hub_pairing_route_pack_port_probe")
        defer { try? FileManager.default.removeItem(at: stateDir) }

        try writeFile(
            stateDir.appendingPathComponent("pairing.env"),
            """
            AXHUB_APP_ID='x_terminal'
            AXHUB_DEVICE_NAME='X-Terminal'
            AXHUB_ROUTE_PACK_VERSION='route_pack_old'
            """
        )
        try writeFile(
            stateDir.appendingPathComponent("hub.env"),
            """
            export HUB_CLIENT_TOKEN='tok_current'
            """
        )
        let fakeAxhubctl = try writeFakeAxhubctl(
            in: stateDir,
            discoverOutput: """
            host: hub.test.invalid
            pairing_port: 50055
            grpc_port: 50056
            internet_host: hub.test.invalid
            route_pack_version: route_pack_live
            """
        )

        let result = await HubPairingCoordinator.shared.detectPorts(
            options: HubRemoteConnectOptions(
                grpcPort: 50051,
                pairingPort: 50052,
                deviceName: "X-Terminal",
                internetHost: "hub.test.invalid",
                inviteToken: "",
                axhubctlPath: fakeAxhubctl.path,
                stateDir: stateDir
            ),
            candidates: [50052]
        )

        #expect(result.ok == false)
        #expect(result.reasonCode == "route_pack_outdated")
        #expect(result.candidates.first?.routePackVersion == "route_pack_live")
        let invocations = readAxhubctlInvocationLog(from: stateDir)
        #expect(invocations.isEmpty || invocations == ["discover"])
    }

    func ensureConnectedSkipsBootstrapRefreshWhenConnectFailsWithIdentityBoundaryReason() async throws {
        let stateDir = try makeTempStateDir(prefix: "hub_pairing_identity_boundary_refresh")
        defer { try? FileManager.default.removeItem(at: stateDir) }

        try writeFile(
            stateDir.appendingPathComponent("pairing.env"),
            """
            AXHUB_APP_ID='x_terminal'
            AXHUB_DEVICE_NAME='X-Terminal'
            """
        )
        try writeFile(
            stateDir.appendingPathComponent("hub.env"),
            """
            export HUB_CLIENT_TOKEN='tok_current'
            """
        )
        let fakeAxhubctl = try writeFakeAxhubctl(
            in: stateDir,
            discoverOutput: """
            host: hub.test.invalid
            pairing_port: 50052
            grpc_port: 50051
            internet_host: hub.test.invalid
            """,
            connectOutput: """
            [error] unauthenticated: token no longer matches current pairing profile
            """,
            connectExitCode: 1
        )

        let report = await HubPairingCoordinator.shared.ensureConnected(
            options: HubRemoteConnectOptions(
                grpcPort: 50051,
                pairingPort: 50052,
                deviceName: "X-Terminal",
                internetHost: "hub.test.invalid",
                inviteToken: "",
                axhubctlPath: fakeAxhubctl.path,
                stateDir: stateDir
            ),
            allowBootstrap: true,
            preferredRoute: .stableNamedRemote,
            candidateRoutes: [.stableNamedRemote]
        )

        #expect(report.ok == false)
        #expect(report.reasonCode == "unauthenticated")
        let invocations = readAxhubctlInvocationLog(from: stateDir)
        #expect(invocations.contains("discover"))
        #expect(invocations.contains("connect"))
        #expect(invocations.contains("bootstrap") == false)
        #expect(report.logText.contains("skip refresh") == true)
    }

    @Test
    func parseRemoteModelsResultCapturesPaidAccessBudgetTruth() {
        let report = HubPairingCoordinator.parseRemoteModelsResultForTesting(
            """
            Hub connected: 17.81.11.116:50053
            [paid-access] trust_profile_present=true paid_model_policy_mode=all_paid_models daily_token_limit=640 single_request_token_limit=256
            Models: 1
            - GPT-5.4 | openai/gpt-5.4 | PAID_ONLINE | openai | AVAILABLE
            """
        )

        #expect(report.models.count == 1)
        #expect(report.paidAccessSnapshot?.trustProfilePresent == true)
        #expect(report.paidAccessSnapshot?.paidModelPolicyMode == "all_paid_models")
        #expect(report.paidAccessSnapshot?.dailyTokenLimit == 640)
        #expect(report.paidAccessSnapshot?.singleRequestTokenLimit == 256)
    }

    @Test
    func reusableInternetHostSkipsCorporateLanAddressWhenHubIdentityIsKnown() {
        let host = HubPairingCoordinator.inferredReusableInternetHostForTesting(
            "17.81.12.12",
            hubInstanceID: "hub_deadbeefcafefeed00",
            lanDiscoveryName: "axhub-edge-bj"
        )

        #expect(host == nil)
    }

    @Test
    func reusableInternetHostSkipsUnnamedRawIPv4() {
        let host = HubPairingCoordinator.inferredReusableInternetHostForTesting("100.96.10.8")
        #expect(host == nil)
    }

    @Test
    func preferredConnectHubSkipsCachedRawPublicIPWithoutNamedEntry() {
        let host = HubPairingCoordinator.preferredConnectHubForTesting(
            cachedHost: "17.81.11.116"
        )

        #expect(host == "auto")
    }

    @Test
    func orderedConnectRouteCandidatesRespectPreferredRouteAndAvailability() {
        let defaultOrder = HubPairingCoordinator.orderedConnectRouteCandidatesForTesting(
            requestedCandidates: [],
            preferredRoute: nil,
            internetHost: "hub.tailnet.example"
        )
        let preferredOnlyTunnelOrder = HubPairingCoordinator.orderedConnectRouteCandidatesForTesting(
            requestedCandidates: [],
            preferredRoute: .managedTunnelFallback,
            internetHost: "hub.tailnet.example"
        )
        let handedOffOrder = HubPairingCoordinator.orderedConnectRouteCandidatesForTesting(
            requestedCandidates: [.stableNamedRemote, .managedTunnelFallback],
            preferredRoute: .managedTunnelFallback,
            internetHost: "hub.tailnet.example"
        )
        let lanOnlyOrder = HubPairingCoordinator.orderedConnectRouteCandidatesForTesting(
            requestedCandidates: [.stableNamedRemote, .managedTunnelFallback],
            preferredRoute: .stableNamedRemote,
            internetHost: ""
        )

        #expect(defaultOrder == [.lanDirect, .stableNamedRemote])
        #expect(preferredOnlyTunnelOrder == [.managedTunnelFallback, .lanDirect, .stableNamedRemote])
        #expect(handedOffOrder == [.managedTunnelFallback, .stableNamedRemote])
        #expect(lanOnlyOrder == [.lanDirect])
    }

    @Test
    func orderedConnectRouteCandidatesDropFormalRemotePathsForRawPublicIP() {
        let defaultOrder = HubPairingCoordinator.orderedConnectRouteCandidatesForTesting(
            requestedCandidates: [],
            preferredRoute: nil,
            internetHost: "17.81.11.116"
        )
        let requestedRemoteOrder = HubPairingCoordinator.orderedConnectRouteCandidatesForTesting(
            requestedCandidates: [.stableNamedRemote, .managedTunnelFallback],
            preferredRoute: .managedTunnelFallback,
            internetHost: "17.81.11.116"
        )

        #expect(defaultOrder == [.lanDirect])
        #expect(requestedRemoteOrder == [.lanDirect])
    }

    @Test
    func connectRepairHostsPreferStableNamedEntryOverCachedRawPublicIP() {
        let hosts = HubPairingCoordinator.connectRepairHostsForTesting(
            cachedHost: "17.81.11.116",
            cachedInternetHost: "hub.tailnet.example"
        )

        #expect(hosts == ["hub.tailnet.example"])
    }

    @Test
    func preferredPresenceHostUsesInternetHostForTunnelRoute() {
        let host = HubPairingCoordinator.preferredPresenceHostForTesting(
            route: .internetTunnel,
            cachedHost: "127.0.0.1",
            cachedInternetHost: "hub.tailnet.example"
        )

        #expect(host == "hub.tailnet.example")
    }

    @Test
    func preferredPresenceHostStaysOnLanHostForLanRoute() {
        let host = HubPairingCoordinator.preferredPresenceHostForTesting(
            route: .lan,
            cachedHost: "192.168.10.22",
            cachedInternetHost: "hub.tailnet.example"
        )

        #expect(host == "192.168.10.22")
    }

    @Test
    func pairingRepairDiscoveryAllowsUniqueLANFallbackForCachedProfile() {
        let allowed = HubPairingCoordinator.shouldAttemptLANRepairDiscoveryForTesting(
            configuredInternetHost: "203.0.113.7",
            cachedHost: "203.0.113.7",
            cachedPairingPort: 50054,
            cachedGrpcPort: 50053,
            allowConfiguredHostRepair: true
        )

        #expect(allowed == true)
    }

    @Test
    func lanDiscoveryPrepassRunsDuringRepairReconnectEvenWhenConfiguredHostExists() {
        let allowed = HubPairingCoordinator.shouldRunLANDiscoveryPrepassForTesting(
            configuredInternetHost: "203.0.113.7",
            cachedHost: "17.81.11.116",
            cachedPairingPort: 50054,
            cachedGrpcPort: 50053,
            allowConfiguredHostRepair: true
        )

        #expect(allowed == true)
    }

    @Test
    func lanSubnetFallbackScanSkipsExplicitConfiguredRemoteHost() {
        let allowed = HubPairingCoordinator.shouldAttemptLANSubnetFallbackScanForTesting(
            configuredInternetHost: "hub.tailnet.example",
            cachedHost: "17.81.11.116",
            cachedPairingPort: 50054,
            cachedGrpcPort: 50053,
            allowConfiguredHostRepair: true
        )

        #expect(allowed == false)
    }

    @Test
    func lanSubnetFallbackScanRemainsAvailableWithoutConfiguredRemoteHost() {
        let allowed = HubPairingCoordinator.shouldAttemptLANSubnetFallbackScanForTesting(
            configuredInternetHost: "",
            cachedHost: "17.81.11.116",
            cachedPairingPort: 50054,
            cachedGrpcPort: 50053,
            allowConfiguredHostRepair: true
        )

        #expect(allowed == true)
    }

    @Test
    func lanSubnetFallbackScanAllowsConfiguredRawIPRepair() {
        let allowed = HubPairingCoordinator.shouldAttemptLANSubnetFallbackScanForTesting(
            configuredInternetHost: "192.168.10.101",
            cachedHost: "ortdemac-mini.local",
            cachedInternetHost: "192.168.10.101",
            cachedPairingPort: 50053,
            cachedGrpcPort: 50052,
            allowConfiguredHostRepair: true
        )

        #expect(allowed == true)
    }

    @Test
    func lanDiscoveryFallbackProbeTimeoutMatchesKnownHostProbeBudget() {
        #expect(
            HubPairingCoordinator.lanDiscoveryFallbackProbeTimeoutSecForTesting()
                == HubPairingCoordinator.pairingDiscoveryProbeTimeoutSecForTesting()
        )
    }

    @Test
    func lanDiscoveryOrderedUniquePortsPreservePreferredPortOrder() {
        let ports = HubPairingCoordinator.orderedUniquePairingPortsForTesting(
            [50054, 50052, 50054, 50053, 50052]
        )

        #expect(ports == [50054, 50052, 50053])
    }

    @Test
    func freshLANDiscoveryPortsPreferSecureRemoteDefaultBeforeLegacySweep() {
        let ports = HubPairingCoordinator.lanDiscoveryPairingPortsForTesting(
            [50052, 50053, 50054, 50055, 50056],
            configuredInternetHost: nil,
            cachedHost: nil,
            cachedInternetHost: nil,
            cachedPairingPort: nil,
            cachedHubInstanceID: nil
        )

        #expect(ports == [50054, 50052, 50053, 50055, 50056])
    }

    @Test
    func authoritativeLANDiscoveryPortsKeepExistingPreferredOrder() {
        let ports = HubPairingCoordinator.lanDiscoveryPairingPortsForTesting(
            [50052, 50053, 50054, 50055, 50056],
            configuredInternetHost: "17.81.11.116",
            cachedHost: nil,
            cachedInternetHost: nil,
            cachedPairingPort: nil,
            cachedHubInstanceID: nil
        )

        #expect(ports == [50052, 50053, 50054, 50055, 50056])
    }

    @Test
    func lanDiscoveryPriorityHostWindowCapsEachSubnet() {
        let hosts = [
            "17.81.10.1",
            "17.81.10.2",
            "17.81.10.3",
            "17.81.11.1",
            "17.81.11.2",
            "17.81.11.3",
            "17.81.9.1",
        ]

        let priority = HubPairingCoordinator.lanDiscoveryPriorityHostWindowForTesting(
            hosts,
            limitPerSubnet: 2
        )

        #expect(priority == [
            "17.81.10.1",
            "17.81.10.2",
            "17.81.11.1",
            "17.81.11.2",
            "17.81.9.1",
        ])
    }

    @Test
    func lanDiscoveryPermissionDeniedHeuristicRecognizesPosixEPERM() {
        #expect(
            HubPairingCoordinator.isLocalNetworkAccessDeniedForTesting(
                domain: NSPOSIXErrorDomain,
                code: Int(EPERM),
                description: "Operation not permitted"
            ) == true
        )
        #expect(
            HubPairingCoordinator.isLocalNetworkAccessDeniedForTesting(
                domain: NSURLErrorDomain,
                code: -1001,
                description: "The request timed out."
            ) == false
        )
    }

    @Test
    func rawConfiguredRemoteDoesNotPinDiscoveredHostDuringRepair() {
        let shouldPin = HubPairingCoordinator.shouldPinDiscoveredHostToConfiguredRemoteForTesting(
            configuredInternetHost: "192.168.10.101"
        )
        let shouldPinBonjour = HubPairingCoordinator.shouldPinDiscoveredHostToConfiguredRemoteForTesting(
            configuredInternetHost: "ortdemac-mini.local"
        )

        #expect(shouldPin == false)
        #expect(shouldPinBonjour == false)
    }

    @Test
    func stableNamedConfiguredRemoteKeepsDiscoveredHostPinned() {
        let shouldPin = HubPairingCoordinator.shouldPinDiscoveredHostToConfiguredRemoteForTesting(
            configuredInternetHost: "hub.tailnet.example"
        )

        #expect(shouldPin == true)
    }

    @Test
    func pairingRepairDiscoveryStaysStrictWithoutCachedProfile() {
        let allowed = HubPairingCoordinator.shouldAttemptLANRepairDiscoveryForTesting(
            configuredInternetHost: "203.0.113.7",
            allowConfiguredHostRepair: true
        )

        #expect(allowed == false)
    }

    @Test
    func lanDiscoveryPrepassStaysStrictWhenRepairFlagIsOff() {
        let allowed = HubPairingCoordinator.shouldRunLANDiscoveryPrepassForTesting(
            configuredInternetHost: "203.0.113.7",
            cachedHost: "17.81.11.116",
            cachedPairingPort: 50054,
            cachedGrpcPort: 50053,
            allowConfiguredHostRepair: false
        )

        #expect(allowed == false)
    }

    @Test
    func public24LANDiscoveryExpandsToNeighboringSubnets() {
        let networks = HubPairingCoordinator.expandedLANDiscoveryNetworksForTesting(
            address: "17.81.10.243",
            prefixLength: 24
        )

        #expect(networks == ["17.81.10.0/24", "17.81.11.0/24", "17.81.9.0/24"])
    }

    @Test
    func private24LANDiscoveryStaysOnCurrentSubnet() {
        let networks = HubPairingCoordinator.expandedLANDiscoveryNetworksForTesting(
            address: "192.168.10.22",
            prefixLength: 24
        )

        #expect(networks == ["192.168.10.0/24"])
    }

    @Test
    func lanDiscoveryInterfaceFilterSkipsTunnelAndBridgeAdapters() {
        #expect(
            HubPairingCoordinator.shouldIncludeLANDiscoveryInterfaceForTesting(
                interfaceName: "utun6",
                flags: Int32(IFF_UP | IFF_RUNNING | IFF_POINTOPOINT)
            ) == false
        )
        #expect(
            HubPairingCoordinator.shouldIncludeLANDiscoveryInterfaceForTesting(
                interfaceName: "bridge0",
                flags: Int32(IFF_UP | IFF_RUNNING)
            ) == false
        )
    }

    @Test
    func lanDiscoveryInterfaceFilterKeepsPrimaryLanAdapters() {
        let allowed = HubPairingCoordinator.shouldIncludeLANDiscoveryInterfaceForTesting(
            interfaceName: "en0",
            flags: Int32(IFF_UP | IFF_RUNNING)
        )

        #expect(allowed == true)
    }

    @Test
    func authoritativeFormalBootstrapSkipsDiscoveryWhenStableNamedHostAndInviteTokenExist() {
        let skipped = HubPairingCoordinator.shouldSkipDiscoveryForAuthoritativeBootstrapForTesting(
            configuredInternetHost: "hub.xhubsystem.com",
            inviteToken: "axhub_invite_test_123",
            hasAuthoritativeLocalProfile: false
        )

        #expect(skipped == true)
    }

    @Test
    func authoritativeFormalBootstrapKeepsDiscoveryForRawIPMissingTokenOrExistingProfile() {
        #expect(
            HubPairingCoordinator.shouldSkipDiscoveryForAuthoritativeBootstrapForTesting(
                configuredInternetHost: "17.81.11.116",
                inviteToken: "axhub_invite_test_123",
                hasAuthoritativeLocalProfile: false
            ) == false
        )
        #expect(
            HubPairingCoordinator.shouldSkipDiscoveryForAuthoritativeBootstrapForTesting(
                configuredInternetHost: "hub.xhubsystem.com",
                inviteToken: "",
                hasAuthoritativeLocalProfile: false
            ) == false
        )
        #expect(
            HubPairingCoordinator.shouldSkipDiscoveryForAuthoritativeBootstrapForTesting(
                configuredInternetHost: "hub.xhubsystem.com",
                inviteToken: "axhub_invite_test_123",
                hasAuthoritativeLocalProfile: true
            ) == false
        )
    }

    @Test
    func authoritativeManualEndpointSkipsDiscoveryForRawIPBeforeFirstPair() {
        #expect(
            HubPairingCoordinator.shouldSkipDiscoveryForAuthoritativeBootstrapForTesting(
                configuredInternetHost: "17.81.11.116",
                inviteToken: "",
                configuredEndpointIsAuthoritative: true,
                hasAuthoritativeLocalProfile: false
            ) == true
        )
    }

    @Test
    func authoritativeManualEndpointSkipsDiscoveryForReconnectToo() {
        #expect(
            HubPairingCoordinator.shouldSkipDiscoveryForAuthoritativeBootstrapForTesting(
                configuredInternetHost: "192.168.10.101",
                inviteToken: "",
                configuredEndpointIsAuthoritative: true,
                hasAuthoritativeLocalProfile: true
            ) == true
        )
    }

    @Test
    func authoritativeManualEndpointDisablesReconnectRepairDiscovery() {
        let allowed = HubPairingCoordinator.shouldRunLANDiscoveryPrepassForTesting(
            configuredInternetHost: "192.168.10.101",
            cachedHost: "axhub-56919a1b67.local",
            cachedInternetHost: "192.168.10.101",
            cachedPairingPort: 50053,
            cachedGrpcPort: 50052,
            allowConfiguredHostRepair: true,
            configuredEndpointIsAuthoritative: true
        )

        #expect(allowed == false)
    }

    @Test
    func authoritativeManualEndpointDisablesLANSubnetFallbackScan() {
        let allowed = HubPairingCoordinator.shouldAttemptLANSubnetFallbackScanForTesting(
            configuredInternetHost: "192.168.10.101",
            cachedHost: "axhub-56919a1b67.local",
            cachedInternetHost: "192.168.10.101",
            cachedPairingPort: 50053,
            cachedGrpcPort: 50052,
            allowConfiguredHostRepair: true,
            configuredEndpointIsAuthoritative: true
        )

        #expect(allowed == false)
    }

    @Test
    func discoveryHintsExcludeLoopbackWithoutAuthoritativeLocalProfile() {
        let hints = HubPairingCoordinator.discoveryHintsForTesting(
            cachedHost: "17.81.11.116"
        )

        #expect(hints == ["17.81.11.116"])
    }

    @Test
    func discoveryHintsPreferStableEntriesAheadOfRawCachedIP() {
        let hints = HubPairingCoordinator.discoveryHintsForTesting(
            configuredInternetHost: "hub.tailnet.example",
            cachedHost: "17.81.11.116",
            cachedInternetHost: "hub.tailnet.example",
            cachedLanDiscoveryName: "axhub-edge-bj"
        )

        #expect(hints == ["hub.tailnet.example", "17.81.11.116", "axhub-edge-bj.local"])
    }

    @Test
    func discoveryHintsAllowLoopbackForExplicitLocalHub() {
        let hints = HubPairingCoordinator.discoveryHintsForTesting(
            configuredInternetHost: "127.0.0.1",
            hasAuthoritativeLocalProfile: false
        )

        #expect(hints == ["127.0.0.1", "localhost"])
    }

    @Test
    func discoveryHintsIncludeDerivedBonjourHostFromInviteInstanceID() {
        let hints = HubPairingCoordinator.discoveryHintsForTesting(
            inviteInstanceID: "hub_92bfecdb8b539c67ab26"
        )

        #expect(hints == ["axhub-92bfecdb8b.local"])
    }

    @Test
    func preferredDiscoveryHostsPrioritizeReusableRemoteThenBonjourThenLan() {
        let hosts = HubPairingCoordinator.preferredDiscoveryHostsForTesting(
            configuredInternetHost: "hub.tailnet.example",
            cachedHost: "192.168.10.105",
            cachedInternetHost: "hub.tailnet.example",
            cachedLanDiscoveryName: "axhub-studio"
        )

        #expect(hosts == ["hub.tailnet.example", "axhub-studio.local", "192.168.10.105"])
    }

    @Test
    func preferredDiscoveryHostsUseInviteIdentityHintBeforeBlindLanFallback() {
        let hosts = HubPairingCoordinator.preferredDiscoveryHostsForTesting(
            inviteInstanceID: "hub_92bfecdb8b539c67ab26"
        )

        #expect(hosts == ["axhub-92bfecdb8b.local"])
    }

    @Test
    func rawDiscoverLoopbackCandidateIsIgnoredWithoutAuthoritativeLocalProfile() {
        #expect(
            HubPairingCoordinator.shouldIgnoreDiscoveredLoopbackCandidateForTesting(
                discoveredHost: "127.0.0.1"
            ) == true
        )
        #expect(
            HubPairingCoordinator.shouldIgnoreDiscoveredLoopbackCandidateForTesting(
                discoveredHost: "localhost",
                configuredInternetHost: "192.168.10.105"
            ) == true
        )
        #expect(
            HubPairingCoordinator.shouldIgnoreDiscoveredLoopbackCandidateForTesting(
                discoveredHost: "127.0.0.1",
                cachedHost: "127.0.0.1",
                hasAuthoritativeLocalProfile: false
            ) == true
        )
    }

    @Test
    func rawDiscoverLoopbackCandidateIsAllowedForKnownLocalProfile() {
        #expect(
            HubPairingCoordinator.shouldIgnoreDiscoveredLoopbackCandidateForTesting(
                discoveredHost: "127.0.0.1",
                cachedHost: "127.0.0.1",
                hasAuthoritativeLocalProfile: true
            ) == false
        )
        #expect(
            HubPairingCoordinator.shouldIgnoreDiscoveredLoopbackCandidateForTesting(
                discoveredHost: "localhost",
                configuredInternetHost: "127.0.0.1"
            ) == false
        )
    }

    func synchronizeCachedPairingStateRealignsStalePairingEnvFromAuthoritativeConnection() async throws {
        let stateDir = try makeTempStateDir(prefix: "hub_pairing_sync")
        defer { try? FileManager.default.removeItem(at: stateDir) }

        try writeFile(
            stateDir.appendingPathComponent("pairing.env"),
            """
            AXHUB_HUB_HOST='AndrewXies-Laptop.local'
            AXHUB_PAIRING_PORT='50055'
            AXHUB_GRPC_PORT='50054'
            AXHUB_APP_ID='x_terminal'
            AXHUB_DEVICE_NAME='Andrew.Xie Laptop'
            AXHUB_PAIRING_REQUEST_ID='req-1'
            AXHUB_PAIRING_SECRET='secret-1'
            AXHUB_INTERNET_HOST='10.106.215.29'
            AXHUB_HUB_INSTANCE_ID='hub_33bdbcae9a4fa1cb9c27'
            AXHUB_LAN_DISCOVERY_NAME='axhub-33bdbcae9a'
            AXHUB_PAIRING_PROFILE_EPOCH='7'
            AXHUB_ROUTE_PACK_VERSION='route_pack_old'
            """
        )
        try writeFile(
            stateDir.appendingPathComponent("hub.env"),
            """
            export HUB_HOST='17.81.11.116'
            export HUB_PORT='50053'
            export HUB_CLIENT_TOKEN='tok_current'
            """
        )
        try writeFile(
            stateDir.appendingPathComponent("connection.json"),
            """
            {
              "schema_version": "axhub_connection.v1",
              "hub_host": "17.81.11.116",
              "grpc_port": 50053,
              "pairing_port": 50054,
              "pairing_profile_epoch": 9,
              "route_pack_version": "route_pack_live"
            }
            """
        )

        await HubPairingCoordinator.shared.synchronizeCachedPairingStateForTesting(
            stateDir: stateDir,
            deviceName: "X-Terminal"
        )

        let pairingEnv = try String(
            contentsOf: stateDir.appendingPathComponent("pairing.env"),
            encoding: .utf8
        )
        #expect(pairingEnv.contains("AXHUB_HUB_HOST='17.81.11.116'"))
        #expect(pairingEnv.contains("AXHUB_PAIRING_PORT='50054'"))
        #expect(pairingEnv.contains("AXHUB_GRPC_PORT='50053'"))
        #expect(pairingEnv.contains("AXHUB_PAIRING_REQUEST_ID='req-1'"))
        #expect(pairingEnv.contains("AXHUB_PAIRING_SECRET='secret-1'"))
        #expect(pairingEnv.contains("AXHUB_PAIRING_PROFILE_EPOCH='9'"))
        #expect(pairingEnv.contains("AXHUB_ROUTE_PACK_VERSION='route_pack_live'"))
    }

    @Test
    func prepareDiscoveryProbeStateSeedsAuthoritativeArtifactsIntoEphemeralStateDir() async throws {
        let sourceStateDir = try makeTempStateDir(prefix: "hub_pairing_probe_source")
        let probeStateDir = try makeTempStateDir(prefix: "hub_pairing_probe_target")
        defer {
            try? FileManager.default.removeItem(at: sourceStateDir)
            try? FileManager.default.removeItem(at: probeStateDir)
        }

        try writeFile(
            sourceStateDir.appendingPathComponent("pairing.env"),
            """
            AXHUB_HUB_HOST='AndrewXies-Laptop.local'
            AXHUB_PAIRING_PORT='50055'
            AXHUB_GRPC_PORT='50054'
            AXHUB_APP_ID='x_terminal'
            AXHUB_DEVICE_NAME='Andrew.Xie Laptop'
            AXHUB_PAIRING_REQUEST_ID='req-1'
            AXHUB_PAIRING_SECRET='secret-1'
            AXHUB_PAIRING_PROFILE_EPOCH='7'
            AXHUB_ROUTE_PACK_VERSION='route_pack_old'
            """
        )
        try writeFile(
            sourceStateDir.appendingPathComponent("hub.env"),
            """
            export HUB_HOST='17.81.11.116'
            export HUB_PORT='50053'
            export HUB_CLIENT_TOKEN='tok_current'
            """
        )
        try writeFile(
            sourceStateDir.appendingPathComponent("connection.json"),
            """
            {
              "schema_version": "axhub_connection.v1",
              "hub_host": "17.81.11.116",
              "grpc_port": 50053,
              "pairing_port": 50054,
              "pairing_profile_epoch": 12,
              "route_pack_version": "route_pack_live"
            }
            """
        )

        await HubPairingCoordinator.shared.prepareDiscoveryProbeStateForTesting(
            sourceStateDir: sourceStateDir,
            probeStateDir: probeStateDir,
            deviceName: "X-Terminal"
        )

        let probePairingEnv = try String(
            contentsOf: probeStateDir.appendingPathComponent("pairing.env"),
            encoding: .utf8
        )
        let probeHubEnv = try String(
            contentsOf: probeStateDir.appendingPathComponent("hub.env"),
            encoding: .utf8
        )
        let probeConnectionJSON = try String(
            contentsOf: probeStateDir.appendingPathComponent("connection.json"),
            encoding: .utf8
        )

        #expect(probePairingEnv.contains("AXHUB_HUB_HOST='17.81.11.116'"))
        #expect(probePairingEnv.contains("AXHUB_PAIRING_PORT='50054'"))
        #expect(probePairingEnv.contains("AXHUB_GRPC_PORT='50053'"))
        #expect(probePairingEnv.contains("AXHUB_PAIRING_SECRET='secret-1'"))
        #expect(probePairingEnv.contains("AXHUB_PAIRING_PROFILE_EPOCH='12'"))
        #expect(probePairingEnv.contains("AXHUB_ROUTE_PACK_VERSION='route_pack_live'"))
        #expect(probeHubEnv.contains("export HUB_HOST='17.81.11.116'"))
        #expect(probeConnectionJSON.contains("\"hub_host\": \"17.81.11.116\""))
        #expect(probeConnectionJSON.contains("\"pairing_profile_epoch\": 12"))
        #expect(probeConnectionJSON.contains("\"route_pack_version\": \"route_pack_live\""))
    }

    @Test
    func persistLoopbackTunnelRouteStateRealignsRemoteProfileToLoopbackAndPreservesInternetHost() async throws {
        let stateDir = try makeTempStateDir(prefix: "hub_pairing_tunnel_state")
        defer { try? FileManager.default.removeItem(at: stateDir) }

        try writeFile(
            stateDir.appendingPathComponent("pairing.env"),
            """
            AXHUB_HUB_HOST='17.81.11.116'
            AXHUB_PAIRING_PORT='50054'
            AXHUB_GRPC_PORT='50053'
            AXHUB_APP_ID='x_terminal'
            AXHUB_DEVICE_NAME='Andrew.Xie Laptop'
            AXHUB_PAIRING_REQUEST_ID='req-1'
            AXHUB_PAIRING_SECRET='secret-1'
            AXHUB_INTERNET_HOST='17.81.11.116'
            AXHUB_HUB_INSTANCE_ID='hub_33bdbcae9a4fa1cb9c27'
            AXHUB_LAN_DISCOVERY_NAME='axhub-33bdbcae9a'
            AXHUB_PAIRING_PROFILE_EPOCH='13'
            AXHUB_ROUTE_PACK_VERSION='route_pack_live'
            """
        )
        try writeFile(
            stateDir.appendingPathComponent("hub.env"),
            """
            export HUB_HOST='17.81.11.116'
            export HUB_PORT='50053'
            export HUB_CLIENT_TOKEN='tok_current'
            export HUB_DEVICE_ID='dev-1'
            export HUB_USER_ID='user-1'
            export HUB_APP_ID='x_terminal'
            export HUB_GRPC_TLS_MODE='tls'
            export HUB_GRPC_TLS_SERVER_NAME='hub.example'
            export HUB_GRPC_TLS_CA_CERT_PATH='/tmp/ca.pem'
            """
        )
        try writeFile(
            stateDir.appendingPathComponent("connection.json"),
            """
            {
              "schema_version": "axhub_connection.v1",
              "hub_host": "17.81.11.116",
              "grpc_port": 50053,
              "pairing_port": 50054,
              "pairing_profile_epoch": 13,
              "route_pack_version": "route_pack_live"
            }
            """
        )

        try await HubPairingCoordinator.shared.persistLoopbackTunnelRouteStateForTesting(
            stateDir: stateDir,
            internetHost: "17.81.11.116",
            pairingPort: 50054,
            grpcPort: 50053
        )

        let pairingEnv = try String(
            contentsOf: stateDir.appendingPathComponent("pairing.env"),
            encoding: .utf8
        )
        let hubEnv = try String(
            contentsOf: stateDir.appendingPathComponent("hub.env"),
            encoding: .utf8
        )
        let connectionJSON = try String(
            contentsOf: stateDir.appendingPathComponent("connection.json"),
            encoding: .utf8
        )

        #expect(pairingEnv.contains("AXHUB_HUB_HOST='127.0.0.1'"))
        #expect(pairingEnv.contains("AXHUB_INTERNET_HOST='17.81.11.116'"))
        #expect(pairingEnv.contains("AXHUB_PAIRING_REQUEST_ID='req-1'"))
        #expect(pairingEnv.contains("AXHUB_PAIRING_PROFILE_EPOCH='13'"))
        #expect(pairingEnv.contains("AXHUB_ROUTE_PACK_VERSION='route_pack_live'"))
        #expect(hubEnv.contains("export HUB_HOST='127.0.0.1'"))
        #expect(hubEnv.contains("export HUB_PORT='50053'"))
        #expect(hubEnv.contains("export HUB_CLIENT_TOKEN='tok_current'"))
        #expect(hubEnv.contains("export HUB_GRPC_TLS_MODE='tls'"))
        #expect(connectionJSON.contains("\"hub_host\" : \"127.0.0.1\""))
        #expect(connectionJSON.contains("\"grpc_port\" : 50053"))
        #expect(connectionJSON.contains("\"pairing_port\" : 50054"))
        #expect(connectionJSON.contains("\"pairing_profile_epoch\" : 13"))
        #expect(connectionJSON.contains("\"route_pack_version\" : \"route_pack_live\""))
        #expect(connectionJSON.contains("\"tls_mode\" : \"tls\""))
    }

    @Test
    func remoteGenerateSuccessPreservesReturnedModelId() {
        let json = """
        {"ok":true,"text":"hello","model_id":"openai/gpt-5.3-codex","reason":"eos"}
        """

        let result = HubPairingCoordinator.remoteGenerateResultForTesting(
            jsonLine: json,
            requestedModelId: "openai/gpt-4.1"
        )

        #expect(result?.ok == true)
        #expect(result?.text == "hello")
        #expect(result?.modelId == "openai/gpt-5.3-codex")
    }

    @Test
    func remoteGenerateSuccessFallsBackToRequestedModelIdWhenPayloadOmitsIt() {
        let json = """
        {"ok":true,"text":"hello","reason":"eos"}
        """

        let result = HubPairingCoordinator.remoteGenerateResultForTesting(
            jsonLine: json,
            requestedModelId: "openai/gpt-5.3-codex"
        )

        #expect(result?.ok == true)
        #expect(result?.text == "hello")
        #expect(result?.modelId == "openai/gpt-5.3-codex")
    }

    @Test
    func remoteGenerateSuccessPreservesExecutionMetadata() {
        let json = """
        {"ok":true,"text":"hello","model_id":"qwen3-17b-mlx-bf16","requested_model_id":"gpt-5.4","actual_model_id":"qwen3-17b-mlx-bf16","runtime_provider":"Hub (Local)","execution_path":"hub_downgraded_to_local","fallback_reason_code":"downgrade_to_local","audit_ref":"audit-route-1","deny_code":"credential_finding","reason":"eos"}
        """

        let result = HubPairingCoordinator.remoteGenerateResultForTesting(
            jsonLine: json,
            requestedModelId: "gpt-5.4"
        )

        #expect(result?.ok == true)
        #expect(result?.requestedModelId == "gpt-5.4")
        #expect(result?.actualModelId == "qwen3-17b-mlx-bf16")
        #expect(result?.runtimeProvider == "Hub (Local)")
        #expect(result?.executionPath == "hub_downgraded_to_local")
        #expect(result?.fallbackReasonCode == "downgrade_to_local")
        #expect(result?.auditRef == "audit-route-1")
        #expect(result?.denyCode == "credential_finding")
    }

    @Test
    func remoteSupervisorCandidateReviewQueueResultParsesRequestLevelSnapshot() {
        let json = """
        {"ok":true,"source":"hub_runtime_grpc","updated_at_ms":1773420090000,"items":[{"schema_version":"xhub.supervisor_candidate_review_item.v1","review_id":"sup_cand_review:device:x_terminal:req-1","request_id":"req-1","evidence_ref":"candidate_carrier_request:req-1","review_state":"pending_review","durable_promotion_state":"not_promoted","promotion_boundary":"candidate_carrier_only","device_id":"device-a","user_id":"user-a","app_id":"x_terminal","thread_id":"thread-1","thread_key":"shadow-thread","project_id":"project-a","project_ids":["project-a"],"scopes":["project_scope"],"record_types":["project_blocker"],"audit_refs":["audit-1"],"idempotency_keys":["sha256:req-1"],"candidate_count":2,"summary_line":"project_scope","mirror_target":"hub_candidate_carrier_shadow_thread","local_store_role":"cache|fallback|edit_buffer","carrier_kind":"supervisor_after_turn_durable_candidate_shadow_write","carrier_schema_version":"xt.supervisor.durable_candidate_mirror.v1","pending_change_id":"","pending_change_status":"","edit_session_id":"","doc_id":"","writeback_ref":"","stage_created_at_ms":0,"stage_updated_at_ms":0,"latest_emitted_at_ms":1773420080000,"created_at_ms":1773420079000,"updated_at_ms":1773420081000}]}
        """

        let result = HubPairingCoordinator.remoteSupervisorCandidateReviewQueueResultForTesting(jsonLine: json)

        #expect(result?.ok == true)
        #expect(result?.updatedAtMs == 1_773_420_090_000)
        #expect(result?.items.count == 1)
        #expect(result?.items.first?.requestId == "req-1")
        #expect(result?.items.first?.reviewState == "pending_review")
        #expect(result?.items.first?.candidateCount == 2)
        #expect(result?.items.first?.projectIds == ["project-a"])
    }

    @Test
    func remoteSupervisorCandidateReviewStageResultParsesDraftMetadata() {
        let json = """
        {"ok":true,"source":"hub_memory_v1_grpc","staged":true,"idempotent":false,"review_state":"draft_staged","durable_promotion_state":"not_promoted","promotion_boundary":"longterm_markdown_pending_change","candidate_request_id":"req-1","evidence_ref":"candidate_carrier_request:req-1","edit_session_id":"edit-1","pending_change_id":"chg-1","doc_id":"longterm:project-a","base_version":"v1","working_version":"v2","session_revision":3,"status":"draft","markdown":"# Supervisor Candidate Review Handoff","created_at_ms":1773420082000,"updated_at_ms":1773420083000,"expires_at_ms":1773423683000}
        """

        let result = HubPairingCoordinator.remoteSupervisorCandidateReviewStageResultForTesting(jsonLine: json)

        #expect(result?.ok == true)
        #expect(result?.staged == true)
        #expect(result?.idempotent == false)
        #expect(result?.reviewState == "draft_staged")
        #expect(result?.promotionBoundary == "longterm_markdown_pending_change")
        #expect(result?.pendingChangeId == "chg-1")
        #expect(result?.sessionRevision == 3)
        #expect(result?.status == "draft")
    }

    private func makeTempStateDir(prefix: String) throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(prefix, isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func writeFile(_ url: URL, _ contents: String) throws {
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    private func writeFakeAxhubctl(
        in directory: URL,
        discoverOutput: String,
        connectOutput: String? = nil,
        connectExitCode: Int = 91
    ) throws -> URL {
        let scriptURL = directory.appendingPathComponent("fake_axhubctl.sh")
        let trimmedOutput = discoverOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedConnectOutput = connectOutput?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        try writeFile(
            scriptURL,
            """
            #!/bin/sh
            set -eu
            script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
            log_file="$script_dir/axhubctl_calls.log"
            cmd="${1:-}"
            printf '%s\n' "$cmd" >> "$log_file"
            case "$cmd" in
              discover)
                cat <<'EOF'
            \(trimmedOutput)
            EOF
                exit 0
                ;;
              connect)
                if [ -n "\(trimmedConnectOutput)" ]; then
                  cat <<'EOF' >&2
            \(trimmedConnectOutput)
            EOF
                  exit \(connectExitCode)
                fi
                echo "connect_should_not_run" >&2
                exit 91
                ;;
              bootstrap)
                echo "bootstrap_should_not_run" >&2
                exit 92
                ;;
              install-client)
                echo "install_client_should_not_run" >&2
                exit 93
                ;;
              *)
                echo "unsupported:$cmd" >&2
                exit 64
                ;;
            esac
            """
        )
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        return scriptURL
    }

    private func readAxhubctlInvocationLog(from directory: URL) -> [String] {
        let logURL = directory.appendingPathComponent("axhubctl_calls.log")
        guard let contents = try? String(contentsOf: logURL, encoding: .utf8) else { return [] }
        return contents
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
