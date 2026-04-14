import Foundation

enum ProjectGovernanceStatusBadgeTone: Equatable, Sendable {
    case current
    case configured
    case effective
    case recommended
    case safeFloor
    case belowSafeFloor
}

struct ProjectGovernanceStatusBadge: Equatable, Sendable {
    let label: String
    let tone: ProjectGovernanceStatusBadgeTone
}

struct ProjectExecutionTierCardPresentation: Equatable, Sendable {
    let statusBadges: [ProjectGovernanceStatusBadge]
    let accessibilityStateLabel: String

    init(
        tier: AXProjectExecutionTier,
        configuredTier: AXProjectExecutionTier,
        effectiveTier: AXProjectExecutionTier
    ) {
        if configuredTier == tier && effectiveTier == tier {
            statusBadges = [
                ProjectGovernanceStatusBadge(label: ProjectGovernanceStatusBadgeTone.current.localizedLabel, tone: .current)
            ]
        } else {
            var badges: [ProjectGovernanceStatusBadge] = []
            if configuredTier == tier {
                badges.append(
                    ProjectGovernanceStatusBadge(
                        label: ProjectGovernanceStatusBadgeTone.configured.localizedLabel,
                        tone: .configured
                    )
                )
            }
            if effectiveTier == tier {
                badges.append(
                    ProjectGovernanceStatusBadge(
                        label: ProjectGovernanceStatusBadgeTone.effective.localizedLabel,
                        tone: .effective
                    )
                )
            }
            statusBadges = badges
        }

        switch (configuredTier == tier, effectiveTier == tier) {
        case (true, true):
            accessibilityStateLabel = "当前"
        case (true, false):
            accessibilityStateLabel = "已配置"
        case (false, true):
            accessibilityStateLabel = "生效中"
        default:
            accessibilityStateLabel = "可用"
        }
    }
}

struct ProjectSupervisorTierCardPresentation: Equatable, Sendable {
    let statusBadges: [ProjectGovernanceStatusBadge]
    let accessibilityStateLabel: String

    init(
        tier: AXProjectSupervisorInterventionTier,
        currentExecutionTier: AXProjectExecutionTier,
        configuredTier: AXProjectSupervisorInterventionTier,
        effectiveTier: AXProjectSupervisorInterventionTier
    ) {
        var badges: [ProjectGovernanceStatusBadge] = []

        if configuredTier == tier && effectiveTier == tier {
            badges.append(
                ProjectGovernanceStatusBadge(
                    label: ProjectGovernanceStatusBadgeTone.current.localizedLabel,
                    tone: .current
                )
            )
        } else {
            if configuredTier == tier {
                badges.append(
                    ProjectGovernanceStatusBadge(
                        label: ProjectGovernanceStatusBadgeTone.configured.localizedLabel,
                        tone: .configured
                    )
                )
            }
            if effectiveTier == tier {
                badges.append(
                    ProjectGovernanceStatusBadge(
                        label: ProjectGovernanceStatusBadgeTone.effective.localizedLabel,
                        tone: .effective
                    )
                )
            }
        }

        if tier == currentExecutionTier.defaultSupervisorInterventionTier {
            badges.append(
                ProjectGovernanceStatusBadge(
                    label: ProjectGovernanceStatusBadgeTone.recommended.localizedLabel,
                    tone: .recommended
                )
            )
        }
        if tier == currentExecutionTier.minimumSafeSupervisorTier {
            badges.append(
                ProjectGovernanceStatusBadge(
                    label: ProjectGovernanceStatusBadgeTone.safeFloor.localizedLabel,
                    tone: .safeFloor
                )
            )
        } else if tier < currentExecutionTier.minimumSafeSupervisorTier {
            badges.append(
                ProjectGovernanceStatusBadge(
                    label: ProjectGovernanceStatusBadgeTone.belowSafeFloor.localizedLabel,
                    tone: .belowSafeFloor
                )
            )
        }

        statusBadges = badges

        switch (configuredTier == tier, effectiveTier == tier) {
        case (true, true):
            accessibilityStateLabel = "当前"
        case (true, false):
            accessibilityStateLabel = "已配置"
        case (false, true):
            accessibilityStateLabel = "生效中"
        default:
            accessibilityStateLabel = "可用"
        }
    }
}

