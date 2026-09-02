import Foundation

extension SupervisorManager {
    func normalizedPendingSupervisorSkillApprovals(
        projects: [AXProjectEntry]
    ) -> [SupervisorPendingSkillApproval] {
        guard let appModel else { return [] }
        var approvals: [SupervisorPendingSkillApproval] = []

        for project in projects {
            guard let ctx = appModel.projectContext(for: project.projectId) else { continue }
            let snapshot = SupervisorProjectSkillCallStore.load(for: ctx)
            let awaitingRecords = snapshot.calls.filter { $0.status == .awaitingAuthorization }
            guard !awaitingRecords.isEmpty else { continue }

            let config = supervisorProjectConfig(ctx: ctx)
            let currentProfileSnapshot = AXSkillsLibrary.projectEffectiveSkillProfileSnapshot(
                projectId: project.projectId,
                projectName: project.displayName,
                projectRoot: ctx.root,
                config: config,
                hubBaseDir: HubPaths.baseDir()
            )
            for record in awaitingRecords {
                let toolCall = resolvedSupervisorToolCallForRecord(record)
                let registryItem = resolvedSupervisorRegistryItem(
                    skillId: record.skillId,
                    projectId: project.projectId,
                    projectName: project.displayName,
                    projectRoot: ctx.root
                )
                let readiness = record.readiness ?? supervisorBaseSkillReadiness(
                    record: record,
                    project: project,
                    ctx: ctx,
                    config: config,
                    registryItem: registryItem
                ).map {
                    supervisorEffectiveSkillReadiness(
                        from: $0,
                        record: record,
                        ctx: ctx,
                        config: config,
                        toolCall: toolCall
                    )
                }
                let capability = record.requiredCapability?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let localApprovalPending = readiness?.executionReadiness == XTSkillExecutionReadinessState.localApprovalRequired.rawValue
                if !capability.isEmpty && !localApprovalPending {
                    continue
                }

                let tool = toolCall?.tool
                let requestedFamilies = !(readiness?.capabilityFamilies.isEmpty ?? true)
                    ? (readiness?.capabilityFamilies ?? [])
                    : (toolCall.map { XTSkillCapabilityProfileSupport.capabilityFamilies(for: $0.tool, args: $0.args) } ?? [])
                let deltaApproval = record.deltaApproval.flatMap { delta in
                    delta.requestId.trimmingCharacters(in: .whitespacesAndNewlines) == record.requestId
                        ? delta
                        : nil
                } ?? XTSkillCapabilityProfileSupport.deltaApproval(
                    requestId: record.requestId,
                    projectId: project.projectId,
                    projectName: project.displayName,
                    requestedSkillId: firstNonEmpty(record.requestedSkillId, record.skillId) ?? record.skillId,
                    effectiveSkillId: record.skillId,
                    toolName: record.toolName,
                    requestedCapabilityFamilies: requestedFamilies,
                    currentSnapshot: currentProfileSnapshot,
                    reason: firstNonEmpty(readiness?.reasonCode, record.resultSummary, record.policyReason) ?? "waiting for local governed approval"
                )
                approvals.append(
                    SupervisorPendingSkillApproval(
                        id: "skill:\(record.requestId)",
                        requestId: record.requestId,
                        projectId: record.projectId,
                        projectName: project.displayName,
                        jobId: record.jobId,
                        planId: record.planId,
                        stepId: record.stepId,
                        skillId: record.skillId,
                        requestedSkillId: record.requestedSkillId,
                        toolName: record.toolName,
                        tool: tool,
                        toolSummary: pendingSupervisorSkillToolSummary(record: record, toolCall: toolCall),
                        reason: pendingSupervisorSkillApprovalReason(record: record),
                        createdAt: record.createdAtMs > 0 ? Double(record.createdAtMs) / 1000.0 : nil,
                        actionURL: supervisorActionURL(
                            projectId: project.projectId,
                            requestId: record.requestId
                        ),
                        routingReasonCode: record.routingReasonCode,
                        routingExplanation: record.routingExplanation,
                        deltaApproval: deltaApproval,
                        readiness: readiness
                    )
                )
            }
        }

        return approvals.sorted { lhs, rhs in
            let lt = lhs.createdAt ?? 0
            let rt = rhs.createdAt ?? 0
            if lt != rt { return lt < rt }
            if lhs.projectName != rhs.projectName {
                return lhs.projectName.localizedCaseInsensitiveCompare(rhs.projectName) == .orderedAscending
            }
            if lhs.skillId != rhs.skillId {
                return lhs.skillId.localizedCaseInsensitiveCompare(rhs.skillId) == .orderedAscending
            }
            return lhs.requestId.localizedCaseInsensitiveCompare(rhs.requestId) == .orderedAscending
        }
    }

