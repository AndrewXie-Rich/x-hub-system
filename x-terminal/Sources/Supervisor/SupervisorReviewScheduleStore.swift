import Foundation

enum SupervisorReviewRunKind: String, Codable, CaseIterable, Sendable {
    case pulse
    case brainstorm
    case eventDriven = "event_driven"
    case manual
}

struct SupervisorReviewScheduleState: Equatable, Codable, Sendable {
    static let currentSchemaVersion = "xt.supervisor_review_schedule.v1"

    var schemaVersion: String
    var projectId: String
    var updatedAtMs: Int64
    var lastHeartbeatAtMs: Int64
    var lastObservedProgressAtMs: Int64
    var lastPulseReviewAtMs: Int64
    var lastBrainstormReviewAtMs: Int64
    var lastTriggerReviewAtMs: [String: Int64]
    var nextHeartbeatDueAtMs: Int64
    var nextPulseReviewDueAtMs: Int64
    var nextBrainstormReviewDueAtMs: Int64

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case projectId = "project_id"
        case updatedAtMs = "updated_at_ms"
        case lastHeartbeatAtMs = "last_heartbeat_at_ms"
        case lastObservedProgressAtMs = "last_observed_progress_at_ms"
        case lastPulseReviewAtMs = "last_pulse_review_at_ms"
        case lastBrainstormReviewAtMs = "last_brainstorm_review_at_ms"
        case lastTriggerReviewAtMs = "last_trigger_review_at_ms"
        case nextHeartbeatDueAtMs = "next_heartbeat_due_at_ms"
        case nextPulseReviewDueAtMs = "next_pulse_review_due_at_ms"
        case nextBrainstormReviewDueAtMs = "next_brainstorm_review_due_at_ms"
    }

    init(
        schemaVersion: String,
        projectId: String,
        updatedAtMs: Int64,
        lastHeartbeatAtMs: Int64,
        lastObservedProgressAtMs: Int64,
        lastPulseReviewAtMs: Int64,
        lastBrainstormReviewAtMs: Int64,
        lastTriggerReviewAtMs: [String: Int64],
        nextHeartbeatDueAtMs: Int64,
        nextPulseReviewDueAtMs: Int64,
        nextBrainstormReviewDueAtMs: Int64
    ) {
        self.schemaVersion = schemaVersion
        self.projectId = projectId
        self.updatedAtMs = updatedAtMs
        self.lastHeartbeatAtMs = lastHeartbeatAtMs
        self.lastObservedProgressAtMs = lastObservedProgressAtMs
        self.lastPulseReviewAtMs = lastPulseReviewAtMs
        self.lastBrainstormReviewAtMs = lastBrainstormReviewAtMs
        self.lastTriggerReviewAtMs = lastTriggerReviewAtMs
        self.nextHeartbeatDueAtMs = nextHeartbeatDueAtMs
        self.nextPulseReviewDueAtMs = nextPulseReviewDueAtMs
        self.nextBrainstormReviewDueAtMs = nextBrainstormReviewDueAtMs
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = (try? c.decode(String.self, forKey: .schemaVersion)) ?? Self.currentSchemaVersion
        projectId = (try? c.decode(String.self, forKey: .projectId)) ?? ""
        updatedAtMs = max(0, (try? c.decode(Int64.self, forKey: .updatedAtMs)) ?? 0)
        lastHeartbeatAtMs = max(0, (try? c.decode(Int64.self, forKey: .lastHeartbeatAtMs)) ?? 0)
        lastObservedProgressAtMs = max(0, (try? c.decode(Int64.self, forKey: .lastObservedProgressAtMs)) ?? 0)
        lastPulseReviewAtMs = max(0, (try? c.decode(Int64.self, forKey: .lastPulseReviewAtMs)) ?? 0)
        lastBrainstormReviewAtMs = max(0, (try? c.decode(Int64.self, forKey: .lastBrainstormReviewAtMs)) ?? 0)
        lastTriggerReviewAtMs = (try? c.decode([String: Int64].self, forKey: .lastTriggerReviewAtMs)) ?? [:]
        nextHeartbeatDueAtMs = max(0, (try? c.decode(Int64.self, forKey: .nextHeartbeatDueAtMs)) ?? 0)
        nextPulseReviewDueAtMs = max(0, (try? c.decode(Int64.self, forKey: .nextPulseReviewDueAtMs)) ?? 0)
        nextBrainstormReviewDueAtMs = max(0, (try? c.decode(Int64.self, forKey: .nextBrainstormReviewDueAtMs)) ?? 0)
    }
}

enum SupervisorReviewScheduleStore {
    private static let fileName = "supervisor_review_schedule.json"

