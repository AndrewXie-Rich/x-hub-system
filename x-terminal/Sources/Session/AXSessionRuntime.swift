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
}
