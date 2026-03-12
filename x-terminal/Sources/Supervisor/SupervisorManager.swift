import Foundation
import Combine
import UniformTypeIdentifiers
import AppKit
import CryptoKit

@MainActor
final class SupervisorManager: ObservableObject {
    private enum SupervisorReplyExecutionMode: String {
        case idle
        case localPreflight = "local_preflight"
        case localDirectReply = "local_direct_reply"
        case localDirectAction = "local_direct_action"
        case remoteModel = "remote_model"
        case localFallbackAfterRemoteError = "local_fallback_after_remote_error"
    }

    static let shared = SupervisorManager()

    @Published var messages: [SupervisorMessage] = []
    @Published var isProcessing: Bool = false
    @Published private(set) var lastSupervisorReplyExecutionMode: String = SupervisorReplyExecutionMode.idle.rawValue
    @Published private(set) var lastSupervisorActualModelId: String = ""
    @Published var currentTask: SupervisorTask?
    @Published private(set) var oneShotNormalizationIssues: [OneShotNormalizationIssue] = []
    @Published private(set) var oneShotIntakeRequest: SupervisorOneShotIntakeRequest?
    @Published private(set) var oneShotAdaptivePoolPlan: AdaptivePoolPlanDecision?
    @Published private(set) var oneShotSeatGovernor: OneShotSeatGovernorDecision?
    @Published private(set) var oneShotRunState: OneShotRunStateSnapshot?
    @Published private(set) var oneShotPlannerExplain: [String] = []
    @Published private(set) var automationPreparedRun: XTAutomationPreparedRun?
    @Published private(set) var automationCurrentCheckpoint: XTAutomationRunCheckpoint?
    @Published private(set) var automationRecoveryDecision: XTAutomationRestartRecoveryDecision?
    @Published private(set) var automationLatestExecutionReport: XTAutomationRunExecutionReport?
    @Published private(set) var automationLatestRetryPackage: XTAutomationRetryPackage?
    @Published private(set) var automationStatusLine: String = "automation runtime: idle"

    private let eventBus = AXEventBus.shared
    private let hubClient = HubAIClient.shared
    private let modelManager = HubModelManager.shared
    private let sessionManager = AXSessionManager.shared
    private var appModel: AppModel?
    private let oneShotIntakeCoordinator = OneShotIntakeCoordinator()
    private let oneShotAdaptivePoolPlanner = AdaptivePoolPlanner()
    private let oneShotTaskDecomposer = TaskDecomposer()
    private let oneShotRunStateStore = OneShotRunStateStore()
    private var oneShotPreparedSplitBuildResult: SplitProposalBuildResult?
    private var automationRunCoordinator = XTAutomationRunCoordinator()
    private var automationRunExecutor = XTAutomationRunExecutor()
    private var automationExecutionTask: Task<Void, Never>?
    private var automationAutoRetryTask: Task<Void, Never>?
    private var automationExternalTriggerReplayLedger: [String: TimeInterval] = [:]
    private var automationExternalTriggerAcceptedLedger: [String: TimeInterval] = [:]
    private var automationExternalTriggerHistoryLoadedProjects: Set<String> = []

    private var cancellables = Set<AnyCancellable>()
    private var appModelCancellables = Set<AnyCancellable>()
    private var recentEvents: [String] = []
    private var actionLedger: [SupervisorActionLedgerEntry] = []
    private let actionLedgerMaxEntries = 80
    private var supervisorProjectCapsuleSyncAuditRefs: [String: String] = [:]
    private var supervisorPortfolioSnapshotSyncFingerprint: String = ""
    private var supervisorSkillExecutionTasks: [String: Task<Void, Never>] = [:]
    private let supervisorHubGrantPreflightEnabled: Bool
    private let supervisorEventLoopAutoFollowUpEnabled: Bool
    private var supervisorNetworkAccessRequestOverride: (@Sendable (URL, Int, String?) async -> HubIPCClient.NetworkAccessResult)?
    private var supervisorToolExecutorOverride: (@Sendable (ToolCall, URL) async throws -> ToolResult)?
    private var supervisorEventLoopResponseOverride: (@Sendable (String, String) async -> String)?
    private var supervisorEventLoopTask: Task<Void, Never>?
    private var pendingSupervisorEventLoopTrigger: SupervisorEventLoopTrigger?
    private var supervisorEventLoopRecentTriggerLedger: [String: TimeInterval] = [:]

    private var heartbeatTimer: Timer?
    private var lastHeartbeatSnapshot: String = ""
    private var lastHeartbeatAt: TimeInterval = 0
    private var heartbeatAutoProgressLedger: [String: TimeInterval] = [:]
    private let heartbeatIntervalSec: TimeInterval = 300
    private let projectPausedAfterIdleSec: TimeInterval = 300
    private let forceHeartbeatMinIntervalSec: TimeInterval = 15
    private let heartbeatAutoProgressCooldownSec: TimeInterval = 120
    private var schedulerPollTimer: Timer?
    private var schedulerSnapshot: HubIPCClient.SchedulerStatusSnapshot?
    private var pendingGrantSnapshot: HubIPCClient.PendingGrantSnapshot?
    private var connectorIngressSnapshot: HubIPCClient.ConnectorIngressSnapshot?
    private var schedulerLastRefreshAt: TimeInterval = 0
    private var schedulerLastSuccessAt: TimeInterval = 0
    private var schedulerRefreshInFlight = false
    private let schedulerPollIntervalSec: TimeInterval = 2.0
    private let schedulerSnapshotStaleSec: TimeInterval = 12.0
    private var pendingGrantLastSuccessAt: TimeInterval = 0
    private var connectorIngressLastSuccessAt: TimeInterval = 0
    @Published private(set) var pendingHubGrants: [SupervisorPendingGrant] = []
    @Published private(set) var pendingHubGrantSource: String = ""
    @Published private(set) var pendingHubGrantUpdatedAt: TimeInterval = 0
    @Published private(set) var hasFreshPendingHubGrantSnapshot: Bool = false
    @Published private(set) var pendingHubGrantActionsInFlight: Set<String> = []
    @Published private(set) var pendingSupervisorSkillApprovals: [SupervisorPendingSkillApproval] = []
    @Published private(set) var voiceRuntimeState: SupervisorVoiceRuntimeState = .idle
    @Published private(set) var voiceRouteDecision: VoiceRouteDecision = .unavailable
    @Published private(set) var voiceAuthorizationStatus: VoiceTranscriberAuthorizationStatus = .undetermined
    @Published private(set) var voiceActiveHealthReasonCode: String = ""
    @Published private(set) var voiceFunASRSidecarHealth: VoiceSidecarHealthSnapshot?
    @Published private(set) var voiceWakeProfileSnapshot: VoiceWakeProfileSnapshot = .empty
    @Published private(set) var voiceReadinessSnapshot: VoiceReadinessSnapshot = .empty
    @Published private(set) var conversationSessionSnapshot = SupervisorConversationSessionSnapshot.idle(
        policy: .default(),
        wakeMode: .pushToTalk,
        route: .manualText
    )
    @Published private(set) var voiceAuthorizationResolution: SupervisorVoiceAuthorizationResolution?
    @Published private(set) var activeVoiceChallenge: HubIPCClient.VoiceGrantChallengeSnapshot?
    @Published private(set) var supervisorIncidentLedger: [SupervisorLaneIncident] = []
    @Published private(set) var supervisorLaneHealthSnapshot: SupervisorLaneHealthSnapshot?
    @Published private(set) var supervisorLaneHealthStatusLine: String = "lane health: idle"
    @Published private(set) var lastSupervisorRequestedModelId: String = ""
    @Published private(set) var lastSupervisorRemoteFailureReasonCode: String = ""
    @Published private(set) var xtReadyIncidentEventsReportPath: String = ""
    @Published private(set) var xtReadyIncidentEventsAutoExportStatus: String = "idle"
    @Published private(set) var doctorReport: SupervisorDoctorReport?
    @Published private(set) var doctorSuggestionCards: [SupervisorDoctorSuggestionCard] = []
    @Published private(set) var doctorStatusLine: String = "未运行 Doctor 预检"
    @Published private(set) var doctorReportPath: String = ""
    @Published private(set) var doctorHasBlockingFindings: Bool = false
    @Published private(set) var releaseBlockedByDoctorWithoutReport: Int = 1
    @Published private(set) var blockerEscalationThreshold: Int = 3
    @Published private(set) var blockerEscalationCooldownSec: TimeInterval = 900
    @Published private(set) var supervisorMemoryStatusLine: String = "memory: idle"
    @Published private(set) var supervisorMemorySource: String = ""
    @Published private(set) var supervisorMemoryUpdatedAt: TimeInterval = 0
    @Published private(set) var supervisorMemoryPreview: String = ""
    @Published private(set) var supervisorMemoryProjectDigests: [SupervisorMemoryProjectDigest] = []
    @Published private(set) var supervisorSkillRegistrySnapshot: SupervisorSkillRegistrySnapshot?
    @Published private(set) var supervisorSkillRegistryStatusLine: String = "skills: no focused project"
    @Published private(set) var supervisorJurisdictionRegistry: SupervisorJurisdictionRegistry = SupervisorJurisdictionRegistryStore.load()
    @Published private(set) var supervisorPortfolioSnapshot: SupervisorPortfolioSnapshot = .empty
    @Published private(set) var supervisorProjectNotificationSnapshot: SupervisorProjectNotificationSnapshot = .empty
    @Published private(set) var supervisorLastProjectDrillDownSnapshot: SupervisorProjectDrillDownSnapshot?
    @Published private(set) var supervisorRecentProjectActionEvents: [SupervisorProjectActionEvent] = []
    private let heartbeatNotificationDedupeKey = "x_terminal_supervisor_heartbeat"
    private let supervisorProjectActionEventMaxEntries = 24
    private var supervisorProjectNotificationLastDeliveredAt: [String: TimeInterval] = [:]
    private var blockerStreakCount: Int = 0
    private var lastBlockerFingerprint: String = ""
    private var lastBlockerEscalationAt: TimeInterval = 0
    private var lastXTReadyIncidentAutoExportAt: TimeInterval = 0
    private let xtReadyIncidentAutoExportMinIntervalSec: TimeInterval = 0.8
    private var lastLaneHealthFingerprint: String = ""
    private let voiceSessionCoordinator = VoiceSessionCoordinator.shared
    private let voiceWakeProfileStore = VoiceWakeProfileStore.shared
    private let conversationSessionController: SupervisorConversationSessionController
    private let conversationWindowBridge = SupervisorConversationWindowBridge.shared
    private let supervisorSpeechSynthesizer: SupervisorSpeechSynthesizer
    private let backgroundSupervisorServicesEnabled: Bool
    private var voiceAuthorizationBridge = SupervisorVoiceAuthorizationBridge()
    private var preparedOneShotLaunchExecutorForTesting: ((SupervisorOneShotIntakeRequest, AdaptivePoolPlanDecision, SplitProposalBuildResult) async -> GuardedOneShotLaunchResumeOutcome)?
    private var activeVoiceAuthorizationRequest: SupervisorVoiceAuthorizationRequest?
    private var voiceAuthorizationInFlight = false

    private static let defaultsThreshold = 3
    private static let defaultsCooldownMinutes = 15
    private let escalationThresholdDefaultsKey = "xterminal_supervisor_blocker_escalation_threshold"
    private let escalationCooldownMinutesDefaultsKey = "xterminal_supervisor_blocker_escalation_cooldown_minutes"
    private let legacyEscalationThresholdDefaultsKey = "xterminal_supervisor_blocker_escalation_threshold"
    private let legacyEscalationCooldownMinutesDefaultsKey = "xterminal_supervisor_blocker_escalation_cooldown_minutes"
    private let automationAutoRetryTrigger = "automatic"
    private let automationManualRetryTrigger = "manual_recover"
    private let automationAutoRetryEligibleHoldReasons: Set<String> = [
        "automation_verify_failed",
        "automation_verify_execution_error",
        "automation_patch_check_failed",
        "automation_action_failed",
        "automation_action_execution_error",
    ]

    private struct SupervisorMemoryBuildInfo {
        var text: String
        var source: String
        var updatedAt: TimeInterval
        var projectDigests: [SupervisorMemoryProjectDigest]
        var skillRegistrySnapshot: SupervisorSkillRegistrySnapshot?
    }

    private struct SupervisorMemoryComposition {
        var constitution: String
        var canonical: String
        var observations: String
        var workingSet: String
        var rawEvidence: String
        var localText: String
        var projectDigests: [SupervisorMemoryProjectDigest]
        var skillRegistrySnapshot: SupervisorSkillRegistrySnapshot?
    }

    private struct SupervisorEventLoopTrigger {
        var userMessage: String
        var triggerSource: SupervisorCommandTriggerSource
        var dedupeKey: String
    }

    private struct SupervisorWorkflowMemorySlice {
        var canonical: String
        var observation: String
        var workingSet: String
    }

    struct SupervisorMemoryProjectDigest: Identifiable, Equatable {
        var projectId: String
        var displayName: String
        var runtimeState: String
        var source: String
        var goal: String
        var currentState: String
        var nextStep: String
        var blocker: String
        var updatedAt: Double
        var recentMessageCount: Int

        var id: String { projectId }
    }

    private struct SupervisorProjectDigestGovernanceContext {
        var specCapsule: SupervisorProjectSpecCapsule?
        var missingSpecFields: [SupervisorProjectSpecField]
        var hardDecisions: [SupervisorDecisionCategory: SupervisorDecisionTrackEvent]
        var backgroundShadowHint: String
        var updatedAt: TimeInterval
        var sourceTags: [String]
    }

    private struct XTReadyIncidentInjectSpec {
        var laneID: String
        var incidentCode: String
    }

    private struct ParsedAssignCommand {
        var projectRef: String?
        var role: AXRole
        var modelId: String
        var tag: String
    }

    private struct DirectModelAssignmentIntent {
        var appliesToAllProjects: Bool
        var projectRef: String?
        var role: AXRole
        var usedDefaultRole: Bool
        var modelId: String
        var sourceModelToken: String
    }

    private enum ModelTokenResolution {
        case resolved(String)
        case auto
        case ambiguous([HubModel])
        case inventoryUnavailable
        case notFound
    }

    private struct ParsedAutomationRuntimeCommand {
        enum Action {
            case help
            case status
            case start
            case recover
            case cancel
            case advance(XTAutomationRunState)
            case selfIterateStatus
            case selfIterateSet(Bool)
            case selfIterateMax(Int)
        }

        var action: Action
        var projectRef: String?
    }

    private struct AutomationRetryRevision {
        var planningMode: String
        var planningSummary: String
        var revisedActionGraph: [XTAutomationRecipeAction]?
        var revisedVerifyCommands: [String]?
        var additionalEvidenceRefs: [String]
    }

    private struct AutomationRetryPlanningMaterialization {
        var package: XTAutomationRetryPackage
        var planningArtifact: XTAutomationRetryPlanningArtifact?
        var recipeProposalArtifact: XTAutomationRecipeProposalArtifact?
    }

    private enum HubConnectorIngressResolution {
        case route(SupervisorAutomationExternalTriggerIngress)
        case failClosed(SupervisorAutomationExternalTriggerIngress, String)
    }

    struct SupervisorAutomationExternalTriggerIngress: Equatable, Sendable {
        var projectId: String
        var triggerId: String
        var triggerType: XTAutomationTriggerType
        var source: XTAutomationTriggerSource
        var payloadRef: String
        var dedupeKey: String
        var requiresGrant: Bool?
        var policyRef: String?
        var receivedAt: Date
        var ingressChannel: String

        init(
            projectId: String,
            triggerId: String,
            triggerType: XTAutomationTriggerType,
            source: XTAutomationTriggerSource,
            payloadRef: String,
            dedupeKey: String,
            requiresGrant: Bool? = nil,
            policyRef: String? = nil,
            receivedAt: Date = Date(),
            ingressChannel: String = "supervisor_bridge"
        ) {
            self.projectId = projectId
            self.triggerId = triggerId
            self.triggerType = triggerType
            self.source = source
            self.payloadRef = payloadRef
            self.dedupeKey = dedupeKey
            self.requiresGrant = requiresGrant
            self.policyRef = policyRef
            self.receivedAt = receivedAt
            self.ingressChannel = ingressChannel
        }
    }

    enum SupervisorAutomationExternalTriggerDecision: String, Equatable, Sendable {
        case run
        case drop
        case hold
        case failClosed = "fail_closed"
    }

    struct SupervisorAutomationExternalTriggerResult: Equatable, Sendable {
        var projectId: String
        var triggerId: String
        var triggerType: XTAutomationTriggerType
        var decision: SupervisorAutomationExternalTriggerDecision
        var reasonCode: String
        var runId: String?
        var auditRef: String
    }

    private enum ProjectReferenceResolution {
        case matched(AXProjectEntry)
        case ambiguous([AXProjectEntry])
        case notFound
    }

    private enum ProjectRuntimeState {
        case running
        case paused
        case blocked
    }

    enum GuardedOneShotLaunchResumeOutcome {
        case launched(LaneLaunchReport)
        case blocked(reason: String, report: LaneLaunchReport?)
        case failedClosed(reason: String)
    }

    private struct ModelAssignmentResult {
        var ok: Bool
        var reasonCode: String
        var message: String
    }

    private enum SupervisorCommandTriggerSource: String {
        case userTurn = "user_turn"
        case heartbeat
        case skillCallback = "skill_callback"
        case incident
        case externalTriggerIngress = "external_trigger_ingress"
        case grantResolution = "grant_resolution"
        case approvalResolution = "approval_resolution"

        static func parse(_ raw: String) -> SupervisorCommandTriggerSource {
            let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return SupervisorCommandTriggerSource(rawValue: normalized) ?? .userTurn
        }

        var defaultJobSource: SupervisorJobSource {
            switch self {
            case .userTurn:
                return .user
            case .heartbeat:
                return .heartbeat
            case .skillCallback:
                return .skillCallback
            case .incident:
                return .incident
            case .externalTriggerIngress:
                return .externalTrigger
            case .grantResolution:
                return .grantResolution
            case .approvalResolution:
                return .approvalResolution
            }
        }
    }

    private struct SupervisorCreateJobPayload: Codable {
        var projectRef: String?
        var goal: String
        var priority: String?
        var source: String?
        var currentOwner: String?

        enum CodingKeys: String, CodingKey {
            case projectRef = "project_ref"
            case goal
            case priority
            case source
            case currentOwner = "current_owner"
        }
    }

    private struct SupervisorUpsertPlanStepPayload: Codable {
        var stepId: String
        var title: String
        var kind: String?
        var status: String?
        var skillId: String?
        var currentOwner: String?
        var detail: String?

        enum CodingKeys: String, CodingKey {
            case stepId = "step_id"
            case title
            case kind
            case status
            case skillId = "skill_id"
            case currentOwner = "current_owner"
            case detail
        }
    }

    private struct SupervisorUpsertPlanPayload: Codable {
        var projectRef: String?
        var jobId: String
        var planId: String
        var currentOwner: String?
        var steps: [SupervisorUpsertPlanStepPayload]

        enum CodingKeys: String, CodingKey {
            case projectRef = "project_ref"
            case jobId = "job_id"
            case planId = "plan_id"
            case currentOwner = "current_owner"
            case steps
        }
    }

    private struct SupervisorCallSkillPayload: Codable {
        var projectRef: String?
        var jobId: String
        var stepId: String
        var skillId: String
        var payload: [String: JSONValue]?

        enum CodingKeys: String, CodingKey {
            case projectRef = "project_ref"
            case jobId = "job_id"
            case stepId = "step_id"
            case skillId = "skill_id"
            case payload
        }
    }

    private struct SupervisorCancelSkillPayload: Codable {
        var projectRef: String?
        var requestId: String
        var reason: String?

        enum CodingKeys: String, CodingKey {
            case projectRef = "project_ref"
            case requestId = "request_id"
            case reason
        }
    }

    private struct SupervisorJSONPayloadDecodeError: Error {
        var message: String
    }

    private struct SupervisorActionLedgerEntry: Codable {
        var id: String
        var createdAt: Double
        var action: String
        var targetRef: String
        var projectId: String?
        var projectName: String?
        var role: String?
        var modelId: String?
        var status: String
        var reasonCode: String
        var detail: String
        var verifiedAt: Double?
        var triggerSource: String?
    }

    private init(
        registerForEvents: Bool = true,
        backgroundSupervisorServicesEnabled: Bool = true,
        supervisorHubGrantPreflightEnabled: Bool = true,
        supervisorEventLoopAutoFollowUpEnabled: Bool = true,
        supervisorSpeechSynthesizer: SupervisorSpeechSynthesizer? = nil,
        conversationSessionController: SupervisorConversationSessionController? = nil
    ) {
        self.conversationSessionController = conversationSessionController ?? SupervisorConversationSessionController.shared
        self.supervisorSpeechSynthesizer = supervisorSpeechSynthesizer ?? SupervisorSpeechSynthesizer()
        self.backgroundSupervisorServicesEnabled = backgroundSupervisorServicesEnabled
        self.supervisorHubGrantPreflightEnabled = supervisorHubGrantPreflightEnabled
        self.supervisorEventLoopAutoFollowUpEnabled = supervisorEventLoopAutoFollowUpEnabled
        loadEscalationPolicyFromDefaults()
        loadActionLedgerFromDisk()
        bindVoiceRuntime()
        bindConversationSession()
        if registerForEvents {
            setupEventListeners()
        }
    }

    static func makeForTesting(
        enableSupervisorHubGrantPreflight: Bool = false,
        enableSupervisorEventLoopAutoFollowUp: Bool = false,
        supervisorSpeechSynthesizer: SupervisorSpeechSynthesizer? = nil,
        conversationSessionController: SupervisorConversationSessionController? = nil
    ) -> SupervisorManager {
        SupervisorManager(
            registerForEvents: false,
            backgroundSupervisorServicesEnabled: false,
            supervisorHubGrantPreflightEnabled: enableSupervisorHubGrantPreflight,
            supervisorEventLoopAutoFollowUpEnabled: enableSupervisorEventLoopAutoFollowUp,
            supervisorSpeechSynthesizer: supervisorSpeechSynthesizer,
            conversationSessionController: conversationSessionController
        )
    }

    var blockerEscalationCooldownMinutes: Int {
        Int(max(1, round(blockerEscalationCooldownSec / 60.0)))
    }

    func setBlockerEscalationThreshold(_ value: Int) {
        let normalized = normalizedEscalationThreshold(value)
        blockerEscalationThreshold = normalized
        UserDefaults.standard.set(normalized, forKey: escalationThresholdDefaultsKey)
        UserDefaults.standard.set(normalized, forKey: legacyEscalationThresholdDefaultsKey)
    }

    func setBlockerEscalationCooldownMinutes(_ value: Int) {
        let normalized = normalizedEscalationCooldownMinutes(value)
        blockerEscalationCooldownSec = Double(normalized) * 60.0
        UserDefaults.standard.set(normalized, forKey: escalationCooldownMinutesDefaultsKey)
        UserDefaults.standard.set(normalized, forKey: legacyEscalationCooldownMinutesDefaultsKey)
    }

    func resetBlockerEscalationPolicyToDefaults() {
        setBlockerEscalationThreshold(Self.defaultsThreshold)
        setBlockerEscalationCooldownMinutes(Self.defaultsCooldownMinutes)
    }

    func setAppModel(_ appModel: AppModel) {
        self.appModel = appModel
        appModelCancellables.removeAll()
        appModel.settingsStore.$settings
            .sink { [weak self] settings in
                self?.updateConversationSessionPolicy(using: settings.voice)
                self?.refreshWakeProfileStatus()
                self?.refreshVoiceReadinessSnapshot()
            }
            .store(in: &appModelCancellables)
        appModel.$hubConnected
            .sink { [weak self] _ in
                self?.refreshWakeProfileStatus()
                self?.refreshVoiceReadinessSnapshot()
            }
            .store(in: &appModelCancellables)
        appModel.$hubRemoteConnected
            .sink { [weak self] _ in
                self?.refreshWakeProfileStatus()
                self?.refreshVoiceReadinessSnapshot()
            }
            .store(in: &appModelCancellables)
        appModel.$hubRemoteRoute
            .sink { [weak self] _ in
                self?.refreshWakeProfileStatus()
                self?.refreshVoiceReadinessSnapshot()
            }
            .store(in: &appModelCancellables)
        appModel.$hubRemoteLinking
            .sink { [weak self] _ in
                self?.refreshWakeProfileStatus()
                self?.refreshVoiceReadinessSnapshot()
            }
            .store(in: &appModelCancellables)
        appModel.$hubPairingPort
            .sink { [weak self] _ in self?.refreshVoiceReadinessSnapshot() }
            .store(in: &appModelCancellables)
        appModel.$hubGrpcPort
            .sink { [weak self] _ in self?.refreshVoiceReadinessSnapshot() }
            .store(in: &appModelCancellables)
        appModel.$hubInternetHost
            .sink { [weak self] _ in self?.refreshVoiceReadinessSnapshot() }
            .store(in: &appModelCancellables)
        appModel.$runtimeStatus
            .sink { [weak self] _ in self?.refreshVoiceReadinessSnapshot() }
            .store(in: &appModelCancellables)
        appModel.$modelsState
            .sink { [weak self] _ in self?.refreshVoiceReadinessSnapshot() }
            .store(in: &appModelCancellables)
        appModel.$bridgeAlive
            .sink { [weak self] _ in self?.refreshVoiceReadinessSnapshot() }
            .store(in: &appModelCancellables)
        appModel.$bridgeEnabled
            .sink { [weak self] _ in self?.refreshVoiceReadinessSnapshot() }
            .store(in: &appModelCancellables)
        appModel.$selectedProjectId
            .sink { [weak self] _ in self?.refreshVoiceReadinessSnapshot() }
            .store(in: &appModelCancellables)
        appModel.$registry
            .sink { [weak self] _ in
                guard let self else { return }
                self.rebuildPendingSupervisorSkillApprovalViewState()
                Task { @MainActor in
                    await self.refreshSupervisorMemorySnapshot(reason: "registry_changed")
                }
            }
            .store(in: &appModelCancellables)
        updateConversationSessionPolicy(using: appModel.settingsStore.settings.voice)
        refreshWakeProfileStatus()
        refreshVoiceReadinessSnapshot()
        if backgroundSupervisorServicesEnabled {
            restartHeartbeatTimer()
            restartSchedulerPollTimer()
            Task { @MainActor in
                await refreshSchedulerSnapshot(force: true)
            }
        }
        _ = runSupervisorDoctorPreflight(reason: "app_model_attached", emitSystemMessage: false)
        if backgroundSupervisorServicesEnabled {
            emitHeartbeatIfNeeded(force: true, reason: "app_model_attached")
        }
        rebuildPendingSupervisorSkillApprovalViewState()
        Task { @MainActor in
            await refreshSupervisorMemorySnapshot(reason: "app_model_attached")
        }
    }

    private func setupEventListeners() {
        eventBus.eventPublisher
            .sink { [weak self] event in
                self?.handleEvent(event)
            }
            .store(in: &cancellables)
    }

    private func bindVoiceRuntime() {
        voiceRuntimeState = voiceSessionCoordinator.runtimeState
        voiceRouteDecision = voiceSessionCoordinator.routeDecision
        voiceAuthorizationStatus = voiceSessionCoordinator.authorizationStatus
        voiceActiveHealthReasonCode = voiceSessionCoordinator.activeHealthReasonCode ?? ""
        voiceFunASRSidecarHealth = voiceSessionCoordinator.funASRSidecarHealth
        voiceWakeProfileSnapshot = voiceWakeProfileStore.snapshot
        updateConversationSessionPolicy(using: currentVoicePreferences())

        voiceWakeProfileStore.$snapshot
            .sink { [weak self] snapshot in
                self?.voiceWakeProfileSnapshot = snapshot
                self?.updateConversationSessionPolicy(using: self?.currentVoicePreferences() ?? .default())
                self?.refreshVoiceReadinessSnapshot()
            }
            .store(in: &cancellables)

        voiceSessionCoordinator.$runtimeState
            .sink { [weak self] state in
                self?.voiceRuntimeState = state
                if state.state == .failClosed {
                    self?.conversationSessionController.registerRouteFailClosed(reasonCode: state.reasonCode)
                }
                self?.refreshVoiceReadinessSnapshot()
            }
            .store(in: &cancellables)

        voiceSessionCoordinator.$routeDecision
            .sink { [weak self] decision in
                self?.voiceRouteDecision = decision
                self?.updateConversationSessionPolicy(using: self?.currentVoicePreferences() ?? .default())
                self?.refreshVoiceReadinessSnapshot()
            }
            .store(in: &cancellables)

        voiceSessionCoordinator.$authorizationStatus
            .sink { [weak self] status in
                self?.voiceAuthorizationStatus = status
                self?.refreshVoiceReadinessSnapshot()
            }
            .store(in: &cancellables)

        voiceSessionCoordinator.$activeHealthReasonCode
            .sink { [weak self] reason in
                self?.voiceActiveHealthReasonCode = reason ?? ""
                self?.refreshVoiceReadinessSnapshot()
            }
            .store(in: &cancellables)

        voiceSessionCoordinator.$funASRSidecarHealth
            .sink { [weak self] snapshot in
                self?.voiceFunASRSidecarHealth = snapshot
                self?.refreshVoiceReadinessSnapshot()
            }
            .store(in: &cancellables)

        voiceSessionCoordinator.$lastWakeEvent
            .compactMap { $0 }
            .sink { [weak self] event in
                self?.conversationSessionController.configure(route: event.route)
                self?.conversationSessionController.registerWakeHit(
                    now: Date(timeIntervalSince1970: event.timestamp)
                )
                self?.conversationWindowBridge.requestOpen(reason: event.phrase)
            }
            .store(in: &cancellables)
    }

    private func bindConversationSession() {
        conversationSessionSnapshot = conversationSessionController.snapshot

        conversationSessionController.$snapshot
            .sink { [weak self] snapshot in
                self?.conversationSessionSnapshot = snapshot
                self?.refreshVoiceReadinessSnapshot()
            }
            .store(in: &cancellables)
    }

    private func updateConversationSessionPolicy(using preferences: VoiceRuntimePreferences) {
        conversationSessionController.configure(
            policy: .default(),
            wakeMode: resolvedConversationWakeMode(for: preferences),
            route: voiceRouteDecision.route
        )
    }

    private func resolvedConversationWakeMode(for preferences: VoiceRuntimePreferences) -> VoiceWakeMode {
        if preferences.wakeMode == .pushToTalk {
            return .pushToTalk
        }
        return voiceWakeProfileSnapshot.effectiveWakeMode
    }

    private func currentVoicePreferences() -> VoiceRuntimePreferences {
        appModel?.settingsStore.settings.voice ?? .default()
    }

    private func currentWakeProfilePairingReady() -> Bool {
        guard let appModel else { return false }
        return appModel.hubConnected || appModel.hubRemoteConnected
    }

    private func refreshWakeProfileStatus() {
        let preferences = currentVoicePreferences()
        voiceWakeProfileStore.applyPreferences(preferences)
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.voiceWakeProfileStore.refresh(pairingReady: self.currentWakeProfilePairingReady())
        }
    }

    func openConversationSession(openedBy: SupervisorConversationOpenedBy = .manualButton) {
        switch openedBy {
        case .manualButton:
            conversationSessionController.manualOpen()
        case .wakePhrase, .promptPhrase:
            conversationSessionController.registerWakeHit()
        case .voiceReplyFollowup:
            conversationSessionController.registerAssistantTurn(spoken: true)
        }
    }

    func endConversationSession(reasonCode: String = "manual_close") {
        conversationSessionController.endConversation(reasonCode: reasonCode)
    }

    private func speakSupervisorVoiceAuthorizationUpdate(
        resolution: SupervisorVoiceAuthorizationResolution,
        challengeToken: String
    ) {
        let stateToken = resolution.state.rawValue
        let detailToken = resolution.denyCode ?? resolution.reasonCode ?? "none"
        let script = conciseVoiceAuthorizationScript(
            resolution: resolution,
            challengeToken: challengeToken
        )
        let job = SupervisorVoiceTTSJob(
            trigger: .authorization,
            priority: resolution.state == .verified ? .normal : .interrupt,
            script: [script],
            dedupeKey: "voice_auth:\(stateToken):\(challengeToken):\(detailToken)"
        )
        _ = supervisorSpeechSynthesizer.speak(
            job: job,
            preferences: currentVoicePreferences()
        )
    }

    private func conciseVoiceAuthorizationScript(
        resolution: SupervisorVoiceAuthorizationResolution,
        challengeToken: String
    ) -> String {
        switch resolution.state {
        case .pending:
            return "Voice authorization challenge issued. Challenge \(challengeToken)."
        case .escalatedToMobile:
            return "Voice authorization requires mobile confirmation. Challenge \(challengeToken)."
        case .verified:
            return "Voice authorization verified. Challenge \(challengeToken)."
        case .denied:
            let deny = resolution.denyCode ?? "denied"
            return "Voice authorization denied. Reason \(deny)."
        case .failClosed:
            let reason = resolution.reasonCode ?? "unknown"
            return "Voice authorization failed closed. Reason \(reason)."
        }
    }

    func handleEvent(_ event: AXEvent) {
        var forceHeartbeat = false
        var heartbeatReason = "event"
        switch event {
        case .projectCreated(let entry):
            let portfolioEvent = SupervisorPortfolioSnapshotBuilder.makeActionEvent(from: entry, kind: .created)
            if supervisorJurisdictionRegistry.allowsEventVisibility(portfolioEvent) {
                let text = "新增项目：\(entry.displayName)"
                appendRecentEvent(text)
                appendProjectActionEvent(portfolioEvent)
                deliverProjectActionNotificationIfNeeded(portfolioEvent)
            }
            Task { @MainActor in
                await refreshSupervisorMemorySnapshot(reason: "project_created")
            }
            forceHeartbeat = true
            heartbeatReason = "project_created"
        case .projectUpdated(let entry):
            let portfolioEvent = SupervisorPortfolioSnapshotBuilder.makeActionEvent(from: entry, kind: .updated)
            if supervisorJurisdictionRegistry.allowsEventVisibility(portfolioEvent) {
                appendRecentEvent(portfolioEvent.actionTitle)
                appendProjectActionEvent(portfolioEvent)
                deliverProjectActionNotificationIfNeeded(portfolioEvent)
            }
            Task { @MainActor in
                await refreshSupervisorMemorySnapshot(reason: "project_updated")
            }
            forceHeartbeat = true
            heartbeatReason = "project_updated"
        case .projectRemoved(let entry):
            let portfolioEvent = SupervisorPortfolioSnapshotBuilder.makeActionEvent(from: entry, kind: .removed)
            if supervisorJurisdictionRegistry.allowsEventVisibility(portfolioEvent) {
                let text = "移除项目：\(entry.displayName)"
                appendRecentEvent(text)
                appendProjectActionEvent(portfolioEvent)
                deliverProjectActionNotificationIfNeeded(portfolioEvent)
            }
            Task { @MainActor in
                await refreshSupervisorMemorySnapshot(reason: "project_removed")
            }
            forceHeartbeat = true
            heartbeatReason = "project_removed"
        case .sessionCreated(let info):
            let text = "创建了新会话：\(info.title)"
            appendRecentEvent(text)
            addSystemMessage(text)
        case .sessionUpdated(let info):
            let text = "更新了会话：\(info.title)"
            appendRecentEvent(text)
            addSystemMessage(text)
        case .messageCreated(let sessionId, _):
            let text = "项目 \(sessionId) 收到新消息"
            appendRecentEvent(text)
            addSystemMessage(text)
            Task { @MainActor in
                await refreshSupervisorMemorySnapshot(reason: "message_created")
            }
        case .toolCallCreated(let sessionId, let toolCall):
            let text = "项目 \(sessionId) 执行工具：\(toolCall.tool.rawValue)"
            appendRecentEvent(text)
            addSystemMessage(text)
            Task { @MainActor in
                await refreshSupervisorMemorySnapshot(reason: "tool_call_created")
            }
        case .supervisorIncident(let incident):
            appendSupervisorIncident(incident)
            let projectText = incident.projectID?.uuidString ?? "n/a"
            let text = "泳道 \(incident.laneID) 事件：\(incident.incidentCode) -> \(incident.proposedAction.rawValue) (deny=\(incident.denyCode), latency=\(incident.takeoverLatencyMs ?? -1)ms, project=\(projectText))"
            appendRecentEvent(text)
            if incident.severity == .high || incident.severity == .critical || incident.requiresUserAck {
                addSystemMessage("🚧 \(text)\n审计: \(incident.auditRef)")
                pushSupervisorIncidentNotification(incident)
            }
            forceHeartbeat = true
            heartbeatReason = "incident_handled"
        case .supervisorLaneHealth(let snapshot):
            let changed = applySupervisorLaneHealthSnapshot(snapshot)
            if changed {
                let summary = snapshot.summary
                let text = "lane 健康态：running=\(summary.running), blocked=\(summary.blocked), stalled=\(summary.stalled), failed=\(summary.failed)"
                appendRecentEvent(text)
                forceHeartbeat = true
                heartbeatReason = "lane_health_changed"
            }
        default:
            break
        }
        emitHeartbeatIfNeeded(force: forceHeartbeat, reason: heartbeatReason)
    }

    func sendMessage(_ text: String, fromVoice: Bool = false) {
        let message = SupervisorMessage(
            id: UUID().uuidString,
            role: .user,
            content: text,
            isVoice: fromVoice,
            timestamp: Date().timeIntervalSince1970
        )
        messages.append(message)
        conversationSessionController.registerUserTurn(fromVoice: fromVoice)

        isProcessing = true

        Task {
            await processUserMessage(text, fromVoice: fromVoice)
        }
    }

    private func processUserMessage(_ text: String, fromVoice: Bool) async {
        defer {
            isProcessing = false
            drainPendingSupervisorEventLoopIfNeeded()
        }

        if let local = await handleLocalPreflightCommand(text) {
            recordSupervisorReplyExecution(mode: .localPreflight, actualModelId: nil)
            let assistantMessage = SupervisorMessage(
                id: UUID().uuidString,
                role: .assistant,
                content: local,
                isVoice: false,
                timestamp: Date().timeIntervalSince1970
            )
            messages.append(assistantMessage)
            let spokenOutcome = fromVoice ? speakSupervisorVoiceReply(local) : .suppressed("not_voice_triggered")
            conversationSessionController.registerAssistantTurn(spoken: spokenOutcome == .spoken)
            return
        }

        let response = await generateSupervisorResponse(text, triggerSource: .userTurn)

        let assistantMessage = SupervisorMessage(
            id: UUID().uuidString,
            role: .assistant,
            content: response,
            isVoice: false,
            timestamp: Date().timeIntervalSince1970
        )

        messages.append(assistantMessage)
        let spokenOutcome = fromVoice ? speakSupervisorVoiceReply(response) : .suppressed("not_voice_triggered")
        conversationSessionController.registerAssistantTurn(spoken: spokenOutcome == .spoken)
    }

    private func generateSupervisorResponse(
        _ userMessage: String,
        triggerSource: SupervisorCommandTriggerSource = .userTurn
    ) async -> String {
        let projects = allProjects()
        if let directReply = directSupervisorReplyIfApplicable(userMessage, projects: projects) {
            recordSupervisorReplyExecution(mode: .localDirectReply, actualModelId: nil)
            return directReply
        }
        if let directAction = directSupervisorActionIfApplicable(userMessage, projects: projects) {
            recordSupervisorReplyExecution(mode: .localDirectAction, actualModelId: nil)
            return directAction
        }

        await refreshSchedulerSnapshot(force: false)
        let preferredModel = modelManager.getPreferredModel(for: .supervisor)
        let memoryInfo = await buildSupervisorMemoryV1(userMessage: userMessage)
        publishSupervisorMemoryInfo(memoryInfo)
        let prompt = buildSupervisorSystemPrompt(
            userMessage: userMessage,
            projects: projects,
            preferredModel: preferredModel,
            memoryInfo: memoryInfo
        )

        do {
            let rid = try await hubClient.enqueueGenerate(
                prompt: prompt,
                taskType: "supervisor",
                preferredModelId: preferredModel,
                explicitModelId: nil,
                appId: "x_terminal_supervisor",
                maxTokens: 2048,
                temperature: 0.7,
                topP: 0.95,
                autoLoad: true
            )

            var response = ""
            var actualModelId: String?
            for try await ev in await hubClient.streamResponse(reqId: rid, timeoutSec: 300.0) {
                if ev.type == "delta", let t = ev.text {
                    response += t
                }
                let modelId = ev.model_id?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !modelId.isEmpty {
                    actualModelId = modelId
                }
            }

            if let strictFailure = strictSupervisorRemoteModelMismatchResponse(
                preferredModelId: preferredModel,
                actualModelId: actualModelId
            ) {
                recordSupervisorReplyExecution(
                    mode: .remoteModel,
                    actualModelId: actualModelId,
                    requestedModelId: preferredModel,
                    failureReasonCode: nil
                )
                return strictFailure
            }

            let sanitizedResponse = sanitizeSupervisorRemoteResponse(
                response,
                userMessage: userMessage,
                projects: projects
            )
            if sanitizedResponse != response {
                recordSupervisorReplyExecution(
                    mode: .localFallbackAfterRemoteError,
                    actualModelId: actualModelId,
                    requestedModelId: preferredModel,
                    failureReasonCode: "sanitized_remote_response"
                )
                return sanitizedResponse
            }

            let processedResponse = processSupervisorCommands(
                sanitizedResponse,
                userMessage: userMessage,
                triggerSource: triggerSource
            )
            if processedResponse.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty {
                recordSupervisorReplyExecution(
                    mode: .localFallbackAfterRemoteError,
                    actualModelId: nil,
                    requestedModelId: preferredModel,
                    failureReasonCode: "empty_remote_response"
                )
                return generateFallbackResponse(userMessage)
            }
            recordSupervisorReplyExecution(
                mode: .remoteModel,
                actualModelId: actualModelId,
                requestedModelId: preferredModel,
                failureReasonCode: nil
            )
            return processedResponse
        } catch {
            print("Supervisor AI error: \(error)")
            let failureContext = supervisorRemoteFailureContext(
                for: error,
                preferredModelId: preferredModel
            )
            recordSupervisorReplyExecution(
                mode: .localFallbackAfterRemoteError,
                actualModelId: nil,
                requestedModelId: failureContext.requestedModelId,
                failureReasonCode: failureContext.failureReasonCode
            )
            return renderSupervisorFailureResponse(error: error, userMessage: userMessage)
        }
    }

    private func queueSupervisorEventLoopTurn(
        userMessage: String,
        triggerSource: SupervisorCommandTriggerSource,
        dedupeKey: String
    ) {
        guard supervisorEventLoopAutoFollowUpEnabled || supervisorEventLoopResponseOverride != nil else { return }
        let normalizedMessage = userMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedKey = dedupeKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedMessage.isEmpty, !normalizedKey.isEmpty else { return }

        pruneSupervisorEventLoopTriggerLedger(now: Date().timeIntervalSince1970)
        if supervisorEventLoopRecentTriggerLedger[normalizedKey] != nil {
            return
        }
        supervisorEventLoopRecentTriggerLedger[normalizedKey] = Date().timeIntervalSince1970

        let trigger = SupervisorEventLoopTrigger(
            userMessage: normalizedMessage,
            triggerSource: triggerSource,
            dedupeKey: normalizedKey
        )
        if isProcessing || supervisorEventLoopTask != nil {
            pendingSupervisorEventLoopTrigger = trigger
            return
        }

        startSupervisorEventLoopTurn(trigger)
    }

    private func startSupervisorEventLoopTurn(_ trigger: SupervisorEventLoopTrigger) {
        supervisorEventLoopTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.runSupervisorEventLoopTurn(trigger)
        }
    }

    private func runSupervisorEventLoopTurn(_ trigger: SupervisorEventLoopTrigger) async {
        let response: String
        if let override = supervisorEventLoopResponseOverride {
            let raw = await override(trigger.userMessage, trigger.triggerSource.rawValue)
            response = processSupervisorCommands(
                raw,
                userMessage: trigger.userMessage,
                triggerSource: trigger.triggerSource
            )
        } else {
            response = await generateSupervisorResponse(
                trigger.userMessage,
                triggerSource: trigger.triggerSource
            )
        }

        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            addAssistantMessage(trimmed)
        }

        supervisorEventLoopTask = nil
        drainPendingSupervisorEventLoopIfNeeded()
    }

    private func drainPendingSupervisorEventLoopIfNeeded() {
        guard !isProcessing else { return }
        guard supervisorEventLoopTask == nil else { return }
        guard let trigger = pendingSupervisorEventLoopTrigger else { return }
        pendingSupervisorEventLoopTrigger = nil
        startSupervisorEventLoopTurn(trigger)
    }

    private func pruneSupervisorEventLoopTriggerLedger(now: TimeInterval) {
        let maxAge: TimeInterval = 15
        supervisorEventLoopRecentTriggerLedger = supervisorEventLoopRecentTriggerLedger.filter {
            now - $0.value < maxAge
        }
    }

    private func buildSupervisorEventLoopMessage(
        trigger: SupervisorCommandTriggerSource,
        project: AXProjectEntry,
        record: SupervisorSkillCallRecord,
        extraLines: [String]
    ) -> String {
        let workflowContext = supervisorEventLoopWorkflowContext(project: project, record: record)
        let baseLines = [
            "自动继续当前 governed workflow。",
            "trigger=\(trigger.rawValue)",
            "project_ref=\(project.displayName)",
            "project_id=\(project.projectId)",
            "job_id=\(record.jobId)",
            "plan_id=\(record.planId)",
            "step_id=\(record.stepId)",
            "request_id=\(record.requestId)",
            "skill_id=\(record.skillId)"
        ] + extraLines

        var lines = baseLines
        if !workflowContext.isEmpty {
            lines.append(workflowContext.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return lines.joined(separator: "\n")
    }

    private func scheduleSupervisorSkillCallbackFollowUp(
        record: SupervisorSkillCallRecord,
        project: AXProjectEntry,
        status: SupervisorSkillCallStatus,
        reason: String
    ) {
        let normalizedReason = capped(
            reason.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\n", with: " "),
            maxChars: 220
        )
        let message = buildSupervisorEventLoopMessage(
            trigger: .skillCallback,
            project: project,
            record: record,
            extraLines: [
                "tool_name=\(record.toolName.isEmpty ? "(none)" : record.toolName)",
                "status=\(status.rawValue)",
                "summary=\(normalizedReason.isEmpty ? "(none)" : normalizedReason)"
            ]
        )
        queueSupervisorEventLoopTurn(
            userMessage: message,
            triggerSource: .skillCallback,
            dedupeKey: "skill_callback:\(record.requestId):\(status.rawValue)"
        )
    }

    private func scheduleSupervisorGrantResolutionFollowUp(
        record: SupervisorSkillCallRecord,
        project: AXProjectEntry,
        reasonCode: String,
        summary: String
    ) {
        let normalizedSummary = capped(
            summary.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\n", with: " "),
            maxChars: 220
        )
        let normalizedReasonCode = reasonCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let message = buildSupervisorEventLoopMessage(
            trigger: .grantResolution,
            project: project,
            record: record,
            extraLines: [
                "status=\(record.status.rawValue)",
                "reason_code=\(normalizedReasonCode.isEmpty ? "(none)" : normalizedReasonCode)",
                "summary=\(normalizedSummary.isEmpty ? "(none)" : normalizedSummary)"
            ]
        )
        queueSupervisorEventLoopTurn(
            userMessage: message,
            triggerSource: .grantResolution,
            dedupeKey: "grant_resolution:\(record.requestId):\(reasonCode)"
        )
    }

    private func scheduleSupervisorApprovalResolutionFollowUp(
        record: SupervisorSkillCallRecord,
        project: AXProjectEntry,
        reasonCode: String,
        summary: String
    ) {
        let normalizedSummary = capped(
            summary.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\n", with: " "),
            maxChars: 220
        )
        let normalizedReasonCode = reasonCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let message = buildSupervisorEventLoopMessage(
            trigger: .approvalResolution,
            project: project,
            record: record,
            extraLines: [
                "status=\(record.status.rawValue)",
                "reason_code=\(normalizedReasonCode.isEmpty ? "(none)" : normalizedReasonCode)",
                "summary=\(normalizedSummary.isEmpty ? "(none)" : normalizedSummary)"
            ]
        )
        queueSupervisorEventLoopTurn(
            userMessage: message,
            triggerSource: .approvalResolution,
            dedupeKey: "approval_resolution:\(record.requestId):\(reasonCode)"
        )
    }

    func refreshSupervisorMemorySnapshotNow() {
        Task { @MainActor in
            await refreshSupervisorMemorySnapshot(reason: "manual_refresh")
        }
    }

    private func refreshSupervisorMemorySnapshot(reason: String) async {
        let userMessage = "(supervisor_memory_panel:\(reason))"
        let memoryInfo = await buildSupervisorMemoryV1(userMessage: userMessage)
        publishSupervisorMemoryInfo(memoryInfo)
    }

    private func publishSupervisorMemoryInfo(_ memoryInfo: SupervisorMemoryBuildInfo) {
        let registry = syncSupervisorJurisdictionRegistry(with: knownProjects())
        let visibleDigests = registry.filteredDigests(memoryInfo.projectDigests)
        supervisorMemorySource = memoryInfo.source
        supervisorMemoryUpdatedAt = memoryInfo.updatedAt
        supervisorMemoryProjectDigests = visibleDigests
        supervisorMemoryPreview = memoryInfo.text
        supervisorSkillRegistrySnapshot = memoryInfo.skillRegistrySnapshot
        supervisorSkillRegistryStatusLine = memoryInfo.skillRegistrySnapshot?.statusLine ?? "skills: no focused project"
        supervisorRecentProjectActionEvents = registry.filteredEvents(supervisorRecentProjectActionEvents)
        supervisorMemoryStatusLine = "memory=\(memoryInfo.source) · projects=\(visibleDigests.count) · updated=\(Int(memoryInfo.updatedAt))"
        supervisorPortfolioSnapshot = SupervisorPortfolioSnapshotBuilder.build(from: visibleDigests)
        syncSupervisorPortfolioSnapshotIfNeeded(supervisorPortfolioSnapshot)
        syncSupervisorProjectCapsulesIfNeeded(from: visibleDigests)
    }

    private func syncSupervisorProjectCapsulesIfNeeded(from digests: [SupervisorMemoryProjectDigest]) {
        let visibleIDs = Set(digests.map(\.projectId))
        supervisorProjectCapsuleSyncAuditRefs = supervisorProjectCapsuleSyncAuditRefs.filter { visibleIDs.contains($0.key) }

        for digest in digests {
            let capsule = SupervisorProjectCapsuleBuilder.build(from: digest)
            guard !capsule.projectId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            if supervisorProjectCapsuleSyncAuditRefs[capsule.projectId] == capsule.auditRef {
                continue
            }
            supervisorProjectCapsuleSyncAuditRefs[capsule.projectId] = capsule.auditRef
            HubIPCClient.syncSupervisorProjectCapsule(capsule)
        }
    }

    private func syncSupervisorPortfolioSnapshotIfNeeded(_ snapshot: SupervisorPortfolioSnapshot) {
        let supervisorId = HubIPCClient.defaultSupervisorCanonicalID()
        let fingerprint = SupervisorPortfolioSnapshotCanonicalSync.fingerprint(
            snapshot: snapshot,
            supervisorId: supervisorId
        )
        guard !fingerprint.isEmpty else { return }
        if supervisorPortfolioSnapshotSyncFingerprint == fingerprint {
            return
        }
        supervisorPortfolioSnapshotSyncFingerprint = fingerprint
        HubIPCClient.syncSupervisorPortfolioSnapshot(
            snapshot,
            supervisorId: supervisorId,
            displayName: currentSupervisorIdentityProfile().name
        )
    }

    private func buildSupervisorSystemPrompt(
        userMessage: String,
        projects: [AXProjectEntry],
        preferredModel: String?,
        memoryInfo: SupervisorMemoryBuildInfo
    ) -> String {
        let promptPreferences = currentSupervisorPromptPreferences()
        let params = SupervisorSystemPromptParamsBuilder.build(
            identity: currentSupervisorIdentityProfile(),
            preferredSupervisorModelId: preferredModel,
            supervisorModelRouteSummary: currentSupervisorModelRouteSummary(),
            memorySource: memoryInfo.source,
            projectCount: projects.count,
            userMessage: userMessage,
            memoryV1: memoryInfo.text,
            promptMode: .full,
            extraSystemPrompt: promptPreferences.extraSystemPromptOrNil,
            hubConnected: appModel?.hubConnected ?? false,
            hubRemoteConnected: appModel?.hubRemoteConnected ?? false
        )
        return sanitizeSupervisorOutboundPrompt(
            SupervisorSystemPromptBuilder().build(params)
        )
    }

    func renderSupervisorFailureResponse(error: Error, userMessage: String) -> String {
        let fallback = generateFallbackResponse(userMessage)

        if let resolution = paidModelAccessResolution(from: error) {
            return """
⚠️ Supervisor 当前无法调用已分配模型，已切换为本地直答兜底。

原因：\(resolution.headline)
处理建议：
1. \(primaryRepairStep(for: resolution))
2. \(secondaryRepairStep(for: resolution))

以下为本地直答结果：
\(fallback)
"""
        }

        return """
⚠️ Supervisor 当前无法调用远端模型，已切换为本地直答兜底。

原因：\(conciseSupervisorFailureReason(error))

以下为本地直答结果：
\(fallback)
"""
    }

    private func paidModelAccessResolution(from error: Error) -> XTPaidModelAccessResolution? {
        guard let hubError = error as? HubAIError,
              case let .responseDoneNotOk(failure) = hubError else {
            return nil
        }
        return XTPaidModelAccessExplainability.resolve(
            rawReasonCode: failure.reason,
            deviceName: failure.deviceName,
            modelId: failure.modelId ?? "unknown_model"
        )
    }

    private func primaryRepairStep(for resolution: XTPaidModelAccessResolution) -> String {
        switch resolution.state {
        case .allowedByDevicePolicy:
            return "当前设备策略已允许该模型，直接重试当前请求即可。"
        case .blockedPaidModelDisabled:
            return "到 Hub Settings -> Pairing & Device Trust 为这台设备开启 paid model 访问。"
        case .blockedModelNotInCustomAllowlist:
            return "到 Hub Settings -> Pairing & Device Trust 把 \(resolution.modelId) 加入该设备 allowlist。"
        case .blockedDailyBudgetExceeded:
            return "到 Hub Settings -> Models & Paid Access 提升 daily token limit，或等待下一配额窗口。"
        case .blockedSingleRequestBudgetExceeded:
            return "缩小这次请求，或到 Hub Settings -> Models & Paid Access 提升 single request token limit。"
        case .legacyGrantFlowRequired:
            return "临时放行：到 Hub Settings -> Grants & Permissions 完成一次 legacy grant。"
        }
    }

    private func secondaryRepairStep(for resolution: XTPaidModelAccessResolution) -> String {
        switch resolution.state {
        case .allowedByDevicePolicy:
            return "如果仍失败，改查 Hub 当前模型库存与桥接连通性，而不是重复授权。"
        case .blockedPaidModelDisabled, .blockedModelNotInCustomAllowlist:
            return "如果暂时不改设备策略，可先切到本地模型或已授权模型后再试。"
        case .blockedDailyBudgetExceeded, .blockedSingleRequestBudgetExceeded:
            return "如果暂时不改预算，可先切到本地模型或缩短上下文后再试。"
        case .legacyGrantFlowRequired:
            return "长期修复：到 Hub Settings -> Pairing & Device Trust 把这台设备升级到新 trust profile。"
        }
    }

    private func conciseSupervisorFailureReason(_ error: Error) -> String {
        if let localized = (error as? LocalizedError)?.errorDescription?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !localized.isEmpty {
            return firstNonEmptyLine(in: localized)
        }
        let fallback = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return fallback.isEmpty ? "未知错误" : firstNonEmptyLine(in: fallback)
    }

    private func firstNonEmptyLine(in text: String) -> String {
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !line.isEmpty {
                return line
            }
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func firstNonEmptyLine(items: [String]) -> String {
        for item in items {
            let line = item.trimmingCharacters(in: .whitespacesAndNewlines)
            if !line.isEmpty {
                return line
            }
        }
        return ""
    }

    private func firstNonEmptyValue(_ preferred: String, _ fallback: String?) -> String {
        let primary = preferred.trimmingCharacters(in: .whitespacesAndNewlines)
        if !primary.isEmpty {
            return primary
        }
        return (fallback ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func firstMeaningfulDigestValue(
        _ values: [String?],
        treatContinueCurrentTaskAsPlaceholder: Bool = false,
        treatNoValueAsPlaceholder: Bool = true
    ) -> String {
        for raw in values {
            let cleaned = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !isDigestPlaceholder(
                cleaned,
                treatContinueCurrentTaskAsPlaceholder: treatContinueCurrentTaskAsPlaceholder,
                treatNoValueAsPlaceholder: treatNoValueAsPlaceholder
            ) {
                return cleaned
            }
        }
        return ""
    }

    private func isDigestPlaceholder(
        _ text: String,
        treatContinueCurrentTaskAsPlaceholder: Bool = false,
        treatNoValueAsPlaceholder: Bool = true
    ) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return true
        }

        let lowered = trimmed.lowercased()
        var placeholders = Set(["(暂无)", "(none)", "none", "n/a", "na"].map { $0.lowercased() })
        if treatNoValueAsPlaceholder {
            placeholders.formUnion(["(无)", "无"].map { $0.lowercased() })
        }
        if treatContinueCurrentTaskAsPlaceholder {
            placeholders.insert("继续当前任务")
        }
        return placeholders.contains(lowered)
    }

    private func hasDurableSupervisorProjectMemory(_ memory: AXMemory?) -> Bool {
        guard let memory else { return false }
        if !memory.goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        return !memory.requirements.isEmpty ||
            !memory.currentState.isEmpty ||
            !memory.decisions.isEmpty ||
            !memory.nextSteps.isEmpty ||
            !memory.openQuestions.isEmpty ||
            !memory.risks.isEmpty ||
            !memory.recommendations.isEmpty
    }

    private func processSupervisorCommands(
        _ response: String,
        userMessage: String,
        triggerSource: SupervisorCommandTriggerSource = .userTurn
    ) -> String {
        var processedResponse = response
        let normalizedUserMessage = normalizedSupervisorIntentText(userMessage)
        let allowProjectCreation = triggerSource == .userTurn && isExplicitProjectCreationRequest(normalizedUserMessage)
        let allowModelAssignment = triggerSource == .userTurn && isExplicitModelAssignmentRequest(normalizedUserMessage)
        let allowGovernedOrchestration = isExplicitSupervisorWorkflowExecutionRequest(
            normalizedUserMessage,
            triggerSource: triggerSource
        )

        if !allowProjectCreation {
            processedResponse = replacingTaggedSection(
                in: processedResponse,
                tag: "CREATE_PROJECT",
                with: ""
            )
        }

        if !allowModelAssignment {
            processedResponse = replacingTaggedSection(
                in: processedResponse,
                tag: "ASSIGN_MODEL_ALL",
                with: ""
            )
            processedResponse = replacingTaggedSection(
                in: processedResponse,
                tag: "ASSIGN_MODEL",
                with: ""
            )
        }

        if !allowGovernedOrchestration {
            for tag in ["CREATE_JOB", "UPSERT_PLAN", "CALL_SKILL", "CANCEL_SKILL"] {
                processedResponse = replacingTaggedSection(
                    in: processedResponse,
                    tag: tag,
                    with: ""
                )
            }
        }

        if let projectName = firstTagContent(in: processedResponse, tag: "CREATE_PROJECT"), !projectName.isEmpty {
            let actionId = appendActionLedger(
                action: "create_project",
                targetRef: projectName,
                projectId: nil,
                projectName: nil,
                role: nil,
                modelId: nil,
                status: "pending",
                reasonCode: "started",
                detail: "create project requested",
                verifiedAt: nil,
                triggerSource: triggerSource.rawValue
            )
            Task { @MainActor in
                if let result = await createProject(projectName) {
                    addSystemMessage("✅ 成功创建项目：\(result)")
                    updateActionLedger(
                        id: actionId,
                        status: "ok",
                        reasonCode: "ok",
                        detail: "created project \(result)",
                        verifiedAt: Date().timeIntervalSince1970
                    )
                } else {
                    addSystemMessage("❌ 创建项目失败")
                    updateActionLedger(
                        id: actionId,
                        status: "failed",
                        reasonCode: "user_cancelled_or_create_failed",
                        detail: "create project cancelled or failed",
                        verifiedAt: nil
                    )
                }
            }
            processedResponse = replacingTaggedSection(
                in: processedResponse,
                tag: "CREATE_PROJECT",
                with: "✅ 正在创建项目：\(projectName)"
            )
        }

        var assignAllCommand: ParsedAssignCommand?
        if let payload = firstTagContent(in: processedResponse, tag: "ASSIGN_MODEL_ALL") {
            let parsed = parseAssignCommand(tag: "ASSIGN_MODEL_ALL", payload: payload)
            if let command = parsed.command {
                assignAllCommand = command
            } else {
                let reason = parsed.error ?? "unknown"
                processedResponse = replacingTaggedSection(
                    in: processedResponse,
                    tag: "ASSIGN_MODEL_ALL",
                    with: "❌ 批量分配标签解析失败：\(reason)"
                )
                _ = appendActionLedger(
                    action: "assign_model_all",
                    targetRef: "*",
                    projectId: nil,
                    projectName: nil,
                    role: nil,
                    modelId: nil,
                    status: "failed",
                    reasonCode: "invalid_assign_model_all_format",
                    detail: reason,
                    verifiedAt: nil
                )
            }
        }

        var assignOneCommand: ParsedAssignCommand?
        if let payload = firstTagContent(in: processedResponse, tag: "ASSIGN_MODEL") {
            let parsed = parseAssignCommand(tag: "ASSIGN_MODEL", payload: payload)
            if let command = parsed.command {
                assignOneCommand = command
            } else {
                let reason = parsed.error ?? "unknown"
                processedResponse = replacingTaggedSection(
                    in: processedResponse,
                    tag: "ASSIGN_MODEL",
                    with: "❌ 单项目分配标签解析失败：\(reason)"
                )
                _ = appendActionLedger(
                    action: "assign_model",
                    targetRef: payload,
                    projectId: nil,
                    projectName: nil,
                    role: nil,
                    modelId: nil,
                    status: "failed",
                    reasonCode: "invalid_assign_model_format",
                    detail: reason,
                    verifiedAt: nil
                )
            }
        }

        if let one = assignOneCommand, let all = assignAllCommand {
            if one.projectRef == nil {
                assignOneCommand = nil
                processedResponse = replacingTaggedSection(
                    in: processedResponse,
                    tag: "ASSIGN_MODEL",
                    with: "⚠️ 跳过重复批量分配：已优先执行 ASSIGN_MODEL_ALL。"
                )
                _ = appendActionLedger(
                    action: "assign_model",
                    targetRef: "*",
                    projectId: nil,
                    projectName: nil,
                    role: one.role.rawValue,
                    modelId: one.modelId,
                    status: "skipped",
                    reasonCode: "duplicate_with_assign_model_all",
                    detail: "Skipped duplicate bulk assignment; ASSIGN_MODEL_ALL is used",
                    verifiedAt: nil
                )
            } else {
                assignAllCommand = nil
                processedResponse = replacingTaggedSection(
                    in: processedResponse,
                    tag: "ASSIGN_MODEL_ALL",
                    with: "⚠️ 跳过批量分配：与单项目分配冲突，已优先执行 ASSIGN_MODEL。"
                )
                _ = appendActionLedger(
                    action: "assign_model_all",
                    targetRef: "*",
                    projectId: nil,
                    projectName: nil,
                    role: all.role.rawValue,
                    modelId: all.modelId,
                    status: "skipped",
                    reasonCode: "conflict_with_assign_model",
                    detail: "Skipped bulk assignment because a single-project assignment is present",
                    verifiedAt: nil
                )
            }
        }

        if let all = assignAllCommand {
            let result = assignModelToAllProjects(role: all.role, modelId: all.modelId)
            processedResponse = replacingTaggedSection(
                in: processedResponse,
                tag: all.tag,
                with: result.message
            )
        }

        if let one = assignOneCommand {
            if let projectRef = one.projectRef {
                let result = assignModelToProject(projectRef: projectRef, role: one.role, modelId: one.modelId)
                processedResponse = replacingTaggedSection(
                    in: processedResponse,
                    tag: one.tag,
                    with: result.message
                )
            } else {
                let result = assignModelToAllProjects(role: one.role, modelId: one.modelId)
                processedResponse = replacingTaggedSection(
                    in: processedResponse,
                    tag: one.tag,
                    with: result.message
                )
            }
        }

        processedResponse = processCreateJobCommand(
            in: processedResponse,
            userMessage: userMessage,
            triggerSource: triggerSource
        )
        processedResponse = processUpsertPlanCommand(
            in: processedResponse,
            userMessage: userMessage,
            triggerSource: triggerSource
        )
        processedResponse = processCallSkillCommand(
            in: processedResponse,
            userMessage: userMessage,
            triggerSource: triggerSource
        )
        processedResponse = processCancelSkillCommand(
            in: processedResponse,
            userMessage: userMessage,
            triggerSource: triggerSource
        )

        return processedResponse
    }

    private func createProject(_ projectName: String) async -> String? {
        let panel = NSSavePanel()
        panel.title = "创建新项目"
        panel.prompt = "创建"
        panel.nameFieldStringValue = projectName
        panel.canCreateDirectories = true
        panel.showsHiddenFiles = false
        panel.allowedContentTypes = [.folder]

        let response: NSApplication.ModalResponse
        if let window = NSApp.keyWindow {
            response = await panel.beginSheetModal(for: window)
        } else {
            response = panel.runModal()
        }
        guard response == .OK, let url = panel.url else {
            return nil
        }

        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)

        guard let appModel = appModel else { return nil }
        var reg = appModel.registry
        let res = AXProjectRegistryStore.upsertProject(reg, root: url)
        reg = res.0
        reg.lastSelectedProjectId = res.1.projectId
        appModel.registry = reg
        AXProjectRegistryStore.save(reg)
        appModel.selectedProjectId = res.1.projectId

        return projectName
    }

    private func assignModelToProject(projectRef: String, role: AXRole, modelId: String) -> ModelAssignmentResult {
        let normalizedRef = sanitizeProjectReference(projectRef)
        guard let appModel = appModel else {
            let message = "❌ 分配失败：Supervisor 未初始化（app_model_unavailable）"
            addSystemMessage(message)
            _ = appendActionLedger(
                action: "assign_model",
                targetRef: normalizedRef,
                projectId: nil,
                projectName: nil,
                role: role.rawValue,
                modelId: modelId,
                status: "failed",
                reasonCode: "app_model_unavailable",
                detail: "AppModel is nil",
                verifiedAt: nil
            )
            return ModelAssignmentResult(ok: false, reasonCode: "app_model_unavailable", message: message)
        }

        let resolved = resolveProjectReference(normalizedRef)
        switch resolved {
        case .notFound:
            let hints = allProjects().prefix(4).map { $0.displayName }.joined(separator: "、")
            let suffix = hints.isEmpty ? "" : "。可用项目：\(hints)"
            let message = "❌ 找不到项目引用：\(normalizedRef) (project_not_found)\(suffix)"
            addSystemMessage(message)
            _ = appendActionLedger(
                action: "assign_model",
                targetRef: normalizedRef,
                projectId: nil,
                projectName: nil,
                role: role.rawValue,
                modelId: modelId,
                status: "failed",
                reasonCode: "project_not_found",
                detail: "No project matched for reference",
                verifiedAt: nil
            )
            return ModelAssignmentResult(ok: false, reasonCode: "project_not_found", message: message)

        case .ambiguous(let candidates):
            let list = candidates.prefix(4).map { "\($0.displayName)(\($0.projectId))" }.joined(separator: "、")
            let message = "⚠️ 项目引用不唯一：\(normalizedRef) (project_ambiguous)。候选：\(list)"
            addSystemMessage(message)
            _ = appendActionLedger(
                action: "assign_model",
                targetRef: normalizedRef,
                projectId: nil,
                projectName: nil,
                role: role.rawValue,
                modelId: modelId,
                status: "failed",
                reasonCode: "project_ambiguous",
                detail: "Candidates: \(list)",
                verifiedAt: nil
            )
            return ModelAssignmentResult(ok: false, reasonCode: "project_ambiguous", message: message)

        case .matched(let project):
            guard let ctx = appModel.projectContext(for: project.projectId) else {
                let message = "❌ 项目上下文不可用：\(project.displayName) (project_context_missing)"
                addSystemMessage(message)
                _ = appendActionLedger(
                    action: "assign_model",
                    targetRef: normalizedRef,
                    projectId: project.projectId,
                    projectName: project.displayName,
                    role: role.rawValue,
                    modelId: modelId,
                    status: "failed",
                    reasonCode: "project_context_missing",
                    detail: "Project context lookup failed",
                    verifiedAt: nil
                )
                return ModelAssignmentResult(ok: false, reasonCode: "project_context_missing", message: message)
            }

            guard var cfg = try? AXProjectStore.loadOrCreateConfig(for: ctx) else {
                let message = "❌ 无法加载项目配置：\(project.displayName) (config_load_failed)"
                addSystemMessage(message)
                _ = appendActionLedger(
                    action: "assign_model",
                    targetRef: normalizedRef,
                    projectId: project.projectId,
                    projectName: project.displayName,
                    role: role.rawValue,
                    modelId: modelId,
                    status: "failed",
                    reasonCode: "config_load_failed",
                    detail: "Load config failed",
                    verifiedAt: nil
                )
                return ModelAssignmentResult(ok: false, reasonCode: "config_load_failed", message: message)
            }

            let expectedModelId = normalizedModelId(modelId)
            cfg.setModelOverride(role: role, modelId: expectedModelId)

            do {
                try AXProjectStore.saveConfig(cfg, for: ctx)
            } catch {
                let message = "❌ 保存配置失败：\(project.displayName) (config_save_failed: \(error.localizedDescription))"
                addSystemMessage(message)
                _ = appendActionLedger(
                    action: "assign_model",
                    targetRef: normalizedRef,
                    projectId: project.projectId,
                    projectName: project.displayName,
                    role: role.rawValue,
                    modelId: modelId,
                    status: "failed",
                    reasonCode: "config_save_failed",
                    detail: error.localizedDescription,
                    verifiedAt: nil
                )
                return ModelAssignmentResult(ok: false, reasonCode: "config_save_failed", message: message)
            }

            guard let verify = try? AXProjectStore.loadOrCreateConfig(for: ctx) else {
                let message = "❌ 写入后复检失败：\(project.displayName) (verify_load_failed)"
                addSystemMessage(message)
                _ = appendActionLedger(
                    action: "assign_model",
                    targetRef: normalizedRef,
                    projectId: project.projectId,
                    projectName: project.displayName,
                    role: role.rawValue,
                    modelId: modelId,
                    status: "failed",
                    reasonCode: "verify_load_failed",
                    detail: "Failed to reload config for verification",
                    verifiedAt: nil
                )
                return ModelAssignmentResult(ok: false, reasonCode: "verify_load_failed", message: message)
            }

            let actualModelId = verify.modelOverride(for: role)
            guard actualModelId == expectedModelId else {
                let expected = expectedModelId ?? "auto"
                let actual = actualModelId ?? "auto"
                let message = "❌ 复检不一致：\(project.displayName) (verify_mismatch, expected=\(expected), actual=\(actual))"
                addSystemMessage(message)
                _ = appendActionLedger(
                    action: "assign_model",
                    targetRef: normalizedRef,
                    projectId: project.projectId,
                    projectName: project.displayName,
                    role: role.rawValue,
                    modelId: modelId,
                    status: "failed",
                    reasonCode: "verify_mismatch",
                    detail: "expected=\(expected), actual=\(actual)",
                    verifiedAt: nil
                )
                return ModelAssignmentResult(ok: false, reasonCode: "verify_mismatch", message: message)
            }

            let label = expectedModelId ?? "auto"
            let message = "✅ 已为项目 \(project.displayName) 设置 \(role.displayName) 模型：\(label) (id: \(project.projectId))"
            addSystemMessage(message)
            _ = appendActionLedger(
                action: "assign_model",
                targetRef: normalizedRef,
                projectId: project.projectId,
                projectName: project.displayName,
                role: role.rawValue,
                modelId: label,
                status: "ok",
                reasonCode: "ok",
                detail: "Model assignment verified",
                verifiedAt: Date().timeIntervalSince1970
            )
            return ModelAssignmentResult(ok: true, reasonCode: "ok", message: message)
        }
    }

    private func assignModelToAllProjects(role: AXRole, modelId: String) -> ModelAssignmentResult {
        guard let appModel = appModel else {
            let message = "❌ 批量分配失败：Supervisor 未初始化（app_model_unavailable）"
            addSystemMessage(message)
            _ = appendActionLedger(
                action: "assign_model_all",
                targetRef: "*",
                projectId: nil,
                projectName: nil,
                role: role.rawValue,
                modelId: modelId,
                status: "failed",
                reasonCode: "app_model_unavailable",
                detail: "AppModel is nil",
                verifiedAt: nil
            )
            return ModelAssignmentResult(ok: false, reasonCode: "app_model_unavailable", message: message)
        }

        let projects = appModel.registry.projects
        if projects.isEmpty {
            let message = "⚠️ 当前没有可分配的项目"
            addSystemMessage(message)
            _ = appendActionLedger(
                action: "assign_model_all",
                targetRef: "*",
                projectId: nil,
                projectName: nil,
                role: role.rawValue,
                modelId: modelId,
                status: "failed",
                reasonCode: "no_projects",
                detail: "No projects in registry",
                verifiedAt: nil
            )
            return ModelAssignmentResult(ok: false, reasonCode: "no_projects", message: message)
        }

        let expectedModelId = normalizedModelId(modelId)
        let label = expectedModelId ?? "auto"
        var success = 0
        var failed: [String] = []

        for project in projects {
            guard let ctx = appModel.projectContext(for: project.projectId) else {
                failed.append("\(project.displayName)(project_context_missing)")
                continue
            }
            guard var cfg = try? AXProjectStore.loadOrCreateConfig(for: ctx) else {
                failed.append("\(project.displayName)(config_load_failed)")
                continue
            }
            cfg.setModelOverride(role: role, modelId: expectedModelId)
            do {
                try AXProjectStore.saveConfig(cfg, for: ctx)
                guard let verify = try? AXProjectStore.loadOrCreateConfig(for: ctx),
                      verify.modelOverride(for: role) == expectedModelId else {
                    failed.append("\(project.displayName)(verify_mismatch)")
                    continue
                }
                success += 1
            } catch {
                failed.append("\(project.displayName)(config_save_failed)")
            }
        }

        let result: ModelAssignmentResult
        if failed.isEmpty {
            let message = "✅ 已为全部 \(success) 个项目设置 \(role.displayName) 模型：\(label)"
            result = ModelAssignmentResult(ok: true, reasonCode: "ok", message: message)
        } else if success > 0 {
            let message = "⚠️ 批量分配部分成功：成功 \(success) 个，失败 \(failed.count) 个：\(failed.joined(separator: ", "))"
            result = ModelAssignmentResult(ok: false, reasonCode: "partial_failure", message: message)
        } else {
            let message = "❌ 批量分配失败：\(failed.joined(separator: ", "))"
            result = ModelAssignmentResult(ok: false, reasonCode: "all_failed", message: message)
        }

        addSystemMessage(result.message)
        _ = appendActionLedger(
            action: "assign_model_all",
            targetRef: "*",
            projectId: nil,
            projectName: nil,
            role: role.rawValue,
            modelId: label,
            status: result.ok ? "ok" : "failed",
            reasonCode: result.reasonCode,
            detail: failed.isEmpty ? "Applied to all projects" : failed.joined(separator: "; "),
            verifiedAt: Date().timeIntervalSince1970
        )
        return result
    }

    private func normalizedModelId(_ modelId: String) -> String? {
        let cleaned = modelId.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty { return nil }
        if cleaned.lowercased() == "auto" { return nil }
        return cleaned
    }

    private func parseAssignCommand(tag: String, payload: String) -> (command: ParsedAssignCommand?, error: String?) {
        let trimmedPayload = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        if tag == "ASSIGN_MODEL_ALL" {
            let parts = trimmedPayload.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            guard parts.count == 2 else {
                return (nil, "应为 2 段：角色|模型ID")
            }
            guard let role = AXRole.resolveModelAssignmentToken(parts[0]) else {
                return (nil, "未知角色：\(parts[0])")
            }
            return (ParsedAssignCommand(projectRef: nil, role: role, modelId: parts[1], tag: tag), nil)
        }

        if tag == "ASSIGN_MODEL" {
            let parts = trimmedPayload.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false)
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            guard parts.count == 3 else {
                return (nil, "应为 3 段：项目引用|角色|模型ID")
            }
            guard let role = AXRole.resolveModelAssignmentToken(parts[1]) else {
                return (nil, "未知角色：\(parts[1])")
            }
            let ref = sanitizeProjectReference(parts[0])
            let normalizedRef: String? = (ref == "*" || ref.lowercased() == "all") ? nil : ref
            return (ParsedAssignCommand(projectRef: normalizedRef, role: role, modelId: parts[2], tag: tag), nil)
        }

        return (nil, "unsupported tag: \(tag)")
    }

    private func sanitizeProjectReference(_ raw: String) -> String {
        var out = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if out.isEmpty { return out }

        let wrappers: [(String, String)] = [
            ("[", "]"), ("【", "】"),
            ("(", ")"), ("（", "）"),
            ("“", "”"), ("\"", "\""),
            ("'", "'"), ("`", "`")
        ]
        var changed = true
        while changed {
            changed = false
            for (head, tail) in wrappers {
                if out.hasPrefix(head), out.hasSuffix(tail), out.count > (head.count + tail.count) {
                    out.removeFirst(head.count)
                    out.removeLast(tail.count)
                    out = out.trimmingCharacters(in: .whitespacesAndNewlines)
                    changed = true
                }
            }
        }

        let lower = out.lowercased()
        let prefixes = ["project_id:", "project id:", "项目id:", "项目id：", "项目:", "项目："]
        for prefix in prefixes where lower.hasPrefix(prefix) {
            out = String(out.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            break
        }
        return out
    }

    private func supervisorTriggerContextValue(_ key: String, userMessage: String?) -> String? {
        guard let userMessage else { return nil }
        let normalizedKey = key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedKey.isEmpty else { return nil }

        for rawLine in userMessage.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            let prefix = "\(normalizedKey)="
            guard line.lowercased().hasPrefix(prefix) else { continue }
            let value = String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        }
        return nil
    }

    private func supervisorFallbackProjectReference(
        userMessage: String?,
        triggerSource: SupervisorCommandTriggerSource
    ) -> String? {
        guard triggerSource != .userTurn else { return nil }
        if let projectId = supervisorTriggerContextValue("project_id", userMessage: userMessage) {
            let sanitized = sanitizeProjectReference(projectId)
            if !sanitized.isEmpty {
                return sanitized
            }
        }
        if let projectRef = supervisorTriggerContextValue("project_ref", userMessage: userMessage) {
            let sanitized = sanitizeProjectReference(projectRef)
            if !sanitized.isEmpty {
                return sanitized
            }
        }
        return nil
    }

    private func resolvedSupervisorProjectLookup(
        projectRef: String?,
        projects: [AXProjectEntry],
        userMessage: String?,
        triggerSource: SupervisorCommandTriggerSource
    ) -> (requestedRef: String, resolution: ProjectReferenceResolution?, projectScopeMissing: Bool) {
        let rawProjectRef = sanitizeProjectReference(projectRef ?? "")
        let fallbackRef = supervisorFallbackProjectReference(
            userMessage: userMessage,
            triggerSource: triggerSource
        )

        let primaryRef: String = {
            if !rawProjectRef.isEmpty {
                return rawProjectRef
            }
            if let defaultRef = defaultProjectReferenceForDirectAssignment(projects: projects) {
                return defaultRef
            }
            return ""
        }()

        if !primaryRef.isEmpty {
            let primaryResolution = resolveProjectReference(primaryRef)
            if case .matched = primaryResolution {
                return (primaryRef, primaryResolution, false)
            }
            if let fallbackRef,
               !fallbackRef.isEmpty,
               fallbackRef.compare(primaryRef, options: .caseInsensitive) != .orderedSame {
                let fallbackResolution = resolveProjectReference(fallbackRef)
                if case .matched = fallbackResolution {
                    return (fallbackRef, fallbackResolution, false)
                }
            }
            return (primaryRef, primaryResolution, false)
        }

        if let fallbackRef, !fallbackRef.isEmpty {
            return (fallbackRef, resolveProjectReference(fallbackRef), false)
        }

        return ("", nil, true)
    }

    private func resolveProjectReference(_ projectRef: String) -> ProjectReferenceResolution {
        let projects = allProjects()
        guard !projects.isEmpty else { return .notFound }

        if let exactId = projects.first(where: { $0.projectId.compare(projectRef, options: .caseInsensitive) == .orderedSame }) {
            return .matched(exactId)
        }
        if let exactName = projects.first(where: { $0.displayName.compare(projectRef, options: .caseInsensitive) == .orderedSame }) {
            return .matched(exactName)
        }

        let key = normalizedLookupKey(projectRef)
        guard !key.isEmpty else { return .notFound }

        let scored: [(entry: AXProjectEntry, score: Int)] = projects.compactMap { entry in
            let nameKey = normalizedLookupKey(entry.displayName)
            let idKey = normalizedLookupKey(entry.projectId)
            var score = 0
            if key == idKey { score = max(score, 120) }
            if key == nameKey { score = max(score, 110) }
            if !nameKey.isEmpty && nameKey.hasPrefix(key) { score = max(score, 95) }
            if !nameKey.isEmpty && nameKey.contains(key) { score = max(score, 85) }
            if !idKey.isEmpty && idKey.hasPrefix(key) { score = max(score, 80) }
            if !idKey.isEmpty && idKey.contains(key) { score = max(score, 70) }
            if score == 0 { return nil }
            return (entry, score)
        }
        .sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            if lhs.entry.lastOpenedAt != rhs.entry.lastOpenedAt { return lhs.entry.lastOpenedAt > rhs.entry.lastOpenedAt }
            return lhs.entry.displayName.localizedCaseInsensitiveCompare(rhs.entry.displayName) == .orderedAscending
        }

        guard let best = scored.first else { return .notFound }
        if scored.count == 1 {
            return .matched(best.entry)
        }
        let second = scored[1]
        if best.score - second.score >= 20 {
            return .matched(best.entry)
        }
        return .ambiguous(Array(scored.prefix(4).map { $0.entry }))
    }

    private func normalizedLookupKey(_ text: String) -> String {
        let folded = text
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let scalars = folded.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
        return String(String.UnicodeScalarView(scalars))
    }

    private func collectSupervisorProjectMemoryDigests(maxProjects: Int = 24) -> [SupervisorMemoryProjectDigest] {
        Array(allProjects().prefix(maxProjects)).map(supervisorMemoryDigest)
    }

    func buildSupervisorProjectDrillDown(
        for project: AXProjectEntry,
        requestedScope: SupervisorProjectDrillDownScope = .capsuleOnly,
        recentMessageLimit: Int = 6
    ) -> SupervisorProjectDrillDownSnapshot {
        let registry = supervisorJurisdictionRegistry
        let now = Date().timeIntervalSince1970
        guard registry.allowsProjectVisibility(project) else {
            let denied = SupervisorProjectDrillDownSnapshot.denied(
                projectId: project.projectId,
                projectName: project.displayName,
                status: .deniedProjectInvisible,
                requestedScope: requestedScope,
                denyReason: "project_not_visible_in_current_jurisdiction",
                updatedAt: now
            )
            supervisorLastProjectDrillDownSnapshot = denied
            return denied
        }
        guard registry.allowsDrillDown(projectId: project.projectId, requestedScope: requestedScope) else {
            let denied = SupervisorProjectDrillDownSnapshot.denied(
                projectId: project.projectId,
                projectName: project.displayName,
                status: .deniedScope,
                requestedScope: requestedScope,
                denyReason: "requested_scope_exceeds_jurisdiction_cap",
                updatedAt: now
            )
            supervisorLastProjectDrillDownSnapshot = denied
            return denied
        }

        let digest = supervisorMemoryDigest(project)
        let capsule = SupervisorPortfolioSnapshotBuilder.build(from: [digest], now: now).projects.first
        let ctx = AXProjectContext(root: URL(fileURLWithPath: project.rootPath, isDirectory: true))
        let recentMessages: [AXRecentContextMessage]
        switch requestedScope {
        case .capsuleOnly:
            recentMessages = []
        case .capsulePlusRecent:
            recentMessages = Array(AXRecentContextStore.load(for: ctx).messages.suffix(max(0, recentMessageLimit))).map {
                AXRecentContextMessage(
                    role: $0.role,
                    content: capped($0.content, maxChars: 280),
                    createdAt: $0.createdAt
                )
            }
        case .rawEvidence:
            recentMessages = []
        }

        let snapshot = SupervisorProjectDrillDownSnapshot(
            updatedAt: now,
            projectId: project.projectId,
            projectName: project.displayName,
            status: .allowed,
            requestedScope: requestedScope,
            grantedScope: requestedScope,
            capsule: capsule,
            recentMessages: recentMessages,
            denyReason: nil,
            refs: SupervisorProjectDrillDownRefsBuilder.build(
                projectId: project.projectId,
                ctx: ctx,
                requestedScope: requestedScope
            )
        )
        supervisorLastProjectDrillDownSnapshot = snapshot
        return snapshot
    }

    func buildSupervisorProjectDrillDown(
        projectId: String,
        requestedScope: SupervisorProjectDrillDownScope = .capsuleOnly,
        recentMessageLimit: Int = 6
    ) -> SupervisorProjectDrillDownSnapshot {
        let projects = knownProjects()
        guard let project = projects.first(where: { $0.projectId == projectId }) else {
            let denied = SupervisorProjectDrillDownSnapshot.denied(
                projectId: projectId,
                projectName: projectId,
                status: .projectNotFound,
                requestedScope: requestedScope,
                denyReason: "project_not_found"
            )
            supervisorLastProjectDrillDownSnapshot = denied
            return denied
        }
        return buildSupervisorProjectDrillDown(
            for: project,
            requestedScope: requestedScope,
            recentMessageLimit: recentMessageLimit
        )
    }

    private func supervisorMemoryDigest(_ project: AXProjectEntry) -> SupervisorMemoryProjectDigest {
        let root = URL(fileURLWithPath: project.rootPath, isDirectory: true)
        let ctx = AXProjectContext(root: root)
        let runtime = runtimeStatus(for: project)
        let localMemory = try? AXProjectStore.loadOrCreateMemory(for: ctx)
        let recent = AXRecentContextStore.load(for: ctx)
        let governance = loadSupervisorProjectDigestGovernanceContext(projectId: project.projectId, ctx: ctx)

        let localGoal = (localMemory?.goal ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let localCurrent = firstNonEmptyLine(items: localMemory?.currentState ?? [])
        let localNext = firstNonEmptyLine(items: localMemory?.nextSteps ?? [])
        var localBlocker = firstNonEmptyLine(items: localMemory?.openQuestions ?? [])
        if localBlocker.isEmpty {
            localBlocker = firstNonEmptyLine(items: localMemory?.risks ?? [])
        }

        let state = resolvedSupervisorDigestCurrentState(
            localCurrent: localCurrent,
            registryCurrent: project.currentStateSummary,
            runtimeText: runtime.text,
            governance: governance
        )
        let next = resolvedSupervisorDigestNextStep(
            localNext: localNext,
            registryNext: project.nextStepSummary,
            governance: governance
        )
        let blocker = resolvedSupervisorDigestBlocker(
            localBlocker: localBlocker,
            registryBlocker: project.blockerSummary,
            governance: governance
        )
        let goal = resolvedSupervisorDigestGoal(
            localGoal: localGoal,
            registryDigest: project.statusDigest,
            governance: governance
        )

        let source = resolvedSupervisorDigestSource(
            hasDurableLocalMemory: hasDurableSupervisorProjectMemory(localMemory),
            governance: governance
        )
        let updatedAt = max(
            localMemory?.updatedAt ?? 0,
            project.lastSummaryAt ?? 0,
            project.lastEventAt ?? 0,
            project.lastOpenedAt,
            governance.updatedAt
        )

        return SupervisorMemoryProjectDigest(
            projectId: project.projectId,
            displayName: project.displayName,
            runtimeState: runtime.text,
            source: source,
            goal: goal.isEmpty ? "(暂无)" : goal,
            currentState: state.isEmpty ? "(暂无)" : state,
            nextStep: next.isEmpty ? "(暂无)" : next,
            blocker: blocker.isEmpty ? "(无)" : blocker,
            updatedAt: updatedAt,
            recentMessageCount: recent.messages.count
        )
    }

    private func loadSupervisorProjectDigestGovernanceContext(
        projectId: String,
        ctx: AXProjectContext
    ) -> SupervisorProjectDigestGovernanceContext {
        let specCapsule = SupervisorProjectSpecCapsuleStore.load(for: ctx)
        let decisionSnapshot = SupervisorDecisionTrackStore.load(for: ctx)
        let backgroundSnapshot = SupervisorBackgroundPreferenceTrackStore.load(for: ctx)
        let rails = SupervisorDecisionRailResolver.resolve(
            projectId: projectId,
            decisions: decisionSnapshot.events,
            backgroundNotes: backgroundSnapshot.notes
        )

        let hardDecisions = rails.decisionTrack.reduce(into: [SupervisorDecisionCategory: SupervisorDecisionTrackEvent]()) {
            partial, event in
            partial[event.category] = event
        }

        let preferredBackgroundNote = rails.resolutions
            .compactMap(\.preferredBackgroundNote)
            .sorted { lhs, rhs in
                if lhs.strength.rank != rhs.strength.rank {
                    return lhs.strength.rank > rhs.strength.rank
                }
                return lhs.createdAtMs > rhs.createdAtMs
            }
            .first

        let backgroundShadowHint = preferredBackgroundNote.map { note in
            let statement = capped(firstNonEmptyLine(in: note.statement), maxChars: 80)
            return "背景偏好（弱参考）：\(note.domain.rawValue)=\(statement)"
        } ?? ""

        let updatedAt = max(
            TimeInterval(specCapsule?.updatedAtMs ?? 0) / 1000.0,
            TimeInterval(decisionSnapshot.updatedAtMs) / 1000.0,
            TimeInterval(backgroundSnapshot.updatedAtMs) / 1000.0
        )

        var sourceTags: [String] = []
        if specCapsule != nil {
            sourceTags.append("spec_capsule")
        }
        if !decisionSnapshot.events.isEmpty {
            sourceTags.append("decision_track")
        }
        if !backgroundSnapshot.notes.isEmpty {
            sourceTags.append("background_preference_track")
        }

        return SupervisorProjectDigestGovernanceContext(
            specCapsule: specCapsule,
            missingSpecFields: specCapsule?.missingRequiredFields ?? [],
            hardDecisions: hardDecisions,
            backgroundShadowHint: backgroundShadowHint,
            updatedAt: updatedAt,
            sourceTags: sourceTags
        )
    }

    private func resolvedSupervisorDigestGoal(
        localGoal: String,
        registryDigest: String?,
        governance: SupervisorProjectDigestGovernanceContext
    ) -> String {
        firstMeaningfulDigestValue(
            [
                localGoal,
                governance.specCapsule?.goal,
                registryDigest
            ]
        )
    }

    private func resolvedSupervisorDigestCurrentState(
        localCurrent: String,
        registryCurrent: String?,
        runtimeText: String,
        governance: SupervisorProjectDigestGovernanceContext
    ) -> String {
        let preferred = firstMeaningfulDigestValue([localCurrent, registryCurrent])
        if !preferred.isEmpty {
            return preferred
        }
        if !governance.missingSpecFields.isEmpty {
            return supervisorSpecGapStateHint(governance.missingSpecFields)
        }
        let decisionSummary = supervisorFormalDecisionSummary(governance.hardDecisions)
        if !decisionSummary.isEmpty {
            return decisionSummary
        }
        if !governance.backgroundShadowHint.isEmpty {
            return governance.backgroundShadowHint
        }
        let milestoneHint = supervisorSpecMilestoneStateHint(governance.specCapsule)
        if !milestoneHint.isEmpty {
            return milestoneHint
        }
        return isDigestPlaceholder(runtimeText) ? "" : runtimeText
    }

    private func resolvedSupervisorDigestNextStep(
        localNext: String,
        registryNext: String?,
        governance: SupervisorProjectDigestGovernanceContext
    ) -> String {
        let preferred = firstMeaningfulDigestValue(
            [localNext, registryNext],
            treatContinueCurrentTaskAsPlaceholder: true
        )
        if !preferred.isEmpty {
            return preferred
        }
        if !governance.missingSpecFields.isEmpty {
            return supervisorSpecGapNextStepHint(governance.missingSpecFields)
        }
        let decisionHint = supervisorDecisionNextStepHint(governance.hardDecisions)
        if !decisionHint.isEmpty {
            return decisionHint
        }
        let milestoneHint = supervisorSpecMilestoneNextStepHint(governance.specCapsule)
        if !milestoneHint.isEmpty {
            return milestoneHint
        }
        let techStackHint = supervisorSpecTechStackNextStepHint(governance.specCapsule)
        if !techStackHint.isEmpty {
            return techStackHint
        }
        return ""
    }

    private func resolvedSupervisorDigestBlocker(
        localBlocker: String,
        registryBlocker: String?,
        governance: SupervisorProjectDigestGovernanceContext
    ) -> String {
        let preferred = firstMeaningfulDigestValue(
            [localBlocker, registryBlocker],
            treatNoValueAsPlaceholder: true
        )
        if !preferred.isEmpty {
            return preferred
        }
        if !governance.missingSpecFields.isEmpty {
            return supervisorSpecGapBlockerHint(governance.missingSpecFields)
        }
        return supervisorDecisionBlockerHint(governance.hardDecisions)
    }

    private func resolvedSupervisorDigestSource(
        hasDurableLocalMemory: Bool,
        governance: SupervisorProjectDigestGovernanceContext
    ) -> String {
        var parts = hasDurableLocalMemory ? ["local_project_memory", "registry"] : ["registry_summary"]
        for tag in governance.sourceTags where !parts.contains(tag) {
            parts.append(tag)
        }
        return parts.joined(separator: "+")
    }

    private func supervisorSpecGapFieldList(_ fields: [SupervisorProjectSpecField]) -> String {
        fields.map(supervisorSpecGapFieldLabel).joined(separator: " / ")
    }

    private func supervisorSpecGapFieldLabel(_ field: SupervisorProjectSpecField) -> String {
        switch field {
        case .goal:
            return "goal"
        case .mvpDefinition:
            return "mvp_definition"
        case .nonGoals:
            return "non_goals"
        case .approvedTechStack:
            return "tech_stack"
        case .milestones:
            return "milestones"
        }
    }

    private func supervisorSpecGapStateHint(_ fields: [SupervisorProjectSpecField]) -> String {
        capped("规格待补齐：\(supervisorSpecGapFieldList(fields))", maxChars: 120)
    }

    private func supervisorSpecGapNextStepHint(_ fields: [SupervisorProjectSpecField]) -> String {
        capped("补齐 formal spec 字段：\(supervisorSpecGapFieldList(fields))", maxChars: 120)
    }

    private func supervisorSpecGapBlockerHint(_ fields: [SupervisorProjectSpecField]) -> String {
        capped("formal_spec_missing: \(supervisorSpecGapFieldList(fields))", maxChars: 120)
    }

    private func supervisorDecisionHintOrder() -> [SupervisorDecisionCategory] {
        [.approvalResult, .scopeFreeze, .techStack, .riskPosture]
    }

    private func supervisorFormalDecisionSummary(
        _ hardDecisions: [SupervisorDecisionCategory: SupervisorDecisionTrackEvent]
    ) -> String {
        let items = supervisorDecisionHintOrder().compactMap { category -> String? in
            guard let event = hardDecisions[category] else { return nil }
            let statement = capped(firstNonEmptyLine(in: event.statement), maxChars: 56)
            return "\(category.rawValue)=\(statement)"
        }
        guard !items.isEmpty else { return "" }
        return capped("已批准决策：\(items.prefix(2).joined(separator: "；"))", maxChars: 160)
    }

    private func supervisorDecisionNextStepHint(
        _ hardDecisions: [SupervisorDecisionCategory: SupervisorDecisionTrackEvent]
    ) -> String {
        for category in supervisorDecisionHintOrder() {
            guard let event = hardDecisions[category] else { continue }
            let statement = capped(firstNonEmptyLine(in: event.statement), maxChars: 72)
            switch category {
            case .approvalResult:
                if supervisorDecisionIndicatesBlocker(event) {
                    return "处理已批准 approval_result：\(statement)"
                }
                return "按已批准 approval_result 继续：\(statement)"
            case .scopeFreeze:
                return "按已批准 scope_freeze 收口：\(statement)"
            case .techStack:
                return "按已批准 tech_stack 推进：\(statement)"
            case .riskPosture:
                return "按已批准 risk_posture 执行：\(statement)"
            default:
                return "按已批准决策推进：\(statement)"
            }
        }
        return ""
    }

    private func supervisorDecisionBlockerHint(
        _ hardDecisions: [SupervisorDecisionCategory: SupervisorDecisionTrackEvent]
    ) -> String {
        for category in supervisorDecisionHintOrder() {
            guard let event = hardDecisions[category], supervisorDecisionIndicatesBlocker(event) else { continue }
            let statement = capped(firstNonEmptyLine(in: event.statement), maxChars: 84)
            return "formal_\(category.rawValue): \(statement)"
        }
        return ""
    }

    private func supervisorDecisionIndicatesBlocker(_ event: SupervisorDecisionTrackEvent) -> Bool {
        let lowered = event.statement.lowercased()
        return [
            "deny",
            "denied",
            "rejected",
            "blocked",
            "blocking",
            "no_go",
            "no-go",
            "hold",
            "requires authorization",
            "requires approval",
            "等待授权",
            "阻塞",
            "驳回"
        ].contains { lowered.contains($0) }
    }

    private func supervisorSpecMilestoneStateHint(_ specCapsule: SupervisorProjectSpecCapsule?) -> String {
        guard let milestone = specCapsule?.milestoneMap.first(where: { $0.status == .active }) ??
                specCapsule?.milestoneMap.first else {
            return ""
        }
        return capped("当前规格里程碑：\(milestone.title)", maxChars: 100)
    }

    private func supervisorSpecMilestoneNextStepHint(_ specCapsule: SupervisorProjectSpecCapsule?) -> String {
        guard let milestone = specCapsule?.milestoneMap.first(where: { $0.status == .active }) ??
                specCapsule?.milestoneMap.first else {
            return ""
        }
        return capped("推进规格里程碑：\(milestone.title)", maxChars: 100)
    }

    private func supervisorSpecTechStackNextStepHint(_ specCapsule: SupervisorProjectSpecCapsule?) -> String {
        guard let specCapsule, !specCapsule.approvedTechStack.isEmpty else { return "" }
        let summary = specCapsule.approvedTechStack.prefix(3).joined(separator: ", ")
        return capped("按规格技术栈推进：\(summary)", maxChars: 100)
    }

    private func generateProjectList(from digests: [SupervisorMemoryProjectDigest]) -> String {
        if digests.isEmpty {
            return "(暂无项目)"
        }
        return digests.map { digest in
            """
            - \(digest.displayName)
              运行态: \(digest.runtimeState)
              记忆来源: \(digest.source)
              目标/摘要: \(digest.goal)
              当前状态: \(digest.currentState)
              下一步: \(digest.nextStep)
              阻塞: \(digest.blocker)
              recent_messages: \(digest.recentMessageCount)
            """
        }.joined(separator: "\n")
    }

    private func generateAvailableModels() -> String {
        let models = modelManager.availableModels
        if models.isEmpty {
            return "(暂无可用模型)"
        }
        return models.map { model in
            """
            - \(model.name)
              ID: \(model.id)
              后端: \(model.backend)
              上下文长度: \(model.contextLength)
              状态: \(model.state == .loaded ? "已加载" : "可用")
            """
        }.joined(separator: "\n")
    }

    private func generateFallbackResponse(_ userMessage: String) -> String {
        let projects = allProjects()

        if shouldRunDoctorCommand(userMessage) {
            let report = runSupervisorDoctorPreflight(reason: "fallback_doctor_command", emitSystemMessage: false)
            return renderDoctorSummary(report)
        } else if shouldRunSecretsDryRunCommand(userMessage) {
            let report = runSupervisorDoctorPreflight(reason: "fallback_secrets_dry_run", emitSystemMessage: false)
            return renderSecretsDryRunSummary(report)
        } else if shouldShowXTReadyIncidentEventsStatusCommand(userMessage) {
            return renderXTReadyIncidentEventsStatus()
        } else if shouldExportXTReadyIncidentEventsCommand(userMessage) {
            let result = exportXTReadyIncidentEventsReport()
            return renderXTReadyIncidentExportSummary(result)
        }

        if let directReply = directSupervisorReplyIfApplicable(userMessage, projects: projects) {
            return directReply
        } else if let directAction = directSupervisorActionIfApplicable(userMessage, projects: projects) {
            return directAction
        } else if userMessage.contains("进度") || userMessage.contains("状态") {
            return generateProgressReport(projects)
        } else if userMessage.contains("卡点") || userMessage.contains("问题") {
            return generateBlockerReport(projects)
        } else if userMessage.contains("下一步") || userMessage.contains("建议") {
            return generateNextStepSuggestions(projects)
        } else if userMessage.contains("优先") || userMessage.contains("排序") {
            return generatePriorityRecommendation(projects)
        } else {
            return generateGeneralResponse(userMessage, projects)
        }
    }

    private func isIdentityQuestion(_ normalized: String) -> Bool {
        let tokens = [
            "你是谁",
            "你是啥",
            "你是不是gpt",
            "你是gpt吗",
            "你是不是chatgpt",
            "你是chatgpt吗",
            "who are you",
            "are you gpt",
            "are you chatgpt"
        ]
        return tokens.contains { normalized.contains($0) }
    }

    private func isCapabilityQuestion(_ normalized: String) -> Bool {
        let tokens = [
            "你能做什么",
            "你可以做什么",
            "你会什么",
            "help",
            "帮助",
            "能帮我做什么",
            "what can you do"
        ]
        return tokens.contains { normalized.contains($0) }
    }

    private func isLastActualModelQuestion(_ normalized: String) -> Bool {
        let tokens = [
            "上一轮实际调用了什么模型",
            "上一轮用了什么模型",
            "刚刚上一轮实际调用了什么模型",
            "刚刚那轮实际调用了什么模型",
            "上一次实际调用了什么模型",
            "最近一次实际调用了什么模型",
            "最近一次调用了什么模型",
            "last actual model",
            "last model used",
            "previous model used"
        ]
        return tokens.contains { normalized.contains($0) }
    }

    private func isModelRouteQuestion(_ normalized: String) -> Bool {
        let tokens = [
            "什么模型",
            "哪个模型",
            "当前模型",
            "现在是什么模型",
            "现在什么模型",
            "现在用的什么模型",
            "用了什么模型",
            "实际是什么模型",
            "实际走的什么模型",
            "当前走的是什么模型",
            "是不是gpt模型",
            "what model",
            "which model",
            "current model",
            "model route"
        ]
        return tokens.contains { normalized.contains($0) }
    }

    private func isExecutionIntakeRequest(_ normalized: String) -> Bool {
        if isExplicitProjectCreationRequest(normalized) || isExplicitModelAssignmentRequest(normalized) {
            return false
        }

        let buildVerbs = [
            "帮我做",
            "给我做",
            "请做",
            "做个",
            "做一个",
            "写个",
            "写一个",
            "开发一个",
            "实现一个",
            "build me",
            "make me",
            "create a",
            "create an",
            "implement a",
            "implement an"
        ]
        let artifactHints = [
            "游戏",
            "贪食蛇",
            "贪吃蛇",
            "snake",
            "game",
            "app",
            "应用",
            "网站",
            "网页",
            "web",
            "工具",
            "tool",
            "脚本",
            "script",
            "demo",
            "原型",
            "feature",
            "功能"
        ]
        return buildVerbs.contains(where: { normalized.contains($0) })
            && artifactHints.contains(where: { normalized.contains($0) })
    }

    private func directSupervisorReplyIfApplicable(
        _ userMessage: String,
        projects: [AXProjectEntry]
    ) -> String? {
        if let hubRouteReply = directSupervisorHubRouteReplyIfApplicable(userMessage) {
            return hubRouteReply
        }
        let normalized = normalizedSupervisorIntentText(userMessage)
        if isLastActualModelQuestion(normalized) {
            return generateLastActualModelInvocationResponse(projects)
        }
        if isModelRouteQuestion(normalized) {
            return generateModelRouteStatusResponse(projects)
        }
        if isIdentityQuestion(normalized) {
            return generateIdentityResponse(projects)
        }
        if isExecutionIntakeRequest(normalized) {
            return generateExecutionIntakeResponse(userMessage, projects)
        }
        if isCapabilityQuestion(normalized) {
            return generateCapabilitySummary(projects)
        }
        return nil
    }

    private func directSupervisorHubRouteReplyIfApplicable(_ userMessage: String) -> String? {
        let trimmed = userMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/") else { return nil }

        let tokens = trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let head = tokens.first?.lowercased(), head == "/hub" else { return nil }
        let args = Array(tokens.dropFirst())
        return handleSupervisorSlashHub(args: args)
    }

    private func handleSupervisorSlashHub(args: [String]) -> String {
        guard let headRaw = args.first?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !headRaw.isEmpty else {
            return supervisorHubRouteText()
        }

        switch headRaw {
        case "status", "show", "list":
            return supervisorHubRouteText()
        case "route":
            guard args.count >= 2 else {
                return supervisorHubRouteText()
            }
            let rawMode = args[1]
            if rawMode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "selftest" {
                return supervisorHubRouteSelfTestText()
            }
            guard let mode = HubAIClient.parseTransportModeToken(rawMode) else {
                return "未知 route：\(rawMode)\n可选：auto / grpc / file"
            }
            HubAIClient.setTransportMode(mode)
            return "已设置 Supervisor 所在 Hub 通道：\(mode.rawValue)\n\n" + supervisorHubRouteText()
        default:
            return """
用法：
- /hub route
- /hub route <auto|grpc|file>
- /hub route selftest
"""
        }
    }

    private func supervisorHubRouteText() -> String {
        let mode = HubAIClient.transportMode()
        let withRemote = HubRouteStateMachine.resolve(mode: mode, hasRemoteProfile: true)
        let withoutRemote = HubRouteStateMachine.resolve(mode: mode, hasRemoteProfile: false)
        return """
当前 Hub transport:
- mode: \(mode.rawValue)
- when remote profile exists: \(supervisorRouteDecisionText(withRemote))
- when remote profile missing: \(supervisorRouteDecisionText(withoutRemote))

命令：
- /hub route
- /hub route <auto|grpc|file>
- /hub route selftest
"""
    }

    private func supervisorHubRouteSelfTestText() -> String {
        let checks = HubRouteStateMachine.runSelfChecks()
        let okCount = checks.filter(\.ok).count
        let total = checks.count
        let status = okCount == total ? "PASS" : "FAIL"
        let lines = checks.map { check in
            "- [\(check.ok ? "PASS" : "FAIL")] \(check.name): \(check.detail)"
        }
        return "Hub route selftest: \(status) (\(okCount)/\(total))\n\n" + lines.joined(separator: "\n")
    }

    private func supervisorRouteDecisionText(_ decision: HubRouteDecision) -> String {
        if decision.preferRemote {
            return decision.allowFileFallback ? "remote first -> fallback file on route failure" : "remote only (no fallback)"
        }
        if decision.requiresRemote {
            return "fail-closed (\(decision.remoteUnavailableReasonCode ?? "remote_unavailable"))"
        }
        return "file IPC only"
    }

    private func directSupervisorActionIfApplicable(
        _ userMessage: String,
        projects: [AXProjectEntry]
    ) -> String? {
        let normalized = normalizedSupervisorIntentText(userMessage)
        guard isExplicitModelAssignmentRequest(normalized) else { return nil }

        let explicitRole = firstExplicitRoleMention(in: normalized)
        let role = explicitRole ?? .coder
        let usedDefaultRole = explicitRole == nil

        guard let rawModelToken = extractRequestedModelToken(from: userMessage) else {
            return """
我大概知道你是想切模型，但这句话里还缺目标模型。

你可以直接这样说：
- 把 我的世界还原项目 的开发者模型改成 openai/gpt-5.3-codex
- 把当前项目的模型换成 5.3
- 把 reviewer 改成 auto
"""
        }

        let resolvedModelId: String
        switch resolveRequestedModelToken(rawModelToken) {
        case .resolved(let modelId):
            resolvedModelId = modelId
        case .auto:
            resolvedModelId = "auto"
        case .inventoryUnavailable:
            return """
我知道你想切到“\(rawModelToken)”，但我现在拿不到 Hub 模型清单，所以没法把这个简称稳妥地映射成具体 model id。

如果你现在就要改，直接给完整 model id 最稳，比如 `openai/gpt-5.3-codex`。
"""
        case .notFound:
            return """
当前 Hub 模型清单里，我没找到能稳定匹配“\(rawModelToken)”的模型。

最直接的做法是你给我完整 model id，或者先看一下 Hub 的 Models 页面再回来改。
"""
        case .ambiguous(let candidates):
            let labels = candidates.prefix(4).map { "\($0.id)（\($0.name)）" }.joined(separator: "、")
            return """
“\(rawModelToken)”现在能匹配到多个模型，我不想替你盲选。

候选：
\(labels)

你再说具体一点，最好直接给完整 model id。
"""
        }

        guard let intent = parseDirectModelAssignmentIntent(
            userMessage,
            projects: projects,
            role: role,
            usedDefaultRole: usedDefaultRole,
            resolvedModelId: resolvedModelId,
            sourceModelToken: rawModelToken
        ) else {
            return """
我知道你是要改模型，但我现在还拿不到稳定的项目范围。

你补项目名就行，或者先在侧栏选中项目后再说一句：
`把这个项目的模型换成 \(rawModelToken)`
"""
        }

        let result: ModelAssignmentResult
        if intent.appliesToAllProjects {
            result = assignModelToAllProjects(role: intent.role, modelId: intent.modelId)
        } else {
            let projectRef = intent.projectRef ?? defaultProjectReferenceForDirectAssignment(projects: projects)
            guard let projectRef else {
                return """
我知道你要切模型，但当前项目不唯一，我不能替你猜。

现在有 \(projects.count) 个项目。你补项目名，或者先选中项目后再说“把这个项目的模型换成 \(intent.sourceModelToken)”就行。
"""
            }
            result = assignModelToProject(projectRef: projectRef, role: intent.role, modelId: intent.modelId)
        }

        return naturalizeModelAssignmentResponse(result: result, intent: intent)
    }

    private func normalizedSupervisorIntentText(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private func isExplicitProjectCreationRequest(_ normalized: String) -> Bool {
        let tokens = [
            "创建项目",
            "新建项目",
            "建个项目",
            "建一个项目",
            "建立项目",
            "按默认方案建项目",
            "按默认方案创建项目",
            "直接建项目",
            "直接创建项目",
            "create project",
            "new project"
        ]
        return tokens.contains { normalized.contains($0) }
    }

    private func isExplicitModelAssignmentRequest(_ normalized: String) -> Bool {
        let directTokens = [
            "分配模型",
            "批量分配模型",
            "统一分配模型",
            "设置模型",
            "换模型",
            "切模型",
            "set model",
            "assign model"
        ]
        if directTokens.contains(where: { normalized.contains($0) }) {
            return true
        }

        let roleTokens = [
            "coder",
            "coarse",
            "refine",
            "reviewer",
            "advisor",
            "开发者",
            "粗编",
            "粗稿",
            "初稿",
            "精编",
            "精修",
            "审查",
            "审阅",
            "评审",
            "顾问"
        ]
        let changeTokens = [
            "改成",
            "改为",
            "换成",
            "换为",
            "换到",
            "切到",
            "切换到",
            "设为",
            "设置为",
            "指定",
            "指定为",
            "调整为",
            "用"
        ]
        let modelTokens = ["模型", "model", "auto"]
        let scopeTokens = ["项目", "当前项目", "这个项目", "该项目", "所有项目", "全部项目"]

        let hasRole = roleTokens.contains(where: { normalized.contains($0) })
        let hasChange = changeTokens.contains(where: { normalized.contains($0) })
        let hasModel = modelTokens.contains(where: { normalized.contains($0) })
        let hasScope = scopeTokens.contains(where: { normalized.contains($0) })
        let hasVersionLikeToken = normalized.range(
            of: #"\b[a-z]*[0-9]+(?:\.[0-9]+)+(?:[a-z0-9._/-]*)\b"#,
            options: .regularExpression
        ) != nil
        return hasChange && (hasRole || hasScope) && (hasModel || hasVersionLikeToken)
    }

    private func isExplicitSupervisorWorkflowExecutionRequest(
        _ normalized: String,
        triggerSource: SupervisorCommandTriggerSource
    ) -> Bool {
        if triggerSource != .userTurn {
            return true
        }

        let directTokens = [
            "创建任务",
            "新建任务",
            "建个任务",
            "建一个任务",
            "create job",
            "创建job",
            "新增job",
            "更新计划",
            "创建计划",
            "执行计划",
            "调用技能",
            "调用skill",
            "call skill",
            "取消技能",
            "取消skill",
            "cancel skill",
            "停止技能",
            "执行这个技能",
            "自动处理",
            "自动执行",
            "自动继续",
            "继续执行",
            "启动自动化",
            "launch run",
            "开始跑"
        ]
        if directTokens.contains(where: { normalized.contains($0) }) {
            return true
        }

        let orchestrationNouns = [
            "任务",
            "job",
            "计划",
            "plan",
            "技能",
            "skill",
            "运行",
            "执行"
        ]
        let executionVerbs = [
            "创建",
            "新建",
            "建立",
            "更新",
            "执行",
            "运行",
            "启动",
            "开始",
            "取消",
            "停止",
            "终止",
            "调",
            "调用",
            "create",
            "run",
            "start",
            "cancel",
            "execute",
            "call"
        ]
        let hasNoun = orchestrationNouns.contains(where: { normalized.contains($0) })
        let hasVerb = executionVerbs.contains(where: { normalized.contains($0) })
        return hasNoun && hasVerb
    }

    private func processCreateJobCommand(
        in text: String,
        userMessage: String,
        triggerSource: SupervisorCommandTriggerSource
    ) -> String {
        guard let payload = firstTagContent(in: text, tag: "CREATE_JOB"), !payload.isEmpty else {
            return text
        }

        switch decodeSupervisorJSONPayload(payload, as: SupervisorCreateJobPayload.self) {
        case .success(let command):
            let result = createSupervisorJob(
                from: command,
                userMessage: userMessage,
                triggerSource: triggerSource
            )
            _ = appendActionLedger(
                action: "create_job",
                targetRef: (command.projectRef ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                projectId: result.projectId,
                projectName: result.projectName,
                role: nil,
                modelId: nil,
                status: result.ok ? "ok" : "failed",
                reasonCode: result.reasonCode,
                detail: result.message,
                verifiedAt: result.ok ? Date().timeIntervalSince1970 : nil,
                triggerSource: triggerSource.rawValue
            )
            return replacingTaggedSection(
                in: text,
                tag: "CREATE_JOB",
                with: result.message
            )
        case .failure(let error):
            let reason = error.message
            _ = appendActionLedger(
                action: "create_job",
                targetRef: "(invalid_json)",
                projectId: nil,
                projectName: nil,
                role: nil,
                modelId: nil,
                status: "failed",
                reasonCode: "invalid_create_job_format",
                detail: reason,
                verifiedAt: nil,
                triggerSource: triggerSource.rawValue
            )
            return replacingTaggedSection(
                in: text,
                tag: "CREATE_JOB",
                with: "❌ CREATE_JOB 标签解析失败：\(reason)"
            )
        }
    }

    private func processUpsertPlanCommand(
        in text: String,
        userMessage: String,
        triggerSource: SupervisorCommandTriggerSource
    ) -> String {
        guard let payload = firstTagContent(in: text, tag: "UPSERT_PLAN"), !payload.isEmpty else {
            return text
        }

        switch decodeSupervisorJSONPayload(payload, as: SupervisorUpsertPlanPayload.self) {
        case .success(let command):
            let result = upsertSupervisorPlan(
                from: command,
                userMessage: userMessage,
                triggerSource: triggerSource
            )
            _ = appendActionLedger(
                action: "upsert_plan",
                targetRef: (command.projectRef ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                projectId: result.projectId,
                projectName: result.projectName,
                role: nil,
                modelId: nil,
                status: result.ok ? "ok" : "failed",
                reasonCode: result.reasonCode,
                detail: result.message,
                verifiedAt: result.ok ? Date().timeIntervalSince1970 : nil,
                triggerSource: triggerSource.rawValue
            )
            return replacingTaggedSection(
                in: text,
                tag: "UPSERT_PLAN",
                with: result.message
            )
        case .failure(let error):
            let reason = error.message
            _ = appendActionLedger(
                action: "upsert_plan",
                targetRef: "(invalid_json)",
                projectId: nil,
                projectName: nil,
                role: nil,
                modelId: nil,
                status: "failed",
                reasonCode: "invalid_upsert_plan_format",
                detail: reason,
                verifiedAt: nil,
                triggerSource: triggerSource.rawValue
            )
            return replacingTaggedSection(
                in: text,
                tag: "UPSERT_PLAN",
                with: "❌ UPSERT_PLAN 标签解析失败：\(reason)"
            )
        }
    }

    private func processCallSkillCommand(
        in text: String,
        userMessage: String,
        triggerSource: SupervisorCommandTriggerSource
    ) -> String {
        guard let payload = firstTagContent(in: text, tag: "CALL_SKILL"), !payload.isEmpty else {
            return text
        }

        switch decodeSupervisorJSONPayload(payload, as: SupervisorCallSkillPayload.self) {
        case .success(let command):
            let result = callSupervisorSkill(
                from: command,
                userMessage: userMessage,
                triggerSource: triggerSource
            )
            _ = appendActionLedger(
                action: "call_skill",
                targetRef: (command.projectRef ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                projectId: result.projectId,
                projectName: result.projectName,
                role: nil,
                modelId: nil,
                status: result.ok ? "ok" : "failed",
                reasonCode: result.reasonCode,
                detail: result.message,
                verifiedAt: result.ok ? Date().timeIntervalSince1970 : nil,
                triggerSource: triggerSource.rawValue
            )
            return replacingTaggedSection(
                in: text,
                tag: "CALL_SKILL",
                with: result.message
            )
        case .failure(let error):
            let reason = error.message
            _ = appendActionLedger(
                action: "call_skill",
                targetRef: "(invalid_json)",
                projectId: nil,
                projectName: nil,
                role: nil,
                modelId: nil,
                status: "failed",
                reasonCode: "invalid_call_skill_format",
                detail: reason,
                verifiedAt: nil,
                triggerSource: triggerSource.rawValue
            )
            return replacingTaggedSection(
                in: text,
                tag: "CALL_SKILL",
                with: "❌ CALL_SKILL 标签解析失败：\(reason)"
            )
        }
    }

    private func processCancelSkillCommand(
        in text: String,
        userMessage: String,
        triggerSource: SupervisorCommandTriggerSource
    ) -> String {
        guard let payload = firstTagContent(in: text, tag: "CANCEL_SKILL"), !payload.isEmpty else {
            return text
        }

        switch decodeSupervisorJSONPayload(payload, as: SupervisorCancelSkillPayload.self) {
        case .success(let command):
            let result = cancelSupervisorSkill(
                from: command,
                userMessage: userMessage,
                triggerSource: triggerSource
            )
            _ = appendActionLedger(
                action: "cancel_skill",
                targetRef: (command.projectRef ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                projectId: result.projectId,
                projectName: result.projectName,
                role: nil,
                modelId: nil,
                status: result.ok ? "ok" : "failed",
                reasonCode: result.reasonCode,
                detail: result.message,
                verifiedAt: result.ok ? Date().timeIntervalSince1970 : nil,
                triggerSource: triggerSource.rawValue
            )
            return replacingTaggedSection(
                in: text,
                tag: "CANCEL_SKILL",
                with: result.message
            )
        case .failure(let error):
            let reason = error.message
            _ = appendActionLedger(
                action: "cancel_skill",
                targetRef: "(invalid_json)",
                projectId: nil,
                projectName: nil,
                role: nil,
                modelId: nil,
                status: "failed",
                reasonCode: "invalid_cancel_skill_format",
                detail: reason,
                verifiedAt: nil,
                triggerSource: triggerSource.rawValue
            )
            return replacingTaggedSection(
                in: text,
                tag: "CANCEL_SKILL",
                with: "❌ CANCEL_SKILL 标签解析失败：\(reason)"
            )
        }
    }

    private func decodeSupervisorJSONPayload<T: Decodable>(
        _ payload: String,
        as type: T.Type
    ) -> Result<T, SupervisorJSONPayloadDecodeError> {
        guard let data = payload.data(using: .utf8) else {
            return .failure(SupervisorJSONPayloadDecodeError(message: "payload 不是合法 UTF-8 文本"))
        }
        let decoder = JSONDecoder()
        do {
            return .success(try decoder.decode(type, from: data))
        } catch {
            return .failure(
                SupervisorJSONPayloadDecodeError(
                    message: "body 必须是单个 JSON object：\(error.localizedDescription)"
                )
            )
        }
    }

    private func decodeSupervisorJSONObject(
        _ payload: String
    ) -> Result<[String: Any], SupervisorJSONPayloadDecodeError> {
        guard let data = payload.data(using: .utf8) else {
            return .failure(SupervisorJSONPayloadDecodeError(message: "payload 不是合法 UTF-8 文本"))
        }
        do {
            let object = try JSONSerialization.jsonObject(with: data)
            guard let dictionary = object as? [String: Any] else {
                return .failure(SupervisorJSONPayloadDecodeError(message: "body 必须是单个 JSON object"))
            }
            return .success(dictionary)
        } catch {
            return .failure(
                SupervisorJSONPayloadDecodeError(
                    message: "body 必须是单个 JSON object：\(error.localizedDescription)"
                )
            )
        }
    }

    private func createSupervisorJob(
        from payload: SupervisorCreateJobPayload,
        userMessage: String,
        triggerSource: SupervisorCommandTriggerSource
    ) -> (ok: Bool, reasonCode: String, message: String, projectId: String?, projectName: String?) {
        let goal = payload.goal.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !goal.isEmpty else {
            let message = "❌ CREATE_JOB 失败：goal 不能为空（goal_missing）"
            addSystemMessage(message)
            return (false, "goal_missing", message, nil, nil)
        }

        let scope: SupervisorProjectScopeResolution
        switch resolveSupervisorProjectScope(
            projectRef: payload.projectRef,
            commandName: "CREATE_JOB",
            userMessage: userMessage,
            triggerSource: triggerSource
        ) {
        case .failure(let failure):
            addSystemMessage(failure.message)
            return (false, failure.reasonCode, failure.message, failure.projectId, failure.projectName)
        case .success(let resolved):
            scope = resolved
        }

        let now = Date()
        let nowMs = Int64((now.timeIntervalSince1970 * 1000.0).rounded())
        let jobId = "job-\(nowMs)-\(String(UUID().uuidString.lowercased().prefix(8)))"
        let auditRef = "audit-xt-supervisor-job-\(String(jobId.suffix(12)))"
        let source = SupervisorJobSource.parse(payload.source, fallback: triggerSource.defaultJobSource)
        let owner = (payload.currentOwner ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let record = SupervisorJobRecord(
            schemaVersion: SupervisorJobRecord.currentSchemaVersion,
            jobId: jobId,
            projectId: scope.project.projectId,
            goal: goal,
            priority: SupervisorJobPriority.parse(payload.priority),
            status: .queued,
            source: source,
            currentOwner: owner.isEmpty ? "supervisor" : owner,
            activePlanId: "",
            createdAtMs: nowMs,
            updatedAtMs: nowMs,
            auditRef: auditRef
        )

        do {
            try SupervisorProjectJobStore.append(record, for: scope.ctx)
        } catch {
            let message = "❌ CREATE_JOB 失败：任务落盘失败（job_store_write_failed: \(error.localizedDescription))"
            addSystemMessage(message)
            return (false, "job_store_write_failed", message, scope.project.projectId, scope.project.displayName)
        }

        AXProjectStore.appendRawLog(
            [
                "type": "supervisor_job",
                "action": "create",
                "schema_version": SupervisorJobRecord.currentSchemaVersion,
                "job_id": record.jobId,
                "project_id": record.projectId,
                "goal": record.goal,
                "priority": record.priority.rawValue,
                "status": record.status.rawValue,
                "source": record.source.rawValue,
                "current_owner": record.currentOwner,
                "trigger_source": triggerSource.rawValue,
                "audit_ref": record.auditRef,
                "timestamp_ms": record.updatedAtMs
            ],
            for: scope.ctx
        )
        currentTask = SupervisorTask(
            id: record.jobId,
            projectId: record.projectId,
            title: record.goal,
            status: record.status.rawValue,
            createdAt: now.timeIntervalSince1970
        )
        syncSupervisorProjectWorkflowCanonical(
            ctx: scope.ctx,
            project: scope.project
        )

        let message = "✅ 已为项目 \(scope.project.displayName) 创建任务：\(record.goal)（priority=\(record.priority.rawValue)）"
        addSystemMessage(message)
        return (true, "ok", message, scope.project.projectId, scope.project.displayName)
    }

    private func upsertSupervisorPlan(
        from payload: SupervisorUpsertPlanPayload,
        userMessage: String,
        triggerSource: SupervisorCommandTriggerSource
    ) -> (ok: Bool, reasonCode: String, message: String, projectId: String?, projectName: String?) {
        let planId = payload.planId.trimmingCharacters(in: .whitespacesAndNewlines)
        let jobId = payload.jobId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !planId.isEmpty else {
            let message = "❌ UPSERT_PLAN 失败：plan_id 不能为空（plan_id_missing）"
            addSystemMessage(message)
            return (false, "plan_id_missing", message, nil, nil)
        }
        guard !jobId.isEmpty else {
            let message = "❌ UPSERT_PLAN 失败：job_id 不能为空（job_id_missing）"
            addSystemMessage(message)
            return (false, "job_id_missing", message, nil, nil)
        }
        guard !payload.steps.isEmpty else {
            let message = "❌ UPSERT_PLAN 失败：steps 不能为空（steps_missing）"
            addSystemMessage(message)
            return (false, "steps_missing", message, nil, nil)
        }

        let scope: SupervisorProjectScopeResolution
        switch resolveSupervisorProjectScope(
            projectRef: payload.projectRef,
            commandName: "UPSERT_PLAN",
            userMessage: userMessage,
            triggerSource: triggerSource
        ) {
        case .failure(let failure):
            addSystemMessage(failure.message)
            return (false, failure.reasonCode, failure.message, failure.projectId, failure.projectName)
        case .success(let resolved):
            scope = resolved
        }

        let jobSnapshot = SupervisorProjectJobStore.load(for: scope.ctx)
        guard var job = jobSnapshot.jobs.first(where: { $0.jobId == jobId }) else {
            let message = "❌ UPSERT_PLAN 失败：找不到 job_id \(jobId)（job_not_found）"
            addSystemMessage(message)
            return (false, "job_not_found", message, scope.project.projectId, scope.project.displayName)
        }

        guard job.projectId == scope.project.projectId else {
            let message = "❌ UPSERT_PLAN 失败：job 与当前 project scope 不一致（job_project_scope_mismatch）"
            addSystemMessage(message)
            return (false, "job_project_scope_mismatch", message, scope.project.projectId, scope.project.displayName)
        }

        let now = Date()
        let nowMs = Int64((now.timeIntervalSince1970 * 1000.0).rounded())
        let previousPlanSnapshot = SupervisorProjectPlanStore.load(for: scope.ctx)
        let existingPlan = previousPlanSnapshot.plans.first(where: { $0.planId == planId })
        let owner = (payload.currentOwner ?? job.currentOwner)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let steps = payload.steps.enumerated().map { index, step in
            let title = step.title.trimmingCharacters(in: .whitespacesAndNewlines)
            return SupervisorPlanStepRecord(
                schemaVersion: SupervisorPlanStepRecord.currentSchemaVersion,
                stepId: step.stepId.trimmingCharacters(in: .whitespacesAndNewlines),
                title: title.isEmpty ? "step-\(index + 1)" : title,
                kind: SupervisorPlanStepKind.parse(step.kind),
                status: SupervisorPlanStepStatus.parse(step.status),
                skillId: (step.skillId ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                currentOwner: (step.currentOwner ?? owner).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "supervisor"
                    : (step.currentOwner ?? owner).trimmingCharacters(in: .whitespacesAndNewlines),
                detail: (step.detail ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                orderIndex: index,
                updatedAtMs: nowMs
            )
        }
        guard steps.allSatisfy({ !$0.stepId.isEmpty }) else {
            let message = "❌ UPSERT_PLAN 失败：steps.step_id 不能为空（step_id_missing）"
            addSystemMessage(message)
            return (false, "step_id_missing", message, scope.project.projectId, scope.project.displayName)
        }

        let planStatus = derivedPlanStatus(from: steps)
        let plan = SupervisorPlanRecord(
            schemaVersion: SupervisorPlanRecord.currentSchemaVersion,
            planId: planId,
            jobId: jobId,
            projectId: scope.project.projectId,
            status: planStatus,
            currentOwner: owner.isEmpty ? "supervisor" : owner,
            steps: steps,
            createdAtMs: existingPlan?.createdAtMs ?? nowMs,
            updatedAtMs: nowMs,
            auditRef: existingPlan?.auditRef ?? "audit-xt-supervisor-plan-\(String(planId.suffix(12)))"
        )

        do {
            try SupervisorProjectPlanStore.upsert(plan, for: scope.ctx)
        } catch {
            let message = "❌ UPSERT_PLAN 失败：计划落盘失败（plan_store_write_failed: \(error.localizedDescription))"
            addSystemMessage(message)
            return (false, "plan_store_write_failed", message, scope.project.projectId, scope.project.displayName)
        }

        job.activePlanId = plan.planId
        job.status = derivedJobStatus(from: plan)
        job.currentOwner = plan.currentOwner
        job.updatedAtMs = nowMs
        do {
            try SupervisorProjectJobStore.upsert(job, for: scope.ctx)
        } catch {
            let message = "❌ UPSERT_PLAN 失败：任务状态更新失败（job_store_write_failed: \(error.localizedDescription))"
            addSystemMessage(message)
            return (false, "job_store_write_failed", message, scope.project.projectId, scope.project.displayName)
        }

        AXProjectStore.appendRawLog(
            [
                "type": "supervisor_plan",
                "action": existingPlan == nil ? "create" : "upsert",
                "schema_version": SupervisorPlanRecord.currentSchemaVersion,
                "plan_id": plan.planId,
                "job_id": plan.jobId,
                "project_id": plan.projectId,
                "status": plan.status.rawValue,
                "step_count": plan.steps.count,
                "trigger_source": triggerSource.rawValue,
                "audit_ref": plan.auditRef,
                "timestamp_ms": plan.updatedAtMs
            ],
            for: scope.ctx
        )
        currentTask = SupervisorTask(
            id: job.jobId,
            projectId: job.projectId,
            title: job.goal,
            status: job.status.rawValue,
            createdAt: Double(job.createdAtMs) / 1000.0
        )
        syncSupervisorProjectWorkflowCanonical(
            ctx: scope.ctx,
            project: scope.project
        )

        let message = "✅ 已为项目 \(scope.project.displayName) 写入计划：\(plan.planId)（job=\(plan.jobId), steps=\(plan.steps.count)）"
        addSystemMessage(message)
        return (true, "ok", message, scope.project.projectId, scope.project.displayName)
    }

    private struct SupervisorProjectScopeResolution {
        var project: AXProjectEntry
        var ctx: AXProjectContext
    }

    private struct SupervisorWorkflowStepResolution {
        var project: AXProjectEntry
        var ctx: AXProjectContext
        var job: SupervisorJobRecord
        var plan: SupervisorPlanRecord
        var stepIndex: Int
        var step: SupervisorPlanStepRecord
    }

    private struct SupervisorSkillCallResolution {
        var project: AXProjectEntry
        var ctx: AXProjectContext
        var record: SupervisorSkillCallRecord
    }

    private struct SupervisorMappedSkillDispatch {
        var toolCall: ToolCall
        var toolName: String
    }

    private struct SupervisorCommandResolutionFailure: Error {
        var reasonCode: String
        var message: String
        var projectId: String?
        var projectName: String?
    }

    private struct SupervisorSkillMappingFailure: Error {
        var reasonCode: String
    }

    private func resolveSupervisorProjectScope(
        projectRef: String?,
        commandName: String,
        userMessage: String? = nil,
        triggerSource: SupervisorCommandTriggerSource = .userTurn
    ) -> Result<SupervisorProjectScopeResolution, SupervisorCommandResolutionFailure> {
        guard let appModel else {
            return .failure(
                SupervisorCommandResolutionFailure(
                    reasonCode: "app_model_unavailable",
                    message: "❌ \(commandName) 失败：Supervisor 未初始化（app_model_unavailable）",
                    projectId: nil,
                    projectName: nil
                )
            )
        }

        let projects = allProjects()
        let lookup = resolvedSupervisorProjectLookup(
            projectRef: projectRef,
            projects: projects,
            userMessage: userMessage,
            triggerSource: triggerSource
        )
        if lookup.projectScopeMissing {
            return .failure(
                SupervisorCommandResolutionFailure(
                    reasonCode: "project_scope_missing",
                    message: "❌ \(commandName) 失败：当前项目范围不唯一，请补 project_ref（project_scope_missing）",
                    projectId: nil,
                    projectName: nil
                )
            )
        }

        let project: AXProjectEntry
        switch lookup.resolution ?? .notFound {
        case .matched(let matched):
            project = matched
        case .notFound:
            let hints = projects.prefix(4).map { $0.displayName }.joined(separator: "、")
            let suffix = hints.isEmpty ? "" : "。可用项目：\(hints)"
            return .failure(
                SupervisorCommandResolutionFailure(
                    reasonCode: "project_not_found",
                    message: "❌ \(commandName) 失败：找不到项目引用 \(lookup.requestedRef.isEmpty ? "(empty)" : lookup.requestedRef)（project_not_found）\(suffix)",
                    projectId: nil,
                    projectName: nil
                )
            )
        case .ambiguous(let candidates):
            let list = candidates.prefix(4).map { "\($0.displayName)(\($0.projectId))" }.joined(separator: "、")
            return .failure(
                SupervisorCommandResolutionFailure(
                    reasonCode: "project_ambiguous",
                    message: "❌ \(commandName) 失败：项目引用不唯一（project_ambiguous）。候选：\(list)",
                    projectId: nil,
                    projectName: nil
                )
            )
        }

        guard let ctx = appModel.projectContext(for: project.projectId) else {
            return .failure(
                SupervisorCommandResolutionFailure(
                    reasonCode: "project_context_missing",
                    message: "❌ \(commandName) 失败：项目上下文不可用（project_context_missing）",
                    projectId: project.projectId,
                    projectName: project.displayName
                )
            )
        }
        return .success(SupervisorProjectScopeResolution(project: project, ctx: ctx))
    }

    private func resolveSupervisorWorkflowStep(
        projectRef: String?,
        jobId: String,
        stepId: String,
        skillId: String,
        commandName: String,
        userMessage: String? = nil,
        triggerSource: SupervisorCommandTriggerSource = .userTurn
    ) -> Result<SupervisorWorkflowStepResolution, SupervisorCommandResolutionFailure> {
        switch resolveSupervisorProjectScope(
            projectRef: projectRef,
            commandName: commandName,
            userMessage: userMessage,
            triggerSource: triggerSource
        ) {
        case .failure(let failure):
            return .failure(failure)
        case .success(let scope):
            guard let job = SupervisorProjectJobStore.load(for: scope.ctx).jobs.first(where: { $0.jobId == jobId }) else {
                return .failure(
                    SupervisorCommandResolutionFailure(
                        reasonCode: "job_not_found",
                        message: "❌ \(commandName) 失败：找不到 job_id \(jobId)（job_not_found）",
                        projectId: scope.project.projectId,
                        projectName: scope.project.displayName
                    )
                )
            }

            let plans = SupervisorProjectPlanStore.load(for: scope.ctx).plans
                .filter { $0.jobId == jobId }
                .sorted { lhs, rhs in
                    let leftActive = lhs.planId == job.activePlanId ? 0 : 1
                    let rightActive = rhs.planId == job.activePlanId ? 0 : 1
                    if leftActive != rightActive {
                        return leftActive < rightActive
                    }
                    if lhs.updatedAtMs != rhs.updatedAtMs {
                        return lhs.updatedAtMs > rhs.updatedAtMs
                    }
                    return lhs.planId > rhs.planId
                }
            guard let plan = plans.first(where: { plan in
                plan.steps.contains(where: { $0.stepId == stepId })
            }) else {
                return .failure(
                    SupervisorCommandResolutionFailure(
                        reasonCode: "step_not_found",
                        message: "❌ \(commandName) 失败：找不到 step_id \(stepId)（step_not_found）",
                        projectId: scope.project.projectId,
                        projectName: scope.project.displayName
                    )
                )
            }
            guard let stepIndex = plan.steps.firstIndex(where: { $0.stepId == stepId }) else {
                return .failure(
                    SupervisorCommandResolutionFailure(
                        reasonCode: "step_not_found",
                        message: "❌ \(commandName) 失败：找不到 step_id \(stepId)（step_not_found）",
                        projectId: scope.project.projectId,
                        projectName: scope.project.displayName
                    )
                )
            }
            let step = plan.steps[stepIndex]
            let expectedSkillId = step.skillId.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            if !expectedSkillId.isEmpty && expectedSkillId != skillId {
                return .failure(
                    SupervisorCommandResolutionFailure(
                        reasonCode: "step_skill_mismatch",
                        message: "❌ \(commandName) 失败：step 绑定 skill_id=\(expectedSkillId)，与请求 skill_id=\(skillId) 不一致（step_skill_mismatch）",
                        projectId: scope.project.projectId,
                        projectName: scope.project.displayName
                    )
                )
            }
            return .success(
                SupervisorWorkflowStepResolution(
                    project: scope.project,
                    ctx: scope.ctx,
                    job: job,
                    plan: plan,
                    stepIndex: stepIndex,
                    step: step
                )
            )
        }
    }

    private func locateSupervisorSkillCall(
        requestId: String,
        projectRef: String?,
        commandName: String,
        userMessage: String? = nil,
        triggerSource: SupervisorCommandTriggerSource = .userTurn
    ) -> Result<SupervisorSkillCallResolution, SupervisorCommandResolutionFailure> {
        guard let appModel else {
            return .failure(
                SupervisorCommandResolutionFailure(
                    reasonCode: "app_model_unavailable",
                    message: "❌ \(commandName) 失败：Supervisor 未初始化（app_model_unavailable）",
                    projectId: nil,
                    projectName: nil
                )
            )
        }

        let normalizedRequestId = requestId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedRequestId.isEmpty else {
            return .failure(
                SupervisorCommandResolutionFailure(
                    reasonCode: "request_id_missing",
                    message: "❌ \(commandName) 失败：request_id 不能为空（request_id_missing）",
                    projectId: nil,
                    projectName: nil
                )
            )
        }

        let hasExplicitScope = !(projectRef?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        let hasFallbackScope = supervisorFallbackProjectReference(
            userMessage: userMessage,
            triggerSource: triggerSource
        ) != nil
        if hasExplicitScope || hasFallbackScope {
            switch resolveSupervisorProjectScope(
                projectRef: projectRef,
                commandName: commandName,
                userMessage: userMessage,
                triggerSource: triggerSource
            ) {
            case .failure(let failure):
                return .failure(failure)
            case .success(let scope):
                let snapshot = SupervisorProjectSkillCallStore.load(for: scope.ctx)
                guard let record = snapshot.calls.first(where: { $0.requestId == normalizedRequestId }) else {
                    return .failure(
                        SupervisorCommandResolutionFailure(
                            reasonCode: "request_not_found",
                            message: "❌ \(commandName) 失败：找不到 request_id \(normalizedRequestId)（request_not_found）",
                            projectId: scope.project.projectId,
                            projectName: scope.project.displayName
                        )
                    )
                }
                return .success(SupervisorSkillCallResolution(project: scope.project, ctx: scope.ctx, record: record))
            }
        }

        for project in allProjects() {
            guard let ctx = appModel.projectContext(for: project.projectId) else { continue }
            let snapshot = SupervisorProjectSkillCallStore.load(for: ctx)
            if let record = snapshot.calls.first(where: { $0.requestId == normalizedRequestId }) {
                return .success(SupervisorSkillCallResolution(project: project, ctx: ctx, record: record))
            }
        }

        return .failure(
            SupervisorCommandResolutionFailure(
                reasonCode: "request_not_found",
                message: "❌ \(commandName) 失败：找不到 request_id \(normalizedRequestId)（request_not_found）",
                projectId: nil,
                projectName: nil
            )
        )
    }

    private func callSupervisorSkill(
        from payload: SupervisorCallSkillPayload,
        userMessage: String,
        triggerSource: SupervisorCommandTriggerSource
    ) -> (ok: Bool, reasonCode: String, message: String, projectId: String?, projectName: String?) {
        let jobId = payload.jobId.trimmingCharacters(in: .whitespacesAndNewlines)
        let stepId = payload.stepId.trimmingCharacters(in: .whitespacesAndNewlines)
        let skillId = payload.skillId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !jobId.isEmpty else {
            let message = "❌ CALL_SKILL 失败：job_id 不能为空（job_id_missing）"
            addSystemMessage(message)
            return (false, "job_id_missing", message, nil, nil)
        }
        guard !stepId.isEmpty else {
            let message = "❌ CALL_SKILL 失败：step_id 不能为空（step_id_missing）"
            addSystemMessage(message)
            return (false, "step_id_missing", message, nil, nil)
        }
        guard !skillId.isEmpty else {
            let message = "❌ CALL_SKILL 失败：skill_id 不能为空（skill_id_missing）"
            addSystemMessage(message)
            return (false, "skill_id_missing", message, nil, nil)
        }

        let workflow: SupervisorWorkflowStepResolution
        switch resolveSupervisorWorkflowStep(
            projectRef: payload.projectRef,
            jobId: jobId,
            stepId: stepId,
            skillId: skillId,
            commandName: "CALL_SKILL",
            userMessage: userMessage,
            triggerSource: triggerSource
        ) {
        case .failure(let failure):
            addSystemMessage(failure.message)
            return (false, failure.reasonCode, failure.message, failure.projectId, failure.projectName)
        case .success(let resolved):
            workflow = resolved
        }

        guard let registrySnapshot = AXSkillsLibrary.supervisorSkillRegistrySnapshot(
            projectId: workflow.project.projectId,
            projectName: workflow.project.displayName,
            hubBaseDir: HubPaths.baseDir()
        ) else {
            let message = "❌ CALL_SKILL 失败：Hub skill registry 当前不可用（skill_registry_unavailable）"
            addSystemMessage(message)
            return (false, "skill_registry_unavailable", message, workflow.project.projectId, workflow.project.displayName)
        }
        guard let registryItem = registrySnapshot.items.first(where: { $0.skillId == skillId }) else {
            let message = "❌ CALL_SKILL 失败：技能 \(skillId) 不在当前 project scope 的 Hub registry 中（skill_not_registered）"
            addSystemMessage(message)
            return (false, "skill_not_registered", message, workflow.project.projectId, workflow.project.displayName)
        }

        let nowMs = Int64((Date().timeIntervalSince1970 * 1000.0).rounded())
        let requestId = "skill-\(nowMs)-\(String(UUID().uuidString.lowercased().prefix(8)))"
        let payloadObject = payload.payload ?? [:]
        let owner = workflow.step.currentOwner.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? (workflow.job.currentOwner.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "supervisor" : workflow.job.currentOwner)
            : workflow.step.currentOwner

        let mapped: SupervisorMappedSkillDispatch
        switch mapSupervisorSkillToToolCall(skillId: skillId, payload: payloadObject, requestId: requestId) {
        case .success(let dispatch):
            mapped = dispatch
        case .failure:
            let blocked = SupervisorSkillCallRecord(
                schemaVersion: SupervisorSkillCallRecord.currentSchemaVersion,
                requestId: requestId,
                projectId: workflow.project.projectId,
                jobId: workflow.job.jobId,
                planId: workflow.plan.planId,
                stepId: workflow.step.stepId,
                skillId: skillId,
                toolName: "",
                status: .blocked,
                payload: payloadObject,
                currentOwner: owner,
                resultSummary: "skill mapping unavailable",
                denyCode: "skill_mapping_missing",
                requiredCapability: nil,
                grantRequestId: nil,
                grantId: nil,
                createdAtMs: nowMs,
                updatedAtMs: nowMs,
                auditRef: "audit-xt-supervisor-skill-\(String(requestId.suffix(12)))"
            )
            try? SupervisorProjectSkillCallStore.upsert(blocked, for: workflow.ctx)
            _ = updateSupervisorWorkflowStepState(
                ctx: workflow.ctx,
                project: workflow.project,
                jobId: workflow.job.jobId,
                planId: workflow.plan.planId,
                stepId: workflow.step.stepId,
                status: .blocked,
                detail: blocked.resultSummary,
                owner: blocked.currentOwner,
                updatedAtMs: nowMs
            )
            appendSupervisorSkillCallRawLog(
                action: "blocked",
                record: blocked,
                toolCall: nil,
                triggerSource: triggerSource,
                ctx: workflow.ctx
            )
            let message = "❌ CALL_SKILL 失败：技能 \(skillId) 还没有接到受治理 runtime（skill_mapping_missing）"
            addSystemMessage(message)
            return (false, "skill_mapping_missing", message, workflow.project.projectId, workflow.project.displayName)
        }

        let requiredCapability = supervisorRequiredHubCapability(for: mapped.toolCall)
        let requiresGrant = registryItem.requiresGrant
        let requiresWaitingAuthorization = requiresGrant && !supervisorToolCallHasExplicitGrant(mapped.toolCall)
        let awaitingResultSummary: String = {
            guard requiresWaitingAuthorization else { return "queued governed dispatch" }
            if let requiredCapability, !requiredCapability.isEmpty {
                return "waiting for Hub grant approval"
            }
            return "waiting for local governed approval"
        }()
        let awaitingDenyCode: String = {
            guard requiresWaitingAuthorization else { return "" }
            if let requiredCapability, !requiredCapability.isEmpty {
                return "grant_required"
            }
            return "local_approval_required"
        }()
        let record = SupervisorSkillCallRecord(
            schemaVersion: SupervisorSkillCallRecord.currentSchemaVersion,
            requestId: requestId,
            projectId: workflow.project.projectId,
            jobId: workflow.job.jobId,
            planId: workflow.plan.planId,
            stepId: workflow.step.stepId,
            skillId: skillId,
            toolName: mapped.toolName,
            status: requiresWaitingAuthorization ? .awaitingAuthorization : .queued,
            payload: payloadObject,
            currentOwner: owner,
            resultSummary: awaitingResultSummary,
            denyCode: awaitingDenyCode,
            requiredCapability: requiredCapability,
            grantRequestId: nil,
            grantId: nil,
            createdAtMs: nowMs,
            updatedAtMs: nowMs,
            auditRef: "audit-xt-supervisor-skill-\(String(requestId.suffix(12)))"
        )

        do {
            try SupervisorProjectSkillCallStore.upsert(record, for: workflow.ctx)
        } catch {
            let message = "❌ CALL_SKILL 失败：技能调用落盘失败（skill_call_store_write_failed: \(error.localizedDescription))"
            addSystemMessage(message)
            return (false, "skill_call_store_write_failed", message, workflow.project.projectId, workflow.project.displayName)
        }

        _ = updateSupervisorWorkflowStepState(
            ctx: workflow.ctx,
            project: workflow.project,
            jobId: workflow.job.jobId,
            planId: workflow.plan.planId,
            stepId: workflow.step.stepId,
            status: requiresWaitingAuthorization ? .awaitingAuthorization : .running,
            detail: record.resultSummary,
            owner: record.currentOwner,
            updatedAtMs: nowMs
        )
        appendSupervisorSkillCallRawLog(
            action: requiresWaitingAuthorization ? "awaiting_authorization" : "dispatch",
            record: record,
            toolCall: mapped.toolCall,
            triggerSource: triggerSource,
            ctx: workflow.ctx
        )

        if requiresWaitingAuthorization {
            if let requiredCapability,
               supervisorHubGrantPreflightEnabled {
                let requestedSeconds = supervisorRequestedGrantWindowSeconds(payload: payloadObject)
                let reason = supervisorGrantReason(
                    project: workflow.project,
                    job: workflow.job,
                    skillId: skillId,
                    capability: requiredCapability
                )
                let task = Task { [weak self] in
                    guard let self else { return }
                    await self.requestSupervisorHubGrantForSkillCall(
                        requestId: requestId,
                        project: workflow.project,
                        ctx: workflow.ctx,
                        toolCall: mapped.toolCall,
                        requiredCapability: requiredCapability,
                        requestedSeconds: requestedSeconds,
                        reason: reason
                    )
                }
                supervisorSkillExecutionTasks[requestId] = task
                let message = "⏸️ 已登记技能调用：\(skillId)（request_id=\(requestId)），正在向 Hub 申请 \(requiredCapability) 授权。"
                addSystemMessage(message)
                return (true, "awaiting_authorization", message, workflow.project.projectId, workflow.project.displayName)
            }

            let message: String
            if let requiredCapability, !requiredCapability.isEmpty {
                message = "⏸️ 已登记技能调用：\(skillId)（request_id=\(requestId)），当前需要 Hub 授权后才能继续。"
            } else {
                message = "⏸️ 已登记技能调用：\(skillId)（request_id=\(requestId)），当前需要本地审批后才能继续。"
            }
            addSystemMessage(message)
            return (true, "awaiting_authorization", message, workflow.project.projectId, workflow.project.displayName)
        }

        let task = Task { [weak self] in
            guard let self else { return }
            await self.executeSupervisorSkillCall(
                requestId: requestId,
                project: workflow.project,
                ctx: workflow.ctx,
                toolCall: mapped.toolCall,
                triggerSource: triggerSource
            )
        }
        supervisorSkillExecutionTasks[requestId] = task

        let message = "✅ 已为项目 \(workflow.project.displayName) 排队技能调用：\(skillId)（request_id=\(requestId), tool=\(mapped.toolName)）"
        addSystemMessage(message)
        return (true, "ok", message, workflow.project.projectId, workflow.project.displayName)
    }

    private func cancelSupervisorSkill(
        from payload: SupervisorCancelSkillPayload,
        userMessage: String,
        triggerSource: SupervisorCommandTriggerSource
    ) -> (ok: Bool, reasonCode: String, message: String, projectId: String?, projectName: String?) {
        let requestId = payload.requestId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !requestId.isEmpty else {
            let message = "❌ CANCEL_SKILL 失败：request_id 不能为空（request_id_missing）"
            addSystemMessage(message)
            return (false, "request_id_missing", message, nil, nil)
        }

        let resolved: SupervisorSkillCallResolution
        switch locateSupervisorSkillCall(
            requestId: requestId,
            projectRef: payload.projectRef,
            commandName: "CANCEL_SKILL",
            userMessage: userMessage,
            triggerSource: triggerSource
        ) {
        case .failure(let failure):
            addSystemMessage(failure.message)
            return (false, failure.reasonCode, failure.message, failure.projectId, failure.projectName)
        case .success(let call):
            resolved = call
        }

        if [.completed, .failed, .blocked, .canceled].contains(resolved.record.status) {
            let message = "ℹ️ request_id=\(requestId) 已处于终态（status=\(resolved.record.status.rawValue)），无需重复取消。"
            addSystemMessage(message)
            return (true, "already_terminal", message, resolved.project.projectId, resolved.project.displayName)
        }

        var record = resolved.record
        record.status = .canceled
        record.resultSummary = capped(
            (payload.reason ?? "canceled by supervisor").trimmingCharacters(in: .whitespacesAndNewlines),
            maxChars: 320
        )
        record.denyCode = ""
        record.updatedAtMs = Int64((Date().timeIntervalSince1970 * 1000.0).rounded())
        do {
            try SupervisorProjectSkillCallStore.upsert(record, for: resolved.ctx)
        } catch {
            let message = "❌ CANCEL_SKILL 失败：技能调用状态更新失败（skill_call_store_write_failed: \(error.localizedDescription))"
            addSystemMessage(message)
            return (false, "skill_call_store_write_failed", message, resolved.project.projectId, resolved.project.displayName)
        }

        _ = updateSupervisorWorkflowStepState(
            ctx: resolved.ctx,
            project: resolved.project,
            jobId: record.jobId,
            planId: record.planId,
            stepId: record.stepId,
            status: .canceled,
            detail: record.resultSummary,
            owner: record.currentOwner,
            updatedAtMs: record.updatedAtMs
        )
        appendSupervisorSkillCallRawLog(
            action: "cancel",
            record: record,
            toolCall: nil,
            triggerSource: triggerSource,
            ctx: resolved.ctx
        )

        supervisorSkillExecutionTasks.removeValue(forKey: requestId)?.cancel()
        let message = "✅ 已取消项目 \(resolved.project.displayName) 的技能调用：\(record.skillId)（request_id=\(requestId)）"
        addSystemMessage(message)
        return (true, "ok", message, resolved.project.projectId, resolved.project.displayName)
    }

    private func supervisorRequiredHubCapability(for toolCall: ToolCall) -> String? {
        switch toolCall.tool {
        case .web_fetch, .web_search, .browser_read:
            return "web.fetch"
        default:
            return nil
        }
    }

    private func supervisorToolCallHasExplicitGrant(_ toolCall: ToolCall) -> Bool {
        for key in ["grant_id", "grant_request_id"] {
            guard let value = toolCall.args[key]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty else {
                continue
            }
            return true
        }
        return false
    }

    private func supervisorRequestedGrantWindowSeconds(payload: [String: JSONValue]) -> Int {
        if let raw = payload["timeout_sec"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
           let timeout = Double(raw),
           timeout.isFinite,
           timeout > 0 {
            return max(120, min(3_600, Int(timeout.rounded(.up)) * 4))
        }
        return 900
    }

    private func supervisorGrantReason(
        project: AXProjectEntry,
        job: SupervisorJobRecord,
        skillId: String,
        capability: String
    ) -> String {
        let goal = job.goal.trimmingCharacters(in: .whitespacesAndNewlines)
        if goal.isEmpty {
            return "supervisor skill \(skillId) for project \(project.displayName) requires \(capability)"
        }
        return "supervisor skill \(skillId) for project \(project.displayName): \(goal)"
    }

    private func requestSupervisorHubGrantForSkillCall(
        requestId: String,
        project: AXProjectEntry,
        ctx: AXProjectContext,
        toolCall: ToolCall,
        requiredCapability: String,
        requestedSeconds: Int,
        reason: String
    ) async {
        if isSupervisorSkillCanceled(requestId: requestId, ctx: ctx) {
            supervisorSkillExecutionTasks.removeValue(forKey: requestId)
            return
        }

        let access: HubIPCClient.NetworkAccessResult
        if let override = supervisorNetworkAccessRequestOverride {
            access = await override(ctx.root, requestedSeconds, reason)
        } else {
            access = await HubIPCClient.requestNetworkAccess(
                root: ctx.root,
                seconds: requestedSeconds,
                reason: reason
            )
        }

        if isSupervisorSkillCanceled(requestId: requestId, ctx: ctx) {
            supervisorSkillExecutionTasks.removeValue(forKey: requestId)
            return
        }

        let nowMs = Int64((Date().timeIntervalSince1970 * 1000.0).rounded())
        let normalizedGrantRequestId = access.grantRequestId?.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackSeconds = max(120, access.remainingSeconds ?? requestedSeconds)

        switch access.state {
        case .enabled, .autoApproved:
            let activatedGrantId = await ToolExecutor.activateHighRiskGrantForSupervisor(
                projectRoot: ctx.root,
                capability: requiredCapability,
                grantRequestId: normalizedGrantRequestId,
                fallbackSeconds: fallbackSeconds
            )
            let resumeGrantId = (activatedGrantId?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
                ? activatedGrantId!.trimmingCharacters(in: .whitespacesAndNewlines)
                : (normalizedGrantRequestId ?? "")
            let resumeToolCall = injectSupervisorGrant(
                into: toolCall,
                grantId: resumeGrantId,
                capability: requiredCapability
            )
            _ = applySupervisorSkillCallStatus(
                requestId: requestId,
                ctx: ctx,
                project: project,
                status: .queued,
                stepStatus: .pending,
                resultSummary: "grant approved; resuming governed dispatch",
                denyCode: "",
                requiredCapability: requiredCapability,
                grantRequestId: normalizedGrantRequestId,
                grantId: resumeGrantId.isEmpty ? nil : resumeGrantId,
                updatedAtMs: nowMs,
                triggerSource: .grantResolution,
                toolCall: resumeToolCall
            )
            let executeTask = Task { [weak self] in
                guard let self else { return }
                await self.executeSupervisorSkillCall(
                    requestId: requestId,
                    project: project,
                    ctx: ctx,
                    toolCall: resumeToolCall,
                    triggerSource: .grantResolution
                )
            }
            supervisorSkillExecutionTasks[requestId] = executeTask
            addSystemMessage("✅ 已取得 Hub 授权并恢复技能调用：\(requestId)")
            return

        case .queued:
            _ = applySupervisorSkillCallStatus(
                requestId: requestId,
                ctx: ctx,
                project: project,
                status: .awaitingAuthorization,
                stepStatus: .awaitingAuthorization,
                resultSummary: normalizedGrantRequestId?.isEmpty == false
                    ? "waiting for Hub grant approval (\(normalizedGrantRequestId!))"
                    : "waiting for Hub grant approval",
                denyCode: "grant_required",
                requiredCapability: requiredCapability,
                grantRequestId: normalizedGrantRequestId,
                grantId: nil,
                updatedAtMs: nowMs,
                triggerSource: .grantResolution,
                toolCall: toolCall
            )
            if let normalizedGrantRequestId, !normalizedGrantRequestId.isEmpty {
                addSystemMessage("⏸️ 已向 Hub 提交授权请求：grant_request_id=\(normalizedGrantRequestId)")
            }
            await refreshSchedulerSnapshot(force: true)
            supervisorSkillExecutionTasks.removeValue(forKey: requestId)

        case .denied:
            if let blocked = applySupervisorSkillCallStatus(
                requestId: requestId,
                ctx: ctx,
                project: project,
                status: .blocked,
                stepStatus: .blocked,
                resultSummary: "Hub grant denied",
                denyCode: access.reasonCode?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "grant_denied",
                requiredCapability: requiredCapability,
                grantRequestId: normalizedGrantRequestId,
                grantId: nil,
                updatedAtMs: nowMs,
                triggerSource: .grantResolution,
                toolCall: toolCall
            ) {
                scheduleSupervisorGrantResolutionFollowUp(
                    record: blocked,
                    project: project,
                    reasonCode: blocked.denyCode,
                    summary: blocked.resultSummary
                )
            }
            supervisorSkillExecutionTasks.removeValue(forKey: requestId)

        case .failed:
            if let blocked = applySupervisorSkillCallStatus(
                requestId: requestId,
                ctx: ctx,
                project: project,
                status: .blocked,
                stepStatus: .blocked,
                resultSummary: access.reasonCode?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                    ? "Hub grant request failed: \(access.reasonCode!.trimmingCharacters(in: .whitespacesAndNewlines))"
                    : "Hub grant request failed",
                denyCode: access.reasonCode?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "grant_request_failed",
                requiredCapability: requiredCapability,
                grantRequestId: normalizedGrantRequestId,
                grantId: nil,
                updatedAtMs: nowMs,
                triggerSource: .grantResolution,
                toolCall: toolCall
            ) {
                scheduleSupervisorGrantResolutionFollowUp(
                    record: blocked,
                    project: project,
                    reasonCode: blocked.denyCode,
                    summary: blocked.resultSummary
                )
            }
            supervisorSkillExecutionTasks.removeValue(forKey: requestId)
        }
    }

    private func injectSupervisorGrant(
        into toolCall: ToolCall,
        grantId: String,
        capability: String
    ) -> ToolCall {
        guard !grantId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return toolCall
        }
        guard capability.lowercased().contains("web.fetch") else {
            return toolCall
        }
        var args = toolCall.args
        args["grant_id"] = .string(grantId.trimmingCharacters(in: .whitespacesAndNewlines))
        return ToolCall(id: toolCall.id, tool: toolCall.tool, args: args)
    }

    private func resumeSupervisorSkillCallsAfterGrantAction(
        grant: SupervisorPendingGrant,
        approve: Bool,
        result: HubIPCClient.PendingGrantActionResult
    ) async {
        let projectId = grant.projectId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !projectId.isEmpty else { return }
        guard let project = knownProjects().first(where: { $0.projectId == projectId }),
              let ctx = appModel?.projectContext(for: projectId) else {
            return
        }

        let capability = grant.capability.trimmingCharacters(in: .whitespacesAndNewlines)
        let grantRequestId = grant.grantRequestId.trimmingCharacters(in: .whitespacesAndNewlines)
        let snapshot = SupervisorProjectSkillCallStore.load(for: ctx)
        let matches = snapshot.calls.filter { record in
            guard record.status == .awaitingAuthorization else { return false }
            if !grantRequestId.isEmpty,
               record.grantRequestId?.trimmingCharacters(in: .whitespacesAndNewlines) == grantRequestId {
                return true
            }
            guard record.projectId == projectId else { return false }
            return record.requiredCapability?.trimmingCharacters(in: .whitespacesAndNewlines) == capability
        }
        guard !matches.isEmpty else { return }

        if !approve {
            let updatedAtMs = Int64((Date().timeIntervalSince1970 * 1000.0).rounded())
            for record in matches {
                if let blocked = applySupervisorSkillCallStatus(
                    requestId: record.requestId,
                    ctx: ctx,
                    project: project,
                    status: .blocked,
                    stepStatus: .blocked,
                    resultSummary: "Hub grant denied by user",
                    denyCode: "grant_denied",
                    requiredCapability: capability.isEmpty ? record.requiredCapability : capability,
                    grantRequestId: grantRequestId.isEmpty ? record.grantRequestId : grantRequestId,
                    grantId: nil,
                    updatedAtMs: updatedAtMs,
                    triggerSource: .grantResolution,
                    toolCall: nil
                ) {
                    scheduleSupervisorGrantResolutionFollowUp(
                        record: blocked,
                        project: project,
                        reasonCode: blocked.denyCode,
                        summary: blocked.resultSummary
                    )
                }
            }
            return
        }

        guard result.ok else { return }
        let resolvedGrantId = [
            result.grantId,
            result.grantRequestId,
            grant.grantRequestId
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .first(where: { !$0.isEmpty }) ?? ""

        let nowMs = Int64((Date().timeIntervalSince1970 * 1000.0).rounded())
        let fallbackSeconds: Int = {
            guard let expiresAtMs = result.expiresAtMs, expiresAtMs > 0 else {
                return max(120, grant.requestedTtlSec > 0 ? grant.requestedTtlSec : 900)
            }
            let remaining = Int(((expiresAtMs / 1000.0) - Date().timeIntervalSince1970).rounded(.up))
            return max(120, remaining)
        }()

        if !resolvedGrantId.isEmpty, !capability.isEmpty {
            _ = await ToolExecutor.activateHighRiskGrantForSupervisor(
                projectRoot: ctx.root,
                capability: capability,
                grantRequestId: resolvedGrantId,
                fallbackSeconds: fallbackSeconds
            )
        }

        for record in matches {
            switch mapSupervisorSkillToToolCall(
                skillId: record.skillId,
                payload: record.payload,
                requestId: record.requestId
            ) {
            case .failure:
                if let blocked = applySupervisorSkillCallStatus(
                    requestId: record.requestId,
                    ctx: ctx,
                    project: project,
                    status: .blocked,
                    stepStatus: .blocked,
                    resultSummary: "skill mapping unavailable during grant resume",
                    denyCode: "skill_mapping_missing",
                    requiredCapability: capability.isEmpty ? record.requiredCapability : capability,
                    grantRequestId: grantRequestId.isEmpty ? record.grantRequestId : grantRequestId,
                    grantId: resolvedGrantId.isEmpty ? record.grantId : resolvedGrantId,
                    updatedAtMs: nowMs,
                    triggerSource: .grantResolution,
                    toolCall: nil
                ) {
                    scheduleSupervisorGrantResolutionFollowUp(
                        record: blocked,
                        project: project,
                        reasonCode: blocked.denyCode,
                        summary: blocked.resultSummary
                    )
                }

            case .success(let mapped):
                let resumedToolCall = injectSupervisorGrant(
                    into: mapped.toolCall,
                    grantId: resolvedGrantId,
                    capability: capability.isEmpty ? (record.requiredCapability ?? "") : capability
                )
                _ = applySupervisorSkillCallStatus(
                    requestId: record.requestId,
                    ctx: ctx,
                    project: project,
                    status: .queued,
                    stepStatus: .pending,
                    resultSummary: "grant approved; resuming governed dispatch",
                    denyCode: "",
                    requiredCapability: capability.isEmpty ? record.requiredCapability : capability,
                    grantRequestId: grantRequestId.isEmpty ? record.grantRequestId : grantRequestId,
                    grantId: resolvedGrantId.isEmpty ? record.grantId : resolvedGrantId,
                    updatedAtMs: nowMs,
                    triggerSource: .grantResolution,
                    toolCall: resumedToolCall
                )

                let task = Task { [weak self] in
                    guard let self else { return }
                    await self.executeSupervisorSkillCall(
                        requestId: record.requestId,
                        project: project,
                        ctx: ctx,
                        toolCall: resumedToolCall,
                        triggerSource: .grantResolution
                    )
                }
                supervisorSkillExecutionTasks[record.requestId] = task
            }
        }
    }

    private func executeSupervisorSkillCall(
        requestId: String,
        project: AXProjectEntry,
        ctx: AXProjectContext,
        toolCall: ToolCall,
        allowPreviouslyApprovedAuthorization: Bool = false,
        triggerSource: SupervisorCommandTriggerSource
    ) async {
        defer { supervisorSkillExecutionTasks.removeValue(forKey: requestId) }

        if isSupervisorSkillCanceled(requestId: requestId, ctx: ctx) {
            return
        }

        let config = (try? AXProjectStore.loadOrCreateConfig(for: ctx)) ?? .default(forProjectRoot: ctx.root)
        let decision = await xtToolAuthorizationDecision(
            call: toolCall,
            config: config,
            projectRoot: ctx.root
        )

        if isSupervisorSkillCanceled(requestId: requestId, ctx: ctx) {
            return
        }

        let nowMs = Int64((Date().timeIntervalSince1970 * 1000.0).rounded())
        if decision.isDenied {
            if let blocked = applySupervisorSkillCallStatus(
                requestId: requestId,
                ctx: ctx,
                project: project,
                status: .blocked,
                stepStatus: .blocked,
                resultSummary: decision.detail.isEmpty ? decision.denyCode : decision.detail,
                denyCode: decision.denyCode,
                updatedAtMs: nowMs,
                triggerSource: triggerSource,
                toolCall: toolCall
            ) {
                scheduleSupervisorSkillCallbackFollowUp(
                    record: blocked,
                    project: project,
                    status: .blocked,
                    reason: blocked.resultSummary
                )
            }
            return
        }

        if decision.needsApproval, !allowPreviouslyApprovedAuthorization {
            _ = applySupervisorSkillCallStatus(
                requestId: requestId,
                ctx: ctx,
                project: project,
                status: .awaitingAuthorization,
                stepStatus: .awaitingAuthorization,
                resultSummary: decision.policyReason.isEmpty ? "tool confirmation required" : "tool confirmation required: \(decision.policyReason)",
                denyCode: "",
                updatedAtMs: nowMs,
                triggerSource: triggerSource,
                toolCall: toolCall
            )
            return
        }

        _ = applySupervisorSkillCallStatus(
            requestId: requestId,
            ctx: ctx,
            project: project,
            status: .running,
            stepStatus: .running,
            resultSummary: "executing \(toolCall.tool.rawValue)",
            denyCode: "",
            updatedAtMs: nowMs,
            triggerSource: triggerSource,
            toolCall: toolCall
        )

        do {
            let result: ToolResult
            if let override = supervisorToolExecutorOverride {
                result = try await override(toolCall, ctx.root)
            } else {
                result = try await ToolExecutor.execute(call: toolCall, projectRoot: ctx.root)
            }
            if isSupervisorSkillCanceled(requestId: requestId, ctx: ctx) {
                return
            }
            AXProjectStore.appendToolLog(
                action: toolCall.tool.rawValue,
                input: foundationJSONObject(from: toolCall.args),
                output: result.output,
                ok: result.ok,
                for: ctx
            )
            let finalStatus = result.ok ? SupervisorSkillCallStatus.completed : .failed
            if let updated = applySupervisorSkillCallStatus(
                requestId: requestId,
                ctx: ctx,
                project: project,
                status: finalStatus,
                stepStatus: result.ok ? .completed : .failed,
                resultSummary: summarizedSupervisorSkillOutput(result.output, ok: result.ok),
                denyCode: "",
                updatedAtMs: Int64((Date().timeIntervalSince1970 * 1000.0).rounded()),
                triggerSource: triggerSource,
                toolCall: toolCall
            ) {
                scheduleSupervisorSkillCallbackFollowUp(
                    record: updated,
                    project: project,
                    status: finalStatus,
                    reason: updated.resultSummary
                )
            }
        } catch {
            if isSupervisorSkillCanceled(requestId: requestId, ctx: ctx) {
                return
            }
            if let failed = applySupervisorSkillCallStatus(
                requestId: requestId,
                ctx: ctx,
                project: project,
                status: .failed,
                stepStatus: .failed,
                resultSummary: capped(String(describing: error), maxChars: 320),
                denyCode: "tool_execution_failed",
                updatedAtMs: Int64((Date().timeIntervalSince1970 * 1000.0).rounded()),
                triggerSource: triggerSource,
                toolCall: toolCall
            ) {
                scheduleSupervisorSkillCallbackFollowUp(
                    record: failed,
                    project: project,
                    status: .failed,
                    reason: failed.resultSummary
                )
            }
        }
    }

    private func resolvedSupervisorToolCallForRecord(_ record: SupervisorSkillCallRecord) -> ToolCall? {
        let requestId = record.requestId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !requestId.isEmpty else { return nil }
        let mapped: SupervisorMappedSkillDispatch
        switch mapSupervisorSkillToToolCall(
            skillId: record.skillId,
            payload: record.payload,
            requestId: requestId
        ) {
        case .failure:
            return nil
        case .success(let dispatch):
            mapped = dispatch
        }

        let capability = record.requiredCapability?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let candidateGrantId = [
            record.grantId,
            record.grantRequestId
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .first(where: { !$0.isEmpty }) ?? ""
        if candidateGrantId.isEmpty || capability.isEmpty {
            return mapped.toolCall
        }
        return injectSupervisorGrant(
            into: mapped.toolCall,
            grantId: candidateGrantId,
            capability: capability
        )
    }

    @discardableResult
    private func applySupervisorSkillCallStatus(
        requestId: String,
        ctx: AXProjectContext,
        project: AXProjectEntry,
        status: SupervisorSkillCallStatus,
        stepStatus: SupervisorPlanStepStatus,
        resultSummary: String,
        denyCode: String,
        requiredCapability: String? = nil,
        grantRequestId: String? = nil,
        grantId: String? = nil,
        updatedAtMs: Int64,
        triggerSource: SupervisorCommandTriggerSource,
        toolCall: ToolCall?
    ) -> SupervisorSkillCallRecord? {
        let snapshot = SupervisorProjectSkillCallStore.load(for: ctx)
        guard var record = snapshot.calls.first(where: { $0.requestId == requestId }) else { return nil }
        record.status = status
        record.resultSummary = capped(resultSummary, maxChars: 320)
        record.denyCode = denyCode.trimmingCharacters(in: .whitespacesAndNewlines)
        if let requiredCapability, !requiredCapability.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            record.requiredCapability = requiredCapability.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let grantRequestId, !grantRequestId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            record.grantRequestId = grantRequestId.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let grantId, !grantId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            record.grantId = grantId.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        record.updatedAtMs = updatedAtMs
        try? SupervisorProjectSkillCallStore.upsert(record, for: ctx)
        _ = updateSupervisorWorkflowStepState(
            ctx: ctx,
            project: project,
            jobId: record.jobId,
            planId: record.planId,
            stepId: record.stepId,
            status: stepStatus,
            detail: record.resultSummary,
            owner: record.currentOwner,
            updatedAtMs: updatedAtMs
        )
        appendSupervisorSkillCallRawLog(
            action: status.rawValue,
            record: record,
            toolCall: toolCall,
            triggerSource: triggerSource,
            ctx: ctx
        )
        return record
    }

    @discardableResult
    private func updateSupervisorWorkflowStepState(
        ctx: AXProjectContext,
        project: AXProjectEntry,
        jobId: String,
        planId: String,
        stepId: String,
        status: SupervisorPlanStepStatus,
        detail: String,
        owner: String?,
        updatedAtMs: Int64
    ) -> Bool {
        let planSnapshot = SupervisorProjectPlanStore.load(for: ctx)
        guard var plan = planSnapshot.plans.first(where: { $0.planId == planId })
            ?? planSnapshot.plans.first(where: { $0.jobId == jobId && $0.steps.contains(where: { $0.stepId == stepId }) }) else {
            return false
        }
        guard let stepIndex = plan.steps.firstIndex(where: { $0.stepId == stepId }) else { return false }
        let jobSnapshot = SupervisorProjectJobStore.load(for: ctx)
        guard var job = jobSnapshot.jobs.first(where: { $0.jobId == jobId }) else { return false }

        plan.steps[stepIndex].status = status
        plan.steps[stepIndex].detail = capped(detail, maxChars: 320)
        if let owner, !owner.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            plan.steps[stepIndex].currentOwner = owner
            job.currentOwner = owner
        }
        plan.steps[stepIndex].updatedAtMs = updatedAtMs
        plan.updatedAtMs = updatedAtMs
        plan.status = derivedPlanStatus(from: plan.steps)
        job.activePlanId = plan.planId
        job.status = derivedJobStatus(from: plan)
        job.updatedAtMs = updatedAtMs

        do {
            try SupervisorProjectPlanStore.upsert(plan, for: ctx)
            try SupervisorProjectJobStore.upsert(job, for: ctx)
        } catch {
            return false
        }

        currentTask = SupervisorTask(
            id: job.jobId,
            projectId: job.projectId,
            title: job.goal,
            status: job.status.rawValue,
            createdAt: Double(job.createdAtMs) / 1000.0
        )
        syncSupervisorProjectWorkflowCanonical(ctx: ctx, project: project)
        return true
    }

    private func mapSupervisorSkillToToolCall(
        skillId: String,
        payload: [String: JSONValue],
        requestId: String
    ) -> Result<SupervisorMappedSkillDispatch, SupervisorSkillMappingFailure> {
        switch skillId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "repo.git.status":
            return .success(SupervisorMappedSkillDispatch(
                toolCall: ToolCall(id: requestId, tool: .git_status, args: [:]),
                toolName: ToolName.git_status.rawValue
            ))
        case "repo.git.diff":
            var args: [String: JSONValue] = [:]
            if let cached = payload["cached"] {
                args["cached"] = cached
            }
            return .success(SupervisorMappedSkillDispatch(
                toolCall: ToolCall(id: requestId, tool: .git_diff, args: args),
                toolName: ToolName.git_diff.rawValue
            ))
        case "repo.search", "repo.grep":
            guard let pattern = payload["pattern"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !pattern.isEmpty else {
                return .failure(SupervisorSkillMappingFailure(reasonCode: "payload.pattern_missing"))
            }
            var args: [String: JSONValue] = ["pattern": .string(pattern)]
            if let path = payload["path"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
               !path.isEmpty {
                args["path"] = .string(path)
            }
            if let glob = payload["glob"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
               !glob.isEmpty {
                args["glob"] = .string(glob)
            }
            return .success(SupervisorMappedSkillDispatch(
                toolCall: ToolCall(id: requestId, tool: .search, args: args),
                toolName: ToolName.search.rawValue
            ))
        case "repo.read.file", "repo.read", "repo.file.read":
            guard let path = payload["path"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !path.isEmpty else {
                return .failure(SupervisorSkillMappingFailure(reasonCode: "payload.path_missing"))
            }
            return .success(SupervisorMappedSkillDispatch(
                toolCall: ToolCall(id: requestId, tool: .read_file, args: ["path": .string(path)]),
                toolName: ToolName.read_file.rawValue
            ))
        case "repo.list.dir", "repo.list", "repo.dir.list":
            let path = payload["path"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "."
            return .success(SupervisorMappedSkillDispatch(
                toolCall: ToolCall(id: requestId, tool: .list_dir, args: ["path": .string(path.isEmpty ? "." : path)]),
                toolName: ToolName.list_dir.rawValue
            ))
        case "project.snapshot", "project_snapshot":
            return .success(SupervisorMappedSkillDispatch(
                toolCall: ToolCall(id: requestId, tool: .project_snapshot, args: [:]),
                toolName: ToolName.project_snapshot.rawValue
            ))
        case "memory.snapshot", "memory_snapshot":
            var args: [String: JSONValue] = [:]
            if let mode = payload["mode"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
               !mode.isEmpty {
                args["mode"] = .string(mode)
            }
            return .success(SupervisorMappedSkillDispatch(
                toolCall: ToolCall(id: requestId, tool: .memory_snapshot, args: args),
                toolName: ToolName.memory_snapshot.rawValue
            ))
        case "bridge.status", "bridge_status":
            return .success(SupervisorMappedSkillDispatch(
                toolCall: ToolCall(id: requestId, tool: .bridge_status, args: [:]),
                toolName: ToolName.bridge_status.rawValue
            ))
        case "browser.open", "browser.navigate", "browser_open", "browser_navigate":
            guard let url = payload["url"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !url.isEmpty else {
                return .failure(SupervisorSkillMappingFailure(reasonCode: "payload.url_missing"))
            }
            return .success(SupervisorMappedSkillDispatch(
                toolCall: ToolCall(
                    id: requestId,
                    tool: .deviceBrowserControl,
                    args: [
                        "action": .string("open_url"),
                        "url": .string(url)
                    ]
                ),
                toolName: ToolName.deviceBrowserControl.rawValue
            ))
        case "browser.runtime.inspect", "browser_runtime.inspect":
            var args: [String: JSONValue] = ["action": .string("snapshot")]
            if let url = payload["url"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
               !url.isEmpty {
                args["url"] = .string(url)
            }
            if let sessionId = payload["session_id"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
               !sessionId.isEmpty {
                args["session_id"] = .string(sessionId)
            }
            guard args["url"] != nil || args["session_id"] != nil else {
                return .failure(SupervisorSkillMappingFailure(reasonCode: "payload.url_or_session_id_missing"))
            }
            return .success(SupervisorMappedSkillDispatch(
                toolCall: ToolCall(id: requestId, tool: .deviceBrowserControl, args: args),
                toolName: ToolName.deviceBrowserControl.rawValue
            ))
        case "browser.runtime.smoke", "browser_runtime.smoke":
            let url = payload["url"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "https://example.com"
            return .success(SupervisorMappedSkillDispatch(
                toolCall: ToolCall(
                    id: requestId,
                    tool: .deviceBrowserControl,
                    args: [
                        "action": .string("open_url"),
                        "url": .string(url)
                    ]
                ),
                toolName: ToolName.deviceBrowserControl.rawValue
            ))
        case "web.fetch", "web_fetch":
            guard let url = payload["url"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !url.isEmpty else {
                return .failure(SupervisorSkillMappingFailure(reasonCode: "payload.url_missing"))
            }
            var args: [String: JSONValue] = ["url": .string(url)]
            for key in ["grant_id", "timeout_sec", "max_bytes"] {
                if let value = payload[key] {
                    args[key] = value
                }
            }
            return .success(SupervisorMappedSkillDispatch(
                toolCall: ToolCall(id: requestId, tool: .web_fetch, args: args),
                toolName: ToolName.web_fetch.rawValue
            ))
        case "web.search", "web_search":
            guard let query = payload["query"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !query.isEmpty else {
                return .failure(SupervisorSkillMappingFailure(reasonCode: "payload.query_missing"))
            }
            var args: [String: JSONValue] = ["query": .string(query)]
            for key in ["grant_id", "timeout_sec", "max_results", "max_bytes"] {
                if let value = payload[key] {
                    args[key] = value
                }
            }
            return .success(SupervisorMappedSkillDispatch(
                toolCall: ToolCall(id: requestId, tool: .web_search, args: args),
                toolName: ToolName.web_search.rawValue
            ))
        case "browser.read", "browser_read":
            guard let url = payload["url"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !url.isEmpty else {
                return .failure(SupervisorSkillMappingFailure(reasonCode: "payload.url_missing"))
            }
            var args: [String: JSONValue] = ["url": .string(url)]
            for key in ["grant_id", "timeout_sec", "max_bytes"] {
                if let value = payload[key] {
                    args[key] = value
                }
            }
            return .success(SupervisorMappedSkillDispatch(
                toolCall: ToolCall(id: requestId, tool: .browser_read, args: args),
                toolName: ToolName.browser_read.rawValue
            ))
        case "coder.run.command", "coder.run", "coder_run.command", "coder_run":
            guard let command = payload["command"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !command.isEmpty else {
                return .failure(SupervisorSkillMappingFailure(reasonCode: "payload.command_missing"))
            }
            var args: [String: JSONValue] = ["command": .string(command)]
            if let timeout = payload["timeout_sec"] {
                args["timeout_sec"] = timeout
            }
            return .success(SupervisorMappedSkillDispatch(
                toolCall: ToolCall(id: requestId, tool: .run_command, args: args),
                toolName: ToolName.run_command.rawValue
            ))
        default:
            return .failure(SupervisorSkillMappingFailure(reasonCode: "unsupported_skill_id"))
        }
    }

    private func appendSupervisorSkillCallRawLog(
        action: String,
        record: SupervisorSkillCallRecord,
        toolCall: ToolCall?,
        triggerSource: SupervisorCommandTriggerSource,
        ctx: AXProjectContext
    ) {
        var row: [String: Any] = [
            "type": "supervisor_skill_call",
            "action": action,
            "schema_version": SupervisorSkillCallRecord.currentSchemaVersion,
            "request_id": record.requestId,
            "project_id": record.projectId,
            "job_id": record.jobId,
            "plan_id": record.planId,
            "step_id": record.stepId,
            "skill_id": record.skillId,
            "tool_name": record.toolName,
            "status": record.status.rawValue,
            "current_owner": record.currentOwner,
            "trigger_source": triggerSource.rawValue,
            "audit_ref": record.auditRef,
            "timestamp_ms": record.updatedAtMs
        ]
        if !record.resultSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            row["result_summary"] = record.resultSummary
        }
        if !record.denyCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            row["deny_code"] = record.denyCode
        }
        if let capability = record.requiredCapability?.trimmingCharacters(in: .whitespacesAndNewlines),
           !capability.isEmpty {
            row["required_capability"] = capability
        }
        if let grantRequestId = record.grantRequestId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !grantRequestId.isEmpty {
            row["grant_request_id"] = grantRequestId
        }
        if let grantId = record.grantId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !grantId.isEmpty {
            row["grant_id"] = grantId
        }
        if let toolCall {
            row["tool"] = toolCall.tool.rawValue
            row["tool_args"] = foundationJSONObject(from: toolCall.args)
        }
        AXProjectStore.appendRawLog(row, for: ctx)
    }

    private func summarizedSupervisorSkillOutput(_ output: String, ok: Bool) -> String {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ok ? "tool execution completed" : "tool execution failed"
        }
        return capped(trimmed, maxChars: 320)
    }

    private func isSupervisorSkillCanceled(requestId: String, ctx: AXProjectContext) -> Bool {
        SupervisorProjectSkillCallStore.load(for: ctx).calls.first(where: { $0.requestId == requestId })?.status == .canceled
    }

    private func foundationJSONObject(from object: [String: JSONValue]) -> [String: Any] {
        object.reduce(into: [String: Any]()) { partial, item in
            partial[item.key] = foundationValue(from: item.value)
        }
    }

    private func foundationValue(from value: JSONValue) -> Any {
        switch value {
        case .string(let string):
            return string
        case .number(let number):
            return number
        case .bool(let bool):
            return bool
        case .object(let object):
            return foundationJSONObject(from: object)
        case .array(let array):
            return array.map { foundationValue(from: $0) }
        case .null:
            return NSNull()
        }
    }

    private func derivedPlanStatus(from steps: [SupervisorPlanStepRecord]) -> SupervisorPlanStatus {
        let statuses = steps.map(\.status)
        if statuses.isEmpty || statuses.allSatisfy({ $0 == .pending }) {
            return .planning
        }
        if statuses.contains(.awaitingAuthorization) {
            return .awaitingAuthorization
        }
        if statuses.contains(.blocked) {
            return .blocked
        }
        if statuses.allSatisfy({ $0 == .completed }) {
            return .completed
        }
        if statuses.contains(.failed) {
            return .failed
        }
        if statuses.allSatisfy({ $0 == .canceled }) {
            return .canceled
        }
        return .active
    }

    private func derivedJobStatus(from plan: SupervisorPlanRecord) -> SupervisorJobStatus {
        switch plan.status {
        case .planning:
            return .planning
        case .active:
            return .running
        case .blocked:
            return .blocked
        case .awaitingAuthorization:
            return .awaitingAuthorization
        case .completed:
            return .completed
        case .failed:
            return .failed
        case .canceled:
            return .canceled
        }
    }

    private func syncSupervisorProjectWorkflowCanonical(
        ctx: AXProjectContext,
        project: AXProjectEntry
    ) {
        defer { rebuildPendingSupervisorSkillApprovalViewState() }
        let jobSnapshot = SupervisorProjectJobStore.load(for: ctx)
        let planSnapshot = SupervisorProjectPlanStore.load(for: ctx)
        let skillCallSnapshot = SupervisorProjectSkillCallStore.load(for: ctx)
        guard let snapshot = SupervisorProjectWorkflowCanonicalSync.snapshot(
            projectId: project.projectId,
            projectName: project.displayName,
            jobSnapshot: jobSnapshot,
            planSnapshot: planSnapshot,
            skillCallSnapshot: skillCallSnapshot
        ) else {
            return
        }
        HubIPCClient.syncSupervisorProjectWorkflow(snapshot)
    }

    private func generateIdentityResponse(_ projects: [AXProjectEntry]) -> String {
        let identity = currentSupervisorIdentityProfile()
        let route = currentSupervisorModelRouteSummary()
        return """
不是。当前这个入口的身份是 \(identity.name)，不是一个裸的 GPT 聊天窗口。

对外身份描述：
\(identity.roleSummary)

配置层面上，Supervisor 当前首选的远端模型路由是：
\(route)

但这条回复本身是本地直答，没有实际调用远端模型。所以这里表达的是“当前配置准备优先走哪条路由”，不等于“这轮已经用了 GPT”。

当前接管项目数：\(projects.count)。
"""
    }

    private func generateModelRouteStatusResponse(_ projects: [AXProjectEntry]) -> String {
        let configuredRoute = currentSupervisorModelRouteSummary()
        let actualInvocation = lastSupervisorActualInvocationSummary()
        let verification = currentSupervisorModelVerificationSummary()
        let mismatch = currentSupervisorModelMismatchSummary()
        let transport = currentHubTransportSummary()
        return """
如果你问的是这条回复本身：这条是本地直答，没有实际调用远端模型。

以下记录只针对 Supervisor 角色；Project AI / coder / reviewer 的模型路由与最近调用彼此独立，不能混读。

当前配置的 Supervisor 首选远端模型路由：
\(configuredRoute)

当前 Hub transport:
\(transport)

当前验证状态：
\(verification)

\(mismatch.map { "当前差异提示：\n\($0)\n" } ?? "")

最近一次真实调用记录：
\(actualInvocation)

所以你看到某次回复里自称“阿里巴巴集团研发”这类话，不能直接拿来判断当前实际模型，更不能据此断定 paid GPT 一定不可用。更可能是那一轮把“模型身份问题”交给了远端模型自由回答。

当前接管项目数：\(projects.count)。
"""
    }

    private func generateLastActualModelInvocationResponse(_ projects: [AXProjectEntry]) -> String {
        let configuredRoute = currentSupervisorModelRouteSummary()
        let actualInvocation = lastSupervisorActualInvocationSummary()
        let verification = currentSupervisorModelVerificationSummary()
        let mismatch = currentSupervisorModelMismatchSummary()
        let transport = currentHubTransportSummary()
        return """
如果你问的是刚刚上一轮真正触发到的模型，结论先说：
\(actualInvocation)

补充一点：这条回复本身仍然是本地直答，用来读运行记录，不会为了回答这个问题再额外打一次远端模型。

以下记录只针对 Supervisor 角色；Project AI / coder / reviewer 的模型路由与最近调用彼此独立，不能混读。

当前配置的 Supervisor 首选远端模型路由：
\(configuredRoute)

当前 Hub transport:
\(transport)

当前验证状态：
\(verification)

\(mismatch.map { "当前差异提示：\n\($0)\n" } ?? "")

当前接管项目数：\(projects.count)。
"""
    }

    private func generateCapabilitySummary(_ projects: [AXProjectEntry]) -> String {
        let identity = currentSupervisorIdentityProfile()
        return """
我这边当前的主身份是 \(identity.name)。最擅长的是项目总控：看进度、找阻塞、给项目切模型、做发布前检查、跟踪心跳变化。

如果你想让我直接动手，说得像正常口语就行，比如“看看现在卡在哪”“把我的世界项目切到 5.3”“把 reviewer 改回 auto”。

如果你只是想正常聊天，也可以。天气、旅行、模型选择、日常想法这些都能聊；只是碰到需要实时信息的题目，我会尽量把不确定性讲清楚。

当前接管项目数：\(projects.count)。
"""
    }

    private func generateExecutionIntakeResponse(_ userMessage: String, _ projects: [AXProjectEntry]) -> String {
        let track = inferredExecutionTrack(for: userMessage)
        let brief = capped(userMessage, maxChars: 40)
        return """
可以。这类需求我会把它当成一个新的交付任务来收敛，不会先编造什么“只能回 JSON”之类的限制。

按你这句，我建议先走\(track)的最短交付路径，先做一个最小可运行版本。当前我理解的目标是：
\(brief)

如果你没有特殊限制，下一句只要补一个最关键的约束就够了，比如平台、是否联网、要不要排行榜；如果你想直接推进成项目，也可以直接说“按默认方案建项目”。
"""
    }

    private func generateProgressReport(_ projects: [AXProjectEntry]) -> String {
        guard !projects.isEmpty else { return "📊 暂无项目，可先让 Supervisor 创建或导入项目。" }
        var report = "📊 项目进度报告\n\n"

        for project in projects {
            let progress = calculateProgress(project)
            let runtime = runtimeStatus(for: project)
            report += "• \(project.displayName)\n"
            report += "  进度：\(progress)%\n"
            report += "  状态：\(runtime.text)\n\n"
        }

        return report
    }

    private func generateBlockerReport(_ projects: [AXProjectEntry]) -> String {
        guard !projects.isEmpty else { return "🚧 暂无项目阻塞信息。" }
        var report = "🚧 项目卡点分析\n\n"

        for project in projects {
            let blocker = (project.blockerSummary ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            report += "• \(project.displayName)\n"
            report += "  卡点：\(blocker.isEmpty ? "未发现明确阻塞" : blocker)\n"
            report += "  下一步：\((project.nextStepSummary ?? "继续当前任务"))\n\n"
        }

        return report
    }

    private func generateNextStepSuggestions(_ projects: [AXProjectEntry]) -> String {
        guard !projects.isEmpty else { return "🎯 暂无项目，可先新建项目后我会给出下一步建议。" }
        var report = "🎯 下一步建议\n\n"

        for project in projects {
            let next = (project.nextStepSummary ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            report += "• \(project.displayName)\n"
            report += "  建议：\(next.isEmpty ? "补充当前项目的目标和约束，再继续执行" : next)\n\n"
        }

        return report
    }

    private func generatePriorityRecommendation(_ projects: [AXProjectEntry]) -> String {
        guard !projects.isEmpty else { return "🎯 暂无项目可排序。" }
        var report = "🎯 优先级建议\n\n"

        let sortedProjects = projects.sorted { p1, p2 in
            calculatePriority(p1) > calculatePriority(p2)
        }

        for (index, project) in sortedProjects.enumerated() {
            let priority = calculatePriority(project)
            report += "\(index + 1). \(project.displayName) (优先级：\(priority))\n"
        }

        return report
    }

    private func generateGeneralResponse(_ userMessage: String, _ projects: [AXProjectEntry]) -> String {
        """
这句我先不替你乱解释。

如果你是想聊天，我就直接聊；如果你是想让我执行动作，通常只差一个关键约束，比如项目名、目标模型、平台，或者你是要查询现状还是直接修改。

你按平时说话的方式补一句就够了。当前接管项目数：\(projects.count)。
"""
    }

    private func inferredExecutionTrack(for userMessage: String) -> String {
        let normalized = normalizedSupervisorIntentText(userMessage)
        if containsAny(normalized, ["mac", "macos", "桌面"]) {
            return "macOS 桌面版"
        }
        if containsAny(normalized, ["ios", "iphone", "ipad"]) {
            return "iOS 版"
        }
        if containsAny(normalized, ["终端", "命令行", "cli"]) {
            return "终端版"
        }
        if containsAny(normalized, ["网页", "网站", "浏览器", "html", "web"]) {
            return "网页版"
        }
        if containsAny(normalized, ["游戏", "贪食蛇", "贪吃蛇", "snake", "game"]) {
            return "网页版"
        }
        return "最小可运行版本"
    }

    private func sanitizeSupervisorRemoteResponse(
        _ response: String,
        userMessage: String,
        projects: [AXProjectEntry]
    ) -> String {
        let trimmed = response.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return response }

        let lowered = trimmed.lowercased()
        let dangerSignals = [
            "<private",
            "-----begin private key-----",
            "authorization:",
            "set-cookie:",
            "bearer sk-",
            "ghp_",
            "gho_",
            "ghu_",
            "sk-ant-"
        ]
        if dangerSignals.contains(where: { lowered.contains($0) }) {
            return """
            远端回复包含疑似敏感或不可信内容，Supervisor 已改用本地安全兜底结果。

            \(generateFallbackResponse(userMessage))
            """
        }

        let hallucinatedGlobalClaims = [
            "我已经检查了你所有项目的完整记忆文件",
            "我已经读取了所有项目的原始邮件",
            "我已经拿到了所有项目的密钥"
        ]
        if hallucinatedGlobalClaims.contains(where: { lowered.contains($0.lowercased()) }) && !projects.isEmpty {
            return """
            远端回复超出了当前 Supervisor memory 的可见范围，已切换到本地摘要兜底结果。

            \(generateFallbackResponse(userMessage))
            """
        }

        let normalizedResponse = normalizedSupervisorIntentText(response)
        guard !normalizedResponse.isEmpty else { return response }
        if responseAppearsToFabricateRuntimeConstraints(normalizedResponse, userMessage: userMessage)
            || responseAppearsToIgnoreUserIntent(normalizedResponse) {
            return generateFallbackResponse(userMessage)
        }
        return response
    }

    private func responseAppearsToFabricateRuntimeConstraints(
        _ normalizedResponse: String,
        userMessage: String
    ) -> Bool {
        let normalizedUser = normalizedSupervisorIntentText(userMessage)
        let userExplicitlyAskedForJSON = containsAny(normalizedUser, ["json", "结构化", "machine readable"])
        if userExplicitlyAskedForJSON {
            return false
        }

        if containsAny(
            normalizedResponse,
            [
                "不能直接落地文件",
                "不能创建文件",
                "不能写文件",
                "当前我还没执行工具调用",
                "当前我还未执行工具调用",
                "cannot create files",
                "cannot write files",
                "can't create files"
            ]
        ) {
            return true
        }

        let claimsJSONOnly = containsAny(
            normalizedResponse,
            [
                "纯 json",
                "纯json",
                "json 结果",
                "json结果",
                "json-only",
                "json only"
            ]
        ) && containsAny(normalizedResponse, ["只能", "只可", "要求", "must", "only"])
        if claimsJSONOnly {
            return true
        }

        let demandsTriggerPhrase = containsAny(normalizedResponse, ["开始生成", "start generating"])
            && containsAny(normalizedResponse, ["回复我一句", "reply with", "回复一句"])
        return demandsTriggerPhrase
    }

    private func responseAppearsToIgnoreUserIntent(_ normalizedResponse: String) -> Bool {
        let signals = [
            normalizedResponse.contains("我已收到你的指令"),
            normalizedResponse.contains("作为 supervisor"),
            normalizedResponse.contains("你刚才说的是")
        ]
        return signals.filter { $0 }.count >= 2
    }

    private func naturalizeModelAssignmentResponse(
        result: ModelAssignmentResult,
        intent: DirectModelAssignmentIntent
    ) -> String {
        guard result.ok else {
            return "我试着改了，但这次没成功。\n\n\(result.message)"
        }

        let projectPhrase: String
        if intent.appliesToAllProjects {
            projectPhrase = "所有项目"
        } else if let projectRef = intent.projectRef, !projectRef.isEmpty {
            projectPhrase = "《\(projectRef)》"
        } else {
            projectPhrase = "当前项目"
        }

        let rolePhrase = naturalRolePhrase(intent.role)
        let modelPhrase = intent.modelId == "auto" ? "自动路由" : intent.modelId
        var lines: [String] = []

        if intent.appliesToAllProjects {
            lines.append("已经把\(projectPhrase)的 \(rolePhrase) 模型切到 \(modelPhrase)。")
        } else if intent.modelId == "auto" {
            lines.append("已经把\(projectPhrase)的 \(rolePhrase) 恢复到自动路由。")
        } else {
            lines.append("已经把\(projectPhrase)的 \(rolePhrase) 模型切到 \(modelPhrase)。")
        }

        if intent.usedDefaultRole {
            lines.append("你这句里没单独写角色，所以我默认按 coder 处理。")
        }

        return lines.joined(separator: "\n\n")
    }

    private func naturalRolePhrase(_ role: AXRole) -> String {
        switch role {
        case .coder:
            return "coder"
        case .coarse:
            return "coarse"
        case .refine:
            return "refine"
        case .reviewer:
            return "reviewer"
        case .advisor:
            return "advisor"
        case .supervisor:
            return "supervisor"
        }
    }

    private func calculateProgress(_ project: AXProjectEntry) -> Int {
        var progress = 55
        let runtime = runtimeStatus(for: project)
        if let state = project.currentStateSummary, !state.isEmpty { progress += 10 }
        if let next = project.nextStepSummary, !next.isEmpty { progress += 10 }
        if let blocker = project.blockerSummary, !blocker.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { progress -= 20 }
        if runtime.state == .paused { progress -= 8 }
        if project.lastOpenedAt > Date().timeIntervalSince1970 - 3600 { progress += 5 }
        return min(100, max(5, progress))
    }

    private func calculatePriority(_ project: AXProjectEntry) -> Int {
        var priority = 100 - calculateProgress(project)
        if let blocker = project.blockerSummary, !blocker.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            priority += 15
        }
        if project.lastOpenedAt > Date().timeIntervalSince1970 - 3600 {
            priority += 8
        }
        return min(100, max(1, priority))
    }

    private func buildSupervisorMemoryV1(userMessage: String) async -> SupervisorMemoryBuildInfo {
        let composition = await composeSupervisorMemoryV1(userMessage: userMessage)
        let hub = await HubIPCClient.requestMemoryContext(
            useMode: .supervisorOrchestration,
            requesterRole: .supervisor,
            projectId: nil,
            projectRoot: nil,
            displayName: "Supervisor",
            latestUser: userMessage,
            constitutionHint: composition.constitution,
            canonicalText: composition.canonical,
            observationsText: composition.observations,
            workingSetText: composition.workingSet,
            rawEvidenceText: composition.rawEvidence,
            budgets: nil,
            timeoutSec: 1.2
        )
        if let hub {
            let src = XTProjectMemoryGovernance.normalizedResolvedSource(hub.source)
            return SupervisorMemoryBuildInfo(
                text: sanitizeSupervisorOutboundPrompt(hub.text),
                source: src,
                updatedAt: Date().timeIntervalSince1970,
                projectDigests: composition.projectDigests,
                skillRegistrySnapshot: composition.skillRegistrySnapshot
            )
        }
        return SupervisorMemoryBuildInfo(
            text: sanitizeSupervisorOutboundPrompt(composition.localText),
            source: "local_fallback",
            updatedAt: Date().timeIntervalSince1970,
            projectDigests: composition.projectDigests,
            skillRegistrySnapshot: composition.skillRegistrySnapshot
        )
    }

    private func composeSupervisorMemoryV1(userMessage: String) async -> SupervisorMemoryComposition {
        let constitution = loadConstitutionOneLiner(userMessage: userMessage)
        let projects = allProjects()
        let projectDigests = collectSupervisorProjectMemoryDigests()
        let focusedSkillProject = focusedSupervisorSkillRegistryProject(projects: projects)
        let skillRegistrySnapshot: SupervisorSkillRegistrySnapshot?
        if let focusedSkillProject {
            skillRegistrySnapshot = await HubIPCClient.requestSupervisorSkillRegistrySnapshot(
                projectId: focusedSkillProject.projectId,
                projectName: focusedSkillProject.displayName
            )
        } else {
            skillRegistrySnapshot = nil
        }
        let workflowSlice = focusedSupervisorWorkflowMemorySlice(projects: projects)
        let canonical = capped(
            [
                generateProjectList(from: projectDigests),
                workflowSlice?.canonical ?? ""
            ]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n\n"),
            maxChars: 3200
        )
        let localMemoryProjectCount = projectDigests.filter { $0.source.contains("local_project_memory") }.count
        let observations = sanitizeSupervisorPromptIdentifiers(
            (recentEvents.suffix(8) + [
                "managed_projects: \(projectDigests.count)",
                "projects_with_local_memory: \(localMemoryProjectCount)",
                workflowSlice?.observation ?? ""
            ]).joined(separator: "\n")
        )
        let chatWorkingSet = messages
            .suffix(8)
            .map {
                let content = sanitizeSupervisorPromptIdentifiers(
                    capped($0.content, maxChars: 220)
                )
                return "\($0.role.rawValue): \(content)"
            }
            .joined(separator: "\n")
        let actionWorkingSet = sanitizeSupervisorPromptIdentifiers(
            generateActionLedgerSummary(maxItems: 8)
        )
        let workflowWorkingSet = sanitizeSupervisorPromptIdentifiers(
            workflowSlice?.workingSet ?? ""
        )
        let workingSet = """
\(chatWorkingSet.isEmpty ? "(none)" : chatWorkingSet)
\(actionWorkingSet.isEmpty ? "" : "\n[action_ledger]\n\(actionWorkingSet)")
\(workflowWorkingSet.isEmpty ? "" : "\n[workflow]\n\(workflowWorkingSet)")
"""
        let modelEvidence = sanitizeSupervisorPromptIdentifiers(
            capped(generateAvailableModels(), maxChars: 1400)
        )
        let skillRegistryEvidence = sanitizeSupervisorPromptIdentifiers(
            capped(skillRegistrySnapshot?.memorySummary(maxItems: 6, maxChars: 900) ?? "", maxChars: 900)
        )
        let rawEvidence = """
models:
\(modelEvidence.isEmpty ? "(none)" : modelEvidence)
\(skillRegistryEvidence.isEmpty ? "" : "\nskills_registry:\n\(skillRegistryEvidence)")
"""

        let local = """
[MEMORY_V1]
[L0_CONSTITUTION]
\(constitution)
[/L0_CONSTITUTION]

[L1_CANONICAL]
\(canonical.isEmpty ? "(none)" : canonical)
[/L1_CANONICAL]

[L2_OBSERVATIONS]
\(observations.isEmpty ? "(none)" : observations)
[/L2_OBSERVATIONS]

[L3_WORKING_SET]
\(workingSet.isEmpty ? "(none)" : workingSet)
[/L3_WORKING_SET]

[L4_RAW_EVIDENCE]
\(rawEvidence.isEmpty ? "(none)" : rawEvidence)
latest_user:
\(capped(userMessage, maxChars: 300))
[/L4_RAW_EVIDENCE]
[/MEMORY_V1]
"""

        return SupervisorMemoryComposition(
            constitution: constitution,
            canonical: canonical,
            observations: observations,
            workingSet: workingSet,
            rawEvidence: rawEvidence,
            localText: local,
            projectDigests: projectDigests,
            skillRegistrySnapshot: skillRegistrySnapshot
        )
    }

    private func focusedSupervisorSkillRegistryProject(projects: [AXProjectEntry]) -> AXProjectEntry? {
        if let taskProjectID = currentTask?.projectId,
           let taskProject = projects.first(where: { $0.projectId == taskProjectID }) {
            return taskProject
        }
        if let selectedProjectID = appModel?.selectedProjectId,
           selectedProjectID != AXProjectRegistry.globalHomeId,
           let selectedProject = projects.first(where: { $0.projectId == selectedProjectID }) {
            return selectedProject
        }
        if projects.count == 1 {
            return projects[0]
        }
        return nil
    }

    private func focusedSupervisorWorkflowMemorySlice(
        projects: [AXProjectEntry]
    ) -> SupervisorWorkflowMemorySlice? {
        guard let project = focusedSupervisorSkillRegistryProject(projects: projects),
              let ctx = appModel?.projectContext(for: project.projectId) else {
            return nil
        }
        return supervisorWorkflowMemorySlice(
            project: project,
            ctx: ctx,
            preferredJobId: currentTask?.projectId == project.projectId ? currentTask?.id : nil,
            preferredPlanId: nil,
            preferredRequestId: nil
        )
    }

    private func supervisorWorkflowState(
        project: AXProjectEntry,
        ctx: AXProjectContext,
        preferredJobId: String?,
        preferredPlanId: String?,
        preferredRequestId: String?
    ) -> (job: SupervisorJobRecord, plan: SupervisorPlanRecord?, skillCall: SupervisorSkillCallRecord?)? {
        let jobSnapshot = SupervisorProjectJobStore.load(for: ctx)
        let normalizedJobId = preferredJobId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let activeJob = jobSnapshot.jobs.first(where: { !$0.jobId.isEmpty && $0.jobId == normalizedJobId })
            ?? jobSnapshot.jobs.first
        guard let activeJob else { return nil }

        let planSnapshot = SupervisorProjectPlanStore.load(for: ctx)
        let normalizedPlanId = preferredPlanId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let activePlan = planSnapshot.plans.first(where: { !$0.planId.isEmpty && $0.planId == normalizedPlanId && $0.jobId == activeJob.jobId })
            ?? planSnapshot.plans.first(where: { $0.planId == activeJob.activePlanId && !$0.planId.isEmpty })
            ?? planSnapshot.plans.first(where: { $0.jobId == activeJob.jobId })

        let skillCallSnapshot = SupervisorProjectSkillCallStore.load(for: ctx)
        let normalizedRequestId = preferredRequestId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let activeSkillCall = skillCallSnapshot.calls.first(where: { !$0.requestId.isEmpty && $0.requestId == normalizedRequestId })
            ?? skillCallSnapshot.calls.first(where: { $0.jobId == activeJob.jobId })
            ?? skillCallSnapshot.calls.first(where: { $0.projectId == project.projectId })
        return (activeJob, activePlan, activeSkillCall)
    }

    private func supervisorWorkflowMemorySlice(
        project: AXProjectEntry,
        ctx: AXProjectContext,
        preferredJobId: String?,
        preferredPlanId: String?,
        preferredRequestId: String?
    ) -> SupervisorWorkflowMemorySlice? {
        guard let state = supervisorWorkflowState(
            project: project,
            ctx: ctx,
            preferredJobId: preferredJobId,
            preferredPlanId: preferredPlanId,
            preferredRequestId: preferredRequestId
        ) else {
            return nil
        }
        let activeJob = state.job
        let activePlan = state.plan
        let activeSkillCall = state.skillCall
        let activePlanId = (activePlan?.planId ?? activeJob.activePlanId).trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedActivePlanId = activePlanId.isEmpty ? "(none)" : activePlanId
        let activeSkillSummary = activeSkillCall.map { call in
            """
active_skill_request_id: \(call.requestId)
active_skill_id: \(call.skillId)
active_skill_step_id: \(call.stepId)
active_skill_tool_name: \(call.toolName.isEmpty ? "(none)" : call.toolName)
active_skill_required_capability: \(call.requiredCapability?.isEmpty == false ? call.requiredCapability! : "(none)")
active_skill_grant_request_id: \(call.grantRequestId?.isEmpty == false ? call.grantRequestId! : "(none)")
active_skill_grant_id: \(call.grantId?.isEmpty == false ? call.grantId! : "(none)")
active_skill_status: \(call.status.rawValue)
active_skill_result_summary: \(call.resultSummary.isEmpty ? "(none)" : call.resultSummary)
"""
        } ?? """
active_skill_request_id: (none)
active_skill_id: (none)
active_skill_step_id: (none)
active_skill_tool_name: (none)
active_skill_required_capability: (none)
active_skill_grant_request_id: (none)
active_skill_grant_id: (none)
active_skill_status: (none)
active_skill_result_summary: (none)
"""

        let canonical = """
[supervisor_workflow]
project: \(project.displayName) (\(project.projectId))
active_job_id: \(activeJob.jobId)
active_job_goal: \(activeJob.goal)
active_job_priority: \(activeJob.priority.rawValue)
active_job_status: \(activeJob.status.rawValue)
active_plan_id: \(resolvedActivePlanId)
active_plan_status: \(activePlan?.status.rawValue ?? "(none)")
active_plan_steps:
\(activePlan.map(workflowPlanStepsDigest) ?? "(none)")
\(activeSkillSummary)
[/supervisor_workflow]
"""
        let observation = "supervisor_workflow_active: project=\(project.projectId) job=\(activeJob.jobId) status=\(activeJob.status.rawValue) plan=\(activePlan?.planId ?? "(none)") steps=\(activePlan?.steps.count ?? 0) skill=\(activeSkillCall?.skillId ?? "(none)") skill_status=\(activeSkillCall?.status.rawValue ?? "(none)")"
        let workingSet = """
job \(activeJob.jobId) goal=\(activeJob.goal)
status=\(activeJob.status.rawValue) priority=\(activeJob.priority.rawValue) owner=\(activeJob.currentOwner)
plan=\(activePlan?.planId ?? "(none)") plan_status=\(activePlan?.status.rawValue ?? "(none)")
steps:
\(activePlan.map(workflowPlanStepsDigest) ?? "(none)")
active_skill:
\(activeSkillCall.map { call in
    "request_id=\(call.requestId) skill=\(call.skillId) status=\(call.status.rawValue) tool=\(call.toolName.isEmpty ? "(none)" : call.toolName) capability=\(call.requiredCapability?.isEmpty == false ? call.requiredCapability! : "(none)") grant_request_id=\(call.grantRequestId?.isEmpty == false ? call.grantRequestId! : "(none)") grant_id=\(call.grantId?.isEmpty == false ? call.grantId! : "(none)")\nsummary=\(call.resultSummary.isEmpty ? "(none)" : call.resultSummary)"
} ?? "(none)")
"""
        return SupervisorWorkflowMemorySlice(
            canonical: canonical,
            observation: observation,
            workingSet: workingSet
        )
    }

    private func workflowPlanFilteredStepsDigest(
        _ plan: SupervisorPlanRecord,
        statuses: Set<SupervisorPlanStepStatus>,
        excludingStepId: String? = nil,
        limit: Int = 4
    ) -> String {
        let excluded = excludingStepId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let rows = plan.steps
            .sorted { lhs, rhs in
                if lhs.orderIndex != rhs.orderIndex {
                    return lhs.orderIndex < rhs.orderIndex
                }
                return lhs.stepId < rhs.stepId
            }
            .filter { step in
                statuses.contains(step.status) &&
                    (excluded.isEmpty || step.stepId != excluded)
            }
            .prefix(limit)
            .map { step in
                let skill = step.skillId.trimmingCharacters(in: .whitespacesAndNewlines)
                let suffix = skill.isEmpty ? "" : " skill=\(skill)"
                return "\(step.orderIndex + 1). \(step.stepId) | \(step.status.rawValue) | \(step.kind.rawValue) | \(capped(step.title, maxChars: 120))\(suffix)"
            }
        return rows.isEmpty ? "(none)" : rows.joined(separator: "\n")
    }

    private func supervisorEventLoopWorkflowContext(
        project: AXProjectEntry,
        record: SupervisorSkillCallRecord
    ) -> String {
        guard let ctx = appModel?.projectContext(for: project.projectId),
              let state = supervisorWorkflowState(
                project: project,
                ctx: ctx,
                preferredJobId: record.jobId,
                preferredPlanId: record.planId,
                preferredRequestId: record.requestId
              ) else {
            return ""
        }

        let nextPendingSteps = state.plan.map {
            workflowPlanFilteredStepsDigest(
                $0,
                statuses: [.pending],
                excludingStepId: record.stepId
            )
        } ?? "(none)"
        let attentionSteps = state.plan.map {
            workflowPlanFilteredStepsDigest(
                $0,
                statuses: [.running, .blocked, .awaitingAuthorization],
                excludingStepId: nil
            )
        } ?? "(none)"
        let planSteps = state.plan.map(workflowPlanStepsDigest) ?? "(none)"
        let planStatus = state.plan?.status.rawValue ?? "(none)"
        let jobGoal = capped(state.job.goal, maxChars: 220)

        return """
workflow_focus:
active_job_goal=\(jobGoal.isEmpty ? "(none)" : jobGoal)
active_job_status=\(state.job.status.rawValue)
active_plan_id=\(state.plan?.planId ?? "(none)")
active_plan_status=\(planStatus)
active_plan_steps:
\(planSteps)
next_pending_steps:
\(nextPendingSteps)
attention_steps:
\(attentionSteps)
"""
    }

    private func workflowPlanStepsDigest(_ plan: SupervisorPlanRecord) -> String {
        let rows = plan.steps
            .sorted { lhs, rhs in
                if lhs.orderIndex != rhs.orderIndex {
                    return lhs.orderIndex < rhs.orderIndex
                }
                return lhs.stepId < rhs.stepId
            }
            .prefix(8)
            .map { step in
                let skill = step.skillId.trimmingCharacters(in: .whitespacesAndNewlines)
                let suffix = skill.isEmpty ? "" : " skill=\(skill)"
                return "\(step.orderIndex + 1). \(step.stepId) | \(step.status.rawValue) | \(step.kind.rawValue) | \(capped(step.title, maxChars: 120))\(suffix)"
            }
        return rows.isEmpty ? "(none)" : rows.joined(separator: "\n")
    }

    private func loadConstitutionOneLiner(userMessage: String) -> String {
        // Keep routine coding asks concise to avoid over-triggering policy-style refusals.
        if shouldUseConciseConstitutionForLowRiskRequest(userMessage) {
            return "优先给出可执行答案；保持真实透明并保护隐私。"
        }

        let fallback = "真实透明、最小化外发；仅在高风险或不可逆动作时先解释后执行；普通编程/创作请求直接给出可执行答案。"
        let url = HubPaths.baseDir()
            .appendingPathComponent("memory", isDirectory: true)
            .appendingPathComponent("ax_constitution.json")
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return fallback
        }

        if let one = obj["one_liner"] as? [String: Any] {
            let zh = (one["zh"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !zh.isEmpty { return normalizedConstitutionOneLiner(zh) }
            let en = (one["en"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !en.isEmpty { return normalizedConstitutionOneLiner(en) }
        }
        return fallback
    }

    private func normalizedConstitutionOneLiner(_ raw: String) -> String {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else {
            return "真实透明、最小化外发；仅在高风险或不可逆动作时先解释后执行；普通编程/创作请求直接给出可执行答案。"
        }

        let legacy = "真实透明、最小化外发、关键风险先解释后执行。"
        var out = t
        if out == legacy {
            out = "真实透明、最小化外发；仅在高风险或不可逆动作时先解释后执行；普通编程/创作请求直接给出可执行答案。"
        }

        let lower = out.lowercased()
        let zhRiskFocused =
            out.contains("高风险") ||
            out.contains("合规") ||
            out.contains("法律") ||
            out.contains("隐私") ||
            out.contains("安全") ||
            out.contains("伤害") ||
            out.contains("必要时拒绝") ||
            out.contains("关键风险先解释后执行")
        let enRiskFocused =
            lower.contains("high-risk") ||
            lower.contains("compliance") ||
            lower.contains("legal") ||
            lower.contains("privacy") ||
            lower.contains("safety") ||
            lower.contains("harm") ||
            lower.contains("refuse")

        let zhHasCarveout =
            out.contains("仅在高风险") ||
            out.contains("低风险") ||
            out.contains("普通编程") ||
            out.contains("普通创作") ||
            out.contains("普通请求") ||
            out.contains("直接给出可执行答案") ||
            out.contains("直接回答")
        let enHasCarveout =
            lower.contains("only for high-risk") ||
            lower.contains("normal coding") ||
            lower.contains("creative requests") ||
            lower.contains("respond directly") ||
            lower.contains("answer normal")

        if zhRiskFocused && !zhHasCarveout {
            return out + " 仅在高风险或不可逆动作时先解释后执行；普通编程/创作请求直接给出可执行答案。"
        }
        if enRiskFocused && !enHasCarveout {
            return out + " Explain first only for high-risk or irreversible actions; answer normal coding/creative requests directly."
        }
        return out
    }

    private func shouldUseConciseConstitutionForLowRiskRequest(_ userText: String) -> Bool {
        let t = userText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if t.isEmpty { return false }

        let codingSignals = [
            "写一个", "写个", "代码", "程序", "脚本", "函数", "类", "项目", "网页", "网站", "游戏", "赛车游戏",
            "write", "code", "script", "function", "class", "build", "create", "game", "app", "web"
        ]
        let riskSignals = [
            "绕过", "规避", "破解", "入侵", "提权", "钓鱼", "木马", "勒索", "盗号", "删日志",
            "违法", "犯罪", "武器", "爆炸", "毒品", "未成年人", "自杀", "自残", "伤害", "暴力",
            "法律", "合规", "隐私", "保密", "风险", "后果",
            "bypass", "circumvent", "hack", "exploit", "privilege escalation", "phishing", "malware", "ransomware",
            "illegal", "weapon", "explosive", "drugs", "minor", "suicide", "self-harm", "violence",
            "legal", "compliance", "privacy", "risk", "consequence"
        ]
        let hasCoding = codingSignals.contains(where: { t.contains($0) })
        let hasRisk = riskSignals.contains(where: { t.contains($0) })
        return hasCoding && !hasRisk
    }

    @discardableResult
    func applySupervisorJurisdictionRegistry(
        _ registry: SupervisorJurisdictionRegistry,
        persist: Bool = true,
        normalizeWithKnownProjects: Bool = true
    ) -> SupervisorJurisdictionRegistry {
        let normalized = normalizeWithKnownProjects
            ? registry.normalized(for: knownProjects())
            : registry
        supervisorJurisdictionRegistry = normalized
        if persist {
            SupervisorJurisdictionRegistryStore.save(normalized)
        }
        supervisorRecentProjectActionEvents = normalized.filteredEvents(supervisorRecentProjectActionEvents)
        supervisorMemoryProjectDigests = normalized.filteredDigests(supervisorMemoryProjectDigests)
        supervisorPortfolioSnapshot = SupervisorPortfolioSnapshotBuilder.build(from: supervisorMemoryProjectDigests)
        if supervisorMemoryUpdatedAt > 0 || !supervisorMemorySource.isEmpty {
            supervisorMemoryStatusLine = "memory=\(supervisorMemorySource) · projects=\(supervisorMemoryProjectDigests.count) · updated=\(Int(supervisorMemoryUpdatedAt))"
        }
        return normalized
    }

    private func syncSupervisorJurisdictionRegistry(with projects: [AXProjectEntry]) -> SupervisorJurisdictionRegistry {
        let normalized = supervisorJurisdictionRegistry.normalized(for: projects)
        guard normalized != supervisorJurisdictionRegistry else { return supervisorJurisdictionRegistry }
        supervisorJurisdictionRegistry = normalized
        SupervisorJurisdictionRegistryStore.save(normalized)
        supervisorRecentProjectActionEvents = normalized.filteredEvents(supervisorRecentProjectActionEvents)
        supervisorMemoryProjectDigests = normalized.filteredDigests(supervisorMemoryProjectDigests)
        supervisorPortfolioSnapshot = SupervisorPortfolioSnapshotBuilder.build(from: supervisorMemoryProjectDigests)
        return normalized
    }

    private func knownProjects() -> [AXProjectEntry] {
        let registry = appModel?.registry ?? AXProjectRegistryStore.load()
        let projects = AXProjectRegistryStore.sanitizeLoadedRegistry(registry).registry.projects
        return projects.sorted { a, b in
            if a.pinned != b.pinned { return a.pinned && !b.pinned }
            if a.lastOpenedAt != b.lastOpenedAt { return a.lastOpenedAt > b.lastOpenedAt }
            return a.displayName.localizedCaseInsensitiveCompare(b.displayName) == .orderedAscending
        }
    }

    private func allProjects() -> [AXProjectEntry] {
        let projects = knownProjects()
        let registry = syncSupervisorJurisdictionRegistry(with: projects)
        return registry.filteredProjects(projects)
    }

    private func appendRecentEvent(_ text: String) {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        recentEvents.append(cleaned)
        if recentEvents.count > 30 {
            recentEvents.removeFirst(recentEvents.count - 30)
        }
    }

    private func appendProjectActionEvent(_ event: SupervisorProjectActionEvent) {
        if let first = supervisorRecentProjectActionEvents.first,
           first.projectId == event.projectId,
           first.eventType == event.eventType,
           first.actionSummary == event.actionSummary,
           first.nextAction == event.nextAction,
           abs(first.occurredAt - event.occurredAt) <= 30 {
            return
        }

        supervisorRecentProjectActionEvents.insert(event, at: 0)
        if supervisorRecentProjectActionEvents.count > supervisorProjectActionEventMaxEntries {
            supervisorRecentProjectActionEvents.removeLast(
                supervisorRecentProjectActionEvents.count - supervisorProjectActionEventMaxEntries
            )
        }
    }

    private func deliverProjectActionNotificationIfNeeded(
        _ event: SupervisorProjectActionEvent,
        now: TimeInterval = Date().timeIntervalSince1970
    ) {
        let decision = SupervisorProjectNotificationPolicy.decide(for: event)
        let fingerprint = SupervisorProjectNotificationPolicy.dedupeFingerprint(for: event, channel: decision.channel)
        if decision.shouldDedupe,
           let last = supervisorProjectNotificationLastDeliveredAt[fingerprint],
           now - last < decision.dedupeWindowSec {
            updateProjectNotificationSnapshot(
                event: event,
                channel: decision.channel,
                status: .suppressedDuplicate,
                now: now
            )
            return
        }

        supervisorProjectNotificationLastDeliveredAt[fingerprint] = now
        if decision.shouldAddSystemMessage, let message = decision.systemMessage {
            addSystemMessage(message)
        }
        if decision.shouldOpenConversationWindow {
            conversationWindowBridge.requestOpen(reason: "project_event:\(event.projectId):\(event.eventType.rawValue)")
        }
        pushProjectActionNotificationIfNeeded(
            event: event,
            channel: decision.channel,
            dedupeKey: fingerprint
        )
        updateProjectNotificationSnapshot(
            event: event,
            channel: decision.channel,
            status: .delivered,
            now: now
        )
    }

    private func pushProjectActionNotificationIfNeeded(
        event: SupervisorProjectActionEvent,
        channel: SupervisorProjectNotificationChannel,
        dedupeKey: String
    ) {
        switch channel {
        case .interruptNow, .briefCard:
            let actionURL = supervisorActionURL(projectId: event.projectId)
            let body = """
summary=\(event.actionSummary)
next=\(event.nextAction)
why=\(event.whyItMatters)
"""
            HubIPCClient.pushNotification(
                source: "X-Terminal",
                title: event.actionTitle,
                body: body,
                dedupeKey: "x_terminal_project_action_\(dedupeKey)",
                actionURL: actionURL,
                unread: true
            )
        case .badgeOnly, .silentLog:
            return
        }
    }

    private func updateProjectNotificationSnapshot(
        event: SupervisorProjectActionEvent,
        channel: SupervisorProjectNotificationChannel,
        status: SupervisorProjectNotificationDeliveryStatus,
        now: TimeInterval
    ) {
        var snapshot = supervisorProjectNotificationSnapshot
        snapshot.updatedAt = now
        snapshot.lastDeliverySummary = SupervisorProjectNotificationPolicy.deliverySummary(
            event: event,
            channel: channel,
            status: status
        )

        if status == .suppressedDuplicate {
            snapshot.suppressedDuplicates += 1
            supervisorProjectNotificationSnapshot = snapshot
            appendProjectActionAudit(event: event, channel: channel, status: status)
            return
        }

        switch channel {
        case .interruptNow:
            snapshot.deliveredInterrupts += 1
        case .briefCard:
            snapshot.deliveredBriefs += 1
        case .badgeOnly:
            snapshot.deliveredBadges += 1
        case .silentLog:
            snapshot.mutedLogs += 1
        }
        supervisorProjectNotificationSnapshot = snapshot
        appendProjectActionAudit(event: event, channel: channel, status: status)
    }

    private func appendProjectActionAudit(
        event: SupervisorProjectActionEvent,
        channel: SupervisorProjectNotificationChannel,
        status: SupervisorProjectNotificationDeliveryStatus
    ) {
        let jurisdictionRole = supervisorJurisdictionRegistry.role(for: event.projectId).rawValue
        let grantedScope = supervisorJurisdictionRegistry
            .allowedDrillDownScopes(projectId: event.projectId)
            .sorted { $0.rank < $1.rank }
            .last?
            .rawValue
        HubIPCClient.appendSupervisorProjectActionAudit(
            eventID: event.eventId,
            projectID: event.projectId,
            projectName: event.projectName,
            eventType: event.eventType.rawValue,
            severity: event.severity.rawValue,
            actionTitle: event.actionTitle,
            actionSummary: event.actionSummary,
            whyItMatters: event.whyItMatters,
            nextAction: event.nextAction,
            occurredAtMs: Int64((event.occurredAt * 1000.0).rounded()),
            deliveryChannel: channel.rawValue,
            deliveryStatus: status.rawValue,
            jurisdictionRole: jurisdictionRole,
            grantedScope: grantedScope,
            auditRef: "project_action_audit:\(event.eventId)"
        )
    }

    @discardableResult
    private func appendActionLedger(
        action: String,
        targetRef: String,
        projectId: String?,
        projectName: String?,
        role: String?,
        modelId: String?,
        status: String,
        reasonCode: String,
        detail: String,
        verifiedAt: Double?,
        triggerSource: String? = nil
    ) -> String {
        let entry = SupervisorActionLedgerEntry(
            id: UUID().uuidString,
            createdAt: Date().timeIntervalSince1970,
            action: action,
            targetRef: targetRef,
            projectId: projectId,
            projectName: projectName,
            role: role,
            modelId: modelId,
            status: status,
            reasonCode: reasonCode,
            detail: capped(detail, maxChars: 220),
            verifiedAt: verifiedAt,
            triggerSource: triggerSource
        )
        actionLedger.append(entry)
        if actionLedger.count > actionLedgerMaxEntries {
            actionLedger.removeFirst(actionLedger.count - actionLedgerMaxEntries)
        }
        saveActionLedgerToDisk()
        return entry.id
    }

    private func updateActionLedger(
        id: String,
        status: String,
        reasonCode: String,
        detail: String,
        verifiedAt: Double?
    ) {
        guard let idx = actionLedger.lastIndex(where: { $0.id == id }) else { return }
        actionLedger[idx].status = status
        actionLedger[idx].reasonCode = reasonCode
        actionLedger[idx].detail = capped(detail, maxChars: 220)
        actionLedger[idx].verifiedAt = verifiedAt
        saveActionLedgerToDisk()
    }

    private func generateActionLedgerSummary(maxItems: Int) -> String {
        guard !actionLedger.isEmpty else { return "" }
        return actionLedger.suffix(maxItems).map { item in
            let target: String
            if let name = item.projectName, !name.isEmpty {
                target = name
            } else if let pid = item.projectId, !pid.isEmpty {
                target = "project_ref:\(compactSupervisorIdentifier(pid, fallback: "project"))"
            } else {
                target = sanitizeSupervisorPromptIdentifiers(item.targetRef)
            }
            let model = (item.modelId ?? "").isEmpty ? "-" : (item.modelId ?? "-")
            return "- \(item.action) target=\(target) role=\(item.role ?? "-") model=\(model) status=\(item.status) reason=\(item.reasonCode)"
        }.joined(separator: "\n")
    }

    private func sanitizeSupervisorOutboundPrompt(_ text: String) -> String {
        sanitizeSupervisorPromptIdentifiers(text)
    }

    private func sanitizeSupervisorPromptIdentifiers(_ text: String) -> String {
        var output = text
        output = replaceSupervisorPromptPattern(
            output,
            pattern: #"(?i)\b([0-9a-f]{8})-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b"#,
            template: "id:$1"
        )
        output = replaceSupervisorPromptPattern(
            output,
            pattern: #"(?i)\b([0-9a-f]{8})[0-9a-f]{24,120}\b"#,
            template: "hex:$1"
        )
        return output
    }

    private func replaceSupervisorPromptPattern(
        _ text: String,
        pattern: String,
        template: String
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return text
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: template)
    }

    private func compactSupervisorIdentifier(_ raw: String, fallback: String) -> String {
        let cleaned = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !cleaned.isEmpty else { return fallback }
        let compact = cleaned.filter { $0.isLetter || $0.isNumber }
        guard !compact.isEmpty else { return fallback }
        return String(compact.prefix(8))
    }

    private func loadActionLedgerFromDisk() {
        let url = actionLedgerURL()
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([SupervisorActionLedgerEntry].self, from: data) else {
            return
        }
        actionLedger = Array(decoded.suffix(actionLedgerMaxEntries))
    }

    private func saveActionLedgerToDisk() {
        let url = actionLedgerURL()
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(actionLedger) else { return }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            // Best effort only; failure should not block Supervisor flows.
        }
    }

    private func actionLedgerURL() -> URL {
        AXProjectRegistryStore.baseDir()
            .appendingPathComponent("supervisor", isDirectory: true)
            .appendingPathComponent("action_ledger.json")
    }

    private func loadEscalationPolicyFromDefaults() {
        let defaults = UserDefaults.standard

        let savedThreshold: Int = {
            guard defaults.object(forKey: escalationThresholdDefaultsKey) != nil else {
                if defaults.object(forKey: legacyEscalationThresholdDefaultsKey) != nil {
                    let legacy = defaults.integer(forKey: legacyEscalationThresholdDefaultsKey)
                    defaults.set(legacy, forKey: escalationThresholdDefaultsKey)
                    return legacy
                }
                return Self.defaultsThreshold
            }
            return defaults.integer(forKey: escalationThresholdDefaultsKey)
        }()
        let savedCooldownMinutes: Int = {
            guard defaults.object(forKey: escalationCooldownMinutesDefaultsKey) != nil else {
                if defaults.object(forKey: legacyEscalationCooldownMinutesDefaultsKey) != nil {
                    let legacy = defaults.integer(forKey: legacyEscalationCooldownMinutesDefaultsKey)
                    defaults.set(legacy, forKey: escalationCooldownMinutesDefaultsKey)
                    return legacy
                }
                return Self.defaultsCooldownMinutes
            }
            return defaults.integer(forKey: escalationCooldownMinutesDefaultsKey)
        }()

        blockerEscalationThreshold = normalizedEscalationThreshold(savedThreshold)
        blockerEscalationCooldownSec = Double(normalizedEscalationCooldownMinutes(savedCooldownMinutes)) * 60.0
    }

    private func normalizedEscalationThreshold(_ value: Int) -> Int {
        min(max(1, value), 20)
    }

    private func normalizedEscalationCooldownMinutes(_ value: Int) -> Int {
        min(max(1, value), 240)
    }

    private func restartHeartbeatTimer() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: heartbeatIntervalSec, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.emitHeartbeatIfNeeded(force: false, reason: "timer")
            }
        }
        RunLoop.main.add(heartbeatTimer!, forMode: .common)
    }

    private func restartSchedulerPollTimer() {
        schedulerPollTimer?.invalidate()
        schedulerPollTimer = Timer.scheduledTimer(withTimeInterval: schedulerPollIntervalSec, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.refreshSchedulerSnapshot(force: false)
            }
        }
        RunLoop.main.add(schedulerPollTimer!, forMode: .common)
    }

    private func refreshSchedulerSnapshot(force: Bool) async {
        if schedulerRefreshInFlight, !force {
            return
        }
        let now = Date().timeIntervalSince1970
        if !force, (now - schedulerLastRefreshAt) < max(0.8, schedulerPollIntervalSec * 0.8) {
            return
        }
        schedulerRefreshInFlight = true
        defer {
            schedulerRefreshInFlight = false
            schedulerLastRefreshAt = Date().timeIntervalSince1970
        }

        async let schedulerSnapshotRequest = HubIPCClient.requestSchedulerStatus(includeQueueItems: true, queueItemsLimit: 120)
        async let pendingGrantsRequest = HubIPCClient.requestPendingGrantRequests(projectId: nil, limit: 240)
        async let connectorIngressRequest = HubIPCClient.requestConnectorIngressReceipts(projectId: nil, limit: 240)

        let snapshot = await schedulerSnapshotRequest
        if let snapshot {
            schedulerSnapshot = snapshot
            schedulerLastSuccessAt = Date().timeIntervalSince1970
        } else if force || (schedulerLastSuccessAt > 0 && (now - schedulerLastSuccessAt) >= schedulerSnapshotStaleSec) {
            schedulerSnapshot = nil
        }

        let pendingGrants = await pendingGrantsRequest
        if let pendingGrants {
            pendingGrantSnapshot = pendingGrants
            pendingGrantLastSuccessAt = Date().timeIntervalSince1970
        } else if force || (pendingGrantLastSuccessAt > 0 && (now - pendingGrantLastSuccessAt) >= schedulerSnapshotStaleSec) {
            pendingGrantSnapshot = nil
        }

        let connectorIngress = await connectorIngressRequest
        if let connectorIngress {
            connectorIngressSnapshot = connectorIngress
            connectorIngressLastSuccessAt = Date().timeIntervalSince1970
        } else if force || (connectorIngressLastSuccessAt > 0 && (now - connectorIngressLastSuccessAt) >= schedulerSnapshotStaleSec) {
            connectorIngressSnapshot = nil
        }
        let refreshCompletedAt = Date()
        rebuildPendingHubGrantViewState(now: refreshCompletedAt.timeIntervalSince1970)
        rebuildPendingSupervisorSkillApprovalViewState()
        _ = serviceHubConnectorIngressReceipts(now: refreshCompletedAt, emitSystemMessage: false)
        _ = serviceAutomationScheduleTriggers(now: refreshCompletedAt, emitSystemMessage: false)
    }

    private func schedulerSignal(
        for projectId: String,
        now: TimeInterval = Date().timeIntervalSince1970
    ) -> (inFlight: Int, queued: Int, oldestQueuedMs: Int)? {
        let pid = projectId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pid.isEmpty else { return nil }
        guard let snapshot = schedulerSnapshot else { return nil }

        let updatedAtSec: Double = {
            let ms = max(0, snapshot.updatedAtMs)
            if ms > 0 {
                return ms / 1000.0
            }
            return schedulerLastSuccessAt
        }()
        if updatedAtSec > 0, now - updatedAtSec > schedulerSnapshotStaleSec {
            return nil
        }

        let scopeKey = "project:\(pid)"
        let inFlight = snapshot.inFlightByScope.first(where: { $0.scopeKey == scopeKey })?.count ?? 0
        let queued = snapshot.queuedByScope.first(where: { $0.scopeKey == scopeKey })?.count ?? 0
        let oldestQueuedMs = snapshot.queueItems
            .filter { $0.scopeKey == scopeKey }
            .map(\.queuedMs)
            .max() ?? (queued > 0 ? snapshot.oldestQueuedMs : 0)
        return (max(0, inFlight), max(0, queued), max(0, oldestQueuedMs))
    }

    private func emitHeartbeatIfNeeded(force: Bool, reason: String) {
        let projects = allProjects()
        guard !projects.isEmpty else { return }

        let now = Date().timeIntervalSince1970
        let queueSignals = queuedProjectSignals(for: projects, now: now)
        let permissionSignals = collectPermissionSignals(for: projects)

        let queueFingerprint = queueSignals
            .map { "\($0.project.projectId):\($0.queued):\($0.inFlight)" }
            .joined(separator: "|")
        let permissionFingerprint = permissionSignals
            .map { "\($0.projectId):\($0.kind.rawValue):\($0.summary)" }
            .joined(separator: "|")
        let laneHealthSummary = supervisorLaneHealthSnapshot?.summary ?? .empty
        let laneHealthFingerprint = supervisorLaneHealthSnapshot?.fingerprint ?? ""
        let snapshot = projects.map { p in
            [
                p.projectId,
                p.statusDigest ?? "",
                p.currentStateSummary ?? "",
                p.nextStepSummary ?? "",
                p.blockerSummary ?? "",
            ].joined(separator: "|")
        }.joined(separator: "\n") + "\n[queue]\(queueFingerprint)\n[perm]\(permissionFingerprint)\n[lane]\(laneHealthFingerprint)"

        let dueByTime = (now - lastHeartbeatAt) >= heartbeatIntervalSec
        let changed = snapshot != lastHeartbeatSnapshot
        let criticalForce = reason == "project_created" || reason == "project_removed"

        if force {
            if !criticalForce && !changed {
                return
            }
            if !criticalForce && (now - lastHeartbeatAt) < forceHeartbeatMinIntervalSec {
                return
            }
        } else if !dueByTime {
            return
        }

        let progressActions = heartbeatAutoProgressActions(
            reason: reason,
            now: Date(timeIntervalSince1970: now),
            projects: projects,
            queueSignals: queueSignals,
            permissionSignals: permissionSignals
        )
        let progressSummary = progressActions.prefix(4).map(\.summaryLine).joined(separator: "\n")

        let queueSummary = queueSignals.prefix(4).map { signal -> String in
            let waitMin = max(1, Int(ceil(Double(signal.oldestQueuedMs) / 60_000.0)))
            if signal.inFlight > 0 {
                return "• \(signal.project.displayName)：\(signal.queued) 个待执行（Hub 正在处理中）"
            }
            return "• \(signal.project.displayName)：\(signal.queued) 个排队中（最长约 \(waitMin) 分钟）"
        }.joined(separator: "\n")
        let permissionSummary = permissionSignals.prefix(4).map { signal -> String in
            let ageText: String
            if let createdAt = signal.createdAt, createdAt > 0 {
                ageText = "（\(idleDurationText(max(0, now - createdAt)))）"
            } else {
                ageText = ""
            }
            let action = signal.actionURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let actionText = action.isEmpty ? "" : "（打开：\(action)）"
            return "• \(signal.projectName)：\(signal.summary)\(ageText)\(actionText)"
        }.joined(separator: "\n")
        let laneHealthLine = supervisorLaneHealthStatusLine
        let laneHotspots = supervisorLaneHealthSnapshot?.lanes
            .filter { $0.status == .failed || $0.status == .stalled || $0.status == .blocked }
            .prefix(4)
            .map { lane in
                let reason = lane.blockedReason?.rawValue ?? "none"
                return "• \(lane.laneID)：\(lane.status.rawValue) (reason=\(reason), action=\(lane.nextActionRecommendation))"
            }.joined(separator: "\n") ?? ""
        let nextStepSummary = buildHeartbeatNextStepSummary(
            projects: projects,
            queueSignals: queueSignals,
            permissionSignals: permissionSignals,
            maxItems: 4
        )

        lastHeartbeatSnapshot = snapshot
        lastHeartbeatAt = now

        let fmt = DateFormatter()
        fmt.dateStyle = .none
        fmt.timeStyle = .short
        let time = fmt.string(from: Date(timeIntervalSince1970: now))

        let top = projects.prefix(4).map { p in
            let blocker = (p.blockerSummary ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let next = (p.nextStepSummary ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let runtime = runtimeStatus(for: p, now: now)
            if !blocker.isEmpty {
                return "• \(p.displayName)：🚧 \(capped(blocker, maxChars: 60))"
            }
            if !next.isEmpty {
                if runtime.state == .paused {
                    return "• \(p.displayName)：⏸️ \(capped(runtime.text, maxChars: 60))"
                }
                return "• \(p.displayName)：➡️ \(capped(next, maxChars: 60))"
            }
            switch runtime.state {
            case .blocked:
                return "• \(p.displayName)：🚧 \(capped(runtime.text, maxChars: 60))"
            case .paused:
                return "• \(p.displayName)：⏸️ \(capped(runtime.text, maxChars: 60))"
            case .running:
                return "• \(p.displayName)：✅ \(capped(runtime.text, maxChars: 60))"
            }
        }.joined(separator: "\n")

        let blockerProjects: [(projectId: String, blocker: String)] = projects.compactMap { project in
            let blocker = (project.blockerSummary ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !blocker.isEmpty else { return nil }
            return (project.projectId, blocker)
        }
        let blockerCount = blockerProjects.count
        let blockerFingerprint = blockerProjects
            .map { "\($0.projectId)|\($0.blocker)" }
            .joined(separator: "\n")
        let blockerSignal = evaluateBlockerSignal(
            now: now,
            blockerCount: blockerCount,
            blockerFingerprint: blockerFingerprint
        )
        let focusProjectId = progressActions.first?.projectId
            ?? blockerProjects.first?.projectId
            ?? permissionSignals.first?.projectId
            ?? queueSignals.first?.project.projectId
        let focusActionURL = permissionSignals.first?.actionURL
            ?? supervisorActionURL(projectId: focusProjectId)

        let content = """
🫀 Supervisor Heartbeat (\(time))
原因：\(reason)
项目总数：\(projects.count)
\(changed ? "变化：检测到项目状态更新" : "变化：无重大状态变化")
\(queueSignals.isEmpty ? "排队项目：0" : "排队项目：\(queueSignals.count)")
\(permissionSignals.isEmpty ? "待授权项目：0" : "待授权项目：\(permissionSignals.count)")
lane 状态：total=\(laneHealthSummary.total), running=\(laneHealthSummary.running), blocked=\(laneHealthSummary.blocked), stalled=\(laneHealthSummary.stalled), failed=\(laneHealthSummary.failed)

主动推进：
\(progressSummary.isEmpty ? "（本轮无需介入）" : progressSummary)

重点看板：
\(top)

排队态势：
\(queueSummary.isEmpty ? "（无）" : queueSummary)

权限申请：
\(permissionSummary.isEmpty ? "（无）" : permissionSummary)

Lane 健康巡检：
\(laneHealthLine)
\(laneHotspots.isEmpty ? "（无异常 lane）" : laneHotspots)

Coder 下一步建议：
\(nextStepSummary.isEmpty ? "（暂无）" : nextStepSummary)
"""

        addAssistantMessage(content)
        pushHubHeartbeatNotification(
            timeText: time,
            reason: reason,
            projectCount: projects.count,
            changed: changed,
            blockerCount: blockerCount,
            blockerSignal: blockerSignal,
            focusActionURL: focusActionURL,
            topSummary: top,
            queueSummary: queueSummary,
            permissionSummary: permissionSummary,
            progressSummary: progressSummary,
            nextStepSummary: nextStepSummary,
            queuePendingCount: queueSignals.count,
            permissionPendingCount: permissionSignals.count
        )
        speakSupervisorHeartbeatUpdate(
            reason: reason,
            changed: changed,
            projects: projects,
            blockerProjects: blockerProjects,
            blockerSignal: blockerSignal,
            permissionSignals: permissionSignals,
            queueSignals: queueSignals,
            progressActions: progressActions,
            nextStepSummary: nextStepSummary
        )
    }

    private struct BlockerSignal {
        var streak: Int
        var escalated: Bool
        var cooldownRemainingSec: Int
    }

    private enum HeartbeatAutoProgressKind: String {
        case recover
        case start
    }

    private struct HeartbeatAutoProgressAction {
        var kind: HeartbeatAutoProgressKind
        var projectId: String
        var projectName: String
        var detail: String
        var runId: String?

        var summaryLine: String {
            switch kind {
            case .recover:
                if let runId, !runId.isEmpty {
                    return "• 主动恢复：\(projectName) — \(detail)（run_id=\(runId)）"
                }
                return "• 主动恢复：\(projectName) — \(detail)"
            case .start:
                if let runId, !runId.isEmpty {
                    return "• 主动启动：\(projectName) — \(detail)（run_id=\(runId)）"
                }
                return "• 主动启动：\(projectName) — \(detail)"
            }
        }
    }

    private func shouldAttemptHeartbeatAutoProgress(reason: String) -> Bool {
        reason == "timer"
    }

    private func heartbeatAutoProgressActions(
        reason: String,
        now: Date,
        projects: [AXProjectEntry],
        queueSignals: [ProjectQueueSignal],
        permissionSignals: [ProjectPermissionSignal]
    ) -> [HeartbeatAutoProgressAction] {
        guard shouldAttemptHeartbeatAutoProgress(reason: reason) else { return [] }

        let nowSec = now.timeIntervalSince1970
        let queuedProjectIds = Set(queueSignals.map { $0.project.projectId })
        let permissionProjectIds = Set(permissionSignals.map(\.projectId))
        var actions: [HeartbeatAutoProgressAction] = []

        for project in projects {
            if actions.count >= 2 { break }
            if queuedProjectIds.contains(project.projectId) { continue }
            if permissionProjectIds.contains(project.projectId) { continue }
            if let lastActionAt = heartbeatAutoProgressLedger[project.projectId],
               nowSec - lastActionAt < heartbeatAutoProgressCooldownSec {
                continue
            }
            guard let ctx = projectContext(from: project) else { continue }
            guard let config = try? AXProjectStore.loadOrCreateConfig(for: ctx),
                  let recipe = config.activeAutomationRecipe,
                  recipe.lifecycleState == .ready else {
                continue
            }

            let recoverAuditRef = automationRuntimeAuditRef(action: "heartbeat_recover", project: project)
            if let decision = try? recoverLatestAutomationRun(
                for: project,
                ctx: ctx,
                checkpointAgeSeconds: automationLatestCheckpointAgeSeconds(for: ctx, now: nowSec),
                auditRef: recoverAuditRef,
                emitSystemMessage: false
            ), decision.decision == .resume {
                heartbeatAutoProgressLedger[project.projectId] = nowSec
                actions.append(
                    HeartbeatAutoProgressAction(
                        kind: .recover,
                        projectId: project.projectId,
                        projectName: project.displayName,
                        detail: "已恢复可继续的 automation run",
                        runId: decision.runID
                    )
                )
                continue
            }

            if automationProjectHasBlockingRun(ctx) {
                continue
            }
            let blocker = (project.blockerSummary ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !blocker.isEmpty { continue }
            if !recipe.actionGraph.isEmpty {
                let runtime = runtimeStatus(for: project, now: nowSec)
                if runtime.state == .paused,
                   (try? latestAutomationLaunchRef(for: ctx)) == nil,
                   let request = try? makeManualAutomationRunRequest(for: project, ctx: ctx),
                   let prepared = try? startAutomationRun(for: ctx, request: request, emitSystemMessage: false) {
                    heartbeatAutoProgressLedger[project.projectId] = nowSec
                    actions.append(
                        HeartbeatAutoProgressAction(
                            kind: .start,
                            projectId: project.projectId,
                            projectName: project.displayName,
                            detail: "已发起 automation kickstart",
                            runId: prepared.launchRef
                        )
                    )
                }
            }
        }

        return actions
    }

    private func automationLatestCheckpointAgeSeconds(
        for ctx: AXProjectContext,
        now: TimeInterval
    ) -> Int {
        let entries = automationRawLogEntries(for: ctx)
        let latestCreatedAt = entries
            .filter { ($0["type"] as? String) == "automation_checkpoint" }
            .compactMap { $0["created_at"] as? Double }
            .max() ?? now
        return max(0, Int(now - latestCreatedAt))
    }

    private struct ProjectQueueSignal {
        var project: AXProjectEntry
        var inFlight: Int
        var queued: Int
        var oldestQueuedMs: Int
    }

    private enum PermissionSignalKind: String {
        case toolApproval = "tool_approval"
        case hubGrant = "hub_grant"
        case supervisorSkillApproval = "supervisor_skill_approval"
    }

    private struct ProjectPermissionSignal {
        var projectId: String
        var projectName: String
        var kind: PermissionSignalKind
        var summary: String
        var createdAt: TimeInterval?
        var grantRequestId: String?
        var capability: String?
        var actionURL: String?
    }

    struct SupervisorPendingGrant: Identifiable, Equatable {
        var id: String
        var dedupeKey: String
        var grantRequestId: String
        var requestId: String
        var projectId: String
        var projectName: String
        var capability: String
        var modelId: String
        var reason: String
        var requestedTtlSec: Int
        var requestedTokenCap: Int
        var createdAt: TimeInterval?
        var actionURL: String?
        var priorityRank: Int
        var priorityReason: String
        var nextAction: String
    }

    struct SupervisorAutoGrantResolution {
        var ok: Bool
        var reasonCode: String
        var grantRequestId: String?
    }

    struct SupervisorPendingSkillApproval: Identifiable, Equatable {
        var id: String
        var requestId: String
        var projectId: String
        var projectName: String
        var jobId: String
        var planId: String
        var stepId: String
        var skillId: String
        var toolName: String
        var tool: ToolName?
        var toolSummary: String
        var reason: String
        var createdAt: TimeInterval?
        var actionURL: String?
    }

    struct XTReadyIncidentEventsExportResult {
        var ok: Bool
        var outputPath: String
        var exportedEventCount: Int
        var missingIncidentCodes: [String]
        var reason: String
    }

    struct XTReadyIncidentExportSnapshot {
        var autoExportEnabled: Bool
        var ledgerIncidentCount: Int
        var requiredIncidentEventCount: Int
        var missingIncidentCodes: [String]
        var strictE2EReady: Bool
        var strictE2EIssues: [String]
        var status: String
        var reportPath: String
    }

    struct XTReadyIncidentReadiness {
        var ready: Bool
        var issues: [String]
    }

    private struct XTReadyIncidentEventsPayload: Codable {
        var runId: String
        var schemaVersion: String
        var generatedAtMs: Int64
        var source: String
        var summary: XTReadyIncidentSummary
        var events: [XTReadyIncidentEvent]

        enum CodingKeys: String, CodingKey {
            case runId = "run_id"
            case schemaVersion = "schema_version"
            case generatedAtMs = "generated_at_ms"
            case source
            case summary
            case events
        }
    }

    private struct XTReadyIncidentSummary: Codable {
        var highRiskLaneWithoutGrant: Int
        var unauditedAutoResolution: Int
        var highRiskBypassCount: Int
        var blockedEventMissRate: Double
        var nonMessageIngressPolicyCoverage: Int

        enum CodingKeys: String, CodingKey {
            case highRiskLaneWithoutGrant = "high_risk_lane_without_grant"
            case unauditedAutoResolution = "unaudited_auto_resolution"
            case highRiskBypassCount = "high_risk_bypass_count"
            case blockedEventMissRate = "blocked_event_miss_rate"
            case nonMessageIngressPolicyCoverage = "non_message_ingress_policy_coverage"
        }
    }

    private static let xtReadyRequiredIncidentCodes: [String] = [
        LaneBlockedReason.grantPending.rawValue,
        LaneBlockedReason.awaitingInstruction.rawValue,
        LaneBlockedReason.runtimeError.rawValue,
    ]
    private static let xtReadyDefaultInjectSpecs: [XTReadyIncidentInjectSpec] = [
        XTReadyIncidentInjectSpec(
            laneID: "lane-2",
            incidentCode: LaneBlockedReason.grantPending.rawValue
        ),
        XTReadyIncidentInjectSpec(
            laneID: "lane-3",
            incidentCode: LaneBlockedReason.awaitingInstruction.rawValue
        ),
        XTReadyIncidentInjectSpec(
            laneID: "lane-4",
            incidentCode: LaneBlockedReason.runtimeError.rawValue
        ),
    ]
    private static let xtReadyExpectedEventTypes: [String: String] = [
        LaneBlockedReason.grantPending.rawValue: "supervisor.incident.grant_pending.handled",
        LaneBlockedReason.awaitingInstruction.rawValue: "supervisor.incident.awaiting_instruction.handled",
        LaneBlockedReason.runtimeError.rawValue: "supervisor.incident.runtime_error.handled",
    ]
    private static let xtReadyMaxTakeoverLatencyMs: Int64 = 2_000

    private func evaluateBlockerSignal(
        now: TimeInterval,
        blockerCount: Int,
        blockerFingerprint: String
    ) -> BlockerSignal {
        guard blockerCount > 0 else {
            blockerStreakCount = 0
            lastBlockerFingerprint = ""
            return BlockerSignal(streak: 0, escalated: false, cooldownRemainingSec: 0)
        }

        if blockerFingerprint == lastBlockerFingerprint {
            blockerStreakCount += 1
        } else {
            blockerStreakCount = 1
            lastBlockerFingerprint = blockerFingerprint
        }

        guard blockerStreakCount >= blockerEscalationThreshold else {
            return BlockerSignal(streak: blockerStreakCount, escalated: false, cooldownRemainingSec: 0)
        }

        let elapsed = now - lastBlockerEscalationAt
        if elapsed >= blockerEscalationCooldownSec {
            lastBlockerEscalationAt = now
            return BlockerSignal(streak: blockerStreakCount, escalated: true, cooldownRemainingSec: 0)
        }

        let remaining = Int(max(0, ceil(blockerEscalationCooldownSec - elapsed)))
        return BlockerSignal(streak: blockerStreakCount, escalated: false, cooldownRemainingSec: remaining)
    }

    private func queuedProjectSignals(
        for projects: [AXProjectEntry],
        now: TimeInterval
    ) -> [ProjectQueueSignal] {
        projects.compactMap { project in
            guard let signal = schedulerSignal(for: project.projectId, now: now) else { return nil }
            guard signal.queued > 0 else { return nil }
            return ProjectQueueSignal(
                project: project,
                inFlight: signal.inFlight,
                queued: signal.queued,
                oldestQueuedMs: signal.oldestQueuedMs
            )
        }.sorted { lhs, rhs in
            if lhs.oldestQueuedMs != rhs.oldestQueuedMs { return lhs.oldestQueuedMs > rhs.oldestQueuedMs }
            if lhs.queued != rhs.queued { return lhs.queued > rhs.queued }
            return lhs.project.displayName.localizedCaseInsensitiveCompare(rhs.project.displayName) == .orderedAscending
        }
    }

    private func collectPermissionSignals(
        for projects: [AXProjectEntry]
    ) -> [ProjectPermissionSignal] {
        var out: [ProjectPermissionSignal] = []
        for project in projects {
            guard let ctx = projectContext(from: project) else { continue }

            if let pending = AXPendingActionsStore.pendingToolApproval(for: ctx) {
                let preview = (pending.preview ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let reason = (pending.reason ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let detail = !preview.isEmpty ? preview : (!reason.isEmpty ? reason : "待确认工具操作")
                out.append(
                    ProjectPermissionSignal(
                        projectId: project.projectId,
                        projectName: project.displayName,
                        kind: .toolApproval,
                        summary: "等待你审批工具：\(capped(detail, maxChars: 66))",
                        createdAt: pending.createdAt,
                        grantRequestId: nil,
                        capability: nil,
                        actionURL: supervisorActionURL(projectId: project.projectId)
                    )
                )
            }
        }

        out.append(contentsOf: supervisorPendingSkillApprovalSignals(for: projects))
        out.append(contentsOf: hubPendingGrantSignals(for: projects))

        return out.sorted { lhs, rhs in
            let lt = lhs.createdAt ?? 0
            let rt = rhs.createdAt ?? 0
            if lt != rt { return lt < rt }
            if lhs.projectName != rhs.projectName {
                return lhs.projectName.localizedCaseInsensitiveCompare(rhs.projectName) == .orderedAscending
            }
            return lhs.kind.rawValue < rhs.kind.rawValue
        }
    }

    private func hasFreshPendingGrantSnapshot(now: TimeInterval) -> Bool {
        guard let snapshot = pendingGrantSnapshot else { return false }
        let updatedAtSec = snapshot.updatedAtMs > 0 ? snapshot.updatedAtMs / 1000.0 : pendingGrantLastSuccessAt
        guard updatedAtSec > 0 else { return false }
        return now - updatedAtSec <= schedulerSnapshotStaleSec
    }

    private func rebuildPendingHubGrantViewState(now: TimeInterval) {
        let projects = allProjects()
        hasFreshPendingHubGrantSnapshot = hasFreshPendingGrantSnapshot(now: now)
        pendingHubGrants = normalizedPendingHubGrants(
            projects: projects,
            allowStaleSnapshot: false,
            now: now
        )

        if let snapshot = pendingGrantSnapshot {
            pendingHubGrantSource = snapshot.source.trimmingCharacters(in: .whitespacesAndNewlines)
            let updatedAtSec = snapshot.updatedAtMs > 0 ? snapshot.updatedAtMs / 1000.0 : pendingGrantLastSuccessAt
            pendingHubGrantUpdatedAt = max(0, updatedAtSec)
        } else {
            pendingHubGrantSource = ""
            pendingHubGrantUpdatedAt = 0
            pendingHubGrants = []
        }

        if pendingHubGrantActionsInFlight.isEmpty {
            return
        }
        let activeGrantIds = Set(pendingHubGrants.map(\.grantRequestId))
        pendingHubGrantActionsInFlight = Set(pendingHubGrantActionsInFlight.filter { activeGrantIds.contains($0) })
    }

    private func rebuildPendingSupervisorSkillApprovalViewState() {
        pendingSupervisorSkillApprovals = normalizedPendingSupervisorSkillApprovals(projects: allProjects())
    }

    private func normalizedPendingSupervisorSkillApprovals(
        projects: [AXProjectEntry]
    ) -> [SupervisorPendingSkillApproval] {
        guard let appModel else { return [] }
        var approvals: [SupervisorPendingSkillApproval] = []

        for project in projects {
            guard let ctx = appModel.projectContext(for: project.projectId) else { continue }
            let snapshot = SupervisorProjectSkillCallStore.load(for: ctx)
            for record in snapshot.calls {
                guard record.status == .awaitingAuthorization else { continue }
                let capability = record.requiredCapability?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !capability.isEmpty {
                    continue
                }

                let toolCall = resolvedSupervisorToolCallForRecord(record)
                let tool = toolCall?.tool
                approvals.append(
                    SupervisorPendingSkillApproval(
                        id: "skill:\(record.requestId)",
                        requestId: record.requestId,
                        projectId: record.projectId,
                        projectName: project.displayName,
                        jobId: record.jobId,
                        planId: record.planId,
                        stepId: record.stepId,
                        skillId: record.skillId,
                        toolName: record.toolName,
                        tool: tool,
                        toolSummary: pendingSupervisorSkillToolSummary(record: record, toolCall: toolCall),
                        reason: pendingSupervisorSkillApprovalReason(record: record),
                        createdAt: record.createdAtMs > 0 ? Double(record.createdAtMs) / 1000.0 : nil,
                        actionURL: supervisorActionURL(projectId: project.projectId)
                    )
                )
            }
        }

        return approvals.sorted { lhs, rhs in
            let lt = lhs.createdAt ?? 0
            let rt = rhs.createdAt ?? 0
            if lt != rt { return lt < rt }
            if lhs.projectName != rhs.projectName {
                return lhs.projectName.localizedCaseInsensitiveCompare(rhs.projectName) == .orderedAscending
            }
            if lhs.skillId != rhs.skillId {
                return lhs.skillId.localizedCaseInsensitiveCompare(rhs.skillId) == .orderedAscending
            }
            return lhs.requestId.localizedCaseInsensitiveCompare(rhs.requestId) == .orderedAscending
        }
    }

    private func supervisorPendingSkillApprovalSignals(
        for projects: [AXProjectEntry]
    ) -> [ProjectPermissionSignal] {
        normalizedPendingSupervisorSkillApprovals(projects: projects).map { approval in
            ProjectPermissionSignal(
                projectId: approval.projectId,
                projectName: approval.projectName,
                kind: .supervisorSkillApproval,
                summary: "等待 Supervisor 审批技能：\(capped(approval.skillId, maxChars: 40))",
                createdAt: approval.createdAt,
                grantRequestId: approval.requestId,
                capability: nil,
                actionURL: approval.actionURL
            )
        }
    }

    private func pendingSupervisorSkillToolSummary(
        record: SupervisorSkillCallRecord,
        toolCall: ToolCall?
    ) -> String {
        guard let toolCall else {
            return record.toolName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? record.skillId
                : record.toolName
        }

        switch toolCall.tool {
        case .read_file, .write_file:
            if let path = toolCall.args["path"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
               !path.isEmpty {
                return path
            }
        case .run_command:
            if let command = toolCall.args["command"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
               !command.isEmpty {
                return capped(command, maxChars: 72)
            }
        case .search:
            if let pattern = toolCall.args["pattern"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
               !pattern.isEmpty {
                return pattern
            }
        case .web_search:
            if let query = toolCall.args["query"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
               !query.isEmpty {
                return query
            }
        case .web_fetch, .browser_read, .deviceBrowserControl:
            if let url = toolCall.args["url"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
               !url.isEmpty {
                return url
            }
            if let action = toolCall.args["action"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
               !action.isEmpty {
                return action
            }
        default:
            break
        }

        let toolName = toolCall.tool.rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return toolName.isEmpty ? record.skillId : toolName
    }

    private func pendingSupervisorSkillApprovalReason(record: SupervisorSkillCallRecord) -> String {
        let summary = record.resultSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !summary.isEmpty {
            return summary
        }
        return "waiting for local governed approval"
    }

    private func normalizedPendingHubGrants(
        projects: [AXProjectEntry],
        allowStaleSnapshot: Bool,
        now: TimeInterval
    ) -> [SupervisorPendingGrant] {
        guard let snapshot = pendingGrantSnapshot else { return [] }
        if !allowStaleSnapshot, !hasFreshPendingGrantSnapshot(now: now) {
            return []
        }

        let projectsById = Dictionary(uniqueKeysWithValues: projects.map { ($0.projectId, $0.displayName) })
        var deduped: [String: SupervisorPendingGrant] = [:]

        for item in snapshot.items {
            let status = item.status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let decision = item.decision.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if status != "pending", decision != "queued" {
                continue
            }

            let projectId = item.projectId.trimmingCharacters(in: .whitespacesAndNewlines)
            if projectId.isEmpty {
                continue
            }

            let grantId = item.grantRequestId.trimmingCharacters(in: .whitespacesAndNewlines)
            let reqId = item.requestId.trimmingCharacters(in: .whitespacesAndNewlines)
            let capability = item.capability.trimmingCharacters(in: .whitespacesAndNewlines)
            let modelId = item.modelId.trimmingCharacters(in: .whitespacesAndNewlines)
            let reason = item.reason.trimmingCharacters(in: .whitespacesAndNewlines)
            let displayName = projectsById[projectId] ?? projectId
            let createdAt = item.createdAtMs > 0 ? item.createdAtMs / 1000.0 : nil
            let stableId = stablePendingGrantKey(
                grantRequestId: grantId,
                requestId: reqId,
                projectId: projectId,
                capability: capability,
                createdAtMs: item.createdAtMs
            )

            let candidate = SupervisorPendingGrant(
                id: stableId,
                dedupeKey: stableId,
                grantRequestId: grantId,
                requestId: reqId,
                projectId: projectId,
                projectName: displayName,
                capability: capability,
                modelId: modelId,
                reason: reason,
                requestedTtlSec: max(0, item.requestedTtlSec),
                requestedTokenCap: max(0, item.requestedTokenCap),
                createdAt: createdAt,
                actionURL: supervisorActionURL(
                    projectId: projectId,
                    grantRequestId: grantId.isEmpty ? nil : grantId,
                    capability: capability.isEmpty ? nil : capability
                ),
                priorityRank: pendingGrantPriority(capability: capability) + 1,
                priorityReason: pendingGrantPriorityReason(capability: capability),
                nextAction: pendingGrantNextAction(capability: capability, modelId: modelId, reason: reason)
            )

            guard let existing = deduped[stableId] else {
                deduped[stableId] = candidate
                continue
            }
            deduped[stableId] = preferredPendingGrantCandidate(existing: existing, candidate: candidate)
        }

        return deduped.values.sorted { lhs, rhs in
            let lp = pendingGrantPriority(capability: lhs.capability)
            let rp = pendingGrantPriority(capability: rhs.capability)
            if lp != rp { return lp < rp }

            let lt = lhs.createdAt ?? 0
            let rt = rhs.createdAt ?? 0
            if lt != rt { return lt < rt }

            if lhs.projectName != rhs.projectName {
                return lhs.projectName.localizedCaseInsensitiveCompare(rhs.projectName) == .orderedAscending
            }
            if lhs.projectId != rhs.projectId {
                return lhs.projectId.localizedCaseInsensitiveCompare(rhs.projectId) == .orderedAscending
            }

            let lid = lhs.grantRequestId.isEmpty ? lhs.id : lhs.grantRequestId
            let rid = rhs.grantRequestId.isEmpty ? rhs.id : rhs.grantRequestId
            return lid.localizedCaseInsensitiveCompare(rid) == .orderedAscending
        }
    }

    private func stablePendingGrantKey(
        grantRequestId: String,
        requestId: String,
        projectId: String,
        capability: String,
        createdAtMs: Double
    ) -> String {
        let gid = grantRequestId.trimmingCharacters(in: .whitespacesAndNewlines)
        if !gid.isEmpty { return "grant:\(gid)" }

        let rid = requestId.trimmingCharacters(in: .whitespacesAndNewlines)
        if !rid.isEmpty { return "request:\(rid)" }

        let cap = capability.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let createdAt = createdAtMs > 0 ? String(Int(createdAtMs)) : "0"
        return "synthetic:\(projectId.lowercased())|\(cap)|\(createdAt)"
    }

    private func pendingGrantPriority(capability: String) -> Int {
        let token = capability.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if token.contains("web_fetch") || token.contains("web.fetch") {
            return 0
        }
        if token.contains("ai_generate_paid") || token.contains("ai.generate.paid") {
            return 0
        }
        if token.contains("ai_generate_local") || token.contains("ai.generate.local") {
            return 1
        }
        return 2
    }

    private func pendingGrantPriorityReason(capability: String) -> String {
        let token = capability.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if token.contains("web_fetch") || token.contains("web.fetch") {
            return "涉及联网能力，需先确认来源与访问范围。"
        }
        if token.contains("ai_generate_paid") || token.contains("ai.generate.paid") {
            return "涉及付费额度，优先处理可减少排队与成本滞留。"
        }
        if token.contains("ai_generate_local") || token.contains("ai.generate.local") {
            return "本地能力风险相对较低，可在高风险授权后处理。"
        }
        return "能力类型不明确，建议先核对权限边界。"
    }

    private func pendingGrantNextAction(capability: String, modelId: String, reason: String) -> String {
        let token = capability.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if token.contains("web_fetch") || token.contains("web.fetch") {
            return "先 Open 核对目标域名，再按最小权限 Approve 或 Deny。"
        }
        if token.contains("ai_generate_paid") || token.contains("ai.generate.paid") {
            if modelId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "先补齐 model_id 或降级到本地模型后再审批。"
            }
            return "确认预算后优先审批，避免付费任务长时间阻塞。"
        }
        if !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "根据 reason 核对业务必要性后再执行审批。"
        }
        return "先核对请求上下文，再执行 Approve/Deny。"
    }

    private func preferredPendingGrantCandidate(
        existing: SupervisorPendingGrant,
        candidate: SupervisorPendingGrant
    ) -> SupervisorPendingGrant {
        var winner = existing
        if winner.projectName == winner.projectId,
           candidate.projectName != candidate.projectId {
            winner.projectName = candidate.projectName
        }
        if winner.capability.isEmpty, !candidate.capability.isEmpty {
            winner.capability = candidate.capability
        }
        if winner.modelId.isEmpty, !candidate.modelId.isEmpty {
            winner.modelId = candidate.modelId
        }
        if winner.reason.isEmpty, !candidate.reason.isEmpty {
            winner.reason = candidate.reason
        }
        if winner.grantRequestId.isEmpty, !candidate.grantRequestId.isEmpty {
            winner.grantRequestId = candidate.grantRequestId
        }
        if winner.requestId.isEmpty, !candidate.requestId.isEmpty {
            winner.requestId = candidate.requestId
        }
        if winner.createdAt == nil, let createdAt = candidate.createdAt {
            winner.createdAt = createdAt
        }
        if winner.actionURL == nil, let actionURL = candidate.actionURL {
            winner.actionURL = actionURL
        }
        if winner.priorityReason.isEmpty, !candidate.priorityReason.isEmpty {
            winner.priorityReason = candidate.priorityReason
        }
        if winner.nextAction.isEmpty, !candidate.nextAction.isEmpty {
            winner.nextAction = candidate.nextAction
        }
        winner.priorityRank = min(max(1, winner.priorityRank), max(1, candidate.priorityRank))
        return winner
    }

    private func hubPendingGrantSignals(
        for projects: [AXProjectEntry]
    ) -> [ProjectPermissionSignal] {
        let projectsById = Dictionary(uniqueKeysWithValues: projects.map { ($0.projectId, $0) })
        var out: [ProjectPermissionSignal] = []

        for grant in pendingHubGrants {
            guard let project = projectsById[grant.projectId] else { continue }

            let capabilityText = grantCapabilityText(capability: grant.capability, modelId: grant.modelId)
            var summary = "等待 Hub 授权：\(capabilityText)"
            let reason = grant.reason.trimmingCharacters(in: .whitespacesAndNewlines)
            if !reason.isEmpty {
                summary += "（\(capped(reason, maxChars: 48))）"
            }

            out.append(
                ProjectPermissionSignal(
                    projectId: project.projectId,
                    projectName: project.displayName,
                    kind: .hubGrant,
                    summary: summary,
                    createdAt: grant.createdAt,
                    grantRequestId: grant.grantRequestId.isEmpty ? nil : grant.grantRequestId,
                    capability: grant.capability.isEmpty ? nil : grant.capability,
                    actionURL: grant.actionURL
                )
            )
        }

        return out
    }

    private func grantCapabilityText(capability: String, modelId: String) -> String {
        let cap = capability.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = cap.lowercased()
        if lowered.contains("web_fetch") || lowered.contains("web.fetch") {
            return "联网访问（web_fetch）"
        }
        if lowered.contains("ai_generate_paid") || lowered.contains("ai.generate.paid") {
            if modelId.isEmpty { return "付费模型调用" }
            return "付费模型调用（\(modelId)）"
        }
        if lowered.contains("ai_generate_local") || lowered.contains("ai.generate.local") {
            if modelId.isEmpty { return "本地模型调用" }
            return "本地模型调用（\(modelId)）"
        }
        if cap.isEmpty { return "高风险能力" }
        return cap
    }

    private func buildHeartbeatNextStepSummary(
        projects: [AXProjectEntry],
        queueSignals: [ProjectQueueSignal],
        permissionSignals: [ProjectPermissionSignal],
        maxItems: Int
    ) -> String {
        let maxCount = max(1, maxItems)
        let queueByProjectId = Dictionary(uniqueKeysWithValues: queueSignals.map { ($0.project.projectId, $0) })
        let orderedProjects = projects.sorted { p1, p2 in
            calculatePriority(p1) > calculatePriority(p2)
        }

        var lines: [String] = []
        var includedProjectIds = Set<String>()
        var rank = 1

        for signal in permissionSignals {
            if lines.count >= maxCount { break }
            let action = signal.actionURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let actionSuffix = action.isEmpty ? "" : "（打开：\(action)）"
            lines.append("\(rank). 先处理授权：\(signal.projectName) — \(capped(signal.summary, maxChars: 72))\(actionSuffix)")
            includedProjectIds.insert(signal.projectId)
            rank += 1
        }

        for queue in queueSignals {
            if lines.count >= maxCount { break }
            if includedProjectIds.contains(queue.project.projectId) { continue }
            let mins = max(1, Int(ceil(Double(queue.oldestQueuedMs) / 60_000.0)))
            lines.append("\(rank). 关注排队：\(queue.project.displayName) — 已排队 \(mins) 分钟，建议先清队列")
            includedProjectIds.insert(queue.project.projectId)
            rank += 1
        }

        for project in orderedProjects {
            if lines.count >= maxCount { break }
            if includedProjectIds.contains(project.projectId) { continue }
            let next = (project.nextStepSummary ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !next.isEmpty {
                lines.append("\(rank). 常规推进：\(project.displayName) — \(capped(next, maxChars: 72))")
            } else if let queue = queueByProjectId[project.projectId] {
                let mins = max(1, Int(ceil(Double(queue.oldestQueuedMs) / 60_000.0)))
                lines.append("\(rank). 常规推进：\(project.displayName) — 等待 Hub 排队（约 \(mins) 分钟）")
            } else {
                lines.append("\(rank). 常规推进：\(project.displayName) — 继续当前任务并在完成后同步摘要")
            }
            includedProjectIds.insert(project.projectId)
            rank += 1
        }

        return lines.joined(separator: "\n")
    }

    private func projectContext(from project: AXProjectEntry) -> AXProjectContext? {
        let raw = project.rootPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        let expanded = NSString(string: raw).expandingTildeInPath
        return AXProjectContext(root: URL(fileURLWithPath: expanded, isDirectory: true))
    }

    private func firstTagContent(in text: String, tag: String) -> String? {
        let pattern = "\\[\(tag)\\](.*?)\\[/\(tag)\\]"
        guard let range = text.range(of: pattern, options: .regularExpression) else { return nil }
        let raw = String(text[range])
        return raw
            .replacingOccurrences(of: "[\(tag)]", with: "")
            .replacingOccurrences(of: "[/\(tag)]", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func replacingTaggedSection(in text: String, tag: String, with replacement: String) -> String {
        let pattern = "\\[\(tag)\\](.*?)\\[/\(tag)\\]"
        guard let range = text.range(of: pattern, options: .regularExpression) else { return text }
        return text.replacingCharacters(in: range, with: replacement)
    }

    private func capped(_ text: String, maxChars: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxChars else { return trimmed }
        let idx = trimmed.index(trimmed.startIndex, offsetBy: maxChars)
        return String(trimmed[..<idx]) + "…"
    }

    private func runtimeStatus(
        for project: AXProjectEntry,
        now: TimeInterval = Date().timeIntervalSince1970
    ) -> (state: ProjectRuntimeState, text: String) {
        let blocker = (project.blockerSummary ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !blocker.isEmpty {
            return (.blocked, "阻塞中")
        }

        if let signal = schedulerSignal(for: project.projectId, now: now) {
            if signal.inFlight > 0 {
                if signal.queued > 0 {
                    return (.running, "进行中（Hub 执行中，另有 \(signal.queued) 个请求排队）")
                }
                return (.running, "进行中（Hub 执行中）")
            }
            if signal.queued > 0 {
                let mins = max(1, Int(ceil(Double(signal.oldestQueuedMs) / 60_000.0)))
                return (.paused, "排队中（等待 Hub 执行，最长约 \(mins) 分钟）")
            }
        }

        let state = (project.currentStateSummary ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let digest = (project.statusDigest ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = state.isEmpty ? digest : state
        let lowered = candidate.lowercased()

        if containsAny(lowered, ["暂停", "等待", "待命", "idle", "paused", "waiting"]) {
            return (.paused, candidate.isEmpty ? "暂停中" : candidate)
        }
        if containsAny(lowered, ["完成", "done", "completed", "finished"]) {
            return (.running, candidate.isEmpty ? "已完成" : candidate)
        }

        let lastActivity = max(project.lastSummaryAt ?? 0, project.lastEventAt ?? 0)
        if lastActivity > 0 {
            let idleSec = max(0, now - lastActivity)
            if idleSec >= projectPausedAfterIdleSec {
                return (.paused, "暂停中（\(idleDurationText(idleSec))）")
            }
        }

        if candidate.isEmpty {
            return (.running, "进行中")
        }
        return (.running, candidate)
    }

    func processSupervisorResponseForTesting(
        _ response: String,
        userMessage: String,
        triggerSource: String = SupervisorCommandTriggerSource.userTurn.rawValue
    ) -> String {
        processSupervisorCommands(
            response,
            userMessage: userMessage,
            triggerSource: SupervisorCommandTriggerSource.parse(triggerSource)
        )
    }

    func directSupervisorReplyIfApplicableForTesting(_ userMessage: String) -> String? {
        directSupervisorReplyIfApplicable(userMessage, projects: allProjects())
    }

    func directSupervisorActionIfApplicableForTesting(_ userMessage: String) -> String? {
        directSupervisorActionIfApplicable(userMessage, projects: allProjects())
    }

    func sanitizedSupervisorRemoteResponseForTesting(_ response: String, userMessage: String) -> String {
        sanitizeSupervisorRemoteResponse(response, userMessage: userMessage, projects: allProjects())
    }

    func buildSupervisorMemoryV1ForTesting(_ userMessage: String) async -> String {
        let info = await buildSupervisorMemoryV1(userMessage: userMessage)
        return info.text
    }

    func supervisorMemoryDigestForTesting(_ project: AXProjectEntry) -> SupervisorMemoryProjectDigest {
        supervisorMemoryDigest(project)
    }

    func buildSupervisorLocalMemoryV1ForTesting(_ userMessage: String) async -> String {
        let composition = await composeSupervisorMemoryV1(userMessage: userMessage)
        return composition.localText
    }

    func supervisorSkillRegistrySnapshotForTesting(_ userMessage: String) async -> SupervisorSkillRegistrySnapshot? {
        let composition = await composeSupervisorMemoryV1(userMessage: userMessage)
        return composition.skillRegistrySnapshot
    }

    func setSupervisorNetworkAccessRequestOverrideForTesting(
        _ override: (@Sendable (URL, Int, String?) async -> HubIPCClient.NetworkAccessResult)?
    ) {
        supervisorNetworkAccessRequestOverride = override
    }

    func setSupervisorToolExecutorOverrideForTesting(
        _ override: (@Sendable (ToolCall, URL) async throws -> ToolResult)?
    ) {
        supervisorToolExecutorOverride = override
    }

    func setSupervisorEventLoopResponseOverrideForTesting(
        _ override: (@Sendable (String, String) async -> String)?
    ) {
        supervisorEventLoopResponseOverride = override
    }

    func waitForSupervisorSkillDispatchForTesting() async {
        let tasks = Array(supervisorSkillExecutionTasks.values)
        for task in tasks {
            _ = await task.value
        }
    }

    func waitForSupervisorEventLoopForTesting() async {
        while true {
            if let task = supervisorEventLoopTask {
                _ = await task.value
                continue
            }
            if pendingSupervisorEventLoopTrigger != nil {
                await Task.yield()
                continue
            }
            break
        }
    }

    func completePendingHubGrantActionForTesting(
        grant: SupervisorPendingGrant,
        approve: Bool,
        result: HubIPCClient.PendingGrantActionResult
    ) async {
        let grantId = grant.grantRequestId.trimmingCharacters(in: .whitespacesAndNewlines)
        if !grantId.isEmpty {
            pendingHubGrantActionsInFlight.insert(grantId)
        }
        await completePendingHubGrantAction(
            grantId: grantId,
            grant: grant,
            approve: approve,
            result: result
        )
    }

    @discardableResult
    func runHeartbeatAutoProgressForTesting(
        reason: String = "timer",
        now: Date = Date()
    ) -> [String] {
        let projects = allProjects()
        let queueSignals = queuedProjectSignals(for: projects, now: now.timeIntervalSince1970)
        let permissionSignals = collectPermissionSignals(for: projects)
        return heartbeatAutoProgressActions(
            reason: reason,
            now: now,
            projects: projects,
            queueSignals: queueSignals,
            permissionSignals: permissionSignals
        ).map(\.summaryLine)
    }

    func sanitizedSupervisorOutboundPromptForTesting(_ text: String) -> String {
        sanitizeSupervisorOutboundPrompt(text)
    }

    func recordSupervisorReplyExecutionForTesting(mode: String, actualModelId: String?) {
        let resolved = SupervisorReplyExecutionMode(rawValue: mode) ?? .idle
        recordSupervisorReplyExecution(
            mode: resolved,
            actualModelId: actualModelId,
            requestedModelId: nil,
            failureReasonCode: nil
        )
    }

    func strictSupervisorRemoteModelMismatchResponseForTesting(
        preferredModelId: String?,
        actualModelId: String?
    ) -> String? {
        strictSupervisorRemoteModelMismatchResponse(
            preferredModelId: preferredModelId,
            actualModelId: actualModelId
        )
    }

    private func currentPreferredModelID(for role: AXRole) -> String? {
        if let appModel {
            let configured = appModel.settingsStore.settings.assignment(for: role).model?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let configured, !configured.isEmpty {
                return configured
            }
        }
        return modelManager.getPreferredModel(for: role)
    }

    private func currentSupervisorPromptPreferences() -> SupervisorPromptPreferences {
        (appModel?.settingsStore.settings.supervisorPrompt ?? .default()).normalized()
    }

    private func currentSupervisorIdentityProfile() -> SupervisorIdentityProfile {
        SupervisorIdentityProfile.default().applying(currentSupervisorPromptPreferences())
    }

    private func recordSupervisorReplyExecution(
        mode: SupervisorReplyExecutionMode,
        actualModelId: String?,
        requestedModelId: String? = nil,
        failureReasonCode: String? = nil
    ) {
        lastSupervisorReplyExecutionMode = mode.rawValue
        let trimmedActual = actualModelId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let trimmedRequested = requestedModelId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let normalizedFailure = normalizedSupervisorFailureReasonCode(failureReasonCode)
        switch mode {
        case .remoteModel:
            lastSupervisorActualModelId = trimmedActual
            lastSupervisorRequestedModelId = trimmedRequested
            lastSupervisorRemoteFailureReasonCode = ""
        case .idle:
            lastSupervisorActualModelId = ""
            lastSupervisorRequestedModelId = ""
            lastSupervisorRemoteFailureReasonCode = ""
        case .localFallbackAfterRemoteError:
            lastSupervisorActualModelId = trimmedActual
            if !trimmedRequested.isEmpty {
                lastSupervisorRequestedModelId = trimmedRequested
            }
            lastSupervisorRemoteFailureReasonCode = normalizedFailure
        case .localPreflight, .localDirectReply, .localDirectAction:
            break
        }
    }

    private func lastSupervisorActualInvocationSummary() -> String {
        let actualModelId = lastSupervisorActualModelId.trimmingCharacters(in: .whitespacesAndNewlines)
        let requestedModelId = lastSupervisorRequestedModelId.trimmingCharacters(in: .whitespacesAndNewlines)
        let failureReason = displayedSupervisorFailureReason(lastSupervisorRemoteFailureReasonCode)
        if let mismatch = currentSupervisorModelMismatchSummary(),
           !actualModelId.isEmpty {
            return "最近一次实际执行没有按当前配置模型命中；实际执行的是：\(actualModelId)\n\n\(mismatch)"
        }
        switch SupervisorReplyExecutionMode(rawValue: lastSupervisorReplyExecutionMode) ?? .idle {
        case .remoteModel:
            if actualModelId.isEmpty {
                if !requestedModelId.isEmpty {
                    return "最近一次 Supervisor 远端调用已经发生，首选模型是 \(requestedModelId)，但运行层没有回传明确的 model_id。"
                }
                return "最近一次远端调用已经发生，但运行层没有回传明确的 model_id。"
            }
            return "最近一次 Supervisor 远端调用实际返回的 model_id 是：\(actualModelId)"
        case .localPreflight:
            return "最近一次回复属于本地预检路径，没有远端模型调用。"
        case .localDirectReply:
            return "最近一次回复属于本地直答路径，没有远端模型调用。"
        case .localDirectAction:
            return "最近一次回复属于本地直行动作路径，没有远端模型调用。"
        case .localFallbackAfterRemoteError:
            if actualModelId.isEmpty {
                if !requestedModelId.isEmpty, !failureReason.isEmpty {
                    return "最近一次 Supervisor 远端尝试首选 \(requestedModelId)，但因 \(failureReason) 失败，随后走了本地兜底；没有拿到可确认的实际 model_id。"
                }
                if !requestedModelId.isEmpty {
                    return "最近一次 Supervisor 远端尝试首选 \(requestedModelId)，但这轮失败后走了本地兜底；没有拿到可确认的实际 model_id。"
                }
                return "最近一次尝试调用远端模型时失败，随后走了本地兜底；没有拿到可确认的实际 model_id。"
            }
            if !requestedModelId.isEmpty, !failureReason.isEmpty {
                return "最近一次 Supervisor 远端尝试首选 \(requestedModelId)，运行层返回的 actual model_id 是 \(actualModelId)，但该轮最终因 \(failureReason) 被本地兜底接管。"
            }
            if !requestedModelId.isEmpty {
                return "最近一次 Supervisor 远端尝试首选 \(requestedModelId)，但这轮最终回复被本地回退接管；实际拿到的 model_id 是：\(actualModelId)"
            }
            return "最近一次已经触发过远端调用，但这轮最终回复被本地回退接管；实际拿到的 model_id 是：\(actualModelId)"
        case .idle:
            return "当前还没有可用的调用记录。"
        }
    }

    private func currentSupervisorModelVerificationSummary() -> String {
        let actualModelId = lastSupervisorActualModelId.trimmingCharacters(in: .whitespacesAndNewlines)
        let requestedModelId = lastSupervisorRequestedModelId.trimmingCharacters(in: .whitespacesAndNewlines)
        let failureReason = displayedSupervisorFailureReason(lastSupervisorRemoteFailureReasonCode)
        if currentSupervisorModelMismatchSummary() != nil, !actualModelId.isEmpty {
            return "未按配置模型执行。当前已记录到一次成功回复，但实际模型与当前配置不一致。"
        }
        switch SupervisorReplyExecutionMode(rawValue: lastSupervisorReplyExecutionMode) ?? .idle {
        case .remoteModel:
            if actualModelId.isEmpty {
                if !requestedModelId.isEmpty {
                    return "已触发过 Supervisor 远端调用，首选模型是 \(requestedModelId)，但运行层没有回传明确 model_id，属于已调用未精确核验。"
                }
                return "已触发过远端调用，但运行层没有回传明确 model_id，属于已调用未精确核验。"
            }
            return "已验证。最近一次可确认的远端实际 model_id 是 \(actualModelId)。"
        case .localFallbackAfterRemoteError:
            if !requestedModelId.isEmpty, !failureReason.isEmpty {
                return "未验证成功。最近一次 Supervisor 远端尝试首选 \(requestedModelId)，但因 \(failureReason) 失败并由本地兜底接管。"
            }
            if actualModelId.isEmpty {
                return "未验证成功。系统尝试过远端调用，但本地回退接管了最终回复，而且没有拿到可确认的实际 model_id。"
            }
            return "部分验证。远端曾被触发，且拿到 model_id=\(actualModelId)，但那轮最终回复被本地回退接管。"
        case .localPreflight, .localDirectReply, .localDirectAction, .idle:
            return "未验证。当前只能确认已配置好远端首选路由，但还没有一轮可确认的成功远端调用记录。"
        }
    }

    private func supervisorRemoteFailureContext(
        for error: Error,
        preferredModelId: String?
    ) -> (requestedModelId: String?, failureReasonCode: String?) {
        if let hubError = error as? HubAIError {
            switch hubError {
            case .responseDoneNotOk(let failure):
                return (
                    requestedModelId: failure.modelId?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                        ? failure.modelId
                        : preferredModelId,
                    failureReasonCode: failure.reason
                )
            case .responseTimeout:
                return (preferredModelId, "response_timeout")
            case .grpcRouteUnavailable:
                return (preferredModelId, "grpc_route_unavailable")
            case .runtimeNotRunning:
                return (preferredModelId, "runtime_not_running")
            case .requestWriteFailed:
                return (preferredModelId, "request_write_failed")
            }
        }
        return (preferredModelId, "remote_error")
    }

    private func normalizedSupervisorFailureReasonCode(_ raw: String?) -> String {
        guard let raw else { return "" }
        return raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
    }

    private func displayedSupervisorFailureReason(_ raw: String) -> String {
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        switch normalized {
        case "":
            return ""
        case "model_not_found", "remote_model_not_found":
            return "model_not_found"
        case "response_timeout":
            return "response_timeout"
        case "grpc_route_unavailable":
            return "grpc_route_unavailable"
        case "runtime_not_running":
            return "runtime_not_running"
        case "request_write_failed":
            return "request_write_failed"
        case "sanitized_remote_response":
            return "远端回复未通过 Supervisor 输出约束"
        case "empty_remote_response":
            return "远端回复为空"
        default:
            return normalized
        }
    }

    private func currentSupervisorModelMismatchSummary() -> String? {
        let configured = currentPreferredModelID(for: .supervisor)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let actual = lastSupervisorActualModelId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !configured.isEmpty, !actual.isEmpty else { return nil }
        guard normalizedModelIdentity(configured) != normalizedModelIdentity(actual) else { return nil }
        switch HubAIClient.transportMode() {
        case .grpc:
            return """
当前配置首选是 \(configured)，但最近一次实际执行是 \(actual)。
XT 当前已经是 grpc-only，所以这次不一致基本不是 XT 本地 auto fallback；更可能是 Hub 端触发了 downgrade_to_local，或 Hub 的 remote_export gate 主动把 paid 请求降到了本地模型。
下一步不要再看 XT 路由设置，直接去 Hub 侧查 `ai.generate.downgraded_to_local` / `remote_export_blocked` 审计。
"""
        case .auto:
            return """
当前配置首选是 \(configured)，但最近一次实际执行是 \(actual)。
这通常表示远端 paid 路由没有真正命中，而是发生了 XT 自动回退到本地模型，或 Hub 端触发了 downgrade_to_local。
如果你要强制验证 paid GPT，请先把 Hub transport 切到 `/hub route grpc`，这样远端不可用时会直接报错，不会静默掉回本地。
"""
        case .fileIPC:
            return """
当前配置首选是 \(configured)，但最近一次实际执行是 \(actual)。
XT 当前 transport 是 fileIPC，所以这轮本来就不会强制走远端 paid GPT；请先在 Supervisor 里执行 `/hub route grpc`，再重新验证。
"""
        }
    }

    private func strictSupervisorRemoteModelMismatchResponse(
        preferredModelId: String?,
        actualModelId: String?
    ) -> String? {
        guard HubAIClient.transportMode() == .grpc else { return nil }
        let configured = preferredModelId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let actual = actualModelId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !configured.isEmpty, !actual.isEmpty else { return nil }
        guard normalizedModelIdentity(configured) != normalizedModelIdentity(actual) else { return nil }

        return """
❌ Supervisor 已拒绝接受本次回复：当前配置首选是 \(configured)，但这轮实际执行返回的是 \(actual)。

XT 当前 transport 是 grpc-only，这不属于 XT 本地 auto fallback；更可能是 Hub 端触发了 `downgrade_to_local`，或 `remote_export_blocked` 把 paid 请求降到了本地模型。
为了避免“界面选了 GPT，但实际 quietly 用本地模型继续执行”，这轮结果已按 fail-closed 丢弃。

下一步：
1. 到 Hub 审计里查 `ai.generate.downgraded_to_local`
2. 查同 request_id 对应的 `remote_export_blocked` deny_code
3. 修完 Hub export gate 后，再重试当前请求
"""
    }

    private func normalizedModelIdentity(_ raw: String) -> String {
        raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "（已加载，名称：", with: "")
            .replacingOccurrences(of: ")", with: "")
            .replacingOccurrences(of: "）", with: "")
    }

    private func currentHubTransportSummary() -> String {
        let mode = HubAIClient.transportMode()
        let decision = HubRouteStateMachine.resolve(mode: mode, hasRemoteProfile: true)
        return "\(mode.rawValue) - \(supervisorRouteDecisionText(decision))"
    }

    private func supervisorModelInventory() -> [HubModel] {
        if let models = appModel?.modelsState.models, !models.isEmpty {
            return models
        }
        if !modelManager.availableModels.isEmpty {
            return modelManager.availableModels
        }
        return []
    }

    private func currentSupervisorModelRouteSummary() -> String {
        guard let preferred = currentPreferredModelID(for: .supervisor) else {
            return "未绑定固定 model id，当前按默认 Hub 路由执行。"
        }
        if let matched = supervisorModelInventory().first(where: {
            $0.id.compare(preferred, options: .caseInsensitive) == .orderedSame
        }) {
            let stateText: String
            switch matched.state {
            case .loaded:
                stateText = "已加载"
            case .available:
                stateText = "可用"
            case .sleeping:
                stateText = "休眠"
            }
            return "\(matched.id)（\(stateText)，名称：\(matched.name)）"
        }
        return "\(preferred)（当前 Hub 模型清单里暂未看到这个 id）"
    }

    private func parseDirectModelAssignmentIntent(
        _ userMessage: String,
        projects: [AXProjectEntry],
        role: AXRole,
        usedDefaultRole: Bool,
        resolvedModelId: String,
        sourceModelToken: String
    ) -> DirectModelAssignmentIntent? {
        let normalized = normalizedSupervisorIntentText(userMessage)
        let appliesToAllProjects = normalized.contains("所有项目") || normalized.contains("全部项目")

        let projectRef = appliesToAllProjects
            ? nil
            : extractProjectReferenceForDirectAssignment(userMessage, projects: projects)
        return DirectModelAssignmentIntent(
            appliesToAllProjects: appliesToAllProjects,
            projectRef: projectRef,
            role: role,
            usedDefaultRole: usedDefaultRole,
            modelId: resolvedModelId,
            sourceModelToken: sourceModelToken
        )
    }

    private func firstExplicitRoleMention(in normalized: String) -> AXRole? {
        let aliases: [(String, AXRole)] = [
            ("reviewer", .reviewer), ("advisor", .advisor), ("coarse", .coarse), ("refine", .refine), ("coder", .coder),
            ("开发者", .coder), ("开发", .coder), ("编程", .coder), ("编码", .coder),
            ("粗编", .coarse), ("粗稿", .coarse), ("初稿", .coarse),
            ("精编", .refine), ("精修", .refine), ("润色", .refine),
            ("审查", .reviewer), ("审阅", .reviewer), ("评审", .reviewer),
            ("顾问", .advisor)
        ]
        for (token, role) in aliases.sorted(by: { $0.0.count > $1.0.count }) where normalized.contains(token) {
            return role
        }
        return nil
    }

    private func extractRequestedModelToken(from userMessage: String) -> String? {
        let patterns = [
            #"(?:改成|改为|换成|换为|换到|切到|切换到|设为|设置为|指定为|调整为)\s*[“"']?([^“"'\n。！!？?]+)"#,
            #"(?:用|使用)\s*[“"']?([^“"'\n。！!？?]+)"#
        ]
        for pattern in patterns {
            if let captured = firstRegexCapture(in: userMessage, pattern: pattern) {
                let cleaned = sanitizeRequestedModelToken(captured)
                if !cleaned.isEmpty {
                    return cleaned
                }
            }
        }
        return nil
    }

    private func sanitizeRequestedModelToken(_ raw: String) -> String {
        var out = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while out.hasPrefix("模型") || out.hasPrefix("model") || out.hasPrefix("为") {
            if out.hasPrefix("模型") {
                out.removeFirst("模型".count)
            } else if out.hasPrefix("model") {
                out.removeFirst("model".count)
            } else if out.hasPrefix("为") {
                out.removeFirst("为".count)
            }
            out = out.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let suffixes = ["吧", "一下", "试试", "看看", "谢谢"]
        for suffix in suffixes where out.hasSuffix(suffix) {
            out = String(out.dropLast(suffix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return out.trimmingCharacters(in: CharacterSet(charactersIn: "\"'“”‘’.,，。!！?？"))
    }

    private func resolveRequestedModelToken(_ token: String) -> ModelTokenResolution {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = trimmed.lowercased()
        if ["auto", "default", "none", "clear", "自动"].contains(lowered) {
            return .auto
        }

        let inventory = supervisorModelInventory()
        guard !inventory.isEmpty else {
            if lowered.contains("/") || lowered.contains("gpt") || lowered.contains("claude") || lowered.contains("gemini") {
                return .resolved(trimmed)
            }
            return .inventoryUnavailable
        }

        let compactQuery = compactModelLookupKey(trimmed)
        let versionFragments = versionLikeFragments(in: trimmed.lowercased())
        let scored: [(model: HubModel, score: Int)] = inventory.compactMap { model in
            let idLower = model.id.lowercased()
            let nameLower = model.name.lowercased()
            let compactID = compactModelLookupKey(model.id)
            let compactName = compactModelLookupKey(model.name)
            var score = 0

            if idLower == lowered { score = max(score, 300) }
            if nameLower == lowered { score = max(score, 290) }
            if !compactQuery.isEmpty && compactID == compactQuery { score = max(score, 270) }
            if !compactQuery.isEmpty && compactName == compactQuery { score = max(score, 260) }
            if idLower.contains(lowered) { score = max(score, 230) }
            if nameLower.contains(lowered) { score = max(score, 220) }
            if !compactQuery.isEmpty && compactID.contains(compactQuery) { score = max(score, 210) }
            if !compactQuery.isEmpty && compactName.contains(compactQuery) { score = max(score, 200) }
            if versionFragments.contains(where: { fragment in
                idLower.contains(fragment) || nameLower.contains(fragment)
            }) {
                score = max(score, 240)
            }
            if score == 0 { return nil }
            return (model, score)
        }
        .sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            if lhs.model.state != rhs.model.state { return lhs.model.state == .loaded }
            return lhs.model.id.localizedCaseInsensitiveCompare(rhs.model.id) == .orderedAscending
        }

        guard let best = scored.first else { return .notFound }
        if scored.count == 1 {
            return .resolved(best.model.id)
        }
        let second = scored[1]
        if best.score - second.score >= 20 {
            return .resolved(best.model.id)
        }
        return .ambiguous(Array(scored.prefix(4).map(\.model)))
    }

    private func compactModelLookupKey(_ text: String) -> String {
        text
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init)
            .joined()
    }

    private func versionLikeFragments(in text: String) -> [String] {
        let pattern = #"[0-9]+(?:\.[0-9]+)+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, options: [], range: range).compactMap { match in
            guard let range = Range(match.range, in: text) else { return nil }
            return String(text[range])
        }
    }

    private func extractProjectReferenceForDirectAssignment(
        _ userMessage: String,
        projects: [AXProjectEntry]
    ) -> String? {
        let normalized = normalizedSupervisorIntentText(userMessage)
        if normalized.contains("当前项目") || normalized.contains("这个项目") || normalized.contains("该项目") {
            return defaultProjectReferenceForDirectAssignment(projects: projects)
        }

        let patterns = [
            #"(?:把|给|将)\s*(.+?)(?:这个项目|该项目|项目)"#,
            #"(?:把|给|将)\s*(.+?)\s*的\s*(?:开发者|开发|coder|coarse|refine|reviewer|advisor|审查|审阅|评审|顾问|粗编|精修)?\s*模型"#
        ]
        for pattern in patterns {
            if let captured = firstRegexCapture(in: userMessage, pattern: pattern) {
                let cleaned = sanitizeDirectProjectHint(captured)
                if !cleaned.isEmpty {
                    return cleaned
                }
            }
        }
        return nil
    }

    private func sanitizeDirectProjectHint(_ raw: String) -> String {
        var out = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefixes = ["把", "给", "将"]
        for prefix in prefixes where out.hasPrefix(prefix) {
            out.removeFirst(prefix.count)
            out = out.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let fillers = ["这个", "该", "当前", "一下"]
        for filler in fillers {
            out = out.replacingOccurrences(of: filler, with: "")
        }
        return sanitizeProjectReference(out)
    }

    private func defaultProjectReferenceForDirectAssignment(projects: [AXProjectEntry]) -> String? {
        if let selectedProjectID = appModel?.selectedProjectId,
           selectedProjectID != AXProjectRegistry.globalHomeId,
           let selected = projects.first(where: { $0.projectId == selectedProjectID }) {
            return selected.displayName
        }
        if projects.count == 1 {
            return projects[0].displayName
        }
        return nil
    }

    private func firstRegexCapture(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[captureRange])
    }

    private func containsAny(_ text: String, _ needles: [String]) -> Bool {
        needles.contains { text.contains($0) }
    }

    private func idleDurationText(_ seconds: TimeInterval) -> String {
        if seconds < 90 { return "刚刚无更新" }
        let mins = Int(seconds / 60)
        if mins < 60 { return "\(mins) 分钟无更新" }
        let hours = Int(round(Double(mins) / 60.0))
        if hours < 48 { return "\(hours) 小时无更新" }
        let days = Int(round(Double(hours) / 24.0))
        return "\(days) 天无更新"
    }

    private func addAssistantMessage(_ text: String) {
        let message = SupervisorMessage(
            id: UUID().uuidString,
            role: .assistant,
            content: text,
            isVoice: false,
            timestamp: Date().timeIntervalSince1970
        )
        messages.append(message)
    }

    private func addSystemMessage(_ text: String) {
        let message = SupervisorMessage(
            id: UUID().uuidString,
            role: .system,
            content: text,
            isVoice: false,
            timestamp: Date().timeIntervalSince1970
        )
        messages.append(message)
    }

    private func pushSupervisorIncidentNotification(_ incident: SupervisorLaneIncident) {
        let linkedGrant = selectPendingGrant(for: incident.projectID)
        let projectToken = incident.projectID?.uuidString
        let actionURL = supervisorActionURL(
            projectId: projectToken,
            grantRequestId: linkedGrant?.grantRequestId,
            capability: linkedGrant?.capability
        )
        let title = "🚧 Lane 需要处理：\(incident.incidentCode)"
        let body = """
lane=\(incident.laneID)
action=\(incident.proposedAction.rawValue)
deny=\(incident.denyCode)
latency=\(incident.takeoverLatencyMs ?? -1)ms
audit=\(incident.auditRef)
"""

        HubIPCClient.pushNotification(
            source: "X-Terminal",
            title: title,
            body: body,
            dedupeKey: "x_terminal_supervisor_incident_\(incident.id)",
            actionURL: actionURL,
            unread: true
        )
    }

    private func appendSupervisorIncident(_ incident: SupervisorLaneIncident) {
        supervisorIncidentLedger.append(incident)
        if supervisorIncidentLedger.count > 240 {
            supervisorIncidentLedger.removeFirst(supervisorIncidentLedger.count - 240)
        }
        HubIPCClient.appendSupervisorIncidentAudit(
            incidentID: incident.id,
            laneID: incident.laneID,
            taskID: incident.taskID,
            projectID: incident.projectID,
            incidentCode: incident.incidentCode,
            eventType: incident.eventType,
            denyCode: incident.denyCode,
            proposedAction: incident.proposedAction.rawValue,
            severity: incident.severity.rawValue,
            category: incident.category.rawValue,
            detectedAtMs: incident.detectedAtMs,
            handledAtMs: incident.handledAtMs,
            takeoverLatencyMs: incident.takeoverLatencyMs,
            auditRef: incident.auditRef,
            detail: incident.detail,
            status: incident.status.rawValue
        )
        autoExportXTReadyIncidentEventsIfNeeded()
    }

    @discardableResult
    private func applySupervisorLaneHealthSnapshot(_ snapshot: SupervisorLaneHealthSnapshot) -> Bool {
        supervisorLaneHealthSnapshot = snapshot
        supervisorLaneHealthStatusLine = laneHealthStatusLine(summary: snapshot.summary)

        let fingerprint = snapshot.fingerprint
        let changed = fingerprint != lastLaneHealthFingerprint
        if changed {
            lastLaneHealthFingerprint = fingerprint
            maybePushLaneHealthNotification(snapshot)
        }
        return changed
    }

    private func laneHealthStatusLine(summary: LaneHealthSummary) -> String {
        if summary.total == 0 {
            return "lane health: idle"
        }
        return "lane health: total=\(summary.total), running=\(summary.running), blocked=\(summary.blocked), stalled=\(summary.stalled), failed=\(summary.failed)"
    }

    private func maybePushLaneHealthNotification(_ snapshot: SupervisorLaneHealthSnapshot) {
        let summary = snapshot.summary
        guard summary.failed > 0 || summary.stalled > 0 else { return }

        let hotspots = snapshot.lanes
            .filter { $0.status == .failed || $0.status == .stalled }
            .prefix(3)
            .map { lane in
                "\(lane.laneID):\(lane.status.rawValue)/\(lane.blockedReason?.rawValue ?? "none")"
            }
            .joined(separator: ";")

        let body = """
running=\(summary.running)
blocked=\(summary.blocked)
stalled=\(summary.stalled)
failed=\(summary.failed)
hotspots=\(hotspots.isEmpty ? "none" : hotspots)
"""

        HubIPCClient.pushNotification(
            source: "X-Terminal",
            title: "🫀 Lane 健康巡检告警",
            body: body,
            dedupeKey: "x_terminal_supervisor_lane_health_\(summary.failed)_\(summary.stalled)_\(hotspots)",
            actionURL: supervisorActionURL(projectId: nil),
            unread: true
        )
    }

    private func autoExportXTReadyIncidentEventsIfNeeded() {
        guard isXTReadyIncidentAutoExportEnabled else {
            xtReadyIncidentEventsAutoExportStatus = "disabled"
            return
        }

        let now = Date().timeIntervalSince1970
        guard now - lastXTReadyIncidentAutoExportAt >= xtReadyIncidentAutoExportMinIntervalSec else {
            return
        }
        lastXTReadyIncidentAutoExportAt = now

        _ = exportXTReadyIncidentEventsReport()
    }

    private var isXTReadyIncidentAutoExportEnabled: Bool {
        let raw = (ProcessInfo.processInfo.environment["XTERMINAL_AUTO_EXPORT_XT_READY_INCIDENT_EVENTS"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if raw.isEmpty {
            return true
        }
        return !["0", "false", "off", "no", "n"].contains(raw)
    }

    static func buildXTReadyIncidentEvents(
        from incidents: [SupervisorLaneIncident],
        limit: Int = 120
    ) -> [XTReadyIncidentEvent] {
        let required = Set(xtReadyRequiredIncidentCodes)
        return incidents
            .filter { required.contains($0.incidentCode) && $0.status == .handled }
            .sorted { lhs, rhs in
                let lt = lhs.handledAtMs ?? lhs.detectedAtMs
                let rt = rhs.handledAtMs ?? rhs.detectedAtMs
                if lt != rt {
                    return lt < rt
                }
                if lhs.incidentCode != rhs.incidentCode {
                    return lhs.incidentCode < rhs.incidentCode
                }
                return lhs.laneID < rhs.laneID
            }
            .suffix(max(1, limit))
            .map { incident in
                XTReadyIncidentEvent(
                    eventType: incident.eventType,
                    incidentCode: incident.incidentCode,
                    laneID: incident.laneID,
                    detectedAtMs: incident.detectedAtMs,
                    handledAtMs: incident.handledAtMs ?? incident.detectedAtMs,
                    denyCode: incident.denyCode,
                    auditEventType: "supervisor.incident.handled",
                    auditRef: incident.auditRef,
                    takeoverLatencyMs: incident.takeoverLatencyMs
                )
            }
    }

    static func missingXTReadyIncidentCodes(
        in events: [XTReadyIncidentEvent]
    ) -> [String] {
        let existing = Set(events.map(\.incidentCode))
        return xtReadyRequiredIncidentCodes.filter { !existing.contains($0) }
    }

    static func evaluateXTReadyIncidentReadiness(
        events: [XTReadyIncidentEvent]
    ) -> XTReadyIncidentReadiness {
        var issues: [String] = []

        for incidentCode in xtReadyRequiredIncidentCodes {
            guard let selected = selectBestXTReadyIncidentEvent(
                incidentCode: incidentCode,
                events: events
            ) else {
                issues.append("\(incidentCode):missing_incident")
                continue
            }

            let expectedEventType = xtReadyExpectedEventTypes[incidentCode] ?? ""
            if !expectedEventType.isEmpty, selected.eventType != expectedEventType {
                issues.append("\(incidentCode):event_type_mismatch")
            }
            if selected.denyCode != incidentCode {
                issues.append("\(incidentCode):deny_code_mismatch")
            }
            if selected.auditRef.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append("\(incidentCode):audit_ref_missing")
            }
            guard let latency = resolvedTakeoverLatencyMs(for: selected) else {
                issues.append("\(incidentCode):takeover_latency_missing")
                continue
            }
            if latency > xtReadyMaxTakeoverLatencyMs {
                issues.append("\(incidentCode):takeover_latency_exceeded")
            }
        }

        return XTReadyIncidentReadiness(
            ready: issues.isEmpty,
            issues: issues
        )
    }

    func exportXTReadyIncidentEventsReport(
        outputURL: URL? = nil,
        limit: Int = 120
    ) -> XTReadyIncidentEventsExportResult {
        let rows = Self.buildXTReadyIncidentEvents(from: supervisorIncidentLedger, limit: limit)
        let missing = Self.missingXTReadyIncidentCodes(in: rows)
        let destination = outputURL ?? defaultXTReadyIncidentEventsReportURL()
        let summary = XTReadyIncidentSummary(
            highRiskLaneWithoutGrant: 0,
            unauditedAutoResolution: 0,
            highRiskBypassCount: 0,
            blockedEventMissRate: 0,
            nonMessageIngressPolicyCoverage: rows.isEmpty ? 0 : 1
        )
        let payload = XTReadyIncidentEventsPayload(
            runId: "xt_ready_runtime_\(Int64((Date().timeIntervalSince1970 * 1000).rounded()))",
            schemaVersion: "xt_ready_incident_events.v1",
            generatedAtMs: Int64((Date().timeIntervalSince1970 * 1000).rounded()),
            source: "supervisor_manager",
            summary: summary,
            events: rows
        )

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(payload)
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: destination, options: .atomic)
            let result = XTReadyIncidentEventsExportResult(
                ok: true,
                outputPath: destination.path,
                exportedEventCount: rows.count,
                missingIncidentCodes: missing,
                reason: "ok"
            )
            xtReadyIncidentEventsReportPath = result.outputPath
            xtReadyIncidentEventsAutoExportStatus = missing.isEmpty
                ? "ok"
                : "partial_missing:\(missing.joined(separator: ","))"
            return result
        } catch {
            let result = XTReadyIncidentEventsExportResult(
                ok: false,
                outputPath: destination.path,
                exportedEventCount: rows.count,
                missingIncidentCodes: missing,
                reason: "write_failed:\(error.localizedDescription)"
            )
            xtReadyIncidentEventsReportPath = result.outputPath
            xtReadyIncidentEventsAutoExportStatus = "failed:\(result.reason)"
            return result
        }
    }

    func xtReadyIncidentExportSnapshot(limit: Int = 120) -> XTReadyIncidentExportSnapshot {
        let rows = Self.buildXTReadyIncidentEvents(from: supervisorIncidentLedger, limit: limit)
        let missing = Self.missingXTReadyIncidentCodes(in: rows)
        let readiness = Self.evaluateXTReadyIncidentReadiness(events: rows)
        let defaultPath = defaultXTReadyIncidentEventsReportURL().path
        return XTReadyIncidentExportSnapshot(
            autoExportEnabled: isXTReadyIncidentAutoExportEnabled,
            ledgerIncidentCount: supervisorIncidentLedger.count,
            requiredIncidentEventCount: rows.count,
            missingIncidentCodes: missing,
            strictE2EReady: readiness.ready,
            strictE2EIssues: readiness.issues,
            status: xtReadyIncidentEventsAutoExportStatus,
            reportPath: xtReadyIncidentEventsReportPath.isEmpty ? defaultPath : xtReadyIncidentEventsReportPath
        )
    }

    private static func selectBestXTReadyIncidentEvent(
        incidentCode: String,
        events: [XTReadyIncidentEvent]
    ) -> XTReadyIncidentEvent? {
        let expectedEventType = xtReadyExpectedEventTypes[incidentCode] ?? ""
        let candidates = events.filter { $0.incidentCode == incidentCode }
        guard !candidates.isEmpty else { return nil }
        return candidates.max { lhs, rhs in
            let lScore = scoreXTReadyIncidentEvent(lhs, incidentCode: incidentCode, expectedEventType: expectedEventType)
            let rScore = scoreXTReadyIncidentEvent(rhs, incidentCode: incidentCode, expectedEventType: expectedEventType)
            if lScore != rScore {
                return lScore < rScore
            }
            if lhs.handledAtMs != rhs.handledAtMs {
                return lhs.handledAtMs < rhs.handledAtMs
            }
            return lhs.detectedAtMs < rhs.detectedAtMs
        }
    }

    private static func scoreXTReadyIncidentEvent(
        _ event: XTReadyIncidentEvent,
        incidentCode: String,
        expectedEventType: String
    ) -> Int {
        var score = 0
        if event.incidentCode == incidentCode { score += 2 }
        if event.denyCode == incidentCode { score += 2 }
        if !expectedEventType.isEmpty, event.eventType == expectedEventType { score += 2 }
        if !event.auditRef.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { score += 2 }
        if let latency = resolvedTakeoverLatencyMs(for: event) {
            score += 1
            if latency <= xtReadyMaxTakeoverLatencyMs {
                score += 1
            }
        }
        return score
    }

    private static func resolvedTakeoverLatencyMs(
        for event: XTReadyIncidentEvent
    ) -> Int64? {
        if let direct = event.takeoverLatencyMs, direct >= 0 {
            return direct
        }
        if event.handledAtMs >= event.detectedAtMs {
            return event.handledAtMs - event.detectedAtMs
        }
        return nil
    }

    private func defaultXTReadyIncidentEventsReportURL() -> URL {
        let env = (ProcessInfo.processInfo.environment["XTERMINAL_XT_READY_INCIDENT_EVENTS_PATH"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !env.isEmpty {
            let expanded = NSString(string: env).expandingTildeInPath
            return URL(fileURLWithPath: expanded)
        }
        let root = SupervisorDoctorChecker.defaultWorkspaceRoot()
        return root.appendingPathComponent(".axcoder/reports/xt_ready_incident_events.runtime.json")
    }

    func clearMessages() {
        messages.removeAll()
    }

    func refreshVoiceRuntimeStatus() {
        Task { @MainActor in
            await voiceSessionCoordinator.refreshRouteAvailability()
            await voiceSessionCoordinator.refreshAuthorizationStatus(requestIfNeeded: false)
            await voiceWakeProfileStore.refresh(pairingReady: currentWakeProfilePairingReady())
            refreshVoiceReadinessSnapshot()
        }
    }

    func updateVoiceWakeTriggerWords(_ rawText: String) {
        voiceWakeProfileStore.setLocalOverrideTriggerWords(rawText)
        refreshVoiceReadinessSnapshot()
    }

    func restoreDefaultVoiceWakeTriggerWords() {
        voiceWakeProfileStore.restoreDefaultLocalOverrideTriggerWords()
        refreshVoiceReadinessSnapshot()
    }

    func resyncVoiceWakeProfile() {
        Task { @MainActor in
            await voiceWakeProfileStore.refresh(pairingReady: currentWakeProfilePairingReady())
            refreshVoiceReadinessSnapshot()
        }
    }

    func pushVoiceWakeProfileToHub() {
        Task { @MainActor in
            _ = await voiceWakeProfileStore.pushLocalOverrideToHub(pairingReady: currentWakeProfilePairingReady())
            refreshVoiceReadinessSnapshot()
        }
    }

    private func refreshVoiceReadinessSnapshot() {
        guard let appModel else {
            voiceReadinessSnapshot = .empty
            return
        }

        let session = currentVoiceReadinessSession()
        voiceReadinessSnapshot = VoiceReadinessAggregator.build(
            input: VoiceReadinessAggregatorInput(
                generatedAt: Date(),
                localConnected: appModel.hubConnected,
                remoteConnected: appModel.hubRemoteConnected,
                remoteRoute: appModel.hubRemoteRoute,
                linking: appModel.hubRemoteLinking,
                pairingPort: appModel.hubPairingPort,
                grpcPort: appModel.hubGrpcPort,
                internetHost: appModel.hubInternetHost,
                configuredModelIDs: configuredHubModelIDs(appModel),
                totalModelRoles: AXRole.allCases.count,
                runtimeStatus: appModel.runtimeStatus,
                modelsState: appModel.modelsState,
                bridgeAlive: appModel.bridgeAlive,
                bridgeEnabled: appModel.bridgeEnabled,
                sessionID: session?.id,
                sessionTitle: session?.title,
                sessionRuntime: session?.runtime,
                voiceRouteDecision: voiceRouteDecision,
                voiceRuntimeState: voiceRuntimeState,
                voiceAuthorizationStatus: voiceAuthorizationStatus,
                voiceActiveHealthReasonCode: voiceActiveHealthReasonCode,
                voiceSidecarHealth: voiceFunASRSidecarHealth,
                wakeProfileSnapshot: voiceWakeProfileSnapshot,
                conversationSession: conversationSessionSnapshot
            )
        )
    }

    private func currentVoiceReadinessSession() -> AXSessionInfo? {
        guard let appModel else { return nil }
        if let selectedProjectId = appModel.selectedProjectId,
           selectedProjectId != AXProjectRegistry.globalHomeId,
           let session = sessionManager.primarySession(for: selectedProjectId) {
            return session
        }
        if let activeSessionId = sessionManager.activeSessionId,
           let session = sessionManager.session(for: activeSessionId) {
            return session
        }
        return sessionManager.sessions.sorted { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhs.id < rhs.id
        }.first
    }

    private func configuredHubModelIDs(_ appModel: AppModel) -> [String] {
        AXRole.allCases.compactMap { role in
            let model = (appModel.settingsStore.settings.assignment(for: role).model ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return model.isEmpty ? nil : model
        }
    }

    func refreshSupervisorDoctorReport() {
        _ = runSupervisorDoctorPreflight(reason: "manual_refresh", emitSystemMessage: true)
    }

    func refreshPendingHubGrantSnapshotNow() {
        Task { @MainActor in
            await refreshSchedulerSnapshot(force: true)
        }
    }

    func startVoiceAuthorization(
        _ request: SupervisorVoiceAuthorizationRequest
    ) async -> SupervisorVoiceAuthorizationResolution {
        guard !voiceAuthorizationInFlight else {
            let resolution = makeVoiceAuthorizationManagerFailureResolution(
                requestId: request.requestId,
                projectId: request.projectId,
                templateId: request.templateId,
                riskTier: request.riskTier,
                reasonCode: "voice_authorization_inflight",
                challenge: activeVoiceChallenge
            )
            applyVoiceAuthorizationResolution(
                resolution,
                request: activeVoiceAuthorizationRequest ?? request,
                preserveActiveChallengeOnFailClosed: activeVoiceChallenge != nil
            )
            return resolution
        }

        voiceAuthorizationInFlight = true
        let resolution = await voiceAuthorizationBridge.beginAuthorization(request)
        applyVoiceAuthorizationResolution(
            resolution,
            request: request,
            preserveActiveChallengeOnFailClosed: false
        )
        voiceAuthorizationInFlight = false
        return resolution
    }

    func confirmVoiceAuthorization(
        _ verification: SupervisorVoiceAuthorizationVerificationInput
    ) async -> SupervisorVoiceAuthorizationResolution {
        guard !voiceAuthorizationInFlight else {
            let resolution = makeVoiceAuthorizationManagerFailureResolution(
                requestId: verification.requestId,
                projectId: activeVoiceAuthorizationRequest?.projectId,
                templateId: activeVoiceAuthorizationRequest?.templateId ?? "voice.grant.v1",
                riskTier: activeVoiceAuthorizationRequest?.riskTier ?? .high,
                reasonCode: "voice_authorization_inflight",
                challenge: activeVoiceChallenge
            )
            applyVoiceAuthorizationResolution(
                resolution,
                request: activeVoiceAuthorizationRequest,
                preserveActiveChallengeOnFailClosed: activeVoiceChallenge != nil
            )
            return resolution
        }

        guard let request = activeVoiceAuthorizationRequest,
              let challenge = activeVoiceChallenge else {
            let resolution = makeVoiceAuthorizationManagerFailureResolution(
                requestId: verification.requestId,
                projectId: nil,
                templateId: "voice.grant.v1",
                riskTier: .high,
                reasonCode: "voice_authorization_not_started",
                challenge: nil
            )
            applyVoiceAuthorizationResolution(
                resolution,
                request: nil,
                preserveActiveChallengeOnFailClosed: false
            )
            return resolution
        }

        voiceAuthorizationInFlight = true
        let resolution = await voiceAuthorizationBridge.verifyAuthorization(
            request: request,
            challenge: challenge,
            verification: verification
        )
        applyVoiceAuthorizationResolution(
            resolution,
            request: request,
            preserveActiveChallengeOnFailClosed: resolution.challenge != nil
        )
        await applyVoiceAuthorizationRuntimeSideEffects(
            resolution,
            request: request,
            forceCancel: false
        )
        voiceAuthorizationInFlight = false
        return resolution
    }

    func retryVoiceAuthorizationVerification(
        transcript: String,
        semanticMatchScore: Double = 0.99,
        mobileConfirmed: Bool = false
    ) async -> SupervisorVoiceAuthorizationResolution {
        let requestId = activeVoiceAuthorizationRequest?.requestId
            ?? voiceAuthorizationResolution?.requestId
            ?? "voice-authorization-retry"
        let normalizedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let boundDeviceId: String? = {
            let token = activeVoiceChallenge?.boundDeviceId.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return token.isEmpty ? nil : token
        }()
        let clippedScore = max(0, min(1, semanticMatchScore))

        return await confirmVoiceAuthorization(
            SupervisorVoiceAuthorizationVerificationInput(
                requestId: requestId,
                challengeCode: activeVoiceChallenge?.challengeCode,
                transcript: normalizedTranscript.isEmpty ? nil : normalizedTranscript,
                semanticMatchScore: clippedScore,
                actionText: activeVoiceAuthorizationRequest?.actionText ?? "",
                scopeText: activeVoiceAuthorizationRequest?.scopeText ?? "",
                amountText: activeVoiceAuthorizationRequest?.amountText,
                verifyNonce: UUID().uuidString.lowercased(),
                boundDeviceId: boundDeviceId,
                mobileConfirmed: mobileConfirmed
            )
        )
    }

    func cancelVoiceAuthorization() {
        guard let request = activeVoiceAuthorizationRequest ?? voiceAuthorizationResolution.map({
            SupervisorVoiceAuthorizationRequest(
                requestId: $0.requestId,
                projectId: $0.projectId,
                templateId: $0.templateId,
                actionText: "",
                scopeText: "",
                amountText: nil,
                riskTier: LaneRiskTier(rawValue: $0.riskTier) ?? .high,
                boundDeviceId: activeVoiceChallenge?.boundDeviceId,
                mobileTerminalId: activeVoiceChallenge?.mobileTerminalId,
                challengeCode: activeVoiceChallenge?.challengeCode,
                ttlMs: 120_000
            )
        }) else {
            return
        }

        let resolution = makeVoiceAuthorizationManagerFailureResolution(
            requestId: request.requestId,
            projectId: request.projectId,
            templateId: request.templateId,
            riskTier: request.riskTier,
            reasonCode: "user_cancelled",
            challenge: activeVoiceChallenge
        )
        applyVoiceAuthorizationResolution(
            resolution,
            request: nil,
            preserveActiveChallengeOnFailClosed: false,
            forceCancel: true
        )
    }

    func bestPendingHubGrant(for projectID: UUID?) -> SupervisorPendingGrant? {
        selectPendingGrant(for: projectID)
    }

    func autoApprovePendingHubGrant(
        for projectID: UUID?,
        auditRef: String
    ) async -> SupervisorAutoGrantResolution {
        var candidate = selectPendingGrant(for: projectID)
        if candidate == nil {
            await refreshSchedulerSnapshot(force: true)
            candidate = selectPendingGrant(for: projectID)
        }

        guard let grant = candidate else {
            return SupervisorAutoGrantResolution(
                ok: false,
                reasonCode: "pending_grant_not_found",
                grantRequestId: nil
            )
        }

        let grantId = grant.grantRequestId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !grantId.isEmpty else {
            return SupervisorAutoGrantResolution(
                ok: false,
                reasonCode: "grant_request_id_empty",
                grantRequestId: nil
            )
        }
        if pendingHubGrantActionsInFlight.contains(grantId) {
            return SupervisorAutoGrantResolution(
                ok: false,
                reasonCode: "grant_action_inflight",
                grantRequestId: grantId
            )
        }

        pendingHubGrantActionsInFlight.insert(grantId)
        let projectId = grant.projectId.trimmingCharacters(in: .whitespacesAndNewlines)
        let ttlOverride = grant.requestedTtlSec > 0 ? grant.requestedTtlSec : nil
        let tokenOverride = grant.requestedTokenCap > 0 ? grant.requestedTokenCap : nil
        let result = await HubIPCClient.approvePendingGrantRequest(
            grantRequestId: grantId,
            projectId: projectId.isEmpty ? nil : projectId,
            requestedTtlSec: ttlOverride,
            requestedTokenCap: tokenOverride,
            note: "x_terminal_supervisor_auto_grant:\(auditRef)"
        )

        await completePendingHubGrantAction(
            grantId: grantId,
            grant: grant,
            approve: true,
            result: result
        )

        return SupervisorAutoGrantResolution(
            ok: result.ok,
            reasonCode: result.reasonCode?.trimmingCharacters(in: .whitespacesAndNewlines) ?? (result.ok ? "ok" : "unknown"),
            grantRequestId: grantId
        )
    }

    func refreshPendingSupervisorSkillApprovalsNow() {
        rebuildPendingSupervisorSkillApprovalViewState()
    }

    func approvePendingSupervisorSkillApproval(_ approval: SupervisorPendingSkillApproval) {
        performPendingSupervisorSkillApprovalAction(approval, approve: true)
    }

    func denyPendingSupervisorSkillApproval(_ approval: SupervisorPendingSkillApproval) {
        performPendingSupervisorSkillApprovalAction(approval, approve: false)
    }

    func approvePendingHubGrant(_ grant: SupervisorPendingGrant) {
        performPendingHubGrantAction(grant, approve: true)
    }

    func denyPendingHubGrant(_ grant: SupervisorPendingGrant) {
        performPendingHubGrantAction(grant, approve: false)
    }

    private func selectPendingGrant(for projectID: UUID?) -> SupervisorPendingGrant? {
        let projectToken = projectID?.uuidString.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !projectToken.isEmpty {
            if let exact = pendingHubGrants.first(where: {
                $0.projectId.trimmingCharacters(in: .whitespacesAndNewlines) == projectToken
            }) {
                return exact
            }
        }
        return pendingHubGrants.first
    }

    private func performPendingSupervisorSkillApprovalAction(
        _ approval: SupervisorPendingSkillApproval,
        approve: Bool
    ) {
        let requestId = approval.requestId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !requestId.isEmpty else { return }

        let resolution: SupervisorSkillCallResolution
        switch locateSupervisorSkillCall(
            requestId: requestId,
            projectRef: approval.projectId,
            commandName: approve ? "APPROVE_SUPERVISOR_SKILL" : "DENY_SUPERVISOR_SKILL"
        ) {
        case .failure(let failure):
            addSystemMessage(failure.message)
            rebuildPendingSupervisorSkillApprovalViewState()
            return
        case .success(let resolved):
            resolution = resolved
        }

        guard resolution.record.status == .awaitingAuthorization else {
            rebuildPendingSupervisorSkillApprovalViewState()
            return
        }

        let capability = resolution.record.requiredCapability?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard capability.isEmpty else {
            addSystemMessage("ℹ️ request_id=\(requestId) 当前是 Hub 授权等待态，请在 Hub 授权面板处理。")
            rebuildPendingSupervisorSkillApprovalViewState()
            return
        }

        if approve {
            resumeSupervisorSkillCallAfterLocalApproval(resolution)
        } else {
            blockSupervisorSkillCallAfterLocalApprovalDenial(resolution)
        }
    }

    private func resumeSupervisorSkillCallAfterLocalApproval(
        _ resolution: SupervisorSkillCallResolution
    ) {
        guard let toolCall = resolvedSupervisorToolCallForRecord(resolution.record) else {
            let nowMs = Int64((Date().timeIntervalSince1970 * 1000.0).rounded())
            if let blocked = applySupervisorSkillCallStatus(
                requestId: resolution.record.requestId,
                ctx: resolution.ctx,
                project: resolution.project,
                status: .blocked,
                stepStatus: .blocked,
                resultSummary: "local approval resume failed: skill mapping unavailable",
                denyCode: "skill_mapping_missing",
                updatedAtMs: nowMs,
                triggerSource: .approvalResolution,
                toolCall: nil
            ) {
                scheduleSupervisorApprovalResolutionFollowUp(
                    record: blocked,
                    project: resolution.project,
                    reasonCode: blocked.denyCode,
                    summary: blocked.resultSummary
                )
            }
            addSystemMessage("❌ 无法恢复技能调用：\(resolution.record.skillId)（request_id=\(resolution.record.requestId)）")
            return
        }

        let nowMs = Int64((Date().timeIntervalSince1970 * 1000.0).rounded())
        _ = applySupervisorSkillCallStatus(
            requestId: resolution.record.requestId,
            ctx: resolution.ctx,
            project: resolution.project,
            status: .queued,
            stepStatus: .pending,
            resultSummary: "local approval approved; resuming governed dispatch",
            denyCode: "",
            updatedAtMs: nowMs,
            triggerSource: .approvalResolution,
            toolCall: toolCall
        )

        let task = Task { [weak self] in
            guard let self else { return }
            await self.executeSupervisorSkillCall(
                requestId: resolution.record.requestId,
                project: resolution.project,
                ctx: resolution.ctx,
                toolCall: toolCall,
                allowPreviouslyApprovedAuthorization: true,
                triggerSource: .approvalResolution
            )
        }
        supervisorSkillExecutionTasks[resolution.record.requestId] = task
        addSystemMessage("✅ 已批准技能调用：\(resolution.record.skillId)（request_id=\(resolution.record.requestId)）")
    }

    private func blockSupervisorSkillCallAfterLocalApprovalDenial(
        _ resolution: SupervisorSkillCallResolution
    ) {
        let nowMs = Int64((Date().timeIntervalSince1970 * 1000.0).rounded())
        let toolCall = resolvedSupervisorToolCallForRecord(resolution.record)
        if let blocked = applySupervisorSkillCallStatus(
            requestId: resolution.record.requestId,
            ctx: resolution.ctx,
            project: resolution.project,
            status: .blocked,
            stepStatus: .blocked,
            resultSummary: "local approval denied by user",
            denyCode: "local_approval_denied",
            updatedAtMs: nowMs,
            triggerSource: .approvalResolution,
            toolCall: toolCall
        ) {
            scheduleSupervisorApprovalResolutionFollowUp(
                record: blocked,
                project: resolution.project,
                reasonCode: blocked.denyCode,
                summary: blocked.resultSummary
            )
        }
        addSystemMessage("⛔️ 已拒绝技能调用：\(resolution.record.skillId)（request_id=\(resolution.record.requestId)）")
    }

    private func performPendingHubGrantAction(
        _ grant: SupervisorPendingGrant,
        approve: Bool
    ) {
        let grantId = grant.grantRequestId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !grantId.isEmpty else { return }
        guard !pendingHubGrantActionsInFlight.contains(grantId) else { return }

        pendingHubGrantActionsInFlight.insert(grantId)
        let projectId = grant.projectId.trimmingCharacters(in: .whitespacesAndNewlines)

        Task { [weak self] in
            guard let self else { return }

            let result: HubIPCClient.PendingGrantActionResult
            if approve {
                let ttlOverride = grant.requestedTtlSec > 0 ? grant.requestedTtlSec : nil
                let tokenOverride = grant.requestedTokenCap > 0 ? grant.requestedTokenCap : nil
                result = await HubIPCClient.approvePendingGrantRequest(
                    grantRequestId: grantId,
                    projectId: projectId.isEmpty ? nil : projectId,
                    requestedTtlSec: ttlOverride,
                    requestedTokenCap: tokenOverride,
                    note: "x_terminal_supervisor_quick_approve"
                )
            } else {
                result = await HubIPCClient.denyPendingGrantRequest(
                    grantRequestId: grantId,
                    projectId: projectId.isEmpty ? nil : projectId,
                    reason: "user_denied_from_supervisor"
                )
            }

            await self.completePendingHubGrantAction(
                grantId: grantId,
                grant: grant,
                approve: approve,
                result: result
            )
        }
    }

    private func completePendingHubGrantAction(
        grantId: String,
        grant: SupervisorPendingGrant,
        approve: Bool,
        result: HubIPCClient.PendingGrantActionResult
    ) async {
        pendingHubGrantActionsInFlight.remove(grantId)

        if result.ok {
            pendingHubGrants.removeAll { $0.grantRequestId == grantId }
            let action = approve ? "通过" : "拒绝"
            addSystemMessage("已\(action) Hub 授权：\(grant.projectName)（grant=\(grantId)）")
            await resumeSupervisorSkillCallsAfterGrantAction(
                grant: grant,
                approve: approve,
                result: result
            )
        } else {
            let action = approve ? "通过" : "拒绝"
            let reason = result.reasonCode?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown"
            addSystemMessage("Hub 授权\(action)失败：\(grant.projectName)（grant=\(grantId)，reason=\(reason)）")
        }

        await refreshSchedulerSnapshot(force: true)
    }

    private func applyVoiceAuthorizationResolution(
        _ resolution: SupervisorVoiceAuthorizationResolution,
        request: SupervisorVoiceAuthorizationRequest?,
        preserveActiveChallengeOnFailClosed: Bool,
        forceCancel: Bool = false
    ) {
        voiceAuthorizationResolution = resolution

        switch resolution.state {
        case .pending, .escalatedToMobile:
            activeVoiceAuthorizationRequest = request
            activeVoiceChallenge = resolution.challenge
        case .verified, .denied:
            activeVoiceAuthorizationRequest = nil
            activeVoiceChallenge = nil
        case .failClosed:
            if forceCancel || !preserveActiveChallengeOnFailClosed {
                activeVoiceAuthorizationRequest = nil
                activeVoiceChallenge = nil
            } else if let request {
                activeVoiceAuthorizationRequest = request
                activeVoiceChallenge = resolution.challenge ?? activeVoiceChallenge
            }
        }

        let challengeId = resolution.challengeId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let challengeToken = challengeId.isEmpty ? "n/a" : challengeId
        let reasonToken = resolution.reasonCode?.trimmingCharacters(in: .whitespacesAndNewlines)
        let denyToken = resolution.denyCode?.trimmingCharacters(in: .whitespacesAndNewlines)

        let eventText: String
        let messageText: String
        switch resolution.state {
        case .pending:
            eventText = "voice authorization challenge issued: \(challengeToken)"
            messageText = "语音授权挑战已发起（challenge=\(challengeToken)）"
        case .escalatedToMobile:
            eventText = "voice authorization escalated to mobile: \(challengeToken)"
            messageText = "语音授权已升级到移动端确认（challenge=\(challengeToken)）"
        case .verified:
            eventText = "voice authorization verified: \(challengeToken)"
            messageText = "语音授权已验证通过（challenge=\(challengeToken)）"
        case .denied:
            let deny = denyToken ?? "denied"
            eventText = "voice authorization denied: \(challengeToken) -> \(deny)"
            messageText = "语音授权被拒绝（challenge=\(challengeToken)，deny=\(deny)）"
        case .failClosed:
            let reason = reasonToken ?? "unknown"
            eventText = "voice authorization fail-closed: \(challengeToken) -> \(reason)"
            if forceCancel, reason == "user_cancelled" {
                messageText = "已取消语音授权挑战（challenge=\(challengeToken)）"
            } else {
                messageText = "语音授权失败闭锁（challenge=\(challengeToken)，reason=\(reason)）"
            }
        }

        appendRecentEvent(eventText)
        addSystemMessage(messageText)
        speakSupervisorVoiceAuthorizationUpdate(
            resolution: resolution,
            challengeToken: challengeToken
        )
    }

    private func applyVoiceAuthorizationRuntimeSideEffects(
        _ resolution: SupervisorVoiceAuthorizationResolution,
        request: SupervisorVoiceAuthorizationRequest?,
        forceCancel: Bool
    ) async {
        guard !forceCancel else { return }
        guard resolution.state == .verified else { return }
        guard isCurrentGuardedOneShotVoiceAuthorization(request) else { return }
        guard let intakeRequest = oneShotIntakeRequest,
              let planDecision = oneShotAdaptivePoolPlan,
              oneShotRunState?.state == .awaitingGrant else {
            return
        }

        let resumedRunState = oneShotRunStateStore.transition(
            to: .launching,
            owner: .supervisor,
            activePools: planDecision.poolPlan.map(\.poolID),
            activeLanes: planDecision.poolPlan.flatMap(\.laneIDs),
            topBlocker: "none",
            nextDirectedTarget: "Supervisor",
            userVisibleSummary: "voice authorization verified; guarded one-shot launch resumed",
            evidenceRefs: OneShotControlPlaneSnapshot.defaultEvidenceRefs(),
            auditRef: intakeRequest.auditRef
        )
        oneShotRunState = resumedRunState
        appendRecentEvent("guarded one-shot launch resumed after voice authorization")
        addSystemMessage("高风险 one-shot 语音授权已通过，正在接入真实启动链路。")

        let outcome = await executePreparedOneShotLaunch(
            request: intakeRequest,
            planDecision: planDecision
        )
        applyGuardedOneShotLaunchResumeOutcome(
            outcome,
            request: intakeRequest,
            planDecision: planDecision
        )
    }

    private func isCurrentGuardedOneShotVoiceAuthorization(
        _ request: SupervisorVoiceAuthorizationRequest?
    ) -> Bool {
        guard let request,
              let intakeRequest = oneShotIntakeRequest else {
            return false
        }
        let expectedRequestID = oneShotVoiceAuthorizationRequestID(
            requestID: intakeRequest.requestID,
            authorizationTypes: intakeRequest.requiresHumanAuthorizationTypes
        )
        guard request.requestId == expectedRequestID else { return false }
        let projectID = request.projectId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !projectID.isEmpty, projectID == intakeRequest.projectID else {
            return false
        }
        return true
    }

    private func executePreparedOneShotLaunch(
        request: SupervisorOneShotIntakeRequest,
        planDecision: AdaptivePoolPlanDecision
    ) async -> GuardedOneShotLaunchResumeOutcome {
        guard let buildResult = oneShotPreparedSplitBuildResult else {
            return .failedClosed(reason: "guarded_one_shot_split_plan_missing")
        }

        if let executor = preparedOneShotLaunchExecutorForTesting {
            return await executor(request, planDecision, buildResult)
        }

        guard let supervisor = appModel?.supervisor else {
            return .failedClosed(reason: "supervisor_model_unavailable")
        }

        guard supervisor.orchestrator != nil else {
            return .failedClosed(reason: "supervisor_orchestrator_unavailable")
        }
        let orchestrator = supervisor.orchestrator!
        _ = await ensureOneShotAnchorProject(
            in: supervisor,
            request: request,
            planDecision: planDecision
        )
        _ = orchestrator.adoptPreparedSplitProposal(
            buildResult,
            auditDetail: "guarded one-shot prepared proposal adopted after voice authorization"
        )

        if buildResult.validation.hasBlockingIssues {
            let reason = buildResult.validation.blockingIssues.first?.code ?? "split_proposal_blocked"
            return .blocked(reason: reason, report: nil)
        }

        guard let promptResult = orchestrator.confirmActiveSplitProposal(globalContext: request.userGoal) else {
            let reason = normalizedOneShotFailureReason(
                orchestrator.splitFlowErrorMessage,
                fallback: "prompt_contract_confirmation_failed"
            )
            return .blocked(reason: reason, report: nil)
        }

        if promptResult.status != .ready || promptResult.lintResult.hasBlockingErrors {
            let lintReason = promptResult.lintResult.blockingIssues.first?.code
            let reason = normalizedOneShotFailureReason(lintReason, fallback: "prompt_contract_blocked")
            return .blocked(reason: reason, report: nil)
        }

        guard let launchReport = await orchestrator.executeActiveSplitProposal() else {
            let reason = normalizedOneShotFailureReason(
                orchestrator.splitFlowErrorMessage,
                fallback: "lane_launch_execution_failed"
            )
            return .blocked(reason: reason, report: nil)
        }

        if !launchReport.launchedLaneIDs.isEmpty {
            return .launched(launchReport)
        }

        let blockedReason = primaryBlockedReason(from: launchReport)
        return .blocked(reason: blockedReason, report: launchReport)
    }

    private func ensureOneShotAnchorProject(
        in supervisor: SupervisorModel,
        request: SupervisorOneShotIntakeRequest,
        planDecision: AdaptivePoolPlanDecision
    ) async -> ProjectModel {
        if let existing = supervisor.activeProjects.first(where: { $0.name == "Root" }) {
            existing.taskDescription = request.userGoal
            existing.status = .running
            applyOneShotAnchorExecutionProfile(to: existing, planDecision: planDecision)
            return existing
        }

        if let existing = supervisor.activeProjects.first(where: {
            $0.status == .running || $0.status == .pending
        }) {
            existing.taskDescription = request.userGoal
            if existing.status == .pending {
                existing.status = .running
            }
            applyOneShotAnchorExecutionProfile(to: existing, planDecision: planDecision)
            return existing
        }

        let root = ProjectModel(
            name: "Root",
            taskDescription: request.userGoal,
            taskIcon: "point.3.connected.trianglepath.dotted",
            status: .running,
            modelName: oneShotAnchorModelName(for: planDecision),
            autonomyLevel: planDecision.riskSurface >= .high ? .fullAuto : .auto,
            budget: Budget(
                daily: planDecision.riskSurface >= .high ? 40.0 : 20.0,
                monthly: planDecision.riskSurface >= .high ? 1200.0 : 600.0
            )
        )
        applyOneShotAnchorExecutionProfile(to: root, planDecision: planDecision)
        supervisor.activeProjects.append(root)
        await supervisor.onProjectCreated(root)
        return root
    }

    private func applyOneShotAnchorExecutionProfile(
        to project: ProjectModel,
        planDecision: AdaptivePoolPlanDecision
    ) {
        let capability: ModelCapability
        let autonomy: AutonomyLevel
        let modelName: String

        switch planDecision.riskSurface {
        case .critical:
            capability = .expert
            autonomy = .fullAuto
            modelName = "one-shot-anchor-critical"
        case .high:
            capability = .advanced
            autonomy = .fullAuto
            modelName = "one-shot-anchor-high"
        case .medium:
            capability = .advanced
            autonomy = .auto
            modelName = "one-shot-anchor-medium"
        case .low:
            capability = .intermediate
            autonomy = .auto
            modelName = "one-shot-anchor-low"
        }

        project.autonomyLevel = autonomy
        project.currentModel = ModelInfo(
            id: modelName,
            name: modelName,
            displayName: modelName,
            type: .hubPaid,
            capability: capability,
            speed: capability == .expert ? .slow : .medium,
            costPerMillionTokens: capability == .expert ? 5.0 : 3.0,
            memorySize: nil,
            suitableFor: ["one-shot", "supervisor_anchor"],
            badge: nil,
            badgeColor: nil
        )
    }

    private func oneShotAnchorModelName(for planDecision: AdaptivePoolPlanDecision) -> String {
        switch planDecision.riskSurface {
        case .critical:
            return "one-shot-anchor-critical"
        case .high:
            return "one-shot-anchor-high"
        case .medium:
            return "one-shot-anchor-medium"
        case .low:
            return "one-shot-anchor-low"
        }
    }

    private func applyGuardedOneShotLaunchResumeOutcome(
        _ outcome: GuardedOneShotLaunchResumeOutcome,
        request: SupervisorOneShotIntakeRequest,
        planDecision: AdaptivePoolPlanDecision
    ) {
        switch outcome {
        case .launched(let report):
            let blockedCount = report.blockedLaneReasons.count
            let deferredCount = report.deferredLaneIDs.count
            let summary = "one-shot launch started: launched=\(report.launchedLaneIDs.count), blocked=\(blockedCount), deferred=\(deferredCount)"
            oneShotRunState = oneShotRunStateStore.transition(
                to: .running,
                owner: .supervisor,
                activePools: planDecision.poolPlan.map(\.poolID),
                activeLanes: report.launchedLaneIDs.isEmpty ? planDecision.poolPlan.flatMap(\.laneIDs) : report.launchedLaneIDs,
                topBlocker: "none",
                nextDirectedTarget: "Supervisor",
                userVisibleSummary: summary,
                evidenceRefs: OneShotControlPlaneSnapshot.defaultEvidenceRefs(),
                auditRef: request.auditRef
            )
            appendRecentEvent(summary)
            addSystemMessage("one-shot 已进入真实执行（launched=\(report.launchedLaneIDs.count)，blocked=\(blockedCount)，deferred=\(deferredCount)）。")

        case .blocked(let reason, let report):
            let blockedCount = report?.blockedLaneReasons.count ?? 0
            let summary = "one-shot launch blocked: \(reason)"
            oneShotRunState = oneShotRunStateStore.transition(
                to: .blocked,
                owner: .supervisor,
                activePools: planDecision.poolPlan.map(\.poolID),
                activeLanes: planDecision.poolPlan.flatMap(\.laneIDs),
                topBlocker: reason,
                nextDirectedTarget: "Supervisor",
                userVisibleSummary: summary,
                evidenceRefs: OneShotControlPlaneSnapshot.defaultEvidenceRefs(),
                auditRef: request.auditRef
            )
            appendRecentEvent(summary)
            addSystemMessage("one-shot 启动仍被阻塞（reason=\(reason)，blocked=\(blockedCount)）。")

        case .failedClosed(let reason):
            let summary = "failed closed: \(reason)"
            oneShotRunState = oneShotRunStateStore.transition(
                to: .failedClosed,
                owner: .supervisor,
                activePools: planDecision.poolPlan.map(\.poolID),
                activeLanes: planDecision.poolPlan.flatMap(\.laneIDs),
                topBlocker: reason,
                nextDirectedTarget: "Supervisor",
                userVisibleSummary: summary,
                evidenceRefs: OneShotControlPlaneSnapshot.defaultEvidenceRefs(),
                auditRef: request.auditRef
            )
            appendRecentEvent("one-shot launch failed closed: \(reason)")
            addSystemMessage("one-shot 启动失败闭锁（reason=\(reason)）。")
        }
    }

    private func normalizedOneShotFailureReason(_ raw: String?, fallback: String) -> String {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return fallback }
        let singleLine = trimmed.replacingOccurrences(of: "\n", with: " ")
        let sanitized = singleLine
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: "_")
        return sanitized.isEmpty ? fallback : sanitized.lowercased()
    }

    private func primaryBlockedReason(from report: LaneLaunchReport) -> String {
        let candidates = report.blockedLaneReasons
            .values
            .map { normalizedOneShotFailureReason($0, fallback: "lane_launch_blocked") }
            .sorted()
        return candidates.first ?? "lane_launch_blocked"
    }

    private func makeVoiceAuthorizationManagerFailureResolution(
        requestId: String,
        projectId: String?,
        templateId: String,
        riskTier: LaneRiskTier,
        reasonCode: String,
        challenge: HubIPCClient.VoiceGrantChallengeSnapshot?
    ) -> SupervisorVoiceAuthorizationResolution {
        let normalizedTemplate = templateId.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackTemplate = normalizedTemplate.isEmpty ? "voice.grant.v1" : normalizedTemplate
        let requiresMobileConfirm = challenge?.requiresMobileConfirm ?? (riskTier >= .high)
        let allowVoiceOnly = challenge?.allowVoiceOnly ?? (riskTier < .high)
        let policyRef = [
            "schema=\(SupervisorVoiceAuthorizationResolution.currentSchemaVersion)",
            "state=\(SupervisorVoiceAuthorizationResolution.State.failClosed.rawValue)",
            "risk_tier=\(riskTier.rawValue)",
            "requires_mobile_confirm=\(requiresMobileConfirm ? "true" : "false")",
            "allow_voice_only=\(allowVoiceOnly ? "true" : "false")",
            "reason_code=\(reasonCode)"
        ].joined(separator: ";")

        let nextAction: String = {
            switch reasonCode {
            case "voice_authorization_not_started":
                return "issue a new voice challenge before attempting verify"
            case "voice_authorization_inflight":
                return "wait for the current voice authorization round to finish"
            case "user_cancelled":
                return "reissue the challenge if authorization is still required"
            case "hub_env_missing":
                return "repair Hub pairing/runtime profile before retrying voice authorization"
            default:
                return "hold the gated action and repair the voice authorization path first"
            }
        }()

        return SupervisorVoiceAuthorizationResolution(
            schemaVersion: SupervisorVoiceAuthorizationResolution.currentSchemaVersion,
            state: .failClosed,
            ok: false,
            requestId: requestId.trimmingCharacters(in: .whitespacesAndNewlines),
            projectId: {
                let token = projectId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return token.isEmpty ? nil : token
            }(),
            templateId: fallbackTemplate,
            riskTier: riskTier.rawValue,
            challengeId: challenge?.challengeId,
            challenge: challenge,
            verified: false,
            requiresMobileConfirm: requiresMobileConfirm,
            allowVoiceOnly: allowVoiceOnly,
            denyCode: nil,
            reasonCode: reasonCode,
            transcriptHash: nil,
            semanticMatchScore: nil,
            policyRef: policyRef,
            nextAction: nextAction
        )
    }

    private func pushHubHeartbeatNotification(
        timeText: String,
        reason: String,
        projectCount: Int,
        changed: Bool,
        blockerCount: Int,
        blockerSignal: BlockerSignal,
        focusActionURL: String?,
        topSummary: String,
        queueSummary: String,
        permissionSummary: String,
        progressSummary: String,
        nextStepSummary: String,
        queuePendingCount: Int,
        permissionPendingCount: Int
    ) {
        let title: String
        let unread: Bool
        if blockerCount > 0, blockerSignal.escalated {
            title = "🚨 Supervisor 升级提醒：\(blockerCount) 个阻塞已持续 \(blockerSignal.streak) 次心跳"
            unread = true
        } else if !progressSummary.isEmpty {
            title = "🚀 Supervisor 心跳：已主动推进项目"
            unread = true
        } else if blockerCount > 0, blockerSignal.streak <= 1 {
            title = "🚧 Supervisor 心跳：检测到 \(blockerCount) 个阻塞"
            unread = true
        } else if blockerCount > 0 {
            title = "🚧 Supervisor 心跳：阻塞持续（静默）"
            unread = false
        } else if permissionPendingCount > 0 {
            title = "🛂 Supervisor 心跳：\(permissionPendingCount) 个权限申请待处理"
            unread = true
        } else if queuePendingCount > 0 {
            title = "⏳ Supervisor 心跳：\(queuePendingCount) 个项目排队中"
            unread = changed
        } else if changed {
            title = "Supervisor 心跳：项目有更新（静默）"
            unread = false
        } else {
            title = "Supervisor 心跳：状态稳定（静默）"
            unread = false
        }

        var blockerLines: [String] = []
        blockerLines.append(blockerCount > 0 ? "阻塞项目数：\(blockerCount)" : "阻塞项目数：0")
        if blockerCount > 0 {
            blockerLines.append("阻塞连续心跳：\(max(1, blockerSignal.streak)) 次")
            if blockerSignal.escalated {
                blockerLines.append("升级状态：已触发升级提醒")
            } else if blockerSignal.cooldownRemainingSec > 0 {
                let mins = max(1, Int(ceil(Double(blockerSignal.cooldownRemainingSec) / 60.0)))
                blockerLines.append("升级冷却中：约 \(mins) 分钟后可再次升级提醒")
            }
        }
        let body = """
时间：\(timeText)
原因：\(reason)
项目总数：\(projectCount)
\(blockerLines.joined(separator: "\n"))
排队项目数：\(queuePendingCount)
待授权项目数：\(permissionPendingCount)
主动推进：
\(progressSummary.isEmpty ? "（本轮无需介入）" : progressSummary)
重点看板：
\(topSummary)
排队态势：
\(queueSummary.isEmpty ? "（无）" : queueSummary)
权限申请：
\(permissionSummary.isEmpty ? "（无）" : permissionSummary)
Coder 下一步建议：
\(nextStepSummary.isEmpty ? "（暂无）" : nextStepSummary)
"""
        HubIPCClient.pushNotification(
            source: "X-Terminal",
            title: title,
            body: body,
            dedupeKey: heartbeatNotificationDedupeKey,
            actionURL: focusActionURL,
            unread: unread
        )
    }

    private func speakSupervisorHeartbeatUpdate(
        reason: String,
        changed: Bool,
        projects: [AXProjectEntry],
        blockerProjects: [(projectId: String, blocker: String)],
        blockerSignal: BlockerSignal,
        permissionSignals: [ProjectPermissionSignal],
        queueSignals: [ProjectQueueSignal],
        progressActions: [HeartbeatAutoProgressAction],
        nextStepSummary: String
    ) {
        guard let job = heartbeatVoiceJob(
            reason: reason,
            changed: changed,
            projects: projects,
            blockerProjects: blockerProjects,
            blockerSignal: blockerSignal,
            permissionSignals: permissionSignals,
            queueSignals: queueSignals,
            progressActions: progressActions,
            nextStepSummary: nextStepSummary
        ) else {
            return
        }

        _ = supervisorSpeechSynthesizer.speak(
            job: job,
            preferences: currentVoicePreferences()
        )
    }

    @discardableResult
    private func speakSupervisorVoiceReply(_ text: String) -> SupervisorSpeechSynthesizer.Outcome {
        let script = conciseVoiceReplyScript(text)
        guard !script.isEmpty else { return .suppressed("empty_script") }
        let dedupeKey = "voice-reply:\(capped(script.joined(separator: "|"), maxChars: 96))"
        let job = SupervisorVoiceTTSJob(
            trigger: .userQueryReply,
            priority: .normal,
            script: script,
            dedupeKey: dedupeKey
        )
        return supervisorSpeechSynthesizer.speak(
            job: job,
            preferences: currentVoicePreferences()
        )
    }

    private func heartbeatVoiceJob(
        reason: String,
        changed: Bool,
        projects: [AXProjectEntry],
        blockerProjects: [(projectId: String, blocker: String)],
        blockerSignal: BlockerSignal,
        permissionSignals: [ProjectPermissionSignal],
        queueSignals: [ProjectQueueSignal],
        progressActions: [HeartbeatAutoProgressAction],
        nextStepSummary: String
    ) -> SupervisorVoiceTTSJob? {
        let nextStepLine = conciseHeartbeatNextStep(nextStepSummary)
        let progressVoiceLine: String? = {
            guard let first = progressActions.first else { return nil }
            switch first.kind {
            case .recover:
                return "我已主动恢复 \(first.projectName)。"
            case .start:
                return "我已主动启动 \(first.projectName)。"
            }
        }()

        if let firstBlocker = blockerProjects.first {
            let projectName = heartbeatProjectName(for: firstBlocker.projectId, in: projects) ?? "当前项目"
            var script = [
                "Supervisor 更新。当前有 \(blockerProjects.count) 个阻塞项目。",
                "\(projectName) 阻塞：\(capped(firstBlocker.blocker, maxChars: 36))。"
            ]
            if let progressVoiceLine {
                script.append(progressVoiceLine)
            }
            if blockerSignal.escalated {
                script.append("该阻塞已持续 \(max(1, blockerSignal.streak)) 次心跳。")
            }
            if let nextStepLine {
                script.append("建议下一步：\(nextStepLine)。")
            }
            return SupervisorVoiceTTSJob(
                trigger: .blocked,
                priority: blockerSignal.escalated ? .interrupt : .normal,
                script: script,
                dedupeKey: "heartbeat:blocker:\(firstBlocker.projectId):\(capped(firstBlocker.blocker, maxChars: 48)):\(blockerSignal.streak)"
            )
        }

        if let permission = permissionSignals.first {
            var script = [
                "Supervisor 更新。当前有 \(permissionSignals.count) 个待授权项目。",
                "\(permission.projectName) 需要处理：\(capped(permission.summary, maxChars: 36))。"
            ]
            if let progressVoiceLine {
                script.append(progressVoiceLine)
            }
            if let nextStepLine {
                script.append("建议下一步：\(nextStepLine)。")
            }
            return SupervisorVoiceTTSJob(
                trigger: .blocked,
                priority: .normal,
                script: script,
                dedupeKey: "heartbeat:permission:\(permission.projectId):\(permission.kind.rawValue):\(capped(permission.summary, maxChars: 48))"
            )
        }

        guard changed || reason != "timer" || !progressActions.isEmpty else {
            return nil
        }

        let queueCount = queueSignals.count
        let projectCount = projects.count
        let leadProjectName = queueSignals.first?.project.displayName ?? projects.first?.displayName ?? "当前项目"
        var summary = "Supervisor 更新。当前 \(projectCount) 个项目，无阻塞。"
        if queueCount > 0 {
            summary += " \(queueCount) 个项目仍在排队。"
        } else {
            summary += " 主线运行稳定。"
        }
        var script = [summary]
        if let progressVoiceLine {
            script.append(progressVoiceLine)
        }
        if queueCount > 0 {
            script.append("当前关注：\(leadProjectName)。")
        }
        if let nextStepLine {
            script.append("建议下一步：\(nextStepLine)。")
        }
        return SupervisorVoiceTTSJob(
            trigger: .completed,
            priority: .quiet,
            script: script,
            dedupeKey: "heartbeat:summary:\(reason):\(projectCount):\(queueCount):\(leadProjectName)"
        )
    }

    private func heartbeatProjectName(
        for projectId: String,
        in projects: [AXProjectEntry]
    ) -> String? {
        projects.first(where: { $0.projectId == projectId })?.displayName
    }

    private func conciseHeartbeatNextStep(_ text: String) -> String? {
        for rawLine in text.split(separator: "\n") {
            let line = rawLine
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "•", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !line.isEmpty {
                return capped(line, maxChars: 40)
            }
        }
        return nil
    }

    private func conciseVoiceReplyScript(_ text: String) -> [String] {
        let sanitizedLines = text
            .replacingOccurrences(of: "```", with: " ")
            .components(separatedBy: .newlines)
            .map { line in
                line
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "•", with: "")
                    .replacingOccurrences(of: "📊", with: "")
                    .replacingOccurrences(of: "🚧", with: "")
                    .replacingOccurrences(of: "🎯", with: "")
                    .replacingOccurrences(of: "✅", with: "")
                    .replacingOccurrences(of: "❌", with: "")
                    .replacingOccurrences(of: "⚠️", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { line in
                !line.isEmpty &&
                !line.hasPrefix("[") &&
                !line.hasPrefix("```")
            }

        guard !sanitizedLines.isEmpty else { return [] }

        let lead = capped(sanitizedLines[0], maxChars: 80)
        if sanitizedLines.count == 1 {
            return [lead]
        }

        let second = capped(sanitizedLines[1], maxChars: 80)
        if second.isEmpty {
            return [lead]
        }
        return [lead, second]
    }

    private func supervisorActionURL(
        projectId: String?,
        grantRequestId: String? = nil,
        capability: String? = nil
    ) -> String? {
        let grantId = grantRequestId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let capabilityToken = capability?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if let raw = projectId?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
            var components = URLComponents()
            components.scheme = "xterminal"
            components.host = "project"
            var queryItems: [URLQueryItem] = [
                URLQueryItem(name: "project_id", value: raw),
                URLQueryItem(name: "pane", value: "chat"),
                URLQueryItem(name: "open", value: "supervisor"),
            ]
            if !grantId.isEmpty {
                queryItems.append(URLQueryItem(name: "focus", value: "grant"))
                queryItems.append(URLQueryItem(name: "grant_request_id", value: grantId))
            }
            if !capabilityToken.isEmpty {
                queryItems.append(URLQueryItem(name: "grant_capability", value: capabilityToken))
            }
            components.queryItems = queryItems
            return components.url?.absoluteString
        }
        if !grantId.isEmpty || !capabilityToken.isEmpty {
            var components = URLComponents()
            components.scheme = "xterminal"
            components.host = "supervisor"
            var queryItems: [URLQueryItem] = []
            if !grantId.isEmpty {
                queryItems.append(URLQueryItem(name: "focus", value: "grant"))
                queryItems.append(URLQueryItem(name: "grant_request_id", value: grantId))
            }
            if !capabilityToken.isEmpty {
                queryItems.append(URLQueryItem(name: "grant_capability", value: capabilityToken))
            }
            components.queryItems = queryItems
            return components.url?.absoluteString
        }
        return "xterminal://supervisor"
    }

    private func runSupervisorDoctorPreflight(
        reason: String,
        emitSystemMessage: Bool
    ) -> SupervisorDoctorReport {
        let input = SupervisorDoctorChecker.loadDefaultInputBundle()
        let report = SupervisorDoctorChecker.runAndPersist(input: input)
        doctorReport = report
        doctorSuggestionCards = report.suggestions
        doctorHasBlockingFindings = report.summary.blockingCount > 0
        releaseBlockedByDoctorWithoutReport = report.summary.releaseBlockedByDoctorWithoutReport
        doctorReportPath = input.reportURL.path

        if report.ok {
            doctorStatusLine = "Doctor 已通过（\(report.summary.warningCount) 个告警）"
        } else {
            doctorStatusLine = "Doctor 阻断：\(report.summary.blockingCount) 项（\(report.summary.warningCount) 告警）"
        }

        if emitSystemMessage {
            let headline = report.ok ? "✅ Doctor 预检通过" : "⛔️ Doctor 预检阻断"
            let body = "\(headline)（reason=\(reason)）\n\(renderDoctorSummary(report))"
            addSystemMessage(body)
        }
        return report
    }

    private func handleLocalPreflightCommand(_ userMessage: String) async -> String? {
        let trimmed = userMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let automationResponse = performAutomationRuntimeCommand(trimmed) {
            return automationResponse
        }
        if shouldRunDoctorCommand(trimmed) {
            let report = runSupervisorDoctorPreflight(reason: "user_command_doctor", emitSystemMessage: false)
            return renderDoctorSummary(report)
        }
        if shouldRunSecretsDryRunCommand(trimmed) {
            let report = runSupervisorDoctorPreflight(reason: "user_command_secrets_dry_run", emitSystemMessage: false)
            return renderSecretsDryRunSummary(report)
        }
        if shouldShowXTReadyIncidentEventsStatusCommand(trimmed) {
            return renderXTReadyIncidentEventsStatus()
        }
        if shouldExportXTReadyIncidentEventsCommand(trimmed) {
            let result = exportXTReadyIncidentEventsReport()
            return renderXTReadyIncidentExportSummary(result)
        }
        if shouldInjectXTReadyIncidentsCommand(trimmed) {
            return await injectXTReadyIncidents(using: trimmed)
        }
        return nil
    }

    @discardableResult
    func performAutomationRuntimeCommand(
        _ userMessage: String,
        emitSystemMessage: Bool = false
    ) -> String? {
        let trimmed = userMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard looksLikeAutomationRuntimeCommand(trimmed) else { return nil }

        let response: String
        guard let command = parseAutomationRuntimeCommand(trimmed) else {
            response = automationRuntimeCommandHelpText()
            if emitSystemMessage {
                addSystemMessage(response)
            }
            return response
        }

        do {
            switch command.action {
            case .help:
                response = automationRuntimeCommandHelpText()

            case .status:
                let (project, ctx) = try resolveAutomationCommandProject(command.projectRef)
                response = try renderAutomationRuntimeStatus(for: project, ctx: ctx)

            case .start:
                let (project, ctx) = try resolveAutomationCommandProject(command.projectRef)
                let request = try makeManualAutomationRunRequest(for: project, ctx: ctx)
                let prepared = try startAutomationRun(for: ctx, request: request, emitSystemMessage: false)
                response = renderAutomationStartSummary(project: project, prepared: prepared)

            case .recover:
                let (project, ctx) = try resolveAutomationCommandProject(command.projectRef)
                let decision = try recoverLatestAutomationRun(
                    for: ctx,
                    checkpointAgeSeconds: 0,
                    auditRef: automationRuntimeAuditRef(action: "recover", project: project),
                    emitSystemMessage: false
                )
                response = renderAutomationRecoverySummary(
                    project: project,
                    decision: decision,
                    retryPackage: automationLatestRetryPackage
                )

            case .cancel:
                let (project, ctx) = try resolveAutomationCommandProject(command.projectRef)
                let runID = try latestAutomationLaunchRef(for: ctx)
                let decision = try cancelAutomationRun(
                    for: ctx,
                    runID: runID,
                    auditRef: automationRuntimeAuditRef(action: "cancel", project: project),
                    emitSystemMessage: false
                )
                response = renderAutomationCancelSummary(project: project, decision: decision)

            case .advance(let nextState):
                let (project, ctx) = try resolveAutomationCommandProject(command.projectRef)
                let runID = try latestAutomationLaunchRef(for: ctx)
                let checkpoint = try advanceAutomationRun(
                    for: ctx,
                    to: nextState,
                    runID: runID,
                    auditRef: automationRuntimeAuditRef(action: "advance_\(nextState.rawValue)", project: project),
                    emitSystemMessage: false
                )
                response = renderAutomationAdvanceSummary(project: project, checkpoint: checkpoint)

            case .selfIterateStatus:
                let (project, ctx) = try resolveAutomationCommandProject(command.projectRef)
                let config = try AXProjectStore.loadOrCreateConfig(for: ctx)
                response = renderAutomationSelfIterateSummary(
                    project: project,
                    config: config,
                    headline: "🧠 automation self-iterate 状态"
                )

            case .selfIterateSet(let enabled):
                let (project, ctx) = try resolveAutomationCommandProject(command.projectRef)
                let config = try updateAutomationSelfIterateConfig(
                    for: project,
                    ctx: ctx,
                    enabled: enabled
                )
                response = renderAutomationSelfIterateSummary(
                    project: project,
                    config: config,
                    headline: enabled
                        ? "🧠 automation self-iterate 已开启"
                        : "🧠 automation self-iterate 已关闭"
                )

            case .selfIterateMax(let depth):
                let (project, ctx) = try resolveAutomationCommandProject(command.projectRef)
                let config = try updateAutomationSelfIterateConfig(
                    for: project,
                    ctx: ctx,
                    maxAutoRetryDepth: depth
                )
                response = renderAutomationSelfIterateSummary(
                    project: project,
                    config: config,
                    headline: "🧠 automation self-iterate 深度已更新"
                )
            }
        } catch {
            response = renderAutomationRuntimeError(error)
        }

        if emitSystemMessage {
            addSystemMessage(response)
        }
        return response
    }

    private func looksLikeAutomationRuntimeCommand(_ text: String) -> Bool {
        let head = text
            .split(whereSeparator: \.isWhitespace)
            .first?
            .lowercased() ?? ""
        return head == "/automation" || head == "automation"
    }

    private func parseAutomationRuntimeCommand(_ text: String) -> ParsedAutomationRuntimeCommand? {
        let tokens = text
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        guard let head = tokens.first?.lowercased(),
              head == "/automation" || head == "automation" else {
            return nil
        }
        guard tokens.count >= 2 else {
            return ParsedAutomationRuntimeCommand(action: .help, projectRef: nil)
        }

        let actionToken = normalizedAutomationCommandToken(tokens[1])
        switch actionToken {
        case "help":
            return ParsedAutomationRuntimeCommand(action: .help, projectRef: nil)
        case "status":
            return ParsedAutomationRuntimeCommand(
                action: .status,
                projectRef: automationProjectRef(from: tokens, startingAt: 2)
            )
        case "start":
            return ParsedAutomationRuntimeCommand(
                action: .start,
                projectRef: automationProjectRef(from: tokens, startingAt: 2)
            )
        case "recover":
            return ParsedAutomationRuntimeCommand(
                action: .recover,
                projectRef: automationProjectRef(from: tokens, startingAt: 2)
            )
        case "cancel":
            return ParsedAutomationRuntimeCommand(
                action: .cancel,
                projectRef: automationProjectRef(from: tokens, startingAt: 2)
            )
        case "advance":
            guard tokens.count >= 3,
                  let nextState = automationRunState(from: tokens[2]) else {
                return nil
            }
            return ParsedAutomationRuntimeCommand(
                action: .advance(nextState),
                projectRef: automationProjectRef(from: tokens, startingAt: 3)
            )
        case "self_iterate":
            let modeToken = normalizedAutomationSelfIterateCommandToken(tokens.count > 2 ? tokens[2] : "")
            switch modeToken {
            case "", "status":
                return ParsedAutomationRuntimeCommand(
                    action: .selfIterateStatus,
                    projectRef: automationProjectRef(from: tokens, startingAt: modeToken.isEmpty ? 2 : 3)
                )
            case "on":
                return ParsedAutomationRuntimeCommand(
                    action: .selfIterateSet(true),
                    projectRef: automationProjectRef(from: tokens, startingAt: 3)
                )
            case "off":
                return ParsedAutomationRuntimeCommand(
                    action: .selfIterateSet(false),
                    projectRef: automationProjectRef(from: tokens, startingAt: 3)
                )
            case "max":
                guard tokens.count >= 4,
                      let depth = Int(tokens[3].trimmingCharacters(in: .whitespacesAndNewlines)),
                      depth >= 1 else {
                    return nil
                }
                return ParsedAutomationRuntimeCommand(
                    action: .selfIterateMax(depth),
                    projectRef: automationProjectRef(from: tokens, startingAt: 4)
                )
            default:
                return nil
            }
        default:
            return nil
        }
    }

    private func normalizedAutomationCommandToken(_ token: String) -> String {
        let lowered = token.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch lowered {
        case "help", "帮助":
            return "help"
        case "status", "状态":
            return "status"
        case "start", "启动", "开始":
            return "start"
        case "recover", "恢复":
            return "recover"
        case "cancel", "取消", "停止":
            return "cancel"
        case "advance", "推进", "更新":
            return "advance"
        case "self-iterate", "self_iterate", "selfiterate", "自迭代":
            return "self_iterate"
        default:
            return lowered
        }
    }

    private func normalizedAutomationSelfIterateCommandToken(_ token: String) -> String {
        let lowered = token.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch lowered {
        case "", "status", "状态":
            return lowered.isEmpty ? "" : "status"
        case "on", "enable", "enabled", "开启", "打开", "启用":
            return "on"
        case "off", "disable", "disabled", "关闭", "关掉", "停用":
            return "off"
        case "max", "depth", "最大", "深度":
            return "max"
        default:
            return lowered
        }
    }

    private func automationProjectRef(from tokens: [String], startingAt index: Int) -> String? {
        guard index < tokens.count else { return nil }
        let raw = tokens[index...].joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        let sanitized = sanitizeProjectReference(raw)
        return sanitized.isEmpty ? nil : sanitized
    }

    private func automationRunState(from raw: String) -> XTAutomationRunState? {
        let token = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
        switch token {
        case "queued", "queue", "排队", "排队中":
            return .queued
        case "running", "run", "运行", "运行中":
            return .running
        case "blocked", "block", "阻塞", "卡住":
            return .blocked
        case "takeover", "接管":
            return .takeover
        case "delivered", "deliver", "交付", "已交付":
            return .delivered
        case "failed", "fail", "失败":
            return .failed
        case "downgraded", "downgrade", "degraded", "降级":
            return .downgraded
        default:
            return nil
        }
    }

    private func automationRuntimeCommandHelpText() -> String {
        """
🤖 Automation Runtime 命令
- /automation status [projectRef]
- /automation start [projectRef]
- /automation recover [projectRef]
- /automation cancel [projectRef]
- /automation advance <queued|running|blocked|takeover|delivered|failed|downgraded> [projectRef]
- /automation self-iterate status [projectRef]
- /automation self-iterate on [projectRef]
- /automation self-iterate off [projectRef]
- /automation self-iterate max <depth> [projectRef]

如果不传 projectRef，默认使用当前选中的项目；若当前未选中且存在多个项目，请显式指定项目名或 project_id。
"""
    }

    private func resolveAutomationCommandProject(_ projectRef: String?) throws -> (AXProjectEntry, AXProjectContext) {
        if let rawRef = projectRef?.trimmingCharacters(in: .whitespacesAndNewlines),
           !rawRef.isEmpty {
            let normalizedRef = sanitizeProjectReference(rawRef)
            switch resolveProjectReference(normalizedRef) {
            case .matched(let project):
                guard let ctx = projectContext(from: project) else {
                    throw SupervisorAutomationRuntimeError.projectContextMissing(project.projectId)
                }
                return (project, ctx)
            case .notFound:
                throw SupervisorAutomationRuntimeError.projectNotFound(normalizedRef)
            case .ambiguous(let candidates):
                let labels = candidates.map { "\($0.displayName)(\($0.projectId))" }
                throw SupervisorAutomationRuntimeError.projectAmbiguous(normalizedRef, labels)
            }
        }

        if let selectedProjectID = appModel?.selectedProjectId,
           selectedProjectID != AXProjectRegistry.globalHomeId,
           let project = allProjects().first(where: { $0.projectId == selectedProjectID }) {
            guard let ctx = projectContext(from: project) else {
                throw SupervisorAutomationRuntimeError.projectContextMissing(project.projectId)
            }
            return (project, ctx)
        }

        let projects = allProjects()
        if projects.count == 1, let project = projects.first {
            guard let ctx = projectContext(from: project) else {
                throw SupervisorAutomationRuntimeError.projectContextMissing(project.projectId)
            }
            return (project, ctx)
        }

        throw SupervisorAutomationRuntimeError.projectSelectionMissing
    }

    @discardableResult
    func ingestAutomationExternalTrigger(
        _ ingress: SupervisorAutomationExternalTriggerIngress,
        emitSystemMessage: Bool = false
    ) -> SupervisorAutomationExternalTriggerResult {
        let projectId = ingress.projectId.trimmingCharacters(in: .whitespacesAndNewlines)
        let triggerId = ingress.triggerId.trimmingCharacters(in: .whitespacesAndNewlines)
        let auditRef = automationExternalTriggerAuditRef(
            projectId: projectId,
            triggerId: triggerId,
            now: ingress.receivedAt
        )

        guard !projectId.isEmpty else {
            return SupervisorAutomationExternalTriggerResult(
                projectId: "",
                triggerId: triggerId,
                triggerType: ingress.triggerType,
                decision: .failClosed,
                reasonCode: "project_id_missing",
                runId: nil,
                auditRef: auditRef
            )
        }

        guard let project = allProjects().first(where: { $0.projectId == projectId }),
              let ctx = projectContext(from: project) else {
            return SupervisorAutomationExternalTriggerResult(
                projectId: projectId,
                triggerId: triggerId,
                triggerType: ingress.triggerType,
                decision: .failClosed,
                reasonCode: "project_context_missing",
                runId: nil,
                auditRef: auditRef
            )
        }

        return ingestAutomationExternalTrigger(
            ingress,
            for: project,
            ctx: ctx,
            auditRef: auditRef,
            emitSystemMessage: emitSystemMessage
        )
    }

    @discardableResult
    func serviceAutomationScheduleTriggers(
        now: Date = Date(),
        emitSystemMessage: Bool = false
    ) -> [SupervisorAutomationExternalTriggerResult] {
        let projects = allProjects()
        guard !projects.isEmpty else { return [] }

        var results: [SupervisorAutomationExternalTriggerResult] = []
        for project in projects {
            guard let ctx = projectContext(from: project) else { continue }
            guard automationProjectHasBlockingRun(ctx) == false else { continue }
            guard let config = try? AXProjectStore.loadOrCreateConfig(for: ctx),
                  let recipe = config.activeAutomationRecipe,
                  recipe.lifecycleState == .ready else {
                continue
            }

            let scheduleTriggerIds = automationTriggerIds(from: recipe.triggerRefs, matching: .schedule)
            guard !scheduleTriggerIds.isEmpty else { continue }

            let projectToken = normalizedLookupKey(project.displayName).isEmpty
                ? normalizedLookupKey(project.projectId)
                : normalizedLookupKey(project.displayName)

            for triggerId in scheduleTriggerIds {
                let intervalSec = automationScheduleMinimumInterval(for: triggerId)
                let windowStart = Int(floor(now.timeIntervalSince1970 / Double(intervalSec)) * Double(intervalSec))
                let dedupeKey = automationExternalTriggerDeterministicDigest(
                    stable: "schedule|\(project.projectId)|\(triggerId)|\(windowStart)"
                )
                if automationExternalTriggerReplaySeen(
                    projectId: project.projectId,
                    dedupeKey: dedupeKey,
                    ctx: ctx
                ) {
                    continue
                }
                if let lastAcceptedAt = automationExternalTriggerLastAcceptedAt(
                    projectId: project.projectId,
                    triggerId: triggerId,
                    ctx: ctx
                ),
                   now.timeIntervalSince1970 - lastAcceptedAt < Double(intervalSec) {
                    continue
                }

                let triggerToken = xtAutomationActionToken(triggerId, fallback: "schedule")
                let ingress = SupervisorAutomationExternalTriggerIngress(
                    projectId: project.projectId,
                    triggerId: triggerId,
                    triggerType: .schedule,
                    source: .timer,
                    payloadRef: "local://supervisor/scheduler_poll/\(projectToken)/\(triggerToken)/\(windowStart)",
                    dedupeKey: dedupeKey,
                    receivedAt: now,
                    ingressChannel: "scheduler_poll"
                )
                let result = ingestAutomationExternalTrigger(
                    ingress,
                    for: project,
                    ctx: ctx,
                    auditRef: automationExternalTriggerAuditRef(
                        projectId: project.projectId,
                        triggerId: triggerId,
                        now: now
                    ),
                    emitSystemMessage: emitSystemMessage
                )
                results.append(result)
                if result.decision == .run {
                    break
                }
            }
        }

        return results
    }

    @discardableResult
    func serviceHubConnectorIngressReceiptsForTesting(
        _ snapshot: HubIPCClient.ConnectorIngressSnapshot,
        now: Date = Date(),
        emitSystemMessage: Bool = false
    ) -> [SupervisorAutomationExternalTriggerResult] {
        connectorIngressSnapshot = snapshot
        connectorIngressLastSuccessAt = max(now.timeIntervalSince1970, snapshot.updatedAtMs / 1000.0)
        return serviceHubConnectorIngressReceipts(now: now, emitSystemMessage: emitSystemMessage)
    }

    @discardableResult
    private func serviceHubConnectorIngressReceipts(
        now: Date = Date(),
        emitSystemMessage: Bool = false
    ) -> [SupervisorAutomationExternalTriggerResult] {
        guard let snapshot = connectorIngressSnapshot else { return [] }

        let snapshotUpdatedAtSec: TimeInterval = {
            let ms = max(0, snapshot.updatedAtMs)
            if ms > 0 {
                return ms / 1000.0
            }
            return connectorIngressLastSuccessAt
        }()
        if snapshotUpdatedAtSec > 0, now.timeIntervalSince1970 - snapshotUpdatedAtSec > schedulerSnapshotStaleSec {
            return []
        }

        let projectMap = allProjects().reduce(into: [String: AXProjectEntry]()) { partialResult, project in
            partialResult[project.projectId] = project
        }
        guard !projectMap.isEmpty else { return [] }

        let receipts = snapshot.items.sorted { lhs, rhs in
            if lhs.receivedAtMs != rhs.receivedAtMs {
                return lhs.receivedAtMs < rhs.receivedAtMs
            }
            return lhs.receiptId.localizedCaseInsensitiveCompare(rhs.receiptId) == .orderedAscending
        }

        var results: [SupervisorAutomationExternalTriggerResult] = []
        var blockedProjects: Set<String> = []

        for receipt in receipts {
            let projectId = receipt.projectId.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !projectId.isEmpty else { continue }
            guard blockedProjects.contains(projectId) == false else { continue }
            guard let project = projectMap[projectId],
                  let ctx = projectContext(from: project) else {
                continue
            }
            let dedupeKey = hubConnectorIngressDedupeKey(for: receipt)
            if automationExternalTriggerReplaySeen(
                projectId: projectId,
                dedupeKey: dedupeKey,
                ctx: ctx
            ) {
                continue
            }
            if automationProjectHasBlockingRun(ctx) {
                blockedProjects.insert(projectId)
                continue
            }

            let resolution = resolveHubConnectorIngressReceipt(receipt, ctx: ctx, fallbackNow: now)
            switch resolution {
            case .route(let ingress):
                let result = ingestAutomationExternalTrigger(
                    ingress,
                    for: project,
                    ctx: ctx,
                    auditRef: automationExternalTriggerAuditRef(
                        projectId: projectId,
                        triggerId: ingress.triggerId,
                        now: ingress.receivedAt
                    ),
                    emitSystemMessage: emitSystemMessage
                )
                results.append(result)
                if result.decision == .run || result.decision == .hold {
                    blockedProjects.insert(projectId)
                }
            case .failClosed(let ingress, let reasonCode):
                let result = recordAutomationExternalTriggerDecision(
                    ingress: ingress,
                    decision: .failClosed,
                    reasonCode: reasonCode,
                    runId: nil,
                    auditRef: automationExternalTriggerAuditRef(
                        projectId: projectId,
                        triggerId: ingress.triggerId,
                        now: ingress.receivedAt
                    ),
                    ctx: ctx,
                    emitSystemMessage: emitSystemMessage
                )
                results.append(result)
            }
        }

        return results
    }

    private func resolveHubConnectorIngressReceipt(
        _ receipt: HubIPCClient.ConnectorIngressReceipt,
        ctx: AXProjectContext,
        fallbackNow: Date
    ) -> HubConnectorIngressResolution {
        let projectId = receipt.projectId.trimmingCharacters(in: .whitespacesAndNewlines)
        let triggerType = hubConnectorIngressTriggerType(for: receipt)
        let receivedAt = hubConnectorIngressReceivedAt(receipt, fallbackNow: fallbackNow)
        let payloadRef = hubConnectorIngressPayloadRef(for: receipt)
        let dedupeKey = hubConnectorIngressDedupeKey(for: receipt)
        let resolvedSource = hubConnectorIngressSource(for: receipt.connector)
        let fallbackIngress = SupervisorAutomationExternalTriggerIngress(
            projectId: projectId,
            triggerId: hubConnectorIngressFallbackTriggerId(for: receipt),
            triggerType: triggerType,
            source: resolvedSource ?? .hub,
            payloadRef: payloadRef,
            dedupeKey: dedupeKey,
            receivedAt: receivedAt,
            ingressChannel: "hub_connector_receipt_snapshot"
        )

        guard let source = resolvedSource else {
            return .failClosed(fallbackIngress, "hub_ingress_source_unsupported")
        }
        guard let config = try? AXProjectStore.loadOrCreateConfig(for: ctx),
              let recipe = config.activeAutomationRecipe,
              recipe.lifecycleState == .ready else {
            return .failClosed(fallbackIngress, "hub_ingress_recipe_unavailable")
        }

        let candidates = automationTriggerIds(from: recipe.triggerRefs, matching: triggerType)
        guard let triggerId = resolveHubConnectorTriggerID(
            candidates: candidates,
            connector: receipt.connector,
            channelScope: receipt.channelScope,
            targetId: receipt.targetId,
            sourceId: receipt.sourceId
        ) else {
            return .failClosed(fallbackIngress, "hub_ingress_trigger_unresolved")
        }

        return .route(
            SupervisorAutomationExternalTriggerIngress(
                projectId: projectId,
                triggerId: triggerId,
                triggerType: triggerType,
                source: source,
                payloadRef: payloadRef,
                dedupeKey: dedupeKey,
                receivedAt: receivedAt,
                ingressChannel: "hub_connector_receipt_snapshot"
            )
        )
    }

    private func hubConnectorIngressTriggerType(
        for receipt: HubIPCClient.ConnectorIngressReceipt
    ) -> XTAutomationTriggerType {
        normalizedLookupKey(receipt.ingressType) == XTAutomationTriggerType.webhook.rawValue
            ? .webhook
            : .connectorEvent
    }

    private func hubConnectorIngressSource(for connector: String) -> XTAutomationTriggerSource? {
        switch normalizedLookupKey(connector) {
        case XTAutomationTriggerSource.github.rawValue:
            return .github
        case XTAutomationTriggerSource.slack.rawValue:
            return .slack
        case XTAutomationTriggerSource.telegram.rawValue:
            return .telegram
        default:
            return nil
        }
    }

    private func hubConnectorIngressReceivedAt(
        _ receipt: HubIPCClient.ConnectorIngressReceipt,
        fallbackNow: Date
    ) -> Date {
        let receivedAtMs = max(0, receipt.receivedAtMs)
        guard receivedAtMs > 0 else { return fallbackNow }
        return Date(timeIntervalSince1970: receivedAtMs / 1000.0)
    }

    private func hubConnectorIngressPayloadRef(
        for receipt: HubIPCClient.ConnectorIngressReceipt
    ) -> String {
        let connectorToken = xtAutomationActionToken(receipt.connector, fallback: "connector")
        let receiptToken = xtAutomationActionToken(receipt.receiptId, fallback: "receipt")
        return "hub://connector_ingress/\(connectorToken)/\(receiptToken)"
    }

    private func hubConnectorIngressFallbackTriggerId(
        for receipt: HubIPCClient.ConnectorIngressReceipt
    ) -> String {
        let connectorToken = xtAutomationActionToken(receipt.connector, fallback: "connector")
        let receiptToken = xtAutomationActionToken(receipt.receiptId, fallback: "receipt")
        return "hub_receipt/\(connectorToken)/\(receiptToken)"
    }

    private func hubConnectorIngressDedupeKey(
        for receipt: HubIPCClient.ConnectorIngressReceipt
    ) -> String {
        let provided = receipt.dedupeKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !provided.isEmpty {
            return provided
        }
        return automationExternalTriggerDeterministicDigest(
            stable: [
                "hub_connector_receipt",
                receipt.receiptId,
                receipt.projectId,
                receipt.connector,
                receipt.messageId,
                receipt.sourceId,
            ].joined(separator: "|")
        )
    }

    private func resolveHubConnectorTriggerID(
        candidates: [String],
        connector: String,
        channelScope: String,
        targetId: String,
        sourceId: String
    ) -> String? {
        let normalizedCandidates = candidates
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !normalizedCandidates.isEmpty else { return nil }
        if normalizedCandidates.count == 1 {
            return normalizedCandidates[0]
        }

        let connectorToken = normalizedLookupKey(connector)
        let channelToken = normalizedLookupKey(channelScope)
        let targetToken = normalizedLookupKey(targetId)
        let sourceToken = normalizedLookupKey(sourceId)

        let scored = normalizedCandidates.map { candidate -> (candidate: String, score: Int) in
            let key = normalizedLookupKey(candidate)
            var score = 0
            if !connectorToken.isEmpty, key.contains(connectorToken) {
                score += 8
            }
            if !channelToken.isEmpty, key.contains(channelToken) {
                score += 4
            }
            if !targetToken.isEmpty, key.contains(targetToken) {
                score += 2
            }
            if !sourceToken.isEmpty, key.contains(sourceToken) {
                score += 1
            }
            return (candidate, score)
        }
        .sorted { lhs, rhs in
            if lhs.score != rhs.score {
                return lhs.score > rhs.score
            }
            return lhs.candidate.localizedCaseInsensitiveCompare(rhs.candidate) == .orderedAscending
        }

        guard let best = scored.first, best.score > 0 else { return nil }
        if scored.count > 1, best.score == scored[1].score {
            return nil
        }
        return best.candidate
    }

    private func recordAutomationExternalTriggerDecision(
        ingress: SupervisorAutomationExternalTriggerIngress,
        decision: SupervisorAutomationExternalTriggerDecision,
        reasonCode: String,
        runId: String?,
        auditRef: String,
        ctx: AXProjectContext,
        emitSystemMessage: Bool
    ) -> SupervisorAutomationExternalTriggerResult {
        let projectId = ingress.projectId.trimmingCharacters(in: .whitespacesAndNewlines)
        let triggerId = ingress.triggerId.trimmingCharacters(in: .whitespacesAndNewlines)
        let dedupeKey = ingress.dedupeKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let acceptedAt = ingress.receivedAt.timeIntervalSince1970

        appendAutomationExternalTriggerRouteLog(
            ingress: ingress,
            decision: decision,
            reasonCode: reasonCode,
            runId: runId,
            auditRef: auditRef,
            ctx: ctx
        )

        if decision != .hold, !dedupeKey.isEmpty {
            let replayKey = automationExternalTriggerReplayLedgerKey(projectId: projectId, dedupeKey: dedupeKey)
            automationExternalTriggerReplayLedger[replayKey] = max(
                acceptedAt,
                automationExternalTriggerReplayLedger[replayKey] ?? 0
            )
        }
        if decision == .run, !triggerId.isEmpty {
            let acceptedKey = automationExternalTriggerAcceptedLedgerKey(projectId: projectId, triggerId: triggerId)
            automationExternalTriggerAcceptedLedger[acceptedKey] = max(
                acceptedAt,
                automationExternalTriggerAcceptedLedger[acceptedKey] ?? 0
            )
            appendRecentEvent("automation trigger run: \(ctx.projectName()) -> \(triggerId)")
        } else if decision == .failClosed {
            appendRecentEvent("automation trigger fail-closed: \(ctx.projectName()) -> \(triggerId) (\(reasonCode))")
        }

        if emitSystemMessage && decision != .run {
            addSystemMessage("automation 外部触发未执行：\(ctx.projectName()) -> \(triggerId) (\(reasonCode))")
        }

        return SupervisorAutomationExternalTriggerResult(
            projectId: projectId,
            triggerId: triggerId,
            triggerType: ingress.triggerType,
            decision: decision,
            reasonCode: reasonCode,
            runId: runId,
            auditRef: auditRef
        )
    }

    private func ingestAutomationExternalTrigger(
        _ ingress: SupervisorAutomationExternalTriggerIngress,
        for project: AXProjectEntry,
        ctx: AXProjectContext,
        auditRef: String,
        emitSystemMessage: Bool
    ) -> SupervisorAutomationExternalTriggerResult {
        let projectId = project.projectId.trimmingCharacters(in: .whitespacesAndNewlines)
        let triggerId = ingress.triggerId.trimmingCharacters(in: .whitespacesAndNewlines)
        let dedupeKey = ingress.dedupeKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let now = ingress.receivedAt

        func finalize(
            _ decision: SupervisorAutomationExternalTriggerDecision,
            reasonCode: String,
            runId: String? = nil
        ) -> SupervisorAutomationExternalTriggerResult {
            return recordAutomationExternalTriggerDecision(
                ingress: ingress,
                decision: decision,
                reasonCode: reasonCode,
                runId: runId,
                auditRef: auditRef,
                ctx: ctx,
                emitSystemMessage: emitSystemMessage
            )
        }

        primeAutomationExternalTriggerHistoryIfNeeded(projectId: projectId, ctx: ctx)

        guard !triggerId.isEmpty else {
            return finalize(.failClosed, reasonCode: "trigger_id_missing")
        }
        guard !dedupeKey.isEmpty || ingress.triggerType == .manual else {
            return finalize(.failClosed, reasonCode: "external_trigger_dedupe_key_missing")
        }
        if !dedupeKey.isEmpty,
           automationExternalTriggerReplaySeen(projectId: projectId, dedupeKey: dedupeKey, ctx: ctx) {
            return finalize(.drop, reasonCode: "external_trigger_replay_detected")
        }
        if automationProjectHasBlockingRun(ctx) {
            return finalize(.hold, reasonCode: "automation_active_run_present")
        }

        let cooldownWindowSec = automationTriggerCooldownWindowSeconds(
            triggerId: triggerId,
            triggerType: ingress.triggerType
        )
        if let lastAcceptedAt = automationExternalTriggerLastAcceptedAt(
            projectId: projectId,
            triggerId: triggerId,
            ctx: ctx
        ),
           now.timeIntervalSince1970 - lastAcceptedAt < Double(cooldownWindowSec) {
            return finalize(.drop, reasonCode: "trigger_cooldown_active")
        }

        do {
            let request = try makeExternalTriggerAutomationRunRequest(
                ctx: ctx,
                ingress: ingress
            )
            let prepared = try startAutomationRun(
                for: ctx,
                request: request,
                emitSystemMessage: emitSystemMessage
            )
            return finalize(.run, reasonCode: "trigger_route_allowed", runId: prepared.launchRef)
        } catch {
            return finalize(
                .failClosed,
                reasonCode: automationExternalTriggerReasonCode(from: error)
            )
        }
    }

    private func automationTriggerIds(
        from triggerRefs: [String],
        matching triggerType: XTAutomationTriggerType? = nil
    ) -> [String] {
        var seen: Set<String> = []
        var ordered: [String] = []
        for ref in triggerRefs {
            let trimmed = ref.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let triggerId: String = {
                guard let separator = trimmed.lastIndex(of: ":") else { return trimmed }
                let suffix = trimmed[trimmed.index(after: separator)...]
                return String(suffix).trimmingCharacters(in: .whitespacesAndNewlines)
            }()
            guard !triggerId.isEmpty else { continue }
            if let triggerType {
                let prefix = "\(triggerType.rawValue)/"
                if triggerId != triggerType.rawValue && !triggerId.hasPrefix(prefix) {
                    continue
                }
            }
            if seen.insert(triggerId).inserted {
                ordered.append(triggerId)
            }
        }
        return ordered
    }

    private func makeExternalTriggerAutomationRunRequest(
        ctx: AXProjectContext,
        ingress: SupervisorAutomationExternalTriggerIngress
    ) throws -> XTAutomationRunRequest {
        let config = try AXProjectStore.loadOrCreateConfig(for: ctx)
        guard let recipe = config.activeAutomationRecipe else {
            throw XTAutomationRunCoordinatorError.activeRecipeMissing
        }
        let trustedAutomationStatus = config.trustedAutomationStatus(
            forProjectRoot: ctx.root,
            permissionReadiness: AXTrustedAutomationPermissionOwnerReadiness.current(),
            requiredDeviceToolGroups: recipe.requiredDeviceToolGroups
        )

        let triggerId = ingress.triggerId.trimmingCharacters(in: .whitespacesAndNewlines)
        let requiresGrant = ingress.requiresGrant ?? !recipe.grantPolicyRef.isEmpty
        let preferredPolicyRef = ingress.policyRef?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let policyRef = requiresGrant
            ? (preferredPolicyRef.isEmpty ? recipe.grantPolicyRef : preferredPolicyRef)
            : ""
        let triggerToken = xtAutomationActionToken(triggerId, fallback: ingress.triggerType.rawValue)
        let triggerClass = xtAutomationActionToken(ingress.triggerType.rawValue, fallback: "trigger")

        return XTAutomationRunRequest(
            triggerSeeds: [
                XTAutomationTriggerSeed(
                    triggerID: triggerId,
                    triggerType: ingress.triggerType,
                    source: ingress.source,
                    payloadRef: ingress.payloadRef,
                    requiresGrant: requiresGrant,
                    policyRef: policyRef,
                    dedupeKey: ingress.dedupeKey
                )
            ],
            trustedAutomationReady: trustedAutomationStatus.trustedAutomationReady,
            permissionOwnerReady: trustedAutomationStatus.permissionOwnerReady,
            currentOwner: trustedAutomationStatus.permissionOwnerReady ? "XT-TRUSTED" : "XT-L2",
            blockedTaskID: "XT-AUTO-TRIGGER-\(triggerClass.uppercased())",
            operatorConsoleEvidenceRef: "build/reports/xt_auto_\(triggerClass)_trigger_operator_console.v1.json",
            latestDeltaRef: "build/reports/xt_auto_\(triggerClass)_trigger_delta.v1.json",
            deliveryRef: "build/reports/xt_auto_\(triggerClass)_trigger_delivery.v1.json",
            additionalEvidenceRefs: [
                "trigger://\(ingress.ingressChannel)/\(triggerClass)/\(triggerToken)",
                "payload://\(ingress.payloadRef)",
                "dedupe://\(ingress.dedupeKey)"
            ] + trustedAutomationStatus.missingPrerequisites.map {
                "trusted_automation_issue://\($0)"
            },
            now: ingress.receivedAt
        )
    }

    private func automationScheduleMinimumInterval(for triggerId: String) -> Int {
        let lowered = triggerId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if lowered.contains("weekly") {
            return 7 * 24 * 60 * 60
        }
        if lowered.contains("nightly") || lowered.contains("daily") {
            return 24 * 60 * 60
        }
        if lowered.contains("hourly") {
            return 60 * 60
        }
        if lowered.contains("minutely") {
            return 60
        }
        return max(automationDefaultTriggerCooldownSeconds(for: .schedule), 300)
    }

    private func automationTriggerCooldownWindowSeconds(
        triggerId: String,
        triggerType: XTAutomationTriggerType
    ) -> Int {
        switch triggerType {
        case .schedule:
            return max(automationDefaultTriggerCooldownSeconds(for: .schedule), automationScheduleMinimumInterval(for: triggerId))
        case .webhook, .connectorEvent, .manual:
            return automationDefaultTriggerCooldownSeconds(for: triggerType)
        }
    }

    private func automationDefaultTriggerCooldownSeconds(
        for triggerType: XTAutomationTriggerType
    ) -> Int {
        switch triggerType {
        case .schedule:
            return 300
        case .webhook:
            return 30
        case .connectorEvent:
            return 45
        case .manual:
            return 0
        }
    }

    private func automationExternalTriggerAuditRef(
        projectId: String,
        triggerId: String,
        now: Date
    ) -> String {
        let projectToken = xtAutomationActionToken(projectId, fallback: "project")
        let triggerToken = xtAutomationActionToken(triggerId, fallback: "trigger")
        return "audit-xt-auto-trigger-\(projectToken)-\(triggerToken)-\(Int(now.timeIntervalSince1970))"
    }

    private func automationExternalTriggerDeterministicDigest(stable: String) -> String {
        let digest = SHA256.hash(data: Data(stable.utf8))
        return "sha256:" + digest.map { String(format: "%02x", $0) }.joined()
    }

    private func automationExternalTriggerReplayLedgerKey(projectId: String, dedupeKey: String) -> String {
        "\(projectId)|\(dedupeKey)"
    }

    private func automationExternalTriggerAcceptedLedgerKey(projectId: String, triggerId: String) -> String {
        "\(projectId)|\(triggerId)"
    }

    private func primeAutomationExternalTriggerHistoryIfNeeded(projectId: String, ctx: AXProjectContext) {
        let normalizedProjectId = projectId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedProjectId.isEmpty else { return }
        guard automationExternalTriggerHistoryLoadedProjects.contains(normalizedProjectId) == false else { return }

        for row in automationRawLogEntries(for: ctx) {
            guard (row["type"] as? String) == "automation_external_trigger_route" else { continue }
            let decisionRaw = (row["decision"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if decisionRaw == SupervisorAutomationExternalTriggerDecision.hold.rawValue {
                continue
            }
            let createdAt = row["created_at"] as? Double ?? 0
            let triggerId = (row["trigger_id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let dedupeKey = (row["dedupe_key"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !dedupeKey.isEmpty {
                let key = automationExternalTriggerReplayLedgerKey(projectId: normalizedProjectId, dedupeKey: dedupeKey)
                automationExternalTriggerReplayLedger[key] = max(createdAt, automationExternalTriggerReplayLedger[key] ?? 0)
            }
            if decisionRaw == SupervisorAutomationExternalTriggerDecision.run.rawValue, !triggerId.isEmpty {
                let key = automationExternalTriggerAcceptedLedgerKey(projectId: normalizedProjectId, triggerId: triggerId)
                automationExternalTriggerAcceptedLedger[key] = max(createdAt, automationExternalTriggerAcceptedLedger[key] ?? 0)
            }
        }

        automationExternalTriggerHistoryLoadedProjects.insert(normalizedProjectId)
    }

    private func automationExternalTriggerReplaySeen(
        projectId: String,
        dedupeKey: String,
        ctx: AXProjectContext
    ) -> Bool {
        primeAutomationExternalTriggerHistoryIfNeeded(projectId: projectId, ctx: ctx)
        let key = automationExternalTriggerReplayLedgerKey(projectId: projectId, dedupeKey: dedupeKey)
        return automationExternalTriggerReplayLedger[key] != nil
    }

    private func automationExternalTriggerLastAcceptedAt(
        projectId: String,
        triggerId: String,
        ctx: AXProjectContext
    ) -> TimeInterval? {
        primeAutomationExternalTriggerHistoryIfNeeded(projectId: projectId, ctx: ctx)
        let key = automationExternalTriggerAcceptedLedgerKey(projectId: projectId, triggerId: triggerId)
        return automationExternalTriggerAcceptedLedger[key]
    }

    private func appendAutomationExternalTriggerRouteLog(
        ingress: SupervisorAutomationExternalTriggerIngress,
        decision: SupervisorAutomationExternalTriggerDecision,
        reasonCode: String,
        runId: String?,
        auditRef: String,
        ctx: AXProjectContext
    ) {
        AXProjectStore.appendRawLog(
            [
                "type": "automation_external_trigger_route",
                "created_at": ingress.receivedAt.timeIntervalSince1970,
                "trigger_id": ingress.triggerId,
                "trigger_type": ingress.triggerType.rawValue,
                "source": ingress.source.rawValue,
                "ingress_channel": ingress.ingressChannel,
                "payload_ref": ingress.payloadRef,
                "dedupe_key": ingress.dedupeKey,
                "cooldown_sec": automationTriggerCooldownWindowSeconds(
                    triggerId: ingress.triggerId,
                    triggerType: ingress.triggerType
                ),
                "decision": decision.rawValue,
                "reason_code": reasonCode,
                "run_id": runId ?? NSNull(),
                "external_trigger_ingress_schema_version": XTAutomationExternalTriggerIngressEnvelope.currentSchemaVersion,
                "audit_ref": auditRef
            ],
            for: ctx
        )
    }

    private func automationExternalTriggerReasonCode(from error: Error) -> String {
        if let coordinatorError = error as? XTAutomationRunCoordinatorError {
            switch coordinatorError {
            case .activeRecipeMissing:
                return "active_recipe_missing"
            case .triggerSeedsMissing:
                return "trigger_seeds_missing"
            case .triggerIngressNotAllowed:
                return "trigger_ingress_not_allowed"
            case .triggerIngressReplayDetected:
                return "external_trigger_replay_detected"
            case .triggerIngressPolicyMissing:
                return "trigger_ingress_policy_missing"
            case .runNotFound:
                return "run_not_found"
            }
        }
        if let runtimeError = error as? SupervisorAutomationRuntimeError {
            switch runtimeError {
            case .projectSelectionMissing:
                return "project_selection_missing"
            case .projectNotFound:
                return "project_not_found"
            case .projectAmbiguous:
                return "project_ambiguous"
            case .projectContextMissing:
                return "project_context_missing"
            }
        }
        return "automation_external_trigger_failed_closed"
    }

    private func automationProjectHasBlockingRun(_ ctx: AXProjectContext) -> Bool {
        guard let runId = try? latestAutomationLaunchRef(for: ctx),
              let checkpoint = try? automationRunCoordinator.latestCheckpoint(for: runId, in: ctx) else {
            return false
        }

        switch checkpoint.state {
        case .queued, .running, .blocked, .takeover:
            return true
        case .delivered, .failed, .downgraded:
            return false
        }
    }

    private func automationRawLogEntries(for ctx: AXProjectContext) -> [[String: Any]] {
        guard FileManager.default.fileExists(atPath: ctx.rawLogURL.path),
              let data = try? Data(contentsOf: ctx.rawLogURL),
              let text = String(data: data, encoding: .utf8) else {
            return []
        }

        return text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { line in
                let rawLine = String(line)
                guard let lineData = rawLine.data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
                    return nil
                }
                return object
            }
    }

    private func makeManualAutomationRunRequest(
        for project: AXProjectEntry,
        ctx: AXProjectContext
    ) throws -> XTAutomationRunRequest {
        let config = try AXProjectStore.loadOrCreateConfig(for: ctx)
        guard let recipe = config.activeAutomationRecipe else {
            throw XTAutomationRunCoordinatorError.activeRecipeMissing
        }
        let trustedAutomationStatus = config.trustedAutomationStatus(
            forProjectRoot: ctx.root,
            permissionReadiness: AXTrustedAutomationPermissionOwnerReadiness.current(),
            requiredDeviceToolGroups: recipe.requiredDeviceToolGroups
        )

        let now = Date()
        let timestamp = Int(now.timeIntervalSince1970)
        let projectToken = normalizedLookupKey(project.displayName).isEmpty
            ? normalizedLookupKey(project.projectId)
            : normalizedLookupKey(project.displayName)
        let triggerID = recipe.triggerRefs.first?
            .split(separator: ":")
            .last
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "manual/supervisor"
        let requiresGrant = !recipe.grantPolicyRef.isEmpty
        let policyRef = requiresGrant ? recipe.grantPolicyRef : ""

        return XTAutomationRunRequest(
            triggerSeeds: [
                XTAutomationTriggerSeed(
                    triggerID: triggerID.isEmpty ? "manual/supervisor" : triggerID,
                    triggerType: .manual,
                    source: .hub,
                    payloadRef: "local://supervisor/manual-start/\(projectToken)/\(timestamp)",
                    requiresGrant: requiresGrant,
                    policyRef: policyRef,
                    dedupeKey: "manual|\(project.projectId)|\(timestamp)"
                )
            ],
            trustedAutomationReady: trustedAutomationStatus.trustedAutomationReady,
            permissionOwnerReady: trustedAutomationStatus.permissionOwnerReady,
            currentOwner: trustedAutomationStatus.permissionOwnerReady ? "XT-TRUSTED" : "XT-L2",
            blockedTaskID: "XT-AUTO-MANUAL-START",
            operatorConsoleEvidenceRef: "build/reports/xt_auto_manual_operator_console.v1.json",
            latestDeltaRef: "build/reports/xt_auto_manual_delta.v1.json",
            deliveryRef: "build/reports/xt_auto_manual_delivery.v1.json",
            additionalEvidenceRefs: [
                "manual://supervisor_command/start",
                "recipe://\(recipe.ref)",
                "trusted_automation://\(trustedAutomationStatus.state.rawValue)"
            ] + trustedAutomationStatus.missingPrerequisites.map {
                "trusted_automation_issue://\($0)"
            },
            now: now
        )
    }

    private func makeRetryAutomationRunRequest(
        for project: AXProjectEntry,
        ctx: AXProjectContext,
        retryPackage: XTAutomationRetryPackage,
        triggerMode: String
    ) throws -> XTAutomationRunRequest {
        let config = try AXProjectStore.loadOrCreateConfig(for: ctx)
        guard let recipe = config.activeAutomationRecipe else {
            throw XTAutomationRunCoordinatorError.activeRecipeMissing
        }
        let trustedAutomationStatus = config.trustedAutomationStatus(
            forProjectRoot: ctx.root,
            permissionReadiness: AXTrustedAutomationPermissionOwnerReadiness.current(),
            requiredDeviceToolGroups: recipe.requiredDeviceToolGroups
        )

        let now = Date()
        let timestamp = Int(now.timeIntervalSince1970)
        let projectToken = normalizedLookupKey(project.displayName).isEmpty
            ? normalizedLookupKey(project.projectId)
            : normalizedLookupKey(project.displayName)
        let requiresGrant = !recipe.grantPolicyRef.isEmpty
        let policyRef = requiresGrant ? recipe.grantPolicyRef : ""
        let sourceRunToken = xtAutomationActionToken(retryPackage.sourceRunID, fallback: "run")
        let normalizedTriggerMode = triggerMode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? automationManualRetryTrigger
            : triggerMode.trimmingCharacters(in: .whitespacesAndNewlines)
        let triggerID = normalizedTriggerMode == automationAutoRetryTrigger ? "auto/retry" : "manual/recover"
        let blockedTaskID = normalizedTriggerMode == automationAutoRetryTrigger ? "XT-AUTO-SELF-ITERATE" : "XT-AUTO-RECOVER"
        let operatorConsoleEvidenceRef = normalizedTriggerMode == automationAutoRetryTrigger
            ? "build/reports/xt_auto_self_iterate_operator_console.v1.json"
            : "build/reports/xt_auto_recover_operator_console.v1.json"
        let latestDeltaRef = normalizedTriggerMode == automationAutoRetryTrigger
            ? "build/reports/xt_auto_self_iterate_delta.v1.json"
            : "build/reports/xt_auto_recover_delta.v1.json"
        let deliveryRef = normalizedTriggerMode == automationAutoRetryTrigger
            ? "build/reports/xt_auto_self_iterate_delivery.v1.json"
            : "build/reports/xt_auto_recover_delivery.v1.json"
        let triggerEvidenceRef = normalizedTriggerMode == automationAutoRetryTrigger
            ? "automatic://self_iterate/retry"
            : "manual://supervisor_command/recover"
        let dedupePrefix = normalizedTriggerMode == automationAutoRetryTrigger ? "auto_recover" : "recover"
        let planningArtifact = xtAutomationResolvedRetryPlanningArtifact(
            from: retryPackage,
            ctx: ctx
        )
        let recipeProposalArtifact = xtAutomationResolvedRetryRecipeProposalArtifact(
            from: retryPackage,
            ctx: ctx
        )
        let runtimePatchOverlay = recipeProposalArtifact?.runtimePatchOverlay
            ?? retryPackage.runtimePatchOverlay
        let overlayOverrides = runtimePatchOverlay.map {
            xtAutomationApplyRuntimePatchOverlay(
                $0,
                baseRecipe: recipe,
                baseVerifyCommands: config.verifyCommands
            )
        }
        let retryLineage = automationRetryLineage(for: retryPackage)
        let recipeOverride = overlayOverrides?.recipeOverride
            ?? recipeProposalArtifact.flatMap { artifact in
            automationRetryRecipeOverride(
                recipeProposalArtifact: artifact,
                baseRecipe: recipe
            )
        } ?? planningArtifact.flatMap { artifact in
            automationRetryRecipeOverride(
                planningArtifact: artifact,
                baseRecipe: recipe
            )
        } ?? automationRetryRecipeOverride(
            from: retryPackage,
            baseRecipe: recipe
        )
        let verifyCommandsOverride: [String]? = {
            if let overlayCommands = overlayOverrides?.verifyCommandsOverride {
                return overlayCommands
            }
            if let proposalCommands = recipeProposalArtifact?.proposedVerifyCommands,
               !proposalCommands.isEmpty {
                return proposalCommands
            }
            if let planningCommands = planningArtifact?.proposedVerifyCommands,
               !planningCommands.isEmpty {
                return planningCommands
            }
            return retryPackage.revisedVerifyCommands
        }()

        return XTAutomationRunRequest(
            triggerSeeds: [
                XTAutomationTriggerSeed(
                    triggerID: triggerID,
                    triggerType: .manual,
                    source: .hub,
                    payloadRef: "local://supervisor/\(normalizedTriggerMode)/\(projectToken)/\(timestamp)/\(sourceRunToken)",
                    requiresGrant: requiresGrant,
                    policyRef: policyRef,
                    dedupeKey: "\(dedupePrefix)|\(project.projectId)|\(retryPackage.sourceRunID)|\(timestamp)"
                )
            ],
            lineage: retryLineage,
            trustedAutomationReady: trustedAutomationStatus.trustedAutomationReady,
            permissionOwnerReady: trustedAutomationStatus.permissionOwnerReady,
            currentOwner: trustedAutomationStatus.permissionOwnerReady ? "XT-TRUSTED" : "XT-L2",
            blockedTaskID: blockedTaskID,
            operatorConsoleEvidenceRef: operatorConsoleEvidenceRef,
            latestDeltaRef: latestDeltaRef,
            deliveryRef: deliveryRef,
            additionalEvidenceRefs: xtAutomationMergeEvidenceRefs(
                [
                    triggerEvidenceRef,
                    "recipe://\(recipe.ref)",
                    "trusted_automation://\(trustedAutomationStatus.state.rawValue)"
                ] + trustedAutomationStatus.missingPrerequisites.map {
                    "trusted_automation_issue://\($0)"
                },
                retryPackage.additionalEvidenceRefs
            ),
            recipeOverride: recipeOverride,
            verifyCommandsOverride: verifyCommandsOverride,
            now: now
        )
    }

    private func buildAutomationRetryPackage(
        for project: AXProjectEntry,
        ctx: AXProjectContext,
        sourceRunID: String,
        triggerMode: String
    ) -> AutomationRetryPlanningMaterialization? {
        let config = try? AXProjectStore.loadOrCreateConfig(for: ctx)
        guard let recipe = config?.activeAutomationRecipe,
              !recipe.actionGraph.isEmpty else {
            return nil
        }

        let reportedHandoffPath = automationLatestExecutionReport?.runID == sourceRunID
            ? automationLatestExecutionReport?.handoffArtifactPath
            : nil
        guard let handoff = xtAutomationLoadHandoffArtifact(
            for: sourceRunID,
            ctx: ctx,
            reportedRelativePath: reportedHandoffPath
        ) else {
            return nil
        }

        let strategy = automationRetryStrategy(for: handoff.artifact)
        let sourceHoldReason = handoff.artifact.holdReason.trimmingCharacters(in: .whitespacesAndNewlines)
        let verificationHoldReason = handoff.artifact.verificationReport?.holdReason
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let diffFileCount = handoff.artifact.workspaceDiffReport?.fileCount ?? 0
        let revision = automationRetryRevision(
            recipe: recipe,
            artifact: handoff.artifact
        )
        let previousRetryPackage = xtAutomationLoadRetryPackage(
            forRetryRunID: sourceRunID,
            projectID: project.projectId,
            ctx: ctx
        )
        let sourceLineage = xtAutomationResolvedLineage(
            previousRetryPackage?.lineage
                ?? handoff.artifact.lineage
                ?? (automationLatestExecutionReport?.runID == sourceRunID
                    ? automationLatestExecutionReport?.lineage
                    : nil),
            fallbackRunID: handoff.artifact.runID
        )
        let retryLineage = sourceLineage.retryChild(parentRunID: handoff.artifact.runID)
        let nextRetryDepth = retryLineage.retryDepth
        let additionalEvidenceRefs = xtAutomationMergeEvidenceRefs(
            [
                handoff.relativePath,
                "retry://source_run/\(handoff.artifact.runID)",
                "retry://source_state/\(handoff.artifact.finalState.rawValue)",
                "retry://strategy/\(strategy.strategy)",
                "retry://trigger/\(normalizedLookupKey(triggerMode))",
                "retry://depth/\(nextRetryDepth)"
            ],
            [
                sourceHoldReason.isEmpty ? "" : "retry://hold_reason/\(sourceHoldReason)",
                verificationHoldReason.isEmpty ? "" : "retry://verify_hold_reason/\(verificationHoldReason)",
                diffFileCount > 0 ? "retry://workspace_diff/\(diffFileCount)_files" : "",
                strategy.reason.isEmpty ? "" : "retry://reason/\(strategy.reason)"
            ] + revision.additionalEvidenceRefs + handoff.artifact.suggestedNextActions.prefix(4).map {
                "retry://suggested/\(xtAutomationActionToken($0, fallback: "step"))"
            }
        )
        let runtimePatchOverlay = xtAutomationRuntimePatchOverlay(
            revisedActionGraph: revision.revisedActionGraph,
            revisedVerifyCommands: revision.revisedVerifyCommands
        )

        let planningArtifact = XTAutomationRetryPlanningArtifact(
            schemaVersion: XTAutomationRetryPlanningArtifact.currentSchemaVersion,
            generatedAt: Date().timeIntervalSince1970,
            projectID: project.projectId,
            lineage: retryLineage,
            sourceRunID: handoff.artifact.runID,
            sourceHandoffArtifactPath: handoff.relativePath,
            baseRecipeRef: recipe.ref,
            retryStrategy: strategy.strategy,
            retryReason: strategy.reason,
            planningMode: revision.planningMode,
            planningSummary: revision.planningSummary,
            proposedActionGraph: revision.revisedActionGraph ?? [],
            proposedVerifyCommands: revision.revisedVerifyCommands ?? [],
            suggestedNextActions: handoff.artifact.suggestedNextActions,
            additionalEvidenceRefs: additionalEvidenceRefs
        )
        let planningArtifactPath = xtAutomationPersistRetryPlanningArtifact(planningArtifact, ctx: ctx) ?? ""
        let recipeProposalArtifact = XTAutomationRecipeProposalArtifact(
            schemaVersion: XTAutomationRecipeProposalArtifact.currentSchemaVersion,
            generatedAt: Date().timeIntervalSince1970,
            projectID: project.projectId,
            lineage: retryLineage,
            sourceRunID: handoff.artifact.runID,
            sourceHandoffArtifactPath: handoff.relativePath,
            sourcePlanningArtifactPath: planningArtifactPath.isEmpty ? nil : planningArtifactPath,
            baseRecipeRef: recipe.ref,
            retryStrategy: strategy.strategy,
            retryReason: strategy.reason,
            proposalMode: revision.planningMode,
            proposalSummary: revision.planningSummary,
            runtimePatchOverlay: runtimePatchOverlay,
            proposedActionGraph: revision.revisedActionGraph ?? [],
            proposedVerifyCommands: revision.revisedVerifyCommands ?? [],
            suggestedNextActions: handoff.artifact.suggestedNextActions,
            additionalEvidenceRefs: additionalEvidenceRefs
        )
        let recipeProposalArtifactPath = xtAutomationPersistRetryRecipeProposalArtifact(recipeProposalArtifact, ctx: ctx) ?? ""

        let package = XTAutomationRetryPackage(
            schemaVersion: XTAutomationRetryPackage.currentSchemaVersion,
            generatedAt: Date().timeIntervalSince1970,
            projectID: project.projectId,
            lineage: retryLineage,
            sourceRunID: handoff.artifact.runID,
            sourceFinalState: handoff.artifact.finalState,
            sourceHoldReason: sourceHoldReason,
            sourceHandoffArtifactPath: handoff.relativePath,
            retryStrategy: strategy.strategy,
            retryReason: strategy.reason,
            suggestedNextActions: handoff.artifact.suggestedNextActions,
            additionalEvidenceRefs: additionalEvidenceRefs,
            planningMode: revision.planningMode,
            planningSummary: revision.planningSummary,
            runtimePatchOverlay: runtimePatchOverlay,
            revisedActionGraph: revision.revisedActionGraph,
            revisedVerifyCommands: revision.revisedVerifyCommands,
            planningArtifactPath: planningArtifactPath.isEmpty ? nil : planningArtifactPath,
            recipeProposalArtifactPath: recipeProposalArtifactPath.isEmpty ? nil : recipeProposalArtifactPath,
            retryRunID: "",
            retryArtifactPath: ""
        )
        return AutomationRetryPlanningMaterialization(
            package: package,
            planningArtifact: planningArtifactPath.isEmpty ? nil : planningArtifact,
            recipeProposalArtifact: recipeProposalArtifactPath.isEmpty ? nil : recipeProposalArtifact
        )
    }

    private func scheduleAutomationRetryIfPossible(
        for project: AXProjectEntry,
        ctx: AXProjectContext,
        decision: XTAutomationRestartRecoveryDecision,
        auditRef: String
    ) -> XTAutomationRetryPackage? {
        guard decision.decision == .resume else { return nil }
        return launchAutomationRetryIfPossible(
            for: project,
            ctx: ctx,
            sourceRunID: decision.runID,
            triggerMode: automationManualRetryTrigger,
            auditRef: auditRef
        )
    }

    private func launchAutomationRetryIfPossible(
        for project: AXProjectEntry,
        ctx: AXProjectContext,
        sourceRunID: String,
        triggerMode: String,
        auditRef: String
    ) -> XTAutomationRetryPackage? {
        guard let materialization = buildAutomationRetryPackage(
            for: project,
            ctx: ctx,
            sourceRunID: sourceRunID,
            triggerMode: triggerMode
        ) else {
            return nil
        }
        let retryPackage = materialization.package

        do {
            let request = try makeRetryAutomationRunRequest(
                for: project,
                ctx: ctx,
                retryPackage: retryPackage,
                triggerMode: triggerMode
            )
            let prepared = try startAutomationRun(
                for: ctx,
                request: request,
                emitSystemMessage: false
            )
            var finalized = retryPackage
            finalized.retryRunID = prepared.launchRef
            finalized.lineage = prepared.lineage
            if let persisted = xtAutomationPersistRetryPackage(finalized, ctx: ctx) {
                finalized = persisted
            }
            automationLatestRetryPackage = finalized
            let retryLineage = automationRetryLineage(for: finalized)
            let scheduledRow: [String: Any] = [
                "type": "automation_retry",
                "status": "scheduled",
                "created_at": Date().timeIntervalSince1970,
                "source_run_id": finalized.sourceRunID,
                "retry_run_id": finalized.retryRunID,
                "lineage_id": retryLineage.lineageID,
                "root_run_id": retryLineage.rootRunID,
                "parent_run_id": retryLineage.parentRunID.isEmpty ? NSNull() : retryLineage.parentRunID,
                "retry_depth": retryLineage.retryDepth,
                "retry_strategy": finalized.retryStrategy,
                "retry_reason": finalized.retryReason,
                "source_handoff_artifact_path": finalized.sourceHandoffArtifactPath,
                "retry_artifact_path": finalized.retryArtifactPath.isEmpty ? NSNull() : finalized.retryArtifactPath,
                "planning_artifact_path": (finalized.planningArtifactPath?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
                    ? finalized.planningArtifactPath!
                    : NSNull(),
                "recipe_proposal_artifact_path": (finalized.recipeProposalArtifactPath?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
                    ? finalized.recipeProposalArtifactPath!
                    : NSNull(),
                "additional_evidence_refs": finalized.additionalEvidenceRefs,
                "retry_trigger": normalizedLookupKey(triggerMode),
                "audit_ref": auditRef
            ]
            AXProjectStore.appendRawLog(scheduledRow, for: ctx)
            appendRecentEvent("automation retry scheduled: \(ctx.projectName()) -> \(prepared.launchRef) from \(sourceRunID)")
            return finalized
        } catch {
            let retryLineage = automationRetryLineage(for: retryPackage)
            let failedRow: [String: Any] = [
                "type": "automation_retry",
                "status": "failed",
                "created_at": Date().timeIntervalSince1970,
                "source_run_id": retryPackage.sourceRunID,
                "lineage_id": retryLineage.lineageID,
                "root_run_id": retryLineage.rootRunID,
                "parent_run_id": retryLineage.parentRunID.isEmpty ? NSNull() : retryLineage.parentRunID,
                "retry_depth": retryLineage.retryDepth,
                "retry_strategy": retryPackage.retryStrategy,
                "retry_reason": retryPackage.retryReason,
                "source_handoff_artifact_path": retryPackage.sourceHandoffArtifactPath,
                "planning_artifact_path": (retryPackage.planningArtifactPath?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
                    ? retryPackage.planningArtifactPath!
                    : NSNull(),
                "recipe_proposal_artifact_path": (retryPackage.recipeProposalArtifactPath?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
                    ? retryPackage.recipeProposalArtifactPath!
                    : NSNull(),
                "retry_trigger": normalizedLookupKey(triggerMode),
                "detail": error.localizedDescription,
                "audit_ref": auditRef
            ]
            AXProjectStore.appendRawLog(failedRow, for: ctx)
            appendRecentEvent("automation retry scheduling failed: \(ctx.projectName()) -> \(error.localizedDescription)")
            return nil
        }
    }

    private func automationRetryStrategy(
        for artifact: XTAutomationRunHandoffArtifact
    ) -> (strategy: String, reason: String) {
        let verificationHoldReason = artifact.verificationReport?.holdReason
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let holdReason = artifact.holdReason.trimmingCharacters(in: .whitespacesAndNewlines)

        if verificationHoldReason.hasPrefix("automation_verify_") || holdReason.hasPrefix("automation_verify_") {
            return ("verify_failed_retry", verificationHoldReason.isEmpty ? holdReason : verificationHoldReason)
        }
        if holdReason == "automation_patch_check_failed" {
            return ("patch_check_retry", "automation_patch_check_failed")
        }
        if holdReason == "automation_action_failed" || holdReason == "automation_action_execution_error" {
            return ("action_failure_retry", holdReason)
        }
        if holdReason.isEmpty {
            return ("resume_retry", artifact.finalState.rawValue)
        }
        return ("resume_retry", holdReason)
    }

    private func automationRetryRevision(
        recipe: AXAutomationRecipeRuntimeBinding,
        artifact: XTAutomationRunHandoffArtifact
    ) -> AutomationRetryRevision {
        let verificationHoldReason = artifact.verificationReport?.holdReason
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let holdReason = artifact.holdReason.trimmingCharacters(in: .whitespacesAndNewlines)
        let failedActionIDs = Set(artifact.actionResults.filter { !$0.ok }.map(\.actionID))
        let firstFailedIndex = recipe.actionGraph.firstIndex { failedActionIDs.contains($0.actionID) }

        if verificationHoldReason.hasPrefix("automation_verify_") || holdReason.hasPrefix("automation_verify_") {
            let revisedActionGraph = automationVerifyOnlyRetryActionGraph(includeWorkspaceDiff: artifact.workspaceDiffReport?.attempted == true)
            let revisedVerifyCommands = automationRetryVerifyCommands(from: artifact.verificationReport)
            return AutomationRetryRevision(
                planningMode: "verify_only_retry",
                planningSummary: "skip successful mutation actions and rerun failing verification commands against current workspace",
                revisedActionGraph: revisedActionGraph,
                revisedVerifyCommands: revisedVerifyCommands,
                additionalEvidenceRefs: [
                    "retry://planning_mode/verify_only_retry",
                    "retry://planning_summary/skip_successful_mutations_and_rerun_verify",
                    "retry://revised_action_graph/\(revisedActionGraph.count)",
                    revisedVerifyCommands.isEmpty ? "" : "retry://revised_verify_commands/\(revisedVerifyCommands.count)"
                ]
            )
        }

        if let firstFailedIndex, firstFailedIndex > 0 {
            let failedActionID = recipe.actionGraph[firstFailedIndex].actionID
            let revisedActionGraph = Array(recipe.actionGraph[firstFailedIndex...])
            return AutomationRetryRevision(
                planningMode: "resume_from_failed_action",
                planningSummary: "skip \(firstFailedIndex) successful actions and resume from \(failedActionID)",
                revisedActionGraph: revisedActionGraph,
                revisedVerifyCommands: nil,
                additionalEvidenceRefs: [
                    "retry://planning_mode/resume_from_failed_action",
                    "retry://resume_from_action/\(failedActionID)",
                    "retry://revised_action_graph/\(revisedActionGraph.count)"
                ]
            )
        }

        let summary: String
        if holdReason == "automation_patch_check_failed" {
            summary = "patch precheck failed before a resumable suffix was found; replay same recipe with carried evidence"
        } else {
            summary = "no deterministic retry revision available; replay same recipe with carried evidence"
        }
        return AutomationRetryRevision(
            planningMode: "replay_same_recipe",
            planningSummary: summary,
            revisedActionGraph: nil,
            revisedVerifyCommands: nil,
            additionalEvidenceRefs: [
                "retry://planning_mode/replay_same_recipe"
            ]
        )
    }

    private func automationRetryVerifyCommands(
        from report: XTAutomationVerificationReport?
    ) -> [String] {
        guard let report else { return [] }
        let commands = report.commandResults
            .filter { !$0.ok }
            .map(\.command)
        return xtAutomationMergeEvidenceRefs(commands, [])
    }

    private func automationVerifyOnlyRetryActionGraph(includeWorkspaceDiff: Bool) -> [XTAutomationRecipeAction] {
        var actions: [XTAutomationRecipeAction] = [
            XTAutomationRecipeAction(
                actionID: "retry_verify_snapshot",
                title: "Retry Verify Snapshot",
                tool: .project_snapshot,
                args: [:],
                continueOnFailure: false,
                successBodyContains: "root=",
                requiresVerification: true
            )
        ]
        if includeWorkspaceDiff {
            actions.append(
                XTAutomationRecipeAction(
                    actionID: "retry_verify_workspace_diff",
                    title: "Retry Workspace Diff",
                    tool: .git_diff,
                    args: [:],
                    continueOnFailure: true,
                    successBodyContains: "",
                    requiresVerification: false
                )
            )
        }
        return actions
    }

    private func automationRetryRecipeOverride(
        from retryPackage: XTAutomationRetryPackage,
        baseRecipe: AXAutomationRecipeRuntimeBinding
    ) -> AXAutomationRecipeRuntimeBinding? {
        if let runtimePatchOverlay = retryPackage.runtimePatchOverlay,
           let patched = xtAutomationApplyRuntimePatchOverlay(
                runtimePatchOverlay,
                baseRecipe: baseRecipe,
                baseVerifyCommands: []
           ).recipeOverride {
            return patched
        }
        guard let revisedActionGraph = retryPackage.revisedActionGraph,
              !revisedActionGraph.isEmpty else {
            return nil
        }
        var revised = baseRecipe
        revised.actionGraph = revisedActionGraph
        return revised.normalized()
    }

    private func automationRetryRecipeOverride(
        planningArtifact: XTAutomationRetryPlanningArtifact,
        baseRecipe: AXAutomationRecipeRuntimeBinding
    ) -> AXAutomationRecipeRuntimeBinding? {
        guard !planningArtifact.proposedActionGraph.isEmpty else { return nil }
        var revised = baseRecipe
        revised.actionGraph = planningArtifact.proposedActionGraph
        return revised.normalized()
    }

    private func automationRetryRecipeOverride(
        recipeProposalArtifact: XTAutomationRecipeProposalArtifact,
        baseRecipe: AXAutomationRecipeRuntimeBinding
    ) -> AXAutomationRecipeRuntimeBinding? {
        if let runtimePatchOverlay = recipeProposalArtifact.runtimePatchOverlay,
           let patched = xtAutomationApplyRuntimePatchOverlay(
                runtimePatchOverlay,
                baseRecipe: baseRecipe,
                baseVerifyCommands: []
           ).recipeOverride {
            return patched
        }
        guard !recipeProposalArtifact.proposedActionGraph.isEmpty else { return nil }
        var revised = baseRecipe
        revised.actionGraph = recipeProposalArtifact.proposedActionGraph
        return revised.normalized()
    }

    private func xtAutomationResolvedRetryPlanningArtifact(
        from retryPackage: XTAutomationRetryPackage,
        ctx: AXProjectContext
    ) -> XTAutomationRetryPlanningArtifact? {
        if let artifact = xtAutomationLoadRetryPlanningArtifact(
            sourceRunID: retryPackage.sourceRunID,
            ctx: ctx,
            reportedRelativePath: retryPackage.planningArtifactPath
        )?.artifact {
            return artifact
        }

        guard let planningMode = retryPackage.planningMode,
              let planningSummary = retryPackage.planningSummary else {
            return nil
        }

        return XTAutomationRetryPlanningArtifact(
            schemaVersion: XTAutomationRetryPlanningArtifact.currentSchemaVersion,
            generatedAt: retryPackage.generatedAt,
            projectID: retryPackage.projectID,
            lineage: retryPackage.lineage,
            sourceRunID: retryPackage.sourceRunID,
            sourceHandoffArtifactPath: retryPackage.sourceHandoffArtifactPath,
            baseRecipeRef: "",
            retryStrategy: retryPackage.retryStrategy,
            retryReason: retryPackage.retryReason,
            planningMode: planningMode,
            planningSummary: planningSummary,
            runtimePatchOverlay: retryPackage.runtimePatchOverlay,
            proposedActionGraph: retryPackage.revisedActionGraph ?? [],
            proposedVerifyCommands: retryPackage.revisedVerifyCommands ?? [],
            suggestedNextActions: retryPackage.suggestedNextActions,
            additionalEvidenceRefs: retryPackage.additionalEvidenceRefs
        )
    }

    private func xtAutomationResolvedRetryRecipeProposalArtifact(
        from retryPackage: XTAutomationRetryPackage,
        ctx: AXProjectContext
    ) -> XTAutomationRecipeProposalArtifact? {
        if var artifact = xtAutomationLoadRetryRecipeProposalArtifact(
            sourceRunID: retryPackage.sourceRunID,
            ctx: ctx,
            reportedRelativePath: retryPackage.recipeProposalArtifactPath
        )?.artifact {
            if artifact.runtimePatchOverlay == nil {
                artifact.runtimePatchOverlay = xtAutomationRuntimePatchOverlay(
                    revisedActionGraph: artifact.proposedActionGraph,
                    revisedVerifyCommands: artifact.proposedVerifyCommands
                )
            }
            return artifact
        }

        let planningArtifact = xtAutomationResolvedRetryPlanningArtifact(
            from: retryPackage,
            ctx: ctx
        )
        let proposalMode = planningArtifact?.planningMode
            ?? retryPackage.planningMode?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        let proposalSummary = planningArtifact?.planningSummary
            ?? retryPackage.planningSummary?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let proposalMode,
              !proposalMode.isEmpty,
              let proposalSummary,
              !proposalSummary.isEmpty else {
            return nil
        }

        return XTAutomationRecipeProposalArtifact(
            schemaVersion: XTAutomationRecipeProposalArtifact.currentSchemaVersion,
            generatedAt: retryPackage.generatedAt,
            projectID: retryPackage.projectID,
            lineage: retryPackage.lineage,
            sourceRunID: retryPackage.sourceRunID,
            sourceHandoffArtifactPath: retryPackage.sourceHandoffArtifactPath,
            sourcePlanningArtifactPath: retryPackage.planningArtifactPath,
            baseRecipeRef: planningArtifact?.baseRecipeRef ?? "",
            retryStrategy: retryPackage.retryStrategy,
            retryReason: retryPackage.retryReason,
            proposalMode: proposalMode,
            proposalSummary: proposalSummary,
            runtimePatchOverlay: retryPackage.runtimePatchOverlay
                ?? xtAutomationRuntimePatchOverlay(
                    revisedActionGraph: planningArtifact?.proposedActionGraph ?? retryPackage.revisedActionGraph,
                    revisedVerifyCommands: planningArtifact?.proposedVerifyCommands ?? retryPackage.revisedVerifyCommands
                ),
            proposedActionGraph: planningArtifact?.proposedActionGraph ?? retryPackage.revisedActionGraph ?? [],
            proposedVerifyCommands: planningArtifact?.proposedVerifyCommands ?? retryPackage.revisedVerifyCommands ?? [],
            suggestedNextActions: retryPackage.suggestedNextActions,
            additionalEvidenceRefs: retryPackage.additionalEvidenceRefs
        )
    }

    private func scheduleAutomaticSelfIterationIfNeeded(
        prepared: XTAutomationPreparedRun,
        report: XTAutomationRunExecutionReport,
        finalCheckpoint: XTAutomationRunCheckpoint,
        ctx: AXProjectContext,
        emitSystemMessage: Bool
    ) {
        guard report.finalState == .blocked,
              let config = try? AXProjectStore.loadOrCreateConfig(for: ctx),
              config.automationSelfIterateEnabled else {
            return
        }
        guard automationAutoRetryEligibleHoldReasons.contains(report.holdReason) else {
            logAutomationAutoRetrySkipped(
                sourceRunID: prepared.launchRef,
                holdReason: report.holdReason,
                reason: "hold_reason_not_auto_retryable",
                ctx: ctx,
                lineage: prepared.lineage
            )
            return
        }

        let project = automationProjectEntry(for: ctx)
        guard let materialization = buildAutomationRetryPackage(
            for: project,
            ctx: ctx,
            sourceRunID: prepared.launchRef,
            triggerMode: automationAutoRetryTrigger
        ) else {
            logAutomationAutoRetrySkipped(
                sourceRunID: prepared.launchRef,
                holdReason: report.holdReason,
                reason: "retry_package_unavailable",
                ctx: ctx,
                lineage: prepared.lineage
            )
            return
        }
        let retryPackage = materialization.package

        let retryDepth = automationRetryDepthValue(from: retryPackage)
        guard retryDepth <= config.automationMaxAutoRetryDepth else {
            logAutomationAutoRetrySkipped(
                sourceRunID: prepared.launchRef,
                holdReason: report.holdReason,
                reason: "auto_retry_budget_exhausted",
                ctx: ctx,
                retryDepth: retryDepth,
                lineage: prepared.lineage
            )
            automationStatusLine = automationStatusLine(
                runID: finalCheckpoint.runID,
                state: finalCheckpoint.state,
                detail: "auto_retry_budget_exhausted"
            )
            return
        }

        let autoRetryAuditRef = "audit-xt-auto-self-iterate-\(xtAutomationActionToken(prepared.launchRef, fallback: "run"))-\(Int(Date().timeIntervalSince1970))"
        automationAutoRetryTask?.cancel()
        automationStatusLine = automationStatusLine(
            runID: finalCheckpoint.runID,
            state: finalCheckpoint.state,
            detail: "auto_retry_scheduled:\(retryDepth)"
        )
        let retryLineage = automationRetryLineage(for: retryPackage)
        let pendingRow: [String: Any] = [
            "type": "automation_retry",
            "status": "pending",
            "created_at": Date().timeIntervalSince1970,
            "source_run_id": prepared.launchRef,
            "lineage_id": retryLineage.lineageID,
            "root_run_id": retryLineage.rootRunID,
            "parent_run_id": retryLineage.parentRunID.isEmpty ? NSNull() : retryLineage.parentRunID,
            "retry_depth": retryDepth,
            "retry_strategy": retryPackage.retryStrategy,
            "retry_reason": retryPackage.retryReason,
            "retry_trigger": automationAutoRetryTrigger,
            "source_handoff_artifact_path": retryPackage.sourceHandoffArtifactPath,
            "audit_ref": autoRetryAuditRef
        ]
        AXProjectStore.appendRawLog(pendingRow, for: ctx)
        appendRecentEvent("automation auto retry pending: \(ctx.projectName()) -> \(prepared.launchRef) depth \(retryDepth)")

        automationAutoRetryTask = Task { @MainActor [weak self] in
            defer { self?.automationAutoRetryTask = nil }
            guard let self else { return }
            guard !Task.isCancelled else { return }
            await Task.yield()
            guard !Task.isCancelled else { return }
            let launched = self.launchAutomationRetryIfPossible(
                for: project,
                ctx: ctx,
                sourceRunID: prepared.launchRef,
                triggerMode: self.automationAutoRetryTrigger,
                auditRef: autoRetryAuditRef
            )
            guard let launched else { return }
            self.automationStatusLine = self.automationStatusLine(
                runID: launched.retryRunID,
                state: .queued,
                detail: "auto_retry_started:\(retryDepth)"
            )
            if emitSystemMessage {
                self.addSystemMessage(
                    """
automation 自动迭代已继续
项目: \(ctx.projectName())
source_run_id: \(prepared.launchRef)
retry_run_id: \(launched.retryRunID)
retry_strategy: \(launched.retryStrategy)
retry_depth: \(retryDepth)
"""
                )
            }
        }
    }

    private func logAutomationAutoRetrySkipped(
        sourceRunID: String,
        holdReason: String,
        reason: String,
        ctx: AXProjectContext,
        retryDepth: Int? = nil,
        lineage: XTAutomationRunLineage? = nil
    ) {
        let resolvedLineage = lineage.map { xtAutomationResolvedLineage($0, fallbackRunID: sourceRunID) }
        let parentRunID = resolvedLineage?.parentRunID.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let suppressedRow: [String: Any] = [
            "type": "automation_retry",
            "status": "suppressed",
            "created_at": Date().timeIntervalSince1970,
            "source_run_id": sourceRunID,
            "lineage_id": resolvedLineage?.lineageID ?? NSNull(),
            "root_run_id": resolvedLineage?.rootRunID ?? NSNull(),
            "parent_run_id": parentRunID.isEmpty ? NSNull() : parentRunID,
            "retry_reason": holdReason,
            "retry_trigger": automationAutoRetryTrigger,
            "detail": reason,
            "retry_depth": retryDepth ?? resolvedLineage?.retryDepth ?? NSNull()
        ]
        AXProjectStore.appendRawLog(suppressedRow, for: ctx)
    }

    private func automationRetryDepthValue(from retryPackage: XTAutomationRetryPackage) -> Int {
        if let retryDepth = retryPackage.lineage?.retryDepth,
           retryDepth > 0 {
            return retryDepth
        }
        for ref in retryPackage.additionalEvidenceRefs where ref.hasPrefix("retry://depth/") {
            if let token = ref.split(separator: "/").last,
               let depth = Int(token) {
                return max(1, depth)
            }
        }
        return 1
    }

    private func automationRetryLineage(for retryPackage: XTAutomationRetryPackage) -> XTAutomationRunLineage {
        let fallbackRunID = retryPackage.retryRunID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? retryPackage.sourceRunID
            : retryPackage.retryRunID
        let lineage = xtAutomationResolvedLineage(retryPackage.lineage, fallbackRunID: fallbackRunID)
        let sourceRunID = retryPackage.sourceRunID.trimmingCharacters(in: .whitespacesAndNewlines)
        if sourceRunID.isEmpty {
            return lineage
        }
        if lineage.parentRunID == sourceRunID {
            return lineage
        }
        return lineage.retryChild(
            parentRunID: sourceRunID,
            retryDepth: automationRetryDepthValue(from: retryPackage)
        )
    }

    private func automationRetryTrigger(from retryPackage: XTAutomationRetryPackage?) -> String {
        guard let retryPackage else { return "" }
        for ref in retryPackage.additionalEvidenceRefs where ref.hasPrefix("retry://trigger/") {
            return String(ref.dropFirst("retry://trigger/".count))
        }
        return automationManualRetryTrigger
    }

    private func xtAutomationMergeEvidenceRefs(_ lhs: [String], _ rhs: [String]) -> [String] {
        var seen = Set<String>()
        var merged: [String] = []

        for value in lhs + rhs {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { continue }
            merged.append(trimmed)
        }

        return merged
    }

    private func automationProjectEntry(for ctx: AXProjectContext) -> AXProjectEntry {
        AXProjectEntry(
            projectId: AXProjectRegistryStore.projectId(forRoot: ctx.root),
            rootPath: ctx.root.path,
            displayName: ctx.projectName(),
            lastOpenedAt: Date().timeIntervalSince1970,
            manualOrderIndex: nil,
            pinned: false,
            statusDigest: nil,
            currentStateSummary: nil,
            nextStepSummary: nil,
            blockerSummary: nil,
            lastSummaryAt: nil,
            lastEventAt: nil
        )
    }

    private func latestAutomationLaunchRef(for ctx: AXProjectContext) throws -> String {
        let config = try AXProjectStore.loadOrCreateConfig(for: ctx)
        let runID = config.lastAutomationLaunchRef.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !runID.isEmpty else {
            throw XTAutomationRunCoordinatorError.runNotFound("last_launch")
        }
        return runID
    }

    private func automationRuntimeAuditRef(action: String, project: AXProjectEntry) -> String {
        let actionToken = normalizedLookupKey(action)
        let projectToken = normalizedLookupKey(project.projectId)
        return "audit-xt-auto-\(actionToken)-\(projectToken)-\(Int(Date().timeIntervalSince1970))"
    }

    private func updateAutomationSelfIterateConfig(
        for project: AXProjectEntry,
        ctx: AXProjectContext,
        enabled: Bool? = nil,
        maxAutoRetryDepth: Int? = nil
    ) throws -> AXProjectConfig {
        let config = try AXProjectStore.loadOrCreateConfig(for: ctx)
        let updated = config.settingAutomationSelfIteration(
            enabled: enabled,
            maxAutoRetryDepth: maxAutoRetryDepth
        )
        try AXProjectStore.saveConfig(updated, for: ctx)
        if appModel?.selectedProjectId == project.projectId {
            appModel?.projectConfig = updated
        }
        return updated
    }

    private func renderAutomationRuntimeStatus(
        for project: AXProjectEntry,
        ctx: AXProjectContext
    ) throws -> String {
        let config = try AXProjectStore.loadOrCreateConfig(for: ctx)
        let activeRecipeRef = config.activeAutomationRecipeRef.trimmingCharacters(in: .whitespacesAndNewlines)
        let lastLaunchRef = config.lastAutomationLaunchRef.trimmingCharacters(in: .whitespacesAndNewlines)
        hydrateAutomationRuntimeSnapshot(
            for: project,
            ctx: ctx,
            lastLaunchRef: lastLaunchRef
        )
        let activeRecipe = config.activeAutomationRecipe
        let permissionReadiness = AXTrustedAutomationPermissionOwnerReadiness.current()
        let trustedAutomationStatus = config.trustedAutomationStatus(
            forProjectRoot: ctx.root,
            permissionReadiness: permissionReadiness,
            requiredDeviceToolGroups: activeRecipe?.requiredDeviceToolGroups ?? []
        )
        let trustedRequiredPermissions = AXTrustedAutomationPermissionOwnerReadiness.requiredPermissionKeys(
            forDeviceToolGroups: trustedAutomationStatus.deviceToolGroups
        )
        let trustedRepairActions = permissionReadiness.suggestedOpenSettingsActions(
            forDeviceToolGroups: trustedAutomationStatus.deviceToolGroups
        )

        var lines: [String] = []
        lines.append("🤖 Automation Runtime 状态")
        lines.append("项目: \(project.displayName) (\(project.projectId))")
        lines.append("recipe: \(activeRecipeRef.isEmpty ? "(未激活)" : activeRecipeRef)")
        lines.append("trusted_automation: \(trustedAutomationStatus.state.rawValue)")
        if !trustedRequiredPermissions.isEmpty {
            lines.append("trusted_required_permissions: \(trustedRequiredPermissions.joined(separator: ","))")
        }
        if let activeRecipe {
            lines.append("goal: \(activeRecipe.goal.isEmpty ? "(未填写)" : activeRecipe.goal)")
            if !activeRecipe.requiredToolGroups.isEmpty {
                lines.append("required_tool_groups: \(activeRecipe.requiredToolGroups.joined(separator: ","))")
            }
            if !activeRecipe.requiredDeviceToolGroups.isEmpty {
                lines.append("required_device_tool_groups: \(activeRecipe.requiredDeviceToolGroups.joined(separator: ","))")
            }
        }
        lines.append("self_iterate_mode: \(config.automationSelfIterateEnabled ? "enabled" : "disabled")")
        lines.append("self_iterate_max_auto_retry_depth: \(config.automationMaxAutoRetryDepth)")
        if !trustedAutomationStatus.armedDeviceToolGroups.isEmpty {
            lines.append("trusted_armed_device_tool_groups: \(trustedAutomationStatus.armedDeviceToolGroups.joined(separator: ","))")
        }
        lines.append("last_launch: \(lastLaunchRef.isEmpty ? "(none)" : lastLaunchRef)")
        if let report = automationLatestExecutionReport,
           report.runID == lastLaunchRef {
            lines.append("last_execution_state: \(report.finalState.rawValue)")
            lines.append("last_execution_actions: \(report.executedActionCount)/\(report.totalActionCount)")
            if let lineage = report.lineage {
                lines.append("last_execution_lineage: \(lineage.lineageID)")
                lines.append("last_execution_root_run: \(lineage.rootRunID)")
                if !lineage.parentRunID.isEmpty {
                    lines.append("last_execution_parent_run: \(lineage.parentRunID)")
                }
                lines.append("last_execution_retry_depth: \(lineage.retryDepth)")
            }
            if let handoffPath = report.handoffArtifactPath,
               !handoffPath.isEmpty {
                lines.append("last_execution_handoff: \(handoffPath)")
            }
            if let diff = report.workspaceDiffReport,
               diff.attempted {
                lines.append("last_execution_diff: \(diff.fileCount) files / \(diff.diffChars) chars")
                lines.append("last_execution_diff_detail: \(diff.detail)")
            }
            if let verification = report.verificationReport,
               verification.required {
                lines.append("last_execution_verify: \(verification.passedCommandCount)/\(verification.commandCount)")
                if !verification.holdReason.isEmpty {
                    lines.append("last_execution_verify_hold_reason: \(verification.holdReason)")
                }
                lines.append("last_execution_verify_detail: \(verification.detail)")
            }
            if !report.holdReason.isEmpty {
                lines.append("last_execution_hold_reason: \(report.holdReason)")
            }
            lines.append("last_execution_detail: \(report.detail)")
        }
        if let retryPackage = automationLatestRetryPackage,
           retryPackage.projectID == project.projectId {
            lines.append("retry_attempt_from_run: \(retryPackage.sourceRunID)")
            lines.append("retry_strategy: \(retryPackage.retryStrategy)")
            lines.append("retry_trigger: \(automationRetryTrigger(from: retryPackage))")
            if let lineage = retryPackage.lineage {
                lines.append("retry_lineage: \(lineage.lineageID)")
                lines.append("retry_root_run: \(lineage.rootRunID)")
                if !lineage.parentRunID.isEmpty {
                    lines.append("retry_parent_run: \(lineage.parentRunID)")
                }
                lines.append("retry_depth: \(lineage.retryDepth)")
            }
            if let planningMode = retryPackage.planningMode,
               !planningMode.isEmpty {
                lines.append("retry_planning_mode: \(planningMode)")
            }
            if let planningSummary = retryPackage.planningSummary,
               !planningSummary.isEmpty {
                lines.append("retry_planning_summary: \(planningSummary)")
            }
            if let revisedActionGraph = retryPackage.revisedActionGraph,
               !revisedActionGraph.isEmpty {
                lines.append("retry_revised_action_graph_count: \(revisedActionGraph.count)")
            }
            if let revisedVerifyCommands = retryPackage.revisedVerifyCommands,
               !revisedVerifyCommands.isEmpty {
                lines.append("retry_revised_verify_commands: \(revisedVerifyCommands.joined(separator: " || "))")
            }
            let runtimePatchOverlayKeys = xtAutomationRuntimePatchOverlayKeys(retryPackage.runtimePatchOverlay)
            if !runtimePatchOverlayKeys.isEmpty {
                lines.append("retry_runtime_patch_overlay_keys: \(runtimePatchOverlayKeys.joined(separator: ","))")
            }
            if let recipeProposalArtifactPath = retryPackage.recipeProposalArtifactPath?.trimmingCharacters(in: .whitespacesAndNewlines),
               !recipeProposalArtifactPath.isEmpty {
                lines.append("retry_recipe_proposal_artifact: \(recipeProposalArtifactPath)")
            }
            if let planningArtifactPath = retryPackage.planningArtifactPath?.trimmingCharacters(in: .whitespacesAndNewlines),
               !planningArtifactPath.isEmpty {
                lines.append("retry_planning_artifact: \(planningArtifactPath)")
            }
            lines.append("last_retry_source_handoff: \(retryPackage.sourceHandoffArtifactPath)")
            if !retryPackage.retryRunID.isEmpty {
                lines.append("retry_run_id: \(retryPackage.retryRunID)")
            }
        }
        if !trustedAutomationStatus.missingPrerequisites.isEmpty {
            lines.append("trusted_missing: \(trustedAutomationStatus.missingPrerequisites.joined(separator: ","))")
        }
        if !trustedAutomationStatus.missingRequiredDeviceToolGroups.isEmpty {
            lines.append("trusted_missing_required_device_groups: \(trustedAutomationStatus.missingRequiredDeviceToolGroups.joined(separator: ","))")
        }
        if !trustedRepairActions.isEmpty {
            lines.append("trusted_repair_actions: \(trustedRepairActions.joined(separator: ","))")
        }

        if !lastLaunchRef.isEmpty,
           let checkpoint = try? automationRunCoordinator.latestCheckpoint(for: lastLaunchRef, in: ctx) {
            lines.append("state: \(checkpoint.state.rawValue)")
            lines.append("attempt: \(checkpoint.attempt)")
            lines.append("last_transition: \(checkpoint.lastTransition)")
            lines.append("retry_after_seconds: \(checkpoint.retryAfterSeconds)")
            lines.append("checkpoint_ref: \(checkpoint.checkpointRef)")
            if automationCurrentCheckpoint?.runID == checkpoint.runID,
               let decision = automationRecoveryDecision {
                let holdReason = decision.holdReason.isEmpty ? "none" : decision.holdReason
                lines.append("recovery: \(decision.decision.rawValue) (\(holdReason))")
            }
        } else {
            lines.append("state: idle")
        }

        lines.append("manager_status: \(automationStatusLine)")
        return lines.joined(separator: "\n")
    }

    private func hydrateAutomationRuntimeSnapshot(
        for project: AXProjectEntry,
        ctx: AXProjectContext,
        lastLaunchRef: String
    ) {
        automationPreparedRun = nil
        automationRecoveryDecision = nil
        let normalizedLastLaunchRef = lastLaunchRef.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedLastLaunchRef.isEmpty else {
            clearAutomationRuntimeSnapshotForSelection()
            return
        }

        if let persistedCheckpoint = try? automationRunCoordinator.latestCheckpoint(for: normalizedLastLaunchRef, in: ctx) {
            automationCurrentCheckpoint = persistedCheckpoint
            automationStatusLine = automationStatusLine(
                runID: persistedCheckpoint.runID,
                state: persistedCheckpoint.state,
                detail: persistedCheckpoint.lastTransition
            )
        }
        if let persistedExecution = xtAutomationLoadExecutionReport(for: normalizedLastLaunchRef, ctx: ctx) {
            automationLatestExecutionReport = persistedExecution
            automationStatusLine = automationStatusLine(
                runID: persistedExecution.runID,
                state: persistedExecution.finalState,
                detail: persistedExecution.detail
            )
        }
        if let persistedRetry = xtAutomationLoadRetryPackage(
            forRetryRunID: normalizedLastLaunchRef,
            projectID: project.projectId,
            ctx: ctx
        ) {
            automationLatestRetryPackage = persistedRetry
        } else {
            automationLatestRetryPackage = nil
        }
    }

    private func clearAutomationRuntimeSnapshotForSelection() {
        automationPreparedRun = nil
        automationCurrentCheckpoint = nil
        automationRecoveryDecision = nil
        automationLatestExecutionReport = nil
        automationLatestRetryPackage = nil
        automationStatusLine = "automation runtime: idle"
    }

    func syncAutomationRuntimeSnapshot(forSelectedProject project: AXProjectEntry?) {
        guard let project,
              let ctx = projectContext(from: project),
              let config = try? AXProjectStore.loadOrCreateConfig(for: ctx) else {
            clearAutomationRuntimeSnapshotForSelection()
            return
        }

        let lastLaunchRef = config.lastAutomationLaunchRef.trimmingCharacters(in: .whitespacesAndNewlines)
        hydrateAutomationRuntimeSnapshot(
            for: project,
            ctx: ctx,
            lastLaunchRef: lastLaunchRef
        )
    }

    private func renderAutomationStartSummary(
        project: AXProjectEntry,
        prepared: XTAutomationPreparedRun
    ) -> String {
        let launchDecision = prepared.verticalSlice.eventRunner.launchDecision.decision.rawValue
        return """
✅ automation 已启动准备
项目: \(project.displayName) (\(project.projectId))
recipe: \(prepared.recipeRef)
run_id: \(prepared.launchRef)
state: \(prepared.currentCheckpoint.state.rawValue)
launch_decision: \(launchDecision)
"""
    }

    private func renderAutomationRecoverySummary(
        project: AXProjectEntry,
        decision: XTAutomationRestartRecoveryDecision?,
        retryPackage: XTAutomationRetryPackage?
    ) -> String {
        guard let decision else {
            return """
ℹ️ automation 无可恢复运行
项目: \(project.displayName) (\(project.projectId))
"""
        }

        let holdReason = decision.holdReason.isEmpty ? "none" : decision.holdReason
        let retryLines: String = {
            guard let retryPackage,
                  retryPackage.projectID == project.projectId else {
                return ""
            }
            var lines: [String] = [
                "retry_attempt_from_run: \(retryPackage.sourceRunID)",
                "retry_strategy: \(retryPackage.retryStrategy)",
                "last_retry_source_handoff: \(retryPackage.sourceHandoffArtifactPath)"
            ]
            if let planningMode = retryPackage.planningMode,
               !planningMode.isEmpty {
                lines.append("retry_planning_mode: \(planningMode)")
            }
            if let planningSummary = retryPackage.planningSummary,
               !planningSummary.isEmpty {
                lines.append("retry_planning_summary: \(planningSummary)")
            }
            if let planningArtifactPath = retryPackage.planningArtifactPath?.trimmingCharacters(in: .whitespacesAndNewlines),
               !planningArtifactPath.isEmpty {
                lines.append("retry_planning_artifact: \(planningArtifactPath)")
            }
            let runtimePatchOverlayKeys = xtAutomationRuntimePatchOverlayKeys(retryPackage.runtimePatchOverlay)
            if !runtimePatchOverlayKeys.isEmpty {
                lines.append("retry_runtime_patch_overlay_keys: \(runtimePatchOverlayKeys.joined(separator: ","))")
            }
            if let recipeProposalArtifactPath = retryPackage.recipeProposalArtifactPath?.trimmingCharacters(in: .whitespacesAndNewlines),
               !recipeProposalArtifactPath.isEmpty {
                lines.append("retry_recipe_proposal_artifact: \(recipeProposalArtifactPath)")
            }
            if !retryPackage.retryRunID.isEmpty {
                lines.append("retry_run_id: \(retryPackage.retryRunID)")
            }
            return "\n" + lines.joined(separator: "\n")
        }()
        return """
♻️ automation 恢复判定
项目: \(project.displayName) (\(project.projectId))
run_id: \(decision.runID)
state: \(decision.recoveredState.rawValue)
decision: \(decision.decision.rawValue)
hold_reason: \(holdReason)
\(retryLines)
"""
    }

    private func renderAutomationCancelSummary(
        project: AXProjectEntry,
        decision: XTAutomationRestartRecoveryDecision
    ) -> String {
        let holdReason = decision.holdReason.isEmpty ? "none" : decision.holdReason
        return """
🛑 automation 已取消
项目: \(project.displayName) (\(project.projectId))
run_id: \(decision.runID)
decision: \(decision.decision.rawValue)
hold_reason: \(holdReason)
"""
    }

    private func renderAutomationAdvanceSummary(
        project: AXProjectEntry,
        checkpoint: XTAutomationRunCheckpoint
    ) -> String {
        return """
➡️ automation 状态已推进
项目: \(project.displayName) (\(project.projectId))
run_id: \(checkpoint.runID)
state: \(checkpoint.state.rawValue)
attempt: \(checkpoint.attempt)
last_transition: \(checkpoint.lastTransition)
"""
    }

    private func renderAutomationSelfIterateSummary(
        project: AXProjectEntry,
        config: AXProjectConfig,
        headline: String
    ) -> String {
        """
\(headline)
项目: \(project.displayName) (\(project.projectId))
self_iterate_mode: \(config.automationSelfIterateEnabled ? "enabled" : "disabled")
self_iterate_max_auto_retry_depth: \(config.automationMaxAutoRetryDepth)
behavior: bounded_auto_retry_only
proposal_mode: controlled_runtime_patch_overlay
"""
    }

    private func renderAutomationExecutionSummary(
        projectName: String,
        report: XTAutomationRunExecutionReport
    ) -> String {
        let holdReason = report.holdReason.isEmpty ? "none" : report.holdReason
        let diffText: String = {
            guard let diff = report.workspaceDiffReport,
                  diff.attempted else {
                return "diff: skipped"
            }
            return "diff: \(diff.fileCount) files / \(diff.diffChars) chars (\(diff.detail))"
        }()
        let handoffText: String = {
            let path = (report.handoffArtifactPath ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return path.isEmpty ? "handoff: skipped" : "handoff: \(path)"
        }()
        let verificationText: String = {
            guard let verification = report.verificationReport,
                  verification.required else {
                return "verify: skipped"
            }
            let verifyHoldReason = verification.holdReason.isEmpty ? "none" : verification.holdReason
            return "verify: \(verification.passedCommandCount)/\(verification.commandCount) (\(verifyHoldReason))"
        }()
        return """
⚙️ automation 自动执行完成
项目: \(projectName)
run_id: \(report.runID)
state: \(report.finalState.rawValue)
executed_actions: \(report.executedActionCount)/\(report.totalActionCount)
\(handoffText)
\(diffText)
\(verificationText)
hold_reason: \(holdReason)
detail: \(report.detail)
"""
    }

    private func renderAutomationRuntimeError(_ error: Error) -> String {
        if let runtimeError = error as? SupervisorAutomationRuntimeError {
            switch runtimeError {
            case .projectContextMissing(let projectID):
                return "❌ automation 失败：项目上下文不可用（project_id=\(projectID)）"
            case .projectSelectionMissing:
                let hints = allProjects().prefix(4).map { $0.displayName }.joined(separator: "、")
                let suffix = hints.isEmpty ? "" : "。可用项目：\(hints)"
                return "❌ automation 失败：未选择项目。请先在 UI 中选中项目，或在命令里显式传入 projectRef\(suffix)"
            case .projectNotFound(let projectRef):
                let hints = allProjects().prefix(4).map { $0.displayName }.joined(separator: "、")
                let suffix = hints.isEmpty ? "" : "。可用项目：\(hints)"
                return "❌ automation 失败：找不到项目 \(projectRef)\(suffix)"
            case .projectAmbiguous(let projectRef, let candidates):
                let suffix = candidates.isEmpty ? "" : "。候选：\(candidates.joined(separator: "、"))"
                return "⚠️ automation 失败：项目引用不唯一 \(projectRef)\(suffix)"
            }
        }

        if let coordinatorError = error as? XTAutomationRunCoordinatorError {
            switch coordinatorError {
            case .activeRecipeMissing:
                return "❌ automation 失败：当前项目没有激活的 automation recipe。请先把 recipe 配成 ready + active。"
            case .triggerSeedsMissing:
                return "❌ automation 失败：trigger seed 为空，无法创建 run。"
            case .triggerIngressNotAllowed(let triggerID):
                return "❌ automation 失败：外部触发 \(triggerID) 不在当前 recipe 的 allowlist 内，已 fail-closed。"
            case .triggerIngressReplayDetected(let token):
                return "❌ automation 失败：外部触发 dedupe/replay guard 命中（\(token)），已阻止重复 run。"
            case .triggerIngressPolicyMissing(let triggerID):
                return "❌ automation 失败：外部触发 \(triggerID) 缺少 grant/policy 绑定，已 fail-closed。"
            case .runNotFound(let runID):
                return "❌ automation 失败：找不到运行记录（run_id=\(runID)）。"
            }
        }

        return "❌ automation 失败：\(error.localizedDescription)"
    }

    private func shouldRunDoctorCommand(_ text: String) -> Bool {
        let token = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if token == "/doctor" || token == "doctor" || token == "supervisor doctor" {
            return true
        }
        if text.contains("doctor 预检") || text.contains("doctor体检") || text.contains("发布前体检") || text.contains("运行 doctor") {
            return true
        }
        return false
    }

    private func shouldRunSecretsDryRunCommand(_ text: String) -> Bool {
        let token = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if token == "/secrets dry-run" || token == "secrets dry-run" {
            return true
        }
        if token.contains("secrets") && token.contains("dry") {
            return true
        }
        if text.contains("secrets 预检") || text.contains("密钥预检") || text.contains("dry-run") {
            return true
        }
        return false
    }

    private func shouldExportXTReadyIncidentEventsCommand(_ text: String) -> Bool {
        let token = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if token == "/xt-ready incidents export" || token == "xt-ready incidents export" {
            return true
        }
        if token == "/xt-ready incidents" || token == "xt-ready incidents" {
            return true
        }
        if token.contains("xt-ready") && token.contains("incident") && token.contains("export") {
            return true
        }
        if text.contains("导出") && text.contains("incident") && text.contains("证据") {
            return true
        }
        return false
    }

    private func shouldShowXTReadyIncidentEventsStatusCommand(_ text: String) -> Bool {
        let token = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if token == "/xt-ready incidents status" || token == "xt-ready incidents status" {
            return true
        }
        if token == "/xt-ready status" || token == "xt-ready status" {
            return true
        }
        if token.contains("xt-ready") && token.contains("incident") && token.contains("status") {
            return true
        }
        if text.contains("incident") && text.contains("导出状态") {
            return true
        }
        return false
    }

    private func shouldInjectXTReadyIncidentsCommand(_ text: String) -> Bool {
        let token = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if token == "/xt-ready incidents inject" || token == "xt-ready incidents inject" {
            return true
        }
        if token.hasPrefix("/xt-ready incidents inject ") || token.hasPrefix("xt-ready incidents inject ") {
            return true
        }
        if token.contains("xt-ready") && token.contains("incident") && token.contains("inject") {
            return true
        }
        return false
    }

    private func injectXTReadyIncidents(using command: String) async -> String {
        guard let monitor = appModel?.supervisor.orchestrator?.monitor else {
            return "❌ 未找到执行监控器，请先确保 Supervisor 已启动。"
        }

        let cleared = supervisorIncidentLedger.count
        supervisorIncidentLedger.removeAll()
        xtReadyIncidentEventsAutoExportStatus = "reset_before_inject"

        let specs = parseXTReadyIncidentInjectSpecs(from: command)
        let snapshot = monitor.laneStates
        guard !snapshot.isEmpty else {
            return """
❌ 当前没有可注入的 lane（lane health 为空）。
请先完成提案 confirm 并启动多泳道执行，再运行本命令。
"""
        }

        var applied: [String] = []
        var skipped: [String] = []
        for spec in specs {
            guard let state = snapshot[spec.laneID] else {
                skipped.append("\(spec.laneID):lane_not_found")
                continue
            }
            if state.status.isTerminal {
                skipped.append("\(spec.laneID):lane_terminal")
                continue
            }

            switch spec.incidentCode {
            case LaneBlockedReason.grantPending.rawValue:
                await monitor.updateState(
                    state.taskId,
                    status: .blocked,
                    blockedReason: .grantPending,
                    note: "xt_ready_manual_inject_grant_pending"
                )
                applied.append("\(spec.laneID):grant_pending")
            case LaneBlockedReason.awaitingInstruction.rawValue:
                await monitor.updateState(
                    state.taskId,
                    status: .blocked,
                    blockedReason: .awaitingInstruction,
                    note: "xt_ready_manual_inject_awaiting_instruction"
                )
                applied.append("\(spec.laneID):awaiting_instruction")
            case LaneBlockedReason.runtimeError.rawValue:
                await monitor.updateState(
                    state.taskId,
                    status: .failed,
                    blockedReason: .runtimeError,
                    note: "xt_ready_manual_inject_runtime_error"
                )
                applied.append("\(spec.laneID):runtime_error")
            default:
                skipped.append("\(spec.laneID):unsupported_code=\(spec.incidentCode)")
            }
        }

        _ = exportXTReadyIncidentEventsReport()

        let appliedText = applied.isEmpty ? "（无）" : applied.joined(separator: " | ")
        let skippedText = skipped.isEmpty ? "（无）" : skipped.joined(separator: " | ")
        return """
🧪 XT-Ready incident 注入已执行
ledger_cleared：\(cleared)
applied：\(appliedText)
skipped：\(skippedText)
下一步：
1) /xt-ready incidents status
2) /xt-ready incidents export
"""
    }

    private func parseXTReadyIncidentInjectSpecs(from command: String) -> [XTReadyIncidentInjectSpec] {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = trimmed.lowercased()

        let prefixes = ["/xt-ready incidents inject", "xt-ready incidents inject"]
        var args = ""
        for prefix in prefixes {
            if lowered.hasPrefix(prefix) {
                args = String(trimmed.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }

        if args.isEmpty {
            return Self.xtReadyDefaultInjectSpecs
        }

        let separators = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",;"))
        let tokens = args
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var specs: [XTReadyIncidentInjectSpec] = []
        for token in tokens {
            let normalized = token.lowercased()
            if normalized == "default" {
                specs.append(contentsOf: Self.xtReadyDefaultInjectSpecs)
                continue
            }

            let pair = normalized.replacingOccurrences(of: "=", with: ":")
            let parts = pair.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }

            let laneID = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let code = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !laneID.isEmpty, !code.isEmpty else { continue }
            specs.append(XTReadyIncidentInjectSpec(laneID: laneID, incidentCode: code))
        }

        if specs.isEmpty {
            return Self.xtReadyDefaultInjectSpecs
        }
        return specs
    }

    private func renderDoctorSummary(_ report: SupervisorDoctorReport) -> String {
        var lines: [String] = []
        lines.append("🩺 Supervisor Doctor 预检结果")
        lines.append("状态：\(report.ok ? "通过" : "阻断")")
        lines.append("阻断项：\(report.summary.blockingCount) · 告警项：\(report.summary.warningCount)")
        lines.append("配置来源：\(report.configSource)")
        lines.append("Secrets 计划：\(report.secretsPlanSource)")
        lines.append("报告路径：\(doctorReportPath.isEmpty ? "(未落盘)" : doctorReportPath)")

        if report.findings.isEmpty {
            lines.append("未发现风险项。")
            return lines.joined(separator: "\n")
        }

        lines.append("")
        lines.append("优先级解释与可操作建议（Top 3）：")
        for (index, finding) in report.findings.prefix(3).enumerated() {
            lines.append("\(index + 1). [\(finding.priority.rawValue.uppercased())] \(finding.title)")
            lines.append("   解释：\(finding.priorityReason)")
            if let first = finding.actions.first {
                lines.append("   建议：\(first)")
            }
        }
        return lines.joined(separator: "\n")
    }

    private func renderSecretsDryRunSummary(_ report: SupervisorDoctorReport) -> String {
        let summary = report.summary
        var lines: [String] = []
        lines.append("🔐 Secrets dry-run 摘要")
        lines.append("目标路径越界：\(summary.secretsPathOutOfScopeCount)")
        lines.append("缺失变量：\(summary.secretsMissingVariableCount)")
        lines.append("权限边界错误：\(summary.secretsPermissionBoundaryCount)")
        lines.append("阻断项总数：\(summary.blockingCount)")

        let secretsFindings = report.findings.filter { $0.area == "secrets_dry_run" }
        if secretsFindings.isEmpty {
            lines.append("当前未发现 secrets dry-run 风险。")
        } else {
            lines.append("")
            lines.append("可执行修复卡片：")
            for finding in secretsFindings.prefix(3) {
                lines.append("- \(finding.title)：\(finding.actions.first ?? "按建议修复后重新 dry-run")")
            }
        }
        return lines.joined(separator: "\n")
    }

    private func renderXTReadyIncidentExportSummary(
        _ result: XTReadyIncidentEventsExportResult
    ) -> String {
        var lines: [String] = []
        lines.append("🧾 XT-Ready incident 事件导出")
        lines.append("状态：\(result.ok ? "成功" : "失败")")
        lines.append("导出条数：\(result.exportedEventCount)")
        lines.append("输出路径：\(result.outputPath)")
        if !result.missingIncidentCodes.isEmpty {
            lines.append("缺失必需 incident_code：\(result.missingIncidentCodes.joined(separator: ","))")
        }
        if result.reason != "ok" {
            lines.append("原因：\(result.reason)")
        }
        lines.append("下一步：node ./scripts/m3_generate_xt_ready_e2e_evidence.js --strict --events-json \(result.outputPath) --out-json ./build/xt_ready_e2e_evidence.runtime.json")
        return lines.joined(separator: "\n")
    }

    private func renderXTReadyIncidentEventsStatus() -> String {
        let snapshot = xtReadyIncidentExportSnapshot(limit: 120)

        var lines: [String] = []
        lines.append("📌 XT-Ready incident 导出状态")
        lines.append("auto_export：\(snapshot.autoExportEnabled ? "enabled" : "disabled")")
        lines.append("ledger incidents：\(snapshot.ledgerIncidentCount)")
        lines.append("exported required incidents：\(snapshot.requiredIncidentEventCount)")
        lines.append("status：\(snapshot.status)")
        lines.append("strict_e2e_ready：\(snapshot.strictE2EReady ? "yes" : "no")")
        lines.append("report_path：\(snapshot.reportPath)")
        if snapshot.missingIncidentCodes.isEmpty {
            lines.append("missing incident_code：none")
        } else {
            lines.append("missing incident_code：\(snapshot.missingIncidentCodes.joined(separator: ","))")
        }
        if snapshot.strictE2EIssues.isEmpty {
            lines.append("strict_e2e_issues：none")
        } else {
            lines.append("strict_e2e_issues：\(snapshot.strictE2EIssues.joined(separator: ","))")
        }
        return lines.joined(separator: "\n")
    }
}

struct SupervisorMessage: Identifiable, Equatable {
    var id: String
    var role: SupervisorRole
    var content: String
    var isVoice: Bool
    var timestamp: Double

    enum SupervisorRole: String, Equatable {
        case user
        case assistant
        case system
    }
}

struct SupervisorTask: Identifiable {
    var id: String
    var projectId: String
    var title: String
    var status: String
    var createdAt: Double
}

enum SupervisorAutomationRuntimeError: Error, Equatable {
    case projectContextMissing(String)
    case projectSelectionMissing
    case projectNotFound(String)
    case projectAmbiguous(String, [String])
}

extension SupervisorManager {
    @discardableResult
    func prepareOneShotControlPlane(submission: OneShotIntakeSubmission) async -> OneShotControlPlaneSnapshot {
        let normalization = oneShotIntakeCoordinator.normalize(submission)
        oneShotNormalizationIssues = normalization.issues
        oneShotIntakeRequest = normalization.request

        let buildResult = await oneShotTaskDecomposer.analyzeAndBuildSplitProposal(
            normalization.request.userGoal,
            rootProjectId: normalization.request.projectUUID,
            planVersion: 1
        )
        oneShotPreparedSplitBuildResult = buildResult
        let planning = oneShotAdaptivePoolPlanner.plan(
            request: normalization.request,
            buildResult: buildResult
        )
        oneShotAdaptivePoolPlan = planning.decision
        oneShotSeatGovernor = planning.seatGovernor
        oneShotPlannerExplain = planning.decision.decisionExplain

        _ = oneShotRunStateStore.bootstrap(
            request: normalization.request,
            planDecision: planning.decision,
            owner: .supervisor,
            evidenceRefs: OneShotControlPlaneSnapshot.defaultEvidenceRefs()
        )
        _ = oneShotRunStateStore.transition(
            to: .planning,
            owner: .supervisor,
            activePools: planning.decision.poolPlan.map(\ .poolID),
            activeLanes: planning.decision.poolPlan.flatMap(\ .laneIDs),
            topBlocker: "none",
            nextDirectedTarget: "Supervisor",
            userVisibleSummary: "adaptive pool planning completed",
            evidenceRefs: OneShotControlPlaneSnapshot.defaultEvidenceRefs(),
            auditRef: normalization.request.auditRef
        )

        var finalRunState: OneShotRunStateSnapshot
        if planning.decision.decision == .deny {
            finalRunState = oneShotRunStateStore.transition(
                to: .failedClosed,
                owner: .supervisor,
                activePools: planning.decision.poolPlan.map(\ .poolID),
                activeLanes: planning.decision.poolPlan.flatMap(\ .laneIDs),
                topBlocker: planning.decision.denyCode,
                nextDirectedTarget: "Supervisor",
                userVisibleSummary: "failed closed: \(planning.decision.denyCode)",
                evidenceRefs: OneShotControlPlaneSnapshot.defaultEvidenceRefs(),
                auditRef: normalization.request.auditRef
            )
        } else if !normalization.request.requiresHumanAuthorizationTypes.isEmpty {
            finalRunState = oneShotRunStateStore.transition(
                to: .awaitingGrant,
                owner: .hubL5,
                activePools: planning.decision.poolPlan.map(\ .poolID),
                activeLanes: planning.decision.poolPlan.flatMap(\ .laneIDs),
                topBlocker: normalization.request.requiresHumanAuthorizationTypes.map(\ .rawValue).joined(separator: ","),
                nextDirectedTarget: "Hub-L5",
                userVisibleSummary: "awaiting grant for guarded one-shot launch",
                evidenceRefs: OneShotControlPlaneSnapshot.defaultEvidenceRefs(),
                auditRef: normalization.request.auditRef
            )
            _ = await ensureVoiceAuthorizationForGuardedOneShotLaunch(
                request: normalization.request,
                planDecision: planning.decision
            )
        } else {
            let launchingRunState = oneShotRunStateStore.transition(
                to: .launching,
                owner: .supervisor,
                activePools: planning.decision.poolPlan.map(\ .poolID),
                activeLanes: planning.decision.poolPlan.flatMap(\ .laneIDs),
                topBlocker: "none",
                nextDirectedTarget: "Supervisor",
                userVisibleSummary: "one-shot mainline ready to launch",
                evidenceRefs: OneShotControlPlaneSnapshot.defaultEvidenceRefs(),
                auditRef: normalization.request.auditRef
            )
            oneShotRunState = launchingRunState
            let outcome = await executePreparedOneShotLaunch(
                request: normalization.request,
                planDecision: planning.decision
            )
            applyGuardedOneShotLaunchResumeOutcome(
                outcome,
                request: normalization.request,
                planDecision: planning.decision
            )
            finalRunState = oneShotRunState ?? launchingRunState
        }

        oneShotRunState = finalRunState

        return OneShotControlPlaneSnapshot(
            schemaVersion: "xt.one_shot_control_plane_snapshot.v1",
            normalization: normalization,
            planDecision: planning.decision,
            seatGovernor: planning.seatGovernor,
            runState: finalRunState,
            fieldFreeze: .ai1Core
        )
    }

    @discardableResult
    private func ensureVoiceAuthorizationForGuardedOneShotLaunch(
        request: SupervisorOneShotIntakeRequest,
        planDecision: AdaptivePoolPlanDecision
    ) async -> SupervisorVoiceAuthorizationResolution? {
        let voiceRequest = makeVoiceAuthorizationRequestForGuardedOneShotLaunch(
            request: request,
            planDecision: planDecision
        )

        if let activeRequest = activeVoiceAuthorizationRequest,
           activeRequest.requestId == voiceRequest.requestId,
           let existingResolution = voiceAuthorizationResolution {
            switch existingResolution.state {
            case .pending, .escalatedToMobile:
                if activeVoiceChallenge != nil {
                    return existingResolution
                }
            case .verified:
                return existingResolution
            case .denied, .failClosed:
                break
            }
        }

        return await startVoiceAuthorization(voiceRequest)
    }

    private func makeVoiceAuthorizationRequestForGuardedOneShotLaunch(
        request: SupervisorOneShotIntakeRequest,
        planDecision: AdaptivePoolPlanDecision
    ) -> SupervisorVoiceAuthorizationRequest {
        let authorizationTypes = request.requiresHumanAuthorizationTypes
        let requestId = oneShotVoiceAuthorizationRequestID(
            requestID: request.requestID,
            authorizationTypes: authorizationTypes
        )
        let riskTier = oneShotVoiceAuthorizationRiskTier(
            authorizationTypes: authorizationTypes,
            riskSurface: planDecision.riskSurface
        )
        let primaryAuthorizationType = oneShotPrimaryVoiceAuthorizationType(authorizationTypes)
        let templateId = oneShotVoiceAuthorizationTemplateID(
            primaryAuthorizationType: primaryAuthorizationType,
            authorizationTypes: authorizationTypes
        )
        let goalSummary = capped(
            request.userGoal.replacingOccurrences(of: "\n", with: " "),
            maxChars: 160
        )
        let poolSummary = planDecision.poolPlan.map(\.poolID).joined(separator: ",")
        let laneSummary = planDecision.poolPlan.flatMap(\.laneIDs).joined(separator: ",")
        let authSummary = authorizationTypes.map(\.rawValue).joined(separator: ",")

        return SupervisorVoiceAuthorizationRequest(
            requestId: requestId,
            projectId: request.projectID,
            templateId: templateId,
            actionText: oneShotVoiceAuthorizationActionText(
                primaryAuthorizationType: primaryAuthorizationType,
                authorizationTypes: authorizationTypes
            ),
            scopeText: [
                "goal=\(goalSummary)",
                "auth_types=\(authSummary)",
                "pools=\(poolSummary.isEmpty ? "none" : poolSummary)",
                "lanes=\(laneSummary.isEmpty ? "none" : laneSummary)"
            ].joined(separator: "; "),
            amountText: oneShotVoiceAuthorizationAmountText(userGoal: request.userGoal),
            riskTier: riskTier,
            boundDeviceId: preferredVoiceBoundDeviceId(for: request.projectID),
            mobileTerminalId: nil,
            challengeCode: nil,
            ttlMs: riskTier >= .high ? 180_000 : 120_000
        )
    }

    private func oneShotVoiceAuthorizationRequestID(
        requestID: String,
        authorizationTypes: [OneShotHumanAuthorizationType]
    ) -> String {
        let normalizedRequestID = requestID
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let authKey = authorizationTypes
            .map(\.rawValue)
            .joined(separator: "_")
            .replacingOccurrences(of: "-", with: "_")
        return "voice_auth_\(normalizedRequestID)_\(authKey)"
    }

    private func oneShotPrimaryVoiceAuthorizationType(
        _ authorizationTypes: [OneShotHumanAuthorizationType]
    ) -> OneShotHumanAuthorizationType {
        let priority: [OneShotHumanAuthorizationType] = [
            .payment,
            .externalSideEffect,
            .secretBinding,
            .connectorBinding,
            .scopeExpansion
        ]
        for candidate in priority where authorizationTypes.contains(candidate) {
            return candidate
        }
        return authorizationTypes.first ?? .externalSideEffect
    }

    private func oneShotVoiceAuthorizationTemplateID(
        primaryAuthorizationType: OneShotHumanAuthorizationType,
        authorizationTypes: [OneShotHumanAuthorizationType]
    ) -> String {
        if authorizationTypes.count > 1 {
            return "voice.grant.guarded_one_shot_launch.v1"
        }

        switch primaryAuthorizationType {
        case .payment:
            return "voice.grant.payment.v1"
        case .externalSideEffect:
            return "voice.grant.external_side_effect.v1"
        case .connectorBinding:
            return "voice.grant.connector_binding.v1"
        case .secretBinding:
            return "voice.grant.secret_binding.v1"
        case .scopeExpansion:
            return "voice.grant.scope_expansion.v1"
        }
    }

    private func oneShotVoiceAuthorizationActionText(
        primaryAuthorizationType: OneShotHumanAuthorizationType,
        authorizationTypes: [OneShotHumanAuthorizationType]
    ) -> String {
        if authorizationTypes.count > 1 {
            return "Approve guarded one-shot launch with multiple high-risk actions"
        }

        switch primaryAuthorizationType {
        case .payment:
            return "Approve guarded one-shot payment action"
        case .externalSideEffect:
            return "Approve guarded one-shot external side effect"
        case .connectorBinding:
            return "Approve guarded one-shot connector binding"
        case .secretBinding:
            return "Approve guarded one-shot secret binding"
        case .scopeExpansion:
            return "Approve one-shot scope expansion"
        }
    }

    private func oneShotVoiceAuthorizationRiskTier(
        authorizationTypes: [OneShotHumanAuthorizationType],
        riskSurface: OneShotRiskSurface
    ) -> LaneRiskTier {
        var riskTier = laneRiskTier(from: riskSurface)
        if authorizationTypes.contains(.payment) {
            riskTier = .critical
        }
        if authorizationTypes.contains(.externalSideEffect)
            || authorizationTypes.contains(.connectorBinding)
            || authorizationTypes.contains(.secretBinding)
            || authorizationTypes.contains(.scopeExpansion) {
            riskTier = max(riskTier, .high)
        }
        return riskTier
    }

    private func laneRiskTier(from riskSurface: OneShotRiskSurface) -> LaneRiskTier {
        switch riskSurface {
        case .low:
            return .low
        case .medium:
            return .medium
        case .high:
            return .high
        case .critical:
            return .critical
        }
    }

    private func oneShotVoiceAuthorizationAmountText(userGoal: String) -> String? {
        let goal = userGoal.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !goal.isEmpty else { return nil }

        let patterns = [
            #"(?i)\b(?:usd|rmb|cny|eur|gbp|jpy)\s*[\d,]+(?:\.\d+)?\b"#,
            #"(?i)\b[\d,]+(?:\.\d+)?\s*(?:usd|rmb|cny|eur|gbp|jpy)\b"#,
            #"(?i)[¥$€£]\s*[\d,]+(?:\.\d+)?"#
        ]

        for pattern in patterns {
            if let range = goal.range(of: pattern, options: .regularExpression) {
                let token = goal[range].trimmingCharacters(in: .whitespacesAndNewlines)
                if !token.isEmpty {
                    return String(token)
                }
            }
        }

        return nil
    }

    private func preferredVoiceBoundDeviceId(for projectID: String) -> String? {
        guard let appModel else { return nil }
        let selectedProjectID = appModel.selectedProjectId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !selectedProjectID.isEmpty, selectedProjectID == projectID else { return nil }
        let boundDeviceId = appModel.projectConfig?.trustedAutomationDeviceId
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return boundDeviceId.isEmpty ? nil : boundDeviceId
    }

    func resetAutomationRuntimeState() {
        automationExecutionTask?.cancel()
        automationExecutionTask = nil
        automationAutoRetryTask?.cancel()
        automationAutoRetryTask = nil
        automationPreparedRun = nil
        automationCurrentCheckpoint = nil
        automationRecoveryDecision = nil
        automationLatestExecutionReport = nil
        automationLatestRetryPackage = nil
        automationStatusLine = "automation runtime: idle"
        automationRunCoordinator = XTAutomationRunCoordinator()
        automationRunExecutor = XTAutomationRunExecutor()
        resetVoiceAuthorizationState()
    }

    func installAutomationRunExecutorForTesting(_ executor: XTAutomationRunExecutor) {
        automationRunExecutor = executor
    }

    func automationRetryTriggerForTesting() -> String {
        automationRetryTrigger(from: automationLatestRetryPackage)
    }

    func resetVoiceAuthorizationState() {
        voiceAuthorizationResolution = nil
        activeVoiceChallenge = nil
        activeVoiceAuthorizationRequest = nil
        voiceAuthorizationInFlight = false
        voiceAuthorizationBridge = SupervisorVoiceAuthorizationBridge()
        preparedOneShotLaunchExecutorForTesting = nil
    }

    func installVoiceAuthorizationBridgeForTesting(_ bridge: SupervisorVoiceAuthorizationBridge) {
        voiceAuthorizationBridge = bridge
    }

    func resetOneShotControlPlaneState() {
        oneShotNormalizationIssues = []
        oneShotIntakeRequest = nil
        oneShotAdaptivePoolPlan = nil
        oneShotSeatGovernor = nil
        oneShotRunState = nil
        oneShotPlannerExplain = []
        oneShotPreparedSplitBuildResult = nil
    }

    func installPreparedOneShotLaunchExecutorForTesting(
        _ executor: @escaping (SupervisorOneShotIntakeRequest, AdaptivePoolPlanDecision, SplitProposalBuildResult) async -> GuardedOneShotLaunchResumeOutcome
    ) {
        preparedOneShotLaunchExecutorForTesting = executor
    }

    @discardableResult
    func startAutomationRun(
        for project: AXProjectEntry,
        request: XTAutomationRunRequest,
        emitSystemMessage: Bool = false
    ) throws -> XTAutomationPreparedRun {
        guard let ctx = projectContext(from: project) else {
            throw SupervisorAutomationRuntimeError.projectContextMissing(project.projectId)
        }
        return try startAutomationRun(for: ctx, request: request, emitSystemMessage: emitSystemMessage)
    }

    @discardableResult
    func startAutomationRun(
        for ctx: AXProjectContext,
        request: XTAutomationRunRequest,
        emitSystemMessage: Bool = false
    ) throws -> XTAutomationPreparedRun {
        let prepared = try prepareAutomationRun(for: ctx, request: request, emitSystemMessage: emitSystemMessage)
        try scheduleAutomationExecutionIfNeeded(
            prepared: prepared,
            ctx: ctx,
            emitSystemMessage: emitSystemMessage
        )
        return prepared
    }

    @discardableResult
    func prepareAutomationRun(
        for project: AXProjectEntry,
        request: XTAutomationRunRequest,
        emitSystemMessage: Bool = false
    ) throws -> XTAutomationPreparedRun {
        guard let ctx = projectContext(from: project) else {
            throw SupervisorAutomationRuntimeError.projectContextMissing(project.projectId)
        }
        return try prepareAutomationRun(for: ctx, request: request, emitSystemMessage: emitSystemMessage)
    }

    @discardableResult
    func prepareAutomationRun(
        for ctx: AXProjectContext,
        request: XTAutomationRunRequest,
        emitSystemMessage: Bool = false
    ) throws -> XTAutomationPreparedRun {
        let prepared = try automationRunCoordinator.prepareActiveRun(for: ctx, request: request)
        automationPreparedRun = prepared
        automationCurrentCheckpoint = prepared.currentCheckpoint
        automationRecoveryDecision = nil
        automationLatestRetryPackage = nil
        automationStatusLine = automationStatusLine(
            runID: prepared.launchRef,
            state: prepared.currentCheckpoint.state,
            detail: prepared.verticalSlice.eventRunner.launchDecision.decision.rawValue
        )
        appendRecentEvent("automation prepared: \(ctx.projectName()) -> \(prepared.launchRef)")
        if emitSystemMessage {
            addSystemMessage("automation 已准备：\(ctx.projectName()) -> \(prepared.launchRef)")
        }
        return prepared
    }

    private func scheduleAutomationExecutionIfNeeded(
        prepared: XTAutomationPreparedRun,
        ctx: AXProjectContext,
        emitSystemMessage: Bool
    ) throws {
        guard prepared.currentCheckpoint.state == .queued else { return }

        let config = try AXProjectStore.loadOrCreateConfig(for: ctx)
        let recipe = prepared.executionRecipe
        guard !recipe.actionGraph.isEmpty else {
            return
        }
        if prepared.recipeRef == recipe.ref,
           config.automationRecipes.contains(where: { $0.ref == recipe.ref }) == false {
            return
        }

        automationExecutionTask?.cancel()
        automationAutoRetryTask?.cancel()
        automationAutoRetryTask = nil
        automationStatusLine = automationStatusLine(
            runID: prepared.launchRef,
            state: prepared.currentCheckpoint.state,
            detail: "auto_execution_scheduled"
        )
        appendRecentEvent("automation execution scheduled: \(ctx.projectName()) -> \(prepared.launchRef)")

        automationExecutionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.executeAutomationActionGraph(
                prepared: prepared,
                recipe: recipe,
                ctx: ctx,
                emitSystemMessage: emitSystemMessage
            )
        }
    }

    private func executeAutomationActionGraph(
        prepared: XTAutomationPreparedRun,
        recipe: AXAutomationRecipeRuntimeBinding,
        ctx: AXProjectContext,
        emitSystemMessage: Bool
    ) async {
        defer { automationExecutionTask = nil }
        let startAuditRef = "audit-xt-auto-action-graph-start-\(Int(Date().timeIntervalSince1970))"

        do {
            let runningCheckpoint = try automationRunCoordinator.advanceRun(
                prepared.launchRef,
                to: .running,
                for: ctx,
                auditRef: startAuditRef,
                now: Date()
            )
            automationCurrentCheckpoint = runningCheckpoint
            automationStatusLine = automationStatusLine(
                runID: runningCheckpoint.runID,
                state: runningCheckpoint.state,
                detail: "action_graph_started"
            )

            let report = await automationRunExecutor.execute(
                runID: prepared.launchRef,
                recipe: recipe,
                ctx: ctx,
                lineage: prepared.lineage,
                verifyCommandsOverride: prepared.verifyCommandsOverride
            )
            automationLatestExecutionReport = report

            let finalCheckpoint = try automationRunCoordinator.advanceRun(
                prepared.launchRef,
                to: report.finalState,
                retryAfterSeconds: report.finalState == .blocked ? 120 : 0,
                for: ctx,
                auditRef: report.auditRef,
                now: Date()
            )
            automationCurrentCheckpoint = finalCheckpoint
            automationRecoveryDecision = nil
            automationStatusLine = automationStatusLine(
                runID: finalCheckpoint.runID,
                state: finalCheckpoint.state,
                detail: report.detail
            )
            appendRecentEvent("automation executed: \(ctx.projectName()) -> \(report.detail)")
            if emitSystemMessage {
                addSystemMessage(renderAutomationExecutionSummary(projectName: ctx.projectName(), report: report))
            }
            scheduleAutomaticSelfIterationIfNeeded(
                prepared: prepared,
                report: report,
                finalCheckpoint: finalCheckpoint,
                ctx: ctx,
                emitSystemMessage: emitSystemMessage
            )
        } catch {
            automationStatusLine = "automation runtime: \(prepared.launchRef) -> failed (\(error.localizedDescription))"
            appendRecentEvent("automation execution failed: \(ctx.projectName()) -> \(error.localizedDescription)")
            if emitSystemMessage {
                addSystemMessage("automation 执行失败：\(ctx.projectName()) -> \(error.localizedDescription)")
            }
        }
    }

    @discardableResult
    func advanceAutomationRun(
        for project: AXProjectEntry,
        to nextState: XTAutomationRunState,
        runID: String? = nil,
        retryAfterSeconds: Int = 0,
        auditRef: String,
        now: Date = Date(),
        emitSystemMessage: Bool = false
    ) throws -> XTAutomationRunCheckpoint {
        guard let ctx = projectContext(from: project) else {
            throw SupervisorAutomationRuntimeError.projectContextMissing(project.projectId)
        }
        return try advanceAutomationRun(
            for: ctx,
            to: nextState,
            runID: runID,
            retryAfterSeconds: retryAfterSeconds,
            auditRef: auditRef,
            now: now,
            emitSystemMessage: emitSystemMessage
        )
    }

    @discardableResult
    func advanceAutomationRun(
        for ctx: AXProjectContext,
        to nextState: XTAutomationRunState,
        runID: String? = nil,
        retryAfterSeconds: Int = 0,
        auditRef: String,
        now: Date = Date(),
        emitSystemMessage: Bool = false
    ) throws -> XTAutomationRunCheckpoint {
        let resolvedRunID = try resolvedAutomationRunID(runID)
        let checkpoint = try automationRunCoordinator.advanceRun(
            resolvedRunID,
            to: nextState,
            retryAfterSeconds: retryAfterSeconds,
            for: ctx,
            auditRef: auditRef,
            now: now
        )
        automationCurrentCheckpoint = checkpoint
        automationStatusLine = automationStatusLine(
            runID: checkpoint.runID,
            state: checkpoint.state,
            detail: checkpoint.lastTransition
        )
        appendRecentEvent("automation advanced: \(ctx.projectName()) -> \(checkpoint.state.rawValue)")
        if emitSystemMessage {
            addSystemMessage("automation 状态更新：\(ctx.projectName()) -> \(checkpoint.state.rawValue)")
        }
        return checkpoint
    }

    @discardableResult
    func cancelAutomationRun(
        for project: AXProjectEntry,
        runID: String? = nil,
        auditRef: String,
        now: Date = Date(),
        emitSystemMessage: Bool = false
    ) throws -> XTAutomationRestartRecoveryDecision {
        guard let ctx = projectContext(from: project) else {
            throw SupervisorAutomationRuntimeError.projectContextMissing(project.projectId)
        }
        return try cancelAutomationRun(
            for: ctx,
            runID: runID,
            auditRef: auditRef,
            now: now,
            emitSystemMessage: emitSystemMessage
        )
    }

    @discardableResult
    func cancelAutomationRun(
        for ctx: AXProjectContext,
        runID: String? = nil,
        auditRef: String,
        now: Date = Date(),
        emitSystemMessage: Bool = false
    ) throws -> XTAutomationRestartRecoveryDecision {
        let resolvedRunID = try resolvedAutomationRunID(runID)
        automationExecutionTask?.cancel()
        automationExecutionTask = nil
        automationAutoRetryTask?.cancel()
        automationAutoRetryTask = nil
        try automationRunCoordinator.cancelRun(
            resolvedRunID,
            for: ctx,
            auditRef: auditRef,
            now: now
        )
        let decision = try automationRunCoordinator.recoverRun(
            resolvedRunID,
            for: ctx,
            checkpointAgeSeconds: 0,
            auditRef: auditRef
        )
        automationRecoveryDecision = decision
        automationStatusLine = automationStatusLine(
            runID: decision.runID,
            state: decision.recoveredState,
            detail: decision.holdReason
        )
        appendRecentEvent("automation cancelled: \(ctx.projectName()) -> \(decision.runID)")
        if emitSystemMessage {
            addSystemMessage("automation 已取消：\(ctx.projectName()) -> \(decision.runID)")
        }
        return decision
    }

    @discardableResult
    func recoverLatestAutomationRun(
        for project: AXProjectEntry,
        checkpointAgeSeconds: Int,
        auditRef: String,
        emitSystemMessage: Bool = false
    ) throws -> XTAutomationRestartRecoveryDecision? {
        guard let ctx = projectContext(from: project) else {
            throw SupervisorAutomationRuntimeError.projectContextMissing(project.projectId)
        }
        return try recoverLatestAutomationRun(
            for: project,
            ctx: ctx,
            checkpointAgeSeconds: checkpointAgeSeconds,
            auditRef: auditRef,
            emitSystemMessage: emitSystemMessage
        )
    }

    @discardableResult
    func recoverLatestAutomationRun(
        for ctx: AXProjectContext,
        checkpointAgeSeconds: Int,
        auditRef: String,
        emitSystemMessage: Bool = false
    ) throws -> XTAutomationRestartRecoveryDecision? {
        try recoverLatestAutomationRun(
            for: automationProjectEntry(for: ctx),
            ctx: ctx,
            checkpointAgeSeconds: checkpointAgeSeconds,
            auditRef: auditRef,
            emitSystemMessage: emitSystemMessage
        )
    }

    @discardableResult
    private func recoverLatestAutomationRun(
        for project: AXProjectEntry,
        ctx: AXProjectContext,
        checkpointAgeSeconds: Int,
        auditRef: String,
        emitSystemMessage: Bool
    ) throws -> XTAutomationRestartRecoveryDecision? {
        let decision = try automationRunCoordinator.recoverLatestRun(
            for: ctx,
            checkpointAgeSeconds: checkpointAgeSeconds,
            auditRef: auditRef
        )
        automationRecoveryDecision = decision
        automationLatestRetryPackage = nil
        if let decision {
            let checkpoint = try automationRunCoordinator.latestCheckpoint(for: decision.runID, in: ctx)
            automationCurrentCheckpoint = checkpoint
            let retryPackage = scheduleAutomationRetryIfPossible(
                for: project,
                ctx: ctx,
                decision: decision,
                auditRef: auditRef
            )
            automationRecoveryDecision = decision
            if retryPackage == nil {
                automationStatusLine = automationStatusLine(
                    runID: decision.runID,
                    state: decision.recoveredState,
                    detail: decision.decision.rawValue
                )
            }
            appendRecentEvent("automation recovered: \(ctx.projectName()) -> \(decision.runID)")
            if emitSystemMessage {
                addSystemMessage("automation 已恢复判定：\(ctx.projectName()) -> \(decision.decision.rawValue)")
            }
        }
        return decision
    }

    private func resolvedAutomationRunID(_ runID: String?) throws -> String {
        let candidate = runID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !candidate.isEmpty {
            return candidate
        }
        if let checkpointRunID = automationCurrentCheckpoint?.runID,
           !checkpointRunID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return checkpointRunID
        }
        if let preparedRunID = automationPreparedRun?.launchRef,
           !preparedRunID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return preparedRunID
        }
        throw XTAutomationRunCoordinatorError.runNotFound("active")
    }

    private func automationStatusLine(runID: String, state: XTAutomationRunState, detail: String) -> String {
        let cleanDetail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanDetail.isEmpty {
            return "automation runtime: \(runID) -> \(state.rawValue)"
        }
        return "automation runtime: \(runID) -> \(state.rawValue) (\(cleanDetail))"
    }
}
