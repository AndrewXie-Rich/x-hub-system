import Foundation

enum AXProjectRuntimeSurfaceMode: String, Codable, Equatable, CaseIterable {
    case manual
    case guided
    // Legacy raw value retained for on-disk and bridge compatibility.
    case trustedOpenClawMode = "trusted_openclaw_mode"

    var displayName: String {
        switch self {
        case .manual:
            return "Manual"
        case .guided:
            return "Guided"
        case .trustedOpenClawMode:
            return "Trusted Agent Surface"
        }
    }
}

enum AXProjectRuntimeSurfaceHubOverrideMode: String, Codable, Equatable, CaseIterable {
    case none
    case clampGuided = "clamp_guided"
    case clampManual = "clamp_manual"
    case killSwitch = "kill_switch"

    var displayName: String {
        switch self {
        case .none:
            return "None"
        case .clampGuided:
            return "Clamp Guided"
        case .clampManual:
            return "Clamp Manual"
        case .killSwitch:
            return "Kill Switch"
        }
    }
}

struct AXProjectRuntimeSurfaceRemoteOverrideSnapshot: Equatable, Sendable {
    var projectId: String
    var overrideMode: AXProjectRuntimeSurfaceHubOverrideMode
    var updatedAtMs: Int64
    var source: String
    var reason: String?
    var auditRef: String?
}

struct AXProjectRuntimeSurfaceEffectivePolicy: Equatable, Sendable {
    var configuredMode: AXProjectRuntimeSurfaceMode
    var effectiveMode: AXProjectRuntimeSurfaceMode
    var hubOverrideMode: AXProjectRuntimeSurfaceHubOverrideMode
    var localOverrideMode: AXProjectRuntimeSurfaceHubOverrideMode
    var remoteOverrideMode: AXProjectRuntimeSurfaceHubOverrideMode
    var remoteOverrideUpdatedAtMs: Int64
    var remoteOverrideSource: String
    var allowDeviceTools: Bool
    var allowBrowserRuntime: Bool
    var allowConnectorActions: Bool
    var allowExtensions: Bool
    var ttlSeconds: Int
    var remainingSeconds: Int
    var expired: Bool
    var killSwitchEngaged: Bool

    var allowedSurfaceLabels: [String] {
        var labels: [String] = []
        if allowDeviceTools { labels.append("device") }
        if allowBrowserRuntime { labels.append("browser") }
        if allowConnectorActions { labels.append("connector") }
        if allowExtensions { labels.append("extension") }
        return labels
    }
}

struct AXProjectResolvedRuntimeSurfacePolicyState: Equatable, Sendable {
    var projectId: String
    var remoteOverride: AXProjectRuntimeSurfaceRemoteOverrideSnapshot?
    var effectivePolicy: AXProjectRuntimeSurfaceEffectivePolicy
}

private struct AXProjectRuntimeSurfacePreset {
    var allowDeviceTools: Bool
    var allowBrowserRuntime: Bool
    var allowConnectorActions: Bool
    var allowExtensions: Bool
}

private func xtProjectRuntimeSurfacePreset(
    for mode: AXProjectRuntimeSurfaceMode
) -> AXProjectRuntimeSurfacePreset {
    switch mode {
    case .manual:
        return AXProjectRuntimeSurfacePreset(
            allowDeviceTools: false,
            allowBrowserRuntime: false,
            allowConnectorActions: false,
            allowExtensions: false
        )
    case .guided:
        return AXProjectRuntimeSurfacePreset(
            allowDeviceTools: false,
            allowBrowserRuntime: true,
            allowConnectorActions: false,
            allowExtensions: false
        )
    case .trustedOpenClawMode:
        return AXProjectRuntimeSurfacePreset(
            allowDeviceTools: true,
            allowBrowserRuntime: true,
            allowConnectorActions: true,
            allowExtensions: true
        )
    }
}

private func xtRuntimeSurfaceOverrideRank(_ mode: AXProjectRuntimeSurfaceHubOverrideMode) -> Int {
    switch mode {
    case .none:
        return 0
    case .clampGuided:
        return 1
    case .clampManual:
        return 2
    case .killSwitch:
        return 3
    }
}

