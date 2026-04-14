import XCTest
@testable import RELFlowHubCore

final class AIRuntimeStatusStorageTests: XCTestCase {
    override func tearDown() {
        unsetenv("XHUB_SOURCE_RUN_HOME")
        super.tearDown()
    }

    func testLoadResolvedPrefersPrimaryRuntimeRootOverFresherFallbackSnapshot() throws {
        let home = try makeTempHome()
        setenv("XHUB_SOURCE_RUN_HOME", home.path, 1)

        let primaryURL = AIRuntimeStatusStorage.url()
        let primaryBase = primaryURL.deletingLastPathComponent()
        let fallbackBaseName = primaryBase.lastPathComponent == SharedPaths.preferredRuntimeDirectoryName
            ? SharedPaths.legacyRuntimeDirectoryName
            : SharedPaths.preferredRuntimeDirectoryName
        let fallbackBase = home.appendingPathComponent(fallbackBaseName, isDirectory: true)

        try writeStatus(
            makeStatus(pid: 111, updatedAt: Date().timeIntervalSince1970 - 2.0, providerReasonCode: "primary_ready"),
            to: primaryURL
        )
        try writeStatus(
            makeStatus(pid: 222, updatedAt: Date().timeIntervalSince1970 - 1.0, providerReasonCode: "fallback_ready"),
            to: fallbackBase.appendingPathComponent(AIRuntimeStatusStorage.fileName)
        )

        let resolved = try XCTUnwrap(AIRuntimeStatusStorage.loadResolved())
        XCTAssertEqual(resolved.status.pid, 111)
        XCTAssertEqual(resolved.url.path, primaryURL.path)
        XCTAssertEqual(resolved.status.providerStatus("mlx")?.reasonCode, "primary_ready")
    }

    func testLoadResolvedFallsBackToFreshestReadableSnapshotWhenPrimaryMissing() throws {
        let home = try makeTempHome()
        setenv("XHUB_SOURCE_RUN_HOME", home.path, 1)

        let xhubBase = home.appendingPathComponent("XHub", isDirectory: true)
        let legacyBase = home.appendingPathComponent("RELFlowHub", isDirectory: true)

        try writeStatus(
            makeStatus(pid: 333, updatedAt: Date().timeIntervalSince1970 - 4.0, providerReasonCode: "older_fallback"),
            to: xhubBase.appendingPathComponent(AIRuntimeStatusStorage.fileName)
        )
        try writeStatus(
            makeStatus(pid: 444, updatedAt: Date().timeIntervalSince1970 - 1.0, providerReasonCode: "newer_fallback"),
            to: legacyBase.appendingPathComponent(AIRuntimeStatusStorage.fileName)
        )

        let resolved = try XCTUnwrap(AIRuntimeStatusStorage.loadResolved())
        XCTAssertEqual(resolved.status.pid, 444)
        XCTAssertEqual(
            resolved.url.path,
            legacyBase.appendingPathComponent(AIRuntimeStatusStorage.fileName).path
        )
        XCTAssertEqual(resolved.status.providerStatus("mlx")?.reasonCode, "newer_fallback")
    }

    private func makeTempHome() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("xhub-status-storage-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeStatus(pid: Int, updatedAt: Double, providerReasonCode: String) -> AIRuntimeStatus {
        AIRuntimeStatus(
            pid: pid,
            updatedAt: updatedAt,
            mlxOk: true,
            runtimeVersion: "test-runtime",
            schemaVersion: "xhub.local_runtime_status.v2",
            providers: [
                "mlx": AIRuntimeProviderStatus(
                    provider: "mlx",
                    ok: true,
                    reasonCode: providerReasonCode,
                    runtimeVersion: "test-runtime",
                    availableTaskKinds: ["text_generate"],
                    loadedModels: ["qwen3-17b-mlx-bf16"],
                    deviceBackend: "mps",
                    updatedAt: updatedAt,
                    loadedModelCount: 1
                ),
            ]
        )
    }

    private func writeStatus(_ status: AIRuntimeStatus, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(status)
        try data.write(to: url, options: .atomic)
    }
}
