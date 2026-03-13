import Foundation
import Darwin
import AppKit
import EventKit
import SwiftUI
@preconcurrency import UserNotifications
import RELFlowHubCore

private extension FileManager {
    func directoryExists(atPath path: String) -> Bool {
        var isDir: ObjCBool = false
        return fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }
}

// If a Process is still running when it deinitializes, Foundation throws an ObjC exception which
// aborts the entire app. We keep a small bounded set of "leaked" processes as a last resort to
// prevent startup crashes if we fail to terminate within our timeouts.
@MainActor private var runCaptureLeakedProcs: [Process] = []
@MainActor private func leakRunningCaptureProcess(_ p: Process) {
    runCaptureLeakedProcs.append(p)
    if runCaptureLeakedProcs.count > 8 {
        runCaptureLeakedProcs.removeFirst(runCaptureLeakedProcs.count - 8)
    }
}

@MainActor
private func runCapture(_ exe: String, _ args: [String], env: [String: String] = [:], timeoutSec: Double = 1.2) -> (code: Int32, out: String, err: String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: exe)
    p.arguments = args
    var e = ProcessInfo.processInfo.environment
    for (k, v) in env { e[k] = v }
    p.environment = e
    let outPipe = Pipe()
    let errPipe = Pipe()
    p.standardOutput = outPipe
    p.standardError = errPipe
    do {
        try p.run()
    } catch {
        return (code: 127, out: "", err: String(describing: error))
    }

    var timedOut = false
    let deadline = Date().addingTimeInterval(timeoutSec)
    while p.isRunning && Date() < deadline {
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.03))
    }
    if p.isRunning {
        timedOut = true
        p.terminate()
        // Give the process a moment to exit gracefully.
        let termDeadline = Date().addingTimeInterval(0.6)
        while p.isRunning && Date() < termDeadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.03))
        }
        // Last resort: SIGKILL to guarantee we don't crash on Process dealloc.
        if p.isRunning {
            let pid = p.processIdentifier
            if pid > 0 {
                kill(pid, SIGKILL)
            }
            let killDeadline = Date().addingTimeInterval(0.6)
            while p.isRunning && Date() < killDeadline {
                RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.03))
            }
        }
    }

    if p.isRunning {
        // Avoid touching terminationStatus and avoid deinit-crash; keep it alive and fail fast.
        leakRunningCaptureProcess(p)
        return (code: 124, out: "", err: "timeout")
    }

    let outData = (try? outPipe.fileHandleForReading.readToEnd()) ?? Data()
    let errData = (try? errPipe.fileHandleForReading.readToEnd()) ?? Data()
    try? outPipe.fileHandleForReading.close()
    try? errPipe.fileHandleForReading.close()
    let out = String(data: outData, encoding: .utf8) ?? ""
    let err = String(data: errData, encoding: .utf8) ?? ""
    let code: Int32 = timedOut ? 124 : p.terminationStatus
    return (code: code, out: out.trimmingCharacters(in: .whitespacesAndNewlines), err: err.trimmingCharacters(in: .whitespacesAndNewlines))
}

@MainActor
var hubAuditDatabaseURLProvider: @Sendable () -> URL = {
    SharedPaths.ensureHubDirectory()
        .appendingPathComponent("hub_grpc", isDirectory: true)
        .appendingPathComponent("hub.sqlite3")
}

@MainActor
func appendSupervisorProjectActionAuditToHubDB(_ payload: IPCSupervisorProjectActionAuditPayload) -> Bool {
    let eventId = payload.eventId.trimmingCharacters(in: .whitespacesAndNewlines)
    let projectId = payload.projectId.trimmingCharacters(in: .whitespacesAndNewlines)
    let projectName = payload.projectName.trimmingCharacters(in: .whitespacesAndNewlines)
    let actionEventType = payload.eventType.trimmingCharacters(in: .whitespacesAndNewlines)
    let severity = payload.severity.trimmingCharacters(in: .whitespacesAndNewlines)
    let actionTitle = payload.actionTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    let actionSummary = payload.actionSummary.trimmingCharacters(in: .whitespacesAndNewlines)
    let whyItMatters = payload.whyItMatters.trimmingCharacters(in: .whitespacesAndNewlines)
    let nextAction = payload.nextAction.trimmingCharacters(in: .whitespacesAndNewlines)
    let deliveryChannel = payload.deliveryChannel.trimmingCharacters(in: .whitespacesAndNewlines)
    let deliveryStatus = payload.deliveryStatus.trimmingCharacters(in: .whitespacesAndNewlines)
    let auditRef = payload.auditRef.trimmingCharacters(in: .whitespacesAndNewlines)

    guard !eventId.isEmpty,
          !projectId.isEmpty,
          !projectName.isEmpty,
          !actionEventType.isEmpty,
          !severity.isEmpty,
          !actionTitle.isEmpty,
          !actionSummary.isEmpty,
          !whyItMatters.isEmpty,
          !nextAction.isEmpty,
          !deliveryChannel.isEmpty,
          !deliveryStatus.isEmpty,
          !auditRef.isEmpty else {
        return false
    }

    let dbURL = hubAuditDatabaseURLProvider()
    guard FileManager.default.fileExists(atPath: dbURL.path) else {
        return false
    }

    let occurredAtMs = max(0, payload.occurredAtMs)
    let createdAtMs = occurredAtMs > 0 ? occurredAtMs : Int64(Date().timeIntervalSince1970 * 1000.0)
    let storedEventType = "supervisor.project_action.\(actionEventType)"
    let source = payload.source?.trimmingCharacters(in: .whitespacesAndNewlines)
    let jurisdictionRole = payload.jurisdictionRole?.trimmingCharacters(in: .whitespacesAndNewlines)
    let grantedScope = payload.grantedScope?.trimmingCharacters(in: .whitespacesAndNewlines)

    let ext: [String: Any] = [
        "event_id": eventId,
        "project_id": projectId,
        "project_name": projectName,
        "event_type": actionEventType,
        "severity": severity,
        "action_title": actionTitle,
        "action_summary": actionSummary,
        "why_it_matters": whyItMatters,
        "next_action": nextAction,
        "occurred_at_ms": occurredAtMs,
        "delivery_channel": deliveryChannel,
        "delivery_status": deliveryStatus,
        "jurisdiction_role": jurisdictionRole ?? "",
        "granted_scope": grantedScope ?? "",
        "audit_ref": auditRef,
        "audit_event_type": "supervisor.project_action.delivery",
        "source": source ?? "x_terminal_supervisor",
    ]
    guard JSONSerialization.isValidJSONObject(ext),
          let extData = try? JSONSerialization.data(withJSONObject: ext, options: []),
          let extJSON = String(data: extData, encoding: .utf8) else {
        return false
    }

    func sqlQuoted(_ text: String) -> String {
        "'\(text.replacingOccurrences(of: "'", with: "''"))'"
    }
    func sqlNullable(_ text: String?) -> String {
        guard let text, !text.isEmpty else { return "NULL" }
        return sqlQuoted(text)
    }

    let sql = """
PRAGMA busy_timeout=1500;
INSERT OR IGNORE INTO audit_events(
  event_id, event_type, created_at_ms, severity,
  device_id, user_id, app_id, project_id, session_id,
  request_id, capability, model_id,
  prompt_tokens, completion_tokens, total_tokens, cost_usd_estimate,
  network_allowed, ok, error_code, error_message, duration_ms, ext_json
) VALUES (
  \(sqlQuoted("supervisor_project_action_\(auditRef.lowercased())")), \(sqlQuoted(storedEventType)), \(createdAtMs), \(sqlQuoted(severity)),
  'x_terminal', 'x_terminal', 'x_terminal', \(sqlQuoted(projectId)),
  NULL, \(sqlQuoted(eventId)),
  'supervisor_project_action_feed', NULL,
  NULL, NULL, NULL, NULL,
  NULL, 1, NULL, NULL,
  NULL, \(sqlQuoted(extJSON))
);
"""

    let result = runCapture("/usr/bin/sqlite3", [dbURL.path, sql], timeoutSec: 1.5)
    return result.code == 0
}

@MainActor
private func waitForProcessExit(_ p: Process, timeoutSec: Double) -> Bool {
    let deadline = Date().addingTimeInterval(max(0.1, timeoutSec))
    while p.isRunning && Date() < deadline {
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.03))
    }
    return !p.isRunning
}

@MainActor
final class HubStore: ObservableObject {
    static let shared = HubStore()

    @Published private(set) var notifications: [HubNotification] = []
    @Published var ipcStatus: String = "IPC: starting…"
    @Published var ipcPath: String = ""

    // Optional: launcher path for FA Tracker (either a .app bundle or a .command script).
    @Published var faTrackerLauncherPath: String = UserDefaults.standard.string(forKey: "relflowhub_fatracker_launcher_path") ?? "" {
        didSet {
            UserDefaults.standard.set(faTrackerLauncherPath, forKey: "relflowhub_fatracker_launcher_path")
        }
    }

    // Preferred: open FA Tracker by bundle id (works well for DMG-installed apps; avoids file permissions).
    @Published var faTrackerBundleId: String = UserDefaults.standard.string(forKey: "relflowhub_fatracker_bundle_id") ?? "FAtracker" {
        didSet {
            UserDefaults.standard.set(faTrackerBundleId, forKey: "relflowhub_fatracker_bundle_id")
        }
    }

    private let faTrackerLauncherBookmarkKey = "relflowhub_fatracker_launcher_bookmark"

    @Published var floatingMode: FloatingMode = .orb {
        didSet {
            UserDefaults.standard.set(floatingMode.rawValue, forKey: "relflowhub_floating_mode")
        }
    }

    @Published var meetingUrgentMinutes: Int = 5 {
        didSet {
            let v = max(1, min(30, meetingUrgentMinutes))
            if v != meetingUrgentMinutes { meetingUrgentMinutes = v }
            UserDefaults.standard.set(v, forKey: "relflowhub_meeting_urgent_minutes")
        }
    }

    @Published var showModelsDrawer: Bool = false {
        didSet {
            UserDefaults.standard.set(showModelsDrawer, forKey: "relflowhub_show_models_drawer")
        }
    }
    @Published var calendarStatus: String = "Calendar: not enabled"
    @Published private(set) var meetings: [HubMeeting] = []
    @Published private(set) var specialDaysToday: [String] = []

    // Meeting reminders (Card/orb) should stop once the user has opened the meeting.
    // We persist "dismissed until endAt" so both Card and Inbox behave consistently.
    @Published private var dismissedMeetingsUntilByKey: [String: Double] = [:]

    private let dismissedMeetingsKey = "relflowhub_dismissed_meetings_v1"

    // -------------------- AI runtime (local provider worker) --------------------
    @Published var aiRuntimeAutoStart: Bool = UserDefaults.standard.bool(forKey: "relflowhub_ai_runtime_autostart") {
        didSet {
            UserDefaults.standard.set(aiRuntimeAutoStart, forKey: "relflowhub_ai_runtime_autostart")
        }
    }
    @Published var aiRuntimePython: String = UserDefaults.standard.string(forKey: "relflowhub_ai_runtime_python") ?? "" {
        didSet {
            UserDefaults.standard.set(aiRuntimePython, forKey: "relflowhub_ai_runtime_python")
        }
    }
    @Published private(set) var aiRuntimeStatusText: String = "Runtime: unknown"
    @Published private(set) var aiRuntimeLastError: String = ""
    @Published private(set) var aiRuntimeLastTestText: String = ""
    @Published private(set) var aiRuntimeProviderSummaryText: String = ""
    @Published private(set) var aiRuntimeDoctorSummaryText: String = ""

    // Routing defaults persisted for the python runtime (task_type -> preferred model id).
    @Published private(set) var routingPreferredModelIdByTask: [String: String] = [:]

    @Published var calendarRemindMinutes: Int = 10 {
        didSet {
            let m = max(1, min(180, calendarRemindMinutes))
            if m != calendarRemindMinutes { calendarRemindMinutes = m }
            UserDefaults.standard.set(m, forKey: "relflowhub_calendar_remind_minutes")
            calendar?.updateRemindMinutes(m)
            refreshCalendar()
        }
    }

    private var server: UnixSocketServer?
    private var fileIPC: FileIPC?
    private var calendar: CalendarPipeline?

    // -------------------- Integrations (counts-only) --------------------
    // Calendar authorization state is queried via EventKit (not via calendarStatus text).
    // IMPORTANT: avoid string matching for "enabled" because "not enabled" contains it.
    var calendarAuthStatus: EKAuthorizationStatus {
        EKEventStore.authorizationStatus(for: .event)
    }

