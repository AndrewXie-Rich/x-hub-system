import XCTest
@testable import RELFlowHub
import RELFlowHubCore

final class LocalRuntimeOperationsSummaryBuilderTests: XCTestCase {
    func testBuildMarksMatchingLoadedInstanceAsCurrentTarget() {
        let now = Date()
        let nowSeconds = now.timeIntervalSince1970
        let model = HubModel(
            id: "vision-local",
            name: "Vision Local",
            backend: "mlx",
            runtimeProviderID: "transformers",
            quant: "int4",
            contextLength: 16_384,
            paramsB: 8,
            state: .loaded,
            modelPath: "/models/vision-local",
            taskKinds: ["vision_understand", "ocr"]
        )
        let instance = AIRuntimeLoadedInstance(
            instanceKey: "transformers:vision-local:hash-vision",
            modelId: "vision-local",
            taskKinds: ["vision_understand"],
            loadProfileHash: "hash-vision",
            effectiveContextLength: 16_384,
            maxContextLength: 32_768,
            effectiveLoadProfile: LocalModelLoadProfile(
                contextLength: 16_384,
                ttl: 600,
                parallel: 2,
                identifier: "vision-a",
                vision: LocalModelVisionLoadProfile(imageMaxDimension: 2048)
            ),
            loadedAt: nowSeconds - 120,
            lastUsedAt: nowSeconds - 20,
            residency: "resident",
            deviceBackend: "helper_binary_bridge"
        )
        let status = AIRuntimeStatus(
            pid: 12,
            updatedAt: nowSeconds,
            mlxOk: false,
            providers: [
                "transformers": AIRuntimeProviderStatus(
                    provider: "transformers",
                    ok: true,
                    availableTaskKinds: ["vision_understand", "ocr"],
                    lifecycleMode: "warmable",
                    supportedLifecycleActions: ["warmup_local_model", "unload_local_model", "evict_local_instance"],
                    residencyScope: "provider_local",
                    loadedInstances: [instance]
                )
            ],
            monitorSnapshot: AIRuntimeMonitorSnapshot(
                schemaVersion: "xhub.local_runtime_monitor.v1",
                updatedAt: nowSeconds,
                providers: [
                    AIRuntimeMonitorProvider(
                        provider: "transformers",
                        ok: true,
                        realTaskKinds: ["vision_understand", "ocr"],
                        loadedInstanceCount: 1,
                        queueMode: "fifo"
                    )
                ],
                loadedInstances: [instance]
            )
        )
        let requestContext = LocalModelRuntimeRequestContext(
            providerID: "transformers",
            modelID: "vision-local",
            deviceID: "terminal_device",
            instanceKey: instance.instanceKey,
            loadProfileHash: instance.loadProfileHash,
            predictedLoadProfileHash: instance.loadProfileHash,
            effectiveContextLength: instance.effectiveContextLength,
            loadProfileOverride: nil,
            source: "selected_loaded_instance"
        )

        let summary = LocalRuntimeOperationsSummaryBuilder.build(
            status: status,
            models: [model],
            currentTargetsByModelID: ["vision-local": requestContext],
            now: now
        )

        XCTAssertEqual(summary.runtimeSummary, "已就绪：transformers")
        XCTAssertEqual(summary.loadedSummary, "1 个已加载实例")
        XCTAssertEqual(summary.instanceRows.count, 1)
        XCTAssertTrue(summary.instanceRows[0].isCurrentTarget)
        XCTAssertEqual(summary.instanceRows[0].currentTargetSummary, "已固定实例")
        XCTAssertTrue(summary.instanceRows[0].canUnload)
        XCTAssertTrue(summary.instanceRows[0].canEvict)
        XCTAssertEqual(summary.instanceRows[0].loadSummary, "ctx 16384 · max 32768 · ttl 600s · par 2 · img 2048 · 加载配置 hash-vis")
        XCTAssertEqual(summary.instanceRows[0].detailSummary, "transformers · resident · helper_binary_bridge · 配置 vision-a · 20 秒前")
    }

    func testBuildSummarizesProviderBusyAndFallbackStates() {
        let now = Date()
        let nowSeconds = now.timeIntervalSince1970
        let status = AIRuntimeStatus(
            pid: 34,
            updatedAt: nowSeconds,
            mlxOk: true,
            providers: [
                "mlx": AIRuntimeProviderStatus(provider: "mlx", ok: true),
                "transformers": AIRuntimeProviderStatus(provider: "transformers", ok: true, fallbackUsed: true)
            ],
            monitorSnapshot: AIRuntimeMonitorSnapshot(
                schemaVersion: "xhub.local_runtime_monitor.v1",
                updatedAt: nowSeconds,
                providers: [
                    AIRuntimeMonitorProvider(
                        provider: "mlx",
                        ok: true,
                        activeTaskCount: 1,
                        queueMode: "fifo"
                    ),
                    AIRuntimeMonitorProvider(
                        provider: "transformers",
                        ok: true,
                        fallbackUsed: true,
                        fallbackTaskKinds: ["vision_understand"],
                        loadedInstanceCount: 2,
                        queueMode: "fifo"
                    ),
                ],
                queue: AIRuntimeMonitorQueue(
                    activeTaskCount: 1,
                    queuedTaskCount: 2,
                    maxOldestWaitMs: 480
                )
            )
        )

        let summary = LocalRuntimeOperationsSummaryBuilder.build(
            status: status,
            models: [],
            currentTargetsByModelID: [:],
            now: now
        )

        XCTAssertEqual(summary.queueSummary, "1 个执行中 · 2 个排队中 · 等待 480ms")
        XCTAssertEqual(summary.providerRows.map { $0.providerID }, ["mlx", "transformers"])
        XCTAssertEqual(summary.providerRows.first(where: { $0.providerID == "mlx" })?.stateLabel, "busy")
        XCTAssertEqual(summary.providerRows.first(where: { $0.providerID == "transformers" })?.stateLabel, "fallback")
    }

    func testBuildFallsBackToResidentUnloadWhenProviderStatusIsMissing() {
        let now = Date()
        let nowSeconds = now.timeIntervalSince1970
        let model = HubModel(
            id: "embed-local",
            name: "Embed Local",
            backend: "transformers",
            quant: "fp16",
            contextLength: 8192,
            paramsB: 0.4,
            state: .loaded,
            modelPath: "/models/embed-local",
            taskKinds: ["embedding"]
        )
        let instance = AIRuntimeLoadedInstance(
            instanceKey: "transformers:embed-local:hash1234",
            modelId: "embed-local",
            taskKinds: ["embedding"],
            loadProfileHash: "hash1234",
            effectiveContextLength: 8192,
            maxContextLength: 16384,
            loadedAt: nowSeconds - 60,
            lastUsedAt: nowSeconds - 10,
            residency: "resident",
            residencyScope: "provider_runtime",
            deviceBackend: "mps"
        )
        let status = AIRuntimeStatus(
            pid: 56,
            updatedAt: nowSeconds,
            mlxOk: false,
            providers: [:],
            monitorSnapshot: AIRuntimeMonitorSnapshot(
                schemaVersion: "xhub.local_runtime_monitor.v1",
                updatedAt: nowSeconds,
                providers: [],
                loadedInstances: [instance]
            )
        )

        let summary = LocalRuntimeOperationsSummaryBuilder.build(
            status: status,
            models: [model],
            currentTargetsByModelID: [:],
            now: now
        )

        XCTAssertEqual(summary.instanceRows.count, 1)
        XCTAssertTrue(summary.instanceRows[0].canUnload)
        XCTAssertFalse(summary.instanceRows[0].canEvict)
    }
}
