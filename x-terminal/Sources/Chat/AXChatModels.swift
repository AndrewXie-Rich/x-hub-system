import Foundation

enum AXChatRole: String, Codable {
    case user
    case assistant
    case tool
}

struct AXChatMessage: Identifiable, Codable, Equatable {
    var id: String
    var role: AXChatRole
    var tag: String?
    var content: String
    var createdAt: Double

    init(role: AXChatRole, tag: String? = nil, content: String, createdAt: Double = Date().timeIntervalSince1970) {
        self.id = UUID().uuidString
        self.role = role
        self.tag = tag
        self.content = content
        self.createdAt = createdAt
    }
}
