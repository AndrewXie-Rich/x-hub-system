import XCTest
@testable import RELFlowHub
@testable import RELFlowHubCore

final class LocalModelRuntimeCompatibilityPolicyTests: XCTestCase {
    func testImportWarningFlagsMLXMultimodalModel() throws {
        let modelDir = try makeTempDir(named: "GLM-4.6V-Flash-MLX-4bit")
        try writeJSON(
            [
                "model_type": "glm4v",
                "vision_config": [
                    "hidden_size": 1536,
                ],
            ],
            to: modelDir.appendingPathComponent("config.json")
        )
        try writeJSON(
            [
                "image_processor_type": "Glm46VImageProcessor",
            ],
            to: modelDir.appendingPathComponent("preprocessor_config.json")
        )

        let warning = LocalModelRuntimeCompatibilityPolicy.importWarning(
            modelPath: modelDir.path,
            backend: "mlx"
        )

        XCTAssertEqual(
            warning,
            "当前 Hub 的 MLX 运行时仍是纯文本链路，暂不支持多模态 MLX 模型。model_type=glm4v。 `config.json` 包含 `vision_config`。 `preprocessor_config.json` 暴露了图像处理器。"
        )
    }

    func testImportWarningMergesMLXMultimodalBlockWithIncompleteShardFolder() throws {
        let modelDir = try makeTempDir(named: "GLM-4.6V-Flash-MLX-4bit")
        try writeJSON(
            [
                "model_type": "glm4v",
                "vision_config": [
                    "hidden_size": 1536,
                ],
            ],
            to: modelDir.appendingPathComponent("config.json")
        )
        try writeJSON(
            [
                "image_processor_type": "Glm46VImageProcessor",
            ],
            to: modelDir.appendingPathComponent("preprocessor_config.json")
        )
        try writeJSON(
            [
                "metadata": [
                    "total_size": 1234,
                ],
                "weight_map": [
                    "model.layers.0.weight": "model-00001-of-00004.safetensors",
                    "model.layers.1.weight": "model-00002-of-00004.safetensors",
                ],
            ],
            to: modelDir.appendingPathComponent("model.safetensors.index.json")
        )

        let warning = LocalModelRuntimeCompatibilityPolicy.importWarning(
            modelPath: modelDir.path,
            backend: "mlx"
        )

        XCTAssertEqual(
            warning,
            "当前 Hub 的 MLX 运行时仍是纯文本链路，暂不支持多模态 MLX 模型。model_type=glm4v。 `config.json` 包含 `vision_config`。 `preprocessor_config.json` 暴露了图像处理器。 目录完整性：模型目录不完整，暂时无法加载。缺少 2 个权重分片，例如 model-00001-of-00004.safetensors, model-00002-of-00004.safetensors。"
        )
    }

    func testBlockedActionMessageStopsMLXWarmupForMultimodalModel() throws {
        let modelDir = try makeTempDir(named: "Qwen3-VL-MLX")
        try writeJSON(
            [
                "model_type": "qwen3_vl_moe",
                "vision_config": [
                    "hidden_size": 1280,
                ],
            ],
            to: modelDir.appendingPathComponent("config.json")
        )

        let model = HubModel(
            id: "qwen3-vl-mlx",
            name: "Qwen3 VL",
            backend: "mlx",
            quant: "int4",
            contextLength: 8192,
            paramsB: 30.0,
            state: .available,
            modelPath: modelDir.path
        )

        let message = LocalModelRuntimeCompatibilityPolicy.blockedActionMessage(
            action: "warmup",
            model: model
        )

        XCTAssertEqual(
            message,
            "无法预热。当前 Hub 的 MLX 运行时仍是纯文本链路，暂不支持多模态 MLX 模型。model_type=qwen3_vl_moe。 `config.json` 包含 `vision_config`。"
        )
    }

