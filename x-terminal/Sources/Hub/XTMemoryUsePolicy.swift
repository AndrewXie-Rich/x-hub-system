import Foundation

enum XTMemoryRequesterRole: String, CaseIterable, Sendable {
    case chat
    case session
    case supervisor
    case tool
    case lane
    case remoteExport
}

enum XTMemoryLayer: String, CaseIterable, Sendable {
    case l0Constitution = "l0_constitution"
    case l1Canonical = "l1_canonical"
    case l2Observations = "l2_observations"
    case l3WorkingSet = "l3_working_set"
    case l4RawEvidence = "l4_raw_evidence"
}

enum XTMemoryFreshnessPolicy: String, Sendable {
    case allowShortTTLCache = "allow_short_ttl_cache"
    case requireFreshRemoteSnapshot = "require_fresh_remote_snapshot"
    case refsOnly = "refs_only"
}

enum XTMemoryUserMemoryPolicy: String, Sendable {
    case defaultOff = "default_off"
    case explicitGrantRequired = "explicit_grant_required"
    case denied = "denied"
}

enum XTMemoryLongtermPolicy: String, Sendable {
    case summaryOnly = "summary_only"
    case progressiveDisclosureRequired = "progressive_disclosure_required"
    case denied = "denied"
}

enum XTMemoryRemoteExportPolicy: String, Sendable {
    case localOnly = "local_only"
    case sanitizedOnly = "sanitized_only"
    case refsOnly = "refs_only"
}

enum XTMemoryUseDenyCode: String, Sendable {
    case memoryLayerNotAllowedForMode = "memory_layer_not_allowed_for_mode"
    case userMemoryGrantRequired = "user_memory_grant_required"
    case crossScopeMemoryDenied = "cross_scope_memory_denied"
    case longtermFulltextPDRequired = "longterm_fulltext_pd_required"
    case rawEvidenceRemoteExportDenied = "raw_evidence_remote_export_denied"
    case memorySnapshotStaleForHighRiskAct = "memory_snapshot_stale_for_high_risk_act"
    case laneHandoffFulltextDenied = "lane_handoff_fulltext_denied"
    case memoryModeContractMissing = "memory_mode_contract_missing"
    case memoryRoutePolicyMismatch = "memory_route_policy_mismatch"
}

enum XTMemoryUseMode: String, CaseIterable, Sendable {
    case projectChat = "project_chat"
    case sessionResume = "session_resume"
    case supervisorOrchestration = "supervisor_orchestration"
    case toolPlan = "tool_plan"
    case toolActLowRisk = "tool_act_low_risk"
    case toolActHighRisk = "tool_act_high_risk"
    case laneHandoff = "lane_handoff"
    case remotePromptBundle = "remote_prompt_bundle"

    static func parse(_ raw: String?) -> XTMemoryUseMode? {
        let token = (raw ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !token.isEmpty else { return .projectChat }
        if let mode = XTMemoryUseMode(rawValue: token) {
            return mode
        }
        switch token {
        case "project":
            return .projectChat
        case "supervisor":
            return .supervisorOrchestration
        case "session":
            return .sessionResume
        case "tool":
            return .toolPlan
        default:
            return nil
        }
    }
}

struct XTMemoryUseContract: Sendable {
    var mode: XTMemoryUseMode
    var allowedRequesterRoles: Set<XTMemoryRequesterRole>
    var allowedLayers: Set<XTMemoryLayer>
    var freshnessPolicy: XTMemoryFreshnessPolicy
    var userMemoryPolicy: XTMemoryUserMemoryPolicy
    var longtermPolicy: XTMemoryLongtermPolicy
    var remoteExportPolicy: XTMemoryRemoteExportPolicy
    var constitutionMaxChars: Int
    var canonicalMaxChars: Int
    var observationsMaxChars: Int
    var workingSetMaxChars: Int
    var rawEvidenceMaxChars: Int
    var lineCap: Int
    var budgetCap: HubIPCClient.MemoryContextBudgets?
    var directUseDenyCode: XTMemoryUseDenyCode?

