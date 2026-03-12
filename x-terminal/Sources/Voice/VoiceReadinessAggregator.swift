import Foundation

enum VoiceReadinessCheckKind: String, CaseIterable, Codable, Sendable {
    case pairingValidity = "pairing_validity"
    case modelRouteReadiness = "model_route_readiness"
    case bridgeToolReadiness = "bridge_tool_readiness"
    case sessionRuntimeReadiness = "session_runtime_readiness"
    case wakeProfileReadiness = "wake_profile_readiness"
    case talkLoopReadiness = "talk_loop_readiness"
    case ttsReadiness = "tts_readiness"

    var title: String {
        switch self {
        case .pairingValidity:
            return "Pairing Validity"
        case .modelRouteReadiness:
            return "Model Route Readiness"
        case .bridgeToolReadiness:
            return "Bridge / Tool Readiness"
        case .sessionRuntimeReadiness:
            return "Session Runtime Readiness"
        case .wakeProfileReadiness:
            return "Wake Profile Readiness"
        case .talkLoopReadiness:
            return "Talk Loop Readiness"
        case .ttsReadiness:
            return "Voice Playback Readiness"
        }
    }
}

struct VoiceReadinessCheck: Identifiable, Codable, Equatable, Sendable {
    var kind: VoiceReadinessCheckKind
    var state: XTUISurfaceState
    var reasonCode: String
    var headline: String
    var summary: String
    var nextStep: String
    var repairEntry: UITroubleshootDestination
    var detailLines: [String]

    var id: String { kind.rawValue }

    func asDoctorSection() -> XTUnifiedDoctorSection? {
        let mappedKind: XTUnifiedDoctorSectionKind? = {
            switch kind {
            case .pairingValidity:
                return .pairingValidity
            case .modelRouteReadiness:
                return .modelRouteReadiness
            case .bridgeToolReadiness:
                return .bridgeToolReadiness
            case .sessionRuntimeReadiness:
                return .sessionRuntimeReadiness
            case .wakeProfileReadiness, .talkLoopReadiness, .ttsReadiness:
                return nil
            }
        }()
        guard let mappedKind else { return nil }
        return XTUnifiedDoctorSection(
            kind: mappedKind,
            state: state,
            headline: headline,
            summary: summary,
            nextStep: nextStep,
            repairEntry: repairEntry,
            detailLines: detailLines
        )
    }
}

struct VoiceReadinessSnapshot: Codable, Equatable, Sendable {
    static let currentSchemaVersion = "xt.supervisor_voice_readiness_snapshot.v1"

    var schemaVersion: String
    var generatedAtMs: Int64
    var overallState: XTUISurfaceState
    var overallSummary: String
    var primaryReasonCode: String
    var orderedFixes: [String]
    var checks: [VoiceReadinessCheck]
    var nodeSync: VoiceNodeSyncSnapshot

    static let empty = VoiceReadinessSnapshot(
        schemaVersion: currentSchemaVersion,
        generatedAtMs: 0,
        overallState: .blockedWaitingUpstream,
        overallSummary: "Voice readiness pending.",
        primaryReasonCode: "",
        orderedFixes: [],
        checks: [],
        nodeSync: .empty
    )

    func check(_ kind: VoiceReadinessCheckKind) -> VoiceReadinessCheck? {
        checks.first { $0.kind == kind }
    }
}

struct VoiceReadinessAggregatorInput: Sendable {
    var generatedAt: Date
    var localConnected: Bool
    var remoteConnected: Bool
    var remoteRoute: HubRemoteRoute
    var linking: Bool
    var pairingPort: Int
    var grpcPort: Int
    var internetHost: String
    var configuredModelIDs: [String]
    var totalModelRoles: Int
    var runtimeStatus: AIRuntimeStatus?
    var modelsState: ModelStateSnapshot
    var bridgeAlive: Bool
    var bridgeEnabled: Bool
    var sessionID: String?
    var sessionTitle: String?
    var sessionRuntime: AXSessionRuntimeSnapshot?
    var voiceRouteDecision: VoiceRouteDecision
    var voiceRuntimeState: SupervisorVoiceRuntimeState
    var voiceAuthorizationStatus: VoiceTranscriberAuthorizationStatus
    var voiceActiveHealthReasonCode: String
    var voiceSidecarHealth: VoiceSidecarHealthSnapshot?
    var wakeProfileSnapshot: VoiceWakeProfileSnapshot
    var conversationSession: SupervisorConversationSessionSnapshot

