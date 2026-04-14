import SwiftUI
import AppKit
import Dispatch

@main
struct XTerminalApp: App {
    @NSApplicationDelegateAdaptor(XTerminalAppDelegate.self) private var appDelegate
    @StateObject private var appModel = AppModel()

    init() {
        if let code = XTerminalGateSmokeRunner.runIfRequested(arguments: CommandLine.arguments) {
            fflush(stdout)
            fflush(stderr)
            Foundation.exit(Int32(code))
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appModel)
                .onAppear {
                    appDelegate.bind(appModel: appModel)
                }
        }
        
        Window("Supervisor AI", id: "supervisor") {
            SupervisorView()
                .environmentObject(appModel)
        }

        Window("Supervisor Settings", id: "supervisor_settings") {
            SupervisorToolWindowRootView(preferredTab: .supervisor)
                .environmentObject(appModel)
        }

        Window("AI 模型", id: "model_settings") {
            SupervisorToolWindowRootView(preferredTab: .models)
                .environmentObject(appModel)
        }

        Window("Hub Setup", id: "hub_setup") {
            HubSetupWizardView()
                .environmentObject(appModel)
        }
        
        Settings {
            SettingsView()
                .environmentObject(appModel)
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("Open Project…") {
                    appModel.openProjectPicker()
                }
                .keyboardShortcut("o")
            }

            CommandMenu("Project") {
                Button(appModel.preferredResumeCommandTitle) {
                    appModel.presentPreferredResumeBrief()
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(!appModel.canPresentPreferredResumeBrief)

                Divider()

                Button("Open .xterminal Folder") {
                    appModel.openCurrentProjectXTerminalFolder()
                }
                .disabled(appModel.projectContext == nil)

                Button("Open AX_MEMORY.md") {
                    appModel.openCurrentProjectMemoryMarkdown()
                }
                .disabled(appModel.projectContext == nil)

                Button("Open ax_memory.json") {
                    appModel.openCurrentProjectMemoryJSON()
                }
                .disabled(appModel.projectContext == nil)

                Button("Open config.json") {
                    appModel.openCurrentProjectConfig()
                }
                .disabled(appModel.projectContext == nil)

                Button("Open raw_log.jsonl") {
                    appModel.openCurrentProjectRawLog()
                }
                .disabled(appModel.projectContext == nil)
            }

            CommandMenu("Hub") {
                Button(hubCommandTitle) {
                    Task { @MainActor in
                        await appModel.connectToHub(auto: false)
                    }
                }
                .keyboardShortcut("x", modifiers: [.command, .option])

                Divider()

                Button("Open Hub Setup Wizard") {
                    NotificationCenter.default.post(name: .xterminalOpenHubSetupWizard, object: nil)
                }

                Button("One-Click Pairing Setup") {
                    appModel.startHubOneClickSetup()
                }

                Button("Reconnect Remote Link") {
                    appModel.startHubReconnectOnly()
                }
            }

            CommandMenu(XTL10n.MenuBarLanguage.menuTitle) {
                ForEach(XTInterfaceLanguage.allCases) { option in
                    Button(
                        XTL10n.MenuBarLanguage.optionTitle(
                            option,
                            selectedLanguage: appModel.settingsStore.settings.interfaceLanguage
                        )
                    ) {
                        appModel.setInterfaceLanguage(option)
                    }
                }
            }
        }
    }

    private var hubCommandTitle: String {
        if appModel.hubConnected {
            return "Hub Connected"
        }
        if appModel.hubRemoteLinking {
            return "Hub Linking..."
        }
        if appModel.hubRemoteConnected {
            switch appModel.hubRemoteRoute {
            case .lan:
                return "Hub Relay (LAN)"
            case .internet:
                return "Hub Relay (Internet)"
            case .internetTunnel:
                return "Hub Relay (Tunnel)"
            case .none:
                return "Hub Relay"
            }
        }
        return "One-Click Connect to Hub"
    }
}

final class XTerminalAppDelegate: NSObject, NSApplicationDelegate {
    private weak var appModel: AppModel?

    func bind(appModel: AppModel) {
        self.appModel = appModel
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if XTerminalGateSmokeRunner.isSmokeInvocation(arguments: CommandLine.arguments) {
            return
        }
        // When launched via `swift run`, make sure the app is a regular foreground app
        // so keyboard events are routed to text inputs correctly.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        appModel?.cleanupPairedSurfaceHeartbeat()
        appModel?.persistSessionSummariesForLifecycle(reason: "app_exit")
    }
}

struct XTSupervisorVoiceSmokeReportSummary: Decodable, Equatable, Sendable {
    static let currentSchemaVersion = "xt.supervisor_voice_smoke.v1"

    enum Phase: String, Equatable, Sendable {
        case wake
        case grant
        case briefPlayback = "brief_playback"

        var order: Int {
            switch self {
            case .wake:
                return 0
            case .grant:
                return 1
            case .briefPlayback:
                return 2
            }
        }

        var headline: String {
            switch self {
            case .wake:
                return "唤醒阶段"
            case .grant:
                return "授权挑战阶段"
            case .briefPlayback:
                return "Hub 简报播报阶段"
            }
        }
    }

    enum PhaseStatus: String, Equatable, Sendable {
        case passed
        case failed
        case notReached = "not_reached"
        case unknown
    }

    struct Check: Decodable, Equatable, Sendable {
        var id: String?
        var passed: Bool?
        var detail: String?
    }

    var schemaVersion: String
    var outputPath: String?
    var voiceRoute: String?
    var error: String?
    var checks: [Check]

    var checkCount: Int { checks.count }

    var passedCheckCount: Int {
        checks.reduce(into: 0) { partialResult, item in
            if item.passed == true {
                partialResult += 1
            }
        }
    }

