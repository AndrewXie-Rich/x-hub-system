import Foundation

struct XTProjectTranscriptLine: Equatable {
    var role: String
    var content: String
    var createdAt: Double
    var messageId: String
    var dispatchId: String?
    var sourceRole: String?
    var targetRole: String?
    var dispatchKind: String?
    var status: String?
}

struct XTProjectTranscriptProjection: Equatable {
    var source: String
    var projectId: String
    var projectName: String
    var status: String
    var pendingToolCallCount: Int
    var isSending: Bool
    var lastError: String
    var latestSupervisorDispatch: XTProjectTranscriptLine?
    var latestCoderReply: XTProjectTranscriptLine?
    var latestReviewerNote: XTProjectTranscriptLine?
    var latestToolApproval: XTProjectTranscriptLine?
    var latestToolApprovalDecision: XTProjectTranscriptLine?
    var latestToolResult: XTProjectTranscriptLine?
    var latestHeartbeat: XTProjectTranscriptLine?
    var latestDispatchId: String?
    var latestDispatchStatus: String?
    var recentLines: [XTProjectTranscriptLine]

    var hasUsefulContent: Bool {
        latestSupervisorDispatch != nil
            || latestCoderReply != nil
            || latestReviewerNote != nil
            || latestToolApproval != nil
            || latestToolApprovalDecision != nil
            || latestToolResult != nil
            || latestHeartbeat != nil
            || !recentLines.isEmpty
    }

    func promptBlock(maxRecentLines: Int = 8, maxLineChars: Int = 220) -> String {
        guard hasUsefulContent else { return "" }
        let truthBoundary: String = source == "hub_role_turn_metadata_projection"
            ? "Hub role-turn metadata projection; XT local sender/text inference is fallback only."
            : "XT local project chat runtime projection only; Hub remains authority for durable memory, skills, grants, model route, quota, kill-switch, and audit."
        var lines = [
            "[project_transcript_observation]",
            "source=\(source)",
            "truth_boundary=\(truthBoundary)",
            "project=\(projectName) (\(projectId))",
            "status=\(status)",
            "pending_tool_calls=\(pendingToolCallCount)",
            "is_sending=\(isSending ? "true" : "false")"
        ]
        if !lastError.isEmpty {
            lines.append("last_error=\(Self.capped(lastError, maxChars: maxLineChars))")
        }
        if let latestDispatchId, !latestDispatchId.isEmpty {
            lines.append("latest_dispatch_id=\(latestDispatchId)")
        }
        if let latestDispatchStatus, !latestDispatchStatus.isEmpty {
            lines.append("latest_dispatch_status=\(latestDispatchStatus)")
        }
        if let latestSupervisorDispatch {
            lines.append("latest_supervisor_dispatch=\(Self.capped(latestSupervisorDispatch.content, maxChars: maxLineChars))")
        }
        if let latestCoderReply {
            lines.append("latest_coder_reply=\(Self.capped(latestCoderReply.content, maxChars: maxLineChars))")
        }
        if let latestReviewerNote {
            lines.append("latest_reviewer_note=\(Self.capped(latestReviewerNote.content, maxChars: maxLineChars))")
        }
        if let latestToolApproval {
            lines.append("latest_tool_approval=\(Self.capped(latestToolApproval.content, maxChars: maxLineChars))")
        }
        if let latestToolApprovalDecision {
            lines.append("latest_tool_approval_decision=\(Self.capped(latestToolApprovalDecision.content, maxChars: maxLineChars))")
        }
        if let latestToolResult {
            lines.append("latest_tool_result=\(Self.capped(latestToolResult.content, maxChars: maxLineChars))")
        }
        if let latestHeartbeat {
            lines.append("latest_heartbeat=\(Self.capped(latestHeartbeat.content, maxChars: maxLineChars))")
        }
        let recent = recentLines.suffix(maxRecentLines)
        if !recent.isEmpty {
            lines.append("recent_role_lines:")
            lines.append(contentsOf: recent.map { line in
                Self.promptLine(line, maxLineChars: maxLineChars)
            })
        }
        lines.append("[/project_transcript_observation]")
        return lines.joined(separator: "\n")
    }

