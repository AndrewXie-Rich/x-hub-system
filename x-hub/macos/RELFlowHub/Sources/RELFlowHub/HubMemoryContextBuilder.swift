import Foundation
import RELFlowHubCore

enum HubMemoryContextBuilder {
    private struct Budget {
        var totalTokens: Int
        var l0Tokens: Int
        var l1Tokens: Int
        var l2Tokens: Int
        var l3Tokens: Int
        var l4Tokens: Int
    }

    private struct RedactionCounters {
        var redactedItems: Int = 0
        var privateDrops: Int = 0
    }

    private struct ClipResult {
        var text: String
        var truncated: Bool
    }

    private struct PrivateTagSanitizeResult {
        var text: String
        var hadPrivate: Bool
        var malformed: Bool
        var redactedCount: Int
    }

    private struct ProjectFallback {
        var canonical: String
        var observations: String
    }

    static func build(from req: IPCMemoryContextRequestPayload) -> IPCMemoryContextResponsePayload {
        let budgets = normalizedBudgets(req.budgets)
        let mode = normalized(req.mode).lowercased()
        var counters = RedactionCounters()
        var truncatedLayers: [String] = []

        let latestUserSeed = sanitized(req.latestUser, counters: &counters)
        let latestUser = latestUserSeed.isEmpty ? "(none)" : latestUserSeed

        let fallback = projectFallback(req: req)
        let canonicalSeed = firstNonEmpty(req.canonicalText, fallback.canonical)
        let observationsSeed = firstNonEmpty(req.observationsText, fallback.observations)
        let workingSeed = normalized(req.workingSetText)
        let rawSeed = firstNonEmpty(req.rawEvidenceText, rawEvidenceFallback(mode: mode))

        let constitutionSeed = firstNonEmpty(
            req.constitutionHint,
            loadConstitutionOneLiner(latestUser: latestUser)
        )
        let l0 = clip(
            constitutionSeed.isEmpty ? defaultConstitution(latestUser: latestUser) : constitutionSeed,
            budgetTokens: budgets.l0Tokens,
            preferTail: false
        )
        if l0.truncated { truncatedLayers.append("l0_constitution") }

        let l1 = clip(
            sanitized(canonicalSeed, counters: &counters),
            budgetTokens: budgets.l1Tokens,
            preferTail: true
        )
        if l1.truncated { truncatedLayers.append("l1_canonical") }

        let l2 = clip(
            sanitized(observationsSeed, counters: &counters),
            budgetTokens: budgets.l2Tokens,
            preferTail: true
        )
        if l2.truncated { truncatedLayers.append("l2_observations") }

        let l3 = clip(
            sanitized(workingSeed, counters: &counters),
            budgetTokens: budgets.l3Tokens,
            preferTail: true
        )
        if l3.truncated { truncatedLayers.append("l3_working_set") }

        let latestUserBudget = max(64, min(220, budgets.l4Tokens / 2))
        let l4LatestUser = clip(
            latestUser,
            budgetTokens: latestUserBudget,
            preferTail: false
        )
        let l4LatestTokens = estimateTokens(l4LatestUser.text)
        let l4Overhead = estimateTokens("tool_results:\nlatest_user:")
        let l4RawBudget = max(0, budgets.l4Tokens - l4LatestTokens - l4Overhead)
        let l4Raw = clip(
            sanitized(rawSeed, counters: &counters),
            budgetTokens: l4RawBudget,
            preferTail: true
        )
        if l4Raw.truncated || l4LatestUser.truncated { truncatedLayers.append("l4_raw_evidence") }

        let l0Text = nonEmptyOrNone(l0.text)
        let l1Text = nonEmptyOrNone(l1.text)
        let l2Text = nonEmptyOrNone(l2.text)
        let l3Text = nonEmptyOrNone(l3.text)
        let l4RawText = nonEmptyOrNone(l4Raw.text)
        let l4LatestUserText = nonEmptyOrNone(l4LatestUser.text)

        let memoryText = """
[MEMORY_V1]
[L0_CONSTITUTION]
\(l0Text)
[/L0_CONSTITUTION]

[L1_CANONICAL]
\(l1Text)
[/L1_CANONICAL]

[L2_OBSERVATIONS]
\(l2Text)
[/L2_OBSERVATIONS]

[L3_WORKING_SET]
\(l3Text)
[/L3_WORKING_SET]

[L4_RAW_EVIDENCE]
tool_results:
\(l4RawText)
latest_user:
\(l4LatestUserText)
[/L4_RAW_EVIDENCE]
[/MEMORY_V1]
"""

        let layerUsage: [IPCMemoryContextLayerUsage] = [
            IPCMemoryContextLayerUsage(layer: "l0_constitution", usedTokens: estimateTokens(l0Text), budgetTokens: budgets.l0Tokens),
            IPCMemoryContextLayerUsage(layer: "l1_canonical", usedTokens: estimateTokens(l1Text), budgetTokens: budgets.l1Tokens),
            IPCMemoryContextLayerUsage(layer: "l2_observations", usedTokens: estimateTokens(l2Text), budgetTokens: budgets.l2Tokens),
            IPCMemoryContextLayerUsage(layer: "l3_working_set", usedTokens: estimateTokens(l3Text), budgetTokens: budgets.l3Tokens),
            IPCMemoryContextLayerUsage(
                layer: "l4_raw_evidence",
                usedTokens: estimateTokens("tool_results:\n\(l4RawText)\nlatest_user:\n\(l4LatestUserText)"),
                budgetTokens: budgets.l4Tokens
            ),
        ]
        let usedTotal = layerUsage.reduce(0) { $0 + max(0, $1.usedTokens) }

        let truncatedText = truncatedLayers.isEmpty ? "none" : truncatedLayers.joined(separator: ",")
        HubDiagnostics.log(
            "memory_context.build mode=\(mode.isEmpty ? "project" : mode) " +
            "used=\(usedTotal)/\(budgets.totalTokens) truncated=\(truncatedText) " +
            "redacted=\(counters.redactedItems) private=\(counters.privateDrops)"
        )

        return IPCMemoryContextResponsePayload(
            text: memoryText,
            source: "hub_memory_v1",
            budgetTotalTokens: budgets.totalTokens,
            usedTotalTokens: usedTotal,
            layerUsage: layerUsage,
            truncatedLayers: truncatedLayers,
            redactedItems: counters.redactedItems,
            privateDrops: counters.privateDrops
        )
    }

