import AppKit
import SwiftUI

@MainActor
final class HubSettingsWindowPresenter: NSObject, NSWindowDelegate {
    static let shared = HubSettingsWindowPresenter()

    private var windowController: NSWindowController?

    func show(store: HubStore = .shared) {
        NSApp.activate(ignoringOtherApps: true)

        if let window = windowController?.window {
            window.makeKeyAndOrderFront(nil)
            return
        }

        let hostingController = NSHostingController(
            rootView: SettingsSheetView()
                .environmentObject(store)
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1088, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = HubUIStrings.Settings.title
        window.contentViewController = hostingController
        window.minSize = NSSize(width: 920, height: 620)
        window.collectionBehavior = [.managed, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        window.setFrameAutosaveName("xhub.settings.window")

        let controller = NSWindowController(window: window)
        windowController = controller
        controller.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        guard let closedWindow = notification.object as? NSWindow,
              closedWindow === windowController?.window else {
            return
        }
        windowController = nil
    }
}
