import SwiftUI
import AppKit
import RELFlowHubCore

struct SettingsSheetView: View {
    @EnvironmentObject var store: HubStore
    @Environment(\.dismiss) private var dismiss

    @ObservedObject private var grpc = HubGRPCServerSupport.shared

    @State private var didAutoRequestCalendarOnOpen = false
    @State private var remoteModels: [RemoteModelEntry] = RemoteModelStorage.load().models
    @State private var showAddRemoteModel: Bool = false
    @State private var showImportOpencodeZen: Bool = false
    @State private var networkPolicies: [HubNetworkPolicyRule] = HubNetworkPolicyStorage.load().policies
    @State private var showAddNetworkPolicy: Bool = false
    @State private var showAddGRPCClient: Bool = false
    @State private var editingGRPCClient: HubGRPCClientEntry? = nil
    @State private var grpcDevicesStatus: GRPCDevicesStatusSnapshot = GRPCDevicesStatusStorage.load()
    @State private var grpcDeniedAttempts: GRPCDeniedAttemptsSnapshot = GRPCDeniedAttemptsStorage.load()
    @State private var hubLaunchStatus: HubLaunchStatusSnapshot? = HubLaunchStatusStorage.load()
    @State private var hubLaunchHistory: HubLaunchHistorySnapshot = HubLaunchHistoryStorage.load()
    @State private var diagnosticsBundleIsExporting: Bool = false
    @State private var diagnosticsBundleArchivePath: String = ""
    @State private var diagnosticsBundleManifestPath: String = ""
    @State private var diagnosticsBundleMissingFiles: [String] = []
    @State private var diagnosticsBundleError: String = ""
    @State private var fixNowIsRunning: Bool = false
    @State private var fixNowResultText: String = ""
    @State private var fixNowErrorText: String = ""
    @State private var diagnosticsActionIsRunning: Bool = false
    @State private var diagnosticsActionResultText: String = ""
    @State private var diagnosticsActionErrorText: String = ""

    @State private var skillsIndex: HubSkillsStoreStorage.SkillsIndexSnapshot = HubSkillsStoreStorage.loadSkillsIndex()
    @State private var skillsPins: HubSkillsStoreStorage.SkillPinsSnapshot = HubSkillsStoreStorage.loadSkillPins()
    @State private var skillsSources: HubSkillsStoreStorage.SkillSourcesSnapshot = HubSkillsStoreStorage.loadSkillSources()
    @State private var skillsSearchQuery: String = ""
    @State private var skillsResolveUserId: String = ""
    @State private var skillsResolveProjectId: String = ""
    @State private var skillsLastActionText: String = ""
    @State private var skillsLastErrorText: String = ""
    @State private var axConstitutionVersion: String = ""
    @State private var axConstitutionEnabledClauseIds: [String] = []
    @State private var axConstitutionErrorText: String = ""

    private var axTrusted: Bool {
        DockBadgeReader.ensureAccessibilityTrusted(prompt: false)
    }

    private var calendarHasReadAccess: Bool {
        store.calendarHasReadAccess
    }

