import Foundation

extension SupervisorManager {
    func knownProjectMatching(_ project: AXProjectEntry) -> AXProjectEntry? {
        knownProjectMatching(
            projectId: project.projectId,
            projectName: project.displayName,
            rootPath: project.rootPath
        )
    }

    func knownProjectMatching(
        projectId: String,
        projectName: String,
        rootPath: String? = nil
    ) -> AXProjectEntry? {
        let normalizedProjectId = projectId.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedProjectName = normalizedLookupKey(projectName)
        let normalizedRootPath = rootPath.flatMap { rawPath -> String? in
            let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return AXProjectRegistryStore.normalizedRootPath(URL(fileURLWithPath: trimmed))
        }
        return knownProjects().first { candidate in
            if !normalizedProjectId.isEmpty &&
                candidate.projectId.compare(normalizedProjectId, options: .caseInsensitive) == .orderedSame {
                return true
            }
            if !normalizedProjectName.isEmpty &&
                normalizedLookupKey(candidate.displayName) == normalizedProjectName {
                return true
            }
            guard let normalizedRootPath else { return false }
            let candidateRootPath = candidate.rootPath.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !candidateRootPath.isEmpty else { return false }
            return AXProjectRegistryStore.normalizedRootPath(URL(fileURLWithPath: candidateRootPath)) == normalizedRootPath
        }
    }

    func projectVisibleInCurrentSupervisorJurisdiction(_ project: AXProjectEntry) -> Bool {
        let registry = syncSupervisorJurisdictionRegistry(with: knownProjects())
        return registry.allowsProjectVisibility(project)
    }

    func projectVisibleInCurrentSupervisorJurisdiction(projectId: String) -> Bool {
        let normalizedProjectId = projectId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedProjectId.isEmpty else { return false }
        guard let project = knownProjects().first(where: {
            $0.projectId.compare(normalizedProjectId, options: .caseInsensitive) == .orderedSame
        }) else {
            return false
        }
        return projectVisibleInCurrentSupervisorJurisdiction(project)
    }

    func projectVisibleInCurrentSupervisorJurisdictionOrUnknown(_ project: AXProjectEntry) -> Bool {
        guard let knownProject = knownProjectMatching(project) else {
            return true
        }
        return projectVisibleInCurrentSupervisorJurisdiction(knownProject)
    }

    func projectVisibleInCurrentSupervisorJurisdictionOrUnknown(
        projectId: String,
        projectName: String
    ) -> Bool {
        guard let knownProject = knownProjectMatching(
            projectId: projectId,
            projectName: projectName
        ) else {
            return true
        }
        return projectVisibleInCurrentSupervisorJurisdiction(knownProject)
    }

    func supervisorCandidateReviewVisibleInCurrentSupervisorJurisdictionOrUnknown(
        _ item: HubIPCClient.SupervisorCandidateReviewItem
    ) -> Bool {
        let primaryProjectId = item.projectId.trimmingCharacters(in: .whitespacesAndNewlines)
        if !primaryProjectId.isEmpty {
            return projectVisibleInCurrentSupervisorJurisdictionOrUnknown(
                projectId: primaryProjectId,
                projectName: primaryProjectId
            )
        }

        let projectIds = supervisorCandidateReviewProjectIDs(item)
        guard !projectIds.isEmpty else { return true }
        return projectIds.contains { projectId in
            projectVisibleInCurrentSupervisorJurisdictionOrUnknown(
                projectId: projectId,
                projectName: projectId
            )
        }
    }

    func supervisorEventLoopTriggerVisibleInCurrentSupervisorJurisdictionOrUnknown(
        _ trigger: SupervisorEventLoopTrigger
    ) -> Bool {
        projectVisibleInCurrentSupervisorJurisdictionOrUnknown(
            projectId: trigger.projectId,
            projectName: trigger.projectName
        )
    }

