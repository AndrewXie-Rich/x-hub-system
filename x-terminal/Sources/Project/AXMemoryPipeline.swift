import Foundation

struct AXConversationTurn: Codable, Equatable {
    var createdAt: Double
    var user: String
    var assistant: String
}

enum AXMemoryPipeline {
    static func updateMemory(
        ctx: AXProjectContext,
        turn: AXConversationTurn,
        projectConfig: AXProjectConfig? = nil,
        preferredModelId: String? = nil,
        router: LLMRouter? = nil
    ) async throws -> AXMemory {
        let memUpdateStartedAt = Date().timeIntervalSince1970
        do {
            let mem = try await updateMemoryImplInner(
                ctx: ctx,
                turn: turn,
                projectConfig: projectConfig,
                preferredModelId: preferredModelId,
                router: router
            )
            return mem
        } catch {
            AXProjectStore.appendRawLog(
                [
                    "type": "memory_update",
                    "phase": "failed",
                    "created_at": Date().timeIntervalSince1970,
                    "elapsed_ms": Int((Date().timeIntervalSince1970 - memUpdateStartedAt) * 1000),
                    "error": String(describing: error),
                ],
                for: ctx
            )

            // Fallback: apply a minimal deterministic merge so memory still updates.
            let existing = try AXProjectStore.loadOrCreateMemory(for: ctx)
            let delta = fallbackDelta(existing: existing, turn: turn)
            // Keep vault/candidates working even when the AI memory update fails (e.g. Hub offline).
            AXForgottenVault.autoArchiveTurn(ctx: ctx, turn: turn, delta: delta)
            let candidates = AXSkillCandidateDetector.detect(turn: turn, delta: delta, ctx: ctx, source: "event_fallback")
            _ = AXSkillCandidateStore.appendCandidates(candidates, for: ctx)
            AXSkillAutoPromoter.maybeAutoPromote(ctx: ctx, detected: candidates)

            var merged = applyDelta(delta, to: existing)
            seedIfEmpty(&merged, userText: turn.user.trimmingCharacters(in: .whitespacesAndNewlines))
            merged = AXMemoryModulePrefixer.normalizeIfNeeded(merged, projectRoot: ctx.root)
            try AXProjectStore.saveMemory(merged, for: ctx)
            AXProjectStore.appendRawLog(
                [
                    "type": "memory_update",
                    "phase": "done_fallback_runtime",
                    "created_at": Date().timeIntervalSince1970,
                ],
                for: ctx
            )
            _ = AXMemoryLifecycleStore.recordAfterTurn(
                ctx: ctx,
                turn: turn,
                beforeMemory: existing,
                observationDelta: delta,
                afterMemory: merged,
                pipelineSource: "runtime_fallback"
            )
            return merged
        }
    }

    static func coarsePrompt(turn: AXConversationTurn) -> String {
        // Strict JSON output only. Keep items short and useful.
        return """
You are X-Terminal Coarse Filter. Your job is to extract ONLY durable project memory updates.

Input (one turn):
- user: \(turn.user)
- assistant: \(turn.assistant)

Output rules (STRICT):
- Output ONE valid JSON object ONLY. No markdown. No extra text.
- Follow this schema exactly (all keys must exist):
{
  "schemaVersion": 1,
  "goalUpdate": string|null,
  "requirementsAdd": [string],
  "currentStateAdd": [string],
  "decisionsAdd": [string],
  "nextStepsAdd": [string],
  "openQuestionsAdd": [string],
  "risksAdd": [string],
  "recommendationsAdd": [string],
  "requirementsRemove": [string],
  "currentStateRemove": [string],
  "nextStepsRemove": [string],
  "openQuestionsRemove": [string],
  "risksRemove": [string]
}

Guidelines:
- Prefer short bullet-like strings, each self-contained.
- Skip transient chatter, retries, errors.
- Always capture the user's explicit request as a requirement (unless it's clearly out-of-scope or already present).
- If nothing to add, return empty arrays and null goalUpdate.
- Monorepo / multi-module projects: if an item clearly belongs to a module/subproject, prefix it with a stable module label, e.g. `Hub:` / `Coder:` / `System:` / `Shared:`. If unsure, use `System:`.
"""
    }