    func testTextOnlyMLXModelHasNoCompatibilityBlock() throws {
        let modelDir = try makeTempDir(named: "Qwen3-1.7B-MLX")
        try writeJSON(
            [
                "model_type": "qwen3",
                "architectures": ["Qwen3ForCausalLM"],
            ],
            to: modelDir.appendingPathComponent("config.json")
        )

        let model = HubModel(
            id: "qwen3-mlx",
            name: "Qwen3",
            backend: "mlx",
            quant: "int4",
            contextLength: 8192,
            paramsB: 1.7,
            state: .available,
            modelPath: modelDir.path
        )

        XCTAssertNil(LocalModelRuntimeCompatibilityPolicy.importWarning(modelPath: modelDir.path, backend: "mlx"))
        XCTAssertNil(LocalModelRuntimeCompatibilityPolicy.blockedActionMessage(action: "load", model: model))
    }

    func testMLXVisionModelWithMLXVLMRuntimeProviderIsNotBlockedByMLXTextOnlyRule() throws {
        let modelDir = try makeTempDir(named: "GLM-4.6V-Flash-MLX-4bit")
        try writeJSON(
            [
                "model_type": "glm4v",
                "vision_config": [
                    "hidden_size": 1536,
                ],
            ],
            to: modelDir.appendingPathComponent("config.json")
        )
        try writeJSON(
            [
                "image_processor_type": "Glm46VImageProcessor",
            ],
            to: modelDir.appendingPathComponent("preprocessor_config.json")
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

        XCTAssertNil(
            LocalModelRuntimeCompatibilityPolicy.importWarning(
                modelPath: modelDir.path,
                backend: "mlx",
                taskKinds: ["vision_understand", "ocr"],
                executionProviderID: "mlx_vlm"
            )
        )
        XCTAssertNil(LocalModelRuntimeCompatibilityPolicy.blockedActionMessage(action: "warmup", model: model))
    }

    func testLlamaCppLoadNoLongerBlockedByStaticProviderWiringGuard() throws {
        let modelDir = try makeTempDir(named: "Qwen3-GGUF")
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
            taskKinds: ["text_generate"]
        )

        let warning = LocalModelRuntimeCompatibilityPolicy.importWarning(
            modelPath: modelDir.path,
            backend: "llama.cpp",
            taskKinds: ["text_generate"],
            executionProviderID: "llama.cpp"
        )
        let message = LocalModelRuntimeCompatibilityPolicy.blockedActionMessage(
            action: "load",
            model: model
        )

        XCTAssertNil(warning)
        XCTAssertNil(message)
    }

    func testImportWarningFlagsIncompleteTransformersShardFolder() throws {
        let modelDir = try makeTempDir(named: "GLM-4.6V-Flash-MLX-4bit")
        try writeJSON(
            [
                "metadata": [
                    "total_size": 1234,
                ],
                "weight_map": [
                    "model.layers.0.weight": "model-00001-of-00004.safetensors",
                    "model.layers.1.weight": "model-00002-of-00004.safetensors",
                ],
            ],
            to: modelDir.appendingPathComponent("model.safetensors.index.json")
        )

        let warning = LocalModelRuntimeCompatibilityPolicy.importWarning(
            modelPath: modelDir.path,
            backend: "transformers"
        )

        XCTAssertEqual(
            warning,
            "模型目录不完整，暂时无法加载。缺少 2 个权重分片，例如 model-00001-of-00004.safetensors, model-00002-of-00004.safetensors。"
        )
    }

    func testBlockedActionMessageStopsTransformersLoadForPartialDownloadFolder() throws {
        let modelDir = try makeTempDir(named: "Qwen3-VL-30B-A3B-Instruct-MLX-4bit")
        try Data().write(to: modelDir.appendingPathComponent("downloading_model-00001-of-00013.safetensors.part"))

        let model = HubModel(
            id: "qwen3-vl-local",
            name: "Qwen3 VL",
            backend: "transformers",
            quant: "int4",
            contextLength: 8192,
            paramsB: 30.0,
            state: .available,
            modelPath: modelDir.path
        )

        let message = LocalModelRuntimeCompatibilityPolicy.blockedActionMessage(
            action: "load",
            model: model
        )

        XCTAssertEqual(
            message,
            "无法加载。模型目录看起来还没下载完整。检测到 1 个未完成分片文件，例如 downloading_model-00001-of-00013.safetensors.part。"
        )
    }

