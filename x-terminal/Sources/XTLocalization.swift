import Foundation

enum XTInterfaceLanguage: String, Codable, CaseIterable, Identifiable, Sendable {
    case simplifiedChinese = "zh-Hans"
    case english = "en"

    static let defaultPreference: XTInterfaceLanguage = .simplifiedChinese

    var id: String { rawValue }

    func displayName(in language: XTInterfaceLanguage) -> String {
        switch (self, language) {
        case (.simplifiedChinese, .simplifiedChinese):
            return "简体中文"
        case (.simplifiedChinese, .english):
            return "Simplified Chinese"
        case (.english, .simplifiedChinese), (.english, .english):
            return "English"
        }
    }
}

struct XTLocalizedText: Equatable, Sendable {
    var simplifiedChinese: String
    var english: String

    func resolve(_ language: XTInterfaceLanguage) -> String {
        switch language {
        case .simplifiedChinese:
            return simplifiedChinese
        case .english:
            return english
        }
    }
}

extension AXRole {
    func displayName(in language: XTInterfaceLanguage) -> String {
        switch language {
        case .simplifiedChinese:
            return displayName
        case .english:
            switch self {
            case .coder:
                return "Coder"
            case .coarse:
                return "Draft"
            case .refine:
                return "Refine"
            case .reviewer:
                return "Reviewer"
            case .advisor:
                return "Advisor"
            case .supervisor:
                return "Supervisor"
            }
        }
    }
}

enum XTL10n {
    static func text(
        _ language: XTInterfaceLanguage,
        zhHans: String,
        en: String
    ) -> String {
        XTLocalizedText(
            simplifiedChinese: zhHans,
            english: en
        ).resolve(language)
    }

    enum Common {
        static let updated = XTLocalizedText(
            simplifiedChinese: "已更新",
            english: "Updated"
        )
        static let automatic = XTLocalizedText(
            simplifiedChinese: "自动",
            english: "Automatic"
        )
        static let automaticRouting = XTLocalizedText(
            simplifiedChinese: "自动路由",
            english: "Automatic"
        )
        static let xtDiagnostics = XTLocalizedText(
            simplifiedChinese: "XT Diagnostics",
            english: "XT Diagnostics"
        )
    }

    enum InterfaceLanguage {
        static let title = XTLocalizedText(
            simplifiedChinese: "界面语言",
            english: "Interface Language"
        )
        static let pickerLabel = XTLocalizedText(
            simplifiedChinese: "界面语言",
            english: "Interface Language"
        )
        static let rolloutSummary = XTLocalizedText(
            simplifiedChinese: "这是第一阶段多语言底座。当前先覆盖模型选择和路由诊断等小范围界面；默认保持中文，只有你显式切换后才改显示文案。",
            english: "This is the first multilingual slice. It currently covers a small set of surfaces including model selection and route diagnosis. Chinese remains the default until you switch it manually."
        )
        static let rolloutCoverage = XTLocalizedText(
            simplifiedChinese: "这次不会动协议、治理边界、状态真值和 action id，只调整展示层文案。",
            english: "This rollout does not touch protocol, governance boundaries, state truth, or action IDs. It only changes display-layer copy."
        )
        static let partialRollout = XTLocalizedText(
            simplifiedChinese: "当前是部分覆盖：其余页面会逐步补齐。",
            english: "This is a partial rollout. Other surfaces will move over gradually."
        )

        static func currentValue(
            _ selection: XTInterfaceLanguage,
            language: XTInterfaceLanguage
        ) -> String {
            XTL10n.text(
                language,
                zhHans: "当前选择：\(selection.displayName(in: language))",
                en: "Current value: \(selection.displayName(in: language))"
            )
        }
    }

    enum MenuBarLanguage {
        static let menuTitle = "语言 / Language"

        static func optionTitle(
            _ option: XTInterfaceLanguage,
            selectedLanguage: XTInterfaceLanguage
        ) -> String {
            let prefix = option == selectedLanguage ? "✓ " : ""
            return prefix + option.displayName(in: option)
        }
    }

    enum HubModelStateCopy {
        static func label(
            _ state: HubModelState,
            language: XTInterfaceLanguage
        ) -> String {
            switch state {
            case .loaded:
                return XTL10n.text(language, zhHans: "已加载", en: "Loaded")
            case .available:
                return XTL10n.text(language, zhHans: "可用未加载", en: "Available, Not Loaded")
            case .sleeping:
                return XTL10n.text(language, zhHans: "休眠", en: "Sleeping")
            }
        }
    }

