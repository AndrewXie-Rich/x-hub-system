import XCTest
@testable import RELFlowHub
@testable import RELFlowHubCore

final class LocalModelRuntimeRequestContextTests: XCTestCase {
    func testCanonicalLoadProfileHashMatchesPythonRuntime() {
        let profile = LocalModelLoadProfile(
            contextLength: 32768,
            ropeFrequencyScale: 2.0
        )

        XCTAssertEqual(
            LocalModelRuntimeRequestContextResolver.canonicalLoadProfileJSONString(profile),
            #"{"context_length":32768,"rope_frequency_scale":2.0}"#
        )
        XCTAssertEqual(
            LocalModelRuntimeRequestContextResolver.canonicalLoadProfileHash(profile),
            "d09cfff434f0b21528d470aa64464d8d22107ef7c748a38f41079713648010cb"
        )
    }

    func testCanonicalLoadProfileHashIncludesTypedLoadConfigFields() {
        let profile = LocalModelLoadProfile(
            contextLength: 16384,
            gpuOffloadRatio: 0.5,
            ttl: 900,
            parallel: 2,
            identifier: "glm4v-slot",
            vision: LocalModelVisionLoadProfile(imageMaxDimension: 4096)
        )

        XCTAssertEqual(
            LocalModelRuntimeRequestContextResolver.canonicalLoadProfileJSONString(profile),
            #"{"context_length":16384,"gpu_offload_ratio":0.5,"identifier":"glm4v-slot","parallel":2,"ttl":900,"vision":{"image_max_dimension":4096}}"#
        )
        XCTAssertEqual(
            LocalModelRuntimeRequestContextResolver.canonicalLoadProfileHash(profile),
            "7e3b36290344460a4d819a7fd7f0d6b7c480a7f8f0ba6fe082392521c4704ddf"
        )
    }

    func testResolverPrefersLoadedInstanceMatchingTerminalDeviceProfile() {
        let model = HubModel(
            id: "glm-local",
            name: "GLM Local",
            backend: "transformers",
            quant: "int4",
            contextLength: 8192,
            maxContextLength: 131072,
            paramsB: 9.0,
            state: .available,
            modelPath: "/tmp/models/glm-local",
            defaultLoadProfile: LocalModelLoadProfile(contextLength: 8192),
            taskKinds: ["embedding"]
        )
        let preferredProfile = LocalModelLoadProfile(
            contextLength: 32768,
            ropeFrequencyScale: 2.0
        )
        let preferredHash = LocalModelRuntimeRequestContextResolver.canonicalLoadProfileHash(preferredProfile)
        let runtimeStatus = AIRuntimeStatus(
            pid: 321,
            updatedAt: Date().timeIntervalSince1970,
            mlxOk: false,
            providers: [
                "transformers": AIRuntimeProviderStatus(
                    provider: "transformers",
                    ok: true,
                    reasonCode: "ready",
                    runtimeVersion: "v2",
                    availableTaskKinds: ["embedding"],
                    loadedModels: ["glm-local"],
                    deviceBackend: "mps",
                    updatedAt: Date().timeIntervalSince1970,
                    lifecycleMode: "warmable",
                    supportedLifecycleActions: ["warmup_local_model", "unload_local_model"],
                    warmupTaskKinds: ["embedding"],
                    residencyScope: "runtime_process",
                    loadedInstances: [
                        AIRuntimeLoadedInstance(
                            instanceKey: "transformers:glm-local:other-hash",
                            modelId: "glm-local",
                            taskKinds: ["embedding"],
                            loadProfileHash: "other-hash",
                            effectiveContextLength: 8192,
                            loadedAt: 100,
                            lastUsedAt: 200,
                            residency: "resident",
                            residencyScope: "runtime_process",
                            deviceBackend: "mps"
                        ),
                        AIRuntimeLoadedInstance(
                            instanceKey: "transformers:glm-local:\(preferredHash)",
                            modelId: "glm-local",
                            taskKinds: ["embedding"],
                            loadProfileHash: preferredHash,
                            effectiveContextLength: 32768,
                            loadedAt: 150,
                            lastUsedAt: 190,
                            residency: "resident",
                            residencyScope: "runtime_process",
                            deviceBackend: "mps"
                        ),
                    ]
                ),
            ]
        )
        let pairedProfiles = HubPairedTerminalLocalModelProfilesSnapshot(
            profiles: [
                HubPairedTerminalLocalModelProfile(
                    deviceId: "terminal_device",
                    modelId: "glm-local",
                    overrideProfile: LocalModelLoadProfileOverride(
                        contextLength: 32768,
                        ropeFrequencyScale: 2.0
                    )
                ),
            ]
        )

        let resolved = LocalModelRuntimeRequestContextResolver.resolve(
            model: model,
            runtimeStatus: runtimeStatus,
            pairedProfilesSnapshot: pairedProfiles
        )

        XCTAssertEqual(resolved.deviceID, "terminal_device")
        XCTAssertEqual(resolved.instanceKey, "transformers:glm-local:\(preferredHash)")
        XCTAssertEqual(resolved.loadProfileHash, preferredHash)
        XCTAssertEqual(resolved.predictedLoadProfileHash, preferredHash)
        XCTAssertEqual(resolved.effectiveContextLength, 32768)
        XCTAssertEqual(resolved.effectiveLoadProfile, preferredProfile)
        XCTAssertEqual(resolved.source, "loaded_instance_preferred_profile")
    }

