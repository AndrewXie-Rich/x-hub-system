import SwiftUI

struct XTSettingsSectionDescriptor: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let title: String
    let summary: String
    let repairEntry: String
}

enum XTSettingsCenterManifest {
    static let sections: [XTSettingsSectionDescriptor] = [
        XTSettingsSectionDescriptor(id: "pair_hub", title: "连接 Hub", summary: "先把连接打通，再处理模型、授权和诊断。", repairEntry: "XT Settings → 连接 Hub"),
        XTSettingsSectionDescriptor(id: "choose_model", title: "AI 模型主入口", summary: "这里只看摘要；实际编辑统一进入 Supervisor Control Center · AI 模型。", repairEntry: "Supervisor Control Center → AI 模型"),
        XTSettingsSectionDescriptor(id: "grant_permissions", title: "授权与排障", summary: "集中处理 grant、系统权限和常见阻塞。", repairEntry: "XT Settings → 授权与排障"),
        XTSettingsSectionDescriptor(id: "security_runtime", title: "安全与运行时", summary: "管理本地服务、工具路径和安全边界。", repairEntry: "XT Settings → 安全与运行时"),
        XTSettingsSectionDescriptor(id: "diagnostics", title: "诊断与核对", summary: "统一查看链路、运行时状态、日志与修复线索。", repairEntry: "XT Settings → 诊断与核对")
    ]

    static let consumedFrozenFields: [String] = [
        "xt.ui_information_architecture.v1",
        "xt.delivery_scope_freeze.v1.validated_scope",
        "xt.unblock_baton.v1",
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
        let pairingContext = pairingContext(for: state)
        let connectedRouteSummary = connectedRouteSummary(for: state)
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
            if issue == .permissionDenied,
               let localNetworkStatus = localNetworkPermissionStatus(
                   for: state,
                   machineStatusRef: machineStatusRef
               ) {
                return localNetworkStatus
            }
            return StatusExplanation(
                state: issue == .grantRequired ? .grantRequired : issue == .permissionDenied ? .permissionDenied : .diagnosticRequired,
                headline: "设置中心当前优先处理：\(issue.title)",
                whatHappened: "常见阻塞已经收口到连接 Hub、授权与排障、诊断与核对这几个入口；这里会直接把你带到该修的地方。",
                whyItHappened: "这样你不用在多个页面来回猜，XT / Home / Cockpit / Settings 看到的是同一套运行时状态。",
                userAction: state.runtime.nextRepairAction ?? UITroubleshootKnowledgeBase.guide(
                    for: issue,
                    pairingContext: pairingContext
                ).steps.first?.instruction ?? "先按排障主链继续。",
                machineStatusRef: machineStatusRef,
                hardLine: "先修当前阻塞，再继续后续步骤",
                highlights: mergedHighlights([
                    "primary_sections=pair_hub,choose_model,grant_permissions,security_runtime,diagnostics"
                ], runtime: state.runtime)
            )
        }

        if state.runtime.scopeDecision == DeliveryScopeFreezeDecision.noGo.rawValue {
            return StatusExplanation(
                state: .blockedWaitingUpstream,
                headline: "当前请求超出已验证主链",
                whatHappened: "这次请求超出了当前已验证范围，所以这里只继续显示已验证主链允许的入口。",
                whyItHappened: "界面会明确收口超范围能力，避免把还没验证的路径说成可用。",
                userAction: state.runtime.scopeNextActions.first ?? "先收回 scope expansion，再回到已验证主链。",
                machineStatusRef: machineStatusRef,
                hardLine: "当前只继续显示已验证可走的入口",
                highlights: mergedHighlights([], runtime: state.runtime)
            )
        }

        if state.runtime.replayBlocked {
            return StatusExplanation(
                state: .diagnosticRequired,
                headline: "当前优先处理：重放回归未通过",
                whatHappened: "配对和设置入口都已具备，但回放核对还没通过，现在不能把自检或首个任务误判成已就绪。",
                whyItHappened: "系统会继续把回放核对当作硬门槛，先修复当前拒绝原因和失败场景，再往下走。",
                userAction: state.runtime.nextRepairAction ?? "先到诊断与核对里看 replay 失败原因，再重跑自检。",
                machineStatusRef: machineStatusRef,
                hardLine: "重放未通过前，不继续放行",
                highlights: mergedHighlights([
                    "replay_fail_closed=true"
                ], runtime: state.runtime)
            )
        }