    enum ModelSelector {
        static let currentConfigurationTitle = XTLocalizedText(
            simplifiedChinese: "当前配置提示",
            english: "Current Configuration"
        )
        static let hubDisconnected = XTLocalizedText(
            simplifiedChinese: "Hub 未连接",
            english: "Hub Not Connected"
        )
        static let automaticSelectedBadge = XTLocalizedText(
            simplifiedChinese: "当前生效",
            english: "Currently Active"
        )
        static let automaticRestoreBadge = XTLocalizedText(
            simplifiedChinese: "恢复继承",
            english: "Restore Inheritance"
        )
        static let automaticDescription = XTLocalizedText(
            simplifiedChinese: "让 Hub 或全局配置自行路由当前 coder 模型。",
            english: "Let Hub or the global configuration route the current coder model."
        )

        static func pickerTitle(language: XTInterfaceLanguage) -> String {
            XTL10n.text(language, zhHans: "为 Coder 选择模型", en: "Choose Model for Coder")
        }

        static func selectorTitle(
            selectionTitle: String,
            language: XTInterfaceLanguage
        ) -> String {
            XTL10n.text(
                language,
                zhHans: "Coder：\(selectionTitle)",
                en: "Coder: \(selectionTitle)"
            )
        }

        static func explicitSourceLabel(language: XTInterfaceLanguage) -> String {
            XTL10n.text(language, zhHans: "项目覆盖", en: "Project Override")
        }

        static func inheritedSourceLabel(
            inheritedModelId: String?,
            language: XTInterfaceLanguage
        ) -> String {
            if inheritedModelId == nil {
                return XTL10n.Common.automaticRouting.resolve(language)
            }
            return XTL10n.text(language, zhHans: "继承全局", en: "Inherited Global")
        }

        static func automaticTitle(language: XTInterfaceLanguage) -> String {
            XTL10n.Common.automatic.resolve(language)
        }

        static func automaticPopoverTitle(language: XTInterfaceLanguage) -> String {
            XTL10n.text(
                language,
                zhHans: "自动（使用全局 / Hub 路由）",
                en: "Automatic (Use Global / Hub Routing)"
            )
        }

        static func inheritedModelLabel(
            inheritedModelId: String?,
            language: XTInterfaceLanguage
        ) -> String {
            if inheritedModelId == nil {
                return XTL10n.Common.automaticRouting.resolve(language)
            }
            return XTL10n.text(language, zhHans: "全局模型", en: "Global Model")
        }

        static func availabilityUnknown(
            sourceLabel: String,
            selectedModelId: String,
            language: XTInterfaceLanguage
        ) -> String {
            XTL10n.text(
                language,
                zhHans: "当前无法确认\(sourceLabel) `\(selectedModelId)` 是否可用。",
                en: "XT cannot confirm whether the \(sourceLabel.lowercased()) `\(selectedModelId)` is currently runnable."
            )
        }

        static func nonInteractiveRecommendation(
            blockedId: String,
            candidate: String,
            language: XTInterfaceLanguage
        ) -> String {
            XTL10n.text(
                language,
                zhHans: "`\(blockedId)` 是检索专用模型，Supervisor 会按需调用它做检索；如果你要立刻继续，可改用 `\(candidate)`。",
                en: "`\(blockedId)` is a retrieval-only model. Supervisor can still call it when needed, but if you want to continue right now, switch to `\(candidate)`."
            )
        }

        static func exactStateRecommendation(
            exactId: String,
            stateLabel: String,
            candidate: String,
            language: XTInterfaceLanguage
        ) -> String {
            XTL10n.text(
                language,
                zhHans: "`\(exactId)` 当前是 \(stateLabel)；如果你要立刻继续，可改用已加载的 `\(candidate)`。",
                en: "`\(exactId)` is currently \(stateLabel). If you want to continue right now, switch to the loaded model `\(candidate)`."
            )
        }

        static func missingRecommendation(
            selectedModelId: String,
            candidate: String,
            language: XTInterfaceLanguage
        ) -> String {
            XTL10n.text(
                language,
                zhHans: "`\(selectedModelId)` 当前不在可直接执行的模型清单里；如果你要立刻继续，可改用已加载的 `\(candidate)`，避免这轮直接掉到本地。",
                en: "`\(selectedModelId)` is not in the directly runnable model list right now. If you want to continue immediately, switch to the loaded model `\(candidate)` to avoid dropping straight to local."
            )
        }

