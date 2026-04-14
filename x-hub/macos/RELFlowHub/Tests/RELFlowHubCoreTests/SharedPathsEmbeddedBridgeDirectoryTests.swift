import XCTest
@testable import RELFlowHubCore

final class SharedPathsEmbeddedBridgeDirectoryTests: XCTestCase {
    func testEmbeddedBridgeDirectoryPrefersHubContainerWhenSandboxContainerExists() {
        let dir = SharedPaths.ensureEmbeddedBridgeDirectory(bundleId: "com.rel.flowhub")

        XCTAssertFalse(dir.path.hasPrefix("/private/tmp/RELFlowHub"))
        if SharedPaths.appGroupDirectory() == nil,
           SharedPaths.isSandboxedProcess(),
           let container = SharedPaths.containerDataDirectory(bundleId: "com.rel.flowhub") {
            XCTAssertEqual(
                dir.path,
                container.appendingPathComponent("RELFlowHub", isDirectory: true).path
            )
        } else {
            XCTAssertEqual(dir.path, SharedPaths.ensureHubDirectory().path)
        }
    }
}
