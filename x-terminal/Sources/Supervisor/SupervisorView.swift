import Foundation
import AppKit
import SwiftUI

struct SupervisorView: View {
    private let supervisor = SupervisorManager.shared
    private let isPrewarming: Bool
    @StateObject private var ui = SupervisorViewUIState()
    @StateObject private var leanHeaderStore = SupervisorLeanHeaderProjectionStore(
        minimumUpdateIntervalNanoseconds: 16_000_000
    )
    @State private var leanSupervisorAutoOpenTask: Task<Void, Never>? = nil
    @State private var leanConversationMounted: Bool = false
    @State private var leanConversationMountTask: Task<Void, Never>? = nil
    @Environment(\.xtAppModelReference) private var appModelReference
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var hubConnectionStore: XTHubConnectionStore

    private static let leanAutoOpenDelayNanoseconds: UInt64 = 350_000_000
    private static let leanConversationMountDelayNanoseconds: UInt64 = 64_000_000

    init(isPrewarming: Bool = false) {
        self.isPrewarming = isPrewarming
    }

    var body: some View {
        Group {
            if isPrewarming {
                SupervisorInactiveSurfacePlaceholder()
                    .onAppear(perform: handleSupervisorDeactivation)
            } else if requiresFullSupervisorPresentation {
                fullSupervisorBody
            } else {
                leanSupervisorBody
            }
        }
        .frame(minWidth: 800, minHeight: 600)
        .onChange(of: isPrewarming) { prewarming in
            if prewarming {
                handleSupervisorDeactivation()
            } else {
                handleSupervisorActivation()
            }
        }
        .onDisappear(perform: handleSupervisorDeactivation)
        .background(
            XTSupervisorWindowAccessor { window in
                XTSupervisorWindowVisibilityRegistry.shared.track(window: window)
            }
            .frame(width: 0, height: 0)
        )
    }

    private var fullSupervisorBody: some View {
        SupervisorObservedFullPresentation(
            supervisor: supervisor,
            ui: ui,
            appModel: appModel,
            openWindow: openWindow,
            openURL: openURL
        )
    }

    private var leanSupervisorBody: some View {
        let snapshot = leanHeaderStore.snapshot
        let headerContext = snapshot.context(
            heartbeatFeedVisible: ui.showHeartbeatFeed,
            signalCenterVisible: ui.showSignalCenter
        )
        let detectedBigTaskCandidate = SupervisorBigTaskAssist.detect(
            inputText: ui.inputText,
            latestUserMessage: snapshot.latestUserMessageContent,
            dismissedFingerprint: ui.dismissedBigTaskFingerprint
        )
        let bigTaskSceneHint = detectedBigTaskCandidate.map {
            SupervisorBigTaskAssist.sceneHint(
                for: $0,
                selectedProject: snapshot.selectedProject,
                selectedProjectTemplate: snapshot.selectedProjectTemplate
            )
        }

        return VStack(spacing: 0) {
            SupervisorHeaderBar(
                configuredModelId: snapshot.configuredModelId,
                snapshot: snapshot.executionSnapshot,
                hubInteractive: hubConnectionStore.snapshot.interactive,
                latestRuntimeActivityText: snapshot.latestRuntimeActivityText,
                context: headerContext,
                voiceStatus: snapshot.voiceStatus,
                isProcessing: snapshot.isProcessing,
                processingStatusText: snapshot.processingStatusText,
                detectedBigTaskCandidate: detectedBigTaskCandidate,
                bigTaskSceneHint: bigTaskSceneHint,
                heartbeatIconScale: ui.heartbeatIconScale,
                onTriggerBigTask: triggerLightBigTaskFlow,
                onDismissBigTask: { ui.dismissedBigTaskFingerprint = $0.fingerprint },
                onVoiceCallAction: handleLightVoiceCallAction,
                onAction: performLightHeaderAction
            )

            Divider()

            Group {
                if leanConversationMounted {
                    SupervisorConversationPanel(
                        supervisor: supervisor,
                        inputText: uiBinding(\.inputText),
                        autoSendVoice: uiBinding(\.autoSendVoice),
                        focusRequestID: ui.conversationFocusRequestID
                    )
                    .onAppear {
                        XTPerformanceTrace.event("XT Supervisor Conversation Appeared")
                    }
                } else {
                    SupervisorConversationWarmupView()
                        .onAppear {
                            scheduleLeanConversationMountIfNeeded()
                        }
                }
            }
            .frame(maxHeight: .infinity)
        }
        .onAppear(perform: handleLeanSupervisorAppear)
        .onDisappear {
            cancelLeanSupervisorAutoOpen()
            cancelLeanConversationMount()
        }
        .onChange(of: leanHeaderStore.snapshot.focusRequestNonce) { _ in
            scheduleLeanSupervisorAutoOpenChecks()
        }
        .onChange(of: leanHeaderStore.snapshot.pendingHubGrantCount) { _ in
            scheduleLeanSupervisorAutoOpenChecks()
        }
        .onChange(of: leanHeaderStore.snapshot.pendingSkillApprovalCount) { _ in
            scheduleLeanSupervisorAutoOpenChecks()
        }
        .onChange(of: leanHeaderStore.snapshot.requestedWindowSheetID) { _ in
            scheduleLeanSupervisorAutoOpenChecks()
        }
    }

