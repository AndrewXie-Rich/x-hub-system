import Foundation

enum ProviderKeyRuntimeFeedbackSupport {
    static func successFeedback(
        accountKey: String,
        modelID: String,
        tokensUsed: Int64,
        costUsd: Double = 0,
        latencyMs: Int64 = 0,
        occurredAtMs: Int64 = currentTimestampMs()
    ) -> HubProviderKeysClient.ProviderKeyRuntimeFeedback {
        HubProviderKeysClient.ProviderKeyRuntimeFeedback(
            accountKey: accountKey,
            modelID: normalized(modelID),
            outcome: "success",
            httpStatus: 0,
            reasonCode: "",
            statusMessage: "",
            tokensUsed: max(0, tokensUsed),
            costUsd: costUsd,
            latencyMs: max(0, latencyMs),
            occurredAtMs: max(0, occurredAtMs),
            nextRetryAtMs: 0,
            retryAtSource: ""
        )
    }

    static func failureFeedback(
        accountKey: String,
        modelID: String,
        error: Error,
        statusMessage: String? = nil,
        httpStatus: Int? = nil,
        latencyMs: Int64 = 0,
        occurredAtMs: Int64 = currentTimestampMs()
    ) -> HubProviderKeysClient.ProviderKeyRuntimeFeedback {
        let nsError = error as NSError
        let resolvedStatus = httpStatus ?? inferredHTTPStatus(from: nsError)
        let providedMessage = normalized(statusMessage ?? "")
        let message = providedMessage.isEmpty
            ? normalized(nsError.localizedDescription)
            : providedMessage
        let reasonCode = inferredReasonCode(
            rawCode: String(nsError.code),
            statusMessage: message,
            httpStatus: resolvedStatus
        )
        let outcome = inferredOutcome(
            reasonCode: reasonCode,
            statusMessage: message,
            httpStatus: resolvedStatus
        )

        return HubProviderKeysClient.ProviderKeyRuntimeFeedback(
            accountKey: accountKey,
            modelID: normalized(modelID),
            outcome: outcome,
            httpStatus: max(0, resolvedStatus),
            reasonCode: reasonCode,
            statusMessage: message,
            tokensUsed: 0,
            costUsd: 0,
            latencyMs: max(0, latencyMs),
            occurredAtMs: max(0, occurredAtMs),
            nextRetryAtMs: 0,
            retryAtSource: ""
        )
    }

    static func matchesRedactedKey(_ apiKey: String, redacted: String) -> Bool {
        let normalizedAPIKey = normalized(apiKey)
        let normalizedRedacted = normalized(redacted)
        guard !normalizedAPIKey.isEmpty, !normalizedRedacted.isEmpty else { return false }
        guard let separator = normalizedRedacted.range(of: "...") else {
            return normalizedAPIKey == normalizedRedacted
        }
        let prefix = String(normalizedRedacted[..<separator.lowerBound])
        let suffix = String(normalizedRedacted[separator.upperBound...])
        guard normalizedAPIKey.count >= prefix.count + suffix.count else { return false }
        return normalizedAPIKey.hasPrefix(prefix) && normalizedAPIKey.hasSuffix(suffix)
    }

    private static func inferredHTTPStatus(from error: NSError) -> Int {
        if (100...599).contains(error.code) {
            return error.code
        }
        return 0
    }

    private static func inferredReasonCode(
        rawCode: String,
        statusMessage: String,
        httpStatus: Int
    ) -> String {
        let message = statusMessage.lowercased()
        if message.contains("api.responses.write")
            || message.contains("responses.write")
            || message.contains("missing scope")
            || message.contains("缺少生成 scope") {
            return "missing_scope"
        }
        if message.contains("token_expired")
            || message.contains("token has expired")
            || message.contains("authentication token has expired") {
            return "token_expired"
        }
        if message.contains("invalid api key")
            || message.contains("incorrect api key")
            || message.contains("authentication_failed") {
            return "invalid_api_key"
        }
        if message.contains("no api key available")
            || message.contains("api key is empty")
            || message.contains("auth_missing") {
            return "auth_missing"
        }
        if message.contains("input must be a list") {
            return "invalid_request_shape"
        }
        if message.contains("invalid base url") {
            return "invalid_base_url"
        }
        if message.contains("model_not_found")
            || message.contains("no available channel for model")
            || message.contains("model unsupported")
            || message.contains("model_unsupported") {
            return "model_not_supported"
        }
        if message.contains("insufficient_quota")
            || (message.contains("quota") && message.contains("exceeded"))
            || message.contains("额度已用尽") {
            return "quota_exceeded"
        }
        if message.contains("rate limit")
            || message.contains("too many requests")
            || message.contains("rate_limited") {
            return "rate_limited"
        }
        if message.contains("timed out")
            || message.contains("time-out")
            || message.contains("gateway time-out") {
            return "provider_timeout"
        }
        if message.contains("network unreachable")
            || message.contains("network is unreachable")
            || message.contains("could not resolve")
            || message.contains("dns")
            || message.contains("fetch_failed")
            || message.contains("ehostunreach")
            || message.contains("enotfound")
            || message.contains("econnrefused")
            || message.contains("econnreset") {
            return "network_unreachable"
        }

        switch httpStatus {
        case 401, 403:
            return "auth_failed"
        case 402, 429:
            return "quota_exceeded"
        case 408, 504:
            return "provider_timeout"
        case 404:
            return "model_not_supported"
        case 400:
            return "invalid_request"
        default:
            break
        }

        let trimmedCode = normalized(rawCode)
        if let status = Int(trimmedCode), (100...599).contains(status) {
            return "http_\(status)"
        }
        return trimmedCode.isEmpty ? "provider_error" : trimmedCode
    }

    private static func inferredOutcome(
        reasonCode: String,
        statusMessage: String,
        httpStatus: Int
    ) -> String {
        let reason = normalized(reasonCode)
        let message = statusMessage.lowercased()
        if ["missing_scope", "token_expired", "invalid_api_key", "auth_failed"].contains(reason)
            || httpStatus == 401
            || httpStatus == 403 {
            return "auth_error"
        }
        if ["quota_exceeded", "rate_limited"].contains(reason)
            || httpStatus == 402
            || httpStatus == 429 {
            return "quota_error"
        }
        if ["network_unreachable", "provider_timeout"].contains(reason)
            || httpStatus == 408
            || httpStatus == 504
            || message.contains("timed out")
            || message.contains("network unreachable")
            || message.contains("fetch_failed") {
            return "network_error"
        }
        if ["auth_missing", "invalid_base_url", "invalid_request_shape", "invalid_request"].contains(reason)
            || (httpStatus == 400 && reason == "invalid_request") {
            return "config_error"
        }
        return "provider_error"
    }

    private static func normalized(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func currentTimestampMs() -> Int64 {
        Int64((Date().timeIntervalSince1970 * 1000.0).rounded())
    }
}
