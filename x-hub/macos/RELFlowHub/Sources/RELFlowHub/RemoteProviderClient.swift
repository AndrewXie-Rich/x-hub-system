import Foundation
import Darwin
import RELFlowHubCore

enum RemoteProviderClient {
    struct UsageLimitNotice: Equatable {
        var retryAtText: String?
        var suggestsPlusUpgrade: Bool
    }

    enum ProviderError: LocalizedError {
        case missingAPIKey
        case invalidBaseURL
        case httpError(status: Int, body: String)
        case badResponse
        case emptyResponse
        case bridgeFailure(reason: String)

        var errorDescription: String? {
            switch self {
            case .missingAPIKey:
                return HubUIStrings.Models.ProviderImport.missingAPIKey
            case .invalidBaseURL:
                return HubUIStrings.Models.ProviderImport.invalidBaseURL
            case .httpError(let status, let body):
                return RemoteProviderClient.userFacingHTTPError(status: status, body: body)
            case .badResponse:
                return HubUIStrings.Models.ProviderImport.badResponse
            case .emptyResponse:
                return HubUIStrings.Models.ProviderImport.emptyResponse
            case .bridgeFailure(let reason):
                return HubUIStrings.Models.ProviderImport.bridgeFailure(
                    RemoteProviderClient.humanizedBridgeFailureReason(reason)
                )
            }
        }
    }

    static func userFacingHTTPError(status: Int, body: String) -> String {
        let normalizedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if let usageLimit = usageLimitNotice(from: normalizedBody) {
            if let retryAtText = usageLimit.retryAtText, !retryAtText.isEmpty {
                if usageLimit.suggestsPlusUpgrade {
                    return HubUIStrings.Settings.RemoteModels.usageLimitUpgradeRetryDetail(retryAtText)
                }
                return HubUIStrings.Settings.RemoteModels.usageLimitRetryDetail(retryAtText)
            }
            if usageLimit.suggestsPlusUpgrade {
                return HubUIStrings.Settings.RemoteModels.usageLimitUpgradeDetail
            }
            return HubUIStrings.Settings.RemoteModels.usageLimitDetail
        }
        if let permissionNotice = permissionDeniedNotice(status: status, body: normalizedBody) {
            return permissionNotice
        }
        if isQuotaError(status: status, body: normalizedBody) {
            if normalizedBody.isEmpty {
                return "Provider 配额不足或额度已用尽（status=\(status)）。"
            }
            return "Provider 配额不足或额度已用尽（status=\(status)）：\(normalizedBody)"
        }
        if isRateLimitError(status: status, body: normalizedBody) {
            if normalizedBody.isEmpty {
                return "Provider 当前正在限流，请稍后重试（status=\(status)）。"
            }
            return "Provider 当前正在限流，请稍后重试（status=\(status)）：\(normalizedBody)"
        }
        return HubUIStrings.Models.ProviderImport.httpError(status: status, body: normalizedBody)
    }

    static func usageLimitNotice(from text: String) -> UsageLimitNotice? {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }

        let lowercased = normalized.lowercased()
        let suggestsPlusUpgrade = lowercased.contains("upgrade to plus")
            || lowercased.contains("升级 plus")
        let hasUsageLimitSignal = lowercased.contains("you've hit your usage limit")
            || lowercased.contains("usage limit")
            || lowercased.contains("rate limit resets")
            || lowercased.contains("resets on")
            || lowercased.contains("当前额度已用完")
            || lowercased.contains("额度已用完")

        let retryAtText = firstCapturedGroup(
            in: normalized,
            patterns: [
                #"(?i)try again at\s+([^\n]+?)(?:[。.]?$)"#,
                #"(?i)rate limit resets on\s+([^\n]+?)(?:\.\s*to continue|\.\s*upgrade|[。.]?$)"#,
                #"(?i)resets on\s+([^\n]+?)(?:\.\s*to continue|\.\s*upgrade|[。.]?$)"#,
                #"建议到\s*([^\n]+?)\s*再试"#,
                #"到\s*([^\n]+?)\s*再试"#,
            ]
        )

