import Foundation

/// 执行监控器 - 负责监控任务执行状态
@MainActor
class ExecutionMonitor: ObservableObject {

    // MARK: - 属性

    weak var supervisor: SupervisorModel?

    /// 任务执行状态
    @Published var taskStates: [UUID: TaskExecutionState] = [:]

    /// lane 运行态快照（XT-W2-13）
    @Published private(set) var laneStates: [String: LaneRuntimeState] = [:]
    @Published private(set) var laneHealthSummary: LaneHealthSummary = .empty

    /// 监控是否活跃
    @Published var isMonitoring: Bool = false

    /// 已完成 lane（用于依赖门控）
    @Published private(set) var completedLaneIDs: Set<String> = []
    @Published private(set) var incidents: [SupervisorLaneIncident] = []
    @Published private(set) var directedUnblockBatons: [DirectedUnblockBaton] = []

    /// 监控间隔（秒）
    private let monitoringInterval: TimeInterval = 1.0

    /// 任务停滞阈值（秒）
    private let taskStallThreshold: TimeInterval = 2.0

    /// 最大重试次数
    private let maxRetries: Int = 3

    /// 监控任务
    private var monitoringTask: Task<Void, Never>?

    private let eventBus = AXEventBus.shared
    private let heartbeatController = LaneHeartbeatController(stallTimeoutMs: 2_000)
    private let incidentArbiter = IncidentArbiter()
    private let directedUnblockRouter = DirectedUnblockRouter()
    private var blockedReasonByTaskID: [UUID: LaneBlockedReason] = [:]
    private var pendingAutoGrantTaskIDs: Set<UUID> = []
    private var laneConcurrencyLimit: Int = .max
    private var lastPublishedLaneHealthFingerprint: String = ""
    private var pendingGrantProjectIDs: Set<UUID> = []
    private var pendingGrantProjectTokenSet: Set<String> = []
    private var hasUnscopedPendingGrant: Bool = false
    private var pendingGrantBlockedSinceMsByTaskID: [UUID: Int64] = [:]
    private var lastPendingGrantRefreshAt: TimeInterval = 0
    private let pendingGrantRefreshIntervalSec: TimeInterval = 1.5
    private let awaitingInstructionEscalationMs: Int64 = 4_000
    private var parentForkOverflowBlockedCount: Int = 0
    private var parentForkOverflowSilentFailCount: Int = 0
    private var parentForkOverflowDetectSamplesMs: [Int64] = []
    private var routeFallbackSameChannelAllowedCount: Int = 0
    private var routeFallbackCrossChannelBlockedCount: Int = 0
    private var routeOriginFallbackViolations: Int = 0
    private var dispatchIdleStuckIncidents: Int = 0
    private var laneStallDetectSamplesMs: [Int64] = []
    private var cleanupLedgerByLaneID: [String: LaneCleanupLedgerRecord] = [:]
    private var completionDetectSamplesMs: [Int64] = []
    private var duplicateCompletionActions: Int = 0
    private var completionEventDedupeKeys: Set<String> = []
    private var completionDetectedEvents: [SupervisorLaneCompletionDetectedEvent] = []
    private let parentForkDefaultMaxTokens: Int = 12_000

    // MARK: - 初始化

    init(supervisor: SupervisorModel? = nil) {
        self.supervisor = supervisor
    }

    deinit {
        monitoringTask?.cancel()
    }

    // MARK: - 公共方法

    /// 设置 lane 启动并发上限（XT-W2-12 LaneLauncher）
    func configureLaneLaunchPolicy(concurrencyLimit: Int) {
        laneConcurrencyLimit = max(1, concurrencyLimit)
    }

    /// 开始监控任务
    /// - Parameters:
    ///   - task: 要监控的任务
    ///   - project: 执行任务的项目
    ///   - laneID: lane 标识（默认从 metadata 读取）
    ///   - agentProfile: 分配到的 agent profile
    ///   - initialStatus: 初始 lane 健康态
    ///   - blockedReason: 阻塞原因（如果是 blocked）
    func startMonitoring(
        _ task: DecomposedTask,
        in project: ProjectModel,
        laneID: String? = nil,
        agentProfile: String? = nil,
        initialStatus: LaneHealthStatus = .running,
        blockedReason: LaneBlockedReason? = nil
    ) async {
        let resolvedLaneID = laneID ?? self.laneID(for: task)

        var trackedTask = task
        trackedTask.assignedProjectId = project.id
        trackedTask.metadata["lane_id"] = resolvedLaneID
        trackedTask.metadata["agent_profile"] = agentProfile ?? trackedTask.metadata["agent_profile"]

        let guardResult = evaluateStartupRuntimeGuard(task: trackedTask, laneID: resolvedLaneID)
        let resolvedBlockedReason = guardResult?.blockedReason ?? blockedReason
        let resolvedInitialStatus: LaneHealthStatus = {
            if resolvedBlockedReason != nil { return .blocked }
            if initialStatus == .blocked { return .blocked }
            return initialStatus
        }()
        let taskStatus: DecomposedTaskStatus = resolvedInitialStatus == .blocked ? .blocked : .inProgress

        trackedTask.status = taskStatus
        if let resolvedBlockedReason {
            trackedTask.metadata["blocked_reason"] = resolvedBlockedReason.rawValue
        } else {
            trackedTask.metadata.removeValue(forKey: "blocked_reason")
        }
        if let guardResult {
            trackedTask.metadata["deny_code"] = guardResult.denyCode
            trackedTask.metadata["runtime_guard_note"] = guardResult.note
        }

        let state = TaskExecutionState(
            task: trackedTask,
            projectId: project.id,
            startedAt: Date(),
            lastUpdateAt: Date(),
            progress: taskStatus == .completed ? 1.0 : 0.0,
            currentStatus: taskStatus,
            attempts: 1,
            errors: [],
            logs: []
        )

        taskStates[trackedTask.id] = state
        if let resolvedBlockedReason {
            blockedReasonByTaskID[trackedTask.id] = resolvedBlockedReason
        } else if let rawReason = trackedTask.metadata["blocked_reason"], !rawReason.isEmpty {
            blockedReasonByTaskID[trackedTask.id] = LaneBlockedReason(metadataValue: rawReason)
        }

        heartbeatController.registerLane(
            laneID: resolvedLaneID,
            taskId: trackedTask.id,
            projectId: project.id,
            agentProfile: agentProfile,
            initialStatus: resolvedInitialStatus,
            blockedReason: resolvedBlockedReason,
            recommendation: resolvedInitialStatus == .blocked
                ? recommendation(for: resolvedBlockedReason ?? .unknown)
                : "continue"
        )

        refreshLaneSnapshots()
        addLog(for: trackedTask.id, message: "开始执行任务: \(trackedTask.description)")
        if let guardResult {
            addLog(for: trackedTask.id, message: "runtime_guard_blocked: \(guardResult.note)")
        }

        if !isMonitoring {
            startMonitoringLoop()
        }
    }

    /// 注册无法启动但需要托管的 lane（例如分配失败）
    func registerUnassignedLane(
        task: DecomposedTask,
        laneID: String,
        reason: LaneBlockedReason,
        note: String
    ) {
        heartbeatController.recordHeartbeat(
            laneID: laneID,
            taskId: task.id,
            projectId: nil,
            agentProfile: task.metadata["agent_profile"],
            status: .failed,
            blockedReason: reason,
            recommendation: "replan",
            note: note
        )
        refreshLaneSnapshots()

        if !isMonitoring {
            startMonitoringLoop()
        }
    }

    /// 停止监控任务
    /// - Parameter taskId: 任务 ID
    func stopMonitoring(_ taskId: UUID) {
        taskStates.removeValue(forKey: taskId)
        blockedReasonByTaskID.removeValue(forKey: taskId)
        pendingAutoGrantTaskIDs.remove(taskId)
        pendingGrantBlockedSinceMsByTaskID.removeValue(forKey: taskId)

        if taskStates.isEmpty && laneStates.values.allSatisfy({ $0.status.isTerminal }) {
            stopMonitoringLoop()
        }
    }

