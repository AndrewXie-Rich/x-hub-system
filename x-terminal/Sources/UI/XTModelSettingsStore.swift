import Combine
import Foundation

struct XTModelSettingsSnapshot: Equatable {
    var interfaceLanguage: XTInterfaceLanguage
    var settings: XTerminalSettings
    var modelsState: ModelStateSnapshot
    var hubBaseDir: URL?
    var hubInteractive: Bool
    var hubRemoteConnected: Bool
    var hubRemoteRoute: HubRemoteRoute
    var remotePaidAccessSnapshot: HubRemotePaidAccessSnapshot?
    var selectedProjectId: String?
    var selectedProjectName: String?
    var selectedProjectContext: AXProjectContext?
    var selectedProjectConfig: AXProjectConfig?
    var unifiedDoctorGeneratedAtMs: Int64
    var modelRouteReadinessSection: XTUnifiedDoctorSection?

    static let empty = XTModelSettingsSnapshot(
        interfaceLanguage: .defaultPreference,
        settings: .default(),
        modelsState: .empty(),
        hubBaseDir: nil,
        hubInteractive: false,
        hubRemoteConnected: false,
        hubRemoteRoute: .none,
        remotePaidAccessSnapshot: nil,
        selectedProjectId: nil,
        selectedProjectName: nil,
        selectedProjectContext: nil,
        selectedProjectConfig: nil,
        unifiedDoctorGeneratedAtMs: 0,
        modelRouteReadinessSection: nil
    )
}

@MainActor
final class XTModelSettingsStore: ObservableObject {
    @Published private(set) var snapshot: XTModelSettingsSnapshot

    init(snapshot: XTModelSettingsSnapshot = .empty) {
        self.snapshot = snapshot
    }

    func update(_ nextSnapshot: XTModelSettingsSnapshot) {
        guard snapshot != nextSnapshot else { return }
        snapshot = nextSnapshot
    }
}
