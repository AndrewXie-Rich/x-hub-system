import Darwin
import Foundation
import Testing
@testable import XTerminal

@Suite(.serialized)
struct HubIPCClientProjectCanonicalMemorySyncTests {
    private static let gate = HubGlobalStateTestGate.shared

    @Test
    func syncProjectCanonicalMemoryUsesFriendlyRegistryNameInPayloadAndCanonicalItems() async throws {
        try await Self.gate.run {
            let hubBase = FileManager.default.temporaryDirectory
                .appendingPathComponent("hub_project_memory_sync_\(UUID().uuidString)", isDirectory: true)
            let projectRoot = FileManager.default.temporaryDirectory
                .appendingPathComponent("hub-project-memory-friendly-\(UUID().uuidString)", isDirectory: true)
            let registryBase = FileManager.default.temporaryDirectory
                .appendingPathComponent("hub_project_memory_registry_\(UUID().uuidString)", isDirectory: true)
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
                let ctx = AXProjectContext(root: projectRoot)
                try ctx.ensureDirs()

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
                            statusDigest: "sync=ready",
                            currentStateSummary: nil,
                            nextStepSummary: nil,
                            blockerSummary: nil,
                            lastSummaryAt: 500,
                            lastEventAt: 500
                        )
                    ]
                )
                AXProjectRegistryStore.save(registry)

                var memory = AXMemory.new(
                    projectName: projectRoot.lastPathComponent,
                    projectRoot: projectRoot.path
                )
                memory.goal = "Keep canonical Hub memory aligned with the friendly project identity."
                memory.updatedAt = 1_772_200_222.0

                HubIPCClient.syncProjectCanonicalMemory(ctx: ctx, memory: memory, config: nil)

                let eventDir = hubBase.appendingPathComponent("ipc_events", isDirectory: true)
                let files = try FileManager.default.contentsOfDirectory(at: eventDir, includingPropertiesForKeys: nil)
                    .filter { $0.lastPathComponent.hasPrefix("xterminal_project_memory_") }
                #expect(files.count == 1)

                let data = try Data(contentsOf: files[0])
                let decoded = try JSONDecoder().decode(HubIPCClient.ProjectCanonicalMemoryIPCRequest.self, from: data)
                let payload = decoded.projectCanonicalMemory

                #expect(decoded.type == "project_canonical_memory")
                #expect(payload.projectId == projectId)
                #expect(payload.displayName == friendlyName)
                #expect(payload.displayName != projectRoot.lastPathComponent)

                let lookup = Dictionary(uniqueKeysWithValues: payload.items.map { ($0.key, $0.value) })
                #expect(lookup["xterminal.project.memory.project_name"] == friendlyName)

                let summary = try #require(lookup["xterminal.project.memory.summary_json"])
                let summaryData = try #require(summary.data(using: .utf8))
                let summaryObject = try #require(
                    JSONSerialization.jsonObject(with: summaryData) as? [String: Any]
                )
                #expect(summaryObject["project_name"] as? String == friendlyName)
            }
        }
    }

    @Test
    func syncProjectCanonicalMemoryRecordsFailedSyncStatusWhenLocalWriteFails() async throws {
        try await Self.gate.run {
            let hubBase = FileManager.default.temporaryDirectory
                .appendingPathComponent("hub_project_memory_sync_failure_\(UUID().uuidString)", isDirectory: true)
            let projectRoot = FileManager.default.temporaryDirectory
                .appendingPathComponent("hub-project-memory-failure-\(UUID().uuidString)", isDirectory: true)
            let registryBase = FileManager.default.temporaryDirectory
                .appendingPathComponent("hub_project_memory_registry_failure_\(UUID().uuidString)", isDirectory: true)
            let originalMode = HubAIClient.transportMode()

            try FileManager.default.createDirectory(at: hubBase, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: registryBase, withIntermediateDirectories: true)
            try writeTestHubStatus(base: hubBase)

            HubAIClient.setTransportMode(.fileIPC)
            HubPaths.setPinnedBaseDirOverride(hubBase)
            installScopedProjectMemoryWriteFailureOverride(base: hubBase)
            defer {
                HubAIClient.setTransportMode(originalMode)
                HubIPCClient.resetIPCEventWriteOverrideForTesting()
                HubPaths.clearPinnedBaseDirOverride()
                try? FileManager.default.removeItem(at: hubBase)
                try? FileManager.default.removeItem(at: projectRoot)
                try? FileManager.default.removeItem(at: registryBase)
            }

            try await withTemporaryEnvironment([
                "XTERMINAL_PROJECT_REGISTRY_BASE_DIR": registryBase.path
            ]) {
                let ctx = AXProjectContext(root: projectRoot)
                try ctx.ensureDirs()

                let projectId = AXProjectRegistryStore.projectId(forRoot: projectRoot)
                AXProjectRegistryStore.save(
                    AXProjectRegistry(
                        version: AXProjectRegistry.currentVersion,
                        updatedAt: 500,
                        sortPolicy: "manual_then_last_opened",
                        globalHomeVisible: false,
                        lastSelectedProjectId: projectId,
                        projects: [
                            AXProjectEntry(
                                projectId: projectId,
                                rootPath: projectRoot.path,
                                displayName: "Sync Failure Project",
                                lastOpenedAt: 500,
                                manualOrderIndex: 0,
                                pinned: false,
                                statusDigest: "sync=stale",
                                currentStateSummary: nil,
                                nextStepSummary: nil,
                                blockerSummary: nil,
                                lastSummaryAt: 500,
                                lastEventAt: 500
                            )
                        ]
                    )
                )

                var memory = AXMemory.new(
                    projectName: projectRoot.lastPathComponent,
                    projectRoot: projectRoot.path
                )
                memory.goal = "Surface canonical sync write failures."
                memory.updatedAt = 1_772_200_333.0

                HubIPCClient.syncProjectCanonicalMemory(ctx: ctx, memory: memory, config: nil)

                let snapshot = try #require(HubIPCClient.canonicalMemorySyncStatusSnapshot(limit: 10))
                let item = try #require(snapshot.items.first { $0.scopeId == projectId })
                #expect(item.scopeKind == "project")
                #expect(item.ok == false)
                #expect(item.source == "file_ipc")
                #expect(item.reasonCode == "project_canonical_memory_write_failed")
                #expect(item.detail?.contains("xterminal_project_memory_write_failed") == true)
            }
        }
    }

    private func writeTestHubStatus(base: URL) throws {
        let ipcDir = base.appendingPathComponent("ipc_events", isDirectory: true)
        try FileManager.default.createDirectory(at: ipcDir, withIntermediateDirectories: true)
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

    private func installScopedProjectMemoryWriteFailureOverride(base: URL) {
        let scopedBasePath = base.path
        HubIPCClient.installIPCEventWriteOverrideForTesting { data, tmpURL, finalURL in
            if finalURL.path.hasPrefix(scopedBasePath),
               finalURL.lastPathComponent.hasPrefix("xterminal_project_memory_") {
                throw NSError(domain: NSPOSIXErrorDomain, code: 28)
            }
            try data.write(to: tmpURL, options: .atomic)
            try FileManager.default.moveItem(at: tmpURL, to: finalURL)
        }
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
