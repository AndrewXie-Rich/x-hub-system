import Foundation
import RELFlowHubCore

enum RemoteProviderKeyRuntimeFeedbackSupport {
    struct RuntimeEvent: Equatable {
        var accountKey: String
        var provider: String
        var modelID: String
        var outcome: String
        var httpStatus: Int
        var reasonCode: String
        var statusMessage: String
        var tokensUsed: Int64
        var latencyMs: Int64
        var occurredAtMs: Int64
    }

    struct FailureProjection: Equatable {
        var event: RuntimeEvent
        var category: ModelTrialCategory
        var state: RemoteKeyHealthState
    }

    static func successEvent(
        accountKey: String,
        provider: String,
        modelID: String,
        tokensUsed: Int64,
        latencyMs: Int64,
        occurredAtMs: Int64
    ) -> RuntimeEvent {
        RuntimeEvent(
            accountKey: normalized(accountKey),
            provider: normalized(provider),
            modelID: normalized(modelID),
            outcome: "success",
            httpStatus: 0,
            reasonCode: "",
            statusMessage: "",
            tokensUsed: max(0, tokensUsed),
            latencyMs: max(0, latencyMs),
            occurredAtMs: max(0, occurredAtMs)
        )
    }

    static func failureProjection(
        accountKey: String,
        provider: String,
        modelID: String,
        status: Int,
        error: String,
        detail: String? = nil,
        latencyMs: Int64 = 0,
        occurredAtMs: Int64 = currentTimestampMs()
    ) -> FailureProjection {
        let message = normalized(detail ?? error)
        let reasonCode = inferredReasonCode(
            rawCode: status > 0 ? String(status) : "",
            statusMessage: message,
            httpStatus: status
        )
        let outcome = inferredOutcome(
            reasonCode: reasonCode,
            statusMessage: message,
            httpStatus: status
        )
        let event = RuntimeEvent(
            accountKey: normalized(accountKey),
            provider: normalized(provider),
            modelID: normalized(modelID),
            outcome: outcome,
            httpStatus: max(0, status),
            reasonCode: reasonCode,
            statusMessage: message,
            tokensUsed: 0,
            latencyMs: max(0, latencyMs),
            occurredAtMs: max(0, occurredAtMs)
        )
        let category = projectedCategory(for: event)
        return FailureProjection(
            event: event,
            category: category,
            state: projectedHealthState(for: event, category: category)
        )
    }

    static func projectedCategory(
        status: Int,
        error: String,
        detail: String? = nil
    ) -> ModelTrialCategory {
        failureProjection(
            accountKey: "",
            provider: "",
            modelID: "",
            status: status,
            error: error,
            detail: detail
        ).category
    }

    static func projectedHealthState(
        status: Int,
        error: String,
        detail: String? = nil
    ) -> RemoteKeyHealthState {
        failureProjection(
            accountKey: "",
            provider: "",
            modelID: "",
            status: status,
            error: error,
            detail: detail
        ).state
    }

    static func shouldTryNextCandidate(status: Int, error: String) -> Bool {
        switch projectedCategory(status: status, error: error) {
        case .quota, .rateLimit, .auth:
            return true
        default:
            return false
        }
    }

    private static func projectedCategory(for event: RuntimeEvent) -> ModelTrialCategory {
        let reason = normalized(event.reasonCode)
        let outcome = normalized(event.outcome)

        if outcome == "auth_error" {
            return .auth
        }
        if outcome == "quota_error" {
            return reason == "rate_limited" ? .rateLimit : .quota
        }
        if reason == "provider_timeout" {
            return .timeout
        }
        if outcome == "network_error" {
            return .network
        }
        if outcome == "config_error" {
            return .config
        }
        if reason == "model_not_supported" {
            return .unsupported
        }
        if reason == "runtime_stale" {
            return .runtime
        }
        if event.httpStatus >= 500 {
            return .runtime
        }
        return .failed
    }

    private static func projectedHealthState(
        for event: RuntimeEvent,
        category: ModelTrialCategory
    ) -> RemoteKeyHealthState {
        switch category {
        case .success:
            return .healthy
        case .quota, .rateLimit:
            return .blockedQuota
        case .auth:
            return .blockedAuth
        case .network, .timeout:
            return .blockedNetwork
        case .config:
            return .blockedConfig
        case .unsupported, .runtime, .failed:
            return .blockedProvider
        case .running:
            return .unknownStale
        }
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
            || message.contains("authentication_failed")
            || (message.contains("api key") && (message.contains("无效") || message.contains("撤销") || message.contains("revoked"))) {
            return "invalid_api_key"
        }
        if message.contains("no api key available")
            || message.contains("api key is empty")
            || message.contains("api_key_missing")
            || message.contains("auth_missing") {
            return "auth_missing"
        }
        if message.contains("input must be a list") {
            return "invalid_request_shape"
        }
        if message.contains("invalid base url")
            || message.contains("base_url_invalid") {
            return "invalid_base_url"
        }
        if message.contains("missing_model_id")
            || message.contains("remote_model_not_found") {
            return "model_not_configured"
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
        if message.contains("runtime heartbeat stale") {
            return "runtime_stale"
        }
        if message.contains("bad_json") || message.contains("invalid response") {
            return "provider_bad_response"
        }
        if message.contains("encode_failed") {
            return "invalid_request"
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
        if [
            "auth_missing",
            "invalid_base_url",
            "invalid_request_shape",
            "invalid_request",
            "model_not_configured"
        ].contains(reason) || (httpStatus == 400 && reason == "invalid_request") {
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
