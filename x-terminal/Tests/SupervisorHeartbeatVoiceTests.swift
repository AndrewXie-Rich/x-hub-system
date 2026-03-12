import Foundation
import Testing
@testable import XTerminal

@MainActor
struct SupervisorHeartbeatVoiceTests {

    @Test
    func appModelAttachSpeaksBlockedHeartbeatWhenSummaryReportingEnabled() throws {
        var spoken: [String] = []
        let synthesizer = SupervisorSpeechSynthesizer(
            deduper: SupervisorVoiceBriefDeduper(cooldown: 60),
            speakSink: { spoken.append($0) }
        )
        let manager = SupervisorManager.makeForTesting(
            supervisorSpeechSynthesizer: synthesizer
        )
        let root = try makeProjectRoot(named: "voice-heartbeat-blocked")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(
            root: root,
            displayName: "Voice Runtime",
            blockerSummary: "等待 Hub grant 批准",
            nextStepSummary: "完成授权后继续运行语音回归"
        )
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.settingsStore.settings = configuredSettings(
            from: appModel.settingsStore.settings,
            autoReportMode: .summary
        )

        manager.setAppModel(appModel)

        #expect(spoken.count == 1)
        #expect(spoken[0].contains("1 个阻塞项目"))
        #expect(spoken[0].contains("Voice Runtime"))
        #expect(spoken[0].contains("等待 Hub grant 批准"))
    }

    @Test
    func appModelAttachSuppressesStableSummaryWhenBlockersOnlyModeIsEnabled() throws {
        var spoken: [String] = []
        let synthesizer = SupervisorSpeechSynthesizer(
            deduper: SupervisorVoiceBriefDeduper(cooldown: 60),
            speakSink: { spoken.append($0) }
        )
        let manager = SupervisorManager.makeForTesting(
            supervisorSpeechSynthesizer: synthesizer
        )
        let root = try makeProjectRoot(named: "voice-heartbeat-stable")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(
            root: root,
            displayName: "Stable Runtime",
            blockerSummary: nil,
            nextStepSummary: "继续执行联调验证"
        )
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.settingsStore.settings = configuredSettings(
            from: appModel.settingsStore.settings,
            autoReportMode: .blockersOnly
        )

        manager.setAppModel(appModel)

        #expect(spoken.isEmpty)
    }

    @Test
    func explicitVoiceQuerySpeaksReplyEvenWhenAutoReportModeIsBlockersOnly() async throws {
        var spoken: [String] = []
        let synthesizer = SupervisorSpeechSynthesizer(
            deduper: SupervisorVoiceBriefDeduper(cooldown: 60),
            speakSink: { spoken.append($0) }
        )
        let manager = SupervisorManager.makeForTesting(
            supervisorSpeechSynthesizer: synthesizer
        )
        let appModel = AppModel()
        appModel.registry = registry(with: [])
        appModel.settingsStore.settings = configuredSettings(
            from: appModel.settingsStore.settings,
            autoReportMode: .blockersOnly
        )
        manager.setAppModel(appModel)

        manager.sendMessage("/automation", fromVoice: true)

        try await waitUntil("voice reply emitted") {
            !spoken.isEmpty &&
            manager.messages.contains(where: { $0.role == .assistant && $0.content.contains("Automation Runtime 命令") })
        }

        #expect(spoken.count == 1)
        #expect(spoken[0].contains("Automation Runtime 命令"))
        #expect(spoken[0].contains("/automation status"))
    }

    private func configuredSettings(
        from settings: XTerminalSettings,
        autoReportMode: VoiceAutoReportMode
    ) -> XTerminalSettings {
        var next = settings
        next.voice.autoReportMode = autoReportMode
        next.voice.quietHours.enabled = false
        return next
    }

    private func registry(with projects: [AXProjectEntry]) -> AXProjectRegistry {
        AXProjectRegistry(
            version: AXProjectRegistry.currentVersion,
            updatedAt: Date().timeIntervalSince1970,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: false,
            lastSelectedProjectId: projects.first?.projectId,
            projects: projects
        )
    }

    private func makeProjectEntry(
        root: URL,
        displayName: String,
        blockerSummary: String?,
        nextStepSummary: String?
    ) -> AXProjectEntry {
        AXProjectEntry(
            projectId: AXProjectRegistryStore.projectId(forRoot: root),
            rootPath: root.path,
            displayName: displayName,
            lastOpenedAt: Date().timeIntervalSince1970,
            manualOrderIndex: 0,
            pinned: false,
            statusDigest: "runtime=\(blockerSummary == nil ? "stable" : "blocked")",
            currentStateSummary: blockerSummary == nil ? "运行中" : "阻塞中",
            nextStepSummary: nextStepSummary,
            blockerSummary: blockerSummary,
            lastSummaryAt: Date().timeIntervalSince1970,
            lastEventAt: Date().timeIntervalSince1970
        )
    }

    private func makeProjectRoot(named name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("xterminal-tests", isDirectory: true)
            .appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func waitUntil(
        _ label: String,
        timeoutMs: UInt64 = 2_000,
        intervalMs: UInt64 = 50,
        condition: @escaping @MainActor @Sendable () -> Bool
    ) async throws {
        let attempts = max(1, Int(timeoutMs / intervalMs))
        for _ in 0..<attempts {
            if await MainActor.run(body: condition) {
                return
            }
            try await Task.sleep(nanoseconds: intervalMs * 1_000_000)
        }
        Issue.record("Timed out waiting for \(label)")
    }
}
