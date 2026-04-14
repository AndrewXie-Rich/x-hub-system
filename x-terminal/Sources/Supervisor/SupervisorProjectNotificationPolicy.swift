import Foundation

enum SupervisorProjectNotificationChannel: String, Codable, Sendable {
    case silentLog = "silent_log"
    case badgeOnly = "badge_only"
    case briefCard = "brief_card"
    case interruptNow = "interrupt_now"
}

enum SupervisorProjectNotificationDeliveryStatus: String, Codable, Sendable {
    case delivered
    case suppressedDuplicate = "suppressed_duplicate"
    case suppressedJurisdiction = "suppressed_jurisdiction"
}

struct SupervisorProjectNotificationDecision: Equatable, Sendable {
    var channel: SupervisorProjectNotificationChannel
    var dedupeWindowSec: TimeInterval
    var shouldAddSystemMessage: Bool
    var shouldOpenConversationWindow: Bool
    var systemMessage: String?
    var recommendation: SupervisorRhythmRecommendation

    var shouldDedupe: Bool { dedupeWindowSec > 0 }
}

struct SupervisorProjectNotificationSnapshot: Equatable, Codable, Sendable {
    var updatedAt: Double
    var deliveredInterrupts: Int
    var deliveredBriefs: Int
    var deliveredBadges: Int
    var mutedLogs: Int
    var suppressedDuplicates: Int
    var lastDeliverySummary: String

    static let empty = SupervisorProjectNotificationSnapshot(
        updatedAt: 0,
        deliveredInterrupts: 0,
        deliveredBriefs: 0,
        deliveredBadges: 0,
        mutedLogs: 0,
        suppressedDuplicates: 0,
        lastDeliverySummary: ""
    )

    var hasActivity: Bool {
        deliveredInterrupts > 0 ||
        deliveredBriefs > 0 ||
        deliveredBadges > 0 ||
        mutedLogs > 0 ||
        suppressedDuplicates > 0
    }

    var statusLine: String {
        "notif interrupt=\(deliveredInterrupts) · brief=\(deliveredBriefs) · badge=\(deliveredBadges) · muted=\(mutedLogs) · deduped=\(suppressedDuplicates)"
    }

    var userFacingStatusLine: String {
        let deliveredCount = deliveredInterrupts + deliveredBriefs + deliveredBadges
        var parts: [String] = ["提醒 \(deliveredCount) 条"]
        if deliveredInterrupts > 0 {
            parts.append("高优先 \(deliveredInterrupts)")
        }
        if deliveredBriefs > 0 {
            parts.append("待跟进 \(deliveredBriefs)")
        }
        if deliveredBadges > 0 {
            parts.append("轻提醒 \(deliveredBadges)")
        }
        if mutedLogs > 0 {
            parts.append("静默观察 \(mutedLogs)")
        }
        if suppressedDuplicates > 0 {
            parts.append("重复折叠 \(suppressedDuplicates)")
        }
        return parts.joined(separator: " · ")
    }

    static func aggregated(
        from records: [SupervisorProjectNotificationRecord]
    ) -> SupervisorProjectNotificationSnapshot {
        guard !records.isEmpty else { return .empty }

        var snapshot = SupervisorProjectNotificationSnapshot.empty
        let sortedRecords = records.sorted { lhs, rhs in
            if lhs.occurredAt != rhs.occurredAt {
                return lhs.occurredAt < rhs.occurredAt
            }
            return lhs.deliverySummary < rhs.deliverySummary
        }

        for record in sortedRecords {
            snapshot.updatedAt = max(snapshot.updatedAt, record.occurredAt)
            snapshot.lastDeliverySummary = record.deliverySummary
            switch record.status {
            case .delivered:
                switch record.channel {
                case .interruptNow:
                    snapshot.deliveredInterrupts += 1
                case .briefCard:
                    snapshot.deliveredBriefs += 1
                case .badgeOnly:
                    snapshot.deliveredBadges += 1
                case .silentLog:
                    snapshot.mutedLogs += 1
                }
            case .suppressedDuplicate:
                snapshot.suppressedDuplicates += 1
            case .suppressedJurisdiction:
                continue
            }
        }

        return snapshot
    }
}

struct SupervisorProjectNotificationRecord: Equatable, Codable, Sendable {
    var projectId: String
    var projectName: String
    var eventType: SupervisorProjectActionEventType
    var severity: SupervisorProjectActionSeverity
    var channel: SupervisorProjectNotificationChannel
    var status: SupervisorProjectNotificationDeliveryStatus
    var occurredAt: Double
    var deliverySummary: String
}

