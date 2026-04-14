import Foundation

enum VoiceSafetyInvariantStatus: String, Codable, Equatable, Sendable {
    case pass
    case observing
    case fail

    var localizedLabel: String {
        switch self {
        case .pass:
            return "已满足"
        case .observing:
            return "观察中"
        case .fail:
            return "异常"
        }
    }

    var surfaceState: XTUISurfaceState {
        switch self {
        case .pass:
            return .ready
        case .observing:
            return .inProgress
        case .fail:
            return .diagnosticRequired
        }
    }
}

enum VoiceSafetyInvariantKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case wakeDoesNotImplyAuthorization = "wake_does_not_imply_authorization"
    case talkLoopDoesNotBypassToolGates = "talk_loop_does_not_bypass_tool_gates"
    case providerFallbackDoesNotDropAudit = "provider_fallback_does_not_drop_audit"
    case interruptDoesNotCorruptPendingAuthorizationChallenge = "interrupt_does_not_corrupt_pending_authorization_challenge"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .wakeDoesNotImplyAuthorization:
            return "wake 不等于授权通过"
        case .talkLoopDoesNotBypassToolGates:
            return "talk loop 不绕过工具门禁"
        case .providerFallbackDoesNotDropAudit:
            return "provider fallback 不丢审计"
        case .interruptDoesNotCorruptPendingAuthorizationChallenge:
            return "interrupt 不破坏待决挑战"
        }
    }
}

struct VoiceSafetyInvariantCheck: Codable, Equatable, Identifiable, Sendable {
    var kind: VoiceSafetyInvariantKind
    var status: VoiceSafetyInvariantStatus
    var summary: String
    var detail: String
    var evidence: [String]

    var id: String { kind.id }
}

struct VoiceSafetyInvariantReport: Codable, Equatable, Sendable {
    var overallState: VoiceEvidenceState
    var headline: String
    var summaryLine: String
    var checks: [VoiceSafetyInvariantCheck]
    var updatedAt: TimeInterval

    static let empty = VoiceSafetyInvariantReport(
        overallState: .idle,
        headline: "等待语音安全证据",
        summaryLine: "当前还没有足够的语音回放事件来检查不变量。",
        checks: VoiceSafetyInvariantKind.allCases.map {
            VoiceSafetyInvariantCheck(
                kind: $0,
                status: .observing,
                summary: "等待事件",
                detail: "还没有看到可用于校验这一条不变量的语音事件。",
                evidence: []
            )
        },
        updatedAt: 0
    )
}

struct VoiceSafetyInvariantContext: Equatable {
    var replayEvents: [VoiceReplayEvent]
    var dispatchAuditEntries: [SupervisorVoiceDispatchAuditEntry]
    var playbackActivity: VoicePlaybackActivity
    var authorizationResolution: SupervisorVoiceAuthorizationResolution?
    var activeChallenge: HubIPCClient.VoiceGrantChallengeSnapshot?

    init(
        replayEvents: [VoiceReplayEvent] = [],
        dispatchAuditEntries: [SupervisorVoiceDispatchAuditEntry] = [],
        playbackActivity: VoicePlaybackActivity = .empty,
        authorizationResolution: SupervisorVoiceAuthorizationResolution? = nil,
        activeChallenge: HubIPCClient.VoiceGrantChallengeSnapshot? = nil
    ) {
        self.replayEvents = replayEvents
        self.dispatchAuditEntries = dispatchAuditEntries
        self.playbackActivity = playbackActivity
        self.authorizationResolution = authorizationResolution
        self.activeChallenge = activeChallenge
    }
}

enum VoiceSafetyInvariantChecker {
    static func evaluate(
        _ context: VoiceSafetyInvariantContext
    ) -> VoiceSafetyInvariantReport {
        let orderedReplayEvents = context.replayEvents.sorted { lhs, rhs in
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt < rhs.createdAt
            }
            return lhs.id < rhs.id
        }

