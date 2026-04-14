import Foundation
import Foundation
import Testing
@testable import XTerminal

struct AppModelHubNetworkPathTests {
    @Test
    func reconnectsWhenNetworkReturns() {
        let previous = HubNetworkPathFingerprint(
            statusKey: "unsatisfied",
            usesWiFi: false,
            usesWiredEthernet: false,
            usesCellular: false,
            isExpensive: false,
            isConstrained: false
        )
        let current = HubNetworkPathFingerprint(
            statusKey: "satisfied",
            usesWiFi: false,
            usesWiredEthernet: true,
            usesCellular: false,
            isExpensive: false,
            isConstrained: false
        )

        #expect(AppModel.shouldForceHubReconnect(previous: previous, current: current))
    }

    @Test
    func reconnectsWhenSatisfiedRouteSwitchesInterfaces() {
        let previous = HubNetworkPathFingerprint(
            statusKey: "satisfied",
            usesWiFi: true,
            usesWiredEthernet: false,
            usesCellular: false,
            isExpensive: false,
            isConstrained: false
        )
        let current = HubNetworkPathFingerprint(
            statusKey: "satisfied",
            usesWiFi: false,
            usesWiredEthernet: true,
            usesCellular: false,
            isExpensive: false,
            isConstrained: false
        )

        #expect(AppModel.shouldForceHubReconnect(previous: previous, current: current))
    }

    @Test
    func doesNotReconnectWhenSatisfiedPathOnlyChangesCostOrConstraintFlags() {
        let previous = HubNetworkPathFingerprint(
            statusKey: "satisfied",
            usesWiFi: true,
            usesWiredEthernet: false,
            usesCellular: false,
            isExpensive: false,
            isConstrained: false
        )
        let constrained = HubNetworkPathFingerprint(
            statusKey: "satisfied",
            usesWiFi: true,
            usesWiredEthernet: false,
            usesCellular: false,
            isExpensive: false,
            isConstrained: true
        )
        let expensive = HubNetworkPathFingerprint(
            statusKey: "satisfied",
            usesWiFi: true,
            usesWiredEthernet: false,
            usesCellular: false,
            isExpensive: true,
            isConstrained: false
        )

        #expect(AppModel.shouldForceHubReconnect(previous: previous, current: constrained) == false)
        #expect(AppModel.shouldForceHubReconnect(previous: previous, current: expensive) == false)
    }

    @Test
    func doesNotReconnectWhenPathFingerprintIsUnchangedOrOffline() {
        let stable = HubNetworkPathFingerprint(
            statusKey: "satisfied",
            usesWiFi: false,
            usesWiredEthernet: true,
            usesCellular: false,
            isExpensive: false,
            isConstrained: false
        )
        let offline = HubNetworkPathFingerprint(
            statusKey: "unsatisfied",
            usesWiFi: false,
            usesWiredEthernet: false,
            usesCellular: false,
            isExpensive: false,
            isConstrained: false
        )

        #expect(AppModel.shouldForceHubReconnect(previous: stable, current: stable) == false)
        #expect(AppModel.shouldForceHubReconnect(previous: stable, current: offline) == false)
        #expect(AppModel.shouldForceHubReconnect(previous: nil, current: stable) == false)
    }

