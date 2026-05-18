import Foundation
import RELFlowHubCore

enum RemoteProviderKeyBootstrapper {
    private struct AuthVariant {
        var credentials: ProviderAuthImport.ImportedCredentials
        var sourceURL: URL
    }

    private struct InferredOpenAIAccessTokenMetadata {
        var email: String
        var accountID: String
        var expiresAtMs: Int64
        var oauthSourceKey: String
    }

    @discardableResult
    static func bootstrapIfNeeded() -> Bool {
        let remoteModels = RemoteModelStorage.load().models.filter {
            !(($0.apiKey ?? "").trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)).isEmpty
        }
        guard !remoteModels.isEmpty else { return false }

        let current = ProviderKeyStorage.load()
        if current.schemaVersion == "hub_provider_keys.v1",
           current.totalAccounts > 0,
           !formalStoreNeedsMetadataRepair(remoteModels: remoteModels) {
            return false
        }

        let authVariants = authVariantsByAPIKey()
        let groupedModels = Dictionary(grouping: remoteModels, by: bootstrapGroupKey(for:))
        var authDirInputs: [String: [ProviderKeyImportedAccountInput]] = [:]
        var manualInputs: [ProviderKeyImportedAccountInput] = []

        for models in groupedModels.values {
            guard let sample = models.first else { continue }
            let apiKey = (sample.apiKey ?? "").trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            guard !apiKey.isEmpty else { continue }

            let providerModels = Array(Set(models.map {
                ($0.effectiveProviderModelID).trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            }.filter { !$0.isEmpty })).sorted()
            let notes = "Bootstrapped from remote_models.json"

            if let variant = authVariants[apiKey] {
                let sourceDir = variant.sourceURL.deletingLastPathComponent().path
                let input = ProviderKeyImportedAccountInput(
                    provider: providerKeyProvider(for: variant.credentials),
                    email: variant.credentials.email,
                    apiKey: variant.credentials.apiKey,
                    refreshToken: variant.credentials.refreshToken,
                    baseURL: resolvedBaseURL(for: models, fallback: variant.credentials.baseURL),
                    proxyURL: "",
                    enabled: models.contains { $0.enabled },
                    authType: variant.credentials.authType,
                    wireAPI: resolvedWireAPI(for: models, fallback: variant.credentials.wireAPI),
                    expiresAtMs: variant.credentials.expiresAtMs,
                    tier: "",
                    customHeaders: [:],
                    models: providerModels,
                    notes: notes,
                    priority: 0,
                    accountID: variant.credentials.accountID,
                    sourceType: "auth_file",
                    sourceRef: variant.sourceURL.path,
                    oauthSourceKey: variant.credentials.oauthSourceKey,
                    authIndex: variant.credentials.authIndex,
                    sourceOwners: []
                )
                authDirInputs[sourceDir, default: []].append(input)
                continue
            }

            let inferredTokenMetadata = inferredOpenAIAccessTokenMetadata(
                apiKey: apiKey,
                backend: sample.backend
            )
            manualInputs.append(
                ProviderKeyImportedAccountInput(
                    provider: providerKeyProvider(forBackend: sample.backend),
                    email: inferredTokenMetadata?.email ?? "",
                    apiKey: apiKey,
                    refreshToken: "",
                    baseURL: resolvedBaseURL(for: models, fallback: sample.baseURL ?? ""),
                    proxyURL: "",
                    enabled: models.contains { $0.enabled },
                    authType: "api_key",
                    wireAPI: resolvedWireAPI(for: models, fallback: sample.wireAPI ?? ""),
                    expiresAtMs: inferredTokenMetadata?.expiresAtMs ?? 0,
                    tier: "",
                    customHeaders: [:],
                    models: providerModels,
                    notes: notes,
                    priority: 0,
                    accountID: inferredTokenMetadata?.accountID ?? "",
                    sourceType: "",
                    sourceRef: "",
                    oauthSourceKey: inferredTokenMetadata?.oauthSourceKey ?? "",
                    authIndex: 0,
                    sourceOwners: []
                )
            )
        }

        var wroteFormalStore = false

