import XCTest
@testable import RELFlowHubCore

final class LocalProviderRuntimeSchemaTests: XCTestCase {
    private func jsonObject(_ data: Data) throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(with: data)
        return try XCTUnwrap(object as? [String: Any])
    }

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
          "default_load_config": {
            "context_length": 16384,
            "gpu_offload_ratio": 0.75,
            "eval_batch_size": 8,
            "ttl": 900,
            "parallel": 2,
            "identifier": "glm4v-slot",
            "vision": {
              "image_max_dimension": 4096
            }
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
        XCTAssertEqual(model.defaultLoadProfile.ttl, 900)
        XCTAssertEqual(model.defaultLoadProfile.parallel, 2)
        XCTAssertEqual(model.defaultLoadProfile.identifier, "glm4v-slot")
        XCTAssertEqual(model.defaultLoadProfile.vision?.imageMaxDimension, 4096)
    }

    func testHubModelStillDecodesLegacyDefaultLoadProfileAlias() throws {
        let json = """
        {
          "id": "legacy-local",
          "name": "Legacy Local",
          "backend": "transformers",
          "contextLength": 2048,
          "default_load_profile": {
            "context_length": 4096,
            "ttl": 600
          }
        }
        """

        let model = try JSONDecoder().decode(HubModel.self, from: Data(json.utf8))
        XCTAssertEqual(model.defaultLoadProfile.contextLength, 4096)
        XCTAssertEqual(model.defaultLoadProfile.ttl, 600)
    }

    func testManifestDecodeParsesSnakeCaseFields() throws {
        let json = """
        {
          "schema_version": "xhub_model_manifest.v1",
          "backend": "transformers",
          "model_format": "hf_transformers",
          "max_context_length": 131072,
          "default_load_config": {
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

    func testHubModelEncodeUsesCanonicalDefaultLoadProfileKey() throws {
        let model = HubModel(
            id: "glm-local",
            name: "GLM Local",
            backend: "transformers",
            quant: "int4",
            contextLength: 8192,
            maxContextLength: 131072,
            paramsB: 9.0,
            state: .available,
            defaultLoadProfile: LocalModelLoadProfile(contextLength: 16384, ttl: 900)
        )

        let json = try jsonObject(JSONEncoder().encode(model))

        XCTAssertNotNil(json["defaultLoadProfile"])
        XCTAssertNil(json["default_load_config"])
        XCTAssertNil(json["default_load_profile"])
    }

    func testModelCatalogEntryEncodeUsesCanonicalDefaultLoadProfileKey() throws {
        let entry = ModelCatalogEntry(
            id: "mlx-qwen-7b",
            name: "MLX Qwen 7B",
            backend: "mlx",
            quant: "int4",
            contextLength: 8192,
            maxContextLength: 16384,
            paramsB: 7.0,
            modelPath: "/tmp/models/mlx-qwen-7b",
            defaultLoadProfile: LocalModelLoadProfile(contextLength: 12288, ttl: 600)
        )

        let json = try jsonObject(JSONEncoder().encode(entry))

        XCTAssertNotNil(json["defaultLoadProfile"])
        XCTAssertNil(json["default_load_config"])
        XCTAssertNil(json["default_load_profile"])
    }

    func testManifestEncodeUsesCanonicalDefaultLoadProfileKey() throws {
        let manifest = XHubLocalModelManifest(
            backend: "transformers",
            modelFormat: "hf_transformers",
            maxContextLength: 131072,
            defaultLoadProfile: LocalModelLoadProfile(contextLength: 16384, evalBatchSize: 16),
            taskKinds: ["speech_to_text"],
            inputModalities: ["audio"],
            outputModalities: ["text", "segments"]
        )

        let json = try jsonObject(JSONEncoder().encode(manifest))

        XCTAssertNotNil(json["default_load_profile"])
        XCTAssertNil(json["default_load_config"])
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
                "rope_frequency_scale": 2.0,
                "ttl": 1200,
                "parallel": 4,
                "identifier": "terminal-a",
                "vision": {
                  "image_max_dimension": 3072
                }
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
        XCTAssertEqual(snapshot.profiles.first?.overrideProfile.ttl, 1200)
        XCTAssertEqual(snapshot.profiles.first?.overrideProfile.parallel, 4)
        XCTAssertEqual(snapshot.profiles.first?.overrideProfile.identifier, "terminal-a")
        XCTAssertEqual(snapshot.profiles.first?.overrideProfile.vision?.imageMaxDimension, 3072)
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

    func testAIRuntimeLoadedInstanceDecodesTypedLoadProfileFields() throws {
        let json = """
        {
          "instance_key": "transformers:glm-local:hash1234",
          "model_id": "glm-local",
          "task_kinds": ["vision_understand"],
          "load_profile_hash": "hash1234",
          "effective_context_length": 16384,
          "max_context_length": 131072,
          "effective_load_profile": {
            "context_length": 16384,
            "ttl": 600,
            "parallel": 3,
            "identifier": "glm4v-a",
            "vision": {
              "image_max_dimension": 2048
            }
          },
          "loaded_at": 10,
          "last_used_at": 20,
          "residency": "resident",
          "residency_scope": "runtime_process",
          "device_backend": "helper_binary_bridge"
        }
        """

        let instance = try JSONDecoder().decode(AIRuntimeLoadedInstance.self, from: Data(json.utf8))
        XCTAssertEqual(instance.instanceKey, "transformers:glm-local:hash1234")
        XCTAssertEqual(instance.maxContextLength, 131072)
        XCTAssertEqual(instance.ttl, 600)
        XCTAssertEqual(instance.effectiveLoadProfile?.ttl, 600)
        XCTAssertEqual(instance.effectiveLoadProfile?.parallel, 3)
        XCTAssertEqual(instance.effectiveLoadProfile?.identifier, "glm4v-a")
        XCTAssertEqual(instance.effectiveLoadProfile?.vision?.imageMaxDimension, 2048)
    }

    func testAIRuntimeLoadedInstanceDecodesNodeTypedLoadConfigAliases() throws {
        let json = """
        {
          "instance_key": "mlx:qwen-local:hash5678",
          "model_id": "qwen-local",
          "task_kinds": ["text_generate"],
          "load_config_hash": "hash5678",
          "current_context_length": 40960,
          "max_context_length": 65536,
          "load_config": {
            "schema_version": "xhub.load_config.v1",
            "context_length": 40960,
            "ttl": 900,
            "parallel": 2,
            "identifier": "slot-b"
          },
          "loaded_at": 15,
          "last_used_at": 30,
          "residency": "resident",
          "residency_scope": "legacy_runtime",
          "device_backend": "mps"
        }
        """

        let instance = try JSONDecoder().decode(AIRuntimeLoadedInstance.self, from: Data(json.utf8))
        XCTAssertEqual(instance.loadConfigHash, "hash5678")
        XCTAssertEqual(instance.loadProfileHash, "hash5678")
        XCTAssertEqual(instance.currentContextLength, 40960)
        XCTAssertEqual(instance.effectiveContextLength, 40960)
        XCTAssertEqual(instance.maxContextLength, 65536)
        XCTAssertEqual(instance.ttl, 900)
        XCTAssertEqual(instance.loadConfig?.ttl, 900)
        XCTAssertEqual(instance.loadConfig?.parallel, 2)
        XCTAssertEqual(instance.loadConfig?.identifier, "slot-b")
    }

    func testAIRuntimeMonitorActiveTaskDecodesTypedLoadConfigAliases() throws {
        let json = """
        {
          "provider": "transformers",
          "lease_id": "lease-a",
          "task_kind": "embedding",
          "model_id": "bge-small",
          "request_id": "req-a",
          "device_id": "terminal-a",
          "load_config_hash": "cfg1234",
          "instance_key": "transformers:bge-small:cfg1234",
          "current_context_length": 8192,
          "max_context_length": 16384,
          "lease_ttl_sec": 300,
          "lease_remaining_ttl_sec": 120,
          "expires_at": 320,
          "started_at": 20
        }
        """

        let task = try JSONDecoder().decode(AIRuntimeMonitorActiveTask.self, from: Data(json.utf8))
        XCTAssertEqual(task.loadConfigHash, "cfg1234")
        XCTAssertEqual(task.loadProfileHash, "cfg1234")
        XCTAssertEqual(task.currentContextLength, 8192)
        XCTAssertEqual(task.effectiveContextLength, 8192)
        XCTAssertEqual(task.maxContextLength, 16384)
        XCTAssertEqual(task.leaseTtlSec, 300)
        XCTAssertEqual(task.leaseRemainingTtlSec, 120)
        XCTAssertEqual(task.expiresAt, 320)
    }

    func testProviderPackRuntimeRequirementsDecodeServiceBaseURLFromSnakeCase() throws {
        let json = """
        {
          "execution_mode": "xhub_local_service",
          "service_base_url": "http://127.0.0.1:50171",
          "notes": ["hub_managed_service"]
        }
        """

        let requirements = try JSONDecoder().decode(AIRuntimeProviderPackRuntimeRequirements.self, from: Data(json.utf8))
        XCTAssertEqual(requirements.executionMode, "xhub_local_service")
        XCTAssertEqual(requirements.serviceBaseUrl, "http://127.0.0.1:50171")
        XCTAssertEqual(requirements.notes, ["hub_managed_service"])
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
        XCTAssertEqual(status.providerPackStatus("mlx")?.packState, "legacy_unreported")
        XCTAssertEqual(status.providerPackStatus("mlx")?.reasonCode, "runtime_status_missing_provider_pack_inventory")
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

    func testAIRuntimeStatusDecodesProviderPackInventoryAndBackfillsProviderPackFields() throws {
        let json = """
        {
          "pid": 457,
          "updated_at": 9999999999,
          "schemaVersion": "xhub.local_runtime_status.v2",
          "providers": {
            "transformers": {
              "provider": "transformers",
              "ok": true,
              "reason_code": "ready",
              "runtime_version": "entry-v2",
              "runtime_source": "user_python_venv",
              "runtime_source_path": "/Users/test/project/.venv/bin/python3",
              "runtime_resolution_state": "user_runtime_fallback",
              "runtime_reason_code": "ready",
              "fallback_used": true,
              "runtime_hint": "transformers is running from user Python /Users/test/project/.venv/bin/python3.",
              "runtime_missing_requirements": [],
              "runtime_missing_optional_requirements": [],
              "available_task_kinds": ["embedding", "vision_understand"],
              "loaded_models": ["bge-small"],
              "device_backend": "mps",
              "updated_at": 9999999999
            }
          },
          "provider_packs": [
            {
              "schema_version": "xhub.provider_pack_manifest.v1",
              "provider_id": "mlx",
              "engine": "mlx-llm",
              "version": "builtin-2026-03-16",
              "supported_formats": ["mlx"],
              "supported_domains": ["text"],
              "runtime_requirements": {
                "execution_mode": "builtin_python",
                "python_modules": ["mlx_lm"],
                "notes": ["offline_only"]
              },
              "min_hub_version": "2026.03",
              "installed": true,
              "enabled": true,
              "pack_state": "installed",
              "reason_code": "builtin_pack_registered"
            },
            {
              "schema_version": "xhub.provider_pack_manifest.v1",
              "provider_id": "transformers",
              "engine": "hf-transformers",
              "version": "builtin-2026-03-16",
              "supported_formats": ["hf_transformers"],
              "supported_domains": ["embedding", "audio", "vision", "ocr"],
              "runtime_requirements": {
                "execution_mode": "builtin_python",
                "python_modules": ["transformers", "torch", "tokenizers", "PIL"],
                "notes": ["offline_only", "processor_required_for_multimodal"]
              },
              "min_hub_version": "2026.03",
              "installed": true,
              "enabled": true,
              "pack_state": "installed",
              "reason_code": "builtin_pack_registered"
            }
          ]
        }
        """

        let status = try JSONDecoder().decode(AIRuntimeStatus.self, from: Data(json.utf8))

        XCTAssertEqual(status.providerPacks.count, 2)
        XCTAssertEqual(status.providerPackStatus("transformers")?.engine, "hf-transformers")
        XCTAssertEqual(status.providerPackStatus("transformers")?.runtimeRequirements.executionMode, "builtin_python")
        XCTAssertEqual(status.providerPackStatus("transformers")?.runtimeRequirements.pythonModules, ["transformers", "torch", "tokenizers", "pil"])
        XCTAssertEqual(status.providerStatus("transformers")?.availableTaskKinds, ["embedding", "vision_understand"])
        XCTAssertEqual(status.providerStatus("transformers")?.packId, "transformers")
        XCTAssertEqual(status.providerStatus("transformers")?.packEngine, "hf-transformers")
        XCTAssertEqual(status.providerStatus("transformers")?.packVersion, "builtin-2026-03-16")
        XCTAssertEqual(status.providerStatus("transformers")?.packInstalled, true)
        XCTAssertEqual(status.providerStatus("transformers")?.packEnabled, true)
        XCTAssertEqual(status.providerStatus("transformers")?.packState, "installed")
        XCTAssertEqual(status.providerStatus("transformers")?.packReasonCode, "builtin_pack_registered")
        XCTAssertEqual(status.providerStatus("transformers")?.runtimeSource, "user_python_venv")
        XCTAssertEqual(status.providerStatus("transformers")?.runtimeSourcePath, "/Users/test/project/.venv/bin/python3")
        XCTAssertEqual(status.providerStatus("transformers")?.runtimeResolutionState, "user_runtime_fallback")
        XCTAssertEqual(status.providerStatus("transformers")?.runtimeReasonCode, "ready")
        XCTAssertEqual(status.providerStatus("transformers")?.fallbackUsed, true)
    }

    func testProviderAwareAIRuntimeStatusDecodesManagedServiceState() throws {
        let json = """
        {
          "pid": 790,
          "updatedAt": 9999999999,
          "schema_version": "xhub.local_runtime_status.v2",
          "providers": {
            "transformers": {
              "provider": "transformers",
              "ok": false,
              "reasonCode": "runtime_missing",
              "runtimeVersion": "entry-v2",
              "runtimeSource": "xhub_local_service",
              "runtimeSourcePath": "http://127.0.0.1:50171",
              "runtimeResolutionState": "runtime_missing",
              "runtimeReasonCode": "xhub_local_service_unreachable",
              "fallbackUsed": false,
              "availableTaskKinds": [],
              "loadedModels": [],
              "deviceBackend": "service_proxy",
              "updatedAt": 9999999999,
              "managedServiceState": {
                "baseUrl": "http://127.0.0.1:50171",
                "bindHost": "127.0.0.1",
                "bindPort": 50171,
                "pid": 43001,
                "processState": "launch_failed",
                "lastProbeAtMs": 1741800001000,
                "lastProbeHttpStatus": 0,
                "lastProbeError": "ConnectionRefusedError:[Errno 61] Connection refused",
                "lastLaunchAttemptAtMs": 1741800000000,
                "startAttemptCount": 2,
                "lastStartError": "health_timeout:http://127.0.0.1:50171",
                "updatedAtMs": 1741800001000
              }
            }
          }
        }
        """

        let status = try JSONDecoder().decode(AIRuntimeStatus.self, from: Data(json.utf8))
        let managed = try XCTUnwrap(status.providerStatus("transformers")?.managedServiceState)

        XCTAssertEqual(managed.baseURL, "http://127.0.0.1:50171")
        XCTAssertEqual(managed.bindHost, "127.0.0.1")
        XCTAssertEqual(managed.bindPort, 50171)
        XCTAssertEqual(managed.pid, 43001)
        XCTAssertEqual(managed.processState, "launch_failed")
        XCTAssertEqual(managed.lastProbeHTTPStatus, 0)
        XCTAssertEqual(managed.startAttemptCount, 2)
        XCTAssertEqual(managed.lastStartError, "health_timeout:http://127.0.0.1:50171")
        XCTAssertEqual(
            status.providerDiagnoses(ttl: 30).first(where: { $0.provider == "transformers" })?.managedServiceState?.processState,
            "launch_failed"
        )
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
                    runtimeSource: "user_python_venv",
                    runtimeSourcePath: "/Users/test/project/.venv/bin/python3",
                    runtimeResolutionState: "user_runtime_fallback",
                    runtimeReasonCode: "ready",
                    fallbackUsed: true,
                    availableTaskKinds: ["embedding", "speech_to_text"],
                    loadedModels: ["bge-small", "whisper-small"],
                    deviceBackend: "mps",
                    updatedAt: Date().timeIntervalSince1970,
                    loadedModelCount: 2
                ),
            ],
            providerPacks: [
                AIRuntimeProviderPackStatus(
                    schemaVersion: "xhub.provider_pack_manifest.v1",
                    providerId: "transformers",
                    engine: "hf-transformers",
                    version: "builtin-2026-03-16",
                    supportedFormats: ["hf_transformers"],
                    supportedDomains: ["embedding", "audio", "vision", "ocr"],
                    runtimeRequirements: AIRuntimeProviderPackRuntimeRequirements(
                        executionMode: "builtin_python",
                        pythonModules: ["transformers", "torch"]
                    ),
                    minHubVersion: "2026.03",
                    installed: true,
                    enabled: true,
                    packState: "installed",
                    reasonCode: "builtin_pack_registered"
                ),
            ]
        )

        let summary = status.providerOperatorSummary(ttl: 30, blockedCapabilities: ["ai.audio.local"])
        XCTAssertTrue(summary.contains("ready_providers=transformers"))
        XCTAssertTrue(summary.contains("provider_pack_count=2"))
        XCTAssertTrue(summary.contains("provider=mlx state=down reason=import_error"))
        XCTAssertTrue(summary.contains("provider=transformers state=ready reason=ready"))
        XCTAssertTrue(summary.contains("runtime_source=user_python_venv"))
        XCTAssertTrue(summary.contains("runtime_state=user_runtime_fallback"))
        XCTAssertTrue(summary.contains("fallback=1"))
        XCTAssertTrue(summary.contains("provider_packs:"))
        XCTAssertTrue(summary.contains("provider=transformers installed=1 enabled=1 state=installed engine=hf-transformers version=builtin-2026-03-16"))
        XCTAssertTrue(summary.contains("provider=mlx installed=0 enabled=0 state=legacy_unreported"))
        XCTAssertTrue(summary.contains("capability=ai.embed.local state=available providers=transformers"))
        XCTAssertTrue(summary.contains("capability=ai.audio.local state=blocked providers=none detail=blocked by ai.audio.local"))
    }

    func testAIRuntimeStatusDecodesSnakeCaseRuntimeMonitorSnapshot() throws {
        let json = """
        {
          "pid": 902,
          "updated_at": 9999999999,
          "schemaVersion": "xhub.local_runtime_status.v2",
          "mlx_ok": false,
          "runtime_version": "entry-v2",
          "providers": {
            "transformers": {
              "provider": "transformers",
              "ok": true,
              "reason_code": "fallback_ready",
              "runtime_version": "entry-v2",
              "available_task_kinds": ["embedding", "speech_to_text"],
              "loaded_models": ["bge-small", "whisper-small"],
              "device_backend": "mps",
              "updated_at": 9999999999
            }
          },
          "monitor_snapshot": {
            "schema_version": "xhub.local_runtime_monitor.v1",
            "updated_at": 9999999998,
            "providers": [
              {
                "provider": "transformers",
                "ok": true,
                "reason_code": "fallback_ready",
                "available_task_kinds": ["embedding", "speech_to_text"],
                "real_task_kinds": ["embedding"],
                "fallback_task_kinds": ["speech_to_text"],
                "unavailable_task_kinds": ["vision_caption"],
                "device_backend": "mps",
                "lifecycle_mode": "warmable",
                "residency_scope": "provider_runtime",
                "loaded_instance_count": 1,
                "loaded_model_count": 2,
                "active_task_count": 1,
                "queued_task_count": 2,
                "concurrency_limit": 2,
                "queue_mode": "fifo",
                "queueing_supported": true,
                "oldest_waiter_started_at": 9999999997,
                "oldest_waiter_age_ms": 280,
                "contention_count": 3,
                "last_contention_at": 9999999996,
                "active_memory_bytes": 2048,
                "peak_memory_bytes": 4096,
                "memory_state": "ok",
                "idle_eviction_policy": "ttl",
                "last_idle_eviction_reason": "timeout",
                "updated_at": 9999999998
              }
            ],
            "active_tasks": [
              {
                "provider": "transformers",
                "lease_id": "lease-b",
                "task_kind": "speech_to_text",
                "model_id": "whisper-small",
                "request_id": "req-b",
                "device_id": "terminal-b",
                "load_profile_hash": "ctx4096",
                "instance_key": "transformers:whisper-small:ctx4096",
                "effective_context_length": 4096,
                "started_at": 9999999998
              },
              {
                "provider": "transformers",
                "lease_id": "lease-a",
                "task_kind": "embedding",
                "model_id": "bge-small",
                "request_id": "req-a",
                "device_id": "terminal-a",
                "load_profile_hash": "ctx8192",
                "instance_key": "transformers:bge-small:ctx8192",
                "effective_context_length": 8192,
                "started_at": 9999999997
              }
            ],
            "loaded_instances": [
              {
                "instance_key": "transformers:bge-small:ctx8192",
                "model_id": "bge-small",
                "task_kinds": ["embedding"],
                "load_profile_hash": "ctx8192",
                "effective_context_length": 8192,
                "loaded_at": 9999999990,
                "last_used_at": 9999999998,
                "residency": "resident",
                "residency_scope": "provider_runtime",
                "device_backend": "mps"
              }
            ],
            "recent_bench_results": [
              {
                "provider": "transformers",
                "model_id": "glm4v-local",
                "task_kind": "vision_understand",
                "load_profile_hash": "vision8192",
                "fixture_profile": "vision_smoke",
                "fixture_title": "Vision Smoke",
                "measured_at": 9999999998,
                "result_kind": "task_aware_quick_bench",
                "ok": true,
                "reason_code": "ready",
                "runtime_source": "xhub_local_service",
                "runtime_resolution_state": "service_ready",
                "runtime_reason_code": "xhub_local_service_ready",
                "route_trace_summary": {
                  "schema_version": "xhub.local_runtime.route_trace_summary.v1",
                  "selected_task_kind": "vision_understand",
                  "selection_reason": "model_only_vision_understand",
                  "request_mode": "chat_completions",
                  "image_count": 1,
                  "resolved_image_count": 1,
                  "execution_path": "real_runtime",
                  "fallback_mode": "",
                  "image_files": ["route_trace_fixture.png"]
                }
              }
            ],
            "queue": {
              "provider_count": 1,
              "active_task_count": 1,
              "queued_task_count": 2,
              "providers_busy_count": 1,
              "providers_with_queued_tasks_count": 1,
              "max_oldest_wait_ms": 280,
              "contention_count": 3,
              "last_contention_at": 9999999996,
              "updated_at": 9999999998,
              "providers": [
                {
                  "provider": "transformers",
                  "concurrency_limit": 2,
                  "active_task_count": 1,
                  "queued_task_count": 2,
                  "queue_mode": "fifo",
                  "queueing_supported": true,
                  "oldest_waiter_started_at": 9999999997,
                  "oldest_waiter_age_ms": 280,
                  "contention_count": 3,
                  "last_contention_at": 9999999996,
                  "updated_at": 9999999998
                }
              ]
            },
            "last_errors": [
              {
                "provider": "transformers",
                "code": "queue_backpressure",
                "message": "gpu busy",
                "severity": "warn",
                "updated_at": 9999999994
              },
              {
                "provider": "mlx",
                "code": "import_error",
                "message": "missing mlx",
                "severity": "error",
                "updated_at": 9999999995
              }
            ],
            "fallback_counters": {
              "provider_count": 1,
              "fallback_ready_provider_count": 1,
              "fallback_only_provider_count": 0,
              "fallback_ready_task_count": 1,
              "fallback_only_task_count": 0,
              "task_kind_counts": {
                "speech_to_text": 1
              }
            }
          }
        }
        """

        let status = try JSONDecoder().decode(AIRuntimeStatus.self, from: Data(json.utf8))

        XCTAssertEqual(status.schemaVersion, "xhub.local_runtime_status.v2")
        XCTAssertEqual(status.runtimeVersion, "entry-v2")
        XCTAssertFalse(status.mlxOk)
        XCTAssertNotNil(status.monitorSnapshot)
        XCTAssertEqual(status.monitorSnapshot?.schemaVersion, "xhub.local_runtime_monitor.v1")
        XCTAssertEqual(status.monitorSnapshot?.providers.count, 1)
        XCTAssertEqual(status.monitorSnapshot?.providers.first?.reasonCode, "fallback_ready")
        XCTAssertEqual(status.monitorSnapshot?.providers.first?.realTaskKinds, ["embedding"])
        XCTAssertEqual(status.monitorSnapshot?.providers.first?.fallbackTaskKinds, ["speech_to_text"])
        XCTAssertEqual(status.monitorSnapshot?.providers.first?.unavailableTaskKinds, ["vision_caption"])
        XCTAssertEqual(status.monitorSnapshot?.activeTasks.map(\.leaseId), ["lease-a", "lease-b"])
        XCTAssertEqual(status.monitorSnapshot?.activeTasks.first?.taskKind, "embedding")
        XCTAssertEqual(status.monitorSnapshot?.loadedInstances.first?.instanceKey, "transformers:bge-small:ctx8192")
        XCTAssertEqual(status.monitorSnapshot?.recentBenchResults.count, 1)
        XCTAssertEqual(status.monitorSnapshot?.recentBenchResults.first?.providerID, "transformers")
        XCTAssertEqual(status.monitorSnapshot?.recentBenchResults.first?.routeTraceSummary?.selectedTaskKind, "vision_understand")
        XCTAssertEqual(status.monitorSnapshot?.recentBenchResults.first?.routeTraceSummary?.executionPath, "real_runtime")
        XCTAssertEqual(status.monitorSnapshot?.recentBenchResults.first?.routeTraceSummary?.imageFiles, ["route_trace_fixture.png"])
        XCTAssertEqual(status.monitorSnapshot?.queue.providerCount, 1)
        XCTAssertEqual(status.monitorSnapshot?.queue.providers.first?.queueMode, "fifo")
        XCTAssertEqual(status.monitorSnapshot?.lastErrors.map(\.provider), ["mlx", "transformers"])
        XCTAssertEqual(status.monitorSnapshot?.fallbackCounters.fallbackReadyProviderCount, 1)
        XCTAssertEqual(status.monitorSnapshot?.fallbackCounters.taskKindCounts["speech_to_text"], 1)
    }

    func testAIRuntimeStatusBuildsRuntimeMonitorOperatorSummary() {
        let status = AIRuntimeStatus(
            pid: 903,
            updatedAt: Date().timeIntervalSince1970,
            mlxOk: false,
            runtimeVersion: "entry-v2",
            schemaVersion: "xhub.local_runtime_status.v2",
            providers: [
                "transformers": AIRuntimeProviderStatus(
                    provider: "transformers",
                    ok: true,
                    reasonCode: "fallback_ready",
                    runtimeVersion: "entry-v2",
                    availableTaskKinds: ["embedding", "speech_to_text"],
                    loadedModels: ["bge-small", "whisper-small"],
                    deviceBackend: "mps",
                    updatedAt: Date().timeIntervalSince1970
                )
            ],
            monitorSnapshot: AIRuntimeMonitorSnapshot(
                schemaVersion: "xhub.local_runtime_monitor.v1",
                updatedAt: Date().timeIntervalSince1970,
                providers: [
                    AIRuntimeMonitorProvider(
                        provider: "transformers",
                        ok: true,
                        reasonCode: "fallback_ready",
                        availableTaskKinds: ["embedding", "speech_to_text"],
                        realTaskKinds: ["embedding"],
                        fallbackTaskKinds: ["speech_to_text"],
                        unavailableTaskKinds: ["vision_caption"],
                        deviceBackend: "mps",
                        lifecycleMode: "warmable",
                        residencyScope: "provider_runtime",
                        loadedInstanceCount: 1,
                        loadedModelCount: 2,
                        activeTaskCount: 1,
                        queuedTaskCount: 2,
                        concurrencyLimit: 2,
                        queueMode: "fifo",
                        queueingSupported: true,
                        oldestWaiterStartedAt: Date().timeIntervalSince1970 - 2,
                        oldestWaiterAgeMs: 280,
                        contentionCount: 3,
                        lastContentionAt: Date().timeIntervalSince1970 - 1,
                        activeMemoryBytes: 2048,
                        peakMemoryBytes: 4096,
                        memoryState: "ok",
                        idleEvictionPolicy: "ttl",
                        lastIdleEvictionReason: "timeout",
                        updatedAt: Date().timeIntervalSince1970
                    )
                ],
                activeTasks: [
                    AIRuntimeMonitorActiveTask(
                        provider: "transformers",
                        leaseId: "lease-a",
                        taskKind: "embedding",
                        modelId: "bge-small",
                        requestId: "req-a",
                        deviceId: "terminal-a",
                        loadProfileHash: "ctx8192",
                        instanceKey: "transformers:bge-small:ctx8192",
                        effectiveContextLength: 8192,
                        startedAt: Date().timeIntervalSince1970 - 1
                    )
                ],
                loadedInstances: [
                    AIRuntimeLoadedInstance(
                        instanceKey: "transformers:bge-small:ctx8192",
                        modelId: "bge-small",
                        taskKinds: ["embedding"],
                        loadProfileHash: "ctx8192",
                        effectiveContextLength: 8192,
                        loadedAt: Date().timeIntervalSince1970 - 20,
                        lastUsedAt: Date().timeIntervalSince1970 - 1,
                        residency: "resident",
                        residencyScope: "provider_runtime",
                        deviceBackend: "mps"
                    )
                ],
                recentBenchResults: [
                    ModelBenchResult(
                        modelId: "glm4v-local",
                        providerID: "transformers",
                        taskKind: "vision_understand",
                        loadProfileHash: "vision8192",
                        fixtureProfile: "vision_smoke",
                        fixtureTitle: "Vision Smoke",
                        measuredAt: Date().timeIntervalSince1970 - 2,
                        ok: true,
                        reasonCode: "ready",
                        runtimeSource: "xhub_local_service",
                        runtimeResolutionState: "service_ready",
                        runtimeReasonCode: "xhub_local_service_ready",
                        routeTraceSummary: AIRuntimeRouteTraceSummary(
                            schemaVersion: "xhub.local_runtime.route_trace_summary.v1",
                            requestMode: "chat_completions",
                            selectedTaskKind: "vision_understand",
                            selectionReason: "model_only_vision_understand",
                            imageCount: 1,
                            resolvedImageCount: 1,
                            executionPath: "real_runtime",
                            imageFiles: ["route_trace_fixture.png"]
                        )
                    )
                ],
                queue: AIRuntimeMonitorQueue(
                    providerCount: 1,
                    activeTaskCount: 1,
                    queuedTaskCount: 2,
                    providersBusyCount: 1,
                    providersWithQueuedTasksCount: 1,
                    maxOldestWaitMs: 280,
                    contentionCount: 3,
                    lastContentionAt: Date().timeIntervalSince1970 - 1,
                    updatedAt: Date().timeIntervalSince1970,
                    providers: [
                        AIRuntimeMonitorQueueProvider(
                            provider: "transformers",
                            concurrencyLimit: 2,
                            activeTaskCount: 1,
                            queuedTaskCount: 2,
                            queueMode: "fifo",
                            queueingSupported: true,
                            oldestWaiterStartedAt: Date().timeIntervalSince1970 - 2,
                            oldestWaiterAgeMs: 280,
                            contentionCount: 3,
                            lastContentionAt: Date().timeIntervalSince1970 - 1,
                            updatedAt: Date().timeIntervalSince1970
                        )
                    ]
                ),
                lastErrors: [
                    AIRuntimeMonitorLastError(
                        provider: "mlx",
                        code: "import_error",
                        message: "missing mlx",
                        severity: "error",
                        updatedAt: Date().timeIntervalSince1970
                    )
                ],
                fallbackCounters: AIRuntimeMonitorFallbackCounters(
                    providerCount: 1,
                    fallbackReadyProviderCount: 1,
                    fallbackOnlyProviderCount: 0,
                    fallbackReadyTaskCount: 1,
                    fallbackOnlyTaskCount: 0,
                    taskKindCounts: ["speech_to_text": 1]
                )
            )
        )

        let summary = status.runtimeMonitorOperatorSummary(ttl: 30)

        XCTAssertTrue(summary.contains("runtime_alive=1"))
        XCTAssertTrue(summary.contains("status_schema_version=xhub.local_runtime_status.v2"))
        XCTAssertTrue(summary.contains("monitor_schema_version=xhub.local_runtime_monitor.v1"))
        XCTAssertTrue(summary.contains("monitor_provider_count=1"))
        XCTAssertTrue(summary.contains("monitor_active_task_count=1"))
        XCTAssertTrue(summary.contains("monitor_queued_task_count=2"))
        XCTAssertTrue(summary.contains("monitor_loaded_instance_count=1"))
        XCTAssertTrue(summary.contains("monitor_fallback_ready_provider_count=1"))
        XCTAssertTrue(summary.contains("monitor_last_error_count=1"))
        XCTAssertTrue(summary.contains("monitor_recent_bench_result_count=1"))
        XCTAssertTrue(summary.contains("provider=transformers ok=1 reason=fallback_ready"))
        XCTAssertTrue(summary.contains("real_tasks=embedding"))
        XCTAssertTrue(summary.contains("fallback_tasks=speech_to_text"))
        XCTAssertTrue(summary.contains("unavailable_tasks=vision_caption"))
        XCTAssertTrue(summary.contains("memory=active=2048 peak=4096"))
        XCTAssertTrue(summary.contains("provider=transformers task_kind=embedding model_id=bge-small request_id=req-a device_id=terminal-a instance_key=transformers:bge-small:ctx8192"))
        XCTAssertTrue(summary.contains("provider=transformers task_kind=vision_understand model_id=glm4v-local execution_path=real_runtime"))
        XCTAssertTrue(summary.contains("provider=mlx severity=error code=import_error message=missing mlx"))
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
        XCTAssertTrue(doctor.contains("本地运行时部分就绪：transformers 已就绪；mlx unavailable (import_error)。"))
        XCTAssertTrue(doctor.contains("文本生成当前不可用"))
        XCTAssertTrue(doctor.contains("向量能力当前可通过 transformers 使用。"))
        XCTAssertTrue(doctor.contains("本地音频能力被 ai.audio.local 阻止。"))
    }

    func testProviderAwareAIRuntimeStatusDoctorTextIncludesRecentBenchRouteEvidence() {
        let status = AIRuntimeStatus(
            pid: 791,
            updatedAt: Date().timeIntervalSince1970,
            mlxOk: false,
            runtimeVersion: "entry-v2",
            schemaVersion: "xhub.local_runtime_status.v2",
            providers: [
                "transformers": AIRuntimeProviderStatus(
                    provider: "transformers",
                    ok: true,
                    reasonCode: "ready",
                    runtimeVersion: "entry-v2",
                    availableTaskKinds: ["text_generate", "vision_understand"],
                    loadedModels: ["glm4v-local"],
                    deviceBackend: "mps",
                    updatedAt: Date().timeIntervalSince1970,
                    loadedModelCount: 1
                ),
            ],
            monitorSnapshot: AIRuntimeMonitorSnapshot(
                schemaVersion: "xhub.local_runtime_monitor.v1",
                updatedAt: Date().timeIntervalSince1970,
                recentBenchResults: [
                    ModelBenchResult(
                        modelId: "glm4v-local",
                        providerID: "transformers",
                        taskKind: "vision_understand",
                        loadProfileHash: "vision8192",
                        fixtureProfile: "vision_smoke",
                        measuredAt: Date().timeIntervalSince1970 - 1,
                        ok: true,
                        reasonCode: "ready",
                        routeTraceSummary: AIRuntimeRouteTraceSummary(
                            requestMode: "chat_completions",
                            selectedTaskKind: "vision_understand",
                            imageCount: 1,
                            resolvedImageCount: 1,
                            executionPath: "real_runtime"
                        )
                    )
                ]
            )
        )

        let doctor = status.providerDoctorText(ttl: 30)

        XCTAssertTrue(doctor.contains("最近一次快速评审路由显示，transformers 执行了 vision_understand，模型为 glm4v-local，执行路径为 real_runtime，并携带了 1 张图片。"))
    }

    func testProviderAwareAIRuntimeStatusDoctorTextSurfacesManagedServiceLaunchFailure() {
        let status = AIRuntimeStatus(
            pid: 792,
            updatedAt: Date().timeIntervalSince1970,
            mlxOk: false,
            runtimeVersion: "entry-v2",
            schemaVersion: "xhub.local_runtime_status.v2",
            providers: [
                "transformers": AIRuntimeProviderStatus(
                    provider: "transformers",
                    ok: false,
                    reasonCode: "runtime_missing",
                    runtimeVersion: "entry-v2",
                    runtimeSource: "xhub_local_service",
                    runtimeSourcePath: "http://127.0.0.1:50171",
                    runtimeResolutionState: "runtime_missing",
                    runtimeReasonCode: "xhub_local_service_unreachable",
                    fallbackUsed: false,
                    availableTaskKinds: [],
                    loadedModels: [],
                    deviceBackend: "service_proxy",
                    updatedAt: Date().timeIntervalSince1970,
                    managedServiceState: AIRuntimeManagedServiceState(
                        baseURL: "http://127.0.0.1:50171",
                        bindHost: "127.0.0.1",
                        bindPort: 50171,
                        pid: 43001,
                        processState: "launch_failed",
                        lastProbeAtMs: 1_741_800_001_000,
                        lastLaunchAttemptAtMs: 1_741_800_000_000,
                        startAttemptCount: 2,
                        lastStartError: "health_timeout:http://127.0.0.1:50171",
                        updatedAtMs: 1_741_800_001_000
                    )
                ),
            ]
        )

        let doctor = status.providerDoctorText(ttl: 30)

        XCTAssertTrue(doctor.contains("当前没有可用的本地 provider："))
        XCTAssertTrue(doctor.contains("transformers unavailable (xhub_local_service_unreachable; managed_service=launch_failed; attempts=2; last_start_error=health_timeout:http://127.0.0.1:50171)"))
    }

    func testModelBenchLegacyDecodeMapsToLegacyTextBench() throws {
        let json = """
        {
          "modelId": "mlx-qwen",
          "measuredAt": 1741800000,
          "promptTokens": 256,
          "generationTokens": 256,
          "promptTPS": 512.0,
          "generationTPS": 24.5,
          "peakMemoryBytes": 4294967296,
          "runtimeVersion": "legacy-runtime"
        }
        """

        let result = try JSONDecoder().decode(ModelBenchResult.self, from: Data(json.utf8))
        XCTAssertEqual(result.modelId, "mlx-qwen")
        XCTAssertEqual(result.taskKind, "text_generate")
        XCTAssertEqual(result.fixtureProfile, "legacy_mlx_text_default")
        XCTAssertEqual(result.resultKind, ModelBenchResult.legacyTextBenchKind)
        XCTAssertEqual(result.reasonCode, ModelBenchResult.legacyTextBenchKind)
        XCTAssertEqual(result.verdict, "Balanced")
        XCTAssertEqual(result.throughputUnit, "tokens_per_sec")
        XCTAssertEqual(result.throughputValue, 24.5)
        XCTAssertTrue(result.isLegacyTextBench)
    }

    func testModelBenchTaskAwareDecodePreservesCompositeKeyFields() throws {
        let json = """
        {
          "schemaVersion": "xhub.models_bench.v2",
          "results": [
            {
              "resultID": "hf-embed::embedding::ctx8192::embed_small_docs",
              "modelId": "hf-embed",
              "providerID": "transformers",
              "taskKind": "embedding",
              "loadProfileHash": "ctx8192",
              "fixtureProfile": "embed_small_docs",
              "fixtureTitle": "Small Document Batch",
              "measuredAt": 1741800001,
              "resultKind": "task_aware_quick_bench",
              "ok": true,
              "reasonCode": "ready",
              "runtimeSource": "user_python_venv",
              "runtimeSourcePath": "/Users/test/project/.venv/bin/python3",
              "runtimeResolutionState": "user_runtime_fallback",
              "runtimeReasonCode": "ready",
              "fallbackUsed": true,
              "runtimeHint": "transformers is running from user Python /Users/test/project/.venv/bin/python3.",
              "runtimeMissingRequirements": [],
              "runtimeMissingOptionalRequirements": ["python_module:pil"],
              "verdict": "Balanced",
              "fallbackMode": "",
              "coldStartMs": 400,
              "latencyMs": 92,
              "peakMemoryBytes": 1048576,
              "throughputValue": 32.5,
              "throughputUnit": "items_per_sec",
              "effectiveContextLength": 8192,
              "notes": ["dims=384", "text_count=3"]
            }
          ],
          "updatedAt": 1741800002
        }
        """

        let snapshot = try JSONDecoder().decode(ModelsBenchSnapshot.self, from: Data(json.utf8))
        XCTAssertEqual(snapshot.schemaVersion, "xhub.models_bench.v2")
        XCTAssertEqual(snapshot.results.count, 1)
        XCTAssertEqual(snapshot.results.first?.id, "hf-embed::embedding::ctx8192::embed_small_docs")
        XCTAssertEqual(snapshot.results.first?.providerID, "transformers")
        XCTAssertEqual(snapshot.results.first?.taskKind, "embedding")
        XCTAssertEqual(snapshot.results.first?.fixtureProfile, "embed_small_docs")
        XCTAssertEqual(snapshot.results.first?.effectiveContextLength, 8192)
        XCTAssertEqual(snapshot.results.first?.throughputUnit, "items_per_sec")
        XCTAssertEqual(snapshot.results.first?.runtimeSource, "user_python_venv")
        XCTAssertEqual(snapshot.results.first?.runtimeSourcePath, "/Users/test/project/.venv/bin/python3")
        XCTAssertEqual(snapshot.results.first?.runtimeResolutionState, "user_runtime_fallback")
        XCTAssertEqual(snapshot.results.first?.runtimeReasonCode, "ready")
        XCTAssertEqual(snapshot.results.first?.fallbackUsed, true)
        XCTAssertEqual(snapshot.results.first?.runtimeMissingOptionalRequirements, ["python_module:pil"])
    }
}