    @Test
    func suppressesAutomaticReconnectDuringStartupWarmupWindow() {
        let now = Date(timeIntervalSince1970: 1_741_300_100)
        let warmupUntil = now.addingTimeInterval(5.0)

        #expect(
            AppModel.shouldSuppressAutomaticReconnectDuringStartup(
                now: now,
                warmupUntil: warmupUntil
            )
        )
        #expect(
            AppModel.shouldSuppressAutomaticReconnectDuringStartup(
                now: warmupUntil.addingTimeInterval(0.1),
                warmupUntil: warmupUntil
            ) == false
        )
    }

    @Test
    func suppressesAutomaticReconnectWhileRemoteGenerateIsInFlight() {
        #expect(
            AppModel.shouldSuppressAutomaticRemoteReconnect(
                hubRemoteLinking: false,
                startupSuppressed: false,
                activeRemoteGenerate: true
            )
        )
        #expect(
            AppModel.shouldSuppressAutomaticRemoteReconnect(
                hubRemoteLinking: false,
                startupSuppressed: false,
                activeRemoteGenerate: false
            ) == false
        )
    }

    @Test
    func defersAutomaticRouteHandoffWhileRemoteGenerateIsInFlight() {
        #expect(
            AppModel.shouldDeferAutomaticRemoteRouteHandoff(
                activeRemoteGenerate: true,
                remoteConnected: true,
                remoteRoute: .internet
            )
        )
        #expect(
            AppModel.shouldDeferAutomaticRemoteRouteHandoff(
                activeRemoteGenerate: true,
                remoteConnected: false,
                remoteRoute: .none
            ) == false
        )
        #expect(
            AppModel.shouldDeferAutomaticRemoteRouteHandoff(
                activeRemoteGenerate: false,
                remoteConnected: true,
                remoteRoute: .internet
            ) == false
        )
    }

    @Test
    func defersBackgroundRemoteInventoryRefreshWhileRemoteGenerateIsInFlight() {
        #expect(
            AppModel.shouldDeferBackgroundRemoteInventoryRefresh(
                activeRemoteGenerate: true
            )
        )
        #expect(
            AppModel.shouldDeferBackgroundRemoteInventoryRefresh(
                activeRemoteGenerate: false
            ) == false
        )
    }

    @Test
    func relaxesBackgroundHubPollIntervalDuringRemoteGenerate() {
        #expect(
            AppModel.backgroundHubPollInterval(activeRemoteGenerate: true, connected: true)
                > AppModel.backgroundHubPollInterval(activeRemoteGenerate: false, connected: true)
        )
    }

    @Test
    func automaticReconnectCandidateRoutesExcludeManagedTunnelFallback() {
        #expect(
            AppModel.automaticRemoteReconnectCandidateRoutes(
                internetHost: "hub.tailnet.example"
            ) == [.lanDirect, .stableNamedRemote]
        )
        #expect(
            AppModel.automaticRemoteReconnectCandidateRoutes(
                internetHost: ""
            ) == [.lanDirect]
        )
    }

    @Test
    func discoveryRepairReconnectRunsOnAnySatisfiedInternetPath() {
        let wifi = HubNetworkPathFingerprint(
            statusKey: "satisfied",
            usesWiFi: true,
            usesWiredEthernet: false,
            usesCellular: false,
            isExpensive: false,
            isConstrained: false
        )
        let wired = HubNetworkPathFingerprint(
            statusKey: "satisfied",
            usesWiFi: false,
            usesWiredEthernet: true,
            usesCellular: false,
            isExpensive: false,
            isConstrained: false
        )
        let cellular = HubNetworkPathFingerprint(
            statusKey: "satisfied",
            usesWiFi: false,
            usesWiredEthernet: false,
            usesCellular: true,
            isExpensive: true,
            isConstrained: false
        )
        let otherSatisfied = HubNetworkPathFingerprint(
            statusKey: "satisfied",
            usesWiFi: false,
            usesWiredEthernet: false,
            usesCellular: false,
            isExpensive: false,
            isConstrained: true
        )
        let offline = HubNetworkPathFingerprint(
            statusKey: "unsatisfied",
            usesWiFi: false,
            usesWiredEthernet: false,
            usesCellular: false,
            isExpensive: false,
            isConstrained: false
        )

        #expect(AppModel.shouldAllowDiscoveryRepairReconnect(current: wifi))
        #expect(AppModel.shouldAllowDiscoveryRepairReconnect(current: wired))
        #expect(AppModel.shouldAllowDiscoveryRepairReconnect(current: cellular))
        #expect(AppModel.shouldAllowDiscoveryRepairReconnect(current: otherSatisfied))
        #expect(AppModel.shouldAllowDiscoveryRepairReconnect(current: offline) == false)
    }

    @Test
    func preservesExistingRemoteRouteOnlyDuringSatisfiedAutomaticReconnect() {
        let satisfied = HubNetworkPathFingerprint(
            statusKey: "satisfied",
            usesWiFi: false,
            usesWiredEthernet: false,
            usesCellular: true,
            isExpensive: true,
            isConstrained: false
        )
        let offline = HubNetworkPathFingerprint(
            statusKey: "unsatisfied",
            usesWiFi: false,
            usesWiredEthernet: false,
            usesCellular: false,
            isExpensive: false,
            isConstrained: false
        )

        #expect(
            AppModel.shouldPreserveExistingRemoteRouteDuringAutomaticReconnect(
                current: satisfied,
                shouldAttemptReconnect: true,
                remoteConnected: true,
                remoteRoute: .internet
            )
        )
        #expect(
            AppModel.shouldPreserveExistingRemoteRouteDuringAutomaticReconnect(
                current: satisfied,
                shouldAttemptReconnect: false,
                remoteConnected: true,
                remoteRoute: .internet
            ) == false
        )
        #expect(
            AppModel.shouldPreserveExistingRemoteRouteDuringAutomaticReconnect(
                current: offline,
                shouldAttemptReconnect: true,
                remoteConnected: true,
                remoteRoute: .internet
            ) == false
        )
        #expect(
            AppModel.shouldPreserveExistingRemoteRouteDuringAutomaticReconnect(
                current: satisfied,
                shouldAttemptReconnect: true,
                remoteConnected: false,
                remoteRoute: .internet
            ) == false
        )
    }

    @Test
    func automaticBootstrapReconnectRequiresExistingHubEnvEvenWhenHintsExist() {
        #expect(
            !AppModel.shouldAllowAutomaticBootstrapReconnect(
                hasHubEnv: false,
                internetHost: "17.81.11.116",
                inviteToken: "",
                inviteAlias: "",
                inviteInstanceID: ""
            )
        )
        #expect(
            !AppModel.shouldAllowAutomaticBootstrapReconnect(
                hasHubEnv: false,
                internetHost: "",
                inviteToken: "invite-token-1",
                inviteAlias: "",
                inviteInstanceID: ""
            )
        )
    }

    @Test
    func automaticBootstrapReconnectStaysOffWithoutProfileOrHints() {
        #expect(
            AppModel.shouldAllowAutomaticBootstrapReconnect(
                hasHubEnv: false,
                internetHost: "",
                inviteToken: "",
                inviteAlias: "",
                inviteInstanceID: ""
            ) == false
        )
        #expect(
            AppModel.shouldAllowAutomaticBootstrapReconnect(
                hasHubEnv: true,
                internetHost: "",
                inviteToken: "",
                inviteAlias: "",
                inviteInstanceID: ""
            )
        )
    }

    @Test
    func automaticReconnectProgressIsSurfacedWhenStateWouldOtherwiseBeInvisible() {
        #expect(
            AppModel.shouldSurfaceAutomaticRemoteConnectProgress(
                force: false,
                allowBootstrap: false,
                existingSummary: "",
                existingLog: ""
            )
        )
        #expect(
            AppModel.shouldSurfaceAutomaticRemoteConnectProgress(
                force: true,
                allowBootstrap: false,
                existingSummary: "existing",
                existingLog: "existing"
            )
        )
        #expect(
            AppModel.shouldSurfaceAutomaticRemoteConnectProgress(
                force: false,
                allowBootstrap: true,
                existingSummary: "existing",
                existingLog: "existing"
            )
        )
    }

    @Test
    func automaticReconnectProgressStaysQuietWhenVisibleStateAlreadyExists() {
        #expect(
            AppModel.shouldSurfaceAutomaticRemoteConnectProgress(
                force: false,
                allowBootstrap: false,
                existingSummary: "connecting",
                existingLog: "$ axhubctl connect --hub auto"
            ) == false
        )
    }

    @Test
    func invalidatesRemoteRouteWhenPersistedHubEndpointChanges() {
        let previous = HubRemoteEndpointFingerprint(
            pairingPort: 50054,
            grpcPort: 50053,
            internetHost: "10.106.215.29"
        )
        let current = HubRemoteEndpointFingerprint(
            pairingPort: 50054,
            grpcPort: 50053,
            internetHost: "17.81.11.116"
        )

        #expect(
            AppModel.shouldInvalidateRemoteRouteAfterEndpointChange(
                previous: previous,
                current: current
            )
        )
    }

    @Test
    func keepsRemoteRouteWhenPersistedHubEndpointIsStable() {
        let previous = HubRemoteEndpointFingerprint(
            pairingPort: 50054,
            grpcPort: 50053,
            internetHost: "17.81.11.116"
        )
        let current = HubRemoteEndpointFingerprint(
            pairingPort: 50054,
            grpcPort: 50053,
            internetHost: "17.81.11.116"
        )

        #expect(
            AppModel.shouldInvalidateRemoteRouteAfterEndpointChange(
                previous: previous,
                current: current
            ) == false
        )
    }

    @Test
    func networkChangeRefreshesValidatedRemoteRouteWithoutBootstrap() {
        let decision = XTHubConnectivityDecisionBuilder.build(
            input: XTHubConnectivityDecisionInput(
                trigger: .networkChanged,
                currentPath: HubNetworkPathFingerprint(
                    statusKey: "satisfied",
                    usesWiFi: false,
                    usesWiredEthernet: false,
                    usesCellular: true,
                    isExpensive: true,
                    isConstrained: false
                ),
                pairedRouteSetSnapshot: makePairedRouteSetSnapshot(
                    readiness: .remoteReady,
                    stableRemoteRoute: true
                ),
                localConnected: false,
                remoteConnected: true,
                remoteRoute: .internet
            )
        )

        #expect(decision.shouldAttemptReconnect)
        #expect(decision.allowBootstrap == false)
        #expect(decision.reasonCode == "refresh_validated_remote_route")
        #expect(decision.summaryLine == "network changed; refreshing validated remote route ...")
    }

    @Test
    func networkChangeWaitsForRepairWhenRemoteRouteIsBlocked() {
        let decision = XTHubConnectivityDecisionBuilder.build(
            input: XTHubConnectivityDecisionInput(
                trigger: .networkChanged,
                currentPath: HubNetworkPathFingerprint(
                    statusKey: "satisfied",
                    usesWiFi: false,
                    usesWiredEthernet: true,
                    usesCellular: false,
                    isExpensive: false,
                    isConstrained: false
                ),
                pairedRouteSetSnapshot: makePairedRouteSetSnapshot(
                    readiness: .remoteBlocked,
                    stableRemoteRoute: true
                ),
                localConnected: false,
                remoteConnected: false,
                remoteRoute: .none
            )
        )

        #expect(decision.shouldAttemptReconnect == false)
        #expect(decision.allowBootstrap == false)
        #expect(decision.reasonCode == "remote_route_blocked_waiting_for_repair")
        #expect(decision.summaryLine.contains("waiting for repair") == true)
    }

    @Test
    func backgroundKeepaliveRetriesLanRouteWhenCurrentPathStillLooksLanCapable() {
        let decision = XTHubConnectivityDecisionBuilder.build(
            input: XTHubConnectivityDecisionInput(
                trigger: .backgroundKeepalive,
                currentPath: HubNetworkPathFingerprint(
                    statusKey: "satisfied",
                    usesWiFi: true,
                    usesWiredEthernet: false,
                    usesCellular: false,
                    isExpensive: false,
                    isConstrained: false
                ),
                pairedRouteSetSnapshot: makePairedRouteSetSnapshot(
                    readiness: .localReady,
                    lanRoute: true,
                    stableRemoteRoute: false
                ),
                localConnected: false,
                remoteConnected: false,
                remoteRoute: .none
            )
        )

        #expect(decision.shouldAttemptReconnect)
        #expect(decision.allowBootstrap == false)
        #expect(decision.reasonCode == "retry_same_lan_paired_route")
        #expect(decision.summaryLine == "remote route not active; retrying same-LAN paired route ...")
    }

    @Test
    func backgroundKeepaliveStopsRetryingLanRouteOnCellularOnlyPath() {
        let decision = XTHubConnectivityDecisionBuilder.build(
            input: XTHubConnectivityDecisionInput(
                trigger: .backgroundKeepalive,
                currentPath: HubNetworkPathFingerprint(
                    statusKey: "satisfied",
                    usesWiFi: false,
                    usesWiredEthernet: false,
                    usesCellular: true,
                    isExpensive: true,
                    isConstrained: false
                ),
                pairedRouteSetSnapshot: makePairedRouteSetSnapshot(
                    readiness: .localReady,
                    lanRoute: true,
                    stableRemoteRoute: false
                ),
                localConnected: false,
                remoteConnected: false,
                remoteRoute: .none
            )
        )

        #expect(decision.shouldAttemptReconnect == false)
        #expect(decision.allowBootstrap == false)
        #expect(decision.reasonCode == "waiting_for_same_lan_or_formal_remote_route")
        #expect(decision.summaryLine.contains("not same-LAN") == true)
    }

    @Test
    func backgroundKeepaliveVerifiesSavedFormalRemoteRouteBeforeBootstrap() {
        let decision = XTHubConnectivityDecisionBuilder.build(
            input: XTHubConnectivityDecisionInput(
                trigger: .backgroundKeepalive,
                currentPath: HubNetworkPathFingerprint(
                    statusKey: "satisfied",
                    usesWiFi: false,
                    usesWiredEthernet: false,
                    usesCellular: true,
                    isExpensive: true,
                    isConstrained: false
                ),
                pairedRouteSetSnapshot: makePairedRouteSetSnapshot(
                    readiness: .localReady,
                    lanRoute: true,
                    stableRemoteRoute: true
                ),
                localConnected: false,
                remoteConnected: false,
                remoteRoute: .none
            )
        )

        #expect(decision.shouldAttemptReconnect)
        #expect(decision.allowBootstrap == false)
        #expect(decision.reasonCode == "verify_formal_remote_route")
        #expect(decision.summaryLine == "remote route not active; verifying saved formal remote route ...")
    }

    @Test
    func foregroundResumePrewarmsSavedFormalRemoteRoute() {
        let decision = XTHubConnectivityDecisionBuilder.build(
            input: XTHubConnectivityDecisionInput(
                trigger: .appBecameActive,
                currentPath: HubNetworkPathFingerprint(
                    statusKey: "satisfied",
                    usesWiFi: false,
                    usesWiredEthernet: false,
                    usesCellular: true,
                    isExpensive: true,
                    isConstrained: false
                ),
                pairedRouteSetSnapshot: makePairedRouteSetSnapshot(
                    readiness: .localReady,
                    lanRoute: true,
                    stableRemoteRoute: true
                ),
                localConnected: false,
                remoteConnected: false,
                remoteRoute: .none
            )
        )

        #expect(decision.shouldAttemptReconnect)
        #expect(decision.selectedRoute == .stableNamedRemote)
        #expect(decision.reasonCode == "verify_formal_remote_route")
        #expect(decision.summaryLine == "app resumed in foreground; verifying saved formal remote route ...")
    }

    @Test
    func localReadyRouteSelectionPrefersStableNamedRemoteBeforeLanRouteWhenFormalEntryExists() {
        let decision = XTHubConnectivityDecisionBuilder.build(
            input: XTHubConnectivityDecisionInput(
                trigger: .networkChanged,
                currentPath: HubNetworkPathFingerprint(
                    statusKey: "satisfied",
                    usesWiFi: true,
                    usesWiredEthernet: false,
                    usesCellular: false,
                    isExpensive: false,
                    isConstrained: false
                ),
                pairedRouteSetSnapshot: makePairedRouteSetSnapshot(
                    readiness: .localReady,
                    lanRoute: true,
                    stableRemoteRoute: true
                ),
                localConnected: false,
                remoteConnected: false,
                remoteRoute: .none
            )
        )

        #expect(decision.shouldAttemptReconnect)
        #expect(decision.selectedRoute == .stableNamedRemote)
        #expect(decision.candidatesTried == [.stableNamedRemote, .lanDirect])
        #expect(decision.reasonCode == "verify_formal_remote_route")
    }

    @Test
    func systemWakeRefreshesValidatedRemoteRoute() {
        let decision = XTHubConnectivityDecisionBuilder.build(
            input: XTHubConnectivityDecisionInput(
                trigger: .systemWoke,
                currentPath: HubNetworkPathFingerprint(
                    statusKey: "satisfied",
                    usesWiFi: false,
                    usesWiredEthernet: false,
                    usesCellular: true,
                    isExpensive: true,
                    isConstrained: false
                ),
                pairedRouteSetSnapshot: makePairedRouteSetSnapshot(
                    readiness: .remoteReady,
                    stableRemoteRoute: true
                ),
                localConnected: false,
                remoteConnected: false,
                remoteRoute: .none
            )
        )

        #expect(decision.shouldAttemptReconnect)
        #expect(decision.selectedRoute == .stableNamedRemote)
        #expect(decision.reasonCode == "refresh_validated_remote_route")
        #expect(decision.summaryLine == "system woke from sleep; refreshing validated remote route ...")
    }

    @Test
    func hubReachabilityChangePrewarmsFallbackWhenLocalHubDisappears() {
        let decision = XTHubConnectivityDecisionBuilder.build(
            input: XTHubConnectivityDecisionInput(
                trigger: .hubReachabilityChanged,
                currentPath: HubNetworkPathFingerprint(
                    statusKey: "satisfied",
                    usesWiFi: false,
                    usesWiredEthernet: false,
                    usesCellular: true,
                    isExpensive: true,
                    isConstrained: false
                ),
                pairedRouteSetSnapshot: makePairedRouteSetSnapshot(
                    readiness: .remoteDegraded,
                    stableRemoteRoute: true
                ),
                localConnected: false,
                remoteConnected: false,
                remoteRoute: .none
            )
        )

        #expect(decision.shouldAttemptReconnect)
        #expect(decision.selectedRoute == .stableNamedRemote)
        #expect(decision.reasonCode == "retry_degraded_remote_route")
        #expect(decision.summaryLine == "local hub availability changed; retrying degraded remote route ...")
    }

    @Test
    func connectivityIncidentBlocksSavedRemoteRouteUntilRepairCompletes() {
        let pairedRouteSetSnapshot = makePairedRouteSetSnapshot(
            readiness: .remoteBlocked,
            readinessReasonCode: "remote_pairing_or_identity_blocked",
            stableRemoteRoute: true
        )
        let decision = XTHubConnectivityDecisionBuilder.build(
            input: XTHubConnectivityDecisionInput(
                trigger: .networkChanged,
                currentPath: HubNetworkPathFingerprint(
                    statusKey: "satisfied",
                    usesWiFi: false,
                    usesWiredEthernet: true,
                    usesCellular: false,
                    isExpensive: false,
                    isConstrained: false
                ),
                pairedRouteSetSnapshot: pairedRouteSetSnapshot,
                localConnected: false,
                remoteConnected: false,
                remoteRoute: .none
            )
        )
        let incident = XTHubConnectivityIncidentSnapshotBuilder.build(
            input: XTHubConnectivityIncidentInput(
                trigger: .networkChanged,
                decision: decision,
                currentPath: HubNetworkPathFingerprint(
                    statusKey: "satisfied",
                    usesWiFi: false,
                    usesWiredEthernet: true,
                    usesCellular: false,
                    isExpensive: false,
                    isConstrained: false
                ),
                pairedRouteSetSnapshot: pairedRouteSetSnapshot,
                localConnected: false,
                remoteConnected: false,
                remoteRoute: .none,
                currentFailureCode: "pairing_approval_timeout",
                updatedAt: Date(timeIntervalSince1970: 1_741_300_012)
            )
        )

        #expect(incident.incidentState == XTHubConnectivityIncidentState.blocked)
        #expect(incident.reasonCode == "pairing_approval_timeout")
        #expect(incident.decisionReasonCode == "remote_route_blocked_waiting_for_repair")
        #expect(incident.pairedRouteReadiness == XTPairedRouteReadiness.remoteBlocked)
        #expect(incident.stableRemoteRouteHost == "hub.tailnet.example")
    }

    @Test
    func connectivityIncidentWaitsForLanCapablePathWhenOnlyLanRouteExists() {
        let pairedRouteSetSnapshot = makePairedRouteSetSnapshot(
            readiness: .localReady,
            readinessReasonCode: "local_pairing_ready",
            lanRoute: true,
            stableRemoteRoute: false
        )
        let path = HubNetworkPathFingerprint(
            statusKey: "satisfied",
            usesWiFi: false,
            usesWiredEthernet: false,
            usesCellular: true,
            isExpensive: true,
            isConstrained: false
        )
        let decision = XTHubConnectivityDecisionBuilder.build(
            input: XTHubConnectivityDecisionInput(
                trigger: .backgroundKeepalive,
                currentPath: path,
                pairedRouteSetSnapshot: pairedRouteSetSnapshot,
                localConnected: false,
                remoteConnected: false,
                remoteRoute: .none
            )
        )
        let incident = XTHubConnectivityIncidentSnapshotBuilder.build(
            input: XTHubConnectivityIncidentInput(
                trigger: .backgroundKeepalive,
                decision: decision,
                currentPath: path,
                pairedRouteSetSnapshot: pairedRouteSetSnapshot,
                localConnected: false,
                remoteConnected: false,
                remoteRoute: .none,
                currentFailureCode: "",
                updatedAt: Date(timeIntervalSince1970: 1_741_300_013)
            )
        )

        #expect(incident.incidentState == XTHubConnectivityIncidentState.waiting)
        #expect(incident.reasonCode == "local_pairing_ready")
        #expect(incident.decisionReasonCode == "waiting_for_same_lan_or_formal_remote_route")
        #expect(incident.currentPath?.usesCellular == true)
        #expect(incident.summaryLine.contains("same-LAN") == true)
    }

    @Test
    func connectivityIncidentRetriesDegradedRemoteRoute() {
        let pairedRouteSetSnapshot = makePairedRouteSetSnapshot(
            readiness: .remoteDegraded,
            readinessReasonCode: "cached_remote_reconnect_smoke_failed",
            stableRemoteRoute: true
        )
        let path = HubNetworkPathFingerprint(
            statusKey: "satisfied",
            usesWiFi: false,
            usesWiredEthernet: false,
            usesCellular: true,
            isExpensive: true,
            isConstrained: false
        )
        let decision = XTHubConnectivityDecisionBuilder.build(
            input: XTHubConnectivityDecisionInput(
                trigger: .backgroundKeepalive,
                currentPath: path,
                pairedRouteSetSnapshot: pairedRouteSetSnapshot,
                localConnected: false,
                remoteConnected: false,
                remoteRoute: .none
            )
        )
        let incident = XTHubConnectivityIncidentSnapshotBuilder.build(
            input: XTHubConnectivityIncidentInput(
                trigger: .backgroundKeepalive,
                decision: decision,
                currentPath: path,
                pairedRouteSetSnapshot: pairedRouteSetSnapshot,
                localConnected: false,
                remoteConnected: false,
                remoteRoute: .none,
                currentFailureCode: "grpc_unavailable",
                updatedAt: Date(timeIntervalSince1970: 1_741_300_014)
            )
        )

        #expect(incident.incidentState == XTHubConnectivityIncidentState.retrying)
        #expect(incident.reasonCode == "grpc_unavailable")
        #expect(incident.decisionReasonCode == "retry_degraded_remote_route")
        #expect(incident.pairedRouteReadiness == XTPairedRouteReadiness.remoteDegraded)
        #expect(incident.summaryLine.contains("retrying degraded remote route") == true)
    }

    @Test
    func degradedRemoteRouteWaitsWhenStableRemoteIsCoolingDown() {
        let ledgerSnapshot = makeRepairLedgerSnapshot(
            entries: [
                makeRepairOutcomeEntry(
                    recordedAtMs: 1_741_300_100_000,
                    finalRoute: .internetTunnel,
                    selectedRoute: .stableNamedRemote,
                    attemptedRoutes: [.stableNamedRemote, .managedTunnelFallback]
                ),
                makeRepairOutcomeEntry(
                    recordedAtMs: 1_741_300_160_000,
                    finalRoute: .internetTunnel,
                    selectedRoute: .stableNamedRemote,
                    attemptedRoutes: [.stableNamedRemote, .managedTunnelFallback]
                )
            ]
        )
        let decision = XTHubConnectivityDecisionBuilder.build(
            input: XTHubConnectivityDecisionInput(
                trigger: .backgroundKeepalive,
                currentPath: HubNetworkPathFingerprint(
                    statusKey: "satisfied",
                    usesWiFi: false,
                    usesWiredEthernet: false,
                    usesCellular: true,
                    isExpensive: true,
                    isConstrained: false
                ),
                pairedRouteSetSnapshot: makePairedRouteSetSnapshot(
                    readiness: .remoteDegraded,
                    stableRemoteRoute: true
                ),
                localConnected: false,
                remoteConnected: false,
                remoteRoute: .none,
                repairLedgerSnapshot: ledgerSnapshot,
                now: Date(timeIntervalSince1970: 1_741_300_190)
            )
        )

        let stableStatus = decision.routeStatuses.first { $0.route == .stableNamedRemote }
        #expect(decision.shouldAttemptReconnect == false)
        #expect(decision.selectedRoute == .stableNamedRemote)
        #expect(decision.candidatesTried == [.stableNamedRemote])
        #expect(decision.handoffReason == "all_candidates_in_cooldown")
        #expect(decision.cooldownApplied)
        #expect(stableStatus?.recentFailureCount == 2)
        #expect(stableStatus?.cooldownUntilMs != nil)
        #expect(decision.summaryLine.contains("cooling down") == true)
    }

    @Test
    func degradedRemoteRouteWaitsWhenAllCandidatesAreCoolingDown() {
        let ledgerSnapshot = makeRepairLedgerSnapshot(
            entries: [
                makeRepairFailedEntry(
                    recordedAtMs: 1_741_300_100_000,
                    selectedRoute: .stableNamedRemote,
                    attemptedRoutes: [.stableNamedRemote]
                ),
                makeRepairFailedEntry(
                    recordedAtMs: 1_741_300_160_000,
                    selectedRoute: .stableNamedRemote,
                    attemptedRoutes: [.stableNamedRemote]
                ),
                makeRepairFailedEntry(
                    recordedAtMs: 1_741_300_170_000,
                    selectedRoute: .managedTunnelFallback,
                    attemptedRoutes: [.managedTunnelFallback]
                ),
                makeRepairFailedEntry(
                    recordedAtMs: 1_741_300_180_000,
                    selectedRoute: .managedTunnelFallback,
                    attemptedRoutes: [.managedTunnelFallback]
                )
            ]
        )
        let decision = XTHubConnectivityDecisionBuilder.build(
            input: XTHubConnectivityDecisionInput(
                trigger: .backgroundKeepalive,
                currentPath: HubNetworkPathFingerprint(
                    statusKey: "satisfied",
                    usesWiFi: false,
                    usesWiredEthernet: false,
                    usesCellular: true,
                    isExpensive: true,
                    isConstrained: false
                ),
                pairedRouteSetSnapshot: makePairedRouteSetSnapshot(
                    readiness: .remoteDegraded,
                    stableRemoteRoute: true
                ),
                localConnected: false,
                remoteConnected: false,
                remoteRoute: .none,
                repairLedgerSnapshot: ledgerSnapshot,
                now: Date(timeIntervalSince1970: 1_741_300_200)
            )
        )

        #expect(decision.shouldAttemptReconnect == false)
        #expect(decision.selectedRoute == .stableNamedRemote)
        #expect(decision.candidatesTried == [.stableNamedRemote])
        #expect(decision.handoffReason == "all_candidates_in_cooldown")
        #expect(decision.cooldownApplied)
        #expect(decision.summaryLine.contains("cooling down") == true)
    }

    @Test
    func connectivityIncidentCanRepresentRetryingHandoffEvenWhenOldRouteIsStillHeld() {
        let currentPath = HubNetworkPathFingerprint(
            statusKey: "satisfied",
            usesWiFi: false,
            usesWiredEthernet: false,
            usesCellular: true,
            isExpensive: true,
            isConstrained: false
        )
        let pairedRouteSetSnapshot = makePairedRouteSetSnapshot(
            readiness: .remoteReady,
            stableRemoteRoute: true
        )
        let decision = XTHubConnectivityDecisionBuilder.build(
            input: XTHubConnectivityDecisionInput(
                trigger: .networkChanged,
                currentPath: currentPath,
                pairedRouteSetSnapshot: pairedRouteSetSnapshot,
                localConnected: false,
                remoteConnected: true,
                remoteRoute: .internet
            )
        )
        let incident = XTHubConnectivityIncidentSnapshotBuilder.build(
            input: XTHubConnectivityIncidentInput(
                trigger: .networkChanged,
                decision: decision,
                currentPath: currentPath,
                pairedRouteSetSnapshot: pairedRouteSetSnapshot,
                localConnected: false,
                remoteConnected: false,
                remoteRoute: .none,
                currentFailureCode: "",
                updatedAt: Date(timeIntervalSince1970: 1_741_300_012)
            )
        )

        #expect(incident.incidentState == .retrying)
        #expect(incident.reasonCode == XTPairedRouteReadiness.remoteReady.rawValue)
        #expect(incident.summaryLine == "network changed; refreshing validated remote route ...")
    }
}

