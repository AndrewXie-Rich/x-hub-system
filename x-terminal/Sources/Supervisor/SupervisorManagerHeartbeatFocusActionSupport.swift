import Foundation

extension SupervisorManager {
    func resolvedHeartbeatFocusActionURL(
        projects: [AXProjectEntry],
        progressActions: [HeartbeatAutoProgressAction],
        blockerProjects: [(projectId: String, blocker: String)],
        permissionSignals: [ProjectPermissionSignal],
        recoveryFollowUpSignal: HeartbeatRecoveryFollowUpSignal?,
        governedReviewSignal: HeartbeatGovernedReviewSignal?,
        governanceRepairSignals: [ProjectGovernanceRepairSignal],
        queueSignals: [ProjectQueueSignal],
        hubLoadSignal: HeartbeatHubLoadSignal?,
        doctorPresentation: SupervisorDoctorBoardPresentation? = nil,
        now: TimeInterval
    ) -> String? {
        let doctorPresentation = doctorPresentation ?? heartbeatDoctorBoardPresentation()
        if let actionURL = permissionSignals.first?.actionURL {
            let trimmed = actionURL.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }

        if let actionURL = heartbeatGovernanceRepairActionURL(signals: governanceRepairSignals) {
            let trimmed = actionURL.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }

        if let actionURL = recoveryFollowUpSignal?.actionURL?.trimmingCharacters(in: .whitespacesAndNewlines),
           !actionURL.isEmpty {
            return actionURL
        }

        if let actionURL = governedReviewSignal?.actionURL?.trimmingCharacters(in: .whitespacesAndNewlines),
           !actionURL.isEmpty {
            return actionURL
        }

        if blockerProjects.isEmpty,
           permissionSignals.isEmpty,
           governanceRepairSignals.isEmpty,
           recoveryFollowUpSignal == nil,
           governedReviewSignal == nil,
           let actionURL = heartbeatSkillDoctorTruthNotificationEntry(
                doctorPresentation: doctorPresentation
           )?.focusAction,
           case .openFocus(let rawURL) = actionURL.action {
            let trimmed = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }

        if blockerProjects.isEmpty,
           permissionSignals.isEmpty,
           governanceRepairSignals.isEmpty,
           let actionURL = heartbeatVoiceReadinessSignal()?.actionURL {
            let trimmed = actionURL.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }

        if blockerProjects.isEmpty,
           permissionSignals.isEmpty,
           governanceRepairSignals.isEmpty,
           let actionURL = hubLoadSignal?.actionURL {
            let trimmed = actionURL.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }

        let focusProjectId = progressActions.first?.projectId
            ?? blockerProjects.first?.projectId
            ?? permissionSignals.first?.projectId
            ?? governanceRepairSignals.first?.projectId
            ?? queueSignals.first?.project.projectId
        if let focusProjectId {
            return resumeProjectActionURL(projectId: focusProjectId)
        }

        if let routeRepairItem = heartbeatLeadRouteRepairAttentionItem(projects: projects) {
            let followUp = AXRouteRepairLogStore.latestStatusBarFollowUp(
                for: routeRepairItem.digest,
                now: now
            )
            if let followUpURL = heartbeatRouteRepairFollowUpActionURL(
                followUp,
                projectId: routeRepairItem.projectId
            ) {
                let trimmed = followUpURL.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            }
        }

        if let routeProjectId = heartbeatRouteDiagnoseProjectId(projects: projects) {
            return routeDiagnoseActionURL(projectId: routeProjectId)
        }

        if projectCreationStatusPresentation() != nil {
            return XTDeepLinkURLBuilder.supervisorURL(
                focusTarget: .projectCreationBoard
            )?.absoluteString
        }

        return XTDeepLinkURLBuilder.supervisorURL()?.absoluteString
    }

    private func heartbeatGovernanceRepairActionURL(
        signals: [ProjectGovernanceRepairSignal]
    ) -> String? {
        for signal in signals {
            let actionURL = signal.actionURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !actionURL.isEmpty {
                return actionURL
            }
        }
        return nil
    }

    private func heartbeatRouteDiagnoseProjectId(
        projects: [AXProjectEntry]
    ) -> String? {
        if let projectId = heartbeatLeadRouteRepairAttentionItem(projects: projects)?.projectId {
            return projectId
        }

        let orderedProjects = projects.sorted { p1, p2 in
            calculatePriority(p1) > calculatePriority(p2)
        }
        let routeMemorySnapshot = heartbeatRouteMemorySnapshot()
        for project in orderedProjects {
            if AXProjectModelRouteMemoryStore.heartbeatNotice(
                for: project,
                snapshot: routeMemorySnapshot
            ) != nil {
                return project.projectId
            }
        }
        return nil
    }
}
