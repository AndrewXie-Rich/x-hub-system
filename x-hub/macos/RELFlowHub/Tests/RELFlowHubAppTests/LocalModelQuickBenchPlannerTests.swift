import XCTest
@testable import RELFlowHub
@testable import RELFlowHubCore

final class LocalModelQuickBenchPlannerTests: XCTestCase {
    func testPrepareRequiresWarmupForWarmableProviderWithoutMatchingResidentTarget() {
        let plan = LocalModelQuickBenchPlanner.prepare(
            model: makeModel(),
            taskKind: "embedding",
            runtimeStatus: makeRuntimeStatus(loadedInstances: []),
            requestContext: makeRequestContext()
        )

        XCTAssertTrue(plan.requiresWarmup)
    }

    func testPrepareSkipsWarmupWhenMatchingResidentTargetAlreadyLoaded() {
        let requestContext = makeRequestContext()
        let plan = LocalModelQuickBenchPlanner.prepare(
            model: makeModel(),
            taskKind: "embedding",
            runtimeStatus: makeRuntimeStatus(
                loadedInstances: [
                    AIRuntimeLoadedInstance(
                        instanceKey: "transformers:hf-embed:predicted-hash",
                        modelId: "hf-embed",
                        taskKinds: ["embedding"],
                        loadProfileHash: "predicted-hash",
                        effectiveContextLength: 16384,
                        loadedAt: 100,
                        lastUsedAt: 120,
                        residency: "resident",
                        residencyScope: "runtime_process",
                        deviceBackend: "mps"
                    ),
                ]
            ),
            requestContext: requestContext
        )

        XCTAssertFalse(plan.requiresWarmup)
        XCTAssertEqual(plan.requestContext, requestContext)
    }

    func testPrepareRequiresWarmupWhenLoadedInstanceDoesNotSupportBenchTask() {
        let plan = LocalModelQuickBenchPlanner.prepare(
            model: makeModel(),
            taskKind: "embedding",
            runtimeStatus: makeRuntimeStatus(
                loadedInstances: [
                    AIRuntimeLoadedInstance(
                        instanceKey: "transformers:hf-embed:predicted-hash",
                        modelId: "hf-embed",
                        taskKinds: ["text_generate"],
                        loadProfileHash: "predicted-hash",
                        effectiveContextLength: 16384,
                        loadedAt: 100,
                        lastUsedAt: 120,
                        residency: "resident",
                        residencyScope: "runtime_process",
                        deviceBackend: "mps"
                    ),
                ]
            ),
            requestContext: makeRequestContext()
        )

        XCTAssertTrue(plan.requiresWarmup)
    }

    func testPrepareSkipsWarmupForOnDemandProvider() {
        let plan = LocalModelQuickBenchPlanner.prepare(
            model: makeModel(taskKinds: ["speech_to_text"]),
            taskKind: "speech_to_text",
            runtimeStatus: makeRuntimeStatus(
                taskKinds: ["speech_to_text"],
                warmupTaskKinds: ["speech_to_text"],
                lifecycleMode: "warmable",
                residencyScope: "process_local",
                loadedInstances: []
            ),
            requestContext: makeRequestContext(taskKind: "speech_to_text")
        )

        XCTAssertFalse(plan.requiresWarmup)
    }

