import XCTest
@testable import RELFlowHub
@testable import RELFlowHubCore

final class HubStoreNetworkRequestPolicyTests: XCTestCase {
    func testTransientSupervisorWorkspaceUsesDisplayNameAsPolicyKey() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt-supervisor-call-summarize-url-\(UUID().uuidString)", isDirectory: true)

        let request = HubNetworkRequest(
            id: UUID().uuidString,
            source: "x_terminal",
            projectId: "hashed-temp-project-id",
            rootPath: root.path,
            displayName: "我的世界还原项目",
            reason: "supervisor skill summarize for project 我的世界还原项目：总结浏览器 grant 方案",
            requestedSeconds: 900,
            createdAt: Date().timeIntervalSince1970
        )

        XCTAssertEqual(HubStore.policyProjectId(for: request), "我的世界还原项目")
    }

    func testRegularWorkspaceKeepsStableProjectIdAsPolicyKey() {
        let root = URL(fileURLWithPath: "/Users/tester/work/my-project", isDirectory: true)
        let request = HubNetworkRequest(
            id: UUID().uuidString,
            source: "x_terminal",
            projectId: "stable-project-id",
            rootPath: root.path,
            displayName: "My Project",
            reason: "normal project task",
            requestedSeconds: 1200,
            createdAt: Date().timeIntervalSince1970
        )

        XCTAssertEqual(HubStore.policyProjectId(for: request), "stable-project-id")
    }

    func testXTerminalRequestsDefaultToAutoApproveWindow() {
        let request = HubNetworkRequest(
            id: UUID().uuidString,
            source: "x_terminal",
            projectId: "project-1",
            rootPath: "/tmp/project-1",
            displayName: "Project One",
            reason: "supervisor summarize",
            requestedSeconds: 900,
            createdAt: Date().timeIntervalSince1970
        )

        XCTAssertEqual(HubStore.defaultAutoApproveSeconds(for: request, appId: "x_terminal"), 900)
        XCTAssertEqual(HubStore.defaultAutoApproveSeconds(for: request, appId: "X_TERMINAL"), 900)
        XCTAssertEqual(HubStore.defaultAutoApproveSeconds(for: request, appId: "x-terminal"), 900)
        XCTAssertEqual(HubStore.defaultAutoApproveSeconds(for: request, appId: "X-Terminal"), 900)
        XCTAssertEqual(HubStore.defaultAutoApproveSeconds(for: request, appId: "xterminal"), 900)
        XCTAssertEqual(HubStore.defaultAutoApproveSeconds(for: request, appId: "ax_terminal"), 900)
        XCTAssertEqual(HubStore.defaultAutoApproveSeconds(for: request, appId: "ax-terminal"), 900)
    }

    func testNonTerminalRequestsStillNeedExplicitPolicy() {
        let request = HubNetworkRequest(
            id: UUID().uuidString,
            source: "other_app",
            projectId: "project-2",
            rootPath: "/tmp/project-2",
            displayName: "Project Two",
            reason: "other runtime",
            requestedSeconds: 600,
            createdAt: Date().timeIntervalSince1970
        )

        XCTAssertNil(HubStore.defaultAutoApproveSeconds(for: request, appId: "other_app"))
    }

    func testPolicyAppIdCanonicalizesXTerminalAliases() {
        let request = HubNetworkRequest(
            id: UUID().uuidString,
            source: "X-Terminal",
            projectId: "project-3",
            rootPath: "/tmp/project-3",
            displayName: "Project Three",
            reason: "summarize",
            requestedSeconds: 600,
            createdAt: Date().timeIntervalSince1970
        )

        XCTAssertEqual(HubStore.policyAppId(for: request), "x_terminal")
    }

    func testNetworkPolicyStorageMatchesXTerminalAliasesAcrossStoredRules() {
        XCTAssertEqual(HubNetworkPolicyStorage.canonicalAppId("X-Terminal"), "x_terminal")
        XCTAssertEqual(HubNetworkPolicyStorage.canonicalAppId("ax_terminal"), "x_terminal")
        XCTAssertEqual(HubNetworkPolicyStorage.canonicalAppId("ax-terminal"), "x_terminal")
        XCTAssertEqual(HubNetworkPolicyStorage.canonicalAppId("xterminal"), "x_terminal")
    }
}
