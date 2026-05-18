import AppKit
import SwiftUI

struct ProjectTerminalView: View {
    private struct TerminalWorkHeaderState: Equatable {
        var readinessText: String
        var readinessTone: ProjectCoderExecutionStatusTone
        var nextStepText: String
        var detailText: String?

        static let loading = TerminalWorkHeaderState(
            readinessText: "载入中",
            readinessTone: .neutral,
            nextStepText: "正在读取当前终端与 AI 路由状态。",
            detailText: nil
        )
    }

    private struct TerminalRuntimeHeaderSnapshot: Equatable {
        var displayName: String
        var terminalStatus: XTTerminalStatusSnapshot
        var coderSnapshot: AXRoleExecutionSnapshot
        var configuredModelId: String
        var interfaceLanguage: XTInterfaceLanguage
        var statusPresentation: ProjectCoderExecutionStatusPresentation?
        var primaryStatusAction: ProjectCoderExecutionStatusPrimaryActionPresentation?
        var headerState: TerminalWorkHeaderState
        var routeNeedsAttention: Bool

        static let empty = TerminalRuntimeHeaderSnapshot(
            displayName: "",
            terminalStatus: XTTerminalStatusSnapshot(
                isRunning: true,
                lastExitCode: nil,
                lastError: nil,
                outputIsEmpty: true
            ),
            coderSnapshot: .empty(role: .coder, source: "project_terminal"),
            configuredModelId: "",
            interfaceLanguage: .defaultPreference,
            statusPresentation: nil,
            primaryStatusAction: nil,
            headerState: .loading,
            routeNeedsAttention: false
        )
    }

    let ctx: AXProjectContext
    @ObservedObject var session: TerminalSessionModel
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let statusSnapshot = terminalStatusSnapshot
        let outputSnapshot = terminalOutputSnapshot

