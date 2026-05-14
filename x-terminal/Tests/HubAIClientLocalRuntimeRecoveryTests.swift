import Foundation
import Testing
@testable import XTerminal

@Suite(.serialized)
struct HubAIClientLocalRuntimeRecoveryTests {
    @Test
    func enqueueLocalGenerateWritesRequestWhenRuntimeMissingButAutoLoadEnabled() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let originalMode = HubAIClient.transportMode()
        HubPaths.setPinnedBaseDirOverride(tempDir)
        HubAIClient.setTransportMode(.fileIPC)

        defer {
            HubAIClient.setTransportMode(originalMode)
            HubPaths.clearPinnedBaseDirOverride()
            try? FileManager.default.removeItem(at: tempDir)
        }

        try writeModelsState(to: tempDir, models: [localLoadedModel()])

        let reqId = try await HubAIClient.shared.enqueueGenerate(
            prompt: "hello",
            taskType: "assist",
            autoLoad: true,
            transportOverride: .fileIPC
        )

        let reqURL = tempDir
            .appendingPathComponent("ai_requests", isDirectory: true)
            .appendingPathComponent("req_\(reqId).json")
        #expect(FileManager.default.fileExists(atPath: reqURL.path))

        let data = try Data(contentsOf: reqURL)
        let req = try JSONDecoder().decode(HubAIRequest.self, from: data)
        #expect(req.auto_load)
    }

    @Test
    func enqueueLocalGenerateStillFailsFastWhenRuntimeMissingAndAutoLoadDisabled() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let originalMode = HubAIClient.transportMode()
        HubPaths.setPinnedBaseDirOverride(tempDir)
        HubAIClient.setTransportMode(.fileIPC)

        defer {
            HubAIClient.setTransportMode(originalMode)
            HubPaths.clearPinnedBaseDirOverride()
            try? FileManager.default.removeItem(at: tempDir)
        }

        try writeModelsState(to: tempDir, models: [localLoadedModel()])

        do {
            _ = try await HubAIClient.shared.enqueueGenerate(
                prompt: "hello",
                taskType: "assist",
                autoLoad: false,
                transportOverride: .fileIPC
            )
            Issue.record("Expected HubAIError.runtimeNotRunning")
        } catch let error as HubAIError {
            switch error {
            case .runtimeNotRunning:
                break
            default:
                Issue.record("Unexpected HubAIError: \(String(describing: error.errorDescription ?? ""))")
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test
    func loadRuntimeStatusRejectsHeartbeatOnlyStatus() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        HubPaths.setPinnedBaseDirOverride(tempDir)
        defer {
            HubPaths.clearPinnedBaseDirOverride()
            try? FileManager.default.removeItem(at: tempDir)
        }

        try writeRuntimeStatus(
            """
            {
              "pid": 46081,
              "updatedAt": \(Date().timeIntervalSince1970),
              "mlxOk": true,
              "runtimeVersion": "2026-02-11-runtime-stop-v1",
              "loadedModelCount": 0
            }
            """,
            to: tempDir
        )

        let status = await HubAIClient.shared.loadRuntimeStatus()
        #expect(status == nil)
    }

    @Test
    func loadRuntimeStatusAcceptsAuthoritativeStatusSnapshot() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        HubPaths.setPinnedBaseDirOverride(tempDir)
        defer {
            HubPaths.clearPinnedBaseDirOverride()
            try? FileManager.default.removeItem(at: tempDir)
        }

        let now = Date().timeIntervalSince1970
        try writeRuntimeStatus(
            """
            {
              "schema_version": "xhub.local_runtime_status.v2",
              "pid": 9041,
              "updatedAt": \(now),
              "mlxOk": true,
              "runtimeVersion": "2026-03-14-mlx-instance-identity-v1",
              "providers": {
                "mlx": {
                  "provider": "mlx",
                  "ok": true,
                  "reasonCode": "ready",
                  "runtimeVersion": "2026-03-14-mlx-instance-identity-v1",
                  "availableTaskKinds": ["text_generate"],
                  "loadedModels": [],
                  "deviceBackend": "mps",
                  "updatedAt": \(now),
                  "loadedModelCount": 0
                }
              },
              "loadedInstanceCount": 0
            }
            """,
            to: tempDir
        )

        let status = await HubAIClient.shared.loadRuntimeStatus()
        let resolvedStatus = try #require(status)
        #expect(resolvedStatus.hasAuthoritativeRuntimeState)
        #expect(resolvedStatus.runtimeVersion == "2026-03-14-mlx-instance-identity-v1")
    }

    private func writeModelsState(to dir: URL, models: [HubModel]) throws {
        let snapshot = ModelStateSnapshot(models: models, updatedAt: Date().timeIntervalSince1970)
        let url = dir.appendingPathComponent("models_state.json")
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: url, options: .atomic)
    }

    private func writeRuntimeStatus(_ payload: String, to dir: URL) throws {
        try payload.write(
            to: dir.appendingPathComponent("ai_runtime_status.json"),
            atomically: true,
            encoding: .utf8
        )
    }

    private func localLoadedModel() -> HubModel {
        HubModel(
            id: "qwen3-14b-mlx",
            name: "Qwen 14B",
            backend: "mlx",
            quant: "bf16",
            contextLength: 32_768,
            paramsB: 14,
            roles: nil,
            state: .loaded,
            memoryBytes: nil,
            tokensPerSec: nil,
            modelPath: "/models/qwen3",
            note: nil
        )
    }
}