    func scopedItemVisibleInCurrentSupervisorJurisdiction(
        projectId: String?,
        projectName: String?,
        requiresKnownProjectMatch: Bool
    ) -> Bool {
        let normalizedProjectId = projectId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let normalizedProjectName = projectName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if normalizedProjectId.isEmpty && normalizedProjectName.isEmpty {
            return !requiresKnownProjectMatch
        }
        if requiresKnownProjectMatch {
            guard let knownProject = knownProjectMatching(
                projectId: normalizedProjectId,
                projectName: normalizedProjectName
            ) else {
                return false
            }
            return projectVisibleInCurrentSupervisorJurisdiction(knownProject)
        }
        return projectVisibleInCurrentSupervisorJurisdictionOrUnknown(
            projectId: normalizedProjectId,
            projectName: normalizedProjectName
        )
    }

    func messageVisibleInCurrentSupervisorJurisdiction(
        _ message: SupervisorMessage
    ) -> Bool {
        scopedItemVisibleInCurrentSupervisorJurisdiction(
            projectId: message.projectId,
            projectName: message.projectName,
            requiresKnownProjectMatch: message.requiresKnownProjectMatch
        )
    }

    func runtimeActivityVisibleInCurrentSupervisorJurisdiction(
        _ entry: RuntimeActivityEntry
    ) -> Bool {
        scopedItemVisibleInCurrentSupervisorJurisdiction(
            projectId: entry.projectId,
            projectName: entry.projectName,
            requiresKnownProjectMatch: entry.requiresKnownProjectMatch
        )
    }

    func runtimeActivityEntry(
        _ entry: RuntimeActivityEntry,
        matches project: AXProjectEntry
    ) -> Bool {
        let projectId = entry.projectId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let projectName = entry.projectName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !projectId.isEmpty,
           projectId.compare(project.projectId, options: .caseInsensitive) == .orderedSame {
            return true
        }
        if !projectName.isEmpty,
           projectName.compare(project.displayName, options: .caseInsensitive) == .orderedSame {
            return true
        }
        return false
    }

    func actionLedgerEntryVisibleInCurrentSupervisorJurisdiction(
        _ entry: SupervisorActionLedgerEntry
    ) -> Bool {
        scopedItemVisibleInCurrentSupervisorJurisdiction(
            projectId: entry.projectId,
            projectName: entry.projectName,
            requiresKnownProjectMatch: false
        )
    }

    func actionLedgerEntry(
        _ entry: SupervisorActionLedgerEntry,
        matches project: AXProjectEntry
    ) -> Bool {
        let projectId = entry.projectId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let projectName = entry.projectName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !projectId.isEmpty,
           projectId.compare(project.projectId, options: .caseInsensitive) == .orderedSame {
            return true
        }
        if !projectName.isEmpty,
           projectName.compare(project.displayName, options: .caseInsensitive) == .orderedSame {
            return true
        }
        return false
    }

    func actionLedgerEntriesForPrompt(
        focusedSelection: SupervisorFocusedProjectSelection?
    ) -> [SupervisorActionLedgerEntry] {
        guard let focusedSelection else {
            return actionLedger.filter(actionLedgerEntryVisibleInCurrentSupervisorJurisdiction(_:))
        }

        let explicitHiddenProjectFocus = focusedSelection.source == "explicit_user_mention" &&
            !projectVisibleInCurrentSupervisorJurisdiction(focusedSelection.project)
        if explicitHiddenProjectFocus {
            return actionLedger.filter {
                actionLedgerEntry($0, matches: focusedSelection.project)
            }
        }

        return actionLedger.filter(actionLedgerEntryVisibleInCurrentSupervisorJurisdiction(_:))
    }

    func supervisorIncidentVisibleInCurrentSupervisorJurisdictionOrUnknown(
        _ incident: SupervisorLaneIncident
    ) -> Bool {
        guard let projectId = incident.projectID?.uuidString else {
            return true
        }
        guard let knownProject = knownProjectMatching(
            projectId: projectId,
            projectName: ""
        ) else {
            return false
        }
        return projectVisibleInCurrentSupervisorJurisdiction(knownProject)
    }