        VStack(spacing: 0) {
            header
            Divider()
            transcript(outputSnapshot: outputSnapshot)
            Divider()
            inputBar(statusSnapshot: statusSnapshot)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            bindSessionProjectionStores()
            session.ensureStarted()
            refreshTerminalRuntimeHeaderSnapshot(statusSnapshot: statusSnapshot)
        }
        .onChange(of: sessionIdentity) { _ in
            bindSessionProjectionStores()
            session.ensureStarted()
            refreshTerminalRuntimeHeaderSnapshot(statusSnapshot: terminalStatusSnapshot)
        }
        .onChange(of: statusSnapshot) { nextStatus in
            refreshTerminalRuntimeHeaderSnapshot(statusSnapshot: nextStatus)
        }
        .onChange(of: hubConnectionStore.snapshot) { _ in
            refreshTerminalRuntimeHeaderSnapshot(statusSnapshot: terminalStatusSnapshot)
        }
        .onChange(of: workSurfaceStore.snapshot) { _ in
            refreshTerminalRuntimeHeaderSnapshot(statusSnapshot: terminalStatusSnapshot)
        }
    }

    private var header: some View {
        let snapshot = AXRoleExecutionSnapshots.latestSnapshots(for: ctx)[.coder]
            ?? .empty(role: .coder, source: "project_terminal")
        let configuredModelId = AXRoleExecutionSnapshots.configuredModelId(
            for: .coder,
            projectConfig: projectConfig,
            settings: appModel.settingsStore.settings
        )
        let interfaceLanguage = appModel.settingsStore.settings.interfaceLanguage
        let primaryStatusAction = ProjectCoderExecutionStatusPrimaryActionResolver.resolve(
            configuredModelId: configuredModelId,
            snapshot: snapshot,
            hubConnected: appModel.hubConnected
        )
        let statusPresentation = ProjectCoderExecutionStatusResolver.map(
            configuredModelId: configuredModelId,
            snapshot: snapshot,
            hubConnected: appModel.hubConnected,
            governancePresentation: governancePresentation
        )
        let routeNeedsAttention = statusPresentation.tone == .warning || statusPresentation.tone == .danger
        let headerState = terminalWorkHeaderState(
            statusPresentation: statusPresentation,
            primaryStatusAction: primaryStatusAction
        )

        return ProjectWorkHeaderCard(
            icon: "terminal.fill",
            title: ctx.displayName(),
            readinessText: headerState.readinessText,
            readinessTone: headerState.readinessTone,
            nextStepText: headerState.nextStepText,
            badgeText: session.lastExitCode.map { "exit=\($0)" },
            detailText: headerState.detailText,
            statusPresentation: statusPresentation,
            primaryAction: terminalPrimaryAction(
                routeNeedsAttention: routeNeedsAttention,
                primaryStatusAction: primaryStatusAction,
                configuredModelId: configuredModelId,
                snapshot: snapshot,
                interfaceLanguage: interfaceLanguage
            ),
            secondaryAction: terminalSecondaryAction(routeNeedsAttention: routeNeedsAttention),
            tertiaryAction: session.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : ProjectWorkHeaderAction(
                title: "清空输出",
                helpText: "清空当前终端输出，不会停止 shell。",
                style: .plain,
                disabled: false
            ) {
                session.clearOutput()
            }
        )
    }

    private func transcript(outputSnapshot: XTTerminalOutputSnapshot) -> some View {
        TranscriptTextView(attributedText: transcriptAttributed(output: outputSnapshot.output))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .layoutPriority(1)
    }

    private func inputBar(statusSnapshot: XTTerminalStatusSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                TextField("Type a command…", text: terminalDraftBinding)
                    .font(.system(.body, design: .monospaced))
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        session.sendLine()
                    }

                Button("Send") {
                    session.sendLine()
                }
                .keyboardShortcut(.return, modifiers: [.command])

                Button("Ctrl+C") {
                    session.sendCtrlC()
                }

                if let err = statusSnapshot.lastError, !err.isEmpty {
                    Text(err)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.red)
                        .lineLimit(1)
                }
            }
        }
        .padding(10)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func transcriptAttributed(output: String) -> NSAttributedString {
        let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        return NSAttributedString(
            string: output.isEmpty ? "(empty)" : output,
            attributes: [
                .font: font,
                .foregroundColor: NSColor.labelColor,
            ]
        )
    }

    private var projectId: String {
        AXProjectRegistryStore.projectId(forRoot: ctx.root)
    }

    private var sessionIdentity: ObjectIdentifier {
        ObjectIdentifier(session)
    }

    private var terminalStatusSnapshot: XTTerminalStatusSnapshot {
        if terminalStatusStore.isBound(to: session) {
            return terminalStatusStore.snapshot
        }
        return XTTerminalStatusSnapshot(
            isRunning: session.isRunning,
            lastExitCode: session.lastExitCode,
            lastError: session.lastError,
            outputIsEmpty: session.output.isEmpty
        )
    }

    private var terminalOutputSnapshot: XTTerminalOutputSnapshot {
        if terminalOutputStore.isBound(to: session) {
            return terminalOutputStore.snapshot
        }
        return XTTerminalOutputSnapshot(
            output: XTTerminalOutputPresentation.visibleOutput(from: session.output)
        )
    }

    private var terminalDraftBinding: Binding<String> {
        Binding(
            get: { session.draft },
            set: { session.draft = $0 }
        )
    }

    private var hubConnected: Bool {
        hubConnectionStore.snapshot.interactive
    }

    private var workSurfaceSnapshot: XTWorkSurfaceSnapshot {
        workSurfaceStore.snapshot
    }

    private var appModel: AppModel {
        guard let appModelReference else {
            preconditionFailure("ProjectTerminalView requires xtAppModelReference")
        }
        return appModelReference
    }

    private var projectConfig: AXProjectConfig {
        if workSurfaceSnapshot.projectContext?.root.standardizedFileURL == ctx.root.standardizedFileURL,
           let config = workSurfaceSnapshot.projectConfig {
            return config
        }
        return XTProjectUIPresentationReadCache.projectConfig(for: ctx) {
            (try? AXProjectStore.loadOrCreateConfig(for: ctx))
        } ?? .default(forProjectRoot: ctx.root)
    }

    private func openGovernance(_ destination: XTProjectGovernanceDestination) {
        appModel.requestProjectSettingsFocus(
            projectId: projectId,
            destination: destination,
            preserveCurrentPane: true
        )
    }

    private func terminalWorkHeaderState(
        statusPresentation: ProjectCoderExecutionStatusPresentation,
        primaryStatusAction: ProjectCoderExecutionStatusPrimaryActionPresentation?
    ) -> (
        readinessText: String,
        readinessTone: ProjectCoderExecutionStatusTone,
        nextStepText: String,
        detailText: String?
    ) {
        let lastError = session.lastError?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if !session.isRunning {
            return (
                readinessText: "Shell 已停止",
                readinessTone: lastError.isEmpty ? .warning : .danger,
                nextStepText: "先重启项目 Shell，再继续运行命令或让 AI 接手。",
                detailText: lastError.isEmpty ? "Project-bound shell 当前没有运行。" : lastError
            )
        }

        if !lastError.isEmpty {
            return (
                readinessText: "Shell 异常",
                readinessTone: .danger,
                nextStepText: "先处理当前 shell 错误；如果 AI 路由也异常，再去看项目设置。",
                detailText: lastError
            )
        }

        if statusPresentation.tone == .warning || statusPresentation.tone == .danger {
            return (
                readinessText: "AI 需修复",
                readinessTone: statusPresentation.tone,
                nextStepText: primaryStatusAction.map { "Shell 可用；如果接下来要走 AI，先\($0.title)。" }
                    ?? "Shell 可用，但 AI 路由还需要先修复。",
                detailText: ProjectWorkHeaderText.firstLine(statusPresentation.summaryText)
            )
        }

        return (
            readinessText: "可工作",
            readinessTone: .success,
            nextStepText: "可以直接运行命令；如果接下来要让 AI 执行，当前路径也基本就绪。",
            detailText: "Project-bound shell 已附着到当前项目。"
        )
    }

    private func terminalPrimaryAction(
        routeNeedsAttention: Bool,
        primaryStatusAction: ProjectCoderExecutionStatusPrimaryActionPresentation?,
        configuredModelId: String,
        snapshot: AXRoleExecutionSnapshot,
        interfaceLanguage: XTInterfaceLanguage
    ) -> ProjectWorkHeaderAction? {
        if !session.isRunning {
            return ProjectWorkHeaderAction(
                title: "重启 Shell",
                helpText: "重新启动当前项目绑定的 shell。",
                style: .prominent,
                disabled: false
            ) {
                session.stop()
                session.ensureStarted()
            }
        }

        if routeNeedsAttention, let primaryStatusAction {
            return ProjectWorkHeaderAction(
                title: primaryStatusAction.title,
                helpText: primaryStatusAction.helpText,
                style: .prominent,
                disabled: false
            ) {
                performTerminalStatusAction(
                    primaryStatusAction.kind,
                    configuredModelId: configuredModelId,
                    snapshot: snapshot,
                    interfaceLanguage: interfaceLanguage
                )
            }
        }

        return nil
    }

    private func terminalSecondaryAction(
        routeNeedsAttention: Bool
    ) -> ProjectWorkHeaderAction {
        if routeNeedsAttention {
            return ProjectWorkHeaderAction(
                title: "项目设置",
                helpText: "打开当前项目的治理与执行设置。",
                style: .secondary,
                disabled: false
            ) {
                openGovernance(.overview)
            }
        }

        return ProjectWorkHeaderAction(
            title: "项目设置",
            helpText: "打开当前项目的治理与执行设置。",
            style: .secondary,
            disabled: false
        ) {
            openGovernance(.overview)
        }
    }

    private func performTerminalStatusAction(
        _ action: ProjectCoderExecutionStatusPrimaryActionKind,
        configuredModelId: String,
        snapshot: AXRoleExecutionSnapshot,
        interfaceLanguage: XTInterfaceLanguage
    ) {
        let routeSummary = ExecutionRoutePresentation.routeSummaryText(
            configuredModelId: configuredModelId,
            snapshot: snapshot
        )
        let governanceDetail = ProjectCoderExecutionStatusPrimaryActionResolver.governanceOpenDetail(
            snapshot: snapshot,
            governanceInterception: nil,
            language: interfaceLanguage
        )

        switch action {
        case .routeDiagnose:
            appModel.requestProjectRouteDiagnoseFocus(projectId: projectId)
            appModel.setPane(.chat, for: projectId)
        case .openModelSettings:
            appModel.requestModelSettingsFocus(
                role: .coder,
                title: XTL10n.RouteDiagnose.modelSettingsTitle(language: interfaceLanguage),
                detail: routeSummary ?? XTL10n.RouteDiagnose.modelSettingsFallback(language: interfaceLanguage)
            )
            SupervisorManager.shared.requestSupervisorWindow(
                sheet: .modelSettings,
                reason: "project_terminal_model_settings",
                focusConversation: false
            )
        case .openDiagnostics:
            appModel.requestSettingsFocus(
                sectionId: "diagnostics",
                title: XTL10n.RouteDiagnose.diagnosticsTitle(language: interfaceLanguage),
                detail: routeSummary ?? XTL10n.RouteDiagnose.diagnosticsFallback(language: interfaceLanguage)
            )
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        case .openHubRecovery:
            appModel.requestHubSetupFocus(
                sectionId: "troubleshoot",
                title: XTL10n.RouteDiagnose.hubRecoveryFocusTitle(language: interfaceLanguage),
                detail: routeSummary ?? XTL10n.RouteDiagnose.hubRecoveryFocusFallback(language: interfaceLanguage)
            )
            openWindow(id: "hub_setup")
        case .openHubConnectionLog:
            appModel.requestHubSetupFocus(
                sectionId: "connection_log",
                title: XTL10n.RouteDiagnose.hubLogFocusTitle(language: interfaceLanguage),
                detail: routeSummary ?? XTL10n.RouteDiagnose.hubLogFocusFallback(language: interfaceLanguage)
            )
            openWindow(id: "hub_setup")
        case .openExecutionTier:
            appModel.requestProjectSettingsFocus(
                projectId: projectId,
                destination: .executionTier,
                preserveCurrentPane: true,
                title: XTL10n.text(
                    interfaceLanguage,
                    zhHans: "治理拦截修复",
                    en: "Governance Repair"
                ),
                detail: governanceDetail ?? XTL10n.text(
                    interfaceLanguage,
                    zhHans: "最近这次动作被项目 A-Tier 拦下了，直接检查当前 A-Tier 与最低要求。",
                    en: "The latest action was blocked by the project's A-Tier. Check the current tier and minimum requirement directly."
                )
            )
        case .openGovernanceOverview:
            appModel.requestProjectSettingsFocus(
                projectId: projectId,
                destination: .overview,
                preserveCurrentPane: true,
                title: XTL10n.text(
                    interfaceLanguage,
                    zhHans: "治理拦截修复",
                    en: "Governance Repair"
                ),
                detail: governanceDetail ?? XTL10n.text(
                    interfaceLanguage,
                    zhHans: "最近这次动作被治理运行面拦下了，直接检查 effective governance truth、运行面限制和修复提示。",
                    en: "The latest action was blocked by the governance runtime surface. Check the effective governance truth, surface limits, and repair guidance directly."
                )
            )
        }
    }
}