private func xtResolvedRuntimeSurfaceOverrideMode(
    local: AXProjectRuntimeSurfaceHubOverrideMode,
    remote: AXProjectRuntimeSurfaceHubOverrideMode
) -> AXProjectRuntimeSurfaceHubOverrideMode {
    xtRuntimeSurfaceOverrideRank(remote) > xtRuntimeSurfaceOverrideRank(local) ? remote : local
}

func xtResolveProjectRuntimeSurfacePolicy(
    projectRoot: URL,
    config: AXProjectConfig
) async -> AXProjectResolvedRuntimeSurfacePolicyState {
    let projectId = AXProjectRegistryStore.projectId(forRoot: projectRoot)
    let remoteOverride = await HubIPCClient.requestProjectRuntimeSurfaceOverride(projectId: projectId)
    return AXProjectResolvedRuntimeSurfacePolicyState(
        projectId: projectId,
        remoteOverride: remoteOverride,
        effectivePolicy: config.effectiveRuntimeSurfacePolicy(remoteOverride: remoteOverride)
    )
}

func xtProjectGovernedDeviceAuthorityEnabled(
    projectRoot: URL,
    config: AXProjectConfig,
    effectiveRuntimeSurface: AXProjectRuntimeSurfaceEffectivePolicy
) -> Bool {
    guard xtProjectGovernedDeviceAuthorityConfigured(
        projectRoot: projectRoot,
        config: config
    ) else { return false }
    guard effectiveRuntimeSurface.effectiveMode == .trustedOpenClawMode else { return false }
    return effectiveRuntimeSurface.allowDeviceTools
}

func xtProjectGovernedDeviceAuthorityConfigured(
    projectRoot: URL,
    config: AXProjectConfig
) -> Bool {
    guard config.autonomyMode == .trustedOpenClawMode else { return false }
    guard config.autonomyAllowDeviceTools else { return false }
    guard config.automationMode == .trustedAutomation else { return false }
    guard !config.trustedAutomationDeviceId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        return false
    }

    let expectedWorkspaceBindingHash = xtTrustedAutomationWorkspaceHash(forProjectRoot: projectRoot)
    let configuredWorkspaceBindingHash = config.workspaceBindingHash.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !configuredWorkspaceBindingHash.isEmpty else { return false }
    return configuredWorkspaceBindingHash == expectedWorkspaceBindingHash
}

func xtProjectGovernedAutoApprovalConfigured(
    projectRoot: URL,
    config: AXProjectConfig
) -> Bool {
    guard config.governedAutoApproveLocalToolCalls else { return false }
    return xtProjectGovernedDeviceAuthorityConfigured(
        projectRoot: projectRoot,
        config: config
    )
}

func xtProjectGovernedAutoApprovalEnabled(
    projectRoot: URL,
    config: AXProjectConfig,
    effectiveRuntimeSurface: AXProjectRuntimeSurfaceEffectivePolicy
) -> Bool {
    guard xtProjectGovernedAutoApprovalConfigured(
        projectRoot: projectRoot,
        config: config
    ) else { return false }
    guard effectiveRuntimeSurface.effectiveMode == .trustedOpenClawMode else { return false }
    return effectiveRuntimeSurface.allowDeviceTools
}

extension AXProjectConfig {
    var runtimeSurfaceMode: AXProjectRuntimeSurfaceMode {
        get { autonomyMode }
        set { autonomyMode = newValue }
    }

    var runtimeSurfaceAllowDeviceTools: Bool {
        get { autonomyAllowDeviceTools }
        set { autonomyAllowDeviceTools = newValue }
    }

    var runtimeSurfaceAllowBrowserRuntime: Bool {
        get { autonomyAllowBrowserRuntime }
        set { autonomyAllowBrowserRuntime = newValue }
    }

    var runtimeSurfaceAllowConnectorActions: Bool {
        get { autonomyAllowConnectorActions }
        set { autonomyAllowConnectorActions = newValue }
    }

    var runtimeSurfaceAllowExtensions: Bool {
        get { autonomyAllowExtensions }
        set { autonomyAllowExtensions = newValue }
    }

    var runtimeSurfaceTTLSeconds: Int {
        get { autonomyTTLSeconds }
        set { autonomyTTLSeconds = newValue }
    }

