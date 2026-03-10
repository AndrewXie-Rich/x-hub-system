import Foundation
import Combine
import UniformTypeIdentifiers
import AppKit

@MainActor
final class SupervisorManager: ObservableObject {
    static let shared = SupervisorManager()

    @Published var messages: [SupervisorMessage] = []
    @Published var isProcessing: Bool = false
    @Published var currentTask: SupervisorTask?
    @Published private(set) var oneShotNormalizationIssues: [OneShotNormalizationIssue] = []
    @Published private(set) var oneShotIntakeRequest: SupervisorOneShotIntakeRequest?
    @Published private(set) var oneShotAdaptivePoolPlan: AdaptivePoolPlanDecision?
    @Published private(set) var oneShotSeatGovernor: OneShotSeatGovernorDecision?
    @Published private(set) var oneShotRunState: OneShotRunStateSnapshot?
    @Published private(set) var oneShotPlannerExplain: [String] = []

    private let eventBus = AXEventBus.shared
    private let hubClient = HubAIClient.shared
    private let modelManager = HubModelManager.shared
    private var appModel: AppModel?
    private let oneShotIntakeCoordinator = OneShotIntakeCoordinator()
    private let oneShotAdaptivePoolPlanner = AdaptivePoolPlanner()
    private let oneShotTaskDecomposer = TaskDecomposer()
    private let oneShotRunStateStore = OneShotRunStateStore()

    private var cancellables = Set<AnyCancellable>()
    private var recentEvents: [String] = []
    private var actionLedger: [SupervisorActionLedgerEntry] = []
    private let actionLedgerMaxEntries = 80

    private var heartbeatTimer: Timer?
    private var lastHeartbeatSnapshot: String = ""
    private var lastHeartbeatAt: TimeInterval = 0
    private let heartbeatIntervalSec: TimeInterval = 300
    private let projectPausedAfterIdleSec: TimeInterval = 300
    private let forceHeartbeatMinIntervalSec: TimeInterval = 15
    private var schedulerPollTimer: Timer?
    private var schedulerSnapshot: HubIPCClient.SchedulerStatusSnapshot?
    private var pendingGrantSnapshot: HubIPCClient.PendingGrantSnapshot?
    private var schedulerLastRefreshAt: TimeInterval = 0
    private var schedulerLastSuccessAt: TimeInterval = 0
    private var schedulerRefreshInFlight = false
    private let schedulerPollIntervalSec: TimeInterval = 2.0
    private let schedulerSnapshotStaleSec: TimeInterval = 12.0
    private var pendingGrantLastSuccessAt: TimeInterval = 0
    @Published private(set) var pendingHubGrants: [SupervisorPendingGrant] = []
    @Published private(set) var pendingHubGrantSource: String = ""
    @Published private(set) var pendingHubGrantUpdatedAt: TimeInterval = 0
    @Published private(set) var hasFreshPendingHubGrantSnapshot: Bool = false
    @Published private(set) var pendingHubGrantActionsInFlight: Set<String> = []
    @Published private(set) var supervisorIncidentLedger: [SupervisorLaneIncident] = []
    @Published private(set) var supervisorLaneHealthSnapshot: SupervisorLaneHealthSnapshot?
    @Published private(set) var supervisorLaneHealthStatusLine: String = "lane health: idle"
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
    private let heartbeatNotificationDedupeKey = "x_terminal_supervisor_heartbeat"
    private var blockerStreakCount: Int = 0
    private var lastBlockerFingerprint: String = ""
    private var lastBlockerEscalationAt: TimeInterval = 0
    private var lastXTReadyIncidentAutoExportAt: TimeInterval = 0
    private let xtReadyIncidentAutoExportMinIntervalSec: TimeInterval = 0.8
    private var lastLaneHealthFingerprint: String = ""

