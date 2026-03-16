import Foundation

enum AXProjectAutonomyProfile: String, CaseIterable, Sendable, Identifiable {
    case conservative
    case safe
    case fullAutonomy = "full_autonomy"
    case custom

    static let selectableProfiles: [AXProjectAutonomyProfile] = [
        .conservative,
        .safe,
        .fullAutonomy,
    ]

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .conservative:
            return "保守"
        case .safe:
            return "安全"
        case .fullAutonomy:
            return "完全自治"
        case .custom:
            return "自定义"
        }
    }

    var shortDescription: String {
        switch self {
        case .conservative:
            return "以理解、规划和审阅为主，默认走人工审批。"
        case .safe:
            return "推荐默认档，project 内持续推进，高风险仍走治理。"
        case .fullAutonomy:
            return "允许完整执行面，但继续受 Hub grant、宪章和 kill-switch 约束。"
        case .custom:
            return "当前高级治理项已偏离默认映射。"
        }
    }
}

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
            return "Portfolio"
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

struct AXProjectAutonomySwitchboardPresentation: Equatable, Sendable {
    var configuredProfile: AXProjectAutonomyProfile
    var effectiveProfile: AXProjectAutonomyProfile
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

private struct AXProjectAutonomyProfileSpec {
    var profile: AXProjectAutonomyProfile
    var executionTier: AXProjectExecutionTier
    var supervisorTier: AXProjectSupervisorInterventionTier
    var reviewPolicyMode: AXProjectReviewPolicyMode
    var progressHeartbeatSeconds: Int
    var reviewPulseSeconds: Int
    var brainstormReviewSeconds: Int
    var eventDrivenReviewEnabled: Bool
    var eventReviewTriggers: [AXProjectReviewTrigger]
    var autonomyMode: AXProjectAutonomyMode
    var localAutoApproveConfigured: Bool
    var requiresHubMemory: Bool
    var deviceAuthorityPosture: AXProjectDeviceAuthorityPosture
    var supervisorScope: AXProjectSupervisorScope
    var grantPosture: AXProjectGrantPosture

