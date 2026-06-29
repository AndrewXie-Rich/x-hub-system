import Foundation

struct PendingCommand: Equatable, Sendable {
    var reqId: String
    var action: String
    var requestedAt: Double
}

struct SuccessfulLocalLifecycleAction: Equatable, Sendable {
    var action: String
    var finishedAt: Double
}

struct ModelCommandResult: Codable, Equatable, Sendable {
    var type: String
    var reqId: String
    var action: String
    var modelId: String
    var ok: Bool
    var msg: String
    var finishedAt: Double

    enum CodingKeys: String, CodingKey {
        case type
        case reqId = "req_id"
        case action
        case modelId = "model_id"
        case ok
        case msg
        case finishedAt = "finished_at"
    }
}
