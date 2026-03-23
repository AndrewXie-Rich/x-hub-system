import Foundation

struct XTSettingsGuidanceItem: Equatable, Identifiable, Sendable {
    var id: String
    var title: String
    var detail: String
}

struct XTModelGuidancePresentation: Equatable, Sendable {
    var inventorySummary: String
    var items: [XTSettingsGuidanceItem]
    var routeMemoryHint: String?

    static func build(
        settings: XTerminalSettings,
        snapshot: ModelStateSnapshot,
        currentProjectName: String? = nil,
        currentProjectContext: AXProjectContext? = nil,
        currentProjectCoderModelId: String? = nil
    ) -> XTModelGuidancePresentation {
        let interactiveLoaded = snapshot.models.filter { $0.state == .loaded && $0.isSelectableForInteractiveRouting }
        let remoteLoaded = interactiveLoaded.filter { !$0.isLocalModel }
        let localLoaded = interactiveLoaded.filter(\.isLocalModel)
        let supportLoadedCount = snapshot.models.filter { $0.state == .loaded && !$0.isSelectableForInteractiveRouting }.count

        let inventorySummary: String
        if snapshot.models.isEmpty {
            inventorySummary = "当前还没有拿到 Hub 模型快照；先刷新模型列表，或去 Hub -> Models 确认模型是否真的已加载。"
        } else if interactiveLoaded.isEmpty {
            inventorySummary = "当前 inventory 已同步，但没有已加载的可对话模型；先在 Hub -> Models 至少加载 1 个对话模型，否则角色容易回退到本地或无法执行。"
        } else {
            var parts = [
                "当前已加载可对话模型：远端 \(remoteLoaded.count) 个",
                "本地 \(localLoaded.count) 个"
            ]
            if supportLoadedCount > 0 {
                parts.append("辅助模型 \(supportLoadedCount) 个")
            }
            inventorySummary = parts.joined(separator: "，") + "。"
        }

        var items: [XTSettingsGuidanceItem] = [
            XTSettingsGuidanceItem(
                id: "coder",
                title: "Coder 选型",
                detail: "优先选已加载、能直接对话执行的模型；如果当前项目最近老是掉到本地，先切回已加载的稳定备选最稳。"
            ),
            XTSettingsGuidanceItem(
                id: "supervisor",
                title: "Supervisor 选型",
                detail: "更看重稳定长对话、计划审查质量和持续可用性；不要把检索/语音专用模型绑成 Supervisor 聊天模型。"
            )
        ]

        if snapshot.models.isEmpty {
            items.append(
                XTSettingsGuidanceItem(
                    id: "snapshot_missing",
                    title: "当前状态",
                    detail: "这时先不要盲填模型 ID。没有快照时很难判断是模型没加载、被休眠，还是只是名称写错。"
                )
            )
        } else if interactiveLoaded.isEmpty {
            items.append(
                XTSettingsGuidanceItem(
                    id: "no_interactive_loaded",
                    title: "当前状态",
                    detail: "先确保至少有 1 个已加载的对话模型，再来配置各个角色；否则很多路由建议都只是纸面上的。"
                )
            )
        } else if remoteLoaded.isEmpty {
            items.append(
                XTSettingsGuidanceItem(
                    id: "local_only",
                    title: "当前状态",
                    detail: "现在只有本地对话模型在工作；如果你预期用远端 GPT，这通常说明 Hub 侧远端模型还没真正 ready。"
                )
            )
        } else if localLoaded.isEmpty {
            items.append(
                XTSettingsGuidanceItem(
                    id: "no_local_fallback",
                    title: "当前状态",
                    detail: "现在没有本地对话兜底；远端失联时弹性会更差，必要时可以保留一个本地模型做 fallback。"
                )
            )
        }

        if supportLoadedCount > 0 {
            items.append(
                XTSettingsGuidanceItem(
                    id: "support_models",
                    title: "辅助模型",
                    detail: "检索 / embedding / TTS 这类模型会由系统按需调用；它们显示在 inventory 里，不代表适合手动绑到聊天角色上。"
                )
            )
        }

        let configuredCoderModelId = normalized(currentProjectCoderModelId)
            ?? normalized(settings.assignment(for: .coder).model)
        let routeMemoryHint: String? = {
            guard let currentProjectContext,
                  let guidance = AXProjectModelRouteMemoryStore.selectionGuidance(
                    configuredModelId: configuredCoderModelId,
                    role: .coder,
                    ctx: currentProjectContext,
                    snapshot: snapshot
                  ) else {
                return nil
            }
            let projectPrefix = normalized(currentProjectName).map { "当前项目 \($0)：" } ?? "当前项目："
            return projectPrefix + guidance.warningText
        }()

        return XTModelGuidancePresentation(
            inventorySummary: inventorySummary,
            items: items,
            routeMemoryHint: routeMemoryHint
        )
    }