    static func fromDoctorInput(_ input: XTUnifiedDoctorInput) -> VoiceReadinessAggregatorInput {
        VoiceReadinessAggregatorInput(
            generatedAt: input.generatedAt,
            localConnected: input.localConnected,
            remoteConnected: input.remoteConnected,
            remoteRoute: input.remoteRoute,
            linking: input.linking,
            pairingPort: input.pairingPort,
            grpcPort: input.grpcPort,
            internetHost: input.internetHost,
            configuredModelIDs: input.configuredModelIDs,
            totalModelRoles: input.totalModelRoles,
            runtimeStatus: input.runtimeStatus,
            modelsState: input.modelsState,
            bridgeAlive: input.bridgeAlive,
            bridgeEnabled: input.bridgeEnabled,
            sessionID: input.sessionID,
            sessionTitle: input.sessionTitle,
            sessionRuntime: input.sessionRuntime,
            voiceRouteDecision: input.voiceRouteDecision,
            voiceRuntimeState: input.voiceRuntimeState,
            voiceAuthorizationStatus: input.voiceAuthorizationStatus,
            voiceActiveHealthReasonCode: input.voiceActiveHealthReasonCode,
            voiceSidecarHealth: input.voiceSidecarHealth,
            wakeProfileSnapshot: input.wakeProfileSnapshot,
            conversationSession: input.conversationSession
        )
    }
}

enum VoiceReadinessAggregator {
    static func build(input: VoiceReadinessAggregatorInput) -> VoiceReadinessSnapshot {
        let trimmedHost = input.internetHost.trimmingCharacters(in: .whitespacesAndNewlines)
        let hubInteractive = input.localConnected || input.remoteConnected
        let runtimeAlive = input.runtimeStatus?.isAlive(ttl: 3.0) == true
        let pairingLooksValid = portLooksValid(input.pairingPort) && portLooksValid(input.grpcPort) && input.pairingPort != input.grpcPort
        let pairingMatchesConvention = input.pairingPort == max(1, min(65_535, input.grpcPort + 1))
        let configuredModelIDs = orderedUnique(input.configuredModelIDs)
        let configuredModelCount = configuredModelIDs.count
        let availableModels = input.modelsState.models
        let availableModelCount = availableModels.count
        let loadedModelCount = availableModels.filter { $0.state == .loaded }.count
        let availableModelIDs = Set(availableModels.map(\.id))
        let missingAssignedModels = configuredModelIDs.filter { !availableModelIDs.contains($0) }
        let toolRouteExecutable = hubInteractive && input.bridgeAlive && input.bridgeEnabled
        let sessionSnapshot = input.sessionRuntime ?? AXSessionRuntimeSnapshot.idle()

        let pairing = buildPairingValidityCheck(
            input: input,
            host: trimmedHost,
            pairingLooksValid: pairingLooksValid,
            pairingMatchesConvention: pairingMatchesConvention
        )
        let modelRoute = buildModelRouteCheck(
            hubInteractive: hubInteractive,
            runtimeAlive: runtimeAlive,
            availableModelCount: availableModelCount,
            loadedModelCount: loadedModelCount,
            configuredModelCount: configuredModelCount,
            totalModelRoles: input.totalModelRoles,
            missingAssignedModels: missingAssignedModels,
            configuredModelIDs: configuredModelIDs
        )
        let bridge = buildBridgeToolCheck(
            hubInteractive: hubInteractive,
            modelRouteReady: modelRoute.state == .ready,
            bridgeAlive: input.bridgeAlive,
            bridgeEnabled: input.bridgeEnabled,
            activeRoute: input.voiceRouteDecision.route.rawValue
        )
        let session = buildSessionRuntimeCheck(
            toolRouteExecutable: toolRouteExecutable,
            sessionID: input.sessionID,
            sessionTitle: input.sessionTitle,
            runtime: sessionSnapshot
        )
        let wake = buildWakeProfileCheck(
            routeDecision: input.voiceRouteDecision,
            authorizationStatus: input.voiceAuthorizationStatus,
            wakeProfile: input.wakeProfileSnapshot,
            conversationSession: input.conversationSession,
            activeHealthReasonCode: input.voiceActiveHealthReasonCode
        )
        let talkLoop = buildTalkLoopCheck(
            toolRouteExecutable: toolRouteExecutable,
            routeDecision: input.voiceRouteDecision,
            runtimeState: input.voiceRuntimeState,
            authorizationStatus: input.voiceAuthorizationStatus,
            conversationSession: input.conversationSession
        )
        let tts = buildTTSCheck(
            toolRouteExecutable: toolRouteExecutable,
            routeDecision: input.voiceRouteDecision
        )

        let checks = [pairing, modelRoute, bridge, session, wake, talkLoop, tts]
        let overallState = overallState(for: checks)
        let orderedFixes = orderedUnique(checks.compactMap { check in
            check.state == .ready ? nil : check.nextStep
        })
        let primaryReasonCode = checks.first(where: { $0.state != .ready })?.reasonCode ?? "voice_readiness_ready"
        let overallSummary: String = {
            switch overallState {
            case .ready:
                return "Voice readiness is aligned across pairing, model route, bridge, session runtime, wake, and playback."
            case .inProgress:
                return checks.first(where: { $0.state == .inProgress })?.headline ?? "Voice readiness is still converging."
            case .blockedWaitingUpstream:
                return checks.first(where: { $0.state == .blockedWaitingUpstream })?.headline ?? "Voice readiness is blocked by an upstream dependency."
            case .grantRequired:
                return checks.first(where: { $0.state == .grantRequired })?.headline ?? "Voice readiness still needs grant approval."
            case .permissionDenied:
                return checks.first(where: { $0.state == .permissionDenied })?.headline ?? "Voice readiness is blocked by a permission denial."
            case .releaseFrozen, .diagnosticRequired:
                return checks.first(where: { $0.state == .diagnosticRequired || $0.state == .releaseFrozen })?.headline
                    ?? "Voice readiness requires diagnostics."
            }
        }()

        let nodeSync = VoiceNodeSyncSnapshot(
            schemaVersion: VoiceNodeSyncSnapshot.currentSchemaVersion,
            generatedAtMs: Int64(input.generatedAt.timeIntervalSince1970 * 1000),
            localConnected: input.localConnected,
            remoteConnected: input.remoteConnected,
            linking: input.linking,
            remoteRoute: input.remoteRoute.rawValue,
            pairingPort: input.pairingPort,
            grpcPort: input.grpcPort,
            internetHost: trimmedHost,
            currentVoiceRoute: input.voiceRouteDecision.route.rawValue,
            desiredWakeMode: input.wakeProfileSnapshot.desiredWakeMode.rawValue,
            effectiveWakeMode: input.wakeProfileSnapshot.effectiveWakeMode.rawValue,
            wakeCapability: input.voiceRouteDecision.wakeCapability,
            wakeProfileSyncState: input.wakeProfileSnapshot.syncState.rawValue,
            wakeProfileSource: input.wakeProfileSnapshot.profileSource?.rawValue ?? "none",
            wakeProfileReasonCode: input.wakeProfileSnapshot.reasonCode,
            wakeTriggerWords: input.wakeProfileSnapshot.triggerWords,
            bridgeAlive: input.bridgeAlive,
            bridgeEnabled: input.bridgeEnabled,
            toolRouteExecutable: toolRouteExecutable,
            sessionID: input.sessionID,
            sessionTitle: input.sessionTitle,
            sessionState: sessionSnapshot.state.rawValue,
            conversationWindowState: input.conversationSession.windowState.rawValue
        )

        return VoiceReadinessSnapshot(
            schemaVersion: VoiceReadinessSnapshot.currentSchemaVersion,
            generatedAtMs: Int64(input.generatedAt.timeIntervalSince1970 * 1000),
            overallState: overallState,
            overallSummary: overallSummary,
            primaryReasonCode: primaryReasonCode,
            orderedFixes: orderedFixes,
            checks: checks,
            nodeSync: nodeSync
        )
    }

