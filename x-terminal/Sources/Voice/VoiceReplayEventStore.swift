import Foundation

enum VoiceEvidenceState: String, Codable, Equatable, Sendable {
    case idle
    case ready
    case attention
    case failed

    var localizedLabel: String {
        switch self {
        case .idle:
            return "等待事件"
        case .ready:
            return "证据完整"
        case .attention:
            return "继续观察"
        case .failed:
            return "需要排查"
        }
    }

    var surfaceState: XTUISurfaceState {
        switch self {
        case .idle:
            return .blockedWaitingUpstream
        case .ready:
            return .ready
        case .attention:
            return .inProgress
        case .failed:
            return .diagnosticRequired
        }
    }
}

enum VoiceReplayEventCategory: String, Codable, Equatable, CaseIterable, Sendable {
    case conversation
    case wake
    case utterance
    case talkLoop = "talk_loop"
    case playback
    case dispatch
    case authorization
}

enum VoiceReplayEventState: String, Codable, Equatable, CaseIterable, Sendable {
    case started
    case stopped
    case hit
    case committed
    case forwarded
    case resumed
    case interrupted
    case spoken
    case fallback
    case failed
    case pending
    case escalated
    case verified
    case denied
    case failClosed = "fail_closed"
    case mobileConfirmed = "mobile_confirmed"
    case mobileCleared = "mobile_cleared"
    case cancelled
    case preserved
    case repeated
    case dropped
    case suppressed
}

struct VoiceReplayEvent: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var createdAt: TimeInterval
    var category: VoiceReplayEventCategory
    var state: VoiceReplayEventState
    var summary: String
    var reasonCode: String
    var detail: String
    var metadata: [String: String]

    init(
        id: String = UUID().uuidString.lowercased(),
        createdAt: TimeInterval = Date().timeIntervalSince1970,
        category: VoiceReplayEventCategory,
        state: VoiceReplayEventState,
        summary: String,
        reasonCode: String = "",
        detail: String = "",
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.createdAt = createdAt
        self.category = category
        self.state = state
        self.summary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        self.reasonCode = reasonCode.trimmingCharacters(in: .whitespacesAndNewlines)
        self.detail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        self.metadata = Self.normalized(metadata)
    }

    var timelineLabel: String {
        let trimmed = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }

        switch (category, state) {
        case (.wake, .hit):
            return "唤醒命中"
        case (.utterance, .forwarded):
            return "语音转入 Supervisor"
        case (.talkLoop, .resumed):
            return "Talk loop 恢复监听"
        case (.playback, .interrupted):
            return "播报被打断"
        case (.playback, .fallback):
            return "语音已回退播放"
        case (.playback, .failed):
            return "语音播放失败"
        case (.dispatch, .spoken):
            return "语音派发已播报"
        case (.authorization, .pending):
            return "授权挑战已发起"
        case (.authorization, .escalated):
            return "授权升级到移动端"
        case (.authorization, .verified):
            return "口头授权已验证"
        case (.authorization, .failClosed):
            return "授权保持 fail-closed"
        case (.authorization, .preserved):
            return "挑战保持不变"
        case (.authorization, .cancelled):
            return "授权挑战已取消"
        case (.conversation, .started):
            return "免提通话已开始"
        case (.conversation, .stopped):
            return "免提通话已结束"
        default:
            return "\(category.rawValue):\(state.rawValue)"
        }
    }

    private static func normalized(
        _ metadata: [String: String]
    ) -> [String: String] {
        var result: [String: String] = [:]
        for (key, value) in metadata {
            let normalizedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedKey.isEmpty, !normalizedValue.isEmpty else { continue }
            result[normalizedKey] = normalizedValue
        }
        return result
    }
}

struct VoiceReplaySummary: Codable, Equatable, Sendable {
    var overallState: VoiceEvidenceState
    var headline: String
    var summaryLine: String
    var compactTimelineText: String
    var recentEntries: [VoiceReplayEvent]
    var updatedAt: TimeInterval

    static let empty = VoiceReplaySummary(
        overallState: .idle,
        headline: "等待语音链路事件",
        summaryLine: "当前还没有可回放的语音摘要。",
        compactTimelineText: "",
        recentEntries: [],
        updatedAt: 0
    )

    var isEmpty: Bool {
        recentEntries.isEmpty && updatedAt == 0
    }
}

struct VoiceReplayEventStore: Equatable, Sendable {
    private(set) var events: [VoiceReplayEvent]
    var maxEntries: Int

    init(
        maxEntries: Int = 24,
        events: [VoiceReplayEvent] = []
    ) {
        self.maxEntries = max(1, maxEntries)
        self.events = Array(events.prefix(max(1, maxEntries)))
    }

    mutating func append(_ event: VoiceReplayEvent) {
        events.insert(event, at: 0)
        if events.count > maxEntries {
            events.removeLast(events.count - maxEntries)
        }
    }

    mutating func append(
        category: VoiceReplayEventCategory,
        state: VoiceReplayEventState,
        summary: String,
        reasonCode: String = "",
        detail: String = "",
        metadata: [String: String] = [:],
        createdAt: TimeInterval = Date().timeIntervalSince1970
    ) {
        append(
            VoiceReplayEvent(
                createdAt: createdAt,
                category: category,
                state: state,
                summary: summary,
                reasonCode: reasonCode,
                detail: detail,
                metadata: metadata
            )
        )
    }

    mutating func reset() {
        events = []
    }

    func buildSummary(limit: Int = 6) -> VoiceReplaySummary {
        guard !events.isEmpty else {
            return .empty
        }

        let selected = Array(events.prefix(max(1, limit)))
        let ordered = selected.sorted { lhs, rhs in
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt < rhs.createdAt
            }
            return lhs.id < rhs.id
        }
        let latest = selected.first ?? ordered.last!
        let overallState = VoiceReplayEventStore.overallState(for: selected)
        let compactTimelineText = ordered
            .map(\.timelineLabel)
            .joined(separator: " -> ")
        let latestLabel = latest.timelineLabel
        let summaryLine = "最近 \(selected.count) 条语音证据已记录；最新事件：\(latestLabel)"

        return VoiceReplaySummary(
            overallState: overallState,
            headline: latestLabel,
            summaryLine: summaryLine,
            compactTimelineText: compactTimelineText,
            recentEntries: selected,
            updatedAt: latest.createdAt
        )
    }

    private static func overallState(
        for events: [VoiceReplayEvent]
    ) -> VoiceEvidenceState {
        if events.contains(where: { $0.state == .failed || $0.state == .failClosed }) {
            return .failed
        }
        if events.contains(where: { $0.state == .fallback || $0.state == .interrupted || $0.state == .cancelled }) {
            return .attention
        }
        if events.contains(where: { $0.state == .suppressed || $0.state == .dropped }) {
            return .attention
        }
        return .ready
    }
}
