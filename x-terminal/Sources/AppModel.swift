import AppKit
import Combine
import Foundation
import Network

enum HubSetupStepState: String {
    case idle
    case running
    case awaitingApproval
    case success
    case failed
    case skipped
}

enum HubStartupAutomaticConnectDisposition: Equatable {
    case none
    case recoverExistingProfile(allowBootstrap: Bool)
    case firstPairNearby
}

struct HubNetworkPathFingerprint: Equatable {
    var statusKey: String
    var usesWiFi: Bool
    var usesWiredEthernet: Bool
    var usesCellular: Bool
    var isExpensive: Bool
    var isConstrained: Bool

    init(
        statusKey: String,
        usesWiFi: Bool,
        usesWiredEthernet: Bool,
        usesCellular: Bool,
        isExpensive: Bool,
        isConstrained: Bool
    ) {
        self.statusKey = statusKey
        self.usesWiFi = usesWiFi
        self.usesWiredEthernet = usesWiredEthernet
        self.usesCellular = usesCellular
        self.isExpensive = isExpensive
        self.isConstrained = isConstrained
    }

    init(path: NWPath) {
        self.init(
            statusKey: Self.statusKey(path.status),
            usesWiFi: path.usesInterfaceType(.wifi),
            usesWiredEthernet: path.usesInterfaceType(.wiredEthernet),
            usesCellular: path.usesInterfaceType(.cellular),
            isExpensive: path.isExpensive,
            isConstrained: path.isConstrained
        )
    }

    var isSatisfied: Bool {
        statusKey == Self.statusKey(.satisfied)
    }

    func hasMeaningfulReconnectChange(comparedTo previous: Self) -> Bool {
        if previous.isSatisfied != isSatisfied {
            return isSatisfied
        }

        guard isSatisfied else { return false }

        // Ignore cost/constrained drift on the same active interface set.
        // Those flags can bounce on a stable Wi-Fi path and should not tear
        // down the current remote route.
        return previous.usesWiFi != usesWiFi
            || previous.usesWiredEthernet != usesWiredEthernet
            || previous.usesCellular != usesCellular
    }

    private static func statusKey(_ status: NWPath.Status) -> String {
        switch status {
        case .satisfied:
            return "satisfied"
        case .requiresConnection:
            return "requires_connection"
        case .unsatisfied:
            return "unsatisfied"
        @unknown default:
            return "unknown"
        }
    }
}

struct HubRemoteEndpointFingerprint: Equatable {
    var pairingPort: Int
    var grpcPort: Int
    var internetHost: String

    init(pairingPort: Int, grpcPort: Int, internetHost: String) {
        self.pairingPort = pairingPort
        self.grpcPort = grpcPort
        self.internetHost = internetHost.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct HubPairingResetPlan: Equatable {
    var endpoint: HubRemoteEndpointFingerprint
    var preserveEndpointOverride: Bool
    var shouldAutoDetect: Bool
}

private struct XTNotificationObservationToken {
    var center: NotificationCenter
    var token: NSObjectProtocol
}

@MainActor
final class AppModel: ObservableObject {
    private struct HistoricalProjectBoundaryRepairSummary {
        var scanned: Int = 0
        var repairedConfigCount: Int = 0
        var repairedMemoryCount: Int = 0
        var failedProjectRefs: [String] = []

        var touchedCount: Int {
            repairedConfigCount + repairedMemoryCount
        }

        var failedCount: Int {
            failedProjectRefs.count
        }

        var outcomeToken: String {
            if failedCount > 0 {
                return touchedCount > 0 ? "partial" : "failed"
            }
            if touchedCount > 0 {
                return "repaired"
            }
            return scanned == 0 ? "idle" : "noop"
        }

        func statusLine(reason: String) -> String {
            var parts = [
                "historical_project_boundary_repair=\(outcomeToken)",
                "reason=\(reason)",
                "scanned=\(scanned)",
                "repaired_config=\(repairedConfigCount)",
                "repaired_memory=\(repairedMemoryCount)"
            ]
            if failedCount > 0 {
                parts.append("failed=\(failedCount)")
            }
            return parts.joined(separator: " ")
        }
    }

    @Published var settingsStore: SettingsStore
    @Published var llmRouter: LLMRouter
    @Published var projectRoot: URL? = nil {
        didSet {
            projectRootLoadTask?.cancel()
            projectRootLoadTask = Task { @MainActor [weak self] in
                guard let self else { return }
                guard !Task.isCancelled else { return }
                await self.loadSelectedProject()
            }
        }
    }

    @Published var registry: AXProjectRegistry = .empty()
    @Published var selectedProjectId: String? = nil {
        didSet {
            projectSelectionTask?.cancel()
            projectSelectionTask = Task { @MainActor [weak self] in
                guard let self else { return }
                guard !Task.isCancelled else { return }
                await self.applySelection()
            }
        }
    }

    @Published var projectContext: AXProjectContext? = nil
    @Published var memory: AXMemory? = nil
    @Published var usageSummary: AXUsageSummary = .empty()
    @Published var projectConfig: AXProjectConfig? = nil
    @Published var projectRemoteRuntimeSurfaceOverride: AXProjectRuntimeSurfaceRemoteOverrideSnapshot? = nil
    @Published var skillsCompatibilitySnapshot: AXSkillsDoctorSnapshot = .empty
    @Published var unifiedDoctorReport: XTUnifiedDoctorReport = .empty
    @Published private(set) var officialSkillsRecheckStatusLine: String = ""
    @Published private(set) var historicalProjectBoundaryRepairStatusLine: String = ""
    @Published private(set) var supervisorVoiceSmokeRunning: Bool = false
    @Published private(set) var supervisorVoiceSmokeStatusLine: String = ""
    @Published private(set) var supervisorVoiceSmokeDetailLine: String = ""
    @Published private(set) var supervisorVoiceSmokeLastPassed: Bool? = nil
    @Published private(set) var supervisorVoiceSmokeReportURL: URL? = nil
    @Published private(set) var supervisorVoiceSmokeReportSummary: XTSupervisorVoiceSmokeReportSummary? = nil
    @Published var lastImportedAgentSkillDirectory: URL? = nil
    @Published var lastImportedAgentSkillName: String = ""
    @Published var lastImportedAgentSkillStage: HubIPCClient.AgentImportStageResult? = nil
    @Published var lastImportedAgentSkillStatusLine: String = ""
    @Published var agentSkillImportBusy: Bool = false
    @Published var baselineInstallBusy: Bool = false
    @Published var baselineInstallStatusLine: String = ""
    @Published private(set) var skillGovernanceActionStatusLine: String = ""

    var skillsDirectoryOverrideForTesting: URL? = nil
    var openPanelSelectionOverrideForTesting: ((NSOpenPanel) -> [URL]?)? = nil
    var openedURLOverrideForTesting: ((URL) -> Void)? = nil
    var alertPresenterOverrideForTesting: ((String, String) -> Void)? = nil
    var baselineInstallConfirmationOverrideForTesting: ((String, String) -> Bool)? = nil
    var baselineInstallActionOverrideForTesting: ((AXAgentBaselineInstallScope) -> Void)? = nil
    var skillRemovalConfirmationOverrideForTesting: ((String, String) -> Bool)? = nil
    var skillRenamePromptOverrideForTesting: ((String, String, String) -> String?)? = nil
    var stagedImportSummaryOverrideForTesting: ((URL, URL) async -> String?)? = nil
    var supervisorVoiceSmokeReportURLOverrideForTesting: URL? = nil

    @Published var runtimeStatus: AIRuntimeStatus? = nil
    @Published var modelsState: ModelStateSnapshot = .empty()

    @Published var hubConnected: Bool = false
    @Published var hubBaseDir: URL? = nil
    @Published var hubStatus: HubStatus? = nil
    @Published var hubLastError: String? = nil
    @Published var hubRemoteConnected: Bool = false
    @Published var hubRemoteRoute: HubRemoteRoute = .none
    @Published var hubRemotePaidAccessSnapshot: HubRemotePaidAccessSnapshot? = nil
    @Published var hubRemoteLog: String = ""
    @Published var hubRemoteLinking: Bool = false
    @Published var hubRemoteSummary: String = ""
    @Published var hubFreshPairReconnectSmokeSnapshot: XTFreshPairReconnectSmokeSnapshot? = nil
    @Published var hubRemoteShadowReconnectSmokeSnapshot: XTRemoteShadowReconnectSmokeSnapshot? = nil
    @Published var hubSetupDiscoverState: HubSetupStepState = .idle
    @Published var hubSetupBootstrapState: HubSetupStepState = .idle
    @Published var hubSetupConnectState: HubSetupStepState = .idle
    @Published var hubSetupFailureCode: String = ""
    @Published var hubPortAutoDetectRunning: Bool = false
    @Published var hubPortAutoDetectMessage: String = ""
    @Published var hubDiscoveredCandidates: [HubDiscoveredHubCandidateSummary] = []
    @Published var hubPairingPort: Int = 50052
    @Published var hubGrpcPort: Int = 50051
    @Published var hubInternetHost: String = ""
    @Published var hubInviteToken: String = ""
    @Published var hubInviteAlias: String = ""
    @Published var hubInviteInstanceID: String = ""
    @Published var hubAxhubctlPath: String = ""

    var hubInteractive: Bool {
        hubConnected || hubRemoteConnected
    }

    @available(*, deprecated, message: "Use projectRemoteRuntimeSurfaceOverride")
    var projectRemoteAutonomyOverride: AXProjectAutonomyRemoteOverrideSnapshot? {
        get { projectRemoteRuntimeSurfaceOverride }
        set { projectRemoteRuntimeSurfaceOverride = newValue }
    }

    var canReviewLastImportedAgentSkill: Bool {
        guard !agentSkillImportBusy else { return false }
        let stagingId = lastImportedAgentSkillStage?.stagingId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !stagingId.isEmpty
    }

    var canEnableLastImportedAgentSkill: Bool {
        guard !agentSkillImportBusy else { return false }
        return lastImportedAgentSkillDirectory != nil
    }

    var canInstallDefaultAgentBaselineGlobally: Bool {
        guard !baselineInstallBusy else { return false }
        return hubInteractive
    }

    var canInstallDefaultAgentBaselineForCurrentProject: Bool {
        guard !baselineInstallBusy else { return false }
        guard hubInteractive else { return false }
        guard let selectedProjectId else { return false }
        return selectedProjectId != AXProjectRegistry.globalHomeId
    }

    var lastImportedAgentSkillToolbarStatusLine: String {
        let line = lastImportedAgentSkillStatusLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return "" }
        if line.count <= 72 {
            return line
        }
        let idx = line.index(line.startIndex, offsetBy: 72)
        return String(line[..<idx]) + "..."
    }

    var baselineInstallToolbarStatusLine: String {
        let line = baselineInstallStatusLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return "" }
        if line.count <= 72 {
            return line
        }
        let idx = line.index(line.startIndex, offsetBy: 72)
        return String(line[..<idx]) + "..."
    }

    var officialSkillChannelSummaryLine: String {
        skillsCompatibilitySnapshot.officialChannelSummaryLine
    }

    var officialSkillChannelDetailLine: String {
        skillsCompatibilitySnapshot.officialChannelDetailLine
    }

    var officialSkillChannelTopBlockersLine: String {
        skillsCompatibilitySnapshot.officialChannelTopBlockersLine
    }

    var officialSkillChannelTopBlockerSummaries: [AXOfficialSkillBlockerSummaryItem] {
        skillsCompatibilitySnapshot.officialPackageLifecycleTopBlockerSummaries
    }

    @Published var memoryCoarseRunning: Bool = false
    @Published var memoryRefineRunning: Bool = false

    @Published var bridgeEnabled: Bool = false
    @Published var bridgeAlive: Bool = false
    @Published var bridgeLastEnsureError: String = ""

    @Published var serverRunning: Bool = false
    @Published var localServerEnabled: Bool = false
    @Published var localServerPort: Int = 8080
    @Published var localServerLastError: String = ""
    @Published private(set) var projectFocusRequest: AXProjectFocusRequest? = nil
    @Published private(set) var supervisorFocusRequest: AXSupervisorFocusRequest? = nil
    @Published private(set) var settingsFocusRequest: XTSettingsFocusRequest? = nil
    @Published private(set) var hubSetupFocusRequest: XTHubSetupFocusRequest? = nil
    @Published private(set) var supervisorSettingsFocusRequest: XTSupervisorSettingsFocusRequest? = nil
    @Published private(set) var modelSettingsFocusRequest: XTModelSettingsFocusRequest? = nil
    @Published private(set) var projectDetailFocusRequest: XTProjectDetailFocusRequest? = nil
    @Published private(set) var projectSettingsFocusRequest: XTProjectSettingsFocusRequest? = nil
    @Published private var resumeReminderAcknowledgedSummaryMsByProjectId: [String: Int64] = [:]

    private var chatSessions: [String: ChatSessionModel] = [:]
    private var terminalSessions: [String: TerminalSessionModel] = [:]

    @Published var paneByProjectId: [String: AXProjectPane] = [:]

    private var notifTokens: [XTNotificationObservationToken] = []
    private var settingsSubscriptions: Set<AnyCancellable> = []
    private var projectRootLoadTask: Task<Void, Never>? = nil
    private var projectSelectionTask: Task<Void, Never>? = nil
    private let loadPersistedProjectRegistry: Bool
    private let persistProjectRegistryChanges: Bool
    private var skillScanTimer: Timer? = nil
    private let skillScanLastKey = "xterminal_skill_scan_last_ts"
    private let legacySkillScanLastKey = "xterminal_skill_scan_last_ts"
    private let skillScanHour = 17
    private let skillScanMinute = 30
    private let skillsMigrationKey = "xterminal_skills_migration_v1"
    private let legacySkillsMigrationKey = "xterminal_skills_migration_v1"
    private let hubPairingPortKey = "xterminal_hub_pairing_port"
    private let legacyHubPairingPortKey = "xterminal_hub_pairing_port"
    private let hubGrpcPortKey = "xterminal_hub_grpc_port"
    private let legacyHubGrpcPortKey = "xterminal_hub_grpc_port"
    private let hubInternetHostKey = "xterminal_hub_internet_host"
    private let legacyHubInternetHostKey = "xterminal_hub_internet_host"
    private let hubInviteTokenKey = "xterminal_hub_invite_token"
    private let legacyHubInviteTokenKey = "xterminal_hub_invite_token"
    private let hubInviteAliasKey = "xterminal_hub_invite_alias"
    private let legacyHubInviteAliasKey = "xterminal_hub_invite_alias"
    private let hubInviteInstanceIDKey = "xterminal_hub_invite_instance_id"
    private let legacyHubInviteInstanceIDKey = "xterminal_hub_invite_instance_id"
    private let hubAxhubctlPathKey = "xterminal_hub_axhubctl_path"
    private let legacyHubAxhubctlPathKey = "xterminal_hub_axhubctl_path"
    private let hubRemoteEndpointOverridePendingKey = "xterminal_hub_remote_endpoint_override_pending"
    private let legacyHubRemoteEndpointOverridePendingKey = "xterminal_hub_remote_endpoint_override_pending"
    private let bridgeAlwaysOnKey = "xterminal_bridge_always_on"
    private let legacyBridgeAlwaysOnKey = "xterminal_bridge_always_on"
    private let localServerEnabledKey = "xterminal_local_server_enabled"
    private let legacyLocalServerEnabledKey = "xterminal_local_server_enabled"

    private let sessionManager = AXSessionManager.shared
    private let serverManager = AXServerManager.shared
    private let eventBus = AXEventBus.shared
    private let supervisorCalendarReminderScheduler: SupervisorCalendarReminderScheduler
    private static let automaticReconnectStartupWarmupSec: TimeInterval = 6.0
    private static let automaticRemoteConnectStartupDelaySec: TimeInterval = 1.5
    private static let remoteSkillsCompatibilityOverlayRefreshIntervalSec: TimeInterval = 30.0
    private static let hubRemotePrefsDoctorRefreshDebounceNs: UInt64 = 350_000_000
    private var hubReconnectLastAttemptAt: Date = .distantPast
    private var hubSetupAutofillLastAttemptAt: Date = .distantPast
    private var bridgeAlwaysOn: Bool = false
    private var bridgeEnsureInFlight: Bool = false
    private var bridgeEnsureLastAttemptAt: Date = .distantPast
    private var nextProjectFocusRequestNonce: Int = 0
    private var nextSupervisorFocusRequestNonce: Int = 0
    private var nextSettingsFocusRequestNonce: Int = 0
    private var nextHubSetupFocusRequestNonce: Int = 0
    private var nextSupervisorSettingsFocusRequestNonce: Int = 0
    private var nextModelSettingsFocusRequestNonce: Int = 0
    private var nextProjectDetailFocusRequestNonce: Int = 0
    private var nextProjectSettingsFocusRequestNonce: Int = 0
    private var nextProjectSnapshotRefreshAt: Date = .distantPast
    private var nextProjectRuntimeSurfaceOverrideRefreshAt: Date = .distantPast
    private var nextSkillsCompatibilityRefreshAt: Date = .distantPast
    private var nextUnifiedDoctorRefreshAt: Date = .distantPast
    private var nextRemoteSkillsCompatibilityOverlayRefreshAt: Date = .distantPast
    private var pairedSurfaceHeartbeatBaseDir: URL? = nil
    private var remoteSkillsCompatibilityOverlayInFlight: Bool = false
    private var lastRemoteSkillsCompatibilityOverlayProjectId: String? = nil
    private var startupAutomaticFirstPairAttemptedThisLaunch: Bool = false
    private var startupAutomaticFirstPairSmokeAttemptedThisLaunch: Bool = false
    private var startupAutomaticFirstPairRemoteShadowSmokeAttemptedThisLaunch: Bool = false
    private var hubNetworkMonitor: NWPathMonitor? = nil
    private let hubNetworkMonitorQueue = DispatchQueue(label: "com.xterminal.hub-network-monitor")
    private var lastHubNetworkPathFingerprint: HubNetworkPathFingerprint? = nil
    private var hubConnectivityIncidentSnapshot: XTHubConnectivityIncidentSnapshot? = nil
    private var hubRemotePrefsDoctorRefreshTask: Task<Void, Never>? = nil
    private var automaticReconnectStartupWarmupUntil: Date = .distantPast
    private var nextRemotePresenceRefreshAt: Date = .distantPast
    private var lastObservedModelAssignments: [AXRole: RoleProviderAssignment]

    convenience init() {
        let shouldPersistProjectRegistry = !Self.isRunningUnderTestProcess
        self.init(
            loadPersistedProjectRegistry: shouldPersistProjectRegistry,
            persistProjectRegistryChanges: shouldPersistProjectRegistry
        )
    }

    init(
        loadPersistedProjectRegistry: Bool,
        persistProjectRegistryChanges: Bool
    ) {
        let ss = SettingsStore()
        let calendarReminderScheduler = SupervisorCalendarReminderScheduler()
        settingsStore = ss
        llmRouter = LLMRouter(settingsStore: ss)
        supervisorCalendarReminderScheduler = calendarReminderScheduler
        lastObservedModelAssignments = Self.modelAssignmentMap(for: ss.settings)
        self.loadPersistedProjectRegistry = loadPersistedProjectRegistry
        self.persistProjectRegistryChanges = persistProjectRegistryChanges
        automaticReconnectStartupWarmupUntil = Date().addingTimeInterval(
            Self.automaticReconnectStartupWarmupSec
        )

        // Memory pipeline status (coarse/refine) for toolbar indicators.
        let nc = NotificationCenter.default
        registerNotificationObserver(
            center: nc,
            name: AXMemoryPipelineNotifications.coarseStart
        ) { [weak self] _ in
            Task { @MainActor in self?.memoryCoarseRunning = true }
        }
        registerNotificationObserver(
            center: nc,
            name: AXMemoryPipelineNotifications.coarseEnd
        ) { [weak self] _ in
            Task { @MainActor in self?.memoryCoarseRunning = false }
        }
        registerNotificationObserver(
            center: nc,
            name: AXMemoryPipelineNotifications.refineStart
        ) { [weak self] _ in
            Task { @MainActor in self?.memoryRefineRunning = true }
        }
        registerNotificationObserver(
            center: nc,
            name: AXMemoryPipelineNotifications.refineEnd
        ) { [weak self] _ in
            Task { @MainActor in self?.memoryRefineRunning = false }
        }
        observeModelAssignmentChanges()

        loadRegistry()
        bootstrapSelection()
        migrateSkillsIfNeeded()
        scheduleSkillScan()
        loadHubRemotePrefs()
        refreshSkillsCompatibilitySnapshot(force: true)
        refreshUnifiedDoctorReport(force: true)
        loadBridgePrefs()
        loadLocalServerPrefs()
        if SupervisorCalendarReminderScheduler.shouldAutoStartInCurrentProcess {
            supervisorCalendarReminderScheduler.bind(settingsStore: ss)
        }

        if !Self.isRunningUnderTestProcess {
            startHubConnectivityLifecycleObservers()
            startHubNetworkMonitor()

            // Auto-connect if Hub is already running.
            Task { @MainActor in
                await connectToHub(auto: true)
            }
            Task { @MainActor in
                await pollHubStatusLoop()
            }

            // Start local HTTP server only if enabled in settings.
            Task { @MainActor in
                await applyLocalServerPreference(isStartup: true)
            }
        }
    }

    static func makeForTesting() -> AppModel {
        AppModel(
            loadPersistedProjectRegistry: false,
            persistProjectRegistryChanges: false
        )
    }

    func waitForPendingSelectionWorkForTesting() async {
        if let selectionTask = projectSelectionTask {
            _ = await selectionTask.result
        }
        if let rootLoadTask = projectRootLoadTask {
            _ = await rootLoadTask.result
        }
    }

    deinit {
        projectRootLoadTask?.cancel()
        projectSelectionTask?.cancel()
        hubRemotePrefsDoctorRefreshTask?.cancel()
        for observation in notifTokens {
            observation.center.removeObserver(observation.token)
        }
        skillScanTimer?.invalidate()
        hubNetworkMonitor?.cancel()
    }

    private func registerNotificationObserver(
        center: NotificationCenter,
        name: Notification.Name,
        using block: @escaping @Sendable (Notification) -> Void
    ) {
        let token = center.addObserver(forName: name, object: nil, queue: .main, using: block)
        notifTokens.append(
            XTNotificationObservationToken(
                center: center,
                token: token
            )
        )
    }

    nonisolated static func shouldSuppressAutomaticReconnectDuringStartup(
        now: Date,
        warmupUntil: Date
    ) -> Bool {
        now < warmupUntil
    }

    nonisolated static func shouldSuppressAutomaticRemoteReconnect(
        hubRemoteLinking: Bool,
        startupSuppressed: Bool,
        activeRemoteGenerate: Bool
    ) -> Bool {
        hubRemoteLinking || startupSuppressed || activeRemoteGenerate
    }

    nonisolated static func automaticRemoteReconnectCandidateRoutes(
        internetHost: String
    ) -> [XTHubRouteCandidate] {
        HubAIClient.automaticRemoteReconnectCandidateRoutes(
            internetHost: internetHost
        )
    }

    nonisolated static func shouldConsumeHubInviteTokenAfterSuccessfulRemoteConnect(
        report: HubRemoteConnectReport?,
        inviteToken: String,
        internetHost: String,
        hasHubEnv: Bool
    ) -> Bool {
        guard let report, report.ok else { return false }
        guard hasHubEnv else { return false }
        guard !inviteToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }

        let hostClassification = XTHubRemoteAccessHostClassification.classify(internetHost)
        guard case .stableNamed = hostClassification.kind else { return false }
        return true
    }

    nonisolated static func shouldDeferAutomaticRemoteRouteHandoff(
        activeRemoteGenerate: Bool,
        remoteConnected: Bool,
        remoteRoute: HubRemoteRoute
    ) -> Bool {
        activeRemoteGenerate && (remoteConnected || remoteRoute != .none)
    }

    nonisolated static func shouldDeferBackgroundRemoteInventoryRefresh(
        activeRemoteGenerate: Bool
    ) -> Bool {
        activeRemoteGenerate
    }

    nonisolated static func backgroundHubPollInterval(
        activeRemoteGenerate: Bool,
        connected: Bool
    ) -> TimeInterval {
        let disconnectedInterval: TimeInterval = 5.0
        let connectedInterval: TimeInterval = 8.0
        let remoteGenerateInterval: TimeInterval = 12.0
        if activeRemoteGenerate {
            return remoteGenerateInterval
        }
        return connected ? connectedInterval : disconnectedInterval
    }

    private func shouldSuppressAutomaticReconnectDuringStartup(now: Date = Date()) -> Bool {
        Self.shouldSuppressAutomaticReconnectDuringStartup(
            now: now,
            warmupUntil: automaticReconnectStartupWarmupUntil
        )
    }

    private func startHubConnectivityLifecycleObservers() {
        registerNotificationObserver(
            center: NotificationCenter.default,
            name: NSApplication.didBecomeActiveNotification
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleHubConnectivityLifecycleTrigger(.appBecameActive)
            }
        }
        registerNotificationObserver(
            center: NSWorkspace.shared.notificationCenter,
            name: NSWorkspace.didWakeNotification
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleHubConnectivityLifecycleTrigger(.systemWoke)
            }
        }
    }

    func connectToHub(auto: Bool = false) async {
        let res = HubConnector.connect(ttl: 3.0)
        hubConnected = res.ok
        hubBaseDir = res.baseDir
        hubStatus = res.status
        hubLastError = res.ok ? nil : (res.error ?? (auto ? nil : "hub_not_running"))
        if res.ok {
            hubRemoteConnected = false
            hubRemoteRoute = .none
            hubRemotePaidAccessSnapshot = nil
            hubRemoteSummary = ""
            nextRemotePresenceRefreshAt = .distantPast
            await maybeRefreshRemotePresence(force: true)
            refreshSkillsCompatibilitySnapshot(force: true)
            refreshUnifiedDoctorReport(force: true)
            return
        }

        refreshSkillsCompatibilitySnapshot(force: true)
        refreshUnifiedDoctorReport(force: true)
        if auto {
            let startupDelayNs = UInt64(
                (Self.automaticRemoteConnectStartupDelaySec * 1_000_000_000.0).rounded()
            )
            try? await Task.sleep(nanoseconds: startupDelayNs)
            guard !Task.isCancelled else { return }
            let hasEnv = await HubPairingCoordinator.shared.hasHubEnv(stateDir: nil)
            let startupDisposition = Self.startupAutomaticConnectDisposition(
                hasHubEnv: hasEnv,
                internetHost: hubInternetHost,
                inviteToken: hubInviteToken,
                inviteAlias: hubInviteAlias,
                inviteInstanceID: hubInviteInstanceID
            )
            switch startupDisposition {
            case .none:
                return
            case .recoverExistingProfile(let allowBootstrap):
                _ = await runRemoteConnectFlow(
                    allowBootstrap: allowBootstrap,
                    showAlertOnFinish: false,
                    updateSetupProgress: true,
                    repairTrigger: .startupAutoConnect,
                    repairOwner: .xtRuntime,
                    candidateRoutes: Self.automaticRemoteReconnectCandidateRoutes(
                        internetHost: hubInternetHost
                    )
                )
            case .firstPairNearby:
                guard !startupAutomaticFirstPairAttemptedThisLaunch else { return }
                startupAutomaticFirstPairAttemptedThisLaunch = true
                try? await Task.sleep(nanoseconds: 700_000_000)
                let report = await runRemoteConnectFlow(
                    allowBootstrap: true,
                    showAlertOnFinish: false,
                    updateSetupProgress: true,
                    initialSummary: "searching nearby hub ...",
                    openHubSetupOnFailure: true,
                    repairTrigger: .startupAutoConnect,
                    repairOwner: .xtRuntime,
                    candidateRoutes: Self.automaticRemoteReconnectCandidateRoutes(
                        internetHost: hubInternetHost
                    )
                )
                if Self.shouldRunAutomaticFirstPairReconnectSmoke(after: report) {
                    _ = await runAutomaticFirstPairReconnectSmoke()
                }
            }
        } else {
            _ = await runHubOneClickSetup(showAlertOnFinish: true)
        }
    }

    func startHubOneClickSetup() {
        Task { @MainActor in
            await runHubOneClickSetup(showAlertOnFinish: true)
        }
    }

    func startHubReconnectOnly() {
        Task { @MainActor in
            await runRemoteConnectFlow(
                allowBootstrap: false,
                showAlertOnFinish: true,
                repairTrigger: .manualReconnect,
                repairOwner: .user
            )
        }
    }

    func runSupervisorVoiceSmokeDiagnostics() {
        guard !supervisorVoiceSmokeRunning else { return }

        let workspaceRoot: URL
        do {
            workspaceRoot = try supervisorVoiceSmokeDiagnosticsWorkspaceRoot()
        } catch {
            supervisorVoiceSmokeLastPassed = false
            supervisorVoiceSmokeStatusLine = "Supervisor 语音自检无法启动"
            supervisorVoiceSmokeDetailLine = "诊断工作区创建失败：\(error.localizedDescription)"
            return
        }

        let outputURL = workspaceRoot
            .appendingPathComponent(".axcoder/reports", isDirectory: true)
            .appendingPathComponent("xt_supervisor_voice_smoke.runtime.json")

        supervisorVoiceSmokeRunning = true
        supervisorVoiceSmokeLastPassed = nil
        supervisorVoiceSmokeReportURL = outputURL
        supervisorVoiceSmokeStatusLine = "Supervisor 语音自检运行中..."
        supervisorVoiceSmokeDetailLine = "工作区：\(workspaceRoot.path)"

        Task { @MainActor in
            let exitCode = await XTerminalGateSmokeRunner.runSupervisorVoiceSmokeCheck(
                workspaceRoot: workspaceRoot,
                outputURL: outputURL
            )
            finishSupervisorVoiceSmokeDiagnostics(exitCode: exitCode, outputURL: outputURL)
        }
    }

    var canOpenSupervisorVoiceSmokeReport: Bool {
        guard let url = effectiveSupervisorVoiceSmokeReportURL() else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    func openSupervisorVoiceSmokeReport() {
        guard canOpenSupervisorVoiceSmokeReport,
              let url = effectiveSupervisorVoiceSmokeReportURL() else { return }
        openURLInWorkspace(url)
    }

    func runHubOneClickSetup(showAlertOnFinish: Bool = false) async -> HubRemoteConnectReport? {
        guard let report = await runRemoteConnectFlow(
            allowBootstrap: true,
            showAlertOnFinish: false,
            updateSetupProgress: true,
            openHubSetupOnFailure: true,
            repairTrigger: .manualOneClickSetup,
            repairOwner: .user
        ) else {
            return nil
        }

        if Self.shouldRunFreshPairReconnectSmoke(after: report) {
            let smokeReport = await runFreshPairReconnectSmoke(
                source: .manualOneClickSetup,
                useStartupLaunchGuard: false,
                showAlertOnFinish: showAlertOnFinish,
                openHubSetupOnFailure: true
            )
            return smokeReport ?? report
        }

        if showAlertOnFinish {
            showHubRemoteConnectAlert(for: report)
        }
        return report
    }

    func runHubReconnectOnly(showAlertOnFinish: Bool = false) async -> HubRemoteConnectReport? {
        await runRemoteConnectFlow(
            allowBootstrap: false,
            showAlertOnFinish: showAlertOnFinish,
            repairTrigger: .manualReconnect,
            repairOwner: .user
        )
    }

    private func runAutomaticFirstPairReconnectSmoke() async -> HubRemoteConnectReport? {
        await runFreshPairReconnectSmoke(
            source: .startupAutomaticFirstPair,
            useStartupLaunchGuard: true,
            showAlertOnFinish: false,
            openHubSetupOnFailure: true
        )
    }

    private func runFreshPairReconnectSmoke(
        source: XTFreshPairReconnectSmokeSource,
        useStartupLaunchGuard: Bool,
        showAlertOnFinish: Bool,
        openHubSetupOnFailure: Bool
    ) async -> HubRemoteConnectReport? {
        if useStartupLaunchGuard {
            guard !startupAutomaticFirstPairSmokeAttemptedThisLaunch else { return nil }
            startupAutomaticFirstPairSmokeAttemptedThisLaunch = true
        }

        let startedAtMs = Int64(Date().timeIntervalSince1970 * 1000)
        hubFreshPairReconnectSmokeSnapshot = XTFreshPairReconnectSmokeSnapshot(
            source: source,
            status: .running,
            triggeredAtMs: startedAtMs,
            completedAtMs: 0,
            route: hubRemoteRoute,
            reasonCode: nil,
            summary: "verifying paired route ..."
        )
        hubRemoteSummary = "verifying paired route ..."
        refreshUnifiedDoctorReport(force: true)
        guard var report = await runRemoteConnectFlow(
            allowBootstrap: false,
            showAlertOnFinish: false,
            updateSetupProgress: false,
            openHubSetupOnFailure: openHubSetupOnFailure,
            repairTrigger: .freshPairReconnectSmoke,
            repairOwner: .xtRuntime,
            candidateRoutes: Self.automaticRemoteReconnectCandidateRoutes(
                internetHost: hubInternetHost
            )
        ) else {
            return nil
        }
        let completedAtMs = Int64(Date().timeIntervalSince1970 * 1000)
        if report.ok {
            report.summary = "first pair complete; cached route verified."
            hubRemoteSummary = report.summary
            hubSetupFailureCode = ""
            hubFreshPairReconnectSmokeSnapshot = XTFreshPairReconnectSmokeSnapshot(
                source: source,
                status: .succeeded,
                triggeredAtMs: startedAtMs,
                completedAtMs: completedAtMs,
                route: report.route,
                reasonCode: nil,
                summary: report.summary
            )
            scheduleFirstPairRemoteShadowReconnectSmokeIfNeeded(
                after: report,
                useStartupLaunchGuard: useStartupLaunchGuard
            )
        } else {
            hubSetupFailureCode = report.reasonCode ?? report.summary
            hubFreshPairReconnectSmokeSnapshot = XTFreshPairReconnectSmokeSnapshot(
                source: source,
                status: .failed,
                triggeredAtMs: startedAtMs,
                completedAtMs: completedAtMs,
                route: report.route,
                reasonCode: report.reasonCode,
                summary: report.summary
            )
        }
        hubConnectivityIncidentSnapshot = currentHubConnectivityIncidentSnapshot(
            trigger: .backgroundKeepalive,
            currentPath: lastHubNetworkPathFingerprint
        )
        refreshUnifiedDoctorReport(force: true)
        if showAlertOnFinish {
            showHubRemoteConnectAlert(for: report)
        }
        return report
    }

    private func scheduleFirstPairRemoteShadowReconnectSmokeIfNeeded(
        after report: HubRemoteConnectReport,
        useStartupLaunchGuard: Bool
    ) {
        let pairedRouteSetSnapshot = currentPairedRouteSetSnapshot()
        guard Self.shouldRunRemoteShadowReconnectSmoke(
            after: report,
            pairedRouteSetSnapshot: pairedRouteSetSnapshot,
            existingSnapshot: hubRemoteShadowReconnectSmokeSnapshot
        ) else {
            return
        }

        if report.route == .internet {
            let completedAtMs = Int64(Date().timeIntervalSince1970 * 1000)
            hubRemoteShadowReconnectSmokeSnapshot = XTRemoteShadowReconnectSmokeSnapshot(
                source: .cachedRemoteReconnectEvidence,
                status: .succeeded,
                triggeredAtMs: completedAtMs,
                completedAtMs: completedAtMs,
                route: .internet,
                reasonCode: nil,
                summary: "stable remote route was already verified by cached reconnect smoke."
            )
            hubConnectivityIncidentSnapshot = currentHubConnectivityIncidentSnapshot(
                trigger: .backgroundKeepalive,
                currentPath: lastHubNetworkPathFingerprint,
                pairedRouteSetSnapshot: currentPairedRouteSetSnapshot(),
                updatedAt: Date()
            )
            refreshUnifiedDoctorReport(force: true)
            return
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.runRemoteShadowReconnectSmoke(
                useStartupLaunchGuard: useStartupLaunchGuard
            )
        }
    }

    private func runRemoteShadowReconnectSmoke(
        useStartupLaunchGuard: Bool
    ) async {
        if useStartupLaunchGuard {
            guard !startupAutomaticFirstPairRemoteShadowSmokeAttemptedThisLaunch else { return }
            startupAutomaticFirstPairRemoteShadowSmokeAttemptedThisLaunch = true
        }

        guard currentPairedRouteSetSnapshot().stableRemoteRoute != nil else {
            return
        }
        guard hubRemoteShadowReconnectSmokeSnapshot?.status != .running else {
            return
        }

        let startedAtMs = Int64(Date().timeIntervalSince1970 * 1000)
        hubRemoteShadowReconnectSmokeSnapshot = XTRemoteShadowReconnectSmokeSnapshot(
            source: .dedicatedStableRemoteProbe,
            status: .running,
            triggeredAtMs: startedAtMs,
            completedAtMs: 0,
            route: .internet,
            reasonCode: nil,
            summary: "verifying stable remote route shadow path ..."
        )
        hubConnectivityIncidentSnapshot = currentHubConnectivityIncidentSnapshot(
            trigger: .backgroundKeepalive,
            currentPath: lastHubNetworkPathFingerprint,
            pairedRouteSetSnapshot: currentPairedRouteSetSnapshot(),
            updatedAt: Date()
        )
        refreshUnifiedDoctorReport(force: true)

        guard let report = await runRemoteConnectFlow(
            allowBootstrap: false,
            showAlertOnFinish: false,
            updateSetupProgress: false,
            openHubSetupOnFailure: false,
            repairTrigger: .remoteShadowReconnectSmoke,
            repairOwner: .xtRuntime,
            preferredRoute: .stableNamedRemote,
            candidateRoutes: [.stableNamedRemote]
        ) else {
            return
        }

        let completedAtMs = Int64(Date().timeIntervalSince1970 * 1000)
        hubRemoteShadowReconnectSmokeSnapshot = XTRemoteShadowReconnectSmokeSnapshot(
            source: .dedicatedStableRemoteProbe,
            status: report.ok ? .succeeded : .failed,
            triggeredAtMs: startedAtMs,
            completedAtMs: completedAtMs,
            route: report.ok ? report.route : .internet,
            reasonCode: report.reasonCode,
            summary: report.ok
                ? "stable remote route shadow verification passed."
                : (report.summary.isEmpty ? "stable remote route shadow verification failed." : report.summary)
        )
        hubConnectivityIncidentSnapshot = currentHubConnectivityIncidentSnapshot(
            trigger: .backgroundKeepalive,
            currentPath: lastHubNetworkPathFingerprint,
            pairedRouteSetSnapshot: currentPairedRouteSetSnapshot(),
            updatedAt: Date()
        )
        refreshUnifiedDoctorReport(force: true)
    }

    func saveHubRemotePrefsNow(markEndpointOverride: Bool = false) {
        if markEndpointOverride {
            setHubRemoteEndpointOverridePending(true)
        }
        saveHubRemotePrefs()
        scheduleHubRemotePrefsDoctorRefresh()
    }

    func setHubPairingPortFromUser(_ value: Int) {
        hubPairingPort = max(1, min(65_535, value))
        saveHubRemotePrefsNow(markEndpointOverride: true)
    }

    func setHubGrpcPortFromUser(_ value: Int) {
        hubGrpcPort = max(1, min(65_535, value))
        saveHubRemotePrefsNow(markEndpointOverride: true)
    }

    func setHubInternetHostFromUser(_ value: String) {
        hubInternetHost = value
        saveHubRemotePrefsNow(markEndpointOverride: true)
    }

    private func scheduleHubRemotePrefsDoctorRefresh() {
        hubRemotePrefsDoctorRefreshTask?.cancel()
        hubRemotePrefsDoctorRefreshTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: Self.hubRemotePrefsDoctorRefreshDebounceNs)
            guard !Task.isCancelled else { return }
            self?.refreshUnifiedDoctorReport(force: true)
        }
    }

    private func finishSupervisorVoiceSmokeDiagnostics(exitCode: Int, outputURL: URL) {
        supervisorVoiceSmokeRunning = false
        supervisorVoiceSmokeReportURL = outputURL

        do {
            let report = try XTSupervisorVoiceSmokeReportSummary.load(from: outputURL)
            supervisorVoiceSmokeReportSummary = report
            let passed = exitCode == 0 && report.isPassing
            let route = (report.voiceRoute ?? "unknown")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            supervisorVoiceSmokeLastPassed = passed
            if let error = report.normalizedError {
                supervisorVoiceSmokeStatusLine = "Supervisor 语音自检失败 · \(error)"
            } else {
                supervisorVoiceSmokeStatusLine = "\(passed ? "已通过" : "未通过") · \(report.passedCheckCount)/\(report.checkCount) checks · route=\(route.isEmpty ? "unknown" : route)"
            }
            if passed {
                supervisorVoiceSmokeDetailLine = "报告：\(outputURL.path)"
            } else if let failedPhase = report.firstFailedPhase,
                      let failureLine = report.failureSummaryLine(for: failedPhase) {
                supervisorVoiceSmokeDetailLine = "\(failureLine) 报告：\(outputURL.path)"
            } else {
                supervisorVoiceSmokeDetailLine = "报告：\(outputURL.path)"
            }
        } catch {
            supervisorVoiceSmokeReportSummary = nil
            supervisorVoiceSmokeLastPassed = false
            supervisorVoiceSmokeStatusLine = exitCode == 0
                ? "Supervisor 语音自检完成，但报告不可读"
                : "Supervisor 语音自检失败"
            supervisorVoiceSmokeDetailLine = "报告读取失败：\(error.localizedDescription)"
        }
        refreshUnifiedDoctorReport(force: true)
    }

    private func supervisorVoiceSmokeDiagnosticsWorkspaceRoot() throws -> URL {
        let supportBase = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
        let workspaceRoot = supportBase
            .appendingPathComponent("X-Terminal", isDirectory: true)
            .appendingPathComponent("diagnostics", isDirectory: true)
            .appendingPathComponent("voice-smoke", isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceRoot, withIntermediateDirectories: true)
        return workspaceRoot
    }

    private func loadSupervisorVoiceSmokeReportSummary() -> XTSupervisorVoiceSmokeReportSummary? {
        let defaultReportURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("X-Terminal", isDirectory: true)
            .appendingPathComponent("diagnostics", isDirectory: true)
            .appendingPathComponent("voice-smoke", isDirectory: true)
            .appendingPathComponent(".axcoder/reports", isDirectory: true)
            .appendingPathComponent("xt_supervisor_voice_smoke.runtime.json")
        let candidates = [supervisorVoiceSmokeReportURL, defaultReportURL].compactMap { $0 }
        for candidate in candidates {
            guard FileManager.default.fileExists(atPath: candidate.path) else { continue }
            if let report = try? XTSupervisorVoiceSmokeReportSummary.load(from: candidate) {
                supervisorVoiceSmokeReportURL = candidate
                supervisorVoiceSmokeReportSummary = report
                if !supervisorVoiceSmokeRunning && supervisorVoiceSmokeStatusLine.isEmpty {
                    supervisorVoiceSmokeLastPassed = report.isPassing
                    let route = (report.voiceRoute ?? "unknown").trimmingCharacters(in: .whitespacesAndNewlines)
                    supervisorVoiceSmokeStatusLine = "\(report.isPassing ? "已通过" : "最近一次未通过") · \(report.passedCheckCount)/\(report.checkCount) checks · route=\(route.isEmpty ? "unknown" : route)"
                    supervisorVoiceSmokeDetailLine = "报告：\(candidate.path)"
                }
                return report
            }
        }
        return supervisorVoiceSmokeReportSummary
    }

    func applyHubPairingInvitePrefill(_ prefill: XTHubPairingInvitePrefill) {
        var endpointChanged = false
        if let pairingPort = prefill.pairingPort {
            hubPairingPort = max(1, min(65_535, pairingPort))
            endpointChanged = true
        }
        if let grpcPort = prefill.grpcPort {
            hubGrpcPort = max(1, min(65_535, grpcPort))
            endpointChanged = true
        }
        if let internetHost = normalizedDeepLinkToken(prefill.internetHost) {
            hubInternetHost = internetHost
            endpointChanged = true
        }
        if let inviteToken = normalizedDeepLinkToken(prefill.inviteToken) {
            hubInviteToken = inviteToken
        }
        if let inviteAlias = normalizedDeepLinkToken(prefill.hubAlias) {
            hubInviteAlias = inviteAlias
        }
        if let inviteInstanceID = normalizedDeepLinkToken(prefill.hubInstanceID) {
            hubInviteInstanceID = inviteInstanceID
        }
        saveHubRemotePrefsNow(markEndpointOverride: endpointChanged)
    }

    func setLocalServerEnabled(_ enabled: Bool) {
        localServerEnabled = enabled
        saveLocalServerPrefs()
        Task { @MainActor in
            await applyLocalServerPreference(isStartup: false)
        }
    }

    func restartLocalServer() {
        Task { @MainActor in
            await startLocalServer(forceRestart: true)
        }
    }

    func autoDetectHubPorts() {
        Task { @MainActor in
            await autoDetectHubPortsNow()
        }
    }

    func autoFillHubSetupPathAndPorts() {
        Task { @MainActor in
            await autoFillHubSetupPathAndPortsNow()
        }
    }

    func maybeAutoFillHubSetupPathAndPorts(force: Bool = false) {
        Task { @MainActor in
            await maybeAutoFillHubSetupPathAndPortsNow(force: force)
        }
    }

    func selectDiscoveredHubCandidate(_ candidate: HubDiscoveredHubCandidateSummary) {
        Task { @MainActor in
            await applySelectedHubCandidateNow(candidate)
        }
    }

    func resetPairingStateAndOneClickSetup() {
        Task { @MainActor in
            await resetPairingAndSetupNow()
        }
    }

    func openProjectPicker() {
        let panel = NSOpenPanel()
        panel.title = "Choose Project Folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false

        presentOpenPanel(panel) { [weak self] urls in
            guard let self, let url = urls.first else { return }
            self.addProject(url)
        }
    }

    func openSkillEditor() {
        let panel = NSOpenPanel()
        panel.title = "Choose Skill Folder or SKILL.md"
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        if let base = resolveSkillsDirectory() {
            panel.directoryURL = base
        }

        presentOpenPanel(panel) { [weak self] urls in
            guard let self, let url = urls.first else { return }
            self.rememberSkillsDirectory(for: url)
            if url.hasDirectoryPath {
                let skillMD = url.appendingPathComponent("SKILL.md")
                if FileManager.default.fileExists(atPath: skillMD.path) {
                    self.openURLInWorkspace(skillMD)
                } else {
                    self.openURLInWorkspace(url)
                }
            } else {
                self.openURLInWorkspace(url)
            }
        }
    }

    func openCurrentSkillsIndex() {
        let selectedProject = selectedProjectId == AXProjectRegistry.globalHomeId ? nil : selectedProjectId
        let projectName = selectedProject.flatMap { registry.project(for: $0)?.displayName }
        guard let skillsDir = resolveSkillsDirectory() else {
            showAlert(title: "Skills Index", message: "Skills directory not configured.")
            return
        }

        let targetURL: URL?
        if let selectedProject {
            targetURL = AXSkillsLibrary.projectSkillsIndexURLIfExists(
                projectId: selectedProject,
                projectName: projectName,
                skillsDir: skillsDir
            )
        } else {
            targetURL = AXSkillsLibrary.globalSkillsIndexURLIfExists(skillsDir: skillsDir)
        }

        guard let targetURL else {
            let scope = selectedProject == nil ? "global" : "project"
            showAlert(title: "Skills Index", message: "No \(scope) skills index found yet.")
            return
        }
        openURLInWorkspace(targetURL)
    }

    func openWorkspaceURL(_ url: URL?) {
        guard let url else { return }
        openURLInWorkspace(url)
    }

    func presentSkillLibraryAlert(title: String, message: String) {
        showAlert(title: title, message: message)
    }

    func canPerformSkillGovernanceSurfaceAction(
        _ action: String,
        for entry: AXSkillGovernanceSurfaceEntry
    ) -> Bool {
        switch normalizedSkillGovernanceSurfaceAction(action) {
        case "install_baseline":
            return hubInteractive && !baselineInstallBusy
        case "pin_package_project":
            return hubInteractive && selectedProjectBaselineInstallScope() != nil
        case "pin_package_global":
            return hubInteractive
        case "request_local_approval", "open_project_settings":
            return selectedProjectBaselineInstallScope() != nil
        case "request_hub_grant", "open_trusted_automation_doctor", "reconnect_hub",
             "open_skill_governance_surface", "refresh_resolved_cache", "retry_dispatch":
            return true
        default:
            return false
        }
    }

    func performSkillGovernanceSurfaceAction(
        _ action: String,
        for entry: AXSkillGovernanceSurfaceEntry
    ) {
        let normalizedAction = normalizedSkillGovernanceSurfaceAction(action)
        guard !normalizedAction.isEmpty else { return }

        switch normalizedAction {
        case "install_baseline":
            let scope = selectedProjectBaselineInstallScope() ?? .global
            let target = scope.hubScope
            skillGovernanceActionStatusLine = "skill_governance_action=install_baseline skill=\(entry.skillID) target=\(target)"
            if let override = baselineInstallActionOverrideForTesting {
                override(scope)
                return
            }
            if selectedProjectBaselineInstallScope() != nil {
                installDefaultAgentBaselineForCurrentProject()
            } else {
                installDefaultAgentBaselineGlobally()
            }
        case "pin_package_project":
            guard let scope = selectedProjectBaselineInstallScope() else {
                showAlert(
                    title: "Pin Governed Skill",
                    message: "Select a project first before pinning \(governanceSurfaceSubject(entry)) to project scope."
                )
                return
            }
            Task { @MainActor [weak self] in
                await self?.pinGovernedSkillFromGovernanceSurface(entry, scope: scope)
            }
        case "pin_package_global":
            Task { @MainActor [weak self] in
                await self?.pinGovernedSkillFromGovernanceSurface(entry, scope: .global)
            }
        case "refresh_resolved_cache":
            skillGovernanceActionStatusLine = "skill_governance_action=refresh skill=\(entry.skillID) status=running"
            recheckOfficialSkills(reason: "skill_governance_surface_refresh")
            skillGovernanceActionStatusLine = officialSkillsRecheckStatusLine.isEmpty
                ? "skill_governance_action=refresh skill=\(entry.skillID) status=done"
                : officialSkillsRecheckStatusLine
        case "retry_dispatch":
            skillGovernanceActionStatusLine = "skill_governance_action=retry_dispatch skill=\(entry.skillID) status=rechecking"
            recheckOfficialSkills(reason: "skill_governance_retry_dispatch")
            openSkillGovernanceSurface(
                for: entry,
                title: "重查技能执行状态",
                detail: governanceSurfaceDetail(
                    entry,
                    fallback: "已重查当前 governed skill truth；如果仍然 blocked，请继续沿当前治理面处理。"
                )
            )
        case "request_local_approval":
            guard let projectScope = selectedProjectBaselineInstallScope() else {
                showAlert(
                    title: "Handle Local Approval",
                    message: "Select a project first before handling local approval for \(governanceSurfaceSubject(entry))."
                )
                return
            }
            skillGovernanceActionStatusLine = "skill_governance_action=request_local_approval skill=\(entry.skillID) scope=\(projectScope.hubScope)"
            requestProjectSettingsFocus(
                projectId: projectScope.projectId,
                destination: .overview,
                title: "处理本地技能审批",
                detail: governanceSurfaceDetail(
                    entry,
                    fallback: "查看当前项目的技能治理概况，并处理待本地确认的技能动作。"
                )
            )
        case "open_project_settings":
            guard let projectScope = selectedProjectBaselineInstallScope() else {
                showAlert(
                    title: "Open Project Settings",
                    message: "No project is currently selected. Open a project first to inspect governed skill settings."
                )
                return
            }
            skillGovernanceActionStatusLine = "skill_governance_action=open_project_settings skill=\(entry.skillID) scope=\(projectScope.hubScope)"
            requestProjectSettingsFocus(
                projectId: projectScope.projectId,
                destination: .overview,
                title: "技能治理总览",
                detail: governanceSurfaceDetail(
                    entry,
                    fallback: "查看当前项目的 governed skill profiles / readiness / blockers。"
                )
            )
        case "open_skill_governance_surface":
            skillGovernanceActionStatusLine = "skill_governance_action=open_surface skill=\(entry.skillID)"
            openSkillGovernanceSurface(
                for: entry,
                title: "技能治理明细",
                detail: governanceSurfaceDetail(
                    entry,
                    fallback: "查看当前 governed skill 的 discover / install / request / run 真相。"
                )
            )
        case "request_hub_grant":
            skillGovernanceActionStatusLine = "skill_governance_action=request_hub_grant skill=\(entry.skillID)"
            openGovernanceRouteURL(
                XTDeepLinkURLBuilder.hubSetupURL(
                    sectionId: "troubleshoot",
                    title: "处理技能 Hub Grant",
                    detail: governanceSurfaceDetail(
                        entry,
                        fallback: "打开 Hub Troubleshoot，优先确认缺少的 Hub grant / pairing / policy 条件。"
                    )
                )
            )
        case "open_trusted_automation_doctor":
            skillGovernanceActionStatusLine = "skill_governance_action=open_trusted_automation_doctor skill=\(entry.skillID)"
            openGovernanceRouteURL(
                XTDeepLinkURLBuilder.settingsURL(
                    sectionId: "diagnostics",
                    title: "Trusted Automation Doctor",
                    detail: governanceSurfaceDetail(
                        entry,
                        fallback: "打开 XT Diagnostics，检查 trusted automation readiness 与本地权限条件。"
                    )
                )
            )
        case "reconnect_hub":
            skillGovernanceActionStatusLine = "skill_governance_action=reconnect_hub skill=\(entry.skillID)"
            openGovernanceRouteURL(
                XTDeepLinkURLBuilder.hubSetupURL(
                    sectionId: "pair_progress",
                    title: "Reconnect Hub",
                    detail: governanceSurfaceDetail(
                        entry,
                        fallback: "打开 Hub Setup 并重查当前配对 / 远端可达性。"
                    )
                )
            )
        default:
            showAlert(
                title: "Skill Governance Action",
                message: "Unsupported unblock action: \(normalizedAction)"
            )
        }
    }

    func createLocalSkillManifest(at folderURL: URL) {
        let standardized = folderURL.standardizedFileURL
        rememberSkillsDirectory(for: standardized)

        guard FileManager.default.fileExists(atPath: standardized.path) else {
            showAlert(
                title: "Create skill.json",
                message: "Skill folder no longer exists: \(standardized.path)"
            )
            return
        }

        let manifestURL = standardized.appendingPathComponent("skill.json")
        if FileManager.default.fileExists(atPath: manifestURL.path) {
            openURLInWorkspace(manifestURL)
            showAlert(
                title: "Create skill.json",
                message: "skill.json already exists for \(standardized.lastPathComponent)\n\n\(manifestURL.path)"
            )
            return
        }

        do {
            let manifestJSON = try defaultLocalSkillManifestJSON(for: standardized)
            try manifestJSON.write(to: manifestURL, atomically: true, encoding: .utf8)
            refreshSkillsCompatibilitySnapshot(force: true)
            openURLInWorkspace(manifestURL)
            showAlert(
                title: "Create skill.json",
                message: "Created minimal ABI-compatible manifest for \(standardized.lastPathComponent)\n\n\(manifestURL.path)"
            )
        } catch {
            showAlert(
                title: "Create skill.json",
                message: "Failed to create skill.json: \(error.localizedDescription)"
            )
        }
    }

    func renameLocalSkill(at folderURL: URL) {
        let standardized = folderURL.standardizedFileURL
        rememberSkillsDirectory(for: standardized)

        guard FileManager.default.fileExists(atPath: standardized.path) else {
            showAlert(
                title: "Rename Skill Folder",
                message: "Skill folder no longer exists: \(standardized.path)"
            )
            return
        }

        let title = "Rename Skill Folder"
        let message = "Rename local skill folder for \"\(standardized.lastPathComponent)\".\n\nThis changes the folder name only. Existing skill_id / manifest identity is left untouched."
        guard let requestedName = promptForSkillRename(
            title: title,
            message: message,
            initialValue: standardized.lastPathComponent
        ) else {
            return
        }

        let sanitizedName = sanitizePathComponent(requestedName)
        guard !sanitizedName.isEmpty else {
            showAlert(
                title: title,
                message: "Folder name cannot be empty."
            )
            return
        }

        guard sanitizedName != standardized.lastPathComponent else {
            return
        }

        let destination = standardized.deletingLastPathComponent().appendingPathComponent(sanitizedName, isDirectory: true)
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            showAlert(
                title: title,
                message: "A skill folder named \"\(sanitizedName)\" already exists.\n\n\(destination.path)"
            )
            return
        }

        do {
            try FileManager.default.moveItem(at: standardized, to: destination)
            if lastImportedAgentSkillDirectory?.standardizedFileURL == standardized {
                lastImportedAgentSkillDirectory = destination
                lastImportedAgentSkillName = sanitizedName
            }
            refreshSkillsCompatibilitySnapshot(force: true)
            let skillMarkdownURL = destination.appendingPathComponent("SKILL.md")
            if FileManager.default.fileExists(atPath: skillMarkdownURL.path) {
                openURLInWorkspace(skillMarkdownURL)
            } else {
                openURLInWorkspace(destination)
            }
            showAlert(
                title: title,
                message: "Renamed \(standardized.lastPathComponent) -> \(sanitizedName)\n\n\(destination.path)"
            )
        } catch {
            showAlert(
                title: title,
                message: "Failed to rename skill folder: \(error.localizedDescription)"
            )
        }
    }

    func duplicateLocalSkill(at folderURL: URL) {
        let standardized = folderURL.standardizedFileURL
        rememberSkillsDirectory(for: standardized)

        guard FileManager.default.fileExists(atPath: standardized.path) else {
            showAlert(
                title: "Duplicate Skill",
                message: "Skill folder no longer exists: \(standardized.path)"
            )
            return
        }

        let destination = uniqueDuplicatedSkillURL(for: standardized)
        do {
            try FileManager.default.copyItem(at: standardized, to: destination)
            refreshSkillsCompatibilitySnapshot(force: true)
            let duplicatedSkillMarkdown = destination.appendingPathComponent("SKILL.md")
            if FileManager.default.fileExists(atPath: duplicatedSkillMarkdown.path) {
                openURLInWorkspace(duplicatedSkillMarkdown)
            } else {
                openURLInWorkspace(destination)
            }
            showAlert(
                title: "Duplicate Skill",
                message: "Created \(destination.lastPathComponent)\n\n\(destination.path)"
            )
        } catch {
            showAlert(
                title: "Duplicate Skill",
                message: "Failed to duplicate skill: \(error.localizedDescription)"
            )
        }
    }

    func removeLocalSkill(at folderURL: URL) {
        let standardized = folderURL.standardizedFileURL
        rememberSkillsDirectory(for: standardized)

        guard FileManager.default.fileExists(atPath: standardized.path) else {
            showAlert(
                title: "Remove Skill",
                message: "Skill folder no longer exists: \(standardized.path)"
            )
            return
        }

        guard confirmRemoveSkill(name: standardized.lastPathComponent, path: standardized.path) else {
            return
        }

        do {
            try FileManager.default.removeItem(at: standardized)
            if lastImportedAgentSkillDirectory?.standardizedFileURL == standardized {
                lastImportedAgentSkillDirectory = nil
                lastImportedAgentSkillName = ""
                lastImportedAgentSkillStage = nil
                lastImportedAgentSkillStatusLine = ""
            }
            refreshSkillsCompatibilitySnapshot(force: true)
            showAlert(
                title: "Remove Skill",
                message: "Removed \(standardized.lastPathComponent)\n\n\(standardized.path)"
            )
        } catch {
            showAlert(
                title: "Remove Skill",
                message: "Failed to remove skill: \(error.localizedDescription)"
            )
        }
    }

    func openCurrentProjectXTerminalFolder() {
        openCurrentProjectArtifact { $0.xterminalDir }
    }

    func openCurrentProjectMemoryMarkdown() {
        openCurrentProjectArtifact { $0.memoryMarkdownURL }
    }

    func openCurrentProjectMemoryJSON() {
        openCurrentProjectArtifact { $0.memoryJSONURL }
    }

    func openCurrentProjectConfig() {
        openCurrentProjectArtifact { $0.configURL }
    }

    func openCurrentProjectRawLog() {
        openCurrentProjectArtifact { $0.rawLogURL }
    }

    func importSkills() {
        let panel = NSOpenPanel()
        panel.title = "Import Skills or Packages"
        panel.prompt = "Import"
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        if let base = ensureSkillsDirectory() {
            panel.directoryURL = base
        }

        presentOpenPanel(panel) { [weak self] selectedURLs in
            guard let self else { return }
            guard let base = self.ensureSkillsDirectory() else { return }
            self.rememberSkillsDirectory(for: base)
            Task { @MainActor in
                var imported = 0
                var skipped = 0
                var stageSummaries: [String] = []
                for url in selectedURLs {
                    let result = await self.importSkill(from: url, to: base)
                    if result.imported {
                        imported += 1
                    } else {
                        skipped += 1
                    }
                    if let stageSummary = result.stageSummary {
                        stageSummaries.append(stageSummary)
                    }
                }
                var lines = ["Imported \(imported), skipped \(skipped)."]
                if !stageSummaries.isEmpty {
                    lines.append("")
                    lines.append(contentsOf: stageSummaries)
                }
                if imported > 0 || skipped > 0 {
                    self.showAlert(
                        title: "Import Skills",
                        message: lines.joined(separator: "\n")
                    )
                }
                self.refreshSkillsCompatibilitySnapshot(force: true)
            }
        }
    }

    func selectProject(_ projectId: String) {
        selectedProjectId = projectId
    }

    func removeProject(_ projectId: String) {
        var reg = registry
        let removed = reg.projects.first(where: { $0.projectId == projectId })
        reg = AXProjectRegistryStore.removeProject(reg, projectId: projectId)
        registry = reg
        if persistProjectRegistryChanges {
            AXProjectRegistryStore.save(reg)
        }
        if let removed {
            eventBus.publish(.projectRemoved(removed))
        }
        chatSessions[projectId] = nil
        if let term = terminalSessions[projectId] {
            term.stop()
        }
        terminalSessions[projectId] = nil
        paneByProjectId[projectId] = nil
        if selectedProjectId == projectId {
            selectedProjectId = reg.globalHomeVisible ? AXProjectRegistry.globalHomeId : nil
        }
    }

    func session(for ctx: AXProjectContext) -> ChatSessionModel {
        let pid = AXProjectRegistryStore.projectId(forRoot: ctx.root)
        _ = sessionManager.ensurePrimarySession(
            projectId: pid,
            title: ctx.displayName(registry: registry),
            directory: ctx.root.standardizedFileURL.path
        )
        if let s = chatSessions[pid] { return s }
        let s = ChatSessionModel()
        chatSessions[pid] = s
        return s
    }

    func terminalSession(for ctx: AXProjectContext) -> TerminalSessionModel {
        let pid = AXProjectRegistryStore.projectId(forRoot: ctx.root)
        if let s = terminalSessions[pid] { return s }
        let s = TerminalSessionModel(root: ctx.root)
        terminalSessions[pid] = s
        return s
    }

    func pane(for projectId: String) -> AXProjectPane {
        paneByProjectId[projectId] ?? .chat
    }

    func setPane(_ pane: AXProjectPane, for projectId: String) {
        paneByProjectId[projectId] = pane
    }

    func projectContext(for projectId: String) -> AXProjectContext? {
        guard let entry = registry.projects.first(where: { $0.projectId == projectId }) else { return nil }
        let url = URL(fileURLWithPath: entry.rootPath, isDirectory: true)
        return AXProjectContext(root: url)
    }

    func projectConfigSnapshot(for ctx: AXProjectContext) -> AXProjectConfig? {
        if isCurrentProjectContext(ctx), let projectConfig {
            return projectConfig
        }
        return try? AXProjectStore.loadOrCreateConfig(for: ctx)
    }

    func projectConfigSnapshot(for projectId: String) -> AXProjectConfig? {
        guard let ctx = projectContext(for: projectId) else { return nil }
        return projectConfigSnapshot(for: ctx)
    }

    func sessionForProjectId(_ projectId: String) -> ChatSessionModel? {
        guard let ctx = projectContext(for: projectId) else { return nil }
        return session(for: ctx)
    }

    func persistSessionSummariesForLifecycle(reason: String) {
        for ctx in activeProjectContextsForSessionSummary() {
            _ = AXMemoryLifecycleStore.writeSessionSummaryCapsule(ctx: ctx, reason: reason)
        }
    }

    func sendFromHome(projectId: String, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let ctx = projectContext(for: projectId) else { return }
        let s = session(for: ctx)
        s.ensureLoaded(ctx: ctx, limit: 200)
        let mem = try? AXProjectStore.loadOrCreateMemory(for: ctx)
        let cfg = try? AXProjectStore.loadOrCreateConfig(for: ctx)
        s.draft = trimmed
        s.send(ctx: ctx, memory: mem, config: cfg, router: llmRouter)
    }

    func presentResumeBrief(projectId: String) {
        guard let ctx = projectContext(for: projectId) else { return }
        if let latest = sessionSummaryPresentation(projectId: projectId) {
            resumeReminderAcknowledgedSummaryMsByProjectId[projectId] = latest.createdAtMs
        }
        let s = session(for: ctx)
        s.presentProjectResumeBrief(ctx: ctx)
        setPane(.chat, for: projectId)
        selectProject(projectId)
    }

    func sessionSummaryPresentation(projectId: String) -> AXSessionSummaryCapsulePresentation? {
        guard let ctx = projectContext(for: projectId) else { return nil }
        return AXSessionSummaryCapsulePresentation.load(for: ctx)
    }

    func resumeReminderPresentation(projectId: String) -> AXSessionSummaryCapsulePresentation? {
        guard let latest = sessionSummaryPresentation(projectId: projectId) else {
            return nil
        }
        let acknowledgedAt = resumeReminderAcknowledgedSummaryMsByProjectId[projectId] ?? 0
        guard latest.createdAtMs > acknowledgedAt else {
            return nil
        }
        return latest
    }

    func latestResumeReminderProject() -> AXResumeReminderProjectPresentation? {
        latestSessionSummaryProject(using: resumeReminderPresentation)
    }

    func latestSessionSummaryProject() -> AXResumeReminderProjectPresentation? {
        latestSessionSummaryProject(using: sessionSummaryPresentation)
    }

    func preferredResumeProject() -> AXResumeReminderProjectPresentation? {
        if let selected = selectedProjectResumeProject() {
            return selected
        }
        return latestResumeReminderProject() ?? latestSessionSummaryProject()
    }

    func presentPreferredResumeBrief() {
        guard let target = preferredResumeProject() else { return }
        presentResumeBrief(projectId: target.projectId)
    }

    var canPresentPreferredResumeBrief: Bool {
        preferredResumeProject() != nil
    }

    var preferredResumeCommandTitle: String {
        guard let target = preferredResumeProject() else {
            return "接上次进度"
        }
        return "接上次进度（\(target.projectDisplayName)）"
    }

    func dismissResumeReminder(projectId: String) {
        guard let latest = resumeReminderPresentation(projectId: projectId) else { return }
        resumeReminderAcknowledgedSummaryMsByProjectId[projectId] = latest.createdAtMs
    }

    func requestSupervisorGrantFocus(
        projectId: String?,
        grantRequestId: String?,
        capability: String?
    ) {
        let normalizedProjectId = normalizedDeepLinkToken(projectId)
        let normalizedGrantId = normalizedDeepLinkToken(grantRequestId)
        let normalizedCapability = normalizedDeepLinkToken(capability)
        guard normalizedGrantId != nil || normalizedCapability != nil else { return }

        nextSupervisorFocusRequestNonce += 1
        supervisorFocusRequest = AXSupervisorFocusRequest(
            nonce: nextSupervisorFocusRequestNonce,
            projectId: normalizedProjectId,
            subject: .grant(
                grantRequestId: normalizedGrantId,
                capability: normalizedCapability
            )
        )
    }

    func requestSupervisorBoardFocus(
        anchorID: String?,
        projectId: String? = nil
    ) {
        let normalizedProjectId = normalizedDeepLinkToken(projectId)
        let normalizedAnchorID = normalizedDeepLinkToken(anchorID)
        guard let normalizedAnchorID else { return }

        nextSupervisorFocusRequestNonce += 1
        supervisorFocusRequest = AXSupervisorFocusRequest(
            nonce: nextSupervisorFocusRequestNonce,
            projectId: normalizedProjectId,
            subject: .board(anchorID: normalizedAnchorID)
        )
    }

    func requestSupervisorApprovalFocus(
        projectId: String?,
        requestId: String?
    ) {
        let normalizedProjectId = normalizedDeepLinkToken(projectId)
        let normalizedRequestId = normalizedDeepLinkToken(requestId)
        guard let normalizedRequestId else { return }

        nextSupervisorFocusRequestNonce += 1
        supervisorFocusRequest = AXSupervisorFocusRequest(
            nonce: nextSupervisorFocusRequestNonce,
            projectId: normalizedProjectId,
            subject: .approval(requestId: normalizedRequestId)
        )
    }

    func requestSupervisorCandidateReviewFocus(
        projectId: String?,
        requestId: String?
    ) {
        let normalizedProjectId = normalizedDeepLinkToken(projectId)
        let normalizedRequestId = normalizedDeepLinkToken(requestId)
        guard let normalizedRequestId else { return }

        nextSupervisorFocusRequestNonce += 1
        supervisorFocusRequest = AXSupervisorFocusRequest(
            nonce: nextSupervisorFocusRequestNonce,
            projectId: normalizedProjectId,
            subject: .candidateReview(requestId: normalizedRequestId)
        )
    }

    func requestSupervisorSkillRecordFocus(
        projectId: String?,
        requestId: String?
    ) {
        let normalizedProjectId = normalizedDeepLinkToken(projectId)
        let normalizedRequestId = normalizedDeepLinkToken(requestId)
        guard let normalizedRequestId else { return }

        nextSupervisorFocusRequestNonce += 1
        supervisorFocusRequest = AXSupervisorFocusRequest(
            nonce: nextSupervisorFocusRequestNonce,
            projectId: normalizedProjectId,
            subject: .skillRecord(requestId: normalizedRequestId)
        )
    }

    func requestProjectToolApprovalFocus(
        projectId: String?,
        requestId: String?
    ) {
        guard let normalizedProjectId = normalizedDeepLinkToken(projectId) else { return }
        let normalizedRequestId = normalizedDeepLinkToken(requestId)

        nextProjectFocusRequestNonce += 1
        projectFocusRequest = AXProjectFocusRequest(
            nonce: nextProjectFocusRequestNonce,
            projectId: normalizedProjectId,
            subject: .toolApproval(requestId: normalizedRequestId)
        )
    }

    func requestProjectRouteDiagnoseFocus(projectId: String?) {
        guard let normalizedProjectId = normalizedDeepLinkToken(projectId) else { return }

        nextProjectFocusRequestNonce += 1
        projectFocusRequest = AXProjectFocusRequest(
            nonce: nextProjectFocusRequestNonce,
            projectId: normalizedProjectId,
            subject: .routeDiagnose
        )
    }

    func clearProjectFocusRequest(_ request: AXProjectFocusRequest) {
        guard projectFocusRequest?.nonce == request.nonce else { return }
        projectFocusRequest = nil
    }

    func clearSupervisorFocusRequest(_ request: AXSupervisorFocusRequest) {
        guard supervisorFocusRequest?.nonce == request.nonce else { return }
        supervisorFocusRequest = nil
    }

    func requestProjectDetailFocus(
        projectId: String?,
        section: XTProjectDetailSection = .overview,
        title: String? = nil,
        detail: String? = nil
    ) {
        guard let normalizedProjectId = normalizedDeepLinkToken(projectId) else { return }
        let sectionContext = section.focusContext
        let context = normalizedFocusContext(
            title: title ?? sectionContext.title,
            detail: detail ?? sectionContext.detail
        )

        nextProjectDetailFocusRequestNonce += 1
        projectDetailFocusRequest = XTProjectDetailFocusRequest(
            nonce: nextProjectDetailFocusRequestNonce,
            projectId: normalizedProjectId,
            section: section,
            context: context
        )
        setPane(.chat, for: normalizedProjectId)
        selectProject(normalizedProjectId)
    }

    func clearProjectDetailFocusRequest(_ request: XTProjectDetailFocusRequest) {
        guard projectDetailFocusRequest?.nonce == request.nonce else { return }
        projectDetailFocusRequest = nil
    }

    func requestSettingsFocus(
        sectionId: String?,
        title: String? = nil,
        detail: String? = nil,
        refreshAction: XTSectionRefreshAction? = nil,
        refreshReason: String? = nil
    ) {
        guard let normalizedSectionId = normalizedDeepLinkToken(sectionId) else { return }
        let context = normalizedFocusContext(
            title: title,
            detail: detail,
            refreshAction: refreshAction,
            refreshReason: refreshReason
        )

        nextSettingsFocusRequestNonce += 1
        settingsFocusRequest = XTSettingsFocusRequest(
            nonce: nextSettingsFocusRequestNonce,
            sectionId: normalizedSectionId,
            context: context
        )
    }

    func clearSettingsFocusRequest(_ request: XTSettingsFocusRequest) {
        guard settingsFocusRequest?.nonce == request.nonce else { return }
        settingsFocusRequest = nil
    }

    func requestSupervisorSettingsFocus(
        section: XTSupervisorSettingsFocusSection,
        title: String? = nil,
        detail: String? = nil
    ) {
        let sectionContext = section.focusContext
        let context = normalizedFocusContext(
            title: title ?? sectionContext.title,
            detail: detail ?? sectionContext.detail
        )

        nextSupervisorSettingsFocusRequestNonce += 1
        supervisorSettingsFocusRequest = XTSupervisorSettingsFocusRequest(
            nonce: nextSupervisorSettingsFocusRequestNonce,
            section: section,
            context: context
        )
    }

    func clearSupervisorSettingsFocusRequest(_ request: XTSupervisorSettingsFocusRequest) {
        guard supervisorSettingsFocusRequest?.nonce == request.nonce else { return }
        supervisorSettingsFocusRequest = nil
    }

    func requestProjectSettingsFocus(
        projectId: String?,
        destination: XTProjectGovernanceDestination?,
        preserveCurrentPane: Bool = false,
        overviewAnchor: XTProjectSettingsOverviewAnchor? = nil,
        title: String? = nil,
        detail: String? = nil
    ) {
        guard let normalizedProjectId = normalizedDeepLinkToken(projectId),
              let destination else {
            return
        }
        let destinationContext = destination.focusContext
        let context = normalizedFocusContext(
            title: title ?? destinationContext.title,
            detail: detail ?? destinationContext.detail
        )

        nextProjectSettingsFocusRequestNonce += 1
        projectSettingsFocusRequest = XTProjectSettingsFocusRequest(
            nonce: nextProjectSettingsFocusRequestNonce,
            projectId: normalizedProjectId,
            destination: destination,
            context: context,
            overviewAnchor: overviewAnchor
        )
        if !preserveCurrentPane {
            setPane(.chat, for: normalizedProjectId)
        }
        selectProject(normalizedProjectId)
    }

    func requestProjectSettingsFocus(
        projectId: String?,
        sectionId: String?,
        preserveCurrentPane: Bool = false,
        overviewAnchor: XTProjectSettingsOverviewAnchor? = nil,
        title: String? = nil,
        detail: String? = nil
    ) {
        requestProjectSettingsFocus(
            projectId: projectId,
            destination: XTProjectGovernanceDestination.parse(sectionId),
            preserveCurrentPane: preserveCurrentPane,
            overviewAnchor: overviewAnchor,
            title: title,
            detail: detail
        )
    }

    func clearProjectSettingsFocusRequest(_ request: XTProjectSettingsFocusRequest) {
        guard projectSettingsFocusRequest?.nonce == request.nonce else { return }
        projectSettingsFocusRequest = nil
    }

    func requestProjectUIReviewFocus(
        projectId: String?,
        title: String? = nil,
        detail: String? = nil
    ) {
        requestProjectSettingsFocus(
            projectId: projectId,
            destination: .uiReview,
            title: title ?? "Latest UI Review",
            detail: detail ?? "Project UI review workspace"
        )
    }

    func requestHubSetupFocus(
        sectionId: String?,
        title: String? = nil,
        detail: String? = nil,
        refreshAction: XTSectionRefreshAction? = nil,
        refreshReason: String? = nil
    ) {
        guard let normalizedSectionId = normalizedDeepLinkToken(sectionId) else { return }
        let context = normalizedFocusContext(
            title: title,
            detail: detail,
            refreshAction: refreshAction,
            refreshReason: refreshReason
        )

        nextHubSetupFocusRequestNonce += 1
        hubSetupFocusRequest = XTHubSetupFocusRequest(
            nonce: nextHubSetupFocusRequestNonce,
            sectionId: normalizedSectionId,
            context: context
        )
    }

    func clearHubSetupFocusRequest(_ request: XTHubSetupFocusRequest) {
        guard hubSetupFocusRequest?.nonce == request.nonce else { return }
        hubSetupFocusRequest = nil
    }

    func requestModelSettingsFocus(
        role: AXRole? = nil,
        title: String? = nil,
        detail: String? = nil
    ) {
        let context = normalizedFocusContext(title: title, detail: detail)
        guard role != nil || context != nil else { return }

        nextModelSettingsFocusRequestNonce += 1
        modelSettingsFocusRequest = XTModelSettingsFocusRequest(
            nonce: nextModelSettingsFocusRequestNonce,
            role: role,
            context: context
        )
    }

    func clearModelSettingsFocusRequest(_ request: XTModelSettingsFocusRequest) {
        guard modelSettingsFocusRequest?.nonce == request.nonce else { return }
        modelSettingsFocusRequest = nil
    }

    func prefillGrantContext(
        projectId: String,
        grantRequestId: String,
        capability: String?,
        reason: String? = nil
    ) {
        let grantId = grantRequestId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !grantId.isEmpty else { return }
        guard let ctx = projectContext(for: projectId) else { return }

        let s = session(for: ctx)
        s.ensureLoaded(ctx: ctx, limit: 200)

        let capabilityToken = (capability ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let capabilityLabel = XTHubGrantPresentation.capabilityLabel(
            capability: capabilityToken,
            modelId: ""
        )
        let reasonText = (reason ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        var lines = ["请先处理这笔 Hub 授权。"]
        lines.append("授权单号：\(grantId)")
        if !capabilityToken.isEmpty {
            lines.append("授权类型：\(capabilityLabel)")
        }
        lines.append("确认后继续推进当前项目。")
        if !reasonText.isEmpty {
            lines.append("授权原因：\(reasonText)")
        }
        let message = lines.joined(separator: "\n")

        let currentDraft = s.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if currentDraft.isEmpty {
            s.draft = message
        } else if !currentDraft.contains(grantId) {
            s.draft = message + "\n\n" + currentDraft
        }

        setPane(.chat, for: projectId)
        selectProject(projectId)
    }

    private func normalizedDeepLinkToken(_ raw: String?) -> String? {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func performSectionRefreshAction(
        _ action: XTSectionRefreshAction,
        reason: String? = nil
    ) {
        switch action {
        case .recheckOfficialSkills:
            recheckOfficialSkills(reason: reason)
        case .repairHistoricalProjectBoundaries:
            repairHistoricalProjectBoundariesNow(reason: reason)
        }
    }

    @discardableResult
    func repairHistoricalProjectBoundariesNow(reason: String? = nil) -> String {
        let normalizedReason = normalizedDeepLinkToken(reason) ?? "manual"
        let summary = runHistoricalProjectBoundaryRepair(reason: normalizedReason)
        if projectRoot != nil {
            Task { @MainActor in
                await loadSelectedProject()
            }
        }
        return summary.statusLine(reason: normalizedReason)
    }

    func recheckOfficialSkills(reason: String? = nil) {
        let normalizedReason = normalizedDeepLinkToken(reason) ?? "manual"
        let previousDigest = [
            normalizedDeepLinkToken(officialSkillChannelSummaryLine),
            normalizedDeepLinkToken(officialSkillChannelTopBlockersLine)
        ]
        .compactMap { $0 }
        .joined(separator: " | ")

        officialSkillsRecheckStatusLine = "official_skills_recheck=running reason=\(normalizedReason)"
        refreshSkillsCompatibilitySnapshot(force: true)
        refreshResolvedSkillsCacheForCurrentSelection()
        refreshUnifiedDoctorReport(force: true)

        let snapshotLine = normalizedDeepLinkToken(officialSkillChannelSummaryLine)
            ?? normalizedDeepLinkToken(skillsCompatibilitySnapshot.statusLine)
            ?? "skills?"
        let blockersLine = normalizedDeepLinkToken(officialSkillChannelTopBlockersLine)
        let currentDigest = [snapshotLine, blockersLine].compactMap { $0 }.joined(separator: " | ")
        let changeState = previousDigest.isEmpty ? "captured" : (previousDigest == currentDigest ? "unchanged" : "updated")

        var parts = [
            "official_skills_recheck=\(changeState)",
            "reason=\(normalizedReason)",
            "snapshot=\(snapshotLine)"
        ]
        if let blockersLine {
            parts.append(blockersLine)
        }
        officialSkillsRecheckStatusLine = parts.joined(separator: " ")
    }

    private func normalizedFocusContext(
        title: String?,
        detail: String?,
        refreshAction: XTSectionRefreshAction? = nil,
        refreshReason: String? = nil
    ) -> XTSectionFocusContext? {
        let normalizedTitle = normalizedDeepLinkToken(title)
        let normalizedDetail = normalizedDeepLinkToken(detail)
        let normalizedRefreshReason = normalizedDeepLinkToken(refreshReason)
        guard let normalizedTitle else {
            guard refreshAction != nil else { return nil }
            return XTSectionFocusContext(
                title: "Refresh requested",
                detail: normalizedDetail,
                refreshAction: refreshAction,
                refreshReason: normalizedRefreshReason
            )
        }
        return XTSectionFocusContext(
            title: normalizedTitle,
            detail: normalizedDetail,
            refreshAction: refreshAction,
            refreshReason: normalizedRefreshReason
        )
    }

    func approvePending(for projectId: String) {
        guard let s = sessionForProjectId(projectId) else { return }
        s.approvePendingTools(router: llmRouter)
    }

    func rejectPending(for projectId: String) {
        guard let s = sessionForProjectId(projectId) else { return }
        s.rejectPendingTools()
    }

    func skillCandidates(for projectId: String) -> [AXSkillCandidate] {
        guard let ctx = projectContext(for: projectId) else { return [] }
        return AXSkillCandidateStore.pendingCandidates(for: ctx)
    }

    func curationSuggestions(for projectId: String) -> [AXCurationSuggestion] {
        guard let ctx = projectContext(for: projectId) else { return [] }
        return AXCurationSuggestionStore.pendingSuggestions(for: ctx)
    }

    func approveSkillCandidate(projectId: String, candidateId: String) {
        guard let ctx = projectContext(for: projectId) else { return }
        let candidates = AXSkillCandidateStore.loadCandidates(for: ctx)
        guard let cand = candidates.first(where: { $0.id == candidateId }) else { return }
        guard let skillName = promoteCandidate(cand, ctx: ctx) else { return }
        AXSkillCandidateStore.updateCandidate(id: candidateId, status: "approved", skillName: skillName, promotedBy: "user", for: ctx)
        objectWillChange.send()
    }

    func rejectSkillCandidate(projectId: String, candidateId: String) {
        guard let ctx = projectContext(for: projectId) else { return }
        AXSkillCandidateStore.updateCandidate(id: candidateId, status: "rejected", skillName: nil, for: ctx)
        objectWillChange.send()
    }

    func applyCurationSuggestion(projectId: String, suggestionId: String) {
        guard let ctx = projectContext(for: projectId) else { return }
        _ = AXVaultCurator.applySuggestion(ctx: ctx, suggestionId: suggestionId, by: "user")
        objectWillChange.send()
    }

    func dismissCurationSuggestion(projectId: String, suggestionId: String) {
        guard let ctx = projectContext(for: projectId) else { return }
        AXVaultCurator.dismissSuggestion(ctx: ctx, suggestionId: suggestionId)
        objectWillChange.send()
    }

    func scanVaultNow(projectId: String) {
        guard let ctx = projectContext(for: projectId) else { return }
        _ = AXVaultCurator.scanAndSuggest(ctx: ctx)
        objectWillChange.send()
    }

    private func scheduleSkillScan() {
        maybeRunSkillScan(force: false)
        scheduleNextSkillScan()
    }

    private func migrateSkillsIfNeeded() {
        if boolDefault(for: skillsMigrationKey, legacy: legacySkillsMigrationKey) { return }
        guard let skillsDir = ensureSkillsDirectory() else { return }

        let projectsRoot = skillsDir.appendingPathComponent("_projects", isDirectory: true)
        let globalRoot = skillsDir.appendingPathComponent("_global", isDirectory: true)
        try? FileManager.default.createDirectory(at: projectsRoot, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: globalRoot, withIntermediateDirectories: true)

        var movedProject: [[String: String]] = []
        var movedGlobal: [[String: String]] = []

        let reserved: Set<String> = [
            "memory-core",
            "skill-creator",
            "skill-installer",
            "_projects",
            "_global",
            ".xterminal",
        ]

        var skillToProject: [String: (String, String)] = [:]
        for entry in registry.projects {
            guard let ctx = projectContext(for: entry.projectId) else { continue }
            let cands = AXSkillCandidateStore.loadCandidates(for: ctx)
            for cand in cands where cand.status == "approved" {
                if let name = cand.skillName, !name.isEmpty {
                    skillToProject[name] = (entry.projectId, entry.displayName)
                }
            }
        }

        let items = (try? FileManager.default.contentsOfDirectory(at: skillsDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        for item in items where item.hasDirectoryPath {
            let name = item.lastPathComponent
            if reserved.contains(name) { continue }
            let skillMD = item.appendingPathComponent("SKILL.md")
            if !FileManager.default.fileExists(atPath: skillMD.path) { continue }

            var moved = false
            if let mapped = skillToProject[name] {
                if let projectDir = projectSkillsDir(projectId: mapped.0, projectName: mapped.1, skillsDir: skillsDir) {
                    if let destName = moveSkill(from: item, to: projectDir, preferredName: name) {
                        let summary = extractSkillSummary(from: projectDir.appendingPathComponent(destName))
                        updateProjectSkillsIndex(projectDir: projectDir, skillName: destName, summary: summary)
                        updateGlobalSkillsIndex(skillsDir: skillsDir, projectDir: projectDir, projectName: mapped.1)
                        movedProject.append([
                            "name": destName,
                            "from": item.path,
                            "to": projectDir.appendingPathComponent(destName).path,
                        ])
                        moved = true
                    }
                }
            } else if let projectName = extractProjectName(from: item) {
                if let entry = registry.projects.first(where: { $0.displayName == projectName }),
                   let projectDir = projectSkillsDir(projectId: entry.projectId, projectName: entry.displayName, skillsDir: skillsDir) {
                    if let destName = moveSkill(from: item, to: projectDir, preferredName: name) {
                        let summary = extractSkillSummary(from: projectDir.appendingPathComponent(destName))
                        updateProjectSkillsIndex(projectDir: projectDir, skillName: destName, summary: summary)
                        updateGlobalSkillsIndex(skillsDir: skillsDir, projectDir: projectDir, projectName: entry.displayName)
                        movedProject.append([
                            "name": destName,
                            "from": item.path,
                            "to": projectDir.appendingPathComponent(destName).path,
                        ])
                        moved = true
                    }
                }
            }

            if !moved {
                if let destName = moveSkill(from: item, to: globalRoot, preferredName: name) {
                    let summary = extractSkillSummary(from: globalRoot.appendingPathComponent(destName))
                    updateGlobalSkillsIndexForGlobalSkill(skillsDir: skillsDir, skillName: destName, summary: summary)
                    movedGlobal.append([
                        "name": destName,
                        "from": item.path,
                        "to": globalRoot.appendingPathComponent(destName).path,
                    ])
                }
            }
        }

        writeMigrationReport(skillsDir: skillsDir, movedProject: movedProject, movedGlobal: movedGlobal)
        setDefault(true, for: skillsMigrationKey, legacy: legacySkillsMigrationKey)
    }

    private func scheduleNextSkillScan() {
        skillScanTimer?.invalidate()
        let next = nextSkillScanDate(from: Date())
        let interval = next.timeIntervalSinceNow
        if interval <= 1 { return }
        skillScanTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.maybeRunSkillScan(force: true)
                self.scheduleNextSkillScan()
            }
        }
    }

    private func maybeRunSkillScan(force: Bool) {
        let now = Date()
        let lastTs = doubleDefault(for: skillScanLastKey, legacy: legacySkillScanLastKey)
        let lastDate = lastTs > 0 ? Date(timeIntervalSince1970: lastTs) : Date(timeIntervalSince1970: 0)
        let currentEpoch = scanEpoch(for: now)
        let lastEpoch = scanEpoch(for: lastDate)
        if !force {
            if lastEpoch >= currentEpoch { return }
        }
        let since = lastTs > 0 ? lastTs : currentEpoch.addingTimeInterval(-86400).timeIntervalSince1970
        for entry in registry.projects {
            guard let ctx = projectContext(for: entry.projectId) else { continue }
            _ = AXSkillCandidateStore.scanCandidates(ctx: ctx, since: since)
            let pending = AXSkillCandidateStore.pendingCandidates(for: ctx)
            AXSkillAutoPromoter.maybeAutoPromote(ctx: ctx, detected: pending)
            _ = AXVaultCurator.scanAndSuggest(ctx: ctx)
        }
        setDefault(now.timeIntervalSince1970, for: skillScanLastKey, legacy: legacySkillScanLastKey)
        objectWillChange.send()
    }

    private func nextSkillScanDate(from now: Date) -> Date {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let todayScan = cal.date(bySettingHour: skillScanHour, minute: skillScanMinute, second: 0, of: today) ?? now
        if now < todayScan { return todayScan }
        return cal.date(byAdding: .day, value: 1, to: todayScan) ?? now.addingTimeInterval(86400)
    }

    private func scanEpoch(for date: Date) -> Date {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: date)
        let scanTime = cal.date(bySettingHour: skillScanHour, minute: skillScanMinute, second: 0, of: dayStart) ?? dayStart
        if date >= scanTime { return scanTime }
        return cal.date(byAdding: .day, value: -1, to: scanTime) ?? scanTime
    }

    private func promoteCandidate(_ cand: AXSkillCandidate, ctx: AXProjectContext) -> String? {
        guard let skillsDir = ensureSkillsDirectory() else { return nil }
        guard let skillName = AXSkillsLibrary.promoteCandidate(cand, skillsDir: skillsDir) else {
            showAlert(title: "Skill Promote", message: "Failed to promote skill candidate.")
            return nil
        }
        return skillName
    }

    private func updateProjectSkillsIndex(projectDir: URL, skillName: String, summary: String) {
        let indexURL = projectDir.appendingPathComponent("skills-index.md")
        let header = "# Skills Index (project)\n\n"
        let entry = "- \(skillName) — \(summary)（路径：\(projectDir.appendingPathComponent(skillName).path)）"
        let existing = (try? String(contentsOf: indexURL, encoding: .utf8)) ?? ""
        if existing.contains("/\(skillName)\n") || existing.contains("/\(skillName)）") { return }
        let out: String
        if existing.isEmpty {
            out = header + entry + "\n"
        } else if existing.contains("# Skills Index (project)") {
            out = existing.trimmingCharacters(in: .whitespacesAndNewlines) + "\n" + entry + "\n"
        } else {
            out = existing.trimmingCharacters(in: .whitespacesAndNewlines) + "\n\n" + header + entry + "\n"
        }
        try? XTStoreWriteSupport.writeUTF8Text(out, to: indexURL)
    }

    private func updateGlobalSkillsIndex(skillsDir: URL, projectDir: URL, projectName: String) {
        let indexURL = skillsDir
            .appendingPathComponent("memory-core", isDirectory: true)
            .appendingPathComponent("references", isDirectory: true)
            .appendingPathComponent("skills-index.md")
        let header = "# Skills Index (auto)\n\n"
        let projectSection = "## Projects (auto)\n"
        let entry = "- \(projectName) — 项目技能索引（路径：\(projectDir.appendingPathComponent("skills-index.md").path)）"
        let existing = (try? String(contentsOf: indexURL, encoding: .utf8)) ?? ""
        if existing.contains(projectDir.appendingPathComponent("skills-index.md").path) { return }
        let out: String
        if existing.isEmpty {
            out = header + projectSection + entry + "\n"
        } else if existing.contains("# Skills Index (auto)") {
            if existing.contains("## Projects (auto)") {
                out = existing.trimmingCharacters(in: .whitespacesAndNewlines) + "\n" + entry + "\n"
            } else {
                out = existing.trimmingCharacters(in: .whitespacesAndNewlines) + "\n\n" + projectSection + entry + "\n"
            }
        } else {
            out = existing.trimmingCharacters(in: .whitespacesAndNewlines) + "\n\n" + header + projectSection + entry + "\n"
        }
        try? XTStoreWriteSupport.writeUTF8Text(out, to: indexURL)
    }

    private func updateGlobalSkillsIndexForGlobalSkill(skillsDir: URL, skillName: String, summary: String) {
        let indexURL = skillsDir
            .appendingPathComponent("memory-core", isDirectory: true)
            .appendingPathComponent("references", isDirectory: true)
            .appendingPathComponent("skills-index.md")
        let header = "# Skills Index (auto)\n\n"
        let section = "## Global (auto)\n"
        let entry = "- \(skillName) — \(summary)（路径：\(skillsDir.appendingPathComponent("_global").appendingPathComponent(skillName).path)）"
        let existing = (try? String(contentsOf: indexURL, encoding: .utf8)) ?? ""
        if existing.contains("/_global/\(skillName)") { return }
        let out: String
        if existing.isEmpty {
            out = header + section + entry + "\n"
        } else if existing.contains("# Skills Index (auto)") {
            if existing.contains("## Global (auto)") {
                out = existing.trimmingCharacters(in: .whitespacesAndNewlines) + "\n" + entry + "\n"
            } else {
                out = existing.trimmingCharacters(in: .whitespacesAndNewlines) + "\n\n" + section + entry + "\n"
            }
        } else {
            out = existing.trimmingCharacters(in: .whitespacesAndNewlines) + "\n\n" + header + section + entry + "\n"
        }
        try? XTStoreWriteSupport.writeUTF8Text(out, to: indexURL)
    }

    private func writeMigrationReport(
        skillsDir: URL,
        movedProject: [[String: String]],
        movedGlobal: [[String: String]]
    ) {
        let report: [String: Any] = [
            "created_at": Date().timeIntervalSince1970,
            "moved_project_count": movedProject.count,
            "moved_global_count": movedGlobal.count,
            "moved_project": movedProject,
            "moved_global": movedGlobal,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted]) else { return }
        let url = skillsDir.appendingPathComponent("_migration_report.json")
        try? XTStoreWriteSupport.writeSnapshotData(data, to: url)
    }

    private func projectSkillsDir(projectId: String, projectName: String, skillsDir: URL) -> URL? {
        let projectsRoot = skillsDir.appendingPathComponent("_projects", isDirectory: true)
        try? FileManager.default.createDirectory(at: projectsRoot, withIntermediateDirectories: true)
        let suffix = String(projectId.prefix(8))
        if let existing = findProjectDir(in: projectsRoot, suffix: suffix) {
            return existing
        }
        let safeName = sanitizePathComponent(projectName)
        let dirName = safeName.isEmpty ? "project-\(suffix)" : "\(safeName)-\(suffix)"
        let dir = projectsRoot.appendingPathComponent(dirName, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func moveSkill(from src: URL, to destDir: URL, preferredName: String) -> String? {
        let name = uniqueSkillName(preferredName, in: destDir)
        let dest = destDir.appendingPathComponent(name, isDirectory: true)
        do {
            try FileManager.default.moveItem(at: src, to: dest)
            return name
        } catch {
            return nil
        }
    }

    private func extractProjectName(from skillDir: URL) -> String? {
        let flow = skillDir.appendingPathComponent("references", isDirectory: true).appendingPathComponent("flow.md")
        guard FileManager.default.fileExists(atPath: flow.path),
              let text = try? String(contentsOf: flow, encoding: .utf8) else { return nil }
        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            let cleaned = trimmed.hasPrefix("-") ? String(trimmed.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines) : trimmed
            if cleaned.hasPrefix("来源项目：") {
                let value = cleaned.replacingOccurrences(of: "来源项目：", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                return value.isEmpty ? nil : value
            }
            if cleaned.hasPrefix("来源项目:") {
                let value = cleaned.replacingOccurrences(of: "来源项目:", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                return value.isEmpty ? nil : value
            }
        }
        return nil
    }

    private func extractSkillSummary(from skillDir: URL) -> String {
        let skillMD = skillDir.appendingPathComponent("SKILL.md")
        guard let text = try? String(contentsOf: skillMD, encoding: .utf8) else {
            return skillDir.lastPathComponent
        }
        var inFrontMatter = false
        for line in text.split(separator: "\n") {
            let raw = String(line)
            if raw.trimmingCharacters(in: .whitespacesAndNewlines) == "---" {
                inFrontMatter.toggle()
                continue
            }
            if inFrontMatter {
                if raw.lowercased().hasPrefix("description:") {
                    let value = raw.dropFirst("description:".count)
                    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    return trimmed.isEmpty ? skillDir.lastPathComponent : trimmed
                }
            }
        }
        return skillDir.lastPathComponent
    }

    private func findProjectDir(in root: URL, suffix: String) -> URL? {
        guard let items = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else {
            return nil
        }
        for item in items where item.hasDirectoryPath {
            if item.lastPathComponent.hasSuffix("-\(suffix)") || item.lastPathComponent == "project-\(suffix)" {
                return item
            }
        }
        return nil
    }

    private func slugify(_ s: String) -> String {
        let allowed = CharacterSet.alphanumerics
        let lower = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var out = ""
        var lastDash = false
        for uni in lower.unicodeScalars {
            if allowed.contains(uni) {
                out.unicodeScalars.append(uni)
                lastDash = false
            } else {
                if !lastDash {
                    out.append("-")
                    lastDash = true
                }
            }
        }
        let trimmed = out.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return trimmed.isEmpty ? "skill-\(Int(Date().timeIntervalSince1970))" : trimmed
    }

    private func uniqueSkillName(_ base: String, in skillsDir: URL) -> String {
        var name = base
        var idx = 2
        while FileManager.default.fileExists(atPath: skillsDir.appendingPathComponent(name).path) {
            name = "\(base)-\(idx)"
            idx += 1
        }
        return name
    }

    private func truncateInline(_ s: String, max: Int) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.count <= max { return t }
        let idx = t.index(t.startIndex, offsetBy: max)
        return String(t[..<idx])
    }

    private func sanitizePathComponent(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return "" }
        let forbidden = CharacterSet(charactersIn: "/\\:?*|\"<>")
        var out = ""
        for scalar in t.unicodeScalars {
            if forbidden.contains(scalar) {
                out.append("-")
            } else {
                out.append(Character(scalar))
            }
        }
        t = out
        while t.contains("  ") { t = t.replacingOccurrences(of: "  ", with: " ") }
        t = t.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "" : t
    }

    private func boolDefault(for key: String, legacy: String) -> Bool {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: key) != nil {
            return defaults.bool(forKey: key)
        }
        if defaults.object(forKey: legacy) != nil {
            let value = defaults.bool(forKey: legacy)
            defaults.set(value, forKey: key)
            return value
        }
        return false
    }

    private func doubleDefault(for key: String, legacy: String) -> Double {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: key) != nil {
            return defaults.double(forKey: key)
        }
        if defaults.object(forKey: legacy) != nil {
            let value = defaults.double(forKey: legacy)
            defaults.set(value, forKey: key)
            return value
        }
        return 0
    }

    private func setDefault<T>(_ value: T, for key: String, legacy: String) {
        let defaults = UserDefaults.standard
        defaults.set(value, forKey: key)
        defaults.set(value, forKey: legacy)
    }

    private let skillsDirDefaultsKey = "xterminal_skills_dir"

    private func ensureSkillsDirectory() -> URL? {
        if let override = skillsDirectoryOverrideForTesting {
            do {
                try FileManager.default.createDirectory(at: override, withIntermediateDirectories: true)
                return override
            } catch {
                showAlert(title: "Import Skills", message: "Failed to create skills folder: \(error.localizedDescription)")
                return nil
            }
        }
        if let existing = resolveSkillsDirectory() {
            return existing
        }
        let support = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("X-Terminal", isDirectory: true)
            .appendingPathComponent("skills", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
            return support
        } catch {
            showAlert(title: "Import Skills", message: "Failed to create skills folder: \(error.localizedDescription)")
            return nil
        }
    }

    private func resolveSkillsDirectory() -> URL? {
        if let override = skillsDirectoryOverrideForTesting {
            let standardized = override.standardizedFileURL
            if FileManager.default.fileExists(atPath: standardized.path) {
                return standardized
            }
        }

        let envKeys = ["XTERMINAL_SKILLS_DIR"]
        for key in envKeys {
            let env = (ProcessInfo.processInfo.environment[key] ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !env.isEmpty {
                let u = URL(fileURLWithPath: NSString(string: env).expandingTildeInPath)
                if FileManager.default.fileExists(atPath: u.path) {
                    return u
                }
            }
        }

        if let stored = UserDefaults.standard.string(forKey: skillsDirDefaultsKey),
           !stored.isEmpty {
            let u = URL(fileURLWithPath: NSString(string: stored).expandingTildeInPath)
            if FileManager.default.fileExists(atPath: u.path) {
                return u
            }
        }

        // Dev builds may place the app bundle under `x-terminal/build` or repo-level `build`.
        let bundleDir = Bundle.main.bundleURL.deletingLastPathComponent()
        let repoRoot = bundleDir.deletingLastPathComponent()
        let devCandidates = [
            repoRoot.appendingPathComponent("skills", isDirectory: true),
            repoRoot.appendingPathComponent("x-terminal", isDirectory: true)
                .appendingPathComponent("skills", isDirectory: true),
        ]
        for candidate in devCandidates where FileManager.default.fileExists(atPath: candidate.path) {
            return candidate
        }

        let supportBase = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
        let support = supportBase
            .appendingPathComponent("X-Terminal", isDirectory: true)
            .appendingPathComponent("skills", isDirectory: true)
        if FileManager.default.fileExists(atPath: support.path) {
            return support
        }
        return nil
    }

    static var isRunningUnderTestProcess: Bool {
        ProcessInfo.processInfo.isRunningUnderAutomatedTests
    }

    private func rememberSkillsDirectory(for url: URL) {
        let dir: URL
        if url.hasDirectoryPath {
            dir = url
        } else {
            dir = url.deletingLastPathComponent()
        }
        UserDefaults.standard.set(dir.path, forKey: skillsDirDefaultsKey)
    }

    private func activateAppForModalPresentation() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func preferredModalHostWindow() -> NSWindow? {
        NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first(where: { $0.isVisible })
    }

    private func presentOpenPanel(_ panel: NSOpenPanel, onSelection: @escaping ([URL]) -> Void) {
        if let override = openPanelSelectionOverrideForTesting {
            guard let urls = override(panel), !urls.isEmpty else { return }
            onSelection(urls)
            return
        }

        activateAppForModalPresentation()
        let completion: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK else { return }
            let urls = panel.urls
            guard !urls.isEmpty else { return }
            onSelection(urls)
        }

        if let window = preferredModalHostWindow() {
            panel.beginSheetModal(for: window, completionHandler: completion)
        } else {
            panel.begin(completionHandler: completion)
        }
    }

    private func openURLInWorkspace(_ url: URL) {
        if let override = openedURLOverrideForTesting {
            override(url)
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func openCurrentProjectArtifact(_ resolveURL: (AXProjectContext) -> URL) {
        guard let ctx = projectContext else { return }
        openWorkspaceURL(resolveURL(ctx))
    }

    private func effectiveSupervisorVoiceSmokeReportURL() -> URL? {
        supervisorVoiceSmokeReportURLOverrideForTesting ?? supervisorVoiceSmokeReportURL
    }

    private struct SkillImportOperationResult {
        var imported: Bool
        var stageSummary: String?
    }

    private struct ResolvedSkillImportSource {
        var skillDirectoryURL: URL
        var cleanupDirectoryURL: URL?
    }

    private struct AgentSkillStageOutcome {
        var summary: String
        var stageResult: HubIPCClient.AgentImportStageResult?
        var importReport: XTAgentSkillImportPreflightReport
    }

    @discardableResult
    private func importSkill(from url: URL, to base: URL) async -> SkillImportOperationResult {
        let resolvedSource: ResolvedSkillImportSource
        do {
            resolvedSource = try resolveSkillImportSource(from: url)
        } catch {
            showAlert(
                title: "Import Skills",
                message: error.localizedDescription
            )
            return SkillImportOperationResult(imported: false, stageSummary: nil)
        }
        let source = resolvedSource.skillDirectoryURL
        defer {
            if let cleanupDirectoryURL = resolvedSource.cleanupDirectoryURL {
                try? FileManager.default.removeItem(at: cleanupDirectoryURL)
            }
        }

        let skillMD = source.appendingPathComponent("SKILL.md")
        guard FileManager.default.fileExists(atPath: skillMD.path) else {
            showAlert(
                title: "Import Skills",
                message: "SKILL.md not found in the selected folder."
            )
            return SkillImportOperationResult(imported: false, stageSummary: nil)
        }

        let dest = base.appendingPathComponent(source.lastPathComponent, isDirectory: true)
        let srcPath = source.standardizedFileURL.path
        let destPath = dest.standardizedFileURL.path
        if srcPath == destPath {
            showAlert(
                title: "Import Skills",
                message: "This skill is already in the skills folder."
            )
            return SkillImportOperationResult(imported: false, stageSummary: nil)
        }

        if FileManager.default.fileExists(atPath: dest.path) {
            guard confirmReplaceSkill(name: dest.lastPathComponent) else {
                return SkillImportOperationResult(imported: false, stageSummary: nil)
            }
            do {
                try FileManager.default.removeItem(at: dest)
            } catch {
                showAlert(
                    title: "Import Skills",
                    message: "Failed to replace existing skill: \(error.localizedDescription)"
                )
                return SkillImportOperationResult(imported: false, stageSummary: nil)
            }
        }

        do {
            try FileManager.default.copyItem(at: source, to: dest)
            let stageOutcome = await effectiveStageImportedSkill(skillDirectory: dest, repoRoot: base)
            rememberLastImportedAgentSkill(skillDirectory: dest, outcome: stageOutcome)
            return SkillImportOperationResult(imported: true, stageSummary: stageOutcome.summary)
        } catch {
            showAlert(
                title: "Import Skills",
                message: "Failed to import skill: \(error.localizedDescription)"
            )
            return SkillImportOperationResult(imported: false, stageSummary: nil)
        }
    }

    private func resolveSkillImportSource(from url: URL) throws -> ResolvedSkillImportSource {
        if url.hasDirectoryPath {
            return ResolvedSkillImportSource(skillDirectoryURL: url, cleanupDirectoryURL: nil)
        }

        let lower = url.lastPathComponent.lowercased()
        if lower == "skill.md" {
            return ResolvedSkillImportSource(skillDirectoryURL: url.deletingLastPathComponent(), cleanupDirectoryURL: nil)
        }

        guard isSupportedSkillArchive(url) else {
            throw NSError(
                domain: "xterminal.skill_import",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Please select a skill folder, SKILL.md, or a supported archive (.zip, .skill, .tgz, .tar.gz, .tar)."]
            )
        }

        let extractionRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt-skill-import-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: extractionRoot, withIntermediateDirectories: true)

        do {
            try extractSkillArchive(url, to: extractionRoot)
            let fallbackNames = archiveFallbackNames(for: url)
            let skillDirectory = try findImportedSkillDirectory(in: extractionRoot, fallbackNames: fallbackNames)
            return ResolvedSkillImportSource(skillDirectoryURL: skillDirectory, cleanupDirectoryURL: extractionRoot)
        } catch {
            try? FileManager.default.removeItem(at: extractionRoot)
            throw error
        }
    }

    private func isSupportedSkillArchive(_ url: URL) -> Bool {
        let lower = url.lastPathComponent.lowercased()
        let ext = url.pathExtension.lowercased()
        if ["zip", "skill", "tgz", "tar"].contains(ext) {
            return true
        }
        return lower.hasSuffix(".tar.gz")
    }

    private func archiveFallbackNames(for url: URL) -> [String] {
        let lower = url.lastPathComponent.lowercased()
        var names: [String] = []
        if lower.hasSuffix(".tar.gz") {
            names.append(String(url.lastPathComponent.dropLast(".tar.gz".count)))
        }
        if !url.deletingPathExtension().lastPathComponent.isEmpty {
            names.append(url.deletingPathExtension().lastPathComponent)
        }
        return Array(
            Set(
                names
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            )
        )
    }

    private func extractSkillArchive(_ archiveURL: URL, to destinationURL: URL) throws {
        let lower = archiveURL.lastPathComponent.lowercased()
        let ext = archiveURL.pathExtension.lowercased()

        let result: ProcessResult
        if ext == "zip" || ext == "skill" {
            result = try ProcessCapture.run(
                "/usr/bin/ditto",
                ["-x", "-k", archiveURL.path, destinationURL.path],
                cwd: nil,
                timeoutSec: 30.0
            )
        } else if ext == "tgz" || lower.hasSuffix(".tar.gz") {
            result = try ProcessCapture.run(
                "/usr/bin/tar",
                ["-xzf", archiveURL.path, "-C", destinationURL.path],
                cwd: nil,
                timeoutSec: 30.0
            )
        } else if ext == "tar" {
            result = try ProcessCapture.run(
                "/usr/bin/tar",
                ["-xf", archiveURL.path, "-C", destinationURL.path],
                cwd: nil,
                timeoutSec: 30.0
            )
        } else {
            throw NSError(
                domain: "xterminal.skill_import",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Unsupported archive format: \(archiveURL.lastPathComponent)"]
            )
        }

        guard result.exitCode == 0 else {
            let detail = result.combined.trimmingCharacters(in: .whitespacesAndNewlines)
            throw NSError(
                domain: "xterminal.skill_import",
                code: Int(result.exitCode),
                userInfo: [NSLocalizedDescriptionKey: detail.isEmpty ? "Failed to extract skill archive." : "Failed to extract skill archive: \(detail)"]
            )
        }
    }

    private func findImportedSkillDirectory(in rootURL: URL, fallbackNames: [String]) throws -> URL {
        let rootSkillMarkdownURL = rootURL.appendingPathComponent("SKILL.md")
        if FileManager.default.fileExists(atPath: rootSkillMarkdownURL.path) {
            return rootURL
        }

        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            throw NSError(
                domain: "xterminal.skill_import",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Imported archive could not be scanned for SKILL.md."]
            )
        }

        var candidates: [URL] = []
        while let next = enumerator.nextObject() as? URL {
            let values = try next.resourceValues(forKeys: [.isDirectoryKey])
            guard values.isDirectory == true else { continue }
            let skillMarkdownURL = next.appendingPathComponent("SKILL.md")
            if FileManager.default.fileExists(atPath: skillMarkdownURL.path) {
                candidates.append(next)
            }
        }

        let uniqueCandidates = Array(
            Set(candidates.map { $0.standardizedFileURL.resolvingSymlinksInPath() })
        ).sorted { lhs, rhs in
            lhs.path.localizedStandardCompare(rhs.path) == .orderedAscending
        }

        if uniqueCandidates.count == 1, let only = uniqueCandidates.first {
            return only
        }

        let normalizedFallbacks = Set(fallbackNames.map { $0.lowercased() })
        let matchedCandidates = uniqueCandidates.filter { candidate in
            normalizedFallbacks.contains(candidate.lastPathComponent.lowercased())
        }
        if matchedCandidates.count == 1, let matched = matchedCandidates.first {
            return matched
        }

        if uniqueCandidates.isEmpty {
            throw NSError(
                domain: "xterminal.skill_import",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: "No SKILL.md was found in the imported archive."]
            )
        }

        let labels = uniqueCandidates.map(\.lastPathComponent).joined(separator: ", ")
        throw NSError(
            domain: "xterminal.skill_import",
            code: 5,
            userInfo: [NSLocalizedDescriptionKey: "The imported archive contains multiple skill folders. Please keep only one SKILL.md root. Candidates: \(labels)"]
        )
    }

    private func effectiveStageImportedSkill(skillDirectory: URL, repoRoot: URL) async -> AgentSkillStageOutcome {
        if let override = stagedImportSummaryOverrideForTesting,
           let summary = await override(skillDirectory, repoRoot) {
            let preflight = XTAgentSkillImportNormalizer.normalize(
                skillMarkdownURL: skillDirectory.appendingPathComponent("SKILL.md"),
                repoRoot: repoRoot
            )
            return AgentSkillStageOutcome(
                summary: summary,
                stageResult: nil,
                importReport: preflight
            )
        }
        return await stageImportedSkill(skillDirectory: skillDirectory, repoRoot: repoRoot)
    }

    func reviewLastImportedSkill() {
        let reviewSkillName = nonEmptyString(lastImportedAgentSkillName)
            ?? nonEmptyString(lastImportedAgentSkillStage?.skillId)
            ?? "skill"
        lastImportedAgentSkillStatusLine = "\(reviewSkillName): reviewing..."
        Task(priority: .userInitiated) { [weak self] in
            await self?.reviewLastImportedSkillNow()
        }
    }

    func enableLastImportedSkill() {
        let enableSkillName = nonEmptyString(lastImportedAgentSkillName)
            ?? lastImportedAgentSkillDirectory?.lastPathComponent
            ?? "skill"
        lastImportedAgentSkillStatusLine = "\(enableSkillName): enabling..."
        Task(priority: .userInitiated) { [weak self] in
            await self?.enableLastImportedSkillNow()
        }
    }

    func installDefaultAgentBaselineGlobally() {
        Task { @MainActor in
            await installDefaultAgentBaselineNow(scope: .global)
        }
    }

    func installDefaultAgentBaselineForCurrentProject() {
        guard let scope = selectedProjectBaselineInstallScope() else { return }
        Task { @MainActor in
            await installDefaultAgentBaselineNow(scope: scope)
        }
    }

    private func selectedProjectBaselineInstallScope() -> AXAgentBaselineInstallScope? {
        guard let selectedProjectId,
              selectedProjectId != AXProjectRegistry.globalHomeId else { return nil }
        let projectName = registry.project(for: selectedProjectId)?.displayName
        return .project(projectId: selectedProjectId, projectName: projectName)
    }

    private func installDefaultAgentBaselineNow(scope: AXAgentBaselineInstallScope) async {
        guard !baselineInstallBusy else { return }
        let hasRemoteSkillsControl = await HubPairingCoordinator.shared.hasHubEnv(stateDir: nil)
        guard hasRemoteSkillsControl else {
            baselineInstallStatusLine = "baseline: Hub pairing required"
            showAlert(
                title: "Install Default Agent Baseline",
                message: "Hub skills control plane is unavailable. Pair X-Terminal to X-Hub first so baseline install can use the governed remote pin flow."
            )
            return
        }

        baselineInstallBusy = true
        defer { baselineInstallBusy = false }

        let baseline = AXSkillsLibrary.defaultAgentBaselineSkills
        let bundles = AXSkillsLibrary.defaultAgentBaselineBundles
        let targetProjectId = scope.projectId
        let targetLabel = scope.displayLabel
        let currentProfileSnapshot = currentBaselineInstallProfileSnapshot(for: scope)
        let initialResolved = await HubIPCClient.listResolvedSkills(projectId: targetProjectId)
        guard initialResolved.ok else {
            baselineInstallStatusLine = "baseline: resolved lookup failed"
            showAlert(
                title: "Install Default Agent Baseline",
                message: "Failed to load resolved Hub skills for \(targetLabel) (\(initialResolved.reasonCode ?? "unknown"))."
            )
            return
        }

        var searchResultsBySkillID: [String: [HubIPCClient.SkillCatalogEntry]] = [:]
        var searchFailures: [String: String] = [:]
        await withTaskGroup(of: (String, HubIPCClient.SkillsSearchResult).self) { group in
            for baselineSkill in baseline {
                let skillID = baselineSkill.skillID
                group.addTask {
                    let result = await HubIPCClient.searchSkills(
                        query: skillID,
                        projectId: targetProjectId,
                        limit: 12
                    )
                    return (skillID, result)
                }
            }

            for await (skillID, result) in group {
                searchResultsBySkillID[skillID] = result.results
                if !result.ok {
                    searchFailures[skillID] = result.reasonCode ?? "search_failed"
                }
            }
        }

        let plan = AXDefaultAgentBaselineInstaller.makePlan(
            scope: scope,
            baseline: baseline,
            bundles: bundles,
            resolvedSkills: initialResolved.skills,
            searchResultsBySkillID: searchResultsBySkillID,
            currentProfileSnapshot: currentProfileSnapshot
        )
        let baselineIDs = Set(baseline.map(\.skillID))

        let previewLines = AXDefaultAgentBaselineInstaller.previewLines(
            plan: plan,
            currentProfileSnapshot: currentProfileSnapshot
        )
        if plan.installableCandidates.isEmpty {
            let currentReadyCount = plan.alreadyResolvedSkillIDs.count
            var lines = ["Target: \(targetLabel)"]
            lines.append("Baseline ready: \(currentReadyCount)/\(plan.totalBaselineCount)")
            lines.append(contentsOf: previewLines)
            if !plan.missingPackageSkills.isEmpty {
                baselineInstallStatusLine = "baseline \(scope.hubScope) \(currentReadyCount)/\(plan.totalBaselineCount) missing_pkg=\(plan.missingPackageSkills.count)"
                lines.append("No uploadable baseline package can be pinned yet for the missing skills above.")
            } else {
                baselineInstallStatusLine = "baseline \(scope.hubScope) \(plan.totalBaselineCount)/\(plan.totalBaselineCount) ready"
                lines.append("No pin work was needed. The default Agent baseline is already resolved for this target.")
            }
            showAlert(title: "Install Default Agent Baseline", message: lines.joined(separator: "\n"))
            return
        }

        var confirmationLines = ["Target: \(targetLabel)"]
        confirmationLines.append(contentsOf: previewLines)
        confirmationLines.append("Proceed with governed pinning for \(plan.installableCandidates.count) package(s)?")
        guard confirmDefaultAgentBaselineInstall(
            title: "Install Default Agent Baseline",
            message: confirmationLines.joined(separator: "\n")
        ) else {
            baselineInstallStatusLine = "baseline \(scope.hubScope) canceled"
            return
        }

        var pinSuccesses: [HubIPCClient.SkillPinResult] = []
        var pinFailures: [String] = []
        for candidate in plan.installableCandidates {
            let pin = await HubIPCClient.setSkillPin(
                scope: scope.hubScope,
                skillId: candidate.skillID,
                packageSHA256: candidate.packageSHA256,
                projectId: targetProjectId,
                note: scope.noteTag,
                requestId: "xt-default-agent-baseline-\(UUID().uuidString)"
            )
            if pin.ok {
                pinSuccesses.append(pin)
            } else {
                pinFailures.append("\(candidate.skillID): \(pin.reasonCode ?? "pin_failed")")
            }
        }

        if !pinSuccesses.isEmpty {
            refreshSkillsCompatibilitySnapshot(force: true)
            refreshUnifiedDoctorReport(force: true)
            if let selectedProjectId,
               selectedProjectId != AXProjectRegistry.globalHomeId,
               let ctx = projectContext {
                let selectedProjectName = registry.project(for: selectedProjectId)?.displayName
                _ = await XTResolvedSkillsCacheStore.refreshFromHubIfPossible(
                    projectId: selectedProjectId,
                    projectName: selectedProjectName,
                    context: ctx,
                    hubBaseDir: hubBaseDir ?? HubPaths.baseDir(),
                    force: true
                )
            } else {
                refreshResolvedSkillsCacheForCurrentSelection()
            }
        }

        let finalResolved = await HubIPCClient.listResolvedSkills(projectId: targetProjectId)
        let finalResolvedIDs = Set(
            (finalResolved.ok ? finalResolved.skills : initialResolved.skills)
                .map { $0.skill.skillID }
        )
        let readyBaselineCount = finalResolvedIDs.intersection(baselineIDs).count

        var status = "baseline \(scope.hubScope) \(readyBaselineCount)/\(plan.totalBaselineCount)"
        if !pinFailures.isEmpty {
            status += " pin_fail=\(pinFailures.count)"
        } else if !plan.missingPackageSkills.isEmpty {
            status += " missing_pkg=\(plan.missingPackageSkills.count)"
        } else if pinSuccesses.isEmpty {
            status += " ready"
        }
        baselineInstallStatusLine = status

        var lines: [String] = []
        lines.append("Target: \(targetLabel)")
        lines.append("Baseline ready: \(readyBaselineCount)/\(plan.totalBaselineCount)")
        if !plan.targetCapabilityProfiles.isEmpty {
            lines.append("Bundle target profiles: \(plan.targetCapabilityProfiles.joined(separator: ", "))")
        }
        lines.append(
            plan.deltaCapabilityProfiles.isEmpty
                ? "Profile delta after install: none"
                : "Profile delta after install: \(plan.deltaCapabilityProfiles.joined(separator: ", "))"
        )
        if !plan.residualBlockedProfiles.isEmpty {
            let blockedLine = plan.residualBlockedProfiles.map { blocked in
                let reason = blocked.reasonCode.trimmingCharacters(in: .whitespacesAndNewlines)
                return reason.isEmpty ? blocked.profileID : "\(blocked.profileID)=\(reason)"
            }.joined(separator: ", ")
            lines.append("Residual blocked profiles: \(blockedLine)")
        } else if currentProfileSnapshot != nil {
            lines.append("Residual blocked profiles: none")
        }

        for bundle in plan.bundles {
            var bundleParts: [String] = [
                "\(bundle.displayName) [\(bundle.bundleID)]"
            ]
            if !bundle.targetCapabilityProfiles.isEmpty {
                bundleParts.append("profiles=\(bundle.targetCapabilityProfiles.joined(separator: ", "))")
            }
            if !bundle.deltaCapabilityProfiles.isEmpty {
                bundleParts.append("delta=\(bundle.deltaCapabilityProfiles.joined(separator: ", "))")
            }
            if !bundle.missingPackageSkills.isEmpty {
                bundleParts.append("missing_pkg=\(bundle.missingPackageSkills.count)")
            }
            lines.append(bundleParts.joined(separator: " | "))
        }

        if !plan.alreadyResolvedSkillIDs.isEmpty {
            lines.append("Already resolved: \(plan.alreadyResolvedSkillIDs.joined(separator: ", "))")
        }
        if !pinSuccesses.isEmpty {
            let successLine = pinSuccesses.map { pin in
                "\(pin.skillId)@\(shortSHA(pin.packageSHA256))"
            }.joined(separator: ", ")
            lines.append("Pinned: \(successLine)")
        }
        if !pinFailures.isEmpty {
            lines.append("Pin failures: \(pinFailures.joined(separator: "; "))")
        }
        if !searchFailures.isEmpty {
            let failureLine = searchFailures.keys.sorted().map { key in
                "\(key): \(searchFailures[key] ?? "search_failed")"
            }.joined(separator: "; ")
            lines.append("Search failures: \(failureLine)")
        }
        if !plan.missingPackageSkills.isEmpty {
            lines.append("Missing uploadable packages:")
            for item in plan.missingPackageSkills {
                let profiles = item.capabilityProfiles.isEmpty ? "" : " [\(item.capabilityProfiles.joined(separator: ", "))]"
                lines.append("- \(item.skillID)\(profiles): \(item.installHint)")
            }
        } else if plan.installableCandidates.isEmpty && pinSuccesses.isEmpty {
            lines.append("No pin work was needed. The default Agent baseline was already resolved for this target.")
        }

        if finalResolved.ok == false {
            lines.append("Final resolved refresh failed: \(finalResolved.reasonCode ?? "unknown")")
        }

        showAlert(title: "Install Default Agent Baseline", message: lines.joined(separator: "\n"))
    }

    private func currentBaselineInstallProfileSnapshot(
        for scope: AXAgentBaselineInstallScope
    ) -> XTProjectEffectiveSkillProfileSnapshot? {
        guard let ctx = projectContext else { return nil }

        switch scope {
        case .project(let projectId, let projectName):
            guard selectedProjectId == projectId else { return nil }
            return AXSkillsLibrary.projectEffectiveSkillProfileSnapshot(
                projectId: projectId,
                projectName: projectName,
                projectRoot: ctx.root,
                config: projectConfig,
                hubBaseDir: hubBaseDir ?? HubPaths.baseDir()
            )
        case .global:
            guard let selectedProjectId,
                  selectedProjectId != AXProjectRegistry.globalHomeId else { return nil }
            let projectName = registry.project(for: selectedProjectId)?.displayName
            return AXSkillsLibrary.projectEffectiveSkillProfileSnapshot(
                projectId: selectedProjectId,
                projectName: projectName,
                projectRoot: ctx.root,
                config: projectConfig,
                hubBaseDir: hubBaseDir ?? HubPaths.baseDir()
            )
        }
    }

    private func refreshResolvedSkillsCacheForCurrentSelection() {
        guard let selectedProjectId,
              selectedProjectId != AXProjectRegistry.globalHomeId,
              let ctx = projectContext else { return }
        let projectName = registry.project(for: selectedProjectId)?.displayName
        Task {
            _ = await XTResolvedSkillsCacheStore.refreshFromHubIfPossible(
                projectId: selectedProjectId,
                projectName: projectName,
                context: ctx,
                hubBaseDir: hubBaseDir ?? HubPaths.baseDir(),
                force: true
            )
        }
    }

    private func stageImportedSkill(skillDirectory: URL, repoRoot: URL) async -> AgentSkillStageOutcome {
        let skillName = skillDirectory.lastPathComponent
        let skillMarkdownURL = skillDirectory.appendingPathComponent("SKILL.md")
        let preflight = XTAgentSkillImportNormalizer.normalize(
            skillMarkdownURL: skillMarkdownURL,
            repoRoot: repoRoot
        )
        let scanInput = XTAgentSkillImportNormalizer.buildScanInput(skillDirectoryURL: skillDirectory)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        guard let manifestData = try? encoder.encode(preflight.manifest),
              let findingsData = try? encoder.encode(preflight.findings),
              let scanInputData = try? encoder.encode(scanInput),
              let manifestJSON = String(data: manifestData, encoding: .utf8),
              let findingsJSON = String(data: findingsData, encoding: .utf8),
              let scanInputJSON = String(data: scanInputData, encoding: .utf8) else {
            return AgentSkillStageOutcome(
                summary: "\(skillName): imported locally; failed to encode Hub stage payload.",
                stageResult: nil,
                importReport: preflight
            )
        }

        let stage = await HubIPCClient.stageAgentImport(
            importManifestJSON: manifestJSON,
            findingsJSON: findingsJSON,
            scanInputJSON: scanInputJSON,
            requestedBy: "xt-ui",
            note: "ui_import:\(skillName)",
            requestId: "xt-ui-agent-import-\(UUID().uuidString)"
        )
        if !stage.ok {
            return AgentSkillStageOutcome(
                summary: "\(skillName): imported locally; Hub stage failed (\(stage.reasonCode ?? "unknown")).",
                stageResult: stage,
                importReport: preflight
            )
        }

        let preflightStatus = stage.preflightStatus ?? preflight.manifest.preflightStatus
        let vetterStatus = stage.vetterStatus ?? "pending"
        let counts = "c\(stage.vetterCriticalCount)/w\(stage.vetterWarnCount)"
        let stageLabel = stage.stagingId ?? "n/a"
        return AgentSkillStageOutcome(
            summary: "\(skillName): Hub \(stage.status ?? "staged"), preflight=\(preflightStatus), vetter=\(vetterStatus), \(counts), id=\(stageLabel)",
            stageResult: stage,
            importReport: preflight
        )
    }

    private func reviewLastImportedSkillNow() async {
        guard !agentSkillImportBusy else { return }
        let stagingId = lastImportedAgentSkillStage?.stagingId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !stagingId.isEmpty else {
            showAlert(title: "Review Imported Skill", message: "No staged import is available yet.")
            return
        }

        agentSkillImportBusy = true
        defer { agentSkillImportBusy = false }

        let record = await HubIPCClient.getAgentImportRecord(stagingId: stagingId)
        guard record.ok else {
            showAlert(
                title: "Review Imported Skill",
                message: "Failed to fetch Hub import record (\(record.reasonCode ?? "unknown"))."
            )
            return
        }

        let reviewText = formatAgentImportRecordReview(
            recordJSON: record.recordJSON,
            fallbackStagingId: record.stagingId ?? stagingId,
            fallbackSkillId: record.skillId ?? lastImportedAgentSkillName
        )
        let reviewSkillName = nonEmptyString(record.skillId) ?? nonEmptyString(lastImportedAgentSkillName) ?? "skill"
        lastImportedAgentSkillStatusLine = "\(reviewSkillName): reviewed"
        showAlert(title: "Review Imported Skill", message: reviewText)
    }

    private func enableLastImportedSkillNow() async {
        guard !agentSkillImportBusy else { return }
        guard let skillDirectory = lastImportedAgentSkillDirectory else {
            showAlert(title: "Enable Imported Skill", message: "No imported skill is available yet.")
            return
        }
        guard FileManager.default.fileExists(atPath: skillDirectory.path) else {
            showAlert(
                title: "Enable Imported Skill",
                message: "The last imported skill folder no longer exists: \(skillDirectory.path)"
            )
            return
        }

        agentSkillImportBusy = true
        defer { agentSkillImportBusy = false }

        let repoRoot = resolveSkillsDirectory() ?? skillDirectory.deletingLastPathComponent()
        let stageOutcome = await effectiveStageImportedSkill(skillDirectory: skillDirectory, repoRoot: repoRoot)
        rememberLastImportedAgentSkill(skillDirectory: skillDirectory, outcome: stageOutcome)

        guard let stage = stageOutcome.stageResult,
              stage.ok,
              let stagingId = nonEmptyString(stage.stagingId) else {
            showAlert(title: "Enable Imported Skill", message: stageOutcome.summary)
            return
        }

        let stageStatus = nonEmptyString(stage.status) ?? "staged"
        let vetterStatus = nonEmptyString(stage.vetterStatus) ?? "pending"
        if stageStatus == "quarantined" || ["pending", "scan_error", "critical"].contains(vetterStatus) {
            var lines = [stageOutcome.summary]
            if let blocked = nonEmptyString(stage.reasonCode) {
                lines.append("Hub blocked enable: \(blocked)")
            } else {
                lines.append("Hub blocked enable: vetter=\(vetterStatus)")
            }
            showAlert(title: "Enable Imported Skill", message: lines.joined(separator: "\n"))
            return
        }

        let packageBuild: XTAgentSkillPackageBuildResult
        do {
            packageBuild = try XTAgentSkillPackageBuilder.build(
                skillDirectoryURL: skillDirectory,
                importReport: stageOutcome.importReport
            )
        } catch {
            showAlert(
                title: "Enable Imported Skill",
                message: "Failed to build skill package: \(error.localizedDescription)"
            )
            return
        }
        defer { XTAgentSkillPackageBuilder.cleanup(packageBuild) }

        let upload = await HubIPCClient.uploadSkillPackage(
            packageFileURL: packageBuild.packageURL,
            manifestJSON: packageBuild.manifestJSON,
            sourceId: "local:xt-import",
            requestId: "xt-ui-agent-upload-\(UUID().uuidString)"
        )
        guard upload.ok,
              let packageSHA256 = nonEmptyString(upload.packageSHA256) else {
            var lines = [stageOutcome.summary]
            lines.append("Package build: \(packageBuild.includedRelativePaths.count) files")
            lines.append("Upload failed: \(upload.reasonCode ?? "unknown")")
            showAlert(title: "Enable Imported Skill", message: lines.joined(separator: "\n"))
            return
        }

        let promote = await HubIPCClient.promoteAgentImport(
            stagingId: stagingId,
            packageSHA256: packageSHA256,
            note: "ui_enable:\(skillDirectory.lastPathComponent)",
            requestId: "xt-ui-agent-promote-\(UUID().uuidString)"
        )

        var lines = [stageOutcome.summary]
        lines.append("Package: sha=\(shortSHA(packageSHA256)), files=\(packageBuild.includedRelativePaths.count)")
        if !packageBuild.includedRelativePaths.isEmpty {
            lines.append("Included: \(packageBuild.includedRelativePaths.prefix(6).joined(separator: ", "))")
        }

        guard promote.ok else {
            lines.append("Promote failed: \(promote.reasonCode ?? "unknown")")
            lastImportedAgentSkillStatusLine = "\(skillDirectory.lastPathComponent): upload ok, promote blocked"
            showAlert(title: "Enable Imported Skill", message: lines.joined(separator: "\n"))
            return
        }

        let enabledSkillId = nonEmptyString(promote.skillId) ?? nonEmptyString(stage.skillId) ?? skillDirectory.lastPathComponent
        lastImportedAgentSkillStatusLine = "\(enabledSkillId): enabled @\(shortSHA(packageSHA256))"
        lines.append("Enabled: \(enabledSkillId)")
        lines.append("Scope: \(nonEmptyString(promote.scope) ?? "unknown")")
        if let previous = nonEmptyString(promote.previousPackageSHA256) {
            lines.append("Previous package: \(shortSHA(previous))")
        }
        showAlert(title: "Enable Imported Skill", message: lines.joined(separator: "\n"))
        refreshSkillsCompatibilitySnapshot(force: true)
        refreshUnifiedDoctorReport(force: true)
    }

    private func rememberLastImportedAgentSkill(skillDirectory: URL, outcome: AgentSkillStageOutcome) {
        lastImportedAgentSkillDirectory = skillDirectory
        lastImportedAgentSkillName = skillDirectory.lastPathComponent
        lastImportedAgentSkillStage = outcome.stageResult
        lastImportedAgentSkillStatusLine = outcome.summary
    }

    private func formatAgentImportRecordReview(
        recordJSON: String?,
        fallbackStagingId: String,
        fallbackSkillId: String
    ) -> String {
        XTAgentSkillImportReviewFormatter.formatHubRecordReview(
            recordJSON: recordJSON,
            fallbackStagingId: fallbackStagingId,
            fallbackSkillId: fallbackSkillId
        )
    }

    private func nonEmptyString(_ value: String?) -> String? {
        let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func shortSHA(_ value: String?) -> String {
        let normalized = nonEmptyString(value) ?? ""
        guard !normalized.isEmpty else { return "n/a" }
        return String(normalized.prefix(12))
    }

    private func defaultLocalSkillManifestJSON(for folderURL: URL) throws -> String {
        let skillMarkdownURL = folderURL.appendingPathComponent("SKILL.md")
        let skillText = (try? String(contentsOf: skillMarkdownURL, encoding: .utf8)) ?? ""
        let frontmatter = parseSkillMarkdownFrontmatter(skillText)
        let skillID = nonEmptyString(frontmatter["skill_id"])
            ?? nonEmptyString(folderURL.lastPathComponent)
            ?? "local-skill"
        let displayName = nonEmptyString(frontmatter["name"]) ?? skillID
        let version = nonEmptyString(frontmatter["version"]) ?? "0.1.0-local"
        let description = nonEmptyString(frontmatter["description"])
            ?? extractSkillMarkdownHeading(skillText)
            ?? "Local skill managed in X-Terminal."
        let entrypoint = inferLocalSkillEntrypoint(in: folderURL)

        let manifest: [String: Any] = [
            "schema_version": "xhub.skill_manifest.v1",
            "skill_id": skillID,
            "name": displayName,
            "version": version,
            "description": description,
            "entrypoint": [
                "runtime": entrypoint.runtime,
                "command": entrypoint.command,
                "args": entrypoint.args,
            ],
            "capabilities_required": [],
            "network_policy": [
                "direct_network_forbidden": true,
            ],
            "publisher": [
                "publisher_id": "xhub.local.dev",
            ],
            "install_hint": "Created in X-Terminal Skill Library",
        ]

        let data = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
        guard var manifestJSON = String(data: data, encoding: .utf8) else {
            throw NSError(
                domain: "xterminal.skill_manifest_create",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to encode skill.json as UTF-8."]
            )
        }
        if !manifestJSON.hasSuffix("\n") {
            manifestJSON.append("\n")
        }
        return manifestJSON
    }

    private func pinGovernedSkillFromGovernanceSurface(
        _ entry: AXSkillGovernanceSurfaceEntry,
        scope: AXAgentBaselineInstallScope
    ) async {
        let skillID = normalizedDeepLinkToken(entry.skillID) ?? ""
        let packageSHA256 = normalizedDeepLinkToken(entry.packageSHA256) ?? ""
        let subject = governanceSurfaceSubject(entry)

        guard hubInteractive else {
            skillGovernanceActionStatusLine = "skill_governance_action=pin skill=\(entry.skillID) scope=\(scope.hubScope) status=blocked reason=hub_pairing_required"
            showAlert(
                title: "Pin Governed Skill",
                message: "Hub skills control plane is unavailable. Pair X-Terminal to X-Hub first before pinning \(subject)."
            )
            return
        }

        skillGovernanceActionStatusLine = "skill_governance_action=pin skill=\(entry.skillID) scope=\(scope.hubScope) status=running"
        let result = await HubIPCClient.setSkillPin(
            scope: scope.hubScope,
            skillId: skillID,
            packageSHA256: packageSHA256,
            projectId: scope.projectId,
            note: "xt_skill_governance_surface:\(scope.hubScope):\(skillID)",
            requestId: "xt-skill-governance-\(UUID().uuidString)"
        )

        if result.ok {
            skillGovernanceActionStatusLine = "skill_governance_action=pin skill=\(entry.skillID) scope=\(scope.hubScope) status=ok sha=\(shortSHA(packageSHA256))"
            refreshSkillsCompatibilitySnapshot(force: true)
            refreshResolvedSkillsCacheForCurrentSelection()
            refreshUnifiedDoctorReport(force: true)

            var lines = [
                "Pinned \(subject)",
                "Scope: \(scope.hubScope)",
                "Package: \(shortSHA(packageSHA256))"
            ]
            if let previous = nonEmptyString(result.previousPackageSHA256) {
                lines.append("Previous package: \(shortSHA(previous))")
            }
            showAlert(title: "Pin Governed Skill", message: lines.joined(separator: "\n"))
        } else {
            let reason = normalizedDeepLinkToken(result.reasonCode) ?? "pin_failed"
            skillGovernanceActionStatusLine = "skill_governance_action=pin skill=\(entry.skillID) scope=\(scope.hubScope) status=failed reason=\(reason)"
            showAlert(
                title: "Pin Governed Skill",
                message: "Failed to pin \(subject)\nScope: \(scope.hubScope)\nReason: \(reason)"
            )
        }
    }

    private func openSkillGovernanceSurface(
        for entry: AXSkillGovernanceSurfaceEntry,
        title: String,
        detail: String
    ) {
        if let projectScope = selectedProjectBaselineInstallScope() {
            requestProjectSettingsFocus(
                projectId: projectScope.projectId,
                destination: .overview,
                title: title,
                detail: detail
            )
        } else {
            openGovernanceRouteURL(
                XTDeepLinkURLBuilder.settingsURL(
                    sectionId: "diagnostics",
                    title: title,
                    detail: detail
                )
            )
        }
    }

    private func openGovernanceRouteURL(_ url: URL?) {
        guard let url else { return }
        openURLInWorkspace(url)
    }

    private func governanceSurfaceSubject(_ entry: AXSkillGovernanceSurfaceEntry) -> String {
        let trimmedName = entry.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSkillID = entry.skillID.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty, !trimmedSkillID.isEmpty, trimmedName.caseInsensitiveCompare(trimmedSkillID) != .orderedSame {
            return "\(trimmedName) (\(trimmedSkillID))"
        }
        return trimmedName.isEmpty ? trimmedSkillID : trimmedName
    }

    private func governanceSurfaceDetail(
        _ entry: AXSkillGovernanceSurfaceEntry,
        fallback: String
    ) -> String {
        let subject = governanceSurfaceSubject(entry)
        let whyNot = normalizedDeepLinkToken(entry.whyNotRunnable) ?? ""
        let installHint = normalizedDeepLinkToken(entry.installHint) ?? ""
        let state = normalizedDeepLinkToken(entry.stateLabel) ?? "unknown"

        var parts = ["\(subject) · state=\(state)"]
        if !whyNot.isEmpty {
            parts.append("why_not=\(whyNot)")
        }
        if !installHint.isEmpty {
            parts.append("hint=\(installHint)")
        }
        if parts.count == 1 && whyNot.isEmpty && installHint.isEmpty {
            parts.append(fallback)
        } else if !fallback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append(fallback)
        }
        return parts.joined(separator: " · ")
    }

    private func normalizedSkillGovernanceSurfaceAction(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func uniqueDuplicatedSkillURL(for folderURL: URL) -> URL {
        let parent = folderURL.deletingLastPathComponent()
        let baseName = folderURL.lastPathComponent
        let ext = folderURL.pathExtension
        let stem = ext.isEmpty ? baseName : String(baseName.dropLast(ext.count + 1))

        var candidateIndex = 0
        while true {
            let suffix = candidateIndex == 0 ? "-copy" : "-copy-\(candidateIndex + 1)"
            let candidateName = ext.isEmpty ? "\(stem)\(suffix)" : "\(stem)\(suffix).\(ext)"
            let candidate = parent.appendingPathComponent(candidateName, isDirectory: true)
            if !FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            candidateIndex += 1
        }
    }

    private func confirmReplaceSkill(name: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Skill already exists"
        alert.informativeText = "Replace \"\(name)\"?"
        alert.addButton(withTitle: "Replace")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func confirmRemoveSkill(name: String, path: String) -> Bool {
        let title = "Remove Skill"
        let message = "Remove \"\(name)\"?\n\n\(path)\n\nThis deletes the local skill folder from disk."
        if let override = skillRemovalConfirmationOverrideForTesting {
            return override(title, message)
        }

        activateAppForModalPresentation()
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func confirmDefaultAgentBaselineInstall(title: String, message: String) -> Bool {
        if let override = baselineInstallConfirmationOverrideForTesting {
            return override(title, message)
        }
        activateAppForModalPresentation()
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "Install")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func promptForSkillRename(title: String, message: String, initialValue: String) -> String? {
        if let override = skillRenamePromptOverrideForTesting {
            return override(title, message, initialValue)
        }

        activateAppForModalPresentation()
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.stringValue = initialValue
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.accessoryView = field
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return nil }
        return field.stringValue
    }

    private func showAlert(title: String, message: String) {
        if let override = alertPresenterOverrideForTesting {
            override(title, message)
            return
        }
        activateAppForModalPresentation()
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }

    private func parseSkillMarkdownFrontmatter(_ text: String) -> [String: String] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        guard normalized.hasPrefix("---\n") else { return [:] }
        let remainder = String(normalized.dropFirst(4))
        guard let closingRange = remainder.range(of: "\n---\n") ?? remainder.range(of: "\n---") else {
            return [:]
        }
        let block = remainder[..<closingRange.lowerBound]
        var values: [String: String] = [:]
        for line in block.split(separator: "\n", omittingEmptySubsequences: false) {
            let raw = String(line)
            guard let separator = raw.firstIndex(of: ":") else { continue }
            let key = raw[..<separator].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = raw[raw.index(after: separator)...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            if !key.isEmpty, !value.isEmpty {
                values[key] = value
            }
        }
        return values
    }

    private func extractSkillMarkdownHeading(_ text: String) -> String? {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        var inFrontmatter = false
        for line in normalized.split(separator: "\n", omittingEmptySubsequences: false) {
            let raw = String(line)
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed == "---" {
                inFrontmatter.toggle()
                continue
            }
            guard !inFrontmatter else { continue }
            if trimmed.hasPrefix("# ") {
                return nonEmptyString(String(trimmed.dropFirst(2)))
            }
        }
        return nil
    }

    private func inferLocalSkillEntrypoint(in folderURL: URL) -> (runtime: String, command: String, args: [String]) {
        let candidates: [(String, String, [String])] = [
            ("node", "node", ["dist/main.js"]),
            ("node", "node", ["main.js"]),
            ("python", "python3", ["dist/main.py"]),
            ("python", "python3", ["main.py"]),
            ("shell", "bash", ["run.sh"]),
            ("shell", "bash", ["main.sh"]),
        ]
        for candidate in candidates {
            let relativePath = candidate.2.first ?? ""
            guard !relativePath.isEmpty else { continue }
            let targetURL = folderURL.appendingPathComponent(relativePath)
            if FileManager.default.fileExists(atPath: targetURL.path) {
                return candidate
            }
        }
        return ("text", "cat", ["SKILL.md"])
    }

    func setProjectRoleModel(role: AXRole, modelId: String?) {
        guard let ctx = projectContext else { return }
        setProjectRoleModel(for: ctx, role: role, modelId: modelId)
    }

    func setProjectRoleModel(
        for ctx: AXProjectContext,
        role: AXRole,
        modelId: String?
    ) {
        guard var cfg = editableProjectConfig(for: ctx) else { return }
        guard projectModelSwitchChanged(current: cfg.modelOverride(for: role), next: modelId) else { return }
        let projectId = AXProjectRegistryStore.projectId(forRoot: ctx.root)
        _ = AXMemoryLifecycleStore.writeSessionSummaryCapsule(ctx: ctx, reason: "ai_switch")
        cfg = cfg.settingModelOverride(role: role, modelId: modelId)
        syncProjectConfigIfCurrent(cfg, for: ctx)
        try? AXProjectStore.saveConfig(cfg, for: ctx)
        syncLegacyProjectRoleModel(
            role: role,
            projectId: projectId,
            ctx: ctx,
            modelId: modelId
        )
        noteRemoteMemoryRouteOrModelPreferenceChanged(projectId: projectId)
    }

    func setProjectRoleModelOverride(projectId: String, role: AXRole, modelId: String?) {
        guard let ctx = projectContext(for: projectId) else { return }
        guard var cfg = try? AXProjectStore.loadOrCreateConfig(for: ctx) else { return }
        guard projectModelSwitchChanged(current: cfg.modelOverride(for: role), next: modelId) else { return }
        _ = AXMemoryLifecycleStore.writeSessionSummaryCapsule(ctx: ctx, reason: "ai_switch")
        cfg.setModelOverride(role: role, modelId: modelId)
        try? AXProjectStore.saveConfig(cfg, for: ctx)
        syncLegacyProjectRoleModel(role: role, projectId: projectId, ctx: ctx, modelId: modelId)
        syncProjectConfigIfCurrent(cfg, for: ctx)
        noteRemoteMemoryRouteOrModelPreferenceChanged(projectId: projectId)
    }

    private func syncLegacyProjectRoleModel(
        role: AXRole,
        projectId: String?,
        ctx: AXProjectContext,
        modelId: String?
    ) {
        guard role == .coder else { return }

        let trimmedOverride = (modelId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackGlobal = settingsStore.settings.assignment(for: role).model?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let resolvedModelId = trimmedOverride.isEmpty ? fallbackGlobal : trimmedOverride
        guard !resolvedModelId.isEmpty else { return }

        let modelInfo = XTModelCatalog.modelInfo(
            for: resolvedModelId,
            preferLocalHint: resolvedModelId.lowercased().contains("local")
                || resolvedModelId.lowercased().contains("mlx")
        )
        let standardizedRootPath = ctx.root.standardizedFileURL.path

        for project in legacyMultiProjectManager.projects {
            let boundProjectId = project.registeredProjectId?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let boundRootPath = project.registeredProjectRootPath?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let matchesProjectId = !(projectId ?? "").isEmpty && boundProjectId == projectId
            let matchesRoot = !boundRootPath.isEmpty
                && URL(fileURLWithPath: boundRootPath, isDirectory: true).standardizedFileURL.path == standardizedRootPath
            guard matchesProjectId || matchesRoot else { continue }
            project.currentModel = modelInfo
        }
    }

    private func isCurrentProjectContext(_ ctx: AXProjectContext) -> Bool {
        projectContext?.root.standardizedFileURL.path == ctx.root.standardizedFileURL.path
    }

    private func editableProjectConfig(for ctx: AXProjectContext) -> AXProjectConfig? {
        if isCurrentProjectContext(ctx), let projectConfig {
            return projectConfig
        }
        return try? AXProjectStore.loadOrCreateConfig(for: ctx)
    }

    private func runtimeSurfaceRemoteOverrideSnapshot(for ctx: AXProjectContext) -> AXProjectRuntimeSurfaceRemoteOverrideSnapshot? {
        isCurrentProjectContext(ctx) ? projectRemoteRuntimeSurfaceOverride : nil
    }

    private func syncProjectConfigIfCurrent(_ cfg: AXProjectConfig, for ctx: AXProjectContext) {
        if isCurrentProjectContext(ctx) {
            projectConfig = cfg
        }
    }

    func setProjectTrustedAutomationBinding(
        mode: AXProjectAutomationMode,
        deviceId: String,
        deviceToolGroups: [String]? = nil,
        workspaceBindingHash: String? = nil
    ) {
        guard let ctx = projectContext else { return }
        setProjectTrustedAutomationBinding(
            for: ctx,
            mode: mode,
            deviceId: deviceId,
            deviceToolGroups: deviceToolGroups,
            workspaceBindingHash: workspaceBindingHash
        )
    }

    func setProjectTrustedAutomationBinding(
        for ctx: AXProjectContext,
        mode: AXProjectAutomationMode,
        deviceId: String,
        deviceToolGroups: [String]? = nil,
        workspaceBindingHash: String? = nil
    ) {
        guard var cfg = editableProjectConfig(for: ctx) else { return }
        let resolvedHash = workspaceBindingHash ?? xtTrustedAutomationWorkspaceHash(forProjectRoot: ctx.root)
        cfg = cfg.settingTrustedAutomationBinding(
            mode: mode,
            deviceId: deviceId,
            deviceToolGroups: deviceToolGroups,
            workspaceBindingHash: resolvedHash
        )
        syncProjectConfigIfCurrent(cfg, for: ctx)
        try? AXProjectStore.saveConfig(cfg, for: ctx)
    }

    func setProjectHubMemoryPreference(enabled: Bool) {
        guard let ctx = projectContext else { return }
        setProjectHubMemoryPreference(for: ctx, enabled: enabled)
    }

    func setProjectHubMemoryPreference(
        for ctx: AXProjectContext,
        enabled: Bool
    ) {
        guard var cfg = editableProjectConfig(for: ctx) else { return }
        cfg = cfg.settingHubMemoryPreference(enabled: enabled)
        syncProjectConfigIfCurrent(cfg, for: ctx)
        try? AXProjectStore.saveConfig(cfg, for: ctx)
    }

    func setSupervisorRecentRawContextProfile(_ profile: XTSupervisorRecentRawContextProfile) {
        let current = settingsStore.settings.supervisorRecentRawContextProfile
        guard current != profile else { return }
        settingsStore.settings = settingsStore.settings.setting(
            supervisorRecentRawContextProfile: profile
        )
        settingsStore.save()
        announceSupervisorSettingsNotice(
            XTSettingsChangeNoticeBuilder.supervisorRecentRawContext(
                profile: profile,
                privacyMode: settingsStore.settings.supervisorPrivacyMode
            )
        )
    }

    func setSupervisorReviewMemoryDepthProfile(_ profile: XTSupervisorReviewMemoryDepthProfile) {
        let current = settingsStore.settings.supervisorReviewMemoryDepthProfile
        guard current != profile else { return }
        settingsStore.settings = settingsStore.settings.setting(
            supervisorReviewMemoryDepthProfile: profile
        )
        settingsStore.save()
        announceSupervisorSettingsNotice(
            XTSettingsChangeNoticeBuilder.supervisorReviewMemoryDepth(profile)
        )
    }

    func setInterfaceLanguage(_ language: XTInterfaceLanguage) {
        let current = settingsStore.settings.interfaceLanguage
        guard current != language else { return }
        settingsStore.settings = settingsStore.settings.setting(
            interfaceLanguage: language
        )
        settingsStore.save()
        announceSupervisorSettingsNotice(
            XTSettingsChangeNoticeBuilder.interfaceLanguage(language)
        )
    }

    func setSupervisorWorkMode(_ mode: XTSupervisorWorkMode) {
        let current = settingsStore.settings.supervisorWorkMode
        guard current != mode else { return }
        settingsStore.settings = settingsStore.settings.setting(
            supervisorWorkMode: mode
        )
        settingsStore.save()
        announceSupervisorSettingsNotice(
            XTSettingsChangeNoticeBuilder.supervisorWorkMode(mode)
        )
    }

    func setSupervisorPrivacyMode(_ mode: XTPrivacyMode) {
        let current = settingsStore.settings.supervisorPrivacyMode
        guard current != mode else { return }
        settingsStore.settings = settingsStore.settings.setting(
            supervisorPrivacyMode: mode
        )
        settingsStore.save()
        announceSupervisorSettingsNotice(
            XTSettingsChangeNoticeBuilder.supervisorPrivacyMode(
                mode,
                configuredProfile: settingsStore.settings.supervisorRecentRawContextProfile
            )
        )
    }

    func setDefaultToolSandboxMode(_ mode: ToolSandboxMode) {
        let current = ToolExecutor.sandboxMode()
        guard current != mode else { return }
        ToolExecutor.setSandboxMode(mode)
        announceCurrentProjectSettingsNotice(
            XTSettingsChangeNoticeBuilder.defaultToolSandboxMode(mode)
        )
    }

    func setSupervisorCalendarReminderPreferences(
        _ preferences: SupervisorCalendarReminderPreferences
    ) {
        settingsStore.settings = settingsStore.settings.setting(
            supervisorCalendarReminders: preferences
        )
        settingsStore.save()
    }

    func setProjectContextAssembly(
        projectRecentDialogueProfile: AXProjectRecentDialogueProfile? = nil,
        projectContextDepthProfile: AXProjectContextDepthProfile? = nil
    ) {
        guard let ctx = projectContext else { return }
        setProjectContextAssembly(
            for: ctx,
            projectRecentDialogueProfile: projectRecentDialogueProfile,
            projectContextDepthProfile: projectContextDepthProfile
        )
    }

    func setProjectContextAssembly(
        for ctx: AXProjectContext,
        projectRecentDialogueProfile: AXProjectRecentDialogueProfile? = nil,
        projectContextDepthProfile: AXProjectContextDepthProfile? = nil
    ) {
        guard var cfg = editableProjectConfig(for: ctx) else { return }
        cfg = cfg.settingProjectContextAssembly(
            projectRecentDialogueProfile: projectRecentDialogueProfile,
            projectContextDepthProfile: projectContextDepthProfile
        )
        syncProjectConfigIfCurrent(cfg, for: ctx)
        try? AXProjectStore.saveConfig(cfg, for: ctx)
        AXProjectStore.appendRawLog(
            [
                "type": "project_context_assembly",
                "action": "update",
                "created_at": Date().timeIntervalSince1970,
                "project_id": AXProjectRegistryStore.projectId(forRoot: ctx.root),
                "project_recent_dialogue_profile": cfg.projectRecentDialogueProfile.rawValue,
                "project_context_depth_profile": cfg.projectContextDepthProfile.rawValue,
            ],
            for: ctx
        )
    }

    private func announceSupervisorSettingsNotice(_ notice: XTSettingsChangeNotice) {
        _ = SupervisorManager.shared.appendLocalAssistantNotice(
            "Supervisor 设置已更新：\(notice.detail)"
        )
    }

    private func announceCurrentProjectSettingsNotice(_ notice: XTSettingsChangeNotice) {
        guard let selectedProjectId,
              selectedProjectId != AXProjectRegistry.globalHomeId,
              let ctx = projectContext(for: selectedProjectId),
              let session = sessionForProjectId(selectedProjectId) else {
            return
        }
        _ = session.appendLocalAssistantNotice(
            "XT Runtime 设置已更新：\(notice.detail)",
            ctx: ctx
        )
    }

    func setProjectGovernedReadableRoots(paths: [String]) {
        guard let ctx = projectContext else { return }
        setProjectGovernedReadableRoots(for: ctx, paths: paths)
    }

    func setProjectGovernedReadableRoots(
        for ctx: AXProjectContext,
        paths: [String]
    ) {
        guard var cfg = editableProjectConfig(for: ctx) else { return }
        cfg = cfg.settingGovernedReadableRoots(paths: paths, projectRoot: ctx.root)
        syncProjectConfigIfCurrent(cfg, for: ctx)
        try? AXProjectStore.saveConfig(cfg, for: ctx)
        AXProjectStore.appendRawLog(
            [
                "type": "project_governed_read_roots",
                "action": "update",
                "created_at": Date().timeIntervalSince1970,
                "project_id": AXProjectRegistryStore.projectId(forRoot: ctx.root),
                "root_count": cfg.governedReadableRoots.count,
                "roots": cfg.governedReadableRoots,
            ],
            for: ctx
        )
    }

    func setProjectGovernedAutoApproveLocalToolCalls(enabled: Bool) {
        guard let ctx = projectContext else { return }
        setProjectGovernedAutoApproveLocalToolCalls(for: ctx, enabled: enabled)
    }

    func setProjectGovernedAutoApproveLocalToolCalls(
        for ctx: AXProjectContext,
        enabled: Bool
    ) {
        guard var cfg = editableProjectConfig(for: ctx) else { return }
        cfg = cfg.settingGovernedAutoApproveLocalToolCalls(enabled: enabled)
        syncProjectConfigIfCurrent(cfg, for: ctx)
        try? AXProjectStore.saveConfig(cfg, for: ctx)
        AXProjectStore.appendRawLog(
            [
                "type": "project_governed_auto_approve",
                "action": "update",
                "created_at": Date().timeIntervalSince1970,
                "project_id": AXProjectRegistryStore.projectId(forRoot: ctx.root),
                "enabled": enabled,
            ],
            for: ctx
        )
    }

    func applyProjectGovernanceTemplate(_ template: AXProjectGovernanceTemplate) {
        guard template != .custom else { return }
        guard let ctx = projectContext else { return }
        applyProjectGovernanceTemplate(template, for: ctx)
    }

    func applyProjectGovernanceTemplate(
        _ template: AXProjectGovernanceTemplate,
        for ctx: AXProjectContext
    ) {
        guard template != .custom else { return }
        guard var cfg = editableProjectConfig(for: ctx) else { return }
        let now = Date()
        cfg = cfg.settingGovernanceTemplate(
            template,
            projectRoot: ctx.root,
            now: now
        )
        let resolved = xtResolveProjectGovernance(
            projectRoot: ctx.root,
            config: cfg,
            remoteOverride: runtimeSurfaceRemoteOverrideSnapshot(for: ctx)
        )
        let governanceTruth = XTGovernanceTruthPresentation.truthLine(
            configuredExecutionTier: resolved.configuredBundle.executionTier.rawValue,
            effectiveExecutionTier: resolved.effectiveBundle.executionTier.rawValue,
            configuredSupervisorTier: resolved.configuredBundle.supervisorInterventionTier.rawValue,
            effectiveSupervisorTier: resolved.effectiveBundle.supervisorInterventionTier.rawValue,
            reviewPolicyMode: resolved.effectiveBundle.reviewPolicyMode.rawValue,
            progressHeartbeatSeconds: resolved.effectiveBundle.schedule.progressHeartbeatSeconds,
            reviewPulseSeconds: resolved.effectiveBundle.schedule.reviewPulseSeconds,
            brainstormReviewSeconds: resolved.effectiveBundle.schedule.brainstormReviewSeconds,
            compatSource: resolved.compatSource.rawValue
        ) ?? ""

        syncProjectConfigIfCurrent(cfg, for: ctx)
        try? AXProjectStore.saveConfig(cfg, for: ctx)
        AXProjectStore.appendRawLog(
            [
                "type": "project_governance_template",
                "legacy_type": "project_autonomy_profile",
                "action": "apply",
                "created_at": now.timeIntervalSince1970,
                "project_id": AXProjectRegistryStore.projectId(forRoot: ctx.root),
                "template": template.rawValue,
                "profile": template.rawValue,
                "execution_tier": cfg.executionTier.rawValue,
                "configured_execution_tier": resolved.configuredBundle.executionTier.rawValue,
                "effective_execution_tier": resolved.effectiveBundle.executionTier.rawValue,
                "supervisor_intervention_tier": cfg.supervisorInterventionTier.rawValue,
                "configured_supervisor_tier": resolved.configuredBundle.supervisorInterventionTier.rawValue,
                "effective_supervisor_tier": resolved.effectiveBundle.supervisorInterventionTier.rawValue,
                "effective_supervisor_intervention_tier": resolved.effectiveBundle.supervisorInterventionTier.rawValue,
                "effective_supervisor_work_order_depth": resolved.supervisorAdaptation.effectiveWorkOrderDepth.rawValue,
                "review_policy_mode": cfg.reviewPolicyMode.rawValue,
                "project_recent_dialogue_profile": cfg.projectRecentDialogueProfile.rawValue,
                "project_context_depth_profile": cfg.projectContextDepthProfile.rawValue,
                "governance_truth": governanceTruth,
                "runtime_surface_configured": cfg.runtimeSurfaceMode.rawValue,
                "runtime_surface_preset": cfg.runtimeSurfaceMode.rawValue,
                "surface_preset": cfg.runtimeSurfaceMode.rawValue,
                "local_auto_approve": cfg.governedAutoApproveLocalToolCalls,
                "prefer_hub_memory": cfg.preferHubMemory,
                "runtime_surface_effective": resolved.effectiveRuntimeSurface.effectiveMode.rawValue,
                "runtime_surface_hub_override": resolved.effectiveRuntimeSurface.hubOverrideMode.rawValue,
                "runtime_surface_local_override": resolved.effectiveRuntimeSurface.localOverrideMode.rawValue,
                "runtime_surface_remote_override": resolved.effectiveRuntimeSurface.remoteOverrideMode.rawValue,
                "runtime_surface_remote_override_source": resolved.effectiveRuntimeSurface.remoteOverrideSource,
                "runtime_surface_remote_override_updated_at_ms": resolved.effectiveRuntimeSurface.remoteOverrideUpdatedAtMs,
                "runtime_surface_ttl_sec": cfg.runtimeSurfaceTTLSeconds,
                "runtime_surface_remaining_sec": resolved.effectiveRuntimeSurface.remainingSeconds,
                "runtime_surface_expired": resolved.effectiveRuntimeSurface.expired,
                "runtime_surface_kill_switch_engaged": resolved.effectiveRuntimeSurface.killSwitchEngaged,
                "effective_runtime_surface": resolved.effectiveRuntimeSurface.effectiveMode.rawValue,
                "effective_runtime_surface_hub_override": resolved.effectiveRuntimeSurface.hubOverrideMode.rawValue,
                "effective_mode": resolved.effectiveRuntimeSurface.effectiveMode.rawValue,
                "effective_hub_override_mode": resolved.effectiveRuntimeSurface.hubOverrideMode.rawValue,
                "trusted_automation_state": resolved.trustedAutomationStatus.state.rawValue,
                "invalid_reasons": resolved.validation.invalidReasons,
                "warning_reasons": resolved.validation.warningReasons,
            ],
            for: ctx
        )
    }

    @available(*, deprecated, message: "Use applyProjectGovernanceTemplate(_:)")
    func applyProjectAutonomyProfile(_ profile: AXProjectGovernanceTemplate) {
        applyProjectGovernanceTemplate(profile)
    }

    func setProjectAutomationSelfIteration(
        enabled: Bool? = nil,
        maxAutoRetryDepth: Int? = nil
    ) {
        guard let ctx = projectContext else { return }
        setProjectAutomationSelfIteration(
            for: ctx,
            enabled: enabled,
            maxAutoRetryDepth: maxAutoRetryDepth
        )
    }

    func setProjectAutomationSelfIteration(
        for ctx: AXProjectContext,
        enabled: Bool? = nil,
        maxAutoRetryDepth: Int? = nil
    ) {
        guard var cfg = editableProjectConfig(for: ctx) else { return }
        cfg = cfg.settingAutomationSelfIteration(
            enabled: enabled,
            maxAutoRetryDepth: maxAutoRetryDepth
        )
        syncProjectConfigIfCurrent(cfg, for: ctx)
        try? AXProjectStore.saveConfig(cfg, for: ctx)
    }

    func setProjectRuntimeSurfacePolicy(
        mode: AXProjectRuntimeSurfaceMode? = nil,
        allowDeviceTools: Bool? = nil,
        allowBrowserRuntime: Bool? = nil,
        allowConnectorActions: Bool? = nil,
        allowExtensions: Bool? = nil,
        ttlSeconds: Int? = nil,
        hubOverrideMode: AXProjectRuntimeSurfaceHubOverrideMode? = nil
    ) {
        guard let ctx = projectContext else { return }
        setProjectRuntimeSurfacePolicy(
            for: ctx,
            mode: mode,
            allowDeviceTools: allowDeviceTools,
            allowBrowserRuntime: allowBrowserRuntime,
            allowConnectorActions: allowConnectorActions,
            allowExtensions: allowExtensions,
            ttlSeconds: ttlSeconds,
            hubOverrideMode: hubOverrideMode
        )
    }

    func setProjectRuntimeSurfacePolicy(
        for ctx: AXProjectContext,
        mode: AXProjectRuntimeSurfaceMode? = nil,
        allowDeviceTools: Bool? = nil,
        allowBrowserRuntime: Bool? = nil,
        allowConnectorActions: Bool? = nil,
        allowExtensions: Bool? = nil,
        ttlSeconds: Int? = nil,
        hubOverrideMode: AXProjectRuntimeSurfaceHubOverrideMode? = nil
    ) {
        guard var cfg = editableProjectConfig(for: ctx) else { return }
        let remoteOverride = runtimeSurfaceRemoteOverrideSnapshot(for: ctx)
        let now = Date()
        let previous = cfg.effectiveRuntimeSurfacePolicy(
            now: now,
            remoteOverride: remoteOverride
        )
        cfg = cfg.settingRuntimeSurfacePolicy(
            mode: mode,
            allowDeviceTools: allowDeviceTools,
            allowBrowserRuntime: allowBrowserRuntime,
            allowConnectorActions: allowConnectorActions,
            allowExtensions: allowExtensions,
            ttlSeconds: ttlSeconds,
            hubOverrideMode: hubOverrideMode,
            updatedAt: now
        )
        let effective = cfg.effectiveRuntimeSurfacePolicy(
            now: now,
            remoteOverride: remoteOverride
        )

        syncProjectConfigIfCurrent(cfg, for: ctx)
        try? AXProjectStore.saveConfig(cfg, for: ctx)
        AXProjectStore.appendRawLog(
            [
                "type": "project_autonomy_policy",
                "action": "update",
                "created_at": now.timeIntervalSince1970,
                "project_id": AXProjectRegistryStore.projectId(forRoot: ctx.root),
                "runtime_surface": cfg.runtimeSurfaceMode.rawValue,
                "runtime_surface_configured": cfg.runtimeSurfaceMode.rawValue,
                "effective_runtime_surface": effective.effectiveMode.rawValue,
                "previous_effective_runtime_surface": previous.effectiveMode.rawValue,
                "runtime_surface_hub_override": effective.hubOverrideMode.rawValue,
                "runtime_surface_local_override": effective.localOverrideMode.rawValue,
                "runtime_surface_remote_override": effective.remoteOverrideMode.rawValue,
                "runtime_surface_remote_override_source": effective.remoteOverrideSource,
                "runtime_surface_remote_override_updated_at_ms": effective.remoteOverrideUpdatedAtMs,
                "runtime_surface_ttl_sec": cfg.runtimeSurfaceTTLSeconds,
                "runtime_surface_remaining_sec": effective.remainingSeconds,
                "runtime_surface_expired": effective.expired,
                "runtime_surface_kill_switch_engaged": effective.killSwitchEngaged,
                "mode": cfg.runtimeSurfaceMode.rawValue,
                "effective_mode": effective.effectiveMode.rawValue,
                "previous_effective_mode": previous.effectiveMode.rawValue,
                "allow_device_tools": cfg.runtimeSurfaceAllowDeviceTools,
                "allow_browser_runtime": cfg.runtimeSurfaceAllowBrowserRuntime,
                "allow_connector_actions": cfg.runtimeSurfaceAllowConnectorActions,
                "allow_extensions": cfg.runtimeSurfaceAllowExtensions,
                "ttl_sec": cfg.runtimeSurfaceTTLSeconds,
                "remaining_sec": effective.remainingSeconds,
                "hub_override_mode": cfg.runtimeSurfaceHubOverrideMode.rawValue,
                "effective_hub_override_mode": effective.hubOverrideMode.rawValue,
                "remote_override_mode": effective.remoteOverrideMode.rawValue,
                "remote_override_source": effective.remoteOverrideSource,
                "audit_ref": "audit-xt-runtime-surface-policy-\(Int(now.timeIntervalSince1970))"
            ],
            for: ctx
        )
    }

    @available(*, deprecated, message: "Use setProjectRuntimeSurfacePolicy(mode:allowDeviceTools:allowBrowserRuntime:allowConnectorActions:allowExtensions:ttlSeconds:hubOverrideMode:)")
    func setProjectAutonomyPolicy(
        mode: AXProjectRuntimeSurfaceMode? = nil,
        allowDeviceTools: Bool? = nil,
        allowBrowserRuntime: Bool? = nil,
        allowConnectorActions: Bool? = nil,
        allowExtensions: Bool? = nil,
        ttlSeconds: Int? = nil,
        hubOverrideMode: AXProjectRuntimeSurfaceHubOverrideMode? = nil
    ) {
        setProjectRuntimeSurfacePolicy(
            mode: mode,
            allowDeviceTools: allowDeviceTools,
            allowBrowserRuntime: allowBrowserRuntime,
            allowConnectorActions: allowConnectorActions,
            allowExtensions: allowExtensions,
            ttlSeconds: ttlSeconds,
            hubOverrideMode: hubOverrideMode
        )
    }

    func resolvedProjectRuntimeSurfacePolicy(
        config: AXProjectConfig? = nil,
        now: Date = Date()
    ) -> AXProjectRuntimeSurfaceEffectivePolicy {
        let resolvedConfig = config ?? projectConfig ?? .default(forProjectRoot: projectContext?.root ?? URL(fileURLWithPath: "/"))
        return resolvedConfig.effectiveRuntimeSurfacePolicy(
            now: now,
            remoteOverride: projectRemoteRuntimeSurfaceOverride
        )
    }

    @available(*, deprecated, message: "Use resolvedProjectRuntimeSurfacePolicy(config:now:)")
    func resolvedProjectAutonomyPolicy(
        config: AXProjectConfig? = nil,
        now: Date = Date()
    ) -> AXProjectRuntimeSurfaceEffectivePolicy {
        resolvedProjectRuntimeSurfacePolicy(
            config: config,
            now: now
        )
    }

    func setProjectGovernance(
        executionTier: AXProjectExecutionTier? = nil,
        supervisorInterventionTier: AXProjectSupervisorInterventionTier? = nil,
        reviewPolicyMode: AXProjectReviewPolicyMode? = nil,
        progressHeartbeatSeconds: Int? = nil,
        reviewPulseSeconds: Int? = nil,
        brainstormReviewSeconds: Int? = nil,
        eventDrivenReviewEnabled: Bool? = nil,
        eventReviewTriggers: [AXProjectReviewTrigger]? = nil
    ) {
        guard let ctx = projectContext else { return }
        setProjectGovernance(
            for: ctx,
            executionTier: executionTier,
            supervisorInterventionTier: supervisorInterventionTier,
            reviewPolicyMode: reviewPolicyMode,
            progressHeartbeatSeconds: progressHeartbeatSeconds,
            reviewPulseSeconds: reviewPulseSeconds,
            brainstormReviewSeconds: brainstormReviewSeconds,
            eventDrivenReviewEnabled: eventDrivenReviewEnabled,
            eventReviewTriggers: eventReviewTriggers
        )
    }

    func setProjectGovernance(
        for ctx: AXProjectContext,
        executionTier: AXProjectExecutionTier? = nil,
        supervisorInterventionTier: AXProjectSupervisorInterventionTier? = nil,
        reviewPolicyMode: AXProjectReviewPolicyMode? = nil,
        progressHeartbeatSeconds: Int? = nil,
        reviewPulseSeconds: Int? = nil,
        brainstormReviewSeconds: Int? = nil,
        eventDrivenReviewEnabled: Bool? = nil,
        eventReviewTriggers: [AXProjectReviewTrigger]? = nil
    ) {
        guard var cfg = editableProjectConfig(for: ctx) else { return }
        cfg = cfg.settingProjectGovernance(
            executionTier: executionTier,
            supervisorInterventionTier: supervisorInterventionTier,
            reviewPolicyMode: reviewPolicyMode,
            progressHeartbeatSeconds: progressHeartbeatSeconds,
            reviewPulseSeconds: reviewPulseSeconds,
            brainstormReviewSeconds: brainstormReviewSeconds,
            eventDrivenReviewEnabled: eventDrivenReviewEnabled,
            eventReviewTriggers: eventReviewTriggers
        )
        if let executionTier {
            cfg = cfg.settingRuntimeSurfacePolicy(
                mode: executionTier.defaultRuntimeSurfacePreset,
                updatedAt: Date()
            )
        }
        let resolved = xtResolveProjectGovernance(
            projectRoot: ctx.root,
            config: cfg,
            remoteOverride: runtimeSurfaceRemoteOverrideSnapshot(for: ctx)
        )
        let governanceTruth = XTGovernanceTruthPresentation.truthLine(
            configuredExecutionTier: resolved.configuredBundle.executionTier.rawValue,
            effectiveExecutionTier: resolved.effectiveBundle.executionTier.rawValue,
            configuredSupervisorTier: resolved.configuredBundle.supervisorInterventionTier.rawValue,
            effectiveSupervisorTier: resolved.effectiveBundle.supervisorInterventionTier.rawValue,
            reviewPolicyMode: resolved.effectiveBundle.reviewPolicyMode.rawValue,
            progressHeartbeatSeconds: resolved.effectiveBundle.schedule.progressHeartbeatSeconds,
            reviewPulseSeconds: resolved.effectiveBundle.schedule.reviewPulseSeconds,
            brainstormReviewSeconds: resolved.effectiveBundle.schedule.brainstormReviewSeconds,
            compatSource: resolved.compatSource.rawValue
        ) ?? ""
        let governanceSnapshot: [String: Any] = [
            "configured_execution_tier": resolved.configuredBundle.executionTier.rawValue,
            "effective_execution_tier": resolved.effectiveBundle.executionTier.rawValue,
            "configured_supervisor_tier": resolved.configuredBundle.supervisorInterventionTier.rawValue,
            "effective_supervisor_tier": resolved.effectiveBundle.supervisorInterventionTier.rawValue,
            "effective_supervisor_intervention_tier": resolved.effectiveBundle.supervisorInterventionTier.rawValue,
            "effective_supervisor_work_order_depth": resolved.supervisorAdaptation.effectiveWorkOrderDepth.rawValue,
            "review_policy_mode": resolved.effectiveBundle.reviewPolicyMode.rawValue,
            "progress_heartbeat_sec": resolved.effectiveBundle.schedule.progressHeartbeatSeconds,
            "review_pulse_sec": resolved.effectiveBundle.schedule.reviewPulseSeconds,
            "brainstorm_review_sec": resolved.effectiveBundle.schedule.brainstormReviewSeconds,
            "event_driven_review_enabled": resolved.effectiveBundle.schedule.eventDrivenReviewEnabled,
            "event_review_triggers": resolved.effectiveBundle.schedule.eventReviewTriggers.map(\.rawValue),
            "compat_source": resolved.compatSource.rawValue,
            "governance_truth": governanceTruth
        ]

        syncProjectConfigIfCurrent(cfg, for: ctx)
        try? AXProjectStore.saveConfig(cfg, for: ctx)
        AXProjectStore.appendRawLog(
            [
                "type": "project_governance_bundle",
                "action": "update",
                "created_at": Date().timeIntervalSince1970,
                "project_id": AXProjectRegistryStore.projectId(forRoot: ctx.root),
                "execution_tier": cfg.executionTier.rawValue,
                "configured_execution_tier": resolved.configuredBundle.executionTier.rawValue,
                "effective_execution_tier": resolved.effectiveBundle.executionTier.rawValue,
                "supervisor_intervention_tier": cfg.supervisorInterventionTier.rawValue,
                "configured_supervisor_tier": resolved.configuredBundle.supervisorInterventionTier.rawValue,
                "effective_supervisor_tier": resolved.effectiveBundle.supervisorInterventionTier.rawValue,
                "effective_supervisor_intervention_tier": resolved.effectiveBundle.supervisorInterventionTier.rawValue,
                "effective_supervisor_work_order_depth": resolved.supervisorAdaptation.effectiveWorkOrderDepth.rawValue,
                "review_policy_mode": cfg.reviewPolicyMode.rawValue,
                "progress_heartbeat_sec": cfg.progressHeartbeatSeconds,
                "review_pulse_sec": cfg.reviewPulseSeconds,
                "brainstorm_review_sec": cfg.brainstormReviewSeconds,
                "event_driven_review_enabled": cfg.eventDrivenReviewEnabled,
                "event_review_triggers": cfg.eventReviewTriggers.map(\.rawValue),
                "compat_source": cfg.governanceCompatSource.rawValue,
                "governance_compat_source": resolved.compatSource.rawValue,
                "governance_truth": governanceTruth,
                "governance": governanceSnapshot,
                "runtime_surface_configured": cfg.runtimeSurfaceMode.rawValue,
                "runtime_surface_preset": cfg.runtimeSurfaceMode.rawValue,
                "effective_runtime_surface": resolved.effectiveRuntimeSurface.effectiveMode.rawValue,
                "runtime_surface_hub_override": resolved.effectiveRuntimeSurface.hubOverrideMode.rawValue,
                "runtime_surface_local_override": resolved.effectiveRuntimeSurface.localOverrideMode.rawValue,
                "runtime_surface_remote_override": resolved.effectiveRuntimeSurface.remoteOverrideMode.rawValue,
                "runtime_surface_remote_override_source": resolved.effectiveRuntimeSurface.remoteOverrideSource,
                "runtime_surface_remote_override_updated_at_ms": resolved.effectiveRuntimeSurface.remoteOverrideUpdatedAtMs,
                "runtime_surface_ttl_sec": cfg.runtimeSurfaceTTLSeconds,
                "runtime_surface_remaining_sec": resolved.effectiveRuntimeSurface.remainingSeconds,
                "runtime_surface_expired": resolved.effectiveRuntimeSurface.expired,
                "runtime_surface_kill_switch_engaged": resolved.effectiveRuntimeSurface.killSwitchEngaged,
                "surface_preset": cfg.runtimeSurfaceMode.rawValue,
                "invalid_reasons": resolved.validation.invalidReasons,
                "warning_reasons": resolved.validation.warningReasons,
                "should_fail_closed": resolved.validation.shouldFailClosed
            ],
            for: ctx
        )
    }

    func resolvedProjectGovernance(
        config: AXProjectConfig? = nil,
        legacyAutonomyLevel: AutonomyLevel? = nil
    ) -> AXProjectResolvedGovernanceState {
        let root = projectContext?.root ?? URL(fileURLWithPath: "/")
        let resolvedConfig = config ?? projectConfig ?? .default(forProjectRoot: root)
        return resolvedProjectGovernance(
            ctx: AXProjectContext(root: root),
            config: resolvedConfig,
            legacyAutonomyLevel: legacyAutonomyLevel,
            remoteOverride: projectRemoteRuntimeSurfaceOverride
        )
    }

    func resolvedProjectGovernance(
        for ctx: AXProjectContext,
        config: AXProjectConfig? = nil,
        legacyAutonomyLevel: AutonomyLevel? = nil
    ) -> AXProjectResolvedGovernanceState {
        let resolvedConfig: AXProjectConfig
        if isCurrentProjectContext(ctx), let projectConfig {
            resolvedConfig = projectConfig
        } else if let config {
            resolvedConfig = config
        } else {
            resolvedConfig = (try? AXProjectStore.loadOrCreateConfig(for: ctx)) ?? .default(forProjectRoot: ctx.root)
        }

        return resolvedProjectGovernance(
            ctx: ctx,
            config: resolvedConfig,
            legacyAutonomyLevel: legacyAutonomyLevel,
            remoteOverride: runtimeSurfaceRemoteOverrideSnapshot(for: ctx)
        )
    }

    func resolvedProjectGovernance(for project: AXProjectEntry) -> AXProjectResolvedGovernanceState {
        let root = URL(fileURLWithPath: project.rootPath, isDirectory: true)
        let config: AXProjectConfig
        let remoteOverride: AXProjectRuntimeSurfaceRemoteOverrideSnapshot?

        if selectedProjectId == project.projectId, let projectConfig {
            config = projectConfig
            remoteOverride = projectRemoteRuntimeSurfaceOverride
        } else {
            let ctx = AXProjectContext(root: root)
            config = (try? AXProjectStore.loadOrCreateConfig(for: ctx)) ?? .default(forProjectRoot: root)
            remoteOverride = nil
        }

        return resolvedProjectGovernance(
            ctx: AXProjectContext(root: root),
            config: config,
            remoteOverride: remoteOverride
        )
    }

    func resolvedProjectGovernance(for project: ProjectModel) -> AXProjectResolvedGovernanceState? {
        guard let ctx = project.governanceActivityContext(resolveProjectContext: projectContext(for:)) else {
            return nil
        }

        let bindingProjectId = project.registeredProjectBinding?.projectId
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let config: AXProjectConfig
        let remoteOverride: AXProjectRuntimeSurfaceRemoteOverrideSnapshot?

        if !bindingProjectId.isEmpty,
           selectedProjectId == bindingProjectId,
           projectContext?.root.standardizedFileURL == ctx.root.standardizedFileURL,
           let projectConfig {
            config = projectConfig
            remoteOverride = projectRemoteRuntimeSurfaceOverride
        } else {
            config = (try? AXProjectStore.loadOrCreateConfig(for: ctx)) ?? .default(forProjectRoot: ctx.root)
            remoteOverride = nil
        }

        return resolvedProjectGovernance(
            ctx: ctx,
            config: config,
            legacyAutonomyLevel: governanceResolverLegacyAutonomyLevel(for: project, config: config),
            remoteOverride: remoteOverride
        )
    }

    func governanceTemplatePreview(for project: AXProjectEntry) -> AXProjectGovernanceTemplatePreview {
        let root = URL(fileURLWithPath: project.rootPath, isDirectory: true)
        let config: AXProjectConfig
        let remoteOverride: AXProjectRuntimeSurfaceRemoteOverrideSnapshot?

        if selectedProjectId == project.projectId, let projectConfig {
            config = projectConfig
            remoteOverride = projectRemoteRuntimeSurfaceOverride
        } else {
            let ctx = AXProjectContext(root: root)
            config = (try? AXProjectStore.loadOrCreateConfig(for: ctx)) ?? .default(forProjectRoot: root)
            remoteOverride = nil
        }

        let resolved = resolvedProjectGovernance(
            ctx: AXProjectContext(root: root),
            config: config,
            remoteOverride: remoteOverride
        )
        return xtProjectGovernanceTemplatePresentation(
            projectRoot: root,
            config: config,
            resolved: resolved
        )
    }

    @available(*, deprecated, message: "Use governanceTemplatePreview(for:)")
    func autonomySwitchboardPresentation(for project: AXProjectEntry) -> AXProjectGovernanceTemplatePreview {
        governanceTemplatePreview(for: project)
    }

    func governanceTemplatePreview(for project: ProjectModel) -> AXProjectGovernanceTemplatePreview {
        if let ctx = project.governanceActivityContext(resolveProjectContext: projectContext(for:)) {
            let bindingProjectId = project.registeredProjectBinding?.projectId
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let config: AXProjectConfig
            let remoteOverride: AXProjectRuntimeSurfaceRemoteOverrideSnapshot?

            if !bindingProjectId.isEmpty,
               selectedProjectId == bindingProjectId,
               projectContext?.root.standardizedFileURL == ctx.root.standardizedFileURL,
               let projectConfig {
                config = projectConfig
                remoteOverride = projectRemoteRuntimeSurfaceOverride
            } else {
                config = (try? AXProjectStore.loadOrCreateConfig(for: ctx)) ?? .default(forProjectRoot: ctx.root)
                remoteOverride = nil
            }

            let resolved = resolvedProjectGovernance(
                ctx: ctx,
                config: config,
                legacyAutonomyLevel: governanceResolverLegacyAutonomyLevel(for: project, config: config),
                remoteOverride: remoteOverride
            )
            return xtProjectGovernanceTemplatePresentation(
                projectRoot: ctx.root,
                config: config,
                resolved: resolved
            )
        }

        let root = fallbackGovernanceTemplateProjectRoot(for: project)
        let config = xtGovernanceTemplateDraftConfig(
            projectRoot: root,
            template: xtGovernanceTemplateBaseline(
                for: project.executionTier,
                supervisorInterventionTier: project.supervisorInterventionTier
            ),
            executionTier: project.executionTier,
            supervisorInterventionTier: project.supervisorInterventionTier,
            reviewPolicyMode: project.reviewPolicyMode,
            progressHeartbeatSeconds: project.progressHeartbeatSeconds,
            reviewPulseSeconds: project.reviewPulseSeconds,
            brainstormReviewSeconds: project.brainstormReviewSeconds,
            eventDrivenReviewEnabled: project.eventDrivenReviewEnabled,
            eventReviewTriggers: project.eventReviewTriggers
        )
        let resolved = resolvedProjectGovernance(
            ctx: AXProjectContext(root: root),
            config: config
        )
        return xtProjectGovernanceTemplatePresentation(
            projectRoot: root,
            config: config,
            resolved: resolved
        )
    }

    @available(*, deprecated, message: "Use governanceTemplatePreview(for:)")
    func autonomySwitchboardPresentation(for project: ProjectModel) -> AXProjectGovernanceTemplatePreview {
        governanceTemplatePreview(for: project)
    }

    func governedAuthorityPresentation(for project: AXProjectEntry) -> AXProjectGovernedAuthorityPresentation {
        let root = URL(fileURLWithPath: project.rootPath, isDirectory: true)
        let config: AXProjectConfig
        if selectedProjectId == project.projectId, let projectConfig {
            config = projectConfig
        } else {
            let ctx = AXProjectContext(root: root)
            config = (try? AXProjectStore.loadOrCreateConfig(for: ctx)) ?? .default(forProjectRoot: root)
        }
        return xtProjectGovernedAuthorityPresentation(
            projectRoot: root,
            config: config
        )
    }

    private func fallbackGovernanceTemplateProjectRoot(for project: ProjectModel) -> URL {
        if let rootPath = project.registeredProjectRootPath?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !rootPath.isEmpty {
            return URL(fileURLWithPath: rootPath, isDirectory: true)
        }
        if let root = projectContext?.root {
            return root
        }
        return URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    }

    private func refreshProjectRemoteRuntimeSurfaceOverride(force: Bool) async {
        guard let ctx = projectContext else {
            projectRemoteRuntimeSurfaceOverride = nil
            nextProjectRuntimeSurfaceOverrideRefreshAt = .distantPast
            return
        }

        let now = Date()
        if !force, now < nextProjectRuntimeSurfaceOverrideRefreshAt {
            return
        }

        let projectId = AXProjectRegistryStore.projectId(forRoot: ctx.root)
        let remoteOverride = await HubIPCClient.requestProjectRuntimeSurfaceOverride(
            projectId: projectId,
            bypassCache: force
        )
        guard projectContext?.root.standardizedFileURL == ctx.root.standardizedFileURL else {
            return
        }
        projectRemoteRuntimeSurfaceOverride = remoteOverride
        nextProjectRuntimeSurfaceOverrideRefreshAt = now.addingTimeInterval(force ? 2.0 : 20.0)
    }

    func moveProjects(from offsets: IndexSet, to destination: Int) {
        var ordered = registry.sortedProjects()
        ordered.move(fromOffsets: offsets, toOffset: destination)

        var reg = registry
        var updated: [AXProjectEntry] = []
        updated.reserveCapacity(ordered.count)

        for (idx, item) in ordered.enumerated() {
            var cur = item
            cur.manualOrderIndex = idx
            updated.append(cur)
        }

        reg.projects = updated
        registry = reg
        if persistProjectRegistryChanges {
            AXProjectRegistryStore.save(reg)
        }
    }

    func reloadMemory() {
        Task { @MainActor in
            await loadSelectedProject()
        }
    }

    private func resolvedProjectGovernance(
        ctx: AXProjectContext,
        config: AXProjectConfig,
        legacyAutonomyLevel: AutonomyLevel? = nil,
        remoteOverride: AXProjectRuntimeSurfaceRemoteOverrideSnapshot? = nil
    ) -> AXProjectResolvedGovernanceState {
        let adaptationPolicy = AXProjectSupervisorAdaptationPolicy.default
        let strengthProfile = AXProjectAIStrengthAssessor.assess(
            ctx: ctx,
            adaptationPolicy: adaptationPolicy
        )
        let compatLegacyAutonomyLevel = config.governanceResolverLegacyAutonomyLevel(legacyAutonomyLevel)

        return xtResolveProjectGovernance(
            projectRoot: ctx.root,
            config: config,
            legacyAutonomyLevel: compatLegacyAutonomyLevel,
            remoteOverride: remoteOverride,
            projectAIStrengthProfile: strengthProfile,
            adaptationPolicy: adaptationPolicy
        )
    }

    private func governanceResolverLegacyAutonomyLevel(
        for project: ProjectModel,
        config: AXProjectConfig
    ) -> AutonomyLevel? {
        config.governanceResolverLegacyAutonomyLevel(project.autonomyLevel)
    }

    private func loadSelectedProject() async {
        guard let root = projectRoot else {
            projectContext = nil
            memory = nil
            usageSummary = .empty()
            projectConfig = nil
            projectRemoteRuntimeSurfaceOverride = nil
            nextProjectSnapshotRefreshAt = .distantPast
            nextProjectRuntimeSurfaceOverrideRefreshAt = .distantPast
            refreshSkillsCompatibilitySnapshot(force: true)
            return
        }
        let ctx = AXProjectContext(root: root)
        projectContext = ctx
        nextProjectSnapshotRefreshAt = .distantPast
        nextProjectRuntimeSurfaceOverrideRefreshAt = .distantPast
        do {
            memory = try AXProjectStore.loadOrCreateMemory(for: ctx)
            usageSummary = AXProjectStore.usageSummary(for: ctx)
            projectConfig = try AXProjectStore.loadOrCreateConfig(for: ctx)
        } catch {
            memory = nil
            usageSummary = .empty()
            projectConfig = nil
        }
        await refreshProjectRemoteRuntimeSurfaceOverride(force: true)
        refreshSkillsCompatibilitySnapshot(force: true)
    }

    var sortedProjects: [AXProjectEntry] {
        registry.sortedProjects()
    }

    private func loadRegistry() {
        guard loadPersistedProjectRegistry else {
            registry = .empty()
            historicalProjectBoundaryRepairStatusLine = HistoricalProjectBoundaryRepairSummary()
                .statusLine(reason: "testing_empty_registry")
            return
        }
        registry = AXProjectRegistryStore.load()
        historicalProjectBoundaryRepairStatusLine = HistoricalProjectBoundaryRepairSummary()
            .statusLine(reason: "startup_deferred")
    }

    @discardableResult
    private func runHistoricalProjectBoundaryRepair(reason: String) -> HistoricalProjectBoundaryRepairSummary {
        historicalProjectBoundaryRepairStatusLine = "historical_project_boundary_repair=running reason=\(reason)"
        let fm = FileManager.default
        var summary = HistoricalProjectBoundaryRepairSummary()

        for entry in registry.projects {
            summary.scanned += 1
            let rootPath = entry.rootPath.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !rootPath.isEmpty else { continue }

            let root = URL(fileURLWithPath: rootPath, isDirectory: true)
            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                continue
            }

            let ctx = AXProjectContext(root: root)
            let missingConfig = !fm.fileExists(atPath: ctx.configURL.path)
            let missingMemory = AXProjectStore.loadMemoryIfPresent(for: ctx) == nil
            guard missingConfig || missingMemory else { continue }

            do {
                if missingConfig {
                    _ = try AXProjectStore.loadOrCreateConfig(for: ctx)
                    summary.repairedConfigCount += 1
                }
                if missingMemory {
                    _ = try AXProjectStore.loadOrCreateMemory(for: ctx)
                    summary.repairedMemoryCount += 1
                }
            } catch {
                let ref = entry.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? entry.projectId
                    : entry.displayName
                summary.failedProjectRefs.append(ref)
                print("Historical project boundary repair failed for \(ref): \(error)")
            }
        }

        historicalProjectBoundaryRepairStatusLine = summary.statusLine(reason: reason)

        if summary.touchedCount > 0 || summary.failedCount > 0 {
            registry = AXProjectRegistryStore.load()
            let failedSuffix = summary.failedProjectRefs.isEmpty
                ? ""
                : " failed=\(summary.failedProjectRefs.joined(separator: ","))"
            print(
                "Historical project boundary repair summary: scanned=\(summary.scanned) repaired_config=\(summary.repairedConfigCount) repaired_memory=\(summary.repairedMemoryCount)\(failedSuffix)"
            )
        }
        return summary
    }

    private func bootstrapSelection() {
        // Startup stays empty on purpose so XT does not touch historical
        // project roots or Home dashboards until the user explicitly opens one.
        selectedProjectId = nil
    }

    private func applySelection() async {
        let previousRoot = projectRoot
        guard let pid = selectedProjectId else {
            persistProjectSwitchSummaryIfNeeded(from: previousRoot, to: nil)
            projectRoot = nil
            return
        }
        if pid == AXProjectRegistry.globalHomeId {
            persistProjectSwitchSummaryIfNeeded(from: previousRoot, to: nil)
            projectRoot = nil
            return
        }
        guard let entry = registry.project(for: pid) else {
            persistProjectSwitchSummaryIfNeeded(from: previousRoot, to: nil)
            projectRoot = nil
            return
        }

        var reg = registry
        reg = AXProjectRegistryStore.touchOpened(reg, projectId: pid)
        reg.lastSelectedProjectId = pid
        registry = reg
        if persistProjectRegistryChanges {
            AXProjectRegistryStore.save(reg)
        }

        guard let resolvedRoot = resolvedProjectRootURL(for: entry) else {
            if reg.globalHomeVisible {
                selectedProjectId = AXProjectRegistry.globalHomeId
            } else {
                selectedProjectId = nil
            }
            return
        }

        persistProjectSwitchSummaryIfNeeded(from: previousRoot, to: resolvedRoot)
        projectRoot = resolvedRoot
    }

    private func addProject(_ url: URL) {
        let normalizedRoot = AXProjectRegistryStore.normalizedRootPath(url)
        let previous = registry.projects.first(where: { $0.rootPath == normalizedRoot })
        let ctx = AXProjectContext(root: URL(fileURLWithPath: normalizedRoot, isDirectory: true))
        let hadExistingMemory = AXProjectStore.loadMemoryIfPresent(for: ctx) != nil

        guard let entry = ensureRegisteredProjectBoundary(
            at: url,
            initializeMemoryBoundary: true,
            selectAfterUpsert: true
        ) else {
            return
        }

        if hadExistingMemory {
            if previous == nil {
                eventBus.publish(.projectCreated(entry))
            } else {
                eventBus.publish(.projectUpdated(entry))
            }
        }
    }

    private func resolvedProjectRootURL(for entry: AXProjectEntry) -> URL? {
        let rootPath = entry.rootPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rootPath.isEmpty else { return nil }

        let fm = FileManager.default
        guard fm.fileExists(atPath: rootPath),
              fm.isReadableFile(atPath: rootPath) else {
            return nil
        }

        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: rootPath, isDirectory: &isDirectory), isDirectory.boolValue else {
            return nil
        }

        return URL(fileURLWithPath: rootPath, isDirectory: true)
    }

    private func observeModelAssignmentChanges() {
        settingsStore.$settings
            .dropFirst()
            .sink { [weak self] newSettings in
                Task { @MainActor in
                    self?.handleObservedSettingsChange(newSettings)
                }
            }
            .store(in: &settingsSubscriptions)
    }

    private func handleObservedSettingsChange(_ newSettings: XTerminalSettings) {
        let nextAssignments = Self.modelAssignmentMap(for: newSettings)
        defer {
            lastObservedModelAssignments = nextAssignments
        }
        guard modelAssignmentsChanged(lastObservedModelAssignments, nextAssignments) else {
            return
        }
        noteRemoteMemoryRouteOrModelPreferenceChanged(projectId: nil)
        persistSessionSummariesForLifecycle(reason: "ai_switch")
    }

    private func noteRemoteMemoryRouteOrModelPreferenceChanged(projectId: String?) {
        Task {
            await HubIPCClient.noteSupervisorRemoteMemoryRouteOrModelPreferenceChanged()
            if let projectId {
                await HubIPCClient.noteProjectRemoteMemoryRouteOrModelPreferenceChanged(
                    projectId: projectId
                )
            } else {
                await HubIPCClient.invalidateProjectRemoteMemorySnapshotCache(
                    projectId: nil,
                    reason: .routeOrModelPreferenceChanged
                )
            }
        }
    }

    private func activeProjectContextsForSessionSummary() -> [AXProjectContext] {
        var ordered: [AXProjectContext] = []
        var seen: Set<String> = []

        if let projectContext {
            let key = projectContext.root.standardizedFileURL.path
            if seen.insert(key).inserted {
                ordered.append(projectContext)
            }
        }

        for projectId in chatSessions.keys.sorted() {
            guard let ctx = projectContext(for: projectId) else { continue }
            let key = ctx.root.standardizedFileURL.path
            if seen.insert(key).inserted {
                ordered.append(ctx)
            }
        }

        return ordered
    }

    private func selectedProjectResumeProject() -> AXResumeReminderProjectPresentation? {
        guard let selectedProjectId,
              selectedProjectId != AXProjectRegistry.globalHomeId,
              let project = registry.project(for: selectedProjectId),
              let summary = sessionSummaryPresentation(projectId: selectedProjectId) else {
            return nil
        }
        return AXResumeReminderProjectPresentation(
            projectId: project.projectId,
            projectDisplayName: project.displayName,
            summary: summary
        )
    }

    private func latestSessionSummaryProject(
        using summaryLoader: (String) -> AXSessionSummaryCapsulePresentation?
    ) -> AXResumeReminderProjectPresentation? {
        let candidates = registry.sortedProjects().compactMap { project -> AXResumeReminderProjectPresentation? in
            guard let summary = summaryLoader(project.projectId) else {
                return nil
            }
            return AXResumeReminderProjectPresentation(
                projectId: project.projectId,
                projectDisplayName: project.displayName,
                summary: summary
            )
        }

        return candidates.sorted { lhs, rhs in
            if lhs.summary.createdAtMs != rhs.summary.createdAtMs {
                return lhs.summary.createdAtMs > rhs.summary.createdAtMs
            }
            let lhsLastOpenedAt = registry.project(for: lhs.projectId)?.lastOpenedAt ?? 0
            let rhsLastOpenedAt = registry.project(for: rhs.projectId)?.lastOpenedAt ?? 0
            if lhsLastOpenedAt != rhsLastOpenedAt {
                return lhsLastOpenedAt > rhsLastOpenedAt
            }
            return lhs.projectDisplayName.localizedCaseInsensitiveCompare(rhs.projectDisplayName) == .orderedAscending
        }.first
    }

    private func persistProjectSwitchSummaryIfNeeded(from previousRoot: URL?, to nextRoot: URL?) {
        guard let previousRoot else { return }
        let previousPath = previousRoot.standardizedFileURL.path
        let nextPath = nextRoot?.standardizedFileURL.path
        guard previousPath != nextPath else { return }
        let ctx = AXProjectContext(root: previousRoot)
        _ = AXMemoryLifecycleStore.writeSessionSummaryCapsule(ctx: ctx, reason: "project_switch")
    }

    private func projectModelSwitchChanged(current: String?, next: String?) -> Bool {
        normalizedModelSwitchValue(current) != normalizedModelSwitchValue(next)
    }

    private func normalizedModelSwitchValue(_ raw: String?) -> String {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.lowercased()
    }

    private func modelAssignmentsChanged(
        _ previous: [AXRole: RoleProviderAssignment],
        _ next: [AXRole: RoleProviderAssignment]
    ) -> Bool {
        for role in AXRole.allCases {
            if previous[role] != next[role] {
                return true
            }
        }
        return false
    }

    private static func modelAssignmentMap(for settings: XTerminalSettings) -> [AXRole: RoleProviderAssignment] {
        Dictionary(
            uniqueKeysWithValues: AXRole.allCases.map { role in
                (role, settings.assignment(for: role))
            }
        )
    }

    private func loadHubRemotePrefs() {
        let d = UserDefaults.standard
        let cached = HubAIClient.cachedRemoteProfile(stateDir: nil)
        let explicitHost = (d.string(forKey: hubInternetHostKey)
            ?? d.string(forKey: legacyHubInternetHostKey)
            ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let explicitPairingPort = d.object(forKey: hubPairingPortKey) as? Int
            ?? d.object(forKey: legacyHubPairingPortKey) as? Int
        let explicitGrpcPort = d.object(forKey: hubGrpcPortKey) as? Int
            ?? d.object(forKey: legacyHubGrpcPortKey) as? Int
        let endpointOverridePending = hasHubRemoteEndpointOverridePending()
        let p = endpointOverridePending
            ? (explicitPairingPort ?? cached.pairingPort ?? 50052)
            : (cached.pairingPort ?? explicitPairingPort ?? 50052)
        let g = endpointOverridePending
            ? (explicitGrpcPort ?? cached.grpcPort ?? 50051)
            : (cached.grpcPort ?? explicitGrpcPort ?? 50051)
        let host = endpointOverridePending
            ? (explicitHost.isEmpty ? (cached.internetHost ?? "") : explicitHost)
            : (cached.internetHost ?? (explicitHost.isEmpty ? "" : explicitHost))
        let inviteToken = (d.string(forKey: hubInviteTokenKey)
            ?? d.string(forKey: legacyHubInviteTokenKey)
            ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let inviteAlias = (d.string(forKey: hubInviteAliasKey)
            ?? d.string(forKey: legacyHubInviteAliasKey)
            ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let inviteInstanceID = (cached.hubInstanceID
            ?? d.string(forKey: hubInviteInstanceIDKey)
            ?? d.string(forKey: legacyHubInviteInstanceIDKey)
            ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let ctl = d.string(forKey: hubAxhubctlPathKey)
            ?? d.string(forKey: legacyHubAxhubctlPathKey)
            ?? ""

        hubPairingPort = max(1, min(65_535, p))
        hubGrpcPort = max(1, min(65_535, g))
        hubInternetHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        hubInviteToken = inviteToken
        hubInviteAlias = inviteAlias
        hubInviteInstanceID = inviteInstanceID
        hubAxhubctlPath = ctl.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func saveHubRemotePrefs() {
        let d = UserDefaults.standard
        d.set(hubPairingPort, forKey: hubPairingPortKey)
        d.set(hubPairingPort, forKey: legacyHubPairingPortKey)
        d.set(hubGrpcPort, forKey: hubGrpcPortKey)
        d.set(hubGrpcPort, forKey: legacyHubGrpcPortKey)
        d.set(hubInternetHost, forKey: hubInternetHostKey)
        d.set(hubInternetHost, forKey: legacyHubInternetHostKey)
        d.set(hubInviteToken, forKey: hubInviteTokenKey)
        d.set(hubInviteToken, forKey: legacyHubInviteTokenKey)
        d.set(hubInviteAlias, forKey: hubInviteAliasKey)
        d.set(hubInviteAlias, forKey: legacyHubInviteAliasKey)
        d.set(hubInviteInstanceID, forKey: hubInviteInstanceIDKey)
        d.set(hubInviteInstanceID, forKey: legacyHubInviteInstanceIDKey)
        d.set(hubAxhubctlPath, forKey: hubAxhubctlPathKey)
        d.set(hubAxhubctlPath, forKey: legacyHubAxhubctlPathKey)
    }

    private func hasHubRemoteEndpointOverridePending() -> Bool {
        let d = UserDefaults.standard
        if d.object(forKey: hubRemoteEndpointOverridePendingKey) != nil {
            return d.bool(forKey: hubRemoteEndpointOverridePendingKey)
        }
        return d.bool(forKey: legacyHubRemoteEndpointOverridePendingKey)
    }

    private func setHubRemoteEndpointOverridePending(_ pending: Bool) {
        let d = UserDefaults.standard
        if pending {
            d.set(true, forKey: hubRemoteEndpointOverridePendingKey)
            d.set(true, forKey: legacyHubRemoteEndpointOverridePendingKey)
        } else {
            d.removeObject(forKey: hubRemoteEndpointOverridePendingKey)
            d.removeObject(forKey: legacyHubRemoteEndpointOverridePendingKey)
        }
    }

    nonisolated static func shouldPreserveHubRemoteEndpointOverride(
        overridePending: Bool,
        currentEndpoint: HubRemoteEndpointFingerprint,
        cachedProfile: HubAIClient.CachedRemoteProfile
    ) -> Bool {
        guard overridePending else { return false }

        let cachedHost = (cachedProfile.internetHost ?? cachedProfile.host ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if currentEndpoint.internetHost != cachedHost {
            return true
        }
        if let cachedPairingPort = cachedProfile.pairingPort,
           currentEndpoint.pairingPort != cachedPairingPort {
            return true
        }
        if let cachedGrpcPort = cachedProfile.grpcPort,
           currentEndpoint.grpcPort != cachedGrpcPort {
            return true
        }
        return false
    }

    nonisolated static func pairingResetPlan(
        overridePending: Bool,
        currentEndpoint: HubRemoteEndpointFingerprint
    ) -> HubPairingResetPlan {
        let hasMeaningfulManualEndpoint = shouldProtectManualHubEndpointFromAutofill(
            overridePending: overridePending,
            currentEndpoint: currentEndpoint
        )
        if hasMeaningfulManualEndpoint {
            return HubPairingResetPlan(
                endpoint: currentEndpoint,
                preserveEndpointOverride: true,
                shouldAutoDetect: false
            )
        }
        return HubPairingResetPlan(
            endpoint: HubRemoteEndpointFingerprint(
                pairingPort: 50052,
                grpcPort: 50051,
                internetHost: ""
            ),
            preserveEndpointOverride: false,
            shouldAutoDetect: true
        )
    }

    nonisolated static func shouldProtectManualHubEndpointFromAutofill(
        overridePending: Bool,
        currentEndpoint: HubRemoteEndpointFingerprint
    ) -> Bool {
        guard overridePending else { return false }

        let internetHost = currentEndpoint.internetHost.trimmingCharacters(in: .whitespacesAndNewlines)
        return !internetHost.isEmpty
            || currentEndpoint.pairingPort != 50052
            || currentEndpoint.grpcPort != 50051
    }

    @discardableResult
    private func synchronizeHubRemotePrefsFromCachedProfile(
        preferDiscoveredInternetHost: Bool
    ) -> HubAIClient.CachedRemoteProfile {
        let cachedProfile = HubAIClient.cachedRemoteProfile(stateDir: nil)
        var changed = false
        let preserveEndpointOverride = Self.shouldPreserveHubRemoteEndpointOverride(
            overridePending: hasHubRemoteEndpointOverridePending(),
            currentEndpoint: currentHubRemoteEndpointFingerprint(),
            cachedProfile: cachedProfile
        )

        if !preserveEndpointOverride,
           let pairingPort = cachedProfile.pairingPort,
           hubPairingPort != pairingPort {
            hubPairingPort = pairingPort
            changed = true
        }

        if !preserveEndpointOverride,
           let grpcPort = cachedProfile.grpcPort,
           hubGrpcPort != grpcPort {
            hubGrpcPort = grpcPort
            changed = true
        }

        let discoveredInternetHost = (cachedProfile.internetHost ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !preserveEndpointOverride,
           !discoveredInternetHost.isEmpty {
            let currentInternetHost = hubInternetHost.trimmingCharacters(in: .whitespacesAndNewlines)
            if preferDiscoveredInternetHost || currentInternetHost.isEmpty {
                if currentInternetHost != discoveredInternetHost {
                    hubInternetHost = discoveredInternetHost
                    changed = true
                }
            }
        }

        if let cachedHubInstanceID = cachedProfile.hubInstanceID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !cachedHubInstanceID.isEmpty,
           hubInviteInstanceID != cachedHubInstanceID {
            hubInviteInstanceID = cachedHubInstanceID
            changed = true
        }

        if changed {
            saveHubRemotePrefs()
        }
        return cachedProfile
    }

    private func loadBridgePrefs() {
        let d = UserDefaults.standard
        // Startup-safe policy: keep bridge off until a real workflow requests it.
        // This also clears older forced-on defaults that made app launch too aggressive.
        bridgeAlwaysOn = false
        d.set(false, forKey: bridgeAlwaysOnKey)
        d.set(false, forKey: legacyBridgeAlwaysOnKey)
    }

    private func loadLocalServerPrefs() {
        let d = UserDefaults.standard
        if d.object(forKey: localServerEnabledKey) != nil {
            localServerEnabled = d.bool(forKey: localServerEnabledKey)
        } else if d.object(forKey: legacyLocalServerEnabledKey) != nil {
            localServerEnabled = d.bool(forKey: legacyLocalServerEnabledKey)
            d.set(localServerEnabled, forKey: localServerEnabledKey)
        } else {
            // Keep startup quiet/safe by default for new users.
            localServerEnabled = false
            d.set(false, forKey: localServerEnabledKey)
            d.set(false, forKey: legacyLocalServerEnabledKey)
        }
    }

    private func saveLocalServerPrefs() {
        let d = UserDefaults.standard
        d.set(localServerEnabled, forKey: localServerEnabledKey)
        d.set(localServerEnabled, forKey: legacyLocalServerEnabledKey)
    }

    private func applyLocalServerPreference(isStartup: Bool) async {
        if !localServerEnabled {
            serverManager.stopServer()
            serverRunning = false
            localServerPort = serverManager.port
            localServerLastError = ""
            if !isStartup {
                print("Local HTTP server disabled by settings.")
            }
            return
        }

        await startLocalServer(forceRestart: false)
    }

    private func startLocalServer(forceRestart: Bool) async {
        if forceRestart {
            serverManager.stopServer()
        }
        do {
            try await serverManager.startServer()
            serverRunning = serverManager.isRunning
            localServerPort = serverManager.port
            localServerLastError = serverManager.lastError
        } catch {
            serverRunning = false
            localServerPort = serverManager.port
            localServerLastError = serverManager.lastError.isEmpty ? "Failed to start local server: \(error)" : serverManager.lastError
            print(localServerLastError)
        }
    }

    private func maybeScheduleRemoteReconnect(
        decisionTrigger: XTHubConnectivityDecisionTrigger,
        decision: XTHubConnectivityDecision,
        incidentSnapshot: XTHubConnectivityIncidentSnapshot? = nil,
        force: Bool
    ) {
        let startupSuppressed = shouldSuppressAutomaticReconnectDuringStartup()
        if Self.shouldSuppressAutomaticRemoteReconnect(
            hubRemoteLinking: hubRemoteLinking,
            startupSuppressed: startupSuppressed,
            activeRemoteGenerate: false
        ) {
            return
        }
        if !force {
            let now = Date()
            if now.timeIntervalSince(hubReconnectLastAttemptAt) < 20.0 {
                return
            }
        }
        Task { @MainActor in
            let activeRemoteGenerate = await HubAIClient.shared.hasActiveRemoteGenerateRequests()
            guard Self.shouldSuppressAutomaticRemoteReconnect(
                hubRemoteLinking: hubRemoteLinking,
                startupSuppressed: shouldSuppressAutomaticReconnectDuringStartup(),
                activeRemoteGenerate: activeRemoteGenerate
            ) == false else {
                return
            }
            let hasEnv = await HubPairingCoordinator.shared.hasHubEnv(stateDir: nil)
            guard Self.shouldAllowAutomaticBootstrapReconnect(
                hasHubEnv: hasEnv,
                internetHost: hubInternetHost,
                inviteToken: hubInviteToken,
                inviteAlias: hubInviteAlias,
                inviteInstanceID: hubInviteInstanceID
            ) else {
                return
            }
            // Automatic recovery must stay connect-only for existing paired profiles.
            let effectiveAllowBootstrap = false
            let shouldSurfaceProgress = Self.shouldSurfaceAutomaticRemoteConnectProgress(
                force: force,
                allowBootstrap: effectiveAllowBootstrap,
                existingSummary: hubRemoteSummary,
                existingLog: hubRemoteLog
            )
            _ = await runRemoteConnectFlow(
                allowBootstrap: effectiveAllowBootstrap,
                showAlertOnFinish: false,
                updateSetupProgress: shouldSurfaceProgress,
                repairTrigger: Self.connectivityRepairTrigger(for: decisionTrigger),
                repairOwner: .xtRuntime,
                repairDecisionReasonCode: decision.reasonCode,
                preferredRoute: decision.selectedRoute,
                candidateRoutes: decision.candidatesTried,
                handoffReason: decision.handoffReason,
                cooldownApplied: decision.cooldownApplied,
                probeTrigger: decisionTrigger,
                probeDecision: decision,
                probeIncidentSnapshot: incidentSnapshot
            )
        }
    }

    private func currentHubConnectivityDecision(
        trigger: XTHubConnectivityDecisionTrigger,
        currentPath: HubNetworkPathFingerprint? = nil,
        pairedRouteSetSnapshot: XTPairedRouteSetSnapshot? = nil
    ) -> XTHubConnectivityDecision {
        let pairedRouteSetSnapshot = pairedRouteSetSnapshot ?? currentPairedRouteSetSnapshot()
        return XTHubConnectivityDecisionBuilder.build(
            input: XTHubConnectivityDecisionInput(
                trigger: trigger,
                currentPath: currentPath,
                pairedRouteSetSnapshot: pairedRouteSetSnapshot,
                localConnected: hubConnected,
                remoteConnected: hubRemoteConnected,
                remoteRoute: hubRemoteRoute,
                repairLedgerSnapshot: XTConnectivityRepairLedgerStore.loadSnapshot()
            )
        )
    }

    private func currentHubConnectivityIncidentSnapshot(
        trigger: XTHubConnectivityDecisionTrigger,
        currentPath: HubNetworkPathFingerprint? = nil,
        pairedRouteSetSnapshot: XTPairedRouteSetSnapshot? = nil,
        decision: XTHubConnectivityDecision? = nil,
        localConnectedOverride: Bool? = nil,
        remoteConnectedOverride: Bool? = nil,
        remoteRouteOverride: HubRemoteRoute? = nil,
        updatedAt: Date = Date()
    ) -> XTHubConnectivityIncidentSnapshot {
        let pairedRouteSetSnapshot = pairedRouteSetSnapshot ?? currentPairedRouteSetSnapshot()
        let decision = decision ?? currentHubConnectivityDecision(
            trigger: trigger,
            currentPath: currentPath,
            pairedRouteSetSnapshot: pairedRouteSetSnapshot
        )
        return XTHubConnectivityIncidentSnapshotBuilder.build(
            input: XTHubConnectivityIncidentInput(
                trigger: trigger,
                decision: decision,
                currentPath: currentPath,
                pairedRouteSetSnapshot: pairedRouteSetSnapshot,
                localConnected: localConnectedOverride ?? hubConnected,
                remoteConnected: remoteConnectedOverride ?? hubRemoteConnected,
                remoteRoute: remoteRouteOverride ?? hubRemoteRoute,
                currentFailureCode: hubSetupFailureCode,
                updatedAt: updatedAt
            )
        )
    }

    private func recordDeferredConnectivityRepairIfNeeded(
        trigger: XTHubConnectivityDecisionTrigger,
        incidentSnapshot: XTHubConnectivityIncidentSnapshot
    ) {
        guard let entry = XTConnectivityRepairLedgerStore.deferredEntry(
            trigger: Self.connectivityRepairTrigger(for: trigger),
            incidentSnapshot: incidentSnapshot
        ) else {
            return
        }
        XTConnectivityRepairLedgerStore.append(entry)
    }

    private func recordConnectivityRepairOutcome(
        trigger: XTConnectivityRepairTrigger,
        owner: XTConnectivityRepairOwner,
        allowBootstrap: Bool,
        decisionReasonCode: String?,
        report: HubRemoteConnectReport,
        incidentSnapshot: XTHubConnectivityIncidentSnapshot,
        recordedAt: Date
    ) {
        let recordedAtMs = Int64((recordedAt.timeIntervalSince1970 * 1000).rounded())
        let entry = XTConnectivityRepairLedgerStore.outcomeEntry(
            trigger: trigger,
            owner: owner,
            allowBootstrap: allowBootstrap,
            decisionReasonCode: decisionReasonCode,
            report: report,
            incidentSnapshot: incidentSnapshot,
            recordedAtMs: recordedAtMs
        )
        XTConnectivityRepairLedgerStore.append(entry)
    }

    private func recordHubNetworkHandoffObservation(
        trigger: XTHubConnectivityDecisionTrigger,
        allowBootstrap: Bool,
        decision: XTHubConnectivityDecision,
        incidentSnapshot: XTHubConnectivityIncidentSnapshot,
        recordedAt: Date = Date()
    ) {
        let recordedAtMs = Int64((recordedAt.timeIntervalSince1970 * 1000).rounded())
        let entry = XTHubNetworkHandoffProbeLogStore.noAttemptEntry(
            trigger: trigger,
            allowBootstrap: allowBootstrap,
            decision: decision,
            incidentSnapshot: incidentSnapshot,
            recordedAtMs: recordedAtMs
        )
        XTHubNetworkHandoffProbeLogStore.append(entry)
    }

    private func recordHubNetworkHandoffOutcome(
        trigger: XTHubConnectivityDecisionTrigger,
        allowBootstrap: Bool,
        decision: XTHubConnectivityDecision,
        incidentSnapshot: XTHubConnectivityIncidentSnapshot,
        report: HubRemoteConnectReport,
        recordedAt: Date
    ) {
        let recordedAtMs = Int64((recordedAt.timeIntervalSince1970 * 1000).rounded())
        let entry = XTHubNetworkHandoffProbeLogStore.outcomeEntry(
            trigger: trigger,
            allowBootstrap: allowBootstrap,
            decision: decision,
            incidentSnapshot: incidentSnapshot,
            report: report,
            recordedAtMs: recordedAtMs
        )
        XTHubNetworkHandoffProbeLogStore.append(entry)
    }

    private static func connectivityRepairTrigger(
        for trigger: XTHubConnectivityDecisionTrigger
    ) -> XTConnectivityRepairTrigger {
        switch trigger {
        case .networkChanged:
            return .networkChanged
        case .backgroundKeepalive:
            return .backgroundKeepalive
        case .appBecameActive:
            return .appBecameActive
        case .systemWoke:
            return .systemWoke
        case .hubReachabilityChanged:
            return .hubReachabilityChanged
        }
    }

    private func maybeRefreshRemotePresence(force: Bool = false) async {
        guard hubConnected || hubRemoteConnected else { return }

        let route: HubRemoteRoute = hubConnected ? .lan : hubRemoteRoute
        guard route != .none else { return }

        let now = Date()
        if !force, now < nextRemotePresenceRefreshAt {
            return
        }

        let ok = await HubPairingCoordinator.shared.sendRemoteDevicePresence(
            route: route,
            stateDir: nil,
            deviceName: Host.current().localizedName ?? "X-Terminal"
        )

        nextRemotePresenceRefreshAt = now.addingTimeInterval(ok ? 25.0 : 10.0)
    }

    private func startHubNetworkMonitor() {
        let monitor = NWPathMonitor()
        hubNetworkMonitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in
            let fingerprint = HubNetworkPathFingerprint(path: path)
            Task { @MainActor [weak self] in
                self?.handleHubNetworkPathUpdate(fingerprint)
            }
        }
        monitor.start(queue: hubNetworkMonitorQueue)
    }

    private func handleHubNetworkPathUpdate(_ fingerprint: HubNetworkPathFingerprint) {
        let previous = lastHubNetworkPathFingerprint
        lastHubNetworkPathFingerprint = fingerprint
        let activeRemoteGenerate = HubAIClient.hasActiveRemoteGenerateRequestsForLifecycleGates()

        if !fingerprint.isSatisfied {
            guard !hubConnected else { return }
            if Self.shouldDeferAutomaticRemoteRouteHandoff(
                activeRemoteGenerate: activeRemoteGenerate,
                remoteConnected: hubRemoteConnected,
                remoteRoute: hubRemoteRoute
            ) {
                hubRemoteSummary = "network unavailable; holding active remote response route until reply completes."
                hubConnectivityIncidentSnapshot = currentHubConnectivityIncidentSnapshot(
                    trigger: .networkChanged,
                    currentPath: fingerprint,
                    updatedAt: Date()
                )
                refreshUnifiedDoctorReport(force: true)
                return
            }
            if hubRemoteConnected || hubRemoteRoute != .none {
                let decision = currentHubConnectivityDecision(
                    trigger: .networkChanged,
                    currentPath: fingerprint
                )
                hubRemoteConnected = false
                hubRemoteRoute = .none
                hubRemotePaidAccessSnapshot = nil
                hubRemoteSummary = "network unavailable"
                nextRemotePresenceRefreshAt = .distantPast
                hubConnectivityIncidentSnapshot = currentHubConnectivityIncidentSnapshot(
                    trigger: .networkChanged,
                    currentPath: fingerprint,
                    decision: decision
                )
                if let snapshot = hubConnectivityIncidentSnapshot {
                    recordDeferredConnectivityRepairIfNeeded(
                        trigger: .networkChanged,
                        incidentSnapshot: snapshot
                    )
                    recordHubNetworkHandoffObservation(
                        trigger: .networkChanged,
                        allowBootstrap: decision.allowBootstrap,
                        decision: decision,
                        incidentSnapshot: snapshot
                    )
                }
                refreshUnifiedDoctorReport(force: true)
            }
            return
        }

        guard Self.shouldForceHubReconnect(previous: previous, current: fingerprint) else { return }
        guard !hubConnected else { return }
        guard !shouldSuppressAutomaticReconnectDuringStartup() else { return }
        if Self.shouldDeferAutomaticRemoteRouteHandoff(
            activeRemoteGenerate: activeRemoteGenerate,
            remoteConnected: hubRemoteConnected,
            remoteRoute: hubRemoteRoute
        ) {
            hubRemoteSummary = "network changed during active remote response; deferring route handoff until reply completes."
            let shouldPreserveRoute = Self.shouldPreserveExistingRemoteRouteDuringAutomaticReconnect(
                current: fingerprint,
                shouldAttemptReconnect: true,
                remoteConnected: hubRemoteConnected,
                remoteRoute: hubRemoteRoute
            )
            hubConnectivityIncidentSnapshot = currentHubConnectivityIncidentSnapshot(
                trigger: .networkChanged,
                currentPath: fingerprint,
                remoteConnectedOverride: shouldPreserveRoute ? false : nil,
                remoteRouteOverride: shouldPreserveRoute ? HubRemoteRoute.none : nil,
                updatedAt: Date()
            )
            refreshUnifiedDoctorReport(force: true)
            return
        }

        let pairedRouteSetSnapshot = currentPairedRouteSetSnapshot()
        let decision = currentHubConnectivityDecision(
            trigger: .networkChanged,
            currentPath: fingerprint,
            pairedRouteSetSnapshot: pairedRouteSetSnapshot
        )
        let shouldPreserveRoute = Self.shouldPreserveExistingRemoteRouteDuringAutomaticReconnect(
            current: fingerprint,
            shouldAttemptReconnect: decision.shouldAttemptReconnect,
            remoteConnected: hubRemoteConnected,
            remoteRoute: hubRemoteRoute
        )
        if !shouldPreserveRoute {
            hubRemoteConnected = false
            hubRemoteRoute = .none
            hubRemotePaidAccessSnapshot = nil
        }
        hubRemoteSummary = decision.summaryLine
        nextRemotePresenceRefreshAt = .distantPast
        hubConnectivityIncidentSnapshot = currentHubConnectivityIncidentSnapshot(
            trigger: .networkChanged,
            currentPath: fingerprint,
            pairedRouteSetSnapshot: pairedRouteSetSnapshot,
            decision: decision,
            remoteConnectedOverride: shouldPreserveRoute ? false : nil,
            remoteRouteOverride: shouldPreserveRoute ? HubRemoteRoute.none : nil
        )
        refreshUnifiedDoctorReport(force: true)
        guard decision.shouldAttemptReconnect else {
            if let snapshot = hubConnectivityIncidentSnapshot {
                recordDeferredConnectivityRepairIfNeeded(
                    trigger: .networkChanged,
                    incidentSnapshot: snapshot
                )
                recordHubNetworkHandoffObservation(
                    trigger: .networkChanged,
                    allowBootstrap: decision.allowBootstrap,
                    decision: decision,
                    incidentSnapshot: snapshot
                )
            }
            return
        }
        maybeScheduleRemoteReconnect(
            decisionTrigger: .networkChanged,
            decision: decision,
            incidentSnapshot: hubConnectivityIncidentSnapshot,
            force: true
        )
    }

    private func handleHubConnectivityLifecycleTrigger(
        _ trigger: XTHubConnectivityDecisionTrigger
    ) {
        let currentPath = lastHubNetworkPathFingerprint
        let pairedRouteSetSnapshot = currentPairedRouteSetSnapshot()
        let decision = currentHubConnectivityDecision(
            trigger: trigger,
            currentPath: currentPath,
            pairedRouteSetSnapshot: pairedRouteSetSnapshot
        )

        hubConnectivityIncidentSnapshot = currentHubConnectivityIncidentSnapshot(
            trigger: trigger,
            currentPath: currentPath,
            pairedRouteSetSnapshot: pairedRouteSetSnapshot,
            decision: decision
        )
        refreshUnifiedDoctorReport(force: true)

        guard !hubConnected else { return }

        if decision.shouldAttemptReconnect {
            maybeScheduleRemoteReconnect(
                decisionTrigger: trigger,
                decision: decision,
                incidentSnapshot: hubConnectivityIncidentSnapshot,
                force: true
            )
        } else if let snapshot = hubConnectivityIncidentSnapshot {
            recordDeferredConnectivityRepairIfNeeded(
                trigger: trigger,
                incidentSnapshot: snapshot
            )
            recordHubNetworkHandoffObservation(
                trigger: trigger,
                allowBootstrap: decision.allowBootstrap,
                decision: decision,
                incidentSnapshot: snapshot
            )
        }
    }

    private func handleHubReachabilityEdge(
        previousConnected: Bool,
        currentConnected: Bool
    ) {
        guard previousConnected != currentConnected else { return }

        let currentPath = lastHubNetworkPathFingerprint
        let pairedRouteSetSnapshot = currentPairedRouteSetSnapshot()

        if currentConnected {
            hubRemoteConnected = false
            hubRemoteRoute = .none
            hubRemotePaidAccessSnapshot = nil
            nextRemotePresenceRefreshAt = .distantPast
            let decision = currentHubConnectivityDecision(
                trigger: .hubReachabilityChanged,
                currentPath: currentPath,
                pairedRouteSetSnapshot: pairedRouteSetSnapshot
            )
            hubConnectivityIncidentSnapshot = currentHubConnectivityIncidentSnapshot(
                trigger: .hubReachabilityChanged,
                currentPath: currentPath,
                pairedRouteSetSnapshot: pairedRouteSetSnapshot,
                decision: decision
            )
            if let snapshot = hubConnectivityIncidentSnapshot {
                recordHubNetworkHandoffObservation(
                    trigger: .hubReachabilityChanged,
                    allowBootstrap: decision.allowBootstrap,
                    decision: decision,
                    incidentSnapshot: snapshot
                )
            }
            refreshUnifiedDoctorReport(force: true)
            return
        }

        let decision = currentHubConnectivityDecision(
            trigger: .hubReachabilityChanged,
            currentPath: currentPath,
            pairedRouteSetSnapshot: pairedRouteSetSnapshot
        )
        hubRemoteSummary = decision.summaryLine
        hubConnectivityIncidentSnapshot = currentHubConnectivityIncidentSnapshot(
            trigger: .hubReachabilityChanged,
            currentPath: currentPath,
            pairedRouteSetSnapshot: pairedRouteSetSnapshot,
            decision: decision
        )
        refreshUnifiedDoctorReport(force: true)

        guard decision.shouldAttemptReconnect else {
            if let snapshot = hubConnectivityIncidentSnapshot {
                recordDeferredConnectivityRepairIfNeeded(
                    trigger: .hubReachabilityChanged,
                    incidentSnapshot: snapshot
                )
                recordHubNetworkHandoffObservation(
                    trigger: .hubReachabilityChanged,
                    allowBootstrap: decision.allowBootstrap,
                    decision: decision,
                    incidentSnapshot: snapshot
                )
            }
            return
        }

        maybeScheduleRemoteReconnect(
            decisionTrigger: .hubReachabilityChanged,
            decision: decision,
            incidentSnapshot: hubConnectivityIncidentSnapshot,
            force: true
        )
    }

    nonisolated static func shouldForceHubReconnect(
        previous: HubNetworkPathFingerprint?,
        current: HubNetworkPathFingerprint
    ) -> Bool {
        guard let previous else { return false }
        return current.hasMeaningfulReconnectChange(comparedTo: previous)
    }

    nonisolated static func shouldAllowDiscoveryRepairReconnect(
        current: HubNetworkPathFingerprint
    ) -> Bool {
        current.isSatisfied
    }

    nonisolated static func shouldPreserveExistingRemoteRouteDuringAutomaticReconnect(
        current: HubNetworkPathFingerprint,
        shouldAttemptReconnect: Bool,
        remoteConnected: Bool,
        remoteRoute: HubRemoteRoute
    ) -> Bool {
        current.isSatisfied && shouldAttemptReconnect && remoteConnected && remoteRoute != .none
    }

    nonisolated static func shouldAllowAutomaticBootstrapReconnect(
        hasHubEnv: Bool,
        internetHost: String,
        inviteToken: String,
        inviteAlias: String,
        inviteInstanceID: String
    ) -> Bool {
        _ = internetHost
        _ = inviteToken
        _ = inviteAlias
        _ = inviteInstanceID
        // Automatic reconnect is only allowed for an already trusted paired profile.
        // Fresh pairing / invite-driven bootstrap remains an explicit user action.
        return hasHubEnv
    }

    nonisolated static func shouldAttemptStartupAutomaticFirstPair(
        internetHost: String,
        inviteToken: String,
        inviteAlias: String,
        inviteInstanceID: String
    ) -> Bool {
        guard normalizedStartupAutomaticFirstPairHint(inviteToken) != nil else { return false }

        let hasRouteHint = normalizedStartupAutomaticFirstPairHint(internetHost) != nil
        let hasIdentityHint =
            normalizedStartupAutomaticFirstPairHint(inviteAlias) != nil
            || normalizedStartupAutomaticFirstPairHint(inviteInstanceID) != nil
        return hasRouteHint || hasIdentityHint
    }

    nonisolated static func startupAutomaticConnectDisposition(
        hasHubEnv: Bool,
        internetHost: String,
        inviteToken: String,
        inviteAlias: String,
        inviteInstanceID: String
    ) -> HubStartupAutomaticConnectDisposition {
        _ = internetHost
        _ = inviteToken
        _ = inviteAlias
        _ = inviteInstanceID
        if hasHubEnv {
            return .recoverExistingProfile(allowBootstrap: false)
        }
        if shouldAttemptStartupAutomaticFirstPair(
            internetHost: internetHost,
            inviteToken: inviteToken,
            inviteAlias: inviteAlias,
            inviteInstanceID: inviteInstanceID
        ) {
            return .firstPairNearby
        }
        return .none
    }

    nonisolated static func shouldRunAutomaticFirstPairReconnectSmoke(
        after report: HubRemoteConnectReport?
    ) -> Bool {
        shouldRunFreshPairReconnectSmoke(after: report)
    }

    nonisolated static func shouldRunFreshPairReconnectSmoke(
        after report: HubRemoteConnectReport?
    ) -> Bool {
        guard let report else { return false }
        return report.ok && report.completedFreshPairing
    }

    private nonisolated static func normalizedStartupAutomaticFirstPairHint(
        _ raw: String
    ) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    nonisolated static func shouldRunRemoteShadowReconnectSmoke(
        after report: HubRemoteConnectReport?,
        pairedRouteSetSnapshot: XTPairedRouteSetSnapshot,
        existingSnapshot: XTRemoteShadowReconnectSmokeSnapshot?
    ) -> Bool {
        guard let report, report.ok else { return false }
        guard pairedRouteSetSnapshot.stableRemoteRoute != nil else { return false }
        if existingSnapshot?.status == .running || existingSnapshot?.status == .succeeded {
            return false
        }
        return true
    }

    nonisolated static func shouldSurfaceAutomaticRemoteConnectProgress(
        force: Bool,
        allowBootstrap: Bool,
        existingSummary: String,
        existingLog: String
    ) -> Bool {
        if force || allowBootstrap { return true }
        if existingSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        if existingLog.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        return false
    }

    nonisolated static func shouldInvalidateRemoteRouteAfterEndpointChange(
        previous: HubRemoteEndpointFingerprint,
        current: HubRemoteEndpointFingerprint
    ) -> Bool {
        previous != current
    }

    private func currentHubRemoteEndpointFingerprint() -> HubRemoteEndpointFingerprint {
        HubRemoteEndpointFingerprint(
            pairingPort: hubPairingPort,
            grpcPort: hubGrpcPort,
            internetHost: hubInternetHost
        )
    }

    func currentHubRemoteConnectOptions(stateDir: URL? = nil) -> HubRemoteConnectOptions {
        HubRemoteConnectOptions(
            grpcPort: hubGrpcPort,
            pairingPort: hubPairingPort,
            deviceName: Host.current().localizedName ?? "X-Terminal",
            internetHost: hubInternetHost,
            inviteToken: hubInviteToken,
            inviteAlias: hubInviteAlias,
            inviteInstanceID: hubInviteInstanceID,
            axhubctlPath: hubAxhubctlPath,
            configuredEndpointIsAuthoritative: hasHubRemoteEndpointOverridePending(),
            stateDir: stateDir
        )
    }

    private func refreshHubRemotePrefsFromPersistedStateIfNeeded() {
        let previousEndpoint = currentHubRemoteEndpointFingerprint()
        _ = synchronizeHubRemotePrefsFromCachedProfile(preferDiscoveredInternetHost: true)
        let currentEndpoint = currentHubRemoteEndpointFingerprint()
        guard Self.shouldInvalidateRemoteRouteAfterEndpointChange(
            previous: previousEndpoint,
            current: currentEndpoint
        ) else {
            return
        }

        if hubRemoteConnected || hubRemoteRoute != .none {
            hubRemoteConnected = false
            hubRemoteRoute = .none
            hubRemotePaidAccessSnapshot = nil
        }
        if !hubConnected {
            hubRemoteSummary = "paired hub updated; refreshing route ..."
        }
    }

    private func runRemoteConnectFlow(
        allowBootstrap: Bool,
        showAlertOnFinish: Bool,
        updateSetupProgress: Bool = true,
        initialSummary: String? = nil,
        openHubSetupOnFailure: Bool = false,
        repairTrigger: XTConnectivityRepairTrigger? = nil,
        repairOwner: XTConnectivityRepairOwner? = nil,
        repairDecisionReasonCode: String? = nil,
        preferredRoute: XTHubRouteCandidate? = nil,
        candidateRoutes: [XTHubRouteCandidate] = [],
        handoffReason: String? = nil,
        cooldownApplied: Bool = false,
        probeTrigger: XTHubConnectivityDecisionTrigger? = nil,
        probeDecision: XTHubConnectivityDecision? = nil,
        probeIncidentSnapshot: XTHubConnectivityIncidentSnapshot? = nil
    ) async -> HubRemoteConnectReport? {
        if hubRemoteLinking { return nil }
        hubRemoteLinking = true
        hubReconnectLastAttemptAt = Date()
        if updateSetupProgress {
            hubRemoteSummary = initialSummary ?? Self.defaultHubRemoteSetupSummary(allowBootstrap: allowBootstrap)
            hubRemoteLog = ""
            resetHubSetupProgress(allowBootstrap: allowBootstrap)
        }
        refreshHubRemotePrefsFromPersistedStateIfNeeded()
        saveHubRemotePrefs()

        let opts = currentHubRemoteConnectOptions(stateDir: nil)

        let progressHandler: (@Sendable (HubRemoteProgressEvent) -> Void)?
        if updateSetupProgress {
            progressHandler = { [weak self] event in
                DispatchQueue.main.async { [weak self] in
                    self?.applyHubSetupEvent(event)
                }
            }
        } else {
            progressHandler = nil
        }

        var effectiveAllowBootstrap = allowBootstrap
        var report = await HubPairingCoordinator.shared.ensureConnected(
            options: opts,
            allowBootstrap: effectiveAllowBootstrap,
            preferredRoute: preferredRoute,
            candidateRoutes: candidateRoutes,
            handoffReason: handoffReason,
            cooldownApplied: cooldownApplied,
            onProgress: progressHandler
        )

        if !report.ok,
           !allowBootstrap,
           showAlertOnFinish,
           report.reasonCode == "mtls_client_certificate_required" {
            effectiveAllowBootstrap = true
            if updateSetupProgress {
                hubRemoteSummary = "mTLS profile refresh required ..."
                resetHubSetupProgress(allowBootstrap: true)
            }
            report = await HubPairingCoordinator.shared.ensureConnected(
                options: opts,
                allowBootstrap: effectiveAllowBootstrap,
                preferredRoute: preferredRoute,
                candidateRoutes: candidateRoutes,
                handoffReason: handoffReason,
                cooldownApplied: cooldownApplied,
                onProgress: progressHandler
            )
        }

        hubRemoteLinking = false
        hubRemoteLog = report.logText
        hubRemoteConnected = report.ok
        hubRemoteRoute = report.route
        hubRemoteSummary = report.summary
        if report.ok {
            nextRemotePresenceRefreshAt = .distantPast
            await maybeRefreshRemotePresence(force: true)
            hubRemotePaidAccessSnapshot = await HubAIClient.shared.currentRemotePaidAccessSnapshot()
        } else {
            nextRemotePresenceRefreshAt = .distantPast
            hubRemotePaidAccessSnapshot = nil
        }
        if updateSetupProgress {
            hubSetupFailureCode = report.ok ? "" : (report.reasonCode ?? report.summary)
        }
        let repairIncidentSnapshot = currentHubConnectivityIncidentSnapshot(
            trigger: .backgroundKeepalive,
            currentPath: lastHubNetworkPathFingerprint
        )
        if let repairTrigger, let repairOwner {
            recordConnectivityRepairOutcome(
                trigger: repairTrigger,
                owner: repairOwner,
                allowBootstrap: allowBootstrap,
                decisionReasonCode: repairDecisionReasonCode,
                report: report,
                incidentSnapshot: repairIncidentSnapshot,
                recordedAt: Date()
            )
        }
        if let probeTrigger, let probeDecision, let probeIncidentSnapshot {
            recordHubNetworkHandoffOutcome(
                trigger: probeTrigger,
                allowBootstrap: effectiveAllowBootstrap,
                decision: probeDecision,
                incidentSnapshot: probeIncidentSnapshot,
                report: report,
                recordedAt: Date()
            )
        }
        hubConnectivityIncidentSnapshot = currentHubConnectivityIncidentSnapshot(
            trigger: .backgroundKeepalive,
            currentPath: lastHubNetworkPathFingerprint
        )

        if report.ok {
            setHubRemoteEndpointOverridePending(false)
            _ = synchronizeHubRemotePrefsFromCachedProfile(preferDiscoveredInternetHost: true)
            if Self.shouldConsumeHubInviteTokenAfterSuccessfulRemoteConnect(
                report: report,
                inviteToken: hubInviteToken,
                internetHost: hubInternetHost,
                hasHubEnv: HubPairingCoordinator.hasHubEnvFast(stateDir: nil)
            ) {
                hubInviteToken = ""
                saveHubRemotePrefs()
            }
            hubLastError = nil
            if showAlertOnFinish {
                showHubRemoteConnectAlert(for: report)
            }
        } else {
            if !hubConnected {
                hubLastError = "hub_remote_connect_failed (\(report.summary))"
            }
            if openHubSetupOnFailure {
                routeAutomaticFirstPairFailureToHubSetup(report)
            }
            if showAlertOnFinish {
                showHubRemoteConnectAlert(for: report)
            }
        }
        refreshUnifiedDoctorReport(force: true)
        return report
    }

    private func showHubRemoteConnectAlert(for report: HubRemoteConnectReport) {
        if report.ok {
            showAlert(
                title: "Hub Link Ready",
                message: "Route: \(report.route.rawValue)\n\n\(report.summary)"
            )
        } else {
            showAlert(
                title: "Hub Link Failed",
                message: report.logText.isEmpty ? report.summary : report.logText
            )
        }
    }

    private func routeAutomaticFirstPairFailureToHubSetup(_ report: HubRemoteConnectReport) {
        let rawReason = (report.reasonCode ?? report.summary)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawReason.isEmpty else { return }
        let repairContext = Self.automaticFirstPairRepairContext(
            for: rawReason,
            internetHost: hubInternetHost
        )

        requestHubSetupFocus(
            sectionId: "pair_hub",
            title: repairContext.title,
            detail: repairContext.detail
        )
        NotificationCenter.default.post(name: .xterminalOpenHubSetupWizard, object: nil)
    }

    nonisolated static func automaticFirstPairRepairContext(
        for rawReason: String,
        internetHost: String? = nil
    ) -> (title: String, detail: String) {
        let trimmedReason = rawReason.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedReason = UITroubleshootKnowledgeBase.normalizedFailureCode(trimmedReason)
        let hostClassification = XTHubRemoteAccessHostClassification.classify(internetHost)
        let host = hostClassification.displayHost ?? "未设置"

        if normalizedReason.contains("first_pair_requires_same_lan") {
            let detail: String
            switch hostClassification.kind {
            case .lanOnly, .rawIP(scope: .privateLAN), .rawIP(scope: .loopback), .rawIP(scope: .linkLocal):
                detail = "Hub 已经明确拒绝这次首次配对，因为它没有把 XT 识别成“同一局域网来源”。即使你看到的是同一个 Wi‑Fi 名称，也可能因为 client isolation、访客网络或 VLAN 分段而被判成不同 LAN。当前目标 \(host) 这类入口只适合同一局域网 / 同一 VPN 使用；请先让 XT 和 Hub 真正回到同一 LAN 后再重试。reason=\(trimmedReason)"
            case .rawIP(scope: .carrierGradeNat), .rawIP(scope: .publicInternet), .stableNamed:
                detail = "首次 Hub 配对默认不会直接在公网或正式远端入口上放行；必须先在同一局域网内完成一次本地批准，后续才能稳定走异网重连。请先把 XT 和 Hub 放回同一 LAN 完成首配。reason=\(trimmedReason)"
            case .missing:
                detail = "首次 Hub 配对默认只允许在同一 Wi‑Fi 或同一局域网内完成。请让 XT 和 Hub 回到同网环境后重试。reason=\(trimmedReason)"
            case .rawIP:
                detail = "首次 Hub 配对默认只允许在同一 Wi‑Fi 或同一局域网内完成。请让 XT 和 Hub 回到同网环境后重试。reason=\(trimmedReason)"
            }
            return (
                "回到同一 Wi-Fi 完成首次配对",
                detail
            )
        }

        if normalizedReason.contains("pairing_approval_timeout") {
            return (
                "在 Hub 上批准这次首次配对",
                "XT 已经发起首次配对，但 Hub 端在等待本机 owner 批准时超时。请回到 Hub 主机，打开首配批准卡并完成 Touch ID / Face ID / 本机密码验证后重试。reason=\(trimmedReason)"
            )
        }

        if normalizedReason.contains("pairing_owner_auth_cancelled") {
            return (
                "回到 Hub 重新确认首次配对",
                "Hub 侧本机 owner 验证被取消，所以首次配对保持 pending 未完成。请在 Hub 主机重新批准，并完成 Touch ID / Face ID / 本机密码验证。reason=\(trimmedReason)"
            )
        }

        if normalizedReason.contains("pairing_owner_auth_failed") {
            return (
                "先修复 Hub 本机验证再配对",
                "Hub 无法完成本机 owner 验证，所以不会下发首次配对资料。请先在 Hub 主机确认 Touch ID / Face ID / 本机密码可用，再重新批准。reason=\(trimmedReason)"
            )
        }

        if normalizedReason.contains("hub_instance_mismatch") {
            return (
                "清掉旧 Hub 档案后重新配对",
                "XT 当前拿着的配对档案和现在响应的 Hub 实例不是同一台主机。继续重试通常只会反复得到 unauthenticated / certificate 失败；请先清理旧配对，再重新打开正确的 Hub 邀请或在同网环境重新首配。reason=\(trimmedReason)"
            )
        }

        if normalizedReason.contains("pairing_profile_epoch_stale") {
            return (
                "刷新最新配对档案后再重连",
                "Hub 侧配对档案已经更新，但 XT 还在使用旧 profile。请先清理本地旧令牌/证书与旧配对档案，再重新拉取当前 Hub 的配对材料。reason=\(trimmedReason)"
            )
        }

        if normalizedReason.contains("route_pack_outdated") {
            return (
                "重新导入最新远端入口",
                "Hub 当前正式远端入口已经换代，但 XT 还在使用旧的 host / port / token 材料。请重新打开最新邀请链接或重新导出接入包，再继续连接。reason=\(trimmedReason)"
            )
        }

        if normalizedReason.contains("local_network_permission_required")
            || normalizedReason.contains("local_network_discovery_blocked") {
            return (
                "先允许 XT 访问本地网络",
                "XT 当前只能看到本机 loopback Hub，看不到同一 Wi-Fi 上的远端 Hub。先到系统设置 → 隐私与安全性 → 本地网络允许 X-Terminal；如果已经允许，再检查当前 Wi-Fi / AP 是否开启了 client isolation，并确认 XT 能访问 Hub 的 pairing 端口。reason=\(trimmedReason)"
            )
        }

        let issue = UITroubleshootKnowledgeBase.issue(forFailureCode: trimmedReason)
        switch issue {
        case .multipleHubsAmbiguous:
            return (
                "选择要连接的 Hub",
                "启动时自动发现到多台 Hub；请在“连接 Hub”里固定目标 Hub 后继续。reason=\(trimmedReason)"
            )
        case .hubPortConflict:
            return (
                "修复 Hub 端口冲突",
                "后台自动首配被端口冲突拦住；请在“连接 Hub”里核对配对端口与 gRPC 端口。reason=\(trimmedReason)"
            )
        case .hubUnreachable:
            let hostClassification = XTHubRemoteAccessHostClassification.classify(internetHost)
            let host = hostClassification.displayHost ?? "未设置"
            switch hostClassification.kind {
            case .missing:
                return (
                    "先补正式远端入口，再继续连接",
                    "XT 当前还没有正式 Internet Host。若这是第一次配对，请先把 XT 和 Hub 放回同一 Wi‑Fi / 同一局域网完成首配；若要异网接入，再到 Hub 配置稳定主机名并重新导出接入包。reason=\(trimmedReason)"
                )
            case .lanOnly:
                return (
                    "当前只有同网入口，先回同网或改正式入口",
                    "XT 当前记录的 Internet Host 还是 \(host)，这类入口只适合同一 Wi‑Fi / 同一局域网或同一 VPN。若要异网接入，请到 Hub 配置稳定主机名后再重试。reason=\(trimmedReason)"
                )
            case .rawIP(let scope):
                switch scope {
                case .privateLAN, .loopback, .linkLocal:
                    return (
                        "先确认当前仍在同一局域网 / 同一 VPN",
                        "XT 当前记录的是\(scope.doctorLabel) \(host)。这类 raw IP 只在同一局域网、同一 VPN，或本机回环路径里可达；一旦换 Wi‑Fi、跨 VLAN、跨网段或离开 VPN，通常就会直接超时。请先确认 XT 还能路由到这条 LAN 路径，或改成稳定命名入口后再试。reason=\(trimmedReason)"
                    )
                case .carrierGradeNat:
                    return (
                        "先替换运营商 NAT 地址入口",
                        "XT 当前记录的是运营商 NAT 地址 \(host)。这类地址通常不适合被另一台设备直接回连；请改成稳定命名入口、relay 或 VPN 地址后再试。reason=\(trimmedReason)"
                    )
                case .publicInternet, .unknown:
                    return (
                        "先替换临时 raw IP 入口",
                        "XT 当前记录的是\(scope.doctorLabel) \(host)。这类 raw IP 在换网、休眠、NAT 或公网 IP 变化后很容易失效；请先确认它仍指向当前 Hub，或改成稳定命名入口后再重试。reason=\(trimmedReason)"
                    )
                }
            case .stableNamed:
                return (
                    "Hub 远端入口已配置，先检查服务是否在线",
                    "XT 当前已有稳定命名入口 \(host)，但这次仍无法连通。请回 Hub 主机确认 app 没休眠、pairing / gRPC 端口正在监听，并检查防火墙、NAT 或 relay 转发。reason=\(trimmedReason)"
                )
            }
        default:
            return (
                "完成首次 Hub 配对",
                "后台自动首配未完成；请在“连接 Hub”里继续修复。reason=\(trimmedReason)"
            )
        }
    }

    private func configuredHubModelIDs() -> [String] {
        AXRole.allCases.compactMap { role in
            let model = (settingsStore.settings.assignment(for: role).model ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return model.isEmpty ? nil : model
        }
    }

    private func currentDoctorSession() -> AXSessionInfo? {
        if let selectedProjectId,
           selectedProjectId != AXProjectRegistry.globalHomeId,
           let session = sessionManager.primarySession(for: selectedProjectId) {
            return session
        }
        if let activeSessionId = sessionManager.activeSessionId,
           let session = sessionManager.session(for: activeSessionId) {
            return session
        }
        return sessionManager.sessions
            .compactMap { sessionManager.session(for: $0.id) ?? $0 }
            .sorted { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhs.id < rhs.id
        }
            .first
    }

    struct DoctorProjectSelection: Equatable {
        var session: AXSessionInfo?
        var projectId: String?
        var projectLabel: String?
        var context: AXProjectContext?
        var config: AXProjectConfig?
    }

    struct DoctorProjectMemoryAdvisory: Equatable {
        var projectId: String?
        var projectLabel: String?
        var readiness: XTProjectMemoryAssemblyReadiness?
    }

    func doctorProjectSelection(
        preferredProjectId: String? = nil
    ) -> DoctorProjectSelection {
        if let preferredProjectId = normalizedDoctorProjectId(preferredProjectId),
           let context = projectContext(for: preferredProjectId) {
            return DoctorProjectSelection(
                session: sessionManager.primarySession(for: preferredProjectId),
                projectId: preferredProjectId,
                projectLabel: doctorProjectLabel(
                    projectId: preferredProjectId,
                    context: context
                ),
                context: context,
                config: projectConfigSnapshot(for: context)
            )
        }

        let session = currentDoctorSession()
        let context = currentDoctorProjectContext(session: session)
        let config = currentDoctorProjectConfig(context: context)
        let projectId = context.map { AXProjectRegistryStore.projectId(forRoot: $0.root) }
            ?? normalizedDoctorProjectId(session?.projectId)
        return DoctorProjectSelection(
            session: session,
            projectId: projectId,
            projectLabel: doctorProjectLabel(
                projectId: projectId,
                context: context
            ),
            context: context,
            config: config
        )
    }

    func doctorProjectMemoryAdvisory(
        preferredProjectId: String? = nil
    ) -> DoctorProjectMemoryAdvisory {
        let selection = doctorProjectSelection(preferredProjectId: preferredProjectId)
        guard let context = selection.context else {
            return DoctorProjectMemoryAdvisory(
                projectId: selection.projectId,
                projectLabel: selection.projectLabel,
                readiness: nil
            )
        }

        let diagnostics = AXProjectContextAssemblyDiagnosticsStore.doctorSummary(
            for: context,
            config: selection.config
        )
        return DoctorProjectMemoryAdvisory(
            projectId: selection.projectId,
            projectLabel: selection.projectLabel,
            readiness: diagnostics.memoryAssemblyReadiness
        )
    }

    private func currentDoctorProjectContext(session: AXSessionInfo?) -> AXProjectContext? {
        if let selectedProjectId,
           selectedProjectId != AXProjectRegistry.globalHomeId,
           let projectContext {
            return projectContext
        }

        if let session {
            let sessionDirectory = session.directory.trimmingCharacters(in: .whitespacesAndNewlines)
            if !sessionDirectory.isEmpty {
                let root = URL(fileURLWithPath: sessionDirectory, isDirectory: true)
                var isDirectory: ObjCBool = false
                if FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory),
                   isDirectory.boolValue {
                    return AXProjectContext(root: root)
                }
            }

            if let entry = registry.project(for: session.projectId),
               let root = resolvedProjectRootURL(for: entry) {
                return AXProjectContext(root: root)
            }
        }

        return nil
    }

    private func currentDoctorProjectConfig(
        context: AXProjectContext?
    ) -> AXProjectConfig? {
        guard let context else { return nil }
        if let projectContext, projectContext.root.path == context.root.path {
            return projectConfig
        }
        guard FileManager.default.fileExists(atPath: context.configURL.path),
              let data = try? Data(contentsOf: context.configURL),
              var config = try? JSONDecoder().decode(AXProjectConfig.self, from: data) else {
            return nil
        }
        config.schemaVersion = AXProjectConfig.currentSchemaVersion
        return config
    }

    private func currentDoctorHeartbeatGovernanceSnapshot(
        context: AXProjectContext?,
        config: AXProjectConfig?,
        projectMemoryReadiness: XTProjectMemoryAssemblyReadiness?,
        projectMemoryContext: XTHeartbeatProjectMemoryContextSnapshot?,
        laneSnapshot: SupervisorLaneHealthSnapshot?,
        now: Date
    ) -> XTProjectHeartbeatGovernanceDoctorSnapshot? {
        guard let context else { return nil }
        let resolvedConfig = config ?? AXProjectConfig.default(forProjectRoot: context.root)
        let projectId = AXProjectRegistryStore.projectId(forRoot: context.root)
        let project = registry.project(for: projectId) ?? AXProjectEntry(
            projectId: projectId,
            rootPath: context.root.path,
            displayName: AXProjectRegistryStore.displayName(forRoot: context.root, registry: registry),
            lastOpenedAt: now.timeIntervalSince1970,
            manualOrderIndex: nil,
            pinned: false,
            statusDigest: nil,
            currentStateSummary: nil,
            nextStepSummary: nil,
            blockerSummary: nil,
            lastSummaryAt: nil,
            lastEventAt: nil
        )
        return XTProjectHeartbeatGovernanceDoctorBuilder.build(
            project: project,
            context: context,
            config: resolvedConfig,
            projectMemoryReadiness: projectMemoryReadiness,
            projectMemoryContext: projectMemoryContext,
            laneSnapshot: laneSnapshot,
            now: now
        )
    }

    private func currentPairedRouteSetSnapshot() -> XTPairedRouteSetSnapshot {
        let cachedProfile = HubAIClient.cachedRemoteProfile(stateDir: nil)
        return XTPairedRouteSetSnapshotBuilder.build(
            input: XTPairedRouteSetBuildInput(
                cachedProfile: cachedProfile,
                configuredInternetHost: hubInternetHost,
                configuredHubInstanceID: hubInviteInstanceID,
                pairingPort: hubPairingPort,
                grpcPort: hubGrpcPort,
                localConnected: hubConnected,
                remoteConnected: hubRemoteConnected,
                remoteRoute: hubRemoteRoute,
                linking: hubRemoteLinking,
                failureCode: hubSetupFailureCode,
                freshPairReconnectSmokeSnapshot: hubFreshPairReconnectSmokeSnapshot,
                remoteShadowReconnectSmokeSnapshot: hubRemoteShadowReconnectSmokeSnapshot
            )
        )
    }

    private func refreshUnifiedDoctorReport(force: Bool = false) {
        let now = Date()
        if !force, now < nextUnifiedDoctorRefreshAt {
            return
        }

        let doctorProjectSelectionSnapshot = doctorProjectSelection()
        let doctorProjectContext = doctorProjectSelectionSnapshot.context
        let doctorProjectConfig = doctorProjectSelectionSnapshot.config
        let projectGovernanceResolved: AXProjectResolvedGovernanceState? = {
            guard let doctorProjectContext, let doctorProjectConfig else {
                return nil
            }
            return xtResolveProjectGovernance(
                projectRoot: doctorProjectContext.root,
                config: doctorProjectConfig,
                permissionReadiness: .current()
            )
        }()
        let projectContextDiagnostics = AXProjectContextAssemblyDiagnosticsStore.doctorSummary(
            for: doctorProjectContext,
            config: doctorProjectConfig
        )
        let heartbeatProjectMemoryContext = doctorProjectContext.flatMap { context in
            XTHeartbeatMemoryProjectionStore.load(for: context)?.rawPayload.projectMemoryContext
                ?? XTHeartbeatProjectMemoryContextSnapshot.from(summary: projectContextDiagnostics)
        }
        let supervisor = SupervisorManager.shared
        let heartbeatGovernanceSnapshot = currentDoctorHeartbeatGovernanceSnapshot(
            context: doctorProjectContext,
            config: doctorProjectConfig,
            projectMemoryReadiness: projectContextDiagnostics.memoryAssemblyReadiness,
            projectMemoryContext: heartbeatProjectMemoryContext,
            laneSnapshot: supervisor.supervisorLaneHealthSnapshot,
            now: now
        )
        let reportURL = XTUnifiedDoctorStore.defaultReportURL()
        let calendarReminderPreferences = settingsStore.settings.supervisorCalendarReminders.normalized()
        let calendarAccessController = XTCalendarAccessController.shared
        calendarAccessController.refreshAuthorizationStatus()
        let calendarEventStore = XTCalendarEventStore.shared
        let pairedRouteSetSnapshot = currentPairedRouteSetSnapshot()
        let cachedRemoteProfile = HubAIClient.cachedRemoteProfile(stateDir: nil)
        let firstPairCompletionProofSnapshot = XTFirstPairCompletionProofBuilder.build(
            input: XTFirstPairCompletionProofBuildInput(
                generatedAt: now,
                localConnected: hubConnected,
                remoteConnected: hubRemoteConnected,
                remoteRoute: hubRemoteRoute,
                cachedProfile: cachedRemoteProfile,
                freshPairReconnectSmokeSnapshot: hubFreshPairReconnectSmokeSnapshot,
                remoteShadowReconnectSmokeSnapshot: hubRemoteShadowReconnectSmokeSnapshot,
                pairedRouteSetSnapshot: pairedRouteSetSnapshot
            )
        )
        let connectivityIncidentSnapshot = hubConnectivityIncidentSnapshot
            ?? currentHubConnectivityIncidentSnapshot(
                trigger: .backgroundKeepalive,
                currentPath: lastHubNetworkPathFingerprint,
                pairedRouteSetSnapshot: pairedRouteSetSnapshot,
                updatedAt: now
            )
        let activeSessionInfo: AXSessionInfo? = projectContext.map { ctx in
            sessionManager.ensurePrimarySession(
                projectId: AXProjectRegistryStore.projectId(forRoot: ctx.root),
                title: ctx.displayName(registry: registry),
                directory: ctx.root.standardizedFileURL.path
            )
        }
        let skillDoctorTruthProjection: XTUnifiedDoctorSkillDoctorTruthProjection? = {
            guard let projectId = doctorProjectSelectionSnapshot.projectId?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                  !projectId.isEmpty,
                  let context = doctorProjectContext else {
                return nil
            }
            let projectName = doctorProjectSelectionSnapshot.projectLabel
            let resolvedHubBaseDir = hubBaseDir ?? HubPaths.baseDir()
            let effectiveProfileSnapshot = AXSkillsLibrary.projectEffectiveSkillProfileSnapshot(
                projectId: projectId,
                projectName: projectName,
                projectRoot: context.root,
                config: doctorProjectConfig,
                hubBaseDir: resolvedHubBaseDir
            )
            let governanceEntries = skillsCompatibilitySnapshot.governanceSurfaceEntries(
                projectId: projectId,
                projectName: projectName,
                projectRoot: context.root,
                config: doctorProjectConfig,
                hubBaseDir: resolvedHubBaseDir
            )
            return XTUnifiedDoctorSkillDoctorTruthProjection(
                effectiveProfileSnapshot: effectiveProfileSnapshot,
                governanceEntries: governanceEntries
            )
        }()
        let calendarReminderSnapshot = XTUnifiedDoctorCalendarReminderSnapshot(
            enabled: calendarReminderPreferences.enabled,
            headsUpMinutes: calendarReminderPreferences.headsUpMinutes,
            finalCallMinutes: calendarReminderPreferences.finalCallMinutes,
            notificationFallbackEnabled: calendarReminderPreferences.notificationFallbackEnabled,
            authorizationStatus: calendarAccessController.authorizationStatus,
            authorizationGuidanceText: calendarAccessController.authorizationStatus.guidanceText,
            schedulerStatusLine: supervisorCalendarReminderScheduler.statusLine,
            schedulerLastRunAtMs: Int64(supervisorCalendarReminderScheduler.lastRunAt * 1000),
            eventStoreStatusLine: calendarEventStore.statusLine,
            eventStoreLastRefreshedAtMs: Int64(calendarEventStore.lastRefreshedAt * 1000),
            upcomingMeetingCount: calendarEventStore.upcomingMeetings.count,
            upcomingMeetingPreviewLines: Array(calendarEventStore.upcomingMeetings.prefix(3)).map { meeting in
                let title = meeting.title
                    .replacingOccurrences(of: "\n", with: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return "\(title) | \(meeting.relativeStartText(now: now))"
            }
        )
        let input = XTUnifiedDoctorInput(
            generatedAt: now,
            localConnected: hubConnected,
            remoteConnected: hubRemoteConnected,
            remoteRoute: hubRemoteRoute,
            remotePaidAccessSnapshot: hubRemotePaidAccessSnapshot,
            linking: hubRemoteLinking,
            pairingPort: hubPairingPort,
            grpcPort: hubGrpcPort,
            internetHost: hubInternetHost,
            configuredModelIDs: configuredHubModelIDs(),
            totalModelRoles: AXRole.allCases.count,
            failureCode: hubSetupFailureCode,
            runtime: capturedRuntimeSnapshot(),
            runtimeStatus: runtimeStatus,
            modelsState: modelsState,
            bridgeAlive: bridgeAlive,
            bridgeEnabled: bridgeEnabled,
            bridgeLastError: bridgeLastEnsureError,
            sessionID: activeSessionInfo?.id,
            sessionTitle: activeSessionInfo?.title,
            sessionRuntime: activeSessionInfo?.runtime,
            voiceRouteDecision: supervisor.voiceRouteDecision,
            voiceRuntimeState: supervisor.voiceRuntimeState,
            voiceAuthorizationStatus: supervisor.voiceAuthorizationStatus,
            voicePermissionSnapshot: supervisor.voicePermissionSnapshot,
            voiceActiveHealthReasonCode: supervisor.voiceActiveHealthReasonCode,
            voiceSidecarHealth: supervisor.voiceFunASRSidecarHealth,
            wakeProfileSnapshot: supervisor.voiceWakeProfileSnapshot,
            conversationSession: supervisor.conversationSessionSnapshot,
            voicePreferences: supervisor.effectiveVoicePreferencesForDiagnostics(),
            voicePlaybackActivity: supervisor.voicePlaybackActivity,
            calendarReminderSnapshot: calendarReminderSnapshot,
            skillsSnapshot: skillsCompatibilitySnapshot,
            skillDoctorTruthProjection: skillDoctorTruthProjection,
            reportPath: reportURL.path,
            modelRouteDiagnostics: AXModelRouteDiagnosticsStore.doctorSummary(
                for: sortedProjects,
                now: now
            ),
            projectContextDiagnostics: projectContextDiagnostics,
            projectGovernanceResolved: projectGovernanceResolved,
            heartbeatGovernanceSnapshot: heartbeatGovernanceSnapshot,
            supervisorMemoryAssemblySnapshot: supervisor.supervisorMemoryAssemblySnapshot,
            supervisorLatestTurnContextAssembly: supervisor.supervisorLatestTurnContextAssembly,
            doctorProjectContext: doctorProjectContext,
            supervisorVoiceSmokeReport: loadSupervisorVoiceSmokeReportSummary(),
            freshPairReconnectSmokeSnapshot: hubFreshPairReconnectSmokeSnapshot,
            firstPairCompletionProofSnapshot: firstPairCompletionProofSnapshot,
            pairedRouteSetSnapshot: pairedRouteSetSnapshot,
            connectivityIncidentSnapshot: connectivityIncidentSnapshot
        )
        let report = XTUnifiedDoctorBuilder.build(input: input)
        XTUnifiedDoctorStore.writeReport(report, to: reportURL)
        let genericDoctorURL = XHubDoctorOutputStore.defaultXTReportURL()
        let genericDoctorReport = XHubDoctorOutputReport.xtReadinessBundle(
            from: report,
            outputPath: genericDoctorURL.path
        )
        XHubDoctorOutputStore.writeReport(genericDoctorReport, to: genericDoctorURL)
        unifiedDoctorReport = report
        nextUnifiedDoctorRefreshAt = now.addingTimeInterval(6.0)
    }

    private func normalizedDoctorProjectId(_ raw: String?) -> String? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty,
              raw != AXProjectRegistry.globalHomeId else {
            return nil
        }
        return raw
    }

    private func doctorProjectLabel(
        projectId: String?,
        context: AXProjectContext?
    ) -> String? {
        if let projectId = normalizedDoctorProjectId(projectId),
           let displayName = registry.project(for: projectId)?.displayName.trimmingCharacters(in: .whitespacesAndNewlines),
           !displayName.isEmpty {
            return displayName
        }
        if let context {
            let displayName = AXProjectRegistryStore.displayName(forRoot: context.root, registry: registry)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !displayName.isEmpty {
                return displayName
            }
        }
        return normalizedDoctorProjectId(projectId)
    }

    private func capturedRuntimeSnapshot() -> UIFailClosedRuntimeSnapshot {
        guard let orchestrator = legacySupervisorRuntimeContextIfLoaded?.orchestrator else {
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

    private func refreshSkillsCompatibilitySnapshot(force: Bool = false) {
        let now = Date()
        if !force, now < nextSkillsCompatibilityRefreshAt {
            return
        }
        let selectedProject = selectedProjectId == AXProjectRegistry.globalHomeId ? nil : selectedProjectId
        let projectName = selectedProject.flatMap { registry.project(for: $0)?.displayName }
        let skillsDir = AXSkillsLibrary.resolveSkillsDirectory()
        let previousOfficialChannelID = skillsCompatibilitySnapshot.officialChannelID
        let previousOfficialChannelStatus = skillsCompatibilitySnapshot.officialChannelStatus
        let previousOfficialChannelUpdatedAtMs = skillsCompatibilitySnapshot.officialChannelUpdatedAtMs
        let previousOfficialChannelLastSuccessAtMs = skillsCompatibilitySnapshot.officialChannelLastSuccessAtMs
        let previousOfficialChannelSkillCount = skillsCompatibilitySnapshot.officialChannelSkillCount
        let previousOfficialChannelErrorCode = skillsCompatibilitySnapshot.officialChannelErrorCode
        let previousOfficialChannelMaintenanceEnabled = skillsCompatibilitySnapshot.officialChannelMaintenanceEnabled
        let previousOfficialChannelMaintenanceIntervalMs = skillsCompatibilitySnapshot.officialChannelMaintenanceIntervalMs
        let previousOfficialChannelMaintenanceLastRunAtMs = skillsCompatibilitySnapshot.officialChannelMaintenanceLastRunAtMs
        let previousOfficialChannelMaintenanceSourceKind = skillsCompatibilitySnapshot.officialChannelMaintenanceSourceKind
        let previousOfficialChannelLastTransitionAtMs = skillsCompatibilitySnapshot.officialChannelLastTransitionAtMs
        let previousOfficialChannelLastTransitionKind = skillsCompatibilitySnapshot.officialChannelLastTransitionKind
        let previousOfficialChannelLastTransitionSummary = skillsCompatibilitySnapshot.officialChannelLastTransitionSummary
        skillsCompatibilitySnapshot = AXSkillsLibrary.compatibilityDoctorSnapshot(
            projectId: selectedProject,
            projectName: projectName,
            skillsDir: skillsDir,
            hubBaseDir: hubBaseDir
        )
        let previousSnapshot = AXSkillsDoctorSnapshot(
            hubIndexAvailable: skillsCompatibilitySnapshot.hubIndexAvailable,
            installedSkillCount: skillsCompatibilitySnapshot.installedSkillCount,
            compatibleSkillCount: skillsCompatibilitySnapshot.compatibleSkillCount,
            partialCompatibilityCount: skillsCompatibilitySnapshot.partialCompatibilityCount,
            revokedMatchCount: skillsCompatibilitySnapshot.revokedMatchCount,
            trustEnabledPublisherCount: skillsCompatibilitySnapshot.trustEnabledPublisherCount,
            baselineRecommendedSkills: skillsCompatibilitySnapshot.baselineRecommendedSkills,
            missingBaselineSkillIDs: skillsCompatibilitySnapshot.missingBaselineSkillIDs,
            builtinGovernedSkills: skillsCompatibilitySnapshot.builtinGovernedSkills,
            projectIndexEntries: skillsCompatibilitySnapshot.projectIndexEntries,
            globalIndexEntries: skillsCompatibilitySnapshot.globalIndexEntries,
            conflictWarnings: skillsCompatibilitySnapshot.conflictWarnings,
            installedSkills: skillsCompatibilitySnapshot.installedSkills,
            statusKind: skillsCompatibilitySnapshot.statusKind,
            statusLine: skillsCompatibilitySnapshot.statusLine,
            compatibilityExplain: skillsCompatibilitySnapshot.compatibilityExplain,
            officialChannelID: previousOfficialChannelID,
            officialChannelStatus: previousOfficialChannelStatus,
            officialChannelUpdatedAtMs: previousOfficialChannelUpdatedAtMs,
            officialChannelLastSuccessAtMs: previousOfficialChannelLastSuccessAtMs,
            officialChannelSkillCount: previousOfficialChannelSkillCount,
            officialChannelErrorCode: previousOfficialChannelErrorCode,
            officialChannelMaintenanceEnabled: previousOfficialChannelMaintenanceEnabled,
            officialChannelMaintenanceIntervalMs: previousOfficialChannelMaintenanceIntervalMs,
            officialChannelMaintenanceLastRunAtMs: previousOfficialChannelMaintenanceLastRunAtMs,
            officialChannelMaintenanceSourceKind: previousOfficialChannelMaintenanceSourceKind,
            officialChannelLastTransitionAtMs: previousOfficialChannelLastTransitionAtMs,
            officialChannelLastTransitionKind: previousOfficialChannelLastTransitionKind,
            officialChannelLastTransitionSummary: previousOfficialChannelLastTransitionSummary
        )
        mergeOfficialSkillChannelStatusFallback(previousSnapshot)
        nextSkillsCompatibilityRefreshAt = now.addingTimeInterval(12.0)
        refreshUnifiedDoctorReport(force: force)
        refreshRemoteSkillsCompatibilityOverlayIfNeeded(projectId: selectedProject)
    }

    private func mergeOfficialSkillChannelStatusFallback(_ previous: AXSkillsDoctorSnapshot) {
        let currentStatus = skillsCompatibilitySnapshot.officialChannelStatus.trimmingCharacters(in: .whitespacesAndNewlines)
        let previousStatus = previous.officialChannelStatus.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentUpdatedAt = max(0, skillsCompatibilitySnapshot.officialChannelUpdatedAtMs)
        let previousUpdatedAt = max(0, previous.officialChannelUpdatedAtMs)
        let shouldUsePrevious = (!previousStatus.isEmpty && currentStatus.isEmpty)
            || (previousUpdatedAt > currentUpdatedAt)

        guard shouldUsePrevious else { return }

        skillsCompatibilitySnapshot.officialChannelID = previous.officialChannelID
        skillsCompatibilitySnapshot.officialChannelStatus = previous.officialChannelStatus
        skillsCompatibilitySnapshot.officialChannelUpdatedAtMs = previous.officialChannelUpdatedAtMs
        skillsCompatibilitySnapshot.officialChannelLastSuccessAtMs = previous.officialChannelLastSuccessAtMs
        skillsCompatibilitySnapshot.officialChannelSkillCount = previous.officialChannelSkillCount
        skillsCompatibilitySnapshot.officialChannelErrorCode = previous.officialChannelErrorCode
        skillsCompatibilitySnapshot.officialChannelMaintenanceEnabled = previous.officialChannelMaintenanceEnabled
        skillsCompatibilitySnapshot.officialChannelMaintenanceIntervalMs = previous.officialChannelMaintenanceIntervalMs
        skillsCompatibilitySnapshot.officialChannelMaintenanceLastRunAtMs = previous.officialChannelMaintenanceLastRunAtMs
        skillsCompatibilitySnapshot.officialChannelMaintenanceSourceKind = previous.officialChannelMaintenanceSourceKind
        skillsCompatibilitySnapshot.officialChannelLastTransitionAtMs = previous.officialChannelLastTransitionAtMs
        skillsCompatibilitySnapshot.officialChannelLastTransitionKind = previous.officialChannelLastTransitionKind
        skillsCompatibilitySnapshot.officialChannelLastTransitionSummary = previous.officialChannelLastTransitionSummary
    }

    private func refreshRemoteSkillsCompatibilityOverlayIfNeeded(projectId: String?) {
        guard hubInteractive else { return }
        guard !remoteSkillsCompatibilityOverlayInFlight else { return }

        let normalizedProjectId = projectId?.trimmingCharacters(in: .whitespacesAndNewlines)
        let now = Date()
        if normalizedProjectId == lastRemoteSkillsCompatibilityOverlayProjectId,
           now < nextRemoteSkillsCompatibilityOverlayRefreshAt {
            return
        }

        let baseline = skillsCompatibilitySnapshot.baselineRecommendedSkills.isEmpty
            ? AXSkillsLibrary.defaultAgentBaselineSkills
            : skillsCompatibilitySnapshot.baselineRecommendedSkills
        guard !baseline.isEmpty else { return }

        lastRemoteSkillsCompatibilityOverlayProjectId = normalizedProjectId
        nextRemoteSkillsCompatibilityOverlayRefreshAt = now.addingTimeInterval(
            Self.remoteSkillsCompatibilityOverlayRefreshIntervalSec
        )
        remoteSkillsCompatibilityOverlayInFlight = true
        Task { @MainActor in
            defer { remoteSkillsCompatibilityOverlayInFlight = false }
            async let resolvedRequest = HubIPCClient.listResolvedSkills(projectId: normalizedProjectId)
            async let searchRequest = HubIPCClient.searchSkills(
                query: "",
                sourceFilter: "builtin:catalog",
                projectId: normalizedProjectId,
                limit: 1
            )
            let resolved = await resolvedRequest
            let search = await searchRequest

            let currentDisplayedProjectId = selectedProjectId == AXProjectRegistry.globalHomeId ? nil : selectedProjectId
            guard currentDisplayedProjectId == normalizedProjectId else { return }
            let statusChanged = applyOfficialSkillChannelStatusOverlay(search.officialChannelStatus)
            guard resolved.ok else {
                if statusChanged {
                    refreshUnifiedDoctorReport(force: true)
                }
                return
            }

            let resolvedIDs = Set(
                resolved.skills.map { $0.skill.skillID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            )
            let missingBaselineSkillIDs = baseline
                .map(\.skillID)
                .filter { !resolvedIDs.contains($0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) }

            guard missingBaselineSkillIDs != skillsCompatibilitySnapshot.missingBaselineSkillIDs else {
                if statusChanged {
                    refreshUnifiedDoctorReport(force: true)
                }
                return
            }

            skillsCompatibilitySnapshot.missingBaselineSkillIDs = missingBaselineSkillIDs
            skillsCompatibilitySnapshot.statusKind = overlaySkillsStatusKind(
                base: skillsCompatibilitySnapshot,
                missingBaselineSkillIDs: missingBaselineSkillIDs
            )
            skillsCompatibilitySnapshot.statusLine = overlaySkillsStatusLine(
                base: skillsCompatibilitySnapshot,
                missingBaselineSkillIDs: missingBaselineSkillIDs,
                totalBaselineCount: baseline.count
            )
            skillsCompatibilitySnapshot.compatibilityExplain = overlaySkillsCompatibilityExplain(
                base: skillsCompatibilitySnapshot.compatibilityExplain,
                missingBaselineSkillIDs: missingBaselineSkillIDs,
                totalBaselineCount: baseline.count
            )
            refreshUnifiedDoctorReport(force: true)
        }
    }

    private func applyOfficialSkillChannelStatusOverlay(
        _ status: HubIPCClient.OfficialSkillChannelStatus?
    ) -> Bool {
        guard let status else { return false }
        let normalizedChannelID = status.channelID.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedState = status.status.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedError = status.errorCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let nextUpdatedAtMs = max(0, status.updatedAtMs)
        let nextLastSuccessAtMs = max(0, status.lastSuccessAtMs)
        let nextSkillCount = max(0, status.skillCount)
        let nextMaintenanceEnabled = status.maintenanceEnabled
        let nextMaintenanceIntervalMs = max(0, status.maintenanceIntervalMs)
        let nextMaintenanceLastRunAtMs = max(0, status.maintenanceLastRunAtMs)
        let nextMaintenanceSourceKind = status.maintenanceSourceKind.trimmingCharacters(in: .whitespacesAndNewlines)
        let nextLastTransitionAtMs = max(0, status.lastTransitionAtMs)
        let nextLastTransitionKind = status.lastTransitionKind.trimmingCharacters(in: .whitespacesAndNewlines)
        let nextLastTransitionSummary = status.lastTransitionSummary.trimmingCharacters(in: .whitespacesAndNewlines)

        if skillsCompatibilitySnapshot.officialChannelID == normalizedChannelID,
           skillsCompatibilitySnapshot.officialChannelStatus == normalizedState,
           skillsCompatibilitySnapshot.officialChannelUpdatedAtMs == nextUpdatedAtMs,
           skillsCompatibilitySnapshot.officialChannelLastSuccessAtMs == nextLastSuccessAtMs,
           skillsCompatibilitySnapshot.officialChannelSkillCount == nextSkillCount,
           skillsCompatibilitySnapshot.officialChannelErrorCode == normalizedError,
           skillsCompatibilitySnapshot.officialChannelMaintenanceEnabled == nextMaintenanceEnabled,
           skillsCompatibilitySnapshot.officialChannelMaintenanceIntervalMs == nextMaintenanceIntervalMs,
           skillsCompatibilitySnapshot.officialChannelMaintenanceLastRunAtMs == nextMaintenanceLastRunAtMs,
           skillsCompatibilitySnapshot.officialChannelMaintenanceSourceKind == nextMaintenanceSourceKind,
           skillsCompatibilitySnapshot.officialChannelLastTransitionAtMs == nextLastTransitionAtMs,
           skillsCompatibilitySnapshot.officialChannelLastTransitionKind == nextLastTransitionKind,
           skillsCompatibilitySnapshot.officialChannelLastTransitionSummary == nextLastTransitionSummary {
            return false
        }

        skillsCompatibilitySnapshot.officialChannelID = normalizedChannelID
        skillsCompatibilitySnapshot.officialChannelStatus = normalizedState
        skillsCompatibilitySnapshot.officialChannelUpdatedAtMs = nextUpdatedAtMs
        skillsCompatibilitySnapshot.officialChannelLastSuccessAtMs = nextLastSuccessAtMs
        skillsCompatibilitySnapshot.officialChannelSkillCount = nextSkillCount
        skillsCompatibilitySnapshot.officialChannelErrorCode = normalizedError
        skillsCompatibilitySnapshot.officialChannelMaintenanceEnabled = nextMaintenanceEnabled
        skillsCompatibilitySnapshot.officialChannelMaintenanceIntervalMs = nextMaintenanceIntervalMs
        skillsCompatibilitySnapshot.officialChannelMaintenanceLastRunAtMs = nextMaintenanceLastRunAtMs
        skillsCompatibilitySnapshot.officialChannelMaintenanceSourceKind = nextMaintenanceSourceKind
        skillsCompatibilitySnapshot.officialChannelLastTransitionAtMs = nextLastTransitionAtMs
        skillsCompatibilitySnapshot.officialChannelLastTransitionKind = nextLastTransitionKind
        skillsCompatibilitySnapshot.officialChannelLastTransitionSummary = nextLastTransitionSummary
        return true
    }

    private func overlaySkillsStatusKind(
        base: AXSkillsDoctorSnapshot,
        missingBaselineSkillIDs: [String]
    ) -> AXSkillsCompatibilityStatusKind {
        if !base.hubIndexAvailable {
            return .unavailable
        }
        if base.revokedMatchCount > 0 {
            return .blocked
        }
        if base.partialCompatibilityCount > 0 || !missingBaselineSkillIDs.isEmpty {
            return .partial
        }
        return .supported
    }

    private func overlaySkillsStatusLine(
        base: AXSkillsDoctorSnapshot,
        missingBaselineSkillIDs: [String],
        totalBaselineCount: Int
    ) -> String {
        let readyBaselineCount = max(0, totalBaselineCount - missingBaselineSkillIDs.count)
        let baselineSuffix = totalBaselineCount > 0 ? " b\(readyBaselineCount)/\(totalBaselineCount)" : ""
        let prefix: String
        switch overlaySkillsStatusKind(base: base, missingBaselineSkillIDs: missingBaselineSkillIDs) {
        case .unavailable:
            prefix = "skills?"
        case .blocked:
            prefix = "skills! \(base.compatibleSkillCount)/\(base.installedSkillCount)"
        case .partial:
            prefix = "skills~ \(base.compatibleSkillCount)/\(base.installedSkillCount)"
        case .supported:
            prefix = "skills \(base.compatibleSkillCount)/\(base.installedSkillCount)"
        }
        let line = prefix + baselineSuffix
        return base.localDevPublisherActive ? "\(line) dev" : line
    }

    private func overlaySkillsCompatibilityExplain(
        base: String,
        missingBaselineSkillIDs: [String],
        totalBaselineCount: Int
    ) -> String {
        var lines = base
            .split(separator: "\n")
            .map(String.init)
            .filter { line in
                !line.hasPrefix("baseline=") && !line.hasPrefix("baseline_missing=")
            }
        let readyBaselineCount = max(0, totalBaselineCount - missingBaselineSkillIDs.count)
        lines.append("baseline=\(readyBaselineCount)/\(totalBaselineCount)")
        if !missingBaselineSkillIDs.isEmpty {
            lines.append("baseline_missing=\(missingBaselineSkillIDs.joined(separator: ","))")
        }
        return lines.joined(separator: "\n")
    }

    private func pollHubStatusLoop() async {
        while !Task.isCancelled {
            let activeRemoteGenerate = await HubAIClient.shared.hasActiveRemoteGenerateRequests()
            refreshHubRemotePrefsFromPersistedStateIfNeeded()
            let previousHubConnected = hubConnected

            // If we're not connected, keep trying in the background (lightweight).
            if !hubConnected {
                let res = HubConnector.connect(ttl: 3.0)
                hubConnected = res.ok
                hubBaseDir = res.baseDir
                hubStatus = res.status
                if res.ok { hubLastError = nil }
            } else {
                hubStatus = HubConnector.readHubStatusIfAny(ttl: 3.0)
            }

            handleHubReachabilityEdge(
                previousConnected: previousHubConnected,
                currentConnected: hubConnected
            )

            // If local file-IPC Hub is unavailable, keep remote gRPC link warm.
            // This allows LAN -> Internet route switching after first pairing/bootstrap.
            if !hubConnected {
                let pairedRouteSetSnapshot = currentPairedRouteSetSnapshot()
                let decision = currentHubConnectivityDecision(
                    trigger: .backgroundKeepalive,
                    currentPath: lastHubNetworkPathFingerprint,
                    pairedRouteSetSnapshot: pairedRouteSetSnapshot
                )
                hubConnectivityIncidentSnapshot = currentHubConnectivityIncidentSnapshot(
                    trigger: .backgroundKeepalive,
                    currentPath: lastHubNetworkPathFingerprint,
                    pairedRouteSetSnapshot: pairedRouteSetSnapshot,
                    decision: decision
                )
                if decision.shouldAttemptReconnect {
                    maybeScheduleRemoteReconnect(
                        decisionTrigger: .backgroundKeepalive,
                        decision: decision,
                        incidentSnapshot: hubConnectivityIncidentSnapshot,
                        force: false
                    )
                } else {
                    if let snapshot = hubConnectivityIncidentSnapshot {
                        recordDeferredConnectivityRepairIfNeeded(
                            trigger: .backgroundKeepalive,
                            incidentSnapshot: snapshot
                        )
                        recordHubNetworkHandoffObservation(
                            trigger: .backgroundKeepalive,
                            allowBootstrap: decision.allowBootstrap,
                            decision: decision,
                            incidentSnapshot: snapshot
                        )
                    }
                    let normalizedSummary = decision.summaryLine.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !normalizedSummary.isEmpty,
                       hubRemoteSummary != normalizedSummary {
                        hubRemoteSummary = normalizedSummary
                        refreshUnifiedDoctorReport(force: true)
                    }
                }
            } else {
                hubRemoteConnected = false
                hubRemoteRoute = .none
                hubRemotePaidAccessSnapshot = nil
                hubConnectivityIncidentSnapshot = currentHubConnectivityIncidentSnapshot(
                    trigger: .backgroundKeepalive,
                    currentPath: lastHubNetworkPathFingerprint
                )
            }

            runtimeStatus = await HubAIClient.shared.loadRuntimeStatus()
            if !Self.shouldDeferBackgroundRemoteInventoryRefresh(
                activeRemoteGenerate: activeRemoteGenerate
            ) {
                modelsState = await HubAIClient.shared.loadModelsState()
            }
            if hubConnected || hubRemoteConnected,
               !Self.shouldDeferBackgroundRemoteInventoryRefresh(
                    activeRemoteGenerate: activeRemoteGenerate
               ) {
                await maybeRefreshRemotePresence(force: false)
            }
            if hubRemoteConnected {
                if !Self.shouldDeferBackgroundRemoteInventoryRefresh(
                    activeRemoteGenerate: activeRemoteGenerate
                ) {
                    hubRemotePaidAccessSnapshot = await HubAIClient.shared.currentRemotePaidAccessSnapshot(
                        refreshIfNeeded: false
                    )
                }
            } else {
                if !hubConnected {
                    nextRemotePresenceRefreshAt = .distantPast
                }
                hubRemotePaidAccessSnapshot = nil
            }
            updatePairedSurfaceHeartbeat()
            refreshSkillsCompatibilitySnapshot()

            let bst = HubBridgeClient.status()
            bridgeAlive = bst.alive
            bridgeEnabled = bst.enabled
            if bst.alive && bst.enabled {
                bridgeLastEnsureError = ""
            }
            maybeEnsureBridgeAlwaysOn(currentStatus: bst)
            let now = Date()
            if let ctx = projectContext, now >= nextProjectSnapshotRefreshAt {
                usageSummary = AXProjectStore.usageSummary(for: ctx)
                if let mem = try? AXProjectStore.loadOrCreateMemory(for: ctx) {
                    memory = mem
                    if loadPersistedProjectRegistry {
                        registry = AXProjectRegistryStore.load()
                    }
                }
                if let cfg = try? AXProjectStore.loadOrCreateConfig(for: ctx) {
                    projectConfig = cfg
                }
                // Throttle heavy local disk snapshots to keep text-input responsiveness stable.
                nextProjectSnapshotRefreshAt = now.addingTimeInterval(6.0)
            }
            if projectContext != nil {
                await refreshProjectRemoteRuntimeSurfaceOverride(force: false)
            }
            refreshUnifiedDoctorReport()
            let pollIntervalNs = UInt64(
                (
                    Self.backgroundHubPollInterval(
                        activeRemoteGenerate: activeRemoteGenerate,
                        connected: hubConnected || hubRemoteConnected
                    )
                        * 1_000_000_000.0
                ).rounded()
            )
            try? await Task.sleep(nanoseconds: pollIntervalNs)
        }
    }

    private func resetHubSetupProgress(allowBootstrap: Bool) {
        if allowBootstrap {
            hubFreshPairReconnectSmokeSnapshot = nil
            hubRemoteShadowReconnectSmokeSnapshot = nil
        }
        if allowBootstrap {
            hubSetupDiscoverState = .idle
            hubSetupBootstrapState = .idle
        } else {
            hubSetupDiscoverState = .skipped
            hubSetupBootstrapState = .skipped
        }
        hubSetupConnectState = .idle
        hubSetupFailureCode = ""
    }

    private func applyHubSetupEvent(_ event: HubRemoteProgressEvent) {
        if let summary = Self.hubSetupSummary(for: event) {
            hubRemoteSummary = summary
        }
        if event.state == .failed,
           let detail = event.detail,
           !detail.isEmpty {
            hubSetupFailureCode = detail
        }

        switch event.phase {
        case .discover:
            hubSetupDiscoverState = Self.resolveHubSetupDisplayState(
                current: hubSetupDiscoverState,
                for: event
            )
        case .bootstrap:
            hubSetupBootstrapState = Self.resolveHubSetupDisplayState(
                current: hubSetupBootstrapState,
                for: event
            )
        case .connect:
            hubSetupConnectState = Self.resolveHubSetupDisplayState(
                current: hubSetupConnectState,
                for: event
            )
        }
    }

    nonisolated static func defaultHubRemoteSetupSummary(allowBootstrap: Bool) -> String {
        allowBootstrap ? "discover/bootstrap/connect ..." : "verifying saved hub route ..."
    }

    nonisolated static func hubSetupStepState(for event: HubRemoteProgressEvent) -> HubSetupStepState {
        switch event.state {
        case .started:
            if event.phase == .bootstrap,
               event.detail?.trimmingCharacters(in: .whitespacesAndNewlines) == "awaiting_hub_approval" {
                return .awaitingApproval
            }
            return .running
        case .succeeded:
            return .success
        case .failed:
            return .failed
        case .skipped:
            return .skipped
        }
    }

    nonisolated static func resolveHubSetupDisplayState(
        current: HubSetupStepState,
        for event: HubRemoteProgressEvent
    ) -> HubSetupStepState {
        let mapped = hubSetupStepState(for: event)
        if shouldPreserveCompletedHubSetupStep(
            current: current,
            mapped: mapped,
            event: event
        ) {
            return current
        }
        return mapped
    }

    nonisolated static func shouldPreserveCompletedHubSetupStep(
        current: HubSetupStepState,
        mapped: HubSetupStepState,
        event: HubRemoteProgressEvent
    ) -> Bool {
        guard current == .success else { return false }
        guard mapped == .skipped else { return false }
        let detail = event.detail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return detail == "bootstrap_disabled"
    }

    nonisolated static func hubSetupSummary(for event: HubRemoteProgressEvent) -> String? {
        let detail = event.detail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        switch (event.phase, event.state, detail) {
        case (.discover, .started, _):
            return "searching nearby hub ..."
        case (.bootstrap, .started, "awaiting_hub_approval"):
            return "waiting for Hub local approval ..."
        case (.bootstrap, .started, "refresh"):
            return "refreshing pairing profile ..."
        case (.bootstrap, .started, _):
            return "pairing with hub ..."
        case (.bootstrap, .succeeded, "refresh"):
            return "pairing profile refreshed; reconnecting ..."
        case (.bootstrap, .succeeded, _):
            return "pairing approved; connecting ..."
        case (.connect, .started, _):
            return "connecting hub route ..."
        case (.connect, .succeeded, "lan"):
            return "hub route connected over lan ..."
        case (.connect, .succeeded, "internet"):
            return "hub route connected over internet ..."
        case (.connect, .succeeded, "tunnel"):
            return "hub route connected over internet tunnel ..."
        default:
            return nil
        }
    }

    private func maybeEnsureBridgeAlwaysOn(currentStatus: HubBridgeClient.BridgeStatus) {
        if !bridgeAlwaysOn { return }
        if bridgeEnsureInFlight { return }

        let now = Date()
        if now.timeIntervalSince(bridgeEnsureLastAttemptAt) < 25.0 {
            return
        }

        let remaining = currentStatus.enabledUntil - now.timeIntervalSince1970
        if currentStatus.enabled && remaining > 900 {
            return
        }

        bridgeEnsureInFlight = true
        bridgeEnsureLastAttemptAt = now

        Task { [weak self] in
            let st = await Task.detached(priority: .utility) {
                HubBridgeClient.requestEnable(seconds: 86_400)
            }.value
            guard let self else { return }
            self.bridgeEnsureInFlight = false
            self.bridgeAlive = st.alive
            self.bridgeEnabled = st.enabled
            self.bridgeLastEnsureError = st.requestError.trimmingCharacters(in: .whitespacesAndNewlines)
            if st.alive && st.enabled {
                self.bridgeLastEnsureError = ""
            }
            self.refreshUnifiedDoctorReport(force: true)
        }
    }

    private func autoDetectHubPortsNow() async {
        if hubPortAutoDetectRunning { return }
        hubPortAutoDetectRunning = true
        hubPortAutoDetectMessage = "probing 50052/50053..."
        hubDiscoveredCandidates = []

        let opts = currentHubRemoteConnectOptions(stateDir: nil)
        let preserveManualEndpoint = Self.shouldProtectManualHubEndpointFromAutofill(
            overridePending: hasHubRemoteEndpointOverridePending(),
            currentEndpoint: currentHubRemoteEndpointFingerprint()
        )

        let probe = await HubPairingCoordinator.shared.detectPorts(options: opts)
        hubPortAutoDetectRunning = false
        hubDiscoveredCandidates = probe.candidates

        if probe.ok {
            if !preserveManualEndpoint {
                hubPairingPort = probe.pairingPort
                hubGrpcPort = probe.grpcPort
            }
            let cachedProfile = HubAIClient.cachedRemoteProfile(stateDir: nil)
            let detectedHost = (cachedProfile.host ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let detectedInternetHost = (cachedProfile.internetHost ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let detectedService = (cachedProfile.lanDiscoveryName ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            var details: [String] = []
            if !detectedService.isEmpty {
                details.append("service=\(detectedService)")
            }
            if !detectedHost.isEmpty {
                details.append("hub=\(detectedHost)")
            }
            if !detectedInternetHost.isEmpty {
                details.append("internet=\(detectedInternetHost)")
            }
            details.append("pairing=\(probe.pairingPort)")
            details.append("grpc=\(probe.grpcPort)")
            if detectedInternetHost.isEmpty {
                details.append("remote_host=missing")
            }
            if preserveManualEndpoint {
                details.append("configured endpoint kept")
            } else {
                _ = synchronizeHubRemotePrefsFromCachedProfile(
                    preferDiscoveredInternetHost: true
                )
            }
            hubPortAutoDetectMessage = "detected " + details.joined(separator: " · ")
            hubSetupFailureCode = ""
            refreshUnifiedDoctorReport(force: true)
        } else {
            let reason = probe.reasonCode ?? "port_probe_failed"
            if reason == "bonjour_multiple_hubs_ambiguous" || reason == "lan_multiple_hubs_ambiguous" {
                hubPortAutoDetectMessage = "detect blocked: multiple LAN hubs found; pin one explicitly before auto-connect"
            } else {
                hubPortAutoDetectMessage = "detect failed (\(reason))"
            }
            hubSetupFailureCode = reason
            refreshUnifiedDoctorReport(force: true)
        }

        if !probe.logText.isEmpty {
            hubRemoteLog = probe.logText
        }
    }

    private func applySelectedHubCandidateNow(_ candidate: HubDiscoveredHubCandidateSummary) async {
        let opts = currentHubRemoteConnectOptions(stateDir: nil)

        do {
            try await HubPairingCoordinator.shared.pinDiscoveredHubCandidate(candidate, options: opts)
            hubPairingPort = candidate.pairingPort
            hubGrpcPort = candidate.grpcPort
            if let internetHost = candidate.internetHost?.trimmingCharacters(in: .whitespacesAndNewlines),
               !internetHost.isEmpty {
                hubInternetHost = internetHost
            }
            saveHubRemotePrefsNow(markEndpointOverride: true)
            hubPortAutoDetectMessage = "selected \(candidate.displayName) · hub=\(candidate.host) · pairing=\(candidate.pairingPort) · grpc=\(candidate.grpcPort)"
            hubSetupFailureCode = ""
            hubDiscoveredCandidates = [candidate]
        } catch {
            hubPortAutoDetectMessage = "selection failed (\(error.localizedDescription))"
            hubSetupFailureCode = "hub_candidate_pin_failed"
        }
    }

    private func autoFillHubSetupPathAndPortsNow() async {
        if hubRemoteLinking || hubPortAutoDetectRunning { return }
        if let suggested = await HubPairingCoordinator.shared.suggestedAxhubctlPath() {
            let trimmedCurrent = hubAxhubctlPath.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedCurrent != suggested {
                hubAxhubctlPath = suggested
                saveHubRemotePrefs()
            }
        }
        await autoDetectHubPortsNow()
    }

    private func maybeAutoFillHubSetupPathAndPortsNow(force: Bool) async {
        if hubRemoteLinking || hubPortAutoDetectRunning { return }

        let now = Date()
        if !force, now.timeIntervalSince(hubSetupAutofillLastAttemptAt) < 20.0 {
            return
        }

        let trimmedAxhubctlPath = hubAxhubctlPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedInternetHost = hubInternetHost.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDetectMessage = hubPortAutoDetectMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        if !force,
           !trimmedAxhubctlPath.isEmpty,
           !trimmedInternetHost.isEmpty,
           !trimmedDetectMessage.isEmpty {
            return
        }

        hubSetupAutofillLastAttemptAt = now
        if Self.shouldProtectManualHubEndpointFromAutofill(
            overridePending: hasHubRemoteEndpointOverridePending(),
            currentEndpoint: currentHubRemoteEndpointFingerprint()
        ) {
            if let suggested = await HubPairingCoordinator.shared.suggestedAxhubctlPath() {
                let trimmedCurrent = hubAxhubctlPath.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmedCurrent != suggested {
                    hubAxhubctlPath = suggested
                    saveHubRemotePrefs()
                }
            }
            if hubPortAutoDetectMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                hubPortAutoDetectMessage = "using configured hub endpoint; discovery suggestions stay separate"
            }
            return
        }
        await autoFillHubSetupPathAndPortsNow()
    }

    private func resetPairingAndSetupNow() async {
        if hubRemoteLinking || hubPortAutoDetectRunning { return }

        hubPortAutoDetectMessage = "resetting local pairing state..."
        hubDiscoveredCandidates = []
        let resetPlan = Self.pairingResetPlan(
            overridePending: hasHubRemoteEndpointOverridePending(),
            currentEndpoint: currentHubRemoteEndpointFingerprint()
        )
        let reset = await HubPairingCoordinator.shared.resetLocalPairingState(stateDir: nil)
        hubRemoteLog = reset.logText
        if !reset.ok {
            let reason = reset.reasonCode ?? "reset_failed"
            hubSetupFailureCode = reason
            hubPortAutoDetectMessage = "reset failed (\(reason))"
            showAlert(
                title: "Reset Pairing Failed",
                message: reset.logText.isEmpty ? reason : reset.logText
            )
            refreshUnifiedDoctorReport(force: true)
            return
        }

        hubRemoteConnected = false
        hubRemoteRoute = .none
        hubRemotePaidAccessSnapshot = nil
        hubPairingPort = resetPlan.endpoint.pairingPort
        hubGrpcPort = resetPlan.endpoint.grpcPort
        hubInternetHost = resetPlan.endpoint.internetHost
        setHubRemoteEndpointOverridePending(resetPlan.preserveEndpointOverride)
        saveHubRemotePrefs()
        if resetPlan.shouldAutoDetect {
            hubPortAutoDetectMessage = "pairing state reset; probing ports..."
            await autoDetectHubPortsNow()
        } else {
            hubPortAutoDetectMessage = "pairing state reset; using configured hub endpoint ..."
        }
        _ = await runRemoteConnectFlow(
            allowBootstrap: true,
            showAlertOnFinish: true,
            updateSetupProgress: true,
            repairTrigger: .manualOneClickSetup,
            repairOwner: .user
        )
    }

    func cleanupPairedSurfaceHeartbeat() {
        HubPairedSurfaceHeartbeat.remove(baseDir: pairedSurfaceHeartbeatBaseDir)
        pairedSurfaceHeartbeatBaseDir = nil
    }

    private func updatePairedSurfaceHeartbeat() {
        let nextBaseDir = hubConnected ? (hubBaseDir ?? HubPaths.baseDir()) : nil
        if let previous = pairedSurfaceHeartbeatBaseDir,
           previous.standardizedFileURL != nextBaseDir?.standardizedFileURL {
            HubPairedSurfaceHeartbeat.remove(baseDir: previous)
        }

        guard let baseDir = nextBaseDir else {
            pairedSurfaceHeartbeatBaseDir = nil
            return
        }

        HubPairedSurfaceHeartbeat.write(
            baseDir: baseDir,
            active: pairedSurfaceIsBusy(),
            aiEnabled: hubInteractive,
            modelMemoryBytes: nil
        )
        pairedSurfaceHeartbeatBaseDir = baseDir
    }

    private func pairedSurfaceIsBusy() -> Bool {
        if chatSessions.values.contains(where: { $0.isSending || !$0.pendingToolCalls.isEmpty }) {
            return true
        }
        if terminalSessions.values.contains(where: \.isRunning) {
            return true
        }
        return false
    }
}