        static func nonInteractiveWarning(
            sourceLabel: String,
            blockedId: String,
            reason: String,
            suggested: String?,
            language: XTInterfaceLanguage
        ) -> String {
            if let suggested {
                return XTL10n.text(
                    language,
                    zhHans: "\(sourceLabel) `\(blockedId)` 当前是检索专用模型。\(reason) 如果你要立刻继续，可改用 `\(suggested)`，或恢复自动。",
                    en: "The \(sourceLabel.lowercased()) `\(blockedId)` is currently retrieval-only. \(reason) If you want to continue right now, switch to `\(suggested)` or restore automatic routing."
                )
            }
            return XTL10n.text(
                language,
                zhHans: "\(sourceLabel) `\(blockedId)` 当前是检索专用模型。\(reason)",
                en: "The \(sourceLabel.lowercased()) `\(blockedId)` is currently retrieval-only. \(reason)"
            )
        }

        static func exactStateWarning(
            sourceLabel: String,
            exactId: String,
            stateLabel: String,
            suggested: String?,
            language: XTInterfaceLanguage
        ) -> String {
            if let suggested {
                return XTL10n.text(
                    language,
                    zhHans: "\(sourceLabel) `\(exactId)` 当前状态是 \(stateLabel)，这轮请求可能回退到本地。如果你要立刻继续，可改用 `\(suggested)`。",
                    en: "The \(sourceLabel.lowercased()) `\(exactId)` is currently \(stateLabel), so this request may fall back to local. If you want to continue right now, switch to `\(suggested)`."
                )
            }
            return XTL10n.text(
                language,
                zhHans: "\(sourceLabel) `\(exactId)` 当前状态是 \(stateLabel)，这轮请求可能回退到本地。",
                en: "The \(sourceLabel.lowercased()) `\(exactId)` is currently \(stateLabel), so this request may fall back to local."
            )
        }

        static func missingWarning(
            sourceLabel: String,
            selectedModelId: String,
            language: XTInterfaceLanguage
        ) -> String {
            XTL10n.text(
                language,
                zhHans: "\(sourceLabel) `\(selectedModelId)` 当前不在可直接执行的模型清单里。",
                en: "The \(sourceLabel.lowercased()) `\(selectedModelId)` is not in the directly runnable model list right now."
            )
        }
    }

    enum RouteDiagnose {
        static let diagnose = XTLocalizedText(
            simplifiedChinese: "诊断",
            english: "Diagnose"
        )
        static let quickAIModels = XTLocalizedText(
            simplifiedChinese: "AI 模型",
            english: "AI Models"
        )
        static let quickHubRecovery = XTLocalizedText(
            simplifiedChinese: "Hub 诊断与恢复",
            english: "Hub Recovery"
        )
        static let quickHubLogs = XTLocalizedText(
            simplifiedChinese: "Hub 日志",
            english: "Hub Logs"
        )
        static let moreModels = XTLocalizedText(
            simplifiedChinese: "更多模型",
            english: "More Models"
        )
        static let changeModel = XTLocalizedText(
            simplifiedChinese: "改模型",
            english: "Change Model"
        )
        static let rediagnose = XTLocalizedText(
            simplifiedChinese: "重新诊断",
            english: "Run Again"
        )
        static let modelSettingsButton = XTLocalizedText(
            simplifiedChinese: "Supervisor · AI 模型",
            english: "Supervisor · AI Models"
        )

        static func actionTitle(
            kind: HubModelPickerRecommendationKind,
            modelLabel: String,
            language: XTInterfaceLanguage
        ) -> String {
            switch kind {
            case .continueWithoutSwitch:
                return XTL10n.text(language, zhHans: "固定成 \(modelLabel)", en: "Pin \(modelLabel)")
            case .switchRecommended:
                return XTL10n.text(language, zhHans: "改用 \(modelLabel)", en: "Switch to \(modelLabel)")
            }
        }

