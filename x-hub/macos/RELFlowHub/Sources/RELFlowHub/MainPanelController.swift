import AppKit
import SwiftUI

@MainActor
final class MainPanelController: NSObject, NSWindowDelegate {
    private let store: HubStore
    private let panel: NSPanel

    init(store: HubStore) {
        self.store = store

        let root = MainPanelView().environmentObject(store)
        let host = NSHostingController(rootView: root.frame(width: 760, height: 560))

        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        p.title = "REL Flow Hub"
        p.level = .normal
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.isReleasedWhenClosed = false
        p.titlebarAppearsTransparent = true
        p.isMovableByWindowBackground = true
        p.contentViewController = host

        self.panel = p
        super.init()
        self.panel.delegate = self

        // Restore last frame.
        if let s = UserDefaults.standard.string(forKey: "relflowhub_main_frame") {
            let r = NSRectFromString(s)
            if !r.isEmpty {
                self.panel.setFrame(r, display: false)
            } else {
                self.panel.center()
            }
        } else {
            self.panel.center()
        }
    }

    func show() {
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hide() {
        panel.orderOut(nil)
    }

    func toggle() {
        if panel.isVisible { hide() } else { show() }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Close button should just hide to keep the floating orb alive.
        hide()
        return false
    }

    func windowDidMove(_ notification: Notification) {
        persistFrame()
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        persistFrame()
    }

    private func persistFrame() {
        UserDefaults.standard.set(NSStringFromRect(panel.frame), forKey: "relflowhub_main_frame")
    }
}
