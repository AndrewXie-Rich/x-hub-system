import Foundation

struct SupervisorConversationVoiceRailChip: Equatable, Identifiable {
    var id: String
    var text: String
    var state: XTUISurfaceState
    var prefersMonospacedText: Bool = false
    var helpText: String? = nil
}

struct SupervisorConversationVoiceRailNotice: Equatable {
    var state: XTUISurfaceState
    var title: String
    var summary: String
    var nextStep: String?
    var repairEntry: UITroubleshootDestination?

    var iconName: String {
        state.iconName
    }
}

struct SupervisorConversationVoiceRailPresentation: Equatable {
    var phaseLabel: String
    var phaseIconName: String
    var phaseState: XTUISurfaceState
    var chips: [SupervisorConversationVoiceRailChip]
    var notice: SupervisorConversationVoiceRailNotice?
    var canEndSession: Bool
}

enum SupervisorConversationVoiceRailPresentationBuilder {
    static func build(
        routeDecision: VoiceRouteDecision,
        readinessSnapshot: VoiceReadinessSnapshot,
        authorizationStatus: VoiceTranscriberAuthorizationStatus,
        permissionSnapshot: VoicePermissionSnapshot = .unknown,
        runtimeState: SupervisorVoiceRuntimeState,
        conversationSession: SupervisorConversationSessionSnapshot,
        playbackActivity: VoicePlaybackActivity,
        activeHealthReasonCode: String,
        latestRuntimeActivityText: String? = nil,
        recentVoiceDispatchAuditEntries: [SupervisorVoiceDispatchAuditEntry] = []
    ) -> SupervisorConversationVoiceRailPresentation {
        let phase = phasePresentation(
            readinessSnapshot: readinessSnapshot,
            runtimeState: runtimeState,
            conversationSession: conversationSession
        )
        let notice = noticePresentation(
            readinessSnapshot: readinessSnapshot,
            playbackActivity: playbackActivity
        )
        let talkLoopState = readinessSnapshot.check(.talkLoopReadiness)?.state
            ?? readinessSnapshot.overallState
        let wakeState = readinessSnapshot.check(.wakeProfileReadiness)?.state
            ?? readinessSnapshot.overallState
        let authorizationChip = authorizationChipPresentation(
            route: routeDecision.route,
            authorizationStatus: authorizationStatus,
            permissionSnapshot: permissionSnapshot
        )
        var chips: [SupervisorConversationVoiceRailChip] = [
            SupervisorConversationVoiceRailChip(
                id: "route",
                text: "链路：\(routeDecision.route.displayName)",
                state: talkLoopState
            ),
            SupervisorConversationVoiceRailChip(
                id: "wake_mode",
                text: "唤醒：\(conversationSession.wakeMode.displayName)",
                state: wakeState,
                prefersMonospacedText: false
            ),
            SupervisorConversationVoiceRailChip(
                id: "wake_capability",
                text: "唤醒能力：\(wakeCapabilityText(routeDecision.wakeCapability))",
                state: wakeState,
                prefersMonospacedText: false
            ),
            SupervisorConversationVoiceRailChip(
                id: "auth",
                text: authorizationChip.text,
                state: authorizationChip.state,
                prefersMonospacedText: false,
                helpText: authorizationChip.helpText
            ),
            SupervisorConversationVoiceRailChip(
                id: "session",
                text: "会话：\(sessionWindowStateText(conversationSession.windowState))",
                state: sessionState(conversationSession),
                prefersMonospacedText: false
            )
        ]

        if conversationSession.remainingTTLSeconds > 0 {
            chips.append(
                SupervisorConversationVoiceRailChip(
                    id: "ttl",
                    text: "剩余：\(conversationSession.remainingTTLSeconds) 秒",
                    state: conversationSession.isConversing ? .inProgress : .ready,
                    prefersMonospacedText: false
                )
            )
        }

        if let reasonCode = normalizedReasonCode(
            runtimeReasonCode: runtimeState.reasonCode,
            activeHealthReasonCode: activeHealthReasonCode,
            readinessReasonCode: readinessSnapshot.primaryReasonCode
        ) {
            let reasonDisplay = reasonChipPresentation(reasonCode)
            chips.append(
                SupervisorConversationVoiceRailChip(
                    id: "reason",
                    text: "原因：\(reasonDisplay.text)",
                    state: notice?.state ?? phase.state,
                    prefersMonospacedText: reasonDisplay.prefersMonospacedText
                )
            )
        }

        if let playbackSummary = playbackActivity.compactRailSummaryLine {
            chips.append(
                SupervisorConversationVoiceRailChip(
                    id: "playback",
                    text: playbackSummary,
                    state: playbackState(playbackActivity.state),
                    prefersMonospacedText: true
                )
            )
        }

        if let voiceDispatch = SupervisorVoiceDispatchPresentationResolver.map(
            latestRuntimeActivityText: latestRuntimeActivityText
        ) {
            chips.append(
                SupervisorConversationVoiceRailChip(
                    id: "voice_dispatch",
                    text: "语音：\(voiceDispatch.text)",
                    state: voiceDispatch.surfaceState,
                    prefersMonospacedText: false,
                    helpText: voiceDispatch.helpText
                )
            )
        }

        if let auditChip = SupervisorVoiceDispatchPresentationResolver.auditChip(
            entries: recentVoiceDispatchAuditEntries
        ) {
            chips.append(auditChip)
        }

        return SupervisorConversationVoiceRailPresentation(
            phaseLabel: phase.label,
            phaseIconName: phase.iconName,
            phaseState: phase.state,
            chips: chips,
            notice: notice,
            canEndSession: conversationSession.isConversing
        )
    }

