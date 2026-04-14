import AppKit
import SwiftUI

enum ProjectCoderExecutionStatusPrimaryActionKind: Equatable {
    case routeDiagnose
    case openModelSettings
    case openDiagnostics
    case openHubRecovery
    case openHubConnectionLog
    case openExecutionTier
    case openGovernanceOverview
}

struct ProjectCoderExecutionStatusPrimaryActionPresentation: Equatable {
    var kind: ProjectCoderExecutionStatusPrimaryActionKind
    var title: String
    var helpText: String
}

enum ProjectCoderExecutionStatusPrimaryActionResolver {
    static func resolve(
        configuredModelId: String,
        snapshot: AXRoleExecutionSnapshot,
        hubConnected: Bool,
        governanceInterception: ProjectGovernanceInterceptionPresentation? = nil,
        language: XTInterfaceLanguage = .defaultPreference
    ) -> ProjectCoderExecutionStatusPrimaryActionPresentation? {
        guard let kind = primaryActionKind(
            configuredModelId: configuredModelId,
            snapshot: snapshot,
            hubConnected: hubConnected,
            governanceInterception: governanceInterception
        ) else {
            return nil
        }

        return ProjectCoderExecutionStatusPrimaryActionPresentation(
            kind: kind,
            title: title(for: kind, language: language),
            helpText: helpText(
                for: kind,
                snapshot: snapshot,
                hubConnected: hubConnected,
                language: language
            )
        )
    }

    @MainActor
    static func perform(
        _ action: ProjectCoderExecutionStatusPrimaryActionKind,
        configuredModelId: String,
        snapshot: AXRoleExecutionSnapshot,
        ctx: AXProjectContext,
        config: AXProjectConfig?,
        session: ChatSessionModel,
        appModel: AppModel,
        openWindow: OpenWindowAction,
        governanceInterception: ProjectGovernanceInterceptionPresentation? = nil,
        interfaceLanguage: XTInterfaceLanguage
    ) {
        recordRouteRepairAction(action, snapshot: snapshot, ctx: ctx)

        let routeSummary = ExecutionRoutePresentation.routeSummaryText(
            configuredModelId: configuredModelId,
            snapshot: snapshot
        )
        let governanceDetail = governanceOpenDetail(
            snapshot: snapshot,
            governanceInterception: governanceInterception,
            language: interfaceLanguage
        )
        let projectId = AXProjectRegistryStore.projectId(forRoot: ctx.root)

        switch action {
        case .routeDiagnose:
            session.presentProjectRouteDiagnosis(
                ctx: ctx,
                config: config,
                router: appModel.llmRouter
            )
        case .openModelSettings:
            appModel.requestModelSettingsFocus(
                role: .coder,
                title: XTL10n.RouteDiagnose.modelSettingsTitle(language: interfaceLanguage),
                detail: routeSummary ?? XTL10n.RouteDiagnose.modelSettingsFallback(language: interfaceLanguage)
            )
            SupervisorManager.shared.requestSupervisorWindow(
                sheet: .modelSettings,
                reason: "coder_status_bar_model_settings",
                focusConversation: false
            )
        case .openDiagnostics:
            appModel.requestSettingsFocus(
                sectionId: "diagnostics",
                title: XTL10n.RouteDiagnose.diagnosticsTitle(language: interfaceLanguage),
                detail: routeSummary ?? XTL10n.RouteDiagnose.diagnosticsFallback(language: interfaceLanguage)
            )
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        case .openHubRecovery:
            appModel.requestHubSetupFocus(
                sectionId: "troubleshoot",
                title: XTL10n.RouteDiagnose.hubRecoveryFocusTitle(language: interfaceLanguage),
                detail: routeSummary ?? XTL10n.RouteDiagnose.hubRecoveryFocusFallback(language: interfaceLanguage)
            )
            openWindow(id: "hub_setup")
        case .openHubConnectionLog:
            appModel.requestHubSetupFocus(
                sectionId: "connection_log",
                title: XTL10n.RouteDiagnose.hubLogFocusTitle(language: interfaceLanguage),
                detail: routeSummary ?? XTL10n.RouteDiagnose.hubLogFocusFallback(language: interfaceLanguage)
            )
            openWindow(id: "hub_setup")
        case .openExecutionTier:
            appModel.requestProjectSettingsFocus(
                projectId: projectId,
                destination: .executionTier,
                title: XTL10n.text(
                    interfaceLanguage,
                    zhHans: "治理拦截修复",
                    en: "Governance Repair"
                ),
                detail: governanceDetail ?? XTL10n.text(
                    interfaceLanguage,
                    zhHans: "最近这次动作被项目 A-Tier 拦下了，直接检查当前 A-Tier 与最低要求。",
                    en: "The latest action was blocked by the project's A-Tier. Check the current tier and minimum requirement directly."
                )
            )
        case .openGovernanceOverview:
            appModel.requestProjectSettingsFocus(
                projectId: projectId,
                destination: .overview,
                title: XTL10n.text(
                    interfaceLanguage,
                    zhHans: "治理拦截修复",
                    en: "Governance Repair"
                ),
                detail: governanceDetail ?? XTL10n.text(
                    interfaceLanguage,
                    zhHans: "最近这次动作被治理运行面拦下了，直接检查 effective governance truth、运行面限制和修复提示。",
                    en: "The latest action was blocked by the governance runtime surface. Check the effective governance truth, surface limits, and repair guidance directly."
                )
            )
        }
    }