struct ProjectHeartbeatReviewBaselineInput: Equatable, Sendable {
    let trigger: SupervisorReviewTrigger
    let reviewLevel: SupervisorReviewLevel
    let runKind: SupervisorReviewRunKind
    let reason: String
}

struct ProjectGovernanceParameterMatrixRowPresentation: Equatable, Sendable {
    let title: String
    let configuredValue: String
    let recommendedValue: String
    let effectiveValue: String
    let sourceSummary: String
    let detail: String?
}

struct ProjectGovernanceSceneParameterMatrixPresentation: Equatable, Sendable {
    let sceneLabel: String
    let cadenceRows: [ProjectGovernanceParameterMatrixRowPresentation]
    let continuityRows: [ProjectGovernanceParameterMatrixRowPresentation]
    let executionRows: [ProjectGovernanceParameterMatrixRowPresentation]
    let closeoutRows: [ProjectGovernanceParameterMatrixRowPresentation]
}

struct ProjectHeartbeatReviewEditorPresentation: Equatable, Sendable {
    let mandatoryTriggers: [AXProjectReviewTrigger]
    let optionalTriggers: [AXProjectReviewTrigger]
    let derivedTriggers: [AXProjectReviewTrigger]
    let baselineDecisionInput: ProjectHeartbeatReviewBaselineInput
    let baselineDecision: SupervisorReviewPolicyDecision
    let baselineDecisionSummary: String
    let sceneParameterMatrix: ProjectGovernanceSceneParameterMatrixPresentation

    init(
        configuredExecutionTier: AXProjectExecutionTier,
        configuredReviewPolicyMode: AXProjectReviewPolicyMode,
        reviewPulseSeconds: Int,
        brainstormReviewSeconds: Int,
        resolvedGovernance: AXProjectResolvedGovernanceState,
        projectConfig: AXProjectConfig? = nil,
        configuredSupervisorRecentRawContextProfile: XTSupervisorRecentRawContextProfile = .defaultProfile,
        configuredSupervisorReviewMemoryDepth: XTSupervisorReviewMemoryDepthProfile = .defaultProfile,
        supervisorPrivacyMode: XTPrivacyMode = .defaultMode
    ) {
        let mandatory = configuredExecutionTier.mandatoryReviewTriggers
        mandatoryTriggers = mandatory
        optionalTriggers = AXProjectReviewTrigger.governanceOptionalSelectableCases.filter {
            !mandatory.contains($0)
        }

        var derived: [AXProjectReviewTrigger] = [.manualRequest, .userOverride]
        if configuredReviewPolicyMode.supportsPulseCadence && reviewPulseSeconds > 0 {
            derived.append(.periodicPulse)
        }
        if configuredReviewPolicyMode.supportsBrainstormCadence && brainstormReviewSeconds > 0 {
            derived.append(.noProgressWindow)
        }
        derivedTriggers = AXProjectReviewTrigger.normalizedList(derived)

        if configuredReviewPolicyMode.supportsBrainstormCadence && brainstormReviewSeconds > 0 {
            baselineDecisionInput = ProjectHeartbeatReviewBaselineInput(
                trigger: .noProgressWindow,
                reviewLevel: .r2Strategic,
                runKind: .brainstorm,
                reason: "brainstorm cadence"
            )
        } else if configuredReviewPolicyMode.supportsPulseCadence && reviewPulseSeconds > 0 {
            baselineDecisionInput = ProjectHeartbeatReviewBaselineInput(
                trigger: .periodicPulse,
                reviewLevel: .r1Pulse,
                runKind: .pulse,
                reason: "pulse cadence"
            )
        } else {
            baselineDecisionInput = ProjectHeartbeatReviewBaselineInput(
                trigger: .manualRequest,
                reviewLevel: .r1Pulse,
                runKind: .manual,
                reason: "manual review"
            )
        }

        baselineDecision = SupervisorReviewPolicyEngine.resolve(
            governance: resolvedGovernance,
            trigger: baselineDecisionInput.trigger,
            requestedReviewLevel: baselineDecisionInput.reviewLevel,
            verdict: .watch,
            requestedDeliveryMode: .contextAppend,
            requestedAckRequired: false,
            runKind: baselineDecisionInput.runKind
        )
        let reason = Self.localizedBaselineReason(baselineDecisionInput.reason)
        let trigger = ProjectGovernanceActivityDisplay.displayValue(
            label: "trigger",
            value: baselineDecisionInput.trigger.displayName
        )
        let level = ProjectGovernanceActivityDisplay.displayValue(
            label: "level",
            value: baselineDecision.reviewLevel.displayName
        )
        let intervention = ProjectGovernanceActivityDisplay.displayValue(
            label: "intervention",
            value: baselineDecision.interventionMode.displayName
        )
        baselineDecisionSummary = "\(reason) -> \(trigger) · \(level) · \(intervention)"

        let resolvedProjectConfig = projectConfig
            ?? Self.synthesizedProjectConfig(
                executionTier: configuredExecutionTier,
                reviewPolicyMode: configuredReviewPolicyMode,
                reviewPulseSeconds: reviewPulseSeconds,
                brainstormReviewSeconds: brainstormReviewSeconds
            )
        sceneParameterMatrix = Self.buildSceneParameterMatrix(
            projectConfig: resolvedProjectConfig,
            resolvedGovernance: resolvedGovernance,
            baselineDecision: baselineDecision,
            configuredSupervisorRecentRawContextProfile: configuredSupervisorRecentRawContextProfile,
            configuredSupervisorReviewMemoryDepth: configuredSupervisorReviewMemoryDepth,
            supervisorPrivacyMode: supervisorPrivacyMode
        )
    }

