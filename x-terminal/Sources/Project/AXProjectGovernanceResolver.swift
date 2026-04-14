import Foundation

enum AXProjectGovernanceResolver {
    static func resolve(
        projectRoot: URL,
        config: AXProjectConfig,
        legacyAutonomyLevel: AutonomyLevel? = nil,
        remoteOverride: AXProjectRuntimeSurfaceRemoteOverrideSnapshot? = nil,
        projectAIStrengthProfile: AXProjectAIStrengthProfile? = nil,
        adaptationPolicy: AXProjectSupervisorAdaptationPolicy = .default,
        permissionReadiness: AXTrustedAutomationPermissionOwnerReadiness = .current()
    ) -> AXProjectResolvedGovernanceState {
        let projectId = AXProjectRegistryStore.projectId(forRoot: projectRoot)
        let compatSource = resolvedCompatSource(config: config, legacyAutonomyLevel: legacyAutonomyLevel)
        let configuredBundle = configuredBundle(config: config, compatSource: compatSource, legacyAutonomyLevel: legacyAutonomyLevel)
        let effectiveRuntimeSurface = config.effectiveRuntimeSurfacePolicy(remoteOverride: remoteOverride)
        let trustedAutomationStatus = config.trustedAutomationStatus(
            forProjectRoot: projectRoot,
            permissionReadiness: permissionReadiness
        )
        let validation = validate(bundle: configuredBundle)

        var effectiveBundle = configuredBundle
        var capabilityBundle = configuredBundle.executionTier.baseCapabilityBundle
        var supervisorAdaptation = resolvedSupervisorAdaptation(
            configuredBundle: configuredBundle,
            validation: validation,
            projectAIStrengthProfile: projectAIStrengthProfile,
            adaptationPolicy: adaptationPolicy
        )

        effectiveBundle.supervisorInterventionTier = supervisorAdaptation.effectiveSupervisorTier

        if validation.shouldFailClosed {
            effectiveBundle = .conservativeFallback
            capabilityBundle = .observeOnly
            supervisorAdaptation.effectiveSupervisorTier = effectiveBundle.supervisorInterventionTier
            supervisorAdaptation.effectiveWorkOrderDepth = effectiveBundle.supervisorInterventionTier.defaultWorkOrderDepth
            supervisorAdaptation.escalationReasons = ["validation_fail_closed"]
        }

        return AXProjectResolvedGovernanceState(
            projectId: projectId,
            configuredBundle: configuredBundle,
            effectiveBundle: effectiveBundle.normalized(),
            supervisorAdaptation: supervisorAdaptation,
            compatSource: compatSource,
            projectMemoryCeiling: effectiveBundle.executionTier.defaultProjectMemoryCeiling,
            supervisorReviewMemoryCeiling: effectiveBundle.supervisorInterventionTier.defaultReviewMemoryCeiling,
            capabilityBundle: capabilityBundle,
            executionBudget: effectiveBundle.executionTier.defaultExecutionBudget,
            validation: validation,
            effectiveRuntimeSurface: effectiveRuntimeSurface,
            trustedAutomationStatus: trustedAutomationStatus
        )
    }

