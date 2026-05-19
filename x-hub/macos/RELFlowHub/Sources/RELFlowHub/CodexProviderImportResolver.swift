import Foundation
import RELFlowHubCore

enum CodexProviderImportResolver {
    private static let codexHomeOverrideEnvKey = "XHUB_CODEX_HOME_OVERRIDE"

    struct ResolvedCredentialVariant: Equatable {
        var credentials: ProviderAuthImport.ImportedCredentials
        var sourceURL: URL?
    }

    struct ResolvedImport: Equatable {
        var credentials: ProviderAuthImport.ImportedCredentials?
        var credentialVariants: [ResolvedCredentialVariant]
        var providerConfig: ProviderConfigImport.ImportedProviderConfig?
    }

    static func resolveAuthImport(from authURL: URL) throws -> ResolvedImport {
        let credentials = try ProviderAuthImport.load(from: authURL)
        let providerConfig = resolvedProviderConfig(
            forAuthURL: authURL,
            credentials: credentials
        )
        return ResolvedImport(
            credentials: mergedCredentials(
                credentials,
                providerConfig: providerConfig,
                forceProviderOverlay: false
            ),
            credentialVariants: [
                ResolvedCredentialVariant(
                    credentials: mergedCredentials(
                        credentials,
                        providerConfig: providerConfig,
                        forceProviderOverlay: false
                    ),
                    sourceURL: authURL
                )
            ],
            providerConfig: providerConfig
        )
    }

    static func resolveConfigImport(from configURL: URL) throws -> ResolvedImport {
        let initialConfig = try ProviderConfigImport.load(from: configURL)
        let companionCredentials = companionCredentials(forConfigURL: configURL)
        let providerConfig = resolvedProviderConfig(
            forConfigURL: configURL,
            initialConfig: initialConfig,
            credentials: companionCredentials.first?.credentials
        )
        let mergedVariants = companionCredentials.map {
            ResolvedCredentialVariant(
                credentials: mergedCredentials(
                    $0.credentials,
                    providerConfig: providerConfig,
                    forceProviderOverlay: true
                ),
                sourceURL: $0.sourceURL
            )
        }
        return ResolvedImport(
            credentials: mergedVariants.first?.credentials,
            credentialVariants: mergedVariants,
            providerConfig: providerConfig
        )
    }

    static func inferredOpenAIWireAPI(backend: String, baseURL: String?) -> RemoteProviderWireAPI? {
        guard supportsOpenAICompatibility(backend: backend) else { return nil }
        let candidates = providerConfigCandidates(
            alongside: nil,
            allowActiveCodexHome: true
        )
        let requestedBaseURL = normalizedBaseURL(baseURL)
        guard !requestedBaseURL.isEmpty else { return nil }

        for candidate in candidates {
            guard let config = loadProviderConfig(from: candidate, requireExplicitProvider: true) else {
                continue
            }
            if normalizedBaseURL(config.baseURL) == requestedBaseURL {
                return RemoteProviderEndpoints.normalizedWireAPI(config.wireAPI)
            }
        }
        return nil
    }

    private static func resolvedProviderConfig(
        forAuthURL authURL: URL,
        credentials: ProviderAuthImport.ImportedCredentials
    ) -> ProviderConfigImport.ImportedProviderConfig? {
        let sameDirectoryCandidates = providerConfigCandidates(
            alongside: authURL,
            allowActiveCodexHome: false
        )

        for candidate in sameDirectoryCandidates {
            if let explicitConfig = loadProviderConfig(from: candidate, requireExplicitProvider: true) {
                return explicitConfig
            }
        }

        if credentials.kind == .chatGPTTokenBundle,
           let activeConfig = activeCodexExplicitProviderConfig() {
            return activeConfig
        }

        for candidate in sameDirectoryCandidates {
            if let config = loadProviderConfig(from: candidate, requireExplicitProvider: false) {
                return config
            }
        }

        return nil
    }

    private static func resolvedProviderConfig(
        forConfigURL configURL: URL,
        initialConfig: ProviderConfigImport.ImportedProviderConfig,
        credentials: ProviderAuthImport.ImportedCredentials?
    ) -> ProviderConfigImport.ImportedProviderConfig {
        if initialConfig.source == .explicitProvider {
            return initialConfig
        }

        for candidate in providerConfigCandidates(alongside: configURL, allowActiveCodexHome: false) {
            guard candidate.standardizedFileURL.path != configURL.standardizedFileURL.path else {
                continue
            }
            if let explicitConfig = loadProviderConfig(from: candidate, requireExplicitProvider: true) {
                return explicitConfig
            }
        }

        if credentials?.kind == .chatGPTTokenBundle,
           let activeConfig = activeCodexExplicitProviderConfig() {
            return activeConfig
        }

        return initialConfig
    }

