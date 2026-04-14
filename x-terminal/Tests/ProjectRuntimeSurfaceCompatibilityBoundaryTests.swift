import Foundation
import Testing

struct ProjectRuntimeSurfaceCompatibilityBoundaryTests {
    @Test
    func appModelKeepsRuntimeSurfaceAsPrimaryProjectRuntimeEntryPoints() throws {
        let source = try String(
            contentsOf: repoRoot().appendingPathComponent("x-terminal/Sources/AppModel.swift"),
            encoding: .utf8
        )

        #expect(source.contains("var projectRemoteRuntimeSurfaceOverride: AXProjectRuntimeSurfaceRemoteOverrideSnapshot? = nil"))
        #expect(source.contains("func setProjectRuntimeSurfacePolicy("))
        #expect(source.contains("func resolvedProjectRuntimeSurfacePolicy("))

        #expect(source.contains("Use projectRemoteRuntimeSurfaceOverride"))
        #expect(source.contains("Use setProjectRuntimeSurfacePolicy(mode:allowDeviceTools:allowBrowserRuntime:allowConnectorActions:allowExtensions:ttlSeconds:hubOverrideMode:)"))
        #expect(source.contains("Use resolvedProjectRuntimeSurfacePolicy(config:now:)"))
        #expect(source.contains("Use applyProjectGovernanceTemplate(_:)"))
        #expect(source.contains("Use governanceTemplatePreview(for:)"))
    }

    @Test
    func projectRuntimeSurfacePolicyFileKeepsLegacyAutonomyAsCompatOnly() throws {
        let source = try String(
            contentsOf: repoRoot().appendingPathComponent("x-terminal/Sources/Project/AXProjectRuntimeSurfacePolicy.swift"),
            encoding: .utf8
        )

        #expect(source.contains("func settingRuntimeSurfacePolicy("))
        #expect(source.contains("var runtimeSurfaceUpdatedAtDate: Date?"))
        #expect(source.contains("func effectiveRuntimeSurfacePolicy("))
        #expect(source.contains("func xtResolveProjectRuntimeSurfacePolicy("))

        #expect(source.contains("Use configuredRuntimeSurfaceLabels"))
        #expect(source.contains("Use settingRuntimeSurfacePolicy(mode:allowDeviceTools:allowBrowserRuntime:allowConnectorActions:allowExtensions:ttlSeconds:hubOverrideMode:updatedAt:)"))
        #expect(source.contains("Use runtimeSurfaceUpdatedAtDate"))
        #expect(source.contains("Use effectiveRuntimeSurfacePolicy(now:remoteOverride:)"))
        #expect(source.contains("Use AXProjectRuntimeSurfaceMode"))
        #expect(source.contains("Use AXProjectRuntimeSurfaceHubOverrideMode"))
        #expect(source.contains("Use AXProjectRuntimeSurfaceRemoteOverrideSnapshot"))
        #expect(source.contains("Use AXProjectRuntimeSurfaceEffectivePolicy"))
        #expect(source.contains("Use AXProjectResolvedRuntimeSurfacePolicyState"))
        #expect(source.contains("Use xtResolveProjectRuntimeSurfacePolicy(projectRoot:config:)"))

        #expect(source.contains("typealias AXProjectAutonomyMode = AXProjectRuntimeSurfaceMode"))
        #expect(source.contains("typealias AXProjectResolvedAutonomyPolicyState = AXProjectResolvedRuntimeSurfacePolicyState"))
    }

    @Test
    func governanceBundleKeepsRuntimeSurfacePrimaryAndLegacyAutonomyAsCompatOnly() throws {
        let source = try String(
            contentsOf: repoRoot().appendingPathComponent("x-terminal/Sources/Project/AXProjectGovernanceBundle.swift"),
            encoding: .utf8
        )

        #expect(source.contains("effectiveRuntimeSurface: AXProjectRuntimeSurfaceEffectivePolicy"))
        #expect(source.contains("Use applying(effectiveRuntimeSurface:trustedAutomationStatus:)"))
        #expect(source.contains("Use effectiveRuntimeSurface"))

        #expect(source.contains("effectiveAutonomy: AXProjectAutonomyEffectivePolicy"))
        #expect(source.contains("snapshot[\"runtime_surface_effective_mode\"]"))
        #expect(source.contains("snapshot[\"runtime_surface_hub_override_mode\"]"))

        #expect(source.contains("snapshot[\"effective_autonomy_mode\"]"))
        #expect(source.contains("snapshot[\"autonomy_ttl_sec\"]"))
        #expect(source.contains("snapshot[\"autonomy_remaining_sec\"]"))
        #expect(source.contains("snapshot[\"autonomy_expired\"]"))
    }

