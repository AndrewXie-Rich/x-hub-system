import Foundation
import Testing
@testable import XTerminal

struct SupervisorPersonaResolverTests {

    @Test
    func explicitMentionMatchesAliasAcrossCaseAndWhitespace() {
        let resolver = SupervisorPersonaResolver()
        let registry = SupervisorPersonaRegistry.default(defaultVoicePersona: .conversational)

        let result = resolver.resolve(
            userMessage: "  ATLAS，帮我看下今天最重要的事  ",
            registry: registry,
            fallbackPersonaID: registry.defaultPersonaID,
            updatedAtMs: 123
        )

        #expect(result.persona.displayName == "Atlas")
        #expect(result.invocation?.matchedAlias.lowercased() == "atlas")
        #expect(result.invocation?.matchSource == .explicitName)
        #expect(result.invocation?.applyScope == .turn)
        #expect(result.reasonCode == "matched")
    }

    @Test
    func persistedDefaultCommandMatchesChineseAlias() {
        let resolver = SupervisorPersonaResolver()
        let registry = SupervisorPersonaRegistry.default(defaultVoicePersona: .conversational)

        let result = resolver.resolve(
            userMessage: "以后默认用 阿特拉斯",
            registry: registry,
            fallbackPersonaID: registry.defaultPersonaID
        )

        #expect(result.persona.displayName == "Atlas")
        #expect(result.invocation?.matchedAlias == "阿特拉斯")
        #expect(result.invocation?.applyScope == .persistedDefault)
    }

    @Test
    func atMentionUsesAtMentionSource() {
        let resolver = SupervisorPersonaResolver()
        let registry = SupervisorPersonaRegistry.default(defaultVoicePersona: .conversational)

        let result = resolver.resolve(
            userMessage: "@nova 帮我总结一下",
            registry: registry,
            fallbackPersonaID: registry.defaultPersonaID
        )

        #expect(result.persona.displayName == "Nova")
        #expect(result.invocation?.matchSource == .atMention)
        #expect(result.invocation?.applyScope == .turn)
    }

    @Test
    func ambiguousMatchFailsClosedToFallbackPersona() {
        var registry = SupervisorPersonaRegistry.default(defaultVoicePersona: .conversational)
        var atlas = registry.slots[1]
        atlas.aliases.append("nova")
        registry = registry.setting(slot: atlas)

        let resolver = SupervisorPersonaResolver()
        let result = resolver.resolve(
            userMessage: "nova，过来一下",
            registry: registry,
            fallbackPersonaID: registry.defaultPersonaID
        )

        #expect(result.persona.displayName == "Supervisor")
        #expect(result.invocation == nil)
        #expect(result.reasonCode == "ambiguous_match")
    }

    @Test
    func disabledPersonaCannotBeInvokedByName() {
        var registry = SupervisorPersonaRegistry.default(defaultVoicePersona: .conversational)
        var atlas = registry.slots[1]
        atlas.enabled = false
        registry = registry.setting(slot: atlas)

        let resolver = SupervisorPersonaResolver()
        let result = resolver.resolve(
            userMessage: "atlas，帮我总结一下",
            registry: registry,
            fallbackPersonaID: registry.defaultPersonaID
        )

        #expect(result.persona.displayName == "Supervisor")
        #expect(result.invocation == nil)
        #expect(result.reasonCode == "default_fallback")
    }

    @Test
    func wakePhraseMatchUsesSessionScopeAndWakeSource() {
        let resolver = SupervisorPersonaResolver()
        let registry = SupervisorPersonaRegistry.default(defaultVoicePersona: .conversational)

        let result = resolver.resolveWakePhrase(
            phrase: "atlas",
            registry: registry,
            fallbackPersonaID: registry.defaultPersonaID,
            updatedAtMs: 456
        )

        #expect(result.persona.displayName == "Atlas")
        #expect(result.invocation?.matchedAlias.lowercased() == "atlas")
        #expect(result.invocation?.matchSource == .wakePhrase)
        #expect(result.invocation?.applyScope == .session)
        #expect(result.reasonCode == "matched")
    }

    @Test
    func genericWakePhraseFallsBackWithoutSwitchingPersona() {
        let resolver = SupervisorPersonaResolver()
        var registry = SupervisorPersonaRegistry.default(defaultVoicePersona: .conversational)
        registry = registry.setting(activePersonaID: "persona_slot_4")

        let result = resolver.resolveWakePhrase(
            phrase: "supervisor",
            registry: registry,
            fallbackPersonaID: "persona_slot_4"
        )

        #expect(result.persona.personaID == "persona_slot_4")
        #expect(result.invocation == nil)
        #expect(result.reasonCode == "generic_wake_fallback")
    }
}
