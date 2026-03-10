import AppKit
import SwiftUI
import RELFlowHubCore

@MainActor
final class StatusBarController {
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private let store: HubStore

    init(store: HubStore) {
        self.store = store
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.popover = NSPopover()

        popover.behavior = .transient
        popover.animates = true

        let content = HubMenuView().environmentObject(store)
        popover.contentViewController = NSHostingController(rootView: content.frame(width: 420, height: 520))

        if let btn = statusItem.button {
            let img = NSImage(systemSymbolName: "bolt.horizontal.fill", accessibilityDescription: "REL Flow Hub")
            img?.isTemplate = true
            btn.image = img
            btn.action = #selector(togglePopover(_:))
            btn.target = self
        }
    }

    @objc private func togglePopover(_ sender: Any?) {
        // Prefer opening the main panel instead of a constrained popover.
        NotificationCenter.default.post(name: .relflowhubOpenMain, object: nil)
    }

    func showPopover() {
        // Legacy path (kept for debugging). Main UX uses MainPanelController.
        guard let btn = statusItem.button else { return }
        popover.show(relativeTo: btn.bounds, of: btn, preferredEdge: .minY)
        // Ensure the app becomes active so keyboard works in popover.
        NSApp.activate(ignoringOtherApps: true)
    }

    func closePopover() {
        popover.performClose(nil)
    }
}
