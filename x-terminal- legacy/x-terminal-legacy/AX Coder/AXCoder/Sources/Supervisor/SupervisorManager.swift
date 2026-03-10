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

    private let eventBus = AXEventBus.shared
    private let hubClient = HubAIClient.shared
    private let modelManager = HubModelManager.shared
    private var appModel: AppModel?

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
    @Published private(set) var blockerEscalationThreshold: Int = 3
    @Published private(set) var blockerEscalationCooldownSec: TimeInterval = 900
    private let heartbeatNotificationDedupeKey = "x_terminal_supervisor_heartbeat"
    private var blockerStreakCount: Int = 0
    private var lastBlockerFingerprint: String = ""
    private var lastBlockerEscalationAt: TimeInterval = 0

    private static let defaultsThreshold = 3
    private static let defaultsCooldownMinutes = 15
    private let escalationThresholdDefaultsKey = "xterminal_supervisor_blocker_escalation_threshold"
    private let escalationCooldownMinutesDefaultsKey = "xterminal_supervisor_blocker_escalation_cooldown_minutes"
    private let legacyEscalationThresholdDefaultsKey = "axcoder_supervisor_blocker_escalation_threshold"
    private let legacyEscalationCooldownMinutesDefaultsKey = "axcoder_supervisor_blocker_escalation_cooldown_minutes"

    private struct SupervisorMemoryBuildInfo {
        var text: String
        var source: String
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
        let permissionSignals = collectPermissionSignals(for: projects, now: now)

        let queueFingerprint = queueSignals
            .map { "\($0.project.projectId):\($0.queued):\($0.inFlight)" }
            .joined(separator: "|")
        let permissionFingerprint = permissionSignals
            .map { "\($0.projectId):\($0.kind.rawValue):\($0.summary)" }
            .joined(separator: "|")
        let snapshot = projects.map { p in
            [
                p.projectId,
                p.statusDigest ?? "",
                p.currentStateSummary ?? "",
                p.nextStepSummary ?? "",
                p.blockerSummary ?? "",
            ].joined(separator: "|")
        }.joined(separator: "\n") + "\n[queue]\(queueFingerprint)\n[perm]\(permissionFingerprint)"

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

重点看板：
\(top)

排队态势：
\(queueSummary.isEmpty ? "（无）" : queueSummary)

权限申请：
\(permissionSummary.isEmpty ? "（无）" : permissionSummary)

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
        case networkGrant = "network_grant"
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
        for projects: [AXProjectEntry],
        now: TimeInterval
    ) -> [ProjectPermissionSignal] {
        var out: [ProjectPermissionSignal] = []
        let useHubPendingGrants = hasFreshPendingGrantSnapshot(now: now)
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

            if !useHubPendingGrants,
               let network = latestNeedNetworkRecord(for: ctx),
               let pendingNetwork = makePendingNetworkSignal(
                    project: project,
                    createdAt: network.createdAt,
                    output: network.output,
                    now: now
               ) {
                out.append(pendingNetwork)
            }
        }

        if useHubPendingGrants {
            out.append(contentsOf: hubPendingGrantSignals(for: projects, now: now))
        }

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

    private func hubPendingGrantSignals(
        for projects: [AXProjectEntry],
        now: TimeInterval
    ) -> [ProjectPermissionSignal] {
        guard hasFreshPendingGrantSnapshot(now: now), let snapshot = pendingGrantSnapshot else {
            return []
        }

        let projectsById = Dictionary(uniqueKeysWithValues: projects.map { ($0.projectId, $0) })
        var out: [ProjectPermissionSignal] = []

        for item in snapshot.items {
            let status = item.status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let decision = item.decision.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if status != "pending", decision != "queued" {
                continue
            }

            let projectId = item.projectId.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !projectId.isEmpty, let project = projectsById[projectId] else {
                continue
            }

            let capability = item.capability.trimmingCharacters(in: .whitespacesAndNewlines)
            let modelId = item.modelId.trimmingCharacters(in: .whitespacesAndNewlines)
            let capabilityText = grantCapabilityText(capability: capability, modelId: modelId)
            var summary = "等待 Hub 授权：\(capabilityText)"
            let reason = item.reason.trimmingCharacters(in: .whitespacesAndNewlines)
            if !reason.isEmpty {
                summary += "（\(capped(reason, maxChars: 48))）"
            }

            out.append(
                ProjectPermissionSignal(
                    projectId: project.projectId,
                    projectName: project.displayName,
                    kind: .hubGrant,
                    summary: summary,
                    createdAt: item.createdAtMs > 0 ? item.createdAtMs / 1000.0 : nil,
                    grantRequestId: item.grantRequestId,
                    capability: capability,
                    actionURL: supervisorActionURL(
                        projectId: project.projectId,
                        grantRequestId: item.grantRequestId,
                        capability: capability
                    )
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

    private func latestNeedNetworkRecord(for ctx: AXProjectContext) -> (createdAt: TimeInterval, output: String)? {
        let url = ctx.rawLogURL
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let data = readTailData(url: url, maxBytes: 280_000),
              let text = String(data: data, encoding: .utf8) else { return nil }

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: true).reversed() {
            let line = String(rawLine)
            guard let lineData = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
                continue
            }
            guard (obj["type"] as? String) == "tool",
                  (obj["action"] as? String) == "need_network" else {
                continue
            }
            let output = (obj["output"] as? String) ?? ""
            let createdAt = (obj["created_at"] as? Double) ?? 0
            return (createdAt: createdAt, output: output)
        }
        return nil
    }

    private func makePendingNetworkSignal(
        project: AXProjectEntry,
        createdAt: TimeInterval,
        output: String,
        now: TimeInterval
    ) -> ProjectPermissionSignal? {
        let lowered = output.lowercased()
        let pending = lowered.contains("waiting for hub approval")
            || lowered.contains("network_request_queued")
            || lowered.contains("network_request_sent")
        guard pending else { return nil }

        if createdAt > 0, now - createdAt > 7_200 {
            // Old pending hints are often stale (already approved/rejected); hide after 2h.
            return nil
        }

        let grantId = firstRegexMatch(output, pattern: #"grant=([A-Za-z0-9_\-]+)"#, group: 1)
        var detail = "等待 Hub 授权联网"
        if let grantId {
            detail += "（grant=\(grantId)）"
        }
        return ProjectPermissionSignal(
            projectId: project.projectId,
            projectName: project.displayName,
            kind: .networkGrant,
            summary: detail,
            createdAt: createdAt > 0 ? createdAt : nil,
            grantRequestId: grantId,
            capability: "CAPABILITY_WEB_FETCH",
            actionURL: supervisorActionURL(
                projectId: project.projectId,
                grantRequestId: grantId,
                capability: "CAPABILITY_WEB_FETCH"
            )
        )
    }

    private func readTailData(url: URL, maxBytes: Int) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        let tailBytes = max(4_096, maxBytes)
        let totalSize = (try? handle.seekToEnd()) ?? 0
        let start = totalSize > UInt64(tailBytes) ? totalSize - UInt64(tailBytes) : 0
        try? handle.seek(toOffset: start)
        return try? handle.readToEnd()
    }

    private func firstRegexMatch(_ text: String, pattern: String, group: Int = 0) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = text as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let match = regex.firstMatch(in: text, options: [], range: range) else { return nil }
        guard group >= 0, group < match.numberOfRanges else { return nil }
        let r = match.range(at: group)
        guard r.location != NSNotFound else { return nil }
        return ns.substring(with: r)
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

    func clearMessages() {
        messages.removeAll()
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