    private static func buildPairingValidityCheck(
        input: VoiceReadinessAggregatorInput,
        host: String,
        pairingLooksValid: Bool,
        pairingMatchesConvention: Bool
    ) -> VoiceReadinessCheck {
        let details = [
            "pairing_port=\(input.pairingPort)",
            "grpc_port=\(input.grpcPort)",
            "internet_host=\(host.isEmpty ? "missing" : host)",
            "pairing_equals_grpc_plus_one=\(pairingMatchesConvention)",
            "local_connected=\(input.localConnected)",
            "remote_connected=\(input.remoteConnected)"
        ]

        if !pairingLooksValid {
            return VoiceReadinessCheck(
                kind: .pairingValidity,
                state: .diagnosticRequired,
                reasonCode: "pairing_values_invalid",
                headline: "Pairing values are not valid yet",
                summary: "Pairing Port and gRPC Port must be explicit, distinct values before voice/runtime bootstrap can be trusted.",
                nextStep: "Copy Pairing Port and gRPC Port from REL Flow Hub -> Settings -> LAN (gRPC), then retry Pair Hub.",
                repairEntry: .xtPairHub,
                detailLines: details
            )
        }

        if input.remoteConnected {
            return VoiceReadinessCheck(
                kind: .pairingValidity,
                state: .ready,
                reasonCode: "pairing_values_match_active_remote_route",
                headline: "Pairing values match an active remote route",
                summary: "The same Pairing Port / gRPC Port / Internet Host values already produced a working remote connection.",
                nextStep: "Keep these exact values for future reconnects.",
                repairEntry: .xtPairHub,
                detailLines: details
            )
        }

        if !host.isEmpty {
            return VoiceReadinessCheck(
                kind: .pairingValidity,
                state: .ready,
                reasonCode: "pairing_values_explicit",
                headline: "Pairing values are explicit and ready to reuse",
                summary: "X-Terminal has all user-visible pairing fields it needs: Pairing Port, gRPC Port, and Internet Host.",
                nextStep: "Use the same values for LAN, VPN, or tunnel pairing without re-discovering them elsewhere.",
                repairEntry: .xtPairHub,
                detailLines: details
            )
        }

        if input.localConnected || input.linking {
            return VoiceReadinessCheck(
                kind: .pairingValidity,
                state: .inProgress,
                reasonCode: "remote_bootstrap_values_incomplete",
                headline: "Local route works, but remote bootstrap values are still incomplete",
                summary: "Same-Mac verification can continue, but Internet Host is still empty, so a second device would not know what to enter yet.",
                nextStep: "Open REL Flow Hub -> Settings -> LAN (gRPC) and copy Internet Host into X-Terminal before remote pairing.",
                repairEntry: .xtPairHub,
                detailLines: details
            )
        }

        return VoiceReadinessCheck(
            kind: .pairingValidity,
            state: .diagnosticRequired,
            reasonCode: "pairing_values_incomplete_for_bootstrap",
            headline: "Pairing values are not complete enough for bootstrap",
            summary: "Without an explicit Internet Host, the pairing path is incomplete for LAN/VPN/tunnel devices.",
            nextStep: "Copy Internet Host from REL Flow Hub -> Settings -> LAN (gRPC), then rerun one-click setup.",
            repairEntry: .xtPairHub,
            detailLines: details
        )
    }

