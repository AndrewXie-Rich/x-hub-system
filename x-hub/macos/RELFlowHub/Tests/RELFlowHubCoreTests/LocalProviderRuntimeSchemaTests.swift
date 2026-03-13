import XCTest
@testable import RELFlowHubCore

final class LocalProviderRuntimeSchemaTests: XCTestCase {
    func testLegacyModelCatalogEntryDecodesWithCapabilityDefaults() throws {
        let json = """
        {
          "id": "mlx-qwen-7b",
          "name": "MLX Qwen 7B",
          "backend": "mlx",
          "quant": "int4",
          "contextLength": 8192,
          "paramsB": 7.0,
          "modelPath": "/tmp/models/mlx-qwen-7b"
        }
        """

        let entry = try JSONDecoder().decode(ModelCatalogEntry.self, from: Data(json.utf8))
        XCTAssertEqual(entry.modelFormat, "mlx")
        XCTAssertEqual(entry.taskKinds, ["text_generate"])
        XCTAssertEqual(entry.inputModalities, ["text"])
        XCTAssertEqual(entry.outputModalities, ["text"])
        XCTAssertTrue(entry.offlineReady)
        XCTAssertEqual(entry.processorRequirements.tokenizerRequired, true)
        XCTAssertEqual(entry.processorRequirements.processorRequired, false)
    }

    func testLegacyHubModelDecodesWithCapabilityDefaults() throws {
        let json = """
        {
          "id": "local-embed",
          "name": "Local Embed",
          "backend": "transformers",
          "quant": "fp16",
          "contextLength": 2048,
          "paramsB": 0.4,
          "state": "available",
          "modelPath": "/tmp/models/local-embed"
        }
        """

        let model = try JSONDecoder().decode(HubModel.self, from: Data(json.utf8))
        XCTAssertEqual(model.modelFormat, "hf_transformers")
        XCTAssertEqual(model.taskKinds, ["text_generate"])
        XCTAssertEqual(model.inputModalities, ["text"])
        XCTAssertEqual(model.outputModalities, ["text"])
        XCTAssertTrue(model.offlineReady)
    }

    func testManifestDecodeParsesSnakeCaseFields() throws {
        let json = """
        {
          "schema_version": "xhub_model_manifest.v1",
          "backend": "transformers",
          "model_format": "hf_transformers",
          "task_kinds": ["speech_to_text"],
          "input_modalities": ["audio"],
          "output_modalities": ["text", "segments"],
          "offline_ready": true,
          "resource_profile": {
            "preferred_device": "mps",
            "memory_floor_mb": 4096,
            "dtype": "float16"
          },
          "processor_requirements": {
            "tokenizer_required": false,
            "processor_required": true,
            "feature_extractor_required": true
          }
        }
        """

        let manifest = try JSONDecoder().decode(XHubLocalModelManifest.self, from: Data(json.utf8))
        XCTAssertEqual(manifest.schemaVersion, "xhub_model_manifest.v1")
        XCTAssertEqual(manifest.backend, "transformers")
        XCTAssertEqual(manifest.modelFormat, "hf_transformers")
        XCTAssertEqual(manifest.taskKinds, ["speech_to_text"])
        XCTAssertEqual(manifest.inputModalities, ["audio"])
        XCTAssertEqual(manifest.outputModalities, ["text", "segments"])
        XCTAssertEqual(manifest.resourceProfile.memoryFloorMB, 4096)
        XCTAssertEqual(manifest.processorRequirements.processorRequired, true)
        XCTAssertEqual(manifest.processorRequirements.featureExtractorRequired, true)
    }

    func testLegacyAIRuntimeStatusSynthesizesMLXProvider() throws {
        let json = """
        {
          "pid": 123,
          "updatedAt": 9999999999,
          "mlxOk": true,
          "runtimeVersion": "legacy-1",
          "activeMemoryBytes": 2048,
          "peakMemoryBytes": 4096,
          "loadedModelCount": 1
        }
        """

        let status = try JSONDecoder().decode(AIRuntimeStatus.self, from: Data(json.utf8))
        XCTAssertTrue(status.mlxOk)
        XCTAssertTrue(status.isProviderReady("mlx", ttl: 30))
        XCTAssertEqual(status.providerSummary(ttl: 30), "mlx")
        XCTAssertEqual(status.providerStatus("mlx")?.availableTaskKinds, ["text_generate"])
        XCTAssertEqual(status.providerStatus("mlx")?.activeMemoryBytes, 2048)
    }

    func testProviderAwareAIRuntimeStatusSupportsTransformersOnlyReadiness() throws {
        let json = """
        {
          "pid": 456,
          "updatedAt": 9999999999,
          "schema_version": "xhub.local_runtime_status.v2",
          "providers": {
            "transformers": {
              "provider": "transformers",
              "ok": true,
              "reasonCode": "ready",
              "runtimeVersion": "v2",
              "availableTaskKinds": ["embedding", "speech_to_text"],
              "loadedModels": ["bge-small", "whisper-small"],
              "deviceBackend": "mps",
              "updatedAt": 9999999999
            }
          }
        }
        """

        let status = try JSONDecoder().decode(AIRuntimeStatus.self, from: Data(json.utf8))
        XCTAssertFalse(status.isProviderReady("mlx", ttl: 30))
        XCTAssertTrue(status.isProviderReady("transformers", ttl: 30))
        XCTAssertEqual(status.providerSummary(ttl: 30), "transformers")
        XCTAssertEqual(status.providerStatus("transformers")?.availableTaskKinds, ["embedding", "speech_to_text"])
        XCTAssertEqual(status.providerStatus("mlx")?.ok, false)
    }

