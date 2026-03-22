import Foundation
import Testing
@testable import XTerminal

@Suite(.serialized)
struct SupervisorPortfolioSnapshotSyncTests {
    private static let gate = HubGlobalStateTestGate.shared

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

    @Test
    func hubIpcClientWritesSupervisorPortfolioSnapshotAsDeviceCanonicalMemory() async throws {
        try await Self.gate.run {
            let base = FileManager.default.temporaryDirectory.appendingPathComponent("xt_w331_portfolio_sync_\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            try writeTestHubStatus(base: base)
            HubPaths.setBaseDirOverride(base)
            let previousTransportMode = HubAIClient.transportMode()
            HubAIClient.setTransportMode(.fileIPC)
            defer {
                HubAIClient.setTransportMode(previousTransportMode)
                HubPaths.setBaseDirOverride(nil)
                try? FileManager.default.removeItem(at: base)
            }

            let snapshot = SupervisorPortfolioSnapshot(
                updatedAt: 1_773_700_500,
                counts: SupervisorPortfolioProjectCounts(active: 2, blocked: 1, awaitingAuthorization: 0, completed: 1, idle: 0),
                criticalQueue: [
                    SupervisorPortfolioCriticalQueueItem(
                        projectId: "p-blocked",
                        projectName: "Blocked Project",
                        reason: "Missing require-real sample",
                        severity: .briefCard,
                        nextAction: "Run RR02"
                    )
                ],
                projects: [
                    SupervisorPortfolioProjectCard(
                        projectId: "p-blocked",
                        displayName: "Blocked Project",
                        projectState: .blocked,
                        runtimeState: "阻塞中",
                        currentAction: "等待 RR02 样本",
                        topBlocker: "Missing require-real sample",
                        nextStep: "Run RR02",
                        memoryFreshness: .ttlCached,
                        updatedAt: 1_773_700_400,
                        recentMessageCount: 3
                    )
                ]
            )

            HubIPCClient.syncSupervisorPortfolioSnapshot(
                snapshot,
                supervisorId: "supervisor-main",
                displayName: "Supervisor"
            )

            let eventDir = base.appendingPathComponent("ipc_events", isDirectory: true)
            let files = try FileManager.default.contentsOfDirectory(at: eventDir, includingPropertiesForKeys: nil)
                .filter { $0.lastPathComponent.hasPrefix("xterminal_device_memory_") }
            #expect(files.count == 1)

            let data = try Data(contentsOf: files[0])
            let decoded = try JSONDecoder().decode(HubIPCClient.DeviceCanonicalMemoryIPCRequest.self, from: data)
            #expect(decoded.type == "device_canonical_memory")
            #expect(decoded.deviceCanonicalMemory.supervisorId == "supervisor-main")
            #expect(decoded.deviceCanonicalMemory.displayName == "Supervisor")

            let lookup = Dictionary(uniqueKeysWithValues: decoded.deviceCanonicalMemory.items.map { ($0.key, $0.value) })
            #expect(lookup["xterminal.supervisor.portfolio.project_counts.blocked"] == "1")
            #expect(lookup["xterminal.supervisor.portfolio.critical_queue_count"] == "1")
            #expect(lookup["xterminal.supervisor.portfolio.summary_json"]?.contains("\"supervisor_id\":\"supervisor-main\"") == true)
        }
    }

    @Test
    func hubIpcClientRecordsFailedDeviceCanonicalSyncStatusWhenLocalWriteFails() async throws {
        try await Self.gate.run {
            let base = FileManager.default.temporaryDirectory.appendingPathComponent("xt_w331_portfolio_sync_failure_\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            try writeTestHubStatus(base: base)
            HubPaths.setBaseDirOverride(base)
            let previousTransportMode = HubAIClient.transportMode()
            HubAIClient.setTransportMode(.fileIPC)
            installScopedDeviceMemoryWriteFailureOverride(base: base)
            defer {
                HubIPCClient.resetIPCEventWriteOverrideForTesting()
                HubAIClient.setTransportMode(previousTransportMode)
                HubPaths.setBaseDirOverride(nil)
                try? FileManager.default.removeItem(at: base)
            }

            let snapshot = SupervisorPortfolioSnapshot(
                updatedAt: 1_773_700_500,
                counts: SupervisorPortfolioProjectCounts(active: 1, blocked: 0, awaitingAuthorization: 0, completed: 0, idle: 0),
                criticalQueue: [],
                projects: [
                    SupervisorPortfolioProjectCard(
                        projectId: "p-alpha",
                        displayName: "Alpha",
                        projectState: .active,
                        runtimeState: "推进中",
                        currentAction: "Sync status",
                        topBlocker: "",
                        nextStep: "Observe failure",
                        memoryFreshness: .fresh,
                        updatedAt: 1_773_700_400,
                        recentMessageCount: 1
                    )
                ]
            )

            HubIPCClient.syncSupervisorPortfolioSnapshot(
                snapshot,
                supervisorId: "supervisor-main",
                displayName: "Supervisor"
            )

            let status = try #require(HubIPCClient.canonicalMemorySyncStatusSnapshot(limit: 10))
            let item = try #require(status.items.first { $0.scopeKind == "device" && $0.scopeId == "supervisor-main" })
            #expect(item.ok == false)
            #expect(item.source == "file_ipc")
            #expect(item.reasonCode == "device_canonical_memory_write_failed")
            #expect(item.detail?.contains("xterminal_device_memory_write_failed") == true)
        }
    }

    private func installScopedDeviceMemoryWriteFailureOverride(base: URL) {
        let scopedBasePath = base.path
        HubIPCClient.installIPCEventWriteOverrideForTesting { data, tmpURL, finalURL in
            if finalURL.path.hasPrefix(scopedBasePath),
               finalURL.lastPathComponent.hasPrefix("xterminal_device_memory_") {
                throw NSError(domain: NSPOSIXErrorDomain, code: 28)
            }
            try data.write(to: tmpURL, options: .atomic)
            try FileManager.default.moveItem(at: tmpURL, to: finalURL)
        }
    }
}
