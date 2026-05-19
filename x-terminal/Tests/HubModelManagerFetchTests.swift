import Foundation
import Testing
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
@testable import XTerminal

@Suite(.serialized)
struct HubModelManagerFetchTests {
    @MainActor
    @Test
    func fetchModelsShowsLocalSnapshotBeforeRemoteOverlayCompletes() async throws {
        let tempRoot = try makeTempDir(prefix: "hub_model_manager_local_first")
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let stateDir = tempRoot.appendingPathComponent("axhub", isDirectory: true)
        let baseDir = tempRoot.appendingPathComponent("RELFlowHub", isDirectory: true)
        try FileManager.default.createDirectory(at: stateDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)

        let localModel = hubModel(id: "local/qwen3-14b")
        let remoteModel = hubModel(id: "openai/gpt-5.4")
        let paidSnapshot = HubRemotePaidAccessSnapshot(
            trustProfilePresent: true,
            paidModelPolicyMode: "allow_all",
            dailyTokenLimit: 20_000,
            singleRequestTokenLimit: 4_000
        )
        let remoteCounter = RemoteFetchCounter()

        try writeHubEnv(to: stateDir)
        try writeModelsState([localModel], to: baseDir)

        try await withAXHubStateDir(stateDir) {
            try await withTransportMode(.grpc) {
                await HubAIClient.resetRemoteModelSnapshotCacheForTesting()
                HubAIClient.installRemoteModelsOverrideForTesting { _ in
                    await remoteCounter.increment()
                    try? await Task.sleep(nanoseconds: 900_000_000)
                    return HubRemoteModelsResult(
                        ok: true,
                        models: [remoteModel],
                        paidAccessSnapshot: paidSnapshot,
                        reasonCode: nil,
                        logLines: []
                    )
                }
                defer {
                    HubAIClient.resetRemoteModelsOverrideForTesting()
                    HubPaths.clearPinnedBaseDirOverride()
                }
                HubPaths.setPinnedBaseDirOverride(baseDir)

                let appModel = AppModel.makeForTesting()
                appModel.hubRemoteConnected = true
                let manager = HubModelManager()
                manager.setAppModel(appModel)

                let fetchTask = Task { @MainActor in
                    await manager.fetchModels()
                }

                let localStateVisible = await waitUntil(timeoutNanoseconds: 500_000_000) {
                    manager.isLoading == false
                        && manager.latestSnapshot.models.map(\.id) == [localModel.id]
                }

                #expect(localStateVisible == true)
                #expect(manager.latestSnapshot.models.map(\.id) == [localModel.id])
                #expect(manager.availableModels.map(\.id) == [localModel.id])
                #expect(appModel.hubRemotePaidAccessSnapshot == nil)

                await fetchTask.value

                #expect(await remoteCounter.value() == 1)
                #expect(manager.latestSnapshot.models.map(\.id) == [remoteModel.id])
                #expect(manager.availableModels.map(\.id) == [remoteModel.id])
                #expect(appModel.hubRemotePaidAccessSnapshot == paidSnapshot)

                await HubAIClient.resetRemoteModelSnapshotCacheForTesting()
            }
        }
    }

