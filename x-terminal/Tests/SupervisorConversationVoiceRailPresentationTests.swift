import Foundation
import Testing
@testable import XTerminal

struct SupervisorConversationVoiceRailPresentationTests {

    @Test
    func failClosedRoutePrefersTalkLoopDiagnosticNotice() {
        let presentation = SupervisorConversationVoiceRailPresentationBuilder.build(
            routeDecision: makeRouteDecision(
                route: .failClosed,
                reasonCode: "voice_route_fail_closed",
                wakeCapability: "none"
            ),
            readinessSnapshot: makeSnapshot(
                overallState: .diagnosticRequired,
                checks: [
                    makeCheck(
                        kind: .talkLoopReadiness,
                        state: .diagnosticRequired,
                        reasonCode: "voice_route_fail_closed",
                        headline: "Talk loop is unavailable on the current route",
                        summary: "The active voice route is fail-closed.",
                        nextStep: "Repair the active voice route."
                    ),
                    makeCheck(
                        kind: .wakeProfileReadiness,
                        state: .diagnosticRequired,
                        reasonCode: "wake_phrase_requires_funasr_kws",
                        headline: "Wake profile is blocked",
                        summary: "Wake phrase is unavailable.",
                        nextStep: "Repair wake profile."
                    )
                ]
            ),
            authorizationStatus: .authorized,
            runtimeState: SupervisorVoiceRuntimeState(
                state: .failClosed,
                route: .failClosed,
                recognizedText: "",
                reasonCode: "voice_route_fail_closed"
            ),
            conversationSession: makeSession(
                windowState: .hidden,
                wakeMode: .pushToTalk,
                route: .failClosed
            ),
            playbackActivity: .empty,
            activeHealthReasonCode: "voice_route_fail_closed"
        )

        #expect(presentation.phaseLabel == "安全关闭")
        #expect(presentation.phaseState == .diagnosticRequired)
        #expect(presentation.notice?.title == "当前链路下，对话链路不可用")
        #expect(presentation.notice?.nextStep == "先修复当前语音链路，或者在实时采集恢复健康前继续停留在手动文本 / 按住说话。")
        #expect(presentation.notice?.repairEntry == .xtDiagnostics)
        #expect(presentation.chips.contains { $0.text == "链路：安全关闭" })
        #expect(presentation.chips.contains { $0.text == "原因：voice_route_fail_closed" })
    }

    @Test
    func routeReasonChipHumanizesUserVisibleRouteFailure() {
        let presentation = SupervisorConversationVoiceRailPresentationBuilder.build(
            routeDecision: makeRouteDecision(),
            readinessSnapshot: makeSnapshot(
                overallState: .diagnosticRequired,
                checks: [
                    makeCheck(
                        kind: .talkLoopReadiness,
                        state: .diagnosticRequired,
                        reasonCode: "voice_runtime_degraded",
                        headline: "Talk loop requires repair",
                        summary: "The runtime needs route repair.",
                        nextStep: "Repair the current route."
                    )
                ]
            ),
            authorizationStatus: .authorized,
            runtimeState: SupervisorVoiceRuntimeState(
                state: .idle,
                route: .funasrStreaming,
                recognizedText: "",
                reasonCode: "fallback_reason_code=provider_not_ready;deny_code=policy_remote_denied"
            ),
            conversationSession: makeSession(
                windowState: .armed,
                wakeMode: .pushToTalk,
                route: .funasrStreaming
            ),
            playbackActivity: .empty,
            activeHealthReasonCode: ""
        )

        let chip = presentation.chips.first(where: { $0.id == "reason" })
        #expect(chip?.text == "原因：provider 尚未 ready（provider_not_ready）")
        #expect(chip?.prefersMonospacedText == false)
    }

