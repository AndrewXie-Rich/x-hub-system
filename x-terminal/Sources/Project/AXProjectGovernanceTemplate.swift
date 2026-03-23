import Foundation

enum AXProjectGovernanceTemplate: String, CaseIterable, Sendable, Identifiable {
    case conservative
    case safe
    case agent = "full_autonomy"
    case custom

    static let selectableTemplates: [Self] = [
        .conservative,
        .safe,
        .agent,
    ]

    static let selectableProfiles: [Self] = selectableTemplates

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .conservative:
            return "保守"
        case .safe:
            return "安全"
        case .agent:
            return "Agent"
        case .custom:
            return "自定义"
        }
    }

    var shortDescription: String {
        switch self {
        case .conservative:
            return "默认映射 A1 + S2，以理解、规划和审阅为主。"
        case .safe:
            return "默认映射 A3 + S3，推荐默认档，在项目内持续推进。"
        case .agent:
            return "默认映射 A4 Agent + S3，允许更大执行面，但仍受治理约束。"
        case .custom:
            return "当前高级治理项已偏离默认映射。"
        }
    }
}

typealias AXProjectAutonomyProfile = AXProjectGovernanceTemplate

enum AXProjectDeviceAuthorityPosture: String, Sendable {
    case off
    case projectBound = "project_bound"
    case deviceGoverned = "device_governed"

    var displayName: String {
        switch self {
        case .off:
            return "关闭"
        case .projectBound:
            return "项目级受治理"
        case .deviceGoverned:
            return "设备级受治理"
        }
    }
}

enum AXProjectSupervisorScope: String, Sendable {
    case focusedProject = "focused_project"
    case portfolio
    case deviceGoverned = "device_governed"

    var displayName: String {
        switch self {
        case .focusedProject:
            return "当前项目"
        case .portfolio:
            return "全部项目"
        case .deviceGoverned:
            return "设备治理视角"
        }
    }
}

enum AXProjectGrantPosture: String, Sendable {
    case manualReview = "manual_review"
    case guidedAuto = "guided_auto"
    case envelopeAuto = "envelope_auto"

    var displayName: String {
        switch self {
        case .manualReview:
            return "人工审批"
        case .guidedAuto:
            return "引导式自动审批"
        case .envelopeAuto:
            return "包络预授权"
        }
    }
}

struct AXProjectGovernanceTemplatePreview: Equatable, Sendable {
    var configuredProfile: AXProjectGovernanceTemplate
    var effectiveProfile: AXProjectGovernanceTemplate
    var configuredDeviceAuthorityPosture: AXProjectDeviceAuthorityPosture
    var effectiveDeviceAuthorityPosture: AXProjectDeviceAuthorityPosture
    var configuredSupervisorScope: AXProjectSupervisorScope
    var effectiveSupervisorScope: AXProjectSupervisorScope
    var configuredGrantPosture: AXProjectGrantPosture
    var effectiveGrantPosture: AXProjectGrantPosture
    var configuredProfileSummary: String
    var effectiveProfileSummary: String
    var configuredDeviceAuthorityDetail: String
    var effectiveDeviceAuthorityDetail: String
    var configuredSupervisorScopeDetail: String
    var effectiveSupervisorScopeDetail: String
    var configuredGrantDetail: String
    var effectiveGrantDetail: String
    var configuredDeviationReasons: [String]
    var effectiveDeviationReasons: [String]
    var runtimeSummary: String

    var hasConfiguredEffectiveDrift: Bool {
        configuredProfile != effectiveProfile
            || configuredDeviceAuthorityPosture != effectiveDeviceAuthorityPosture
            || configuredSupervisorScope != effectiveSupervisorScope
            || configuredGrantPosture != effectiveGrantPosture
    }
}

typealias AXProjectAutonomySwitchboardPresentation = AXProjectGovernanceTemplatePreview

private struct AXProjectGovernanceTemplateSpec {
    var template: AXProjectGovernanceTemplate
    var executionTier: AXProjectExecutionTier
    var supervisorTier: AXProjectSupervisorInterventionTier
    var reviewPolicyMode: AXProjectReviewPolicyMode
    var progressHeartbeatSeconds: Int
    var reviewPulseSeconds: Int
    var brainstormReviewSeconds: Int
    var eventDrivenReviewEnabled: Bool
    var eventReviewTriggers: [AXProjectReviewTrigger]
    var runtimeSurfaceMode: AXProjectRuntimeSurfaceMode
    var localAutoApproveConfigured: Bool
    var requiresHubMemory: Bool
    var deviceAuthorityPosture: AXProjectDeviceAuthorityPosture
    var supervisorScope: AXProjectSupervisorScope
    var grantPosture: AXProjectGrantPosture

