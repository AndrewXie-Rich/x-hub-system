import XCTest
@testable import RELFlowHub
@testable import RELFlowHubCore

final class LocalModelRuntimeActionPlannerTests: XCTestCase {
    func testPlannerClassifiesProcessLocalProviderAsOnDemand() {
        let model = HubModel(
            id: "embed-local",
            name: "Embed Local",
            backend: "transformers",
            quant: "fp16",
            contextLength: 2048,
            paramsB: 0.4,
            state: .available,
            modelPath: "/tmp/models/embed-local",
            taskKinds: ["embedding"]
        )
        let runtimeStatus = AIRuntimeStatus(
            pid: 123,
            updatedAt: Date().timeIntervalSince1970,
            mlxOk: false,
            providers: [
                "transformers": AIRuntimeProviderStatus(
                    provider: "transformers",
                    ok: true,
                    reasonCode: "ready",
                    runtimeVersion: "v2",
                    availableTaskKinds: ["embedding"],
                    loadedModels: [],
                    deviceBackend: "mps",
                    updatedAt: Date().timeIntervalSince1970,
                    lifecycleMode: "warmable",
                    supportedLifecycleActions: ["warmup_local_model", "unload_local_model"],
                    warmupTaskKinds: ["embedding"],
                    residencyScope: "process_local",
                    loadedInstances: []
                ),
            ]
        )

        let presentation = LocalModelRuntimeActionPlanner.presentation(for: model, runtimeStatus: runtimeStatus)

        XCTAssertEqual(presentation?.controlMode, .ephemeralOnDemand)
        XCTAssertEqual(presentation?.badgeTitle, "On-Demand")
        XCTAssertFalse(presentation?.supportsWarmup ?? true)
        XCTAssertFalse(presentation?.supportsUnload ?? true)
    }

    func testPlannerRoutesMLXActionsToLegacyCommandPath() {
        let model = HubModel(
            id: "mlx-local",
            name: "MLX Local",
            backend: "mlx",
            quant: "int4",
            contextLength: 8192,
            paramsB: 7.0,
            state: .available,
            modelPath: "/tmp/models/mlx-local",
            taskKinds: ["text_generate"]
        )
        let runtimeStatus = AIRuntimeStatus(
            pid: 124,
            updatedAt: Date().timeIntervalSince1970,
            mlxOk: true,
            providers: [
                "mlx": AIRuntimeProviderStatus(
                    provider: "mlx",
                    ok: true,
                    reasonCode: "ready",
                    runtimeVersion: "legacy",
                    availableTaskKinds: ["text_generate"],
                    loadedModels: [],
                    deviceBackend: "mps",
                    updatedAt: Date().timeIntervalSince1970,
                    lifecycleMode: "mlx_legacy",
                    supportedLifecycleActions: [],
                    warmupTaskKinds: [],
                    residencyScope: "runtime_process",
                    loadedInstances: []
                ),
            ]
        )

        let routedWarmup = LocalModelRuntimeActionPlanner.plan(action: "warmup", model: model, runtimeStatus: runtimeStatus)
        let routedLoad = LocalModelRuntimeActionPlanner.plan(action: "load", model: model, runtimeStatus: runtimeStatus)

        XCTAssertEqual(routedWarmup, .legacyModelCommand(action: "load"))
        XCTAssertEqual(routedLoad, .legacyModelCommand(action: "load"))
    }

    func testPlannerBlocksProcessLocalWarmupWithHonestMessage() {
        let model = HubModel(
            id: "asr-local",
            name: "ASR Local",
            backend: "transformers",
            quant: "fp16",
            contextLength: 2048,
            paramsB: 1.2,
            state: .available,
            modelPath: "/tmp/models/asr-local",
            taskKinds: ["speech_to_text"]
        )
        let runtimeStatus = AIRuntimeStatus(
            pid: 125,
            updatedAt: Date().timeIntervalSince1970,
            mlxOk: false,
            providers: [
                "transformers": AIRuntimeProviderStatus(
                    provider: "transformers",
                    ok: true,
                    reasonCode: "ready",
                    runtimeVersion: "v2",
                    availableTaskKinds: ["speech_to_text"],
                    loadedModels: [],
                    deviceBackend: "mps",
                    updatedAt: Date().timeIntervalSince1970,
                    lifecycleMode: "warmable",
                    supportedLifecycleActions: ["warmup_local_model", "unload_local_model"],
                    warmupTaskKinds: ["speech_to_text"],
                    residencyScope: "process_local",
                    loadedInstances: []
                ),
            ]
        )

        let plan = LocalModelRuntimeActionPlanner.plan(action: "warmup", model: model, runtimeStatus: runtimeStatus)

        guard case .immediateFailure(let message) = plan else {
            XCTFail("expected immediate failure")
            return
        }
        XCTAssertTrue(message.contains("runs on demand"))
        XCTAssertTrue(message.contains("Warmup is not available"))
        XCTAssertFalse(message.contains("legacy MLX command path"))
    }

    func testPlannerBlocksWarmableProviderUntilResidentTransportExists() {
        let model = HubModel(
            id: "embed-resident",
            name: "Embed Resident",
            backend: "transformers",
            quant: "fp16",
            contextLength: 2048,
            paramsB: 0.4,
            state: .available,
            modelPath: "/tmp/models/embed-resident",
            taskKinds: ["embedding"]
        )
        let runtimeStatus = AIRuntimeStatus(
            pid: 126,
            updatedAt: Date().timeIntervalSince1970,
            mlxOk: false,
            providers: [
                "transformers": AIRuntimeProviderStatus(
                    provider: "transformers",
                    ok: true,
                    reasonCode: "ready",
                    runtimeVersion: "v2",
                    availableTaskKinds: ["embedding"],
                    loadedModels: [],
                    deviceBackend: "mps",
                    updatedAt: Date().timeIntervalSince1970,
                    lifecycleMode: "warmable",
                    supportedLifecycleActions: ["warmup_local_model", "unload_local_model"],
                    warmupTaskKinds: ["embedding"],
                    residencyScope: "provider_runtime",
                    loadedInstances: []
                ),
            ]
        )

        let plan = LocalModelRuntimeActionPlanner.plan(action: "warmup", model: model, runtimeStatus: runtimeStatus)

        guard case .immediateFailure(let message) = plan else {
            XCTFail("expected immediate failure")
            return
        }
        XCTAssertTrue(message.contains("resident lifecycle"))
        XCTAssertTrue(message.contains("resident transport"))
    }
}