    @Test
    func permissionDeniedNoticeSurfacesPermissionFixPath() {
        let presentation = SupervisorConversationVoiceRailPresentationBuilder.build(
            routeDecision: makeRouteDecision(
                route: .systemSpeechCompatibility,
                reasonCode: "system_speech_authorization_denied",
                wakeCapability: "push_to_talk_only"
            ),
            readinessSnapshot: makeSnapshot(
                overallState: .permissionDenied,
                checks: [
                    makeCheck(
                        kind: .talkLoopReadiness,
                        state: .permissionDenied,
                        reasonCode: "speech_authorization_denied",
                        headline: "对话链路被麦克风或语音识别权限阻塞",
                        summary: "在 macOS 系统设置里恢复实时收音所需权限之前，连续语音对话仍然不可用。",
                        nextStep: "请先在 macOS 系统设置中授予麦克风和语音识别权限，然后刷新语音运行时。",
                        repairEntry: .systemPermissions
                    ),
                    makeCheck(
                        kind: .wakeProfileReadiness,
                        state: .permissionDenied,
                        reasonCode: "speech_authorization_denied",
                        headline: "唤醒配置被麦克风或语音识别权限阻塞",
                        summary: "在所需权限恢复之前，唤醒能力仍然不可用。",
                        nextStep: "请先在 macOS 系统设置中授予相关权限。",
                        repairEntry: .systemPermissions
                    )
                ]
            ),
            authorizationStatus: .denied,
            runtimeState: SupervisorVoiceRuntimeState(
                state: .idle,
                route: .systemSpeechCompatibility,
                recognizedText: "",
                reasonCode: nil
            ),
            conversationSession: makeSession(
                windowState: .hidden,
                wakeMode: .pushToTalk,
                route: .systemSpeechCompatibility
            ),
            playbackActivity: .empty,
            activeHealthReasonCode: ""
        )

        #expect(presentation.phaseLabel == "空闲")
        #expect(presentation.phaseState == .permissionDenied)
        #expect(presentation.notice?.state == .permissionDenied)
        #expect(presentation.notice?.repairEntry == .systemPermissions)
        #expect(
            presentation.notice?.nextStep?.contains("macOS 系统设置") == true
        )
        #expect(presentation.chips.contains { $0.text == "权限：已拒绝" })
    }

    @Test
    func armedSessionShowsReadyPhaseWithoutNotice() {
        let presentation = SupervisorConversationVoiceRailPresentationBuilder.build(
            routeDecision: makeRouteDecision(),
            readinessSnapshot: makeSnapshot(
                overallState: .ready,
                checks: [
                    makeCheck(
                        kind: .talkLoopReadiness,
                        state: .ready,
                        reasonCode: "talk_loop_ready",
                        headline: "Talk loop foundation is ready",
                        summary: "The live voice route is healthy enough.",
                        nextStep: "Use wake or push-to-talk to start a new Supervisor voice turn."
                    )
                ]
            ),
            authorizationStatus: .authorized,
            runtimeState: .idle,
            conversationSession: makeSession(
                windowState: .armed,
                wakeMode: .wakePhrase,
                route: .funasrStreaming
            ),
            playbackActivity: .empty,
            activeHealthReasonCode: ""
        )

        #expect(presentation.phaseLabel == "待唤醒")
        #expect(presentation.phaseState == .ready)
        #expect(presentation.notice == nil)
        #expect(presentation.chips.contains { $0.text == "会话：待唤醒" })
        #expect(!presentation.canEndSession)
    }

    @Test
    func playbackFailureCreatesFallbackDiagnosticNoticeWhenReadinessIsHealthy() {
        let presentation = SupervisorConversationVoiceRailPresentationBuilder.build(
            routeDecision: makeRouteDecision(),
            readinessSnapshot: makeSnapshot(
                overallState: .ready,
                checks: [
                    makeCheck(
                        kind: .talkLoopReadiness,
                        state: .ready,
                        reasonCode: "talk_loop_ready",
                        headline: "Talk loop foundation is ready",
                        summary: "The live voice route is healthy enough.",
                        nextStep: "Use wake or push-to-talk to start a new Supervisor voice turn."
                    )
                ]
            ),
            authorizationStatus: .authorized,
            runtimeState: .idle,
            conversationSession: makeSession(
                windowState: .conversing,
                remainingTTLSeconds: 45,
                wakeMode: .wakePhrase,
                route: .funasrStreaming
            ),
            playbackActivity: VoicePlaybackActivity(
                state: .failed,
                configuredResolution: nil,
                actualSource: .systemSpeech,
                reasonCode: "tts_output_device_unavailable",
                detail: "Check the current playback output device.",
                provider: "",
                modelID: "",
                engineName: "",
                speakerId: "",
                deviceBackend: "",
                nativeTTSUsed: nil,
                fallbackMode: "",
                fallbackReasonCode: "",
                audioFormat: "",
                voiceName: "",
                updatedAt: 42
            ),
            activeHealthReasonCode: ""
        )

        #expect(presentation.phaseLabel == "对话中")
        #expect(presentation.notice?.title == "最近一次播放失败")
        #expect(presentation.notice?.nextStep == "Check the current playback output device.")
        #expect(presentation.notice?.repairEntry == .xtDiagnostics)
        #expect(presentation.chips.contains { $0.text == "剩余：45 秒" })
        #expect(presentation.canEndSession)
    }

    @Test
    func playbackFallbackCreatesVisibleNoticeWhenReadinessIsHealthy() {
        let presentation = SupervisorConversationVoiceRailPresentationBuilder.build(
            routeDecision: makeRouteDecision(),
            readinessSnapshot: makeSnapshot(
                overallState: .ready,
                checks: [
                    makeCheck(
                        kind: .talkLoopReadiness,
                        state: .ready,
                        reasonCode: "talk_loop_ready",
                        headline: "Talk loop foundation is ready",
                        summary: "The live voice route is healthy enough.",
                        nextStep: "Use wake or push-to-talk to start a new Supervisor voice turn."
                    )
                ]
            ),
            authorizationStatus: .authorized,
            runtimeState: .idle,
            conversationSession: makeSession(
                windowState: .conversing,
                remainingTTLSeconds: 45,
                wakeMode: .wakePhrase,
                route: .funasrStreaming
            ),
            playbackActivity: VoicePlaybackActivity(
                state: .fallbackPlayed,
                configuredResolution: VoicePlaybackResolution(
                    requestedPreference: .hubVoicePack,
                    resolvedSource: .systemSpeech,
                    preferredHubVoicePackID: "hub.voice.zh.warm",
                    resolvedHubVoicePackID: "",
                    reasonCode: "preferred_hub_voice_pack_unavailable",
                    fallbackFrom: .hubVoicePack
                ),
                actualSource: .systemSpeech,
                reasonCode: "hub_voice_pack_runtime_failed",
                detail: "",
                provider: "hub_voice_pack",
                modelID: "hub.voice.zh.warm",
                engineName: "",
                speakerId: "",
                deviceBackend: "system_speech",
                nativeTTSUsed: nil,
                fallbackMode: "hub_voice_pack_unavailable",
                fallbackReasonCode: "hub_voice_pack_runtime_failed",
                audioFormat: "",
                voiceName: "",
                updatedAt: 42
            ),
            activeHealthReasonCode: ""
        )

        #expect(presentation.notice?.state == .inProgress)
        #expect(presentation.notice?.title == "最近一次播放已回退")
        #expect(presentation.notice?.summary == "播放已从 Hub 语音包 回退到 系统语音。")
        #expect(
            presentation.notice?.nextStep
                == "如果你想恢复 Hub 语音包，请打开 Supervisor 设置，检查语音包是否仍在 Hub Library，且本机 Hub IPC 已报告 ready。"
        )
        #expect(presentation.notice?.repairEntry == .homeSupervisor)
        #expect(presentation.chips.contains { $0.id == "playback" })
    }

    @Test
    func manualTextRouteShowsPermissionAsNotNeededInsteadOfUnavailable() {
        let presentation = SupervisorConversationVoiceRailPresentationBuilder.build(
            routeDecision: makeRouteDecision(
                route: .manualText,
                reasonCode: "manual_text_only",
                wakeCapability: "none"
            ),
            readinessSnapshot: makeSnapshot(overallState: .inProgress, checks: []),
            authorizationStatus: .unavailable,
            permissionSnapshot: VoicePermissionSnapshot(
                microphone: .authorized,
                speechRecognition: .authorized
            ),
            runtimeState: SupervisorVoiceRuntimeState(
                state: .idle,
                route: .manualText,
                recognizedText: "",
                reasonCode: nil
            ),
            conversationSession: makeSession(
                windowState: .hidden,
                wakeMode: .pushToTalk,
                route: .manualText
            ),
            playbackActivity: .empty,
            activeHealthReasonCode: ""
        )

        let chip = presentation.chips.first(where: { $0.id == "auth" })
        #expect(chip?.text == "权限：当前链路不需要")
        #expect(chip?.state == .ready)
    }

    @Test
    func liveCaptureRoutePrefersPermissionSnapshotOverUnavailableEngineStateForPermissionChip() {
        let presentation = SupervisorConversationVoiceRailPresentationBuilder.build(
            routeDecision: makeRouteDecision(
                route: .systemSpeechCompatibility,
                reasonCode: "system_speech_recognizer_unavailable",
                wakeCapability: "push_to_talk_only"
            ),
            readinessSnapshot: makeSnapshot(overallState: .diagnosticRequired, checks: []),
            authorizationStatus: .unavailable,
            permissionSnapshot: VoicePermissionSnapshot(
                microphone: .authorized,
                speechRecognition: .authorized
            ),
            runtimeState: SupervisorVoiceRuntimeState(
                state: .idle,
                route: .systemSpeechCompatibility,
                recognizedText: "",
                reasonCode: "system_speech_recognizer_unavailable"
            ),
            conversationSession: makeSession(
                windowState: .hidden,
                wakeMode: .pushToTalk,
                route: .systemSpeechCompatibility
            ),
            playbackActivity: .empty,
            activeHealthReasonCode: "system_speech_recognizer_unavailable"
        )

        let chip = presentation.chips.first(where: { $0.id == "auth" })
        #expect(chip?.text == "权限：已授权")
        #expect(chip?.state == .ready)
    }

    @Test
    func advisoryNoticeUsesOverallSummaryWhenCorePathIsReady() {
        let wakeCheck = makeCheck(
            kind: .wakeProfileReadiness,
            state: .permissionDenied,
            reasonCode: "speech_authorization_denied",
            headline: "唤醒配置被麦克风或语音识别权限阻塞",
            summary: "在相关权限恢复之前，唤醒词仍然不可用。",
            nextStep: "请先在 macOS 系统设置中授予麦克风和语音识别权限，然后刷新语音运行时。",
            repairEntry: .systemPermissions
        )
        let talkLoopCheck = makeCheck(
            kind: .talkLoopReadiness,
            state: .ready,
            reasonCode: "talk_loop_ready",
            headline: "Talk loop foundation is ready",
            summary: "The live voice route is healthy enough.",
            nextStep: "Use wake or push-to-talk to start a new Supervisor voice turn."
        )
        let snapshot = VoiceReadinessSnapshot(
            schemaVersion: VoiceReadinessSnapshot.currentSchemaVersion,
            generatedAtMs: 0,
            overallState: .permissionDenied,
            overallSummary: "首个任务已可启动，但唤醒配置就绪仍需修复：唤醒配置被麦克风或语音识别权限阻塞",
            primaryReasonCode: "speech_authorization_denied",
            orderedFixes: [wakeCheck.nextStep],
            checks: [wakeCheck, talkLoopCheck],
            nodeSync: .empty
        )

        let presentation = SupervisorConversationVoiceRailPresentationBuilder.build(
            routeDecision: makeRouteDecision(
                route: .systemSpeechCompatibility,
                reasonCode: "system_speech_authorization_denied",
                wakeCapability: "push_to_talk_only"
            ),
            readinessSnapshot: snapshot,
            authorizationStatus: .authorized,
            runtimeState: .idle,
            conversationSession: makeSession(
                windowState: .armed,
                wakeMode: .pushToTalk,
                route: .systemSpeechCompatibility
            ),
            playbackActivity: .empty,
            activeHealthReasonCode: ""
        )

        #expect(presentation.notice?.title == wakeCheck.headline)
        #expect(presentation.notice?.summary == snapshot.overallSummary)
        #expect(presentation.notice?.nextStep == wakeCheck.nextStep)
    }

    @Test
    func proofAwarePairingAdvisoryNoticeUsesOverallSummaryWhenCorePathIsReady() {
        let pairingCheck = makeCheck(
            kind: .pairingValidity,
            state: .inProgress,
            reasonCode: "local_pairing_ready_remote_unverified",
            headline: "同网首配已完成，正在验证正式异网入口",
            summary: "同网首配和 Hub 本地批准已经完成，XT 也拿到了正式异网入口（host=hub.tailnet.example）。",
            nextStep: "先保留当前配对档案，等待这轮正式异网验证结束；如果长时间不通过，再检查 Hub 的 stable remote host、relay / tailnet / DNS 和端口可达性。",
            repairEntry: .xtPairHub
        )
        let talkLoopCheck = makeCheck(
            kind: .talkLoopReadiness,
            state: .ready,
            reasonCode: "talk_loop_ready",
            headline: "Talk loop foundation is ready",
            summary: "The live voice route is healthy enough.",
            nextStep: "Use wake or push-to-talk to start a new Supervisor voice turn."
        )
        let snapshot = VoiceReadinessSnapshot(
            schemaVersion: VoiceReadinessSnapshot.currentSchemaVersion,
            generatedAtMs: 0,
            overallState: .inProgress,
            overallSummary: "首个任务已可启动，但配对有效性仍需修复：同网首配已完成，正在验证正式异网入口",
            primaryReasonCode: "local_pairing_ready_remote_unverified",
            orderedFixes: [pairingCheck.nextStep],
            checks: [pairingCheck, talkLoopCheck],
            nodeSync: .empty
        )

        let presentation = SupervisorConversationVoiceRailPresentationBuilder.build(
            routeDecision: makeRouteDecision(),
            readinessSnapshot: snapshot,
            authorizationStatus: .authorized,
            runtimeState: .idle,
            conversationSession: makeSession(
                windowState: .armed,
                wakeMode: .wakePhrase,
                route: .funasrStreaming
            ),
            playbackActivity: .empty,
            activeHealthReasonCode: ""
        )

        #expect(presentation.notice?.title == pairingCheck.headline)
        #expect(presentation.notice?.summary == snapshot.overallSummary)
        #expect(presentation.notice?.nextStep == pairingCheck.nextStep)
        #expect(presentation.notice?.repairEntry == .xtPairHub)
    }

    @Test
    func voiceDispatchSuppressionAddsFriendlyRailChip() {
        let presentation = SupervisorConversationVoiceRailPresentationBuilder.build(
            routeDecision: makeRouteDecision(),
            readinessSnapshot: makeSnapshot(
                overallState: .ready,
                checks: [
                    makeCheck(
                        kind: .talkLoopReadiness,
                        state: .ready,
                        reasonCode: "talk_loop_ready",
                        headline: "Talk loop foundation is ready",
                        summary: "The live voice route is healthy enough.",
                        nextStep: "Use wake or push-to-talk to start a new Supervisor voice turn."
                    )
                ]
            ),
            authorizationStatus: .authorized,
            runtimeState: .idle,
            conversationSession: makeSession(
                windowState: .armed,
                wakeMode: .wakePhrase,
                route: .funasrStreaming
            ),
            playbackActivity: .empty,
            activeHealthReasonCode: "",
            latestRuntimeActivityText: "voice_dispatch state=suppressed source=heartbeat reason=source_duplicate_suppressed"
        )

        let chip = presentation.chips.first(where: { $0.id == "voice_dispatch" })
        #expect(chip?.text == "语音：已抑制重复播报")
        #expect(chip?.state == .ready)
        #expect(chip?.helpText == "同一来源或同一内容的短时间重复语音已被自动去重，不再重复播报。")
    }

    @Test
    func nonVoiceRuntimeActivityDoesNotAddVoiceDispatchChip() {
        let presentation = SupervisorConversationVoiceRailPresentationBuilder.build(
            routeDecision: makeRouteDecision(),
            readinessSnapshot: makeSnapshot(
                overallState: .ready,
                checks: [
                    makeCheck(
                        kind: .talkLoopReadiness,
                        state: .ready,
                        reasonCode: "talk_loop_ready",
                        headline: "Talk loop foundation is ready",
                        summary: "The live voice route is healthy enough.",
                        nextStep: "Use wake or push-to-talk to start a new Supervisor voice turn."
                    )
                ]
            ),
            authorizationStatus: .authorized,
            runtimeState: .idle,
            conversationSession: makeSession(
                windowState: .armed,
                wakeMode: .wakePhrase,
                route: .funasrStreaming
            ),
            playbackActivity: .empty,
            activeHealthReasonCode: "",
            latestRuntimeActivityText: "voice_playback state=played output=system_speech"
        )

        #expect(!presentation.chips.contains(where: { $0.id == "voice_dispatch" }))
    }

    @Test
    func crossSourceVoiceDispatchSuppressionExplainsPreviousSource() {
        let presentation = SupervisorConversationVoiceRailPresentationBuilder.build(
            routeDecision: makeRouteDecision(),
            readinessSnapshot: makeSnapshot(
                overallState: .ready,
                checks: [
                    makeCheck(
                        kind: .talkLoopReadiness,
                        state: .ready,
                        reasonCode: "talk_loop_ready",
                        headline: "Talk loop foundation is ready",
                        summary: "The live voice route is healthy enough.",
                        nextStep: "Use wake or push-to-talk to start a new Supervisor voice turn."
                    )
                ]
            ),
            authorizationStatus: .authorized,
            runtimeState: .idle,
            conversationSession: makeSession(
                windowState: .armed,
                wakeMode: .wakePhrase,
                route: .funasrStreaming
            ),
            playbackActivity: .empty,
            activeHealthReasonCode: "",
            latestRuntimeActivityText: "voice_dispatch state=suppressed source=voice_skill reason=cross_source_duplicate_suppressed detail=heartbeat"
        )

        let chip = presentation.chips.first(where: { $0.id == "voice_dispatch" })
        #expect(chip?.text == "语音：已抑制重复播报")
        #expect(chip?.helpText?.contains("心跳") == true)
    }

    @Test
    func voiceDispatchAuditChipListsRecentSourcesInOrder() {
        let presentation = SupervisorConversationVoiceRailPresentationBuilder.build(
            routeDecision: makeRouteDecision(),
            readinessSnapshot: makeSnapshot(
                overallState: .ready,
                checks: [
                    makeCheck(
                        kind: .talkLoopReadiness,
                        state: .ready,
                        reasonCode: "talk_loop_ready",
                        headline: "Talk loop foundation is ready",
                        summary: "The live voice route is healthy enough.",
                        nextStep: "Use wake or push-to-talk to start a new Supervisor voice turn."
                    )
                ]
            ),
            authorizationStatus: .authorized,
            runtimeState: .idle,
            conversationSession: makeSession(
                windowState: .armed,
                wakeMode: .wakePhrase,
                route: .funasrStreaming
            ),
            playbackActivity: .empty,
            activeHealthReasonCode: "",
            recentVoiceDispatchAuditEntries: [
                SupervisorVoiceDispatchAuditEntry(
                    id: "3",
                    createdAt: 3,
                    source: "voice_skill",
                    state: "suppressed",
                    reasonCode: "cross_source_duplicate_suppressed",
                    detail: "heartbeat"
                ),
                SupervisorVoiceDispatchAuditEntry(
                    id: "2",
                    createdAt: 2,
                    source: "heartbeat",
                    state: "spoken",
                    reasonCode: "dispatched",
                    detail: ""
                ),
                SupervisorVoiceDispatchAuditEntry(
                    id: "1",
                    createdAt: 1,
                    source: "pending_grant_arrival",
                    state: "spoken",
                    reasonCode: "dispatched",
                    detail: ""
                )
            ]
        )

        let chip = presentation.chips.first(where: { $0.id == "voice_dispatch_audit" })
        #expect(chip?.text == "最近语音：Grant 到达 → 心跳 → 显式播报")
        #expect(chip?.state == .blockedWaitingUpstream)
        #expect(chip?.helpText?.contains("Grant 到达 - 已播报") == true)
        #expect(chip?.helpText?.contains("显式播报 - 已抑制重复") == true)
        #expect(chip?.helpText?.contains("（心跳）") == true)
    }
}

