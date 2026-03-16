import SwiftUI

struct XTSettingsSectionDescriptor: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let title: String
    let summary: String
    let repairEntry: String
}

enum XTSettingsCenterManifest {
    static let releaseScope = "XT-W3-23 -> XT-W3-24 -> XT-W3-25 mainline only"
    static let sections: [XTSettingsSectionDescriptor] = [
        XTSettingsSectionDescriptor(id: "pair_hub", title: "Pair Hub", summary: "配对、Pairing Port / gRPC Port / Internet Host 与 reconnect smoke 都从这里开始。", repairEntry: "XT Settings → Pair Hub"),
        XTSettingsSectionDescriptor(id: "choose_model", title: "Choose Model", summary: "为首个任务选择 Hub 模型，避免把模型缺失误判成 grant 问题。", repairEntry: "XT Settings → Choose Model"),
        XTSettingsSectionDescriptor(id: "grant_permissions", title: "Grant & Permissions", summary: "集中处理 grant_required / permission_denied / hub_unreachable。", repairEntry: "XT Settings → Grant & Repair"),
        XTSettingsSectionDescriptor(id: "security_runtime", title: "Security & Runtime", summary: "保留本地 HTTP server 与安全边界相关开关。", repairEntry: "XT Settings → Security & Runtime"),
        XTSettingsSectionDescriptor(id: "diagnostics", title: "Diagnostics", summary: "统一查看当前连接摘要、verify readiness、日志与修复线索。", repairEntry: "XT Settings → Diagnostics")
    ]

    static let consumedFrozenFields: [String] = [
        "xt.ui_information_architecture.v1",
        "xt.ui_design_token_bundle.v1",
        "xt.ui_surface_state_contract.v1",
        "xt.ui_release_scope_badge.v1",
        "xt.one_shot_run_state.v1.state",
        "xt.delivery_scope_freeze.v1.validated_scope",
        "xt.unblock_baton.v1",
        "xt.delivery_scope_freeze.v1",
        "xt.one_shot_autonomy_policy.v1",
        "xt.one_shot_replay_regression.v1"
    ]
}

struct XTSettingsSurfaceState: Codable, Equatable, Sendable {
    let hubConnected: Bool
    let remoteConnected: Bool
    let linking: Bool
    let localServerEnabled: Bool
    let serverRunning: Bool
    let failureCode: String
    let runtime: UIFailClosedRuntimeSnapshot
    let doctor: XTUnifiedDoctorReport

    init(
        hubConnected: Bool,
        remoteConnected: Bool,
        linking: Bool,
        localServerEnabled: Bool,
        serverRunning: Bool,
        failureCode: String,
        runtime: UIFailClosedRuntimeSnapshot,
        doctor: XTUnifiedDoctorReport = .empty
    ) {
        self.hubConnected = hubConnected
        self.remoteConnected = remoteConnected
        self.linking = linking
        self.localServerEnabled = localServerEnabled
        self.serverRunning = serverRunning
        self.failureCode = failureCode
        self.runtime = runtime
        self.doctor = doctor
    }

    var hubInteractive: Bool {
        hubConnected || remoteConnected
    }
}