    init?(template: AXProjectGovernanceTemplate) {
        switch template {
        case .conservative:
            let bundle = AXProjectGovernanceBundle.recommended(
                for: .a1Plan,
                supervisorInterventionTier: .s2PeriodicReview
            )
            self.template = template
            executionTier = .a1Plan
            supervisorTier = .s2PeriodicReview
            reviewPolicyMode = bundle.reviewPolicyMode
            progressHeartbeatSeconds = bundle.schedule.progressHeartbeatSeconds
            reviewPulseSeconds = bundle.schedule.reviewPulseSeconds
            brainstormReviewSeconds = bundle.schedule.brainstormReviewSeconds
            eventDrivenReviewEnabled = bundle.schedule.eventDrivenReviewEnabled
            eventReviewTriggers = bundle.schedule.eventReviewTriggers
            runtimeSurfaceMode = .manual
            localAutoApproveConfigured = false
            requiresHubMemory = false
            deviceAuthorityPosture = .off
            supervisorScope = .focusedProject
            grantPosture = .manualReview
        case .safe:
            let bundle = AXProjectGovernanceBundle.recommended(
                for: .a3DeliverAuto,
                supervisorInterventionTier: .s3StrategicCoach
            )
            self.template = template
            executionTier = .a3DeliverAuto
            supervisorTier = .s3StrategicCoach
            reviewPolicyMode = bundle.reviewPolicyMode
            progressHeartbeatSeconds = bundle.schedule.progressHeartbeatSeconds
            reviewPulseSeconds = bundle.schedule.reviewPulseSeconds
            brainstormReviewSeconds = bundle.schedule.brainstormReviewSeconds
            eventDrivenReviewEnabled = bundle.schedule.eventDrivenReviewEnabled
            eventReviewTriggers = bundle.schedule.eventReviewTriggers
            runtimeSurfaceMode = .guided
            localAutoApproveConfigured = false
            requiresHubMemory = false
            deviceAuthorityPosture = .projectBound
            supervisorScope = .portfolio
            grantPosture = .guidedAuto
        case .agent:
            let bundle = AXProjectGovernanceBundle.recommended(
                for: .a4OpenClaw,
                supervisorInterventionTier: .s3StrategicCoach
            )
            self.template = template
            executionTier = .a4OpenClaw
            supervisorTier = .s3StrategicCoach
            reviewPolicyMode = bundle.reviewPolicyMode
            progressHeartbeatSeconds = bundle.schedule.progressHeartbeatSeconds
            reviewPulseSeconds = bundle.schedule.reviewPulseSeconds
            brainstormReviewSeconds = bundle.schedule.brainstormReviewSeconds
            eventDrivenReviewEnabled = bundle.schedule.eventDrivenReviewEnabled
            eventReviewTriggers = bundle.schedule.eventReviewTriggers
            runtimeSurfaceMode = .trustedOpenClawMode
            localAutoApproveConfigured = true
            requiresHubMemory = true
            deviceAuthorityPosture = .deviceGoverned
            supervisorScope = .deviceGoverned
            grantPosture = .envelopeAuto
        case .custom:
            return nil
        }
    }
}

private struct AXProjectGovernanceTemplateSnapshot {
    var executionTier: AXProjectExecutionTier
    var supervisorTier: AXProjectSupervisorInterventionTier
    var reviewPolicyMode: AXProjectReviewPolicyMode
    var progressHeartbeatSeconds: Int
    var reviewPulseSeconds: Int
    var brainstormReviewSeconds: Int
    var eventDrivenReviewEnabled: Bool
    var eventReviewTriggers: [AXProjectReviewTrigger]
    var runtimeSurfaceMode: AXProjectRuntimeSurfaceMode
    var localAutoApproveConfigured: Bool
    var hubMemoryEnabled: Bool
    var runtimeSurfaceClamp: AXProjectRuntimeSurfaceHubOverrideMode
}

extension AXProjectConfig {
    func settingGovernanceTemplate(
        _ template: AXProjectGovernanceTemplate,
        projectRoot _: URL,
        now: Date = Date()
    ) -> AXProjectConfig {
        guard let spec = AXProjectGovernanceTemplateSpec(template: template) else { return self }

        var out = self
        out = out.settingProjectGovernance(
            executionTier: spec.executionTier,
            supervisorInterventionTier: spec.supervisorTier,
            reviewPolicyMode: spec.reviewPolicyMode,
            progressHeartbeatSeconds: spec.progressHeartbeatSeconds,
            reviewPulseSeconds: spec.reviewPulseSeconds,
            brainstormReviewSeconds: spec.brainstormReviewSeconds,
            eventDrivenReviewEnabled: spec.eventDrivenReviewEnabled,
            eventReviewTriggers: spec.eventReviewTriggers,
            governanceCompatSource: .explicitDualDial
        )
        out = out.settingRuntimeSurfacePolicy(
            mode: spec.runtimeSurfaceMode,
            ttlSeconds: 3600,
            hubOverrideMode: AXProjectRuntimeSurfaceHubOverrideMode.none,
            updatedAt: now
        )
        out = out.settingGovernedAutoApproveLocalToolCalls(enabled: spec.localAutoApproveConfigured)
        if spec.requiresHubMemory {
            out = out.settingHubMemoryPreference(enabled: true)
        }
        return out
    }

