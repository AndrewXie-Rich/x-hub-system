import XCTest
@testable import RELFlowHub
@testable import RELFlowHubCore

final class LocalProviderPackRegistryTests: XCTestCase {
    func testHelperDiscoveryPrefersLocalLMStudioBinary() throws {
        let home = try makeTempDir()
        let helper = home
            .appendingPathComponent(".lmstudio", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("lms")
        try makeExecutable(at: helper)

        let discovered = LocalHelperBridgeDiscovery.discoverHelperBinary(
            homeDirectory: home,
            fileManager: .default,
            environment: [:]
        )

        XCTAssertEqual(discovered, helper.path)
    }

    func testSyncAutoManagedPacksWritesTransformersHelperOverrideForVisionCatalog() throws {
        let baseDir = try makeTempDir()
        let helper = try makeHelper()
        let catalog = ModelCatalogSnapshot(
            models: [
                ModelCatalogEntry(
                    id: "glm4v-local",
                    name: "GLM4V Local",
                    backend: "transformers",
                    quant: "int4",
                    contextLength: 8192,
                    paramsB: 9.0,
                    modelPath: "/tmp/models/glm4v-local",
                    taskKinds: ["vision_understand", "ocr"]
                ),
            ],
            updatedAt: 0
        )

        let changed = LocalProviderPackRegistry.syncAutoManagedPacks(
            baseDir: baseDir,
            catalog: catalog,
            helperBinaryPath: helper.path
        )
        let snapshot = LocalProviderPackRegistry.load(baseDir: baseDir)

        XCTAssertTrue(changed)
        XCTAssertEqual(snapshot.packs.count, 1)
        XCTAssertEqual(snapshot.packs[0].providerId, "transformers")
        XCTAssertEqual(snapshot.packs[0].runtimeRequirements.executionMode, "helper_binary_bridge")
        XCTAssertEqual(snapshot.packs[0].runtimeRequirements.helperBinary, helper.path)
        XCTAssertEqual(snapshot.packs[0].reasonCode, "auto_local_helper_bridge_enabled")
    }

    func testSyncAutoManagedPacksWritesMLXVLMHelperOverrideForMLXVisionCatalog() throws {
        let baseDir = try makeTempDir()
        let helper = try makeHelper()
        let catalog = ModelCatalogSnapshot(
            models: [
                ModelCatalogEntry(
                    id: "glm4v-mlx",
                    name: "GLM4V MLX",
                    backend: "mlx",
                    quant: "int4",
                    contextLength: 8192,
                    paramsB: 9.0,
                    modelPath: "/tmp/models/glm4v-mlx",
                    taskKinds: ["vision_understand", "ocr"]
                ),
            ],
            updatedAt: 0
        )

        let changed = LocalProviderPackRegistry.syncAutoManagedPacks(
            baseDir: baseDir,
            catalog: catalog,
            helperBinaryPath: helper.path
        )
        let snapshot = LocalProviderPackRegistry.load(baseDir: baseDir)

        XCTAssertTrue(changed)
        XCTAssertEqual(snapshot.packs.count, 1)
        XCTAssertEqual(snapshot.packs[0].providerId, "mlx_vlm")
        XCTAssertEqual(snapshot.packs[0].engine, "mlx-vlm")
        XCTAssertEqual(snapshot.packs[0].supportedFormats, ["mlx"])
        XCTAssertEqual(snapshot.packs[0].supportedDomains, ["vision", "ocr"])
        XCTAssertEqual(snapshot.packs[0].runtimeRequirements.executionMode, "helper_binary_bridge")
    }

    func testSyncAutoManagedPacksWritesLlamaCppHelperOverrideForGGUFCatalog() throws {
        let baseDir = try makeTempDir()
        let helper = try makeHelper()
        let catalog = ModelCatalogSnapshot(
            models: [
                ModelCatalogEntry(
                    id: "qwen3-gguf",
                    name: "Qwen3 GGUF",
                    backend: "llama.cpp",
                    quant: "q4_k_m",
                    contextLength: 8192,
                    paramsB: 8.0,
                    modelPath: "/tmp/models/qwen3-gguf",
                    taskKinds: ["text_generate", "embedding"]
                ),
            ],
            updatedAt: 0
        )

        let changed = LocalProviderPackRegistry.syncAutoManagedPacks(
            baseDir: baseDir,
            catalog: catalog,
            helperBinaryPath: helper.path
        )
        let snapshot = LocalProviderPackRegistry.load(baseDir: baseDir)

        XCTAssertTrue(changed)
        XCTAssertEqual(snapshot.packs.count, 1)
        XCTAssertEqual(snapshot.packs[0].providerId, "llama.cpp")
        XCTAssertEqual(snapshot.packs[0].engine, "llama.cpp")
        XCTAssertEqual(snapshot.packs[0].version, "auto-2026-03-25")
        XCTAssertEqual(snapshot.packs[0].supportedFormats, ["gguf"])
        XCTAssertEqual(snapshot.packs[0].supportedDomains, ["text", "embedding"])
        XCTAssertEqual(snapshot.packs[0].runtimeRequirements.executionMode, "helper_binary_bridge")
        XCTAssertEqual(snapshot.packs[0].runtimeRequirements.helperBinary, helper.path)
        XCTAssertEqual(snapshot.packs[0].reasonCode, "auto_local_helper_bridge_enabled")
    }

    func testSyncAutoManagedPacksWritesTransformersHelperOverrideForTTSCatalog() throws {
        let baseDir = try makeTempDir()
        let helper = try makeHelper()
        let catalog = ModelCatalogSnapshot(
            models: [
                ModelCatalogEntry(
                    id: "kokoro-82m-zh-warm",
                    name: "Kokoro Warm Chinese",
                    backend: "transformers",
                    quant: "fp16",
                    contextLength: 4096,
                    paramsB: 0.08,
                    modelPath: "/tmp/models/kokoro-82m-zh-warm",
                    taskKinds: ["text_to_speech"]
                ),
            ],
            updatedAt: 0
        )

        let changed = LocalProviderPackRegistry.syncAutoManagedPacks(
            baseDir: baseDir,
            catalog: catalog,
            helperBinaryPath: helper.path
        )
        let snapshot = LocalProviderPackRegistry.load(baseDir: baseDir)

        XCTAssertTrue(changed)
        XCTAssertEqual(snapshot.packs.count, 1)
        XCTAssertEqual(snapshot.packs[0].providerId, "transformers")
        XCTAssertEqual(snapshot.packs[0].runtimeRequirements.executionMode, "helper_binary_bridge")
        XCTAssertTrue(snapshot.packs[0].supportedDomains.contains("voice"))
        XCTAssertEqual(snapshot.packs[0].reasonCode, "auto_local_helper_bridge_enabled")
    }

    func testSyncAutoManagedPacksSkipsTransformersHelperOverrideWhenASRModelExists() throws {
        let baseDir = try makeTempDir()
        let helper = try makeHelper()
        let catalog = ModelCatalogSnapshot(
            models: [
                ModelCatalogEntry(
                    id: "whisper-local",
                    name: "Whisper Local",
                    backend: "transformers",
                    quant: "fp16",
                    contextLength: 2048,
                    paramsB: 1.0,
                    modelPath: "/tmp/models/whisper-local",
                    taskKinds: ["speech_to_text"]
                ),
            ],
            updatedAt: 0
        )

        let changed = LocalProviderPackRegistry.syncAutoManagedPacks(
            baseDir: baseDir,
            catalog: catalog,
            helperBinaryPath: helper.path
        )
        let snapshot = LocalProviderPackRegistry.load(baseDir: baseDir)

        XCTAssertFalse(changed)
        XCTAssertTrue(snapshot.packs.isEmpty)
    }

    func testSyncAutoManagedPacksPreservesManualTransformersOverride() throws {
        let baseDir = try makeTempDir()
        let helper = try makeHelper()
        let existing = LocalProviderPackRegistrySnapshot(
            schemaVersion: LocalProviderPackRegistry.schemaVersion,
            updatedAt: 1,
            packs: [
                LocalProviderPackRegistryEntry(
                    providerId: "transformers",
                    engine: "hf-transformers",
                    version: "manual",
                    runtimeRequirements: LocalProviderPackRegistryRuntimeRequirements(
                        executionMode: "builtin_python"
                    ),
                    installed: true,
                    enabled: true,
                    packState: "installed",
                    reasonCode: "manual_override",
                    note: "manual"
                ),
            ]
        )
        LocalProviderPackRegistry.save(existing, baseDir: baseDir)
        let catalog = ModelCatalogSnapshot(
            models: [
                ModelCatalogEntry(
                    id: "glm4v-local",
                    name: "GLM4V Local",
                    backend: "transformers",
                    quant: "int4",
                    contextLength: 8192,
                    paramsB: 9.0,
                    modelPath: "/tmp/models/glm4v-local",
                    taskKinds: ["vision_understand"]
                ),
            ],
            updatedAt: 0
        )

        let changed = LocalProviderPackRegistry.syncAutoManagedPacks(
            baseDir: baseDir,
            catalog: catalog,
            helperBinaryPath: helper.path
        )
        let snapshot = LocalProviderPackRegistry.load(baseDir: baseDir)

        XCTAssertFalse(changed)
        XCTAssertEqual(snapshot, existing)
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

    private func makeHelper() throws -> URL {
        let directory = try makeTempDir()
        let helper = directory.appendingPathComponent("lms")
        try makeExecutable(at: helper)
        return helper
    }

    private func makeExecutable(at url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try XCTUnwrap("#!/bin/sh\nexit 0\n".data(using: .utf8))
        try data.write(to: url)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o755))],
            ofItemAtPath: url.path
        )
    }
}
