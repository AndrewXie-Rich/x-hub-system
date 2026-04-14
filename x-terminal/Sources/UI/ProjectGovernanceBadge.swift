import SwiftUI

struct ProjectGovernanceCapabilityBoundary: Equatable, Sendable {
    let label: String
    let summary: String
}

struct ProjectGovernancePresentation {
    var executionTier: AXProjectExecutionTier
    var effectiveExecutionTier: AXProjectExecutionTier?
    var supervisorInterventionTier: AXProjectSupervisorInterventionTier
    var recommendedSupervisorInterventionTier: AXProjectSupervisorInterventionTier?
    var effectiveSupervisorInterventionTier: AXProjectSupervisorInterventionTier?
    var recommendedWorkOrderDepth: AXProjectSupervisorWorkOrderDepth?
    var effectiveWorkOrderDepth: AXProjectSupervisorWorkOrderDepth?
    var projectAIStrengthBand: AXProjectAIStrengthBand?
    var projectAIStrengthConfidence: Double?
    var projectAIStrengthReasons: [String]
    var supervisorAdaptationMode: AXProjectSupervisorAdaptationMode?
    var adaptationSummaryOverridesWarning: Bool
    var reviewPolicyMode: AXProjectReviewPolicyMode
    var progressHeartbeatSeconds: Int
    var reviewPulseSeconds: Int
    var brainstormReviewSeconds: Int
    var eventDrivenReviewEnabled: Bool
    var eventReviewTriggerLabels: [String]
    var projectMemoryCeiling: XTMemoryServingProfile
    var supervisorReviewMemoryCeiling: XTMemoryServingProfile
    var capabilityLabels: [String]
    var capabilityBoundaryItems: [ProjectGovernanceCapabilityBoundary]
    var runtimeReadiness: AXProjectGovernanceRuntimeReadinessSnapshot?
    var invalidMessages: [String]
    var warningMessages: [String]
    var compatSource: String
    var statusSummary: String
    var clampSummary: String
    var adaptationSummary: String
    var guidanceSummary: String
    var guidanceAckSummary: String
    var followUpRhythmSummary: String?
    var cadenceExplainability: SupervisorCadenceExplainability?