        let checks = [
            wakeDoesNotImplyAuthorization(events: orderedReplayEvents, context: context),
            talkLoopDoesNotBypassToolGates(events: orderedReplayEvents),
            providerFallbackDoesNotDropAudit(events: orderedReplayEvents, context: context),
            interruptDoesNotCorruptPendingAuthorizationChallenge(events: orderedReplayEvents, context: context),
        ]

        let updatedAt = max(
            orderedReplayEvents.last?.createdAt ?? 0,
            context.playbackActivity.updatedAt
        )
        let failCount = checks.filter { $0.status == .fail }.count
        let observingCount = checks.filter { $0.status == .observing }.count
        let hasEvidence = !orderedReplayEvents.isEmpty
            || !context.dispatchAuditEntries.isEmpty
            || context.playbackActivity.state != .idle
            || context.authorizationResolution != nil
            || context.activeChallenge != nil

        let overallState: VoiceEvidenceState
        let headline: String
        let summaryLine: String

        if failCount > 0 {
            overallState = .failed
            headline = "发现 \(failCount) 条语音安全不变量异常"
            summaryLine = "请先修复 fail-closed 或审计缺口，再继续推进语音主演示链。"
        } else if !hasEvidence {
            overallState = .idle
            headline = "等待语音安全证据"
            summaryLine = "当前还没有足够的语音回放事件来检查不变量。"
        } else if observingCount > 0 {
            overallState = .ready
            headline = "语音安全不变量保持成立，继续累积证据"
            summaryLine = "\(checks.count - observingCount)/\(checks.count) 条已拿到直接证据，\(observingCount) 条仍在观察。"
        } else {
            overallState = .ready
            headline = "4 条语音安全不变量均已满足"
            summaryLine = "wake、talk loop、fallback audit、interrupt challenge 都有直接证据支撑。"
        }