        static func repairTitle(
            _ action: RouteDiagnoseMessagePresentation.RepairAction,
            inProgress: Bool,
            language: XTInterfaceLanguage
        ) -> String {
            switch action {
            case .connectHubAndDiagnose:
                return XTL10n.text(language, zhHans: inProgress ? "连接中..." : "连接 Hub 并重诊断", en: inProgress ? "Connecting..." : "Connect Hub and Retry")
            case .reconnectHubAndDiagnose:
                return XTL10n.text(language, zhHans: inProgress ? "重连中..." : "重连并重诊断", en: inProgress ? "Reconnecting..." : "Reconnect and Retry")
            case .openChooseModel:
                return XTL10n.text(language, zhHans: "检查 Supervisor Control Center · AI 模型", en: "Check Supervisor Control Center · AI Models")
            case .openProjectGovernanceOverview:
                return XTL10n.text(language, zhHans: "检查 Project Governance", en: "Check Project Governance")
            case .openHubRecovery:
                return XTL10n.text(language, zhHans: "检查 Hub 诊断与恢复", en: "Check Hub Recovery")
            case .openHubConnectionLog:
                return XTL10n.text(language, zhHans: "查看 Hub 日志", en: "View Hub Logs")
            }
        }

        static func helperText(
            _ action: RouteDiagnoseMessagePresentation.RepairAction,
            language: XTInterfaceLanguage
        ) -> String {
            switch action {
            case .connectHubAndDiagnose:
                return XTL10n.text(language, zhHans: "这更像是 Hub 连接或运行服务还没就绪。先把连接补通，再自动回到当前项目重跑一次路由诊断。", en: "This looks like Hub connectivity or runtime readiness is still missing. Restore connectivity first, then automatically rerun route diagnosis for the current project.")
            case .reconnectHubAndDiagnose:
                return XTL10n.text(language, zhHans: "这更像是远端链路或运行服务状态异常。先重连，再自动重跑一次当前项目的路由诊断。", en: "This looks like a remote link or runtime state issue. Reconnect first, then automatically rerun route diagnosis for the current project.")
            case .openChooseModel:
                return XTL10n.text(language, zhHans: "这更像是目标远端模型还没加载、当前配置还不在可直接执行的列表里，或者付费模型资格、允许名单或预算还没收敛。先到 Supervisor Control Center · AI 模型看当前真实可执行模型；只有你想固定当前配置时，再手动切。", en: "This looks like the target remote model is not loaded yet, the current configuration is not directly runnable, or paid-model eligibility / allowlist / budget has not converged yet. Open Supervisor Control Center · AI Models first to see the true runnable list. Only switch manually if you want to pin the current configuration.")
            case .openProjectGovernanceOverview:
                return XTL10n.text(language, zhHans: "这次更像是 Hub supervisor route 的 governance runtime readiness 还没过，不是单纯的模型选择问题。先看 blocked planes、deny_code 和建议动作，再修 project governance、preferred device 或 grant 边界。", en: "This looks more like Hub supervisor route governance runtime readiness is still blocked, not just a model-selection issue. Inspect the blocked planes, deny_code, and next step first, then repair the project governance, preferred device, or grant boundary.")
            case .openHubRecovery:
                return XTL10n.text(language, zhHans: "这更像是 Hub 的远端导出闸门、配额或恢复链路拦住了付费远端路径。先到 Hub 诊断与恢复看失败码和修复提示。", en: "This looks like Hub remote export gating, quota, or recovery flow is blocking the paid route. Open Hub Recovery first to inspect the failure code and recovery guidance.")
            case .openHubConnectionLog:
                return XTL10n.text(language, zhHans: "这更像是 Hub 侧把远端请求降到了本地。先看 Hub 日志和最近连接状态，再决定是否继续追 Hub 端降级原因。", en: "This looks like Hub downgraded the remote request to local. Check Hub logs and recent connectivity state first, then decide whether to keep chasing the Hub-side downgrade reason.")
            }
        }

        static func chooseModelFocusTitle(language: XTInterfaceLanguage) -> String {
            XTL10n.text(language, zhHans: "路由诊断：检查 Supervisor Control Center · AI 模型", en: "Route Diagnose: Check Supervisor Control Center · AI Models")
        }

