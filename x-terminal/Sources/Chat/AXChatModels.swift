import Foundation

enum AXChatRole: String, Codable {
    case user
    case assistant
    case tool
}

struct AXChatAttachment: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var displayName: String
    var path: String
    var relativePath: String?
    var kind: AXChatAttachmentKind
    var scope: AXChatAttachmentScope
    var sizeBytes: Int64?
    var addedAt: Double

    init(
        id: String = UUID().uuidString,
        displayName: String,
        path: String,
        relativePath: String? = nil,
        kind: AXChatAttachmentKind,
        scope: AXChatAttachmentScope,
        sizeBytes: Int64? = nil,
        addedAt: Double = Date().timeIntervalSince1970
    ) {
        self.id = id
        self.displayName = displayName
        self.path = path
        self.relativePath = relativePath
        self.kind = kind
        self.scope = scope
        self.sizeBytes = sizeBytes
        self.addedAt = addedAt
    }
}

struct AXChatMessage: Identifiable, Codable, Equatable {
    var id: String
    var role: AXChatRole
    var tag: String?
    var content: String
    var createdAt: Double
    var attachments: [AXChatAttachment]

    init(
        role: AXChatRole,
        tag: String? = nil,
        content: String,
        createdAt: Double = Date().timeIntervalSince1970,
        attachments: [AXChatAttachment] = []
    ) {
        self.id = UUID().uuidString
        self.role = role
        self.tag = tag
        self.content = content
        self.createdAt = createdAt
        self.attachments = attachments
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        role = try container.decode(AXChatRole.self, forKey: .role)
        tag = try container.decodeIfPresent(String.self, forKey: .tag)
        content = try container.decode(String.self, forKey: .content)
        createdAt = try container.decode(Double.self, forKey: .createdAt)
        attachments = try container.decodeIfPresent([AXChatAttachment].self, forKey: .attachments) ?? []
    }

    enum CodingKeys: String, CodingKey {
        case id
        case role
        case tag
        case content
        case createdAt
        case attachments
    }
}
