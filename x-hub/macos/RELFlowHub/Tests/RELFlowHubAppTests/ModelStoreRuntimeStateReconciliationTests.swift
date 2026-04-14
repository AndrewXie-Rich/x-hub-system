import XCTest
@testable import RELFlowHub
@testable import RELFlowHubCore

@MainActor
final class ModelStoreRuntimeStateReconciliationTests: XCTestCase {
    func testReconciledLocalRuntimeStateDowngradesStaleLoadedMLXModels() {
        let snapshot = ModelStateSnapshot(
            models: [
                makeModel(
                    id: "qwen-local",
                    state: .loaded,
                    memoryBytes: 1_024,
                    tokensPerSec: 14.0
                )
            ],
            updatedAt: 10
        )
        let runtimeStatus = makeRuntimeStatus(loadedModels: [])

        let reconciled = ModelStore.reconciledLocalRuntimeState(
            snapshot,
            runtimeStatus: runtimeStatus,
            pendingByModelId: [:]
        )

        XCTAssertEqual(reconciled.models.first?.state, .available)
        XCTAssertNil(reconciled.models.first?.memoryBytes)
        XCTAssertNil(reconciled.models.first?.tokensPerSec)
    }

    func testReconciledLocalRuntimeStatePromotesRuntimeLoadedModels() {
        let snapshot = ModelStateSnapshot(
            models: [
                makeModel(id: "qwen-local", state: .available)
            ],
            updatedAt: 10
        )
        let runtimeStatus = makeRuntimeStatus(loadedModels: ["qwen-local"])

        let reconciled = ModelStore.reconciledLocalRuntimeState(
            snapshot,
            runtimeStatus: runtimeStatus,
            pendingByModelId: [:]
        )

        XCTAssertEqual(reconciled.models.first?.state, .loaded)
    }

    func testReconciledLocalRuntimeStateKeepsLoadedStateWhileLoadIsPending() {
        let snapshot = ModelStateSnapshot(
            models: [
                makeModel(id: "qwen-local", state: .loaded)
            ],
            updatedAt: 10
        )
        let runtimeStatus = makeRuntimeStatus(loadedModels: [])
        let pending = [
            "qwen-local": PendingCommand(
                reqId: "req-1",
                action: "load",
                requestedAt: 20
            )
        ]

        let reconciled = ModelStore.reconciledLocalRuntimeState(
            snapshot,
            runtimeStatus: runtimeStatus,
            pendingByModelId: pending
        )

        XCTAssertEqual(reconciled.models.first?.state, .loaded)
    }

    func testReconciledLocalRuntimeStateHonorsRecentUnloadUntilHeartbeatCatchesUp() {
        let finishedAt = Date().timeIntervalSince1970
        let snapshot = ModelStateSnapshot(
            models: [
                makeModel(
                    id: "qwen-local",
                    state: .available,
                    memoryBytes: nil,
                    tokensPerSec: nil
                )
            ],
            updatedAt: finishedAt
        )
        let runtimeStatus = AIRuntimeStatus(
            pid: 42,
            updatedAt: finishedAt - 1,
            mlxOk: true,
            providers: [
                "mlx": AIRuntimeProviderStatus(
                    provider: "mlx",
                    ok: true,
                    loadedModels: ["qwen-local"],
                    loadedInstances: [
                        AIRuntimeLoadedInstance(
                            instanceKey: "mlx:qwen-local:legacy_runtime",
                            modelId: "qwen-local"
                        )
                    ]
                )
            ]
        )

        let reconciled = ModelStore.reconciledLocalRuntimeState(
            snapshot,
            runtimeStatus: runtimeStatus,
            pendingByModelId: [:],
            successfulLocalLifecycleActionsByModelId: [
                "qwen-local": SuccessfulLocalLifecycleAction(
                    action: "unload",
                    finishedAt: finishedAt
                )
            ],
            now: finishedAt + 1
        )

        XCTAssertEqual(reconciled.models.first?.state, .available)
    }

