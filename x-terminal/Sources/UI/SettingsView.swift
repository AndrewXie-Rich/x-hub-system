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
        XTSettingsSectionDescriptor(id: "pair_hub", title: "连接 Hub（Pair Hub）", summary: "配对、端口、公网地址和重连 smoke 都从这里开始。", repairEntry: "XT Settings → 连接 Hub（Pair Hub）"),
        XTSettingsSectionDescriptor(id: "choose_model", title: "AI 模型（Choose Model）", summary: "先为首个任务选好 Hub 模型，避免把模型缺失误判成授权问题。", repairEntry: "XT Settings → AI 模型（Choose Model）"),
        XTSettingsSectionDescriptor(id: "grant_permissions", title: "授权与权限（Grant & Permissions）", summary: "集中处理授权、系统权限和 Hub 不可达。", repairEntry: "XT Settings → 授权修复（Grant & Repair）"),
        XTSettingsSectionDescriptor(id: "security_runtime", title: "安全与运行时（Security & Runtime）", summary: "管理本地 HTTP 服务、工具执行路径和安全边界。", repairEntry: "XT Settings → 安全与运行时（Security & Runtime）"),
        XTSettingsSectionDescriptor(id: "diagnostics", title: "诊断（Diagnostics）", summary: "统一查看当前链路、运行时核对、日志与修复线索。", repairEntry: "XT Settings → 诊断（Diagnostics）")
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
                headline: "设置中心当前优先处理：\(issue.title)",
                whatHappened: "常见阻塞已经收口到连接 Hub（Pair Hub）、授权修复（Grant & Repair）和诊断（Diagnostics）三个入口；denyCode、replay 和恢复线索也会一起显示。",
                whyItHappened: "这样你不用在多个页面来回猜，XT / Home / Cockpit / Settings 看到的是同一套运行时状态。",
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
                headline: "当前请求超出已验证主链",
                whatHappened: "这次请求碰到了 release freeze 的 fail-closed 边界，所以这里只继续显示已验证主链允许的入口。",
                whyItHappened: "界面会明确收口超范围能力，避免把还没验证的路径说成可用。",
                userAction: state.runtime.scopeNextActions.first ?? "先收回 scope expansion，再回到已验证主链。",
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
                headline: "当前优先处理：重放回归未通过",
                whatHappened: "配对和设置入口都已具备，但 replay harness 还没通过，现在不能把 smoke 或首个任务误判成绿色。",
                whyItHappened: "系统会继续把 replay 当作硬门槛，先修复 denyCode 和失败场景，再往下走。",
                userAction: state.runtime.nextRepairAction ?? "先到诊断（Diagnostics）查看 replay denyCode / 场景，再重跑 smoke。",
                machineStatusRef: machineStatusRef,
                hardLine: ValidatedScopePresentation.validatedMainlineOnly.hardLine,
                highlights: mergedHighlights([
                    "replay_fail_closed=true"
                ], runtime: state.runtime)
            )
        }

        return StatusExplanation(
            state: state.hubInteractive ? .ready : .blockedWaitingUpstream,
            headline: state.hubInteractive ? "设置中心已对齐当前已验证主链" : "设置中心已就绪，但 Hub 还没接入",
            whatHappened: "这里先回答四件事：配对、模型、授权、诊断，而不是把底层工程开关都堆给你。",
            whyItHappened: "目标是让新用户走完首用路径，老用户也能在 3 步内找到授权、权限或连通性修复入口。",
            userAction: state.hubInteractive ? "继续重连自检（Reconnect Smoke），或返回 Home / Supervisor 开始首个任务。" : "先完成 Pair Hub，再回来选择模型和处理授权。",
            machineStatusRef: machineStatusRef,
            hardLine: ValidatedScopePresentation.validatedMainlineOnly.hardLine,
            highlights: mergedHighlights([
                "primary_sections=pair_hub,choose_model,grant_permissions,security_runtime,diagnostics",
                "release_scope=validated-mainline-only"
            ], runtime: state.runtime)
        )
    }

    static func quickActions(for state: XTSettingsSurfaceState) -> [PrimaryActionRailAction] {
        let issue = issue(for: state)
        let primaryAction = UITroubleshootKnowledgeBase.primaryAction(
            for: issue,
            defaultPairSubtitle: "从 One-Click Setup 开始首用路径"
        )
        return [
            PrimaryActionRailAction(
                id: primaryAction.id,
                title: primaryAction.title,
                subtitle: primaryAction.subtitle,
                systemImage: primaryAction.systemImage,
                style: .primary
            ),
            PrimaryActionRailAction(
                id: "run_smoke",
                title: "重连自检（Run Reconnect Smoke）",
                subtitle: runSmokeSubtitle(runtime: state.runtime),
                systemImage: "bolt.horizontal.circle",
                style: .secondary
            ),
            PrimaryActionRailAction(
                id: "open_repair_entry",
                title: UITroubleshootKnowledgeBase.repairEntryTitle(for: issue),
                subtitle: reviewSubtitle(issue: issue, runtime: state.runtime),
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

    fileprivate static func issue(for state: XTSettingsSurfaceState) -> UITroubleshootIssue? {
        UITroubleshootKnowledgeBase.issue(forFailureCode: state.failureCode) ?? state.runtime.primaryIssue
    }

    private static func mergedHighlights(_ highlights: [String], runtime: UIFailClosedRuntimeSnapshot) -> [String] {
        orderedUnique(highlights + runtime.statusHighlights + XTSettingsCenterManifest.consumedFrozenFields + runtime.consumedContracts.map({ "runtime_contract=\($0)" }))
    }

    fileprivate static func runSmokeSubtitle(runtime: UIFailClosedRuntimeSnapshot) -> String {
        if runtime.replayPass == true {
            return "replay regression PASS；验证 pair + model + grant 已连通"
        }
        if runtime.replayPass == false {
            return "replay fail-closed；先看 denyCode / diagnostics"
        }
        return "验证 pair + model + grant 已连通"
    }

    fileprivate static func reviewSubtitle(issue: UITroubleshootIssue?, runtime: UIFailClosedRuntimeSnapshot) -> String {
        if issue == .pairingRepairRequired || issue == .multipleHubsAmbiguous || issue == .hubPortConflict {
            return UITroubleshootKnowledgeBase.repairEntryDetail(for: issue, runtime: runtime)
        }
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
    @StateObject private var supervisorManager = SupervisorManager.shared
    @StateObject private var chooseModelUpdateFeedback = XTTransientUpdateFeedbackState()
    @StateObject private var securityRuntimeUpdateFeedback = XTTransientUpdateFeedbackState()
    @State private var activeFocusRequest: XTSettingsFocusRequest?
    @State private var defaultToolSandboxMode: ToolSandboxMode = ToolExecutor.sandboxMode()
    @State private var chooseModelChangeNotice: XTSettingsChangeNotice?
    @State private var securityRuntimeChangeNotice: XTSettingsChangeNotice?

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
                appModel.maybeAutoFillHubSetupPathAndPorts(force: false)
                defaultToolSandboxMode = ToolExecutor.sandboxMode()
            }
            .onChange(of: appModel.settingsFocusRequest?.nonce) { _ in
                processSettingsFocusRequest(proxy)
            }
            .onDisappear {
                chooseModelUpdateFeedback.cancel(resetState: true)
                chooseModelChangeNotice = nil
                securityRuntimeUpdateFeedback.cancel(resetState: true)
                securityRuntimeChangeNotice = nil
            }
        }
        .frame(minWidth: 820, idealWidth: 860, minHeight: 760)
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("XT 设置中心")
                .font(UIThemeTokens.sectionFont())
            Text("把连接、模型、授权、安全和诊断收口到同一页；常见问题优先直接给修复入口。")
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
        GroupBox("1) 连接 Hub") {
            VStack(alignment: .leading, spacing: 10) {
                Text("首用路径从 Hub 配对开始：发现 → 配对 → 连接 → 重连 smoke。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                    GridRow {
                        Text("配对端口")
                            .frame(width: 140, alignment: .leading)
                        TextField("50052", value: pairingPortBinding, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 120)
                    }
                    GridRow {
                        Text("gRPC 端口")
                            .frame(width: 140, alignment: .leading)
                        TextField("50051", value: grpcPortBinding, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 120)
                    }
                    GridRow {
                        Text("公网地址")
                            .frame(width: 140, alignment: .leading)
                        TextField("hub.example.com", text: internetHostBinding)
                            .textFieldStyle(.roundedBorder)
                    }
                    GridRow {
                        Text("axhubctl 路径")
                            .frame(width: 140, alignment: .leading)
                        TextField("自动探测", text: axhubctlPathBinding)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                HStack(spacing: 10) {
                    Button(appModel.hubPortAutoDetectRunning ? "探测中..." : "自动探测") {
                        appModel.maybeAutoFillHubSetupPathAndPorts(force: true)
                    }
                    .buttonStyle(.bordered)
                    .disabled(appModel.hubRemoteLinking)

                    Button(appModel.hubRemoteLinking ? "连接中..." : "一键连接") {
                        appModel.startHubOneClickSetup()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("重连 Smoke") {
                        appModel.startHubReconnectOnly()
                    }
                    .buttonStyle(.bordered)

                    Button(appModel.hubRemoteLinking ? "重置中..." : "清除配对后重连") {
                        appModel.resetPairingStateAndOneClickSetup()
                    }
                    .buttonStyle(.bordered)
                    .disabled(appModel.hubRemoteLinking || appModel.hubPortAutoDetectRunning)

                    Spacer()

                    Text(connectionStateLabel)
                        .font(UIThemeTokens.monoFont())
                        .foregroundStyle(connectionStateColor)
                }

                if !appModel.hubPortAutoDetectMessage.isEmpty {
                    Text(appModel.hubPortAutoDetectMessage)
                        .font(UIThemeTokens.monoFont())
                        .foregroundStyle(.secondary)
                }
                if !appModel.hubRemoteSummary.isEmpty {
                    Text("摘要：\(appModel.hubRemoteSummary)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HubDiscoveryCandidatesView(appModel: appModel)
            }
            .padding(8)
        }
    }

    private var chooseModelSection: some View {
        let guidance = XTModelGuidancePresentation.build(
            settings: appModel.settingsStore.settings,
            snapshot: appModel.modelsState,
            currentProjectName: selectedProjectDisplayName,
            currentProjectContext: appModel.projectContext,
            currentProjectCoderModelId: appModel.projectConfig?.modelOverride(for: .coder)
        )

        return GroupBox("2) 选择模型") {
            VStack(alignment: .leading, spacing: 10) {
                if let context = focusContext(for: "choose_model") {
                    XTFocusContextCard(context: context)
                }
                Text("所有角色仍经由 Hub 路由，但这里先保证首个任务所需角色已经选到模型。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if chooseModelUpdateFeedback.showsBadge,
                   let chooseModelChangeNotice {
                    XTSettingsChangeNoticeInlineView(
                        notice: chooseModelChangeNotice,
                        tint: .accentColor
                    )
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("选型提示")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text(guidance.inventorySummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    ForEach(guidance.items) { item in
                        Text("• \(item.title)：\(item.detail)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let routeMemoryHint = guidance.routeMemoryHint {
                        Text(routeMemoryHint)
                            .font(.caption)
                            .foregroundStyle(UIThemeTokens.color(for: .diagnosticRequired))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(NSColor.controlBackgroundColor))
                )

                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                    GridRow {
                        Text("角色")
                            .foregroundStyle(.secondary)
                        Text("Hub 模型")
                            .foregroundStyle(.secondary)
                    }
                    .font(UIThemeTokens.monoFont())

                    ForEach(AXRole.allCases) { role in
                        GridRow {
                            Text(role.displayName)
                                .font(UIThemeTokens.monoFont())
                                .frame(width: 120, alignment: .leading)

                            TextField("模型 ID", text: bindingModel(role))
                                .font(UIThemeTokens.monoFont())
                                .frame(width: 360)
                        }
                    }
                }

                if !chooseModelIssues.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("即时提示")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(UIThemeTokens.color(for: .diagnosticRequired))
                        ForEach(chooseModelIssues) { issue in
                            HStack(alignment: .top, spacing: 10) {
                                Text(issue.message)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 8)
                                if let suggestedModelId = issue.suggestedModelId {
                                    Button("改用推荐") {
                                        applySuggestedGlobalModel(
                                            role: issue.role,
                                            modelId: suggestedModelId
                                        )
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    .help("把 \(issue.role.displayName) 直接切到 `\(suggestedModelId)`。")
                                }
                            }
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(UIThemeTokens.stateBackground(for: .diagnosticRequired))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(UIThemeTokens.color(for: .diagnosticRequired).opacity(0.2), lineWidth: 1)
                    )
                }

                Text("建议至少先配置 coder 与 supervisor；如果付费模型被 grant 拦住，可直接去下一分区修复。")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            .padding(8)
        }
    }

    private var grantAndRepairSection: some View {
        GroupBox("3) 授权与修复") {
            VStack(alignment: .leading, spacing: 10) {
                TroubleshootPanel(
                    title: "3 步内定位修复入口",
                    issues: [
                        .multipleHubsAmbiguous,
                        .hubPortConflict,
                        .pairingRepairRequired,
                        .grantRequired,
                        .permissionDenied,
                        .hubUnreachable
                    ]
                )
            }
            .padding(8)
        }
    }

    private var securityRuntimeSection: some View {
        let guidance = XTSecurityRuntimeGuidancePresentation.build(
            sandboxMode: defaultToolSandboxMode,
            workMode: appModel.settingsStore.settings.supervisorWorkMode,
            privacyMode: appModel.settingsStore.settings.supervisorPrivacyMode
        )

        return GroupBox("4) 安全与运行时") {
            VStack(alignment: .leading, spacing: 10) {
                if let context = focusContext(for: "security_runtime") {
                    XTFocusContextCard(context: context)
                }

                if securityRuntimeUpdateFeedback.showsBadge,
                   let securityRuntimeChangeNotice {
                    XTSettingsChangeNoticeInlineView(
                        notice: securityRuntimeChangeNotice,
                        tint: .accentColor
                    )
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("安全说明")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    ForEach(guidance.items) { item in
                        Text("• \(item.title)：\(item.detail)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(NSColor.controlBackgroundColor))
                )

                Toggle("启用本地 HTTP 服务", isOn: localServerEnabledBinding)

                Picker("默认工具执行路径", selection: defaultToolSandboxModeBinding) {
                    ForEach(ToolSandboxMode.allCases, id: \.rawValue) { mode in
                        Text(mode == .host ? "宿主机" : "沙箱").tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                HStack(spacing: 8) {
                    Circle()
                        .fill(appModel.serverRunning ? UIThemeTokens.color(for: .ready) : Color.secondary)
                        .frame(width: 8, height: 8)
                    if appModel.serverRunning {
                        Text("运行中：端口 \(appModel.localServerPort)")
                            .font(UIThemeTokens.monoFont())
                    } else if appModel.localServerEnabled {
                        Text("已启用，但未运行")
                            .font(UIThemeTokens.monoFont())
                            .foregroundStyle(UIThemeTokens.color(for: .inProgress))
                    } else {
                        Text("已关闭")
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

                Button("重启服务") {
                    appModel.restartLocalServer()
                }
                .buttonStyle(.bordered)
                .disabled(!appModel.localServerEnabled)
            }
            .padding(8)
        }
        .xtTransientUpdateCardChrome(
            cornerRadius: 12,
            isUpdated: securityRuntimeUpdateFeedback.isHighlighted,
            focusTint: .accentColor,
            updateTint: .accentColor,
            baseBackground: Color(NSColor.controlBackgroundColor).opacity(0.35)
        )
    }

    private var diagnosticsSection: some View {
        GroupBox("5) 诊断与核对") {
            VStack(alignment: .leading, spacing: 10) {
                if let context = focusContext(for: "diagnostics") {
                    XTFocusContextCard(context: context)
                }
                officialSkillsRecheckStatus
                HStack {
                    Text("当前链路")
                    Spacer()
                    Text(connectionStateLabel)
                        .font(UIThemeTokens.monoFont())
                        .foregroundStyle(connectionStateColor)
                }

                Text("在同一分区核对当前传输方式、配对端口 / gRPC 端口 / 公网地址、模型可见性、工具路由、会话运行时与技能兼容性。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                XTUnifiedDoctorSummaryView(report: doctorReport)

                if !appModel.officialSkillChannelSummaryLine.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("官方技能通道")
                            Spacer()
                            Button("重查") {
                                appModel.recheckOfficialSkills(reason: "settings_diagnostics_manual")
                            }
                            .buttonStyle(.borderless)
                            Text(appModel.officialSkillChannelSummaryLine)
                                .font(UIThemeTokens.monoFont())
                                .foregroundStyle(officialSkillChannelStatusColor)
                                .textSelection(.enabled)
                        }
                        if !appModel.officialSkillChannelDetailLine.isEmpty {
                            Text(appModel.officialSkillChannelDetailLine)
                                .font(UIThemeTokens.monoFont())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                        if !appModel.officialSkillChannelTopBlockersLine.isEmpty {
                            if !appModel.officialSkillChannelTopBlockerSummaries.isEmpty {
                                XTOfficialSkillsBlockerListView(
                                    items: appModel.officialSkillChannelTopBlockerSummaries
                                )
                            } else {
                                Text(appModel.officialSkillChannelTopBlockersLine)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.orange)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }

                if !appModel.skillsCompatibilitySnapshot.builtinGovernedSkills.isEmpty {
                    XTBuiltinGovernedSkillsListView(
                        items: appModel.skillsCompatibilitySnapshot.builtinGovernedSkills
                    )
                }

                if !XTSettingsSurfacePlanner.diagnosticsLines(for: settingsState).isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("运行时状态线索")
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
                        if routeRepairLogDigest.totalEvents > 0 {
                            Text("路由修复摘要")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(routeRepairLogDigest.headline)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            ForEach(routeRepairLogDigest.detailLines, id: \.self) { line in
                                Text("• \(line)")
                                    .font(UIThemeTokens.monoFont())
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        }

                        if let reminderStatus = currentProjectRouteReminderStatus {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("路由修复提醒")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Spacer(minLength: 8)
                                if appModel.selectedProjectId != nil {
                                    Button("查看路由") {
                                        openCurrentProjectRouteDiagnose()
                                    }
                                    .buttonStyle(.borderless)
                                    .controlSize(.small)
                                    .help("切回当前项目聊天，并自动展开 route diagnose。")
                                }
                                if reminderStatus.quietingCurrentIssue,
                                   let projectId = appModel.selectedProjectId {
                                    Button("恢复提醒") {
                                        supervisorManager.clearRouteAttentionReminderState(projectId: projectId)
                                    }
                                    .buttonStyle(.borderless)
                                    .controlSize(.small)
                                    .help("清掉当前静默状态；如果问题还在，下一次 timer 心跳会重新主动提醒。")
                                }
                            }
                            if let line = routeReminderLine(reminderStatus) {
                                Text(line)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }

                        Text("最近路由修复记录")
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
                    Text(appModel.hubRemoteLog.isEmpty ? "还没有远端连接日志。" : appModel.hubRemoteLog)
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
        return AXRouteRepairLogStore.userFacingSummaryLines(for: ctx, limit: 5)
    }

    private var routeRepairLogDigest: AXRouteRepairLogDigest {
        guard let ctx = appModel.projectContext else { return .empty }
        return AXRouteRepairLogStore.digest(for: ctx, limit: 50)
    }

    private var chooseModelIssues: [HubGlobalRoleModelIssue] {
        let snapshot = ModelStateSnapshot(
            models: appModel.modelsState.models,
            updatedAt: appModel.modelsState.updatedAt
        )
        return Array(
            AXRole.allCases.compactMap { role in
                HubModelSelectionAdvisor.globalAssignmentIssue(
                    for: role,
                    configuredModelId: appModel.settingsStore.settings.assignment(for: role).model,
                    snapshot: snapshot
                )
            }
            .prefix(3)
        )
    }

    private var selectedProjectDisplayName: String? {
        guard let selectedProjectId = appModel.selectedProjectId,
              selectedProjectId != AXProjectRegistry.globalHomeId else {
            return nil
        }
        return appModel.registry.project(for: selectedProjectId)?.displayName
    }

    private var currentProjectRouteReminderStatus: SupervisorManager.RouteAttentionReminderStatus? {
        guard let projectId = appModel.selectedProjectId,
              projectId != AXProjectRegistry.globalHomeId,
              let project = appModel.registry.project(for: projectId),
              let watchItem = AXRouteRepairLogStore.watchItems(for: [project], limit: 1).first else {
            return nil
        }
        return supervisorManager.routeAttentionReminderStatus(for: watchItem)
    }

    private func routeReminderLine(
        _ status: SupervisorManager.RouteAttentionReminderStatus
    ) -> String? {
        guard let lastAlertAt = status.lastAlertAt else { return nil }
        let lastAlertText = relativeTimeText(lastAlertAt)
        if status.quietingCurrentIssue {
            let cooldownText = compactDurationText(status.cooldownRemainingSec)
            return "上次提醒：\(lastAlertText)；当前静默观察中，约 \(cooldownText) 后才会再次主动提醒。"
        }
        return "上次提醒：\(lastAlertText)。"
    }

    private func relativeTimeText(_ ts: Double) -> String {
        guard ts > 0 else { return "未知" }
        let elapsedSec = max(0, Int(Date().timeIntervalSince1970 - ts))
        if elapsedSec < 90 { return "刚刚" }
        let mins = elapsedSec / 60
        if mins < 60 { return "\(mins) 分钟前" }
        let hours = mins / 60
        if hours < 48 { return "\(hours) 小时前" }
        return "\(hours / 24) 天前"
    }

    private func compactDurationText(_ seconds: Int) -> String {
        let normalized = max(0, seconds)
        if normalized < 90 { return "1 分钟内" }
        let mins = normalized / 60
        if mins < 60 { return "\(mins) 分钟" }
        let hours = mins / 60
        if hours < 48 { return "\(hours) 小时" }
        return "\(hours / 24) 天"
    }

    private func openCurrentProjectRouteDiagnose() {
        guard let projectId = appModel.selectedProjectId,
              projectId != AXProjectRegistry.globalHomeId else { return }
        appModel.selectProject(projectId)
        appModel.setPane(.chat, for: projectId)
        appModel.requestProjectRouteDiagnoseFocus(projectId: projectId)
    }

    private func applySuggestedGlobalModel(role: AXRole, modelId: String) {
        updateGlobalModelAssignment(role: role, rawModelId: modelId)
    }

    private var officialSkillChannelStatusColor: Color {
        switch appModel.skillsCompatibilitySnapshot.officialChannelStatus.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "healthy":
            return UIThemeTokens.color(for: .ready)
        case "stale":
            return UIThemeTokens.color(for: .inProgress)
        case "failed", "missing":
            return UIThemeTokens.color(for: .diagnosticRequired)
        default:
            return .secondary
        }
    }

    private func handleAction(_ action: PrimaryActionRailAction) {
        switch action.id {
        case "pair_hub":
            appModel.startHubOneClickSetup()
        case "repair_pairing":
            appModel.resetPairingStateAndOneClickSetup()
        case "resolve_hub_ambiguity":
            appModel.requestSettingsFocus(
                sectionId: "pair_hub",
                title: "固定目标 Hub 后继续连接",
                detail: UITroubleshootKnowledgeBase.repairEntryDetail(
                    for: .multipleHubsAmbiguous,
                    runtime: runtimeSnapshot
                )
            )
        case "repair_hub_port_conflict":
            appModel.requestSettingsFocus(
                sectionId: "pair_hub",
                title: "修复 Hub 端口冲突",
                detail: UITroubleshootKnowledgeBase.repairEntryDetail(
                    for: .hubPortConflict,
                    runtime: runtimeSnapshot
                )
            )
        case "run_smoke":
            appModel.startHubReconnectOnly()
        case "open_repair_entry":
            let issue = XTSettingsSurfacePlanner.issue(for: settingsState)
            let targetSection: String
            let title: String
            let detail: String
            switch issue {
            case .grantRequired, .paidModelAccessBlocked:
                targetSection = "grant_permissions"
                title = "查看授权与额度修复入口"
                detail = XTSettingsSurfacePlanner.reviewSubtitle(issue: issue, runtime: runtimeSnapshot)
            case .permissionDenied:
                targetSection = "grant_permissions"
                title = "查看权限与 policy 修复入口"
                detail = XTSettingsSurfacePlanner.reviewSubtitle(issue: issue, runtime: runtimeSnapshot)
            case .pairingRepairRequired, .multipleHubsAmbiguous, .hubPortConflict:
                targetSection = "pair_hub"
                title = UITroubleshootKnowledgeBase.repairEntryTitle(for: issue)
                detail = XTSettingsSurfacePlanner.reviewSubtitle(issue: issue, runtime: runtimeSnapshot)
            case .hubUnreachable, .none:
                targetSection = "diagnostics"
                title = "查看连接与诊断入口"
                detail = XTSettingsSurfacePlanner.reviewSubtitle(issue: issue, runtime: runtimeSnapshot)
            }
            appModel.requestSettingsFocus(
                sectionId: targetSection,
                title: title,
                detail: detail
            )
        default:
            break
        }
    }

    private func bindingModel(_ role: AXRole) -> Binding<String> {
        Binding(
            get: { appModel.settingsStore.settings.assignment(for: role).model ?? "" },
            set: { s in
                updateGlobalModelAssignment(role: role, rawModelId: s)
            }
        )
    }

    private func updateGlobalModelAssignment(role: AXRole, rawModelId: String) {
        let value = rawModelId.trimmingCharacters(in: .whitespacesAndNewlines)
        let current = appModel.settingsStore.settings.assignment(for: role).model?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard current != value else { return }

        appModel.settingsStore.settings = appModel.settingsStore.settings.setting(
            role: role,
            providerKind: .hub,
            model: value.isEmpty ? nil : value
        )
        appModel.settingsStore.save()
        chooseModelChangeNotice = XTSettingsChangeNoticeBuilder.globalRoleModel(
            role: role,
            modelId: value.isEmpty ? nil : value,
            snapshot: appModel.modelsState
        )
        chooseModelUpdateFeedback.trigger()
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

    private var defaultToolSandboxModeBinding: Binding<ToolSandboxMode> {
        Binding(
            get: { defaultToolSandboxMode },
            set: { value in
                defaultToolSandboxMode = value
                guard ToolExecutor.sandboxMode() != value else { return }
                appModel.setDefaultToolSandboxMode(value)
                securityRuntimeChangeNotice = XTSettingsChangeNoticeBuilder.defaultToolSandboxMode(value)
                securityRuntimeUpdateFeedback.trigger()
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
            return "本地已连"
        }
        if appModel.hubRemoteLinking {
            return "连接中"
        }
        if appModel.hubRemoteConnected {
            switch appModel.hubRemoteRoute {
            case .lan:
                return "远端已连（局域网）"
            case .internet:
                return "远端已连（公网）"
            case .internetTunnel:
                return "远端已连（隧道）"
            case .none:
                return "远端已连"
            }
        }
        return "未连接"
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
        if let refreshAction = request.context?.refreshAction {
            appModel.performSectionRefreshAction(
                refreshAction,
                reason: request.context?.refreshReason ?? "settings_focus_request"
            )
        }
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

    @ViewBuilder
    private var officialSkillsRecheckStatus: some View {
        let statusLine = appModel.officialSkillsRecheckStatusLine.trimmingCharacters(in: .whitespacesAndNewlines)
        if !statusLine.isEmpty {
            Text(statusLine)
                .font(UIThemeTokens.monoFont())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
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
            Text("修复入口：\(section.repairEntry)")
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
