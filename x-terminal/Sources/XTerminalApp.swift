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
        }
        
        Window("Supervisor AI", id: "supervisor") {
            SupervisorView()
                .environmentObject(appModel)
        }
        
        Window("Supervisor 设置", id: "supervisor_settings") {
            SupervisorSettingsView()
                .environmentObject(appModel)
        }
        
        Window("AI 模型设置", id: "model_settings") {
            ModelSettingsView()
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
                Button("Open .xterminal Folder") {
                    if let ctx = appModel.projectContext {
                        NSWorkspace.shared.open(ctx.xterminalDir)
                    }
                }
                .disabled(appModel.projectContext == nil)

                Button("Open AX_MEMORY.md") {
                    if let ctx = appModel.projectContext {
                        NSWorkspace.shared.open(ctx.memoryMarkdownURL)
                    }
                }
                .disabled(appModel.projectContext == nil)

                Button("Open ax_memory.json") {
                    if let ctx = appModel.projectContext {
                        NSWorkspace.shared.open(ctx.memoryJSONURL)
                    }
                }
                .disabled(appModel.projectContext == nil)

                Button("Open config.json") {
                    if let ctx = appModel.projectContext {
                        NSWorkspace.shared.open(ctx.configURL)
                    }
                }
                .disabled(appModel.projectContext == nil)

                Button("Open raw_log.jsonl") {
                    if let ctx = appModel.projectContext {
                        NSWorkspace.shared.open(ctx.rawLogURL)
                    }
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
    func applicationDidFinishLaunching(_ notification: Notification) {
        if XTerminalGateSmokeRunner.isSmokeInvocation(arguments: CommandLine.arguments) {
            return
        }
        // When launched via `swift run`, make sure the app is a regular foreground app
        // so keyboard events are routed to text inputs correctly.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

enum XTerminalGateSmokeRunner {
    static let grantSmokeFlag = "--xt-grant-smoke"
    static let supervisorDoctorRefreshFlag = "--xt-supervisor-doctor-refresh"
    static let releaseEvidenceSmokeFlag = "--xt-release-evidence-smoke"
    static let splitFlowFixtureSmokeFlag = "--xt-split-flow-fixture-smoke"
    static let projectRootFlag = "--project-root"
    static let outJSONFlag = "--out-json"

    static func isSmokeInvocation(arguments: [String]) -> Bool {
        arguments.contains(grantSmokeFlag)
            || arguments.contains(supervisorDoctorRefreshFlag)
            || arguments.contains(releaseEvidenceSmokeFlag)
            || arguments.contains(splitFlowFixtureSmokeFlag)
    }

    static func runIfRequested(arguments: [String]) -> Int? {
        if arguments.contains(grantSmokeFlag) {
            return runGrantSmoke(arguments: arguments)
        }
        if arguments.contains(supervisorDoctorRefreshFlag) {
            return runSupervisorDoctorRefresh(arguments: arguments)
        }
        if arguments.contains(releaseEvidenceSmokeFlag) {
            return runReleaseEvidenceSmoke(arguments: arguments)
        }
        if arguments.contains(splitFlowFixtureSmokeFlag) {
            return runSplitFlowFixtureSmoke(arguments: arguments)
        }
        return nil
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
            let primarySupervisor = SupervisorModel()
            guard let primaryOrchestrator = primarySupervisor.orchestrator else {
                throw NSError(
                    domain: "xt_split_flow_fixture_smoke",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "primary orchestrator unavailable"]
                )
            }

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

            let blockedSupervisor = SupervisorModel()
            guard let blockedOrchestrator = blockedSupervisor.orchestrator else {
                throw NSError(
                    domain: "xt_split_flow_fixture_smoke",
                    code: 8,
                    userInfo: [NSLocalizedDescriptionKey: "blocked orchestrator unavailable"]
                )
            }
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
}
