import Foundation
import RELFlowHubCore

enum RemoteProviderKeyRuntimeFeedbackRecorder {
    @discardableResult
    static func recordResult(_ result: RemoteModelTrialRunner.TrialResult) -> Bool {
        let accountKey = normalized(result.accountKey)
        guard !accountKey.isEmpty else { return false }

        let event: RemoteProviderKeyRuntimeFeedbackSupport.RuntimeEvent
        if result.ok {
            event = RemoteProviderKeyRuntimeFeedbackSupport.successEvent(
                accountKey: accountKey,
                provider: result.provider,
                modelID: result.modelID,
                tokensUsed: tokensUsed(from: result.usage),
                latencyMs: result.latencyMs,
                occurredAtMs: result.occurredAtMs
            )
        } else {
            let detail = humanizedFailureDetail(status: result.status, error: result.error)
            event = RemoteProviderKeyRuntimeFeedbackSupport.failureProjection(
                accountKey: accountKey,
                provider: result.provider,
                modelID: result.modelID,
                status: result.status,
                error: result.error,
                detail: detail,
                latencyMs: result.latencyMs,
                occurredAtMs: result.occurredAtMs
            ).event
        }

        return record(event)
    }

    @discardableResult
    static func record(_ event: RemoteProviderKeyRuntimeFeedbackSupport.RuntimeEvent) -> Bool {
        guard var raw = readMutableSnapshot(),
              var providers = raw["providers"] as? [String: Any] else {
            return false
        }

        let nowMs = max(Int64(0), event.occurredAtMs > 0 ? event.occurredAtMs : currentTimestampMs())

        for (providerKey, providerValue) in providers {
            guard var providerObject = providerValue as? [String: Any],
                  var accounts = providerObject["accounts"] as? [[String: Any]] else {
                continue
            }

            for index in accounts.indices {
                guard normalized(accounts[index]["account_key"]) == normalized(event.accountKey) else {
                    continue
                }

                if event.outcome == "success" {
                    applySuccess(&accounts[index], event: event, nowMs: nowMs)
                } else {
                    applyFailure(&accounts[index], event: event, nowMs: nowMs)
                }

                providerObject["accounts"] = accounts
                providers[providerKey] = providerObject
                raw["providers"] = providers
                raw["updated_at_ms"] = nowMs
                return writeMutableSnapshot(raw)
            }
        }

        return false
    }

    private static func applySuccess(
        _ account: inout [String: Any],
        event: RemoteProviderKeyRuntimeFeedbackSupport.RuntimeEvent,
        nowMs: Int64
    ) {
        var quota = account["quota"] as? [String: Any] ?? [:]
        let eventTokens = max(Int64(0), event.tokensUsed)
        let currentDailyUsed = int64Value(quota["daily_tokens_used"])
        let currentTotalUsed = int64Value(quota["total_tokens_used"])
        let lastUsedAtMs = int64Value(quota["last_used_at_ms"])
        if !sameUTCDate(lhs: lastUsedAtMs, rhs: nowMs) {
            quota["daily_tokens_used"] = 0
        }
        quota["daily_tokens_used"] = max(Int64(0), int64Value(quota["daily_tokens_used"])) + eventTokens
        quota["total_tokens_used"] = currentTotalUsed + eventTokens
        quota["last_used_at_ms"] = nowMs
        quota["consecutive_errors"] = 0
        quota["cooldown_until_ms"] = 0
        if int64Value(quota["daily_token_cap"]) > 0 {
            quota["daily_tokens_remaining"] = max(
                Int64(0),
                int64Value(quota["daily_token_cap"]) - int64Value(quota["daily_tokens_used"])
            )
        } else if currentDailyUsed == 0 && currentTotalUsed == 0 {
            quota["daily_tokens_remaining"] = int64Value(quota["daily_tokens_remaining"])
        }
        account["quota"] = quota

        var errorState = account["error_state"] as? [String: Any] ?? [:]
        errorState["status"] = "healthy"
        errorState["status_message"] = ""
        errorState["reason_code"] = ""
        errorState["last_error_code"] = ""
        errorState["next_retry_at_ms"] = 0
        errorState["retry_at_source"] = ""
        account["error_state"] = errorState
        account["enabled"] = true

        applyModelState(
            &account,
            modelID: event.modelID,
            state: "ready",
            reasonCode: "",
            statusMessage: "",
            nextRetryAtMs: 0,
            retryAtSource: "",
            lastErrorCode: "",
            lastErrorAtMs: 0,
            updatedAtMs: nowMs
        )
        account["updated_at_ms"] = nowMs
    }

