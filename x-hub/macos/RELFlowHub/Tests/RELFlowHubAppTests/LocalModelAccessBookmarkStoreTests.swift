import XCTest
@testable import RELFlowHub

final class LocalModelAccessBookmarkStoreTests: XCTestCase {
    func testPersistBookmarkStoresAndResolvesExactDirectory() throws {
        let baseDir = try makeTempDir()
        let modelDir = baseDir.appendingPathComponent("source-model", isDirectory: true)
        try FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)

        LocalModelAccessBookmarkStore.persistBookmarkIfPossible(
            for: modelDir,
            baseDir: baseDir
        )

        let snapshot = LocalModelAccessBookmarkStore.load(baseDir: baseDir)
        XCTAssertEqual(snapshot.records.count, 1)
        XCTAssertEqual(snapshot.records.first?.path, modelDir.standardizedFileURL.path)
        XCTAssertEqual(
            LocalModelAccessBookmarkStore.resolvedBookmarkURL(for: modelDir, baseDir: baseDir)?.path,
            modelDir.standardizedFileURL.path
        )
    }

    func testResolvedBookmarkURLFallsBackToAncestorDirectory() throws {
        let baseDir = try makeTempDir()
        let rootDir = baseDir.appendingPathComponent("root", isDirectory: true)
        let nestedModelDir = rootDir
            .appendingPathComponent("publisher", isDirectory: true)
            .appendingPathComponent("vision-model", isDirectory: true)
        try FileManager.default.createDirectory(at: nestedModelDir, withIntermediateDirectories: true)

        LocalModelAccessBookmarkStore.persistBookmarkIfPossible(
            for: rootDir,
            baseDir: baseDir
        )

        let resolved = LocalModelAccessBookmarkStore.resolvedBookmarkURL(
            for: nestedModelDir,
            baseDir: baseDir
        )
        XCTAssertEqual(resolved?.path, rootDir.standardizedFileURL.path)
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
