import Foundation
import Testing
@testable import XTerminal

struct HubIPCClientRuntimeSurfaceOverrideSnapshotTests {
    @Test
    func requestRuntimeSurfaceOverridesReadsLocalSnapshotAndFiltersProject() async throws {
        let originalMode = HubAIClient.transportMode()
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt_hub_runtime_surface_snapshot_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)

        HubAIClient.setTransportMode(.fileIPC)
        HubPaths.setPinnedBaseDirOverride(base)
        defer {
            HubAIClient.setTransportMode(originalMode)
            HubPaths.clearPinnedBaseDirOverride()
            try? FileManager.default.removeItem(at: base)
        }

        let payload: [String: Any] = [
            "schema_version": "autonomy_policy_overrides_status.v1",
            "updated_at_ms": 1_773_320_190_000,
            "items": [
                [
                    "project_id": "project-a",
                    "override_mode": "clamp_guided",
                    "updated_at_ms": 1_773_320_150_000,
                    "reason": "hub_browser_only",
                    "audit_ref": "audit-a",
                ],
                [
                    "project_id": "project-b",
                    "override_mode": "kill_switch",
                    "updated_at_ms": 1_773_320_180_000,
                    "reason": "hub_emergency_stop",
                    "audit_ref": "audit-b",
                ],
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        try data.write(to: base.appendingPathComponent("autonomy_policy_overrides_status.json"), options: .atomic)

        let snapshot = await HubIPCClient.requestRuntimeSurfaceOverrides(projectId: "project-a", limit: 10)
        let resolved = try #require(snapshot)

        #expect(resolved.source == "hub_autonomy_policy_overrides_file")
        #expect(resolved.updatedAtMs == 1_773_320_190_000)
        #expect(resolved.items.count == 1)
        #expect(resolved.items.first?.projectId == "project-a")
        #expect(resolved.items.first?.overrideMode == .clampGuided)
        #expect(resolved.items.first?.reason == "hub_browser_only")
        #expect(resolved.items.first?.auditRef == "audit-a")

        let remoteOverride = await HubIPCClient.requestProjectRuntimeSurfaceOverride(projectId: "project-a")
        let resolvedOverride = try #require(remoteOverride)
        #expect(resolvedOverride.projectId == "project-a")
        #expect(resolvedOverride.overrideMode == .clampGuided)
        #expect(resolvedOverride.reason == "hub_browser_only")
        #expect(resolvedOverride.auditRef == "audit-a")
    }
}
