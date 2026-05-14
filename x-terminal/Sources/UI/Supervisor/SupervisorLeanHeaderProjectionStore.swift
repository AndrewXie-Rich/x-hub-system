import Combine
import Foundation

struct SupervisorLeanHeaderProjectionSnapshot: Equatable {
    var configuredModelId: String
    var executionSnapshot: AXRoleExecutionSnapshot
    var latestRuntimeActivityText: String?
    var context: SupervisorHeaderControls.Context
    var voiceStatus: SupervisorHeaderVoiceStatusPresentation
    var isProcessing: Bool
    var processingStatusText: String?
    var latestUserMessageContent: String?
    var selectedProject: AXProjectEntry?
    var selectedProjectTemplate: AXProjectGovernanceTemplatePreview?
    var focusRequestNonce: Int?

    static let empty = SupervisorLeanHeaderProjectionSnapshot(
        configuredModelId: "",
        executionSnapshot: AXRoleExecutionSnapshot.empty(role: .supervisor, source: "supervisor_lean_header"),
        latestRuntimeActivityText: nil,
        context: SupervisorHeaderControls.Context(
            hasFocusRequest: false,
            pendingHubGrantCount: 0,
            pendingSkillApprovalCount: 0,
            hasLatestHeartbeat: false,
            highestHeartbeatPriority: nil,
            heartbeatOverview: nil,
            hasLatestRuntimeActivity: false,
            signalCenterOverview: nil,
            isHeartbeatFeedVisible: false,
            isSignalCenterVisible: false,
            requestedWindowSheet: nil
        ),
        voiceStatus: .empty(),
        isProcessing: false,
        processingStatusText: nil,
        latestUserMessageContent: nil,
        selectedProject: nil,
        selectedProjectTemplate: nil,
        focusRequestNonce: nil
    )

    var pendingHubGrantCount: Int {
        context.pendingHubGrantCount
    }

    var pendingSkillApprovalCount: Int {
        context.pendingSkillApprovalCount
    }

    var requestedWindowSheetID: String? {
        context.requestedWindowSheet?.id
    }

    func context(
        heartbeatFeedVisible: Bool,
        signalCenterVisible: Bool
    ) -> SupervisorHeaderControls.Context {
        var next = context
        next.isHeartbeatFeedVisible = heartbeatFeedVisible
        next.isSignalCenterVisible = signalCenterVisible
        return next
    }

    @MainActor
    static func make(
        supervisor: SupervisorManager,
        appModel: AppModel
    ) -> SupervisorLeanHeaderProjectionSnapshot {
        let selectedProject = SupervisorViewStateSupport.selectedAutomationProject(appModel: appModel)
        let selectedTemplate = selectedProject.map {
            appModel.governanceTemplatePreview(for: $0)
        }
        let heartbeatSummary = SupervisorHeartbeatPresentation.lightweightHeaderSummary(
            entries: supervisor.heartbeatHistory,
            historicalProjectBoundaryRepairStatusLine: appModel.historicalProjectBoundaryRepairStatusLine
        )
        let context = SupervisorHeaderControls.Context(
            hasFocusRequest: appModel.supervisorFocusRequest != nil,
            pendingHubGrantCount: supervisor.frontstagePendingHubGrants.count,
            pendingSkillApprovalCount: supervisor.frontstagePendingSupervisorSkillApprovals.count,
            hasLatestHeartbeat: supervisor.latestHeartbeat != nil,
            highestHeartbeatPriority: heartbeatSummary.highestPriority,
            heartbeatOverview: heartbeatSummary.overview,
            hasLatestRuntimeActivity: supervisor.latestRuntimeActivity != nil,
            signalCenterOverview: nil,
            isHeartbeatFeedVisible: false,
            isSignalCenterVisible: false,
            requestedWindowSheet: supervisor.requestedWindowSheet
        )

        return SupervisorLeanHeaderProjectionSnapshot(
            configuredModelId: SupervisorViewStateSupport.configuredSupervisorModelId(appModel: appModel),
            executionSnapshot: executionSnapshot(from: supervisor),
            latestRuntimeActivityText: supervisor.latestRuntimeActivity?.text,
            context: context,
            voiceStatus: SupervisorHeaderVoiceStatusPresentationMapper.map(
                replaySummary: supervisor.voiceReplaySummary,
                safetyReport: supervisor.voiceSafetyInvariantReport,
                callModeActive: supervisor.voiceCallModeActive,
                preflight: supervisor.voiceCallEntryPreflight,
                runtimeState: supervisor.voiceRuntimeState,
                routeDecision: supervisor.voiceRouteDecision,
                captureSource: supervisor.voiceCaptureSource
            ),
            isProcessing: supervisor.isProcessing,
            processingStatusText: supervisor.processingStatusText,
            latestUserMessageContent: latestUserMessageContent(from: supervisor),
            selectedProject: selectedProject,
            selectedProjectTemplate: selectedTemplate,
            focusRequestNonce: appModel.supervisorFocusRequest?.nonce
        )
    }

