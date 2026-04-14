import Foundation

enum HubModelRoutingTruthSurface {
    case globalRoleSettings
    case projectRoleSettings
}

struct HubModelRoutingTruthBuildResult: Equatable {
    var lines: [String]
    var pickerTruth: HubModelRoutingSupplementaryPresentation
}

enum HubModelRoutingTruthBuilder {
    static func build(
        surface: HubModelRoutingTruthSurface,
        role: AXRole,
        selectedProjectID: String?,
        selectedProjectName: String?,
        projectConfig: AXProjectConfig?,
        projectRuntimeReadiness: AXProjectGovernanceRuntimeReadinessSnapshot? = nil,
        settings: XTerminalSettings,
        snapshot: AXRoleExecutionSnapshot,
        transportMode: String,
        language: XTInterfaceLanguage = .defaultPreference
    ) -> HubModelRoutingTruthBuildResult {
        let projectID = normalized(selectedProjectID)
        let projectName = normalized(selectedProjectName)
        let configuredModelId = AXRoleExecutionSnapshots.configuredModelId(
            for: role,
            projectConfig: projectID == nil ? nil : projectConfig,
            settings: settings
        )
        let configuredTarget = normalized(configuredModelId)
            ?? normalized(snapshot.requestedModelId)
            ?? "auto"

        var lines: [String] = [
            displayLine(
                label: XTL10n.text(language, zhHans: "你设定的目标", en: "Configured Target"),
                value: configuredTarget
            ),
            configuredSourceLine(
                role: role,
                projectID: projectID,
                projectConfig: projectConfig,
                settings: settings,
                language: language
            ),
            routeScopeLine(
                role: role,
                projectID: projectID,
                projectName: projectName,
                language: language
            )
        ]

        if snapshot.hasRecord {
            lines.append(
                displayLine(
                    label: XTL10n.text(language, zhHans: "这次实际命中", en: "Actual Route"),
                    value: XTRouteTruthPresentation.actualRouteText(
                        executionPath: snapshot.executionPath,
                        runtimeProvider: snapshot.runtimeProvider,
                        actualModelId: snapshot.actualModelId,
                        language: language
                    )
                )
            )
            if let fallbackReason = XTRouteTruthPresentation.routeReasonDisplayText(
                snapshot.effectiveFailureReasonCode,
                language: language
            ) {
                lines.append(
                    displayLine(
                        label: XTL10n.text(language, zhHans: "没按预期走的原因", en: "Fallback Reason"),
                        value: fallbackReason
                    )
                )
            }
            lines.append(
                displayLine(
                    label: XTL10n.text(language, zhHans: "当前状态说明", en: "Route State"),
                    value: XTRouteTruthPresentation.routeStateText(
                        executionPath: snapshot.executionPath,
                        routeReasonCode: snapshot.effectiveFailureReasonCode,
                        denyCode: snapshot.denyCode,
                        language: language
                    )
                )
            )
            if let denyCode = XTRouteTruthPresentation.denyCodeText(
                snapshot.denyCode,
                language: language
            ) {
                lines.append(
                    displayLine(
                        label: XTL10n.text(language, zhHans: "明确拦截原因", en: "Deny Reason"),
                        value: denyCode
                    )
                )
            }
            if let auditRef = normalized(snapshot.auditRef) {
                lines.append(
                    displayLine(
                        label: XTL10n.text(language, zhHans: "审计编号", en: "Audit Ref"),
                        value: auditRef
                    )
                )
            }
            if let supervisorHint = XTRouteTruthPresentation.supervisorRouteGovernanceHint(
                routeReasonCode: snapshot.effectiveFailureReasonCode,
                denyCode: snapshot.denyCode,
                language: language
            ) {
                lines.append(
                    displayLine(
                        label: XTL10n.text(language, zhHans: "修复建议", en: "Repair Hint"),
                        value: supervisorHint.repairHintText
                    )
                )
            }
        } else {
            lines.append(
                displayLine(
                    label: XTL10n.text(language, zhHans: "这次实际命中", en: "Actual Route"),
                    value: unobservedActualRouteText(
                        role: role,
                        projectID: projectID,
                        language: language
                    )
                )
            )
            lines.append(
                displayLine(
                    label: XTL10n.text(language, zhHans: "当前状态说明", en: "Route State"),
                    value: unobservedRouteStateText(
                        role: role,
                        projectID: projectID,
                        language: language
                    )
                )
            )
        }

        if let transportLine = transportLine(transportMode, language: language) {
            lines.append(transportLine)
        }
        if let projectRuntimeReadiness,
           projectRuntimeReadiness.requiresA4RuntimeReady {
            lines.append(
                displayLine(
                    label: XTL10n.text(language, zhHans: "A4 Runtime Ready", en: "A4 Runtime Ready"),
                    value: XTRouteTruthPresentation.governanceRuntimeReadinessStateText(
                        projectRuntimeReadiness,
                        language: language
                    )
                )
            )
            lines.append(
                displayLine(
                    label: XTL10n.text(language, zhHans: "A4 五维检查", en: "A4 Readiness Matrix"),
                    value: XTRouteTruthPresentation.governanceRuntimeReadinessMatrixText(
                        projectRuntimeReadiness,
                        language: language
                    )
                )
            )
            if let gapText = XTRouteTruthPresentation.governanceRuntimeReadinessGapText(
                projectRuntimeReadiness,
                language: language
            ) {
                lines.append(
                    displayLine(
                        label: XTL10n.text(language, zhHans: "A4 当前缺口", en: "A4 Current Gaps"),
                        value: gapText
                    )
                )
            }
        }

        return HubModelRoutingTruthBuildResult(
            lines: lines,
            pickerTruth: pickerTruth(
                surface: surface,
                role: role,
                projectID: projectID,
                projectName: projectName,
                projectConfig: projectConfig,
                projectRuntimeReadiness: projectRuntimeReadiness,
                settings: settings,
                configuredModelId: configuredModelId,
                snapshot: snapshot,
                transportMode: transportMode,
                lines: lines,
                language: language
            )
        )
    }

