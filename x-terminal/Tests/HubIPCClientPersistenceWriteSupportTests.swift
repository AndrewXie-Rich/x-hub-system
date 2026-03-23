import Foundation
import Testing
@testable import XTerminal

@Suite(.serialized)
struct HubIPCClientPersistenceWriteSupportTests {
    @Test
    func operatorChannelResultSnapshotFallsBackToDirectOverwriteWhenAtomicWriteRunsOutOfSpace() async throws {
        let originalMode = HubAIClient.transportMode()
        let base = try makeTempDirectory("hub_ipc_results")
        defer {
            XTStoreWriteSupport.resetWriteBehaviorForTesting()
            HubAIClient.setTransportMode(originalMode)
            HubPaths.clearPinnedBaseDirOverride()
            try? FileManager.default.removeItem(at: base)
        }

        HubAIClient.setTransportMode(.fileIPC)
        HubPaths.setPinnedBaseDirOverride(base)

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
        #expect(HubIPCClient.appendOperatorChannelXTCommandResult(first))

        let capture = HubIPCWriteCapture()
        installScopedExistingFileOutOfSpaceOverride(root: base, capture: capture)

        let second = HubIPCClient.OperatorChannelXTCommandResultItem(
            commandId: "cmd-1",
            requestId: "req-1",
            actionName: "deploy.plan",
            projectId: "project-a",
            resolvedDeviceId: "device_xt_001",
            status: "completed",
            denyCode: "",
            detail: "completed under pressure",
            runId: "run-1",
            createdAtMs: 1_773_320_100_000,
            completedAtMs: 1_773_320_101_000,
            auditRef: "audit-2"
        )
        #expect(HubIPCClient.appendOperatorChannelXTCommandResult(second))

        let snapshot = await HubIPCClient.requestOperatorChannelXTCommandResults(projectId: "project-a", limit: 10)
        let resolved = try #require(snapshot)
        #expect(resolved.items.count == 1)
        #expect(resolved.items.first?.status == "completed")
        #expect(resolved.items.first?.runId == "run-1")

        let options = capture.writeOptionsSnapshot()
        #expect(options.count == 2)
        #expect(options[0].contains(.atomic))
        #expect(options[1].isEmpty)
    }

    private func makeTempDirectory(_ suffix: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt_hub_ipc_write_\(suffix)_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func installScopedExistingFileOutOfSpaceOverride(root: URL, capture: HubIPCWriteCapture) {
        XTStoreWriteSupport.installWriteAttemptOverrideForTesting { data, url, options in
            if !Self.normalizedPath(url).hasPrefix(Self.normalizedPath(root)) {
                try data.write(to: url, options: options)
                return
            }
            capture.appendWriteOption(options)
            if options.contains(.atomic),
               let existingTarget = Self.existingTargetForAtomicTemp(url),
               FileManager.default.fileExists(atPath: existingTarget.path) {
                throw NSError(domain: NSPOSIXErrorDomain, code: 28)
            }
            try data.write(to: url, options: options)
        }
    }

    private static func existingTargetForAtomicTemp(_ url: URL) -> URL? {
        let name = url.lastPathComponent
        guard name.hasPrefix("."),
              let tempRange = name.range(of: ".tmp-") else {
            return nil
        }
        let targetName = String(name[name.index(after: name.startIndex)..<tempRange.lowerBound])
        guard !targetName.isEmpty else { return nil }
        return url.deletingLastPathComponent().appendingPathComponent(targetName)
    }

    private static func normalizedPath(_ url: URL) -> String {
        url.standardizedFileURL.path.replacingOccurrences(
            of: "/private",
            with: "",
            options: [.anchored]
        )
    }
}

private final class HubIPCWriteCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var writeOptions: [Data.WritingOptions] = []

    func appendWriteOption(_ option: Data.WritingOptions) {
        lock.lock()
        defer { lock.unlock() }
        writeOptions.append(option)
    }

    func writeOptionsSnapshot() -> [Data.WritingOptions] {
        lock.lock()
        defer { lock.unlock() }
        return writeOptions
    }
}
