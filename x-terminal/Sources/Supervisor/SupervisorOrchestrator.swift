//
//  SupervisorOrchestrator.swift
//  XTerminal
//
//

import Foundation
import Combine

/// Supervisor 编排器
/// 负责智能调度和管理所有项目的执行
@MainActor
class SupervisorOrchestrator: ObservableObject {
    // MARK: - Published Properties

    @Published var resourcePool: ResourcePool
    @Published var allocationPlan: ResourceAllocationPlan?
    @Published var isScheduling: Bool = false
    @Published private(set) var splitProposalState: SplitProposalFlowState = .idle
    @Published private(set) var activeSplitProposal: SplitProposal?
    @Published private(set) var splitProposalValidation: SplitProposalValidationResult?
    @Published private(set) var promptCompilationResult: PromptCompilationResult?
    @Published private(set) var splitAuditTrail: [SplitAuditEvent] = []
    @Published private(set) var splitFlowErrorMessage: String?
    @Published private(set) var splitProposalBaseSnapshot: SplitProposal?
    @Published private(set) var splitOverrideHistory: [SplitLaneOverrideRecord] = []
    @Published private(set) var splitOverrideReplayConsistent: Bool?
    @Published private(set) var lastSplitDecomposition: DecompositionResult?
    @Published private(set) var lastMaterializationResult: MaterializationResult?
    @Published private(set) var lastLaneAllocationResult: LaneAllocationResult?
    @Published private(set) var lastLaneLaunchReport: LaneLaunchReport?
    @Published private(set) var lastMergebackGateReport: LaneMergebackGateReport?
    @Published private(set) var lastMergebackQualityReport: MergebackQualityGateReport?
    @Published private(set) var lastLaneWorktreeMergebackReport: LaneWorktreeMergebackReport?
    @Published private(set) var laneWorktreeMergebackReports: [String: LaneWorktreeMergebackReport] = [:]
    @Published private(set) var coderLaneOutputs: [String: CoderLaneOutput] = [:]
    @Published private(set) var laneReviewReports: [String: LaneReviewReport] = [:]
    @Published private(set) var lastLaneWinnerScoreReport: LaneWinnerScoreReport?
    @Published private(set) var laneWinnerSelectionOverride: LaneWinnerSelectionOverride?
    @Published private(set) var oneShotAutonomyPolicy: OneShotAutonomyPolicy?
    @Published private(set) var latestDeliveryScopeFreeze: DeliveryScopeFreeze?
    @Published private(set) var latestReplayHarnessReport: OneShotReplayReport?
    @Published private(set) var laneLaunchDecisions: [String: OneShotLaunchDecision] = [:]

    // MARK: - Private Properties

    private weak var runtimeHost: (any SupervisorProjectRuntimeHosting)?
    private let splitProposalEngine = SplitProposalEngine()
    private let promptFactory = PromptFactory()
    private let mergebackGateEvaluator = LaneMergebackGateEvaluator()
    private let mergebackQualityEvaluator = MergebackQualityGateEvaluator()
    private let mergebackRunSnapshotBuilder = MergebackRunSnapshotBuilder()
    private let autonomyPolicyEngine = OneShotAutonomyPolicyEngine()
    private let deliveryScopeFreezeStore = DeliveryScopeFreezeStore()
    private let replayHarness = OneShotReplayHarness()
    private var cancellables = Set<AnyCancellable>()

    // Phase 2: 任务分解组件
    lazy var taskDecomposer = TaskDecomposer()
    lazy var taskAssigner = TaskAssigner(runtimeHost: runtimeHost)
    lazy var executionMonitor = ExecutionMonitor(runtimeHost: runtimeHost)
    lazy var projectMaterializer = ProjectMaterializer(runtimeHost: runtimeHost)

    // MARK: - Initialization

    init(runtimeHost: any SupervisorProjectRuntimeHosting) {
        self.runtimeHost = runtimeHost
        self.resourcePool = ResourcePool()
    }

    // MARK: - Public Methods

    /// 采纳外部已准备好的 split proposal，并复用现有 confirm/execute 主链。
    @discardableResult
    func adoptPreparedSplitProposal(
        _ buildResult: SplitProposalBuildResult,
        auditDetail: String = "prepared split proposal adopted"
    ) -> SplitProposalBuildResult {
        promptCompilationResult = nil
        activeSplitProposal = buildResult.proposal
        splitProposalValidation = buildResult.validation
        splitProposalBaseSnapshot = buildResult.proposal
        splitOverrideHistory = []
        splitOverrideReplayConsistent = true
        lastSplitDecomposition = buildResult.decomposition
        clearLaneWinnerSelectionOverrideForNewPlan()

        if buildResult.validation.hasBlockingIssues {
            splitProposalState = .blocked
            splitFlowErrorMessage = "Prepared split proposal blocked: \(summarizeBlockingIssues(buildResult.validation))"
        } else {
            splitProposalState = .proposed
            splitFlowErrorMessage = nil
        }

        appendSplitAudit(
            .splitProposed,
            splitPlanId: buildResult.proposal.splitPlanId,
            detail: auditDetail,
            payload: [
                SplitAuditPayloadKeys.SplitProposed.laneCount: "\(buildResult.proposal.lanes.count)",
                SplitAuditPayloadKeys.SplitProposed.recommendedConcurrency: "\(buildResult.proposal.recommendedConcurrency)",
                SplitAuditPayloadKeys.SplitProposed.blockingIssueCount: "\(buildResult.validation.blockingIssues.count)",
                SplitAuditPayloadKeys.SplitProposed.blockingIssueCodes: buildResult.validation.blockingIssues.map { $0.code }.joined(separator: ","),
                SplitAuditPayloadKeys.Common.state: splitProposalState.rawValue
            ]
        )
        return buildResult
    }

    /// 智能调度项目
    func scheduleProjects(_ projects: [ProjectModel]) async {
        guard !isScheduling else { return }
        isScheduling = true
        defer { isScheduling = false }

        // 1. 分析优先级
        let prioritized = analyzePriority(projects)

        // 2. 分配资源
        let plan = allocateResources(prioritized)
        allocationPlan = plan

        // 3. 并行执行
        await executeParallel(plan)

        // 4. 监控和调整
        await monitorAndAdjust()
    }

    /// 分析项目优先级
    func analyzePriority(_ projects: [ProjectModel]) -> [ProjectModel] {
        return projects.sorted { p1, p2 in
            calculatePriority(p1) > calculatePriority(p2)
        }
    }

    /// 计算项目优先级分数
    func calculatePriority(_ project: ProjectModel) -> Int {
        var score = 0

        // 用户设置的优先级 (0-100)
        score += project.priority * 100

        // 状态加分
        switch project.status {
        case .blocked:
            score += 200  // 被阻塞的项目优先解决
        case .running:
            score += 50   // 运行中的项目保持优先
        default:
            break
        }

        // 依赖关系（被依赖的项目优先）
        score += project.dependents.count * 50

        // 阻塞时间（阻塞越久优先级越高）
        if project.isBlocked {
            score += Int(project.blockedDuration / 60) * 10
        }

        // A-Tier 越高，越适合持续推进并占用更少人工协调带宽。
        score += project.governanceParallelCapacity * 10

        return score
    }

    /// 分配资源
    func allocateResources(_ projects: [ProjectModel]) -> ResourceAllocationPlan {
        var plan = ResourceAllocationPlan()

        for project in projects {
            // 跳过已完成或归档的项目
            guard project.status != .completed && project.status != .archived else {
                continue
            }

            // 分析项目需求
            let complexity = analyzeComplexity(project)
            let requiresExclusive = complexity == .high || project.governancePrefersExclusiveScheduling

            // 查找最佳资源
            if let model = findBestModel(for: project, complexity: complexity) {
                let allocation = ProjectAllocation(
                    project: project,
                    model: model,
                    priority: calculatePriority(project),
                    estimatedDuration: estimateDuration(project, complexity: complexity),
                    requiresExclusive: requiresExclusive
                )

                if requiresExclusive {
                    plan.exclusiveProjects.append(allocation)
                } else {
                    plan.parallelProjects.append(allocation)
                }
            } else {
                // 没有可用资源，加入等待队列
                plan.waitingProjects.append(project)
            }
        }

        // 按优先级排序
        plan.exclusiveProjects.sort { $0.priority > $1.priority }
        plan.parallelProjects.sort { $0.priority > $1.priority }

        return plan
    }

    /// 分析任务复杂度
    func analyzeComplexity(_ project: ProjectModel) -> ProjectTaskComplexity {
        // 简化实现：根据任务描述关键词判断
        let description = project.taskDescription.lowercased()

        if description.contains("重构") || description.contains("架构") || description.contains("设计") {
            return .high
        } else if description.contains("修复") || description.contains("优化") || description.contains("改进") {
            return .medium
        } else {
            return .low
        }
    }

    /// 查找最佳模型
    func findBestModel(for project: ProjectModel, complexity: ProjectTaskComplexity) -> ModelInfo? {
        let budget = project.budget
        let usedPercentage = budget.dailyPercentage

        // 如果预算紧张（超过 80%），优先使用本地模型
        if usedPercentage > 80 {
            return resourcePool.localModels.first
        }

        // 根据复杂度选择模型
        switch complexity {
        case .high:
            // 高复杂度：使用最强模型
            if budget.dailyRemaining > 1.0 {
                return resourcePool.opusModel
            } else {
                return resourcePool.sonnetModel ?? resourcePool.localModels.first
            }

        case .medium:
            // 中等复杂度：使用平衡模型
            if budget.dailyRemaining > 0.5 {
                return resourcePool.sonnetModel
            } else {
                return resourcePool.localModels.first
            }

        case .low:
            // 低复杂度：优先使用本地模型
            return resourcePool.localModels.first ?? resourcePool.haikuModel
        }
    }