    private static func pickerTruth(
        surface: HubModelRoutingTruthSurface,
        role: AXRole,
        projectID: String?,
        projectName: String?,
        projectConfig: AXProjectConfig?,
        projectRuntimeReadiness: AXProjectGovernanceRuntimeReadinessSnapshot?,
        settings: XTerminalSettings,
        configuredModelId: String,
        snapshot: AXRoleExecutionSnapshot,
        transportMode: String,
        lines: [String],
        language: XTInterfaceLanguage
    ) -> HubModelRoutingSupplementaryPresentation {
        var badges: [HubModelRoutingBadgePresentation] = []
        let projectOverride = projectID == nil
            ? nil
            : normalized(projectConfig?.modelOverride(for: role))

        switch surface {
        case .globalRoleSettings:
            if projectOverride != nil {
                badges.append(
                    HubModelRoutingBadgePresentation(
                        text: XTL10n.text(
                            language,
                            zhHans: "项目单独设置",
                            en: "Project Override"
                        ),
                        tone: .neutral,
                        kind: .source
                    )
                )
            }
        case .projectRoleSettings:
            badges.append(
                HubModelRoutingBadgePresentation(
                    text: projectOverride == nil
                        ? XTL10n.text(
                            language,
                            zhHans: "沿用全局",
                            en: "Inherited Global"
                        )
                        : XTL10n.text(
                            language,
                            zhHans: "项目单独设置",
                            en: "Project Override"
                        ),
                    tone: .neutral,
                    kind: .source
                )
            )
        }

        if snapshot.hasRecord {
            badges.append(
                HubModelRoutingBadgePresentation(
                    text: ExecutionRoutePresentation.statusText(snapshot: snapshot),
                    tone: statusTone(snapshot),
                    kind: .status
                )
            )

            if let detailBadge = ExecutionRoutePresentation.detailBadge(
                configuredModelId: configuredModelId,
                snapshot: snapshot
            ) {
                badges.append(
                    HubModelRoutingBadgePresentation(
                        text: detailBadge.text,
                        tone: detailTone(snapshot),
                        kind: .detail
                    )
                )
            }

            if let evidenceBadge = ExecutionRoutePresentation.evidenceBadge(snapshot: snapshot) {
                badges.append(
                    HubModelRoutingBadgePresentation(
                        text: evidenceBadge.text,
                        tone: evidenceTone(snapshot, text: evidenceBadge.text),
                        kind: .evidence
                    )
                )
            }
        } else {
            badges.append(
                HubModelRoutingBadgePresentation(
                    text: XTL10n.text(
                        language,
                        zhHans: "待观察",
                        en: "Pending"
                    ),
                    tone: .neutral,
                    kind: .status
                )
            )
        }

        return HubModelRoutingSupplementaryPresentation(
            badges: badges,
            summaryText: pickerSummary(
                surface: surface,
                role: role,
                projectID: projectID,
                projectName: projectName,
                projectOverride: projectOverride,
                projectRuntimeReadiness: projectRuntimeReadiness,
                settings: settings,
                configuredModelId: configuredModelId,
                snapshot: snapshot,
                transportMode: transportMode,
                language: language
            ),
            tooltip: lines.joined(separator: "\n")
        )
    }

