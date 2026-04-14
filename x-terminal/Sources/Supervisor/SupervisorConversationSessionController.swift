import Foundation

enum SupervisorConversationWindowState: String, Codable, Equatable {
    case hidden
    case armed
    case conversing
}

enum SupervisorConversationOpenedBy: String, Codable, Equatable {
    case manualButton = "manual_button"
    case wakePhrase = "wake_phrase"
    case promptPhrase = "prompt_phrase"
    case voiceReplyFollowup = "voice_reply_followup"
}

enum SupervisorConversationSessionEventKind: String, Codable, Equatable {
    case wakeHit = "wake_hit"
    case userTurn = "user_turn"
    case assistantTurn = "assistant_turn"
    case ttsSpoken = "tts_spoken"
    case timeout
}

struct SupervisorConversationSessionPolicy: Codable, Equatable {
    var enabled: Bool
    var autoOpenOnWake: Bool
    var defaultTTLSeconds: Int
    var maxTTLSeconds: Int
    var extendOnUserTurn: Bool
    var extendOnAssistantTurn: Bool
    var allowHiddenArmedMode: Bool
    var allowBackgroundWakeWhenWindowClosed: Bool
    var quietHoursRespected: Bool
    var wakeDoesNotImplyAuthorization: Bool
    var auditRef: String?

    static func `default`() -> SupervisorConversationSessionPolicy {
        SupervisorConversationSessionPolicy(
            enabled: true,
            autoOpenOnWake: true,
            defaultTTLSeconds: 45,
            maxTTLSeconds: 180,
            extendOnUserTurn: true,
            extendOnAssistantTurn: true,
            allowHiddenArmedMode: true,
            allowBackgroundWakeWhenWindowClosed: true,
            quietHoursRespected: true,
            wakeDoesNotImplyAuthorization: true,
            auditRef: nil
        )
    }
}

struct SupervisorConversationSessionSnapshot: Codable, Equatable {
    var schemaVersion: String
    var windowState: SupervisorConversationWindowState
    var conversationId: String?
    var openedBy: SupervisorConversationOpenedBy?
    var wakeMode: VoiceWakeMode
    var route: VoiceRouteMode
    var expiresAtMs: Double?
    var remainingTTLSeconds: Int
    var keepOpenOverride: Bool
    var reasonCode: String
    var auditRef: String?

    var outwardState: SupervisorConversationSessionOutwardState {
        SupervisorConversationSessionOutwardState(snapshot: self)
    }

    static func idle(
        policy: SupervisorConversationSessionPolicy,
        wakeMode: VoiceWakeMode,
        route: VoiceRouteMode,
        reasonCode: String = "none"
    ) -> SupervisorConversationSessionSnapshot {
        SupervisorConversationSessionSnapshot(
            schemaVersion: "xt.supervisor_conversation_window_state.v1",
            windowState: idleWindowState(policy: policy, wakeMode: wakeMode),
            conversationId: nil,
            openedBy: nil,
            wakeMode: wakeMode,
            route: route,
            expiresAtMs: nil,
            remainingTTLSeconds: 0,
            keepOpenOverride: false,
            reasonCode: reasonCode,
            auditRef: policy.auditRef
        )
    }

    var isConversing: Bool {
        windowState == .conversing
    }

    private static func idleWindowState(
        policy: SupervisorConversationSessionPolicy,
        wakeMode: VoiceWakeMode
    ) -> SupervisorConversationWindowState {
        guard policy.enabled,
              policy.allowHiddenArmedMode,
              wakeMode != .pushToTalk else {
            return .hidden
        }
        return .armed
    }
}

struct SupervisorConversationSessionOutwardState: Codable, Equatable {
    var schemaVersion: String
    var windowState: SupervisorConversationWindowState
    var remainingTTLSeconds: Int
    var reasonCode: String
    var auditRef: String?

    init(snapshot: SupervisorConversationSessionSnapshot) {
        schemaVersion = snapshot.schemaVersion
        windowState = snapshot.windowState
        remainingTTLSeconds = snapshot.remainingTTLSeconds
        reasonCode = snapshot.reasonCode
        auditRef = snapshot.auditRef
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case windowState = "window_state"
        case remainingTTLSeconds = "remaining_ttl_sec"
        case reasonCode = "reason_code"
        case auditRef = "audit_ref"
    }
}

struct SupervisorConversationSessionEvent: Codable, Equatable {
    var schemaVersion: String
    var conversationId: String?
    var event: SupervisorConversationSessionEventKind
    var reasonCode: String
    var remainingTTLSeconds: Int
    var emittedAtMs: Double
    var auditRef: String?

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case conversationId = "conversation_id"
        case event
        case reasonCode = "reason_code"
        case remainingTTLSeconds = "remaining_ttl_sec"
        case emittedAtMs = "emitted_at_ms"
        case auditRef = "audit_ref"
    }
}

@MainActor
final class SupervisorConversationSessionController: ObservableObject {
    static let shared = SupervisorConversationSessionController()

    @Published private(set) var snapshot: SupervisorConversationSessionSnapshot
    @Published private(set) var latestEvent: SupervisorConversationSessionEvent?

