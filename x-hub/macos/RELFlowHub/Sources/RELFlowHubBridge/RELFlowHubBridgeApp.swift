import SwiftUI
import AppKit
import RELFlowHubCore

@main
struct RELFlowHubBridgeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var statusMenuItem: NSMenuItem?
    private var runner: BridgeRunner?
    private var toastPanel: NSPanel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let r = BridgeRunner()
        runner = r
        r.start()

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        if let btn = item.button {
            let img = NSImage(systemSymbolName: "network", accessibilityDescription: "X-Hub Bridge")
            img?.isTemplate = true
            btn.image = img
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "X-Hub Bridge", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        let st = NSMenuItem(title: "Status: starting…", action: nil, keyEquivalent: "")
        st.isEnabled = false
        menu.addItem(st)
        statusMenuItem = st
        menu.addItem(.separator())
        let stop = NSMenuItem(title: "Stop Bridge", action: #selector(stopBridge), keyEquivalent: "q")
        stop.target = self
        menu.addItem(stop)
        item.menu = menu

        showLaunchToastOnce()

        // Update status text periodically.
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshStatusMenuItem()
            }
        }
    }

    @objc private func stopBridge() {
        runner?.stop()
        NSApp.terminate(nil)
    }

    private func refreshStatusMenuItem() {
        let txt = runner?.statusText() ?? "stopped"
        statusMenuItem?.title = "Status: \(txt)"
    }

    private func showLaunchToastOnce() {
        // Bridge is a menu bar-only helper (LSUIElement). First launch can look like "nothing happened".
        // Show a small non-intrusive toast once.
        let key = "relflowhub_bridge_did_show_toast"
        if UserDefaults.standard.bool(forKey: key) {
            return
        }
        UserDefaults.standard.set(true, forKey: key)

        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 110),
            styleMask: [.nonactivatingPanel, .hudWindow],
            backing: .buffered,
            defer: false
        )
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.hidesOnDeactivate = false

        let label = NSTextField(labelWithString: "X-Hub Bridge is running\n(Menu bar icon added)")
        label.alignment = .center
        label.textColor = .white
        label.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        label.frame = NSRect(x: 16, y: 28, width: 288, height: 54)

        let bg = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 320, height: 110))
        bg.material = .hudWindow
        bg.state = .active
        bg.wantsLayer = true
        bg.layer?.cornerRadius = 14
        bg.layer?.masksToBounds = true
        bg.addSubview(label)
        p.contentView = bg

        if let screen = NSScreen.main {
            let vis = screen.visibleFrame
            let x = vis.maxX - 340
            let y = vis.maxY - 160
            p.setFrameOrigin(NSPoint(x: x, y: y))
        }

        toastPanel = p
        p.orderFront(nil)

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.toastPanel?.orderOut(nil)
            self?.toastPanel = nil
        }
    }
}
