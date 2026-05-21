import Foundation

struct XTProjectConversationTurnMetadata: Codable, Equatable, Sendable {
    static let schemaVersion = "xhub.role_turn_metadata.v1"

    var schemaVersion: String
    var clientMessageId: String
    var sourceRole: String
    var targetRole: String
    var senderRole: String
    var projectId: String
    var rootProjectId: String?
    var threadKey: String
    var dispatchId: String
    var dispatchKind: String
    var runId: String?
    var launchRunId: String?
    var toolCallId: String?
    var reviewerNoteId: String?
    var status: String
    var evidenceRefs: [String]
    var auditRefs: [String]
    var tags: [String]
    var observedAtMs: Int64

    init(
        schemaVersion: String = XTProjectConversationTurnMetadata.schemaVersion,
        clientMessageId: String,
        sourceRole: String,
        targetRole: String,
        senderRole: String? = nil,
        projectId: String,
        rootProjectId: String? = nil,
        threadKey: String,
        dispatchId: String,
        dispatchKind: String,
        runId: String? = nil,
        launchRunId: String? = nil,
        toolCallId: String? = nil,
        reviewerNoteId: String? = nil,
        status: String,
        evidenceRefs: [String] = [],
        auditRefs: [String] = [],
        tags: [String] = [],
        observedAtMs: Int64
    ) {
        self.schemaVersion = schemaVersion
        self.clientMessageId = clientMessageId.trimmingCharacters(in: .whitespacesAndNewlines)
        self.sourceRole = sourceRole.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.targetRole = targetRole.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.senderRole = (senderRole ?? sourceRole).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.projectId = projectId.trimmingCharacters(in: .whitespacesAndNewlines)
        self.rootProjectId = Self.normalizedOptional(rootProjectId)
        self.threadKey = threadKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.dispatchId = dispatchId.trimmingCharacters(in: .whitespacesAndNewlines)
        self.dispatchKind = dispatchKind.trimmingCharacters(in: .whitespacesAndNewlines)
        self.runId = Self.normalizedOptional(runId)
        self.launchRunId = Self.normalizedOptional(launchRunId)
        self.toolCallId = Self.normalizedOptional(toolCallId)
        self.reviewerNoteId = Self.normalizedOptional(reviewerNoteId)
        self.status = status.trimmingCharacters(in: .whitespacesAndNewlines)
        self.evidenceRefs = evidenceRefs.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        self.auditRefs = auditRefs.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        self.tags = tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        self.observedAtMs = observedAtMs
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case clientMessageId = "client_message_id"
        case sourceRole = "source_role"
        case targetRole = "target_role"
        case senderRole = "sender_role"
        case projectId = "project_id"
        case rootProjectId = "root_project_id"
        case threadKey = "thread_key"
        case dispatchId = "dispatch_id"
        case dispatchKind = "dispatch_kind"
        case runId = "run_id"
        case launchRunId = "launch_run_id"
        case toolCallId = "tool_call_id"
        case reviewerNoteId = "reviewer_note_id"
        case status
        case evidenceRefs = "evidence_refs"
        case auditRefs = "audit_refs"
        case tags
        case observedAtMs = "observed_at_ms"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.schemaVersion = try container.decodeIfPresent(String.self, forKey: .schemaVersion) ?? Self.schemaVersion
        self.clientMessageId = try container.decodeIfPresent(String.self, forKey: .clientMessageId) ?? ""
        self.sourceRole = (try container.decodeIfPresent(String.self, forKey: .sourceRole) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        self.targetRole = (try container.decodeIfPresent(String.self, forKey: .targetRole) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        self.senderRole = (try container.decodeIfPresent(String.self, forKey: .senderRole) ?? self.sourceRole)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        self.projectId = (try container.decodeIfPresent(String.self, forKey: .projectId) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.rootProjectId = Self.normalizedOptional(try container.decodeIfPresent(String.self, forKey: .rootProjectId))
        self.threadKey = (try container.decodeIfPresent(String.self, forKey: .threadKey) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.dispatchId = (try container.decodeIfPresent(String.self, forKey: .dispatchId) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.dispatchKind = (try container.decodeIfPresent(String.self, forKey: .dispatchKind) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.runId = Self.normalizedOptional(try container.decodeIfPresent(String.self, forKey: .runId))
        self.launchRunId = Self.normalizedOptional(try container.decodeIfPresent(String.self, forKey: .launchRunId))
        self.toolCallId = Self.normalizedOptional(try container.decodeIfPresent(String.self, forKey: .toolCallId))
        self.reviewerNoteId = Self.normalizedOptional(try container.decodeIfPresent(String.self, forKey: .reviewerNoteId))
        self.status = (try container.decodeIfPresent(String.self, forKey: .status) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.evidenceRefs = (try container.decodeIfPresent([String].self, forKey: .evidenceRefs) ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        self.auditRefs = (try container.decodeIfPresent([String].self, forKey: .auditRefs) ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        self.tags = (try container.decodeIfPresent([String].self, forKey: .tags) ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        self.observedAtMs = Self.decodeInt64(from: container, key: .observedAtMs)
    }

    private static func normalizedOptional(_ value: String?) -> String? {
        let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func decodeInt64(
        from container: KeyedDecodingContainer<CodingKeys>,
        key: CodingKeys
    ) -> Int64 {
        if let value = try? container.decodeIfPresent(Int64.self, forKey: key) {
            return max(0, value)
        }
        if let text = try? container.decodeIfPresent(String.self, forKey: key),
           let value = Int64(text.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return max(0, value)
        }
        return 0
    }
}

struct XTProjectConversationMirrorMessage: Codable, Equatable, Sendable {
    var role: String
    var content: String
    var turnMetadata: XTProjectConversationTurnMetadata?

    init(
        role: String,
        content: String,
        turnMetadata: XTProjectConversationTurnMetadata? = nil
    ) {
        self.role = role
        self.content = content
        self.turnMetadata = turnMetadata
    }

    enum CodingKeys: String, CodingKey {
        case role
        case content
        case turnMetadata = "turn_metadata"
    }
}

enum XTProjectConversationMirror {
    static let maxCharsPerMessage = 6_000

    static func projectThreadKey(projectId: String) -> String {
        let trimmed = projectId.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "xterminal_project_unknown" }
        return "xterminal_project_\(trimmed)"
    }

    static func requestID(projectId: String, createdAt: Double) -> String {
        let compactProjectId = projectId
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "-", with: "")
        let token = compactProjectId.isEmpty ? "unknown" : String(compactProjectId.prefix(12))
        return "xterminal_turn_\(token)_\(createdAtMs(createdAt))"
    }

    static func createdAtMs(_ createdAt: Double) -> Int64 {
        Int64((createdAt * 1000.0).rounded())
    }

    static func fallbackDispatchID(projectId: String, createdAtMs: Int64) -> String {
        AXChatMessageLineageMetadata.makeDispatchId(projectId: projectId, createdAtMs: createdAtMs)
    }

    static func roleEventMessage(
        role: String,
        projectId: String,
        threadKey: String,
        content: String,
        createdAt: Double,
        sourceRole: String,
        targetRole: String,
        dispatchKind: String,
        status: String,
        lineage: AXChatMessageLineageMetadata? = nil,
        dispatchId: String? = nil,
        runId: String? = nil,
        launchRunId: String? = nil,
        toolCallId: String? = nil,
        reviewerNoteId: String? = nil,
        evidenceRefs: [String] = [],
        auditRefs: [String] = [],
        tags: [String] = []
    ) -> XTProjectConversationMirrorMessage? {
        let normalized = normalizedContent(content)
        guard !normalized.isEmpty else { return nil }

        let observedAtMs = createdAtMs(createdAt)
        let resolvedDispatchId = normalizedOptional(dispatchId)
            ?? normalizedOptional(lineage?.dispatchId)
            ?? fallbackDispatchID(projectId: projectId, createdAtMs: observedAtMs)
        let resolvedRunId = normalizedOptional(runId) ?? normalizedOptional(lineage?.runId)
        let resolvedLaunchRunId = normalizedOptional(launchRunId) ?? normalizedOptional(lineage?.launchRunId)
        let metadataTags = ["xt_project_conversation"] + tags

        return XTProjectConversationMirrorMessage(
            role: normalizedWireRole(role),
            content: normalized,
            turnMetadata: XTProjectConversationTurnMetadata(
                clientMessageId: "\(requestID(projectId: projectId, createdAt: createdAt)):\(metadataClientSuffix(sourceRole: sourceRole, dispatchKind: dispatchKind, toolCallId: toolCallId, reviewerNoteId: reviewerNoteId))",
                sourceRole: sourceRole,
                targetRole: targetRole,
                projectId: projectId,
                threadKey: threadKey,
                dispatchId: resolvedDispatchId,
                dispatchKind: dispatchKind,
                runId: resolvedRunId,
                launchRunId: resolvedLaunchRunId,
                toolCallId: toolCallId,
                reviewerNoteId: reviewerNoteId,
                status: status,
                evidenceRefs: evidenceRefs,
                auditRefs: auditRefs,
                tags: metadataTags,
                observedAtMs: observedAtMs
            )
        )
    }

    static func messages(userText: String, assistantText: String) -> [XTProjectConversationMirrorMessage] {
        let candidates: [(String, String)] = [
            ("user", normalizedContent(userText)),
            ("assistant", normalizedContent(assistantText)),
        ]

        return candidates.compactMap { role, content in
            guard !content.isEmpty else { return nil }
            return XTProjectConversationMirrorMessage(role: role, content: content)
        }
    }

    static func roleAwareMessages(
        projectId: String,
        threadKey: String,
        userText: String,
        assistantText: String,
        createdAt: Double,
        userSender: AXChatMessageSender? = nil,
        userLineage: AXChatMessageLineageMetadata? = nil,
        assistantLineage: AXChatMessageLineageMetadata? = nil
    ) -> [XTProjectConversationMirrorMessage] {
        let observedAtMs = createdAtMs(createdAt)
        // TODO: replace fallback with Supervisor launch/run IDs for every dispatch source once all launch paths expose them.
        let fallbackDispatchId = fallbackDispatchID(projectId: projectId, createdAtMs: observedAtMs)
        let thread = threadKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let userSource = normalizedSourceRole(
            sender: userSender,
            text: userText,
            lineage: userLineage
        )
        let userKind = userLineage?.dispatchKind ?? dispatchKindForUserSource(userSource)
        let userTarget = userLineage?.targetRole ?? targetRoleForUserSource(userSource)
        let dispatchId = userLineage?.dispatchId.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? assistantLineage?.dispatchId.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? fallbackDispatchId
        let userStatus = userLineage?.status ?? statusForUserSource(userSource)

        var output: [XTProjectConversationMirrorMessage] = []
        let normalizedUser = normalizedContent(userText)
        if !normalizedUser.isEmpty {
            output.append(
                XTProjectConversationMirrorMessage(
                    role: "user",
                    content: normalizedUser,
                    turnMetadata: metadata(
                        clientMessageId: "\(requestID(projectId: projectId, createdAt: createdAt)):user",
                        sourceRole: userLineage?.sourceRole ?? userSource,
                        targetRole: userTarget,
                        projectId: projectId,
                        threadKey: thread,
                        dispatchId: dispatchId,
                        dispatchKind: userKind,
                        runId: userLineage?.runId,
                        launchRunId: userLineage?.launchRunId,
                        status: userStatus,
                        observedAtMs: userLineage?.createdAtMs ?? observedAtMs
                    )
                )
            )
        }

        let normalizedAssistant = normalizedContent(assistantText)
        if !normalizedAssistant.isEmpty {
            let replyLineage = assistantLineage
                ?? (userLineage?.isSupervisorToCoderDispatch == true
                    ? userLineage?.coderReply(status: "completed")
                    : nil)
            output.append(
                XTProjectConversationMirrorMessage(
                    role: "assistant",
                    content: normalizedAssistant,
                    turnMetadata: metadata(
                        clientMessageId: "\(requestID(projectId: projectId, createdAt: createdAt)):assistant",
                        sourceRole: replyLineage?.sourceRole ?? "coder",
                        targetRole: replyLineage?.targetRole ?? assistantTargetRole(forUserSource: userSource),
                        projectId: projectId,
                        threadKey: thread,
                        dispatchId: replyLineage?.dispatchId ?? dispatchId,
                        dispatchKind: replyLineage?.dispatchKind ?? "coder_reply",
                        runId: replyLineage?.runId ?? userLineage?.runId,
                        launchRunId: replyLineage?.launchRunId ?? userLineage?.launchRunId,
                        status: replyLineage?.status ?? "completed",
                        observedAtMs: replyLineage?.createdAtMs ?? observedAtMs + 1
                    )
                )
            )
        }
        return output
    }

    private static func metadata(
        clientMessageId: String,
        sourceRole: String,
        targetRole: String,
        projectId: String,
        threadKey: String,
        dispatchId: String,
        dispatchKind: String,
        runId: String?,
        launchRunId: String?,
        status: String,
        observedAtMs: Int64
    ) -> XTProjectConversationTurnMetadata {
        XTProjectConversationTurnMetadata(
            clientMessageId: clientMessageId,
            sourceRole: sourceRole,
            targetRole: targetRole,
            projectId: projectId,
            threadKey: threadKey,
            dispatchId: dispatchId,
            dispatchKind: dispatchKind,
            runId: runId,
            launchRunId: launchRunId,
            status: status,
            tags: ["xt_project_conversation"],
            observedAtMs: observedAtMs
        )
    }

    private static func normalizedSourceRole(
        sender: AXChatMessageSender?,
        text: String,
        lineage: AXChatMessageLineageMetadata?
    ) -> String {
        if let source = lineage?.sourceRole.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           !source.isEmpty {
            return source
        }
        if let sender {
            return sender.rawValue
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("来自 Supervisor 的项目执行派发。") {
            return "supervisor"
        }
        if trimmed.lowercased().hasPrefix("reviewer:") {
            return "reviewer"
        }
        return "user"
    }

    private static func dispatchKindForUserSource(_ sourceRole: String) -> String {
        switch sourceRole {
        case "supervisor":
            return "supervisor_to_coder"
        case "reviewer":
            return "reviewer_note"
        default:
            return "user_request"
        }
    }

    private static func targetRoleForUserSource(_ sourceRole: String) -> String {
        switch sourceRole {
        case "supervisor", "reviewer":
            return "coder"
        default:
            return "coder"
        }
    }

    private static func assistantTargetRole(forUserSource sourceRole: String) -> String {
        switch sourceRole {
        case "supervisor":
            return "supervisor"
        case "reviewer":
            return "reviewer"
        default:
            return "user"
        }
    }

    private static func statusForUserSource(_ sourceRole: String) -> String {
        switch sourceRole {
        case "supervisor":
            return "dispatched"
        default:
            return "observed"
        }
    }

    private static func normalizedContent(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if trimmed.count <= maxCharsPerMessage { return trimmed }
        let idx = trimmed.index(trimmed.startIndex, offsetBy: maxCharsPerMessage)
        return String(trimmed[..<idx]) + "\n\n[x-terminal] truncated"
    }

    private static func normalizedWireRole(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.isEmpty ? "system" : trimmed
    }

    private static func normalizedOptional(_ value: String?) -> String? {
        let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func metadataClientSuffix(
        sourceRole: String,
        dispatchKind: String,
        toolCallId: String?,
        reviewerNoteId: String?
    ) -> String {
        let parts = [
            sourceRole,
            dispatchKind,
            normalizedOptional(toolCallId),
            normalizedOptional(reviewerNoteId)
        ].compactMap { $0 }
        let raw = parts.joined(separator: ":")
        let safe = raw.unicodeScalars.map { scalar -> String in
            CharacterSet.alphanumerics.contains(scalar) ? String(scalar) : "_"
        }.joined()
        let compact = safe
            .split(separator: "_", omittingEmptySubsequences: true)
            .joined(separator: "_")
        return compact.isEmpty ? "event" : compact
    }
}
