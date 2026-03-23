import Foundation
import Testing
@testable import XTerminal

struct VoiceReadinessAggregatorTests {
    @Test
    func marksRemoteBootstrapValuesIncompleteWithoutInternetHost() {
        let snapshot = VoiceReadinessAggregator.build(
            input: makeVoiceReadinessInput(
                localConnected: true,
                remoteConnected: false,
                internetHost: ""
            )
        )

        #expect(snapshot.check(.pairingValidity)?.state == .inProgress)
        #expect(snapshot.check(.pairingValidity)?.reasonCode == "remote_bootstrap_values_incomplete")
        #expect(snapshot.primaryReasonCode == "remote_bootstrap_values_incomplete")
    }

    @Test
    func marksBridgeHeartbeatMissingAsTopDiagnostic() {
        let model = voiceReadinessModel(id: "hub.model.coder")
        let snapshot = VoiceReadinessAggregator.build(
            input: makeVoiceReadinessInput(
                localConnected: true,
                remoteConnected: false,
                configuredModelIDs: [model.id],
                models: [model],
                bridgeAlive: false,
                bridgeEnabled: false
            )
        )

        #expect(snapshot.check(.modelRouteReadiness)?.state == .ready)
        #expect(snapshot.check(.bridgeToolReadiness)?.state == .diagnosticRequired)
        #expect(snapshot.check(.bridgeToolReadiness)?.reasonCode == "bridge_heartbeat_missing")
        #expect(snapshot.overallState == .diagnosticRequired)
    }

    @Test
    func bridgeDiagnosticCarriesLastEnableDeliveryFailure() {
        let model = voiceReadinessModel(id: "hub.model.coder")
        let snapshot = VoiceReadinessAggregator.build(
            input: makeVoiceReadinessInput(
                localConnected: true,
                remoteConnected: false,
                configuredModelIDs: [model.id],
                models: [model],
                bridgeAlive: false,
                bridgeEnabled: false,
                bridgeLastError: "bridge_enable_command_write_failed=POSIXError: No space left on device"
            )
        )

        let check = snapshot.check(.bridgeToolReadiness)
        #expect(check?.summary.contains("上一次 bridge enable 请求也在链路恢复前失败了") == true)
        #expect(check?.detailLines.contains(where: { $0.contains("bridge_last_error=") }) == true)
    }

    @Test
    func marksWakeAndTalkLoopPermissionDeniedWhenSpeechPermissionMissing() {
        let model = voiceReadinessModel(id: "hub.model.supervisor")
        let snapshot = VoiceReadinessAggregator.build(
            input: makeVoiceReadinessInput(
                localConnected: true,
                remoteConnected: false,
                configuredModelIDs: [model.id],
                models: [model],
                bridgeAlive: true,
                bridgeEnabled: true,
                voiceAuthorizationStatus: .denied,
                voicePermissionSnapshot: VoicePermissionSnapshot(
                    microphone: .authorized,
                    speechRecognition: .denied
                ),
                voiceRouteDecision: VoiceRouteDecision(
                    route: .systemSpeechCompatibility,
                    reasonCode: "system_speech_authorization_denied",
                    funasrHealth: .disabled,
                    whisperKitHealth: .disabled,
                    systemSpeechHealth: .unauthorized,
                    wakeCapability: "push_to_talk_only"
                )
            )
        )

        #expect(snapshot.check(.wakeProfileReadiness)?.state == .permissionDenied)
        #expect(snapshot.check(.talkLoopReadiness)?.state == .permissionDenied)
        #expect(snapshot.check(.wakeProfileReadiness)?.headline == "唤醒配置被语音识别权限阻塞")
        #expect(snapshot.check(.talkLoopReadiness)?.headline == "对话链路被语音识别权限阻塞")
        #expect(snapshot.check(.talkLoopReadiness)?.nextStep == "请先在 macOS 系统设置中授予语音识别权限，然后刷新语音运行时。")
        #expect(snapshot.primaryReasonCode == "speech_authorization_denied")
    }

