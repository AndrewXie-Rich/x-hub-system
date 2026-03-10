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
}

struct AXSessionInfo: Identifiable, Codable, Equatable {
    var id: String
    var projectId: String
    var title: String
    var directory: String
    var parentId: String?
    var createdAt: Double
    var updatedAt: Double
    var version: String
    var summary: AXSessionSummary?
}

struct AXSessionSummary: Codable, Equatable {
    var additions: Int
    var deletions: Int
    var files: Int
    var diffs: [AXFileDiff]?
}

struct AXFileDiff: Identifiable, Codable, Equatable {
    var id: String
    var path: String
    var additions: Int
    var deletions: Int
    var patch: String?
}

struct AXError: Identifiable, Codable, Equatable {
    var id: String
    var type: String
    var message: String
    var timestamp: Double
    var details: [String: String]?
}