    init(
        resolved: AXProjectResolvedGovernanceState,
        scheduleState: SupervisorReviewScheduleState? = nil,
        nowMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000.0)
    ) {
        executionTier = resolved.configuredBundle.executionTier
        effectiveExecutionTier = resolved.effectiveBundle.executionTier == resolved.configuredBundle.executionTier
            ? nil
            : resolved.effectiveBundle.executionTier
        supervisorInterventionTier = resolved.configuredBundle.supervisorInterventionTier
        recommendedSupervisorInterventionTier = resolved.supervisorAdaptation.recommendedSupervisorTier == resolved.configuredBundle.supervisorInterventionTier
            ? nil
            : resolved.supervisorAdaptation.recommendedSupervisorTier
        effectiveSupervisorInterventionTier = resolved.effectiveBundle.supervisorInterventionTier == resolved.configuredBundle.supervisorInterventionTier
            ? nil
            : resolved.effectiveBundle.supervisorInterventionTier
        recommendedWorkOrderDepth = resolved.supervisorAdaptation.recommendedWorkOrderDepth
        effectiveWorkOrderDepth = resolved.supervisorAdaptation.effectiveWorkOrderDepth
        projectAIStrengthBand = resolved.supervisorAdaptation.projectAIStrengthProfile?.strengthBand
        projectAIStrengthConfidence = resolved.supervisorAdaptation.projectAIStrengthProfile?.confidence
        projectAIStrengthReasons = resolved.supervisorAdaptation.projectAIStrengthProfile?.reasons ?? []
        supervisorAdaptationMode = resolved.supervisorAdaptation.adaptationPolicy.adaptationMode
        adaptationSummaryOverridesWarning =
            (resolved.supervisorAdaptation.projectAIStrengthProfile?.recommendedSupervisorFloor ?? .s0SilentAudit) >
            resolved.supervisorAdaptation.configuredSupervisorTier
        reviewPolicyMode = resolved.effectiveBundle.reviewPolicyMode
        progressHeartbeatSeconds = resolved.effectiveBundle.schedule.progressHeartbeatSeconds
        reviewPulseSeconds = resolved.effectiveBundle.schedule.reviewPulseSeconds
        brainstormReviewSeconds = resolved.effectiveBundle.schedule.brainstormReviewSeconds
        eventDrivenReviewEnabled = resolved.effectiveBundle.schedule.eventDrivenReviewEnabled
        eventReviewTriggerLabels = resolved.effectiveBundle.schedule.eventReviewTriggers.map(\.localizedDisplayName)
        projectMemoryCeiling = resolved.projectMemoryCeiling
        supervisorReviewMemoryCeiling = resolved.supervisorReviewMemoryCeiling
        capabilityLabels = resolved.capabilityBundle.allowedCapabilityLabels
        let effectiveCapabilityBundle = resolved.capabilityBundle.applying(
            effectiveRuntimeSurface: resolved.effectiveRuntimeSurface,
            trustedAutomationStatus: resolved.trustedAutomationStatus
        )
        capabilityBoundaryItems = ProjectGovernancePresentation.capabilityBoundaryItems(
            capabilityBundle: effectiveCapabilityBundle
        )
        runtimeReadiness = resolved.runtimeReadinessSnapshot
        invalidMessages = ProjectGovernancePresentation.messages(
            executionTier: resolved.configuredBundle.executionTier,
            validation: resolved.validation,
            kind: .invalid
        )
        warningMessages = ProjectGovernancePresentation.messages(
            executionTier: resolved.configuredBundle.executionTier,
            validation: resolved.validation,
            kind: .warning
        )
        compatSource = resolved.compatSource.rawValue
        statusSummary = ProjectGovernancePresentation.statusSummary(
            resolved,
            runtimeReadiness: runtimeReadiness
        )
        clampSummary = ProjectGovernancePresentation.clampSummary(resolved)
        adaptationSummary = ProjectGovernancePresentation.adaptationSummary(resolved)
        guidanceSummary = ProjectGovernancePresentation.guidanceSummary(
            resolved.effectiveBundle.supervisorInterventionTier.defaultInterventionMode
        )
        guidanceAckSummary = resolved.effectiveBundle.supervisorInterventionTier.defaultAckRequired
            ? "需要确认"
            : "可选确认"
        followUpRhythmSummary = SupervisorReviewPolicyEngine.eventFollowUpCadenceLabel(governance: resolved)
        cadenceExplainability = scheduleState.map {
            SupervisorReviewPolicyEngine.cadenceExplainability(
                governance: resolved,
                schedule: $0,
                nowMs: nowMs
            )
        }
    }

    init(
        executionTier: AXProjectExecutionTier,
        supervisorInterventionTier: AXProjectSupervisorInterventionTier,
        reviewPolicyMode: AXProjectReviewPolicyMode,
        progressHeartbeatSeconds: Int,
        reviewPulseSeconds: Int,
        brainstormReviewSeconds: Int,
        eventDrivenReviewEnabled: Bool,
        eventReviewTriggers: [AXProjectReviewTrigger]? = nil,
        compatSource: String = "ui_draft"
    ) {
        let minimumSafe = executionTier.minimumSafeSupervisorTier
        let recommended = executionTier.defaultSupervisorInterventionTier
        self.executionTier = executionTier
        effectiveExecutionTier = nil
        self.supervisorInterventionTier = supervisorInterventionTier
        recommendedSupervisorInterventionTier = nil
        effectiveSupervisorInterventionTier = nil
        recommendedWorkOrderDepth = supervisorInterventionTier.defaultWorkOrderDepth
        effectiveWorkOrderDepth = supervisorInterventionTier.defaultWorkOrderDepth
        projectAIStrengthBand = nil
        projectAIStrengthConfidence = nil
        projectAIStrengthReasons = []
        supervisorAdaptationMode = nil
        adaptationSummaryOverridesWarning = false
        self.reviewPolicyMode = reviewPolicyMode
        self.progressHeartbeatSeconds = max(60, progressHeartbeatSeconds)
        self.reviewPulseSeconds = max(0, reviewPulseSeconds)
        self.brainstormReviewSeconds = max(0, brainstormReviewSeconds)
        self.eventDrivenReviewEnabled = eventDrivenReviewEnabled
        let configuredTriggers = AXProjectReviewTrigger.normalizedList(
            eventReviewTriggers ?? executionTier.defaultEventReviewTriggers
        )
        eventReviewTriggerLabels = eventDrivenReviewEnabled
            ? configuredTriggers.map(\.localizedDisplayName)
            : []
        projectMemoryCeiling = executionTier.defaultProjectMemoryCeiling
        supervisorReviewMemoryCeiling = supervisorInterventionTier.defaultReviewMemoryCeiling
        capabilityLabels = executionTier.baseCapabilityBundle.allowedCapabilityLabels
        capabilityBoundaryItems = ProjectGovernancePresentation.capabilityBoundaryItems(
            capabilityBundle: executionTier.baseCapabilityBundle
        )
        runtimeReadiness = nil
        invalidMessages = []
        warningMessages = supervisorInterventionTier < minimumSafe
            ? ["\(executionTier.shortToken) 当前搭配 \(supervisorInterventionTier.shortToken) 属于高风险组合：系统允许保存，但监督强度低于风险参考线，drift / 误操作 / rescue 的发现窗口会更弱。"]
            : (supervisorInterventionTier < recommended
                ? ["\(executionTier.shortToken) 推荐搭配 \(recommended.shortToken) 及以上，当前配置更容易拉长 drift / rescue 的发现窗口。"]
                : [])
        self.compatSource = compatSource
        statusSummary = warningMessages.isEmpty
            ? "治理组合已接受，后续仍会受运行时收束和 TTL 影响。"
            : "当前组合允许保存，但建议你同时关注运行时收束、grant 和高风险动作前的审查配置。"
        clampSummary = "当前未连接运行时收束；这里只展示配置意图。"
        adaptationSummary = "当前还没有项目 AI 强弱自适应评估。"
        guidanceSummary = ProjectGovernancePresentation.guidanceSummary(
            supervisorInterventionTier.defaultInterventionMode
        )
        guidanceAckSummary = supervisorInterventionTier.defaultAckRequired
            ? "需要确认"
            : "可选确认"
        followUpRhythmSummary = nil
        cadenceExplainability = nil
    }

    var effectiveExecutionLabel: String {
        effectiveExecutionTier.map { "\($0.shortToken) \($0.localizedShortLabel)" }
            ?? "\(executionTier.shortToken) \(executionTier.localizedShortLabel)"
    }

    var effectiveSupervisorLabel: String {
        effectiveSupervisorInterventionTier.map { "\($0.shortToken) \($0.localizedShortLabel)" }
            ?? "\(supervisorInterventionTier.shortToken) \(supervisorInterventionTier.localizedShortLabel)"
    }

    var reviewCadenceText: String {
        "心跳 \(governanceDisplayDurationLabel(progressHeartbeatSeconds)) · 脉冲 \(governanceDisplayDurationLabel(reviewPulseSeconds)) · 脑暴 \(governanceDisplayDurationLabel(brainstormReviewSeconds))"
    }

    var cadenceConfiguredSummaryText: String? {
        cadenceExplainability.map { cadenceSummaryText($0, selector: \.configuredSeconds) }
    }

    var cadenceRecommendedSummaryText: String? {
        cadenceExplainability.map { cadenceSummaryText($0, selector: \.recommendedSeconds) }
    }

    var cadenceEffectiveSummaryText: String? {
        cadenceExplainability.map { cadenceSummaryText($0, selector: \.effectiveSeconds) }
    }

    var cadenceReasonSummaryText: String? {
        guard let cadenceExplainability else { return nil }
        let parts = [
            cadenceDimensionReasonSummary("心跳", dimension: cadenceExplainability.progressHeartbeat),
            cadenceDimensionReasonSummary("脉冲", dimension: cadenceExplainability.reviewPulse),
            cadenceDimensionReasonSummary("脑暴", dimension: cadenceExplainability.brainstormReview)
        ]
        return parts.joined(separator: " | ")
    }

    var cadenceDueSummaryText: String? {
        guard let cadenceExplainability else { return nil }
        let parts = [
            cadenceDimensionDueSummary("心跳", dimension: cadenceExplainability.progressHeartbeat),
            cadenceDimensionDueSummary("脉冲", dimension: cadenceExplainability.reviewPulse),
            cadenceDimensionDueSummary("脑暴", dimension: cadenceExplainability.brainstormReview)
        ]
        return parts.joined(separator: " | ")
    }

    var displayReviewPolicyShortLabel: String {
        reviewPolicyMode.localizedShortLabel
    }

    var displayReviewPolicyName: String {
        reviewPolicyMode.localizedDisplayName
    }

    var hasHighRiskWarning: Bool {
        warningMessages.contains { $0.contains("高风险") || $0.contains("风险参考线") }
    }

    var capabilityBoundarySummary: String {
        capabilityBoundaryItems.map { "\($0.label)：\($0.summary)" }.joined(separator: " · ")
    }

    var effectiveTruthLine: String? {
        XTGovernanceTruthPresentation.truthLine(
            configuredExecutionTier: executionTier.rawValue,
            effectiveExecutionTier: (effectiveExecutionTier ?? executionTier).rawValue,
            configuredSupervisorTier: supervisorInterventionTier.rawValue,
            effectiveSupervisorTier: (effectiveSupervisorInterventionTier ?? supervisorInterventionTier).rawValue,
            reviewPolicyMode: reviewPolicyMode.rawValue,
            progressHeartbeatSeconds: progressHeartbeatSeconds,
            reviewPulseSeconds: reviewPulseSeconds,
            brainstormReviewSeconds: brainstormReviewSeconds,
            compatSource: compatSource
        )
    }

    var displayEffectiveTruthLine: String? {
        effectiveTruthLine.map(XTGovernanceTruthPresentation.displayText)
    }

    var compatSourceLabel: String {
        switch compatSource {
        case AXProjectGovernanceCompatSource.explicitDualDial.rawValue:
            return "A/S 档位显式配置"
        case AXProjectGovernanceCompatSource.legacyAutonomyLevel.rawValue:
            return "兼容旧项目卡片档位"
        case AXProjectGovernanceCompatSource.legacyAutonomyMode.rawValue:
            return "兼容旧执行面预设"
        case AXProjectGovernanceCompatSource.defaultConservative.rawValue:
            return "默认 Observe 起步"
        case "ui_draft":
            return "界面草稿预览"
        case "multi_project_detail":
            return "多项目详情卡片"
        default:
            return compatSource
        }
    }

    var compatSourceDetail: String? {
        switch compatSource {
        case AXProjectGovernanceCompatSource.explicitDualDial.rawValue:
            return "当前项目已明确保存 A-Tier / S-Tier / Heartbeat / Review，后续以这组治理设置为准。"
        case AXProjectGovernanceCompatSource.legacyAutonomyLevel.rawValue:
            return "当前治理仍在兼容旧项目卡片档位影子值。建议在项目设置里把 A-Tier / S-Tier / Heartbeat / Review 显式保存一次，让运行时不再依赖旧字段。"
        case AXProjectGovernanceCompatSource.legacyAutonomyMode.rawValue:
            return "当前治理仍由旧执行面预设映射而来。建议补一次显式 A-Tier / S-Tier / Heartbeat / Review 配置，避免后续继续走兼容桥。"
        case AXProjectGovernanceCompatSource.defaultConservative.rawValue:
            return "当前项目还没有显式治理配置，系统先按旧 Observe 起步（A0 + S0）运行；需要进入新的执行场景时，再明确设置 A-Tier / S-Tier / Heartbeat / Review。"
        default:
            return nil
        }
    }

    var governanceSourceHint: String? {
        switch compatSource {
        case AXProjectGovernanceCompatSource.legacyAutonomyLevel.rawValue,
             AXProjectGovernanceCompatSource.legacyAutonomyMode.rawValue,
             AXProjectGovernanceCompatSource.defaultConservative.rawValue:
            return compatSourceDetail
        default:
            return nil
        }
    }

    private func cadenceSummaryText(
        _ cadence: SupervisorCadenceExplainability,
        selector: KeyPath<SupervisorCadenceDimensionExplainability, Int>
    ) -> String {
        [
            "心跳 \(governanceDisplayDurationLabel(cadence.progressHeartbeat[keyPath: selector]))",
            "脉冲 \(governanceDisplayDurationLabel(cadence.reviewPulse[keyPath: selector]))",
            "脑暴 \(governanceDisplayDurationLabel(cadence.brainstormReview[keyPath: selector]))"
        ].joined(separator: " · ")
    }

    private func cadenceDimensionReasonSummary(
        _ title: String,
        dimension: SupervisorCadenceDimensionExplainability
    ) -> String {
        "\(title)：\(Self.localizedCadenceReasonCodes(dimension.effectiveReasonCodes))"
    }

    private func cadenceDimensionDueSummary(
        _ title: String,
        dimension: SupervisorCadenceDimensionExplainability
    ) -> String {
        let state = dimension.isDue ? "已到期" : "未到期"
        return "\(title)：\(state)，\(Self.localizedCadenceReasonCodes(dimension.nextDueReasonCodes))"
    }

    private static func localizedCadenceReasonCodes(_ codes: [String]) -> String {
        HeartbeatGovernanceUserFacingText.cadenceReasonSummary(codes, empty: "无")
    }

    private static func localizedCadenceReasonCode(_ code: String) -> String {
        HeartbeatGovernanceUserFacingText.cadenceReasonText(code) ?? code
    }

    var homeStatusMessage: String {
        if let invalid = invalidMessages.first {
            return invalid
        }
        let normalizedAdaptation = adaptationSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        if adaptationSummaryOverridesWarning && normalizedAdaptation != "当前还没有项目 AI 强弱自适应评估。" {
            return normalizedAdaptation
        }
        if let warning = warningMessages.first {
            return warning
        }
        if normalizedAdaptation != "当前还没有项目 AI 强弱自适应评估。" {
            return normalizedAdaptation
        }
        if let sourceHint = governanceSourceHint {
            return sourceHint
        }
        return statusSummary
    }

    var homeClampMessage: String? {
        let normalized = clampSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        switch normalized {
        case "当前没有额外收束；但仍继续受 Hub 授权、执行面 TTL、就绪状态与紧急回收约束。":
            return nil
        case "当前未连接运行时收束；这里只展示配置意图。":
            return nil
        default:
            return normalized
        }
    }

    var compactCalloutMessage: String? {
        if let invalid = invalidMessages.first {
            return invalid
        }
        if let warning = warningMessages.first {
            return warning
        }
        if let sourceHint = governanceSourceHint {
            return sourceHint
        }
        return homeClampMessage
    }

    var compactCalloutTone: ProjectGovernanceCalloutTone {
        if !invalidMessages.isEmpty {
            return .invalid
        }
        if !warningMessages.isEmpty {
            return .warning
        }
        if governanceSourceHint != nil {
            return .info
        }
        return homeClampMessage == nil ? .neutral : .info
    }

    private enum MessageKind {
        case invalid
        case warning
    }

    private static func messages(
        executionTier: AXProjectExecutionTier,
        validation: AXProjectGovernanceValidation,
        kind: MessageKind
    ) -> [String] {
        switch kind {
        case .invalid:
            guard !validation.invalidReasons.isEmpty else { return [] }
            return ["当前治理配置存在未识别冲突；系统会按更保守的路径处理。"]
        case .warning:
            guard !validation.warningReasons.isEmpty else { return [] }
            if validation.warningReasons.contains(where: { $0.contains("_is_below_review_reference_") }) {
                return ["\(executionTier.shortToken) 当前组合允许保存，但低于 \(validation.minimumSafeSupervisorTier.shortToken) 风险参考线，属于高风险监督区。"]
            }
            return ["\(executionTier.shortToken) 推荐搭配 \(validation.recommendedSupervisorTier.shortToken) 及以上，当前组合允许但偏保守。"]
        }
    }

    private static func statusSummary(
        _ resolved: AXProjectResolvedGovernanceState,
        runtimeReadiness: AXProjectGovernanceRuntimeReadinessSnapshot?
    ) -> String {
        if let runtimeReadiness,
           runtimeReadiness.requiresA4RuntimeReady,
           !runtimeReadiness.runtimeReady {
            return runtimeReadiness.summaryLine
        }
        if resolved.validation.shouldFailClosed {
            return "当前治理配置含未识别冲突，生效档位已按保守路径处理。"
        }
        if resolved.effectiveBundle.executionTier != resolved.configuredBundle.executionTier
            || resolved.effectiveBundle.supervisorInterventionTier != resolved.configuredBundle.supervisorInterventionTier {
            return "当前生效治理已被运行时收束；请同时看预设值和生效值。"
        }
        if resolved.validation.warningReasons.contains(where: { $0.contains("_is_below_review_reference_") }) {
            return "当前组合允许保存，但监督强度低于风险参考线。"
        }
        return "当前预设值和生效值一致。"
    }

    private static func adaptationSummary(_ resolved: AXProjectResolvedGovernanceState) -> String {
        let adaptation = resolved.supervisorAdaptation
        guard let strength = adaptation.projectAIStrengthProfile else {
            return "当前还没有项目 AI 强弱自适应评估。"
        }

        let confidence = Int((strength.confidence * 100).rounded())
        let base = "项目 AI 评估=\(strength.strengthBand.rawValue)（置信度 \(confidence)%）"
        if strength.strengthBand == .unknown {
            if adaptation.recommendedSupervisorTier > adaptation.configuredSupervisorTier {
                return "\(base)；当前证据仍不足，建议至少提升到 \(adaptation.recommendedSupervisorTier.shortToken)。"
            }
            return "\(base)；当前证据仍不足，系统先沿现有治理运行并继续观察。"
        }
        if adaptation.effectiveSupervisorTier > adaptation.configuredSupervisorTier {
            return "\(base)；Supervisor 已从 \(adaptation.configuredSupervisorTier.shortToken) 抬到 \(adaptation.effectiveSupervisorTier.shortToken)。"
        }
        if adaptation.recommendedSupervisorTier > adaptation.configuredSupervisorTier {
            return "\(base)；当前建议至少提升到 \(adaptation.recommendedSupervisorTier.shortToken)，但尚未自动生效。"
        }
        return "\(base)；当前 S-Tier 无需额外抬高。"
    }

    private static func clampSummary(_ resolved: AXProjectResolvedGovernanceState) -> String {
        let runtimeSurface = resolved.effectiveRuntimeSurface
        if let clamp = xtProjectGovernanceClampExplanation(
            effective: runtimeSurface,
            style: .uiChinese
        ) {
            return clamp.summary
        }
        if resolved.configuredBundle.executionTier == .a4OpenClaw
            && (!resolved.trustedAutomationStatus.trustedAutomationReady || !resolved.trustedAutomationStatus.permissionOwnerReady) {
            return "A4 Agent 已配置，但设备 / 浏览器执行仍受受治理自动化就绪检查和权限宿主门禁约束。"
        }
        return "当前没有额外收束；但仍继续受 Hub 授权、执行面 TTL、就绪状态与紧急回收约束。"
    }

    private static func guidanceSummary(_ mode: SupervisorGuidanceInterventionMode) -> String {
        switch mode {
        case .observeOnly:
            return "仅观察，默认不注入指导"
        case .suggestNextSafePoint:
            return "下一个安全点给出建议"
        case .replanNextSafePoint:
            return "下一个安全点要求重规划"
        case .stopImmediately:
            return "触发介入后立即停止"
        }
    }

    private static func capabilityBoundaryItems(
        capabilityBundle: AXProjectCapabilityBundle
    ) -> [ProjectGovernanceCapabilityBoundary] {
        [
            ProjectGovernanceCapabilityBoundary(
                label: "工单 / 计划",
                summary: capabilityBundle.allowJobPlanAuto
                    ? "可自动建 job / plan，并回写执行计划"
                    : "只允许观察，不自动建 job / plan"
            ),
            ProjectGovernanceCapabilityBoundary(
                label: "仓库写入",
                summary: capabilityStatusSummary(
                    allowed: [
                        capabilityBundle.allowRepoWrite ? "改文件" : nil,
                        capabilityBundle.allowGitApply ? "apply patch" : nil,
                        capabilityBundle.allowRepoDeleteMove ? "delete / move" : nil
                    ],
                    denied: [
                        capabilityBundle.allowRepoWrite ? nil : "改文件",
                        capabilityBundle.allowGitApply ? nil : "apply patch",
                        capabilityBundle.allowRepoDeleteMove ? nil : "delete / move"
                    ],
                    allDenied: "改文件 / apply patch / delete / move 全部受限"
                )
            ),
            ProjectGovernanceCapabilityBoundary(
                label: "Build / Test / 进程",
                summary: capabilityStatusSummary(
                    allowed: [
                        capabilityBundle.allowRepoBuild ? "build" : nil,
                        capabilityBundle.allowRepoTest ? "test" : nil,
                        capabilityBundle.allowManagedProcesses ? "managed process" : nil,
                        capabilityBundle.allowProcessAutoRestart ? "auto-restart" : nil
                    ],
                    denied: [
                        capabilityBundle.allowRepoBuild ? nil : "build",
                        capabilityBundle.allowRepoTest ? nil : "test",
                        capabilityBundle.allowManagedProcesses ? nil : "managed process",
                        capabilityBundle.allowProcessAutoRestart ? nil : "auto-restart"
                    ],
                    allDenied: "build / test / managed process 全部受限"
                )
            ),
            ProjectGovernanceCapabilityBoundary(
                label: "Push / Release",
                summary: capabilityStatusSummary(
                    allowed: [
                        capabilityBundle.allowGitCommit ? "commit" : nil,
                        capabilityBundle.allowGitPush ? "push" : nil,
                        capabilityBundle.allowPRCreate ? "PR create" : nil,
                        capabilityBundle.allowCIRead ? "CI read" : nil,
                        capabilityBundle.allowCITrigger ? "CI trigger" : nil
                    ],
                    denied: [
                        capabilityBundle.allowGitCommit ? nil : "commit",
                        capabilityBundle.allowGitPush ? nil : "push",
                        capabilityBundle.allowPRCreate ? nil : "PR create",
                        capabilityBundle.allowCIRead ? nil : "CI read",
                        capabilityBundle.allowCITrigger ? nil : "CI trigger"
                    ],
                    allDenied: "commit / push / PR / CI 全部受限"
                )
            ),
            ProjectGovernanceCapabilityBoundary(
                label: "Browser / Device / Connector",
                summary: capabilityStatusSummary(
                    allowed: [
                        capabilityBundle.allowBrowserRuntime ? "browser" : nil,
                        capabilityBundle.allowDeviceTools ? "device" : nil,
                        capabilityBundle.allowConnectorActions ? "connector" : nil,
                        capabilityBundle.allowExtensions ? "extension" : nil,
                        capabilityBundle.allowAutoLocalApproval ? "low-risk local auto-approve" : nil
                    ],
                    denied: [
                        capabilityBundle.allowBrowserRuntime ? nil : "browser",
                        capabilityBundle.allowDeviceTools ? nil : "device",
                        capabilityBundle.allowConnectorActions ? nil : "connector",
                        capabilityBundle.allowExtensions ? nil : "extension",
                        capabilityBundle.allowAutoLocalApproval ? nil : "low-risk local auto-approve"
                    ],
                    allDenied: "browser / device / connector / extension 全部受限"
                )
            )
        ]
    }

    private static func capabilityStatusSummary(
        allowed: [String?],
        denied: [String?],
        allDenied: String
    ) -> String {
        let allowedValues = allowed.compactMap { $0 }
        let deniedValues = denied.compactMap { $0 }

        guard !allowedValues.isEmpty else { return allDenied }
        let allowedSummary = "可 \(allowedValues.joined(separator: " / "))"
        guard !deniedValues.isEmpty else { return allowedSummary }
        return "\(allowedSummary)；\(deniedValues.joined(separator: " / ")) 仍受限"
    }
}

