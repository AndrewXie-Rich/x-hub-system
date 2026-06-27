import Foundation

extension HubMemoryContextBuilder {
    static func clip(_ text: String, budgetTokens: Int, preferTail: Bool) -> ClipResult {
        let clean = normalized(text)
        guard !clean.isEmpty else {
            return ClipResult(text: "", truncated: false)
        }
        guard budgetTokens > 0 else {
            return ClipResult(text: "", truncated: true)
        }
        if estimateTokens(clean) <= budgetTokens {
            return ClipResult(text: clean, truncated: false)
        }

        var lo = 0
        var hi = clean.count
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            let cand = truncatedCandidate(clean, chars: mid, preferTail: preferTail)
            if estimateTokens(cand) <= budgetTokens {
                lo = mid
            } else {
                hi = mid - 1
            }
        }

        let out = truncatedCandidate(clean, chars: lo, preferTail: preferTail)
        return ClipResult(text: normalized(out), truncated: true)
    }

    static func estimateTokens(_ text: String) -> Int {
        if text.isEmpty { return 0 }
        var ascii = 0
        var nonAscii = 0
        for u in text.unicodeScalars {
            if u.isASCII {
                ascii += 1
            } else {
                nonAscii += 1
            }
        }
        let asciiTokens = Int(ceil(Double(ascii) / 4.0))
        let nonAsciiTokens = Int(ceil(Double(nonAscii) / 1.5))
        return max(0, asciiTokens + nonAsciiTokens)
    }

    static func nonEmptyOrNone(_ text: String) -> String {
        let t = normalized(text)
        return t.isEmpty ? "(none)" : t
    }

    static func firstNonEmpty(_ lhs: String?, _ rhs: String) -> String {
        let left = normalized(lhs)
        if !left.isEmpty { return left }
        return normalized(rhs)
    }

    static func normalized(_ text: String?) -> String {
        guard let text else { return "" }
        return text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func clamp(_ v: Int, min minValue: Int, max maxValue: Int) -> Int {
        if v < minValue { return minValue }
        if v > maxValue { return maxValue }
        return v
    }

    private static func truncatedCandidate(_ text: String, chars: Int, preferTail: Bool) -> String {
        guard !text.isEmpty else { return "" }
        let n = max(0, min(chars, text.count))
        if n == 0 { return "…" }
        let chunk = preferTail ? suffix(text, n) : prefix(text, n)
        if n >= text.count { return chunk }
        return preferTail ? "…" + chunk : chunk + "…"
    }

    private static func prefix(_ text: String, _ chars: Int) -> String {
        guard chars > 0 else { return "" }
        if chars >= text.count { return text }
        let idx = text.index(text.startIndex, offsetBy: chars)
        return String(text[..<idx])
    }

    private static func suffix(_ text: String, _ chars: Int) -> String {
        guard chars > 0 else { return "" }
        if chars >= text.count { return text }
        let idx = text.index(text.endIndex, offsetBy: -chars)
        return String(text[idx...])
    }
}
