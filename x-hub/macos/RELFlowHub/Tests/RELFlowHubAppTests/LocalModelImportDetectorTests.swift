import XCTest
@testable import RELFlowHub
@testable import RELFlowHubCore

final class LocalModelImportDetectorTests: XCTestCase {
    func testDetectBackendPrefersManifestBackend() throws {
        let tempDir = try makeTempDir(named: "manifest-backend")
        let manifest = XHubLocalModelManifest(
            backend: "transformers",
            modelFormat: "hf_transformers",
            taskKinds: ["embedding"],
            inputModalities: ["text"],
            outputModalities: ["embedding"]
        )

        let detection = LocalModelImportDetector.detectBackend(
            for: tempDir,
            manifest: manifest,
            config: nil
        )

        XCTAssertEqual(detection.backend, "transformers")
        XCTAssertEqual(detection.sourceSummary, "backend manifest")
    }

    func testDetectBackendTreatsMLXNamedShardedFolderAsMLX() throws {
        let tempDir = try makeTempDir(named: "GLM-4.6V-Flash-MLX-4bit")
        try Data("{}".utf8).write(to: tempDir.appendingPathComponent("config.json"))
        try Data("{}".utf8).write(to: tempDir.appendingPathComponent("preprocessor_config.json"))
        try Data("{}".utf8).write(to: tempDir.appendingPathComponent("video_preprocessor_config.json"))
        try Data(
            """
            {
              "weight_map": {
                "model.layers.0.weight": "model-00001-of-00004.safetensors"
              }
            }
            """.utf8
        ).write(to: tempDir.appendingPathComponent("model.safetensors.index.json"))

        let detection = LocalModelImportDetector.detectBackend(
            for: tempDir,
            manifest: nil,
            config: [
                "model_type": "glm4v",
                "quantization": ["bits": 4, "group_size": 64],
            ]
        )

        XCTAssertEqual(detection.backend, "mlx")
        XCTAssertEqual(detection.sourceSummary, "backend mlx folder heuristic")
    }

    func testDetectBackendKeepsExplicitMLXFolderSignatureAsMLX() throws {
        let tempDir = try makeTempDir(named: "local-qwen")
        try Data("{}".utf8).write(to: tempDir.appendingPathComponent("config.json"))
        try Data("{}".utf8).write(to: tempDir.appendingPathComponent("weights.npz"))

        let detection = LocalModelImportDetector.detectBackend(
            for: tempDir,
            manifest: nil,
            config: [
                "model_type": "qwen2",
            ]
        )

        XCTAssertEqual(detection.backend, "mlx")
        XCTAssertEqual(detection.sourceSummary, "backend folder signature")
    }

    func testDetectBackendUsesProcessorSignatureForTransformers() throws {
        let tempDir = try makeTempDir(named: "whisper-small-local")
        try Data("{}".utf8).write(to: tempDir.appendingPathComponent("config.json"))
        try Data("{}".utf8).write(to: tempDir.appendingPathComponent("processor_config.json"))

        let detection = LocalModelImportDetector.detectBackend(
            for: tempDir,
            manifest: nil,
            config: [
                "model_type": "whisper",
            ]
        )

        XCTAssertEqual(detection.backend, "transformers")
        XCTAssertEqual(detection.sourceSummary, "backend processor signature")
    }

    func testDetectBackendRecognizesGGUFFolderAsLlamaCpp() throws {
        let tempDir = try makeTempDir(named: "Qwen3-8B-Instruct-GGUF")
        try Data().write(to: tempDir.appendingPathComponent("qwen3-q4_k_m.gguf"))

        let detection = LocalModelImportDetector.detectBackend(
            for: tempDir,
            manifest: nil,
            config: nil
        )

        XCTAssertEqual(detection.backend, "llama.cpp")
        XCTAssertEqual(detection.sourceSummary, "backend gguf signature")
    }

    func testDetectCapabilitiesInfersVisionAndOCRForVisionLLM() throws {
        let tempDir = try makeTempDir(named: "GLM-4.6V-Flash-MLX-4bit")
        try Data("{}".utf8).write(to: tempDir.appendingPathComponent("config.json"))
        try Data("{}".utf8).write(to: tempDir.appendingPathComponent("preprocessor_config.json"))

        let capabilities = LocalModelImportDetector.detectCapabilities(
            for: tempDir,
            backend: "transformers",
            config: [
                "model_type": "glm4v",
                "vision_config": [
                    "hidden_size": 1536,
                ],
            ]
        )

        XCTAssertEqual(capabilities?.modelFormat, "hf_transformers")
        XCTAssertEqual(capabilities?.taskKinds, ["vision_understand", "ocr"])
        XCTAssertEqual(capabilities?.inputModalities, ["image"])
        XCTAssertEqual(capabilities?.outputModalities, ["text", "spans"])
        XCTAssertEqual(capabilities?.sourceSummary, "inferred: config/vision")
        XCTAssertEqual(capabilities?.processorRequirements.tokenizerRequired, true)
        XCTAssertEqual(capabilities?.processorRequirements.processorRequired, true)
        XCTAssertEqual(capabilities?.processorRequirements.featureExtractorRequired, true)
    }