        return VoiceSafetyInvariantReport(
            overallState: overallState,
            headline: headline,
            summaryLine: summaryLine,
            checks: checks,
            updatedAt: updatedAt
        )
    }

    private static func wakeDoesNotImplyAuthorization(
        events: [VoiceReplayEvent],
        context: VoiceSafetyInvariantContext
    ) -> VoiceSafetyInvariantCheck {
        let wakeEvents = events.filter { $0.category == .wake && $0.state == .hit }
        let verifiedEvents = events.filter {
            $0.category == .authorization && $0.state == .verified
        }
        let activeState = context.authorizationResolution?.state

        guard !wakeEvents.isEmpty || !verifiedEvents.isEmpty || activeState != nil else {
            return VoiceSafetyInvariantCheck(
                kind: .wakeDoesNotImplyAuthorization,
                status: .observing,
                summary: "等待唤醒与授权事件",
                detail: "还没有看到 wake hit 或授权结果，暂时只能保持观察。",
                evidence: []
            )
        }

        if let verified = verifiedEvents.last {
            let verifiedChallengeID = challengeID(for: verified)
            let requestID = verified.metadata["request_id"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let challengeEvidence = events.contains { event in
                guard event.category == .authorization else { return false }
                guard event.createdAt <= verified.createdAt else { return false }
                guard event.state == .pending || event.state == .escalated else { return false }
                if matchesChallenge(event: event, challengeID: verifiedChallengeID) {
                    return true
                }
                let candidateRequestID = event.metadata["request_id"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return !requestID.isEmpty && candidateRequestID == requestID
            }

            if challengeEvidence {
                return VoiceSafetyInvariantCheck(
                    kind: .wakeDoesNotImplyAuthorization,
                    status: .pass,
                    summary: "授权通过前看到了挑战门禁",
                    detail: "最近一次授权通过之前，系统先记录了 pending / escalated challenge，没有因为 wake hit 直接放行。",
                    evidence: compactEvidenceLines(for: [verifiedEvents.last].compactMap { $0 })
                )
            }

            return VoiceSafetyInvariantCheck(
                kind: .wakeDoesNotImplyAuthorization,
                status: .fail,
                summary: "看到授权通过，但缺少挑战前置证据",
                detail: "这意味着高风险链路可能绕过了显式 challenge，必须先修复。",
                evidence: compactEvidenceLines(for: [verified])
            )
        }

        if activeState == .pending || activeState == .escalatedToMobile || context.activeChallenge != nil {
            return VoiceSafetyInvariantCheck(
                kind: .wakeDoesNotImplyAuthorization,
                status: .pass,
                summary: "wake hit 后仍停留在挑战门前",
                detail: "当前仍然要求挑战或移动端确认，wake 本身没有带来自动放行。",
                evidence: compactEvidenceLines(for: wakeEvents.suffix(1))
            )
        }

        return VoiceSafetyInvariantCheck(
            kind: .wakeDoesNotImplyAuthorization,
            status: .pass,
            summary: "wake hit 没有触发自动授权",
            detail: "已看到唤醒命中，但还没有任何直接授权通过事件。",
            evidence: compactEvidenceLines(for: wakeEvents.suffix(2))
        )
    }

    private static func talkLoopDoesNotBypassToolGates(
        events: [VoiceReplayEvent]
    ) -> VoiceSafetyInvariantCheck {
        let routed = events.filter { event in
            guard event.category == .utterance, event.state == .forwarded else { return false }
            let source = event.metadata["capture_source"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return source == VoiceCaptureSource.talkLoop.rawValue
                || source == VoiceCaptureSource.continuousConversation.rawValue
        }

        guard !routed.isEmpty else {
            return VoiceSafetyInvariantCheck(
                kind: .talkLoopDoesNotBypassToolGates,
                status: .observing,
                summary: "等待 talk loop 真实转发证据",
                detail: "当前还没有看到 talk loop / continuous conversation 进入 Supervisor 主链的事件。",
                evidence: []
            )
        }

        let bypassEvents = routed.filter {
            let path = $0.metadata["path"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return path != "send_message"
        }
        if !bypassEvents.isEmpty {
            return VoiceSafetyInvariantCheck(
                kind: .talkLoopDoesNotBypassToolGates,
                status: .fail,
                summary: "发现 talk loop 事件没有走 sendMessage 主门禁",
                detail: "talk loop 的语音输入必须先进入 Supervisor 主链，再由既有工具审批与路由继续处理。",
                evidence: compactEvidenceLines(for: bypassEvents)
            )
        }

        return VoiceSafetyInvariantCheck(
            kind: .talkLoopDoesNotBypassToolGates,
            status: .pass,
            summary: "talk loop 仍通过 Supervisor 主门禁",
            detail: "最近的 talk loop / continuous conversation 都带有 path=send_message 证据，没有出现绕过工具门禁的旁路。",
            evidence: compactEvidenceLines(for: routed.suffix(3))
        )
    }

    private static func providerFallbackDoesNotDropAudit(
        events: [VoiceReplayEvent],
        context: VoiceSafetyInvariantContext
    ) -> VoiceSafetyInvariantCheck {
        let fallbackEvents = events.filter {
            $0.category == .playback && $0.state == .fallback
        }
        let playbackState = context.playbackActivity.state

        guard playbackState == .fallbackPlayed || !fallbackEvents.isEmpty else {
            return VoiceSafetyInvariantCheck(
                kind: .providerFallbackDoesNotDropAudit,
                status: .observing,
                summary: "当前还没有触发 provider fallback",
                detail: "这一条不变量只会在真实 fallback 发生后给出直接证据。",
                evidence: []
            )
        }

        let hasReplayEvidence = !fallbackEvents.isEmpty
        let hasAuditEvidence =
            !context.playbackActivity.auditLine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !context.dispatchAuditEntries.isEmpty
            || events.contains { $0.category == .dispatch }

        if hasReplayEvidence && hasAuditEvidence {
            return VoiceSafetyInvariantCheck(
                kind: .providerFallbackDoesNotDropAudit,
                status: .pass,
                summary: "fallback 发生后仍保留了审计摘要",
                detail: "回放摘要和派发审计至少保留了一条，因此 fallback 没有把审计链条打断。",
                evidence: compactEvidenceLines(for: fallbackEvents.suffix(2))
            )
        }

        var missing: [String] = []
        if !hasReplayEvidence {
            missing.append("replay_summary")
        }
        if !hasAuditEvidence {
            missing.append("dispatch_audit")
        }
        return VoiceSafetyInvariantCheck(
            kind: .providerFallbackDoesNotDropAudit,
            status: .fail,
            summary: "fallback 发生后审计证据不完整",
            detail: "缺口：\(missing.joined(separator: ", "))。provider fallback 必须同时保留回放摘要和至少一条可追溯审计。",
            evidence: compactEvidenceLines(for: fallbackEvents)
        )
    }

    private static func interruptDoesNotCorruptPendingAuthorizationChallenge(
        events: [VoiceReplayEvent],
        context: VoiceSafetyInvariantContext
    ) -> VoiceSafetyInvariantCheck {
        let interruptEvents = events.filter { event in
            guard event.category == .playback, event.state == .interrupted else { return false }
            let challengeID = event.metadata["challenge_id"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return !challengeID.isEmpty
        }

        guard !interruptEvents.isEmpty else {
            return VoiceSafetyInvariantCheck(
                kind: .interruptDoesNotCorruptPendingAuthorizationChallenge,
                status: .observing,
                summary: "等待真实 interrupt + challenge 场景",
                detail: "当前还没有看到带 challenge_id 的 interrupt 事件。",
                evidence: []
            )
        }

        let failedInterrupt = interruptEvents.first { interruptEvent in
            let challengeID = interruptEvent.metadata["challenge_id"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !challengeID.isEmpty else { return true }

            if context.activeChallenge?.challengeId.trimmingCharacters(in: .whitespacesAndNewlines) == challengeID {
                return false
            }

            let recovered = events.contains { event in
                guard event.createdAt >= interruptEvent.createdAt else { return false }
                guard event.category == .authorization else { return false }
                guard matchesChallenge(event: event, challengeID: challengeID) else { return false }
                return event.state == .preserved
                    || event.state == .verified
                    || event.state == .denied
                    || event.state == .failClosed
                    || event.state == .pending
                    || event.state == .escalated
            }
            return !recovered
        }

        if let failedInterrupt {
            return VoiceSafetyInvariantCheck(
                kind: .interruptDoesNotCorruptPendingAuthorizationChallenge,
                status: .fail,
                summary: "interrupt 之后没有看到同一 challenge 的保留或收束证据",
                detail: "这意味着待决挑战可能在播报中断后丢失，违背 fail-closed 要求。",
                evidence: compactEvidenceLines(for: [failedInterrupt])
            )
        }

        return VoiceSafetyInvariantCheck(
            kind: .interruptDoesNotCorruptPendingAuthorizationChallenge,
            status: .pass,
            summary: "interrupt 后挑战仍保持同一条链",
            detail: "所有带 challenge_id 的 interrupt 事件，后续都能看到相同 challenge 的保留或收束证据。",
            evidence: compactEvidenceLines(for: interruptEvents.suffix(2))
        )
    }

    private static func compactEvidenceLines<S: Sequence>(
        for events: S
    ) -> [String] where S.Element == VoiceReplayEvent {
        Array(events).map { event in
            var parts = [
                event.timelineLabel,
            ]
            let challengeID = challengeID(for: event)
            if !challengeID.isEmpty {
                parts.append("challenge=\(challengeID)")
            }
            let source = event.metadata["capture_source"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !source.isEmpty {
                parts.append("source=\(source)")
            }
            return parts.joined(separator: " | ")
        }
    }

    private static func challengeID(
        for event: VoiceReplayEvent
    ) -> String {
        event.metadata["challenge_id"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static func matchesChallenge(
        event: VoiceReplayEvent,
        challengeID: String
    ) -> Bool {
        guard !challengeID.isEmpty else { return false }
        return self.challengeID(for: event) == challengeID
    }
}