    @MainActor
    @Test
    func fetchModelsUsesAuthoritativeRemoteSnapshotWhenRemoteProfileExistsEvenIfConnectionFlagIsStale() async throws {
        let tempRoot = try makeTempDir(prefix: "hub_model_manager_local_only")
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let stateDir = tempRoot.appendingPathComponent("axhub", isDirectory: true)
        let baseDir = tempRoot.appendingPathComponent("RELFlowHub", isDirectory: true)
        try FileManager.default.createDirectory(at: stateDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)

        let localModel = hubModel(id: "local/phi-4")
        let remoteCounter = RemoteFetchCounter()

        try writeHubEnv(to: stateDir)
        try writeModelsState([localModel], to: baseDir)

        try await withAXHubStateDir(stateDir) {
            try await withTransportMode(.grpc) {
                await HubAIClient.resetRemoteModelSnapshotCacheForTesting()
                HubAIClient.installRemoteModelsOverrideForTesting { _ in
                    await remoteCounter.increment()
                    return HubRemoteModelsResult(
                        ok: true,
                        models: [hubModel(id: "openai/gpt-5.4")],
                        paidAccessSnapshot: nil,
                        reasonCode: nil,
                        logLines: []
                    )
                }
                defer {
                    HubAIClient.resetRemoteModelsOverrideForTesting()
                    HubPaths.clearPinnedBaseDirOverride()
                }
                HubPaths.setPinnedBaseDirOverride(baseDir)

                let appModel = AppModel.makeForTesting()
                appModel.hubRemoteConnected = false
                let manager = HubModelManager()
                manager.setAppModel(appModel)

                await manager.fetchModels()

                #expect(await remoteCounter.value() == 1)
                #expect(manager.latestSnapshot.models.map(\.id) == ["openai/gpt-5.4"])
                #expect(manager.availableModels.map(\.id) == ["openai/gpt-5.4"])
                #expect(appModel.hubRemotePaidAccessSnapshot == nil)

                await HubAIClient.resetRemoteModelSnapshotCacheForTesting()
            }
        }
    }

    @MainActor
    @Test
    func fetchModelsSkipsRemoteOverlayWhenTransportIsForcedFileIPC() async throws {
        let tempRoot = try makeTempDir(prefix: "hub_model_manager_fileipc_only")
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let stateDir = tempRoot.appendingPathComponent("axhub", isDirectory: true)
        let baseDir = tempRoot.appendingPathComponent("RELFlowHub", isDirectory: true)
        try FileManager.default.createDirectory(at: stateDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)

        let localModel = hubModel(id: "local/phi-4")
        let remoteCounter = RemoteFetchCounter()

        try writeHubEnv(to: stateDir)
        try writeModelsState([localModel], to: baseDir)

        try await withAXHubStateDir(stateDir) {
            try await withTransportMode(.fileIPC) {
                await HubAIClient.resetRemoteModelSnapshotCacheForTesting()
                HubAIClient.installRemoteModelsOverrideForTesting { _ in
                    await remoteCounter.increment()
                    return HubRemoteModelsResult(
                        ok: true,
                        models: [hubModel(id: "openai/gpt-5.4")],
                        paidAccessSnapshot: nil,
                        reasonCode: nil,
                        logLines: []
                    )
                }
                defer {
                    HubAIClient.resetRemoteModelsOverrideForTesting()
                    HubPaths.clearPinnedBaseDirOverride()
                }
                HubPaths.setPinnedBaseDirOverride(baseDir)

                let appModel = AppModel.makeForTesting()
                appModel.hubRemoteConnected = false
                let manager = HubModelManager()
                manager.setAppModel(appModel)

                await manager.fetchModels()

                #expect(await remoteCounter.value() == 0)
                #expect(manager.latestSnapshot.models.map(\.id) == [localModel.id])
                #expect(manager.availableModels.map(\.id) == [localModel.id])
                #expect(appModel.hubRemotePaidAccessSnapshot == nil)

                await HubAIClient.resetRemoteModelSnapshotCacheForTesting()
            }
        }
    }

