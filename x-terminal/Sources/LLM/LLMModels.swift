import Foundation

struct LLMMessage: Codable, Equatable {
    var role: String
    var content: String
}

struct LLMRequest: Codable, Equatable {
    var role: AXRole
    var messages: [LLMMessage]
    var maxTokens: Int
    var temperature: Double
    var topP: Double

    // Provider hints.
    var taskType: String
    var preferredModelId: String?
    var projectId: String? = nil
    var sessionId: String? = nil
}

struct LLMUsage: Codable, Equatable {
    var promptTokens: Int
    var completionTokens: Int

    var totalTokens: Int {
        max(0, promptTokens + completionTokens)
    }
}

enum LLMStreamEvent: Equatable {
    case delta(String)
    case done(ok: Bool, reason: String, usage: LLMUsage?)
}