enum ProjectGovernanceCalloutTone {
    case neutral
    case info
    case warning
    case invalid
}

enum ProjectGovernanceCompactSummaryDisplayStyle: Equatable, Sendable {
    case regular
    case dense
    case watchlist

    var badgeDenseLayout: Bool {
        switch self {
        case .regular:
            return false
        case .dense, .watchlist:
            return true
        }
    }

    var outerPadding: CGFloat {
        switch self {
        case .regular:
            return 12
        case .dense:
            return 10
        case .watchlist:
            return 9
        }
    }

    var verticalSpacing: CGFloat {
        switch self {
        case .regular:
            return 6
        case .dense:
            return 5
        case .watchlist:
            return 4
        }
    }

    var metaLineLimit: Int {
        switch self {
        case .regular:
            return 2
        case .dense, .watchlist:
            return 1
        }
    }

    var cornerRadius: CGFloat {
        switch self {
        case .regular:
            return 14
        case .dense, .watchlist:
            return 12
        }
    }

    var prefersCondensedMeta: Bool {
        self == .watchlist
    }
}

struct ProjectGovernanceCompactMetaItem: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case axisLegend
        case governanceModel
        case callout
        case truthLine
        case followUp
    }

    let kind: Kind
    let text: String
}

struct ProjectGovernanceCompactMetaContext: Equatable, Sendable {
    let axisLegendText: String
    let governanceModelText: String?
    let calloutMessage: String?
    let shouldPreferCalloutInCondensedMeta: Bool
    let truthLine: String?
    let followUpText: String?
}

