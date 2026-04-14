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
        doctorReport: XHubDoctorOutputReport? = nil,
        runtimeMonitor: XHubLocalRuntimeMonitorSnapshotReport? = nil,
        currentProjectName: String? = nil,
        currentProjectContext: AXProjectContext? = nil,
        currentProjectCoderModelId: String? = nil,
        currentRemotePaidAccessSnapshot: HubRemotePaidAccessSnapshot? = nil
    ) -> XTModelGuidancePresentation {
        let supportLoadedCount = snapshot.models.filter { $0.state == .loaded && !$0.isSelectableForInteractiveRouting }.count
        let inventoryTruth = XTModelInventoryTruthPresentation.build(
            snapshot: snapshot,
            doctorReport: doctorReport,
            runtimeMonitor: runtimeMonitor
        )

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

        if inventoryTruth.showsStatusCard {
            items.append(
                XTSettingsGuidanceItem(
                    id: inventoryTruth.state.rawValue,
                    title: inventoryTruth.state == .localOnlyReady ? "当前姿态" : "当前状态",
                    detail: inventoryTruth.state == .localOnlyReady ? inventoryTruth.summary + " " + inventoryTruth.detail : inventoryTruth.detail
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
            guard let currentProjectContext else { return nil }

            let guidanceText = AXProjectModelRouteMemoryStore.selectionGuidance(
                configuredModelId: configuredCoderModelId,
                role: .coder,
                ctx: currentProjectContext,
                snapshot: snapshot,
                paidAccessSnapshot: currentRemotePaidAccessSnapshot
            )?.warningText

            let executionSnapshot = AXRoleExecutionSnapshots.latestSnapshots(for: currentProjectContext)[.coder]
                ?? .empty(role: .coder, source: "settings_guidance")
            let recentRouteTruthHint = ExecutionRoutePresentation.recentGrpcRouteTruthHint(
                snapshot: executionSnapshot,
                transportMode: HubAIClient.transportMode().rawValue,
                language: settings.interfaceLanguage
            )
            let paidTruthHint: String? = {
                guard let paidTruth = XTRouteTruthPresentation.pairedDeviceTruthText(
                    routeReasonCode: executionSnapshot.effectiveFailureReasonCode,
                    denyCode: executionSnapshot.denyCode,
                    paidAccessSnapshot: currentRemotePaidAccessSnapshot,
                    language: settings.interfaceLanguage
                ) else {
                    return nil
                }

                let existingText = [guidanceText, recentRouteTruthHint]
                    .compactMap { normalized($0) }
                    .joined(separator: " ")
                guard !existingText.contains(paidTruth) else { return nil }
                return XTL10n.text(
                    settings.interfaceLanguage,
                    zhHans: "当前设备真值：\(paidTruth)。",
                    en: "Current device truth: \(paidTruth)."
                )
            }()
            let parts = [guidanceText, normalized(recentRouteTruthHint), normalized(paidTruthHint)]
                .compactMap { normalized($0) }
            guard !parts.isEmpty else { return nil }

            let projectPrefix = normalized(currentProjectName).map { "当前项目 \($0)：" } ?? "当前项目："
            return projectPrefix + parts.joined(separator: " ")
        }()

        return XTModelGuidancePresentation(
            inventorySummary: inventoryTruth.summary,
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
            sandboxDetail = "当前默认直接在本机执行；只有工具调用明确要求进沙箱时，才会切到沙箱。"
        case .sandbox:
            sandboxDetail = "当前默认走沙箱执行；只有工具调用明确要求走本机时，才会切回本机。"
        }

        let automationDetail: String
        switch workMode {
        case .conversationOnly:
            automationDetail = "当前是对话模式；Supervisor 只回答你的明确请求，不会自己发起 coder / skill / tool 执行。"
        case .guidedProgress:
            automationDetail = "当前是推进模式；Supervisor 会给计划、提醒和下一步建议，但执行仍要你来点头。"
        case .governedAutomation:
            automationDetail = "当前是自动执行模式；只有 A-Tier、S-Tier、授权和运行时状态都允许时，才会继续自动执行。"
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
                    title: "工具自动执行",
                    detail: "这是项目聊天里的会话开关，不是全局放开；关闭时仍会先把工具调用列出来，等你批准。"
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
        snapshot: ModelStateSnapshot,
        executionSnapshot: AXRoleExecutionSnapshot? = nil,
        transportMode: String = HubAIClient.transportMode().rawValue,
        language: XTInterfaceLanguage = .defaultPreference
    ) -> String {
        let assessment = HubModelSelectionAdvisor.assess(
            requestedId: modelId,
            snapshot: snapshot
        )

        let recentRouteTruthSuffix: String = {
            guard let executionSnapshot else { return "" }
            let hint = ExecutionRoutePresentation.recentGrpcRouteTruthHint(
                snapshot: executionSnapshot,
                transportMode: transportMode,
                language: language
            )
            return hint.isEmpty ? "" : " " + hint
        }()

        if let exact = assessment?.exactMatch,
           exact.state == .loaded {
            let sourceLabel = XTL10n.text(
                language,
                zhHans: exact.isLocalModel ? "本地" : "远端",
                en: exact.isLocalModel ? "local" : "remote"
            )
            return XTL10n.text(
                language,
                zhHans: "它当前已加载，且属于可直接对话的\(sourceLabel)模型，后续路由可以直接用。",
                en: "It is currently loaded and is a directly interactive \(sourceLabel) model, so runtime can use it directly."
            )
        }

        if let blocked = assessment?.nonInteractiveExactMatch {
            let reason = blocked.interactiveRoutingDisabledReason
                ?? XTL10n.text(
                    language,
                    zhHans: "它不适合作为当前角色的对话模型。",
                    en: "It is not suitable as the interactive model for this role."
                )
            return XTL10n.text(
                language,
                zhHans: "但它属于非对话模型。\(reason) 建议直接改成一个已加载的对话模型。",
                en: "But it is a non-chat model. \(reason) Switch directly to a loaded interactive model."
            )
        }

        if let exact = assessment?.exactMatch {
            return XTL10n.text(
                language,
                zhHans: "但它现在是 \(HubModelSelectionAdvisor.stateLabel(exact.state, language: language))；继续运行时可能会回退到本地，建议先去 Supervisor Control Center · AI 模型确认它已进入真实可执行列表，或改用一个已加载候选。",
                en: "But it is currently \(HubModelSelectionAdvisor.stateLabel(exact.state, language: language)). Runtime may fall back to local, so first check in Supervisor Control Center · AI Models that it is in the true runnable list, or switch to a loaded candidate."
            ) + recentRouteTruthSuffix
        }

        if assessment?.isMissingFromInventory == true {
            return XTL10n.text(
                language,
                zhHans: "但当前 inventory 里没有精确匹配。建议先刷新模型列表，或直接改用即时提示里的候选模型。",
                en: "But there is no exact match in the current inventory. Refresh the model list first, or switch to one of the suggested candidates."
            ) + recentRouteTruthSuffix
        }

        return XTL10n.text(
            language,
            zhHans: "如果它没有真正 loaded，运行时仍可能回退到本地。",
            en: "If it is not truly loaded, runtime may still fall back to local."
        ) + recentRouteTruthSuffix
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

    static func supervisorReviewMemoryDepth(
        _ profile: XTSupervisorReviewMemoryDepthProfile
    ) -> XTSettingsChangeNotice {
        XTSettingsChangeNotice(
            title: "Review Memory Depth 已更新",
            detail: "Review Memory Depth 已设为 \(profile.displayName)。这个改动只影响 Supervisor 的 review-memory 组装目标；实际生效仍会受当前项目的 S-Tier ceiling clamp，X-宪章、Hub gate 和审计链保持不变。"
        )
    }

    static func interfaceLanguage(
        _ language: XTInterfaceLanguage
    ) -> XTSettingsChangeNotice {
        XTSettingsChangeNotice(
            title: XTL10n.text(
                language,
                zhHans: "界面语言已更新",
                en: "Interface Language Updated"
            ),
            detail: XTL10n.text(
                language,
                zhHans: "当前界面语言已切到 \(language.displayName(in: language))。这次先覆盖模型选择和路由诊断等小范围界面，其余页面会逐步补齐。",
                en: "The interface language is now \(language.displayName(in: language)). This first rollout covers a small set of surfaces including model selection and route diagnosis. Other surfaces will move over gradually."
            )
        )
    }

    static func defaultToolSandboxMode(_ mode: ToolSandboxMode) -> XTSettingsChangeNotice {
        XTSettingsChangeNotice(
            title: "默认工具路径已更新",
            detail: {
                switch mode {
                case .host:
                    return "默认工具执行路径已切到本机。自动执行仍会受项目授权和运行时状态约束。"
                case .sandbox:
                    return "默认工具执行路径已切到沙箱。自动执行仍会受项目授权和运行时状态约束。"
                }
            }()
        )
    }

    static func globalRoleModel(
        role: AXRole,
        modelId rawModelId: String?,
        snapshot: ModelStateSnapshot,
        executionSnapshot: AXRoleExecutionSnapshot? = nil,
        transportMode: String = HubAIClient.transportMode().rawValue,
        language: XTInterfaceLanguage = .defaultPreference
    ) -> XTSettingsChangeNotice {
        let modelId = (rawModelId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !modelId.isEmpty else {
            return XTSettingsChangeNotice(
                title: XTL10n.text(
                    language,
                    zhHans: "\(role.displayName(in: language)) 模型已清空",
                    en: "\(role.displayName(in: language)) Model Cleared"
                ),
                detail: XTL10n.text(
                    language,
                    zhHans: "已清空 \(role.displayName(in: language)) 的默认 Hub 模型。系统之后会重新按 inventory 和路由策略挑候选；继续前建议至少把 coder 和 supervisor 配完整。",
                    en: "Cleared the default Hub model for \(role.displayName(in: language)). XT will pick candidates again from inventory and routing policy. Before continuing, it is best to configure at least coder and supervisor."
                )
            )
        }

        return XTSettingsChangeNotice(
            title: XTL10n.text(
                language,
                zhHans: "\(role.displayName(in: language)) 模型已更新",
                en: "\(role.displayName(in: language)) Model Updated"
            ),
            detail: XTL10n.text(
                language,
                zhHans: "已把 \(role.displayName(in: language)) 默认模型设为 `\(modelId)`。",
                en: "Set the default model for \(role.displayName(in: language)) to `\(modelId)`."
            ) + " " + roleModelStatusDetail(
                modelId: modelId,
                snapshot: snapshot,
                executionSnapshot: executionSnapshot,
                transportMode: transportMode,
                language: language
            )
        )
    }

    static func projectRoleModel(
        projectName: String,
        role: AXRole,
        modelId rawModelId: String?,
        inheritedModelId rawInheritedModelId: String?,
        snapshot: ModelStateSnapshot,
        executionSnapshot: AXRoleExecutionSnapshot? = nil,
        transportMode: String = HubAIClient.transportMode().rawValue,
        language: XTInterfaceLanguage = .defaultPreference
    ) -> XTSettingsChangeNotice {
        let projectDisplayName = projectName.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedProjectName = projectDisplayName.isEmpty
            ? XTL10n.text(language, zhHans: "当前项目", en: "Current Project")
            : projectDisplayName
        let modelId = (rawModelId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let inheritedModelId = (rawInheritedModelId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        guard !modelId.isEmpty else {
            if inheritedModelId.isEmpty {
                return XTSettingsChangeNotice(
                    title: XTL10n.text(
                        language,
                        zhHans: "项目模型已更新",
                        en: "Project Model Updated"
                    ),
                    detail: XTL10n.text(
                        language,
                        zhHans: "已清空 \(normalizedProjectName) 的 \(role.displayName(in: language)) 项目覆盖。当前没有全局固定模型，之后会回到系统自动路由。",
                        en: "Cleared the project override for \(role.displayName(in: language)) in \(normalizedProjectName). There is no global pinned model right now, so XT will return to automatic system routing."
                    )
                )
            }

            return XTSettingsChangeNotice(
                title: XTL10n.text(
                    language,
                    zhHans: "项目模型已更新",
                    en: "Project Model Updated"
                ),
                detail: XTL10n.text(
                    language,
                    zhHans: "已清空 \(normalizedProjectName) 的 \(role.displayName(in: language)) 项目覆盖。当前会回到全局模型 `\(inheritedModelId)`。",
                    en: "Cleared the project override for \(role.displayName(in: language)) in \(normalizedProjectName). XT will fall back to the global model `\(inheritedModelId)`."
                ) + " " + roleModelStatusDetail(
                    modelId: inheritedModelId,
                    snapshot: snapshot,
                    executionSnapshot: executionSnapshot,
                    transportMode: transportMode,
                    language: language
                )
            )
        }

        return XTSettingsChangeNotice(
            title: XTL10n.text(
                language,
                zhHans: "项目模型已更新",
                en: "Project Model Updated"
            ),
            detail: XTL10n.text(
                language,
                zhHans: "已把 \(normalizedProjectName) 的 \(role.displayName(in: language)) 项目覆盖设为 `\(modelId)`。",
                en: "Set the project override for \(role.displayName(in: language)) in \(normalizedProjectName) to `\(modelId)`."
            ) + " " + roleModelStatusDetail(
                modelId: modelId,
                snapshot: snapshot,
                executionSnapshot: executionSnapshot,
                transportMode: transportMode,
                language: language
            )
        )
    }

    static func projectRoleModelBatch(
        role: AXRole,
        modelId rawModelId: String?,
        changedProjectCount: Int,
        totalProjectCount: Int,
        snapshot: ModelStateSnapshot,
        language: XTInterfaceLanguage = .defaultPreference
    ) -> XTSettingsChangeNotice {
        let modelId = (rawModelId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let safeChangedCount = max(0, changedProjectCount)
        let safeTotalCount = max(0, totalProjectCount)

        guard !modelId.isEmpty else {
            return XTSettingsChangeNotice(
                title: XTL10n.text(
                    language,
                    zhHans: "批量应用已完成",
                    en: "Batch Apply Complete"
                ),
                detail: XTL10n.text(
                    language,
                    zhHans: "已把 \(role.displayName(in: language)) 的项目覆盖批量恢复为继承模式，影响 \(safeChangedCount)/\(safeTotalCount) 个项目。",
                    en: "Restored project overrides for \(role.displayName(in: language)) back to inherited mode across \(safeChangedCount)/\(safeTotalCount) projects."
                )
            )
        }

        if safeChangedCount == 0 {
            return XTSettingsChangeNotice(
                title: XTL10n.text(
                    language,
                    zhHans: "批量应用已完成",
                    en: "Batch Apply Complete"
                ),
                detail: XTL10n.text(
                    language,
                    zhHans: "全部项目的 \(role.displayName(in: language)) 当前本来就已是 `\(modelId)`，没有额外改动。",
                    en: "All projects were already set to `\(modelId)` for \(role.displayName(in: language)), so no extra changes were needed."
                )
            )
        }

        return XTSettingsChangeNotice(
            title: XTL10n.text(
                language,
                zhHans: "批量应用已完成",
                en: "Batch Apply Complete"
            ),
            detail: XTL10n.text(
                language,
                zhHans: "已把 \(role.displayName(in: language)) 的项目覆盖批量设为 `\(modelId)`，影响 \(safeChangedCount)/\(safeTotalCount) 个项目。",
                en: "Set the project override for \(role.displayName(in: language)) to `\(modelId)` across \(safeChangedCount)/\(safeTotalCount) projects."
            ) + " " + roleModelStatusDetail(
                modelId: modelId,
                snapshot: snapshot,
                language: language
            )
        )
    }
}
