import Foundation
import Testing
@testable import XTerminal

@MainActor
struct SupervisorConversationSessionIntegrationTests {

    @Test
    func voiceQueryOpensConversationAndReplyKeepsItConversing() async throws {
        var now = Date(timeIntervalSince1970: 4_000)
        var spoken: [String] = []
        let controller = SupervisorConversationSessionController.makeForTesting(
            nowProvider: { now }
        )
        let synthesizer = SupervisorSpeechSynthesizer(
            deduper: SupervisorVoiceBriefDeduper(cooldown: 60),
            speakSink: { spoken.append($0) }
        )
        let manager = SupervisorManager.makeForTesting(
            supervisorSpeechSynthesizer: synthesizer,
            conversationSessionController: controller
        )
        let appModel = AppModel()
        manager.setAppModel(appModel)
        spoken.removeAll()

        manager.sendMessage("/automation", fromVoice: true)

        #expect(manager.conversationSessionSnapshot.windowState == .conversing)
        #expect(manager.conversationSessionSnapshot.reasonCode == "user_turn")

        try await waitUntil("assistant reply committed") {
            manager.messages.contains { message in
                message.role == .assistant && message.content.contains("Automation Runtime 命令")
            }
        }

        #expect(manager.conversationSessionSnapshot.windowState == .conversing)
        #expect(manager.conversationSessionSnapshot.reasonCode == "tts_spoken")
        #expect(manager.conversationSessionSnapshot.remainingTTLSeconds == 45)
        #expect(spoken.count == 1)
        #expect(spoken.last?.contains("Automation Runtime 命令") == true)

        now = now.addingTimeInterval(46)
        controller.refresh()

        #expect(manager.conversationSessionSnapshot.windowState == .hidden)
        #expect(manager.conversationSessionSnapshot.reasonCode == "ttl_expired")
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