    private static func localizedBaselineReason(_ raw: String) -> String {
        switch raw {
        case "brainstorm cadence":
            return "脑暴节奏"
        case "pulse cadence":
            return "脉冲节奏"
        case "manual review":
            return "手动审查"
        default:
            return raw
        }
    }

    private static func synthesizedProjectConfig(
        executionTier: AXProjectExecutionTier,
        reviewPolicyMode: AXProjectReviewPolicyMode,
        reviewPulseSeconds: Int,
        brainstormReviewSeconds: Int
    ) -> AXProjectConfig {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("project-governance-editor-\(UUID().uuidString)", isDirectory: true)
        return AXProjectConfig.default(forProjectRoot: root).settingProjectGovernance(
            executionTier: executionTier,
            supervisorInterventionTier: executionTier.defaultSupervisorInterventionTier,
            reviewPolicyMode: reviewPolicyMode,
            progressHeartbeatSeconds: executionTier.defaultProgressHeartbeatSeconds,
            reviewPulseSeconds: reviewPulseSeconds,
            brainstormReviewSeconds: brainstormReviewSeconds,
            eventDrivenReviewEnabled: executionTier.defaultEventDrivenReviewEnabled,
            eventReviewTriggers: executionTier.defaultEventReviewTriggers
        )
    }