enum XTSettingsSurfacePlanner {
    static func status(for state: XTSettingsSurfaceState) -> StatusExplanation {
        let issue = UITroubleshootKnowledgeBase.issue(forFailureCode: state.failureCode) ?? state.runtime.primaryIssue
        let machineStatusRef = [
            "hub_connected=\(state.hubConnected)",
            "remote_connected=\(state.remoteConnected)",
            "linking=\(state.linking)",
            "local_server_enabled=\(state.localServerEnabled)",
            "server_running=\(state.serverRunning)",
            "failure_code=\(state.failureCode.isEmpty ? "none" : state.failureCode)",
            state.runtime.machineStatusSegment
        ].joined(separator: "; ")

        if let issue {
            return StatusExplanation(
                state: issue == .grantRequired ? .grantRequired : issue == .permissionDenied ? .permissionDenied : .diagnosticRequired,
                headline: "XT Settings 当前优先处理：\(issue.title)",
                whatHappened: "AI-4 已把高频问题收敛到 Pair Hub / Grant & Repair / Diagnostics 三个入口；本轮还把 denyCode / replay / baton 一并贴到同一状态卡。",
                whyItHappened: "本轮直接消费 AI-3 冻结的 state semantics 与 AI-2 的 runtime 合同，使 XT / Home / Cockpit / Settings 的状态口径一致。",
                userAction: state.runtime.nextRepairAction ?? UITroubleshootKnowledgeBase.guide(for: issue).steps.first?.instruction ?? "先按排障主链继续。",
                machineStatusRef: machineStatusRef,
                hardLine: "badge 文案与 action IDs 不再漂移",
                highlights: mergedHighlights([
                    "primary_sections=pair_hub,choose_model,grant_permissions,security_runtime,diagnostics"
                ], runtime: state.runtime)
            )
        }

        if state.runtime.scopeDecision == DeliveryScopeFreezeDecision.noGo.rawValue {
            return StatusExplanation(
                state: .blockedWaitingUpstream,
                headline: "XT Settings 检测到 scope freeze=NO_GO",
                whatHappened: "当前请求已碰到 release freeze 的 fail-closed 边界，因此 settings 只继续展示 validated mainline 所允许的入口。",
                whyItHappened: "AI-4 直接消费 xt.delivery_scope_freeze.v1.decision / blocked_expansion_items，避免 UI 把超范围能力说成可用。",
                userAction: state.runtime.scopeNextActions.first ?? "先 drop scope expansion，再回 validated mainline。",
                machineStatusRef: machineStatusRef,
                hardLine: ValidatedScopePresentation.validatedMainlineOnly.hardLine,
                highlights: mergedHighlights([
                    "release_scope=validated-mainline-only"
                ], runtime: state.runtime)
            )
        }

        if state.runtime.replayBlocked {
            return StatusExplanation(
                state: .diagnosticRequired,
                headline: "XT Settings 当前优先处理：Replay Regression",
                whatHappened: "配对与设置入口已经齐备，但 replay harness 仍未通过，当前不能把 smoke 或首个任务伪装成 green。",
                whyItHappened: "xt.one_shot_replay_regression.v1.pass / scenarios 已接入 settings 状态层，并保持 fail-closed。",
                userAction: state.runtime.nextRepairAction ?? "先到 Diagnostics 查看 replay denyCode / scenario，再重跑 smoke。",
                machineStatusRef: machineStatusRef,
                hardLine: ValidatedScopePresentation.validatedMainlineOnly.hardLine,
                highlights: mergedHighlights([
                    "replay_fail_closed=true"
                ], runtime: state.runtime)
            )
        }

        return StatusExplanation(
            state: state.hubInteractive ? .ready : .blockedWaitingUpstream,
            headline: state.hubInteractive ? "XT Settings 已对齐 validated mainline 主链" : "XT Settings 已就绪，但 Hub 仍待接入",
            whatHappened: "设置中心不再堆叠底层工程选项，而是先回答 pair / model / grant / diagnostics 四个主问题。",
            whyItHappened: "本轮目标是让新用户能完成首用路径，老用户能在 3 步内定位 grant / permission / unreachable 修复入口。",
            userAction: state.hubInteractive ? "继续 Reconnect Smoke 或返回 Home / Supervisor 开始首个任务。" : "先完成 Pair Hub，再回来选择模型和处理授权。",
            machineStatusRef: machineStatusRef,
            hardLine: ValidatedScopePresentation.validatedMainlineOnly.hardLine,
            highlights: mergedHighlights([
                "primary_sections=pair_hub,choose_model,grant_permissions,security_runtime,diagnostics",
                "release_scope=validated-mainline-only"
            ], runtime: state.runtime)
        )
    }