    private static let defaultsThreshold = 3
    private static let defaultsCooldownMinutes = 15
    private let escalationThresholdDefaultsKey = "xterminal_supervisor_blocker_escalation_threshold"
    private let escalationCooldownMinutesDefaultsKey = "xterminal_supervisor_blocker_escalation_cooldown_minutes"
    private let legacyEscalationThresholdDefaultsKey = "xterminal_supervisor_blocker_escalation_threshold"
    private let legacyEscalationCooldownMinutesDefaultsKey = "xterminal_supervisor_blocker_escalation_cooldown_minutes"

    private struct SupervisorMemoryBuildInfo {
        var text: String
        var source: String
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

    private struct ModelAssignmentResult {
        var ok: Bool
        var reasonCode: String
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
    }

    private init() {
        loadEscalationPolicyFromDefaults()
        loadActionLedgerFromDisk()
        setupEventListeners()
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
        restartHeartbeatTimer()
        restartSchedulerPollTimer()
        Task { @MainActor in
            await refreshSchedulerSnapshot(force: true)
        }
        _ = runSupervisorDoctorPreflight(reason: "app_model_attached", emitSystemMessage: false)
        emitHeartbeatIfNeeded(force: true, reason: "app_model_attached")
    }

    private func setupEventListeners() {
        eventBus.eventPublisher
            .sink { [weak self] event in
                self?.handleEvent(event)
            }
            .store(in: &cancellables)
    }

    func handleEvent(_ event: AXEvent) {
        var forceHeartbeat = false
        var heartbeatReason = "event"
        switch event {
        case .projectCreated(let entry):
            let text = "新增项目：\(entry.displayName)"
            appendRecentEvent(text)
            addSystemMessage(text)
            forceHeartbeat = true
            heartbeatReason = "project_created"
        case .projectUpdated(let entry):
            let text = "项目状态更新：\(entry.displayName)"
            appendRecentEvent(text)
            forceHeartbeat = true
            heartbeatReason = "project_updated"
        case .projectRemoved(let entry):
            let text = "移除项目：\(entry.displayName)"
            appendRecentEvent(text)
            addSystemMessage(text)
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
        case .toolCallCreated(let sessionId, let toolCall):
            let text = "项目 \(sessionId) 执行工具：\(toolCall.tool.rawValue)"
            appendRecentEvent(text)
            addSystemMessage(text)
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

        isProcessing = true

        Task {
            await processUserMessage(text)
        }
    }

    private func processUserMessage(_ text: String) async {
        if let local = await handleLocalPreflightCommand(text) {
            let assistantMessage = SupervisorMessage(
                id: UUID().uuidString,
                role: .assistant,
                content: local,
                isVoice: false,
                timestamp: Date().timeIntervalSince1970
            )
            messages.append(assistantMessage)
            isProcessing = false
            return
        }

        let response = await generateSupervisorResponse(text)

        let assistantMessage = SupervisorMessage(
            id: UUID().uuidString,
            role: .assistant,
            content: response,
            isVoice: false,
            timestamp: Date().timeIntervalSince1970
        )

        messages.append(assistantMessage)
        isProcessing = false
    }

    private func generateSupervisorResponse(_ userMessage: String) async -> String {
        await refreshSchedulerSnapshot(force: false)
        let preferredModel = modelManager.getPreferredModel(for: .supervisor)
        let memoryInfo = await buildSupervisorMemoryV1(userMessage: userMessage)
        let memoryV1 = memoryInfo.text

        let prompt = """
你是一个 Supervisor AI，负责管理所有编程项目（跨项目协调、分配模型、推进执行）。

请使用下面的 5 层 Memory v1 上下文（已包含项目与模型快照）：
\(memoryV1)

用户问题：\(userMessage)

请用中文回答，格式清晰，包含可以直接执行的建议。

当你要执行动作时，请用以下标签（可以与正常回答同时出现）：
1) 创建项目：
[CREATE_PROJECT]项目名称[/CREATE_PROJECT]

2) 给单个项目分配模型（项目引用支持项目ID/项目名）：
[ASSIGN_MODEL]项目引用|角色|模型ID[/ASSIGN_MODEL]

3) 给所有项目批量分配模型：
[ASSIGN_MODEL_ALL]角色|模型ID[/ASSIGN_MODEL_ALL]

注意：同一轮如果要分配模型，只输出 ASSIGN_MODEL 或 ASSIGN_MODEL_ALL 其中一个，不要同时输出。
"""

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
            for try await ev in await hubClient.streamResponse(reqId: rid, timeoutSec: 300.0) {
                if ev.type == "delta", let t = ev.text {
                    response += t
                }
            }

            let processedResponse = processSupervisorCommands(response)
            if processedResponse.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return generateFallbackResponse(userMessage)
            }
            return processedResponse
        } catch {
            print("Supervisor AI error: \(error)")
            let detail: String
            if let e = error as? LocalizedError, let desc = e.errorDescription, !desc.isEmpty {
                detail = desc
            } else {
                detail = error.localizedDescription
            }
            return "❌ Supervisor 调用失败：\(detail)\n\n" + generateFallbackResponse(userMessage)
        }
    }

