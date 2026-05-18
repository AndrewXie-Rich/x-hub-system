import XCTest
@testable import RELFlowHub

final class HubGRPCServerSupportProcessCleanupTests: XCTestCase {
    @MainActor
    func testBundledServerProcessPIDsMatchesOnlyCurrentBundleNodeServerPair() {
        let nodePath = "/Applications/X-Hub.app/Contents/Resources/relflowhub_node"
        let serverPath = "/Applications/X-Hub.app/Contents/Resources/hub_grpc_server/src/server.js"
        let processList = """
         10949 \(nodePath) \(serverPath)
         10950 /Applications/Other.app/Contents/Resources/relflowhub_node \(serverPath)
         10951 \(nodePath) /Applications/X-Hub.app/Contents/Resources/hub_grpc_server/src/worker.js
         10952 /usr/bin/python3 /tmp/something.py
        """

        let pids = HubGRPCServerSupport.bundledServerProcessPIDs(
            processListOutput: processList,
            nodeExecutablePath: nodePath,
            serverJSPath: serverPath
        )

        XCTAssertEqual(pids, [10949])
    }

    @MainActor
    func testBundledServerProcessPIDsExcludesSpecifiedPIDs() {
        let nodePath = "/Applications/X-Hub.app/Contents/Resources/relflowhub_node"
        let serverPath = "/Applications/X-Hub.app/Contents/Resources/hub_grpc_server/src/server.js"
        let processList = """
         10949 \(nodePath) \(serverPath)
         10953 \(nodePath) \(serverPath)
        """

        let pids = HubGRPCServerSupport.bundledServerProcessPIDs(
            processListOutput: processList,
            nodeExecutablePath: nodePath,
            serverJSPath: serverPath,
            excluding: [10949]
        )

        XCTAssertEqual(pids, [10953])
    }
}
