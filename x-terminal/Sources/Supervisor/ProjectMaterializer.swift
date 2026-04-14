import Foundation

/// 泳道风险档位
enum LaneRiskTier: String, Codable, CaseIterable, Comparable {
    case low
    case medium
    case high
    case critical

    static func < (lhs: LaneRiskTier, rhs: LaneRiskTier) -> Bool {
        let order: [LaneRiskTier] = [.low, .medium, .high, .critical]
        return (order.firstIndex(of: lhs) ?? 0) < (order.firstIndex(of: rhs) ?? 0)
    }
}

/// 泳道预算档位
enum LaneBudgetClass: String, Codable, CaseIterable {
    case economy
    case balanced
    case premium
}

/// 泳道落盘模式：hard=建子项目，soft=仅 lane task
enum LaneMaterializationMode: String, Codable {
    case hardSplit = "hard_split"
    case softSplit = "soft_split"
}

enum LanePlanSource: String, Codable {
    case aiXT1 = "ai_xt_1"
    case inferred
}

/// 来自拆分提案（AI-XT-1 输出）或本地推导的 lane 计划
struct SupervisorLanePlan: Identifiable {
    var id: String { laneID }

    let laneID: String
    let goal: String
    let dependsOn: [String]
    let riskTier: LaneRiskTier
    let budgetClass: LaneBudgetClass
    let createChildProject: Bool
    let expectedArtifacts: [String]
    let dodChecklist: [String]
    let verificationContract: LaneVerificationContract?
    let source: LanePlanSource
    let metadata: [String: String]
    let task: DecomposedTask

    init(
        laneID: String,
        goal: String,
        dependsOn: [String],
        riskTier: LaneRiskTier,
        budgetClass: LaneBudgetClass,
        createChildProject: Bool,
        expectedArtifacts: [String],
        dodChecklist: [String],
        verificationContract: LaneVerificationContract? = nil,
        source: LanePlanSource,
        metadata: [String: String],
        task: DecomposedTask
    ) {
        self.laneID = laneID
        self.goal = goal
        self.dependsOn = dependsOn
        self.riskTier = riskTier
        self.budgetClass = budgetClass
        self.createChildProject = createChildProject
        self.expectedArtifacts = expectedArtifacts
        self.dodChecklist = dodChecklist
        self.verificationContract = verificationContract
        self.source = source
        self.metadata = metadata
        self.task = task
    }
}

struct LineageWriteOperation: Identifiable {
    enum Operation: String {
        case upsertProjectLineage = "UpsertProjectLineage"
        case attachDispatchContext = "AttachDispatchContext"
    }

    let id = UUID()
    let operation: Operation
    let parentProjectID: UUID?
    let childProjectID: UUID
    let laneID: String
    let splitPlanID: String
    let detail: String
}

struct MaterializationAuditEvent: Identifiable {
    let id = UUID()
    let eventType: String
    let laneID: String
    let detail: String
}

/// 已落盘的 lane
struct MaterializedLane: Identifiable {
    var id: String { plan.laneID }

    let plan: SupervisorLanePlan
    let mode: LaneMaterializationMode
    let task: DecomposedTask
    let targetProject: ProjectModel?
    let lineageOperations: [LineageWriteOperation]
    let decisionReasons: [String]
    let explain: String
}

struct MaterializationResult {
    let splitPlanID: String
    let rootProjectID: UUID?
    let lanes: [MaterializedLane]
    let lineageOperations: [LineageWriteOperation]
    let auditEvents: [MaterializationAuditEvent]
    let hardSplitWithoutChildProject: Int
    let softSplitLineagePollution: Int

    var recommendedConcurrency: Int {
        min(max(1, lanes.count), 4)
    }
}

/// XT-W2-10 Hybrid 落盘器
@MainActor
final class ProjectMaterializer {
    weak var runtimeHost: (any SupervisorProjectRuntimeHosting)?

    private let hardSplitDurationThreshold: TimeInterval = 45 * 60
    private let parallelFanOutThreshold = 2

    private struct MaterializationDecision {
        let mode: LaneMaterializationMode
        let forcedHard: Bool
        let reasons: [String]
    }

    init(runtimeHost: (any SupervisorProjectRuntimeHosting)? = nil) {
        self.runtimeHost = runtimeHost
    }

