import Foundation

extension ChatSessionModel {
    func handleSlashModel(
        args: [String],
        userText: String,
        ctx: AXProjectContext,
        config: AXProjectConfig?,
        snapshot overrideSnapshot: ModelStateSnapshot? = nil
    ) -> String {
        if args.isEmpty {
            return slashModelsText(ctx: ctx, config: config)
        }

        let mid = args.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        if mid.isEmpty {
            return slashModelsText(ctx: ctx, config: config)
        }

        if ["auto", "default", "none", "clear"].contains(mid.lowercased()) {
            guard var cfg = (config ?? (try? AXProjectStore.loadOrCreateConfig(for: ctx))) else {
                return projectConfigUpdateUnavailableText()
            }
            if projectModelOverrideChanged(current: cfg.modelOverride(for: .coder), next: nil) {
                writeSessionSummaryCapsuleIfPossible(
                    ctx: ctx,
                    reason: "ai_switch",
                    excludingTrailingUserText: userText
                )
            }
            cfg = cfg.settingModelOverride(role: .coder, modelId: nil)
            activeConfig = cfg
            try? AXProjectStore.saveConfig(cfg, for: ctx)
            return "已清除 coder 的项目级模型覆盖，回退到全局路由。"
        }

        let snapshot = modelsSnapshotForSlash(snapshot: overrideSnapshot)
        let assessment = HubModelSelectionAdvisor.assess(requestedId: mid, snapshot: snapshot)
        if let blocked = assessment?.nonInteractiveExactMatch {
            return blockedSlashModelSelectionText(
                role: .coder,
                requestedModelId: mid,
                blocked: blocked,
                assessment: assessment,
                ctx: ctx,
                snapshot: snapshot
            )
        }
        if shouldRejectUnavailableSlashModelSelection(
            assessment: assessment,
            snapshot: snapshot
        ) {
            return unavailableSlashModelSelectionPreflightText(
                role: .coder,
                requestedModelId: mid,
                assessment: assessment,
                ctx: ctx,
                snapshot: snapshot
            )
        }
        guard var cfg = (config ?? (try? AXProjectStore.loadOrCreateConfig(for: ctx))) else {
            return projectConfigUpdateUnavailableText()
        }
        if projectModelOverrideChanged(current: cfg.modelOverride(for: .coder), next: mid) {
            writeSessionSummaryCapsuleIfPossible(
                ctx: ctx,
                reason: "ai_switch",
                excludingTrailingUserText: userText
            )
        }
        cfg = cfg.settingModelOverride(role: .coder, modelId: mid)
        activeConfig = cfg
        try? AXProjectStore.saveConfig(cfg, for: ctx)

        if AXProjectModelRouteMemoryStore.isDirectlyRunnable(assessment: assessment) {
            return "已将 coder 模型设置为：\(mid)"
        }
        if snapshot.models.isEmpty {
            return [
                "已将 coder 模型设置为：\(mid)",
                "",
                "当前拿不到 Hub 的模型快照，暂时无法确认它是否真的可用。可执行 `/models`，或去 Supervisor Control Center · AI 模型检查。"
            ].joined(separator: "\n")
        }
        return unavailableSlashModelSelectionText(modelId: mid, assessment: assessment, transportMode: HubAIClient.transportMode().rawValue)
    }