    /// 更新任务状态
    /// - Parameters:
    ///   - taskId: 任务 ID
    ///   - status: 新状态
    ///   - blockedReason: 阻塞原因
    ///   - note: 附加说明
    func updateState(
        _ taskId: UUID,
        status: DecomposedTaskStatus,
        blockedReason: LaneBlockedReason? = nil,
        note: String? = nil
    ) async {
        guard var state = taskStates[taskId] else { return }

        state.currentStatus = status
        state.lastUpdateAt = Date()

        let laneID = self.laneID(for: state.task)
        let reason = blockedReason ?? blockedReasonFromTask(state.task)

        switch status {
        case .completed:
            state.progress = 1.0
            taskStates[taskId] = state
            completedLaneIDs.insert(laneID)
            addLog(for: taskId, message: "任务完成")
            recordLaneCompletionDetectedEvent(
                laneID: laneID,
                taskID: taskId,
                projectID: state.projectId,
                task: state.task,
                startedAt: state.startedAt
            )
            heartbeatController.markCompleted(laneID: laneID, note: note)
            recordCompletionCleanup(
                laneID: laneID,
                taskID: taskId,
                task: state.task,
                outcome: .success,
                note: note
            )
            refreshLaneSnapshots()
            applyDirectedUnblockContinue(
                resolvedLaneID: laneID,
                resolvedTask: state.task,
                resolvedBy: firstNonEmpty(
                    state.task.metadata["resolved_by"],
                    state.task.metadata["current_owner"],
                    state.task.metadata["task_owner"]
                ) ?? "Supervisor",
                resolvedFact: note ?? "dependency_resolved"
            )
            stopMonitoring(taskId)
            return

        case .failed:
            let resolvedFailureReason = inferRuntimeBlockedReason(
                note: note,
                fallback: reason ?? .runtimeError
            )
            taskStates[taskId] = state
            blockedReasonByTaskID[taskId] = resolvedFailureReason
            setTaskMetadata(taskID: taskId, key: "blocked_reason", value: resolvedFailureReason.rawValue)
            addLog(for: taskId, message: "任务失败")
            heartbeatController.markFailed(
                laneID: laneID,
                note: note ?? "task_failed",
                blockedReason: resolvedFailureReason
            )
            refreshLaneSnapshots()
            let error = DecomposedTaskError(
                message: note ?? "任务执行失败",
                code: resolvedFailureReason.rawValue,
                recoverable: resolvedFailureReason == .runtimeError || resolvedFailureReason == .skillRuntimeError
            )
            await handleFailure(taskId, error: error)
            return

        case .cancelled:
            taskStates[taskId] = state
            blockedReasonByTaskID.removeValue(forKey: taskId)
            setTaskMetadata(taskID: taskId, key: "blocked_reason", value: "")
            addLog(for: taskId, message: "任务已取消")
            // LaneHealthStatus does not expose "cancelled"; use completed terminal state while preserving cancel outcome in cleanup ledger.
            heartbeatController.markCompleted(laneID: laneID, note: note ?? "task_cancelled")
            recordCompletionCleanup(
                laneID: laneID,
                taskID: taskId,
                task: state.task,
                outcome: .cancel,
                note: note
            )
            refreshLaneSnapshots()
            stopMonitoring(taskId)
            return

        case .blocked:
            taskStates[taskId] = state
            let resolvedReason = reason ?? .unknown
            blockedReasonByTaskID[taskId] = resolvedReason
            setTaskMetadata(taskID: taskId, key: "blocked_reason", value: resolvedReason.rawValue)
            addLog(for: taskId, message: "任务被阻塞")
            heartbeatController.recordHeartbeat(
                laneID: laneID,
                taskId: taskId,
                projectId: state.projectId,
                agentProfile: state.task.metadata["agent_profile"],
                status: .blocked,
                blockedReason: resolvedReason,
                recommendation: recommendation(for: resolvedReason),
                note: note
            )
            refreshLaneSnapshots()
            return

        default:
            taskStates[taskId] = state
            blockedReasonByTaskID.removeValue(forKey: taskId)
            setTaskMetadata(taskID: taskId, key: "blocked_reason", value: "")
            heartbeatController.recordHeartbeat(
                laneID: laneID,
                taskId: taskId,
                projectId: state.projectId,
                agentProfile: state.task.metadata["agent_profile"],
                status: .running,
                blockedReason: nil,
                recommendation: "continue",
                note: note
            )
            refreshLaneSnapshots()
            return
        }
    }

    /// 更新任务进度
    /// - Parameters:
    ///   - taskId: 任务 ID
    ///   - progress: 进度 (0-1)
    func updateProgress(_ taskId: UUID, progress: Double) async {
        guard var state = taskStates[taskId] else { return }

        let oldProgress = state.progress
        state.updateProgress(progress)
        taskStates[taskId] = state

        let laneID = self.laneID(for: state.task)
        heartbeatController.recordHeartbeat(
            laneID: laneID,
            taskId: state.task.id,
            projectId: state.projectId,
            agentProfile: state.task.metadata["agent_profile"],
            status: .running,
            blockedReason: nil,
            recommendation: "continue",
            note: "progress=\(Int(progress * 100))%"
        )
        refreshLaneSnapshots()

        // 记录重要的进度里程碑
        if oldProgress < 0.25 && progress >= 0.25 {
            addLog(for: taskId, message: "进度: 25%")
        } else if oldProgress < 0.5 && progress >= 0.5 {
            addLog(for: taskId, message: "进度: 50%")
        } else if oldProgress < 0.75 && progress >= 0.75 {
            addLog(for: taskId, message: "进度: 75%")
        }
    }

    /// 检查健康状态
    /// - Returns: 健康问题列表
    func checkHealth() async -> [HealthIssue] {
        var issues: [HealthIssue] = []
        let nowMs = Date().millisecondsSinceEpoch

        let transitions = heartbeatController.inspect()
        refreshLaneSnapshots()

        for transition in transitions {
            guard let lane = laneStates[transition.laneID] else { continue }
            switch transition.to {
            case .stalled:
                let detectLatencyMs = max(0, nowMs - lane.lastHeartbeatAtMs)
                laneStallDetectSamplesMs.append(detectLatencyMs)
                issues.append(
                    HealthIssue(
                        taskId: lane.taskId,
                        type: .stalled,
                        severity: .high,
                        message: "lane \(transition.laneID) heartbeat 超时（>2s）"
                    )
                )
            case .blocked:
                issues.append(
                    HealthIssue(
                        taskId: lane.taskId,
                        type: .blocked,
                        severity: .medium,
                        message: "lane \(transition.laneID) 进入 blocked"
                    )
                )
            case .failed:
                issues.append(
                    HealthIssue(
                        taskId: lane.taskId,
                        type: .maxRetriesExceeded,
                        severity: .critical,
                        message: "lane \(transition.laneID) failed"
                    )
                )
            default:
                break
            }
        }

        for (taskID, state) in taskStates {
            // 检查超时
            let elapsed = Date().timeIntervalSince(state.startedAt)
            let estimated = state.task.estimatedEffort
            if elapsed > estimated * 1.5 {
                issues.append(
                    HealthIssue(
                        taskId: taskID,
                        type: .timeout,
                        severity: .high,
                        message: "任务执行时间超过预期 50%"
                    )
                )
            }

            // 检查停滞（inProgress 且 2 秒无更新）
            if state.currentStatus == .inProgress {
                let timeSinceUpdate = Date().timeIntervalSince(state.lastUpdateAt)
                if timeSinceUpdate > taskStallThreshold {
                    issues.append(
                        HealthIssue(
                            taskId: taskID,
                            type: .stalled,
                            severity: .medium,
                            message: "任务超过 \(Int(taskStallThreshold)) 秒无更新"
                        )
                    )
                }
            }

            // 检查错误率
            if state.errors.count > 2 {
                issues.append(
                    HealthIssue(
                        taskId: taskID,
                        type: .highErrorRate,
                        severity: .high,
                        message: "任务错误次数过多: \(state.errors.count)"
                    )
                )
            }

            // 检查重试次数
            if state.attempts > maxRetries {
                issues.append(
                    HealthIssue(
                        taskId: taskID,
                        type: .maxRetriesExceeded,
                        severity: .critical,
                        message: "任务重试次数超过限制"
                    )
                )
            }
        }

        return issues
    }

    /// 处理任务失败
    /// - Parameters:
    ///   - taskId: 任务 ID
    ///   - error: 错误信息
    func handleFailure(_ taskId: UUID, error: DecomposedTaskError) async {
        guard var state = taskStates[taskId] else { return }

        state.recordError(error)
        taskStates[taskId] = state

        addLog(for: taskId, message: "错误: \(error.message)")

        if error.recoverable && state.attempts < maxRetries {
            addLog(for: taskId, message: "准备重试 (第 \(state.attempts + 1) 次)")
            await retryTask(taskId)
        } else {
            let resolvedReason = inferRuntimeBlockedReason(
                note: error.code ?? error.message,
                fallback: blockedReasonFromTask(state.task) ?? .runtimeError
            )
            addLog(for: taskId, message: "任务失败，不再重试")
            state.currentStatus = .failed
            state.task.metadata["blocked_reason"] = resolvedReason.rawValue
            taskStates[taskId] = state
            blockedReasonByTaskID[taskId] = resolvedReason
            heartbeatController.markFailed(
                laneID: laneID(for: state.task),
                note: error.message,
                blockedReason: resolvedReason
            )
            recordCompletionCleanup(
                laneID: laneID(for: state.task),
                taskID: taskId,
                task: state.task,
                outcome: .fail,
                note: error.message
            )
            refreshLaneSnapshots()
            stopMonitoring(taskId)
        }
    }

    /// 生成执行报告
    /// - Returns: 执行报告
    func generateReport() -> ExecutionReport {
        let allStates = Array(taskStates.values)

        let totalTasks = allStates.count
        let completedTasks = allStates.filter { $0.currentStatus == .completed }.count
        let failedTasks = allStates.filter { $0.currentStatus == .failed }.count
        let inProgressTasks = allStates.filter { $0.currentStatus == .inProgress }.count

        let averageProgress = allStates.isEmpty ? 0.0 : allStates.reduce(0.0) { $0 + $1.progress } / Double(allStates.count)
        let totalErrors = allStates.reduce(0) { $0 + $1.errors.count }
        let estimatedCompletion = estimateCompletionTime(allStates)

        return ExecutionReport(
            totalTasks: totalTasks,
            completedTasks: completedTasks,
            failedTasks: failedTasks,
            inProgressTasks: inProgressTasks,
            averageProgress: averageProgress,
            totalErrors: totalErrors,
            estimatedCompletion: estimatedCompletion,
            generatedAt: Date()
        )
    }

