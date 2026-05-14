import Foundation
import Testing
@testable import XTerminal

struct XTModelSettingsStoreTests {
    @Test
    @MainActor
    func appModelMirrorsModelSettingsInputsIntoFocusedStore() async {
        let appModel = AppModel.makeForTesting()
        let hubBaseDir = URL(fileURLWithPath: "/tmp/xhub-model-settings", isDirectory: true)

        appModel.settingsStore.settings = appModel.settingsStore.settings.setting(
            role: .coder,
            providerKind: .hub,
            model: "openai/gpt-5.4"
        )
        appModel.modelsState = ModelStateSnapshot(models: [], updatedAt: 123)
        appModel.hubBaseDir = hubBaseDir
        appModel.hubConnected = true
        appModel.hubRemoteConnected = true
        appModel.hubRemoteRoute = .internet
        appModel.hubRemotePaidAccessSnapshot = HubRemotePaidAccessSnapshot(
            trustProfilePresent: true,
            paidModelPolicyMode: "allowlisted",
            dailyTokenLimit: 10_000,
            singleRequestTokenLimit: 2_000
        )

        for _ in 0..<20 {
            let snapshot = appModel.modelSettingsStore.snapshot
            if snapshot.settings.assignment(for: .coder).model == "openai/gpt-5.4",
               snapshot.hubInteractive,
               snapshot.hubBaseDir == hubBaseDir,
               snapshot.remotePaidAccessSnapshot?.trustProfilePresent == true {
                return
            }
            await Task.yield()
        }

        let snapshot = appModel.modelSettingsStore.snapshot
        #expect(snapshot.settings.assignment(for: .coder).model == "openai/gpt-5.4")
        #expect(snapshot.modelsState.updatedAt == 123)
        #expect(snapshot.hubBaseDir == hubBaseDir)
        #expect(snapshot.hubInteractive == true)
        #expect(snapshot.hubRemoteConnected == true)
        #expect(snapshot.hubRemoteRoute == .internet)
        #expect(snapshot.remotePaidAccessSnapshot?.trustProfilePresent == true)
    }

    @Test
    @MainActor
    func modelSettingsStoreSuppressesIdenticalSnapshots() {
        let snapshot = XTModelSettingsSnapshot.empty
        let store = XTModelSettingsStore(snapshot: snapshot)

        store.update(snapshot)

        #expect(store.snapshot == snapshot)
    }
}
