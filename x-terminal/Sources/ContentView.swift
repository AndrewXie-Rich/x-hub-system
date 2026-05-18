import SwiftUI
import AppKit

struct ContentView: View {
    @Environment(\.xtAppModelReference) private var appModelReference
    @EnvironmentObject private var navigationFocusStore: XTNavigationFocusStore
    @Environment(\.openWindow) private var openWindow

    @State private var selectedPrimarySurface: XTPrimarySurface = .work
    @State private var preferredControlSection: XTControlSurfaceView.Section = .overview
    @State private var showMemoryInspector: Bool = false
    @State private var showProjectSettings: Bool = false
    @State private var showHistoryPanel: Bool = false
    @State private var showCreateProject: Bool = false
    @State private var projectSettingsProjectId: String? = nil
    @State private var projectSettingsDestination: XTProjectGovernanceDestination = .overview
    @State private var workSurfaceMounted: Bool = true
    @State private var workSurfaceMountTask: Task<Void, Never>? = nil
    @State private var supervisorSurfaceMounted: Bool = false
    @State private var supervisorManagerPrewarmTask: Task<Void, Never>? = nil
    @State private var supervisorSurfaceMountTask: Task<Void, Never>? = nil
    @State private var supervisorSurfacePrewarmTask: Task<Void, Never>? = nil
    @State private var reviewSurfaceMounted: Bool = false
    @State private var reviewSurfaceMountTask: Task<Void, Never>? = nil
    @State private var controlSurfaceMounted: Bool = false
    @State private var controlSurfaceMountTask: Task<Void, Never>? = nil
    @State private var retainedWorkSurfaceAfterPrimarySwitch: Bool = false
    @State private var workSurfaceReleaseTask: Task<Void, Never>? = nil
    @State private var retainedReviewSurfaceAfterPrimarySwitch: Bool = false
    @State private var reviewSurfaceReleaseTask: Task<Void, Never>? = nil
    @State private var retainedControlSurfaceAfterPrimarySwitch: Bool = false
    @State private var controlSurfaceReleaseTask: Task<Void, Never>? = nil

    private static let supervisorManagerPrewarmDelayNanoseconds: UInt64 = 220_000_000
    private static let supervisorSurfaceMountDelayNanoseconds: UInt64 = 48_000_000
    private static let supervisorSurfacePrewarmDelayNanoseconds: UInt64 = 420_000_000
    private static let secondarySurfaceMountDelayNanoseconds: UInt64 = 48_000_000
    private static let inactiveSurfaceReleaseDelayNanoseconds: UInt64 = 120_000_000

