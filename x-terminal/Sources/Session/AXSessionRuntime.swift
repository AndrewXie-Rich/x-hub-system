import Foundation

enum AXSessionRuntimeState: String, Codable, Equatable, Sendable {
    case idle
    case planning
    case awaiting_model
    case awaiting_tool_approval
    case running_tools
    case awaiting_hub
    case failed_recoverable
    case completed
}

struct AXSessionRuntimeSnapshot: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1
    static let staleBusyScavengeAfterSeconds: TimeInterval = 15 * 60
    static let restoredInterruptedFailureCode = "interrupted_session_runtime_restored"

    var schemaVersion: Int
    var state: AXSessionRuntimeState
    var runID: String?
    var updatedAt: Double
    var startedAt: Double?
    var completedAt: Double?
    var lastRuntimeSummary: String?
    var lastToolBatchIDs: [String]
    var pendingToolCallCount: Int
    var lastFailureCode: String?
    var resumeToken: String?
    var recoverable: Bool

    static func idle(at timestamp: Double = Date().timeIntervalSince1970) -> AXSessionRuntimeSnapshot {
        AXSessionRuntimeSnapshot(
            schemaVersion: currentSchemaVersion,
            state: .idle,
            runID: nil,
            updatedAt: timestamp,
            startedAt: nil,
            completedAt: nil,
            lastRuntimeSummary: nil,
            lastToolBatchIDs: [],
            pendingToolCallCount: 0,
            lastFailureCode: nil,
            resumeToken: nil,
            recoverable: false
        )
    }

    func normalized(at timestamp: Double = Date().timeIntervalSince1970) -> AXSessionRuntimeSnapshot {
        var snapshot = self
        snapshot.schemaVersion = Self.currentSchemaVersion
        snapshot.updatedAt = max(snapshot.updatedAt, timestamp)
        snapshot.pendingToolCallCount = max(0, snapshot.pendingToolCallCount)
        return snapshot
    }

    func stabilized(now: Double = Date().timeIntervalSince1970) -> AXSessionRuntimeSnapshot {
        var snapshot = self
        snapshot.schemaVersion = Self.currentSchemaVersion
        snapshot.pendingToolCallCount = max(0, snapshot.pendingToolCallCount)

        guard snapshot.shouldScavengeBusyState(now: now) else {
            return snapshot
        }

        let existingSummary = snapshot.lastRuntimeSummary?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        snapshot.state = .failed_recoverable
        snapshot.lastFailureCode = snapshot.lastFailureCode?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? snapshot.lastFailureCode
            : "stale_session_runtime_scavenged"
        snapshot.lastRuntimeSummary = existingSummary.isEmpty
            ? "stale_session_runtime_scavenged"
            : "stale_session_runtime_scavenged: \(existingSummary)"
        snapshot.pendingToolCallCount = 0
        snapshot.lastToolBatchIDs = []
        snapshot.resumeToken = nil
        snapshot.recoverable = false
        snapshot.completedAt = snapshot.completedAt ?? now
        snapshot.updatedAt = max(snapshot.updatedAt, now)
        return snapshot
    }

    func restoredFromPersistence(now: Double = Date().timeIntervalSince1970) -> AXSessionRuntimeSnapshot {
        var snapshot = normalized(at: now)

        guard snapshot.state.recoversToIdleWhenRestored else {
            return snapshot.stabilized(now: now)
        }

        let existingSummary = snapshot.lastRuntimeSummary?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        snapshot.state = .idle
        snapshot.lastFailureCode = snapshot.lastFailureCode?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? snapshot.lastFailureCode
            : Self.restoredInterruptedFailureCode
        snapshot.lastRuntimeSummary = existingSummary.isEmpty
            ? Self.restoredInterruptedFailureCode
            : "\(Self.restoredInterruptedFailureCode): \(existingSummary)"
        snapshot.pendingToolCallCount = 0
        snapshot.lastToolBatchIDs = []
        snapshot.resumeToken = nil
        snapshot.recoverable = false
        snapshot.completedAt = now
        snapshot.updatedAt = max(snapshot.updatedAt, now)
        return snapshot
    }

    private func shouldScavengeBusyState(now: Double) -> Bool {
        guard state.scavengesWhenStale else { return false }
        let lastActivityAt = max(updatedAt, startedAt ?? 0, completedAt ?? 0)
        guard lastActivityAt > 0 else { return false }
        return now - lastActivityAt >= Self.staleBusyScavengeAfterSeconds
    }
}

private extension AXSessionRuntimeState {
    var scavengesWhenStale: Bool {
        switch self {
        case .planning, .awaiting_model, .running_tools, .awaiting_hub:
            return true
        case .idle, .awaiting_tool_approval, .failed_recoverable, .completed:
            return false
        }
    }

    var recoversToIdleWhenRestored: Bool {
        switch self {
        case .planning, .awaiting_model, .running_tools, .awaiting_hub:
            return true
        case .idle, .awaiting_tool_approval, .failed_recoverable, .completed:
            return false
        }
    }
}