    var runtimeSurfaceHubOverrideMode: AXProjectRuntimeSurfaceHubOverrideMode {
        get { autonomyHubOverrideMode }
        set { autonomyHubOverrideMode = newValue }
    }

    var runtimeSurfaceUpdatedAtMs: Int64 {
        get { autonomyUpdatedAtMs }
        set { autonomyUpdatedAtMs = newValue }
    }

    var configuredRuntimeSurfaceLabels: [String] {
        var labels: [String] = []
        if runtimeSurfaceAllowBrowserRuntime { labels.append("browser") }
        if runtimeSurfaceAllowDeviceTools { labels.append("device") }
        if runtimeSurfaceAllowConnectorActions { labels.append("connector") }
        if runtimeSurfaceAllowExtensions { labels.append("extension") }
        return labels
    }

    var consumesLegacyAutonomyLevelResolverInput: Bool {
        switch governanceCompatSource {
        case .legacyAutonomyLevel, .legacyAutonomyMode:
            return true
        case .explicitDualDial, .defaultConservative:
            return false
        }
    }

    func governanceResolverLegacyAutonomyLevel(_ candidate: AutonomyLevel?) -> AutonomyLevel? {
        guard consumesLegacyAutonomyLevelResolverInput else { return nil }
        return candidate
    }

    func settingRuntimeSurfacePolicy(
        mode: AXProjectRuntimeSurfaceMode? = nil,
        allowDeviceTools: Bool? = nil,
        allowBrowserRuntime: Bool? = nil,
        allowConnectorActions: Bool? = nil,
        allowExtensions: Bool? = nil,
        ttlSeconds: Int? = nil,
        hubOverrideMode: AXProjectRuntimeSurfaceHubOverrideMode? = nil,
        updatedAt: Date = Date()
    ) -> AXProjectConfig {
        var out = self

        if let mode {
            out.runtimeSurfaceMode = mode
            let preset = xtProjectRuntimeSurfacePreset(for: mode)
            out.runtimeSurfaceAllowDeviceTools = preset.allowDeviceTools
            out.runtimeSurfaceAllowBrowserRuntime = preset.allowBrowserRuntime
            out.runtimeSurfaceAllowConnectorActions = preset.allowConnectorActions
            out.runtimeSurfaceAllowExtensions = preset.allowExtensions

            // Legacy autonomy mode remains a compatibility input until the user
            // explicitly switches the project onto the dual-dial governance model.
            if out.governanceCompatSource != .explicitDualDial {
                let recommended = AXProjectGovernanceBundle.recommended(
                    for: AXProjectExecutionTier.fromRuntimeSurfaceMode(mode)
                )
                out.executionTier = recommended.executionTier
                out.supervisorInterventionTier = recommended.supervisorInterventionTier
                out.reviewPolicyMode = recommended.reviewPolicyMode
                out.progressHeartbeatSeconds = recommended.schedule.progressHeartbeatSeconds
                out.reviewPulseSeconds = recommended.schedule.reviewPulseSeconds
                out.brainstormReviewSeconds = recommended.schedule.brainstormReviewSeconds
                out.eventDrivenReviewEnabled = recommended.schedule.eventDrivenReviewEnabled
                out.eventReviewTriggers = recommended.schedule.eventReviewTriggers
                out.governanceCompatSource = .legacyAutonomyMode
            }
        }
        if let allowDeviceTools {
            out.runtimeSurfaceAllowDeviceTools = allowDeviceTools
        }
        if let allowBrowserRuntime {
            out.runtimeSurfaceAllowBrowserRuntime = allowBrowserRuntime
        }
        if let allowConnectorActions {
            out.runtimeSurfaceAllowConnectorActions = allowConnectorActions
        }
        if let allowExtensions {
            out.runtimeSurfaceAllowExtensions = allowExtensions
        }
        if let ttlSeconds {
            out.runtimeSurfaceTTLSeconds = max(60, ttlSeconds)
        }
        if let hubOverrideMode {
            out.runtimeSurfaceHubOverrideMode = hubOverrideMode
        }

        let requestedChange = mode != nil
            || allowDeviceTools != nil
            || allowBrowserRuntime != nil
            || allowConnectorActions != nil
            || allowExtensions != nil
            || ttlSeconds != nil
            || hubOverrideMode != nil
        if requestedChange {
            out.runtimeSurfaceUpdatedAtMs = max(0, Int64((updatedAt.timeIntervalSince1970 * 1000.0).rounded()))
        }

        return out.normalizedAutomationState()
    }

