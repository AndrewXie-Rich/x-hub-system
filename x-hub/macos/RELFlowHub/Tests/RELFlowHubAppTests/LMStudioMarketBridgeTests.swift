import XCTest
@testable import RELFlowHub
@testable import RELFlowHubCore

final class LMStudioMarketBridgeTests: XCTestCase {
    func testParseSearchResultsHandlesStaffPicksOutput() {
        let output = """
        \u{001B}[34m?\u{001B}[39m \u{001B}[1mSelect a model to download\u{001B}[22m \u{001B}[36m\u{001B}[39m

        \u{001B}[36m❯ liquid/lfm2-24b-a2b — LFM2 is a family of hybrid models designed for \u{001B}[39m
        \u{001B}[36mon-devic...\u{001B}[39m
          zai-org/glm-4.6v-flash — GLM 4.6V Flash is a 9B vision-language model
        optimized ...
          qwen/qwen3-coder-next — Qwen Coder Next is an 80B MoE with 3B active
        parameters...
        """

        let results = LMStudioMarketBridge.parseSearchResultsFromTerminalOutput(output)

        XCTAssertGreaterThanOrEqual(results.count, 3)
        XCTAssertEqual(results.map(\.modelKey), [
            "liquid/lfm2-24b-a2b",
            "zai-org/glm-4.6v-flash",
            "qwen/qwen3-coder-next",
        ])
        XCTAssertEqual(results[safe: 1]?.capabilityTags, ["Vision"])
        XCTAssertEqual(results[safe: 2]?.capabilityTags, ["Coding"])
    }

