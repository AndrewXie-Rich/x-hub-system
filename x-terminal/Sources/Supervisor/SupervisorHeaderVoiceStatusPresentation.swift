import Foundation

struct SupervisorHeaderVoiceEvidenceItem: Equatable, Identifiable {
    var id: String { title }

    let title: String
    let state: XTUISurfaceState
    let headline: String
    let summary: String
    let detail: String?
}

struct SupervisorHeaderVoiceStatusPresentation: Equatable {
    var iconName: String
    var tone: SupervisorHeaderControlTone
    var chrome: SupervisorHeaderButtonChrome
    var helpText: String
    var summaryText: String
    var call: SupervisorHeaderVoiceCallPresentation
    var items: [SupervisorHeaderVoiceEvidenceItem]

    var hasEvidence: Bool {
        !items.isEmpty
    }

    static func empty(
        call: SupervisorHeaderVoiceCallPresentation = .idle
    ) -> SupervisorHeaderVoiceStatusPresentation {
        SupervisorHeaderVoiceStatusPresentation(
            iconName: iconName(for: call.statusTone),
            tone: call.statusTone,
            chrome: chrome(for: call.statusTone),
            helpText: "语音：\(call.statusText) · \(call.headline)",
            summaryText: "当前还没有语音回放或安全不变量证据。",
            call: call,
            items: []
        )
    }

    private static func iconName(for tone: SupervisorHeaderControlTone) -> String {
        switch tone {
        case .danger:
            return "mic.slash.fill"
        case .neutral:
            return "mic"
        case .accent, .success, .warning:
            return "mic.fill"
        }
    }

    private static func chrome(
        for tone: SupervisorHeaderControlTone
    ) -> SupervisorHeaderButtonChrome {
        switch tone {
        case .danger:
            return SupervisorHeaderButtonChrome(
                tone: .danger,
                fillOpacity: 0.18,
                strokeOpacity: 0.30,
                shadowOpacity: 0.12
            )
        case .warning:
            return SupervisorHeaderButtonChrome(
                tone: .warning,
                fillOpacity: 0.16,
                strokeOpacity: 0.26,
                shadowOpacity: 0.08
            )
        case .accent:
            return SupervisorHeaderButtonChrome(
                tone: .accent,
                fillOpacity: 0.14,
                strokeOpacity: 0.22,
                shadowOpacity: 0.06
            )
        case .success:
            return SupervisorHeaderButtonChrome(
                tone: .success,
                fillOpacity: 0.12,
                strokeOpacity: 0.18,
                shadowOpacity: 0
            )
        case .neutral:
            return .plain
        }
    }
}

struct SupervisorHeaderVoiceCallPresentation: Equatable {
    var buttonIconName: String
    var buttonTitle: String
    var buttonTone: SupervisorHeaderControlTone
    var statusText: String
    var statusTone: SupervisorHeaderControlTone
    var headline: String
    var detail: String
    var actionHelpText: String

    static let idle = SupervisorHeaderVoiceCallPresentation(
        buttonIconName: "phone.fill",
        buttonTitle: "进入通话",
        buttonTone: .neutral,
        statusText: "文本模式",
        statusTone: .neutral,
        headline: "像打电话一样连续说话",
        detail: "当前还没在实时语音链路上，先修复语音就绪状态再进入通话。",
        actionHelpText: "进入连续语音会话"
    )
}

enum SupervisorHeaderVoiceStatusPresentationMapper {
    static func map(
        replaySummary: VoiceReplaySummary,
        safetyReport: VoiceSafetyInvariantReport,
        callModeActive: Bool = false,
        preflight: SupervisorManager.SupervisorVoiceCallEntryPreflight? = nil,
        runtimeState: SupervisorVoiceRuntimeState = .idle,
        routeDecision: VoiceRouteDecision = .unavailable,
        captureSource: VoiceCaptureSource? = nil
    ) -> SupervisorHeaderVoiceStatusPresentation {
        let call = SupervisorHeaderVoiceCallPresentationMapper.map(
            callModeActive: callModeActive,
            preflight: preflight,
            runtimeState: runtimeState,
            routeDecision: routeDecision,
            captureSource: captureSource
        )
        var items: [SupervisorHeaderVoiceEvidenceItem] = []

        if !replaySummary.isEmpty {
            items.append(
                SupervisorHeaderVoiceEvidenceItem(
                    title: "回放核对",
                    state: replaySummary.overallState.surfaceState,
                    headline: replaySummary.headline,
                    summary: replaySummary.summaryLine,
                    detail: replaySummary.compactTimelineText
                )
            )
        }

        if safetyReport.updatedAt > 0 {
            items.append(
                SupervisorHeaderVoiceEvidenceItem(
                    title: "安全约束",
                    state: safetyReport.overallState.surfaceState,
                    headline: safetyReport.headline,
                    summary: safetyReport.summaryLine,
                    detail: nil
                )
            )
        }

        guard !items.isEmpty else { return .empty(call: call) }

        let evidenceTone = strongestTone(for: items)
        let tone = strongerTone(evidenceTone, call.statusTone)
        let headline = items
            .map { "\($0.title)：\($0.headline)" }
            .joined(separator: "；")

        return SupervisorHeaderVoiceStatusPresentation(
            iconName: iconName(for: tone),
            tone: tone,
            chrome: chrome(for: tone),
            helpText: "语音：\(call.statusText) · \(call.headline)；核对：\(headline)",
            summaryText: headline,
            call: call,
            items: items
        )
    }

