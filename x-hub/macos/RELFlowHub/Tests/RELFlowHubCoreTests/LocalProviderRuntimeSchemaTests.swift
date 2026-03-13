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
        XCTAssertEqual(entry.maxContextLength, 8192)
        XCTAssertEqual(entry.defaultLoadProfile.contextLength, 8192)
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
        XCTAssertEqual(model.maxContextLength, 2048)
        XCTAssertEqual(model.defaultLoadProfile.contextLength, 2048)
        XCTAssertEqual(model.taskKinds, ["text_generate"])
        XCTAssertEqual(model.inputModalities, ["text"])
        XCTAssertEqual(model.outputModalities, ["text"])
        XCTAssertTrue(model.offlineReady)
    }

    func testHubModelDecodesLoadProfileAndMaxContextFromSnakeCase() throws {
        let json = """
        {
          "id": "glm-local",
          "name": "GLM Local",
          "backend": "transformers",
          "quant": "int4",
          "contextLength": 8192,
          "max_context_length": 131072,
          "default_load_profile": {
            "context_length": 16384,
            "gpu_offload_ratio": 0.75,
            "eval_batch_size": 8
          },
          "paramsB": 9.0,
          "state": "available",
          "modelPath": "/tmp/models/glm-local"
        }
        """

        let model = try JSONDecoder().decode(HubModel.self, from: Data(json.utf8))
        XCTAssertEqual(model.contextLength, 16384)
        XCTAssertEqual(model.maxContextLength, 131072)
        XCTAssertEqual(model.defaultLoadProfile.contextLength, 16384)
        XCTAssertEqual(model.defaultLoadProfile.gpuOffloadRatio, 0.75)
        XCTAssertEqual(model.defaultLoadProfile.evalBatchSize, 8)
    }

    func testManifestDecodeParsesSnakeCaseFields() throws {
        let json = """
        {
          "schema_version": "xhub_model_manifest.v1",
          "backend": "transformers",
          "model_format": "hf_transformers",
          "max_context_length": 131072,
          "default_load_profile": {
            "context_length": 16384,
            "eval_batch_size": 16
          },
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
        XCTAssertEqual(manifest.maxContextLength, 131072)
        XCTAssertEqual(manifest.defaultLoadProfile?.contextLength, 16384)
        XCTAssertEqual(manifest.defaultLoadProfile?.evalBatchSize, 16)
        XCTAssertEqual(manifest.taskKinds, ["speech_to_text"])
        XCTAssertEqual(manifest.inputModalities, ["audio"])
        XCTAssertEqual(manifest.outputModalities, ["text", "segments"])
        XCTAssertEqual(manifest.resourceProfile.memoryFloorMB, 4096)
        XCTAssertEqual(manifest.processorRequirements.processorRequired, true)
        XCTAssertEqual(manifest.processorRequirements.featureExtractorRequired, true)
    }

    func testPairedTerminalLocalModelProfilesSnapshotDecodesSnakeCaseOverrideProfile() throws {
        let json = """
        {
          "schema_version": "hub.paired_terminal_local_model_profiles.v1",
          "updated_at_ms": 1741800000000,
          "profiles": [
            {
              "device_id": "terminal_device",
              "model_id": "glm-local",
              "override_profile": {
                "context_length": 32768,
                "rope_frequency_scale": 2.0
              },
              "updated_at_ms": 1741800001000,
              "updated_by": "operator",
              "note": "context experiment"
            }
          ]
        }
        """

        let snapshot = try JSONDecoder().decode(HubPairedTerminalLocalModelProfilesSnapshot.self, from: Data(json.utf8))
        XCTAssertEqual(snapshot.schemaVersion, "hub.paired_terminal_local_model_profiles.v1")
        XCTAssertEqual(snapshot.profiles.count, 1)
        XCTAssertEqual(snapshot.profiles.first?.deviceId, "terminal_device")
        XCTAssertEqual(snapshot.profiles.first?.modelId, "glm-local")
        XCTAssertEqual(snapshot.profiles.first?.overrideProfile.contextLength, 32768)
        XCTAssertEqual(snapshot.profiles.first?.overrideProfile.ropeFrequencyScale, 2.0)
    }

    func testLoadProfileOverrideKeepsHiddenFieldsWhenContextCleared() {
        var overrideProfile = LocalModelLoadProfileOverride(
            contextLength: 32768,
            gpuOffloadRatio: 0.8,
            evalBatchSize: 16
        )

        overrideProfile.contextLength = nil

        XCTAssertNil(overrideProfile.contextLength)
        XCTAssertEqual(overrideProfile.gpuOffloadRatio, 0.8)
        XCTAssertEqual(overrideProfile.evalBatchSize, 16)
        XCTAssertFalse(overrideProfile.isEmpty)
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
              "updatedAt": 9999999999,
              "lifecycleMode": "warmable",
              "supportedLifecycleActions": ["warmup_local_model", "unload_local_model", "evict_local_instance"],
              "warmupTaskKinds": ["embedding", "speech_to_text"],
              "residencyScope": "process_local",
              "loadedInstances": [
                {
                  "instanceKey": "transformers:bge-small:ctx8192",
                  "modelId": "bge-small",
                  "taskKinds": ["embedding"],
                  "loadProfileHash": "ctx8192",
                  "effectiveContextLength": 8192,
                  "loadedAt": 9999999999,
                  "lastUsedAt": 9999999999,
                  "residency": "resident",
                  "residencyScope": "process_local",
                  "deviceBackend": "mps"
                }
              ]
            }
          }
        }
        """

        let status = try JSONDecoder().decode(AIRuntimeStatus.self, from: Data(json.utf8))
        XCTAssertFalse(status.isProviderReady("mlx", ttl: 30))
        XCTAssertTrue(status.isProviderReady("transformers", ttl: 30))
        XCTAssertEqual(status.providerSummary(ttl: 30), "transformers")
        XCTAssertEqual(status.providerStatus("transformers")?.availableTaskKinds, ["embedding", "speech_to_text"])
        XCTAssertEqual(status.providerStatus("transformers")?.lifecycleMode, "warmable")
        XCTAssertEqual(status.providerStatus("transformers")?.warmupTaskKinds, ["embedding", "speech_to_text"])
        XCTAssertEqual(status.providerStatus("transformers")?.loadedInstances.first?.instanceKey, "transformers:bge-small:ctx8192")
        XCTAssertEqual(
            status.providerStatus("transformers")?.hubControlMode(forModelTaskKinds: ["embedding"]),
            .ephemeralOnDemand
        )
        XCTAssertEqual(status.providerStatus("mlx")?.ok, false)
    }

    func testProviderStatusWarmableControlModeRequiresNonProcessResidency() {
        let status = AIRuntimeProviderStatus(
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
        )

        XCTAssertTrue(status.supportsWarmup(forModelTaskKinds: ["embedding"]))
        XCTAssertEqual(status.hubControlMode(forModelTaskKinds: ["embedding"]), .warmable)
        XCTAssertEqual(status.hubControlMode(forModelTaskKinds: ["speech_to_text"]), .ephemeralOnDemand)
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