    @available(*, deprecated, message: "Use settingGovernanceTemplate(_:projectRoot:now:)")
    func settingAutonomySwitchboardProfile(
        _ profile: AXProjectAutonomyProfile,
        projectRoot: URL,
        now: Date = Date()
    ) -> AXProjectConfig {
        settingGovernanceTemplate(
            profile,
            projectRoot: projectRoot,
            now: now
        )
    }
}

func xtGovernanceTemplateBaseline(for executionTier: AXProjectExecutionTier) -> AXProjectGovernanceTemplate {
    switch executionTier {
    case .a0Observe, .a1Plan:
        return .conservative
    case .a2RepoAuto, .a3DeliverAuto:
        return .safe
    case .a4OpenClaw:
            return .agent
    }
}

@available(*, deprecated, message: "Use xtGovernanceTemplateBaseline(for:)")
func xtAutonomyBaselineProfile(for executionTier: AXProjectExecutionTier) -> AXProjectAutonomyProfile {
    xtGovernanceTemplateBaseline(for: executionTier)
}

func xtGovernanceTemplateDraftConfig(
    projectRoot: URL,
    template: AXProjectGovernanceTemplate,
    executionTier: AXProjectExecutionTier,
    supervisorInterventionTier: AXProjectSupervisorInterventionTier,
    reviewPolicyMode: AXProjectReviewPolicyMode,
    progressHeartbeatSeconds: Int,
    reviewPulseSeconds: Int,
    brainstormReviewSeconds: Int,
    eventDrivenReviewEnabled: Bool,
    eventReviewTriggers: [AXProjectReviewTrigger]? = nil
) -> AXProjectConfig {
    let normalizedTemplate = AXProjectGovernanceTemplate.selectableTemplates.contains(template)
        ? template
        : xtGovernanceTemplateBaseline(for: executionTier)

    return AXProjectConfig
        .default(forProjectRoot: projectRoot)
        .settingGovernanceTemplate(
            normalizedTemplate,
            projectRoot: projectRoot
        )
        .settingProjectGovernance(
            executionTier: executionTier,
            supervisorInterventionTier: supervisorInterventionTier,
            reviewPolicyMode: reviewPolicyMode,
            progressHeartbeatSeconds: progressHeartbeatSeconds,
            reviewPulseSeconds: reviewPulseSeconds,
            brainstormReviewSeconds: brainstormReviewSeconds,
            eventDrivenReviewEnabled: eventDrivenReviewEnabled,
            eventReviewTriggers: eventReviewTriggers ?? executionTier.defaultEventReviewTriggers,
            governanceCompatSource: .explicitDualDial
        )
}

@available(*, deprecated, message: "Use xtGovernanceTemplateDraftConfig(projectRoot:template:executionTier:supervisorInterventionTier:reviewPolicyMode:progressHeartbeatSeconds:reviewPulseSeconds:brainstormReviewSeconds:eventDrivenReviewEnabled:)")
func xtAutonomySwitchboardDraftConfig(
    projectRoot: URL,
    baselineProfile: AXProjectAutonomyProfile,
    executionTier: AXProjectExecutionTier,
    supervisorInterventionTier: AXProjectSupervisorInterventionTier,
    reviewPolicyMode: AXProjectReviewPolicyMode,
    progressHeartbeatSeconds: Int,
    reviewPulseSeconds: Int,
    brainstormReviewSeconds: Int,
    eventDrivenReviewEnabled: Bool
) -> AXProjectConfig {
    xtGovernanceTemplateDraftConfig(
        projectRoot: projectRoot,
        template: baselineProfile,
        executionTier: executionTier,
        supervisorInterventionTier: supervisorInterventionTier,
        reviewPolicyMode: reviewPolicyMode,
        progressHeartbeatSeconds: progressHeartbeatSeconds,
        reviewPulseSeconds: reviewPulseSeconds,
        brainstormReviewSeconds: brainstormReviewSeconds,
        eventDrivenReviewEnabled: eventDrivenReviewEnabled
    )
}