    private func quitApp() {
        // Some LSUIElement apps can get into a state where `terminate` is ignored.
        // Use forceTerminate as a fallback so users don't need Terminal.
        let app = NSRunningApplication.current
        // Stop the AI runtime so upgrades don't inherit a stale long-lived worker.
        store.stopAIRuntime()
        dismiss()
        NSApp.terminate(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            if !app.isTerminated {
                _ = app.forceTerminate()
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            formContent
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(width: 620, height: 640)
        .onReceive(Timer.publish(every: 2.0, on: .main, in: .common).autoconnect()) { _ in
            // Lightweight status snapshot exported by Node server for device presence/quotas.
            grpcDevicesStatus = GRPCDevicesStatusStorage.load()
            grpcDeniedAttempts = GRPCDeniedAttemptsStorage.load()
            hubLaunchStatus = HubLaunchStatusStorage.load()
            hubLaunchHistory = HubLaunchHistoryStorage.load()
            skillsIndex = HubSkillsStoreStorage.loadSkillsIndex()
            skillsPins = HubSkillsStoreStorage.loadSkillPins()
            skillsSources = HubSkillsStoreStorage.loadSkillSources()
            reloadAXConstitutionStatus()
        }
        .sheet(isPresented: $showAddRemoteModel) {
            AddRemoteModelSheet { entries in
                upsertRemoteModels(entries)
            }
        }
        .sheet(isPresented: $showImportOpencodeZen) {
            ImportOpencodeZenSheet { result in
                importOpencodeZen(result)
            }
        }
        .sheet(isPresented: $showAddNetworkPolicy) {
            AddNetworkPolicySheet { rule in
                _ = HubNetworkPolicyStorage.upsert(rule)
                reloadNetworkPolicies()
            }
        }
        .sheet(isPresented: $showAddGRPCClient) {
            AddGRPCClientSheet { deviceName in
                let entry = grpc.createClient(name: deviceName)
                grpc.copyConnectVars(for: entry)
            }
        }
        .sheet(item: $editingGRPCClient) { client in
            EditGRPCClientSheet(
                client: client,
                serverPort: grpc.port,
                onSave: { updated in
                    grpc.upsertClient(updated)
                },
                onRotateToken: { deviceId in
                    grpc.rotateClientToken(deviceId: deviceId)
                },
                onCopyVars: { tok in
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(grpc.connectionGuideOverride(token: tok, deviceId: client.deviceId), forType: .string)
                }
            )
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("REL Flow Hub Settings")
                        .font(.headline)
                    Text("Pairing · Models · Grants · Security · Diagnostics")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }
            }
            Text("validated-mainline-only · pairing → model → grant → smoke")
                .font(.caption.monospaced())
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.secondary.opacity(0.12))
                .clipShape(Capsule())
        }
    }

    @ViewBuilder
    private var formContent: some View {
        Form {
            setupCenterSection
            firstRunFastPathSection
            quickTroubleshootSection
            grpcServerSection
            routingSection
            remoteModelsSection
            doctorSection
            diagnosticsSection
            networkPoliciesSection
            networkingSection
            integrationsSection
            floatingModeSection
            skillsSection
            advancedSection
            quitSection
        }
        .formStyle(.grouped)
        .task {
            // If the user has Calendar integration ON but hasn't granted permission yet,
            // attempt to trigger the system prompt once when opening Settings.
            if didAutoRequestCalendarOnOpen { return }
            if store.integrationCalendarEnabled, store.calendarNotDetermined {
                didAutoRequestCalendarOnOpen = true
                NSApp.activate(ignoringOtherApps: true)
                store.requestCalendarAccessAndStart()
            }
        }
        .onAppear {
            remoteModels = RemoteModelStorage.load().models
            reloadNetworkPolicies()
            reloadAXConstitutionStatus()
        }
    }

    private var setupCenterSection: some View {
        Section("Setup Center") {
            HubSectionCard(
                systemImage: "link.badge.plus",
                title: "Pair Hub",
                summary: "把 XT 设备配对、copy bootstrap、客户端 token 与 reachability 放在一条主链。",
                badge: grpc.isRunning ? "ready" : "needs start",
                highlights: [
                    "\(grpc.allowedClients.count) allowed clients",
                    "pairing port \(grpc.xtTerminalPairingPort)",
                    grpc.statusText
                ]
            )

            HubSectionCard(
                systemImage: "cpu",
                title: "Models & Paid Access",
                summary: "先决定 local / paid 模型，再把 paid access 的 quota / key 状态与路由放在一起看。",
                badge: activeRemoteModelCount > 0 ? "\(activeRemoteModelCount) enabled" : "local only",
                highlights: [
                    "Hub routing remains source-of-truth",
                    "remote models can be toggled without leaving this sheet",
                    "quota review stays next to model setup"
                ]
            )

            HubSectionCard(
                systemImage: "checkmark.shield",
                title: "Grants & Permissions",
                summary: "设备 capability、denied attempts、系统权限与 paid model 入口统一在这里对齐。",
                badge: grpcDeniedAttempts.attempts.isEmpty ? "clear" : "\(grpcDeniedAttempts.attempts.count) blocked",
                highlights: [
                    "Calendar / Accessibility repair stays close to grants",
                    "denied attempts can jump to client edit or quotas",
                    "permission issues stay within 3 repair steps"
                ]
            )

            HubSectionCard(
                systemImage: "lock.shield",
                title: "Security Boundary",
                summary: "Network policy、allowed CIDRs、capabilities 与 fail-closed defaults 不再散落在多个区域。",
                badge: networkPolicies.isEmpty ? "default" : "\(networkPolicies.count) rules",
                highlights: [
                    "bridge remains governed by explicit grant windows",
                    "client capabilities stay device-scoped",
                    "security changes remain auditable"
                ]
            )

            HubSectionCard(
                systemImage: "stethoscope",
                title: "Diagnostics & Recovery",
                summary: "启动状态、Fix Now、导出 bundle、日志与历史都围绕 recovery 收口。",
                badge: currentLaunchStateLabel,
                highlights: [
                    "Fix Now stays next to launch root cause",
                    "logs and history remain one hop away",
                    "redacted export keeps QA / support handoff short"
                ]
            )
        }
    }

    private var firstRunFastPathSection: some View {
        Section("First Run Path") {
            VStack(alignment: .leading, spacing: 10) {
                Text("冻结主链：pair XT device → choose model → resolve grant → run smoke")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                firstRunStepRow(
                    index: 1,
                    title: "Pair XT device",
                    summary: "创建或编辑 gRPC client，并把 bootstrap/copy-vars 交给 XT。"
                ) {
                    Button("Copy Bootstrap Cmd") { grpc.copyBootstrapCommandToClipboard() }
                    Button("Add Client…") { showAddGRPCClient = true }
                    Button("Refresh") { grpc.refresh() }
                }

                firstRunStepRow(
                    index: 2,
                    title: "Choose model",
                    summary: "先把 Hub routing 与 paid models 定到位，避免首用时在多个地方猜测。"
                ) {
                    Button("Add Paid Model…") { showAddRemoteModel = true }
                    Button("Open Quotas") { grpc.openQuotaConfig() }
                }

                firstRunStepRow(
                    index: 3,
                    title: "Resolve grant / permission",
                    summary: "设备 capability、denied attempts、系统权限入口都不超过 3 步。"
                ) {
                    if let preferredClientForRepair {
                        Button("Edit Device") { editingGRPCClient = preferredClientForRepair }
                    } else {
                        Button("Open Clients") { grpc.openClientsConfig() }
                    }
                    Button("Open Accessibility") { SystemSettingsLinks.openAccessibilityPrivacy() }
                    Button("Open Quotas") { grpc.openQuotaConfig() }
                }

                firstRunStepRow(
                    index: 4,
                    title: "Run smoke",
                    summary: "先看 launch status，再用 Fix Now / log / refresh 把 reachability 收敛。"
                ) {
                    Button("Fix Now") { fixNow(snapshot: hubLaunchStatus) }
                    Button("Open Log") { grpc.openLog() }
                    Button("Refresh") { grpc.refresh() }
                }
            }
        }
    }

    private var quickTroubleshootSection: some View {
        Section("Troubleshoot In 3 Steps") {
            VStack(alignment: .leading, spacing: 10) {
                quickFixCard(
                    title: "grant_required",
                    summary: "付费模型或受控能力未放行时，直接回到模型 / quota / capability 三处修复。",
                    steps: [
                        "1. Hub Settings → Models & Paid Access",
                        "2. Hub Settings → Grants & Permissions / Open Quotas",
                        "3. Retry from First Run Path"
                    ]
                ) {
                    Button("Add Model…") { showAddRemoteModel = true }
                    Button("Open Quotas") { grpc.openQuotaConfig() }
                }

                quickFixCard(
                    title: "permission_denied",
                    summary: "优先区分系统权限、device capability 还是 policy 拒绝，不再只留原始错误。",
                    steps: [
                        "1. Hub Settings → Grants & Permissions",
                        "2. System Settings → Accessibility / Calendar",
                        "3. Edit device or re-run request"
                    ]
                ) {
                    Button("Open Accessibility") { SystemSettingsLinks.openAccessibilityPrivacy() }
                    Button("Open Calendar") { SystemSettingsLinks.openCalendarPrivacy() }
                    if let preferredClientForRepair {
                        Button("Edit Device") { editingGRPCClient = preferredClientForRepair }
                    }
                }

                quickFixCard(
                    title: "hub_unreachable",
                    summary: "Hub 不可达时，先查 launch status，再用 diagnostics 修复，再回 pair/smoke。",
                    steps: [
                        "1. First Run Path → Pair XT device",
                        "2. Diagnostics & Recovery → Fix Now / Open Log",
                        "3. Refresh gRPC and retry smoke"
                    ]
                ) {
                    Button("Fix Now") { fixNow(snapshot: hubLaunchStatus) }
                    Button("Open Log") { grpc.openLog() }
                    Button("Refresh") { grpc.refresh() }
                }

                if let denied = grpcDeniedAttempts.attempts.first {
                    Text("Latest denied attempt: \(denied.clientName.isEmpty ? denied.deviceId : denied.clientName) · \(denied.reason)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var activeRemoteModelCount: Int {
        remoteModels.filter { $0.enabled }.count
    }

    private var currentLaunchStateLabel: String {
        hubLaunchStatus?.state.rawValue ?? "unknown"
    }

    private var preferredClientForRepair: HubGRPCClientEntry? {
        if let denied = grpcDeniedAttempts.attempts.first,
           let client = grpc.allowedClients.first(where: { $0.deviceId == denied.deviceId }) {
            return client
        }
        return grpc.allowedClients.first
    }

    @ViewBuilder
    private func firstRunStepRow<Actions: View>(index: Int, title: String, summary: String, @ViewBuilder actions: () -> Actions) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(index). \(title)")
                    .font(.subheadline.weight(.semibold))
                Spacer()
            }
            Text(summary)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                actions()
                Spacer()
            }
            .font(.caption)
        }
        .padding(12)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private func quickFixCard<Actions: View>(title: String, summary: String, steps: [String], @ViewBuilder actions: () -> Actions) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("3 steps")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            Text(summary)
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(steps, id: \.self) { step in
                Text(step)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                actions()
                Spacer()
            }
            .font(.caption)
        }
        .padding(12)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var floatingModeSection: some View {
        Section("Floating Mode") {
            Picker("Mode", selection: $store.floatingMode) {
                ForEach(FloatingMode.allCases, id: \.self) { m in
                    Text(m.title).tag(m)
                }
            }
            .pickerStyle(.segmented)

            Stepper("Meeting urgent: \(store.meetingUrgentMinutes)m", value: $store.meetingUrgentMinutes, in: 1...30)
        }
    }

    private var integrationsSection: some View {
        Section("Integrations") {
            IntegrationToggleRow(
                systemImage: "calendar",
                title: "Calendar",
                detail: store.calendarStatus,
                isOn: $store.integrationCalendarEnabled
            )

            IntegrationToggleRow(
                systemImage: "envelope",
                title: "Mail (counts only)",
                detail: badgeDetailText(dedupeKey: "mail_unread", isEnabled: store.integrationMailEnabled),
                isOn: $store.integrationMailEnabled
            )
            IntegrationToggleRow(
                systemImage: "message",
                title: "Messages (counts only)",
                detail: badgeDetailText(dedupeKey: "messages_unread", isEnabled: store.integrationMessagesEnabled),
                isOn: $store.integrationMessagesEnabled
            )
            IntegrationToggleRow(
                systemImage: "bubble.left.and.bubble.right",
                title: "Slack (best-effort)",
                detail: badgeDetailText(dedupeKey: "slack_updates", isEnabled: store.integrationSlackEnabled),
                isOn: $store.integrationSlackEnabled
            )

            if store.integrationSlackEnabled, store.integrationsDebugText.contains("Slack:use_dock_agent") {
                Text("Slack unread counts require the external Dock Agent on newer macOS versions (sandboxed apps cannot read Dock badges).")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var doctorSection: some View {
        Section("Doctor") {
            HStack {
                Text("Calendar")
                Spacer()
                Text(store.calendarStatus)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if store.integrationCalendarEnabled, !calendarHasReadAccess {
                HStack(spacing: 10) {
                    Button("Enable Calendar") {
                        NSApp.activate(ignoringOtherApps: true)
                        store.requestCalendarAccessAndStart()
                    }
                    Button("Open Settings") { SystemSettingsLinks.openCalendarPrivacy() }
                    Spacer()
                }
                if store.calendarDeniedOrRestricted {
                    Text("Calendar access is denied/restricted. Enable it in System Settings → Privacy & Security → Calendars.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Text("Accessibility")
                Spacer()
                Text(axTrusted ? "Granted" : "Not granted")
                    .foregroundStyle(.secondary)
            }
            if !axTrusted {
                HStack(spacing: 10) {
                    Button("Request") {
                        NSApp.activate(ignoringOtherApps: true)
                        _ = DockBadgeReader.ensureAccessibilityTrusted(prompt: true)
                        SystemSettingsLinks.openAccessibilityPrivacy()
                    }
                    Button("Open Settings") { SystemSettingsLinks.openAccessibilityPrivacy() }
                    Spacer()
                }
            }

            if store.integrationSlackEnabled || store.integrationMessagesEnabled {
                HStack {
                    Text("Dock Agent")
                    Spacer()
                    Text(store.dockAgentStatusText)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Start at login")
                    Spacer()
                    Text(store.dockAgentAutoStartText)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 10) {
                    Button("Open Dock Agent") { openDockAgentApp() }
                    Button("Enable at Login") { store.enableDockAgentAutoStart() }
                    Button("Disable") { store.disableDockAgentAutoStart() }
                    Button("Open Accessibility") { SystemSettingsLinks.openAccessibilityPrivacy() }
                    Spacer()
                }
                Text("If Slack/Messages counts do not update, install/run REL Flow Hub Dock Agent and grant Accessibility once.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Button("Refresh Integrations") { store.refreshIntegrationsNow() }
                Spacer()
            }

            DisclosureGroup("Details") {
                if !store.integrationsStatusText.isEmpty {
                    Text(store.integrationsStatusText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(store.integrationsDebugText.isEmpty ? "Debug: (none yet)" : store.integrationsDebugText)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }

    private var diagnosticsSection: some View {
        Section("Diagnostics") {
            let snap = hubLaunchStatus
            let primary = HubLaunchStatusStorage.url()
            let fallback = URL(fileURLWithPath: "/tmp/RELFlowHub", isDirectory: true).appendingPathComponent(HubLaunchStatusStorage.fileName)
            let histPrimary = HubLaunchHistoryStorage.url()
            let histFallback = URL(fileURLWithPath: "/tmp/RELFlowHub", isDirectory: true).appendingPathComponent(HubLaunchHistoryStorage.fileName)

            HStack {
                Text("Launch status")
                Spacer()
                Text(snap?.state.rawValue ?? "unknown")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if let snap, snap.updatedAtMs > 0 {
                HStack {
                    Text("Updated")
                    Spacer()
                    Text(formatEpochMs(snap.updatedAtMs))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            if let id = snap?.launchId.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty {
                HStack {
                    Text("Launch ID")
                    Spacer()
                    Text(id)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .textSelection(.enabled)
                }
            }

            let rootCauseText = renderRootCauseText(snap?.rootCause)
            if !rootCauseText.isEmpty {
                Text("Root cause")
                    .font(.caption.weight(.semibold))
                Text(rootCauseText)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            } else {
                Text("Root cause: (none)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            let blocked = snap?.degraded.blockedCapabilities ?? []
            if !blocked.isEmpty {
                Text("Blocked capabilities")
                    .font(.caption.weight(.semibold))
                Text(blocked.joined(separator: "\n"))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            } else {
                Text("Blocked capabilities: (none)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Button(diagnosticsActionIsRunning ? "Running..." : "Retry Start") {
                    retryLaunchDiagnosis()
                }
                .disabled(diagnosticsActionIsRunning || fixNowIsRunning)

                Button("Restart Components") {
                    restartComponentsForDiagnostics()
                }
                .disabled(diagnosticsActionIsRunning || fixNowIsRunning)

                Button("Reset Volatile Caches") {
                    resetVolatileCachesForDiagnostics()
                }
                .disabled(diagnosticsActionIsRunning || fixNowIsRunning)

                Spacer()
            }
            .font(.caption)

            HStack(spacing: 10) {
                Button("Repair DB (Safe)") {
                    repairDBSafeForDiagnostics()
                }
                .disabled(diagnosticsActionIsRunning || fixNowIsRunning)
                Spacer()
            }
            .font(.caption)

            if !diagnosticsActionErrorText.isEmpty {
                Text(diagnosticsActionErrorText)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            } else if !diagnosticsActionResultText.isEmpty {
                Text(diagnosticsActionResultText)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            if !hubLaunchHistory.launches.isEmpty {
                DisclosureGroup("Launch history") {
                    HStack(spacing: 10) {
                        Button("Copy History") {
                            copyLaunchHistoryToClipboard(snapshot: hubLaunchHistory)
                        }
                        Button("Open History File") {
                            openLaunchStatusFile(primary: histPrimary, fallback: histFallback)
                        }
                        Spacer()
                    }
                    .font(.caption)

                    Text(renderLaunchHistory(hubLaunchHistory.launches))
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            let fixAction = recommendedFixAction(snapshot: snap)
            let fixSummary = fixAction?.summary ?? ""
            if !fixSummary.isEmpty {
                HStack(spacing: 10) {
                    Button(fixNowIsRunning ? "Fixing..." : "Fix Now") {
                        fixNow(snapshot: snap)
                    }
                    .disabled(fixNowIsRunning || diagnosticsActionIsRunning)
                    if fixAction == .restartRuntime || fixAction == .clearPythonAndRestartRuntime || fixAction == .unlockRuntimeLockHolders {
                        Button("Open AI Runtime Log") {
                            store.openAIRuntimeLog()
                        }
                    }
                    if fixAction == .unlockRuntimeLockHolders {
                        Button(fixNowIsRunning ? "Running..." : "Run lsof+kill") {
                            runLsofKillAndRestart()
                        }
                        .disabled(fixNowIsRunning || diagnosticsActionIsRunning)
                        Button("Copy lsof+kill") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(store.aiRuntimeLockKillCommandHint(), forType: .string)
                        }
                    }
                    Text(fixSummary)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                }
                .font(.caption)

                if !fixNowErrorText.isEmpty {
                    Text(fixNowErrorText)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                } else if !fixNowResultText.isEmpty {
                    Text(fixNowResultText)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            HStack(spacing: 10) {
                Button("Copy Root Cause + Blocked") {
                    copyLaunchRootCauseAndBlockedToClipboard(snapshot: snap)
                }
                Button("Open File") {
                    openLaunchStatusFile(primary: primary, fallback: fallback)
                }
                Spacer()
            }
            .font(.caption)

            HStack(spacing: 10) {
                Button(diagnosticsBundleIsExporting ? "Exporting..." : "Export Diagnostics Bundle (Redacted)") {
                    exportDiagnosticsBundle()
                }
                .disabled(diagnosticsBundleIsExporting)

                if !diagnosticsBundleArchivePath.isEmpty {
                    Button("Reveal") {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: diagnosticsBundleArchivePath)])
                    }
                    Button("Copy Path") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(diagnosticsBundleArchivePath, forType: .string)
                    }
                    Button("Copy Issue Snippet") {
                        copyIssueSnippetToClipboard(snapshot: snap)
                    }
                }
                Spacer()
            }
            .font(.caption)

            if !diagnosticsBundleError.isEmpty {
                Text(diagnosticsBundleError)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            } else if !diagnosticsBundleArchivePath.isEmpty {
                Text(diagnosticsBundleArchivePath)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            } else {
                Text("Bundle includes hub_launch_status.json + key status/logs. Tokens are redacted by default.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if !diagnosticsBundleMissingFiles.isEmpty {
                DisclosureGroup("Bundle missing files") {
                    Text(diagnosticsBundleMissingFiles.joined(separator: "\n"))
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            DisclosureGroup("Paths") {
                Text(pathLine("Primary", url: primary))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Text(pathLine("Fallback", url: fallback))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Text(pathLine("History", url: histPrimary))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Text(pathLine("History Fallback", url: histFallback))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            if let snap, !snap.steps.isEmpty {
                DisclosureGroup("Steps") {
                    Text(renderLaunchSteps(snap.steps))
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private var networkingSection: some View {
        Section("Networking (Bridge)") {
            HStack {
                Text("Bridge")
                Spacer()
                Text(store.bridge.bridgeStatusText)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                Button("Enable 30m") {
                    store.bridge.enable(seconds: 30 * 60)
                }
                Button("Disable") { store.bridge.disable() }
                Button("Refresh") { store.bridge.refresh() }
                Spacer()
            }

            if store.pendingNetworkRequests.isEmpty {
                Text("No pending network requests.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(store.pendingNetworkRequests) { req in
                    networkRequestCard(req)
                }
            }
        }
    }

    private func formatEpochMs(_ ms: Int64) -> String {
        let d = Date(timeIntervalSince1970: Double(ms) / 1000.0)
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.string(from: d)
    }

    private func renderRootCauseText(_ rc: HubLaunchRootCause?) -> String {
        guard let rc else { return "" }
        let comp = rc.component.rawValue
        let code = rc.errorCode
        let detail = rc.detail.trimmingCharacters(in: .whitespacesAndNewlines)
        if detail.isEmpty {
            return "\(comp) · \(code)"
        }
        return "\(comp) · \(code)\n\(detail)"
    }

    private func renderLaunchHistory(_ launches: [HubLaunchStatusSnapshot], limit: Int = 12) -> String {
        let maxN = max(1, min(50, limit))
        let rows = launches.prefix(maxN).map { s in
            let ts = s.updatedAtMs > 0 ? formatEpochMs(s.updatedAtMs) : "unknown_time"
            let state = s.state.rawValue
            let degraded = s.degraded.isDegraded ? "1" : "0"
            let id = s.launchId.trimmingCharacters(in: .whitespacesAndNewlines)
            let root = renderRootCauseText(s.rootCause).replacingOccurrences(of: "\n", with: " | ")
            let rootText = root.isEmpty ? "(none)" : root
            let blocked = s.degraded.blockedCapabilities
            let blockedText = blocked.isEmpty ? "(none)" : blocked.joined(separator: ",")
            return "\(ts) state=\(state) degraded=\(degraded)\nlaunch_id=\(id)\nroot=\(rootText)\nblocked=\(blockedText)"
        }
        return rows.joined(separator: "\n\n---\n\n")
    }

    private func copyLaunchHistoryToClipboard(snapshot: HubLaunchHistorySnapshot) {
        let updated = snapshot.updatedAtMs > 0 ? formatEpochMs(snapshot.updatedAtMs) : "unknown_time"
        let header = "launch_history_updated_at: \(updated)\nmax_entries: \(snapshot.maxEntries)"
        let body = renderLaunchHistory(snapshot.launches, limit: snapshot.maxEntries)
        let out = HubDiagnosticsBundleExporter.redactTextForSharing(header + "\n\n" + body)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(out, forType: .string)
    }

    private func reloadSkillsSnapshots() {
        skillsIndex = HubSkillsStoreStorage.loadSkillsIndex()
        skillsPins = HubSkillsStoreStorage.loadSkillPins()
        skillsSources = HubSkillsStoreStorage.loadSkillSources()
    }

    private func shortSha(_ sha: String) -> String {
        let s = sha.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.count <= 12 { return s }
        return "\(s.prefix(8))…\(s.suffix(4))"
    }

    private func renderResolvedSkills(_ resolved: [HubSkillsStoreStorage.ResolvedSkill]) -> String {
        let uid = skillsResolveUserId.trimmingCharacters(in: .whitespacesAndNewlines)
        let pid = skillsResolveProjectId.trimmingCharacters(in: .whitespacesAndNewlines)

        var lines: [String] = []
        lines.append("user_id: \(uid.isEmpty ? "(empty)" : uid)")
        lines.append("project_id: \(pid.isEmpty ? "(empty)" : pid)")
        lines.append("precedence: Memory-Core > Global > Project")
        lines.append("")

        for r in resolved {
            let sid = r.pin.skillId.trimmingCharacters(in: .whitespacesAndNewlines)
            let sha = r.pin.packageSha256.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let ver = r.meta?.version.trimmingCharacters(in: .whitespacesAndNewlines) ?? "(missing)"
            let src = r.meta?.sourceId.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let srcSuffix = src.isEmpty ? "" : " source=\(src)"
            lines.append("\(r.scope.shortLabel) skill_id=\(sid) version=\(ver) package_sha256=\(sha)\(srcSuffix)")
        }

        return HubDiagnosticsBundleExporter.redactTextForSharing(lines.joined(separator: "\n"))
    }

    private func openSkillManifest(packageSha256: String) {
        let sha = packageSha256.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !sha.isEmpty else { return }
        let url = HubSkillsStoreStorage.skillManifestURL(packageSha256: sha)
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) {
            NSWorkspace.shared.open(url)
        } else {
            NSWorkspace.shared.open(url.deletingLastPathComponent())
        }
    }

    private func revealSkillPackage(packageSha256: String) {
        let sha = packageSha256.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !sha.isEmpty else { return }
        let url = HubSkillsStoreStorage.skillPackageURL(packageSha256: sha)
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([url.deletingLastPathComponent()])
        }
    }

    private func updateSkillPin(
        scope: HubSkillsStoreStorage.PinScope,
        skillId: String,
        packageSha256: String,
        userIdOverride: String? = nil,
        projectIdOverride: String? = nil
    ) {
        skillsLastActionText = ""
        skillsLastErrorText = ""

        let uid = (userIdOverride ?? skillsResolveUserId).trimmingCharacters(in: .whitespacesAndNewlines)
        let pid = (projectIdOverride ?? skillsResolveProjectId).trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            let userForScope: String? = {
                if scope == .memoryCore { return nil }
                return uid.isEmpty ? nil : uid
            }()
            let projectForScope: String? = {
                if scope != .project { return nil }
                return pid.isEmpty ? nil : pid
            }()

            let res = try HubSkillsStoreStorage.setPin(
                scope: scope,
                userId: userForScope,
                projectId: projectForScope,
                skillId: skillId,
                packageSha256: packageSha256,
                note: nil
            )
            skillsPins = HubSkillsStoreStorage.loadSkillPins()

            let newSha = packageSha256.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if newSha.isEmpty {
                skillsLastActionText = "Unpinned \(skillId) (\(scope.shortLabel))"
            } else {
                let prev = res.previousSha.trimmingCharacters(in: .whitespacesAndNewlines)
                let prevSuffix = prev.isEmpty ? "" : " prev=\(shortSha(prev))"
                skillsLastActionText = "Pinned \(skillId) (\(scope.shortLabel)) -> \(shortSha(newSha))\(prevSuffix)"
            }
        } catch {
            skillsLastErrorText = error.localizedDescription
        }
    }

    private func sortedPins(_ pins: [HubSkillsStoreStorage.SkillPin]) -> [HubSkillsStoreStorage.SkillPin] {
        pins.sorted { a, b in
            let am = a.updatedAtMs ?? 0
            let bm = b.updatedAtMs ?? 0
            if am != bm { return am > bm }
            return a.skillId.localizedCaseInsensitiveCompare(b.skillId) == .orderedAscending
        }
    }

    @ViewBuilder
    private func skillResolvedRow(_ r: HubSkillsStoreStorage.ResolvedSkill) -> some View {
        let sid = r.pin.skillId.trimmingCharacters(in: .whitespacesAndNewlines)
        let sha = r.pin.packageSha256.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let ver = (r.meta?.version ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let name = (r.meta?.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let title = ver.isEmpty ? sid : "\(sid) · \(ver)"

        VStack(alignment: .leading, spacing: 2) {
            Text("\(r.scope.shortLabel) · \(title)")
                .font(.callout.weight(.semibold))
            if !name.isEmpty, name != sid {
                Text(name)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if r.meta == nil {
                Text("Pinned package not installed: \(shortSha(sha))")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            } else {
                Text("package_sha256: \(shortSha(sha))")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            HStack(spacing: 10) {
                if !sha.isEmpty {
                    Button("Open Manifest") { openSkillManifest(packageSha256: sha) }
                    Button("Reveal Package") { revealSkillPackage(packageSha256: sha) }
                }
                Spacer()
            }
            .font(.caption)
        }
    }

    @ViewBuilder
    private func skillPinRow(_ p: HubSkillsStoreStorage.SkillPin, scope: HubSkillsStoreStorage.PinScope) -> some View {
        let sid = p.skillId.trimmingCharacters(in: .whitespacesAndNewlines)
        let sha = p.packageSha256.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let uid = (p.userId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let pid = (p.projectId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let scopeDetail = [uid.isEmpty ? nil : "user_id=\(uid)", pid.isEmpty ? nil : "project_id=\(pid)"]
            .compactMap { $0 }
            .joined(separator: " · ")

        let meta = skillsIndex.skills.first(where: { $0.packageSha256.lowercased() == sha })?.toMeta()
        let ver = (meta?.version ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let title = ver.isEmpty ? sid : "\(sid) · \(ver)"

        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.callout.weight(.semibold))
            if !scopeDetail.isEmpty {
                Text(scopeDetail)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .textSelection(.enabled)
            }
            Text("package_sha256: \(shortSha(sha))")
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            HStack(spacing: 10) {
                if !sha.isEmpty {
                    Button("Open Manifest") { openSkillManifest(packageSha256: sha) }
                    Button("Reveal Package") { revealSkillPackage(packageSha256: sha) }
                }
                Button("Unpin") {
                    updateSkillPin(scope: scope, skillId: sid, packageSha256: "", userIdOverride: uid, projectIdOverride: pid)
                }
                Spacer()
            }
            .font(.caption)
        }
    }

    @ViewBuilder
    private func skillMetaRow(_ meta: HubSkillsStoreStorage.SkillMeta) -> some View {
        let sid = meta.skillId.trimmingCharacters(in: .whitespacesAndNewlines)
        let ver = meta.version.trimmingCharacters(in: .whitespacesAndNewlines)
        let sha = meta.packageSha256.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let desc = meta.description.trimmingCharacters(in: .whitespacesAndNewlines)
        let caps = meta.capabilitiesRequired
        let capsText = caps.isEmpty ? "(none)" : caps.joined(separator: ", ")
        let hint = meta.installHint.trimmingCharacters(in: .whitespacesAndNewlines)

        let canPin = !sha.isEmpty
        let uid = skillsResolveUserId.trimmingCharacters(in: .whitespacesAndNewlines)
        let pid = skillsResolveProjectId.trimmingCharacters(in: .whitespacesAndNewlines)

        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("\(sid) · \(ver)")
                    .font(.callout.weight(.semibold))
                Spacer()
                if sha.isEmpty {
                    Text("not installed")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text(shortSha(sha))
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
            }

            if !desc.isEmpty {
                Text(desc)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Text("publisher: \(meta.publisherId) · source: \(meta.sourceId) · caps: \(capsText)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if !hint.isEmpty {
                Text("install_hint: \(hint)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .textSelection(.enabled)
            }

            HStack(spacing: 10) {
                Menu("Pin…") {
                    Button("Memory-Core") { updateSkillPin(scope: .memoryCore, skillId: sid, packageSha256: sha) }
                        .disabled(!canPin)
                    Button("Global (user_id)") { updateSkillPin(scope: .global, skillId: sid, packageSha256: sha, userIdOverride: uid) }
                        .disabled(!canPin || uid.isEmpty)
                    Button("Project (user_id + project_id)") {
                        updateSkillPin(scope: .project, skillId: sid, packageSha256: sha, userIdOverride: uid, projectIdOverride: pid)
                    }
                    .disabled(!canPin || uid.isEmpty || pid.isEmpty)

                    Divider()

                    Button("Unpin Memory-Core") { updateSkillPin(scope: .memoryCore, skillId: sid, packageSha256: "") }
                    Button("Unpin Global (user_id)") { updateSkillPin(scope: .global, skillId: sid, packageSha256: "", userIdOverride: uid) }
                        .disabled(uid.isEmpty)
                    Button("Unpin Project (user_id + project_id)") {
                        updateSkillPin(scope: .project, skillId: sid, packageSha256: "", userIdOverride: uid, projectIdOverride: pid)
                    }
                    .disabled(uid.isEmpty || pid.isEmpty)
                }

                if !sha.isEmpty {
                    Button("Open Manifest") { openSkillManifest(packageSha256: sha) }
                    Button("Reveal Package") { revealSkillPackage(packageSha256: sha) }
                }
                Spacer()
            }
            .font(.caption)
        }
    }

    private enum FixNowAction {
        case restartGRPC
        case switchGRPCPortAndRestart
        case restartBridge
        case restartRuntime
        case clearPythonAndRestartRuntime
        case unlockRuntimeLockHolders
        case repairDBAndRestartGRPC
        case repairInstallLocation
        case openNodeInstall
        case openPermissionsSettings

        var summary: String {
            switch self {
            case .restartGRPC:
                return "Restart gRPC"
            case .switchGRPCPortAndRestart:
                return "Switch gRPC to a free port"
            case .restartBridge:
                return "Restart Bridge"
            case .restartRuntime:
                return "Restart AI Runtime"
            case .clearPythonAndRestartRuntime:
                return "Auto-fix Python + restart Runtime"
            case .unlockRuntimeLockHolders:
                return "Kill runtime lock holder (lsof+kill)"
            case .repairDBAndRestartGRPC:
                return "Repair gRPC DB + restart"
            case .repairInstallLocation:
                return "Repair install location"
            case .openNodeInstall:
                return "Install Node.js"
            case .openPermissionsSettings:
                return "Open permissions settings"
            }
        }
    }

    private struct FixNowOutcome {
        var ok: Bool
        var code: String
        var detail: String

        func render() -> String {
            let state = ok ? "ok" : "failed"
            let msg = detail.trimmingCharacters(in: .whitespacesAndNewlines)
            if msg.isEmpty {
                return "result_code=\(code)\nstatus=\(state)"
            }
            return "result_code=\(code)\nstatus=\(state)\n\(msg)"
        }
    }

    private func recommendedFixSummary(snapshot: HubLaunchStatusSnapshot?) -> String {
        guard let act = recommendedFixAction(snapshot: snapshot) else { return "" }
        return act.summary
    }

    private func recommendedRuntimeFixAction() -> FixNowAction? {
        // The launch state machine only captures startup-time failures. The AI runtime can still
        // exit later (lock-busy / python misconfig / import errors). Surface a quick fix here so
        // Diagnostics remains useful after "SERVING".
        let err = store.aiRuntimeLastError.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = err.lowercased()
        if !err.isEmpty {
            if lower.contains("lock busy") || lower.contains("ai_runtime.lock") || lower.contains("runtime exited immediately (code 0)") {
                return .unlockRuntimeLockHolders
            }
            if lower.contains("python path") || lower.contains("xcrun stub") || lower.contains("not executable") {
                return .clearPythonAndRestartRuntime
            }
            if lower.contains("script is missing") || lower.contains("failed to install runtime script") {
                return .repairInstallLocation
            }
            return .restartRuntime
        }

        // Lock can remain busy with empty lastError (e.g. after relaunch). Prefer lock fix first.
        if store.aiRuntimeLockBusyNow() {
            return .unlockRuntimeLockHolders
        }

        // Even if lastError is empty (common for code=0 exits), we can still detect an unhealthy
        // runtime via the status text and offer a restart. Do NOT gate on auto-start here; Fix Now
        // is user-initiated and should prioritize core AI health over integrations permissions.
        let status = store.aiRuntimeStatusText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let isRunning = status.contains("runtime: running")
        let wantsRefresh = status.contains("needs refresh")
        if wantsRefresh {
            return .restartRuntime
        }
        if !isRunning, status.contains("stale") || status.contains("not running") || status.contains("stopped") || status.contains("error") {
            return .restartRuntime
        }

        return nil
    }

    private func recommendedFixAction(snapshot: HubLaunchStatusSnapshot?) -> FixNowAction? {
        if let rc = snapshot?.rootCause {
            let code = rc.errorCode.trimmingCharacters(in: .whitespacesAndNewlines)

            // Install-location issues are common root causes for "weird" behavior (TCC prompts / AppTranslocation).
            if code == "XHUB_ENV_INVALID", AppInstallDoctor.shouldWarn() {
                return .repairInstallLocation
            }

            switch code {
        case "XHUB_GRPC_PORT_IN_USE":
            return .switchGRPCPortAndRestart
        case "XHUB_GRPC_NODE_MISSING":
            return .openNodeInstall
        case "XHUB_GRPC_SERVER_EXITED":
            return .restartGRPC
        case "XHUB_BRIDGE_UNAVAILABLE":
            return .restartBridge
        case "XHUB_RT_PYTHON_INVALID":
            return .clearPythonAndRestartRuntime
        case "XHUB_RT_LOCK_BUSY":
            return .unlockRuntimeLockHolders
        case "XHUB_RT_IMPORT_ERROR":
            return .restartRuntime
        case "XHUB_RT_SCRIPT_MISSING":
            return .repairInstallLocation
        case "XHUB_DB_OPEN_FAILED", "XHUB_DB_INTEGRITY_FAILED":
            return .repairDBAndRestartGRPC
        case "XHUB_ENV_INVALID":
            return AppInstallDoctor.shouldWarn() ? .repairInstallLocation : .openPermissionsSettings
        default:
            switch rc.component {
            case .grpc:
                return .restartGRPC
            case .bridge:
                return .restartBridge
            case .runtime:
                return .restartRuntime
            case .env, .db:
                return AppInstallDoctor.shouldWarn() ? .repairInstallLocation : .openPermissionsSettings
            }
            }
        }

        // No launch root-cause fix. If the runtime is unhealthy (common after launch), prioritize
        // self-healing over unrelated permissions prompts.
        if let act = recommendedRuntimeFixAction() {
            return act
        }

        // No launch root-cause fix; fall back to common permission blockers.
        if store.integrationCalendarEnabled, store.calendarDeniedOrRestricted {
            return .openPermissionsSettings
        }
        let needsAXForIntegrations = store.integrationSlackEnabled || store.integrationMessagesEnabled
        if needsAXForIntegrations, !axTrusted {
            return .openPermissionsSettings
        }
        if AppInstallDoctor.shouldWarn() {
            return .repairInstallLocation
        }
        return nil
    }

    private func fixNow(snapshot: HubLaunchStatusSnapshot?) {
        Task { await fixNowAsync(snapshot: snapshot) }
    }

    private func runLsofKillAndRestart() {
        Task { await runLsofKillAndRestartAsync() }
    }

    private func retryLaunchDiagnosis() {
        Task { await retryLaunchDiagnosisAsync() }
    }

    private func restartComponentsForDiagnostics() {
        Task { await restartComponentsForDiagnosticsAsync() }
    }

    private func resetVolatileCachesForDiagnostics() {
        Task { await resetVolatileCachesForDiagnosticsAsync() }
    }

    private func repairDBSafeForDiagnostics() {
        Task { await repairDBSafeForDiagnosticsAsync() }
    }

    private func runtimeAliveSnapshot() -> (alive: Bool, pid: Int, mlxOk: Bool, runtimeVersion: String, ageSec: Double) {
        guard let st = AIRuntimeStatusStorage.load() else {
            return (false, 0, false, "", 0)
        }
        let age = max(0.0, Date().timeIntervalSince1970 - st.updatedAt)
        let ver = (st.runtimeVersion ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return (st.isAlive(ttl: 3.0), st.pid, st.mlxOk, ver, age)
    }

    private struct RuntimeUnlockRestartOutcome {
        var ok: Bool
        var code: String
        var detail: String
        var error: String
    }

    private func runtimeLockIssueLikely(snapshot: HubLaunchStatusSnapshot?) -> Bool {
        if snapshot?.rootCause?.errorCode == "XHUB_RT_LOCK_BUSY" {
            return true
        }
        if store.aiRuntimeLockBusyNow() {
            return true
        }
        let err = store.aiRuntimeLastError.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if err.isEmpty { return false }
        return err.contains("lock busy") || err.contains("ai_runtime.lock") || err.contains("runtime exited immediately (code 0)")
    }

    private func grpcPortConflictLikely(snapshot: HubLaunchStatusSnapshot?) -> Bool {
        if snapshot?.rootCause?.errorCode == "XHUB_GRPC_PORT_IN_USE" {
            return true
        }
        let err = store.grpc.lastError.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if err.isEmpty { return false }
        return err.contains("port") && err.contains("already in use")
    }

    @MainActor
    private func repairGRPCPortConflictAsync() async -> FixNowOutcome {
        let oldPort = store.grpc.port
        if let free = HubGRPCServerSupport.diagnosticsFindAvailablePort(startingAt: oldPort + 1) {
            store.grpc.port = free
            store.grpc.start()
            return await verifyGRPCAfterFix(
                successCode: "FIX_GRPC_PORT_SWITCH_OK",
                failureCode: "FIX_GRPC_PORT_SWITCH_FAILED",
                actionSummary: "Requested: gRPC port \(oldPort) -> \(free), restart."
            )
        }

        store.grpc.restart()
        return await verifyGRPCAfterFix(
            successCode: "FIX_GRPC_RESTART_OK",
            failureCode: "FIX_GRPC_RESTART_FAILED",
            actionSummary: "No free port found nearby. Requested: gRPC restart on \(oldPort)."
        )
    }

    @MainActor
    private func unlockRuntimeLockAndRestartResult(allowNonRuntimeHolders: Bool, autoEscalateToForce: Bool) async -> RuntimeUnlockRestartOutcome {
        // First ask runtime to stop via its marker file; this clears most stale-lock cases.
        store.stopAIRuntime()
        try? await Task.sleep(nanoseconds: 600_000_000)

        var r = store.forceUnlockAIRuntimeLockByLsof(allowNonRuntimeHolders: allowNonRuntimeHolders)
        var forcedMode = allowNonRuntimeHolders
        if !r.lockReleased && !allowNonRuntimeHolders && autoEscalateToForce {
            let allCandidatesSkipped = !r.holderPids.isEmpty && Set(r.holderPids) == Set(r.skippedPids)
            let lower = r.detail.lowercased()
            if allCandidatesSkipped || lower.contains("lsof is blocked by sandbox") {
                // User already clicked Fix Now: retry once in force mode to avoid manual Terminal kills.
                r = store.forceUnlockAIRuntimeLockByLsof(allowNonRuntimeHolders: true)
                forcedMode = true
            }
        }

        if !r.lockReleased {
            let hint = "\n\nTry in Terminal:\n  \(r.command)"
            return RuntimeUnlockRestartOutcome(
                ok: false,
                code: "FIX_RT_LOCK_STILL_BUSY",
                detail: "",
                error: (r.detail.isEmpty ? "Runtime lock is still busy." : r.detail) + hint
            )
        }

        // Lock is now free; immediately restart runtime and verify.
        store.startAIRuntime()
        try? await Task.sleep(nanoseconds: 1_300_000_000)
        let rt = runtimeAliveSnapshot()
        if rt.alive {
            let ok = rt.mlxOk ? "mlx_ok=1" : "mlx_ok=0"
            let ver = rt.runtimeVersion.isEmpty ? "" : " version=\(rt.runtimeVersion)"
            let killed = r.killedPids.isEmpty ? "" : " killed=\(r.killedPids.map(String.init).joined(separator: ","))"
            let mode = forcedMode ? " (force)" : ""
            return RuntimeUnlockRestartOutcome(
                ok: true,
                code: forcedMode ? "FIX_RT_LOCK_FORCE_CLEAR_RESTART_OK" : "FIX_RT_LOCK_CLEAR_RESTART_OK",
                detail: "Runtime lock cleared\(mode) + restarted · pid \(rt.pid) (\(ok))\(ver)\(killed)",
                error: ""
            )
        }

        let err = store.aiRuntimeLastError.trimmingCharacters(in: .whitespacesAndNewlines)
        if err.isEmpty {
            return RuntimeUnlockRestartOutcome(
                ok: false,
                code: "FIX_RT_RESTART_AFTER_LOCK_CLEAR_FAILED",
                detail: "",
                error: "Lock was cleared but runtime did not start.\n\nTry in Terminal:\n  \(r.command)"
            )
        }
        return RuntimeUnlockRestartOutcome(
            ok: false,
            code: classifyRuntimeFailureCode(err, fallback: "FIX_RT_RESTART_AFTER_LOCK_CLEAR_FAILED"),
            detail: "",
            error: err
        )
    }

    @MainActor
    private func unlockRuntimeLockAndRestart(allowNonRuntimeHolders: Bool) async {
        let out = await unlockRuntimeLockAndRestartResult(
            allowNonRuntimeHolders: allowNonRuntimeHolders,
            autoEscalateToForce: !allowNonRuntimeHolders
        )
        let outcome = FixNowOutcome(
            ok: out.ok,
            code: out.code,
            detail: out.ok ? out.detail : out.error
        )
        applyFixNowOutcome(outcome)
        rerunLaunchDiagnosisSoon(delayNs: 1_350_000_000)
    }

    @MainActor
    private func runLsofKillAndRestartAsync() async {
        guard !fixNowIsRunning else { return }
        fixNowIsRunning = true
        fixNowResultText = ""
        fixNowErrorText = ""
        defer { fixNowIsRunning = false }

        HubDiagnostics.log("diagnostics.fix action=unlock_runtime_lock_holders_force")
        await unlockRuntimeLockAndRestart(allowNonRuntimeHolders: true)
    }

    @MainActor
    private func retryLaunchDiagnosisAsync() async {
        guard !diagnosticsActionIsRunning else { return }
        diagnosticsActionIsRunning = true
        diagnosticsActionResultText = ""
        diagnosticsActionErrorText = ""
        defer { diagnosticsActionIsRunning = false }

        HubDiagnostics.log("diagnostics.action action=retry_start")
        HubLaunchStateMachine.shared.start(bridgeStarted: true)
        try? await Task.sleep(nanoseconds: 450_000_000)
        hubLaunchStatus = HubLaunchStatusStorage.load()
        hubLaunchHistory = HubLaunchHistoryStorage.load()
        diagnosticsActionResultText = "Requested: retry start."
    }

    @MainActor
    private func restartComponentsForDiagnosticsAsync() async {
        guard !diagnosticsActionIsRunning else { return }
        diagnosticsActionIsRunning = true
        diagnosticsActionResultText = ""
        diagnosticsActionErrorText = ""
        defer { diagnosticsActionIsRunning = false }

        HubDiagnostics.log("diagnostics.action action=restart_components")

        // Restart embedded Bridge first so status heartbeats resume quickly.
        if let appDelegate = NSApp.delegate as? AppDelegate {
            appDelegate.restartEmbeddedBridgeForDiagnostics()
        }
        store.bridge.refresh()

        // Restart gRPC server (best-effort; may fail if Node is missing / port conflict).
        store.grpc.restart()

        // Restart AI runtime (best-effort; lock-holder issues are handled by Fix Now).
        store.stopAIRuntime()
        try? await Task.sleep(nanoseconds: 900_000_000)
        store.startAIRuntime()

        // Re-run attribution to update root-cause + blocked capabilities.
        HubLaunchStateMachine.shared.start(bridgeStarted: true)
        try? await Task.sleep(nanoseconds: 650_000_000)
        hubLaunchStatus = HubLaunchStatusStorage.load()
        hubLaunchHistory = HubLaunchHistoryStorage.load()

        diagnosticsActionResultText = "Requested: restart components (Bridge/gRPC/Runtime)."
    }

    @MainActor
    private func resetVolatileCachesForDiagnosticsAsync() async {
        guard !diagnosticsActionIsRunning else { return }
        diagnosticsActionIsRunning = true
        diagnosticsActionResultText = ""
        diagnosticsActionErrorText = ""
        defer { diagnosticsActionIsRunning = false }

        HubDiagnostics.log("diagnostics.action action=reset_volatile_caches")

        let base = SharedPaths.ensureHubDirectory()
        let dirs: [URL] = [
            base.appendingPathComponent("ai_requests", isDirectory: true),
            base.appendingPathComponent("ai_responses", isDirectory: true),
            base.appendingPathComponent("ipc_events", isDirectory: true),
            base.appendingPathComponent("ipc_responses", isDirectory: true),
            base.appendingPathComponent("bridge_commands", isDirectory: true),
            base.appendingPathComponent("bridge_requests", isDirectory: true),
            base.appendingPathComponent("bridge_responses", isDirectory: true),
        ]

        let fm = FileManager.default
        var removedCount = 0
        var failedCount = 0

        for dir in dirs {
            do {
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
                let files = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
                for u in files {
                    do {
                        try fm.removeItem(at: u)
                        removedCount += 1
                    } catch {
                        failedCount += 1
                    }
                }
            } catch {
                failedCount += 1
            }
        }

        HubLaunchStateMachine.shared.start(bridgeStarted: true)
        try? await Task.sleep(nanoseconds: 650_000_000)
        hubLaunchStatus = HubLaunchStatusStorage.load()
        hubLaunchHistory = HubLaunchHistoryStorage.load()

        diagnosticsActionResultText = "Reset volatile caches: removed=\(removedCount) failed=\(failedCount)"
    }

    @MainActor
    private func repairDBSafeForDiagnosticsAsync() async {
        guard !diagnosticsActionIsRunning else { return }
        diagnosticsActionIsRunning = true
        diagnosticsActionResultText = ""
        diagnosticsActionErrorText = ""
        defer { diagnosticsActionIsRunning = false }

        HubDiagnostics.log("diagnostics.action action=repair_db_safe")

        let res = await repairGRPCDBSafeAndRestart()

        HubLaunchStateMachine.shared.start(bridgeStarted: true)
        try? await Task.sleep(nanoseconds: 650_000_000)
        hubLaunchStatus = HubLaunchStatusStorage.load()
        hubLaunchHistory = HubLaunchHistoryStorage.load()

        if res.ok {
            diagnosticsActionResultText = res.render()
        } else {
            diagnosticsActionErrorText = res.render()
        }
    }

    @MainActor
    private func repairGRPCDBSafeAndRestart() async -> FixNowOutcome {
        // Stop gRPC first to reduce chances of DB locks during checkpoint/check.
        store.grpc.stop()

        let base = SharedPaths.ensureHubDirectory()
        let dbDir = base.appendingPathComponent("hub_grpc", isDirectory: true)
        let db = dbDir.appendingPathComponent("hub.sqlite3")

        do {
            try FileManager.default.createDirectory(at: dbDir, withIntermediateDirectories: true)

            // Fix a common crash-loop case: a zero-byte DB file.
            if FileManager.default.fileExists(atPath: db.path),
               let attrs = try? FileManager.default.attributesOfItem(atPath: db.path),
               let size = attrs[.size] as? NSNumber,
               size.int64Value == 0 {
                try? FileManager.default.removeItem(at: db)
            }

            // Backup (best-effort) before touching WAL/checkpoint.
            if FileManager.default.fileExists(atPath: db.path) {
                let ts = Int(Date().timeIntervalSince1970)
                let bak = dbDir.appendingPathComponent("hub.sqlite3.bak_\(ts)")
                if !FileManager.default.fileExists(atPath: bak.path) {
                    try? FileManager.default.copyItem(at: db, to: bak)
                }
            }

            // Best-effort: checkpoint WAL (safe) to reduce "stuck WAL" and shrink temporary files.
            _ = runSQLite(dbPath: db.path, readonly: false, sql: "PRAGMA busy_timeout=1500; PRAGMA wal_checkpoint(TRUNCATE);")

            // Quick check for corruption/locking.
            let qc = runSQLite(dbPath: db.path, readonly: true, sql: "PRAGMA busy_timeout=1500; PRAGMA quick_check;")
            let out = qc.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            let ok = qc.exitCode == 0 && (out.lowercased() == "ok" || out.lowercased().hasSuffix("\nok"))

            store.grpc.start()

            if ok {
                return await verifyGRPCAfterFix(
                    successCode: "FIX_GRPC_DB_REPAIR_OK",
                    failureCode: "FIX_GRPC_DB_REPAIR_RESTART_FAILED",
                    actionSummary: "DB repair (safe): quick_check OK + restart."
                )
            }

            let err = (qc.stderr + "\n" + qc.stdout).trimmingCharacters(in: .whitespacesAndNewlines)
            let msg = err.isEmpty ? "DB repair (safe): quick_check failed (exit=\(qc.exitCode))" : "DB repair (safe): quick_check failed\n\n\(err)"
            return FixNowOutcome(ok: false, code: "FIX_GRPC_DB_REPAIR_CHECK_FAILED", detail: msg)
        } catch {
            store.grpc.start()
            return FixNowOutcome(ok: false, code: "FIX_GRPC_DB_REPAIR_EXCEPTION", detail: "DB repair (safe) failed: \(error.localizedDescription)")
        }
    }

    private struct SQLiteRunResult {
        var exitCode: Int32
        var stdout: String
        var stderr: String
    }

    private func grpcLogTail(maxBytes: Int = 64 * 1024) -> String {
        let base = SharedPaths.appGroupDirectory() ?? SharedPaths.ensureHubDirectory()
        let logURL = base.appendingPathComponent("hub_grpc.log")
        guard let data = try? Data(contentsOf: logURL), !data.isEmpty else {
            return ""
        }
        let tail = data.suffix(max(2048, min(maxBytes, 512 * 1024)))
        return String(data: tail, encoding: .utf8) ?? ""
    }

    private func grpcLikelyTLSPEMFailure() -> Bool {
        let lower = grpcLogTail().lowercased()
        if lower.isEmpty { return false }
        let pemNoStartLine =
            lower.contains("err_ossl_pem_no_start_line") ||
            lower.contains("pem routines::no start line") ||
            (lower.contains("node:internal/tls/secure-context") && lower.contains("setcert"))
        let opensslSerialWriteDenied =
            (lower.contains("openssl x509 -req") && lower.contains("-cacreateserial") && lower.contains(".srl: operation not permitted")) ||
            (lower.contains("getting ca private key") && lower.contains(".srl: operation not permitted"))
        return
            pemNoStartLine ||
            opensslSerialWriteDenied
    }

    private func runSQLite(dbPath: String, readonly: Bool, sql: String) -> SQLiteRunResult {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        var args: [String] = []
        if readonly {
            args.append("-readonly")
        }
        args.append(contentsOf: ["-batch", dbPath, sql])
        p.arguments = args

        let outPipe = Pipe()
        let errPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = errPipe

        do {
            try p.run()
            p.waitUntilExit()
        } catch {
            return SQLiteRunResult(exitCode: -1, stdout: "", stderr: error.localizedDescription)
        }

        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        return SQLiteRunResult(
            exitCode: p.terminationStatus,
            stdout: String(data: outData, encoding: .utf8) ?? "",
            stderr: String(data: errData, encoding: .utf8) ?? ""
        )
    }

    private func applyFixNowOutcome(_ outcome: FixNowOutcome) {
        let rendered = outcome.render()
        if outcome.ok {
            fixNowErrorText = ""
            fixNowResultText = rendered
        } else {
            fixNowResultText = ""
            fixNowErrorText = rendered
        }
        let compact = outcome.detail
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " | ")
        HubDiagnostics.log("diagnostics.fix result code=\(outcome.code) ok=\(outcome.ok ? 1 : 0) detail=\(compact)")
    }

    private struct GRPCFixSnapshot {
        var running: Bool
        var statusText: String
        var lastError: String
    }

    private func grpcFixSnapshot() -> GRPCFixSnapshot {
        store.grpc.refresh()
        let status = store.grpc.statusText.trimmingCharacters(in: .whitespacesAndNewlines)
        let err = store.grpc.lastError.trimmingCharacters(in: .whitespacesAndNewlines)
        let running = status.lowercased().contains("grpc: running")
        return GRPCFixSnapshot(running: running, statusText: status, lastError: err)
    }

    @MainActor
    private func waitForGRPCFixSnapshot(timeoutNs: UInt64 = 3_500_000_000, pollNs: UInt64 = 250_000_000) async -> GRPCFixSnapshot {
        let start = Date().timeIntervalSince1970
        let timeoutSec = Double(timeoutNs) / 1_000_000_000.0
        var snap = grpcFixSnapshot()
        while !snap.running && (Date().timeIntervalSince1970 - start) < timeoutSec {
            try? await Task.sleep(nanoseconds: pollNs)
            snap = grpcFixSnapshot()
        }
        return snap
    }

    private func classifyGRPCFailureCode(_ errorOrStatus: String, fallback: String) -> String {
        let lower = errorOrStatus.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if lower.isEmpty { return fallback }
        if lower.contains("already in use") || lower.contains("eaddrinuse") {
            return "FIX_GRPC_PORT_IN_USE"
        }
        if lower.contains("node not found") || lower.contains("node missing") {
            return "FIX_GRPC_NODE_MISSING"
        }
        if lower.contains("pem") || lower.contains("certificate") || lower.contains("tls") || lower.contains("secure-context") || lower.contains(".srl") {
            return "FIX_GRPC_TLS_INVALID"
        }
        if lower.contains("db") {
            return "FIX_GRPC_DB_ERROR"
        }
        if lower.contains("exited") {
            return "FIX_GRPC_EXITED"
        }
        return fallback
    }

    @MainActor
    private func verifyGRPCAfterFix(successCode: String, failureCode: String, actionSummary: String) async -> FixNowOutcome {
        let snap = await waitForGRPCFixSnapshot()
        if snap.running {
            return FixNowOutcome(ok: true, code: successCode, detail: actionSummary)
        }
        let failureText = !snap.lastError.isEmpty ? snap.lastError : (!snap.statusText.isEmpty ? snap.statusText : "gRPC is still not running.")
        let code = classifyGRPCFailureCode(failureText, fallback: failureCode)
        return FixNowOutcome(
            ok: false,
            code: code,
            detail: "\(actionSummary)\n\n\(failureText)"
        )
    }

    private struct BridgeFixSnapshot {
        var alive: Bool
        var updatedAt: Double
    }

    private func bridgeFixSnapshot() -> BridgeFixSnapshot {
        store.bridge.refresh()
        let st = BridgeSupport.shared.statusSnapshot()
        return BridgeFixSnapshot(alive: st.alive, updatedAt: st.updatedAt)
    }

    @MainActor
    private func waitForBridgeFixSnapshot(timeoutNs: UInt64 = 2_800_000_000, pollNs: UInt64 = 250_000_000) async -> BridgeFixSnapshot {
        let start = Date().timeIntervalSince1970
        let timeoutSec = Double(timeoutNs) / 1_000_000_000.0
        var snap = bridgeFixSnapshot()
        while !snap.alive && (Date().timeIntervalSince1970 - start) < timeoutSec {
            try? await Task.sleep(nanoseconds: pollNs)
            snap = bridgeFixSnapshot()
        }
        return snap
    }

    @MainActor
    private func verifyBridgeAfterFix(successCode: String, failureCode: String, actionSummary: String) async -> FixNowOutcome {
        let snap = await waitForBridgeFixSnapshot()
        if snap.alive {
            return FixNowOutcome(ok: true, code: successCode, detail: actionSummary)
        }
        let ageSec: Int = {
            if snap.updatedAt <= 0 { return -1 }
            return Int(max(0.0, Date().timeIntervalSince1970 - snap.updatedAt))
        }()
        let staleInfo = ageSec < 0 ? "Bridge heartbeat is missing." : "Bridge heartbeat is stale (\(ageSec)s)."
        return FixNowOutcome(
            ok: false,
            code: failureCode,
            detail: "\(actionSummary)\n\n\(staleInfo)"
        )
    }

    private func classifyRuntimeFailureCode(_ errorText: String, fallback: String) -> String {
        let lower = errorText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if lower.isEmpty { return fallback }
        if lower.contains("lock busy") || lower.contains("ai_runtime.lock") || lower.contains("runtime exited immediately (code 0)") {
            return "FIX_RT_LOCK_BUSY"
        }
        if lower.contains("python path") || lower.contains("xcrun stub") || lower.contains("not executable") {
            return "FIX_RT_PYTHON_INVALID"
        }
        if lower.contains("script is missing") || lower.contains("failed to install runtime script") {
            return "FIX_RT_SCRIPT_MISSING"
        }
        if lower.contains("mlx is unavailable") || lower.contains("import") {
            return "FIX_RT_IMPORT_ERROR"
        }
        return fallback
    }

    @MainActor
    private func waitForRuntimeFixSnapshot(timeoutNs: UInt64 = 4_500_000_000, pollNs: UInt64 = 250_000_000) async -> (alive: Bool, pid: Int, mlxOk: Bool, runtimeVersion: String, ageSec: Double) {
        let start = Date().timeIntervalSince1970
        let timeoutSec = Double(timeoutNs) / 1_000_000_000.0
        var snap = runtimeAliveSnapshot()
        while !snap.alive && (Date().timeIntervalSince1970 - start) < timeoutSec {
            try? await Task.sleep(nanoseconds: pollNs)
            snap = runtimeAliveSnapshot()
        }
        return snap
    }

    @MainActor
    private func verifyRuntimeAfterFix(successCode: String, failureCode: String, actionSummary: String) async -> FixNowOutcome {
        let rt = await waitForRuntimeFixSnapshot()
        if rt.alive {
            let ok = rt.mlxOk ? "mlx_ok=1" : "mlx_ok=0"
            let ver = rt.runtimeVersion.isEmpty ? "" : " version=\(rt.runtimeVersion)"
            return FixNowOutcome(
                ok: true,
                code: successCode,
                detail: "\(actionSummary)\nRuntime: running · pid \(rt.pid) (\(ok))\(ver)"
            )
        }
        let err = store.aiRuntimeLastError.trimmingCharacters(in: .whitespacesAndNewlines)
        let msg = err.isEmpty ? "Runtime did not start. Open AI runtime log for details." : err
        let code = classifyRuntimeFailureCode(msg, fallback: failureCode)
        return FixNowOutcome(
            ok: false,
            code: code,
            detail: "\(actionSummary)\n\n\(msg)"
        )
    }

    @MainActor
    private func fixNowAsync(snapshot: HubLaunchStatusSnapshot?) async {
        guard let action = recommendedFixAction(snapshot: snapshot), !fixNowIsRunning else { return }
        fixNowIsRunning = true
        fixNowResultText = ""
        fixNowErrorText = ""
        defer { fixNowIsRunning = false }

        let lockIssue = runtimeLockIssueLikely(snapshot: snapshot)
        let portIssue = grpcPortConflictLikely(snapshot: snapshot)
        if lockIssue && portIssue {
            HubDiagnostics.log("diagnostics.fix action=stabilize_runtime_and_grpc")
            let runtimeRaw = await unlockRuntimeLockAndRestartResult(
                allowNonRuntimeHolders: false,
                autoEscalateToForce: true
            )
            let runtime = FixNowOutcome(
                ok: runtimeRaw.ok,
                code: runtimeRaw.code,
                detail: runtimeRaw.ok ? runtimeRaw.detail : runtimeRaw.error
            )
            let grpc = await repairGRPCPortConflictAsync()
            let bothOk = runtime.ok && grpc.ok
            let bothFail = !runtime.ok && !grpc.ok
            let combinedCode: String = {
                if bothOk { return "FIX_STABILIZE_RUNTIME_GRPC_OK" }
                if bothFail { return "FIX_STABILIZE_RUNTIME_GRPC_FAILED" }
                return "FIX_STABILIZE_RUNTIME_GRPC_PARTIAL"
            }()
            let combined = FixNowOutcome(
                ok: bothOk,
                code: combinedCode,
                detail:
                    """
                    runtime[\(runtime.code)] \(runtime.ok ? "ok" : "failed")
                    \(runtime.detail)

                    grpc[\(grpc.code)] \(grpc.ok ? "ok" : "failed")
                    \(grpc.detail)
                    """
            )
            applyFixNowOutcome(combined)
            rerunLaunchDiagnosisSoon(delayNs: 1_500_000_000)
            return
        }

        switch action {
        case .restartGRPC:
            HubDiagnostics.log("diagnostics.fix action=restart_grpc")
            if grpcLikelyTLSPEMFailure(), store.grpc.tlsMode != "insecure" {
                let oldMode = store.grpc.tlsMode
                // Self-heal common crash-loop: malformed TLS PEM files.
                // Reliability first: downgrade to insecure so gRPC can boot.
                store.grpc.tlsMode = "insecure"
                store.grpc.start()
                let outcome = await verifyGRPCAfterFix(
                    successCode: "FIX_GRPC_TLS_DOWNGRADE_RESTART_OK",
                    failureCode: "FIX_GRPC_TLS_DOWNGRADE_RESTART_FAILED",
                    actionSummary: "Detected broken TLS cert/PEM in hub_grpc.log. Switched gRPC tls \(oldMode) -> insecure and restarted."
                )
                applyFixNowOutcome(outcome)
                rerunLaunchDiagnosisSoon(delayNs: 650_000_000)
                return
            }
            store.grpc.restart()
            let outcome = await verifyGRPCAfterFix(
                successCode: "FIX_GRPC_RESTART_OK",
                failureCode: "FIX_GRPC_RESTART_FAILED",
                actionSummary: "Requested: gRPC restart."
            )
            applyFixNowOutcome(outcome)
            rerunLaunchDiagnosisSoon()

        case .switchGRPCPortAndRestart:
            HubDiagnostics.log("diagnostics.fix action=switch_grpc_port")
            let res = await repairGRPCPortConflictAsync()
            applyFixNowOutcome(res)
            rerunLaunchDiagnosisSoon()

        case .restartBridge:
            HubDiagnostics.log("diagnostics.fix action=restart_bridge")
            if let appDelegate = NSApp.delegate as? AppDelegate {
                appDelegate.restartEmbeddedBridgeForDiagnostics()
                store.bridge.refresh()
                let outcome = await verifyBridgeAfterFix(
                    successCode: "FIX_BRIDGE_RESTART_OK",
                    failureCode: "FIX_BRIDGE_RESTART_FAILED",
                    actionSummary: "Requested: Bridge restart."
                )
                applyFixNowOutcome(outcome)
                rerunLaunchDiagnosisSoon()
            } else {
                applyFixNowOutcome(
                    FixNowOutcome(
                        ok: false,
                        code: "FIX_BRIDGE_RESTART_UNAVAILABLE",
                        detail: "Cannot access AppDelegate to restart embedded Bridge."
                    )
                )
            }

        case .restartRuntime:
            HubDiagnostics.log("diagnostics.fix action=restart_runtime")
            store.stopAIRuntime()
            let stopErr = store.aiRuntimeLastError.trimmingCharacters(in: .whitespacesAndNewlines)
            if !stopErr.isEmpty {
                // Stop can fail if the lock holder is a different/orphaned process. Surface that
                // guidance instead of immediately clearing it by starting again.
                applyFixNowOutcome(
                    FixNowOutcome(
                        ok: false,
                        code: classifyRuntimeFailureCode(stopErr, fallback: "FIX_RT_STOP_FAILED"),
                        detail: stopErr
                    )
                )
                return
            }
            try? await Task.sleep(nanoseconds: 900_000_000)
            store.startAIRuntime()
            let outcome = await verifyRuntimeAfterFix(
                successCode: "FIX_RT_RESTART_OK",
                failureCode: "FIX_RT_RESTART_FAILED",
                actionSummary: "Requested: Runtime restart."
            )
            applyFixNowOutcome(outcome)
            rerunLaunchDiagnosisSoon(delayNs: 1_350_000_000)

        case .clearPythonAndRestartRuntime:
            HubDiagnostics.log("diagnostics.fix action=clear_python_restart_runtime")
            store.stopAIRuntime()
            store.aiRuntimePython = "" // allow auto-detection in startAIRuntime()
            let stopErr = store.aiRuntimeLastError.trimmingCharacters(in: .whitespacesAndNewlines)
            if !stopErr.isEmpty {
                applyFixNowOutcome(
                    FixNowOutcome(
                        ok: false,
                        code: classifyRuntimeFailureCode(stopErr, fallback: "FIX_RT_STOP_FAILED"),
                        detail: stopErr
                    )
                )
                return
            }
            try? await Task.sleep(nanoseconds: 700_000_000)
            store.startAIRuntime()
            let outcome = await verifyRuntimeAfterFix(
                successCode: "FIX_RT_CLEAR_PYTHON_RESTART_OK",
                failureCode: "FIX_RT_CLEAR_PYTHON_RESTART_FAILED",
                actionSummary: "Requested: clear Python selection + Runtime restart."
            )
            applyFixNowOutcome(outcome)
            rerunLaunchDiagnosisSoon(delayNs: 1_350_000_000)

        case .unlockRuntimeLockHolders:
            HubDiagnostics.log("diagnostics.fix action=unlock_runtime_lock_holders")
            await unlockRuntimeLockAndRestart(allowNonRuntimeHolders: false)

        case .repairDBAndRestartGRPC:
            HubDiagnostics.log("diagnostics.fix action=repair_db_restart_grpc")
            let res = await repairGRPCDBSafeAndRestart()
            applyFixNowOutcome(res)
            rerunLaunchDiagnosisSoon()

        case .repairInstallLocation:
            HubDiagnostics.log("diagnostics.fix action=repair_install_location")
            NSApp.activate(ignoringOtherApps: true)
            if AppInstallDoctor.shouldWarn() {
                AppInstallDoctor.showInstallAlertIfNeeded()
                applyFixNowOutcome(
                    FixNowOutcome(
                        ok: true,
                        code: "FIX_INSTALL_GUIDE_OPENED",
                        detail: "Opened install-location guidance."
                    )
                )
            } else {
                // Best-effort: if the "install doctor" doesn't apply, at least reveal the app bundle
                // so users can confirm what they're running (common issue: multiple copies).
                NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
                applyFixNowOutcome(
                    FixNowOutcome(
                        ok: true,
                        code: "FIX_APP_BUNDLE_REVEALED",
                        detail: "Revealed current app bundle."
                    )
                )
            }

        case .openNodeInstall:
            HubDiagnostics.log("diagnostics.fix action=open_node_install")
            if let u = URL(string: "https://nodejs.org/en/download"), NSWorkspace.shared.open(u) {
                applyFixNowOutcome(
                    FixNowOutcome(
                        ok: true,
                        code: "FIX_NODE_INSTALL_PAGE_OPENED",
                        detail: "Opened Node.js download page."
                    )
                )
            } else {
                applyFixNowOutcome(
                    FixNowOutcome(
                        ok: false,
                        code: "FIX_NODE_INSTALL_PAGE_OPEN_FAILED",
                        detail: "Failed to open Node.js download page."
                    )
                )
            }

        case .openPermissionsSettings:
            HubDiagnostics.log("diagnostics.fix action=open_permissions")
            if store.integrationCalendarEnabled, store.calendarDeniedOrRestricted {
                SystemSettingsLinks.openCalendarPrivacy()
                applyFixNowOutcome(
                    FixNowOutcome(
                        ok: true,
                        code: "FIX_OPEN_SETTINGS_CALENDAR",
                        detail: "Opened System Settings → Calendars."
                    )
                )
            } else if !axTrusted {
                SystemSettingsLinks.openAccessibilityPrivacy()
                applyFixNowOutcome(
                    FixNowOutcome(
                        ok: true,
                        code: "FIX_OPEN_SETTINGS_ACCESSIBILITY",
                        detail: "Opened System Settings → Accessibility."
                    )
                )
            } else {
                SystemSettingsLinks.openSystemSettings()
                applyFixNowOutcome(
                    FixNowOutcome(
                        ok: true,
                        code: "FIX_OPEN_SETTINGS_GENERAL",
                        detail: "Opened System Settings."
                    )
                )
            }
        }
    }

    private func rerunLaunchDiagnosisSoon(delayNs: UInt64 = 350_000_000) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: delayNs)
            HubLaunchStateMachine.shared.start(bridgeStarted: true)
            hubLaunchStatus = HubLaunchStatusStorage.load()
        }
    }

    private func renderLaunchSteps(_ steps: [HubLaunchStep]) -> String {
        // Compact, grep-friendly one-line format:
        //   <elapsed_ms> <STATE> ok=<0|1> code=<...> hint=<...>
        let out = steps.map { st in
            let ok = st.ok ? "1" : "0"
            let code = st.errorCode.trimmingCharacters(in: .whitespacesAndNewlines)
            let hint = st.errorHint.trimmingCharacters(in: .whitespacesAndNewlines)
            var line = "\(st.elapsedMs) \(st.state.rawValue) ok=\(ok)"
            if !code.isEmpty { line += " code=\(code)" }
            if !hint.isEmpty { line += " hint=\(hint)" }
            return line
        }
        return out.joined(separator: "\n")
    }

    private func copyLaunchRootCauseAndBlockedToClipboard(snapshot: HubLaunchStatusSnapshot?) {
        let state = snapshot?.state.rawValue ?? "unknown"
        let root = renderRootCauseText(snapshot?.rootCause)
        let blocked = snapshot?.degraded.blockedCapabilities ?? []

        var lines: [String] = []
        lines.append("state: \(state)")
        if let id = snapshot?.launchId.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty {
            lines.append("launch_id: \(id)")
        }
        if let snapshot, snapshot.updatedAtMs > 0 {
            lines.append("updated_at: \(formatEpochMs(snapshot.updatedAtMs))")
        }
        lines.append("root_cause:\n" + (root.isEmpty ? "(none)" : root))
        lines.append("blocked_capabilities:\n" + (blocked.isEmpty ? "(none)" : blocked.joined(separator: "\n")))

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n\n"), forType: .string)
    }

    private func copyIssueSnippetToClipboard(snapshot: HubLaunchStatusSnapshot?) {
        let state = snapshot?.state.rawValue ?? "unknown"
        let root = renderRootCauseText(snapshot?.rootCause)
        let blocked = snapshot?.degraded.blockedCapabilities ?? []
        let rtErr = store.aiRuntimeLastError.trimmingCharacters(in: .whitespacesAndNewlines)
        let rtStatus = store.aiRuntimeStatusText.trimmingCharacters(in: .whitespacesAndNewlines)

        var lines: [String] = []
        lines.append("state: \(state)")
        if let id = snapshot?.launchId.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty {
            lines.append("launch_id: \(id)")
        }
        if let snapshot, snapshot.updatedAtMs > 0 {
            lines.append("updated_at: \(formatEpochMs(snapshot.updatedAtMs))")
        }
        lines.append("root_cause:\n" + (root.isEmpty ? "(none)" : root))
        lines.append("blocked_capabilities:\n" + (blocked.isEmpty ? "(none)" : blocked.joined(separator: "\n")))
        if !rtStatus.isEmpty {
            lines.append("runtime_status:\n\(rtStatus)")
        }
        if !rtErr.isEmpty {
            lines.append("runtime_last_error:\n\(rtErr)")
        }
        lines.append("diagnostics_bundle:\n" + (diagnosticsBundleArchivePath.isEmpty ? "(missing)" : diagnosticsBundleArchivePath))

        let out = HubDiagnosticsBundleExporter.redactTextForSharing(lines.joined(separator: "\n\n"))
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(out, forType: .string)
    }

    private func exportDiagnosticsBundle() {
        Task { await exportDiagnosticsBundleAsync() }
    }

    private func reloadAXConstitutionStatus() {
        axConstitutionErrorText = ""
        axConstitutionVersion = ""
        axConstitutionEnabledClauseIds = []

        let url = store.axConstitutionURL()
        guard let data = try? Data(contentsOf: url) else {
            // Missing is common before the first runtime start.
            return
        }
        do {
            let raw = try JSONSerialization.jsonObject(with: data, options: [])
            guard let obj = raw as? [String: Any] else {
                axConstitutionErrorText = "Invalid JSON shape."
                return
            }
            if let v = obj["version"] as? String {
                axConstitutionVersion = v
            } else {
                axConstitutionVersion = ""
            }

            var enabled: [String] = []
            if let clauses = obj["clauses"] as? [Any] {
                for item in clauses {
                    guard let c = item as? [String: Any] else { continue }
                    guard let cid = c["id"] as? String else { continue }
                    if (c["default"] as? Bool) == true {
                        enabled.append(cid)
                    }
                }
            }
            enabled.sort()
            axConstitutionEnabledClauseIds = enabled
        } catch {
            axConstitutionErrorText = error.localizedDescription
        }
    }

    private func copyAXConstitutionSummaryToClipboard() {
        let url = store.axConstitutionURL()
        let ver = axConstitutionVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        let enabled = axConstitutionEnabledClauseIds

        var lines: [String] = []
        lines.append("ax_constitution_path: \(url.path)")
        lines.append("version: \(ver.isEmpty ? "(unknown)" : ver)")
        lines.append("enabled_default_clauses: " + (enabled.isEmpty ? "(none)" : enabled.joined(separator: ",")))

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
    }

    @MainActor
    private func exportDiagnosticsBundleAsync() async {
        if diagnosticsBundleIsExporting { return }
        diagnosticsBundleIsExporting = true
        diagnosticsBundleError = ""
        diagnosticsBundleArchivePath = ""
        diagnosticsBundleManifestPath = ""
        diagnosticsBundleMissingFiles = []
        defer { diagnosticsBundleIsExporting = false }

        do {
            let res: HubDiagnosticsBundleExporter.ExportResult = try await Task.detached(priority: .utility) {
                try HubDiagnosticsBundleExporter.exportDiagnosticsBundle(redactTokens: true)
            }.value

            diagnosticsBundleArchivePath = res.archivePath
            diagnosticsBundleManifestPath = res.manifestPath
            diagnosticsBundleMissingFiles = res.missingFiles

            // Copy the archive path for quick sharing in GitHub issues/Slack.
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(res.archivePath, forType: .string)
        } catch {
            diagnosticsBundleError = error.localizedDescription
        }
    }

    private func openLaunchStatusFile(primary: URL, fallback: URL) {
        let fm = FileManager.default
        if fm.fileExists(atPath: primary.path) {
            NSWorkspace.shared.activateFileViewerSelecting([primary])
            return
        }
        if fm.fileExists(atPath: fallback.path) {
            NSWorkspace.shared.activateFileViewerSelecting([fallback])
            return
        }
        // No file found yet; open the primary directory so users can see where to look.
        NSWorkspace.shared.open(primary.deletingLastPathComponent())
    }

    private func pathLine(_ label: String, url: URL) -> String {
        let fm = FileManager.default
        let exists = fm.fileExists(atPath: url.path)
        return "\(label): \(url.path)\(exists ? "" : " (missing)")"
    }

    private var grpcServerSection: some View {
        Section("LAN (gRPC)") {
            Toggle("Enable LAN gRPC", isOn: $grpc.autoStart)

            HStack {
                Text("Status")
                Spacer()
                Text(grpc.statusText)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if !grpc.lastError.isEmpty {
                Text(grpc.lastError)
                    .font(.caption2)
                    .foregroundStyle(.red)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("X-Terminal Pairing")
                    .font(.caption.weight(.semibold))

                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                    GridRow {
                        Text("Internet Host")
                            .foregroundStyle(.secondary)
                        Text(grpc.xtTerminalInternetHost ?? "No LAN IPv4 detected")
                            .font(.caption.monospaced())
                            .foregroundStyle(grpc.xtTerminalInternetHost == nil ? .secondary : .primary)
                            .textSelection(.enabled)
                    }
                    GridRow {
                        Text("Pairing Port")
                            .foregroundStyle(.secondary)
                        Text("\(grpc.xtTerminalPairingPort)")
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                    GridRow {
                        Text("gRPC Port")
                            .foregroundStyle(.secondary)
                        Text("\(grpc.port)")
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                }
                .font(.caption)

                Text("Use these values in X-Terminal -> Hub Setup. Internet Host should be a reachable LAN/VPN/Tunnel host for the Terminal device.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if !grpc.lanAddresses.isEmpty {
                Text(grpc.lanAddresses.joined(separator: "\n"))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            HStack(spacing: 10) {
                Button("Copy Connect Vars") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(grpc.connectionGuide, forType: .string)
                }
                Button("Copy Bootstrap Cmd") { grpc.copyBootstrapCommandToClipboard() }
                Button("Add Client…") { showAddGRPCClient = true }
                Button("Refresh") { grpc.refresh() }
                Spacer()
            }
            .font(.caption)

            if !grpc.connectionGuide.isEmpty {
                Text(grpc.connectionGuide)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            DisclosureGroup("Advanced") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Transport Security")
                        .font(.caption.weight(.semibold))
                    Picker("TLS", selection: $grpc.tlsMode) {
                        Text("Insecure").tag("insecure")
                        Text("TLS").tag("tls")
                        Text("mTLS").tag("mtls")
                    }
                    .pickerStyle(.segmented)
                    .font(.caption)

                    Text("Recommendation: use mTLS for LAN/VPN. Insecure is for dev/compatibility only. When enabling mTLS, pair devices again so the Hub can issue client certs.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Divider()

                HStack {
                    Text("Port")
                    Spacer()
                    TextField(
                        "50051",
                        value: $grpc.port,
                        formatter: {
                            let f = NumberFormatter()
                            f.allowsFloats = false
                            f.minimum = 1
                            f.maximum = 65535
                            return f
                        }()
                    )
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    .frame(width: 120)
                }

                HStack(spacing: 10) {
                    Button("Open Log") { grpc.openLog() }
                    Button("Rotate Client Token") { grpc.regenerateClientToken() }
                    Spacer()
                }
                .font(.caption)

                HStack(spacing: 10) {
                    Button("Open Quotas") { grpc.openQuotaConfig() }
                    Spacer()
                }
                .font(.caption)

                Text("Quota file: \(grpc.quotaConfigURL().path)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                Divider()

                Text("Clients (Allowlist)")
                    .font(.caption.weight(.semibold))

                HStack(spacing: 10) {
                    Button("Add…") { showAddGRPCClient = true }
                    Button("Open Clients") { grpc.openClientsConfig() }
                    Spacer()
                }
                .font(.caption)

                let ipDenied = grpcDeniedAttempts.attempts
                    .filter { a in
                        a.reason.trimmingCharacters(in: .whitespacesAndNewlines) == "source_ip_not_allowed"
                            && !a.peerIp.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    }
                    .prefix(6)
                if !ipDenied.isEmpty {
                    Divider()
                    Text("Denied (IP allowlist)")
                        .font(.caption.weight(.semibold))
                    ForEach(ipDenied) { a in
                        VStack(alignment: .leading, spacing: 4) {
                            let title = !a.clientName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? a.clientName
                                : (a.deviceId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Unknown device" : a.deviceId)
                            let lastText = a.lastSeenAtMs > 0 ? formatMs(a.lastSeenAtMs) : "(unknown)"

                            Text(title)
                                .font(.caption.weight(.semibold))

                            Text("ip \(a.peerIp) · \(a.count)x · last \(lastText)")
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)

                            if !a.expectedAllowedCidrs.isEmpty {
                                Text("Allowed CIDRs: " + a.expectedAllowedCidrs.joined(separator: ", "))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                    .textSelection(.enabled)
                            }

                            let did = a.deviceId.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !did.isEmpty, grpc.allowedClients.contains(where: { $0.deviceId == did }) {
                                HStack(spacing: 10) {
                                    Button("Add IP to Device") {
                                        grpc.addAllowedCidr(deviceId: did, value: a.peerIp)
                                    }
                                    .font(.caption)
                                    Button("Edit…") {
                                        if let c = grpc.allowedClients.first(where: { $0.deviceId == did }) {
                                            editingGRPCClient = c
                                        }
                                    }
                                    .font(.caption)
                                    Spacer()
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }

                if grpc.allowedClients.isEmpty {
                    Text("No clients yet.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    let statusById: [String: GRPCDeviceStatusEntry] = Dictionary(
                        uniqueKeysWithValues: grpcDevicesStatus.devices.map { ($0.deviceId, $0) }
                    )
                    ForEach(grpc.allowedClients) { c in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(c.name.isEmpty ? c.deviceId : c.name)
                                        .font(.caption.weight(.semibold))
                                    Text(c.deviceId)
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Edit…") { editingGRPCClient = c }
                                    .font(.caption)
                                Button("Copy Vars") { grpc.copyConnectVars(for: c) }
                                    .font(.caption)
                                Button(c.enabled ? "Disable" : "Enable") {
                                    grpc.setClientEnabled(deviceId: c.deviceId, enabled: !c.enabled)
                                }
                                .font(.caption)
                            }

                            Text(grpcClientSecuritySummary(c))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .textSelection(.enabled)

                            if let st = statusById[c.deviceId] {
                                Text(grpcClientStatusSummary(st))
                                    .font(.caption2)
                                    .foregroundStyle(st.connected ? Color.green : Color.secondary)
                                    .lineLimit(2)
                                    .textSelection(.enabled)

                                Text(grpcClientPolicyUsageSummary(st))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                    .textSelection(.enabled)

                                if let act = st.lastActivity {
                                    Text(grpcClientLastActivitySummary(act))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                        .textSelection(.enabled)
                                }

                                if !st.lastBlockedReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !st.lastDenyCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    Text(grpcClientLastBlockedSummary(st))
                                        .font(.caption2)
                                        .foregroundStyle(.orange)
                                        .lineLimit(2)
                                        .textSelection(.enabled)
                                }

                                if let series = st.tokenSeries5m1h, !series.points.isEmpty {
                                    TokenSparkline(
                                        points: series.points,
                                        strokeColor: st.connected ? .accentColor : Color.gray.opacity(0.7),
                                        lineWidth: 1.5
                                    )
                                    .frame(height: 18)
                                }

                                if st.dailyTokenCap > 0 {
                                    ProgressView(value: Double(st.dailyTokenUsed), total: Double(st.dailyTokenCap))
                                        .progressViewStyle(.linear)
                                    Text("Tokens (UTC \(st.quotaDay)): \(st.dailyTokenUsed)/\(st.dailyTokenCap) · remaining \(max(0, st.remainingDailyTokenBudget))")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                } else if st.dailyTokenUsed > 0 {
                                    Text("Tokens (UTC \(st.quotaDay)): \(st.dailyTokenUsed) (cap: unlimited)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }

                                if !st.modelBreakdown.isEmpty {
                                    DisclosureGroup("Usage details") {
                                        ForEach(Array(st.modelBreakdown.prefix(3))) { row in
                                            Text(grpcClientModelBreakdownSummary(row))
                                                .font(.caption2.monospaced())
                                                .foregroundStyle(.secondary)
                                                .textSelection(.enabled)
                                        }
                                    }
                                    .font(.caption2)
                                }
                            } else {
                                Text("Status: unknown (no event subscription yet)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Text("Clients file: \(grpc.clientsConfigURL().path)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                Text("Only enabled clients in this file can connect via LAN gRPC.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Divider()

                DisclosureGroup("Remote Mode (VPN / Tunnel)") {
                    Text("Recommendation: do NOT expose this gRPC port directly to the public Internet. Use a VPN (WireGuard / ZeroTier) or an encrypted tunnel (SSH) so gRPC stays inside a private network.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Text("Hardening (recommended): for each paired device, set Allowed CIDRs to the VPN subnet (e.g. `10.7.0.0/24`) and keep paid/web capabilities OFF unless needed.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Text("Admin RPCs are local-only by default (safer). If you must manage remotely, set `HUB_ADMIN_ALLOW_REMOTE=1` (or `HUB_ADMIN_ALLOWED_CIDRS=...`) when starting the server.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Button("Copy Remote Guide") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(Self.remoteModeGuideText, forType: .string)
                    }
                    .font(.caption)

                    Text(Self.remoteModeGuideText)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private func grpcClientSecuritySummary(_ c: HubGRPCClientEntry) -> String {
        let caps = c.capabilities
        let cidrs = c.allowedCidrs
        let user = c.userId.trimmingCharacters(in: .whitespacesAndNewlines)
        let cert = c.certSha256.trimmingCharacters(in: .whitespacesAndNewlines)

        let policyText: String = {
            if c.policyMode == .legacyGrant {
                return "Policy: legacy_grant"
            }
            guard let profile = c.approvedTrustProfile else {
                return "Policy: new_profile (missing payload)"
            }
            let paid = profile.paidModelPolicy.mode.rawValue
            let web = profile.networkPolicy.defaultWebFetchEnabled ? "web:on" : "web:off"
            let daily = profile.budgetPolicy.dailyTokenLimit > 0 ? "daily:\(profile.budgetPolicy.dailyTokenLimit)" : "daily:unset"
            return "Policy: new_profile [\(paid), \(web), \(daily)]"
        }()
        let capsText: String = {
            if caps.isEmpty { return "Caps: ALL (empty = allow all)" }
            return "Caps: " + caps.joined(separator: ", ")
        }()
        let cidrText: String = {
            if cidrs.isEmpty { return "IP: ANY (empty = allow any source IP)" }
            return "IP: " + cidrs.joined(separator: ", ")
        }()
        let certText: String = {
            if cert.isEmpty { return "mTLS: (not pinned)" }
            if cert.count <= 12 { return "mTLS: pin \(cert)" }
            return "mTLS: pin \(cert.prefix(8))…\(cert.suffix(4))"
        }()
        let userText = user.isEmpty ? "User: (device_id fallback)" : "User: \(user)"
        return "\(policyText) · \(userText) · \(capsText) · \(cidrText) · \(certText)"
    }

    private func grpcClientStatusSummary(_ st: GRPCDeviceStatusEntry) -> String {
        let ip = st.peerIp.trimmingCharacters(in: .whitespacesAndNewlines)
        let streams = max(0, st.activeEventSubscriptions)
        if st.connected {
            var parts: [String] = ["Status: connected"]
            if !ip.isEmpty { parts.append("ip \(ip)") }
            if streams > 1 { parts.append("streams \(streams)") }
            return parts.joined(separator: " · ")
        }
        let lastSeen = st.lastSeenAtMs > 0 ? "last seen \(formatMs(st.lastSeenAtMs))" : "never seen"
        if ip.isEmpty { return "Status: disconnected · \(lastSeen)" }
        return "Status: disconnected · \(lastSeen) · ip \(ip)"
    }


    private func grpcClientPolicyUsageSummary(_ st: GRPCDeviceStatusEntry) -> String {
        var parts: [String] = []
        let mode = st.paidModelPolicyMode.trimmingCharacters(in: .whitespacesAndNewlines)
        if !mode.isEmpty {
            parts.append("policy \(paidPolicyModeLabel(mode))")
        }
        parts.append(st.defaultWebFetchEnabled ? "web:on" : "web:off")
        if st.dailyTokenCap > 0 {
            parts.append("budget \(st.dailyTokenUsed)/\(st.dailyTokenCap)")
            parts.append("remaining \(max(0, st.remainingDailyTokenBudget))")
        }
        if !st.topModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append("top \(st.topModel)")
        }
        if st.requestsToday > 0 { parts.append("req \(st.requestsToday)") }
        if st.blockedToday > 0 { parts.append("blocked \(st.blockedToday)") }
        return parts.joined(separator: " · ")
    }

    private func grpcClientLastBlockedSummary(_ st: GRPCDeviceStatusEntry) -> String {
        let reason = st.lastBlockedReason.trimmingCharacters(in: .whitespacesAndNewlines)
        let code = st.lastDenyCode.trimmingCharacters(in: .whitespacesAndNewlines)
        if reason.isEmpty && code.isEmpty { return "Last blocked: none" }
        if reason.isEmpty { return "Last blocked: \(code)" }
        if code.isEmpty { return "Last blocked: \(reason)" }
        return "Last blocked: \(reason) · \(code)"
    }

    private func grpcClientModelBreakdownSummary(_ row: GRPCDeviceModelBreakdownEntry) -> String {
        var parts: [String] = [row.modelId]
        parts.append("tokens \(row.totalTokens)")
        parts.append("req \(row.requestCount)")
        if row.blockedCount > 0 { parts.append("blocked \(row.blockedCount)") }
        if row.lastUsedAtMs > 0 { parts.append("last \(formatMs(row.lastUsedAtMs))") }
        if row.lastBlockedAtMs > 0 {
            let code = row.lastDenyCode.trimmingCharacters(in: .whitespacesAndNewlines)
            parts.append(code.isEmpty ? "deny logged" : "deny \(code)")
        }
        return parts.joined(separator: " · ")
    }

    private func paidPolicyModeLabel(_ raw: String) -> String {
        switch raw {
        case "all_paid_models":
            return "all_paid_models"
        case "custom_selected_models":
            return "custom_selected_models"
        case "legacy_grant":
            return "legacy_grant"
        case "off":
            return "off"
        default:
            return raw.isEmpty ? "unset" : raw
        }
    }

    private func grpcClientLastActivitySummary(_ a: GRPCDeviceLastActivity) -> String {
        let model = a.modelId.trimmingCharacters(in: .whitespacesAndNewlines)
        let cap = a.capability.trimmingCharacters(in: .whitespacesAndNewlines)
        let at = a.createdAtMs > 0 ? formatMs(a.createdAtMs) : ""

        var parts: [String] = []
        if !model.isEmpty {
            parts.append("Last: \(model)")
        } else if !a.eventType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append("Last: \(a.eventType)")
        } else {
            parts.append("Last: (unknown)")
        }

        if !cap.isEmpty { parts.append(cap) }
        parts.append(a.networkAllowed ? "net:on" : "net:off")
        if a.totalTokens > 0 { parts.append("tokens \(a.totalTokens)") }
        parts.append(a.ok ? "ok" : "fail")
        if !at.isEmpty { parts.append(at) }
        if !a.ok {
            let code = a.errorCode.trimmingCharacters(in: .whitespacesAndNewlines)
            if !code.isEmpty { parts.append(code) }
        }
        return parts.joined(separator: " · ")
    }

    private func formatMs(_ ms: Int64) -> String {
        let secs = Double(ms) / 1000.0
        let d = Date(timeIntervalSince1970: secs)
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.string(from: d)
    }

    private static let remoteModeGuideText: String = """
Remote mode (VPN/Tunnel) checklist / 远程模式检查清单

1) Transport (recommended): WireGuard / ZeroTier. Avoid port-forwarding gRPC directly.
   传输层首选：WireGuard / ZeroTier（把终端变成“虚拟局域网”）。不要把 gRPC 端口直接映射到公网。

   Connect: on the Terminal device, set HUB_HOST to the Hub's VPN IP (or use an encrypted tunnel like SSH).
   连接方式：终端侧把 HUB_HOST 设置为 Hub 的 VPN IP（或用 SSH 等加密隧道把端口转发到本地）。

2) Per-device hardening: set Allowed CIDRs to your VPN subnet (e.g. 10.7.0.0/24).
   设备级加固：把 Allowed CIDRs 绑定到 VPN 子网（例如 10.7.0.0/24）。

3) Capability hardening: keep `ai.generate.paid` / `web.fetch` OFF unless needed.
   能力收敛：除非确实需要，否则不要给设备开启 `ai.generate.paid` / `web.fetch`。

4) Admin RPC: local-only by default. Only enable remote admin if required.
   管理端默认仅本机访问（更安全）。确实要远程管理时才放开。

Example Allowed CIDRs:
- private, loopback
- 100.64.0.0/10 (Tailscale/Headscale)
- 10.7.0.0/24
- 192.168.1.0/24,10.7.0.0/24
"""

    private var networkPoliciesSection: some View {
        Section("Network Policies") {
            HStack {
                Text("Policies")
                Spacer()
                Button("Add…") { showAddNetworkPolicy = true }
            }

            if networkPolicies.isEmpty {
                Text("No network policies yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(networkPolicies) { p in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(p.appId) · \(p.projectId)")
                            .font(.callout.weight(.semibold))
                        Text("模式：\(policyModeText(p.mode)) · 限制：\(policyLimitText(p.maxSeconds))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 10) {
                            Menu("Mode") {
                                Button("Manual") { updatePolicy(p, mode: .manual, maxSeconds: nil) }
                                Button("Auto-approve") { updatePolicy(p, mode: .autoApprove, maxSeconds: p.maxSeconds) }
                                Button("Always-on") { updatePolicy(p, mode: .alwaysOn, maxSeconds: p.maxSeconds) }
                                Button("Deny") { updatePolicy(p, mode: .deny, maxSeconds: nil) }
                            }
                            Menu("Limit") {
                                Button("No limit") { updatePolicy(p, mode: nil, maxSeconds: nil) }
                                Button("15m") { updatePolicy(p, mode: nil, maxSeconds: 15 * 60) }
                                Button("30m") { updatePolicy(p, mode: nil, maxSeconds: 30 * 60) }
                                Button("60m") { updatePolicy(p, mode: nil, maxSeconds: 60 * 60) }
                                Button("120m") { updatePolicy(p, mode: nil, maxSeconds: 120 * 60) }
                                Button("8h") { updatePolicy(p, mode: nil, maxSeconds: 8 * 60 * 60) }
                            }
                            Button("Remove") { removePolicy(p) }
                            Spacer()
                        }
                        .font(.caption)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private var routingSection: some View {
        Section("AI Routing") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Self.routingTaskTypes, id: \.self) { t in
                    HStack {
                        Text(t)
                            .font(.caption.monospaced())
                        Spacer()
                        TextField("model id", text: bindingRoutingModelId(t))
                            .textFieldStyle(.roundedBorder)
                            .font(.caption)
                            .frame(width: 320)
                    }
                }
                Text("Routing lives in Hub. Coder only requests a role; Hub decides the model.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var remoteModelsSection: some View {
        Section("Remote Models (Paid)") {
            HStack {
                Text("Remote Models")
                Spacer()
                Button("OpenCode Zen…") { showImportOpencodeZen = true }
                Button("Add…") { showAddRemoteModel = true }
            }
            if remoteModels.isEmpty {
                Text("No remote models yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(remoteModels) { m in
                    HStack(spacing: 10) {
                        Toggle("", isOn: bindingRemoteEnabled(m.id))
                            .labelsHidden()

                        VStack(alignment: .leading, spacing: 2) {
                            Text(m.name.isEmpty ? m.id : m.name)
                                .font(.callout.weight(.semibold))
                            Text(remoteModelSubtitle(m))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            keychainStatusLine(model: m)
                        }
                        Spacer()
                        Button("Remove") { removeRemoteModel(id: m.id) }
                    }
                }
            }
            Text("Enabled remote models are written into models_state.json as Loaded so X-Terminal can select them.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var skillsSection: some View {
        Section("Skills") {
            let storeDir = HubSkillsStoreStorage.skillsStoreDir()

            HStack {
                Text("Store")
                Spacer()
                Button("Reveal") {
                    try? FileManager.default.createDirectory(at: storeDir, withIntermediateDirectories: true)
                    NSWorkspace.shared.activateFileViewerSelecting([storeDir])
                }
                Button("Reload") {
                    reloadSkillsSnapshots()
                }
            }

            Text(storeDir.path)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .textSelection(.enabled)

            HStack {
                Text("Installed packages")
                Spacer()
                Text("\(skillsIndex.skills.count)")
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("Pins")
                Spacer()
                Text("MC \(skillsPins.memoryCorePins.count) · G \(skillsPins.globalPins.count) · P \(skillsPins.projectPins.count)")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if !skillsLastErrorText.isEmpty {
                Text(skillsLastErrorText)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            } else if !skillsLastActionText.isEmpty {
                Text(skillsLastActionText)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            } else {
                Text("Skills v1 is file-backed. Use Search + Pin to make them effective for a user/project.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("user_id")
                        .font(.caption.monospaced())
                    Spacer()
                    TextField("user_id (for Global/Project pins)", text: $skillsResolveUserId)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                        .frame(width: 320)
                }

                HStack {
                    Text("project_id")
                        .font(.caption.monospaced())
                    Spacer()
                    TextField("project_id (for Project pins)", text: $skillsResolveProjectId)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                        .frame(width: 320)
                }

                Text("Precedence: Memory-Core > Global(user_id) > Project(user_id+project_id).")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            DisclosureGroup("Resolved") {
                let resolved = HubSkillsStoreStorage.resolvedSkills(
                    index: skillsIndex,
                    pins: skillsPins,
                    userId: skillsResolveUserId,
                    projectId: skillsResolveProjectId
                )

                HStack(spacing: 10) {
                    Button("Copy Resolved") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(renderResolvedSkills(resolved), forType: .string)
                    }
                    Button("Open Pins File") {
                        let url = HubSkillsStoreStorage.skillsPinsURL()
                        let fm = FileManager.default
                        if !fm.fileExists(atPath: url.path) {
                            // Create an empty pins file so users can inspect/edit it directly.
                            let empty = HubSkillsStoreStorage.SkillPinsSnapshot(
                                schemaVersion: "skills_pins.v1",
                                updatedAtMs: 0,
                                memoryCorePins: [],
                                globalPins: [],
                                projectPins: []
                            )
                            try? HubSkillsStoreStorage.saveSkillPins(empty)
                        }
                        if fm.fileExists(atPath: url.path) {
                            NSWorkspace.shared.open(url)
                        } else {
                            NSWorkspace.shared.open(url.deletingLastPathComponent())
                        }
                    }
                    Spacer()
                }
                .font(.caption)

                if resolved.isEmpty {
                    Text("No resolved skills (set user_id/project_id and pin something).")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(resolved) { r in
                        skillResolvedRow(r)
                            .padding(.vertical, 3)
                    }
                }
            }

            DisclosureGroup("Pins") {
                Text("Memory-Core pins")
                    .font(.caption.weight(.semibold))
                if skillsPins.memoryCorePins.isEmpty {
                    Text("(none)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sortedPins(skillsPins.memoryCorePins)) { p in
                        skillPinRow(p, scope: .memoryCore)
                            .padding(.vertical, 3)
                    }
                }

                Divider()

                Text("Global pins")
                    .font(.caption.weight(.semibold))
                let uid = skillsResolveUserId.trimmingCharacters(in: .whitespacesAndNewlines)
                let globals = uid.isEmpty ? sortedPins(skillsPins.globalPins) : sortedPins(skillsPins.globalPins.filter { ($0.userId ?? "") == uid })
                if globals.isEmpty {
                    Text(uid.isEmpty ? "(none) · set user_id above to filter" : "(none)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(globals) { p in
                        skillPinRow(p, scope: .global)
                            .padding(.vertical, 3)
                    }
                }

                Divider()

                Text("Project pins")
                    .font(.caption.weight(.semibold))
                let pid = skillsResolveProjectId.trimmingCharacters(in: .whitespacesAndNewlines)
                let projects = (!uid.isEmpty && !pid.isEmpty)
                    ? sortedPins(skillsPins.projectPins.filter { ($0.userId ?? "") == uid && ($0.projectId ?? "") == pid })
                    : sortedPins(skillsPins.projectPins)
                if projects.isEmpty {
                    Text((!uid.isEmpty && !pid.isEmpty) ? "(none)" : "(none) · set user_id + project_id above to filter")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(projects) { p in
                        skillPinRow(p, scope: .project)
                            .padding(.vertical, 3)
                    }
                }
            }

            DisclosureGroup("Search") {
                TextField("search skill_id / name / description…", text: $skillsSearchQuery)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)

                let results = HubSkillsStoreStorage.searchSkills(index: skillsIndex, sources: skillsSources, query: skillsSearchQuery, limit: 30)
                if results.isEmpty {
                    Text(skillsSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "No skills yet." : "No matches.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(results) { meta in
                        skillMetaRow(meta)
                            .padding(.vertical, 4)
                    }
                }
            }
        }
    }

    private var advancedSection: some View {
        Section("Advanced") {
            DisclosureGroup("AI Runtime") {
                Toggle("Auto-start runtime", isOn: $store.aiRuntimeAutoStart)

                HStack {
                    Text("Status")
                    Spacer()
                    Text(store.aiRuntimeStatusText)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if !store.aiRuntimeLastError.isEmpty {
                    Text(store.aiRuntimeLastError)
                        .font(.caption2)
                        .foregroundStyle(.red)
                }

                HStack(spacing: 10) {
                    Button("Start") { store.startAIRuntime() }
                    Button("Stop") { store.stopAIRuntime() }
                    Button("Open Log") { store.openAIRuntimeLog() }
                    Spacer()
                }

                DisclosureGroup("Runtime Config") {
                    HStack {
                        Text("Python")
                        Spacer()
                        TextField("/path/to/python3", text: $store.aiRuntimePython)
                            .textFieldStyle(.roundedBorder)
                            .font(.caption)
                    }
                    Text("Runtime script is bundled with the app and auto-refreshed on updates.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            DisclosureGroup("AX Constitution") {
                HStack {
                    Text("Pinned policy file")
                    Spacer()
                    Button("Reload") { reloadAXConstitutionStatus() }
                    Button("Open…") { store.openAXConstitutionFile() }
                }
                let ver = axConstitutionVersion.trimmingCharacters(in: .whitespacesAndNewlines)
                HStack {
                    Text("Version")
                    Spacer()
                    Text(ver.isEmpty ? "(unknown)" : ver)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                let clauseSummary = axConstitutionEnabledClauseIds.isEmpty
                    ? "(none)"
                    : axConstitutionEnabledClauseIds.joined(separator: ", ")
                Text("Enabled clauses: \(clauseSummary)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                HStack(spacing: 10) {
                    Button("Copy Summary") { copyAXConstitutionSummaryToClipboard() }
                    Spacer()
                }
                Text(store.axConstitutionURL().path)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
                if !axConstitutionErrorText.isEmpty {
                    Text(axConstitutionErrorText)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
                Text("Tip: start the AI runtime once to generate the default file if it's missing.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            // FA Tracker launcher settings removed for teammate-facing builds.
        }
    }

    private var quitSection: some View {
        Section("Quit") {
            HStack(spacing: 10) {
                Button("Quit REL Flow Hub") { quitApp() }
                Spacer()
            }
            let ver = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? ""
            let build = (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? ""
            Text("Version \(ver) (\(build))")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func networkRequestCard(_ req: HubNetworkRequest) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Request from \(req.source ?? "unknown")")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let p = req.rootPath, !p.isEmpty {
                Text(p)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }

            if let r = req.reason, !r.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(r)
                    .font(.caption)
            }

            let secs = req.requestedSeconds ?? 900
            HStack(spacing: 10) {
                Button("Approve 5m") { store.approveNetworkRequest(req, seconds: 5 * 60) }
                Button("Approve 30m") { store.approveNetworkRequest(req, seconds: 30 * 60) }
                Button("Approve \(max(1, secs / 60))m") { store.approveNetworkRequest(req, seconds: secs) }
                Button("Dismiss") { store.dismissNetworkRequest(req) }
                Menu("Policy") {
                    Button("Always allow this project") {
                        // No explicit limit: "always on" will be kept alive automatically by Hub.
                        store.setNetworkPolicy(for: req, mode: .alwaysOn, maxSeconds: nil)
                        let requested = max(10, req.requestedSeconds ?? 900)
                        let secs = max(requested, 8 * 60 * 60)
                        store.approveNetworkRequest(req, seconds: secs)
                    }
                    Button("Auto-approve this project") {
                        let maxSecs = max(10, req.requestedSeconds ?? 900)
                        store.setNetworkPolicy(for: req, mode: .autoApprove, maxSeconds: maxSecs)
                        store.approveNetworkRequest(req, seconds: maxSecs)
                    }
                    Button("Always deny this project") {
                        store.setNetworkPolicy(for: req, mode: .deny, maxSeconds: nil)
                        store.dismissNetworkRequest(req)
                    }
                }
                Spacer()
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func keychainStatusLine(model: RemoteModelEntry) -> some View {
        let status = keychainStatus(model: model)
        Text(status.text)
            .font(.caption2)
            .foregroundStyle(status.color)
    }

    private static let routingTaskTypes: [String] = [
        "assist",
        "review",
        "advisor",
        "x_terminal_coarse",
        "x_terminal_refine",
        "ax_coder_coarse",
        "ax_coder_refine",
    ]

    private func bindingRoutingModelId(_ taskType: String) -> Binding<String> {
        Binding(
            get: { store.routingPreferredModelIdByTask[taskType] ?? "" },
            set: { s in
                let v = s.trimmingCharacters(in: .whitespacesAndNewlines)
                store.setRoutingPreferredModel(taskType: taskType, modelId: v.isEmpty ? nil : v)
            }
        )
    }

    private func bindingRemoteEnabled(_ id: String) -> Binding<Bool> {
        Binding(
            get: { remoteModels.first(where: { $0.id == id })?.enabled ?? false },
            set: { v in
                guard let idx = remoteModels.firstIndex(where: { $0.id == id }) else { return }
                remoteModels[idx].enabled = v
                persistRemoteModels()
            }
        )
    }

    private func upsertRemoteModel(_ entry: RemoteModelEntry) {
        upsertRemoteModels([entry])
    }

    private func upsertRemoteModels(_ entries: [RemoteModelEntry]) {
        guard !entries.isEmpty else { return }
        for entry in entries {
            if let idx = remoteModels.firstIndex(where: { $0.id == entry.id }) {
                remoteModels[idx] = entry
            } else {
                remoteModels.append(entry)
            }
        }
        remoteModels.sort { $0.id.localizedCaseInsensitiveCompare($1.id) == .orderedAscending }
        persistRemoteModels()
    }

    private func removeRemoteModel(id: String) {
        remoteModels.removeAll { $0.id == id }
        persistRemoteModels()
    }

    private func persistRemoteModels() {
        let snap = RemoteModelSnapshot(models: remoteModels, updatedAt: Date().timeIntervalSince1970)
        RemoteModelStorage.save(snap)
        ModelStore.shared.refresh()
    }

    private func importOpencodeZen(_ result: ImportOpencodeZenResult) {
        let apiKey = result.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else { return }

        let apiKeyRef = "opencode:default"

        let baseURL = OpencodeZenClient.defaultBaseURL.absoluteString
        let idPrefix = normalizeModelPrefix(result.idPrefix)

        var imported: [RemoteModelEntry] = []
        for raw in result.modelIds {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            let baseModelId = normalizeOpencodeZenModelId(trimmed)
            if baseModelId.isEmpty { continue }

            let fullId: String = {
                if idPrefix.isEmpty { return baseModelId }
                let a = baseModelId.lowercased()
                let p = idPrefix.lowercased()
                if a.hasPrefix(p) { return baseModelId }
                return idPrefix + baseModelId
            }()

            let entry = RemoteModelEntry(
                id: fullId,
                name: opencodeZenDisplayName(modelId: baseModelId),
                backend: "opencode_zen",
                contextLength: opencodeZenContextLength(modelId: baseModelId),
                enabled: result.enabled,
                baseURL: baseURL,
                apiKeyRef: apiKeyRef,
                upstreamModelId: baseModelId,
                apiKey: apiKey,
                note: "OpenCode Zen"
            )
            imported.append(entry)
        }

        if imported.isEmpty {
            return
        }

        var updated = remoteModels
        if result.replaceExisting {
            updated.removeAll { $0.backend.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "opencode_zen" }
        }
        for m in imported {
            if let idx = updated.firstIndex(where: { $0.id == m.id }) {
                updated[idx] = m
            } else {
                updated.append(m)
            }
        }
        updated.sort { $0.id.lowercased() < $1.id.lowercased() }
        remoteModels = updated
        persistRemoteModels()
    }

    private func normalizeModelPrefix(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return "" }
        // Normalize to "provider/".
        if !s.hasSuffix("/") {
            s += "/"
        }
        return s
    }

    private func normalizeOpencodeZenModelId(_ raw: String) -> String {
        RemoteProviderEndpoints.stripModelRef(raw)
    }

    private func opencodeZenDisplayName(modelId: String) -> String {
        let t = modelId.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return "" }
        let map: [String: String] = [
            "gpt-5.1-codex": "GPT-5.1 Codex",
            "gpt-5.1-codex-mini": "GPT-5.1 Codex Mini",
            "gpt-5.1-codex-max": "GPT-5.1 Codex Max",
            "gpt-5.2": "GPT-5.2",
            "gpt-5.1": "GPT-5.1",
            "claude-opus-4-5": "Claude Opus 4.5",
            "gemini-3-pro": "Gemini 3 Pro",
            "gemini-3-flash": "Gemini 3 Flash",
            "glm-4.7": "GLM-4.7",
        ]
        if let v = map[t.lowercased()] {
            return v
        }
        return t
    }

    private func opencodeZenContextLength(modelId: String) -> Int {
        let t = modelId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if t.isEmpty { return 128_000 }
        let map: [String: Int] = [
            "gpt-5.1-codex": 400_000,
            "gpt-5.1-codex-mini": 400_000,
            "gpt-5.1-codex-max": 400_000,
            "gpt-5.2": 400_000,
            "gpt-5.1": 400_000,
            "claude-opus-4-5": 200_000,
            "gemini-3-pro": 1_048_576,
            "gemini-3-flash": 1_048_576,
            "glm-4.7": 204_800,
        ]
        return map[t] ?? 128_000
    }

    private func reloadNetworkPolicies() {
        let list = HubNetworkPolicyStorage.load().policies
        networkPolicies = list.sorted {
            if $0.appId != $1.appId { return $0.appId < $1.appId }
            return $0.projectId < $1.projectId
        }
    }

    private func updatePolicy(_ rule: HubNetworkPolicyRule, mode: HubNetworkPolicyMode?, maxSeconds: Int?) {
        var r = rule
        if let m = mode { r.mode = m }
        r.maxSeconds = maxSeconds
        r.updatedAt = Date().timeIntervalSince1970
        _ = HubNetworkPolicyStorage.upsert(r)
        reloadNetworkPolicies()
    }

    private func removePolicy(_ rule: HubNetworkPolicyRule) {
        _ = HubNetworkPolicyStorage.remove(id: rule.id)
        reloadNetworkPolicies()
    }

    private func policyModeText(_ mode: HubNetworkPolicyMode) -> String {
        switch mode {
        case .manual: return "手动审批"
        case .autoApprove: return "自动批准"
        case .alwaysOn: return "总是允许"
        case .deny: return "总是拒绝"
        }
    }

    private func policyLimitText(_ maxSeconds: Int?) -> String {
        guard let s = maxSeconds, s > 0 else { return "默认" }
        let mins = max(1, s / 60)
        if mins >= 60 {
            let hours = max(1, mins / 60)
            return "\(hours) 小时"
        }
        return "\(mins) 分钟"
    }

    private func remoteModelSubtitle(_ model: RemoteModelEntry) -> String {
        let upstream = (model.upstreamModelId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let keyRef = (model.apiKeyRef ?? model.id).trimmingCharacters(in: .whitespacesAndNewlines)
        if upstream.isEmpty || upstream == model.id {
            return "\(model.id) · \(model.backend) · ctx \(model.contextLength) · key \(keyRef)"
        }
        return "\(model.id) -> \(upstream) · \(model.backend) · ctx \(model.contextLength) · key \(keyRef)"
    }

    private func keychainStatus(model: RemoteModelEntry) -> (text: String, color: Color) {
        let inMemory = (model.apiKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !inMemory.isEmpty {
            if KeychainStore.hasSharedAccessGroup {
                return ("API Key: 已设置（Keychain + 加密）", .secondary)
            }
            return ("API Key: 已设置（加密）", .secondary)
        }

        let hasEncrypted = !(model.apiKeyCiphertext ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let acct = (model.apiKeyRef ?? model.id).trimmingCharacters(in: .whitespacesAndNewlines)

        // Avoid triggering repeated Keychain prompts in ad-hoc/dev builds (no shared access group).
        if !KeychainStore.hasSharedAccessGroup {
            if hasEncrypted {
                return ("API Key: 已设置（加密，当前会话未解锁）", .orange)
            }
            return ("API Key: 未设置", .red)
        }

        switch KeychainStore.read(account: acct) {
        case .value:
            return ("API Key: 已设置（Keychain）", .secondary)
        case .notFound:
            if hasEncrypted {
                return ("API Key: 已设置（加密，当前会话未解锁）", .orange)
            }
            return ("API Key: 未设置", .red)
        case .error(let msg):
            if hasEncrypted {
                return ("API Key: 已设置（加密，Keychain错误）", .orange)
            }
            return ("API Key: Keychain 错误 (\(msg))", .red)
        }
    }
}

private struct AddGRPCClientSheet: View {
    let onAdd: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pair New Device")
                .font(.headline)

            TextField("Device name (optional)", text: $name)
                .textFieldStyle(.roundedBorder)

            Text("Tip: this adds a token entry to the Hub allowlist and copies connect vars. If the Hub is in mTLS mode, prefer the Bootstrap command (axhubctl) so the Hub can issue a client certificate.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Create & Copy") {
                    onAdd(name)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 420)
    }
}

private struct EditGRPCClientSheet: View {
    let client: HubGRPCClientEntry
    let serverPort: Int
    let onSave: (HubGRPCClientEntry) -> Void
    let onRotateToken: (String) -> String?
    let onCopyVars: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var userId: String
    @State private var enabled: Bool
    @State private var token: String
    @State private var createdAtMs: Int64
    @State private var allowAnySourceIP: Bool
    @State private var allowedCidrs: [String]
    @State private var allowedCidrsBackup: [String]
    @State private var addCidrText: String
    @State private var caps: Set<String>
    @State private var certSha256: String
    @State private var policyMode: HubGRPCClientPolicyMode
    @State private var paidModelSelectionMode: HubPaidModelSelectionMode
    @State private var allowedPaidModelsText: String
    @State private var defaultWebFetchEnabled: Bool
    @State private var dailyTokenLimitText: String

    init(
        client: HubGRPCClientEntry,
        serverPort: Int,
        onSave: @escaping (HubGRPCClientEntry) -> Void,
        onRotateToken: @escaping (String) -> String?,
        onCopyVars: @escaping (String) -> Void
    ) {
        self.client = client
        self.serverPort = serverPort
        self.onSave = onSave
        self.onRotateToken = onRotateToken
        self.onCopyVars = onCopyVars

        _name = State(initialValue: client.name)
        _userId = State(initialValue: client.userId)
        _enabled = State(initialValue: client.enabled)
        _token = State(initialValue: client.token)
        _createdAtMs = State(initialValue: client.createdAtMs)
        let initialCidrs = Self.normalizeAllowedCidrs(client.allowedCidrs)
        let allowAny = initialCidrs.isEmpty
        _allowAnySourceIP = State(initialValue: allowAny)
        // When allow-any is enabled, keep a safe restore set so users can flip back without rebuilding rules.
        let backup = allowAny ? ["private", "loopback"] : initialCidrs
        _allowedCidrs = State(initialValue: backup)
        _allowedCidrsBackup = State(initialValue: backup)
        _addCidrText = State(initialValue: "")
        _caps = State(initialValue: Set(client.capabilities))
        _certSha256 = State(initialValue: client.certSha256)
        let profile = client.approvedTrustProfile
        let legacyPaidEnabled = client.capabilities.contains("ai.generate.paid")
        let legacyWebFetchEnabled = client.capabilities.contains("web.fetch")
        _policyMode = State(initialValue: client.policyMode)
        _paidModelSelectionMode = State(initialValue: profile?.paidModelPolicy.mode ?? (legacyPaidEnabled ? .allPaidModels : .off))
        _allowedPaidModelsText = State(initialValue: (profile?.paidModelPolicy.allowedModelIds ?? []).joined(separator: ", "))
        _defaultWebFetchEnabled = State(initialValue: profile?.networkPolicy.defaultWebFetchEnabled ?? legacyWebFetchEnabled)
        let initialDailyTokenLimit = profile?.budgetPolicy.dailyTokenLimit ?? HubTrustProfileDefaults.dailyTokenLimit
        _dailyTokenLimitText = State(initialValue: String(max(1, initialDailyTokenLimit)))
    }

    private struct CapSpec: Identifiable {
        var key: String
        var title: String
        var detail: String
        var id: String { key }
    }

    private static let capSpecs: [CapSpec] = [
        CapSpec(key: "models", title: "Models", detail: "Allow listing Hub model catalog"),
        CapSpec(key: "events", title: "Events", detail: "Allow subscribing to Hub push events (grants/quota/killswitch/requests)"),
        CapSpec(key: "memory", title: "Memory", detail: "Allow Hub-side thread + canonical memory RPCs"),
        CapSpec(key: "skills", title: "Skills", detail: "Allow HubSkills search/import/pin/resolve/download RPCs"),
        CapSpec(key: "ai.generate.local", title: "Local AI", detail: "Allow local/offline inference on Hub"),
        CapSpec(key: "ai.generate.paid", title: "Paid AI", detail: "Allow requesting/using paid models (still grant-gated)"),
        CapSpec(key: "web.fetch", title: "Web Fetch", detail: "Allow requesting/using web.fetch (still grant-gated)"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Edit Paired Device")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    var out = client
                    let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    let effectiveName = trimmedName.isEmpty ? client.deviceId : trimmedName
                    out.name = effectiveName
                    out.userId = userId.trimmingCharacters(in: .whitespacesAndNewlines)
                    out.enabled = enabled
                    out.token = token.trimmingCharacters(in: .whitespacesAndNewlines)
                    out.createdAtMs = createdAtMs
                    out.allowedCidrs = allowAnySourceIP ? [] : orderedAllowedCidrs(allowedCidrs)
                    out.certSha256 = certSha256.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    if policyMode == .newProfile {
                        let profile = HubGRPCClientEntry.buildApprovedTrustProfile(
                            deviceId: client.deviceId,
                            deviceName: effectiveName,
                            requestedCapabilities: orderedCaps(Array(caps)),
                            paidModelSelectionMode: paidModelSelectionMode,
                            allowedPaidModels: parseList(allowedPaidModelsText),
                            defaultWebFetchEnabled: defaultWebFetchEnabled,
                            dailyTokenLimit: parsedDailyTokenLimit ?? HubTrustProfileDefaults.dailyTokenLimit,
                            auditRef: client.deviceId
                        )
                        out.policyMode = .newProfile
                        out.approvedTrustProfile = profile
                        out.capabilities = profile.capabilities
                    } else {
                        out.policyMode = .legacyGrant
                        out.approvedTrustProfile = nil
                        out.capabilities = orderedCaps(Array(caps))
                    }
                    onSave(out)
                    dismiss()
                }
                .disabled(!allowedCidrsConfigIsValid || !policyProfileIsValid)
                .keyboardShortcut(.defaultAction)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Device ID")
                    Spacer()
                    Text(client.deviceId)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Toggle("Enabled", isOn: $enabled)
                TextField("Display name (optional)", text: $name)
                    .textFieldStyle(.roundedBorder)
                TextField("User ID (optional; empty = device_id)", text: $userId)
                    .textFieldStyle(.roundedBorder)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Policy Mode")
                    .font(.callout.weight(.semibold))
                Picker("Policy Mode", selection: $policyMode) {
                    ForEach(HubGRPCClientPolicyMode.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                if policyMode == .newProfile {
                    Picker("Paid Models", selection: $paidModelSelectionMode) {
                        ForEach(HubPaidModelSelectionMode.allCases, id: \.self) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    if paidModelSelectionMode == .customSelectedModels {
                        TextField("Allowed paid models (comma or newline separated)", text: $allowedPaidModelsText)
                            .textFieldStyle(.roundedBorder)
                        if parseList(allowedPaidModelsText).isEmpty {
                            Text("Custom Selected Models requires at least one model id.")
                                .font(.caption2)
                                .foregroundStyle(.red)
                        }
                    }

                    Toggle("Default Web Fetch Enabled", isOn: $defaultWebFetchEnabled)

                    TextField("Daily token limit", text: $dailyTokenLimitText)
                        .textFieldStyle(.roundedBorder)
                    if parsedDailyTokenLimit == nil {
                        Text("Daily token limit must be a positive integer.")
                            .font(.caption2)
                            .foregroundStyle(.red)
                    } else {
                        Text("Policy profiles persist as policy_mode=new_profile with device-level paid-model, web-fetch, and budget boundaries.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Legacy Grant keeps the current capability/grant path. Existing paired devices stay compatible until you explicitly switch to Policy Profile.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Capabilities")
                        .font(.callout.weight(.semibold))
                    Spacer()
                    Button("Local-only") {
                        caps = Set(["models", "events", "memory", "skills", "ai.generate.local"])
                    }
                    .font(.caption)
                    Button("Full") {
                        caps = Set(["models", "events", "memory", "skills", "ai.generate.local", "ai.generate.paid", "web.fetch"])
                    }
                    .font(.caption)
                }

                ForEach(Self.capSpecs) { spec in
                    Toggle(isOn: bindingCap(spec.key)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(spec.title)
                                .font(.caption.weight(.semibold))
                            Text(spec.detail)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if policyMode == .newProfile {
                    Text("In Policy Profile mode, paid-model and web-fetch capability bits are derived from the policy fields above when you save.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if caps.isEmpty {
                    Text("Warning: empty capabilities list means the device is allowed to call ALL RPCs (backward compatible but unsafe).")
                        .font(.caption2)
                        .foregroundStyle(.red)
                } else {
                    Text("Note: Paid AI / Web Fetch still require a time-limited grant and Bridge enable; this only allows the device to request/use them.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Allowed CIDRs (Source IP)")
                        .font(.callout.weight(.semibold))
                    Spacer()
                    Button("LAN only") {
                        allowAnySourceIP = false
                        allowedCidrs = ["private", "loopback"]
                        allowedCidrsBackup = allowedCidrs
                    }
                        .font(.caption)
                    Button("Any") { allowAnySourceIP = true }
                        .font(.caption)
                }

                Toggle(
                    "Allow any source IP (unsafe)",
                    isOn: Binding(
                        get: { allowAnySourceIP },
                        set: { on in
                            if on {
                                allowedCidrsBackup = orderedAllowedCidrs(allowedCidrs)
                                allowAnySourceIP = true
                            } else {
                                allowAnySourceIP = false
                                let restore = orderedAllowedCidrs(allowedCidrsBackup)
                                allowedCidrs = restore.isEmpty ? ["private", "loopback"] : restore
                            }
                        }
                    )
                )

                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Allow private (RFC1918)", isOn: bindingAllowedCidrRule("private"))
                    Toggle("Allow loopback (localhost)", isOn: bindingAllowedCidrRule("loopback"))

                    let customs = allowedCidrsCustomItems
                    if !customs.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Custom CIDRs / IPs")
                                .font(.caption.weight(.semibold))
                            ForEach(customs, id: \.self) { v in
                                HStack(spacing: 8) {
                                    Text(v)
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                    Spacer()
                                    Button("Remove") { removeAllowedCidrValue(v) }
                                        .font(.caption)
                                }
                            }
                        }
                    }

                    HStack(spacing: 8) {
                        TextField("Add CIDR/IP (e.g. 10.7.0.0/24)", text: $addCidrText)
                            .textFieldStyle(.roundedBorder)
                        Button("Add") { addAllowedCidrsFromText(addCidrText) }
                            .font(.caption)
                            .disabled(addCidrText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .disabled(allowAnySourceIP)

                if allowAnySourceIP {
                    Text("Warning: allow-any means any source IP is accepted. For remote mode, set this to your VPN subnet and keep paid/web caps OFF unless needed.")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                } else if !allowedCidrsConfigIsValid {
                    Text("Invalid: restricted mode requires at least one rule (otherwise it behaves like ANY). Add your VPN subnet (e.g. 10.7.0.0/24) or enable LAN-only.")
                        .font(.caption2)
                        .foregroundStyle(.red)
                } else {
                    Text("Supported: `private`, `loopback`, exact IP, or IPv4 CIDR (e.g. 10.7.0.0/24).")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("mTLS Cert Pin (sha256)")
                        .font(.callout.weight(.semibold))
                    Spacer()
                    Button("Clear") { certSha256 = "" }
                        .font(.caption)
                }
                TextField("Optional (hex). Leave empty to allow any client cert (unsafe in mTLS mode).", text: $certSha256)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption2.monospaced())
                Text("Tip: when the Hub is running in mTLS mode, set this to bind the device token to a specific client certificate fingerprint.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Divider()

            HStack(spacing: 10) {
                Button("Copy Vars (LAN)") { onCopyVars(token) }
                    .font(.caption)
                Button("Copy Vars (Remote)") {
                    let p = max(1, min(65535, serverPort))
                    let snippet = """
HUB_HOST=<hub_vpn_ip_or_tunnel>
HUB_PORT=\(p)
HUB_CLIENT_TOKEN='\(token)'
"""
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(snippet, forType: .string)
                }
                .font(.caption)
                Button("Rotate Token") {
                    if let newToken = onRotateToken(client.deviceId) {
                        token = newToken
                        createdAtMs = Int64(Date().timeIntervalSince1970 * 1000.0)
                    }
                }
                .font(.caption)
                Spacer()
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(width: 520)
    }

    private func bindingCap(_ key: String) -> Binding<Bool> {
        Binding(
            get: { caps.contains(key) },
            set: { on in
                if on { caps.insert(key) } else { caps.remove(key) }
            }
        )
    }

    private var parsedDailyTokenLimit: Int? {
        let trimmed = dailyTokenLimitText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Int(trimmed), value > 0 else { return nil }
        return value
    }

    private var policyProfileIsValid: Bool {
        guard policyMode == .newProfile else { return true }
        guard parsedDailyTokenLimit != nil else { return false }
        if paidModelSelectionMode == .customSelectedModels {
            return !parseList(allowedPaidModelsText).isEmpty
        }
        return true
    }

    private var allowedCidrsConfigIsValid: Bool {
        // Empty allowed_cidrs means "allow any source IP" on the server, which is only intended when
        // allowAnySourceIP is enabled. In restricted mode, enforce at least one rule so the UI intent matches reality.
        if allowAnySourceIP { return true }
        return !orderedAllowedCidrs(allowedCidrs).isEmpty
    }

    private var allowedCidrsCustomItems: [String] {
        let norm = Self.normalizeAllowedCidrs(allowedCidrs)
        return norm.filter { v in
            let lower = v.lowercased()
            return lower != "private" && lower != "loopback"
        }
    }

    private func bindingAllowedCidrRule(_ rule: String) -> Binding<Bool> {
        let key = rule.lowercased()
        return Binding(
            get: { Self.normalizeAllowedCidrs(allowedCidrs).contains(where: { $0.lowercased() == key }) },
            set: { on in
                if on { addAllowedCidrValue(key) } else { removeAllowedCidrValue(key) }
            }
        )
    }

    private func addAllowedCidrsFromText(_ text: String) {
        let parts = text
            .split(whereSeparator: { ch in
                ch == "," || ch == "\n" || ch == ";" || ch == "\t"
            })
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !parts.isEmpty else { return }
        for p in parts {
            addAllowedCidrValue(p)
        }
        addCidrText = ""
    }

    private func addAllowedCidrValue(_ value: String) {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        // Treat allow-all aliases as "Any" mode for clarity.
        let lower = cleaned.lowercased()
        if lower == "any" || lower == "*" {
            allowAnySourceIP = true
            return
        }
        allowAnySourceIP = false

        var cur = Self.normalizeAllowedCidrs(allowedCidrs)
        let canon: String = {
            if lower == "localhost" { return "loopback" }
            if lower == "loopback" { return "loopback" }
            if lower == "private" { return "private" }
            return cleaned
        }()
        if cur.contains(where: { $0.lowercased() == canon.lowercased() }) {
            allowedCidrs = orderedAllowedCidrs(cur)
            return
        }
        cur.append(canon)
        allowedCidrs = orderedAllowedCidrs(cur)
        allowedCidrsBackup = orderedAllowedCidrs(cur)
    }

    private func removeAllowedCidrValue(_ value: String) {
        let key = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !key.isEmpty else { return }
        var cur = Self.normalizeAllowedCidrs(allowedCidrs)
        cur.removeAll { $0.lowercased() == key }
        allowedCidrs = orderedAllowedCidrs(cur)
        allowedCidrsBackup = orderedAllowedCidrs(cur)
    }

    private func orderedAllowedCidrs(_ list: [String]) -> [String] {
        let clean = Self.normalizeAllowedCidrs(list)
        if clean.isEmpty { return [] }

        // Keep stable order but pull well-known rules to the front.
        let order = ["private", "loopback"]
        var out: [String] = []
        for k in order {
            if clean.contains(where: { $0.lowercased() == k }) { out.append(k) }
        }
        out.append(contentsOf: clean.filter { v in
            let lower = v.lowercased()
            return !order.contains(lower)
        })
        return out
    }

    private static func normalizeAllowedCidrs(_ list: [String]) -> [String] {
        let raw = list
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if raw.contains(where: { s in
            let lower = s.lowercased()
            return lower == "any" || lower == "*"
        }) {
            return []
        }

        // De-dup while preserving order.
        var seen = Set<String>()
        var out: [String] = []
        for s in raw {
            let lower = s.lowercased()
            let canon: String = {
                if lower == "localhost" { return "loopback" }
                if lower == "loopback" { return "loopback" }
                if lower == "private" { return "private" }
                return s
            }()
            let key = canon.lowercased()
            if seen.contains(key) { continue }
            seen.insert(key)
            out.append(canon)
        }
        return out
    }

    private func orderedCaps(_ list: [String]) -> [String] {
        let clean = list.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        if clean.isEmpty { return [] }

        let order = Self.capSpecs.map { $0.key }
        let known = clean.filter { order.contains($0) }
        let unknown = clean.filter { !order.contains($0) }

        var out: [String] = []
        for k in order {
            if known.contains(k) { out.append(k) }
        }
        // Keep unknowns stable-ish.
        out.append(contentsOf: unknown.sorted())

        // De-dup while preserving out order.
        var seen = Set<String>()
        var uniq: [String] = []
        for c in out {
            if seen.contains(c) { continue }
            seen.insert(c)
            uniq.append(c)
        }
        return uniq
    }

    private func parseList(_ text: String) -> [String] {
        let raw = text
            .split(whereSeparator: { ch in
                ch == "," || ch == "\n" || ch == ";" || ch == "\t"
            })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if raw.isEmpty { return [] }

        // De-dup while preserving order.
        var seen = Set<String>()
        var out: [String] = []
        for s in raw {
            if seen.contains(s) { continue }
            seen.insert(s)
            out.append(s)
        }
        return out
    }
}

extension SettingsSheetView {
    private func openDockAgentApp() {
        // Prefer LaunchServices lookup by bundle id.
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.rel.flowhub.dockagent") {
            NSWorkspace.shared.open(url)
            return
        }

        // Dev convention: Dock Agent app is placed next to Hub app in the build output.
        let hubBundle = Bundle.main.bundleURL
        let dir = hubBundle.deletingLastPathComponent()
        let agent = dir.appendingPathComponent("RELFlowHubDockAgent.app")
        if FileManager.default.fileExists(atPath: agent.path) {
            NSWorkspace.shared.open(agent)
        }
    }

    private func badgeDetailText(dedupeKey: String, isEnabled: Bool) -> String {
        // Dock badge integrations require Accessibility.
        if isEnabled, (dedupeKey == "mail_unread" || dedupeKey == "messages_unread" || dedupeKey == "slack_updates"),
           !DockBadgeReader.ensureAccessibilityTrusted(prompt: false) {
            return "Need Accessibility"
        }
        if let n = store.notifications.first(where: { $0.dedupeKey == dedupeKey }) {
            let c = firstInt(in: n.title) ?? firstInt(in: n.body) ?? 0
            if c > 0 {
                return "\(c) unread"
            }
            return "No unread"
        }
        return "No unread"
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
}

private struct IntegrationToggleRow: View {
    let systemImage: String
    let title: String
    let detail: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .frame(width: 18)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.semibold))
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
        }
        .padding(.vertical, 2)
    }
}