    func testReconciledLastCommandResultsClearsRecoveredRuntimeStartError() {
        let snapshot = ModelStateSnapshot(
            models: [
                makeTransformersModel(id: "hf-qwen25-05b-instruct", state: .available)
            ],
            updatedAt: 10
        )
        let runtimeStatus = makeTransformersRuntimeStatus(loadedModels: [])
        let results = [
            "hf-qwen25-05b-instruct": ModelCommandResult(
                type: "model_result",
                reqId: "req-1",
                action: "warmup",
                modelId: "hf-qwen25-05b-instruct",
                ok: false,
                msg: LocalModelRuntimeActionPlanner.runtimeStartMessage,
                finishedAt: 20
            )
        ]

        let reconciled = ModelStore.reconciledLastCommandResults(
            results,
            snapshot: snapshot,
            runtimeStatus: runtimeStatus
        )

        XCTAssertTrue(reconciled.isEmpty)
    }

    func testReconciledLastCommandResultsKeepsProviderErrorUntilProviderReady() {
        let snapshot = ModelStateSnapshot(
            models: [
                makeTransformersModel(id: "hf-qwen25-05b-instruct", state: .available)
            ],
            updatedAt: 10
        )
        let runtimeStatus = AIRuntimeStatus(
            pid: 42,
            updatedAt: Date().timeIntervalSince1970,
            mlxOk: true,
            providers: [
                "transformers": AIRuntimeProviderStatus(
                    provider: "transformers",
                    ok: false,
                    reasonCode: "missing_runtime"
                )
            ]
        )
        let message = HubUIStrings.Models.Runtime.ActionPlanner.providerUnavailable(
            providerID: "transformers",
            extra: ""
        )
        let results = [
            "hf-qwen25-05b-instruct": ModelCommandResult(
                type: "model_result",
                reqId: "req-2",
                action: "warmup",
                modelId: "hf-qwen25-05b-instruct",
                ok: false,
                msg: message,
                finishedAt: 20
            )
        ]

        let reconciled = ModelStore.reconciledLastCommandResults(
            results,
            snapshot: snapshot,
            runtimeStatus: runtimeStatus
        )

        XCTAssertEqual(reconciled, results)
    }

    func testReconciledManagedLocalModelSnapshotsPrunesMissingManagedCopies() throws {
        let baseDir = try makeTempDir()
        let missingManagedPath = baseDir
            .appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent("deepseek-r1-0528-qwen3-8b", isDirectory: true)

        let catalog = ModelCatalogSnapshot(
            models: [
                ModelCatalogEntry(
                    id: "deepseek-r1-0528-qwen3-8b",
                    name: "DeepSeek R1",
                    backend: "transformers",
                    runtimeProviderID: "transformers",
                    quant: "4bit",
                    contextLength: 32768,
                    modelPath: missingManagedPath.path,
                    note: "managed_copy",
                    modelFormat: "hf_transformers",
                    taskKinds: ["text_generate"]
                )
            ],
            updatedAt: 10
        )
        let state = ModelStateSnapshot(
            models: [
                HubModel(
                    id: "deepseek-r1-0528-qwen3-8b",
                    name: "DeepSeek R1",
                    backend: "transformers",
                    runtimeProviderID: "transformers",
                    quant: "4bit",
                    contextLength: 32768,
                    paramsB: 8.0,
                    state: .available,
                    modelPath: missingManagedPath.path,
                    note: "managed_copy",
                    modelFormat: "hf_transformers",
                    taskKinds: ["text_generate"]
                )
            ],
            updatedAt: 12
        )

        let reconciled = ModelStore.reconciledManagedLocalModelSnapshots(
            catalog: catalog,
            state: state,
            baseDir: baseDir,
            fileManager: .default
        )

        XCTAssertTrue(reconciled.catalog.models.isEmpty)
        XCTAssertTrue(reconciled.state.models.isEmpty)
        XCTAssertEqual(reconciled.removedModelIDs, Set(["deepseek-r1-0528-qwen3-8b"]))
    }