    private static func iconName(for tone: SupervisorHeaderControlTone) -> String {
        switch tone {
        case .danger:
            return "mic.slash.fill"
        case .neutral:
            return "mic"
        case .accent, .success, .warning:
            return "mic.fill"
        }
    }

    private static func strongestTone(
        for items: [SupervisorHeaderVoiceEvidenceItem]
    ) -> SupervisorHeaderControlTone {
        let states = items.map(\.state)
        if states.contains(where: {
            $0 == .diagnosticRequired || $0 == .permissionDenied || $0 == .blockedWaitingUpstream
        }) {
            return .danger
        }
        if states.contains(.grantRequired) {
            return .warning
        }
        if states.contains(.inProgress) {
            return .accent
        }
        if states.contains(.ready) {
            return .success
        }
        return .neutral
    }

    private static func strongerTone(
        _ lhs: SupervisorHeaderControlTone,
        _ rhs: SupervisorHeaderControlTone
    ) -> SupervisorHeaderControlTone {
        rank(lhs) >= rank(rhs) ? lhs : rhs
    }

    private static func rank(_ tone: SupervisorHeaderControlTone) -> Int {
        switch tone {
        case .danger:
            return 4
        case .warning:
            return 3
        case .accent:
            return 2
        case .success:
            return 1
        case .neutral:
            return 0
        }
    }

    private static func chrome(
        for tone: SupervisorHeaderControlTone
    ) -> SupervisorHeaderButtonChrome {
        switch tone {
        case .danger:
            return SupervisorHeaderButtonChrome(
                tone: .danger,
                fillOpacity: 0.18,
                strokeOpacity: 0.30,
                shadowOpacity: 0.12
            )
        case .warning:
            return SupervisorHeaderButtonChrome(
                tone: .warning,
                fillOpacity: 0.16,
                strokeOpacity: 0.26,
                shadowOpacity: 0.08
            )
        case .accent:
            return SupervisorHeaderButtonChrome(
                tone: .accent,
                fillOpacity: 0.14,
                strokeOpacity: 0.22,
                shadowOpacity: 0.06
            )
        case .success:
            return SupervisorHeaderButtonChrome(
                tone: .success,
                fillOpacity: 0.12,
                strokeOpacity: 0.18,
                shadowOpacity: 0
            )
        case .neutral:
            return .plain
        }
    }
}

enum SupervisorHeaderVoiceCallPresentationMapper {
    static func map(
        callModeActive: Bool,
        preflight: SupervisorManager.SupervisorVoiceCallEntryPreflight?,
        runtimeState: SupervisorVoiceRuntimeState,
        routeDecision: VoiceRouteDecision,
        captureSource: VoiceCaptureSource?
    ) -> SupervisorHeaderVoiceCallPresentation {
        let activePreflight = callModeActive ? nil : preflight
        let buttonIconName = buttonIconName(
            callModeActive: callModeActive,
            preflight: activePreflight
        )
        let buttonTitle = buttonTitle(
            callModeActive: callModeActive,
            preflight: activePreflight
        )
        let headline = headline(
            callModeActive: callModeActive,
            preflight: activePreflight,
            runtimeState: runtimeState,
            captureSource: captureSource
        )
        let detail = detail(
            callModeActive: callModeActive,
            preflight: activePreflight,
            runtimeState: runtimeState,
            routeDecision: routeDecision,
            captureSource: captureSource
        )

        return SupervisorHeaderVoiceCallPresentation(
            buttonIconName: buttonIconName,
            buttonTitle: buttonTitle,
            buttonTone: buttonTone(
                callModeActive: callModeActive,
                preflight: activePreflight,
                routeDecision: routeDecision
            ),
            statusText: statusText(
                callModeActive: callModeActive,
                preflight: activePreflight,
                runtimeState: runtimeState,
                captureSource: captureSource
            ),
            statusTone: statusTone(
                callModeActive: callModeActive,
                preflight: activePreflight,
                runtimeState: runtimeState,
                captureSource: captureSource
            ),
            headline: headline,
            detail: detail,
            actionHelpText: "\(buttonTitle)：\(headline)"
        )
    }

    private static func buttonTone(
        callModeActive: Bool,
        preflight: SupervisorManager.SupervisorVoiceCallEntryPreflight?,
        routeDecision: VoiceRouteDecision
    ) -> SupervisorHeaderControlTone {
        if callModeActive {
            return .danger
        }
        if let preflight {
            switch preflight.disposition {
            case .block:
                return .danger
            case .advisory:
                return .warning
            }
        }
        if routeDecision.route.supportsLiveCapture {
            return .success
        }
        return .neutral
    }