    private func processSupervisorCommands(_ response: String) -> String {
        var processedResponse = response

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
                verifiedAt: nil
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
            guard let role = AXRole(rawValue: parts[0].lowercased()) else {
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
            guard let role = AXRole(rawValue: parts[1].lowercased()) else {
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

    private func generateProjectList() -> String {
        let projects = allProjects()
        if projects.isEmpty {
            return "(暂无项目)"
        }
        return projects.map { project in
            let state = (project.currentStateSummary ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let next = (project.nextStepSummary ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let blocker = (project.blockerSummary ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let digest = (project.statusDigest ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let runtime = runtimeStatus(for: project)

            return """
            - \(project.displayName)
              项目ID: \(project.projectId)
              运行态: \(runtime.text)
              状态摘要: \(digest.isEmpty ? "(暂无)" : digest)
              当前状态: \(state.isEmpty ? "(暂无)" : state)
              下一步: \(next.isEmpty ? "(暂无)" : next)
              阻塞: \(blocker.isEmpty ? "(无)" : blocker)
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

        if userMessage.contains("进度") || userMessage.contains("状态") {
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
        return """
我已收到你的指令。作为 Supervisor，我可以帮你：

📋 查询项目状态
- "查看所有项目进度"
- "项目A的状态如何"

🤖 批量分配模型
- "给所有项目的 coder 分配 xxx 模型"
- "把 reviewer 都改成 auto"

🚧 分析项目卡点
- "哪个项目卡住了"
- "项目A有什么问题"

🩺 发布前体检 / Secrets 预检
- "/doctor" 或 "运行 doctor 预检"
- "/secrets dry-run" 查看目标路径/变量/权限边界摘要

🫀 主动心跳同步
- 我会周期性推送项目心跳，汇报关键变化与阻塞

当前项目数：\(projects.count)
你刚才说的是："\(userMessage)"
"""
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
        let constitution = loadConstitutionOneLiner(userMessage: userMessage)
        let canonical = capped(generateProjectList(), maxChars: 2400)
        let observations = recentEvents.suffix(8).joined(separator: "\n")
        let chatWorkingSet = messages
            .suffix(8)
            .map { "\($0.role.rawValue): \(capped($0.content, maxChars: 220))" }
            .joined(separator: "\n")
        let actionWorkingSet = generateActionLedgerSummary(maxItems: 8)
        let workingSet = """
\(chatWorkingSet.isEmpty ? "(none)" : chatWorkingSet)
\(actionWorkingSet.isEmpty ? "" : "\n[action_ledger]\n\(actionWorkingSet)")
"""
        let rawEvidence = capped(generateAvailableModels(), maxChars: 1400)

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
models:
\(rawEvidence.isEmpty ? "(none)" : rawEvidence)
latest_user:
\(capped(userMessage, maxChars: 300))
[/L4_RAW_EVIDENCE]
[/MEMORY_V1]
"""
        let hub = await HubIPCClient.requestMemoryContext(
            mode: "supervisor",
            projectId: nil,
            projectRoot: nil,
            displayName: "Supervisor",
            latestUser: userMessage,
            constitutionHint: constitution,
            canonicalText: canonical,
            observationsText: observations,
            workingSetText: workingSet,
            rawEvidenceText: rawEvidence,
            budgets: nil,
            timeoutSec: 1.2
        )
        if let hub {
            let src = hub.source.trimmingCharacters(in: .whitespacesAndNewlines)
            return SupervisorMemoryBuildInfo(text: hub.text, source: src.isEmpty ? "hub_memory_v1" : src)
        }
        return SupervisorMemoryBuildInfo(text: local, source: "local_fallback")
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

    private func allProjects() -> [AXProjectEntry] {
        let projects = appModel?.registry.projects ?? AXProjectRegistryStore.load().projects
        return projects.sorted { a, b in
            if a.pinned != b.pinned { return a.pinned && !b.pinned }
            if a.lastOpenedAt != b.lastOpenedAt { return a.lastOpenedAt > b.lastOpenedAt }
            return a.displayName.localizedCaseInsensitiveCompare(b.displayName) == .orderedAscending
        }
    }

    private func appendRecentEvent(_ text: String) {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        recentEvents.append(cleaned)
        if recentEvents.count > 30 {
            recentEvents.removeFirst(recentEvents.count - 30)
        }
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
        verifiedAt: Double?
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
            verifiedAt: verifiedAt
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
                target = pid
            } else {
                target = item.targetRef
            }
            let model = (item.modelId ?? "").isEmpty ? "-" : (item.modelId ?? "-")
            return "- \(item.action) target=\(target) role=\(item.role ?? "-") model=\(model) status=\(item.status) reason=\(item.reasonCode)"
        }.joined(separator: "\n")
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

        let snapshot = await HubIPCClient.requestSchedulerStatus(includeQueueItems: true, queueItemsLimit: 120)
        if let snapshot {
            schedulerSnapshot = snapshot
            schedulerLastSuccessAt = Date().timeIntervalSince1970
        } else if force || (schedulerLastSuccessAt > 0 && (now - schedulerLastSuccessAt) >= schedulerSnapshotStaleSec) {
            schedulerSnapshot = nil
        }

        let pendingGrants = await HubIPCClient.requestPendingGrantRequests(projectId: nil, limit: 240)
        if let pendingGrants {
            pendingGrantSnapshot = pendingGrants
            pendingGrantLastSuccessAt = Date().timeIntervalSince1970
        } else if force || (pendingGrantLastSuccessAt > 0 && (now - pendingGrantLastSuccessAt) >= schedulerSnapshotStaleSec) {
            pendingGrantSnapshot = nil
        }
        rebuildPendingHubGrantViewState(now: Date().timeIntervalSince1970)
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
        let focusProjectId = blockerProjects.first?.projectId
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
            nextStepSummary: nextStepSummary,
            queuePendingCount: queueSignals.count,
            permissionPendingCount: permissionSignals.count
        )
    }

    private struct BlockerSignal {
        var streak: Int
        var escalated: Bool
        var cooldownRemainingSec: Int
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

    func refreshSupervisorDoctorReport() {
        _ = runSupervisorDoctorPreflight(reason: "manual_refresh", emitSystemMessage: true)
    }

    func refreshPendingHubGrantSnapshotNow() {
        Task { @MainActor in
            await refreshSchedulerSnapshot(force: true)
        }
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
        } else {
            let action = approve ? "通过" : "拒绝"
            let reason = result.reasonCode?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown"
            addSystemMessage("Hub 授权\(action)失败：\(grant.projectName)（grant=\(grantId)，reason=\(reason)）")
        }

        await refreshSchedulerSnapshot(force: true)
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
        nextStepSummary: String,
        queuePendingCount: Int,
        permissionPendingCount: Int
    ) {
        let title: String
        let unread: Bool
        if blockerCount > 0, blockerSignal.escalated {
            title = "🚨 Supervisor 升级提醒：\(blockerCount) 个阻塞已持续 \(blockerSignal.streak) 次心跳"
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

        let finalRunState: OneShotRunStateSnapshot
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
        } else {
            finalRunState = oneShotRunStateStore.transition(
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
}
