import Foundation

extension SupervisorManager {
    var currentSupervisorWorkMode: XTSupervisorWorkMode {
        appModel?.settingsStore.settings.supervisorWorkMode ?? .defaultMode
    }

    var currentSupervisorPrivacyMode: XTPrivacyMode {
        appModel?.settingsStore.settings.supervisorPrivacyMode ?? .defaultMode
    }
}