    private static func phasePresentation(
        readinessSnapshot: VoiceReadinessSnapshot,
        runtimeState: SupervisorVoiceRuntimeState,
        conversationSession: SupervisorConversationSessionSnapshot
    ) -> (label: String, iconName: String, state: XTUISurfaceState) {
        switch runtimeState.state {
        case .listening:
            return ("监听中", "mic.circle.fill", .inProgress)
        case .transcribing:
            return ("识别中", "waveform.badge.mic", .inProgress)
        case .completed:
            return ("已完成", "checkmark.circle.fill", .ready)
        case .failClosed:
            let state: XTUISurfaceState = readinessSnapshot.overallState == .permissionDenied
                ? .permissionDenied
                : .diagnosticRequired
            return ("安全关闭", "exclamationmark.triangle.fill", state)
        case .idle:
            switch conversationSession.windowState {
            case .armed:
                return ("待唤醒", "bolt.circle.fill", .ready)
            case .conversing:
                return ("对话中", "bubble.left.and.waveform.right.fill", .inProgress)
            case .hidden:
                let state = readinessSnapshot.overallState == .ready
                    ? .ready
                    : readinessSnapshot.overallState
                return ("空闲", "waveform.circle", state)
            }
        }
    }

    private static func noticePresentation(
        readinessSnapshot: VoiceReadinessSnapshot,
        playbackActivity: VoicePlaybackActivity
    ) -> SupervisorConversationVoiceRailNotice? {
        if let check = preferredReadinessCheck(in: readinessSnapshot) {
            let localizedCopy = localizedNoticeCopy(for: check)
            let summary = readinessSnapshot.readyForFirstTask
                && !check.kind.contributesToFirstTaskReadiness
                ? readinessSnapshot.overallSummary
                : (localizedCopy?.summary ?? check.summary)
            return SupervisorConversationVoiceRailNotice(
                state: check.state,
                title: localizedCopy?.title ?? check.headline,
                summary: summary,
                nextStep: localizedCopy?.nextStep ?? check.nextStep,
                repairEntry: check.repairEntry
            )
        }

        guard playbackActivity.state == .failed || playbackActivity.state == .fallbackPlayed else { return nil }
        let nextStep: String
        let repairEntry: UITroubleshootDestination
        if playbackActivity.state == .fallbackPlayed {
            nextStep = playbackActivity.recommendedNextStep
                ?? fallbackPlaybackNextStep(playbackActivity)
            repairEntry = .homeSupervisor
        } else {
            nextStep = playbackActivity.recommendedNextStep
                ?? "打开 Supervisor 设置，确认当前播放输出链路。"
            repairEntry = .xtDiagnostics
        }
        return SupervisorConversationVoiceRailNotice(
            state: playbackState(playbackActivity.state),
            title: playbackActivity.headline,
            summary: playbackActivity.summaryLine,
            nextStep: nextStep,
            repairEntry: repairEntry
        )
    }