    private var policy: SupervisorConversationSessionPolicy
    private var route: VoiceRouteMode
    private var wakeMode: VoiceWakeMode
    private var expiryDate: Date?
    private let nowProvider: () -> Date
    private var ticker: Timer?

    init(
        policy: SupervisorConversationSessionPolicy = .default(),
        route: VoiceRouteMode = .manualText,
        wakeMode: VoiceWakeMode = .pushToTalk,
        nowProvider: @escaping () -> Date = Date.init,
        autoTick: Bool = true
    ) {
        self.policy = policy
        self.route = route
        self.wakeMode = wakeMode
        self.nowProvider = nowProvider
        self.snapshot = .idle(
            policy: policy,
            wakeMode: wakeMode,
            route: route
        )
        if autoTick {
            startTicker()
        }
    }

    deinit {
        ticker?.invalidate()
    }

    static func makeForTesting(
        policy: SupervisorConversationSessionPolicy = .default(),
        route: VoiceRouteMode = .manualText,
        wakeMode: VoiceWakeMode = .pushToTalk,
        nowProvider: @escaping () -> Date
    ) -> SupervisorConversationSessionController {
        SupervisorConversationSessionController(
            policy: policy,
            route: route,
            wakeMode: wakeMode,
            nowProvider: nowProvider,
            autoTick: false
        )
    }

    func configure(
        policy: SupervisorConversationSessionPolicy? = nil,
        wakeMode: VoiceWakeMode? = nil,
        route: VoiceRouteMode? = nil
    ) {
        if let policy {
            self.policy = policy
        }
        if let wakeMode {
            self.wakeMode = wakeMode
        }
        if let route {
            self.route = route
        }
        refresh(now: nowProvider())
    }

    func manualOpen(now: Date? = nil) {
        openConversation(
            openedBy: .manualButton,
            reasonCode: "manual_open",
            now: now ?? nowProvider()
        )
    }

    func registerWakeHit(now: Date? = nil) {
        guard policy.enabled, policy.autoOpenOnWake, wakeMode != .pushToTalk else { return }
        let current = now ?? nowProvider()
        let source: SupervisorConversationOpenedBy = wakeMode == .promptPhraseOnly ? .promptPhrase : .wakePhrase
        openConversation(
            openedBy: source,
            reasonCode: "wake_detected",
            now: current
        )
        publishEvent(kind: .wakeHit, now: current)
    }

    func registerUserTurn(fromVoice: Bool, now: Date? = nil) {
        guard policy.enabled, policy.extendOnUserTurn else { return }
        let current = now ?? nowProvider()
        let source: SupervisorConversationOpenedBy = fromVoice ? .wakePhrase : .manualButton
        openOrExtend(
            openedBy: source,
            reasonCode: "user_turn",
            now: current
        )
        publishEvent(kind: .userTurn, now: current)
    }

    func registerAssistantTurn(spoken: Bool, now: Date? = nil) {
        guard policy.enabled, policy.extendOnAssistantTurn else { return }
        let current = now ?? nowProvider()
        let reasonCode = spoken ? "tts_spoken" : "assistant_turn"
        openOrExtend(
            openedBy: .voiceReplyFollowup,
            reasonCode: reasonCode,
            now: current
        )
        publishEvent(kind: spoken ? .ttsSpoken : .assistantTurn, now: current)
    }

    func holdConversationForFollowUp(
        reasonCode: String = "awaiting_memory_fact_follow_up",
        now: Date? = nil
    ) {
        guard policy.enabled else { return }
        let current = now ?? nowProvider()
        let openedBy = snapshot.openedBy ?? .voiceReplyFollowup
        expiryDate = current.addingTimeInterval(TimeInterval(policy.maxTTLSeconds))
        if snapshot.isConversing {
            publishConversationSnapshot(
                openedBy: openedBy,
                reasonCode: reasonCode,
                now: current
            )
            return
        }

        snapshot = SupervisorConversationSessionSnapshot(
            schemaVersion: "xt.supervisor_conversation_window_state.v1",
            windowState: .conversing,
            conversationId: UUID().uuidString.lowercased(),
            openedBy: openedBy,
            wakeMode: wakeMode,
            route: route,
            expiresAtMs: expiryDate?.timeIntervalSince1970.multiplied(by: 1000),
            remainingTTLSeconds: remainingTTLSeconds(at: current),
            keepOpenOverride: false,
            reasonCode: reasonCode,
            auditRef: policy.auditRef
        )
    }

    func registerRouteFailClosed(reasonCode: String?, now: Date? = nil) {
        guard snapshot.isConversing else { return }
        endConversation(
            reasonCode: reasonCode?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                ? reasonCode!
                : "route_fail_closed",
            now: now ?? nowProvider()
        )
    }

    func endConversation(reasonCode: String = "manual_close", now: Date? = nil) {
        expiryDate = nil
        snapshot = .idle(
            policy: policy,
            wakeMode: wakeMode,
            route: route,
            reasonCode: reasonCode
        )
        refresh(now: now ?? nowProvider())
    }