    private static func configuredSourceLine(
        role: AXRole,
        projectID: String?,
        projectConfig: AXProjectConfig?,
        settings: XTerminalSettings,
        language: XTInterfaceLanguage
    ) -> String {
        let projectOverride = projectID == nil
            ? nil
            : normalized(projectConfig?.modelOverride(for: role))
        let globalAssignment = normalized(settings.assignment(for: role).model)
        let value: String

        if projectOverride != nil {
            value = XTL10n.text(
                language,
                zhHans: "当前项目单独设置",
                en: "current project override"
            )
        } else if globalAssignment != nil {
            value = projectID == nil
                ? XTL10n.text(
                    language,
                    zhHans: "全局角色设置",
                    en: "global role override"
                )
                : XTL10n.text(
                    language,
                    zhHans: "当前项目没有单独设置；沿用全局角色设置",
                    en: "no project override; inheriting the global role override"
                )
        } else {
            value = XTL10n.text(
                language,
                zhHans: "未固定；继续使用 Hub 默认 / 自动路由",
                en: "not pinned; using Hub default / automatic routing"
            )
        }

        return displayLine(
            label: XTL10n.text(language, zhHans: "配置来源", en: "Config Source"),
            value: value
        )
    }

    private static func routeScopeLine(
        role: AXRole,
        projectID: String?,
        projectName: String?,
        language: XTInterfaceLanguage
    ) -> String {
        if role == .supervisor {
            if let projectID {
                return displayLine(
                    label: XTL10n.text(language, zhHans: "适用范围", en: "Scope"),
                    value: XTL10n.text(
                        language,
                        zhHans: "Supervisor 全局对话；当前项目焦点 \(projectDisplayName(projectName, projectID: projectID))",
                        en: "Supervisor global conversation; current project focus \(projectDisplayName(projectName, projectID: projectID))"
                    )
                )
            }
            return displayLine(
                label: XTL10n.text(language, zhHans: "适用范围", en: "Scope"),
                value: XTL10n.text(
                    language,
                    zhHans: "Supervisor 全局对话",
                    en: "Supervisor global conversation"
                )
            )
        }

        if let projectID {
            return displayLine(
                label: XTL10n.text(language, zhHans: "适用范围", en: "Scope"),
                value: XTL10n.text(
                    language,
                    zhHans: "当前项目 \(projectDisplayName(projectName, projectID: projectID))",
                    en: "current project \(projectDisplayName(projectName, projectID: projectID))"
                )
            )
        }

        return displayLine(
            label: XTL10n.text(language, zhHans: "适用范围", en: "Scope"),
            value: XTL10n.text(
                language,
                zhHans: "当前未绑定项目；这里只能核对全局角色设置",
                en: "no project selected; only the global role override can be checked here"
            )
        )
    }