    @Test
    func governanceResolverKeepsRuntimeSurfaceNamedPrimaryEntryPoints() throws {
        let source = try String(
            contentsOf: repoRoot().appendingPathComponent("x-terminal/Sources/Project/AXProjectGovernanceResolver.swift"),
            encoding: .utf8
        )

        #expect(source.contains("effectiveRuntimeSurface: AXProjectRuntimeSurfaceEffectivePolicy"))
        #expect(source.contains("remoteOverride: AXProjectRuntimeSurfaceRemoteOverrideSnapshot? = nil"))
        #expect(source.contains("let effectiveRuntimeSurface = config.effectiveRuntimeSurfacePolicy(remoteOverride: remoteOverride)"))
        #expect(source.contains("Use resolve(projectRoot:config:legacyAutonomyLevel:effectiveRuntimeSurface:projectAIStrengthProfile:adaptationPolicy:permissionReadiness:)"))
        #expect(source.contains("Use xtResolveProjectGovernance(projectRoot:config:legacyAutonomyLevel:effectiveRuntimeSurface:projectAIStrengthProfile:adaptationPolicy:permissionReadiness:)"))

        #expect(source.contains("effectiveAutonomy: AXProjectAutonomyEffectivePolicy"))
        #expect(source.contains("effectiveRuntimeSurface: effectiveAutonomy"))
        #expect(source.contains("AXProjectExecutionTier.fromRuntimeSurfaceMode(config.runtimeSurfaceMode)"))
    }

    @Test
    func governanceExplanationAndExecutionTierUseRuntimeSurfaceTypesAsPrimaryNames() throws {
        let explanationSource = try String(
            contentsOf: repoRoot().appendingPathComponent("x-terminal/Sources/Project/AXProjectGovernanceSurfaceExplanation.swift"),
            encoding: .utf8
        )
        let executionTierSource = try String(
            contentsOf: repoRoot().appendingPathComponent("x-terminal/Sources/Project/AXProjectExecutionTier.swift"),
            encoding: .utf8
        )
        let configSource = try String(
            contentsOf: repoRoot().appendingPathComponent("x-terminal/Sources/Project/AXProjectConfig.swift"),
            encoding: .utf8
        )

        #expect(explanationSource.contains("func xtProjectRuntimeSurfaceExplanation("))
        #expect(explanationSource.contains("mode: AXProjectRuntimeSurfaceMode"))
        #expect(explanationSource.contains("effective: AXProjectRuntimeSurfaceEffectivePolicy"))
        #expect(explanationSource.contains("Use xtProjectRuntimeSurfaceExplanation(mode:style:)"))
        #expect(explanationSource.contains("Use xtProjectGovernanceClampExplanation(effective:style:)"))

        #expect(executionTierSource.contains("var defaultRuntimeSurfacePreset: AXProjectRuntimeSurfaceMode"))
        #expect(executionTierSource.contains("Use defaultRuntimeSurfacePreset"))
        #expect(executionTierSource.contains("static func fromRuntimeSurfaceMode(_ mode: AXProjectRuntimeSurfaceMode) -> AXProjectExecutionTier"))
        #expect(executionTierSource.contains("Use fromRuntimeSurfaceMode(_:)"))

        #expect(configSource.contains("var autonomyMode: AXProjectRuntimeSurfaceMode"))
        #expect(configSource.contains("var autonomyHubOverrideMode: AXProjectRuntimeSurfaceHubOverrideMode"))
        #expect(configSource.contains("c.decode(AXProjectRuntimeSurfaceMode.self, forKey: .autonomyMode)"))
        #expect(configSource.contains("c.decode(AXProjectRuntimeSurfaceHubOverrideMode.self, forKey: .autonomyHubOverrideMode)"))
    }

    private func repoRoot() -> URL {
        monorepoTestRepoRoot(filePath: #filePath)
    }
}
