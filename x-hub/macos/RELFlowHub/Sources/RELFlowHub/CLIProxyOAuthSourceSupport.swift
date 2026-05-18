import Foundation
import RELFlowHubCore

enum CLIProxyOAuthSourceSupport {
    static let defaultBaseURL = "http://127.0.0.1:8317"
    @MainActor static var httpDataOverride: (@Sendable (URLRequest) async throws -> (Data, HTTPURLResponse))? = nil

    struct Settings: Codable, Equatable, Sendable {
        var baseURL: String
        var autoSync: Bool
        var lastSyncAtMs: Int64

        init(
            baseURL: String = CLIProxyOAuthSourceSupport.defaultBaseURL,
            autoSync: Bool = true,
            lastSyncAtMs: Int64 = 0
        ) {
            self.baseURL = CLIProxyOAuthSourceSupport.normalizedBaseURLString(baseURL)
            self.autoSync = autoSync
            self.lastSyncAtMs = lastSyncAtMs
        }
    }

    struct RemoteAuthQuota: Equatable, Sendable {
        var exceeded: Bool
        var reason: String
        var backoffLevel: Int
        var nextRecoverAtMs: Int64
    }

    struct RemoteAuthFile: Identifiable, Equatable, Sendable {
        var runtimeAuthIndex: String
        var name: String
        var provider: String
        var label: String
        var email: String
        var account: String
        var accountType: String
        var status: String
        var statusMessage: String
        var disabled: Bool
        var unavailable: Bool
        var runtimeOnly: Bool
        var priority: Int
        var note: String
        var lastRefreshAtMs: Int64
        var nextRefreshAtMs: Int64
        var nextRetryAtMs: Int64
        var quota: RemoteAuthQuota

        var id: String {
            let preferred = runtimeAuthIndex.trimmingCharacters(in: .whitespacesAndNewlines)
            if !preferred.isEmpty {
                return preferred
            }
            let fallback = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !fallback.isEmpty {
                return fallback
            }
            return provider + ":" + email
        }
    }

    struct OAuthLaunch: Equatable, Sendable {
        var provider: OAuthProvider
        var state: String
        var url: URL
    }

    enum OAuthProvider: String, CaseIterable, Identifiable, Sendable {
        case claude
        case codex
        case gemini
        case antigravity
        case kimi

        var id: String { rawValue }

        var title: String {
            switch self {
            case .claude:
                return "Claude"
            case .codex:
                return "Codex"
            case .gemini:
                return "Gemini"
            case .antigravity:
                return "Antigravity"
            case .kimi:
                return "Kimi"
            }
        }

        var endpointPath: String {
            switch self {
            case .claude:
                return "/v0/management/anthropic-auth-url"
            case .codex:
                return "/v0/management/codex-auth-url"
            case .gemini:
                return "/v0/management/gemini-cli-auth-url"
            case .antigravity:
                return "/v0/management/antigravity-auth-url"
            case .kimi:
                return "/v0/management/kimi-auth-url"
            }
        }
    }

    enum OAuthStatus: Equatable, Sendable {
        case waiting
        case completed
        case failed(String)
    }

    struct SyncSummary: Equatable, Sendable {
        var remoteAuths: [RemoteAuthFile]
        var importedCount: Int
        var prunedCount: Int
        var errorMessages: [String]
    }

    enum SupportError: LocalizedError {
        case invalidBaseURL
        case missingManagementKey
        case badResponse
        case httpError(status: Int, body: String)
        case invalidOAuthLaunchResponse
        case syncFailed([String])

        var errorDescription: String? {
            switch self {
            case .invalidBaseURL:
                return "CLIProxy 地址无效。"
            case .missingManagementKey:
                return "请先填写 CLIProxy management key。"
            case .badResponse:
                return "CLIProxy 返回了无法识别的数据。"
            case .httpError(let status, let body):
                let detail = body.trimmingCharacters(in: .whitespacesAndNewlines)
                if detail.isEmpty {
                    return "CLIProxy 管理接口请求失败（status=\(status)）。"
                }
                return "CLIProxy 管理接口请求失败（status=\(status)）：\(detail)"
            case .invalidOAuthLaunchResponse:
                return "CLIProxy OAuth 启动成功，但返回的跳转链接不完整。"
            case .syncFailed(let errors):
                let detail = errors.prefix(3).joined(separator: " | ")
                return detail.isEmpty ? "CLIProxy OAuth 同步失败。" : "CLIProxy OAuth 同步失败：\(detail)"
            }
        }
    }