func xtProjectGovernanceTemplatePresentation(
    projectRoot: URL,
    config: AXProjectConfig,
    resolved: AXProjectResolvedGovernanceState
) -> AXProjectGovernanceTemplatePreview {
    let configuredProfile = xtConfiguredGovernanceTemplate(for: config)
    let configuredAuthority = xtProjectGovernedAuthorityPresentation(
        projectRoot: projectRoot,
        config: config
    )
    let effectiveCapability = resolved.effectiveBundle.executionTier.baseCapabilityBundle.applying(
        effectiveRuntimeSurface: resolved.effectiveRuntimeSurface,
        trustedAutomationStatus: resolved.trustedAutomationStatus
    )
    let effectiveProfile = xtEffectiveGovernanceTemplate(
        config: config,
        resolved: resolved,
        effectiveCapability: effectiveCapability
    )
    let configuredDeviceAuthority = xtConfiguredDeviceAuthorityPosture(
        config: config,
        profile: configuredProfile
    )
    let effectiveDeviceAuthority = xtEffectiveDeviceAuthorityPosture(
        resolved: resolved,
        effectiveCapability: effectiveCapability
    )
    let configuredSupervisorScope = xtConfiguredSupervisorScope(
        config: config,
        profile: configuredProfile
    )
    let effectiveSupervisorScope = xtEffectiveSupervisorScope(
        config: config,
        resolved: resolved
    )
    let configuredGrantPosture = xtConfiguredGrantPosture(
        config: config,
        profile: configuredProfile
    )
    let effectiveGrantPosture = xtEffectiveGrantPosture(
        resolved: resolved,
        effectiveCapability: effectiveCapability
    )
    let runtimeSummary = xtRuntimeSummary(
        config: config,
        resolved: resolved
    )

    return AXProjectGovernanceTemplatePreview(
        configuredProfile: configuredProfile,
        effectiveProfile: effectiveProfile,
        configuredDeviceAuthorityPosture: configuredDeviceAuthority,
        effectiveDeviceAuthorityPosture: effectiveDeviceAuthority,
        configuredSupervisorScope: configuredSupervisorScope,
        effectiveSupervisorScope: effectiveSupervisorScope,
        configuredGrantPosture: configuredGrantPosture,
        effectiveGrantPosture: effectiveGrantPosture,
        configuredProfileSummary: configuredProfile.shortDescription,
        effectiveProfileSummary: xtEffectiveTemplateSummary(
            template: effectiveProfile,
            resolved: resolved,
            effectiveCapability: effectiveCapability
        ),
        configuredDeviceAuthorityDetail: xtConfiguredDeviceAuthorityDetail(
            posture: configuredDeviceAuthority,
            authority: configuredAuthority,
            trustedAutomationStatus: resolved.trustedAutomationStatus
        ),
        effectiveDeviceAuthorityDetail: xtEffectiveDeviceAuthorityDetail(
            posture: effectiveDeviceAuthority,
            resolved: resolved,
            effectiveCapability: effectiveCapability
        ),
        configuredSupervisorScopeDetail: xtSupervisorScopeDetail(
            scope: configuredSupervisorScope,
            hubMemoryEnabled: config.preferHubMemory,
            effective: false
        ),
        effectiveSupervisorScopeDetail: xtSupervisorScopeDetail(
            scope: effectiveSupervisorScope,
            hubMemoryEnabled: config.preferHubMemory,
            effective: true
        ),
        configuredGrantDetail: xtGrantDetail(
            posture: configuredGrantPosture,
            effective: false
        ),
        effectiveGrantDetail: xtGrantDetail(
            posture: effectiveGrantPosture,
            effective: true
        ),
        configuredDeviationReasons: xtConfiguredTemplateDeviationReasons(config),
        effectiveDeviationReasons: xtEffectiveTemplateDeviationReasons(
            config: config,
            resolved: resolved,
            effectiveCapability: effectiveCapability
        ),
        runtimeSummary: runtimeSummary
    )
}

@available(*, deprecated, message: "Use xtProjectGovernanceTemplatePresentation(projectRoot:config:resolved:)")
func xtProjectAutonomySwitchboardPresentation(
    projectRoot: URL,
    config: AXProjectConfig,
    resolved: AXProjectResolvedGovernanceState
) -> AXProjectAutonomySwitchboardPresentation {
    xtProjectGovernanceTemplatePresentation(
        projectRoot: projectRoot,
        config: config,
        resolved: resolved
    )
}

private func xtConfiguredGovernanceTemplate(for config: AXProjectConfig) -> AXProjectGovernanceTemplate {
    if xtMatchesLegacyConservativeTemplate(config) || xtMatchesTemplate(config, template: .conservative) {
        return .conservative
    }
    if xtMatchesTemplate(config, template: .safe) {
        return .safe
    }
    if xtMatchesTemplate(config, template: .agent) {
        return .agent
    }
    return .custom
}

