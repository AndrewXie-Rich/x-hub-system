import XCTest
@testable import RELFlowHub
@testable import RELFlowHubCore

final class LocalModelBenchCapabilityPolicyTests: XCTestCase {
    func testMLXBenchableDescriptorsAreTextOnly() throws {
        let modelDir = try makeModelDir()
        let model = HubModel(
            id: "glm-mlx",
            name: "GLM MLX",
            backend: "mlx",
            runtimeProviderID: "mlx",
            quant: "int4",
            contextLength: 8192,
            paramsB: 9.0,
            state: .available,
            modelPath: modelDir.path,
            taskKinds: ["vision_understand", "text_generate"]
        )

        let descriptors = LocalModelBenchCapabilityPolicy.benchableDescriptors(for: model)

        XCTAssertEqual(descriptors.map(\.taskKind), ["text_generate"])
    }

    func testMLXVisionBenchReturnsHonestUnsupportedMessage() throws {
        let modelDir = try makeModelDir()
        let model = HubModel(
            id: "glm-mlx",
            name: "GLM MLX",
            backend: "mlx",
            runtimeProviderID: "mlx",
            quant: "int4",
            contextLength: 8192,
            paramsB: 9.0,
            state: .available,
            modelPath: modelDir.path,
            taskKinds: ["vision_understand", "text_generate"]
        )

        let message = LocalModelBenchCapabilityPolicy.unsupportedTaskMessage(
            for: model,
            taskKind: "vision_understand"
        )

        XCTAssertEqual(
            message,
            "MLX 快速评审目前只支持文本生成。\n\n视觉理解 模型仍然可以导入 Hub，但 MLX 还没有接通 视觉理解 的 provider 原生评审链路。"
        )
    }

    func testLegacyMLXControlModeStillUsesTextOnlyBenchPolicy() throws {
        let modelDir = try makeModelDir()
        let fakePython = try makeFakePython(
            """
            code=ok
            summary=ok
            blocking=0
            """
        )
        let model = HubModel(
            id: "glm-legacy-bridge",
            name: "GLM Legacy Bridge",
            backend: "mlx",
            runtimeProviderID: "mlx_vlm",
            quant: "int4",
            contextLength: 8192,
            paramsB: 9.0,
            state: .available,
            modelPath: modelDir.path,
            taskKinds: ["vision_understand", "text_generate"]
        )
        let runtimeStatus = AIRuntimeStatus(
            pid: 998,
            updatedAt: Date().timeIntervalSince1970,
            mlxOk: true,
            providers: [
                "mlx_vlm": AIRuntimeProviderStatus(
                    provider: "mlx_vlm",
                    ok: true,
                    reasonCode: "legacy_ready",
                    availableTaskKinds: ["vision_understand", "text_generate"],
                    loadedModels: [],
                    deviceBackend: "helper_binary_bridge",
                    updatedAt: Date().timeIntervalSince1970,
                    lifecycleMode: "mlx_legacy"
                ),
            ]
        )

        let descriptors = LocalModelBenchCapabilityPolicy.benchableDescriptors(
            for: model,
            runtimeStatus: runtimeStatus,
            pythonPath: fakePython.path
        )
        let message = LocalModelBenchCapabilityPolicy.unsupportedTaskMessage(
            for: model,
            taskKind: "vision_understand",
            runtimeStatus: runtimeStatus,
            pythonPath: fakePython.path
        )

        XCTAssertEqual(descriptors.map(\.taskKind), ["text_generate"])
        XCTAssertEqual(
            message,
            "MLX 快速评审目前只支持文本生成。\n\n视觉理解 模型仍然可以导入 Hub，但 MLX 还没有接通 视觉理解 的 provider 原生评审链路。"
        )
    }