    private static func unobservedActualRouteText(
        role: AXRole,
        projectID: String?,
        language: XTInterfaceLanguage
    ) -> String {
        if role == .supervisor {
            return XTL10n.text(
                language,
                zhHans: "尚未观测到最近一轮 Supervisor 实际执行",
                en: "No recent actual Supervisor execution has been observed yet"
            )
        }
        if projectID != nil {
            return XTL10n.text(
                language,
                zhHans: "尚未观测到当前角色在当前项目的最近执行",
                en: "No recent execution for this role has been observed in the current project yet"
            )
        }
        return XTL10n.text(
            language,
            zhHans: "尚未观测到当前角色的最近执行",
            en: "No recent execution for this role has been observed yet"
        )
    }

    private static func unobservedRouteStateText(
        role: AXRole,
        projectID: String?,
        language: XTInterfaceLanguage
    ) -> String {
        if role == .supervisor {
            return XTL10n.text(
                language,
                zhHans: "当前还没有足够执行证据；先让 Supervisor 实际跑一轮，再判断这次实际路由。",
                en: "There is not enough execution evidence yet. Let Supervisor run once before judging the actual route."
            )
        }
        if projectID != nil {
            return XTL10n.text(
                language,
                zhHans: "当前还没有足够执行证据；先在当前项目跑一轮该角色，再判断这次实际路由。",
                en: "There is not enough execution evidence yet. Run this role once in the current project before judging the actual route."
            )
        }
        return XTL10n.text(
            language,
            zhHans: "当前还没有足够执行证据；先让该角色实际跑一轮，再判断这次实际路由。",
            en: "There is not enough execution evidence yet. Let this role run once before judging the actual route."
        )
    }

