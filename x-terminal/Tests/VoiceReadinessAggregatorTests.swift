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
}

private func makeVoiceReadinessInput(
    localConnected: Bool,
    remoteConnected: Bool,
    internetHost: String = "10.0.0.8",
    configuredModelIDs: [String] = [],
    models: [HubModel] = [],
    bridgeAlive: Bool = true,
    bridgeEnabled: Bool = true,
    voiceAuthorizationStatus: VoiceTranscriberAuthorizationStatus = .authorized,
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
        sessionID: nil,
        sessionTitle: nil,
        sessionRuntime: nil,
        voiceRouteDecision: voiceRouteDecision,
        voiceRuntimeState: .idle,
        voiceAuthorizationStatus: voiceAuthorizationStatus,
        voiceActiveHealthReasonCode: "",
        voiceSidecarHealth: nil,
        wakeProfileSnapshot: wakeProfileSnapshot,
        conversationSession: .idle(
            policy: .default(),
            wakeMode: .wakePhrase,
            route: voiceRouteDecision.route
        )
    )
}

private func voiceReadinessModel(id: String) -> HubModel {
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
        note: nil
    )
}
