import Foundation
import Testing
@testable import XTerminal

@Suite(.serialized)
@MainActor
struct SupervisorCanonicalMemoryRetryTests {
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

    private func withCanonicalRetryTestEnvironment(
        _ operation: @MainActor (URL) async throws -> Void
    ) async throws {
        try await Self.gate.runOnMainActor { @MainActor in
            let base = FileManager.default.temporaryDirectory
                .appendingPathComponent("xt_supervisor_canonical_retry_\(UUID().uuidString)", isDirectory: true)
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

            try await operation(base)
        }
    }

    private func makeManagerWithCanonicalRetryFixture() -> SupervisorManager {
        let manager = SupervisorManager.makeForTesting()
        let digest = SupervisorManager.SupervisorMemoryProjectDigest(
            projectId: "project-alpha",
            displayName: "Alpha",
            runtimeState: "active",
            source: "hub",
            goal: "Ship governed supervisor memory",
            currentState: "doctor sees canonical sync risk",
            nextStep: "retry canonical sync from Supervisor",
            blocker: "(none)",
            updatedAt: 1_773_800_200,
            recentMessageCount: 4
        )
        let portfolioSnapshot = SupervisorPortfolioSnapshot(
            updatedAt: 1_773_800_300,
            counts: SupervisorPortfolioProjectCounts(
                active: 1,
                blocked: 0,
                awaitingAuthorization: 0,
                completed: 0,
                idle: 0
            ),
            criticalQueue: [],
            projects: [
                SupervisorPortfolioProjectCard(
                    projectId: "project-alpha",
                    displayName: "Alpha",
                    projectState: .active,
                    runtimeState: "推进中",
                    currentAction: "重推 canonical sync",
                    topBlocker: "Hub status lagging",
                    nextStep: "verify Doctor board",
                    memoryFreshness: .fresh,
                    updatedAt: 1_773_800_250,
                    recentMessageCount: 4
                )
            ]
        )
        manager.setSupervisorCanonicalMemoryRetryStateForTesting(
            digests: [digest],
            portfolioSnapshot: portfolioSnapshot
        )
        return manager
    }

    @Test
    func retryCanonicalMemorySyncNowReplaysPortfolioAndProjectCapsules() async throws {
        try await withCanonicalRetryTestEnvironment { base in
            let manager = makeManagerWithCanonicalRetryFixture()

            manager.retryCanonicalMemorySyncNow()

            let eventDir = base.appendingPathComponent("ipc_events", isDirectory: true)
            let files = try FileManager.default.contentsOfDirectory(
                at: eventDir,
                includingPropertiesForKeys: nil
            )
            let projectFiles = files.filter { $0.lastPathComponent.hasPrefix("xterminal_project_memory_") }
            let deviceFiles = files.filter { $0.lastPathComponent.hasPrefix("xterminal_device_memory_") }
            #expect(projectFiles.count == 1)
            #expect(deviceFiles.count == 1)

            #expect(manager.canonicalMemoryRetryFeedback?.tone == .success)
            #expect(manager.canonicalMemoryRetryFeedback?.statusLine == "canonical_sync_retry: ok scopes=2 · projects=1")
            #expect(manager.canonicalMemoryRetryFeedback?.detailLine?.contains("project:project-alpha(Alpha)") == true)

            let status = try #require(HubIPCClient.canonicalMemorySyncStatusSnapshot(limit: 10))
            #expect(status.items.contains(where: {
                $0.scopeKind == "project" &&
                $0.scopeId == "project-alpha" &&
                $0.ok
            }))
            #expect(status.items.contains(where: {
                $0.scopeKind == "device" &&
                $0.ok
            }))
        }
    }

    @Test
    func localPreflightSlashCommandRetriesCanonicalSync() async throws {
        try await withCanonicalRetryTestEnvironment { base in
            let manager = makeManagerWithCanonicalRetryFixture()

            let reply = await manager.directSupervisorLocalPreflightReplyIfApplicableForTesting("/canonical sync retry")

            let text = try #require(reply)
            let supervisorId = HubIPCClient.defaultSupervisorCanonicalID()
            #expect(text.contains("已触发 canonical memory 重试。"))
            #expect(text.contains("canonical_sync_retry: ok scopes=2 · projects=1"))
            #expect(text.contains("canonical_sync_retry_meta：attempt:"))
            #expect(text.contains("canonical_sync_retry_detail：ok: device:\(supervisorId)(Supervisor), project:project-alpha(Alpha)"))

            let eventDir = base.appendingPathComponent("ipc_events", isDirectory: true)
            let files = try FileManager.default.contentsOfDirectory(
                at: eventDir,
                includingPropertiesForKeys: nil
            )
            #expect(files.contains(where: { $0.lastPathComponent.hasPrefix("xterminal_project_memory_") }))
            #expect(files.contains(where: { $0.lastPathComponent.hasPrefix("xterminal_device_memory_") }))
        }
    }

    @Test
    func localPreflightNaturalLanguageRetriesCanonicalSync() async throws {
        try await withCanonicalRetryTestEnvironment { _ in
            let manager = makeManagerWithCanonicalRetryFixture()

            let reply = await manager.directSupervisorLocalPreflightReplyIfApplicableForTesting("请帮我重试 canonical sync，并把项目记忆重新同步一下")

            let text = try #require(reply)
            #expect(text.contains("已触发 canonical memory 重试。"))
            #expect(text.contains("canonical_sync_retry: ok scopes=2 · projects=1"))
            #expect(text.contains("canonical_sync_retry_meta：attempt:"))
            #expect(manager.canonicalMemoryRetryFeedback?.detailLine?.contains("project:project-alpha(Alpha)") == true)
            #expect(manager.canonicalMemoryRetryFeedback?.metaLine?.contains("attempt:") == true)
        }
    }
}
