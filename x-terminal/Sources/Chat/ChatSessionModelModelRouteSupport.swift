import Foundation

extension ChatSessionModel {
    func modelsSnapshotForSlash(snapshot: ModelStateSnapshot? = nil) -> ModelStateSnapshot {
        if let snapshot {
            return snapshot
        }
        let url = HubPaths.modelsStateURL()
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(ModelStateSnapshot.self, from: data) else {
            return .empty()
        }
        return decoded
    }

    func loadedModelsForSlash(snapshot: ModelStateSnapshot? = nil) -> [HubModel] {
        HubModelSelectionAdvisor.loadedModels(in: modelsSnapshotForSlash(snapshot: snapshot))
    }

    func effectiveProjectRouteDecision(
        configuredModelId: String?,
        role: AXRole,
        ctx: AXProjectContext?,
        snapshot: ModelStateSnapshot,
        localSnapshot: ModelStateSnapshot? = nil,
        transportMode: HubTransportMode = HubAIClient.transportMode()
    ) -> AXProjectPreferredModelRouteDecision {
        let baseDecision = AXProjectModelRouteMemoryStore.resolvePreferredModel(
            configuredModelId: configuredModelId,
            role: role,
            ctx: ctx,
            snapshot: snapshot,
            localSnapshot: localSnapshot
        )

        guard role == .coder, transportMode == .grpc else {
            return baseDecision
        }

        guard let configured = baseDecision.configuredModelId?.trimmingCharacters(in: .whitespacesAndNewlines),
              !configured.isEmpty else {
            return baseDecision
        }

        guard baseDecision.reasonCode != "project_configured_model_retrieval_only" else {
            return baseDecision
        }

        guard baseDecision.forceLocalExecution || baseDecision.usedRememberedRemoteModel else {
            return baseDecision
        }

        return AXProjectPreferredModelRouteDecision(
            preferredModelId: configured,
            configuredModelId: configured,
            rememberedRemoteModelId: baseDecision.rememberedRemoteModelId,
            preferredLocalModelId: nil,
            usedRememberedRemoteModel: false,
            forceLocalExecution: false,
            reasonCode: "grpc_preserve_configured_model"
        )
    }

    func slashModelsText(
        ctx: AXProjectContext? = nil,
        config: AXProjectConfig?,
        snapshot: ModelStateSnapshot? = nil,
        routeDecisionSnapshot: ModelStateSnapshot? = nil,
        localSnapshot: ModelStateSnapshot? = nil,
        transportMode: HubTransportMode = HubAIClient.transportMode()
    ) -> String {
        let baseSnapshot = modelsSnapshotForSlash(snapshot: snapshot)
        let resolvedRouteDecisionSnapshot = modelsSnapshotForSlash(snapshot: routeDecisionSnapshot ?? snapshot)
        let resolvedLocalSnapshot = modelsSnapshotForSlash(snapshot: localSnapshot ?? routeDecisionSnapshot ?? snapshot)
        let current = config?.modelOverride(for: .coder)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let models = HubModelSelectionAdvisor.loadedModels(in: baseSnapshot)
        let inventory = HubModelSelectionAdvisor.allModels(in: baseSnapshot)
        let transport = transportMode
        let mode = transport.rawValue
        var lines: [String] = []
        let routeDecision = effectiveProjectRouteDecision(
            configuredModelId: current,
            role: .coder,
            ctx: ctx,
            snapshot: resolvedRouteDecisionSnapshot,
            localSnapshot: resolvedLocalSnapshot
        )
        let routeMemory = ctx.flatMap { AXProjectModelRouteMemoryStore.load(for: $0, role: .coder) }

        if current.isEmpty {
            lines.append("当前 coder 模型：自动路由")
            lines.append("状态：当前项目没有固定模型 ID，会继续按全局分配和 Hub 路由尝试。")
        } else {
            lines.append("当前 coder 模型：\(current)")
            lines.append("状态：\(slashConfiguredModelStatusText(configuredModelId: current, snapshot: resolvedRouteDecisionSnapshot))")
        }
        lines.append("当前传输模式：\(mode)")
        if routeDecision.forceLocalExecution,
           let localModelId = (routeDecision.preferredLocalModelId ?? routeDecision.preferredModelId)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !localModelId.isEmpty {
            lines.append("路由状态：当前项目已锁定为本地模式。")
            lines.append("当前本地模型：\(localModelId)")
            if let routeMemory {
                let requested = routeMemory.lastRequestedModelId.trimmingCharacters(in: .whitespacesAndNewlines)
                if !requested.isEmpty {
                    let reasonSuffix = projectRouteFailureReasonParenthesized(routeMemory.lastFailureReasonCode)
                    lines.append("触发原因：`\(requested)` 最近连续 \(routeMemory.consecutiveRemoteFallbackCount) 次未稳定命中\(reasonSuffix)。")
                }
            }
            lines.append("恢复建议：检查 Hub 的远端模型配置后，再运行 `/models` 或重新 `/model <id>`。")
        } else if let routeStatus = slashRouteStatusSummary(
            configuredModelId: current,
            routeDecision: routeDecision,
            routeMemory: routeMemory,
            snapshot: resolvedRouteDecisionSnapshot,
            transport: transport
        ) {
            lines.append(routeStatus)
        }
        if let routeMemory, !routeMemory.lastHealthyRemoteModelId.isEmpty {
            lines.append("上次稳定远端模型：\(routeMemory.lastHealthyRemoteModelId)")
        }

        if models.isEmpty {
            lines.append("")
            lines.append("当前没有已加载模型。")
            if !inventory.isEmpty {
                lines.append("Hub 候选列表里还能看到 \(inventory.count) 个候选，但它们当前还不能直接执行。")
                let sleepingOrAvailable = inventory.prefix(5).map { model in
                    "- \(HubModelSelectionAdvisor.compactSuggestionLabel(model)) · \(slashInventoryCandidateStatusText(model))"
                }
                if !sleepingOrAvailable.isEmpty {
                    lines.append("")
                    lines.append("Hub 候选列表：")
                    lines.append(contentsOf: sleepingOrAvailable)
                }
            }
            lines.append("")
            lines.append("建议动作：")
            lines.append("1. 在 Supervisor Control Center · AI 模型确认目标模型已经进入真实可执行列表。")
            lines.append("2. 运行 `/models` 刷新当前列表。")
            lines.append("3. 如果暂时没有远端模型，可先接受本地模式回答。")
            return lines.joined(separator: "\n")
        }

        let modelLines = models.flatMap { slashLoadedModelLines($0) }
        lines.append("")
        lines.append("Hub 已加载模型：")
        lines.append(contentsOf: modelLines)

        if !current.isEmpty {
            let actionLines = slashConfiguredModelActionLines(configuredModelId: current, snapshot: baseSnapshot)
            if !actionLines.isEmpty {
                lines.append("")
                lines.append("建议动作：")
                lines.append(contentsOf: actionLines)
            }
        }

        return lines.joined(separator: "\n")
    }

    func slashLoadedModelLines(_ model: HubModel) -> [String] {
        let remote = isRemoteModelForSlash(model) ? "Remote" : "Local"
        let name = model.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? model.id : model.name
        var lines = ["- \(name) · \(model.id) · \(remote) · \(model.backend)"]
        lines.append("  \(model.defaultLoadConfigDisplayLine)")
        if let localLoadConfigLimitLine = model.localLoadConfigLimitLine {
            lines.append("  \(localLoadConfigLimitLine)")
        }
        return lines
    }

    func slashInventoryCandidateStatusText(_ model: HubModel) -> String {
        if model.isKnownLocalButCurrentlyUnrunnable {
            return "本地路径失效，当前不可执行"
        }
        return HubModelSelectionAdvisor.stateLabel(model.state)
    }

    func slashUnavailableLocalModelIssue(_ model: HubModel) -> String? {
        guard let reason = model.localExecutionBlockedReason else { return nil }
        return "\(reason)；这个候选现在不能自动加载。"
    }

    func slashRouteStatusSummary(
        configuredModelId: String,
        routeDecision: AXProjectPreferredModelRouteDecision,
        routeMemory: AXProjectModelRouteMemory?,
        snapshot: ModelStateSnapshot,
        transport: HubTransportMode
    ) -> String? {
        let configured = configuredModelId.trimmingCharacters(in: .whitespacesAndNewlines)

        if shouldExplainGrpcConfiguredRemoteVerification(
            configuredModelId: configured,
            routeDecision: routeDecision,
            routeMemory: routeMemory,
            routeSnapshot: snapshot,
            transport: transport
        ) {
            return "路由状态：当前传输模式是 grpc-only；XT 会保留你配置的 `\(configured)` 继续发起远端验证，不再让项目级本地锁或上次稳定远端改写这轮请求。"
        }

        if routeDecision.usedRememberedRemoteModel,
           let remembered = routeDecision.preferredModelId?.trimmingCharacters(in: .whitespacesAndNewlines),
           let requested = routeDecision.configuredModelId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !remembered.isEmpty,
           !requested.isEmpty,
           remembered.caseInsensitiveCompare(requested) != .orderedSame {
            return "路由状态：当前配置的 `\(requested)` 还不能直接执行；XT 这轮会先自动试上次稳定远端 `\(remembered)`，不用手动切模型。"
        }

        guard let routeMemory,
              routeMemory.shouldSuggestLocalModeNotice,
              !configured.isEmpty else {
            return nil
        }
        let configuredAssessment = HubModelSelectionAdvisor.assess(
            requestedId: configured,
            snapshot: snapshot
        )
        guard AXProjectModelRouteMemoryStore.isDirectlyRunnable(assessment: configuredAssessment) else {
            return nil
        }
        return "路由状态：之前因连续回落触发的本地锁已自动解除；`\(configured)` 现在恢复可执行。"
    }

