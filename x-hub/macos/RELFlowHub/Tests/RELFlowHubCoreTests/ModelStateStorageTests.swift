import XCTest
@testable import RELFlowHubCore

final class ModelStateStorageTests: XCTestCase {
    override func tearDown() {
        unsetenv("XHUB_SOURCE_RUN_HOME")
        super.tearDown()
    }

    func testLoadPrefersPrimaryRuntimeRootOverFresherFallbackSnapshot() throws {
        let home = try makeTempHome()
        setenv("XHUB_SOURCE_RUN_HOME", home.path, 1)
        let primaryUpdatedAt = Date().timeIntervalSince1970 - 2.0
        let fallbackUpdatedAt = Date().timeIntervalSince1970 - 1.0

        let primaryURL = ModelStateStorage.url()
        let primaryBase = primaryURL.deletingLastPathComponent()
        let fallbackBaseName = primaryBase.lastPathComponent == SharedPaths.preferredRuntimeDirectoryName
            ? SharedPaths.legacyRuntimeDirectoryName
            : SharedPaths.preferredRuntimeDirectoryName
        let fallbackBase = home.appendingPathComponent(fallbackBaseName, isDirectory: true)

        try writeSnapshot(
            makeSnapshot(
                modelID: "primary-model",
                updatedAt: primaryUpdatedAt
            ),
            to: primaryURL
        )
        try writeSnapshot(
            makeSnapshot(
                modelID: "fallback-model",
                updatedAt: fallbackUpdatedAt
            ),
            to: fallbackBase.appendingPathComponent(ModelStateStorage.fileName)
        )

        let loaded = ModelStateStorage.load()
        XCTAssertEqual(loaded.models.map(\.id), ["primary-model"])
        XCTAssertEqual(loaded.updatedAt, primaryUpdatedAt, accuracy: 0.0001)
    }

    func testLoadFallsBackToFreshestReadableSnapshotWhenPrimaryMissing() throws {
        let home = try makeTempHome()
        setenv("XHUB_SOURCE_RUN_HOME", home.path, 1)

        let xhubBase = home.appendingPathComponent(SharedPaths.preferredRuntimeDirectoryName, isDirectory: true)
        let legacyBase = home.appendingPathComponent(SharedPaths.legacyRuntimeDirectoryName, isDirectory: true)

        try writeSnapshot(
            makeSnapshot(
                modelID: "older-model",
                updatedAt: Date().timeIntervalSince1970 - 4.0
            ),
            to: xhubBase.appendingPathComponent(ModelStateStorage.fileName)
        )
        try writeSnapshot(
            makeSnapshot(
                modelID: "newer-model",
                updatedAt: Date().timeIntervalSince1970 - 1.0
            ),
            to: legacyBase.appendingPathComponent(ModelStateStorage.fileName)
        )

        let loaded = ModelStateStorage.load()
        XCTAssertEqual(loaded.models.map(\.id), ["newer-model"])
    }

    private func makeTempHome() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("xhub-model-state-storage-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeSnapshot(modelID: String, updatedAt: Double) -> ModelStateSnapshot {
        ModelStateSnapshot(
            models: [
                HubModel(
                    id: modelID,
                    name: modelID,
                    backend: "transformers",
                    runtimeProviderID: "transformers",
                    quant: "fp16",
                    contextLength: 32768,
                    paramsB: 0.5,
                    state: .loaded,
                    modelPath: "/tmp/\(modelID)",
                    taskKinds: ["text_generate"]
                )
            ],
            updatedAt: updatedAt
        )
    }

    private func writeSnapshot(_ snapshot: ModelStateSnapshot, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(snapshot)
        try data.write(to: url, options: .atomic)
    }
}