    static func loadSettings() -> Settings {
        let url = settingsURL()
        guard let data = try? Data(contentsOf: url),
              let settings = try? JSONDecoder().decode(Settings.self, from: data) else {
            return Settings()
        }
        return Settings(
            baseURL: settings.baseURL,
            autoSync: settings.autoSync,
            lastSyncAtMs: settings.lastSyncAtMs
        )
    }

    @discardableResult
    static func saveSettings(_ settings: Settings) -> Bool {
        let normalized = Settings(
            baseURL: settings.baseURL,
            autoSync: settings.autoSync,
            lastSyncAtMs: settings.lastSyncAtMs
        )
        guard let data = try? JSONEncoder().encode(normalized) else {
            return false
        }
        do {
            try data.write(to: settingsURL(), options: .atomic)
            return true
        } catch {
            return false
        }
    }

    static func loadManagementKey(baseURL: String) -> String {
        KeychainStore.get(account: keychainAccount(baseURL: baseURL)) ?? ""
    }

    @discardableResult
    static func saveManagementKey(_ rawValue: String, baseURL: String) -> Bool {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let account = keychainAccount(baseURL: baseURL)
        if value.isEmpty {
            return KeychainStore.delete(account: account)
        }
        return KeychainStore.set(account: account, value: value)
    }

    static func managementConsoleURL(baseURL: String) -> URL? {
        guard var components = URLComponents(string: normalizedBaseURLString(baseURL)) else {
            return nil
        }
        components.path = joinedPath(basePath: components.path, suffix: "/management.html")
        components.fragment = "/oauth"
        return components.url
    }

    static func listRemoteAuths(
        baseURL: String,
        managementKey: String
    ) async throws -> [RemoteAuthFile] {
        let payload = try await requestJSONObject(
            baseURL: baseURL,
            path: "/v0/management/auth-files",
            managementKey: managementKey
        )
        guard let files = payload["files"] as? [[String: Any]] else {
            throw SupportError.badResponse
        }
        return files
            .compactMap(parseRemoteAuthFile(_:))
            .sorted(by: remoteAuthSort(lhs:rhs:))
    }

    static func startOAuth(
        provider: OAuthProvider,
        baseURL: String,
        managementKey: String
    ) async throws -> OAuthLaunch {
        let payload = try await requestJSONObject(
            baseURL: baseURL,
            path: provider.endpointPath,
            queryItems: [URLQueryItem(name: "is_webui", value: "1")],
            managementKey: managementKey
        )
        let state = stringValue(payload["state"])
        let rawURL = stringValue(payload["url"])
        guard !state.isEmpty,
              let url = URL(string: rawURL) else {
            throw SupportError.invalidOAuthLaunchResponse
        }
        return OAuthLaunch(provider: provider, state: state, url: url)
    }

    static func pollOAuthStatus(
        state: String,
        baseURL: String,
        managementKey: String
    ) async throws -> OAuthStatus {
        let payload = try await requestJSONObject(
            baseURL: baseURL,
            path: "/v0/management/get-auth-status",
            queryItems: [URLQueryItem(name: "state", value: state)],
            managementKey: managementKey
        )
        let status = stringValue(payload["status"]).lowercased()
        switch status {
        case "wait":
            return .waiting
        case "ok":
            return .completed
        case "error":
            return .failed(stringValue(payload["error"]))
        default:
            throw SupportError.badResponse
        }
    }

