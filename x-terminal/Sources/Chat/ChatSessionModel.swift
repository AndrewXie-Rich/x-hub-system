import Foundation

@MainActor
final class ChatSessionModel: ObservableObject {
    @Published var messages: [AXChatMessage] = []
    @Published var draft: String = ""
    @Published var isSending: Bool = false
    @Published var lastError: String? = nil

    @Published var currentReqId: String? = nil

    @Published var autoRunTools: Bool = false
    @Published var pendingToolCalls: [ToolCall] = []

    private var pendingFlow: ToolFlowState? = nil
    private var activeRouter: LLMRouter? = nil
    private var lastCoderProviderTag: String = ""
    private var loadedRootPath: String? = nil
    // Cold-start handoff: include more recent context for the first prompt after switching projects.
    private var expandRecentOnceAfterLoad: Bool = false
    private var activeConfig: AXProjectConfig? = nil
    private var toolStreamStates: [String: ToolStreamState] = [:]
    private let sessionManager = AXSessionManager.shared
    private var boundSessionId: String? = nil
    private var currentRunId: String? = nil

    private struct ToolStreamState {
        var header: String
        var display: String
        var truncated: Bool
    }

    private let toolStreamMaxChars: Int = 12000

    private struct ToolFlowState {
        var ctx: AXProjectContext
        var memory: AXMemory?
        var config: AXProjectConfig?
        var userText: String
        var step: Int
        var toolResults: [ToolResult]
        var assistantIndex: Int

        // Verification / repair control.
        var dirtySinceVerify: Bool
        var verifyRunIndex: Int
        var repairAttemptsUsed: Int
        var deferredFinal: String?
        var finalizeOnly: Bool

        var formatRetryUsed: Bool
    }

    private struct MemoryV1BuildInfo {
        var text: String
        var source: String
        var usedTokens: Int?
        var budgetTokens: Int?
        var truncatedLayers: [String]
        var redactedItems: Int?
        var privateDrops: Int?
    }

    private struct PromptBuildOutput {
        var prompt: String
        var memory: MemoryV1BuildInfo
    }

    func cancel() {
        guard let rid = currentReqId else { return }
        Task {
            await HubAIClient.shared.cancel(reqId: rid)
        }
    }