    var bypassRemoteCache: Bool {
        freshnessPolicy == .requireFreshRemoteSnapshot
    }
}

struct XTMemoryRouteDecision: Sendable {
    var contract: XTMemoryUseContract
    var payload: HubIPCClient.MemoryContextPayload
    var denyCode: XTMemoryUseDenyCode?
    var downgradeCode: XTMemoryUseDenyCode?
    var bypassRemoteCache: Bool
}

enum XTMemoryRoleScopedRouter {
    static func route(
        role: XTMemoryRequesterRole,
        mode: XTMemoryUseMode,
        payload: HubIPCClient.MemoryContextPayload,
        remoteExportRequested: Bool = false
    ) -> XTMemoryRouteDecision {
        let contract = contract(for: mode)

        if let directUseDenyCode = contract.directUseDenyCode {
            return XTMemoryRouteDecision(
                contract: contract,
                payload: payload,
                denyCode: directUseDenyCode,
                downgradeCode: nil,
                bypassRemoteCache: contract.bypassRemoteCache
            )
        }

        guard contract.allowedRequesterRoles.contains(role) else {
            return XTMemoryRouteDecision(
                contract: contract,
                payload: payload,
                denyCode: .memoryRoutePolicyMismatch,
                downgradeCode: nil,
                bypassRemoteCache: contract.bypassRemoteCache
            )
        }

        if remoteExportRequested, contract.remoteExportPolicy == .localOnly {
            return XTMemoryRouteDecision(
                contract: contract,
                payload: payload,
                denyCode: .rawEvidenceRemoteExportDenied,
                downgradeCode: nil,
                bypassRemoteCache: contract.bypassRemoteCache
            )
        }

        var sanitized = payload
        sanitized.mode = mode.rawValue
        sanitized.constitutionHint = allowed(contract.allowedLayers, .l0Constitution)
            ? XTMemorySanitizer.sanitizeText(
                payload.constitutionHint,
                maxChars: contract.constitutionMaxChars,
                lineCap: contract.lineCap
            )
            : nil
        sanitized.canonicalText = allowed(contract.allowedLayers, .l1Canonical)
            ? XTMemorySanitizer.sanitizeText(
                payload.canonicalText,
                maxChars: contract.canonicalMaxChars,
                lineCap: contract.lineCap
            )
            : nil
        sanitized.observationsText = allowed(contract.allowedLayers, .l2Observations)
            ? XTMemorySanitizer.sanitizeText(
                payload.observationsText,
                maxChars: contract.observationsMaxChars,
                lineCap: contract.lineCap
            )
            : nil
        sanitized.workingSetText = allowed(contract.allowedLayers, .l3WorkingSet)
            ? XTMemorySanitizer.sanitizeText(
                payload.workingSetText,
                maxChars: contract.workingSetMaxChars,
                lineCap: contract.lineCap
            )
            : nil
        sanitized.rawEvidenceText = allowed(contract.allowedLayers, .l4RawEvidence) && contract.rawEvidenceMaxChars > 0
            ? XTMemorySanitizer.sanitizeRawEvidenceSummary(
                payload.rawEvidenceText,
                maxChars: contract.rawEvidenceMaxChars,
                lineCap: contract.lineCap
            )
            : nil
        sanitized.latestUser = XTMemorySanitizer.sanitizeText(
            payload.latestUser,
            maxChars: 400,
            lineCap: 10
        ) ?? "(none)"
        sanitized.budgets = cappedBudgets(payload.budgets, cap: contract.budgetCap)

        return XTMemoryRouteDecision(
            contract: contract,
            payload: sanitized,
            denyCode: nil,
            downgradeCode: nil,
            bypassRemoteCache: contract.bypassRemoteCache
        )
    }