    static func resolve(
        projectRoot: URL,
        config: AXProjectConfig,
        legacyAutonomyLevel: AutonomyLevel? = nil,
        effectiveRuntimeSurface: AXProjectRuntimeSurfaceEffectivePolicy,
        projectAIStrengthProfile: AXProjectAIStrengthProfile? = nil,
        adaptationPolicy: AXProjectSupervisorAdaptationPolicy = .default,
        permissionReadiness: AXTrustedAutomationPermissionOwnerReadiness = .current()
    ) -> AXProjectResolvedGovernanceState {
        let projectId = AXProjectRegistryStore.projectId(forRoot: projectRoot)
        let compatSource = resolvedCompatSource(config: config, legacyAutonomyLevel: legacyAutonomyLevel)
        let configuredBundle = configuredBundle(config: config, compatSource: compatSource, legacyAutonomyLevel: legacyAutonomyLevel)
        let trustedAutomationStatus = config.trustedAutomationStatus(
            forProjectRoot: projectRoot,
            permissionReadiness: permissionReadiness
        )
        let validation = validate(bundle: configuredBundle)

        var effectiveBundle = configuredBundle
        var capabilityBundle = configuredBundle.executionTier.baseCapabilityBundle
        var supervisorAdaptation = resolvedSupervisorAdaptation(
            configuredBundle: configuredBundle,
            validation: validation,
            projectAIStrengthProfile: projectAIStrengthProfile,
            adaptationPolicy: adaptationPolicy
        )

        effectiveBundle.supervisorInterventionTier = supervisorAdaptation.effectiveSupervisorTier

        if validation.shouldFailClosed {
            effectiveBundle = .conservativeFallback
            capabilityBundle = .observeOnly
            supervisorAdaptation.effectiveSupervisorTier = effectiveBundle.supervisorInterventionTier
            supervisorAdaptation.effectiveWorkOrderDepth = effectiveBundle.supervisorInterventionTier.defaultWorkOrderDepth
            supervisorAdaptation.escalationReasons = ["validation_fail_closed"]
        }

        return AXProjectResolvedGovernanceState(
            projectId: projectId,
            configuredBundle: configuredBundle,
            effectiveBundle: effectiveBundle.normalized(),
            supervisorAdaptation: supervisorAdaptation,
            compatSource: compatSource,
            projectMemoryCeiling: effectiveBundle.executionTier.defaultProjectMemoryCeiling,
            supervisorReviewMemoryCeiling: effectiveBundle.supervisorInterventionTier.defaultReviewMemoryCeiling,
            capabilityBundle: capabilityBundle,
            executionBudget: effectiveBundle.executionTier.defaultExecutionBudget,
            validation: validation,
            effectiveRuntimeSurface: effectiveRuntimeSurface,
            trustedAutomationStatus: trustedAutomationStatus
        )
    }

    @available(*, deprecated, message: "Use resolve(projectRoot:config:legacyAutonomyLevel:effectiveRuntimeSurface:projectAIStrengthProfile:adaptationPolicy:permissionReadiness:)")
    static func resolve(
        projectRoot: URL,
        config: AXProjectConfig,
        legacyAutonomyLevel: AutonomyLevel? = nil,
        effectiveAutonomy: AXProjectAutonomyEffectivePolicy,
        projectAIStrengthProfile: AXProjectAIStrengthProfile? = nil,
        adaptationPolicy: AXProjectSupervisorAdaptationPolicy = .default,
        permissionReadiness: AXTrustedAutomationPermissionOwnerReadiness = .current()
    ) -> AXProjectResolvedGovernanceState {
        resolve(
            projectRoot: projectRoot,
            config: config,
            legacyAutonomyLevel: legacyAutonomyLevel,
            effectiveRuntimeSurface: effectiveAutonomy,
            projectAIStrengthProfile: projectAIStrengthProfile,
            adaptationPolicy: adaptationPolicy,
            permissionReadiness: permissionReadiness
        )
    }

    private static func resolvedCompatSource(
        config: AXProjectConfig,
        legacyAutonomyLevel: AutonomyLevel?
    ) -> AXProjectGovernanceCompatSource {
        switch config.governanceCompatSource {
        case .explicitDualDial:
            return .explicitDualDial
        case .legacyAutonomyMode:
            return legacyAutonomyLevel == nil ? .legacyAutonomyMode : .legacyAutonomyLevel
        case .legacyAutonomyLevel:
            return .legacyAutonomyLevel
        case .defaultConservative:
            return legacyAutonomyLevel == nil ? .defaultConservative : .legacyAutonomyLevel
        }
    }

    private static func configuredBundle(
        config: AXProjectConfig,
        compatSource: AXProjectGovernanceCompatSource,
        legacyAutonomyLevel: AutonomyLevel?
    ) -> AXProjectGovernanceBundle {
        switch compatSource {
        case .explicitDualDial, .defaultConservative:
            return config.governanceBundle.normalized()
        case .legacyAutonomyLevel:
            let level = legacyAutonomyLevel ?? .manual
            return AXProjectGovernanceBundle.recommended(
                for: AXProjectExecutionTier.fromLegacyAutonomyLevel(level)
            )
        case .legacyAutonomyMode:
            return AXProjectGovernanceBundle.recommended(
                for: AXProjectExecutionTier.fromRuntimeSurfaceMode(config.runtimeSurfaceMode)
            )
        }
    }

