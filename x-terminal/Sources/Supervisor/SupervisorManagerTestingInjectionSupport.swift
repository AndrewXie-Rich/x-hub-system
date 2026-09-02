import Foundation

extension SupervisorManager {
    func installXTReadyIncidentReportWriteAttemptOverrideForTesting(
        _ override: XTReadyIncidentReportWriteAttemptOverride?
    ) {
        Self.withXTReadyIncidentReportWriteTestingLock {
            Self.xtReadyIncidentReportWriteAttemptOverrideForTesting = override
        }
    }

    func resetXTReadyIncidentReportWriteBehaviorForTesting() {
        Self.withXTReadyIncidentReportWriteTestingLock {
            Self.xtReadyIncidentReportWriteAttemptOverrideForTesting = nil
        }
    }

    func installSupervisorVoiceSkillActionOverrideForTesting(
        _ override: SupervisorVoiceSkillActionOverride?
    ) {
        Self.withSupervisorVoiceSkillActionTestingLock {
            Self.supervisorVoiceSkillActionOverrideForTesting = override
        }
    }

    func resetSupervisorVoiceSkillActionOverrideForTesting() {
        Self.withSupervisorVoiceSkillActionTestingLock {
            Self.supervisorVoiceSkillActionOverrideForTesting = nil
        }
    }

    func automationRetryTriggerForTesting() -> String {
        automationRetryTrigger(from: automationLatestRetryPackage)
    }

    func installSupervisorBriefProjectionFetcherForTesting(
        _ fetcher: @escaping @Sendable (HubIPCClient.SupervisorBriefProjectionRequestPayload) async -> HubIPCClient.SupervisorBriefProjectionResult
    ) {
        supervisorBriefProjectionRequestOverride = fetcher
    }

    @discardableResult
    func dispatchSupervisorVoiceJobForTesting(
        _ job: SupervisorVoiceTTSJob,
        source: String,
        suppressRapidSameSourceRepeat: Bool = true,
        cancelPendingHeartbeat: Bool = false,
        now: Date = Date()
    ) -> SupervisorSpeechSynthesizer.Outcome {
        dispatchSupervisorVoiceJob(
            job,
            preferences: currentVoicePreferences(),
            source: source,
            now: now,
            suppressRapidSameSourceRepeat: suppressRapidSameSourceRepeat,
            cancelPendingHeartbeat: cancelPendingHeartbeat
        )
    }

    func installPendingHubGrantApproveOverrideForTesting(
        _ override: (@Sendable (String, String?, Int?, Int?, String) async -> HubIPCClient.PendingGrantActionResult)?
    ) {
        approvePendingHubGrantRequestOverride = override
    }

    func installPendingHubGrantDenyOverrideForTesting(
        _ override: (@Sendable (String, String?, String) async -> HubIPCClient.PendingGrantActionResult)?
    ) {
        denyPendingHubGrantRequestOverride = override
    }

    func installSchedulerSnapshotRefreshOverrideForTesting(
        _ override: (@Sendable (Bool) async -> Void)?
    ) {
        schedulerSnapshotRefreshOverride = override
    }

    func setConnectorIngressSnapshotForTesting(
        _ snapshot: HubIPCClient.ConnectorIngressSnapshot?,
        now: Date = Date()
    ) {
        connectorIngressSnapshot = snapshot
        connectorIngressLastSuccessAt = snapshot.map { max(now.timeIntervalSince1970, $0.updatedAtMs / 1000.0) } ?? 0
    }

    func installStageSupervisorCandidateReviewOverrideForTesting(
        _ override: (@Sendable (String, String) async -> HubIPCClient.SupervisorCandidateReviewStageResult)?
    ) {
        stageSupervisorCandidateReviewRequestOverride = override
    }

    func setSupervisorCandidateReviewSnapshotForTesting(
        _ snapshot: HubIPCClient.SupervisorCandidateReviewSnapshot?,
        now: Date = Date()
    ) {
        supervisorCandidateReviewSnapshot = snapshot
        supervisorCandidateReviewLastSuccessAt = snapshot.map {
            max(now.timeIntervalSince1970, $0.updatedAtMs / 1000.0)
        } ?? 0
        rebuildSupervisorCandidateReviewViewState(now: now.timeIntervalSince1970)
    }

    func setActionLedgerEntriesForTesting(
        _ entries: [(id: String, createdAt: Double, action: String, targetRef: String, projectId: String?, projectName: String?, role: String?, modelId: String?, status: String, reasonCode: String, detail: String, verifiedAt: Double?, triggerSource: String?)]
    ) {
        actionLedger = entries.map {
            SupervisorActionLedgerEntry(
                id: $0.id,
                createdAt: $0.createdAt,
                action: $0.action,
                targetRef: $0.targetRef,
                projectId: $0.projectId,
                projectName: $0.projectName,
                role: $0.role,
                modelId: $0.modelId,
                status: $0.status,
                reasonCode: $0.reasonCode,
                detail: $0.detail,
                verifiedAt: $0.verifiedAt,
                triggerSource: $0.triggerSource
            )
        }
    }

