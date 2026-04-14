import XCTest
@testable import RELFlowHub

final class LocalBenchFixtureCatalogTests: XCTestCase {
    func testResolvePackURLFindsPackInsideProcessedResourceBundleRoot() throws {
        let tempDir = try makeTempDir()
        let bundleDir = tempDir.appendingPathComponent("RELFlowHub_RELFlowHub.bundle", isDirectory: true)
        let packURL = bundleDir.appendingPathComponent("bench_fixture_pack.v1.json", isDirectory: false)
        try FileManager.default.createDirectory(at: bundleDir, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: packURL)

        let resolved = LocalBenchFixtureCatalog.resolvePackURL(searchRoots: [bundleDir])

        XCTAssertEqual(resolved?.standardizedFileURL, packURL.standardizedFileURL)
    }

    func testResolvePackURLFindsPackInsideBenchFixturesSubdirectory() throws {
        let tempDir = try makeTempDir()
        let resourcesDir = tempDir.appendingPathComponent("Resources", isDirectory: true)
        let fixturesDir = resourcesDir.appendingPathComponent("BenchFixtures", isDirectory: true)
        let packURL = fixturesDir.appendingPathComponent("bench_fixture_pack.v1.json", isDirectory: false)
        try FileManager.default.createDirectory(at: fixturesDir, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: packURL)

        let resolved = LocalBenchFixtureCatalog.resolvePackURL(searchRoots: [resourcesDir])

        XCTAssertEqual(resolved?.standardizedFileURL, packURL.standardizedFileURL)
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