    /// SKC-W2-07 machine-readable 可靠性快照（overflow/fallback/cleanup）
    func runtimeReliabilitySnapshot(now: Date = Date()) -> SkillRuntimeReliabilitySnapshot {
        SkillRuntimeReliabilitySnapshot(
            schemaVersion: "xterminal.skill_runtime_reliability.v1",
            generatedAtMs: now.millisecondsSinceEpoch,
            parentForkOverflowBlocked: parentForkOverflowBlockedCount,
            parentForkOverflowSilentFail: parentForkOverflowSilentFailCount,
            parentForkOverflowDetectP95Ms: percentile95(parentForkOverflowDetectSamplesMs),
            routeFallbackSameChannelAllowed: routeFallbackSameChannelAllowedCount,
            routeFallbackCrossChannelBlocked: routeFallbackCrossChannelBlockedCount,
            routeOriginFallbackViolations: routeOriginFallbackViolations,
            dispatchIdleStuckIncidents: dispatchIdleStuckIncidents,
            skillLaneStallDetectP95Ms: percentile95(laneStallDetectSamplesMs),
            cleanupSuccessCount: cleanupLedgerByLaneID.values.filter { $0.outcome == .success }.count,
            cleanupFailCount: cleanupLedgerByLaneID.values.filter { $0.outcome == .fail }.count,
            cleanupCancelCount: cleanupLedgerByLaneID.values.filter { $0.outcome == .cancel }.count,
            cleanupLedger: cleanupLedgerByLaneID.values.sorted { lhs, rhs in
                if lhs.settledAtMs != rhs.settledAtMs {
                    return lhs.settledAtMs < rhs.settledAtMs
                }
                return lhs.laneID < rhs.laneID
            }
        )
    }

    // MARK: - 私有方法

    private func startMonitoringLoop() {
        guard !isMonitoring else { return }

        isMonitoring = true

        monitoringTask = Task {
            while !Task.isCancelled && isMonitoring {
                await performMonitoringCheck()
                try? await Task.sleep(nanoseconds: UInt64(monitoringInterval * 1_000_000_000))
            }
        }
    }

    private func stopMonitoringLoop() {
        isMonitoring = false
        monitoringTask?.cancel()
        monitoringTask = nil
    }

    private func performMonitoringCheck() async {
        promoteBlockedTasksIfCapacityAllows()
        await refreshPendingGrantSignalsIfNeeded()
        applyPendingGrantSignals()

        for (taskID, var state) in taskStates {
            let laneID = self.laneID(for: state.task)
            let reason = blockedReasonFromTask(state.task)

            switch state.currentStatus {
            case .inProgress:
                let elapsed = Date().timeIntervalSince(state.startedAt)
                let estimated = max(1, state.task.estimatedEffort)
                let estimatedProgress = min(1.0, elapsed / estimated)

                if estimatedProgress > state.progress {
                    state.updateProgress(estimatedProgress)
                    taskStates[taskID] = state
                }

                heartbeatController.recordHeartbeat(
                    laneID: laneID,
                    taskId: state.task.id,
                    projectId: state.projectId,
                    agentProfile: state.task.metadata["agent_profile"],
                    status: .running,
                    blockedReason: nil,
                    recommendation: "continue",
                    note: nil
                )

            case .blocked:
                let blocked = reason ?? .unknown
                heartbeatController.recordHeartbeat(
                    laneID: laneID,
                    taskId: state.task.id,
                    projectId: state.projectId,
                    agentProfile: state.task.metadata["agent_profile"],
                    status: .blocked,
                    blockedReason: blocked,
                    recommendation: recommendation(for: blocked),
                    note: nil
                )

            case .failed:
                heartbeatController.markFailed(
                    laneID: laneID,
                    note: "task_failed",
                    blockedReason: reason ?? .runtimeError
                )

            default:
                break
            }
        }

        refreshLaneSnapshots()

        let issues = await checkHealth()
        for issue in issues {
            await handleHealthIssue(issue)
        }

        await arbitrateIncidents()

        if taskStates.isEmpty && laneStates.values.allSatisfy({ $0.status.isTerminal }) {
            stopMonitoringLoop()
        }
    }

    private func promoteBlockedTasksIfCapacityAllows() {
        let runningCount = activeRunningLaneCount()
        let availableSlots: Int
        if laneConcurrencyLimit == .max {
            availableSlots = Int.max
        } else {
            availableSlots = max(0, laneConcurrencyLimit - runningCount)
        }
        if availableSlots == 0 {
            refreshQueuedLaneReasons()
            return
        }

        var candidates: [(taskID: UUID, laneID: String, state: TaskExecutionState, reason: LaneBlockedReason)] = []

        for (taskID, var state) in taskStates {
            guard state.currentStatus == .blocked else { continue }

            let laneID = self.laneID(for: state.task)
            let reason = blockedReasonFromTask(state.task) ?? .unknown
            let dependenciesReady = Set(dependencyLaneIDs(from: state.task)).isSubset(of: completedLaneIDs)

            switch reason {
            case .dependencyBlocked where !dependenciesReady:
                continue
            case .unknown where !dependenciesReady:
                state.task.metadata["blocked_reason"] = LaneBlockedReason.dependencyBlocked.rawValue
                taskStates[taskID] = state
                blockedReasonByTaskID[taskID] = .dependencyBlocked
                continue
            case .dependencyBlocked, .queueStarvation, .unknown:
                candidates.append((taskID: taskID, laneID: laneID, state: state, reason: reason))
            default:
                continue
            }
        }

        guard !candidates.isEmpty else { return }

        candidates.sort { lhs, rhs in
            if lhs.state.task.priority != rhs.state.task.priority {
                return lhs.state.task.priority > rhs.state.task.priority
            }
            if lhs.state.task.estimatedEffort != rhs.state.task.estimatedEffort {
                return lhs.state.task.estimatedEffort < rhs.state.task.estimatedEffort
            }
            return lhs.laneID < rhs.laneID
        }

        let launchBudget = min(availableSlots, candidates.count)
        for index in 0..<launchBudget {
            let candidate = candidates[index]
            var state = candidate.state
            state.currentStatus = .inProgress
            state.lastUpdateAt = Date()
            state.task.status = .inProgress
            state.task.metadata.removeValue(forKey: "blocked_reason")
            taskStates[candidate.taskID] = state
            blockedReasonByTaskID.removeValue(forKey: candidate.taskID)

            let note: String
            switch candidate.reason {
            case .dependencyBlocked:
                note = "dependency_ready"
            case .queueStarvation:
                note = "launch_slot_granted"
            default:
                note = "resumed_by_supervisor"
            }
            addLog(for: candidate.taskID, message: "泳道恢复执行: \(note)")

            heartbeatController.recordHeartbeat(
                laneID: candidate.laneID,
                taskId: state.task.id,
                projectId: state.projectId,
                agentProfile: state.task.metadata["agent_profile"],
                status: .running,
                blockedReason: nil,
                recommendation: "continue",
                note: note
            )
        }

        for candidate in candidates.dropFirst(launchBudget) {
            var state = candidate.state
            state.task.status = .blocked
            state.task.metadata["blocked_reason"] = LaneBlockedReason.queueStarvation.rawValue
            taskStates[candidate.taskID] = state
            blockedReasonByTaskID[candidate.taskID] = .queueStarvation
            heartbeatController.recordHeartbeat(
                laneID: candidate.laneID,
                taskId: state.task.id,
                projectId: state.projectId,
                agentProfile: state.task.metadata["agent_profile"],
                status: .blocked,
                blockedReason: .queueStarvation,
                recommendation: recommendation(for: .queueStarvation),
                note: "queue_waiting"
            )
        }
    }

    private func refreshQueuedLaneReasons() {
        for (taskID, var state) in taskStates {
            guard state.currentStatus == .blocked else { continue }
            let laneID = self.laneID(for: state.task)
            let reason = blockedReasonFromTask(state.task) ?? .unknown
            guard reason == .dependencyBlocked || reason == .queueStarvation || reason == .unknown else {
                continue
            }

            let dependenciesReady = Set(dependencyLaneIDs(from: state.task)).isSubset(of: completedLaneIDs)
            if !dependenciesReady {
                state.task.metadata["blocked_reason"] = LaneBlockedReason.dependencyBlocked.rawValue
                taskStates[taskID] = state
                blockedReasonByTaskID[taskID] = .dependencyBlocked
                continue
            }

            state.task.metadata["blocked_reason"] = LaneBlockedReason.queueStarvation.rawValue
            taskStates[taskID] = state
            blockedReasonByTaskID[taskID] = .queueStarvation
            heartbeatController.recordHeartbeat(
                laneID: laneID,
                taskId: state.task.id,
                projectId: state.projectId,
                agentProfile: state.task.metadata["agent_profile"],
                status: .blocked,
                blockedReason: .queueStarvation,
                recommendation: recommendation(for: .queueStarvation),
                note: "queue_waiting"
            )
        }
    }