    private static func fallbackPlaybackNextStep(
        _ playbackActivity: VoicePlaybackActivity
    ) -> String {
        playbackActivity.recommendedNextStep
            ?? "当前已经安全回退到系统语音；如果你想恢复原始播放链路，请打开 Supervisor 设置检查当前输出配置。"
    }

    private static func preferredReadinessCheck(
        in snapshot: VoiceReadinessSnapshot
    ) -> VoiceReadinessCheck? {
        guard snapshot.overallState != .ready else { return nil }

        let priority: [VoiceReadinessCheckKind] = [
            .talkLoopReadiness,
            .wakeProfileReadiness,
            .bridgeToolReadiness,
            .sessionRuntimeReadiness,
            .modelRouteReadiness,
            .pairingValidity,
            .ttsReadiness
        ]

        for kind in priority {
            if let check = snapshot.check(kind), check.state != .ready {
                return check
            }
        }

        return snapshot.checks.first { $0.state != .ready }
    }

    private static func localizedNoticeCopy(
        for check: VoiceReadinessCheck
    ) -> (title: String, summary: String?, nextStep: String?)? {
        switch (check.kind, check.reasonCode) {
        case (.talkLoopReadiness, "voice_route_fail_closed"):
            return (
                title: "当前链路下，对话链路不可用",
                summary: "当前语音链路已进入安全关闭状态，连续语音对话暂时不可用。",
                nextStep: "先修复当前语音链路，或者在实时采集恢复健康前继续停留在手动文本 / 按住说话。"
            )
        case (.wakeProfileReadiness, "wake_phrase_requires_funasr_kws"):
            return (
                title: "唤醒能力暂不可用",
                summary: "当前链路还不支持唤醒词，只能继续使用按住说话或手动输入。",
                nextStep: "如果要恢复唤醒词，请切回支持 FunASR 唤醒的链路，或先用按住说话继续。"
            )
        default:
            return nil
        }
    }

    private static func authorizationChipPresentation(
        route: VoiceRouteMode,
        authorizationStatus: VoiceTranscriberAuthorizationStatus,
        permissionSnapshot: VoicePermissionSnapshot
    ) -> (text: String, state: XTUISurfaceState, helpText: String?) {
        if !route.supportsLiveCapture {
            let helpText: String
            if permissionSnapshot.requiresSettingsRepair {
                let guidance = VoicePermissionRepairGuidance.build(
                    snapshot: permissionSnapshot,
                    fallbackAuthorizationStatus: dominantPermissionStatus(
                        in: permissionSnapshot,
                        fallback: authorizationStatus
                    )
                )
                helpText = "当前链路不走实时采集，所以不会被语音权限卡住；如果后面要切回实时语音，仍需先修复。\(guidance.settingsGuidance)"
            } else {
                helpText = "当前链路不走实时采集，所以不会使用麦克风或语音识别权限。"
            }
            return ("权限：当前链路不需要", .ready, helpText)
        }

        let dominantStatus = dominantPermissionStatus(
            in: permissionSnapshot,
            fallback: authorizationStatus
        )
        return (
            "权限：\(authorizationStatusText(dominantStatus))",
            authorizationState(dominantStatus),
            nil
        )
    }