    func unavailableSlashModelSelectionText(
        modelId: String,
        assessment: HubModelAvailabilityAssessment?,
        transportMode: String
    ) -> String {
        var lines: [String] = [
            "已将 coder 模型设置为：\(modelId)",
            ""
        ]

        if let assessment {
            if let blocked = assessment.nonInteractiveExactMatch {
                lines.append(
                    "`\(blocked.id)` 是非对话模型。\(blocked.interactiveRoutingDisabledReason ?? "这个模型属于非对话能力，会由 Supervisor 按需调用，不作为对话模型。")"
                )
            } else if let exact = assessment.exactMatch {
                if let issue = slashUnavailableLocalModelIssue(exact) {
                    lines.append("但 Hub 当前还没有把它放进可执行列表。现在记录里看到的是 `\(exact.id)`，\(issue)")
                } else {
                    lines.append(
                        "但 Hub 当前还没有把它放进可执行列表。现在记录里看到的是 `\(exact.id)`，状态是 \(HubModelSelectionAdvisor.stateLabel(exact.state))。"
                    )
                }
            } else {
                lines.append("但 Hub 当前既没有把这个模型加入已加载列表，也没有在候选列表里看到精确匹配。")
            }
        } else {
            lines.append("但当前拿不到 Hub 的模型快照，无法确认它是否真的可用。")
        }

        if slashIsGrpcTransport(transportMode) {
            lines.append("如果现在直接发请求，这一轮大概率不会精确命中这个远端目标。")
        } else {
            lines.append("如果现在直接发请求，这一轮大概率不会精确命中这个远端目标；更可能由本地模式或其他可执行候选接住。")
        }
        if slashIsGrpcTransport(transportMode) {
            lines.append(slashGrpcUnavailableRouteTruthHint())
        }

        let suggestedCandidates = slashSuggestedCandidates(from: assessment)
        let exactLocalPathBroken = assessment?.exactMatch?.isKnownLocalButCurrentlyUnrunnable == true
        if !suggestedCandidates.isEmpty {
            lines.append("")
            lines.append("如果你要立刻继续，可改用这些候选：\(suggestedCandidates.joined(separator: "、"))")
        }

        lines.append("")
        lines.append("建议动作：")
        if exactLocalPathBroken {
            lines.append("1. 去 X-Hub → Models & Paid Access，重新选择 `\(modelId)` 对应的本地目录或文件，确保 modelPath 仍然有效。")
        } else {
            lines.append("1. 在 Supervisor Control Center · AI 模型确认 `\(modelId)` 已进入真实可执行列表。")
        }
        lines.append("2. 运行 `/models` 刷新当前视图。")
        if let first = suggestedCandidates.first {
            lines.append("3. 如果你现在就要继续，可先执行 `/model \(first)`。")
        } else {
            lines.append("3. 如果你现在就要继续，可先接受本地模式回答，再检查 Hub 配置。")
        }
        lines.append("4. 当前传输模式：\(transportMode)")

        return lines.joined(separator: "\n")
    }

    func shouldRejectUnavailableSlashModelSelection(
        assessment: HubModelAvailabilityAssessment?,
        snapshot: ModelStateSnapshot
    ) -> Bool {
        guard !snapshot.models.isEmpty, let assessment else { return false }
        return !AXProjectModelRouteMemoryStore.isDirectlyRunnable(assessment: assessment)
    }

    private struct SlashModelSelectionPreflightGuidance {
        var detailLines: [String]
        var actionItems: [String]
    }

    private func slashSelectionRoutePreflightGuidance(
        role: AXRole,
        requestedModelId rawRequestedModelId: String,
        ctx: AXProjectContext,
        snapshot: ModelStateSnapshot,
        suggestions: [String]
    ) -> SlashModelSelectionPreflightGuidance? {
        let requestedModelId = rawRequestedModelId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !requestedModelId.isEmpty else { return nil }

        let routeDecision = effectiveProjectRouteDecision(
            configuredModelId: requestedModelId,
            role: role,
            ctx: ctx,
            snapshot: snapshot,
            localSnapshot: snapshot
        )

        if routeDecision.usedRememberedRemoteModel,
           let rememberedRaw = routeDecision.preferredModelId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !rememberedRaw.isEmpty,
           rememberedRaw.caseInsensitiveCompare(requestedModelId) != .orderedSame {
            let rememberedAssessment = HubModelSelectionAdvisor.assess(
                requestedId: rememberedRaw,
                snapshot: snapshot
            )
            let rememberedLoaded = AXProjectModelRouteMemoryStore.isDirectlyRunnable(assessment: rememberedAssessment)
            let rememberedCommand = slashModelSelectionCommand(role: role, modelId: rememberedRaw)
            let requestedCommand = slashModelSelectionCommand(role: role, modelId: requestedModelId)

            if rememberedLoaded {
                return SlashModelSelectionPreflightGuidance(
                    detailLines: [
                        "项目路由记忆：`\(requestedModelId)` 当前还不能直接执行，但这个项目上次稳定的远端 `\(rememberedRaw)` 已恢复可用。",
                        "如果你只是想继续，不用手动切模型；XT 下一轮会先试 `\(rememberedRaw)`。"
                    ],
                    actionItems: [
                        "如果你是要固定到 `\(requestedModelId)`，先去 Supervisor Control Center · AI 模型确认它已进入真实可执行列表，再运行 `/models`，然后重试 `\(requestedCommand)`。",
                        "如果你只是想继续，保持当前配置即可；XT 会先自动试 `\(rememberedRaw)`。",
                        "如果你要把 `\(rememberedRaw)` 固定成当前配置，可执行 `\(rememberedCommand)`。"
                    ]
                )
            }

            return SlashModelSelectionPreflightGuidance(
                detailLines: [
                    "项目路由记忆：`\(requestedModelId)` 当前还不能直接执行；XT 下一轮会先把这个项目上次稳定的远端 `\(rememberedRaw)` 当作优先候选。",
                    "如果你只是想继续，XT 仍会先按 `\(rememberedRaw)` 去尝试；但它自己也可能还需要在 Hub 里恢复加载。"
                ],
                actionItems: [
                    "如果你是要固定到 `\(requestedModelId)`，先去 Supervisor Control Center · AI 模型确认它已进入真实可执行列表，再运行 `/models`，然后重试 `\(requestedCommand)`。",
                    "如果你只是想继续，也最好顺手在 Supervisor Control Center · AI 模型确认 `\(rememberedRaw)` 已进入真实可执行列表；否则 XT 改试它时仍可能继续命不中远端。",
                    "如果你要把 `\(rememberedRaw)` 固定成当前配置，可执行 `\(rememberedCommand)`。"
                ]
            )
        }

        if routeDecision.forceLocalExecution,
           let routeMemory = AXProjectModelRouteMemoryStore.load(for: ctx, role: role) {
            let localModelId = (routeDecision.preferredLocalModelId ?? routeDecision.preferredModelId)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let localModelText = localModelId.isEmpty ? "本地模型" : "`\(localModelId)`"
            let reasonSuffix = projectRouteFailureReasonParenthesized(
                routeMemory.lastFailureReasonCode,
                recent: true
            )
            let requestedCommand = slashModelSelectionCommand(role: role, modelId: requestedModelId)

            var detailLines = [
                "项目路由记忆：这个项目最近连续 \(routeMemory.consecutiveRemoteFallbackCount) 次没有稳定命中 `\(requestedModelId)`\(reasonSuffix)，XT 当前仍会先锁到本地 \(localModelText)。"
            ]
            var actionItems = [
                "如果你是要固定到 `\(requestedModelId)`，先去 Supervisor Control Center · AI 模型确认它已恢复到真实可执行列表，再运行 `/models`，然后重试 `\(requestedCommand)`。",
                "当前项目级本地锁还在；就算现在重新选择 `\(requestedModelId)`，这轮也不会立刻避开本地。"
            ]
            if let first = suggestions.first {
                detailLines.append("如果你现在只是想继续，可显式改用已加载的可执行模型 `\(first)`；否则这轮仍更可能由本地接管。")
                actionItems.append("如果你要显式改到可执行候选，可执行 `\(slashModelSelectionCommand(role: role, modelId: first))`。")
            } else {
                detailLines.append("如果你现在只是想继续，这轮只能先接受本地模式；等 `\(requestedModelId)` 在 Hub 恢复后再重试。")
                actionItems.append("如果你只是想继续，只能先接受本地模式回答，再检查 Hub 配置。")
            }
            return SlashModelSelectionPreflightGuidance(
                detailLines: detailLines,
                actionItems: actionItems
            )
        }

        return nil
    }