    func testDecodeSDKSearchResultsPreservesRecommendationMetadata() throws {
        let output = """
        {
          "results": [
            {
              "modelKey": "zai-org/glm-4.6v-flash",
              "title": "GLM 4.6V Flash",
              "summary": "",
              "formatHint": "mlx",
              "capabilityTags": ["Vision"],
              "staffPick": true,
              "recommendationReason": "Best vision starter for this Mac",
              "recommendedForThisMac": true,
              "recommendedFitEstimation": "fullGPUOffload",
              "recommendedSizeBytes": 4831838208,
              "downloadIdentifier": "catalog::glm-4.6v-flash::mlx"
            }
          ]
        }
        """

        let results = try LMStudioMarketBridge.decodeSDKSearchResults(from: output)

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].modelKey, "zai-org/glm-4.6v-flash")
        XCTAssertEqual(results[0].formatHint, "mlx")
        XCTAssertEqual(results[0].capabilityTags, ["Vision"])
        XCTAssertTrue(results[0].staffPick)
        XCTAssertEqual(results[0].recommendationReason, "Best vision starter for this Mac")
        XCTAssertTrue(results[0].recommendedForThisMac)
        XCTAssertEqual(results[0].recommendedFitEstimation, "fullGPUOffload")
        XCTAssertEqual(results[0].recommendedSizeBytes, 4_831_838_208)
        XCTAssertEqual(results[0].downloadIdentifier, "catalog::glm-4.6v-flash::mlx")
    }

    func testHelperFailureDetailPrefersStructuredErrorMessage() {
        let output = """
        {"type":"status","message":"Loading Hub market models..."}
        {"type":"error","message":"Hub 在请求超时前无法连接到 huggingface.co。请检查网络权限、代理设置，或按需设置 HF_ENDPOINT/XHUB_HF_BASE_URL。"}
        """

        let detail = LMStudioMarketBridge.helperFailureDetail(
            from: output,
            timedOut: false,
            terminationStatus: 1
        )

        XCTAssertEqual(detail, "Hub 在请求超时前无法连接到 huggingface.co。请检查网络权限、代理设置，或按需设置 HF_ENDPOINT/XHUB_HF_BASE_URL。")
    }

    func testHelperFailureDetailFallsBackToTimeoutReason() {
        let detail = LMStudioMarketBridge.helperFailureDetail(
            from: "",
            timedOut: true,
            terminationStatus: 15
        )

        XCTAssertEqual(detail, "助手进程未能在预期时间内完成。")
    }

    func testMarketBridgeErrorsStayUserFacing() {
        XCTAssertEqual(
            LMStudioMarketBridgeError.helperBinaryMissing.errorDescription,
            "本地模型助手未安装，Hub 找不到本地模型 Bridge。"
        )
        XCTAssertEqual(
            LMStudioMarketBridgeError.searchFailed("").errorDescription,
            "模型发现失败。"
        )
        XCTAssertEqual(
            LMStudioMarketBridgeError.downloadFailed("disk full").errorDescription,
            "模型下载失败。disk full"
        )
    }

    func testResolvedHuggingFaceBaseURLsPreferStoredMirrorBeforeDirectHost() {
        let urls = LMStudioMarketBridge.resolvedHuggingFaceBaseURLStrings(
            preferred: "",
            configured: "",
            stored: "https://hf-mirror.com/"
        )

        XCTAssertEqual(urls, [
            "https://hf-mirror.com",
            "https://huggingface.co",
        ])
    }

    func testPersistedHuggingFaceBaseURLRoundTrips() throws {
        let baseDir = try makeTempDir()

        XCTAssertEqual(
            LMStudioMarketBridge.persistStoredHuggingFaceBaseURLString(
                "https://hf-mirror.com/",
                baseDir: baseDir
            ),
            "https://hf-mirror.com"
        )
        XCTAssertEqual(
            LMStudioMarketBridge.storedHuggingFaceBaseURLString(baseDir: baseDir),
            "https://hf-mirror.com"
        )

        XCTAssertEqual(
            LMStudioMarketBridge.persistStoredHuggingFaceBaseURLString(
                "",
                baseDir: baseDir
            ),
            ""
        )
        XCTAssertEqual(
            LMStudioMarketBridge.storedHuggingFaceBaseURLString(baseDir: baseDir),
            ""
        )
    }

    func testExpandedSearchTermsRecognizeCapabilityAliases() {
        XCTAssertEqual(
            LMStudioMarketBridge.expandedSearchTerms(for: "Vision", category: ""),
            ["Vision", "vl", "llava", "glm-4.6v", "qwen2-vl", "qwen3-vl", "florence", "ocr", "image"]
        )
        XCTAssertEqual(
            LMStudioMarketBridge.expandedSearchTerms(for: "coding", category: ""),
            ["coding", "coder", "code", "qwen-coder", "deepseek-coder"]
        )
        XCTAssertEqual(
            LMStudioMarketBridge.expandedSearchTerms(for: "", category: "audio"),
            ["speech", "audio", "asr", "whisper"]
        )
        XCTAssertEqual(
            LMStudioMarketBridge.expandedSearchTerms(for: "voice", category: ""),
            ["voice", "tts", "text-to-speech", "kokoro", "melo", "parler", "bark", "speecht5", "f5-tts", "cosyvoice"]
        )
    }

    func testCategoryTagFilterRecognizesAliases() {
        XCTAssertEqual(
            LMStudioMarketBridge.categoryTagFilter(for: "multimodal", category: ""),
            Set(["Vision", "OCR"])
        )
        XCTAssertEqual(
            LMStudioMarketBridge.categoryTagFilter(for: "retrieval", category: ""),
            Set(["Embedding"])
        )
        XCTAssertEqual(
            LMStudioMarketBridge.categoryTagFilter(for: "", category: "code"),
            Set(["Coding"])
        )
        XCTAssertEqual(
            LMStudioMarketBridge.categoryTagFilter(for: "tts", category: ""),
            Set(["Voice"])
        )
    }

    func testCuratedRecommendedResultsBalancePrimaryHubCapabilities() {
        let results = [
            makeMarketResult(
                modelKey: "mlx-community/qwen3-4b-instruct-4bit",
                title: "Qwen3 4B Instruct",
                capabilityTags: ["Text"],
                formatHint: "mlx",
                recommendedFitEstimation: "fullGPUOffload",
                recommendedSizeBytes: 3_800_000_000
            ),
            makeMarketResult(
                modelKey: "mlx-community/qwen3-coder-4b-4bit",
                title: "Qwen3 Coder 4B",
                capabilityTags: ["Coding"],
                formatHint: "mlx",
                recommendedFitEstimation: "fullGPUOffload",
                recommendedSizeBytes: 4_100_000_000
            ),
            makeMarketResult(
                modelKey: "mlx-community/qwen3-embedding-0.6b-4bit-dwq",
                title: "Qwen3 Embedding 0.6B",
                capabilityTags: ["Embedding"],
                formatHint: "mlx",
                recommendedFitEstimation: "fullGPUOffload",
                recommendedSizeBytes: 900_000_000
            ),
            makeMarketResult(
                modelKey: "zai-org/glm-4.6v-flash",
                title: "GLM 4.6V Flash",
                capabilityTags: ["Vision"],
                formatHint: "transformers",
                recommendedFitEstimation: "fitWithoutGPU",
                recommendedSizeBytes: 8_400_000_000
            )
        ]

        let curated = LMStudioMarketBridge.curatedRecommendedResults(from: results, limit: 3)

        XCTAssertEqual(curated.count, 3)
        XCTAssertTrue(curated.contains(where: { $0.capabilityTags == ["Text"] }))
        XCTAssertTrue(curated.contains(where: { $0.capabilityTags == ["Coding"] }))
        XCTAssertTrue(curated.contains(where: { $0.capabilityTags == ["Embedding"] }))
        XCTAssertTrue(curated.allSatisfy(\.staffPick))
        XCTAssertTrue(curated.allSatisfy { !$0.recommendationReason.isEmpty })
        XCTAssertEqual(
            curated.first(where: { $0.capabilityTags == ["Embedding"] })?.recommendationReason,
            "Best embedding starter for local retrieval"
        )
    }

    func testCuratedRecommendedResultsCanIncludeVoiceModels() {
        let results = [
            makeMarketResult(
                modelKey: "hexgrad/kokoro-82m",
                title: "Kokoro 82M",
                capabilityTags: ["Voice"],
                formatHint: "transformers",
                recommendedFitEstimation: "fitWithoutGPU",
                recommendedSizeBytes: 1_200_000_000
            )
        ]

        let curated = LMStudioMarketBridge.curatedRecommendedResults(from: results, limit: 1)

        XCTAssertEqual(curated.count, 1)
        XCTAssertEqual(curated[0].capabilityTags, ["Voice"])
        XCTAssertEqual(
            curated[0].recommendationReason,
            "Best Supervisor voice starter that can stay CPU-friendly"
        )
    }

    func testCuratedRecommendedResultsPreferMacFitWithinCapability() {
        let results = [
            makeMarketResult(
                modelKey: "mlx-community/llama-3-8b-4bit",
                title: "Llama 3 8B",
                capabilityTags: ["Text"],
                formatHint: "mlx",
                recommendedFitEstimation: "willNotFit",
                recommendedSizeBytes: 22_000_000_000
            ),
            makeMarketResult(
                modelKey: "mlx-community/qwen3-4b-instruct-4bit",
                title: "Qwen3 4B Instruct",
                capabilityTags: ["Text"],
                formatHint: "mlx",
                recommendedFitEstimation: "fullGPUOffload",
                recommendedSizeBytes: 3_800_000_000
            )
        ]

        let curated = LMStudioMarketBridge.curatedRecommendedResults(from: results, limit: 1)

        XCTAssertEqual(curated.map(\.modelKey), ["mlx-community/qwen3-4b-instruct-4bit"])
        XCTAssertTrue(curated[0].staffPick)
        XCTAssertEqual(curated[0].recommendationReason, "Best everyday text starter for this Mac")
    }

    func testLoadDownloadedModelsParsesModelIndexCache() throws {
        let home = try makeTempDir()
        let baseDir = try makeTempDir()
        let cacheDirectory = home
            .appendingPathComponent(".lmstudio", isDirectory: true)
            .appendingPathComponent(".internal", isDirectory: true)
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        let payload = """
        {
          "models": [
            {
              "displayName": "GLM 4.6V Flash",
              "indexedModelIdentifier": "zai-org/GLM-4.6V-Flash-MLX-4bit/model.safetensors.index.json",
              "defaultIdentifier": "glm-4.6v-flash",
              "user": "zai-org",
              "model": "GLM-4.6V-Flash-MLX-4bit",
              "file": "model.safetensors.index.json",
              "format": "mlx",
              "quant": { "name": "4bit" },
              "domain": "vision",
              "contextLength": 32768,
              "concreteModelDirAbsolutePath": "/tmp/glm-4.6v-flash",
              "entryPoint": { "absPath": "/tmp/glm-4.6v-flash/model.safetensors.index.json" },
              "sourceDirectoryType": "downloaded"
            }
          ]
        }
        """
        let data = try XCTUnwrap(payload.data(using: .utf8))
        try data.write(
            to: cacheDirectory.appendingPathComponent("model-index-cache.json")
        )

        let models = LMStudioMarketBridge.loadDownloadedModels(homeDirectory: home, baseDir: baseDir)

        XCTAssertEqual(models.count, 1)
        XCTAssertEqual(models[0].displayName, "GLM 4.6V Flash")
        XCTAssertEqual(models[0].quantLabel, "4bit")
        XCTAssertEqual(models[0].domain, "vision")
        XCTAssertFalse(models[0].isBundled)
    }

    func testLoadDownloadedModelsRespectsLMStudioHomePointer() throws {
        let home = try makeTempDir()
        let baseDir = try makeTempDir()
        let redirectedHome = try makeTempDir()
        let cacheDirectory = redirectedHome
            .appendingPathComponent(".internal", isDirectory: true)
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        let pointerData = try XCTUnwrap(redirectedHome.path.data(using: .utf8))
        try pointerData.write(to: home.appendingPathComponent(".lmstudio-home-pointer"))
        let payload = """
        {
          "models": [
            {
              "displayName": "Qwen3 Embedding 0.6B DWQ",
              "indexedModelIdentifier": "mlx-community/Qwen3-Embedding-0.6B-4bit-DWQ",
              "defaultIdentifier": "qwen3-embedding-0.6b-dwq",
              "user": "mlx-community",
              "model": "Qwen3-Embedding-0.6B-4bit-DWQ",
              "file": "model.safetensors",
              "format": "safetensors",
              "quant": { "name": "4bit" },
              "domain": "embedding",
              "contextLength": 32768,
              "concreteModelDirAbsolutePath": "/tmp/qwen3-embedding",
              "entryPoint": { "absPath": "/tmp/qwen3-embedding/model.safetensors" },
              "sourceDirectoryType": "user"
            }
          ]
        }
        """
        let data = try XCTUnwrap(payload.data(using: .utf8))
        try data.write(
            to: cacheDirectory.appendingPathComponent("model-index-cache.json")
        )

        let models = LMStudioMarketBridge.loadDownloadedModels(homeDirectory: home, baseDir: baseDir)

        XCTAssertEqual(models.count, 1)
        XCTAssertEqual(models[0].displayName, "Qwen3 Embedding 0.6B DWQ")
        XCTAssertEqual(
            LMStudioMarketBridge.downloadedModelsDisplayPath(homeDirectory: home, baseDir: baseDir),
            baseDir
                .appendingPathComponent("models", isDirectory: true)
                .appendingPathComponent("_market", isDirectory: true).path
        )
    }

    func testLoadDownloadedModelsFallsBackToFilesystemScanWhenIndexIsMissing() throws {
        let home = try makeTempDir()
        let baseDir = try makeTempDir()
        let modelDirectory = home
            .appendingPathComponent(".lmstudio", isDirectory: true)
            .appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent("mlx-community", isDirectory: true)
            .appendingPathComponent("Qwen3-Embedding-0.6B-4bit-DWQ", isDirectory: true)
        try FileManager.default.createDirectory(at: modelDirectory, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: modelDirectory.appendingPathComponent("config.json"))
        try Data("{}".utf8).write(to: modelDirectory.appendingPathComponent("tokenizer.json"))
        try Data().write(to: modelDirectory.appendingPathComponent("model.safetensors"))

        let models = LMStudioMarketBridge.loadDownloadedModels(homeDirectory: home, baseDir: baseDir)

        XCTAssertEqual(models.count, 1)
        XCTAssertEqual(models[0].user, "mlx-community")
        XCTAssertEqual(models[0].model, "Qwen3-Embedding-0.6B-4bit-DWQ")
        XCTAssertEqual(
            URL(fileURLWithPath: models[0].directoryPath).standardizedFileURL.path,
            modelDirectory.standardizedFileURL.path
        )
        XCTAssertEqual(models[0].file, "model.safetensors")
    }

    func testLoadDownloadedModelsScansHubManagedMarketDirectory() throws {
        let home = try makeTempDir()
        let baseDir = try makeTempDir()
        let modelDirectory = baseDir
            .appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent("_market", isDirectory: true)
            .appendingPathComponent("mlx-community", isDirectory: true)
            .appendingPathComponent("Qwen3-Embedding-0.6B-4bit-DWQ", isDirectory: true)
        try FileManager.default.createDirectory(at: modelDirectory, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: modelDirectory.appendingPathComponent("config.json"))
        try Data("{}".utf8).write(to: modelDirectory.appendingPathComponent("tokenizer.json"))
        try Data().write(to: modelDirectory.appendingPathComponent("model.safetensors"))

        let models = LMStudioMarketBridge.loadDownloadedModels(homeDirectory: home, baseDir: baseDir)

        XCTAssertEqual(models.count, 1)
        XCTAssertEqual(models[0].sourceDirectoryType, "xhub_market")
        XCTAssertEqual(models[0].user, "mlx-community")
        XCTAssertEqual(models[0].model, "Qwen3-Embedding-0.6B-4bit-DWQ")
    }

    func testLoadDownloadedModelsScansHubManagedVoiceDirectory() throws {
        let home = try makeTempDir()
        let baseDir = try makeTempDir()
        let modelDirectory = baseDir
            .appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent("_market", isDirectory: true)
            .appendingPathComponent("hexgrad", isDirectory: true)
            .appendingPathComponent("Kokoro-82M-zh-warm", isDirectory: true)
        try FileManager.default.createDirectory(at: modelDirectory, withIntermediateDirectories: true)
        let config = """
        {
          "architectures": ["KokoroTTSModel"],
          "model_type": "kokoro_tts"
        }
        """
        try Data(config.utf8).write(to: modelDirectory.appendingPathComponent("config.json"))
        try Data("{}".utf8).write(to: modelDirectory.appendingPathComponent("tokenizer.json"))
        try Data().write(to: modelDirectory.appendingPathComponent("model.safetensors"))

        let models = LMStudioMarketBridge.loadDownloadedModels(homeDirectory: home, baseDir: baseDir)
        let entries = LMStudioMarketBridge.catalogEntries(from: models, helperBinaryPath: "")

        XCTAssertEqual(models.count, 1)
        XCTAssertEqual(models[0].sourceDirectoryType, "xhub_market")
        XCTAssertEqual(models[0].domain, "voice")
        XCTAssertEqual(models[0].model, "Kokoro-82M-zh-warm")
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].taskKinds, ["text_to_speech"])
        XCTAssertEqual(entries[0].note, "market_managed")
    }

    func testMarketKeyMatchesDownloadedVariant() {
        let descriptor = LMStudioDownloadedModelDescriptor(
            indexedModelIdentifier: "zai-org/GLM-4.6V-Flash-MLX-4bit/model.safetensors.index.json",
            displayName: "GLM 4.6V Flash",
            defaultIdentifier: "glm-4.6v-flash",
            user: "zai-org",
            model: "GLM-4.6V-Flash-MLX-4bit",
            file: "model.safetensors.index.json",
            format: "mlx",
            quantLabel: "4bit",
            domain: "vision",
            contextLength: 32768,
            directoryPath: "/tmp/glm-4.6v-flash",
            entryPointPath: "/tmp/glm-4.6v-flash/model.safetensors.index.json",
            sourceDirectoryType: "downloaded",
            paramsB: 9.0
        )

        XCTAssertTrue(descriptor.matchesMarketKey("zai-org/glm-4.6v-flash"))
        XCTAssertFalse(descriptor.matchesMarketKey("qwen/qwen3-coder-next"))
    }

    func testMarketKeyMatchesModelKeepsEmbeddingVariantsSeparate() {
        let model = HubModel(
            id: "qwen3-embedding-0.6b-4bit-dwq",
            name: "Qwen3 Embedding 0.6B 4bit DWQ",
            backend: "mlx",
            quant: "4bit",
            contextLength: 32768,
            paramsB: 0.6,
            state: .available,
            modelPath: "/tmp/RELFlowHub/models/_market/mlx-community/Qwen3-Embedding-0.6B-4bit-DWQ",
            note: "market_managed",
            modelFormat: "mlx",
            taskKinds: ["embedding"]
        )

        XCTAssertTrue(LMStudioMarketBridge.marketKeyMatchesModel("mlx-community/qwen3-embedding-0.6b-4bit-dwq", model: model))
        XCTAssertFalse(LMStudioMarketBridge.marketKeyMatchesModel("mlx-community/qwen3-embedding-8b-4bit-dwq", model: model))
        XCTAssertFalse(LMStudioMarketBridge.marketKeyMatchesModel("mlx-community/qwen3-vl-embedding-2b-4bit-dwq", model: model))
    }

    func testCatalogEntriesBuildManagedMLXImport() throws {
        let modelDirectory = try makeTempDir()
        try Data().write(to: modelDirectory.appendingPathComponent("weights.npz"))
        try Data("{}".utf8).write(to: modelDirectory.appendingPathComponent("tokenizer.json"))
        let descriptor = LMStudioDownloadedModelDescriptor(
            indexedModelIdentifier: "mlx-community/Llama-3.2-3B-Instruct-4bit/model.safetensors.index.json",
            displayName: "Llama 3.2 3B Instruct 4bit",
            defaultIdentifier: "llama-3.2-3b-instruct",
            user: "mlx-community",
            model: "Llama-3.2-3B-Instruct-4bit",
            file: "weights.npz",
            format: "mlx",
            quantLabel: "4bit",
            domain: "llm",
            contextLength: 8192,
            directoryPath: modelDirectory.path,
            entryPointPath: modelDirectory.appendingPathComponent("weights.npz").path,
            sourceDirectoryType: "downloaded",
            paramsB: 3.0
        )

        let entries = LMStudioMarketBridge.catalogEntries(
            from: [descriptor],
            helperBinaryPath: ""
        )

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].backend, "mlx")
        XCTAssertEqual(entries[0].note, "lmstudio_managed")
        XCTAssertEqual(entries[0].modelPath, modelDirectory.path)
        XCTAssertEqual(entries[0].taskKinds, ["text_generate"])
    }

    func testCatalogEntriesInferVoiceProfileForTTSModels() throws {
        let modelDirectory = try makeTempDir()
        let config = """
        {
          "architectures": ["KokoroTTSModel"],
          "model_type": "kokoro_tts"
        }
        """
        try Data(config.utf8).write(to: modelDirectory.appendingPathComponent("config.json"))
        try Data("{}".utf8).write(to: modelDirectory.appendingPathComponent("tokenizer.json"))

        let descriptor = LMStudioDownloadedModelDescriptor(
            indexedModelIdentifier: "hexgrad/Kokoro-82M-zh-warm/model.safetensors",
            displayName: "Kokoro Warm Chinese",
            defaultIdentifier: "kokoro-82m-zh-warm",
            user: "hexgrad",
            model: "Kokoro-82M-zh-warm",
            file: "model.safetensors",
            format: "transformers",
            quantLabel: "fp16",
            domain: "audio",
            contextLength: 4096,
            directoryPath: modelDirectory.path,
            entryPointPath: modelDirectory.appendingPathComponent("model.safetensors").path,
            sourceDirectoryType: "xhub_market",
            paramsB: 0.08
        )

        let entries = LMStudioMarketBridge.catalogEntries(
            from: [descriptor],
            helperBinaryPath: ""
        )

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].taskKinds, ["text_to_speech"])
        XCTAssertEqual(entries[0].outputModalities, ["audio"])
        XCTAssertEqual(entries[0].note, "market_managed")
        XCTAssertEqual(entries[0].voiceProfile?.engineHints, ["kokoro"])
        XCTAssertEqual(entries[0].voiceProfile?.styleHints, ["warm"])
        XCTAssertEqual(entries[0].voiceProfile?.languageHints, ["zh"])
    }

    func testVoiceDownloadPolicyKeepsVoiceSidecarBinsAlongsideSafetensors() {
        let siblingNames = [
            "config.json",
            "model.safetensors",
            "tokenizer.json",
            "voices-v1.0.bin",
            "pytorch_model.bin",
        ]

        XCTAssertTrue(
            LMStudioMarketBridge.isAllowedMarketDownloadFile(
                name: "voices-v1.0.bin",
                formatHint: "transformers",
                siblingNames: siblingNames
            )
        )
        XCTAssertFalse(
            LMStudioMarketBridge.isAllowedMarketDownloadFile(
                name: "pytorch_model.bin",
                formatHint: "transformers",
                siblingNames: siblingNames
            )
        )
    }

    func testDiscoverHelperBinaryFallsBackToLMStudioPathWhenExecutableProbeFails() throws {
        let home = try makeTempDir()
        let binDirectory = home
            .appendingPathComponent(".lmstudio", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: binDirectory, withIntermediateDirectories: true)
        let helperURL = binDirectory.appendingPathComponent("lms")
        try Data("helper".utf8).write(to: helperURL)

        let path = LocalHelperBridgeDiscovery.discoverHelperBinary(
            homeDirectory: home,
            fileManager: ExecutableProbeFailingFileManager(),
            environment: [:]
        )

        XCTAssertEqual(path, helperURL.path)
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

    private func makeMarketResult(
        modelKey: String,
        title: String,
        capabilityTags: [String],
        formatHint: String,
        recommendedFitEstimation: String,
        recommendedSizeBytes: Int64
    ) -> LMStudioMarketResult {
        LMStudioMarketResult(
            modelKey: modelKey,
            title: title,
            summary: "",
            formatHint: formatHint,
            capabilityTags: capabilityTags,
            staffPick: false,
            recommendationReason: "",
            recommendedForThisMac: recommendedFitEstimation != "willNotFit",
            recommendedFitEstimation: recommendedFitEstimation,
            recommendedSizeBytes: recommendedSizeBytes,
            downloadIdentifier: modelKey,
            downloaded: false,
            inLibrary: false
        )
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}

private final class ExecutableProbeFailingFileManager: FileManager {
    override func isExecutableFile(atPath path: String) -> Bool {
        false
    }
}