    private static func primaryActionKind(
        configuredModelId: String,
        snapshot: AXRoleExecutionSnapshot,
        hubConnected: Bool,
        governanceInterception: ProjectGovernanceInterceptionPresentation?
    ) -> ProjectCoderExecutionStatusPrimaryActionKind? {
        if let governanceAction = governancePrimaryActionKind(governanceInterception) {
            return governanceAction
        }

        guard snapshot.hasRecord else {
            return hubConnected ? nil : .openDiagnostics
        }

        let normalizedReason = normalizedIssueCode(snapshot.effectiveFailureReasonCode)
        let normalizedDenyCode = normalizedIssueCode(snapshot.denyCode)

        if isRemoteExportGateIssue(normalizedReason) || isRemoteExportGateIssue(normalizedDenyCode) {
            return .openHubRecovery
        }

        if isModelSelectionIssue(normalizedReason) || isModelSelectionIssue(normalizedDenyCode) {
            return .openModelSettings
        }

        if let supervisorHint = supervisorGovernanceHint(for: snapshot) {
            switch supervisorHint.blockedPlane {
            case .grantReady:
                return .openGovernanceOverview
            case .routeReady:
                return hubConnected ? .openGovernanceOverview : .openDiagnostics
            case .capabilityReady, .checkpointRecoveryReady, .evidenceExportReady:
                break
            }
        }

        switch snapshot.executionPath {
        case "hub_downgraded_to_local":
            return .openHubConnectionLog
        case "local_fallback_after_remote_error", "remote_error":
            return .openDiagnostics
        default:
            break
        }

        if ExecutionRoutePresentation.inlineExplanationText(
            configuredModelId: configuredModelId,
            snapshot: snapshot
        ) != nil {
            return .routeDiagnose
        }

        return nil
    }

    private static func title(
        for kind: ProjectCoderExecutionStatusPrimaryActionKind,
        language: XTInterfaceLanguage
    ) -> String {
        switch kind {
        case .routeDiagnose:
            return XTL10n.RouteDiagnose.diagnose.resolve(language)
        case .openModelSettings:
            return XTL10n.RouteDiagnose.quickAIModels.resolve(language)
        case .openDiagnostics:
            return XTL10n.Common.xtDiagnostics.resolve(language)
        case .openHubRecovery:
            return XTL10n.RouteDiagnose.quickHubRecovery.resolve(language)
        case .openHubConnectionLog:
            return XTL10n.RouteDiagnose.quickHubLogs.resolve(language)
        case .openExecutionTier:
            return XTL10n.text(language, zhHans: "A-Tier", en: "A-Tier")
        case .openGovernanceOverview:
            return XTL10n.text(language, zhHans: "治理总览", en: "Governance Overview")
        }
    }

