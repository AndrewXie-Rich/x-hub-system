import Foundation

enum AXChatRole: String, Codable {
    case user
    case assistant
    case tool
}

enum AXChatMessageSender: String, Codable {
    case user
    case supervisor
    case coder
    case reviewer
}

struct AXChatMessageLineageMetadata: Codable, Equatable {
    var schemaVersion: String
    var dispatchId: String
    var sourceRole: String
    var targetRole: String
    var dispatchKind: String
    var projectId: String?
    var runId: String?
    var launchRunId: String?
    var status: String
    var createdAtMs: Int64

    init(
        schemaVersion: String = "xt.chat.dispatch_lineage.v1",
        dispatchId: String,
        sourceRole: String,
        targetRole: String,
        dispatchKind: String,
        projectId: String? = nil,
        runId: String? = nil,
        launchRunId: String? = nil,
        status: String,
        createdAtMs: Int64 = Int64((Date().timeIntervalSince1970 * 1000.0).rounded())
    ) {
        self.schemaVersion = schemaVersion
        self.dispatchId = dispatchId.trimmingCharacters(in: .whitespacesAndNewlines)
        self.sourceRole = sourceRole.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.targetRole = targetRole.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.dispatchKind = dispatchKind.trimmingCharacters(in: .whitespacesAndNewlines)
        self.projectId = Self.normalizedOptional(projectId)
        self.runId = Self.normalizedOptional(runId)
        self.launchRunId = Self.normalizedOptional(launchRunId)
        self.status = status.trimmingCharacters(in: .whitespacesAndNewlines)
        self.createdAtMs = createdAtMs
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case dispatchId = "dispatch_id"
        case sourceRole = "source_role"
        case targetRole = "target_role"
        case dispatchKind = "dispatch_kind"
        case projectId = "project_id"
        case runId = "run_id"
        case launchRunId = "launch_run_id"
        case status
        case createdAtMs = "created_at_ms"
    }

    var isSupervisorToCoderDispatch: Bool {
        sourceRole == "supervisor"
            && targetRole == "coder"
            && dispatchKind == "supervisor_to_coder"
    }

    func withStatus(_ status: String) -> AXChatMessageLineageMetadata {
        var updated = self
        updated.status = status.trimmingCharacters(in: .whitespacesAndNewlines)
        return updated
    }

    func coderReply(status: String = "running") -> AXChatMessageLineageMetadata {
        AXChatMessageLineageMetadata(
            dispatchId: dispatchId,
            sourceRole: "coder",
            targetRole: "supervisor",
            dispatchKind: "coder_reply",
            projectId: projectId,
            runId: runId,
            launchRunId: launchRunId,
            status: status,
            createdAtMs: Int64((Date().timeIntervalSince1970 * 1000.0).rounded())
        )
    }

    static func makeDispatchId(projectId: String, createdAtMs: Int64 = Int64((Date().timeIntervalSince1970 * 1000.0).rounded())) -> String {
        let prefix = normalizedIdentifierFragment(projectId)
        return "xt_dispatch_\(prefix)_\(createdAtMs)"
    }

    static func makeDispatchId(
        projectId: String,
        runId: String?,
        launchRunId: String?,
        createdAtMs: Int64 = Int64((Date().timeIntervalSince1970 * 1000.0).rounded())
    ) -> String {
        let run = normalizedOptionalIdentifierFragment(runId)
        let launchRun = normalizedOptionalIdentifierFragment(launchRunId)
        guard run != nil || launchRun != nil else {
            return makeDispatchId(projectId: projectId, createdAtMs: createdAtMs)
        }

        let project = normalizedIdentifierFragment(projectId)
        if let run, let launchRun {
            return "xt_dispatch_\(project)_\(run)_\(launchRun)"
        }
        if let run {
            return "xt_dispatch_\(project)_\(run)"
        }
        guard let launchRun else {
            return makeDispatchId(projectId: projectId, createdAtMs: createdAtMs)
        }
        return "xt_dispatch_\(project)_\(launchRun)"
    }

    private static func normalizedOptional(_ value: String?) -> String? {
        let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func normalizedIdentifierFragment(_ value: String) -> String {
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let text = normalized.unicodeScalars.map { scalar -> String in
            CharacterSet.alphanumerics.contains(scalar) ? String(scalar) : "_"
        }.joined()
        let compact = text
            .split(separator: "_", omittingEmptySubsequences: true)
            .joined(separator: "_")
        return String((compact.isEmpty ? "project" : compact).prefix(24))
    }

    private static func normalizedOptionalIdentifierFragment(_ value: String?) -> String? {
        let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return normalizedIdentifierFragment(trimmed)
    }
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
    var sender: AXChatMessageSender?
    var tag: String?
    var content: String
    var createdAt: Double
    var attachments: [AXChatAttachment]
    var lineage: AXChatMessageLineageMetadata?

    init(
        role: AXChatRole,
        sender: AXChatMessageSender? = nil,
        tag: String? = nil,
        content: String,
        createdAt: Double = Date().timeIntervalSince1970,
        attachments: [AXChatAttachment] = [],
        lineage: AXChatMessageLineageMetadata? = nil
    ) {
        self.id = UUID().uuidString
        self.role = role
        self.sender = sender
        self.tag = tag
        self.content = content
        self.createdAt = createdAt
        self.attachments = attachments
        self.lineage = lineage
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        role = try container.decode(AXChatRole.self, forKey: .role)
        sender = try container.decodeIfPresent(AXChatMessageSender.self, forKey: .sender)
        tag = try container.decodeIfPresent(String.self, forKey: .tag)
        content = try container.decode(String.self, forKey: .content)
        createdAt = try container.decode(Double.self, forKey: .createdAt)
        attachments = try container.decodeIfPresent([AXChatAttachment].self, forKey: .attachments) ?? []
        lineage = try container.decodeIfPresent(AXChatMessageLineageMetadata.self, forKey: .lineage)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case role
        case sender
        case tag
        case content
        case createdAt
        case attachments
        case lineage
    }
}

extension AXChatMessage {
    var isSupervisorDispatch: Bool {
        lineage?.isSupervisorToCoderDispatch == true
            || sender == .supervisor
            || content.trimmingCharacters(in: .whitespacesAndNewlines)
                .hasPrefix("来自 Supervisor 的项目执行派发。")
    }
}