    var calendarHasReadAccess: Bool {
        let st = calendarAuthStatus
        if #available(macOS 14.0, *) {
            return st == .authorized || st == .fullAccess
        }
        return st == .authorized
    }

    var calendarDeniedOrRestricted: Bool {
        let st = calendarAuthStatus
        return st == .denied || st == .restricted
    }

    var calendarNotDetermined: Bool {
        calendarAuthStatus == .notDetermined
    }

    // Default OFF: users explicitly opt-in to permissions.
    @Published var integrationCalendarEnabled: Bool = UserDefaults.standard.object(forKey: "relflowhub_integration_calendar_enabled") as? Bool ?? false {
        didSet {
            UserDefaults.standard.set(integrationCalendarEnabled, forKey: "relflowhub_integration_calendar_enabled")

            // Cancel any in-flight enable retry.
            calendarEnableRetryTimer?.invalidate()
            calendarEnableRetryTimer = nil

            if integrationCalendarEnabled {
                // Avoid the "request while inactive" issue.
                calendarStatus = "Calendar: requesting access…"
                NSApp.activate(ignoringOtherApps: true)

                // Small delay so the toggle UI commits before the system permission prompt.
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 180_000_000)
                    self.requestCalendarAccessAndStart()

                    // Retry status refresh for a short window; TCC state can lag.
                    self.calendarEnableRetryRemaining = 16
                    self.calendarEnableRetryTimer?.invalidate()
                    self.calendarEnableRetryTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                        Task { @MainActor in
                            guard let self else { return }
                            self.calendarEnableRetryRemaining -= 1
                            self.refreshCalendarStatusOnly()

                            let st = EKEventStore.authorizationStatus(for: .event)
                            if st == .denied || st == .restricted {
                                self.calendarEnableRetryTimer?.invalidate()
                                self.calendarEnableRetryTimer = nil
                                return
                            }
                            if self.calendarHasReadAccess {
                                self.calendarEnableRetryTimer?.invalidate()
                                self.calendarEnableRetryTimer = nil
                                self.refreshCalendar()
                                return
                            }
                            if self.calendarEnableRetryRemaining <= 0 {
                                self.calendarEnableRetryTimer?.invalidate()
                                self.calendarEnableRetryTimer = nil
                                return
                            }
                        }
                    }
                }
            } else {
                calendar?.stopPolling()
                refreshCalendarStatusOnly()
                meetings = []
            }
            updateIntegrationsPresence()
        }
    }
    @Published var integrationFATrackerEnabled: Bool = UserDefaults.standard.object(forKey: "relflowhub_integration_fatracker_enabled") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(integrationFATrackerEnabled, forKey: "relflowhub_integration_fatracker_enabled")
            if !integrationFATrackerEnabled {
                removeNotificationsBySource("FAtracker")
            }
        }
    }
    @Published var integrationMailEnabled: Bool = UserDefaults.standard.bool(forKey: "relflowhub_integration_mail_enabled") {
        didSet {
            UserDefaults.standard.set(integrationMailEnabled, forKey: "relflowhub_integration_mail_enabled")
            if integrationMailEnabled {
                NSApp.activate(ignoringOtherApps: true)
                if !DockBadgeReader.ensureAccessibilityTrusted(prompt: true) {
                    // On newer macOS builds, the prompt may not surface reliably; open the page.
                    SystemSettingsLinks.openAccessibilityPrivacy()
                }
                // Pull counts immediately so users see something right away.
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    self.pollDockBadgeIntegrations()
                }
            } else {
                removeNotificationByDedupeKey("mail_unread")
            }
            updateIntegrationsPolling()
            updateIntegrationsPresence()
        }
    }
    @Published var integrationMessagesEnabled: Bool = UserDefaults.standard.bool(forKey: "relflowhub_integration_messages_enabled") {
        didSet {
            UserDefaults.standard.set(integrationMessagesEnabled, forKey: "relflowhub_integration_messages_enabled")
            if integrationMessagesEnabled {
                NSApp.activate(ignoringOtherApps: true)
                if !DockBadgeReader.ensureAccessibilityTrusted(prompt: true) {
                    SystemSettingsLinks.openAccessibilityPrivacy()
                }
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    self.pollDockBadgeIntegrations()
                }
            } else {
                removeNotificationByDedupeKey("messages_unread")
            }
            updateIntegrationsPolling()
            updateIntegrationsPresence()
        }
    }
    @Published var integrationSlackEnabled: Bool = UserDefaults.standard.bool(forKey: "relflowhub_integration_slack_enabled") {
        didSet {
            UserDefaults.standard.set(integrationSlackEnabled, forKey: "relflowhub_integration_slack_enabled")
            if integrationSlackEnabled {
                NSApp.activate(ignoringOtherApps: true)
                if !DockBadgeReader.ensureAccessibilityTrusted(prompt: true) {
                    SystemSettingsLinks.openAccessibilityPrivacy()
                }
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    self.pollDockBadgeIntegrations()
                }
            } else {
                removeNotificationByDedupeKey("slack_updates")
            }
            updateIntegrationsPolling()
            updateIntegrationsPresence()
        }
    }

    @Published private(set) var integrationsStatusText: String = ""
    @Published private(set) var integrationsDebugText: String = ""
    @Published private(set) var pendingNetworkRequests: [HubNetworkRequest] = []
    @Published private(set) var pendingPairingRequests: [HubPairingRequest] = []

    // Dock Agent (optional helper) status.
    @Published private(set) var dockAgentStatusText: String = "Dock Agent: unknown"
    @Published private(set) var dockAgentAutoStartText: String = "Auto-start: unknown"
    private var dockAgentStatusTimer: Timer?

    private var integrationsPollTimer: Timer?
    private var integrationsPresenceTimer: Timer?
    private var calendarEnableRetryTimer: Timer?
    private var calendarEnableRetryRemaining: Int = 0

    private var lastClientTouchById: [String: Double] = [:]
    // When an external agent pushes counts-only notifications (mail/messages/slack), we
    // temporarily disable the built-in polling for that key to avoid fighting updates.
    private var externalCountsUpdateAtByKey: [String: Double] = [:]
    private var demoSatellitesTimer: Timer?
    private var demoSatellitesEndAt: Double = 0

    private var persistNotificationsTimer: Timer?

    private var aiRuntimeProcess: Process?
    private var aiRuntimeLogHandle: FileHandle?
    private var aiRuntimeMonitorTimer: Timer?
    private var networkRequestsTimer: Timer?
    private var pairingRequestsTimer: Timer?
    private var alwaysOnKeepaliveTimer: Timer?
    private var aiRuntimeLastLaunchAt: Double = 0
    private var aiRuntimeStopRequestedAt: Double = 0
    private var aiRuntimeNextStartAttemptAt: Double = 0
    private var aiRuntimeFailCount: Int = 0
    // If a teammate upgrades the DMG while an older runtime process is still running,
    // the UI can start sending new commands (e.g. `bench`) that the old script does not
    // recognize, resulting in `unknown_action`. Restart once per app run when we detect
    // a runtime version mismatch.
    private var didForceRestartRuntimeForVersionMismatch: Bool = false
    let bridge = BridgeSupport.shared
    let grpc = HubGRPCServerSupport.shared
    let models = ModelStore.shared
    let clients = ClientStore.shared

    private static let defaultAlwaysOnSeconds: Int = 8 * 60 * 60

    private init() {
        HubDiagnostics.log("HubStore.init pid=\(getpid()) appPath=\(Bundle.main.bundleURL.path)")
        // Default integrations OFF for new installs (opt-in permissions).
        if UserDefaults.standard.object(forKey: "relflowhub_integration_calendar_enabled") == nil {
            integrationCalendarEnabled = false
        }
        if UserDefaults.standard.object(forKey: "relflowhub_integration_mail_enabled") == nil {
            integrationMailEnabled = false
        }
        if UserDefaults.standard.object(forKey: "relflowhub_integration_messages_enabled") == nil {
            integrationMessagesEnabled = false
        }
        if UserDefaults.standard.object(forKey: "relflowhub_integration_slack_enabled") == nil {
            integrationSlackEnabled = false
        }

        // For DMG installs we want a good out-of-box experience: the runtime should come up
        // automatically once the user loads a model.
        if UserDefaults.standard.object(forKey: "relflowhub_ai_runtime_autostart") == nil {
            aiRuntimeAutoStart = true
        }

        loadNotificationsFromDisk()

        if let s = UserDefaults.standard.string(forKey: "relflowhub_floating_mode"),
           let m = FloatingMode(rawValue: s) {
            floatingMode = m
        }

        let um = UserDefaults.standard.integer(forKey: "relflowhub_meeting_urgent_minutes")
        if um > 0 { meetingUrgentMinutes = max(1, min(30, um)) }

        showModelsDrawer = UserDefaults.standard.bool(forKey: "relflowhub_show_models_drawer")

        let m = UserDefaults.standard.integer(forKey: "relflowhub_calendar_remind_minutes")
        if m > 0 { calendarRemindMinutes = m }
        startIPC()
        startNetworkRequestsPolling()
        startPairingRequestsPolling()
        startAlwaysOnKeepalive()
        setupNotificationsAuthorizationState()
        refreshCalendarStatusOnly()

        // If the user enabled Calendar integration, try to bring it up early.
        // (The actual permission prompt is still user-controlled.)
        if integrationCalendarEnabled {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 250_000_000)
                self.requestCalendarAccessAndStart()
            }
        }

        loadDismissedMeetings()

        if aiRuntimePython.isEmpty {
            aiRuntimePython = defaultPythonPath()
        }
        startAIRuntimeMonitoring()

        loadRoutingSettings()

        // Counts-only integrations (Mail/Messages/Slack) are driven by Dock badges.
        updateIntegrationsPolling()
        updateIntegrationsPresence()

        startDockAgentStatusPolling()

        // Ensure derived state is correct after restoring notifications.
        sort()
        updateSummary()
    }

    private func hubBaseDirURL() -> URL {
        // Keep consistent with FileIPC's base directory choice.
        let group = SharedPaths.appGroupDirectory()
        let container = SharedPaths.containerDataDirectory()?.appendingPathComponent("RELFlowHub", isDirectory: true)
        return group ?? container ?? SharedPaths.ensureHubDirectory()
    }

    private func startDockAgentStatusPolling() {
        dockAgentStatusTimer?.invalidate()
        dockAgentStatusTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshDockAgentStatus()
            }
        }
        refreshDockAgentStatus()
    }

    func refreshDockAgentStatus() {
        let base = hubBaseDirURL()
        let f = base.appendingPathComponent("dock_agent_status.json")
        guard let data = try? Data(contentsOf: f),
              let st = try? JSONDecoder().decode(DockAgentStatusFile.self, from: data) else {
            dockAgentStatusText = "Dock Agent: not detected"
            dockAgentAutoStartText = "Auto-start: unknown"
            return
        }

        let age = Date().timeIntervalSince1970 - st.updatedAt
        let running = age < 130.0
        dockAgentStatusText = running ? "Dock Agent: running" : "Dock Agent: not running"
        dockAgentAutoStartText = st.autoStartLoaded ? "Auto-start: enabled" : (st.autoStartInstalled ? "Auto-start: installed" : "Auto-start: disabled")
    }

    func enableDockAgentAutoStart() {
        openDockAgentWithArgs(["--install-launchagent"])
    }

    func disableDockAgentAutoStart() {
        openDockAgentWithArgs(["--uninstall-launchagent"])
    }

    private func openDockAgentWithArgs(_ args: [String]) {
        guard let url = dockAgentAppURL() else {
            integrationsDebugText = (integrationsDebugText + "\nDockAgent: not found").trimmingCharacters(in: .whitespacesAndNewlines)
            return
        }
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.arguments = args
        cfg.activates = false
        NSWorkspace.shared.openApplication(at: url, configuration: cfg) { _, _ in
            // Best-effort; status file will update shortly if the agent ran.
        }
    }

    private func dockAgentAppURL() -> URL? {
        // Prefer LaunchServices lookup by bundle id.
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.rel.flowhub.dockagent") {
            return url
        }
        // Fallback: common install location.
        let apps = URL(fileURLWithPath: "/Applications", isDirectory: true)
        let candidate = apps.appendingPathComponent("RELFlowHubDockAgent.app")
        if FileManager.default.fileExists(atPath: candidate.path) {
            return candidate
        }
        return nil
    }

    func refreshIntegrationsNow() {
        updateIntegrationsPolling()
        pollDockBadgeIntegrations()
        updateIntegrationsPresence()
    }

    private func updateIntegrationsPresence() {
        let any = integrationCalendarEnabled || integrationMailEnabled || integrationMessagesEnabled || integrationSlackEnabled
        if !any {
            integrationsPresenceTimer?.invalidate()
            integrationsPresenceTimer = nil
            removeIntegrationPresenceFiles()
            return
        }

        if integrationsPresenceTimer == nil {
            // Keep integration satellites alive under the 12s TTL.
            integrationsPresenceTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.writeIntegrationPresenceFiles()
                }
            }
        }
        writeIntegrationPresenceFiles()
    }

    private func removeIntegrationPresenceFiles() {
        let dir = ClientStorage.dir()
        let ids = ["sys_calendar", "sys_mail", "sys_messages", "sys_slack"]
        for id in ids {
            let url = dir.appendingPathComponent("\(id).json")
            try? FileManager.default.removeItem(at: url)
        }
        clients.refresh()
    }

    private func writeIntegrationPresenceFiles() {
        let now = Date().timeIntervalSince1970
        let dir = ClientStorage.dir()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        func upsert(id: String, name: String, enabled: Bool) {
            let url = dir.appendingPathComponent("\(id).json")
            guard enabled else {
                try? FileManager.default.removeItem(at: url)
                return
            }
            let hb = HubClientHeartbeat(appId: id, appName: name, activity: .idle, aiEnabled: false, updatedAt: now)
            if let data = try? JSONEncoder().encode(hb) {
                try? data.write(to: url, options: .atomic)
            }
        }

        upsert(id: "sys_calendar", name: "Calendar", enabled: integrationCalendarEnabled)
        upsert(id: "sys_mail", name: "Mail", enabled: integrationMailEnabled)
        upsert(id: "sys_messages", name: "Messages", enabled: integrationMessagesEnabled)
        upsert(id: "sys_slack", name: "Slack", enabled: integrationSlackEnabled)

        // Pull immediately so the floating orb reflects it quickly.
        clients.refresh()
    }

    private func updateIntegrationsPolling() {
        let any = integrationMailEnabled || integrationMessagesEnabled || integrationSlackEnabled
        if !any {
            integrationsPollTimer?.invalidate()
            integrationsPollTimer = nil
            integrationsStatusText = "Integrations: off"
            return
        }

        if integrationsPollTimer == nil {
            // Keep it light; this is counts-only.
            integrationsPollTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.pollDockBadgeIntegrations()
                }
            }
        }
        pollDockBadgeIntegrations()
    }

    private func pollDockBadgeIntegrations() {
        let now = Date().timeIntervalSince1970
        func hasRecentExternalUpdate(_ key: String) -> Bool {
            guard let t = externalCountsUpdateAtByKey[key] else { return false }
            return (now - t) < 90.0
        }

        let trusted = DockBadgeReader.ensureAccessibilityTrusted(prompt: false)
        if !trusted {
            integrationsStatusText = "Integrations: need Accessibility permission"
            let bid = Bundle.main.bundleIdentifier ?? "(unknown)"
            let appPath = Bundle.main.bundleURL.path
            var dbg: [String] = [
                "AXTrusted=false",
                "bundleId=\(bid)",
                "appPath=\(appPath)",
                "Tip: the app you run must match the app you enabled in System Settings → Privacy & Security → Accessibility. Quit & relaunch after enabling.",
            ]
            if integrationMailEnabled { dbg.append("Mail: skipped") }
            if integrationMessagesEnabled { dbg.append("Messages: skipped") }
            if integrationSlackEnabled { dbg.append("Slack: skipped") }
            integrationsDebugText = dbg.joined(separator: "\n")
            return
        }

        // Prefer Dock badge counts (best for Slack). If the Dock AX tree is inaccessible
        // on this OS build, fall back to AppleScript for Mail/Messages (counts-only).
        func resolvedCounts(bundleId: String, preferAppleScript: Bool) -> (ok: Bool, count: Int, debug: String) {
            let dock = DockBadgeReader.badgeCountForBundleId(bundleId)
            if dock.debug.hasPrefix("dock_item_not_found") {
                if preferAppleScript {
                    if bundleId == "com.apple.mail" {
                        let r = AppleScriptCountsReader.mailUnreadCount()
                        if r.ok { return (true, r.count, "fallback:\(r.debug)") }
                        return (dock.ok, dock.count, "dock=\(dock.debug) applescript=\(r.debug)")
                    }
                    if bundleId == "com.apple.MobileSMS" {
                        let r = AppleScriptCountsReader.messagesUnreadCount()
                        if r.ok { return (true, r.count, "fallback:\(r.debug)") }
                        return (dock.ok, dock.count, "dock=\(dock.debug) applescript=\(r.debug)")
                    }
                }
            }
            return (dock.ok, dock.count, dock.debug)
        }

        let mail: (ok: Bool, count: Int, debug: String)? = {
            guard integrationMailEnabled else { return nil }
            // If a Dock agent is feeding us counts, don't fight it.
            if hasRecentExternalUpdate("mail_unread") {
                return nil
            }
            return resolvedCounts(bundleId: "com.apple.mail", preferAppleScript: true)
        }()

        // Messages: prefer the external Dock Agent on macOS 26 when Dock AX is inaccessible.
        // AppleScript support for Messages is inconsistent across OS versions.
        let msgDock = integrationMessagesEnabled ? DockBadgeReader.badgeCountForBundleId("com.apple.MobileSMS") : nil
        let msg: (ok: Bool, count: Int, debug: String)? = {
            guard let msgDock else { return nil }
            if hasRecentExternalUpdate("messages_unread") { return nil }
            if msgDock.debug.contains("dockChildren=0") {
                return nil
            }
            // If Dock traversal works, use it; avoids extra Automation prompts.
            return (msgDock.ok, msgDock.count, msgDock.debug)
        }()
        // In macOS 26, sandboxed apps may not be able to enumerate the Dock AX tree
        // (dockChildren=0). In that case, Slack should be powered by an external Dock agent.
        let slackDock = integrationSlackEnabled ? DockBadgeReader.badgeCountForBundleId("com.tinyspeck.slackmacgap") : nil
        let slack: (ok: Bool, count: Int, debug: String)? = {
            guard let slackDock else { return nil }
            if hasRecentExternalUpdate("slack_updates") { return nil }
            if slackDock.debug.contains("dockChildren=0") {
                return nil
            }
            return (slackDock.ok, slackDock.count, slackDock.debug)
        }()

        var debugParts: [String] = ["AXTrusted=true"]
        if integrationMailEnabled {
            if let mail {
                debugParts.append("Mail:\(mail.debug)")
            } else if hasRecentExternalUpdate("mail_unread") {
                debugParts.append("Mail:use_dock_agent")
            } else {
                // Shouldn't happen, but keep it explicit.
                debugParts.append("Mail:unknown")
            }
        }
        if integrationMessagesEnabled {
            if let msg {
                debugParts.append("Messages:\(msg.debug)")
            } else {
                debugParts.append("Messages:use_dock_agent")
            }
        }
        if integrationSlackEnabled {
            if let slack {
                debugParts.append("Slack:\(slack.debug)")
            } else {
                debugParts.append("Slack:use_dock_agent")
            }
        }
        integrationsDebugText = debugParts.joined(separator: "\n")

        var parts: [String] = []
        if let mail { parts.append("Mail=\(mail.count)") }
        if let msg { parts.append("Messages=\(msg.count)") }
        if let slack { parts.append("Slack=\(slack.count)") }
        integrationsStatusText = parts.isEmpty ? "Integrations: off" : ("Integrations: " + parts.joined(separator: " · "))

        if let mail { upsertCountsOnlyNotification(source: "Mail", bundleId: "com.apple.mail", count: mail.count, dedupeKey: "mail_unread") }
        if let msg { upsertCountsOnlyNotification(source: "Messages", bundleId: "com.apple.MobileSMS", count: msg.count, dedupeKey: "messages_unread") }
        if let slack { upsertCountsOnlyNotification(source: "Slack", bundleId: "com.tinyspeck.slackmacgap", count: slack.count, dedupeKey: "slack_updates") }
    }

    private func lastSeenCountKey(_ dedupeKey: String) -> String {
        "relflowhub_seen_count_\(dedupeKey)"
    }

    private func setLastSeenCount(_ n: Int, dedupeKey: String) {
        UserDefaults.standard.set(max(0, n), forKey: lastSeenCountKey(dedupeKey))
    }

    private func getLastSeenCount(dedupeKey: String) -> Int {
        max(0, UserDefaults.standard.integer(forKey: lastSeenCountKey(dedupeKey)))
    }

    func upsertCountsOnlyNotification(source: String, bundleId: String, count: Int, dedupeKey: String) {
        let c = max(0, count)

        // If cleared, remove any existing sticky notification.
        if c == 0 {
            removeNotificationByDedupeKey(dedupeKey)
            // Keep last-seen in sync so a future increase triggers correctly.
            setLastSeenCount(0, dedupeKey: dedupeKey)
            return
        }

        // If the user read items inside the app, badge may decrease; ensure the
        // baseline doesn't get stuck at a higher value.
        let seen = min(getLastSeenCount(dedupeKey: dedupeKey), c)
        setLastSeenCount(seen, dedupeKey: dedupeKey)

        let shouldRemind = c > seen

        // Preserve createdAt unless the count increased (so the card/inbox doesn't "refresh" constantly).
        let existing = notifications.first(where: { $0.dedupeKey == dedupeKey })
        let prevCount = existing.flatMap { firstInt(in: $0.body) } ?? existing.flatMap { firstInt(in: $0.title) } ?? 0
        let createdAt: Double = (existing == nil || c > prevCount) ? Date().timeIntervalSince1970 : (existing?.createdAt ?? Date().timeIntervalSince1970)

        let n = HubNotification(
            id: existing?.id ?? UUID().uuidString,
            source: source,
            title: source,
            body: "\(c) unread",
            createdAt: createdAt,
            dedupeKey: dedupeKey,
            actionURL: "relflowhub://openapp?bundle_id=\(bundleId)",
            snoozedUntil: existing?.snoozedUntil,
            unread: shouldRemind
        )

        // IMPORTANT: do not call push(n) here.
        // push() has a special handling branch for counts-only dedupe keys that calls
        // upsertCountsOnlyNotification(), which would recurse and crash the app when
        // an external agent pushes counts-only notifications.
        if let idx = notifications.firstIndex(where: { $0.dedupeKey == dedupeKey }) {
            notifications[idx] = n
        } else {
            notifications.append(n)
        }
        updateSummary()
        sort()
        schedulePersistNotifications()
    }

    private func firstInt(in s: String) -> Int? {
        var digits = ""
        for ch in s {
            if ch.isNumber {
                digits.append(ch)
            } else if !digits.isEmpty {
                break
            }
        }
        return digits.isEmpty ? nil : Int(digits)
    }

    private func removeNotificationByDedupeKey(_ key: String) {
        guard !key.isEmpty else { return }
        if let idx = notifications.firstIndex(where: { $0.dedupeKey == key }) {
            notifications.remove(at: idx)
            updateSummary()
            sort()
            schedulePersistNotifications()
        }
    }

    private func removeNotificationsBySource(_ source: String) {
        let src = source.trimmingCharacters(in: .whitespacesAndNewlines)
        if src.isEmpty { return }
        let before = notifications.count
        notifications.removeAll(where: { $0.source == src })
        if notifications.count != before {
            updateSummary()
            sort()
            schedulePersistNotifications()
        }
    }

    private func loadDismissedMeetings() {
        guard let data = UserDefaults.standard.data(forKey: dismissedMeetingsKey) else {
            dismissedMeetingsUntilByKey = [:]
            return
        }
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            var out: [String: Double] = [:]
            for (k, v) in obj {
                if let d = v as? Double {
                    out[k] = d
                } else if let n = v as? NSNumber {
                    out[k] = n.doubleValue
                }
            }
            dismissedMeetingsUntilByKey = out
        } else {
            dismissedMeetingsUntilByKey = [:]
        }
        pruneDismissedMeetings(now: Date().timeIntervalSince1970)
    }

    private func saveDismissedMeetings() {
        // Keep it small: only store future entries.
        let now = Date().timeIntervalSince1970
        pruneDismissedMeetings(now: now)
        let obj: [String: Any] = dismissedMeetingsUntilByKey
        if let data = try? JSONSerialization.data(withJSONObject: obj, options: []) {
            UserDefaults.standard.set(data, forKey: dismissedMeetingsKey)
        }
    }

    private func pruneDismissedMeetings(now: Double) {
        if dismissedMeetingsUntilByKey.isEmpty { return }
        // Allow a small grace period after end.
        let cutoff = now - 60.0
        let trimmed = dismissedMeetingsUntilByKey.filter { _, until in
            until > cutoff
        }
        if trimmed.count != dismissedMeetingsUntilByKey.count {
            dismissedMeetingsUntilByKey = trimmed
        }
    }

    private func meetingDismissKey(_ m: HubMeeting) -> String {
        // Include startAt so dismissing one occurrence does not hide future recurring events.
        "\(m.id)|\(Int(m.startAt))"
    }

    func isMeetingDismissed(_ m: HubMeeting, now: Double = Date().timeIntervalSince1970) -> Bool {
        let until = dismissedMeetingsUntilByKey[meetingDismissKey(m)] ?? 0
        return until > now
    }

    func openMeeting(_ m: HubMeeting) {
        // Mark as dismissed first so card/orb stop reminding immediately even if the app switch takes time.
        if !m.id.isEmpty {
            dismissedMeetingsUntilByKey[meetingDismissKey(m)] = m.endAt
            saveDismissedMeetings()
        }
        if let s = m.joinURL, let url = URL(string: s) {
            NSWorkspace.shared.open(url)
        } else {
            // If we can't open a join link, show main UI so user can see details.
            NotificationCenter.default.post(name: .relflowhubOpenMain, object: nil)
        }
    }

    func dismissedMeetingsCount(now: Double = Date().timeIntervalSince1970) -> Int {
        pruneDismissedMeetings(now: now)
        return dismissedMeetingsUntilByKey.count
    }

    func clearDismissedMeetings() {
        dismissedMeetingsUntilByKey = [:]
        UserDefaults.standard.removeObject(forKey: dismissedMeetingsKey)
    }

    func loadRoutingSettings() {
        let st = RoutingSettingsStorage.load()
        routingPreferredModelIdByTask = st.preferredModelIdByTask
    }

    func setRoutingPreferredModel(taskType: String, modelId: String?) {
        let k = (taskType).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !k.isEmpty else { return }
        var cur = routingPreferredModelIdByTask
        let mid = (modelId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if mid.isEmpty {
            cur.removeValue(forKey: k)
        } else {
            cur[k] = mid
        }
        routingPreferredModelIdByTask = cur

        var st = RoutingSettingsStorage.load()
        st.preferredModelIdByTask = cur
        RoutingSettingsStorage.save(st)
    }

    func refreshNetworkRequests() {
        let list = HubNetworkRequestStorage.load()
        pendingNetworkRequests = list.requests.sorted { a, b in
            a.createdAt > b.createdAt
        }
    }

    func refreshPairingRequests() {
        let adminToken = grpc.localAdminToken()
        let grpcPort = grpc.port
        Task { @MainActor [weak self] in
            guard let self else { return }
            // Avoid piling up requests when the control plane is temporarily down (e.g. gRPC server not started yet).
            if self.pairingPollInFlight { return }
            self.pairingPollInFlight = true
            defer { self.pairingPollInFlight = false }

            do {
                let reqs = try await PairingHTTPClient.listPending(adminToken: adminToken, grpcPort: grpcPort)
                self.pendingPairingRequests = reqs.sorted { a, b in
                    a.createdAtMs > b.createdAtMs
                }
            } catch {
                // Silent failure: pairing server may not be running yet.
                self.pendingPairingRequests = []
            }
        }
    }

    enum NetworkDecision {
        case queued
        case autoApproved(Int)
        case denied(String)
    }

    func handleNetworkRequest(_ req: HubNetworkRequest) -> NetworkDecision {
        let appId = policyAppId(req)
        let projectId = policyProjectId(req)

        if let rule = HubNetworkPolicyStorage.match(appId: appId, projectId: projectId) {
            switch rule.mode {
            case .deny:
                return .denied("denied_by_policy")
            case .autoApprove:
                let requested = max(10, req.requestedSeconds ?? 900)
                let maxSecs = max(10, rule.maxSeconds ?? requested)
                let secs = min(requested, maxSecs)
                grantNetwork(seconds: secs, openBridge: true)
                return .autoApproved(secs)
            case .alwaysOn:
                // Always-on means "keep networking available" rather than "cap a single request".
                //
                // - If maxSeconds is set: treat it as the desired enable window.
                // - If maxSeconds is unset: default to a long window so clients don't have to keep re-requesting.
                let requested = max(10, req.requestedSeconds ?? 900)
                let desired = max(10, rule.maxSeconds ?? max(requested, Self.defaultAlwaysOnSeconds))
                grantNetwork(seconds: desired, openBridge: true)
                return .autoApproved(desired)
            case .manual:
                break
            }
        }

        _ = HubNetworkRequestStorage.add(req)
        refreshNetworkRequests()
        return .queued
    }

    func appendSupervisorIncidentAudit(_ payload: IPCSupervisorIncidentAuditPayload) -> Bool {
        let eventType = payload.eventType.trimmingCharacters(in: .whitespacesAndNewlines)
        let incidentCode = payload.incidentCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let denyCode = payload.denyCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let auditRef = payload.auditRef.trimmingCharacters(in: .whitespacesAndNewlines)
        let laneId = payload.laneId.trimmingCharacters(in: .whitespacesAndNewlines)
        let taskId = payload.taskId.trimmingCharacters(in: .whitespacesAndNewlines)
        let incidentId = payload.incidentId.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !eventType.isEmpty,
              eventType.hasPrefix("supervisor.incident."),
              eventType.hasSuffix(".handled"),
              !incidentCode.isEmpty,
              !denyCode.isEmpty,
              !auditRef.isEmpty,
              !laneId.isEmpty else {
            return false
        }

        let dbURL = hubAuditDatabaseURLProvider()
        guard FileManager.default.fileExists(atPath: dbURL.path) else {
            return false
        }

        let nowMs = Int64(Date().timeIntervalSince1970 * 1000.0)
        let detectedAtMs = max(0, payload.detectedAtMs)
        let handledAtMs = max(0, payload.handledAtMs ?? detectedAtMs)
        let createdAtMs = max(0, handledAtMs > 0 ? handledAtMs : nowMs)
        let durationMs: Int64? = {
            if let explicit = payload.takeoverLatencyMs, explicit >= 0 {
                return explicit
            }
            if handledAtMs >= detectedAtMs {
                return handledAtMs - detectedAtMs
            }
            return nil
        }()

        let eventIdSeed = auditRef.lowercased()
        let eventId = "supervisor_incident_\(eventIdSeed)"
        let projectId = payload.projectId?.trimmingCharacters(in: .whitespacesAndNewlines)
        let detail = payload.detail?.trimmingCharacters(in: .whitespacesAndNewlines)
        let action = payload.proposedAction.trimmingCharacters(in: .whitespacesAndNewlines)
        let status = payload.status.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = payload.source?.trimmingCharacters(in: .whitespacesAndNewlines)

        let ext: [String: Any] = [
            "incident_id": incidentId,
            "lane_id": laneId,
            "task_id": taskId,
            "project_id": projectId ?? "",
            "incident_code": incidentCode,
            "event_type": eventType,
            "deny_code": denyCode,
            "proposed_action": action,
            "severity": payload.severity.trimmingCharacters(in: .whitespacesAndNewlines),
            "category": payload.category.trimmingCharacters(in: .whitespacesAndNewlines),
            "detected_at_ms": detectedAtMs,
            "handled_at_ms": handledAtMs,
            "takeover_latency_ms": durationMs ?? NSNull(),
            "audit_ref": auditRef,
            "audit_event_type": "supervisor.incident.handled",
            "detail": detail ?? "",
            "status": status,
            "source": source ?? "x_terminal_supervisor",
        ]
        guard JSONSerialization.isValidJSONObject(ext),
              let extData = try? JSONSerialization.data(withJSONObject: ext, options: []),
              let extJSON = String(data: extData, encoding: .utf8) else {
            return false
        }

        func sqlQuoted(_ text: String) -> String {
            "'\(text.replacingOccurrences(of: "'", with: "''"))'"
        }
        func sqlNullable(_ text: String?) -> String {
            guard let text, !text.isEmpty else { return "NULL" }
            return sqlQuoted(text)
        }

        let sql = """
PRAGMA busy_timeout=1500;
INSERT OR IGNORE INTO audit_events(
  event_id, event_type, created_at_ms, severity,
  device_id, user_id, app_id, project_id, session_id,
  request_id, capability, model_id,
  prompt_tokens, completion_tokens, total_tokens, cost_usd_estimate,
  network_allowed, ok, error_code, error_message, duration_ms, ext_json
) VALUES (
  \(sqlQuoted(eventId)), \(sqlQuoted(eventType)), \(createdAtMs), \(sqlQuoted(payload.severity.trimmingCharacters(in: .whitespacesAndNewlines))),
  'x_terminal', 'x_terminal', 'x_terminal', \(sqlNullable(projectId)),
  NULL, \(sqlQuoted(incidentId.isEmpty ? auditRef : incidentId)),
  NULL, NULL,
  NULL, NULL, NULL, NULL,
  NULL, 1, \(sqlQuoted(denyCode)), \(sqlQuoted((detail?.isEmpty == false ? detail! : denyCode))),
  \(durationMs != nil ? String(durationMs!) : "NULL"), \(sqlQuoted(extJSON))
);
"""

        let result = runCapture("/usr/bin/sqlite3", [dbURL.path, sql], timeoutSec: 1.5)
        return result.code == 0
    }

    func appendSupervisorProjectActionAudit(_ payload: IPCSupervisorProjectActionAuditPayload) -> Bool {
        appendSupervisorProjectActionAuditToHubDB(payload)
    }

    func approveNetworkRequest(_ req: HubNetworkRequest, seconds: Int) {
        grantNetwork(seconds: seconds, openBridge: true)
        _ = HubNetworkRequestStorage.remove(id: req.id)
        refreshNetworkRequests()
    }

    func dismissNetworkRequest(_ req: HubNetworkRequest) {
        _ = HubNetworkRequestStorage.remove(id: req.id)
        refreshNetworkRequests()
    }

    func setNetworkPolicy(appId: String, projectId: String, mode: HubNetworkPolicyMode, maxSeconds: Int?) {
        _ = HubNetworkPolicyStorage.upsert(appId: appId, projectId: projectId, mode: mode, maxSeconds: maxSeconds)
    }

    func setNetworkPolicy(for req: HubNetworkRequest, mode: HubNetworkPolicyMode, maxSeconds: Int?) {
        let appId = policyAppId(req)
        let projectId = policyProjectId(req)
        setNetworkPolicy(appId: appId, projectId: projectId, mode: mode, maxSeconds: maxSeconds)
    }

    private func startNetworkRequestsPolling() {
        refreshNetworkRequests()
        networkRequestsTimer?.invalidate()
        networkRequestsTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshNetworkRequests()
            }
        }
    }

    private var pairingPollInFlight: Bool = false

    private func startPairingRequestsPolling() {
        refreshPairingRequests()
        pairingRequestsTimer?.invalidate()
        pairingRequestsTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshPairingRequests()
            }
        }
    }

    func approvePairingRequest(_ req: HubPairingRequest, approval: HubPairingApprovalDraft? = nil) {
        let id = req.pairingRequestId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return }
        let adminToken = grpc.localAdminToken()
        let grpcPort = grpc.port
        let draft = approval ?? HubPairingApprovalDraft.suggested(for: req)
        Task { @MainActor in
            do {
                let requestedScopes = req.requestedScopes
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                let caps = draft.effectiveCapabilities(requestedScopes: requestedScopes)
                try await PairingHTTPClient.approve(
                    pairingRequestId: id,
                    approval: draft,
                    capabilities: caps,
                    allowedCidrs: nil,
                    adminToken: adminToken,
                    grpcPort: grpcPort
                )
                refreshPairingRequests()
                push(.make(source: "Hub", title: "Pairing Approved with Policy", body: "\(draft.normalizedDeviceName) approved.", dedupeKey: nil))
            } catch {
                push(.make(source: "Hub", title: "Pairing Approve Failed", body: (error as NSError).localizedDescription, dedupeKey: nil))
            }
        }
    }

    func denyPairingRequest(_ req: HubPairingRequest, reason: String? = nil) {
        let id = req.pairingRequestId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return }
        let adminToken = grpc.localAdminToken()
        let grpcPort = grpc.port
        Task { @MainActor in
            do {
                try await PairingHTTPClient.deny(pairingRequestId: id, reason: reason, adminToken: adminToken, grpcPort: grpcPort)
                refreshPairingRequests()
                push(.make(source: "Hub", title: "Pairing Denied", body: "\(req.deviceName.isEmpty ? id : req.deviceName) denied.", dedupeKey: nil))
            } catch {
                push(.make(source: "Hub", title: "Pairing Deny Failed", body: (error as NSError).localizedDescription, dedupeKey: nil))
            }
        }
    }

    // Convenience: approve/deny directly from an inbox notification (dedupeKey includes pairing id).
    func approvePairingRequestId(_ pairingRequestId: String) {
        let id = pairingRequestId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return }
        if let req = pendingPairingRequests.first(where: { $0.pairingRequestId == id }) {
            approvePairingRequest(req)
            return
        }
        let adminToken = grpc.localAdminToken()
        let grpcPort = grpc.port
        Task { @MainActor in
            do {
                let fallbackReq = HubPairingRequest(
                    pairingRequestId: id,
                    requestId: id,
                    status: "pending",
                    appId: "paired-terminal",
                    claimedDeviceId: "",
                    userId: "",
                    deviceName: "",
                    peerIp: "",
                    createdAtMs: 0,
                    decidedAtMs: 0,
                    denyReason: "",
                    requestedScopes: []
                )
                try await PairingHTTPClient.approve(
                    pairingRequestId: id,
                    approval: HubPairingApprovalDraft.suggested(for: fallbackReq),
                    capabilities: nil,
                    allowedCidrs: nil,
                    adminToken: adminToken,
                    grpcPort: grpcPort
                )
                refreshPairingRequests()
                push(.make(source: "Hub", title: "Pairing Approved with Policy", body: "\(id) approved.", dedupeKey: nil))
            } catch {
                push(.make(source: "Hub", title: "Pairing Approve Failed", body: (error as NSError).localizedDescription, dedupeKey: nil))
            }
        }
    }

    func denyPairingRequestId(_ pairingRequestId: String, reason: String? = nil) {
        let id = pairingRequestId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return }
        if let req = pendingPairingRequests.first(where: { $0.pairingRequestId == id }) {
            denyPairingRequest(req, reason: reason)
            return
        }
        let adminToken = grpc.localAdminToken()
        let grpcPort = grpc.port
        Task { @MainActor in
            do {
                try await PairingHTTPClient.deny(pairingRequestId: id, reason: reason, adminToken: adminToken, grpcPort: grpcPort)
                refreshPairingRequests()
                push(.make(source: "Hub", title: "Pairing Denied", body: "\(id) denied.", dedupeKey: nil))
            } catch {
                push(.make(source: "Hub", title: "Pairing Deny Failed", body: (error as NSError).localizedDescription, dedupeKey: nil))
            }
        }
    }

    private func startAlwaysOnKeepalive() {
        alwaysOnKeepaliveTimer?.invalidate()
        let t = Timer.scheduledTimer(withTimeInterval: 20.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tickAlwaysOnKeepalive()
            }
        }
        t.tolerance = 4.0
        alwaysOnKeepaliveTimer = t
        tickAlwaysOnKeepalive()
    }

    private func tickAlwaysOnKeepalive() {
        let rules = HubNetworkPolicyStorage.load().policies.filter { $0.mode == .alwaysOn }
        guard !rules.isEmpty else { return }

        // Do not auto-launch the Bridge app. Only keep it enabled if it's already running.
        let st = bridge.statusSnapshot()
        guard st.alive else { return }

        // Since Bridge is global, use the "most permissive" always-on window to minimize renew churn.
        let desired = rules
            .map { r in max(10, r.maxSeconds ?? Self.defaultAlwaysOnSeconds) }
            .max() ?? Self.defaultAlwaysOnSeconds

        let now = Date().timeIntervalSince1970
        let remaining = st.enabledUntil - now

        // Renew early enough so short windows don't accidentally expire under app-nap / timer delays.
        let baseThreshold = Double(max(30, min(15 * 60, desired / 6)))
        let threshold = min(baseThreshold, Double(desired) * 0.5)

        if remaining <= threshold {
            bridge.enable(seconds: desired)
        }
    }

    private func grantNetwork(seconds: Int, openBridge: Bool) {
        bridge.enable(seconds: seconds)
        if openBridge {
            bridge.openBridgeApp()
        }
    }

    private func policyAppId(_ req: HubNetworkRequest) -> String {
        let s = (req.source ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? "unknown" : s
    }

    private func policyProjectId(_ req: HubNetworkRequest) -> String {
        if let pid = req.projectId?.trimmingCharacters(in: .whitespacesAndNewlines), !pid.isEmpty {
            return pid
        }
        if let name = req.displayName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name
        }
        if let p = req.rootPath, !p.isEmpty {
            let name = URL(fileURLWithPath: p).lastPathComponent
            if !name.isEmpty { return name }
        }
        return "unknown"
    }

    private func notificationsPersistURL() -> URL {
        SharedPaths.ensureHubDirectory().appendingPathComponent("notifications.json")
    }

    private func loadNotificationsFromDisk() {
        let url = notificationsPersistURL()
        guard let data = try? Data(contentsOf: url) else { return }
        guard let arr = try? JSONDecoder().decode([HubNotification].self, from: data) else { return }

        // Keep the file bounded: only retain a small, recent window.
        // (Today-new radars remain visible even if read; older items can be dropped.)
        let now = Date().timeIntervalSince1970
        let keepAfter = now - (4 * 24 * 60 * 60) // last 4 days
        let trimmed = arr.filter { $0.createdAt >= keepAfter }.sorted { $0.createdAt > $1.createdAt }
        notifications = Array(trimmed.prefix(200))
    }

    private func schedulePersistNotifications() {
        // Coalesce frequent updates (mark read, snooze, etc) into a single write.
        persistNotificationsTimer?.invalidate()
        persistNotificationsTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.persistNotificationsNow()
            }
        }
    }

    private func persistNotificationsNow() {
        let url = notificationsPersistURL()
        let sorted = notifications.sorted { $0.createdAt > $1.createdAt }
        let capped = Array(sorted.prefix(200))
        if let data = try? JSONEncoder().encode(capped) {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic)
        }
    }

    private func aiRuntimeScriptNamesInPreferenceOrder() -> [String] {
        ["relflowhub_local_runtime.py", "relflowhub_mlx_runtime.py"]
    }

    private func isAIRuntimeCommandLine(_ commandLine: String) -> Bool {
        let normalized = commandLine.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.isEmpty {
            return false
        }
        return aiRuntimeScriptNamesInPreferenceOrder().contains { normalized.contains($0.lowercased()) }
    }

    private func bundledAIRuntimeServiceRootURL() -> URL? {
        guard let resourceURL = Bundle.main.resourceURL else {
            return nil
        }
        let candidate = resourceURL.appendingPathComponent("python_service", isDirectory: true)
        guard FileManager.default.directoryExists(atPath: candidate.path) else {
            return nil
        }
        return candidate
    }

    private func preferredAIRuntimeScriptURL(in directory: URL) -> URL? {
        for scriptName in aiRuntimeScriptNamesInPreferenceOrder() {
            let candidate = directory.appendingPathComponent(scriptName)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    private func runtimeVersionFromScript(at url: URL) -> String? {
        guard let data = try? Data(contentsOf: url),
              let source = String(data: data, encoding: .utf8) else {
            return nil
        }
        let pat = "RUNTIME_VERSION\\s*=\\s*\"([^\"]+)\""
        guard let re = try? NSRegularExpression(pattern: pat, options: []) else { return nil }
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        guard let m = re.firstMatch(in: source, options: [], range: range), m.numberOfRanges >= 2,
              let r = Range(m.range(at: 1), in: source) else { return nil }
        return String(source[r]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func resolveAIRuntimeScriptURL() -> URL? {
        // Prefer the bundled python_service tree for app builds.
        if let root = bundledAIRuntimeServiceRootURL(),
           let bundled = preferredAIRuntimeScriptURL(in: root) {
            return bundled
        }

        // Backward-compatible fallback for older app bundles that shipped a flat script.
        if let bundled = Bundle.main.url(forResource: "relflowhub_local_runtime", withExtension: "py") {
            return bundled
        }
        if let bundled = Bundle.main.url(forResource: "relflowhub_mlx_runtime", withExtension: "py") {
            return bundled
        }

        // Dev build fallback (repo layout; no Resources bundling).
        let p = defaultRuntimeScriptPath()
        if !p.isEmpty, FileManager.default.fileExists(atPath: p) {
            return URL(fileURLWithPath: p)
        }

        return nil
    }

    private func resolveAIRuntimeServiceRootURL() -> URL? {
        if let bundled = bundledAIRuntimeServiceRootURL() {
            return bundled
        }
        let p = defaultRuntimePythonServicePath()
        if !p.isEmpty, FileManager.default.directoryExists(atPath: p) {
            return URL(fileURLWithPath: p, isDirectory: true)
        }
        guard let scriptURL = resolveAIRuntimeScriptURL() else {
            return nil
        }
        let dir = scriptURL.deletingLastPathComponent()
        return dir.lastPathComponent == "python_service" ? dir : nil
    }

    private func installAIRuntimeServiceRoot(from sourceRoot: URL, to destinationRoot: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: destinationRoot.path) {
            try? fm.removeItem(at: destinationRoot)
        }
        try fm.copyItem(at: sourceRoot, to: destinationRoot)
    }



    func connectedAppSources() -> [String] {
        // Prefer client heartbeats; fallback to notification sources.
        let now = Date().timeIntervalSince1970
        let live = clients.liveClients(now: now)
        if !live.isEmpty {
            return live.map { $0.appName }.sorted()
        }
        let srcs = Set(notifications.map { $0.source }.filter { !$0.isEmpty && $0 != "Hub" })
        return srcs.sorted()
    }

    func previewItems() -> [HubNotification] {
        let now = Date().timeIntervalSince1970
        return notifications.filter { $0.unread && ($0.snoozedUntil ?? 0) <= now }.prefix(5).map { $0 }
    }

    func topAlert(now: Date = Date()) -> TopAlert {
        // 1) Meeting urgency: 30m (soon), 10m (hot), 5m (urgent). Urgent is configurable.
        if let m = meetings.first(where: { $0.isMeeting && !$0.id.isEmpty && !isMeetingDismissed($0, now: now.timeIntervalSince1970) }) {
            let nowTs = now.timeIntervalSince1970
            let urgentMin = max(1, meetingUrgentMinutes)
            let outerMin = max(urgentMin, calendarRemindMinutes)
            let hotMin = min(10, outerMin)

            let th = urgentMin * 60
            let hot = hotMin * 60
            let warn = outerMin * 60
            // "Urgent" window begins th seconds before start, and continues until meeting ends
            // (unless the user already opened it).
            if nowTs < m.endAt {
                let dt = Int(m.startDate.timeIntervalSince(now))
                if dt <= th {
                    if m.isMeeting || (m.joinURL ?? "").isEmpty == false {
                        return TopAlert(kind: .meetingUrgent, count: 1, urgentSecondsToMeeting: max(0, dt), urgentWindowSeconds: th)
                    }
                    // Non-meeting calendar event -> treat as a task.
                    return TopAlert(kind: .task, count: 1, urgentSecondsToMeeting: nil, urgentWindowSeconds: nil)
                }

                // "Meeting hot" window: within ~10 minutes (orange), before it becomes urgent.
                if dt > 0, hotMin > urgentMin {
                    let dtSec = Double(dt)
                    let minsCeil = Int(ceil(dtSec / 60.0))
                    if minsCeil <= hotMin {
                        return TopAlert(kind: .meetingHot, count: 1, urgentSecondsToMeeting: dt, urgentWindowSeconds: hot)
                    }
                }

                // "Meeting soon" window: give a noticeable cue (amber) before it becomes urgent.
                if dt > 0 {
                    // Use minute-granularity so events that are "10m 30s" away still count as 10 minutes.
                    let dtSec = Double(dt)
                    let minsCeil = Int(ceil(dtSec / 60.0))
                    if minsCeil <= outerMin {
                        return TopAlert(kind: .meetingSoon, count: 1, urgentSecondsToMeeting: dt, urgentWindowSeconds: warn)
                    }
                }
            }
        }

        let tnow = now.timeIntervalSince1970
        let unread = notifications.filter { $0.unread && ($0.snoozedUntil ?? 0) <= tnow }
        let radar = unread.filter { isFATrackerRadarNotification($0) }
        if !radar.isEmpty {
            return TopAlert(kind: .radar, count: radar.count, urgentSecondsToMeeting: nil, urgentWindowSeconds: nil)
        }
        let msgs = unread.filter { $0.source == "Messages" }
        if !msgs.isEmpty {
            return TopAlert(kind: .message, count: msgs.count, urgentSecondsToMeeting: nil, urgentWindowSeconds: nil)
        }
        let mails = unread.filter { $0.source == "Mail" }
        if !mails.isEmpty {
            return TopAlert(kind: .mail, count: mails.count, urgentSecondsToMeeting: nil, urgentWindowSeconds: nil)
        }
        let slacks = unread.filter { $0.source == "Slack" }
        if !slacks.isEmpty {
            return TopAlert(kind: .slack, count: slacks.count, urgentSecondsToMeeting: nil, urgentWindowSeconds: nil)
        }

        // Today non-meeting events: show as task (blue).
        // (Priority is lower than radar/messages/mail.)
        let cal = Calendar.current
        let today = now
        if meetings.contains(where: { !$0.isMeeting && $0.startDate > now && cal.isDate($0.startDate, inSameDayAs: today) }) {
            let n = meetings.filter { !$0.isMeeting && $0.startDate > now && cal.isDate($0.startDate, inSameDayAs: today) }.count
            return TopAlert(kind: .task, count: n, urgentSecondsToMeeting: nil, urgentWindowSeconds: nil)
        }

        // 5) Today tasks due: treat other unread items as tasks for now.
        let others = unread.filter { !["FAtracker", "Messages", "Mail", "Slack"].contains($0.source) }
        if !others.isEmpty {
            return TopAlert(kind: .task, count: others.count, urgentSecondsToMeeting: nil, urgentWindowSeconds: nil)
        }

        return TopAlert(kind: .idle, count: 0, urgentSecondsToMeeting: nil, urgentWindowSeconds: nil)
    }

    // -------------------- AI runtime (local provider worker) --------------------
    func startAIRuntimeMonitoring() {
        aiRuntimeMonitorTimer?.invalidate()
        aiRuntimeMonitorTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshAIRuntimeStatus()
                self?.autoStartAIRuntimeIfNeeded()
            }
        }
        refreshAIRuntimeStatus()
        autoStartAIRuntimeIfNeeded()
    }

    private func refreshAIRuntimeStatus() {
        let st = AIRuntimeStatusStorage.load()
        if let s = st {
            let alive = s.isAlive(ttl: 3.0) || (findRunningAIRuntimePid(status: st) != nil)
            let heartbeatAlive = s.isAlive(ttl: 3.0)
            let readyProviders = s.readyProviderIDs(ttl: 3.0)
            let mlxReady = s.isProviderReady("mlx", ttl: 3.0)
            aiRuntimeProviderSummaryText = s.providerOperatorSummary(ttl: 3.0)
            aiRuntimeDoctorSummaryText = s.providerDoctorText(ttl: 3.0)
            var v = "stale"
            if alive {
                if readyProviders.isEmpty {
                    v = "running (no providers ready)"
                } else if readyProviders == ["mlx"] {
                    v = "running (mlx ready)"
                } else if mlxReady {
                    v = "running (providers: \(readyProviders.joined(separator: ", ")))"
                } else {
                    v = "running (partial: \(readyProviders.joined(separator: ", ")); mlx unavailable)"
                }
            }
            if heartbeatAlive {
                let expected = bundledRuntimeVersion()
                // Treat missing runtimeVersion as mismatch (older scripts didn't write it).
                if let exp = expected {
                    if (s.runtimeVersion ?? "") != exp {
                        v = "running (needs refresh)"
                    } else {
                        didForceRestartRuntimeForVersionMismatch = false
                    }
                } else {
                    didForceRestartRuntimeForVersionMismatch = false
                }
            } else if alive {
                // Runtime can be alive but the heartbeat stale during long inference; avoid spurious "stale".
                v = "running (heartbeat stale)"
            } else {
                didForceRestartRuntimeForVersionMismatch = false
            }
            aiRuntimeStatusText = "Runtime: \(v) · pid \(s.pid)"

            // Only reset backoff when the runtime is truly alive.
            if heartbeatAlive && !readyProviders.isEmpty {
                aiRuntimeFailCount = 0
                aiRuntimeNextStartAttemptAt = 0
            }

            // Surface actionable guidance when MLX is unavailable.
            if alive && !mlxReady {
                let ie = (s.importError ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let base = mlxUnavailableHelp(importError: ie)
                let doctorLead = s.providerDoctorText(ttl: 3.0).trimmingCharacters(in: .whitespacesAndNewlines)
                let prefix = doctorLead.isEmpty ? "" : doctorLead + "\n\n"
                let msg = prefix + base
                if !msg.isEmpty {
                    // Don't overwrite unrelated errors (e.g. python path selection).
                    if aiRuntimeLastError.isEmpty
                        || aiRuntimeLastError.hasPrefix("MLX is unavailable")
                        || aiRuntimeLastError.hasPrefix("Local runtime is partially ready") {
                        aiRuntimeLastError = msg
                    }
                }
            } else if mlxReady {
                // Clear stale MLX-unavailable hints once we recover.
                if aiRuntimeLastError.hasPrefix("MLX is unavailable")
                    || aiRuntimeLastError.hasPrefix("Local runtime is partially ready") {
                    aiRuntimeLastError = ""
                }
            }
        } else {
            didForceRestartRuntimeForVersionMismatch = false
            aiRuntimeStatusText = "Runtime: not running"
            aiRuntimeProviderSummaryText = "runtime_alive=0\nready_providers=none\nproviders:\ncapabilities:"
            aiRuntimeDoctorSummaryText = "Local runtime is not running."
        }
    }

    private func mlxUnavailableHelp(importError: String) -> String {
        let ie = importError.trimmingCharacters(in: .whitespacesAndNewlines)
        let low = ie.lowercased()

        var hint = ""
        if low.contains("incompatible architecture") || low.contains("wrong architecture") || low.contains("mach-o") {
            hint =
                "This usually means the machine is Intel (x86_64) or the installed MLX binaries don't match the CPU arch.\n\n" +
                "Fix:\n" +
                "1) If this is an Intel Mac: MLX local models are not supported. Use remote/paid models instead.\n" +
                "2) If this is Apple Silicon: reinstall MLX deps for the correct architecture.\n"
        } else if low.contains("no module named") || low.contains("modulenotfounderror") {
            hint =
                "This usually means MLX deps are not installed into the Python that Hub is using.\n\n" +
                "Fix (offline):\n" +
                "1) Run: offline_mlx_deps_py311/install_relflowhub_mlx_deps.command\n" +
                "2) If macOS blocks dlopen/system policy: run install_relflowhub_mlx_deps_system_python311.command instead\n" +
                "3) Hub Settings -> AI Runtime -> Stop, then Start\n\n" +
                "Note: Hub sets PYTHONNOUSERSITE=1, so pip --user (~/Library/Python/...) won't be used.\n"
        } else if low.contains("library load disallowed by system policy") || low.contains("not valid for use in process") {
            hint =
                "macOS blocked loading native extensions from the current install location.\n\n" +
                "Fix:\n" +
                "1) Run: offline_mlx_deps_py311/install_relflowhub_mlx_deps_system_python311.command\n" +
                "2) Hub Settings -> AI Runtime -> Stop, then Start\n"
        } else {
            hint =
                "Fix:\n" +
                "1) Ensure you're on Apple Silicon (MLX requires it)\n" +
                "2) Install MLX deps for Python 3.11 (offline installers in offline_mlx_deps_py311/)\n" +
                "3) Hub Settings -> AI Runtime -> Stop, then Start\n"
        }

        if ie.isEmpty {
            return "MLX is unavailable.\n\n" + hint
        }
        return "MLX is unavailable.\n\nImport error:\n\(ie)\n\n" + hint
    }

    private func findRunningAIRuntimePid(status: AIRuntimeStatus?) -> Int32? {
        // Fast-path: runtime we launched in this process.
        if let p = aiRuntimeProcess, p.isRunning {
            return p.processIdentifier
        }

        // Next: verify the pid from the last heartbeat (even if stale).
        if let st = status, st.pid > 1 {
            let ps = runCapture("/bin/ps", ["-p", String(st.pid), "-o", "command="], timeoutSec: 0.6)
            let txt = (ps.out.isEmpty ? ps.err : ps.out).lowercased()
            if ps.code == 0, isAIRuntimeCommandLine(txt) {
                return Int32(st.pid)
            }
        }

        // Fallback: scan all processes (rare path; used when heartbeat is missing).
        let ps = runCapture("/bin/ps", ["-ax", "-o", "pid=,command="], timeoutSec: 1.0)
        let raw = (ps.out.isEmpty ? ps.err : ps.out)
        if raw.isEmpty { return nil }
        for row in raw.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = row.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }
            let parts = line.split(maxSplits: 1, omittingEmptySubsequences: true, whereSeparator: { $0 == " " || $0 == "\t" })
            if parts.count < 2 { continue }
            guard let pidNum = Int32(parts[0]), pidNum > 1 else { continue }
            let cmd = String(parts[1]).lowercased()
            if !isAIRuntimeCommandLine(cmd) { continue }
            return pidNum
        }
        return nil
    }

    private func bundledRuntimeVersion() -> String? {
        // Keep version checks aligned with the legacy runtime loop that currently writes
        // ai_runtime_status.json, even when the launch entrypoint is relflowhub_local_runtime.py.
        if let root = bundledAIRuntimeServiceRootURL() {
            let legacy = root.appendingPathComponent("relflowhub_mlx_runtime.py")
            if FileManager.default.fileExists(atPath: legacy.path),
               let version = runtimeVersionFromScript(at: legacy) {
                return version
            }
            if let entry = preferredAIRuntimeScriptURL(in: root),
               let version = runtimeVersionFromScript(at: entry) {
                return version
            }
        }
        if let flatLegacy = Bundle.main.url(forResource: "relflowhub_mlx_runtime", withExtension: "py"),
           let version = runtimeVersionFromScript(at: flatLegacy) {
            return version
        }
        if let resolved = resolveAIRuntimeScriptURL() {
            return runtimeVersionFromScript(at: resolved)
        }
        return nil
    }

    private func autoStartAIRuntimeIfNeeded() {
        if !aiRuntimeAutoStart {
            return
        }
        // If already alive, do nothing *unless* the running runtime is an older version.
        let st = AIRuntimeStatusStorage.load()
        if let st, st.isAlive(ttl: 3.0) {
            let expected = bundledRuntimeVersion()
            if let exp = expected, (st.runtimeVersion ?? "") != exp {
                if !didForceRestartRuntimeForVersionMismatch {
                    didForceRestartRuntimeForVersionMismatch = true
                    appendAIRuntimeLogLine("Detected runtime version mismatch (running=\(st.runtimeVersion ?? "") expected=\(exp)); restarting")
                    stopAIRuntime()
                    // Start immediately (ignore backoff) because the runtime was already healthy.
                    startAIRuntime()
                }
            }
            return
        }
        let now = Date().timeIntervalSince1970
        if now < aiRuntimeNextStartAttemptAt {
            return
        }
        // If a runtime process is already running (even with a stale heartbeat), do not auto-start another.
        // This prevents spurious "lock busy" errors during long inference.
        if findRunningAIRuntimePid(status: st) != nil {
            return
        }
        // Backoff on repeated failures. Minimum delay avoids spamming TCC prompts.
        let exp = Double(min(6, max(0, aiRuntimeFailCount)))
        let delay = min(300.0, 15.0 * pow(2.0, exp))
        aiRuntimeNextStartAttemptAt = now + delay
        startAIRuntime()
    }

    func startAIRuntime() {
        aiRuntimeLastError = ""
        aiRuntimeStopRequestedAt = 0

        // If a previous Hub instance left the runtime running, stop it first so we don't
        // end up with multiple runtimes racing on the same file IPC directories.
        if let st = AIRuntimeStatusStorage.load(), st.isAlive(ttl: 3.0) {
            stopAIRuntime()
        }

        // Keep logging useful even when we fail early (e.g. lock busy).
        let base = SharedPaths.appGroupDirectory() ?? SharedPaths.ensureHubDirectory()
        let logURL = base.appendingPathComponent("ai_runtime.log")
        if !FileManager.default.fileExists(atPath: logURL.path) {
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
        }
        do {
            if aiRuntimeLogHandle == nil {
                let handle = try FileHandle(forWritingTo: logURL)
                try handle.seekToEnd()
                aiRuntimeLogHandle = handle
            } else {
                try aiRuntimeLogHandle?.seekToEnd()
            }
        } catch {
            // Non-fatal; continue without log.
            aiRuntimeLogHandle = nil
        }

        appendAIRuntimeLogLine("==== start attempt ==== (autoStart=\(aiRuntimeAutoStart)) (base=\(base.path))")

        // Do not start a second copy if we already launched one.
        if let p = aiRuntimeProcess, p.isRunning {
            return
        }

        // Preflight: if the runtime lock is held, avoid starting a process that will
        // immediately exit with code 0 (and cause an auto-start loop).
        if isAIRuntimeLockBusy(baseDir: base) {
            let lockURL = base.appendingPathComponent("ai_runtime.lock")
            // Treat as "already running". Users can click Stop to force a restart.
            appendAIRuntimeLogLine("Preflight: lock busy (runtime already running) (\(lockURL.path))")
            refreshAIRuntimeStatus()
            return
        }

        let resolved = resolveAIRuntimeScriptURL()
        let serviceRoot = resolveAIRuntimeServiceRootURL()
        let scriptURL: URL? = resolved.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
        guard let scriptURL else {
            aiRuntimeLastError = "AI runtime script is missing from this build. Please rebuild/reinstall Hub (it should bundle python_service/relflowhub_local_runtime.py, with relflowhub_mlx_runtime.py kept as fallback)."
            aiRuntimeFailCount += 1
            return
        }

        // Copy the runtime into App Group so the sandboxed child process can read the full
        // python_service tree (provider registry, legacy runtime fallback, etc).
        let rtDir = base.appendingPathComponent("ai_runtime", isDirectory: true)
        try? FileManager.default.createDirectory(at: rtDir, withIntermediateDirectories: true)
        let rtScript: URL
        do {
            if let serviceRoot, FileManager.default.directoryExists(atPath: serviceRoot.path) {
                let destinationRoot = rtDir.appendingPathComponent("python_service", isDirectory: true)
                if serviceRoot.path != destinationRoot.path {
                    try installAIRuntimeServiceRoot(from: serviceRoot, to: destinationRoot)
                    appendAIRuntimeLogLine("Copied runtime service root to base: \(destinationRoot.path)")
                }
                guard let installed = preferredAIRuntimeScriptURL(in: destinationRoot) else {
                    throw NSError(
                        domain: "relflowhub",
                        code: 1,
                        userInfo: [
                            NSLocalizedDescriptionKey: "Installed python_service is missing relflowhub_local_runtime.py and relflowhub_mlx_runtime.py."
                        ]
                    )
                }
                rtScript = installed
            } else {
                rtScript = rtDir.appendingPathComponent(scriptURL.lastPathComponent)
                if scriptURL.path != rtScript.path {
                    if FileManager.default.fileExists(atPath: rtScript.path) {
                        try? FileManager.default.removeItem(at: rtScript)
                    }
                    try FileManager.default.copyItem(at: scriptURL, to: rtScript)
                    appendAIRuntimeLogLine("Copied runtime script to base: \(rtScript.path)")
                }
            }
        } catch {
            aiRuntimeLastError = "Failed to install runtime into base dir.\n\n\(error.localizedDescription)"
            aiRuntimeFailCount += 1
            return
        }

        let p = Process()
        var py = aiRuntimePython.trimmingCharacters(in: .whitespacesAndNewlines)
        let exe: String
        var args: [String] = []

        // Auto-detect a usable python if missing.
        // Do not override a user-provided path (even if wrong); we'll surface a clear error below.
        if py.isEmpty {
            if let best = autoDetectPython() {
                py = best
                aiRuntimePython = best
            }
        }
        if py.isEmpty {
            // Fall back to a reasonable python. If the fallback is /usr/bin/env, we must
            // pass "python3" explicitly; otherwise env will try to execute the script.
            exe = defaultPythonPath()
            if (exe as NSString).lastPathComponent == "env" {
                args = ["python3", rtScript.path]
            } else {
                args = [rtScript.path]
            }
        } else if py.contains("/") {
            // Absolute path: must be an executable file, not a directory like site-packages.
            let norm = (py as NSString).expandingTildeInPath
            if FileManager.default.directoryExists(atPath: norm) {
                aiRuntimeLastError = "Python path points to a directory (site-packages). Please set it to a python3 executable, e.g. /Library/Frameworks/Python.framework/Versions/3.11/bin/python3."
                aiRuntimeFailCount += 1
                return
            }
            if !FileManager.default.isExecutableFile(atPath: norm) {
                aiRuntimeLastError = "Python path is not executable. Please set it to a python3 executable, e.g. /Library/Frameworks/Python.framework/Versions/3.11/bin/python3."
                aiRuntimeFailCount += 1
                return
            }
            exe = norm
            if (norm as NSString).lastPathComponent == "env" {
                args = ["python3", rtScript.path]
            } else {
                args = [rtScript.path]
            }
        } else {
            // Treat as "python3" style: run through env.
            exe = "/usr/bin/env"
            args = [py, rtScript.path]
        }

        // Preflight: reject xcrun stub python which cannot run inside App Sandbox.
        do {
            let test = runCapture(exe, (args.first == "python3" ? ["python3", "-c", "import sys; print(sys.version)"] : ["-c", "import sys; print(sys.version)"]), timeoutSec: 1.2)
            if test.out.contains("xcrun") || test.err.contains("xcrun") {
                aiRuntimeLastError = "The selected python appears to be an xcrun stub (cannot run in App Sandbox). Please install a real Python 3.11 (python.org installer recommended) and set Python to /Library/Frameworks/Python.framework/Versions/3.11/bin/python3."
                aiRuntimeFailCount += 1
                return
            }
        }

        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        var env = ProcessInfo.processInfo.environment
        env["REL_FLOW_HUB_BASE_DIR"] = base.path
        env["PYTHONUNBUFFERED"] = "1"
        // Avoid importing from ~/Library/Python/... which can be quarantined or policy-blocked on some machines.
        env["PYTHONNOUSERSITE"] = "1"
        env["HF_HUB_OFFLINE"] = "1"
        env["TRANSFORMERS_OFFLINE"] = "1"
        env["HF_DATASETS_OFFLINE"] = "1"
        env["TOKENIZERS_PARALLELISM"] = "false"

        // Offline deps: optionally add Hub-local site-packages to PYTHONPATH.
        //
        // Problem (macOS 26): some machines block dlopen() of native extensions from the app container
        // ("library load disallowed by system policy"). If the user already installed deps into a
        // real python site-packages, we should NOT force PYTHONPATH to the container.
        //
        // Rule:
        // - Prefer system/user site-packages (no PYTHONPATH)
        // - Only use offline PYTHONPATH if explicitly opted-in AND required

        // 1) Preflight import WITHOUT offline PYTHONPATH.
        // If that works, ignore any offline marker (it would just make things worse).
        let basicImportTest = "import mlx_lm; import mlx; import numpy; print('OK')"
        do {
            let t = runCapture(exe, (args.first == "python3" ? ["python3", "-c", basicImportTest] : ["-c", basicImportTest]), env: env, timeoutSec: 6.0)
            if t.code == 0 {
                // No-op: system/user deps already work.
            } else {
                // 2) Try offline deps (PYTHONPATH) only if explicitly enabled via marker.
                let offlineRoots: [URL] = [
                    // Prefer real home dir because Hub has an entitlement exception for ~/RELFlowHub.
                    SharedPaths.realHomeDirectory().appendingPathComponent("RELFlowHub", isDirectory: true).appendingPathComponent("py_deps", isDirectory: true),
                    // Legacy location: under the Hub base dir (often the container for sandbox builds).
                    base.appendingPathComponent("py_deps", isDirectory: true),
                ]

                for root in offlineRoots {
                    let marker = root.appendingPathComponent("USE_PYTHONPATH")
                    let site = root.appendingPathComponent("site-packages", isDirectory: true)
                    if !FileManager.default.fileExists(atPath: marker.path) { continue }
                    if !FileManager.default.directoryExists(atPath: site.path) { continue }

                    var env2 = env
                    let prev = env2["PYTHONPATH"] ?? ""
                    env2["PYTHONPATH"] = site.path + (prev.isEmpty ? "" : ":" + prev)

                    let t2 = runCapture(exe, (args.first == "python3" ? ["python3", "-c", basicImportTest] : ["-c", basicImportTest]), env: env2, timeoutSec: 6.0)
                    if t2.code == 0 {
                        env = env2
                        break
                    }
                    let err = (t2.err + "\n" + t2.out)
                    if err.contains("library load disallowed by system policy") || err.contains("not valid for use in process") {
                        aiRuntimeLastError = "Offline deps were detected but macOS blocked loading native extensions from this location (system policy).\n\nFix:\n1) Run the *system* installer: install_relflowhub_mlx_deps_system_python311.command\n2) Restart Hub -> Models -> Stop/Start\n\nIf the error persists, delete the marker file USE_PYTHONPATH under the py_deps folder."
                        aiRuntimeFailCount += 1
                        return
                    }
                }
            }
        }
        p.environment = env

        appendAIRuntimeLogLine(
            "Starting runtime: \(exe) \(args.joined(separator: " ")) (script=\(scriptURL.path) -> \(rtScript.path)) (REL_FLOW_HUB_BASE_DIR=\(base.path))"
        )
        if let h = aiRuntimeLogHandle {
            p.standardOutput = h
            p.standardError = h
        }

        p.terminationHandler = { [weak self] proc in
            Task { @MainActor in
                guard let self else { return }

                // Avoid clobbering a newer runtime if we restarted quickly.
                if let cur = self.aiRuntimeProcess, cur !== proc {
                    self.appendAIRuntimeLogLine("Runtime exited (stale proc ignored): pid=\(proc.processIdentifier) code=\(proc.terminationStatus)")
                    return
                }

                let now = Date().timeIntervalSince1970
                self.aiRuntimeProcess = nil
                let stopRequestedAt = self.aiRuntimeStopRequestedAt
                let stopRequestedRecently = stopRequestedAt > 0 && (now - stopRequestedAt) < 5.0

                // Surface quick failures (including lock-busy exit=0).
                if !stopRequestedRecently {
                    let launchedAt = self.aiRuntimeLastLaunchAt
                    let elapsed = launchedAt > 0 ? max(0, now - launchedAt) : 0
                    if proc.terminationStatus != 0 {
                        if self.aiRuntimeLastError.isEmpty {
                            self.aiRuntimeLastError = "Runtime exited (code \(proc.terminationStatus)). If you see 'xcrun: error: cannot be used within an App Sandbox', set Python to a real interpreter (e.g. /opt/homebrew/bin/python3)."
                        }
                        self.aiRuntimeFailCount += 1
                    } else if elapsed > 0 && elapsed < 2.0 {
                        if self.aiRuntimeLastError.isEmpty {
                            self.aiRuntimeLastError = "Runtime exited immediately (code 0). This usually means another runtime already holds the lock (ai_runtime.lock). Try: Settings → AI Runtime → Stop, then Start."
                        }
                        self.aiRuntimeFailCount += 1
                    }
                }
                self.appendAIRuntimeLogLine("Runtime exited: code=\(proc.terminationStatus)")
            }
        }

        do {
            aiRuntimeLastLaunchAt = Date().timeIntervalSince1970
            try p.run()
            aiRuntimeProcess = p
            refreshAIRuntimeStatus()
        } catch {
            aiRuntimeLastError = "Failed to start runtime: \(error.localizedDescription)"
            aiRuntimeFailCount += 1
        }
    }

    private func autoDetectPython() -> String? {
        // Prefer real python binaries. /usr/bin/python3 may be a stub on some macOS setups.
        let candidates = [
            "/Library/Frameworks/Python.framework/Versions/3.11/bin/python3",
            "/Library/Frameworks/Python.framework/Versions/Current/bin/python3",
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3",
            "/usr/bin/python3",
        ]
        let fm = FileManager.default
        var bestAny: String? = nil
        for c in candidates {
            if !fm.isExecutableFile(atPath: c) { continue }
            let r = runCapture(c, ["-c", "import sys; print(f'{sys.version_info[0]}.{sys.version_info[1]}')"], timeoutSec: 1.2)
            let s = (r.out.isEmpty ? r.err : r.out)
            if r.code != 0 { continue }
            if s.contains("xcrun") { continue }
            if bestAny == nil { bestAny = c }
            if s.hasPrefix("3.11") {
                return c
            }
        }
        return bestAny
    }

    struct AIRuntimeUnlockResult {
        var lockPath: String
        var command: String
        var holderPids: [Int32]
        var killedPids: [Int32]
        var skippedPids: [Int32]
        var lockReleased: Bool
        var detail: String
    }

    private func runtimeBaseDirForAIRuntime() -> URL {
        SharedPaths.appGroupDirectory() ?? SharedPaths.ensureHubDirectory()
    }

    private func resolvedLsofPath() -> String? {
        let fm = FileManager.default
        let candidates = ["/usr/sbin/lsof", "/usr/bin/lsof"]
        for p in candidates where fm.isExecutableFile(atPath: p) {
            return p
        }
        return nil
    }

    func aiRuntimeLockBusyNow() -> Bool {
        isAIRuntimeLockBusy(baseDir: runtimeBaseDirForAIRuntime())
    }

    func aiRuntimeLockKillCommandHint(pids: [Int32] = []) -> String {
        let base = runtimeBaseDirForAIRuntime()
        let lockPath = base.appendingPathComponent("ai_runtime.lock").path
        let lsofCmd = resolvedLsofPath() ?? "lsof"
        let uniq = Array(Set(pids.filter { $0 > 1 })).sorted()
        if !uniq.isEmpty {
            let pidList = uniq.map(String.init).joined(separator: " ")
            return "kill -9 \(pidList)"
        }
        // Runnable snippet for Terminal copy/paste that resolves holders at execution time.
        return "pids=$(\(lsofCmd) -t \"\(lockPath)\" 2>/dev/null); [ -n \"$pids\" ] && kill -9 $pids"
    }

    private func aiRuntimePsKillCommandHint(pids: [Int32] = []) -> String {
        let uniq = Array(Set(pids.filter { $0 > 1 })).sorted()
        if !uniq.isEmpty {
            let pidList = uniq.map(String.init).joined(separator: " ")
            return "kill -9 \(pidList)"
        }
        return "pids=$(ps ax -o pid=,command= | awk '/relflowhub_(local|mlx)_runtime.py/ && $0 !~ /awk/ {print $1}'); [ -n \"$pids\" ] && kill -9 $pids"
    }

    private func parsePidList(_ text: String) -> [Int32] {
        let raw = text
            .split(whereSeparator: { $0 == "\n" || $0 == "\r" || $0 == "\t" || $0 == " " || $0 == "," })
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        var seen = Set<Int32>()
        var out: [Int32] = []
        for s in raw {
            guard let pid = Int32(s), pid > 1 else { continue }
            if seen.contains(pid) { continue }
            seen.insert(pid)
            out.append(pid)
        }
        return out
    }

    private func collectRuntimePidsFromStatusAndPS() -> [Int32] {
        var out: [Int32] = []
        var seen = Set<Int32>()

        if let st = AIRuntimeStatusStorage.load() {
            let pid = Int32(st.pid)
            if pid > 1 {
                // Guard against stale/reused pids from old heartbeat files.
                let cmd = runtimeCommandLineForPid(pid).lowercased()
                let ageSec = max(0.0, Date().timeIntervalSince1970 - st.updatedAt)
                let heartbeatRecent = ageSec < 90.0
                let psBlocked =
                    cmd.isEmpty ||
                    cmd.contains("operation not permitted") ||
                    cmd.contains("permission denied")
                if isAIRuntimeCommandLine(cmd) ||
                    (heartbeatRecent && psBlocked && alivePid(pid_t(pid))) {
                    seen.insert(pid)
                    out.append(pid)
                }
            }
        }

        let ps = runCapture("/bin/ps", ["-ax", "-o", "pid=,command="], timeoutSec: 1.0)
        let raw = (ps.out.isEmpty ? ps.err : ps.out)
        if raw.isEmpty {
            return out
        }
        for row in raw.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = row.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }
            let parts = line.split(maxSplits: 1, omittingEmptySubsequences: true, whereSeparator: { $0 == " " || $0 == "\t" })
            if parts.count < 2 { continue }
            guard let pid = Int32(parts[0]), pid > 1 else { continue }
            let cmd = String(parts[1]).lowercased()
            if !isAIRuntimeCommandLine(cmd) { continue }
            if seen.contains(pid) { continue }
            seen.insert(pid)
            out.append(pid)
        }

        return out
    }

    private func runtimeCommandLineForPid(_ pid: Int32) -> String {
        let ps = runCapture("/bin/ps", ["-p", String(pid), "-o", "command="], timeoutSec: 0.8)
        let txt = (ps.out.isEmpty ? ps.err : ps.out).trimmingCharacters(in: .whitespacesAndNewlines)
        return txt
    }

    private func alivePid(_ pid: pid_t) -> Bool {
        if pid <= 1 { return false }
        if kill(pid, 0) == 0 { return true }
        return errno == EPERM
    }

    func forceUnlockAIRuntimeLockByLsof(allowNonRuntimeHolders: Bool = false) -> AIRuntimeUnlockResult {
        let base = runtimeBaseDirForAIRuntime()
        let lockPath = base.appendingPathComponent("ai_runtime.lock").path
        var result = AIRuntimeUnlockResult(
            lockPath: lockPath,
            command: aiRuntimeLockKillCommandHint(),
            holderPids: [],
            killedPids: [],
            skippedPids: [],
            lockReleased: false,
            detail: ""
        )

        if !isAIRuntimeLockBusy(baseDir: base) {
            result.lockReleased = true
            result.detail = "Runtime lock is already free."
            return result
        }

        guard let lsofExe = resolvedLsofPath() else {
            result.detail = "lsof is not available at /usr/sbin/lsof or /usr/bin/lsof."
            return result
        }
        let lsofCandidates = [lsofExe]
        var lsofOut = ""
        var lsofErr = ""
        var lsofCode: Int32 = 127
        for exe in lsofCandidates {
            let r = runCapture(exe, ["-t", lockPath], timeoutSec: 1.4)
            lsofOut = r.out
            lsofErr = r.err
            lsofCode = r.code
            let pids = parsePidList(r.out)
            if !pids.isEmpty || r.code == 0 {
                result.holderPids = pids
                break
            }
        }

        let lsofTail = [lsofOut, lsofErr].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        let lsofTailLower = lsofTail.lowercased()
        let lsofBlocked =
            lsofTailLower.contains("operation not permitted") ||
            lsofTailLower.contains("can't get pid byte count")

        if result.holderPids.isEmpty {
            let fallbackPids = collectRuntimePidsFromStatusAndPS()
            if !fallbackPids.isEmpty {
                result.holderPids = fallbackPids
                result.command = aiRuntimePsKillCommandHint(pids: fallbackPids)
                if lsofBlocked {
                    result.detail = "lsof is blocked by sandbox; used ps fallback."
                }
            } else if lsofCode != 0 {
                if lsofBlocked {
                    result.command = aiRuntimePsKillCommandHint()
                    result.detail = "lsof is blocked by sandbox (Operation not permitted), and no runtime pid was found via ps."
                } else {
                    result.detail = lsofTail.isEmpty ? "lsof failed with code \(lsofCode)." : "lsof failed: \(lsofTail)"
                }
                return result
            }
        }

        if result.command.isEmpty || (result.command.contains("lsof") && !result.holderPids.isEmpty) {
            result.command = aiRuntimeLockKillCommandHint(pids: result.holderPids)
        }
        if result.holderPids.isEmpty {
            result.lockReleased = !isAIRuntimeLockBusy(baseDir: base)
            if result.lockReleased {
                result.detail = "Runtime lock released."
            } else {
                if result.detail.isEmpty {
                    result.detail = "Runtime lock is busy but no holder pid was found."
                }
            }
            return result
        }

        for pidNum in result.holderPids {
            let pid = pid_t(pidNum)
            if pid <= 1 || pid == getpid() {
                result.skippedPids.append(pidNum)
                continue
            }

            let cmd = runtimeCommandLineForPid(pidNum).lowercased()
            // Safety by default: only auto-kill known Hub runtime holders.
            if !allowNonRuntimeHolders && !isAIRuntimeCommandLine(cmd) {
                result.skippedPids.append(pidNum)
                continue
            }

            kill(pid, SIGTERM)
            for _ in 0..<12 {
                if !alivePid(pid) { break }
                usleep(50_000)
            }
            if alivePid(pid) {
                kill(pid, SIGKILL)
                for _ in 0..<10 {
                    if !alivePid(pid) { break }
                    usleep(50_000)
                }
            }
            if alivePid(pid) {
                result.detail = "Failed to kill lock holder pid \(pidNum)."
            } else {
                result.killedPids.append(pidNum)
            }
        }

        for _ in 0..<18 {
            if !isAIRuntimeLockBusy(baseDir: base) { break }
            usleep(50_000)
        }
        result.lockReleased = !isAIRuntimeLockBusy(baseDir: base)

        if result.lockReleased {
            if result.killedPids.isEmpty {
                result.detail = "Runtime lock released."
            } else {
                let pids = result.killedPids.map(String.init).joined(separator: ",")
                result.detail = "Runtime lock released. killed=\(pids)"
            }
            return result
        }

        var parts: [String] = []
        if !result.killedPids.isEmpty {
            parts.append("killed=\(result.killedPids.map(String.init).joined(separator: ","))")
        }
        if !result.skippedPids.isEmpty {
            parts.append("skipped=\(result.skippedPids.map(String.init).joined(separator: ","))")
        }
        parts.append("lock_still_busy=1")
        if !result.detail.isEmpty {
            parts.append(result.detail)
        }
        result.detail = parts.joined(separator: " · ")
        return result
    }

    private func isAIRuntimeLockBusy(baseDir: URL) -> Bool {
        // The python runtime uses a flock() lock at: <base>/ai_runtime.lock.
        // If that lock is held, starting a new runtime will immediately exit (code 0),
        // which is confusing for users. Preflight here and surface a human error.
        let lockURL = baseDir.appendingPathComponent("ai_runtime.lock")
        let fd = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR | S_IRGRP | S_IROTH)
        if fd < 0 {
            return false
        }
        defer { close(fd) }
        if flock(fd, LOCK_EX | LOCK_NB) == 0 {
            _ = flock(fd, LOCK_UN)
            return false
        }
        if errno == EWOULDBLOCK || errno == EAGAIN {
            return true
        }
        return false
    }

    func stopAIRuntime() {
        aiRuntimeLastError = ""
        aiRuntimeStopRequestedAt = Date().timeIntervalSince1970

        // Ask the runtime to stop via a file marker first. This works even when OS signals
        // are restricted (App Sandbox), and also handles runtimes that survived an app relaunch.
        let base = runtimeBaseDirForAIRuntime()
        do {
            let stopURL = base.appendingPathComponent("ai_runtime_stop.json")
            let obj: [String: Any] = [
                "req_id": UUID().uuidString,
                "requested_at": Date().timeIntervalSince1970,
                "hub_pid": Int(getpid()),
            ]
            let data = try JSONSerialization.data(withJSONObject: obj, options: [])
            try data.write(to: stopURL, options: .atomic)
        } catch {
            // Best-effort.
        }

        // Give the runtime a brief moment to observe the marker and release the lock.
        for _ in 0..<12 {
            if !isAIRuntimeLockBusy(baseDir: base) {
                break
            }
            usleep(50_000)
        }

        // Best-effort: terminate by pid from the runtime heartbeat as well.
        // This cleans up runtimes started by older Hub instances.
        if let st = AIRuntimeStatusStorage.load() {
            let pid = pid_t(st.pid)
            if pid > 1 {
                // Avoid killing an unrelated process if the pid was reused.
                // Prefer verifying the command line contains our script name.
                let ps = runCapture("/bin/ps", ["-p", String(pid), "-o", "command="], timeoutSec: 0.8)
                let psText = (ps.out.isEmpty ? ps.err : ps.out).lowercased()
                let looksLikeRuntime = ps.code == 0 && isAIRuntimeCommandLine(psText)
                let statusAgeSec = max(0.0, Date().timeIntervalSince1970 - st.updatedAt)
                let statusRecent = statusAgeSec < 10 * 60 // 10 minutes

                if looksLikeRuntime || (ps.code != 0 && statusRecent) {
                    kill(pid, SIGTERM)
                    // If it doesn't exit quickly, force-kill to avoid lock-busy loops.
                    var stillAlive = false
                    for _ in 0..<8 {
                        usleep(50_000)
                        if kill(pid, 0) == 0 {
                            stillAlive = true
                            continue
                        }
                        stillAlive = false
                        break
                    }
                    if stillAlive {
                        kill(pid, SIGKILL)
                    }
                }
            }
        }

        // If the heartbeat is stale (or missing), the lock can still be held by a lingering
        // runtime process. As a safety net, kill any known relflowhub runtime processes we can find.
        do {
            let ps = runCapture("/bin/ps", ["-ax", "-o", "pid=,command="], timeoutSec: 1.0)
            let raw = (ps.out.isEmpty ? ps.err : ps.out)
            if !raw.isEmpty {
                for row in raw.split(separator: "\n", omittingEmptySubsequences: true) {
                    let line = row.trimmingCharacters(in: .whitespacesAndNewlines)
                    if line.isEmpty { continue }
                    let parts = line.split(maxSplits: 1, omittingEmptySubsequences: true, whereSeparator: { $0 == " " || $0 == "\t" })
                    if parts.count < 2 { continue }
                    guard let pidNum = Int32(parts[0]), pidNum > 1 else { continue }
                    let cmd = String(parts[1]).lowercased()
                    if !isAIRuntimeCommandLine(cmd) { continue }
                    let pid = pid_t(pidNum)
                    kill(pid, SIGTERM)
                    var stillAlive = false
                    for _ in 0..<8 {
                        usleep(50_000)
                        if kill(pid, 0) == 0 {
                            stillAlive = true
                            continue
                        }
                        stillAlive = false
                        break
                    }
                    if stillAlive {
                        kill(pid, SIGKILL)
                    }
                }
            }
        }

        if let p = aiRuntimeProcess {
            if p.isRunning {
                let pid = pid_t(p.processIdentifier)
                p.terminate()
                _ = waitForProcessExit(p, timeoutSec: 0.9)
                if p.isRunning, pid > 1 {
                    kill(pid, SIGKILL)
                    _ = waitForProcessExit(p, timeoutSec: 0.9)
                }
            }
            if p.isRunning {
                // Keep it alive so we don't crash on Process deinit; surface an error below.
                leakRunningCaptureProcess(p)
                aiRuntimeProcess = p
            } else {
                aiRuntimeProcess = nil
            }
        }
        try? aiRuntimeLogHandle?.close()
        aiRuntimeLogHandle = nil

        // If we're still locked after all stop attempts, surface actionable guidance.
        if isAIRuntimeLockBusy(baseDir: base) {
            let lockURL = base.appendingPathComponent("ai_runtime.lock")
            let pidHint = (AIRuntimeStatusStorage.load()?.pid ?? 0)
            aiRuntimeLastError =
                "Stop requested, but the runtime lock is still busy.\n\n" +
                "Lock: \(lockURL.path)\n\n" +
                "Try Diagnostics → Fix Now (Kill runtime lock holder).\n\n" +
                "If no other Hub instance is running, kill the lock holder from Terminal:\n" +
                "  \(aiRuntimeLockKillCommandHint())\n" +
                (pidHint > 1 ? "\nPID hint (from ai_runtime_status.json): \(pidHint)\n  kill -9 \(pidHint)\n" : "")
        }

        refreshAIRuntimeStatus()
    }

    func openAIRuntimeLog() {
        let base = SharedPaths.ensureHubDirectory()
        let logURL = base.appendingPathComponent("ai_runtime.log")
        NSWorkspace.shared.open(logURL)
    }

    func axConstitutionURL() -> URL {
        SharedPaths.ensureHubDirectory()
            .appendingPathComponent("memory", isDirectory: true)
            .appendingPathComponent("ax_constitution.json")
    }

    func openAXConstitutionFile() {
        let url = axConstitutionURL()
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.open(url)
        } else {
            // The runtime creates the default file on first start; open the folder so users can inspect/edit.
            NSWorkspace.shared.open(url.deletingLastPathComponent())
        }
    }

    func recentAIRuntimeAuditLines(limit: Int = 16) -> [String] {
        let n = max(1, min(80, limit))
        let base = SharedPaths.ensureHubDirectory()
        let p = base.appendingPathComponent("mlx_runtime_audit.log")
        guard let data = try? Data(contentsOf: p), let s = String(data: data, encoding: .utf8) else {
            return []
        }
        let lines = s.split(separator: "\n", omittingEmptySubsequences: true).map { String($0) }
        let ai = lines.filter { $0.contains("\tai_request\t") }
        return Array(ai.suffix(n))
    }

    func testAIRuntimeGenerate() {
        aiRuntimeLastTestText = ""

        // Fast preflight checks.
        if !(AIRuntimeStatusStorage.load()?.isAlive(ttl: 3.0) ?? false) {
            aiRuntimeLastTestText = "AI test: runtime is not running"
            return
        }
        let loaded = ModelStore.shared.snapshot.models.filter { $0.state == .loaded }
        if loaded.isEmpty {
            aiRuntimeLastTestText = "AI test: no loaded model (load one in Models)"
            return
        }

        let base = SharedPaths.ensureHubDirectory()
        let reqDir = base.appendingPathComponent("ai_requests", isDirectory: true)
        let respDir = base.appendingPathComponent("ai_responses", isDirectory: true)
        try? FileManager.default.createDirectory(at: reqDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: respDir, withIntermediateDirectories: true)

        let reqId = UUID().uuidString
        let reqURL = reqDir.appendingPathComponent("req_\(reqId).json")
        let respURL = respDir.appendingPathComponent("resp_\(reqId).jsonl")

        let obj: [String: Any] = [
            "type": "generate",
            "req_id": reqId,
            "app_id": "hub_ui",
            "task_type": "assist",
            "prompt": "Say hello in one short sentence. Output ONLY the sentence.",
            "max_tokens": 64,
            "temperature": 0.2,
            "top_p": 0.95,
            "created_at": Date().timeIntervalSince1970,
            "auto_load": false,
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: obj, options: []) else {
            aiRuntimeLastTestText = "AI test: failed to encode request"
            return
        }
        do {
            try data.write(to: reqURL, options: .atomic)
        } catch {
            aiRuntimeLastTestText = "AI test: cannot write request (\(error.localizedDescription))"
            return
        }

        // Poll response asynchronously to keep UI responsive.
        Task { @MainActor in
            let finalText: String = await Task.detached(priority: .userInitiated) {
                let deadline = Date().addingTimeInterval(12)
                var pos: UInt64 = 0
                var buf = ""
                var done: (ok: Bool, reason: String)? = nil

                while Date() < deadline {
                    if let fh = try? FileHandle(forReadingFrom: respURL) {
                        defer { try? fh.close() }
                        do {
                            try fh.seek(toOffset: pos)
                            let chunk = try fh.readToEnd() ?? Data()
                            pos += UInt64(chunk.count)
                            if !chunk.isEmpty, let s = String(data: chunk, encoding: .utf8) {
                                for line in s.split(separator: "\n", omittingEmptySubsequences: true) {
                                    guard let ld = String(line).data(using: .utf8) else { continue }
                                    guard let o = try? JSONSerialization.jsonObject(with: ld) as? [String: Any] else { continue }
                                    guard String(describing: o["req_id"] ?? "") == reqId else { continue }
                                    let typ = String(describing: o["type"] ?? "")
                                    if typ == "delta" {
                                        buf += String(describing: o["text"] ?? "")
                                    } else if typ == "done" {
                                        let ok = (o["ok"] as? Bool) ?? false
                                        let reason = String(describing: o["reason"] ?? "")
                                        done = (ok: ok, reason: reason)
                                    }
                                }
                            }
                        } catch {
                            // Ignore read races.
                        }
                    }

                    if done != nil { break }
                    try? await Task.sleep(nanoseconds: 120_000_000) // 120ms
                }

                if let d = done {
                    if d.ok {
                        let t = buf.trimmingCharacters(in: .whitespacesAndNewlines)
                        return t.isEmpty ? "AI test: OK (empty response)" : "AI test: OK — \(t.prefix(120))"
                    }
                    return "AI test: FAILED — \(d.reason)"
                }
                return "AI test: timeout"
            }.value

            self.aiRuntimeLastTestText = finalText
        }
    }

    // -------------------- Hub AI (file IPC) --------------------
    private func preferredModelIdForTask(_ taskType: String) -> String {
        let k = taskType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return routingPreferredModelIdByTask[k] ?? ""
    }

    /// Send a single text-generate request to the local runtime via file IPC.
    ///
    /// This is used by Hub-side features (Routing Preview, Today New summaries, etc).
    func aiGenerate(
        prompt: String,
        taskType: String,
        maxTokens: Int = 768,
        temperature: Double = 0.2,
        topP: Double = 0.95,
        autoLoad: Bool = true,
        timeoutSec: Double = 25
    ) async throws -> String {
        // Preflight.
        guard let st = AIRuntimeStatusStorage.load(), st.isAlive(ttl: 3.0) else {
            throw NSError(domain: "relflowhub", code: 1, userInfo: [NSLocalizedDescriptionKey: "AI runtime is not running. Open Settings → AI Runtime and click Start."])
        }
        if !st.isProviderReady("mlx", ttl: 3.0) {
            let doctor = st.providerDoctorText(ttl: 3.0).trimmingCharacters(in: .whitespacesAndNewlines)
            let fallback = (st.providerStatus("mlx")?.importError?.isEmpty == false)
                ? (st.providerStatus("mlx")?.importError ?? "")
                : ((st.importError?.isEmpty == false) ? (st.importError ?? "") : "MLX provider unavailable")
            let msg = doctor.isEmpty ? fallback : doctor
            throw NSError(domain: "relflowhub", code: 2, userInfo: [NSLocalizedDescriptionKey: "AI runtime is not ready: \(msg)"])
        }
        let localTextModels = ModelStore.shared.snapshot.models.filter { model in
            let path = (model.modelPath ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return !path.isEmpty
                && model.backend.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "mlx"
                && model.taskKinds.contains("text_generate")
        }
        if localTextModels.isEmpty {
            throw NSError(domain: "relflowhub", code: 3, userInfo: [NSLocalizedDescriptionKey: "No local text-generate model is registered. Open Models → Add Model… and import an MLX text model."])
        }

        let base = SharedPaths.ensureHubDirectory()
        let reqDir = base.appendingPathComponent("ai_requests", isDirectory: true)
        let respDir = base.appendingPathComponent("ai_responses", isDirectory: true)
        try? FileManager.default.createDirectory(at: reqDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: respDir, withIntermediateDirectories: true)

        let reqId = UUID().uuidString
        let reqURL = reqDir.appendingPathComponent("req_\(reqId).json")
        let respURL = respDir.appendingPathComponent("resp_\(reqId).jsonl")
        let preferred = preferredModelIdForTask(taskType)

        let obj: [String: Any] = [
            "type": "generate",
            "req_id": reqId,
            "app_id": "hub_ui",
            "task_type": taskType,
            "preferred_model_id": preferred,
            "prompt": prompt,
            "max_tokens": max(1, min(8192, maxTokens)),
            "temperature": temperature,
            "top_p": topP,
            "created_at": Date().timeIntervalSince1970,
            "auto_load": autoLoad,
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: obj, options: []) else {
            throw NSError(domain: "relflowhub", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to encode AI request"])
        }
        do {
            try data.write(to: reqURL, options: .atomic)
        } catch {
            throw NSError(domain: "relflowhub", code: 5, userInfo: [NSLocalizedDescriptionKey: "Cannot write AI request (\(error.localizedDescription))"])
        }

        let finalText: String = try await Task.detached(priority: .userInitiated) {
            let deadline = Date().addingTimeInterval(timeoutSec)
            var pos: UInt64 = 0
            var buf = ""
            var done: (ok: Bool, reason: String)? = nil

            while Date() < deadline {
                if let fh = try? FileHandle(forReadingFrom: respURL) {
                    defer { try? fh.close() }
                    do {
                        try fh.seek(toOffset: pos)
                        let chunk = try fh.readToEnd() ?? Data()
                        pos += UInt64(chunk.count)
                        if !chunk.isEmpty, let s = String(data: chunk, encoding: .utf8) {
                            for line in s.split(separator: "\n", omittingEmptySubsequences: true) {
                                guard let ld = String(line).data(using: .utf8) else { continue }
                                guard let o = try? JSONSerialization.jsonObject(with: ld) as? [String: Any] else { continue }
                                guard String(describing: o["req_id"] ?? "") == reqId else { continue }
                                let typ = String(describing: o["type"] ?? "")
                                if typ == "delta" {
                                    buf += String(describing: o["text"] ?? "")
                                } else if typ == "done" {
                                    let ok = (o["ok"] as? Bool) ?? false
                                    let reason = String(describing: o["reason"] ?? "")
                                    done = (ok: ok, reason: reason)
                                }
                            }
                        }
                    } catch {
                        // Ignore read races.
                    }
                }

                if done != nil { break }
                try? await Task.sleep(nanoseconds: 120_000_000)
            }

            if let d = done {
                if d.ok {
                    return buf.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                throw NSError(domain: "relflowhub", code: 6, userInfo: [NSLocalizedDescriptionKey: d.reason])
            }
            throw NSError(domain: "relflowhub", code: 7, userInfo: [NSLocalizedDescriptionKey: "AI request timed out"])
        }.value

        return finalText
    }

    // -------------------- Today New (FA) batch summarization --------------------
    private struct FASummaryItem {
        let radarId: Int
        let title: String
    }

    private func parseFATrackerProjectName(_ n: HubNotification) -> String? {
        guard n.source == "FAtracker" else { return nil }
        let lines = n.body.split(separator: "\n", omittingEmptySubsequences: false).map { String($0) }
        if let first = lines.first {
            let s = first.trimmingCharacters(in: .whitespacesAndNewlines)
            if !s.isEmpty { return s }
        }
        return nil
    }

    private func parseFATrackerRadarIds(_ n: HubNotification) -> [Int] {
        guard n.source == "FAtracker" else { return [] }
        if let s = n.actionURL, let u = URL(string: s), (u.scheme ?? "").lowercased() == "relflowhub" {
            let items = URLComponents(url: u, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let radarsRaw = items.first(where: { $0.name == "radars" })?.value ?? ""
            let ids = radarsRaw.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            if !ids.isEmpty { return ids }
        }

        // Fallback: only look at the 2nd line (plain id list).
        let lines = n.body.split(separator: "\n", omittingEmptySubsequences: false).map { String($0) }
        if lines.count >= 2 {
            return lines[1].split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        }
        return []
    }

    private func parseFATrackerRadarTitles(_ n: HubNotification) -> [Int: String] {
        // Expected agent body format:
        //   <projectName>\n
        //   <id, id, id>\n
        //   \n
        //   <id> - <title>\n
        guard n.source == "FAtracker" else { return [:] }
        let lines = n.body.split(separator: "\n", omittingEmptySubsequences: false).map { String($0) }
        if lines.count < 3 { return [:] }

        var out: [Int: String] = [:]
        for i in 2..<lines.count {
            let ln = lines[i].trimmingCharacters(in: .whitespacesAndNewlines)
            if ln.isEmpty { continue }

            // Extract leading number.
            var digits = ""
            var idx = ln.startIndex
            while idx < ln.endIndex {
                let ch = ln[idx]
                if ch.isNumber {
                    digits.append(ch)
                    idx = ln.index(after: idx)
                    continue
                }
                break
            }
            guard let rid = Int(digits), rid > 0 else { continue }

            var rest = String(ln[idx...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if rest.hasPrefix("-") || rest.hasPrefix("—") || rest.hasPrefix(":") {
                rest = String(rest.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            let ttl = rest.trimmingCharacters(in: .whitespacesAndNewlines)
            if !ttl.isEmpty {
                out[rid] = ttl
            }
        }
        return out
    }

    func summarizeTodayNewFA(projectNameFilter: String? = nil) async throws -> String {
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: Date()).timeIntervalSince1970
        let now = Date().timeIntervalSince1970
        let active = notifications.filter { ($0.snoozedUntil ?? 0) <= now }
        let todayFA = active.filter { isFATrackerRadarNotification($0) && $0.createdAt >= todayStart }
        if todayFA.isEmpty {
            throw NSError(domain: "relflowhub", code: 20, userInfo: [NSLocalizedDescriptionKey: "No new FA radars today."])
        }

        // Group by project name.
        var itemsByProject: [String: [FASummaryItem]] = [:]
        for n in todayFA {
            let proj = (parseFATrackerProjectName(n) ?? "(Unknown Project)").trimmingCharacters(in: .whitespacesAndNewlines)
            if let f = projectNameFilter, !f.isEmpty, proj != f { continue }
            let ids = parseFATrackerRadarIds(n)
            let titles = parseFATrackerRadarTitles(n)
            var arr = itemsByProject[proj] ?? []
            for rid in ids {
                let ttl = titles[rid] ?? ""
                arr.append(FASummaryItem(radarId: rid, title: ttl))
            }
            // De-dup by radar id.
            var seen: Set<Int> = []
            arr = arr.filter { seen.insert($0.radarId).inserted }
            itemsByProject[proj] = arr
        }

        if itemsByProject.isEmpty {
            throw NSError(domain: "relflowhub", code: 21, userInfo: [NSLocalizedDescriptionKey: "No matching project radars found."])
        }

        let projects = itemsByProject.keys.sorted()
        var input = ""
        for p in projects {
            let arr = itemsByProject[p] ?? []
            input += "Project: \(p) (\(arr.count))\n"
            for it in arr.prefix(18) {
                if it.title.isEmpty {
                    input += "- \(it.radarId)\n"
                } else {
                    input += "- \(it.radarId): \(it.title)\n"
                }
            }
            if arr.count > 18 {
                input += "- … (+\(arr.count - 18) more)\n"
            }
            input += "\n"
        }

        let prompt = (
            "你是失效分析(FA)每日雷达汇总助理。\n"
            + "请根据下面的‘今日新增 radars（按 project 分组）’，输出一个可执行的简短摘要。\n"
            + "注意：你只能基于给定的 radar id + title 做归纳，不要编造具体细节。\n\n"
            + "输出格式（纯文本，不要 markdown）：\n"
            + "Overall:\n"
            + "- Total radars: <N>\n"
            + "- Top themes: <2-4 bullets>\n"
            + "- Suggested next actions: <2-4 bullets>\n\n"
            + "Per project:\n"
            + "<Project name> (N):\n"
            + "- Themes: ...\n"
            + "- Attention radars: <up to 5 ids> (why)\n"
            + "- Next actions: ...\n\n"
            + "Rules:\n"
            + "- 如果 title 信息不足，请写 ‘信息不足：缺少 title/上下文’。\n"
            + "- Next actions 要具体（找谁/查什么/跑什么/补什么证据）。\n"
            + "- 保持简短（整体 25 行以内）。\n\n"
            + "Today New radars:\n"
            + input
        )

        return try await aiGenerate(prompt: prompt, taskType: "summarize", maxTokens: 900, temperature: 0.2, autoLoad: true, timeoutSec: 35)
    }

    private func appendAIRuntimeLogLine(_ line: String) {
        guard let h = aiRuntimeLogHandle else {
            return
        }
        let ts = ISO8601DateFormatter().string(from: Date())
        let s = "[\(ts)] \(line)\n"
        guard let data = s.data(using: .utf8) else {
            return
        }
        do {
            try h.write(contentsOf: data)
        } catch {
            // Ignore.
        }
    }

    private func defaultRuntimePythonServicePath() -> String {
        // Dev build heuristic: .../REL Flow Hub/build/RELFlowHub.app -> .../REL Flow Hub/python_service/
        var dir = Bundle.main.bundleURL.deletingLastPathComponent()
        for _ in 0..<6 {
            let candidate = dir.appendingPathComponent("python_service", isDirectory: true)
            if FileManager.default.directoryExists(atPath: candidate.path),
               preferredAIRuntimeScriptURL(in: candidate) != nil {
                return candidate.path
            }
            dir.deleteLastPathComponent()
        }
        return ""
    }

    private func defaultRuntimeScriptPath() -> String {
        let root = defaultRuntimePythonServicePath()
        guard !root.isEmpty else {
            return ""
        }
        guard let scriptURL = preferredAIRuntimeScriptURL(in: URL(fileURLWithPath: root, isDirectory: true)) else {
            return ""
        }
        return scriptURL.path
    }

    private func defaultPythonPath() -> String {
        // Prefer a real python binary. `/usr/bin/python3` and `env python3` can be a
        // CommandLineTools stub that shells out to xcrun, which fails under App Sandbox.
        let cands = [
            "/Library/Frameworks/Python.framework/Versions/3.11/bin/python3",
            "/Library/Frameworks/Python.framework/Versions/Current/bin/python3",
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3",
        ]
        for p in cands {
            if FileManager.default.fileExists(atPath: p) {
                return p
            }
        }
        // Fallback (may be a stub on some systems).
        return "/usr/bin/env"
    }

    func startIPC() {
        HubDiagnostics.log("startIPC pid=\(getpid()) sandbox=\(SharedPaths.isSandboxedProcess())")
        // In App Sandbox, external tools cannot reliably connect to AF_UNIX sockets.
        // Use file-based IPC dropbox + heartbeat.
        if SharedPaths.isSandboxedProcess() {
            let f = FileIPC(store: self)
            self.fileIPC = f
            do {
                try f.start()
                ipcStatus = "IPC: file"
                ipcPath = f.ipcPathText()
                HubDiagnostics.log("startIPC ok mode=file path=\(ipcPath)")
            } catch {
                ipcStatus = "IPC: file failed (\(error))"
                ipcPath = f.ipcPathText()
                HubDiagnostics.log("startIPC failed mode=file err=\(error)")
            }
            return
        }

        let srv = UnixSocketServer(store: self)
        self.server = srv
        do {
            try srv.start()
            ipcStatus = "IPC: socket"
            ipcPath = SharedPaths.ipcSocketPath()
            HubDiagnostics.log("startIPC ok mode=socket path=\(ipcPath)")
        } catch {
            ipcStatus = "IPC: socket failed (\(error))"
            ipcPath = SharedPaths.ipcSocketPath()
            HubDiagnostics.log("startIPC failed mode=socket err=\(error)")
        }
    }

    func startDemoSatellites(count: Int = 6, seconds: Int = 120) {
        stopDemoSatellites(removeFiles: true)

        let n = max(1, min(6, count))
        let endAt = Date().addingTimeInterval(Double(max(10, min(600, seconds)))).timeIntervalSince1970
        demoSatellitesEndAt = endAt

        // Global stop marker: if multiple Hub instances are running, a single stop should
        // disable demo writers across all instances.
        let stopMarker = ClientStorage.dir().appendingPathComponent(".demo_satellites_stop")
        try? FileManager.default.removeItem(at: stopMarker)

        writeDemoSatellites(count: n)
        demoSatellitesTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }

                // Respect global stop marker.
                let stopMarker = ClientStorage.dir().appendingPathComponent(".demo_satellites_stop")
                if FileManager.default.fileExists(atPath: stopMarker.path) {
                    self.stopDemoSatellites(removeFiles: true)
                    return
                }

                if Date().timeIntervalSince1970 >= self.demoSatellitesEndAt {
                    self.stopDemoSatellites(removeFiles: true)
                    return
                }
                self.writeDemoSatellites(count: n)
            }
        }
    }

    private func writeDemoSatellites(count: Int) {
        let n = max(1, min(6, count))
        let now = Date().timeIntervalSince1970
        let dir = ClientStorage.dir()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        for i in 1...n {
            let id = "demoapp\(i)"
            let hb = HubClientHeartbeat(
                appId: id,
                appName: "Demo App \(i)",
                activity: (i % 3 == 0) ? .idle : .active,
                aiEnabled: (i % 2 == 0),
                modelMemoryBytes: Int64(1_200_000_000 + i * 350_000_000),
                updatedAt: now
            )
            let path = dir.appendingPathComponent("\(id).json")
            if let data = try? JSONEncoder().encode(hb) {
                try? data.write(to: path, options: .atomic)
            }
        }

        clients.refresh()
    }

    func stopDemoSatellites(removeFiles: Bool = true) {
        demoSatellitesTimer?.invalidate()
        demoSatellitesTimer = nil
        demoSatellitesEndAt = 0

        guard removeFiles else { return }
        let dir = ClientStorage.dir()

        // Write stop marker first so any other Hub instances stop refreshing demo files.
        let stopMarker = dir.appendingPathComponent(".demo_satellites_stop")
        try? Data("stop".utf8).write(to: stopMarker, options: .atomic)

        // Remove all demoapp*.json files (be robust to older runs).
        if let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
            for url in files {
                let name = url.lastPathComponent
                if name.hasPrefix("demoapp") && name.hasSuffix(".json") {
                    try? FileManager.default.removeItem(at: url)
                }
            }
        }
        clients.refresh()
    }

    func push(_ n: HubNotification) {
        // Allow users to disable noisy sources without uninstalling any agent.
        if !integrationFATrackerEnabled, n.source == "FAtracker" {
            return
        }
        if !integrationMailEnabled, n.source == "Mail" {
            return
        }
        if !integrationMessagesEnabled, n.source == "Messages" {
            return
        }
        if !integrationSlackEnabled, n.source == "Slack" {
            return
        }

        // Counts-only notifications (Mail/Messages/Slack) must go through the same
        // upsert/baseline logic as the built-in integrations. This allows an external
        // Dock agent to push counts without re-alerting after the user opens the app.
        if let key = n.dedupeKey, !key.isEmpty, (key == "mail_unread" || key == "messages_unread" || key == "slack_updates") {
            externalCountsUpdateAtByKey[key] = Date().timeIntervalSince1970
            let count = firstInt(in: n.body) ?? firstInt(in: n.title) ?? 0
            let bundleId: String = {
                if let s = n.actionURL, let u = URL(string: s),
                   let items = URLComponents(url: u, resolvingAgainstBaseURL: false)?.queryItems,
                   let bid = items.first(where: { $0.name == "bundle_id" })?.value,
                   !bid.isEmpty {
                    return bid
                }
                if n.source == "Mail" { return "com.apple.mail" }
                if n.source == "Messages" { return "com.apple.MobileSMS" }
                if n.source == "Slack" { return "com.tinyspeck.slackmacgap" }
                return ""
            }()

            if !bundleId.isEmpty {
                upsertCountsOnlyNotification(source: n.source, bundleId: bundleId, count: count, dedupeKey: key)
                return
            }
        }

        // Treat inbound notifications as a client "presence" signal so satellites show up even
        // before apps implement explicit heartbeat writes.
        touchClientPresence(from: n)

        // Dedupe/update on dedupeKey when provided.
        if let key = n.dedupeKey, !key.isEmpty {
            if let idx = notifications.firstIndex(where: { $0.dedupeKey == key }) {
                var merged = n
                merged.id = notifications[idx].id
                notifications[idx] = merged
                sort()
                updateSummary()
                schedulePersistNotifications()
                return
            }
        }
        notifications.append(n)
        sort()
        updateSummary()
        schedulePersistNotifications()
    }

    private func touchClientPresence(from n: HubNotification) {
        let source = n.source.trimmingCharacters(in: .whitespacesAndNewlines)
        if source.isEmpty || source == "Hub" { return }

        let now = Date().timeIntervalSince1970

        let appId = normalizedClientId(source)
        if appId.isEmpty { return }

        // Throttle disk writes to keep the hub ultra-light.
        if let last = lastClientTouchById[appId], (now - last) < 5.0 {
            return
        }
        lastClientTouchById[appId] = now

        let dir = ClientStorage.dir()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let path = dir.appendingPathComponent("\(appId).json")
        var hb: HubClientHeartbeat

        if let data = try? Data(contentsOf: path),
           let existing = try? JSONDecoder().decode(HubClientHeartbeat.self, from: data) {
            hb = existing
            hb.appName = existing.appName.isEmpty ? source : existing.appName
            hb.activity = .active
            hb.updatedAt = now
        } else {
            hb = HubClientHeartbeat(appId: appId, appName: source, activity: .active, aiEnabled: false, updatedAt: now)
        }

        if let data = try? JSONEncoder().encode(hb) {
            // `.atomic` keeps the file read-safe for the ClientStore polling loop.
            try? data.write(to: path, options: .atomic)
        }

        // Pull immediately so the floating orb can reflect the new satellite quickly.
        clients.refresh()
    }

    private func normalizedClientId(_ s: String) -> String {
        let lower = s.lowercased()
        var out = ""
        out.reserveCapacity(lower.count)
        for ch in lower.unicodeScalars {
            let v = ch.value
            if (v >= 48 && v <= 57) || (v >= 97 && v <= 122) {
                out.unicodeScalars.append(ch)
            } else if v == 95 || v == 45 || v == 32 {
                if out.last != "_" { out.append("_") }
            }
        }
        return out.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    }

    func snooze(_ id: String, minutes: Int = 10) {
        let m = max(1, min(24 * 60, minutes))
        if let idx = notifications.firstIndex(where: { $0.id == id }) {
            notifications[idx].snoozedUntil = Date().addingTimeInterval(Double(m) * 60.0).timeIntervalSince1970
            updateSummary()
            sort()
            schedulePersistNotifications()
        }
    }

    func snoozeLaterToday(_ id: String) {
        // "Later Today" heuristic: if before 17:00 -> 17:00, else -> tomorrow 09:00.
        let now = Date()
        let cal = Calendar.current
        let hour = cal.component(.hour, from: now)
        var target: Date
        if hour < 17 {
            target = cal.date(bySettingHour: 17, minute: 0, second: 0, of: now) ?? now.addingTimeInterval(60 * 60)
        } else {
            let tomorrow = cal.date(byAdding: .day, value: 1, to: now) ?? now.addingTimeInterval(24 * 60 * 60)
            target = cal.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow
        }
        snoozeUntil(id, until: target)
    }

    private func snoozeUntil(_ id: String, until: Date) {
        if let idx = notifications.firstIndex(where: { $0.id == id }) {
            notifications[idx].snoozedUntil = until.timeIntervalSince1970
            updateSummary()
            sort()
            schedulePersistNotifications()
        }
    }

    func unsnooze(_ id: String) {
        if let idx = notifications.firstIndex(where: { $0.id == id }) {
            notifications[idx].snoozedUntil = nil
            updateSummary()
            sort()
            schedulePersistNotifications()
        }
    }

    func requestCalendarAccessAndStart() {
        // Calendar permission prompts can fail to appear if the app is not active.
        NSApp.activate(ignoringOtherApps: true)
        if calendar == nil {
            calendar = CalendarPipeline(remindMinutesBefore: calendarRemindMinutes)
        }
        Task { @MainActor in
            guard let cal = calendar else { return }
            let ok = await cal.requestAccessIfNeeded()
            refreshCalendarStatusOnly()
            if ok {
                await requestNotificationAuthorizationIfNeeded()
                cal.startPolling { [weak self] meetings, specialDays in
                    self?.handleCalendarMeetingsUpdate(meetings, specialDays: specialDays)
                }
                // Force an immediate refresh after access transitions to granted.
                self.refreshCalendar()
            }
        }
    }

    func refreshCalendar() {
        guard let cal = calendar else { return }
        let ms = cal.fetchNext12HoursMeetings()
        let special = cal.fetchTodaySpecialDays()
        handleCalendarMeetingsUpdate(ms, specialDays: special)
    }

    func markRead(_ id: String) {
        if let idx = notifications.firstIndex(where: { $0.id == id }) {
            notifications[idx].unread = false
            updateSummary()
            schedulePersistNotifications()
        }
    }

    func openNotificationAction(_ n: HubNotification) {
        guard let s = n.actionURL, !s.isEmpty, let url = URL(string: s) else {
            return
        }

        // Counts-only integrations: opening the target app counts as "seen".
        if let key = n.dedupeKey, let c = (firstInt(in: n.body) ?? firstInt(in: n.title)) {
            if key == "mail_unread" || key == "messages_unread" || key == "slack_updates" {
                setLastSeenCount(c, dedupeKey: key)
            }
        }

        // Custom local actions handled by the Hub.
        if handleLocalActionURL(url) {
            return
        }

        // Default: let macOS route the URL.
        NSWorkspace.shared.open(url)
    }

    func openFATrackerForRadars(_ radarIds: [Int], projectId: Int? = nil, fallbackURL: String? = nil) {
        openInFATracker(radarIds: radarIds, projectId: projectId, fallbackURL: fallbackURL)
    }

    func setFATrackerLauncher(url: URL) {
        faTrackerLauncherPath = url.path
        // Persist a security-scoped bookmark so sandboxed builds can open it later.
        do {
            let data = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(data, forKey: faTrackerLauncherBookmarkKey)
        } catch {
            // Keep path only; opening may still work if it is inside an allowed location.
            UserDefaults.standard.removeObject(forKey: faTrackerLauncherBookmarkKey)
        }
    }

    func clearFATrackerLauncher() {
        faTrackerLauncherPath = ""
        UserDefaults.standard.removeObject(forKey: faTrackerLauncherBookmarkKey)
    }

    func testOpenFATrackerLauncher() {
        _ = openFATracker()
    }

    func openFATracker() -> Bool {
        if openFATrackerByBundleIdIfConfigured() {
            return true
        }
        return openFATrackerLauncherIfConfigured()
    }

    private func handleLocalActionURL(_ url: URL) -> Bool {
        // relflowhub://handoff/fatracker?radars=123,456&fallback=rdar://123
        let scheme = (url.scheme ?? "").lowercased()
        if scheme != "relflowhub" {
            return false
        }
        let host = (url.host ?? "").lowercased()
        let path = url.path.lowercased()

        // relflowhub://openapp?bundle_id=com.apple.mail
        if host == "openapp" {
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let bid = (items.first(where: { $0.name == "bundle_id" })?.value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !bid.isEmpty, let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) {
                _ = NSWorkspace.shared.open(appURL)
                return true
            }
            return true // handled (even if we couldn't resolve)
        }

        if host == "handoff" && path == "/fatracker" {
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let radarsRaw = items.first(where: { $0.name == "radars" })?.value ?? ""
            let fallback = items.first(where: { $0.name == "fallback" })?.value
            let projectId = Int(items.first(where: { $0.name == "project_id" })?.value ?? "")
            let ids = radarsRaw.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            openInFATracker(radarIds: ids, projectId: projectId, fallbackURL: fallback)
            return true
        }
        return false
    }

    private func openInFATracker(radarIds: [Int], projectId: Int?, fallbackURL: String?) {
        // 1) Write a handoff file so FA Tracker can locate the intended radars.
        if !radarIds.isEmpty {
            writeFATrackerHandoff(radarIds: radarIds, projectId: projectId)
        }

        // 2) Attempt to launch FA Tracker (preferred).
        if openFATracker() {
            return
        }

        // 3) Fallback: open the first rdar:// link (or explicit fallback URL).
        if let s = fallbackURL, let u = URL(string: s) {
            NSWorkspace.shared.open(u)
            return
        }
        if let first = radarIds.first, let u = URL(string: "rdar://\(first)") {
            NSWorkspace.shared.open(u)
        }
    }

    private func openFATrackerByBundleIdIfConfigured() -> Bool {
        let bid = faTrackerBundleId.trimmingCharacters(in: .whitespacesAndNewlines)
        if bid.isEmpty { return false }

        // Resolve to an app URL via LaunchServices (does not require direct file access).
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) {
            return NSWorkspace.shared.open(url)
        }

        return false
    }

    private func openFATrackerLauncherIfConfigured() -> Bool {
        // Prefer the security-scoped bookmark if available.
        if let data = UserDefaults.standard.data(forKey: faTrackerLauncherBookmarkKey) {
            var stale = false
            do {
                let u = try URL(
                    resolvingBookmarkData: data,
                    options: [.withSecurityScope],
                    relativeTo: nil,
                    bookmarkDataIsStale: &stale
                )
                let ok = u.startAccessingSecurityScopedResource()
                defer {
                    if ok { u.stopAccessingSecurityScopedResource() }
                }
                if FileManager.default.fileExists(atPath: u.path) {
                    return NSWorkspace.shared.open(u)
                }
            } catch {
                // Fall back to path.
            }
        }

        let p = faTrackerLauncherPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if p.isEmpty { return false }
        let u = URL(fileURLWithPath: normalizeUserPath(p))
        // Do not preflight existence here: sandboxed builds may be unable to stat the file even
        // though LaunchServices can open it.
        return NSWorkspace.shared.open(u)
    }

    func installFATrackerLauncherWrapper(targetPath: String) -> Bool {
        let target = normalizeUserPath(targetPath)
        if target.isEmpty { return false }

        // Put the wrapper under ~/RELFlowHub (allowed by our sandbox exception).
        let base = SharedPaths.ensureHubDirectory()
        let out = base.appendingPathComponent("launch_fatracker.command")

        let esc = target.replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
#!/bin/bash
set -euo pipefail

TARGET=\"\(esc)\"

if [ -d \"$TARGET\" ] && [[ \"$TARGET\" == *.app ]]; then
  /usr/bin/open \"$TARGET\"
  exit 0
fi

if [ -f \"$TARGET\" ]; then
  /bin/bash \"$TARGET\"
  exit 0
fi

echo \"FA Tracker launcher target not found: $TARGET\" >&2
exit 1
"""

        do {
            try script.data(using: .utf8)?.write(to: out, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: out.path)
            faTrackerLauncherPath = out.path
            // Wrapper is inside allowed path; bookmark isn't necessary.
            UserDefaults.standard.removeObject(forKey: faTrackerLauncherBookmarkKey)
            return true
        } catch {
            return false
        }
    }

    private func normalizeUserPath(_ s: String) -> String {
        // Users often paste shell-escaped paths (e.g. "Andrew\ projects").
        // Convert common escapes back to a normal filesystem path.
        var p = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if (p.hasPrefix("\"") && p.hasSuffix("\"")) || (p.hasPrefix("'") && p.hasSuffix("'")) {
            p = String(p.dropFirst().dropLast())
        }
        p = p.replacingOccurrences(of: "\\ ", with: " ")
        return (p as NSString).expandingTildeInPath
    }

    private func writeFATrackerHandoff(radarIds: [Int], projectId: Int?) {
        var obj: [String: Any] = [
            "type": "fatracker_open",
            "createdAt": Date().timeIntervalSince1970,
            "radarIds": radarIds,
        ]
        if let pid = projectId, pid > 0 {
            obj["projectId"] = pid
        }

        // Write into the Hub directory (sandbox-safe). FA Tracker also watches this location.
        // This avoids App Group TCC prompt spam on ad-hoc signed dev builds.
        let base = SharedPaths.ensureHubDirectory()

        guard let data = try? JSONSerialization.data(withJSONObject: obj, options: []) else {
            return
        }

        let dir = base.appendingPathComponent("handoff", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent("fatracker_open.json")
        try? data.write(to: path, options: .atomic)

        // Note: we intentionally do not touch App Group storage here to avoid repeated prompts.
    }

    func dismiss(_ id: String) {
        notifications.removeAll(where: { $0.id == id })
        updateSummary()
        schedulePersistNotifications()
    }

    func dismissAll() {
        notifications.removeAll()
        updateSummary()
        schedulePersistNotifications()
    }

    private func sort() {
        notifications.sort { a, b in
            let now = Date().timeIntervalSince1970
            let asn = (a.snoozedUntil ?? 0) > now
            let bsn = (b.snoozedUntil ?? 0) > now
            if asn != bsn {
                return !asn && bsn
            }
            if a.unread != b.unread {
                return a.unread && !b.unread
            }
            return a.createdAt > b.createdAt
        }
    }

    private func updateSummary() {
        // MVP: Today-new count is the number of unread FAtracker "radar" notifications.
        let now = Date().timeIntervalSince1970
        let n = notifications.filter { $0.unread && ($0.snoozedUntil ?? 0) <= now && isFATrackerRadarNotification($0) }.count
        let nextText = nextMeetingText()
        SummaryStorage.save(
            SummaryState(
                todayNewUnseenCount: n,
                nextMeetingText: nextText,
                updatedAt: Date().timeIntervalSince1970
            )
        )
    }

    func isFATrackerRadarNotification(_ n: HubNotification) -> Bool {
        if n.source != "FAtracker" { return false }

        // Agent notifications use a stable title format.
        if n.title.hasPrefix("New radars:") { return true }

        // Or a relflowhub local handoff action.
        if let s = n.actionURL, let u = URL(string: s), (u.scheme ?? "").lowercased() == "relflowhub" {
            return (u.host ?? "").lowercased() == "handoff" && u.path.lowercased() == "/fatracker"
        }

        return false
    }

    private func nextMeetingText() -> String {
        let now = Date().timeIntervalSince1970
        if let m = meetings.first(where: { $0.isMeeting && !$0.id.isEmpty && !isMeetingDismissed($0, now: now) }) {
            let f = DateFormatter()
            f.dateFormat = "HH:mm"
            if now >= m.startAt && now < m.endAt {
                return "Now: \(m.title)"
            }
            return "Next: \(f.string(from: m.startDate)) \(m.title)"
        }
        // Keep default consistent with widget template.
        return "No events today"
    }

    private func handleCalendarMeetingsUpdate(_ ms: [HubMeeting], specialDays: [String]) {
        meetings = ms
        specialDaysToday = specialDays
        pruneDismissedMeetings(now: Date().timeIntervalSince1970)
        updateSummary()
    }

    private func refreshCalendarStatusOnly() {
        if calendar == nil {
            calendar = CalendarPipeline(remindMinutesBefore: calendarRemindMinutes)
        }
        calendarStatus = calendar?.currentStatusText() ?? "Calendar: unknown"
    }

    private func setupNotificationsAuthorizationState() {
        // No-op for now; kept as a hook for future UI.
    }

    private func requestNotificationAuthorizationIfNeeded() async {
        guard NotificationSupport.isAvailable else { return }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }
    }
}

private struct DockAgentStatusFile: Codable {
    var updatedAt: Double
    var pid: Int32
    var appVersion: String
    var appBuild: String
    var appPath: String
    var axTrusted: Bool
    var autoStartInstalled: Bool
    var autoStartLoaded: Bool
}
