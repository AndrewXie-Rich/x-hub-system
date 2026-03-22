import Foundation
import Testing
@testable import XTerminal

@MainActor
struct SupervisorChatVisibilityTests {

    @Test
    func chatTimelineHidesHeartbeatAndSystemEntries() {
        let manager = SupervisorManager.makeForTesting()
        manager.messages = [
            SupervisorMessage(
                id: "hb",
                role: .assistant,
                content: "🫀 Supervisor Heartbeat (8:28)\n变化：无重大状态变化",
                isVoice: false,
                timestamp: 1
            ),
            SupervisorMessage(
                id: "sys",
                role: .system,
                content: "❌ CALL_SKILL 失败：找不到 job_id demo-skill（job_not_found）",
                isVoice: false,
                timestamp: 2
            ),
            SupervisorMessage(
                id: "chat",
                role: .assistant,
                content: "我先帮你看这个项目的 blocker。",
                isVoice: false,
                timestamp: 3
            )
        ]

        #expect(manager.chatTimelineMessages.count == 1)
        #expect(manager.chatTimelineMessages.first?.id == "chat")
    }
}