    func testBlockedActionMessageStopsLoadWhenSavedModelPathIsMissing() {
        let missingPath = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("missing-model", isDirectory: true)

        let model = HubModel(
            id: "missing-local",
            name: "Missing Local",
            backend: "transformers",
            quant: "int4",
            contextLength: 8192,
            paramsB: 7.0,
            state: .available,
            modelPath: missingPath.path
        )

        let message = LocalModelRuntimeCompatibilityPolicy.blockedActionMessage(
            action: "load",
            model: model
        )

        XCTAssertEqual(
            message,
            "无法加载。保存的路径下找不到模型文件。请重新下载模型，或重新添加本地模型目录。"
        )
    }

    func testImportWarningFlagsHighRiskTransformersVisionRuntimeVersion() throws {
        let modelDir = try makeTempDir(named: "GLM-4.6V-Flash-MLX-4bit")
        try writeJSON(
            [
                "model_type": "glm4v",
                "transformers_version": "5.0.0rc0",
                "vision_config": [
                    "hidden_size": 1536,
                ],
            ],
            to: modelDir.appendingPathComponent("config.json")
        )

        let warning = LocalModelRuntimeCompatibilityPolicy.importWarning(
            modelPath: modelDir.path,
            backend: "transformers"
        )

        XCTAssertEqual(
            warning,
            "这个 Transformers 模型可能需要更新的本地 Transformers 运行时，才能正常加载。model_type=glm4v。 `config.json` 声明了 `transformers_version=5.0.0rc0`。 较旧的 Transformers 版本常会以 `Model_type_glm4v_not_supported` 失败。"
        )
    }

    func testBlockedActionMessageDoesNotBlockTransformersRuntimeRiskWarning() throws {
        let modelDir = try makeTempDir(named: "Devstral-Small-2-24B-Instruct-2512-4bit")
        try writeJSON(
            [
                "model_type": "mistral3",
                "transformers_version": "5.0.0.dev0",
                "vision_config": [
                    "hidden_size": 1024,
                ],
            ],
            to: modelDir.appendingPathComponent("config.json")
        )

        let model = HubModel(
            id: "devstral-local",
            name: "Devstral",
            backend: "transformers",
            quant: "int4",
            contextLength: 8192,
            paramsB: 24.0,
            state: .available,
            modelPath: modelDir.path
        )

        XCTAssertNil(LocalModelRuntimeCompatibilityPolicy.blockedActionMessage(action: "warmup", model: model))
    }

    func testTransformersRuntimeProbeWarningSurfacesMissingTorchWithoutUserAction() throws {
        let modelDir = try makeTempDir(named: "GLM-4.6V-Flash-MLX-4bit")
        try writeJSON(
            [
                "model_type": "glm4v",
            ],
            to: modelDir.appendingPathComponent("config.json")
        )
        let fakePython = try makeFakePython(
            """
            code=missing_module:torch
            summary=Current Python runtime is missing torch.
            detail=Hub cannot load this Transformers model until torch is available.
            blocking=1
            """
        )

        let warning = LocalModelRuntimeCompatibilityPolicy.importWarning(
            modelPath: modelDir.path,
            backend: "transformers",
            taskKinds: ["vision_understand"],
            providerPackSnapshot: .empty(),
            pythonPath: fakePython.path
        )

        XCTAssertEqual(
            warning,
            "当前 Python 运行时缺少 torch。Hub 只有在 torch 可用后才能加载这个 Transformers 模型。"
        )
    }

