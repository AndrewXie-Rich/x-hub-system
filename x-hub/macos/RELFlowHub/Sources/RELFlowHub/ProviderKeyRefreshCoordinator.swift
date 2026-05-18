import Foundation
import RELFlowHubCore

enum ProviderKeyRefreshCoordinator {
    enum RetrySource: String {
        case quota = "quota"
        case providerHeader = "provider_header"
        case usageWindow = "usage_window"
        case scheduler = "scheduler"
        case refresh = "refresh"
        case manual = "manual"
    }

    struct RetryDecision: Equatable {
        var nextRefreshAtMs: Int64 = 0
        var nextRetryAtMs: Int64 = 0
        var retryAtSource: String = ""
        var lastErrorCode: String = ""
        var statusMessage: String = ""
        var retryAtText: String? = nil
    }

    static func retryDecision(
        from detail: String,
        category: ModelTrialCategory? = nil,
        state: RemoteKeyHealthState? = nil,
        credential: ProviderKeyResolvedCredential
    ) async -> RetryDecision? {
        let normalizedDetail = trimmed(detail)
        if let providerRetryText = providerRetryText(from: normalizedDetail) {
            return RetryDecision(
                nextRetryAtMs: parsedRetryAtMs(from: providerRetryText),
                retryAtSource: RetrySource.providerHeader.rawValue,
                lastErrorCode: credential.reasonCode,
                statusMessage: normalizedDetail,
                retryAtText: providerRetryText
            )
        }

        if let preference = usageWindowPreference(
            from: normalizedDetail,
            category: category,
            state: state
        ), let estimate = await CodexUsageService.retryEstimate(
            for: credential,
            preference: preference
        ) {
            return RetryDecision(
                nextRetryAtMs: estimate.retryAtMs,
                retryAtSource: normalizedRetrySource(
                    estimate.retryAtSource,
                    reasonCode: credential.reasonCode,
                    nextRetryAtMs: estimate.retryAtMs
                ),
                lastErrorCode: credential.reasonCode,
                statusMessage: normalizedDetail,
                retryAtText: estimate.retryAtText
            )
        }

        return storedRetryDecision(for: credential, fallbackStatusMessage: normalizedDetail)
    }

    static func runtimeFailureDecision(
        for event: RemoteProviderKeyRuntimeFeedbackSupport.RuntimeEvent,
        accountSupportsRefresh: Bool,
        nowMs: Int64
    ) -> RetryDecision {
        let reasonCode = trimmed(event.reasonCode)
        let statusMessage = trimmed(event.statusMessage)
        let outcome = trimmed(event.outcome).lowercased()
        let providerRetryText = providerRetryText(from: statusMessage)
        let providerRetryAtMs = providerRetryText.map(parsedRetryAtMs(from:)) ?? 0
        if providerRetryAtMs > 0 {
            return RetryDecision(
                nextRetryAtMs: providerRetryAtMs,
                retryAtSource: RetrySource.providerHeader.rawValue,
                lastErrorCode: reasonCode,
                statusMessage: statusMessage,
                retryAtText: providerRetryText
            )
        }

        switch outcome {
        case "quota_error":
            return RetryDecision(
                nextRetryAtMs: nowMs + (15 * 60 * 1000),
                retryAtSource: RetrySource.quota.rawValue,
                lastErrorCode: reasonCode,
                statusMessage: statusMessage,
                retryAtText: providerRetryText
            )
        case "network_error":
            return RetryDecision(
                nextRetryAtMs: nowMs + (5 * 60 * 1000),
                retryAtSource: RetrySource.scheduler.rawValue,
                lastErrorCode: reasonCode,
                statusMessage: statusMessage
            )
        case "provider_error":
            if ["provider_timeout", "network_unreachable"].contains(reasonCode.lowercased()) || event.httpStatus >= 500 {
                return RetryDecision(
                    nextRetryAtMs: nowMs + (5 * 60 * 1000),
                    retryAtSource: RetrySource.scheduler.rawValue,
                    lastErrorCode: reasonCode,
                    statusMessage: statusMessage
                )
            }
            if ["model_not_supported", "model_not_configured", "unsupported_refresh_schema"].contains(reasonCode.lowercased()) {
                return RetryDecision(
                    nextRetryAtMs: 0,
                    retryAtSource: RetrySource.manual.rawValue,
                    lastErrorCode: reasonCode,
                    statusMessage: statusMessage
                )
            }
            return RetryDecision(
                nextRetryAtMs: 0,
                retryAtSource: "",
                lastErrorCode: reasonCode,
                statusMessage: statusMessage
            )
        case "auth_error":
            if reasonCode.lowercased() == "token_expired", accountSupportsRefresh {
                return RetryDecision(
                    nextRetryAtMs: nowMs + (60 * 1000),
                    retryAtSource: RetrySource.refresh.rawValue,
                    lastErrorCode: reasonCode,
                    statusMessage: statusMessage
                )
            }
            return RetryDecision(
                nextRetryAtMs: 0,
                retryAtSource: RetrySource.manual.rawValue,
                lastErrorCode: reasonCode,
                statusMessage: statusMessage
            )
        case "config_error":
            return RetryDecision(
                nextRetryAtMs: 0,
                retryAtSource: RetrySource.manual.rawValue,
                lastErrorCode: reasonCode,
                statusMessage: statusMessage
            )
        default:
            return RetryDecision(
                nextRetryAtMs: 0,
                retryAtSource: "",
                lastErrorCode: reasonCode,
                statusMessage: statusMessage
            )
        }
    }