    private static func applyFailure(
        _ account: inout [String: Any],
        event: RemoteProviderKeyRuntimeFeedbackSupport.RuntimeEvent,
        nowMs: Int64
    ) {
        var quota = account["quota"] as? [String: Any] ?? [:]
        var errorState = account["error_state"] as? [String: Any] ?? [:]

        quota["last_error_at_ms"] = nowMs
        quota["consecutive_errors"] = intValue(quota["consecutive_errors"]) + 1

        let status = normalizedStatus(for: event)
        let autoDisabled = inferredAutoDisabled(for: event)
        let retryDecision = ProviderKeyRefreshCoordinator.runtimeFailureDecision(
            for: event,
            accountSupportsRefresh: !normalized(account["refresh_token"]).isEmpty,
            nowMs: nowMs
        )
        let nextRetryAtMs = retryDecision.nextRetryAtMs
        let retryAtSource = retryDecision.retryAtSource

        errorState["status"] = status
        errorState["status_message"] = normalized(retryDecision.statusMessage).isEmpty
            ? (normalized(event.reasonCode).isEmpty ? status : "\(status):\(normalized(event.reasonCode))")
            : normalized(retryDecision.statusMessage)
        errorState["reason_code"] = normalized(event.reasonCode)
        errorState["last_error_code"] = normalized(event.reasonCode)
        errorState["last_error_at_ms"] = nowMs
        errorState["auto_disabled"] = autoDisabled
        errorState["next_retry_at_ms"] = nextRetryAtMs
        errorState["retry_at_source"] = retryAtSource

        if status == "blocked_quota" || status == "rate_limited" {
            quota["cooldown_until_ms"] = max(
                int64Value(quota["cooldown_until_ms"]),
                nextRetryAtMs
            )
            errorState["next_retry_at_ms"] = int64Value(quota["cooldown_until_ms"])
        } else if nextRetryAtMs == 0 {
            quota["cooldown_until_ms"] = 0
        }

        account["quota"] = quota
        account["error_state"] = errorState
        if autoDisabled {
            account["enabled"] = false
        }

        let modelState: String
        if autoDisabled {
            modelState = "disabled"
        } else if nextRetryAtMs > nowMs && ["blocked_quota", "rate_limited", "blocked_network", "blocked_provider"].contains(status) {
            modelState = "cooldown"
        } else {
            modelState = "blocked"
        }

        applyModelState(
            &account,
            modelID: event.modelID,
            state: modelState,
            reasonCode: normalized(event.reasonCode),
            statusMessage: normalized(event.statusMessage),
            nextRetryAtMs: nextRetryAtMs,
            retryAtSource: retryAtSource,
            lastErrorCode: normalized(event.reasonCode),
            lastErrorAtMs: nowMs,
            updatedAtMs: nowMs
        )
        account["updated_at_ms"] = nowMs
    }

    private static func applyModelState(
        _ account: inout [String: Any],
        modelID: String,
        state: String,
        reasonCode: String,
        statusMessage: String,
        nextRetryAtMs: Int64,
        retryAtSource: String,
        lastErrorCode: String,
        lastErrorAtMs: Int64,
        updatedAtMs: Int64
    ) {
        let normalizedModelID = normalized(modelID)
        guard !normalizedModelID.isEmpty else { return }
        var modelStates = account["model_states"] as? [String: Any] ?? [:]
        modelStates[normalizedModelID] = [
            "status": state,
            "reason_code": reasonCode,
            "status_message": statusMessage,
            "next_retry_at_ms": nextRetryAtMs,
            "retry_at_source": retryAtSource,
            "last_error_code": lastErrorCode,
            "last_error_at_ms": lastErrorAtMs,
            "updated_at_ms": updatedAtMs,
        ]
        account["model_states"] = modelStates
    }