    init?(profile: AXProjectAutonomyProfile) {
        switch profile {
        case .conservative:
            let bundle = AXProjectGovernanceBundle.recommended(
                for: .a1Plan,
                supervisorInterventionTier: .s2PeriodicReview
            )
            self.profile = profile
            executionTier = .a1Plan
            supervisorTier = .s2PeriodicReview
            reviewPolicyMode = bundle.reviewPolicyMode
            progressHeartbeatSeconds = bundle.schedule.progressHeartbeatSeconds
            reviewPulseSeconds = bundle.schedule.reviewPulseSeconds
            brainstormReviewSeconds = bundle.schedule.brainstormReviewSeconds
            eventDrivenReviewEnabled = bundle.schedule.eventDrivenReviewEnabled
            eventReviewTriggers = bundle.schedule.eventReviewTriggers
            autonomyMode = .manual
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
            self.profile = profile
            executionTier = .a3DeliverAuto
            supervisorTier = .s3StrategicCoach
            reviewPolicyMode = bundle.reviewPolicyMode
            progressHeartbeatSeconds = bundle.schedule.progressHeartbeatSeconds
            reviewPulseSeconds = bundle.schedule.reviewPulseSeconds
            brainstormReviewSeconds = bundle.schedule.brainstormReviewSeconds
            eventDrivenReviewEnabled = bundle.schedule.eventDrivenReviewEnabled
            eventReviewTriggers = bundle.schedule.eventReviewTriggers
            autonomyMode = .guided
            localAutoApproveConfigured = false
            requiresHubMemory = false
            deviceAuthorityPosture = .projectBound
            supervisorScope = .portfolio
            grantPosture = .guidedAuto
        case .fullAutonomy:
            let bundle = AXProjectGovernanceBundle.recommended(
                for: .a4OpenClaw,
                supervisorInterventionTier: .s3StrategicCoach
            )
            self.profile = profile
            executionTier = .a4OpenClaw
            supervisorTier = .s3StrategicCoach
            reviewPolicyMode = bundle.reviewPolicyMode
            progressHeartbeatSeconds = bundle.schedule.progressHeartbeatSeconds
            reviewPulseSeconds = bundle.schedule.reviewPulseSeconds
            brainstormReviewSeconds = bundle.schedule.brainstormReviewSeconds
            eventDrivenReviewEnabled = bundle.schedule.eventDrivenReviewEnabled
            eventReviewTriggers = bundle.schedule.eventReviewTriggers
            autonomyMode = .trustedOpenClawMode
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

private struct AXProjectAutonomyProfileSnapshot {
    var executionTier: AXProjectExecutionTier
    var supervisorTier: AXProjectSupervisorInterventionTier
    var reviewPolicyMode: AXProjectReviewPolicyMode
    var progressHeartbeatSeconds: Int
    var reviewPulseSeconds: Int
    var brainstormReviewSeconds: Int
    var eventDrivenReviewEnabled: Bool
    var eventReviewTriggers: [AXProjectReviewTrigger]
    var autonomyMode: AXProjectAutonomyMode
    var localAutoApproveConfigured: Bool
    var hubMemoryEnabled: Bool
    var terminalClamp: AXProjectAutonomyHubOverrideMode
}

extension AXProjectConfig {
    func settingAutonomySwitchboardProfile(
        _ profile: AXProjectAutonomyProfile,
        projectRoot _: URL,
        now: Date = Date()
    ) -> AXProjectConfig {
        guard let spec = AXProjectAutonomyProfileSpec(profile: profile) else { return self }

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
        out = out.settingAutonomyPolicy(
            mode: spec.autonomyMode,
            ttlSeconds: 3600,
            hubOverrideMode: AXProjectAutonomyHubOverrideMode.none,
            updatedAt: now
        )
        out = out.settingGovernedAutoApproveLocalToolCalls(enabled: spec.localAutoApproveConfigured)
        if spec.requiresHubMemory {
            out = out.settingHubMemoryPreference(enabled: true)
        }
        return out
    }
}

func xtAutonomyBaselineProfile(for executionTier: AXProjectExecutionTier) -> AXProjectAutonomyProfile {
    switch executionTier {
    case .a0Observe, .a1Plan:
        return .conservative
    case .a2RepoAuto, .a3DeliverAuto:
        return .safe
    case .a4OpenClaw:
        return .fullAutonomy
    }
}

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
    let normalizedBaseline = AXProjectAutonomyProfile.selectableProfiles.contains(baselineProfile)
        ? baselineProfile
        : xtAutonomyBaselineProfile(for: executionTier)

    return AXProjectConfig
        .default(forProjectRoot: projectRoot)
        .settingAutonomySwitchboardProfile(
            normalizedBaseline,
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
            eventReviewTriggers: executionTier.defaultEventReviewTriggers,
            governanceCompatSource: .explicitDualDial
        )
}

func xtProjectAutonomySwitchboardPresentation(
    projectRoot: URL,
    config: AXProjectConfig,
    resolved: AXProjectResolvedGovernanceState
) -> AXProjectAutonomySwitchboardPresentation {
    let configuredProfile = xtConfiguredAutonomyProfile(for: config)
    let configuredAuthority = xtProjectGovernedAuthorityPresentation(
        projectRoot: projectRoot,
        config: config
    )
    let effectiveCapability = resolved.effectiveBundle.executionTier.baseCapabilityBundle.applying(
        effectiveAutonomy: resolved.effectiveAutonomy,
        trustedAutomationStatus: resolved.trustedAutomationStatus
    )
    let effectiveProfile = xtEffectiveAutonomyProfile(
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

    return AXProjectAutonomySwitchboardPresentation(
        configuredProfile: configuredProfile,
        effectiveProfile: effectiveProfile,
        configuredDeviceAuthorityPosture: configuredDeviceAuthority,
        effectiveDeviceAuthorityPosture: effectiveDeviceAuthority,
        configuredSupervisorScope: configuredSupervisorScope,
        effectiveSupervisorScope: effectiveSupervisorScope,
        configuredGrantPosture: configuredGrantPosture,
        effectiveGrantPosture: effectiveGrantPosture,
        configuredProfileSummary: configuredProfile.shortDescription,
        effectiveProfileSummary: xtEffectiveProfileSummary(
            profile: effectiveProfile,
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
        configuredDeviationReasons: xtConfiguredDeviationReasons(config),
        effectiveDeviationReasons: xtEffectiveDeviationReasons(
            config: config,
            resolved: resolved,
            effectiveCapability: effectiveCapability
        ),
        runtimeSummary: runtimeSummary
    )
}

private func xtConfiguredAutonomyProfile(for config: AXProjectConfig) -> AXProjectAutonomyProfile {
    if xtMatchesLegacyConservativeProfile(config) || xtMatchesProfile(config, profile: .conservative) {
        return .conservative
    }
    if xtMatchesProfile(config, profile: .safe) {
        return .safe
    }
    if xtMatchesProfile(config, profile: .fullAutonomy) {
        return .fullAutonomy
    }
    return .custom
}

private func xtEffectiveAutonomyProfile(
    config: AXProjectConfig,
    resolved: AXProjectResolvedGovernanceState,
    effectiveCapability: AXProjectCapabilityBundle
) -> AXProjectAutonomyProfile {
    let snapshot = AXProjectAutonomyProfileSnapshot(
        executionTier: resolved.effectiveBundle.executionTier,
        supervisorTier: resolved.effectiveBundle.supervisorInterventionTier,
        reviewPolicyMode: resolved.effectiveBundle.reviewPolicyMode,
        progressHeartbeatSeconds: resolved.effectiveBundle.schedule.progressHeartbeatSeconds,
        reviewPulseSeconds: resolved.effectiveBundle.schedule.reviewPulseSeconds,
        brainstormReviewSeconds: resolved.effectiveBundle.schedule.brainstormReviewSeconds,
        eventDrivenReviewEnabled: resolved.effectiveBundle.schedule.eventDrivenReviewEnabled,
        eventReviewTriggers: resolved.effectiveBundle.schedule.eventReviewTriggers,
        autonomyMode: resolved.effectiveAutonomy.effectiveMode,
        localAutoApproveConfigured: effectiveCapability.allowAutoLocalApproval,
        hubMemoryEnabled: config.preferHubMemory,
        terminalClamp: resolved.effectiveAutonomy.hubOverrideMode
    )

    if xtMatchesLegacyConservativeProfile(snapshot) || xtMatchesProfile(snapshot, profile: .conservative) {
        return .conservative
    }
    if xtMatchesProfile(snapshot, profile: .safe) {
        return .safe
    }
    if xtMatchesProfile(snapshot, profile: .fullAutonomy) {
        return .fullAutonomy
    }
    return .custom
}

private func xtMatchesProfile(
    _ config: AXProjectConfig,
    profile: AXProjectAutonomyProfile
) -> Bool {
    let snapshot = AXProjectAutonomyProfileSnapshot(
        executionTier: config.executionTier,
        supervisorTier: config.supervisorInterventionTier,
        reviewPolicyMode: config.reviewPolicyMode,
        progressHeartbeatSeconds: config.progressHeartbeatSeconds,
        reviewPulseSeconds: config.reviewPulseSeconds,
        brainstormReviewSeconds: config.brainstormReviewSeconds,
        eventDrivenReviewEnabled: config.eventDrivenReviewEnabled,
        eventReviewTriggers: config.eventReviewTriggers,
        autonomyMode: config.autonomyMode,
        localAutoApproveConfigured: config.governedAutoApproveLocalToolCalls,
        hubMemoryEnabled: config.preferHubMemory,
        terminalClamp: config.autonomyHubOverrideMode
    )
    return xtMatchesProfile(snapshot, profile: profile)
}

private func xtMatchesProfile(
    _ snapshot: AXProjectAutonomyProfileSnapshot,
    profile: AXProjectAutonomyProfile
) -> Bool {
    guard let spec = AXProjectAutonomyProfileSpec(profile: profile) else { return false }
    if snapshot.executionTier != spec.executionTier { return false }
    if snapshot.supervisorTier != spec.supervisorTier { return false }
    if snapshot.reviewPolicyMode != spec.reviewPolicyMode { return false }
    if snapshot.progressHeartbeatSeconds != spec.progressHeartbeatSeconds { return false }
    if snapshot.reviewPulseSeconds != spec.reviewPulseSeconds { return false }
    if snapshot.brainstormReviewSeconds != spec.brainstormReviewSeconds { return false }
    if snapshot.eventDrivenReviewEnabled != spec.eventDrivenReviewEnabled { return false }
    if snapshot.eventReviewTriggers != spec.eventReviewTriggers { return false }
    if snapshot.autonomyMode != spec.autonomyMode { return false }
    if snapshot.localAutoApproveConfigured != spec.localAutoApproveConfigured { return false }
    if snapshot.terminalClamp != .none { return false }
    if spec.requiresHubMemory && !snapshot.hubMemoryEnabled { return false }
    return true
}

private func xtMatchesLegacyConservativeProfile(_ config: AXProjectConfig) -> Bool {
    let snapshot = AXProjectAutonomyProfileSnapshot(
        executionTier: config.executionTier,
        supervisorTier: config.supervisorInterventionTier,
        reviewPolicyMode: config.reviewPolicyMode,
        progressHeartbeatSeconds: config.progressHeartbeatSeconds,
        reviewPulseSeconds: config.reviewPulseSeconds,
        brainstormReviewSeconds: config.brainstormReviewSeconds,
        eventDrivenReviewEnabled: config.eventDrivenReviewEnabled,
        eventReviewTriggers: config.eventReviewTriggers,
        autonomyMode: config.autonomyMode,
        localAutoApproveConfigured: config.governedAutoApproveLocalToolCalls,
        hubMemoryEnabled: config.preferHubMemory,
        terminalClamp: config.autonomyHubOverrideMode
    )
    return xtMatchesLegacyConservativeProfile(snapshot)
}

private func xtMatchesLegacyConservativeProfile(_ snapshot: AXProjectAutonomyProfileSnapshot) -> Bool {
    snapshot.executionTier == .a0Observe
        && snapshot.supervisorTier == .s0SilentAudit
        && snapshot.reviewPolicyMode == .milestoneOnly
        && snapshot.progressHeartbeatSeconds == AXProjectGovernanceBundle.recommended(for: .a0Observe).schedule.progressHeartbeatSeconds
        && snapshot.reviewPulseSeconds == 0
        && snapshot.brainstormReviewSeconds == 0
        && snapshot.eventDrivenReviewEnabled == false
        && snapshot.eventReviewTriggers == [.manualRequest]
        && snapshot.autonomyMode == .manual
        && snapshot.localAutoApproveConfigured == false
        && snapshot.terminalClamp == .none
}

private func xtConfiguredDeviceAuthorityPosture(
    config: AXProjectConfig,
    profile: AXProjectAutonomyProfile
) -> AXProjectDeviceAuthorityPosture {
    if let spec = AXProjectAutonomyProfileSpec(profile: profile) {
        return spec.deviceAuthorityPosture
    }
    if config.executionTier == .a4OpenClaw {
        return .deviceGoverned
    }
    if config.executionTier == .a2RepoAuto || config.executionTier == .a3DeliverAuto {
        if config.autonomyMode == .trustedOpenClawMode
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
    profile: AXProjectAutonomyProfile
) -> AXProjectSupervisorScope {
    if let spec = AXProjectAutonomyProfileSpec(profile: profile) {
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
        return resolved.effectiveAutonomy.effectiveMode == .trustedOpenClawMode ? .deviceGoverned : .portfolio
    }
}

private func xtConfiguredGrantPosture(
    config: AXProjectConfig,
    profile: AXProjectAutonomyProfile
) -> AXProjectGrantPosture {
    if let spec = AXProjectAutonomyProfileSpec(profile: profile) {
        return spec.grantPosture
    }
    if config.executionTier == .a4OpenClaw && config.autonomyMode == .trustedOpenClawMode {
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
        || resolved.effectiveAutonomy.killSwitchEngaged
        || resolved.effectiveAutonomy.effectiveMode == .manual {
        return .manualReview
    }
    if resolved.effectiveBundle.executionTier == .a4OpenClaw
        && resolved.effectiveAutonomy.effectiveMode == .trustedOpenClawMode {
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
            return "当前预设默认关闭设备级能力；Governance Details 里保留的绑定不会被本档直接放行。"
        }
        return "当前主档默认不触达设备级执行面。"
    case .projectBound:
        if authority.deviceAuthorityConfigured {
            let device = trustedAutomationStatus.boundDeviceID.isEmpty ? authority.pairedDeviceId : trustedAutomationStatus.boundDeviceID
            return "默认把设备能力收束在当前 project 边界内。\(device.isEmpty ? "" : "当前已绑定 \(device)。")"
        }
        return "默认只允许当前 project 在受治理前提下使用设备能力；仍需在 Governance Details 完成 trusted automation 绑定。"
    case .deviceGoverned:
        if authority.deviceAuthorityConfigured {
            let device = trustedAutomationStatus.boundDeviceID.isEmpty ? authority.pairedDeviceId : trustedAutomationStatus.boundDeviceID
            return "当前档位允许完整执行面，但仍继续受 Hub grant、kill-switch、审计链和 readable roots 约束。\(device.isEmpty ? "" : "当前已绑定 \(device)。")"
        }
        return "当前档位允许完整执行面；真正生效仍需要 trusted automation 绑定与权限就绪。"
    }
}

private func xtEffectiveDeviceAuthorityDetail(
    posture: AXProjectDeviceAuthorityPosture,
    resolved: AXProjectResolvedGovernanceState,
    effectiveCapability _: AXProjectCapabilityBundle
) -> String {
    switch posture {
    case .off:
        if resolved.effectiveAutonomy.killSwitchEngaged {
            return "Hub kill-switch 已生效，设备面当前 fail-closed。"
        }
        if resolved.effectiveAutonomy.expired {
            return "runtime surface TTL 已过期，设备面已自动回收。"
        }
        if resolved.effectiveAutonomy.effectiveMode != .trustedOpenClawMode {
            return "当前 effective surface 不是 full surface，设备面保持关闭。"
        }
        if !resolved.trustedAutomationStatus.trustedAutomationReady {
            return "trusted automation / permission owner 未就绪，设备面尚未生效。"
        }
        return "当前设备面未放行。"
    case .projectBound:
        return "设备能力当前只在本 project 范围内受治理放行。"
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
            ? "当前更偏向本地 continuity 和当前 project 摘要，不主动放大全局检索范围。"
            : "默认只围绕当前 project 和记忆摘要做判断。"
    case .portfolio:
        return "默认可看全部 project 的概要状态，并对当前 project 做深钻。"
    case .deviceGoverned:
        return hubMemoryEnabled
            ? "默认可在受治理前提下读取 portfolio、grants、incidents 和已批准 roots。"
            : "当前目标是设备治理视角，但 Hub memory 关闭会收窄上下文来源。"
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
            ? "按能力包络自动推进，但支付、删除、scope 扩张仍继续受审批。"
            : "默认允许按能力包络预授权推进，但支付、删除、scope 扩张仍继续受审批。"
    }
}

private func xtConfiguredDeviationReasons(_ config: AXProjectConfig) -> [String] {
    let profile = xtConfiguredAutonomyProfile(for: config)
    guard profile == .custom else { return [] }
    let baseline = xtAutonomyBaselineProfile(for: config.executionTier)
    guard let spec = AXProjectAutonomyProfileSpec(profile: baseline) else { return [] }

    var reasons: [String] = []
    if config.executionTier != spec.executionTier {
        reasons.append("execution tier 已偏离 \(baseline.displayName) 默认档。")
    }
    if config.supervisorInterventionTier != spec.supervisorTier {
        reasons.append("supervisor tier 已被单独调节。")
    }
    if config.reviewPolicyMode != spec.reviewPolicyMode
        || config.progressHeartbeatSeconds != spec.progressHeartbeatSeconds
        || config.reviewPulseSeconds != spec.reviewPulseSeconds
        || config.brainstormReviewSeconds != spec.brainstormReviewSeconds
        || config.eventDrivenReviewEnabled != spec.eventDrivenReviewEnabled
        || config.eventReviewTriggers != spec.eventReviewTriggers {
        reasons.append("review cadence / trigger 已偏离默认映射。")
    }
    if config.autonomyMode != spec.autonomyMode {
        reasons.append("runtime surface preset 已被单独改动。")
    }
    if config.governedAutoApproveLocalToolCalls != spec.localAutoApproveConfigured {
        reasons.append("local auto-approve 已被单独改动。")
    }
    if config.autonomyHubOverrideMode != .none {
        reasons.append("Terminal clamp 当前不为 none。")
    }
    if spec.requiresHubMemory && !config.preferHubMemory {
        reasons.append("当前档位要求 Hub memory，但项目已切到 local-only prompt memory。")
    }
    return Array(reasons.prefix(4))
}

private func xtEffectiveDeviationReasons(
    config: AXProjectConfig,
    resolved: AXProjectResolvedGovernanceState,
    effectiveCapability: AXProjectCapabilityBundle
) -> [String] {
    var reasons: [String] = []
    if resolved.validation.shouldFailClosed {
        reasons.append("当前治理组合无效，runtime 已 fail-closed 到保守基线。")
    }
    if resolved.effectiveAutonomy.killSwitchEngaged {
        reasons.append("Hub kill-switch 已回收高风险执行面。")
    } else if resolved.effectiveAutonomy.expired {
        reasons.append("runtime surface TTL 已过期，执行面已自动回收。")
    } else if resolved.effectiveAutonomy.hubOverrideMode != .none {
        reasons.append("当前存在 clamp：\(resolved.effectiveAutonomy.hubOverrideMode.displayName)。")
    }
    if config.executionTier == .a4OpenClaw && !resolved.trustedAutomationStatus.trustedAutomationReady {
        reasons.append("trusted automation 未就绪，完整设备面尚未真正放行。")
    }
    if config.governedAutoApproveLocalToolCalls && !effectiveCapability.allowAutoLocalApproval {
        reasons.append("local auto-approve 已配置，但当前 effective capability 还未放行。")
    }
    return Array(reasons.prefix(4))
}

private func xtRuntimeSummary(
    config: AXProjectConfig,
    resolved: AXProjectResolvedGovernanceState
) -> String {
    let ttl: String
    if resolved.effectiveAutonomy.killSwitchEngaged {
        ttl = "kill_switch"
    } else if resolved.effectiveAutonomy.expired {
        ttl = "expired"
    } else if config.autonomyMode == .manual {
        ttl = "n/a"
    } else {
        ttl = "\(max(1, (resolved.effectiveAutonomy.remainingSeconds + 59) / 60))m"
    }
    let clamp = resolved.effectiveAutonomy.hubOverrideMode.displayName
    let hubMemory = config.preferHubMemory ? "Hub" : "Local"
    return "记忆来源: \(hubMemory) · surface TTL 剩余: \(ttl) · 本地 clamp: \(config.autonomyHubOverrideMode.displayName) · 生效 clamp: \(clamp)"
}

private func xtEffectiveProfileSummary(
    profile: AXProjectAutonomyProfile,
    resolved: AXProjectResolvedGovernanceState,
    effectiveCapability _: AXProjectCapabilityBundle
) -> String {
    if profile == .custom {
        if resolved.validation.shouldFailClosed {
            return "当前生效状态已因无效组合进入保守 fail-closed。"
        }
        if resolved.effectiveAutonomy.killSwitchEngaged {
            return "当前生效状态已被 kill-switch 回收。"
        }
        if resolved.effectiveAutonomy.expired {
            return "当前生效状态已因 runtime surface TTL 到期被回收。"
        }
        if resolved.effectiveAutonomy.hubOverrideMode != .none {
            return "当前生效状态已被 runtime clamp 收窄。"
        }
        return "当前生效状态仍受 readiness、grant 和治理细项共同影响。"
    }
    return profile.shortDescription
}