    static func refinePrompt(existingMemoryJSON: String, deltaJSON: String) -> String {
        return """
You are X-Terminal Refiner. Merge the delta into the current project memory.

Current memory JSON:
\(existingMemoryJSON)

Delta JSON:
\(deltaJSON)

Output rules (STRICT):
- Output ONE valid JSON object ONLY. No markdown. No extra text.
- Must match AXMemory schema exactly:
{
  "schemaVersion": 1,
  "projectName": string,
  "projectRoot": string,
  "goal": string,
  "requirements": [string],
  "currentState": [string],
  "decisions": [string],
  "nextSteps": [string],
  "openQuestions": [string],
  "risks": [string],
  "recommendations": [string],
  "updatedAt": number
}

Merge rules:
- Apply *Remove lists* first, then Add lists.
- De-duplicate strings (case-insensitive, trim whitespace).
- Keep lists compact: remove near-duplicates.
- Keep the memory short and high-signal.
- Preserve projectName/projectRoot.
- Set updatedAt to the current unix timestamp (seconds).
- Monorepo / multi-module: preserve module prefixes (e.g. `Hub:`/`Coder:`/`System:`/`Shared:`) and prefer adding a prefix when a new item is clearly attributable.
"""
    }

    // updateMemoryImpl removed; updateMemory now handles logging + fallback.