    func testResolverKeepsPredictedHashLocalUntilRuntimeReturnsActualIdentity() {
        let model = HubModel(
            id: "hf-embed",
            name: "HF Embed",
            backend: "transformers",
            quant: "fp16",
            contextLength: 16384,
            maxContextLength: 65536,
            paramsB: 0.4,
            state: .available,
            modelPath: "/tmp/models/hf-embed",
            defaultLoadProfile: LocalModelLoadProfile(
                contextLength: 16384,
                gpuOffloadRatio: 0.75,
                evalBatchSize: 8
            ),
            taskKinds: ["embedding"]
        )
        let pairedProfiles = HubPairedTerminalLocalModelProfilesSnapshot(
            profiles: [
                HubPairedTerminalLocalModelProfile(
                    deviceId: "terminal_device",
                    modelId: "hf-embed",
                    overrideProfile: LocalModelLoadProfileOverride(
                        contextLength: 32768
                    )
                ),
            ]
        )

        let resolved = LocalModelRuntimeRequestContextResolver.resolve(
            model: model,
            runtimeStatus: nil,
            pairedProfilesSnapshot: pairedProfiles
        )
        let payload = resolved.applying(to: [
            "provider": "transformers",
            "model_id": "hf-embed",
        ])

        XCTAssertEqual(resolved.deviceID, "terminal_device")
        XCTAssertEqual(resolved.instanceKey, "")
        XCTAssertEqual(resolved.loadProfileHash, "")
        XCTAssertFalse(resolved.preferredBenchHash.isEmpty)
        XCTAssertEqual(resolved.effectiveContextLength, 32768)
        XCTAssertEqual(
            resolved.effectiveLoadProfile,
            LocalModelLoadProfile(
                contextLength: 32768,
                gpuOffloadRatio: 0.75,
                evalBatchSize: 8
            )
        )
        XCTAssertEqual(resolved.source, "paired_terminal_default")
        XCTAssertEqual(payload["device_id"] as? String, "terminal_device")
        XCTAssertEqual(payload["effective_context_length"] as? Int, 32768)
        XCTAssertEqual(payload["current_context_length"] as? Int, 32768)
        XCTAssertNil(payload["load_profile_hash"])
        XCTAssertNil(payload["load_config_hash"])
        XCTAssertNil(payload["instance_key"])
        XCTAssertEqual(
            (payload["load_profile_override"] as? [String: Any])?["context_length"] as? Int,
            32768
        )

        let benchResult = ModelBenchResult(
            modelId: "hf-embed",
            providerID: "transformers",
            taskKind: "embedding",
            loadProfileHash: resolved.preferredBenchHash,
            fixtureProfile: "embed_small_docs",
            ok: true,
            effectiveContextLength: 32768
        )
        XCTAssertTrue(resolved.matchesBenchResult(benchResult))
    }

