import AppKit
import SwiftUI
import Combine

extension Notification.Name {
    static let relflowhubToggleFloating = Notification.Name("relflowhub.toggleFloating")
}

@MainActor
final class FloatingPanelController: NSObject, NSWindowDelegate {
    private let store: HubStore
    private let panel: NSPanel
    private var cancellables: Set<AnyCancellable> = []
    private var levelTimer: Timer?

    init(store: HubStore) {
        self.store = store

        let root = FloatingRootView().environmentObject(store)
        let host = NSHostingController(rootView: root.frame(width: store.floatingMode.panelSize.width, height: store.floatingMode.panelSize.height))

        let sz = store.floatingMode.panelSize
        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: sz.width, height: sz.height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.isFloatingPanel = true
        // Default: stay behind the frontmost app (similar to desktop widgets).
        // Using `.normal` keeps it interactive when visible, without being always-on-top.
        p.level = .normal
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.isOpaque = false
        p.backgroundColor = .clear
        // Orb: keep fully transparent (no panel shadow). Card: keep a subtle window shadow.
        p.hasShadow = (store.floatingMode == .card)
        p.ignoresMouseEvents = false
        p.isMovableByWindowBackground = true
        p.contentViewController = host

        self.panel = p
        super.init()
        self.panel.delegate = self

        // Keep the orb "desktop-like" by default. Only elevate when a meeting is imminent.
        updateWindowLevel()
        levelTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateWindowLevel()
            }
        }

        // Resize panel when mode changes.
        store.$floatingMode
            .receive(on: DispatchQueue.main)
            .sink { [weak self] mode in
                guard let self else { return }
                let sz = mode.panelSize
                self.panel.setContentSize(NSSize(width: sz.width, height: sz.height))
                self.updateWindowLevel()
                self.panel.hasShadow = (mode == .card)
            }
            .store(in: &cancellables)

        // Restore last frame (if any).
        if let s = UserDefaults.standard.string(forKey: "relflowhub_floating_frame") {
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

    func toggle() {
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            show()
        }
    }

    func show() {
        panel.orderFront(nil)
    }

    private func updateWindowLevel() {
        // Orb: stay at normal level unless a meeting is urgent.
        // Card: always stay at normal level.
        if store.floatingMode == .card {
            if panel.level != .normal {
                panel.level = .normal
            }
            return
        }

        let alert = store.topAlert()
        if alert.kind == .meetingUrgent {
            if panel.level != .floating {
                panel.level = .floating
            }
        } else {
            if panel.level != .normal {
                panel.level = .normal
            }
        }
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        persistFrame()
    }

    func windowDidMove(_ notification: Notification) {
        persistFrame()
    }

    private func persistFrame() {
        UserDefaults.standard.set(NSStringFromRect(panel.frame), forKey: "relflowhub_floating_frame")
    }
}
