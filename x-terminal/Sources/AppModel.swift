import AppKit
import Foundation

enum HubSetupStepState: String {
    case idle
    case running
    case success
    case failed
    case skipped
}

@MainActor
final class AppModel: ObservableObject {
    @Published var settingsStore: SettingsStore
    @Published var llmRouter: LLMRouter
    @Published var projectRoot: URL? = nil {
        didSet {
            Task { @MainActor in
                await loadSelectedProject()
            }
        }
    }

    @Published var registry: AXProjectRegistry = .empty()
    @Published var selectedProjectId: String? = nil {
        didSet {
            Task { @MainActor in
                await applySelection()
            }
        }
    }

    @Published var projectContext: AXProjectContext? = nil
    @Published var memory: AXMemory? = nil
    @Published var usageSummary: AXUsageSummary = .empty()
    @Published var projectConfig: AXProjectConfig? = nil
    @Published var projectRemoteAutonomyOverride: AXProjectAutonomyRemoteOverrideSnapshot? = nil
    @Published var skillsCompatibilitySnapshot: AXSkillsDoctorSnapshot = .empty
    @Published var unifiedDoctorReport: XTUnifiedDoctorReport = .empty
    @Published var lastImportedAgentSkillDirectory: URL? = nil
    @Published var lastImportedAgentSkillName: String = ""
    @Published var lastImportedAgentSkillStage: HubIPCClient.AgentImportStageResult? = nil
    @Published var lastImportedAgentSkillStatusLine: String = ""
    @Published var agentSkillImportBusy: Bool = false
    @Published var baselineInstallBusy: Bool = false
    @Published var baselineInstallStatusLine: String = ""

    @Published var runtimeStatus: AIRuntimeStatus? = nil
    @Published var modelsState: ModelStateSnapshot = .empty()

    @Published var hubConnected: Bool = false
    @Published var hubBaseDir: URL? = nil
    @Published var hubStatus: HubStatus? = nil
    @Published var hubLastError: String? = nil
    @Published var hubRemoteConnected: Bool = false
    @Published var hubRemoteRoute: HubRemoteRoute = .none
    @Published var hubRemoteLog: String = ""
    @Published var hubRemoteLinking: Bool = false
    @Published var hubRemoteSummary: String = ""
    @Published var hubSetupDiscoverState: HubSetupStepState = .idle
    @Published var hubSetupBootstrapState: HubSetupStepState = .idle
    @Published var hubSetupConnectState: HubSetupStepState = .idle
    @Published var hubSetupFailureCode: String = ""
    @Published var hubPortAutoDetectRunning: Bool = false
    @Published var hubPortAutoDetectMessage: String = ""
    @Published var hubPairingPort: Int = 50052
    @Published var hubGrpcPort: Int = 50051
    @Published var hubInternetHost: String = ""
    @Published var hubAxhubctlPath: String = ""

