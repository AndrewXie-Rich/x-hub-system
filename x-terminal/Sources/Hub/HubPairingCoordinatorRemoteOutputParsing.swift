import Foundation

extension HubPairingCoordinator {
    func emit(
        _ callback: (@Sendable (HubRemoteProgressEvent) -> Void)?,
        _ phase: HubRemoteProgressPhase,
        _ state: HubRemoteProgressState,
        _ detail: String?
    ) {
        callback?(HubRemoteProgressEvent(phase: phase, state: state, detail: detail))
    }

    func normalizedRemoteReasonCode(
        rawReason: String?,
        stepOutput: String,
        fallback: String
    ) -> String {
        Self.normalizedRemoteReasonCode(
            rawReason: rawReason,
            stepOutput: stepOutput,
            fallback: fallback
        )
    }

    nonisolated static func normalizedRemoteReasonCode(
        rawReason: String?,
        stepOutput: String,
        fallback: String
    ) -> String {
        let trimmedRaw = rawReason?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if let sanitized = sanitizedReasonToken(trimmedRaw),
           isCanonicalReasonToken(trimmedRaw) {
            if sanitized == "14_unavailable" {
                return "grpc_unavailable"
            }
            return sanitized
        }

        if !trimmedRaw.isEmpty {
            let inferredFromRaw = inferFailureCodeFromText(trimmedRaw, fallback: fallback)
            if inferredFromRaw != fallback || stepOutput.isEmpty {
                return inferredFromRaw
            }
        }

        return inferFailureCodeFromText(stepOutput, fallback: fallback)
    }

