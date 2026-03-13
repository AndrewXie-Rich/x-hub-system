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
        #expect(ToolResultPresentation.title(for: result) == "Credential filled from Secret Vault")
        #expect(ToolResultPresentation.body(for: result).contains("Secret Vault credential"))
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
        #expect(summary.contains("Hub did not authorize this credential use"))
        #expect(summary.contains("no longer available in Hub"))
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
        #expect(summary.contains("does not contain the target field"))
        #expect(summary.contains("#password"))
    }
}