    var hubInteractive: Bool {
        hubConnected || hubRemoteConnected
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

    @Published var memoryCoarseRunning: Bool = false
    @Published var memoryRefineRunning: Bool = false

    @Published var bridgeEnabled: Bool = false
    @Published var bridgeAlive: Bool = false

    @Published var serverRunning: Bool = false
    @Published var localServerEnabled: Bool = false
    @Published var localServerPort: Int = 8080
    @Published var localServerLastError: String = ""

    private var chatSessions: [String: ChatSessionModel] = [:]
    private var terminalSessions: [String: TerminalSessionModel] = [:]

    @Published var paneByProjectId: [String: AXProjectPane] = [:]

    private var notifTokens: [NSObjectProtocol] = []
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
    private let hubAxhubctlPathKey = "xterminal_hub_axhubctl_path"
    private let legacyHubAxhubctlPathKey = "xterminal_hub_axhubctl_path"
    private let bridgeAlwaysOnKey = "xterminal_bridge_always_on"
    private let legacyBridgeAlwaysOnKey = "xterminal_bridge_always_on"
    private let localServerEnabledKey = "xterminal_local_server_enabled"
    private let legacyLocalServerEnabledKey = "xterminal_local_server_enabled"

    private let sessionManager = AXSessionManager.shared
    private let serverManager = AXServerManager.shared
    private let eventBus = AXEventBus.shared
    private var hubReconnectLastAttemptAt: Date = .distantPast
    private var bridgeAlwaysOn: Bool = true
    private var bridgeEnsureInFlight: Bool = false
    private var bridgeEnsureLastAttemptAt: Date = .distantPast
    private var nextProjectSnapshotRefreshAt: Date = .distantPast
    private var nextProjectAutonomyOverrideRefreshAt: Date = .distantPast
    private var nextSkillsCompatibilityRefreshAt: Date = .distantPast
    private var nextUnifiedDoctorRefreshAt: Date = .distantPast
    private var remoteSkillsCompatibilityOverlayInFlight: Bool = false

    init() {
        let ss = SettingsStore()
        settingsStore = ss
        llmRouter = LLMRouter(settingsStore: ss)

        // Memory pipeline status (coarse/refine) for toolbar indicators.
        let nc = NotificationCenter.default
        notifTokens.append(
            nc.addObserver(forName: AXMemoryPipelineNotifications.coarseStart, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.memoryCoarseRunning = true }
            }
        )
        notifTokens.append(
            nc.addObserver(forName: AXMemoryPipelineNotifications.coarseEnd, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.memoryCoarseRunning = false }
            }
        )
        notifTokens.append(
            nc.addObserver(forName: AXMemoryPipelineNotifications.refineStart, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.memoryRefineRunning = true }
            }
        )
        notifTokens.append(
            nc.addObserver(forName: AXMemoryPipelineNotifications.refineEnd, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.memoryRefineRunning = false }
            }
        )

        loadRegistry()
        bootstrapSelection()
        migrateSkillsIfNeeded()
        scheduleSkillScan()
        loadHubRemotePrefs()
        refreshSkillsCompatibilitySnapshot(force: true)
        refreshUnifiedDoctorReport(force: true)
        loadBridgePrefs()
        loadLocalServerPrefs()

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

    deinit {
        for t in notifTokens {
            NotificationCenter.default.removeObserver(t)
        }
        skillScanTimer?.invalidate()
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
            hubRemoteSummary = ""
            refreshSkillsCompatibilitySnapshot(force: true)
            refreshUnifiedDoctorReport(force: true)
            return
        }

        refreshSkillsCompatibilitySnapshot(force: true)
        refreshUnifiedDoctorReport(force: true)
        if auto {
            maybeScheduleRemoteReconnect(allowBootstrap: false, force: false)
        } else {
            await runRemoteConnectFlow(allowBootstrap: true, showAlertOnFinish: true)
        }
    }

    func startHubOneClickSetup() {
        Task { @MainActor in
            await runRemoteConnectFlow(allowBootstrap: true, showAlertOnFinish: true)
        }
    }

    func startHubReconnectOnly() {
        Task { @MainActor in
            await runRemoteConnectFlow(allowBootstrap: false, showAlertOnFinish: true)
        }
    }

    func saveHubRemotePrefsNow() {
        saveHubRemotePrefs()
        refreshUnifiedDoctorReport(force: true)
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

        if panel.runModal() == .OK {
            if let url = panel.url {
                addProject(url)
            }
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

        if panel.runModal() == .OK, let url = panel.url {
            rememberSkillsDirectory(for: url)
            if url.hasDirectoryPath {
                let skillMD = url.appendingPathComponent("SKILL.md")
                if FileManager.default.fileExists(atPath: skillMD.path) {
                    NSWorkspace.shared.open(skillMD)
                } else {
                    NSWorkspace.shared.open(url)
                }
            } else {
                NSWorkspace.shared.open(url)
            }
        }
    }

    func openCurrentSkillsIndex() {
        let selectedProject = selectedProjectId == AXProjectRegistry.globalHomeId ? nil : selectedProjectId
        let projectName = selectedProject.flatMap { registry.project(for: $0)?.displayName }
        guard let skillsDir = AXSkillsLibrary.resolveSkillsDirectory() else {
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
        NSWorkspace.shared.open(targetURL)
    }

    func importSkills() {
        let panel = NSOpenPanel()
        panel.title = "Import Skill(s)"
        panel.prompt = "Import"
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        if let base = ensureSkillsDirectory() {
            panel.directoryURL = base
        }

        if panel.runModal() == .OK {
            guard let base = ensureSkillsDirectory() else { return }
            rememberSkillsDirectory(for: base)
            let selectedURLs = panel.urls
            Task { @MainActor in
                var imported = 0
                var skipped = 0
                var stageSummaries: [String] = []
                for url in selectedURLs {
                    let result = await importSkill(from: url, to: base)
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
                    showAlert(
                        title: "Import Skills",
                        message: lines.joined(separator: "\n")
                    )
                }
                refreshSkillsCompatibilitySnapshot(force: true)
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
        AXProjectRegistryStore.save(reg)
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
            title: ctx.projectName(),
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

    func sessionForProjectId(_ projectId: String) -> ChatSessionModel? {
        guard let ctx = projectContext(for: projectId) else { return nil }
        return session(for: ctx)
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
        let reasonText = (reason ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        var message = "请先处理 Hub 授权请求（grant_request_id=\(grantId)"
        if !capabilityToken.isEmpty {
            message += "，capability=\(capabilityToken)"
        }
        message += "），确认后继续推进当前项目。"
        if !reasonText.isEmpty {
            message += "\n授权原因：\(reasonText)"
        }

        let currentDraft = s.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if currentDraft.isEmpty {
            s.draft = message
        } else if !currentDraft.contains(grantId) {
            s.draft = message + "\n\n" + currentDraft
        }

        setPane(.chat, for: projectId)
        selectProject(projectId)
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
        try? out.data(using: .utf8)?.write(to: indexURL, options: .atomic)
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
        try? out.data(using: .utf8)?.write(to: indexURL, options: .atomic)
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
        try? out.data(using: .utf8)?.write(to: indexURL, options: .atomic)
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
        try? data.write(to: url, options: .atomic)
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

    private func rememberSkillsDirectory(for url: URL) {
        let dir: URL
        if url.hasDirectoryPath {
            dir = url
        } else {
            dir = url.deletingLastPathComponent()
        }
        UserDefaults.standard.set(dir.path, forKey: skillsDirDefaultsKey)
    }

    private struct SkillImportOperationResult {
        var imported: Bool
        var stageSummary: String?
    }

    private struct AgentSkillStageOutcome {
        var summary: String
        var stageResult: HubIPCClient.AgentImportStageResult?
        var importReport: XTAgentSkillImportPreflightReport
    }

    @discardableResult
    private func importSkill(from url: URL, to base: URL) async -> SkillImportOperationResult {
        var source = url
        if !url.hasDirectoryPath {
            let lower = url.lastPathComponent.lowercased()
            if lower == "skill.md" {
                source = url.deletingLastPathComponent()
            } else if ["zip", "skill"].contains(url.pathExtension.lowercased()) {
                showAlert(
                    title: "Import Skills",
                    message: "Please unzip the skill package first, then select the skill folder."
                )
                return SkillImportOperationResult(imported: false, stageSummary: nil)
            } else {
                showAlert(
                    title: "Import Skills",
                    message: "Please select a skill folder or SKILL.md."
                )
                return SkillImportOperationResult(imported: false, stageSummary: nil)
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
            let stageOutcome = await stageImportedSkill(skillDirectory: dest, repoRoot: base)
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

    func reviewLastImportedSkill() {
        Task { @MainActor in
            await reviewLastImportedSkillNow()
        }
    }

    func enableLastImportedSkill() {
        Task { @MainActor in
            await enableLastImportedSkillNow()
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
        let targetProjectId = scope.projectId
        let targetLabel = scope.displayLabel
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
            resolvedSkills: initialResolved.skills,
            searchResultsBySkillID: searchResultsBySkillID
        )
        let baselineIDs = Set(baseline.map(\.skillID))

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
            refreshResolvedSkillsCacheForCurrentSelection()
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
                lines.append("- \(item.skillID): \(item.installHint)")
            }
        } else if plan.installableCandidates.isEmpty && pinSuccesses.isEmpty {
            lines.append("No pin work was needed. The default Agent baseline was already resolved for this target.")
        }

        if finalResolved.ok == false {
            lines.append("Final resolved refresh failed: \(finalResolved.reasonCode ?? "unknown")")
        }

        showAlert(title: "Install Default Agent Baseline", message: lines.joined(separator: "\n"))
    }

    private func refreshResolvedSkillsCacheForCurrentSelection() {
        guard let selectedProjectId,
              selectedProjectId != AXProjectRegistry.globalHomeId,
              let ctx = projectContext else { return }
        let projectName = registry.project(for: selectedProjectId)?.displayName
        _ = XTResolvedSkillsCacheStore.refreshFromHub(
            projectId: selectedProjectId,
            projectName: projectName,
            context: ctx,
            hubBaseDir: hubBaseDir ?? HubPaths.baseDir()
        )
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
        let stageOutcome = await stageImportedSkill(skillDirectory: skillDirectory, repoRoot: repoRoot)
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
        refreshSkillsCompatibilitySnapshot(force: true)
        refreshUnifiedDoctorReport(force: true)

        lines.append("Enabled: \(enabledSkillId)")
        lines.append("Scope: \(nonEmptyString(promote.scope) ?? "unknown")")
        if let previous = nonEmptyString(promote.previousPackageSHA256) {
            lines.append("Previous package: \(shortSHA(previous))")
        }
        showAlert(title: "Enable Imported Skill", message: lines.joined(separator: "\n"))
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

    private func confirmReplaceSkill(name: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Skill already exists"
        alert.informativeText = "Replace \"\(name)\"?"
        alert.addButton(withTitle: "Replace")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }

    func setProjectRoleModel(role: AXRole, modelId: String?) {
        guard let ctx = projectContext else { return }
        guard var cfg = projectConfig else { return }
        cfg = cfg.settingModelOverride(role: role, modelId: modelId)
        projectConfig = cfg
        try? AXProjectStore.saveConfig(cfg, for: ctx)
    }

    func setProjectTrustedAutomationBinding(
        mode: AXProjectAutomationMode,
        deviceId: String,
        deviceToolGroups: [String]? = nil,
        workspaceBindingHash: String? = nil
    ) {
        guard let ctx = projectContext else { return }
        guard var cfg = projectConfig else { return }
        let resolvedHash = workspaceBindingHash ?? xtTrustedAutomationWorkspaceHash(forProjectRoot: ctx.root)
        cfg = cfg.settingTrustedAutomationBinding(
            mode: mode,
            deviceId: deviceId,
            deviceToolGroups: deviceToolGroups,
            workspaceBindingHash: resolvedHash
        )
        projectConfig = cfg
        try? AXProjectStore.saveConfig(cfg, for: ctx)
    }

    func setProjectHubMemoryPreference(enabled: Bool) {
        guard let ctx = projectContext else { return }
        guard var cfg = projectConfig else { return }
        cfg = cfg.settingHubMemoryPreference(enabled: enabled)
        projectConfig = cfg
        try? AXProjectStore.saveConfig(cfg, for: ctx)
    }

    func setProjectGovernedReadableRoots(paths: [String]) {
        guard let ctx = projectContext else { return }
        guard var cfg = projectConfig else { return }
        cfg = cfg.settingGovernedReadableRoots(paths: paths, projectRoot: ctx.root)
        projectConfig = cfg
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
        guard var cfg = projectConfig else { return }
        cfg = cfg.settingGovernedAutoApproveLocalToolCalls(enabled: enabled)
        projectConfig = cfg
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

    func setProjectAutomationSelfIteration(
        enabled: Bool? = nil,
        maxAutoRetryDepth: Int? = nil
    ) {
        guard let ctx = projectContext else { return }
        guard var cfg = projectConfig else { return }
        cfg = cfg.settingAutomationSelfIteration(
            enabled: enabled,
            maxAutoRetryDepth: maxAutoRetryDepth
        )
        projectConfig = cfg
        try? AXProjectStore.saveConfig(cfg, for: ctx)
    }

    func setProjectAutonomyPolicy(
        mode: AXProjectAutonomyMode? = nil,
        allowDeviceTools: Bool? = nil,
        allowBrowserRuntime: Bool? = nil,
        allowConnectorActions: Bool? = nil,
        allowExtensions: Bool? = nil,
        ttlSeconds: Int? = nil,
        hubOverrideMode: AXProjectAutonomyHubOverrideMode? = nil
    ) {
        guard let ctx = projectContext else { return }
        guard var cfg = projectConfig else { return }

        let now = Date()
        let previous = cfg.effectiveAutonomyPolicy(
            now: now,
            remoteOverride: projectRemoteAutonomyOverride
        )
        cfg = cfg.settingAutonomyPolicy(
            mode: mode,
            allowDeviceTools: allowDeviceTools,
            allowBrowserRuntime: allowBrowserRuntime,
            allowConnectorActions: allowConnectorActions,
            allowExtensions: allowExtensions,
            ttlSeconds: ttlSeconds,
            hubOverrideMode: hubOverrideMode,
            updatedAt: now
        )
        let effective = cfg.effectiveAutonomyPolicy(
            now: now,
            remoteOverride: projectRemoteAutonomyOverride
        )

        projectConfig = cfg
        try? AXProjectStore.saveConfig(cfg, for: ctx)
        AXProjectStore.appendRawLog(
            [
                "type": "project_autonomy_policy",
                "action": "update",
                "created_at": now.timeIntervalSince1970,
                "project_id": AXProjectRegistryStore.projectId(forRoot: ctx.root),
                "mode": cfg.autonomyMode.rawValue,
                "effective_mode": effective.effectiveMode.rawValue,
                "previous_effective_mode": previous.effectiveMode.rawValue,
                "allow_device_tools": cfg.autonomyAllowDeviceTools,
                "allow_browser_runtime": cfg.autonomyAllowBrowserRuntime,
                "allow_connector_actions": cfg.autonomyAllowConnectorActions,
                "allow_extensions": cfg.autonomyAllowExtensions,
                "ttl_sec": cfg.autonomyTTLSeconds,
                "remaining_sec": effective.remainingSeconds,
                "hub_override_mode": cfg.autonomyHubOverrideMode.rawValue,
                "effective_hub_override_mode": effective.hubOverrideMode.rawValue,
                "remote_override_mode": effective.remoteOverrideMode.rawValue,
                "remote_override_source": effective.remoteOverrideSource,
                "audit_ref": "audit-xt-autonomy-policy-\(Int(now.timeIntervalSince1970))"
            ],
            for: ctx
        )
    }

    func resolvedProjectAutonomyPolicy(
        config: AXProjectConfig? = nil,
        now: Date = Date()
    ) -> AXProjectAutonomyEffectivePolicy {
        let resolvedConfig = config ?? projectConfig ?? .default(forProjectRoot: projectContext?.root ?? URL(fileURLWithPath: "/"))
        return resolvedConfig.effectiveAutonomyPolicy(
            now: now,
            remoteOverride: projectRemoteAutonomyOverride
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
        guard var cfg = projectConfig else { return }

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
            cfg = cfg.settingAutonomyPolicy(
                mode: executionTier.defaultSurfacePreset,
                updatedAt: Date()
            )
        }
        let resolved = xtResolveProjectGovernance(
            projectRoot: ctx.root,
            config: cfg,
            remoteOverride: projectRemoteAutonomyOverride
        )

        projectConfig = cfg
        try? AXProjectStore.saveConfig(cfg, for: ctx)
        AXProjectStore.appendRawLog(
            [
                "type": "project_governance_bundle",
                "action": "update",
                "created_at": Date().timeIntervalSince1970,
                "project_id": AXProjectRegistryStore.projectId(forRoot: ctx.root),
                "execution_tier": cfg.executionTier.rawValue,
                "supervisor_intervention_tier": cfg.supervisorInterventionTier.rawValue,
                "review_policy_mode": cfg.reviewPolicyMode.rawValue,
                "progress_heartbeat_sec": cfg.progressHeartbeatSeconds,
                "review_pulse_sec": cfg.reviewPulseSeconds,
                "brainstorm_review_sec": cfg.brainstormReviewSeconds,
                "event_driven_review_enabled": cfg.eventDrivenReviewEnabled,
                "event_review_triggers": cfg.eventReviewTriggers.map(\.rawValue),
                "compat_source": cfg.governanceCompatSource.rawValue,
                "surface_preset": cfg.autonomyMode.rawValue,
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
        return xtResolveProjectGovernance(
            projectRoot: root,
            config: resolvedConfig,
            legacyAutonomyLevel: legacyAutonomyLevel,
            remoteOverride: projectRemoteAutonomyOverride
        )
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

    private func refreshProjectRemoteAutonomyOverride(force: Bool) async {
        guard let ctx = projectContext else {
            projectRemoteAutonomyOverride = nil
            nextProjectAutonomyOverrideRefreshAt = .distantPast
            return
        }

        let now = Date()
        if !force, now < nextProjectAutonomyOverrideRefreshAt {
            return
        }

        let projectId = AXProjectRegistryStore.projectId(forRoot: ctx.root)
        let remoteOverride = await HubIPCClient.requestProjectAutonomyPolicyOverride(
            projectId: projectId,
            bypassCache: force
        )
        guard projectContext?.root.standardizedFileURL == ctx.root.standardizedFileURL else {
            return
        }
        projectRemoteAutonomyOverride = remoteOverride
        nextProjectAutonomyOverrideRefreshAt = now.addingTimeInterval(force ? 1.0 : 2.0)
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
        AXProjectRegistryStore.save(reg)
    }

    func reloadMemory() {
        Task { @MainActor in
            await loadSelectedProject()
        }
    }

    private func loadSelectedProject() async {
        guard let root = projectRoot else {
            projectContext = nil
            memory = nil
            usageSummary = .empty()
            projectConfig = nil
            projectRemoteAutonomyOverride = nil
            nextProjectSnapshotRefreshAt = .distantPast
            nextProjectAutonomyOverrideRefreshAt = .distantPast
            refreshSkillsCompatibilitySnapshot(force: true)
            return
        }
        let ctx = AXProjectContext(root: root)
        projectContext = ctx
        nextProjectSnapshotRefreshAt = .distantPast
        nextProjectAutonomyOverrideRefreshAt = .distantPast
        do {
            memory = try AXProjectStore.loadOrCreateMemory(for: ctx)
            usageSummary = AXProjectStore.usageSummary(for: ctx)
            projectConfig = try AXProjectStore.loadOrCreateConfig(for: ctx)
        } catch {
            memory = nil
            usageSummary = .empty()
            projectConfig = nil
        }
        await refreshProjectRemoteAutonomyOverride(force: true)
        refreshSkillsCompatibilitySnapshot(force: true)
    }

    var sortedProjects: [AXProjectEntry] {
        registry.sortedProjects()
    }

    private func loadRegistry() {
        registry = AXProjectRegistryStore.load()
    }

    private func bootstrapSelection() {
        if let last = registry.lastSelectedProjectId,
           let entry = registry.project(for: last),
           resolvedProjectRootURL(for: entry) != nil {
            selectedProjectId = last
            return
        }
        if registry.globalHomeVisible {
            selectedProjectId = AXProjectRegistry.globalHomeId
            return
        }
        if let newest = registry.sortedProjects().last(where: { resolvedProjectRootURL(for: $0) != nil }) {
            selectedProjectId = newest.projectId
        }
    }

    private func applySelection() async {
        guard let pid = selectedProjectId else {
            projectRoot = nil
            return
        }
        if pid == AXProjectRegistry.globalHomeId {
            projectRoot = nil
            return
        }
        guard let entry = registry.project(for: pid) else {
            projectRoot = nil
            return
        }

        var reg = registry
        reg = AXProjectRegistryStore.touchOpened(reg, projectId: pid)
        reg.lastSelectedProjectId = pid
        registry = reg
        AXProjectRegistryStore.save(reg)

        guard let resolvedRoot = resolvedProjectRootURL(for: entry) else {
            if reg.globalHomeVisible {
                selectedProjectId = AXProjectRegistry.globalHomeId
            } else {
                selectedProjectId = nil
            }
            return
        }

        projectRoot = resolvedRoot
    }

    private func addProject(_ url: URL) {
        var reg = registry
        let normalizedRoot = AXProjectRegistryStore.normalizedRootPath(url)
        let previous = reg.projects.first(where: { $0.rootPath == normalizedRoot })
        let res = AXProjectRegistryStore.upsertProject(reg, root: url)
        reg = res.0
        reg.lastSelectedProjectId = res.1.projectId
        registry = reg
        AXProjectRegistryStore.save(reg)
        if previous == nil {
            eventBus.publish(.projectCreated(res.1))
        } else {
            eventBus.publish(.projectUpdated(res.1))
        }
        selectedProjectId = res.1.projectId
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

    private func loadHubRemotePrefs() {
        let d = UserDefaults.standard
        let p = d.object(forKey: hubPairingPortKey) as? Int
            ?? d.object(forKey: legacyHubPairingPortKey) as? Int
            ?? 50052
        let g = d.object(forKey: hubGrpcPortKey) as? Int
            ?? d.object(forKey: legacyHubGrpcPortKey) as? Int
            ?? 50051
        let host = d.string(forKey: hubInternetHostKey)
            ?? d.string(forKey: legacyHubInternetHostKey)
            ?? ""
        let ctl = d.string(forKey: hubAxhubctlPathKey)
            ?? d.string(forKey: legacyHubAxhubctlPathKey)
            ?? ""

        hubPairingPort = max(1, min(65_535, p))
        hubGrpcPort = max(1, min(65_535, g))
        hubInternetHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
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
        d.set(hubAxhubctlPath, forKey: hubAxhubctlPathKey)
        d.set(hubAxhubctlPath, forKey: legacyHubAxhubctlPathKey)
    }

    private func loadBridgePrefs() {
        let d = UserDefaults.standard
        // P0 policy: keep Network Bridge always-on by default.
        bridgeAlwaysOn = true
        d.set(true, forKey: bridgeAlwaysOnKey)
        d.set(true, forKey: legacyBridgeAlwaysOnKey)
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

    private func maybeScheduleRemoteReconnect(allowBootstrap: Bool, force: Bool) {
        if hubRemoteLinking { return }
        if !force {
            let now = Date()
            if now.timeIntervalSince(hubReconnectLastAttemptAt) < 20.0 {
                return
            }
        }
        Task { @MainActor in
            // Only run background reconnect after a paired profile exists.
            let hasEnv = await HubPairingCoordinator.shared.hasHubEnv(stateDir: nil)
            if !hasEnv { return }
            await runRemoteConnectFlow(
                allowBootstrap: allowBootstrap,
                showAlertOnFinish: false,
                updateSetupProgress: false
            )
        }
    }

    private func runRemoteConnectFlow(
        allowBootstrap: Bool,
        showAlertOnFinish: Bool,
        updateSetupProgress: Bool = true
    ) async {
        if hubRemoteLinking { return }
        hubRemoteLinking = true
        hubReconnectLastAttemptAt = Date()
        if updateSetupProgress {
            hubRemoteSummary = allowBootstrap ? "discover/bootstrap/connect ..." : "connect ..."
            hubRemoteLog = ""
            resetHubSetupProgress(allowBootstrap: allowBootstrap)
        }
        saveHubRemotePrefs()

        let opts = HubRemoteConnectOptions(
            grpcPort: hubGrpcPort,
            pairingPort: hubPairingPort,
            deviceName: Host.current().localizedName ?? "X-Terminal",
            internetHost: hubInternetHost,
            axhubctlPath: hubAxhubctlPath,
            stateDir: nil
        )

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

        let report = await HubPairingCoordinator.shared.ensureConnected(
            options: opts,
            allowBootstrap: allowBootstrap,
            onProgress: progressHandler
        )

        hubRemoteLinking = false
        hubRemoteLog = report.logText
        hubRemoteConnected = report.ok
        hubRemoteRoute = report.route
        hubRemoteSummary = report.summary
        if updateSetupProgress {
            hubSetupFailureCode = report.ok ? "" : (report.reasonCode ?? report.summary)
        }

        if report.ok {
            hubLastError = nil
            if showAlertOnFinish {
                showAlert(
                    title: "Hub Link Ready",
                    message: "Route: \(report.route.rawValue)\n\n\(report.summary)"
                )
            }
        } else {
            if !hubConnected {
                hubLastError = "hub_remote_connect_failed (\(report.summary))"
            }
            if showAlertOnFinish {
                showAlert(
                    title: "Hub Link Failed",
                    message: report.logText.isEmpty ? report.summary : report.logText
                )
            }
        }
        refreshUnifiedDoctorReport(force: true)
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
        return sessionManager.sessions.sorted { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhs.id < rhs.id
        }.first
    }

    private func refreshUnifiedDoctorReport(force: Bool = false) {
        let now = Date()
        if !force, now < nextUnifiedDoctorRefreshAt {
            return
        }

        let session = currentDoctorSession()
        let reportURL = XTUnifiedDoctorStore.defaultReportURL()
        let supervisor = SupervisorManager.shared
        let input = XTUnifiedDoctorInput(
            generatedAt: now,
            localConnected: hubConnected,
            remoteConnected: hubRemoteConnected,
            remoteRoute: hubRemoteRoute,
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
            sessionID: session?.id,
            sessionTitle: session?.title,
            sessionRuntime: session?.runtime,
            voiceRouteDecision: supervisor.voiceRouteDecision,
            voiceRuntimeState: supervisor.voiceRuntimeState,
            voiceAuthorizationStatus: supervisor.voiceAuthorizationStatus,
            voiceActiveHealthReasonCode: supervisor.voiceActiveHealthReasonCode,
            voiceSidecarHealth: supervisor.voiceFunASRSidecarHealth,
            wakeProfileSnapshot: supervisor.voiceWakeProfileSnapshot,
            conversationSession: supervisor.conversationSessionSnapshot,
            skillsSnapshot: skillsCompatibilitySnapshot,
            reportPath: reportURL.path
        )
        let report = XTUnifiedDoctorBuilder.build(input: input)
        XTUnifiedDoctorStore.writeReport(report, to: reportURL)
        unifiedDoctorReport = report
        nextUnifiedDoctorRefreshAt = now.addingTimeInterval(2.0)
    }

    private func capturedRuntimeSnapshot() -> UIFailClosedRuntimeSnapshot {
        guard let orchestrator = supervisor.orchestrator else {
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
        skillsCompatibilitySnapshot = AXSkillsLibrary.compatibilityDoctorSnapshot(
            projectId: selectedProject,
            projectName: projectName,
            skillsDir: skillsDir,
            hubBaseDir: hubBaseDir
        )
        nextSkillsCompatibilityRefreshAt = now.addingTimeInterval(5.0)
        refreshUnifiedDoctorReport(force: force)
        refreshRemoteSkillsCompatibilityOverlayIfNeeded(projectId: selectedProject)
    }

    private func refreshRemoteSkillsCompatibilityOverlayIfNeeded(projectId: String?) {
        guard hubInteractive else { return }
        guard !remoteSkillsCompatibilityOverlayInFlight else { return }

        let baseline = skillsCompatibilitySnapshot.baselineRecommendedSkills.isEmpty
            ? AXSkillsLibrary.defaultAgentBaselineSkills
            : skillsCompatibilitySnapshot.baselineRecommendedSkills
        guard !baseline.isEmpty else { return }

        remoteSkillsCompatibilityOverlayInFlight = true
        Task { @MainActor in
            defer { remoteSkillsCompatibilityOverlayInFlight = false }
            let resolved = await HubIPCClient.listResolvedSkills(projectId: projectId)
            guard resolved.ok else { return }

            let currentDisplayedProjectId = selectedProjectId == AXProjectRegistry.globalHomeId ? nil : selectedProjectId
            guard currentDisplayedProjectId == projectId else { return }

            let resolvedIDs = Set(
                resolved.skills.map { $0.skill.skillID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            )
            let missingBaselineSkillIDs = baseline
                .map(\.skillID)
                .filter { !resolvedIDs.contains($0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) }

            guard missingBaselineSkillIDs != skillsCompatibilitySnapshot.missingBaselineSkillIDs else { return }

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

            // If local file-IPC Hub is unavailable, keep remote gRPC link warm.
            // This allows LAN -> Internet route switching after first pairing/bootstrap.
            if !hubConnected {
                maybeScheduleRemoteReconnect(allowBootstrap: false, force: false)
            } else {
                hubRemoteConnected = false
                hubRemoteRoute = .none
            }

            runtimeStatus = await HubAIClient.shared.loadRuntimeStatus()
            modelsState = await HubAIClient.shared.loadModelsState()
            refreshSkillsCompatibilitySnapshot()

            let bst = HubBridgeClient.status()
            bridgeAlive = bst.alive
            bridgeEnabled = bst.enabled
            maybeEnsureBridgeAlwaysOn(currentStatus: bst)
            let now = Date()
            if let ctx = projectContext, now >= nextProjectSnapshotRefreshAt {
                usageSummary = AXProjectStore.usageSummary(for: ctx)
                if let mem = try? AXProjectStore.loadOrCreateMemory(for: ctx) {
                    memory = mem
                    registry = AXProjectRegistryStore.load()
                }
                if let cfg = try? AXProjectStore.loadOrCreateConfig(for: ctx) {
                    projectConfig = cfg
                }
                // Throttle heavy local disk snapshots to keep text-input responsiveness stable.
                nextProjectSnapshotRefreshAt = now.addingTimeInterval(3.0)
            }
            if projectContext != nil {
                await refreshProjectRemoteAutonomyOverride(force: false)
            }
            refreshUnifiedDoctorReport()
            try? await Task.sleep(nanoseconds: 800_000_000)
        }
    }

    private func resetHubSetupProgress(allowBootstrap: Bool) {
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
        let mapped: HubSetupStepState
        switch event.state {
        case .started:
            mapped = .running
        case .succeeded:
            mapped = .success
        case .failed:
            mapped = .failed
            if let detail = event.detail, !detail.isEmpty {
                hubSetupFailureCode = detail
            }
        case .skipped:
            mapped = .skipped
        }

        switch event.phase {
        case .discover:
            hubSetupDiscoverState = mapped
        case .bootstrap:
            hubSetupBootstrapState = mapped
        case .connect:
            hubSetupConnectState = mapped
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
            self.refreshUnifiedDoctorReport(force: true)
        }
    }

    private func autoDetectHubPortsNow() async {
        if hubPortAutoDetectRunning { return }
        hubPortAutoDetectRunning = true
        hubPortAutoDetectMessage = "probing 50052/50053..."

        let opts = HubRemoteConnectOptions(
            grpcPort: hubGrpcPort,
            pairingPort: hubPairingPort,
            deviceName: Host.current().localizedName ?? "X-Terminal",
            internetHost: hubInternetHost,
            axhubctlPath: hubAxhubctlPath,
            stateDir: nil
        )

        let probe = await HubPairingCoordinator.shared.detectPorts(options: opts)
        hubPortAutoDetectRunning = false

        if probe.ok {
            hubPairingPort = probe.pairingPort
            hubGrpcPort = probe.grpcPort
            saveHubRemotePrefs()
            hubPortAutoDetectMessage = "detected pairing=\(probe.pairingPort), grpc=\(probe.grpcPort)"
            hubSetupFailureCode = ""
            refreshUnifiedDoctorReport(force: true)
        } else {
            let reason = probe.reasonCode ?? "port_probe_failed"
            hubPortAutoDetectMessage = "detect failed (\(reason))"
            hubSetupFailureCode = reason
            refreshUnifiedDoctorReport(force: true)
        }

        if !probe.logText.isEmpty {
            hubRemoteLog = probe.logText
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

    private func resetPairingAndSetupNow() async {
        if hubRemoteLinking || hubPortAutoDetectRunning { return }

        hubPortAutoDetectMessage = "resetting local pairing state..."
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
        hubPairingPort = 50052
        hubGrpcPort = 50051
        saveHubRemotePrefs()
        hubPortAutoDetectMessage = "pairing state reset; probing ports..."
        await autoDetectHubPortsNow()
        await runRemoteConnectFlow(allowBootstrap: true, showAlertOnFinish: true, updateSetupProgress: true)
    }
}