private func xtEffectiveGovernanceTemplate(
    config: AXProjectConfig,
    resolved: AXProjectResolvedGovernanceState,
    effectiveCapability: AXProjectCapabilityBundle
) -> AXProjectGovernanceTemplate {
    let snapshot = AXProjectGovernanceTemplateSnapshot(
        executionTier: resolved.effectiveBundle.executionTier,
        supervisorTier: resolved.effectiveBundle.supervisorInterventionTier,
        reviewPolicyMode: resolved.effectiveBundle.reviewPolicyMode,
        progressHeartbeatSeconds: resolved.effectiveBundle.schedule.progressHeartbeatSeconds,
        reviewPulseSeconds: resolved.effectiveBundle.schedule.reviewPulseSeconds,
        brainstormReviewSeconds: resolved.effectiveBundle.schedule.brainstormReviewSeconds,
        eventDrivenReviewEnabled: resolved.effectiveBundle.schedule.eventDrivenReviewEnabled,
        eventReviewTriggers: resolved.effectiveBundle.schedule.eventReviewTriggers,
        runtimeSurfaceMode: resolved.effectiveRuntimeSurface.effectiveMode,
        localAutoApproveConfigured: effectiveCapability.allowAutoLocalApproval,
        hubMemoryEnabled: config.preferHubMemory,
        runtimeSurfaceClamp: resolved.effectiveRuntimeSurface.hubOverrideMode
    )

    if xtMatchesLegacyConservativeTemplate(snapshot) || xtMatchesTemplate(snapshot, template: .conservative) {
        return .conservative
    }
    if xtMatchesTemplate(snapshot, template: .safe) {
        return .safe
    }
    if xtMatchesTemplate(snapshot, template: .agent) {
        return .agent
    }
    return .custom
}

private func xtMatchesTemplate(
    _ config: AXProjectConfig,
    template: AXProjectGovernanceTemplate
) -> Bool {
    let snapshot = AXProjectGovernanceTemplateSnapshot(
        executionTier: config.executionTier,
        supervisorTier: config.supervisorInterventionTier,
        reviewPolicyMode: config.reviewPolicyMode,
        progressHeartbeatSeconds: config.progressHeartbeatSeconds,
        reviewPulseSeconds: config.reviewPulseSeconds,
        brainstormReviewSeconds: config.brainstormReviewSeconds,
        eventDrivenReviewEnabled: config.eventDrivenReviewEnabled,
        eventReviewTriggers: config.eventReviewTriggers,
        runtimeSurfaceMode: config.runtimeSurfaceMode,
        localAutoApproveConfigured: config.governedAutoApproveLocalToolCalls,
        hubMemoryEnabled: config.preferHubMemory,
        runtimeSurfaceClamp: config.runtimeSurfaceHubOverrideMode
    )
    return xtMatchesTemplate(snapshot, template: template)
}

private func xtMatchesTemplate(
    _ snapshot: AXProjectGovernanceTemplateSnapshot,
    template: AXProjectGovernanceTemplate
) -> Bool {
    guard let spec = AXProjectGovernanceTemplateSpec(template: template) else { return false }
    if snapshot.executionTier != spec.executionTier { return false }
    if snapshot.supervisorTier != spec.supervisorTier { return false }
    if snapshot.reviewPolicyMode != spec.reviewPolicyMode { return false }
    if snapshot.progressHeartbeatSeconds != spec.progressHeartbeatSeconds { return false }
    if snapshot.reviewPulseSeconds != spec.reviewPulseSeconds { return false }
    if snapshot.brainstormReviewSeconds != spec.brainstormReviewSeconds { return false }
    if snapshot.eventDrivenReviewEnabled != spec.eventDrivenReviewEnabled { return false }
    if snapshot.eventReviewTriggers != spec.eventReviewTriggers { return false }
    if snapshot.runtimeSurfaceMode != spec.runtimeSurfaceMode { return false }
    if snapshot.localAutoApproveConfigured != spec.localAutoApproveConfigured { return false }
    if snapshot.runtimeSurfaceClamp != .none { return false }
    if spec.requiresHubMemory && !snapshot.hubMemoryEnabled { return false }
    return true
}

private func xtMatchesLegacyConservativeTemplate(_ config: AXProjectConfig) -> Bool {
    let snapshot = AXProjectGovernanceTemplateSnapshot(
        executionTier: config.executionTier,
        supervisorTier: config.supervisorInterventionTier,
        reviewPolicyMode: config.reviewPolicyMode,
        progressHeartbeatSeconds: config.progressHeartbeatSeconds,
        reviewPulseSeconds: config.reviewPulseSeconds,
        brainstormReviewSeconds: config.brainstormReviewSeconds,
        eventDrivenReviewEnabled: config.eventDrivenReviewEnabled,
        eventReviewTriggers: config.eventReviewTriggers,
        runtimeSurfaceMode: config.runtimeSurfaceMode,
        localAutoApproveConfigured: config.governedAutoApproveLocalToolCalls,
        hubMemoryEnabled: config.preferHubMemory,
        runtimeSurfaceClamp: config.runtimeSurfaceHubOverrideMode
    )
    return xtMatchesLegacyConservativeTemplate(snapshot)
}

