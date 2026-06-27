import SwiftUI
import AppKit
import RELFlowHubCore

// Main panel: Inbox first; models in a right-side drawer.
struct MainPanelView: View {
    @EnvironmentObject var store: HubStore
    private let modelsDrawerWidth: CGFloat = 720

    var body: some View {
        ZStack(alignment: .trailing) {
            InboxColumn()
                .environmentObject(store)
                .frame(minWidth: 520)

            if store.showModelsDrawer {
                ModelsDrawer()
                    .environmentObject(store)
                    .frame(width: modelsDrawerWidth)
                    .transition(.move(edge: .trailing))
                    .zIndex(10)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: store.showModelsDrawer)
        .background(
            ZStack {
                LinearGradient(
                    colors: [
                        Color(NSColor.windowBackgroundColor),
                        Color(NSColor.controlBackgroundColor).opacity(0.96)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Rectangle()
                    .fill(.regularMaterial.opacity(0.72))
            }
        )
    }
}
