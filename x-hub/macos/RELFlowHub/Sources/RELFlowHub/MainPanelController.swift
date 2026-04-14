import AppKit
import SwiftUI

extension Notification.Name {
    static let relflowhubMainPanelShown = Notification.Name("relflowhub.mainPanelShown")
    static let relflowhubMainPanelHidden = Notification.Name("relflowhub.mainPanelHidden")
}

@MainActor
final class MainPanelController: NSObject, NSWindowDelegate {
    private let store: HubStore
    private let panel: NSWindow
    private let defaultSize = NSSize(width: 760, height: 560)
    private let minimumSize = NSSize(width: 640, height: 460)

    var isVisible: Bool {
        panel.isVisible
    }

    init(store: HubStore) {
        self.store = store

        let root = MainPanelView().environmentObject(store)
        let host = NSHostingController(rootView: root)

        let p = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        p.title = "X-Hub"
        p.level = .normal
        p.collectionBehavior = WindowCollectionBehaviorPolicy.mainPanel()
        p.isReleasedWhenClosed = false
        p.titlebarAppearsTransparent = true
        p.isMovableByWindowBackground = true
        p.minSize = minimumSize
        p.setContentSize(defaultSize)
        p.contentViewController = host

        self.panel = p
        super.init()
        self.panel.delegate = self

        // Restore last frame.
        if let s = UserDefaults.standard.string(forKey: "relflowhub_main_frame") {
            let r = NSRectFromString(s)
            if let adjusted = Self.normalizedFrame(r, for: self.panel) {
                self.panel.setFrame(adjusted, display: false)
            } else {
                self.panel.center()
            }
        } else {
            self.panel.center()
        }
    }

    func show() {
        let wasVisible = panel.isVisible
        restoreFrameIfNeeded()
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        if !wasVisible {
            NotificationCenter.default.post(name: .relflowhubMainPanelShown, object: nil)
        }
        HubDiagnostics.log("mainPanel.show frame=\(NSStringFromRect(panel.frame)) visible=\(panel.isVisible ? 1 : 0)")
    }

    func hide() {
        let wasVisible = panel.isVisible
        HubDiagnostics.log("mainPanel.hide requested wasVisible=\(wasVisible ? 1 : 0) frame=\(NSStringFromRect(panel.frame))")
        panel.orderOut(nil)
        if wasVisible {
            NotificationCenter.default.post(name: .relflowhubMainPanelHidden, object: nil)
            HubDiagnostics.log("mainPanel.hide posted_hidden_notification")
        }
    }

    func toggle() {
        if panel.isVisible { hide() } else { show() }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Close button should just hide to keep the floating orb alive.
        HubDiagnostics.log("mainPanel.windowShouldClose visible=\(panel.isVisible ? 1 : 0)")
        hide()
        return false
    }

    func windowDidMove(_ notification: Notification) {
        persistFrame()
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        persistFrame()
    }

    func windowDidResize(_ notification: Notification) {
        persistFrame()
    }

    private func persistFrame() {
        UserDefaults.standard.set(NSStringFromRect(panel.frame), forKey: "relflowhub_main_frame")
    }

    private func restoreFrameIfNeeded() {
        if panel.frame.isEmpty {
            if let adjusted = Self.normalizedFrame(
                NSRect(origin: panel.frame.origin, size: defaultSize),
                for: panel
            ) {
                panel.setFrame(adjusted, display: false)
            } else {
                panel.center()
            }
            return
        }

        if let adjusted = Self.normalizedFrame(panel.frame, for: panel),
           adjusted != panel.frame {
            panel.setFrame(adjusted, display: false)
        }
    }

    private static func normalizedFrame(_ rect: NSRect, for window: NSWindow) -> NSRect? {
        guard !rect.isEmpty else { return nil }
        for screen in NSScreen.screens {
            let visible = screen.visibleFrame.insetBy(dx: 20, dy: 20)
            guard rect.width <= visible.width, rect.height <= visible.height else { continue }
            guard visible.intersects(rect) || visible.contains(rect.origin) else { continue }

            var adjusted = rect
            adjusted.origin.x = min(max(adjusted.origin.x, visible.minX), visible.maxX - adjusted.width)
            adjusted.origin.y = min(max(adjusted.origin.y, visible.minY), visible.maxY - adjusted.height)
            return adjusted
        }

        if let screen = window.screen ?? NSScreen.main {
            var centered = rect
            let visible = screen.visibleFrame
            centered.origin.x = visible.midX - (centered.width / 2)
            centered.origin.y = visible.midY - (centered.height / 2)
            return centered
        }

        return nil
    }
}