    static func normalizedRetrySource(
        _ rawSource: String,
        status: String = "",
        reasonCode: String = "",
        nextRetryAtMs: Int64 = 0,
        quotaCooldownUntilMs: Int64 = 0
    ) -> String {
        let normalized = trimmed(rawSource).lowercased()
        switch normalized {
        case "quota_refresh", "codex_usage":
            return RetrySource.usageWindow.rawValue
        case RetrySource.quota.rawValue,
             RetrySource.providerHeader.rawValue,
             RetrySource.usageWindow.rawValue,
             RetrySource.scheduler.rawValue,
             RetrySource.refresh.rawValue,
             RetrySource.manual.rawValue:
            return normalized
        case "refresh_schema":
            return RetrySource.manual.rawValue
        default:
            break
        }

        let normalizedStatus = trimmed(status).lowercased()
        let normalizedReason = trimmed(reasonCode).lowercased()
        if normalizedReason == "token_expired" {
            return RetrySource.refresh.rawValue
        }
        if [
            "missing_scope",
            "scope_missing",
            "auth_missing",
            "model_not_supported",
            "model_not_configured",
            "unsupported_refresh_schema",
        ].contains(normalizedReason)
            || ["blocked_auth", "auth_failed", "blocked_config"].contains(normalizedStatus) {
            return RetrySource.manual.rawValue
        }
        if ["blocked_quota", "rate_limited"].contains(normalizedStatus) || quotaCooldownUntilMs > 0 {
            return max(nextRetryAtMs, quotaCooldownUntilMs) > 0 ? RetrySource.quota.rawValue : ""
        }
        if ["blocked_network", "blocked_provider", "degraded"].contains(normalizedStatus) {
            return nextRetryAtMs > 0 ? RetrySource.scheduler.rawValue : ""
        }
        return ""
    }

    static func formattedRetryText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm 'UTC'"
        return formatter.string(from: date)
    }

    private static func usageWindowPreference(
        from detail: String,
        category: ModelTrialCategory?,
        state: RemoteKeyHealthState?
    ) -> CodexUsageService.ResetTimePreference? {
        if category == .quota || state == .blockedQuota || category == .rateLimit || state == .degraded {
            return .blockingOnly
        }
        if category == .auth || state == .blockedAuth {
            return .anyWindow
        }
        if state == .blockedProvider && isPermissionStyleFailure(detail) {
            return .anyWindow
        }
        if category == .failed && isPermissionStyleFailure(detail) {
            return .anyWindow
        }
        return nil
    }

    private static func isPermissionStyleFailure(_ detail: String) -> Bool {
        let normalized = trimmed(detail).lowercased()
        guard !normalized.isEmpty else { return false }
        return normalized.contains("missing scope")
            || normalized.contains("missing scopes")
            || normalized.contains("scope：")
            || normalized.contains("scope:")
            || normalized.contains("permissions")
            || normalized.contains("permission")
            || normalized.contains("权限不足")
            || normalized.contains("forbidden")
            || normalized.contains("unauthorized")
            || normalized.contains("token_expired")
            || normalized.contains("authentication token has expired")
            || normalized.contains("signing in again")
    }

    private static func providerRetryText(from detail: String) -> String? {
        guard let retryAtText = RemoteProviderClient.usageLimitNotice(from: detail)?.retryAtText else {
            return nil
        }
        let normalized = trimmed(retryAtText)
        return normalized.isEmpty ? nil : normalized
    }

    private static func storedRetryDecision(
        for credential: ProviderKeyResolvedCredential,
        fallbackStatusMessage: String
    ) -> RetryDecision? {
        let nextRetryAtMs = credential.nextRetryAtMs
        guard nextRetryAtMs > 0 else { return nil }
        let retryDate = Date(timeIntervalSince1970: Double(nextRetryAtMs) / 1000.0)
        guard retryDate.timeIntervalSinceNow > -60 else { return nil }
        return RetryDecision(
            nextRetryAtMs: nextRetryAtMs,
            retryAtSource: normalizedRetrySource(
                credential.retryAtSource,
                reasonCode: credential.reasonCode,
                nextRetryAtMs: nextRetryAtMs
            ),
            lastErrorCode: credential.reasonCode,
            statusMessage: fallbackStatusMessage,
            retryAtText: formattedRetryText(retryDate)
        )
    }

    private static func parsedRetryAtMs(from text: String) -> Int64 {
        let normalized = trimmed(text)
        guard !normalized.isEmpty else { return 0 }

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = isoFormatter.date(from: normalized) ?? ISO8601DateFormatter().date(from: normalized) {
            return Int64((date.timeIntervalSince1970 * 1000.0).rounded())
        }

        let utcFormats = [
            "yyyy-MM-dd HH:mm 'UTC'",
            "yyyy-MM-dd'T'HH:mm:ss'Z'",
            "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'",
        ]
        for format in utcFormats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = format
            if let date = formatter.date(from: normalized) {
                return Int64((date.timeIntervalSince1970 * 1000.0).rounded())
            }
        }

        let localFormats = [
            "MMM d, yyyy, h:mm a",
            "MMMM d, yyyy, h:mm a",
            "yyyy-MM-dd HH:mm",
            "yyyy/MM/dd HH:mm",
        ]
        for format in localFormats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = .current
            formatter.dateFormat = format
            if let date = formatter.date(from: normalized) {
                return Int64((date.timeIntervalSince1970 * 1000.0).rounded())
            }
        }

        return 0
    }

    private static func trimmed(_ raw: String?) -> String {
        (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
