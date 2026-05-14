import Testing
@testable import XTerminal

struct SupervisorHeaderVoiceStatusPresentationTests {

    @Test
    func emptyEvidenceKeepsNeutralHeaderMic() {
        let presentation = SupervisorHeaderVoiceStatusPresentationMapper.map(
            replaySummary: .empty,
            safetyReport: .empty
        )

        #expect(presentation.iconName == "mic")
        #expect(presentation.tone == .neutral)
        #expect(presentation.chrome == .plain)
        #expect(presentation.items.isEmpty)
        #expect(presentation.call.buttonTitle == "进入通话")
    }

    @Test
    func failedReplayPromotesHeaderMicToDanger() {
        let presentation = SupervisorHeaderVoiceStatusPresentationMapper.map(
            replaySummary: headerVoiceReplaySummary(
                state: .failed,
                headline: "语音派发被抑制：heartbeat"
            ),
            safetyReport: .empty
        )

        #expect(presentation.iconName == "mic.slash.fill")
        #expect(presentation.tone == .danger)
        #expect(presentation.items.map(\.title) == ["回放核对"])
    }

    @Test
    func replayAndSafetyReportBothRemainAvailableInPopoverItems() {
        let presentation = SupervisorHeaderVoiceStatusPresentationMapper.map(
            replaySummary: headerVoiceReplaySummary(
                state: .attention,
                headline: "最近 6 条语音证据已记录"
            ),
            safetyReport: VoiceSafetyInvariantReport(
                overallState: .ready,
                headline: "语音安全不变量保持成立",
                summaryLine: "继续累积证据。",
                checks: [],
                updatedAt: 42
            )
        )

        #expect(presentation.items.map(\.title) == ["回放核对", "安全约束"])
        #expect(presentation.summaryText.contains("回放核对：最近 6 条语音证据已记录"))
        #expect(presentation.summaryText.contains("安全约束：语音安全不变量保持成立"))
    }

    @Test
    func blockingCallPreflightMovesRepairStateIntoHeaderMic() {
        let presentation = SupervisorHeaderVoiceStatusPresentationMapper.map(
            replaySummary: .empty,
            safetyReport: .empty,
            preflight: SupervisorManager.SupervisorVoiceCallEntryPreflight(
                disposition: .block,
                headline: "对话链路正在等待工具链路变为可执行",
                detail: "bridge / 工具链路准备好之前必须保持阻塞。",
                nextStep: "先修复语音就绪状态。",
                reasonCode: "bridge_tool_runtime_blocked",
                repairDestination: .xtDiagnostics
            )
        )

        #expect(presentation.iconName == "mic.slash.fill")
        #expect(presentation.tone == .danger)
        #expect(presentation.call.buttonTitle == "先修复语音")
        #expect(presentation.call.statusText == "先修复")
        #expect(presentation.call.headline == "对话链路正在等待工具链路变为可执行")
        #expect(presentation.items.isEmpty)
    }
}

private func headerVoiceReplaySummary(
    state: VoiceEvidenceState,
    headline: String
) -> VoiceReplaySummary {
    VoiceReplaySummary(
        overallState: state,
        headline: headline,
        summaryLine: "最近 6 条语音证据已记录。",
        compactTimelineText: "voice_dispatch state=suppressed source=heartbeat",
        recentEntries: [
            VoiceReplayEvent(
                id: "header-voice-event",
                createdAt: 1,
                category: .dispatch,
                state: .suppressed,
                summary: headline
            )
        ],
        updatedAt: 1
    )
}