    func testProviderAwareAIRuntimeStatusPreservesMLXImportErrorForDiagnostics() throws {
        let json = """
        {
          "pid": 789,
          "updatedAt": 9999999999,
          "schema_version": "xhub.local_runtime_status.v2",
          "runtimeVersion": "legacy-mlx-test",
          "providers": {
            "mlx": {
              "provider": "mlx",
              "ok": false,
              "reasonCode": "import_error",
              "runtimeVersion": "legacy-mlx-test",
              "availableTaskKinds": [],
              "loadedModels": [],
              "deviceBackend": "mps",
              "updatedAt": 9999999999,
              "importError": "missing_module:mlx_lm"
            },
            "transformers": {
              "provider": "transformers",
              "ok": true,
              "reasonCode": "ready",
              "runtimeVersion": "transformers-skeleton",
              "availableTaskKinds": ["embedding"],
              "loadedModels": [],
              "deviceBackend": "mps",
              "updatedAt": 9999999999
            }
          }
        }
        """

        let status = try JSONDecoder().decode(AIRuntimeStatus.self, from: Data(json.utf8))
        XCTAssertFalse(status.mlxOk)
        XCTAssertTrue(status.isProviderReady("transformers", ttl: 30))
        XCTAssertFalse(status.isProviderReady("mlx", ttl: 30))
        XCTAssertEqual(status.importError, "missing_module:mlx_lm")
        XCTAssertEqual(status.providerStatus("mlx")?.importError, "missing_module:mlx_lm")
        XCTAssertEqual(status.providerStatus("mlx")?.reasonCode, "import_error")
    }

    func testProviderAwareAIRuntimeStatusBuildsProviderOperatorSummary() {
        let status = AIRuntimeStatus(
            pid: 789,
            updatedAt: Date().timeIntervalSince1970,
            mlxOk: false,
            runtimeVersion: "legacy-mlx-test",
            importError: "missing_module:mlx_lm",
            schemaVersion: "xhub.local_runtime_status.v2",
            providers: [
                "mlx": AIRuntimeProviderStatus(
                    provider: "mlx",
                    ok: false,
                    reasonCode: "import_error",
                    runtimeVersion: "legacy-mlx-test",
                    availableTaskKinds: [],
                    loadedModels: [],
                    deviceBackend: "mps",
                    updatedAt: Date().timeIntervalSince1970,
                    importError: "missing_module:mlx_lm"
                ),
                "transformers": AIRuntimeProviderStatus(
                    provider: "transformers",
                    ok: true,
                    reasonCode: "ready",
                    runtimeVersion: "transformers-skeleton",
                    availableTaskKinds: ["embedding", "speech_to_text"],
                    loadedModels: ["bge-small", "whisper-small"],
                    deviceBackend: "mps",
                    updatedAt: Date().timeIntervalSince1970,
                    loadedModelCount: 2
                ),
            ]
        )

        let summary = status.providerOperatorSummary(ttl: 30, blockedCapabilities: ["ai.audio.local"])
        XCTAssertTrue(summary.contains("ready_providers=transformers"))
        XCTAssertTrue(summary.contains("provider=mlx state=down reason=import_error"))
        XCTAssertTrue(summary.contains("provider=transformers state=ready reason=ready"))
        XCTAssertTrue(summary.contains("capability=ai.embed.local state=available providers=transformers"))
        XCTAssertTrue(summary.contains("capability=ai.audio.local state=blocked providers=none detail=blocked by ai.audio.local"))
    }

    func testProviderAwareAIRuntimeStatusDoctorTextExplainsPartialReadinessAndBlockedAudio() {
        let status = AIRuntimeStatus(
            pid: 790,
            updatedAt: Date().timeIntervalSince1970,
            mlxOk: false,
            runtimeVersion: "legacy-mlx-test",
            importError: "missing_module:mlx_lm",
            schemaVersion: "xhub.local_runtime_status.v2",
            providers: [
                "mlx": AIRuntimeProviderStatus(
                    provider: "mlx",
                    ok: false,
                    reasonCode: "import_error",
                    runtimeVersion: "legacy-mlx-test",
                    availableTaskKinds: [],
                    loadedModels: [],
                    deviceBackend: "mps",
                    updatedAt: Date().timeIntervalSince1970,
                    importError: "missing_module:mlx_lm"
                ),
                "transformers": AIRuntimeProviderStatus(
                    provider: "transformers",
                    ok: true,
                    reasonCode: "ready",
                    runtimeVersion: "transformers-skeleton",
                    availableTaskKinds: ["embedding"],
                    loadedModels: ["bge-small"],
                    deviceBackend: "mps",
                    updatedAt: Date().timeIntervalSince1970,
                    loadedModelCount: 1
                ),
            ]
        )

        let doctor = status.providerDoctorText(ttl: 30, blockedCapabilities: ["ai.audio.local"])
        XCTAssertTrue(doctor.contains("Local runtime is partially ready: transformers ready; mlx unavailable (import_error)."))
        XCTAssertTrue(doctor.contains("Text generation is unavailable"))
        XCTAssertTrue(doctor.contains("Embeddings are available via transformers."))
        XCTAssertTrue(doctor.contains("Local audio is blocked by ai.audio.local."))
    }
}