    @Test
    func acceptsLocalWakeOverrideWhenKeywordRouteIsHealthy() {
        let model = voiceReadinessModel(id: "hub.model.supervisor")
        let snapshot = VoiceReadinessAggregator.build(
            input: makeVoiceReadinessInput(
                localConnected: true,
                remoteConnected: false,
                configuredModelIDs: [model.id],
                models: [model],
                wakeProfileSnapshot: VoiceWakeProfileSnapshot(
                    schemaVersion: VoiceWakeProfileSnapshot.currentSchemaVersion,
                    generatedAtMs: 1_741_300_000_000,
                    desiredWakeMode: .wakePhrase,
                    effectiveWakeMode: .wakePhrase,
                    syncState: .localOverrideActive,
                    reasonCode: "wake_profile_local_override_active",
                    profile: VoiceWakeProfile.migratedLocalOverride(wakeMode: .wakePhrase),
                    usedCachedProfile: true,
                    lastSyncAtMs: nil,
                    lastRemoteReasonCode: "voice_wake_profile_remote_not_supported"
                )
            )
        )

        #expect(snapshot.check(.wakeProfileReadiness)?.state == .ready)
        #expect(snapshot.check(.wakeProfileReadiness)?.reasonCode == "wake_profile_local_override_active")
    }

    @Test
    func downgradesStaleWakeProfileToDiagnosticRequired() {
        let model = voiceReadinessModel(id: "hub.model.supervisor")
        let snapshot = VoiceReadinessAggregator.build(
            input: makeVoiceReadinessInput(
                localConnected: true,
                remoteConnected: true,
                configuredModelIDs: [model.id],
                models: [model],
                wakeProfileSnapshot: VoiceWakeProfileSnapshot(
                    schemaVersion: VoiceWakeProfileSnapshot.currentSchemaVersion,
                    generatedAtMs: 1_741_300_000_000,
                    desiredWakeMode: .wakePhrase,
                    effectiveWakeMode: .pushToTalk,
                    syncState: .stale,
                    reasonCode: "wake_profile_stale",
                    profile: VoiceWakeProfile(
                        schemaVersion: VoiceWakeProfile.currentSchemaVersion,
                        profileID: "default",
                        triggerWords: ["x hub"],
                        updatedAtMs: 1_741_200_000_000,
                        scope: .pairedDeviceGroup,
                        source: .hubPairingSync,
                        wakeMode: .wakePhrase,
                        requiresPairingReady: true,
                        auditRef: nil
                    ),
                    usedCachedProfile: true,
                    lastSyncAtMs: 1_741_200_000_000,
                    lastRemoteReasonCode: "network_unreachable"
                )
            )
        )

        #expect(snapshot.check(.wakeProfileReadiness)?.state == .diagnosticRequired)
        #expect(snapshot.check(.wakeProfileReadiness)?.reasonCode == "wake_profile_stale")
    }

    @Test
    func marksHubVoicePackPlaybackReadyWhenPreferredPackExists() {
        let voicePack = voiceReadinessModel(
            id: "hub.voice.zh.warm",
            taskKinds: ["text_to_speech"],
            outputModalities: ["audio"]
        )
        var preferences = VoiceRuntimePreferences.default()
        preferences.playbackPreference = .hubVoicePack
        preferences.preferredHubVoicePackID = voicePack.id

        let snapshot = VoiceReadinessAggregator.build(
            input: makeVoiceReadinessInput(
                localConnected: true,
                remoteConnected: false,
                models: [voicePack],
                voicePreferences: preferences
            )
        )

        #expect(snapshot.check(.ttsReadiness)?.state == .ready)
        #expect(snapshot.check(.ttsReadiness)?.reasonCode == "preferred_hub_voice_pack_ready")
        #expect(snapshot.check(.ttsReadiness)?.detailLines.contains(where: { $0.contains("resolved_playback_source=hub_voice_pack") }) == true)
    }