    func testDetectCapabilitiesInfersEmbeddingTaskProfile() throws {
        let tempDir = try makeTempDir(named: "bge-m3-local")
        try Data("{}".utf8).write(to: tempDir.appendingPathComponent("config.json"))

        let capabilities = LocalModelImportDetector.detectCapabilities(
            for: tempDir,
            backend: "transformers",
            config: [
                "architectures": ["BGEEmbeddingModel"],
                "model_type": "bge",
            ]
        )

        XCTAssertEqual(capabilities?.taskKinds, ["embedding"])
        XCTAssertEqual(capabilities?.inputModalities, ["text"])
        XCTAssertEqual(capabilities?.outputModalities, ["embedding"])
        XCTAssertEqual(capabilities?.sourceSummary, "inferred: config/embedding")
        XCTAssertEqual(capabilities?.processorRequirements.processorRequired, false)
    }

    func testDetectCapabilitiesInfersEmbeddingProfileForGGUFModel() throws {
        let tempDir = try makeTempDir(named: "bge-m3-gguf")
        try Data().write(to: tempDir.appendingPathComponent("bge-m3-f16.gguf"))

        let capabilities = LocalModelImportDetector.detectCapabilities(
            for: tempDir,
            backend: "llama.cpp",
            config: nil
        )

        XCTAssertEqual(capabilities?.modelFormat, "gguf")
        XCTAssertEqual(capabilities?.taskKinds, ["embedding"])
        XCTAssertEqual(capabilities?.inputModalities, ["text"])
        XCTAssertEqual(capabilities?.outputModalities, ["embedding"])
        XCTAssertEqual(capabilities?.sourceSummary, "inferred: gguf/embedding")
    }

    func testDetectCapabilitiesInfersTextToSpeechTaskProfile() throws {
        let tempDir = try makeTempDir(named: "kokoro-82m-local")
        try Data("{}".utf8).write(to: tempDir.appendingPathComponent("config.json"))

        let capabilities = LocalModelImportDetector.detectCapabilities(
            for: tempDir,
            backend: "transformers",
            config: [
                "architectures": ["KokoroTTSModel"],
                "model_type": "kokoro_tts",
            ]
        )

        XCTAssertEqual(capabilities?.taskKinds, ["text_to_speech"])
        XCTAssertEqual(capabilities?.inputModalities, ["text"])
        XCTAssertEqual(capabilities?.outputModalities, ["audio"])
        XCTAssertEqual(capabilities?.sourceSummary, "inferred: config/tts")
        XCTAssertEqual(capabilities?.processorRequirements.tokenizerRequired, true)
        XCTAssertEqual(capabilities?.processorRequirements.processorRequired, false)
        XCTAssertEqual(capabilities?.processorRequirements.featureExtractorRequired, false)
    }

    func testDetectRuntimeReadinessSummarizesDisabledPackAndMissingRuntime() {
        let status = AIRuntimeStatus(
            pid: 42,
            updatedAt: Date().timeIntervalSince1970,
            mlxOk: false,
            providers: [
                "transformers": AIRuntimeProviderStatus(
                    provider: "transformers",
                    ok: false,
                    reasonCode: "provider_pack_disabled",
                    runtimeSource: "hub_py_deps",
                    runtimeResolutionState: "runtime_missing",
                    runtimeReasonCode: "missing_runtime",
                    packInstalled: true,
                    packEnabled: false,
                    packState: "disabled",
                    packReasonCode: "provider_pack_disabled"
                )
            ],
            providerPacks: [
                AIRuntimeProviderPackStatus(
                    providerId: "transformers",
                    installed: true,
                    enabled: false,
                    packState: "disabled",
                    reasonCode: "provider_pack_disabled"
                )
            ]
        )

        let readiness = LocalModelImportDetector.detectRuntimeReadiness(
            for: "transformers",
            runtimeStatus: status
        )

        XCTAssertFalse(readiness.canLoadNow)
        XCTAssertEqual(readiness.statusSummary, "运行包：已禁用 · 运行时：缺失")
        XCTAssertEqual(
            readiness.issueText,
            "transformers 运行包已在 Hub 中禁用；只有重新启用后，这个模型才能加载。"
        )
    }