    func testRequestPayloadCarriesTypedLoadConfigOverrideFields() {
        let context = LocalModelRuntimeRequestContext(
            providerID: "transformers",
            modelID: "glm4v-local",
            deviceID: "terminal_device",
            instanceKey: "",
            loadProfileHash: "",
            predictedLoadProfileHash: "predicted-hash",
            effectiveContextLength: 8192,
            loadProfileOverride: LocalModelLoadProfileOverride(
                contextLength: 8192,
                ttl: 600,
                parallel: 3,
                identifier: "glm4v-a",
                vision: LocalModelVisionLoadProfile(imageMaxDimension: 2048)
            ),
            source: "paired_terminal_default"
        )

        let payload = context.applying(to: ["provider": "transformers"])
        let overridePayload = payload["load_profile_override"] as? [String: Any]
        let visionPayload = overridePayload?["vision"] as? [String: Any]

        XCTAssertEqual(payload["current_context_length"] as? Int, 8192)
        XCTAssertNil(payload["load_config_hash"])
        XCTAssertEqual(overridePayload?["ttl"] as? Int, 600)
        XCTAssertEqual(overridePayload?["parallel"] as? Int, 3)
        XCTAssertEqual(overridePayload?["identifier"] as? String, "glm4v-a")
        XCTAssertEqual(visionPayload?["image_max_dimension"] as? Int, 2048)
    }

    func testResolverHonorsExplicitPairedDevicePreferenceOverAutoTarget() {
        let model = HubModel(
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
            taskKinds: ["embedding"]
        )
        let pairedProfiles = HubPairedTerminalLocalModelProfilesSnapshot(
            profiles: [
                HubPairedTerminalLocalModelProfile(
                    deviceId: "terminal_device",
                    modelId: "hf-embed",
                    overrideProfile: LocalModelLoadProfileOverride(contextLength: 32768)
                ),
                HubPairedTerminalLocalModelProfile(
                    deviceId: "studio-mac",
                    modelId: "hf-embed",
                    overrideProfile: LocalModelLoadProfileOverride(contextLength: 16384)
                ),
            ]
        )
        let terminalHash = LocalModelRuntimeRequestContextResolver.canonicalLoadProfileHash(
            LocalModelLoadProfile(contextLength: 32768)
        )
        let runtimeStatus = AIRuntimeStatus(
            pid: 321,
            updatedAt: Date().timeIntervalSince1970,
            mlxOk: false,
            providers: [
                "transformers": AIRuntimeProviderStatus(
                    provider: "transformers",
                    ok: true,
                    reasonCode: "ready",
                    runtimeVersion: "v2",
                    availableTaskKinds: ["embedding"],
                    loadedModels: ["hf-embed"],
                    deviceBackend: "mps",
                    updatedAt: Date().timeIntervalSince1970,
                    lifecycleMode: "warmable",
                    supportedLifecycleActions: ["warmup_local_model", "unload_local_model", "evict_local_instance"],
                    warmupTaskKinds: ["embedding"],
                    residencyScope: "runtime_process",
                    loadedInstances: [
                        AIRuntimeLoadedInstance(
                            instanceKey: "transformers:hf-embed:\(terminalHash)",
                            modelId: "hf-embed",
                            taskKinds: ["embedding"],
                            loadProfileHash: terminalHash,
                            effectiveContextLength: 32768,
                            loadedAt: 100,
                            lastUsedAt: 100,
                            residency: "resident",
                            residencyScope: "runtime_process",
                            deviceBackend: "mps"
                        ),
                    ]
                ),
            ]
        )

        let resolved = LocalModelRuntimeRequestContextResolver.resolve(
            model: model,
            runtimeStatus: runtimeStatus,
            pairedProfilesSnapshot: pairedProfiles,
            targetPreference: LocalModelRuntimeTargetPreference(
                modelId: "hf-embed",
                targetKind: .pairedDevice,
                deviceId: "studio-mac"
            )
        )

        XCTAssertEqual(resolved.deviceID, "studio-mac")
        XCTAssertEqual(resolved.instanceKey, "")
        XCTAssertEqual(resolved.effectiveContextLength, 16384)
        XCTAssertEqual(resolved.source, "selected_paired_device")
    }

