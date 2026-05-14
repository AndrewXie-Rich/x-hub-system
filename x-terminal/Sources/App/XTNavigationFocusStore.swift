import Combine
import Foundation

struct XTNavigationFocusSnapshot: Equatable {
    var projectFocusRequest: AXProjectFocusRequest?
    var supervisorFocusRequest: AXSupervisorFocusRequest?
    var settingsFocusRequest: XTSettingsFocusRequest?
    var hubSetupFocusRequest: XTHubSetupFocusRequest?
    var supervisorSettingsFocusRequest: XTSupervisorSettingsFocusRequest?
    var modelSettingsFocusRequest: XTModelSettingsFocusRequest?
    var projectDetailFocusRequest: XTProjectDetailFocusRequest?
    var projectSettingsFocusRequest: XTProjectSettingsFocusRequest?

    static let empty = XTNavigationFocusSnapshot(
        projectFocusRequest: nil,
        supervisorFocusRequest: nil,
        settingsFocusRequest: nil,
        hubSetupFocusRequest: nil,
        supervisorSettingsFocusRequest: nil,
        modelSettingsFocusRequest: nil,
        projectDetailFocusRequest: nil,
        projectSettingsFocusRequest: nil
    )
}

@MainActor
final class XTNavigationFocusStore: ObservableObject {
    @Published private(set) var snapshot: XTNavigationFocusSnapshot

    init(snapshot: XTNavigationFocusSnapshot = .empty) {
        self.snapshot = snapshot
    }

    func update(_ nextSnapshot: XTNavigationFocusSnapshot) {
        guard snapshot != nextSnapshot else { return }
        snapshot = nextSnapshot
    }
}
