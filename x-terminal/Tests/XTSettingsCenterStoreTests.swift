import Foundation
import Testing
@testable import XTerminal

struct XTSettingsCenterStoreTests {
    @Test
    @MainActor
    func appModelMirrorsSettingsCenterInputsIntoFocusedStore() async {
        let appModel = AppModel.makeForTesting()
        let hubBaseDir = URL(fileURLWithPath: "/tmp/xhub-settings-center", isDirectory: true)

        appModel.settingsStore.settings = appModel.settingsStore.settings.setting(
            role: .coder,
            providerKind: .hub,
            model: "openai/gpt-5.4"
        )
        appModel.modelsState = ModelStateSnapshot(models: [], updatedAt: 456)
        appModel.hubBaseDir = hubBaseDir
        appModel.hubConnected = true
        appModel.hubRemoteLinking = true
        appModel.hubRemoteSummary = "relay linking"
        appModel.hubSetupDiscoverState = .success
        appModel.hubSetupBootstrapState = .running
        appModel.hubSetupFailureCode = "local_network_permission_required"
        appModel.hubPairingPort = 50152
        appModel.hubGrpcPort = 50151
        appModel.hubInternetHost = "hub.example.com"
        appModel.localServerEnabled = true
        appModel.localServerPort = 8181
        appModel.hubRemoteLog = "settings log"

        for _ in 0..<20 {
            let snapshot = appModel.settingsCenterStore.snapshot
            if snapshot.settings.assignment(for: .coder).model == "openai/gpt-5.4",
               snapshot.modelsState.updatedAt == 456,
               snapshot.hubBaseDir == hubBaseDir,
               snapshot.hubConnected,
               snapshot.hubPairingPort == 50152,
               snapshot.localServerEnabled {
                return
            }
            await Task.yield()
        }

        let snapshot = appModel.settingsCenterStore.snapshot
        #expect(snapshot.settings.assignment(for: .coder).model == "openai/gpt-5.4")
        #expect(snapshot.modelsState.updatedAt == 456)
        #expect(snapshot.hubBaseDir == hubBaseDir)
        #expect(snapshot.hubConnected == true)
        #expect(snapshot.hubRemoteLinking == true)
        #expect(snapshot.hubRemoteSummary == "relay linking")
        #expect(snapshot.hubSetupDiscoverState == .success)
        #expect(snapshot.hubSetupBootstrapState == .running)
        #expect(snapshot.hubSetupFailureCode == "local_network_permission_required")
        #expect(snapshot.hubPairingPort == 50152)
        #expect(snapshot.hubGrpcPort == 50151)
        #expect(snapshot.hubInternetHost == "hub.example.com")
        #expect(snapshot.localServerEnabled == true)
        #expect(snapshot.localServerPort == 8181)
        #expect(snapshot.hubRemoteLog == "settings log")
    }

    @Test
    @MainActor
    func settingsCenterStoreSuppressesIdenticalSnapshots() {
        let snapshot = XTSettingsCenterSnapshot.empty
        let store = XTSettingsCenterStore(snapshot: snapshot)

        store.update(snapshot)

        #expect(store.snapshot == snapshot)
    }
}
