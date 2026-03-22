import Foundation
import Testing
@testable import XTerminal

actor SupervisorConversationPayloadRecorder {
    private var payload: HubRemoteSupervisorConversationPayload?

    func record(_ payload: HubRemoteSupervisorConversationPayload) {
        self.payload = payload
    }

    func snapshot() -> HubRemoteSupervisorConversationPayload? {
        payload
    }
}

@Suite(.serialized)
@MainActor
struct SupervisorRemoteContinuityThreadTests {
    @Test
    func appendSupervisorConversationTurnUsesDeviceScopeThread() async {
        let recorder = SupervisorConversationPayloadRecorder()

        HubIPCClient.installSupervisorConversationAppendOverrideForTesting { payload in
            await recorder.record(payload)
            return true
        }
        defer { HubIPCClient.resetMemoryContextResolutionOverrideForTesting() }

        let ok = await HubIPCClient.appendSupervisorConversationTurn(
            userText: "  继续推进亮亮  ",
            assistantText: "好的，我先审查上下文。",
            createdAt: 12.345
        )
        let payload = await recorder.snapshot()

        #expect(ok)
        #expect(payload?.threadKey == XTSupervisorConversationMirror.threadKey)
        #expect(payload?.requestId.hasPrefix("xterminal_supervisor_turn_") == true)
        #expect(payload?.createdAtMs == 12_345)
        #expect(payload?.userText == "继续推进亮亮")
        #expect(payload?.assistantText == "好的，我先审查上下文。")
    }

    @Test
    func requestSupervisorRemoteContinuityCanBeStubbedForRuntimeAssembly() async {
        HubIPCClient.installSupervisorRemoteContinuityOverrideForTesting { bypassCache in
            HubIPCClient.SupervisorRemoteContinuityResult(
                ok: true,
                source: bypassCache ? "hub_thread" : "hub_thread",
                workingEntries: [
                    "user: user-turn-1",
                    "assistant: assistant-turn-1",
                ],
                cacheHit: !bypassCache,
                reasonCode: nil
            )
        }
        defer { HubIPCClient.resetMemoryContextResolutionOverrideForTesting() }

        let result = await HubIPCClient.requestSupervisorRemoteContinuity()

        #expect(result.ok)
        #expect(result.source == "hub_thread")
        #expect(result.workingEntries.count == 2)
        #expect(result.cacheHit)
    }
}
