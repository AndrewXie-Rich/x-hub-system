import Foundation

enum RouteDiagnoseMessagePresentation {
    enum RepairAction: Equatable {
        case connectHubAndDiagnose
        case reconnectHubAndDiagnose
        case openChooseModel
        case openProjectGovernanceOverview
        case openHubRecovery
        case openHubConnectionLog
    }

    struct SupervisorRouteExplainability: Equatable {
        struct BlockedComponent: Equatable, Identifiable {
            var key: AXProjectGovernanceRuntimeReadinessComponentKey
            var detail: String

            var id: String { key.rawValue }
        }

        var decision: String?
        var denyCode: String?
        var auditRef: String?
        var runtimeReadinessSummary: String?
        var blockedComponentKeys: [AXProjectGovernanceRuntimeReadinessComponentKey]
        var blockedComponents: [BlockedComponent]
        var suggestedAction: String?

        var hasActionableBlocker: Bool {
            !blockedComponentKeys.isEmpty
                || !blockedComponents.isEmpty
                || denyCode != nil
                || suggestedAction != nil
        }
    }

    enum RailFeedbackTrigger {
        case inlineModelPickerOpened
        case repairSurfaceOpened(RepairAction)
        case modelSettingsOpened
        case diagnosticsOpened
        case connectivityRepairFinished(
            action: RepairAction,
            report: HubRemoteConnectReport?
        )
    }

    struct RailFeedbackPlan: Equatable {
        var notice: XTSettingsChangeNotice?
        var shouldHighlight: Bool
    }

    static let coderHeading = "Project route diagnose: coder"
    static let localizedCoderHeading = "项目路由诊断：coder"

    static func matches(_ message: AXChatMessage) -> Bool {
        message.role == .assistant && matches(content: message.content)
    }

    static func matches(content: String) -> Bool {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix(coderHeading) || trimmed.hasPrefix(localizedCoderHeading)
    }

    static func recommendation(
        config: AXProjectConfig?,
        settings: XTerminalSettings,
        ctx: AXProjectContext,
        modelsState: ModelStateSnapshot
    ) -> HubModelPickerRecommendationState? {
        let configuredModelId = normalizedModelId(
            config?.modelOverride(for: .coder)
                ?? settings.assignment(for: .coder).model
        )
        guard let guidance = AXProjectModelRouteMemoryStore.selectionGuidance(
            configuredModelId: configuredModelId,
            role: .coder,
            ctx: ctx,
            snapshot: modelsState,
            language: settings.interfaceLanguage
        ),
        let recommendedModelId = normalizedModelId(guidance.recommendedModelId) else {
            return nil
        }

        let message = normalizedModelId(guidance.recommendationText) ?? guidance.warningText
        return HubModelPickerRecommendationState(
            kind: HubModelPickerRecommendationKind(guidance.recommendationKind),
            modelId: recommendedModelId,
            message: message
        )
    }

    static func actionTitle(
        for recommendation: HubModelPickerRecommendationState,
        models: [HubModel],
        language: XTInterfaceLanguage = .defaultPreference
    ) -> String {
        XTL10n.RouteDiagnose.actionTitle(
            kind: recommendation.kind,
            modelLabel: displayLabel(for: recommendation.modelId, models: models),
            language: language
        )
    }

    static func repairAction(
        latestEvent: AXModelRouteDiagnosticEvent?,
        hubConnected: Bool,
        hubRemoteConnected: Bool,
        hasRecommendation: Bool,
        messageContent: String? = nil
    ) -> RepairAction? {
        guard shouldOfferConnectivityRepair(latestEvent: latestEvent) else {
            if let governanceRepairAction = governanceRepairAction(
                for: messageContent.flatMap(supervisorRouteExplainability(from:)),
                hubConnected: hubConnected,
                hubRemoteConnected: hubRemoteConnected
            ) {
                return governanceRepairAction
            }
            if shouldOfferChooseModelRepair(latestEvent: latestEvent, hasRecommendation: hasRecommendation) {
                return .openChooseModel
            }
            if shouldOfferHubRecoveryRepair(latestEvent: latestEvent) {
                return .openHubRecovery
            }
            if shouldOfferHubConnectionLogRepair(latestEvent: latestEvent) {
                return .openHubConnectionLog
            }
            return nil
        }
        guard !hubConnected else {
            return nil
        }
        return hubRemoteConnected ? .reconnectHubAndDiagnose : .connectHubAndDiagnose
    }