        static func chooseModelFocusFallback(
            recommendation: HubModelPickerRecommendationState?,
            language: XTInterfaceLanguage
        ) -> String {
            if let recommendation {
                switch recommendation.kind {
                case .continueWithoutSwitch:
                    return XTL10n.text(language, zhHans: "优先确认目标远端是否已经加载；如果你只是继续推进，不用手动切模型，XT 会先自动改试上次稳定远端。只有想把它固定成当前配置时，再手动切。", en: "First confirm that the target remote model is actually loaded. If you only want to continue, you do not need to switch manually. XT will first retry the last stable remote model automatically. Only switch manually if you want to pin it as the current configuration.")
                case .switchRecommended:
                    return XTL10n.text(language, zhHans: "优先确认目标远端是否已经加载；如果你现在就要继续，也可以直接固定推荐模型，避免这轮再掉本地。", en: "First confirm that the target remote model is actually loaded. If you want to continue immediately, you can also pin the recommended model directly to avoid dropping to local again.")
                }
            }
            return XTL10n.text(language, zhHans: "优先确认目标远端是否已经加载；这里只展示当前真实可执行模型，只有要固定当前配置时，再手动切。", en: "First confirm that the target remote model is actually loaded. This surface only shows the true runnable models. Switch manually only if you want to pin the current configuration.")
        }

        static func hubRecoveryFocusTitle(language: XTInterfaceLanguage) -> String {
            XTL10n.text(language, zhHans: "路由诊断：检查 Hub 诊断与恢复", en: "Route Diagnose: Check Hub Recovery")
        }

        static func hubRecoveryFocusFallback(language: XTInterfaceLanguage) -> String {
            XTL10n.text(language, zhHans: "这更像是远端导出闸门、配额或付费远端恢复问题；先看失败码和恢复入口。", en: "This looks more like a remote export gate, quota, or paid-route recovery issue. Check the failure code and recovery entry first.")
        }

        static func hubLogFocusTitle(language: XTInterfaceLanguage) -> String {
            XTL10n.text(language, zhHans: "路由诊断：查看 Hub 日志", en: "Route Diagnose: View Hub Logs")
        }

        static func hubLogFocusFallback(language: XTInterfaceLanguage) -> String {
            XTL10n.text(language, zhHans: "这更像是 Hub 侧把远端请求降到了本地；先看最近连接日志和降级线索。", en: "This looks like Hub downgraded the remote request to local. Check recent connectivity logs and downgrade clues first.")
        }

        static func diagnosticsTitle(language: XTInterfaceLanguage) -> String {
            XTL10n.text(language, zhHans: "路由诊断：查看 XT 设置 → 诊断与核对", en: "Route Diagnose: View XT Diagnostics")
        }

        static func diagnosticsFallback(language: XTInterfaceLanguage) -> String {
            XTL10n.text(language, zhHans: "先核对当前路由事件、传输方式、模型可见性和最近连接状态。", en: "Start by checking the current route event, transport path, model visibility, and recent connectivity state.")
        }

        static func modelSettingsTitle(language: XTInterfaceLanguage) -> String {
            XTL10n.text(language, zhHans: "路由诊断：检查 Supervisor Control Center · AI 模型", en: "Route Diagnose: Check Supervisor Control Center · AI Models")
        }

        static func modelSettingsFallback(language: XTInterfaceLanguage) -> String {
            XTL10n.text(language, zhHans: "如果你想固定当前项目的 coder 默认模型，可在这里直接切换；这里拿到的是 Hub 当前真实可用视图。", en: "If you want to pin the current project's default coder model, you can switch it here directly. This surface uses Hub's current truth view of runnable models.")
        }

        static func projectGovernanceTitle(language: XTInterfaceLanguage) -> String {
            XTL10n.text(language, zhHans: "路由诊断：检查 Project Governance", en: "Route Diagnose: Check Project Governance")
        }

        static func projectGovernanceFallback(language: XTInterfaceLanguage) -> String {
            XTL10n.text(language, zhHans: "先核对 Hub supervisor route 的 governance runtime readiness、blocked planes 和 deny_code，再决定是修 preferred device、grant 还是 project governance 本身。", en: "Start by checking Hub supervisor route governance runtime readiness, blocked planes, and deny_code before deciding whether to repair the preferred device, grant boundary, or project governance itself.")
        }

        static func diagnosticsFailureTitle(
            _ action: RouteDiagnoseMessagePresentation.RepairAction,
            language: XTInterfaceLanguage
        ) -> String {
            switch action {
            case .connectHubAndDiagnose:
                return XTL10n.text(language, zhHans: "连接修复失败：查看 XT 设置 → 诊断与核对", en: "Connection Repair Failed: View XT Diagnostics")
            case .reconnectHubAndDiagnose:
                return XTL10n.text(language, zhHans: "重连修复失败：查看 XT 设置 → 诊断与核对", en: "Reconnect Repair Failed: View XT Diagnostics")
            case .openChooseModel, .openProjectGovernanceOverview, .openHubRecovery, .openHubConnectionLog:
                return XTL10n.text(language, zhHans: "路由诊断：查看 XT 设置 → 诊断与核对", en: "Route Diagnose: View XT Diagnostics")
            }
        }