    static func syncAccounts(
        baseURL: String,
        managementKey: String
    ) async throws -> SyncSummary {
        let normalizedBaseURL = normalizedBaseURLString(baseURL)
        let source = ProviderKeyImportSource(kind: "cliproxy_oauth", sourceRef: normalizedBaseURL)
        let ownerKey = importSourceOwnerKey(baseURL: normalizedBaseURL)
        let remoteAuths: [RemoteAuthFile]
        do {
            remoteAuths = try await listRemoteAuths(
                baseURL: normalizedBaseURL,
                managementKey: managementKey
            )
        } catch {
            _ = ProviderKeyStorage.recordImportSourceSyncFailure(source, errors: [error.localizedDescription])
            throw error
        }

        var inputs: [ProviderKeyImportedAccountInput] = []
        var errors: [String] = []

        for auth in remoteAuths {
            if auth.runtimeOnly {
                continue
            }
            do {
                let input = try await importedAccountInput(
                    from: auth,
                    baseURL: normalizedBaseURL,
                    managementKey: managementKey
                )
                inputs.append(input)
            } catch {
                errors.append("\(auth.name): \(error.localizedDescription)")
            }
        }

        if errors.isEmpty {
            let result = ProviderKeyStorage.syncImportedAccounts(inputs, importSource: source)
            guard result.ok else {
                _ = ProviderKeyStorage.recordImportSourceSyncFailure(source, errors: result.errors)
                throw SupportError.syncFailed(result.errors)
            }
            var settings = loadSettings()
            settings.baseURL = normalizedBaseURL
            settings.lastSyncAtMs = currentTimestampMs()
            _ = saveSettings(settings)
            return SyncSummary(
                remoteAuths: remoteAuths,
                importedCount: result.importedCount,
                prunedCount: result.prunedCount,
                errorMessages: []
            )
        }

        if !inputs.isEmpty {
            let partialInputs = inputs.map { input -> ProviderKeyImportedAccountInput in
                var copy = input
                copy.sourceOwners = uniqueStrings(copy.sourceOwners + [ownerKey])
                return copy
            }
            _ = ProviderKeyStorage.syncImportedAccounts(partialInputs)
        }
        _ = ProviderKeyStorage.recordImportSourceSyncFailure(source, errors: errors)
        return SyncSummary(
            remoteAuths: remoteAuths,
            importedCount: inputs.count,
            prunedCount: 0,
            errorMessages: errors
        )
    }

    private static func importedAccountInput(
        from auth: RemoteAuthFile,
        baseURL: String,
        managementKey: String
    ) async throws -> ProviderKeyImportedAccountInput {
        let fileName = auth.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !fileName.isEmpty else {
            throw SupportError.badResponse
        }

        let payloadData = try await requestData(
            baseURL: baseURL,
            path: "/v0/management/auth-files/download",
            queryItems: [URLQueryItem(name: "name", value: fileName)],
            managementKey: managementKey
        )
        let localURL = try saveDownloadedAuthFile(
            data: payloadData,
            baseURL: baseURL,
            fileName: fileName
        )
        let imported = try ProviderAuthImport.parse(data: payloadData)
        let modelIDs = (try? await fetchModelIDs(
            baseURL: baseURL,
            managementKey: managementKey,
            fileName: fileName
        )) ?? []
        let provider = importedAccountProvider(for: auth, imported: imported)
        let normalizedBase = imported.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedBaseURL = normalizedBase.isEmpty
            ? defaultProviderBaseURL(provider)
            : normalizedBase
        let resolvedStatusMessage = firstNonEmpty(
            auth.statusMessage,
            auth.quota.reason,
            auth.note
        )

        return ProviderKeyImportedAccountInput(
            provider: provider,
            email: firstNonEmpty(imported.email, auth.email),
            apiKey: imported.apiKey,
            refreshToken: imported.refreshToken,
            baseURL: resolvedBaseURL,
            proxyURL: "",
            enabled: !auth.disabled,
            authType: imported.authType.isEmpty ? "oauth" : imported.authType,
            wireAPI: imported.wireAPI,
            expiresAtMs: imported.expiresAtMs,
            tier: "",
            customHeaders: [:],
            models: modelIDs,
            notes: "Imported from CLIProxy OAuth",
            priority: max(0, auth.priority),
            accountID: firstNonEmpty(imported.accountID, auth.account),
            sourceType: "auth_file",
            sourceRef: localURL.path,
            oauthSourceKey: imported.oauthSourceKey.isEmpty ? normalizedProviderHint(auth.provider) : imported.oauthSourceKey,
            authIndex: stableAuthIndex(auth.runtimeAuthIndex, fallback: fileName),
            runtimeAuthIndex: auth.runtimeAuthIndex,
            runtimeStatus: normalizedRuntimeStatus(auth),
            statusMessage: resolvedStatusMessage,
            reasonCode: auth.quota.exceeded ? "quota_exceeded" : "",
            nextRetryAtMs: auth.nextRetryAtMs,
            lastRefreshAtMs: auth.lastRefreshAtMs,
            refreshStatus: normalizedRefreshStatus(auth),
            nextRefreshAtMs: auth.nextRefreshAtMs,
            quotaReason: auth.quota.reason,
            quotaNextRecoverAtMs: auth.quota.nextRecoverAtMs,
            sourceOwners: []
        )
    }