    func refresh(now: Date? = nil) {
        let current = now ?? nowProvider()
        guard snapshot.isConversing else {
            if snapshot.windowState != idleWindowState() ||
                snapshot.route != route ||
                snapshot.wakeMode != wakeMode {
                snapshot = .idle(
                    policy: policy,
                    wakeMode: wakeMode,
                    route: route,
                    reasonCode: snapshot.reasonCode
                )
            }
            return
        }

        guard let expiryDate else {
            snapshot = .idle(
                policy: policy,
                wakeMode: wakeMode,
                route: route,
                reasonCode: "ttl_expired"
            )
            publishEvent(
                kind: .timeout,
                reasonCode: "timeout",
                conversationId: nil,
                now: current
            )
            return
        }

        if !snapshot.keepOpenOverride, current >= expiryDate {
            let expiredConversationId = snapshot.conversationId
            endConversation(reasonCode: "ttl_expired", now: current)
            publishEvent(
                kind: .timeout,
                reasonCode: "timeout",
                conversationId: expiredConversationId,
                now: current
            )
            return
        }

        publishConversationSnapshot(
            openedBy: snapshot.openedBy ?? .manualButton,
            reasonCode: snapshot.reasonCode,
            now: current
        )
    }

    private func openOrExtend(
        openedBy: SupervisorConversationOpenedBy,
        reasonCode: String,
        now: Date
    ) {
        if snapshot.isConversing {
            extendConversation(reasonCode: reasonCode, now: now)
        } else {
            openConversation(openedBy: openedBy, reasonCode: reasonCode, now: now)
        }
    }

    private func openConversation(
        openedBy: SupervisorConversationOpenedBy,
        reasonCode: String,
        now: Date
    ) {
        expiryDate = clampedExpiry(from: now)
        snapshot = SupervisorConversationSessionSnapshot(
            schemaVersion: "xt.supervisor_conversation_window_state.v1",
            windowState: .conversing,
            conversationId: UUID().uuidString.lowercased(),
            openedBy: openedBy,
            wakeMode: wakeMode,
            route: route,
            expiresAtMs: expiryDate?.timeIntervalSince1970.multiplied(by: 1000),
            remainingTTLSeconds: remainingTTLSeconds(at: now),
            keepOpenOverride: false,
            reasonCode: reasonCode,
            auditRef: policy.auditRef
        )
    }

    private func extendConversation(reasonCode: String, now: Date) {
        expiryDate = clampedExpiry(from: now)
        publishConversationSnapshot(
            openedBy: snapshot.openedBy ?? .manualButton,
            reasonCode: reasonCode,
            now: now
        )
    }

    private func publishConversationSnapshot(
        openedBy: SupervisorConversationOpenedBy,
        reasonCode: String,
        now: Date
    ) {
        snapshot.schemaVersion = "xt.supervisor_conversation_window_state.v1"
        snapshot.windowState = .conversing
        snapshot.conversationId = snapshot.conversationId ?? UUID().uuidString.lowercased()
        snapshot.openedBy = openedBy
        snapshot.wakeMode = wakeMode
        snapshot.route = route
        snapshot.expiresAtMs = expiryDate?.timeIntervalSince1970.multiplied(by: 1000)
        snapshot.remainingTTLSeconds = remainingTTLSeconds(at: now)
        snapshot.reasonCode = reasonCode
        snapshot.auditRef = policy.auditRef
    }

    private func clampedExpiry(from now: Date) -> Date {
        let desired = now.addingTimeInterval(TimeInterval(policy.defaultTTLSeconds))
        let maximum = now.addingTimeInterval(TimeInterval(policy.maxTTLSeconds))
        return min(desired, maximum)
    }

    private func remainingTTLSeconds(at now: Date) -> Int {
        guard let expiryDate else { return 0 }
        return max(0, Int(ceil(expiryDate.timeIntervalSince(now))))
    }

    private func idleWindowState() -> SupervisorConversationWindowState {
        if policy.enabled,
           policy.allowHiddenArmedMode,
           wakeMode != .pushToTalk {
            return .armed
        }
        return .hidden
    }

    private func startTicker() {
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
        if let ticker {
            RunLoop.main.add(ticker, forMode: .common)
        }
    }

    private func publishEvent(
        kind: SupervisorConversationSessionEventKind,
        reasonCode: String? = nil,
        conversationId: String? = nil,
        now: Date
    ) {
        let emittedReasonCode = reasonCode ?? snapshot.reasonCode
        let resolvedConversationId = conversationId ?? snapshot.conversationId
        latestEvent = SupervisorConversationSessionEvent(
            schemaVersion: "xt.supervisor_conversation_window_event.v1",
            conversationId: resolvedConversationId,
            event: kind,
            reasonCode: emittedReasonCode,
            remainingTTLSeconds: snapshot.remainingTTLSeconds,
            emittedAtMs: now.timeIntervalSince1970.multiplied(by: 1000),
            auditRef: policy.auditRef
        )
    }
}

private extension Double {
    func multiplied(by value: Double) -> Double {
        self * value
    }
}