    private static func normalizedStatus(
        for event: RemoteProviderKeyRuntimeFeedbackSupport.RuntimeEvent
    ) -> String {
        switch normalized(event.outcome) {
        case "auth_error":
            return "blocked_auth"
        case "quota_error":
            return normalized(event.reasonCode) == "rate_limited" ? "rate_limited" : "blocked_quota"
        case "network_error":
            return "blocked_network"
        case "config_error":
            return "blocked_config"
        default:
            return "blocked_provider"
        }
    }

    private static func inferredAutoDisabled(
        for event: RemoteProviderKeyRuntimeFeedbackSupport.RuntimeEvent
    ) -> Bool {
        let reason = normalized(event.reasonCode)
        if reason == "missing_scope" || reason == "auth_missing" {
            return false
        }
        if event.httpStatus == 401 {
            return true
        }
        return ["auth_failed", "invalid_api_key", "token_expired"].contains(reason)
    }

    private static func humanizedFailureDetail(status: Int, error: String) -> String {
        let normalizedError = error.trimmingCharacters(in: .whitespacesAndNewlines)
        if status > 0 {
            return RemoteProviderClient.userFacingHTTPError(status: status, body: normalizedError)
        }
        if !normalizedError.isEmpty {
            return RemoteProviderClient.humanizedBridgeFailureReason(normalizedError)
        }
        return ""
    }

    private static func tokensUsed(from usage: [String: Any]) -> Int64 {
        let total = int64Value(usage["total_tokens"])
        if total > 0 { return total }
        return max(0, int64Value(usage["prompt_tokens"]) + int64Value(usage["completion_tokens"]))
    }

    private static func sameUTCDate(lhs: Int64, rhs: Int64) -> Bool {
        guard lhs > 0, rhs > 0 else { return false }
        let lhsDate = Date(timeIntervalSince1970: Double(lhs) / 1000.0)
        let rhsDate = Date(timeIntervalSince1970: Double(rhs) / 1000.0)
        let calendar = Calendar(identifier: .gregorian)
        var utc = calendar
        utc.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let lhsComponents = utc.dateComponents([.year, .month, .day], from: lhsDate)
        let rhsComponents = utc.dateComponents([.year, .month, .day], from: rhsDate)
        return lhsComponents.year == rhsComponents.year
            && lhsComponents.month == rhsComponents.month
            && lhsComponents.day == rhsComponents.day
    }

    private static func readMutableSnapshot() -> [String: Any]? {
        let url = storeURL()
        guard let data = try? Data(contentsOf: url),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return raw
    }

    private static func writeMutableSnapshot(_ raw: [String: Any]) -> Bool {
        let destination = storeURL()
        guard let data = try? JSONSerialization.data(withJSONObject: raw, options: [.prettyPrinted, .sortedKeys]) else {
            return false
        }
        let tmp = destination
            .deletingLastPathComponent()
            .appendingPathComponent(".\(destination.lastPathComponent).tmp.\(UUID().uuidString)")

        do {
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: tmp, options: .atomic)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: tmp, to: destination)
            return true
        } catch {
            try? FileManager.default.removeItem(at: tmp)
            return false
        }
    }

    private static func storeURL() -> URL {
        let fileName = "hub_provider_keys.json"
        for base in SharedPaths.hubDirectoryCandidates() {
            let candidate = base.appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return SharedPaths.ensureHubDirectory().appendingPathComponent(fileName)
    }

    private static func intValue(_ any: Any?) -> Int {
        if let value = any as? Int { return value }
        if let value = any as? NSNumber { return value.intValue }
        if let value = any as? Double { return Int(value) }
        return 0
    }

    private static func int64Value(_ any: Any?) -> Int64 {
        if let value = any as? Int64 { return value }
        if let value = any as? Int { return Int64(value) }
        if let value = any as? NSNumber { return value.int64Value }
        if let value = any as? Double { return Int64(value) }
        return 0
    }

    private static func normalized(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalized(_ any: Any?) -> String {
        if let value = any as? String {
            return normalized(value)
        }
        if let value = any as? NSNumber {
            return value.stringValue
        }
        return ""
    }

    private static func currentTimestampMs() -> Int64 {
        Int64((Date().timeIntervalSince1970 * 1000.0).rounded())
    }
}
