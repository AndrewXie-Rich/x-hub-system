import Foundation

@MainActor
final class SettingsStore: ObservableObject {
    @Published var settings: XTerminalSettings

    private let url: URL

    init() {
        let fm = FileManager.default
        let supportBase = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
        let base = supportBase.appendingPathComponent("X-Terminal", isDirectory: true)
        try? fm.createDirectory(at: base, withIntermediateDirectories: true)

        url = base.appendingPathComponent("settings.json")
        if let data = try? Data(contentsOf: url),
           let s = try? JSONDecoder().decode(XTerminalSettings.self, from: data) {
            settings = SettingsStore.enforceHubOnly(s)
        } else {
            settings = SettingsStore.enforceHubOnly(.default())
        }

    }

    func save() {
        var s = settings
        s.schemaVersion = XTerminalSettings.currentSchemaVersion
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(s) {
            try? data.write(to: url, options: .atomic)
        }
    }

    private static func enforceHubOnly(_ s: XTerminalSettings) -> XTerminalSettings {
        var out = s
        out.assignments = out.assignments.map { RoleProviderAssignment(role: $0.role, providerKind: .hub, model: $0.model) }
        return out
    }

}