struct SupervisorProjectNotificationCenterState: Equatable, Codable, Sendable {
    static let maxReadEventIDs = 192
    static let maxSnoozedEventIDs = 96

    var readEventIDs: [String]
    var snoozedUntilByEventID: [String: TimeInterval]

    static let empty = SupervisorProjectNotificationCenterState(
        readEventIDs: [],
        snoozedUntilByEventID: [:]
    )

    func normalized(
        now: Date = Date(),
        activeEventIDs: Set<String>? = nil
    ) -> SupervisorProjectNotificationCenterState {
        let normalizedActiveIDs = activeEventIDs?.reduce(into: Set<String>()) { result, raw in
            let value = Self.normalizedID(raw)
            guard !value.isEmpty else { return }
            result.insert(value)
        }
        let normalizedReadEventIDs = Self.deduplicated(readEventIDs.map(Self.normalizedID))
            .filter { !$0.isEmpty }
            .filter { normalizedActiveIDs?.contains($0) ?? true }
        let limitedReadEventIDs = Array(
            normalizedReadEventIDs.suffix(Self.maxReadEventIDs)
        )

        let nowTs = now.timeIntervalSince1970
        let filteredSnoozes = snoozedUntilByEventID.reduce(
            into: [String: TimeInterval]()
        ) { result, entry in
            let eventID = Self.normalizedID(entry.key)
            guard !eventID.isEmpty else { return }
            guard entry.value > nowTs else { return }
            guard normalizedActiveIDs?.contains(eventID) ?? true else { return }
            result[eventID] = max(entry.value, result[eventID] ?? 0)
        }
        let limitedSnoozes: [String: TimeInterval]
        if filteredSnoozes.count > Self.maxSnoozedEventIDs {
            limitedSnoozes = Dictionary(
                uniqueKeysWithValues: filteredSnoozes
                    .sorted { lhs, rhs in
                        if lhs.value != rhs.value {
                            return lhs.value > rhs.value
                        }
                        return lhs.key < rhs.key
                    }
                    .prefix(Self.maxSnoozedEventIDs)
                    .map { ($0.key, $0.value) }
            )
        } else {
            limitedSnoozes = filteredSnoozes
        }

        return SupervisorProjectNotificationCenterState(
            readEventIDs: limitedReadEventIDs,
            snoozedUntilByEventID: limitedSnoozes
        )
    }

    func isRead(
        eventID: String,
        defaultUnread: Bool
    ) -> Bool {
        guard defaultUnread else { return true }
        let normalized = Self.normalizedID(eventID)
        guard !normalized.isEmpty else { return false }
        return readEventIDs.contains(normalized)
    }

    func snoozedUntil(
        eventID: String,
        now: Date = Date()
    ) -> Date? {
        let normalized = Self.normalizedID(eventID)
        guard !normalized.isEmpty,
              let until = snoozedUntilByEventID[normalized],
              until > now.timeIntervalSince1970 else {
            return nil
        }
        return Date(timeIntervalSince1970: until)
    }

    mutating func setRead(
        eventID: String,
        isRead: Bool
    ) {
        let normalized = Self.normalizedID(eventID)
        guard !normalized.isEmpty else { return }
        if isRead {
            if !readEventIDs.contains(normalized) {
                readEventIDs.append(normalized)
            }
        } else {
            readEventIDs.removeAll { $0 == normalized }
        }
    }

    mutating func setSnoozedUntil(
        eventID: String,
        until: Date?,
        now: Date = Date()
    ) {
        let normalized = Self.normalizedID(eventID)
        guard !normalized.isEmpty else { return }
        guard let until,
              until.timeIntervalSince1970 > now.timeIntervalSince1970 else {
            snoozedUntilByEventID.removeValue(forKey: normalized)
            return
        }
        snoozedUntilByEventID[normalized] = until.timeIntervalSince1970
    }

    private static func deduplicated(_ ids: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for id in ids where !id.isEmpty {
            guard !seen.contains(id) else { continue }
            seen.insert(id)
            result.append(id)
        }
        return result
    }

