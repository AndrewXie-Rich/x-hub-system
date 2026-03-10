import Foundation

@MainActor
final class LLMRouter: ObservableObject {
    @Published var settingsStore: SettingsStore

    init(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
    }

    nonisolated func taskType(for role: AXRole) -> String {
        switch role {
        case .coder:
            return "assist"
        case .coarse:
            return "x_terminal_coarse"
        case .refine:
            return "x_terminal_refine"
        case .reviewer:
            return "review"
        case .advisor:
            return "advisor"
        case .supervisor:
            return "supervisor"
        }
    }

    func provider(for role: AXRole) -> LLMProvider {
        _ = role
        return HubLLMProvider()
    }

    func preferredModelIdForHub(for role: AXRole, projectConfig: AXProjectConfig? = nil) -> String? {
        if let cfg = projectConfig, let mid = cfg.modelOverride(for: role) {
            return mid
        }
        let a = settingsStore.settings.assignment(for: role)
        let mid = (a.model ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return mid.isEmpty ? nil : mid
    }
}
