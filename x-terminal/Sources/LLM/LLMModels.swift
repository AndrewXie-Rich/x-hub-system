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
    var transportOverride: HubTransportMode? = nil
}

struct LLMUsage: Codable, Equatable {
    var promptTokens: Int
    var completionTokens: Int
    var requestedModelId: String?
    var actualModelId: String?
    var runtimeProvider: String?
    var executionPath: String?
    var fallbackReasonCode: String?

    init(
        promptTokens: Int,
        completionTokens: Int,
        requestedModelId: String? = nil,
        actualModelId: String? = nil,
        runtimeProvider: String? = nil,
        executionPath: String? = nil,
        fallbackReasonCode: String? = nil
    ) {
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.requestedModelId = requestedModelId
        self.actualModelId = actualModelId
        self.runtimeProvider = runtimeProvider
        self.executionPath = executionPath
        self.fallbackReasonCode = fallbackReasonCode
    }

    var totalTokens: Int {
        max(0, promptTokens + completionTokens)
    }
}

enum LLMStreamEvent: Equatable {
    case delta(String)
    case done(ok: Bool, reason: String, usage: LLMUsage?)
}