    private static func buildModelRouteCheck(
        hubInteractive: Bool,
        runtimeAlive: Bool,
        availableModelCount: Int,
        loadedModelCount: Int,
        configuredModelCount: Int,
        totalModelRoles: Int,
        missingAssignedModels: [String],
        configuredModelIDs: [String]
    ) -> VoiceReadinessCheck {
        var details = [
            "runtime_alive=\(runtimeAlive)",
            "available_models=\(availableModelCount)",
            "loaded_models=\(loadedModelCount)",
            "configured_roles=\(configuredModelCount)/\(totalModelRoles)",
            configuredModelIDs.isEmpty ? "configured_model_ids=none" : "configured_model_ids=\(configuredModelIDs.joined(separator: ","))"
        ]
        if !missingAssignedModels.isEmpty {
            details.append("missing_assigned_models=\(missingAssignedModels.joined(separator: ","))")
        }

        if !hubInteractive {
            return VoiceReadinessCheck(
                kind: .modelRouteReadiness,
                state: .blockedWaitingUpstream,
                reasonCode: "hub_route_not_interactive",
                headline: "Model route waits for a live Hub route",
                summary: "Until Hub reachability becomes interactive, XT cannot verify which models are actually available.",
                nextStep: "Finish Pair Hub first, then return to Choose Model.",
                repairEntry: .xtChooseModel,
                detailLines: details
            )
        }

        if availableModelCount == 0 {
            return VoiceReadinessCheck(
                kind: .modelRouteReadiness,
                state: .diagnosticRequired,
                reasonCode: "model_inventory_empty",
                headline: "Pairing ok, but model route is unavailable",
                summary: "Hub is reachable, but XT cannot see any usable models yet. This must stay distinct from pairing and grant failures.",
                nextStep: "Open Choose Model or REL Flow Hub -> Models & Paid Access, confirm at least one active model, then re-run Verify.",
                repairEntry: .xtChooseModel,
                detailLines: details
            )
        }

        if configuredModelCount == 0 {
            return VoiceReadinessCheck(
                kind: .modelRouteReadiness,
                state: .inProgress,
                reasonCode: "xt_role_assignment_empty",
                headline: "Hub models are visible, but XT role assignment is still empty",
                summary: "The model route exists, but X-Terminal has not bound any role to a Hub model yet.",
                nextStep: "Assign at least the coder and supervisor roles in Choose Model.",
                repairEntry: .xtChooseModel,
                detailLines: details
            )
        }

        if !missingAssignedModels.isEmpty {
            return VoiceReadinessCheck(
                kind: .modelRouteReadiness,
                state: .diagnosticRequired,
                reasonCode: "assigned_model_missing_from_inventory",
                headline: "XT role assignment points to models that are not currently exposed",
                summary: "Pairing succeeded, but at least one assigned model ID is missing from the current Hub model inventory.",
                nextStep: "Replace stale model IDs in Choose Model or re-enable those models in Hub.",
                repairEntry: .xtChooseModel,
                detailLines: details
            )
        }

        return VoiceReadinessCheck(
            kind: .modelRouteReadiness,
            state: .ready,
            reasonCode: "model_route_ready",
            headline: "Model route is ready",
            summary: "XT can see available Hub models and the current role assignments map to visible model IDs.",
            nextStep: "Continue into bridge/tool verification without leaving this screen.",
            repairEntry: .xtChooseModel,
            detailLines: details
        )
    }

