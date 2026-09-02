import Foundation

extension SupervisorManager {
    func heartbeatVoiceReadinessSignal() -> HeartbeatVoiceReadinessSignal? {
        let snapshot = voiceReadinessSnapshot
        guard !snapshot.checks.isEmpty else { return nil }
        guard let check = heartbeatEligibleVoiceReadinessCheck(in: snapshot) else {
            return nil
        }
        return HeartbeatVoiceReadinessSignal(
            kind: check.kind,
            readyForFirstTask: snapshot.readyForFirstTask,
            overallSummary: snapshot.overallSummary,
            headline: check.headline,
            nextStep: check.nextStep,
            reasonCode: check.reasonCode,
            repairEntry: check.repairEntry,
            actionURL: Self.troubleshootActionURL(
                repairEntry: check.repairEntry,
                headline: check.headline,
                detail: [check.summary, check.nextStep]
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    .joined(separator: "\n"),
                detailLines: check.detailLines
            )
        )
    }

    func heartbeatEligibleVoiceReadinessCheck(
        in snapshot: VoiceReadinessSnapshot
    ) -> VoiceReadinessCheck? {
        if snapshot.readyForFirstTask {
            return snapshot.checks.first { heartbeatShouldSurfaceAdvisoryVoiceReadiness($0) }
        }
        return snapshot.checks.first { heartbeatShouldSurfaceBlockingVoiceReadiness($0) }
    }

    func heartbeatShouldSurfaceAdvisoryVoiceReadiness(
        _ check: VoiceReadinessCheck
    ) -> Bool {
        guard check.state != .ready else { return false }
        switch check.kind {
        case .pairingValidity, .wakeProfileReadiness, .talkLoopReadiness, .ttsReadiness:
            return true
        case .modelRouteReadiness, .bridgeToolReadiness, .sessionRuntimeReadiness:
            return false
        }
    }

    func heartbeatShouldSurfaceBlockingVoiceReadiness(
        _ check: VoiceReadinessCheck
    ) -> Bool {
        guard check.state != .ready else { return false }
        guard heartbeatVoiceReadinessStateIsActionable(check.state) else {
            return false
        }
        switch check.kind {
        case .bridgeToolReadiness, .sessionRuntimeReadiness:
            return true
        case .pairingValidity, .modelRouteReadiness, .wakeProfileReadiness, .talkLoopReadiness, .ttsReadiness:
            return false
        }
    }

    func heartbeatVoiceReadinessStateIsActionable(
        _ state: XTUISurfaceState
    ) -> Bool {
        switch state {
        case .permissionDenied, .grantRequired, .diagnosticRequired, .releaseFrozen:
            return true
        case .blockedWaitingUpstream, .inProgress, .ready:
            return false
        }
    }

    nonisolated static func troubleshootActionURL(
        repairEntry: UITroubleshootDestination,
        headline: String,
        detail: String,
        detailLines: [String] = []
    ) -> String? {
        let normalizedHeadline = headline.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedDetail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = normalizedHeadline.isEmpty ? nil : normalizedHeadline
        let detailText = normalizedDetail.isEmpty ? nil : normalizedDetail

        switch repairEntry {
        case .xtPairHub:
            return XTDeepLinkURLBuilder.settingsURL(
                sectionId: "pair_hub",
                title: title,
                detail: detailText
            )?.absoluteString
        case .xtChooseModel:
            return XTDeepLinkURLBuilder.supervisorModelSettingsURL(
                title: title,
                detail: detailText
            )?.absoluteString
        case .xtDiagnostics:
            return XTDeepLinkURLBuilder.settingsURL(
                sectionId: "diagnostics",
                title: title,
                detail: detailText
            )?.absoluteString
        case .xtExternalTerminals:
            return XTDeepLinkURLBuilder.settingsURL(
                sectionId: "external_terminals",
                title: title,
                detail: detailText
            )?.absoluteString
        case .hubPairing:
            return XTDeepLinkURLBuilder.hubSetupURL(
                sectionId: "pair_progress",
                title: title,
                detail: detailText
            )?.absoluteString
        case .hubLAN:
            return XTDeepLinkURLBuilder.hubSetupURL(
                sectionId: "pair_progress",
                title: title,
                detail: detailText
            )?.absoluteString
        case .hubModels:
            return XTDeepLinkURLBuilder.hubSetupURL(
                sectionId: "choose_model",
                title: title,
                detail: detailText
            )?.absoluteString
        case .hubProviderKeys:
            return RELFlowHubActionURLBuilder.providerKeysSettingsURL(
                sourceRef: providerKeyIssueSourceRef(from: detailLines)
            )?.absoluteString
        case .hubGrants, .hubSecurity, .hubDiagnostics:
            return XTDeepLinkURLBuilder.hubSetupURL(
                sectionId: "troubleshoot",
                title: title,
                detail: detailText
            )?.absoluteString
        case .systemPermissions, .homeSupervisor:
            return XTDeepLinkURLBuilder.supervisorSettingsURL()?.absoluteString
        }
    }

    private nonisolated static func providerKeyIssueSourceRef(from detailLines: [String]) -> String? {
        XTProviderKeyImportSourcePresentation.issues(fromDoctorDetailLines: detailLines)
            .lazy
            .map(\.sourceRef)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    func heartbeatVoiceReadinessActionURL(
        repairEntry: UITroubleshootDestination,
        headline: String,
        detail: String,
        detailLines: [String] = []
    ) -> String? {
        Self.troubleshootActionURL(
            repairEntry: repairEntry,
            headline: headline,
            detail: detail,
            detailLines: detailLines
        )
    }
}