    private static func helpText(
        for kind: ProjectCoderExecutionStatusPrimaryActionKind,
        snapshot: AXRoleExecutionSnapshot,
        hubConnected: Bool,
        language: XTInterfaceLanguage
    ) -> String {
        switch kind {
        case .routeDiagnose:
            return XTL10n.text(
                language,
                zhHans: "运行当前项目的 route diagnose，解释为什么这轮没有按配置命中。",
                en: "Run route diagnose for the current project to explain why this turn did not hit the configured route."
            )
        case .openModelSettings:
            return RouteDiagnoseMessagePresentation.helperText(
                for: .openChooseModel,
                language: language
            )
        case .openDiagnostics:
            return XTL10n.text(
                language,
                zhHans: "这更像是 Hub 或上游远端链路问题。先打开 XT Diagnostics 看最近路由事件、连通性和失败原因。",
                en: "This looks more like a Hub or upstream remote path issue. Open XT Diagnostics first to inspect the latest route event, connectivity state, and failure reason."
            )
        case .openHubRecovery:
            return RouteDiagnoseMessagePresentation.helperText(
                for: .openHubRecovery,
                language: language
            )
        case .openHubConnectionLog:
            return RouteDiagnoseMessagePresentation.helperText(
                for: .openHubConnectionLog,
                language: language
            )
        case .openExecutionTier:
            return XTL10n.text(
                language,
                zhHans: "最近这次动作被治理拦下了。直接打开项目设置里的 A-Tier 页面，查看当前档位、最低要求和修复建议。",
                en: "The latest action was blocked by governance. Open the project's A-Tier settings directly to inspect the current tier, minimum requirement, and repair guidance."
            )
        case .openGovernanceOverview:
            if let supervisorHint = supervisorGovernanceHint(for: snapshot) {
                return [
                    supervisorHint.summaryText,
                    XTL10n.text(
                        language,
                        zhHans: "修复方向：\(supervisorHint.repairHintText)",
                        en: "repair direction: \(supervisorHint.repairHintText)"
                    ),
                    XTL10n.text(
                        language,
                        zhHans: hubConnected
                            ? "直接打开项目治理总览，检查 effective governance truth、运行面限制和修复建议。"
                            : "当前还没连上 Hub，先补通连接；如果已经连上，再回到项目治理总览继续修 preferred device、project scope 或 grant 边界。",
                        en: hubConnected
                            ? "Open the project governance overview directly to inspect the effective governance truth, runtime limits, and repair guidance."
                            : "Hub is not connected yet. Restore connectivity first, then return to the project governance overview to repair the preferred device, project scope, or grant boundary."
                    )
                ].joined(separator: " ")
            }
            return XTL10n.text(
                language,
                zhHans: "最近这次动作被治理运行面拦下了。直接打开项目治理总览，检查 effective governance truth、运行面限制和修复建议。",
                en: "The latest action was blocked by the governance runtime surface. Open the project governance overview directly to inspect the effective governance truth, surface limits, and repair guidance."
            )
        }
    }

    private static func supervisorGovernanceHint(
        for snapshot: AXRoleExecutionSnapshot,
        language: XTInterfaceLanguage = .defaultPreference
    ) -> XTSupervisorRouteGovernanceHint? {
        XTRouteTruthPresentation.supervisorRouteGovernanceHint(
            routeReasonCode: snapshot.effectiveFailureReasonCode,
            denyCode: normalizedText(snapshot.denyCode),
            language: language
        )
    }

    private static func routeRepairActionID(
        for kind: ProjectCoderExecutionStatusPrimaryActionKind
    ) -> String? {
        switch kind {
        case .routeDiagnose:
            return "open_route_diagnose"
        case .openModelSettings:
            return "open_model_settings"
        case .openDiagnostics:
            return "open_xt_diagnostics"
        case .openHubRecovery:
            return "open_hub_recovery"
        case .openHubConnectionLog:
            return "open_hub_connection_log"
        case .openExecutionTier, .openGovernanceOverview:
            return nil
        }
    }

    private static func recordRouteRepairAction(
        _ kind: ProjectCoderExecutionStatusPrimaryActionKind,
        snapshot: AXRoleExecutionSnapshot,
        ctx: AXProjectContext
    ) {
        guard let actionId = routeRepairActionID(for: kind) else { return }
        let latestEvent = AXModelRouteDiagnosticsStore.recentEvents(for: ctx, limit: 1).first
            ?? syntheticDiagnosticEvent(snapshot: snapshot, ctx: ctx)

        AXRouteRepairLogStore.record(
            actionId: actionId,
            outcome: "opened",
            latestEvent: latestEvent,
            note: "source=status_bar",
            for: ctx
        )
    }

