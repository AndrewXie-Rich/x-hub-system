import Foundation
import Testing
@testable import XTerminal

struct ProjectGovernanceSurfaceExplanationTests {

    @Test
    func effectiveClampAndRuntimePolicyReasonShareSameCanonicalExplanation() throws {
        let effective = AXProjectRuntimeSurfaceEffectivePolicy(
            configuredMode: .trustedOpenClawMode,
            effectiveMode: .guided,
            hubOverrideMode: .clampGuided,
            localOverrideMode: .none,
            remoteOverrideMode: .clampGuided,
            remoteOverrideUpdatedAtMs: 123,
            remoteOverrideSource: "hub",
            allowDeviceTools: false,
            allowBrowserRuntime: true,
            allowConnectorActions: false,
            allowExtensions: false,
            ttlSeconds: 600,
            remainingSeconds: 420,
            expired: false,
            killSwitchEngaged: false
        )

        let ui = try #require(
            xtProjectGovernanceClampExplanation(
                effective: effective,
                style: .uiChinese
            )
        )
        let guardrail = try #require(
            xtProjectGovernanceClampExplanation(
                policyReason: ui.policyReason,
                style: .guardrailEnglish
            )
        )

        #expect(ui.policyReason == AXProjectGovernanceClampKind.clampGuided.rawValue)
        #expect(ui.summary.contains("Hub clamp_guided"))
        #expect(guardrail.summary.contains("guided runtime surface"))
    }

    @Test
    func runtimeSurfaceExplanationUsesSurfaceLanguageInsteadOfLegacyAutonomyCopy() {
        let manual = xtProjectRuntimeSurfaceExplanation(mode: .manual, style: .uiChinese)
        let guided = xtProjectRuntimeSurfaceExplanation(mode: .guided, style: .guardrailEnglish)

        #expect(manual.contains("runtime surface"))
        #expect(!manual.contains("Manual 是最保守执行面"))
        #expect(guided.contains("guided runtime surface"))
        #expect(!guided.contains("guided mode"))
    }
}
