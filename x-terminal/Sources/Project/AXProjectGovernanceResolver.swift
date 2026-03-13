import Foundation

enum AXProjectGovernanceResolver {
    static func resolve(
        projectRoot: URL,
        config: AXProjectConfig,
        legacyAutonomyLevel: AutonomyLevel? = nil,
        remoteOverride: AXProjectAutonomyRemoteOverrideSnapshot? = nil,
        permissionReadiness: AXTrustedAutomationPermissionOwnerReadiness = .current()
    ) -> AXProjectResolvedGovernanceState {
        let projectId = AXProjectRegistryStore.projectId(forRoot: projectRoot)
        let compatSource = resolvedCompatSource(config: config, legacyAutonomyLevel: legacyAutonomyLevel)
        let configuredBundle = configuredBundle(config: config, compatSource: compatSource, legacyAutonomyLevel: legacyAutonomyLevel)
        let effectiveAutonomy = config.effectiveAutonomyPolicy(remoteOverride: remoteOverride)
        let trustedAutomationStatus = config.trustedAutomationStatus(
            forProjectRoot: projectRoot,
            permissionReadiness: permissionReadiness
        )
        let validation = validate(bundle: configuredBundle)

        var effectiveBundle = configuredBundle
        var capabilityBundle = configuredBundle.executionTier.baseCapabilityBundle

        if validation.shouldFailClosed {
            effectiveBundle = .conservativeFallback
            capabilityBundle = .observeOnly
        }

        return AXProjectResolvedGovernanceState(
            projectId: projectId,
            configuredBundle: configuredBundle,
            effectiveBundle: effectiveBundle.normalized(),
            compatSource: compatSource,
            projectMemoryCeiling: effectiveBundle.executionTier.defaultProjectMemoryCeiling,
            supervisorReviewMemoryCeiling: effectiveBundle.supervisorInterventionTier.defaultReviewMemoryCeiling,
            capabilityBundle: capabilityBundle,
            executionBudget: effectiveBundle.executionTier.defaultExecutionBudget,
            validation: validation,
            effectiveAutonomy: effectiveAutonomy,
            trustedAutomationStatus: trustedAutomationStatus
        )
    }

    static func resolve(
        projectRoot: URL,
        config: AXProjectConfig,
        legacyAutonomyLevel: AutonomyLevel? = nil,
        effectiveAutonomy: AXProjectAutonomyEffectivePolicy,
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

        if validation.shouldFailClosed {
            effectiveBundle = .conservativeFallback
            capabilityBundle = .observeOnly
        }

        return AXProjectResolvedGovernanceState(
            projectId: projectId,
            configuredBundle: configuredBundle,
            effectiveBundle: effectiveBundle.normalized(),
            compatSource: compatSource,
            projectMemoryCeiling: effectiveBundle.executionTier.defaultProjectMemoryCeiling,
            supervisorReviewMemoryCeiling: effectiveBundle.supervisorInterventionTier.defaultReviewMemoryCeiling,
            capabilityBundle: capabilityBundle,
            executionBudget: effectiveBundle.executionTier.defaultExecutionBudget,
            validation: validation,
            effectiveAutonomy: effectiveAutonomy,
            trustedAutomationStatus: trustedAutomationStatus
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
                for: AXProjectExecutionTier.fromLegacyAutonomyMode(config.autonomyMode)
            )
        }
    }

    private static func validate(bundle: AXProjectGovernanceBundle) -> AXProjectGovernanceValidation {
        let executionTier = bundle.executionTier
        let supervisorTier = bundle.supervisorInterventionTier

        var invalidReasons: [String] = []
        var warningReasons: [String] = []

        if supervisorTier < executionTier.minimumSafeSupervisorTier {
            invalidReasons.append(
                "execution_\(executionTier.rawValue)_requires_supervisor_at_least_\(executionTier.minimumSafeSupervisorTier.rawValue)"
            )
        }

        let recommended = executionTier.defaultSupervisorInterventionTier
        if supervisorTier < recommended && invalidReasons.isEmpty {
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
}

func xtResolveProjectGovernance(
    projectRoot: URL,
    config: AXProjectConfig,
    legacyAutonomyLevel: AutonomyLevel? = nil,
    remoteOverride: AXProjectAutonomyRemoteOverrideSnapshot? = nil,
    permissionReadiness: AXTrustedAutomationPermissionOwnerReadiness = .current()
) -> AXProjectResolvedGovernanceState {
    AXProjectGovernanceResolver.resolve(
        projectRoot: projectRoot,
        config: config,
        legacyAutonomyLevel: legacyAutonomyLevel,
        remoteOverride: remoteOverride,
        permissionReadiness: permissionReadiness
    )
}

func xtResolveProjectGovernance(
    projectRoot: URL,
    config: AXProjectConfig,
    legacyAutonomyLevel: AutonomyLevel? = nil,
    effectiveAutonomy: AXProjectAutonomyEffectivePolicy,
    permissionReadiness: AXTrustedAutomationPermissionOwnerReadiness = .current()
) -> AXProjectResolvedGovernanceState {
    AXProjectGovernanceResolver.resolve(
        projectRoot: projectRoot,
        config: config,
        legacyAutonomyLevel: legacyAutonomyLevel,
        effectiveAutonomy: effectiveAutonomy,
        permissionReadiness: permissionReadiness
    )
}

func xtResolveProjectGovernance(
    projectRoot: URL,
    config: AXProjectConfig,
    legacyAutonomyLevel: AutonomyLevel? = nil
) async -> AXProjectResolvedGovernanceState {
    let projectId = AXProjectRegistryStore.projectId(forRoot: projectRoot)
    let remoteOverride = await HubIPCClient.requestProjectAutonomyPolicyOverride(projectId: projectId)
    return AXProjectGovernanceResolver.resolve(
        projectRoot: projectRoot,
        config: config,
        legacyAutonomyLevel: legacyAutonomyLevel,
        remoteOverride: remoteOverride,
        permissionReadiness: .current()
    )
}
