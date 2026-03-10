import SwiftUI
import AppKit
@preconcurrency import UserNotifications
import RELFlowHubCore

@main
struct RELFlowHubApp: App {
    // Use an AppDelegate so we can programmatically show a popover (needed for widget click -> open popover).
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Menu bar apps don't need a normal window.
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var statusController: StatusBarController?
    private var floatingController: FloatingPanelController?
    private var mainPanelController: MainPanelController?
    private var embeddedBridgeRunner: EmbeddedBridgeRunner?
    private var activity: NSObjectProtocol?
    private var didCheckInstallLocation = false

    private let didShowMainOnFirstLaunchKey = "relflowhub_did_show_main_on_first_launch"

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Accessory app: show in menu bar, hide Dock icon.
        NSApp.setActivationPolicy(.accessory)

        // Prevent App Nap from pausing timers (IPC heartbeat/drain, calendar polling).
        // On macOS 26, LSUIElement apps can get napped aggressively.
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep, .latencyCritical],
            reason: "REL Flow Hub timers (IPC/Calendar)"
        )

        // Allow meeting reminders to open join links.
        // NOTE: calling UNUserNotificationCenter.current() can assert+abort when running via
        // `swift run` (not an app bundle). Only enable notifications for real .app builds.
        if NotificationSupport.isAvailable {
            UNUserNotificationCenter.current().delegate = self
        }

        // Single-app mode: run Bridge IPC service inside Hub.
        let embeddedBridge = EmbeddedBridgeRunner()
        embeddedBridge.start()
        embeddedBridgeRunner = embeddedBridge

        // Ensure enabled remote models are reflected in models_state.json for satellites (gRPC/X-Terminal).
        RemoteModelStorage.syncEnabledRemoteModelsIntoModelState()

        // Resolve HubStore before starting launch-state timers. HubStore init can briefly spin
        // the main runloop (for bounded subprocess probes); starting the state machine first can
        // re-enter HubStore.shared during initialization and crash with recursive dispatch_once.
        let store = HubStore.shared
        statusController = StatusBarController(store: store)
        floatingController = FloatingPanelController(store: store)
        mainPanelController = MainPanelController(store: store)

        // Emit a single structured launch status file so startup failures are diagnosable
        // even when the UI appears "stuck" (common for LSUIElement apps).
        HubLaunchStateMachine.shared.start(bridgeStarted: true)

        // Make launch visible (LSUIElement apps can feel like "nothing happened").
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self else { return }
            self.floatingController?.show()
            self.showMainPanelIfFirstLaunch()

            // After we have shown something, guide users to install into /Applications.
            // This reduces repeated Calendar/Accessibility prompts caused by running from DMG/Downloads.
            if !self.didCheckInstallLocation {
                self.didCheckInstallLocation = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    AppInstallDoctor.showInstallAlertIfNeeded()
                }
            }
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(toggleFloatingWindow),
            name: .relflowhubToggleFloating,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(openMainPanel),
            name: .relflowhubOpenMain,
            object: nil
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        HubLaunchStateMachine.shared.stop()
        embeddedBridgeRunner?.stop()
        embeddedBridgeRunner = nil
        HubGRPCServerSupport.shared.stop()
        if let activity {
            ProcessInfo.processInfo.endActivity(activity)
            self.activity = nil
        }
    }

    func restartEmbeddedBridgeForDiagnostics() {
        HubDiagnostics.log("diagnostics.fix bridge_restart requested")
        embeddedBridgeRunner?.stop()
        let embeddedBridge = EmbeddedBridgeRunner()
        embeddedBridge.start()
        embeddedBridgeRunner = embeddedBridge
    }


    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Finder double-clicking an LSUIElement app often feels like "nothing happened".
        // Bring up a real window so users have an obvious affordance.
        floatingController?.show()
        mainPanelController?.show()
        return true
    }

    private func showMainPanelIfFirstLaunch() {
        let didShow = UserDefaults.standard.bool(forKey: didShowMainOnFirstLaunchKey)
        guard !didShow else { return }
        UserDefaults.standard.set(true, forKey: didShowMainOnFirstLaunchKey)
        mainPanelController?.show()
    }

    @objc private func toggleFloatingWindow() {
        floatingController?.toggle()
    }

    @objc private func openMainPanel() {
        mainPanelController?.show()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        // Future: handle relflowhub://open?panel=inbox to show popover.
        guard !urls.isEmpty else { return }
        mainPanelController?.show()
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show banners even when the hub is running in the foreground.
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        defer { completionHandler() }
        if let s = response.notification.request.content.userInfo["action_url"] as? String,
           let url = URL(string: s) {
            Task { @MainActor in
                NSWorkspace.shared.open(url)
            }
        }
    }
}
