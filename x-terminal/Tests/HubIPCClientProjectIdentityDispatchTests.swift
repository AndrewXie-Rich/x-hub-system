import Darwin
import Foundation
import Testing
@testable import XTerminal

@Suite(.serialized)
struct HubIPCClientProjectIdentityDispatchTests {
    @Test
    func syncProjectWritesFriendlyDisplayNameInProjectSyncEvent() async throws {
        let hubBase = FileManager.default.temporaryDirectory
            .appendingPathComponent("hub_project_sync_\(UUID().uuidString)", isDirectory: true)
        let projectRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("project-sync-friendly-\(UUID().uuidString)", isDirectory: true)
        let registryBase = FileManager.default.temporaryDirectory
            .appendingPathComponent("hub_project_sync_registry_\(UUID().uuidString)", isDirectory: true)
        let originalMode = HubAIClient.transportMode()

        try FileManager.default.createDirectory(at: hubBase, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: registryBase, withIntermediateDirectories: true)
        try writeTestHubStatus(base: hubBase)

        HubAIClient.setTransportMode(.fileIPC)
        HubPaths.setPinnedBaseDirOverride(hubBase)
        defer {
            HubAIClient.setTransportMode(originalMode)
            HubPaths.clearPinnedBaseDirOverride()
            try? FileManager.default.removeItem(at: hubBase)
            try? FileManager.default.removeItem(at: projectRoot)
            try? FileManager.default.removeItem(at: registryBase)
        }

        try await withTemporaryEnvironment([
            "XTERMINAL_PROJECT_REGISTRY_BASE_DIR": registryBase.path
        ]) {
            let projectId = AXProjectRegistryStore.projectId(forRoot: projectRoot)
            let friendlyName = "Supervisor 耳机项目"
            let registry = AXProjectRegistry(
                version: AXProjectRegistry.currentVersion,
                updatedAt: 500,
                sortPolicy: "manual_then_last_opened",
                globalHomeVisible: false,
                lastSelectedProjectId: projectId,
                projects: [
                    AXProjectEntry(
                        projectId: projectId,
                        rootPath: projectRoot.path,
                        displayName: friendlyName,
                        lastOpenedAt: 500,
                        manualOrderIndex: 0,
                        pinned: false,
                        statusDigest: "review=ready",
                        currentStateSummary: nil,
                        nextStepSummary: nil,
                        blockerSummary: nil,
                        lastSummaryAt: 500,
                        lastEventAt: 500
                    )
                ]
            )
            AXProjectRegistryStore.save(registry)

            let entry = try #require(AXProjectRegistryStore.load().project(for: projectId))
            HubIPCClient.syncProject(entry)

            let eventURL = try await waitForEventFile(
                in: hubBase.appendingPathComponent("ipc_events", isDirectory: true),
                prefix: "xterminal_"
            )
            let data = try Data(contentsOf: eventURL)
            let decoded = try JSONDecoder().decode(HubIPCClient.IPCRequest.self, from: data)

            #expect(decoded.type == "project_sync")
            #expect(decoded.project.projectId == projectId)
            #expect(decoded.project.rootPath == projectRoot.path)
            #expect(decoded.project.displayName == friendlyName)
            #expect(decoded.project.displayName != projectRoot.lastPathComponent)
            #expect(decoded.project.statusDigest == "review=ready")
        }
    }