struct ProjectGovernanceCompactSummarySurfaceConfiguration: Equatable, Sendable {
    let showAxisLegend: Bool
    let displayStyle: ProjectGovernanceCompactSummaryDisplayStyle

    static let operationalDense = Self(
        showAxisLegend: true,
        displayStyle: .dense
    )

    static let watchlist = Self(
        showAxisLegend: true,
        displayStyle: .watchlist
    )
}

enum ProjectGovernanceCompactMetaResolver {
    static func context(
        presentation: ProjectGovernancePresentation,
        displayStyle: ProjectGovernanceCompactSummaryDisplayStyle
    ) -> ProjectGovernanceCompactMetaContext {
        let model = ProjectGovernanceThreeAxisOverviewPresentation(presentation: presentation)
        let axisLegendText: String = switch displayStyle {
        case .regular:
            "三轴：\(model.coordinationSummary)"
        case .dense, .watchlist:
            "三轴：A 管执行，S 管监督，节奏管 review"
        }
        let governanceModelText: String? = switch displayStyle {
        case .regular:
            "新版：双环治理 + 角色记忆；Coder 执行，Supervisor 纠偏，Project / Review 记忆按 resolver 分开算。"
        case .dense:
            "新版：双环治理 + 角色记忆"
        case .watchlist:
            nil
        }

        let trimmedFollowUp = presentation.followUpRhythmSummary?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return ProjectGovernanceCompactMetaContext(
            axisLegendText: axisLegendText,
            governanceModelText: governanceModelText,
            calloutMessage: presentation.compactCalloutMessage,
            shouldPreferCalloutInCondensedMeta: !presentation.invalidMessages.isEmpty
                || !presentation.warningMessages.isEmpty
                || presentation.governanceSourceHint != nil,
            truthLine: presentation.displayEffectiveTruthLine,
            followUpText: {
                guard let trimmedFollowUp, !trimmedFollowUp.isEmpty else { return nil }
                return "自动跟进：\(trimmedFollowUp)"
            }()
        )
    }