    private static func pickerSummary(
        surface: HubModelRoutingTruthSurface,
        role: AXRole,
        projectID: String?,
        projectName: String?,
        projectOverride: String?,
        projectRuntimeReadiness: AXProjectGovernanceRuntimeReadinessSnapshot?,
        settings: XTerminalSettings,
        configuredModelId: String,
        snapshot: AXRoleExecutionSnapshot,
        transportMode: String,
        language: XTInterfaceLanguage
    ) -> String {
        let routeState = snapshot.hasRecord
            ? XTRouteTruthPresentation.routeStateText(
                executionPath: snapshot.executionPath,
                routeReasonCode: snapshot.effectiveFailureReasonCode,
                denyCode: snapshot.denyCode,
                language: language
            )
            : unobservedRouteStateText(role: role, projectID: projectID, language: language)
        let transportHint = grpcTransportMismatchHint(
            configuredModelId: configuredModelId,
            snapshot: snapshot,
            transportMode: transportMode,
            language: language
        )
        let supervisorRepairHint = snapshot.hasRecord
            ? XTRouteTruthPresentation.supervisorRouteGovernanceHint(
                routeReasonCode: snapshot.effectiveFailureReasonCode,
                denyCode: snapshot.denyCode,
                language: language
            )?.repairHintText ?? ""
            : ""
        let governanceHint = governanceRuntimeReadinessHint(
            projectRuntimeReadiness,
            language: language
        )
        let globalModel = normalized(settings.assignment(for: role).model)

        switch surface {
        case .globalRoleSettings:
            if let projectID,
               let projectOverride {
                let globalText = globalModel.map {
                    XTL10n.text(
                        language,
                        zhHans: "；全局默认当前是 \($0)",
                        en: ". The current global default is \($0)"
                    )
                } ?? ""
                return XTL10n.text(
                    language,
                    zhHans: "项目 \(projectDisplayName(projectName, projectID: projectID)) 当前优先使用项目内单独设置 `\(projectOverride)`；你这里改的是全局默认\(globalText)。\(routeState)",
                    en: "The project override `\(projectOverride)` for \(projectDisplayName(projectName, projectID: projectID)) is currently deciding the configured route. This control edits the global default\(globalText). \(routeState)"
                ) + transportHint + appendedHint(supervisorRepairHint) + governanceHint
            }

            if role == .supervisor {
                if let projectID {
                    return XTL10n.text(
                        language,
                        zhHans: "当前看到的是 Supervisor 全局对话最近一次可见的路由记录；项目焦点是 \(projectDisplayName(projectName, projectID: projectID))。\(routeState)",
                        en: "This is the latest route truth for Supervisor global conversation. The current project focus is \(projectDisplayName(projectName, projectID: projectID)). \(routeState)"
                    ) + transportHint + appendedHint(supervisorRepairHint) + governanceHint
                }
                return routeState + transportHint + appendedHint(supervisorRepairHint) + governanceHint
            }

            if let projectID {
                return XTL10n.text(
                    language,
                    zhHans: "当前看到的是项目 \(projectDisplayName(projectName, projectID: projectID)) 最近一次可见的路由记录。\(routeState)",
                    en: "This is the latest route truth for project \(projectDisplayName(projectName, projectID: projectID)). \(routeState)"
                ) + transportHint + appendedHint(supervisorRepairHint) + governanceHint
            }

            return XTL10n.text(
                language,
                zhHans: "当前未绑定项目；这里只能核对全局角色设置。\(routeState)",
                en: "No project is currently selected, so only the global role override can be checked here. \(routeState)"
            ) + transportHint + appendedHint(supervisorRepairHint) + governanceHint

        case .projectRoleSettings:
            let projectLabel = projectID.map { projectDisplayName(projectName, projectID: $0) }
                ?? XTL10n.text(
                    language,
                    zhHans: "当前项目",
                    en: "Current Project"
                )
            let subject = role == .supervisor
                ? XTL10n.text(
                    language,
                    zhHans: "当前项目 \(projectLabel) 下的 Supervisor",
                    en: "Supervisor for \(projectLabel)"
                )
                : XTL10n.text(
                    language,
                    zhHans: "当前项目 \(projectLabel)",
                    en: "Current project \(projectLabel)"
                )
            let supervisorTruthTail = role == .supervisor
                ? XTL10n.text(
                    language,
                    zhHans: "最近一次可见的实际路由仍来自 Supervisor 全局对话。",
                    en: "The latest visible actual route still comes from Supervisor global conversation."
                )
                : ""

            if let projectOverride {
                let globalText = globalModel.map {
                    XTL10n.text(
                        language,
                        zhHans: "；全局默认当前是 \($0)",
                        en: ". The current global default is \($0)"
                    )
                } ?? ""
                return XTL10n.text(
                    language,
                    zhHans: "\(subject) 当前优先使用项目内单独设置 `\(projectOverride)`；你在这里改的是当前项目，不会改全局默认\(globalText)。\(supervisorTruthTail)\(routeState)",
                    en: "The override `\(projectOverride)` for \(subject) is currently deciding the configured route. This control edits the current project only and will not change the global default\(globalText). \(supervisorTruthTail) \(routeState)"
                ) + transportHint + appendedHint(supervisorRepairHint) + governanceHint
            }

            if let globalModel {
                return XTL10n.text(
                    language,
                    zhHans: "\(subject) 当前沿用全局模型 `\(globalModel)`；你在这里一旦选择，就会写成项目单独设置。\(supervisorTruthTail)\(routeState)",
                    en: "\(subject) is currently inheriting the global model `\(globalModel)`. Choosing here will write a project override. \(supervisorTruthTail) \(routeState)"
                ) + transportHint + appendedHint(supervisorRepairHint) + governanceHint
            }

            return XTL10n.text(
                language,
                zhHans: "\(subject) 当前沿用 Hub 默认 / 自动路由；你在这里一旦选择，就会写成项目单独设置。\(supervisorTruthTail)\(routeState)",
                en: "\(subject) is currently inheriting Hub default / automatic routing. Choosing here will write a project override. \(supervisorTruthTail) \(routeState)"
            ) + transportHint + appendedHint(supervisorRepairHint) + governanceHint
        }
    }