    private static func normalizedBudgets(_ raw: IPCMemoryContextBudgets?) -> Budget {
        let defaultTotal = 1_700
        let defaultL0 = 70
        let defaultL1 = 420
        let defaultL2 = 240
        let defaultL3 = 560
        let defaultL4 = 410

        var total = clamp(raw?.totalTokens ?? defaultTotal, min: 400, max: 16_000)
        let l0 = clamp(raw?.l0Tokens ?? defaultL0, min: 24, max: 1_500)
        var l1 = clamp(raw?.l1Tokens ?? defaultL1, min: 40, max: 4_000)
        var l2 = clamp(raw?.l2Tokens ?? defaultL2, min: 40, max: 4_000)
        var l3 = clamp(raw?.l3Tokens ?? defaultL3, min: 80, max: 6_000)
        var l4 = clamp(raw?.l4Tokens ?? defaultL4, min: 60, max: 6_000)

        let sum = l0 + l1 + l2 + l3 + l4
        if sum > total {
            let fixed = l0
            let variable = max(1, sum - fixed)
            let room = max(160, total - fixed)
            let scale = Double(room) / Double(variable)
            l1 = max(40, Int(Double(l1) * scale))
            l2 = max(40, Int(Double(l2) * scale))
            l3 = max(80, Int(Double(l3) * scale))
            l4 = max(60, room - l1 - l2 - l3)
        }

        let newSum = l0 + l1 + l2 + l3 + l4
        if newSum > total {
            let overflow = newSum - total
            l3 = max(80, l3 - overflow)
        } else if newSum < total {
            l3 += (total - newSum)
        }

        total = max(total, l0 + l1 + l2 + l3 + l4)
        return Budget(totalTokens: total, l0Tokens: l0, l1Tokens: l1, l2Tokens: l2, l3Tokens: l3, l4Tokens: l4)
    }