    static func items(
        context: ProjectGovernanceCompactMetaContext,
        showAxisLegend: Bool,
        showCallout: Bool,
        displayStyle: ProjectGovernanceCompactSummaryDisplayStyle
    ) -> [ProjectGovernanceCompactMetaItem] {
        var items: [ProjectGovernanceCompactMetaItem] = []
        if showAxisLegend {
            items.append(ProjectGovernanceCompactMetaItem(kind: .axisLegend, text: context.axisLegendText))
        }

        if displayStyle.prefersCondensedMeta {
            if context.shouldPreferCalloutInCondensedMeta,
               showCallout,
               let callout = context.calloutMessage {
                items.append(ProjectGovernanceCompactMetaItem(kind: .callout, text: callout))
            } else if let truthLine = context.truthLine {
                items.append(ProjectGovernanceCompactMetaItem(kind: .truthLine, text: truthLine))
            } else if let followUpText = context.followUpText {
                items.append(ProjectGovernanceCompactMetaItem(kind: .followUp, text: followUpText))
            } else if showCallout, let callout = context.calloutMessage {
                items.append(ProjectGovernanceCompactMetaItem(kind: .callout, text: callout))
            }
            return items
        }

        if let governanceModelText = context.governanceModelText {
            items.append(ProjectGovernanceCompactMetaItem(kind: .governanceModel, text: governanceModelText))
        }

        if showCallout, let callout = context.calloutMessage {
            items.append(ProjectGovernanceCompactMetaItem(kind: .callout, text: callout))
        }

        if let truthLine = context.truthLine {
            items.append(ProjectGovernanceCompactMetaItem(kind: .truthLine, text: truthLine))
        }

        if let followUpText = context.followUpText {
            items.append(ProjectGovernanceCompactMetaItem(kind: .followUp, text: followUpText))
        }

        return items
    }
}

struct ProjectGovernanceCompactSummaryView: View {
    let presentation: ProjectGovernancePresentation
    var showCallout: Bool
    var showAxisLegend: Bool
    var displayStyle: ProjectGovernanceCompactSummaryDisplayStyle
    var onExecutionTierTap: (() -> Void)?
    var onSupervisorTierTap: (() -> Void)?
    var onReviewCadenceTap: (() -> Void)?
    var onStatusTap: (() -> Void)?
    var onCalloutTap: (() -> Void)?

    init(
        presentation: ProjectGovernancePresentation,
        showCallout: Bool = true,
        showAxisLegend: Bool = false,
        displayStyle: ProjectGovernanceCompactSummaryDisplayStyle = .regular,
        onExecutionTierTap: (() -> Void)? = nil,
        onSupervisorTierTap: (() -> Void)? = nil,
        onReviewCadenceTap: (() -> Void)? = nil,
        onStatusTap: (() -> Void)? = nil,
        onCalloutTap: (() -> Void)? = nil
    ) {
        self.presentation = presentation
        self.showCallout = showCallout
        self.showAxisLegend = showAxisLegend
        self.displayStyle = displayStyle
        self.onExecutionTierTap = onExecutionTierTap
        self.onSupervisorTierTap = onSupervisorTierTap
        self.onReviewCadenceTap = onReviewCadenceTap
        self.onStatusTap = onStatusTap
        self.onCalloutTap = onCalloutTap
    }

    init(
        presentation: ProjectGovernancePresentation,
        configuration: ProjectGovernanceCompactSummarySurfaceConfiguration,
        showCallout: Bool = true,
        onExecutionTierTap: (() -> Void)? = nil,
        onSupervisorTierTap: (() -> Void)? = nil,
        onReviewCadenceTap: (() -> Void)? = nil,
        onStatusTap: (() -> Void)? = nil,
        onCalloutTap: (() -> Void)? = nil
    ) {
        self.init(
            presentation: presentation,
            showCallout: showCallout,
            showAxisLegend: configuration.showAxisLegend,
            displayStyle: configuration.displayStyle,
            onExecutionTierTap: onExecutionTierTap,
            onSupervisorTierTap: onSupervisorTierTap,
            onReviewCadenceTap: onReviewCadenceTap,
            onStatusTap: onStatusTap,
            onCalloutTap: onCalloutTap
        )
    }

    private var metaContext: ProjectGovernanceCompactMetaContext {
        ProjectGovernanceCompactMetaResolver.context(
            presentation: presentation,
            displayStyle: displayStyle
        )
    }