    static func load(for ctx: AXProjectContext) -> SupervisorReviewScheduleState {
        try? ctx.ensureDirs()
        guard let data = try? Data(contentsOf: url(for: ctx)),
              let snapshot = try? JSONDecoder().decode(SupervisorReviewScheduleState.self, from: data) else {
            return emptyState(for: ctx)
        }
        return snapshot
    }

    @discardableResult
    static func touchHeartbeat(
        for ctx: AXProjectContext,
        config: AXProjectConfig,
        observedProgressAtMs: Int64? = nil,
        nowMs: Int64
    ) throws -> SupervisorReviewScheduleState {
        var state = load(for: ctx)
        state.projectId = AXProjectRegistryStore.projectId(forRoot: ctx.root)
        state.lastHeartbeatAtMs = max(state.lastHeartbeatAtMs, nowMs)
        state.updatedAtMs = max(state.updatedAtMs, nowMs)
        state.nextHeartbeatDueAtMs = dueAt(baseMs: nowMs, seconds: config.progressHeartbeatSeconds)
        let sanitizedObservedProgressAtMs = max(0, observedProgressAtMs ?? 0)
        let resolvedObservedProgressAtMs: Int64
        if sanitizedObservedProgressAtMs > 0 {
            resolvedObservedProgressAtMs = sanitizedObservedProgressAtMs
        } else if state.lastObservedProgressAtMs > 0 {
            resolvedObservedProgressAtMs = state.lastObservedProgressAtMs
        } else {
            resolvedObservedProgressAtMs = nowMs
        }
        state.lastObservedProgressAtMs = max(state.lastObservedProgressAtMs, resolvedObservedProgressAtMs)
        if state.nextPulseReviewDueAtMs <= 0 {
            state.nextPulseReviewDueAtMs = dueAt(baseMs: nowMs, seconds: config.reviewPulseSeconds)
        }
        state.nextBrainstormReviewDueAtMs = dueAt(
            baseMs: state.lastObservedProgressAtMs > 0 ? state.lastObservedProgressAtMs : nowMs,
            seconds: config.brainstormReviewSeconds
        )
        try save(state, for: ctx)
        return state
    }

    @discardableResult
    static func markReview(
        for ctx: AXProjectContext,
        config: AXProjectConfig,
        trigger: SupervisorReviewTrigger,
        runKind: SupervisorReviewRunKind,
        nowMs: Int64
    ) throws -> SupervisorReviewScheduleState {
        var state = load(for: ctx)
        state.projectId = AXProjectRegistryStore.projectId(forRoot: ctx.root)
        state.updatedAtMs = max(state.updatedAtMs, nowMs)
        state.lastTriggerReviewAtMs[trigger.rawValue] = nowMs

        switch runKind {
        case .pulse:
            state.lastPulseReviewAtMs = max(state.lastPulseReviewAtMs, nowMs)
            state.nextPulseReviewDueAtMs = dueAt(baseMs: nowMs, seconds: config.reviewPulseSeconds)
        case .brainstorm:
            state.lastBrainstormReviewAtMs = max(state.lastBrainstormReviewAtMs, nowMs)
            state.nextBrainstormReviewDueAtMs = dueAt(baseMs: nowMs, seconds: config.brainstormReviewSeconds)
        case .eventDriven, .manual:
            break
        }

        try save(state, for: ctx)
        return state
    }

    private static func save(
        _ state: SupervisorReviewScheduleState,
        for ctx: AXProjectContext
    ) throws {
        try ctx.ensureDirs()
        let data = try JSONEncoder().encode(state)
        try data.write(to: url(for: ctx), options: .atomic)
    }

    private static func url(for ctx: AXProjectContext) -> URL {
        ctx.xterminalDir.appendingPathComponent(fileName)
    }

    private static func emptyState(for ctx: AXProjectContext) -> SupervisorReviewScheduleState {
        SupervisorReviewScheduleState(
            schemaVersion: SupervisorReviewScheduleState.currentSchemaVersion,
            projectId: AXProjectRegistryStore.projectId(forRoot: ctx.root),
            updatedAtMs: 0,
            lastHeartbeatAtMs: 0,
            lastObservedProgressAtMs: 0,
            lastPulseReviewAtMs: 0,
            lastBrainstormReviewAtMs: 0,
            lastTriggerReviewAtMs: [:],
            nextHeartbeatDueAtMs: 0,
            nextPulseReviewDueAtMs: 0,
            nextBrainstormReviewDueAtMs: 0
        )
    }

    private static func dueAt(baseMs: Int64, seconds: Int) -> Int64 {
        guard seconds > 0 else { return 0 }
        return max(0, baseMs) + Int64(seconds) * 1000
    }
}