private func makePairedRouteSetSnapshot(
    readiness: XTPairedRouteReadiness,
    readinessReasonCode: String? = nil,
    lanRoute: Bool = false,
    stableRemoteRoute: Bool = false
) -> XTPairedRouteSetSnapshot {
    XTPairedRouteSetSnapshot(
        readiness: readiness,
        readinessReasonCode: readinessReasonCode ?? readiness.rawValue,
        summaryLine: "",
        hubInstanceID: "hub_test_connectivity",
        activeRoute: nil,
        lanRoute: lanRoute
            ? XTPairedRouteTargetSnapshot(
                routeKind: .lan,
                host: "192.168.0.10",
                pairingPort: 50052,
                grpcPort: 50051,
                hostKind: "raw_ip",
                source: .cachedProfileHost
            )
            : nil,
        stableRemoteRoute: stableRemoteRoute
            ? XTPairedRouteTargetSnapshot(
                routeKind: .internet,
                host: "hub.tailnet.example",
                pairingPort: 50052,
                grpcPort: 50051,
                hostKind: "stable_named",
                source: .cachedProfileInternetHost
            )
            : nil,
        lastKnownGoodRoute: stableRemoteRoute
            ? XTPairedRouteTargetSnapshot(
                routeKind: .internet,
                host: "hub.tailnet.example",
                pairingPort: 50052,
                grpcPort: 50051,
                hostKind: "stable_named",
                source: .freshPairReconnectSmoke
            )
            : nil,
        cachedReconnectSmokeStatus: nil,
        cachedReconnectSmokeReasonCode: nil,
        cachedReconnectSmokeSummary: nil
    )
}