    private static func updateMemoryImplInner(
        ctx: AXProjectContext,
        turn: AXConversationTurn,
        projectConfig: AXProjectConfig? = nil,
        preferredModelId: String? = nil,
        router: LLMRouter? = nil
    ) async throws -> AXMemory {
        AXProjectStore.appendRawLog(
            [
                "type": "memory_update",
                "phase": "start",
                "created_at": Date().timeIntervalSince1970,
            ],
            for: ctx
        )

        let existing = try AXProjectStore.loadOrCreateMemory(for: ctx)
        let projectId = AXProjectRegistryStore.projectId(forRoot: ctx.root)
        async let routeSnapshotTask = HubAIClient.shared.loadModelsState()
        async let localSnapshotTask = HubAIClient.shared.loadModelsState(transportOverride: .fileIPC)
        let routeSnapshot = await routeSnapshotTask
        let localSnapshot = await localSnapshotTask
        var deltaSource = "coarse_model_json"

        // Coarse filter.
        let coarsePromptText = coarsePrompt(turn: turn)
        NotificationCenter.default.post(name: AXMemoryPipelineNotifications.coarseStart, object: nil)
        defer { NotificationCenter.default.post(name: AXMemoryPipelineNotifications.coarseEnd, object: nil) }

        let coarseText: String
        let coarseUsage: LLMUsage?
        let coarseRouteDecision: AXProjectPreferredModelRouteDecision
        if let router {
            let provider = await router.provider(for: .coarse)
            let preferredHub = await router.preferredModelIdForHub(for: .coarse, projectConfig: projectConfig)
            coarseRouteDecision = AXProjectModelRouteMemoryStore.resolvePreferredModel(
                configuredModelId: preferredHub ?? preferredModelId,
                role: .coarse,
                ctx: ctx,
                snapshot: routeSnapshot,
                localSnapshot: localSnapshot
            )
            let taskType = router.taskType(for: .coarse)
            let req = LLMRequest(
                role: .coarse,
                messages: [LLMMessage(role: "user", content: coarsePromptText)],
                maxTokens: 768,
                temperature: 0.1,
                topP: 0.95,
                taskType: taskType,
                preferredModelId: coarseRouteDecision.preferredModelId,
                projectId: projectId,
                sessionId: nil,
                transportOverride: coarseRouteDecision.forceLocalExecution ? .fileIPC : nil
            )
            var out = ""
            var usage: LLMUsage? = nil
            for try await ev in provider.stream(req) {
                switch ev {
                case .delta(let t): out += t
                case .done(_, _, let u): usage = u
                }
            }
            coarseText = out
            coarseUsage = usage
        } else {
            coarseRouteDecision = AXProjectModelRouteMemoryStore.resolvePreferredModel(
                configuredModelId: preferredModelId,
                role: .coarse,
                ctx: ctx,
                snapshot: routeSnapshot,
                localSnapshot: localSnapshot
            )
            let res = try await HubAIClient.shared.generateTextWithReqId(
                prompt: coarsePromptText,
                taskType: "x_terminal_coarse",
                preferredModelId: coarseRouteDecision.preferredModelId,
                explicitModelId: nil,
                appId: "x_terminal",
                projectId: projectId,
                sessionId: nil,
                maxTokens: 768,
                temperature: 0.1,
                topP: 0.95,
                autoLoad: true,
                transportOverride: coarseRouteDecision.forceLocalExecution ? .fileIPC : nil,
                timeoutSec: 120
            )
            coarseText = res.text
            if let u = res.usage {
                coarseUsage = LLMUsage(
                    promptTokens: u.promptTokens,
                    completionTokens: u.generationTokens,
                    requestedModelId: u.requestedModelId,
                    actualModelId: u.actualModelId,
                    runtimeProvider: u.runtimeProvider,
                    executionPath: u.executionPath,
                    fallbackReasonCode: u.fallbackReasonCode,
                    remoteRetryAttempted: u.remoteRetryAttempted,
                    remoteRetryFromModelId: u.remoteRetryFromModelId,
                    remoteRetryToModelId: u.remoteRetryToModelId,
                    remoteRetryReasonCode: u.remoteRetryReasonCode
                )
            } else {
                coarseUsage = nil
            }
        }

        // usage log (prefer real tokens).
        var coarseUsageEntry: [String: Any] = [
            "type": "ai_usage",
            "created_at": Date().timeIntervalSince1970,
            "stage": "x_terminal_coarse",
            "role": AXRole.coarse.rawValue,
            "task_type": "x_terminal_coarse",
            "prompt_chars": coarsePromptText.count,
            "output_chars": coarseText.count,
            "prompt_tokens": coarseUsage?.promptTokens as Any,
            "output_tokens": coarseUsage?.completionTokens as Any,
            "token_source": (coarseUsage != nil) ? "provider" : "estimate",
            "prompt_tokens_est": TokenEstimator.estimateTokens(coarsePromptText),
            "output_tokens_est": TokenEstimator.estimateTokens(coarseText),
        ]
        if let requested = coarseUsage?.requestedModelId, !requested.isEmpty {
            coarseUsageEntry["requested_model_id"] = requested
        }
        if let actual = coarseUsage?.actualModelId, !actual.isEmpty {
            coarseUsageEntry["actual_model_id"] = actual
        }
        if let provider = coarseUsage?.runtimeProvider, !provider.isEmpty {
            coarseUsageEntry["runtime_provider"] = provider
        }
        if let path = coarseUsage?.executionPath, !path.isEmpty {
            coarseUsageEntry["execution_path"] = path
        }
        if let reason = coarseUsage?.fallbackReasonCode, !reason.isEmpty {
            coarseUsageEntry["fallback_reason_code"] = reason
        }
        if coarseUsage?.remoteRetryAttempted == true {
            coarseUsageEntry["remote_retry_attempted"] = true
        }
        if let retryFrom = coarseUsage?.remoteRetryFromModelId, !retryFrom.isEmpty {
            coarseUsageEntry["remote_retry_from_model_id"] = retryFrom
        }
        if let retryTo = coarseUsage?.remoteRetryToModelId, !retryTo.isEmpty {
            coarseUsageEntry["remote_retry_to_model_id"] = retryTo
        }
        if let retryReason = coarseUsage?.remoteRetryReasonCode, !retryReason.isEmpty {
            coarseUsageEntry["remote_retry_reason_code"] = retryReason
        }
        if let configured = coarseRouteDecision.configuredModelId, !configured.isEmpty {
            coarseUsageEntry["route_configured_model_id"] = configured
        }
        if let remembered = coarseRouteDecision.rememberedRemoteModelId, !remembered.isEmpty {
            coarseUsageEntry["route_memory_remote_model_id"] = remembered
        }
        if let local = coarseRouteDecision.preferredLocalModelId, !local.isEmpty {
            coarseUsageEntry["route_local_model_id"] = local
        }
        if let resolved = coarseRouteDecision.preferredModelId, !resolved.isEmpty {
            coarseUsageEntry["route_resolved_preferred_model_id"] = resolved
        }
        if coarseRouteDecision.forceLocalExecution {
            coarseUsageEntry["route_force_local_execution"] = true
        }
        if let reason = coarseRouteDecision.reasonCode, !reason.isEmpty {
            coarseUsageEntry["route_decision_reason"] = reason
        }
        AXProjectStore.appendUsage(coarseUsageEntry, for: ctx)

        // If coarse doesn't return JSON, fall back to a minimal delta.
        let deltaJSONString: String
        if let s = extractFirstJSONObject(from: coarseText) {
            deltaJSONString = s
        } else {
            deltaSource = "coarse_no_json_fallback"
            let user = turn.user.trimmingCharacters(in: .whitespacesAndNewlines)
            var d = AXMemoryDelta.empty()
            if !user.isEmpty {
                d.goalUpdate = user
                d.requirementsAdd = [user]
                d.nextStepsAdd = ["Implement: \(user)"]
            }
            let enc = JSONEncoder()
            enc.outputFormatting = [.sortedKeys]
            let data = try enc.encode(d)
            deltaJSONString = String(decoding: data, as: UTF8.self)
            AXProjectStore.appendRawLog(
                [
                    "type": "memory_update",
                    "phase": "coarse_no_json_fallback",
                    "created_at": Date().timeIntervalSince1970,
                ],
                for: ctx
            )
        }

        let deltaData = Data(deltaJSONString.utf8)
        let delta: AXMemoryDelta
        do {
            delta = try JSONDecoder().decode(AXMemoryDelta.self, from: deltaData)
        } catch {
            // If the model returns malformed JSON, don't lose the whole pipeline.
            AXProjectStore.appendRawLog(
                [
                    "type": "memory_update",
                    "phase": "coarse_decode_failed",
                    "created_at": Date().timeIntervalSince1970,
                    "error": String(describing: error),
                    "raw": deltaJSONString,
                ],
                for: ctx
            )
            // Best-effort: treat as empty delta.
            delta = .empty()
        }

        // Automatic deep memory: archive non-trivial turns into project-level Forgotten Vault.
        AXForgottenVault.autoArchiveTurn(ctx: ctx, turn: turn, delta: delta)

        // Event-trigger skill candidate detection (lightweight, deduped).
        let candidates = AXSkillCandidateDetector.detect(turn: turn, delta: delta, ctx: ctx, source: "event")
        _ = AXSkillCandidateStore.appendCandidates(candidates, for: ctx)
        AXSkillAutoPromoter.maybeAutoPromote(ctx: ctx, detected: candidates)

        // Refine merge.
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        let existingJSON = String(data: try enc.encode(existing), encoding: .utf8) ?? "{}"

        // Always feed valid JSON into refiner (avoid coarse invalid-json poisoning).
        let deltaForRefineJSON: String = {
            let enc = JSONEncoder()
            enc.outputFormatting = [.sortedKeys]
            if let data = try? enc.encode(delta) {
                return String(decoding: data, as: UTF8.self)
            }
            return "{}"
        }()

        let refinePromptText = refinePrompt(existingMemoryJSON: existingJSON, deltaJSON: deltaForRefineJSON)
        NotificationCenter.default.post(name: AXMemoryPipelineNotifications.refineStart, object: nil)
        defer { NotificationCenter.default.post(name: AXMemoryPipelineNotifications.refineEnd, object: nil) }

        let refineText: String
        let refineUsage: LLMUsage?
        let refineRouteDecision: AXProjectPreferredModelRouteDecision
        if let router {
            let provider = await router.provider(for: .refine)
            let preferredHub = await router.preferredModelIdForHub(for: .refine, projectConfig: projectConfig)
            refineRouteDecision = AXProjectModelRouteMemoryStore.resolvePreferredModel(
                configuredModelId: preferredHub ?? preferredModelId,
                role: .refine,
                ctx: ctx,
                snapshot: routeSnapshot,
                localSnapshot: localSnapshot
            )
            let taskType = router.taskType(for: .refine)
            let req = LLMRequest(
                role: .refine,
                messages: [LLMMessage(role: "user", content: refinePromptText)],
                maxTokens: 1024,
                temperature: 0.1,
                topP: 0.95,
                taskType: taskType,
                preferredModelId: refineRouteDecision.preferredModelId,
                projectId: projectId,
                sessionId: nil,
                transportOverride: refineRouteDecision.forceLocalExecution ? .fileIPC : nil
            )
            var out = ""
            var usage: LLMUsage? = nil
            for try await ev in provider.stream(req) {
                switch ev {
                case .delta(let t): out += t
                case .done(_, _, let u): usage = u
                }
            }
            refineText = out
            refineUsage = usage
        } else {
            refineRouteDecision = AXProjectModelRouteMemoryStore.resolvePreferredModel(
                configuredModelId: preferredModelId,
                role: .refine,
                ctx: ctx,
                snapshot: routeSnapshot,
                localSnapshot: localSnapshot
            )
            let res = try await HubAIClient.shared.generateTextWithReqId(
                prompt: refinePromptText,
                taskType: "x_terminal_refine",
                preferredModelId: refineRouteDecision.preferredModelId,
                explicitModelId: nil,
                appId: "x_terminal",
                projectId: projectId,
                sessionId: nil,
                maxTokens: 1024,
                temperature: 0.1,
                topP: 0.95,
                autoLoad: true,
                transportOverride: refineRouteDecision.forceLocalExecution ? .fileIPC : nil,
                timeoutSec: 180
            )
            refineText = res.text
            if let u = res.usage {
                refineUsage = LLMUsage(
                    promptTokens: u.promptTokens,
                    completionTokens: u.generationTokens,
                    requestedModelId: u.requestedModelId,
                    actualModelId: u.actualModelId,
                    runtimeProvider: u.runtimeProvider,
                    executionPath: u.executionPath,
                    fallbackReasonCode: u.fallbackReasonCode,
                    remoteRetryAttempted: u.remoteRetryAttempted,
                    remoteRetryFromModelId: u.remoteRetryFromModelId,
                    remoteRetryToModelId: u.remoteRetryToModelId,
                    remoteRetryReasonCode: u.remoteRetryReasonCode
                )
            } else {
                refineUsage = nil
            }
        }

        var refineUsageEntry: [String: Any] = [
            "type": "ai_usage",
            "created_at": Date().timeIntervalSince1970,
            "stage": "x_terminal_refine",
            "role": AXRole.refine.rawValue,
            "task_type": "x_terminal_refine",
            "prompt_chars": refinePromptText.count,
            "output_chars": refineText.count,
            "prompt_tokens": refineUsage?.promptTokens as Any,
            "output_tokens": refineUsage?.completionTokens as Any,
            "token_source": (refineUsage != nil) ? "provider" : "estimate",
            "prompt_tokens_est": TokenEstimator.estimateTokens(refinePromptText),
            "output_tokens_est": TokenEstimator.estimateTokens(refineText),
        ]
        if let requested = refineUsage?.requestedModelId, !requested.isEmpty {
            refineUsageEntry["requested_model_id"] = requested
        }
        if let actual = refineUsage?.actualModelId, !actual.isEmpty {
            refineUsageEntry["actual_model_id"] = actual
        }
        if let provider = refineUsage?.runtimeProvider, !provider.isEmpty {
            refineUsageEntry["runtime_provider"] = provider
        }
        if let path = refineUsage?.executionPath, !path.isEmpty {
            refineUsageEntry["execution_path"] = path
        }
        if let reason = refineUsage?.fallbackReasonCode, !reason.isEmpty {
            refineUsageEntry["fallback_reason_code"] = reason
        }
        if refineUsage?.remoteRetryAttempted == true {
            refineUsageEntry["remote_retry_attempted"] = true
        }
        if let retryFrom = refineUsage?.remoteRetryFromModelId, !retryFrom.isEmpty {
            refineUsageEntry["remote_retry_from_model_id"] = retryFrom
        }
        if let retryTo = refineUsage?.remoteRetryToModelId, !retryTo.isEmpty {
            refineUsageEntry["remote_retry_to_model_id"] = retryTo
        }
        if let retryReason = refineUsage?.remoteRetryReasonCode, !retryReason.isEmpty {
            refineUsageEntry["remote_retry_reason_code"] = retryReason
        }
        if let configured = refineRouteDecision.configuredModelId, !configured.isEmpty {
            refineUsageEntry["route_configured_model_id"] = configured
        }
        if let remembered = refineRouteDecision.rememberedRemoteModelId, !remembered.isEmpty {
            refineUsageEntry["route_memory_remote_model_id"] = remembered
        }
        if let local = refineRouteDecision.preferredLocalModelId, !local.isEmpty {
            refineUsageEntry["route_local_model_id"] = local
        }
        if let resolved = refineRouteDecision.preferredModelId, !resolved.isEmpty {
            refineUsageEntry["route_resolved_preferred_model_id"] = resolved
        }
        if refineRouteDecision.forceLocalExecution {
            refineUsageEntry["route_force_local_execution"] = true
        }
        if let reason = refineRouteDecision.reasonCode, !reason.isEmpty {
            refineUsageEntry["route_decision_reason"] = reason
        }
        AXProjectStore.appendUsage(refineUsageEntry, for: ctx)

        guard let memJSON = extractFirstJSONObject(from: refineText) else {
            // Fallback: apply a conservative local merge.
            var merged = applyDelta(delta, to: existing)
            seedIfEmpty(&merged, userText: turn.user)
            merged = AXMemoryModulePrefixer.normalizeIfNeeded(merged, projectRoot: ctx.root)
            try AXProjectStore.saveMemory(merged, for: ctx)
            _ = AXMemoryLifecycleStore.recordAfterTurn(
                ctx: ctx,
                turn: turn,
                beforeMemory: existing,
                observationDelta: delta,
                afterMemory: merged,
                pipelineSource: "\(deltaSource)_refine_text_fallback"
            )
            return merged
        }

        let memData = Data(memJSON.utf8)
        var mem: AXMemory
        do {
            mem = try JSONDecoder().decode(AXMemory.self, from: memData)
        } catch {
            // Refiner returned JSON but not matching schema. Fall back to local merge.
            AXProjectStore.appendRawLog(
                [
                    "type": "memory_update",
                    "phase": "refine_decode_failed",
                    "created_at": Date().timeIntervalSince1970,
                    "error": String(describing: error),
                    "raw": memJSON,
                ],
                for: ctx
            )
            var merged = applyDelta(delta, to: existing)
            seedIfEmpty(&merged, userText: turn.user)
            merged = AXMemoryModulePrefixer.normalizeIfNeeded(merged, projectRoot: ctx.root)
            try AXProjectStore.saveMemory(merged, for: ctx)
            AXProjectStore.appendRawLog(
                [
                    "type": "memory_update",
                    "phase": "done_fallback",
                    "created_at": Date().timeIntervalSince1970,
                ],
                for: ctx
            )
            _ = AXMemoryLifecycleStore.recordAfterTurn(
                ctx: ctx,
                turn: turn,
                beforeMemory: existing,
                observationDelta: delta,
                afterMemory: merged,
                pipelineSource: "\(deltaSource)_refine_decode_fallback"
            )
            return merged
        }
        // Ensure schema + timestamps are sane.
        mem.schemaVersion = AXMemory.currentSchemaVersion
        mem.projectName = existing.projectName
        mem.projectRoot = existing.projectRoot
        mem.updatedAt = Date().timeIntervalSince1970

        seedIfEmpty(&mem, userText: turn.user)
        mem = AXMemoryModulePrefixer.normalizeIfNeeded(mem, projectRoot: ctx.root)

        try AXProjectStore.saveMemory(mem, for: ctx)

        AXProjectStore.appendRawLog(
            [
                "type": "memory_update",
                "phase": "done",
                "created_at": Date().timeIntervalSince1970,
            ],
            for: ctx
        )
        _ = AXMemoryLifecycleStore.recordAfterTurn(
            ctx: ctx,
            turn: turn,
            beforeMemory: existing,
            observationDelta: delta,
            afterMemory: mem,
            pipelineSource: "\(deltaSource)_refine_model_json"
        )
        return mem
    }