    static func quickActions(for state: XTSettingsSurfaceState) -> [PrimaryActionRailAction] {
        [
            PrimaryActionRailAction(
                id: "pair_hub",
                title: "Pair Hub",
                subtitle: "从 One-Click Setup 开始首用路径",
                systemImage: "link.badge.plus",
                style: .primary
            ),
            PrimaryActionRailAction(
                id: "run_smoke",
                title: "Run Reconnect Smoke",
                subtitle: runSmokeSubtitle(runtime: state.runtime),
                systemImage: "bolt.horizontal.circle",
                style: .secondary
            ),
            PrimaryActionRailAction(
                id: "review_grants",
                title: "Review Grants",
                subtitle: reviewSubtitle(issue: issue(for: state), runtime: state.runtime),
                systemImage: "checkmark.shield",
                style: .diagnostic
            )
        ]
    }

    static func diagnosticsLines(for state: XTSettingsSurfaceState) -> [String] {
        Self.orderedUnique([
            "current_route=\(state.remoteConnected ? "remote" : state.hubConnected ? "local" : "disconnected")",
            "local_server=\(state.localServerEnabled ? (state.serverRunning ? "enabled_running" : "enabled_idle") : "disabled")"
        ] + state.runtime.diagnosticsLines)
    }

    private static func issue(for state: XTSettingsSurfaceState) -> UITroubleshootIssue? {
        UITroubleshootKnowledgeBase.issue(forFailureCode: state.failureCode) ?? state.runtime.primaryIssue
    }

    private static func mergedHighlights(_ highlights: [String], runtime: UIFailClosedRuntimeSnapshot) -> [String] {
        orderedUnique(highlights + runtime.statusHighlights + XTSettingsCenterManifest.consumedFrozenFields + runtime.consumedContracts.map({ "runtime_contract=\($0)" }))
    }

    private static func runSmokeSubtitle(runtime: UIFailClosedRuntimeSnapshot) -> String {
        if runtime.replayPass == true {
            return "replay regression PASS；验证 pair + model + grant 已连通"
        }
        if runtime.replayPass == false {
            return "replay fail-closed；先看 denyCode / diagnostics"
        }
        return "验证 pair + model + grant 已连通"
    }

    private static func reviewSubtitle(issue: UITroubleshootIssue?, runtime: UIFailClosedRuntimeSnapshot) -> String {
        if let issue {
            return "\(issue.rawValue) → \(runtime.nextRepairAction ?? "open_repair_entry")"
        }
        if !runtime.nextDirectedAction.isEmpty {
            return "resume baton: \(runtime.nextDirectedAction)"
        }
        if let denyCode = runtime.launchDenyCodes.first(where: { !$0.isEmpty }) {
            return "fail_closed=\(denyCode)"
        }
        return "排查 grant_required / permission_denied / hub_unreachable"
    }

    private static func orderedUnique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var ordered: [String] = []
        for rawValue in values {
            let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard value.isEmpty == false else { continue }
            if seen.insert(value).inserted {
                ordered.append(value)
            }
        }
        return ordered
    }
}

