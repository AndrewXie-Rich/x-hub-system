import Foundation

@MainActor
final class SettingsStore: ObservableObject {
    let voiceWakeProfileStore: VoiceWakeProfileStore

    @Published var settings: XTerminalSettings {
        didSet {
            VoiceSessionCoordinator.sharedIfInitialized?.setPreferences(settings.voice)
            voiceWakeProfileStore.applyPreferences(settings.voice)
            Task { @MainActor in
                await VoiceSessionCoordinator.sharedIfInitialized?.refreshRouteAvailability()
            }
        }
    }

    private let url: URL

    convenience init() {
        self.init(url: nil, voiceWakeProfileStore: VoiceWakeProfileStore.shared)
    }

    init(url: URL? = nil, voiceWakeProfileStore: VoiceWakeProfileStore) {
        self.voiceWakeProfileStore = voiceWakeProfileStore
        let fm = FileManager.default
        let resolvedURL: URL = {
            if let url { return url }
            let supportBase = fm.homeDirectoryForCurrentUser
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Application Support", isDirectory: true)
            let base = supportBase.appendingPathComponent("X-Terminal", isDirectory: true)
            return base.appendingPathComponent("settings.json")
        }()
        let base = resolvedURL.deletingLastPathComponent()
        try? fm.createDirectory(at: base, withIntermediateDirectories: true)

        self.url = resolvedURL
        if let data = try? Data(contentsOf: resolvedURL),
           let s = try? JSONDecoder().decode(XTerminalSettings.self, from: data) {
            settings = SettingsStore.enforceHubOnly(s)
        } else {
            settings = SettingsStore.enforceHubOnly(.default())
        }

        voiceWakeProfileStore.applyPreferences(settings.voice)
        Task { @MainActor in
            await VoiceSessionCoordinator.sharedIfInitialized?.refreshRouteAvailability()
        }

    }

    func save() {
        let s = settings.normalizedForPersistence()
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(s) {
            try? XTStoreWriteSupport.writeSnapshotData(data, to: url)
        }
    }

    private static func enforceHubOnly(_ s: XTerminalSettings) -> XTerminalSettings {
        var out = s
        out.assignments = out.assignments.map { RoleProviderAssignment(role: $0.role, providerKind: .hub, model: $0.model) }
        return out
    }

}