    nonisolated static func sanitizedReasonToken(_ raw: String?) -> String? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return nil }
        var token = trimmed
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
        while token.contains("__") {
            token = token.replacingOccurrences(of: "__", with: "_")
        }
        token = token.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return token.isEmpty ? nil : token
    }

    nonisolated static func isCanonicalReasonToken(_ raw: String) -> Bool {
        guard !raw.isEmpty, raw.count <= 80 else { return false }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
        return raw.rangeOfCharacter(from: allowed.inverted) == nil
    }

    func inferFailureCode(from output: String, fallback: String) -> String {
        Self.inferFailureCodeFromText(output, fallback: fallback)
    }

    nonisolated static func inferFailureCodeFromText(_ output: String, fallback: String) -> String {
        let text = output.lowercased()
        if text.isEmpty { return fallback }
        let looksLikeHTMLPayload = text.contains("<!doctype html")
            || text.contains("<html")
            || text.contains("</html>")
        let looksLikeHTMLServiceOutage = looksLikeHTMLPayload && (
            text.contains("error code 504")
            || text.contains("gateway time-out")
            || text.contains("gateway timeout")
            || text.contains("error code 503")
            || text.contains("service unavailable")
            || text.contains("error code 502")
            || text.contains("bad gateway")
        )
        if looksLikeHTMLServiceOutage || (text.contains("bad_json") && looksLikeHTMLServiceOutage) {
            return "service_unavailable"
        }
        if text.contains("alert certificate required")
            || text.contains("tlsv13 alert certificate required")
            || text.contains("peer did not return a certificate")
            || text.contains("client certificate required")
            || text.contains("certificate required") {
            return "mtls_client_certificate_required"
        }
        if let done = extractRegexGroup(in: text, pattern: #"(?m)^\[done\].*reason=([a-z0-9_.-]+)\s*$"#) {
            return done.replacingOccurrences(of: "-", with: "_")
        }
        if let errCode = extractRegexGroup(in: text, pattern: #"(?m)^\[error\]\s*([a-z0-9_.-]+)\s*:"#) {
            return errCode.replacingOccurrences(of: "-", with: "_")
        }
        if let fromParens = extractParenReason(in: text, prefix: "connect failed (") {
            return fromParens
        }
        if text.contains("bridge_disabled") { return "bridge_disabled" }
        if text.contains("bridge_unavailable") { return "bridge_unavailable" }
        if text.contains("remote_model_not_found") { return "remote_model_not_found" }
        if text.contains("api_key_missing") { return "api_key_missing" }
        if text.contains("base_url_invalid") { return "base_url_invalid" }
        if text.contains("local_network_permission_required") { return localNetworkPermissionRequiredReason }
        if text.contains("local network access denied") { return localNetworkPermissionRequiredReason }
        if text.contains("local_network_discovery_blocked") { return localNetworkDiscoveryBlockedReason }
        if text.contains("token expired")
            || text.contains("token has expired")
            || text.contains("expired token")
            || text.contains("该令牌已过期")
            || text.contains("令牌已过期") {
            return "provider_token_expired"
        }
        if text.contains("grant_required") { return "grant_required" }
        if text.contains("permission_denied") { return "forbidden" }
        if text.contains("node_runtime_killed") || text.contains("node runtime killed") {
            return "node_runtime_killed"
        }
        if text.contains("permission denied") { return "permission_denied" }
        if text.contains("unknown command: discover") { return "discover_unsupported" }
        if text.contains("unknown command: connect") { return "connect_unsupported" }
        if text.contains("source_ip_not_allowed") || text.contains("source ip may not be allowed") {
            return "source_ip_not_allowed"
        }
        if text.contains("connect etimedout") || text.contains(" etimedout ") || text.contains("etimedout") {
            return "tcp_timeout"
        }
        if text.contains("econnrefused") || text.contains("connection refused") {
            return "connection_refused"
        }
        if text.contains("grpc_unavailable") { return "grpc_unavailable" }
        if text.contains("14 unavailable") || text.contains("14_unavailable") {
            return "grpc_unavailable"
        }
        if text.contains("eaddrinuse")
            || text.contains("address already in use")
            || (text.contains("already in use") && text.contains("port")) {
            return "hub_port_conflict"
        }
        if text.contains("no connection established") {
            return "grpc_unavailable"
        }
        if text.contains("failed to connect to all addresses") {
            return "grpc_unavailable"
        }
        if text.contains("killed: 9")
            || text.contains("(exit=137)")
            || text.contains("(exit=134)")
            || text.contains("(exit=139)") {
            return "node_runtime_killed"
        }
        if text.contains("discovery_failed") { return "discovery_failed" }
        if text.contains("pairing_health_failed") { return "pairing_health_failed" }
        if text.contains("grpc_probe_failed") { return "grpc_probe_failed" }
        if text.contains("first_pair_requires_same_lan") { return "first_pair_requires_same_lan" }
        if text.contains("missing_pairing_secret") { return "missing_pairing_secret" }
        if text.contains("invite_token_required") { return "invite_token_required" }
        if text.contains("invite_token_invalid") { return "invite_token_invalid" }
        if text.contains("unauthenticated") { return "unauthenticated" }
        if text.contains("forbidden") || text.contains(" 403") { return "forbidden" }
        if text.contains("timeout waiting for approval") { return "pairing_approval_timeout" }
        if text.contains("local owner approval was cancelled") { return "pairing_owner_auth_cancelled" }
        if text.contains("this mac cannot verify the local hub owner right now")
            || text.contains("local owner authentication failed") {
            return "pairing_owner_auth_failed"
        }
        if text.contains("certificate") || text.contains("tls") { return "tls_error" }
        if text.contains("timeout") { return "timeout" }
        if text.contains("couldn't connect to server") || text.contains("failed to connect to") {
            return "hub_unreachable"
        }
        if text.contains("network is unreachable") { return "network_unreachable" }
        if text.contains("doesn't exist") || text.contains("doesn’t exist") { return "file_not_found" }
        if text.contains("nscocoaerrordomain code=4") { return "file_not_found" }
        if text.contains("not found") { return "not_found" }
        if text.contains("client kit not installed") || text.contains("axhub_client_kit_not_found") {
            return "client_kit_missing"
        }
        return fallback
    }

    nonisolated static func shouldRetryLoopbackTunnelProbe(reasonCode: String) -> Bool {
        switch reasonCode {
        case "timeout", "tcp_timeout", "grpc_unavailable", "connection_refused", "hub_unreachable", "network_unreachable":
            return true
        default:
            return false
        }
    }

    func shouldRetryAfterClientKitInstall(_ output: String) -> Bool {
        let text = output.lowercased()
        return text.contains("client kit not installed")
            || text.contains("axhub_client_kit_not_found")
            || text.contains("client kit not available")
            || text.contains("killed: 9")
            || text.contains("missing node")
    }

    func isUnknownCommand(_ output: String, command: String) -> Bool {
        output.lowercased().contains("unknown command: \(command.lowercased())")
    }

    nonisolated static func parseListModelsResultText(
        _ output: String
    ) -> (models: [HubModel], paidAccessSnapshot: HubRemotePaidAccessSnapshot?) {
        var rows: [HubModel] = []
        var paidAccessSnapshot: HubRemotePaidAccessSnapshot?
        let lines = output.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if let parsedPaidAccess = parseListModelsPaidAccessLine(trimmed) {
                paidAccessSnapshot = parsedPaidAccess
                continue
            }
            guard trimmed.hasPrefix("- ") else { continue }
            let payload = String(trimmed.dropFirst(2))
            let fields = payload.components(separatedBy: "|").map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard fields.count >= 2 else { continue }
            let name = fields[0]
            let modelId = fields[1]
            if modelId.isEmpty { continue }
            let kind = fields.count > 2 ? fields[2] : ""
            let backend = fields.count > 3 ? fields[3] : "unknown"
            let visibility = fields.count > 4 ? fields[4] : ""

            var roles: [String] = ["general"]
            let kindUpper = kind.uppercased()
            if kindUpper.contains("PAID") {
                roles.append("paid")
            } else if kindUpper.contains("LOCAL") {
                roles.append("local")
            }

            let noteParts = [kind, visibility]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            rows.append(
                HubModel(
                    id: modelId,
                    name: name.isEmpty ? modelId : name,
                    backend: backend.isEmpty ? "unknown" : backend,
                    quant: "",
                    contextLength: 8192,
                    paramsB: 0,
                    roles: roles,
                    // ListModels entries from paired Hub are directly routable in remote mode.
                    state: .loaded,
                    memoryBytes: nil,
                    tokensPerSec: nil,
                    modelPath: nil,
                    note: noteParts.isEmpty ? nil : noteParts.joined(separator: " | "),
                    remoteConfiguredContextLength: 8192,
                    remoteKnownContextLength: nil,
                    remoteKnownContextSource: nil
                )
            )
        }
        return (rows, paidAccessSnapshot)
    }

    nonisolated static func parseListModelsPaidAccessLine(
        _ line: String
    ) -> HubRemotePaidAccessSnapshot? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("[paid-access]") else { return nil }
        let payload = trimmed
            .dropFirst("[paid-access]".count)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var fields: [String: String] = [:]
        for token in payload.split(separator: " ") {
            guard let eq = token.firstIndex(of: "=") else { continue }
            let key = String(token[..<eq]).trimmingCharacters(in: .whitespacesAndNewlines)
            let value = String(token[token.index(after: eq)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { continue }
            fields[key] = value
        }

        let trustProfilePresent = parseBoolToken(fields["trust_profile_present"]) ?? false
        let paidModelPolicyMode = {
            let value = fields["paid_model_policy_mode"]?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let value, !value.isEmpty, value != "unspecified" else { return nil as String? }
            return value
        }()

        return HubRemotePaidAccessSnapshot(
            trustProfilePresent: trustProfilePresent,
            paidModelPolicyMode: paidModelPolicyMode,
            dailyTokenLimit: max(0, Int(fields["daily_token_limit"] ?? "") ?? 0),
            singleRequestTokenLimit: max(0, Int(fields["single_request_token_limit"] ?? "") ?? 0)
        )
    }

    nonisolated static func parseBoolToken(_ raw: String?) -> Bool? {
        guard let raw else { return nil }
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "true", "1", "yes", "on":
            return true
        case "false", "0", "no", "off":
            return false
        default:
            return nil
        }
    }

    func extractChatAssistantText(_ output: String) -> String {
        let rawLines = output.components(separatedBy: .newlines)
        var content: [String] = []
        var started = false

        for raw in rawLines {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty {
                if started {
                    content.append("")
                }
                continue
            }

            if line.hasPrefix("Hub connected:")
                || line.hasPrefix("Using model:")
                || line.hasPrefix("Memory:")
                || line.hasPrefix("Usage:")
                || line.hasPrefix("Tips (interactive):")
                || line.hasPrefix("Next:")
                || line.hasPrefix("chat failed:")
                || line.hasPrefix("[grant]")
                || line.hasPrefix("[models]")
                || line.hasPrefix("[quota]")
                || line.hasPrefix("[killswitch]")
                || line.hasPrefix("[req]")
                || line.hasPrefix("[error]")
                || line.hasPrefix("[done]") {
                continue
            }

            started = true
            content.append(raw)
        }

        return content
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func extractParenReason(_ lowerText: String, prefix: String) -> String? {
        Self.extractParenReason(in: lowerText, prefix: prefix)
    }

    nonisolated static func extractParenReason(in lowerText: String, prefix: String) -> String? {
        guard let start = lowerText.range(of: prefix) else { return nil }
        let tail = lowerText[start.upperBound...]
        guard let close = tail.firstIndex(of: ")") else { return nil }
        let raw = String(tail[..<close]).trimmingCharacters(in: .whitespacesAndNewlines)
        let cleaned = raw.replacingOccurrences(of: " ", with: "_")
        return cleaned.isEmpty ? nil : cleaned
    }

    func extractRegexGroup(_ text: String, pattern: String) -> String? {
        Self.extractRegexGroup(in: text, pattern: pattern)
    }

    nonisolated static func extractRegexGroup(in text: String, pattern: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = text as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let m = re.firstMatch(in: text, range: range), m.numberOfRanges >= 2 else { return nil }
        let g = m.range(at: 1)
        guard g.location != NSNotFound, g.length > 0 else { return nil }
        let out = ns.substring(with: g).trimmingCharacters(in: .whitespacesAndNewlines)
        return out.isEmpty ? nil : out
    }

    func parsePortField(_ output: String, fieldName: String) -> Int? {
        let pattern = "(?m)^\\s*" + NSRegularExpression.escapedPattern(for: fieldName) + "\\s*:\\s*([0-9]{1,5})\\s*$"
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = output as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let m = re.firstMatch(in: output, options: [], range: range), m.numberOfRanges > 1 else {
            return nil
        }
        let s = ns.substring(with: m.range(at: 1))
        return Int(s)
    }

    func parseStringField(_ output: String, fieldName: String) -> String? {
        let pattern = "(?m)^\\s*" + NSRegularExpression.escapedPattern(for: fieldName) + "\\s*:\\s*(.+?)\\s*$"
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = output as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let m = re.firstMatch(in: output, options: [], range: range), m.numberOfRanges > 1 else {
            return nil
        }
        let s = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? nil : s
    }
}
