import Testing
@testable import XTerminal

struct XTHubConnectionStoreTests {
    @Test
    @MainActor
    func appModelMirrorsHubConnectionFieldsIntoFocusedStore() {
        let appModel = AppModel.makeForTesting()

        appModel.hubRemoteConnected = true
        appModel.hubRemoteRoute = .internetTunnel
        appModel.hubRemoteSummary = "remote tunnel ready"
        appModel.hubRemotePaidAccessSnapshot = HubRemotePaidAccessSnapshot(
            trustProfilePresent: true,
            paidModelPolicyMode: "allow_paid_models",
            dailyTokenLimit: 100_000,
            singleRequestTokenLimit: 8_000
        )

        let snapshot = appModel.hubConnectionStore.snapshot
        #expect(snapshot.localConnected == false)
        #expect(snapshot.remoteConnected)
        #expect(snapshot.remoteRoute == .internetTunnel)
        #expect(snapshot.remoteSummary == "remote tunnel ready")
        #expect(snapshot.remotePaidAccessSnapshot?.trustProfilePresent == true)
        #expect(snapshot.remotePaidAccessSnapshot?.singleRequestTokenLimit == 8_000)
        #expect(snapshot.interactive)
    }

    @Test
    func presentationPrefersLocalRouteOverRemoteRoute() {
        let snapshot = XTHubConnectionSnapshot(
            localConnected: true,
            remoteConnected: true,
            remoteLinking: false,
            remoteRoute: .internetTunnel,
            remoteSummary: "",
            lastError: nil
        )

        #expect(XTHubConnectionPresentation.statusLabel(for: snapshot) == "local")
        #expect(XTHubConnectionPresentation.statusTone(for: snapshot) == .localReady)
        #expect(XTHubConnectionPresentation.controlButtonTitle(for: snapshot) == "Control · Hub Local")
        #expect(XTHubConnectionPresentation.menuCommandTitle(for: snapshot) == "Hub Connected")
    }

    @Test
    func presentationSurfacesRemoteTunnelRouteForMenuCommand() {
        let snapshot = XTHubConnectionSnapshot(
            localConnected: false,
            remoteConnected: true,
            remoteLinking: false,
            remoteRoute: .internetTunnel,
            remoteSummary: "",
            lastError: nil
        )

        #expect(XTHubConnectionPresentation.statusLabel(for: snapshot) == "remote")
        #expect(XTHubConnectionPresentation.statusTone(for: snapshot) == .remoteReady)
        #expect(XTHubConnectionPresentation.controlButtonTitle(for: snapshot) == "Control · Hub Remote")
        #expect(XTHubConnectionPresentation.menuCommandTitle(for: snapshot) == "Hub Relay (Tunnel)")
    }

    @Test
    func presentationKeepsOfflineConnectPrompt() {
        let snapshot = XTHubConnectionSnapshot.disconnected

        #expect(!snapshot.interactive)
        #expect(XTHubConnectionPresentation.statusLabel(for: snapshot) == "off")
        #expect(XTHubConnectionPresentation.statusTone(for: snapshot) == .offline)
        #expect(XTHubConnectionPresentation.controlButtonIconName(for: snapshot) == "link.badge.plus")
        #expect(XTHubConnectionPresentation.controlButtonTitle(for: snapshot) == "Control · Connect Hub")
    }
}