    func blockedSlashModelSelectionText(
        role: AXRole,
        requestedModelId: String,
        blocked: HubModel,
        assessment: HubModelAvailabilityAssessment?,
        ctx: AXProjectContext,
        snapshot: ModelStateSnapshot
    ) -> String {
        let suggestions = slashSuggestedCandidates(
            from: assessment,
            configuredModelId: requestedModelId,
            role: role,
            ctx: ctx,
            snapshot: snapshot
        )
        var lines = [
            "未修改当前 \(role.rawValue) 模型配置。",
            "`\(blocked.id)` 不能直接用于对话执行。\(blocked.interactiveRoutingDisabledReason ?? "这个模型属于非对话能力，会由 Supervisor 按需调用，不作为对话模型。")"
        ]
        if let first = suggestions.first {
            lines.append("建议直接执行 `\(slashModelSelectionCommand(role: role, modelId: first))`。")
        } else {
            lines.append("可执行 `\(slashModelSelectionCommand(role: role, modelId: "auto"))` 恢复自动路由。")
        }
        return lines.joined(separator: "\n")
    }

    func unavailableSlashModelSelectionPreflightText(
        role: AXRole,
        requestedModelId: String,
        assessment: HubModelAvailabilityAssessment?,
        ctx: AXProjectContext,
        snapshot: ModelStateSnapshot
    ) -> String {
        let suggestions = slashSuggestedCandidates(
            from: assessment,
            configuredModelId: requestedModelId,
            role: role,
            ctx: ctx,
            snapshot: snapshot
        )
        let routeGuidance = slashSelectionRoutePreflightGuidance(
            role: role,
            requestedModelId: requestedModelId,
            ctx: ctx,
            snapshot: snapshot,
            suggestions: suggestions
        )
        var lines = ["未修改当前 \(role.rawValue) 模型配置。"]
        if let exact = assessment?.exactMatch {
            if let issue = slashUnavailableLocalModelIssue(exact) {
                lines.append("`\(exact.id)` 当前还不能直接执行，\(issue)")
            } else {
                lines.append("`\(exact.id)` 当前还不能直接执行，状态是 \(HubModelSelectionAdvisor.stateLabel(exact.state))。")
            }
        } else {
            lines.append("当前候选列表里没有找到 `\(requestedModelId)` 的精确匹配。")
        }
        if slashIsGrpcTransport(HubAIClient.transportMode().rawValue) {
            lines.append(slashGrpcUnavailableRouteTruthHint())
        }
        if let routeGuidance {
            lines.append("")
            lines.append(contentsOf: routeGuidance.detailLines)
        } else if let first = suggestions.first {
            lines.append("建议直接执行 `\(slashModelSelectionCommand(role: role, modelId: first))`，或先去 Supervisor Control Center · AI 模型确认目标模型已进入真实可执行列表再试。")
        } else {
            lines.append("建议先去 Supervisor Control Center · AI 模型确认目标模型已进入真实可执行列表，再运行 `/models` 刷新。")
        }
        let actionItems = routeGuidance?.actionItems ?? {
            let localPathFix = assessment?.exactMatch?.isKnownLocalButCurrentlyUnrunnable == true
            var items = [
                localPathFix
                    ? "先去 X-Hub → Models & Paid Access，重新选择 `\(requestedModelId)` 对应的本地目录或文件，确保 modelPath 仍然有效。"
                    : "先去 Supervisor Control Center · AI 模型确认 `\(requestedModelId)` 已进入真实可执行列表。",
                "运行 `/models` 刷新当前视图。"
            ]
            if let first = suggestions.first {
                items.append("如果你现在就要继续，可先执行 `\(slashModelSelectionCommand(role: role, modelId: first))`。")
            } else {
                items.append("如果你现在就要继续，可先接受本地模式回答，再检查 Hub 配置。")
            }
            return items
        }()
        lines.append("")
        lines.append("建议动作：")
        for (index, item) in actionItems.enumerated() {
            lines.append("\(index + 1). \(item)")
        }
        lines.append("\(actionItems.count + 1). 当前传输模式：\(HubAIClient.transportMode().rawValue)")
        return lines.joined(separator: "\n")
    }

    func slashModelSelectionCommand(role: AXRole, modelId: String) -> String {
        let normalized = modelId.trimmingCharacters(in: .whitespacesAndNewlines)
        if role == .coder {
            return "/model \(normalized)"
        }
        return "/rolemodel \(role.rawValue) \(normalized)"
    }

    func slashGrpcUnavailableRouteTruthHint() -> String {
        "当前传输模式是 grpc-only；如果之后实际仍落到本地，更像是 Hub 执行阶段触发降级、export gate 生效，或上游远端还没 ready，不是 XT 静默改成本地。"
    }

    func slashConfiguredModelStatusText(
        configuredModelId: String,
        snapshot: ModelStateSnapshot
    ) -> String {
        guard let assessment = HubModelSelectionAdvisor.assess(
            requestedId: configuredModelId,
            snapshot: snapshot
        ) else {
            return "当前没有固定模型。"
        }

        if AXProjectModelRouteMemoryStore.isDirectlyRunnable(assessment: assessment),
           let exact = assessment.exactMatch {
            let locality = isRemoteModelForSlash(exact) ? "远端" : "本地"
            if exact.state == .loaded {
                return "已加载，可直接执行（\(locality)）。"
            }
            return "Hub 候选列表已精确命中；当前会继续按远端执行尝试（\(locality)，状态：\(HubModelSelectionAdvisor.stateLabel(exact.state))）。"
        }
        if let blocked = assessment.nonInteractiveExactMatch {
            return "当前命中的是非对话模型：`\(blocked.id)`。\(blocked.interactiveRoutingDisabledReason ?? "这个模型属于非对话能力，会由 Supervisor 按需调用，不作为对话模型。")"
        }
        if let exact = assessment.exactMatch {
            if let issue = slashUnavailableLocalModelIssue(exact) {
                return "已配置，但\(issue)"
            }
            let tail = slashIsGrpcTransport(HubAIClient.transportMode().rawValue)
                ? " 当前传输模式是 grpc-only；如果实际仍落到本地，更像是 Hub / 上游链路还没 ready，不是 XT 静默改成本地。"
                : ""
            let base = "已配置，但当前只在候选列表中可见，状态：\(HubModelSelectionAdvisor.stateLabel(exact.state))；这轮大概率不会精确命中这个目标。"
            return base + tail
        }
        let tail = slashIsGrpcTransport(HubAIClient.transportMode().rawValue)
            ? " 当前传输模式是 grpc-only；如果实际仍落到本地，更像是 Hub 执行阶段触发降级、export gate 生效，或上游远端还没 ready，不是 XT 静默改成本地。"
            : ""
        let base = "当前候选列表里没有精确匹配；这轮大概率不会精确命中这个目标。"
        return base + tail
    }

    func slashConfiguredModelActionLines(
        configuredModelId: String,
        snapshot: ModelStateSnapshot
    ) -> [String] {
        guard let assessment = HubModelSelectionAdvisor.assess(
            requestedId: configuredModelId,
            snapshot: snapshot
        ) else {
            return []
        }
        guard !AXProjectModelRouteMemoryStore.isDirectlyRunnable(assessment: assessment) else { return [] }

        var lines = [
            "检查 Supervisor Control Center · AI 模型，确认 `\(configuredModelId)` 已进入真实可执行列表。",
            "执行 `/models` 刷新当前模型列表。"
        ]
        if assessment.nonInteractiveExactMatch != nil {
            lines[0] = "这个模型是检索专用，不建议作为当前对话模型。"
            lines[1] = "执行 `/model auto` 恢复自动路由，或切到一个可对话模型。"
        } else if let exact = assessment.exactMatch,
                  exact.isKnownLocalButCurrentlyUnrunnable {
            lines[0] = "去 X-Hub → Models & Paid Access，重新选择 `\(exact.id)` 对应的本地目录或文件，确保 modelPath 仍然有效。"
            lines[1] = "执行 `/models` 刷新当前模型列表。"
        }
        if let first = slashSuggestedCandidates(from: assessment).first {
            lines.append("如果只是想先继续工作，可临时切到 `/model \(first)`。")
        }
        return lines
    }

    func slashSuggestedCandidates(
        from assessment: HubModelAvailabilityAssessment?,
        configuredModelId: String? = nil,
        role: AXRole = .coder,
        ctx: AXProjectContext? = nil,
        snapshot: ModelStateSnapshot? = nil
    ) -> [String] {
        guard let assessment else { return [] }
        var seen = Set<String>()
        var result: [String] = []

        func append(_ raw: String?) {
            let id = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !id.isEmpty else { return }
            guard seen.insert(id.lowercased()).inserted else { return }
            result.append(id)
        }

        if let ctx, let snapshot,
           let guidance = AXProjectModelRouteMemoryStore.selectionGuidance(
                configuredModelId: configuredModelId ?? assessment.requestedId,
                role: role,
                ctx: ctx,
                snapshot: snapshot
           ) {
            append(guidance.recommendedModelId)
        }

        let source = assessment.loadedCandidates.isEmpty ? assessment.inventoryCandidates : assessment.loadedCandidates
        for model in source {
            append(model.id)
            if result.count >= 3 { break }
        }
        return result
    }