    func setPendingGrantSnapshotForTesting(
        _ snapshot: HubIPCClient.PendingGrantSnapshot?,
        now: Date = Date()
    ) {
        pendingGrantSnapshot = snapshot
        pendingGrantLastSuccessAt = snapshot.map { max(now.timeIntervalSince1970, $0.updatedAtMs / 1000.0) } ?? 0
        rebuildPendingHubGrantViewState(now: now.timeIntervalSince1970)
    }

    func directSupervisorLocalPreflightReplyIfApplicableForTesting(_ userMessage: String) async -> String? {
        await handleLocalPreflightCommand(userMessage)
    }

    func pendingSupervisorSkillApprovalDisplaySkillForTesting(
        _ approval: SupervisorPendingSkillApproval
    ) -> String {
        supervisorPendingApprovalDisplaySummary(approval)
    }

    func supervisorSkillDisplaySummaryForTesting(
        requestedSkillId: String?,
        effectiveSkillId: String,
        payload: [String: JSONValue] = [:]
    ) -> String {
        supervisorSkillDisplaySummary(
            requestedSkillId: requestedSkillId,
            effectiveSkillId: effectiveSkillId,
            payload: payload
        )
    }

    func conciseVoiceReplyScriptForTesting(_ text: String) -> [String] {
        conciseVoiceReplyScript(text)
    }

    func renderXTReadyIncidentEventsStatusForTesting() -> String {
        renderXTReadyIncidentEventsStatus()
    }

    func renderXTReadyIncidentExportSummaryForTesting(
        _ result: XTReadyIncidentEventsExportResult
    ) -> String {
        renderXTReadyIncidentExportSummary(result)
    }

    func renderDoctorSummaryForTesting(_ report: SupervisorDoctorReport) -> String {
        renderDoctorSummary(report)
    }

    func renderSecretsDryRunSummaryForTesting(_ report: SupervisorDoctorReport) -> String {
        renderSecretsDryRunSummary(report)
    }

    func summarizedSupervisorSkillOutputForTesting(
        _ output: String,
        ok: Bool,
        toolCall: ToolCall? = nil
    ) -> String {
        summarizedSupervisorSkillOutput(output, ok: ok, toolCall: toolCall)
    }

    func queueSupervisorEventLoopTurnForTesting(
        userMessage: String,
        triggerSource: String,
        dedupeKey: String
    ) {
        queueSupervisorEventLoopTurn(
            userMessage: userMessage,
            triggerSource: SupervisorCommandTriggerSource.parse(triggerSource),
            dedupeKey: dedupeKey
        )
    }

    func recentSupervisorEventLoopActivitiesForTesting() -> [SupervisorEventLoopActivity] {
        recentSupervisorEventLoopActivities
    }

    func completePendingHubGrantActionForTesting(
        grant: SupervisorPendingGrant,
        approve: Bool,
        result: HubIPCClient.PendingGrantActionResult
    ) async {
        let grantId = grant.grantRequestId.trimmingCharacters(in: .whitespacesAndNewlines)
        if !grantId.isEmpty {
            pendingHubGrantActionsInFlight.insert(grantId)
        }
        await completePendingHubGrantAction(
            grantId: grantId,
            grant: grant,
            approve: approve,
            result: result
        )
    }

    func sanitizedSupervisorOutboundPromptForTesting(_ text: String) -> String {
        sanitizeSupervisorOutboundPrompt(text)
    }

    func currentSupervisorModelRouteSummaryForTesting(
        _ userMessage: String,
        projects: [AXProjectEntry]? = nil
    ) -> String {
        contextualSupervisorModelRouteSummary(
            userMessage: userMessage,
            projects: projects ?? allProjects()
        )
    }

    func supervisorLatestTurnRoutingDecisionForTesting() -> SupervisorTurnRoutingDecision? {
        supervisorLatestTurnRoutingDecision
    }

    func supervisorLatestTurnContextAssemblyForTesting() -> SupervisorTurnContextAssemblyResult? {
        supervisorLatestTurnContextAssembly
    }

    func supervisorLatestModelRouteContextForTesting() -> SupervisorModelRouteContext? {
        supervisorLatestModelRouteContext
    }

    func projectTranscriptObservationForTesting(_ project: AXProjectEntry) -> String {
        focusedProjectTranscriptObservationBlock(
            selection: SupervisorFocusedProjectSelection(
                project: project,
                source: "testing"
            )
        )
    }

    func supervisorAfterTurnWritebackClassificationForTesting() -> SupervisorAfterTurnWritebackClassification? {
        supervisorAfterTurnWritebackClassification
    }

    func supervisorPersonaStatusLineForTesting() -> String {
        supervisorPersonaStatusLine
    }

    func currentVoicePreferencesForTesting() -> VoiceRuntimePreferences {
        currentVoicePreferences()
    }

}