    private static func validate(bundle: AXProjectGovernanceBundle) -> AXProjectGovernanceValidation {
        let executionTier = bundle.executionTier
        let supervisorTier = bundle.supervisorInterventionTier

        let invalidReasons: [String] = []
        var warningReasons: [String] = []

        if supervisorTier < executionTier.minimumSafeSupervisorTier {
            warningReasons.append(
                "execution_\(executionTier.rawValue)_is_below_review_reference_\(executionTier.minimumSafeSupervisorTier.rawValue)"
            )
        }

        let recommended = executionTier.defaultSupervisorInterventionTier
        if supervisorTier < recommended && supervisorTier >= executionTier.minimumSafeSupervisorTier {
            warningReasons.append(
                "execution_\(executionTier.rawValue)_is_below_recommended_supervision_\(recommended.rawValue)"
            )
        }

        return AXProjectGovernanceValidation(
            minimumSafeSupervisorTier: executionTier.minimumSafeSupervisorTier,
            recommendedSupervisorTier: recommended,
            invalidReasons: invalidReasons,
            warningReasons: warningReasons
        )
    }

    private static func resolvedSupervisorAdaptation(
        configuredBundle: AXProjectGovernanceBundle,
        validation: AXProjectGovernanceValidation,
        projectAIStrengthProfile: AXProjectAIStrengthProfile?,
        adaptationPolicy: AXProjectSupervisorAdaptationPolicy
    ) -> AXProjectSupervisorAdaptationSnapshot {
        let configuredTier = configuredBundle.supervisorInterventionTier
        let baselineRecommendedTier = validation.recommendedSupervisorTier
        var recommendedTier = baselineRecommendedTier
        var effectiveTier = configuredTier
        var escalationReasons: [String] = []

        if let projectAIStrengthProfile {
            recommendedTier = max(recommendedTier, projectAIStrengthProfile.recommendedSupervisorFloor)

            if projectAIStrengthProfile.recommendedSupervisorFloor > configuredTier {
                escalationReasons.append(
                    "project_ai_strength_\(projectAIStrengthProfile.strengthBand.rawValue)_requires_supervisor_at_least_\(projectAIStrengthProfile.recommendedSupervisorFloor.rawValue)"
                )
            }
        }

        switch adaptationPolicy.adaptationMode {
        case .manualOnly:
            effectiveTier = configuredTier
        case .raiseOnly, .bidirectional:
            // A-Tier recommendations remain advisory by default.
            // Only explicit AI-strength evidence should auto-raise the effective S-Tier.
            effectiveTier = configuredTier
            if let projectAIStrengthProfile {
                effectiveTier = max(configuredTier, projectAIStrengthProfile.recommendedSupervisorFloor)
            }
        }

        let recommendedWorkOrderDepth = resolvedWorkOrderDepth(
            supervisorTier: recommendedTier,
            projectAIStrengthProfile: projectAIStrengthProfile
        )
        let effectiveWorkOrderDepth = adaptationPolicy.adaptationMode == .manualOnly
            ? configuredTier.defaultWorkOrderDepth
            : resolvedWorkOrderDepth(
                supervisorTier: effectiveTier,
                projectAIStrengthProfile: projectAIStrengthProfile
            )

        return AXProjectSupervisorAdaptationSnapshot(
            configuredSupervisorTier: configuredTier,
            baselineRecommendedSupervisorTier: baselineRecommendedTier,
            recommendedSupervisorTier: recommendedTier,
            effectiveSupervisorTier: effectiveTier,
            recommendedWorkOrderDepth: recommendedWorkOrderDepth,
            effectiveWorkOrderDepth: effectiveWorkOrderDepth,
            adaptationPolicy: adaptationPolicy,
            projectAIStrengthProfile: projectAIStrengthProfile,
            escalationReasons: escalationReasons
        )
    }