    private static func buildBridgeToolCheck(
        hubInteractive: Bool,
        modelRouteReady: Bool,
        bridgeAlive: Bool,
        bridgeEnabled: Bool,
        activeRoute: String
    ) -> VoiceReadinessCheck {
        let toolRouteExecutable = hubInteractive && bridgeAlive && bridgeEnabled
        let details = [
            "bridge_alive=\(bridgeAlive)",
            "bridge_enabled=\(bridgeEnabled)",
            "tool_route_executable=\(toolRouteExecutable)",
            "active_route=\(activeRoute)"
        ]

        if !hubInteractive {
            return VoiceReadinessCheck(
                kind: .bridgeToolReadiness,
                state: .blockedWaitingUpstream,
                reasonCode: "hub_route_not_interactive",
                headline: "Tool route waits for Hub reachability",
                summary: "Bridge and tool execution cannot be verified before X-Terminal has a live Hub route.",
                nextStep: "Finish Pair Hub first, then re-run Verify.",
                repairEntry: .hubDiagnostics,
                detailLines: details
            )
        }

        if !bridgeAlive {
            return VoiceReadinessCheck(
                kind: .bridgeToolReadiness,
                state: .diagnosticRequired,
                reasonCode: "bridge_heartbeat_missing",
                headline: modelRouteReady ? "Model route ok, but bridge / tool route is unavailable" : "Bridge / tool route is unavailable",
                summary: "Hub is reachable, but the bridge heartbeat is missing, so tool calls must remain fail-closed.",
                nextStep: "Open Hub Diagnostics & Recovery, relaunch the bridge if needed, then rerun Verify.",
                repairEntry: .hubDiagnostics,
                detailLines: details
            )
        }

        if !bridgeEnabled {
            return VoiceReadinessCheck(
                kind: .bridgeToolReadiness,
                state: .diagnosticRequired,
                reasonCode: "bridge_execution_window_disabled",
                headline: "Bridge is alive, but tool execution is not enabled",
                summary: "The bridge process exists, but the current execution window is not active, so tools are not yet executable.",
                nextStep: "Run reconnect smoke or re-enable the bridge window, then verify tools again.",
                repairEntry: .hubDiagnostics,
                detailLines: details
            )
        }

        return VoiceReadinessCheck(
            kind: .bridgeToolReadiness,
            state: .ready,
            reasonCode: "bridge_tool_route_ready",
            headline: "Bridge / tool route is ready",
            summary: "The bridge heartbeat is alive and the execution window is enabled, so tool calls can run through the current Hub route.",
            nextStep: "Continue to session runtime verification on the same route.",
            repairEntry: .hubDiagnostics,
            detailLines: details
        )
    }

    private static func buildSessionRuntimeCheck(
        toolRouteExecutable: Bool,
        sessionID: String?,
        sessionTitle: String?,
        runtime: AXSessionRuntimeSnapshot
    ) -> VoiceReadinessCheck {
        let details = [
            sessionID == nil ? "session_id=none" : "session_id=\(sessionID!)",
            sessionTitle == nil ? "session_title=none" : "session_title=\(sessionTitle!)",
            "state=\(runtime.state.rawValue)",
            "recoverable=\(runtime.recoverable)",
            "pending_tool_calls=\(runtime.pendingToolCallCount)",
            runtime.lastFailureCode?.isEmpty == false ? "last_failure_code=\(runtime.lastFailureCode!)" : "last_failure_code=none",
            runtime.resumeToken?.isEmpty == false ? "resume_token_present=true" : "resume_token_present=false"
        ]

        if !toolRouteExecutable {
            return VoiceReadinessCheck(
                kind: .sessionRuntimeReadiness,
                state: .blockedWaitingUpstream,
                reasonCode: "tool_route_not_executable",
                headline: "Session runtime waits for the tool route to become executable",
                summary: "Until the bridge / tool layer is ready, runtime verification remains blocked instead of pretending the session can recover.",
                nextStep: "Repair bridge / tool readiness first, then come back to Verify.",
                repairEntry: .xtDiagnostics,
                detailLines: details
            )
        }

        if runtime.state == .failed_recoverable && !runtime.recoverable {
            return VoiceReadinessCheck(
                kind: .sessionRuntimeReadiness,
                state: .diagnosticRequired,
                reasonCode: "session_runtime_not_recoverable",
                headline: "Bridge ok, but session runtime is not recoverable",
                summary: "The runtime reached a failure state without a valid recovery path. This must stay separate from bridge and model routing issues.",
                nextStep: "Open XT Diagnostics, inspect the last failure code, then recreate or repair the affected session before continuing.",
                repairEntry: .xtDiagnostics,
                detailLines: details
            )
        }

        if runtime.state == .failed_recoverable {
            return VoiceReadinessCheck(
                kind: .sessionRuntimeReadiness,
                state: .inProgress,
                reasonCode: "session_runtime_recoverable_failure",
                headline: "Session runtime has a recoverable failure path",
                summary: "The current session is paused behind a recoverable failure. A resume path exists, but verification is not complete yet.",
                nextStep: "Use the resume path or rerun the blocked request, then verify the runtime returns to idle or completed.",
                repairEntry: .xtDiagnostics,
                detailLines: details
            )
        }

        if runtime.pendingToolCallCount > 0 || runtimeBusy(runtime.state) {
            return VoiceReadinessCheck(
                kind: .sessionRuntimeReadiness,
                state: .inProgress,
                reasonCode: "session_runtime_active",
                headline: "Session runtime is active",
                summary: "The runtime is currently processing or waiting on a step. Verification should wait until it returns to a stable state.",
                nextStep: "Wait for the current session activity to finish, then re-open Verify.",
                repairEntry: .xtDiagnostics,
                detailLines: details
            )
        }

        if sessionID == nil {
            return VoiceReadinessCheck(
                kind: .sessionRuntimeReadiness,
                state: .ready,
                reasonCode: "session_runtime_idle_ready",
                headline: "Session runtime foundation is ready",
                summary: "No primary session exists yet, but the runtime foundation is idle and ready to materialize one on the first task.",
                nextStep: "Start the first task to create the primary session on top of the verified route.",
                repairEntry: .homeSupervisor,
                detailLines: details
            )
        }

        return VoiceReadinessCheck(
            kind: .sessionRuntimeReadiness,
            state: .ready,
            reasonCode: "session_runtime_stable",
            headline: "Session runtime is ready",
            summary: "The current session is in a stable state and can resume normal work on the verified route.",
            nextStep: "You can continue into the first task without switching pages.",
            repairEntry: .homeSupervisor,
            detailLines: details
        )
    }

