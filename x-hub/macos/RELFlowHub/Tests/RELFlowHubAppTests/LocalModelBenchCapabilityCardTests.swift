import XCTest
@testable import RELFlowHub
@testable import RELFlowHubCore

final class LocalModelBenchCapabilityCardTests: XCTestCase {
    func testBuilderSummarizesFallbackPreviewCard() {
        let model = HubModel(
            id: "hf-embed",
            name: "HF Embed",
            backend: "transformers",
            quant: "fp16",
            contextLength: 8192,
            maxContextLength: 65536,
            paramsB: 0.4,
            state: .loaded,
            modelPath: "/tmp/models/hf-embed",
            defaultLoadProfile: LocalModelLoadProfile(contextLength: 8192),
            taskKinds: ["embedding"]
        )
        let requestContext = LocalModelRuntimeRequestContext(
            providerID: "transformers",
            modelID: "hf-embed",
            deviceID: "",
            instanceKey: "transformers:hf-embed:abcd1234deadbeef",
            loadProfileHash: "abcd1234deadbeef",
            predictedLoadProfileHash: "abcd1234deadbeef",
            effectiveContextLength: 32768,
            loadProfileOverride: nil,
            effectiveLoadProfile: LocalModelLoadProfile(contextLength: 32768, ttl: 600, parallel: 2),
            source: "selected_loaded_instance"
        )
        let runtimeStatus = AIRuntimeStatus(
            pid: 321,
            updatedAt: Date().timeIntervalSince1970,
            mlxOk: false,
            providers: [
                "transformers": AIRuntimeProviderStatus(
                    provider: "transformers",
                    ok: true,
                    reasonCode: "ready",
                    availableTaskKinds: ["embedding"],
                    loadedModels: ["hf-embed"],
                    deviceBackend: "mps",
                    updatedAt: Date().timeIntervalSince1970,
                    lifecycleMode: "warmable",
                    residencyScope: "runtime_process",
                    loadedInstances: [
                        AIRuntimeLoadedInstance(
                            instanceKey: "transformers:hf-embed:abcd1234deadbeef",
                            modelId: "hf-embed",
                            taskKinds: ["embedding"],
                            loadProfileHash: "abcd1234deadbeef",
                            effectiveContextLength: 32768,
                            loadedAt: 100,
                            lastUsedAt: 120,
                            residency: "resident",
                            residencyScope: "runtime_process",
                            deviceBackend: "mps"
                        ),
                    ]
                ),
            ],
            monitorSnapshot: AIRuntimeMonitorSnapshot(
                schemaVersion: "monitor.v1",
                updatedAt: Date().timeIntervalSince1970,
                providers: [
                    AIRuntimeMonitorProvider(
                        provider: "transformers",
                        ok: true,
                        reasonCode: "ready",
                        realTaskKinds: ["embedding"],
                        fallbackTaskKinds: ["embedding"],
                        deviceBackend: "mps",
                        lifecycleMode: "warmable",
                        residencyScope: "runtime_process",
                        loadedInstanceCount: 1,
                        loadedModelCount: 1,
                        activeTaskCount: 0,
                        queuedTaskCount: 0,
                        concurrencyLimit: 1,
                        queueMode: "fifo",
                        queueingSupported: true,
                        updatedAt: Date().timeIntervalSince1970
                    ),
                ]
            )
        )
        let benchResult = ModelBenchResult(
            modelId: "hf-embed",
            providerID: "transformers",
            taskKind: "embedding",
            loadProfileHash: "abcd1234deadbeef",
            fixtureProfile: "embed_small_docs",
            fixtureTitle: "Small Docs",
            ok: true,
            runtimeSource: "provider_runtime",
            runtimeResolutionState: "ready",
            fallbackUsed: true,
            verdict: "Preview only",
            fallbackMode: "cpu_preview",
            effectiveContextLength: 32768
        )
        let explanation = LocalModelBenchMonitorExplanationBuilder.build(
            model: model,
            taskKind: "embedding",
            requestContext: requestContext,
            benchResult: benchResult,
            runtimeStatus: runtimeStatus
        )

        let card = LocalModelBenchCapabilityCardBuilder.build(
            model: model,
            taskKind: "embedding",
            requestContext: requestContext,
            benchResult: benchResult,
            explanation: explanation,
            runtimeStatus: runtimeStatus
        )

        XCTAssertEqual(card.headline, "CPU 回退")
        XCTAssertEqual(card.tone, .caution)
        XCTAssertTrue(card.badges.contains(where: { $0.title == "仅预览" }))
        XCTAssertTrue(card.badges.contains(where: { $0.title == "CPU 回退" }))
        XCTAssertTrue(card.badges.contains(where: { $0.title == "已常驻" }))
        XCTAssertEqual(card.insights.first(where: { $0.label == "适合" })?.value, "兼容性检查和预览流量")
        XCTAssertEqual(
            card.insights.first(where: { $0.label == "不适合" })?.value,
            "对延迟敏感或生产关键的 向量 流量"
        )
        XCTAssertEqual(
            card.insights.first(where: { $0.label == "需要预热" })?.value,
            "不需要。匹配的常驻目标已经加载。"
        )
    }

