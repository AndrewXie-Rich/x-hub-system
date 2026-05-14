import Testing
@testable import XTerminal

struct XTControlSurfaceStoreTests {
    @Test
    @MainActor
    func appModelMirrorsRoleAssignmentsAndBridgeIntoFocusedControlSurfaceStore() async {
        let appModel = AppModel.makeForTesting()

        appModel.settingsStore.settings = appModel.settingsStore.settings.setting(
            role: .coder,
            providerKind: .hub,
            model: "openai/gpt-5.4"
        )
        appModel.bridgeEnabled = true

        for _ in 0..<20 {
            let snapshot = appModel.controlSurfaceStore.snapshot
            if snapshot.roleAssignmentSummary.contains("编程助手: openai/gpt-5.4"),
               snapshot.bridgeEnabled == true {
                return
            }
            await Task.yield()
        }

        let snapshot = appModel.controlSurfaceStore.snapshot
        #expect(snapshot.roleAssignmentSummary.contains("编程助手: openai/gpt-5.4"))
        #expect(snapshot.bridgeEnabled == true)
    }

    @Test
    @MainActor
    func controlSurfaceStoreSuppressesIdenticalSnapshots() {
        let snapshot = XTControlSurfaceSnapshot(
            roleAssignmentSummary: "Supervisor: auto · 编程助手: auto · 代码审查: auto",
            bridgeEnabled: false
        )
        let store = XTControlSurfaceStore(snapshot: snapshot)

        store.update(snapshot)

        #expect(store.snapshot == snapshot)
    }
}
