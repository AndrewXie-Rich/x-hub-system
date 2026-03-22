import SwiftUI

struct SupervisorWindowSheetView: View {
    let sheet: SupervisorManager.SupervisorWindowSheet
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        switch sheet {
        case .supervisorSettings:
            SupervisorSettingsView()
                .environmentObject(appModel)
                .frame(minWidth: 820, minHeight: 620)
        case .modelSettings:
            ModelSettingsView()
                .environmentObject(appModel)
                .frame(minWidth: 860, minHeight: 620)
        }
    }
}
