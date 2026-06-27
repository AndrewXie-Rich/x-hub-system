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

    func testMirrorsRuntimeAuthorityFilesToRustLiveBaseBeforeAlias() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let appBase = root.appendingPathComponent("container/RELFlowHub", isDirectory: true)
        let liveBase = root.appendingPathComponent("RELFlowHub", isDirectory: true)
        let now: TimeInterval = 1_778_900_050
        try writeLiveStatus(baseDir: liveBase, now: now - 0.25)
        try writeText(
            #"{"schema_version":"xhub.models_state.v1","updatedAt":1,"models":[]}"#,
            to: liveBase.appendingPathComponent("models_state.json")
        )
        try setModificationDate(Date(timeIntervalSince1970: now - 20), for: liveBase.appendingPathComponent("models_state.json"))

        let modelsState = #"{"schema_version":"xhub.models_state.v1","updatedAt":1778900050,"models":[{"id":"openai/gpt-5.5","name":"GPT 5.5","backend":"openai","state":"available"}]}"#
        let providerKeys = #"{"schema_version":"hub_provider_keys.v1","updated_at_ms":1778900050000,"global_routing_strategy":"fill-first","providers":{"openai":{"routing_strategy":"fill-first","accounts":[{"account_key":"openai:test","provider":"openai","api_key":"sk-test","enabled":true,"models":["openai/gpt-5.5"]}]}}}"#
        try writeText(modelsState, to: appBase.appendingPathComponent("models_state.json"))
        try writeText(providerKeys, to: appBase.appendingPathComponent("hub_provider_keys.json"))
        try setModificationDate(Date(timeIntervalSince1970: now), for: appBase.appendingPathComponent("models_state.json"))
        try setModificationDate(Date(timeIntervalSince1970: now), for: appBase.appendingPathComponent("hub_provider_keys.json"))

        let bridge = makeBridge(appBase: appBase, liveBase: liveBase)
        XCTAssertTrue(bridge.publishAliasHeartbeat(fallbackStatus: makeFallbackStatus(baseDir: appBase, now: now), now: now))

        XCTAssertEqual(try String(contentsOf: liveBase.appendingPathComponent("models_state.json"), encoding: .utf8), modelsState)
        XCTAssertEqual(try String(contentsOf: liveBase.appendingPathComponent("hub_provider_keys.json"), encoding: .utf8), providerKeys)

        let object = try readJSONObject(appBase.appendingPathComponent("hub_status.json"))
        XCTAssertEqual(object["baseDir"] as? String, liveBase.path)
    }

    func testSkipsSwiftRuntimeAuthorityMirrorWhenRustSyncSucceeds() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let appBase = root.appendingPathComponent("container/RELFlowHub", isDirectory: true)
        let liveBase = root.appendingPathComponent("RELFlowHub", isDirectory: true)
        let now: TimeInterval = 1_778_900_075
        try writeLiveStatus(baseDir: liveBase, now: now - 0.25)
        try writeText(
            #"{"schema_version":"xhub.models_state.v1","models":[{"id":"openai/gpt-5.5"}]}"#,
            to: appBase.appendingPathComponent("models_state.json")
        )
        var syncCalls: [(URL, TimeInterval)] = []

        let bridge = RustLiveFileIPCBridge(
            appBaseDir: appBase,
            appEventsDir: appBase.appendingPathComponent("ipc_events", isDirectory: true),
            appResponsesDir: appBase.appendingPathComponent("ipc_responses", isDirectory: true),
            appStatusFile: appBase.appendingPathComponent("hub_status.json"),
            compatBaseDirs: [],
            liveBaseDirCandidates: { [liveBase] },
            httpLiveStatusOverride: { _ in nil },
            runtimeAuthoritySyncOverride: { liveBase, now in
                syncCalls.append((liveBase, now))
                return true
            },
            useRustLiveStatusHTTP: true,
            runCompatibilityWorkInline: true
        )

        XCTAssertTrue(bridge.publishAliasHeartbeat(fallbackStatus: makeFallbackStatus(baseDir: appBase, now: now), now: now))

        XCTAssertEqual(syncCalls.count, 1)
        XCTAssertEqual(syncCalls.first?.0.standardizedFileURL.path, liveBase.standardizedFileURL.path)
        XCTAssertFalse(FileManager.default.fileExists(atPath: liveBase.appendingPathComponent("models_state.json").path))
    }

    func testFallsBackToSwiftRuntimeAuthorityMirrorWhenRustSyncUnavailable() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let appBase = root.appendingPathComponent("container/RELFlowHub", isDirectory: true)
        let liveBase = root.appendingPathComponent("RELFlowHub", isDirectory: true)
        let now: TimeInterval = 1_778_900_080
        try writeLiveStatus(baseDir: liveBase, now: now - 0.25)
        let modelsState = #"{"schema_version":"xhub.models_state.v1","models":[{"id":"openai/gpt-5.5"}]}"#
        try writeText(modelsState, to: appBase.appendingPathComponent("models_state.json"))

        let bridge = RustLiveFileIPCBridge(
            appBaseDir: appBase,
            appEventsDir: appBase.appendingPathComponent("ipc_events", isDirectory: true),
            appResponsesDir: appBase.appendingPathComponent("ipc_responses", isDirectory: true),
            appStatusFile: appBase.appendingPathComponent("hub_status.json"),
            compatBaseDirs: [],
            liveBaseDirCandidates: { [liveBase] },
            httpLiveStatusOverride: { _ in nil },
            runtimeAuthoritySyncOverride: { _, _ in nil },
            useRustLiveStatusHTTP: true,
            runCompatibilityWorkInline: true
        )

        XCTAssertTrue(bridge.publishAliasHeartbeat(fallbackStatus: makeFallbackStatus(baseDir: appBase, now: now), now: now))

        XCTAssertEqual(try String(contentsOf: liveBase.appendingPathComponent("models_state.json"), encoding: .utf8), modelsState)
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
            httpLiveStatusOverride: { _ in nil },
            useRustLiveStatusHTTP: false
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
            liveBaseDirCandidates: { [containerBase, liveBase] },
            useRustLiveStatusHTTP: false
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
            },
            useRustLiveStatusHTTP: false
        )

        XCTAssertTrue(bridge.publishAliasHeartbeat(fallbackStatus: makeFallbackStatus(baseDir: containerBase, now: now), now: now + 0.1))

        let object = try readJSONObject(containerBase.appendingPathComponent("hub_status.json"))
        XCTAssertEqual(object["baseDir"] as? String, liveBase.path)
        XCTAssertEqual((object["rustHub"] as? [String: Any])?["authority"] as? String, "swift_shell_http_health_fallback")
    }

    func testHTTPFallbackRefreshCoalescesConcurrentHotPathCalls() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let containerBase = root.appendingPathComponent("container/RELFlowHub", isDirectory: true)
        let liveBase = root.appendingPathComponent("RELFlowHub", isDirectory: true)
        let now: TimeInterval = 1_778_900_170.5
        try writeLiveStatus(baseDir: containerBase, now: now)

        let started = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let done = DispatchSemaphore(value: 0)
        let lock = NSLock()
        var fallbackCallCount = 0
        var firstResult = false

        let bridge = RustLiveFileIPCBridge(
            appBaseDir: containerBase,
            appEventsDir: containerBase.appendingPathComponent("ipc_events", isDirectory: true),
            appResponsesDir: containerBase.appendingPathComponent("ipc_responses", isDirectory: true),
            appStatusFile: containerBase.appendingPathComponent("hub_status.json"),
            compatBaseDirs: [],
            liveBaseDirCandidates: { [containerBase] },
            httpLiveStatusOverride: { overrideNow in
                lock.lock()
                fallbackCallCount += 1
                lock.unlock()
                started.signal()
                _ = release.wait(timeout: .now() + 2)
                return RustLiveFileIPCBridge.LiveStatus(
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
            },
            useRustLiveStatusHTTP: false
        )

        DispatchQueue.global(qos: .utility).async {
            firstResult = bridge.publishAliasHeartbeat(
                fallbackStatus: self.makeFallbackStatus(baseDir: containerBase, now: now),
                now: now + 0.1
            )
            done.signal()
        }

        XCTAssertEqual(started.wait(timeout: .now() + 2), .success)
        let secondResult = bridge.publishAliasHeartbeat(
            fallbackStatus: makeFallbackStatus(baseDir: containerBase, now: now + 0.02),
            now: now + 0.12
        )
        XCTAssertFalse(secondResult)

        release.signal()
        XCTAssertEqual(done.wait(timeout: .now() + 2), .success)
        XCTAssertTrue(firstResult)
        lock.lock()
        let calls = fallbackCallCount
        lock.unlock()
        XCTAssertEqual(calls, 1)

        let object = try readJSONObject(containerBase.appendingPathComponent("hub_status.json"))
        XCTAssertEqual(object["baseDir"] as? String, liveBase.path)
    }

    func testUsesRecentStaleLiveStatusOnHotPathWhenRefreshIsDue() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let containerBase = root.appendingPathComponent("container/RELFlowHub", isDirectory: true)
        let liveBase = root.appendingPathComponent("RELFlowHub", isDirectory: true)
        let now: TimeInterval = 1_778_900_171
        try writeLiveStatus(baseDir: liveBase, now: now)

        let bridge = RustLiveFileIPCBridge(
            appBaseDir: containerBase,
            appEventsDir: containerBase.appendingPathComponent("ipc_events", isDirectory: true),
            appResponsesDir: containerBase.appendingPathComponent("ipc_responses", isDirectory: true),
            appStatusFile: containerBase.appendingPathComponent("hub_status.json"),
            compatBaseDirs: [],
            liveBaseDirCandidates: { [liveBase] },
            httpLiveStatusOverride: { _ in nil },
            useRustLiveStatusHTTP: false,
            runCompatibilityWorkInline: true
        )

        XCTAssertTrue(bridge.publishAliasHeartbeat(fallbackStatus: makeFallbackStatus(baseDir: containerBase, now: now), now: now + 0.1))
        try FileManager.default.removeItem(at: liveBase.appendingPathComponent("hub_status.json"))

        XCTAssertTrue(bridge.publishAliasHeartbeat(fallbackStatus: makeFallbackStatus(baseDir: containerBase, now: now + 2.4), now: now + 2.4))

        let object = try readJSONObject(containerBase.appendingPathComponent("hub_status.json"))
        XCTAssertEqual(object["baseDir"] as? String, liveBase.path)
        XCTAssertEqual(object["ipcPath"] as? String, liveBase.appendingPathComponent("ipc_events", isDirectory: true).path)
    }

    func testCanPreferRustHTTPLiveStatusBeforeScanningCandidateFiles() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let containerBase = root.appendingPathComponent("container/RELFlowHub", isDirectory: true)
        let liveBase = root.appendingPathComponent("RELFlowHub", isDirectory: true)
        let now: TimeInterval = 1_778_900_172
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
                            "authority": "rust_live_status_http",
                        ],
                    ],
                    baseDir: liveBase,
                    eventsDir: liveBase.appendingPathComponent("ipc_events", isDirectory: true),
                    responsesDir: liveBase.appendingPathComponent("ipc_responses", isDirectory: true),
                    updatedAt: overrideNow
                )
            },
            useRustLiveStatusHTTP: true
        )

        XCTAssertTrue(bridge.publishAliasHeartbeat(fallbackStatus: makeFallbackStatus(baseDir: containerBase, now: now), now: now + 0.1))

        let object = try readJSONObject(containerBase.appendingPathComponent("hub_status.json"))
        XCTAssertEqual(object["baseDir"] as? String, liveBase.path)
        XCTAssertEqual((object["rustHub"] as? [String: Any])?["authority"] as? String, "rust_live_status_http")
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

    func testEventDirectoryCacheInvalidatesWhenNewKernelEventArrives() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let appBase = root.appendingPathComponent("group.rel.flowhub", isDirectory: true)
        let liveBase = root.appendingPathComponent("RELFlowHub", isDirectory: true)
        let appEvents = appBase.appendingPathComponent("ipc_events", isDirectory: true)
        let liveEvents = liveBase.appendingPathComponent("ipc_events", isDirectory: true)
        let now: TimeInterval = 1_778_900_220
        try writeLiveStatus(baseDir: liveBase, now: now)
        try FileManager.default.createDirectory(at: appEvents, withIntermediateDirectories: true)

        let bridge = makeBridge(appBase: appBase, liveBase: liveBase)
        XCTAssertTrue(bridge.bridgeDropboxes(now: now + 0.1))

        let event = appEvents.appendingPathComponent("event_memory_after_idle.json")
        try #"{"type":"memory_retrieval","reqId":"req-after-idle","memory_retrieval":{"query":"later"}}"#
            .write(to: event, atomically: true, encoding: .utf8)

        XCTAssertTrue(bridge.bridgeDropboxes(now: now + 0.2))
        XCTAssertFalse(FileManager.default.fileExists(atPath: event.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: liveEvents.appendingPathComponent("event_memory_after_idle.json").path))
    }

    func testUnsupportedPrimaryEventBackoffDoesNotBlockNewKernelEvent() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let appBase = root.appendingPathComponent("group.rel.flowhub", isDirectory: true)
        let liveBase = root.appendingPathComponent("RELFlowHub", isDirectory: true)
        let appEvents = appBase.appendingPathComponent("ipc_events", isDirectory: true)
        let liveEvents = liveBase.appendingPathComponent("ipc_events", isDirectory: true)
        let now: TimeInterval = 1_778_900_240
        try writeLiveStatus(baseDir: liveBase, now: now)
        try FileManager.default.createDirectory(at: appEvents, withIntermediateDirectories: true)

        let swiftEvent = appEvents.appendingPathComponent("event_notification.json")
        try #"{"type":"push_notification","notification":{"title":"Hi"}}"#
            .write(to: swiftEvent, atomically: true, encoding: .utf8)

        let bridge = makeBridge(appBase: appBase, liveBase: liveBase)
        XCTAssertTrue(bridge.bridgeDropboxes(now: now + 0.1))
        XCTAssertTrue(FileManager.default.fileExists(atPath: swiftEvent.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: liveEvents.appendingPathComponent("event_notification.json").path))

        let kernelEvent = appEvents.appendingPathComponent("event_memory_after_swift.json")
        try #"{"type":"memory_retrieval","reqId":"req-after-swift","memory_retrieval":{"query":"kernel"}}"#
            .write(to: kernelEvent, atomically: true, encoding: .utf8)

        XCTAssertTrue(bridge.bridgeDropboxes(now: now + 0.2))
        XCTAssertTrue(FileManager.default.fileExists(atPath: swiftEvent.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: kernelEvent.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: liveEvents.appendingPathComponent("event_memory_after_swift.json").path))
    }

    func testIgnoredEventBackoffAllowsReusedPathWithNewModificationTime() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let appBase = root.appendingPathComponent("group.rel.flowhub", isDirectory: true)
        let liveBase = root.appendingPathComponent("RELFlowHub", isDirectory: true)
        let appEvents = appBase.appendingPathComponent("ipc_events", isDirectory: true)
        let liveEvents = liveBase.appendingPathComponent("ipc_events", isDirectory: true)
        let now: TimeInterval = 1_778_900_260
        try writeLiveStatus(baseDir: liveBase, now: now)
        try FileManager.default.createDirectory(at: appEvents, withIntermediateDirectories: true)

        let reusedEvent = appEvents.appendingPathComponent("event_reused.json")
        try #"{"type":"push_notification","notification":{"title":"Hi"}}"#
            .write(to: reusedEvent, atomically: true, encoding: .utf8)

        let bridge = makeBridge(appBase: appBase, liveBase: liveBase)
        XCTAssertTrue(bridge.bridgeDropboxes(now: now + 0.1))
        XCTAssertTrue(FileManager.default.fileExists(atPath: reusedEvent.path))

        try FileManager.default.removeItem(at: reusedEvent)
        try #"{"type":"memory_retrieval","reqId":"req-reused","memory_retrieval":{"query":"reused"}}"#
            .write(to: reusedEvent, atomically: true, encoding: .utf8)
        try setModificationDate(Date(timeIntervalSince1970: now + 1), for: reusedEvent)

        XCTAssertTrue(bridge.bridgeDropboxes(now: now + 0.2))
        XCTAssertFalse(FileManager.default.fileExists(atPath: reusedEvent.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: liveEvents.appendingPathComponent("event_reused.json").path))
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
            useRustLiveStatusHTTP: false,
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

    private func writeText(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private func setModificationDate(_ date: Date, for url: URL) throws {
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("RustLiveFileIPCBridgeTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