    private var requiresFullSupervisorPresentation: Bool {
        !isPrewarming &&
            (ui.showHeartbeatFeed ||
            ui.showSignalCenter ||
            ui.selectedSupervisorAuditDrillDown != nil)
    }

    private var lightweightHeaderContext: SupervisorHeaderControls.Context {
        leanHeaderStore.snapshot.context(
            heartbeatFeedVisible: ui.showHeartbeatFeed,
            signalCenterVisible: ui.showSignalCenter
        )
    }

    private var appModel: AppModel {
        guard let appModelReference else {
            preconditionFailure("SupervisorView requires xtAppModelReference")
        }
        return appModelReference
    }

    private func handleLeanSupervisorAppear() {
        XTPerformanceTrace.event(
            isPrewarming ? "XT Supervisor Lean Prewarm Appeared" : "XT Supervisor Lean Appeared"
        )
        supervisor.setAppModel(appModel)
        bindLeanHeaderStoreIfNeeded()
        if !isPrewarming {
            scheduleLeanConversationMountIfNeeded()
            handleSupervisorActivation()
        }
    }

    private func handleSupervisorActivation() {
        XTPerformanceTrace.event("XT Supervisor Lean Activated")
        bindLeanHeaderStoreIfNeeded()
        requestConversationFocus()
        scheduleLeanConversationMountIfNeeded()
        scheduleLeanSupervisorAutoOpenChecks()
    }

    private func handleSupervisorDeactivation() {
        cancelLeanSupervisorAutoOpen()
        cancelLeanConversationMount()
        leanHeaderStore.unbind()
        XTPerformanceTrace.event("XT Supervisor Lean Deactivated")
    }

    private func bindLeanHeaderStoreIfNeeded() {
        guard !leanHeaderStore.isBound(
            supervisor: supervisor,
            appModel: appModel
        ) else {
            return
        }
        XTPerformanceTrace.event("XT Supervisor Lean Header Store Bound")
        leanHeaderStore.bind(supervisor: supervisor, appModel: appModel)
    }

    private func scheduleLeanConversationMountIfNeeded() {
        guard !isPrewarming,
              !leanConversationMounted,
              leanConversationMountTask == nil else {
            return
        }
        XTPerformanceTrace.event(
            "XT Supervisor Conversation Mount Scheduled",
            "delay_ms=64"
        )
        leanConversationMountTask = Task { @MainActor in
            await Task.yield()
            try? await Task.sleep(nanoseconds: Self.leanConversationMountDelayNanoseconds)
            guard !Task.isCancelled else {
                leanConversationMountTask = nil
                return
            }
            leanConversationMountTask = nil
            leanConversationMounted = true
            XTPerformanceTrace.event("XT Supervisor Conversation Mount Committed")
        }
    }

    private func cancelLeanConversationMount() {
        leanConversationMountTask?.cancel()
        leanConversationMountTask = nil
        leanConversationMounted = false
    }

    private func scheduleLeanSupervisorAutoOpenChecks() {
        guard !isPrewarming else {
            cancelLeanSupervisorAutoOpen()
            return
        }
        leanSupervisorAutoOpenTask?.cancel()
        leanSupervisorAutoOpenTask = Task { @MainActor in
            await Task.yield()
            try? await Task.sleep(nanoseconds: Self.leanAutoOpenDelayNanoseconds)
            guard !Task.isCancelled else {
                leanSupervisorAutoOpenTask = nil
                return
            }
            leanSupervisorAutoOpenTask = nil
            guard !isPrewarming else { return }
            guard !requiresFullSupervisorPresentation else { return }
            let snapshot = leanHeaderStore.snapshot

            if snapshot.context.requestedWindowSheet != nil {
                XTPerformanceTrace.event("XT Supervisor Lean Auto Open", "requested_window_sheet")
                performLightHeaderLifecycleEvent(.requestedWindowSheetChanged)
            }
            if snapshot.context.hasFocusRequest {
                XTPerformanceTrace.event("XT Supervisor Lean Auto Open", "focus_request")
                performLightHeaderLifecycleEvent(.focusRequestChanged)
            }
            if snapshot.pendingHubGrantCount > 0 {
                XTPerformanceTrace.event("XT Supervisor Lean Auto Open", "pending_hub_grants")
                performLightHeaderLifecycleEvent(.pendingHubGrantsChanged)
            }
            if snapshot.pendingSkillApprovalCount > 0 {
                XTPerformanceTrace.event("XT Supervisor Lean Auto Open", "pending_skill_approvals")
                performLightHeaderLifecycleEvent(.pendingSkillApprovalsChanged)
            }
        }
    }