    var normalizedError: String? {
        let trimmed = error?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    var isPassing: Bool {
        normalizedError == nil && checkCount > 0 && passedCheckCount == checkCount
    }

    var firstFailedCheck: Check? {
        checks.first { $0.passed != true }
    }

    var firstFailedPhase: Phase? {
        Self.phase(forCheckID: firstFailedCheck?.id)
    }

    func phaseStatus(_ phase: Phase) -> PhaseStatus {
        if isPassing {
            return .passed
        }
        guard let failedPhase = firstFailedPhase else {
            return normalizedError == nil ? .unknown : .failed
        }
        if failedPhase == phase {
            return .failed
        }
        if failedPhase.order < phase.order {
            return .notReached
        }
        return .passed
    }

    func detailLines(for phase: Phase) -> [String] {
        var lines = [
            "voice_smoke_status=\(isPassing ? "pass" : normalizedError == nil ? "fail" : "error")",
            "voice_smoke_checks=\(passedCheckCount)/\(checkCount)",
            "voice_smoke_phase=\(phase.rawValue)",
            "voice_smoke_phase_status=\(phaseStatus(phase).rawValue)"
        ]
        let route = (voiceRoute ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !route.isEmpty {
            lines.append("voice_smoke_route=\(route)")
        }
        if let failedPhase = firstFailedPhase {
            lines.append("voice_smoke_failed_phase=\(failedPhase.rawValue)")
            lines.append("voice_smoke_failed_phase_label=\(failedPhase.headline)")
        }
        if let failedCheck = firstFailedCheck,
           let failedID = failedCheck.id?.trimmingCharacters(in: .whitespacesAndNewlines),
           !failedID.isEmpty {
            lines.append("voice_smoke_failed_check=\(failedID)")
            lines.append("voice_smoke_failed_check_label=\(Self.label(forCheckID: failedID))")
            let trimmedDetail = failedCheck.detail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !trimmedDetail.isEmpty {
                lines.append("voice_smoke_failed_detail=\(trimmedDetail)")
            }
        }
        if let normalizedError {
            lines.append("voice_smoke_error=\(normalizedError)")
        }
        return lines
    }

    func failureSummaryLine(for phase: Phase) -> String? {
        let status = phaseStatus(phase)
        switch status {
        case .passed:
            return "最近一次 Supervisor 语音自检已通过\(phase.headline)。"
        case .failed:
            let failedLabel = firstFailedCheck.flatMap { check in
                check.id.map(Self.label(forCheckID:))
            } ?? phase.headline
            let detail = firstFailedCheck?.detail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !detail.isEmpty {
                return "最近一次 Supervisor 语音自检卡在\(phase.headline)：\(failedLabel)。\(detail)"
            }
            return "最近一次 Supervisor 语音自检卡在\(phase.headline)：\(failedLabel)。"
        case .notReached:
            if let failedPhase = firstFailedPhase {
                return "最近一次 Supervisor 语音自检在\(failedPhase.headline)之前中断，所以还没走到\(phase.headline)。"
            }
            return "最近一次 Supervisor 语音自检还没走到\(phase.headline)。"
        case .unknown:
            if let normalizedError {
                return "最近一次 Supervisor 语音自检未能完成：\(normalizedError)"
            }
            return "最近一次 Supervisor 语音自检结果不完整。"
        }
    }

    static func load(from url: URL) throws -> XTSupervisorVoiceSmokeReportSummary {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(XTSupervisorVoiceSmokeReportSummary.self, from: data)
    }

    static func phase(forCheckID id: String?) -> Phase? {
        switch id?.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "wake_armed_ready", "wake_prompt_spoken":
            return .wake
        case "wake_prompt_resumed_listening", "voice_grant_challenge_issued", "grant_prompt_resumed_listening", "approve_callback_recorded":
            return .grant
        case "grant_approved_and_brief_emitted", "brief_resumed_listening", "brief_projection_callback_recorded":
            return .briefPlayback
        default:
            return nil
        }
    }

    static func label(forCheckID id: String) -> String {
        switch id.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "wake_armed_ready":
            return "唤醒待命未就绪"
        case "wake_prompt_spoken":
            return "唤醒响应提示未播报"
        case "wake_prompt_resumed_listening":
            return "唤醒提示后未恢复监听"
        case "voice_grant_challenge_issued":
            return "语音授权挑战未发出"
        case "grant_prompt_resumed_listening":
            return "授权提示后未恢复监听"
        case "approve_callback_recorded":
            return "授权批准回调未记录"
        case "grant_approved_and_brief_emitted":
            return "授权通过后未发出 Hub 简报"
        case "brief_resumed_listening":
            return "简报播报后未恢复监听"
        case "brief_projection_callback_recorded":
            return "Hub 简报投影回调未记录"
        default:
            return id
        }
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case outputPath = "output_path"
        case voiceRoute = "voice_route"
        case error
        case checks
    }
}

enum XTerminalGateSmokeRunner {
    static let routeSmokeFlag = "--xt-route-smoke"
    static let grantSmokeFlag = "--xt-grant-smoke"
    static let supervisorVoiceSmokeFlag = "--xt-supervisor-voice-smoke"
    static let supervisorDoctorRefreshFlag = "--xt-supervisor-doctor-refresh"
    static let unifiedDoctorExportFlag = "--xt-unified-doctor-export"
    static let releaseEvidenceSmokeFlag = "--xt-release-evidence-smoke"
    static let splitFlowFixtureSmokeFlag = "--xt-split-flow-fixture-smoke"
    static let projectRootFlag = "--project-root"
    static let outJSONFlag = "--out-json"

    static func isSmokeInvocation(arguments: [String]) -> Bool {
        arguments.contains(routeSmokeFlag)
            || arguments.contains(grantSmokeFlag)
            || arguments.contains(supervisorVoiceSmokeFlag)
            || arguments.contains(supervisorDoctorRefreshFlag)
            || arguments.contains(unifiedDoctorExportFlag)
            || arguments.contains(releaseEvidenceSmokeFlag)
            || arguments.contains(splitFlowFixtureSmokeFlag)
    }

    static func runIfRequested(arguments: [String]) -> Int? {
        if arguments.contains(routeSmokeFlag) {
            return runRouteSmoke(arguments: arguments)
        }
        if arguments.contains(grantSmokeFlag) {
            return runGrantSmoke(arguments: arguments)
        }
        if arguments.contains(supervisorVoiceSmokeFlag) {
            return runSupervisorVoiceSmoke(arguments: arguments)
        }
        if arguments.contains(supervisorDoctorRefreshFlag) {
            return runSupervisorDoctorRefresh(arguments: arguments)
        }
        if arguments.contains(unifiedDoctorExportFlag) {
            return runUnifiedDoctorExport(arguments: arguments)
        }
        if arguments.contains(releaseEvidenceSmokeFlag) {
            return runReleaseEvidenceSmoke(arguments: arguments)
        }
        if arguments.contains(splitFlowFixtureSmokeFlag) {
            return runSplitFlowFixtureSmoke(arguments: arguments)
        }
        return nil
    }

    @MainActor
    static func runSupervisorVoiceSmokeCheck(workspaceRoot: URL, outputURL: URL) async -> Int {
        await runSupervisorVoiceSmokeScenario(workspaceRoot: workspaceRoot, outputURL: outputURL)
    }

    private static func runRouteSmoke(arguments: [String]) -> Int {
        let root = projectRoot(from: arguments)
            ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let checks = HubRouteStateMachine.runSelfChecks()
        let passedCount = checks.filter(\.ok).count

        print("[xt-route-smoke] workspace=\(root.path)")
        print("[xt-route-smoke] self_checks=\(passedCount)/\(checks.count)")
        for item in checks {
            print("- [\(item.ok ? "PASS" : "FAIL")] \(item.name) :: \(item.detail)")
        }

        guard !checks.isEmpty else {
            print("[xt-route-smoke] FAIL")
            return 1
        }

        if checks.allSatisfy(\.ok) {
            print("[xt-route-smoke] PASS")
            return 0
        }

        print("[xt-route-smoke] FAIL")
        return 1
    }