    func materialize(
        tasks: [DecomposedTask],
        rootProject: ProjectModel?,
        splitPlanID explicitSplitPlanID: String? = nil
    ) async -> MaterializationResult {
        let splitPlanID = explicitSplitPlanID ?? "split-\(UUID().uuidString.lowercased())"
        let anchorProject = rootProject ?? runtimeHost?.activeProjects.first
        let lanePlans = buildLanePlans(from: tasks)

        var lanes: [MaterializedLane] = []
        var lineageOps: [LineageWriteOperation] = []
        var auditEvents: [MaterializationAuditEvent] = []
        var hardSplitWithoutChildProject = 0
        var softSplitLineagePollution = 0

        for plan in lanePlans {
            let decision = materializationDecision(for: plan)
            let mode = decision.mode

            if decision.forcedHard && !plan.createChildProject {
                auditEvents.append(
                    MaterializationAuditEvent(
                        eventType: "supervisor.split.hard_enforced",
                        laneID: plan.laneID,
                        detail: "forced hard split: \(decision.reasons.joined(separator: ","))"
                    )
                )
            }

            let targetProject: ProjectModel?
            var laneLineageOps: [LineageWriteOperation] = []

            if mode == .hardSplit {
                let childProject = await ensureChildProject(for: plan, parent: anchorProject)
                targetProject = childProject

                if let childProject {
                    laneLineageOps.append(
                        LineageWriteOperation(
                            operation: .upsertProjectLineage,
                            parentProjectID: anchorProject?.id,
                            childProjectID: childProject.id,
                            laneID: plan.laneID,
                            splitPlanID: splitPlanID,
                            detail: "materialized hard split child project"
                        )
                    )
                    laneLineageOps.append(
                        LineageWriteOperation(
                            operation: .attachDispatchContext,
                            parentProjectID: anchorProject?.id,
                            childProjectID: childProject.id,
                            laneID: plan.laneID,
                            splitPlanID: splitPlanID,
                            detail: "attach lane dispatch context"
                        )
                    )
                } else {
                    hardSplitWithoutChildProject += 1
                }
            } else {
                targetProject = anchorProject
                if !laneLineageOps.isEmpty {
                    softSplitLineagePollution += 1
                }
            }

            var task = plan.task
            var metadata = task.metadata
            metadata["split_plan_id"] = splitPlanID
            metadata["lane_id"] = plan.laneID
            metadata["depends_on"] = plan.dependsOn.joined(separator: ",")
            metadata["risk_tier"] = plan.riskTier.rawValue
            metadata["budget_class"] = plan.budgetClass.rawValue
            metadata["create_child_project"] = mode == .hardSplit ? "1" : "0"
            metadata["materialization_mode"] = mode.rawValue
            metadata["hard_split_forced"] = decision.forcedHard ? "1" : "0"
            metadata["materialization_reasons"] = decision.reasons.joined(separator: "|")
            metadata["expected_artifacts"] = plan.expectedArtifacts.joined(separator: ",")
            metadata["dod_checklist"] = plan.dodChecklist.joined(separator: " | ")
            metadata["split_plan_source"] = plan.source.rawValue
            if let verificationContract = plan.verificationContract {
                applyVerificationContractMetadata(verificationContract, to: &metadata)
            }
            if let targetProject {
                metadata["project_id"] = targetProject.id.uuidString
            }
            task.metadata = metadata

            let explain = buildExplain(
                laneID: plan.laneID,
                mode: mode,
                targetProject: targetProject,
                forcedHard: decision.forcedHard,
                riskTier: plan.riskTier,
                budgetClass: plan.budgetClass,
                reasons: decision.reasons
            )

            let lane = MaterializedLane(
                plan: plan,
                mode: mode,
                task: task,
                targetProject: targetProject,
                lineageOperations: laneLineageOps,
                decisionReasons: decision.reasons,
                explain: explain
            )

            lanes.append(lane)
            lineageOps.append(contentsOf: laneLineageOps)

            auditEvents.append(
                MaterializationAuditEvent(
                    eventType: "supervisor.split.materialized",
                    laneID: plan.laneID,
                    detail: explain
                )
            )
        }

        return MaterializationResult(
            splitPlanID: splitPlanID,
            rootProjectID: anchorProject?.id,
            lanes: lanes,
            lineageOperations: lineageOps,
            auditEvents: auditEvents,
            hardSplitWithoutChildProject: hardSplitWithoutChildProject,
            softSplitLineagePollution: softSplitLineagePollution
        )
    }

