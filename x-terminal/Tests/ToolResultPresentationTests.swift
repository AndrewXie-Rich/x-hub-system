import Testing
@testable import XTerminal

struct ToolResultPresentationTests {

    @Test
    func browserSecretFillSuccessGetsVisibleSuccessCard() throws {
        let result = ToolResult(
            id: "tool_browser_secret_ok",
            tool: .deviceBrowserControl,
            ok: true,
            output: ToolExecutor.structuredOutput(
                summary: [
                    "tool": .string(ToolName.deviceBrowserControl.rawValue),
                    "ok": .bool(true),
                    "action": .string("type"),
                    "selector": .string("input[type=password]"),
                    "browser_runtime_driver_state": .string("secret_vault_applescript_fill"),
                    "browser_fill_tag_name": .string("input"),
                ],
                body: "session_id=browser_session_1"
            )
        )

        #expect(ToolResultPresentation.shouldShowTimelineCard(for: result))
        #expect(ToolResultPresentation.iconName(for: result) == "checkmark.shield.fill")
        #expect(ToolResultPresentation.title(for: result) == "已从 Secret Vault 填充凭据")
        #expect(ToolResultPresentation.body(for: result).contains("Secret Vault 凭据"))
        #expect(ToolResultPresentation.body(for: result).contains("input[type=password]"))
    }

    @Test
    func browserSecretBeginUseFailureGetsHumanReadableSummary() throws {
        let result = ToolResult(
            id: "tool_browser_secret_begin_fail",
            tool: .deviceBrowserControl,
            ok: false,
            output: ToolExecutor.structuredOutput(
                summary: [
                    "tool": .string(ToolName.deviceBrowserControl.rawValue),
                    "ok": .bool(false),
                    "action": .string("type"),
                    "selector": .string("input[type=password]"),
                    "deny_code": .string(XTDeviceAutomationRejectCode.browserSecretBeginUseFailed.rawValue),
                    "browser_runtime_driver_state": .string("secret_vault_resolution_failed"),
                    "secret_ref_only": .bool(true),
                    "secret_item_id": .string("sv_project_login"),
                    "secret_reason_code": .string("secret_vault_item_not_found"),
                ],
                body: "browser_secret_begin_use_failed"
            )
        )

        let summary = ToolResultPresentation.body(for: result)
        #expect(summary.contains("Hub 未授权此次凭据使用"))
        #expect(summary.contains("已不在 Hub 中"))
    }

    @Test
    func browserSecretFillFailureExplainsMissingSelectorTarget() throws {
        let result = ToolResult(
            id: "tool_browser_secret_fill_fail",
            tool: .deviceBrowserControl,
            ok: false,
            output: ToolExecutor.structuredOutput(
                summary: [
                    "tool": .string(ToolName.deviceBrowserControl.rawValue),
                    "ok": .bool(false),
                    "action": .string("type"),
                    "selector": .string("#password"),
                    "deny_code": .string(XTDeviceAutomationRejectCode.browserSecretFillFailed.rawValue),
                    "browser_runtime_driver_state": .string("secret_vault_applescript_fill_failed"),
                    "secret_ref_only": .bool(true),
                    "secret_item_id": .string("sv_project_login"),
                    "secret_reason_code": .string("selector_not_found"),
                ],
                body: "browser_secret_fill_failed"
            )
        )

        let summary = ToolResultPresentation.body(for: result)
        #expect(summary.contains("当前页面里找不到目标字段"))
        #expect(summary.contains("#password"))
    }

    @Test
    func browserUIObservationSuccessGetsVisibleSuccessCard() throws {
        let result = ToolResult(
            id: "tool_browser_observation_ok",
            tool: .deviceBrowserControl,
            ok: true,
            output: ToolExecutor.structuredOutput(
                summary: [
                    "tool": .string(ToolName.deviceBrowserControl.rawValue),
                    "ok": .bool(true),
                    "action": .string("snapshot"),
                    "browser_runtime_current_url": .string("https://example.com/login"),
                    "ui_observation_bundle_ref": .string("local://.xterminal/ui_observation/bundles/uob-1.json"),
                    "ui_observation_status": .string(XTUIObservationBundleStatus.captured.rawValue),
                    "ui_observation_probe_depth": .string(XTUIObservationProbeDepth.standard.rawValue),
                    "ui_observation_captured_layers": .number(5),
                    "ui_review_verdict": .string(XTUIReviewVerdict.ready.rawValue),
                    "ui_review_summary": .string("ready; confidence=high; all core review checks passed"),
                ],
                body: "local://.xterminal/browser_runtime/snapshots/brsnap-1.json"
            )
        )

        #expect(ToolResultPresentation.shouldShowTimelineCard(for: result))
        #expect(ToolResultPresentation.iconName(for: result) == "eye.fill")
        #expect(ToolResultPresentation.title(for: result) == "已采集浏览器 UI 观察")
        #expect(ToolResultPresentation.body(for: result).contains("https://example.com/login"))
        #expect(ToolResultPresentation.body(for: result).contains("5 层"))
        #expect(ToolResultPresentation.body(for: result).contains("审查结论：ready"))
    }