    func testResolverHonorsExplicitLoadedInstancePreferenceOverPairedProfile() {
        let model = HubModel(
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
            taskKinds: ["embedding"]
        )
        let pairedProfiles = HubPairedTerminalLocalModelProfilesSnapshot(
            profiles: [
                HubPairedTerminalLocalModelProfile(
                    deviceId: "terminal_device",
                    modelId: "hf-embed",
                    overrideProfile: LocalModelLoadProfileOverride(contextLength: 32768)
                ),
            ]
        )
        let preferredHash = LocalModelRuntimeRequestContextResolver.canonicalLoadProfileHash(
            LocalModelLoadProfile(contextLength: 32768)
        )
        let otherHash = LocalModelRuntimeRequestContextResolver.canonicalLoadProfileHash(
            LocalModelLoadProfile(contextLength: 12288)
        )
        let runtimeStatus = AIRuntimeStatus(
            pid: 321,
            updatedAt: Date().timeIntervalSince1970,
            mlxOk: false,
            providers: [
                "transformers": AIRuntimeProviderStatus(
                    provider: "transformers",
                    ok: true,
                    reasonCode: "ready",
                    runtimeVersion: "v2",
                    availableTaskKinds: ["embedding"],
                    loadedModels: ["hf-embed"],
                    deviceBackend: "mps",
                    updatedAt: Date().timeIntervalSince1970,
                    lifecycleMode: "warmable",
                    supportedLifecycleActions: ["warmup_local_model", "unload_local_model", "evict_local_instance"],
                    warmupTaskKinds: ["embedding"],
                    residencyScope: "runtime_process",
                    loadedInstances: [
                        AIRuntimeLoadedInstance(
                            instanceKey: "transformers:hf-embed:\(preferredHash)",
                            modelId: "hf-embed",
                            taskKinds: ["embedding"],
                            loadProfileHash: preferredHash,
                            effectiveContextLength: 32768,
                            loadedAt: 100,
                            lastUsedAt: 100,
                            residency: "resident",
                            residencyScope: "runtime_process",
                            deviceBackend: "mps"
                        ),
                        AIRuntimeLoadedInstance(
                            instanceKey: "transformers:hf-embed:\(otherHash)",
                            modelId: "hf-embed",
                            taskKinds: ["embedding"],
                            loadProfileHash: otherHash,
                            effectiveContextLength: 12288,
                            loadedAt: 200,
                            lastUsedAt: 200,
                            residency: "resident",
                            residencyScope: "runtime_process",
                            deviceBackend: "mps"
                        ),
                    ]
                ),
            ]
        )

        let resolved = LocalModelRuntimeRequestContextResolver.resolve(
            model: model,
            runtimeStatus: runtimeStatus,
            pairedProfilesSnapshot: pairedProfiles,
            targetPreference: LocalModelRuntimeTargetPreference(
                modelId: "hf-embed",
                targetKind: .loadedInstance,
                instanceKey: "transformers:hf-embed:\(otherHash)"
            )
        )

        XCTAssertEqual(resolved.deviceID, "")
        XCTAssertEqual(resolved.instanceKey, "transformers:hf-embed:\(otherHash)")
        XCTAssertEqual(resolved.loadProfileHash, otherHash)
        XCTAssertEqual(resolved.effectiveContextLength, 12288)
        XCTAssertEqual(
            resolved.effectiveLoadProfile,
            LocalModelLoadProfile(contextLength: 12288)
        )
        XCTAssertEqual(resolved.source, "selected_loaded_instance")
    }

    func testRequestContextSummariesStayReadableForUIAndBenchSheets() {
        let context = LocalModelRuntimeRequestContext(
            providerID: "transformers",
            modelID: "hf-embed",
            deviceID: "terminal_device",
            instanceKey: "transformers:hf-embed:abcd1234deadbeef",
            loadProfileHash: "abcd1234deadbeef",
            predictedLoadProfileHash: "abcd1234deadbeef",
            effectiveContextLength: 32768,
            loadProfileOverride: LocalModelLoadProfileOverride(contextLength: 32768),
            effectiveLoadProfile: LocalModelLoadProfile(
                contextLength: 32768,
                ttl: 600,
                parallel: 2,
                identifier: "vision-a",
                vision: LocalModelVisionLoadProfile(imageMaxDimension: 2048)
            ),
            source: "loaded_instance_preferred_profile"
        )

        XCTAssertEqual(context.uiLoadProfileSummary, "ctx 32768 · ttl 600s · par 2 · img 2048")
        XCTAssertEqual(context.technicalLoadProfileSummary, "ctx=32768 · ttl=600s · par=2 · id=vision-a · img=2048")
        XCTAssertEqual(context.uiSummary, "Target: terminal_device · ctx 32768 · ttl 600s · par 2 · img 2048 · resident")
        XCTAssertEqual(
            context.technicalSummary,
            "配对目标 · device=terminal_device · ctx=32768 · ttl=600s · par=2 · id=vision-a · img=2048 · hash=abcd1234 · instance=abcd1234"
        )
    }
}
