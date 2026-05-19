import SwiftUI

/// 新的聊天视图，使用现代化的消息时间线
struct ModernChatView: View {
    private struct WorkHeaderState: Equatable {
        var readinessText: String
        var readinessTone: ProjectCoderExecutionStatusTone
        var nextStepText: String
        var detailText: String?

        static let loading = WorkHeaderState(
            readinessText: "载入中",
            readinessTone: .neutral,
            nextStepText: "正在读取当前项目状态。",
            detailText: nil
        )
    }

    private struct RuntimeHeaderSnapshot: Equatable {
        var displayName: String
        var governanceInterception: ProjectGovernanceInterceptionPresentation?
        var latestSessionSummary: AXSessionSummaryCapsulePresentation?
        var resumeReminder: AXSessionSummaryCapsulePresentation?
        var coderSnapshot: AXRoleExecutionSnapshot
        var configuredModelId: String
        var interfaceLanguage: XTInterfaceLanguage
        var statusPresentation: ProjectCoderExecutionStatusPresentation?
        var primaryStatusAction: ProjectCoderExecutionStatusPrimaryActionPresentation?
        var workHeaderState: WorkHeaderState
        var routeNeedsAttention: Bool
        var statusActionDisabled: Bool
        var resumeActionDisabled: Bool

        static let empty = RuntimeHeaderSnapshot(
            displayName: "",
            governanceInterception: nil,
            latestSessionSummary: nil,
            resumeReminder: nil,
            coderSnapshot: .empty(role: .coder),
            configuredModelId: "",
            interfaceLanguage: .defaultPreference,
            statusPresentation: nil,
            primaryStatusAction: nil,
            workHeaderState: .loading,
            routeNeedsAttention: false,
            statusActionDisabled: false,
            resumeActionDisabled: false
        )
    }

    let ctx: AXProjectContext
    let memory: AXMemory?
    let config: AXProjectConfig?
    let hubConnected: Bool
    let session: ChatSessionModel
    @Environment(\.xtAppModelReference) private var appModelReference
    @EnvironmentObject private var navigationFocusStore: XTNavigationFocusStore
    @Environment(\.openWindow) private var openWindow
    @StateObject private var chatStatusStore = XTChatStatusStore()
    @State private var highlightedSkillActivityRequestId: String?
    @State private var highlightedSkillActivityFocusNonce: Int?
    @State private var runtimeHeaderSnapshot: RuntimeHeaderSnapshot = .empty
    @State private var timelineScrollToBottomNonce = 0
    @State private var localToolApprovalFocusNonce = 1_000_000

