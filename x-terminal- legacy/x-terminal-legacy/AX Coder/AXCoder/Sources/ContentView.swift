import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.openWindow) private var openWindow

    @State private var showMemoryInspector: Bool = false
    @State private var showProjectSettings: Bool = false
    @State private var showHistoryPanel: Bool = false

    var body: some View {
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
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Button("Open Project…") {
                    appModel.openProjectPicker()
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
                    appModel.openSkillEditor()
                }
                .help("Open a skill folder or SKILL.md for editing")

                Button("Import Skills…") {
                    appModel.importSkills()
                }
                .help("Import skill folders into the skills library")

                Button {
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
            }
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

    private var mainPane: some View {
        VStack(spacing: 0) {
            if appModel.selectedProjectId == AXProjectRegistry.globalHomeId {
                GlobalHomeView()
            } else if let ctx = appModel.projectContext {
                if appModel.pane(for: appModel.selectedProjectId ?? "") == .terminal {
                    ProjectTerminalView(ctx: ctx, session: appModel.terminalSession(for: ctx))
                } else {
                    TerminalChatView(
                        ctx: ctx,
                        memory: appModel.memory,
                        config: appModel.projectConfig,
                        hubConnected: appModel.hubInteractive,
                        session: appModel.session(for: ctx)
                    )
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
            if let ctx = appModel.projectContext {
                ProjectSettingsView(ctx: ctx).environmentObject(appModel)
            }
        }
        .onOpenURL { url in
            handleDeepLink(url)
        }
        .onReceive(NotificationCenter.default.publisher(for: .xterminalOpenHubSetupWizard)) { _ in
            openWindow(id: "hub_setup")
        }
    }

    private func handleDeepLink(_ url: URL) {
        let scheme = (url.scheme ?? "").lowercased()
        guard scheme == "axcoder" || scheme == "xterminal" || scheme == "x-terminal" else {
            return
        }

        let host = (url.host ?? "").lowercased()
        let path = url.path.lowercased()
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        var query: [String: String] = [:]
        for item in items {
            query[item.name.lowercased()] = item.value ?? ""
        }

        let openSupervisor: () -> Void = {
            openWindow(id: "supervisor")
        }
        let openSupervisorSettings: () -> Void = {
            openWindow(id: "supervisor_settings")
        }

        if host == "supervisor" || path == "/supervisor" {
            openSupervisor()
            return
        }
        if host == "hub-setup" || path == "/hub-setup" {
            openWindow(id: "hub_setup")
            return
        }
        if host == "supervisor-settings" || path == "/supervisor-settings" {
            openSupervisorSettings()
            return
        }
        if host == "project" || path == "/project" {
            let projectId = (query["project_id"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !projectId.isEmpty {
                appModel.selectProject(projectId)
            }

            let pane = (query["pane"] ?? "").lowercased()
            if !projectId.isEmpty {
                if pane == "terminal" {
                    appModel.setPane(.terminal, for: projectId)
                } else if pane == "chat" {
                    appModel.setPane(.chat, for: projectId)
                }
            }

            let openTarget = (query["open"] ?? "").lowercased()
            if openTarget == "supervisor" {
                openSupervisor()
            } else if openTarget == "supervisor_settings" {
                openSupervisorSettings()
            }

            let grantRequestId = (query["grant_request_id"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !projectId.isEmpty, !grantRequestId.isEmpty {
                let capability = (query["grant_capability"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let reason = (query["grant_reason"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                appModel.prefillGrantContext(
                    projectId: projectId,
                    grantRequestId: grantRequestId,
                    capability: capability.isEmpty ? nil : capability,
                    reason: reason.isEmpty ? nil : reason
                )
            }
        }
    }
}