    @MainActor
    private static func latestUserMessageContent(
        from supervisor: SupervisorManager
    ) -> String? {
        supervisor.chatTimelineMessages.reversed()
            .first(where: { $0.role == .user })?
            .content
    }

    @MainActor
    private static func executionSnapshot(
        from supervisor: SupervisorManager
    ) -> AXRoleExecutionSnapshot {
        let mode = supervisor.lastSupervisorReplyExecutionMode
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let executionPath: String
        switch mode {
        case "remote_model":
            executionPath = "remote_model"
        case "hub_downgraded_to_local":
            executionPath = "hub_downgraded_to_local"
        case "local_fallback_after_remote_error":
            executionPath = "local_fallback_after_remote_error"
        case "local_preflight", "local_direct_reply", "local_direct_action", "hub_brief_projection":
            executionPath = mode
        default:
            executionPath = "no_record"
        }

        let runtimeProvider: String
        switch executionPath {
        case "remote_model":
            runtimeProvider = "Hub (Remote)"
        case "hub_downgraded_to_local", "local_fallback_after_remote_error", "local_runtime":
            runtimeProvider = "Hub (Local)"
        default:
            runtimeProvider = ""
        }

        return AXRoleExecutionSnapshots.snapshot(
            role: .supervisor,
            updatedAt: max(
                supervisor.lastSupervisorRemoteSuccessAt,
                supervisor.lastSupervisorRemoteFailureAt
            ),
            stage: "supervisor",
            requestedModelId: supervisor.lastSupervisorRequestedModelId,
            actualModelId: supervisor.lastSupervisorActualModelId,
            runtimeProvider: runtimeProvider,
            executionPath: executionPath,
            fallbackReasonCode: supervisor.lastSupervisorRemoteFailureReasonCode,
            source: "supervisor_lean_header"
        )
    }
}

@MainActor
final class SupervisorLeanHeaderProjectionStore: ObservableObject {
    @Published private(set) var snapshot: SupervisorLeanHeaderProjectionSnapshot

    private let minimumUpdateIntervalNanoseconds: UInt64
    private weak var boundSupervisor: SupervisorManager?
    private weak var boundAppModel: AppModel?
    private var cancellables: Set<AnyCancellable> = []
    private var settingsCancellable: AnyCancellable?
    private var updateScheduled = false
    private var lastUpdateNanoseconds = DispatchTime.now().uptimeNanoseconds

    init(
        snapshot: SupervisorLeanHeaderProjectionSnapshot = .empty,
        minimumUpdateIntervalNanoseconds: UInt64 = 0
    ) {
        self.snapshot = snapshot
        self.minimumUpdateIntervalNanoseconds = minimumUpdateIntervalNanoseconds
    }

