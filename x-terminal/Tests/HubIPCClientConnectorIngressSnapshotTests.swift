import Foundation
import Testing
@testable import XTerminal

struct HubIPCClientConnectorIngressSnapshotTests {
    @Test
    func requestConnectorIngressReceiptsReadsLocalSnapshotAndFiltersProject() async throws {
        let originalMode = HubAIClient.transportMode()
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt_hub_connector_ingress_snapshot_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)

        HubAIClient.setTransportMode(.fileIPC)
        HubPaths.setBaseDirOverride(base)
        defer {
            HubAIClient.setTransportMode(originalMode)
            HubPaths.setBaseDirOverride(nil)
            try? FileManager.default.removeItem(at: base)
        }

        let payload: [String: Any] = [
            "schema_version": "connector_ingress_receipts_status.v1",
            "updated_at_ms": 1_773_320_090_000,
            "items": [
                [
                    "receipt_id": "rcpt-older",
                    "request_id": "req-older",
                    "project_id": "project-a",
                    "connector": "slack",
                    "target_id": "dm-001",
                    "ingress_type": "connector_event",
                    "channel_scope": "dm",
                    "source_id": "user-1",
                    "message_id": "msg-older",
                    "dedupe_key": "sha256:older",
                    "received_at_ms": 1_773_320_010_000,
                    "event_sequence": 11,
                    "delivery_state": "accepted",
                    "runtime_state": "queued",
                ],
                [
                    "receipt_id": "rcpt-newer",
                    "request_id": "req-newer",
                    "project_id": "project-a",
                    "connector": "github",
                    "target_id": "repo-1",
                    "ingress_type": "webhook",
                    "channel_scope": "repo",
                    "source_id": "pr-42",
                    "message_id": "msg-newer",
                    "dedupe_key": "sha256:newer",
                    "received_at_ms": 1_773_320_080_000,
                    "event_sequence": 12,
                    "delivery_state": "accepted",
                    "runtime_state": "queued",
                ],
                [
                    "receipt_id": "rcpt-other-project",
                    "request_id": "req-other-project",
                    "project_id": "project-b",
                    "connector": "telegram",
                    "target_id": "chat-7",
                    "ingress_type": "connector_event",
                    "channel_scope": "dm",
                    "source_id": "user-9",
                    "message_id": "msg-other",
                    "dedupe_key": "sha256:other",
                    "received_at_ms": 1_773_320_085_000,
                    "event_sequence": 13,
                    "delivery_state": "accepted",
                    "runtime_state": "queued",
                ],
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        try data.write(to: base.appendingPathComponent("connector_ingress_receipts_status.json"), options: .atomic)

        let snapshot = await HubIPCClient.requestConnectorIngressReceipts(projectId: "project-a", limit: 10)
        let resolved = try #require(snapshot)

        #expect(resolved.source == "hub_connector_ingress_file")
        #expect(resolved.updatedAtMs == 1_773_320_090_000)
        #expect(resolved.items.count == 2)
        #expect(resolved.items.map(\.receiptId) == ["rcpt-newer", "rcpt-older"])
        #expect(resolved.items.allSatisfy { $0.projectId == "project-a" })
        #expect(resolved.items.first?.connector == "github")
        #expect(resolved.items.first?.ingressType == "webhook")
        #expect(resolved.items.first?.eventSequence == 12)
    }
}