    private static func normalizedID(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum SupervisorProjectNotificationPolicy {
    static func decide(for event: SupervisorProjectActionEvent) -> SupervisorProjectNotificationDecision {
        let recommendation = SupervisorRhythmRecommendationEngine.recommendation(for: event)

        switch event.severity {
        case .authorizationRequired:
            return SupervisorProjectNotificationDecision(
                channel: .interruptNow,
                dedupeWindowSec: 180,
                shouldAddSystemMessage: true,
                shouldOpenConversationWindow: true,
                systemMessage: interruptSystemMessage(for: recommendation),
                recommendation: recommendation
            )
        case .interruptNow:
            return SupervisorProjectNotificationDecision(
                channel: .interruptNow,
                dedupeWindowSec: 120,
                shouldAddSystemMessage: true,
                shouldOpenConversationWindow: true,
                systemMessage: interruptSystemMessage(for: recommendation),
                recommendation: recommendation
            )
        case .briefCard:
            return SupervisorProjectNotificationDecision(
                channel: recommendation.isSubstantiveChange ? .briefCard : .silentLog,
                dedupeWindowSec: 90,
                shouldAddSystemMessage: false,
                shouldOpenConversationWindow: false,
                systemMessage: nil,
                recommendation: recommendation
            )
        case .badgeOnly:
            if recommendation.recommendationType == .decisionRailCleanup,
               recommendation.isSubstantiveChange {
                return SupervisorProjectNotificationDecision(
                    channel: .briefCard,
                    dedupeWindowSec: 120,
                    shouldAddSystemMessage: false,
                    shouldOpenConversationWindow: false,
                    systemMessage: nil,
                    recommendation: recommendation
                )
            }
            return SupervisorProjectNotificationDecision(
                channel: .badgeOnly,
                dedupeWindowSec: 60,
                shouldAddSystemMessage: false,
                shouldOpenConversationWindow: false,
                systemMessage: nil,
                recommendation: recommendation
            )
        case .silentLog:
            if recommendation.recommendationType == .decisionRailCleanup,
               recommendation.isSubstantiveChange {
                return SupervisorProjectNotificationDecision(
                    channel: .briefCard,
                    dedupeWindowSec: 120,
                    shouldAddSystemMessage: false,
                    shouldOpenConversationWindow: false,
                    systemMessage: nil,
                    recommendation: recommendation
                )
            }
            return SupervisorProjectNotificationDecision(
                channel: .silentLog,
                dedupeWindowSec: 45,
                shouldAddSystemMessage: false,
                shouldOpenConversationWindow: false,
                systemMessage: nil,
                recommendation: recommendation
            )
        }
    }

    static func dedupeFingerprint(
        for event: SupervisorProjectActionEvent,
        channel: SupervisorProjectNotificationChannel
    ) -> String {
        let recommendation = SupervisorRhythmRecommendationEngine.recommendation(for: event)
        return [
            event.projectId,
            channel.rawValue,
            recommendation.dedupeKey,
        ].joined(separator: "|")
    }

    static func deliverySummary(
        event: SupervisorProjectActionEvent,
        channel: SupervisorProjectNotificationChannel,
        status: SupervisorProjectNotificationDeliveryStatus
    ) -> String {
        "\(channel.rawValue):\(status.rawValue):\(event.projectName)"
    }

    private static func interruptSystemMessage(
        for recommendation: SupervisorRhythmRecommendation
    ) -> String {
        let evidence = recommendation.evidenceRefs.first ?? "supervisor_project_action_event"
        return [
            "[Supervisor Update]",
            "变化：\(interruptPresentedWhatChangedText(recommendation.whatChanged))",
            "原因：\(recommendation.whyItMatters)",
            "当前阻塞：\(interruptPresentedWaitingOnText(recommendation.waitingOn))",
            "下一步：\(recommendation.recommendedNextAction)",
            "预计更新时间：\(recommendation.nextUpdateEta)",
            "证据：\(evidence)",
        ].joined(separator: "\n")
    }

    private static func interruptPresentedWhatChangedText(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "unknown" }
        return SupervisorBlockerPresentation.label(trimmed)
    }

    private static func interruptPresentedWaitingOnText(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "unknown" }

        switch trimmed.lowercased() {
        case "user / hub authorization":
            return "用户 / Hub 授权"
        case "a portfolio-level decision":
            return "一项组合级决策"
        case "blocker resolution":
            return "阻塞解除"
        case "the recommended next action":
            return "推荐下一步执行"
        case "first concrete triage step":
            return "首个明确分诊动作"
        case "none":
            return "无"
        default:
            let presented = SupervisorBlockerPresentation.label(trimmed)
            return presented == "none" ? "无" : presented
        }
    }
}
