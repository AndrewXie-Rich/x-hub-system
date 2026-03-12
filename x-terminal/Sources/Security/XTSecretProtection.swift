import Foundation

struct XTSecretProtectionAnalysis: Equatable {
    var shouldProtect: Bool
    var sanitizedText: String
    var signals: [String]
}

enum XTSecretProtection {
    private struct Rule {
        var signal: String
        var regex: NSRegularExpression
        var replacement: String
    }

    private static let rules: [Rule] = [
        rule(
            signal: "private_block",
            pattern: #"(?is)<private\b[^>]*>.*?</private\s*>"#,
            replacement: "[private omitted]"
        ),
        rule(
            signal: "private_key_block",
            pattern: #"(?is)-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----.*?-----END [A-Z0-9 ]*PRIVATE KEY-----"#,
            replacement: "[redacted_private_key]"
        ),
        rule(
            signal: "openai_api_key",
            pattern: #"\bsk-[A-Za-z0-9_-]{10,}\b"#,
            replacement: "[redacted_api_key]"
        ),
        rule(
            signal: "anthropic_api_key",
            pattern: #"\bsk-ant-[A-Za-z0-9_-]{10,}\b"#,
            replacement: "[redacted_api_key]"
        ),
        rule(
            signal: "github_token",
            pattern: #"\bgh[pousr]_[A-Za-z0-9]{20,}\b"#,
            replacement: "[redacted_token]"
        ),
        rule(
            signal: "slack_token",
            pattern: #"\bxox[abprs]-[A-Za-z0-9-]{10,}\b"#,
            replacement: "[redacted_token]"
        ),
        rule(
            signal: "bearer_token",
            pattern: #"\bBearer\s+[A-Za-z0-9._-]{16,}\b"#,
            options: [.caseInsensitive],
            replacement: "Bearer [redacted_token]"
        ),
        rule(
            signal: "jwt",
            pattern: #"\beyJ[A-Za-z0-9_-]{6,}\.[A-Za-z0-9_-]{6,}\.[A-Za-z0-9_-]{6,}\b"#,
            replacement: "[redacted_jwt]"
        ),
        rule(
            signal: "authorization_header",
            pattern: #"(?i)(authorization|cookie|set-cookie)\s*:\s*[^\n]{8,}"#,
            replacement: "$1: [redacted]"
        ),
        rule(
            signal: "named_secret_assignment",
            pattern: #"(?i)(password|passwd|pwd|api[_-]?key|secret|access[_\s-]*token|refresh[_\s-]*token|client[_\s-]*secret|session[_\s-]*secret|otp|passcode|auth(?:orization)?[_\s-]*code|verification[_\s-]*code)\s*(?:[:=]|\bis\b)\s*[^\s,;]{4,}"#,
            replacement: "$1=[redacted]"
        ),
        rule(
            signal: "named_secret_assignment_zh",
            pattern: #"(密码|口令|密钥|令牌|验证码|授权码|访问令牌|刷新令牌)\s*(?:[:：=]|是)\s*[^\s，；,;]{4,}"#,
            replacement: "$1=[已脱敏]"
        ),
        rule(
            signal: "cookie_assignment",
            pattern: #"(?i)(cookie|session(?:_id)?|sid|csrftoken)\s*[:=]\s*[A-Za-z0-9._%=-]{8,}"#,
            replacement: "$1=[redacted]"
        ),
    ]

    static func analyzeUserInput(_ raw: String) -> XTSecretProtectionAnalysis {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return XTSecretProtectionAnalysis(
                shouldProtect: false,
                sanitizedText: "",
                signals: []
            )
        }

        var sanitized = trimmed
        var signals: [String] = []

        for rule in rules {
            let range = NSRange(sanitized.startIndex..<sanitized.endIndex, in: sanitized)
            if rule.regex.firstMatch(in: sanitized, options: [], range: range) != nil {
                signals.append(rule.signal)
                sanitized = rule.regex.stringByReplacingMatches(
                    in: sanitized,
                    options: [],
                    range: range,
                    withTemplate: rule.replacement
                )
            }
        }

        let lineCount = max(1, trimmed.split(separator: "\n", omittingEmptySubsequences: false).count)
        let maxChars = max(512, min(32_000, trimmed.count + 128))
        let lineCap = max(16, min(240, lineCount + 8))
        let normalizedSanitized = XTMemorySanitizer.sanitizeText(
            sanitized,
            maxChars: maxChars,
            lineCap: lineCap
        ) ?? sanitized

        let dedupedSignals = orderedUnique(signals)
        let finalText = normalizedSanitized.trimmingCharacters(in: .whitespacesAndNewlines)
        let protectedText = finalText.isEmpty ? "[protected_secret_input]" : finalText
        let shouldProtect = !dedupedSignals.isEmpty || protectedText != trimmed

        return XTSecretProtectionAnalysis(
            shouldProtect: shouldProtect,
            sanitizedText: protectedText,
            signals: dedupedSignals
        )
    }

    static func blockedInputReply(for analysis: XTSecretProtectionAnalysis) -> String {
        let hint = analysis.signals.isEmpty
            ? "sensitive_input_detected"
            : analysis.signals.joined(separator: ", ")
        return """
检测到敏感凭据输入，已按保护模式处理。

- 原文未写入本地 recent/raw_log/memory
- 原文未镜像到 Hub 会话
- 原文未发送给模型

当前测试版请不要把密码、API key、cookie、token 直接发在聊天框里。
下一步应通过后续的 Hub Secret Vault / secure capture 绑定后，再让我代你登录或调用。

reason=\(hint)
"""
    }

    private static func orderedUnique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for value in values {
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else { continue }
            guard seen.insert(normalized).inserted else { continue }
            out.append(normalized)
        }
        return out
    }

    private static func rule(
        signal: String,
        pattern: String,
        options: NSRegularExpression.Options = [],
        replacement: String
    ) -> Rule {
        Rule(
            signal: signal,
            regex: try! NSRegularExpression(pattern: pattern, options: options),
            replacement: replacement
        )
    }
}
