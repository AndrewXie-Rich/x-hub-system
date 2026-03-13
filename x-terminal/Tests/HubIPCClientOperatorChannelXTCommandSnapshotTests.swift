import Foundation
import Testing
@testable import XTerminal

@Suite(.serialized)
struct HubIPCClientOperatorChannelXTCommandSnapshotTests {
    @Test
    func requestOperatorChannelXTCommandsReadsLocalSnapshotAndFiltersProject() async throws {
        let originalMode = HubAIClient.transportMode()
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt_operator_channel_xt_commands_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)

        HubAIClient.setTransportMode(.fileIPC)
        HubPaths.setPinnedBaseDirOverride(base)
        defer {
            HubAIClient.setTransportMode(originalMode)
            HubPaths.clearPinnedBaseDirOverride()
            try? FileManager.default.removeItem(at: base)
        }

        let payload: [String: Any] = [
            "schema_version": "operator_channel_xt_command_queue_status.v1",
            "updated_at_ms": 1_773_320_190_000,
            "items": [
                [
                    "command_id": "cmd-older",
                    "request_id": "req-older",
                    "action_name": "deploy.plan",
                    "scope_type": "project",
                    "scope_id": "project-a",
                    "project_id": "project-a",
                    "provider": "slack",
                    "resolved_device_id": "device_xt_001",
                    "created_at_ms": 1_773_320_010_000,
                    "audit_ref": "audit-cmd-older",
                ],
                [
                    "command_id": "cmd-newer",
                    "request_id": "req-newer",
                    "action_name": "deploy.plan",
                    "scope_type": "project",
                    "scope_id": "project-a",
                    "project_id": "project-a",
                    "provider": "slack",
                    "resolved_device_id": "device_xt_001",
                    "created_at_ms": 1_773_320_080_000,
                    "audit_ref": "audit-cmd-newer",
                ],
                [
                    "command_id": "cmd-other-project",
                    "request_id": "req-other-project",
                    "action_name": "deploy.plan",
                    "scope_type": "project",
                    "scope_id": "project-b",
                    "project_id": "project-b",
                    "provider": "slack",
                    "resolved_device_id": "device_xt_002",
                    "created_at_ms": 1_773_320_090_000,
                    "audit_ref": "audit-cmd-other",
                ],
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        try data.write(to: base.appendingPathComponent("operator_channel_xt_command_queue_status.json"), options: .atomic)

        let snapshot = await HubIPCClient.requestOperatorChannelXTCommands(projectId: "project-a", limit: 10)
        let resolved = try #require(snapshot)

        #expect(resolved.source == "hub_operator_channel_xt_command_file")
        #expect(resolved.updatedAtMs == 1_773_320_190_000)
        #expect(resolved.items.count == 2)
        #expect(resolved.items.map(\.commandId) == ["cmd-newer", "cmd-older"])
        #expect(resolved.items.allSatisfy { $0.projectId == "project-a" })
        #expect(resolved.items.first?.resolvedDeviceId == "device_xt_001")
    }

    @Test
    func appendOperatorChannelXTCommandResultPersistsAndDedupesByCommandID() async throws {
        let originalMode = HubAIClient.transportMode()
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt_operator_channel_xt_results_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)

        HubAIClient.setTransportMode(.fileIPC)
        HubPaths.setPinnedBaseDirOverride(base)
        defer {
            HubAIClient.setTransportMode(originalMode)
            HubPaths.clearPinnedBaseDirOverride()
            try? FileManager.default.removeItem(at: base)
        }

        let first = HubIPCClient.OperatorChannelXTCommandResultItem(
            commandId: "cmd-1",
            requestId: "req-1",
            actionName: "deploy.plan",
            projectId: "project-a",
            resolvedDeviceId: "device_xt_001",
            status: "queued",
            denyCode: "",
            detail: "queued",
            runId: "",
            createdAtMs: 1_773_320_100_000,
            completedAtMs: 1_773_320_100_000,
            auditRef: "audit-1"
        )
        let second = HubIPCClient.OperatorChannelXTCommandResultItem(
            commandId: "cmd-1",
            requestId: "req-1",
            actionName: "deploy.plan",
            projectId: "project-a",
            resolvedDeviceId: "device_xt_001",
            status: "prepared",
            denyCode: "",
            detail: "automation prepared",
            runId: "run-1",
            createdAtMs: 1_773_320_100_000,
            completedAtMs: 1_773_320_101_000,
            auditRef: "audit-1"
        )

        #expect(HubIPCClient.appendOperatorChannelXTCommandResult(first))
        #expect(HubIPCClient.appendOperatorChannelXTCommandResult(second))

        let snapshot = await HubIPCClient.requestOperatorChannelXTCommandResults(projectId: "project-a", limit: 10)
        let resolved = try #require(snapshot)
        #expect(resolved.items.count == 1)
        #expect(resolved.items.first?.commandId == "cmd-1")
        #expect(resolved.items.first?.status == "prepared")
        #expect(resolved.items.first?.runId == "run-1")
    }
}
