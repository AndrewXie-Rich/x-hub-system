import XCTest
@testable import RELFlowHub
@testable import RELFlowHubCore

final class LocalModelBenchMonitorExplanationTests: XCTestCase {
    func testBuilderExplainsQueueAndColdStartForUnloadedTarget() {
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
                    supportedLifecycleActions: ["warmup_local_model"],
                    warmupTaskKinds: ["embedding"],
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
                        activeMemoryBytes: 4_000_000,
                        peakMemoryBytes: 6_000_000,
                        memoryState: "tracked",
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

        XCTAssertEqual(explanation?.headline, "当前提供方队列繁忙")
        XCTAssertEqual(explanation?.severity, .warning)
        XCTAssertTrue(explanation?.detailLines.contains("目标载入：ctx=16384。") == true)
        XCTAssertTrue(explanation?.detailLines.contains("队列：2 个等待，最久等待 1400ms。") == true)
        XCTAssertTrue(explanation?.detailLines.contains("目标常驻：没有匹配的已加载实例；下一次运行可能会冷启动。") == true)
    }

    func testBuilderExplainsFallbackAndResidentInstance() {
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
            effectiveLoadProfile: LocalModelLoadProfile(
                contextLength: 32768,
                ttl: 600,
                parallel: 2,
                identifier: "bench-a",
                vision: LocalModelVisionLoadProfile(imageMaxDimension: 2048)
            ),
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
                    supportedLifecycleActions: ["warmup_local_model", "unload_local_model"],
                    warmupTaskKinds: ["embedding"],
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
                        activeMemoryBytes: 4_000_000,
                        peakMemoryBytes: 6_000_000,
                        memoryState: "tracked",
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
            ok: true,
            reasonCode: "fallback_only",
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

        XCTAssertEqual(explanation?.headline, "本次 Bench 走了回退路径")
        XCTAssertEqual(explanation?.severity, .warning)
        XCTAssertTrue(explanation?.detailLines.contains("目标载入：ctx=32768 · ttl=600s · par=2 · id=bench-a · img=2048。") == true)
        XCTAssertTrue(explanation?.detailLines.contains("Bench 载入：ctx=32768 · profile=abcd1234（与当前目标一致）。") == true)
        XCTAssertTrue(explanation?.detailLines.contains("回退模式：cpu_preview") == true)
        XCTAssertTrue(explanation?.detailLines.contains("目标常驻：实例 abcd1234 已加载。") == true)
    }
}