    private static func buildWakeProfileCheck(
        routeDecision: VoiceRouteDecision,
        authorizationStatus: VoiceTranscriberAuthorizationStatus,
        wakeProfile: VoiceWakeProfileSnapshot,
        conversationSession: SupervisorConversationSessionSnapshot,
        activeHealthReasonCode: String
    ) -> VoiceReadinessCheck {
        let details = [
            "desired_wake_mode=\(wakeProfile.desiredWakeMode.rawValue)",
            "effective_wake_mode=\(wakeProfile.effectiveWakeMode.rawValue)",
            "wake_sync_state=\(wakeProfile.syncState.rawValue)",
            "wake_profile_reason=\(wakeProfile.reasonCode)",
            "wake_profile_source=\(wakeProfile.profileSource?.rawValue ?? "none")",
            wakeProfile.triggerWords.isEmpty ? "wake_trigger_words=none" : "wake_trigger_words=\(wakeProfile.triggerWords.joined(separator: ","))",
            "route=\(routeDecision.route.rawValue)",
            "wake_capability=\(routeDecision.wakeCapability)",
            "window_state=\(conversationSession.windowState.rawValue)",
            activeHealthReasonCode.isEmpty ? "engine_reason=none" : "engine_reason=\(activeHealthReasonCode)",
            wakeProfile.lastRemoteReasonCode?.isEmpty == false
                ? "wake_remote_reason=\(wakeProfile.lastRemoteReasonCode!)"
                : "wake_remote_reason=none"
        ]

        if authorizationStatus == .denied || authorizationStatus == .restricted {
            return VoiceReadinessCheck(
                kind: .wakeProfileReadiness,
                state: .permissionDenied,
                reasonCode: "speech_authorization_denied",
                headline: "Wake profile is blocked by microphone or speech permission",
                summary: "Wake and live capture remain fail-closed until speech-recognition permission is granted.",
                nextStep: "Grant microphone and speech-recognition permission in macOS Settings, then refresh voice runtime.",
                repairEntry: .systemPermissions,
                detailLines: details
            )
        }

        if wakeProfile.effectiveWakeMode == .pushToTalk {
            switch wakeProfile.syncState {
            case .notRequired:
                return VoiceReadinessCheck(
                    kind: .wakeProfileReadiness,
                    state: .ready,
                    reasonCode: "push_to_talk_only",
                    headline: "Wake profile is ready in push-to-talk mode",
                    summary: "Push-to-talk remains the safest fallback when background wake is not required.",
                    nextStep: "You can start voice capture manually without enabling background wake.",
                    repairEntry: .xtDiagnostics,
                    detailLines: details
                )
            case .waitingForPairing:
                return VoiceReadinessCheck(
                    kind: .wakeProfileReadiness,
                    state: .inProgress,
                    reasonCode: wakeProfile.reasonCode,
                    headline: "Wake profile is waiting for pairing or sync bootstrap",
                    summary: "Wake contract has not been paired in yet, so XT keeps the runtime on push-to-talk instead of pretending background wake is live.",
                    nextStep: "Finish Hub pairing or keep using push-to-talk until wake profile sync becomes available.",
                    repairEntry: .xtPairHub,
                    detailLines: details
                )
            case .stale:
                return VoiceReadinessCheck(
                    kind: .wakeProfileReadiness,
                    state: .diagnosticRequired,
                    reasonCode: wakeProfile.reasonCode,
                    headline: "Wake profile exists, but the paired sync is stale",
                    summary: "XT preserved the last known profile for audit, but background wake is downgraded to push-to-talk until a fresh sync arrives.",
                    nextStep: "Refresh the paired wake profile or switch to a fresh local override before using wake phrase mode again.",
                    repairEntry: .xtPairHub,
                    detailLines: details
                )
            case .syncUnavailable, .invalid:
                return VoiceReadinessCheck(
                    kind: .wakeProfileReadiness,
                    state: .diagnosticRequired,
                    reasonCode: wakeProfile.reasonCode,
                    headline: "Wake profile sync is unavailable, so runtime stays on push-to-talk",
                    summary: "XT keeps the last known contract visible, but it will not claim background wake is active without a usable wake profile source.",
                    nextStep: "Repair wake profile sync or keep the route on push-to-talk for this device.",
                    repairEntry: .xtDiagnostics,
                    detailLines: details
                )
            case .pairedSynced, .localOverrideActive:
                break
            }
        }

        if routeDecision.route == .failClosed {
            return VoiceReadinessCheck(
                kind: .wakeProfileReadiness,
                state: .diagnosticRequired,
                reasonCode: routeDecision.reasonCode,
                headline: "Wake profile is blocked because the current voice route is fail-closed",
                summary: "XT will not pretend wake is available while the active route is fail-closed.",
                nextStep: "Repair the active voice route or switch back to push-to-talk until live capture is healthy.",
                repairEntry: .xtDiagnostics,
                detailLines: details
            )
        }

        if routeDecision.wakeCapability != "funasr_kws" {
            return VoiceReadinessCheck(
                kind: .wakeProfileReadiness,
                state: .inProgress,
                reasonCode: "wake_phrase_requires_funasr_kws",
                headline: "Wake profile is configured, but the current route does not expose keyword spotting",
                summary: "The selected wake mode expects live keyword spotting, but the current route only supports push-to-talk style capture.",
                nextStep: "Enable a healthy FunASR route for wake phrase mode, or switch the wake mode back to push-to-talk.",
                repairEntry: .xtDiagnostics,
                detailLines: details
            )
        }

        if wakeProfile.syncState == .localOverrideActive {
            return VoiceReadinessCheck(
                kind: .wakeProfileReadiness,
                state: .ready,
                reasonCode: wakeProfile.reasonCode,
                headline: "Wake profile is ready with a local device override",
                summary: "XT has a valid local wake contract for this device. Pair-synced vocabulary can replace it later without weakening the current fail-closed boundaries.",
                nextStep: "Use wake locally now, or pair Hub sync if you want the same wake contract on other devices.",
                repairEntry: .xtPairHub,
                detailLines: details
            )
        }

        return VoiceReadinessCheck(
            kind: .wakeProfileReadiness,
            state: .ready,
            reasonCode: wakeProfile.reasonCode == "wake_profile_pair_synced" ? wakeProfile.reasonCode : "wake_phrase_ready",
            headline: wakeProfile.syncState == .pairedSynced
                ? "Wake profile is ready and pair-synced"
                : "Wake profile is ready",
            summary: wakeProfile.syncState == .pairedSynced
                ? "The current route exposes keyword spotting and the wake contract is aligned with the paired Hub profile."
                : "The current route exposes keyword spotting and the selected wake mode can open a Supervisor session safely.",
            nextStep: "Use wake to open the shared Supervisor conversation window.",
            repairEntry: .homeSupervisor,
            detailLines: details
        )
    }

