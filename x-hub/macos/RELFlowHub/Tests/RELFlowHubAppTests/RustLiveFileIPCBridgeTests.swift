import XCTest
@testable import RELFlowHub

final class RustLiveFileIPCBridgeTests: XCTestCase {
    func testPublishesAppGroupStatusAliasToRustLiveBase() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let appBase = root.appendingPathComponent("group.rel.flowhub", isDirectory: true)
        let liveBase = root.appendingPathComponent("RELFlowHub", isDirectory: true)
        let now: TimeInterval = 1_778_900_000
        try writeLiveStatus(baseDir: liveBase, now: now - 0.25)

        let bridge = makeBridge(appBase: appBase, liveBase: liveBase)
        let fallback = makeFallbackStatus(baseDir: appBase, now: now)

        XCTAssertTrue(bridge.publishAliasHeartbeat(fallbackStatus: fallback, now: now))

        let object = try readJSONObject(appBase.appendingPathComponent("hub_status.json"))
        XCTAssertEqual(object["baseDir"] as? String, liveBase.path)
        XCTAssertEqual(object["ipcPath"] as? String, liveBase.appendingPathComponent("ipc_events", isDirectory: true).path)
        XCTAssertEqual(object["updatedAt"] as? Double, now)
        XCTAssertEqual(object["appVersion"] as? String, "9.8.7")
        XCTAssertEqual((object["rustHub"] as? [String: Any])?["schema_version"] as? String, "xhub.rust_hub.xt_classic_status.v1")
        XCTAssertEqual((object["swiftShellBridge"] as? [String: Any])?["mode"] as? String, "app_group_alias")
    }

    func testForwardsKernelEventAndMirrorsRustResponse() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let appBase = root.appendingPathComponent("group.rel.flowhub", isDirectory: true)
        let liveBase = root.appendingPathComponent("RELFlowHub", isDirectory: true)
        let appEvents = appBase.appendingPathComponent("ipc_events", isDirectory: true)
        let appResponses = appBase.appendingPathComponent("ipc_responses", isDirectory: true)
        let liveEvents = liveBase.appendingPathComponent("ipc_events", isDirectory: true)
        let liveResponses = liveBase.appendingPathComponent("ipc_responses", isDirectory: true)
        let now: TimeInterval = 1_778_900_100
        try writeLiveStatus(baseDir: liveBase, now: now)
        try FileManager.default.createDirectory(at: appEvents, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: liveResponses, withIntermediateDirectories: true)

        let event = appEvents.appendingPathComponent("event_memory.json")
        try #"{"type":"memory_retrieval","reqId":"req-123","memory_retrieval":{"query":"hello"}}"#
            .write(to: event, atomically: true, encoding: .utf8)

        let bridge = makeBridge(appBase: appBase, liveBase: liveBase)
        XCTAssertTrue(bridge.bridgeDropboxes(now: now + 0.1))

        XCTAssertFalse(FileManager.default.fileExists(atPath: event.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: liveEvents.appendingPathComponent("event_memory.json").path))

        let liveResponse = liveResponses.appendingPathComponent("resp_req-123.json")
        try #"{"type":"memory_retrieval_ack","reqId":"req-123","ok":true}"#
            .write(to: liveResponse, atomically: true, encoding: .utf8)

        XCTAssertTrue(bridge.bridgeDropboxes(now: now + 0.2))
        XCTAssertTrue(FileManager.default.fileExists(atPath: appResponses.appendingPathComponent("resp_req-123.json").path))
    }

    func testPrimaryEventIdleThrottleStillMirrorsRustResponse() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let appBase = root.appendingPathComponent("group.rel.flowhub", isDirectory: true)
        let liveBase = root.appendingPathComponent("RELFlowHub", isDirectory: true)
        let appEvents = appBase.appendingPathComponent("ipc_events", isDirectory: true)
        let appResponses = appBase.appendingPathComponent("ipc_responses", isDirectory: true)
        let liveEvents = liveBase.appendingPathComponent("ipc_events", isDirectory: true)
        let liveResponses = liveBase.appendingPathComponent("ipc_responses", isDirectory: true)
        let now: TimeInterval = 1_778_900_120
        try writeLiveStatus(baseDir: liveBase, now: now)
        try FileManager.default.createDirectory(at: appEvents, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: liveResponses, withIntermediateDirectories: true)

        let firstEvent = appEvents.appendingPathComponent("event_memory_first.json")
        try #"{"type":"memory_retrieval","reqId":"req-first","memory_retrieval":{"query":"first"}}"#
            .write(to: firstEvent, atomically: true, encoding: .utf8)

        let bridge = RustLiveFileIPCBridge(
            appBaseDir: appBase,
            appEventsDir: appEvents,
            appResponsesDir: appResponses,
            appStatusFile: appBase.appendingPathComponent("hub_status.json"),
            compatBaseDirs: [],
            liveBaseDirCandidates: { [liveBase] },
            httpLiveStatusOverride: { _ in nil }
        )

        XCTAssertTrue(bridge.bridgeDropboxes(now: now + 0.1))
        XCTAssertFalse(FileManager.default.fileExists(atPath: firstEvent.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: liveEvents.appendingPathComponent("event_memory_first.json").path))

        let liveResponse = liveResponses.appendingPathComponent("resp_req-first.json")
        try #"{"type":"memory_retrieval_ack","reqId":"req-first","ok":true}"#
            .write(to: liveResponse, atomically: true, encoding: .utf8)
        let secondEvent = appEvents.appendingPathComponent("event_memory_second.json")
        try #"{"type":"memory_retrieval","reqId":"req-second","memory_retrieval":{"query":"second"}}"#
            .write(to: secondEvent, atomically: true, encoding: .utf8)

        XCTAssertTrue(bridge.bridgeDropboxes(now: now + 0.2))
        XCTAssertTrue(FileManager.default.fileExists(atPath: appResponses.appendingPathComponent("resp_req-first.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: secondEvent.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: liveEvents.appendingPathComponent("event_memory_second.json").path))

        XCTAssertTrue(bridge.bridgeDropboxes(now: now + 0.5))
        XCTAssertFalse(FileManager.default.fileExists(atPath: secondEvent.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: liveEvents.appendingPathComponent("event_memory_second.json").path))
    }

    func testPublishesAliasToCompatibilityBaseWhenPrimaryIsContainer() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let containerBase = root.appendingPathComponent("container/RELFlowHub", isDirectory: true)
        let compatBase = root.appendingPathComponent("Library/Group Containers/group.rel.flowhub", isDirectory: true)
        let liveBase = root.appendingPathComponent("RELFlowHub", isDirectory: true)
        let now: TimeInterval = 1_778_900_150
        try writeLiveStatus(baseDir: liveBase, now: now - 0.25)

        let bridge = makeBridge(appBase: containerBase, liveBase: liveBase, compatBaseDirs: [compatBase])
        let fallback = makeFallbackStatus(baseDir: containerBase, now: now)

        XCTAssertTrue(bridge.publishAliasHeartbeat(fallbackStatus: fallback, now: now))

        let primaryObject = try readJSONObject(containerBase.appendingPathComponent("hub_status.json"))
        XCTAssertEqual(primaryObject["baseDir"] as? String, liveBase.path)
        XCTAssertEqual((primaryObject["swiftShellBridge"] as? [String: Any])?["endpoint_role"] as? String, "primary")

        let compatObject = try readJSONObject(compatBase.appendingPathComponent("hub_status.json"))
        XCTAssertEqual(compatObject["baseDir"] as? String, liveBase.path)
        XCTAssertEqual((compatObject["swiftShellBridge"] as? [String: Any])?["endpoint_role"] as? String, "compat")
        XCTAssertEqual((compatObject["swiftShellBridge"] as? [String: Any])?["compat_base_dir"] as? String, compatBase.path)
    }

    func testSkipsPrimaryStatusWhenResolvingRustLiveBase() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let containerBase = root.appendingPathComponent("container/RELFlowHub", isDirectory: true)
        let liveBase = root.appendingPathComponent("RELFlowHub", isDirectory: true)
        let now: TimeInterval = 1_778_900_165
        try writeLiveStatus(baseDir: containerBase, now: now)
        try writeLiveStatus(baseDir: liveBase, now: now)

        let bridge = RustLiveFileIPCBridge(
            appBaseDir: containerBase,
            appEventsDir: containerBase.appendingPathComponent("ipc_events", isDirectory: true),
            appResponsesDir: containerBase.appendingPathComponent("ipc_responses", isDirectory: true),
            appStatusFile: containerBase.appendingPathComponent("hub_status.json"),
            compatBaseDirs: [],
            liveBaseDirCandidates: { [containerBase, liveBase] }
        )

        XCTAssertTrue(bridge.publishAliasHeartbeat(fallbackStatus: makeFallbackStatus(baseDir: containerBase, now: now), now: now + 0.1))

        let object = try readJSONObject(containerBase.appendingPathComponent("hub_status.json"))
        XCTAssertEqual(object["baseDir"] as? String, liveBase.path)
        XCTAssertEqual((object["swiftShellBridge"] as? [String: Any])?["rust_live_base_dir"] as? String, liveBase.path)
    }

    func testUsesHTTPHealthFallbackWhenLiveStatusFileIsUnavailable() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let containerBase = root.appendingPathComponent("container/RELFlowHub", isDirectory: true)
        let liveBase = root.appendingPathComponent("RELFlowHub", isDirectory: true)
        let now: TimeInterval = 1_778_900_170
        try writeLiveStatus(baseDir: containerBase, now: now)

        let bridge = RustLiveFileIPCBridge(
            appBaseDir: containerBase,
            appEventsDir: containerBase.appendingPathComponent("ipc_events", isDirectory: true),
            appResponsesDir: containerBase.appendingPathComponent("ipc_responses", isDirectory: true),
            appStatusFile: containerBase.appendingPathComponent("hub_status.json"),
            compatBaseDirs: [],
            liveBaseDirCandidates: { [containerBase] },
            httpLiveStatusOverride: { overrideNow in
                RustLiveFileIPCBridge.LiveStatus(
                    raw: [
                        "updatedAt": overrideNow,
                        "ipcMode": "file",
                        "ipcPath": liveBase.appendingPathComponent("ipc_events", isDirectory: true).path,
                        "baseDir": liveBase.path,
                        "protocolVersion": 1,
                        "rustHub": [
                            "schema_version": "xhub.rust_hub.xt_classic_status.v1",
                            "authority": "swift_shell_http_health_fallback",
                        ],
                    ],
                    baseDir: liveBase,
                    eventsDir: liveBase.appendingPathComponent("ipc_events", isDirectory: true),
                    responsesDir: liveBase.appendingPathComponent("ipc_responses", isDirectory: true),
                    updatedAt: overrideNow
                )
            }
        )

        XCTAssertTrue(bridge.publishAliasHeartbeat(fallbackStatus: makeFallbackStatus(baseDir: containerBase, now: now), now: now + 0.1))

        let object = try readJSONObject(containerBase.appendingPathComponent("hub_status.json"))
        XCTAssertEqual(object["baseDir"] as? String, liveBase.path)
        XCTAssertEqual((object["rustHub"] as? [String: Any])?["authority"] as? String, "swift_shell_http_health_fallback")
    }

    func testForwardsCompatibilityBaseKernelEventAndMirrorsResponse() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let containerBase = root.appendingPathComponent("container/RELFlowHub", isDirectory: true)
        let compatBase = root.appendingPathComponent("Library/Group Containers/group.rel.flowhub", isDirectory: true)
        let liveBase = root.appendingPathComponent("RELFlowHub", isDirectory: true)
        let compatEvents = compatBase.appendingPathComponent("ipc_events", isDirectory: true)
        let compatResponses = compatBase.appendingPathComponent("ipc_responses", isDirectory: true)
        let containerResponses = containerBase.appendingPathComponent("ipc_responses", isDirectory: true)
        let liveEvents = liveBase.appendingPathComponent("ipc_events", isDirectory: true)
        let liveResponses = liveBase.appendingPathComponent("ipc_responses", isDirectory: true)
        let now: TimeInterval = 1_778_900_175
        try writeLiveStatus(baseDir: liveBase, now: now)
        try FileManager.default.createDirectory(at: compatEvents, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: liveResponses, withIntermediateDirectories: true)

        let event = compatEvents.appendingPathComponent("event_memory_compat.json")
        try #"{"type":"memory_retrieval","reqId":"req-compat","memory_retrieval":{"query":"hello"}}"#
            .write(to: event, atomically: true, encoding: .utf8)

        let bridge = makeBridge(appBase: containerBase, liveBase: liveBase, compatBaseDirs: [compatBase])
        XCTAssertTrue(bridge.bridgeDropboxes(now: now + 0.1))

        XCTAssertFalse(FileManager.default.fileExists(atPath: event.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: liveEvents.appendingPathComponent("event_memory_compat.json").path))

        let liveResponse = liveResponses.appendingPathComponent("resp_req-compat.json")
        try #"{"type":"memory_retrieval_ack","reqId":"req-compat","ok":true}"#
            .write(to: liveResponse, atomically: true, encoding: .utf8)

        XCTAssertTrue(bridge.bridgeDropboxes(now: now + 0.2))
        XCTAssertTrue(FileManager.default.fileExists(atPath: compatResponses.appendingPathComponent("resp_req-compat.json").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: containerResponses.appendingPathComponent("resp_req-compat.json").path))
    }

    func testLeavesSwiftShellEventForLocalHandler() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let appBase = root.appendingPathComponent("group.rel.flowhub", isDirectory: true)
        let liveBase = root.appendingPathComponent("RELFlowHub", isDirectory: true)
        let appEvents = appBase.appendingPathComponent("ipc_events", isDirectory: true)
        let liveEvents = liveBase.appendingPathComponent("ipc_events", isDirectory: true)
        let now: TimeInterval = 1_778_900_200
        try writeLiveStatus(baseDir: liveBase, now: now)
        try FileManager.default.createDirectory(at: appEvents, withIntermediateDirectories: true)

        let event = appEvents.appendingPathComponent("event_notification.json")
        try #"{"type":"push_notification","notification":{"title":"Hi"}}"#
            .write(to: event, atomically: true, encoding: .utf8)

        let bridge = makeBridge(appBase: appBase, liveBase: liveBase)
        XCTAssertTrue(bridge.bridgeDropboxes(now: now + 0.1))

        XCTAssertTrue(FileManager.default.fileExists(atPath: event.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: liveEvents.appendingPathComponent("event_notification.json").path))
    }

    func testNoOpWhenLiveBaseMatchesAppBase() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let appBase = root.appendingPathComponent("RELFlowHub", isDirectory: true)
        let now: TimeInterval = 1_778_900_300
        try writeLiveStatus(baseDir: appBase, now: now)

        let bridge = makeBridge(appBase: appBase, liveBase: appBase)
        XCTAssertFalse(bridge.publishAliasHeartbeat(fallbackStatus: makeFallbackStatus(baseDir: appBase, now: now), now: now + 0.1))
        XCTAssertFalse(bridge.bridgeDropboxes(now: now + 0.1))
    }

    private func makeBridge(appBase: URL, liveBase: URL, compatBaseDirs: [URL]? = []) -> RustLiveFileIPCBridge {
        RustLiveFileIPCBridge(
            appBaseDir: appBase,
            appEventsDir: appBase.appendingPathComponent("ipc_events", isDirectory: true),
            appResponsesDir: appBase.appendingPathComponent("ipc_responses", isDirectory: true),
            appStatusFile: appBase.appendingPathComponent("hub_status.json"),
            compatBaseDirs: compatBaseDirs,
            liveBaseDirCandidates: { [liveBase] },
            httpLiveStatusOverride: { _ in nil },
            runCompatibilityWorkInline: true
        )
    }

    private func makeFallbackStatus(baseDir: URL, now: TimeInterval) -> HubStatus {
        HubStatus(
            pid: 42,
            startedAt: now - 10,
            updatedAt: now,
            ipcMode: "file",
            ipcPath: baseDir.appendingPathComponent("ipc_events", isDirectory: true).path,
            baseDir: baseDir.path,
            protocolVersion: 1,
            appVersion: "9.8.7",
            appBuild: "654",
            appPath: "/Applications/X-Hub.app",
            aiReady: true,
            loadedModelCount: 2,
            modelsUpdatedAt: now - 1
        )
    }

    private func writeLiveStatus(baseDir: URL, now: TimeInterval) throws {
        try FileManager.default.createDirectory(
            at: baseDir.appendingPathComponent("ipc_events", isDirectory: true),
            withIntermediateDirectories: true
        )
        let object: [String: Any] = [
            "pid": 77,
            "startedAt": now - 20,
            "updatedAt": now,
            "ipcMode": "file",
            "ipcPath": baseDir.appendingPathComponent("ipc_events", isDirectory: true).path,
            "baseDir": baseDir.path,
            "protocolVersion": 1,
            "aiReady": true,
            "loadedModelCount": 0,
            "modelsUpdatedAt": now - 2,
            "rustHub": [
                "schema_version": "xhub.rust_hub.xt_classic_status.v1",
                "authority": "explicit_cutover_only",
                "http_addr": "127.0.0.1:50151",
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        try data.write(to: baseDir.appendingPathComponent("hub_status.json"), options: .atomic)
    }

    private func readJSONObject(_ url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("RustLiveFileIPCBridgeTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