    private static func normalized(_ raw: String?) -> String? {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct XTSecurityRuntimeGuidancePresentation: Equatable, Sendable {
    var items: [XTSettingsGuidanceItem]

    static func build(
        sandboxMode: ToolSandboxMode,
        workMode: XTSupervisorWorkMode,
        privacyMode: XTPrivacyMode
    ) -> XTSecurityRuntimeGuidancePresentation {
        let sandboxDetail: String
        switch sandboxMode {
        case .host:
            sandboxDetail = "当前默认走宿主执行；只有 tool call 明确写 `sandbox=true` 时才进沙箱。"
        case .sandbox:
            sandboxDetail = "当前默认走沙箱执行；只有 tool call 明确写 `sandbox=false` 时才回宿主。"
        }

        let automationDetail: String
        switch workMode {
        case .conversationOnly:
            automationDetail = "当前是对话模式；Supervisor 只回答你的明确请求，不会自己发起 coder / skill / tool 执行。"
        case .guidedProgress:
            automationDetail = "当前是推进模式；Supervisor 会给计划、提醒和下一步建议，但执行层面仍会收回到 manual。"
        case .governedAutomation:
            automationDetail = "当前是自动执行模式；只有 A-tier、S-tier、授权、runtime readiness 和 fail-closed gate 都允许时，才会继续自动执行。"
        }

        return XTSecurityRuntimeGuidancePresentation(
            items: [
                XTSettingsGuidanceItem(
                    id: "sandbox",
                    title: "默认工具路径",
                    detail: sandboxDetail
                ),
                XTSettingsGuidanceItem(
                    id: "auto_run",
                    title: "Auto-run tools",
                    detail: "这是项目聊天里的会话开关，不是全局放开；关闭时仍会先把工具调用列出来等你批准。"
                ),
                XTSettingsGuidanceItem(
                    id: "automation_guardrails",
                    title: "自动执行边界",
                    detail: automationDetail + " 高风险命令和能力不会因为你开了自动执行就直接放行。"
                ),
                XTSettingsGuidanceItem(
                    id: "privacy",
                    title: "隐私模式",
                    detail: "\(privacyMode.displayName)：\(privacyMode.summary)"
                )
            ]
        )
    }
}

struct XTSettingsChangeNotice: Equatable, Sendable {
    var title: String
    var detail: String
}

enum XTSettingsChangeNoticeBuilder {
    private static func roleModelStatusDetail(
        modelId: String,
        snapshot: ModelStateSnapshot
    ) -> String {
        let assessment = HubModelSelectionAdvisor.assess(
            requestedId: modelId,
            snapshot: snapshot
        )

        if let exact = assessment?.exactMatch,
           exact.state == .loaded {
            let sourceLabel = exact.isLocalModel ? "本地" : "远端"
            return "它当前已加载，且属于可直接对话的\(sourceLabel)模型，后续路由可以直接用。"
        }

        if let blocked = assessment?.nonInteractiveExactMatch {
            let reason = blocked.interactiveRoutingDisabledReason
                ?? "它不适合作为当前角色的对话模型。"
            return "但它属于非对话模型。\(reason) 建议直接改成一个已加载的对话模型。"
        }

        if let exact = assessment?.exactMatch {
            return "但它现在是 \(HubModelSelectionAdvisor.stateLabel(exact.state))；继续运行时可能会回退到本地，建议先在 Hub -> Models 加载它，或改用一个已加载候选。"
        }

        if assessment?.isMissingFromInventory == true {
            return "但当前 inventory 里没有精确匹配。建议先刷新模型列表，或直接改用即时提示里的候选模型。"
        }

        return "如果它没有真正 loaded，运行时仍可能回退到本地。"
    }

    static func supervisorWorkMode(_ mode: XTSupervisorWorkMode) -> XTSettingsChangeNotice {
        XTSettingsChangeNotice(
            title: "工作模式已更新",
            detail: {
                switch mode {
                case .conversationOnly:
                    return "已切到对话模式。Supervisor 现在只回答你的明确请求，不主动推进，也不会自己发起 coder / skill / tool。"
                case .guidedProgress:
                    return "已切到推进模式。Supervisor 会主动给计划、提醒和下一步建议，但先给方案，不会自己直接开跑。"
                case .governedAutomation:
                    return "已切到自动执行模式。只要治理、授权和 runtime 都允许，Supervisor 就可以在边界内继续自动推进。"
                }
            }()
        )
    }

    static func supervisorPrivacyMode(
        _ mode: XTPrivacyMode,
        configuredProfile: XTSupervisorRecentRawContextProfile
    ) -> XTSettingsChangeNotice {
        let effectiveProfile = mode.effectiveRecentRawContextProfile(configuredProfile)
        let detail: String
        switch mode {
        case .balanced:
            detail = "已切到平衡模式。最近原始对话会按你配置的档位工作，Hub 长期记忆、handoff capsule 和状态重建保持不变。"
        case .tightenedContext:
            if effectiveProfile == configuredProfile {
                detail = "已切到收紧模式。最近原始对话会更偏向摘要而不是复述原话，Hub 长期记忆和 handoff 不受影响。"
            } else {
                detail = "已切到收紧模式。最近原始对话会从 \(configuredProfile.displayName) · \(configuredProfile.shortLabel) 收束到 \(effectiveProfile.displayName) · \(effectiveProfile.shortLabel)，但 Hub 长期记忆和 handoff 不受影响。"
            }
        }
        return XTSettingsChangeNotice(
            title: "隐私模式已更新",
            detail: detail
        )
    }

    static func supervisorRecentRawContext(
        profile: XTSupervisorRecentRawContextProfile,
        privacyMode: XTPrivacyMode
    ) -> XTSettingsChangeNotice {
        let effectiveProfile = privacyMode.effectiveRecentRawContextProfile(profile)
        let detail: String
        if effectiveProfile == profile {
            detail = "最近原始上下文已设为 \(profile.displayName) · \(profile.shortLabel)。这个改动只影响 recent raw dialogue，不会动长期记忆内核。"
        } else {
            detail = "最近原始上下文已设为 \(profile.displayName) · \(profile.shortLabel)，但当前隐私模式会实际按 \(effectiveProfile.displayName) · \(effectiveProfile.shortLabel) 执行。"
        }
        return XTSettingsChangeNotice(
            title: "最近原始上下文已更新",
            detail: detail
        )
    }

    static func defaultToolSandboxMode(_ mode: ToolSandboxMode) -> XTSettingsChangeNotice {
        XTSettingsChangeNotice(
            title: "默认工具路径已更新",
            detail: {
                switch mode {
                case .host:
                    return "默认工具执行路径已切到 Host。Auto-run 仍会受项目授权、runtime readiness 和 fail-closed gate 约束。"
                case .sandbox:
                    return "默认工具执行路径已切到 Sandbox。Auto-run 仍会受项目授权、runtime readiness 和 fail-closed gate 约束。"
                }
            }()
        )
    }

    static func globalRoleModel(
        role: AXRole,
        modelId rawModelId: String?,
        snapshot: ModelStateSnapshot
    ) -> XTSettingsChangeNotice {
        let modelId = (rawModelId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !modelId.isEmpty else {
            return XTSettingsChangeNotice(
                title: "\(role.displayName) 模型已清空",
                detail: "已清空 \(role.displayName) 的默认 Hub 模型。系统之后会重新按 inventory 和路由策略挑候选；继续前建议至少把 coder 和 supervisor 配完整。"
            )
        }

        return XTSettingsChangeNotice(
            title: "\(role.displayName) 模型已更新",
            detail: "已把 \(role.displayName) 默认模型设为 `\(modelId)`。\(roleModelStatusDetail(modelId: modelId, snapshot: snapshot))"
        )
    }

    static func projectRoleModel(
        projectName: String,
        role: AXRole,
        modelId rawModelId: String?,
        inheritedModelId rawInheritedModelId: String?,
        snapshot: ModelStateSnapshot
    ) -> XTSettingsChangeNotice {
        let projectDisplayName = projectName.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedProjectName = projectDisplayName.isEmpty ? "当前项目" : projectDisplayName
        let modelId = (rawModelId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let inheritedModelId = (rawInheritedModelId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        guard !modelId.isEmpty else {
            if inheritedModelId.isEmpty {
                return XTSettingsChangeNotice(
                    title: "项目模型已更新",
                    detail: "已清空 \(normalizedProjectName) 的 \(role.displayName) 项目覆盖。当前没有全局固定模型，之后会回到系统自动路由。"
                )
            }

            return XTSettingsChangeNotice(
                title: "项目模型已更新",
                detail: "已清空 \(normalizedProjectName) 的 \(role.displayName) 项目覆盖。当前会回到全局模型 `\(inheritedModelId)`。\(roleModelStatusDetail(modelId: inheritedModelId, snapshot: snapshot))"
            )
        }

        return XTSettingsChangeNotice(
            title: "项目模型已更新",
            detail: "已把 \(normalizedProjectName) 的 \(role.displayName) 项目覆盖设为 `\(modelId)`。\(roleModelStatusDetail(modelId: modelId, snapshot: snapshot))"
        )
    }

    static func projectRoleModelBatch(
        role: AXRole,
        modelId rawModelId: String?,
        changedProjectCount: Int,
        totalProjectCount: Int,
        snapshot: ModelStateSnapshot
    ) -> XTSettingsChangeNotice {
        let modelId = (rawModelId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let safeChangedCount = max(0, changedProjectCount)
        let safeTotalCount = max(0, totalProjectCount)

        guard !modelId.isEmpty else {
            return XTSettingsChangeNotice(
                title: "批量应用已完成",
                detail: "已把 \(role.displayName) 的项目覆盖批量恢复为继承模式，影响 \(safeChangedCount)/\(safeTotalCount) 个项目。"
            )
        }

        if safeChangedCount == 0 {
            return XTSettingsChangeNotice(
                title: "批量应用已完成",
                detail: "全部项目的 \(role.displayName) 当前本来就已是 `\(modelId)`，没有额外改动。"
            )
        }

        return XTSettingsChangeNotice(
            title: "批量应用已完成",
            detail: "已把 \(role.displayName) 的项目覆盖批量设为 `\(modelId)`，影响 \(safeChangedCount)/\(safeTotalCount) 个项目。\(roleModelStatusDetail(modelId: modelId, snapshot: snapshot))"
        )
    }
}
