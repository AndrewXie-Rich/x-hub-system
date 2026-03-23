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

    private func writeModelsState(to dir: URL, models: [HubModel]) throws {
        let snapshot = ModelStateSnapshot(models: models, updatedAt: Date().timeIntervalSince1970)
        let url = dir.appendingPathComponent("models_state.json")
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: url, options: .atomic)
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
