import Foundation
import Testing
@testable import XTerminal

@MainActor
struct SupervisorMemoryWorkingSetWindowTests {

    @Test
    func localMemoryWorkingSetKeepsEightUserTurnsByDefault() async {
        let manager = SupervisorManager.makeForTesting()
        manager.messages = makeConversation(turns: 10)

        let localMemory = await manager.buildSupervisorLocalMemoryV1ForTesting("继续推进当前项目")
        let lines = Set(localMemory.split(separator: "\n").map(String.init))

        #expect(!lines.contains("user: user-turn-1"))
        #expect(!lines.contains("assistant: assistant-turn-2"))
        #expect(lines.contains("user: user-turn-3"))
        #expect(lines.contains("assistant: assistant-turn-10"))
        #expect(lines.contains("system: system-turn-10"))
    }

    private func makeConversation(turns: Int) -> [SupervisorMessage] {
        var out: [SupervisorMessage] = []
        for index in 1...turns {
            let base = Double(index * 10)
            out.append(
                SupervisorMessage(
                    id: "u-\(index)",
                    role: .user,
                    content: "user-turn-\(index)",
                    isVoice: false,
                    timestamp: base
                )
            )
            out.append(
                SupervisorMessage(
                    id: "a-\(index)",
                    role: .assistant,
                    content: "assistant-turn-\(index)",
                    isVoice: false,
                    timestamp: base + 1
                )
            )
            out.append(
                SupervisorMessage(
                    id: "s-\(index)",
                    role: .system,
                    content: "system-turn-\(index)",
                    isVoice: false,
                    timestamp: base + 2
                )
            )
        }
        return out
    }
}