    func loadFromRawLog(ctx: AXProjectContext, limit: Int = 20) {
        messages = []
        guard FileManager.default.fileExists(atPath: ctx.rawLogURL.path) else { return }
        guard let data = try? Data(contentsOf: ctx.rawLogURL), let s = String(data: data, encoding: .utf8) else { return }

        var turns: [(Double, String, String)] = []
        for line in s.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let ld = line.data(using: .utf8) else { continue }
            guard let obj = try? JSONSerialization.jsonObject(with: ld) as? [String: Any] else { continue }
            guard (obj["type"] as? String) == "turn" else { continue }
            let ts = (obj["created_at"] as? Double) ?? 0
            let u = (obj["user"] as? String) ?? ""
            let a = (obj["assistant"] as? String) ?? ""
            turns.append((ts, u, a))
        }
        turns.sort { $0.0 < $1.0 }
        let tail = turns.suffix(max(0, limit))
        for (ts, u, a) in tail {
            if !u.isEmpty { messages.append(AXChatMessage(role: .user, content: u, createdAt: ts)) }
            if !a.isEmpty { messages.append(AXChatMessage(role: .assistant, content: a, createdAt: ts)) }
        }
    }

    func ensureLoaded(ctx: AXProjectContext, limit: Int = 200) {
        let rootPath = ctx.root.standardizedFileURL.path
        if loadedRootPath == rootPath { return }
        resetSessionState()
        _ = ensurePrimarySessionBound(ctx: ctx)
        expandRecentOnceAfterLoad = true
        // Ensure recent_context exists for prompt assembly (especially for older projects).
        AXRecentContextStore.bootstrapFromRawLogIfNeeded(ctx: ctx, maxTurns: 12)
        loadFromRawLog(ctx: ctx, limit: limit)
        restorePendingToolApprovalIfAny(ctx: ctx)
        loadedRootPath = rootPath
    }

    private func resetSessionState() {
        messages = []
        draft = ""
        isSending = false
        lastError = nil
        currentReqId = nil
        pendingToolCalls = []
        pendingFlow = nil
        activeRouter = nil
        lastCoderProviderTag = ""
        activeConfig = nil
        toolStreamStates = [:]
        boundSessionId = nil
        currentRunId = nil
    }

    private func ensurePrimarySessionBound(ctx: AXProjectContext) -> String {
        let projectId = AXProjectRegistryStore.projectId(forRoot: ctx.root)
        if let boundSessionId,
           let session = sessionManager.session(for: boundSessionId),
           session.projectId == projectId {
            currentRunId = session.runtime?.runID
            return boundSessionId
        }

        let session = sessionManager.ensurePrimarySession(
            projectId: projectId,
            title: ctx.projectName(),
            directory: ctx.root.standardizedFileURL.path
        )
        boundSessionId = session.id
        currentRunId = session.runtime?.runID
        return session.id
    }

    private func withBoundSessionRuntime(
        ctx: AXProjectContext,
        at timestamp: Double = Date().timeIntervalSince1970,
        _ mutate: (inout AXSessionRuntimeSnapshot) -> Void
    ) {
        let sessionId = ensurePrimarySessionBound(ctx: ctx)
        if let updated = sessionManager.updateRuntime(sessionId: sessionId, at: timestamp, mutate) {
            boundSessionId = updated.id
            currentRunId = updated.runtime?.runID
        }
    }

    private func ensureRunID() -> String {
        if let currentRunId, !currentRunId.isEmpty {
            return currentRunId
        }
        let created = UUID().uuidString
        currentRunId = created
        return created
    }

    private func summarizeRuntimeText(_ text: String, max: Int = 160) -> String {
        let normalized = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count > max else { return normalized }
        let end = normalized.index(normalized.startIndex, offsetBy: max)
        return String(normalized[..<end]) + "..."
    }

    private func recordRunStart(ctx: AXProjectContext, userText: String, state: AXSessionRuntimeState = .planning) {
        let now = Date().timeIntervalSince1970
        let runID = UUID().uuidString
        currentRunId = runID
        withBoundSessionRuntime(ctx: ctx, at: now) { runtime in
            runtime.state = state
            runtime.runID = runID
            runtime.startedAt = now
            runtime.completedAt = nil
            runtime.lastRuntimeSummary = summarizeRuntimeText(userText)
            runtime.lastToolBatchIDs = []
            runtime.pendingToolCallCount = 0
            runtime.lastFailureCode = nil
            runtime.resumeToken = runID
            runtime.recoverable = false
        }
    }

    private func recordAwaitingModel(ctx: AXProjectContext, detail: String) {
        let now = Date().timeIntervalSince1970
        let runID = ensureRunID()
        withBoundSessionRuntime(ctx: ctx, at: now) { runtime in
            runtime.state = .awaiting_model
            runtime.runID = runID
            runtime.startedAt = runtime.startedAt ?? now
            runtime.completedAt = nil
            runtime.lastRuntimeSummary = summarizeRuntimeText(detail)
            runtime.pendingToolCallCount = 0
            runtime.lastFailureCode = nil
            runtime.resumeToken = runID
            runtime.recoverable = false
        }
    }

    private func recordAwaitingToolApproval(ctx: AXProjectContext, calls: [ToolCall], reason: String) {
        let now = Date().timeIntervalSince1970
        let runID = ensureRunID()
        withBoundSessionRuntime(ctx: ctx, at: now) { runtime in
            runtime.state = .awaiting_tool_approval
            runtime.runID = runID
            runtime.startedAt = runtime.startedAt ?? now
            runtime.completedAt = nil
            runtime.lastRuntimeSummary = summarizeRuntimeText(reason)
            runtime.lastToolBatchIDs = calls.map(\.id)
            runtime.pendingToolCallCount = calls.count
            runtime.lastFailureCode = nil
            runtime.resumeToken = "tool_approval:\(runID)"
            runtime.recoverable = true
        }
    }

    private func recordRunningTools(ctx: AXProjectContext, toolCalls: [ToolCall], reason: String? = nil) {
        let now = Date().timeIntervalSince1970
        let runID = ensureRunID()
        let summary = reason ?? "running_tools: \(toolCalls.map { $0.tool.rawValue }.joined(separator: ", "))"
        withBoundSessionRuntime(ctx: ctx, at: now) { runtime in
            runtime.state = .running_tools
            runtime.runID = runID
            runtime.startedAt = runtime.startedAt ?? now
            runtime.completedAt = nil
            runtime.lastRuntimeSummary = summarizeRuntimeText(summary)
            runtime.lastToolBatchIDs = toolCalls.map(\.id)
            runtime.pendingToolCallCount = 0
            runtime.lastFailureCode = nil
            runtime.resumeToken = runID
            runtime.recoverable = false
        }
    }

    private func recordRunCompletion(ctx: AXProjectContext, assistantText: String) {
        let now = Date().timeIntervalSince1970
        let runID = currentRunId
        withBoundSessionRuntime(ctx: ctx, at: now) { runtime in
            runtime.state = .completed
            runtime.runID = runID ?? runtime.runID
            runtime.startedAt = runtime.startedAt ?? now
            runtime.completedAt = now
            runtime.lastRuntimeSummary = summarizeRuntimeText(assistantText)
            runtime.lastToolBatchIDs = []
            runtime.pendingToolCallCount = 0
            runtime.lastFailureCode = nil
            runtime.resumeToken = nil
            runtime.recoverable = false
        }
        currentRunId = nil
    }

    private func recordRunFailure(ctx: AXProjectContext, message: String) {
        let now = Date().timeIntervalSince1970
        let runID = ensureRunID()
        let failureCode = normalizedFailureCode(message)
        withBoundSessionRuntime(ctx: ctx, at: now) { runtime in
            runtime.state = .failed_recoverable
            runtime.runID = runID
            runtime.startedAt = runtime.startedAt ?? now
            runtime.completedAt = nil
            runtime.lastRuntimeSummary = summarizeRuntimeText(message)
            runtime.pendingToolCallCount = 0
            runtime.lastFailureCode = failureCode
            runtime.resumeToken = runID
            runtime.recoverable = true
        }
        currentRunId = nil
    }

    private func normalizedFailureCode(_ message: String) -> String {
        let lowered = message.lowercased()
        let separators = CharacterSet.alphanumerics.inverted
        let parts = lowered
            .components(separatedBy: separators)
            .filter { !$0.isEmpty }
        if let first = parts.first, first.count >= 3 {
            return first
        }
        return "runtime_error"
    }

    private func persistPendingToolApproval(ctx: AXProjectContext, flow: ToolFlowState, calls: [ToolCall], assistantStub: String, reason: String?) {
        let pid = AXProjectRegistryStore.projectId(forRoot: ctx.root)
        let createdAt = Date().timeIntervalSince1970

        // Keep the persisted blob bounded; it is a recovery hint, not a full audit log (raw_log is the audit log).
        let maxToolResults = 40
        let cappedResults = Array(flow.toolResults.suffix(maxToolResults)).map { r in
            ToolResult(id: r.id, tool: r.tool, ok: r.ok, output: truncateInline(r.output, max: 80_000))
        }

        let state = AXPendingToolFlowState(
            step: flow.step,
            toolResults: cappedResults,
            dirtySinceVerify: flow.dirtySinceVerify,
            verifyRunIndex: flow.verifyRunIndex,
            repairAttemptsUsed: flow.repairAttemptsUsed,
            deferredFinal: flow.deferredFinal,
            finalizeOnly: flow.finalizeOnly,
            formatRetryUsed: flow.formatRetryUsed
        )

        let preview = calls.map { c in
            let keys = c.args.keys.sorted().joined(separator: ",")
            return "\(c.tool.rawValue)(\(keys))"
        }.joined(separator: " ")

        let action = AXPendingAction(
            id: "tool_approval_\(Int(createdAt * 1000))",
            type: .toolApproval,
            createdAt: createdAt,
            status: "pending",
            projectId: pid,
            projectName: ctx.projectName(),
            reason: reason,
            preview: preview.isEmpty ? nil : preview,
            userText: flow.userText,
            assistantStub: assistantStub,
            toolCalls: calls,
            flow: state
        )
        AXPendingActionsStore.saveToolApproval(action, for: ctx)
    }

    private func restorePendingToolApprovalIfAny(ctx: AXProjectContext) {
        guard let pending = AXPendingActionsStore.pendingToolApproval(for: ctx) else { return }
        guard let userText = pending.userText, !userText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let stub = (pending.assistantStub ?? "有待审批的工具操作（本页或 Home 可处理）。").trimmingCharacters(in: .whitespacesAndNewlines)
        let calls = pending.toolCalls ?? []
        guard !calls.isEmpty else { return }
        guard let state = pending.flow else { return }

        // Reconstruct a synthetic tail so the transcript doesn't "lose" the user's last input.
        messages.append(AXChatMessage(role: .user, content: userText, createdAt: pending.createdAt))
        let assistantIndex = messages.count
        messages.append(AXChatMessage(role: .assistant, tag: lastCoderProviderTag.isEmpty ? nil : lastCoderProviderTag, content: stub, createdAt: pending.createdAt))

        let mem = try? AXProjectStore.loadOrCreateMemory(for: ctx)
        let cfg = try? AXProjectStore.loadOrCreateConfig(for: ctx)
        let flow = ToolFlowState(
            ctx: ctx,
            memory: mem,
            config: cfg,
            userText: userText,
            step: state.step,
            toolResults: state.toolResults,
            assistantIndex: assistantIndex,
            dirtySinceVerify: state.dirtySinceVerify,
            verifyRunIndex: state.verifyRunIndex,
            repairAttemptsUsed: state.repairAttemptsUsed,
            deferredFinal: state.deferredFinal,
            finalizeOnly: state.finalizeOnly,
            formatRetryUsed: state.formatRetryUsed
        )

        pendingToolCalls = calls
        pendingFlow = flow
        isSending = false
        currentReqId = nil
        recordAwaitingToolApproval(ctx: ctx, calls: calls, reason: "restored_pending_tool_approval")
    }

    private func truncateInline(_ s: String, max: Int) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.count <= max { return t }
        let idx = t.index(t.startIndex, offsetBy: max)
        return String(t[..<idx]) + "\n\n[x-terminal] truncated"
    }

    func send(ctx: AXProjectContext, memory: AXMemory?, config: AXProjectConfig?, router: LLMRouter) {
        activeRouter = router
        activeConfig = config
        lastCoderProviderTag = shortProviderTag(router.provider(for: .coder).displayName)
        let userText = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !userText.isEmpty else { return }

        draft = ""
        lastError = nil
        isSending = true

        let userCreatedAt = Date().timeIntervalSince1970
        messages.append(AXChatMessage(role: .user, content: userText, createdAt: userCreatedAt))
        // Keep a crash-resilient short-term buffer so prompt assembly doesn't depend on UI state.
        AXRecentContextStore.appendUserMessage(ctx: ctx, text: userText, createdAt: userCreatedAt)
        touchProjectActivity(ctx: ctx, eventAt: userCreatedAt)
        let assistantIndex = messages.count
        messages.append(AXChatMessage(role: .assistant, tag: lastCoderProviderTag, content: ""))

        pendingToolCalls = []
        pendingFlow = nil
        _ = ensurePrimarySessionBound(ctx: ctx)
        recordRunStart(ctx: ctx, userText: userText)

        if handleSlashCommand(
            text: userText,
            ctx: ctx,
            config: config,
            assistantIndex: assistantIndex
        ) {
            return
        }

        if isDirectNetworkRequest(userText) {
            performDirectNetworkRequest(
                ctx: ctx,
                memory: memory,
                config: config,
                userText: userText,
                assistantIndex: assistantIndex,
                seconds: nil
            )
            return
        }

        Task {
            let flow = ToolFlowState(
                ctx: ctx,
                memory: memory,
                config: config,
                userText: userText,
                step: 0,
                toolResults: [],
                assistantIndex: assistantIndex,
                dirtySinceVerify: false,
                verifyRunIndex: 0,
                repairAttemptsUsed: 0,
                deferredFinal: nil,
                finalizeOnly: false,
                formatRetryUsed: false
            )
            await runToolLoop(flow: flow, router: router)
        }
    }

    func approvePendingTools(router: LLMRouter) {
        guard let flow = pendingFlow else { return }
        let calls = pendingToolCalls
        pendingToolCalls = []
        pendingFlow = nil
        AXPendingActionsStore.clearToolApproval(for: flow.ctx)
        activeRouter = router
        activeConfig = flow.config
        isSending = true

        Task {
            let updated = await executeTools(flow: flow, toolCalls: calls)
            await runToolLoop(flow: updated, router: router)
        }
    }

    func rejectPendingTools() {
        guard let flow = pendingFlow else {
            pendingToolCalls = []
            pendingFlow = nil
            isSending = false
            currentReqId = nil
            lastError = nil
            return
        }
        let ctx = flow.ctx
        let userText = flow.userText
        let assistantIndex = flow.assistantIndex

        pendingToolCalls = []
        pendingFlow = nil
        isSending = false
        currentReqId = nil
        AXPendingActionsStore.clearToolApproval(for: ctx)

        // Record the turn so the user's last input isn't silently lost across restart.
        activeConfig = flow.config
        let msg = "已拒绝执行待审批的工具操作。你可以修改要求后再试。"
        finalizeTurn(ctx: ctx, userText: userText, assistantText: msg, assistantIndex: assistantIndex)
    }

    private func runToolLoop(flow initial: ToolFlowState, router: LLMRouter) async {
        let ctx = initial.ctx
        do {
            var flow = initial
            let ctx = flow.ctx
            let memory = flow.memory
            let config = flow.config
            let userText = flow.userText
            let assistantIndex = flow.assistantIndex

            while flow.step < 14 {
                flow.step += 1

                // If we must stop, ask for a final-only summary.
                if flow.finalizeOnly {
                    let prompt = await buildFinalizeOnlyPrompt(
                        ctx: ctx,
                        memory: memory,
                        config: config,
                        userText: userText,
                        toolResults: flow.toolResults
                    )
                    recordAwaitingModel(ctx: ctx, detail: "awaiting finalize_only response")
                    let out = try await llmGenerate(role: .coder, prompt: prompt, router: router)

                    if let json = JSONExtractor.extractFirstJSON(from: out),
                       let env = try? JSONDecoder().decode(ToolActionEnvelope.self, from: Data(json.utf8)),
                       let final = env.final, !final.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        finalizeTurn(ctx: ctx, userText: userText, assistantText: final, assistantIndex: assistantIndex)
                    } else {
                        finalizeTurn(ctx: ctx, userText: userText, assistantText: out, assistantIndex: assistantIndex)
                    }
                    return
                }

                // Auto-run verification before allowing final when we have pending changes.
                if let verifyCalls = nextVerifyCallsIfNeeded(flow: &flow) {
                    // Verification uses run_command so it may require confirmation.
                    var toRun: [ToolCall] = []
                    var toConfirm: [ToolCall] = []
                    for call in verifyCalls {
                        if ToolPolicy.isAlwaysConfirm(call: call) {
                            toConfirm.append(call)
                            continue
                        }
                        switch ToolPolicy.risk(for: call) {
                        case .safe:
                            toRun.append(call)
                        case .needsConfirm, .alwaysConfirm:
                            if autoRunTools {
                                toRun.append(call)
                            } else {
                                toConfirm.append(call)
                            }
                        }
                    }

                    if !toRun.isEmpty {
                        flow = await executeTools(flow: flow, toolCalls: toRun)
                    }
                    if !toConfirm.isEmpty {
                        pendingToolCalls = toConfirm
                        pendingFlow = flow
                        if assistantIndex < messages.count {
                            messages[assistantIndex].content = "有待审批的验证操作（本页或 Home 可处理）。"
                        }
                        persistPendingToolApproval(ctx: ctx, flow: flow, calls: toConfirm, assistantStub: "有待审批的验证操作（本页或 Home 可处理）。", reason: "verify")
                        recordAwaitingToolApproval(ctx: ctx, calls: toConfirm, reason: "awaiting_verify_approval")
                        isSending = false
                        currentReqId = nil
                        return
                    }

                    // Evaluate the verify run (we created ids with verify prefix).
                    let ok = verifyRunOK(flow: flow)
                    if ok {
                        flow.dirtySinceVerify = false
                        if let deferred = flow.deferredFinal, !deferred.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            finalizeTurn(ctx: ctx, userText: userText, assistantText: deferred, assistantIndex: assistantIndex)
                            return
                        }
                    } else {
                        flow.deferredFinal = nil
                        if flow.repairAttemptsUsed < 1 {
                            flow.repairAttemptsUsed += 1
                            // Allow one repair pass by continuing the loop.
                        } else {
                            // Already attempted one repair; stop and ask for summary.
                            flow.finalizeOnly = true
                        }
                    }

                    continue
                }

                recordAwaitingModel(ctx: ctx, detail: "planning_step_\(flow.step)")
                let promptBuild = await buildToolLoopPrompt(
                    ctx: ctx,
                    memory: memory,
                    config: config,
                    userText: userText,
                    toolResults: flow.toolResults
                )
                let prompt = promptBuild.prompt
                let (out, usage) = try await llmGenerateWithUsage(role: .coder, prompt: prompt, router: router)
                // During tool planning, show a short status instead of dumping JSON.
                if assistantIndex < messages.count {
                    messages[assistantIndex].content = "(planning…)"
                }

                // Log usage for the planning step.
                AXProjectStore.appendUsage(
                    [
                        "type": "ai_usage",
                        "created_at": Date().timeIntervalSince1970,
                        "stage": "chat_plan",
                        "role": "coder",
                        "provider": router.provider(for: .coder).displayName,
                        "task_type": router.taskType(for: .coder),
                        "prompt_chars": prompt.count,
                        "output_chars": out.count,
                        "prompt_tokens": usage?.promptTokens as Any,
                        "output_tokens": usage?.completionTokens as Any,
                        "token_source": (usage != nil) ? "provider" : "estimate",
                        "prompt_tokens_est": TokenEstimator.estimateTokens(prompt),
                        "output_tokens_est": TokenEstimator.estimateTokens(out),
                        "memory_v1_source": promptBuild.memory.source,
                        "memory_v1_tokens_est": promptBuild.memory.usedTokens as Any,
                        "memory_v1_budget_tokens": promptBuild.memory.budgetTokens as Any,
                        "memory_v1_truncated_layers": promptBuild.memory.truncatedLayers,
                        "memory_v1_redacted_items": promptBuild.memory.redactedItems as Any,
                        "memory_v1_private_drops": promptBuild.memory.privateDrops as Any,
                        "prompt_compact_mode": true,
                    ],
                    for: ctx
                )

                let env: ToolActionEnvelope
                if let json = JSONExtractor.extractFirstJSON(from: out),
                   let env0 = try? JSONDecoder().decode(ToolActionEnvelope.self, from: Data(json.utf8)) {
                    env = env0
                } else {
                    // The model didn't follow the JSON-only contract (common with local models). Try one repair round.
                    if !flow.formatRetryUsed {
                        flow.formatRetryUsed = true
                        let repaired = try await llmGenerate(role: .coder, prompt: formatRepairPrompt(original: out), router: router)
                        if let json2 = JSONExtractor.extractFirstJSON(from: repaired),
                           let env2 = try? JSONDecoder().decode(ToolActionEnvelope.self, from: Data(json2.utf8)) {
                            env = env2
                        } else {
                            finalizeTurn(ctx: ctx, userText: userText, assistantText: out, assistantIndex: assistantIndex)
                            return
                        }
                    } else {
                        finalizeTurn(ctx: ctx, userText: userText, assistantText: out, assistantIndex: assistantIndex)
                        return
                    }
                }

                if let final = env.final, !final.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    // Gate final behind verification when we have pending changes.
                    if requiresVerify(flow: flow) {
                        flow.deferredFinal = final
                        continue
                    }
                    finalizeTurn(ctx: ctx, userText: userText, assistantText: final, assistantIndex: assistantIndex)
                    return
                }

                let calls = env.tool_calls ?? []
                if calls.isEmpty {
                    finalizeTurn(ctx: ctx, userText: userText, assistantText: "(no action)", assistantIndex: assistantIndex)
                    return
                }

                let toolPolicy = effectiveToolPolicy(config: config)
                var policyAllowedCalls: [ToolCall] = []
                for call in calls {
                    guard toolPolicy.allowed.contains(call.tool) else {
                        let reason = """
tool_blocked_by_policy
profile=\(toolPolicy.profile.rawValue)
tool=\(call.tool.rawValue)
allow=\(toolPolicy.allowTokens.isEmpty ? "(none)" : toolPolicy.allowTokens.joined(separator: ","))
deny=\(toolPolicy.denyTokens.isEmpty ? "(none)" : toolPolicy.denyTokens.joined(separator: ","))
hint=use /tools to inspect or change tool policy
"""
                        let blocked = ToolResult(id: call.id, tool: call.tool, ok: false, output: reason)
                        flow.toolResults.append(blocked)
                        AXProjectStore.appendToolLog(action: call.tool.rawValue, input: jsonArgs(call.args), output: reason, ok: false, for: ctx)
                        messages.append(AXChatMessage(role: .tool, content: "[tool:\(call.tool.rawValue)] ok=false\n\(reason)"))
                        continue
                    }
                    policyAllowedCalls.append(call)
                }
                if policyAllowedCalls.isEmpty {
                    // Let the model continue with the blocked results already appended into tool history.
                    continue
                }

                // Split into safe vs needs-confirm so we can run read/search/diff without prompting.
                var toRun: [ToolCall] = []
                var toConfirm: [ToolCall] = []
                for call in policyAllowedCalls {
                    if ToolPolicy.isAlwaysConfirm(call: call) {
                        toConfirm.append(call)
                        continue
                    }
                    switch ToolPolicy.risk(for: call) {
                    case .safe:
                        toRun.append(call)
                    case .needsConfirm, .alwaysConfirm:
                        if autoRunTools {
                            toRun.append(call)
                        } else {
                            toConfirm.append(call)
                        }
                    }
                }

                if !toRun.isEmpty {
                    flow = await executeTools(flow: flow, toolCalls: toRun)
                }

                if !toConfirm.isEmpty {
                    // If git_apply is pending, run a dry-run check automatically to help the user approve safely.
                    let gitApplyCalls = toConfirm.filter { $0.tool == .git_apply }
                    if !gitApplyCalls.isEmpty {
                        var checkCalls: [ToolCall] = []
                        for c in gitApplyCalls {
                            if case .string(let patch)? = c.args["patch"], !patch.isEmpty {
                                checkCalls.append(ToolCall(id: "check_\(c.id)", tool: .git_apply_check, args: ["patch": .string(patch)]))
                            }
                        }
                        if !checkCalls.isEmpty {
                            flow = await executeTools(flow: flow, toolCalls: checkCalls)
                        }
                    }

                    pendingToolCalls = toConfirm
                    pendingFlow = flow
                    if assistantIndex < messages.count {
                        messages[assistantIndex].content = "有待审批的工具操作（本页或 Home 可处理）。"
                    }
                    persistPendingToolApproval(ctx: ctx, flow: flow, calls: toConfirm, assistantStub: "有待审批的工具操作（本页或 Home 可处理）。", reason: "tools")
                    recordAwaitingToolApproval(ctx: ctx, calls: toConfirm, reason: "awaiting_tool_approval")
                    isSending = false
                    currentReqId = nil
                    return
                }

                // Continue loop with tool results.
            }

            finalizeTurn(ctx: ctx, userText: userText, assistantText: "(stopped: too many tool steps)", assistantIndex: assistantIndex)
        } catch {
            let msg: String
            if let e = error as? LocalizedError, let d = e.errorDescription, !d.isEmpty {
                msg = d
            } else {
                msg = String(describing: error)
            }
            recordRunFailure(ctx: ctx, message: msg)
            lastError = msg
            if let idx = messages.indices.last,
               messages[idx].role == .assistant,
               messages[idx].content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                messages[idx].content = "请求失败：\n\n\(msg)"
            }
            isSending = false
            currentReqId = nil
        }
    }

    private func handleSlashCommand(text: String, ctx: AXProjectContext, config: AXProjectConfig?, assistantIndex: Int) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/") else { return false }

        let body = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
        if body.isEmpty {
            return false
        }

        let tokens = body
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
        guard let headRaw = tokens.first else { return false }
        let head = headRaw.lowercased()

        switch head {
        case "help":
            finalizeTurn(ctx: ctx, userText: text, assistantText: slashHelpText(), assistantIndex: assistantIndex)
            return true
        case "tools":
            let args = Array(tokens.dropFirst())
            let reply = handleSlashTools(args: args, ctx: ctx, config: config)
            finalizeTurn(ctx: ctx, userText: text, assistantText: reply, assistantIndex: assistantIndex)
            return true
        case "models":
            performSlashModels(
                ctx: ctx,
                userText: text,
                config: config,
                assistantIndex: assistantIndex
            )
            return true
        case "model":
            let args = Array(tokens.dropFirst())
            let reply = handleSlashModel(args: args, ctx: ctx, config: config)
            finalizeTurn(ctx: ctx, userText: text, assistantText: reply, assistantIndex: assistantIndex)
            return true
        case "rolemodel":
            let args = Array(tokens.dropFirst())
            let reply = handleSlashRoleModel(args: args, ctx: ctx, config: config)
            finalizeTurn(ctx: ctx, userText: text, assistantText: reply, assistantIndex: assistantIndex)
            return true
        case "hub":
            let args = Array(tokens.dropFirst())
            let reply = handleSlashHub(args: args)
            finalizeTurn(ctx: ctx, userText: text, assistantText: reply, assistantIndex: assistantIndex)
            return true
        case "sandbox":
            let args = Array(tokens.dropFirst())
            if args.first?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "selftest" {
                performSlashSandboxSelfTest(
                    ctx: ctx,
                    userText: text,
                    assistantIndex: assistantIndex
                )
                return true
            }
            let reply = handleSlashSandbox(args: args)
            finalizeTurn(ctx: ctx, userText: text, assistantText: reply, assistantIndex: assistantIndex)
            return true
        case "grant":
            let args = Array(tokens.dropFirst())
            performSlashGrantCommand(
                ctx: ctx,
                userText: text,
                args: args,
                assistantIndex: assistantIndex
            )
            return true
        case "network":
            let arg = tokens.dropFirst().joined(separator: " ")
            let secs = max(60, extractNetworkSeconds(arg) ?? 1800)
            let requestText = "need network \(max(1, secs / 60))m"
            performDirectNetworkRequest(
                ctx: ctx,
                memory: nil,
                config: config,
                userText: requestText,
                assistantIndex: assistantIndex,
                seconds: secs
            )
            return true
        case "clear":
            messages.removeAll()
            isSending = false
            currentReqId = nil
            lastError = nil
            recordRunCompletion(ctx: ctx, assistantText: "conversation_cleared")
            return true
        default:
            // Unknown /command falls back to normal chat text.
            return false
        }
    }

    private func handleSlashModel(args: [String], ctx: AXProjectContext, config: AXProjectConfig?) -> String {
        if args.isEmpty {
            return slashModelsText(config: config)
        }

        let mid = args.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        if mid.isEmpty {
            return slashModelsText(config: config)
        }

        if ["auto", "default", "none", "clear"].contains(mid.lowercased()) {
            guard var cfg = (config ?? (try? AXProjectStore.loadOrCreateConfig(for: ctx))) else {
                return "无法读取 project config，未修改。"
            }
            cfg = cfg.settingModelOverride(role: .coder, modelId: nil)
            activeConfig = cfg
            try? AXProjectStore.saveConfig(cfg, for: ctx)
            return "已清除 coder 的项目级模型覆盖，回退到全局路由。"
        }

        let known = loadedModelsForSlash().contains { $0.id == mid }
        guard var cfg = (config ?? (try? AXProjectStore.loadOrCreateConfig(for: ctx))) else {
            return "无法读取 project config，未修改。"
        }
        cfg = cfg.settingModelOverride(role: .coder, modelId: mid)
        activeConfig = cfg
        try? AXProjectStore.saveConfig(cfg, for: ctx)

        if known {
            return "已将 coder 模型设置为：\(mid)"
        }
        return "已将 coder 模型设置为：\(mid)\n\n注意：Hub 当前 loaded 列表里暂未看到该模型 id，请确认 Hub 端模型已加载。"
    }

    private func handleSlashRoleModel(args: [String], ctx: AXProjectContext, config: AXProjectConfig?) -> String {
        guard args.count >= 2 else {
            return "用法：/rolemodel <coder|coarse|refine|reviewer|advisor> <model_id|auto>"
        }

        guard let role = roleFromSlashToken(args[0]) else {
            return "未知角色：\(args[0])\n可选：coder / coarse / refine / reviewer / advisor"
        }

        let modelArg = args.dropFirst().joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard var cfg = (config ?? (try? AXProjectStore.loadOrCreateConfig(for: ctx))) else {
            return "无法读取 project config，未修改。"
        }

        if ["auto", "default", "none", "clear"].contains(modelArg.lowercased()) {
            cfg = cfg.settingModelOverride(role: role, modelId: nil)
            activeConfig = cfg
            try? AXProjectStore.saveConfig(cfg, for: ctx)
            return "已清除 \(role.rawValue) 的项目级模型覆盖，回退到全局路由。"
        }

        cfg = cfg.settingModelOverride(role: role, modelId: modelArg)
        activeConfig = cfg
        try? AXProjectStore.saveConfig(cfg, for: ctx)
        return "已将 \(role.rawValue) 模型设置为：\(modelArg)"
    }

    private func performSlashModels(
        ctx: AXProjectContext,
        userText: String,
        config: AXProjectConfig?,
        assistantIndex: Int
    ) {
        Task {
            let snapshot = await HubAIClient.shared.loadModelsState()
            let reply = slashModelsText(config: config, snapshot: snapshot)
            finalizeTurn(ctx: ctx, userText: userText, assistantText: reply, assistantIndex: assistantIndex)
        }
    }

    private func handleSlashHub(args: [String]) -> String {
        guard let headRaw = args.first?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !headRaw.isEmpty else {
            return slashHubRouteText()
        }

        switch headRaw {
        case "status", "show", "list":
            return slashHubRouteText()
        case "route":
            guard args.count >= 2 else {
                return slashHubRouteText()
            }
            let rawMode = args[1]
            if rawMode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "selftest" {
                return slashHubRouteSelfTestText()
            }
            guard let mode = HubAIClient.parseTransportModeToken(rawMode) else {
                return "未知 route：\(rawMode)\n可选：auto / grpc / file"
            }
            HubAIClient.setTransportMode(mode)
            return "已设置 Hub 会话通道：\(mode.rawValue)\n\n" + slashHubRouteText()
        default:
            return """
用法：
- /hub route
- /hub route <auto|grpc|file>
- /hub route selftest
"""
        }
    }

    private func slashHubRouteText() -> String {
        let mode = HubAIClient.transportMode()
        let withRemote = HubRouteStateMachine.resolve(mode: mode, hasRemoteProfile: true)
        let withoutRemote = HubRouteStateMachine.resolve(mode: mode, hasRemoteProfile: false)
        let withRemoteBehavior = routeDecisionText(withRemote)
        let withoutRemoteBehavior = routeDecisionText(withoutRemote)
        return """
Hub transport:
- mode: \(mode.rawValue)
- when remote profile exists: \(withRemoteBehavior)
- when remote profile missing: \(withoutRemoteBehavior)

命令：
- /hub route
- /hub route <auto|grpc|file>
- /hub route selftest
"""
    }

    private func slashHubRouteSelfTestText() -> String {
        let checks = HubRouteStateMachine.runSelfChecks()
        let okCount = checks.filter(\.ok).count
        let total = checks.count
        let status = okCount == total ? "PASS" : "FAIL"
        let lines = checks.map { check in
            "- [\(check.ok ? "PASS" : "FAIL")] \(check.name): \(check.detail)"
        }
        return "Hub route selftest: \(status) (\(okCount)/\(total))\n\n" + lines.joined(separator: "\n")
    }

    private func routeDecisionText(_ decision: HubRouteDecision) -> String {
        if decision.preferRemote {
            return decision.allowFileFallback ? "remote first -> fallback file on route failure" : "remote only (no fallback)"
        }
        if decision.requiresRemote {
            return "fail-closed (\(decision.remoteUnavailableReasonCode ?? "remote_unavailable"))"
        }
        return "file IPC only"
    }

    private func handleSlashSandbox(args: [String]) -> String {
        guard let headRaw = args.first?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !headRaw.isEmpty else {
            return slashSandboxText()
        }

        switch headRaw {
        case "show", "status", "list":
            return slashSandboxText()
        case "mode":
            guard args.count >= 2 else {
                return slashSandboxText()
            }
            let token = args[1]
            guard let mode = ToolExecutor.parseSandboxModeToken(token) else {
                return "未知 sandbox mode：\(token)\n可选：host / sandbox"
            }
            ToolExecutor.setSandboxMode(mode)
            return "已设置工具默认执行路径：\(mode.rawValue)\n\n" + slashSandboxText()
        default:
            return """
用法：
- /sandbox
- /sandbox mode <host|sandbox>
- /sandbox selftest
"""
        }
    }

    private func slashSandboxText() -> String {
        let mode = ToolExecutor.sandboxMode()
        let behavior: String
        switch mode {
        case .host:
            behavior = "默认走宿主执行；传 `sandbox=true` 时走沙箱。"
        case .sandbox:
            behavior = "默认走沙箱执行；传 `sandbox=false` 时走宿主。"
        }
        return """
Tool sandbox route:
- mode: \(mode.rawValue)
- behavior: \(behavior)

命令：
- /sandbox
- /sandbox mode <host|sandbox>
- /sandbox selftest
"""
    }

    private func performSlashSandboxSelfTest(
        ctx: AXProjectContext,
        userText: String,
        assistantIndex: Int
    ) {
        Task {
            let previousMode = ToolExecutor.sandboxMode()
            let token = "XTERMINAL_SANDBOX_SELFTEST_TOKEN_\(UUID().uuidString)"
            let tempRoot = FileManager.default.temporaryDirectory
                .appendingPathComponent("xterminal-sandbox-selftest-\(UUID().uuidString)", isDirectory: true)

            defer {
                ToolExecutor.setSandboxMode(previousMode)
                try? FileManager.default.removeItem(at: tempRoot)
            }

            do {
                let srcDir = tempRoot.appendingPathComponent("src", isDirectory: true)
                try FileManager.default.createDirectory(at: srcDir, withIntermediateDirectories: true)
                let file = srcDir.appendingPathComponent("selftest.txt")
                let content = """
                line one
                \(token)
                line three
                """
                guard let data = content.data(using: .utf8) else {
                    throw NSError(domain: "xterminal", code: 1, userInfo: [NSLocalizedDescriptionKey: "selftest content encode failed"])
                }
                try data.write(to: file, options: .atomic)

                let explicitSandboxCall = ToolCall(
                    id: "sandbox_selftest_explicit",
                    tool: .search,
                    args: [
                        "pattern": .string(token),
                        "sandbox": .bool(true),
                    ]
                )
                let explicitSandbox = try await ToolExecutor.execute(call: explicitSandboxCall, projectRoot: tempRoot)
                let explicitSandboxOK = explicitSandbox.ok &&
                    explicitSandbox.output.contains("sandbox: true") &&
                    explicitSandbox.output.contains(token)

                ToolExecutor.setSandboxMode(.sandbox)
                let defaultSandboxCall = ToolCall(
                    id: "sandbox_selftest_default",
                    tool: .search,
                    args: [
                        "pattern": .string(token),
                    ]
                )
                let defaultSandbox = try await ToolExecutor.execute(call: defaultSandboxCall, projectRoot: tempRoot)
                let defaultSandboxOK = defaultSandbox.ok &&
                    defaultSandbox.output.contains("sandbox: true") &&
                    defaultSandbox.output.contains(token)

                let hostOverrideCall = ToolCall(
                    id: "sandbox_selftest_host_override",
                    tool: .search,
                    args: [
                        "pattern": .string(token),
                        "sandbox": .bool(false),
                    ]
                )
                let hostOverride = try await ToolExecutor.execute(call: hostOverrideCall, projectRoot: tempRoot)
                let hostOverrideOK = hostOverride.ok &&
                    !hostOverride.output.contains("sandbox: true") &&
                    hostOverride.output.contains(token)

                try? await SandboxManager.shared.destroySandbox(forProjectRoot: tempRoot)

                let overall = explicitSandboxOK && defaultSandboxOK && hostOverrideOK
                let summary = """
Sandbox selftest \(overall ? "PASS" : "FAIL")
- explicit sandbox=true: \(explicitSandboxOK ? "PASS" : "FAIL")
- default mode=sandbox: \(defaultSandboxOK ? "PASS" : "FAIL")
- explicit sandbox=false override: \(hostOverrideOK ? "PASS" : "FAIL")
"""
                finalizeTurn(ctx: ctx, userText: userText, assistantText: summary, assistantIndex: assistantIndex)
            } catch {
                let msg = String(describing: error)
                let out = "Sandbox selftest FAIL\n- error: \(msg)"
                finalizeTurn(ctx: ctx, userText: userText, assistantText: out, assistantIndex: assistantIndex)
            }
        }
    }

    private func performSlashGrantCommand(
        ctx: AXProjectContext,
        userText: String,
        args: [String],
        assistantIndex: Int
    ) {
        Task {
            let head = args.first?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
            switch head {
            case "", "show", "status", "list":
                let runtime = await ToolExecutor.highRiskGrantRuntimeStatus(projectRoot: ctx.root)
                let reply = """
High-risk grant gate:
- enforced capability: web_fetch (requires args.grant_id)
\(runtime)

命令：
- /grant status
- /grant scan
- /grant selftest
"""
                finalizeTurn(ctx: ctx, userText: userText, assistantText: reply, assistantIndex: assistantIndex)
            case "scan":
                let runtime = await ToolExecutor.highRiskGrantRuntimeStatus(projectRoot: ctx.root)
                let report = ToolExecutor.scanHighRiskGrantBypass(ctx: ctx)
                let scanText = ToolExecutor.formatHighRiskGrantBypassScanReport(report)
                let reply = scanText + "\n\n" + runtime
                finalizeTurn(ctx: ctx, userText: userText, assistantText: reply, assistantIndex: assistantIndex)
            case "selftest":
                let checks = await ToolExecutor.runHighRiskGrantSelfChecks(projectRoot: ctx.root)
                let passCount = checks.filter(\.ok).count
                let total = checks.count
                let status = passCount == total ? "PASS" : "FAIL"
                let lines = checks.map { check in
                    "- [\(check.ok ? "PASS" : "FAIL")] \(check.name): \(check.detail)"
                }
                let scan = ToolExecutor.scanHighRiskGrantBypass(ctx: ctx, maxBytes: 180_000, maxFindings: 8)
                let reply = """
Grant gate selftest: \(status) (\(passCount)/\(total))
\(lines.joined(separator: "\n"))

\(ToolExecutor.formatHighRiskGrantBypassScanReport(scan))
"""
                finalizeTurn(ctx: ctx, userText: userText, assistantText: reply, assistantIndex: assistantIndex)
            default:
                let runtime = await ToolExecutor.highRiskGrantRuntimeStatus(projectRoot: ctx.root)
                let reply = """
用法：
- /grant status
- /grant scan
- /grant selftest

\(runtime)
"""
                finalizeTurn(ctx: ctx, userText: userText, assistantText: reply, assistantIndex: assistantIndex)
            }
        }
    }

    private struct EffectiveToolPolicy {
        var profile: ToolProfile
        var allowTokens: [String]
        var denyTokens: [String]
        var allowed: Set<ToolName>
    }

    private func effectiveToolPolicy(config: AXProjectConfig?) -> EffectiveToolPolicy {
        let profileRaw = config?.toolProfile ?? ToolPolicy.defaultProfile.rawValue
        let allow = ToolPolicy.normalizePolicyTokens(config?.toolAllow ?? [])
        let deny = ToolPolicy.normalizePolicyTokens(config?.toolDeny ?? [])
        let profile = ToolPolicy.parseProfile(profileRaw)
        let allowed = ToolPolicy.effectiveAllowedTools(profileRaw: profile.rawValue, allowTokens: allow, denyTokens: deny)
        return EffectiveToolPolicy(profile: profile, allowTokens: allow, denyTokens: deny, allowed: allowed)
    }

    private func handleSlashTools(args: [String], ctx: AXProjectContext, config: AXProjectConfig?) -> String {
        guard var cfg = (config ?? (try? AXProjectStore.loadOrCreateConfig(for: ctx))) else {
            return "无法读取 project config，未修改。"
        }

        guard let headRaw = args.first?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !headRaw.isEmpty else {
            return slashToolsText(config: cfg)
        }

        switch headRaw {
        case "show", "status", "list":
            return slashToolsText(config: cfg)
        case "reset":
            cfg = cfg.settingToolPolicy(profile: ToolPolicy.defaultProfile.rawValue, allow: [], deny: [])
            activeConfig = cfg
            try? AXProjectStore.saveConfig(cfg, for: ctx)
            return "已重置工具策略为默认（profile=\(ToolPolicy.defaultProfile.rawValue)）。\n\n" + slashToolsText(config: cfg)
        case "profile":
            guard args.count >= 2 else {
                return "用法：/tools profile <\(ToolPolicy.profileOptionsText())>"
            }
            let raw = args[1]
            let profile = ToolPolicy.parseProfile(raw)
            if profile.rawValue != raw.lowercased() {
                return "未知 profile：\(raw)\n可选：\(ToolPolicy.profileOptionsText())"
            }
            cfg = cfg.settingToolPolicy(profile: profile.rawValue)
            activeConfig = cfg
            try? AXProjectStore.saveConfig(cfg, for: ctx)
            return "已设置工具 profile：\(profile.rawValue)\n\n" + slashToolsText(config: cfg)
        case "allow":
            let tokens = normalizedToolPolicyTokens(from: Array(args.dropFirst()))
            cfg = cfg.settingToolPolicy(allow: tokens)
            activeConfig = cfg
            try? AXProjectStore.saveConfig(cfg, for: ctx)
            return "已更新 tools allow。\n\n" + slashToolsText(config: cfg)
        case "deny":
            let tokens = normalizedToolPolicyTokens(from: Array(args.dropFirst()))
            cfg = cfg.settingToolPolicy(deny: tokens)
            activeConfig = cfg
            try? AXProjectStore.saveConfig(cfg, for: ctx)
            return "已更新 tools deny。\n\n" + slashToolsText(config: cfg)
        default:
            return """
用法：
- /tools                         查看当前策略
- /tools profile <minimal|coding|full>
- /tools allow <token...>        token 支持 tool 名称 / group:*
- /tools deny <token...>
- /tools reset
"""
        }
    }

    private func normalizedToolPolicyTokens(from args: [String]) -> [String] {
        let raw = args.joined(separator: " ")
        let parsed = ToolPolicy.parsePolicyTokens(raw)
        return ToolPolicy.normalizePolicyTokens(parsed)
    }

    private func slashToolsText(config: AXProjectConfig?) -> String {
        let policy = effectiveToolPolicy(config: config)
        let allowedTools = ToolPolicy.sortedTools(policy.allowed).map { $0.rawValue }
        let allowedText = allowedTools.isEmpty ? "(none)" : allowedTools.joined(separator: ", ")
        let allowText = policy.allowTokens.isEmpty ? "(none)" : policy.allowTokens.joined(separator: ", ")
        let denyText = policy.denyTokens.isEmpty ? "(none)" : policy.denyTokens.joined(separator: ", ")

        return """
Tool policy:
- profile: \(policy.profile.rawValue)
- allow: \(allowText)
- deny: \(denyText)
- effective tools: \(allowedText)

常用 token：
- group:fs / group:runtime / group:git / group:network
- group:minimal / group:coding / group:full
- all 或 *
"""
    }

    private func performDirectNetworkRequest(
        ctx: AXProjectContext,
        memory: AXMemory?,
        config: AXProjectConfig?,
        userText: String,
        assistantIndex: Int,
        seconds: Int?
    ) {
        Task {
            let reqSeconds = max(60, seconds ?? extractNetworkSeconds(userText) ?? 900)

            var flow = ToolFlowState(
                ctx: ctx,
                memory: memory,
                config: config,
                userText: userText,
                step: 0,
                toolResults: [],
                assistantIndex: assistantIndex,
                dirtySinceVerify: false,
                verifyRunIndex: 0,
                repairAttemptsUsed: 0,
                deferredFinal: nil,
                finalizeOnly: false,
                formatRetryUsed: false
            )

            let call = ToolCall(
                id: "need_network_direct",
                tool: .need_network,
                args: [
                    "seconds": .number(Double(reqSeconds)),
                    "reason": .string(userText),
                ]
            )
            flow = await executeTools(flow: flow, toolCalls: [call])

            let res = flow.toolResults.last(where: { $0.id == call.id })
            let st2 = HubBridgeClient.status()
            if st2.enabled {
                let rem = Int(max(0, st2.enabledUntil - Date().timeIntervalSince1970))
                let mins = max(1, rem / 60)
                let grantHint: String
                if let gid = extractGrantTokenFromOutput(res?.output) {
                    grantHint = "请在后续 web_fetch 里带上 grant_id=\(gid)"
                } else {
                    grantHint = ""
                }
                let msg = grantHint.isEmpty
                    ? "已自动批准/已开启网络，剩余约 \(mins) 分钟。"
                    : "已自动批准/已开启网络，剩余约 \(mins) 分钟。\n\(grantHint)"
                finalizeTurn(ctx: ctx, userText: userText, assistantText: msg, assistantIndex: assistantIndex)
                return
            }

            if let res, !res.ok {
                let msg = "申请联网失败：\n\n" + truncateInline(res.output, max: 800)
                finalizeTurn(ctx: ctx, userText: userText, assistantText: msg, assistantIndex: assistantIndex)
                return
            }

            if let out = res?.output.lowercased(), out.contains("auto_approved") {
                let grantHint: String
                if let gid = extractGrantTokenFromOutput(res?.output) {
                    grantHint = "（grant_id=\(gid)）"
                } else {
                    grantHint = ""
                }
                let msg = "已自动批准\(grantHint)，正在开启网络…"
                finalizeTurn(ctx: ctx, userText: userText, assistantText: msg, assistantIndex: assistantIndex)
                return
            }

            let grantHint: String
            if let gid = extractGrantTokenFromOutput(res?.output) {
                grantHint = "审批后请继续使用 grant_id=\(gid)"
            } else {
                grantHint = ""
            }
            let msg = grantHint.isEmpty
                ? "已向 Flow Hub 申请联网（\(max(1, reqSeconds / 60)) 分钟）。请在 Hub Inbox 审批。"
                : "已向 Flow Hub 申请联网（\(max(1, reqSeconds / 60)) 分钟）。请在 Hub Inbox 审批。\n\(grantHint)"
            finalizeTurn(ctx: ctx, userText: userText, assistantText: msg, assistantIndex: assistantIndex)
        }
    }

    private func loadedModelsForSlash(snapshot: ModelStateSnapshot? = nil) -> [HubModel] {
        let baseSnapshot: ModelStateSnapshot
        if let snapshot {
            baseSnapshot = snapshot
        } else {
            let url = HubPaths.modelsStateURL()
            guard let data = try? Data(contentsOf: url),
                  let decoded = try? JSONDecoder().decode(ModelStateSnapshot.self, from: data) else {
                return []
            }
            baseSnapshot = decoded
        }

        return baseSnapshot.models.filter { $0.state == .loaded }
            .sorted { a, b in
                let an = (a.name.isEmpty ? a.id : a.name).lowercased()
                let bn = (b.name.isEmpty ? b.id : b.name).lowercased()
                if an != bn { return an < bn }
                return a.id.lowercased() < b.id.lowercased()
            }
    }

    private func slashModelsText(config: AXProjectConfig?, snapshot: ModelStateSnapshot? = nil) -> String {
        let current = config?.modelOverride(for: .coder) ?? "(auto route)"
        let models = loadedModelsForSlash(snapshot: snapshot)
        let mode = HubAIClient.transportMode().rawValue
        if models.isEmpty {
            return "当前没有 loaded 模型（transport=\(mode)）。\n\n先去 Hub 端加载模型，再用 `/model <id>` 选择。"
        }

        let lines = models.map { m in
            let remote = isRemoteModelForSlash(m) ? "Remote" : "Local"
            let name = m.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? m.id : m.name
            return "- \(name) · \(m.id) · \(remote) · \(m.backend)"
        }
        return "当前 coder 模型：\(current)\n当前 transport：\(mode)\n\nHub loaded 模型：\n" + lines.joined(separator: "\n")
    }

    private func slashHelpText() -> String {
        """
可用 / 命令：
- /tools                  查看当前工具策略与有效工具
- /tools profile <p>      切换工具 profile（minimal/coding/full）
- /tools allow <tokens>   设置工具 allow（覆盖式）
- /tools deny <tokens>    设置工具 deny（覆盖式）
- /tools reset            重置工具策略为默认
- /hub route              查看 Hub 会话通道（auto/grpc/file）
- /hub route <mode>       设置 Hub 会话通道（mode: auto/grpc/file）
- /hub route selftest     校验 Hub 路由状态机规则（XT-W1-02）
- /sandbox                查看工具默认执行路径（host/sandbox）
- /sandbox mode <mode>    设置工具默认执行路径（mode: host/sandbox）
- /sandbox selftest       执行工具沙箱路径自检（search）
- /grant status           查看高风险 grant gate 状态（XT-W1-04）
- /grant scan             扫描高风险动作旁路执行（XT-W1-04）
- /grant selftest         执行高风险 grant gate 自检（XT-W1-04）
- /models                 查看 Hub 当前 loaded 模型
- /model <id>             设置当前 project 的 coder 模型
- /model auto             清除 coder 项目级覆盖
- /rolemodel <role> <id>  设置某个角色模型（role: coder/coarse/refine/reviewer/advisor）
- /rolemodel <role> auto  清除角色覆盖
- /network 30m            申请联网（也可用 need network 30m）
- /clear                  清空当前页面聊天记录（不删除项目文件）
"""
    }

    private func roleFromSlashToken(_ token: String) -> AXRole? {
        switch token.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "coder": return .coder
        case "coarse": return .coarse
        case "refine": return .refine
        case "reviewer", "review": return .reviewer
        case "advisor": return .advisor
        default: return nil
        }
    }

    private func isRemoteModelForSlash(_ m: HubModel) -> Bool {
        let mp = (m.modelPath ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !mp.isEmpty { return false }
        return m.backend.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() != "mlx"
    }

    private func llmGenerate(role: AXRole, prompt: String, router: LLMRouter) async throws -> String {
        let (t, _) = try await llmGenerateWithUsage(role: role, prompt: prompt, router: router)
        return t
    }

    private func llmGenerateWithUsage(role: AXRole, prompt: String, router: LLMRouter) async throws -> (String, LLMUsage?) {
        let provider = router.provider(for: role)
        let preferredHub = router.preferredModelIdForHub(for: role, projectConfig: activeConfig)
        let projectId = currentProjectIdForLLM()
        let req = LLMRequest(
            role: role,
            messages: [
                LLMMessage(role: "user", content: prompt),
            ],
            maxTokens: 2048,
            temperature: 0.2,
            topP: 0.95,
            taskType: router.taskType(for: role),
            preferredModelId: preferredHub,
            projectId: projectId,
            sessionId: currentSessionIdForLLM()
        )

        var out = ""
        var usage: LLMUsage? = nil
        for try await ev in provider.stream(req) {
            switch ev {
            case .delta(let t):
                out += t
            case .done(_, _, let u):
                usage = u
            }
        }
        return (out, usage)
    }

    private func currentProjectIdForLLM() -> String? {
        guard let root = loadedRootPath else { return nil }
        let url = URL(fileURLWithPath: root, isDirectory: true)
        return AXProjectRegistryStore.projectId(forRoot: url)
    }

    private func currentSessionIdForLLM() -> String? {
        boundSessionId
    }

    private func executeTools(flow: ToolFlowState, toolCalls: [ToolCall]) async -> ToolFlowState {
        var f = flow
        let root = f.ctx.root
        touchProjectActivity(ctx: f.ctx)
        recordRunningTools(ctx: f.ctx, toolCalls: toolCalls)

        messages.append(AXChatMessage(role: .tool, content: "[tools] running \(toolCalls.count) call(s)…"))
        for call in toolCalls {
            var streamId: String? = nil
            var streamHandler: (@MainActor @Sendable (String) -> Void)? = nil
            if call.tool == .run_command {
                let id = startToolStream(call)
                streamId = id
                streamHandler = { [weak self] chunk in
                    guard let self else { return }
                    self.appendToolStream(id: id, chunk: chunk)
                }
            }
            do {
                let res = try await ToolExecutor.execute(call: call, projectRoot: root, stream: streamHandler)
                f.toolResults.append(res)
                AXProjectStore.appendToolLog(action: call.tool.rawValue, input: jsonArgs(call.args), output: res.output, ok: res.ok, for: f.ctx)
                if call.tool == .run_command, let id = streamId {
                    finishToolStream(id: id, result: res)
                } else {
                    messages.append(AXChatMessage(role: .tool, content: "[tool:\(call.tool.rawValue)] ok=\(res.ok)\n\(res.output)"))
                }

                if call.tool == .write_file || call.tool == .git_apply {
                    f.dirtySinceVerify = true
                    if let updated = autoReconcileVerifyCommandsIfNeeded(ctx: f.ctx, config: f.config) {
                        f.config = updated
                        activeConfig = updated
                    }
                }

                // After mutating tools, automatically show git diff (patch-first visibility).
                if (call.tool == .write_file || call.tool == .git_apply), GitTool.isGitRepo(root: root) {
                    if let diffRes = try? GitTool.diff(root: root, cached: false) {
                        let diffText = diffRes.combined.isEmpty ? "(empty diff)" : diffRes.combined
                        let diffTool = ToolResult(id: "auto_diff_after_\(call.id)", tool: .git_diff, ok: diffRes.exitCode == 0, output: diffText)
                        f.toolResults.append(diffTool)
                        AXProjectStore.appendToolLog(action: "git_diff", input: ["auto": true], output: diffText, ok: diffRes.exitCode == 0, for: f.ctx)
                        messages.append(AXChatMessage(role: .tool, content: "[tool:git_diff] ok=\(diffRes.exitCode == 0)\n\(diffText)"))
                    }
                }
            } catch {
                let msg = String(describing: error)
                let res = ToolResult(id: call.id, tool: call.tool, ok: false, output: msg)
                f.toolResults.append(res)
                AXProjectStore.appendToolLog(action: call.tool.rawValue, input: jsonArgs(call.args), output: msg, ok: false, for: f.ctx)
                if call.tool == .run_command, let id = streamId {
                    finishToolStreamWithError(id: id, error: msg)
                } else {
                    messages.append(AXChatMessage(role: .tool, content: "[tool:\(call.tool.rawValue)] ok=false\n\(msg)"))
                }
            }
        }
        return f
    }

    private func autoReconcileVerifyCommandsIfNeeded(ctx: AXProjectContext, config: AXProjectConfig?) -> AXProjectConfig? {
        guard var cfg = config else { return nil }

        var changed = false

        let filtered = AXProjectStackDetector.filterApplicableVerifyCommands(cfg.verifyCommands, forProjectRoot: ctx.root)
        if filtered != cfg.verifyCommands {
            cfg.verifyCommands = filtered
            changed = true
        }

        if cfg.verifyCommands.isEmpty {
            let recommended = AXProjectStackDetector.recommendedVerifyCommands(forProjectRoot: ctx.root)
            if recommended != cfg.verifyCommands {
                cfg.verifyCommands = recommended
                changed = true
            }
        }

        guard changed else { return nil }
        try? AXProjectStore.saveConfig(cfg, for: ctx)
        return cfg
    }

    private func startToolStream(_ call: ToolCall) -> String {
        let header = "[tool:\(call.tool.rawValue)] running..."
        let msg = AXChatMessage(role: .tool, content: header)
        messages.append(msg)
        toolStreamStates[msg.id] = ToolStreamState(header: header, display: "", truncated: false)
        return msg.id
    }

    private func appendToolStream(id: String, chunk: String) {
        guard var st = toolStreamStates[id] else { return }
        st.display += chunk
        if st.display.count > toolStreamMaxChars {
            st.display = String(st.display.suffix(toolStreamMaxChars))
            st.truncated = true
        }
        updateMessage(id: id, content: streamContent(for: st))
        toolStreamStates[id] = st
    }

    private func finishToolStream(id: String, result: ToolResult) {
        let header = "[tool:\(result.tool.rawValue)] ok=\(result.ok)"
        let body = truncateOutput(result.output)
        updateMessage(id: id, content: header + "\n" + body)
        toolStreamStates[id] = nil
    }

    private func finishToolStreamWithError(id: String, error: String) {
        let header = "[tool:run_command] ok=false"
        updateMessage(id: id, content: header + "\n" + error)
        toolStreamStates[id] = nil
    }

    private func updateMessage(id: String, content: String) {
        guard let idx = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[idx].content = content
    }

    private func streamContent(for st: ToolStreamState) -> String {
        let notice = st.truncated ? "[output truncated]\n" : ""
        if st.display.isEmpty {
            return st.header + "\n" + notice
        }
        return st.header + "\n" + notice + st.display
    }

    private func truncateOutput(_ s: String) -> String {
        if s.count <= toolStreamMaxChars { return s }
        let suffix = String(s.suffix(toolStreamMaxChars))
        return "[output truncated]\n" + suffix
    }

    private func requiresVerify(flow: ToolFlowState) -> Bool {
        let cmds = cleanedVerifyCommands(flow.config)
        guard let cfg = flow.config, cfg.verifyAfterChanges, !cmds.isEmpty else { return false }
        return flow.dirtySinceVerify
    }

    private func cleanedVerifyCommands(_ config: AXProjectConfig?) -> [String] {
        guard let config else { return [] }
        return config.verifyCommands
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func nextVerifyCallsIfNeeded(flow: inout ToolFlowState) -> [ToolCall]? {
        if !requiresVerify(flow: flow) { return nil }
        let cmds = cleanedVerifyCommands(flow.config)
        if cmds.isEmpty { return nil }

        flow.verifyRunIndex += 1
        let runId = flow.verifyRunIndex

        var calls: [ToolCall] = []
        for (i, cmd) in cmds.enumerated() {
            let id = "verify\(runId)_cmd\(i + 1)"
            calls.append(
                ToolCall(
                    id: id,
                    tool: .run_command,
                    args: [
                        "command": .string(cmd),
                        "timeout_sec": .number(900),
                    ]
                )
            )
        }
        return calls
    }

    private func verifyRunOK(flow: ToolFlowState) -> Bool {
        let runId = flow.verifyRunIndex
        let prefix = "verify\(runId)_"
        let results = flow.toolResults.filter { $0.id.hasPrefix(prefix) }
        if results.isEmpty { return false }
        return results.allSatisfy { $0.ok }
    }

    private func buildFinalizeOnlyPrompt(
        ctx: AXProjectContext,
        memory: AXMemory?,
        config: AXProjectConfig?,
        userText: String,
        toolResults: [ToolResult]
    ) async -> String {
        let base = await buildToolLoopPrompt(
            ctx: ctx,
            memory: memory,
            config: config,
            userText: userText,
            toolResults: toolResults
        ).prompt
        return base + "\n\nFINALIZE ONLY:\n- Verification is still failing after one auto-repair attempt.\n- Do NOT call tools. Output {\"final\": ...} only.\n- Include: what failed, likely cause, and the next 1-3 actions for the user.\n"
    }

    private func formatRepairPrompt(original: String) -> String {
        """
You produced output that is not valid JSON.

Return ONLY one valid JSON object in this exact schema:
- If you need tools: {"tool_calls":[{"id":"1","tool":"need_network","args":{"seconds":900}}]}
- If done: {"final":"..."}

If the user request requires file changes, prefer tool_calls (create/edit files) over returning a plan in final.

Do NOT use single quotes.
Do NOT include markdown.
Do NOT include extra keys.

Original output:
\(original)
"""
    }

    private func finalizeTurn(ctx: AXProjectContext, userText: String, assistantText: String, assistantIndex: Int) {
        if assistantIndex < messages.count {
            messages[assistantIndex].content = assistantText
        }

        let createdAt = Date().timeIntervalSince1970
        AXRecentContextStore.appendAssistantMessage(ctx: ctx, text: assistantText, createdAt: createdAt)
        touchProjectActivity(ctx: ctx, eventAt: createdAt)

        let turn = AXConversationTurn(createdAt: createdAt, user: userText, assistant: assistantText)
        AXProjectStore.appendRawLog(
            ["type": "turn", "created_at": turn.createdAt, "user": turn.user, "assistant": turn.assistant],
            for: ctx
        )

        recordRunCompletion(ctx: ctx, assistantText: assistantText)
        isSending = false
        currentReqId = nil

        let router = activeRouter
        Task {
            do {
                _ = try await AXMemoryPipeline.updateMemory(ctx: ctx, turn: turn, projectConfig: activeConfig, router: router)
            } catch {
                await MainActor.run {
                    self.lastError = "memory_update_failed: \(String(describing: error))"
                }
            }
        }
    }

    private func touchProjectActivity(ctx: AXProjectContext, eventAt: Double? = nil) {
        let update = AXProjectRegistryStore.touchActivity(forRoot: ctx.root, eventAt: eventAt, minIntervalSec: 2.0)
        guard update.changed, let entry = update.entry else { return }
        HubIPCClient.syncProject(entry)
    }

    private func shortProviderTag(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.localizedCaseInsensitiveContains("hub") { return "Hub" }
        if t.localizedCaseInsensitiveContains("anthropic") || t.localizedCaseInsensitiveContains("claude") { return "Claude" }
        if t.localizedCaseInsensitiveContains("gemini") { return "Gemini" }
        if t.localizedCaseInsensitiveContains("openai") { return "OpenAI" }
        if t.localizedCaseInsensitiveContains("compatible") { return "API" }
        return t.isEmpty ? "" : t
    }

    private func isDirectNetworkRequest(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if t.isEmpty { return false }
        if t == "need network" || t == "联网" { return true }
        if t.hasPrefix("need network") { return true }
        if t.hasPrefix("需要联网") || t.hasPrefix("请求联网") || t.hasPrefix("打开网络") || t.hasPrefix("开启网络") { return true }
        return false
    }

    private func extractNetworkSeconds(_ text: String) -> Int? {
        let t = text.lowercased()
        let patterns: [(String, Int)] = [
            ("(\\d+)\\s*(分钟|min|m)", 60),
            ("(\\d+)\\s*(小时|hr|h)", 3600),
        ]
        for (pat, mul) in patterns {
            if let r = try? NSRegularExpression(pattern: pat, options: []) {
                let range = NSRange(t.startIndex..<t.endIndex, in: t)
                if let m = r.firstMatch(in: t, options: [], range: range),
                   m.numberOfRanges > 1,
                   let r1 = Range(m.range(at: 1), in: t) {
                    if let v = Int(t[r1]) {
                        return max(60, v * mul)
                    }
                }
            }
        }
        return nil
    }

    private func extractGrantTokenFromOutput(_ output: String?) -> String? {
        let text = (output ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        guard let regex = try? NSRegularExpression(pattern: #"grant=([A-Za-z0-9_\-]+)"#) else { return nil }
        let ns = text as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges >= 2 else {
            return nil
        }
        let r = match.range(at: 1)
        guard r.location != NSNotFound else { return nil }
        let token = ns.substring(with: r).trimmingCharacters(in: .whitespacesAndNewlines)
        return token.isEmpty ? nil : token
    }

    private func buildCoderPrompt(ctx: AXProjectContext, memory: AXMemory?, userText: String) -> String {
        var memText = ""
        if let memory {
            memText = AXMemoryMarkdown.render(memory)
        } else if FileManager.default.fileExists(atPath: ctx.memoryMarkdownURL.path) {
            memText = (try? String(contentsOf: ctx.memoryMarkdownURL, encoding: .utf8)) ?? ""
        }

        // Keep it simple for MVP (single-turn). We'll move to structured multi-message prompting later.
        return """
[X_TERMINAL_CONTEXT]
Project root: \(ctx.root.path)

[X_TERMINAL_MEMORY]
\(memText)
[/X_TERMINAL_MEMORY]

[USER_REQUEST]
\(userText)
[/USER_REQUEST]

Instructions:
- Give a direct, actionable response.
- When suggesting file changes, mention paths and what to change.
- If you need more info, ask targeted questions.
"""
    }

    private func buildToolLoopPrompt(
        ctx: AXProjectContext,
        memory: AXMemory?,
        userText: String,
        toolResults: [ToolResult]
    ) async -> PromptBuildOutput {
        return await buildToolLoopPrompt(
            ctx: ctx,
            memory: memory,
            config: nil,
            userText: userText,
            toolResults: toolResults
        )
    }

    private func buildToolLoopPrompt(
        ctx: AXProjectContext,
        memory: AXMemory?,
        config: AXProjectConfig?,
        userText: String,
        toolResults: [ToolResult]
    ) async -> PromptBuildOutput {
        var memText = ""
        if let memory {
            memText = AXMemoryMarkdown.render(memory)
        } else if FileManager.default.fileExists(atPath: ctx.memoryMarkdownURL.path) {
            memText = (try? String(contentsOf: ctx.memoryMarkdownURL, encoding: .utf8)) ?? ""
        }

        let stack = AXProjectStackDetector.detect(forProjectRoot: ctx.root)
        let stackText = "swift=\(stack.swiftPackage) node=\(stack.node) python=\(stack.python) rust=\(stack.rust) go=\(stack.go) dotnet=\(stack.dotnet) maven=\(stack.maven) gradle=\(stack.gradle)"

        let shouldExpand = expandRecentOnceAfterLoad || shouldExpandRecent(userText)
        // Reset after first use to keep steady-state prompts compact.
        if expandRecentOnceAfterLoad {
            expandRecentOnceAfterLoad = false
        }
        let recentTurns = shouldExpand ? 12 : 4
        let recentText = recentConversationForPrompt(ctx: ctx, userText: userText, maxTurns: recentTurns)
        let memoryInfo = await buildProjectMemoryV1ViaHub(
            ctx: ctx,
            canonicalMemory: memText,
            recentText: recentText,
            toolResults: toolResults,
            userText: userText
        )
        let memoryV1 = memoryInfo.text
        let toolPolicy = effectiveToolPolicy(config: config)
        let allowedTools = toolPolicy.allowed
        let toolList: String = {
            let items = ToolPolicy.sortedTools(allowedTools).map { ToolPolicy.toolSpec($0) }
            if items.isEmpty { return "(none)" }
            return items.joined(separator: "\n")
        }()
        let networkAllowed = allowedTools.contains(.need_network) && (allowedTools.contains(.web_fetch) || allowedTools.contains(.web_search) || allowedTools.contains(.browser_read))
        let networkingGuidance: String = {
            if networkAllowed {
                return """
Networking (IMPORTANT):
- If the user asks for live web data (prices, availability, current events, official docs), you MUST request network access first:
  {"tool_calls":[{"tool":"need_network","args":{"seconds":900}}]}
- If you can answer offline, do not request network.

Practical rule:
- For travel planning / "攻略" requests, you should request network first unless the user explicitly says "offline is OK".
- After need_network succeeds, extract grant id from tool output (`grant=...`) and call `web_fetch`, `web_search`, or `browser_read` with `args.grant_id`.
- Examples:
  {"tool_calls":[{"tool":"web_search","args":{"query":"OpenAI API pricing","grant_id":"<grant-id>"}}]}
  {"tool_calls":[{"tool":"browser_read","args":{"url":"https://example.com","grant_id":"<grant-id>"}}]}
- Any `web_fetch` / `web_search` / `browser_read` call without `grant_id` will be denied by the runtime security gate.
"""
            }
            return """
Networking:
- Network tools are currently disabled by tool policy. Do not emit `need_network`, `web_fetch`, `web_search`, or `browser_read`.
- If live web data is required, explain that network capability must be enabled first.
"""
        }()

        let toolHistory: String = {
            if toolResults.isEmpty { return "(none)" }
            return toolResults.map { r in
                let head = "id=\(r.id) tool=\(r.tool.rawValue) ok=\(r.ok)"
                var body = r.output
                // Keep verify output compact to avoid drowning context.
                if r.id.hasPrefix("verify") {
                    body = tailLines(body, maxLines: 120)
                }
                if body.count > 6000 {
                    body = String(body.prefix(6000)) + "\n[truncated]"
                }
                return head + "\n" + body
            }.joined(separator: "\n\n")
        }()

        let verifyText: String = {
            guard let config, config.verifyAfterChanges else { return "(disabled)" }
            let cmds = config.verifyCommands.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            if cmds.isEmpty { return "(not configured)" }
            return cmds.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        }()

        let prompt = """
You are X-Terminal.

Context:
- Project root: \(ctx.root.path)

Memory v1 (5-layer, compact):
\(memoryV1)

Detected stacks (root markers):
\(stackText)

Available tools:
\(toolList)

Project verify commands (run after changes before final):
\(verifyText)

Tool policy:
- profile=\(toolPolicy.profile.rawValue)
- allow=\(toolPolicy.allowTokens.isEmpty ? "(none)" : toolPolicy.allowTokens.joined(separator: ","))
- deny=\(toolPolicy.denyTokens.isEmpty ? "(none)" : toolPolicy.denyTokens.joined(separator: ","))
- Tools outside this allowlist will be rejected by runtime.

Patch-first workflow (IMPORTANT):
- Prefer producing a unified diff and using git_apply_check + git_apply for edits.
- Avoid write_file for modifying existing files when the project is a git repo.
- For new files, you may use write_file (still requires confirmation).
- If no stack is detected yet and the user asks to build something, choose a stack and scaffold minimal runnable files first (e.g., web: index.html; python: main.py; node: package.json; swift: Package.swift).
- After applying changes, use git_diff to show what changed before returning final.
- If verify commands are configured, run them (run_command) after changes and include output.

\(networkingGuidance)

Tool results so far:
\(toolHistory)

User request:
\(userText)

Response rules (STRICT):
- Output ONLY valid JSON.
- If you need to use tools, output:
  {"tool_calls":[{"id":"1","tool":"read_file","args":{"path":"..."}}]}
- If you are done, output:
  {"final":"..."}
- Do not include markdown. Do not include extra keys.
"""
        return PromptBuildOutput(prompt: prompt, memory: memoryInfo)
    }

    private func shouldExpandRecent(_ userText: String) -> Bool {
        let t = userText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if t.isEmpty { return false }
        let signals = [
            "这个", "上面", "刚刚", "同上", "之前", "前面", "继续", "按之前", "按上面", "那个", "如前",
            "same as", "as above", "previous", "earlier"
        ]
        return signals.contains(where: { t.contains($0) })
    }

    private func recentConversationForPrompt(ctx: AXProjectContext, userText: String, maxTurns: Int) -> String {
        guard maxTurns > 0 else { return "(disabled)" }

        // Prefer crash-resilient recent context stored on disk. Fall back to in-memory UI state if missing.
        var hist: [(String, String)] = [] // (role, content)
        let recent = AXRecentContextStore.load(for: ctx)
        if !recent.messages.isEmpty {
            hist = recent.messages.compactMap { m in
                let r = m.role.trimmingCharacters(in: .whitespacesAndNewlines)
                if r != "user" && r != "assistant" { return nil }
                return (r, m.content)
            }
        } else {
            hist = messages
                .filter { $0.role == .user || $0.role == .assistant }
                .map { ($0.role == .user ? "user" : "assistant", $0.content) }
        }

        // Drop the current user message (already included separately in the prompt).
        if let last = hist.last, last.0 == "user" {
            let t = last.1.trimmingCharacters(in: .whitespacesAndNewlines)
            let u = userText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !u.isEmpty, t == u {
                hist.removeLast()
            }
        }

        let maxMsgs = max(2, maxTurns * 2)
        let slice = hist.suffix(maxMsgs)
        if slice.isEmpty { return "(none)" }

        func truncateBlock(_ s: String, maxChars: Int) -> String {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.count <= maxChars { return t }
            let idx = t.index(t.startIndex, offsetBy: maxChars)
            return String(t[..<idx]) + "…"
        }

        return slice.map { (role, content) in
            "\(role): \(truncateBlock(content, maxChars: 900))"
        }.joined(separator: "\n")
    }

    private func buildProjectMemoryV1Block(
        ctx: AXProjectContext,
        canonicalMemory: String,
        recentText: String,
        toolResults: [ToolResult],
        userText: String
    ) -> String {
        let constitution = constitutionOneLinerForMemoryV1(userText: userText)
        let canonical = cappedForMemoryV1(canonicalMemory, maxChars: 2800)
        let observations = cappedForMemoryV1(projectObservationDigest(ctx: ctx), maxChars: 900)
        let working = cappedForMemoryV1(recentText, maxChars: 1600)
        let rawEvidence = cappedForMemoryV1(toolEvidenceForMemoryV1(toolResults), maxChars: 1400)
        let latestUser = cappedForMemoryV1(userText, maxChars: 350)

        return """
[MEMORY_V1]
[L0_CONSTITUTION]
\(constitution)
[/L0_CONSTITUTION]

[L1_CANONICAL]
\(canonical.isEmpty ? "(none)" : canonical)
[/L1_CANONICAL]

[L2_OBSERVATIONS]
\(observations.isEmpty ? "(none)" : observations)
[/L2_OBSERVATIONS]

[L3_WORKING_SET]
\(working.isEmpty ? "(none)" : working)
[/L3_WORKING_SET]

[L4_RAW_EVIDENCE]
tool_results:
\(rawEvidence.isEmpty ? "(none)" : rawEvidence)
latest_user:
\(latestUser)
[/L4_RAW_EVIDENCE]
[/MEMORY_V1]
"""
    }

    private func buildProjectMemoryV1ViaHub(
        ctx: AXProjectContext,
        canonicalMemory: String,
        recentText: String,
        toolResults: [ToolResult],
        userText: String
    ) async -> MemoryV1BuildInfo {
        let local = buildProjectMemoryV1Block(
            ctx: ctx,
            canonicalMemory: canonicalMemory,
            recentText: recentText,
            toolResults: toolResults,
            userText: userText
        )

        let observationsText = projectObservationDigest(ctx: ctx)
        let rawEvidence = toolEvidenceForMemoryV1(toolResults)
        let projectId = AXProjectRegistryStore.projectId(forRoot: ctx.root)
        let reg = AXProjectRegistryStore.load()
        let displayName = reg.projects.first(where: { $0.projectId == projectId })?.displayName ?? ctx.root.lastPathComponent
        let constitutionHint = constitutionOneLinerForMemoryV1(userText: userText)

        let hubMemory = await HubIPCClient.requestMemoryContext(
            mode: "project",
            projectId: projectId,
            projectRoot: ctx.root.path,
            displayName: displayName,
            latestUser: userText,
            constitutionHint: constitutionHint,
            canonicalText: canonicalMemory,
            observationsText: observationsText,
            workingSetText: recentText,
            rawEvidenceText: rawEvidence,
            budgets: nil,
            timeoutSec: 1.2
        )
        if let hubMemory {
            let source = hubMemory.source.trimmingCharacters(in: .whitespacesAndNewlines)
            return MemoryV1BuildInfo(
                text: hubMemory.text,
                source: source.isEmpty ? "hub_memory_v1" : source,
                usedTokens: hubMemory.usedTotalTokens,
                budgetTokens: hubMemory.budgetTotalTokens,
                truncatedLayers: hubMemory.truncatedLayers,
                redactedItems: hubMemory.redactedItems,
                privateDrops: hubMemory.privateDrops
            )
        }

        return MemoryV1BuildInfo(
            text: local,
            source: "local_fallback",
            usedTokens: TokenEstimator.estimateTokens(local),
            budgetTokens: nil,
            truncatedLayers: [],
            redactedItems: nil,
            privateDrops: nil
        )
    }

    private func constitutionOneLinerForMemoryV1(userText: String) -> String {
        // For normal coding/creative asks, keep L0 concise and execution-oriented
        // so the model doesn't over-index on policy wording.
        if shouldUseConciseConstitutionForLowRiskRequest(userText) {
            return "优先给出可执行答案；保持真实透明并保护隐私。"
        }

        let fallback = "真实透明、最小化外发；仅在高风险或不可逆动作时先解释后执行；普通编程/创作请求直接给出可执行答案。"
        let url = HubPaths.baseDir()
            .appendingPathComponent("memory", isDirectory: true)
            .appendingPathComponent("ax_constitution.json")
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let one = obj["one_liner"] as? [String: Any] else {
            return fallback
        }

        let zh = (one["zh"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !zh.isEmpty { return normalizedConstitutionOneLinerForMemoryV1(zh) }
        let en = (one["en"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !en.isEmpty { return normalizedConstitutionOneLinerForMemoryV1(en) }
        return fallback
    }

    private func normalizedConstitutionOneLinerForMemoryV1(_ raw: String) -> String {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else {
            return "真实透明、最小化外发；仅在高风险或不可逆动作时先解释后执行；普通编程/创作请求直接给出可执行答案。"
        }

        let legacy = "真实透明、最小化外发、关键风险先解释后执行。"
        var out = t
        if out == legacy {
            out = "真实透明、最小化外发；仅在高风险或不可逆动作时先解释后执行；普通编程/创作请求直接给出可执行答案。"
        }

        let lower = out.lowercased()
        let zhRiskFocused =
            out.contains("高风险") ||
            out.contains("合规") ||
            out.contains("法律") ||
            out.contains("隐私") ||
            out.contains("安全") ||
            out.contains("伤害") ||
            out.contains("必要时拒绝") ||
            out.contains("关键风险先解释后执行")
        let enRiskFocused =
            lower.contains("high-risk") ||
            lower.contains("compliance") ||
            lower.contains("legal") ||
            lower.contains("privacy") ||
            lower.contains("safety") ||
            lower.contains("harm") ||
            lower.contains("refuse")

        let zhHasCarveout =
            out.contains("仅在高风险") ||
            out.contains("低风险") ||
            out.contains("普通编程") ||
            out.contains("普通创作") ||
            out.contains("普通请求") ||
            out.contains("直接给出可执行答案") ||
            out.contains("直接回答")
        let enHasCarveout =
            lower.contains("only for high-risk") ||
            lower.contains("normal coding") ||
            lower.contains("creative requests") ||
            lower.contains("respond directly") ||
            lower.contains("answer normal")

        if zhRiskFocused && !zhHasCarveout {
            return out + " 仅在高风险或不可逆动作时先解释后执行；普通编程/创作请求直接给出可执行答案。"
        }
        if enRiskFocused && !enHasCarveout {
            return out + " Explain first only for high-risk or irreversible actions; answer normal coding/creative requests directly."
        }
        return out
    }

    private func shouldUseConciseConstitutionForLowRiskRequest(_ userText: String) -> Bool {
        let t = userText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if t.isEmpty { return false }

        let codingSignals = [
            "写一个", "写个", "代码", "程序", "脚本", "函数", "类", "项目", "网页", "网站", "游戏", "赛车游戏",
            "write", "code", "script", "function", "class", "build", "create", "game", "app", "web"
        ]
        let riskSignals = [
            "绕过", "规避", "破解", "入侵", "提权", "钓鱼", "木马", "勒索", "盗号", "删日志",
            "违法", "犯罪", "武器", "爆炸", "毒品", "未成年人", "自杀", "自残", "伤害", "暴力",
            "法律", "合规", "隐私", "保密", "风险", "后果",
            "bypass", "circumvent", "hack", "exploit", "privilege escalation", "phishing", "malware", "ransomware",
            "illegal", "weapon", "explosive", "drugs", "minor", "suicide", "self-harm", "violence",
            "legal", "compliance", "privacy", "risk", "consequence"
        ]
        let hasCoding = codingSignals.contains(where: { t.contains($0) })
        let hasRisk = riskSignals.contains(where: { t.contains($0) })
        return hasCoding && !hasRisk
    }

    private func projectObservationDigest(ctx: AXProjectContext) -> String {
        let pid = AXProjectRegistryStore.projectId(forRoot: ctx.root)
        let reg = AXProjectRegistryStore.load()
        guard let p = reg.projects.first(where: { $0.projectId == pid }) else {
            return ""
        }
        let state = (p.currentStateSummary ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let next = (p.nextStepSummary ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let blocker = (p.blockerSummary ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let digest = (p.statusDigest ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        return """
project: \(p.displayName)
status: \(digest.isEmpty ? "(none)" : digest)
current: \(state.isEmpty ? "(none)" : state)
next: \(next.isEmpty ? "(none)" : next)
blocker: \(blocker.isEmpty ? "(none)" : blocker)
"""
    }

    private func toolEvidenceForMemoryV1(_ toolResults: [ToolResult]) -> String {
        guard !toolResults.isEmpty else { return "" }
        return toolResults.suffix(6).map { r in
            let out = cappedForMemoryV1(r.output, maxChars: 260)
            return "id=\(r.id) tool=\(r.tool.rawValue) ok=\(r.ok)\n\(out)"
        }.joined(separator: "\n\n")
    }

    private func cappedForMemoryV1(_ text: String, maxChars: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxChars else { return trimmed }
        let idx = trimmed.index(trimmed.startIndex, offsetBy: maxChars)
        return String(trimmed[..<idx]) + "…"
    }

    private func tailLines(_ s: String, maxLines: Int) -> String {
        let n = max(1, maxLines)
        let lines = s.split(separator: "\n", omittingEmptySubsequences: false)
        if lines.count <= n {
            return s
        }
        let tail = lines.suffix(n).joined(separator: "\n")
        return "[x-terminal] showing last \(n) lines of verify output\n" + tail
    }

    private func jsonArgs(_ args: [String: JSONValue]) -> [String: Any] {
        var out: [String: Any] = [:]
        for (k, v) in args {
            out[k] = jsonValueToAny(v)
        }
        return out
    }

    private func jsonValueToAny(_ v: JSONValue) -> Any {
        switch v {
        case .string(let s): return s
        case .number(let n): return n
        case .bool(let b): return b
        case .null: return NSNull()
        case .array(let a): return a.map { jsonValueToAny($0) }
        case .object(let o):
            var out: [String: Any] = [:]
            for (k, vv) in o { out[k] = jsonValueToAny(vv) }
            return out
        }
    }
}