    private func refreshPendingGrantSignalsIfNeeded(now: Date = Date()) async {
        let nowSec = now.timeIntervalSince1970
        guard nowSec - lastPendingGrantRefreshAt >= pendingGrantRefreshIntervalSec else {
            return
        }
        lastPendingGrantRefreshAt = nowSec

        guard let snapshot = await HubIPCClient.requestPendingGrantRequests(projectId: nil, limit: 240) else {
            pendingGrantProjectIDs.removeAll()
            pendingGrantProjectTokenSet.removeAll()
            hasUnscopedPendingGrant = false
            pendingGrantBlockedSinceMsByTaskID.removeAll()
            return
        }

        var projects: Set<UUID> = []
        var projectTokens: Set<String> = []
        var unscopedPending = false
        for item in snapshot.items {
            let status = item.status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let decision = item.decision.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard status == "pending" || decision == "queued" else { continue }
            let projectToken = item.projectId.trimmingCharacters(in: .whitespacesAndNewlines)
            if projectToken.isEmpty {
                unscopedPending = true
                continue
            }
            let normalizedToken = projectToken.lowercased()
            projectTokens.insert(normalizedToken)
            if let projectID = UUID(uuidString: projectToken) {
                projects.insert(projectID)
            }
        }
        pendingGrantProjectIDs = projects
        pendingGrantProjectTokenSet = projectTokens
        hasUnscopedPendingGrant = unscopedPending
    }

    private func applyPendingGrantSignals(now: Date = Date()) {
        let nowMs = now.millisecondsSinceEpoch
        var activeGrantBlockedTaskIDs: Set<UUID> = []

        for (taskID, var state) in taskStates {
            let laneID = self.laneID(for: state.task)
            let currentReason = blockedReasonFromTask(state.task)
            let isPermissionBlocked = currentReason == .grantPending || currentReason == .awaitingInstruction
            let taskProjectTokens = projectTokens(for: state)
            let hasScopedPendingGrant = pendingGrantProjectIDs.contains(state.projectId)
                || !taskProjectTokens.isDisjoint(with: pendingGrantProjectTokenSet)
            let hasPendingGrant = hasScopedPendingGrant || hasUnscopedPendingGrant
            let wasSignalBlocked = pendingGrantBlockedSinceMsByTaskID[taskID] != nil

            guard hasPendingGrant else {
                if isPermissionBlocked && wasSignalBlocked {
                    state.currentStatus = .inProgress
                    state.task.status = .inProgress
                    state.task.metadata.removeValue(forKey: "blocked_reason")
                    state.lastUpdateAt = now
                    taskStates[taskID] = state
                    blockedReasonByTaskID.removeValue(forKey: taskID)
                    heartbeatController.recordHeartbeat(
                        laneID: laneID,
                        taskId: taskID,
                        projectId: state.projectId,
                        agentProfile: state.task.metadata["agent_profile"],
                        status: .recovering,
                        blockedReason: nil,
                        recommendation: "continue",
                        note: "grant_cleared"
                    )
                }
                pendingGrantBlockedSinceMsByTaskID.removeValue(forKey: taskID)
                continue
            }

            guard !state.currentStatus.isTerminal else {
                pendingGrantBlockedSinceMsByTaskID.removeValue(forKey: taskID)
                continue
            }

            let blockedSince = pendingGrantBlockedSinceMsByTaskID[taskID] ?? nowMs
            pendingGrantBlockedSinceMsByTaskID[taskID] = blockedSince
            activeGrantBlockedTaskIDs.insert(taskID)

            let nextReason: LaneBlockedReason = nowMs - blockedSince >= awaitingInstructionEscalationMs
                ? .awaitingInstruction
                : .grantPending
            if currentReason == nextReason {
                continue
            }

            state.currentStatus = .blocked
            state.task.status = .blocked
            state.task.metadata["blocked_reason"] = nextReason.rawValue
            state.lastUpdateAt = now
            taskStates[taskID] = state
            blockedReasonByTaskID[taskID] = nextReason

            heartbeatController.recordHeartbeat(
                laneID: laneID,
                taskId: taskID,
                projectId: state.projectId,
                agentProfile: state.task.metadata["agent_profile"],
                status: .blocked,
                blockedReason: nextReason,
                recommendation: recommendation(for: nextReason),
                note: nextReason == .grantPending ? "hub_pending_grant" : "grant_wait_timeout"
            )
            addLog(
                for: taskID,
                message: "权限门禁接管: \(nextReason.rawValue) (project=\(state.projectId.uuidString))"
            )
        }

        pendingGrantBlockedSinceMsByTaskID = pendingGrantBlockedSinceMsByTaskID.filter { activeGrantBlockedTaskIDs.contains($0.key) }
    }

    private func handleHealthIssue(_ issue: HealthIssue) async {
        addLog(for: issue.taskId, message: "健康问题: \(issue.message)")

        switch issue.type {
        case .timeout:
            if issue.severity == .critical {
                await updateState(issue.taskId, status: .failed, note: "timeout_critical")
            }

        case .stalled:
            addLog(for: issue.taskId, message: "检测到任务停滞，等待下一次 heartbeat 巡检")

        case .blocked:
            addLog(for: issue.taskId, message: "任务处于 blocked，等待接管策略")

        case .highErrorRate:
            addLog(for: issue.taskId, message: "错误率过高，考虑暂停任务")

        case .maxRetriesExceeded:
            await updateState(issue.taskId, status: .failed, note: "max_retries_exceeded")
        }
    }

    private func retryTask(_ taskId: UUID) async {
        guard let supervisor,
              var state = taskStates[taskId] else { return }

        state.attempts += 1
        taskStates[taskId] = state

        if let assigner = supervisor.orchestrator?.taskAssigner {
            await assigner.reassignTask(taskId)
        }
    }

    private func addLog(for taskId: UUID, message: String) {
        guard var state = taskStates[taskId] else { return }
        state.addLog(message)
        taskStates[taskId] = state
    }

    private func refreshLaneSnapshots() {
        laneStates = heartbeatController.snapshot()
        laneHealthSummary = heartbeatController.healthSummary()
        publishLaneHealthSnapshotIfNeeded()
    }

    private func activeRunningLaneCount() -> Int {
        laneStates.values.filter { state in
            state.status == .running || state.status == .recovering
        }.count
    }

    private func recommendation(for blockedReason: LaneBlockedReason) -> String {
        switch blockedReason {
        case .skillPreflightFailed:
            return SupervisorIncidentAction.notifyUser.rawValue
        case .skillGrantPending:
            return SupervisorIncidentAction.notifyUser.rawValue
        case .skillRuntimeError:
            return SupervisorIncidentAction.autoRetry.rawValue
        case .dependencyBlocked:
            return "wait_dependency"
        case .queueStarvation:
            return "wait_slot"
        case .grantPending:
            return SupervisorIncidentAction.notifyUser.rawValue
        case .awaitingInstruction:
            return SupervisorIncidentAction.replan.rawValue
        case .runtimeError:
            return SupervisorIncidentAction.autoRetry.rawValue
        case .quotaExceeded:
            return "rebalance_budget"
        case .authzDenied:
            return SupervisorIncidentAction.notifyUser.rawValue
        case .webhookUnhealthy:
            return SupervisorIncidentAction.replan.rawValue
        case .authChallengeLoop:
            return SupervisorIncidentAction.notifyUser.rawValue
        case .restartDrain:
            return "wait_drain_recover"
        case .contextOverflow:
            return "trim_context"
        case .routeOriginUnavailable:
            return "fallback_same_origin"
        case .dispatchIdleTimeout:
            return "restart_dispatch"
        case .unknown:
            return "inspect"
        }
    }

    private func publishLaneHealthSnapshotIfNeeded() {
        let snapshot = buildLaneHealthSnapshot()
        guard !snapshot.lanes.isEmpty else {
            if !lastPublishedLaneHealthFingerprint.isEmpty {
                lastPublishedLaneHealthFingerprint = ""
                eventBus.publish(.supervisorLaneHealth(snapshot))
            }
            return
        }
        if snapshot.fingerprint == lastPublishedLaneHealthFingerprint {
            return
        }
        lastPublishedLaneHealthFingerprint = snapshot.fingerprint
        eventBus.publish(.supervisorLaneHealth(snapshot))
    }

    private func buildLaneHealthSnapshot() -> SupervisorLaneHealthSnapshot {
        let rows = laneStates.values
            .map { SupervisorLaneHealthLaneState(state: $0) }
            .sorted { lhs, rhs in
                if lhs.status != rhs.status {
                    return laneStatusPriority(lhs.status) > laneStatusPriority(rhs.status)
                }
                return lhs.laneID < rhs.laneID
            }

        return SupervisorLaneHealthSnapshot(
            generatedAtMs: Date().millisecondsSinceEpoch,
            summary: laneHealthSummary,
            lanes: rows
        )
    }