        for (sourceDir, inputs) in authDirInputs {
            let result = ProviderKeyStorage.syncImportedAccounts(
                inputs,
                importSource: ProviderKeyImportSource(kind: "auth_dir", sourceRef: sourceDir)
            )
            if result.ok, (result.importedCount > 0 || result.prunedCount > 0) {
                wroteFormalStore = true
            }
            if !result.ok {
                HubDiagnostics.log("provider_keys.bootstrap auth_dir_failed dir=\(sourceDir) errors=\(result.errors.joined(separator: " | "))")
            }
        }

        if !manualInputs.isEmpty {
            let result = ProviderKeyStorage.syncImportedAccounts(manualInputs)
            if result.ok, (result.importedCount > 0 || result.prunedCount > 0) {
                wroteFormalStore = true
            }
            if !result.ok {
                HubDiagnostics.log("provider_keys.bootstrap manual_failed errors=\(result.errors.joined(separator: " | "))")
            }
        }

        if wroteFormalStore {
            let snapshot = ProviderKeyStorage.load()
            HubDiagnostics.log(
                "provider_keys.bootstrap synced accounts=\(snapshot.totalAccounts) schema=\(snapshot.schemaVersion)"
            )
            NotificationCenter.default.post(name: .relflowhubRemoteKeyHealthChanged, object: nil)
        }

