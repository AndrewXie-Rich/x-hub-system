import Foundation
import Testing

struct HubRuntimeSurfaceCompatibilityBoundaryTests {
    @Test
    func hubIPCClientKeepsRuntimeSurfaceAsPrimaryNaming() throws {
        let source = try String(
            contentsOf: repoRoot().appendingPathComponent("x-terminal/Sources/Hub/HubIPCClient.swift"),
            encoding: .utf8
        )

        #expect(source.contains("struct RuntimeSurfaceOverrideItem"))
        #expect(source.contains("struct RuntimeSurfaceOverridesSnapshot"))
        #expect(source.contains("requestRuntimeSurfaceOverrides("))
        #expect(source.contains("requestProjectRuntimeSurfaceOverride("))

        #expect(source.contains("Use requestRuntimeSurfaceOverrides(projectId:limit:bypassCache:)"))
        #expect(source.contains("Use requestProjectRuntimeSurfaceOverride(projectId:bypassCache:)"))
        #expect(source.contains("Use RuntimeSurfaceOverrideItem"))
        #expect(source.contains("Use RuntimeSurfaceOverridesSnapshot"))

        #expect(!source.contains("LocalAutonomyPolicyOverrideItem"))
        #expect(!source.contains("LocalAutonomyPolicyOverridesSnapshotFile"))

        #expect(source.contains("autonomy_policy_overrides_status.json"))
        #expect(source.contains("hub_autonomy_policy_overrides_file"))
    }

    @Test
    func hubPairingCoordinatorKeepsRuntimeSurfaceAsPrimaryNaming() throws {
        let source = try String(
            contentsOf: repoRoot().appendingPathComponent("x-terminal/Sources/Hub/HubPairingCoordinator.swift"),
            encoding: .utf8
        )

        #expect(source.contains("func fetchRemoteRuntimeSurfaceOverrides("))
        #expect(source.contains("private func remoteRuntimeSurfaceOverridesScriptSource()"))
        #expect(source.contains("Use fetchRemoteRuntimeSurfaceOverrides(options:projectId:limit:)"))
        #expect(source.contains("Use remoteRuntimeSurfaceOverridesScriptSource()"))

        #expect(source.contains("typealias HubRemoteAutonomyPolicyOverrideItem = HubRemoteRuntimeSurfaceOverrideItem"))
        #expect(source.contains("typealias HubRemoteAutonomyPolicyOverridesResult = HubRemoteRuntimeSurfaceOverridesResult"))

        #expect(source.contains("HubRemoteRuntimeSurfaceCompatContract"))
        #expect(source.contains("static let grpcMethod = \"GetAutonomyPolicyOverrides\""))
        #expect(source.contains("remote_autonomy_policy_overrides_failed"))
    }

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
