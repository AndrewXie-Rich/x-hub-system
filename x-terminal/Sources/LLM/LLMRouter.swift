import Foundation

@MainActor
final class LLMRouter: ObservableObject {
    @Published var settingsStore: SettingsStore

    init(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
    }

    nonisolated func taskType(for role: AXRole) -> String {
        role.primaryRole.rawValue
    }

    func provider(for role: AXRole) -> LLMProvider {
        _ = role
        return HubLLMProvider()
    }

    func preferredModelIdForHub(for role: AXRole, projectConfig: AXProjectConfig? = nil) -> String? {
        if let cfg = projectConfig, let mid = cfg.modelOverride(for: role) {
            return mid
        }
        let route = settingsStore.settings.modelRoute(for: role)
        let mid = (route.primaryModelId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return mid.isEmpty ? nil : mid
    }

    func paidBackupModelIdForHub(for role: AXRole) -> String? {
        let route = settingsStore.settings.modelRoute(for: role)
        let mid = (route.paidBackupModelId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return mid.isEmpty ? nil : mid
    }

    func localFallbackMode(for role: AXRole) -> LocalModelFallbackMode {
        settingsStore.settings.modelRoute(for: role).localFallbackMode
    }
}