    private static func clip(_ text: String, budgetTokens: Int, preferTail: Bool) -> ClipResult {
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

    private static func estimateTokens(_ text: String) -> Int {
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

    private static func sanitized(_ raw: String?, counters: inout RedactionCounters) -> String {
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

    private enum PrivateTagKind {
        case open
        case close
    }

    private struct PrivateTagToken {
        var kind: PrivateTagKind
        var end: Int
        var malformed: Bool
    }

    // State-machine parser for <private>...</private>, fail-closed on malformed tags.
    private static func stripPrivateTagsFailClosed(_ input: String, placeholder: String) -> PrivateTagSanitizeResult {
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

    private static func replacingRegex(
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

    private static func projectFallback(req: IPCMemoryContextRequestPayload) -> ProjectFallback {
        let reg = HubProjectRegistryStorage.load()
        guard !reg.projects.isEmpty else {
            return ProjectFallback(canonical: "", observations: "")
        }
        let pid = normalized(req.projectId)
        let root = normalized(req.projectRoot)
        let display = normalized(req.displayName)

        let matched: HubProjectSnapshot? = {
            if !pid.isEmpty, let p = reg.projects.first(where: { $0.projectId == pid }) {
                return p
            }
            if !root.isEmpty, let p = reg.projects.first(where: { normalized($0.rootPath) == root }) {
                return p
            }
            if !display.isEmpty,
               let p = reg.projects.first(where: {
                   normalized($0.displayName).localizedCaseInsensitiveCompare(display) == .orderedSame
               }) {
                return p
            }
            return nil
        }()

        guard let p = matched else {
            return ProjectFallback(canonical: "", observations: "")
        }
        let status = normalized(p.statusDigest)
        let canonical = """
project: \(p.displayName)
project_id: \(p.projectId)
root_path: \(p.rootPath)
status: \(status.isEmpty ? "(none)" : status)
"""
        let obs = """
hub_registry_updated_at: \(Int(reg.updatedAt))
project_updated_at: \(Int(p.updatedAt ?? 0))
last_summary_at: \(Int(p.lastSummaryAt ?? 0))
last_event_at: \(Int(p.lastEventAt ?? 0))
"""
        return ProjectFallback(canonical: canonical, observations: obs)
    }

    private static func rawEvidenceFallback(mode: String) -> String {
        let ms = ModelStateStorage.load()
        guard !ms.models.isEmpty else { return "" }

        let sorted = ms.models.sorted { a, b in
            if a.state != b.state {
                if a.state == .loaded { return true }
                if b.state == .loaded { return false }
            }
            return a.id.localizedCaseInsensitiveCompare(b.id) == .orderedAscending
        }

        let cap = mode == "supervisor" ? 16 : 8
        let lines = sorted.prefix(cap).map { m in
            let roles = (m.roles ?? []).joined(separator: ",")
            let roleText = roles.isEmpty ? "" : " roles=\(roles)"
            return "- \(m.id) [\(m.state.rawValue)] ctx=\(m.contextLength) backend=\(m.backend)\(roleText)"
        }.joined(separator: "\n")

        return """
models_state_updated_at: \(Int(ms.updatedAt))
\(lines)
"""
    }

    private static func loadConstitutionOneLiner(latestUser: String) -> String {
        if shouldUseConciseConstitutionForLowRiskRequest(latestUser) {
            return "优先给出可执行答案；保持真实透明并保护隐私。"
        }

        let fallback = defaultConstitution(latestUser: latestUser)
        let url = SharedPaths.ensureHubDirectory()
            .appendingPathComponent("memory", isDirectory: true)
            .appendingPathComponent("ax_constitution.json")
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let one = obj["one_liner"] as? [String: Any] else {
            return fallback
        }

        let zh = normalized(one["zh"] as? String)
        if !zh.isEmpty { return normalizeConstitution(zh) }
        let en = normalized(one["en"] as? String)
        if !en.isEmpty { return normalizeConstitution(en) }
        return fallback
    }

    private static func defaultConstitution(latestUser: String) -> String {
        if shouldUseConciseConstitutionForLowRiskRequest(latestUser) {
            return "优先给出可执行答案；保持真实透明并保护隐私。"
        }
        return "真实透明、最小化外发；仅在高风险或不可逆动作时先解释后执行；普通编程/创作请求直接给出可执行答案。"
    }

    private static func normalizeConstitution(_ raw: String) -> String {
        let t = normalized(raw)
        guard !t.isEmpty else {
            return "真实透明、最小化外发；仅在高风险或不可逆动作时先解释后执行；普通编程/创作请求直接给出可执行答案。"
        }

        let legacy = "真实透明、最小化外发、关键风险先解释后执行。"
        var out = (t == legacy)
            ? "真实透明、最小化外发；仅在高风险或不可逆动作时先解释后执行；普通编程/创作请求直接给出可执行答案。"
            : t

        let lower = out.lowercased()
        let zhRiskFocused =
            out.contains("高风险") ||
            out.contains("合规") ||
            out.contains("法律") ||
            out.contains("隐私") ||
            out.contains("安全") ||
            out.contains("伤害") ||
            out.contains("必要时拒绝") ||
            out.contains("关键风险先解释后执行")
        let enRiskFocused =
            lower.contains("high-risk") ||
            lower.contains("compliance") ||
            lower.contains("legal") ||
            lower.contains("privacy") ||
            lower.contains("safety") ||
            lower.contains("harm") ||
            lower.contains("refuse")

        let zhHasCarveout =
            out.contains("仅在高风险") ||
            out.contains("低风险") ||
            out.contains("普通编程") ||
            out.contains("普通创作") ||
            out.contains("普通请求") ||
            out.contains("直接给出可执行答案") ||
            out.contains("直接回答")
        let enHasCarveout =
            lower.contains("only for high-risk") ||
            lower.contains("normal coding") ||
            lower.contains("creative requests") ||
            lower.contains("respond directly") ||
            lower.contains("answer normal")

        if zhRiskFocused && !zhHasCarveout {
            out += " 仅在高风险或不可逆动作时先解释后执行；普通编程/创作请求直接给出可执行答案。"
        } else if enRiskFocused && !enHasCarveout {
            out += " Explain first only for high-risk or irreversible actions; answer normal coding/creative requests directly."
        }
        return out
    }

    private static func shouldUseConciseConstitutionForLowRiskRequest(_ userText: String) -> Bool {
        let t = normalized(userText).lowercased()
        if t.isEmpty { return false }

        let codingSignals = [
            "写一个", "写个", "代码", "程序", "脚本", "函数", "类", "项目", "网页", "网站", "游戏", "赛车游戏",
            "write", "code", "script", "function", "class", "build", "create", "game", "app", "web",
        ]
        let riskSignals = [
            "绕过", "规避", "破解", "入侵", "提权", "钓鱼", "木马", "勒索", "盗号", "删日志",
            "违法", "犯罪", "武器", "爆炸", "毒品", "未成年人", "自杀", "自残", "伤害", "暴力",
            "法律", "合规", "隐私", "保密", "风险", "后果",
            "bypass", "circumvent", "hack", "exploit", "privilege escalation", "phishing", "malware", "ransomware",
            "illegal", "weapon", "explosive", "drugs", "minor", "suicide", "self-harm", "violence",
            "legal", "compliance", "privacy", "risk", "consequence",
        ]
        let hasCoding = codingSignals.contains(where: { t.contains($0) })
        let hasRisk = riskSignals.contains(where: { t.contains($0) })
        return hasCoding && !hasRisk
    }

    private static func nonEmptyOrNone(_ text: String) -> String {
        let t = normalized(text)
        return t.isEmpty ? "(none)" : t
    }

    private static func firstNonEmpty(_ lhs: String?, _ rhs: String) -> String {
        let left = normalized(lhs)
        if !left.isEmpty { return left }
        return normalized(rhs)
    }

    private static func normalized(_ text: String?) -> String {
        guard let text else { return "" }
        return text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func clamp(_ v: Int, min minValue: Int, max maxValue: Int) -> Int {
        if v < minValue { return minValue }
        if v > maxValue { return maxValue }
        return v
    }
}