    /// 直接消费 split proposal（AI-XT-1 输出/覆盖后的提案）进行落盘
    func materialize(
        proposal: SplitProposal,
        decomposition: DecompositionResult?,
        rootProject: ProjectModel?
    ) async -> MaterializationResult {
        let taskByID = Dictionary(
            uniqueKeysWithValues: (decomposition?.allTasks ?? []).map { ($0.id, $0) }
        )

        let tasks: [DecomposedTask] = proposal.lanes.map { lane in
            var task: DecomposedTask

            if let sourceTaskId = lane.sourceTaskId,
               let sourceTask = taskByID[sourceTaskId] {
                task = sourceTask
            } else {
                task = DecomposedTask(
                    description: lane.goal,
                    type: inferType(from: lane.goal),
                    complexity: inferComplexity(from: lane.riskTier),
                    estimatedEffort: max(600, TimeInterval(lane.estimatedEffortMs) / 1_000.0),
                    dependencies: [],
                    status: .pending,
                    priority: 5
                )
            }

            task.description = lane.goal
            task.estimatedEffort = max(task.estimatedEffort, TimeInterval(lane.estimatedEffortMs) / 1_000.0)
            task.metadata["lane_id"] = lane.laneId
            task.metadata["depends_on"] = lane.dependsOn.joined(separator: ",")
            task.metadata["risk_tier"] = lane.riskTier.rawValue
            task.metadata["budget_class"] = lane.budgetClass.rawValue
            task.metadata["create_child_project"] = lane.createChildProject ? "1" : "0"
            task.metadata["split_mode"] = lane.createChildProject ? LaneMaterializationMode.hardSplit.rawValue : LaneMaterializationMode.softSplit.rawValue
            task.metadata["expected_artifacts"] = lane.expectedArtifacts.joined(separator: ",")
            task.metadata["dod_checklist"] = lane.dodChecklist.joined(separator: "|")
            task.metadata["split_plan_source"] = LanePlanSource.aiXT1.rawValue
            task.metadata["source_split_plan_id"] = proposal.splitPlanId.uuidString.lowercased()
            task.metadata["token_budget"] = "\(lane.tokenBudget)"
            if let verificationContract = lane.verificationContract {
                applyVerificationContractMetadata(verificationContract, to: &task.metadata)
            }
            return task
        }

        return await materialize(
            tasks: tasks,
            rootProject: rootProject,
            splitPlanID: proposal.splitPlanId.uuidString.lowercased()
        )
    }

    // MARK: - Private

    private func buildLanePlans(from tasks: [DecomposedTask]) -> [SupervisorLanePlan] {
        let laneIDByTaskID = Dictionary(uniqueKeysWithValues: tasks.enumerated().map { index, task in
            (task.id, normalizeLaneID(task.metadata["lane_id"], fallbackIndex: index + 1))
        })

        return tasks.enumerated().map { index, task in
            let metadata = task.metadata
            let laneID = laneIDByTaskID[task.id] ?? "lane-\(index + 1)"
            let source: LanePlanSource = hasExplicitSplitMetadata(metadata) ? .aiXT1 : .inferred

            let riskTier = parseRiskTier(metadata["risk_tier"]) ?? inferRiskTier(for: task)
            let budgetClass = parseBudgetClass(metadata["budget_class"]) ?? inferBudgetClass(for: task, riskTier: riskTier)
            let splitMode = parseMode(metadata["split_mode"])
            let createChildExplicit = parseBool(metadata["create_child_project"])

            let dependsOn = parseDependencies(metadata["depends_on"], fallback: task.dependencies.compactMap { laneIDByTaskID[$0] })
            let createChildProject: Bool
            if let createChildExplicit {
                createChildProject = createChildExplicit
            } else if splitMode == .hardSplit {
                createChildProject = true
            } else if splitMode == .softSplit {
                createChildProject = false
            } else {
                createChildProject = inferDefaultCreateChildProject(for: task, riskTier: riskTier, budgetClass: budgetClass)
            }

            let expectedArtifacts = parseList(metadata["expected_artifacts"], separator: ",", fallback: defaultArtifacts(for: task.type))
            let dodChecklist = parseList(metadata["dod_checklist"], separator: "|", fallback: defaultDoDChecklist(for: task.type))
            let verificationContract = buildVerificationContract(
                metadata: metadata,
                task: task,
                riskTier: riskTier,
                expectedArtifacts: expectedArtifacts,
                dodChecklist: dodChecklist
            )

            return SupervisorLanePlan(
                laneID: laneID,
                goal: task.description,
                dependsOn: dependsOn,
                riskTier: riskTier,
                budgetClass: budgetClass,
                createChildProject: createChildProject,
                expectedArtifacts: expectedArtifacts,
                dodChecklist: dodChecklist,
                verificationContract: verificationContract,
                source: source,
                metadata: metadata,
                task: task
            )
        }
    }