    static func contract(for mode: XTMemoryUseMode) -> XTMemoryUseContract {
        switch mode {
        case .projectChat:
            return XTMemoryUseContract(
                mode: mode,
                allowedRequesterRoles: [.chat, .tool],
                allowedLayers: [.l0Constitution, .l1Canonical, .l2Observations, .l3WorkingSet, .l4RawEvidence],
                freshnessPolicy: .allowShortTTLCache,
                userMemoryPolicy: .defaultOff,
                longtermPolicy: .summaryOnly,
                remoteExportPolicy: .localOnly,
                constitutionMaxChars: 300,
                canonicalMaxChars: 3_200,
                observationsMaxChars: 1_800,
                workingSetMaxChars: 2_600,
                rawEvidenceMaxChars: 1_100,
                lineCap: 28,
                budgetCap: nil,
                directUseDenyCode: nil
            )
        case .sessionResume:
            return XTMemoryUseContract(
                mode: mode,
                allowedRequesterRoles: [.session, .tool],
                allowedLayers: [.l0Constitution, .l1Canonical, .l2Observations, .l3WorkingSet],
                freshnessPolicy: .allowShortTTLCache,
                userMemoryPolicy: .defaultOff,
                longtermPolicy: .summaryOnly,
                remoteExportPolicy: .localOnly,
                constitutionMaxChars: 240,
                canonicalMaxChars: 2_400,
                observationsMaxChars: 1_000,
                workingSetMaxChars: 1_600,
                rawEvidenceMaxChars: 0,
                lineCap: 20,
                budgetCap: HubIPCClient.MemoryContextBudgets(
                    totalTokens: 1_200,
                    l0Tokens: 70,
                    l1Tokens: 420,
                    l2Tokens: 180,
                    l3Tokens: 530,
                    l4Tokens: 60
                ),
                directUseDenyCode: nil
            )
        case .supervisorOrchestration:
            return XTMemoryUseContract(
                mode: mode,
                allowedRequesterRoles: [.supervisor, .tool],
                allowedLayers: [.l0Constitution, .l1Canonical, .l2Observations, .l3WorkingSet],
                freshnessPolicy: .allowShortTTLCache,
                userMemoryPolicy: .denied,
                longtermPolicy: .summaryOnly,
                remoteExportPolicy: .localOnly,
                constitutionMaxChars: 280,
                canonicalMaxChars: 2_200,
                observationsMaxChars: 1_400,
                workingSetMaxChars: 1_400,
                rawEvidenceMaxChars: 0,
                lineCap: 22,
                budgetCap: HubIPCClient.MemoryContextBudgets(
                    totalTokens: 1_300,
                    l0Tokens: 80,
                    l1Tokens: 420,
                    l2Tokens: 240,
                    l3Tokens: 500,
                    l4Tokens: 60
                ),
                directUseDenyCode: nil
            )
        case .toolPlan:
            return XTMemoryUseContract(
                mode: mode,
                allowedRequesterRoles: [.tool],
                allowedLayers: [.l0Constitution, .l1Canonical, .l2Observations, .l3WorkingSet, .l4RawEvidence],
                freshnessPolicy: .allowShortTTLCache,
                userMemoryPolicy: .defaultOff,
                longtermPolicy: .summaryOnly,
                remoteExportPolicy: .localOnly,
                constitutionMaxChars: 240,
                canonicalMaxChars: 2_400,
                observationsMaxChars: 1_400,
                workingSetMaxChars: 1_800,
                rawEvidenceMaxChars: 700,
                lineCap: 20,
                budgetCap: HubIPCClient.MemoryContextBudgets(
                    totalTokens: 1_300,
                    l0Tokens: 70,
                    l1Tokens: 430,
                    l2Tokens: 210,
                    l3Tokens: 450,
                    l4Tokens: 140
                ),
                directUseDenyCode: nil
            )
        case .toolActLowRisk:
            return XTMemoryUseContract(
                mode: mode,
                allowedRequesterRoles: [.tool],
                allowedLayers: [.l0Constitution, .l1Canonical, .l2Observations, .l3WorkingSet, .l4RawEvidence],
                freshnessPolicy: .allowShortTTLCache,
                userMemoryPolicy: .defaultOff,
                longtermPolicy: .summaryOnly,
                remoteExportPolicy: .localOnly,
                constitutionMaxChars: 220,
                canonicalMaxChars: 2_000,
                observationsMaxChars: 1_200,
                workingSetMaxChars: 1_300,
                rawEvidenceMaxChars: 500,
                lineCap: 18,
                budgetCap: HubIPCClient.MemoryContextBudgets(
                    totalTokens: 1_100,
                    l0Tokens: 70,
                    l1Tokens: 360,
                    l2Tokens: 180,
                    l3Tokens: 350,
                    l4Tokens: 140
                ),
                directUseDenyCode: nil
            )
        case .toolActHighRisk:
            return XTMemoryUseContract(
                mode: mode,
                allowedRequesterRoles: [.tool],
                allowedLayers: [.l0Constitution, .l1Canonical, .l2Observations, .l3WorkingSet],
                freshnessPolicy: .requireFreshRemoteSnapshot,
                userMemoryPolicy: .defaultOff,
                longtermPolicy: .summaryOnly,
                remoteExportPolicy: .localOnly,
                constitutionMaxChars: 220,
                canonicalMaxChars: 1_800,
                observationsMaxChars: 900,
                workingSetMaxChars: 900,
                rawEvidenceMaxChars: 0,
                lineCap: 14,
                budgetCap: HubIPCClient.MemoryContextBudgets(
                    totalTokens: 950,
                    l0Tokens: 70,
                    l1Tokens: 340,
                    l2Tokens: 180,
                    l3Tokens: 300,
                    l4Tokens: 60
                ),
                directUseDenyCode: nil
            )
        case .laneHandoff:
            return XTMemoryUseContract(
                mode: mode,
                allowedRequesterRoles: [.lane],
                allowedLayers: [],
                freshnessPolicy: .refsOnly,
                userMemoryPolicy: .denied,
                longtermPolicy: .denied,
                remoteExportPolicy: .refsOnly,
                constitutionMaxChars: 0,
                canonicalMaxChars: 0,
                observationsMaxChars: 0,
                workingSetMaxChars: 0,
                rawEvidenceMaxChars: 0,
                lineCap: 0,
                budgetCap: nil,
                directUseDenyCode: .laneHandoffFulltextDenied
            )
        case .remotePromptBundle:
            return XTMemoryUseContract(
                mode: mode,
                allowedRequesterRoles: [.remoteExport],
                allowedLayers: [.l0Constitution, .l1Canonical, .l2Observations, .l3WorkingSet],
                freshnessPolicy: .allowShortTTLCache,
                userMemoryPolicy: .defaultOff,
                longtermPolicy: .summaryOnly,
                remoteExportPolicy: .sanitizedOnly,
                constitutionMaxChars: 180,
                canonicalMaxChars: 1_400,
                observationsMaxChars: 900,
                workingSetMaxChars: 900,
                rawEvidenceMaxChars: 0,
                lineCap: 12,
                budgetCap: HubIPCClient.MemoryContextBudgets(
                    totalTokens: 900,
                    l0Tokens: 70,
                    l1Tokens: 300,
                    l2Tokens: 160,
                    l3Tokens: 310,
                    l4Tokens: 60
                ),
                directUseDenyCode: nil
            )
        }
    }

