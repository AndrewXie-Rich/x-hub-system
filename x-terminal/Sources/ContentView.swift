import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.openWindow) private var openWindow

    @State private var showMemoryInspector: Bool = false
    @State private var showProjectSettings: Bool = false
    @State private var showHistoryPanel: Bool = false
    @State private var showCreateProject: Bool = false
    @State private var showSkillLibrary: Bool = false
    @State private var showBuiltinGovernedSkillsPopover: Bool = false
    @State private var projectSettingsProjectId: String? = nil
    @State private var projectSettingsDestination: XTProjectGovernanceDestination = .overview

    var body: some View {
        VStack(spacing: 0) {
            // Supervisor 状态栏在断连时也保留显示，避免把“Hub 不可交互”误读成“Supervisor 消失了”。
            SupervisorStatusBar()
                .environmentObject(appModel)
            Divider()

            // 主内容区域
            HSplitView {
                ProjectSidebarView()

                HSplitView {
                    mainPane

                    if showHistoryPanel {
                        HistoryPanelView()
                            .frame(minWidth: 300, maxWidth: 400)
                    }

                    if showMemoryInspector, let ctx = appModel.projectContext {
                        MemoryInspectorView(ctx: ctx, memory: appModel.memory)
                    }
                }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Button("Open Project…") {
                    appModel.openProjectPicker()
                }

                Button {
                    appModel.presentPreferredResumeBrief()
                } label: {
                    Label("接上次进度", systemImage: "arrow.clockwise.circle")
                }
                .help(toolbarResumeHelp)
                .disabled(toolbarResumeTarget == nil)

                Divider()

                // 多项目视图切换
                if appModel.hubInteractive {
                    Button {
                        appModel.toggleMultiProjectView()
                    } label: {
                        Image(systemName: appModel.isMultiProjectViewEnabled ? "square.grid.2x2" : "square")
                    }
                    .help(appModel.isMultiProjectViewEnabled ? "Switch to Single Project View" : "Switch to Multi-Project View")

                    // 创建新项目按钮
                    if appModel.isMultiProjectViewEnabled {
                        Button {
                            showCreateProject = true
                        } label: {
                            Image(systemName: "plus.circle")
                        }
                        .help("Create New Project")
                    }
                }

                Divider()

                Button(hubConnectButtonTitle) {
                    if appModel.hubConnected {
                        Task { @MainActor in
                            await appModel.connectToHub(auto: false)
                        }
                    } else {
                        openWindow(id: "hub_setup")
                    }
                }
                .keyboardShortcut("x", modifiers: [.command, .option])

                Button {
                    showMemoryInspector.toggle()
                } label: {
                    Image(systemName: "sidebar.right")
                }
                .help("Toggle Memory Inspector")
                .disabled(appModel.projectContext == nil)

                Button {
                    showHistoryPanel.toggle()
                } label: {
                    Image(systemName: "clock")
                }
                .help("Toggle History Panel")
                .disabled(appModel.projectContext == nil)

                Button("Edit Skill…") {
                    showSkillLibrary = true
                }
                .help("Browse local skills, inspect governed skills, and open a local SKILL.md for editing")

                Button(toolbarImportSkillsTitle) {
                    appModel.importSkills()
                }
                .help(toolbarImportSkillsHelp)

                Button(toolbarReviewImportTitle) {
                    appModel.reviewLastImportedSkill()
                }
                .help(toolbarReviewImportHelp)
                .disabled(!appModel.canReviewLastImportedAgentSkill)

                Button(toolbarEnableImportTitle) {
                    appModel.enableLastImportedSkill()
                }
                .help(toolbarEnableImportHelp)
                .disabled(!appModel.canEnableLastImportedAgentSkill)

                Menu("Baseline") {
                    Button(toolbarCurrentProjectBaselineTitle) {
                        appModel.installDefaultAgentBaselineForCurrentProject()
                    }
                    .disabled(!appModel.canInstallDefaultAgentBaselineForCurrentProject)

                    Button(toolbarGlobalBaselineTitle) {
                        appModel.installDefaultAgentBaselineGlobally()
                    }
                    .disabled(!appModel.canInstallDefaultAgentBaselineGlobally)
                }
                .help(toolbarBaselineHelp)

                Button {
                    appModel.openCurrentSkillsIndex()
                } label: {
                    Image(systemName: "list.bullet.rectangle")
                }
                .help("Open current project/global skills index")

                Button {
                    projectSettingsProjectId = appModel.selectedProjectId
                    showProjectSettings = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .help("Project Settings")
                .disabled(appModel.projectContext == nil || appModel.selectedProjectId == AXProjectRegistry.globalHomeId)

                if let pid = appModel.selectedProjectId,
                   pid != AXProjectRegistry.globalHomeId,
                   appModel.projectContext != nil {
                    Picker(
                        "",
                        selection: Binding(
                            get: { appModel.pane(for: pid) },
                            set: { appModel.setPane($0, for: pid) }
                        )
                    ) {
                        Text("Chat").tag(AXProjectPane.chat)
                        Text("Terminal").tag(AXProjectPane.terminal)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                    .help("Project Pane")
                }

                BreathingDotView(label: "C", isActive: appModel.memoryCoarseRunning)
                    .help("Memory coarse filter")
                BreathingDotView(label: "R", isActive: appModel.memoryRefineRunning)
                    .help("Memory refiner")

                Text(appModel.bridgeEnabled ? "net" : "net?")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(appModel.bridgeEnabled ? Color.secondary : Color.red)
                    .help("Hub Networking Bridge")

                if appModel.hubConnected {
                    Text("hub")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                } else if appModel.hubRemoteLinking {
                    Text("hub...")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.orange)
                } else if appModel.hubRemoteConnected {
                    Text("hub~\(hubRouteTag)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.orange)
                } else {
                    Text("hub?")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.red)
                }

                if appModel.projectContext != nil {
                    Text("tok today \(appModel.usageSummary.todayTokensEst)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                if appModel.skillsCompatibilitySnapshot.statusKind != .unavailable || appModel.skillsCompatibilitySnapshot.installedSkillCount > 0 {
                    Text(appModel.skillsCompatibilitySnapshot.statusLine)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(skillsStatusColor)
                        .help(appModel.skillsCompatibilitySnapshot.compatibilityExplain)
                }

                if !appModel.skillsCompatibilitySnapshot.builtinGovernedSkills.isEmpty {
                    Button {
                        showBuiltinGovernedSkillsPopover.toggle()
                    } label: {
                        XTBuiltinGovernedSkillsListView(
                            items: appModel.skillsCompatibilitySnapshot.builtinGovernedSkills,
                            style: .compact
                        )
                    }
                    .buttonStyle(.plain)
                    .help(toolbarBuiltinGovernedSkillsHelp)
                    .popover(isPresented: $showBuiltinGovernedSkillsPopover, arrowEdge: .bottom) {
                        ScrollView {
                            XTBuiltinGovernedSkillsListView(
                                items: appModel.skillsCompatibilitySnapshot.builtinGovernedSkills
                            )
                            .padding(12)
                        }
                        .frame(minWidth: 380, idealWidth: 420, maxWidth: 460, minHeight: 220, maxHeight: 420)
                    }
                }

                if !appModel.lastImportedAgentSkillToolbarStatusLine.isEmpty {
                    Text(appModel.lastImportedAgentSkillToolbarStatusLine)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(appModel.agentSkillImportBusy ? .orange : .secondary)
                        .help(appModel.lastImportedAgentSkillStatusLine)
                }

                if !appModel.baselineInstallToolbarStatusLine.isEmpty {
                    Text(appModel.baselineInstallToolbarStatusLine)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(appModel.baselineInstallBusy ? .orange : .secondary)
                        .help(appModel.baselineInstallStatusLine)
                }
            }
        }
        .sheet(isPresented: $showSkillLibrary) {
            XTSkillLibrarySheet()
                .environmentObject(appModel)
        }
    }

    private var hubConnectButtonTitle: String {
        if appModel.hubConnected {
            return "Hub: Connected"
        }
        if appModel.hubRemoteLinking {
            return "Hub: Linking..."
        }
        if appModel.hubRemoteConnected {
            return "Hub: Relay (\(hubRouteTag))"
        }
        return "Hub: One-Click Setup"
    }


    private var skillsStatusColor: Color {
        switch appModel.skillsCompatibilitySnapshot.statusKind {
        case .supported:
            return .secondary
        case .partial:
            return .orange
        case .blocked, .unavailable:
            return .red
        }
    }

    private var hubRouteTag: String {
        switch appModel.hubRemoteRoute {
        case .lan:
            return "lan"
        case .internet:
            return "internet"
        case .internetTunnel:
            return "tunnel"
        case .none:
            return "?"
        }
    }

    private var toolbarResumeTarget: AXResumeReminderProjectPresentation? {
        appModel.preferredResumeProject()
    }

    private var toolbarResumeHelp: String {
        guard let target = toolbarResumeTarget else {
            return "当前没有可恢复的交接摘要"
        }
        return "接上次进度：\(target.projectDisplayName) · \(target.summary.detailText)。只会在你点击后展开，不会自动塞进当前 prompt。"
    }

    private var toolbarBuiltinGovernedSkillsHelp: String {
        let items = appModel.skillsCompatibilitySnapshot.builtinGovernedSkills
        guard !items.isEmpty else {
            return "No XT native governed skills are currently registered."
        }
        let detailLines = items.map { item in
            let summary = item.summary.trimmingCharacters(in: .whitespacesAndNewlines)
            let risk = normalizedToolbarToken(item.riskLevel, fallback: "unknown")
            if summary.isEmpty {
                return "\(item.displayName) [\(risk)]"
            }
            return "\(item.displayName) [\(risk)]: \(summary)"
        }
        return ([
            "XT native governed skills are local to XT and remain available even when Hub-managed packages are missing."
        ] + detailLines).joined(separator: "\n")
    }

    private var toolbarHasMissingBaselinePackages: Bool {
        !appModel.skillsCompatibilitySnapshot.missingBaselineSkillIDs.isEmpty
    }

    private var toolbarHasPartialCompatibility: Bool {
        appModel.skillsCompatibilitySnapshot.partialCompatibilityCount > 0
    }

    private var toolbarHasConflictWarnings: Bool {
        !appModel.skillsCompatibilitySnapshot.conflictWarnings.isEmpty
    }

    private var toolbarImportSkillsTitle: String {
        "Import Skills…"
    }

    private var toolbarImportSkillsHelp: String {
        if toolbarHasMissingBaselinePackages {
            return "Import skill folders, SKILL.md, or supported archives (.zip/.skill/.tgz/.tar.gz/.tar) into the local skills library so currently discoverable profiles can become installable."
        }
        return "Import skill folders, SKILL.md, or supported archives (.zip/.skill/.tgz/.tar.gz/.tar) into the local skills library."
    }

    private var toolbarReviewImportTitle: String {
        appModel.canReviewLastImportedAgentSkill ? "Review Installability" : "Review Import"
    }

    private var toolbarReviewImportHelp: String {
        "Review the last staged agent skill import from Hub and verify whether it is installable / requestable yet."
    }

    private var toolbarEnableImportTitle: String {
        toolbarHasPartialCompatibility ? "Enable Installable Skill" : "Enable Import"
    }

    private var toolbarEnableImportHelp: String {
        "Package, upload, and enable the last imported agent skill through Hub governance so installable skills can enter the requestable set."
    }

    private var toolbarCurrentProjectBaselineTitle: String {
        if toolbarHasMissingBaselinePackages {
            return "Install Missing Packages in Current Project"
        }
        if toolbarHasPartialCompatibility {
            return "Pin Baseline into Current Project"
        }
        return "Install in Current Project"
    }

    private var toolbarGlobalBaselineTitle: String {
        appModel.skillsCompatibilitySnapshot.missingBaselineSkillIDs.isEmpty
            ? "Install Globally"
            : "Install Missing Packages Globally"
    }

    private var toolbarBaselineHelp: String {
        var parts = ["Install the default Agent baseline through Hub-governed skill pinning."]
        if toolbarHasMissingBaselinePackages {
            parts.append("Some recommended baseline packages are still missing from the current environment.")
        }
        if toolbarHasPartialCompatibility {
            parts.append("Some skills are only partially compatible and may still need project pinning or governance approval.")
        }
        if toolbarHasConflictWarnings {
            parts.append("Compatibility doctor has conflict warnings that can block runnable readiness.")
        }
        return parts.joined(separator: " ")
    }

    private var mainPane: some View {
        VStack(spacing: 0) {
            // 多项目视图
            if appModel.isMultiProjectViewEnabled && appModel.hubInteractive {
                ProjectsGridView(projectsManager: appModel.legacyMultiProjectManager)
                    .environmentObject(appModel)
            }
            // 单项目视图
            else if appModel.selectedProjectId == AXProjectRegistry.globalHomeId {
                GlobalHomeView()
            } else if let ctx = appModel.projectContext {
                if appModel.pane(for: appModel.selectedProjectId ?? "") == .terminal {
                    ProjectTerminalView(ctx: ctx, session: appModel.terminalSession(for: ctx))
                } else {
                    // 使用新的现代化聊天视图
                    ModernChatView(
                        ctx: ctx,
                        memory: appModel.memory,
                        config: appModel.projectConfig,
                        hubConnected: appModel.hubInteractive,
                        session: appModel.session(for: ctx)
                    )
                    .environmentObject(appModel)
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text("X-Terminal")
                        .font(.title2)
                    Text("Open a project to start.")
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .padding(16)
            }
        }
        .frame(minWidth: 720, minHeight: 520)
        .sheet(isPresented: $showProjectSettings) {
            if let ctx = projectSettingsSheetContext {
                ProjectSettingsView(
                    ctx: ctx,
                    initialGovernanceDestination: projectSettingsDestination
                )
                .environmentObject(appModel)
            }
        }
        .onChange(of: appModel.projectSettingsFocusRequest?.nonce) { _ in
            processProjectSettingsFocusRequest()
        }
        .sheet(isPresented: $showCreateProject) {
            CreateProjectSheet()
                .environmentObject(appModel)
        }
        .onOpenURL { url in
            handleDeepLink(url)
        }
        .onReceive(NotificationCenter.default.publisher(for: .xterminalOpenHubSetupWizard)) { _ in
            openWindow(id: "hub_setup")
        }
        .onReceive(NotificationCenter.default.publisher(for: .xterminalOpenSupervisorWindow)) { notification in
            handleSupervisorWindowOpen(notification)
        }
        .onReceive(NotificationCenter.default.publisher(for: .xterminalOpenSupervisorToolWindow)) { notification in
            handleSupervisorToolWindowOpen(notification)
        }
        .onChange(of: showProjectSettings) { presented in
            if !presented {
                projectSettingsProjectId = nil
                projectSettingsDestination = .overview
            }
        }
    }

    private var projectSettingsSheetContext: AXProjectContext? {
        if let projectSettingsProjectId,
           let ctx = appModel.projectContext(for: projectSettingsProjectId) {
            return ctx
        }
        return appModel.projectContext
    }

    private func processProjectSettingsFocusRequest() {
        guard let request = appModel.projectSettingsFocusRequest else { return }
        projectSettingsProjectId = request.projectId
        projectSettingsDestination = request.destination
        showProjectSettings = true
    }

    private func handleSupervisorWindowOpen(_ notification: Notification) {
        let request = SupervisorConversationWindowOpenRequest(notification: notification)
        let decision = XTSupervisorWindowPresentationPolicy.decision(
            for: request,
            isWindowVisible: XTSupervisorWindowVisibilityRegistry.shared.isWindowVisible
        )
        guard decision.shouldOpenWindow else { return }
        openWindow(id: "supervisor")
    }

    private func handleSupervisorToolWindowOpen(_ notification: Notification) {
        guard let rawValue = notification.userInfo?["sheet_id"] as? String,
              let sheet = SupervisorManager.SupervisorWindowSheet(rawValue: rawValue) else {
            return
        }
        openWindow(id: sheet.windowID)
    }

    private func handleDeepLink(_ url: URL) {
        guard let route = XTDeepLinkParser.parse(url) else { return }

        let openSupervisor: (XTSupervisorWindowOpenIntent) -> Void = { intent in
            SupervisorManager.shared.requestSupervisorWindow(
                reason: intent.reason,
                focusConversation: intent.focusConversation,
                startConversation: intent.startConversation
            )
        }
        let openSupervisorSettings: () -> Void = {
            SupervisorManager.shared.requestSupervisorWindow(
                sheet: .supervisorSettings,
                reason: "deep_link_supervisor_settings",
                focusConversation: false
            )
        }
        let openSupervisorModelSettings: (_ route: XTSupervisorModelSettingsRoute) -> Void = { route in
            appModel.requestModelSettingsFocus(
                title: route.title,
                detail: route.detail
            )
            SupervisorManager.shared.requestSupervisorWindow(
                sheet: .modelSettings,
                reason: "deep_link_supervisor_model_settings",
                focusConversation: false
            )
        }
        let openSettingsWindow: () -> Void = {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }

        switch route {
        case let .supervisor(supervisorRoute):
            applyDeepLinkActionPlan(
                XTDeepLinkActionPlanner.plan(for: supervisorRoute),
                openSupervisor: openSupervisor
            )
        case let .hubSetup(hubSetupRoute):
            if let pairingPrefill = hubSetupRoute.pairingPrefill {
                appModel.applyHubPairingInvitePrefill(pairingPrefill)
            }
            let hubSetupSectionId = hubSetupRoute.sectionId
                ?? (hubSetupRoute.pairingPrefill == nil ? nil : "pair_hub")
            if let sectionId = hubSetupRoute.sectionId {
                appModel.requestHubSetupFocus(
                    sectionId: sectionId,
                    title: resolvedHubSetupTitle(hubSetupRoute),
                    detail: resolvedHubSetupDetail(hubSetupRoute),
                    refreshAction: hubSetupRoute.refreshAction,
                    refreshReason: hubSetupRoute.refreshReason
                )
            } else if let sectionId = hubSetupSectionId {
                appModel.requestHubSetupFocus(
                    sectionId: sectionId,
                    title: resolvedHubSetupTitle(hubSetupRoute),
                    detail: resolvedHubSetupDetail(hubSetupRoute),
                    refreshAction: hubSetupRoute.refreshAction,
                    refreshReason: hubSetupRoute.refreshReason
                )
            }
            openWindow(id: "hub_setup")
        case let .settings(settingsRoute):
            if let sectionId = settingsRoute.sectionId {
                appModel.requestSettingsFocus(
                    sectionId: sectionId,
                    title: settingsRoute.title,
                    detail: settingsRoute.detail,
                    refreshAction: settingsRoute.refreshAction,
                    refreshReason: settingsRoute.refreshReason
                )
            }
            openSettingsWindow()
        case .supervisorSettings:
            openSupervisorSettings()
        case let .supervisorModelSettings(route):
            openSupervisorModelSettings(route)
        case let .resume(projectId):
            if let projectId {
                appModel.presentResumeBrief(projectId: projectId)
            } else {
                appModel.presentPreferredResumeBrief()
            }
        case let .project(projectRoute):
            let actionPlan = XTDeepLinkActionPlanner.plan(for: projectRoute)
            let projectId = projectRoute.projectId ?? ""

            if projectRoute.resumeRequested {
                if !projectId.isEmpty {
                    appModel.presentResumeBrief(projectId: projectId)
                } else {
                    appModel.presentPreferredResumeBrief()
                }
            }

            applyDeepLinkActionPlan(actionPlan, openSupervisor: openSupervisor)

            if projectRoute.openTarget == .supervisorSettings {
                openSupervisorSettings()
            }

            if !projectId.isEmpty, let governanceDestination = projectRoute.governanceDestination {
                appModel.requestProjectSettingsFocus(
                    projectId: projectId,
                    destination: governanceDestination
                )
            }
        }
    }

    private func applyDeepLinkActionPlan(
        _ plan: XTDeepLinkActionPlan,
        openSupervisor: (XTSupervisorWindowOpenIntent) -> Void
    ) {
        XTDeepLinkActionExecutor.execute(
            plan,
            appModel: appModel,
            openSupervisor: openSupervisor
        )
    }

    private func normalizedToolbarToken(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    private func resolvedHubSetupTitle(_ route: XTHubSetupRoute) -> String? {
        if let title = route.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            return title
        }
        guard route.pairingPrefill != nil else { return nil }
        return "已载入 Hub 邀请"
    }

    private func resolvedHubSetupDetail(_ route: XTHubSetupRoute) -> String? {
        if let detail = route.detail?.trimmingCharacters(in: .whitespacesAndNewlines), !detail.isEmpty {
            return detail
        }
        guard let prefill = route.pairingPrefill else { return nil }
        let alias = prefill.hubAlias?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let host = prefill.internetHost?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hasInviteToken = prefill.inviteToken?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        if !alias.isEmpty && !host.isEmpty {
            return "Hub alias: \(alias) · host: \(host)" + (hasInviteToken ? " · invite token ready" : "")
        }
        if !alias.isEmpty {
            return "Hub alias: \(alias)"
        }
        if !host.isEmpty {
            return "host: \(host)" + (hasInviteToken ? " · invite token ready" : "")
        }
        return "Pair Hub 参数已从邀请链接自动填入。"
    }
}