    private func hasExplicitSplitMetadata(_ metadata: [String: String]) -> Bool {
        metadata.keys.contains(where: { key in
            ["lane_id", "risk_tier", "budget_class", "create_child_project", "split_mode"].contains(key)
        })
    }

    private func materializationDecision(for plan: SupervisorLanePlan) -> MaterializationDecision {
        var hardReasons: [String] = []

        if plan.riskTier >= .high {
            hardReasons.append("high_risk_lane")
        }
        if plan.task.estimatedEffort > hardSplitDurationThreshold {
            hardReasons.append("long_running_lane")
        }
        if parseBool(plan.metadata["requires_isolated_rollback"]) == true {
            hardReasons.append("isolated_rollback_required")
        }
        if parseBool(plan.metadata["grant_profile_mismatch"]) == true {
            hardReasons.append("grant_profile_mismatch")
        }
        if plan.dependsOn.count >= parallelFanOutThreshold {
            hardReasons.append("high_parallel_fanout")
        }
        if plan.budgetClass == .premium && plan.task.type == .deployment {
            hardReasons.append("premium_deployment_lane")
        }

        if plan.createChildProject {
            let reasons = ["user_requested_child_project"] + hardReasons
            return MaterializationDecision(mode: .hardSplit, forcedHard: false, reasons: dedup(reasons))
        }

        if !hardReasons.isEmpty {
            return MaterializationDecision(mode: .hardSplit, forcedHard: true, reasons: dedup(hardReasons))
        }

        return MaterializationDecision(mode: .softSplit, forcedHard: false, reasons: ["lane_task_inline"])
    }

    private func ensureChildProject(for plan: SupervisorLanePlan, parent: ProjectModel?) async -> ProjectModel? {
        guard let runtimeHost else {
            return createDetachedChildProject(for: plan, parent: parent)
        }

        let parentName = parent?.name ?? "Root"
        let childName = "\(parentName) · \(plan.laneID)"

        if let existing = runtimeHost.activeProjects.first(where: { $0.name == childName }) {
            // Existing pinned child projects may come from older sessions with stale model profile.
            // Refresh capability/autonomy so high-risk lanes do not fail allocation before execution.
            applySuggestedExecutionProfile(to: existing, for: plan)
            return existing
        }

        let budgetTemplate = parent?.budget ?? Budget(daily: 10.0, monthly: 300.0)
        let childBudget = deriveChildBudget(from: budgetTemplate, laneBudgetClass: plan.budgetClass)

        let childProject = ProjectModel(
            name: childName,
            taskDescription: plan.goal,
            taskIcon: parent?.taskIcon ?? "arrow.triangle.branch",
            status: .pending,
            modelName: suggestedModelName(for: plan),
            isLocalModel: plan.budgetClass == .economy,
            executionTier: xtSuggestedExecutionTier(for: plan.riskTier),
            supervisorInterventionTier: xtSuggestedSupervisorTier(for: plan.riskTier),
            budget: childBudget
        )
        applySuggestedExecutionProfile(to: childProject, for: plan)

        runtimeHost.addActiveProjectIfNeeded(childProject)
        await runtimeHost.onProjectCreated(childProject)

        return childProject
    }

    private func createDetachedChildProject(for plan: SupervisorLanePlan, parent: ProjectModel?) -> ProjectModel {
        let childProject = ProjectModel(
            name: "\(parent?.name ?? "Root") · \(plan.laneID)",
            taskDescription: plan.goal,
            taskIcon: parent?.taskIcon ?? "arrow.triangle.branch",
            status: .pending,
            modelName: suggestedModelName(for: plan),
            isLocalModel: plan.budgetClass == .economy,
            executionTier: xtSuggestedExecutionTier(for: plan.riskTier),
            supervisorInterventionTier: xtSuggestedSupervisorTier(for: plan.riskTier),
            budget: deriveChildBudget(from: parent?.budget ?? Budget(daily: 10.0, monthly: 300.0), laneBudgetClass: plan.budgetClass)
        )
        applySuggestedExecutionProfile(to: childProject, for: plan)
        return childProject
    }

