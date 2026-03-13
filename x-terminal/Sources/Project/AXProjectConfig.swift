import Foundation

struct AXProjectConfig: Codable, Equatable {
    static let currentSchemaVersion = 10

    var schemaVersion: Int

    // Per-role model overrides (role rawValue -> model id).
    var roleModelOverrides: [String: String]

    // Verification commands to run after changes (in order).
    // Examples:
    // - swift test
    // - npm test
    // - python -m pytest
    var verifyCommands: [String]

    // If true, X-Terminal will suggest/trigger verification automatically in the tool loop.
    // Actual execution still follows the tool confirmation policy.
    var verifyAfterChanges: Bool

    // If true, retryable blocked automation runs can launch bounded follow-up iterations automatically.
    var automationSelfIterateEnabled: Bool
    var automationMaxAutoRetryDepth: Int

    // If true, project prompt memory prefers Hub memory context and falls back to local layers when unavailable.
    // If false, prompt memory stays local-only on the X-Terminal side.
    var preferHubMemory: Bool

    // Tool policy: profile + additive allow/deny tokens.
    // profile: minimal|coding|full
    // allow/deny tokens support tool names, group:*, and all/*
    var toolProfile: String
    var toolAllow: [String]
    var toolDeny: [String]

    // Trusted automation binds device-level execution to this project only.
    var automationMode: AXProjectAutomationMode
    var trustedAutomationDeviceId: String
    var deviceToolGroups: [String]
    var workspaceBindingHash: String

    // Extra read-only roots that Supervisor/tools may inspect when governed device authority is enabled.
    // Project root is always implicitly included and does not need to be repeated here.
    var governedReadableRoots: [String]

    // If true, local needs-confirm tools may auto-run when governed device authority is active.
    // Dangerous always-confirm commands still remain manual.
    var governedAutoApproveLocalToolCalls: Bool

    // User-visible autonomy policy preset + hub clamp slot for OpenClaw-style execution.
    var autonomyMode: AXProjectAutonomyMode
    var autonomyAllowDeviceTools: Bool
    var autonomyAllowBrowserRuntime: Bool
    var autonomyAllowConnectorActions: Bool
    var autonomyAllowExtensions: Bool
    var autonomyTTLSeconds: Int
    var autonomyUpdatedAtMs: Int64
    var autonomyHubOverrideMode: AXProjectAutonomyHubOverrideMode

    // New project governance contract. Legacy autonomy fields remain as compatibility inputs only.
    var executionTier: AXProjectExecutionTier
    var supervisorInterventionTier: AXProjectSupervisorInterventionTier
    var reviewPolicyMode: AXProjectReviewPolicyMode
    var progressHeartbeatSeconds: Int
    var reviewPulseSeconds: Int
    var brainstormReviewSeconds: Int
    var eventDrivenReviewEnabled: Bool
    var eventReviewTriggers: [AXProjectReviewTrigger]
    var governanceCompatSource: AXProjectGovernanceCompatSource

    // Governed automation recipe assets stored at the project boundary.
    var automationRecipes: [AXAutomationRecipeRuntimeBinding]
    var activeAutomationRecipeRef: String
    var lastAutomationLaunchRef: String