        static func diagnosticsFailureDetail(
            hasStructuredParts: Bool,
            language: XTInterfaceLanguage
        ) -> String {
            if hasStructuredParts {
                return ""
            }
            return XTL10n.text(language, zhHans: "连接修复没有成功，先看 XT 设置 → 诊断与核对 里的最新路由事件和连接状态。", en: "The repair did not succeed. Check the latest route event and connectivity state in XT Diagnostics first.")
        }

        static func repairFinishedTitle(
            _ action: RouteDiagnoseMessagePresentation.RepairAction,
            language: XTInterfaceLanguage
        ) -> String {
            switch action {
            case .connectHubAndDiagnose:
                return XTL10n.text(language, zhHans: "连接流程已结束", en: "Connection Flow Finished")
            case .reconnectHubAndDiagnose:
                return XTL10n.text(language, zhHans: "重连流程已结束", en: "Reconnect Flow Finished")
            case .openChooseModel, .openProjectGovernanceOverview, .openHubRecovery, .openHubConnectionLog:
                return XTL10n.text(language, zhHans: "修复流程已结束", en: "Repair Flow Finished")
            }
        }

        static func repairFinishedDetail(
            summary: String?,
            language: XTInterfaceLanguage
        ) -> String {
            let trimmed = (summary ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                return XTL10n.text(language, zhHans: "没有拿到额外的 Hub 修复报告，但已重新对当前项目跑了一次路由诊断。", en: "XT did not receive an extra Hub repair report, but it did rerun route diagnosis for the current project.")
            }
            return XTL10n.text(language, zhHans: "连接修复已完成，并重新对当前项目跑了一次路由诊断。\(trimmed)", en: "The connectivity repair completed and XT reran route diagnosis for the current project. \(trimmed)")
        }

        static func repairSucceededTitle(
            _ action: RouteDiagnoseMessagePresentation.RepairAction,
            language: XTInterfaceLanguage
        ) -> String {
            switch action {
            case .connectHubAndDiagnose:
                return XTL10n.text(language, zhHans: "Hub 已连接并已重诊断", en: "Hub Connected and Rediagnosed")
            case .reconnectHubAndDiagnose:
                return XTL10n.text(language, zhHans: "Hub 已重连并已重诊断", en: "Hub Reconnected and Rediagnosed")
            case .openChooseModel, .openProjectGovernanceOverview, .openHubRecovery, .openHubConnectionLog:
                return XTL10n.text(language, zhHans: "修复已完成", en: "Repair Complete")
            }
        }

        static func repairSucceededDetail(
            summary: String?,
            language: XTInterfaceLanguage
        ) -> String {
            let trimmed = (summary ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                return XTL10n.text(language, zhHans: "连接修复已完成，并重新对当前项目跑了一次路由诊断。", en: "The connectivity repair completed and XT reran route diagnosis for the current project.")
            }
            return XTL10n.text(language, zhHans: "连接修复已完成，并重新对当前项目跑了一次路由诊断。\(trimmed)", en: "The connectivity repair completed and XT reran route diagnosis for the current project. \(trimmed)")
        }

        static func repairFailedTitle(
            _ action: RouteDiagnoseMessagePresentation.RepairAction,
            language: XTInterfaceLanguage
        ) -> String {
            switch action {
            case .connectHubAndDiagnose:
                return XTL10n.text(language, zhHans: "连接修复未完成", en: "Connection Repair Incomplete")
            case .reconnectHubAndDiagnose:
                return XTL10n.text(language, zhHans: "重连修复未完成", en: "Reconnect Repair Incomplete")
            case .openChooseModel, .openProjectGovernanceOverview, .openHubRecovery, .openHubConnectionLog:
                return XTL10n.text(language, zhHans: "修复未完成", en: "Repair Incomplete")
            }
        }