    private static func companionCredentials(forConfigURL configURL: URL) -> [ResolvedCredentialVariant] {
        var collected: [ResolvedCredentialVariant] = []
        var seen: Set<String> = []
        for candidate in authCandidates(alongside: configURL) {
            if let credential = try? ProviderAuthImport.load(from: candidate) {
                let signature = credentialSignature(credential)
                guard seen.insert(signature).inserted else { continue }
                collected.append(
                    ResolvedCredentialVariant(
                        credentials: credential,
                        sourceURL: candidate
                    )
                )
            }
        }
        return collected
    }

    private static func activeCodexExplicitProviderConfig() -> ProviderConfigImport.ImportedProviderConfig? {
        loadProviderConfig(
            from: codexHomeDirectory().appendingPathComponent("config.toml", isDirectory: false),
            requireExplicitProvider: true
        )
    }

    private static func mergedCredentials(
        _ credentials: ProviderAuthImport.ImportedCredentials,
        providerConfig: ProviderConfigImport.ImportedProviderConfig?,
        forceProviderOverlay: Bool
    ) -> ProviderAuthImport.ImportedCredentials {
        guard let providerConfig else { return credentials }
        if forceProviderOverlay {
            var merged = credentials
            merged.backend = providerConfig.backend
            merged.baseURL = providerConfig.baseURL
            merged.apiKeyRef = providerConfig.apiKeyRef
            let normalizedWireAPI = preferredWireAPI(
                credentials: credentials,
                providerConfig: providerConfig
            )
            if !normalizedWireAPI.isEmpty {
                merged.wireAPI = normalizedWireAPI
            }
            return merged
        }
        guard shouldOverlayProviderMetadata(
            onto: credentials,
            providerConfig: providerConfig
        ) else {
            return credentials
        }

        var merged = credentials
        merged.backend = providerConfig.backend
        merged.baseURL = providerConfig.baseURL
        merged.apiKeyRef = providerConfig.apiKeyRef
        let normalizedWireAPI = preferredWireAPI(
            credentials: credentials,
            providerConfig: providerConfig
        )
        if !normalizedWireAPI.isEmpty {
            merged.wireAPI = normalizedWireAPI
        }
        return merged
    }

    private static func preferredWireAPI(
        credentials: ProviderAuthImport.ImportedCredentials,
        providerConfig: ProviderConfigImport.ImportedProviderConfig
    ) -> String {
        let configWireAPI = providerConfig.wireAPI.trimmingCharacters(in: .whitespacesAndNewlines)
        if credentials.kind == .chatGPTTokenBundle,
           providerConfig.source == .fallbackOpenAI,
           RemoteProviderEndpoints.normalizedWireAPI(configWireAPI) == .responses {
            let credentialWireAPI = credentials.wireAPI.trimmingCharacters(in: .whitespacesAndNewlines)
            if !credentialWireAPI.isEmpty {
                return credentialWireAPI
            }
        }
        return configWireAPI
    }

    private static func shouldOverlayProviderMetadata(
        onto credentials: ProviderAuthImport.ImportedCredentials,
        providerConfig: ProviderConfigImport.ImportedProviderConfig
    ) -> Bool {
        if credentials.kind == .chatGPTTokenBundle {
            return true
        }

        let credentialBaseURL = normalizedBaseURL(credentials.baseURL)
        if credentialBaseURL.isEmpty {
            return true
        }

        let configBaseURL = normalizedBaseURL(providerConfig.baseURL)
        if configBaseURL.isEmpty {
            return false
        }

        return credentialBaseURL == configBaseURL
    }

    private static func providerConfigCandidates(
        alongside url: URL?,
        allowActiveCodexHome: Bool
    ) -> [URL] {
        var candidates: [URL] = []
        if let url {
            if let pairedConfig = pairedConfigCandidate(forAuthURL: url) {
                candidates.append(pairedConfig)
            }
            candidates.append(url.deletingLastPathComponent().appendingPathComponent("config.toml", isDirectory: false))
        }
        if allowActiveCodexHome {
            candidates.append(codexHomeDirectory().appendingPathComponent("config.toml", isDirectory: false))
        }
        return uniqueFileCandidates(candidates)
    }

    private static func authCandidates(alongside url: URL?) -> [URL] {
        guard let directory = url?.deletingLastPathComponent() else {
            return []
        }

        var candidates: [URL] = []
        if let url, let pairedAuth = pairedAuthCandidate(forConfigURL: url) {
            candidates.append(pairedAuth)
        }
        candidates.append(directory.appendingPathComponent("auth.json", isDirectory: false))
        candidates.append(contentsOf: discoveredSiblingAuthCandidates(in: directory))
        return uniqueFileCandidates(candidates)
    }