    func supervisorIncidentScopedProjectId(
        _ incident: SupervisorLaneIncident
    ) -> String? {
        incident.projectID?.uuidString
    }

    func supervisorIncidentVisibleProjectId(
        _ incident: SupervisorLaneIncident
    ) -> String? {
        guard let projectId = supervisorIncidentScopedProjectId(incident),
              knownProjectMatching(projectId: projectId, projectName: "") != nil else {
            return nil
        }
        return projectId
    }

    func supervisorIncidentProjectText(
        _ incident: SupervisorLaneIncident
    ) -> String {
        if let projectId = supervisorIncidentVisibleProjectId(incident),
           let project = knownProjectMatching(projectId: projectId, projectName: "") {
            let displayName = project.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            return displayName.isEmpty ? projectId : displayName
        }
        return incident.projectID == nil ? "当前项目" : "redacted"
    }

    func supervisorIncidentSeverityLabel(
        _ severity: SupervisorIncidentSeverity
    ) -> String {
        switch severity {
        case .low:
            return "低（low）"
        case .medium:
            return "中（medium）"
        case .high:
            return "高（high）"
        case .critical:
            return "关键（critical）"
        }
    }

    func supervisorIncidentStatusLabel(
        _ status: SupervisorIncidentStatus
    ) -> String {
        switch status {
        case .detected:
            return "已发现（detected）"
        case .handled:
            return "已处理（handled）"
        }
    }

    func frontstageSupervisorIncidentPresentation(
        _ incident: SupervisorLaneIncident
    ) -> SupervisorIncidentFrontstagePresentation {
        let projectText = supervisorIncidentProjectText(incident)
        let summary = SplitProposalPanelPresentation.incidentSummary(for: incident)
        let eventText = "泳道 \(incident.laneID) 事件：\(summary) · 项目：\(projectText)"
        let titleProjectText = projectText.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = titleProjectText.isEmpty
            ? "🚧 泳道需要处理"
            : "🚧 \(titleProjectText) 泳道需要处理"

        var bodyLines = [
            "项目=\(projectText)",
            "泳道=\(incident.laneID)",
            "摘要=\(summary)",
            "级别=\(supervisorIncidentSeverityLabel(incident.severity))",
            "状态=\(supervisorIncidentStatusLabel(incident.status))"
        ]
        if incident.requiresUserAck {
            bodyLines.append("需确认=是")
        }
        bodyLines.append("审计=\(incident.auditRef)")

        return SupervisorIncidentFrontstagePresentation(
            title: title,
            eventText: eventText,
            systemMessageText: "🚧 \(eventText)\n审计：\(incident.auditRef)",
            notificationBody: bodyLines.joined(separator: "\n")
        )
    }

    func frontstageIncidentProjectToken(
        _ incident: SupervisorLaneIncident
    ) -> String? {
        supervisorIncidentVisibleProjectId(incident)
    }

    var frontstagePendingHubGrants: [SupervisorPendingGrant] {
        pendingHubGrants.filter { grant in
            projectVisibleInCurrentSupervisorJurisdictionOrUnknown(
                projectId: grant.projectId,
                projectName: grant.projectName
            )
        }
    }

    var frontstageSupervisorCandidateReviews: [HubIPCClient.SupervisorCandidateReviewItem] {
        supervisorCandidateReviews.filter(supervisorCandidateReviewVisibleInCurrentSupervisorJurisdictionOrUnknown(_:))
    }

    var frontstageSupervisorCandidateReviewProjectNames: [String: String] {
        var names: [String: String] = [:]
        for project in allProjects() + knownProjects() {
            let projectId = project.projectId.trimmingCharacters(in: .whitespacesAndNewlines)
            let displayName = project.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !projectId.isEmpty, !displayName.isEmpty else { continue }
            names[projectId] = displayName
        }
        return names
    }