    private static func syntheticDiagnosticEvent(
        snapshot: AXRoleExecutionSnapshot,
        ctx: AXProjectContext
    ) -> AXModelRouteDiagnosticEvent? {
        guard snapshot.hasRecord else { return nil }

        return AXModelRouteDiagnosticEvent(
            schemaVersion: AXModelRouteDiagnosticEvent.currentSchemaVersion,
            createdAt: Date().timeIntervalSince1970,
            projectId: AXProjectRegistryStore.projectId(forRoot: ctx.root),
            projectDisplayName: AXProjectRegistryStore.displayName(
                forRoot: ctx.root,
                preferredDisplayName: ctx.projectName()
            ),
            role: snapshot.role.rawValue,
            stage: snapshot.stage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "status_bar" : snapshot.stage,
            requestedModelId: snapshot.requestedModelId,
            actualModelId: snapshot.actualModelId,
            runtimeProvider: snapshot.runtimeProvider,
            executionPath: snapshot.executionPath,
            fallbackReasonCode: snapshot.fallbackReasonCode,
            auditRef: normalizedText(snapshot.auditRef),
            denyCode: normalizedText(snapshot.denyCode),
            remoteRetryAttempted: snapshot.remoteRetryAttempted,
            remoteRetryFromModelId: snapshot.remoteRetryFromModelId,
            remoteRetryToModelId: snapshot.remoteRetryToModelId,
            remoteRetryReasonCode: snapshot.remoteRetryReasonCode
        )
    }

    private static func normalizedIssueCode(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
    }

    private static func normalizedText(_ raw: String?) -> String? {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func isRemoteExportGateIssue(_ raw: String) -> Bool {
        [
            "remote_export_blocked",
            "device_remote_export_denied",
            "policy_remote_denied",
            "budget_remote_denied",
            "remote_disabled_by_user_pref"
        ].contains(raw)
    }

    private static func isModelSelectionIssue(_ raw: String) -> Bool {
        [
            "model_not_found",
            "remote_model_not_found"
        ].contains(raw)
    }

    private static func governancePrimaryActionKind(
        _ governanceInterception: ProjectGovernanceInterceptionPresentation?
    ) -> ProjectCoderExecutionStatusPrimaryActionKind? {
        guard let destination = governanceInterception?.repairHint?.destination else {
            return nil
        }

        switch destination {
        case .executionTier:
            return .openExecutionTier
        case .overview, .uiReview, .supervisorTier, .heartbeatReview:
            return .openGovernanceOverview
        }
    }

    static func governanceOpenDetail(
        snapshot: AXRoleExecutionSnapshot,
        governanceInterception: ProjectGovernanceInterceptionPresentation?,
        language: XTInterfaceLanguage = .defaultPreference
    ) -> String? {
        let lines = orderedUniqueLines(
            governanceFocusDetailLines(governanceInterception)
                + supervisorGovernanceFocusDetailLines(snapshot: snapshot, language: language)
        )

        guard !lines.isEmpty else { return nil }
        return lines.joined(separator: "\n")
    }

    private static func governanceFocusDetailLines(
        _ governanceInterception: ProjectGovernanceInterceptionPresentation?
    ) -> [String] {
        guard let governanceInterception else { return [] }

        var lines: [String] = []
        if let blockedSummary = normalizedText(governanceInterception.blockedSummary)
            ?? normalizedText(governanceInterception.governanceReason) {
            lines.append("最近治理拦截：\(blockedSummary)")
        }
        if let governanceTruth = normalizedText(governanceInterception.governanceTruthLine) {
            lines.append(governanceTruth)
        }
        if let policyReason = normalizedText(governanceInterception.policyReason) {
            lines.append("policy_reason=\(policyReason)")
        }
        if let repairAction = normalizedText(governanceInterception.repairActionSummary) {
            lines.append("repair_action=\(repairAction)")
        }

        return lines
    }

    private static func supervisorGovernanceFocusDetailLines(
        snapshot: AXRoleExecutionSnapshot,
        language: XTInterfaceLanguage
    ) -> [String] {
        guard let supervisorHint = supervisorGovernanceHint(for: snapshot, language: language) else {
            return []
        }

        var lines: [String] = [
            supervisorHint.summaryText,
            "blocked_plane=\(supervisorHint.blockedPlane.rawValue)"
        ]

        if let denyCode = normalizedText(snapshot.denyCode) {
            lines.append("deny_code=\(denyCode)")
        }
        if let auditRef = normalizedText(snapshot.auditRef) {
            lines.append("audit_ref=\(auditRef)")
        }
        lines.append("repair_direction=\(supervisorHint.repairHintText)")

        return lines
    }

    private static func orderedUniqueLines(_ lines: [String]) -> [String] {
        var seen: Set<String> = []
        var ordered: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            guard seen.insert(trimmed).inserted else { continue }
            ordered.append(trimmed)
        }

        return ordered
    }
}
