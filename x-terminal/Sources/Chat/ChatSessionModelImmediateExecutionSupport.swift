import Foundation

extension ChatSessionModel {
    func normalizedProjectDirectReplyQuestion(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "’", with: "'")
    }

    func isImmediateProjectExecutionIntent(_ normalized: String) -> Bool {
        guard !normalized.isEmpty else { return false }
        let blockerTokens = [
            "怎么",
            "如何",
            "how to",
            "can you",
            "能不能",
            "可不可以"
        ]
        if blockerTokens.contains(where: { normalized.contains($0) }) {
            return false
        }
        let continuationQuestionTokens = [
            "怎么继续",
            "如何继续",
            "继续吗",
            "能继续吗",
            "可以继续吗",
            "你可以继续吗",
            "你能继续吗",
            "can you continue",
            "should we continue",
            "how do we continue"
        ]
        if continuationQuestionTokens.contains(where: { normalized.contains($0) }) {
            return false
        }

        let intentTokens = [
            "开始编写",
            "开始写",
            "开始做",
            "开始实现",
            "开始编码",
            "直接开始",
            "现在开始",
            "start coding",
            "start implementing",
            "implement it",
            "build it",
            "write the code"
        ]
        let continuationTokens = [
            "继续",
            "继续推进",
            "往下面推进",
            "往下推进",
            "接着做",
            "继续做",
            "往下做",
            "继续写",
            "接着写",
            "继续实现",
            "继续开发",
            "继续下去",
            "go ahead",
            "keep going",
            "continue working",
            "continue coding"
        ]
        let workTokens = [
            "代码",
            "功能",
            "实现",
            "项目",
            "code",
            "coding",
            "feature",
            "implementation",
            "project"
        ]
        let hasContinuationIntent = continuationTokens.contains(where: { normalized.contains($0) })
        if hasContinuationIntent {
            if normalized.contains("?") || normalized.contains("？") {
                return false
            }
            return true
        }
        let hasIntent = intentTokens.contains(where: { normalized.contains($0) })
        let hasWorkTarget = workTokens.contains(where: { normalized.contains($0) })
        return hasIntent && hasWorkTarget
    }

    func shouldBootstrapImmediateExecution(flow: ToolFlowState) -> Bool {
        guard flow.step == 1 else { return false }
        guard flow.toolResults.isEmpty else { return false }
        return isImmediateProjectExecutionIntent(normalizedProjectDirectReplyQuestion(flow.userText))
    }

    func shouldBootstrapCurrentAttachmentInspection(flow: ToolFlowState) -> Bool {
        guard flow.step == 1 else { return false }
        guard flow.toolResults.isEmpty else { return false }
        guard !flow.currentTurnAttachments.isEmpty else { return false }
        let normalized = normalizedProjectDirectReplyQuestion(flow.userText)
        guard !normalized.isEmpty else { return true }
        let attachmentReferenceTokens = [
            "这个文件",
            "这个文档",
            "这个附件",
            "这份文件",
            "这份文档",
            "附件",
            "拖进来",
            "刚拖",
            "发给你",
            "this file",
            "this attachment",
            "attached file",
            "attachment",
            "what is this",
            "what does this"
        ]
        return attachmentReferenceTokens.contains { normalized.contains($0) }
    }

    func currentAttachmentInspectionBootstrapCalls(flow: ToolFlowState) -> [ToolCall] {
        let allowedTools = effectiveToolPolicy(config: flow.config).allowed
        var calls: [ToolCall] = []
        for attachment in flow.currentTurnAttachments.prefix(3) {
            switch attachment.kind {
            case .file:
                guard allowedTools.contains(.read_file) else { continue }
                calls.append(
                    ToolCall(
                        id: "attachment_read_\(calls.count + 1)",
                        tool: .read_file,
                        args: ["path": .string(attachment.toolPath)]
                    )
                )
            case .directory:
                guard allowedTools.contains(.list_dir) else { continue }
                calls.append(
                    ToolCall(
                        id: "attachment_list_\(calls.count + 1)",
                        tool: .list_dir,
                        args: ["path": .string(attachment.toolPath)]
                    )
                )
            }
        }
        return calls
    }

    func immediateExecutionBootstrapCalls(config: AXProjectConfig?, projectRoot: URL) -> [ToolCall] {
        let allowedTools = effectiveToolPolicy(config: config).allowed
        var calls: [ToolCall] = []
        if allowedTools.contains(.list_dir) {
            calls.append(
                ToolCall(
                    id: "bootstrap_list_dir",
                    tool: .list_dir,
                    args: ["path": .string(".")]
                )
            )
        }
        if allowedTools.contains(.git_status), GitTool.isGitRepo(root: projectRoot) {
            calls.append(
                ToolCall(
                    id: "bootstrap_git_status",
                    tool: .git_status,
                    args: [:]
                )
            )
        }
        return calls
    }

    func hasMeaningfulExecutionProgress(_ toolResults: [ToolResult]) -> Bool {
        toolResults.contains {
            $0.tool == .write_file
                || $0.tool == .git_apply
                || $0.tool == .run_command
        }
    }

    func containsConcreteExecutionBlockerSignal(_ normalized: String) -> Bool {
        guard !normalized.isEmpty else { return false }
        let blockerTokens = [
            "what type",
            "which type",
            "please specify",
            "please clarify",
            "need you to clarify",
            "need more information",
            "missing requirement",
            "需要你确认",
            "需要先确认",
            "请先说明",
            "请先确认",
            "缺少必要信息"
        ]
        if blockerTokens.contains(where: { normalized.contains($0) }) {
            return true
        }
        return normalized.contains("?") || normalized.contains("？")
    }

    func looksLikeExecutionAcknowledgementOnly(_ normalized: String) -> Bool {
        guard !normalized.isEmpty else { return true }
        if containsConcreteExecutionBlockerSignal(normalized) {
            return false
        }
        let deferralTokens = [
            "我已收到",
            "开始编写",
            "开始实现",
            "开始处理",
            "我会",
            "我将",
            "当然可以",
            "可以",
            "好的",
            "收到",
            "acknowledged",
            "i will",
            "i'll",
            "starting to",
            "beginning to",
            "beginning of",
            "starting the",
            "will start",
            "coding project",
            "implementation project",
            "project coding"
        ]
        let executionEvidenceTokens = [
            "已创建",
            "已修改",
            "已新增",
            "写入",
            "patch",
            "diff",
            "文件",
            "created",
            "updated",
            "modified",
            "wrote",
            "changed"
        ]
        if executionEvidenceTokens.contains(where: { normalized.contains($0) }) {
            return false
        }
        let wordCount = normalized.split(whereSeparator: \.isWhitespace).count
        let genericWorkTokens = [
            "project",
            "code",
            "coding",
            "implementation",
            "开始",
            "编写",
            "代码"
        ]
        if wordCount <= 12 && genericWorkTokens.contains(where: { normalized.contains($0) }) {
            return true
        }
        return deferralTokens.contains(where: { normalized.contains($0) })
    }

    func shouldRepairImmediateExecution(flow: ToolFlowState, assistantText: String) -> Bool {
        guard !flow.executionRetryUsed else { return false }
        guard isImmediateProjectExecutionIntent(normalizedProjectDirectReplyQuestion(flow.userText)) else { return false }
        guard !hasMeaningfulExecutionProgress(flow.toolResults) else { return false }
        return looksLikeExecutionAcknowledgementOnly(
            normalizedProjectDirectReplyQuestion(assistantText)
        )
    }

    func immediateExecutionRepairPrompt(basePrompt: String, previousResponse: String) -> String {
        basePrompt + """


RETRY MODE:
- The user explicitly asked you to start coding now.
- Your previous response did not actually begin the work.
- On this retry, do NOT restate, acknowledge, or paraphrase the request.
- You must either:
  1. emit tool_calls that inspect, create, edit, or run within the project immediately, or
  2. return {"final":"..."} only if a single concrete blocker prevents execution right now.
- If the workspace is empty or no stack is detected, choose a sensible stack and scaffold the minimal runnable files first.

Previous non-executing response:
\(previousResponse)
"""
    }

    func parseToolActionEnvelope(from text: String) -> ToolActionEnvelopeParseResult {
        guard let json = JSONExtractor.extractFirstJSON(from: text) else {
            return .none
        }
        guard let env = try? JSONDecoder().decode(ToolActionEnvelope.self, from: Data(json.utf8)) else {
            return .invalidJSONEnvelope
        }
        return .envelope(env)
    }

    func immediateExecutionRepairProducedExecutableResult(_ envelope: ToolActionEnvelope) -> Bool {
        if let calls = envelope.tool_calls, !calls.isEmpty {
            return true
        }
        if let skillCalls = envelope.skill_calls, !skillCalls.isEmpty {
            return true
        }
        guard let final = envelope.final?.trimmingCharacters(in: .whitespacesAndNewlines),
              !final.isEmpty else {
            return false
        }
        return !looksLikeExecutionAcknowledgementOnly(normalizedProjectDirectReplyQuestion(final))
    }

    func shouldFailClosedPlanningResponse(
        userText: String,
        parseResult: ToolActionEnvelopeParseResult,
        modelOutput: String
    ) -> Bool {
        switch parseResult {
        case .invalidJSONEnvelope:
            return true
        case .envelope:
            return false
        case .none:
            let normalizedUserText = normalizedProjectDirectReplyQuestion(userText)
            guard isImmediateProjectExecutionIntent(normalizedUserText) else { return false }
            let normalizedOutput = normalizedProjectDirectReplyQuestion(modelOutput)
            if normalizedOutput.isEmpty {
                return true
            }
            return looksLikeExecutionAcknowledgementOnly(normalizedOutput)
        }
    }

    func planningContractFailureMessage(userText: String, modelOutput: String) -> String {
        let immediateExecution = isImmediateProjectExecutionIntent(
            normalizedProjectDirectReplyQuestion(userText)
        )
        let returnedJSONPlan = JSONExtractor.extractFirstJSON(from: modelOutput) != nil

        if immediateExecution {
            if returnedJSONPlan {
                return """
❌ Project AI 本轮返回了计划对象，但没有进入可执行工具协议，已按 fail-closed 中止，不把这类 JSON 计划当成真实执行结果。

下一步：
1. 直接重试当前请求。
2. 如果当前目录还没有明确工程结构，请同时说明要用什么技术栈或运行形式。
3. 也可以把目标收敛到一个具体文件或具体功能，我会继续执行。
"""
            }

            return """
❌ Project AI 本轮没有真正开始执行，已按 fail-closed 中止，避免把确认语或空转回复当成完成进度。

下一步：
1. 直接重试当前请求。
2. 如果当前目录还没有明确工程结构，请同时说明要用什么技术栈或运行形式。
3. 也可以把目标收敛到一个具体文件或具体功能，我会继续执行。
"""
        }

        if returnedJSONPlan {
            return """
❌ Project AI 本轮返回了不符合工具协议的计划对象，已按 fail-closed 中止，不把原始 JSON 直接当作回复。

请重试，或把请求收敛到更具体的文件或功能级目标。
"""
        }

        return """
❌ Project AI 本轮没有按工具协议返回可执行结果，已中止本轮。

请重试，或把目标收敛到更具体的文件或功能级任务。
"""
    }
}