    static func `default`(forProjectRoot root: URL) -> AXProjectConfig {
        // Heuristic: pick something sensible to reduce setup friction.
        let cmds = AXProjectStackDetector.recommendedVerifyCommands(forProjectRoot: root)

        return AXProjectConfig(
            schemaVersion: currentSchemaVersion,
            roleModelOverrides: [:],
            verifyCommands: cmds,
            verifyAfterChanges: true,
            automationSelfIterateEnabled: false,
            automationMaxAutoRetryDepth: 2,
            preferHubMemory: true,
            toolProfile: ToolPolicy.defaultProfile.rawValue,
            toolAllow: [],
            toolDeny: [],
            automationMode: .standard,
            trustedAutomationDeviceId: "",
            deviceToolGroups: [],
            workspaceBindingHash: "",
            governedReadableRoots: [],
            governedAutoApproveLocalToolCalls: false,
            autonomyMode: .manual,
            autonomyAllowDeviceTools: false,
            autonomyAllowBrowserRuntime: false,
            autonomyAllowConnectorActions: false,
            autonomyAllowExtensions: false,
            autonomyTTLSeconds: 3600,
            autonomyUpdatedAtMs: 0,
            autonomyHubOverrideMode: .none,
            executionTier: .a0Observe,
            supervisorInterventionTier: .s0SilentAudit,
            reviewPolicyMode: .milestoneOnly,
            progressHeartbeatSeconds: 1800,
            reviewPulseSeconds: 0,
            brainstormReviewSeconds: 0,
            eventDrivenReviewEnabled: false,
            eventReviewTriggers: [.manualRequest],
            governanceCompatSource: .defaultConservative,
            automationRecipes: [],
            activeAutomationRecipeRef: "",
            lastAutomationLaunchRef: ""
        )
    }