    private var metaItems: [ProjectGovernanceCompactMetaItem] {
        ProjectGovernanceCompactMetaResolver.items(
            context: metaContext,
            showAxisLegend: showAxisLegend,
            showCallout: showCallout,
            displayStyle: displayStyle
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: displayStyle.verticalSpacing) {
            ProjectGovernanceBadge(
                presentation: presentation,
                compact: true,
                denseCompactLayout: displayStyle.badgeDenseLayout,
                onExecutionTierTap: onExecutionTierTap,
                onSupervisorTierTap: onSupervisorTierTap,
                onReviewCadenceTap: onReviewCadenceTap,
                onStatusTap: onStatusTap
            )

            ForEach(Array(metaItems.enumerated()), id: \.offset) { _, item in
                compactMetaRow(item)
            }
        }
        .padding(displayStyle.outerPadding)
        .background(
            RoundedRectangle(cornerRadius: displayStyle.cornerRadius)
                .fill(containerBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: displayStyle.cornerRadius)
                .stroke(containerBorderColor, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func interactiveSurface<Content: View>(
        help: String,
        action: (() -> Void)?,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let surface = content()
            .contentShape(Rectangle())

        if let action {
            surface
                .highPriorityGesture(TapGesture().onEnded { action() })
                .help(help)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
                .accessibilityAction(.default) { action() }
        } else {
            surface
        }
    }

    private var executionTint: Color {
        ProjectGovernanceComposerAccentTone.forExecutionTier(
            presentation.effectiveExecutionTier ?? presentation.executionTier
        ).color
    }

    private var supervisorTint: Color {
        ProjectGovernanceComposerAccentTone.forSupervisorTier(
            presentation.effectiveSupervisorInterventionTier ?? presentation.supervisorInterventionTier
        ).color
    }

    private var reviewTint: Color {
        ProjectGovernanceComposerAccentTone.forReviewPolicy(presentation.reviewPolicyMode).color
    }

    private var containerBackground: LinearGradient {
        let executionOpacity: Double
        let reviewOpacity: Double
        let supervisorOpacity: Double

        switch displayStyle {
        case .regular:
            executionOpacity = 0.08
            reviewOpacity = 0.07
            supervisorOpacity = 0.07
        case .dense:
            executionOpacity = 0.06
            reviewOpacity = 0.05
            supervisorOpacity = 0.05
        case .watchlist:
            executionOpacity = 0.05
            reviewOpacity = 0.04
            supervisorOpacity = 0.04
        }

        return LinearGradient(
            colors: [
                executionTint.opacity(executionOpacity),
                reviewTint.opacity(reviewOpacity),
                Color(nsColor: .windowBackgroundColor),
                supervisorTint.opacity(supervisorOpacity)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var containerBorderColor: Color {
        switch presentation.compactCalloutTone {
        case .invalid:
            return Color.red.opacity(0.22)
        case .warning:
            return Color.orange.opacity(0.22)
        case .info:
            return Color.secondary.opacity(0.16)
        case .neutral:
            return Color.secondary.opacity(0.12)
        }
    }

    private func metaCalloutRow(_ callout: String) -> some View {
        let toneColor = calloutColor(presentation.compactCalloutTone)
        let iconName: String = switch presentation.compactCalloutTone {
        case .invalid:
            "exclamationmark.triangle.fill"
        case .warning:
            "eye.trianglebadge.exclamationmark"
        case .info:
            "info.circle"
        case .neutral:
            "line.3.horizontal.decrease.circle"
        }

        return interactiveMetaRow(
            iconName: iconName,
            text: callout,
            color: toneColor,
            action: onCalloutTap
        )
    }

    @ViewBuilder
    private func compactMetaRow(_ item: ProjectGovernanceCompactMetaItem) -> some View {
        switch item.kind {
        case .axisLegend:
            interactiveMetaRow(
                iconName: "slider.horizontal.3",
                text: item.text,
                color: .secondary,
                action: onCalloutTap
            )
        case .governanceModel:
            interactiveMetaRow(
                iconName: "point.3.connected.trianglepath",
                text: item.text,
                color: .secondary,
                action: onCalloutTap
            )
        case .callout:
            metaCalloutRow(item.text)
        case .truthLine:
            metaRow(
                iconName: "scope",
                text: item.text,
                color: .secondary
            )
        case .followUp:
            metaRow(
                iconName: "arrow.triangle.branch",
                text: item.text,
                color: .secondary
            )
        }
    }

    private func metaRow(
        iconName: String,
        text: String,
        color: Color
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: iconName)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(color)
                .frame(width: 12, alignment: .center)

            Text(text)
                .font(.caption2)
                .foregroundStyle(color)
                .lineLimit(displayStyle.metaLineLimit)
                .minimumScaleFactor(displayStyle == .dense ? 0.84 : 0.9)

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func interactiveMetaRow(
        iconName: String,
        text: String,
        color: Color,
        action: (() -> Void)?
    ) -> some View {
        if let action {
            interactiveSurface(
                help: "打开项目治理概览",
                action: action
            ) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: iconName)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(color)
                        .frame(width: 12, alignment: .center)

                    Text(text)
                        .font(.caption2)
                        .foregroundStyle(color)
                        .lineLimit(displayStyle.metaLineLimit)
                        .minimumScaleFactor(displayStyle == .dense ? 0.84 : 0.9)

                    Spacer(minLength: 4)

                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
        } else {
            metaRow(iconName: iconName, text: text, color: color)
        }
    }

    private func calloutColor(_ tone: ProjectGovernanceCalloutTone) -> Color {
        switch tone {
        case .invalid:
            return .red
        case .warning:
            return .orange
        case .info:
            return .secondary
        case .neutral:
            return .secondary
        }
    }
}

struct ProjectGovernanceBadge: View {
    let presentation: ProjectGovernancePresentation
    var compact: Bool = false
    var denseCompactLayout: Bool = false
    var onExecutionTierTap: (() -> Void)? = nil
    var onSupervisorTierTap: (() -> Void)? = nil
    var onReviewCadenceTap: (() -> Void)? = nil
    var onStatusTap: (() -> Void)? = nil

    private var model: ProjectGovernanceThreeAxisOverviewPresentation {
        ProjectGovernanceThreeAxisOverviewPresentation(presentation: presentation)
    }

    private var executionTint: Color {
        ProjectGovernanceComposerAccentTone.forExecutionTier(
            presentation.effectiveExecutionTier ?? presentation.executionTier
        ).color
    }

    private var supervisorTint: Color {
        ProjectGovernanceComposerAccentTone.forSupervisorTier(
            presentation.effectiveSupervisorInterventionTier ?? presentation.supervisorInterventionTier
        ).color
    }

    private var reviewTint: Color {
        ProjectGovernanceComposerAccentTone.forReviewPolicy(presentation.reviewPolicyMode).color
    }

    private var statusTone: Color {
        if !presentation.invalidMessages.isEmpty {
            return .red
        }
        if presentation.hasHighRiskWarning {
            return .orange
        }
        if !presentation.warningMessages.isEmpty {
            return .yellow
        }
        return .secondary
    }

    private var statusSummary: String? {
        if !presentation.invalidMessages.isEmpty {
            return "治理冲突 · 当前已 fail-closed 收束"
        }
        if presentation.hasHighRiskWarning {
            return "高风险组合 · \(model.bridgeLabel)"
        }
        if !presentation.warningMessages.isEmpty {
            return "低于推荐监督强度"
        }
        return nil
    }

    private var reviewBadgeLine: String {
        "HB \(governanceDisplayDurationLabel(presentation.progressHeartbeatSeconds)) · Review \(presentation.displayReviewPolicyName)"
    }

    private var reviewDetailLine: String {
        "Pulse \(governanceDisplayDurationLabel(presentation.reviewPulseSeconds)) · Brainstorm \(governanceDisplayDurationLabel(presentation.brainstormReviewSeconds))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? (denseCompactLayout ? 5 : 6) : 8) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: compact ? (denseCompactLayout ? 6 : 8) : 10) {
                    dialBadge(
                        token: model.executionDial.token,
                        label: model.executionDial.label,
                        selectedIndex: model.executionDial.selectedIndex,
                        stepCount: model.executionDial.markerTokens.count,
                        tint: executionTint,
                        action: onExecutionTierTap
                    )

                    connectorBadge

                    dialBadge(
                        token: model.supervisorDial.token,
                        label: model.supervisorDial.label,
                        selectedIndex: model.supervisorDial.selectedIndex,
                        stepCount: model.supervisorDial.markerTokens.count,
                        tint: supervisorTint,
                        action: onSupervisorTierTap
                    )

                    reviewBadge
                }

                VStack(alignment: .leading, spacing: compact ? (denseCompactLayout ? 6 : 8) : 10) {
                    HStack(alignment: .center, spacing: compact ? (denseCompactLayout ? 6 : 8) : 10) {
                        dialBadge(
                            token: model.executionDial.token,
                            label: model.executionDial.label,
                            selectedIndex: model.executionDial.selectedIndex,
                            stepCount: model.executionDial.markerTokens.count,
                            tint: executionTint,
                            action: onExecutionTierTap
                        )

                        connectorBadge

                        dialBadge(
                            token: model.supervisorDial.token,
                            label: model.supervisorDial.label,
                            selectedIndex: model.supervisorDial.selectedIndex,
                            stepCount: model.supervisorDial.markerTokens.count,
                            tint: supervisorTint,
                            action: onSupervisorTierTap
                        )
                    }

                    reviewBadge
                }
            }

            if let statusSummary {
                interactiveSurface(
                    help: "打开项目治理概览",
                    action: onStatusTap,
                    defaultHelp: "打开项目治理概览"
                ) {
                    HStack(alignment: .center, spacing: 6) {
                        Image(systemName: !presentation.invalidMessages.isEmpty ? "exclamationmark.triangle.fill" : "eye.trianglebadge.exclamationmark")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(statusTone)
                        Text(statusSummary)
                            .font(.caption2)
                            .foregroundStyle(statusTone)
                            .lineLimit(denseCompactLayout ? 2 : 1)
                    }
                }
            }
        }
    }

    private func dialBadge(
        token: String,
        label: String,
        selectedIndex: Int,
        stepCount: Int,
        tint: Color,
        action: (() -> Void)?
    ) -> some View {
        let dial = VStack(spacing: compact ? (denseCompactLayout ? 3 : 4) : 5) {
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.12), lineWidth: compact ? 4 : 5)

                Circle()
                    .trim(from: 0.18, to: dialTrimEnd(selectedIndex: selectedIndex, stepCount: stepCount))
                    .stroke(
                        tint,
                        style: StrokeStyle(lineWidth: compact ? 5 : 6, lineCap: .round)
                    )
                    .rotationEffect(.degrees(140))

                Circle()
                    .fill(Color(nsColor: .windowBackgroundColor))
                    .padding(compact ? 9 : 10)

                Text(token)
                    .font(.system(size: compact ? 13 : 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
            }
            .frame(
                width: compact ? (denseCompactLayout ? 36 : 40) : 48,
                height: compact ? (denseCompactLayout ? 36 : 40) : 48
            )

            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(minWidth: compact ? (denseCompactLayout ? 44 : 48) : 58)

        return interactiveSurface(
            help: "打开对应的项目治理设置",
            action: action,
            defaultHelp: "打开项目治理设置"
        ) {
            dial
        }
    }

    private var connectorBadge: some View {
        interactiveSurface(
            help: "打开项目治理概览",
            action: onStatusTap,
            defaultHelp: "打开项目治理概览"
        ) {
            VStack(spacing: compact ? (denseCompactLayout ? 3 : 4) : 5) {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Color.red.opacity(0.95), Color.red.opacity(0.65)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(
                        width: compact ? (denseCompactLayout ? 24 : 28) : 34,
                        height: compact ? (denseCompactLayout ? 4 : 5) : 6
                    )

                Text(model.bridgeLabel)
                    .font(.system(compact ? .caption2 : .caption, design: .monospaced).weight(.semibold))
                    .foregroundStyle(.primary)

                Text(model.bridgeTitle)
                    .font(.caption2)
                    .foregroundStyle(statusTone)
                    .lineLimit(1)
            }
            .frame(minWidth: compact ? (denseCompactLayout ? 48 : 52) : 64)
        }
    }

    private var reviewBadge: some View {
        interactiveSurface(
            help: "打开 Heartbeat / Review 设置",
            action: onReviewCadenceTap,
            defaultHelp: "打开 Heartbeat / Review 设置"
        ) {
            VStack(alignment: .leading, spacing: compact ? 2 : 3) {
                Text(reviewBadgeLine)
                    .font(.system(compact ? .caption2 : .caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(reviewTint)
                    .lineLimit(1)
                    .minimumScaleFactor(denseCompactLayout ? 0.84 : 0.9)

                Text(reviewDetailLine)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(denseCompactLayout ? 0.84 : 0.9)
            }
            .padding(.horizontal, compact ? (denseCompactLayout ? 7 : 8) : 10)
            .padding(.vertical, compact ? (denseCompactLayout ? 5 : 6) : 7)
            .background(
                RoundedRectangle(cornerRadius: compact ? 10 : 12)
                    .fill(reviewTint.opacity(0.10))
            )
        }
    }

    @ViewBuilder
    private func interactiveSurface<Content: View>(
        help: String,
        action: (() -> Void)?,
        defaultHelp: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let surface = content()
            .contentShape(Rectangle())

        if let action {
            surface
                .highPriorityGesture(TapGesture().onEnded { action() })
                .help(help)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
                .accessibilityAction(.default) { action() }
        } else {
            surface
                .help(defaultHelp)
        }
    }

    private func dialTrimEnd(selectedIndex: Int, stepCount: Int) -> CGFloat {
        guard stepCount > 1 else { return 0.90 }
        let clampedIndex = min(max(selectedIndex, 0), stepCount - 1)
        let progress = CGFloat(clampedIndex) / CGFloat(stepCount - 1)
        return 0.18 + (progress * 0.72)
    }
}

struct ProjectGovernanceInspector: View {
    let presentation: ProjectGovernancePresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !presentation.invalidMessages.isEmpty {
                governanceMessageBlock(
                    title: "配置冲突",
                    messages: presentation.invalidMessages,
                    color: .red
                )
            } else if !presentation.warningMessages.isEmpty {
                governanceMessageBlock(
                    title: presentation.hasHighRiskWarning ? "高风险组合" : "风险提示",
                    messages: presentation.warningMessages,
                    color: .orange
                )
            }

            if let effectiveTruthLine = presentation.displayEffectiveTruthLine {
                governanceRow("治理真相") {
                    Text(effectiveTruthLine)
                        .foregroundStyle(.secondary)
                }
            }

            governanceRow("A-Tier") {
                Text("预设：\(presentation.executionTier.shortToken) \(presentation.executionTier.localizedShortLabel)")
                if let effectiveExecutionTier = presentation.effectiveExecutionTier {
                    Text("生效：\(effectiveExecutionTier.shortToken) \(effectiveExecutionTier.localizedShortLabel)")
                        .foregroundStyle(.secondary)
                }
            }

            if let runtimeReadiness = presentation.runtimeReadiness {
                governanceRow("A-Tier Runtime Ready") {
                    Text(runtimeReadiness.summaryLine)
                    if runtimeReadiness.runtimeReady {
                        Text(runtimeReadiness.runtimeReadyLine)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(runtimeReadiness.runtimeReadyLine)
                            .foregroundStyle(Color.orange)
                    }
                    if let missingSummary = runtimeReadiness.missingSummaryLine {
                        Text(missingSummary)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            governanceRow("S-Tier") {
                Text("预设：\(presentation.supervisorInterventionTier.shortToken) \(presentation.supervisorInterventionTier.localizedShortLabel)")
                if let recommendedSupervisorTier = presentation.recommendedSupervisorInterventionTier {
                    Text("建议：\(recommendedSupervisorTier.shortToken) \(recommendedSupervisorTier.localizedShortLabel)")
                        .foregroundStyle(.secondary)
                }
                if let effectiveSupervisorTier = presentation.effectiveSupervisorInterventionTier {
                    Text("生效：\(effectiveSupervisorTier.shortToken) \(effectiveSupervisorTier.localizedShortLabel)")
                        .foregroundStyle(.secondary)
                }
            }

            if let strengthBand = presentation.projectAIStrengthBand {
                governanceRow("项目 AI 强弱") {
                    Text(
                        "\(ProjectGovernanceActivityDisplay.displayValue(label: "project_ai_strength", value: strengthBand.displayName))\(presentation.projectAIStrengthConfidence.map { " · 置信度 \(Int(($0 * 100).rounded()))%" } ?? "")"
                    )
                    if let mode = presentation.supervisorAdaptationMode {
                        Text("适配模式：\(mode.localizedDisplayName)")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if !presentation.projectAIStrengthReasons.isEmpty {
                governanceRow("评估依据") {
                    Text(presentation.projectAIStrengthReasons.joined(separator: " · "))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            if let recommendedWorkOrderDepth = presentation.recommendedWorkOrderDepth,
               let effectiveWorkOrderDepth = presentation.effectiveWorkOrderDepth {
                governanceRow("派工深度") {
                    Text("建议：\(ProjectGovernanceActivityDisplay.displayValue(label: "work_order_depth", value: recommendedWorkOrderDepth.displayName))")
                    Text("生效：\(ProjectGovernanceActivityDisplay.displayValue(label: "work_order_depth", value: effectiveWorkOrderDepth.displayName))")
                        .foregroundStyle(.secondary)
                }
            }

            governanceRow("Heartbeat / Review") {
                Text(presentation.displayReviewPolicyName)
                Text(presentation.reviewCadenceText)
                    .foregroundStyle(.secondary)
            }

            if let configured = presentation.cadenceConfiguredSummaryText,
               let recommended = presentation.cadenceRecommendedSummaryText,
               let effective = presentation.cadenceEffectiveSummaryText {
                governanceRow("节奏解析") {
                    Text("配置：\(configured)")
                    Text("建议：\(recommended)")
                        .foregroundStyle(.secondary)
                    Text("生效：\(effective)")
                        .foregroundStyle(.secondary)
                }
            }

            if let cadenceReason = presentation.cadenceReasonSummaryText {
                governanceRow("生效原因") {
                    Text(cadenceReason)
                        .foregroundStyle(.secondary)
                }
            }

            if let cadenceDue = presentation.cadenceDueSummaryText {
                governanceRow("到期判断") {
                    Text(cadenceDue)
                        .foregroundStyle(.secondary)
                }
            }

            if let followUpRhythmSummary = presentation.followUpRhythmSummary,
               !followUpRhythmSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                governanceRow("自动跟进节奏") {
                    Text(followUpRhythmSummary)
                        .foregroundStyle(.secondary)
                }
            }

            governanceRow("指导注入") {
                Text(presentation.guidanceSummary)
                Text(presentation.guidanceAckSummary)
                    .foregroundStyle(.secondary)
            }

            governanceRow("事件驱动审查") {
                Text(presentation.eventDrivenReviewEnabled ? "已开启" : "已关闭")
                if !presentation.eventReviewTriggerLabels.isEmpty {
                    Text(presentation.eventReviewTriggerLabels.joined(separator: ", "))
                        .foregroundStyle(.secondary)
                }
            }

            governanceRow("上下文供给") {
                Text("coder：\(presentation.projectMemoryCeiling.rawValue)")
                Text("supervisor：\(presentation.supervisorReviewMemoryCeiling.rawValue)")
                    .foregroundStyle(.secondary)
            }

            governanceRow("能力边界") {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(presentation.capabilityBoundaryItems, id: \.label) { item in
                        Text("\(item.label)：\(item.summary)")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            governanceRow("能力包") {
                Text(presentation.capabilityLabels.isEmpty ? "无" : presentation.capabilityLabels.joined(separator: ", "))
                    .lineLimit(4)
                    .textSelection(.enabled)
            }

            governanceRow("当前状态") {
                Text(presentation.statusSummary)
                    .foregroundStyle(.secondary)
            }

            if !presentation.adaptationSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                governanceRow("自适应监督") {
                    Text(presentation.adaptationSummary)
                        .foregroundStyle(.secondary)
                }
            }

            governanceRow("收束 / 限制") {
                Text(presentation.clampSummary)
                    .foregroundStyle(.secondary)
            }

            governanceRow("治理来源") {
                Text(presentation.compatSourceLabel)
                    .foregroundStyle(.secondary)
                if let detail = presentation.compatSourceDetail {
                    Text(detail)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func governanceRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
                .font(.subheadline)
        }
    }

    private func governanceMessageBlock(title: String, messages: [String], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
            ForEach(messages, id: \.self) { message in
                Text(message)
                    .font(.caption)
            }
        }
        .foregroundStyle(color)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(color.opacity(0.10))
        )
    }
}

func governanceDurationLabel(_ seconds: Int) -> String {
    guard seconds > 0 else { return "off" }
    if seconds % 3600 == 0 {
        return "\(seconds / 3600)h"
    }
    return "\(max(1, seconds / 60))m"
}

func governanceDisplayDurationLabel(_ seconds: Int) -> String {
    let raw = governanceDurationLabel(seconds)
    return raw == "off" ? "关闭" : raw
}

extension AXProjectReviewPolicyMode {
    var localizedShortLabel: String {
        switch self {
        case .off:
            return "关闭"
        case .milestoneOnly:
            return "里程碑"
        case .periodic:
            return "周期"
        case .hybrid:
            return "混合"
        case .aggressive:
            return "高压"
        }
    }

    var localizedDisplayName: String {
        localizedShortLabel
    }

    var shortLabel: String {
        switch self {
        case .off:
            return "Off"
        case .milestoneOnly:
            return "Milestone"
        case .periodic:
            return "Periodic"
        case .hybrid:
            return "Hybrid"
        case .aggressive:
            return "Aggressive"
        }
    }

    var oneLineSummary: String {
        switch self {
        case .off:
            return "只保留手动请求和 A 档强制检查点，不做周期审查。"
        case .milestoneOnly:
            return "只在 blocker、完成前等关键里程碑审查，不跑周期脉冲。"
        case .periodic:
            return "按固定节奏做脉冲审查，不额外做脑暴复盘。"
        case .hybrid:
            return "周期脉冲 + 脑暴复盘 + 事件触发一起工作，是默认推荐档。"
        case .aggressive:
            return "高频复盘并放大失败 / 无进展类触发，更适合救火和高风险项目。"
        }
    }

    var supportsPulseCadence: Bool {
        switch self {
        case .periodic, .hybrid, .aggressive:
            return true
        case .off, .milestoneOnly:
            return false
        }
    }

    var supportsBrainstormCadence: Bool {
        switch self {
        case .hybrid, .aggressive:
            return true
        case .off, .milestoneOnly, .periodic:
            return false
        }
    }

    var supportsEventDrivenReview: Bool {
        switch self {
        case .off:
            return false
        case .milestoneOnly, .periodic, .hybrid, .aggressive:
            return true
        }
    }

    var displayName: String {
        switch self {
        case .off:
            return "Off"
        case .milestoneOnly:
            return "Milestone Only"
        case .periodic:
            return "Periodic"
        case .hybrid:
            return "Hybrid"
        case .aggressive:
            return "Aggressive"
        }
    }
}

extension AXProjectReviewTrigger {
    var localizedDisplayName: String {
        switch self {
        case .periodicHeartbeat:
            return "周期心跳"
        case .periodicPulse:
            return "周期脉冲审查"
        case .failureStreak:
            return "连续失败"
        case .noProgressWindow:
            return "进展停滞"
        case .blockerDetected:
            return "发现阻塞"
        case .planDrift:
            return "计划漂移"
        case .preHighRiskAction:
            return "高风险前审查"
        case .preDoneSummary:
            return "完成前审查"
        case .manualRequest:
            return "手动请求"
        case .userOverride:
            return "用户覆盖"
        }
    }

    var governanceSummary: String {
        switch self {
        case .periodicHeartbeat:
            return "轻量进度检查；不是战略 review。"
        case .periodicPulse:
            return "按周期节奏做一次常规 pulse review。"
        case .failureStreak:
            return "连续失败达到阈值时，触发一次补救型 review。"
        case .noProgressWindow:
            return "长时间没有进展时，触发 brainstorm / rescue review。"
        case .blockerDetected:
            return "发现 blocker 或卡点时，要求 supervisor 介入看方向。"
        case .planDrift:
            return "执行路径开始偏离最初交付目标时触发。"
        case .preHighRiskAction:
            return "做高风险动作前先 review，一般不会让它裸跑。"
        case .preDoneSummary:
            return "准备宣布完成前做收口审查。"
        case .manualRequest:
            return "用户或系统手动要求 review。"
        case .userOverride:
            return "用户强制覆盖当前策略。"
        }
    }

    var displayName: String {
        switch self {
        case .periodicHeartbeat:
            return "periodic heartbeat"
        case .periodicPulse:
            return "periodic pulse"
        case .failureStreak:
            return "failure streak"
        case .noProgressWindow:
            return "no progress window"
        case .blockerDetected:
            return "blocker detected"
        case .planDrift:
            return "plan drift"
        case .preHighRiskAction:
            return "pre-high-risk"
        case .preDoneSummary:
            return "pre-done"
        case .manualRequest:
            return "manual request"
        case .userOverride:
            return "user override"
        }
    }
}

extension AXProjectAIStrengthBand {
    var displayName: String {
        switch self {
        case .unknown:
            return "Unknown"
        case .weak:
            return "Weak"
        case .developing:
            return "Developing"
        case .capable:
            return "Capable"
        case .strong:
            return "Strong"
        }
    }
}

extension AXProjectSupervisorAdaptationMode {
    var displayName: String {
        switch self {
        case .manualOnly:
            return "Manual Only"
        case .raiseOnly:
            return "Raise Only"
        case .bidirectional:
            return "Bidirectional"
        }
    }

    var localizedDisplayName: String {
        switch self {
        case .manualOnly:
            return "手动保持"
        case .raiseOnly:
            return "只抬不降"
        case .bidirectional:
            return "双向调节"
        }
    }
}

extension AXProjectSupervisorWorkOrderDepth {
    var displayName: String {
        switch self {
        case .none:
            return "None"
        case .brief:
            return "Brief"
        case .milestoneContract:
            return "Milestone Contract"
        case .executionReady:
            return "Execution Ready"
        case .stepLockedRescue:
            return "Step-Locked Rescue"
        }
    }
}

extension SupervisorGuidanceInterventionMode {
    var displayName: String {
        switch self {
        case .observeOnly:
            return "Observe Only"
        case .suggestNextSafePoint:
            return "Suggest At Safe Point"
        case .replanNextSafePoint:
            return "Replan At Safe Point"
        case .stopImmediately:
            return "Stop Immediately"
        }
    }
}