    func testTransformersBenchableDescriptorsKeepAdvertisedTaskKinds() throws {
        let modelDir = try makeModelDir()
        let fakePython = try makeFakePython(
            """
            code=ok
            summary=ok
            blocking=0
            """
        )
        let model = HubModel(
            id: "qwen-vl",
            name: "Qwen VL",
            backend: "transformers",
            quant: "fp16",
            contextLength: 8192,
            paramsB: 7.0,
            state: .available,
            modelPath: modelDir.path,
            taskKinds: ["vision_understand", "embedding"]
        )
        let runtimeStatus = AIRuntimeStatus(
            pid: 999,
            updatedAt: Date().timeIntervalSince1970,
            mlxOk: false,
            providers: [
                "transformers": AIRuntimeProviderStatus(
                    provider: "transformers",
                    ok: true,
                    reasonCode: "ready",
                    availableTaskKinds: ["vision_understand"],
                    loadedModels: [],
                    deviceBackend: "mps",
                    updatedAt: Date().timeIntervalSince1970
                ),
            ]
        )

        let descriptors = LocalModelBenchCapabilityPolicy.benchableDescriptors(
            for: model,
            runtimeStatus: runtimeStatus,
            pythonPath: fakePython.path
        )

        XCTAssertEqual(descriptors.map(\.taskKind), ["vision_understand"])
    }

    func testTransformersVoiceBenchStaysHiddenWhenMonitorMarksTaskUnavailable() throws {
        let modelDir = try makeModelDir()
        let fakePython = try makeFakePython(
            """
            code=ok
            summary=ok
            blocking=0
            """
        )
        let model = HubModel(
            id: "kokoro-local",
            name: "Kokoro Local",
            backend: "transformers",
            quant: "fp16",
            contextLength: 4096,
            paramsB: 0.08,
            state: .available,
            modelPath: modelDir.path,
            taskKinds: ["text_to_speech"]
        )
        let runtimeStatus = AIRuntimeStatus(
            pid: 1000,
            updatedAt: Date().timeIntervalSince1970,
            mlxOk: false,
            providers: [
                "transformers": AIRuntimeProviderStatus(
                    provider: "transformers",
                    ok: false,
                    reasonCode: "text_to_speech_unavailable",
                    availableTaskKinds: [],
                    loadedModels: [],
                    deviceBackend: "cpu",
                    updatedAt: Date().timeIntervalSince1970
                ),
            ],
            monitorSnapshot: AIRuntimeMonitorSnapshot(
                schemaVersion: "xhub.local_runtime_monitor.v1",
                updatedAt: Date().timeIntervalSince1970,
                providers: [
                    AIRuntimeMonitorProvider(
                        provider: "transformers",
                        ok: false,
                        reasonCode: "text_to_speech_unavailable",
                        unavailableTaskKinds: ["text_to_speech"],
                        updatedAt: Date().timeIntervalSince1970
                    ),
                ]
            )
        )

        let descriptors = LocalModelBenchCapabilityPolicy.benchableDescriptors(
            for: model,
            runtimeStatus: runtimeStatus,
            pythonPath: fakePython.path
        )

        XCTAssertTrue(descriptors.isEmpty)
    }

    func testTransformersVoiceBenchAppearsWhenRuntimeAdvertisesVoiceTask() throws {
        let modelDir = try makeModelDir()
        let fakePython = try makeFakePython(
            """
            code=ok
            summary=ok
            blocking=0
            """
        )
        let model = HubModel(
            id: "kokoro-local",
            name: "Kokoro Local",
            backend: "transformers",
            quant: "fp16",
            contextLength: 4096,
            paramsB: 0.08,
            state: .available,
            modelPath: modelDir.path,
            taskKinds: ["text_to_speech"]
        )
        let runtimeStatus = AIRuntimeStatus(
            pid: 1002,
            updatedAt: Date().timeIntervalSince1970,
            mlxOk: false,
            providers: [
                "transformers": AIRuntimeProviderStatus(
                    provider: "transformers",
                    ok: true,
                    reasonCode: "ready",
                    availableTaskKinds: ["text_to_speech"],
                    loadedModels: [],
                    deviceBackend: "cpu",
                    updatedAt: Date().timeIntervalSince1970
                ),
            ],
            monitorSnapshot: AIRuntimeMonitorSnapshot(
                schemaVersion: "xhub.local_runtime_monitor.v1",
                updatedAt: Date().timeIntervalSince1970,
                providers: [
                    AIRuntimeMonitorProvider(
                        provider: "transformers",
                        ok: true,
                        reasonCode: "ready",
                        availableTaskKinds: ["text_to_speech"],
                        updatedAt: Date().timeIntervalSince1970
                    ),
                ]
            )
        )

        let descriptors = LocalModelBenchCapabilityPolicy.benchableDescriptors(
            for: model,
            runtimeStatus: runtimeStatus,
            pythonPath: fakePython.path
        )

        XCTAssertEqual(descriptors.map(\.taskKind), ["text_to_speech"])
    }