    private static func buildTalkLoopCheck(
        toolRouteExecutable: Bool,
        routeDecision: VoiceRouteDecision,
        runtimeState: SupervisorVoiceRuntimeState,
        authorizationStatus: VoiceTranscriberAuthorizationStatus,
        conversationSession: SupervisorConversationSessionSnapshot
    ) -> VoiceReadinessCheck {
        let details = [
            "tool_route_executable=\(toolRouteExecutable)",
            "route=\(routeDecision.route.rawValue)",
            "voice_state=\(runtimeState.state.rawValue)",
            "conversation_state=\(conversationSession.windowState.rawValue)",
            "authorization=\(authorizationStatus.rawValue)",
            runtimeState.reasonCode?.isEmpty == false ? "runtime_reason=\(runtimeState.reasonCode!)" : "runtime_reason=none"
        ]

        if !toolRouteExecutable {
            return VoiceReadinessCheck(
                kind: .talkLoopReadiness,
                state: .blockedWaitingUpstream,
                reasonCode: "tool_route_not_executable",
                headline: "Talk loop waits for the tool route to become executable",
                summary: "Until the bridge / tool route is ready, runtime verification must stay blocked instead of pretending the session can recover by itself.",
                nextStep: "Repair bridge / tool readiness first, then come back to voice verify.",
                repairEntry: .hubDiagnostics,
                detailLines: details
            )
        }

        if authorizationStatus == .denied || authorizationStatus == .restricted {
            return VoiceReadinessCheck(
                kind: .talkLoopReadiness,
                state: .permissionDenied,
                reasonCode: "speech_authorization_denied",
                headline: "Talk loop is blocked by microphone or speech permission",
                summary: "Continuous voice interaction remains blocked until live capture permission is restored.",
                nextStep: "Grant microphone and speech-recognition permission in macOS Settings, then refresh voice runtime.",
                repairEntry: .systemPermissions,
                detailLines: details
            )
        }

        if routeDecision.route == .failClosed || runtimeState.state == .failClosed {
            return VoiceReadinessCheck(
                kind: .talkLoopReadiness,
                state: .diagnosticRequired,
                reasonCode: runtimeState.reasonCode ?? routeDecision.reasonCode,
                headline: "Talk loop is unavailable on the current route",
                summary: "The active voice route is fail-closed, so XT will not claim that short-lived persistent conversation can self-heal.",
                nextStep: "Repair the active voice route or stay on manual text / push-to-talk until live capture is healthy.",
                repairEntry: .xtDiagnostics,
                detailLines: details
            )
        }

        if !routeDecision.route.supportsLiveCapture {
            return VoiceReadinessCheck(
                kind: .talkLoopReadiness,
                state: .inProgress,
                reasonCode: "manual_text_only",
                headline: "Talk loop is not active on a live-capture route yet",
                summary: "The current route is not a live audio route, so XT can only keep the conversation open through text turns.",
                nextStep: "Switch to a live voice route if you want continuous voice conversation.",
                repairEntry: .xtDiagnostics,
                detailLines: details
            )
        }

        if conversationSession.isConversing || runtimeState.state == .listening || runtimeState.state == .transcribing {
            return VoiceReadinessCheck(
                kind: .talkLoopReadiness,
                state: .inProgress,
                reasonCode: "talk_loop_active",
                headline: "Talk loop is active",
                summary: "Voice runtime is currently listening or transcribing inside the shared Supervisor conversation session.",
                nextStep: "Finish the current turn or let the session return to idle before changing runtime settings.",
                repairEntry: .homeSupervisor,
                detailLines: details
            )
        }

        return VoiceReadinessCheck(
            kind: .talkLoopReadiness,
            state: .ready,
            reasonCode: "talk_loop_ready",
            headline: "Talk loop foundation is ready",
            summary: "The live voice route is healthy enough for the shared Supervisor conversation session to enter continuous talk mode later.",
            nextStep: "Use wake or push-to-talk to start a new Supervisor voice turn.",
            repairEntry: .homeSupervisor,
            detailLines: details
        )
    }