    func handleSlashRoleModel(
        args: [String],
        userText: String,
        ctx: AXProjectContext,
        config: AXProjectConfig?,
        snapshot overrideSnapshot: ModelStateSnapshot? = nil
    ) -> String {
        guard args.count >= 2 else {
            return "用法：/rolemodel <supervisor|coder|reviewer> <model_id|auto>"
        }

        guard let role = roleFromSlashToken(args[0]) else {
            return "未知角色：\(args[0])\n可选：\(AXRole.modelAssignmentHelpText)"
        }

        let modelArg = args.dropFirst().joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard var cfg = (config ?? (try? AXProjectStore.loadOrCreateConfig(for: ctx))) else {
            return projectConfigUpdateUnavailableText()
        }

        if ["auto", "default", "none", "clear"].contains(modelArg.lowercased()) {
            if projectModelOverrideChanged(current: cfg.modelOverride(for: role), next: nil) {
                writeSessionSummaryCapsuleIfPossible(
                    ctx: ctx,
                    reason: "ai_switch",
                    excludingTrailingUserText: userText
                )
            }
            cfg = cfg.settingModelOverride(role: role, modelId: nil)
            activeConfig = cfg
            try? AXProjectStore.saveConfig(cfg, for: ctx)
            return "已清除 \(role.rawValue) 的项目级模型覆盖，回退到全局路由。"
        }

        let snapshot = modelsSnapshotForSlash(snapshot: overrideSnapshot)
        let assessment = HubModelSelectionAdvisor.assess(requestedId: modelArg, snapshot: snapshot)
        if let blocked = assessment?.nonInteractiveExactMatch {
            return blockedSlashModelSelectionText(
                role: role,
                requestedModelId: modelArg,
                blocked: blocked,
                assessment: assessment,
                ctx: ctx,
                snapshot: snapshot
            )
        }
        if shouldRejectUnavailableSlashModelSelection(
            assessment: assessment,
            snapshot: snapshot
        ) {
            return unavailableSlashModelSelectionPreflightText(
                role: role,
                requestedModelId: modelArg,
                assessment: assessment,
                ctx: ctx,
                snapshot: snapshot
            )
        }

        if projectModelOverrideChanged(current: cfg.modelOverride(for: role), next: modelArg) {
            writeSessionSummaryCapsuleIfPossible(
                ctx: ctx,
                reason: "ai_switch",
                excludingTrailingUserText: userText
            )
        }
        cfg = cfg.settingModelOverride(role: role, modelId: modelArg)
        activeConfig = cfg
        try? AXProjectStore.saveConfig(cfg, for: ctx)
        if AXProjectModelRouteMemoryStore.isDirectlyRunnable(assessment: assessment) {
            return "已将 \(role.rawValue) 模型设置为：\(modelArg)"
        }
        if snapshot.models.isEmpty {
            return [
                "已将 \(role.rawValue) 模型设置为：\(modelArg)",
                "",
                "当前拿不到 Hub 的模型快照，暂时无法确认它是否真的可用。可执行 `/models`，或去 Supervisor Control Center · AI 模型检查。"
            ].joined(separator: "\n")
        }
        return "已将 \(role.rawValue) 模型设置为：\(modelArg)"
    }

    func performSlashModels(
        ctx: AXProjectContext,
        userText: String,
        config: AXProjectConfig?,
        assistantIndex: Int
    ) {
        Task {
            async let displaySnapshot = HubAIClient.shared.loadModelsState()
            async let routeDecisionSnapshot = HubAIClient.shared.loadRouteDecisionModelsState()
            async let localSnapshot = HubAIClient.shared.loadModelsState(transportOverride: .fileIPC)
            let reply = slashModelsText(
                ctx: ctx,
                config: config,
                snapshot: await displaySnapshot,
                routeDecisionSnapshot: await routeDecisionSnapshot,
                localSnapshot: await localSnapshot
            )
            finalizeTurn(ctx: ctx, userText: userText, assistantText: reply, assistantIndex: assistantIndex)
        }
    }

    func performSlashRouteDiagnose(
        ctx: AXProjectContext,
        userText: String,
        config: AXProjectConfig?,
        router: LLMRouter,
        assistantIndex: Int
    ) {
        Task {
            async let routeSnapshot = HubAIClient.shared.loadRouteDecisionModelsState()
            async let localSnapshot = HubAIClient.shared.loadModelsState(transportOverride: .fileIPC)
            async let supervisorRouteDecision = currentProjectSupervisorRouteDecisionSnapshot(
                ctx: ctx,
                config: config
            )
            let reply = projectRouteDiagnosisText(
                ctx: ctx,
                config: config,
                router: router,
                routeSnapshot: await routeSnapshot,
                localSnapshot: await localSnapshot,
                supervisorRouteDecision: await supervisorRouteDecision
            )
            finalizeTurn(ctx: ctx, userText: userText, assistantText: reply, assistantIndex: assistantIndex)
        }
    }

    func slashRouteUsageText() -> String {
        """
用法：
- /route
- /route diagnose
"""
    }

    private func roleFromSlashToken(_ token: String) -> AXRole? {
        AXRole.resolveModelAssignmentToken(token)
    }
}
