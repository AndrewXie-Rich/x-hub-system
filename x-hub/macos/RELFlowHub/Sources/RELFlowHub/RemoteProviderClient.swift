import Foundation
import Darwin
import RELFlowHubCore

enum RemoteProviderClient {
    enum ProviderError: LocalizedError {
        case missingAPIKey
        case invalidBaseURL
        case httpError(status: Int, body: String)
        case badResponse
        case bridgeFailure(reason: String)

        var errorDescription: String? {
            switch self {
            case .missingAPIKey:
                return "API Key is required."
            case .invalidBaseURL:
                return "Base URL is invalid for this provider."
            case .httpError(let status, let body):
                if body.isEmpty {
                    return "Provider request failed (status=\(status))."
                }
                return "Provider request failed (status=\(status)): \(body)"
            case .badResponse:
                return "Provider returned an unsupported response format."
            case .bridgeFailure(let reason):
                let r = reason.trimmingCharacters(in: .whitespacesAndNewlines)
                return r.isEmpty ? "Bridge request failed." : "Bridge request failed: \(r)"
            }
        }
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
            let obj = try await requestJSON(
                url: url,
                headers: [
                    "x-api-key": key,
                    "anthropic-version": "2023-06-01",
                ],
                timeoutSec: timeoutSec
            )
            let ids = idsFromDataArray(obj)
            guard !ids.isEmpty else {
                throw ProviderError.badResponse
            }
            return uniqSorted(ids)

        case "gemini":
            guard let url = RemoteProviderEndpoints.geminiModelsURL(baseURL: baseURL, apiKey: key) else {
                throw ProviderError.invalidBaseURL
            }
            let obj = try await requestJSON(url: url, headers: [:], timeoutSec: timeoutSec)
            let ids = geminiModelIds(from: obj)
            guard !ids.isEmpty else {
                throw ProviderError.badResponse
            }
            return uniqSorted(ids)

        default:
            guard let url = RemoteProviderEndpoints.openAIModelsURL(baseURL: baseURL, backend: backend) else {
                throw ProviderError.invalidBaseURL
            }
            let obj = try await requestJSON(
                url: url,
                headers: ["Authorization": "Bearer \(key)"],
                timeoutSec: timeoutSec
            )
            let ids = idsFromDataArray(obj)
            guard !ids.isEmpty else {
                throw ProviderError.badResponse
            }
            return uniqSorted(ids)
        }
    }

    private static func requestJSON(url: URL, headers: [String: String], timeoutSec: Double) async throws -> [String: Any] {
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

    private static func parseJSONResponse(data: Data, status: Int) throws -> [String: Any] {
        guard status >= 200 && status < 300 else {
            let body = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw ProviderError.httpError(status: status, body: body)
        }
        guard let obj = (try? JSONSerialization.jsonObject(with: data, options: [])) as? [String: Any] else {
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

    private static func idsFromDataArray(_ obj: [String: Any]) -> [String] {
        guard let list = obj["data"] as? [[String: Any]] else { return [] }
        var out: [String] = []
        for item in list {
            let id = (item["id"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !id.isEmpty {
                out.append(id)
            }
        }
        return out
    }

    private static func geminiModelIds(from obj: [String: Any]) -> [String] {
        guard let models = obj["models"] as? [[String: Any]] else { return [] }
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
