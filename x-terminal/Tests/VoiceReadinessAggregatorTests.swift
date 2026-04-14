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
    func remoteGrpcRouteDoesNotBlockOnLocalBridgeHeartbeat() {
        let model = voiceReadinessModel(id: "hub.model.coder")
        let snapshot = VoiceReadinessAggregator.build(
            input: makeVoiceReadinessInput(
                localConnected: false,
                remoteConnected: true,
                configuredModelIDs: [model.id],
                models: [model],
                bridgeAlive: false,
                bridgeEnabled: false
            )
        )

        #expect(snapshot.check(.modelRouteReadiness)?.state == .ready)
        #expect(snapshot.check(.bridgeToolReadiness)?.state == .ready)
        #expect(snapshot.check(.bridgeToolReadiness)?.reasonCode == "remote_tool_route_ready")
        #expect(snapshot.check(.sessionRuntimeReadiness)?.state == .ready)
        #expect(snapshot.overallState == .ready)
        #expect(snapshot.overallSummary == "配对、语音链路、桥接、会话运行时、唤醒、对话链路和播放都已通过检查")
    }

    @Test
    func activeSessionRuntimeUsesSettlingSummaryInsteadOfFailClosedCopy() {
        let model = voiceReadinessModel(id: "hub.model.coder")
        let snapshot = VoiceReadinessAggregator.build(
            input: makeVoiceReadinessInput(
                localConnected: true,
                remoteConnected: false,
                configuredModelIDs: [model.id],
                models: [model],
                sessionID: "voice-session-1",
                sessionRuntime: AXSessionRuntimeSnapshot(
                    schemaVersion: AXSessionRuntimeSnapshot.currentSchemaVersion,
                    state: .planning,
                    runID: "run-active-1",
                    updatedAt: 1_741_300_000,
                    startedAt: 1_741_299_980,
                    completedAt: nil,
                    lastRuntimeSummary: "planning next reply",
                    lastToolBatchIDs: [],
                    pendingToolCallCount: 0,
                    lastFailureCode: nil,
                    resumeToken: "run-active-1",
                    recoverable: false
                )
            )
        )

        #expect(snapshot.check(.sessionRuntimeReadiness)?.state == .inProgress)
        #expect(snapshot.readyForFirstTask == false)
        #expect(snapshot.overallSummary.contains("当前仍在收敛") == true)
        #expect(snapshot.overallSummary.contains("会话运行时就绪仍在处理中") == true)
        #expect(snapshot.overallSummary.contains("fail-closed") == false)
    }

    @Test
    func modelRouteDiagnosticUsesAIModeledChooseModelNaming() {
        let snapshot = VoiceReadinessAggregator.build(
            input: makeVoiceReadinessInput(
                localConnected: true,
                remoteConnected: false,
                configuredModelIDs: [],
                models: []
            )
        )

        #expect(snapshot.check(.modelRouteReadiness)?.state == .diagnosticRequired)
        #expect(snapshot.check(.modelRouteReadiness)?.nextStep.contains("Supervisor Control Center · AI 模型") == true)
        #expect(snapshot.check(.modelRouteReadiness)?.nextStep.contains("REL Flow Hub → Models & Paid Access") == true)
    }

    @Test
    func modelRouteDiagnosticExplainsNoReadyProviderWhenInventoryIsEmpty() {
        let snapshot = VoiceReadinessAggregator.build(
            input: makeVoiceReadinessInput(
                localConnected: true,
                remoteConnected: false,
                configuredModelIDs: [],
                models: [],
                runtimeStatus: makeProviderAwareRuntimeStatus(
                    readyProviderIDs: [],
                    providers: [
                        "mlx": ["ok": false, "reason_code": "runtime_missing"]
                    ]
                )
            )
        )

        let check = snapshot.check(.modelRouteReadiness)
        #expect(check?.state == .diagnosticRequired)
        #expect(check?.reasonCode == "no_ready_provider")
        #expect(check?.headline == "本地 provider 全部未就绪，模型路由当前不可用")
        #expect(check?.detailLines.contains("runtime_provider_state=no_ready_provider") == true)
        #expect(check?.detailLines.contains("ready_providers=none") == true)
    }

    @Test
    func remoteModelRouteStaysReadyButExplainsMissingLocalFallback() {
        let remoteModel = HubModel(
            id: "hub.remote.coder",
            name: "hub.remote.coder",
            backend: "openai",
            quant: "hosted",
            contextLength: 128_000,
            paramsB: 0,
            roles: ["coder"],
            state: .loaded,
            memoryBytes: nil,
            tokensPerSec: nil,
            modelPath: nil,
            note: nil,
            taskKinds: ["text_generate"],
            outputModalities: ["text"]
        )
        let snapshot = VoiceReadinessAggregator.build(
            input: makeVoiceReadinessInput(
                localConnected: false,
                remoteConnected: true,
                configuredModelIDs: [remoteModel.id],
                models: [remoteModel],
                runtimeStatus: makeProviderAwareRuntimeStatus(
                    readyProviderIDs: [],
                    providers: [
                        "mlx": ["ok": false, "reason_code": "runtime_missing"]
                    ]
                ),
                bridgeAlive: false,
                bridgeEnabled: false
            )
        )

        let check = snapshot.check(VoiceReadinessCheckKind.modelRouteReadiness)
        #expect(check?.state == .ready)
        #expect(check?.headline == "模型路由已就绪（当前无本地兜底）")
        #expect(check?.summary.contains("远端失联时不会有本地兜底") == true)
        #expect(check?.detailLines.contains("interactive_posture=remote_only") == true)
        #expect(check?.detailLines.contains("ready_providers=none") == true)
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
    func pairingValidityBecomesProofAwareWhenFormalRemoteVerificationIsPending() {
        let model = voiceReadinessModel(id: "hub.model.supervisor")
        let stableRemoteRoute = XTPairedRouteTargetSnapshot(
            routeKind: .internet,
            host: "hub.tailnet.example",
            pairingPort: 50052,
            grpcPort: 50051,
            hostKind: "stable_named",
            source: .cachedProfileInternetHost
        )
        let snapshot = VoiceReadinessAggregator.build(
            input: makeVoiceReadinessInput(
                localConnected: true,
                remoteConnected: false,
                configuredModelIDs: [model.id],
                models: [model],
                firstPairCompletionProofSnapshot: makeFirstPairCompletionProofSnapshot(
                    readiness: .localReady,
                    remoteShadowSmokeStatus: .running,
                    stableRemoteRoutePresent: true,
                    remoteShadowSummary: "verifying stable remote route shadow path ..."
                ),
                pairedRouteSetSnapshot: makePairedRouteSetSnapshot(
                    readiness: .localReady,
                    summaryLine: "当前已完成同网首配，但正式异网入口仍未完成验证。",
                    stableRemoteRoute: stableRemoteRoute,
                    readinessReasonCode: "local_pairing_ready_remote_unverified"
                )
            )
        )

        #expect(snapshot.readyForFirstTask)
        #expect(snapshot.check(.pairingValidity)?.state == .inProgress)
        #expect(snapshot.check(.pairingValidity)?.reasonCode == "local_pairing_ready_remote_unverified")
        #expect(snapshot.check(.pairingValidity)?.headline == "同网首配已完成，正在验证正式异网入口")
        #expect(snapshot.check(.pairingValidity)?.summary.contains("正式异网入口（host=hub.tailnet.example）") == true)
        #expect(snapshot.overallSummary == "首个任务已可启动，但配对有效性仍需修复：同网首配已完成，正在验证正式异网入口")
    }

    @Test
    func pairingValidityUsesSwitchSafeCopyWhenRemoteRouteIsVerified() {
        let model = voiceReadinessModel(id: "hub.model.supervisor")
        let stableRemoteRoute = XTPairedRouteTargetSnapshot(
            routeKind: .internet,
            host: "hub.tailnet.example",
            pairingPort: 50052,
            grpcPort: 50051,
            hostKind: "stable_named",
            source: .cachedProfileInternetHost
        )
        let snapshot = VoiceReadinessAggregator.build(
            input: makeVoiceReadinessInput(
                localConnected: false,
                remoteConnected: true,
                configuredModelIDs: [model.id],
                models: [model],
                bridgeAlive: false,
                bridgeEnabled: false,
                firstPairCompletionProofSnapshot: makeFirstPairCompletionProofSnapshot(
                    readiness: .remoteReady,
                    remoteShadowSmokeStatus: .passed,
                    stableRemoteRoutePresent: true,
                    remoteShadowSummary: "stable remote route was already verified by cached reconnect smoke."
                ),
                pairedRouteSetSnapshot: makePairedRouteSetSnapshot(
                    readiness: .remoteReady,
                    summaryLine: "正式异网入口已验证，切网后可继续重连。",
                    stableRemoteRoute: stableRemoteRoute,
                    readinessReasonCode: "cached_remote_reconnect_smoke_verified",
                    cachedReconnectSmokeStatus: "succeeded"
                )
            )
        )

        #expect(snapshot.check(.pairingValidity)?.state == .ready)
        #expect(snapshot.check(.pairingValidity)?.reasonCode == "cached_remote_reconnect_smoke_verified")
        #expect(snapshot.check(.pairingValidity)?.headline == "正式异网入口已验证，切网后可继续工作")
        #expect(snapshot.check(.pairingValidity)?.summary.contains("切网后") == true)
        #expect(snapshot.check(.pairingValidity)?.detailLines.contains("paired_cached_reconnect_smoke_status=succeeded") == true)
        #expect(snapshot.overallSummary == "首个任务已可启动，正式异网入口已验证，切网后可继续工作")
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
    runtimeStatus: AIRuntimeStatus? = nil,
    bridgeAlive: Bool = true,
    bridgeEnabled: Bool = true,
    bridgeLastError: String = "",
    sessionID: String? = nil,
    sessionRuntime: AXSessionRuntimeSnapshot? = nil,
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
    firstPairCompletionProofSnapshot: XTFirstPairCompletionProofSnapshot? = nil,
    pairedRouteSetSnapshot: XTPairedRouteSetSnapshot? = nil,
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
        runtimeStatus: runtimeStatus ?? AIRuntimeStatus(
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
        sessionID: sessionID,
        sessionTitle: sessionID == nil ? nil : "Voice Session",
        sessionRuntime: sessionRuntime,
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
        voicePackReadyEvaluator: voicePackReadyEvaluator,
        firstPairCompletionProofSnapshot: firstPairCompletionProofSnapshot,
        pairedRouteSetSnapshot: pairedRouteSetSnapshot
    )
}

private func makeProviderAwareRuntimeStatus(
    updatedAt: Double = Date().timeIntervalSince1970,
    readyProviderIDs: [String],
    providers: [String: [String: Any]]
) -> AIRuntimeStatus {
    let providerStatuses = providers.reduce(into: [String: AIRuntimeProviderStatus]()) { partial, entry in
        partial[entry.key] = AIRuntimeProviderStatus(
            providerIDHint: entry.key,
            jsonObject: ["provider": entry.key] + entry.value
        )
    }
    return AIRuntimeStatus(
        pid: 42,
        updatedAt: updatedAt,
        mlxOk: false,
        runtimeVersion: "test-runtime",
        importError: nil,
        activeMemoryBytes: nil,
        peakMemoryBytes: nil,
        loadedModelCount: nil,
        schemaVersion: "xhub.local_runtime_status.v2",
        localRuntimeEntryVersion: "2026-03-12-local-provider-runtime-v1",
        runtimeAlive: true,
        providerIDs: providers.keys.sorted(),
        readyProviderIDs: readyProviderIDs,
        providerPacks: [],
        providers: providerStatuses,
        loadedInstances: [],
        loadedInstanceCount: nil
    )
}

private func + (lhs: [String: Any], rhs: [String: Any]) -> [String: Any] {
    var merged = lhs
    rhs.forEach { merged[$0.key] = $0.value }
    return merged
}

private func makePairedRouteSetSnapshot(
    readiness: XTPairedRouteReadiness,
    summaryLine: String,
    stableRemoteRoute: XTPairedRouteTargetSnapshot? = nil,
    readinessReasonCode: String? = nil,
    cachedReconnectSmokeStatus: String? = nil
) -> XTPairedRouteSetSnapshot {
    XTPairedRouteSetSnapshot(
        readiness: readiness,
        readinessReasonCode: readinessReasonCode ?? readiness.rawValue,
        summaryLine: summaryLine,
        hubInstanceID: "hub_test_123",
        activeRoute: nil,
        lanRoute: XTPairedRouteTargetSnapshot(
            routeKind: .lan,
            host: "192.168.0.10",
            pairingPort: 50052,
            grpcPort: 50051,
            hostKind: "raw_ip",
            source: .cachedProfileHost
        ),
        stableRemoteRoute: stableRemoteRoute,
        lastKnownGoodRoute: stableRemoteRoute,
        cachedReconnectSmokeStatus: cachedReconnectSmokeStatus,
        cachedReconnectSmokeReasonCode: nil,
        cachedReconnectSmokeSummary: nil
    )
}

private func makeFirstPairCompletionProofSnapshot(
    readiness: XTPairedRouteReadiness,
    remoteShadowSmokeStatus: XTFirstPairRemoteShadowSmokeStatus,
    stableRemoteRoutePresent: Bool,
    remoteShadowReasonCode: String? = nil,
    remoteShadowSummary: String? = nil
) -> XTFirstPairCompletionProofSnapshot {
    XTFirstPairCompletionProofSnapshot(
        generatedAtMs: 1_741_300_000_000,
        readiness: readiness,
        sameLanVerified: true,
        ownerLocalApprovalVerified: true,
        pairingMaterialIssued: true,
        cachedReconnectSmokePassed: remoteShadowSmokeStatus == .passed,
        stableRemoteRoutePresent: stableRemoteRoutePresent,
        remoteShadowSmokePassed: remoteShadowSmokeStatus == .passed,
        remoteShadowSmokeStatus: remoteShadowSmokeStatus,
        remoteShadowSmokeSource: remoteShadowSmokeStatus == .notRun ? nil : .dedicatedStableRemoteProbe,
        remoteShadowTriggeredAtMs: remoteShadowSmokeStatus == .notRun ? nil : 1_741_300_100_000,
        remoteShadowCompletedAtMs: remoteShadowSmokeStatus == .running ? nil : 1_741_300_120_000,
        remoteShadowRoute: stableRemoteRoutePresent ? .internet : nil,
        remoteShadowReasonCode: remoteShadowReasonCode,
        remoteShadowSummary: remoteShadowSummary,
        summaryLine: "first pair proof test summary"
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
