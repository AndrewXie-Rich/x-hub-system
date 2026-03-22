import Foundation
import Testing
@testable import XTerminal

struct SupervisorSkillRoutingCompatibilityHintTests {

    @Test
    func routingResolutionExplainsPreferredBuiltinSelectionForEntrypoint() {
        let resolution = SupervisorSkillRoutingCompatibilityHint.routingResolution(
            requestedSkillId: "browser.open",
            effectiveSkillId: "guarded-automation",
            payload: [
                "action": .string("open"),
                "url": .string("https://example.com")
            ]
        )

        #expect(resolution?.summary == "browser.open -> guarded-automation · action=open")
        #expect(resolution?.reasonCode == "preferred_builtin_selected")
        #expect(resolution?.explanation?.contains("requested entrypoint browser.open converged to preferred builtin guarded-automation") == true)
        #expect(resolution?.explanation?.contains("resolved action open") == true)
    }

    @Test
    func routingResolutionExplainsWrapperConvergenceWhenPreferredBuiltinExists() {
        let resolution = SupervisorSkillRoutingCompatibilityHint.routingResolution(
            requestedSkillId: "agent-browser",
            effectiveSkillId: "guarded-automation",
            payload: [:],
            registryItems: [
                SupervisorSkillRegistryItem(
                    skillId: "guarded-automation",
                    displayName: "Guarded Automation",
                    description: "Governed browser automation",
                    capabilitiesRequired: [],
                    governedDispatch: nil,
                    governedDispatchVariants: [],
                    governedDispatchNotes: [],
                    inputSchemaRef: "schema://guarded-in",
                    outputSchemaRef: "schema://guarded-out",
                    sideEffectClass: "browser",
                    riskLevel: .high,
                    requiresGrant: true,
                    policyScope: "xt_builtin",
                    timeoutMs: 30_000,
                    maxRetries: 2,
                    available: true
                )
            ]
        )

        #expect(resolution?.reasonCode == "preferred_builtin_selected")
        #expect(resolution?.explanation?.contains("requested wrapper agent-browser converged to preferred builtin guarded-automation") == true)
    }

    @Test
    func routingResolutionExplainsAliasNormalization() {
        let resolution = SupervisorSkillRoutingCompatibilityHint.routingResolution(
            requestedSkillId: "trusted-automation",
            effectiveSkillId: "guarded-automation",
            payload: [:]
        )

        #expect(resolution?.reasonCode == "requested_alias_normalized")
        #expect(resolution?.explanation == "alias trusted-automation normalized to guarded-automation")
    }
}