    private static func buildTTSCheck(
        toolRouteExecutable: Bool,
        routeDecision: VoiceRouteDecision
    ) -> VoiceReadinessCheck {
        let details = [
            "provider=system_fallback",
            "tool_route_executable=\(toolRouteExecutable)",
            "voice_route=\(routeDecision.route.rawValue)"
        ]

        return VoiceReadinessCheck(
            kind: .ttsReadiness,
            state: .ready,
            reasonCode: "system_tts_fallback_ready",
            headline: "Voice playback fallback is ready",
            summary: "Supervisor voice playback still has a local system TTS fallback even before streaming playback providers are introduced.",
            nextStep: "Use current blocker / authorization playback as the baseline before enabling richer playback providers.",
            repairEntry: .homeSupervisor,
            detailLines: details
        )
    }

    private static func orderedUnique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var ordered: [String] = []
        for raw in values {
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { continue }
            if seen.insert(value).inserted {
                ordered.append(value)
            }
        }
        return ordered
    }

    private static func portLooksValid(_ value: Int) -> Bool {
        (1...65_535).contains(value)
    }

    private static func runtimeBusy(_ state: AXSessionRuntimeState) -> Bool {
        switch state {
        case .planning, .awaiting_model, .awaiting_tool_approval, .running_tools, .awaiting_hub:
            return true
        case .idle, .failed_recoverable, .completed:
            return false
        }
    }

    private static func overallState(for checks: [VoiceReadinessCheck]) -> XTUISurfaceState {
        if checks.allSatisfy({ $0.state == .ready }) {
            return .ready
        }
        let orderedStates: [XTUISurfaceState] = [
            .permissionDenied,
            .grantRequired,
            .diagnosticRequired,
            .blockedWaitingUpstream,
            .releaseFrozen,
            .inProgress,
            .ready
        ]
        for state in orderedStates {
            if checks.contains(where: { $0.state == state }) {
                return state
            }
        }
        return .diagnosticRequired
    }
}
