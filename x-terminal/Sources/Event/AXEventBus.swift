import Foundation
import Combine

@MainActor
final class AXEventBus: ObservableObject {
    static let shared = AXEventBus()
    
    private let eventSubject = PassthroughSubject<AXEvent, Never>()
    var eventPublisher: AnyPublisher<AXEvent, Never> {
        eventSubject.eraseToAnyPublisher()
    }
    
    private init() {}
    
    func publish(_ event: AXEvent) {
        eventSubject.send(event)
    }
}

enum AXEvent: Equatable {
    case projectCreated(AXProjectEntry)
    case projectUpdated(AXProjectEntry)
    case projectRemoved(AXProjectEntry)

    case sessionCreated(AXSessionInfo)
    case sessionUpdated(AXSessionInfo)
    case sessionDeleted(String)
    case sessionDiff(String, [AXFileDiff])
    case sessionError(String, AXError)
    
    case messageCreated(String, AXChatMessage)
    case messageUpdated(String, AXChatMessage)
    case messageDeleted(String, String)
    
    case toolCallCreated(String, ToolCall)
    case toolCallUpdated(String, ToolCall)
    case toolCallDeleted(String, String)

    // Supervisor lane incident stream (XT-W2-14)
    case supervisorIncident(SupervisorLaneIncident)
    // Supervisor lane health stream (XT-W2-13)
    case supervisorLaneHealth(SupervisorLaneHealthSnapshot)
    // Completion adapter machine event stream (XT-W2-26-A)
    case supervisorLaneCompletionDetected(SupervisorLaneCompletionDetectedEvent)
}

struct SupervisorLaneCompletionDetectedEvent: Codable, Equatable, Sendable {
    let eventType: String
    let laneID: String
    let taskID: UUID
    let projectID: UUID
    let completionSource: String
    let completionEpoch: Int64
    let detectedAtMs: Int64
    let confidence: Double

    enum CodingKeys: String, CodingKey {
        case eventType = "event_type"
        case laneID = "lane_id"
        case taskID = "task_id"
        case projectID = "project_id"
        case completionSource = "completion_source"
        case completionEpoch = "completion_epoch"
        case detectedAtMs = "detected_at_ms"
        case confidence
    }
}

struct AXSessionInfo: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var projectId: String
    var title: String
    var directory: String
    var parentId: String?
    var createdAt: Double
    var updatedAt: Double
    var version: String
    var summary: AXSessionSummary?
    var runtime: AXSessionRuntimeSnapshot? = nil
}

struct AXSessionSummary: Codable, Equatable, Sendable {
    var additions: Int
    var deletions: Int
    var files: Int
    var diffs: [AXFileDiff]?
}

struct AXFileDiff: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var path: String
    var additions: Int
    var deletions: Int
    var patch: String?
}

struct AXError: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var type: String
    var message: String
    var timestamp: Double
    var details: [String: String]?
}