    func normalizedRecentSupervisorSkillActivities(
        projects: [AXProjectEntry],
        limit: Int = 8
    ) -> [SupervisorRecentSkillActivity] {
        guard let appModel, limit > 0 else { return [] }
        var activities: [SupervisorRecentSkillActivity] = []

        for project in projects {
            guard let ctx = appModel.projectContext(for: project.projectId) else { continue }
            let snapshot = SupervisorProjectSkillCallStore.load(for: ctx)
            guard !snapshot.calls.isEmpty else { continue }

            let governanceEvidenceByRequestID = recentSupervisorSkillGovernanceEvidenceByRequestID(ctx: ctx)
            let latestReview = SupervisorReviewNoteStore.latest(for: ctx)
            let latestGuidance = SupervisorGuidanceInjectionStore.latest(for: ctx)
            let pendingAckGuidance = SupervisorGuidanceInjectionStore.latestPendingAck(for: ctx)
            let resolvedGovernance = resolvedSupervisorProjectGovernanceState(
                projectId: project.projectId,
                ctx: ctx
            )
            let governanceSummary = normalizedSupervisorSkillActivityGovernanceSummary(
                latestReview: latestReview,
                latestGuidance: latestGuidance,
                pendingAckGuidance: pendingAckGuidance,
                resolvedGovernance: resolvedGovernance
            )
            for record in snapshot.calls {
                let toolCall = resolvedSupervisorToolCallForRecord(record)
                activities.append(
                    SupervisorRecentSkillActivity(
                        projectId: project.projectId,
                        projectName: project.displayName,
                        record: record,
                        tool: toolCall?.tool,
                        toolCall: toolCall,
                        toolSummary: pendingSupervisorSkillToolSummary(record: record, toolCall: toolCall),
                        actionURL: supervisorSkillActivityActionURL(
                            projectId: project.projectId,
                            record: record,
                            ctx: ctx
                        ),
                        governanceEvidence: governanceEvidenceByRequestID[record.requestId],
                        governance: governanceSummary
                    )
                )
            }
        }

        return activities.sorted { lhs, rhs in
            let leftUpdated = lhs.updatedAt ?? 0
            let rightUpdated = rhs.updatedAt ?? 0
            if leftUpdated != rightUpdated { return leftUpdated > rightUpdated }

            let leftCreated = lhs.createdAt ?? 0
            let rightCreated = rhs.createdAt ?? 0
            if leftCreated != rightCreated { return leftCreated > rightCreated }

            if lhs.projectName != rhs.projectName {
                return lhs.projectName.localizedCaseInsensitiveCompare(rhs.projectName) == .orderedAscending
            }
            if lhs.skillId != rhs.skillId {
                return lhs.skillId.localizedCaseInsensitiveCompare(rhs.skillId) == .orderedAscending
            }
            return lhs.requestId.localizedCaseInsensitiveCompare(rhs.requestId) == .orderedAscending
        }
        .prefix(limit)
        .map { $0 }
    }

    func supervisorPendingSkillApprovalSignals(
        for projects: [AXProjectEntry]
    ) -> [ProjectPermissionSignal] {
        normalizedPendingSupervisorSkillApprovals(projects: projects).map { approval in
            ProjectPermissionSignal(
                projectId: approval.projectId,
                projectName: approval.projectName,
                kind: .supervisorSkillApproval,
                summary: "等待 Supervisor 审批技能：\(capped(supervisorPendingApprovalDisplaySummary(approval), maxChars: 40))",
                createdAt: approval.createdAt,
                grantRequestId: approval.requestId,
                capability: nil,
                actionURL: approval.actionURL
            )
        }
    }

    func pendingSupervisorSkillToolSummary(
        record: SupervisorSkillCallRecord,
        toolCall: ToolCall?
    ) -> String {
        guard let toolCall else {
            return record.toolName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? record.skillId
                : record.toolName
        }

        switch toolCall.tool {
        case .read_file, .write_file:
            if let path = toolCall.args["path"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
               !path.isEmpty {
                return path
            }
        case .run_command:
            if let command = toolCall.args["command"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
               !command.isEmpty {
                return capped(command, maxChars: 72)
            }
        case .search:
            if let pattern = toolCall.args["pattern"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
               !pattern.isEmpty {
                return pattern
            }
        case .agentImportRecord:
            if let stagingId = toolCall.args["staging_id"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
               !stagingId.isEmpty {
                return stagingId
            }
        case .skills_search:
            if let query = toolCall.args["query"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
               !query.isEmpty {
                return query
            }
        case .web_search:
            if let query = toolCall.args["query"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
               !query.isEmpty {
                return query
            }
        case .summarize:
            if let url = toolCall.args["url"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
               !url.isEmpty {
                return url
            }
            if let path = toolCall.args["path"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
               !path.isEmpty {
                return path
            }
            if let text = toolCall.args["text"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
               !text.isEmpty {
                return capped(text, maxChars: 72)
            }
        case .supervisorVoicePlayback:
            if let action = toolCall.args["action"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
               !action.isEmpty {
                return action
            }
            if let text = toolCall.args["text"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
               !text.isEmpty {
                return capped(text, maxChars: 72)
            }
        case .web_fetch, .browser_read, .deviceBrowserControl:
            if let url = toolCall.args["url"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
               !url.isEmpty {
                return url
            }
            if let action = toolCall.args["action"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
               !action.isEmpty {
                return action
            }
        default:
            break
        }

        let toolName = toolCall.tool.rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return toolName.isEmpty ? record.skillId : toolName
    }

    func pendingSupervisorSkillApprovalReason(record: SupervisorSkillCallRecord) -> String {
        let summary = record.resultSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !summary.isEmpty {
            return summary
        }
        return "waiting for local governed approval"
    }
}