    func testMLXVLMRuntimeProbeSkipsPythonTorchGateWhenHelperBridgeIsUsed() throws {
        let helperBinary = try makeHelper()

        let modelDir = try makeTempDir(named: "Qwen3-VL-4B-Instruct-3bit")
        try writeJSON(
            [
                "model_type": "qwen3_vl_moe",
                "vision_config": [
                    "hidden_size": 1280,
                ],
            ],
            to: modelDir.appendingPathComponent("config.json")
        )

        let probeLog = modelDir.appendingPathComponent("python-probe.log")
        let fakePython = try makeLoggingFakePython(
            output: """
            code=missing_module:torch
            summary=Current Python runtime is missing torch.
            detail=Hub cannot load this MLX VLM model until torch is available.
            blocking=1
            """,
            logFile: probeLog
        )

        let warning = LocalModelRuntimeCompatibilityPolicy.importWarning(
            modelPath: modelDir.path,
            backend: "mlx",
            taskKinds: ["vision_understand"],
            executionProviderID: "mlx_vlm",
            providerPackSnapshot: .empty(),
            helperBinaryPath: helperBinary.path,
            pythonPath: fakePython.path
        )

        XCTAssertNil(warning)
        XCTAssertFalse(FileManager.default.fileExists(atPath: probeLog.path))
    }

    func testTransformersRuntimeProbeSkipsPythonTorchGateWhenHelperBridgePackCoversVisionTask() throws {
        let helperBinary = try makeHelper()
        let modelDir = try makeTempDir(named: "Qwen3-VL-30B-A3B-Instruct")
        try writeJSON(
            [
                "model_type": "qwen3_vl_moe",
            ],
            to: modelDir.appendingPathComponent("config.json")
        )
        let probeLog = modelDir.appendingPathComponent("python-probe.log")
        let fakePython = try makeLoggingFakePython(
            output: """
            code=missing_module:torch
            summary=Current Python runtime is missing torch.
            detail=Hub cannot load this Transformers model until torch is available.
            blocking=1
            """,
            logFile: probeLog
        )
        let previewCatalog = catalogSnapshot(
            models: [
                ModelCatalogEntry(
                    id: "qwen3-vl-local",
                    name: "Qwen3 VL",
                    backend: "transformers",
                    quant: "int4",
                    contextLength: 8192,
                    paramsB: 30.0,
                    modelPath: modelDir.path,
                    taskKinds: ["vision_understand", "ocr"]
                ),
            ]
        )

        let warning = LocalModelRuntimeCompatibilityPolicy.importWarning(
            modelPath: modelDir.path,
            backend: "transformers",
            taskKinds: ["vision_understand", "ocr"],
            executionProviderID: "transformers",
            catalogSnapshot: previewCatalog,
            providerPackSnapshot: .empty(),
            helperBinaryPath: helperBinary.path,
            pythonPath: fakePython.path
        )

        XCTAssertNil(warning)
        XCTAssertFalse(FileManager.default.fileExists(atPath: probeLog.path))
    }

