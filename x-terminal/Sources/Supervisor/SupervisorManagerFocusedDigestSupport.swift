import Foundation

extension SupervisorManager {
    func pendingGrantSummaryLine(
        _ grant: SupervisorPendingGrant,
        includeGrantToken: Bool,
        includeScope: Bool,
        includeReason: Bool,
        includeSource: Bool = false,
        now: TimeInterval = Date().timeIntervalSince1970
    ) -> String {
        var parts: [String] = [
            grant.projectName,
            grantCapabilityText(
                capability: grant.capability,
                modelId: grant.modelId
            )
        ]
        if includeGrantToken {
            parts.append(userFacingGrantIdentifier(pendingGrantStableToken(grant)))
        }
        if includeScope, let scope = pendingGrantScopeText(grant) {
            parts.append(scope)
        }
        if includeSource, let source = pendingGrantSourceSummary(grant, now: now) {
            parts.append("来源：\(source)")
        }
        if includeReason, let reason = pendingGrantReasonText(grant) {
            parts.append("说明：\(capped(reason, maxChars: 96))")
        }
        return parts.joined(separator: " / ")
    }

    func focusedSupervisorPendingGrantDigest(
        projectId: String,
        maxItems: Int = 3
    ) -> String {
        let grants = pendingHubGrants.filter {
            $0.projectId.trimmingCharacters(in: .whitespacesAndNewlines)
                .compare(projectId, options: .caseInsensitive) == .orderedSame
        }
        guard !grants.isEmpty else { return "(none)" }
        return grants.prefix(max(1, maxItems)).map { grant in
            "- " + pendingGrantSummaryLine(
                grant,
                includeGrantToken: true,
                includeScope: true,
                includeReason: true,
                includeSource: true
            )
        }
        .joined(separator: "\n")
    }

    func focusedSupervisorPendingSkillApprovalDigest(
        projectId: String,
        maxItems: Int = 3
    ) -> String {
        let approvals = pendingSupervisorSkillApprovals.filter {
            $0.projectId.trimmingCharacters(in: .whitespacesAndNewlines)
                .compare(projectId, options: .caseInsensitive) == .orderedSame
        }
        guard !approvals.isEmpty else { return "(none)" }
        return approvals.prefix(max(1, maxItems)).map { approval in
            var parts: [String] = [
                supervisorPendingApprovalDisplaySummary(approval),
                userFacingRequestIdentifier(approval.requestId)
            ]
            if let governanceContext = supervisorPendingApprovalDigestContext(approval), !governanceContext.isEmpty {
                parts.append("治理：\(capped(governanceContext, maxChars: 96))")
            }
            let detail = firstMeaningfulDigestValue(
                [
                    approval.toolSummary,
                    approval.reason
                ],
                treatNoValueAsPlaceholder: false
            )
            if !detail.isEmpty {
                parts.append("说明：\(capped(detail, maxChars: 96))")
            }
            let routingExplanation = approval.routingExplanation?.trimmingCharacters(
                in: .whitespacesAndNewlines
            ) ?? ""
            if !routingExplanation.isEmpty {
                parts.append("路由：\(capped(routingExplanation, maxChars: 96))")
            }
            return "- " + parts.joined(separator: " / ")
        }
        .joined(separator: "\n")
    }

    func focusedSupervisorRecentSkillActivityDigest(
        _ activities: [SupervisorRecentSkillActivity],
        maxItems: Int = 3
    ) -> String {
        guard !activities.isEmpty else { return "(none)" }
        return activities.prefix(max(1, maxItems)).map { activity in
            var parts: [String] = [
                supervisorRecentSkillActivityDisplaySummary(activity),
                userFacingRequestIdentifier(activity.requestId),
                "状态：\(SupervisorSkillActivityPresentation.statusLabel(for: activity))"
            ]
            if let governanceContext = supervisorRecentSkillActivityDigestContext(activity), !governanceContext.isEmpty {
                parts.append("治理：\(capped(governanceContext, maxChars: 96))")
            }
            let toolSummary = activity.toolSummary.trimmingCharacters(in: .whitespacesAndNewlines)
            if !toolSummary.isEmpty {
                parts.append("目标：\(capped(toolSummary, maxChars: 96))")
            }
            let detail = firstMeaningfulDigestValue(
                [
                    activity.resultSummary,
                    activity.policyReason,
                    activity.denyCode
                ],
                treatNoValueAsPlaceholder: false
            )
            if !detail.isEmpty {
                parts.append("结果：\(capped(detail, maxChars: 96))")
            }
            return "- " + parts.joined(separator: " / ")
        }
        .joined(separator: "\n")
    }

