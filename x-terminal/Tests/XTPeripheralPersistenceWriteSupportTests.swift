import Foundation
import Testing
@testable import XTerminal

@Suite(.serialized)
struct XTPeripheralPersistenceWriteSupportTests {
    @MainActor
    @Test
    func settingsStoreFallsBackToDirectOverwriteWhenAtomicWriteRunsOutOfSpace() throws {
        let settingsRoot = try makeTempDirectory("settings_store")
        let voiceRoot = try makeTempDirectory("settings_store_voice")
        defer {
            XTStoreWriteSupport.resetWriteBehaviorForTesting()
            try? FileManager.default.removeItem(at: settingsRoot)
            try? FileManager.default.removeItem(at: voiceRoot)
        }

        let voiceStore = VoiceWakeProfileStore(
            url: voiceRoot.appendingPathComponent("voice_wake_profile.json"),
            syncClient: MockPeripheralVoiceWakeSyncClient(),
            nowProvider: { Date(timeIntervalSince1970: 10_000) }
        )
        let settingsURL = settingsRoot.appendingPathComponent("settings.json")
        let store = SettingsStore(
            url: settingsURL,
            voiceWakeProfileStore: voiceStore
        )
        store.save()

        let capture = XTPeripheralWriteCapture()
        installScopedExistingFileOutOfSpaceOverride(root: settingsRoot, capture: capture)

        store.settings = store.settings.setting(
            supervisorPrompt: SupervisorPromptPreferences(
                identityName: "Mira",
                roleSummary: "Strategic reviewer.",
                toneDirectives: "Direct.",
                extraSystemPrompt: "Keep the project on track."
            )
        )
        store.save()

        let data = try Data(contentsOf: settingsURL)
        let decoded = try JSONDecoder().decode(XTerminalSettings.self, from: data)
        #expect(decoded.supervisorPrompt.identityName == "Mira")
        #expect(decoded.supervisorPrompt.roleSummary == "Strategic reviewer.")

        let options = capture.writeOptionsSnapshot()
        #expect(options.count == 2)
        #expect(options.filter { $0.contains(.atomic) }.count == 1)
        #expect(options.filter(\.isEmpty).count == 1)
    }

    @MainActor
    @Test
    func voiceWakeProfileStoreFallsBackToDirectOverwriteWhenAtomicWriteRunsOutOfSpace() async throws {
        let root = try makeTempDirectory("voice_wake_profile")
        defer {
            XTStoreWriteSupport.resetWriteBehaviorForTesting()
            try? FileManager.default.removeItem(at: root)
        }

        let url = root.appendingPathComponent("voice_wake_profile.json")
        let store = VoiceWakeProfileStore(
            url: url,
            syncClient: MockPeripheralVoiceWakeSyncClient(),
            nowProvider: { Date(timeIntervalSince1970: 20_000) }
        )

        var preferences = VoiceRuntimePreferences.default()
        preferences.wakeMode = .wakePhrase
        store.applyPreferences(preferences)

        let capture = XTPeripheralWriteCapture()
        installScopedExistingFileOutOfSpaceOverride(root: root, capture: capture)

        store.setLocalOverrideTriggerWords("alpha, beta")

        let data = try Data(contentsOf: url)
        let decoded = try JSONDecoder().decode(VoiceWakeProfileStoreState.self, from: data)
        #expect(decoded.localOverrideProfile?.normalizedTriggerWords == ["alpha", "beta"])

        let options = capture.writeOptionsSnapshot()
        #expect(options.count == 2)
        #expect(options.filter { $0.contains(.atomic) }.count == 1)
        #expect(options.filter(\.isEmpty).count == 1)
    }

    @Test
    func managedProcessSnapshotFallsBackToDirectOverwriteWhenAtomicWriteRunsOutOfSpace() async throws {
        let root = try makeTempDirectory("managed_process")
        defer {
            XTStoreWriteSupport.resetWriteBehaviorForTesting()
            try? FileManager.default.removeItem(at: root)
        }

        let store = XTManagedProcessStore.shared
        let processId = "proc" + String(UUID().uuidString.lowercased().prefix(8))

        _ = try await startManagedProcess(
            store: store,
            root: root,
            processId: processId
        )

        let snapshotURL = AXProjectContext(root: root).managedProcessesSnapshotURL
        #expect(FileManager.default.fileExists(atPath: snapshotURL.path))

        let capture = XTPeripheralWriteCapture()
        installScopedExistingFileOutOfSpaceOverride(root: root, capture: capture)

        let stopped = try await store.stop(
            projectRoot: root,
            processId: processId,
            force: false
        )
        #expect(stopped.status == .exited)

        let data = try Data(contentsOf: snapshotURL)
        let decoded = try JSONDecoder().decode(XTManagedProcessSnapshot.self, from: data)
        let record = try #require(decoded.processes.first(where: { $0.processId == processId }))
        #expect(record.status == .exited)

        let options = capture.writeOptionsSnapshot()
        #expect(options.count == 6)
        #expect(options.filter { $0.contains(.atomic) }.count == 3)
        #expect(options.filter(\.isEmpty).count == 3)
    }

    private func startManagedProcess(
        store: XTManagedProcessStore,
        root: URL,
        processId: String
    ) async throws -> XTManagedProcessRecord {
        try await store.start(
            projectRoot: root,
            processId: processId,
            name: "Sleep",
            command: "sleep 30",
            cwd: ".",
            env: [:],
            restartOnExit: false
        )
    }

    private func makeTempDirectory(_ suffix: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt_peripheral_write_\(suffix)_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func installScopedExistingFileOutOfSpaceOverride(root: URL, capture: XTPeripheralWriteCapture) {
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

private final class XTPeripheralWriteCapture: @unchecked Sendable {
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

private struct MockPeripheralVoiceWakeSyncClient: VoiceWakeSyncClient {
    func fetchWakeProfile(desiredWakeMode: VoiceWakeMode) async -> VoiceWakeProfileSyncResult {
        VoiceWakeProfileSyncResult(
            ok: false,
            source: "test",
            profile: nil,
            reasonCode: "unavailable",
            logLines: [],
            syncedAtMs: nil
        )
    }

    func setWakeProfile(_ profile: VoiceWakeProfile) async -> VoiceWakeProfileSyncResult {
        VoiceWakeProfileSyncResult(
            ok: false,
            source: "test",
            profile: nil,
            reasonCode: "unavailable",
            logLines: [],
            syncedAtMs: nil
        )
    }
}