    @Test
    func marksExplicitHubVoicePackPreferenceAsFallbackWhenPackMissing() {
        var preferences = VoiceRuntimePreferences.default()
        preferences.playbackPreference = .hubVoicePack
        preferences.preferredHubVoicePackID = "hub.voice.zh.warm"

        let snapshot = VoiceReadinessAggregator.build(
            input: makeVoiceReadinessInput(
                localConnected: true,
                remoteConnected: false,
                models: [],
                voicePreferences: preferences
            )
        )

        #expect(snapshot.check(.ttsReadiness)?.state == .inProgress)
        #expect(snapshot.check(.ttsReadiness)?.reasonCode == "preferred_hub_voice_pack_unavailable")
        #expect(snapshot.check(.ttsReadiness)?.summary.contains("回退到了系统语音") == true)
    }

    @Test
    func marksAutomaticVoicePackAsInProgressWhenRecommendedPackIsExposedButRuntimeIsUnavailable() {
        let voicePack = voiceReadinessModel(
            id: "hub.voice.zh.warm",
            taskKinds: ["text_to_speech"],
            outputModalities: ["audio"]
        )
        var preferences = VoiceRuntimePreferences.default()
        preferences.playbackPreference = .automatic
        preferences.localeIdentifier = "zh-CN"
        preferences.timbre = .warm

        let snapshot = VoiceReadinessAggregator.build(
            input: makeVoiceReadinessInput(
                localConnected: true,
                remoteConnected: false,
                models: [voicePack],
                voicePreferences: preferences,
                voicePackReadyEvaluator: { _ in false }
            )
        )

        #expect(snapshot.check(.ttsReadiness)?.state == .inProgress)
        #expect(snapshot.check(.ttsReadiness)?.reasonCode == "automatic_hub_voice_pack_recommended_unavailable")
        #expect(snapshot.check(.ttsReadiness)?.summary.contains("推荐语音包") == true)
        #expect(snapshot.check(.ttsReadiness)?.summary.contains("还不能执行") == true)
    }

    @Test
    func overallSummaryKeepsFirstTaskReadyWhenOnlyPairingBootstrapNeedsRepair() {
        let model = voiceReadinessModel(id: "hub.model.supervisor")
        let snapshot = VoiceReadinessAggregator.build(
            input: makeVoiceReadinessInput(
                localConnected: true,
                remoteConnected: false,
                internetHost: "",
                configuredModelIDs: [model.id],
                models: [model],
                bridgeAlive: true,
                bridgeEnabled: true
            )
        )

        #expect(snapshot.readyForFirstTask)
        #expect(snapshot.firstTaskBlockingCheck == nil)
        #expect(snapshot.firstAdvisoryCheck?.kind == .pairingValidity)
        #expect(snapshot.overallSummary == "首个任务已可启动，但配对有效性仍需修复：本机链路可用，但远端引导参数还不完整")
    }

    @Test
    func overallSummaryFailsClosedWhenBridgePathBlocksFirstTask() {
        let model = voiceReadinessModel(id: "hub.model.supervisor")
        let snapshot = VoiceReadinessAggregator.build(
            input: makeVoiceReadinessInput(
                localConnected: true,
                remoteConnected: false,
                configuredModelIDs: [model.id],
                models: [model],
                bridgeAlive: false,
                bridgeEnabled: false
            )
        )

        #expect(!snapshot.readyForFirstTask)
        #expect(snapshot.firstTaskBlockingCheck?.kind == .bridgeToolReadiness)
        #expect(snapshot.overallSummary == "当前为 fail-closed：桥接 / 工具就绪 仍未就绪：模型路由已通，但桥接 / 工具链路不可用")
    }
}

