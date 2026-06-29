import Foundation

extension ChatSessionModel {
    func toolEvidenceForMemoryV1(_ toolResults: [ToolResult]) -> String {
        guard !toolResults.isEmpty else { return "" }
        return toolResults.suffix(6).map { r in
            let out = cappedForMemoryV1(sanitizedPromptContextText(r.output), maxChars: 260)
            return "id=\(r.id) tool=\(r.tool.rawValue) ok=\(r.ok)\n\(out)"
        }.joined(separator: "\n\n")
    }

    func toolHistoryForPrompt(_ toolResults: [ToolResult]) -> String {
        guard !toolResults.isEmpty else { return "(none)" }
        return toolResults.map(toolHistoryEntryForPrompt).joined(separator: "\n\n")
    }

    func toolHistoryEntryForPrompt(_ result: ToolResult) -> String {
        var lines: [String] = ["id=\(result.id) tool=\(result.tool.rawValue) ok=\(result.ok)"]
        let promptSummary = sanitizedPromptContextText(ToolResultHumanSummary.specializedSummary(for: result) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !promptSummary.isEmpty {
            let cappedSummary = promptSummary.count > 260
                ? String(promptSummary.prefix(260)) + "..."
                : promptSummary
            lines.append("summary=\(cappedSummary)")
        }

        var body = sanitizedPromptContextText(result.output)
        if result.id.hasPrefix("verify") {
            body = tailLines(body, maxLines: 120)
        }
        if body.count > 1800 {
            body = String(body.prefix(1800)) + "\n[truncated]"
        }
        if !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append(body)
        }
        return lines.joined(separator: "\n")
    }

    func remoteProjectPromptOverrideIfNeeded(
        role: AXRole,
        prompt: String,
        routeDecision: AXProjectPreferredModelRouteDecision,
        transportMode: HubTransportMode,
        hasRemoteProfile: Bool
    ) -> String? {
        guard role == .coder, !routeDecision.forceLocalExecution else { return nil }
        let route = HubRouteStateMachine.resolve(mode: transportMode, hasRemoteProfile: hasRemoteProfile)
        guard route.preferRemote else { return nil }
        let sanitized = sanitizedRemoteProjectPrompt(prompt)
        return sanitized == prompt ? nil : sanitized
    }

    func sanitizedRemoteProjectPrompt(_ prompt: String) -> String {
        var out = sanitizedPromptContextText(prompt)
        out = replacingRegex(
            in: out,
            pattern: #"<private>[\s\S]*?<\/private>"#,
            with: "[REDACTED_PRIVATE_BLOCK]"
        )
        out = replacingRegex(
            in: out,
            pattern: #"\[private\]"#,
            with: "[REDACTED_PRIVATE]",
            options: [.caseInsensitive]
        )
        out = replacingPromptSection(
            in: out,
            tag: "L4_RAW_EVIDENCE",
            body: """
tool_results:
(scope-limited raw evidence retained locally and omitted from remote export)
latest_user:
(refer to the explicit User request section below)
"""
        )
        out = replacingRemoteToolResultsSection(in: out)
        return out
    }

    func replacingRemoteToolResultsSection(in text: String) -> String {
        guard let headerRange = text.range(of: "Tool results so far:\n") else { return text }
        guard let footerRange = text.range(
            of: "\n\nUser request:\n",
            range: headerRange.upperBound..<text.endIndex
        ) else { return text }

        let rawBlock = String(text[headerRange.upperBound..<footerRange.lowerBound])
        let summarizedBlock = summarizedRemoteToolResultsBlock(rawBlock)
        return String(text[..<headerRange.upperBound]) + summarizedBlock + String(text[footerRange.lowerBound...])
    }

    func summarizedRemoteToolResultsBlock(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "(none)" else { return "(none)" }

        let entryChunks = trimmed
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let summarizedEntries = entryChunks.prefix(6).map { chunk -> String in
            let lines = chunk
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            var compact: [String] = []
            if let idLine = lines.first(where: { $0.hasPrefix("id=") }) {
                compact.append(idLine)
            }
            if let summaryLine = lines.first(where: { $0.hasPrefix("summary=") }) {
                compact.append(summaryLine)
            }
            compact.append("details=(raw tool output retained locally in XT and omitted from remote export)")
            return compact.joined(separator: "\n")
        }

        return summarizedEntries.joined(separator: "\n\n")
    }