        guard hasUsageLimitSignal || retryAtText != nil else { return nil }
        return UsageLimitNotice(
            retryAtText: retryAtText?.trimmingCharacters(in: .whitespacesAndNewlines),
            suggestsPlusUpgrade: suggestsPlusUpgrade
        )
    }

    static func humanizedBridgeFailureReason(_ reason: String) -> String {
        let normalized = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        switch normalized {
        case "api_key_missing":
            return "API Key 未设置。"
        case "remote_model_not_found":
            return "Hub 当前没有把这个远程模型挂到可执行面。请先 Load 再试。"
        case "base_url_invalid":
            return "Base URL 无效。"
        case "missing_model_id":
            return "缺少模型 ID。"
        default:
            return normalized
        }
    }

    private static func isQuotaError(status: Int, body: String) -> Bool {
        if usageLimitNotice(from: body) != nil {
            return true
        }
        if status == 402 {
            return true
        }
        let normalized = body.lowercased()
        return normalized.contains("quota")
            || normalized.contains("insufficient_quota")
            || normalized.contains("insufficient quota")
            || normalized.contains("额度")
            || normalized.contains("余额")
            || normalized.contains("credit balance")
            || normalized.contains("billing")
    }

    private static func isRateLimitError(status: Int, body: String) -> Bool {
        let normalized = body.lowercased()
        if normalized.contains("rate limit")
            || normalized.contains("too many requests")
            || normalized.contains("requests per min")
            || normalized.contains("rpm limit")
            || normalized.contains("tpm limit") {
            return true
        }
        return status == 429 && !isQuotaError(status: status, body: body)
    }

    private static func permissionDeniedNotice(status: Int, body: String) -> String? {
        guard status == 401 || status == 403 else { return nil }
        let normalized = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return "Provider 权限不足（status=\(status)）。"
        }

        let lowercased = normalized.lowercased()
        let isPermissionSignal = lowercased.contains("missing scopes")
            || lowercased.contains("insufficient permissions")
            || lowercased.contains("forbidden")
            || lowercased.contains("unauthorized")
        guard isPermissionSignal else { return nil }

        if let scopes = missingScopesList(from: normalized), !scopes.isEmpty {
            if scopes.lowercased().contains("responses.write") {
                return "Provider 权限不足，缺少生成 scope：\(scopes)。请更换具备 Responses 写权限的 key。"
            }
            return "Provider 权限不足，缺少 scope：\(scopes)。"
        }

        return "Provider 权限不足（status=\(status)）：\(normalized)"
    }

    private static func missingScopesList(from text: String) -> String? {
        let captured = firstCapturedGroup(
            in: text,
            patterns: [
                #"(?i)missing scopes?:\s*([^\n]+?)(?:(?:\.\s*check that)|(?:\.\s*please)|[}\"]?$)"#,
                #"(?i)missing scopes?:\s*([^\n]+)"#,
            ]
        )?.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))

        guard let captured, !captured.isEmpty else { return nil }
        return captured
    }

    static func fetchModelIds(
        backend: String,
        apiKey: String,
        baseURL: String?,
        timeoutSec: Double = 12.0
    ) async throws -> [String] {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            throw ProviderError.missingAPIKey
        }

        let b = RemoteProviderEndpoints.normalizedBackend(backend)
        switch b {
        case "anthropic":
            guard let url = RemoteProviderEndpoints.anthropicModelsURL(baseURL: baseURL) else {
                throw ProviderError.invalidBaseURL
            }
            let payload = try await requestJSON(
                url: url,
                headers: [
                    "x-api-key": key,
                    "anthropic-version": "2023-06-01",
                ],
                timeoutSec: timeoutSec
            )
            let ids = modelIds(from: payload, backend: backend)
            guard !ids.isEmpty else {
                throw ProviderError.badResponse
            }
            return uniqSorted(ids)

        case "gemini":
            guard let url = RemoteProviderEndpoints.geminiModelsURL(baseURL: baseURL, apiKey: key) else {
                throw ProviderError.invalidBaseURL
            }
            let payload = try await requestJSON(url: url, headers: [:], timeoutSec: timeoutSec)
            let ids = modelIds(from: payload, backend: backend)
            guard !ids.isEmpty else {
                throw ProviderError.badResponse
            }
            return uniqSorted(ids)

        default:
            guard let url = RemoteProviderEndpoints.openAIModelsURL(baseURL: baseURL, backend: backend) else {
                throw ProviderError.invalidBaseURL
            }
            do {
                let payload = try await requestJSON(
                    url: url,
                    headers: ["Authorization": "Bearer \(key)"],
                    timeoutSec: timeoutSec
                )
                let ids = modelIds(from: payload, backend: backend)
                guard !ids.isEmpty else {
                    throw ProviderError.badResponse
                }
                return uniqSorted(ids)
            } catch {
                let fallback = fallbackModelIdsIfApplicable(
                    backend: backend,
                    baseURL: baseURL,
                    error: error
                )
                if !fallback.isEmpty {
                    return fallback
                }
                throw error
            }
        }
    }

    static func modelIds(from payload: Any, backend: String) -> [String] {
        switch RemoteProviderEndpoints.canonicalBackend(backend) {
        case "gemini":
            return geminiModelIds(from: payload)
        default:
            return genericModelIds(from: payload)
        }
    }

    private static func requestJSON(url: URL, headers: [String: String], timeoutSec: Double) async throws -> Any {
        do {
            let (data, status) = try await requestDataDirect(url: url, headers: headers, timeoutSec: timeoutSec)
            return try parseJSONResponse(data: data, status: status)
        } catch {
            guard shouldUseBridgeFallback(for: error) else {
                throw error
            }

            let bridged: BridgeFetchIPC.FetchResult
            do {
                bridged = try await BridgeFetchIPC.fetch(url: url, headers: headers, timeoutSec: timeoutSec)
            } catch {
                throw error
            }

            if bridged.status == 0 {
                throw ProviderError.bridgeFailure(reason: bridged.error)
            }

            let data = Data(bridged.text.utf8)
            return try parseJSONResponse(data: data, status: bridged.status)
        }
    }

    static func fallbackModelIdsIfApplicable(
        backend: String,
        baseURL: String?,
        error: Error
    ) -> [String] {
        guard CodexModelCatalogFallback.supportsFallback(for: backend),
              shouldUseLocalCatalogFallback(for: error) else {
            return []
        }
        return CodexModelCatalogFallback.modelIDs(backend: backend, baseURL: baseURL)
    }

    private static func requestDataDirect(url: URL, headers: [String: String], timeoutSec: Double) async throws -> (Data, Int) {
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = max(3.0, min(60.0, timeoutSec))
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("RELFlowHub/1.0", forHTTPHeaderField: "User-Agent")
        for (k, v) in headers {
            req.setValue(v, forHTTPHeaderField: k)
        }

        let (data, resp) = try await URLSession.shared.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        return (data, status)
    }

    private static func parseJSONResponse(data: Data, status: Int) throws -> Any {
        guard status >= 200 && status < 300 else {
            let body = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw ProviderError.httpError(status: status, body: body)
        }
        let trimmed = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            throw ProviderError.emptyResponse
        }
        guard let obj = try? JSONSerialization.jsonObject(with: data, options: []) else {
            throw ProviderError.badResponse
        }
        return obj
    }

    private static func shouldUseBridgeFallback(for error: Error) -> Bool {
        let ns = error as NSError
        if isPermissionDenied(ns) {
            return true
        }
        if ns.domain == NSURLErrorDomain {
            if ns.code == URLError.dataNotAllowed.rawValue || ns.code == URLError.cannotLoadFromNetwork.rawValue {
                return true
            }
        }
        return false
    }

    private static func shouldUseLocalCatalogFallback(for error: Error) -> Bool {
        guard let providerError = error as? ProviderError else {
            return false
        }

        switch providerError {
        case .httpError(let status, let body):
            if [404, 405, 410, 422, 501].contains(status) {
                return true
            }
            return isModelReadScopeDenied(status: status, body: body)
        case .badResponse, .emptyResponse:
            return true
        case .missingAPIKey, .invalidBaseURL, .bridgeFailure:
            return false
        }
    }

    private static func isModelReadScopeDenied(status: Int, body: String) -> Bool {
        guard status == 401 || status == 403 else { return false }
        let normalized = body.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return false }
        if normalized.contains("api.model.read") {
            return true
        }
        if normalized.contains("missing scopes") && normalized.contains("model.read") {
            return true
        }
        return normalized.contains("insufficient permissions")
            && normalized.contains("model")
            && normalized.contains("read")
    }

    private static func isPermissionDenied(_ err: NSError) -> Bool {
        if err.domain == NSPOSIXErrorDomain && err.code == Int(EPERM) {
            return true
        }
        let msg = err.localizedDescription.lowercased()
        if msg.contains("operation not permitted") || msg.contains("not permitted") {
            return true
        }
        if let underlying = err.userInfo[NSUnderlyingErrorKey] as? NSError, isPermissionDenied(underlying) {
            return true
        }
        return false
    }

    private static func idsFromEntries(_ list: [Any]) -> [String] {
        var out: [String] = []
        for item in list {
            if let text = item as? String {
                let direct = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !direct.isEmpty {
                    out.append(direct)
                }
                continue
            }

            guard let row = item as? [String: Any] else { continue }
            let id = firstNonEmptyString(
                row["id"],
                row["model_id"],
                row["name"]
            )
            if !id.isEmpty {
                out.append(id)
            }
        }
        return out
    }

    private static func genericModelIds(from payload: Any) -> [String] {
        if let list = payload as? [Any] {
            return idsFromEntries(list)
        }

        guard let obj = payload as? [String: Any] else { return [] }

        for key in ["data", "models", "items", "results"] {
            if let list = obj[key] as? [Any] {
                let ids = idsFromEntries(list)
                if !ids.isEmpty {
                    return ids
                }
            }
        }

        for key in ["result", "response", "payload"] {
            if let nested = obj[key] {
                let ids = genericModelIds(from: nested)
                if !ids.isEmpty {
                    return ids
                }
            }
        }

        return []
    }

    private static func geminiModelIds(from payload: Any) -> [String] {
        guard let obj = payload as? [String: Any],
              let models = obj["models"] as? [[String: Any]] else { return [] }
        var out: [String] = []
        for item in models {
            if let methods = item["supportedGenerationMethods"] as? [String], !methods.isEmpty {
                let supportsGenerate = methods.contains { $0.caseInsensitiveCompare("generateContent") == .orderedSame }
                if !supportsGenerate {
                    continue
                }
            }

            let rawName = (item["name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let id = RemoteProviderEndpoints.stripModelRef(rawName)
            if id.isEmpty { continue }
            out.append(id)
        }
        return out
    }

    private static func firstNonEmptyString(_ values: Any?...) -> String {
        for value in values {
            let normalized: String
            if let string = value as? String {
                normalized = string.trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                normalized = ""
            }
            if !normalized.isEmpty {
                return normalized
            }
        }
        return ""
    }

    private static func firstCapturedGroup(in text: String, patterns: [String]) -> String? {
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
                continue
            }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            guard let match = regex.firstMatch(in: text, options: [], range: range),
                  match.numberOfRanges >= 2,
                  let captureRange = Range(match.range(at: 1), in: text) else {
                continue
            }
            let captured = text[captureRange].trimmingCharacters(in: .whitespacesAndNewlines)
            if !captured.isEmpty {
                return captured
            }
        }
        return nil
    }

    private static func uniqSorted(_ values: [String]) -> [String] {
        var out: [String] = []
        var seen: Set<String> = []
        for raw in values {
            let v = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if v.isEmpty { continue }
            if seen.contains(v) { continue }
            seen.insert(v)
            out.append(v)
        }
        return out.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
}