    func bind(
        supervisor: SupervisorManager,
        appModel: AppModel
    ) {
        if boundSupervisor === supervisor,
           boundAppModel === appModel {
            update(supervisor: supervisor, appModel: appModel)
            return
        }

        cancellables.removeAll()
        settingsCancellable = nil
        boundSupervisor = supervisor
        boundAppModel = appModel
        updateScheduled = false
        update(supervisor: supervisor, appModel: appModel)
        bindSettingsStore(appModel.settingsStore, supervisor: supervisor, appModel: appModel)

        observe(supervisor.$messages, supervisor: supervisor, appModel: appModel)
        observe(supervisor.$heartbeatHistory, supervisor: supervisor, appModel: appModel)
        observe(supervisor.$runtimeActivityEntries, supervisor: supervisor, appModel: appModel)
        observe(supervisor.$requestedWindowSheet, supervisor: supervisor, appModel: appModel)
        observe(supervisor.$isProcessing, supervisor: supervisor, appModel: appModel)
        observe(supervisor.$processingStatusText, supervisor: supervisor, appModel: appModel)
        observe(supervisor.$pendingHubGrants, supervisor: supervisor, appModel: appModel)
        observe(supervisor.$pendingSupervisorSkillApprovals, supervisor: supervisor, appModel: appModel)
        observe(supervisor.$lastSupervisorReplyExecutionMode, supervisor: supervisor, appModel: appModel)
        observe(supervisor.$lastSupervisorRequestedModelId, supervisor: supervisor, appModel: appModel)
        observe(supervisor.$lastSupervisorActualModelId, supervisor: supervisor, appModel: appModel)
        observe(supervisor.$lastSupervisorRemoteFailureReasonCode, supervisor: supervisor, appModel: appModel)
        observe(supervisor.$lastSupervisorRemoteSuccessAt, supervisor: supervisor, appModel: appModel)
        observe(supervisor.$lastSupervisorRemoteFailureAt, supervisor: supervisor, appModel: appModel)
        observe(supervisor.$voiceReplaySummary, supervisor: supervisor, appModel: appModel)
        observe(supervisor.$voiceSafetyInvariantReport, supervisor: supervisor, appModel: appModel)
        observe(supervisor.$voiceCallModeActive, supervisor: supervisor, appModel: appModel)
        observe(supervisor.$voiceCallEntryPreflight, supervisor: supervisor, appModel: appModel)
        observe(supervisor.$voiceRuntimeState, supervisor: supervisor, appModel: appModel)
        observe(supervisor.$voiceRouteDecision, supervisor: supervisor, appModel: appModel)
        observe(supervisor.$voiceCaptureSource, supervisor: supervisor, appModel: appModel)
        observe(appModel.$supervisorFocusRequest, supervisor: supervisor, appModel: appModel)
        observe(appModel.$selectedProjectId, supervisor: supervisor, appModel: appModel)
        observe(appModel.$registry, supervisor: supervisor, appModel: appModel)
        observe(appModel.$historicalProjectBoundaryRepairStatusLine, supervisor: supervisor, appModel: appModel)

        appModel.$settingsStore
            .dropFirst()
            .sink { [weak self, weak supervisor, weak appModel] settingsStore in
                guard let self, let supervisor, let appModel else { return }
                self.bindSettingsStore(settingsStore, supervisor: supervisor, appModel: appModel)
                self.scheduleUpdate(supervisor: supervisor, appModel: appModel)
            }
            .store(in: &cancellables)
    }

    func isBound(
        supervisor: SupervisorManager,
        appModel: AppModel
    ) -> Bool {
        boundSupervisor === supervisor && boundAppModel === appModel
    }

    func unbind(resetSnapshot: Bool = true) {
        cancellables.removeAll()
        settingsCancellable = nil
        boundSupervisor = nil
        boundAppModel = nil
        updateScheduled = false
        if resetSnapshot, snapshot != .empty {
            snapshot = .empty
        }
    }

    private func bindSettingsStore(
        _ settingsStore: SettingsStore,
        supervisor: SupervisorManager,
        appModel: AppModel
    ) {
        settingsCancellable = settingsStore.$settings
            .dropFirst()
            .sink { [weak self, weak supervisor, weak appModel] _ in
                guard let supervisor, let appModel else { return }
                self?.scheduleUpdate(supervisor: supervisor, appModel: appModel)
            }
    }

    private func observe<P: Publisher>(
        _ publisher: P,
        supervisor: SupervisorManager,
        appModel: AppModel
    ) where P.Failure == Never {
        publisher
            .dropFirst()
            .sink { [weak self, weak supervisor, weak appModel] _ in
                guard let supervisor, let appModel else { return }
                self?.scheduleUpdate(supervisor: supervisor, appModel: appModel)
            }
            .store(in: &cancellables)
    }

    private func update(
        supervisor: SupervisorManager,
        appModel: AppModel
    ) {
        let nextSnapshot = SupervisorLeanHeaderProjectionSnapshot.make(
            supervisor: supervisor,
            appModel: appModel
        )
        guard snapshot != nextSnapshot else { return }
        lastUpdateNanoseconds = DispatchTime.now().uptimeNanoseconds
        snapshot = nextSnapshot
    }

    private func scheduleUpdate(
        supervisor: SupervisorManager,
        appModel: AppModel
    ) {
        guard !updateScheduled else { return }
        updateScheduled = true
        let delayNanoseconds = nextUpdateDelayNanoseconds()
        Task { @MainActor [weak self, weak supervisor, weak appModel] in
            if delayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: delayNanoseconds)
            }
            guard let self else { return }
            self.updateScheduled = false
            guard let supervisor,
                  let appModel,
                  self.boundSupervisor === supervisor,
                  self.boundAppModel === appModel else {
                return
            }
            self.update(supervisor: supervisor, appModel: appModel)
        }
    }

    private func nextUpdateDelayNanoseconds() -> UInt64 {
        guard minimumUpdateIntervalNanoseconds > 0 else { return 0 }
        let now = DispatchTime.now().uptimeNanoseconds
        let elapsed = now >= lastUpdateNanoseconds ? now - lastUpdateNanoseconds : minimumUpdateIntervalNanoseconds
        guard elapsed < minimumUpdateIntervalNanoseconds else { return 0 }
        return minimumUpdateIntervalNanoseconds - elapsed
    }
}