    func testMLXVisionModelUsingMLXVLMRuntimeProviderCanBenchVisionTask() throws {
        let modelDir = try makeModelDir()
        let fakePython = try makeFakePython(
            """
            code=ok
            summary=ok
            blocking=0
            """
        )
        let model = HubModel(
            id: "glm4v-helper",
            name: "GLM4V Helper",
            backend: "mlx",
            runtimeProviderID: "mlx_vlm",
            quant: "int4",
            contextLength: 8192,
            paramsB: 9.0,
            state: .available,
            modelPath: modelDir.path,
            taskKinds: ["vision_understand", "ocr"]
        )
        let runtimeStatus = AIRuntimeStatus(
            pid: 1001,
            updatedAt: Date().timeIntervalSince1970,
            mlxOk: false,
            providers: [
                "mlx_vlm": AIRuntimeProviderStatus(
                    provider: "mlx_vlm",
                    ok: true,
                    reasonCode: "helper_bridge_ready",
                    availableTaskKinds: ["vision_understand", "ocr"],
                    loadedModels: [],
                    deviceBackend: "helper_binary_bridge",
                    updatedAt: Date().timeIntervalSince1970
                ),
            ]
        )

        let descriptors = LocalModelBenchCapabilityPolicy.benchableDescriptors(
            for: model,
            runtimeStatus: runtimeStatus,
            pythonPath: fakePython.path
        )

        XCTAssertEqual(descriptors.map(\.taskKind), ["vision_understand", "ocr"])
    }

    func testMLXMultimodalModelHasNoBenchDescriptorsWhenLoadIsBlocked() throws {
        let modelDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)
        try JSONSerialization.data(
            withJSONObject: [
                "model_type": "glm4v",
                "vision_config": ["hidden_size": 1536],
            ],
            options: [.sortedKeys]
        ).write(to: modelDir.appendingPathComponent("config.json"))
        addTeardownBlock {
            try? FileManager.default.removeItem(at: modelDir)
        }

        let model = HubModel(
            id: "glm-mlx",
            name: "GLM MLX",
            backend: "mlx",
            quant: "int4",
            contextLength: 8192,
            paramsB: 9.0,
            state: .available,
            modelPath: modelDir.path,
            taskKinds: ["text_generate"]
        )

        let descriptors = LocalModelBenchCapabilityPolicy.benchableDescriptors(for: model)