    private static func authorizationState(
        _ authorizationStatus: VoiceTranscriberAuthorizationStatus
    ) -> XTUISurfaceState {
        switch authorizationStatus {
        case .authorized:
            return .ready
        case .undetermined:
            return .inProgress
        case .denied, .restricted:
            return .permissionDenied
        case .unavailable:
            return .diagnosticRequired
        }
    }

    private static func dominantPermissionStatus(
        in permissionSnapshot: VoicePermissionSnapshot,
        fallback: VoiceTranscriberAuthorizationStatus
    ) -> VoiceTranscriberAuthorizationStatus {
        let statuses = [permissionSnapshot.microphone, permissionSnapshot.speechRecognition]
        if statuses.allSatisfy({ $0 == .undetermined }) {
            return fallback
        }
        if statuses.contains(.denied) {
            return .denied
        }
        if statuses.contains(.restricted) {
            return .restricted
        }
        if statuses.contains(.undetermined) {
            return .undetermined
        }
        if statuses.allSatisfy({ $0 == .authorized }) {
            return .authorized
        }
        if statuses.contains(.unavailable) {
            return .unavailable
        }
        return fallback
    }

    private static func authorizationStatusText(
        _ authorizationStatus: VoiceTranscriberAuthorizationStatus
    ) -> String {
        switch authorizationStatus {
        case .authorized:
            return "已授权"
        case .undetermined:
            return "待确认"
        case .denied:
            return "已拒绝"
        case .restricted:
            return "受限"
        case .unavailable:
            return "不可用"
        }
    }

    private static func wakeCapabilityText(_ rawValue: String) -> String {
        switch normalized(rawValue) ?? rawValue {
        case "funasr_kws":
            return "FunASR 唤醒词"
        case "push_to_talk_only":
            return "仅按住说话"
        case "prompt_phrase_only":
            return "仅提示词"
        case "none":
            return "无"
        default:
            return rawValue
        }
    }

    private static func sessionWindowStateText(
        _ state: SupervisorConversationWindowState
    ) -> String {
        switch state {
        case .hidden:
            return "空闲"
        case .armed:
            return "待唤醒"
        case .conversing:
            return "对话中"
        }
    }

    private static func sessionState(
        _ conversationSession: SupervisorConversationSessionSnapshot
    ) -> XTUISurfaceState {
        switch conversationSession.windowState {
        case .hidden:
            return .ready
        case .armed:
            return .ready
        case .conversing:
            return .inProgress
        }
    }

    private static func playbackState(
        _ playbackState: VoicePlaybackActivityState
    ) -> XTUISurfaceState {
        switch playbackState {
        case .idle, .played:
            return .ready
        case .fallbackPlayed:
            return .inProgress
        case .suppressed:
            return .blockedWaitingUpstream
        case .failed:
            return .diagnosticRequired
        }
    }

    private static func normalizedReasonCode(
        runtimeReasonCode: String?,
        activeHealthReasonCode: String,
        readinessReasonCode: String
    ) -> String? {
        if let runtimeReasonCode = normalized(runtimeReasonCode),
           runtimeReasonCode != "none" {
            return runtimeReasonCode
        }
        if let activeHealthReasonCode = normalized(activeHealthReasonCode),
           activeHealthReasonCode != "none" {
            return activeHealthReasonCode
        }
        guard let readinessReasonCode = normalized(readinessReasonCode),
              readinessReasonCode != "voice_readiness_ready",
              readinessReasonCode != "none" else {
            return nil
        }
        return readinessReasonCode
    }

    private static func reasonChipPresentation(
        _ raw: String
    ) -> (text: String, prefersMonospacedText: Bool) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return (raw, true) }
        if let humanized = XTRouteTruthPresentation.userVisibleReasonText(trimmed) {
            return (humanized, false)
        }
        return (trimmed, true)
    }

    private static func normalized(_ value: String?) -> String? {
        let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension VoicePermissionSnapshot {
    var requiresSettingsRepair: Bool {
        microphone == .denied
            || microphone == .restricted
            || speechRecognition == .denied
            || speechRecognition == .restricted
    }
}
