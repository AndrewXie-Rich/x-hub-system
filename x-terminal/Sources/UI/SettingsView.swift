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
        XTSettingsSectionDescriptor(id: "external_terminals", title: "非 XT Terminal 访问", summary: "管理给外部 terminal 使用的 access key、导出 env 和轮换撤销。", repairEntry: "XT Settings → 非 XT Terminal 访问"),
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

private struct XTSettingsTaskSection<Content: View>: View {
    let iconName: String
    let title: String
    let subtitle: String
    var badgeText: String?
    let content: Content

    init(
        iconName: String,
        title: String,
        subtitle: String,
        badgeText: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.iconName = iconName
        self.title = title
        self.subtitle = subtitle
        self.badgeText = badgeText
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: iconName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 10)

                if let badgeText, !badgeText.isEmpty {
                    Text(badgeText)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.10))
                        .clipShape(Capsule())
                }
            }

            Divider()

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
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
        let issue = issue(for: state)
        let pairingContext = pairingContext(for: state)
        let externalTerminalAccessProjection = externalTerminalAccessProjection(for: state)
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
                    pairingContext: pairingContext,
                    externalTerminalAccessProjection: externalTerminalAccessProjection
                ).steps.first?.instruction ?? "先按排障主链继续。",
                machineStatusRef: machineStatusRef,
                hardLine: "先修当前阻塞，再继续后续步骤",
                highlights: mergedHighlights([
                    "primary_sections=pair_hub,choose_model,grant_permissions,external_terminals,security_runtime,diagnostics"
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
                "primary_sections=pair_hub,choose_model,grant_permissions,external_terminals,security_runtime,diagnostics"
            ], runtime: state.runtime)
        )
    }

    static func quickActions(for state: XTSettingsSurfaceState) -> [PrimaryActionRailAction] {
        let issue = issue(for: state)
        let pairingContext = pairingContext(for: state)
        let externalTerminalAccessProjection = externalTerminalAccessProjection(for: state)
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
                    pairingContext: pairingContext,
                    externalTerminalAccessProjection: externalTerminalAccessProjection
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
        UITroubleshootKnowledgeBase.issue(forFailureCode: state.failureCode)
            ?? state.runtime.primaryIssue
            ?? state.doctor.currentFailureIssue
            ?? externalTerminalAccessProjection(for: state)?.primaryIssue
    }

    fileprivate static func pairingContext(for state: XTSettingsSurfaceState) -> UITroubleshootPairingContext? {
        UITroubleshootPairingContext(
            firstPairCompletionProofSnapshot: state.doctor.firstPairCompletionProofSnapshot,
            pairedRouteSetSnapshot: state.doctor.pairedRouteSetSnapshot
        )
    }

    fileprivate static func externalTerminalAccessProjection(
        for state: XTSettingsSurfaceState
    ) -> XTUnifiedDoctorExternalTerminalAccessProjection? {
        state.doctor.section(.externalTerminalAccessReadiness)?.externalTerminalAccessProjection
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
        pairingContext: UITroubleshootPairingContext? = nil,
        externalTerminalAccessProjection: XTUnifiedDoctorExternalTerminalAccessProjection? = nil
    ) -> String {
        if let subtitle = localNetworkRepairSubtitle(failureCode: failureCode) {
            return subtitle
        }
        if issue == .pairingRepairRequired
            || issue == .multipleHubsAmbiguous
            || issue == .hubPortConflict
            || issue == .hubUnreachable
            || issue == .connectorScopeBlocked
            || issue == .externalTerminalAccessBlocked {
            return UITroubleshootKnowledgeBase.repairEntryDetail(
                for: issue,
                runtime: runtime,
                pairingContext: pairingContext,
                externalTerminalAccessProjection: externalTerminalAccessProjection
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
            "primary_sections=pair_hub,choose_model,grant_permissions,external_terminals,security_runtime,diagnostics",
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
    let embeddedInControlCenter: Bool

    @Environment(\.xtAppModelReference) private var appModelReference
    @EnvironmentObject private var settingsSurfaceProjectionStore: XTSettingsSurfaceProjectionStore
    @EnvironmentObject private var navigationFocusStore: XTNavigationFocusStore
    private let supervisorManager = SupervisorManager.shared
    @StateObject private var modelManager = HubModelManager.shared
    @StateObject private var providerOAuthLoginModel = ProviderOAuthLoginModel()
    @StateObject private var securityRuntimeUpdateFeedback = XTTransientUpdateFeedbackState()
    @State private var activeFocusRequest: XTSettingsFocusRequest?
    @State private var selectedSettingsSectionID: String
    @State private var connectionToolsExpanded = false
    @State private var statusDetailsExpanded = false
    @State private var diagnosticsDetailsExpanded = false
    @State private var defaultToolSandboxMode: ToolSandboxMode = ToolExecutor.sandboxMode()
    @State private var securityRuntimeChangeNotice: XTSettingsChangeNotice?
    @State private var rustHubReadinessPresentation = RustHubReadinessPresentation.loading()
    @State private var rustHubReadinessRefreshID = 0

    init(embeddedInControlCenter: Bool = false) {
        self.embeddedInControlCenter = embeddedInControlCenter
        _selectedSettingsSectionID = State(
            initialValue: XTSettingsCenterManifest.sections.first?.id ?? "pair_hub"
        )
    }

    var body: some View {
        ScrollViewReader { proxy in
            Group {
                if embeddedInControlCenter {
                    ScrollView {
                        settingsDetailContent(proxy: proxy)
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    .background(Color(nsColor: .windowBackgroundColor))
                } else {
                    HStack(spacing: 0) {
                        settingsNavigationPane(proxy: proxy)

                        Divider()

                        ScrollView {
                            settingsDetailContent(proxy: proxy)
                                .padding(16)
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                        .background(Color(nsColor: .windowBackgroundColor))
                    }
                }
            }
            .onAppear {
                processSettingsFocusRequest(proxy)
                appModel.maybeAutoFillHubSetupPathAndPorts(force: false)
                defaultToolSandboxMode = ToolExecutor.sandboxMode()
                modelManager.setAppModel(appModel)
                if settingsSnapshot.hubInteractive {
                    Task {
                        await modelManager.fetchModels()
                    }
                }
            }
            .onChange(of: settingsSnapshot.hubInteractive) { connected in
                if connected {
                    Task {
                        await modelManager.fetchModels()
                    }
                }
            }
            .onChange(of: navigationFocusSnapshot.settingsFocusRequest?.nonce) { _ in
                processSettingsFocusRequest(proxy)
            }
            .task(id: rustHubReadinessRefreshID) {
                await refreshRustHubReadiness()
            }
            .onDisappear {
                securityRuntimeUpdateFeedback.cancel(resetState: true)
                securityRuntimeChangeNotice = nil
            }
        }
        .frame(
            minWidth: embeddedInControlCenter ? 720 : 860,
            idealWidth: embeddedInControlCenter ? 900 : 960,
            minHeight: 720
        )
    }

    private func settingsDetailContent(proxy: ScrollViewProxy) -> some View {
        LazyVStack(alignment: .leading, spacing: UIThemeTokens.sectionSpacing) {
            Color.clear
                .frame(height: 0)
                .id("settings_detail_top")

            headerSection
            settingsStatusSummary
            compactQuickActions
            selectedSettingsSectionContent(proxy: proxy)
        }
    }

    private func settingsNavigationPane(proxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("设置")
                    .font(.title3.weight(.semibold))
                Text("按任务分组")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(XTSettingsCenterManifest.sections) { section in
                    Button {
                        selectSettingsSection(section.id, proxy: proxy)
                    } label: {
                        HStack(alignment: .center, spacing: 10) {
                            Image(systemName: settingsSectionIconName(section.id))
                                .frame(width: 18)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(section.title)
                                    .font(.subheadline.weight(.semibold))
                                Text(settingsSectionShortSummary(section))
                                    .font(.caption2)
                                    .foregroundStyle(selectedSettingsSectionID == section.id ? .white.opacity(0.82) : .secondary)
                                    .lineLimit(1)
                            }

                            Spacer(minLength: 6)

                            if let badge = settingsSectionBadge(section.id) {
                                Text(badge)
                                    .font(.caption2.monospaced())
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(
                                        Capsule()
                                            .fill(selectedSettingsSectionID == section.id ? Color.white.opacity(0.16) : Color.secondary.opacity(0.10))
                                    )
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 9)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: UIThemeTokens.cardRadius, style: .continuous)
                                .fill(selectedSettingsSectionID == section.id ? Color.accentColor : Color.clear)
                        )
                        .foregroundStyle(selectedSettingsSectionID == section.id ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer(minLength: 12)

            VStack(alignment: .leading, spacing: 8) {
                Text("当前")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                XTCompactStatusPill(
                    iconName: "link.circle",
                    text: connectionStateLabel,
                    tint: connectionStateColor,
                    monospaced: true
                )

                XTCompactStatusPill(
                    iconName: "brain.head.profile",
                    text: "模型 \(configuredGlobalModelRoleCount)/\(AXRole.allCases.count)",
                    tint: configuredGlobalModelRoleCount == AXRole.allCases.count
                        ? UIThemeTokens.color(for: .ready)
                        : UIThemeTokens.color(for: .inProgress),
                    monospaced: true
                )

                XTCompactStatusPill(
                    iconName: defaultToolSandboxMode == .host ? "desktopcomputer" : "lock.shield",
                    text: defaultToolSandboxMode == .host ? "host tools" : "sandbox tools",
                    tint: defaultToolSandboxMode == .host
                        ? UIThemeTokens.color(for: .grantRequired)
                        : UIThemeTokens.color(for: .ready),
                    monospaced: true
                )

                Text(selectedSettingsSection.repairEntry)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: UIThemeTokens.cardRadius, style: .continuous)
                    .fill(UIThemeTokens.secondaryCardBackground)
            )
        }
        .padding(14)
        .frame(minWidth: 260, idealWidth: 260, maxWidth: 260, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var settingsStatusSummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: settingsStatus.state.iconName)
                    .font(.title3)
                    .foregroundStyle(settingsStatus.state.tint)

                VStack(alignment: .leading, spacing: 4) {
                    Text(settingsStatus.headline)
                        .font(.headline)
                    Text(settingsStatus.userAction)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                XTCompactStatusPill(
                    iconName: "link.circle",
                    text: connectionStateLabel,
                    tint: connectionStateColor,
                    monospaced: true
                )
            }

            DisclosureGroup(isExpanded: $statusDetailsExpanded) {
                StatusExplanationCard(explanation: settingsStatus)
                    .padding(.top, 6)
            } label: {
                Text(statusDetailsExpanded ? "收起完整状态" : "查看完整状态")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: UIThemeTokens.cardRadius, style: .continuous)
                .fill(UIThemeTokens.stateBackground(for: settingsStatus.state))
        )
        .overlay(
            RoundedRectangle(cornerRadius: UIThemeTokens.cardRadius, style: .continuous)
                .stroke(settingsStatus.state.tint.opacity(0.22), lineWidth: 1)
        )
    }

    private var compactQuickActions: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 180), spacing: 10)],
            alignment: .leading,
            spacing: 10
        ) {
            ForEach(quickActions) { action in
                Button {
                    handleAction(action)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(action.title, systemImage: action.systemImage)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        if let subtitle = action.subtitle, !subtitle.isEmpty {
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                }
                .buttonStyle(.bordered)
                .tint(action.style == .diagnostic ? UIThemeTokens.color(for: .releaseFrozen) : nil)
            }

            Button {
                supervisorManager.requestSupervisorWindow(
                    sheet: .supervisorSettings,
                    reason: "settings_center_open_supervisor_settings",
                    focusConversation: false
                )
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Supervisor 设置", systemImage: "person.3.sequence")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text("语音、人格、个人记忆、心跳和项目模型")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            }
            .buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    private func selectedSettingsSectionContent(proxy: ScrollViewProxy) -> some View {
        switch selectedSettingsSectionID {
        case "pair_hub":
            pairHubSection
                .id("pair_hub")
        case "choose_model":
            chooseModelSection
                .id("choose_model")
        case "grant_permissions":
            grantAndRepairSection
                .id("grant_permissions")
        case "external_terminals":
            externalTerminalAccessSection { anchorID in
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(anchorID, anchor: .center)
                }
            }
            .id("external_terminals")
        case "security_runtime":
            securityRuntimeSection
                .id("security_runtime")
        case "diagnostics":
            diagnosticsSection
                .id("diagnostics")
        default:
            pairHubSection
                .id("pair_hub")
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(selectedSettingsSection.title)
                        .font(UIThemeTokens.sectionFont())
                    Text(selectedSettingsSection.summary)
                        .font(UIThemeTokens.bodyFont())
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                Text("XT 设置中心")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            settingsHeaderStatusPills
        }
    }

    private var settingsHeaderStatusPills: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                settingsHeaderStatusPillContent
            }

            VStack(alignment: .leading, spacing: 6) {
                settingsHeaderStatusPillContent
            }
        }
    }

    @ViewBuilder
    private var settingsHeaderStatusPillContent: some View {
        XTCompactStatusPill(
            iconName: "link.circle",
            text: connectionStateLabel,
            tint: connectionStateColor,
            monospaced: true
        )
        XTCompactStatusPill(
            iconName: "brain.head.profile",
            text: "模型 \(configuredGlobalModelRoleCount)/\(AXRole.allCases.count)",
            tint: configuredGlobalModelRoleCount == AXRole.allCases.count
                ? UIThemeTokens.color(for: .ready)
                : UIThemeTokens.color(for: .inProgress),
            monospaced: true
        )
        XTCompactStatusPill(
            iconName: defaultToolSandboxMode == .host ? "desktopcomputer" : "lock.shield",
            text: defaultToolSandboxMode == .host ? "host tools" : "sandbox tools",
            tint: defaultToolSandboxMode == .host
                ? UIThemeTokens.color(for: .grantRequired)
                : UIThemeTokens.color(for: .ready),
            monospaced: true
        )
    }

    private var settingsCenterOverview: some View {
        return XTSettingsTaskSection(
            iconName: "rectangle.grid.1x2",
            title: "任务入口",
            subtitle: "按任务进入对应设置域，避免在一个长列表里寻找开关。"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(XTSettingsCenterManifest.sections) { section in
                    XTSettingsFocusCard(section: section)
                }
            }
        }
    }

    private var pairHubSection: some View {
        return XTSettingsTaskSection(
            iconName: settingsSectionIconName("pair_hub"),
            title: "连接 Hub",
            subtitle: "发现、配对、连接按顺序推进；只有需要固定目标或清理旧状态时再展开高级参数。",
            badgeText: settingsSectionBadge("pair_hub")
        ) {
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

                rustHubShadowStatusCard

                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: pairProgressValue, total: 3.0)
                    Text(pairProgressHintText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                stepRow(title: "发现", subtitle: "发现 Hub（局域网优先）", state: settingsSnapshot.hubSetupDiscoverState)
                stepRow(title: "配对", subtitle: "配对 + 凭据下发", state: settingsSnapshot.hubSetupBootstrapState)
                stepRow(title: "连接", subtitle: "建立连接并启用自动重连", state: settingsSnapshot.hubSetupConnectState)

                if !settingsSnapshot.hubPortAutoDetectMessage.isEmpty {
                    Text(settingsSnapshot.hubPortAutoDetectMessage)
                        .font(UIThemeTokens.monoFont())
                        .foregroundStyle(.secondary)
                }
                if !settingsSnapshot.hubRemoteSummary.isEmpty {
                    Text("摘要：\(settingsSnapshot.hubRemoteSummary)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HubDiscoveryCandidatesView(
                    candidates: settingsSnapshot.hubDiscoveredCandidates,
                    selectionDisabled: settingsSnapshot.hubPortAutoDetectRunning || settingsSnapshot.hubRemoteLinking,
                    onSelect: { candidate in
                        appModel.selectDiscoveredHubCandidate(candidate)
                    }
                )

                DisclosureGroup(isExpanded: $connectionToolsExpanded) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("自动探测失败、需要固定目标 Hub，或要清掉旧配对时，再展开这里。")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 10) {
                            Button(settingsSnapshot.hubPortAutoDetectRunning ? "探测中..." : "自动探测") {
                                appModel.maybeAutoFillHubSetupPathAndPorts(force: true)
                            }
                            .buttonStyle(.bordered)
                            .disabled(settingsSnapshot.hubRemoteLinking)

                            Button(settingsSnapshot.hubRemoteLinking ? "重置中..." : "清除配对后重连") {
                                appModel.resetPairingStateAndOneClickSetup()
                            }
                            .buttonStyle(.bordered)
                            .disabled(settingsSnapshot.hubRemoteLinking || settingsSnapshot.hubPortAutoDetectRunning)
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
        }
    }

    private var rustHubShadowStatusCard: some View {
        let presentation = rustHubReadinessPresentation
        let tint = rustHubReadinessTint(presentation.tone)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: presentation.tone == .ready ? "checkmark.seal.fill" : "waveform.path.ecg")
                    .foregroundStyle(tint)
                Text(presentation.title)
                    .font(.caption.weight(.semibold))
                Spacer()
                Text(presentation.badgeText)
                    .font(UIThemeTokens.monoFont())
                    .foregroundStyle(tint)
                Button {
                    rustHubReadinessRefreshID += 1
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .help("刷新 Rust Hub shadow 状态")
            }

            ForEach(Array(presentation.lines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(tint.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(tint.opacity(0.22), lineWidth: 1)
        )
    }

    private var chooseModelSection: some View {
        let hubBaseDir = settingsSnapshot.hubBaseDir ?? HubPaths.baseDir()
        let configuredRoles = AXRole.allCases.filter { configuredGlobalModelID(for: $0) != nil }.count
        let guidance = XTModelGuidancePresentation.build(
            settings: settingsSnapshot.settings,
            snapshot: visibleModelSnapshot,
            doctorReport: XHubDoctorOutputStore.loadHubReport(baseDir: hubBaseDir),
            runtimeMonitor: XHubDoctorOutputStore.loadHubLocalRuntimeMonitorSnapshot(baseDir: hubBaseDir),
            currentProjectName: selectedProjectDisplayName,
            currentProjectContext: settingsSnapshot.selectedProjectContext,
            currentProjectCoderModelId: settingsSnapshot.selectedProjectConfig?.modelOverride(for: .coder),
            currentRemotePaidAccessSnapshot: settingsSnapshot.hubRemotePaidAccessSnapshot
        )

        return XTSettingsTaskSection(
            iconName: settingsSectionIconName("choose_model"),
            title: "AI 模型主入口",
            subtitle: "设置页只保留角色摘要和异常入口；主模型、备用付费模型和本地兜底统一进入模型路由页。",
            badgeText: settingsSectionBadge("choose_model")
        ) {
            VStack(alignment: .leading, spacing: 10) {
                if let context = focusContext(for: "choose_model") {
                    XTFocusContextCard(context: context)
                }
                Text("这里不再维护第二套可编辑模型面板；Supervisor / Coder 的主模型、备用付费模型、本地兜底和路由修复统一收口到控制中心 · 模型。")
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
                    Button("打开控制中心 · 模型") {
                        openSupervisorModelSettings(
                            title: "检查当前全局角色绑定",
                            detail: "XT Settings 这里只保留摘要；主模型、备用付费模型和本地兜底统一进入控制中心 · 模型。"
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

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 260), spacing: 10)],
                    alignment: .leading,
                    spacing: 10
                ) {
                    ForEach(AXRole.allCases) { role in
                        settingsRoleRouteSummaryCard(role)
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
        }
    }

    private func settingsRoleRouteSummaryCard(_ role: AXRole) -> some View {
        let route = settingsSnapshot.settings.modelRoute(for: role)
        let primaryModelId = normalizedSettingsModelID(route.primaryModelId)
        let paidBackupModelId = normalizedSettingsModelID(route.paidBackupModelId)
        let isPriorityRole = role == .supervisor || role == .coder

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(role.displayName)
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 8)
                Text(primaryModelId == nil ? "未配置" : (isPriorityRole ? "优先" : "已配置"))
                    .font(.caption2.monospaced())
                    .foregroundStyle(primaryModelId == nil ? UIThemeTokens.color(for: .inProgress) : .secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.10))
                    .clipShape(Capsule())
            }

            VStack(alignment: .leading, spacing: 5) {
                settingsRouteSummaryLine(
                    title: "主",
                    value: primaryModelId ?? "Hub 自动",
                    tint: primaryModelId == nil ? .secondary : .accentColor
                )
                settingsRouteSummaryLine(
                    title: "备",
                    value: paidBackupModelId ?? "无备用",
                    tint: paidBackupModelId == nil ? .secondary : .orange
                )
                settingsRouteSummaryLine(
                    title: "本地",
                    value: "自动本地兜底",
                    tint: UIThemeTokens.color(for: .ready)
                )
            }

            Button("编辑路由") {
                openSupervisorModelSettings(
                    role: role,
                    title: "检查 \(role.displayName) 模型路由",
                    detail: primaryModelId.map {
                        "当前主模型是 `\($0)`；备用付费模型、清空备用或路由修复都在统一模型入口处理。"
                    } ?? "当前角色没有固定主模型；可以保留 Hub 自动路由，也可以在统一模型入口指定主模型和备用付费模型。"
                )
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isPriorityRole ? Color.accentColor.opacity(0.07) : Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isPriorityRole ? Color.accentColor.opacity(0.22) : Color.secondary.opacity(0.12), lineWidth: 1)
        )
    }

    private func settingsRouteSummaryLine(
        title: String,
        value: String,
        tint: Color
    ) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.caption2.monospaced().weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 26, alignment: .leading)
            Text(value)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private var grantAndRepairSection: some View {
        XTSettingsTaskSection(
            iconName: settingsSectionIconName("grant_permissions"),
            title: "授权与排障",
            subtitle: "Provider 登录、Hub access key 快捷入口和三步排障集中在这里。",
            badgeText: settingsSectionBadge("grant_permissions")
        ) {
            VStack(alignment: .leading, spacing: 10) {
                providerOAuthLoginCard
                hubAccessKeysQuickEntryCard
                TroubleshootPanel(
                    title: "3 步内定位修复入口",
                    issues: UITroubleshootIssue.highFrequencyIssues,
                    paidAccessSnapshot: settingsSnapshot.hubRemotePaidAccessSnapshot,
                    internetHost: settingsSnapshot.hubInternetHost,
                    pairingContext: troubleshootPairingContext,
                    providerKeyRouteContext: modelRouteProviderKeyContext,
                    externalTerminalAccessProjection: externalTerminalAccessDoctorProjection
                )
            }
        }
    }

    private func externalTerminalAccessSection(
        scrollToAccessKey: @escaping (String) -> Void
    ) -> some View {
        let sectionFocusContext = focusContext(for: "external_terminals")
        return XTSettingsTaskSection(
            iconName: settingsSectionIconName("external_terminals"),
            title: "非 XT Terminal 访问",
            subtitle: "集中管理外部 CLI 和自动化代理使用的 access key、导出、轮换与撤销。",
            badgeText: settingsSectionBadge("external_terminals")
        ) {
            VStack(alignment: .leading, spacing: 10) {
                if let context = sectionFocusContext {
                    XTFocusContextCard(context: context)
                    if let projection = externalTerminalAccessDoctorProjection,
                       let focusPresentation = XTExternalTerminalAccessDoctorFocusPresentation.build(
                           projection: projection
                       ) {
                        XTExternalTerminalAccessDoctorFocusCard(presentation: focusPresentation)
                    }
                }

                Text("给 CLI、自动化代理或其他非 XT terminal 签发独立的 Hub access key。这里集中处理导出、轮换、撤销和连接目标核对。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HubAccessKeysSettingsCard(
                    focusContext: sectionFocusContext,
                    doctorProjection: externalTerminalAccessDoctorProjection,
                    onRequestScrollToAccessKey: scrollToAccessKey
                )
            }
        }
    }

    private var providerOAuthLoginCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                Text("Provider OAuth 登录")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("打开 Hub Key 管理") {
                    _ = appModel.openRELFlowHubProviderKeysSettings()
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
            }

            Text("直接在 XT 发起浏览器登录；Hub 会在 callback 后自动交换 token、写入托管 auth 文件并刷新 provider key 池。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                ForEach(ProviderOAuthLoginModel.Provider.allCases) { provider in
                    Button(buttonTitle(for: provider)) {
                        providerOAuthLoginModel.startLogin(
                            provider: provider,
                            openBrowser: { url in
                                appModel.openWorkspaceURL(url)
                                return true
                            },
                            onSuccess: {
                                await modelManager.fetchModels(force: true)
                            }
                        )
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!settingsSnapshot.hubInteractive || providerOAuthLoginModel.isRunning)
                }
            }

            if providerOAuthLoginModel.isRunning || !providerOAuthLoginModel.statusLine.isEmpty {
                HStack(alignment: .center, spacing: 8) {
                    if providerOAuthLoginModel.isRunning {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(providerOAuthLoginModel.statusLine.isEmpty ? "等待登录" : providerOAuthLoginModel.statusLine)
                        .font(UIThemeTokens.monoFont())
                        .foregroundStyle(providerOAuthLoginModel.isRunning ? UIThemeTokens.color(for: .inProgress) : .secondary)
                        .textSelection(.enabled)
                }
            }

            if !providerOAuthLoginModel.detailLine.isEmpty {
                Text(providerOAuthLoginModel.detailLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            if !settingsSnapshot.hubInteractive {
                Text("先连上 Hub，再从 XT 直接发起 provider 登录。")
                    .font(.caption)
                    .foregroundStyle(UIThemeTokens.color(for: .diagnosticRequired))
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.controlBackgroundColor))
        )
    }

    private var hubAccessKeysQuickEntryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                Text("非 XT Terminal Access")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("打开完整管理页") {
                    appModel.requestSettingsFocus(
                        sectionId: "external_terminals",
                        title: "继续管理非 XT Terminal access key",
                        detail: "这里可以查看 key 详情、导出 connect env / 导入脚本，以及执行轮换和撤销。"
                    )
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
            }

            Text("给外部 terminal 的 Hub access key 管理已经独立成一页。授权区只保留快捷入口，避免和 provider OAuth / 排障信息混在一起。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button("滚动到 Access Key 管理页") {
                    appModel.requestSettingsFocus(
                        sectionId: "external_terminals",
                        title: "继续管理非 XT Terminal access key",
                        detail: "这里可以签发、导出、轮换和撤销给外部 terminal 使用的 Hub access key。"
                    )
                }
                .buttonStyle(.borderedProminent)
                .disabled(!settingsSnapshot.hubInteractive)

                Text(settingsSnapshot.hubInteractive
                     ? "Hub 已连通，可直接继续签发和导出。"
                     : "先连上 Hub，再继续签发和导出。")
                    .font(.caption)
                    .foregroundStyle(
                        settingsSnapshot.hubInteractive
                            ? .secondary
                            : UIThemeTokens.color(for: .diagnosticRequired)
                    )
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.controlBackgroundColor))
        )
    }

    private var securityRuntimeSection: some View {
        let guidance = XTSecurityRuntimeGuidancePresentation.build(
            sandboxMode: defaultToolSandboxMode,
            workMode: settingsSnapshot.settings.supervisorWorkMode,
            privacyMode: settingsSnapshot.settings.supervisorPrivacyMode
        )

        return XTSettingsTaskSection(
            iconName: settingsSectionIconName("security_runtime"),
            title: "安全与运行时",
            subtitle: "把本地服务、工具执行路径和安全边界放在同一个可审计入口。",
            badgeText: settingsSectionBadge("security_runtime")
        ) {
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
                        .fill(settingsSnapshot.serverRunning ? UIThemeTokens.color(for: .ready) : Color.secondary)
                        .frame(width: 8, height: 8)
                    if settingsSnapshot.serverRunning {
                        Text("运行中：端口 \(settingsSnapshot.localServerPort)")
                            .font(UIThemeTokens.monoFont())
                    } else if settingsSnapshot.localServerEnabled {
                        Text("已启用，但未运行")
                            .font(UIThemeTokens.monoFont())
                            .foregroundStyle(UIThemeTokens.color(for: .inProgress))
                    } else {
                        Text("已关闭")
                            .font(UIThemeTokens.monoFont())
                            .foregroundStyle(.secondary)
                    }
                }

                if !settingsSnapshot.localServerLastError.isEmpty {
                    Text(settingsSnapshot.localServerLastError)
                        .font(.caption)
                        .foregroundStyle(UIThemeTokens.color(for: .permissionDenied))
                        .textSelection(.enabled)
                }

                Button("重启服务") {
                    appModel.restartLocalServer()
                }
                .buttonStyle(.bordered)
                .disabled(!settingsSnapshot.localServerEnabled)
            }
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
        let runtimeDiagnosticsLines = diagnosticsLines
        let visibleRouteRepairLogLines = displayedRouteRepairLogLines

        return XTSettingsTaskSection(
            iconName: settingsSectionIconName("diagnostics"),
            title: "诊断与核对",
            subtitle: "Doctor、自检、日志和运行时线索集中在这里，默认只展示下一步可操作信息。",
            badgeText: settingsSectionBadge("diagnostics")
        ) {
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
                        if settingsSnapshot.supervisorVoiceSmokeRunning {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Button("打开报告") {
                            appModel.openSupervisorVoiceSmokeReport()
                        }
                        .buttonStyle(.borderless)
                        .disabled(!settingsSnapshot.canOpenSupervisorVoiceSmokeReport)
                        Button(settingsSnapshot.supervisorVoiceSmokeRunning ? "运行中..." : "运行自检") {
                            appModel.runSupervisorVoiceSmokeDiagnostics()
                        }
                        .buttonStyle(.bordered)
                        .disabled(settingsSnapshot.supervisorVoiceSmokeRunning)
                    }
                    if !settingsSnapshot.supervisorVoiceSmokeStatusLine.isEmpty {
                        Text(settingsSnapshot.supervisorVoiceSmokeStatusLine)
                            .font(UIThemeTokens.monoFont())
                            .foregroundStyle(supervisorVoiceSmokeStatusColor)
                            .textSelection(.enabled)
                    }
                    if !settingsSnapshot.supervisorVoiceSmokeDetailLine.isEmpty {
                        Text(settingsSnapshot.supervisorVoiceSmokeDetailLine)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }

                XTUnifiedDoctorSummaryView(report: doctorReport)

                DisclosureGroup(isExpanded: $diagnosticsDetailsExpanded) {
                    VStack(alignment: .leading, spacing: 10) {
                        if !settingsSnapshot.skillsCompatibilitySnapshot.officialChannelSummaryLine.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("官方技能通道")
                                    Spacer()
                                    Button("重查") {
                                        appModel.recheckOfficialSkills(reason: "settings_diagnostics_manual")
                                    }
                                    .buttonStyle(.borderless)
                                    Text(settingsSnapshot.skillsCompatibilitySnapshot.officialChannelSummaryLine)
                                        .font(UIThemeTokens.monoFont())
                                        .foregroundStyle(officialSkillChannelStatusColor)
                                        .textSelection(.enabled)
                                }
                                if !settingsSnapshot.skillsCompatibilitySnapshot.officialChannelDetailLine.isEmpty {
                                    Text(settingsSnapshot.skillsCompatibilitySnapshot.officialChannelDetailLine)
                                        .font(UIThemeTokens.monoFont())
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                }
                                if !settingsSnapshot.skillsCompatibilitySnapshot.officialChannelTopBlockersLine.isEmpty {
                                    if !settingsSnapshot.skillsCompatibilitySnapshot.officialPackageLifecycleTopBlockerSummaries.isEmpty {
                                        XTOfficialSkillsBlockerListView(
                                            items: settingsSnapshot.skillsCompatibilitySnapshot.officialPackageLifecycleTopBlockerSummaries
                                        )
                                    } else {
                                        Text(settingsSnapshot.skillsCompatibilitySnapshot.officialChannelTopBlockersLine)
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.orange)
                                            .textSelection(.enabled)
                                    }
                                }
                            }
                        }

                        if !settingsSnapshot.skillsCompatibilitySnapshot.builtinGovernedSkills.isEmpty {
                            XTBuiltinGovernedSkillsListView(
                                items: settingsSnapshot.skillsCompatibilitySnapshot.builtinGovernedSkills
                            )
                        }

                        if !settingsSnapshot.skillsCompatibilitySnapshot.governanceSurfaceEntries.isEmpty {
                            XTSkillGovernanceSurfaceView(
                                items: settingsSnapshot.skillsCompatibilitySnapshot.governanceSurfaceEntries
                            )
                        }

                        if !runtimeDiagnosticsLines.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("运行时状态线索")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                ForEach(runtimeDiagnosticsLines, id: \.self) { line in
                                    Text("• \(line)")
                                        .font(UIThemeTokens.monoFont())
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                }
                            }
                        }

                        if !visibleRouteRepairLogLines.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                if routeRepairLogDigest.totalEvents > 0 {
                                    Text("路由修复摘要")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                    Text(
                                        AXRouteRepairLogStore.watchHeadline(
                                            for: routeRepairLogDigest,
                                            paidAccessSnapshot: settingsSnapshot.hubRemotePaidAccessSnapshot
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
                                        if settingsSnapshot.selectedProjectId != nil {
                                            Button("查看路由") {
                                                openCurrentProjectRouteDiagnose()
                                            }
                                            .buttonStyle(.borderless)
                                            .controlSize(.small)
                                            .help("切回当前项目聊天，并自动展开 route diagnose。")
                                        }
                                        if reminderStatus.quietingCurrentIssue,
                                           let projectId = settingsSnapshot.selectedProjectId {
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
                                if settingsSnapshot.routeRepairLogTotalLineCount > visibleRouteRepairLogLines.count {
                                    Text("仅显示最近 \(visibleRouteRepairLogLines.count) 条路由修复记录。")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                ForEach(visibleRouteRepairLogLines, id: \.self) { line in
                                    Text("• \(line)")
                                        .font(UIThemeTokens.monoFont())
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                }
                            }
                        }

                        ScrollView {
                            Text(displayedHubRemoteLog)
                                .font(UIThemeTokens.monoFont())
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                        }
                        .frame(minHeight: 120, maxHeight: 220)
                        .background(Color(NSColor.controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .padding(.top, 6)
                } label: {
                    HStack(spacing: 8) {
                        Text(diagnosticsDetailsExpanded ? "收起高级诊断线索" : "高级诊断线索")
                            .font(.caption.weight(.semibold))
                        Spacer()
                        Text("技能 / 路由 / 日志")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var settingsStatus: StatusExplanation {
        XTSettingsSurfacePlanner.status(for: settingsState)
    }

    private var appModel: AppModel {
        guard let appModelReference else {
            preconditionFailure("SettingsView requires xtAppModelReference")
        }
        return appModelReference
    }

    private var settingsSnapshot: XTSettingsSurfaceProjectionSnapshot {
        settingsSurfaceProjectionStore.snapshot
    }

    private var navigationFocusSnapshot: XTNavigationFocusSnapshot {
        navigationFocusStore.snapshot
    }

    private var quickActions: [PrimaryActionRailAction] {
        XTSettingsSurfacePlanner.quickActions(for: settingsState)
    }

    private var configuredGlobalModelRoleCount: Int {
        AXRole.allCases.filter { configuredGlobalModelID(for: $0) != nil }.count
    }

    private var selectedSettingsSection: XTSettingsSectionDescriptor {
        XTSettingsCenterManifest.sections.first(where: { $0.id == selectedSettingsSectionID })
            ?? XTSettingsCenterManifest.sections.first!
    }

    private func selectSettingsSection(_ sectionID: String, proxy: ScrollViewProxy) {
        guard XTSettingsCenterManifest.sections.contains(where: { $0.id == sectionID }) else { return }
        withAnimation(.easeInOut(duration: 0.18)) {
            selectedSettingsSectionID = sectionID
            proxy.scrollTo("settings_detail_top", anchor: .top)
        }
    }

    private func settingsSectionIconName(_ sectionID: String) -> String {
        switch sectionID {
        case "pair_hub":
            return "link"
        case "choose_model":
            return "brain.head.profile"
        case "grant_permissions":
            return "checkmark.shield"
        case "external_terminals":
            return "terminal"
        case "security_runtime":
            return "lock.shield"
        case "diagnostics":
            return "waveform.path.ecg.rectangle"
        default:
            return "gearshape"
        }
    }

    private func settingsSectionShortSummary(_ section: XTSettingsSectionDescriptor) -> String {
        switch section.id {
        case "pair_hub":
            return "发现、配对、重连"
        case "choose_model":
            return "角色模型与路由"
        case "grant_permissions":
            return "Grant、权限、OAuth"
        case "external_terminals":
            return "外部 CLI access key"
        case "security_runtime":
            return "本地服务与工具边界"
        case "diagnostics":
            return "Doctor、自检、日志"
        default:
            return section.summary
        }
    }

    private func settingsSectionBadge(_ sectionID: String) -> String? {
        switch sectionID {
        case "pair_hub":
            if settingsSnapshot.hubConnected { return "local" }
            if settingsSnapshot.hubRemoteConnected { return "remote" }
            if settingsSnapshot.hubRemoteLinking { return "linking" }
            return "off"
        case "choose_model":
            let configured = AXRole.allCases.filter { configuredGlobalModelID(for: $0) != nil }.count
            return "\(configured)/\(AXRole.allCases.count)"
        case "grant_permissions":
            return XTSettingsSurfacePlanner.issue(for: settingsState) == nil ? "ok" : "fix"
        case "external_terminals":
            return settingsSnapshot.hubInteractive ? "live" : "wait"
        case "security_runtime":
            return defaultToolSandboxMode == .host ? "host" : "sandbox"
        case "diagnostics":
            if runtimeSnapshot.replayPass == true { return "pass" }
            if runtimeSnapshot.replayPass == false { return "fail" }
            return settingsSnapshot.hubInteractive ? "live" : "fix"
        default:
            return nil
        }
    }

    private func statusDot(color: Color) -> some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
    }

    private var settingsState: XTSettingsSurfaceState {
        XTSettingsSurfaceState(
            hubConnected: settingsSnapshot.hubConnected,
            remoteConnected: settingsSnapshot.hubRemoteConnected,
            linking: settingsSnapshot.hubRemoteLinking,
            localServerEnabled: settingsSnapshot.localServerEnabled,
            serverRunning: settingsSnapshot.serverRunning,
            failureCode: settingsSnapshot.hubSetupFailureCode,
            runtime: runtimeSnapshot,
            doctor: doctorReport
        )
    }

    private var doctorReport: XTUnifiedDoctorReport {
        settingsSnapshot.unifiedDoctorReport
    }

    private var runtimeSnapshot: UIFailClosedRuntimeSnapshot {
        settingsSnapshot.runtimeSnapshot
    }

    private var routeRepairLogLines: [String] {
        settingsSnapshot.routeRepairLogLines
    }

    private var displayedRouteRepairLogLines: [String] {
        routeRepairLogLines
    }

    private var diagnosticsLines: [String] {
        XTSettingsSurfacePlanner.diagnosticsLines(for: settingsState)
    }

    private var displayedHubRemoteLog: String {
        let log = settingsSnapshot.hubRemoteLog
        guard !log.isEmpty else {
            return "还没有远端连接日志。"
        }
        return log
    }

    private var routeRepairLogDigest: AXRouteRepairLogDigest {
        settingsSnapshot.routeRepairLogDigest
    }

    private var chooseModelIssues: [HubGlobalRoleModelIssue] {
        let snapshot = visibleModelSnapshot
        return Array(
            AXRole.allCases.compactMap { role in
                HubModelSelectionAdvisor.globalAssignmentIssue(
                    for: role,
                    configuredModelId: settingsSnapshot.settings.assignment(for: role).model,
                    snapshot: snapshot
                )
            }
            .prefix(3)
        )
    }

    private var selectedProjectDisplayName: String? {
        settingsSnapshot.selectedProjectName
    }

    private var currentProjectRouteReminderStatus: SupervisorManager.RouteAttentionReminderStatus? {
        guard let watchItem = settingsSnapshot.currentProjectRouteWatchItem else {
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
        guard let projectId = settingsSnapshot.selectedProjectId,
              projectId != AXProjectRegistry.globalHomeId else { return }
        appModel.selectProject(projectId)
        appModel.setPane(.chat, for: projectId)
        appModel.requestProjectRouteDiagnoseFocus(projectId: projectId)
    }

    private func buttonTitle(for provider: ProviderOAuthLoginModel.Provider) -> String {
        if providerOAuthLoginModel.activeProvider == provider {
            return "\(provider.displayName)…"
        }
        return provider.displayName
    }

    private var officialSkillChannelStatusColor: Color {
        switch settingsSnapshot.skillsCompatibilitySnapshot.officialChannelStatus.trimmingCharacters(in: .whitespacesAndNewlines) {
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
        if settingsSnapshot.supervisorVoiceSmokeRunning {
            return UIThemeTokens.color(for: .inProgress)
        }
        switch settingsSnapshot.supervisorVoiceSmokeLastPassed {
        case true:
            return UIThemeTokens.color(for: .ready)
        case false:
            return UIThemeTokens.color(for: .diagnosticRequired)
        case nil:
            return .secondary
        }
    }

    private var historicalProjectBoundaryRepairStatusColor: Color {
        let line = settingsSnapshot.historicalProjectBoundaryRepairStatusLine
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
                    pairingContext: troubleshootPairingContext,
                    externalTerminalAccessProjection: externalTerminalAccessDoctorProjection
                )
            case .connectorScopeBlocked:
                targetSection = "security_runtime"
                title = "查看远端导出与安全边界修复入口"
                detail = XTSettingsSurfacePlanner.reviewSubtitle(
                    issue: issue,
                    failureCode: settingsState.failureCode,
                    runtime: runtimeSnapshot,
                    pairingContext: troubleshootPairingContext,
                    externalTerminalAccessProjection: externalTerminalAccessDoctorProjection
                )
            case .externalTerminalAccessBlocked:
                targetSection = "external_terminals"
                title = UITroubleshootKnowledgeBase.repairEntryTitle(for: issue)
                detail = XTSettingsSurfacePlanner.reviewSubtitle(
                    issue: issue,
                    failureCode: settingsState.failureCode,
                    runtime: runtimeSnapshot,
                    pairingContext: troubleshootPairingContext,
                    externalTerminalAccessProjection: externalTerminalAccessDoctorProjection
                )
            case .modelNotReady:
                if let primaryImportIssue = primaryModelRouteProviderKeyImportIssue,
                   appModel.openRELFlowHubProviderKeysSettings(sourceRef: primaryImportIssue.sourceRef) {
                    return
                }
                openSupervisorModelSettings(
                    role: .coder,
                    title: UITroubleshootKnowledgeBase.repairEntryTitle(for: issue),
                    detail: XTSettingsSurfacePlanner.reviewSubtitle(
                        issue: issue,
                        failureCode: settingsState.failureCode,
                        runtime: runtimeSnapshot,
                        pairingContext: troubleshootPairingContext,
                        externalTerminalAccessProjection: externalTerminalAccessDoctorProjection
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
                    pairingContext: troubleshootPairingContext,
                    externalTerminalAccessProjection: externalTerminalAccessDoctorProjection
                )
            case .pairingRepairRequired, .multipleHubsAmbiguous, .hubPortConflict:
                targetSection = "pair_hub"
                title = UITroubleshootKnowledgeBase.repairEntryTitle(for: issue)
                detail = XTSettingsSurfacePlanner.reviewSubtitle(
                    issue: issue,
                    failureCode: settingsState.failureCode,
                    runtime: runtimeSnapshot,
                    pairingContext: troubleshootPairingContext,
                    externalTerminalAccessProjection: externalTerminalAccessDoctorProjection
                )
            case .hubUnreachable, .none:
                targetSection = "diagnostics"
                title = "查看连接与诊断入口"
                detail = XTSettingsSurfacePlanner.reviewSubtitle(
                    issue: issue,
                    failureCode: settingsState.failureCode,
                    runtime: runtimeSnapshot,
                    pairingContext: troubleshootPairingContext,
                    externalTerminalAccessProjection: externalTerminalAccessDoctorProjection
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
            if settingsSnapshot.hubRemoteLinking || settingsState.hubInteractive {
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
        modelManager.visibleSnapshot(fallback: settingsSnapshot.modelsState)
    }

    private var troubleshootPairingContext: UITroubleshootPairingContext? {
        UITroubleshootPairingContext(
            firstPairCompletionProofSnapshot: settingsSnapshot.unifiedDoctorReport.firstPairCompletionProofSnapshot,
            pairedRouteSetSnapshot: settingsSnapshot.unifiedDoctorReport.pairedRouteSetSnapshot
        )
    }

    private var modelRouteProviderKeyContext: XTProviderKeyRouteContext {
        XTProviderKeyRouteContextPresentation.context(
            section: doctorReport.section(.modelRouteReadiness)
        )
    }

    private var externalTerminalAccessDoctorProjection: XTUnifiedDoctorExternalTerminalAccessProjection? {
        doctorReport.section(.externalTerminalAccessReadiness)?.externalTerminalAccessProjection
    }

    private var primaryModelRouteProviderKeyImportIssue: XTProviderKeyImportIssueContext? {
        modelRouteProviderKeyContext.primaryImportIssue
    }

    private func configuredGlobalModelID(for role: AXRole) -> String? {
        normalizedSettingsModelID(settingsSnapshot.settings.modelRoute(for: role).primaryModelId)
    }

    private func normalizedSettingsModelID(_ raw: String?) -> String? {
        let modelID = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
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

    private func refreshRustHubReadiness() async {
        let language = settingsSnapshot.settings.interfaceLanguage
        await MainActor.run {
            rustHubReadinessPresentation = .loading(language: language)
        }
        let result = await RustHubReadinessClient.fetchReadiness()
        let presentation: RustHubReadinessPresentation
        if let snapshot = result.snapshot {
            presentation = RustHubReadinessPresentation.build(
                snapshot: snapshot,
                language: language
            )
        } else {
            presentation = RustHubReadinessPresentation.unavailable(
                message: result.errorMessage.isEmpty ? result.errorCode : result.errorMessage,
                language: language
            )
        }
        await MainActor.run {
            rustHubReadinessPresentation = presentation
        }
    }

    private func rustHubReadinessTint(
        _ tone: RustHubReadinessPresentation.Tone
    ) -> Color {
        switch tone {
        case .ready:
            return UIThemeTokens.color(for: .ready)
        case .warning:
            return UIThemeTokens.color(for: .diagnosticRequired)
        case .unavailable:
            return UIThemeTokens.color(for: .blockedWaitingUpstream)
        }
    }

    private var pairingPortBinding: Binding<Int> {
        Binding(
            get: { settingsSnapshot.hubPairingPort },
            set: { value in
                appModel.setHubPairingPortFromUser(value)
            }
        )
    }

    private var localServerEnabledBinding: Binding<Bool> {
        Binding(
            get: { settingsSnapshot.localServerEnabled },
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
            get: { settingsSnapshot.hubGrpcPort },
            set: { value in
                appModel.setHubGrpcPortFromUser(value)
            }
        )
    }

    private var inviteStatusPresentation: HubInviteStatusPresentation? {
        HubInviteStatusPlanner.build(
            inviteAlias: settingsSnapshot.hubInviteAlias,
            internetHost: settingsSnapshot.hubInternetHost,
            pairingPort: settingsSnapshot.hubPairingPort,
            grpcPort: settingsSnapshot.hubGrpcPort,
            inviteToken: settingsSnapshot.hubInviteToken,
            hubInstanceID: settingsSnapshot.hubInviteInstanceID,
            connected: settingsSnapshot.hubInteractive,
            linking: settingsSnapshot.hubRemoteLinking,
            failureCode: settingsSnapshot.hubSetupFailureCode
        )
    }

    private var pairHubIntroText: String {
        if UITroubleshootKnowledgeBase.isInviteTokenFailure(settingsSnapshot.hubSetupFailureCode) {
            return "当前是邀请配对修复路径：先重新载入 Hub 邀请，再继续发现、配对和连接。"
        }
        if !(settingsSnapshot.hubInviteToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
            return "上面的首用动作负责连接；当前已载入正式首配参数，通常可直接继续。"
        }
        if hasStableFormalEntry {
            return "上面的首用动作负责连接；当前正式入口已设置，XT 后续切网与自愈都会优先验证这条路径。"
        }
        return "上面的首用动作负责连接；这里主要用来看状态，必要时再展开底层修复工具。"
    }

    private var internetHostBinding: Binding<String> {
        Binding(
            get: { settingsSnapshot.hubInternetHost },
            set: { value in
                appModel.setHubInternetHostFromUser(value)
            }
        )
    }

    private var inviteTokenBinding: Binding<String> {
        Binding(
            get: { settingsSnapshot.hubInviteToken },
            set: { value in
                appModel.hubInviteToken = value
                appModel.saveHubRemotePrefsNow()
            }
        )
    }

    private var axhubctlPathBinding: Binding<String> {
        Binding(
            get: { settingsSnapshot.hubAxhubctlPath },
            set: { value in
                appModel.hubAxhubctlPath = value
                appModel.saveHubRemotePrefsNow()
            }
        )
    }

    private var connectionStateLabel: String {
        if settingsSnapshot.hubConnected {
            return "本地已连"
        }
        if settingsSnapshot.hubRemoteLinking {
            return "连接中"
        }
        if settingsSnapshot.hubRemoteConnected {
            switch settingsSnapshot.hubRemoteRoute {
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
        stepScore(settingsSnapshot.hubSetupDiscoverState)
            + stepScore(settingsSnapshot.hubSetupBootstrapState)
            + stepScore(settingsSnapshot.hubSetupConnectState)
    }

    private var pairProgressHintText: String {
        if UITroubleshootKnowledgeBase.isInviteTokenFailure(settingsSnapshot.hubSetupFailureCode) {
            return "当前先修复邀请令牌，再继续连接。"
        }
        if !settingsSnapshot.hubInviteToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "正式首配参数已载入，通常可直接继续连接。"
        }
        if hasStableFormalEntry {
            return "正式入口已设置；切网后 XT 会优先验证这条路径。"
        }
        return "进入页面会先自动探测一轮；需要手动修复时，再展开连接参数与修复工具。"
    }

    private var formalEntryGuidancePresentation: HubRemoteAccessGuidancePresentation {
        HubRemoteAccessGuidanceBuilder.formalEntry(
            internetHost: settingsSnapshot.hubInternetHost
        )
    }

    private var inviteTokenGuidancePresentation: HubRemoteAccessGuidancePresentation {
        HubRemoteAccessGuidanceBuilder.inviteToken(
            internetHost: settingsSnapshot.hubInternetHost,
            inviteToken: settingsSnapshot.hubInviteToken
        )
    }

    private var hasStableFormalEntry: Bool {
        XTHubRemoteAccessHostClassification
            .classify(settingsSnapshot.hubInternetHost)
            .isFormalRemoteEntry
    }

    private var connectionStateColor: Color {
        if settingsSnapshot.hubConnected { return UIThemeTokens.color(for: .ready) }
        if settingsSnapshot.hubRemoteLinking { return UIThemeTokens.color(for: .inProgress) }
        if settingsSnapshot.hubRemoteConnected { return UIThemeTokens.color(for: .ready) }
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
        guard let request = navigationFocusSnapshot.settingsFocusRequest else { return }
        activeFocusRequest = request
        if XTSettingsCenterManifest.sections.contains(where: { $0.id == request.sectionId }) {
            selectedSettingsSectionID = request.sectionId
        }
        if request.sectionId == "pair_hub" {
            connectionToolsExpanded = true
        }
        if let refreshAction = request.context?.refreshAction {
            appModel.performSectionRefreshAction(
                refreshAction,
                reason: request.context?.refreshReason ?? "settings_focus_request"
            )
        }
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.2)) {
                proxy.scrollTo(request.sectionId, anchor: .top)
            }
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
        let statusLine = settingsSnapshot.officialSkillsRecheckStatusLine.trimmingCharacters(in: .whitespacesAndNewlines)
        if !statusLine.isEmpty {
            Text(statusLine)
                .font(UIThemeTokens.monoFont())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private var historicalProjectBoundaryRepairStatus: some View {
        let statusLine = settingsSnapshot.historicalProjectBoundaryRepairStatusLine
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