    var runtimeSurfaceUpdatedAtDate: Date? {
        guard runtimeSurfaceUpdatedAtMs > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(runtimeSurfaceUpdatedAtMs) / 1000.0)
    }

    func effectiveRuntimeSurfacePolicy(
        now: Date = Date(),
        remoteOverride: AXProjectRuntimeSurfaceRemoteOverrideSnapshot? = nil
    ) -> AXProjectRuntimeSurfaceEffectivePolicy {
        let ttlSeconds = max(60, runtimeSurfaceTTLSeconds)
        let nowMs = Int64((now.timeIntervalSince1970 * 1000.0).rounded())
        let remoteOverrideMode = remoteOverride?.overrideMode ?? .none
        let resolvedOverrideMode = xtResolvedRuntimeSurfaceOverrideMode(
            local: runtimeSurfaceHubOverrideMode,
            remote: remoteOverrideMode
        )
        let killSwitchEngaged = resolvedOverrideMode == .killSwitch

        let expired: Bool
        let remainingSeconds: Int
        if runtimeSurfaceMode == .manual {
            expired = false
            remainingSeconds = 0
        } else if runtimeSurfaceUpdatedAtMs <= 0 {
            expired = true
            remainingSeconds = 0
        } else {
            let expiresAtMs = runtimeSurfaceUpdatedAtMs + Int64(ttlSeconds) * 1000
            expired = nowMs >= expiresAtMs
            remainingSeconds = expired ? 0 : max(0, Int((expiresAtMs - nowMs + 999) / 1000))
        }

        var effectiveMode = runtimeSurfaceMode
        if killSwitchEngaged || expired {
            effectiveMode = .manual
        } else {
            switch resolvedOverrideMode {
            case .none:
                break
            case .clampGuided:
                if effectiveMode == .trustedOpenClawMode {
                    effectiveMode = .guided
                }
            case .clampManual:
                effectiveMode = .manual
            case .killSwitch:
                effectiveMode = .manual
            }
        }

        var allowDeviceTools = runtimeSurfaceAllowDeviceTools
        var allowBrowserRuntime = runtimeSurfaceAllowBrowserRuntime
        var allowConnectorActions = runtimeSurfaceAllowConnectorActions
        var allowExtensions = runtimeSurfaceAllowExtensions

        switch effectiveMode {
        case .manual:
            allowDeviceTools = false
            allowBrowserRuntime = false
            allowConnectorActions = false
            allowExtensions = false
        case .guided:
            allowDeviceTools = false
            allowConnectorActions = false
            allowExtensions = false
        case .trustedOpenClawMode:
            break
        }

        return AXProjectRuntimeSurfaceEffectivePolicy(
            configuredMode: runtimeSurfaceMode,
            effectiveMode: effectiveMode,
            hubOverrideMode: resolvedOverrideMode,
            localOverrideMode: runtimeSurfaceHubOverrideMode,
            remoteOverrideMode: remoteOverrideMode,
            remoteOverrideUpdatedAtMs: max(0, remoteOverride?.updatedAtMs ?? 0),
            remoteOverrideSource: remoteOverride?.source.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            allowDeviceTools: allowDeviceTools,
            allowBrowserRuntime: allowBrowserRuntime,
            allowConnectorActions: allowConnectorActions,
            allowExtensions: allowExtensions,
            ttlSeconds: ttlSeconds,
            remainingSeconds: remainingSeconds,
            expired: expired,
            killSwitchEngaged: killSwitchEngaged
        )
    }

    @available(*, deprecated, message: "Use configuredRuntimeSurfaceLabels")
    var configuredAutonomySurfaceLabels: [String] {
        configuredRuntimeSurfaceLabels
    }

    @available(*, deprecated, message: "Use settingRuntimeSurfacePolicy(mode:allowDeviceTools:allowBrowserRuntime:allowConnectorActions:allowExtensions:ttlSeconds:hubOverrideMode:updatedAt:)")
    func settingAutonomyPolicy(
        mode: AXProjectRuntimeSurfaceMode? = nil,
        allowDeviceTools: Bool? = nil,
        allowBrowserRuntime: Bool? = nil,
        allowConnectorActions: Bool? = nil,
        allowExtensions: Bool? = nil,
        ttlSeconds: Int? = nil,
        hubOverrideMode: AXProjectRuntimeSurfaceHubOverrideMode? = nil,
        updatedAt: Date = Date()
    ) -> AXProjectConfig {
        settingRuntimeSurfacePolicy(
            mode: mode,
            allowDeviceTools: allowDeviceTools,
            allowBrowserRuntime: allowBrowserRuntime,
            allowConnectorActions: allowConnectorActions,
            allowExtensions: allowExtensions,
            ttlSeconds: ttlSeconds,
            hubOverrideMode: hubOverrideMode,
            updatedAt: updatedAt
        )
    }

    @available(*, deprecated, message: "Use runtimeSurfaceUpdatedAtDate")
    var autonomyUpdatedAtDate: Date? {
        runtimeSurfaceUpdatedAtDate
    }

    @available(*, deprecated, message: "Use effectiveRuntimeSurfacePolicy(now:remoteOverride:)")
    func effectiveAutonomyPolicy(
        now: Date = Date(),
        remoteOverride: AXProjectRuntimeSurfaceRemoteOverrideSnapshot? = nil
    ) -> AXProjectRuntimeSurfaceEffectivePolicy {
        effectiveRuntimeSurfacePolicy(
            now: now,
            remoteOverride: remoteOverride
        )
    }
}

