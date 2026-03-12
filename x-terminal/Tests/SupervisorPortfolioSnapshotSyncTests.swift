import Foundation
import Testing
@testable import XTerminal

struct SupervisorPortfolioSnapshotSyncTests {
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
    func hubIpcClientWritesSupervisorPortfolioSnapshotAsDeviceCanonicalMemory() throws {
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
