import Foundation
import Testing
@testable import XTerminal

@Suite(.serialized)
@MainActor
struct AppModelHubSetupFocusTests {
    @Test
    func ignoresEmptyHubSetupFocusRequests() {
        let appModel = AppModel()

        appModel.requestHubSetupFocus(sectionId: "   ")

        #expect(appModel.hubSetupFocusRequest == nil)
    }

    @Test
    func hubSetupFocusRequestUsesFreshNonceAndClearsCurrentOnly() throws {
        let appModel = AppModel()

        appModel.requestHubSetupFocus(
            sectionId: " troubleshoot ",
            title: " 检查 Hub Recovery ",
            detail: " reason=remote_export_blocked ",
            refreshAction: .recheckOfficialSkills,
            refreshReason: "official_skill_blocker"
        )
        let first = try #require(appModel.hubSetupFocusRequest)
        #expect(first.sectionId == "troubleshoot")
        #expect(first.context?.title == "检查 Hub Recovery")
        #expect(first.context?.detail == "reason=remote_export_blocked")
        #expect(first.context?.refreshAction == .recheckOfficialSkills)
        #expect(first.context?.refreshReason == "official_skill_blocker")

        appModel.requestHubSetupFocus(sectionId: "connection_log")
        let second = try #require(appModel.hubSetupFocusRequest)
        #expect(second.sectionId == "connection_log")
        #expect(second.nonce == first.nonce + 1)

        appModel.clearHubSetupFocusRequest(first)
        #expect(appModel.hubSetupFocusRequest?.nonce == second.nonce)

        appModel.clearHubSetupFocusRequest(second)
        #expect(appModel.hubSetupFocusRequest == nil)
    }

    @Test
    func applyHubPairingInvitePrefillUpdatesPairHubFields() {
        let appModel = AppModel()

        appModel.hubPairingPort = 50052
        appModel.hubGrpcPort = 50051
        appModel.hubInternetHost = ""
        appModel.hubInviteToken = ""

        appModel.applyHubPairingInvitePrefill(
            XTHubPairingInvitePrefill(
                hubAlias: "ops-main",
                internetHost: "hub.tailnet.example",
                pairingPort: 50054,
                grpcPort: 50053,
                inviteToken: "axhub_invite_test_123",
                hubInstanceID: "hub_deadbeefcafefeed00"
            )
        )

        #expect(appModel.hubPairingPort == 50054)
        #expect(appModel.hubGrpcPort == 50053)
        #expect(appModel.hubInternetHost == "hub.tailnet.example")
        #expect(appModel.hubInviteToken == "axhub_invite_test_123")
        #expect(appModel.hubInviteAlias == "ops-main")
        #expect(appModel.hubInviteInstanceID == "hub_deadbeefcafefeed00")
    }

    @Test
    func applyHubPairingInvitePrefillIgnoresMissingValues() {
        let appModel = AppModel()

        appModel.hubPairingPort = 50052
        appModel.hubGrpcPort = 50051
        appModel.hubInternetHost = "hub.current.example"
        appModel.hubInviteToken = "axhub_invite_existing"
        appModel.hubInviteAlias = "ops-current"
        appModel.hubInviteInstanceID = "hub_existing"

        appModel.applyHubPairingInvitePrefill(
            XTHubPairingInvitePrefill(
                hubAlias: nil,
                internetHost: "   ",
                pairingPort: nil,
                grpcPort: nil,
                inviteToken: "   ",
                hubInstanceID: nil
            )
        )

        #expect(appModel.hubPairingPort == 50052)
        #expect(appModel.hubGrpcPort == 50051)
        #expect(appModel.hubInternetHost == "hub.current.example")
        #expect(appModel.hubInviteToken == "axhub_invite_existing")
        #expect(appModel.hubInviteAlias == "ops-current")
        #expect(appModel.hubInviteInstanceID == "hub_existing")
    }