private func xtMatchesLegacyConservativeTemplate(_ snapshot: AXProjectGovernanceTemplateSnapshot) -> Bool {
    snapshot.executionTier == .a0Observe
        && snapshot.supervisorTier == .s0SilentAudit
        && snapshot.reviewPolicyMode == .milestoneOnly
        && snapshot.progressHeartbeatSeconds == AXProjectGovernanceBundle.recommended(for: .a0Observe).schedule.progressHeartbeatSeconds
        && snapshot.reviewPulseSeconds == 0
        && snapshot.brainstormReviewSeconds == 0
        && snapshot.eventDrivenReviewEnabled == false
        && snapshot.eventReviewTriggers == [.manualRequest]
        && snapshot.runtimeSurfaceMode == .manual
        && snapshot.localAutoApproveConfigured == false
        && snapshot.runtimeSurfaceClamp == .none
}

private func xtConfiguredDeviceAuthorityPosture(
    config: AXProjectConfig,
    profile: AXProjectGovernanceTemplate
) -> AXProjectDeviceAuthorityPosture {
    if let spec = AXProjectGovernanceTemplateSpec(template: profile) {
        return spec.deviceAuthorityPosture
    }
    if config.executionTier == .a4OpenClaw {
        return .deviceGoverned
    }
    if config.executionTier == .a2RepoAuto || config.executionTier == .a3DeliverAuto {
        if config.runtimeSurfaceMode == .trustedOpenClawMode
            || config.automationMode == .trustedAutomation
            || !config.trustedAutomationDeviceId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .projectBound
        }
    }
    return .off
}

private func xtEffectiveDeviceAuthorityPosture(
    resolved: AXProjectResolvedGovernanceState,
    effectiveCapability: AXProjectCapabilityBundle
) -> AXProjectDeviceAuthorityPosture {
    guard effectiveCapability.allowDeviceTools else { return .off }
    return resolved.effectiveBundle.executionTier == .a4OpenClaw ? .deviceGoverned : .projectBound
}

private func xtConfiguredSupervisorScope(
    config: AXProjectConfig,
    profile: AXProjectGovernanceTemplate
) -> AXProjectSupervisorScope {
    if let spec = AXProjectGovernanceTemplateSpec(template: profile) {
        return spec.supervisorScope
    }
    switch config.executionTier {
    case .a0Observe, .a1Plan:
        return .focusedProject
    case .a2RepoAuto, .a3DeliverAuto:
        return .portfolio
    case .a4OpenClaw:
        return config.preferHubMemory ? .deviceGoverned : .portfolio
    }
}

private func xtEffectiveSupervisorScope(
    config: AXProjectConfig,
    resolved: AXProjectResolvedGovernanceState
) -> AXProjectSupervisorScope {
    guard config.preferHubMemory else { return .focusedProject }
    switch resolved.effectiveBundle.executionTier {
    case .a0Observe, .a1Plan:
        return .focusedProject
    case .a2RepoAuto, .a3DeliverAuto:
        return .portfolio
    case .a4OpenClaw:
        return resolved.effectiveRuntimeSurface.effectiveMode == .trustedOpenClawMode ? .deviceGoverned : .portfolio
    }
}

private func xtConfiguredGrantPosture(
    config: AXProjectConfig,
    profile: AXProjectGovernanceTemplate
) -> AXProjectGrantPosture {
    if let spec = AXProjectGovernanceTemplateSpec(template: profile) {
        return spec.grantPosture
    }
    if config.executionTier == .a4OpenClaw && config.runtimeSurfaceMode == .trustedOpenClawMode {
        return .envelopeAuto
    }
    if config.executionTier == .a2RepoAuto || config.executionTier == .a3DeliverAuto {
        return .guidedAuto
    }
    return .manualReview
}

private func xtEffectiveGrantPosture(
    resolved: AXProjectResolvedGovernanceState,
    effectiveCapability _: AXProjectCapabilityBundle
) -> AXProjectGrantPosture {
    if resolved.validation.shouldFailClosed
        || resolved.effectiveRuntimeSurface.killSwitchEngaged
        || resolved.effectiveRuntimeSurface.effectiveMode == .manual {
        return .manualReview
    }
    if resolved.effectiveBundle.executionTier == .a4OpenClaw
        && resolved.effectiveRuntimeSurface.effectiveMode == .trustedOpenClawMode {
        return .envelopeAuto
    }
    return .guidedAuto
}