        static func repairFailedDetail(
            summary: String?,
            language: XTInterfaceLanguage
        ) -> String {
            let trimmed = (summary ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                return XTL10n.text(language, zhHans: "我已自动把焦点切到 XT 设置 → 诊断与核对，先看最新路由事件、连通性和失败原因。", en: "XT automatically moved focus to XT Diagnostics. Check the latest route event, connectivity state, and failure reason first.")
            }
            return XTL10n.text(language, zhHans: "我已自动把焦点切到 XT 设置 → 诊断与核对。\(trimmed)", en: "XT automatically moved focus to XT Diagnostics. \(trimmed)")
        }

        static func actionOpenedTitle(
            _ action: RouteDiagnoseMessagePresentation.RepairAction,
            language: XTInterfaceLanguage
        ) -> String {
            switch action {
            case .openChooseModel:
                return XTL10n.text(language, zhHans: "已打开 Supervisor Control Center · AI 模型", en: "Opened Supervisor Control Center · AI Models")
            case .openProjectGovernanceOverview:
                return XTL10n.text(language, zhHans: "已打开 Project Governance", en: "Opened Project Governance")
            case .openHubRecovery:
                return XTL10n.text(language, zhHans: "已打开 Hub 诊断与恢复", en: "Opened Hub Recovery")
            case .openHubConnectionLog:
                return XTL10n.text(language, zhHans: "已打开 Hub 日志", en: "Opened Hub Logs")
            case .connectHubAndDiagnose, .reconnectHubAndDiagnose:
                return ""
            }
        }

        static func actionOpenedDetail(
            _ action: RouteDiagnoseMessagePresentation.RepairAction,
            language: XTInterfaceLanguage
        ) -> String {
            switch action {
            case .openChooseModel:
                return XTL10n.text(language, zhHans: "先确认目标远端是否已经加载；这里展示的是当前真实可执行模型，如果你只是继续推进，不一定需要立刻手动切模型。", en: "First confirm that the target remote model is loaded. This surface shows the true runnable models, so if you only want to continue, you may not need to switch manually right away.")
            case .openProjectGovernanceOverview:
                return XTL10n.text(language, zhHans: "先核对 governance runtime readiness、blocked planes 和建议动作；如果这次卡在 preferred device、grant、TTL 或 kill-switch，这里比改模型更直接。", en: "Check governance runtime readiness, blocked planes, and the suggested next step first. If this run is blocked by the preferred device, grant, TTL, or kill switch, this surface is more direct than changing the model.")
            case .openHubRecovery:
                return XTL10n.text(language, zhHans: "先看失败码、恢复链路和付费远端相关提示，再决定是不是继续追 Hub 端降级原因。", en: "Check the failure code, recovery flow, and paid-route guidance first, then decide whether to keep chasing the Hub-side downgrade reason.")
            case .openHubConnectionLog:
                return XTL10n.text(language, zhHans: "先核对最近连接状态、远端请求是否被降到本地，以及对应的失败码或恢复线索。", en: "Check recent connectivity state, whether the remote request was downgraded to local, and the related failure or recovery clues first.")
            case .connectHubAndDiagnose, .reconnectHubAndDiagnose:
                return ""
            }
        }

        static func modelSettingsOpenedTitle(language: XTInterfaceLanguage) -> String {
            XTL10n.text(language, zhHans: "已打开 Supervisor Control Center · AI 模型", en: "Opened Supervisor Control Center · AI Models")
        }

        static func modelSettingsOpenedDetail(language: XTInterfaceLanguage) -> String {
            XTL10n.text(language, zhHans: "先确认当前项目单独设置和全局默认是不是一致；这里展示的是 Hub 当前真实可用模型视图，如果目标模型还没加载，运行时仍可能回退到本地。", en: "First confirm whether the current project override matches the global default. This surface uses Hub's current truth view of runnable models. If the target model is still not loaded, runtime may still fall back to local.")
        }

        static func diagnosticsOpenedTitle(language: XTInterfaceLanguage) -> String {
            XTL10n.text(language, zhHans: "已打开 XT 设置 → 诊断与核对", en: "Opened XT Diagnostics")
        }

        static func diagnosticsOpenedDetail(language: XTInterfaceLanguage) -> String {
            XTL10n.text(language, zhHans: "先核对最近路由事件、连通性、模型可见性和失败原因，再决定是改模型还是修 Hub。", en: "Check the latest route event, connectivity state, model visibility, and failure reason first, then decide whether to change the model or repair Hub.")
        }
    }
}