    private static func buildSceneParameterMatrix(
        projectConfig: AXProjectConfig,
        resolvedGovernance: AXProjectResolvedGovernanceState,
        baselineDecision: SupervisorReviewPolicyDecision,
        configuredSupervisorRecentRawContextProfile: XTSupervisorRecentRawContextProfile,
        configuredSupervisorReviewMemoryDepth: XTSupervisorReviewMemoryDepthProfile,
        supervisorPrivacyMode: XTPrivacyMode
    ) -> ProjectGovernanceSceneParameterMatrixPresentation {
        let defaults = xtRecommendedGovernanceTemplateDefaults(
            executionTier: projectConfig.executionTier,
            supervisorInterventionTier: projectConfig.supervisorInterventionTier
        )
        let configuredCapabilityBundle = projectConfig.executionTier.baseCapabilityBundle
        let recommendedCapabilityBundle = defaults.executionTier.baseCapabilityBundle
        let effectiveCapabilityBundle = resolvedGovernance.capabilityBundle.applying(
            effectiveRuntimeSurface: resolvedGovernance.effectiveRuntimeSurface,
            trustedAutomationStatus: resolvedGovernance.trustedAutomationStatus
        )
        let configuredBudget = projectConfig.executionTier.defaultExecutionBudget
        let recommendedBudget = defaults.executionTier.defaultExecutionBudget
        let effectiveBudget = resolvedGovernance.executionBudget

        let effectiveProjectRecent = effectiveProjectRecentDialogueProfile(
            configured: projectConfig.projectRecentDialogueProfile,
            recommended: defaults.projectRecentDialogueProfile
        )
        let effectiveProjectDepth = effectiveProjectContextDepth(
            configured: projectConfig.projectContextDepthProfile,
            recommended: defaults.projectContextDepthProfile
        )

        let supervisorPolicy = XTRoleAwareMemoryPolicyResolver.resolveSupervisor(
            configuredSupervisorRecentRawContextProfile: configuredSupervisorRecentRawContextProfile,
            configuredReviewMemoryDepth: configuredSupervisorReviewMemoryDepth,
            reviewLevelHint: baselineDecision.reviewLevel,
            dominantMode: .projectFirst,
            focusedProjectSelected: true,
            userMessage: "project governance review",
            triggerSource: baselineDecision.policyReason,
            governanceReviewTrigger: .manualRequest,
            governanceReviewRunKind: baselineDecision.reviewLevel == .r3Rescue ? .brainstorm : .pulse,
            reviewMemoryCeiling: resolvedGovernance.supervisorReviewMemoryCeiling,
            privacyMode: supervisorPrivacyMode,
            assemblyPurpose: .governanceReview
        )

        let cadenceRows = [
            ProjectGovernanceParameterMatrixRowPresentation(
                title: "进度心跳",
                configuredValue: governanceDisplayDurationLabel(projectConfig.progressHeartbeatSeconds),
                recommendedValue: governanceDisplayDurationLabel(defaults.progressHeartbeatSeconds),
                effectiveValue: governanceDisplayDurationLabel(resolvedGovernance.effectiveBundle.schedule.progressHeartbeatSeconds),
                sourceSummary: sourceSummary(
                    configured: projectConfig.progressHeartbeatSeconds,
                    recommended: defaults.progressHeartbeatSeconds,
                    effective: resolvedGovernance.effectiveBundle.schedule.progressHeartbeatSeconds,
                    defaultSource: "\(defaults.sceneLabel) 默认",
                    runtimeSource: "runtime 生效值"
                ),
                detail: "只负责看进度，不负责战略纠偏。"
            ),
            ProjectGovernanceParameterMatrixRowPresentation(
                title: "周期复盘",
                configuredValue: governanceDisplayDurationLabel(projectConfig.reviewPulseSeconds),
                recommendedValue: governanceDisplayDurationLabel(defaults.reviewPulseSeconds),
                effectiveValue: governanceDisplayDurationLabel(resolvedGovernance.effectiveBundle.schedule.reviewPulseSeconds),
                sourceSummary: sourceSummary(
                    configured: projectConfig.reviewPulseSeconds,
                    recommended: defaults.reviewPulseSeconds,
                    effective: resolvedGovernance.effectiveBundle.schedule.reviewPulseSeconds,
                    defaultSource: "\(defaults.sceneLabel) 默认",
                    runtimeSource: "runtime 生效值"
                ),
                detail: "适合轻量周期复盘。"
            ),
            ProjectGovernanceParameterMatrixRowPresentation(
                title: "脑暴复盘",
                configuredValue: governanceDisplayDurationLabel(projectConfig.brainstormReviewSeconds),
                recommendedValue: governanceDisplayDurationLabel(defaults.brainstormReviewSeconds),
                effectiveValue: governanceDisplayDurationLabel(resolvedGovernance.effectiveBundle.schedule.brainstormReviewSeconds),
                sourceSummary: sourceSummary(
                    configured: projectConfig.brainstormReviewSeconds,
                    recommended: defaults.brainstormReviewSeconds,
                    effective: resolvedGovernance.effectiveBundle.schedule.brainstormReviewSeconds,
                    defaultSource: "\(defaults.sceneLabel) 默认",
                    runtimeSource: "runtime 生效值"
                ),
                detail: "适合长时间无进展时的方向复盘。"
            )
        ]

        let continuityRows = [
            ProjectGovernanceParameterMatrixRowPresentation(
                title: "Project AI 最近原文底线",
                configuredValue: profileLabel(projectConfig.projectRecentDialogueProfile),
                recommendedValue: profileLabel(defaults.projectRecentDialogueProfile),
                effectiveValue: profileLabel(effectiveProjectRecent),
                sourceSummary: sourceSummary(
                    configured: projectConfig.projectRecentDialogueProfile.rawValue,
                    recommended: defaults.projectRecentDialogueProfile.rawValue,
                    effective: effectiveProjectRecent.rawValue,
                    defaultSource: "\(defaults.sceneLabel) continuity 默认",
                    runtimeSource: "auto continuity 生效值"
                ),
                detail: "这是 coder 的 recent raw floor，不跟 Supervisor 的 recent raw 档位共用。"
            ),
            ProjectGovernanceParameterMatrixRowPresentation(
                title: "Project AI 背景厚度",
                configuredValue: depthLabel(projectConfig.projectContextDepthProfile),
                recommendedValue: depthLabel(defaults.projectContextDepthProfile),
                effectiveValue: depthLabel(effectiveProjectDepth),
                sourceSummary: sourceSummary(
                    configured: projectConfig.projectContextDepthProfile.rawValue,
                    recommended: defaults.projectContextDepthProfile.rawValue,
                    effective: effectiveProjectDepth.rawValue,
                    defaultSource: "\(defaults.sceneLabel) context 默认",
                    runtimeSource: "auto context 生效值"
                ),
                detail: "这决定 coder 除了 recent raw 之外还能看多厚的项目背景。"
            ),
            ProjectGovernanceParameterMatrixRowPresentation(
                title: "Supervisor 最近原文底线",
                configuredValue: profileLabel(supervisorPolicy.configuredSupervisorRecentRawContextProfile),
                recommendedValue: profileLabel(supervisorPolicy.recommendedSupervisorRecentRawContextProfile),
                effectiveValue: profileLabel(supervisorPolicy.effectiveSupervisorRecentRawContextProfile),
                sourceSummary: supervisorRecentSourceSummary(
                    policy: supervisorPolicy,
                    privacyMode: supervisorPrivacyMode
                ),
                detail: "这是 Supervisor 全局 recent raw 设置；项目页只读展示，不会把它和 coder continuity 混成一档。"
            ),
            ProjectGovernanceParameterMatrixRowPresentation(
                title: "Supervisor 审查深度",
                configuredValue: supervisorPolicy.configuredReviewMemoryDepth.displayName,
                recommendedValue: supervisorPolicy.recommendedReviewMemoryDepth.displayName,
                effectiveValue: supervisorPolicy.effectiveReviewMemoryDepth.displayName,
                sourceSummary: supervisorReviewDepthSourceSummary(policy: supervisorPolicy),
                detail: "这条线由 Supervisor 全局 review-memory 设置和当前 S-Tier ceiling 一起决定。"
            )
        ]

        let executionRows = [
            ProjectGovernanceParameterMatrixRowPresentation(
                title: "能力包",
                configuredValue: capabilitySummary(configuredCapabilityBundle),
                recommendedValue: capabilitySummary(recommendedCapabilityBundle),
                effectiveValue: capabilitySummary(effectiveCapabilityBundle),
                sourceSummary: sourceSummary(
                    configured: configuredCapabilityBundle.allowedCapabilityLabels,
                    recommended: recommendedCapabilityBundle.allowedCapabilityLabels,
                    effective: effectiveCapabilityBundle.allowedCapabilityLabels,
                    defaultSource: "\(defaults.sceneLabel) A-Tier 默认",
                    runtimeSource: "runtime capability 收束"
                ),
                detail: "A-Tier 决定主能力边界，runtime surface / grant / TTL 会继续把它往下收。"
            ),
            ProjectGovernanceParameterMatrixRowPresentation(
                title: "执行预算",
                configuredValue: budgetSummary(configuredBudget),
                recommendedValue: budgetSummary(recommendedBudget),
                effectiveValue: budgetSummary(effectiveBudget),
                sourceSummary: sourceSummary(
                    configured: configuredBudget,
                    recommended: recommendedBudget,
                    effective: effectiveBudget,
                    defaultSource: "\(defaults.sceneLabel) A-Tier 默认",
                    runtimeSource: "runtime 生效预算"
                ),
                detail: "包含连续运行时长、工具调用上限、重试深度和软成本预算。"
            )
        ]

        let closeoutRows = [
            ProjectGovernanceParameterMatrixRowPresentation(
                title: "Pre-done Review",
                configuredValue: boolLabel(configuredBudget.preDoneReviewRequired),
                recommendedValue: boolLabel(recommendedBudget.preDoneReviewRequired),
                effectiveValue: boolLabel(effectiveBudget.preDoneReviewRequired),
                sourceSummary: sourceSummary(
                    configured: configuredBudget.preDoneReviewRequired,
                    recommended: recommendedBudget.preDoneReviewRequired,
                    effective: effectiveBudget.preDoneReviewRequired,
                    defaultSource: "\(defaults.sceneLabel) closeout 默认",
                    runtimeSource: "runtime closeout 约束"
                ),
                detail: "决定 coder 想收口时，Supervisor 是否必须先做 pre-done 审查。"
            ),
            ProjectGovernanceParameterMatrixRowPresentation(
                title: "Done Evidence",
                configuredValue: boolLabel(configuredBudget.doneRequiresEvidence),
                recommendedValue: boolLabel(recommendedBudget.doneRequiresEvidence),
                effectiveValue: boolLabel(effectiveBudget.doneRequiresEvidence),
                sourceSummary: sourceSummary(
                    configured: configuredBudget.doneRequiresEvidence,
                    recommended: recommendedBudget.doneRequiresEvidence,
                    effective: effectiveBudget.doneRequiresEvidence,
                    defaultSource: "\(defaults.sceneLabel) closeout 默认",
                    runtimeSource: "runtime closeout 约束"
                ),
                detail: "决定项目宣告完成时，是否必须带 verify / delivery evidence。"
            )
        ]

        return ProjectGovernanceSceneParameterMatrixPresentation(
            sceneLabel: defaults.sceneLabel,
            cadenceRows: cadenceRows,
            continuityRows: continuityRows,
            executionRows: executionRows,
            closeoutRows: closeoutRows
        )
    }