        XCTAssertTrue(descriptors.isEmpty)
    }

    func testTransformersIncompleteFolderHasNoBenchDescriptorsAndReturnsBlockedMessage() throws {
        let modelDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)
        try JSONSerialization.data(
            withJSONObject: [
                "weight_map": [
                    "model.layers.0.weight": "model-00001-of-00004.safetensors",
                ],
            ],
            options: [.sortedKeys]
        ).write(to: modelDir.appendingPathComponent("model.safetensors.index.json"))
        addTeardownBlock {
            try? FileManager.default.removeItem(at: modelDir)
        }

        let model = HubModel(
            id: "glm-vl",
            name: "GLM VL",
            backend: "transformers",
            quant: "fp16",
            contextLength: 8192,
            paramsB: 9.0,
            state: .available,
            modelPath: modelDir.path,
            taskKinds: ["vision_understand"]
        )

        let descriptors = LocalModelBenchCapabilityPolicy.benchableDescriptors(for: model)
        let message = LocalModelBenchCapabilityPolicy.unsupportedTaskMessage(
            for: model,
            taskKind: "vision_understand"
        )

        XCTAssertTrue(descriptors.isEmpty)
        XCTAssertEqual(
            message,
            "无法加载。模型目录不完整，暂时无法加载。缺少 1 个权重分片，例如 model-00001-of-00004.safetensors。"
        )
    }

    func testTransformersDynamicRuntimeProbeRemovesBenchWhenCurrentPythonCannotLoadModel() throws {
        let modelDir = try makeModelDir()
        let model = HubModel(
            id: "qwen-vl",
            name: "Qwen VL",
            backend: "transformers",
            quant: "fp16",
            contextLength: 8192,
            paramsB: 7.0,
            state: .available,
            modelPath: modelDir.path,
            taskKinds: ["vision_understand"]
        )
        let fakePython = try makeFakePython(
            """
            code=unsupported_model_type:qwen3_vl_moe
            summary=Current Python Transformers runtime does not support model_type=qwen3_vl_moe yet.
            detail=Detected in config.model_type. Current transformers=4.57.3.
            blocking=1
            """
        )

        let descriptors = LocalModelBenchCapabilityPolicy.benchableDescriptors(
            for: model,
            pythonPath: fakePython.path
        )
        let message = LocalModelBenchCapabilityPolicy.unsupportedTaskMessage(
            for: model,
            taskKind: "vision_understand",
            pythonPath: fakePython.path
        )

        XCTAssertTrue(descriptors.isEmpty)
        XCTAssertEqual(
            message,
            "无法加载。当前 Python Transformers 运行时暂不支持 model_type=qwen3_vl_moe。检测位置：config.model_type。 当前 transformers=4.57.3。"
        )
    }

    func testLlamaCppBenchUsesHelperAdvertisedTasksOnceProviderIsWired() throws {
        let modelDir = try makeModelDir()
        try Data().write(to: modelDir.appendingPathComponent("qwen3-q4_k_m.gguf"))
        let model = HubModel(
            id: "qwen3-gguf",
            name: "Qwen3 GGUF",
            backend: "llama.cpp",
            runtimeProviderID: "llama.cpp",
            quant: "q4_k_m",
            contextLength: 8192,
            paramsB: 8.0,
            state: .available,
            modelPath: modelDir.path,
            taskKinds: ["text_generate", "embedding"]
        )
        let runtimeStatus = AIRuntimeStatus(
            pid: 1003,
            updatedAt: Date().timeIntervalSince1970,
            mlxOk: false,
            providers: [
                "llama.cpp": AIRuntimeProviderStatus(
                    provider: "llama.cpp",
                    ok: true,
                    reasonCode: "helper_bridge_ready",
                    availableTaskKinds: ["text_generate", "embedding"],
                    loadedModels: [],
                    deviceBackend: "llama.cpp",
                    updatedAt: Date().timeIntervalSince1970
                ),
            ]
        )

        let descriptors = LocalModelBenchCapabilityPolicy.benchableDescriptors(
            for: model,
            runtimeStatus: runtimeStatus
        )
        let message = LocalModelBenchCapabilityPolicy.unsupportedTaskMessage(
            for: model,
            taskKind: "text_generate",
            runtimeStatus: runtimeStatus
        )
        let embeddingMessage = LocalModelBenchCapabilityPolicy.unsupportedTaskMessage(
            for: model,
            taskKind: "embedding",
            runtimeStatus: runtimeStatus
        )

        XCTAssertEqual(descriptors.map(\.taskKind), ["text_generate", "embedding"])
        XCTAssertNil(message)
        XCTAssertNil(embeddingMessage)
    }

    private func makeFakePython(_ output: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }
        let scriptURL = root.appendingPathComponent("python3")
        let script = """
        #!/bin/sh
        cat <<'EOF'
        \(output.trimmingCharacters(in: .whitespacesAndNewlines))
        EOF
        exit 0
        """
        let data = try XCTUnwrap(script.data(using: .utf8))
        try data.write(to: scriptURL)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o755))],
            ofItemAtPath: scriptURL.path
        )
        return scriptURL
    }

    private func makeModelDir() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }
        return root
    }
}