    @Test
    func governanceReasonSummarizesStructuredGovernanceDenial() throws {
        let result = ToolResult(
            id: "tool_write_file_governance_denied",
            tool: .write_file,
            ok: false,
            output: ToolExecutor.structuredOutput(
                summary: [
                    "tool": .string(ToolName.write_file.rawValue),
                    "ok": .bool(false),
                    "deny_code": .string("governance_capability_denied"),
                    "policy_source": .string("project_governance"),
                    "policy_reason": .string("execution_tier_missing_repo_write"),
                ],
                body: "governance denied write_file"
            )
        )

        #expect(ToolResultPresentation.governanceReason(for: result) == "当前项目 A-Tier 不允许写文件。")
        #expect(ToolResultPresentation.policyReason(for: result) == "execution_tier_missing_repo_write")
    }

    @Test
    func policyReasonPrefersRuntimeSurfaceAliasWhenPresent() throws {
        let result = ToolResult(
            id: "tool_browser_runtime_surface_denied",
            tool: .deviceBrowserControl,
            ok: false,
            output: ToolExecutor.structuredOutput(
                summary: [
                    "tool": .string(ToolName.deviceBrowserControl.rawValue),
                    "ok": .bool(false),
                    "deny_code": .string("autonomy_policy_denied"),
                    "policy_source": .string("project_autonomy_policy"),
                    "policy_reason": .string("autonomy_mode=guided"),
                    "runtime_surface_policy_reason": .string("runtime_surface_effective=guided"),
                ],
                body: "runtime surface denied browser control"
            )
        )

        #expect(ToolResultPresentation.policyReason(for: result) == "runtime_surface_effective=guided")
        #expect(ToolResultPresentation.governanceReason(for: result)?.contains("运行面") == true)
    }

    @Test
    func timelineBodySeparatesGovernanceTruthFromVisibleSummary() throws {
        let result = ToolResult(
            id: "tool_browser_truth_split",
            tool: .deviceBrowserControl,
            ok: false,
            output: ToolExecutor.structuredOutput(
                summary: [
                    "tool": .string(ToolName.deviceBrowserControl.rawValue),
                    "ok": .bool(false),
                    "deny_code": .string("autonomy_policy_denied"),
                    "policy_source": .string("project_autonomy_policy"),
                    "policy_reason": .string("autonomy_mode=guided"),
                    "runtime_surface_policy_reason": .string("runtime_surface_effective=guided"),
                    "execution_tier": .string(AXProjectExecutionTier.a4OpenClaw.rawValue),
                    "effective_execution_tier": .string(AXProjectExecutionTier.a4OpenClaw.rawValue),
                    "supervisor_intervention_tier": .string(AXProjectSupervisorInterventionTier.s3StrategicCoach.rawValue),
                    "effective_supervisor_intervention_tier": .string(AXProjectSupervisorInterventionTier.s3StrategicCoach.rawValue),
                    "review_policy_mode": .string(AXProjectReviewPolicyMode.hybrid.rawValue),
                    "progress_heartbeat_sec": .number(300),
                    "review_pulse_sec": .number(600),
                    "brainstorm_review_sec": .number(1800),
                    "governance_compat_source": .string(AXProjectGovernanceCompatSource.explicitDualDial.rawValue)
                ],
                body: "runtime surface blocks device.browser.control on surface device_tools"
            )
        )

        #expect(ToolResultPresentation.governanceTruthLine(for: result) == "治理真相：当前生效 A4/S3 · 审查 混合 · 节奏 心跳 5m / 脉冲 10m / 脑暴 30m。")
        #expect(ToolResultPresentation.body(for: result).contains("治理真相：当前生效 A4/S3") == true)
        #expect(ToolResultPresentation.timelineBody(for: result).contains("治理真相：") == false)
        #expect(ToolResultPresentation.timelineBody(for: result).contains("当前运行面仍然关闭了设备级动作。") == true)
    }
}