    /// 估算任务时长
    func estimateDuration(_ project: ProjectModel, complexity: ProjectTaskComplexity) -> TimeInterval {
        let baseTime: TimeInterval

        switch complexity {
        case .high:
            baseTime = 3600 * 4  // 4 小时
        case .medium:
            baseTime = 3600 * 2  // 2 小时
        case .low:
            baseTime = 3600      // 1 小时
        }

        // 根据自主性级别调整
        return baseTime * project.executionTier.schedulingDurationMultiplier
    }

    /// 并行执行
    func executeParallel(_ plan: ResourceAllocationPlan) async {
        // 先执行独占项目（串行）
        for allocation in plan.exclusiveProjects {
            await executeProject(allocation)
        }

        // 再并行执行共享项目
        await withTaskGroup(of: Void.self) { group in
            for allocation in plan.parallelProjects {
                group.addTask {
                    await self.executeProject(allocation)
                }
            }
        }
    }

    /// 执行单个项目
    func executeProject(_ allocation: ProjectAllocation) async {
        let project = allocation.project

        // 如果项目不是运行状态，先启动
        if project.status != .running {
            project.status = .running
            project.startTime = Date()
        }

        // 切换到分配的模型（如果不同）
        if project.configuredCoderModelId != allocation.model.id {
            await project.changeModel(to: allocation.model)
        }

        // 通知 Supervisor 开始执行
        await runtimeHost?.onProjectExecutionStarted(project, model: allocation.model)

        // 实际执行逻辑由 ProjectAgent 处理
        // 这里只是调度和监控
    }

    /// 监控和动态调整
    func monitorAndAdjust() async {
        // 定期检查项目状态
        // 如果发现问题，动态调整资源分配

        // 简化实现：检查是否有项目需要升级模型
        guard let plan = allocationPlan else { return }

        for allocation in plan.parallelProjects {
            let project = allocation.project

            // 如果项目遇到困难（例如：错误率高），建议升级模型
            if shouldUpgradeModel(project) {
                await suggestModelUpgrade(project)
            }
        }
    }

    /// 判断是否应该升级模型
    func shouldUpgradeModel(_ project: ProjectModel) -> Bool {
        // 简化实现：检查是否有待审批的工具调用
        return project.pendingApprovals > 3
    }

    /// 建议升级模型
    func suggestModelUpgrade(_ project: ProjectModel) async {
        // 通知 Supervisor 建议升级
        await runtimeHost?.suggestModelUpgrade(for: project)
    }

    /// 重新调度
    func reschedule(_ projects: [ProjectModel]) async {
        await scheduleProjects(projects)
    }

    /// 暂停所有执行
    func pauseAll() async {
        guard let plan = allocationPlan else { return }

        for allocation in plan.exclusiveProjects + plan.parallelProjects {
            allocation.project.pause()
        }
    }

    /// 恢复所有执行
    func resumeAll() async {
        guard let plan = allocationPlan else { return }

        for allocation in plan.exclusiveProjects + plan.parallelProjects {
            if allocation.project.status == .paused {
                allocation.project.resume()
            }
        }
    }

    // MARK: - Phase 2: 任务自动分解

    /// 处理新任务（带自动分解）
    /// - Parameter description: 任务描述
    /// - Returns: 分解结果
    func handleNewTask(_ description: String) async -> DecompositionResult {
        // 1. 分析并分解任务
        let result = await taskDecomposer.analyzeAndDecompose(description)

        // 2. 如果有子任务，执行 Hybrid 落盘 + 多泳道分配 + 启动编排
        if result.hasSubtasks {
            let anchorProject = preferredAnchorProject()
            let materialization = await projectMaterializer.materialize(
                tasks: result.subtasks,
                rootProject: anchorProject
            )
            lastMaterializationResult = materialization

            let allocation = await taskAssigner.allocateMaterializedLanes(materialization.lanes)
            lastLaneAllocationResult = allocation

            let launchReport = await launchAllocatedLanes(
                allocation: allocation,
                materialization: materialization
            )
            lastLaneLaunchReport = launchReport
        }

        return result
    }

    /// 生成拆分提案（XT-W2-09）
    @discardableResult
    func proposeSplit(
        for description: String,
        rootProjectId: UUID = UUID(),
        planVersion: Int = 1
    ) async -> SplitProposalBuildResult {
        splitProposalState = .proposing
        splitFlowErrorMessage = nil
        promptCompilationResult = nil

        let buildResult = await taskDecomposer.analyzeAndBuildSplitProposal(
            description,
            rootProjectId: rootProjectId,
            planVersion: planVersion
        )

        activeSplitProposal = buildResult.proposal
        splitProposalValidation = buildResult.validation
        splitProposalBaseSnapshot = buildResult.proposal
        splitOverrideHistory = []
        splitOverrideReplayConsistent = true
        lastSplitDecomposition = buildResult.decomposition
        clearLaneWinnerSelectionOverrideForNewPlan()

        if buildResult.validation.hasBlockingIssues {
            splitProposalState = .blocked
            splitFlowErrorMessage = "Split proposal blocked: \(summarizeBlockingIssues(buildResult.validation))"
        } else {
            splitProposalState = .proposed
        }

        appendSplitAudit(
            .splitProposed,
            splitPlanId: buildResult.proposal.splitPlanId,
            detail: "split proposal generated",
            payload: [
                SplitAuditPayloadKeys.SplitProposed.laneCount: "\(buildResult.proposal.lanes.count)",
                SplitAuditPayloadKeys.SplitProposed.recommendedConcurrency: "\(buildResult.proposal.recommendedConcurrency)",
                SplitAuditPayloadKeys.SplitProposed.blockingIssueCount: "\(buildResult.validation.blockingIssues.count)",
                SplitAuditPayloadKeys.SplitProposed.blockingIssueCodes: buildResult.validation.blockingIssues.map { $0.code }.joined(separator: ","),
                SplitAuditPayloadKeys.Common.state: splitProposalState.rawValue
            ]
        )
        return buildResult
    }

    /// 用户确认拆分提案（XT-W2-09 + XT-W2-11）
    @discardableResult
    func confirmActiveSplitProposal(globalContext: String = "") -> PromptCompilationResult? {
        guard let proposal = activeSplitProposal else {
            splitFlowErrorMessage = "No active split proposal to confirm."
            return nil
        }

        let validation = splitProposalValidation ?? splitProposalEngine.validate(proposal)
        splitProposalValidation = validation
        if validation.hasBlockingIssues {
            splitProposalState = .blocked
            splitFlowErrorMessage = "Cannot confirm split proposal: \(summarizeBlockingIssues(validation))"
            return nil
        }

        let compilation = promptFactory.compileContracts(for: proposal, globalContext: globalContext)
        promptCompilationResult = compilation

        if compilation.lintResult.hasBlockingErrors {
            splitProposalState = .blocked
            splitFlowErrorMessage = "Prompt lint blocked launch: \(summarizePromptBlockingIssues(compilation.lintResult))"
            appendSplitAudit(
                .promptRejected,
                splitPlanId: proposal.splitPlanId,
                detail: "prompt lint blocked launch",
                payload: [
                    SplitAuditPayloadKeys.PromptRejected.expectedLaneCount: "\(compilation.expectedLaneCount)",
                    SplitAuditPayloadKeys.PromptRejected.contractCount: "\(compilation.contracts.count)",
                    SplitAuditPayloadKeys.PromptRejected.blockingLintCount: "\(compilation.lintResult.blockingIssues.count)",
                    SplitAuditPayloadKeys.PromptRejected.blockingLintCodes: compilation.lintResult.blockingIssues.map { $0.code }.joined(separator: ","),
                    SplitAuditPayloadKeys.Common.state: splitProposalState.rawValue
                ]
            )
            return compilation
        }

        splitProposalState = .confirmed
        splitFlowErrorMessage = nil
        appendSplitAudit(
            .promptCompiled,
            splitPlanId: proposal.splitPlanId,
            detail: "prompt contracts compiled",
            payload: [
                SplitAuditPayloadKeys.PromptCompiled.expectedLaneCount: "\(compilation.expectedLaneCount)",
                SplitAuditPayloadKeys.PromptCompiled.contractCount: "\(compilation.contracts.count)",
                SplitAuditPayloadKeys.PromptCompiled.coverage: String(format: "%.2f", compilation.coverage),
                SplitAuditPayloadKeys.PromptCompiled.canLaunch: compilation.canLaunch ? "1" : "0",
                SplitAuditPayloadKeys.PromptCompiled.lintIssueCount: "\(compilation.lintResult.issues.count)",
                SplitAuditPayloadKeys.Common.state: splitProposalState.rawValue
            ]
        )
        appendSplitAudit(
            .splitConfirmed,
            splitPlanId: proposal.splitPlanId,
            detail: "user confirmed split proposal",
            payload: [
                SplitAuditPayloadKeys.SplitConfirmed.userDecision: "confirm",
                SplitAuditPayloadKeys.SplitConfirmed.laneCount: "\(proposal.lanes.count)",
                SplitAuditPayloadKeys.Common.state: splitProposalState.rawValue
            ]
        )
        return compilation
    }

    /// 用户拒绝拆分提案
    func rejectActiveSplitProposal(reason: String = "user_rejected") {
        guard let proposal = activeSplitProposal else {
            splitFlowErrorMessage = "No active split proposal to reject."
            return
        }
        splitProposalState = .rejected
        splitFlowErrorMessage = reason
        appendSplitAudit(
            .splitRejected,
            splitPlanId: proposal.splitPlanId,
            detail: "user rejected split proposal",
            payload: [
                SplitAuditPayloadKeys.SplitRejected.userDecision: "reject",
                SplitAuditPayloadKeys.SplitRejected.reason: reason,
                SplitAuditPayloadKeys.Common.state: splitProposalState.rawValue
            ]
        )
    }