    var frontstageConversationMessages: [SupervisorMessage] {
        messages.filter(messageVisibleInCurrentSupervisorJurisdiction(_:))
    }

    var frontstageRuntimeActivityEntries: [RuntimeActivityEntry] {
        runtimeActivityEntries.filter(runtimeActivityVisibleInCurrentSupervisorJurisdiction(_:))
    }

    var frontstageSupervisorProjectNotificationSnapshot: SupervisorProjectNotificationSnapshot {
        SupervisorProjectNotificationSnapshot.aggregated(
            from: supervisorProjectNotificationRecords.filter { record in
                supervisorJurisdictionRegistry.allowsEventVisibility(
                    projectId: record.projectId,
                    eventType: record.eventType,
                    severity: record.severity
                )
            }
        )
    }

    var frontstageRecentProjectActionEvents: [SupervisorProjectActionEvent] {
        supervisorRecentProjectActionEvents
    }

    var frontstagePairingNotificationSignal: SupervisorPortfolioSystemNotificationSignal? {
        guard let signal = heartbeatVoiceReadinessSignal(),
              signal.kind == .pairingValidity else {
            return nil
        }

        let title = heartbeatVoiceReadinessStateText(signal)
        let summaryLine = signal.overallSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        let whyLine = heartbeatVoiceReadinessWhyImportantText(signal)
        let nextStepLine = signal.nextStep.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? heartbeatVoiceReadinessDefaultNextStepText(signal)
            : signal.nextStep
        let destinationLabel = heartbeatVoiceReadinessDestinationLabel(signal.repairEntry)
        let operationHint = heartbeatVoiceReadinessOperationHint(signal)

        var detailLines: [String] = [
            "当前状态：\(title)",
            "发生了什么：\(summaryLine.isEmpty ? signal.headline : summaryLine)",
            "为什么重要：\(whyLine)",
            "建议动作：\(nextStepLine)"
        ]
        if !destinationLabel.isEmpty {
            detailLines.append("处理入口：\(destinationLabel)")
        }
        if !operationHint.isEmpty {
            detailLines.append("打开后会做什么：\(operationHint)")
        }

        return SupervisorPortfolioSystemNotificationSignal(
            id: [
                "pairing",
                signal.readyForFirstTask ? "advisory" : "repair",
                signal.reasonCode,
                title
            ].joined(separator: ":"),
            sourceLabel: "配对信息",
            scopeLine: destinationLabel.isEmpty ? "Hub 配对 / 连接" : destinationLabel,
            title: title,
            summaryLine: summaryLine.isEmpty ? signal.headline : summaryLine,
            whyLine: whyLine,
            nextStepLine: nextStepLine,
            detailLines: detailLines,
            detailActionLabel: signal.actionURL == nil ? nil : "打开处理",
            destination: signal.actionURL.map { .openURL($0) },
            tone: signal.readyForFirstTask ? .warning : .danger,
            defaultUnread: true
        )
    }

    var frontstagePendingSupervisorSkillApprovals: [SupervisorPendingSkillApproval] {
        pendingSupervisorSkillApprovals.filter { approval in
            projectVisibleInCurrentSupervisorJurisdictionOrUnknown(
                projectId: approval.projectId,
                projectName: approval.projectName
            )
        }
    }

    var frontstageRecentSupervisorSkillActivities: [SupervisorRecentSkillActivity] {
        recentSupervisorSkillActivities.filter { activity in
            projectVisibleInCurrentSupervisorJurisdictionOrUnknown(
                projectId: activity.projectId,
                projectName: activity.projectName
            )
        }
    }

    var frontstageRecentSupervisorEventLoopActivities: [SupervisorEventLoopActivity] {
        recentSupervisorEventLoopActivities.filter { activity in
            projectVisibleInCurrentSupervisorJurisdictionOrUnknown(
                projectId: activity.projectId,
                projectName: activity.projectName
            )
        }
    }
}