    var body: some View {
        HSplitView {
            XTPrimarySidebarView(selectedPrimarySurface: $selectedPrimarySurface)
                .environmentObject(appModel)

            surfacePane
        }
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Button("Open Project…") {
                    selectedPrimarySurface = .work
                    appModel.openProjectPicker()
                }

                Button {
                    selectedPrimarySurface = .work
                    appModel.presentPreferredResumeBrief()
                } label: {
                    Label("接上次进度", systemImage: "arrow.clockwise.circle")
                }
                .help(toolbarResumeHelp)
                .disabled(toolbarResumeTarget == nil)

                if selectedPrimarySurface == .work, appModel.hubInteractive {
                    Divider()

                    Button {
                        appModel.toggleMultiProjectView()
                    } label: {
                        Image(systemName: appModel.isMultiProjectViewEnabled ? "square.grid.2x2" : "square")
                    }
                    .help(appModel.isMultiProjectViewEnabled ? "Switch to Single Project View" : "Switch to Multi-Project View")

                    if appModel.isMultiProjectViewEnabled {
                        Button {
                            showCreateProject = true
                        } label: {
                            Image(systemName: "plus.circle")
                        }
                        .help("Create New Project")
                    }
                }

                if shouldShowWorkToolbarTools {
                    Divider()

                    Button {
                        showHistoryPanel.toggle()
                    } label: {
                        Image(systemName: "clock")
                    }
                    .help("Toggle History Panel")

                    Button {
                        showMemoryInspector.toggle()
                    } label: {
                        Image(systemName: "sidebar.right")
                    }
                    .help("Toggle Memory Inspector")

                    Button {
                        projectSettingsProjectId = appModel.selectedProjectId
                        showProjectSettings = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                    .help("Project Settings")
                    .disabled(!canOpenProjectSettings)

                    if let pid = currentWorkProjectId {
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
                }

                Divider()

                Button {
                    if appModel.hubInteractive {
                        openControl(section: .hub)
                    } else {
                        openControl(section: .hub, focusSectionId: "pair_hub")
                    }
                } label: {
                    Label(controlButtonTitle, systemImage: controlButtonIconName)
                }
                .keyboardShortcut("x", modifiers: [.command, .option])
                .help(controlButtonHelp)
            }
        }
        .sheet(isPresented: $showProjectSettings) {
            if let ctx = projectSettingsSheetContext {
                ProjectSettingsView(
                    ctx: ctx,
                    initialGovernanceDestination: projectSettingsDestination
                )
            }
        }
        .sheet(isPresented: $showCreateProject) {
            CreateProjectSheet()
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
        .onAppear {
            scheduleSupervisorManagerPrewarmIfNeeded()
            scheduleSupervisorSurfacePrewarmIfNeeded()
        }
        .onDisappear {
            workSurfaceMountTask?.cancel()
            workSurfaceMountTask = nil
            supervisorManagerPrewarmTask?.cancel()
            supervisorManagerPrewarmTask = nil
            supervisorSurfaceMountTask?.cancel()
            supervisorSurfaceMountTask = nil
            supervisorSurfacePrewarmTask?.cancel()
            supervisorSurfacePrewarmTask = nil
            reviewSurfaceMountTask?.cancel()
            reviewSurfaceMountTask = nil
            controlSurfaceMountTask?.cancel()
            controlSurfaceMountTask = nil
            workSurfaceReleaseTask?.cancel()
            workSurfaceReleaseTask = nil
            reviewSurfaceReleaseTask?.cancel()
            reviewSurfaceReleaseTask = nil
            controlSurfaceReleaseTask?.cancel()
            controlSurfaceReleaseTask = nil
        }
        .onChange(of: showProjectSettings) { presented in
            if !presented {
                projectSettingsProjectId = nil
                projectSettingsDestination = .overview
            }
        }
        .onChange(of: appModel.projectSettingsFocusRequest?.nonce) { _ in
            selectedPrimarySurface = .work
            processProjectSettingsFocusRequest()
        }
        .onChange(of: appModel.settingsFocusRequest?.nonce) { nonce in
            guard nonce != nil else { return }
            openControl(section: .hub)
        }
        .onChange(of: appModel.modelSettingsFocusRequest?.nonce) { nonce in
            guard nonce != nil else { return }
            openControl(section: .models)
        }
        .onChange(of: appModel.supervisorSettingsFocusRequest?.nonce) { nonce in
            guard nonce != nil else { return }
            openControl(section: .supervisor)
        }
        .onChange(of: appModel.supervisorFocusRequest?.nonce) { nonce in
            guard nonce != nil else { return }
            selectedPrimarySurface = .supervisor
        }
    }

    private var surfacePane: some View {
        Group {
            switch selectedPrimarySurface {
            case .work:
                workSurface
            case .supervisor:
                SupervisorView()
                    .environmentObject(appModel)
            case .review:
                XTReviewSurfaceView(
                    onOpenSupervisor: { selectedPrimarySurface = .supervisor },
                    onOpenControl: { openControl(section: .hub) }
                )
                .environmentObject(appModel)
            case .control:
                XTControlSurfaceView(preferredSection: preferredControlSection)
                    .environmentObject(appModel)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var workSurface: some View {
        HSplitView {
            workMainPane

            if shouldShowHistoryPanel {
                HistoryPanelView()
                    .frame(minWidth: 300, maxWidth: 400)
            }

            if shouldShowMemoryInspector, let ctx = appModel.projectContext {
                MemoryInspectorView(ctx: ctx, memory: appModel.memory)
            }
        }
    }

    private var workMainPane: some View {
        VStack(spacing: 0) {
            if appModel.isMultiProjectViewEnabled && appModel.hubInteractive {
                ProjectsGridView(projectsManager: appModel.legacyMultiProjectManager)
                    .environmentObject(appModel)
            } else if appModel.selectedProjectId == AXProjectRegistry.globalHomeId {
                GlobalHomeView()
            } else if let ctx = appModel.projectContext {
                if appModel.pane(for: appModel.selectedProjectId ?? "") == .terminal {
                    ProjectTerminalView(ctx: ctx, session: appModel.terminalSession(for: ctx))
                } else {
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
                    Text("Work")
                        .font(.title2)
                    Text("从左侧项目列表进入工作台；系统级设置和审查入口已经移到其它一级面。")
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .padding(16)
            }
        }
        .frame(minWidth: 720, minHeight: 520)
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

    private var shouldShowWorkToolbarTools: Bool {
        selectedPrimarySurface == .work &&
            !appModel.isMultiProjectViewEnabled &&
            appModel.projectContext != nil
    }

    private var shouldShowHistoryPanel: Bool {
        selectedPrimarySurface == .work &&
            showHistoryPanel &&
            appModel.projectContext != nil &&
            !appModel.isMultiProjectViewEnabled
    }

    private var shouldShowMemoryInspector: Bool {
        selectedPrimarySurface == .work &&
            showMemoryInspector &&
            appModel.projectContext != nil &&
            !appModel.isMultiProjectViewEnabled
    }

    private var canOpenProjectSettings: Bool {
        appModel.projectContext != nil &&
            appModel.selectedProjectId != AXProjectRegistry.globalHomeId
    }

    private var currentWorkProjectId: String? {
        guard let pid = appModel.selectedProjectId,
              pid != AXProjectRegistry.globalHomeId,
              appModel.projectContext != nil,
              selectedPrimarySurface == .work,
              !appModel.isMultiProjectViewEnabled else {
            return nil
        }
        return pid
    }

    private var controlButtonIconName: String {
        if appModel.hubInteractive {
            return "slider.horizontal.3"
        }
        return "link.badge.plus"
    }

    private var controlButtonTitle: String {
        if appModel.hubConnected {
            return "Control · Hub Local"
        }
        if appModel.hubRemoteConnected {
            return "Control · Hub Remote"
        }
        if appModel.hubRemoteLinking {
            return "Control · Linking"
        }
        return "Control · Connect Hub"
    }

    private var controlButtonHelp: String {
        if appModel.hubInteractive {
            return "打开 Control Center，查看 Hub、模型、技能和诊断。"
        }
        return "打开 Control Center；Hub 还没接入时会优先处理连接主链。"
    }

    private var projectSettingsSheetContext: AXProjectContext? {
        if let projectSettingsProjectId,
           let ctx = appModel.projectContext(for: projectSettingsProjectId) {
            return ctx
        }
        return appModel.workSurfaceStore.snapshot.projectContext
    }

    private func openControl(
        section: XTControlSurfaceView.Section,
        focusSectionId: String? = nil
    ) {
        preferredControlSection = section
        selectedControlSection = section
        selectPrimarySurface(.control)

        if let focusSectionId {
            appModel.requestSettingsFocus(sectionId: focusSectionId)
        }
    }

    private func openControl(
        section: XTControlSurfaceView.Section,
        focusSectionId: String? = nil
    ) {
        preferredControlSection = section
        selectedPrimarySurface = .control

        if let focusSectionId {
            appModel.requestSettingsFocus(sectionId: focusSectionId)
        }
    }

    private func processProjectSettingsFocusRequest() {
        guard let request = navigationFocusSnapshot.projectSettingsFocusRequest else { return }
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
            openControl(section: .supervisor)
        }
        let openSupervisorModelSettings: (_ route: XTSupervisorModelSettingsRoute) -> Void = { route in
            appModel.requestModelSettingsFocus(
                title: route.title,
                detail: route.detail
            )
            openControl(section: .models)
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
            openControl(section: .hub)
        case .supervisorSettings:
            openSupervisorSettings()
        case let .supervisorModelSettings(route):
            openSupervisorModelSettings(route)
        case let .resume(projectId):
            selectedPrimarySurface = .work
            if let projectId {
                appModel.presentResumeBrief(projectId: projectId)
            } else {
                appModel.presentPreferredResumeBrief()
            }
        case let .project(projectRoute):
            selectedPrimarySurface = .work
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

private struct ContentToolbar: ToolbarContent {
    @Environment(\.xtAppModelReference) private var appModelReference

    let selectedPrimarySurface: XTPrimarySurface
    @Binding var showMemoryInspector: Bool
    @Binding var showHistoryPanel: Bool
    @Binding var showCreateProject: Bool
    @Binding var showProjectSettings: Bool
    @Binding var projectSettingsProjectId: String?
    let selectPrimarySurface: (XTPrimarySurface) -> Void
    let openControl: (XTControlSurfaceView.Section, String?) -> Void

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .automatic) {
            Button("Open Project...") {
                selectPrimarySurface(.work)
                appModel.openProjectPicker()
            }
        }

        ContentResumeToolbarItems(selectPrimarySurface: selectPrimarySurface)

        ContentWorkToolbarItems(
            selectedPrimarySurface: selectedPrimarySurface,
            showMemoryInspector: $showMemoryInspector,
            showHistoryPanel: $showHistoryPanel,
            showCreateProject: $showCreateProject,
            showProjectSettings: $showProjectSettings,
            projectSettingsProjectId: $projectSettingsProjectId
        )

        ContentControlToolbarItems(openControl: openControl)
    }

    private var appModel: AppModel {
        guard let appModelReference else {
            preconditionFailure("ContentToolbar requires xtAppModelReference")
        }
        return appModelReference
    }
}

private struct ContentResumeToolbarItems: ToolbarContent {
    @Environment(\.xtAppModelReference) private var appModelReference
    @EnvironmentObject private var globalHomeStore: XTGlobalHomeStore

    let selectPrimarySurface: (XTPrimarySurface) -> Void

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .automatic) {
            Button {
                selectPrimarySurface(.work)
                if let target = toolbarResumeTarget {
                    appModel.presentResumeBrief(projectId: target.projectId)
                }
            } label: {
                Label("接上次进度", systemImage: "arrow.clockwise.circle")
            }
            .help(toolbarResumeHelp)
            .disabled(toolbarResumeTarget == nil)
        }
    }

    private var toolbarResumeTarget: AXResumeReminderProjectPresentation? {
        globalHomeStore.snapshot.preferredResumeProject
    }

    private var toolbarResumeHelp: String {
        guard let target = toolbarResumeTarget else {
            return "当前没有可恢复的交接摘要"
        }
        return "接上次进度：\(target.projectDisplayName) · \(target.summary.detailText)。只会在你点击后展开，不会自动塞进当前 prompt。"
    }

    private var appModel: AppModel {
        guard let appModelReference else {
            preconditionFailure("ContentResumeToolbarItems requires xtAppModelReference")
        }
        return appModelReference
    }
}

private struct ContentWorkToolbarItems: ToolbarContent {
    let selectedPrimarySurface: XTPrimarySurface
    @Binding var showMemoryInspector: Bool
    @Binding var showHistoryPanel: Bool
    @Binding var showCreateProject: Bool
    @Binding var showProjectSettings: Bool
    @Binding var projectSettingsProjectId: String?

    var body: some ToolbarContent {
        if selectedPrimarySurface == .work {
            ContentActiveWorkToolbarItems(
                showMemoryInspector: $showMemoryInspector,
                showHistoryPanel: $showHistoryPanel,
                showCreateProject: $showCreateProject,
                showProjectSettings: $showProjectSettings,
                projectSettingsProjectId: $projectSettingsProjectId
            )
        }
    }
}

private struct ContentActiveWorkToolbarItems: ToolbarContent {
    @Environment(\.xtAppModelReference) private var appModelReference
    @EnvironmentObject private var hubConnectionStore: XTHubConnectionStore
    @EnvironmentObject private var workSurfaceStore: XTWorkSurfaceStore
    @EnvironmentObject private var projectListStore: XTProjectListStore

    @Binding var showMemoryInspector: Bool
    @Binding var showHistoryPanel: Bool
    @Binding var showCreateProject: Bool
    @Binding var showProjectSettings: Bool
    @Binding var projectSettingsProjectId: String?

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .automatic) {
            if hubConnectionSnapshot.interactive {
                Divider()

                Button {
                    appModel.toggleMultiProjectView()
                } label: {
                    Image(systemName: workSurfaceSnapshot.isMultiProjectViewEnabled ? "square.grid.2x2" : "square")
                }
                .help(workSurfaceSnapshot.isMultiProjectViewEnabled ? "Switch to Single Project View" : "Switch to Multi-Project View")

                if workSurfaceSnapshot.isMultiProjectViewEnabled {
                    Button {
                        showCreateProject = true
                    } label: {
                        Image(systemName: "plus.circle")
                    }
                    .help("Create New Project")
                }
            }

            if shouldShowWorkToolbarTools {
                Divider()

                Button {
                    showHistoryPanel.toggle()
                } label: {
                    Image(systemName: "clock")
                }
                .help("Toggle History Panel")

                Button {
                    showMemoryInspector.toggle()
                } label: {
                    Image(systemName: "sidebar.right")
                }
                .help("Toggle Memory Inspector")

                Button {
                    projectSettingsProjectId = workSurfaceSnapshot.selectedProjectId
                    showProjectSettings = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .help("Project Settings")
                .disabled(!canOpenProjectSettings)

                if let pid = currentWorkProjectId {
                    Picker(
                        "",
                        selection: Binding(
                            get: {
                                workSurfaceSnapshot.selectedProjectId == pid
                                    ? workSurfaceSnapshot.selectedPane
                                    : appModel.pane(for: pid)
                            },
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
            }
        }
    }

    private var shouldShowWorkToolbarTools: Bool {
        currentWorkProjectId != nil
    }

    private var canOpenProjectSettings: Bool {
        currentWorkProjectId != nil
    }

    private var currentWorkProjectId: String? {
        concreteProjectId(workSurfaceSnapshot.selectedProjectId)
            ?? concreteProjectId(projectListStore.snapshot.selectedProjectId)
    }

    private var hubConnectionSnapshot: XTHubConnectionSnapshot {
        hubConnectionStore.snapshot
    }

    private var workSurfaceSnapshot: XTWorkSurfaceSnapshot {
        workSurfaceStore.snapshot
    }

    private func concreteProjectId(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != AXProjectRegistry.globalHomeId else {
            return nil
        }
        return trimmed
    }

    private var appModel: AppModel {
        guard let appModelReference else {
            preconditionFailure("ContentActiveWorkToolbarItems requires xtAppModelReference")
        }
        return appModelReference
    }
}

private struct ContentControlToolbarItems: ToolbarContent {
    @EnvironmentObject private var hubConnectionStore: XTHubConnectionStore

    let openControl: (XTControlSurfaceView.Section, String?) -> Void

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .automatic) {
            Divider()

            Button {
                if hubConnectionSnapshot.interactive {
                    openControl(.hub, nil)
                } else {
                    openControl(.hub, "pair_hub")
                }
            } label: {
                Label(controlButtonTitle, systemImage: controlButtonIconName)
            }
            .keyboardShortcut("x", modifiers: [.command, .option])
            .help(controlButtonHelp)
        }
    }

    private var hubConnectionSnapshot: XTHubConnectionSnapshot {
        hubConnectionStore.snapshot
    }

    private var controlButtonIconName: String {
        XTHubConnectionPresentation.controlButtonIconName(for: hubConnectionSnapshot)
    }

    private var controlButtonTitle: String {
        XTHubConnectionPresentation.controlButtonTitle(for: hubConnectionSnapshot)
    }

    private var controlButtonHelp: String {
        XTHubConnectionPresentation.controlButtonHelp(for: hubConnectionSnapshot)
    }
}

private struct ContentWorkSurfaceHost: View {
    @Environment(\.xtAppModelReference) private var appModelReference
    @EnvironmentObject private var hubConnectionStore: XTHubConnectionStore
    @EnvironmentObject private var workSurfaceStore: XTWorkSurfaceStore
    @EnvironmentObject private var projectListStore: XTProjectListStore

    let showHistoryPanel: Bool
    let showMemoryInspector: Bool

    var body: some View {
        HSplitView {
            workMainPane

            if shouldShowHistoryPanel, let ctx = effectiveProjectContext {
                HistoryPanelView(ctx: ctx, session: appModel.session(for: ctx))
                    .frame(minWidth: 300, maxWidth: 400)
            }

            if shouldShowMemoryInspector, let ctx = effectiveProjectContext {
                MemoryInspectorView(ctx: ctx, memory: effectiveProjectMemory)
            }
        }
    }

    private var workMainPane: some View {
        VStack(spacing: 0) {
            if shouldShowMultiProjectGrid {
                ProjectsGridView(projectsManager: appModel.legacyMultiProjectManager)
            } else if isEffectiveGlobalHomeSelected {
                GlobalHomeView()
            } else if let ctx = effectiveProjectContext {
                if effectiveSelectedPane == .terminal {
                    ProjectTerminalView(ctx: ctx, session: appModel.terminalSession(for: ctx))
                } else {
                    ModernChatView(
                        ctx: ctx,
                        memory: effectiveProjectMemory,
                        config: effectiveProjectConfig,
                        hubConnected: hubConnectionSnapshot.interactive,
                        session: appModel.session(for: ctx)
                    )
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Work")
                        .font(.title2)
                    Text("从左侧项目列表进入工作台；系统级设置和审查入口已经移到其它一级面。")
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .padding(16)
            }
        }
        .frame(minWidth: 720, minHeight: 520)
    }

    private var shouldShowHistoryPanel: Bool {
        showHistoryPanel &&
            effectiveProjectContext != nil &&
            !shouldShowMultiProjectGrid
    }

    private var shouldShowMemoryInspector: Bool {
        showMemoryInspector &&
            effectiveProjectContext != nil &&
            !shouldShowMultiProjectGrid
    }

    private var shouldShowMultiProjectGrid: Bool {
        workSurfaceSnapshot.isMultiProjectViewEnabled &&
            hubConnectionSnapshot.interactive &&
            effectiveSelectedConcreteProjectId == nil
    }

    private var isEffectiveGlobalHomeSelected: Bool {
        effectiveSelectedConcreteProjectId == nil &&
            (
                workSurfaceSnapshot.selectedProjectId == AXProjectRegistry.globalHomeId ||
                projectListStore.snapshot.selectedProjectId == AXProjectRegistry.globalHomeId
            )
    }

    private var hubConnectionSnapshot: XTHubConnectionSnapshot {
        hubConnectionStore.snapshot
    }

    private var workSurfaceSnapshot: XTWorkSurfaceSnapshot {
        workSurfaceStore.snapshot
    }

    private var effectiveProjectContext: AXProjectContext? {
        guard let selectedProjectId = effectiveSelectedConcreteProjectId else {
            return nil
        }
        if let projectContext = workSurfaceSnapshot.projectContext,
           projectId(for: projectContext) == selectedProjectId {
            return projectContext
        }
        return appModel.projectContext(for: selectedProjectId)
    }

    private var effectiveProjectMemory: AXMemory? {
        guard let ctx = effectiveProjectContext,
              let snapshotContext = workSurfaceSnapshot.projectContext,
              snapshotContext.root.standardizedFileURL.path == ctx.root.standardizedFileURL.path else {
            return nil
        }
        return workSurfaceSnapshot.memory
    }

    private var effectiveProjectConfig: AXProjectConfig? {
        guard let ctx = effectiveProjectContext,
              let snapshotContext = workSurfaceSnapshot.projectContext,
              snapshotContext.root.standardizedFileURL.path == ctx.root.standardizedFileURL.path else {
            return nil
        }
        return workSurfaceSnapshot.projectConfig
    }

    private var effectiveSelectedPane: AXProjectPane {
        guard let selectedProjectId = effectiveSelectedConcreteProjectId else {
            return .chat
        }
        if workSurfaceSnapshot.selectedProjectId == selectedProjectId {
            return workSurfaceSnapshot.selectedPane
        }
        return appModel.pane(for: selectedProjectId)
    }

    private var effectiveSelectedConcreteProjectId: String? {
        concreteProjectId(workSurfaceSnapshot.selectedProjectId)
            ?? concreteProjectId(projectListStore.snapshot.selectedProjectId)
            ?? concreteProjectId(appModel.selectedProjectId)
    }

    private func concreteProjectId(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != AXProjectRegistry.globalHomeId else {
            return nil
        }
        return trimmed
    }

    private func projectId(for ctx: AXProjectContext) -> String {
        AXProjectRegistryStore.projectId(forRoot: ctx.root)
    }

    private var appModel: AppModel {
        guard let appModelReference else {
            preconditionFailure("ContentWorkSurfaceHost requires xtAppModelReference")
        }
        return appModelReference
    }
}

private struct XTInactiveWorkSurfacePlaceholder: View {
    var body: some View {
        Color.clear
            .frame(minWidth: 720, minHeight: 520)
    }
}

private struct XTInactiveReviewSurfacePlaceholder: View {
    var body: some View {
        Color.clear
            .frame(minWidth: 820, minHeight: 620)
    }
}

private struct XTInactiveControlSurfacePlaceholder: View {
    var body: some View {
        Color.clear
            .frame(minWidth: 900, minHeight: 700)
    }
}

private struct SupervisorSurfaceWarmupView: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)
            Text("正在打开 Supervisor")
                .font(.headline)
            Text("先切换导航，再挂载总控面板。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            XTPerformanceTrace.event("XT Supervisor Warmup Appeared")
        }
    }
}

private struct PrimarySurfaceWarmupView: View {
    let surface: XTPrimarySurface

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)
            Text("正在打开 \(surface.title)")
                .font(.headline)
            Text("先响应导航，再挂载面板。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            XTPerformanceTrace.event(
                "XT Primary Surface Warmup Appeared",
                surface.rawValue
            )
        }
    }
}
