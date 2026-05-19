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

        #expect(appModel.settingsValueStore.snapshot.assignment(for: .coder).model == "openai/gpt-5.4")

        let projection = appModel.settingsSurfaceProjectionStore.snapshot
        #expect(projection.settings.assignment(for: .coder).model == "openai/gpt-5.4")
        #expect(projection.modelsState.updatedAt == 456)
        #expect(projection.hubConnected == true)
        #expect(projection.hubRemoteLinking == true)
        #expect(projection.hubRemoteSummary == "relay linking")
        #expect(projection.hubRemoteLog == "settings log")
    }

    @Test
    @MainActor
    func settingsCenterStoreSuppressesIdenticalSnapshots() {
        let snapshot = XTSettingsCenterSnapshot.empty
        let store = XTSettingsCenterStore(snapshot: snapshot)

        store.update(snapshot)

        #expect(store.snapshot == snapshot)
    }

    @Test
    @MainActor
    func settingsValueStoreCarriesOnlySettings() {
        var settings = XTerminalSettings.default()
        settings = settings.setting(role: .supervisor, providerKind: .hub, model: "local/test-supervisor")
        let store = XTSettingsValueStore()

        store.update(settings)
        store.update(settings)

        #expect(store.snapshot == settings)
        #expect(store.snapshot.assignment(for: .supervisor).model == "local/test-supervisor")
    }

    @Test
    @MainActor
    func settingsSupervisorSignalStoreCarriesOnlySupervisorWindowSignals() {
        let store = XTSettingsSupervisorSignalStore()
        let snapshot = XTSettingsSupervisorSignalSnapshot(
            historicalProjectBoundaryRepairStatusLine: "historical_project_boundary_repair=noop reason=test"
        )

        store.update(snapshot)
        store.update(snapshot)

        #expect(store.snapshot == snapshot)
    }

    @Test
    @MainActor
    func settingsSurfaceProjectionKeepsOnlyDisplaySizedDiagnostics() {
        var snapshot = XTSettingsCenterSnapshot.empty
        snapshot.hubRemoteLog = String(repeating: "x", count: 17_000)
        snapshot.routeRepairLogLines = (0..<100).map { "route-line-\($0)" }

        let projection = XTSettingsSurfaceProjectionBuilder.build(from: snapshot)

        #expect(projection.hubRemoteLogIsTruncated == true)
        #expect(projection.hubRemoteLogOriginalUTF8Count == 17_000)
        #expect(projection.hubRemoteLog.contains("仅显示最近 16000 个字符"))
        #expect(projection.routeRepairLogTotalLineCount == 100)
        #expect(projection.routeRepairLogLines.count == 80)
        #expect(projection.routeRepairLogLines.first == "route-line-20")
        #expect(projection.routeRepairLogLines.last == "route-line-99")
    }

    @Test
    func settingsSurfaceFastProjectionPreservesPreviousDiagnostics() {
        var oldSnapshot = XTSettingsCenterSnapshot.empty
        oldSnapshot.hubRemoteLog = "old log"
        oldSnapshot.routeRepairLogLines = ["old-route"]
        let previous = XTSettingsSurfaceProjectionBuilder.build(from: oldSnapshot)

        var nextSnapshot = XTSettingsCenterSnapshot.empty
        nextSnapshot.hubConnected = true
        nextSnapshot.hubRemoteLog = String(repeating: "x", count: 17_000)
        nextSnapshot.routeRepairLogLines = (0..<100).map { "route-line-\($0)" }

        let projection = XTSettingsSurfaceProjectionBuilder.buildFast(
            from: nextSnapshot,
            preservingDiagnosticsFrom: previous
        )

        #expect(projection.hubConnected == true)
        #expect(projection.hubRemoteLog == "old log")
        #expect(projection.hubRemoteLogOriginalUTF8Count == "old log".utf8.count)
        #expect(projection.routeRepairLogLines == ["old-route"])
        #expect(projection.routeRepairLogTotalLineCount == 1)
    }

    @Test
    func settingsDiagnosticsProjectionInputBuildsDisplaySizedFallback() {
        var snapshot = XTSettingsCenterSnapshot.empty
        snapshot.hubConnected = true
        snapshot.hubRemoteLog = String(repeating: "x", count: 17_000)
        snapshot.routeRepairLogLines = (0..<100).map { "route-line-\($0)" }

        let input = XTSettingsDiagnosticsProjectionInputBuilder.build(from: snapshot)
        let diagnostics = XTSettingsDiagnosticsProjectionInputBuilder.buildProjection(from: input)

        #expect(input.connectionStateLabel == "已连接")
        #expect(diagnostics.hubRemoteLogTail.truncated == true)
        #expect(diagnostics.hubRemoteLogTail.totalBytes == 17_000)
        #expect(diagnostics.routeRepairTotalLineCount == 100)
        #expect(diagnostics.routeRepairRecentLines.count == 80)
        #expect(diagnostics.routeRepairRecentLines.first == "route-line-20")
        #expect(diagnostics.routeRepairRecentLines.last == "route-line-99")
    }
}
