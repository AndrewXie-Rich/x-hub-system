import Foundation

struct SupervisorDialogueContinuityFilter {
    struct Decision: Equatable, Sendable {
        var isLowSignal: Bool
        var reasonCode: String

        static func keep(_ reasonCode: String = "meaningful_or_unclassified") -> Self {
            Self(isLowSignal: false, reasonCode: reasonCode)
        }

        static func drop(_ reasonCode: String) -> Self {
            Self(isLowSignal: true, reasonCode: reasonCode)
        }
    }

    private static let lowSignalCanonicalTurns: Set<String> = [
        "hi",
        "hello",
        "hey",
        "yo",
        "ok",
        "okay",
        "kk",
        "okok",
        "roger",
        "thanks",
        "thankyou",
        "helloagain",
        "你好",
        "您好",
        "嗨",
        "哈喽",
        "嗯",
        "嗯嗯",
        "哦",
        "好",
        "好的",
        "收到",
        "收到啦",
        "好的收到",
        "明白",
        "明白了",
        "谢谢",
        "谢了",
    ]

    static func classify(_ message: SupervisorMessage) -> Decision {
        guard message.role == .user || message.role == .assistant else {
            return .keep("non_dialogue_role")
        }

        let trimmed = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .drop("empty")
        }

        let canonical = canonicalKey(for: trimmed)
        guard !canonical.isEmpty else {
            return .drop("symbol_only")
        }

        if lowSignalCanonicalTurns.contains(canonical) {
            return .drop("pure_ack_or_greeting")
        }

        return .keep()
    }

    private static func canonicalKey(for text: String) -> String {
        let folded = text
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: .current
            )
            .lowercased()

        var scalars = String.UnicodeScalarView()
        scalars.reserveCapacity(folded.unicodeScalars.count)
        for scalar in folded.unicodeScalars {
            if scalar.properties.isAlphabetic || scalar.properties.numericType != nil {
                scalars.append(scalar)
            }
        }
        return String(scalars)
    }
}

struct SupervisorDialogueRollingDigestBuilder {
    static func build(
        olderMessages: [SupervisorMessage],
        turnMode: String,
        focusedProjectName: String?,
        focusedProjectId: String?
    ) -> String {
        let eligible = olderMessages.filter { message in
            guard message.role == .user || message.role == .assistant else { return false }
            return !SupervisorDialogueContinuityFilter.classify(message).isLowSignal
        }
        guard !eligible.isEmpty else { return "" }

        let userIntents = orderedUniqueLines(
            eligible.reversed().compactMap { message in
                guard message.role == .user else { return nil }
                return firstNonEmptyLine(in: message.content)
            }
        )
        let assistantCommitments = orderedUniqueLines(
            eligible.reversed().compactMap { message in
                guard message.role == .assistant else { return nil }
                return firstNonEmptyLine(in: message.content)
            }
        )
        let continuityPoints = orderedUniqueLines(
            eligible.reversed().map { message in
                "\(message.role.rawValue) -> \(firstNonEmptyLine(in: message.content))"
            }
        )

        var lines = [
            "source_eligible_messages: \(eligible.count)",
            "source_pairs: \(Int(ceil(Double(eligible.count) / 2.0)))",
            "turn_mode_hint: \(turnMode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "(none)" : turnMode)",
        ]
        if let focusedProjectName {
            let projectId = normalizedLabel(focusedProjectId)
            lines.append("focused_project_hint: \(focusedProjectName) (\(projectId))")
        }

        lines.append("older_user_intent:")
        lines.append(contentsOf: bulletize(userIntents, maxItems: 3))
        lines.append("older_assistant_commitments:")
        lines.append(contentsOf: bulletize(assistantCommitments, maxItems: 3))
        lines.append("continuity_points:")
        lines.append(contentsOf: bulletize(continuityPoints, maxItems: 4))

        return lines.joined(separator: "\n")
    }

    private static func bulletize(_ items: [String], maxItems: Int) -> [String] {
        let selected = Array(items.prefix(maxItems))
        guard !selected.isEmpty else { return ["- (none)"] }
        return selected.map { "- \(truncate($0, maxChars: 140))" }
    }

    private static func orderedUniqueLines(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { continue }
            ordered.append(trimmed)
        }
        return ordered
    }

    private static func firstNonEmptyLine(in text: String) -> String {
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !line.isEmpty {
                return line
            }
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizedLabel(_ value: String?) -> String {
        let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "(none)" : trimmed
    }

    private static func truncate(_ text: String, maxChars: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxChars else { return trimmed }
        let index = trimmed.index(trimmed.startIndex, offsetBy: maxChars)
        return String(trimmed[..<index]) + "..."
    }
}

struct XTSupervisorConversationMirror {
    static let threadKey = "xterminal_supervisor_device"
    static let maxCharsPerMessage = 6_000