    @Test
    func requestNetworkAccessWritesFriendlyDisplayNameInNeedNetworkEvent() async throws {
        let hubBase = FileManager.default.temporaryDirectory
            .appendingPathComponent("hub_need_network_\(UUID().uuidString)", isDirectory: true)
        let projectRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("need-network-friendly-\(UUID().uuidString)", isDirectory: true)
        let registryBase = FileManager.default.temporaryDirectory
            .appendingPathComponent("hub_need_network_registry_\(UUID().uuidString)", isDirectory: true)
        let originalMode = HubAIClient.transportMode()

        try FileManager.default.createDirectory(at: hubBase, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: registryBase, withIntermediateDirectories: true)
        try writeTestHubStatus(base: hubBase)

        HubAIClient.setTransportMode(.fileIPC)
        HubPaths.setPinnedBaseDirOverride(hubBase)
        defer {
            HubAIClient.setTransportMode(originalMode)
            HubPaths.clearPinnedBaseDirOverride()
            try? FileManager.default.removeItem(at: hubBase)
            try? FileManager.default.removeItem(at: projectRoot)
            try? FileManager.default.removeItem(at: registryBase)
        }

        try await withTemporaryEnvironment([
            "XTERMINAL_PROJECT_REGISTRY_BASE_DIR": registryBase.path
        ]) {
            let projectId = AXProjectRegistryStore.projectId(forRoot: projectRoot)
            let friendlyName = "Slack 远程运营项目"
            let registry = AXProjectRegistry(
                version: AXProjectRegistry.currentVersion,
                updatedAt: 600,
                sortPolicy: "manual_then_last_opened",
                globalHomeVisible: false,
                lastSelectedProjectId: projectId,
                projects: [
                    AXProjectEntry(
                        projectId: projectId,
                        rootPath: projectRoot.path,
                        displayName: friendlyName,
                        lastOpenedAt: 600,
                        manualOrderIndex: 0,
                        pinned: false,
                        statusDigest: nil,
                        currentStateSummary: nil,
                        nextStepSummary: nil,
                        blockerSummary: nil,
                        lastSummaryAt: nil,
                        lastEventAt: nil
                    )
                ]
            )
            AXProjectRegistryStore.save(registry)

            let requestTask = Task {
                await HubIPCClient.requestNetworkAccess(
                    root: projectRoot,
                    seconds: 42,
                    reason: "browser_control"
                )
            }

            let eventDir = hubBase.appendingPathComponent("ipc_events", isDirectory: true)
            let eventURL = try await waitForEventFile(in: eventDir, prefix: "xterminal_net_")
            let data = try Data(contentsOf: eventURL)
            let decoded = try JSONDecoder().decode(HubIPCClient.NetworkIPCRequest.self, from: data)

            #expect(decoded.type == "need_network")
            #expect(decoded.network.projectId == projectId)
            #expect(decoded.network.rootPath == AXProjectRegistryStore.normalizedRootPath(projectRoot))
            #expect(decoded.network.displayName == friendlyName)
            #expect(decoded.network.displayName != projectRoot.lastPathComponent)
            #expect(decoded.network.reason == "browser_control")
            #expect(decoded.network.requestedSeconds == 42)

            try writeNetworkResponse(
                base: hubBase,
                reqId: decoded.reqId,
                response: HubIPCClient.NetworkIPCResponse(
                    type: "need_network_ack",
                    reqId: decoded.reqId,
                    ok: true,
                    id: "grant-need-network-1",
                    error: "queued"
                )
            )

            let result = await requestTask.value
            #expect(result.state == .queued)
            #expect(result.source == "file_ipc")
            #expect(result.reasonCode == "queued")
            #expect(result.grantRequestId == "grant-need-network-1")
        }
    }

    private func writeTestHubStatus(base: URL) throws {
        let ipcDir = base.appendingPathComponent("ipc_events", isDirectory: true)
        let responseDir = base.appendingPathComponent("ipc_responses", isDirectory: true)
        try FileManager.default.createDirectory(at: ipcDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: responseDir, withIntermediateDirectories: true)
        let status = HubStatus(
            pid: nil,
            startedAt: Date().timeIntervalSince1970,
            updatedAt: Date().timeIntervalSince1970,
            ipcMode: "file",
            ipcPath: ipcDir.path,
            baseDir: base.path,
            protocolVersion: 1,
            aiReady: true,
            loadedModelCount: 0,
            modelsUpdatedAt: Date().timeIntervalSince1970
        )
        let data = try JSONEncoder().encode(status)
        try data.write(to: base.appendingPathComponent("hub_status.json"), options: .atomic)
    }

    private func writeNetworkResponse(
        base: URL,
        reqId: String,
        response: HubIPCClient.NetworkIPCResponse
    ) throws {
        let responseDir = base.appendingPathComponent("ipc_responses", isDirectory: true)
        try FileManager.default.createDirectory(at: responseDir, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(response)
        try data.write(
            to: responseDir.appendingPathComponent("resp_\(reqId).json"),
            options: .atomic
        )
    }
}

private func currentEnvironmentValue(_ key: String) -> String? {
    guard let value = getenv(key) else { return nil }
    return String(cString: value)
}

private func withTemporaryEnvironment<T>(
    _ overrides: [String: String?],
    operation: () async throws -> T
) async rethrows -> T {
    let original = Dictionary(uniqueKeysWithValues: overrides.keys.map { ($0, currentEnvironmentValue($0)) })
    for (key, value) in overrides {
        if let value {
            setenv(key, value, 1)
        } else {
            unsetenv(key)
        }
    }
    defer {
        for (key, value) in original {
            if let value {
                setenv(key, value, 1)
            } else {
                unsetenv(key)
            }
        }
    }
    return try await operation()
}

private func waitForEventFile(
    in directory: URL,
    prefix: String,
    timeoutMs: UInt64 = 5_000
) async throws -> URL {
    let deadline = Date().timeIntervalSince1970 + (Double(timeoutMs) / 1_000.0)
    while Date().timeIntervalSince1970 < deadline {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )) ?? []
        if let match = files.first(where: {
            let name = $0.lastPathComponent
            return name.hasPrefix(prefix) && !name.hasPrefix(".")
        }) {
            return match
        }
        try await Task.sleep(nanoseconds: 20_000_000)
    }
    Issue.record("Timed out waiting for IPC event file with prefix \(prefix).")
    throw CancellationError()
}