private func makeRepairLedgerSnapshot(
    entries: [XTConnectivityRepairLedgerEntry]
) -> XTConnectivityRepairLedgerSnapshot {
    XTConnectivityRepairLedgerSnapshot(
        schemaVersion: XTConnectivityRepairLedgerSnapshot.currentSchemaVersion,
        updatedAtMs: entries.last?.recordedAtMs ?? 0,
        entries: entries
    )
}

private func makeRepairOutcomeEntry(
    recordedAtMs: Int64,
    finalRoute: HubRemoteRoute,
    selectedRoute: XTHubRouteCandidate,
    attemptedRoutes: [XTHubRouteCandidate]
) -> XTConnectivityRepairLedgerEntry {
    XTConnectivityRepairLedgerEntry(
        schemaVersion: XTConnectivityRepairLedgerEntry.currentSchemaVersion,
        entryID: "repair-\(recordedAtMs)-\(selectedRoute.rawValue)",
        recordedAtMs: recordedAtMs,
        trigger: .backgroundKeepalive,
        failureCode: "grpc_unavailable",
        reasonFamily: "route_connectivity",
        action: .remoteReconnect,
        owner: .xtRuntime,
        result: .succeeded,
        verifyResult: "repair_completed",
        finalRoute: finalRoute.rawValue,
        decisionReasonCode: "retry_degraded_remote_route",
        incidentReasonCode: "grpc_unavailable",
        summaryLine: "managed tunnel fallback recovered the session",
        selectedRoute: selectedRoute.rawValue,
        attemptedRoutes: attemptedRoutes.map(\.rawValue),
        handoffReason: nil,
        cooldownApplied: false
    )
}

private func makeRepairFailedEntry(
    recordedAtMs: Int64,
    selectedRoute: XTHubRouteCandidate,
    attemptedRoutes: [XTHubRouteCandidate]
) -> XTConnectivityRepairLedgerEntry {
    XTConnectivityRepairLedgerEntry(
        schemaVersion: XTConnectivityRepairLedgerEntry.currentSchemaVersion,
        entryID: "repair-fail-\(recordedAtMs)-\(selectedRoute.rawValue)",
        recordedAtMs: recordedAtMs,
        trigger: .backgroundKeepalive,
        failureCode: "grpc_unavailable",
        reasonFamily: "route_connectivity",
        action: .remoteReconnect,
        owner: .xtRuntime,
        result: .failed,
        verifyResult: "retrying_remote_route",
        finalRoute: HubRemoteRoute.none.rawValue,
        decisionReasonCode: "retry_degraded_remote_route",
        incidentReasonCode: "grpc_unavailable",
        summaryLine: "route retry failed",
        selectedRoute: selectedRoute.rawValue,
        attemptedRoutes: attemptedRoutes.map(\.rawValue),
        handoffReason: nil,
        cooldownApplied: false
    )
}
