import Foundation
import Testing
@testable import XTerminal

struct SupervisorHeaderStatusPresentationTests {

    @Test
    func mapShowsHubOffWhenNoRecordAndHubDisconnected() {
        let snapshot = AXRoleExecutionSnapshot.empty(role: .supervisor)

        let presentation = SupervisorHeaderStatusResolver.map(
            snapshot: snapshot,
            hubInteractive: false
        )

        #expect(presentation.text == "Hub 离线")
        #expect(presentation.tone == .danger)
    }

    @Test
    func mapUsesExecutionPathForNormalStates() {
        #expect(
            SupervisorHeaderStatusResolver.map(
                snapshot: snapshot(path: "remote_model"),
                hubInteractive: true
            ) == SupervisorHeaderStatusPresentation(
                text: "远端",
                tone: .success,
                detailBadge: nil
            )
        )
        #expect(
            SupervisorHeaderStatusResolver.map(
                snapshot: snapshot(path: "local_runtime"),
                hubInteractive: true
            ) == SupervisorHeaderStatusPresentation(
                text: "本地",
                tone: .caution,
                detailBadge: nil
            )
        )
        #expect(
            SupervisorHeaderStatusResolver.map(
                snapshot: snapshot(path: "remote_error"),
                hubInteractive: true
            ) == SupervisorHeaderStatusPresentation(
                text: "失败",
                tone: .danger,
                detailBadge: nil
            )
        )
        #expect(
            SupervisorHeaderStatusResolver.map(
                snapshot: snapshot(path: "no_record", updatedAt: 0),
                hubInteractive: true
            ) == SupervisorHeaderStatusPresentation(
                text: "待开始",
                tone: .neutral,
                detailBadge: nil
            )
        )
    }

    @Test
    func mapShowsFriendlyVoiceDispatchBadgeForSuppressedDuplicates() {
        let presentation = SupervisorHeaderStatusResolver.map(
            snapshot: snapshot(path: "remote_model"),
            hubInteractive: true,
            latestRuntimeActivityText: "voice_dispatch state=suppressed source=heartbeat reason=source_duplicate_suppressed trigger=heartbeat priority=normal"
        )

        #expect(presentation.text == "远端")
        #expect(presentation.tone == .success)
        #expect(
            presentation.detailBadge == SupervisorHeaderStatusBadge(
                text: "已抑制重复播报",
                tone: .success,
                helpText: "同一来源或同一内容的短时间重复语音已被自动去重，不再重复播报。"
            )
        )
    }

    @Test
    func mapShowsFriendlyVoiceDispatchBadgeForCrossSourceSuppression() {
        let presentation = SupervisorHeaderStatusResolver.map(
            snapshot: snapshot(path: "remote_model"),
            hubInteractive: true,
            latestRuntimeActivityText: "voice_dispatch state=suppressed source=voice_skill reason=cross_source_duplicate_suppressed detail=heartbeat"
        )

        #expect(presentation.detailBadge?.text == "已抑制重复播报")
        #expect(presentation.detailBadge?.tone == .success)
        #expect(presentation.detailBadge?.helpText?.contains("心跳") == true)
    }

    @Test
    func mapShowsFriendlyVoiceDispatchBadgeForCancelledHeartbeat() {
        let presentation = SupervisorHeaderStatusResolver.map(
            snapshot: snapshot(path: "remote_model"),
            hubInteractive: true,
            latestRuntimeActivityText: "voice_dispatch state=cancelled source=heartbeat reason=preempted_by_voice_skill"
        )

        #expect(presentation.detailBadge?.text == "已取消旧心跳")
        #expect(presentation.detailBadge?.tone == .neutral)
        #expect(presentation.detailBadge?.helpText?.contains("voice skill") == true)
    }

    @Test
    func mapShowsFriendlyVoiceDispatchBadgeForDroppedStaleHeartbeat() {
        let presentation = SupervisorHeaderStatusResolver.map(
            snapshot: snapshot(path: "remote_model"),
            hubInteractive: true,
            latestRuntimeActivityText: "voice_dispatch state=dropped source=heartbeat reason=stale_generation detail=projection"
        )

        #expect(presentation.detailBadge?.text == "已丢弃过期心跳")
        #expect(presentation.detailBadge?.tone == .neutral)
        #expect(presentation.detailBadge?.helpText?.contains("projection") == true)
    }

    @Test
    func mapIgnoresNonVoiceRuntimeActivityText() {
        let presentation = SupervisorHeaderStatusResolver.map(
            snapshot: snapshot(path: "remote_model"),
            hubInteractive: true,
            latestRuntimeActivityText: "voice_playback state=played output=system_speech"
        )

        #expect(presentation.detailBadge == nil)
    }

    private func snapshot(
        path: String,
        updatedAt: Double = 1
    ) -> AXRoleExecutionSnapshot {
        AXRoleExecutionSnapshot(
            role: .supervisor,
            updatedAt: updatedAt,
            stage: "supervisor",
            requestedModelId: "",
            actualModelId: "",
            runtimeProvider: "",
            executionPath: path,
            fallbackReasonCode: "",
            remoteRetryAttempted: false,
            remoteRetryFromModelId: "",
            remoteRetryToModelId: "",
            remoteRetryReasonCode: "",
            source: "tests"
        )
    }
}
