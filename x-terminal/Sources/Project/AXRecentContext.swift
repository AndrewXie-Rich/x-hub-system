import Dispatch
import Foundation

struct AXRecentContextMessage: Codable, Equatable {
    var role: String // "user" | "assistant"
    var content: String
    var createdAt: Double
    var attachments: [AXChatAttachment]

    init(
        role: String,
        content: String,
        createdAt: Double,
        attachments: [AXChatAttachment] = []
    ) {
        self.role = role
        self.content = content
        self.createdAt = createdAt
        self.attachments = attachments
    }

    enum CodingKeys: String, CodingKey {
        case role
        case content
        case createdAt
        case attachments
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        role = try container.decode(String.self, forKey: .role)
        content = try container.decode(String.self, forKey: .content)
        createdAt = try container.decode(Double.self, forKey: .createdAt)
        attachments = try container.decodeIfPresent([AXChatAttachment].self, forKey: .attachments) ?? []
    }
}

struct AXRecentContext: Codable, Equatable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var updatedAt: Double
    var messages: [AXRecentContextMessage]

    static func empty() -> AXRecentContext {
        AXRecentContext(
            schemaVersion: currentSchemaVersion,
            updatedAt: Date().timeIntervalSince1970,
            messages: []
        )
    }
}

// Short-term, crash-resilient context buffer.
// Purpose: provide the last few turns without reading large raw_log or relying on in-memory UI state.
enum AXRecentContextStore {
    private static let queue = DispatchQueue(label: "xterminal.recent_context_store")
    private static let maxMessages = 40 // ~20 turns
    private static let maxCharsPerMessage = 6_000
    private static let bootstrapMaxBytesCap: Int64 = 8 * 1024 * 1024 // 8MB tail cap

    static func jsonURL(for ctx: AXProjectContext) -> URL {
        ctx.xterminalDir.appendingPathComponent("recent_context.json")
    }

    static func markdownURL(for ctx: AXProjectContext) -> URL {
        ctx.xterminalDir.appendingPathComponent("AX_RECENT.md")
    }

    static func load(for ctx: AXProjectContext) -> AXRecentContext {
        queue.sync {
            loadUnlocked(for: ctx)
        }
    }

    // One-time bootstrap for older projects: if recent_context is missing/empty, seed it from raw_log tail.
    // This keeps prompt assembly fast and crash-resilient without loading large raw_log every time.
    static func bootstrapFromRawLogIfNeeded(ctx: AXProjectContext, maxTurns: Int = 12) {
        guard maxTurns > 0 else { return }
        queue.sync {
            let cur = loadUnlocked(for: ctx)

            // Ensure on-disk placeholders exist so handoff logic can rely on stable paths.
            // If there is no raw_log yet, these files will remain "(none)" but won't be missing.
            let jsonExists = FileManager.default.fileExists(atPath: jsonURL(for: ctx).path)
            let mdExists = FileManager.default.fileExists(atPath: markdownURL(for: ctx).path)
            if !jsonExists || !mdExists {
                saveUnlocked(cur, for: ctx)
            }

            if !cur.messages.isEmpty { return }

            let seeded = seedMessagesFromRawLogTail(ctx: ctx, maxTurns: maxTurns)
            if seeded.isEmpty { return }
            overwriteUnlocked(ctx: ctx, messages: seeded)
        }
    }

    static func appendUserMessage(
        ctx: AXProjectContext,
        text: String,
        createdAt: Double,
        attachments: [AXChatAttachment] = []
    ) {
        appendMessage(
            ctx: ctx,
            role: "user",
            text: text,
            createdAt: createdAt,
            attachments: attachments
        )
    }

    static func appendAssistantMessage(ctx: AXProjectContext, text: String, createdAt: Double) {
        appendMessage(ctx: ctx, role: "assistant", text: text, createdAt: createdAt)
    }

    static func removeTrailingMessage(ctx: AXProjectContext, role: String, text: String) {
        let normalizedText = comparableMessageText(text)
        guard !normalizedText.isEmpty else { return }

        queue.sync {
            var cur = loadUnlocked(for: ctx)
            guard let last = cur.messages.last,
                  last.role == role,
                  comparableMessageText(last.content) == normalizedText else {
                return
            }
            cur.messages.removeLast()
            cur.updatedAt = Date().timeIntervalSince1970
            saveUnlocked(cur, for: ctx)
        }
    }