private func xtConfiguredDeviceAuthorityDetail(
    posture: AXProjectDeviceAuthorityPosture,
    authority: AXProjectGovernedAuthorityPresentation,
    trustedAutomationStatus: AXTrustedAutomationProjectStatus
) -> String {
    switch posture {
    case .off:
        if authority.deviceAuthorityConfigured {
            return "当前预设默认关闭设备级能力；治理详情里保留的绑定不会被本档直接放行。"
        }
        return "当前主档默认不触达设备级执行面。"
    case .projectBound:
        if authority.deviceAuthorityConfigured {
            let device = trustedAutomationStatus.boundDeviceID.isEmpty ? authority.pairedDeviceId : trustedAutomationStatus.boundDeviceID
        return "默认把设备能力收束在当前项目边界内。\(device.isEmpty ? "" : "当前已绑定 \(device)。")"
    }
        return "默认只允许当前项目在受治理前提下使用设备能力；仍需在治理详情里完成受治理自动化绑定。"
    case .deviceGoverned:
        if authority.deviceAuthorityConfigured {
            let device = trustedAutomationStatus.boundDeviceID.isEmpty ? authority.pairedDeviceId : trustedAutomationStatus.boundDeviceID
            return "当前档位允许完整执行面，但仍继续受 Hub 授权、紧急回收、审计链和可读目录白名单约束。\(device.isEmpty ? "" : "当前已绑定 \(device)。")"
        }
        return "当前档位允许完整执行面；真正生效仍需要受治理自动化绑定与权限就绪。"
    }
}

private func xtEffectiveDeviceAuthorityDetail(
    posture: AXProjectDeviceAuthorityPosture,
    resolved: AXProjectResolvedGovernanceState,
    effectiveCapability _: AXProjectCapabilityBundle
) -> String {
    switch posture {
    case .off:
        if resolved.effectiveRuntimeSurface.killSwitchEngaged {
            return "Hub 紧急回收已生效，设备面当前已 fail-closed。"
        }
        if resolved.effectiveRuntimeSurface.expired {
            return "执行面 TTL 已过期，设备面已自动回收。"
        }
        if resolved.effectiveRuntimeSurface.effectiveMode != .trustedOpenClawMode {
            return "当前生效执行面还不是完整执行面，设备面保持关闭。"
        }
        if !resolved.trustedAutomationStatus.trustedAutomationReady {
            return "受治理自动化 / 权限宿主未就绪，设备面尚未生效。"
        }
        return "当前设备面未放行。"
    case .projectBound:
        return "设备能力当前只在当前项目范围内受治理放行。"
    case .deviceGoverned:
        let device = resolved.trustedAutomationStatus.boundDeviceID
        if device.isEmpty {
            return "设备能力已进入受治理执行面。"
        }
        return "设备能力已进入受治理执行面，当前绑定设备 \(device)。"
    }
}

private func xtSupervisorScopeDetail(
    scope: AXProjectSupervisorScope,
    hubMemoryEnabled: Bool,
    effective: Bool
) -> String {
    switch scope {
        case .focusedProject:
            return effective && !hubMemoryEnabled
                ? "当前更偏向本地连续上下文和当前项目摘要，不主动放大全局检索范围。"
                : "默认只围绕当前项目和记忆摘要做判断。"
        case .portfolio:
            return "默认可看全部项目的概要状态，并对当前项目做深钻。"
        case .deviceGoverned:
            return hubMemoryEnabled
                ? "默认可在受治理前提下读取全局项目、授权、事故和已批准根目录。"
                : "当前目标是设备治理视角，但 Hub 记忆关闭会收窄上下文来源。"
        }
}

private func xtGrantDetail(
    posture: AXProjectGrantPosture,
    effective: Bool
) -> String {
    switch posture {
    case .manualReview:
        return effective
            ? "当前外部副作用与中高风险动作以人工 / Hub 审批为主。"
            : "默认把中高风险与外部副作用留给人工 / Hub 审批。"
    case .guidedAuto:
        return effective
            ? "低风险能力可自动通过，高风险继续走人工 / Hub 门禁。"
            : "默认让低风险官方能力自动通过，高风险继续走人工 / Hub 门禁。"
    case .envelopeAuto:
        return effective
            ? "按能力包络自动推进，但支付、删除、范围扩张仍继续受审批。"
            : "默认允许按能力包络预授权推进，但支付、删除、范围扩张仍继续受审批。"
    }
}