struct SettingsView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var activeFocusRequest: XTSettingsFocusRequest?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: UIThemeTokens.sectionSpacing) {
                    headerSection
                    ValidatedScopeBadge(presentation: ValidatedScopePresentation.validatedMainlineOnly)
                    StatusExplanationCard(explanation: settingsStatus)
                    PrimaryActionRail(title: "快速动作", actions: quickActions, onTap: handleAction)
                    settingsCenterOverview
                    pairHubSection
                        .id("pair_hub")
                    chooseModelSection
                        .id("choose_model")
                    grantAndRepairSection
                        .id("grant_permissions")
                    securityRuntimeSection
                        .id("security_runtime")
                    diagnosticsSection
                        .id("diagnostics")
                }
                .padding(16)
            }
            .onAppear {
                processSettingsFocusRequest(proxy)
            }
            .onChange(of: appModel.settingsFocusRequest?.nonce) { _ in
                processSettingsFocusRequest(proxy)
            }
        }
        .frame(minWidth: 820, idealWidth: 860, minHeight: 760)
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("XT Settings Center")
                .font(UIThemeTokens.sectionFont())
            Text("AI-4 已切换到 AI-3 冻结的 surface state / badge / action semantics，不再单独发散 badge 文案和 action IDs。")
                .font(UIThemeTokens.bodyFont())
                .foregroundStyle(.secondary)
            Text("consumed_frozen_fields=\(XTSettingsCenterManifest.consumedFrozenFields.joined(separator: ", "))")
                .font(UIThemeTokens.monoFont())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    private var settingsCenterOverview: some View {
        GroupBox("任务导向分区") {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(XTSettingsCenterManifest.sections) { section in
                    XTSettingsFocusCard(section: section)
                }
            }
            .padding(8)
        }
    }

    private var pairHubSection: some View {
        GroupBox("1) Pair Hub") {
            VStack(alignment: .leading, spacing: 10) {
                Text("首用路径从 Hub 配对开始：discover → bootstrap → connect → reconnect smoke。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                    GridRow {
                        Text("Pairing Port")
                            .frame(width: 140, alignment: .leading)
                        TextField("50052", value: pairingPortBinding, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 120)
                    }
                    GridRow {
                        Text("gRPC Port")
                            .frame(width: 140, alignment: .leading)
                        TextField("50051", value: grpcPortBinding, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 120)
                    }
                    GridRow {
                        Text("Internet Host")
                            .frame(width: 140, alignment: .leading)
                        TextField("hub.example.com", text: internetHostBinding)
                            .textFieldStyle(.roundedBorder)
                    }
                    GridRow {
                        Text("axhubctl Path")
                            .frame(width: 140, alignment: .leading)
                        TextField("auto detect", text: axhubctlPathBinding)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                HStack(spacing: 10) {
                    Button(appModel.hubRemoteLinking ? "Linking..." : "One-Click Setup") {
                        appModel.startHubOneClickSetup()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Reconnect Smoke") {
                        appModel.startHubReconnectOnly()
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Text(connectionStateLabel)
                        .font(UIThemeTokens.monoFont())
                        .foregroundStyle(connectionStateColor)
                }

                if !appModel.hubRemoteSummary.isEmpty {
                    Text("Summary: \(appModel.hubRemoteSummary)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(8)
        }
    }

    private var chooseModelSection: some View {
        GroupBox("2) Choose Model") {
            VStack(alignment: .leading, spacing: 10) {
                if let context = focusContext(for: "choose_model") {
                    XTFocusContextCard(context: context)
                }
                Text("所有角色仍经由 Hub 路由，但这里先保证首个任务所需角色已经选到模型。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                    GridRow {
                        Text("Role")
                            .foregroundStyle(.secondary)
                        Text("Model (Hub)")
                            .foregroundStyle(.secondary)
                    }
                    .font(UIThemeTokens.monoFont())

                    ForEach(AXRole.allCases) { role in
                        GridRow {
                            Text(role.displayName)
                                .font(UIThemeTokens.monoFont())
                                .frame(width: 120, alignment: .leading)

                            TextField("model id", text: bindingModel(role))
                                .font(UIThemeTokens.monoFont())
                                .frame(width: 360)
                        }
                    }
                }

                Text("建议至少先配置 coder 与 supervisor；如果 paid model 被 grant 拦住，可直接去下一分区修复。")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            .padding(8)
        }
    }

    private var grantAndRepairSection: some View {
        GroupBox("3) Grant & Repair") {
            VStack(alignment: .leading, spacing: 10) {
                TroubleshootPanel(title: "3 步内定位修复入口", issues: [.grantRequired, .permissionDenied, .hubUnreachable])
            }
            .padding(8)
        }
    }

    private var securityRuntimeSection: some View {
        GroupBox("4) Security & Runtime") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Enable local HTTP server", isOn: localServerEnabledBinding)

                HStack(spacing: 8) {
                    Circle()
                        .fill(appModel.serverRunning ? UIThemeTokens.color(for: .ready) : Color.secondary)
                        .frame(width: 8, height: 8)
                    if appModel.serverRunning {
                        Text("Running on port \(appModel.localServerPort)")
                            .font(UIThemeTokens.monoFont())
                    } else if appModel.localServerEnabled {
                        Text("Enabled but not running")
                            .font(UIThemeTokens.monoFont())
                            .foregroundStyle(UIThemeTokens.color(for: .inProgress))
                    } else {
                        Text("Disabled")
                            .font(UIThemeTokens.monoFont())
                            .foregroundStyle(.secondary)
                    }
                }

                if !appModel.localServerLastError.isEmpty {
                    Text(appModel.localServerLastError)
                        .font(.caption)
                        .foregroundStyle(UIThemeTokens.color(for: .permissionDenied))
                        .textSelection(.enabled)
                }

                Button("Restart Server") {
                    appModel.restartLocalServer()
                }
                .buttonStyle(.bordered)
                .disabled(!appModel.localServerEnabled)
            }
            .padding(8)
        }
    }

    private var diagnosticsSection: some View {
        GroupBox("5) Diagnostics & Verify") {
            VStack(alignment: .leading, spacing: 10) {
                if let context = focusContext(for: "diagnostics") {
                    XTFocusContextCard(context: context)
                }
                HStack {
                    Text("Current route")
                    Spacer()
                    Text(connectionStateLabel)
                        .font(UIThemeTokens.monoFont())
                        .foregroundStyle(connectionStateColor)
                }

                Text("在同一分区核对当前 transport、Pairing Port / gRPC Port / Internet Host、模型可见性、tool route、session runtime 与 skills compatibility。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                XTUnifiedDoctorSummaryView(report: doctorReport)

                if !XTSettingsSurfacePlanner.diagnosticsLines(for: settingsState).isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("AI-2 runtime contracts")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ForEach(XTSettingsSurfacePlanner.diagnosticsLines(for: settingsState), id: \.self) { line in
                            Text("• \(line)")
                                .font(UIThemeTokens.monoFont())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }

                if !routeRepairLogLines.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Recent route repair log")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ForEach(routeRepairLogLines, id: \.self) { line in
                            Text("• \(line)")
                                .font(UIThemeTokens.monoFont())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }

                ScrollView {
                    Text(appModel.hubRemoteLog.isEmpty ? "No remote link log yet." : appModel.hubRemoteLog)
                        .font(UIThemeTokens.monoFont())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .frame(minHeight: 120, maxHeight: 220)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .padding(8)
        }
    }

    private var settingsStatus: StatusExplanation {
        XTSettingsSurfacePlanner.status(for: settingsState)
    }

    private var quickActions: [PrimaryActionRailAction] {
        XTSettingsSurfacePlanner.quickActions(for: settingsState)
    }

    private var settingsState: XTSettingsSurfaceState {
        XTSettingsSurfaceState(
            hubConnected: appModel.hubConnected,
            remoteConnected: appModel.hubRemoteConnected,
            linking: appModel.hubRemoteLinking,
            localServerEnabled: appModel.localServerEnabled,
            serverRunning: appModel.serverRunning,
            failureCode: appModel.hubSetupFailureCode,
            runtime: runtimeSnapshot,
            doctor: doctorReport
        )
    }

    private var doctorReport: XTUnifiedDoctorReport {
        appModel.unifiedDoctorReport
    }

    private var runtimeSnapshot: UIFailClosedRuntimeSnapshot {
        guard let orchestrator = appModel.supervisor.orchestrator else {
            return .empty
        }
        return UIFailClosedRuntimeSnapshot.capture(
            policy: orchestrator.oneShotAutonomyPolicy,
            freeze: orchestrator.latestDeliveryScopeFreeze,
            launchDecisions: Array(orchestrator.laneLaunchDecisions.values),
            directedUnblockBatons: orchestrator.executionMonitor.directedUnblockBatons,
            replayReport: orchestrator.latestReplayHarnessReport
        )
    }

    private var routeRepairLogLines: [String] {
        guard let ctx = appModel.projectContext else { return [] }
        return AXRouteRepairLogStore.summaryLines(for: ctx, limit: 5)
    }

    private func handleAction(_ action: PrimaryActionRailAction) {
        switch action.id {
        case "pair_hub":
            appModel.startHubOneClickSetup()
        case "run_smoke":
            appModel.startHubReconnectOnly()
        case "review_grants":
            appModel.resetPairingStateAndOneClickSetup()
        default:
            break
        }
    }

    private func bindingModel(_ role: AXRole) -> Binding<String> {
        Binding(
            get: { appModel.settingsStore.settings.assignment(for: role).model ?? "" },
            set: { s in
                let value = s.trimmingCharacters(in: .whitespacesAndNewlines)
                appModel.settingsStore.settings = appModel.settingsStore.settings.setting(role: role, providerKind: .hub, model: value.isEmpty ? nil : value)
                appModel.settingsStore.save()
            }
        )
    }

    private var pairingPortBinding: Binding<Int> {
        Binding(
            get: { appModel.hubPairingPort },
            set: { value in
                appModel.hubPairingPort = max(1, min(65_535, value))
                appModel.saveHubRemotePrefsNow()
            }
        )
    }

    private var localServerEnabledBinding: Binding<Bool> {
        Binding(
            get: { appModel.localServerEnabled },
            set: { value in
                appModel.setLocalServerEnabled(value)
            }
        )
    }

    private var grpcPortBinding: Binding<Int> {
        Binding(
            get: { appModel.hubGrpcPort },
            set: { value in
                appModel.hubGrpcPort = max(1, min(65_535, value))
                appModel.saveHubRemotePrefsNow()
            }
        )
    }

    private var internetHostBinding: Binding<String> {
        Binding(
            get: { appModel.hubInternetHost },
            set: { value in
                appModel.hubInternetHost = value
                appModel.saveHubRemotePrefsNow()
            }
        )
    }

    private var axhubctlPathBinding: Binding<String> {
        Binding(
            get: { appModel.hubAxhubctlPath },
            set: { value in
                appModel.hubAxhubctlPath = value
                appModel.saveHubRemotePrefsNow()
            }
        )
    }

    private var connectionStateLabel: String {
        if appModel.hubConnected {
            return "local"
        }
        if appModel.hubRemoteLinking {
            return "linking"
        }
        if appModel.hubRemoteConnected {
            switch appModel.hubRemoteRoute {
            case .lan:
                return "remote:lan"
            case .internet:
                return "remote:internet"
            case .internetTunnel:
                return "remote:tunnel"
            case .none:
                return "remote"
            }
        }
        return "disconnected"
    }

    private var connectionStateColor: Color {
        if appModel.hubConnected { return .secondary }
        if appModel.hubRemoteLinking { return UIThemeTokens.color(for: .inProgress) }
        if appModel.hubRemoteConnected { return UIThemeTokens.color(for: .inProgress) }
        return UIThemeTokens.color(for: .permissionDenied)
    }

    private func processSettingsFocusRequest(_ proxy: ScrollViewProxy) {
        guard let request = appModel.settingsFocusRequest else { return }
        activeFocusRequest = request
        withAnimation(.easeInOut(duration: 0.2)) {
            proxy.scrollTo(request.sectionId, anchor: .top)
        }
        appModel.clearSettingsFocusRequest(request)
        scheduleFocusContextClear(nonce: request.nonce)
    }

    private func focusContext(for sectionId: String) -> XTSectionFocusContext? {
        guard activeFocusRequest?.sectionId == sectionId else { return nil }
        return activeFocusRequest?.context
    }

    private func scheduleFocusContextClear(nonce: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 12) {
            if activeFocusRequest?.nonce == nonce {
                activeFocusRequest = nil
            }
        }
    }
}

private struct XTSettingsFocusCard: View {
    let section: XTSettingsSectionDescriptor

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(section.title)
                    .font(.headline)
                Spacer()
                Text(section.id)
                    .font(UIThemeTokens.monoFont())
                    .foregroundStyle(.secondary)
            }
            Text(section.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Repair entry: \(section.repairEntry)")
                .font(UIThemeTokens.monoFont())
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: UIThemeTokens.cardRadius)
                .fill(UIThemeTokens.secondaryCardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: UIThemeTokens.cardRadius)
                .stroke(UIThemeTokens.subtleBorder, lineWidth: 1)
        )
    }
}