    private func deriveChildBudget(from parent: Budget, laneBudgetClass: LaneBudgetClass) -> Budget {
        let multiplier: Double
        switch laneBudgetClass {
        case .economy:
            multiplier = 0.2
        case .balanced:
            multiplier = 0.35
        case .premium:
            multiplier = 0.5
        }

        return Budget(
            daily: max(1.0, parent.daily * multiplier),
            monthly: max(30.0, parent.monthly * multiplier),
            used: 0
        )
    }

    private func suggestedModelName(for plan: SupervisorLanePlan) -> String {
        switch plan.riskTier {
        case .critical:
            return "claude-opus-4.6"
        case .high:
            return "claude-sonnet-4.6"
        case .medium:
            return plan.budgetClass == .economy ? "llama-3-70b-local" : "claude-sonnet-4.6"
        case .low:
            return plan.budgetClass == .premium ? "claude-sonnet-4.6" : "llama-3-8b-local"
        }
    }

    private func applySuggestedExecutionProfile(to project: ProjectModel, for plan: SupervisorLanePlan) {
        project.currentModel = suggestedModelInfo(for: plan)
        let governance = AXProjectGovernanceBundle.recommended(
            for: xtSuggestedExecutionTier(for: plan.riskTier),
            supervisorInterventionTier: xtSuggestedSupervisorTier(for: plan.riskTier)
        )
        project.updateGovernance(
            executionTier: governance.executionTier,
            supervisorInterventionTier: governance.supervisorInterventionTier,
            reviewPolicyMode: governance.reviewPolicyMode,
            progressHeartbeatSeconds: governance.schedule.progressHeartbeatSeconds,
            reviewPulseSeconds: governance.schedule.reviewPulseSeconds,
            brainstormReviewSeconds: governance.schedule.brainstormReviewSeconds,
            eventDrivenReviewEnabled: governance.schedule.eventDrivenReviewEnabled,
            eventReviewTriggers: governance.schedule.eventReviewTriggers
        )
    }

    private func suggestedModelInfo(for plan: SupervisorLanePlan) -> ModelInfo {
        let suggestedName = suggestedModelName(for: plan)
        let pool = ResourcePool()
        if let matched = pool.availableResources.first(where: { $0.id == suggestedName || $0.name == suggestedName }) {
            return matched
        }

        let local = plan.budgetClass == .economy
        return ModelInfo(
            id: suggestedName,
            name: suggestedName,
            displayName: suggestedName,
            type: local ? .local : .hubPaid,
            capability: .intermediate,
            speed: .medium,
            costPerMillionTokens: local ? nil : 3.0,
            memorySize: local ? "40GB" : nil,
            suitableFor: ["通用任务"],
            badge: nil,
            badgeColor: nil
        )
    }

    private func buildExplain(
        laneID: String,
        mode: LaneMaterializationMode,
        targetProject: ProjectModel?,
        forcedHard: Bool,
        riskTier: LaneRiskTier,
        budgetClass: LaneBudgetClass,
        reasons: [String]
    ) -> String {
        let projectPart = targetProject.map { "project=\($0.name)" } ?? "project=unassigned"
        let forcePart = forcedHard ? "forced_hard=1" : "forced_hard=0"
        let reasonPart = "reasons=\(reasons.joined(separator: "+"))"
        return "lane=\(laneID),mode=\(mode.rawValue),risk=\(riskTier.rawValue),budget=\(budgetClass.rawValue),\(forcePart),\(reasonPart),\(projectPart)"
    }