private func makeSnapshot(
    overallState: XTUISurfaceState,
    checks: [VoiceReadinessCheck]
) -> VoiceReadinessSnapshot {
    VoiceReadinessSnapshot(
        schemaVersion: VoiceReadinessSnapshot.currentSchemaVersion,
        generatedAtMs: 0,
        overallState: overallState,
        overallSummary: checks.first(where: { $0.state != .ready })?.headline ?? "ready",
        primaryReasonCode: checks.first(where: { $0.state != .ready })?.reasonCode ?? "voice_readiness_ready",
        orderedFixes: checks.compactMap { $0.state == .ready ? nil : $0.nextStep },
        checks: checks,
        nodeSync: .empty
    )
}

private func makeCheck(
    kind: VoiceReadinessCheckKind,
    state: XTUISurfaceState,
    reasonCode: String,
    headline: String,
    summary: String,
    nextStep: String,
    repairEntry: UITroubleshootDestination = .xtDiagnostics
) -> VoiceReadinessCheck {
    VoiceReadinessCheck(
        kind: kind,
        state: state,
        reasonCode: reasonCode,
        headline: headline,
        summary: summary,
        nextStep: nextStep,
        repairEntry: repairEntry,
        detailLines: []
    )
}

private func makeRouteDecision(
    route: VoiceRouteMode = .funasrStreaming,
    reasonCode: String = "preferred_streaming_ready",
    wakeCapability: String = "funasr_kws"
) -> VoiceRouteDecision {
    VoiceRouteDecision(
        route: route,
        reasonCode: reasonCode,
        funasrHealth: .ready,
        whisperKitHealth: .disabled,
        systemSpeechHealth: .ready,
        wakeCapability: wakeCapability
    )
}

private func makeSession(
    windowState: SupervisorConversationWindowState,
    remainingTTLSeconds: Int = 0,
    wakeMode: VoiceWakeMode,
    route: VoiceRouteMode
) -> SupervisorConversationSessionSnapshot {
    SupervisorConversationSessionSnapshot(
        schemaVersion: "xt.supervisor_conversation_window_state.v1",
        windowState: windowState,
        conversationId: windowState == .hidden ? nil : "conversation-1",
        openedBy: windowState == .hidden ? nil : .wakePhrase,
        wakeMode: wakeMode,
        route: route,
        expiresAtMs: remainingTTLSeconds > 0 ? 45_000 : nil,
        remainingTTLSeconds: remainingTTLSeconds,
        keepOpenOverride: false,
        reasonCode: "none",
        auditRef: nil
    )
}
