import XCTest
@testable import RELFlowHub
@testable import RELFlowHubCore

final class LocalModelManagedStorageTests: XCTestCase {
    func testPreparedCatalogEntryCopiesSandboxModelIntoManagedDirectory() throws {
        let sourceRoot = try makeTempDir()
        let baseDir = try makeTempDir()
        let sourceModel = sourceRoot.appendingPathComponent("glm-local", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceModel, withIntermediateDirectories: true)
        try Data().write(to: sourceModel.appendingPathComponent("weights.npz"))
        try Data("{}".utf8).write(to: sourceModel.appendingPathComponent("tokenizer.json"))

        let entry = ModelCatalogEntry(
            id: "glm-local",
            name: "GLM Local",
            backend: "mlx",
            quant: "4bit",
            contextLength: 32768,
            modelPath: sourceModel.path,
            note: "catalog",
            modelFormat: "mlx",
            taskKinds: ["text_generate"]
        )

        let prepared = try LocalModelManagedStorage.preparedCatalogEntryIfNeeded(
            entry,
            sandboxed: true,
            baseDir: baseDir
        )

        XCTAssertEqual(
            prepared.modelPath,
            baseDir.appendingPathComponent("models", isDirectory: true)
                .appendingPathComponent("glm-local", isDirectory: true).path
        )
        XCTAssertEqual(prepared.note, "managed_copy")
        XCTAssertTrue(FileManager.default.fileExists(atPath: prepared.modelPath))
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: URL(fileURLWithPath: prepared.modelPath)
                    .appendingPathComponent("weights.npz").path
            )
        )
    }

    func testPreparedCatalogEntryReusesExistingManagedCopy() throws {
        let sourceRoot = try makeTempDir()
        let baseDir = try makeTempDir()
        let sourceModel = sourceRoot.appendingPathComponent("stale-source", isDirectory: true)
        let managedModel = baseDir
            .appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent("stale-model", isDirectory: true)

        try FileManager.default.createDirectory(at: sourceModel, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: managedModel, withIntermediateDirectories: true)
        try Data().write(to: managedModel.appendingPathComponent("weights.npz"))
        try Data("{}".utf8).write(to: managedModel.appendingPathComponent("tokenizer.json"))

        let entry = ModelCatalogEntry(
            id: "stale-model",
            name: "Stale Model",
            backend: "mlx",
            quant: "bf16",
            contextLength: 8192,
            modelPath: sourceModel.path,
            note: "catalog",
            modelFormat: "mlx",
            taskKinds: ["text_generate"]
        )

        let prepared = try LocalModelManagedStorage.preparedCatalogEntryIfNeeded(
            entry,
            sandboxed: true,
            baseDir: baseDir
        )

        XCTAssertEqual(prepared.modelPath, managedModel.path)
        XCTAssertEqual(prepared.note, "managed_copy")
    }

    func testPreparedCatalogEntryReusesExistingManagedCopyWhenOriginalSourceIsGone() throws {
        let baseDir = try makeTempDir()
        let missingSourceModel = baseDir
            .appendingPathComponent("detached-source", isDirectory: true)
            .appendingPathComponent("qwen-local", isDirectory: true)
        let managedModel = baseDir
            .appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent("qwen-local", isDirectory: true)

        try FileManager.default.createDirectory(at: managedModel, withIntermediateDirectories: true)
        try Data().write(to: managedModel.appendingPathComponent("weights.npz"))
        try Data("{}".utf8).write(to: managedModel.appendingPathComponent("tokenizer.json"))

        let entry = ModelCatalogEntry(
            id: "qwen-local",
            name: "Qwen Local",
            backend: "mlx",
            quant: "bf16",
            contextLength: 8192,
            modelPath: missingSourceModel.path,
            note: "catalog",
            modelFormat: "mlx",
            taskKinds: ["text_generate"]
        )

        let prepared = try LocalModelManagedStorage.preparedCatalogEntryIfNeeded(
            entry,
            sandboxed: true,
            baseDir: baseDir
        )

        XCTAssertEqual(prepared.modelPath, managedModel.path)
        XCTAssertEqual(prepared.note, "managed_copy")
    }

    func testPreparedCatalogEntryPreservesLMStudioManagedSourceNote() throws {
        let sourceRoot = try makeTempDir()
        let baseDir = try makeTempDir()
        let sourceModel = sourceRoot.appendingPathComponent("vision-model", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceModel, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: sourceModel.appendingPathComponent("config.json"))
        try Data("{}".utf8).write(to: sourceModel.appendingPathComponent("tokenizer.json"))

        let entry = ModelCatalogEntry(
            id: "vision-model",
            name: "Vision Model",
            backend: "transformers",
            runtimeProviderID: "transformers",
            quant: "4bit",
            contextLength: 16384,
            modelPath: sourceModel.path,
            note: "lmstudio_managed",
            modelFormat: "hf_transformers",
            taskKinds: ["vision_understand"]
        )

        let prepared = try LocalModelManagedStorage.preparedCatalogEntryIfNeeded(
            entry,
            sandboxed: true,
            baseDir: baseDir
        )

        XCTAssertEqual(prepared.note, "lmstudio_managed_copy")
        XCTAssertTrue(
            prepared.modelPath.hasPrefix(
                baseDir.appendingPathComponent("models", isDirectory: true).path
            )
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