    static func supervisorRouteExplainability(
        from content: String
    ) -> SupervisorRouteExplainability? {
        let lines = content.components(separatedBy: .newlines)
        guard let headerIndex = lines.firstIndex(where: { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed == "Supervisor 路由诊断："
                || trimmed == "Supervisor 路由诊断:"
                || trimmed == "Hub supervisor route 真相："
                || trimmed == "Hub supervisor route 真相:"
                || trimmed == "Hub supervisor route truth:"
                || trimmed == "Hub supervisor route truth："
        }) else {
            return nil
        }

        var explainability = SupervisorRouteExplainability(
            decision: nil,
            denyCode: nil,
            auditRef: nil,
            runtimeReadinessSummary: nil,
            blockedComponentKeys: [],
            blockedComponents: [],
            suggestedAction: nil
        )
        var capturedSection = false

        for line in lines[(headerIndex + 1)...] {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                if capturedSection {
                    break
                }
                continue
            }

            guard trimmed.hasPrefix("- ") else {
                if capturedSection {
                    break
                }
                continue
            }

            capturedSection = true
            let payload = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)

            if consumeExplainabilityField(payload, explainability: &explainability) {
                continue
            }

            if let component = blockedComponent(from: payload) {
                explainability.blockedComponents.append(component)
                if !explainability.blockedComponentKeys.contains(component.key) {
                    explainability.blockedComponentKeys.append(component.key)
                }
            }
        }

        guard capturedSection else { return nil }
        return explainability.hasActionableBlocker || explainability.runtimeReadinessSummary != nil
            ? explainability
            : nil
    }

    static func title(
        for action: RepairAction,
        inProgress: Bool,
        language: XTInterfaceLanguage = .defaultPreference
    ) -> String {
        XTL10n.RouteDiagnose.repairTitle(
            action,
            inProgress: inProgress,
            language: language
        )
    }

    static func helperText(
        for action: RepairAction,
        language: XTInterfaceLanguage = .defaultPreference
    ) -> String {
        XTL10n.RouteDiagnose.helperText(action, language: language)
    }

    static func helperText(
        for action: RepairAction,
        explainability: SupervisorRouteExplainability?,
        language: XTInterfaceLanguage = .defaultPreference
    ) -> String {
        let base = helperText(for: action, language: language)
        guard action == .openProjectGovernanceOverview,
              let explainability,
              let hint = governanceHint(for: explainability, language: language) else {
            return base
        }

        return orderedUniqueLines([
            hint.summaryText,
            repairDirectionLine(hint.repairHintText, language: language),
            base
        ]).joined(separator: " ")
    }

    static func projectGovernanceContext(
        explainability: SupervisorRouteExplainability?,
        language: XTInterfaceLanguage = .defaultPreference
    ) -> XTSectionFocusContext {
        let fallback = XTL10n.RouteDiagnose.projectGovernanceFallback(language: language)
        let lines = explainability.map {
            supervisorRouteExplainabilityLines($0, language: language)
        } ?? []
        let detail = lines.isEmpty
            ? fallback
            : lines.joined(separator: language == .english ? "; " : "；")
        return XTSectionFocusContext(
            title: XTL10n.RouteDiagnose.projectGovernanceTitle(language: language),
            detail: detail
        )
    }

    static func supervisorRouteExplainabilityHeading(
        language: XTInterfaceLanguage = .defaultPreference
    ) -> String {
        XTL10n.text(
            language,
            zhHans: "Supervisor 路由诊断",
            en: "Supervisor Route Diagnosis"
        )
    }

    static func supervisorRouteExplainabilityLines(
        _ explainability: SupervisorRouteExplainability,
        language: XTInterfaceLanguage = .defaultPreference
    ) -> [String] {
        var lines: [String] = []
        let hint = governanceHint(for: explainability, language: language)

        if let runtimeReadinessSummary = normalizedExplainabilityValue(
            explainability.runtimeReadinessSummary
        ) {
            lines.append(
                XTL10n.text(
                    language,
                    zhHans: "runtime readiness：\(runtimeReadinessSummary)",
                    en: "runtime readiness: \(runtimeReadinessSummary)"
                )
            )
        }

        if let hint {
            lines.append(hint.summaryText)
            if explainability.blockedComponents.isEmpty {
                lines.append(
                    XTL10n.text(
                        language,
                        zhHans: "当前阻塞：\(hint.blockerText)",
                        en: "current blocker: \(hint.blockerText)"
                    )
                )
            }
        }

        if !explainability.blockedComponentKeys.isEmpty {
            let blockedPlanes = explainability.blockedComponentKeys
                .map { blockedComponentLabel($0, language: language) }
                .joined(separator: language == .english ? " / " : " / ")
            lines.append(
                XTL10n.text(
                    language,
                    zhHans: "阻塞平面：\(blockedPlanes)",
                    en: "blocked planes: \(blockedPlanes)"
                )
            )
        }

        lines += explainability.blockedComponents.map { component in
            let detail = normalizedExplainabilityValue(component.detail) ?? ""
            return XTL10n.text(
                language,
                zhHans: "\(blockedComponentLabel(component.key, language: language))：\(detail)",
                en: "\(blockedComponentLabel(component.key, language: language)): \(detail)"
            )
        }

        if let denyCode = normalizedExplainabilityValue(explainability.denyCode) {
            let denyDisplay = XTRouteTruthPresentation.denyCodeText(
                denyCode,
                language: language
            ) ?? denyCode
            lines.append(
                XTL10n.text(
                    language,
                    zhHans: "deny code：\(denyDisplay)",
                    en: "deny code: \(denyDisplay)"
                )
            )
        }

        if let suggestedAction = normalizedExplainabilityValue(explainability.suggestedAction) {
            lines.append(
                XTL10n.text(
                    language,
                    zhHans: "建议动作：\(suggestedAction)",
                    en: "next step: \(suggestedAction)"
                )
            )
        }

        if let hint {
            lines.append(repairDirectionLine(hint.repairHintText, language: language))
        }

        if let auditRef = normalizedExplainabilityValue(explainability.auditRef) {
            lines.append("audit_ref=\(auditRef)")
        }

        return orderedUniqueLines(lines)
    }

    static func focusContext(
        for action: RepairAction,
        latestEvent: AXModelRouteDiagnosticEvent?,
        recommendation: HubModelPickerRecommendationState? = nil,
        paidAccessSnapshot: HubRemotePaidAccessSnapshot? = nil,
        explainability: SupervisorRouteExplainability? = nil,
        language: XTInterfaceLanguage = .defaultPreference
    ) -> XTSectionFocusContext? {
        switch action {
        case .openChooseModel:
            return XTSectionFocusContext(
                title: XTL10n.RouteDiagnose.chooseModelFocusTitle(language: language),
                detail: focusDetail(
                    latestEvent: latestEvent,
                    fallback: XTL10n.RouteDiagnose.chooseModelFocusFallback(
                        recommendation: recommendation,
                        language: language
                    ),
                    paidAccessSnapshot: paidAccessSnapshot
                )
            )
        case .openHubRecovery:
            return XTSectionFocusContext(
                title: XTL10n.RouteDiagnose.hubRecoveryFocusTitle(language: language),
                detail: focusDetail(
                    latestEvent: latestEvent,
                    fallback: XTL10n.RouteDiagnose.hubRecoveryFocusFallback(language: language),
                    paidAccessSnapshot: paidAccessSnapshot
                )
            )
        case .openHubConnectionLog:
            return XTSectionFocusContext(
                title: XTL10n.RouteDiagnose.hubLogFocusTitle(language: language),
                detail: focusDetail(
                    latestEvent: latestEvent,
                    fallback: XTL10n.RouteDiagnose.hubLogFocusFallback(language: language),
                    paidAccessSnapshot: paidAccessSnapshot
                )
            )
        case .openProjectGovernanceOverview:
            return projectGovernanceContext(
                explainability: explainability,
                language: language
            )
        case .connectHubAndDiagnose, .reconnectHubAndDiagnose:
            return nil
        }
    }

    static func diagnosticsContext(
        latestEvent: AXModelRouteDiagnosticEvent?,
        paidAccessSnapshot: HubRemotePaidAccessSnapshot? = nil,
        language: XTInterfaceLanguage = .defaultPreference
    ) -> XTSectionFocusContext {
        XTSectionFocusContext(
            title: XTL10n.RouteDiagnose.diagnosticsTitle(language: language),
            detail: focusDetail(
                latestEvent: latestEvent,
                fallback: XTL10n.RouteDiagnose.diagnosticsFallback(language: language),
                paidAccessSnapshot: paidAccessSnapshot
            )
        )
    }

    static func modelSettingsContext(
        latestEvent: AXModelRouteDiagnosticEvent?,
        paidAccessSnapshot: HubRemotePaidAccessSnapshot? = nil,
        language: XTInterfaceLanguage = .defaultPreference
    ) -> XTSectionFocusContext {
        XTSectionFocusContext(
            title: XTL10n.RouteDiagnose.modelSettingsTitle(language: language),
            detail: focusDetail(
                latestEvent: latestEvent,
                fallback: XTL10n.RouteDiagnose.modelSettingsFallback(language: language),
                paidAccessSnapshot: paidAccessSnapshot
            )
        )
    }

    static func diagnosticsFailureContext(
        for action: RepairAction,
        report: HubRemoteConnectReport?,
        latestEvent: AXModelRouteDiagnosticEvent?,
        language: XTInterfaceLanguage = .defaultPreference
    ) -> XTSectionFocusContext {
        let reportReason = normalizedModelId(report?.reasonCode) ?? normalizedModelId(report?.summary)
        let eventText = normalizedModelId(latestEvent?.diagnosticLine(includeProject: false))
        let parts = [
            reportReason.map { "repair_reason=\($0)" },
            eventText.map { "route_event=\($0)" }
        ].compactMap { $0 }
        let detail = parts.isEmpty
            ? XTL10n.RouteDiagnose.diagnosticsFailureDetail(
                hasStructuredParts: false,
                language: language
            )
            : parts.joined(separator: language == .english ? "; " : "；")
        return XTSectionFocusContext(
            title: XTL10n.RouteDiagnose.diagnosticsFailureTitle(
                action,
                language: language
            ),
            detail: detail
        )
    }

    static func connectivityRepairNotice(
        for action: RepairAction,
        report: HubRemoteConnectReport?,
        language: XTInterfaceLanguage = .defaultPreference
    ) -> XTSettingsChangeNotice? {
        switch action {
        case .connectHubAndDiagnose, .reconnectHubAndDiagnose:
            break
        case .openChooseModel, .openProjectGovernanceOverview, .openHubRecovery, .openHubConnectionLog:
            return nil
        }

        guard let report else {
            return XTSettingsChangeNotice(
                title: XTL10n.RouteDiagnose.repairFinishedTitle(
                    action,
                    language: language
                ),
                detail: XTL10n.RouteDiagnose.repairFinishedDetail(
                    summary: nil,
                    language: language
                )
            )
        }

        if report.ok {
            return XTSettingsChangeNotice(
                title: XTL10n.RouteDiagnose.repairSucceededTitle(
                    action,
                    language: language
                ),
                detail: XTL10n.RouteDiagnose.repairSucceededDetail(
                    summary: report.summary,
                    language: language
                )
            )
        }
        return XTSettingsChangeNotice(
            title: XTL10n.RouteDiagnose.repairFailedTitle(
                action,
                language: language
            ),
            detail: XTL10n.RouteDiagnose.repairFailedDetail(
                summary: report.summary,
                language: language
            )
        )
    }

    static func actionOpenedNotice(
        for action: RepairAction,
        language: XTInterfaceLanguage = .defaultPreference
    ) -> XTSettingsChangeNotice? {
        switch action {
        case .openChooseModel:
            return XTSettingsChangeNotice(
                title: XTL10n.RouteDiagnose.actionOpenedTitle(
                    action,
                    language: language
                ),
                detail: XTL10n.RouteDiagnose.actionOpenedDetail(
                    action,
                    language: language
                )
            )
        case .openProjectGovernanceOverview:
            return XTSettingsChangeNotice(
                title: XTL10n.RouteDiagnose.actionOpenedTitle(
                    action,
                    language: language
                ),
                detail: XTL10n.RouteDiagnose.actionOpenedDetail(
                    action,
                    language: language
                )
            )
        case .openHubRecovery:
            return XTSettingsChangeNotice(
                title: XTL10n.RouteDiagnose.actionOpenedTitle(
                    action,
                    language: language
                ),
                detail: XTL10n.RouteDiagnose.actionOpenedDetail(
                    action,
                    language: language
                )
            )
        case .openHubConnectionLog:
            return XTSettingsChangeNotice(
                title: XTL10n.RouteDiagnose.actionOpenedTitle(
                    action,
                    language: language
                ),
                detail: XTL10n.RouteDiagnose.actionOpenedDetail(
                    action,
                    language: language
                )
            )
        case .connectHubAndDiagnose, .reconnectHubAndDiagnose:
            return nil
        }
    }

    static func modelSettingsOpenedNotice(
        language: XTInterfaceLanguage = .defaultPreference
    ) -> XTSettingsChangeNotice {
        XTSettingsChangeNotice(
            title: XTL10n.RouteDiagnose.modelSettingsOpenedTitle(language: language),
            detail: XTL10n.RouteDiagnose.modelSettingsOpenedDetail(language: language)
        )
    }

    static func diagnosticsOpenedNotice(
        language: XTInterfaceLanguage = .defaultPreference
    ) -> XTSettingsChangeNotice {
        XTSettingsChangeNotice(
            title: XTL10n.RouteDiagnose.diagnosticsOpenedTitle(language: language),
            detail: XTL10n.RouteDiagnose.diagnosticsOpenedDetail(language: language)
        )
    }

    static func railFeedbackPlan(
        for trigger: RailFeedbackTrigger,
        language: XTInterfaceLanguage = .defaultPreference
    ) -> RailFeedbackPlan {
        let notice: XTSettingsChangeNotice? = {
        switch trigger {
        case .inlineModelPickerOpened:
            return nil
        case .repairSurfaceOpened(let action):
            return actionOpenedNotice(for: action, language: language)
            case .modelSettingsOpened:
                return modelSettingsOpenedNotice(language: language)
            case .diagnosticsOpened:
                return diagnosticsOpenedNotice(language: language)
            case .connectivityRepairFinished(let action, let report):
                return connectivityRepairNotice(
                    for: action,
                    report: report,
                    language: language
                )
            }
        }()

        return RailFeedbackPlan(
            notice: notice,
            shouldHighlight: notice != nil
        )
    }

    static func displayLabel(
        for modelId: String,
        models: [HubModel]
    ) -> String {
        let trimmedModelId = modelId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedModelId.isEmpty else { return modelId }

        if let model = models.first(where: {
            $0.id.trimmingCharacters(in: .whitespacesAndNewlines)
                .caseInsensitiveCompare(trimmedModelId) == .orderedSame
        }) {
            let display = model.capabilityPresentationModel.displayName
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !display.isEmpty, display.count <= 24 {
                return display
            }
        }

        let catalogDisplay = XTModelCatalog.modelInfo(for: trimmedModelId).displayName
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !catalogDisplay.isEmpty, catalogDisplay.count <= 24 {
            return catalogDisplay
        }

        return trimmedModelId
    }

    private static func normalizedModelId(_ raw: String?) -> String? {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func focusDetail(
        latestEvent: AXModelRouteDiagnosticEvent?,
        fallback: String,
        paidAccessSnapshot: HubRemotePaidAccessSnapshot? = nil
    ) -> String {
        XTRouteTruthPresentation.focusDetail(
            latestEvent: latestEvent,
            fallback: fallback,
            paidAccessSnapshot: paidAccessSnapshot
        )
    }

    private static func shouldOfferConnectivityRepair(
        latestEvent: AXModelRouteDiagnosticEvent?
    ) -> Bool {
        guard let latestEvent else { return false }

        switch normalizedReasonCode(latestEvent.effectiveFailureReasonCode) {
        case "response_timeout", "grpc_route_unavailable", "runtime_not_running", "request_write_failed":
            return true
        default:
            return false
        }
    }

    private static func shouldOfferChooseModelRepair(
        latestEvent: AXModelRouteDiagnosticEvent?,
        hasRecommendation: Bool
    ) -> Bool {
        guard let latestEvent, !hasRecommendation else { return false }
        if latestIssue(for: latestEvent) == .paidModelAccessBlocked {
            return true
        }
        switch normalizedReasonCode(latestEvent.effectiveFailureReasonCode) {
        case "model_not_found", "remote_model_not_found":
            return true
        default:
            return false
        }
    }

    private static func shouldOfferHubRecoveryRepair(
        latestEvent: AXModelRouteDiagnosticEvent?
    ) -> Bool {
        guard let latestEvent else { return false }
        if latestIssue(for: latestEvent) == .connectorScopeBlocked {
            return true
        }
        switch normalizedReasonCode(latestEvent.effectiveFailureReasonCode) {
        case "remote_export_blocked", "device_remote_export_denied", "policy_remote_denied", "budget_remote_denied", "remote_disabled_by_user_pref":
            return true
        default:
            return false
        }
    }

    private static func shouldOfferHubConnectionLogRepair(
        latestEvent: AXModelRouteDiagnosticEvent?
    ) -> Bool {
        guard let latestEvent else { return false }
        switch normalizedReasonCode(latestEvent.effectiveFailureReasonCode) {
        case "downgrade_to_local":
            return true
        default:
            break
        }
        return latestEvent.executionPath.trimmingCharacters(in: .whitespacesAndNewlines) == "hub_downgraded_to_local"
    }

    private static func normalizedReasonCode(_ raw: String?) -> String {
        (raw ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
    }

    private static func governanceRepairAction(
        for explainability: SupervisorRouteExplainability?,
        hubConnected: Bool,
        hubRemoteConnected: Bool
    ) -> RepairAction? {
        guard let explainability, explainability.hasActionableBlocker else {
            return nil
        }
        guard let blockedPlane = governanceHint(for: explainability)?.blockedPlane
            ?? primaryBlockedPlane(for: explainability)
            ?? inferredBlockedPlane(from: explainability.suggestedAction) else {
            return nil
        }
        switch blockedPlane {
        case .routeReady:
            guard !hubConnected else {
                return .openProjectGovernanceOverview
            }
            return hubRemoteConnected ? .reconnectHubAndDiagnose : .connectHubAndDiagnose
        case .grantReady, .capabilityReady, .checkpointRecoveryReady, .evidenceExportReady:
            return .openProjectGovernanceOverview
        }
    }

    private static func consumeExplainabilityField(
        _ payload: String,
        explainability: inout SupervisorRouteExplainability
    ) -> Bool {
        if let decision = explainabilityValue(payload, key: "决策")
            ?? explainabilityValue(payload, key: "decision") {
            explainability.decision = normalizedExplainabilityValue(decision)
            return true
        }
        if let denyCode = explainabilityValue(payload, key: "deny_code") {
            explainability.denyCode = normalizedExplainabilityValue(denyCode)
            return true
        }
        if let auditRef = explainabilityValue(payload, key: "audit_ref") {
            explainability.auditRef = normalizedExplainabilityValue(auditRef)
            return true
        }
        if let runtimeReadiness = explainabilityValue(payload, key: "runtime readiness")
            ?? explainabilityValue(payload, key: "runtime_readiness") {
            explainability.runtimeReadinessSummary = normalizedExplainabilityValue(runtimeReadiness)
            return true
        }
        if let blockedPlanes = explainabilityValue(payload, key: "阻塞平面")
            ?? explainabilityValue(payload, key: "blocked_planes")
            ?? explainabilityValue(payload, key: "blocked_components") {
            explainability.blockedComponentKeys = parseBlockedComponentKeys(blockedPlanes)
            return true
        }
        if let suggestedAction = explainabilityValue(payload, key: "建议动作")
            ?? explainabilityValue(payload, key: "next_step") {
            explainability.suggestedAction = normalizedExplainabilityValue(suggestedAction)
            return true
        }
        return false
    }

    private static func blockedComponent(
        from payload: String
    ) -> SupervisorRouteExplainability.BlockedComponent? {
        let mappings: [(String, AXProjectGovernanceRuntimeReadinessComponentKey)] = [
            ("route plane", .routeReady),
            ("capability plane", .capabilityReady),
            ("grant plane", .grantReady),
            ("checkpoint / recovery plane", .checkpointRecoveryReady),
            ("evidence / export plane", .evidenceExportReady)
        ]

        for (label, key) in mappings {
            if let detail = explainabilityValue(payload, key: label),
               let normalizedDetail = normalizedExplainabilityValue(detail) {
                return SupervisorRouteExplainability.BlockedComponent(
                    key: key,
                    detail: normalizedDetail
                )
            }
        }

        return nil
    }

    private static func explainabilityValue(
        _ payload: String,
        key: String
    ) -> String? {
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidates = [
            "\(key)=",
            "\(key)：",
            "\(key):"
        ]

        for candidate in candidates where trimmed.hasPrefix(candidate) {
            let value = String(trimmed.dropFirst(candidate.count))
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return nil
    }

    private static func normalizedExplainabilityValue(_ raw: String?) -> String? {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        switch trimmed.lowercased() {
        case "(none)", "(unavailable)", "none", "unavailable":
            return nil
        default:
            return trimmed
        }
    }

    private static func governanceHint(
        for explainability: SupervisorRouteExplainability,
        language: XTInterfaceLanguage = .defaultPreference
    ) -> XTSupervisorRouteGovernanceHint? {
        let reason = normalizedExplainabilityValue(explainability.denyCode)
            ?? normalizedExplainabilityValue(explainability.decision)
        if let hint = XTRouteTruthPresentation.supervisorRouteGovernanceHint(
            routeReasonCode: reason,
            denyCode: explainability.denyCode,
            language: language
        ) {
            return hint
        }

        guard let blockedPlane = primaryBlockedPlane(for: explainability)
            ?? inferredBlockedPlane(from: explainability.suggestedAction) else {
            return nil
        }
        let blockerText = normalizedExplainabilityValue(
            explainability.blockedComponents.first(where: { $0.key == blockedPlane })?.detail
        ) ?? blockedComponentLabel(blockedPlane, language: language)

        switch blockedPlane {
        case .routeReady:
            return XTSupervisorRouteGovernanceHint(
                primaryCode: "route_ready",
                blockedPlane: .routeReady,
                blockerText: blockerText,
                summaryText: XTL10n.text(
                    language,
                    zhHans: "这更像是 Supervisor 到 XT / runner 的路由面还没就绪。当前阻塞：\(blockerText)。",
                    en: "This looks more like the Supervisor-to-XT/runner route plane is not ready yet. Current blocker: \(blockerText)."
                ),
                repairHintText: XTL10n.text(
                    language,
                    zhHans: "先检查 XT 在线状态、preferred device、project scope 和当前 route 目标。",
                    en: "Check XT availability, the preferred device, project scope, and the current route target first."
                )
            )
        case .grantReady:
            return XTSupervisorRouteGovernanceHint(
                primaryCode: "grant_ready",
                blockedPlane: .grantReady,
                blockerText: blockerText,
                summaryText: XTL10n.text(
                    language,
                    zhHans: "这更像是 Supervisor 的 grant / governance 面还没就绪。当前阻塞：\(blockerText)。",
                    en: "This looks more like the Supervisor grant/governance plane is not ready yet. Current blocker: \(blockerText)."
                ),
                repairHintText: XTL10n.text(
                    language,
                    zhHans: "先检查 trusted automation、permission owner、kill-switch、TTL 和当前项目绑定。",
                    en: "Check trusted automation, the permission owner, kill switch, TTL, and the current project binding first."
                )
            )
        case .capabilityReady, .checkpointRecoveryReady, .evidenceExportReady:
            return nil
        }
    }

    private static func primaryBlockedPlane(
        for explainability: SupervisorRouteExplainability
    ) -> AXProjectGovernanceRuntimeReadinessComponentKey? {
        explainability.blockedComponents.first?.key ?? explainability.blockedComponentKeys.first
    }

    private static func inferredBlockedPlane(
        from suggestedAction: String?
    ) -> AXProjectGovernanceRuntimeReadinessComponentKey? {
        guard let normalized = normalizedExplainabilityValue(suggestedAction)?.lowercased() else {
            return nil
        }
        if normalized.contains("grant") || normalized.contains("governance") {
            return .grantReady
        }
        if normalized.contains("route") || normalized.contains("preferred device") || normalized.contains("xt / runner") {
            return .routeReady
        }
        return nil
    }

    private static func repairDirectionLine(
        _ detail: String,
        language: XTInterfaceLanguage
    ) -> String {
        XTL10n.text(
            language,
            zhHans: "修复方向：\(detail)",
            en: "repair direction: \(detail)"
        )
    }

    private static func orderedUniqueLines(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if seen.insert(trimmed).inserted {
                ordered.append(trimmed)
            }
        }
        return ordered
    }

    private static func parseBlockedComponentKeys(
        _ raw: String
    ) -> [AXProjectGovernanceRuntimeReadinessComponentKey] {
        raw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .compactMap(AXProjectGovernanceRuntimeReadinessComponentKey.init(rawValue:))
    }

    private static func blockedComponentLabel(
        _ key: AXProjectGovernanceRuntimeReadinessComponentKey,
        language: XTInterfaceLanguage
    ) -> String {
        switch key {
        case .routeReady:
            return XTL10n.text(language, zhHans: "route plane", en: "route plane")
        case .capabilityReady:
            return XTL10n.text(language, zhHans: "capability plane", en: "capability plane")
        case .grantReady:
            return XTL10n.text(language, zhHans: "grant plane", en: "grant plane")
        case .checkpointRecoveryReady:
            return XTL10n.text(language, zhHans: "checkpoint / recovery plane", en: "checkpoint / recovery plane")
        case .evidenceExportReady:
            return XTL10n.text(language, zhHans: "evidence / export plane", en: "evidence / export plane")
        }
    }

    private static func latestIssue(
        for latestEvent: AXModelRouteDiagnosticEvent
    ) -> UITroubleshootIssue? {
        UITroubleshootKnowledgeBase.issue(forFailureCode: latestEvent.effectiveFailureReasonCode)
            ?? UITroubleshootKnowledgeBase.issue(forFailureCode: latestEvent.denyCode ?? "")
    }
}
