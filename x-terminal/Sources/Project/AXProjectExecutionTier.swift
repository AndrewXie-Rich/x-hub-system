import Foundation

enum AXProjectExecutionTier: String, Codable, CaseIterable, Sendable {
    case a0Observe = "a0_observe"
    case a1Plan = "a1_plan"
    case a2RepoAuto = "a2_repo_auto"
    case a3DeliverAuto = "a3_deliver_auto"
    case a4OpenClaw = "a4_openclaw"

    var displayName: String {
        switch self {
        case .a0Observe:
            return "A0 Observe"
        case .a1Plan:
            return "A1 Plan"
        case .a2RepoAuto:
            return "A2 Repo Auto"
        case .a3DeliverAuto:
            return "A3 Deliver Auto"
        case .a4OpenClaw:
            return "A4 Agent"
        }
    }

    var oneLineSummary: String {
        switch self {
        case .a0Observe:
            return "只读项目记忆和状态，给建议，但不自动落任务。"
        case .a1Plan:
            return "可以把目标整理成工单 / 计划，并回写项目记忆，但不直接执行仓库或设备动作。"
        case .a2RepoAuto:
            return "可在项目根目录内自主改文件、跑 build / test 并更新计划，仍不碰高风险执行面。"
        case .a3DeliverAuto:
            return "围绕单个项目连续推进到交付完成，可自动收口并回写总结。"
        case .a4OpenClaw:
            return "在受治理前提下使用完整 Agent 执行面，包含 browser / device / connector / extension。"
        }
    }

    var allowedHighlights: [String] {
        switch self {
        case .a0Observe:
            return [
                "读项目记忆",
                "读项目状态",
                "给建议"
            ]
        case .a1Plan:
            return [
                "创建工单 / 计划",
                "回写项目记忆",
                "整理执行方案"
            ]
        case .a2RepoAuto:
            return [
                "改项目根目录文件",
                "跑 build / test",
                "做 patch 并更新计划"
            ]
        case .a3DeliverAuto:
            return [
                "连续推进多 step",
                "自动收口与汇总",
                "commit / PR 级交付"
            ]
        case .a4OpenClaw:
            return [
                "browser runtime",
                "device tools",
                "connector / extension",
                "预批准的低风险本地动作"
            ]
        }
    }

    var blockedHighlights: [String] {
        switch self {
        case .a0Observe:
            return [
                "不能创建 job / plan",
                "不能改 repo",
                "不能跑 build / test",
                "不能触发 browser / device side effect"
            ]
        case .a1Plan:
            return [
                "不能改 repo 文件",
                "不能跑 build / test",
                "不能触发 browser / device / connector side effect"
            ]
        case .a2RepoAuto:
            return [
                "不能 push 远端分支",
                "不能触发 CI",
                "不能碰 browser / device / connector 执行"
            ]
        case .a3DeliverAuto:
            return [
                "不能 push 远端分支",
                "不能触发 CI",
                "不能碰 device / browser / connector / extension 执行"
            ]
        case .a4OpenClaw:
            return [
                "不能绕过受治理自动化就绪检查",
                "不能绕过 Hub 授权 / allowlist",
                "不能绕过 TTL / 紧急回收 / 审计轨迹"
            ]
        }
    }

    var defaultBudgetSummary: String {
        let budget = defaultExecutionBudget
        let cost = budget.maxCostUSDSoft.rounded(.towardZero) == budget.maxCostUSDSoft
            ? String(Int(budget.maxCostUSDSoft))
            : String(format: "%.1f", budget.maxCostUSDSoft)
        return "\(budget.maxContinuousRunMinutes)m run · \(budget.maxToolCallsPerRun) tools · retry x\(budget.maxRetryDepth) · soft $\(cost)"
    }

    var defaultProjectMemoryCeiling: XTMemoryServingProfile {
        switch self {
        case .a0Observe, .a1Plan:
            return .m2PlanReview
        case .a2RepoAuto, .a3DeliverAuto:
            return .m3DeepDive
        case .a4OpenClaw:
            return .m4FullScan
        }
    }

    var defaultSupervisorInterventionTier: AXProjectSupervisorInterventionTier {
        switch self {
        case .a0Observe:
            return .s0SilentAudit
        case .a1Plan:
            return .s1MilestoneReview
        case .a2RepoAuto:
            return .s2PeriodicReview
        case .a3DeliverAuto, .a4OpenClaw:
            return .s3StrategicCoach
        }
    }