    private static func buttonIconName(
        callModeActive: Bool,
        preflight: SupervisorManager.SupervisorVoiceCallEntryPreflight?
    ) -> String {
        if callModeActive {
            return "phone.down.fill"
        }
        if preflight?.blocksStart == true {
            return "exclamationmark.triangle.fill"
        }
        return "phone.fill"
    }

    private static func buttonTitle(
        callModeActive: Bool,
        preflight: SupervisorManager.SupervisorVoiceCallEntryPreflight?
    ) -> String {
        if callModeActive {
            return "结束通话"
        }
        if preflight?.blocksStart == true {
            return "先修复语音"
        }
        return "进入通话"
    }

    private static func headline(
        callModeActive: Bool,
        preflight: SupervisorManager.SupervisorVoiceCallEntryPreflight?,
        runtimeState: SupervisorVoiceRuntimeState,
        captureSource: VoiceCaptureSource?
    ) -> String {
        if callModeActive {
            switch runtimeState.state {
            case .listening:
                return "已接通，直接开口"
            case .transcribing:
                return "正在听你说话"
            case .completed:
                return "这一句已送进 Supervisor"
            case .failClosed:
                return "通话链路当前不可用"
            case .idle:
                return "通话已接通"
            }
        }
        if let preflight {
            return preflight.headline
        }
        switch captureSource {
        case .wakeArmed:
            return "待命中，叫一声就行"
        case .wakeFollowup:
            return "已唤醒，继续说"
        case .talkLoop:
            return "我在继续听"
        case .continuousConversation:
            return "通话已接通"
        case .manualComposer, .none:
            break
        }
        return "像打电话一样连续说话"
    }

    private static func detail(
        callModeActive: Bool,
        preflight: SupervisorManager.SupervisorVoiceCallEntryPreflight?,
        runtimeState: SupervisorVoiceRuntimeState,
        routeDecision: VoiceRouteDecision,
        captureSource: VoiceCaptureSource?
    ) -> String {
        if callModeActive {
            if runtimeState.state == .failClosed {
                return SupervisorVoiceReasonPresentation.displayTextOrRaw(
                    runtimeState.reasonCode
                ) ?? "请先修复当前语音链路。"
            }
            return "你说完一轮后会自动送进 Supervisor，并在回复后继续监听。"
        }
        if let preflight {
            let detail = preflight.detail.trimmingCharacters(in: .whitespacesAndNewlines)
            if !detail.isEmpty {
                return detail
            }
            return preflight.nextStep
        }

        switch captureSource {
        case .wakeArmed:
            return "当前在后台待命；命中唤醒词后，我会先接通，再继续听你下一句。"
        case .wakeFollowup:
            return "我已经听到唤醒词，现在直接说你的问题或指令。"
        case .talkLoop:
            return "上一轮刚结束；你可以继续接着说，不用重新点麦克风。"
        case .continuousConversation:
            return "当前已经在连续通话模式。"
        case .manualComposer, .none:
            break
        }

        if routeDecision.route.supportsLiveCapture {
            return "这会直接启动连续语音会话，不需要每轮都手动点麦克风。"
        }
        return "当前还没在实时语音链路上，先修复语音就绪状态再进入通话。"
    }

    private static func statusText(
        callModeActive: Bool,
        preflight: SupervisorManager.SupervisorVoiceCallEntryPreflight?,
        runtimeState: SupervisorVoiceRuntimeState,
        captureSource: VoiceCaptureSource?
    ) -> String {
        if callModeActive {
            return "通话中"
        }
        if let preflight {
            switch preflight.disposition {
            case .block:
                return "先修复"
            case .advisory:
                return "建议复检"
            }
        }
        switch captureSource {
        case .wakeArmed:
            return "待命中"
        case .wakeFollowup:
            return "已唤醒"
        case .talkLoop:
            return "跟进监听"
        case .continuousConversation:
            return "通话中"
        case .manualComposer:
            return "手动录音"
        case .none:
            if runtimeState.state == .failClosed {
                return "需修复"
            }
            return "文本模式"
        }
    }

    private static func statusTone(
        callModeActive: Bool,
        preflight: SupervisorManager.SupervisorVoiceCallEntryPreflight?,
        runtimeState: SupervisorVoiceRuntimeState,
        captureSource: VoiceCaptureSource?
    ) -> SupervisorHeaderControlTone {
        if runtimeState.state == .failClosed {
            return .danger
        }
        if callModeActive {
            return .success
        }
        if let preflight {
            switch preflight.disposition {
            case .block:
                return .danger
            case .advisory:
                return .warning
            }
        }
        switch captureSource {
        case .wakeArmed:
            return .accent
        case .wakeFollowup:
            return .warning
        case .talkLoop, .continuousConversation:
            return .success
        case .manualComposer:
            return .danger
        case .none:
            return .neutral
        }
    }
}