    @MainActor
    @Test
    func fetchModelsFallsBackToRemoteWhenLocalInventoryIsEmpty() async throws {
        let tempRoot = try makeTempDir(prefix: "hub_model_manager_remote_fallback")
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let stateDir = tempRoot.appendingPathComponent("axhub", isDirectory: true)
        let baseDir = tempRoot.appendingPathComponent("RELFlowHub", isDirectory: true)
        try FileManager.default.createDirectory(at: stateDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)

        let remoteModel = hubModel(id: "openai/gpt-5.4")
        let paidSnapshot = HubRemotePaidAccessSnapshot(
            trustProfilePresent: true,
            paidModelPolicyMode: "allow_all",
            dailyTokenLimit: 12_000,
            singleRequestTokenLimit: 2_000
        )
        let remoteCounter = RemoteFetchCounter()

        try writeHubEnv(to: stateDir)
        try writeModelsState([], to: baseDir)

        try await withAXHubStateDir(stateDir) {
            try await withTransportMode(.grpc) {
                await HubAIClient.resetRemoteModelSnapshotCacheForTesting()
                HubAIClient.installRemoteModelsOverrideForTesting { _ in
                    await remoteCounter.increment()
                    return HubRemoteModelsResult(
                        ok: true,
                        models: [remoteModel],
                        paidAccessSnapshot: paidSnapshot,
                        reasonCode: nil,
                        logLines: []
                    )
                }
                defer {
                    HubAIClient.resetRemoteModelsOverrideForTesting()
                    HubPaths.clearPinnedBaseDirOverride()
                }
                HubPaths.setPinnedBaseDirOverride(baseDir)

                let appModel = AppModel.makeForTesting()
                appModel.hubRemoteConnected = false
                let manager = HubModelManager()
                manager.setAppModel(appModel)

                await manager.fetchModels()

                #expect(await remoteCounter.value() == 1)
                #expect(manager.latestSnapshot.models.map(\.id) == [remoteModel.id])
                #expect(manager.availableModels.map(\.id) == [remoteModel.id])
                #expect(appModel.hubRemotePaidAccessSnapshot == paidSnapshot)

                await HubAIClient.resetRemoteModelSnapshotCacheForTesting()
            }
        }
    }

    private func makeTempDir(prefix: String) throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(prefix, isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func withAXHubStateDir<T>(
        _ stateDir: URL,
        body: () async throws -> T
    ) async throws -> T {
        let key = "AXHUBCTL_STATE_DIR"
        let previous = getenv(key).flatMap { String(validatingUTF8: $0) }
        setenv(key, stateDir.path, 1)
        defer {
            if let previous {
                setenv(key, previous, 1)
            } else {
                unsetenv(key)
            }
        }
        return try await body()
    }

    private func withTransportMode<T>(
        _ mode: HubTransportMode,
        body: () async throws -> T
    ) async throws -> T {
        let defaults = UserDefaults.standard
        let key = "xterminal_hub_transport_mode"
        let previous = defaults.object(forKey: key)
        HubAIClient.setTransportMode(mode)
        defer {
            if let previous {
                defaults.set(previous, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
        return try await body()
    }

    private func writeHubEnv(to stateDir: URL) throws {
        let payload = """
        export HUB_HOST='remote.example.com'
        export HUB_PORT='50052'
        export HUB_CLIENT_TOKEN='token'
        """
        try payload.write(
            to: stateDir.appendingPathComponent("hub.env"),
            atomically: true,
            encoding: .utf8
        )
    }

    private func writeModelsState(_ models: [HubModel], to baseDir: URL) throws {
        let snapshot = ModelStateSnapshot(
            models: models,
            updatedAt: Date().timeIntervalSince1970
        )
        let data = try JSONEncoder().encode(snapshot)
        try data.write(
            to: baseDir.appendingPathComponent("models_state.json"),
            options: .atomic
        )
    }

    private func hubModel(id: String) -> HubModel {
        HubModel(
            id: id,
            name: id,
            backend: id.hasPrefix("openai/") ? "openai" : "mlx",
            quant: id.hasPrefix("openai/") ? "n/a" : "bf16",
            contextLength: 32_768,
            paramsB: id.hasPrefix("openai/") ? 0 : 14,
            roles: nil,
            state: .loaded,
            memoryBytes: nil,
            tokensPerSec: nil,
            modelPath: id.hasPrefix("openai/") ? nil : "/models/\(id)",
            note: nil
        )
    }

    private func waitUntil(
        timeoutNanoseconds: UInt64,
        pollNanoseconds: UInt64 = 25_000_000,
        condition: @escaping @MainActor () -> Bool
    ) async -> Bool {
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
        while DispatchTime.now().uptimeNanoseconds < deadline {
            if await condition() {
                return true
            }
            try? await Task.sleep(nanoseconds: pollNanoseconds)
        }
        return await condition()
    }
}

private actor RemoteFetchCounter {
    private var count: Int = 0

    func increment() {
        count += 1
    }

    func value() -> Int {
        count
    }
}