    private func laneStatusPriority(_ status: LaneHealthStatus) -> Int {
        switch status {
        case .failed: return 6
        case .stalled: return 5
        case .blocked: return 4
        case .recovering: return 3
        case .running: return 2
        case .waiting: return 1
        case .completed: return 0
        }
    }

    private func estimateCompletionTime(_ states: [TaskExecutionState]) -> Date? {
        guard !states.isEmpty else { return nil }

        var totalRemainingTime: TimeInterval = 0

        for state in states where state.currentStatus != .completed {
            let remainingProgress = 1.0 - state.progress
            totalRemainingTime += state.task.estimatedEffort * remainingProgress
        }

        let averageRemainingTime = totalRemainingTime / Double(states.count)
        return Date().addingTimeInterval(averageRemainingTime)
    }

    private func laneID(for task: DecomposedTask) -> String {
        let laneID = task.metadata["lane_id"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let laneID, !laneID.isEmpty {
            return laneID
        }
        return "lane-\(task.id.uuidString.prefix(8))"
    }

    private func blockedReasonFromTask(_ task: DecomposedTask) -> LaneBlockedReason? {
        if let inMemory = blockedReasonByTaskID[task.id] {
            return inMemory
        }
        guard task.status == .blocked || task.metadata["blocked_reason"] != nil else {
            return nil
        }
        let reason = LaneBlockedReason(metadataValue: task.metadata["blocked_reason"])
        return reason == .unknown && task.status != .blocked ? nil : reason
    }

    private func evaluateStartupRuntimeGuard(
        task: DecomposedTask,
        laneID: String,
        now: Date = Date()
    ) -> RuntimeGuardBlock? {
        let nowMs = now.millisecondsSinceEpoch

        let parentTokens = parseIntMetadata(
            task.metadata,
            keys: ["parent_fork_tokens", "parent_context_tokens", "parent_tokens", "inherited_context_tokens"]
        )
        let parentLimit = parentForkTokenLimit(task.metadata)
        if let parentTokens {
            if parentLimit > 0, parentTokens > parentLimit {
                parentForkOverflowBlockedCount += 1
                let requestedAtMs = Int64(parseIntMetadata(task.metadata, keys: ["parent_fork_started_at_ms", "fork_requested_at_ms"]) ?? Int(nowMs))
                parentForkOverflowDetectSamplesMs.append(max(0, nowMs - requestedAtMs))
                let note = "context_overflow:lane=\(laneID),parent_tokens=\(parentTokens),max=\(parentLimit)"
                return RuntimeGuardBlock(
                    blockedReason: .contextOverflow,
                    denyCode: "context_overflow",
                    note: note
                )
            }
            if parentLimit == 0 {
                addLog(
                    for: task.id,
                    message: "runtime_guard_warn: parent_fork_max_tokens=0 disables overflow blocking (lane=\(laneID), parent_tokens=\(parentTokens))"
                )
            }
        }

        let originChannel = normalizedRuntimeChannel(
            task.metadata["route_origin_channel"]
                ?? task.metadata["route_origin"]
                ?? task.metadata["origin_channel"]
        )
        let fallbackChannel = normalizedRuntimeChannel(
            task.metadata["route_fallback_channel"]
                ?? task.metadata["fallback_channel"]
                ?? task.metadata["fallback_origin"]
        )
        if let originChannel, let fallbackChannel {
            if originChannel == fallbackChannel {
                routeFallbackSameChannelAllowedCount += 1
            } else {
                routeFallbackCrossChannelBlockedCount += 1
                routeOriginFallbackViolations += 1
                let note = "cross_channel_blocked:lane=\(laneID),origin=\(originChannel),fallback=\(fallbackChannel)"
                return RuntimeGuardBlock(
                    blockedReason: .routeOriginUnavailable,
                    denyCode: "cross_channel_blocked",
                    note: note
                )
            }
        }

        if metadataBool(task.metadata, keys: ["permission_denied", "authz_denied", "permission_blocked"]) {
            return RuntimeGuardBlock(
                blockedReason: .authzDenied,
                denyCode: "permission_denied",
                note: "permission_denied:lane=\(laneID)"
            )
        }

        let validatedScope = metadataList(
            firstNonEmpty(task.metadata["validated_scope"], task.metadata["validated_mainline_scope"])
        )
        let requestedScope = metadataList(
            firstNonEmpty(
                task.metadata["requested_scope"],
                task.metadata["scope_request"],
                task.metadata["delivery_scope"],
                task.metadata["public_scope"]
            )
        )
        let blockedExpansionItems = requestedScope.filter { token in
            validatedScope.contains(token) == false
        }
        if blockedExpansionItems.isEmpty == false {
            return RuntimeGuardBlock(
                blockedReason: .awaitingInstruction,
                denyCode: "scope_expansion",
                note: "scope_expansion:lane=\(laneID),items=\(blockedExpansionItems.joined(separator: "+"))"
            )
        }

        let explicitGrantRequired = metadataBool(task.metadata, keys: ["grant_required", "requires_grant", "grant_gate_required"])
            || (isHighRisk(task.metadata) && hasExternalSideEffect(task.metadata))
        let hasGrant = metadataBool(task.metadata, keys: ["grant_ready", "grant_approved", "grant_bound", "grant_attached", "has_grant"])
            || firstNonEmpty(
                task.metadata["grant_request_id"],
                task.metadata["grant_id"],
                task.metadata["last_auto_grant_request_id"]
            ) != nil
        if explicitGrantRequired && hasGrant == false {
            return RuntimeGuardBlock(
                blockedReason: .grantPending,
                denyCode: "grant_required",
                note: "grant_required:lane=\(laneID),grant_gate_mode=fail_closed"
            )
        }

        return nil
    }

    private func recordCompletionCleanup(
        laneID: String,
        taskID: UUID,
        task: DecomposedTask? = nil,
        outcome: RuntimeCompletionOutcome,
        note: String?
    ) {
        let nowMs = Date().millisecondsSinceEpoch
        let metadata = task?.metadata ?? [:]
        let record = LaneCleanupLedgerRecord(
            laneID: laneID,
            taskID: taskID,
            outcome: outcome,
            dispatchIdleCleanupExecuted: true,
            typingCleanupExecuted: true,
            cleanupRequiredChecklist: ["dispatch_idle", "typing_cleanup"],
            cleanupNote: note,
            taskDescription: task?.description ?? "",
            completedTaskRef: completionTaskRef(for: task, laneID: laneID),
            gateVector: metadataList(metadata["gate_vector"]),
            evidenceRefs: metadataList(metadata["evidence_refs"]),
            rollbackRef: firstNonEmpty(metadata["rollback_ref"], metadata["rollback_point"], metadata["rollback_anchor_id"]),
            riskSummary: metadataList(metadata["risk_summary"]),
            auditRef: firstNonEmpty(metadata["audit_ref"]),
            settledAtMs: nowMs
        )
        cleanupLedgerByLaneID[laneID] = record
        if record.dispatchIdleCleanupExecuted == false || record.typingCleanupExecuted == false {
            dispatchIdleStuckIncidents += 1
        }
    }

    private func applyDirectedUnblockContinue(
        resolvedLaneID: String,
        resolvedTask: DecomposedTask,
        resolvedBy: String,
        resolvedFact: String,
        now: Date = Date()
    ) {
        let batons = directedUnblockRouter.routeResolvedDependency(
            completedLaneID: resolvedLaneID,
            resolvedBy: resolvedBy,
            resolvedFact: resolvedFact,
            taskStates: taskStates,
            laneStates: laneStates,
            evidenceRefs: metadataList(resolvedTask.metadata["evidence_refs"]),
            now: now
        )

        guard batons.isEmpty == false else {
            directedUnblockBatons = directedUnblockRouter.ledger(limit: 40)
            return
        }

        for baton in batons {
            guard let targetTaskID = taskID(forLaneID: baton.blockedLane),
                  var waitingState = taskStates[targetTaskID] else {
                continue
            }

            waitingState.currentStatus = .inProgress
            waitingState.lastUpdateAt = now
            waitingState.task.status = .inProgress
            waitingState.task.metadata.removeValue(forKey: "blocked_reason")
            waitingState.task.metadata["last_unblock_baton_edge_id"] = baton.edgeID
            waitingState.task.metadata["last_unblock_resolved_fact"] = baton.resolvedFact
            waitingState.task.metadata["last_unblock_resume_scope"] = baton.resumeScope.rawValue
            taskStates[targetTaskID] = waitingState
            blockedReasonByTaskID.removeValue(forKey: targetTaskID)

            heartbeatController.recordHeartbeat(
                laneID: baton.blockedLane,
                taskId: waitingState.task.id,
                projectId: waitingState.projectId,
                agentProfile: waitingState.task.metadata["agent_profile"],
                status: .recovering,
                blockedReason: nil,
                recommendation: "continue",
                note: baton.edgeID
            )
            addLog(for: targetTaskID, message: "directed_unblock_baton: \(baton.edgeID)")
        }

        directedUnblockBatons = directedUnblockRouter.ledger(limit: 40)
        refreshLaneSnapshots()
    }

    private func inferRuntimeBlockedReason(note: String?, fallback: LaneBlockedReason) -> LaneBlockedReason {
        let token = (note ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
        if token.contains(LaneBlockedReason.contextOverflow.rawValue) {
            return .contextOverflow
        }
        if token.contains("cross_channel_blocked")
            || token.contains(LaneBlockedReason.routeOriginUnavailable.rawValue)
            || token.contains("route_fallback_blocked") {
            return .routeOriginUnavailable
        }
        if token.contains(LaneBlockedReason.dispatchIdleTimeout.rawValue)
            || token.contains("cleanup_timeout")
            || token.contains("typing_cleanup_timeout") {
            return .dispatchIdleTimeout
        }
        if token.contains(LaneBlockedReason.skillPreflightFailed.rawValue) {
            return .skillPreflightFailed
        }
        if token.contains(LaneBlockedReason.skillGrantPending.rawValue) {
            return .skillGrantPending
        }
        if token.contains(LaneBlockedReason.skillRuntimeError.rawValue) {
            return .skillRuntimeError
        }
        if token.contains(LaneBlockedReason.grantPending.rawValue) {
            return .grantPending
        }
        if token.contains(LaneBlockedReason.awaitingInstruction.rawValue) {
            return .awaitingInstruction
        }
        return fallback
    }

    private func parseIntMetadata(_ metadata: [String: String], keys: [String]) -> Int? {
        for key in keys {
            guard let raw = metadata[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
                continue
            }
            if let value = Int(raw) {
                return value
            }
        }
        return nil
    }

    private func metadataBool(_ metadata: [String: String], keys: [String]) -> Bool {
        for key in keys {
            guard let raw = metadata[key]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
                continue
            }
            if ["1", "true", "yes", "y", "required", "deny", "denied", "blocked", "pending", "approved"].contains(raw) {
                return true
            }
        }
        return false
    }

    private func metadataList(_ raw: String?) -> [String] {
        guard let raw else { return [] }
        return orderedUnique(
            raw.replacingOccurrences(of: "\n", with: "|")
                .split(whereSeparator: { $0 == "|" || $0 == "," })
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        )
    }

    private func orderedUnique(_ entries: [String]) -> [String] {
        var seen: Set<String> = []
        var ordered: [String] = []
        for entry in entries {
            let trimmed = entry.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if seen.insert(trimmed).inserted {
                ordered.append(trimmed)
            }
        }
        return ordered
    }

    private func firstNonEmpty(_ values: String?...) -> String? {
        values
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty })
    }

    private func completionTaskRef(for task: DecomposedTask?, laneID: String) -> String {
        guard let task else { return laneID }
        let metadata = task.metadata
        if let explicit = firstNonEmpty(metadata["task_ref"], metadata["work_order"], metadata["task_id"]) {
            return explicit
        }
        let description = task.description.trimmingCharacters(in: .whitespacesAndNewlines)
        return description.isEmpty ? laneID : description
    }

    private func taskID(forLaneID laneID: String) -> UUID? {
        taskStates.first { _, state in
            self.laneID(for: state.task) == laneID
        }?.key
    }

    private func hasExternalSideEffect(_ metadata: [String: String]) -> Bool {
        metadataBool(
            metadata,
            keys: [
                "requires_external_side_effect",
                "requires_payment_auth",
                "requires_external_secret_binding",
                "connector_send",
                "remote_write",
                "webhook_emit"
            ]
        )
    }

    private func isHighRisk(_ metadata: [String: String]) -> Bool {
        guard let rawRisk = metadata["risk_tier"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
            return false
        }
        return rawRisk == "high" || rawRisk == "critical"
    }

    private func normalizedMitigation(_ rawRisk: String) -> String {
        let trimmed = rawRisk.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = trimmed.range(of: ":") {
            let suffix = trimmed[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            if !suffix.isEmpty {
                return suffix
            }
        }
        return trimmed
    }

    private func parentForkTokenLimit(_ metadata: [String: String]) -> Int {
        if let explicit = parseIntMetadata(metadata, keys: ["parent_fork_max_tokens"]) {
            return max(0, explicit)
        }
        if let env = ProcessInfo.processInfo.environment["XT_PARENT_FORK_MAX_TOKENS"],
           let value = Int(env.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return max(0, value)
        }
        return parentForkDefaultMaxTokens
    }

    private func normalizedRuntimeChannel(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let token = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
        guard !token.isEmpty else { return nil }
        switch token {
        case "grpc", "remote", "hub_runtime_grpc":
            return "grpc"
        case "file", "file_ipc", "fileipc", "local":
            return "file"
        case "websocket", "ws":
            return "websocket"
        case "http", "https":
            return "http"
        default:
            return token
        }
    }

    private func percentile95(_ samples: [Int64]) -> Int64 {
        guard !samples.isEmpty else { return 0 }
        let sorted = samples.sorted()
        let rawIndex = Int((Double(sorted.count - 1) * 0.95).rounded(.up))
        let idx = max(0, min(sorted.count - 1, rawIndex))
        return sorted[idx]
    }

    private func inferCompletionSource(from task: DecomposedTask) -> String {
        let mergebackToken = task.metadata["mergeback_gate_result"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if mergebackToken == "pass" || mergebackToken == "ready" {
            return "mergeback_gate"
        }

        let runtimeToken = task.metadata["runtime_status"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if runtimeToken == "completed" || runtimeToken == "done" || runtimeToken == "finished" {
            return "runtime_status"
        }

        return "task_status"
    }

    private func currentCompletionEpoch(for laneID: String) -> Int64 {
        if let lane = laneStates[laneID] {
            return Int64(lane.heartbeatSeq)
        }
        if let lane = heartbeatController.snapshot()[laneID] {
            return Int64(lane.heartbeatSeq)
        }
        return 0
    }

    private func recordLaneCompletionDetectedEvent(
        laneID: String,
        taskID: UUID,
        projectID: UUID,
        task: DecomposedTask,
        startedAt: Date,
        now: Date = Date()
    ) {
        let completionSource = inferCompletionSource(from: task)
        let completionEpoch = currentCompletionEpoch(for: laneID)
        let dedupeKey = "\(laneID)|\(taskID.uuidString)|\(completionEpoch)"
        if completionEventDedupeKeys.contains(dedupeKey) {
            duplicateCompletionActions += 1
            return
        }

        completionEventDedupeKeys.insert(dedupeKey)
        let detectedAtMs = now.millisecondsSinceEpoch
        let startMs = startedAt.millisecondsSinceEpoch
        completionDetectSamplesMs.append(max(0, detectedAtMs - startMs))

        let event = SupervisorLaneCompletionDetectedEvent(
            eventType: "supervisor.lane.completion.detected_machine_event",
            laneID: laneID,
            taskID: taskID,
            projectID: projectID,
            completionSource: completionSource,
            completionEpoch: completionEpoch,
            detectedAtMs: detectedAtMs,
            confidence: 1.0
        )
        completionDetectedEvents.append(event)
        if completionDetectedEvents.count > 120 {
            completionDetectedEvents.removeFirst(completionDetectedEvents.count - 120)
        }
        eventBus.publish(.supervisorLaneCompletionDetected(event))
    }

    private func dependencyLaneIDs(from task: DecomposedTask) -> [String] {
        guard let raw = task.metadata["depends_on"], !raw.isEmpty else {
            return []
        }
        return raw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func normalizedProjectToken(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let token = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return token.isEmpty ? nil : token
    }

    private func projectTokens(for state: TaskExecutionState) -> Set<String> {
        var tokens: Set<String> = []
        if let uuidToken = normalizedProjectToken(state.projectId.uuidString) {
            tokens.insert(uuidToken)
        }

        let metadataKeys = ["project_id", "hub_project_id", "registry_project_id"]
        for key in metadataKeys {
            if let token = normalizedProjectToken(state.task.metadata[key]) {
                tokens.insert(token)
            }
        }
        return tokens
    }

    func recentIncidents(limit: Int = 20) -> [SupervisorLaneIncident] {
        Array(incidents.suffix(max(1, limit)))
    }

    /// XT-W2-26-A completion adapter machine event 导出
    func exportLaneCompletionDetectedMachineEvents(limit: Int = 120) -> [SupervisorLaneCompletionDetectedEvent] {
        Array(completionDetectedEvents.suffix(max(1, limit)))
    }

    /// XT-W2-26-A completion adapter KPI 快照（machine-readable）
    func completionAdapterSnapshot(now: Date = Date()) -> CompletionAdapterSnapshot {
        CompletionAdapterSnapshot(
            schemaVersion: "xterminal.lane_completion_adapter.v1",
            eventType: "supervisor.lane.completion.detected_machine_event",
            generatedAtMs: now.millisecondsSinceEpoch,
            completionDetectLatencyP95Ms: percentile95(completionDetectSamplesMs),
            duplicateCompletionActions: duplicateCompletionActions,
            emittedEventsCount: completionDetectedEvents.count
        )
    }

    func directedUnblockEvidence(now: Date = Date()) -> DirectedUnblockEvidence {
        directedUnblockRouter.snapshot(now: now)
    }

    func buildAcceptanceAggregationInput(
        projectID: UUID,
        userSummaryRef: String,
        auditRef explicitAuditRef: String? = nil,
        additionalEvidenceRefs: [String] = [],
        additionalRollbackPoints: [AcceptanceRollbackPoint] = [],
        additionalRiskSummary: [AcceptanceRisk] = []
    ) -> AcceptanceAggregationInput {
        let successRecords = cleanupLedgerByLaneID.values
            .filter { $0.outcome == .success }
            .sorted { lhs, rhs in
                if lhs.settledAtMs != rhs.settledAtMs {
                    return lhs.settledAtMs < rhs.settledAtMs
                }
                if lhs.completedTaskRef != rhs.completedTaskRef {
                    return lhs.completedTaskRef < rhs.completedTaskRef
                }
                if lhs.laneID != rhs.laneID {
                    return lhs.laneID < rhs.laneID
                }
                return lhs.taskID.uuidString < rhs.taskID.uuidString
            }

        let completedTasks = orderedUnique(
            successRecords.map { record in
                if !record.completedTaskRef.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return record.completedTaskRef
                }
                if !record.taskDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return record.taskDescription
                }
                return record.laneID
            }
        )

        let gateReadings = orderedUnique(successRecords.flatMap(\ .gateVector))
            .compactMap(AcceptanceGateReading.init(token:))

        let recordRisks = successRecords
            .flatMap(\ .riskSummary)
            .enumerated()
            .map { index, rawRisk in
                AcceptanceRisk(
                    riskID: "risk-\(index + 1)",
                    severity: AcceptanceRiskSeverity(token: rawRisk),
                    mitigation: normalizedMitigation(rawRisk)
                )
            }

        let rollbackPoints = successRecords.compactMap { record -> AcceptanceRollbackPoint? in
            guard let rollbackRef = record.rollbackRef?.trimmingCharacters(in: .whitespacesAndNewlines), !rollbackRef.isEmpty else {
                return nil
            }
            return AcceptanceRollbackPoint(component: record.laneID, rollbackRef: rollbackRef)
        } + additionalRollbackPoints

        let evidenceRefs = orderedUnique(successRecords.flatMap(\ .evidenceRefs) + additionalEvidenceRefs)
        let auditRef = explicitAuditRef
            ?? successRecords.compactMap(\ .auditRef).first
            ?? "audit-acceptance-\(projectID.uuidString.lowercased())"

        return AcceptanceAggregationInput(
            projectID: projectID.uuidString.lowercased(),
            completedTasks: completedTasks,
            gateReadings: gateReadings,
            riskSummary: recordRisks + additionalRiskSummary,
            rollbackPoints: rollbackPoints,
            evidenceRefs: evidenceRefs,
            userSummaryRef: userSummaryRef,
            auditRef: auditRef
        )
    }

    /// XT-Ready E2E 证据导出（machine-readable）
    func exportXTReadyIncidentEvents(limit: Int = 120) -> [XTReadyIncidentEvent] {
        let requiredCodes: Set<String> = [
            LaneBlockedReason.grantPending.rawValue,
            LaneBlockedReason.awaitingInstruction.rawValue,
            LaneBlockedReason.runtimeError.rawValue,
        ]

        return incidents
            .filter { requiredCodes.contains($0.incidentCode) && $0.status == .handled }
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

    private func arbitrateIncidents(now: Date = Date()) async {
        let decisions = incidentArbiter.evaluate(
            laneStates: laneStates,
            taskStates: taskStates,
            now: now
        )
        guard !decisions.isEmpty else { return }

        let nowMs = now.millisecondsSinceEpoch
        for decision in decisions {
            await applyIncidentDecision(decision, nowMs: nowMs)
        }

        refreshLaneSnapshots()
    }

    private func applyIncidentDecision(_ decision: IncidentDecision, nowMs: Int64) async {
        var incident = decision.incident

        switch decision.action {
        case .autoRetry:
            if var state = taskStates[decision.taskID], state.attempts < maxRetries {
                addLog(for: decision.taskID, message: "incident=\(incident.incidentCode) -> auto_retry")
                state.currentStatus = .inProgress
                state.lastUpdateAt = Date()
                taskStates[decision.taskID] = state
                blockedReasonByTaskID.removeValue(forKey: decision.taskID)
                clearIncidentEscalationMetadata(taskID: decision.taskID)
                heartbeatController.recordHeartbeat(
                    laneID: decision.laneID,
                    taskId: decision.taskID,
                    projectId: state.projectId,
                    agentProfile: state.task.metadata["agent_profile"],
                    status: .recovering,
                    blockedReason: .runtimeError,
                    recommendation: SupervisorIncidentAction.autoRetry.rawValue,
                    note: incident.auditRef
                )
                await retryTask(decision.taskID)
            } else {
                addLog(for: decision.taskID, message: "incident=\(incident.incidentCode) -> auto_retry_exhausted, pause_lane")
                heartbeatController.markFailed(
                    laneID: decision.laneID,
                    note: "incident_auto_retry_exhausted",
                    blockedReason: .runtimeError
                )
                if var state = taskStates[decision.taskID] {
                    state.currentStatus = .failed
                    state.lastUpdateAt = Date()
                    taskStates[decision.taskID] = state
                }
                incident.proposedAction = .pauseLane
                incident.autoResolvable = false
                incident.requiresUserAck = true
                incident.detail += ",fallback_action=pause_lane"
            }

        case .autoGrant:
            guard !pendingAutoGrantTaskIDs.contains(decision.taskID) else {
                incident.detail += ",auto_grant=inflight"
                break
            }
            pendingAutoGrantTaskIDs.insert(decision.taskID)
            defer { pendingAutoGrantTaskIDs.remove(decision.taskID) }

            addLog(for: decision.taskID, message: "incident=\(incident.incidentCode) -> auto_grant")
            if let state = taskStates[decision.taskID] {
                heartbeatController.recordHeartbeat(
                    laneID: decision.laneID,
                    taskId: decision.taskID,
                    projectId: state.projectId,
                    agentProfile: state.task.metadata["agent_profile"],
                    status: .blocked,
                    blockedReason: LaneBlockedReason(metadataValue: incident.incidentCode),
                    recommendation: SupervisorIncidentAction.autoGrant.rawValue,
                    note: incident.auditRef
                )
            }

            let autoGrantResult = await SupervisorManager.shared.autoApprovePendingHubGrant(
                for: incident.projectID,
                auditRef: incident.auditRef
            )

            if autoGrantResult.ok {
                if var state = taskStates[decision.taskID] {
                    clearIncidentEscalationMetadata(taskID: decision.taskID)
                    state.currentStatus = .inProgress
                    state.lastUpdateAt = Date()
                    state.task.metadata["last_auto_grant_request_id"] = autoGrantResult.grantRequestId
                    taskStates[decision.taskID] = state
                    blockedReasonByTaskID.removeValue(forKey: decision.taskID)
                    heartbeatController.recordHeartbeat(
                        laneID: decision.laneID,
                        taskId: decision.taskID,
                        projectId: state.projectId,
                        agentProfile: state.task.metadata["agent_profile"],
                        status: .recovering,
                        blockedReason: nil,
                        recommendation: "continue",
                        note: autoGrantResult.grantRequestId
                    )
                }
                incident.detail += ",auto_grant=approved,grant_request_id=\(autoGrantResult.grantRequestId ?? "unknown")"
            } else {
                markAutoGrantExhausted(
                    taskID: decision.taskID,
                    reason: autoGrantResult.reasonCode
                )
                incident.proposedAction = .notifyUser
                incident.requiresUserAck = true
                incident.autoResolvable = false
                incident.detail += ",auto_grant=failed,reason=\(autoGrantResult.reasonCode)"
            }

        case .notifyUser:
            addLog(for: decision.taskID, message: "incident=\(incident.incidentCode) -> notify_user")
            if let state = taskStates[decision.taskID] {
                heartbeatController.recordHeartbeat(
                    laneID: decision.laneID,
                    taskId: decision.taskID,
                    projectId: state.projectId,
                    agentProfile: state.task.metadata["agent_profile"],
                    status: .blocked,
                    blockedReason: LaneBlockedReason(metadataValue: incident.incidentCode),
                    recommendation: SupervisorIncidentAction.notifyUser.rawValue,
                    note: incident.auditRef
                )
            }

        case .replan:
            addLog(for: decision.taskID, message: "incident=\(incident.incidentCode) -> replan")
            if let state = taskStates[decision.taskID] {
                let suggestion = buildReplanSuggestion(task: state.task, laneID: decision.laneID)
                setTaskMetadata(taskID: decision.taskID, key: "replan_hint", value: suggestion)
                heartbeatController.recordHeartbeat(
                    laneID: decision.laneID,
                    taskId: decision.taskID,
                    projectId: state.projectId,
                    agentProfile: state.task.metadata["agent_profile"],
                    status: .blocked,
                    blockedReason: LaneBlockedReason(metadataValue: incident.incidentCode),
                    recommendation: SupervisorIncidentAction.replan.rawValue,
                    note: suggestion
                )
                addLog(for: decision.taskID, message: "replan_hint=\(suggestion)")
                incident.detail += ",replan_hint=\(suggestion)"
            }

        case .pauseLane:
            addLog(for: decision.taskID, message: "incident=\(incident.incidentCode) -> pause_lane")
            heartbeatController.markFailed(
                laneID: decision.laneID,
                note: "incident_pause_lane",
                blockedReason: LaneBlockedReason(metadataValue: incident.incidentCode)
            )
            if var state = taskStates[decision.taskID] {
                state.currentStatus = .failed
                state.lastUpdateAt = Date()
                taskStates[decision.taskID] = state
            }
        }

        incident.handledAtMs = nowMs
        incident.takeoverLatencyMs = max(0, nowMs - incident.detectedAtMs)
        incident.status = .handled
        appendIncident(incident)
    }

    private func setTaskMetadata(taskID: UUID, key: String, value: String) {
        guard var state = taskStates[taskID] else { return }
        if value.isEmpty {
            state.task.metadata.removeValue(forKey: key)
        } else {
            state.task.metadata[key] = value
        }
        taskStates[taskID] = state
    }

    private func clearIncidentEscalationMetadata(taskID: UUID) {
        guard var state = taskStates[taskID] else { return }
        state.task.metadata.removeValue(forKey: "auto_grant_exhausted")
        state.task.metadata.removeValue(forKey: "auto_grant_failure_reason")
        taskStates[taskID] = state
    }

    private func markAutoGrantExhausted(taskID: UUID, reason: String) {
        guard var state = taskStates[taskID] else { return }
        state.task.metadata["auto_grant_exhausted"] = "1"
        state.task.metadata["auto_grant_failure_reason"] = reason
        state.currentStatus = .blocked
        state.lastUpdateAt = Date()
        taskStates[taskID] = state
        blockedReasonByTaskID[taskID] = .grantPending
        heartbeatController.recordHeartbeat(
            laneID: laneID(for: state.task),
            taskId: taskID,
            projectId: state.projectId,
            agentProfile: state.task.metadata["agent_profile"],
            status: .blocked,
            blockedReason: .grantPending,
            recommendation: SupervisorIncidentAction.notifyUser.rawValue,
            note: reason
        )
    }

    private func buildReplanSuggestion(task: DecomposedTask, laneID: String) -> String {
        let dependencies = dependencyLaneIDs(from: task)
        if dependencies.isEmpty {
            return "lane=\(laneID):补充下一步指令与验收标准"
        }
        let depText = dependencies.joined(separator: "+")
        return "lane=\(laneID):先确认依赖[\(depText)]产物，再细化下一步指令"
    }

    private func appendIncident(_ incident: SupervisorLaneIncident) {
        incidents.append(incident)
        if incidents.count > 120 {
            incidents.removeFirst(incidents.count - 120)
        }
        eventBus.publish(.supervisorIncident(incident))
    }
}

private extension Date {
    var millisecondsSinceEpoch: Int64 {
        Int64((timeIntervalSince1970 * 1000.0).rounded())
    }
}

// MARK: - 辅助结构

/// XT-Ready 最小 E2E incident 事件行
struct XTReadyIncidentEvent: Codable, Equatable {
    let eventType: String
    let incidentCode: String
    let laneID: String
    let detectedAtMs: Int64
    let handledAtMs: Int64
    let denyCode: String
    let auditEventType: String
    let auditRef: String
    let takeoverLatencyMs: Int64?

    enum CodingKeys: String, CodingKey {
        case eventType = "event_type"
        case incidentCode = "incident_code"
        case laneID = "lane_id"
        case detectedAtMs = "detected_at_ms"
        case handledAtMs = "handled_at_ms"
        case denyCode = "deny_code"
        case auditEventType = "audit_event_type"
        case auditRef = "audit_ref"
        case takeoverLatencyMs = "takeover_latency_ms"
    }
}

private struct RuntimeGuardBlock {
    var blockedReason: LaneBlockedReason
    var denyCode: String
    var note: String
}

enum RuntimeCompletionOutcome: String, Codable {
    case success
    case fail
    case cancel
}

struct LaneCleanupLedgerRecord: Codable, Equatable, Identifiable {
    var id: String { laneID }

    let laneID: String
    let taskID: UUID
    let outcome: RuntimeCompletionOutcome
    let dispatchIdleCleanupExecuted: Bool
    let typingCleanupExecuted: Bool
    let cleanupRequiredChecklist: [String]
    let cleanupNote: String?
    let taskDescription: String
    let completedTaskRef: String
    let gateVector: [String]
    let evidenceRefs: [String]
    let rollbackRef: String?
    let riskSummary: [String]
    let auditRef: String?
    let settledAtMs: Int64

    enum CodingKeys: String, CodingKey {
        case laneID = "lane_id"
        case taskID = "task_id"
        case outcome
        case dispatchIdleCleanupExecuted = "dispatch_idle_cleanup_executed"
        case typingCleanupExecuted = "typing_cleanup_executed"
        case cleanupRequiredChecklist = "cleanup_required_checklist"
        case cleanupNote = "cleanup_note"
        case taskDescription = "task_description"
        case completedTaskRef = "completed_task_ref"
        case gateVector = "gate_vector"
        case evidenceRefs = "evidence_refs"
        case rollbackRef = "rollback_ref"
        case riskSummary = "risk_summary"
        case auditRef = "audit_ref"
        case settledAtMs = "settled_at_ms"
    }
}

struct SkillRuntimeReliabilitySnapshot: Codable, Equatable {
    let schemaVersion: String
    let generatedAtMs: Int64
    let parentForkOverflowBlocked: Int
    let parentForkOverflowSilentFail: Int
    let parentForkOverflowDetectP95Ms: Int64
    let routeFallbackSameChannelAllowed: Int
    let routeFallbackCrossChannelBlocked: Int
    let routeOriginFallbackViolations: Int
    let dispatchIdleStuckIncidents: Int
    let skillLaneStallDetectP95Ms: Int64
    let cleanupSuccessCount: Int
    let cleanupFailCount: Int
    let cleanupCancelCount: Int
    let cleanupLedger: [LaneCleanupLedgerRecord]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case generatedAtMs = "generated_at_ms"
        case parentForkOverflowBlocked = "parent_fork_overflow_blocked"
        case parentForkOverflowSilentFail = "parent_fork_overflow_silent_fail"
        case parentForkOverflowDetectP95Ms = "parent_fork_overflow_detect_p95_ms"
        case routeFallbackSameChannelAllowed = "route_fallback_same_channel_allowed"
        case routeFallbackCrossChannelBlocked = "route_fallback_cross_channel_blocked"
        case routeOriginFallbackViolations = "route_origin_fallback_violations"
        case dispatchIdleStuckIncidents = "dispatch_idle_stuck_incidents"
        case skillLaneStallDetectP95Ms = "skill_lane_stall_detect_p95_ms"
        case cleanupSuccessCount = "cleanup_success_count"
        case cleanupFailCount = "cleanup_fail_count"
        case cleanupCancelCount = "cleanup_cancel_count"
        case cleanupLedger = "cleanup_ledger"
    }
}

struct CompletionAdapterSnapshot: Codable, Equatable {
    let schemaVersion: String
    let eventType: String
    let generatedAtMs: Int64
    let completionDetectLatencyP95Ms: Int64
    let duplicateCompletionActions: Int
    let emittedEventsCount: Int

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case eventType = "event_type"
        case generatedAtMs = "generated_at_ms"
        case completionDetectLatencyP95Ms = "completion_detect_latency_p95_ms"
        case duplicateCompletionActions = "duplicate_completion_actions"
        case emittedEventsCount = "emitted_events_count"
    }
}

