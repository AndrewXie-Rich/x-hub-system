import XCTest
@testable import RELFlowHub
import RELFlowHubCore

final class LocalModelHealthRuntimeInvalidationPolicyTests: XCTestCase {
    func testRuntimeScopedBlockedRecordBecomesReviewWhenProviderIsReadyNewerThanScan() throws {
        let modelDir = try makeRunnableModelDir()
        let model = HubModel(
            id: "hf-qwen",
            name: "HF Qwen",
            backend: "transformers",
            quant: "fp16",
            contextLength: 8192,
            paramsB: 0.5,
            state: .available,
            modelPath: modelDir.path,
            taskKinds: ["text_generate"]
        )
        let checkedAt = Date().timeIntervalSince1970 - 10
        let record = LocalModelHealthRecord(
            modelId: model.id,
            providerID: "transformers",
            state: .blockedReadiness,
            summary: "不推荐",
            detail: "AI 运行时已启动，但 transformers provider 当前不可用 (当前 Python 运行时缺少 torch。)。",
            lastCheckedAt: checkedAt,
            lastSuccessAt: nil
        )
        let status = runtimeStatus(provider: "transformers", updatedAt: checkedAt + 5)

        let revalidated = LocalModelHealthRuntimeInvalidationPolicy.revalidatedRecord(
            record,
            model: model,
            runtimeStatus: status,
            now: checkedAt + 6
        )

        XCTAssertEqual(revalidated?.state, .degraded)
        XCTAssertEqual(revalidated?.summary, HubUIStrings.Models.LocalHealth.reviewBadge)
        XCTAssertEqual(revalidated?.detail, HubUIStrings.Models.LocalHealth.runtimeRevalidatedDetail)
    }

    func testModelIntegrityFailureIsNotInvalidatedByProviderReadiness() throws {
        let modelDir = try makeIncompleteShardModelDir()
        let model = HubModel(
            id: "hf-broken-vl",
            name: "Broken VL",
            backend: "transformers",
            quant: "fp16",
            contextLength: 8192,
            paramsB: 7.0,
            state: .available,
            modelPath: modelDir.path,
            taskKinds: ["vision_understand"]
        )
        let checkedAt = Date().timeIntervalSince1970 - 10
        let record = LocalModelHealthRecord(
            modelId: model.id,
            providerID: "transformers",
            state: .blockedReadiness,
            summary: "不推荐",
            detail: "无法加载。模型目录不完整，暂时无法加载。缺少 1 个权重分片。",
            lastCheckedAt: checkedAt,
            lastSuccessAt: nil
        )
        let status = runtimeStatus(provider: "transformers", updatedAt: checkedAt + 5)

        XCTAssertNil(
            LocalModelHealthRuntimeInvalidationPolicy.revalidatedRecord(
                record,
                model: model,
                runtimeStatus: status,
                now: checkedAt + 6
            )
        )
    }

    private func runtimeStatus(provider: String, updatedAt: TimeInterval) -> AIRuntimeStatus {
        AIRuntimeStatus(
            pid: 100,
            updatedAt: updatedAt,
            mlxOk: true,
            providers: [
                provider: AIRuntimeProviderStatus(
                    provider: provider,
                    ok: true,
                    reasonCode: "ready",
                    runtimeResolutionState: "pack_runtime_ready",
                    runtimeReasonCode: "ready",
                    availableTaskKinds: ["text_generate", "vision_understand", "ocr", "embedding"],
                    loadedModels: [],
                    deviceBackend: "mps_or_cpu",
                    updatedAt: updatedAt
                ),
            ]
        )
    }

    private func makeRunnableModelDir() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: root.appendingPathComponent("config.json"))
        try Data("{}".utf8).write(to: root.appendingPathComponent("tokenizer.json"))
        try Data().write(to: root.appendingPathComponent("model.safetensors"))
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    private func makeIncompleteShardModelDir() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try JSONSerialization.data(
            withJSONObject: [
                "weight_map": [
                    "model.layers.0.weight": "model-00001-of-00002.safetensors",
                ],
            ],
            options: [.sortedKeys]
        ).write(to: root.appendingPathComponent("model.safetensors.index.json"))
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }
}
