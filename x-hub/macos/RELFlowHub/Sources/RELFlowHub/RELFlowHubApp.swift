import SwiftUI
import AppKit
@preconcurrency import UserNotifications
import RELFlowHubCore

@main
struct RELFlowHubApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        if let code = XHubCLIRunner.runIfRequested(arguments: CommandLine.arguments) {
            fflush(stdout)
            fflush(stderr)
            Foundation.exit(Int32(code))
        }
    }

    var body: some Scene {
        Settings {
            SettingsSheetView()
                .environmentObject(HubStore.shared)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var floatingController: FloatingPanelController?
    private var mainPanelController: MainPanelController?
    private var statusBarController: StatusBarController?
    private var embeddedBridgeRunner: EmbeddedBridgeRunner?
    private var activity: NSObjectProtocol?
    private var didCheckInstallLocation = false
    private var launchStartedAt = Date()
    private var foregroundPresentationEstablished = false
    private var foregroundPresentationRepairScheduled = false
    private let launchPresentationPolicy = LaunchPresentationPolicy.from(arguments: CommandLine.arguments)

    func applicationDidFinishLaunching(_ notification: Notification) {
        if XHubCLIRunner.isCLIInvocation(arguments: CommandLine.arguments) {
            return
        }
        launchStartedAt = Date()
        NSApp.setActivationPolicy(.regular)
        HubDiagnostics.log("app.launch didFinishLaunching presentation=\(launchPresentationPolicy)")

        LegacyBridgeProcessCleanup.terminateLegacyProcessesIfNeeded()

        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep, .latencyCritical],
            reason: "REL Flow Hub timers (IPC/background refresh)"
        )

        if NotificationSupport.isAvailable {
            UNUserNotificationCenter.current().delegate = self
        }
        registerWorkspacePowerObservers()

        let embeddedBridge = EmbeddedBridgeRunner()
        embeddedBridge.start()
        embeddedBridgeRunner = embeddedBridge

        RemoteModelStorage.syncEnabledRemoteModelsIntoModelState()

        let store = HubStore.shared
        ensurePresentationControllers(store: store, resetFrames: false, reason: "launch")
        if launchPresentationPolicy == .background {
            statusBarController = StatusBarController(store: store)
        } else {
            ensureForegroundPresentation(reason: "launch_immediate")
            scheduleForegroundPresentationRetry(after: 0.35, reason: "launch_retry_350ms")
            scheduleForegroundPresentationRetry(after: 1.2, reason: "launch_retry_1200ms")
        }

        HubLaunchStateMachine.shared.start(bridgeStarted: true)
        if launchPresentationPolicy == .background {
            HubDiagnostics.log("app.launch background_mode_ready")
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

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        HubDiagnostics.log("app.terminate requested")
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        HubDiagnostics.log("app.terminate willTerminate")
        HubLaunchStateMachine.shared.stop()
        embeddedBridgeRunner?.stop()
        embeddedBridgeRunner = nil
        unregisterWorkspacePowerObservers()
        HubGRPCServerSupport.shared.stop()
        HubServingPowerManager.shared.shutdown()
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
        ensureForegroundPresentation(reason: "reopen")
        return true
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        guard launchPresentationPolicy == .foreground else { return }
        guard !foregroundPresentationEstablished else { return }
        if Date().timeIntervalSince(launchStartedAt) <= 8.0 {
            ensureForegroundPresentation(reason: "did_become_active")
        }
    }

    @objc private func toggleFloatingWindow() {
        floatingController?.toggle()
    }

    @objc private func openMainPanel() {
        ensureForegroundPresentation(reason: "open_main_notification")
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard !urls.isEmpty else { return }
        ensureForegroundPresentation(reason: "open_url")
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

    private func showMainPanel() {
        mainPanelController?.show()
        if mainPanelController?.isVisible == true {
            foregroundPresentationEstablished = true
        }
        maybeCheckInstallLocation()
    }

    private func ensureForegroundPresentation(reason: String) {
        guard launchPresentationPolicy == .foreground else { return }
        let store = HubStore.shared
        ensurePresentationControllers(store: store, resetFrames: false, reason: reason)
        let mainVisible = mainPanelController?.isVisible ?? false
        let floatingVisible = floatingController?.isVisible ?? false
        HubDiagnostics.log(
            "app.presentation.ensure reason=\(reason) mainVisible=\(mainVisible ? 1 : 0) floatingVisible=\(floatingVisible ? 1 : 0) hasMain=\(mainPanelController != nil ? 1 : 0) hasFloating=\(floatingController != nil ? 1 : 0)"
        )

        NSApp.activate(ignoringOtherApps: true)
        floatingController?.show()
        if !mainVisible {
            showMainPanel()
        } else {
            foregroundPresentationEstablished = true
        }
        scheduleForegroundPresentationRepairIfNeeded(reason: reason)
    }

    private func scheduleForegroundPresentationRetry(after delay: TimeInterval, reason: String) {
        guard launchPresentationPolicy == .foreground else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            guard !(self.mainPanelController?.isVisible ?? false) else {
                self.foregroundPresentationEstablished = true
                return
            }
            self.ensureForegroundPresentation(reason: reason)
        }
    }

    private func maybeCheckInstallLocation() {
        guard !didCheckInstallLocation else { return }
        didCheckInstallLocation = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            AppInstallDoctor.showInstallAlertIfNeeded()
        }
    }

    private func ensurePresentationControllers(store: HubStore, resetFrames: Bool, reason: String) {
        if resetFrames {
            UserDefaults.standard.removeObject(forKey: "relflowhub_main_frame")
            UserDefaults.standard.removeObject(forKey: "relflowhub_floating_frame")
        }

        if floatingController == nil {
            floatingController = FloatingPanelController(store: store)
            HubDiagnostics.log("app.presentation.controller_create target=floating reason=\(reason) reset=\(resetFrames ? 1 : 0)")
        }
        if mainPanelController == nil {
            mainPanelController = MainPanelController(store: store)
            HubDiagnostics.log("app.presentation.controller_create target=main reason=\(reason) reset=\(resetFrames ? 1 : 0)")
        }
    }

    private func scheduleForegroundPresentationRepairIfNeeded(reason: String) {
        guard launchPresentationPolicy == .foreground else { return }
        guard !foregroundPresentationRepairScheduled else { return }
        foregroundPresentationRepairScheduled = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self else { return }
            self.foregroundPresentationRepairScheduled = false

            let mainVisible = self.mainPanelController?.isVisible ?? false
            let floatingVisible = self.floatingController?.isVisible ?? false
            guard !mainVisible, !floatingVisible else {
                if mainVisible {
                    self.foregroundPresentationEstablished = true
                }
                return
            }

            HubDiagnostics.log("app.presentation.repair reason=\(reason) action=rebuild_reset_frames")
            self.floatingController = nil
            self.mainPanelController = nil
            self.ensurePresentationControllers(store: HubStore.shared, resetFrames: true, reason: "\(reason)_repair")
            self.floatingController?.show()
            self.showMainPanel()

            let repairedMainVisible = self.mainPanelController?.isVisible ?? false
            let repairedFloatingVisible = self.floatingController?.isVisible ?? false
            HubDiagnostics.log(
                "app.presentation.repair_done reason=\(reason) mainVisible=\(repairedMainVisible ? 1 : 0) floatingVisible=\(repairedFloatingVisible ? 1 : 0)"
            )
        }
    }

    private func registerWorkspacePowerObservers() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(handleSystemWillSleep), name: NSWorkspace.willSleepNotification, object: nil)
        center.addObserver(self, selector: #selector(handleSystemDidWake), name: NSWorkspace.didWakeNotification, object: nil)
        center.addObserver(self, selector: #selector(handleScreensDidSleep), name: NSWorkspace.screensDidSleepNotification, object: nil)
        center.addObserver(self, selector: #selector(handleScreensDidWake), name: NSWorkspace.screensDidWakeNotification, object: nil)
    }

    private func unregisterWorkspacePowerObservers() {
        NSWorkspace.shared.notificationCenter.removeObserver(self, name: NSWorkspace.willSleepNotification, object: nil)
        NSWorkspace.shared.notificationCenter.removeObserver(self, name: NSWorkspace.didWakeNotification, object: nil)
        NSWorkspace.shared.notificationCenter.removeObserver(self, name: NSWorkspace.screensDidSleepNotification, object: nil)
        NSWorkspace.shared.notificationCenter.removeObserver(self, name: NSWorkspace.screensDidWakeNotification, object: nil)
    }

    @objc private func handleSystemWillSleep() {
        let grpc = HubGRPCServerSupport.shared
        HubDiagnostics.log(
            "power.system_will_sleep auto_start=\(grpc.autoStart ? 1 : 0) serving=\(grpc.isServingAvailable ? 1 : 0) running=\(grpc.isRunning ? 1 : 0) host=\(grpc.xtTerminalInternetHost ?? "-")"
        )
    }

    @objc private func handleSystemDidWake() {
        let grpc = HubGRPCServerSupport.shared
        HubDiagnostics.log(
            "power.system_did_wake auto_start=\(grpc.autoStart ? 1 : 0) serving=\(grpc.isServingAvailable ? 1 : 0) running=\(grpc.isRunning ? 1 : 0) host=\(grpc.xtTerminalInternetHost ?? "-")"
        )
        grpc.refresh()
    }

    @objc private func handleScreensDidSleep() {
        HubDiagnostics.log("power.screens_did_sleep")
    }

    @objc private func handleScreensDidWake() {
        HubDiagnostics.log("power.screens_did_wake")
    }
}