    func testReconciledManagedLocalModelSnapshotsKeepsMissingExternalPaths() throws {
        let baseDir = try makeTempDir()
        let externalMissingPath = baseDir
            .appendingPathComponent("external", isDirectory: true)
            .appendingPathComponent("deepseek-r1-0528-qwen3-8b", isDirectory: true)

        let catalog = ModelCatalogSnapshot(
            models: [
                ModelCatalogEntry(
                    id: "deepseek-r1-0528-qwen3-8b",
                    name: "DeepSeek R1",
                    backend: "transformers",
                    runtimeProviderID: "transformers",
                    quant: "4bit",
                    contextLength: 32768,
                    modelPath: externalMissingPath.path,
                    note: "catalog",
                    modelFormat: "hf_transformers",
                    taskKinds: ["text_generate"]
                )
            ],
            updatedAt: 10
        )
        let state = ModelStateSnapshot(
            models: [
                HubModel(
                    id: "deepseek-r1-0528-qwen3-8b",
                    name: "DeepSeek R1",
                    backend: "transformers",
                    runtimeProviderID: "transformers",
                    quant: "4bit",
                    contextLength: 32768,
                    paramsB: 8.0,
                    state: .available,
                    modelPath: externalMissingPath.path,
                    note: "catalog",
                    modelFormat: "hf_transformers",
                    taskKinds: ["text_generate"]
                )
            ],
            updatedAt: 12
        )

        let reconciled = ModelStore.reconciledManagedLocalModelSnapshots(
            catalog: catalog,
            state: state,
            baseDir: baseDir,
            fileManager: .default
        )

        XCTAssertEqual(reconciled.catalog.models.count, 1)
        XCTAssertEqual(reconciled.state.models.count, 1)
        XCTAssertTrue(reconciled.removedModelIDs.isEmpty)
    }

    func testReconciledManagedLocalModelSnapshotsRefreshesStateTaskMetadataFromCatalog() throws {
        let baseDir = try makeTempDir()
        let modelPath = baseDir
            .appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent("hf-whisper-tiny", isDirectory: true)
        try FileManager.default.createDirectory(
            at: modelPath,
            withIntermediateDirectories: true
        )

        let catalog = ModelCatalogSnapshot(
            models: [
                ModelCatalogEntry(
                    id: "hf-whisper-tiny",
                    name: "whisper-tiny",
                    backend: "transformers",
                    runtimeProviderID: "transformers",
                    quant: "fp16",
                    contextLength: 448,
                    maxContextLength: 448,
                    paramsB: 0.1,
                    modelPath: modelPath.path,
                    roles: ["speech"],
                    note: "catalog",
                    modelFormat: "hf_transformers",
                    defaultLoadProfile: LocalModelLoadProfile(contextLength: 448),
                    taskKinds: ["speech_to_text"],
                    inputModalities: ["audio"],
                    outputModalities: ["text", "segments"],
                    offlineReady: true,
                    resourceProfile: ModelResourceProfile(
                        preferredDevice: "mps",
                        memoryFloorMB: 256,
                        dtype: "float16"
                    ),
                    processorRequirements: ModelProcessorRequirements(
                        tokenizerRequired: true,
                        processorRequired: true,
                        featureExtractorRequired: true
                    )
                )
            ],
            updatedAt: 10
        )
        let state = ModelStateSnapshot(
            models: [
                HubModel(
                    id: "hf-whisper-tiny",
                    name: "whisper-tiny",
                    backend: "transformers",
                    runtimeProviderID: "transformers",
                    quant: "fp16",
                    contextLength: 32768,
                    paramsB: 0.1,
                    roles: ["chat"],
                    state: .loaded,
                    memoryBytes: 2_048,
                    tokensPerSec: 17.0,
                    modelPath: modelPath.path,
                    note: "stale",
                    modelFormat: "hf_transformers",
                    taskKinds: ["text_generate"],
                    inputModalities: ["text"],
                    outputModalities: ["text"]
                )
            ],
            updatedAt: 12
        )

        let reconciled = ModelStore.reconciledManagedLocalModelSnapshots(
            catalog: catalog,
            state: state,
            baseDir: baseDir,
            fileManager: .default
        )

        XCTAssertEqual(reconciled.catalog.models.count, 1)
        XCTAssertEqual(reconciled.state.models.count, 1)
        XCTAssertTrue(reconciled.removedModelIDs.isEmpty)
        XCTAssertEqual(reconciled.state.models[0].state, .loaded)
        XCTAssertEqual(reconciled.state.models[0].memoryBytes, 2_048)
        XCTAssertEqual(reconciled.state.models[0].tokensPerSec, 17.0)
        XCTAssertEqual(reconciled.state.models[0].roles, ["speech"])
        XCTAssertEqual(reconciled.state.models[0].taskKinds, ["speech_to_text"])
        XCTAssertEqual(reconciled.state.models[0].inputModalities, ["audio"])
        XCTAssertEqual(reconciled.state.models[0].outputModalities, ["text", "segments"])
        XCTAssertEqual(reconciled.state.models[0].note, "catalog")
        XCTAssertEqual(
            reconciled.state.models[0].contextLength,
            catalog.models[0].contextLength
        )
        XCTAssertEqual(
            reconciled.state.models[0].maxContextLength,
            catalog.models[0].maxContextLength
        )
    }