    private static func effectiveProjectRecentDialogueProfile(
        configured: AXProjectRecentDialogueProfile,
        recommended: AXProjectRecentDialogueProfile
    ) -> AXProjectRecentDialogueProfile {
        configured == .autoMax ? recommended : configured
    }

    private static func effectiveProjectContextDepth(
        configured: AXProjectContextDepthProfile,
        recommended: AXProjectContextDepthProfile
    ) -> AXProjectContextDepthProfile {
        configured == .auto ? recommended : configured
    }

    private static func profileLabel(_ profile: AXProjectRecentDialogueProfile) -> String {
        "\(profile.displayName) · \(profile.shortLabel)"
    }

    private static func profileLabel(_ profile: XTSupervisorRecentRawContextProfile) -> String {
        "\(profile.displayName) · \(profile.shortLabel)"
    }

    private static func depthLabel(_ profile: AXProjectContextDepthProfile) -> String {
        profile.displayName
    }

    private static func capabilitySummary(_ bundle: AXProjectCapabilityBundle) -> String {
        var parts: [String] = []
        if bundle.allowJobPlanAuto {
            parts.append("Plan")
        }
        if bundle.allowRepoWrite || bundle.allowRepoBuild || bundle.allowRepoTest || bundle.allowGitApply {
            parts.append("Repo")
        }
        if bundle.allowManagedProcesses {
            parts.append(bundle.allowProcessAutoRestart ? "Process + Restart" : "Process")
        }
        if bundle.allowGitCommit || bundle.allowPRCreate || bundle.allowCIRead || bundle.allowCITrigger || bundle.allowGitPush {
            parts.append("Delivery")
        }
        if bundle.allowBrowserRuntime || bundle.allowDeviceTools || bundle.allowConnectorActions || bundle.allowExtensions {
            parts.append("Agent Surface")
        }
        if bundle.allowAutoLocalApproval {
            parts.append("Auto Approve")
        }
        if parts.isEmpty {
            return "Observe only"
        }
        return "\(parts.joined(separator: " · ")) · \(bundle.allowedCapabilityLabels.count) capabilities"
    }