    var body: some View {
        let statusSnapshot = chatStatusSnapshot
        VStack(spacing: 0) {
            projectRuntimeSection

            Divider()

            ZStack {
                // 背景
                Color(nsColor: .windowBackgroundColor)
                    .ignoresSafeArea()

                // 消息时间线
                MessageTimelineView(
                    ctx: ctx,
                    config: config,
                    session: session,
                    hubConnected: hubConnected,
                    onApproveSkillActivity: { requestID in
                        session.approvePendingTool(requestID: requestID, router: appModel.llmRouter)
                    },
                    onRetrySkillActivity: { item in
                        session.retryProjectSkillActivity(item, router: appModel.llmRouter)
                    },
                    onApprovePendingTools: {
                        session.approvePendingTools(router: appModel.llmRouter)
                    },
                    onRejectPendingTools: {
                        session.rejectPendingTools()
                    },
                    onOpenGovernance: { destination, focusContext in
                        appModel.requestProjectSettingsFocus(
                            projectId: projectId,
                            destination: destination,
                            title: focusContext?.title,
                            detail: focusContext?.detail
                        )
                    },
                    onStartWorkPrompt: { prompt in
                        startWorkPrompt(prompt)
                    },
                    onResumeProject: {
                        appModel.presentResumeBrief(projectId: projectId)
                    },
                    onRouteDiagnose: {
                        session.presentProjectRouteDiagnosis(
                            ctx: ctx,
                            config: config,
                            router: appModel.llmRouter
                        )
                    },
                    focusedSkillActivityRequestId: highlightedSkillActivityRequestId,
                    focusedSkillActivityNonce: highlightedSkillActivityFocusNonce,
                    bottomPadding: 24,
                    scrollToBottomNonce: timelineScrollToBottomNonce
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .layoutPriority(1)

            VStack(spacing: 0) {
                Divider()
                DockInputView(
                    ctx: ctx,
                    memory: memory,
                    config: config,
                    hubConnected: hubConnected,
                    session: session,
                    composer: session.composer,
                    status: statusSnapshot
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            chatStatusStore.bind(to: session)
            session.ensureLoaded(ctx: ctx, limit: 200)
            refreshProjectRuntimeHeaderSnapshot()
            requestTimelineScrollToBottom()
        }
        .onChange(of: ctx.root.path) { _ in
            chatStatusStore.bind(to: session)
            session.ensureLoaded(ctx: ctx, limit: 200)
            refreshProjectRuntimeHeaderSnapshot()
            requestTimelineScrollToBottom()
        }
        .onChange(of: sessionIdentity) { _ in
            chatStatusStore.bind(to: session)
            session.ensureLoaded(ctx: ctx, limit: 200)
            refreshProjectRuntimeHeaderSnapshot()
            requestTimelineScrollToBottom()
        }
        .onChange(of: hubConnected) { _ in
            refreshProjectRuntimeHeaderSnapshot()
        }
        .onChange(of: config) { _ in
            refreshProjectRuntimeHeaderSnapshot()
        }
        .onAppear {
            processProjectFocusRequest()
        }
        .onChange(of: navigationFocusSnapshot.projectFocusRequest?.nonce) { _ in
            processProjectFocusRequest()
        }
        .onChange(of: chatStatusSnapshot.isSending) { isSending in
            if !isSending {
                processProjectFocusRequest()
            }
            refreshProjectRuntimeHeaderSnapshot()
        }
        .onChange(of: chatStatusSnapshot.pendingToolCallIDSignature) { _ in
            if chatStatusSnapshot.pendingToolCalls.isEmpty {
                highlightedSkillActivityRequestId = nil
                highlightedSkillActivityFocusNonce = nil
            } else if let focusedRequestId = highlightedSkillActivityRequestId,
                      !chatStatusSnapshot.pendingToolCalls.contains(where: { $0.id == focusedRequestId }) {
                highlightedSkillActivityRequestId = nil
                highlightedSkillActivityFocusNonce = nil
            }
            processProjectFocusRequest()
            refreshProjectRuntimeHeaderSnapshot()
        }
        .onChange(of: chatStatusSnapshot.messageCount) { _ in
            refreshProjectRuntimeHeaderSnapshot()
        }
    }

    private var sessionIdentity: ObjectIdentifier {
        ObjectIdentifier(session)
    }

    private var chatStatusSnapshot: XTChatStatusSnapshot {
        if chatStatusStore.isBound(to: session) {
            return chatStatusStore.snapshot
        }
        return XTChatStatusSnapshot(
            messageCount: session.messages.count,
            isSending: session.isSending,
            lastError: session.lastError,
            pendingToolCalls: session.pendingToolCalls
        )
    }

    private var projectId: String {
        AXProjectRegistryStore.projectId(forRoot: ctx.root)
    }

    private var navigationFocusSnapshot: XTNavigationFocusSnapshot {
        navigationFocusStore.snapshot
    }

    private var appModel: AppModel {
        guard let appModelReference else {
            preconditionFailure("ModernChatView requires xtAppModelReference")
        }
        return appModelReference
    }

    private func processProjectFocusRequest() {
        guard let request = navigationFocusSnapshot.projectFocusRequest,
              request.projectId == projectId else {
            return
        }

        switch request.subject {
        case let .toolApproval(requestId):
            guard !chatStatusSnapshot.pendingToolCalls.isEmpty else { return }
            highlightedSkillActivityFocusNonce = request.nonce

            if let requestId = requestId?.trimmingCharacters(in: .whitespacesAndNewlines),
               !requestId.isEmpty {
                if chatStatusSnapshot.pendingToolCalls.contains(where: { $0.id == requestId }) {
                    highlightedSkillActivityRequestId = requestId
                    appModel.clearProjectFocusRequest(request)
                    return
                }
                highlightedSkillActivityRequestId = nil
                appModel.clearProjectFocusRequest(request)
                return
            }

            highlightedSkillActivityRequestId = nil
            appModel.clearProjectFocusRequest(request)
        case .routeDiagnose:
            guard !chatStatusSnapshot.isSending else { return }
            session.presentProjectRouteDiagnosis(
                ctx: ctx,
                config: config,
                router: appModel.llmRouter
            )
            appModel.clearProjectFocusRequest(request)
        }
    }

    private var projectRuntimeSection: some View {
        let headerSnapshot = runtimeHeaderSnapshot

        return ProjectWorkHeaderCard(
            icon: "hammer.circle.fill",
            title: headerSnapshot.displayName.isEmpty ? ctx.projectName() : headerSnapshot.displayName,
            readinessText: headerSnapshot.workHeaderState.readinessText,
            readinessTone: headerSnapshot.workHeaderState.readinessTone,
            nextStepText: headerSnapshot.workHeaderState.nextStepText,
            badgeText: headerSnapshot.latestSessionSummary?.badgeText,
            detailText: headerSnapshot.workHeaderState.detailText,
            statusPresentation: headerSnapshot.statusPresentation,
            primaryAction: chatPrimaryAction(
                routeNeedsAttention: headerSnapshot.routeNeedsAttention,
                primaryStatusAction: headerSnapshot.primaryStatusAction,
                configuredModelId: headerSnapshot.configuredModelId,
                snapshot: headerSnapshot.coderSnapshot,
                governanceInterception: headerSnapshot.governanceInterception,
                interfaceLanguage: headerSnapshot.interfaceLanguage,
                disabled: headerSnapshot.statusActionDisabled,
                statusSnapshot: chatStatusSnapshot,
                hasResumeReminder: headerSnapshot.resumeReminder != nil,
                resumeDisabled: headerSnapshot.resumeActionDisabled
            ),
            secondaryAction: chatSecondaryAction(
                routeNeedsAttention: headerSnapshot.routeNeedsAttention,
                primaryStatusAction: headerSnapshot.primaryStatusAction,
                latestSessionSummary: headerSnapshot.latestSessionSummary,
                resumeReminder: headerSnapshot.resumeReminder,
                disabled: headerSnapshot.statusActionDisabled
            ),
            tertiaryAction: headerSnapshot.resumeReminder == nil ? nil : ProjectWorkHeaderAction(
                title: "稍后",
                helpText: "隐藏这条恢复提醒，稍后再处理。",
                style: .plain,
                disabled: false
            ) {
                appModel.dismissResumeReminder(projectId: projectId)
                refreshProjectRuntimeHeaderSnapshot()
            }
        )
    }

    private func buildRuntimeHeaderSnapshot(
        statusSnapshot: XTChatStatusSnapshot
    ) -> RuntimeHeaderSnapshot {
        let coderSnapshot = XTProjectUIPresentationReadCache.roleExecutionSnapshot(
            for: ctx,
            role: .coder
        ) {
            AXRoleExecutionSnapshots.latestSnapshots(for: ctx)[.coder]
                ?? .empty(role: .coder)
        }
        let projectId = AXProjectRegistryStore.projectId(forRoot: ctx.root)
        let governancePresentation = XTProjectUIPresentationReadCache.governancePresentation(
            projectId: projectId
        ) {
            ProjectGovernancePresentation(
                resolved: appModel.resolvedProjectGovernance(for: ctx, config: config)
            )
        }
        let governanceInterception = XTProjectUIPresentationReadCache.latestGovernanceInterception(
            for: ctx,
            limit: 12
        ) {
            ProjectGovernanceInterceptionPresentation.latest(
                from: AXProjectSkillActivityStore.loadRecentActivities(ctx: ctx, limit: 12)
            )
        }
        let configuredModelId = AXRoleExecutionSnapshots.configuredModelId(
            for: .coder,
            projectConfig: config,
            settings: appModel.settingsStore.settings
        )
        let coderStatusPresentation = ProjectCoderExecutionStatusResolver.map(
            configuredModelId: configuredModelId,
            snapshot: coderSnapshot,
            hubConnected: hubConnected,
            governancePresentation: governancePresentation,
            governanceInterception: governanceInterception
        )
        let interfaceLanguage = appModel.settingsStore.settings.interfaceLanguage
        let primaryAction = ProjectCoderExecutionStatusPrimaryActionResolver.resolve(
            configuredModelId: configuredModelId,
            snapshot: coderSnapshot,
            hubConnected: hubConnected,
            governanceInterception: governanceInterception,
            language: interfaceLanguage
        )
        let latestSessionSummary = XTProjectUIPresentationReadCache.sessionSummary(for: ctx) {
            AXSessionSummaryCapsulePresentation.load(for: ctx)
        }
        let resumeReminder = appModel.resumeReminderPresentation(projectId: projectId)
        let workHeaderState = projectWorkHeaderState(
            statusSnapshot: statusSnapshot,
            coderStatusPresentation: coderStatusPresentation,
            primaryAction: primaryAction,
            latestSessionSummary: latestSessionSummary,
            resumeReminder: resumeReminder
        )
        let routeNeedsAttention = coderStatusPresentation.tone == ProjectCoderExecutionStatusTone.warning
            || coderStatusPresentation.tone == ProjectCoderExecutionStatusTone.danger
        let statusActionDisabled = statusSnapshot.isSending
            || !statusSnapshot.pendingToolCalls.isEmpty

        return RuntimeHeaderSnapshot(
            displayName: ctx.displayName(
                registry: appModel.registry,
                preferredDisplayName: ctx.projectName()
            ),
            governanceInterception: governanceInterception,
            latestSessionSummary: latestSessionSummary,
            resumeReminder: resumeReminder,
            coderSnapshot: coderSnapshot,
            configuredModelId: configuredModelId,
            interfaceLanguage: interfaceLanguage,
            statusPresentation: coderStatusPresentation,
            primaryStatusAction: primaryAction,
            workHeaderState: workHeaderState,
            routeNeedsAttention: routeNeedsAttention,
            statusActionDisabled: statusActionDisabled,
            resumeActionDisabled: statusSnapshot.isSending
        )
    }

    private func projectWorkHeaderState(
        statusSnapshot: XTChatStatusSnapshot,
        coderStatusPresentation: ProjectCoderExecutionStatusPresentation,
        primaryAction: ProjectCoderExecutionStatusPrimaryActionPresentation?,
        latestSessionSummary: AXSessionSummaryCapsulePresentation?,
        resumeReminder: AXSessionSummaryCapsulePresentation?
    ) -> WorkHeaderState {
        if !statusSnapshot.pendingToolCalls.isEmpty {
            let count = statusSnapshot.pendingToolCalls.count
            return WorkHeaderState(
                readinessText: "等待审批",
                readinessTone: .warning,
                nextStepText: "有 \(count) 个工具请求等待审批，审批后将自动继续。",
                detailText: "需要查看参数时，先打开下方审批详情再决定是否放行。"
            )
        }

        if statusSnapshot.isSending {
            return WorkHeaderState(
                readinessText: "正在执行",
                readinessTone: .neutral,
                nextStepText: "当前这一轮还在运行，等结果回来后再继续下一步。",
                detailText: ProjectWorkHeaderText.firstLine(coderStatusPresentation.summaryText)
            )
        }

        if coderStatusPresentation.tone == .warning || coderStatusPresentation.tone == .danger {
            let nextStep = primaryAction.map { "先\($0.title)，再继续当前项目。" }
                ?? "当前执行路径有阻塞，先处理模型或路由问题。"
            return WorkHeaderState(
                readinessText: "需修复",
                readinessTone: coderStatusPresentation.tone,
                nextStepText: nextStep,
                detailText: ProjectWorkHeaderText.firstLine(coderStatusPresentation.summaryText)
                    ?? ProjectWorkHeaderText.firstLine(primaryAction?.helpText)
            )
        }

        if let resumeReminder {
            return WorkHeaderState(
                readinessText: "可继续",
                readinessTone: .success,
                nextStepText: "检测到最近交接摘要，直接从上次边界继续最省事。",
                detailText: "最近交接：\(resumeReminder.reasonLabel) · \(resumeReminder.relativeText)"
            )
        }

        return WorkHeaderState(
            readinessText: "可开始",
            readinessTone: coderStatusPresentation.tone == .neutral ? .success : coderStatusPresentation.tone,
            nextStepText: "底部输入框就是当前项目 Coder 聊天；直接描述要改什么、跑什么或继续哪一步。",
            detailText: ProjectWorkHeaderText.firstLine(coderStatusPresentation.summaryText)
                ?? latestSessionSummary?.detailText
        )
    }

    private func chatPrimaryAction(
        routeNeedsAttention: Bool,
        primaryStatusAction: ProjectCoderExecutionStatusPrimaryActionPresentation?,
        configuredModelId: String,
        snapshot: AXRoleExecutionSnapshot,
        governanceInterception: ProjectGovernanceInterceptionPresentation?,
        interfaceLanguage: XTInterfaceLanguage,
        disabled: Bool,
        statusSnapshot: XTChatStatusSnapshot,
        hasResumeReminder: Bool,
        resumeDisabled: Bool
    ) -> ProjectWorkHeaderAction? {
        if !statusSnapshot.pendingToolCalls.isEmpty {
            let count = statusSnapshot.pendingToolCalls.count
            return ProjectWorkHeaderAction(
                title: "审批",
                helpText: "批准当前 \(count) 个待审批工具请求，审批后自动继续执行。",
                style: .prominent,
                disabled: statusSnapshot.isSending
            ) {
                session.approvePendingTools(router: appModel.llmRouter)
            }
        }

        if routeNeedsAttention, let primaryStatusAction {
            return statusAction(
                primaryStatusAction,
                configuredModelId: configuredModelId,
                snapshot: snapshot,
                governanceInterception: governanceInterception,
                interfaceLanguage: interfaceLanguage,
                style: .prominent,
                disabled: disabled
            )
        }

        if hasResumeReminder {
            return ProjectWorkHeaderAction(
                title: "接上次进度",
                helpText: "基于 canonical memory、session summary 与最近执行记录，生成项目接续摘要；不会写入主上下文。",
                style: .prominent,
                disabled: resumeDisabled
            ) {
                appModel.presentResumeBrief(projectId: projectId)
            }
        }

        return nil
    }

    private func focusPendingToolApproval(requestId: String?) {
        highlightedSkillActivityRequestId = requestId
        highlightedSkillActivityFocusNonce = nextLocalProjectFocusNonce()
    }

    private func nextLocalProjectFocusNonce() -> Int {
        localToolApprovalFocusNonce &+= 1
        return localToolApprovalFocusNonce
    }

    private func chatSecondaryAction(
        routeNeedsAttention: Bool,
        primaryStatusAction: ProjectCoderExecutionStatusPrimaryActionPresentation?,
        latestSessionSummary: AXSessionSummaryCapsulePresentation?,
        resumeReminder: AXSessionSummaryCapsulePresentation?,
        disabled: Bool
    ) -> ProjectWorkHeaderAction? {
        if let firstPending = chatStatusSnapshot.pendingToolCalls.first {
            let count = chatStatusSnapshot.pendingToolCalls.count
            return ProjectWorkHeaderAction(
                title: "查看详情",
                helpText: "跳到当前项目历史区里的 \(count) 个待审批工具请求。",
                style: .secondary,
                disabled: false
            ) {
                focusPendingToolApproval(requestId: firstPending.id)
            }
        }

        if routeNeedsAttention {
            return ProjectWorkHeaderAction(
                title: "项目设置",
                helpText: "打开当前项目的治理与执行设置。",
                style: .secondary,
                disabled: false
            ) {
                openProjectSettingsOverview()
            }
        }

        if primaryStatusAction != nil || latestSessionSummary != nil || resumeReminder != nil {
            return ProjectWorkHeaderAction(
                title: "查看路由",
                helpText: "解释这一轮为什么命中当前执行路径。",
                style: .secondary,
                disabled: disabled
            ) {
                session.presentProjectRouteDiagnosis(
                    ctx: ctx,
                    config: config,
                    router: appModel.llmRouter
                )
            }
        }

        return ProjectWorkHeaderAction(
            title: "项目设置",
            helpText: "打开当前项目的治理与执行设置。",
            style: .secondary,
            disabled: false
        ) {
            openProjectSettingsOverview()
        }
    }

    private func statusAction(
        _ action: ProjectCoderExecutionStatusPrimaryActionPresentation,
        configuredModelId: String,
        snapshot: AXRoleExecutionSnapshot,
        governanceInterception: ProjectGovernanceInterceptionPresentation?,
        interfaceLanguage: XTInterfaceLanguage,
        style: ProjectWorkHeaderActionStyle,
        disabled: Bool
    ) -> ProjectWorkHeaderAction {
        ProjectWorkHeaderAction(
            title: action.title,
            helpText: action.helpText,
            style: style,
            disabled: disabled
        ) {
            ProjectCoderExecutionStatusPrimaryActionResolver.perform(
                action.kind,
                configuredModelId: configuredModelId,
                snapshot: snapshot,
                ctx: ctx,
                config: config,
                session: session,
                appModel: appModel,
                openWindow: openWindow,
                governanceInterception: governanceInterception,
                interfaceLanguage: interfaceLanguage
            )
        }
    }

    private func openProjectSettingsOverview() {
        appModel.requestProjectSettingsFocus(
            projectId: projectId,
            destination: .overview
        )
    }

    private func startWorkPrompt(_ prompt: String) {
        session.composer.draft = prompt
        guard hubConnected,
              !chatStatusSnapshot.isSending,
              chatStatusSnapshot.pendingToolCalls.isEmpty,
              AXChatAttachmentSupport.hasSubmittableContent(
                draft: session.composer.draft,
                attachments: session.composer.draftAttachments
              ) else {
            return
        }

        session.send(
            ctx: ctx,
            memory: memory,
            config: config,
            router: appModel.llmRouter
        )
    }

    private func refreshProjectRuntimeHeaderSnapshot() {
        let next = buildRuntimeHeaderSnapshot(statusSnapshot: chatStatusSnapshot)
        guard runtimeHeaderSnapshot != next else { return }
        runtimeHeaderSnapshot = next
    }

    private func requestTimelineScrollToBottom() {
        timelineScrollToBottomNonce &+= 1
    }
}

/// 预览
#if DEBUG
struct ModernChatView_Previews: PreviewProvider {
    static var previews: some View {
        let ctx = AXProjectContext(
            root: URL(fileURLWithPath: "/tmp/test")
        )
        let session = ChatSessionModel()

        // 添加示例消息
        session.messages = [
            AXChatMessage(role: .user, content: "Hello, can you help me with this code?", createdAt: Date().timeIntervalSince1970 - 300),
            AXChatMessage(role: .assistant, tag: "claude-3.5", content: "Of course! I'd be happy to help. What would you like to know?", createdAt: Date().timeIntervalSince1970 - 280),
            AXChatMessage(role: .user, content: "Can you read the main.swift file?", createdAt: Date().timeIntervalSince1970 - 200),
            AXChatMessage(role: .assistant, tag: "claude-3.5", content: "I'll read that file for you.", createdAt: Date().timeIntervalSince1970 - 180),
        ]

        let appModel = AppModel()

        return ModernChatView(
            ctx: ctx,
            memory: nil,
            config: nil,
            hubConnected: true,
            session: session
        )
        .environment(\.xtAppModelReference, appModel)
        .environmentObject(appModel.navigationFocusStore)
        .environmentObject(appModel.hubConnectionStore)
        .frame(width: 1000, height: 700)
    }
}
#endif