    private func cancelLeanSupervisorAutoOpen() {
        leanSupervisorAutoOpenTask?.cancel()
        leanSupervisorAutoOpenTask = nil
    }

    private func performLightHeaderAction(_ action: SupervisorHeaderAction) {
        SupervisorViewActionSupport.performHeaderAction(
            action,
            context: lightweightHeaderContext,
            dependencies: lightHeaderEffectDependencies
        )
    }

    private func performLightHeaderLifecycleEvent(_ event: SupervisorHeaderLifecycleEvent) {
        SupervisorViewActionSupport.performHeaderLifecycleEvent(
            event,
            context: lightweightHeaderContext,
            dependencies: lightHeaderEffectDependencies
        )
    }

    private var lightHeaderEffectDependencies: SupervisorViewHeaderEffects.Dependencies {
        SupervisorViewActionSupport.headerEffectDependencies(
            setHeartbeatFeedVisible: { ui.showHeartbeatFeed = $0 },
            setSignalCenterVisible: { ui.showSignalCenter = $0 },
            focusSignalCenterOverview: { action in
                switch action {
                case .scrollToBoard(let anchorID):
                    appModel.requestSupervisorBoardFocus(anchorID: anchorID)
                }
            },
            setWindowSheet: openDetachedSupervisorToolWindow,
            clearRequestedWindowSheet: { supervisor.clearRequestedWindowSheet() },
            clearConversation: { supervisor.clearMessages() },
            setHeartbeatScale: { ui.heartbeatIconScale = $0 }
        )
    }

    private func openDetachedSupervisorToolWindow(
        _ sheet: SupervisorManager.SupervisorWindowSheet?
    ) {
        ui.activeWindowSheet = nil
        guard let sheet else { return }
        openWindow(id: sheet.windowID)
    }

    private func requestConversationFocus() {
        ui.conversationFocusRequestID += 1
    }

    private func triggerLightBigTaskFlow(_ candidate: SupervisorBigTaskCandidate) {
        Task { @MainActor in
            let selectedProject = SupervisorViewStateSupport.selectedAutomationProject(appModel: appModel)
            let selectedTemplate = selectedProject.map {
                appModel.governanceTemplatePreview(for: $0)
            }
            await SupervisorViewActionSupport.triggerBigTaskFlow(
                candidate,
                selectedProject: selectedProject,
                selectedProjectTemplate: selectedTemplate,
                setDismissedFingerprint: { ui.dismissedBigTaskFingerprint = $0 },
                setInputText: { ui.inputText = $0 },
                prepareOneShotControlPlane: { submission in
                    await supervisor.prepareOneShotControlPlane(submission: submission)
                },
                sendMessage: { supervisor.sendMessage($0) },
                requestConversationFocus: requestConversationFocus
            )
        }
    }

    private func handleLightVoiceCallAction() {
        if supervisor.voiceCallModeActive {
            supervisor.stopHandsFreeVoiceConversation()
            return
        }
        if supervisor.voiceCallEntryPreflight?.blocksStart == true {
            performLightVoiceRepairAction()
            return
        }
        Task { @MainActor in
            let started = await supervisor.startHandsFreeVoiceConversation()
            if started {
                requestConversationFocus()
                return
            }
            if supervisor.voiceCallEntryPreflight?.blocksStart == true {
                performLightVoiceRepairAction()
            }
        }
    }

