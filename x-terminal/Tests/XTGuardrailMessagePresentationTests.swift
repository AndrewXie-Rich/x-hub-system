import Testing
@testable import XTerminal

struct XTGuardrailMessagePresentationTests {

    @Test
    func awaitingApprovalMessageHumanizesHubCapability() {
        let message = XTGuardrailMessagePresentation.awaitingApprovalMessage(
            toolLabel: "browser control",
            target: "https://example.com",
            requiredCapability: "web.fetch",
            denyCode: "grant_required"
        )

        #expect(message.summary.contains("Waiting for Hub grant approval"))
        #expect(message.summary.contains("联网访问"))
        #expect(!message.summary.contains("web.fetch"))
        #expect(message.nextStep?.contains("Approve the grant in Hub or Supervisor") == true)
    }

    @Test
    func blockedBodyHumanizesDeniedHubCapability() {
        let body = XTGuardrailMessagePresentation.blockedBody(
            tool: .run_command,
            toolLabel: "run command",
            denyCode: "grant_denied",
            policySource: "",
            policyReason: "",
            requiredCapability: "ai.generate.paid",
            fallbackSummary: "",
            fallbackDetail: ""
        )

        #expect(body.contains("Hub grant approval"))
        #expect(body.contains("付费模型调用"))
        #expect(!body.contains("ai.generate.paid"))
        #expect(body.contains("approve a new grant before retrying"))
    }

    @Test
    func blockedBodyExplainsGovernedRepoCommandAllowlist() {
        let body = XTGuardrailMessagePresentation.blockedBody(
            tool: .run_command,
            toolLabel: "run command",
            denyCode: "",
            policySource: "governed_command_guard",
            policyReason: "command_outside_governed_repo_allowlist",
            requiredCapability: "",
            fallbackSummary: "",
            fallbackDetail: ""
        )

        #expect(body.contains("build and test commands"))
        #expect(body.contains("Approve this command locally"))
    }

    @Test
    func blockedBodyUsesSharedKillSwitchExplanationForAutonomyClamp() {
        let body = XTGuardrailMessagePresentation.blockedBody(
            tool: .browser_read,
            toolLabel: "browser navigate",
            denyCode: "autonomy_policy_denied",
            policySource: "project_autonomy_policy",
            policyReason: "hub_override=kill_switch",
            requiredCapability: "",
            fallbackSummary: "",
            fallbackDetail: ""
        )

        #expect(body.contains("kill switch"))
        #expect(body.contains("Clear the kill switch"))
    }

    @Test
    func blockedBodyUsesRuntimeSurfaceLanguageForGuidedSurfaceBlock() {
        let body = XTGuardrailMessagePresentation.blockedBody(
            tool: .deviceBrowserControl,
            toolLabel: "device browser",
            denyCode: "autonomy_policy_denied",
            policySource: "project_autonomy_policy",
            policyReason: "autonomy_mode=guided",
            requiredCapability: "",
            fallbackSummary: "",
            fallbackDetail: ""
        )

        #expect(body.contains("runtime surface"))
        #expect(body.contains("device-level actions"))
        #expect(!body.contains("autonomy policy"))
    }

    @Test
    func blockedBodyAcceptsRuntimeSurfaceReasonAliasForGuidedBlock() {
        let body = XTGuardrailMessagePresentation.blockedBody(
            tool: .deviceBrowserControl,
            toolLabel: "device browser",
            denyCode: "autonomy_policy_denied",
            policySource: "project_autonomy_policy",
            policyReason: "runtime_surface_effective=guided",
            requiredCapability: "",
            fallbackSummary: "",
            fallbackDetail: ""
        )

        #expect(body.contains("runtime surface"))
        #expect(body.contains("device-level actions"))
    }

    @Test
    func toolResultBodyPrefersRuntimeSurfacePolicyReasonAliasWhenPresent() {
        let body = XTGuardrailMessagePresentation.toolResultBody(
            tool: .deviceBrowserControl,
            summary: [
                "deny_code": .string("autonomy_policy_denied"),
                "policy_source": .string("project_autonomy_policy"),
                "policy_reason": .string("autonomy_mode=guided"),
                "runtime_surface_policy_reason": .string("runtime_surface_effective=guided"),
            ],
            detail: "runtime surface policy blocks device.browser.control on surface device_tools"
        )

        #expect(body?.contains("runtime surface") == true)
        #expect(body?.contains("device-level actions") == true)
    }
}