    /// 用户局部覆盖拆分提案
    @discardableResult
    func overrideActiveSplitProposal(
        _ overrides: [SplitLaneOverride],
        reason: String = "user_override"
    ) -> SplitProposalOverrideResult? {
        guard let proposal = activeSplitProposal else {
            splitFlowErrorMessage = "No active split proposal to override."
            return nil
        }

        let overrideResult = splitProposalEngine.applyOverrides(
            overrides,
            to: proposal,
            reason: reason
        )
        activeSplitProposal = overrideResult.proposal
        splitProposalValidation = overrideResult.validation
        splitOverrideHistory.append(contentsOf: overrideResult.appliedOverrides)
        promptCompilationResult = nil

        if overrideResult.validation.hasBlockingIssues {
            splitProposalState = .blocked
            splitFlowErrorMessage = "Override introduced blocking issues: \(summarizeBlockingIssues(overrideResult.validation))"
        } else {
            splitProposalState = .overridden
            splitFlowErrorMessage = nil
        }

        appendSplitAudit(
            .splitOverridden,
            splitPlanId: overrideResult.proposal.splitPlanId,
            detail: "split proposal overridden",
            payload: buildSplitOverriddenAuditPayload(
                appliedOverrides: overrideResult.appliedOverrides,
                validation: overrideResult.validation,
                reason: reason,
                isReplay: false,
                state: splitProposalState
            )
        )
        refreshOverrideReplayConsistency()
        return overrideResult
    }

    /// 从提案基线重放全部覆盖记录（用于可回放验证）
    @discardableResult
    func replayActiveSplitProposalOverrides() -> SplitProposalOverrideResult? {
        guard let baseProposal = splitProposalBaseSnapshot else {
            splitFlowErrorMessage = "No split proposal baseline available for replay."
            return nil
        }

        let replayResult: SplitProposalOverrideResult
        if splitOverrideHistory.isEmpty {
            let validation = splitProposalEngine.validate(baseProposal)
            replayResult = SplitProposalOverrideResult(
                proposal: baseProposal,
                validation: validation,
                appliedOverrides: []
            )
        } else {
            replayResult = splitProposalEngine.replayOverrides(
                splitOverrideHistory,
                baseProposal: baseProposal
            )
        }

        activeSplitProposal = replayResult.proposal
        splitProposalValidation = replayResult.validation
        promptCompilationResult = nil
        if !replayResult.appliedOverrides.isEmpty {
            splitOverrideHistory = replayResult.appliedOverrides
        }

        if replayResult.validation.hasBlockingIssues {
            splitProposalState = .blocked
            splitFlowErrorMessage = "Override replay produced blocking issues: \(summarizeBlockingIssues(replayResult.validation))"
        } else {
            splitProposalState = replayResult.appliedOverrides.isEmpty ? .proposed : .overridden
            splitFlowErrorMessage = nil
        }

        appendSplitAudit(
            .splitOverridden,
            splitPlanId: replayResult.proposal.splitPlanId,
            detail: "split overrides replayed",
            payload: buildSplitOverriddenAuditPayload(
                appliedOverrides: splitOverrideHistory,
                validation: replayResult.validation,
                reason: "override_replay",
                isReplay: true,
                state: splitProposalState
            )
        )
        refreshOverrideReplayConsistency()
        return replayResult
    }

    /// 重置拆分提案状态
    func clearSplitProposalFlow() {
        activeSplitProposal = nil
        splitProposalValidation = nil
        promptCompilationResult = nil
        splitProposalBaseSnapshot = nil
        splitOverrideHistory = []
        splitOverrideReplayConsistent = nil
        lastSplitDecomposition = nil
        clearLaneWinnerSelectionOverrideForNewPlan()
        splitFlowErrorMessage = nil
        splitProposalState = .idle
    }

    /// 执行已确认拆分提案（XT-W2-10/12/13 主链）
    @discardableResult
    func executeActiveSplitProposal() async -> LaneLaunchReport? {
        guard let proposal = activeSplitProposal else {
            splitFlowErrorMessage = "No active split proposal to execute."
            return nil
        }

        if splitProposalValidation == nil {
            splitProposalValidation = splitProposalEngine.validate(proposal)
        }
        if splitProposalValidation?.hasBlockingIssues == true {
            splitProposalState = .blocked
            splitFlowErrorMessage = "Cannot execute split proposal: \(summarizeBlockingIssues(splitProposalValidation!))"
            return nil
        }

        if promptCompilationResult == nil || promptCompilationResult?.status != .ready {
            _ = confirmActiveSplitProposal(globalContext: proposal.sourceTaskDescription)
        }

        guard let promptCompilationResult else {
            splitProposalState = .blocked
            splitFlowErrorMessage = "Prompt contracts are required before lane launch."
            return nil
        }
        if promptCompilationResult.lintResult.hasBlockingErrors {
            splitProposalState = .blocked
            splitFlowErrorMessage = "Prompt lint blocked launch: \(summarizePromptBlockingIssues(promptCompilationResult.lintResult))"
            return nil
        }

        let anchorProject = preferredAnchorProject()
        let materialization = await projectMaterializer.materialize(
            proposal: proposal,
            decomposition: lastSplitDecomposition,
            rootProject: anchorProject
        )
        lastMaterializationResult = materialization

        let allocation = await taskAssigner.allocateMaterializedLanes(materialization.lanes)
        lastLaneAllocationResult = allocation

        let launchReport = await launchAllocatedLanes(
            allocation: allocation,
            materialization: materialization
        )
        lastLaneLaunchReport = launchReport
        splitProposalState = .confirmed
        splitFlowErrorMessage = nil
        appendSplitAudit(
            .splitConfirmed,
            splitPlanId: proposal.splitPlanId,
            detail: "lane_launch_count=\(launchReport.launchedLaneIDs.count), blocked=\(launchReport.blockedLaneReasons.count)"
        )
        return launchReport
    }

    /// 获取任务分解器
    var decomposer: TaskDecomposer {
        return taskDecomposer
    }

    /// 获取任务分配器
    var assigner: TaskAssigner {
        return taskAssigner
    }

    /// 获取执行监控器
    var monitor: ExecutionMonitor {
        return executionMonitor
    }

    /// 获取执行报告
    func getExecutionReport() -> ExecutionReport {
        return executionMonitor.generateReport()
    }

    /// 检查任务健康状态
    func checkTaskHealth() async -> [HealthIssue] {
        return await executionMonitor.checkHealth()
    }

    func oneShotRuntimeEvidenceRefs() -> [String] {
        [
            "build/reports/xt_w3_26_e_safe_auto_launch_evidence.v1.json",
            "build/reports/xt_w3_26_f_directed_unblock_evidence.v1.json",
            "build/reports/xt_w3_26_g_delivery_scope_freeze_evidence.v1.json",
            "build/reports/xt_w3_26_h_replay_regression_evidence.v1.json"
        ]
    }

    /// XT-W3-11：mergeback 前质量门禁（fail-closed）
    @discardableResult
    func evaluateMergebackReadiness(
        strictIncidentCoverage: Bool = true,
        now: Date = Date()
    ) -> LaneMergebackGateReport {
        let splitPlanID = lastLaneLaunchReport?.splitPlanID
            ?? lastMaterializationResult?.splitPlanID
            ?? activeSplitProposal?.splitPlanId.uuidString.lowercased()
            ?? "unknown"
        guard let materialization = lastMaterializationResult,
              !materialization.lanes.isEmpty else {
            let blocked = LaneMergebackGateReport(
                schemaVersion: "xterminal.mergeback_gate.v1",
                generatedAtMs: Int64((now.timeIntervalSince1970 * 1000.0).rounded()),
                splitPlanID: splitPlanID,
                pass: false,
                assertions: [
                    LaneMergebackGateAssertion(
                        id: "mergeback_materialization_ready",
                        ok: false,
                        detail: "missing materialized lanes"
                    )
                ],
                rollbackPoints: [],
                kpi: LaneMergebackKPISnapshot(
                    laneStallDetectP95Ms: 0,
                    supervisorActionLatencyP95Ms: 0,
                    highRiskLaneWithoutGrant: 0,
                    unauditedAutoResolution: 0,
                    mergebackRollbackReadyRate: 0
                )
            )
            lastMergebackGateReport = blocked
            return blocked
        }

        let report = mergebackGateEvaluator.evaluate(
            splitPlanID: splitPlanID,
            lanes: materialization.lanes,
            laneStates: executionMonitor.laneStates,
            incidents: executionMonitor.incidents,
            promptCompilationResult: promptCompilationResult,
            launchReport: lastLaneLaunchReport,
            strictIncidentCoverage: strictIncidentCoverage,
            now: now
        )
        lastMergebackGateReport = report
        return report
    }

    /// XT-W3-11：从生产态 lane/task/runtime state 构建 mergeback quality run audits。
    @discardableResult
    func evaluateMergebackQuality(
        conflicts: [AssemblyConflict] = [],
        strictIncidentCoverage: Bool = true,
        now: Date = Date()
    ) -> MergebackQualityGateReport {
        let gateReport = evaluateMergebackReadiness(
            strictIncidentCoverage: strictIncidentCoverage,
            now: now
        )
        return evaluateMergebackQuality(
            gateReport: gateReport,
            materialization: lastMaterializationResult,
            promptCompilationResult: promptCompilationResult,
            taskStates: executionMonitor.taskStates,
            laneStates: executionMonitor.laneStates,
            incidents: executionMonitor.incidents,
            conflicts: conflicts,
            now: now
        )
    }

    @discardableResult
    func evaluateMergebackQuality(
        gateReport: LaneMergebackGateReport,
        materialization: MaterializationResult?,
        promptCompilationResult: PromptCompilationResult?,
        taskStates: [UUID: TaskExecutionState],
        laneStates: [String: LaneRuntimeState],
        incidents: [SupervisorLaneIncident],
        conflicts: [AssemblyConflict] = [],
        now: Date = Date()
    ) -> MergebackQualityGateReport {
        let runs = mergebackRunSnapshotBuilder.build(
            lanes: materialization?.lanes ?? [],
            promptCompilationResult: promptCompilationResult,
            taskStates: taskStates,
            laneStates: laneStates,
            rollbackPoints: gateReport.rollbackPoints,
            incidents: incidents,
            conflicts: conflicts
        )
        let report = mergebackQualityEvaluator.evaluate(runs: runs, now: now)
        lastMergebackQualityReport = report
        return report
    }