    private static func allowed(_ layers: Set<XTMemoryLayer>, _ layer: XTMemoryLayer) -> Bool {
        layers.contains(layer)
    }

    private static func cappedBudgets(
        _ explicit: HubIPCClient.MemoryContextBudgets?,
        cap: HubIPCClient.MemoryContextBudgets?
    ) -> HubIPCClient.MemoryContextBudgets? {
        guard let cap else {
            return explicit
        }

        let base = explicit ?? cap
        return HubIPCClient.MemoryContextBudgets(
            totalTokens: minPositive(base.totalTokens, cap.totalTokens),
            l0Tokens: minPositive(base.l0Tokens, cap.l0Tokens),
            l1Tokens: minPositive(base.l1Tokens, cap.l1Tokens),
            l2Tokens: minPositive(base.l2Tokens, cap.l2Tokens),
            l3Tokens: minPositive(base.l3Tokens, cap.l3Tokens),
            l4Tokens: minPositive(base.l4Tokens, cap.l4Tokens)
        )
    }

    private static func minPositive(_ lhs: Int?, _ rhs: Int?) -> Int? {
        switch (lhs, rhs) {
        case let (l?, r?):
            return max(1, min(l, r))
        case let (l?, nil):
            return max(1, l)
        case let (nil, r?):
            return max(1, r)
        case (nil, nil):
            return nil
        }
    }
}

enum XTMemorySanitizer {
    static func sanitizeText(_ raw: String?, maxChars: Int, lineCap: Int) -> String? {
        guard maxChars > 0, lineCap > 0 else { return nil }
        let normalized = normalize(raw)
        guard !normalized.isEmpty else { return nil }
        let redacted = redactSecrets(in: normalized)
        let bounded = limitLines(redacted, maxLines: lineCap)
        return capText(bounded, maxChars: maxChars)
    }

