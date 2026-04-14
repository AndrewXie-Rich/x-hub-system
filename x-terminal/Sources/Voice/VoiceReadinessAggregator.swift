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
            return "配对有效性"
        case .modelRouteReadiness:
            return "模型路由就绪"
        case .bridgeToolReadiness:
            return "桥接 / 工具就绪"
        case .sessionRuntimeReadiness:
            return "会话运行时就绪"
        case .wakeProfileReadiness:
            return "唤醒配置就绪"
        case .talkLoopReadiness:
            return "对话链路就绪"
        case .ttsReadiness:
            return "语音播放就绪"
        }
    }

    var contributesToFirstTaskReadiness: Bool {
        switch self {
        case .modelRouteReadiness, .bridgeToolReadiness, .sessionRuntimeReadiness:
            return true
        case .pairingValidity, .wakeProfileReadiness, .talkLoopReadiness, .ttsReadiness:
            return false
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
            case .wakeProfileReadiness:
                return .wakeProfileReadiness
            case .talkLoopReadiness:
                return .talkLoopReadiness
            case .ttsReadiness:
                return .voicePlaybackReadiness
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
        overallSummary: "语音就绪状态待检查。",
        primaryReasonCode: "",
        orderedFixes: [],
        checks: [],
        nodeSync: .empty
    )

    func check(_ kind: VoiceReadinessCheckKind) -> VoiceReadinessCheck? {
        checks.first { $0.kind == kind }
    }

    var readyForFirstTask: Bool {
        firstTaskBlockingCheck == nil
    }

    var firstTaskBlockingCheck: VoiceReadinessCheck? {
        checks.first {
            $0.kind.contributesToFirstTaskReadiness && $0.state != .ready
        }
    }

    var firstAdvisoryCheck: VoiceReadinessCheck? {
        checks.first {
            !$0.kind.contributesToFirstTaskReadiness && $0.state != .ready
        }
    }

    static func summaryLine(
        overallState: XTUISurfaceState,
        checks: [VoiceReadinessCheck]
    ) -> String {
        if let firstTaskBlockingCheck = checks.first(where: {
            $0.kind.contributesToFirstTaskReadiness && failClosedSummaryPriority(for: $0.state) != nil
        }) {
            return "当前为 fail-closed：\(firstTaskBlockingCheck.kind.title) 仍未就绪：\(firstTaskBlockingCheck.headline)"
        }

        if let firstTaskInProgressCheck = checks.first(where: {
            $0.kind.contributesToFirstTaskReadiness && $0.state == .inProgress
        }) {
            return "当前仍在收敛：\(firstTaskInProgressCheck.kind.title)仍在处理中：\(firstTaskInProgressCheck.headline)"
        }

        if let firstAdvisoryCheck = checks.first(where: {
            !$0.kind.contributesToFirstTaskReadiness && $0.state != .ready
        }) {
            return "首个任务已可启动，但\(firstAdvisoryCheck.kind.title)仍需修复：\(firstAdvisoryCheck.headline)"
        }

        switch overallState {
        case .ready:
            if let pairingCheck = checks.first(where: { $0.kind == .pairingValidity && $0.state == .ready }),
               pairingCheck.detailLines.contains("paired_route_readiness=remote_ready")
                || pairingCheck.headline == "正式异网入口已验证，切网后可继续工作" {
                return "首个任务已可启动，正式异网入口已验证，切网后可继续工作"
            }
            return "配对、语音链路、桥接、会话运行时、唤醒、对话链路和播放都已通过检查"
        case .inProgress:
            return checks.first(where: { $0.state == .inProgress })?.headline
                ?? "语音就绪状态仍在收敛。"
        case .blockedWaitingUpstream:
            return checks.first(where: { $0.state == .blockedWaitingUpstream })?.headline
                ?? "语音就绪状态被上游依赖阻塞。"
        case .grantRequired:
            return checks.first(where: { $0.state == .grantRequired })?.headline
                ?? "语音就绪状态还需要授权批准。"
        case .permissionDenied:
            return checks.first(where: { $0.state == .permissionDenied })?.headline
                ?? "语音就绪状态被权限拒绝阻塞。"
        case .releaseFrozen, .diagnosticRequired:
            return checks.first(where: { $0.state == .diagnosticRequired || $0.state == .releaseFrozen })?.headline
                ?? "语音就绪状态需要进一步诊断。"
        }
    }

    private static func failClosedSummaryPriority(for state: XTUISurfaceState) -> Int? {
        switch state {
        case .permissionDenied, .grantRequired, .diagnosticRequired, .blockedWaitingUpstream, .releaseFrozen:
            return 0
        case .inProgress, .ready:
            return nil
        }
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
    var bridgeLastError: String = ""
    var sessionID: String?
    var sessionTitle: String?
    var sessionRuntime: AXSessionRuntimeSnapshot?
    var voiceRouteDecision: VoiceRouteDecision
    var voiceRuntimeState: SupervisorVoiceRuntimeState
    var voiceAuthorizationStatus: VoiceTranscriberAuthorizationStatus
    var voicePermissionSnapshot: VoicePermissionSnapshot
    var voiceActiveHealthReasonCode: String
    var voiceSidecarHealth: VoiceSidecarHealthSnapshot?
    var wakeProfileSnapshot: VoiceWakeProfileSnapshot
    var conversationSession: SupervisorConversationSessionSnapshot
    var voicePreferences: VoiceRuntimePreferences
    var voicePackReadyEvaluator: (@Sendable (String) -> Bool)?
    var firstPairCompletionProofSnapshot: XTFirstPairCompletionProofSnapshot? = nil
    var pairedRouteSetSnapshot: XTPairedRouteSetSnapshot? = nil

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
            bridgeLastError: input.bridgeLastError,
            sessionID: input.sessionID,
            sessionTitle: input.sessionTitle,
            sessionRuntime: input.sessionRuntime,
            voiceRouteDecision: input.voiceRouteDecision,
            voiceRuntimeState: input.voiceRuntimeState,
            voiceAuthorizationStatus: input.voiceAuthorizationStatus,
            voicePermissionSnapshot: input.voicePermissionSnapshot,
            voiceActiveHealthReasonCode: input.voiceActiveHealthReasonCode,
            voiceSidecarHealth: input.voiceSidecarHealth,
            wakeProfileSnapshot: input.wakeProfileSnapshot,
            conversationSession: input.conversationSession,
            voicePreferences: input.voicePreferences,
            voicePackReadyEvaluator: { modelID in
                HubIPCClient.isLocalHubVoicePackPlaybackAvailable(
                    preferredModelID: modelID
                )
            },
            firstPairCompletionProofSnapshot: input.firstPairCompletionProofSnapshot,
            pairedRouteSetSnapshot: input.pairedRouteSetSnapshot
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
        let interactiveLoadedModels = availableModels.filter { $0.state == .loaded && $0.isSelectableForInteractiveRouting }
        let localInteractiveLoadedCount = interactiveLoadedModels.filter(\.isLocalModel).count
        let remoteInteractiveLoadedCount = interactiveLoadedModels.count - localInteractiveLoadedCount
        let availableModelIDs = Set(availableModels.map(\.id))
        let missingAssignedModels = configuredModelIDs.filter { !availableModelIDs.contains($0) }
        let toolRouteExecutable = toolRouteExecutable(
            localConnected: input.localConnected,
            remoteConnected: input.remoteConnected,
            bridgeAlive: input.bridgeAlive,
            bridgeEnabled: input.bridgeEnabled
        )
        let sessionSnapshot = input.sessionRuntime ?? AXSessionRuntimeSnapshot.idle()

        let pairing = enrichPairingValidityCheck(
            buildPairingValidityCheck(
                input: input,
                host: trimmedHost,
                pairingLooksValid: pairingLooksValid,
                pairingMatchesConvention: pairingMatchesConvention
            ),
            firstPairCompletionProofSnapshot: input.firstPairCompletionProofSnapshot,
            pairedRouteSetSnapshot: input.pairedRouteSetSnapshot
        )
        let modelRoute = buildModelRouteCheck(
            hubInteractive: hubInteractive,
            runtimeAlive: runtimeAlive,
            runtimeStatus: input.runtimeStatus,
            availableModelCount: availableModelCount,
            loadedModelCount: loadedModelCount,
            localInteractiveLoadedCount: localInteractiveLoadedCount,
            remoteInteractiveLoadedCount: remoteInteractiveLoadedCount,
            configuredModelCount: configuredModelCount,
            totalModelRoles: input.totalModelRoles,
            missingAssignedModels: missingAssignedModels,
            configuredModelIDs: configuredModelIDs
        )
        let bridge = buildBridgeToolCheck(
            localConnected: input.localConnected,
            remoteConnected: input.remoteConnected,
            hubInteractive: hubInteractive,
            modelRouteReady: modelRoute.state == .ready,
            bridgeAlive: input.bridgeAlive,
            bridgeEnabled: input.bridgeEnabled,
            bridgeLastError: input.bridgeLastError,
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
            permissionSnapshot: input.voicePermissionSnapshot,
            wakeProfile: input.wakeProfileSnapshot,
            conversationSession: input.conversationSession,
            activeHealthReasonCode: input.voiceActiveHealthReasonCode
        )
        let talkLoop = buildTalkLoopCheck(
            toolRouteExecutable: toolRouteExecutable,
            routeDecision: input.voiceRouteDecision,
            runtimeState: input.voiceRuntimeState,
            authorizationStatus: input.voiceAuthorizationStatus,
            permissionSnapshot: input.voicePermissionSnapshot,
            conversationSession: input.conversationSession
        )
        let tts = buildTTSCheck(
            toolRouteExecutable: toolRouteExecutable,
            routeDecision: input.voiceRouteDecision,
            preferences: input.voicePreferences,
            modelsState: input.modelsState,
            voicePackReadyEvaluator: input.voicePackReadyEvaluator
        )

        let checks = [pairing, modelRoute, bridge, session, wake, talkLoop, tts]
        let overallState = overallState(for: checks)
        let orderedFixes = orderedUnique(checks.compactMap { check in
            check.state == .ready ? nil : check.nextStep
        })
        let primaryReasonCode = checks.first(where: { $0.state != .ready })?.reasonCode ?? "voice_readiness_ready"
        let overallSummary = VoiceReadinessSnapshot.summaryLine(
            overallState: overallState,
            checks: checks
        )

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
                headline: "配对参数暂时无效",
                summary: "在信任语音 / 运行时引导之前，Pairing Port 和 gRPC Port 必须是明确且彼此不同的值。",
                nextStep: "去 REL Flow Hub → LAN (gRPC) 复制 Pairing Port 和 gRPC Port，然后重新执行 Pair Hub。",
                repairEntry: .xtPairHub,
                detailLines: details
            )
        }

        if input.remoteConnected {
            return VoiceReadinessCheck(
                kind: .pairingValidity,
                state: .ready,
                reasonCode: "pairing_values_match_active_remote_route",
                headline: "配对参数已匹配当前远端链路",
                summary: "同一组 Pairing Port / gRPC Port / Internet Host 已经成功建立过可用的远端连接。",
                nextStep: "后续重连时继续保留这组值即可。",
                repairEntry: .xtPairHub,
                detailLines: details
            )
        }

        if !host.isEmpty {
            return VoiceReadinessCheck(
                kind: .pairingValidity,
                state: .ready,
                reasonCode: "pairing_values_explicit",
                headline: "配对参数已明确，可重复复用",
                summary: "X-Terminal 已经拿到了用户可见的全部配对字段：Pairing Port、gRPC Port 和 Internet Host。",
                nextStep: "后续做 LAN、VPN 或隧道配对时，直接复用这组值即可，不需要重新到别处查找。",
                repairEntry: .xtPairHub,
                detailLines: details
            )
        }

        if input.localConnected || input.linking {
            return VoiceReadinessCheck(
                kind: .pairingValidity,
                state: .inProgress,
                reasonCode: "remote_bootstrap_values_incomplete",
                headline: "本机链路可用，但远端引导参数还不完整",
                summary: "同机验证可以继续，但 Internet Host 仍为空，所以第二台设备还不知道该填什么。",
                nextStep: "先去 REL Flow Hub → LAN (gRPC) 复制 Internet Host 到 X-Terminal，再做远端配对。",
                repairEntry: .xtPairHub,
                detailLines: details
            )
        }

        return VoiceReadinessCheck(
            kind: .pairingValidity,
            state: .diagnosticRequired,
            reasonCode: "pairing_values_incomplete_for_bootstrap",
            headline: "配对参数不足以完成引导",
            summary: "如果没有明确的 Internet Host，面向 LAN / VPN / 隧道设备的配对路径就是不完整的。",
            nextStep: "去 REL Flow Hub → LAN (gRPC) 复制 Internet Host，然后重新执行一键设置。",
            repairEntry: .xtPairHub,
            detailLines: details
        )
    }

    private static func enrichPairingValidityCheck(
        _ base: VoiceReadinessCheck,
        firstPairCompletionProofSnapshot: XTFirstPairCompletionProofSnapshot?,
        pairedRouteSetSnapshot: XTPairedRouteSetSnapshot?
    ) -> VoiceReadinessCheck {
        guard let pairingContext = UITroubleshootPairingContext(
            firstPairCompletionProofSnapshot: firstPairCompletionProofSnapshot,
            pairedRouteSetSnapshot: pairedRouteSetSnapshot
        ) else {
            return base
        }

        var check = base
        check.detailLines = orderedUnique(
            base.detailLines + pairingReadinessDetailLines(
                firstPairCompletionProofSnapshot: firstPairCompletionProofSnapshot,
                pairedRouteSetSnapshot: pairedRouteSetSnapshot,
                pairingContext: pairingContext
            )
        )

        let stableHost = normalizedPairingField(pairingContext.stableRemoteHost)
        let stableHostSuffix = stableHost.map { "（host=\($0)）" } ?? ""
        let readinessReasonCode = normalizedPairingField(pairedRouteSetSnapshot?.readinessReasonCode)
        let remoteShadowReasonCode = normalizedPairingField(firstPairCompletionProofSnapshot?.remoteShadowReasonCode)

        switch pairingContext.readiness {
        case .remoteReady:
            check.state = .ready
            check.reasonCode = readinessReasonCode ?? "paired_remote_route_ready"
            check.headline = "正式异网入口已验证，切网后可继续工作"
            check.summary = [
                "同网首配、本机批准和正式异网入口已经闭环\(stableHostSuffix)。",
                "切网后，XT 会优先沿这条已验证的正式入口继续连接 Hub。"
            ].joined(separator: " ")
            check.nextStep = "继续保留当前配对档案与正式入口；只有更换 Hub、重置配对材料或入口变更时才需要重新批准。"
        case .remoteBlocked:
            check.state = .diagnosticRequired
            check.reasonCode = readinessReasonCode ?? remoteShadowReasonCode ?? "paired_remote_route_blocked"
            check.headline = "正式异网入口存在，但被配对或身份边界阻断"
            check.summary = [
                "同网首配已经完成，XT 也有正式异网入口\(stableHostSuffix)，但当前被配对或身份边界挡住。",
                "这不是“重新首配就会自己好”的问题，先修批准、证书、令牌或身份约束。"
            ].joined(separator: " ")
            check.nextStep = "先保留现有配对档案，在 XT 连接 Hub 查看当前失败原因；再到 Hub 的配对与设备信任或诊断与恢复修复身份/批准边界。"
        case .remoteDegraded:
            check.state = .diagnosticRequired
            check.reasonCode = readinessReasonCode ?? remoteShadowReasonCode ?? "paired_remote_route_degraded"
            check.headline = "正式异网入口存在，但切网续连目前不稳定"
            check.summary = [
                "同网首配已经完成，XT 也拿到了正式异网入口\(stableHostSuffix)，但最近一次正式异网验证没有通过。",
                "离开当前 Wi-Fi 后，还不能把这条路径当成稳定可恢复。"
            ].joined(separator: " ")
            check.nextStep = "先检查 Hub app 是否在线、pairing / gRPC 端口是否还在监听，以及防火墙、NAT、relay 或 tailnet 路由；修好后再重跑异网验证。"
        case .localReady:
            if pairingContext.formalRemoteVerificationPending {
                check.state = .inProgress
                check.reasonCode = readinessReasonCode ?? "paired_remote_verification_pending"
                check.headline = "同网首配已完成，正在验证正式异网入口"
                check.summary = [
                    "同网首配和 Hub 本地批准已经完成，XT 也拿到了正式异网入口\(stableHostSuffix)。",
                    "当前正在补跑正式异网验证，在它真正通过前，不要把状态误判成已经可以无感切网。"
                ].joined(separator: " ")
                check.nextStep = "先保留当前配对档案，等待这轮正式异网验证结束；如果长时间不通过，再检查 Hub 的 stable remote host、relay / tailnet / DNS 和端口可达性。"
            } else {
                check.state = .inProgress
                check.reasonCode = readinessReasonCode ?? "paired_formal_remote_route_missing"
                check.headline = "同网首配已完成，但还没有正式异网入口"
                check.summary = [
                    "同网首配和 Hub 本地批准已经完成，但 XT 还没有稳定命名的正式异网入口。",
                    "当前留在同网环境可以继续用；离开当前 Wi-Fi 后还不能保证继续连回 Hub。"
                ].joined(separator: " ")
                check.nextStep = "先在 Hub 配置 tailnet、relay 或 DNS 这类正式异网入口，再回 XT 刷新配对资料并补一轮异网验证。"
            }
        case .unknown:
            break
        }

        return check
    }

    private static func pairingReadinessDetailLines(
        firstPairCompletionProofSnapshot: XTFirstPairCompletionProofSnapshot?,
        pairedRouteSetSnapshot: XTPairedRouteSetSnapshot?,
        pairingContext: UITroubleshootPairingContext
    ) -> [String] {
        var lines = [
            "paired_route_readiness=\(pairingContext.readiness.rawValue)",
            "pairing_formal_remote_verification_pending=\(pairingContext.formalRemoteVerificationPending)",
            "pairing_remote_shadow_failed=\(pairingContext.remoteShadowFailed)"
        ]

        if let pairedRouteSetSnapshot {
            lines.append("paired_route_reason_code=\(pairedRouteSetSnapshot.readinessReasonCode)")
            lines.append("paired_route_summary=\(pairedRouteSetSnapshot.summaryLine)")

            if let activeRoute = pairedRouteSetSnapshot.activeRoute {
                lines.append("paired_active_route=\(pairedRouteTargetSummary(activeRoute))")
            }
            if let stableRemoteRoute = pairedRouteSetSnapshot.stableRemoteRoute {
                lines.append("paired_stable_remote_route=\(pairedRouteTargetSummary(stableRemoteRoute))")
            }
            if let lastKnownGoodRoute = pairedRouteSetSnapshot.lastKnownGoodRoute {
                lines.append("paired_last_known_good_route=\(pairedRouteTargetSummary(lastKnownGoodRoute))")
            }
            if let cachedReconnectSmokeStatus = normalizedPairingField(pairedRouteSetSnapshot.cachedReconnectSmokeStatus) {
                lines.append("paired_cached_reconnect_smoke_status=\(cachedReconnectSmokeStatus)")
            }
            if let cachedReconnectSmokeReasonCode = normalizedPairingField(pairedRouteSetSnapshot.cachedReconnectSmokeReasonCode) {
                lines.append("paired_cached_reconnect_smoke_reason_code=\(cachedReconnectSmokeReasonCode)")
            }
            if let cachedReconnectSmokeSummary = normalizedPairingField(pairedRouteSetSnapshot.cachedReconnectSmokeSummary) {
                lines.append("paired_cached_reconnect_smoke_summary=\(cachedReconnectSmokeSummary)")
            }
        }

        if let firstPairCompletionProofSnapshot {
            lines.append("first_pair_proof_readiness=\(firstPairCompletionProofSnapshot.readiness.rawValue)")
            lines.append("first_pair_same_lan_verified=\(firstPairCompletionProofSnapshot.sameLanVerified)")
            lines.append("first_pair_owner_local_approval_verified=\(firstPairCompletionProofSnapshot.ownerLocalApprovalVerified)")
            lines.append("first_pair_pairing_material_issued=\(firstPairCompletionProofSnapshot.pairingMaterialIssued)")
            lines.append("first_pair_cached_reconnect_smoke_passed=\(firstPairCompletionProofSnapshot.cachedReconnectSmokePassed)")
            lines.append("first_pair_stable_remote_route_present=\(firstPairCompletionProofSnapshot.stableRemoteRoutePresent)")
            lines.append("first_pair_remote_shadow_status=\(firstPairCompletionProofSnapshot.remoteShadowSmokeStatus.rawValue)")
            lines.append("first_pair_summary=\(firstPairCompletionProofSnapshot.summaryLine)")

            if let remoteShadowSource = firstPairCompletionProofSnapshot.remoteShadowSmokeSource?.rawValue {
                lines.append("first_pair_remote_shadow_source=\(remoteShadowSource)")
            }
            if let remoteShadowRoute = firstPairCompletionProofSnapshot.remoteShadowRoute?.rawValue {
                lines.append("first_pair_remote_shadow_route=\(remoteShadowRoute)")
            }
            if let remoteShadowReasonCode = normalizedPairingField(firstPairCompletionProofSnapshot.remoteShadowReasonCode) {
                lines.append("first_pair_remote_shadow_reason_code=\(remoteShadowReasonCode)")
            }
            if let remoteShadowSummary = normalizedPairingField(firstPairCompletionProofSnapshot.remoteShadowSummary) {
                lines.append("first_pair_remote_shadow_summary=\(remoteShadowSummary)")
            }
        }

        return lines
    }

    private static func pairedRouteTargetSummary(_ target: XTPairedRouteTargetSnapshot) -> String {
        "\(target.routeKind.rawValue):\(target.host):pairing=\(target.pairingPort),grpc=\(target.grpcPort),source=\(target.source.rawValue)"
    }

    private static func buildModelRouteCheck(
        hubInteractive: Bool,
        runtimeAlive: Bool,
        runtimeStatus: AIRuntimeStatus?,
        availableModelCount: Int,
        loadedModelCount: Int,
        localInteractiveLoadedCount: Int,
        remoteInteractiveLoadedCount: Int,
        configuredModelCount: Int,
        totalModelRoles: Int,
        missingAssignedModels: [String],
        configuredModelIDs: [String]
    ) -> VoiceReadinessCheck {
        let interactivePosture: String
        switch (localInteractiveLoadedCount > 0, remoteInteractiveLoadedCount > 0) {
        case (true, false):
            interactivePosture = "local_only"
        case (false, true):
            interactivePosture = "remote_only"
        case (true, true):
            interactivePosture = "mixed"
        case (false, false):
            interactivePosture = "none"
        }

        let providerStateCode = runtimeStatus?.providerReadinessStateCode(ttl: 3.0)

        var details = [
            "runtime_alive=\(runtimeAlive)",
            "available_models=\(availableModelCount)",
            "loaded_models=\(loadedModelCount)",
            "interactive_local_loaded=\(localInteractiveLoadedCount)",
            "interactive_remote_loaded=\(remoteInteractiveLoadedCount)",
            "interactive_posture=\(interactivePosture)",
            "configured_roles=\(configuredModelCount)/\(totalModelRoles)",
            configuredModelIDs.isEmpty ? "configured_model_ids=none" : "configured_model_ids=\(configuredModelIDs.joined(separator: ","))"
        ]
        if !missingAssignedModels.isEmpty {
            details.append("missing_assigned_models=\(missingAssignedModels.joined(separator: ","))")
        }
        if let runtimeStatus {
            details = orderedUnique(details + runtimeStatus.providerReadinessDetailLines(ttl: 3.0))
        }

        if !hubInteractive {
            return VoiceReadinessCheck(
                kind: .modelRouteReadiness,
                state: .blockedWaitingUpstream,
                reasonCode: "hub_route_not_interactive",
                headline: "模型路由正在等待可用的 Hub 链路",
                summary: "在 Hub 可达性真正进入 interactive 之前，XT 无法确认哪些模型实际可用。",
                nextStep: "先完成 Pair Hub，再回到 Supervisor Control Center · AI 模型。",
                repairEntry: .xtChooseModel,
                detailLines: details
            )
        }

        if availableModelCount == 0 {
            if providerStateCode == "runtime_heartbeat_stale" {
                return VoiceReadinessCheck(
                    kind: .modelRouteReadiness,
                    state: .diagnosticRequired,
                    reasonCode: "runtime_heartbeat_stale",
                    headline: "本地 provider 心跳已过期，模型清单当前不可信",
                    summary: "Hub 已可达，但本地 runtime/provider 心跳已过期，所以 XT 当前拿不到可信的本地模型清单。",
                    nextStep: "先到 REL Flow Hub 重启或刷新本地运行时，再回到 Supervisor Control Center · AI 模型刷新真实可执行列表，然后重新执行 Verify。",
                    repairEntry: .xtChooseModel,
                    detailLines: details
                )
            }

            if providerStateCode == "no_ready_provider" {
                return VoiceReadinessCheck(
                    kind: .modelRouteReadiness,
                    state: .diagnosticRequired,
                    reasonCode: "no_ready_provider",
                    headline: "本地 provider 全部未就绪，模型路由当前不可用",
                    summary: "Hub 已可达，但本地 provider 当前全部未就绪，所以 XT 还看不到任何真正可执行的本地模型。",
                    nextStep: "先到 REL Flow Hub → Models & Paid Access 检查 provider pack、helper 服务和导入失败原因，确认至少有一个 provider ready；再回到 Supervisor Control Center · AI 模型刷新真实可执行列表。",
                    repairEntry: .xtChooseModel,
                    detailLines: details
                )
            }

            if providerStateCode == "provider_partial_readiness" {
                return VoiceReadinessCheck(
                    kind: .modelRouteReadiness,
                    state: .diagnosticRequired,
                    reasonCode: "provider_partial_readiness",
                    headline: "本地 provider 只有部分就绪，当前模型清单可能缺项",
                    summary: "Hub 已可达，但本地 provider 只起来了一部分，所以 XT 现在看到的模型目录和能力覆盖还不完整。",
                    nextStep: "先到 REL Flow Hub → Models & Paid Access 检查还没起来的 provider pack 和 runtime；确认目标 provider ready 后，再回 Supervisor Control Center · AI 模型刷新列表。",
                    repairEntry: .xtChooseModel,
                    detailLines: details
                )
            }

            return VoiceReadinessCheck(
                kind: .modelRouteReadiness,
                state: .diagnosticRequired,
                reasonCode: "model_inventory_empty",
                headline: "配对已通，但模型路由不可用",
                summary: "Hub 已可达，但 XT 还看不到任何可用模型。这个问题需要和配对失败、授权失败区分开。",
                nextStep: "先到 REL Flow Hub → Models & Paid Access 确认至少有一个模型已激活且 provider ready；再回到 Supervisor Control Center · AI 模型确认它进入真实可执行列表，然后重新执行 Verify。",
                repairEntry: .xtChooseModel,
                detailLines: details
            )
        }

        if configuredModelCount == 0 {
            return VoiceReadinessCheck(
                kind: .modelRouteReadiness,
                state: .inProgress,
                reasonCode: "xt_role_assignment_empty",
                headline: "Hub 模型可见，但 XT 的角色分配还是空的",
                summary: "模型路由已经存在，但 X-Terminal 还没有把任何角色绑定到具体的 Hub 模型上。",
                nextStep: "至少先在 Supervisor Control Center · AI 模型里给 coder 和 supervisor 分配模型。",
                repairEntry: .xtChooseModel,
                detailLines: details
            )
        }

        if !missingAssignedModels.isEmpty {
            return VoiceReadinessCheck(
                kind: .modelRouteReadiness,
                state: .diagnosticRequired,
                reasonCode: "assigned_model_missing_from_inventory",
                headline: "XT 的角色分配指向了当前未暴露的模型",
                summary: "虽然配对成功，但至少有一个已分配的模型 ID 不在当前的 Hub 模型清单里。",
                nextStep: "去 Supervisor Control Center · AI 模型替换过期模型 ID；如果目标模型已在 Hub 侧停用，再到 REL Flow Hub → Models & Paid Access 重新启用。",
                repairEntry: .xtChooseModel,
                detailLines: details
            )
        }

        if interactivePosture == "local_only", providerStateCode == "runtime_heartbeat_stale" {
            return VoiceReadinessCheck(
                kind: .modelRouteReadiness,
                state: .diagnosticRequired,
                reasonCode: "runtime_heartbeat_stale",
                headline: "当前走纯本地，但本地 provider 心跳已过期",
                summary: "XT 现在只剩本地模型路径，但本地 runtime/provider 心跳已过期，所以这条执行链不应继续当成可信状态。",
                nextStep: "先到 REL Flow Hub 重启或刷新本地运行时，确认 provider 心跳恢复后，再回 Supervisor Control Center · AI 模型重新验证。",
                repairEntry: .xtChooseModel,
                detailLines: details
            )
        }

        if interactivePosture == "local_only", providerStateCode == "no_ready_provider" {
            return VoiceReadinessCheck(
                kind: .modelRouteReadiness,
                state: .diagnosticRequired,
                reasonCode: "no_ready_provider",
                headline: "当前走纯本地，但本地 provider 全部未就绪",
                summary: "XT 当前只看到本地模型路径，可 Hub 报告本地 provider 全部未就绪，所以这条纯本地执行链还不能继续当成可执行状态。",
                nextStep: "先到 REL Flow Hub → Models & Paid Access 修复本地 provider，就绪后再回 Supervisor Control Center · AI 模型重新验证。",
                repairEntry: .xtChooseModel,
                detailLines: details
            )
        }

        let readyHeadline: String
        let readySummary: String
        let readyNextStep: String

        switch (interactivePosture, providerStateCode) {
        case ("local_only", _):
            readyHeadline = "模型路由已就绪（纯本地）"
            readySummary = "XT 当前只看到本地对话模型，这本身不是异常；即使没有云端服务或 API key，也可以继续完成首个任务。"
            readyNextStep = "如果你只需要本地路径，直接继续做桥接 / 工具链验证；只有你要远端 GPT 或云能力时，再去补远端模型。"
        case ("remote_only", "no_ready_provider"):
            readyHeadline = "模型路由已就绪（当前无本地兜底）"
            readySummary = "当前角色分配还能命中远端模型，所以首个任务可以继续；但本地 provider 当前全部未就绪，远端失联时不会有本地兜底。"
            readyNextStep = "如果你只依赖远端链路，先继续桥接 / 工具链验证；如果你也要本地兜底，再去 REL Flow Hub → Models & Paid Access 修复本地 provider。"
        case ("remote_only", "runtime_heartbeat_stale"):
            readyHeadline = "模型路由已就绪，但本地运行时状态已过期"
            readySummary = "当前角色分配还能命中远端模型，所以首个任务可以继续；但本地 runtime/provider 心跳已过期，本地兜底当前不可信。"
            readyNextStep = "先继续桥接 / 工具链验证；如果你需要本地兜底，再到 REL Flow Hub 重启本地运行时并刷新模型列表。"
        case (_, "provider_partial_readiness"):
            readyHeadline = "模型路由已就绪，但本地能力覆盖还不完整"
            readySummary = "当前角色分配能命中可见模型，所以首个任务可以继续；但仍有部分本地 provider 未就绪，模型目录和能力覆盖可能不完整。"
            readyNextStep = "先继续桥接 / 工具链验证；如果你需要更完整的本地能力覆盖，再去 REL Flow Hub → Models & Paid Access 检查未就绪 provider。"
        default:
            readyHeadline = "模型路由已就绪"
            readySummary = "XT 已经能看到可用的 Hub 模型，当前角色分配也都映射到了可见模型 ID。"
            readyNextStep = "不用离开当前页面，直接继续做桥接 / 工具链验证。"
        }

        return VoiceReadinessCheck(
            kind: .modelRouteReadiness,
            state: .ready,
            reasonCode: "model_route_ready",
            headline: readyHeadline,
            summary: readySummary,
            nextStep: readyNextStep,
            repairEntry: .xtChooseModel,
            detailLines: details
        )
    }

    private static func buildBridgeToolCheck(
        localConnected: Bool,
        remoteConnected: Bool,
        hubInteractive: Bool,
        modelRouteReady: Bool,
        bridgeAlive: Bool,
        bridgeEnabled: Bool,
        bridgeLastError: String,
        activeRoute: String
    ) -> VoiceReadinessCheck {
        let remoteToolRoute = remoteConnected && !localConnected
        let toolRouteExecutable = toolRouteExecutable(
            localConnected: localConnected,
            remoteConnected: remoteConnected,
            bridgeAlive: bridgeAlive,
            bridgeEnabled: bridgeEnabled
        )
        let normalizedBridgeLastError = bridgeLastError.trimmingCharacters(in: .whitespacesAndNewlines)
        let details = [
            "bridge_alive=\(bridgeAlive)",
            "bridge_enabled=\(bridgeEnabled)",
            "tool_route_executable=\(toolRouteExecutable)",
            "active_route=\(activeRoute)",
            "remote_tool_route=\(remoteToolRoute)"
        ] + (normalizedBridgeLastError.isEmpty ? [] : ["bridge_last_error=\(normalizedBridgeLastError)"])

        if !hubInteractive {
            return VoiceReadinessCheck(
                kind: .bridgeToolReadiness,
                state: .blockedWaitingUpstream,
                reasonCode: "hub_route_not_interactive",
                headline: "工具链路正在等待 Hub 可达",
                summary: "在 X-Terminal 建立 live Hub 路由之前，桥接和工具执行都无法被验证。",
                nextStep: "先完成 Pair Hub，再重新执行 Verify。",
                repairEntry: .hubDiagnostics,
                detailLines: details
            )
        }

        if remoteToolRoute {
            return VoiceReadinessCheck(
                kind: .bridgeToolReadiness,
                state: .ready,
                reasonCode: "remote_tool_route_ready",
                headline: "远端 Hub 工具主链已就绪",
                summary: "当前主链走远端 gRPC。即使本机 bridge heartbeat 缺失，也不会阻塞远端授权与远端工具调用。",
                nextStep: "继续在当前远端主链上做会话运行时验证。",
                repairEntry: .hubDiagnostics,
                detailLines: details
            )
        }

        if !bridgeAlive {
            return VoiceReadinessCheck(
                kind: .bridgeToolReadiness,
                state: .diagnosticRequired,
                reasonCode: "bridge_heartbeat_missing",
                headline: modelRouteReady ? "模型路由已通，但桥接 / 工具链路不可用" : "桥接 / 工具链路不可用",
                summary: normalizedBridgeLastError.isEmpty
                    ? "Hub 已可达，但 bridge heartbeat 缺失，所以工具调用必须继续保持 fail-closed。"
                    : "Hub 已可达，但 bridge heartbeat 缺失，而且上一次 bridge enable 请求也在链路恢复前失败了，所以工具调用必须继续保持 fail-closed。",
                nextStep: normalizedBridgeLastError.isEmpty
                    ? "打开 Hub Diagnostics & Recovery，必要时重启 bridge，然后重新执行 Verify。"
                    : "打开 Hub Diagnostics & Recovery，先修 bridge 请求链路，必要时重启 bridge，然后重新执行 Verify。",
                repairEntry: .hubDiagnostics,
                detailLines: details
            )
        }

        if !bridgeEnabled {
            return VoiceReadinessCheck(
                kind: .bridgeToolReadiness,
                state: .diagnosticRequired,
                reasonCode: "bridge_execution_window_disabled",
                headline: "Bridge 存活，但工具执行窗口未启用",
                summary: normalizedBridgeLastError.isEmpty
                    ? "Bridge 进程已经存在，但当前执行窗口没有激活，所以工具还不能真正执行。"
                    : "Bridge 进程已经存在，但当前执行窗口没有激活，而且上一次 bridge enable 请求还报告了投递失败。",
                nextStep: normalizedBridgeLastError.isEmpty
                    ? "执行 reconnect smoke，或重新启用 bridge 窗口，然后再验证工具。"
                    : "先修 bridge 命令投递链路，再重新启用 bridge 窗口并重新验证工具。",
                repairEntry: .hubDiagnostics,
                detailLines: details
            )
        }

        return VoiceReadinessCheck(
            kind: .bridgeToolReadiness,
            state: .ready,
            reasonCode: "bridge_tool_route_ready",
            headline: "桥接 / 工具链路已就绪",
            summary: "Bridge heartbeat 正常，执行窗口也已启用，因此工具调用可以通过当前 Hub 链路执行。",
            nextStep: "继续在同一路径上做会话运行时验证。",
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
                headline: "会话运行时正在等待工具链路变为可执行",
                summary: "在 bridge / 工具层准备好之前，运行时验证必须保持阻塞，而不是假装会话已经能自行恢复。",
                nextStep: "先修复桥接 / 工具就绪状态，再回来执行 Verify。",
                repairEntry: .xtDiagnostics,
                detailLines: details
            )
        }

        if runtime.state == .failed_recoverable && !runtime.recoverable {
            return VoiceReadinessCheck(
                kind: .sessionRuntimeReadiness,
                state: .diagnosticRequired,
                reasonCode: "session_runtime_not_recoverable",
                headline: "Bridge 已通，但会话运行时不可恢复",
                summary: "运行时进入了失败状态，但没有有效恢复路径。这个问题必须与 bridge 或模型路由问题分开看待。",
                nextStep: "打开 XT Diagnostics，检查最后一次失败代码，然后先重建或修复受影响会话，再继续。",
                repairEntry: .xtDiagnostics,
                detailLines: details
            )
        }

        if runtime.state == .failed_recoverable {
            return VoiceReadinessCheck(
                kind: .sessionRuntimeReadiness,
                state: .inProgress,
                reasonCode: "session_runtime_recoverable_failure",
                headline: "会话运行时存在可恢复失败路径",
                summary: "当前会话暂停在一个可恢复失败之后。虽然存在恢复路径，但整体验证还没有完成。",
                nextStep: "走恢复路径或重跑被阻塞的请求，然后确认运行时是否回到 idle 或 completed。",
                repairEntry: .xtDiagnostics,
                detailLines: details
            )
        }

        if runtime.pendingToolCallCount > 0 || runtimeBusy(runtime.state) {
            return VoiceReadinessCheck(
                kind: .sessionRuntimeReadiness,
                state: .inProgress,
                reasonCode: "session_runtime_active",
                headline: "会话运行时当前处于活动中",
                summary: "运行时当前正在处理或等待某一步完成。验证应当等它回到稳定状态后再做。",
                nextStep: "等当前会话活动结束，再重新打开 Verify。",
                repairEntry: .xtDiagnostics,
                detailLines: details
            )
        }

        if sessionID == nil {
            return VoiceReadinessCheck(
                kind: .sessionRuntimeReadiness,
                state: .ready,
                reasonCode: "session_runtime_idle_ready",
                headline: "会话运行时基础已就绪",
                summary: "当前还没有主会话，但运行时基础处于 idle，已经可以在第一个任务到来时创建主会话。",
                nextStep: "直接开始第一个任务，在已验证的路由上创建主会话。",
                repairEntry: .homeSupervisor,
                detailLines: details
            )
        }

        return VoiceReadinessCheck(
            kind: .sessionRuntimeReadiness,
            state: .ready,
            reasonCode: "session_runtime_stable",
            headline: "会话运行时已就绪",
            summary: "当前会话处于稳定状态，可以在已验证的路由上恢复正常工作。",
            nextStep: "不用切页，直接继续进入首个任务即可。",
            repairEntry: .homeSupervisor,
            detailLines: details
        )
    }

    private static func buildWakeProfileCheck(
        routeDecision: VoiceRouteDecision,
        authorizationStatus: VoiceTranscriberAuthorizationStatus,
        permissionSnapshot: VoicePermissionSnapshot,
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
            "microphone_authorization=\(permissionSnapshot.microphone.rawValue)",
            "speech_recognition_authorization=\(permissionSnapshot.speechRecognition.rawValue)",
            "window_state=\(conversationSession.windowState.rawValue)",
            activeHealthReasonCode.isEmpty ? "engine_reason=none" : "engine_reason=\(activeHealthReasonCode)",
            wakeProfile.lastRemoteReasonCode?.isEmpty == false
                ? "wake_remote_reason=\(wakeProfile.lastRemoteReasonCode!)"
                : "wake_remote_reason=none"
        ]

        if authorizationStatus == .denied || authorizationStatus == .restricted {
            let guidance = VoicePermissionRepairGuidance.build(
                snapshot: permissionSnapshot,
                fallbackAuthorizationStatus: authorizationStatus
            )
            return VoiceReadinessCheck(
                kind: .wakeProfileReadiness,
                state: .permissionDenied,
                reasonCode: "speech_authorization_denied",
                headline: "唤醒配置被\(guidance.blockedSurfaceLabel)阻塞",
                summary: guidance.wakeSummary,
                nextStep: guidance.nextStep,
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
                    headline: "唤醒配置已在按住说话模式下就绪",
                    summary: "当你不需要后台唤醒时，按住说话仍然是最安全的回退方式。",
                    nextStep: "不用启用后台唤醒，直接手动开始语音采集即可。",
                    repairEntry: .xtDiagnostics,
                    detailLines: details
                )
            case .waitingForPairing:
                return VoiceReadinessCheck(
                    kind: .wakeProfileReadiness,
                    state: .inProgress,
                    reasonCode: wakeProfile.reasonCode,
                    headline: "唤醒配置正在等待配对或同步引导",
                    summary: "唤醒契约还没有真正配进来，所以 XT 会继续保持按住说话，而不是假装后台唤醒已经可用。",
                    nextStep: "先完成 Hub 配对，或者在唤醒配置同步可用前继续使用按住说话。",
                    repairEntry: .xtPairHub,
                    detailLines: details
                )
            case .stale:
                return VoiceReadinessCheck(
                    kind: .wakeProfileReadiness,
                    state: .diagnosticRequired,
                    reasonCode: wakeProfile.reasonCode,
                    headline: "唤醒配置存在，但配对同步已陈旧",
                    summary: "XT 保留了最后一次已知配置用于审计，但在新的同步到来前，后台唤醒会降级回按住说话。",
                    nextStep: "先刷新已配对的唤醒配置，或者切到新的本地覆盖，再重新使用唤醒词模式。",
                    repairEntry: .xtPairHub,
                    detailLines: details
                )
            case .syncUnavailable, .invalid:
                return VoiceReadinessCheck(
                    kind: .wakeProfileReadiness,
                    state: .diagnosticRequired,
                    reasonCode: wakeProfile.reasonCode,
                    headline: "唤醒配置同步不可用，因此运行时继续停在按住说话",
                    summary: "XT 会保留最后一份已知契约供你查看，但如果没有可用的唤醒配置来源，它不会宣称后台唤醒处于激活状态。",
                    nextStep: "修复唤醒配置同步，或者在这台设备上继续保持按住说话。",
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
                headline: "唤醒配置被阻塞，因为当前语音链路处于 fail-closed",
                summary: "只要当前链路处于 fail-closed，XT 就不会假装唤醒功能可用。",
                nextStep: "先修复当前语音链路，或者在实时采集恢复健康前切回按住说话。",
                repairEntry: .xtDiagnostics,
                detailLines: details
            )
        }

        if routeDecision.wakeCapability != "funasr_kws" {
            return VoiceReadinessCheck(
                kind: .wakeProfileReadiness,
                state: .inProgress,
                reasonCode: "wake_phrase_requires_funasr_kws",
                headline: "唤醒配置已存在，但当前链路不提供关键词检测",
                summary: "当前选择的唤醒模式依赖实时关键词检测，但当前链路只支持按住说话这一类采集方式。",
                nextStep: "为唤醒词模式启用健康的 FunASR 链路，或者把唤醒模式切回按住说话。",
                repairEntry: .xtDiagnostics,
                detailLines: details
            )
        }

        if wakeProfile.syncState == .localOverrideActive {
            return VoiceReadinessCheck(
                kind: .wakeProfileReadiness,
                state: .ready,
                reasonCode: wakeProfile.reasonCode,
                headline: "唤醒配置已通过本机覆盖就绪",
                summary: "XT 已经为这台设备拿到一份有效的本地唤醒契约。以后你仍然可以用 pair-synced 词表替换它，而不会削弱当前的 fail-closed 边界。",
                nextStep: "现在就可以在本机使用唤醒；如果你想让其他设备也用同一套契约，再去配 Hub 同步。",
                repairEntry: .xtPairHub,
                detailLines: details
            )
        }

        return VoiceReadinessCheck(
            kind: .wakeProfileReadiness,
            state: .ready,
            reasonCode: wakeProfile.reasonCode == "wake_profile_pair_synced" ? wakeProfile.reasonCode : "wake_phrase_ready",
            headline: wakeProfile.syncState == .pairedSynced
                ? "唤醒配置已就绪，并且已完成配对同步"
                : "唤醒配置已就绪",
            summary: wakeProfile.syncState == .pairedSynced
                ? "当前链路具备关键词检测能力，唤醒契约也已经和配对中的 Hub 配置对齐。"
                : "当前链路具备关键词检测能力，所选唤醒模式可以安全打开 Supervisor 会话。",
            nextStep: "直接使用唤醒词来打开共享的 Supervisor 对话窗口。",
            repairEntry: .homeSupervisor,
            detailLines: details
        )
    }

    private static func buildTalkLoopCheck(
        toolRouteExecutable: Bool,
        routeDecision: VoiceRouteDecision,
        runtimeState: SupervisorVoiceRuntimeState,
        authorizationStatus: VoiceTranscriberAuthorizationStatus,
        permissionSnapshot: VoicePermissionSnapshot,
        conversationSession: SupervisorConversationSessionSnapshot
    ) -> VoiceReadinessCheck {
        let details = [
            "tool_route_executable=\(toolRouteExecutable)",
            "route=\(routeDecision.route.rawValue)",
            "voice_state=\(runtimeState.state.rawValue)",
            "conversation_state=\(conversationSession.windowState.rawValue)",
            "authorization=\(authorizationStatus.rawValue)",
            "microphone_authorization=\(permissionSnapshot.microphone.rawValue)",
            "speech_recognition_authorization=\(permissionSnapshot.speechRecognition.rawValue)",
            runtimeState.reasonCode?.isEmpty == false ? "runtime_reason=\(runtimeState.reasonCode!)" : "runtime_reason=none"
        ]

        if !toolRouteExecutable {
            return VoiceReadinessCheck(
                kind: .talkLoopReadiness,
                state: .blockedWaitingUpstream,
                reasonCode: "tool_route_not_executable",
                headline: "对话链路正在等待工具链路变为可执行",
                summary: "在 bridge / 工具链路准备好之前，运行时验证必须保持阻塞，而不是假装会话已经可以自行恢复。",
                nextStep: "先修 bridge / 工具就绪状态，再回来做语音验证。",
                repairEntry: .hubDiagnostics,
                detailLines: details
            )
        }

        if authorizationStatus == .denied || authorizationStatus == .restricted {
            let guidance = VoicePermissionRepairGuidance.build(
                snapshot: permissionSnapshot,
                fallbackAuthorizationStatus: authorizationStatus
            )
            return VoiceReadinessCheck(
                kind: .talkLoopReadiness,
                state: .permissionDenied,
                reasonCode: "speech_authorization_denied",
                headline: "对话链路被\(guidance.blockedSurfaceLabel)阻塞",
                summary: guidance.talkLoopSummary,
                nextStep: guidance.nextStep,
                repairEntry: .systemPermissions,
                detailLines: details
            )
        }

        if routeDecision.route == .failClosed || runtimeState.state == .failClosed {
            return VoiceReadinessCheck(
                kind: .talkLoopReadiness,
                state: .diagnosticRequired,
                reasonCode: runtimeState.reasonCode ?? routeDecision.reasonCode,
                headline: "当前链路下，对话链路不可用",
                summary: "当前语音链路处于 fail-closed，所以 XT 不会声称短生命周期的持续对话能自行恢复。",
                nextStep: "先修复当前语音链路，或者在实时采集恢复健康前继续停留在手动文本 / 按住说话。",
                repairEntry: .xtDiagnostics,
                detailLines: details
            )
        }

        if !routeDecision.route.supportsLiveCapture {
            return VoiceReadinessCheck(
                kind: .talkLoopReadiness,
                state: .inProgress,
                reasonCode: "manual_text_only",
                headline: "对话链路当前还没有运行在实时采集链路上",
                summary: "当前链路不是实时音频链路，所以 XT 只能靠文本轮次维持会话不断开。",
                nextStep: "如果你想要连续语音对话，请切换到实时语音链路。",
                repairEntry: .xtDiagnostics,
                detailLines: details
            )
        }

        if conversationSession.isConversing || runtimeState.state == .listening || runtimeState.state == .transcribing {
            return VoiceReadinessCheck(
                kind: .talkLoopReadiness,
                state: .inProgress,
                reasonCode: "talk_loop_active",
                headline: "对话链路当前正在运行",
                summary: "语音运行时当前正在共享的 Supervisor 会话里监听或转写。",
                nextStep: "先完成当前轮，或者等会话回到 idle，再修改运行时设置。",
                repairEntry: .homeSupervisor,
                detailLines: details
            )
        }

        return VoiceReadinessCheck(
            kind: .talkLoopReadiness,
            state: .ready,
            reasonCode: "talk_loop_ready",
            headline: "对话链路基础已就绪",
            summary: "当前实时语音链路已经足够健康，后续可以让共享的 Supervisor 会话进入连续对话模式。",
            nextStep: "直接用唤醒词或按住说话，开始新一轮 Supervisor 语音交互。",
            repairEntry: .homeSupervisor,
            detailLines: details
        )
    }

    private static func buildTTSCheck(
        toolRouteExecutable: Bool,
        routeDecision: VoiceRouteDecision,
        preferences: VoiceRuntimePreferences,
        modelsState: ModelStateSnapshot,
        voicePackReadyEvaluator: (@Sendable (String) -> Bool)?
    ) -> VoiceReadinessCheck {
        let availableVoicePacks = HubVoicePackCatalog.eligibleModels(from: modelsState.models)
        let preferredVoicePackID = preferences.preferredHubVoicePackID
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let preferredVoicePack = HubVoicePackCatalog.selectedModel(
            preferredModelID: preferredVoicePackID,
            models: modelsState.models
        )
        let fallbackReadyEvaluator: @Sendable (String) -> Bool = { modelID in
            HubVoicePackCatalog.model(modelID: modelID, models: modelsState.models) != nil
        }
        let playbackResolution = SupervisorSpeechPlaybackRouting.resolve(
            preferences: preferences,
            availableModels: modelsState.models,
            voicePackReadyEvaluator: voicePackReadyEvaluator ?? fallbackReadyEvaluator
        )
        let resolvedVoicePack = HubVoicePackCatalog.model(
            modelID: playbackResolution.resolvedHubVoicePackID,
            models: modelsState.models
        )
        let voicePackState = resolvedVoicePack?.state.rawValue ?? "missing"
        var details = [
            "requested_playback_source=\(preferences.playbackPreference.rawValue)",
            "resolved_playback_source=\(playbackResolution.resolvedSource.rawValue)",
            "preferred_voice_pack_id=\(preferredVoicePackID.isEmpty ? "(none)" : preferredVoicePackID)",
            "resolved_voice_pack_id=\(playbackResolution.resolvedHubVoicePackID.isEmpty ? "(none)" : playbackResolution.resolvedHubVoicePackID)",
            "voice_pack_state=\(voicePackState)",
            "available_voice_pack_count=\(availableVoicePacks.count)",
            "tool_route_executable=\(toolRouteExecutable)",
            "voice_route=\(routeDecision.route.rawValue)"
        ]
        if let fallbackFrom = playbackResolution.fallbackFrom?.rawValue, !fallbackFrom.isEmpty {
            details.append("fallback_from=\(fallbackFrom)")
        }

        switch playbackResolution.resolvedSource {
        case .hubVoicePack:
            return VoiceReadinessCheck(
                kind: .ttsReadiness,
                state: .ready,
                reasonCode: playbackResolution.reasonCode,
                headline: "Hub 语音包播放已就绪",
                summary: "Supervisor 会优先使用所选 Hub 语音包进行播报，同时保留系统语音作为 fail-soft 回退。",
                nextStep: "继续把这个语音包保留在 Hub Library 里，这样播放链路才能和你选定的音色、语言保持一致。",
                repairEntry: .homeSupervisor,
                detailLines: details
            )
        case .systemSpeech:
            if preferences.playbackPreference == .hubVoicePack,
               !preferredVoicePackID.isEmpty,
               preferredVoicePack == nil {
                return VoiceReadinessCheck(
                    kind: .ttsReadiness,
                    state: .inProgress,
                    reasonCode: playbackResolution.reasonCode,
                    headline: "首选 Hub 语音包暂未就绪",
                    summary: "由于所选 Hub 语音包当前不在 Hub Library 中，Supervisor 播报暂时回退到了系统语音。",
                    nextStep: "把所选语音包下载或导入到 Hub，或者把播放来源切回自动 / 系统语音。",
                    repairEntry: .homeSupervisor,
                    detailLines: details
                )
            }

            if preferences.playbackPreference == .automatic,
               !playbackResolution.resolvedHubVoicePackID.isEmpty,
               resolvedVoicePack != nil {
                return VoiceReadinessCheck(
                    kind: .ttsReadiness,
                    state: .inProgress,
                    reasonCode: playbackResolution.reasonCode,
                    headline: "推荐的 Hub 语音包暂未就绪",
                    summary: "虽然 Hub 已经暴露了推荐语音包，但它在本机 TTS 链路上还不能执行，所以 Supervisor 播报暂时回退到了系统语音。",
                    nextStep: "先把这个语音包保留在本地，然后重启或修复本机 Hub TTS 运行时，直到它在本机 Hub IPC 上报告 ready。",
                    repairEntry: .homeSupervisor,
                    detailLines: details
                )
            }

            return VoiceReadinessCheck(
                kind: .ttsReadiness,
                state: .ready,
                reasonCode: playbackResolution.reasonCode,
                headline: "系统语音播放已就绪",
                summary: "Supervisor 语音播报当前解析到系统语音。在你选择并准备好 Hub 语音包前，它会一直作为基线回退路径存在。",
                nextStep: "只有在你需要模型驱动的 Supervisor 声音时，才需要选择 Hub 语音包；否则当前回退路径已经可用。",
                repairEntry: .homeSupervisor,
                detailLines: details
            )
        }
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

    private static func normalizedPairingField(_ value: String?) -> String? {
        let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func toolRouteExecutable(
        localConnected: Bool,
        remoteConnected: Bool,
        bridgeAlive: Bool,
        bridgeEnabled: Bool
    ) -> Bool {
        if localConnected {
            return bridgeAlive && bridgeEnabled
        }
        if remoteConnected {
            return true
        }
        return false
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