@available(*, deprecated, message: "Use AXProjectRuntimeSurfaceMode")
typealias AXProjectAutonomyMode = AXProjectRuntimeSurfaceMode

@available(*, deprecated, message: "Use AXProjectRuntimeSurfaceHubOverrideMode")
typealias AXProjectAutonomyHubOverrideMode = AXProjectRuntimeSurfaceHubOverrideMode

@available(*, deprecated, message: "Use AXProjectRuntimeSurfaceRemoteOverrideSnapshot")
typealias AXProjectAutonomyRemoteOverrideSnapshot = AXProjectRuntimeSurfaceRemoteOverrideSnapshot

@available(*, deprecated, message: "Use AXProjectRuntimeSurfaceEffectivePolicy")
typealias AXProjectAutonomyEffectivePolicy = AXProjectRuntimeSurfaceEffectivePolicy

@available(*, deprecated, message: "Use AXProjectResolvedRuntimeSurfacePolicyState")
typealias AXProjectResolvedAutonomyPolicyState = AXProjectResolvedRuntimeSurfacePolicyState

@available(*, deprecated, message: "Use xtResolveProjectRuntimeSurfacePolicy(projectRoot:config:)")
func xtResolveProjectAutonomyPolicy(
    projectRoot: URL,
    config: AXProjectConfig
) async -> AXProjectResolvedRuntimeSurfacePolicyState {
    await xtResolveProjectRuntimeSurfacePolicy(
        projectRoot: projectRoot,
        config: config
    )
}

@available(*, deprecated, message: "Use xtProjectGovernedDeviceAuthorityEnabled(projectRoot:config:effectiveRuntimeSurface:)")
func xtProjectGovernedDeviceAuthorityEnabled(
    projectRoot: URL,
    config: AXProjectConfig,
    effectiveAutonomy: AXProjectRuntimeSurfaceEffectivePolicy
) -> Bool {
    xtProjectGovernedDeviceAuthorityEnabled(
        projectRoot: projectRoot,
        config: config,
        effectiveRuntimeSurface: effectiveAutonomy
    )
}

@available(*, deprecated, message: "Use xtProjectGovernedAutoApprovalEnabled(projectRoot:config:effectiveRuntimeSurface:)")
func xtProjectGovernedAutoApprovalEnabled(
    projectRoot: URL,
    config: AXProjectConfig,
    effectiveAutonomy: AXProjectRuntimeSurfaceEffectivePolicy
) -> Bool {
    xtProjectGovernedAutoApprovalEnabled(
        projectRoot: projectRoot,
        config: config,
        effectiveRuntimeSurface: effectiveAutonomy
    )
}