    static func sanitizeRawEvidenceSummary(_ raw: String?, maxChars: Int, lineCap: Int) -> String? {
        guard maxChars > 0, lineCap > 0 else { return nil }
        let normalized = normalize(raw)
        guard !normalized.isEmpty else { return nil }

        let redacted = redactSecrets(in: normalized)
        let rawLines = redacted.split(separator: "\n", omittingEmptySubsequences: false)
        var sanitized: [String] = []
        sanitized.reserveCapacity(min(lineCap, rawLines.count))
        var droppedBlob = false

        for rawLine in rawLines {
            if sanitized.count >= lineCap { break }
            let line = String(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            let lower = line.lowercased()
            if lower.hasPrefix("<!doctype") || lower.hasPrefix("<html") || lower.hasPrefix("<body") ||
                lower.contains("</html") || lower.contains("<script") || lower.contains("<style") {
                droppedBlob = true
                continue
            }
            if lower.hasPrefix("authorization:") || lower.hasPrefix("cookie:") || lower.hasPrefix("set-cookie:") {
                sanitized.append("[redacted_sensitive_header]")
                continue
            }
            if lower.hasPrefix("from:") || lower.hasPrefix("to:") || lower.hasPrefix("cc:") ||
                lower.hasPrefix("bcc:") || lower.hasPrefix("reply-to:") || lower.hasPrefix("delivered-to:") {
                sanitized.append("[redacted_message_header]")
                continue
            }
            if line.count > 260 && !line.contains(" ") {
                droppedBlob = true
                continue
            }
            sanitized.append(capText(line, maxChars: 220))
        }

        if sanitized.isEmpty {
            sanitized.append("[sanitized_raw_evidence_omitted]")
        } else if droppedBlob {
            sanitized.append("[sanitized_raw_evidence_truncated]")
        }

        return capText(sanitized.joined(separator: "\n"), maxChars: maxChars)
    }

    private static func normalize(_ raw: String?) -> String {
        (raw ?? "")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func limitLines(_ text: String, maxLines: Int) -> String {
        guard maxLines > 0 else { return "" }
        let lines = text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if lines.count <= maxLines {
            return lines.joined(separator: "\n")
        }
        return lines.prefix(maxLines).joined(separator: "\n") + "\n[sanitized_truncated]"
    }

    private static func capText(_ text: String, maxChars: Int) -> String {
        guard maxChars > 0 else { return "" }
        guard text.count > maxChars else { return text }
        let idx = text.index(text.startIndex, offsetBy: maxChars)
        return String(text[..<idx]) + "…"
    }

    private static func redactSecrets(in input: String) -> String {
        var text = input
        let replacements: [(String, String)] = [
            ("(?is)<private\\b[^>]*>.*?</private\\s*>", "[private omitted]"),
            ("(?i)</?private\\b[^>]*>", "[private omitted]"),
            ("(?is)-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----.*?-----END [A-Z0-9 ]*PRIVATE KEY-----", "[redacted_private_key]"),
            ("sk-[A-Za-z0-9]{20,}", "[redacted_api_key]"),
            ("sk-ant-[A-Za-z0-9_-]{20,}", "[redacted_api_key]"),
            ("gh[pousr]_[A-Za-z0-9]{20,}", "[redacted_token]"),
            ("eyJ[A-Za-z0-9_-]{6,}\\.[A-Za-z0-9_-]{6,}\\.[A-Za-z0-9_-]{6,}", "[redacted_jwt]"),
            ("(?i)bearer\\s+[A-Za-z0-9._-]{16,}", "Bearer [redacted_token]"),
            ("(?i)(password|passwd|pwd|api[_-]?key|secret)\\s*[:=]\\s*[^\\s,;]{4,}", "$1=[redacted]")
        ]
        for (pattern, replacement) in replacements {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { continue }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            text = regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: replacement)
        }
        return text
    }
}
