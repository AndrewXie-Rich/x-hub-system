import Foundation
import RELFlowHubCore

@MainActor
enum CodexUsageService {
    enum ResetTimePreference {
        case blockingOnly
        case anyWindow
    }

    struct RetryEstimate: Equatable {
        var retryAtMs: Int64
        var retryAtText: String
        var retryAtSource: String
        var isQuotaBlocked: Bool
    }

    static var httpDataOverride: ((URLRequest) async throws -> (Data, HTTPURLResponse))? = nil

    private static let tokenRefreshClientID = "app_EMoamEEZ73f0CkXaXp7hrann"
    private static let usageURLString = "https://chatgpt.com/backend-api/wham/usage"
    private static let tokenRefreshURLString = "https://auth.openai.com/oauth/token"

    private struct UsageWindow {
        var usedPercent: Double
        var resetAfterSeconds: TimeInterval
        var resetAt: Date?

        func resolvedResetDate(now: Date) -> Date? {
            if let resetAt {
                return resetAt
            }
            guard resetAfterSeconds > 0 else { return nil }
            return now.addingTimeInterval(resetAfterSeconds)
        }
    }

    private struct UsageLimit {
        var allowed: Bool
        var limitReached: Bool
        var primaryWindow: UsageWindow?
        var secondaryWindow: UsageWindow?

        var windows: [UsageWindow] {
            [primaryWindow, secondaryWindow].compactMap { $0 }
        }
    }

    private struct RefreshedTokens {
        var accessToken: String
        var refreshToken: String
        var expiresIn: TimeInterval
    }

    private enum UsageError: Error {
        case invalidURL
        case invalidJSON
        case invalidRefreshPayload
        case http(status: Int, body: String)
    }

    static func retryEstimate(
        for credential: ProviderKeyResolvedCredential,
        preference: ResetTimePreference
    ) async -> RetryEstimate? {
        guard supportsUsageQuery(credential) else { return nil }

        do {
            var mutableCredential = credential
            let limit = try await fetchRateLimit(using: &mutableCredential)
            let now = Date()
            let selectedDate: Date?
            let quotaBlockedDate = blockingResetDate(for: limit, now: now)
            switch preference {
            case .blockingOnly:
                selectedDate = quotaBlockedDate
            case .anyWindow:
                selectedDate = quotaBlockedDate ?? nextWindowResetDate(for: limit, now: now)
            }

            guard let selectedDate else { return nil }
            return RetryEstimate(
                retryAtMs: Int64((selectedDate.timeIntervalSince1970 * 1000.0).rounded()),
                retryAtText: formattedRetryText(selectedDate),
                retryAtSource: "usage_window",
                isQuotaBlocked: quotaBlockedDate != nil
            )
        } catch {
            return nil
        }
    }

    private static func supportsUsageQuery(_ credential: ProviderKeyResolvedCredential) -> Bool {
        let accountID = credential.accountId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !accountID.isEmpty else { return false }

        let provider = credential.provider.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch provider {
        case "codex", "openai", "openai_compatible", "remote_catalog":
            return true
        default:
            return credential.authType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "oauth"
        }
    }

    private static func fetchRateLimit(
        using credential: inout ProviderKeyResolvedCredential
    ) async throws -> UsageLimit {
        do {
            let payload = try await fetchUsagePayload(
                accessToken: credential.apiKey,
                accountId: credential.accountId
            )
            return try parseRateLimit(from: payload)
        } catch let error as UsageError {
            guard case .http(let status, _) = error, status == 401 || status == 403 else {
                throw error
            }
            let refreshToken = credential.refreshToken.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !refreshToken.isEmpty else {
                throw error
            }

            let refreshed = try await refreshAccessToken(refreshToken)
            let previousAccessToken = credential.apiKey
            credential.apiKey = refreshed.accessToken
            if !refreshed.refreshToken.isEmpty {
                credential.refreshToken = refreshed.refreshToken
            }
            if refreshed.expiresIn > 0 {
                credential.expiresAtMs = Int64((Date().timeIntervalSince1970 + refreshed.expiresIn) * 1000.0)
            }

            _ = ProviderKeyStorage.updateResolvedCredential(
                accountKey: credential.accountKey,
                apiKey: credential.apiKey,
                refreshToken: credential.refreshToken,
                expiresAtMs: credential.expiresAtMs
            )
            updateRemoteModels(oldAPIKey: previousAccessToken, newAPIKey: credential.apiKey)

            let payload = try await fetchUsagePayload(
                accessToken: credential.apiKey,
                accountId: credential.accountId
            )
            return try parseRateLimit(from: payload)
        }
    }

    private static func fetchUsagePayload(
        accessToken: String,
        accountId: String
    ) async throws -> [String: Any] {
        guard let url = URL(string: usageURLString) else {
            throw UsageError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 12.0
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(accountId, forHTTPHeaderField: "ChatGPT-Account-Id")

        let (data, response) = try await send(request)
        guard response.statusCode < 400 else {
            throw UsageError.http(status: response.statusCode, body: responseBodyText(data))
        }
        guard let payload = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
            throw UsageError.invalidJSON
        }
        return payload
    }