    @Test
    func consumesInviteTokenAfterSuccessfulRemoteConnectOnStableFormalEntry() {
        let report = HubRemoteConnectReport(
            ok: true,
            route: .internet,
            summary: "connected_internet",
            logLines: [],
            reasonCode: nil
        )

        #expect(
            AppModel.shouldConsumeHubInviteTokenAfterSuccessfulRemoteConnect(
                report: report,
                inviteToken: "axhub_invite_test_123",
                internetHost: "hub.xhubsystem.com",
                hasHubEnv: true
            )
        )
    }

    @Test
    func keepsInviteTokenWhenRemoteConnectDidNotReachDurableFormalPairingState() {
        let successfulReport = HubRemoteConnectReport(
            ok: true,
            route: .lan,
            summary: "connected_lan",
            logLines: [],
            reasonCode: nil
        )
        let failedReport = HubRemoteConnectReport(
            ok: false,
            route: .none,
            summary: "remote_connect_failed",
            logLines: [],
            reasonCode: "grpc_unavailable"
        )

        #expect(
            AppModel.shouldConsumeHubInviteTokenAfterSuccessfulRemoteConnect(
                report: successfulReport,
                inviteToken: "axhub_invite_test_123",
                internetHost: "17.81.11.116",
                hasHubEnv: true
            ) == false
        )
        #expect(
            AppModel.shouldConsumeHubInviteTokenAfterSuccessfulRemoteConnect(
                report: successfulReport,
                inviteToken: "axhub_invite_test_123",
                internetHost: "hub.xhubsystem.com",
                hasHubEnv: false
            ) == false
        )
        #expect(
            AppModel.shouldConsumeHubInviteTokenAfterSuccessfulRemoteConnect(
                report: failedReport,
                inviteToken: "axhub_invite_test_123",
                internetHost: "hub.xhubsystem.com",
                hasHubEnv: true
            ) == false
        )
    }

    @Test
    func currentRemoteConnectOptionsPreferLiveUserEditedEndpointBeforeConnectStarts() throws {
        try withHubRemoteDefaultsCleared {
            let defaults = UserDefaults.standard
            defaults.set(50052, forKey: "xterminal_hub_pairing_port")
            defaults.set(50051, forKey: "xterminal_hub_grpc_port")
            defaults.set("axhub-92bfecdb8b.local", forKey: "xterminal_hub_internet_host")

            let appModel = AppModel()
            appModel.setHubPairingPortFromUser(50054)
            appModel.setHubGrpcPortFromUser(50053)
            appModel.setHubInternetHostFromUser("17.81.11.116")
            appModel.hubInviteToken = "axhub_invite_test_123"
            appModel.hubInviteAlias = "ops-main"
            appModel.hubInviteInstanceID = "hub_deadbeefcafefeed00"

            let options = appModel.currentHubRemoteConnectOptions(stateDir: nil)
            #expect(options.pairingPort == 50054)
            #expect(options.grpcPort == 50053)
            #expect(options.internetHost == "17.81.11.116")
            #expect(options.inviteToken == "axhub_invite_test_123")
            #expect(options.inviteAlias == "ops-main")
            #expect(options.inviteInstanceID == "hub_deadbeefcafefeed00")
            #expect(options.configuredEndpointIsAuthoritative == true)
        }
    }

    @Test
    func manualHubEndpointOverrideProtectsVisibleFieldsFromAutofill() {
        #expect(
            AppModel.shouldProtectManualHubEndpointFromAutofill(
                overridePending: true,
                currentEndpoint: HubRemoteEndpointFingerprint(
                    pairingPort: 50053,
                    grpcPort: 50052,
                    internetHost: "192.168.10.101"
                )
            ) == true
        )
    }

    @Test
    func defaultHubEndpointDoesNotBlockAutofillWithoutMeaningfulManualOverride() {
        #expect(
            AppModel.shouldProtectManualHubEndpointFromAutofill(
                overridePending: false,
                currentEndpoint: HubRemoteEndpointFingerprint(
                    pairingPort: 50052,
                    grpcPort: 50051,
                    internetHost: ""
                )
            ) == false
        )
        #expect(
            AppModel.shouldProtectManualHubEndpointFromAutofill(
                overridePending: true,
                currentEndpoint: HubRemoteEndpointFingerprint(
                    pairingPort: 50052,
                    grpcPort: 50051,
                    internetHost: "   "
                )
            ) == false
        )
    }

    @Test
    func pairingResetPlanPreservesMeaningfulManualEndpointOverride() {
        let plan = AppModel.pairingResetPlan(
            overridePending: true,
            currentEndpoint: HubRemoteEndpointFingerprint(
                pairingPort: 50054,
                grpcPort: 50053,
                internetHost: "17.81.11.116"
            )
        )

        #expect(
            plan == HubPairingResetPlan(
                endpoint: HubRemoteEndpointFingerprint(
                    pairingPort: 50054,
                    grpcPort: 50053,
                    internetHost: "17.81.11.116"
                ),
                preserveEndpointOverride: true,
                shouldAutoDetect: false
            )
        )
    }

    @Test
    func pairingResetPlanFallsBackToDefaultProbeWhenNoMeaningfulManualEndpointExists() {
        let plan = AppModel.pairingResetPlan(
            overridePending: false,
            currentEndpoint: HubRemoteEndpointFingerprint(
                pairingPort: 50054,
                grpcPort: 50053,
                internetHost: "17.81.11.116"
            )
        )

        #expect(
            plan == HubPairingResetPlan(
                endpoint: HubRemoteEndpointFingerprint(
                    pairingPort: 50052,
                    grpcPort: 50051,
                    internetHost: ""
                ),
                preserveEndpointOverride: false,
                shouldAutoDetect: true
            )
        )
    }

    private func withHubRemoteDefaultsCleared(_ body: () throws -> Void) throws {
        let defaults = UserDefaults.standard
        let keys = [
            "xterminal_hub_pairing_port",
            "xterminal_hub_grpc_port",
            "xterminal_hub_internet_host",
            "xterminal_hub_invite_token",
            "xterminal_hub_invite_alias",
            "xterminal_hub_invite_instance_id",
            "xterminal_hub_axhubctl_path",
            "xterminal_hub_remote_endpoint_override_pending",
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
}