    func testTransformersRuntimeProbeKeepsPythonTorchGateForSpeechToTextWhenHelperExists() throws {
        let helperBinary = try makeHelper()
        let modelDir = try makeTempDir(named: "Whisper-Large-V3")
        try writeJSON(
            [
                "model_type": "whisper",
            ],
            to: modelDir.appendingPathComponent("config.json")
        )
        let probeLog = modelDir.appendingPathComponent("python-probe.log")
        let fakePython = try makeLoggingFakePython(
            output: """
            code=missing_module:torch
            summary=Current Python runtime is missing torch.
            detail=Hub cannot load this Transformers model until torch is available.
            blocking=1
            """,
            logFile: probeLog
        )
        let previewCatalog = catalogSnapshot(
            models: [
                ModelCatalogEntry(
                    id: "whisper-local",
                    name: "Whisper Local",
                    backend: "transformers",
                    quant: "fp16",
                    contextLength: 2048,
                    paramsB: 1.0,
                    modelPath: modelDir.path,
                    taskKinds: ["speech_to_text"]
                ),
            ]
        )

        let warning = LocalModelRuntimeCompatibilityPolicy.importWarning(
            modelPath: modelDir.path,
            backend: "transformers",
            taskKinds: ["speech_to_text"],
            executionProviderID: "transformers",
            catalogSnapshot: previewCatalog,
            providerPackSnapshot: .empty(),
            helperBinaryPath: helperBinary.path,
            pythonPath: fakePython.path
        )

        XCTAssertEqual(
            warning,
            "当前 Python 运行时缺少 torch。Hub 只有在 torch 可用后才能加载这个 Transformers 模型。"
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: probeLog.path))
    }

    func testTransformersVisionRuntimeProbeStillUsesPythonWhenCatalogContainsASRModel() throws {
        let helperBinary = try makeHelper()
        let visionModelDir = try makeTempDir(named: "GLM4V-Local")
        try writeJSON(
            [
                "model_type": "glm4v",
            ],
            to: visionModelDir.appendingPathComponent("config.json")
        )
        let asrModelDir = try makeTempDir(named: "Whisper-Large-V3")
        let probeLog = visionModelDir.appendingPathComponent("python-probe.log")
        let fakePython = try makeLoggingFakePython(
            output: """
            code=missing_module:torch
            summary=Current Python runtime is missing torch.
            detail=Hub cannot load this Transformers model until torch is available.
            blocking=1
            """,
            logFile: probeLog
        )
        let previewCatalog = catalogSnapshot(
            models: [
                ModelCatalogEntry(
                    id: "glm4v-local",
                    name: "GLM4V Local",
                    backend: "transformers",
                    quant: "int4",
                    contextLength: 8192,
                    paramsB: 9.0,
                    modelPath: visionModelDir.path,
                    taskKinds: ["vision_understand", "ocr"]
                ),
                ModelCatalogEntry(
                    id: "whisper-local",
                    name: "Whisper Local",
                    backend: "transformers",
                    quant: "fp16",
                    contextLength: 2048,
                    paramsB: 1.0,
                    modelPath: asrModelDir.path,
                    taskKinds: ["speech_to_text"]
                ),
            ]
        )

        let warning = LocalModelRuntimeCompatibilityPolicy.importWarning(
            modelPath: visionModelDir.path,
            backend: "transformers",
            taskKinds: ["vision_understand", "ocr"],
            executionProviderID: "transformers",
            catalogSnapshot: previewCatalog,
            providerPackSnapshot: .empty(),
            helperBinaryPath: helperBinary.path,
            pythonPath: fakePython.path
        )

        XCTAssertEqual(
            warning,
            "当前 Python 运行时缺少 torch。Hub 只有在 torch 可用后才能加载这个 Transformers 模型。"
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: probeLog.path))
    }

    func testTransformersTTSRuntimeProbeSkipsPythonTorchGateWhenSystemFallbackAvailable() throws {
        let sayBinary = try makeNamedExecutable("say")
        let modelDir = try makeTempDir(named: "Kokoro-82M-ZH-Warm")
        try writeJSON(
            [
                "model_type": "speecht5",
            ],
            to: modelDir.appendingPathComponent("config.json")
        )
        let probeLog = modelDir.appendingPathComponent("python-probe.log")
        let fakePython = try makeLoggingFakePython(
            output: """
            code=missing_module:torch
            summary=Current Python runtime is missing torch.
            detail=Hub cannot load this Transformers model until torch is available.
            blocking=1
            """,
            logFile: probeLog
        )

        let warning = withEnvironment("XHUB_TRANSFORMERS_TTS_SAY_BINARY", sayBinary.path) {
            LocalModelRuntimeCompatibilityPolicy.importWarning(
                modelPath: modelDir.path,
                backend: "transformers",
                taskKinds: ["text_to_speech"],
                executionProviderID: "transformers",
                providerPackSnapshot: .empty(),
                pythonPath: fakePython.path
            )
        }

        XCTAssertNil(warning)
        XCTAssertFalse(FileManager.default.fileExists(atPath: probeLog.path))
    }

    func testTransformersTTSRuntimeProbeKeepsPythonTorchGateWhenSystemFallbackIsUnavailable() throws {
        let modelDir = try makeTempDir(named: "Kokoro-82M-ZH-Warm")
        try writeJSON(
            [
                "model_type": "speecht5",
            ],
            to: modelDir.appendingPathComponent("config.json")
        )
        let probeLog = modelDir.appendingPathComponent("python-probe.log")
        let fakePython = try makeLoggingFakePython(
            output: """
            code=missing_module:torch
            summary=Current Python runtime is missing torch.
            detail=Hub cannot load this Transformers model until torch is available.
            blocking=1
            """,
            logFile: probeLog
        )
        let missingSayBinary = modelDir.appendingPathComponent("missing-say").path

        let warning = withEnvironment("XHUB_TRANSFORMERS_TTS_SAY_BINARY", missingSayBinary) {
            LocalModelRuntimeCompatibilityPolicy.importWarning(
                modelPath: modelDir.path,
                backend: "transformers",
                taskKinds: ["text_to_speech"],
                executionProviderID: "transformers",
                providerPackSnapshot: .empty(),
                pythonPath: fakePython.path
            )
        }

        XCTAssertEqual(
            warning,
            "当前 Python 运行时缺少 torch。Hub 只有在 torch 可用后才能加载这个 Transformers 模型。"
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: probeLog.path))
    }

    func testTransformersTextAndTTSRuntimeProbeSkipsPythonWhenHelperAndSystemFallbackCoverAllTasks() throws {
        let helperBinary = try makeHelper()
        let sayBinary = try makeNamedExecutable("say")
        let modelDir = try makeTempDir(named: "Qwen3-TTS-Hybrid")
        try writeJSON(
            [
                "model_type": "qwen3",
            ],
            to: modelDir.appendingPathComponent("config.json")
        )
        let probeLog = modelDir.appendingPathComponent("python-probe.log")
        let fakePython = try makeLoggingFakePython(
            output: """
            code=missing_module:torch
            summary=Current Python runtime is missing torch.
            detail=Hub cannot load this Transformers model until torch is available.
            blocking=1
            """,
            logFile: probeLog
        )
        let previewCatalog = catalogSnapshot(
            models: [
                ModelCatalogEntry(
                    id: "qwen3-tts-hybrid",
                    name: "Qwen3 TTS Hybrid",
                    backend: "transformers",
                    quant: "int4",
                    contextLength: 8192,
                    paramsB: 8.0,
                    modelPath: modelDir.path,
                    taskKinds: ["text_generate", "text_to_speech"]
                ),
            ]
        )

        let warning = withEnvironment("XHUB_TRANSFORMERS_TTS_SAY_BINARY", sayBinary.path) {
            LocalModelRuntimeCompatibilityPolicy.importWarning(
                modelPath: modelDir.path,
                backend: "transformers",
                taskKinds: ["text_generate", "text_to_speech"],
                executionProviderID: "transformers",
                catalogSnapshot: previewCatalog,
                providerPackSnapshot: .empty(),
                helperBinaryPath: helperBinary.path,
                pythonPath: fakePython.path
            )
        }

        XCTAssertNil(warning)
        XCTAssertFalse(FileManager.default.fileExists(atPath: probeLog.path))
    }

    func testTransformersRuntimeProbeBlocksWarmupWhenCurrentPythonDoesNotSupportModelType() throws {
        let modelDir = try makeTempDir(named: "Qwen3-VL-30B-A3B-Instruct")
        try writeJSON(
            [
                "model_type": "qwen3_vl_moe",
            ],
            to: modelDir.appendingPathComponent("config.json")
        )
        let fakePython = try makeFakePython(
            """
            code=unsupported_model_type:qwen3_vl_moe
            summary=Current Python Transformers runtime does not support model_type=qwen3_vl_moe yet.
            detail=Detected in config.model_type. Current transformers=4.57.3.
            blocking=1
            """
        )

        let model = HubModel(
            id: "qwen3-vl",
            name: "Qwen3 VL",
            backend: "transformers",
            quant: "int4",
            contextLength: 8192,
            paramsB: 30.0,
            state: .available,
            modelPath: modelDir.path,
            taskKinds: ["vision_understand"]
        )

        let message = LocalModelRuntimeCompatibilityPolicy.blockedActionMessage(
            action: "warmup",
            model: model,
            providerPackSnapshot: .empty(),
            pythonPath: fakePython.path
        )

        XCTAssertEqual(
            message,
            "无法预热。当前 Python Transformers 运行时暂不支持 model_type=qwen3_vl_moe。检测位置：config.model_type。 当前 transformers=4.57.3。"
        )
    }

    func testTransformersRuntimeProbeHumanizesProcessorBootstrapFailure() throws {
        let modelDir = try makeTempDir(named: "GLM-4.6V-Flash-MLX-4bit")
        try writeJSON(
            [
                "model_type": "glm4v",
            ],
            to: modelDir.appendingPathComponent("config.json")
        )
        let fakePython = try makeFakePython(
            """
            code=processor_init_failed:TypeError
            summary=Current Python runtime could not initialize this model's processor.
            detail=argument of type 'NoneType' is not iterable
            blocking=1
            """
        )

        let model = HubModel(
            id: "glm4v-local",
            name: "GLM 4.6V",
            backend: "transformers",
            quant: "int4",
            contextLength: 8192,
            paramsB: 9.0,
            state: .available,
            modelPath: modelDir.path,
            taskKinds: ["vision_understand"]
        )

        let message = LocalModelRuntimeCompatibilityPolicy.blockedActionMessage(
            action: "warmup",
            model: model,
            providerPackSnapshot: .empty(),
            pythonPath: fakePython.path
        )

        XCTAssertEqual(
            message,
            "无法预热。当前 Python Transformers 运行时过旧，无法初始化这个模型的图像/视频处理器。安装中的 Transformers 版本里 AutoProcessor 初始化失败。通常需要更新的 Transformers + torch 运行时。"
        )
    }

    private func makeTempDir(named name: String) throws -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let url = base.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: base)
        }
        return url
    }

    private func writeJSON(_ object: [String: Any], to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        try data.write(to: url)
    }

    private func makeFakePython(_ output: String) throws -> URL {
        let root = try makeTempDir(named: "fake-python")
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

    private func makeLoggingFakePython(output: String, logFile: URL) throws -> URL {
        let root = try makeTempDir(named: "fake-python-logged")
        let scriptURL = root.appendingPathComponent("python3")
        let script = """
        #!/bin/sh
        printf 'called\\n' >> \(shellSingleQuoted(logFile.path))
        cat <<'EOF'
        \(output.trimmingCharacters(in: .whitespacesAndNewlines))
        EOF
        exit 0
        """
        try writeExecutable(script, to: scriptURL)
        return scriptURL
    }

    private func makeHelper() throws -> URL {
        let root = try makeTempDir(named: "helper-binary")
        let helper = root.appendingPathComponent("lms")
        try writeExecutable(
            """
            #!/bin/sh
            exit 0
            """,
            to: helper
        )
        return helper
    }

    private func makeNamedExecutable(_ name: String) throws -> URL {
        let root = try makeTempDir(named: "named-executable")
        let binary = root.appendingPathComponent(name)
        try writeExecutable(
            """
            #!/bin/sh
            exit 0
            """,
            to: binary
        )
        return binary
    }

    private func catalogSnapshot(models: [ModelCatalogEntry]) -> ModelCatalogSnapshot {
        ModelCatalogSnapshot(models: models, updatedAt: 0)
    }

    private func writeExecutable(_ content: String, to url: URL) throws {
        let data = try XCTUnwrap(content.data(using: .utf8))
        try data.write(to: url)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o755))],
            ofItemAtPath: url.path
        )
    }

    private func withEnvironment<T>(_ key: String, _ value: String, perform: () throws -> T) rethrows -> T {
        let previous = getenv(key).map { String(cString: $0) }
        setenv(key, value, 1)
        defer {
            if let previous {
                setenv(key, previous, 1)
            } else {
                unsetenv(key)
            }
        }
        return try perform()
    }

    private func shellSingleQuoted(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "'", with: "'\\''")
        return "'\(escaped)'"
    }
}