    static func build(
        projectId: String,
        projectName: String,
        messages: [AXChatMessage],
        pendingToolCallCount: Int = 0,
        isSending: Bool = false,
        lastError: String? = nil,
        maxRecentLines: Int = 12
    ) -> XTProjectTranscriptProjection {
        let normalizedLines = messages.compactMap(normalizedLine)
        return makeProjection(
            source: "xt_project_chat_runtime_projection",
            projectId: projectId,
            projectName: projectName,
            normalizedLines: normalizedLines,
            pendingToolCallCount: pendingToolCallCount,
            isSending: isSending,
            lastError: lastError,
            maxRecentLines: maxRecentLines
        )
    }

    static func build(
        projectId: String,
        projectName: String,
        hubMessages: [XTProjectConversationMirrorMessage],
        pendingToolCallCount: Int = 0,
        isSending: Bool = false,
        lastError: String? = nil,
        maxRecentLines: Int = 12
    ) -> XTProjectTranscriptProjection {
        let normalizedLines = hubMessages.enumerated().compactMap { index, message in
            normalizedHubLine(message, index: index)
        }
        return makeProjection(
            source: "hub_role_turn_metadata_projection",
            projectId: projectId,
            projectName: projectName,
            normalizedLines: normalizedLines,
            pendingToolCallCount: pendingToolCallCount,
            isSending: isSending,
            lastError: lastError,
            maxRecentLines: maxRecentLines
        )
    }

    private static func makeProjection(
        source: String,
        projectId: String,
        projectName: String,
        normalizedLines: [XTProjectTranscriptLine],
        pendingToolCallCount: Int,
        isSending: Bool,
        lastError: String?,
        maxRecentLines: Int
    ) -> XTProjectTranscriptProjection {
        let latestSupervisorDispatch = normalizedLines.last {
            $0.dispatchKind == "supervisor_to_coder"
        } ?? normalizedLines.last {
            $0.role == "supervisor"
                && $0.content.hasPrefix("来自 Supervisor 的项目执行派发。")
        } ?? normalizedLines.last { $0.role == "supervisor" }
        let latestCoderReply = normalizedLines.last { $0.role == "coder" }
        let latestReviewerNote = normalizedLines.last { $0.role == "reviewer" }
        let latestToolApproval = normalizedLines.last {
            $0.dispatchKind == "tool_approval"
                || ($0.role == "tool" && $0.status == "awaiting_authorization")
        }
        let latestToolApprovalDecision = normalizedLines.last {
            $0.dispatchKind == "tool_approval_decision"
        }
        let latestToolResult = normalizedLines.last {
            $0.dispatchKind == "tool_result"
        }
        let latestHeartbeat = normalizedLines.last { $0.dispatchKind == "heartbeat" }
        let latestToolTerminalEvent = [latestToolApprovalDecision, latestToolResult]
            .compactMap { $0 }
            .max { $0.createdAt < $1.createdAt }
        let toolApprovalStillOpen = latestToolApproval?.status == "awaiting_authorization"
            && (latestToolTerminalEvent == nil
                || (latestToolApproval?.createdAt ?? 0) > (latestToolTerminalEvent?.createdAt ?? 0))
        let dispatchCandidates: [String?] = [
            latestSupervisorDispatch?.dispatchId,
            latestCoderReply?.dispatchId,
            latestReviewerNote?.dispatchId,
            latestToolApproval?.dispatchId,
            latestToolApprovalDecision?.dispatchId,
            latestToolResult?.dispatchId,
            latestHeartbeat?.dispatchId
        ]
        let latestDispatchId = dispatchCandidates.first { candidate in
            !(candidate ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } ?? nil
        let latestDispatchStatus = normalizedLines
            .last {
                guard let latestDispatchId, !latestDispatchId.isEmpty else { return false }
                return $0.dispatchId == latestDispatchId
                    && $0.dispatchKind != "heartbeat"
                    && !($0.status ?? "").isEmpty
            }?
            .status ?? normalizedLines
            .last {
                guard let latestDispatchId, !latestDispatchId.isEmpty else { return false }
                return $0.dispatchId == latestDispatchId
                    && !($0.status ?? "").isEmpty
            }?
            .status
        let trimmedError = (lastError ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let status: String
        if pendingToolCallCount > 0 {
            status = "awaiting_authorization"
        } else if toolApprovalStillOpen {
            status = "awaiting_authorization"
        } else if latestToolResult?.status == "failed" {
            status = "failed"
        } else if latestDispatchStatus == "awaiting_authorization" {
            status = "awaiting_authorization"
        } else if !trimmedError.isEmpty {
            status = "failed"
        } else if isSending {
            status = "running"
        } else if latestDispatchStatus == "failed" {
            status = "failed"
        } else if latestDispatchStatus == "running" {
            status = "running"
        } else if latestCoderReply != nil {
            status = "latest_coder_reply_observed"
        } else if latestToolResult != nil {
            status = "tool_result_observed"
        } else if latestSupervisorDispatch != nil {
            status = "dispatch_observed"
        } else {
            status = "observed"
        }

        return XTProjectTranscriptProjection(
            source: source,
            projectId: projectId.trimmingCharacters(in: .whitespacesAndNewlines),
            projectName: projectName.trimmingCharacters(in: .whitespacesAndNewlines),
            status: status,
            pendingToolCallCount: pendingToolCallCount,
            isSending: isSending,
            lastError: trimmedError,
            latestSupervisorDispatch: latestSupervisorDispatch,
            latestCoderReply: latestCoderReply,
            latestReviewerNote: latestReviewerNote,
            latestToolApproval: latestToolApproval,
            latestToolApprovalDecision: latestToolApprovalDecision,
            latestToolResult: latestToolResult,
            latestHeartbeat: latestHeartbeat,
            latestDispatchId: latestDispatchId,
            latestDispatchStatus: latestDispatchStatus,
            recentLines: Array(normalizedLines.suffix(maxRecentLines))
        )
    }

    private static func normalizedLine(_ message: AXChatMessage) -> XTProjectTranscriptLine? {
        let content = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return nil }
        return XTProjectTranscriptLine(
            role: projectedRole(for: message),
            content: content,
            createdAt: message.createdAt,
            messageId: message.id,
            dispatchId: message.lineage?.dispatchId,
            sourceRole: message.lineage?.sourceRole,
            targetRole: message.lineage?.targetRole,
            dispatchKind: message.lineage?.dispatchKind,
            status: message.lineage?.status
        )
    }

    private static func normalizedHubLine(
        _ message: XTProjectConversationMirrorMessage,
        index: Int
    ) -> XTProjectTranscriptLine? {
        let content = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return nil }
        let metadata = message.turnMetadata
        let sourceRole = normalizedOptional(metadata?.sourceRole)
        return XTProjectTranscriptLine(
            role: sourceRole ?? fallbackHubRole(message.role),
            content: content,
            createdAt: Double(metadata?.observedAtMs ?? 0) / 1000.0,
            messageId: normalizedOptional(metadata?.clientMessageId) ?? "hub_role_turn_\(index)",
            dispatchId: normalizedOptional(metadata?.dispatchId),
            sourceRole: sourceRole,
            targetRole: normalizedOptional(metadata?.targetRole),
            dispatchKind: normalizedOptional(metadata?.dispatchKind),
            status: normalizedOptional(metadata?.status)
        )
    }

