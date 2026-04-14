import Foundation
import RELFlowHubCore

enum CodexModelCatalogFallback {
    private static let codexHomeOverrideEnvKey = "XHUB_CODEX_HOME_OVERRIDE"

    private struct ConfigSnapshot {
        var preferredProviderName: String
        var preferredModelID: String
        var providers: [String: String]
        var modelMigrations: [String: String]

        func matches(baseURL: String?) -> Bool {
            let requested = Self.normalizedBaseURL(baseURL)
            if requested.isEmpty {
                return !preferredProviderName.isEmpty
            }
            guard !preferredProviderName.isEmpty,
                  let providerBase = providers[preferredProviderName] else {
                return false
            }
            return Self.normalizedBaseURL(providerBase) == requested
        }

        func migratedModelIDIfNeeded() -> String {
            let key = preferredModelID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { return "" }
            return modelMigrations[key]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }

        private static func normalizedBaseURL(_ raw: String?) -> String {
            var value = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            while value.hasSuffix("/") {
                value.removeLast()
            }
            return value
        }
    }

    static func supportsFallback(for backend: String) -> Bool {
        switch RemoteProviderEndpoints.canonicalBackend(backend) {
        case "openai", "openai_compatible":
            return true
        default:
            return false
        }
    }

    static func modelIDs(backend: String, baseURL: String?) -> [String] {
        guard supportsFallback(for: backend) else { return [] }

        let config = loadConfigSnapshot()
        var ordered: [String] = []

        if let config, config.matches(baseURL: baseURL) {
            append(config.preferredModelID, to: &ordered)
            append(config.migratedModelIDIfNeeded(), to: &ordered)
        }

        for modelID in loadModelsCacheModelIDs() {
            append(modelID, to: &ordered)
        }

        return ordered
    }

    private static func append(_ raw: String, to ordered: inout [String]) {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !ordered.contains(value) else { return }
        ordered.append(value)
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

    private static func loadModelsCacheModelIDs() -> [String] {
        let url = codexHomeDirectory().appendingPathComponent("models_cache.json", isDirectory: false)
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
              let models = root["models"] as? [[String: Any]] else {
            return []
        }

        var ordered: [String] = []
        for model in models {
            if let supported = model["supported_in_api"] as? Bool, supported == false {
                continue
            }
            let slug = (model["slug"] as? String ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if slug.isEmpty || ordered.contains(slug) {
                continue
            }
            ordered.append(slug)
        }
        return ordered
    }

    private static func loadConfigSnapshot() -> ConfigSnapshot? {
        let url = codexHomeDirectory().appendingPathComponent("config.toml", isDirectory: false)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }

        var preferredProviderName = ""
        var preferredModelID = ""
        var providers: [String: String] = [:]
        var modelMigrations: [String: String] = [:]
        var currentProviderName = ""
        var inModelMigrations = false

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("#") {
                continue
            }

            if line.hasPrefix("[") && line.hasSuffix("]") {
                inModelMigrations = false
                currentProviderName = ""
                let section = String(line.dropFirst().dropLast())
                if section.hasPrefix("model_providers.") {
                    currentProviderName = String(section.dropFirst("model_providers.".count))
                } else if section == "notice.model_migrations" {
                    inModelMigrations = true
                }
                continue
            }

            guard let equalIndex = line.firstIndex(of: "=") else {
                continue
            }
            let key = String(line[..<equalIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            let value = unquote(String(line[line.index(after: equalIndex)...]))

            if inModelMigrations {
                if !key.isEmpty, !value.isEmpty {
                    modelMigrations[key] = value
                }
                continue
            }

            if !currentProviderName.isEmpty {
                if key == "base_url", !value.isEmpty {
                    providers[currentProviderName] = value
                }
                continue
            }

            if key == "model_provider", !value.isEmpty {
                preferredProviderName = value
            } else if key == "model", !value.isEmpty {
                preferredModelID = value
            }
        }

        if preferredProviderName.isEmpty && preferredModelID.isEmpty && providers.isEmpty && modelMigrations.isEmpty {
            return nil
        }

        return ConfigSnapshot(
            preferredProviderName: preferredProviderName,
            preferredModelID: preferredModelID,
            providers: providers,
            modelMigrations: modelMigrations
        )
    }

    private static func unquote(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
            value.removeFirst()
            value.removeLast()
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
