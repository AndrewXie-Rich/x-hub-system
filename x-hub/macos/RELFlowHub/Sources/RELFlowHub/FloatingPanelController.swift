import AppKit
import SwiftUI
import Combine

extension Notification.Name {
    static let relflowhubToggleFloating = Notification.Name("relflowhub.toggleFloating")
}

enum FloatingPanelLevelPolicy {
    static func level(for mode: FloatingMode) -> NSWindow.Level {
        switch mode {
        case .orb:
            // The orb is the persistent "alive" surface after the main panel closes,
            // so it must remain above regular app windows.
            return .floating
        case .card:
            return .normal
        }
    }
}

@MainActor
final class FloatingPanelController: NSObject, NSWindowDelegate {
    private let store: HubStore
    private let panel: NSPanel
    private var cancellables: Set<AnyCancellable> = []
    private var levelTimer: Timer?
    private var suppressedByMainPanel = false
    private var userHidden = false

    var isVisible: Bool {
        panel.isVisible
    }

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
        p.level = FloatingPanelLevelPolicy.level(for: store.floatingMode)
        p.collectionBehavior = WindowCollectionBehaviorPolicy.floatingPanel()
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

        NotificationCenter.default.publisher(for: .relflowhubMainPanelShown)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.setSuppressedByMainPanel(true)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .relflowhubMainPanelHidden)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.setSuppressedByMainPanel(false)
            }
            .store(in: &cancellables)

        // Restore last frame (if any).
        if let s = UserDefaults.standard.string(forKey: "relflowhub_floating_frame") {
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

    func toggle() {
        if panel.isVisible {
            userHidden = true
            HubDiagnostics.log("floating.toggle action=hide userHidden=1 suppressed=\(suppressedByMainPanel ? 1 : 0) level=\(panel.level.rawValue)")
            panel.orderOut(nil)
        } else {
            HubDiagnostics.log("floating.toggle action=show userHidden=\(userHidden ? 1 : 0) suppressed=\(suppressedByMainPanel ? 1 : 0)")
            show()
        }
    }

    func show() {
        userHidden = false
        guard !suppressedByMainPanel else {
            HubDiagnostics.log("floating.show skipped reason=suppressed level=\(panel.level.rawValue)")
            return
        }
        restoreFrameIfNeeded()
        updateWindowLevel()
        HubDiagnostics.log("floating.show frame=\(NSStringFromRect(panel.frame)) level=\(panel.level.rawValue) userHidden=0")
        panel.orderFrontRegardless()
    }

    func hide() {
        userHidden = true
        HubDiagnostics.log("floating.hide userHidden=1 suppressed=\(suppressedByMainPanel ? 1 : 0) level=\(panel.level.rawValue)")
        panel.orderOut(nil)
    }

    func setSuppressedByMainPanel(_ suppressed: Bool) {
        guard suppressedByMainPanel != suppressed else { return }
        suppressedByMainPanel = suppressed
        store.suppressFloatingContent = suppressed
        HubDiagnostics.log("floating.suppressed value=\(suppressed ? 1 : 0) userHidden=\(userHidden ? 1 : 0) visible=\(panel.isVisible ? 1 : 0)")
        if suppressed {
            panel.orderOut(nil)
        } else if !userHidden {
            show()
        }
    }

    private func restoreFrameIfNeeded() {
        let size = store.floatingMode.panelSize
        if panel.frame.isEmpty {
            panel.setContentSize(NSSize(width: size.width, height: size.height))
            panel.center()
            return
        }

        if let adjusted = Self.normalizedFrame(panel.frame, for: panel),
           adjusted != panel.frame {
            panel.setFrame(adjusted, display: false)
        }
    }

    private func updateWindowLevel() {
        let targetLevel = FloatingPanelLevelPolicy.level(for: store.floatingMode)
        if panel.level != targetLevel {
            HubDiagnostics.log("floating.level from=\(panel.level.rawValue) to=\(targetLevel.rawValue) mode=\(store.floatingMode.rawValue)")
            panel.level = targetLevel
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

    private static func normalizedFrame(_ rect: NSRect, for panel: NSPanel) -> NSRect? {
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

        if let screen = panel.screen ?? NSScreen.main {
            var centered = rect
            let visible = screen.visibleFrame
            centered.origin.x = visible.midX - (centered.width / 2)
            centered.origin.y = visible.midY - (centered.height / 2)
            return centered
        }

        return nil
    }
}