    private static func projectedRole(for message: AXChatMessage) -> String {
        if let sourceRole = message.lineage?.sourceRole,
           !sourceRole.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return sourceRole
        }
        switch message.role {
        case .tool:
            return "tool"
        case .assistant:
            switch message.sender {
            case .supervisor:
                return "supervisor"
            case .reviewer:
                return "reviewer"
            case .user:
                return "user"
            case .coder, nil:
                return "coder"
            }
        case .user:
            if message.isSupervisorDispatch {
                return "supervisor"
            }
            switch message.sender {
            case .supervisor:
                return "supervisor"
            case .coder:
                return "coder"
            case .reviewer:
                return "reviewer"
            case .user, nil:
                return "user"
            }
        }
    }

    private static func capped(_ text: String, maxChars: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxChars else { return trimmed }
        let idx = trimmed.index(trimmed.startIndex, offsetBy: maxChars)
        return String(trimmed[..<idx]) + "..."
    }

    private static func normalizedOptional(_ value: String?) -> String? {
        let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func fallbackHubRole(_ role: String) -> String {
        switch role.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "assistant":
            return "coder"
        case "user", "tool", "system":
            return role.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        default:
            return "user"
        }
    }

    private static func promptLine(_ line: XTProjectTranscriptLine, maxLineChars: Int) -> String {
        let lineageParts = [
            line.dispatchId.map { "dispatch_id=\($0)" },
            line.dispatchKind.map { "kind=\($0)" },
            line.status.map { "status=\($0)" }
        ].compactMap { $0 }
        let lineageSuffix = lineageParts.isEmpty ? "" : " [\(lineageParts.joined(separator: " "))]"
        return "- \(line.role)\(lineageSuffix): \(capped(line.content, maxChars: maxLineChars))"
    }
}
