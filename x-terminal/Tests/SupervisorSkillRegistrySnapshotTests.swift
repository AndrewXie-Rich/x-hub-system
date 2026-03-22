import Foundation
import Testing
@testable import XTerminal

struct SupervisorSkillRegistrySnapshotTests {

    @Test
    func memorySummaryIncludesRoutingHintsForBrowserAutomationFamily() {
        let guarded = SupervisorSkillRegistryItem(
            skillId: "guarded-automation",
            displayName: "Guarded Automation",
            description: "Governed browser automation",
            capabilitiesRequired: ["device.browser.control"],
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
        let agentBrowser = SupervisorSkillRegistryItem(
            skillId: "agent-browser",
            displayName: "Agent Browser",
            description: "Wrapper entry",
            capabilitiesRequired: ["web.navigate"],
            governedDispatch: nil,
            governedDispatchVariants: [],
            governedDispatchNotes: [],
            inputSchemaRef: "schema://agent-in",
            outputSchemaRef: "schema://agent-out",
            sideEffectClass: "browser",
            riskLevel: .high,
            requiresGrant: true,
            policyScope: "project",
            timeoutMs: 30_000,
            maxRetries: 2,
            available: true
        )

        let snapshot = SupervisorSkillRegistrySnapshot(
            schemaVersion: SupervisorSkillRegistrySnapshot.currentSchemaVersion,
            projectId: "project-alpha",
            projectName: "Project Alpha",
            updatedAtMs: 1_000,
            memorySource: "hub",
            items: [guarded, agentBrowser],
            auditRef: "audit-skill-routing-summary"
        )

        let summary = snapshot.memorySummary(maxItems: 4, maxChars: 2_000)

        #expect(summary.contains("display: Guarded Automation"))
        #expect(summary.contains("display: Agent Browser"))
        #expect(summary.contains("routing: entrypoints=trusted-automation, agent-browser, browser.open, browser.navigate, browser.runtime.inspect"))
        #expect(summary.contains("routing: prefers_builtin=guarded-automation"))
    }
}
