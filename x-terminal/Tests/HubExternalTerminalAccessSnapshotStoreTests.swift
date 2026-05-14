import Foundation
import Testing
@testable import XTerminal

@Suite(.serialized)
struct HubExternalTerminalAccessSnapshotStoreTests {
    @Test
    func loadRequiresExplicitCompatibilityFallback() throws {
        let tempDir = try makeTempDir(prefix: "external_terminal_access_snapshot_store")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let snapshot = sampleSnapshot()
        try writeSnapshot(snapshot, to: tempDir)

        try withBaseDir(tempDir) {
            #expect(HubExternalTerminalAccessSnapshotStore.load() == nil)

            let fallback = try #require(
                HubExternalTerminalAccessSnapshotStore.load(allowCompatibilityFallback: true)
            )
            #expect(fallback == snapshot)
            #expect(HubExternalTerminalAccessSnapshotStore.load() == snapshot)
        }
    }

    @Test
    func writePrimesPrimaryCachePath() throws {
        let tempDir = try makeTempDir(prefix: "external_terminal_access_snapshot_store_write")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let snapshot = sampleSnapshot(sourceStatus: "fetch_failed")
        withBaseDir(tempDir) {
            HubExternalTerminalAccessSnapshotStore.write(snapshot)
            #expect(HubExternalTerminalAccessSnapshotStore.load() == snapshot)
        }
    }

    private func withBaseDir(
        _ baseDir: URL,
        body: () throws -> Void
    ) rethrows {
        HubPaths.setPinnedBaseDirOverride(baseDir)
        HubPaths.setCandidateBaseDirsOverrideForTesting([baseDir])
        HubExternalTerminalAccessSnapshotStore.resetForTesting()
        defer {
            HubExternalTerminalAccessSnapshotStore.resetForTesting()
            HubPaths.clearPinnedBaseDirOverride()
            HubPaths.setCandidateBaseDirsOverrideForTesting(nil)
        }
        try body()
    }

    private func makeTempDir(prefix: String) throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(prefix, isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func sampleSnapshot(
        sourceStatus: String = "ready"
    ) -> XTUnifiedDoctorExternalTerminalAccessProjection {
        let accessKey = HubAccessKeysClient.AccessKey(
            schemaVersion: "ax.hub.access_key.v1",
            accessKeyID: "ak_live_primary",
            authKind: "bearer",
            status: "ready",
            statusReason: "",
            deviceID: "device_xt",
            userID: "user_primary",
            appID: "xt_terminal",
            name: "XT Export",
            note: "",
            tokenRedacted: "hub_sk_live_***",
            enabled: true,
            createdAtMs: 100,
            updatedAtMs: 200,
            expiresAtMs: 0,
            lastUsedAtMs: 300,
            lastUsedPeerIP: "",
            lastUsedTransport: "",
            revokedAtMs: 0,
            revokeReason: "",
            revokedByUserID: "",
            revokedVia: "",
            createdByUserID: "user_primary",
            createdByAppID: "xt_terminal",
            createdVia: "xt",
            lastRotatedAtMs: 0,
            rotationCount: 0,
            capabilities: ["terminal_connect"],
            scopes: ["hub.connect"],
            allowedCIDRs: [],
            policyMode: "default",
            trustProfilePresent: false,
            connect: nil,
            connectEnvTemplate: "",
            connectEnv: nil
        )
        return XTUnifiedDoctorExternalTerminalAccessProjection(
            accessKeys: [accessKey],
            sourceStatus: sourceStatus,
            observedAt: Date(timeIntervalSince1970: 1),
            dataUpdatedAtMs: 200,
            errorCode: sourceStatus == "ready" ? nil : "fetch_failed",
            errorMessage: sourceStatus == "ready" ? nil : "timeout"
        )
    }

    private func writeSnapshot(
        _ snapshot: XTUnifiedDoctorExternalTerminalAccessProjection,
        to baseDir: URL
    ) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(snapshot)
        try data.write(
            to: baseDir.appendingPathComponent("xt_external_terminal_access_snapshot.json"),
            options: [.atomic]
        )
    }
}