        return wroteFormalStore
    }

    private static func formalStoreNeedsMetadataRepair(remoteModels: [RemoteModelEntry]) -> Bool {
        for model in remoteModels {
            let apiKey = (model.apiKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !apiKey.isEmpty else { continue }
            guard let inferred = inferredOpenAIAccessTokenMetadata(
                apiKey: apiKey,
                backend: model.backend
            ) else {
                continue
            }

            let resolved = ProviderKeyStorage.loadResolvedCredential(
                apiKey: apiKey,
                provider: providerKeyProvider(forBackend: model.backend),
                baseURL: model.baseURL
            )
            guard let resolved else {
                return true
            }
            if resolved.accountId.isEmpty || resolved.oauthSourceKey.isEmpty {
                return true
            }
            if resolved.expiresAtMs <= 0 && inferred.expiresAtMs > 0 {
                return true
            }
        }
        return false
    }

    private static func authVariantsByAPIKey() -> [String: AuthVariant] {
        let authDir = codexHomeDirectory()
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: authDir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return [:]
        }

        let authFiles = entries.filter {
            let name = $0.lastPathComponent.lowercased()
            return $0.pathExtension.lowercased() == "json"
                && name.hasPrefix("auth")
                && name.hasSuffix(".json")
        }

        var variants: [String: AuthVariant] = [:]
        for file in authFiles {
            guard let credentials = try? ProviderAuthImport.load(from: file) else { continue }
            let apiKey = credentials.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !apiKey.isEmpty else { continue }
            let candidate = AuthVariant(credentials: credentials, sourceURL: file)
            if let existing = variants[apiKey] {
                if candidate.credentials.authIndex > existing.credentials.authIndex {
                    variants[apiKey] = candidate
                }
            } else {
                variants[apiKey] = candidate
            }
        }
        return variants
    }

    private static func bootstrapGroupKey(for model: RemoteModelEntry) -> String {
        [
            RemoteProviderEndpoints.canonicalBackend(model.backend),
            (model.baseURL ?? "").trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).lowercased(),
            (model.apiKey ?? "").trimmingCharacters(in: CharacterSet.whitespacesAndNewlines),
        ].joined(separator: "\u{1F}")
    }

    private static func resolvedBaseURL(for models: [RemoteModelEntry], fallback: String) -> String {
        for model in models {
            let value = (model.baseURL ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty {
                return value
            }
        }
        return fallback.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func resolvedWireAPI(for models: [RemoteModelEntry], fallback: String) -> String {
        for model in models {
            let value = (model.wireAPI ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty {
                return value
            }
        }
        return fallback.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func providerKeyProvider(for credentials: ProviderAuthImport.ImportedCredentials) -> String {
        if credentials.kind == .chatGPTTokenBundle {
            return "codex"
        }
        return providerKeyProvider(forBackend: credentials.backend)
    }

    private static func providerKeyProvider(forBackend backend: String) -> String {
        switch RemoteProviderEndpoints.canonicalBackend(backend) {
        case "anthropic":
            return "claude"
        case "gemini":
            return "gemini"
        case "openai", "openai_compatible", "remote_catalog":
            return "openai"
        case "qwen":
            return "qwen"
        case "iflow":
            return "iflow"
        case "kimi":
            return "kimi"
        case "antigravity":
            return "antigravity"
        default:
            return "custom"
        }
    }

    private static func codexHomeDirectory() -> URL {
        let explicit = ProcessInfo.processInfo.environment["XHUB_CODEX_HOME_OVERRIDE"]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !explicit.isEmpty {
            return URL(fileURLWithPath: NSString(string: explicit).expandingTildeInPath, isDirectory: true)
        }

        let env = ProcessInfo.processInfo.environment["CODEX_HOME"]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !env.isEmpty {
            return URL(fileURLWithPath: NSString(string: env).expandingTildeInPath, isDirectory: true)
        }

        return SharedPaths.realHomeDirectory().appendingPathComponent(".codex", isDirectory: true)
    }

    private static func inferredOpenAIAccessTokenMetadata(
        apiKey: String,
        backend: String
    ) -> InferredOpenAIAccessTokenMetadata? {
        let canonicalBackend = RemoteProviderEndpoints.canonicalBackend(backend)
        guard canonicalBackend == "openai" || canonicalBackend == "openai_compatible" || canonicalBackend == "remote_catalog" else {
            return nil
        }

        guard let claims = decodeJWTPayload(apiKey) else {
            return nil
        }

        let authClaims = claims["https://api.openai.com/auth"] as? [String: Any]
        let profileClaims = claims["https://api.openai.com/profile"] as? [String: Any]
        let accountID = firstNonEmpty(
            stringValue(authClaims?["chatgpt_account_id"]),
            stringValue(claims["chatgpt_account_id"]),
            stringValue(claims["account_id"])
        )
        guard !accountID.isEmpty else {
            return nil
        }

        let expiresAtMs = normalizedEpochMs(int64Value(claims["exp"]))
        let email = firstNonEmpty(
            stringValue(profileClaims?["email"]),
            stringValue(claims["email"]),
            stringValue(claims["preferred_username"])
        )
        return InferredOpenAIAccessTokenMetadata(
            email: email,
            accountID: accountID,
            expiresAtMs: expiresAtMs,
            oauthSourceKey: "chatgpt"
        )
    }

    private static func decodeJWTPayload(_ token: String) -> [String: Any]? {
        let segments = token.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count >= 2 else {
            return nil
        }
        return decodeBase64URLJSONObject(String(segments[1]))
    }

    private static func decodeBase64URLJSONObject(_ raw: String) -> [String: Any]? {
        var value = raw
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = value.count % 4
        if remainder != 0 {
            value.append(String(repeating: "=", count: 4 - remainder))
        }
        guard let data = Data(base64Encoded: value),
              let json = try? JSONSerialization.jsonObject(with: data, options: []),
              let object = json as? [String: Any] else {
            return nil
        }
        return object
    }

    private static func stringValue(_ raw: Any?) -> String? {
        if let string = raw as? String {
            return string
        }
        if let number = raw as? NSNumber {
            return number.stringValue
        }
        return nil
    }

    private static func int64Value(_ raw: Any?) -> Int64 {
        if let value = raw as? Int64 {
            return value
        }
        if let value = raw as? Int {
            return Int64(value)
        }
        if let value = raw as? Double {
            return Int64(value.rounded())
        }
        if let value = raw as? NSNumber {
            return value.int64Value
        }
        guard let text = stringValue(raw), let numeric = Double(text) else {
            return 0
        }
        return Int64(numeric.rounded())
    }

    private static func normalizedEpochMs(_ raw: Int64) -> Int64 {
        guard raw > 0 else { return 0 }
        return raw < 1_000_000_000_000 ? raw * 1000 : raw
    }

    private static func firstNonEmpty(_ values: String?...) -> String {
        for value in values {
            let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return ""
    }
}
