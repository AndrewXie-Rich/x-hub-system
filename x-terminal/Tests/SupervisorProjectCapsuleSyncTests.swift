import Foundation
import Testing
@testable import XTerminal

@MainActor
struct SupervisorProjectCapsuleSyncTests {
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
    func hubIpcClientWritesSupervisorProjectCapsuleAsProjectCanonicalMemory() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("xt_w331_capsule_sync_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        try writeTestHubStatus(base: base)
        HubPaths.setBaseDirOverride(base)
        defer {
            HubPaths.setBaseDirOverride(nil)
            try? FileManager.default.removeItem(at: base)
        }

        let capsule = SupervisorProjectCapsule(
            schemaVersion: SupervisorProjectCapsule.schemaVersion,
            projectId: "p-sync",
            projectName: "Sync Project",
            projectState: .active,
            goal: "Mirror portfolio capsule to Hub",
            currentPhase: "implementation",
            currentAction: "Writing capsule sync",
            topBlocker: "(无)",
            nextStep: "Verify canonical keys",
            memoryFreshness: .fresh,
            updatedAtMs: 123_000,
            statusDigest: "goal=Mirror portfolio capsule to Hub",
            evidenceRefs: ["build/reports/xt_w3_31_b_project_capsule_evidence.v1.json"],
            auditRef: "supervisor_project_capsule:psync:123000"
        )

        HubIPCClient.syncSupervisorProjectCapsule(capsule)

        let eventDir = base.appendingPathComponent("ipc_events", isDirectory: true)
        let files = try FileManager.default.contentsOfDirectory(at: eventDir, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("xterminal_project_memory_") }
        #expect(files.count == 1)

        let data = try Data(contentsOf: files[0])
        let decoded = try JSONDecoder().decode(HubIPCClient.ProjectCanonicalMemoryIPCRequest.self, from: data)
        #expect(decoded.type == "project_canonical_memory")
        #expect(decoded.projectCanonicalMemory.projectId == "p-sync")

        let lookup = Dictionary(uniqueKeysWithValues: decoded.projectCanonicalMemory.items.map { ($0.key, $0.value) })
        #expect(lookup["xterminal.project.capsule.project_name"] == "Sync Project")
        #expect(lookup["xterminal.project.capsule.current_action"] == "Writing capsule sync")
        #expect(lookup["xterminal.project.capsule.audit_ref"] == "supervisor_project_capsule:psync:123000")
    }
}