    func testBuilderHighlightsQueueAndWarmupWhenNoBenchYet() {
        let model = HubModel(
            id: "hf-embed",
            name: "HF Embed",
            backend: "transformers",
            quant: "fp16",
            contextLength: 8192,
            maxContextLength: 65536,
            paramsB: 0.4,
            state: .available,
            modelPath: "/tmp/models/hf-embed",
            defaultLoadProfile: LocalModelLoadProfile(contextLength: 8192),
            taskKinds: ["embedding"]
        )
        let requestContext = LocalModelRuntimeRequestContext(
            providerID: "transformers",
            modelID: "hf-embed",
            deviceID: "terminal_device",
            instanceKey: "",
            loadProfileHash: "",
            predictedLoadProfileHash: "predicted-hash",
            effectiveContextLength: 16384,
            loadProfileOverride: LocalModelLoadProfileOverride(contextLength: 16384),
            source: "paired_terminal_default"
        )
        let runtimeStatus = AIRuntimeStatus(
            pid: 321,
            updatedAt: Date().timeIntervalSince1970,
            mlxOk: false,
            providers: [
                "transformers": AIRuntimeProviderStatus(
                    provider: "transformers",
                    ok: true,
                    reasonCode: "ready",
                    availableTaskKinds: ["embedding"],
                    loadedModels: [],
                    deviceBackend: "mps",
                    updatedAt: Date().timeIntervalSince1970,
                    lifecycleMode: "warmable",
                    residencyScope: "runtime_process",
                    loadedInstances: []
                ),
            ],
            monitorSnapshot: AIRuntimeMonitorSnapshot(
                schemaVersion: "monitor.v1",
                updatedAt: Date().timeIntervalSince1970,
                providers: [
                    AIRuntimeMonitorProvider(
                        provider: "transformers",
                        ok: true,
                        reasonCode: "ready",
                        realTaskKinds: ["embedding"],
                        deviceBackend: "mps",
                        lifecycleMode: "warmable",
                        residencyScope: "runtime_process",
                        loadedInstanceCount: 0,
                        loadedModelCount: 0,
                        activeTaskCount: 0,
                        queuedTaskCount: 2,
                        concurrencyLimit: 1,
                        queueMode: "fifo",
                        queueingSupported: true,
                        oldestWaiterAgeMs: 1400,
                        updatedAt: Date().timeIntervalSince1970
                    ),
                ]
            )
        )
        let explanation = LocalModelBenchMonitorExplanationBuilder.build(
            model: model,
            taskKind: "embedding",
            requestContext: requestContext,
            benchResult: nil,
            runtimeStatus: runtimeStatus
        )

        let card = LocalModelBenchCapabilityCardBuilder.build(
            model: model,
            taskKind: "embedding",
            requestContext: requestContext,
            benchResult: nil,
            explanation: explanation,
            runtimeStatus: runtimeStatus
        )

        XCTAssertEqual(card.headline, "当前提供方队列繁忙")
        XCTAssertEqual(card.tone, .caution)
        XCTAssertTrue(card.badges.contains(where: { $0.title == "需要预热" }))
        XCTAssertTrue(card.badges.contains(where: { $0.title == "2 个等待" }))
        XCTAssertEqual(
            card.insights.first(where: { $0.label == "需要预热" })?.value,
            "需要。当前目标还没有常驻，下一次运行可能会冷启动。"
        )
        XCTAssertTrue(
            card.insights.first(where: { $0.label == "运行时" })?.value.contains("2 个等待") == true
        )
    }
}