    private static func budgetSummary(_ budget: AXProjectExecutionBudget) -> String {
        let cost = budget.maxCostUSDSoft.rounded(.towardZero) == budget.maxCostUSDSoft
            ? String(Int(budget.maxCostUSDSoft))
            : String(format: "%.1f", budget.maxCostUSDSoft)
        return "\(budget.maxContinuousRunMinutes)m run · \(budget.maxToolCallsPerRun) tools · retry x\(budget.maxRetryDepth) · soft $\(cost)"
    }

    private static func boolLabel(_ value: Bool) -> String {
        value ? "Required" : "Not required"
    }

    private static func sourceSummary<T: Equatable>(
        configured: T,
        recommended: T,
        effective: T,
        defaultSource: String,
        runtimeSource: String
    ) -> String {
        if effective != configured {
            return "来源：\(runtimeSource)"
        }
        if configured != recommended {
            return "来源：用户手改"
        }
        return "来源：\(defaultSource)"
    }

    private static func supervisorRecentSourceSummary(
        policy: XTSupervisorMemoryPolicy,
        privacyMode: XTPrivacyMode
    ) -> String {
        let privacyAdjusted = privacyMode.effectiveRecentRawContextProfile(
            policy.configuredSupervisorRecentRawContextProfile
        )
        if policy.effectiveSupervisorRecentRawContextProfile != policy.configuredSupervisorRecentRawContextProfile {
            if privacyAdjusted != policy.configuredSupervisorRecentRawContextProfile {
                return "来源：Supervisor 设置 + 隐私收束"
            }
            if policy.configuredSupervisorRecentRawContextProfile == .autoMax {
                return "来源：Supervisor Auto 档"
            }
            return "来源：review 生效值"
        }
        if policy.configuredSupervisorRecentRawContextProfile != policy.recommendedSupervisorRecentRawContextProfile {
            return "来源：Supervisor 用户设置"
        }
        return "来源：Supervisor 默认"
    }

    private static func supervisorReviewDepthSourceSummary(
        policy: XTSupervisorMemoryPolicy
    ) -> String {
        if policy.effectiveReviewMemoryDepth != policy.configuredReviewMemoryDepth {
            if policy.configuredReviewMemoryDepth == .auto {
                return "来源：S-Tier / trigger 自动求值"
            }
            if policy.purposeCapApplied || policy.ceilingHit {
                return "来源：S-Tier ceiling"
            }
            return "来源：review 生效值"
        }
        if policy.configuredReviewMemoryDepth != policy.recommendedReviewMemoryDepth {
            return "来源：Supervisor 用户设置"
        }
        return "来源：Supervisor 默认"
    }
}

private extension AXProjectGovernanceTemplateDefaults {
    var sceneLabel: String { template.displayName }
}

private extension ProjectGovernanceStatusBadgeTone {
    var localizedLabel: String {
        switch self {
        case .current:
            return "当前"
        case .configured:
            return "已配置"
        case .effective:
            return "生效中"
        case .recommended:
            return "推荐"
        case .safeFloor:
            return "风险参考线"
        case .belowSafeFloor:
            return "高风险"
        }
    }
}