    var minimumSafeSupervisorTier: AXProjectSupervisorInterventionTier {
        switch self {
        case .a0Observe, .a1Plan:
            return .s0SilentAudit
        case .a2RepoAuto, .a3DeliverAuto:
            return .s1MilestoneReview
        case .a4OpenClaw:
            return .s2PeriodicReview
        }
    }

    var defaultReviewPolicyMode: AXProjectReviewPolicyMode {
        switch self {
        case .a0Observe:
            return .milestoneOnly
        case .a1Plan:
            return .periodic
        case .a2RepoAuto, .a3DeliverAuto, .a4OpenClaw:
            return .hybrid
        }
    }

    var defaultProgressHeartbeatSeconds: Int {
        switch self {
        case .a0Observe:
            return 1800
        case .a1Plan:
            return 1200
        case .a2RepoAuto:
            return 900
        case .a3DeliverAuto, .a4OpenClaw:
            return 600
        }
    }

    var defaultReviewPulseSeconds: Int {
        switch self {
        case .a0Observe:
            return 0
        case .a1Plan:
            return 3600
        case .a2RepoAuto:
            return 1800
        case .a3DeliverAuto, .a4OpenClaw:
            return 1200
        }
    }

    var defaultBrainstormReviewSeconds: Int {
        switch self {
        case .a0Observe, .a1Plan:
            return 0
        case .a2RepoAuto:
            return 3600
        case .a3DeliverAuto, .a4OpenClaw:
            return 2400
        }
    }

    var defaultEventDrivenReviewEnabled: Bool {
        switch self {
        case .a0Observe, .a1Plan:
            return false
        case .a2RepoAuto, .a3DeliverAuto, .a4OpenClaw:
            return true
        }
    }

    var mandatoryReviewTriggers: [AXProjectReviewTrigger] {
        switch self {
        case .a0Observe, .a1Plan:
            return [.preDoneSummary]
        case .a2RepoAuto:
            return [.blockerDetected, .preDoneSummary]
        case .a3DeliverAuto:
            return [.blockerDetected, .planDrift, .preDoneSummary]
        case .a4OpenClaw:
            return [.blockerDetected, .preHighRiskAction, .preDoneSummary]
        }
    }

    var defaultEventReviewTriggers: [AXProjectReviewTrigger] {
        switch self {
        case .a0Observe:
            return [.manualRequest]
        case .a1Plan:
            return [.preDoneSummary]
        case .a2RepoAuto:
            return [.blockerDetected, .preDoneSummary]
        case .a3DeliverAuto:
            return [.blockerDetected, .planDrift, .preDoneSummary]
        case .a4OpenClaw:
            return [.blockerDetected, .preHighRiskAction, .preDoneSummary]
        }
    }

    var defaultRuntimeSurfacePreset: AXProjectRuntimeSurfaceMode {
        switch self {
        case .a0Observe:
            return .manual
        case .a1Plan, .a2RepoAuto, .a3DeliverAuto:
            return .guided
        case .a4OpenClaw:
            return .trustedOpenClawMode
        }
    }

    @available(*, deprecated, message: "Use defaultRuntimeSurfacePreset")
    var defaultSurfacePreset: AXProjectAutonomyMode {
        defaultRuntimeSurfacePreset
    }

    var baseCapabilityBundle: AXProjectCapabilityBundle {
        switch self {
        case .a0Observe:
            return .observeOnly
        case .a1Plan:
            return AXProjectCapabilityBundle(
                allowJobPlanAuto: true,
                allowRepoWrite: false,
                allowRepoDeleteMove: false,
                allowRepoBuild: false,
                allowRepoTest: false,
                allowGitApply: false,
                allowManagedProcesses: false,
                allowProcessAutoRestart: false,
                allowGitCommit: false,
                allowGitPush: false,
                allowPRCreate: false,
                allowCIRead: false,
                allowCITrigger: false,
                allowBrowserRuntime: false,
                allowDeviceTools: false,
                allowConnectorActions: false,
                allowExtensions: false,
                allowAutoLocalApproval: false
            )
        case .a2RepoAuto:
            return AXProjectCapabilityBundle(
                allowJobPlanAuto: true,
                allowRepoWrite: true,
                allowRepoDeleteMove: true,
                allowRepoBuild: true,
                allowRepoTest: true,
                allowGitApply: true,
                allowManagedProcesses: true,
                allowProcessAutoRestart: false,
                allowGitCommit: false,
                allowGitPush: false,
                allowPRCreate: false,
                allowCIRead: false,
                allowCITrigger: false,
                allowBrowserRuntime: false,
                allowDeviceTools: false,
                allowConnectorActions: false,
                allowExtensions: false,
                allowAutoLocalApproval: false
            )
        case .a3DeliverAuto:
            return AXProjectCapabilityBundle(
                allowJobPlanAuto: true,
                allowRepoWrite: true,
                allowRepoDeleteMove: true,
                allowRepoBuild: true,
                allowRepoTest: true,
                allowGitApply: true,
                allowManagedProcesses: true,
                allowProcessAutoRestart: true,
                allowGitCommit: true,
                allowGitPush: false,
                allowPRCreate: true,
                allowCIRead: true,
                allowCITrigger: false,
                allowBrowserRuntime: false,
                allowDeviceTools: false,
                allowConnectorActions: false,
                allowExtensions: false,
                allowAutoLocalApproval: false
            )
        case .a4OpenClaw:
            return AXProjectCapabilityBundle(
                allowJobPlanAuto: true,
                allowRepoWrite: true,
                allowRepoDeleteMove: true,
                allowRepoBuild: true,
                allowRepoTest: true,
                allowGitApply: true,
                allowManagedProcesses: true,
                allowProcessAutoRestart: true,
                allowGitCommit: true,
                allowGitPush: true,
                allowPRCreate: true,
                allowCIRead: true,
                allowCITrigger: true,
                allowBrowserRuntime: true,
                allowDeviceTools: true,
                allowConnectorActions: true,
                allowExtensions: true,
                allowAutoLocalApproval: true
            )
        }
    }

