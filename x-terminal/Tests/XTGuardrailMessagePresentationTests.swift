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

        #expect(message.summary.contains("Hub 授权"))
        #expect(message.summary.contains("联网访问"))
        #expect(!message.summary.contains("web.fetch"))
        #expect(message.nextStep?.contains("Hub 或 Supervisor") == true)
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

        #expect(body.contains("Hub 授权"))
        #expect(body.contains("付费模型调用"))
        #expect(!body.contains("ai.generate.paid"))
        #expect(body.contains("批准新的授权"))
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

        #expect(body.contains("构建/测试命令"))
        #expect(body.contains("先在本地批准这个命令"))
    }

    @Test
    func blockedBodyUsesSharedKillSwitchExplanationForRuntimeSurfaceClamp() {
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

        #expect(body.contains("kill-switch"))
        #expect(body.contains("清除 kill-switch"))
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

        #expect(body.contains("运行面"))
        #expect(body.contains("设备级动作"))
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

        #expect(body.contains("运行面"))
        #expect(body.contains("设备级动作"))
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
            detail: "运行面 policy blocks device.browser.control on surface device_tools"
        )

        #expect(body?.contains("运行面") == true)
        #expect(body?.contains("设备级动作") == true)
    }

    @Test
    func repairHintRoutesGovernanceDenialToExecutionTier() {
        let hint = XTGuardrailMessagePresentation.repairHint(
            denyCode: "governance_capability_denied",
            policySource: "project_governance",
            policyReason: "execution_tier_missing_managed_processes"
        )

        #expect(hint?.destination == .executionTier)
        #expect(hint?.buttonTitle == "打开执行档位")
        #expect(hint?.helpText.contains("A2 Repo Auto") == true)
    }

    @Test
    func repairHintRoutesRuntimeClampToGovernanceOverview() {
        let hint = XTGuardrailMessagePresentation.repairHint(
            denyCode: "autonomy_policy_denied",
            policySource: "project_autonomy_policy",
            policyReason: "runtime_surface_effective=guided"
        )

        #expect(hint?.destination == .overview)
        #expect(hint?.buttonTitle == "打开治理设置")
        #expect(hint?.helpText.contains("项目治理") == true)
    }

    @Test
    func toolResultBodyPrefixesEffectiveGovernanceTruthWhenPresent() {
        let body = XTGuardrailMessagePresentation.toolResultBody(
            tool: .write_file,
            summary: [
                "deny_code": .string("governance_capability_denied"),
                "policy_source": .string("project_governance"),
                "policy_reason": .string("execution_tier_missing_repo_write"),
                "execution_tier": .string(AXProjectExecutionTier.a1Plan.rawValue),
                "effective_execution_tier": .string(AXProjectExecutionTier.a1Plan.rawValue),
                "supervisor_intervention_tier": .string(AXProjectSupervisorInterventionTier.s1MilestoneReview.rawValue),
                "effective_supervisor_intervention_tier": .string(AXProjectSupervisorInterventionTier.s2PeriodicReview.rawValue),
                "review_policy_mode": .string(AXProjectReviewPolicyMode.periodic.rawValue),
                "progress_heartbeat_sec": .number(900),
                "review_pulse_sec": .number(1800),
                "brainstorm_review_sec": .number(0),
                "governance_compat_source": .string(AXProjectGovernanceCompatSource.legacyAutonomyMode.rawValue)
            ],
            detail: "governance denied write_file"
        )

        #expect(body?.contains("治理真相：预设 A1/S1 · 当前生效 A1/S2 · 审查 Periodic · 节奏 心跳 15m / 脉冲 30m / 脑暴 off · 来源 兼容旧执行面预设。") == true)
        #expect(body?.contains("当前项目执行档位不允许写文件。") == true)
    }
}