    func projectRouteDiagnosisText(
        ctx: AXProjectContext,
        config: AXProjectConfig?,
        router: LLMRouter,
        routeSnapshot: ModelStateSnapshot,
        localSnapshot: ModelStateSnapshot,
        supervisorRouteDecision: HubIPCClient.SupervisorRouteDecisionResult? = nil,
        transportMode: HubTransportMode = HubAIClient.transportMode()
    ) -> String {
        let projectOverride = config?.modelOverride(for: .coder)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let globalAssignment = router.preferredModelIdForHub(for: .coder, projectConfig: nil)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let supervisorAssignment = router.preferredModelIdForHub(for: .supervisor, projectConfig: nil)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let configuredModelId = configuredProjectModelID(for: .coder, config: config, router: router)
        let routeDecision = effectiveProjectRouteDecision(
            configuredModelId: configuredModelId,
            role: .coder,
            ctx: ctx,
            snapshot: routeSnapshot,
            localSnapshot: localSnapshot,
            transportMode: transportMode
        )
        let routeMemory = AXProjectModelRouteMemoryStore.load(for: ctx, role: .coder)
        let executionSnapshot = currentProjectExecutionSnapshot(ctx: ctx, role: .coder)
        let transport = transportMode
        let mismatch = projectModelMismatchSummary(
            configuredModelId: configuredModelId,
            snapshot: executionSnapshot,
            transport: transportMode
        )
        let remoteRetryPlan = projectRemoteRetryPlanSummary(
            ctx: ctx,
            routeDecision: routeDecision,
            routeSnapshot: routeSnapshot,
            transport: transport
        )

        var lines: [String] = [
            "项目路由诊断：coder",
            "配置来源：\(projectConfiguredModelSourceText(projectOverride: projectOverride, globalAssignment: globalAssignment))",
            "当前配置：\(configuredModelId.isEmpty ? "auto" : configuredModelId)",
            "当前传输模式：\(transport.rawValue)",
        ]

        if !configuredModelId.isEmpty {
            lines.append("配置状态：\(slashConfiguredModelStatusText(configuredModelId: configuredModelId, snapshot: routeSnapshot))")
        }

        lines.append("")
        lines.append("全局对照：")
        lines.append(
            projectGlobalRouteComparisonSummary(
                projectOverride: projectOverride,
                globalCoderAssignment: globalAssignment,
                supervisorAssignment: supervisorAssignment,
                snapshot: routeSnapshot
            )
        )
        if let splitSummary = projectSupervisorSplitSummary(
            projectOverride: projectOverride,
            globalCoderAssignment: globalAssignment,
            supervisorAssignment: supervisorAssignment,
            configuredModelId: configuredModelId,
            routeDecision: routeDecision,
            routeMemory: routeMemory,
            executionSnapshot: executionSnapshot,
            transport: transport
        ) {
            lines.append("分叉解释：\(splitSummary)")
        }
        lines.append("")
        lines.append("当前决策：\(projectRouteDecisionSummary(routeDecision, routeMemory: routeMemory, routeSnapshot: routeSnapshot, transport: transport))")
        lines.append("远端备选：\(remoteRetryPlan)")
        if let supervisorRouteDecision {
            lines.append("")
            lines.append("Supervisor 路由诊断：")
            lines.append(projectSupervisorRouteDiagnosisSummary(supervisorRouteDecision))
        }
        lines.append("")
        lines.append("路由记忆：")
        lines.append(projectRouteMemoryDiagnosisSummary(routeMemory))
        lines.append("")
        lines.append("最近路由异常 / 重试记录：")
        lines.append(projectRouteIncidentDiagnosisSummary(ctx))
        if let trend = projectRouteIncidentTrendDiagnosis(ctx) {
            lines.append("异常趋势：\(trend.summary)")
            if let actionHint = trend.actionHint,
               !actionHint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                lines.append("建议动作：\(actionHint)")
            }
        }
        lines.append("")
        lines.append("最近一次 coder 真实记录：")
        lines.append(
            projectExecutionSnapshotDiagnosis(
                configuredModelId: configuredModelId,
                snapshot: executionSnapshot,
                transport: transport
            )
        )
        if let auditHint = projectRouteHubAuditHint(executionSnapshot) {
            lines.append("Hub 审计锚点：\(auditHint)")
        }
        lines.append("")
        lines.append("判定：")
        lines.append(projectRouteDiagnosisConclusion(
            configuredModelId: configuredModelId,
            routeDecision: routeDecision,
            routeMemory: routeMemory,
            routeSnapshot: routeSnapshot,
            executionSnapshot: executionSnapshot,
            transport: transport,
            mismatchSummary: mismatch
        ))
        lines.append("")
        lines.append("提示：项目覆盖会优先于 coder 的全局分配；Supervisor 只看自己的全局分配，不读取项目覆盖或项目级路由记忆。要排除项目级影响，可先执行 `/model auto`。")
        return lines.joined(separator: "\n")
    }

    func currentProjectSupervisorRouteDecisionSnapshot(
        ctx: AXProjectContext,
        config: AXProjectConfig?
    ) async -> HubIPCClient.SupervisorRouteDecisionResult? {
        let transportMode = HubAIClient.transportMode()
        if transportMode == .fileIPC {
            return nil
        }
        if transportMode == .auto, !HubPairingCoordinator.hasHubEnvFast(stateDir: nil) {
            return nil
        }

        let effectiveConfig = config ?? AXProjectConfig.default(forProjectRoot: ctx.root)
        let governance = resolvedProjectPromptGovernance(ctx: ctx, config: effectiveConfig)
        let projectId = AXProjectRegistryStore.projectId(forRoot: ctx.root)
        let requireRunner = governance.configuredBundle.executionTier == .a4OpenClaw
            || governance.effectiveBundle.executionTier == .a4OpenClaw

        return await HubIPCClient.requestSupervisorRouteDecision(
            HubIPCClient.SupervisorRouteDecisionRequestPayload(
                requestId: "xt-route-diagnose-\(String(UUID().uuidString.lowercased().prefix(12)))",
                projectId: projectId,
                runId: nil,
                missionId: nil,
                surfaceType: "xt_ui",
                trustLevel: "paired_surface",
                normalizedIntentType: "directive",
                preferredDeviceId: nil,
                requireXT: true,
                requireRunner: requireRunner,
                actorRef: "xt.route_diagnose",
                conversationId: nil,
                threadKey: nil
            )
        )
    }

    func projectSupervisorRouteDiagnosisSummary(
        _ result: HubIPCClient.SupervisorRouteDecisionResult
    ) -> String {
        var lines: [String] = []
        let governanceHint = projectSupervisorRouteGovernanceHint(result)

        if let route = result.route {
            lines.append("- 决策=\(route.decision.isEmpty ? "(none)" : route.decision)")
            let denyCode = route.denyCode.trimmingCharacters(in: .whitespacesAndNewlines)
            if denyCode.isEmpty {
                lines.append("- deny code：(none)")
            } else {
                let denyDisplay = XTRouteTruthPresentation.denyCodeText(denyCode) ?? denyCode
                lines.append("- deny code：\(denyDisplay)")
            }
            if !route.auditRef.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                lines.append("- audit_ref=\(route.auditRef)")
            }
        } else {
            lines.append("- 决策=(unavailable)")
        }

        if let readiness = result.governanceRuntimeReadiness {
            let blockedKeys = readiness.blockedComponentKeys.map(\.rawValue)
            lines.append("- runtime readiness=\(readiness.summaryLine.isEmpty ? readiness.state.rawValue : readiness.summaryLine)")
            lines.append("- 阻塞平面=\(blockedKeys.isEmpty ? "(none)" : blockedKeys.joined(separator: ","))")
            if let governanceHint {
                lines.append("- 治理判断：\(governanceHint.summaryText)")
            }

            let blockedComponents = readiness.components.filter { $0.state == .blocked }
            for component in blockedComponents {
                let detail = projectSupervisorRouteComponentDetail(component)
                lines.append("- \(projectSupervisorRouteComponentLabel(component.key))：\(detail)")
            }

            if let nextStep = projectSupervisorRouteNextStep(
                readiness: readiness,
                route: result.route
            ) {
                lines.append("- 修复方向：\(nextStep)")
            }
        } else if let reasonCode = result.reasonCode,
                  !reasonCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("- 当前未拿到治理真相：\(reasonCode)")
        }

        return lines.joined(separator: "\n")
    }

    func projectSupervisorRouteComponentDetail(
        _ component: HubIPCClient.SupervisorRouteGovernanceComponentSnapshot
    ) -> String {
        let reasonSummary = component.missingReasonCodes
            .map { AXProjectGovernanceRuntimeReadinessSnapshot.reasonText($0) }
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: " / ")
        if !reasonSummary.isEmpty {
            return reasonSummary
        }
        if !component.summaryLine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return component.summaryLine
        }
        let denyCode = component.denyCode.trimmingCharacters(in: .whitespacesAndNewlines)
        return denyCode.isEmpty ? component.state.displayName : denyCode
    }

    func projectSupervisorRouteComponentLabel(
        _ key: AXProjectGovernanceRuntimeReadinessComponentKey
    ) -> String {
        switch key {
        case .routeReady:
            return "route plane"
        case .capabilityReady:
            return "capability plane"
        case .grantReady:
            return "grant plane"
        case .checkpointRecoveryReady:
            return "checkpoint / recovery plane"
        case .evidenceExportReady:
            return "evidence / export plane"
        }
    }

    func projectSupervisorRouteNextStep(
        readiness: HubIPCClient.SupervisorRouteGovernanceRuntimeReadinessSnapshot,
        route: HubIPCClient.SupervisorRouteDecisionSnapshot?
    ) -> String? {
        let blockedKeys = readiness.blockedComponentKeys
        if blockedKeys.isEmpty {
            return "Hub 这侧的 Supervisor route / grant 已就绪；接下来优先看当前 project 自己的 route truth、拒绝原因和执行证据。"
        }
        if let governanceHint = XTRouteTruthPresentation.supervisorRouteGovernanceHint(
            routeReasonCode: route?.denyCode,
            denyCode: route?.denyCode
        ) {
            return governanceHint.repairHintText
        }
        if blockedKeys.contains(.routeReady) {
            return "先检查 XT 是否在线、preferred device 是否仍可达，以及 project scope 是否一致。"
        }
        if blockedKeys.contains(.grantReady) {
            return "先检查 trusted automation、permission owner、kill-switch、TTL 和当前 project 绑定。"
        }
        if blockedKeys.contains(.checkpointRecoveryReady) {
            return "先检查事件能力和恢复链是否已接好。"
        }
        if blockedKeys.contains(.evidenceExportReady) {
            return "先检查 memory/export gate 和审计导出链。"
        }
        if let route, !route.denyCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let denyDisplay = XTRouteTruthPresentation.denyCodeText(route.denyCode) ?? route.denyCode
            return "先围绕 \(denyDisplay) 这条阻塞继续排查。"
        }
        return nil
    }

    func projectSupervisorRouteGovernanceHint(
        _ result: HubIPCClient.SupervisorRouteDecisionResult
    ) -> XTSupervisorRouteGovernanceHint? {
        let reason = result.route?.denyCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackReason = result.reasonCode?.trimmingCharacters(in: .whitespacesAndNewlines)
        return XTRouteTruthPresentation.supervisorRouteGovernanceHint(
            routeReasonCode: (reason?.isEmpty == false ? reason : fallbackReason),
            denyCode: (reason?.isEmpty == false ? reason : nil)
        )
    }

    func projectRouteHubAuditHint(_ snapshot: AXRoleExecutionSnapshot) -> String? {
        let auditRef = snapshot.auditRef.trimmingCharacters(in: .whitespacesAndNewlines)
        let denyCode = snapshot.denyCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let reason = effectiveProjectFailureReasonCode(
            fallbackReasonCode: snapshot.fallbackReasonCode,
            denyCode: snapshot.denyCode
        )

        guard !auditRef.isEmpty || !denyCode.isEmpty else {
            return nil
        }

        var tokens: [String] = []
        if !auditRef.isEmpty {
            tokens.append("审计锚点：\(auditRef)")
        }
        if !denyCode.isEmpty {
            let displayDenyCode = XTGuardrailMessagePresentation.displayDenyCode(denyCode)
            tokens.append("拒绝原因：\(displayDenyCode)")
        }

        let evidence = tokens.joined(separator: "；")
        switch reason {
        case "remote_export_blocked":
            return "\(evidence)。去 Hub Recovery / Hub 审计优先查 `remote_export_blocked`。"
        case "downgrade_to_local":
            return "\(evidence)。去 Hub 审计优先查 `ai.generate.downgraded_to_local`。"
        case "model_not_found", "remote_model_not_found":
            return "\(evidence)。去 Supervisor Control Center · AI 模型 / Hub 审计优先核对目标模型是否真的可执行。"
        default:
            return "\(evidence)。去 Hub 审计优先按这条证据查。"
        }
    }

    func projectConfiguredModelSourceText(
        projectOverride: String,
        globalAssignment: String
    ) -> String {
        if !projectOverride.isEmpty {
            return "项目覆盖（当前项目单独配置）"
        }
        if !globalAssignment.isEmpty {
            return "全局角色分配"
        }
        return "默认自动选择（没有固定模型 ID）"
    }

    func projectGlobalRouteComparisonSummary(
        projectOverride: String,
        globalCoderAssignment: String,
        supervisorAssignment: String,
        snapshot: ModelStateSnapshot
    ) -> String {
        var lines: [String] = [
            "- Project AI 全局分配：\(displayRouteValue(globalCoderAssignment.isEmpty ? "auto" : globalCoderAssignment))",
            "- Project AI 全局状态：\(globalAssignmentStatusText(globalCoderAssignment, snapshot: snapshot))",
        ]

        if let issue = HubModelSelectionAdvisor.globalAssignmentIssue(
            for: .coder,
            configuredModelId: globalCoderAssignment,
            snapshot: snapshot
        ) {
            lines.append("- Project AI 全局问题：\(singleLineRouteMessage(issue.message))")
        }

        lines.append("- Supervisor 全局分配：\(displayRouteValue(supervisorAssignment.isEmpty ? "auto" : supervisorAssignment))")
        lines.append("- Supervisor 全局状态：\(globalAssignmentStatusText(supervisorAssignment, snapshot: snapshot))")

        if let issue = HubModelSelectionAdvisor.globalAssignmentIssue(
            for: .supervisor,
            configuredModelId: supervisorAssignment,
            snapshot: snapshot
        ) {
            lines.append("- Supervisor 全局问题：\(singleLineRouteMessage(issue.message))")
        }

        lines.append(
            "- 关系说明：\(projectGlobalRouteRelationText(projectOverride: projectOverride, globalCoderAssignment: globalCoderAssignment, supervisorAssignment: supervisorAssignment))"
        )
        return lines.joined(separator: "\n")
    }

    func globalAssignmentStatusText(
        _ configuredModelId: String,
        snapshot: ModelStateSnapshot
    ) -> String {
        let trimmed = configuredModelId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "未固定，按默认 Hub 路由。"
        }
        return slashConfiguredModelStatusText(configuredModelId: trimmed, snapshot: snapshot)
    }

    func projectGlobalRouteRelationText(
        projectOverride: String,
        globalCoderAssignment: String,
        supervisorAssignment: String
    ) -> String {
        let trimmedProjectOverride = projectOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCoderAssignment = globalCoderAssignment.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSupervisorAssignment = supervisorAssignment.trimmingCharacters(in: .whitespacesAndNewlines)

        if !trimmedProjectOverride.isEmpty {
            if trimmedCoderAssignment.isEmpty {
                return "当前项目有项目覆盖；它会直接盖过 coder 的默认 Hub 路由。Supervisor 仍只看自己的全局分配。"
            }
            return "当前项目有项目覆盖；它会盖过 coder 全局分配 `\(trimmedCoderAssignment)`。Supervisor 仍只看自己的全局分配。"
        }

        if trimmedCoderAssignment.isEmpty && trimmedSupervisorAssignment.isEmpty {
            return "coder 和 Supervisor 都没有固定全局分配；两边是否命中远端，主要取决于各自当轮的 Hub 路由与执行链状态。"
        }
        if trimmedCoderAssignment.isEmpty {
            return "当前项目的 coder 没有固定全局分配，但 Supervisor 有自己的全局分配；两边本来就不一定一致。"
        }
        if trimmedSupervisorAssignment.isEmpty {
            return "Supervisor 当前没有固定全局分配，但项目里的 coder 有自己的全局分配；两边本来就不一定一致。"
        }
        if projectModelIdentitiesMatch(trimmedCoderAssignment, trimmedSupervisorAssignment) {
            return "Supervisor 和 project coder 的全局分配一致；如果两边表现不同，通常是项目级路由记忆、本地锁定或项目最近执行记录触发了回落。"
        }
        return "Supervisor 和 project coder 的全局分配不同，这本身就会导致两边命中模型不一致。"
    }

    func projectSupervisorSplitSummary(
        projectOverride: String,
        globalCoderAssignment: String,
        supervisorAssignment: String,
        configuredModelId rawConfiguredModelId: String,
        routeDecision: AXProjectPreferredModelRouteDecision,
        routeMemory: AXProjectModelRouteMemory?,
        executionSnapshot: AXRoleExecutionSnapshot,
        transport: HubTransportMode
    ) -> String? {
        let trimmedProjectOverride = projectOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCoderAssignment = globalCoderAssignment.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSupervisorAssignment = supervisorAssignment.trimmingCharacters(in: .whitespacesAndNewlines)
        let configuredModelId = rawConfiguredModelId.trimmingCharacters(in: .whitespacesAndNewlines)

        let overrideChangesProjectRoute: Bool = {
            guard !trimmedProjectOverride.isEmpty else { return false }
            if !trimmedCoderAssignment.isEmpty {
                return !projectModelIdentitiesMatch(trimmedProjectOverride, trimmedCoderAssignment)
            }
            if !trimmedSupervisorAssignment.isEmpty {
                return !projectModelIdentitiesMatch(trimmedProjectOverride, trimmedSupervisorAssignment)
            }
            return true
        }()

        if overrideChangesProjectRoute {
            return "如果你看到 Supervisor 和 project coder 不一致，先看项目覆盖：当前项目已经单独覆盖到 `\(trimmedProjectOverride)`；Supervisor 不读取这个项目级覆盖。"
        }

        guard !trimmedCoderAssignment.isEmpty,
              !trimmedSupervisorAssignment.isEmpty,
              projectModelIdentitiesMatch(trimmedCoderAssignment, trimmedSupervisorAssignment) else {
            return nil
        }

        let targetModelId = configuredModelId.isEmpty ? trimmedCoderAssignment : configuredModelId
        let effectiveReason = effectiveProjectFailureReasonCode(
            fallbackReasonCode: executionSnapshot.fallbackReasonCode,
            denyCode: executionSnapshot.denyCode,
            secondaryReasonCode: routeDecision.reasonCode ?? ""
        )
        let executionPath = executionSnapshot.executionPath
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if routeDecision.forceLocalExecution {
            let localModelId = (routeDecision.preferredLocalModelId ?? routeDecision.preferredModelId)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let localLabel = localModelId.isEmpty ? "本地模型" : "`\(localModelId)`"
            let reasonSuffix = routeMemory.flatMap {
                projectRouteFailureReasonParenthesized($0.lastFailureReasonCode, recent: true)
            } ?? ""
            return "如果你看到 Supervisor 还能继续按 `\(trimmedSupervisorAssignment)` 尝试、但 project coder 先落到本地，首因更像是这个项目自己的项目级路由记忆 / 本地锁：当前项目已先锁到 \(localLabel)\(reasonSuffix)，而 Supervisor 不读取这份项目级记忆。"
        }

        if routeDecision.usedRememberedRemoteModel,
           let remembered = routeDecision.preferredModelId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !remembered.isEmpty,
           !projectModelIdentitiesMatch(remembered, targetModelId) {
            return "如果你看到 Supervisor 还能继续按 `\(trimmedSupervisorAssignment)` 尝试、但 project coder 没命中 `\(targetModelId)`，首因更像是这个项目当前会先改试上次稳定远端 `\(remembered)`；Supervisor 不使用这份项目级路由记忆。"
        }

        guard transport == .grpc else { return nil }

        switch effectiveReason {
        case "remote_export_blocked",
             "device_remote_export_denied",
             "policy_remote_denied",
             "budget_remote_denied",
             "remote_disabled_by_user_pref":
            return "如果你看到 Supervisor 还能继续按 `\(trimmedSupervisorAssignment)` 尝试、但 project coder 这轮仍落到本地，更像是项目聊天这条执行链里发往 `\(targetModelId)` 的项目提示词 / 记忆导出被 Hub remote export gate 挡住了；Supervisor 不读取项目级路由记忆，实际上下文链也不会完全一样。"
        case "downgrade_to_local":
            return "如果你看到 Supervisor 还能继续按 `\(trimmedSupervisorAssignment)` 尝试、但 project coder 这轮落到本地，更像是 Hub 在执行阶段把这条 project 请求降到了本地，不是 XT 把模型静默改掉。"
        case "blocked_waiting_upstream",
             "provider_not_ready",
             "grpc_route_unavailable",
             "runtime_not_running",
             "request_write_failed",
             "response_timeout",
             "remote_timeout",
             "remote_unreachable":
            return "如果你看到 Supervisor 还能继续按 `\(trimmedSupervisorAssignment)` 尝试、但 project coder 这轮落到本地，更像是项目聊天这条执行链在远端阶段没 ready 或执行失败后由本地兜底；先看当前回落原因、Hub 链路和 provider 就绪状态。"
        default:
            break
        }

        switch executionPath {
        case "hub_downgraded_to_local":
            return "如果你看到 Supervisor 还能继续按 `\(trimmedSupervisorAssignment)` 尝试、但 project coder 这轮落到本地，更像是 Hub 在执行阶段把这条 project 请求改派到了本地，不是 XT 把模型静默改掉。"
        case "local_fallback_after_remote_error":
            return "如果你看到 Supervisor 还能继续按 `\(trimmedSupervisorAssignment)` 尝试、但 project coder 这轮落到本地，更像是项目聊天这条执行链的远端失败后由本地兜底；先看当前回落原因、Hub 链路和 provider 就绪状态。"
        default:
            return nil
        }
    }

    func singleLineRouteMessage(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func shouldExplainGrpcConfiguredRemoteVerification(
        configuredModelId rawConfiguredModelId: String,
        routeDecision: AXProjectPreferredModelRouteDecision,
        routeMemory: AXProjectModelRouteMemory?,
        routeSnapshot: ModelStateSnapshot?,
        transport: HubTransportMode
    ) -> Bool {
        guard transport == .grpc else { return false }

        let configuredModelId = rawConfiguredModelId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !configuredModelId.isEmpty else { return false }

        if routeDecision.reasonCode == "grpc_preserve_configured_model" {
            return true
        }

        guard !routeDecision.forceLocalExecution,
              !routeDecision.usedRememberedRemoteModel,
              let routeMemory,
              routeMemory.shouldSuggestLocalModeNotice,
              let routeSnapshot else {
            return false
        }

        return AXProjectModelRouteMemoryStore.isDirectlyRunnable(
            assessment: HubModelSelectionAdvisor.assess(
                requestedId: configuredModelId,
                snapshot: routeSnapshot
            )
        )
    }

    func projectRouteDecisionSummary(
        _ decision: AXProjectPreferredModelRouteDecision,
        routeMemory: AXProjectModelRouteMemory? = nil,
        routeSnapshot: ModelStateSnapshot? = nil,
        transport: HubTransportMode = HubAIClient.transportMode()
    ) -> String {
        let configured = decision.configuredModelId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if shouldExplainGrpcConfiguredRemoteVerification(
            configuredModelId: configured,
            routeDecision: decision,
            routeMemory: routeMemory,
            routeSnapshot: routeSnapshot,
            transport: transport
        ) {
            return "当前传输模式是 grpc-only；XT 会保留配置的远端模型继续验证：\(configured)"
        }
        if decision.forceLocalExecution {
            let localModel = (decision.preferredLocalModelId ?? decision.preferredModelId)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown_local_model"
            let reasonSuffix = projectRouteDecisionReasonSuffix(decision.reasonCode)
            return "XT 当前会先锁本地：\(localModel)\(reasonSuffix)"
        }
        if decision.usedRememberedRemoteModel,
           let remembered = decision.preferredModelId?.trimmingCharacters(in: .whitespacesAndNewlines),
           let configured = decision.configuredModelId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !remembered.isEmpty {
            let reasonSuffix = projectRouteDecisionReasonSuffix(decision.reasonCode)
            if !configured.isEmpty,
               remembered.caseInsensitiveCompare(configured) != .orderedSame {
                return "当前配置还不能直接执行；XT 这轮会先自动试上次稳定远端：\(remembered)\(reasonSuffix)"
            }
            return "优先改试上次稳定远端：\(remembered)\(reasonSuffix)"
        }
        if let routeMemory,
           routeMemory.shouldSuggestLocalModeNotice,
           let routeSnapshot,
           let preferred = decision.preferredModelId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !preferred.isEmpty,
           let configured = decision.configuredModelId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !configured.isEmpty,
           AXProjectModelRouteMemoryStore.isDirectlyRunnable(
                assessment: HubModelSelectionAdvisor.assess(
                    requestedId: configured,
                    snapshot: routeSnapshot
                )
           ) {
            return "之前的本地锁已自动解除；当前按配置继续尝试：\(preferred)"
        }
        if let preferred = decision.preferredModelId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !preferred.isEmpty {
            return "按当前配置继续尝试：\(preferred)"
        }
        return "没有固定模型，按默认 Hub 路由执行。"
    }

    func projectRemoteRetryPlanSummary(
        ctx: AXProjectContext,
        routeDecision: AXProjectPreferredModelRouteDecision,
        routeSnapshot: ModelStateSnapshot,
        transport: HubTransportMode
    ) -> String {
        if routeDecision.forceLocalExecution {
            return "当前不启用。XT 已锁到本地执行，不会先试远端备选。"
        }
        if transport == .fileIPC {
            return "当前不启用。传输模式=fileIPC，本轮不会先试远端备选。"
        }
        if transport != .auto {
            return "当前不启用。只有自动模式下，项目级远端失败才会先试同族备选远端。"
        }
        guard let requestedModelId = routeDecision.preferredModelId?.trimmingCharacters(in: .whitespacesAndNewlines),
              !requestedModelId.isEmpty else {
            return "当前不适用。没有固定远端模型，仍按默认 Hub 路由决定。"
        }

        let projectId = AXProjectRegistryStore.projectId(forRoot: ctx.root)
        guard let backup = HubAIClient.preferredRemoteRetryBackupModelID(
            requestedModelId: requestedModelId,
            snapshot: routeSnapshot,
            transportMode: transport,
            projectId: projectId
        ), !backup.isEmpty else {
            return "当前没有可用的同族已加载远端备选；首选远端失败后会按现有回落规则处理。"
        }
        return "首选远端失败时，XT 会先改试同族已加载远端：\(backup)；如果仍失败，再按现有回落规则处理。"
    }

    func projectRouteMemoryDiagnosisSummary(_ routeMemory: AXProjectModelRouteMemory?) -> String {
        guard let routeMemory else {
            return "无可用项目级路由记忆。"
        }

        var lines: [String] = [
            "- 最近连续远端回落：\(routeMemory.consecutiveRemoteFallbackCount)",
            "- 最近请求模型：\(displayRouteValue(routeMemory.lastRequestedModelId))",
            "- 最近实际模型：\(displayRouteValue(routeMemory.lastActualModelId))",
            "- 最近执行路径：\(frontstageProjectExecutionPathText(routeMemory.lastExecutionPath))",
            "- 最近失败原因：\(displayRouteValue(projectRouteFailureReasonText(routeMemory.lastFailureReasonCode) ?? routeMemory.lastFailureReasonCode))",
        ]
        let lastHealthyRemote = routeMemory.lastHealthyRemoteModelId.trimmingCharacters(in: .whitespacesAndNewlines)
        if !lastHealthyRemote.isEmpty {
            lines.insert("- 最近稳定远端：\(lastHealthyRemote)", at: 1)
        }
        return lines.joined(separator: "\n")
    }

    func projectRouteIncidentDiagnosisSummary(_ ctx: AXProjectContext) -> String {
        let events = AXModelRouteDiagnosticsStore.recentEvents(for: ctx, limit: 3)
        guard !events.isEmpty else {
            return "无最近路由异常或远端重试记录。"
        }

        return events
            .map { "- \(frontstageProjectRouteIncidentSummary($0))" }
            .joined(separator: "\n")
    }

    func frontstageProjectRouteIncidentSummary(_ event: AXModelRouteDiagnosticEvent) -> String {
        var parts: [String] = []

        if !event.role.isEmpty {
            parts.append("角色：\(event.role)")
        }
        if !event.executionPath.isEmpty {
            parts.append("执行路径：\(frontstageProjectExecutionPathText(event.executionPath))")
        }
        if event.remoteRetryAttempted {
            let retryFrom = event.remoteRetryFromModelId.isEmpty ? event.requestedModelId : event.remoteRetryFromModelId
            if !retryFrom.isEmpty || !event.remoteRetryToModelId.isEmpty {
                let fromText = retryFrom.isEmpty ? "远端" : retryFrom
                let toText = event.remoteRetryToModelId.isEmpty ? "备用远端" : event.remoteRetryToModelId
                parts.append("远端改试：\(fromText) -> \(toText)")
            } else {
                parts.append("远端改试：已发生")
            }
            let retryReason = event.remoteRetryReasonCode.trimmingCharacters(in: .whitespacesAndNewlines)
            if !retryReason.isEmpty {
                parts.append("改试原因：\(projectRouteFailureReasonText(retryReason) ?? retryReason)")
            }
        }
        if !event.requestedModelId.isEmpty {
            parts.append("请求模型：\(event.requestedModelId)")
        }
        if !event.actualModelId.isEmpty {
            parts.append("实际模型：\(event.actualModelId)")
        }

        let effectiveReason = event.effectiveFailureReasonCode.trimmingCharacters(in: .whitespacesAndNewlines)
        if !effectiveReason.isEmpty {
            parts.append("原因：\(projectRouteFailureReasonText(effectiveReason) ?? effectiveReason)")
        }

        let denyCode = event.denyCode?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !denyCode.isEmpty,
           normalizedRouteReasonCode(denyCode) != normalizedRouteReasonCode(effectiveReason) {
            parts.append("拒绝原因：\(XTGuardrailMessagePresentation.displayDenyCode(denyCode))")
        }

        if !event.runtimeProvider.isEmpty {
            parts.append("执行提供方：\(event.runtimeProvider)")
        }
        if let auditRef = event.auditRef?.trimmingCharacters(in: .whitespacesAndNewlines),
           !auditRef.isEmpty {
            parts.append("审计锚点：\(auditRef)")
        }

        return parts.joined(separator: " · ")
    }

    func frontstageProjectExecutionPathText(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "（无）" }

        switch trimmed {
        case "remote_model":
            return "远端执行（remote_model）"
        case "hub_downgraded_to_local":
            return "Hub 改派到本地（hub_downgraded_to_local）"
        case "local_fallback_after_remote_error":
            return "远端失败后本地兜底（local_fallback_after_remote_error）"
        case "local_runtime":
            return "本地执行（local_runtime）"
        case "remote_error":
            return "远端阶段失败（remote_error）"
        case "direct_provider":
            return "直连提供方（direct_provider）"
        case "local_preflight":
            return "本地预检（local_preflight）"
        case "local_direct_reply":
            return "本地直答（local_direct_reply）"
        case "local_direct_action":
            return "本地直行动作（local_direct_action）"
        case "hub_brief_projection":
            return "Hub brief 投影（hub_brief_projection）"
        default:
            return trimmed
        }
    }

    func projectRouteIncidentTrendDiagnosis(_ ctx: AXProjectContext) -> ProjectRouteIncidentTrendDiagnosis? {
        let events = AXModelRouteDiagnosticsStore.recentEvents(for: ctx, limit: 6)
            .filter { $0.role.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == AXRole.coder.rawValue }
        guard !events.isEmpty else { return nil }

        let failureEvents = events.filter(\.isFailureIncident)
        if !failureEvents.isEmpty {
            let reasonCounts = countedRouteReasonCodes(in: failureEvents)

            if let remoteExportBlocked = reasonCounts["remote_export_blocked"], remoteExportBlocked > 0 {
                return ProjectRouteIncidentTrendDiagnosis(
                    summary: "最近 \(remoteExportBlocked) 次主要是 `remote_export_blocked`，更像 Hub 的 remote export gate 或策略直接拦住了 paid 远端，并改派到本地。",
                    actionHint: "先去 Hub Recovery / Hub 审计看 `remote_export_blocked`，不要先改 XT 的 project model。"
                )
            }
            if let downgradeToLocal = reasonCounts["downgrade_to_local"], downgradeToLocal > 0 {
                return ProjectRouteIncidentTrendDiagnosis(
                    summary: "最近 \(downgradeToLocal) 次主要是 `downgrade_to_local`，更像 Hub 在执行阶段主动把远端请求降到了本地，不是 XT 先锁本地。",
                    actionHint: "先查 Hub 侧 `ai.generate.downgraded_to_local` 或连接日志，再决定是否继续改 XT 路由。"
                )
            }
            if let modelNotFound = reasonCounts["model_not_found"], modelNotFound > 0 {
                return ProjectRouteIncidentTrendDiagnosis(
                    summary: "最近 \(modelNotFound) 次主要是 `model_not_found`，更像目标远端模型没加载、模型 ID 不匹配，或当前分配指向了不可执行模型。",
                    actionHint: "先去 Supervisor Control Center · AI 模型确认目标模型已进入真实可执行列表，再运行 `/models`；如果只是想先继续，先看当前项目的路由状态是否已提示会自动改试上次稳定远端。"
                )
            }
            if let remoteModelNotFound = reasonCounts["remote_model_not_found"], remoteModelNotFound > 0 {
                return ProjectRouteIncidentTrendDiagnosis(
                    summary: "最近 \(remoteModelNotFound) 次主要是 `remote_model_not_found`，更像 Hub 侧远端模型本身不可用；先查 Hub 的远端模型清单和导出状态。",
                    actionHint: "优先检查 Hub 远端模型是否真的存在、是否允许导出到当前会话。"
                )
            }
            let connectivityKeys = ["grpc_route_unavailable", "response_timeout", "runtime_not_running", "request_write_failed"]
            let connectivityCount = connectivityKeys.reduce(0) { partial, key in
                partial + (reasonCounts[key] ?? 0)
            }
            if connectivityCount > 0 {
                return ProjectRouteIncidentTrendDiagnosis(
                    summary: "最近 \(connectivityCount) 次主要是 Hub 链路或 runtime 异常（如 `grpc_route_unavailable` / `runtime_not_running`），更像连接问题，不是模型选择本身的问题。",
                    actionHint: "先重连 Hub 或恢复 runtime，再重跑一次 `/route diagnose`。"
                )
            }
        }

        let recoveryEvents = events.filter(\.isRemoteRetryRecovery)
        if !recoveryEvents.isEmpty {
            return ProjectRouteIncidentTrendDiagnosis(
                summary: "最近有 \(recoveryEvents.count) 次远端备选重试成功，说明 XT 还能在远端层改试同族已加载模型；不是所有 GPT 请求都会直接掉回本地。",
                actionHint: "如果你要严格验证指定 GPT 是否被精确命中，先切 `/hub route grpc` 再复现。"
            )
        }

        return nil
    }

    func countedRouteReasonCodes(in events: [AXModelRouteDiagnosticEvent]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for event in events {
            let key = normalizedRouteReasonCode(event.effectiveFailureReasonCode)
            guard !key.isEmpty else { continue }
            counts[key, default: 0] += 1
        }
        return counts
    }

    func normalizedRouteReasonCode(_ raw: String) -> String {
        raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
    }

    func effectiveProjectFailureReasonCode(
        fallbackReasonCode: String,
        denyCode: String,
        secondaryReasonCode: String = ""
    ) -> String {
        let fallback = normalizedRouteReasonCode(fallbackReasonCode)
        if !fallback.isEmpty {
            return fallback
        }

        let deny = normalizedRouteReasonCode(denyCode)
        if !deny.isEmpty {
            return deny
        }

        return normalizedRouteReasonCode(secondaryReasonCode)
    }

    func projectRouteTruthLines(
        configuredModelId: String,
        snapshot: AXRoleExecutionSnapshot,
        transport: HubTransportMode? = nil,
        includeConfiguredRoute: Bool = true,
        includeRouteState: Bool = true,
        includeTransport: Bool = true
    ) -> [String] {
        guard snapshot.hasRecord else { return [] }

        let configuredTarget = configuredModelId.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveConfiguredTarget = configuredTarget.isEmpty ? "auto" : configuredTarget
        let evidence = XTRouteTruthPresentation.evidence(
            configuredModelId: effectiveConfiguredTarget,
            snapshot: projectRouteTruthSnapshot(snapshot),
            transportMode: transport?.rawValue ?? ""
        )

        return [
            includeConfiguredRoute ? evidence.configuredRouteLine : nil,
            evidence.actualRouteLine,
            evidence.fallbackReasonLine,
            includeRouteState ? evidence.routeStateLine : nil,
            evidence.auditRefLine,
            evidence.denyCodeLine,
            includeTransport ? evidence.transportLine : nil
        ]
        .compactMap { line in
            let trimmed = line?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !trimmed.isEmpty else { return nil }
            return frontstageProjectRouteTruthLine(trimmed)
        }
    }

    func frontstageProjectRouteTruthLine(_ line: String) -> String {
        let replacements: [(String, String)] = [
            ("configured route=", "配置目标："),
            ("actual route=", "实际落点："),
            ("fallback reason=", "回落原因："),
            ("route state=", "路由状态："),
            ("audit_ref=", "审计锚点："),
            ("deny_code=", "拒绝原因："),
            ("paired_device_truth=", "配对设备约束："),
            ("transport=", "传输模式：")
        ]

        for (prefix, replacement) in replacements where line.hasPrefix(prefix) {
            return replacement + String(line.dropFirst(prefix.count))
        }
        return line
    }

    func projectRouteTruthSnapshot(_ snapshot: AXRoleExecutionSnapshot) -> AXRoleExecutionSnapshot {
        var normalized = snapshot
        normalized.fallbackReasonCode = effectiveProjectFailureReasonCode(
            fallbackReasonCode: snapshot.fallbackReasonCode,
            denyCode: snapshot.denyCode
        )
        return normalized
    }

    func projectUsageRouteTruthSnapshot(_ usage: LLMUsage?) -> AXRoleExecutionSnapshot {
        func trimmed(_ raw: String?) -> String {
            (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return AXRoleExecutionSnapshot(
            role: .coder,
            updatedAt: usage == nil ? 0 : 1,
            stage: "",
            requestedModelId: trimmed(usage?.requestedModelId),
            actualModelId: trimmed(usage?.actualModelId),
            runtimeProvider: trimmed(usage?.runtimeProvider),
            executionPath: trimmed(usage?.executionPath),
            fallbackReasonCode: effectiveProjectFailureReasonCode(
                fallbackReasonCode: trimmed(usage?.fallbackReasonCode),
                denyCode: trimmed(usage?.denyCode)
            ),
            auditRef: trimmed(usage?.auditRef),
            denyCode: trimmed(usage?.denyCode),
            remoteRetryAttempted: usage?.remoteRetryAttempted ?? false,
            remoteRetryFromModelId: trimmed(usage?.remoteRetryFromModelId),
            remoteRetryToModelId: trimmed(usage?.remoteRetryToModelId),
            remoteRetryReasonCode: trimmed(usage?.remoteRetryReasonCode),
            source: "llm_usage"
        )
    }

    func projectExecutionSnapshotDiagnosis(
        configuredModelId: String,
        snapshot: AXRoleExecutionSnapshot,
        transport: HubTransportMode
    ) -> String {
        guard snapshot.hasRecord else {
            return "- 暂无真实调用记录"
        }

        var lines: [String] = [
            "- 请求模型：\(displayRouteValue(snapshot.requestedModelId))",
            "- 实际模型：\(displayRouteValue(snapshot.actualModelId))",
        ]
        lines.append(
            contentsOf: projectRouteTruthLines(
                configuredModelId: configuredModelId,
                snapshot: snapshot,
                transport: transport
            ).map { "- \($0)" }
        )
        if snapshot.remoteRetryAttempted {
            lines.append("- 发生过远端改试：是")
        }
        if !snapshot.remoteRetryFromModelId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("- 远端改试起点：\(snapshot.remoteRetryFromModelId)")
        }
        if !snapshot.remoteRetryToModelId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("- 远端改试目标：\(snapshot.remoteRetryToModelId)")
        }
        if !snapshot.remoteRetryReasonCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let retryReasonText =
                projectRouteFailureReasonText(snapshot.remoteRetryReasonCode) ?? snapshot.remoteRetryReasonCode
            lines.append("- 远端改试原因：\(retryReasonText)")
        }
        if !snapshot.stage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("- 记录阶段：\(snapshot.stage)")
        }
        return lines.joined(separator: "\n")
    }

    func projectRouteDiagnosisConclusion(
        configuredModelId: String,
        routeDecision: AXProjectPreferredModelRouteDecision,
        routeMemory: AXProjectModelRouteMemory?,
        routeSnapshot: ModelStateSnapshot,
        executionSnapshot: AXRoleExecutionSnapshot,
        transport: HubTransportMode,
        mismatchSummary: String?
    ) -> String {
        if shouldExplainGrpcConfiguredRemoteVerification(
            configuredModelId: configuredModelId,
            routeDecision: routeDecision,
            routeMemory: routeMemory,
            routeSnapshot: routeSnapshot,
            transport: transport
        ) {
            return "XT 当前处于 grpc-only 验证模式；这轮会继续按 `\(configuredModelId)` 发起远端请求，不再让项目级本地锁或上次稳定远端抢路由。如果你之后仍看到本地接管，优先去查 Hub 执行阶段 downgrade 或远端 export gate。"
        }
        if routeDecision.forceLocalExecution {
            return "XT 当前仍会优先走本地。这通常表示近期远端连续没有稳定命中，且当前配置模型和上次稳定远端都还不可直接执行。先检查 Supervisor Control Center · AI 模型里的真实可执行状态，再用 `/models` 或重新 `/model <id>` 验证。"
        }
        if routeDecision.usedRememberedRemoteModel,
           let remembered = routeDecision.preferredModelId?.trimmingCharacters(in: .whitespacesAndNewlines),
           let configured = routeDecision.configuredModelId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !remembered.isEmpty,
           !configured.isEmpty,
           remembered.caseInsensitiveCompare(configured) != .orderedSame {
            return "XT 当前不会再直接掉回本地；因为 `\(configured)` 还不能直接执行，这轮会先自动试上次稳定远端 `\(remembered)`。如果你要验证原目标是否已恢复，先去 Supervisor Control Center · AI 模型确认后再试。"
        }
        if let routeMemory,
           routeMemory.shouldSuggestLocalModeNotice,
           !configuredModelId.isEmpty,
           AXProjectModelRouteMemoryStore.isDirectlyRunnable(
                assessment: HubModelSelectionAdvisor.assess(
                    requestedId: configuredModelId,
                    snapshot: routeSnapshot
                )
           ) {
            if transport == .fileIPC {
                return "从 XT 这层看，之前因连续回落触发的项目级本地锁已经解除；只是当前传输模式是 fileIPC，所以这轮本来就不会强制走远端。先把传输模式切回 `/hub route auto` 或 `/hub route grpc` 再验证。"
            }
            if let mismatchSummary, !mismatchSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return mismatchSummary
            }
            return "从 XT 这层看，之前因连续回落触发的项目级本地锁已经解除；当前项目会按 `\(configuredModelId)` 正常继续尝试。如果你仍看到本地接管，优先去查 Hub 审计或执行阶段 downgrade。"
        }
        if transport == .fileIPC {
            return "XT 当前传输模式是 fileIPC，所以这轮本来就不会强制走远端。先把传输模式切回 `/hub route auto` 或 `/hub route grpc` 再验证。"
        }
        if let mismatchSummary, !mismatchSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return mismatchSummary
        }
        if executionSnapshot.executionPath == "hub_downgraded_to_local" {
            return "XT 当前没有再主动锁本地；如果下一轮仍被本地接管，更可能是 Hub 侧在执行时触发了 downgrade_to_local。"
        }
        if configuredModelId.isEmpty {
            return "当前没有固定模型 ID，XT 只会按默认 Hub 路由尝试，不存在项目级强制锁本地。"
        }
        return "从 XT 这层看，当前项目没有被历史项目级路由记忆卡在本地；如果你仍看到本地接管，优先去查 Hub 审计或项目级覆盖是否被重新写入。"
    }

    func displayRouteValue(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "(none)" : trimmed
    }

    func projectRouteFailureReasonText(_ raw: String?) -> String? {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return XTRouteTruthPresentation.routeReasonDisplayText(trimmed, language: .defaultPreference)
            ?? XTRouteTruthPresentation.denyCodeText(trimmed, language: .defaultPreference)
            ?? trimmed
    }

    func projectRouteFailureReasonOrRaw(_ raw: String?) -> String? {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return projectRouteFailureReasonText(trimmed) ?? trimmed
    }

    func projectRouteFailureReasonParenthesized(
        _ raw: String?,
        recent: Bool = false
    ) -> String {
        guard let reason = projectRouteFailureReasonText(raw),
              !reason.isEmpty else {
            return ""
        }
        return recent ? "（最近原因：\(reason)）" : "（原因：\(reason)）"
    }

    func projectRouteDecisionReasonText(_ raw: String?) -> String? {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        switch trimmed {
        case "project_last_remote_success_loaded":
            return "当前配置还不能直接执行，XT 先试上次稳定且仍已加载的远端（project_last_remote_success_loaded）"
        case "project_last_remote_success_inventory":
            return "当前配置还不能直接执行，XT 先试上次稳定且仍在候选列表中的远端（project_last_remote_success_inventory）"
        case "project_configured_model_retrieval_only":
            return "当前配置是非对话模型，不作为当前角色的对话模型（project_configured_model_retrieval_only）"
        case "project_remote_fallback_lock_local_recent_actual":
            return "当前配置和上次稳定远端都还不能直接执行，XT 暂时沿用最近本地接管结果（project_remote_fallback_lock_local_recent_actual）"
        case "project_remote_fallback_lock_local_loaded":
            return "当前配置和上次稳定远端都还不能直接执行，XT 暂时锁到当前已加载本地模型（project_remote_fallback_lock_local_loaded）"
        default:
            return trimmed
        }
    }

    func projectRouteDecisionReasonSuffix(_ raw: String?) -> String {
        guard let reason = projectRouteDecisionReasonText(raw),
              !reason.isEmpty else {
            return ""
        }
        return "，原因：\(reason)"
    }


    func isRemoteModelForSlash(_ m: HubModel) -> Bool {
        let mp = (m.modelPath ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !mp.isEmpty { return false }
        return m.backend.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() != "mlx"
    }

}