    private static func refreshAccessToken(_ refreshToken: String) async throws -> RefreshedTokens {
        guard let url = URL(string: tokenRefreshURLString) else {
            throw UsageError.invalidURL
        }

        let body: [String: Any] = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": tokenRefreshClientID,
        ]
        guard JSONSerialization.isValidJSONObject(body) else {
            throw UsageError.invalidRefreshPayload
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20.0
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

        let (data, response) = try await send(request)
        guard response.statusCode < 400 else {
            throw UsageError.http(status: response.statusCode, body: responseBodyText(data))
        }
        guard let payload = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
            throw UsageError.invalidRefreshPayload
        }

        let accessToken = stringValue(payload["access_token"])
        let nextRefreshToken = stringValue(payload["refresh_token"])
        let expiresIn = doubleValue(payload["expires_in"])
        guard !accessToken.isEmpty else {
            throw UsageError.invalidRefreshPayload
        }

        return RefreshedTokens(
            accessToken: accessToken,
            refreshToken: nextRefreshToken,
            expiresIn: expiresIn
        )
    }

    private static func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        if let httpDataOverride {
            return try await httpDataOverride(request)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw UsageError.invalidJSON
        }
        return (data, httpResponse)
    }

    private static func parseRateLimit(from payload: [String: Any]) throws -> UsageLimit {
        guard let raw = payload["rate_limit"] as? [String: Any] else {
            throw UsageError.invalidJSON
        }
        return UsageLimit(
            allowed: boolValue(raw["allowed"], default: true),
            limitReached: boolValue(raw["limit_reached"], default: false),
            primaryWindow: parseWindow(raw["primary_window"]),
            secondaryWindow: parseWindow(raw["secondary_window"])
        )
    }

    private static func parseWindow(_ raw: Any?) -> UsageWindow? {
        guard let object = raw as? [String: Any] else { return nil }
        return UsageWindow(
            usedPercent: doubleValue(object["used_percent"]),
            resetAfterSeconds: doubleValue(object["reset_after_seconds"]),
            resetAt: dateValue(object["reset_at"])
        )
    }

    private static func blockingResetDate(for limit: UsageLimit, now: Date) -> Date? {
        let blockedWindows = limit.windows.filter {
            limit.limitReached || !limit.allowed || $0.usedPercent >= 95.0
        }
        let blockedDates = blockedWindows.compactMap { $0.resolvedResetDate(now: now) }
        guard !blockedDates.isEmpty else { return nil }
        return blockedDates.max()
    }

    private static func nextWindowResetDate(for limit: UsageLimit, now: Date) -> Date? {
        limit.windows
            .compactMap { $0.resolvedResetDate(now: now) }
            .filter { $0.timeIntervalSince(now) > 0 }
            .min()
    }

    private static func formattedRetryText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm 'UTC'"
        return formatter.string(from: date)
    }

    private static func updateRemoteModels(oldAPIKey: String, newAPIKey: String) {
        let oldValue = oldAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let newValue = newAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !oldValue.isEmpty, !newValue.isEmpty, oldValue != newValue else { return }

        var snapshot = RemoteModelStorage.load()
        var changed = false
        for index in snapshot.models.indices {
            let current = (snapshot.models[index].apiKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard current == oldValue else { continue }
            snapshot.models[index].apiKey = newValue
            changed = true
        }

        if changed {
            RemoteModelStorage.save(snapshot)
        }
    }

    private static func responseBodyText(_ data: Data) -> String {
        guard !data.isEmpty else { return "" }
        if let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty {
            return text
        }
        return ""
    }

    private static func stringValue(_ raw: Any?) -> String {
        if let value = raw as? String {
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let number = raw as? NSNumber {
            return number.stringValue
        }
        return ""
    }

    private static func doubleValue(_ raw: Any?) -> Double {
        if let value = raw as? Double { return value }
        if let value = raw as? Int { return Double(value) }
        if let value = raw as? Int64 { return Double(value) }
        if let value = raw as? NSNumber { return value.doubleValue }
        if let value = raw as? String, let parsed = Double(value.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return parsed
        }
        return 0
    }

    private static func boolValue(_ raw: Any?, default fallback: Bool) -> Bool {
        if let value = raw as? Bool { return value }
        if let value = raw as? NSNumber { return value.boolValue }
        if let value = raw as? String {
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if normalized == "true" { return true }
            if normalized == "false" { return false }
        }
        return fallback
    }

    private static func dateValue(_ raw: Any?) -> Date? {
        let numeric = doubleValue(raw)
        guard numeric > 0 else { return nil }
        let seconds = numeric > 1_000_000_000_000 ? (numeric / 1000.0) : numeric
        return Date(timeIntervalSince1970: seconds)
    }
}