    private func performLightVoiceRepairAction() {
        guard let preflight = supervisor.voiceCallEntryPreflight else { return }
        guard let destination = preflight.repairDestination else {
            openLightVoiceRepairURLFallback()
            return
        }

        let detail: String? = {
            let trimmed = preflight.detail.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }()
        let plan = SupervisorConversationRepairActionPlanner.plan(for: destination)

        switch plan.action {
        case .openXTSettings(let sectionId):
            appModel.requestSettingsFocus(
                sectionId: sectionId,
                title: preflight.headline,
                detail: detail
            )
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        case .openSupervisorControlCenter(let sheet):
            if sheet == .modelSettings {
                appModel.requestModelSettingsFocus(
                    title: preflight.headline,
                    detail: detail
                )
            }
            supervisor.requestSupervisorWindow(
                sheet: sheet,
                reason: "voice_call_entry_repair",
                focusConversation: false,
                startConversation: false
            )
        case .openHubSetup(let sectionId):
            appModel.requestHubSetupFocus(
                sectionId: sectionId,
                title: preflight.headline,
                detail: detail
            )
            openWindow(id: "hub_setup")
        case .openHubProviderKeys:
            if !appModel.openRELFlowHubProviderKeysSettings() {
                appModel.requestHubSetupFocus(
                    sectionId: "troubleshoot",
                    title: preflight.headline,
                    detail: detail
                )
                openWindow(id: "hub_setup")
            }
        case .openSystemPrivacy(let target):
            XTSystemSettingsLinks.openPrivacy(target)
        case .focusSupervisor:
            NSApp.activate(ignoringOtherApps: true)
            requestConversationFocus()
        }
    }

    private func openLightVoiceRepairURLFallback() {
        guard let raw = supervisor.voiceCallEntryPreflight?.actionURL,
              let url = URL(string: raw) else {
            return
        }
        openURL(url)
    }

    private func uiBinding<Value>(
        _ keyPath: ReferenceWritableKeyPath<SupervisorViewUIState, Value>
    ) -> Binding<Value> {
        Binding(
            get: { ui[keyPath: keyPath] },
            set: { ui[keyPath: keyPath] = $0 }
        )
    }
}

private struct SupervisorObservedFullPresentation: View {
    @ObservedObject var supervisor: SupervisorManager
    @ObservedObject var ui: SupervisorViewUIState
    let appModel: AppModel
    let openWindow: OpenWindowAction
    let openURL: OpenURLAction

    private var screenModel: SupervisorViewStateSupport.ScreenModel {
        SupervisorViewStateSupport.screenModel(
            appModel: appModel,
            supervisor: supervisor,
            inputText: ui.inputText,
            showHeartbeatFeed: ui.showHeartbeatFeed,
            showSignalCenter: ui.showSignalCenter,
            dismissedFingerprint: ui.dismissedBigTaskFingerprint,
            selectedPortfolioProjectID: ui.selectedPortfolioProjectID,
            selectedPortfolioDrillDownScope: ui.selectedPortfolioDrillDownScope,
            highlightedPendingSkillApprovalAnchor: ui.highlightedPendingSupervisorSkillApprovalAnchor,
            highlightedPendingHubGrantAnchor: ui.highlightedPendingHubGrantAnchor,
            highlightedCandidateReviewAnchor: ui.highlightedSupervisorCandidateReviewAnchor,
            laneHealthFilter: ui.laneHealthFilter,
            focusedSplitLaneID: ui.focusedSplitLaneID
        )
    }

    private var adapter: SupervisorViewAdapter {
        let model = screenModel
        let interactionCoordinator = SupervisorViewInteractionCoordinator(
            supervisor: supervisor,
            ui: ui,
            appModel: appModel,
            screenModel: model,
            openWindow: openWindow,
            openURL: openURL
        )
        return SupervisorViewAdapter(
            supervisor: supervisor,
            ui: ui,
            appModel: appModel,
            screenModel: model,
            interactionCoordinator: interactionCoordinator
        )
    }

    var body: some View {
        let adapter = self.adapter
        return GeometryReader { proxy in
            SupervisorViewContent(
                props: adapter.contentProps(
                    totalWidth: proxy.size.width,
                    totalHeight: proxy.size.height
                ),
                bindings: adapter.contentBindings,
                callbacks: adapter.contentCallbacks
            )
        }
        .onAppear {
            XTPerformanceTrace.event("XT Supervisor Full Appeared")
        }
        .modifier(
            SupervisorViewLifecycleAttachments(
                bindings: adapter.lifecycleBindings,
                props: adapter.lifecycleProps,
                callbacks: adapter.lifecycleCallbacks
            )
        )
    }
}

private struct SupervisorConversationWarmupView: View {
    var body: some View {
        VStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text("正在准备 Supervisor 对话")
                .font(.headline)
            Text("总控已打开，对话列表稍后挂载。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            XTPerformanceTrace.event("XT Supervisor Conversation Warmup Appeared")
        }
    }
}

private struct SupervisorInactiveSurfacePlaceholder: View {
    var body: some View {
        Color.clear
            .frame(minWidth: 800, minHeight: 600)
    }
}