    private static func fetchModelIDs(
        baseURL: String,
        managementKey: String,
        fileName: String
    ) async throws -> [String] {
        let payload = try await requestJSONObject(
            baseURL: baseURL,
            path: "/v0/management/auth-files/models",
            queryItems: [URLQueryItem(name: "name", value: fileName)],
            managementKey: managementKey
        )
        guard let models = payload["models"] as? [[String: Any]] else {
            return []
        }
        return uniqueStrings(
            models.compactMap { stringValue($0["id"]) }
        )
    }

    private static func parseRemoteAuthFile(_ raw: [String: Any]) -> RemoteAuthFile? {
        let name = stringValue(raw["name"])
        let provider = normalizedProviderHint(
            firstNonEmpty(
                stringValue(raw["provider"]),
                stringValue(raw["type"])
            )
        )
        guard !name.isEmpty, !provider.isEmpty else {
            return nil
        }

        let quotaRaw = raw["quota"] as? [String: Any] ?? [:]
        return RemoteAuthFile(
            runtimeAuthIndex: firstNonEmpty(
                stringValue(raw["auth_index"]),
                stringValue(raw["id"])
            ),
            name: name,
            provider: provider,
            label: stringValue(raw["label"]),
            email: stringValue(raw["email"]),
            account: stringValue(raw["account"]),
            accountType: stringValue(raw["account_type"]),
            status: stringValue(raw["status"]),
            statusMessage: stringValue(raw["status_message"]),
            disabled: boolValue(raw["disabled"]),
            unavailable: boolValue(raw["unavailable"]),
            runtimeOnly: boolValue(raw["runtime_only"]),
            priority: intValue(raw["priority"]),
            note: stringValue(raw["note"]),
            lastRefreshAtMs: dateLikeToMs(raw["last_refresh"]),
            nextRefreshAtMs: dateLikeToMs(raw["next_refresh_after"]),
            nextRetryAtMs: dateLikeToMs(raw["next_retry_after"]),
            quota: RemoteAuthQuota(
                exceeded: boolValue(quotaRaw["exceeded"]),
                reason: stringValue(quotaRaw["reason"]),
                backoffLevel: intValue(quotaRaw["backoff_level"]),
                nextRecoverAtMs: dateLikeToMs(quotaRaw["next_recover_at"])
            )
        )
    }

    private static func remoteAuthSort(lhs: RemoteAuthFile, rhs: RemoteAuthFile) -> Bool {
        let lhsProvider = lhs.provider.localizedLowercase
        let rhsProvider = rhs.provider.localizedLowercase
        if lhsProvider != rhsProvider {
            return lhsProvider < rhsProvider
        }

        let lhsIdentity = firstNonEmpty(lhs.email, lhs.label, lhs.name).localizedLowercase
        let rhsIdentity = firstNonEmpty(rhs.email, rhs.label, rhs.name).localizedLowercase
        if lhsIdentity != rhsIdentity {
            return lhsIdentity < rhsIdentity
        }

        return lhs.name.localizedLowercase < rhs.name.localizedLowercase
    }