    func testPrepareSkipsWarmupForLegacyControlModeEvenWhenProviderIDIsNotMLX() {
        let model = HubModel(
            id: "vision-local",
            name: "Vision Local",
            backend: "mlx",
            runtimeProviderID: "mlx_vlm",
            quant: "int4",
            contextLength: 8192,
            maxContextLength: 32768,
            paramsB: 4.0,
            state: .available,
            modelPath: "/tmp/models/vision-local",
            defaultLoadProfile: LocalModelLoadProfile(contextLength: 8192),
            taskKinds: ["vision_understand"]
        )
        let requestContext = LocalModelRuntimeRequestContext(
            providerID: "mlx_vlm",
            modelID: "vision-local",
            deviceID: "",
            instanceKey: "",
            loadProfileHash: "",
            predictedLoadProfileHash: "predicted-hash",
            effectiveContextLength: 8192,
            loadProfileOverride: nil,
            effectiveLoadProfile: LocalModelLoadProfile(contextLength: 8192),
            source: "paired_terminal_default"
        )
        let runtimeStatus = AIRuntimeStatus(
            pid: 654,
            updatedAt: Date().timeIntervalSince1970,
            mlxOk: true,
            providers: [
                "mlx_vlm": AIRuntimeProviderStatus(
                    provider: "mlx_vlm",
                    ok: true,
                    reasonCode: "ready",
                    runtimeVersion: "legacy-bridge",
                    availableTaskKinds: ["vision_understand"],
                    loadedModels: [],
                    deviceBackend: "helper_binary_bridge",
                    updatedAt: Date().timeIntervalSince1970,
                    lifecycleMode: "mlx_legacy",
                    supportedLifecycleActions: [],
                    warmupTaskKinds: [],
                    residencyScope: "runtime_process",
                    loadedInstances: []
                ),
            ]
        )

        let plan = LocalModelQuickBenchPlanner.prepare(
            model: model,
            taskKind: "vision_understand",
            runtimeStatus: runtimeStatus,
            requestContext: requestContext
        )

        XCTAssertFalse(plan.requiresWarmup)
    }

    func testUpdatedRequestContextUsesWarmupPayloadIdentity() {
        let updated = LocalModelQuickBenchPlanner.updatedRequestContext(
            fromWarmupPayload: [
                "instanceKey": "transformers:hf-embed:warmed-hash",
                "loadProfileHash": "warmed-hash",
                "effectiveContextLength": 32768,
            ],
            fallback: makeRequestContext()
        )

        XCTAssertEqual(updated.instanceKey, "transformers:hf-embed:warmed-hash")
        XCTAssertEqual(updated.loadProfileHash, "warmed-hash")
        XCTAssertEqual(updated.predictedLoadProfileHash, "warmed-hash")
        XCTAssertEqual(updated.effectiveContextLength, 32768)
        XCTAssertEqual(updated.effectiveLoadProfile, LocalModelLoadProfile(contextLength: 32768))
        XCTAssertEqual(updated.source, "bench_auto_warmup")
    }

    private func makeModel(taskKinds: [String] = ["embedding"]) -> HubModel {
        HubModel(
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
            taskKinds: taskKinds
        )
    }

    private func makeRequestContext(taskKind: String = "embedding") -> LocalModelRuntimeRequestContext {
        LocalModelRuntimeRequestContext(
            providerID: "transformers",
            modelID: "hf-embed",
            deviceID: taskKind == "embedding" ? "terminal_device" : "",
            instanceKey: "",
            loadProfileHash: "",
            predictedLoadProfileHash: "predicted-hash",
            effectiveContextLength: 16384,
            loadProfileOverride: LocalModelLoadProfileOverride(contextLength: 16384),
            effectiveLoadProfile: LocalModelLoadProfile(contextLength: 16384),
            source: "paired_terminal_default"
        )
    }

    private func makeRuntimeStatus(
        taskKinds: [String] = ["embedding"],
        warmupTaskKinds: [String] = ["embedding"],
        lifecycleMode: String = "warmable",
        residencyScope: String = "runtime_process",
        loadedInstances: [AIRuntimeLoadedInstance]
    ) -> AIRuntimeStatus {
        AIRuntimeStatus(
            pid: 321,
            updatedAt: Date().timeIntervalSince1970,
            mlxOk: false,
            providers: [
                "transformers": AIRuntimeProviderStatus(
                    provider: "transformers",
                    ok: true,
                    reasonCode: "ready",
                    runtimeVersion: "v2",
                    availableTaskKinds: taskKinds,
                    loadedModels: loadedInstances.map(\.modelId),
                    deviceBackend: "mps",
                    updatedAt: Date().timeIntervalSince1970,
                    lifecycleMode: lifecycleMode,
                    supportedLifecycleActions: ["warmup_local_model", "unload_local_model"],
                    warmupTaskKinds: warmupTaskKinds,
                    residencyScope: residencyScope,
                    loadedInstances: loadedInstances
                ),
            ]
        )
    }
}