    func testDetectRuntimeReadinessSummarizesUserPythonFallbackAndMergesWarnings() {
        let status = AIRuntimeStatus(
            pid: 43,
            updatedAt: Date().timeIntervalSince1970,
            mlxOk: false,
            providers: [
                "transformers": AIRuntimeProviderStatus(
                    provider: "transformers",
                    ok: true,
                    reasonCode: "ready",
                    runtimeSource: "user_python_venv",
                    runtimeSourcePath: "/Users/test/project/.venv/bin/python3",
                    runtimeResolutionState: "user_runtime_fallback",
                    runtimeReasonCode: "ready",
                    fallbackUsed: true,
                    runtimeHint: "transformers 当前运行在用户 Python /Users/test/project/.venv/bin/python3，而不是 Hub 托管的运行时包。",
                    packInstalled: true,
                    packEnabled: true,
                    packState: "builtin_pack_registered",
                    packReasonCode: "builtin_pack_registered"
                )
            ],
            providerPacks: [
                AIRuntimeProviderPackStatus(
                    providerId: "transformers",
                    installed: true,
                    enabled: true,
                    packState: "builtin_pack_registered",
                    reasonCode: "builtin_pack_registered"
                )
            ]
        )

        let readiness = LocalModelImportDetector.detectRuntimeReadiness(
            for: "transformers",
            runtimeStatus: status,
            importWarning: "这个 Transformers 模型可能需要更新版本的本地 Transformers 运行时后才能正常加载。",
            providerHint: "transformers 当前运行在用户 Python /Users/test/project/.venv/bin/python3，而不是 Hub 托管的运行时包。"
        )

        XCTAssertTrue(readiness.canLoadNow)
        XCTAssertEqual(readiness.statusSummary, "运行包：就绪 · 运行时：用户 Python")
        XCTAssertEqual(
            readiness.issueText,
            """
            这个 Transformers 模型可能需要更新版本的本地 Transformers 运行时后才能正常加载。

            运行时提示：transformers 当前运行在用户 Python /Users/test/project/.venv/bin/python3，而不是 Hub 托管的运行时包。
            """
        )
    }

    func testDetectRuntimeReadinessSummarizesLocalHelperBridgeAsProviderOwnedRuntime() {
        let status = AIRuntimeStatus(
            pid: 44,
            updatedAt: Date().timeIntervalSince1970,
            mlxOk: false,
            providers: [
                "transformers": AIRuntimeProviderStatus(
                    provider: "transformers",
                    ok: true,
                    reasonCode: "helper_bridge_ready",
                    runtimeSource: "helper_binary_bridge",
                    runtimeSourcePath: "/Users/test/.xhub/local_helper",
                    runtimeResolutionState: "pack_runtime_ready",
                    runtimeReasonCode: "helper_bridge_ready",
                    packInstalled: true,
                    packEnabled: true,
                    packState: "builtin_pack_registered",
                    packReasonCode: "builtin_pack_registered"
                )
            ],
            providerPacks: [
                AIRuntimeProviderPackStatus(
                    providerId: "transformers",
                    installed: true,
                    enabled: true,
                    packState: "builtin_pack_registered",
                    reasonCode: "builtin_pack_registered"
                )
            ]
        )

        let readiness = LocalModelImportDetector.detectRuntimeReadiness(
            for: "transformers",
            runtimeStatus: status
        )

        XCTAssertTrue(readiness.canLoadNow)
        XCTAssertEqual(readiness.statusSummary, "运行包：就绪 · 运行时：本地辅助运行时")
    }

    func testDetectRuntimeReadinessSummarizesHubManagedLocalServiceAsProviderOwnedRuntime() {
        let status = AIRuntimeStatus(
            pid: 45,
            updatedAt: Date().timeIntervalSince1970,
            mlxOk: false,
            providers: [
                "transformers": AIRuntimeProviderStatus(
                    provider: "transformers",
                    ok: true,
                    reasonCode: "xhub_local_service_ready",
                    runtimeSource: "xhub_local_service",
                    runtimeSourcePath: "http://127.0.0.1:50171",
                    runtimeResolutionState: "pack_runtime_ready",
                    runtimeReasonCode: "xhub_local_service_ready",
                    packInstalled: true,
                    packEnabled: true,
                    packState: "builtin_pack_registered",
                    packReasonCode: "builtin_pack_registered"
                )
            ],
            providerPacks: [
                AIRuntimeProviderPackStatus(
                    providerId: "transformers",
                    installed: true,
                    enabled: true,
                    packState: "builtin_pack_registered",
                    reasonCode: "builtin_pack_registered"
                )
            ]
        )

        let readiness = LocalModelImportDetector.detectRuntimeReadiness(
            for: "transformers",
            runtimeStatus: status
        )

        XCTAssertTrue(readiness.canLoadNow)
        XCTAssertEqual(readiness.statusSummary, "运行包：就绪 · 运行时：Hub 本地服务")
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
}