    private static func governanceRuntimeReadinessHint(
        _ runtimeReadiness: AXProjectGovernanceRuntimeReadinessSnapshot?,
        language: XTInterfaceLanguage
    ) -> String {
        guard let runtimeReadiness,
              runtimeReadiness.requiresA4RuntimeReady else {
            return ""
        }
        let summary = XTRouteTruthPresentation.governanceRuntimeReadinessSummaryText(
            runtimeReadiness,
            language: language
        )
        guard !summary.isEmpty else { return "" }
        if let gapText = XTRouteTruthPresentation.governanceRuntimeReadinessGapText(
            runtimeReadiness,
            language: language
        ) {
            return " " + summary + " " + gapText
        }
        return " " + summary
    }

    private static func grpcTransportMismatchHint(
        configuredModelId: String,
        snapshot: AXRoleExecutionSnapshot,
        transportMode: String,
        language: XTInterfaceLanguage
    ) -> String {
        ExecutionRoutePresentation.grpcTransportMismatchHint(
            configuredModelId: configuredModelId,
            snapshot: snapshot,
            transportMode: transportMode,
            language: language
        )
    }

    private static func statusTone(_ snapshot: AXRoleExecutionSnapshot) -> HubModelRoutingBadgeTone {
        switch normalized(snapshot.executionPath) {
        case "remote_model", "direct_provider":
            return .success
        case "hub_downgraded_to_local", "local_fallback_after_remote_error":
            return .warning
        case "local_runtime", "local_preflight", "local_direct_reply", "local_direct_action", "hub_brief_projection":
            return .caution
        case "remote_error":
            return .danger
        default:
            return .neutral
        }
    }

    private static func detailTone(_ snapshot: AXRoleExecutionSnapshot) -> HubModelRoutingBadgeTone {
        switch normalized(snapshot.executionPath) {
        case "remote_model", "direct_provider":
            return .warning
        case "hub_downgraded_to_local", "local_fallback_after_remote_error":
            return .warning
        case "local_runtime", "local_preflight", "local_direct_reply", "local_direct_action", "hub_brief_projection":
            return .caution
        case "remote_error":
            return .danger
        default:
            return .neutral
        }
    }

    private static func evidenceTone(
        _ snapshot: AXRoleExecutionSnapshot,
        text: String
    ) -> HubModelRoutingBadgeTone {
        if text.hasPrefix("Deny ") {
            return normalized(snapshot.executionPath) == "remote_error" ? .danger : .warning
        }
        return .neutral
    }

    private static func projectDisplayName(
        _ projectName: String?,
        projectID: String
    ) -> String {
        if let projectName, !projectName.isEmpty {
            return "\(projectName) (\(projectID))"
        }
        return projectID
    }

    private static func appendedHint(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return " \(trimmed)"
    }

    private static func normalized(_ raw: String?) -> String? {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func displayLine(label: String, value: String) -> String {
        "\(label)：\(value)"
    }

    private static func transportLine(
        _ transportMode: String,
        language: XTInterfaceLanguage
    ) -> String? {
        guard let value = transportText(transportMode, language: language) else { return nil }
        return displayLine(
            label: XTL10n.text(language, zhHans: "当前链路", en: "Transport"),
            value: value
        )
    }

    private static func transportText(
        _ transportMode: String,
        language: XTInterfaceLanguage
    ) -> String? {
        switch normalized(transportMode) {
        case "local_fileipc":
            return XTL10n.text(language, zhHans: "本机直连", en: "Local Direct")
        case "remote_grpc_lan":
            return XTL10n.text(language, zhHans: "远端直连（局域网）", en: "Remote Direct (LAN)")
        case "remote_grpc_internet":
            return XTL10n.text(language, zhHans: "远端直连（公网）", en: "Remote Direct (Internet)")
        case "remote_grpc_tunnel":
            return XTL10n.text(language, zhHans: "远端隧道", en: "Remote Tunnel")
        case "remote_grpc":
            return XTL10n.text(language, zhHans: "远端直连", en: "Remote Direct")
        case "pairing_bootstrap":
            return XTL10n.text(language, zhHans: "连接引导中", en: "Connecting")
        case let value?:
            return value
        default:
            return nil
        }
    }
}