    func replacingPromptSection(
        in text: String,
        tag: String,
        body: String
    ) -> String {
        replacingRegex(
            in: text,
            pattern: "\\[\(NSRegularExpression.escapedPattern(for: tag))\\][\\s\\S]*?\\[/\(NSRegularExpression.escapedPattern(for: tag))\\]",
            with: """
[\(tag)]
\(body)
[/\(tag)]
"""
        )
    }

    func replacingRegex(
        in text: String,
        pattern: String,
        with replacement: String,
        options: NSRegularExpression.Options = []
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return text
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: replacement)
    }

    func sanitizedPromptContextText(_ text: String) -> String {
        var out = text
        let regexReplacements: [(pattern: String, template: String, options: NSRegularExpression.Options)] = [
            (#"\bsk-[A-Za-z0-9_-]{10,}\b"#, "[REDACTED_OPENAI_TOKEN]", []),
            (#"\bghp_[A-Za-z0-9]{20,}\b"#, "[REDACTED_GITHUB_TOKEN]", []),
            (#"\bxox[abprs]-[A-Za-z0-9-]{10,}\b"#, "[REDACTED_SLACK_TOKEN]", []),
            (#"\bBearer\s+[A-Za-z0-9._-]{16,}\b"#, "Bearer [REDACTED_TOKEN]", [.caseInsensitive]),
            (#"-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z ]*PRIVATE KEY-----"#, "[REDACTED_PRIVATE_KEY_BLOCK]", []),
            (#"\b(api[_\s-]*key|private[_\s-]*key|secret[_\s-]*token|access[_\s-]*token|jwt|otp|payment[_\s-]*(pin|code)|password|passcode|authorization[_\s-]*code|auth[_\s-]*code|client[_\s-]*secret|session[_\s-]*secret|cookie)\b"#, "[REDACTED_SECRET_KEYWORD]", [.caseInsensitive]),
        ]

        for replacement in regexReplacements {
            guard let regex = try? NSRegularExpression(pattern: replacement.pattern, options: replacement.options) else {
                continue
            }
            let range = NSRange(out.startIndex..<out.endIndex, in: out)
            out = regex.stringByReplacingMatches(in: out, options: [], range: range, withTemplate: replacement.template)
        }

        return out
    }

    func cappedForMemoryV1(_ text: String, maxChars: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxChars else { return trimmed }
        let idx = trimmed.index(trimmed.startIndex, offsetBy: maxChars)
        return String(trimmed[..<idx]) + "…"
    }

    func tailLines(_ s: String, maxLines: Int) -> String {
        let n = max(1, maxLines)
        let lines = s.split(separator: "\n", omittingEmptySubsequences: false)
        if lines.count <= n {
            return s
        }
        let tail = lines.suffix(n).joined(separator: "\n")
        return "[x-terminal] showing last \(n) lines of verify output\n" + tail
    }

    func jsonArgs(_ args: [String: JSONValue]) -> [String: Any] {
        var out: [String: Any] = [:]
        for (k, v) in args {
            out[k] = jsonValueToAny(v)
        }
        return out
    }

    func jsonValueToAny(_ v: JSONValue) -> Any {
        switch v {
        case .string(let s): return s
        case .number(let n): return n
        case .bool(let b): return b
        case .null: return NSNull()
        case .array(let a): return a.map { jsonValueToAny($0) }
        case .object(let o):
            var out: [String: Any] = [:]
            for (k, vv) in o { out[k] = jsonValueToAny(vv) }
            return out
        }
    }

    func appendGovernanceTruthSnapshot(
        to row: inout [String: Any],
        from summary: [String: JSONValue]
    ) {
        for (key, value) in xtPersistedGovernanceEvidenceFields(from: summary) {
            row[key] = jsonValueToAny(value)
        }
    }

    func jsonStringValue(_ value: JSONValue?) -> String? {
        guard case .string(let text)? = value else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