    private func makeRuntimeStatus(loadedModels: [String]) -> AIRuntimeStatus {
        AIRuntimeStatus(
            pid: 42,
            updatedAt: Date().timeIntervalSince1970,
            mlxOk: true,
            providers: [
                "mlx": AIRuntimeProviderStatus(
                    provider: "mlx",
                    ok: true,
                    loadedModels: loadedModels,
                    loadedInstances: loadedModels.map {
                        AIRuntimeLoadedInstance(
                            instanceKey: "mlx:\($0):legacy_runtime",
                            modelId: $0
                        )
                    }
                )
            ]
        )
    }

    private func makeModel(
        id: String,
        state: HubModelState,
        memoryBytes: Int64? = nil,
        tokensPerSec: Double? = nil
    ) -> HubModel {
        HubModel(
            id: id,
            name: id,
            backend: "mlx",
            runtimeProviderID: "mlx",
            quant: "bf16",
            contextLength: 8192,
            paramsB: 7.0,
            state: state,
            memoryBytes: memoryBytes,
            tokensPerSec: tokensPerSec,
            modelPath: "/models/\(id)"
        )
    }

    private func makeTransformersModel(
        id: String,
        state: HubModelState
    ) -> HubModel {
        HubModel(
            id: id,
            name: id,
            backend: "transformers",
            runtimeProviderID: "transformers",
            quant: "fp16",
            contextLength: 32768,
            paramsB: 0.5,
            state: state,
            modelPath: "/models/\(id)",
            taskKinds: ["text_generate"]
        )
    }

    private func makeTransformersRuntimeStatus(loadedModels: [String]) -> AIRuntimeStatus {
        AIRuntimeStatus(
            pid: 52,
            updatedAt: Date().timeIntervalSince1970,
            mlxOk: true,
            providers: [
                "transformers": AIRuntimeProviderStatus(
                    provider: "transformers",
                    ok: true,
                    reasonCode: "ready",
                    loadedModels: loadedModels,
                    loadedInstances: loadedModels.map {
                        AIRuntimeLoadedInstance(
                            instanceKey: "transformers:\($0):default",
                            modelId: $0
                        )
                    }
                )
            ]
        )
    }

    private func makeTempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }
}
