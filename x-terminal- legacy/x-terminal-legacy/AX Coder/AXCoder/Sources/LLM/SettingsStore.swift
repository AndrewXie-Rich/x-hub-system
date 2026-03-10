import Foundation

@MainActor
final class SettingsStore: ObservableObject {
    @Published var settings: AXCoderSettings

    private let url: URL

    init() {
        let fm = FileManager.default
        let supportBase = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
        let base = supportBase.appendingPathComponent("X-Terminal", isDirectory: true)
        let legacyBase = supportBase.appendingPathComponent("AXCoder", isDirectory: true)
        try? fm.createDirectory(at: base, withIntermediateDirectories: true)

        let preferredURL = base.appendingPathComponent("settings.json")
        url = preferredURL
        let legacyURL = legacyBase.appendingPathComponent("settings.json")
        let srcURL: URL = {
            if fm.fileExists(atPath: preferredURL.path) { return preferredURL }
            if fm.fileExists(atPath: legacyURL.path) { return legacyURL }
            return preferredURL
        }()

        if let data = try? Data(contentsOf: srcURL),
           let s = try? JSONDecoder().decode(AXCoderSettings.self, from: data) {
            settings = SettingsStore.enforceHubOnly(s)
            // One-time migration to the new brand directory.
            if srcURL != preferredURL {
                try? data.write(to: preferredURL, options: .atomic)
            }
        } else {
            settings = SettingsStore.enforceHubOnly(.default())
        }

    }

    func save() {
        var s = settings
        s.schemaVersion = AXCoderSettings.currentSchemaVersion
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(s) {
            try? data.write(to: url, options: .atomic)
        }
    }

    private static func enforceHubOnly(_ s: AXCoderSettings) -> AXCoderSettings {
        var out = s
        out.assignments = out.assignments.map { RoleProviderAssignment(role: $0.role, providerKind: .hub, model: $0.model) }
        return out
    }

}