    private static func requestJSONObject(
        baseURL: String,
        path: String,
        queryItems: [URLQueryItem] = [],
        managementKey: String
    ) async throws -> [String: Any] {
        let data = try await requestData(
            baseURL: baseURL,
            path: path,
            queryItems: queryItems,
            managementKey: managementKey
        )
        guard let payload = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
            throw SupportError.badResponse
        }
        return payload
    }

    private static func requestData(
        baseURL: String,
        path: String,
        queryItems: [URLQueryItem] = [],
        managementKey: String
    ) async throws -> Data {
        let key = managementKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            throw SupportError.missingManagementKey
        }

        guard let url = managementURL(baseURL: baseURL, path: path, queryItems: queryItems) else {
            throw SupportError.invalidBaseURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")

        let (data, response): (Data, HTTPURLResponse)
        let override = await MainActor.run { httpDataOverride }
        if let override {
            (data, response) = try await override(request)
        } else {
            let result = try await URLSession.shared.data(for: request)
            guard let httpResponse = result.1 as? HTTPURLResponse else {
                throw SupportError.badResponse
            }
            data = result.0
            response = httpResponse
        }

        guard (200..<300).contains(response.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw SupportError.httpError(status: response.statusCode, body: body)
        }
        return data
    }

    private static func managementURL(
        baseURL: String,
        path: String,
        queryItems: [URLQueryItem]
    ) -> URL? {
        guard var components = URLComponents(string: normalizedBaseURLString(baseURL)) else {
            return nil
        }
        components.path = joinedPath(basePath: components.path, suffix: path)
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        components.fragment = nil
        return components.url
    }

    private static func joinedPath(basePath: String, suffix: String) -> String {
        let prefix = basePath.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/+$", with: "", options: .regularExpression)
        let tail = suffix.trimmingCharacters(in: .whitespacesAndNewlines)
        if prefix.isEmpty {
            return tail.hasPrefix("/") ? tail : "/" + tail
        }
        if tail.isEmpty {
            return prefix
        }
        return prefix + (tail.hasPrefix("/") ? tail : "/" + tail)
    }

    private static func saveDownloadedAuthFile(
        data: Data,
        baseURL: String,
        fileName: String
    ) throws -> URL {
        let directory = authStorageDirectory(baseURL: baseURL)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(safePathComponent(fileName))
        try data.write(to: url, options: .atomic)
        return url
    }

    private static func authStorageDirectory(baseURL: String) -> URL {
        SharedPaths.ensureHubDirectory()
            .appendingPathComponent("cliproxy_oauth", isDirectory: true)
            .appendingPathComponent(safePathComponent(normalizedBaseURLString(baseURL)), isDirectory: true)
    }

    private static func settingsURL() -> URL {
        SharedPaths.ensureHubDirectory().appendingPathComponent("hub_cliproxy_oauth_source.json")
    }

    private static func keychainAccount(baseURL: String) -> String {
        "cliproxy_oauth.management_key.\(normalizedBaseURLString(baseURL))"
    }

    private static func importSourceOwnerKey(baseURL: String) -> String {
        "cliproxy_oauth:\(normalizedBaseURLString(baseURL))"
    }

    static func normalizedBaseURLString(_ rawValue: String) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = trimmed.isEmpty ? defaultBaseURL : trimmed
        let withScheme = candidate.contains("://") ? candidate : "http://\(candidate)"
        guard var components = URLComponents(string: withScheme),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = components.host?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !host.isEmpty else {
            return defaultBaseURL
        }

        components.scheme = scheme
        components.host = host
        components.user = nil
        components.password = nil
        components.query = nil
        components.fragment = nil

        if (scheme == "http" && components.port == 80)
            || (scheme == "https" && components.port == 443) {
            components.port = nil
        }

        var path = components.path.trimmingCharacters(in: .whitespacesAndNewlines)
        if path == "/" {
            path = ""
        }
        while path.hasSuffix("/") {
            path.removeLast()
        }
        components.path = path

        return components.string ?? defaultBaseURL
    }

    private static func normalizedProviderHint(_ rawValue: String) -> String {
        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "anthropic", "claude":
            return "claude"
        case "gemini", "gemini-cli", "google":
            return "gemini"
        case "chatgpt", "openai", "codex":
            return "codex"
        case "antigravity":
            return "antigravity"
        case "kimi":
            return "kimi"
        default:
            return normalized
        }
    }

    private static func importedAccountProvider(
        for auth: RemoteAuthFile,
        imported: ProviderAuthImport.ImportedCredentials
    ) -> String {
        if imported.kind == .chatGPTTokenBundle {
            return "codex"
        }

        let authProvider = normalizedProviderHint(auth.provider)
        if !authProvider.isEmpty {
            return authProvider
        }

        switch RemoteProviderEndpoints.canonicalBackend(imported.backend) {
        case "anthropic":
            return "claude"
        case "gemini":
            return "gemini"
        case "kimi":
            return "kimi"
        case "antigravity":
            return "antigravity"
        case "openai":
            return "codex"
        default:
            return "custom"
        }
    }

    private static func defaultProviderBaseURL(_ provider: String) -> String {
        switch normalizedProviderHint(provider) {
        case "claude":
            return "https://api.anthropic.com/v1"
        case "gemini":
            return "https://generativelanguage.googleapis.com/v1beta"
        case "antigravity":
            return "https://cloudcode-pa.googleapis.com/v1internal"
        case "kimi":
            return "https://api.moonshot.cn/v1"
        case "codex":
            return "https://api.openai.com/v1"
        default:
            return ""
        }
    }

    private static func normalizedRuntimeStatus(_ auth: RemoteAuthFile) -> String {
        if auth.disabled {
            return "disabled"
        }
        let status = auth.status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if status == "active" || status == "ok" {
            return auth.unavailable ? "error" : "ready"
        }
        if status.isEmpty {
            return auth.unavailable ? "error" : "ready"
        }
        return status
    }

    private static func normalizedRefreshStatus(_ auth: RemoteAuthFile) -> String {
        let status = auth.status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if status == "refreshing" {
            return "refreshing"
        }
        if auth.nextRefreshAtMs > 0 {
            return "scheduled"
        }
        if auth.lastRefreshAtMs > 0 {
            return "ready"
        }
        return "idle"
    }

    private static func stableAuthIndex(_ rawValue: String, fallback: String) -> Int {
        let preferred = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let seed = preferred.isEmpty ? fallback.trimmingCharacters(in: .whitespacesAndNewlines) : preferred
        guard !seed.isEmpty else { return 0 }
        var result: UInt64 = 1_469_598_103_934_665_603
        for byte in seed.utf8 {
            result ^= UInt64(byte)
            result &*= 1_099_511_628_211
        }
        return Int((result % 1_999_999_999) + 1)
    }

    private static func safePathComponent(_ rawValue: String) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "default" }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.@")
        let mapped = trimmed.unicodeScalars.map { scalar -> Character in
            allowed.contains(scalar) ? Character(scalar) : "_"
        }
        let collapsed = String(mapped).replacingOccurrences(of: "_+", with: "_", options: .regularExpression)
        return collapsed.isEmpty ? "default" : collapsed
    }

    private static func dateLikeToMs(_ rawValue: Any?) -> Int64 {
        if let value = rawValue as? Int64 {
            return normalizedEpochMs(value)
        }
        if let value = rawValue as? Int {
            return normalizedEpochMs(Int64(value))
        }
        if let value = rawValue as? Double {
            return normalizedEpochMs(Int64(value.rounded()))
        }
        if let date = rawValue as? Date {
            return Int64((date.timeIntervalSince1970 * 1000.0).rounded())
        }
        let text = stringValue(rawValue)
        if text.isEmpty {
            return 0
        }
        if let numeric = Double(text) {
            return normalizedEpochMs(Int64(numeric.rounded()))
        }
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: text) else {
            return 0
        }
        return Int64((date.timeIntervalSince1970 * 1000.0).rounded())
    }

    private static func normalizedEpochMs(_ rawValue: Int64) -> Int64 {
        guard rawValue > 0 else { return 0 }
        return rawValue < 1_000_000_000_000 ? rawValue * 1000 : rawValue
    }

    private static func currentTimestampMs() -> Int64 {
        Int64((Date().timeIntervalSince1970 * 1000.0).rounded())
    }

    private static func boolValue(_ rawValue: Any?) -> Bool {
        if let value = rawValue as? Bool {
            return value
        }
        if let value = rawValue as? NSNumber {
            return value.boolValue
        }
        let text = stringValue(rawValue).lowercased()
        return text == "1" || text == "true" || text == "yes" || text == "on"
    }

    private static func intValue(_ rawValue: Any?) -> Int {
        if let value = rawValue as? Int {
            return value
        }
        if let value = rawValue as? Int64 {
            return Int(value)
        }
        if let value = rawValue as? Double {
            return Int(value)
        }
        if let value = rawValue as? NSNumber {
            return value.intValue
        }
        return 0
    }

    private static func stringValue(_ rawValue: Any?) -> String {
        if let value = rawValue as? String {
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let value = rawValue as? NSNumber {
            return value.stringValue
        }
        return ""
    }

    private static func firstNonEmpty(_ values: String...) -> String {
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return ""
    }

    private static func uniqueStrings(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var out: [String] = []
        for rawValue in values {
            let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { continue }
            guard seen.insert(value).inserted else { continue }
            out.append(value)
        }
        return out
    }
}