private func xtConfiguredTemplateDeviationReasons(_ config: AXProjectConfig) -> [String] {
    let template = xtConfiguredGovernanceTemplate(for: config)
    guard template == .custom else { return [] }
    let baseline = xtGovernanceTemplateBaseline(for: config.executionTier)
    guard let spec = AXProjectGovernanceTemplateSpec(template: baseline) else { return [] }

    var reasons: [String] = []
    if config.executionTier != spec.executionTier {
        reasons.append("执行档位已偏离 \(baseline.displayName) 默认档。")
    }
    if config.supervisorInterventionTier != spec.supervisorTier {
        reasons.append("监督档位已被单独调节。")
    }
    if config.reviewPolicyMode != spec.reviewPolicyMode
        || config.progressHeartbeatSeconds != spec.progressHeartbeatSeconds
        || config.reviewPulseSeconds != spec.reviewPulseSeconds
        || config.brainstormReviewSeconds != spec.brainstormReviewSeconds
        || config.eventDrivenReviewEnabled != spec.eventDrivenReviewEnabled
        || config.eventReviewTriggers != spec.eventReviewTriggers {
        reasons.append("审查节奏 / 触发器已偏离默认映射。")
    }
    if config.runtimeSurfaceMode != spec.runtimeSurfaceMode {
        reasons.append("执行面预设已被单独改动。")
    }
    if config.governedAutoApproveLocalToolCalls != spec.localAutoApproveConfigured {
        reasons.append("本地自动审批已被单独改动。")
    }
    if config.runtimeSurfaceHubOverrideMode != .none {
        reasons.append("终端本地收束当前不为无。")
    }
    if spec.requiresHubMemory && !config.preferHubMemory {
        reasons.append("当前档位要求 Hub 记忆，但项目已切到仅本地提示记忆。")
    }
    return Array(reasons.prefix(4))
}

private func xtEffectiveTemplateDeviationReasons(
    config: AXProjectConfig,
    resolved: AXProjectResolvedGovernanceState,
    effectiveCapability: AXProjectCapabilityBundle
) -> [String] {
    var reasons: [String] = []
    if resolved.validation.shouldFailClosed {
        reasons.append("当前治理组合无效，运行时已 fail-closed 到保守基线。")
    }
    if resolved.effectiveRuntimeSurface.killSwitchEngaged {
        reasons.append("Hub 紧急回收已回收高风险执行面。")
    } else if resolved.effectiveRuntimeSurface.expired {
        reasons.append("执行面 TTL 已过期，执行面已自动回收。")
    } else if resolved.effectiveRuntimeSurface.hubOverrideMode != .none {
        reasons.append("当前存在收束：\(resolved.effectiveRuntimeSurface.hubOverrideMode.displayName)。")
    }
    if config.executionTier == .a4OpenClaw && !resolved.trustedAutomationStatus.trustedAutomationReady {
        reasons.append("受治理自动化未就绪，完整设备面尚未真正放行。")
    }
    if config.governedAutoApproveLocalToolCalls && !effectiveCapability.allowAutoLocalApproval {
        reasons.append("本地自动审批已配置，但当前生效能力还未放行。")
    }
    return Array(reasons.prefix(4))
}

private func xtRuntimeSummary(
    config: AXProjectConfig,
    resolved: AXProjectResolvedGovernanceState
) -> String {
    let ttl: String
    if resolved.effectiveRuntimeSurface.killSwitchEngaged {
        ttl = "kill_switch"
    } else if resolved.effectiveRuntimeSurface.expired {
        ttl = "expired"
    } else if config.runtimeSurfaceMode == .manual {
        ttl = "n/a"
    } else {
        ttl = "\(max(1, (resolved.effectiveRuntimeSurface.remainingSeconds + 59) / 60))m"
    }
    let clamp = resolved.effectiveRuntimeSurface.hubOverrideMode.displayName
    let hubMemory = config.preferHubMemory ? "Hub" : "Local"
    return "记忆来源：\(hubMemory) · 执行面 TTL 剩余：\(ttl) · 本地收束：\(config.runtimeSurfaceHubOverrideMode.displayName) · 生效收束：\(clamp)"
}

private func xtEffectiveTemplateSummary(
    template: AXProjectGovernanceTemplate,
    resolved: AXProjectResolvedGovernanceState,
    effectiveCapability _: AXProjectCapabilityBundle
) -> String {
    if template == .custom {
        if resolved.validation.shouldFailClosed {
            return "当前生效状态已因无效组合进入保守 fail-closed。"
        }
        if resolved.effectiveRuntimeSurface.killSwitchEngaged {
            return "当前生效状态已被紧急回收。"
        }
        if resolved.effectiveRuntimeSurface.expired {
            return "当前生效状态已因执行面 TTL 到期被回收。"
        }
        if resolved.effectiveRuntimeSurface.hubOverrideMode != .none {
            return "当前生效状态已被运行时收束收窄。"
        }
        return "当前生效状态仍受就绪状态、授权门和治理细项共同影响。"
    }
    return template.shortDescription
}