        return StatusExplanation(
            state: state.hubInteractive ? .ready : .blockedWaitingUpstream,
            headline: state.hubInteractive
                ? (connectedRouteSummary ?? "设置中心已对齐当前已验证主链")
                : "设置中心已就绪，但 Hub 还没接入",
            whatHappened: "这里先回答四件事：配对、模型、授权、诊断，而不是把底层工程开关都堆给你。",
            whyItHappened: "目标是让新用户走完首用路径，老用户也能在 3 步内找到授权、权限或连通性修复入口。",
            userAction: state.hubInteractive ? "继续重连自检；查看项目汇总回 Home，发起首个任务进 Supervisor 窗口。" : "先完成连接 Hub，再回来查看模型、授权和诊断。",
            machineStatusRef: machineStatusRef,
            hardLine: "先连接，再往下走",
            highlights: mergedHighlights([
                "primary_sections=pair_hub,choose_model,grant_permissions,security_runtime,diagnostics"
            ], runtime: state.runtime)
        )
    }

    static func quickActions(for state: XTSettingsSurfaceState) -> [PrimaryActionRailAction] {
        let issue = issue(for: state)
        let pairingContext = pairingContext(for: state)
        let connectedRouteSummary = connectedRouteSummary(for: state)
        return [
            PrimaryActionRailAction(
                id: "connect_hub",
                title: "连接 Hub",
                subtitle: connectHubSubtitle(
                    issue: issue,
                    connected: state.hubInteractive,
                    linking: state.linking,
                    connectedSummary: connectedRouteSummary
                ),
                systemImage: state.hubInteractive ? "link.circle.fill" : "link.badge.plus",
                style: .primary
            ),
            PrimaryActionRailAction(
                id: "run_smoke",
                title: "重连自检",
                subtitle: runSmokeSubtitle(runtime: state.runtime),
                systemImage: "bolt.horizontal.circle",
                style: .secondary
            ),
            PrimaryActionRailAction(
                id: "open_repair_entry",
                title: "查看授权与排障",
                subtitle: reviewSubtitle(
                    issue: issue,
                    failureCode: state.failureCode,
                    runtime: state.runtime,
                    pairingContext: pairingContext
                ),
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

    fileprivate static func pairingContext(for state: XTSettingsSurfaceState) -> UITroubleshootPairingContext? {
        UITroubleshootPairingContext(
            firstPairCompletionProofSnapshot: state.doctor.firstPairCompletionProofSnapshot,
            pairedRouteSetSnapshot: state.doctor.pairedRouteSetSnapshot
        )
    }

    fileprivate static func connectedRouteSummary(for state: XTSettingsSurfaceState) -> String? {
        guard state.hubInteractive else { return nil }
        let summary = state.doctor.pairedRouteSetSnapshot?.summaryLine
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return summary.isEmpty ? nil : summary
    }

    private static func mergedHighlights(_ highlights: [String], runtime: UIFailClosedRuntimeSnapshot) -> [String] {
        orderedUnique(highlights)
    }

    fileprivate static func runSmokeSubtitle(runtime: UIFailClosedRuntimeSnapshot) -> String {
        if runtime.replayPass == true {
            return "自检通过；连接 Hub、模型和授权都已连通"
        }
        if runtime.replayPass == false {
            return "自检没通过；先看回放结果和诊断"
        }
        return "验证连接 Hub、模型和授权是否都已连通"
    }

    fileprivate static func reviewSubtitle(
        issue: UITroubleshootIssue?,
        failureCode: String = "",
        runtime: UIFailClosedRuntimeSnapshot,
        pairingContext: UITroubleshootPairingContext? = nil
    ) -> String {
        if let subtitle = localNetworkRepairSubtitle(failureCode: failureCode) {
            return subtitle
        }
        if issue == .pairingRepairRequired
            || issue == .multipleHubsAmbiguous
            || issue == .hubPortConflict
            || issue == .hubUnreachable
            || issue == .connectorScopeBlocked {
            return UITroubleshootKnowledgeBase.repairEntryDetail(
                for: issue,
                runtime: runtime,
                pairingContext: pairingContext
            )
        }
        if let issue {
            return "\(issue.title)；\(runtime.nextRepairAction ?? "先打开排障入口")"
        }
        if !runtime.nextDirectedAction.isEmpty {
            return "系统建议先做：\(runtime.nextDirectedAction)"
        }
        if let denyCode = runtime.launchDenyCodes.first(where: { !$0.isEmpty }) {
            return "当前拒绝原因：\(denyCode)"
        }
        return "先从授权、权限、模型和 Hub 连通性这几类问题里定位"
    }

    private static func localNetworkPermissionStatus(
        for state: XTSettingsSurfaceState,
        machineStatusRef: String
    ) -> StatusExplanation? {
        guard isLocalNetworkFailureCode(state.failureCode) else { return nil }
        let launchStatus = localHubLaunchStatusIfNeeded(for: state.failureCode)
        let blockedCapabilities = launchStatus?.blockedCapabilitiesSummary ?? "none"
        let localHubBlocked = launchStatus?.blocksPaidOrWebCapabilities == true
        let rootCause = launchStatus?.rootCauseErrorCode ?? ""

        let whyItHappened: String
        let userAction: String
        if localHubBlocked {
            whyItHappened = "XT 当前只看见本机 loopback Hub；与此同时，本机 fallback Hub 也处于 \(rootCause.isEmpty ? "bridge_unavailable" : rootCause) 降级，\(blockedCapabilities) 仍被挡住。继续让设置中心显示成“只差一点点”只会把问题延后到真正执行时才爆。"
            userAction = "先到系统设置 → 隐私与安全性 → 本地网络允许 X-Terminal；如果已经允许，再检查当前 Wi-Fi / AP 是否开启了 client isolation。若暂时只能走本机路径，再到 REL Flow Hub → Diagnostics & Recovery 修复 \(rootCause.isEmpty ? "本机 bridge" : rootCause)。"
        } else {
            whyItHappened = "XT 当前只看见本机 loopback Hub。最常见原因是 macOS 本地网络权限没生效，或当前 Wi-Fi / AP 开了 client isolation，所以同网远端 Hub 没法进入 pairing。"
            userAction = "先到系统设置 → 隐私与安全性 → 本地网络允许 X-Terminal；如果已经允许，再检查当前 Wi-Fi / AP 是否开启了 client isolation。"
        }

        var highlights = [
            "primary_sections=pair_hub,choose_model,grant_permissions,security_runtime,diagnostics",
            "remote_lan_blocked=true"
        ]
        if !rootCause.isEmpty {
            highlights.append("local_hub_root_cause=\(rootCause)")
        }
        if blockedCapabilities != "none" {
            highlights.append("local_hub_blocked_capabilities=\(blockedCapabilities)")
        }

        return StatusExplanation(
            state: .permissionDenied,
            headline: "设置中心当前优先处理：XT 只能看到本机 loopback Hub",
            whatHappened: "当前发现阶段没有命中远端 Hub，所以 pairing 请求还没真正发到 Hub 端；XT 现在看到的只有自己机器上的 loopback Hub。",
            whyItHappened: whyItHappened,
            userAction: state.runtime.nextRepairAction ?? userAction,
            machineStatusRef: machineStatusRef,
            hardLine: "先修 Local Network / Wi-Fi policy，再继续远端 Hub 配对",
            highlights: mergedHighlights(highlights, runtime: state.runtime)
        )
    }

    private static func localNetworkRepairSubtitle(failureCode: String) -> String? {
        guard isLocalNetworkFailureCode(failureCode) else { return nil }
        let launchStatus = localHubLaunchStatusIfNeeded(for: failureCode)
        guard let launchStatus, launchStatus.blocksPaidOrWebCapabilities else {
            return "XT 只看见本机 loopback Hub；先打开本地网络权限，若已允许再检查当前 Wi-Fi / AP 是否开启了 client isolation。"
        }
        let rootCause = launchStatus.rootCauseErrorCode.isEmpty
            ? "本机 bridge"
            : launchStatus.rootCauseErrorCode
        return "XT 只看见本机 loopback Hub；另外本机 fallback Hub 也处于 \(rootCause)，\(launchStatus.blockedCapabilitiesSummary) 仍被阻塞。先修本地网络，再到 REL Flow Hub → Diagnostics & Recovery 修 bridge。"
    }

    private static func localHubLaunchStatusIfNeeded(
        for failureCode: String
    ) -> XTHubLaunchStatusSnapshot? {
        guard isLocalNetworkFailureCode(failureCode) else { return nil }
        return XTHubLaunchStatusStore.load()
    }

    private static func isLocalNetworkFailureCode(_ failureCode: String) -> Bool {
        let normalized = UITroubleshootKnowledgeBase.normalizedFailureCode(failureCode)
        return normalized.contains("local_network_permission_required")
            || normalized.contains("local_network_discovery_blocked")
    }

    fileprivate static func connectHubSubtitle(
        issue: UITroubleshootIssue?,
        connected: Bool,
        linking: Bool,
        connectedSummary: String? = nil
    ) -> String {
        if linking {
            return "正在发现 Hub、刷新配对并建立连接"
        }
        switch issue {
        case .pairingRepairRequired:
            return "当前需要清理旧配对后重新连接"
        case .multipleHubsAmbiguous:
            return "先固定目标 Hub，再继续连接"
        case .hubPortConflict:
            return "先修复端口冲突，再继续连接"
        case .hubUnreachable:
            return "先核对 Hub 可达性，再继续连接"
        default:
            if connected {
                return connectedSummary ?? "Hub 已连通；需要改参数或修复时看下方连接区"
            }
            return "先把发现、配对和连接这条主链走通"
        }
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
    @StateObject private var modelManager = HubModelManager.shared
    @StateObject private var securityRuntimeUpdateFeedback = XTTransientUpdateFeedbackState()
    @State private var activeFocusRequest: XTSettingsFocusRequest?
    @State private var connectionToolsExpanded = false
    @State private var defaultToolSandboxMode: ToolSandboxMode = ToolExecutor.sandboxMode()
    @State private var securityRuntimeChangeNotice: XTSettingsChangeNotice?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: UIThemeTokens.sectionSpacing) {
                    headerSection
                    PrimaryActionRail(title: "首用动作", actions: quickActions, onTap: handleAction)
                    StatusExplanationCard(explanation: settingsStatus)
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
                modelManager.setAppModel(appModel)
                if appModel.hubInteractive {
                    Task {
                        await modelManager.fetchModels()
                    }
                }
            }
            .onChange(of: appModel.hubInteractive) { connected in
                if connected {
                    Task {
                        await modelManager.fetchModels()
                    }
                }
            }
            .onChange(of: appModel.settingsFocusRequest?.nonce) { _ in
                processSettingsFocusRequest(proxy)
            }
            .onDisappear {
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
            Text("把连接、模型、授权、安全和诊断收口到同一页。上面先做动作，下面再看状态和修复工具。")
                .font(UIThemeTokens.bodyFont())
                .foregroundStyle(.secondary)
        }
    }

    private var settingsCenterOverview: some View {
        GroupBox("任务入口") {
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
                if let context = focusContext(for: "pair_hub") {
                    XTFocusContextCard(context: context)
                }

                Text(pairHubIntroText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let inviteStatusPresentation {
                    HubInviteStatusCard(presentation: inviteStatusPresentation)
                }

                HStack {
                    Text("当前状态")
                    Spacer()
                    Text(connectionStateLabel)
                        .font(UIThemeTokens.monoFont())
                        .foregroundStyle(connectionStateColor)
                }

                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: pairProgressValue, total: 3.0)
                    Text(pairProgressHintText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                stepRow(title: "发现", subtitle: "发现 Hub（局域网优先）", state: appModel.hubSetupDiscoverState)
                stepRow(title: "配对", subtitle: "配对 + 凭据下发", state: appModel.hubSetupBootstrapState)
                stepRow(title: "连接", subtitle: "建立连接并启用自动重连", state: appModel.hubSetupConnectState)

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

                DisclosureGroup(isExpanded: $connectionToolsExpanded) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("自动探测失败、需要固定目标 Hub，或要清掉旧配对时，再展开这里。")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 10) {
                            Button(appModel.hubPortAutoDetectRunning ? "探测中..." : "自动探测") {
                                appModel.maybeAutoFillHubSetupPathAndPorts(force: true)
                            }
                            .buttonStyle(.bordered)
                            .disabled(appModel.hubRemoteLinking)

                            Button(appModel.hubRemoteLinking ? "重置中..." : "清除配对后重连") {
                                appModel.resetPairingStateAndOneClickSetup()
                            }
                            .buttonStyle(.bordered)
                            .disabled(appModel.hubRemoteLinking || appModel.hubPortAutoDetectRunning)
                        }

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
                                Text("正式入口")
                                    .frame(width: 140, alignment: .leading)
                                VStack(alignment: .leading, spacing: 4) {
                                    TextField("hub.xhubsystem.com", text: internetHostBinding)
                                        .textFieldStyle(.roundedBorder)
                                    Text(formalEntryGuidancePresentation.message)
                                        .font(.caption)
                                        .foregroundStyle(formalEntryGuidancePresentation.state.tint)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            GridRow {
                                Text("邀请令牌（首配用）")
                                    .frame(width: 140, alignment: .leading)
                                VStack(alignment: .leading, spacing: 4) {
                                    TextField("来自 Hub 邀请链接", text: inviteTokenBinding)
                                        .textFieldStyle(.roundedBorder)
                                    Text(inviteTokenGuidancePresentation.message)
                                        .font(.caption)
                                        .foregroundStyle(inviteTokenGuidancePresentation.state.tint)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            GridRow {
                                Text("axhubctl 路径")
                                    .frame(width: 140, alignment: .leading)
                                TextField("自动探测", text: axhubctlPathBinding)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }
                    }
                    .padding(.top, 8)
                } label: {
                    HStack {
                        Text("连接参数与修复工具")
                            .font(.headline)
                        Spacer()
                        Text(connectionToolsExpanded ? "展开中" : "已折叠")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(8)
        }
    }

    private var chooseModelSection: some View {
        let hubBaseDir = appModel.hubBaseDir ?? HubPaths.baseDir()
        let configuredRoles = AXRole.allCases.filter { configuredGlobalModelID(for: $0) != nil }.count
        let guidance = XTModelGuidancePresentation.build(
            settings: appModel.settingsStore.settings,
            snapshot: visibleModelSnapshot,
            doctorReport: XHubDoctorOutputStore.loadHubReport(baseDir: hubBaseDir),
            runtimeMonitor: XHubDoctorOutputStore.loadHubLocalRuntimeMonitorSnapshot(baseDir: hubBaseDir),
            currentProjectName: selectedProjectDisplayName,
            currentProjectContext: appModel.projectContext,
            currentProjectCoderModelId: appModel.projectConfig?.modelOverride(for: .coder),
            currentRemotePaidAccessSnapshot: appModel.hubRemotePaidAccessSnapshot
        )

        return GroupBox("2) AI 模型主入口") {
            VStack(alignment: .leading, spacing: 10) {
                if let context = focusContext(for: "choose_model") {
                    XTFocusContextCard(context: context)
                }
                Text("这里不再维护第二套可编辑模型面板；角色绑定、模型替换和路由修复统一收口到 Supervisor Control Center · AI 模型。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("已配置模型角色：\(configuredRoles)/\(AXRole.allCases.count)")
                            .font(UIThemeTokens.monoFont())
                            .foregroundStyle(.secondary)
                        Text(configuredRoles > 0 ? "当前页只做摘要；需要修改时直接跳到统一模型入口。" : "当前还没有完成首用角色绑定，建议先至少配置 coder / supervisor。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("打开 Supervisor Control Center · AI 模型") {
                        openSupervisorModelSettings(
                            title: "检查当前全局角色绑定",
                            detail: "XT Settings 这里只保留摘要；模型编辑、替换和修复统一进入 Supervisor Control Center · AI 模型。"
                        )
                    }
                    .buttonStyle(.borderedProminent)
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
                        Text("当前绑定")
                            .foregroundStyle(.secondary)
                        Text("入口")
                            .foregroundStyle(.secondary)
                    }
                    .font(UIThemeTokens.monoFont())

                    ForEach(AXRole.allCases) { role in
                        GridRow {
                            Text(role.displayName)
                                .font(UIThemeTokens.monoFont())
                                .frame(width: 120, alignment: .leading)

                            Text(configuredGlobalModelID(for: role) ?? "未配置")
                                .font(UIThemeTokens.monoFont())
                                .foregroundStyle(configuredGlobalModelID(for: role) == nil ? UIThemeTokens.color(for: .inProgress) : .primary)
                                .frame(width: 360, alignment: .leading)

                            Button("定位") {
                                openSupervisorModelSettings(
                                    role: role,
                                    title: "检查 \(role.displayName) 模型绑定",
                                    detail: configuredGlobalModelID(for: role).map {
                                        "当前记录的模型是 `\($0)`；如需替换、核对 inventory 或修复路由，请直接在统一模型入口处理。"
                                    } ?? "当前角色还没有绑定模型；请在统一模型入口完成首用配置。"
                                )
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
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
                                Button("定位到 \(issue.role.displayName)") {
                                    openSupervisorModelSettings(
                                        role: issue.role,
                                        title: "处理 \(issue.role.displayName) 模型阻塞",
                                        detail: issue.suggestedModelId.map {
                                            "\(issue.message) 建议优先检查 `\($0)` 是否已经进入真实可执行列表。"
                                        } ?? issue.message
                                    )
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
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

                Text("建议至少先配置 coder 与 supervisor；如果付费模型被授权拦住，先去 REL Flow Hub → Models & Paid Access / Grants & Permissions，再回统一模型入口确认实际可执行列表。")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            .padding(8)
        }
    }

    private var grantAndRepairSection: some View {
        GroupBox("3) 授权与排障") {
            VStack(alignment: .leading, spacing: 10) {
                TroubleshootPanel(
                    title: "3 步内定位修复入口",
                    issues: UITroubleshootIssue.highFrequencyIssues,
                    paidAccessSnapshot: appModel.hubRemotePaidAccessSnapshot,
                    internetHost: appModel.hubInternetHost,
                    pairingContext: troubleshootPairingContext
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
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .center, spacing: 8) {
                        Text("历史项目修复")
                        Spacer()
                        Button("重跑修复") {
                            appModel.repairHistoricalProjectBoundariesNow(
                                reason: "settings_diagnostics_manual"
                            )
                        }
                        .buttonStyle(.bordered)
                    }
                    Text("补齐 registry 已登记项目缺失的 config.json 和 project memory；只修复缺失边界，不删除项目 root。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    historicalProjectBoundaryRepairStatus
                }

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

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .center, spacing: 8) {
                        Text("Supervisor 语音自检")
                        Spacer()
                        if appModel.supervisorVoiceSmokeRunning {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Button("打开报告") {
                            appModel.openSupervisorVoiceSmokeReport()
                        }
                        .buttonStyle(.borderless)
                        .disabled(!appModel.canOpenSupervisorVoiceSmokeReport)
                        Button(appModel.supervisorVoiceSmokeRunning ? "运行中..." : "运行自检") {
                            appModel.runSupervisorVoiceSmokeDiagnostics()
                        }
                        .buttonStyle(.bordered)
                        .disabled(appModel.supervisorVoiceSmokeRunning)
                    }
                    if !appModel.supervisorVoiceSmokeStatusLine.isEmpty {
                        Text(appModel.supervisorVoiceSmokeStatusLine)
                            .font(UIThemeTokens.monoFont())
                            .foregroundStyle(supervisorVoiceSmokeStatusColor)
                            .textSelection(.enabled)
                    }
                    if !appModel.supervisorVoiceSmokeDetailLine.isEmpty {
                        Text(appModel.supervisorVoiceSmokeDetailLine)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }

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

                if !appModel.skillsCompatibilitySnapshot.governanceSurfaceEntries.isEmpty {
                    XTSkillGovernanceSurfaceView(
                        items: appModel.skillsCompatibilitySnapshot.governanceSurfaceEntries
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
                            Text(
                                AXRouteRepairLogStore.watchHeadline(
                                    for: routeRepairLogDigest,
                                    paidAccessSnapshot: appModel.hubRemotePaidAccessSnapshot
                                )
                            )
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
        guard let orchestrator = appModel.legacySupervisorRuntimeContextIfLoaded?.orchestrator else {
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
        let snapshot = visibleModelSnapshot
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

    private var supervisorVoiceSmokeStatusColor: Color {
        if appModel.supervisorVoiceSmokeRunning {
            return UIThemeTokens.color(for: .inProgress)
        }
        switch appModel.supervisorVoiceSmokeLastPassed {
        case true:
            return UIThemeTokens.color(for: .ready)
        case false:
            return UIThemeTokens.color(for: .diagnosticRequired)
        case nil:
            return .secondary
        }
    }

    private var historicalProjectBoundaryRepairStatusColor: Color {
        let line = appModel.historicalProjectBoundaryRepairStatusLine
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if line.contains("historical_project_boundary_repair=running") {
            return UIThemeTokens.color(for: .inProgress)
        }
        if line.contains("historical_project_boundary_repair=repaired") {
            return UIThemeTokens.color(for: .ready)
        }
        if line.contains("historical_project_boundary_repair=partial")
            || line.contains("historical_project_boundary_repair=failed") {
            return UIThemeTokens.color(for: .diagnosticRequired)
        }
        return .secondary
    }

    private func handleAction(_ action: PrimaryActionRailAction) {
        switch action.id {
        case "connect_hub":
            handleConnectHubAction()
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
                detail = XTSettingsSurfacePlanner.reviewSubtitle(
                    issue: issue,
                    failureCode: settingsState.failureCode,
                    runtime: runtimeSnapshot,
                    pairingContext: troubleshootPairingContext
                )
            case .connectorScopeBlocked:
                targetSection = "security_runtime"
                title = "查看远端导出与安全边界修复入口"
                detail = XTSettingsSurfacePlanner.reviewSubtitle(
                    issue: issue,
                    failureCode: settingsState.failureCode,
                    runtime: runtimeSnapshot,
                    pairingContext: troubleshootPairingContext
                )
            case .modelNotReady:
                openSupervisorModelSettings(
                    role: .coder,
                    title: UITroubleshootKnowledgeBase.repairEntryTitle(for: issue),
                    detail: XTSettingsSurfacePlanner.reviewSubtitle(
                        issue: issue,
                        failureCode: settingsState.failureCode,
                        runtime: runtimeSnapshot,
                        pairingContext: troubleshootPairingContext
                    )
                )
                return
            case .permissionDenied:
                targetSection = "grant_permissions"
                title = "查看权限与 policy 修复入口"
                detail = XTSettingsSurfacePlanner.reviewSubtitle(
                    issue: issue,
                    failureCode: settingsState.failureCode,
                    runtime: runtimeSnapshot,
                    pairingContext: troubleshootPairingContext
                )
            case .pairingRepairRequired, .multipleHubsAmbiguous, .hubPortConflict:
                targetSection = "pair_hub"
                title = UITroubleshootKnowledgeBase.repairEntryTitle(for: issue)
                detail = XTSettingsSurfacePlanner.reviewSubtitle(
                    issue: issue,
                    failureCode: settingsState.failureCode,
                    runtime: runtimeSnapshot,
                    pairingContext: troubleshootPairingContext
                )
            case .hubUnreachable, .none:
                targetSection = "diagnostics"
                title = "查看连接与诊断入口"
                detail = XTSettingsSurfacePlanner.reviewSubtitle(
                    issue: issue,
                    failureCode: settingsState.failureCode,
                    runtime: runtimeSnapshot,
                    pairingContext: troubleshootPairingContext
                )
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

    private func handleConnectHubAction() {
        commitPendingHubEndpointEdits()
        let issue = XTSettingsSurfacePlanner.issue(for: settingsState)
        switch issue {
        case .pairingRepairRequired:
            connectionToolsExpanded = true
            appModel.resetPairingStateAndOneClickSetup()
        case .multipleHubsAmbiguous:
            connectionToolsExpanded = true
            appModel.requestSettingsFocus(
                sectionId: "pair_hub",
                title: "固定目标 Hub 后继续连接",
                detail: UITroubleshootKnowledgeBase.repairEntryDetail(
                    for: .multipleHubsAmbiguous,
                    runtime: runtimeSnapshot
                )
            )
        case .hubPortConflict:
            connectionToolsExpanded = true
            appModel.requestSettingsFocus(
                sectionId: "pair_hub",
                title: "修复 Hub 端口冲突",
                detail: UITroubleshootKnowledgeBase.repairEntryDetail(
                    for: .hubPortConflict,
                    runtime: runtimeSnapshot
                )
            )
        default:
            if appModel.hubRemoteLinking || settingsState.hubInteractive {
                appModel.requestSettingsFocus(
                    sectionId: "pair_hub",
                    title: "查看连接进度",
                    detail: "这里直接看发现 / 配对 / 连接的当前状态；需要手动修复时，再展开连接参数与修复工具。"
                )
            } else {
                appModel.startHubOneClickSetup()
            }
        }
    }

    private func commitPendingHubEndpointEdits() {
        NSApp.keyWindow?.makeFirstResponder(nil)
        if NSApp.mainWindow !== NSApp.keyWindow {
            NSApp.mainWindow?.makeFirstResponder(nil)
        }
    }

    private var visibleModelSnapshot: ModelStateSnapshot {
        modelManager.visibleSnapshot(fallback: appModel.modelsState)
    }

    private var troubleshootPairingContext: UITroubleshootPairingContext? {
        UITroubleshootPairingContext(
            firstPairCompletionProofSnapshot: appModel.unifiedDoctorReport.firstPairCompletionProofSnapshot,
            pairedRouteSetSnapshot: appModel.unifiedDoctorReport.pairedRouteSetSnapshot
        )
    }

    private func configuredGlobalModelID(for role: AXRole) -> String? {
        let modelID = appModel.settingsStore.settings.assignment(for: role).model?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return modelID.isEmpty ? nil : modelID
    }

    private func openSupervisorModelSettings(
        role: AXRole? = nil,
        title: String,
        detail: String
    ) {
        appModel.requestModelSettingsFocus(
            role: role,
            title: title,
            detail: detail
        )
        supervisorManager.requestSupervisorWindow(
            sheet: .modelSettings,
            reason: "settings_model_settings",
            focusConversation: false,
            startConversation: false
        )
    }

    private var pairingPortBinding: Binding<Int> {
        Binding(
            get: { appModel.hubPairingPort },
            set: { value in
                appModel.setHubPairingPortFromUser(value)
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
                appModel.setHubGrpcPortFromUser(value)
            }
        )
    }

    private var inviteStatusPresentation: HubInviteStatusPresentation? {
        HubInviteStatusPlanner.build(
            inviteAlias: appModel.hubInviteAlias,
            internetHost: appModel.hubInternetHost,
            pairingPort: appModel.hubPairingPort,
            grpcPort: appModel.hubGrpcPort,
            inviteToken: appModel.hubInviteToken,
            hubInstanceID: appModel.hubInviteInstanceID,
            connected: appModel.hubInteractive,
            linking: appModel.hubRemoteLinking,
            failureCode: appModel.hubSetupFailureCode
        )
    }

    private var pairHubIntroText: String {
        if UITroubleshootKnowledgeBase.isInviteTokenFailure(appModel.hubSetupFailureCode) {
            return "当前是邀请配对修复路径：先重新载入 Hub 邀请，再继续发现、配对和连接。"
        }
        if !(appModel.hubInviteToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
            return "上面的首用动作负责连接；当前已载入正式首配参数，通常可直接继续。"
        }
        if hasStableFormalEntry {
            return "上面的首用动作负责连接；当前正式入口已设置，XT 后续切网与自愈都会优先验证这条路径。"
        }
        return "上面的首用动作负责连接；这里主要用来看状态，必要时再展开底层修复工具。"
    }

    private var internetHostBinding: Binding<String> {
        Binding(
            get: { appModel.hubInternetHost },
            set: { value in
                appModel.setHubInternetHostFromUser(value)
            }
        )
    }

    private var inviteTokenBinding: Binding<String> {
        Binding(
            get: { appModel.hubInviteToken },
            set: { value in
                appModel.hubInviteToken = value
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

    private var pairProgressValue: Double {
        stepScore(appModel.hubSetupDiscoverState)
            + stepScore(appModel.hubSetupBootstrapState)
            + stepScore(appModel.hubSetupConnectState)
    }

    private var pairProgressHintText: String {
        if UITroubleshootKnowledgeBase.isInviteTokenFailure(appModel.hubSetupFailureCode) {
            return "当前先修复邀请令牌，再继续连接。"
        }
        if !appModel.hubInviteToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "正式首配参数已载入，通常可直接继续连接。"
        }
        if hasStableFormalEntry {
            return "正式入口已设置；切网后 XT 会优先验证这条路径。"
        }
        return "进入页面会先自动探测一轮；需要手动修复时，再展开连接参数与修复工具。"
    }

    private var formalEntryGuidancePresentation: HubRemoteAccessGuidancePresentation {
        HubRemoteAccessGuidanceBuilder.formalEntry(
            internetHost: appModel.hubInternetHost
        )
    }

    private var inviteTokenGuidancePresentation: HubRemoteAccessGuidancePresentation {
        HubRemoteAccessGuidanceBuilder.inviteToken(
            internetHost: appModel.hubInternetHost,
            inviteToken: appModel.hubInviteToken
        )
    }

    private var hasStableFormalEntry: Bool {
        if case .stableNamed = XTHubRemoteAccessHostClassification
            .classify(appModel.hubInternetHost).kind {
            return true
        }
        return false
    }

    private var connectionStateColor: Color {
        if appModel.hubConnected { return .secondary }
        if appModel.hubRemoteLinking { return UIThemeTokens.color(for: .inProgress) }
        if appModel.hubRemoteConnected { return UIThemeTokens.color(for: .inProgress) }
        return UIThemeTokens.color(for: .permissionDenied)
    }

    @ViewBuilder
    private func stepRow(title: String, subtitle: String, state: HubSetupStepState) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: iconName(for: state))
                .foregroundStyle(iconColor(for: state))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(labelText(for: state))
                .font(UIThemeTokens.monoFont())
                .foregroundStyle(iconColor(for: state))
        }
    }

    private func stepScore(_ state: HubSetupStepState) -> Double {
        switch state {
        case .idle:
            return 0.0
        case .running:
            return 0.4
        case .awaitingApproval:
            return 0.6
        case .success, .failed, .skipped:
            return 1.0
        }
    }

    private func iconName(for state: HubSetupStepState) -> String {
        switch state {
        case .idle:
            return "circle"
        case .running:
            return "clock.arrow.circlepath"
        case .awaitingApproval:
            return "lock.shield.fill"
        case .success:
            return "checkmark.circle.fill"
        case .failed:
            return "xmark.octagon.fill"
        case .skipped:
            return "arrow.right.circle.fill"
        }
    }

    private func iconColor(for state: HubSetupStepState) -> Color {
        switch state {
        case .idle:
            return .secondary
        case .running:
            return UIThemeTokens.color(for: .inProgress)
        case .awaitingApproval:
            return .orange
        case .success:
            return UIThemeTokens.color(for: .ready)
        case .failed:
            return UIThemeTokens.color(for: .permissionDenied)
        case .skipped:
            return .gray
        }
    }

    private func labelText(for state: HubSetupStepState) -> String {
        switch state {
        case .idle:
            return "idle"
        case .running:
            return "running"
        case .awaitingApproval:
            return "awaiting approval"
        case .success:
            return "ok"
        case .failed:
            return "failed"
        case .skipped:
            return "skipped"
        }
    }

    private func processSettingsFocusRequest(_ proxy: ScrollViewProxy) {
        guard let request = appModel.settingsFocusRequest else { return }
        activeFocusRequest = request
        if request.sectionId == "pair_hub" {
            connectionToolsExpanded = true
        }
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

    @ViewBuilder
    private var historicalProjectBoundaryRepairStatus: some View {
        let statusLine = appModel.historicalProjectBoundaryRepairStatusLine
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !statusLine.isEmpty {
            Text(statusLine)
                .font(UIThemeTokens.monoFont())
                .foregroundStyle(historicalProjectBoundaryRepairStatusColor)
                .textSelection(.enabled)
        }
    }
}

private struct XTSettingsFocusCard: View {
    let section: XTSettingsSectionDescriptor

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(section.title)
                .font(.headline)
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