    func exportMergebackQualityReport(
        _ report: MergebackQualityGateReport,
        to url: URL
    ) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(report)
        try SupervisorStoreWriteSupport.writeSnapshotData(data, to: url)
    }

    @discardableResult
    func recordCoderLaneOutput(
        laneID: String,
        summary: String,
        artifactRefs: [String] = [],
        auditRef: String? = nil,
        now: Date = Date()
    ) throws -> CoderLaneOutput {
        let projectRoot = try registeredGitProjectRootForLaneContract(laneID: laneID)
        let manager = LaneWorktreeManager(projectRoot: projectRoot)
        let diff = try manager.generateDiff(laneID: laneID)
        let state = try manager.loadState(laneID: laneID)
        let outputRef = coderLaneOutputRef(laneID: laneID)
        let projectID = lastLaneAllocationResult?.assignments
            .first(where: { $0.laneID == laneID })
            .map { $0.project.id.uuidString.lowercased() } ?? ""

        let output = CoderLaneOutput(
            schemaVersion: CoderLaneOutput.currentSchemaVersion,
            laneID: laneID,
            role: AXRole.coder.rawValue,
            projectID: projectID,
            changedFiles: diff.changedFiles,
            diffRef: diff.diffRef,
            diagnosticsRunIDs: state?.diagnosticsRunIDs ?? [],
            artifactRefs: normalizedRefs(artifactRefs),
            summary: summary,
            outputRef: outputRef,
            auditRef: normalizedRef(auditRef) ?? "coder_lane_output:\(safeManagedPathComponent(laneID)):\(Int64((now.timeIntervalSince1970 * 1000.0).rounded()))",
            createdAtMs: Int64((now.timeIntervalSince1970 * 1000.0).rounded())
        )
        try persistCodable(output, to: projectRoot.appendingPathComponent(outputRef))
        coderLaneOutputs[laneID] = output
        appendLaneContractAudit(
            detail: "coder_lane_output lane=\(laneID) changed_files=\(output.changedFiles.count)",
            payload: [
                "lane_id": laneID,
                "role": output.role,
                "coder_lane_output_ref": output.outputRef,
                "diff_ref": output.diffRef,
                "changed_file_count": "\(output.changedFiles.count)",
                "audit_ref": output.auditRef
            ]
        )
        return output
    }

    @discardableResult
    func recordLaneReviewReport(
        laneID: String,
        verdict: LaneReviewVerdict,
        reviewerID: String = "reviewer",
        summary: String,
        issues: [String] = [],
        recommendedActions: [String] = [],
        residualRisks: [String] = [],
        evidenceRefs: [String] = [],
        auditRef: String? = nil,
        now: Date = Date()
    ) throws -> LaneReviewReport {
        let projectRoot = try registeredGitProjectRootForLaneContract(laneID: laneID)
        guard let output = try coderLaneOutput(laneID: laneID, projectRoot: projectRoot) else {
            throw laneReviewContractFailure("missing coder lane output for \(laneID)")
        }

        let reviewRef = laneReviewReportRef(laneID: laneID)
        let mergedEvidenceRefs = normalizedRefs(evidenceRefs + [
            output.outputRef,
            output.diffRef,
        ])
        let report = LaneReviewReport(
            schemaVersion: LaneReviewReport.currentSchemaVersion,
            laneID: laneID,
            role: AXRole.reviewer.rawValue,
            reviewerID: reviewerID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "reviewer" : reviewerID,
            verdict: verdict,
            summary: summary,
            issues: normalizedStrings(issues),
            recommendedActions: normalizedStrings(recommendedActions),
            residualRisks: normalizedStrings(residualRisks),
            evidenceRefs: mergedEvidenceRefs,
            coderOutputRef: output.outputRef,
            reviewRef: reviewRef,
            auditRef: normalizedRef(auditRef) ?? "lane_review:\(safeManagedPathComponent(laneID)):\(Int64((now.timeIntervalSince1970 * 1000.0).rounded()))",
            createdAtMs: Int64((now.timeIntervalSince1970 * 1000.0).rounded())
        )
        try persistCodable(report, to: projectRoot.appendingPathComponent(reviewRef))
        laneReviewReports[laneID] = report
        appendLaneContractAudit(
            detail: "lane_review lane=\(laneID) verdict=\(verdict.rawValue)",
            payload: [
                "lane_id": laneID,
                "role": report.role,
                "reviewer_id": report.reviewerID,
                "reviewer_verdict": verdict.rawValue,
                "review_report_ref": report.reviewRef,
                "coder_lane_output_ref": report.coderOutputRef,
                "audit_ref": report.auditRef
            ]
        )
        return report
    }

    func previewLaneWinnerScoreReport() -> LaneWinnerScoreReport? {
        makeLaneWinnerScoreReport(
            auditRef: "lane_winner_score:\(activeSplitProposal?.splitPlanId.uuidString.lowercased() ?? "unknown"):preview",
            now: Date(timeIntervalSince1970: 0)
        )
    }

    @discardableResult
    func evaluateLaneWinnerScores(now: Date = Date()) -> LaneWinnerScoreReport? {
        guard let report = makeLaneWinnerScoreReport(
            auditRef: "lane_winner_score:\(activeSplitProposal?.splitPlanId.uuidString.lowercased() ?? "unknown"):\(Int64((now.timeIntervalSince1970 * 1000.0).rounded()))",
            now: now
        ) else {
            lastLaneWinnerScoreReport = nil
            return nil
        }
        lastLaneWinnerScoreReport = report
        persistLaneWinnerScoreReport(report)
        appendLaneContractAudit(
            detail: "lane_winner_score recommended=\(report.recommendedLaneID.isEmpty ? "none" : report.recommendedLaneID) eligible=\(report.eligibleCount)/\(report.candidateCount)",
            payload: [
                "split_plan_id": report.splitPlanID,
                "recommended_lane_id": report.recommendedLaneID,
                "automatic_recommended_lane_id": report.automaticRecommendedLaneID,
                "selection_source": report.selectionSource,
                "manual_override_lane_id": report.manualOverrideLaneID,
                "candidate_count": "\(report.candidateCount)",
                "eligible_count": "\(report.eligibleCount)",
                "selection_blockers": report.selectionBlockers.joined(separator: ","),
                "lane_winner_score_ref": report.reportRef,
                "audit_ref": report.auditRef
            ]
        )
        return report
    }

    @discardableResult
    func overrideLaneWinnerSelection(
        laneID rawLaneID: String,
        reason rawReason: String = "manual_lane_winner_override",
        now: Date = Date()
    ) -> LaneWinnerScoreReport? {
        let laneID = rawLaneID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !laneID.isEmpty else {
            clearLaneWinnerSelectionOverride(reason: "manual_override_empty_lane", now: now)
            return evaluateLaneWinnerScores(now: now)
        }

        let reason = rawReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "manual_lane_winner_override"
            : rawReason.trimmingCharacters(in: .whitespacesAndNewlines)
        let auditRef = "lane_winner_manual_override:\(safeManagedPathComponent(laneID)):\(Int64((now.timeIntervalSince1970 * 1000.0).rounded()))"
        laneWinnerSelectionOverride = LaneWinnerSelectionOverride(
            laneID: laneID,
            reason: reason,
            auditRef: auditRef,
            createdAtMs: Int64((now.timeIntervalSince1970 * 1000.0).rounded())
        )
        let report = evaluateLaneWinnerScores(now: now)
        appendLaneContractAudit(
            detail: "lane_winner_manual_override lane=\(laneID) source=operator selection_source=\(report?.selectionSource ?? "pending")",
            payload: [
                "lane_id": laneID,
                "reason": reason,
                "audit_ref": auditRef,
                "selection_source": report?.selectionSource ?? "",
                "selection_blockers": report?.selectionBlockers.joined(separator: ",") ?? "",
                "lane_winner_score_ref": report?.reportRef ?? "",
                "hub_first_note": "local_selection_only_mergeback_still_requires_reviewer_gate_hub_policy"
            ]
        )
        return report
    }

    func clearLaneWinnerSelectionOverride(
        reason rawReason: String = "manual_clear_lane_winner_override",
        now: Date = Date()
    ) {
        let previousLaneID = laneWinnerSelectionOverride?.laneID ?? ""
        laneWinnerSelectionOverride = nil
        lastLaneWinnerScoreReport = evaluateLaneWinnerScores(now: now)
        appendLaneContractAudit(
            detail: "lane_winner_manual_override_cleared previous=\(previousLaneID.isEmpty ? "none" : previousLaneID)",
            payload: [
                "previous_lane_id": previousLaneID,
                "reason": rawReason.trimmingCharacters(in: .whitespacesAndNewlines),
                "audit_ref": "lane_winner_manual_override_clear:\(Int64((now.timeIntervalSince1970 * 1000.0).rounded()))"
            ]
        )
    }

    /// Merge back a selected completed lane worktree into the registered project root.
    ///
    /// This is the Supervisor-level bridge between lane winner selection and the
    /// low-level worktree runner: it fail-closes on mergeback readiness, runs
    /// pre/apply/post diagnostics through `LaneWorktreeMergebackRunner`, and records
    /// the resulting audit snapshot for the cockpit/quality gate.
    @discardableResult
    func mergebackSelectedWorktreeLane(
        laneID requestedLaneID: String? = nil,
        strictIncidentCoverage: Bool = false,
        timeoutSec: Double = 120.0,
        now: Date = Date()
    ) async -> LaneWorktreeMergebackReport? {
        let winnerScoreReport = evaluateLaneWinnerScores(now: now)
        let selectedLaneID = selectedWorktreeMergebackLaneID(requestedLaneID, scoreReport: winnerScoreReport)
        guard let selectedLaneID else {
            return recordSyntheticWorktreeMergebackBlock(
                laneID: requestedLaneID ?? "unknown",
                blockedReason: "no_worktree_lane_candidate",
                detail: "no launched worktree lane is available for mergeback",
                now: now
            )
        }

        guard lastLaneLaunchReport?.worktreePaths[selectedLaneID] != nil else {
            return recordSyntheticWorktreeMergebackBlock(
                laneID: selectedLaneID,
                blockedReason: "lane_worktree_not_prepared",
                detail: "selected lane has no prepared worktree",
                now: now
            )
        }

        guard let assignment = lastLaneAllocationResult?.assignments.first(where: { $0.laneID == selectedLaneID }) else {
            return recordSyntheticWorktreeMergebackBlock(
                laneID: selectedLaneID,
                blockedReason: "lane_assignment_missing",
                detail: "selected lane has no allocation assignment",
                now: now
            )
        }

        guard let projectRoot = registeredGitProjectRoot(for: assignment.project) else {
            return recordSyntheticWorktreeMergebackBlock(
                laneID: selectedLaneID,
                blockedReason: "registered_git_project_root_missing",
                detail: "selected lane project is not bound to a registered git root",
                now: now
            )
        }

        guard ((try? coderLaneOutput(laneID: selectedLaneID, projectRoot: projectRoot)) ?? nil) != nil else {
            return recordSyntheticWorktreeMergebackBlock(
                laneID: selectedLaneID,
                blockedReason: "coder_lane_output_missing",
                detail: "selected lane has no CoderLaneOutput; mergeback requires coder evidence before reviewer approval",
                now: now
            )
        }

        guard let reviewReport = (try? laneReviewReport(laneID: selectedLaneID, projectRoot: projectRoot)) ?? nil else {
            return recordSyntheticWorktreeMergebackBlock(
                laneID: selectedLaneID,
                blockedReason: "reviewer_verdict_missing",
                detail: "selected lane has no LaneReviewReport; mergeback requires Reviewer verdict",
                now: now
            )
        }

        guard reviewReport.verdict.allowsMergeback else {
            return recordSyntheticWorktreeMergebackBlock(
                laneID: selectedLaneID,
                blockedReason: "reviewer_verdict_not_approved",
                detail: "reviewer verdict \(reviewReport.verdict.rawValue) does not allow mergeback",
                now: now
            )
        }

        let gateReport = evaluateMergebackReadiness(
            strictIncidentCoverage: strictIncidentCoverage,
            now: now
        )
        guard gateReport.pass else {
            let blockedAssertions = gateReport.assertions
                .filter { !$0.ok }
                .map(\.id)
                .joined(separator: ",")
            return recordSyntheticWorktreeMergebackBlock(
                laneID: selectedLaneID,
                blockedReason: "mergeback_gate_failed",
                detail: blockedAssertions.isEmpty ? "mergeback readiness gate failed" : blockedAssertions,
                gateReport: gateReport,
                now: now
            )
        }

        do {
            let report = try LaneWorktreeMergebackRunner().mergeback(
                laneID: selectedLaneID,
                projectRoot: projectRoot,
                timeoutSec: timeoutSec
            )
            recordWorktreeMergebackReport(report, gateReport: gateReport, now: now)
            return report
        } catch {
            return recordSyntheticWorktreeMergebackBlock(
                laneID: selectedLaneID,
                blockedReason: "mergeback_runner_error",
                detail: error.localizedDescription,
                gateReport: gateReport,
                now: now
            )
        }
    }

    // MARK: - Lane launcher (XT-W2-12)

    private func launchAllocatedLanes(
        allocation: LaneAllocationResult,
        materialization: MaterializationResult
    ) async -> LaneLaunchReport {
        let laneByID = Dictionary(uniqueKeysWithValues: materialization.lanes.map { ($0.plan.laneID, $0) })
        let sortedAssignments = orderedAssignments(
            allocation.assignments,
            laneByID: laneByID
        )

        var startedLaneIDs: [String] = []
        var blockedLaneReasons: [String: String] = [:]
        var deferredLaneIDs: [String] = []
        var worktreeStateRefs: [String: String] = [:]
        var worktreePaths: [String: String] = [:]
        var startedCount = 0
        let concurrencyLimit = materialization.recommendedConcurrency
        executionMonitor.configureLaneLaunchPolicy(concurrencyLimit: concurrencyLimit)

        let launchNow = Date()
        let anchorProject = sortedAssignments.first?.project ?? preferredAnchorProject()
        var runtimePolicy: OneShotAutonomyPolicy?
        if let anchorProject {
            let policy = autonomyPolicyEngine.buildPolicy(
                project: anchorProject,
                lanes: materialization.lanes,
                splitPlanID: materialization.splitPlanID,
                workMode: SupervisorManager.shared.currentSupervisorWorkMode,
                now: launchNow
            )
            oneShotAutonomyPolicy = policy
            runtimePolicy = policy

            let scopeFreeze = deliveryScopeFreezeStore.freeze(
                projectID: anchorProject.id,
                runID: materialization.splitPlanID,
                requestedScope: DeliveryScopeFreezeStore.defaultValidatedScope,
                auditRef: policy.auditRef
            )
            latestDeliveryScopeFreeze = scopeFreeze
            latestReplayHarnessReport = replayHarness.run(
                policy: policy,
                freeze: scopeFreeze,
                now: launchNow
            )
        } else {
            oneShotAutonomyPolicy = nil
            latestDeliveryScopeFreeze = nil
            latestReplayHarnessReport = nil
        }

        var launchDecisions: [String: OneShotLaunchDecision] = [:]

        for assignment in sortedAssignments {
            guard let lane = laneByID[assignment.laneID] else { continue }
            var task = lane.task

            if let runtimePolicy, let latestDeliveryScopeFreeze {
                task = autonomyPolicyEngine.attachRuntimeContracts(
                    to: task,
                    lane: lane,
                    policy: runtimePolicy,
                    scopeFreeze: latestDeliveryScopeFreeze
                )
            }

            task.metadata["lane_id"] = assignment.laneID
            task.metadata["agent_profile"] = assignment.agentProfile
            task.metadata["assignment_explain"] = assignment.explain
            task.metadata["assignment_risk_fit"] = String(format: "%.2f", assignment.factors.riskFit)
            task.metadata["assignment_budget_fit"] = String(format: "%.2f", assignment.factors.budgetFit)
            task.metadata["assignment_load_fit"] = String(format: "%.2f", assignment.factors.loadFit)
            task.metadata["assignment_skill_fit"] = String(format: "%.2f", assignment.factors.skillFit)
            task.metadata["assignment_reliability_fit"] = String(format: "%.2f", assignment.factors.reliabilityFit)
            task.metadata["assignment_total_score"] = String(format: "%.2f", assignment.factors.total)
            task.metadata["depends_on"] = lane.plan.dependsOn.joined(separator: ",")
            let agentMode = laneAgentMode(for: lane, task: task, agentProfile: assignment.agentProfile)
            task.metadata["agent_mode"] = agentMode.rawValue

            let worktreePreparation = prepareLaneWorktreeIfEligible(
                laneID: assignment.laneID,
                splitPlanID: materialization.splitPlanID,
                project: assignment.project,
                mode: agentMode
            )
            if let prepared = worktreePreparation.state {
                task.metadata["lane_worktree_path"] = prepared.worktreePath
                task.metadata["lane_worktree_branch"] = prepared.branch
                task.metadata["lane_worktree_state_ref"] = worktreePreparation.stateRef ?? ""
                task.metadata["lane_worktree_status"] = prepared.status.rawValue
                if let stateRef = worktreePreparation.stateRef {
                    worktreeStateRefs[assignment.laneID] = stateRef
                }
                worktreePaths[assignment.laneID] = prepared.worktreePath
            } else if let skipReason = worktreePreparation.skipReason {
                task.metadata["lane_worktree_status"] = "skipped"
                task.metadata["lane_worktree_skip_reason"] = skipReason
            } else if let failure = worktreePreparation.failureReason {
                task.metadata["lane_worktree_status"] = "failed"
                task.metadata["lane_worktree_error"] = failure
                let assignedTask = await taskAssigner.assignTask(task, to: assignment.project)
                blockedLaneReasons[assignment.laneID] = "worktree_prepare_failed:\(failure)"
                await executionMonitor.startMonitoring(
                    assignedTask,
                    in: assignment.project,
                    laneID: assignment.laneID,
                    agentProfile: assignment.agentProfile,
                    initialStatus: .blocked,
                    blockedReason: .runtimeError
                )
                continue
            }

            let assignedTask = await taskAssigner.assignTask(task, to: assignment.project)
            let dependenciesReady = Set(lane.plan.dependsOn).isSubset(of: executionMonitor.completedLaneIDs)

            if !dependenciesReady {
                blockedLaneReasons[assignment.laneID] = "dependency_not_ready"
                await executionMonitor.startMonitoring(
                    assignedTask,
                    in: assignment.project,
                    laneID: assignment.laneID,
                    agentProfile: assignment.agentProfile,
                    initialStatus: .blocked,
                    blockedReason: .dependencyBlocked
                )
                continue
            }

            if startedCount >= concurrencyLimit {
                deferredLaneIDs.append(assignment.laneID)
                blockedLaneReasons[assignment.laneID] = "launch_queue_waiting"
                await executionMonitor.startMonitoring(
                    assignedTask,
                    in: assignment.project,
                    laneID: assignment.laneID,
                    agentProfile: assignment.agentProfile,
                    initialStatus: .blocked,
                    blockedReason: .queueStarvation
                )
                continue
            }

            if let runtimePolicy, let latestDeliveryScopeFreeze {
                let decision = autonomyPolicyEngine.evaluateLaunch(
                    policy: runtimePolicy,
                    lane: lane,
                    project: assignment.project,
                    scopeFreeze: latestDeliveryScopeFreeze
                )
                launchDecisions[assignment.laneID] = decision
                task.metadata["one_shot_launch_decision"] = decision.decision.rawValue
                task.metadata["deny_code"] = decision.denyCode
                task.metadata["runtime_guard_note"] = decision.note

                if decision.autoLaunchAllowed == false {
                    blockedLaneReasons[assignment.laneID] = decision.denyCode
                    await executionMonitor.startMonitoring(
                        assignedTaskWithRuntimeMetadata(from: assignedTask, taskMetadata: task.metadata),
                        in: assignment.project,
                        laneID: assignment.laneID,
                        agentProfile: assignment.agentProfile,
                        initialStatus: .blocked,
                        blockedReason: decision.blockedReason ?? .awaitingInstruction
                    )
                    continue
                }
            }

            startedCount += 1
            startedLaneIDs.append(assignment.laneID)
            await executionMonitor.startMonitoring(
                assignedTaskWithRuntimeMetadata(from: assignedTask, taskMetadata: task.metadata),
                in: assignment.project,
                laneID: assignment.laneID,
                agentProfile: assignment.agentProfile,
                initialStatus: .running,
                blockedReason: nil
            )
        }

        for blocked in allocation.blockedLanes {
            let blockedExplain = blocked.explain.trimmingCharacters(in: .whitespacesAndNewlines)
            blockedLaneReasons[blocked.laneID] = blockedExplain.isEmpty ? blocked.reason : blockedExplain
            executionMonitor.registerUnassignedLane(
                task: blocked.task,
                laneID: blocked.laneID,
                reason: blockedReasonFromAllocationReason("\(blocked.reason),\(blocked.explain)"),
                note: blockedExplain.isEmpty ? blocked.reason : blockedExplain
            )
        }

        laneLaunchDecisions = launchDecisions

        return LaneLaunchReport(
            splitPlanID: materialization.splitPlanID,
            launchedLaneIDs: startedLaneIDs,
            blockedLaneReasons: blockedLaneReasons,
            deferredLaneIDs: deferredLaneIDs,
            concurrencyLimit: concurrencyLimit,
            reproducibilitySignature: allocation.reproducibilitySignature,
            worktreeStateRefs: worktreeStateRefs,
            worktreePaths: worktreePaths
        )
    }

    private struct LaneWorktreePreparation {
        let state: LaneWorktreeState?
        let stateRef: String?
        let skipReason: String?
        let failureReason: String?

        static func prepared(_ state: LaneWorktreeState, stateRef: String) -> LaneWorktreePreparation {
            LaneWorktreePreparation(state: state, stateRef: stateRef, skipReason: nil, failureReason: nil)
        }

        static func skipped(_ reason: String) -> LaneWorktreePreparation {
            LaneWorktreePreparation(state: nil, stateRef: nil, skipReason: reason, failureReason: nil)
        }

        static func failed(_ reason: String) -> LaneWorktreePreparation {
            LaneWorktreePreparation(state: nil, stateRef: nil, skipReason: nil, failureReason: reason)
        }
    }

    private func prepareLaneWorktreeIfEligible(
        laneID: String,
        splitPlanID: String,
        project: ProjectModel,
        mode: XTAgentMode
    ) -> LaneWorktreePreparation {
        guard mode == .code || mode == .debug else {
            return .skipped("mode_\(mode.rawValue)_does_not_require_worktree")
        }

        guard let projectRoot = registeredGitProjectRoot(for: project) else {
            return .skipped("registered_git_project_root_missing")
        }

        do {
            let manager = LaneWorktreeManager(projectRoot: projectRoot)
            let state = try manager.prepareLaneWorktree(
                laneID: laneID,
                sessionID: splitPlanID,
                mode: mode
            )
            return .prepared(state, stateRef: relativePath(of: manager.stateFileURL(laneID: laneID), under: projectRoot))
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    private func registeredGitProjectRoot(for project: ProjectModel) -> URL? {
        let rootPath = (project.registeredProjectRootPath ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rootPath.isEmpty else { return nil }

        let root = URL(fileURLWithPath: rootPath, isDirectory: true).standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return nil
        }

        guard (try? ProcessCapture.run(
            "/usr/bin/git",
            ["rev-parse", "--is-inside-work-tree"],
            cwd: root,
            timeoutSec: 5.0
        )).map({ result in
            result.exitCode == 0
                && result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "true"
        }) == true else {
            return nil
        }

        return root
    }

    private func laneAgentMode(
        for lane: MaterializedLane,
        task: DecomposedTask,
        agentProfile: String
    ) -> XTAgentMode {
        if let explicit = XTAgentMode.parse(task.metadata["agent_mode"] ?? task.metadata["xt_agent_mode"]) {
            return explicit
        }
        let profile = agentProfile.lowercased()
        if profile.contains("debug") {
            return .debug
        }
        switch task.type {
        case .bugfix, .testing, .review:
            return .debug
        case .planning:
            return .plan
        case .research:
            return .explore
        case .development, .refactoring, .deployment:
            return .code
        case .documentation, .design:
            return lane.plan.riskTier >= .high ? .code : .explore
        }
    }

    private func relativePath(of url: URL, under root: URL) -> String {
        let path = url.standardizedFileURL.path
        let rootPath = root.standardizedFileURL.path
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard path.hasPrefix(prefix) else { return path }
        return String(path.dropFirst(prefix.count))
    }

    private func registeredGitProjectRootForLaneContract(laneID: String) throws -> URL {
        guard let assignment = lastLaneAllocationResult?.assignments.first(where: { $0.laneID == laneID }) else {
            throw laneReviewContractFailure("lane assignment missing for \(laneID)")
        }
        guard let root = registeredGitProjectRoot(for: assignment.project) else {
            throw laneReviewContractFailure("registered git project root missing for \(laneID)")
        }
        return root
    }

    private func coderLaneOutput(laneID: String, projectRoot: URL) throws -> CoderLaneOutput? {
        if let output = coderLaneOutputs[laneID] {
            return output
        }
        let url = projectRoot.appendingPathComponent(coderLaneOutputRef(laneID: laneID))
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let output = try JSONDecoder().decode(CoderLaneOutput.self, from: Data(contentsOf: url))
        coderLaneOutputs[laneID] = output
        return output
    }

    private func laneReviewReport(laneID: String, projectRoot: URL) throws -> LaneReviewReport? {
        if let report = laneReviewReports[laneID] {
            return report
        }
        let url = projectRoot.appendingPathComponent(laneReviewReportRef(laneID: laneID))
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let report = try JSONDecoder().decode(LaneReviewReport.self, from: Data(contentsOf: url))
        laneReviewReports[laneID] = report
        return report
    }

    private func coderLaneOutputRef(laneID: String) -> String {
        ".xterminal/lane-output/\(safeManagedPathComponent(laneID)).json"
    }

    private func laneReviewReportRef(laneID: String) -> String {
        ".xterminal/lane-review/\(safeManagedPathComponent(laneID)).json"
    }

    private func laneWinnerScoreReportRef(splitPlanID: String) -> String {
        ".xterminal/lane-winner/\(safeManagedPathComponent(splitPlanID)).json"
    }

    private func makeLaneWinnerScoreReport(auditRef: String, now: Date) -> LaneWinnerScoreReport? {
        guard let launchReport = lastLaneLaunchReport else { return nil }
        let completedLaneIDs = Set(
            executionMonitor.laneStates.values
                .filter { $0.status == .completed }
                .map(\.laneID)
        )
        let lanePlansByID = Dictionary(
            uniqueKeysWithValues: (lastMaterializationResult?.lanes ?? []).map { ($0.plan.laneID, $0.plan) }
        )
        let createdAtMs = Int64((now.timeIntervalSince1970 * 1000.0).rounded())
        let reportRef = laneWinnerScoreReportRef(splitPlanID: launchReport.splitPlanID)
        return LaneWinnerScorer.score(
            input: LaneWinnerScoringInput(
                splitPlanID: launchReport.splitPlanID,
                launchedLaneIDs: launchReport.launchedLaneIDs,
                worktreeLaneIDs: Set(launchReport.worktreePaths.keys),
                completedLaneIDs: completedLaneIDs,
                lanePlansByID: lanePlansByID,
                laneLaunchDecisions: laneLaunchDecisions,
                coderLaneOutputs: coderLaneOutputs,
                laneReviewReports: laneReviewReports,
                laneWorktreeMergebackReports: laneWorktreeMergebackReports,
                manualOverrideLaneID: laneWinnerSelectionOverride?.laneID ?? "",
                manualOverrideReason: laneWinnerSelectionOverride?.reason ?? "",
                reportRef: reportRef,
                auditRef: auditRef,
                createdAtMs: createdAtMs
            )
        )
    }

    private func persistLaneWinnerScoreReport(_ report: LaneWinnerScoreReport) {
        guard let projectRoot = firstRegisteredGitProjectRootForLaneWinnerReport() else { return }
        try? persistCodable(report, to: projectRoot.appendingPathComponent(report.reportRef))
    }

    private func firstRegisteredGitProjectRootForLaneWinnerReport() -> URL? {
        for assignment in lastLaneAllocationResult?.assignments ?? [] {
            if let root = registeredGitProjectRoot(for: assignment.project) {
                return root
            }
        }
        return nil
    }

    private func persistCodable<T: Encodable>(_ value: T, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(value).write(to: url, options: .atomic)
    }

    private func normalizedRefs(_ refs: [String]) -> [String] {
        normalizedStrings(refs)
    }

    private func normalizedStrings(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for value in values {
            guard let normalized = normalizedRef(value), !seen.contains(normalized) else { continue }
            seen.insert(normalized)
            out.append(normalized)
        }
        return out
    }

    private func normalizedRef(_ ref: String?) -> String? {
        let trimmed = (ref ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func appendLaneContractAudit(detail: String, payload: [String: String]) {
        guard let splitPlanID = activeSplitProposal?.splitPlanId else { return }
        appendSplitAudit(
            .splitConfirmed,
            splitPlanId: splitPlanID,
            detail: detail,
            payload: payload.merging([
                SplitAuditPayloadKeys.Common.state: splitProposalState.rawValue
            ]) { _, new in new }
        )
    }

    private func selectedWorktreeMergebackLaneID(
        _ requestedLaneID: String?,
        scoreReport: LaneWinnerScoreReport?
    ) -> String? {
        let requested = requestedLaneID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !requested.isEmpty {
            return requested
        }

        guard let launchReport = lastLaneLaunchReport else { return nil }
        if let overrideLaneID = laneWinnerSelectionOverride?.laneID,
           !overrideLaneID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return overrideLaneID
        }
        if let recommended = scoreReport?.recommendedLaneID,
           !recommended.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return recommended
        }

        let worktreeLaneIDs = Set(launchReport.worktreePaths.keys)
        let completedLaneIDs = Set(
            executionMonitor.laneStates.values
                .filter { $0.status == .completed }
                .map(\.laneID)
        )

        if let reviewed = launchReport.launchedLaneIDs.first(where: {
            worktreeLaneIDs.contains($0)
                && completedLaneIDs.contains($0)
                && (laneReviewReports[$0]?.verdict.allowsMergeback == true)
        }) {
            return reviewed
        }

        if let completed = launchReport.launchedLaneIDs.first(where: {
            worktreeLaneIDs.contains($0) && completedLaneIDs.contains($0)
        }) {
            return completed
        }
        return launchReport.launchedLaneIDs.first(where: { worktreeLaneIDs.contains($0) })
    }

    private func clearLaneWinnerSelectionOverrideForNewPlan() {
        laneWinnerSelectionOverride = nil
        lastLaneWinnerScoreReport = nil
    }

    private func recordSyntheticWorktreeMergebackBlock(
        laneID: String,
        blockedReason: String,
        detail: String,
        gateReport: LaneMergebackGateReport? = nil,
        now: Date
    ) -> LaneWorktreeMergebackReport {
        let report = LaneWorktreeMergebackReport(
            schemaVersion: "xt.lane_worktree_mergeback.v1",
            laneID: laneID,
            pass: false,
            preMergeOK: false,
            applyOK: false,
            postMergeOK: false,
            rollbackAttempted: false,
            rollbackOK: false,
            diffRef: "",
            changedFiles: [],
            preMergeRunID: "",
            postMergeRunID: "",
            blockedReason: blockedReason,
            reportRef: ".xterminal/mergeback/\(safeManagedPathComponent(laneID)).json",
            applyOutput: detail,
            rollbackOutput: "",
            conflictTriage: []
        )
        splitFlowErrorMessage = "Worktree mergeback blocked: \(blockedReason)"
        recordWorktreeMergebackReport(report, gateReport: gateReport, now: now)
        return report
    }

    private func recordWorktreeMergebackReport(
        _ report: LaneWorktreeMergebackReport,
        gateReport: LaneMergebackGateReport?,
        now: Date
    ) {
        lastLaneWorktreeMergebackReport = report
        laneWorktreeMergebackReports[report.laneID] = report
        if report.pass {
            splitFlowErrorMessage = nil
        } else if splitFlowErrorMessage == nil {
            splitFlowErrorMessage = "Worktree mergeback blocked: \(report.blockedReason)"
        }

        if let gateReport {
            lastMergebackQualityReport = mergebackQualityEvaluator.evaluate(
                runs: [mergebackRunSnapshot(from: report, gateReport: gateReport)],
                now: now
            )
        }

        if let splitPlanID = activeSplitProposal?.splitPlanId {
            let coderOutput = coderLaneOutputs[report.laneID]
            let reviewReport = laneReviewReports[report.laneID]
            appendSplitAudit(
                .splitConfirmed,
                splitPlanId: splitPlanID,
                detail: "worktree_mergeback lane=\(report.laneID) pass=\(report.pass) reason=\(report.blockedReason)",
                payload: [
                    SplitAuditPayloadKeys.Common.state: splitProposalState.rawValue,
                    SplitAuditPayloadKeys.SplitConfirmed.userDecision: "mergeback",
                    SplitAuditPayloadKeys.SplitConfirmed.laneCount: "1",
                    "lane_id": report.laneID,
                    "mergeback_pass": report.pass ? "1" : "0",
                    "mergeback_blocked_reason": report.blockedReason,
                    "mergeback_report_ref": report.reportRef,
                    "mergeback_diff_ref": report.diffRef,
                    "coder_lane_output_ref": coderOutput?.outputRef ?? "",
                    "reviewer_verdict": reviewReport?.verdict.rawValue ?? "",
                    "review_report_ref": reviewReport?.reviewRef ?? ""
                ]
            )
        }
    }

    private func mergebackRunSnapshot(
        from report: LaneWorktreeMergebackReport,
        gateReport: LaneMergebackGateReport
    ) -> MergebackRunSnapshot {
        let rollbackPoint = gateReport.rollbackPoints.first { $0.laneID == report.laneID }
        let stablePointID = rollbackPoint?.stablePointID ?? "lane-\(safeManagedPathComponent(report.laneID))-stable"
        let poolID = lastLaneAllocationResult?.assignments
            .first(where: { $0.laneID == report.laneID })
            .map { "project-\($0.project.id.uuidString.lowercased())" }
            ?? "pool-default"
        let conflictRecords = report.conflictTriage.map { triage in
            MergebackConflictTriageRecord(
                id: triage.id,
                laneID: triage.laneID,
                poolID: poolID,
                kind: .structural,
                routeTarget: .pool,
                autoTriaged: true,
                fixSuggestion: triage.fixSuggestion
            )
        }
        let rolledBackToStablePoint = report.rollbackAttempted
            ? report.rollbackOK
            : (!report.pass && !report.applyOK)

        return MergebackRunSnapshot(
            runID: firstNonEmpty(
                report.postMergeRunID,
                report.preMergeRunID,
                "worktree-mergeback-\(report.laneID)"
            ) ?? "worktree-mergeback-\(report.laneID)",
            laneID: report.laneID,
            poolID: poolID,
            precheckPassed: report.preMergeOK,
            mergeSucceeded: report.applyOK,
            verifyPassed: report.postMergeOK,
            committed: report.pass,
            stablePointID: stablePointID,
            rollbackAnchorID: "rollback-anchor-for-\(stablePointID)",
            qualityGateBlockedOnFailure: !report.pass,
            rolledBackToStablePoint: rolledBackToStablePoint,
            conflicts: conflictRecords
        )
    }

    private func laneReviewContractFailure(_ message: String) -> NSError {
        NSError(
            domain: "xterminal.lane_review_contract",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }

    private func safeManagedPathComponent(_ raw: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let scalars = raw.unicodeScalars.map { scalar -> Character in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        let collapsed = String(scalars)
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: ".-_"))
        return collapsed.isEmpty ? "lane" : collapsed
    }

    private func firstNonEmpty(_ values: String?...) -> String? {
        for value in values {
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return nil
    }

    private func assignedTaskWithRuntimeMetadata(
        from assignedTask: DecomposedTask,
        taskMetadata: [String: String]
    ) -> DecomposedTask {
        var updated = assignedTask
        for (key, value) in taskMetadata where !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            updated.metadata[key] = value
        }
        return updated
    }

    private func orderedAssignments(
        _ assignments: [LaneAssignment],
        laneByID: [String: MaterializedLane]
    ) -> [LaneAssignment] {
        guard assignments.count > 1 else { return assignments }

        let assignmentByLaneID = Dictionary(uniqueKeysWithValues: assignments.map { ($0.laneID, $0) })
        let laneIDs = Set(assignments.map { $0.laneID })
        var inDegree: [String: Int] = [:]
        var adjacency: [String: [String]] = [:]

        for laneID in laneIDs {
            inDegree[laneID] = 0
            adjacency[laneID] = []
        }

        for laneID in laneIDs {
            let dependencies = laneByID[laneID]?.plan.dependsOn.filter { laneIDs.contains($0) } ?? []
            inDegree[laneID, default: 0] += dependencies.count
            for dependency in dependencies {
                adjacency[dependency, default: []].append(laneID)
            }
        }

        var queue = Array(laneIDs.filter { inDegree[$0, default: 0] == 0 })
        var ordered: [LaneAssignment] = []

        while !queue.isEmpty {
            queue.sort { lhs, rhs in
                guard let left = assignmentByLaneID[lhs], let right = assignmentByLaneID[rhs] else {
                    return lhs < rhs
                }
                let leftPriority = laneLaunchPriority(left, laneByID: laneByID)
                let rightPriority = laneLaunchPriority(right, laneByID: laneByID)
                if leftPriority != rightPriority {
                    return leftPriority > rightPriority
                }
                return lhs < rhs
            }

            let laneID = queue.removeFirst()
            guard let assignment = assignmentByLaneID[laneID] else { continue }
            ordered.append(assignment)

            for child in adjacency[laneID] ?? [] {
                let next = max(0, (inDegree[child] ?? 0) - 1)
                inDegree[child] = next
                if next == 0 {
                    queue.append(child)
                }
            }
        }

        if ordered.count == assignments.count {
            return ordered
        }

        let orderedIDs = Set(ordered.map { $0.laneID })
        let residual = assignments
            .filter { !orderedIDs.contains($0.laneID) }
            .sorted { lhs, rhs in
                let leftPriority = laneLaunchPriority(lhs, laneByID: laneByID)
                let rightPriority = laneLaunchPriority(rhs, laneByID: laneByID)
                if leftPriority != rightPriority {
                    return leftPriority > rightPriority
                }
                return lhs.laneID < rhs.laneID
            }
        return ordered + residual
    }

    private func laneLaunchPriority(_ assignment: LaneAssignment, laneByID: [String: MaterializedLane]) -> Int {
        let lane = laneByID[assignment.laneID]
        let riskScore: Int
        switch lane?.plan.riskTier ?? .medium {
        case .critical: riskScore = 400
        case .high: riskScore = 300
        case .medium: riskScore = 200
        case .low: riskScore = 100
        }
        let dependencyScore = 100 - min(80, (lane?.plan.dependsOn.count ?? 0) * 20)
        return riskScore + assignment.task.priority * 10 + dependencyScore
    }

    private func blockedReasonFromAllocationReason(_ reason: String) -> LaneBlockedReason {
        if reason.contains("skill_profile_mismatch") {
            return .skillPreflightFailed
        }
        if reason.contains("risk_profile_mismatch") || reason.contains("authz_denied") {
            return .authzDenied
        }
        if reason.contains("reliability_history_insufficient") {
            return .runtimeError
        }
        if reason.contains("budget_exhausted") {
            return .quotaExceeded
        }
        return .unknown
    }

    private func preferredAnchorProject() -> ProjectModel? {
        let candidates = runtimeHost?.activeProjects.filter { $0.status == .running || $0.status == .pending } ?? []
        guard !candidates.isEmpty else { return nil }

        return candidates.sorted { lhs, rhs in
            let left = anchorProjectRank(lhs)
            let right = anchorProjectRank(rhs)
            if left != right {
                return left > right
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }.first
    }

    private func anchorProjectRank(_ project: ProjectModel) -> Int {
        var rank = 0
        if project.status == .running {
            rank += 300
        } else if project.status == .pending {
            rank += 200
        }

        if project.name == "Root" {
            rank += 80
        }

        let childDepth = laneChildDepth(for: project.name)
        rank += max(0, 60 - childDepth * 20)
        return rank
    }

    private func laneChildDepth(for projectName: String) -> Int {
        let parts = projectName
            .split(separator: "·")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        guard parts.count > 1 else { return 0 }

        return parts.dropFirst().reduce(0) { partial, part in
            part.hasPrefix("lane-") ? partial + 1 : partial
        }
    }

    // MARK: - Split helpers

    private func appendSplitAudit(
        _ eventType: SplitAuditEventType,
        splitPlanId: UUID,
        detail: String,
        payload: [String: String] = [:]
    ) {
        var envelopePayload = payload
        envelopePayload[SplitAuditPayloadKeys.Common.schema] = SplitAuditPayloadContract.schema
        envelopePayload[SplitAuditPayloadKeys.Common.version] = SplitAuditPayloadContract.version
        envelopePayload[SplitAuditPayloadKeys.Common.eventType] = eventType.rawValue

        splitAuditTrail.append(
            SplitAuditEvent(
                eventType: eventType,
                splitPlanId: splitPlanId,
                detail: detail,
                payload: envelopePayload
            )
        )
        if splitAuditTrail.count > 120 {
            splitAuditTrail.removeFirst(splitAuditTrail.count - 120)
        }
    }

    private func summarizeBlockingIssues(_ validation: SplitProposalValidationResult) -> String {
        let codes = validation.blockingIssues.map { $0.code }
        if codes.isEmpty {
            return "unknown"
        }
        return codes.joined(separator: ",")
    }

    private func summarizePromptBlockingIssues(_ lint: PromptLintResult) -> String {
        let codes = lint.blockingIssues.map { $0.code }
        if codes.isEmpty {
            return "unknown"
        }
        return codes.joined(separator: ",")
    }

    private func buildSplitOverriddenAuditPayload(
        appliedOverrides: [SplitLaneOverrideRecord],
        validation: SplitProposalValidationResult,
        reason: String,
        isReplay: Bool,
        state: SplitProposalFlowState
    ) -> [String: String] {
        let overrideLaneIDs = appliedOverrides.map(\.laneId)
        let blockingIssueCodes = validation.blockingIssues.map(\.code)
        let highRiskConfirmedLaneIDs = Set(
            appliedOverrides
                .filter { record in
                    record.override.confirmHighRiskHardToSoft == true &&
                    record.before.createChildProject &&
                    record.after.createChildProject == false &&
                    record.after.riskTier >= .high
                }
                .map(\.laneId)
        )
        .sorted()

        return [
            SplitAuditPayloadKeys.SplitOverridden.overrideCount: "\(appliedOverrides.count)",
            SplitAuditPayloadKeys.SplitOverridden.overrideLaneIDs: overrideLaneIDs.joined(separator: ","),
            SplitAuditPayloadKeys.SplitOverridden.reason: reason,
            SplitAuditPayloadKeys.SplitOverridden.blockingIssueCount: "\(blockingIssueCodes.count)",
            SplitAuditPayloadKeys.SplitOverridden.blockingIssueCodes: blockingIssueCodes.joined(separator: ","),
            SplitAuditPayloadKeys.SplitOverridden.highRiskHardToSoftConfirmedCount: "\(highRiskConfirmedLaneIDs.count)",
            SplitAuditPayloadKeys.SplitOverridden.highRiskHardToSoftConfirmedLaneIDs: highRiskConfirmedLaneIDs.joined(separator: ","),
            SplitAuditPayloadKeys.SplitOverridden.isReplay: isReplay ? "1" : "0",
            SplitAuditPayloadKeys.Common.state: state.rawValue
        ]
    }

    private func refreshOverrideReplayConsistency() {
        guard let baseProposal = splitProposalBaseSnapshot,
              let activeSplitProposal else {
            splitOverrideReplayConsistent = nil
            return
        }

        guard !splitOverrideHistory.isEmpty else {
            splitOverrideReplayConsistent = (baseProposal == activeSplitProposal)
            return
        }

        let replayed = splitProposalEngine.replayOverrides(
            splitOverrideHistory,
            baseProposal: baseProposal
        )
        splitOverrideReplayConsistent = (replayed.proposal == activeSplitProposal)
        if splitOverrideReplayConsistent == false, splitFlowErrorMessage == nil {
            splitFlowErrorMessage = "Override replay mismatch detected; please review lane overrides."
        }
    }
}

// MARK: - Supporting Types

/// 资源池
struct ResourcePool {
    var opusModel: ModelInfo?
    var sonnetModel: ModelInfo?
    var haikuModel: ModelInfo?
    var localModels: [ModelInfo] = []

    var availableResources: [ModelInfo] {
        [opusModel, sonnetModel, haikuModel].compactMap { $0 } + localModels
    }

    init() {
        // 初始化默认模型
        opusModel = ModelInfo(
            id: "claude-opus-4.6",
            name: "claude-opus-4.6",
            displayName: "claude-opus-4.6",
            type: .hubPaid,
            capability: .expert,
            speed: .medium,
            costPerMillionTokens: 15.0,
            memorySize: nil,
            suitableFor: ["复杂任务", "深度推理"],
            badge: "最强",
            badgeColor: .purple
        )

        sonnetModel = ModelInfo(
            id: "claude-sonnet-4.6",
            name: "claude-sonnet-4.6",
            displayName: "claude-sonnet-4.6",
            type: .hubPaid,
            capability: .advanced,
            speed: .fast,
            costPerMillionTokens: 3.0,
            memorySize: nil,
            suitableFor: ["大多数任务", "平衡性能"],
            badge: "推荐",
            badgeColor: .blue
        )

        haikuModel = ModelInfo(
            id: "claude-haiku-4.5",
            name: "claude-haiku-4.5",
            displayName: "claude-haiku-4.5",
            type: .hubPaid,
            capability: .basic,
            speed: .ultraFast,
            costPerMillionTokens: 0.25,
            memorySize: nil,
            suitableFor: ["简单任务", "批量处理"],
            badge: "经济",
            badgeColor: .green
        )

        localModels = [
            ModelInfo(
                id: "llama-3-70b-local",
                name: "llama-3-70b-local",
                displayName: "llama-3-70b-local",
                type: .local,
                capability: .intermediate,
                speed: .medium,
                costPerMillionTokens: nil,
                memorySize: "40GB",
                suitableFor: ["代码生成", "中等任务"],
                badge: nil,
                badgeColor: nil
            ),
            ModelInfo(
                id: "llama-3-8b-local",
                name: "llama-3-8b-local",
                displayName: "llama-3-8b-local",
                type: .local,
                capability: .basic,
                speed: .fast,
                costPerMillionTokens: nil,
                memorySize: "4GB",
                suitableFor: ["简单任务", "快速响应"],
                badge: nil,
                badgeColor: nil
            )
        ]
    }
}

/// 资源分配计划
struct ResourceAllocationPlan {
    var exclusiveProjects: [ProjectAllocation] = []  // 独占资源的项目
    var parallelProjects: [ProjectAllocation] = []   // 共享资源的项目
    var waitingProjects: [ProjectModel] = []         // 等待资源的项目

    var totalProjects: Int {
        exclusiveProjects.count + parallelProjects.count + waitingProjects.count
    }

    var activeProjects: Int {
        exclusiveProjects.count + parallelProjects.count
    }
}

/// 项目分配
struct ProjectAllocation {
    let project: ProjectModel
    let model: ModelInfo
    let priority: Int
    let estimatedDuration: TimeInterval
    var requiresExclusive: Bool = false

    var estimatedCost: Double {
        guard let costPerMillion = model.costPerMillionTokens else { return 0 }

        // 简化估算：假设每小时使用 50K tokens
        let hours = estimatedDuration / 3600
        let estimatedTokens = hours * 50000
        return (estimatedTokens / 1_000_000) * costPerMillion
    }
}

/// 项目任务复杂度（用于 Orchestrator）
enum ProjectTaskComplexity {
    case low
    case medium
    case high

    var requiredCapability: Int {
        switch self {
        case .low: return 3
        case .medium: return 4
        case .high: return 5
        }
    }
}

/// 多泳道启动编排报告（XT-W2-12）
struct LaneLaunchReport {
    let splitPlanID: String
    let launchedLaneIDs: [String]
    let blockedLaneReasons: [String: String]
    let deferredLaneIDs: [String]
    let concurrencyLimit: Int
    let reproducibilitySignature: String
    let worktreeStateRefs: [String: String]
    let worktreePaths: [String: String]

    init(
        splitPlanID: String,
        launchedLaneIDs: [String],
        blockedLaneReasons: [String: String],
        deferredLaneIDs: [String],
        concurrencyLimit: Int,
        reproducibilitySignature: String,
        worktreeStateRefs: [String: String] = [:],
        worktreePaths: [String: String] = [:]
    ) {
        self.splitPlanID = splitPlanID
        self.launchedLaneIDs = launchedLaneIDs
        self.blockedLaneReasons = blockedLaneReasons
        self.deferredLaneIDs = deferredLaneIDs
        self.concurrencyLimit = concurrencyLimit
        self.reproducibilitySignature = reproducibilitySignature
        self.worktreeStateRefs = worktreeStateRefs
        self.worktreePaths = worktreePaths
    }
}