    static func requestID(createdAt: Double) -> String {
        "xterminal_supervisor_turn_\(createdAtMs(createdAt))"
    }

    static func createdAtMs(_ createdAt: Double) -> Int64 {
        Int64((createdAt * 1000.0).rounded())
    }

    static func normalizedTurn(
        userText: String,
        assistantText: String
    ) -> (userText: String, assistantText: String)? {
        let normalizedUser = normalizedContent(userText)
        let normalizedAssistant = normalizedContent(assistantText)
        guard !normalizedUser.isEmpty || !normalizedAssistant.isEmpty else {
            return nil
        }
        return (normalizedUser, normalizedAssistant)
    }

    private static func normalizedContent(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if trimmed.count <= maxCharsPerMessage { return trimmed }
        let idx = trimmed.index(trimmed.startIndex, offsetBy: maxCharsPerMessage)
        return String(trimmed[..<idx]) + "\n\n[x-terminal] truncated"
    }
}

struct SupervisorDialogueContinuitySourceSelection {
    var messages: [SupervisorMessage]
    var source: String
}

enum SupervisorDialogueContinuitySourceResolver {
    static func resolve(
        localMessages: [SupervisorMessage],
        remoteWorkingEntries: [String]
    ) -> SupervisorDialogueContinuitySourceSelection {
        let localDialogue = dialogueMessages(from: localMessages)
        let remoteDialogue = remoteMessages(from: remoteWorkingEntries)

        guard !remoteDialogue.isEmpty else {
            return SupervisorDialogueContinuitySourceSelection(
                messages: localDialogue,
                source: "xt_cache"
            )
        }
        guard !localDialogue.isEmpty else {
            return SupervisorDialogueContinuitySourceSelection(
                messages: remoteDialogue,
                source: "hub_thread"
            )
        }

        let remoteFingerprints = remoteDialogue.map(fingerprint)
        let localFingerprints = localDialogue.map(fingerprint)

        let remoteToLocalOverlap = overlapLength(
            suffixBase: remoteFingerprints,
            prefixBase: localFingerprints
        )
        if remoteToLocalOverlap > 0 {
            let merged = remoteDialogue + Array(localDialogue.dropFirst(remoteToLocalOverlap))
            return SupervisorDialogueContinuitySourceSelection(
                messages: merged,
                source: merged.map(fingerprint) == remoteFingerprints ? "hub_thread" : "mixed"
            )
        }

        let localToRemoteOverlap = overlapLength(
            suffixBase: localFingerprints,
            prefixBase: remoteFingerprints
        )
        if localToRemoteOverlap > 0 {
            let merged = localDialogue + Array(remoteDialogue.dropFirst(localToRemoteOverlap))
            return SupervisorDialogueContinuitySourceSelection(
                messages: merged,
                source: merged.map(fingerprint) == remoteFingerprints ? "hub_thread" : "mixed"
            )
        }

        var merged = remoteDialogue
        var seen = Set(remoteFingerprints)
        for message in localDialogue {
            let key = fingerprint(message)
            guard seen.insert(key).inserted else { continue }
            merged.append(message)
        }
        return SupervisorDialogueContinuitySourceSelection(
            messages: merged,
            source: merged.map(fingerprint) == remoteFingerprints ? "hub_thread" : "mixed"
        )
    }

    private static func dialogueMessages(from source: [SupervisorMessage]) -> [SupervisorMessage] {
        source.filter { message in
            guard message.role == .user || message.role == .assistant else { return false }
            return !message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private static func remoteMessages(from entries: [String]) -> [SupervisorMessage] {
        entries.enumerated().compactMap { index, entry in
            let trimmed = entry.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, let separator = trimmed.firstIndex(of: ":") else { return nil }
            let rawRole = String(trimmed[..<separator])
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            let content = String(trimmed[trimmed.index(after: separator)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty else { return nil }

            let role: SupervisorMessage.SupervisorRole
            switch rawRole {
            case SupervisorMessage.SupervisorRole.user.rawValue:
                role = .user
            case SupervisorMessage.SupervisorRole.assistant.rawValue:
                role = .assistant
            default:
                return nil
            }

            return SupervisorMessage(
                id: "hub-thread-\(index)-\(role.rawValue)",
                role: role,
                content: content,
                isVoice: false,
                timestamp: Double(index)
            )
        }
    }

    private static func overlapLength(
        suffixBase: [String],
        prefixBase: [String]
    ) -> Int {
        let limit = min(suffixBase.count, prefixBase.count)
        guard limit > 0 else { return 0 }
        for count in stride(from: limit, through: 1, by: -1) {
            if Array(suffixBase.suffix(count)) == Array(prefixBase.prefix(count)) {
                return count
            }
        }
        return 0
    }

    private static func fingerprint(_ message: SupervisorMessage) -> String {
        let content = message.content
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(message.role.rawValue)|\(content)"
    }
}
