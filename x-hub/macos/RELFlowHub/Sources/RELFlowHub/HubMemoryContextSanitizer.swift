import Foundation

extension HubMemoryContextBuilder {
    static func sanitized(_ raw: String?, counters: inout RedactionCounters) -> String {
        var text = normalized(raw)
        if text.isEmpty { return "" }

        let privateSanitized = stripPrivateTagsFailClosed(text, placeholder: "[private omitted]")
        text = privateSanitized.text
        if privateSanitized.redactedCount > 0 {
            counters.redactedItems += privateSanitized.redactedCount
            counters.privateDrops += privateSanitized.redactedCount
        }
        text = replacingRegex(
            text,
            pattern: "(?is)-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----.*?-----END [A-Z0-9 ]*PRIVATE KEY-----",
            with: "[redacted_private_key]",
            counters: &counters
        )
        text = replacingRegex(
            text,
            pattern: "sk-[A-Za-z0-9]{20,}",
            with: "[redacted_api_key]",
            counters: &counters
        )
        text = replacingRegex(
            text,
            pattern: "sk-ant-[A-Za-z0-9_-]{20,}",
            with: "[redacted_api_key]",
            counters: &counters
        )
        text = replacingRegex(
            text,
            pattern: "gh[pousr]_[A-Za-z0-9]{20,}",
            with: "[redacted_token]",
            counters: &counters
        )
        text = replacingRegex(
            text,
            pattern: "eyJ[A-Za-z0-9_-]{6,}\\.[A-Za-z0-9_-]{6,}\\.[A-Za-z0-9_-]{6,}",
            with: "[redacted_jwt]",
            counters: &counters
        )
        text = replacingRegex(
            text,
            pattern: "(?i)bearer\\s+[A-Za-z0-9._-]{16,}",
            with: "Bearer [redacted_token]",
            counters: &counters
        )
        text = replacingRegex(
            text,
            pattern: "(?i)(password|passwd|pwd|api[_-]?key|secret)\\s*[:=]\\s*[^\\s,;]{4,}",
            with: "$1=[redacted]",
            counters: &counters
        )

        return normalized(text)
    }

    // State-machine parser for <private>...</private>, fail-closed on malformed tags.
    static func stripPrivateTagsFailClosed(_ input: String, placeholder: String) -> PrivateTagSanitizeResult {
        let bytes = Array(input.utf8)
        guard !bytes.isEmpty else {
            return PrivateTagSanitizeResult(text: "", hadPrivate: false, malformed: false, redactedCount: 0)
        }
        let placeholderBytes = Array(placeholder.utf8)

        var output: [UInt8] = []
        output.reserveCapacity(bytes.count)

        var i = 0
        var chunkStart = 0
        var depth = 0
        var hadPrivate = false
        var malformed = false
        var redactedCount = 0

        while i < bytes.count {
            if bytes[i] != 0x3c { // <
                i += 1
                continue
            }

            guard let token = parsePrivateTagToken(bytes, from: i) else {
                i += 1
                continue
            }

            hadPrivate = true
            if token.malformed { malformed = true }

            if depth == 0, i > chunkStart {
                output.append(contentsOf: bytes[chunkStart..<i])
            }

            switch token.kind {
            case .open:
                if depth > 0 { malformed = true }
                depth += 1
                if depth == 1 { redactedCount += 1 }
            case .close:
                if depth == 0 {
                    malformed = true
                    redactedCount += 1
                    output.append(contentsOf: placeholderBytes)
                } else {
                    depth -= 1
                    if depth == 0 {
                        output.append(contentsOf: placeholderBytes)
                    }
                }
            }

            i = token.end
            chunkStart = i
        }

        if depth == 0 {
            if chunkStart < bytes.count {
                output.append(contentsOf: bytes[chunkStart..<bytes.count])
            }
        } else {
            malformed = true
            output.append(contentsOf: placeholderBytes)
        }

        return PrivateTagSanitizeResult(
            text: String(decoding: output, as: UTF8.self),
            hadPrivate: hadPrivate,
            malformed: malformed,
            redactedCount: redactedCount
        )
    }

    static func replacingRegex(
        _ input: String,
        pattern: String,
        with replacement: String,
        counters: inout RedactionCounters,
        countPrivateDrops: Bool = false
    ) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern, options: []) else {
            return input
        }
        let range = NSRange(input.startIndex..<input.endIndex, in: input)
        let matches = re.numberOfMatches(in: input, options: [], range: range)
        guard matches > 0 else { return input }
        counters.redactedItems += matches
        if countPrivateDrops {
            counters.privateDrops += matches
        }
        return re.stringByReplacingMatches(in: input, options: [], range: range, withTemplate: replacement)
    }

    private enum PrivateTagKind {
        case open
        case close
    }

    private struct PrivateTagToken {
        var kind: PrivateTagKind
        var end: Int
        var malformed: Bool
    }

    private static func parsePrivateTagToken(_ bytes: [UInt8], from start: Int) -> PrivateTagToken? {
        guard start < bytes.count, bytes[start] == 0x3c else { // <
            return nil
        }

        let n = bytes.count
        var i = start + 1
        while i < n, isASCIIWhitespace(bytes[i]) { i += 1 }
        if i >= n { return nil }

        var kind: PrivateTagKind = .open
        if bytes[i] == 0x2f { // /
            kind = .close
            i += 1
            while i < n, isASCIIWhitespace(bytes[i]) { i += 1 }
        }

        guard startsWithPrivateKeyword(bytes, at: i) else { return nil }
        i += 7 // "private"

        if i < n {
            let next = bytes[i]
            let isBoundary = next == 0x3e || next == 0x2f || isASCIIWhitespace(next) // > or /
            if !isBoundary, isASCIIWord(next) {
                return nil
            }
        }

        var malformed = false
        var sawGt = false
        var tailHasNonWs = false
        while i < n {
            let c = bytes[i]
            if c == 0x3e { // >
                sawGt = true
                i += 1
                break
            }
            if c == 0x3c { malformed = true } // nested '<' in tag body
            if !isASCIIWhitespace(c) { tailHasNonWs = true }
            i += 1
        }

        if !sawGt { malformed = true }
        if tailHasNonWs { malformed = true }

        return PrivateTagToken(kind: kind, end: sawGt ? i : n, malformed: malformed)
    }

    private static func startsWithPrivateKeyword(_ bytes: [UInt8], at start: Int) -> Bool {
        let keyword: [UInt8] = [0x70, 0x72, 0x69, 0x76, 0x61, 0x74, 0x65] // "private"
        if start < 0 || start + keyword.count > bytes.count { return false }
        for j in 0..<keyword.count {
            if lowerASCII(bytes[start + j]) != keyword[j] {
                return false
            }
        }
        return true
    }

    private static func lowerASCII(_ b: UInt8) -> UInt8 {
        if b >= 0x41 && b <= 0x5a { // A-Z
            return b + 0x20
        }
        return b
    }

    private static func isASCIIWhitespace(_ b: UInt8) -> Bool {
        return b == 0x20 || b == 0x09 || b == 0x0a || b == 0x0d || b == 0x0c || b == 0x0b
    }

    private static func isASCIIWord(_ b: UInt8) -> Bool {
        return (
            (b >= 0x30 && b <= 0x39) ||
            (b >= 0x41 && b <= 0x5a) ||
            (b >= 0x61 && b <= 0x7a) ||
            b == 0x5f ||
            b == 0x2d
        )
    }
}