/// 健康问题
struct HealthIssue: Identifiable {
    let id = UUID()
    let taskId: UUID
    let type: HealthIssueType
    let severity: Severity
    let message: String

    enum HealthIssueType {
        case timeout
        case stalled
        case blocked
        case highErrorRate
        case maxRetriesExceeded
    }

    enum Severity {
        case low
        case medium
        case high
        case critical

        var color: String {
            switch self {
            case .low: return "green"
            case .medium: return "yellow"
            case .high: return "orange"
            case .critical: return "red"
            }
        }
    }
}

/// 执行报告
struct ExecutionReport {
    let totalTasks: Int
    let completedTasks: Int
    let failedTasks: Int
    let inProgressTasks: Int
    let averageProgress: Double
    let totalErrors: Int
    let estimatedCompletion: Date?
    let generatedAt: Date

    var successRate: Double {
        guard totalTasks > 0 else { return 0.0 }
        return Double(completedTasks) / Double(totalTasks)
    }

    var failureRate: Double {
        guard totalTasks > 0 else { return 0.0 }
        return Double(failedTasks) / Double(totalTasks)
    }

    var description: String {
        var text = """
        执行报告 (\(ISO8601DateFormatter().string(from: generatedAt)))
        ==========================================
        总任务数: \(totalTasks)
        已完成: \(completedTasks)
        失败: \(failedTasks)
        进行中: \(inProgressTasks)
        平均进度: \(String(format: "%.1f%%", averageProgress * 100))
        成功率: \(String(format: "%.1f%%", successRate * 100))
        总错误数: \(totalErrors)
        """

        if let completion = estimatedCompletion {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            text += "\n预计完成时间: \(formatter.string(from: completion))"
        }

        return text
    }
}