    private static func seedIfEmpty(_ mem: inout AXMemory, userText: String) {
        let u = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !u.isEmpty else { return }
        if mem.goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            mem.goal = u
        }
        if mem.requirements.isEmpty {
            mem.requirements = [u]
        }
    }

    private static func fallbackMerge(existing: AXMemory, turn: AXConversationTurn) -> AXMemory {
        let d = fallbackDelta(existing: existing, turn: turn)
        let user = turn.user.trimmingCharacters(in: .whitespacesAndNewlines)
        var merged = applyDelta(d, to: existing)
        seedIfEmpty(&merged, userText: user)
        return merged
    }

    private static func fallbackDelta(existing: AXMemory, turn: AXConversationTurn) -> AXMemoryDelta {
        var d = AXMemoryDelta.empty()
        let user = turn.user.trimmingCharacters(in: .whitespacesAndNewlines)
        if !user.isEmpty {
            if existing.goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                d.goalUpdate = user
            }
            d.requirementsAdd = [user]
        }

        let steps = extractStepCandidates(from: turn.assistant)
        if !steps.isEmpty {
            d.nextStepsAdd = steps
        }
        return d
    }

    private static func extractStepCandidates(from text: String) -> [String] {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        if lines.isEmpty { return [] }

        let patterns = [
            "^\\s*[-*•]\\s+",
            "^\\s*\\d+[\\.|\\)]\\s+",
            "^\\s*\\d+\\s*[、\\.]\\s+",
            "^\\s*步骤\\s*\\d+[:：\\.]?\\s+",
        ]
        let regs: [NSRegularExpression] = patterns.compactMap { try? NSRegularExpression(pattern: $0, options: []) }

        func stripPrefix(_ s: String) -> String? {
            let r = NSRange(s.startIndex..<s.endIndex, in: s)
            for re in regs {
                if let m = re.firstMatch(in: s, options: [], range: r) {
                    if let rr = Range(m.range, in: s) {
                        let out = String(s[rr.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                        return out.isEmpty ? nil : out
                    }
                }
            }
            return nil
        }

        var out: [String] = []
        var seen: Set<String> = []
        for lineSub in lines {
            let line = String(lineSub)
            guard let cleaned = stripPrefix(line) else { continue }
            let norm = cleaned.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if norm.isEmpty || seen.contains(norm) { continue }
            seen.insert(norm)
            out.append(cleaned)
            if out.count >= 6 { break }
        }
        return out
    }

    // MARK: - Local fallback merge

    private static func applyDelta(_ d: AXMemoryDelta, to mem: AXMemory) -> AXMemory {
        var m = mem
        if let g = d.goalUpdate?.trimmingCharacters(in: .whitespacesAndNewlines), !g.isEmpty {
            m.goal = g
        }
        m.requirements = mergeList(base: m.requirements, add: d.requirementsAdd, remove: d.requirementsRemove)
        m.currentState = mergeList(base: m.currentState, add: d.currentStateAdd, remove: d.currentStateRemove)
        m.decisions = mergeList(base: m.decisions, add: d.decisionsAdd, remove: [])
        m.nextSteps = mergeList(base: m.nextSteps, add: d.nextStepsAdd, remove: d.nextStepsRemove)
        m.openQuestions = mergeList(base: m.openQuestions, add: d.openQuestionsAdd, remove: d.openQuestionsRemove)
        m.risks = mergeList(base: m.risks, add: d.risksAdd, remove: d.risksRemove)
        m.recommendations = mergeList(base: m.recommendations, add: d.recommendationsAdd, remove: [])
        m.updatedAt = Date().timeIntervalSince1970
        return m
    }

    private static func mergeList(base: [String], add: [String], remove: [String]) -> [String] {
        func norm(_ s: String) -> String {
            s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }

        var out: [String] = []
        var seen: Set<String> = []

        let removeSet = Set(remove.map(norm))
        for item in base {
            let t = item.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.isEmpty { continue }
            let k = norm(t)
            if removeSet.contains(k) { continue }
            if seen.contains(k) { continue }
            seen.insert(k)
            out.append(t)
        }

        for item in add {
            let t = item.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.isEmpty { continue }
            let k = norm(t)
            if removeSet.contains(k) { continue }
            if seen.contains(k) { continue }
            seen.insert(k)
            out.append(t)
        }

        return out
    }

    // Extract the first top-level JSON object from model output.
    private static func extractFirstJSONObject(from text: String) -> String? {
        let s = text
        guard let start = s.firstIndex(of: "{") else { return nil }

        var i = start
        var depth = 0
        var inString = false
        var escape = false

        while i < s.endIndex {
            let ch = s[i]

            if inString {
                if escape {
                    escape = false
                } else if ch == "\\" {
                    escape = true
                } else if ch == "\"" {
                    inString = false
                }
            } else {
                if ch == "\"" {
                    inString = true
                } else if ch == "{" {
                    depth += 1
                } else if ch == "}" {
                    depth -= 1
                    if depth == 0 {
                        let end = s.index(after: i)
                        return String(s[start..<end])
                    }
                }
            }

            i = s.index(after: i)
        }

        return nil
    }
}