    private static func pairedConfigCandidate(forAuthURL url: URL) -> URL? {
        let stem = url.deletingPathExtension().lastPathComponent
        guard stem.lowercased().hasPrefix("auth") else { return nil }
        let suffix = String(stem.dropFirst("auth".count))
        return url.deletingLastPathComponent().appendingPathComponent(
            "config\(suffix).toml",
            isDirectory: false
        )
    }

    private static func pairedAuthCandidate(forConfigURL url: URL) -> URL? {
        let stem = url.deletingPathExtension().lastPathComponent
        guard stem.lowercased().hasPrefix("config") else { return nil }
        let suffix = String(stem.dropFirst("config".count))
        return url.deletingLastPathComponent().appendingPathComponent(
            "auth\(suffix).json",
            isDirectory: false
        )
    }

    private static func discoveredSiblingAuthCandidates(in directory: URL) -> [URL] {
        guard let siblingFiles = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return siblingFiles
            .filter { candidate in
                let fileName = candidate.lastPathComponent.lowercased()
                guard fileName != "auth.json" else { return false }
                guard candidate.pathExtension.lowercased() == "json" else { return false }
                return isLikelyCodexAuthCandidate(fileName)
            }
            .sorted { lhs, rhs in
                let lhsRank = authCandidateRank(for: lhs.lastPathComponent)
                let rhsRank = authCandidateRank(for: rhs.lastPathComponent)
                if lhsRank != rhsRank {
                    return lhsRank > rhsRank
                }
                return lhs.lastPathComponent.localizedCaseInsensitiveCompare(rhs.lastPathComponent) == .orderedDescending
            }
    }

    private static func isLikelyCodexAuthCandidate(_ fileName: String) -> Bool {
        let lowercased = fileName.lowercased()
        guard lowercased.hasPrefix("auth"), lowercased.hasSuffix(".json") else {
            return false
        }
        let stem = String(lowercased.dropLast(".json".count))
        let suffix = String(stem.dropFirst("auth".count))
        return suffix.isEmpty || suffix.allSatisfy(\.isNumber)
    }

    private static func authCandidateRank(for fileName: String) -> Int {
        let lowercased = fileName.lowercased()
        if lowercased == "auth.json" {
            return .max
        }
        let stem = String(lowercased.dropLast(".json".count))
        let suffix = String(stem.dropFirst("auth".count))
        return Int(suffix) ?? 1
    }

    private static func loadProviderConfig(
        from url: URL,
        requireExplicitProvider: Bool
    ) -> ProviderConfigImport.ImportedProviderConfig? {
        guard FileManager.default.fileExists(atPath: url.path),
              let config = try? ProviderConfigImport.load(from: url) else {
            return nil
        }
        if requireExplicitProvider, config.source != .explicitProvider {
            return nil
        }
        return config
    }

    private static func supportsOpenAICompatibility(backend: String) -> Bool {
        switch RemoteProviderEndpoints.canonicalBackend(backend) {
        case "openai", "openai_compatible", "remote_catalog":
            return true
        default:
            return false
        }
    }

    private static func codexHomeDirectory() -> URL {
        let override = ProcessInfo.processInfo.environment[codexHomeOverrideEnvKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !override.isEmpty {
            return URL(fileURLWithPath: NSString(string: override).expandingTildeInPath, isDirectory: true)
        }

        let env = ProcessInfo.processInfo.environment["CODEX_HOME"]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !env.isEmpty {
            return URL(fileURLWithPath: NSString(string: env).expandingTildeInPath, isDirectory: true)
        }

        return SharedPaths.realHomeDirectory().appendingPathComponent(".codex", isDirectory: true)
    }

    private static func uniqueFileCandidates(_ candidates: [URL]) -> [URL] {
        var seen: Set<String> = []
        var unique: [URL] = []
        for candidate in candidates {
            let standardized = candidate.standardizedFileURL.path
            guard seen.insert(standardized).inserted else { continue }
            unique.append(candidate)
        }
        return unique
    }

    private static func credentialSignature(_ credentials: ProviderAuthImport.ImportedCredentials) -> String {
        [
            credentials.kind.rawValue,
            credentials.backend.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            credentials.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            credentials.apiKeyRef.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            credentials.wireAPI.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            credentials.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        ].joined(separator: "\u{1F}")
    }

    private static func normalizedBaseURL(_ raw: String?) -> String {
        var value = (raw ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        while value.hasSuffix("/") {
            value.removeLast()
        }
        return value
    }
}
