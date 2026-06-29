import Foundation

extension ChatSessionModel {
    func requiresVerify(flow: ToolFlowState) -> Bool {
        let cmds = cleanedVerifyCommands(flow.config)
        guard let cfg = flow.config, cfg.verifyAfterChanges, !cmds.isEmpty else { return false }
        return flow.dirtySinceVerify
    }

    func cleanedVerifyCommands(_ config: AXProjectConfig?) -> [String] {
        guard let config else { return [] }
        return config.verifyCommands
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    func nextVerifyCallsIfNeeded(flow: inout ToolFlowState) -> [ToolCall]? {
        if !requiresVerify(flow: flow) { return nil }
        let cmds = cleanedVerifyCommands(flow.config)
        if cmds.isEmpty { return nil }

        flow.verifyRunIndex += 1
        let runId = flow.verifyRunIndex

        return [
            ToolCall(
                id: "verify\(runId)_diagnostics",
                tool: .projectDiagnostics,
                args: [
                    "trigger": .string("post_mutation"),
                    "kind": .string("verify"),
                    "use_verify_commands": .bool(true),
                    "timeout_sec": .number(900),
                ]
            )
        ]
    }

    func verifyRunOK(flow: ToolFlowState) -> Bool {
        let runId = flow.verifyRunIndex
        let prefix = "verify\(runId)_"
        let results = flow.toolResults.filter { $0.id.hasPrefix(prefix) }
        if results.isEmpty { return false }
        return results.allSatisfy { $0.ok }
    }

    func formatRepairPrompt(original: String) -> String {
        """
You produced output that is not valid JSON.

Return ONLY one valid JSON object in this exact schema:
- If you need tools: {"tool_calls":[{"id":"1","tool":"need_network","args":{"seconds":900}}]}
- If you need an installed governed skill: {"skill_calls":[{"id":"1","skill_id":"find-skills","payload":{"query":"browser automation"}}]}
- If done: {"final":"..."}

If the user request requires file changes, prefer tool_calls (create/edit files) over returning a plan in final.

Do NOT use single quotes.
Do NOT include markdown.
Do NOT include extra keys.

Original output:
\(original)
"""
    }

    // Governed project turns can repair or fail-close a draft tool-contract response.
    // Keep the progress rail visible, but avoid streaming unstable assistant text that
    // would immediately be replaced by the canonical runtime outcome.
    func projectCoderVisibleStreamMode(for stage: String) -> VisibleLLMStreamMode {
        switch stage {
        case "chat_plan", "chat_finalize_only":
            return .none
        default:
            return .none
        }
    }
}