    private func normalizeLaneID(_ raw: String?, fallbackIndex: Int) -> String {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            return "lane-\(fallbackIndex)"
        }
        return trimmed
    }

    private func inferRiskTier(for task: DecomposedTask) -> LaneRiskTier {
        if task.type == .deployment || task.complexity == .veryComplex {
            return .critical
        }
        if task.type == .bugfix || task.type == .refactoring || task.complexity == .complex {
            return .high
        }
        if task.complexity == .moderate {
            return .medium
        }
        return .low
    }

    private func inferBudgetClass(for task: DecomposedTask, riskTier: LaneRiskTier) -> LaneBudgetClass {
        if riskTier >= .high {
            return .premium
        }
        if task.complexity <= .simple && task.estimatedEffort <= 1_800 {
            return .economy
        }
        return .balanced
    }

    private func inferDefaultCreateChildProject(for task: DecomposedTask, riskTier: LaneRiskTier, budgetClass: LaneBudgetClass) -> Bool {
        riskTier >= .high || budgetClass == .premium || task.estimatedEffort > hardSplitDurationThreshold
    }

    private func parseMode(_ raw: String?) -> LaneMaterializationMode? {
        guard let raw else { return nil }
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let parsed = LaneMaterializationMode(rawValue: normalized) {
            return parsed
        }
        if normalized == "hard" {
            return .hardSplit
        }
        if normalized == "soft" {
            return .softSplit
        }
        return nil
    }

    private func parseRiskTier(_ raw: String?) -> LaneRiskTier? {
        guard let raw else { return nil }
        return LaneRiskTier(rawValue: raw.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func parseBudgetClass(_ raw: String?) -> LaneBudgetClass? {
        guard let raw else { return nil }
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let parsed = LaneBudgetClass(rawValue: normalized) {
            return parsed
        }
        switch normalized {
        case SplitBudgetClass.compact.rawValue:
            return .economy
        case SplitBudgetClass.standard.rawValue:
            return .balanced
        case SplitBudgetClass.premium.rawValue, SplitBudgetClass.burst.rawValue:
            return .premium
        default:
            return nil
        }
    }

    private func parseBool(_ raw: String?) -> Bool? {
        guard let raw = raw?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        if ["1", "true", "yes", "y"].contains(raw) {
            return true
        }
        if ["0", "false", "no", "n"].contains(raw) {
            return false
        }
        return nil
    }

    private func parseDependencies(_ raw: String?, fallback: [String]) -> [String] {
        if let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return raw
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        return fallback
    }

    private func parseVerificationMethod(_ raw: String?) -> LaneVerificationMethod? {
        guard let raw else { return nil }
        return LaneVerificationMethod(rawValue: raw.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func parseVerificationRetryPolicy(_ raw: String?) -> LaneVerificationRetryPolicy? {
        guard let raw else { return nil }
        return LaneVerificationRetryPolicy(rawValue: raw.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func parseVerificationHoldPolicy(_ raw: String?) -> LaneVerificationHoldPolicy? {
        guard let raw else { return nil }
        return LaneVerificationHoldPolicy(rawValue: raw.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func buildVerificationContract(
        metadata: [String: String],
        task: DecomposedTask,
        riskTier: LaneRiskTier,
        expectedArtifacts: [String],
        dodChecklist: [String]
    ) -> LaneVerificationContract {
        if let expectedState = metadata["verification_expected_state"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !expectedState.isEmpty,
           let verifyMethod = parseVerificationMethod(metadata["verification_method"]),
           let retryPolicy = parseVerificationRetryPolicy(metadata["verification_retry_policy"]),
           let holdPolicy = parseVerificationHoldPolicy(metadata["verification_hold_policy"]) {
            return LaneVerificationContract(
                expectedState: expectedState,
                verifyMethod: verifyMethod,
                retryPolicy: retryPolicy,
                holdPolicy: holdPolicy,
                evidenceRequired: parseList(metadata["verification_evidence_required"], separator: "|", fallback: expectedArtifacts),
                verificationChecklist: parseList(
                    metadata["verification_checklist"],
                    separator: "|",
                    fallback: ["expected_state_confirmed", "evidence_attached"] + dodChecklist
                )
            )
        }

        let splitRiskTier: SplitRiskTier = {
            switch riskTier {
            case .low: return .low
            case .medium: return .medium
            case .high: return .high
            case .critical: return .critical
            }
        }()

        let method: LaneVerificationMethod
        let retryPolicy: LaneVerificationRetryPolicy
        let holdPolicy: LaneVerificationHoldPolicy
        let expectedState: String
        var evidenceRequired = expectedArtifacts

        switch task.type {
        case .development, .bugfix, .refactoring, .testing:
            method = .targetedChecksAndDiffReview
            retryPolicy = splitRiskTier >= .high ? .singleRetryThenEscalate : .boundedRetryThenHold
            holdPolicy = .holdOnMismatch
            expectedState = "Lane goal is satisfied, artifacts are updated, and targeted checks confirm no obvious regression."
            evidenceRequired.append(contentsOf: ["diff_summary", "targeted_check_result"])
        case .deployment:
            method = .preflightAndSmoke
            retryPolicy = splitRiskTier >= .high ? .noAutoRetry : .singleRetryThenEscalate
            holdPolicy = .holdUntilEvidence
            expectedState = "Change is ready to ship, post-change smoke checks pass, and rollback readiness is recorded."
            evidenceRequired.append(contentsOf: ["preflight_result", "smoke_result", "rollback_readiness"])
        case .documentation, .research, .review, .design, .planning:
            method = .artifactConsistencyReview
            retryPolicy = .noAutoRetry
            holdPolicy = .advisoryOnly
            expectedState = "Produced artifacts are internally consistent, scoped correctly, and ready for handoff."
            evidenceRequired.append(contentsOf: ["artifact_review_note", "consistency_summary"])
        }

        if splitRiskTier >= .high {
            evidenceRequired.append("grant_or_risk_exception_reference")
        }

        return LaneVerificationContract(
            expectedState: expectedState,
            verifyMethod: method,
            retryPolicy: retryPolicy,
            holdPolicy: holdPolicy,
            evidenceRequired: dedupList(evidenceRequired),
            verificationChecklist: dedupList(["expected_state_confirmed", "evidence_attached"] + dodChecklist)
        )
    }

    private func parseList(_ raw: String?, separator: Character, fallback: [String]) -> [String] {
        if let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return raw
                .split(separator: separator)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        return fallback
    }

    private func applyVerificationContractMetadata(
        _ contract: LaneVerificationContract,
        to metadata: inout [String: String]
    ) {
        metadata["verification_expected_state"] = contract.expectedState
        metadata["verification_method"] = contract.verifyMethod.rawValue
        metadata["verification_retry_policy"] = contract.retryPolicy.rawValue
        metadata["verification_hold_policy"] = contract.holdPolicy.rawValue
        metadata["verification_evidence_required"] = dedupList(contract.evidenceRequired).joined(separator: "|")
        metadata["verification_checklist"] = dedupList(contract.verificationChecklist).joined(separator: "|")
    }

    private func dedup(_ reasons: [String]) -> [String] {
        var seen: Set<String> = []
        var ordered: [String] = []
        for reason in reasons where !reason.isEmpty {
            if seen.insert(reason).inserted {
                ordered.append(reason)
            }
        }
        return ordered
    }

    private func dedupList(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var ordered: [String] = []
        for value in values.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }) where !value.isEmpty {
            if seen.insert(value).inserted {
                ordered.append(value)
            }
        }
        return ordered
    }

    private func defaultArtifacts(for type: DecomposedTaskType) -> [String] {
        switch type {
        case .testing:
            return ["test_report", "coverage_delta"]
        case .documentation:
            return ["docs_update"]
        case .deployment:
            return ["deployment_plan", "rollback_plan"]
        default:
            return ["code_changes"]
        }
    }

    private func defaultDoDChecklist(for type: DecomposedTaskType) -> [String] {
        switch type {
        case .deployment:
            return ["release_gate_passed", "rollback_validated", "audit_event_recorded"]
        case .testing:
            return ["tests_passed", "result_documented", "known_risks_listed"]
        default:
            return ["compilable_changes", "do_not_break_existing_contracts", "evidence_recorded"]
        }
    }

    private func inferType(from goal: String) -> DecomposedTaskType {
        let text = goal.lowercased()
        if text.contains("test") || text.contains("测试") {
            return .testing
        }
        if text.contains("doc") || text.contains("文档") {
            return .documentation
        }
        if text.contains("deploy") || text.contains("部署") || text.contains("发布") {
            return .deployment
        }
        if text.contains("fix") || text.contains("bug") || text.contains("修复") {
            return .bugfix
        }
        return .development
    }

    private func inferComplexity(from risk: SplitRiskTier) -> DecomposedTaskComplexity {
        switch risk {
        case .critical:
            return .veryComplex
        case .high:
            return .complex
        case .medium:
            return .moderate
        case .low:
            return .simple
        }
    }
}
