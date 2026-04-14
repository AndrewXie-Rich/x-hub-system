import Foundation
import RELFlowHubCore

enum ProviderConfigImport {
    enum ConfigSource: String, Equatable {
        case explicitProvider = "explicit_provider"
        case fallbackOpenAI = "fallback_openai"
    }

    struct ImportedProviderConfig: Equatable {
        var providerName: String
        var backend: String
        var baseURL: String
        var apiKeyRef: String
        var preferredModelID: String
        var wireAPI: String
        var source: ConfigSource
    }

    enum ImportError: LocalizedError {
        case unsupportedFormat
        case noSupportedProvider

        var errorDescription: String? {
            switch self {
            case .unsupportedFormat:
                return HubUIStrings.Models.ProviderImport.configUnsupportedFormat
            case .noSupportedProvider:
                return HubUIStrings.Models.ProviderImport.configNoSupportedProvider
            }
        }
    }

    static func load(from url: URL) throws -> ImportedProviderConfig {
        let text = try String(contentsOf: url, encoding: .utf8)
        return try parse(text: text)
    }

    static func parse(text: String) throws -> ImportedProviderConfig {
        let config = extractConfig(from: text)
        let providers = config.providers
            .filter { $0.requiresOpenAIAuth && !$0.baseURL.isEmpty }
        let selected = selectProvider(from: providers, preferredName: config.preferredProviderName)
        if let selected {
            let backend = inferredBackend(baseURL: selected.baseURL)
            return ImportedProviderConfig(
                providerName: selected.name,
                backend: backend,
                baseURL: selected.baseURL,
                apiKeyRef: defaultAPIKeyRef(backend: backend, baseURL: selected.baseURL),
                preferredModelID: config.preferredModelID,
                wireAPI: selected.wireAPI,
                source: .explicitProvider
            )
        }

        if let fallback = fallbackOpenAIConfig(from: config) {
            return fallback
        }

        throw ImportError.noSupportedProvider
    }

    private struct ProviderSection {
        var name: String
        var baseURL: String = ""
        var requiresOpenAIAuth: Bool = false
        var wireAPI: String = ""
    }

    private struct ParsedConfig {
        var preferredProviderName: String?
        var preferredModelID: String
        var providers: [ProviderSection]
    }

    private static func extractConfig(from text: String) -> ParsedConfig {
        var providers: [ProviderSection] = []
        var current: ProviderSection?
        var preferredProviderName: String?
        var preferredModelID: String = ""

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("#") {
                continue
            }

            if line.hasPrefix("[") && line.hasSuffix("]") {
                if let current, !current.name.isEmpty {
                    providers.append(current)
                }
                current = nil

                let section = String(line.dropFirst().dropLast())
                let prefix = "model_providers."
                if section.hasPrefix(prefix) {
                    let name = String(section.dropFirst(prefix.count))
                    current = ProviderSection(name: name)
                }
                continue
            }

            guard let eq = line.firstIndex(of: "=") else {
                continue
            }

            let key = String(line[..<eq]).trimmingCharacters(in: .whitespacesAndNewlines)
            let value = String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespacesAndNewlines)

            if current == nil {
                if key == "model_provider" {
                    let providerName = unquote(value)
                    preferredProviderName = providerName.isEmpty ? preferredProviderName : providerName
                } else if key == "model" {
                    let modelID = unquote(value)
                    preferredModelID = modelID.isEmpty ? preferredModelID : modelID
                }
                continue
            }

            guard var section = current else {
                continue
            }

            switch key {
            case "base_url":
                section.baseURL = unquote(value)
            case "requires_openai_auth":
                section.requiresOpenAIAuth = value.lowercased() == "true"
            case "wire_api":
                section.wireAPI = unquote(value)
            default:
                break
            }
            current = section
        }

        if let current, !current.name.isEmpty {
            providers.append(current)
        }
        return ParsedConfig(
            preferredProviderName: preferredProviderName,
            preferredModelID: preferredModelID,
            providers: providers
        )
    }

    private static func selectProvider(
        from providers: [ProviderSection],
        preferredName: String?
    ) -> ProviderSection? {
        let normalizedPreferred = preferredName?.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if let normalizedPreferred, !normalizedPreferred.isEmpty,
           let exact = providers.first(where: { $0.name.lowercased() == normalizedPreferred }) {
            return exact
        }
        return providers.first
    }

    private static func fallbackOpenAIConfig(from config: ParsedConfig) -> ImportedProviderConfig? {
        guard config.providers.isEmpty else { return nil }
        let preferredModelID = config.preferredModelID.trimmingCharacters(in: .whitespacesAndNewlines)
        let preferredProvider = config.preferredProviderName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        if preferredProvider.isEmpty || preferredProvider == "openai" || preferredProvider == "chatgpt" || !preferredModelID.isEmpty {
            let baseURL = "https://api.openai.com/v1"
            let backend = "openai"
            return ImportedProviderConfig(
                providerName: preferredProvider.isEmpty ? "openai" : preferredProvider,
                backend: backend,
                baseURL: baseURL,
                apiKeyRef: defaultAPIKeyRef(backend: backend, baseURL: baseURL),
                preferredModelID: preferredModelID,
                wireAPI: RemoteProviderWireAPI.responses.rawValue,
                source: .fallbackOpenAI
            )
        }
        return nil
    }

    private static func inferredBackend(baseURL: String) -> String {
        guard let host = URL(string: baseURL)?.host?.lowercased(), !host.isEmpty else {
            return "openai_compatible"
        }
        return host.contains("openai.com") ? "openai" : "openai_compatible"
    }

    private static func defaultAPIKeyRef(backend: String, baseURL: String) -> String {
        let canonical = RemoteProviderEndpoints.canonicalBackend(backend)
        if let host = URL(string: baseURL)?.host?.trimmingCharacters(in: .whitespacesAndNewlines), !host.isEmpty {
            return "\(canonical):\(host)"
        }
        return canonical.isEmpty ? UUID().uuidString : canonical
    }

    private static func unquote(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
            value.removeFirst()
            value.removeLast()
        }
        return value
    }
}
