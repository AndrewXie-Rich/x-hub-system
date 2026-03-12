import Foundation
import Testing
@testable import XTerminal

@MainActor
struct SupervisorProjectActionAuditTests {
    private func writeTestHubStatus(base: URL) throws {
        let status = HubStatus(
            pid: nil,
            startedAt: Date().timeIntervalSince1970,
            updatedAt: Date().timeIntervalSince1970,
            ipcMode: "grpc",
            ipcPath: nil,
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
    func hubIpcClientWritesProjectActionAuditEvent() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("xt_w331_action_audit_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        try writeTestHubStatus(base: base)
        HubPaths.setBaseDirOverride(base)
        defer {
            HubPaths.setBaseDirOverride(nil)
            try? FileManager.default.removeItem(at: base)
        }

        HubIPCClient.appendSupervisorProjectActionAudit(
            eventID: "evt-1",
            projectID: "p-1",
            projectName: "Project One",
            eventType: "awaiting_authorization",
            severity: "authorization_required",
            actionTitle: "项目待授权：Project One",
            actionSummary: "grant_required",
            whyItMatters: "需要用户批准",
            nextAction: "Approve paid model access",
            occurredAtMs: 123456,
            deliveryChannel: "interrupt_now",
            deliveryStatus: "delivered",
            jurisdictionRole: "owner",
            grantedScope: "capsule_plus_recent",
            auditRef: "project_action_audit:evt-1"
        )

        let eventDir = base.appendingPathComponent("ipc_events", isDirectory: true)
        let files = try FileManager.default.contentsOfDirectory(at: eventDir, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("xterminal_project_action_audit_") }
        #expect(files.count == 1)

        let data = try Data(contentsOf: files[0])
        let decoded = try JSONDecoder().decode(HubIPCClient.SupervisorProjectActionAuditIPCRequest.self, from: data)

        #expect(decoded.type == "supervisor_project_action_audit")
        #expect(decoded.supervisorProjectAction.projectId == "p-1")
        #expect(decoded.supervisorProjectAction.deliveryChannel == "interrupt_now")
        #expect(decoded.supervisorProjectAction.deliveryStatus == "delivered")
        #expect(decoded.supervisorProjectAction.grantedScope == "capsule_plus_recent")
    }

    @Test
    func managerWritesDeliveredAndSuppressedProjectActionAuditRows() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("xt_w331_action_manager_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        try writeTestHubStatus(base: base)
        HubPaths.setBaseDirOverride(base)
        defer {
            HubPaths.setBaseDirOverride(nil)
            try? FileManager.default.removeItem(at: base)
        }

        let now = Date(timeIntervalSince1970: 1_773_600_000).timeIntervalSince1970
        let manager = SupervisorManager.makeForTesting()
        let registry = SupervisorJurisdictionRegistry.ownerDefault(now: now)
            .upserting(projectId: "p-auth", displayName: "Auth Project", role: .owner, now: now)
        _ = manager.applySupervisorJurisdictionRegistry(registry, persist: false, normalizeWithKnownProjects: false)

        let authEntry = AXProjectEntry(
            projectId: "p-auth",
            rootPath: "/tmp/p-auth",
            displayName: "Auth Project",
            lastOpenedAt: now,
            manualOrderIndex: nil,
            pinned: false,
            statusDigest: "grant_required",
            currentStateSummary: "等待授权批准",
            nextStepSummary: "Approve paid model access",
            blockerSummary: "grant_required",
            lastSummaryAt: now,
            lastEventAt: now
        )

        manager.handleEvent(.projectUpdated(authEntry))
        manager.handleEvent(.projectUpdated(authEntry))

        let eventDir = base.appendingPathComponent("ipc_events", isDirectory: true)
        let files = try FileManager.default.contentsOfDirectory(at: eventDir, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("xterminal_project_action_audit_") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        #expect(files.count == 2)

        let payloads = try files.map { file -> HubIPCClient.SupervisorProjectActionAuditIPCRequest in
            let data = try Data(contentsOf: file)
            return try JSONDecoder().decode(HubIPCClient.SupervisorProjectActionAuditIPCRequest.self, from: data)
        }
        let statuses = payloads.map { $0.supervisorProjectAction.deliveryStatus }

        #expect(statuses.contains("delivered"))
        #expect(statuses.contains("suppressed_duplicate"))
    }
}