    private static func resolvedWorkOrderDepth(
        supervisorTier: AXProjectSupervisorInterventionTier,
        projectAIStrengthProfile: AXProjectAIStrengthProfile?
    ) -> AXProjectSupervisorWorkOrderDepth {
        max(
            supervisorTier.defaultWorkOrderDepth,
            projectAIStrengthProfile?.recommendedWorkOrderDepth ?? .none
        )
    }
}

func xtResolveProjectGovernance(
    projectRoot: URL,
    config: AXProjectConfig,
    legacyAutonomyLevel: AutonomyLevel? = nil,
    remoteOverride: AXProjectRuntimeSurfaceRemoteOverrideSnapshot? = nil,
    projectAIStrengthProfile: AXProjectAIStrengthProfile? = nil,
    adaptationPolicy: AXProjectSupervisorAdaptationPolicy = .default,
    permissionReadiness: AXTrustedAutomationPermissionOwnerReadiness = .current()
) -> AXProjectResolvedGovernanceState {
    AXProjectGovernanceResolver.resolve(
        projectRoot: projectRoot,
        config: config,
        legacyAutonomyLevel: legacyAutonomyLevel,
        remoteOverride: remoteOverride,
        projectAIStrengthProfile: projectAIStrengthProfile,
        adaptationPolicy: adaptationPolicy,
        permissionReadiness: permissionReadiness
    )
}

func xtResolveProjectGovernance(
    projectRoot: URL,
    config: AXProjectConfig,
    legacyAutonomyLevel: AutonomyLevel? = nil,
    effectiveRuntimeSurface: AXProjectRuntimeSurfaceEffectivePolicy,
    projectAIStrengthProfile: AXProjectAIStrengthProfile? = nil,
    adaptationPolicy: AXProjectSupervisorAdaptationPolicy = .default,
    permissionReadiness: AXTrustedAutomationPermissionOwnerReadiness = .current()
) -> AXProjectResolvedGovernanceState {
    AXProjectGovernanceResolver.resolve(
        projectRoot: projectRoot,
        config: config,
        legacyAutonomyLevel: legacyAutonomyLevel,
        effectiveRuntimeSurface: effectiveRuntimeSurface,
        projectAIStrengthProfile: projectAIStrengthProfile,
        adaptationPolicy: adaptationPolicy,
        permissionReadiness: permissionReadiness
    )
}

@available(*, deprecated, message: "Use xtResolveProjectGovernance(projectRoot:config:legacyAutonomyLevel:effectiveRuntimeSurface:projectAIStrengthProfile:adaptationPolicy:permissionReadiness:)")
func xtResolveProjectGovernance(
    projectRoot: URL,
    config: AXProjectConfig,
    legacyAutonomyLevel: AutonomyLevel? = nil,
    effectiveAutonomy: AXProjectAutonomyEffectivePolicy,
    projectAIStrengthProfile: AXProjectAIStrengthProfile? = nil,
    adaptationPolicy: AXProjectSupervisorAdaptationPolicy = .default,
    permissionReadiness: AXTrustedAutomationPermissionOwnerReadiness = .current()
) -> AXProjectResolvedGovernanceState {
    xtResolveProjectGovernance(
        projectRoot: projectRoot,
        config: config,
        legacyAutonomyLevel: legacyAutonomyLevel,
        effectiveRuntimeSurface: effectiveAutonomy,
        projectAIStrengthProfile: projectAIStrengthProfile,
        adaptationPolicy: adaptationPolicy,
        permissionReadiness: permissionReadiness
    )
}

func xtResolveProjectGovernance(
    projectRoot: URL,
    config: AXProjectConfig,
    legacyAutonomyLevel: AutonomyLevel? = nil
) async -> AXProjectResolvedGovernanceState {
    let projectId = AXProjectRegistryStore.projectId(forRoot: projectRoot)
    let remoteOverride = await HubIPCClient.requestProjectRuntimeSurfaceOverride(
        projectId: projectId,
        timeoutSec: 0.6
    )
    return AXProjectGovernanceResolver.resolve(
        projectRoot: projectRoot,
        config: config,
        legacyAutonomyLevel: legacyAutonomyLevel,
        remoteOverride: remoteOverride,
        permissionReadiness: .current()
    )
}
