import SwiftUI

struct SupervisorWindowSheetView: View {
    let sheet: SupervisorManager.SupervisorWindowSheet
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        SupervisorControlCenterView(preferredTab: sheet.controlCenterTab)
            .environmentObject(appModel)
    }
}
