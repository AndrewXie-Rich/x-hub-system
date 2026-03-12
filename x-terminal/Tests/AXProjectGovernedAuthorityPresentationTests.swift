import Foundation
import Testing
@testable import XTerminal

struct AXProjectGovernedAuthorityPresentationTests {
    @Test
    func defaultConfigShowsManualPresentation() {
        let fixture = ToolExecutorProjectFixture(name: "governed-authority-presentation-default")
        defer { fixture.cleanup() }

        let presentation = xtProjectGovernedAuthorityPresentation(
            projectRoot: fixture.root,
            config: .default(forProjectRoot: fixture.root)
        )

        #expect(presentation.deviceAuthorityConfigured == false)
        #expect(presentation.localAutoApproveConfigured == false)
        #expect(presentation.governedReadableRootCount == 0)
        #expect(presentation.pairedDeviceId.isEmpty)
        #expect(presentation.hasAnyVisibleSignal == false)
    }

    @Test
    func trustedOpenClawConfigShowsGovernedPresentationSignals() {
        let fixture = ToolExecutorProjectFixture(name: "governed-authority-presentation-configured")
        defer { fixture.cleanup() }

        let config = AXProjectConfig
            .default(forProjectRoot: fixture.root)
            .settingTrustedAutomationBinding(
                mode: .trustedAutomation,
                deviceId: "device_xt_001",
                deviceToolGroups: ["device.browser.control"],
                workspaceBindingHash: xtTrustedAutomationWorkspaceHash(forProjectRoot: fixture.root)
            )
            .settingAutonomyPolicy(
                mode: .trustedOpenClawMode,
                updatedAt: Date(timeIntervalSince1970: 1_773_900_000)
            )
            .settingGovernedReadableRoots(
                paths: ["/tmp", "/Users/shared"],
                projectRoot: fixture.root
            )
            .settingGovernedAutoApproveLocalToolCalls(enabled: true)

        let presentation = xtProjectGovernedAuthorityPresentation(
            projectRoot: fixture.root,
            config: config
        )

        #expect(presentation.deviceAuthorityConfigured == true)
        #expect(presentation.localAutoApproveConfigured == true)
        #expect(presentation.governedReadableRootCount == 2)
        #expect(presentation.pairedDeviceId == "device_xt_001")
        #expect(presentation.hasAnyVisibleSignal == true)
    }
}
