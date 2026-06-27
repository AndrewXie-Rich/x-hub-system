import AppKit
import Combine
import SwiftUI
import RELFlowHubCore

@MainActor
final class StatusBarController: NSObject {
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private let store: HubStore
    private var lastRenderKey: String = ""
    private var refreshTimer: Timer?
    private var storeChangeCancellable: AnyCancellable?
    private var grpcChangeCancellable: AnyCancellable?

    init(store: HubStore) {
        self.store = store
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.popover = NSPopover()
        super.init()
        self.statusItem.isVisible = true

        popover.behavior = .transient
        popover.animates = true

        let content = HubMenuView().environmentObject(store)
        popover.contentViewController = NSHostingController(rootView: content.frame(width: 420, height: 520))

        if let btn = statusItem.button {
            btn.image = nil
            btn.imagePosition = .noImage
            btn.toolTip = "X-Hub"
            btn.action = #selector(statusItemClicked(_:))
            btn.target = self
            btn.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        refreshStatusIcon(force: true)

        storeChangeCancellable = store.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in
                await Task.yield()
                self?.refreshStatusIcon(force: false)
            }
        }

        grpcChangeCancellable = HubGRPCServerSupport.shared.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in
                await Task.yield()
                self?.refreshStatusIcon(force: false)
            }
        }

        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshStatusIcon(force: false)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    @objc private func statusItemClicked(_ sender: Any?) {
        let event = NSApp.currentEvent
        let contextClick = event?.type == .rightMouseUp || (event?.modifierFlags.contains(.control) ?? false)
        if contextClick {
            popUp(makeStatusMenu())
            return
        }

        // Prefer opening the main panel instead of a constrained popover.
        openMain()
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

    private func refreshStatusIcon(force: Bool) {
        let presentation = makeStatusPresentation()
        let key = [
            presentation.stateKey,
            presentation.colorKey,
            presentation.toolTip,
            effectiveAppearanceKey(),
        ].joined(separator: "|")
        guard force || key != lastRenderKey else { return }
        lastRenderKey = key

        guard let btn = statusItem.button else { return }
        btn.image = nil
        btn.imagePosition = .noImage
        // Force text presentation so macOS does not render the bolt as a fixed yellow emoji.
        btn.attributedTitle = NSAttributedString(
            string: HubStatusPresentationSupport.menuBarSymbol,
            attributes: [
                .font: NSFont.systemFont(ofSize: 16, weight: .semibold),
                .foregroundColor: presentation.color,
            ]
        )
        btn.toolTip = presentation.toolTip
    }

    private func makeStatusPresentation() -> HubStatusPresentation {
        let grpc = HubGRPCServerSupport.shared
        return HubStatusPresentationSupport.make(
            snapshot: HubLaunchStatusStorage.load(),
            grpcIsRunning: grpc.isRunning,
            grpcStatusText: grpc.statusText
        )
    }

    private func effectiveAppearanceKey() -> String {
        let appearance = statusItem.button?.effectiveAppearance ?? NSApp.effectiveAppearance
        let match = appearance.bestMatch(from: [.aqua, .darkAqua]) ?? .aqua
        return match.rawValue
    }

    private func makeStatusMenu() -> NSMenu {
        let presentation = makeStatusPresentation()
        let menu = NSMenu()

        let title = NSMenuItem(title: "X-Hub • \(presentation.title)", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)

        if !presentation.detail.isEmpty {
            let detail = NSMenuItem(title: shortMenuDetail(presentation.detail), action: nil, keyEquivalent: "")
            detail.isEnabled = false
            menu.addItem(detail)
        }
        if presentation.needsActionHint {
            let actionHint = NSMenuItem(title: "建议：\(presentation.actionTitle)", action: nil, keyEquivalent: "")
            actionHint.isEnabled = false
            menu.addItem(actionHint)
        }

        menu.addItem(.separator())
        menu.addItem(menuItem("打开 X-Hub", action: #selector(openMainAction)))
        menu.addItem(menuItem("打开 Models", action: #selector(openModelsAction)))
        menu.addItem(menuItem("打开设置", action: #selector(openSettingsAction)))
        menu.addItem(menuItem("查看 Hub 诊断", action: #selector(openDiagnosticsAction)))
        menu.addItem(.separator())
        menu.addItem(menuItem(store.floatingMode == .hidden ? "打开 Orb" : "隐藏 Orb", action: #selector(toggleFloatingAction)))
        menu.addItem(menuItem("刷新状态", action: #selector(refreshStatusAction)))
        menu.addItem(.separator())
        menu.addItem(menuItem("退出 X-Hub", action: #selector(quitHubAction), keyEquivalent: "q"))
        return menu
    }

    private func menuItem(_ title: String, action: Selector, keyEquivalent: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        return item
    }

    private func shortMenuDetail(_ detail: String) -> String {
        let cleaned = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count > 76 else { return cleaned }
        return String(cleaned.prefix(73)) + "..."
    }

    private func popUp(_ menu: NSMenu) {
        guard let button = statusItem.button else { return }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.minY - 2), in: button)
    }

    private func openMain() {
        NotificationCenter.default.post(name: .relflowhubOpenMain, object: nil)
    }

    @objc private func openMainAction() {
        openMain()
    }

    @objc private func openModelsAction() {
        store.showModelsDrawer = true
        openMain()
    }

    @objc private func openSettingsAction() {
        HubSettingsWindowPresenter.shared.show(store: store)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openDiagnosticsAction() {
        store.openDiagnosticsSettings()
        HubSettingsWindowPresenter.shared.show(store: store)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func toggleFloatingAction() {
        NotificationCenter.default.post(name: .relflowhubToggleFloating, object: nil)
    }

    @objc private func refreshStatusAction() {
        HubGRPCServerSupport.shared.refresh()
        refreshStatusIcon(force: true)
    }

    @objc private func quitHubAction() {
        store.stopAIRuntime()
        NSApp.terminate(nil)
    }
}