    private static func appendMessage(
        ctx: AXProjectContext,
        role: String,
        text: String,
        createdAt: Double,
        attachments: [AXChatAttachment] = []
    ) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return }

        queue.sync {
            var cur = loadUnlocked(for: ctx)

            let cleaned = truncateInline(trimmed, max: maxCharsPerMessage)
            // Avoid duplicating exact consecutive messages.
            if let last = cur.messages.last,
               last.role == role,
               last.content.trimmingCharacters(in: .whitespacesAndNewlines) == cleaned,
               last.attachments == attachments {
                cur.updatedAt = Date().timeIntervalSince1970
                saveUnlocked(cur, for: ctx)
                return
            }

            cur.messages.append(
                AXRecentContextMessage(
                    role: role,
                    content: cleaned,
                    createdAt: createdAt,
                    attachments: attachments
                )
            )
            if cur.messages.count > maxMessages {
                cur.messages = Array(cur.messages.suffix(maxMessages))
            }
            cur.updatedAt = Date().timeIntervalSince1970
            saveUnlocked(cur, for: ctx)
        }
    }

    // MARK: - IO

    private static func loadUnlocked(for ctx: AXProjectContext) -> AXRecentContext {
        let url = jsonURL(for: ctx)
        guard FileManager.default.fileExists(atPath: url.path) else { return .empty() }
        guard let data = try? Data(contentsOf: url) else { return .empty() }
        return (try? JSONDecoder().decode(AXRecentContext.self, from: data)) ?? .empty()
    }

    private static func saveUnlocked(_ ctxObj: AXRecentContext, for ctx: AXProjectContext) {
        try? ctx.ensureDirs()
        var cur = ctxObj
        cur.schemaVersion = AXRecentContext.currentSchemaVersion
        cur.updatedAt = Date().timeIntervalSince1970

        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(cur) {
            try? XTStoreWriteSupport.writeSnapshotData(data, to: jsonURL(for: ctx))
        }

        let md = renderMarkdown(cur)
        if let markdownData = md.data(using: .utf8) {
            try? XTStoreWriteSupport.writeSnapshotData(markdownData, to: markdownURL(for: ctx))
        }
    }

    private static func overwriteUnlocked(ctx: AXProjectContext, messages: [AXRecentContextMessage]) {
        var cur = AXRecentContext.empty()
        cur.messages = Array(messages.suffix(maxMessages))
        cur.updatedAt = Date().timeIntervalSince1970
        saveUnlocked(cur, for: ctx)
    }

    private static func renderMarkdown(_ recent: AXRecentContext) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let updated = f.string(from: Date(timeIntervalSince1970: recent.updatedAt))

        var out: [String] = []
        out.append("# AX Recent Context")
        out.append("")
        out.append("- updatedAt: \(updated)")
        out.append("- maxMessages: \(maxMessages)")
        out.append("")
        out.append("## Messages (most recent last)")
        if recent.messages.isEmpty {
            out.append("- (none)")
            return out.joined(separator: "\n")
        }

        func roleLabel(_ r: String) -> String {
            if r == "user" { return "user" }
            if r == "assistant" { return "assistant" }
            return r
        }

        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone.current
        df.dateFormat = "MM-dd HH:mm:ss"

        for m in recent.messages {
            let ts = df.string(from: Date(timeIntervalSince1970: m.createdAt))
            out.append("- \(ts) \(roleLabel(m.role))：\(m.content)")
            if !m.attachments.isEmpty {
                let attachments = m.attachments.map(\.displayPath).joined(separator: ", ")
                out.append("  attachments: \(attachments)")
            }
        }
        return out.joined(separator: "\n")
    }

    private static func seedMessagesFromRawLogTail(ctx: AXProjectContext, maxTurns: Int) -> [AXRecentContextMessage] {
        guard FileManager.default.fileExists(atPath: ctx.rawLogURL.path) else { return [] }
        guard let turns = tailTurns(url: ctx.rawLogURL, maxTurns: maxTurns), !turns.isEmpty else { return [] }

        var out: [AXRecentContextMessage] = []
        for (ts, u, a, attachments) in turns.sorted(by: { $0.0 < $1.0 }) {
            let ut = u.trimmingCharacters(in: .whitespacesAndNewlines)
            if !ut.isEmpty {
                out.append(
                    AXRecentContextMessage(
                        role: "user",
                        content: truncateInline(ut, max: maxCharsPerMessage),
                        createdAt: ts,
                        attachments: attachments
                    )
                )
            }
            let at = a.trimmingCharacters(in: .whitespacesAndNewlines)
            if !at.isEmpty {
                out.append(
                    AXRecentContextMessage(
                        role: "assistant",
                        content: truncateInline(at, max: maxCharsPerMessage),
                        createdAt: ts
                    )
                )
            }
        }
        if out.count > maxMessages {
            out = Array(out.suffix(maxMessages))
        }
        return out
    }

    private static func tailTurns(url: URL, maxTurns: Int) -> [(Double, String, String, [AXChatAttachment])]? {
        let fm = FileManager.default
        guard let attrs = try? fm.attributesOfItem(atPath: url.path),
              let sizeNum = attrs[.size] as? NSNumber else { return nil }
        let fileSize = max(Int64(0), sizeNum.int64Value)
        if fileSize <= 0 { return [] }

        var bytesToRead: Int64 = min(fileSize, 256 * 1024)
        var turns: [(Double, String, String, [AXChatAttachment])] = []

        while true {
            let offset = max(Int64(0), fileSize - bytesToRead)
            guard let data = readTailData(url: url, offset: offset) else { break }
            var s = String(data: data, encoding: .utf8) ?? ""

            // Drop the first partial line when we didn't start at file beginning.
            if offset > 0, let nl = s.firstIndex(of: "\n") {
                s = String(s[s.index(after: nl)...])
            }

            turns = extractTurns(from: s, maxTurns: maxTurns)
            if turns.count >= maxTurns { break }
            if offset == 0 { break }
            if bytesToRead >= fileSize { break }
            if bytesToRead >= bootstrapMaxBytesCap { break }
            bytesToRead = min(fileSize, bytesToRead * 2)
        }

        return turns
    }

    private static func readTailData(url: URL, offset: Int64) -> Data? {
        do {
            let fh = try FileHandle(forReadingFrom: url)
            defer { try? fh.close() }
            try fh.seek(toOffset: UInt64(max(0, offset)))
            return try fh.readToEnd() ?? Data()
        } catch {
            return nil
        }
    }

    private static func extractTurns(
        from jsonl: String,
        maxTurns: Int
    ) -> [(Double, String, String, [AXChatAttachment])] {
        var found: [(Double, String, String, [AXChatAttachment])] = []
        for line in jsonl.split(separator: "\n", omittingEmptySubsequences: true).reversed() {
            if found.count >= maxTurns { break }
            guard let ld = line.data(using: .utf8) else { continue }
            guard let obj = try? JSONSerialization.jsonObject(with: ld) as? [String: Any] else { continue }
            guard (obj["type"] as? String) == "turn" else { continue }
            let ts = (obj["created_at"] as? Double) ?? 0
            let u = (obj["user"] as? String) ?? ""
            let a = (obj["assistant"] as? String) ?? ""
            found.append((ts, u, a, decodeAttachments(from: obj["attachments"])))
        }
        // We walked backwards; restore chronological order here.
        return found.sorted(by: { $0.0 < $1.0 })
    }

    private static func decodeAttachments(from raw: Any?) -> [AXChatAttachment] {
        guard let raw,
              JSONSerialization.isValidJSONObject(raw),
              let data = try? JSONSerialization.data(withJSONObject: raw) else {
            return []
        }
        return (try? JSONDecoder().decode([AXChatAttachment].self, from: data)) ?? []
    }

    private static func truncateInline(_ s: String, max: Int) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.count <= max { return t }
        let idx = t.index(t.startIndex, offsetBy: max)
        return String(t[..<idx]) + "\n\n[x-terminal] truncated"
    }

    private static func comparableMessageText(_ raw: String) -> String {
        raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\r\n", with: "\n")
    }
}