private func makeVoiceReadinessInput(
    localConnected: Bool,
    remoteConnected: Bool,
    internetHost: String = "10.0.0.8",
    configuredModelIDs: [String] = [],
    models: [HubModel] = [],
    bridgeAlive: Bool = true,
    bridgeEnabled: Bool = true,
    bridgeLastError: String = "",
    voiceAuthorizationStatus: VoiceTranscriberAuthorizationStatus = .authorized,
    voicePermissionSnapshot: VoicePermissionSnapshot = .unknown,
    wakeProfileSnapshot: VoiceWakeProfileSnapshot = VoiceWakeProfileSnapshot(
        schemaVersion: VoiceWakeProfileSnapshot.currentSchemaVersion,
        generatedAtMs: 1_741_300_000_000,
        desiredWakeMode: .wakePhrase,
        effectiveWakeMode: .wakePhrase,
        syncState: .pairedSynced,
        reasonCode: "wake_profile_pair_synced",
        profile: VoiceWakeProfile(
            schemaVersion: VoiceWakeProfile.currentSchemaVersion,
            profileID: "default",
            triggerWords: ["x hub", "supervisor"],
            updatedAtMs: 1_741_300_000_000,
            scope: .pairedDeviceGroup,
            source: .hubPairingSync,
            wakeMode: .wakePhrase,
            requiresPairingReady: true,
            auditRef: nil
        ),
        usedCachedProfile: false,
        lastSyncAtMs: 1_741_300_000_000,
        lastRemoteReasonCode: nil
    ),
    voicePreferences: VoiceRuntimePreferences = .default(),
    voicePackReadyEvaluator: (@Sendable (String) -> Bool)? = nil,
    voiceRouteDecision: VoiceRouteDecision = VoiceRouteDecision(
        route: .funasrStreaming,
        reasonCode: "preferred_streaming_ready",
        funasrHealth: .ready,
        whisperKitHealth: .disabled,
        systemSpeechHealth: .ready,
        wakeCapability: "funasr_kws"
    )
) -> VoiceReadinessAggregatorInput {
    VoiceReadinessAggregatorInput(
        generatedAt: Date(timeIntervalSince1970: 1_741_300_000),
        localConnected: localConnected,
        remoteConnected: remoteConnected,
        remoteRoute: remoteConnected ? .lan : .none,
        linking: false,
        pairingPort: 50052,
        grpcPort: 50051,
        internetHost: internetHost,
        configuredModelIDs: configuredModelIDs,
        totalModelRoles: AXRole.allCases.count,
        runtimeStatus: AIRuntimeStatus(
            pid: 42,
            updatedAt: Date().timeIntervalSince1970,
            mlxOk: true,
            runtimeVersion: "test-runtime",
            importError: nil,
            activeMemoryBytes: nil,
            peakMemoryBytes: nil,
            loadedModelCount: models.filter { $0.state == .loaded }.count
        ),
        modelsState: ModelStateSnapshot(models: models, updatedAt: Date().timeIntervalSince1970),
        bridgeAlive: bridgeAlive,
        bridgeEnabled: bridgeEnabled,
        bridgeLastError: bridgeLastError,
        sessionID: nil,
        sessionTitle: nil,
        sessionRuntime: nil,
        voiceRouteDecision: voiceRouteDecision,
        voiceRuntimeState: .idle,
        voiceAuthorizationStatus: voiceAuthorizationStatus,
        voicePermissionSnapshot: voicePermissionSnapshot,
        voiceActiveHealthReasonCode: "",
        voiceSidecarHealth: nil,
        wakeProfileSnapshot: wakeProfileSnapshot,
        conversationSession: .idle(
            policy: .default(),
            wakeMode: .wakePhrase,
            route: voiceRouteDecision.route
        ),
        voicePreferences: voicePreferences,
        voicePackReadyEvaluator: voicePackReadyEvaluator
    )
}

private func voiceReadinessModel(
    id: String,
    taskKinds: [String] = ["text_generate"],
    outputModalities: [String] = ["text"]
) -> HubModel {
    HubModel(
        id: id,
        name: id,
        backend: "mlx",
        quant: "4bit",
        contextLength: 32768,
        paramsB: 7.0,
        roles: ["supervisor"],
        state: .loaded,
        memoryBytes: 1_024,
        tokensPerSec: 42,
        modelPath: "/models/\(id)",
        note: nil,
        taskKinds: taskKinds,
        outputModalities: outputModalities
    )
}