    private static func runGrantSmoke(arguments: [String]) -> Int {
        let customRoot = projectRoot(from: arguments)
        let root: URL
        let shouldCleanup: Bool
        if let customRoot {
            root = customRoot
            shouldCleanup = false
        } else {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("xt_grant_smoke_\(UUID().uuidString)", isDirectory: true)
            shouldCleanup = true
        }

        defer {
            if shouldCleanup {
                try? FileManager.default.removeItem(at: root)
            }
        }

        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let ctx = AXProjectContext(root: root)
            try ctx.ensureDirs()
            try writeSampleRawLog(to: ctx.rawLogURL)

            let report = ToolExecutor.scanHighRiskGrantBypass(ctx: ctx, maxBytes: 128_000, maxFindings: 20)
            let checks = runSelfChecks(projectRoot: root)
            let checksOK = !checks.isEmpty && checks.allSatisfy(\.ok)
            let bypassOK = report.bypassCount == 1 && report.deniedEvents >= 1

            print("[xt-grant-smoke] project_root=\(root.path)")
            print("[xt-grant-smoke] self_checks=\(checks.filter { $0.ok }.count)/\(checks.count)")
            for item in checks {
                print("- [\(item.ok ? "PASS" : "FAIL")] \(item.name) :: \(item.detail)")
            }
            print(ToolExecutor.formatHighRiskGrantBypassScanReport(report))

            if checksOK && bypassOK {
                print("[xt-grant-smoke] PASS")
                return 0
            }
            print("[xt-grant-smoke] FAIL")
            return 1
        } catch {
            print("[xt-grant-smoke] FAIL: \(error.localizedDescription)")
            return 2
        }
    }

    private static func runSupervisorVoiceSmoke(arguments: [String]) -> Int {
        let customRoot = projectRoot(from: arguments)
        let root: URL
        let shouldCleanup: Bool
        if let customRoot {
            root = customRoot
            shouldCleanup = false
        } else {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("xt_supervisor_voice_smoke_\(UUID().uuidString)", isDirectory: true)
            shouldCleanup = true
        }
        let outputURL = outputJSONURL(
            from: arguments,
            defaultURL: root
                .appendingPathComponent(".axcoder/reports", isDirectory: true)
                .appendingPathComponent("xt_supervisor_voice_smoke.runtime.json")
        )

        defer {
            if shouldCleanup {
                try? FileManager.default.removeItem(at: root)
            }
        }

        var finished = false
        var exitCode = 2
        Task { @MainActor in
            exitCode = await runSupervisorVoiceSmokeScenario(
                workspaceRoot: root,
                outputURL: outputURL
            )
            finished = true
        }

        let deadline = Date().addingTimeInterval(30)
        while !finished && Date() < deadline {
            _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }

        guard finished else {
            print("[xt-supervisor-voice-smoke] FAIL: timed out")
            print("[xt-supervisor-voice-smoke] workspace=\(root.path)")
            print("[xt-supervisor-voice-smoke] output=\(outputURL.path)")
            return 2
        }

        return exitCode
    }

    private static func runSupervisorDoctorRefresh(arguments: [String]) -> Int {
        let root = projectRoot(from: arguments)
            ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)

        let input = SupervisorDoctorChecker.loadDefaultInputBundle(
            workspaceRoot: root,
            env: ProcessInfo.processInfo.environment
        )
        let report = SupervisorDoctorChecker.runAndPersist(input: input)

        print("[xt-supervisor-doctor] workspace=\(root.path)")
        print("[xt-supervisor-doctor] report=\(input.reportURL.path)")
        print("[xt-supervisor-doctor] ok=\(report.ok ? "yes" : "no") blocking=\(report.summary.blockingCount) warning=\(report.summary.warningCount)")

        let blockingCodes = report.findings
            .filter { $0.severity == .blocking }
            .map(\.code)
        if !blockingCodes.isEmpty {
            print("[xt-supervisor-doctor] blocking_codes=\(blockingCodes.joined(separator: ","))")
        }

        return report.ok ? 0 : 1
    }

    private static func runUnifiedDoctorExport(arguments: [String]) -> Int {
        let root = projectRoot(from: arguments)
            ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let sourceURL = XTUnifiedDoctorStore.defaultReportURL(workspaceRoot: root)
        let defaultOutputURL = XHubDoctorOutputStore.defaultXTReportURL(workspaceRoot: root)
        let outputURL = outputJSONURL(from: arguments, defaultURL: defaultOutputURL)

        if sourceURL.standardizedFileURL == outputURL.standardizedFileURL {
            print("[xt-unified-doctor-export] FAIL: output path must differ from source report path")
            print("[xt-unified-doctor-export] source=\(sourceURL.path)")
            print("[xt-unified-doctor-export] output=\(outputURL.path)")
            return 2
        }

        do {
            guard FileManager.default.fileExists(atPath: sourceURL.path) else {
                print("[xt-unified-doctor-export] FAIL: source report missing")
                print("[xt-unified-doctor-export] workspace=\(root.path)")
                print("[xt-unified-doctor-export] source=\(sourceURL.path)")
                return 2
            }

            let sourceReport = try XTUnifiedDoctorStore.loadReport(from: sourceURL)
            let outputReport = XHubDoctorOutputReport.xtReadinessBundle(
                from: sourceReport,
                outputPath: outputURL.path,
                surface: .xtExport
            )
            XHubDoctorOutputStore.writeReport(outputReport, to: outputURL)

            print("[xt-unified-doctor-export] workspace=\(root.path)")
            print("[xt-unified-doctor-export] source=\(sourceURL.path)")
            print("[xt-unified-doctor-export] output=\(outputURL.path)")
            print("[xt-unified-doctor-export] overall_state=\(outputReport.overallState.rawValue) ready_for_first_task=\(outputReport.readyForFirstTask ? "yes" : "no") failed=\(outputReport.summary.failed) warned=\(outputReport.summary.warned)")

            return outputReport.summary.failed == 0 ? 0 : 1
        } catch {
            print("[xt-unified-doctor-export] FAIL: \(error.localizedDescription)")
            if let detail = decodingFailureDetail(error) {
                print("[xt-unified-doctor-export] detail=\(detail)")
            }
            print("[xt-unified-doctor-export] workspace=\(root.path)")
            print("[xt-unified-doctor-export] source=\(sourceURL.path)")
            return 2
        }
    }

    private static func runReleaseEvidenceSmoke(arguments: [String]) -> Int {
        let root = projectRoot(from: arguments)
            ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let reportsDir = root.appendingPathComponent(".axcoder/reports", isDirectory: true)
        let secretsDir = root.appendingPathComponent(".axcoder/secrets", isDirectory: true)
        let runtimeEventsURL = reportsDir.appendingPathComponent("xt_ready_incident_events.runtime.json")
        let secretsPlanURL = secretsDir.appendingPathComponent("secrets_apply_dry_run.json")

        let nowMs = Int64((Date().timeIntervalSince1970 * 1000.0).rounded())
        let eventsPayload: [String: Any] = [
            "run_id": "xt_release_smoke_\(UUID().uuidString.lowercased())",
            "summary": [
                "high_risk_lane_without_grant": 0,
                "unaudited_auto_resolution": 0,
                "high_risk_bypass_count": 0,
                "blocked_event_miss_rate": 0,
                "non_message_ingress_policy_coverage": 1,
            ],
            "events": [
                [
                    "timestamp_ms": nowMs + 100,
                    "event_type": "supervisor.incident.grant_pending.detected",
                    "incident_code": "grant_pending",
                    "lane_id": "lane-2",
                ],
                [
                    "timestamp_ms": nowMs + 1_200,
                    "event_type": "supervisor.incident.grant_pending.handled",
                    "incident_code": "grant_pending",
                    "lane_id": "lane-2",
                    "deny_code": "grant_pending",
                    "audit_event_type": "supervisor.incident.handled",
                    "audit_ref": "audit-smoke-\(UUID().uuidString.lowercased())",
                ],
                [
                    "detected_at_ms": nowMs + 200,
                    "handled_at_ms": nowMs + 900,
                    "event_type": "supervisor.incident.awaiting_instruction.handled",
                    "incident_code": "awaiting_instruction",
                    "lane_id": "lane-3",
                    "deny_code": "awaiting_instruction",
                    "audit_event_type": "supervisor.incident.handled",
                    "audit_ref": "audit-smoke-\(UUID().uuidString.lowercased())",
                ],
                [
                    "timestamp_ms": nowMs + 300,
                    "event_type": "supervisor.incident.runtime_error.detected",
                    "incident_code": "runtime_error",
                    "lane_id": "lane-4",
                ],
                [
                    "timestamp_ms": nowMs + 1_400,
                    "event_type": "supervisor.incident.runtime_error.handled",
                    "incident_code": "runtime_error",
                    "lane_id": "lane-4",
                    "deny_code": "runtime_error",
                    "audit_event_type": "supervisor.incident.handled",
                    "audit_ref": "audit-smoke-\(UUID().uuidString.lowercased())",
                ],
            ],
            "source": [
                "generated_by": "xt_release_evidence_smoke",
                "kind": "synthetic_runtime",
            ],
        ]

        let secretsPlanPayload: [String: Any] = [
            "allowedRoots": [".axcoder/secrets"],
            "allowedModes": ["0600", "0640"],
            "items": [
                [
                    "name": "ws_shared_token",
                    "targetPath": ".axcoder/secrets/ws_shared_token.env",
                    "requiredVariables": ["WS_SHARED_TOKEN"],
                    "providedVariables": ["WS_SHARED_TOKEN"],
                    "mode": "0600",
                ]
            ],
        ]

        do {
            try FileManager.default.createDirectory(at: reportsDir, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: secretsDir, withIntermediateDirectories: true)
            try writeJSONObject(eventsPayload, to: runtimeEventsURL)
            try writeJSONObject(secretsPlanPayload, to: secretsPlanURL)

            print("[xt-release-evidence] workspace=\(root.path)")
            print("[xt-release-evidence] runtime_events=\(runtimeEventsURL.path)")
            print("[xt-release-evidence] secrets_plan=\(secretsPlanURL.path)")
            return 0
        } catch {
            print("[xt-release-evidence] FAIL: \(error.localizedDescription)")
            return 1
        }
    }

    private static func runSplitFlowFixtureSmoke(arguments: [String]) -> Int {
        let root = projectRoot(from: arguments)
            ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let defaultOutputURL = root
            .appendingPathComponent(".axcoder/reports", isDirectory: true)
            .appendingPathComponent("split_flow_snapshot.runtime.json")
        let outputURL = outputJSONURL(from: arguments, defaultURL: defaultOutputURL)

        var finished = false
        var buildResult: Result<[String: Any], Error> = .failure(
            NSError(
                domain: "xt_split_flow_fixture_smoke",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "split flow fixture build did not run"]
            )
        )

        Task { @MainActor in
            buildResult = await buildSplitFlowFixturePayload(projectRoot: root)
            finished = true
        }

        let deadline = Date().addingTimeInterval(20)
        while !finished && Date() < deadline {
            _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }

        guard finished else {
            print("[xt-split-flow-fixture] FAIL: timed out while building snapshot fixture")
            return 2
        }

        do {
            let payload = try buildResult.get()
            try FileManager.default.createDirectory(
                at: outputURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try writeJSONObject(payload, to: outputURL)
            print("[xt-split-flow-fixture] workspace=\(root.path)")
            print("[xt-split-flow-fixture] output=\(outputURL.path)")
            print("[xt-split-flow-fixture] PASS")
            return 0
        } catch {
            print("[xt-split-flow-fixture] FAIL: \(error.localizedDescription)")
            return 1
        }
    }

    @MainActor
    private static func buildSplitFlowFixturePayload(projectRoot: URL) async -> Result<[String: Any], Error> {
        do {
            let primaryRuntimeHost = SplitFlowFixtureRuntimeHost()
            let primaryOrchestrator = SupervisorOrchestrator(runtimeHost: primaryRuntimeHost)

            let proposalResult = await primaryOrchestrator.proposeSplit(
                for: "导出 split flow fixture：提案、覆盖、确认"
            )
            guard proposalResult.validation.hasBlockingIssues == false else {
                throw NSError(
                    domain: "xt_split_flow_fixture_smoke",
                    code: 3,
                    userInfo: [NSLocalizedDescriptionKey: "proposal unexpectedly blocked"]
                )
            }

            let proposedSnapshot = primaryOrchestrator.splitFlowSnapshot()
            guard let laneID = proposalResult.proposal.lanes.first?.laneId else {
                throw NSError(
                    domain: "xt_split_flow_fixture_smoke",
                    code: 4,
                    userInfo: [NSLocalizedDescriptionKey: "proposal has no lanes"]
                )
            }

            guard let overrideResult = primaryOrchestrator.overrideActiveSplitProposal(
                [SplitLaneOverride(laneId: laneID, note: "fixture_override")],
                reason: "fixture_override"
            ) else {
                throw NSError(
                    domain: "xt_split_flow_fixture_smoke",
                    code: 5,
                    userInfo: [NSLocalizedDescriptionKey: "override result missing"]
                )
            }
            guard overrideResult.validation.hasBlockingIssues == false else {
                throw NSError(
                    domain: "xt_split_flow_fixture_smoke",
                    code: 6,
                    userInfo: [NSLocalizedDescriptionKey: "override unexpectedly blocked"]
                )
            }
            let overriddenSnapshot = primaryOrchestrator.splitFlowSnapshot()

            guard let compilation = primaryOrchestrator.confirmActiveSplitProposal(globalContext: "fixture_confirm"),
                  compilation.status == .ready else {
                throw NSError(
                    domain: "xt_split_flow_fixture_smoke",
                    code: 7,
                    userInfo: [NSLocalizedDescriptionKey: "prompt compilation was not ready during confirmation"]
                )
            }
            let confirmedSnapshot = primaryOrchestrator.splitFlowSnapshot()

            let blockedRuntimeHost = SplitFlowFixtureRuntimeHost()
            let blockedOrchestrator = SupervisorOrchestrator(runtimeHost: blockedRuntimeHost)
            _ = await blockedOrchestrator.proposeSplit(for: " ")
            guard let blockedCompilation = blockedOrchestrator.confirmActiveSplitProposal(
                globalContext: "fixture_prompt_blocked"
            ), blockedCompilation.status == .rejected else {
                throw NSError(
                    domain: "xt_split_flow_fixture_smoke",
                    code: 9,
                    userInfo: [NSLocalizedDescriptionKey: "expected prompt lint rejection for blocked snapshot"]
                )
            }
            let blockedSnapshot = blockedOrchestrator.splitFlowSnapshot()

            let snapshotCases: [(String, SplitFlowSnapshot)] = [
                ("proposed_clean", proposedSnapshot),
                ("overridden_with_replay", overriddenSnapshot),
                ("blocked_by_prompt_lint", blockedSnapshot),
                ("confirmed_ready", confirmedSnapshot),
            ]

            for index in 1..<snapshotCases.count {
                let previous = snapshotCases[index - 1].1.flowState
                let current = snapshotCases[index].1.flowState
                guard previous.canTransition(to: current) else {
                    throw NSError(
                        domain: "xt_split_flow_fixture_smoke",
                        code: 10,
                        userInfo: [
                            NSLocalizedDescriptionKey:
                                "state transition not allowed: \(previous.rawValue) -> \(current.rawValue)"
                        ]
                    )
                }
            }

            let snapshotsJSON = try snapshotCases.map { caseID, snapshot in
                [
                    "case_id": caseID,
                    "snapshot": try snapshotJSONObject(snapshot),
                ]
            }

            let payload: [String: Any] = [
                "schema_version": "xterminal.split_flow_snapshot_fixture.v1",
                "generated_at": ISO8601DateFormatter().string(from: Date()),
                "source": [
                    "generated_by": "xt_split_flow_fixture_smoke",
                    "project_root": projectRoot.path,
                ],
                "snapshots": snapshotsJSON,
            ]
            return .success(payload)
        } catch {
            return .failure(error)
        }
    }

    @MainActor
    private final class SplitFlowFixtureRuntimeHost: SupervisorProjectRuntimeHosting {
        var activeProjects: [ProjectModel] = []
        var taskAssignerForRuntime: TaskAssigner?

        func addActiveProjectIfNeeded(_ project: ProjectModel) {
            if !activeProjects.contains(where: { $0.id == project.id }) {
                activeProjects.append(project)
            }
        }

        func onProjectCreated(_ project: ProjectModel) async {
            addActiveProjectIfNeeded(project)
        }

        func onProjectDeleted(_ project: ProjectModel) async {
            activeProjects.removeAll { $0.id == project.id }
        }

        func onProjectStarted(_ project: ProjectModel) async {}
        func onProjectPaused(_ project: ProjectModel) async {}
        func onProjectResumed(_ project: ProjectModel) async {}
        func onProjectCompleted(_ project: ProjectModel) async {}
        func onProjectArchived(_ project: ProjectModel) async {}
        func onProjectExecutionStarted(_ project: ProjectModel, model: ModelInfo) async {}
        func suggestModelUpgrade(for project: ProjectModel) async {}
    }

    private static func projectRoot(from arguments: [String]) -> URL? {
        guard let value = argumentValue(after: projectRootFlag, in: arguments) else {
            return nil
        }
        return URL(
            fileURLWithPath: NSString(string: value).expandingTildeInPath,
            isDirectory: true
        )
    }

    private static func outputJSONURL(from arguments: [String], defaultURL: URL) -> URL {
        guard let value = argumentValue(after: outJSONFlag, in: arguments) else {
            return defaultURL
        }
        return URL(
            fileURLWithPath: NSString(string: value).expandingTildeInPath,
            isDirectory: false
        )
    }

    private static func argumentValue(after flag: String, in arguments: [String]) -> String? {
        guard let idx = arguments.firstIndex(of: flag) else { return nil }
        let next = arguments.index(after: idx)
        guard next < arguments.endIndex else { return nil }
        let value = arguments[next].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        return value
    }

    private static func decodingFailureDetail(_ error: Error) -> String? {
        func joinedCodingPath(_ codingPath: [CodingKey]) -> String {
            let path = codingPath.map(\.stringValue).joined(separator: ".")
            return path.isEmpty ? "(root)" : path
        }

        switch error {
        case let DecodingError.keyNotFound(key, context):
            return "missing_key=\(key.stringValue) path=\(joinedCodingPath(context.codingPath))"
        case let DecodingError.valueNotFound(_, context):
            return "missing_value path=\(joinedCodingPath(context.codingPath))"
        case let DecodingError.typeMismatch(_, context):
            return "type_mismatch path=\(joinedCodingPath(context.codingPath)) \(context.debugDescription)"
        case let DecodingError.dataCorrupted(context):
            return "data_corrupted path=\(joinedCodingPath(context.codingPath)) \(context.debugDescription)"
        default:
            return nil
        }
    }

    private static func runSelfChecks(projectRoot: URL) -> [ToolExecutor.HighRiskGrantSelfCheck] {
        let sema = DispatchSemaphore(value: 0)
        var checks: [ToolExecutor.HighRiskGrantSelfCheck] = []
        Task {
            checks = await ToolExecutor.runHighRiskGrantSelfChecks(projectRoot: projectRoot)
            sema.signal()
        }
        _ = sema.wait(timeout: .now() + 8)
        return checks
    }

    private static func writeSampleRawLog(to rawLogURL: URL) throws {
        let now = Date().timeIntervalSince1970
        let rows: [[String: Any]] = [
            [
                "type": "tool",
                "created_at": now,
                "action": "web_fetch",
                "ok": true,
                "input": ["url": "https://example.com/without_grant"],
                "output": "ok"
            ],
            [
                "type": "tool",
                "created_at": now + 1,
                "action": "web_fetch",
                "ok": false,
                "input": ["url": "https://example.com/denied"],
                "output": "high_risk_denied (code=high_risk_grant_missing, capability=capability_web_fetch)"
            ],
            [
                "type": "tool",
                "created_at": now + 2,
                "action": "web_fetch",
                "ok": true,
                "input": ["url": "https://example.com/with_grant", "grant_id": "grant_demo_smoke"],
                "output": "ok"
            ],
        ]

        var lines: [String] = []
        lines.reserveCapacity(rows.count)
        for row in rows {
            let data = try JSONSerialization.data(withJSONObject: row, options: [])
            if let line = String(data: data, encoding: .utf8) {
                lines.append(line)
            }
        }
        let body = lines.joined(separator: "\n") + "\n"
        guard let data = body.data(using: .utf8) else {
            throw NSError(
                domain: "xt_grant_smoke",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "utf8 encode failed for smoke log"]
            )
        }
        try data.write(to: rawLogURL, options: .atomic)
    }

    private static func writeJSONObject(_ payload: Any, to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
    }

    @MainActor
    private static func runSupervisorVoiceSmokeScenario(
        workspaceRoot: URL,
        outputURL: URL
    ) async -> Int {
        let projectRoot = workspaceRoot
            .appendingPathComponent("voice_supervisor_smoke_project", isDirectory: true)
        var spoken: [String] = []
        var checks: [[String: Any]] = []

        func appendCheck(_ id: String, _ passed: Bool, _ detail: String) {
            checks.append([
                "id": id,
                "passed": passed,
                "detail": detail
            ])
            let status = passed ? "PASS" : "FAIL"
            print("[xt-supervisor-voice-smoke] \(status) \(id) :: \(detail)")
        }

        do {
            try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
            let ctx = AXProjectContext(root: projectRoot)
            try ctx.ensureDirs()

            let project = makeSupervisorVoiceSmokeProjectEntry(root: projectRoot, displayName: "Release Runtime")
            let grant = makeSupervisorVoiceSmokePendingGrant(project: project)
            let approveProbe = SupervisorVoiceSmokeApproveProbe()
            let briefProbe = SupervisorVoiceSmokeBriefProbe()
            let transcriber = SupervisorVoiceSmokeMockTranscriber(routeMode: .funasrStreaming)
            let synthesizer = SupervisorSpeechSynthesizer(
                deduper: SupervisorVoiceBriefDeduper(cooldown: 0),
                speakSink: { spoken.append($0) }
            )
            let controller = SupervisorConversationSessionController.makeForTesting(
                route: .funasrStreaming,
                wakeMode: .wakePhrase,
                nowProvider: Date.init
            )
            let voiceCoordinator = VoiceSessionCoordinator(
                transcriber: transcriber,
                preferences: .default()
            )
            let manager = SupervisorManager.makeForTesting(
                supervisorSpeechSynthesizer: synthesizer,
                conversationSessionController: controller,
                voiceSessionCoordinator: voiceCoordinator
            )
            manager.resetVoiceAuthorizationState()
            manager.clearMessages()
            defer {
                manager.endConversationSession(reasonCode: "voice_smoke_cleanup")
                voiceCoordinator.discardRecording(reasonCode: "voice_smoke_cleanup")
                manager.resetVoiceAuthorizationState()
            }

            let appModel = AppModel()
            var settings = appModel.settingsStore.settings
            settings.voice.wakeMode = .wakePhrase
            settings.voice.preferredRoute = .funasrStreaming
            appModel.settingsStore.settings = settings

            var registry = AXProjectRegistry.empty()
            registry.projects = [project]
            registry.lastSelectedProjectId = project.projectId
            appModel.registry = registry
            appModel.selectedProjectId = project.projectId
            manager.setAppModel(appModel)

            let now = Date()
            let nowMs = now.timeIntervalSince1970 * 1000.0
            manager.setConnectorIngressSnapshotForTesting(
                HubIPCClient.ConnectorIngressSnapshot(
                    source: "xt_supervisor_voice_smoke",
                    updatedAtMs: nowMs,
                    items: [
                        HubIPCClient.ConnectorIngressReceipt(
                            receiptId: "voice-smoke-receipt",
                            requestId: "voice-smoke-request",
                            projectId: project.projectId,
                            connector: "slack",
                            targetId: "dm-release-runtime",
                            ingressType: "connector_event",
                            channelScope: "dm",
                            sourceId: "user-release-runtime",
                            messageId: "voice-smoke-message",
                            dedupeKey: "sha256:xt-supervisor-voice-smoke",
                            receivedAtMs: nowMs - 5_000,
                            eventSequence: 1,
                            deliveryState: "accepted",
                            runtimeState: "queued"
                        )
                    ]
                ),
                now: now
            )
            manager.setPendingHubGrantsForTesting([grant], now: now)
            manager.installSchedulerSnapshotRefreshOverrideForTesting { _ in }
            manager.installPendingHubGrantApproveOverrideForTesting { grantRequestId, projectId, requestedTtlSec, requestedTokenCap, note in
                await approveProbe.record(
                    grantRequestId: grantRequestId,
                    projectId: projectId,
                    requestedTtlSec: requestedTtlSec,
                    requestedTokenCap: requestedTokenCap,
                    note: note
                )
                return HubIPCClient.PendingGrantActionResult(
                    ok: true,
                    decision: .approved,
                    source: "xt_supervisor_voice_smoke",
                    grantRequestId: grantRequestId,
                    grantId: grantRequestId,
                    expiresAtMs: (Date().timeIntervalSince1970 + 900) * 1000.0,
                    reasonCode: nil
                )
            }
            manager.installSupervisorBriefProjectionFetcherForTesting { payload in
                await briefProbe.record(payload)
                return HubIPCClient.SupervisorBriefProjectionResult(
                    ok: true,
                    source: "xt_supervisor_voice_smoke",
                    projection: makeSupervisorVoiceSmokeBriefProjection(
                        projectId: payload.projectId,
                        trigger: payload.trigger
                    ),
                    reasonCode: nil
                )
            }
            manager.installVoiceAuthorizationBridgeForTesting(
                SupervisorVoiceAuthorizationBridge(
                    issueHandler: { payload in
                        HubIPCClient.VoiceGrantChallengeResult(
                            ok: true,
                            source: "xt_supervisor_voice_smoke",
                            challenge: makeSupervisorVoiceSmokeChallenge(payload: payload),
                            reasonCode: nil
                        )
                    },
                    verifyHandler: { payload in
                        HubIPCClient.VoiceGrantVerificationResult(
                            ok: true,
                            verified: true,
                            decision: .allow,
                            source: "xt_supervisor_voice_smoke",
                            denyCode: nil,
                            challengeId: payload.challengeId,
                            transcriptHash: "sha256:xt-supervisor-voice-smoke",
                            semanticMatchScore: payload.semanticMatchScore ?? 0.99,
                            challengeMatch: true,
                            deviceBindingOK: true,
                            mobileConfirmed: payload.mobileConfirmed,
                            reasonCode: nil
                        )
                    }
                )
            )

            let wakeArmedReady = await waitForSupervisorVoiceSmoke(timeoutSec: 8) {
                manager.conversationSessionSnapshot.windowState == .armed &&
                    voiceCoordinator.isRecording &&
                    voiceCoordinator.currentCaptureSource == .wakeArmed
            }
            appendCheck(
                "wake_armed_ready",
                wakeArmedReady,
                "window=\(manager.conversationSessionSnapshot.windowState.rawValue) capture=\(voiceCoordinator.currentCaptureSource?.rawValue ?? "none")"
            )

            if wakeArmedReady {
                transcriber.emit(.init(kind: .partial, text: "supervisor", isWakeMatch: true))
                transcriber.emit(.init(kind: .final, text: "supervisor"))
            }

            let wakePromptSpoken = await waitForSupervisorVoiceSmoke(timeoutSec: 8) {
                spoken.contains { $0.contains("我在，继续说") }
            }
            appendCheck(
                "wake_prompt_spoken",
                wakePromptSpoken,
                wakePromptSpoken ? "wake follow-up prompt delivered" : "spoken_count=\(spoken.count)"
            )

            let talkLoopAfterWakePrompt = await waitForSupervisorVoiceSmoke(timeoutSec: 8) {
                voiceCoordinator.isRecording &&
                    voiceCoordinator.currentCaptureSource == .talkLoop &&
                    voiceCoordinator.runtimeState.reasonCode == "talk_loop_resumed"
            }
            appendCheck(
                "wake_prompt_resumed_listening",
                talkLoopAfterWakePrompt,
                "starts=\(transcriber.startCount) capture=\(voiceCoordinator.currentCaptureSource?.rawValue ?? "none")"
            )

            if talkLoopAfterWakePrompt {
                transcriber.emit(.init(kind: .final, text: "批准这个 release grant"))
            }

            let challengeIssued = await waitForSupervisorVoiceSmoke(timeoutSec: 8) {
                manager.voiceAuthorizationResolution?.state == .escalatedToMobile &&
                    manager.activeVoiceChallenge?.challengeId == "voice_chal_xt_supervisor_voice_smoke"
            }
            appendCheck(
                "voice_grant_challenge_issued",
                challengeIssued,
                "state=\(manager.voiceAuthorizationResolution?.state.rawValue ?? "none")"
            )

            let talkLoopAfterGrantPrompt = await waitForSupervisorVoiceSmoke(timeoutSec: 8) {
                voiceCoordinator.isRecording &&
                    voiceCoordinator.currentCaptureSource == .talkLoop &&
                    manager.recentEventsForTesting().contains(where: {
                        $0.contains("voice talk loop resumed: pending_grant_voice_reply")
                    })
            }
            appendCheck(
                "grant_prompt_resumed_listening",
                talkLoopAfterGrantPrompt,
                "starts=\(transcriber.startCount) challenge_active=\(manager.activeVoiceChallenge != nil)"
            )

            if talkLoopAfterGrantPrompt {
                transcriber.emit(.init(kind: .final, text: "手机已确认，现在批准 release grant"))
            }

            let grantApproved = await waitForSupervisorVoiceSmoke(timeoutSec: 10) {
                manager.pendingHubGrants.isEmpty &&
                    manager.activeVoiceChallenge == nil &&
                    manager.messages.contains(where: {
                        $0.role == .assistant && $0.content.contains("🧭 Supervisor Brief")
                    })
            }
            appendCheck(
                "grant_approved_and_brief_emitted",
                grantApproved,
                "pending_grants=\(manager.pendingHubGrants.count) challenge_active=\(manager.activeVoiceChallenge != nil)"
            )

            let talkLoopAfterBrief = await waitForSupervisorVoiceSmoke(timeoutSec: 8) {
                voiceCoordinator.isRecording &&
                    voiceCoordinator.currentCaptureSource == .talkLoop &&
                    manager.recentEventsForTesting().contains(where: {
                        $0.contains("voice talk loop resumed: pending_grant_follow_up")
                    })
            }
            appendCheck(
                "brief_resumed_listening",
                talkLoopAfterBrief,
                "starts=\(transcriber.startCount) capture=\(voiceCoordinator.currentCaptureSource?.rawValue ?? "none")"
            )

            let approveCall = await approveProbe.first()
            let briefCall = await briefProbe.first()
            appendCheck(
                "approve_callback_recorded",
                approveCall?.grantRequestId == grant.grantRequestId,
                "grant_request_id=\(approveCall?.grantRequestId ?? "none")"
            )
            appendCheck(
                "brief_projection_callback_recorded",
                briefCall?.projectId == project.projectId,
                "project_id=\(briefCall?.projectId ?? "none")"
            )

            let report: [String: Any] = [
                "schema_version": "xt.supervisor_voice_smoke.v1",
                "generated_at": ISO8601DateFormatter().string(from: Date()),
                "workspace_root": workspaceRoot.path,
                "project_root": projectRoot.path,
                "output_path": outputURL.path,
                "checks": checks,
                "spoken": spoken,
                "recent_events": manager.recentEventsForTesting(),
                "transcriber_start_count": transcriber.startCount,
                "message_count": manager.messages.count,
                "voice_route": voiceCoordinator.routeDecision.route.rawValue,
                "final_capture_source": voiceCoordinator.currentCaptureSource?.rawValue ?? "none",
                "final_window_state": manager.conversationSessionSnapshot.windowState.rawValue,
                "approve_call": [
                    "grant_request_id": approveCall?.grantRequestId ?? "",
                    "project_id": approveCall?.projectId ?? "",
                    "requested_ttl_sec": approveCall?.requestedTtlSec as Any,
                    "requested_token_cap": approveCall?.requestedTokenCap as Any,
                    "note": approveCall?.note ?? ""
                ],
                "brief_request": [
                    "project_id": briefCall?.projectId ?? "",
                    "trigger": briefCall?.trigger ?? "",
                    "projection_kind": briefCall?.projectionKind ?? ""
                ]
            ]

            try FileManager.default.createDirectory(
                at: outputURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try writeJSONObject(report, to: outputURL)

            let passedCount = checks.filter { ($0["passed"] as? Bool) == true }.count
            print("[xt-supervisor-voice-smoke] workspace=\(workspaceRoot.path)")
            print("[xt-supervisor-voice-smoke] output=\(outputURL.path)")
            print("[xt-supervisor-voice-smoke] checks=\(passedCount)/\(checks.count)")

            if checks.allSatisfy({ ($0["passed"] as? Bool) == true }) {
                print("[xt-supervisor-voice-smoke] PASS")
                return 0
            }

            print("[xt-supervisor-voice-smoke] FAIL")
            return 1
        } catch {
            let report: [String: Any] = [
                "schema_version": "xt.supervisor_voice_smoke.v1",
                "generated_at": ISO8601DateFormatter().string(from: Date()),
                "workspace_root": workspaceRoot.path,
                "output_path": outputURL.path,
                "error": error.localizedDescription,
                "checks": checks,
                "spoken": spoken
            ]
            try? FileManager.default.createDirectory(
                at: outputURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? writeJSONObject(report, to: outputURL)
            print("[xt-supervisor-voice-smoke] workspace=\(workspaceRoot.path)")
            print("[xt-supervisor-voice-smoke] output=\(outputURL.path)")
            print("[xt-supervisor-voice-smoke] FAIL: \(error.localizedDescription)")
            return 2
        }
    }

    private static func snapshotJSONObject(_ snapshot: SplitFlowSnapshot) throws -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(snapshot)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(
                domain: "xt_split_flow_fixture_smoke",
                code: 11,
                userInfo: [NSLocalizedDescriptionKey: "failed to serialize SplitFlowSnapshot as JSON object"]
            )
        }
        return json
    }

    @MainActor
    private static func waitForSupervisorVoiceSmoke(
        timeoutSec: TimeInterval,
        pollMs: UInt64 = 50,
        condition: @escaping @MainActor () -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeoutSec)
        while Date() < deadline {
            if condition() {
                return true
            }
            try? await Task.sleep(nanoseconds: pollMs * 1_000_000)
        }
        return condition()
    }

    private static func makeSupervisorVoiceSmokeProjectEntry(
        root: URL,
        displayName: String
    ) -> AXProjectEntry {
        AXProjectEntry(
            projectId: "project_xt_supervisor_voice_smoke",
            rootPath: root.path,
            displayName: displayName,
            lastOpenedAt: Date().timeIntervalSince1970,
            manualOrderIndex: 0,
            pinned: false,
            statusDigest: "grant_pending",
            currentStateSummary: "等待高风险 Hub grant 授权。",
            nextStepSummary: "语音批准 release grant。",
            blockerSummary: "Pending Hub grant blocks release pipeline.",
            lastSummaryAt: nil,
            lastEventAt: nil
        )
    }

    private static func makeSupervisorVoiceSmokePendingGrant(
        project: AXProjectEntry
    ) -> SupervisorManager.SupervisorPendingGrant {
        SupervisorManager.SupervisorPendingGrant(
            id: "pending_grant_xt_supervisor_voice_smoke",
            dedupeKey: "xt-supervisor-voice-smoke-grant",
            grantRequestId: "grant_xt_supervisor_voice_smoke",
            requestId: "request_xt_supervisor_voice_smoke",
            projectId: project.projectId,
            projectName: project.displayName,
            capability: "web.fetch",
            modelId: "",
            reason: "release production deploy",
            requestedTtlSec: 900,
            requestedTokenCap: 0,
            createdAt: Date().timeIntervalSince1970,
            actionURL: "xterminal://pending-grants/grant_xt_supervisor_voice_smoke",
            priorityRank: 1,
            priorityReason: "production_release_blocked",
            nextAction: "Approve the release runtime Hub grant."
        )
    }

    private static func makeSupervisorVoiceSmokeChallenge(
        payload: HubIPCClient.VoiceGrantChallengeRequestPayload
    ) -> HubIPCClient.VoiceGrantChallengeSnapshot {
        let nowMs = Date().timeIntervalSince1970 * 1000.0
        return HubIPCClient.VoiceGrantChallengeSnapshot(
            challengeId: "voice_chal_xt_supervisor_voice_smoke",
            templateId: payload.templateId,
            actionDigest: payload.actionDigest,
            scopeDigest: payload.scopeDigest,
            amountDigest: payload.amountDigest ?? "",
            challengeCode: "773312",
            riskLevel: payload.riskLevel,
            requiresMobileConfirm: true,
            allowVoiceOnly: false,
            boundDeviceId: payload.boundDeviceId ?? "",
            mobileTerminalId: payload.mobileTerminalId ?? "",
            issuedAtMs: nowMs,
            expiresAtMs: nowMs + 180_000
        )
    }

    private static func makeSupervisorVoiceSmokeBriefProjection(
        projectId: String,
        trigger: String
    ) -> HubIPCClient.SupervisorBriefProjectionSnapshot {
        let nowMs = Date().timeIntervalSince1970 * 1000.0
        return HubIPCClient.SupervisorBriefProjectionSnapshot(
            schemaVersion: "hub.supervisor_brief_projection.v1",
            projectionId: "brief_xt_supervisor_voice_smoke",
            projectionKind: "progress_brief",
            projectId: projectId,
            runId: "run_xt_supervisor_voice_smoke",
            missionId: "mission_xt_supervisor_voice_smoke",
            trigger: trigger,
            status: "ok",
            criticalBlocker: "",
            topline: "发布路径已恢复。",
            nextBestAction: "恢复 release pipeline。",
            pendingGrantCount: 0,
            ttsScript: [
                "Supervisor Hub 简报。发布路径已恢复。",
                "建议下一步：恢复 release pipeline。"
            ],
            cardSummary: "发布路径已恢复。下一步：恢复 release pipeline。",
            evidenceRefs: ["audit-xt-supervisor-voice-smoke"],
            generatedAtMs: nowMs,
            expiresAtMs: nowMs + 60_000,
            auditRef: "audit-xt-supervisor-voice-smoke"
        )
    }

    private actor SupervisorVoiceSmokeApproveProbe {
        private var payloads: [(grantRequestId: String, projectId: String?, requestedTtlSec: Int?, requestedTokenCap: Int?, note: String)] = []

        func record(
            grantRequestId: String,
            projectId: String?,
            requestedTtlSec: Int?,
            requestedTokenCap: Int?,
            note: String
        ) {
            payloads.append(
                (
                    grantRequestId: grantRequestId,
                    projectId: projectId,
                    requestedTtlSec: requestedTtlSec,
                    requestedTokenCap: requestedTokenCap,
                    note: note
                )
            )
        }

        func first() -> (grantRequestId: String, projectId: String?, requestedTtlSec: Int?, requestedTokenCap: Int?, note: String)? {
            payloads.first
        }
    }

    private actor SupervisorVoiceSmokeBriefProbe {
        private var payloads: [HubIPCClient.SupervisorBriefProjectionRequestPayload] = []

        func record(_ payload: HubIPCClient.SupervisorBriefProjectionRequestPayload) {
            payloads.append(payload)
        }

        func first() -> HubIPCClient.SupervisorBriefProjectionRequestPayload? {
            payloads.first
        }
    }

    @MainActor
    private final class SupervisorVoiceSmokeMockTranscriber: VoiceStreamingTranscriber {
        let routeMode: VoiceRouteMode
        private(set) var authorizationStatus: VoiceTranscriberAuthorizationStatus
        private(set) var engineHealth: VoiceEngineHealth
        private(set) var healthReasonCode: String?
        private(set) var isRunning: Bool = false
        private(set) var startCount: Int = 0

        private var onChunk: ((VoiceTranscriptChunk) -> Void)?
        private var onFailure: ((String) -> Void)?

        init(
            routeMode: VoiceRouteMode,
            authorizationStatus: VoiceTranscriberAuthorizationStatus = .authorized,
            engineHealth: VoiceEngineHealth = .ready,
            healthReasonCode: String? = nil
        ) {
            self.routeMode = routeMode
            self.authorizationStatus = authorizationStatus
            self.engineHealth = engineHealth
            self.healthReasonCode = healthReasonCode
        }

        func requestAuthorization() async -> VoiceTranscriberAuthorizationStatus {
            authorizationStatus
        }

        func refreshEngineHealth() async -> VoiceEngineHealth {
            engineHealth
        }

        func startTranscribing(
            onChunk: @escaping (VoiceTranscriptChunk) -> Void,
            onFailure: @escaping (String) -> Void
        ) throws {
            guard authorizationStatus.isAuthorized else {
                throw VoiceTranscriberError.notAuthorized
            }
            startCount += 1
            isRunning = true
            self.onChunk = onChunk
            self.onFailure = onFailure
        }

        func stopTranscribing() {
            isRunning = false
        }

        func emit(_ chunk: VoiceTranscriptChunk) {
            guard isRunning else { return }
            onChunk?(chunk)
        }

        func fail(_ reason: String) {
            guard isRunning else { return }
            onFailure?(reason)
        }
    }
}
