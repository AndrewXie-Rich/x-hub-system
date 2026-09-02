import Foundation

extension SupervisorManager {
    func buildVoiceReadinessSnapshot(
        appModel: AppModel,
        session: AXSessionInfo?
    ) -> VoiceReadinessSnapshot {
        VoiceReadinessAggregator.build(
            input: VoiceReadinessAggregatorInput(
                generatedAt: Date(),
                localConnected: appModel.hubConnected,
                remoteConnected: appModel.hubRemoteConnected,
                remoteRoute: appModel.hubRemoteRoute,
                linking: appModel.hubRemoteLinking,
                pairingPort: appModel.hubPairingPort,
                grpcPort: appModel.hubGrpcPort,
                internetHost: appModel.hubInternetHost,
                configuredModelIDs: configuredHubModelIDs(appModel),
                totalModelRoles: AXRole.allCases.count,
                runtimeStatus: appModel.runtimeStatus,
                modelsState: appModel.modelsState,
                bridgeAlive: appModel.bridgeAlive,
                bridgeEnabled: appModel.bridgeEnabled,
                bridgeLastError: appModel.bridgeLastEnsureError,
                sessionID: session?.id,
                sessionTitle: session?.title,
                sessionRuntime: session?.runtime,
                voiceRouteDecision: voiceRouteDecision,
                voiceRuntimeState: voiceRuntimeState,
                voiceAuthorizationStatus: voiceAuthorizationStatus,
                voicePermissionSnapshot: voicePermissionSnapshot,
                voiceActiveHealthReasonCode: voiceActiveHealthReasonCode,
                voiceSidecarHealth: voiceFunASRSidecarHealth,
                wakeProfileSnapshot: voiceWakeProfileSnapshot,
                conversationSession: conversationSessionSnapshot,
                voicePreferences: effectiveVoicePreferencesForDiagnostics(),
                voicePackReadyEvaluator: { modelID in
                    HubIPCClient.isLocalHubVoicePackPlaybackAvailable(
                        preferredModelID: modelID
                    )
                },
                firstPairCompletionProofSnapshot: appModel.unifiedDoctorReport.firstPairCompletionProofSnapshot,
                pairedRouteSetSnapshot: appModel.unifiedDoctorReport.pairedRouteSetSnapshot
            )
        )
    }

    func buildVoiceCallEntryPreflight(
        workspaceRoot: URL,
        readinessSnapshot: VoiceReadinessSnapshot
    ) -> SupervisorVoiceCallEntryPreflight? {
        if let blockingCheck = preferredVoiceCallEntryBlockingCheck(in: readinessSnapshot) {
            let detail = blockingCheck.summary.trimmingCharacters(in: .whitespacesAndNewlines)
            let nextStep = blockingCheck.nextStep.trimmingCharacters(in: .whitespacesAndNewlines)
            let combinedDetail = [detail, nextStep]
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            let actionURL = Self.troubleshootActionURL(
                repairEntry: blockingCheck.repairEntry,
                headline: blockingCheck.headline,
                detail: combinedDetail,
                detailLines: blockingCheck.detailLines
            )
            return SupervisorVoiceCallEntryPreflight(
                disposition: .block,
                headline: blockingCheck.headline,
                detail: detail.isEmpty ? nextStep : detail,
                nextStep: nextStep,
                reasonCode: blockingCheck.reasonCode,
                repairDestination: blockingCheck.repairEntry,
                actionURL: actionURL,
                actionLabel: SupervisorConversationRepairActionPlanner.plan(for: blockingCheck.repairEntry).buttonTitle
            )
        }

        guard let diagnosis = Self.xtReadySupervisorVoiceDiagnosisSnapshot(workspaceRoot: workspaceRoot) else {
            return nil
        }

        let message = diagnosis.message.trimmingCharacters(in: .whitespacesAndNewlines)
        let freshness = diagnosis.freshnessSummary().trimmingCharacters(in: .whitespacesAndNewlines)
        let detail = [freshness, message]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
        let nextStep = diagnosis.nextStep.trimmingCharacters(in: .whitespacesAndNewlines)
        let actionLabel: String? = {
            let raw = diagnosis.repairDestinationRef.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let destination = UITroubleshootDestination(rawValue: raw) else { return nil }
            return SupervisorConversationRepairActionPlanner.plan(for: destination).buttonTitle
        }()
        let repairDestination: UITroubleshootDestination? = {
            let raw = diagnosis.repairDestinationRef.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let destination = UITroubleshootDestination(rawValue: raw) else { return nil }
            return destination
        }()

        if diagnosis.status == XHubDoctorCheckStatus.fail.rawValue && !diagnosis.isStale() {
            return SupervisorVoiceCallEntryPreflight(
                disposition: .block,
                headline: diagnosis.headline,
                detail: detail.isEmpty ? "最近一次语音自检未通过。" : detail,
                nextStep: nextStep,
                reasonCode: diagnosis.status,
                repairDestination: repairDestination,
                actionURL: diagnosis.actionURL,
                actionLabel: actionLabel
            )
        }

        if diagnosis.isStale() {
            return SupervisorVoiceCallEntryPreflight(
                disposition: .advisory,
                headline: "最近一次语音自检已过期",
                detail: detail.isEmpty ? "建议先重跑 Supervisor 语音自检。" : detail,
                nextStep: nextStep.isEmpty ? "建议先在 XT Diagnostics 重跑 Supervisor 语音自检；如果你现在继续，我会直接尝试接通。" : nextStep,
                reasonCode: "voice_smoke_stale",
                repairDestination: repairDestination,
                actionURL: diagnosis.actionURL,
                actionLabel: actionLabel
            )
        }

        if diagnosis.status == XHubDoctorCheckStatus.warn.rawValue {
            return SupervisorVoiceCallEntryPreflight(
                disposition: .advisory,
                headline: diagnosis.headline,
                detail: detail.isEmpty ? "最近一次语音自检仍有待修复项。" : detail,
                nextStep: nextStep,
                reasonCode: diagnosis.status,
                repairDestination: repairDestination,
                actionURL: diagnosis.actionURL,
                actionLabel: actionLabel
            )
        }

        return nil
    }

    func preferredVoiceCallEntryBlockingCheck(
        in snapshot: VoiceReadinessSnapshot
    ) -> VoiceReadinessCheck? {
        let priority: [VoiceReadinessCheckKind] = [
            .talkLoopReadiness,
            .wakeProfileReadiness,
            .bridgeToolReadiness,
            .sessionRuntimeReadiness,
            .modelRouteReadiness,
            .pairingValidity
        ]

        for kind in priority {
            guard let check = snapshot.check(kind) else { continue }
            switch check.state {
            case .ready, .inProgress:
                continue
            case .grantRequired, .permissionDenied, .blockedWaitingUpstream, .releaseFrozen, .diagnosticRequired:
                return check
            }
        }
        return nil
    }

    func configuredHubModelIDs(_ appModel: AppModel) -> [String] {
        AXRole.allCases.compactMap { role in
            let model = (appModel.settingsStore.settings.assignment(for: role).model ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return model.isEmpty ? nil : model
        }
    }
}