    func focusedSupervisorRecentEventLoopActivityDigest(
        _ activities: [SupervisorEventLoopActivity],
        maxItems: Int = 3
    ) -> String {
        guard !activities.isEmpty else { return "(none)" }
        return activities
            .sorted { lhs, rhs in
                if lhs.updatedAt != rhs.updatedAt {
                    return lhs.updatedAt > rhs.updatedAt
                }
                return lhs.createdAt > rhs.createdAt
            }
            .prefix(max(1, maxItems))
            .map { activity in
                var parts: [String] = [
                    "触发：\(SupervisorEventLoopFeedPresentation.triggerLabel(activity.triggerSource))",
                    "状态：\(SupervisorEventLoopFeedPresentation.statusLabel(activity.status))"
                ]
                let reason = activity.reasonCode.trimmingCharacters(in: .whitespacesAndNewlines)
                if !reason.isEmpty {
                    parts.append("原因：\(capped(reason, maxChars: 64))")
                }
                let triggerSummary = activity.triggerSummary.trimmingCharacters(in: .whitespacesAndNewlines)
                if !triggerSummary.isEmpty {
                    parts.append("摘要：\(capped(triggerSummary, maxChars: 96))")
                }
                let resultSummary = activity.resultSummary.trimmingCharacters(in: .whitespacesAndNewlines)
                if !resultSummary.isEmpty {
                    parts.append("结果：\(capped(resultSummary, maxChars: 96))")
                }
                let blockedSummary = activity.blockedSummary.trimmingCharacters(in: .whitespacesAndNewlines)
                if !blockedSummary.isEmpty {
                    parts.append("阻塞：\(capped(SupervisorBlockerPresentation.label(blockedSummary), maxChars: 96))")
                }
                return "- " + parts.joined(separator: " / ")
            }
            .joined(separator: "\n")
    }

    func focusedSupervisorRecentIncidentDigest(
        _ incidents: [SupervisorLaneIncident],
        maxItems: Int = 3
    ) -> String {
        guard !incidents.isEmpty else { return "(none)" }
        return incidents
            .sorted { lhs, rhs in
                let leftHandled = lhs.handledAtMs ?? lhs.detectedAtMs
                let rightHandled = rhs.handledAtMs ?? rhs.detectedAtMs
                if leftHandled != rightHandled {
                    return leftHandled > rightHandled
                }
                return lhs.detectedAtMs > rhs.detectedAtMs
            }
            .prefix(max(1, maxItems))
            .map { incident in
                let summary = SplitProposalPanelPresentation.incidentSummary(for: incident)
                var parts: [String] = [
                    "级别：\(supervisorIncidentSeverityLabel(incident.severity))",
                    "状态：\(supervisorIncidentStatusLabel(incident.status))",
                    "摘要：\(capped(summary, maxChars: 160))"
                ]
                if incident.requiresUserAck {
                    parts.append("需确认：是")
                }
                let detail = incident.detail.trimmingCharacters(in: .whitespacesAndNewlines)
                if !detail.isEmpty {
                    parts.append("详情：\(capped(detail, maxChars: 96))")
                }
                let auditRef = incident.auditRef.trimmingCharacters(in: .whitespacesAndNewlines)
                if !auditRef.isEmpty {
                    parts.append("审计：\(auditRef)")
                }
                return "- " + parts.joined(separator: " / ")
            }
            .joined(separator: "\n")
    }

    func focusedSupervisorRecentProjectNotificationDigest(
        projectId: String,
        maxItems: Int = 3
    ) -> String {
        let records = supervisorProjectNotificationRecords.filter {
            $0.projectId.trimmingCharacters(in: .whitespacesAndNewlines)
                .compare(projectId, options: .caseInsensitive) == .orderedSame
        }
        guard !records.isEmpty else { return "(none)" }
        return records
            .sorted { lhs, rhs in
                if lhs.occurredAt != rhs.occurredAt {
                    return lhs.occurredAt > rhs.occurredAt
                }
                return lhs.deliverySummary > rhs.deliverySummary
            }
            .prefix(max(1, maxItems))
            .map { record in
                var parts: [String] = [
                    "通道：\(record.channel.rawValue)",
                    "状态：\(record.status.rawValue)",
                    "事件：\(record.eventType.rawValue)",
                    "级别：\(record.severity.rawValue)"
                ]
                let summary = record.deliverySummary.trimmingCharacters(in: .whitespacesAndNewlines)
                if !summary.isEmpty {
                    parts.append("回执：\(capped(summary, maxChars: 96))")
                }
                return "- " + parts.joined(separator: " / ")
            }
            .joined(separator: "\n")
    }

    func focusedSupervisorRecentRuntimeActivityDigest(
        project: AXProjectEntry,
        maxItems: Int = 3
    ) -> String {
        let entries = runtimeActivityEntries.filter {
            runtimeActivityEntry($0, matches: project)
        }
        guard !entries.isEmpty else { return "(none)" }
        return entries
            .prefix(max(1, maxItems))
            .map { entry in
                "- " + capped(entry.text, maxChars: 140)
            }
            .joined(separator: "\n")
    }

    func pendingGrantSourceSummary(
        _ grant: SupervisorPendingGrant,
        now: TimeInterval = Date().timeIntervalSince1970
    ) -> String? {
        guard let ingressContext = pendingGrantIngressContext(for: grant, now: now) else {
            return nil
        }
        return "\(ingressContext.provider) / \(ingressContext.ingress)"
    }
}