    func modelOverride(for role: AXRole) -> String? {
        let v = (roleModelOverrides[role.rawValue] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return v.isEmpty ? nil : v
    }

    mutating func setModelOverride(role: AXRole, modelId: String?) {
        let v = (modelId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if v.isEmpty {
            roleModelOverrides.removeValue(forKey: role.rawValue)
        } else {
            roleModelOverrides[role.rawValue] = v
        }
    }

    func settingModelOverride(role: AXRole, modelId: String?) -> AXProjectConfig {
        var out = self
        out.setModelOverride(role: role, modelId: modelId)
        return out
    }

    func modelOverrideCandidates(for roles: [AXRole]) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []

        for role in roles {
            guard let override = modelOverride(for: role) else { continue }
            guard seen.insert(override).inserted else { continue }
            ordered.append(override)
        }

        return ordered
    }

    func settingToolPolicy(profile: String? = nil, allow: [String]? = nil, deny: [String]? = nil) -> AXProjectConfig {
        var out = self
        if let profile {
            let parsed = ToolPolicy.parseProfile(profile)
            out.toolProfile = parsed.rawValue
        }
        if let allow {
            out.toolAllow = ToolPolicy.normalizePolicyTokens(allow)
        }
        if let deny {
            out.toolDeny = ToolPolicy.normalizePolicyTokens(deny)
        }
        return out.normalizedAutomationState()
    }

    func settingHubMemoryPreference(enabled: Bool) -> AXProjectConfig {
        var out = self
        out.preferHubMemory = enabled
        return out.normalizedAutomationState()
    }

    func settingAutomationSelfIteration(
        enabled: Bool? = nil,
        maxAutoRetryDepth: Int? = nil
    ) -> AXProjectConfig {
        var out = self
        if let enabled {
            out.automationSelfIterateEnabled = enabled
        }
        if let maxAutoRetryDepth {
            out.automationMaxAutoRetryDepth = max(1, maxAutoRetryDepth)
        }
        return out.normalizedAutomationState()
    }

    func settingTrustedAutomationBinding(
        mode: AXProjectAutomationMode,
        deviceId: String,
        deviceToolGroups: [String]? = nil,
        workspaceBindingHash: String? = nil
    ) -> AXProjectConfig {
        var out = self
        out.automationMode = mode
        out.trustedAutomationDeviceId = deviceId.trimmingCharacters(in: .whitespacesAndNewlines)
        if let deviceToolGroups {
            out.deviceToolGroups = deviceToolGroups
        }
        if let workspaceBindingHash {
            out.workspaceBindingHash = workspaceBindingHash
        }

        var allow = out.toolAllow
        if mode == .trustedAutomation {
            allow.append("group:device_automation")
            if out.deviceToolGroups.isEmpty {
                out.deviceToolGroups = xtTrustedAutomationDefaultDeviceToolGroups()
            }
        } else {
            allow.removeAll { $0 == "group:device_automation" }
        }
        out.toolAllow = ToolPolicy.normalizePolicyTokens(allow)
        return out.normalizedAutomationState()
    }

    func settingGovernedReadableRoots(
        paths: [String],
        projectRoot: URL
    ) -> AXProjectConfig {
        var out = self
        out.governedReadableRoots = AXProjectConfig.normalizedGovernedReadableRoots(
            paths,
            projectRoot: projectRoot
        )
        return out.normalizedAutomationState()
    }

    func settingGovernedAutoApproveLocalToolCalls(enabled: Bool) -> AXProjectConfig {
        var out = self
        out.governedAutoApproveLocalToolCalls = enabled
        return out.normalizedAutomationState()
    }

    var governanceBundle: AXProjectGovernanceBundle {
        AXProjectGovernanceBundle(
            executionTier: executionTier,
            supervisorInterventionTier: supervisorInterventionTier,
            reviewPolicyMode: reviewPolicyMode,
            schedule: AXProjectGovernanceSchedule(
                progressHeartbeatSeconds: progressHeartbeatSeconds,
                reviewPulseSeconds: reviewPulseSeconds,
                brainstormReviewSeconds: brainstormReviewSeconds,
                eventDrivenReviewEnabled: eventDrivenReviewEnabled,
                eventReviewTriggers: eventReviewTriggers
            )
        ).normalized()
    }

    func settingProjectGovernance(
        executionTier: AXProjectExecutionTier? = nil,
        supervisorInterventionTier: AXProjectSupervisorInterventionTier? = nil,
        reviewPolicyMode: AXProjectReviewPolicyMode? = nil,
        progressHeartbeatSeconds: Int? = nil,
        reviewPulseSeconds: Int? = nil,
        brainstormReviewSeconds: Int? = nil,
        eventDrivenReviewEnabled: Bool? = nil,
        eventReviewTriggers: [AXProjectReviewTrigger]? = nil,
        governanceCompatSource: AXProjectGovernanceCompatSource = .explicitDualDial
    ) -> AXProjectConfig {
        var out = self

        if let executionTier {
            let recommended = AXProjectGovernanceBundle.recommended(
                for: executionTier,
                supervisorInterventionTier: supervisorInterventionTier ?? out.supervisorInterventionTier
            )
            out.executionTier = executionTier
            if supervisorInterventionTier == nil {
                out.supervisorInterventionTier = recommended.supervisorInterventionTier
            }
            if reviewPolicyMode == nil {
                out.reviewPolicyMode = recommended.reviewPolicyMode
            }
            if progressHeartbeatSeconds == nil {
                out.progressHeartbeatSeconds = recommended.schedule.progressHeartbeatSeconds
            }
            if reviewPulseSeconds == nil {
                out.reviewPulseSeconds = recommended.schedule.reviewPulseSeconds
            }
            if brainstormReviewSeconds == nil {
                out.brainstormReviewSeconds = recommended.schedule.brainstormReviewSeconds
            }
            if eventDrivenReviewEnabled == nil {
                out.eventDrivenReviewEnabled = recommended.schedule.eventDrivenReviewEnabled
            }
            if eventReviewTriggers == nil {
                out.eventReviewTriggers = recommended.schedule.eventReviewTriggers
            }
        }

        if let supervisorInterventionTier {
            out.supervisorInterventionTier = supervisorInterventionTier
        }
        if let reviewPolicyMode {
            out.reviewPolicyMode = reviewPolicyMode
        }
        if let progressHeartbeatSeconds {
            out.progressHeartbeatSeconds = progressHeartbeatSeconds
        }
        if let reviewPulseSeconds {
            out.reviewPulseSeconds = reviewPulseSeconds
        }
        if let brainstormReviewSeconds {
            out.brainstormReviewSeconds = brainstormReviewSeconds
        }
        if let eventDrivenReviewEnabled {
            out.eventDrivenReviewEnabled = eventDrivenReviewEnabled
        }
        if let eventReviewTriggers {
            out.eventReviewTriggers = eventReviewTriggers
        }

        out.governanceCompatSource = governanceCompatSource
        return out.normalizedAutomationState()
    }

    static func normalizedGovernedReadableRoots(
        _ paths: [String],
        projectRoot: URL
    ) -> [String] {
        let resolvedProjectRoot = PathGuard.resolve(projectRoot).path
        var seen = Set<String>()
        var ordered: [String] = []

        for raw in paths {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let url: URL
            if trimmed.hasPrefix("/") {
                url = URL(fileURLWithPath: trimmed)
            } else {
                url = projectRoot.appendingPathComponent(trimmed)
            }

            let normalized = PathGuard.resolve(url).path
            guard normalized != resolvedProjectRoot else { continue }
            guard seen.insert(normalized).inserted else { continue }
            ordered.append(normalized)
        }

        return ordered
    }

    func trustedAutomationStatus(
        forProjectRoot root: URL,
        permissionReadiness: AXTrustedAutomationPermissionOwnerReadiness = .current(),
        requiredDeviceToolGroups: [String] = []
    ) -> AXTrustedAutomationProjectStatus {
        let expectedWorkspaceBindingHash = xtTrustedAutomationWorkspaceHash(forProjectRoot: root)
        let cleanDeviceId = trustedAutomationDeviceId.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanWorkspaceBindingHash = workspaceBindingHash.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasSurfaceToken = toolAllow.contains("group:device_automation")
        let armedDeviceGroups = xtNormalizedTrustedAutomationDeviceToolGroups(deviceToolGroups)
        let cleanRequiredDeviceGroups = xtNormalizedTrustedAutomationDeviceToolGroups(requiredDeviceToolGroups)
        let effectiveDeviceGroups = cleanRequiredDeviceGroups.isEmpty ? armedDeviceGroups : cleanRequiredDeviceGroups
        let missingRequiredDeviceGroups = cleanRequiredDeviceGroups.filter { !armedDeviceGroups.contains($0) }
        var issues: [String] = []

        if automationMode != .trustedAutomation {
            issues.append("trusted_automation_mode_off")
        }
        if cleanDeviceId.isEmpty {
            issues.append("trusted_automation_project_not_bound")
        }
        if cleanWorkspaceBindingHash.isEmpty || cleanWorkspaceBindingHash != expectedWorkspaceBindingHash {
            issues.append("trusted_automation_workspace_mismatch")
        }
        if armedDeviceGroups.isEmpty {
            issues.append("trusted_automation_device_tool_groups_missing")
        }
        issues.append(contentsOf: missingRequiredDeviceGroups.map { "trusted_automation_required_device_tool_group_missing:\($0)" })
        if !hasSurfaceToken {
            issues.append("trusted_automation_surface_not_enabled")
        }
        issues.append(contentsOf: permissionReadiness.missingRequirements(forDeviceToolGroups: effectiveDeviceGroups))

        let bindingReady = automationMode == .trustedAutomation
            && !cleanDeviceId.isEmpty
            && !cleanWorkspaceBindingHash.isEmpty
            && cleanWorkspaceBindingHash == expectedWorkspaceBindingHash
            && !armedDeviceGroups.isEmpty
            && missingRequiredDeviceGroups.isEmpty
            && hasSurfaceToken
        let permissionOwnerReady = permissionReadiness.isReady(forDeviceToolGroups: effectiveDeviceGroups)

        let state: AXTrustedAutomationProjectState
        if automationMode != .trustedAutomation {
            state = .off
        } else if !bindingReady {
            state = .blocked
        } else if permissionOwnerReady {
            state = .active
        } else {
            state = .armed
        }

        return AXTrustedAutomationProjectStatus(
            mode: automationMode,
            state: state,
            trustedAutomationReady: bindingReady,
            permissionOwnerReady: permissionOwnerReady,
            boundDeviceID: cleanDeviceId,
            workspaceBindingHash: cleanWorkspaceBindingHash,
            expectedWorkspaceBindingHash: expectedWorkspaceBindingHash,
            deviceToolGroups: effectiveDeviceGroups,
            armedDeviceToolGroups: armedDeviceGroups,
            requiredDeviceToolGroups: cleanRequiredDeviceGroups,
            missingRequiredDeviceToolGroups: missingRequiredDeviceGroups,
            missingPrerequisites: Array(Set(issues)).sorted()
        )
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case roleModelOverrides
        case verifyCommands
        case verifyAfterChanges
        case automationSelfIterateEnabled
        case automationMaxAutoRetryDepth
        case preferHubMemory
        case toolProfile
        case toolAllow
        case toolDeny
        case automationMode
        case trustedAutomationDeviceId
        case deviceToolGroups
        case workspaceBindingHash
        case governedReadableRoots
        case governedAutoApproveLocalToolCalls
        case autonomyMode
        case autonomyAllowDeviceTools
        case autonomyAllowBrowserRuntime
        case autonomyAllowConnectorActions
        case autonomyAllowExtensions
        case autonomyTTLSeconds
        case autonomyUpdatedAtMs
        case autonomyHubOverrideMode
        case executionTier
        case supervisorInterventionTier
        case reviewPolicyMode
        case progressHeartbeatSeconds
        case reviewPulseSeconds
        case brainstormReviewSeconds
        case eventDrivenReviewEnabled
        case eventReviewTriggers
        case governanceCompatSource
        case automationRecipes
        case activeAutomationRecipeRef
        case lastAutomationLaunchRef
    }

    init(
        schemaVersion: Int,
        roleModelOverrides: [String: String],
        verifyCommands: [String],
        verifyAfterChanges: Bool,
        automationSelfIterateEnabled: Bool,
        automationMaxAutoRetryDepth: Int,
        preferHubMemory: Bool,
        toolProfile: String,
        toolAllow: [String],
        toolDeny: [String],
        automationMode: AXProjectAutomationMode,
        trustedAutomationDeviceId: String,
        deviceToolGroups: [String],
        workspaceBindingHash: String,
        governedReadableRoots: [String],
        governedAutoApproveLocalToolCalls: Bool,
        autonomyMode: AXProjectAutonomyMode,
        autonomyAllowDeviceTools: Bool,
        autonomyAllowBrowserRuntime: Bool,
        autonomyAllowConnectorActions: Bool,
        autonomyAllowExtensions: Bool,
        autonomyTTLSeconds: Int,
        autonomyUpdatedAtMs: Int64,
        autonomyHubOverrideMode: AXProjectAutonomyHubOverrideMode,
        executionTier: AXProjectExecutionTier,
        supervisorInterventionTier: AXProjectSupervisorInterventionTier,
        reviewPolicyMode: AXProjectReviewPolicyMode,
        progressHeartbeatSeconds: Int,
        reviewPulseSeconds: Int,
        brainstormReviewSeconds: Int,
        eventDrivenReviewEnabled: Bool,
        eventReviewTriggers: [AXProjectReviewTrigger],
        governanceCompatSource: AXProjectGovernanceCompatSource,
        automationRecipes: [AXAutomationRecipeRuntimeBinding],
        activeAutomationRecipeRef: String,
        lastAutomationLaunchRef: String
    ) {
        self.schemaVersion = schemaVersion
        self.roleModelOverrides = roleModelOverrides
        self.verifyCommands = verifyCommands
        self.verifyAfterChanges = verifyAfterChanges
        self.automationSelfIterateEnabled = automationSelfIterateEnabled
        self.automationMaxAutoRetryDepth = max(1, automationMaxAutoRetryDepth)
        self.preferHubMemory = preferHubMemory
        self.toolProfile = ToolPolicy.parseProfile(toolProfile).rawValue
        self.toolAllow = ToolPolicy.normalizePolicyTokens(toolAllow)
        self.toolDeny = ToolPolicy.normalizePolicyTokens(toolDeny)
        self.automationMode = automationMode
        self.trustedAutomationDeviceId = trustedAutomationDeviceId
        self.deviceToolGroups = deviceToolGroups
        self.workspaceBindingHash = workspaceBindingHash
        self.governedReadableRoots = governedReadableRoots
        self.governedAutoApproveLocalToolCalls = governedAutoApproveLocalToolCalls
        self.autonomyMode = autonomyMode
        self.autonomyAllowDeviceTools = autonomyAllowDeviceTools
        self.autonomyAllowBrowserRuntime = autonomyAllowBrowserRuntime
        self.autonomyAllowConnectorActions = autonomyAllowConnectorActions
        self.autonomyAllowExtensions = autonomyAllowExtensions
        self.autonomyTTLSeconds = autonomyTTLSeconds
        self.autonomyUpdatedAtMs = autonomyUpdatedAtMs
        self.autonomyHubOverrideMode = autonomyHubOverrideMode
        self.executionTier = executionTier
        self.supervisorInterventionTier = supervisorInterventionTier
        self.reviewPolicyMode = reviewPolicyMode
        self.progressHeartbeatSeconds = progressHeartbeatSeconds
        self.reviewPulseSeconds = reviewPulseSeconds
        self.brainstormReviewSeconds = brainstormReviewSeconds
        self.eventDrivenReviewEnabled = eventDrivenReviewEnabled
        self.eventReviewTriggers = eventReviewTriggers
        self.governanceCompatSource = governanceCompatSource
        self.automationRecipes = automationRecipes
        self.activeAutomationRecipeRef = activeAutomationRecipeRef
        self.lastAutomationLaunchRef = lastAutomationLaunchRef
        self = self.normalizedAutomationState()
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let storedSchemaVersion = (try? c.decode(Int.self, forKey: .schemaVersion)) ?? AXProjectConfig.currentSchemaVersion
        schemaVersion = AXProjectConfig.currentSchemaVersion
        roleModelOverrides = (try? c.decode([String: String].self, forKey: .roleModelOverrides)) ?? [:]
        verifyCommands = (try? c.decode([String].self, forKey: .verifyCommands)) ?? []
        verifyAfterChanges = (try? c.decode(Bool.self, forKey: .verifyAfterChanges)) ?? true
        automationSelfIterateEnabled = (try? c.decode(Bool.self, forKey: .automationSelfIterateEnabled)) ?? false
        automationMaxAutoRetryDepth = max(1, (try? c.decode(Int.self, forKey: .automationMaxAutoRetryDepth)) ?? 2)
        preferHubMemory = (try? c.decode(Bool.self, forKey: .preferHubMemory)) ?? true
        let rawProfile = (try? c.decode(String.self, forKey: .toolProfile)) ?? ToolPolicy.defaultProfile.rawValue
        toolProfile = ToolPolicy.parseProfile(rawProfile).rawValue
        toolAllow = ToolPolicy.normalizePolicyTokens((try? c.decode([String].self, forKey: .toolAllow)) ?? [])
        toolDeny = ToolPolicy.normalizePolicyTokens((try? c.decode([String].self, forKey: .toolDeny)) ?? [])
        automationMode = (try? c.decode(AXProjectAutomationMode.self, forKey: .automationMode)) ?? .standard
        trustedAutomationDeviceId = (try? c.decode(String.self, forKey: .trustedAutomationDeviceId)) ?? ""
        deviceToolGroups = (try? c.decode([String].self, forKey: .deviceToolGroups)) ?? []
        workspaceBindingHash = (try? c.decode(String.self, forKey: .workspaceBindingHash)) ?? ""
        governedReadableRoots = (try? c.decode([String].self, forKey: .governedReadableRoots)) ?? []
        governedAutoApproveLocalToolCalls = (try? c.decode(Bool.self, forKey: .governedAutoApproveLocalToolCalls)) ?? false
        autonomyMode = (try? c.decode(AXProjectAutonomyMode.self, forKey: .autonomyMode)) ?? .manual
        autonomyAllowDeviceTools = (try? c.decode(Bool.self, forKey: .autonomyAllowDeviceTools)) ?? false
        autonomyAllowBrowserRuntime = (try? c.decode(Bool.self, forKey: .autonomyAllowBrowserRuntime)) ?? false
        autonomyAllowConnectorActions = (try? c.decode(Bool.self, forKey: .autonomyAllowConnectorActions)) ?? false
        autonomyAllowExtensions = (try? c.decode(Bool.self, forKey: .autonomyAllowExtensions)) ?? false
        autonomyTTLSeconds = max(60, (try? c.decode(Int.self, forKey: .autonomyTTLSeconds)) ?? 3600)
        autonomyUpdatedAtMs = max(0, (try? c.decode(Int64.self, forKey: .autonomyUpdatedAtMs)) ?? 0)
        autonomyHubOverrideMode = (try? c.decode(AXProjectAutonomyHubOverrideMode.self, forKey: .autonomyHubOverrideMode)) ?? .none

        let hasExplicitGovernance =
            c.contains(.executionTier)
            || c.contains(.supervisorInterventionTier)
            || c.contains(.reviewPolicyMode)
            || c.contains(.progressHeartbeatSeconds)
            || c.contains(.reviewPulseSeconds)
            || c.contains(.brainstormReviewSeconds)
            || c.contains(.eventDrivenReviewEnabled)
            || c.contains(.eventReviewTriggers)
        let legacyBundle = AXProjectGovernanceBundle.recommended(
            for: AXProjectExecutionTier.fromLegacyAutonomyMode(autonomyMode)
        )
        executionTier = (try? c.decode(AXProjectExecutionTier.self, forKey: .executionTier))
            ?? legacyBundle.executionTier
        supervisorInterventionTier = (try? c.decode(
            AXProjectSupervisorInterventionTier.self,
            forKey: .supervisorInterventionTier
        )) ?? legacyBundle.supervisorInterventionTier
        reviewPolicyMode = (try? c.decode(AXProjectReviewPolicyMode.self, forKey: .reviewPolicyMode))
            ?? legacyBundle.reviewPolicyMode
        progressHeartbeatSeconds = max(
            60,
            (try? c.decode(Int.self, forKey: .progressHeartbeatSeconds))
                ?? legacyBundle.schedule.progressHeartbeatSeconds
        )
        reviewPulseSeconds = max(
            0,
            (try? c.decode(Int.self, forKey: .reviewPulseSeconds))
                ?? legacyBundle.schedule.reviewPulseSeconds
        )
        brainstormReviewSeconds = max(
            0,
            (try? c.decode(Int.self, forKey: .brainstormReviewSeconds))
                ?? legacyBundle.schedule.brainstormReviewSeconds
        )
        eventDrivenReviewEnabled = (try? c.decode(Bool.self, forKey: .eventDrivenReviewEnabled))
            ?? legacyBundle.schedule.eventDrivenReviewEnabled
        eventReviewTriggers = (try? c.decode([AXProjectReviewTrigger].self, forKey: .eventReviewTriggers))
            ?? legacyBundle.schedule.eventReviewTriggers
        if hasExplicitGovernance {
            governanceCompatSource = (try? c.decode(
                AXProjectGovernanceCompatSource.self,
                forKey: .governanceCompatSource
            )) ?? .explicitDualDial
        } else if storedSchemaVersion < 10 {
            governanceCompatSource = .legacyAutonomyMode
        } else {
            governanceCompatSource = .defaultConservative
        }

        automationRecipes = (try? c.decode([AXAutomationRecipeRuntimeBinding].self, forKey: .automationRecipes)) ?? []
        activeAutomationRecipeRef = (try? c.decode(String.self, forKey: .activeAutomationRecipeRef)) ?? ""
        lastAutomationLaunchRef = (try? c.decode(String.self, forKey: .lastAutomationLaunchRef)) ?? ""
        self = self.normalizedAutomationState()
    }
}