    var defaultExecutionBudget: AXProjectExecutionBudget {
        switch self {
        case .a0Observe:
            return AXProjectExecutionBudget(
                maxContinuousRunMinutes: 10,
                maxToolCallsPerRun: 0,
                maxRetryDepth: 0,
                maxCostUSDSoft: 1,
                preDoneReviewRequired: false,
                doneRequiresEvidence: false
            )
        case .a1Plan:
            return AXProjectExecutionBudget(
                maxContinuousRunMinutes: 20,
                maxToolCallsPerRun: 8,
                maxRetryDepth: 1,
                maxCostUSDSoft: 3,
                preDoneReviewRequired: true,
                doneRequiresEvidence: false
            )
        case .a2RepoAuto:
            return AXProjectExecutionBudget(
                maxContinuousRunMinutes: 45,
                maxToolCallsPerRun: 24,
                maxRetryDepth: 2,
                maxCostUSDSoft: 8,
                preDoneReviewRequired: true,
                doneRequiresEvidence: true
            )
        case .a3DeliverAuto:
            return AXProjectExecutionBudget(
                maxContinuousRunMinutes: 90,
                maxToolCallsPerRun: 48,
                maxRetryDepth: 3,
                maxCostUSDSoft: 15,
                preDoneReviewRequired: true,
                doneRequiresEvidence: true
            )
        case .a4OpenClaw:
            return AXProjectExecutionBudget(
                maxContinuousRunMinutes: 120,
                maxToolCallsPerRun: 80,
                maxRetryDepth: 3,
                maxCostUSDSoft: 25,
                preDoneReviewRequired: true,
                doneRequiresEvidence: true
            )
        }
    }

    static func fromRuntimeSurfaceMode(_ mode: AXProjectRuntimeSurfaceMode) -> AXProjectExecutionTier {
        switch mode {
        case .manual:
            return .a0Observe
        case .guided:
            return .a1Plan
        case .trustedOpenClawMode:
            return .a4OpenClaw
        }
    }

    @available(*, deprecated, message: "Use fromRuntimeSurfaceMode(_:)")
    static func fromLegacyAutonomyMode(_ mode: AXProjectAutonomyMode) -> AXProjectExecutionTier {
        fromRuntimeSurfaceMode(mode)
    }

    static func fromLegacyAutonomyLevel(_ level: AutonomyLevel) -> AXProjectExecutionTier {
        switch level {
        case .manual:
            return .a0Observe
        case .assisted:
            return .a1Plan
        case .semiAuto:
            return .a2RepoAuto
        case .auto:
            return .a3DeliverAuto
        case .fullAuto:
            return .a4OpenClaw
        }
    }
}

extension AXProjectExecutionTier: Comparable {
    static func < (lhs: AXProjectExecutionTier, rhs: AXProjectExecutionTier) -> Bool {
        lhs.sortRank < rhs.sortRank
    }

    private var sortRank: Int {
        switch self {
        case .a0Observe:
            return 0
        case .a1Plan:
            return 1
        case .a2RepoAuto:
            return 2
        case .a3DeliverAuto:
            return 3
        case .a4OpenClaw:
            return 4
        }
    }
}
