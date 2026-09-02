import Foundation

extension SupervisorManager {
    struct SupervisorMemoryLocalPromptRender {
        var text: String
        var selectedSections: [String]
        var omittedSections: [String]
        var contextRefsSelectedCount: Int
        var contextRefsOmittedCount: Int
        var evidenceItemsSelectedCount: Int
        var evidenceItemsOmittedCount: Int
    }

    func supervisorProjectListLayer(
        from digests: [SupervisorMemoryProjectDigest]
    ) -> String {
        if digests.isEmpty {
            return "(暂无项目)"
        }
        return digests.map { digest in
            """
            - \(digest.displayName)
              运行态: \(digest.runtimeState)
              记忆来源: \(digest.source)
              目标/摘要: \(digest.goal)
              当前状态: \(digest.currentState)
              下一步: \(digest.nextStep)
              阻塞: \(digest.blocker)
              recent_messages: \(digest.recentMessageCount)
            """
        }.joined(separator: "\n")
    }

    func supervisorAvailableModelsEvidence(
        from models: [HubModel]
    ) -> String {
        if models.isEmpty {
            return "(暂无可用模型)"
        }
        return models.map { model in
            var lines = [
                "- \(model.name)",
                "  ID: \(model.id)",
                "  后端: \(model.backend)",
                "  \(model.defaultLoadConfigDisplayLine)"
            ]
            if let localLoadConfigLimitLine = model.localLoadConfigLimitLine {
                lines.append("  \(localLoadConfigLimitLine)")
            }
            lines.append("  状态: \(model.state == .loaded ? "已加载" : "可用")")
            return lines.joined(separator: "\n")
        }.joined(separator: "\n")
    }

    func supervisorMemoryCanonicalLayer(
        projectDigests: [SupervisorMemoryProjectDigest],
        workflowSlice: SupervisorWorkflowMemorySlice?
    ) -> String {
        capped(
            [
                supervisorProjectListLayer(from: projectDigests),
                workflowSlice?.canonical ?? ""
            ]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n\n"),
            maxChars: 2200
        )
    }

    func buildSupervisorPortfolioBrief(
        projects: [AXProjectEntry],
        projectDigests: [SupervisorMemoryProjectDigest],
        focusedSelection: SupervisorFocusedProjectSelection?
    ) -> String {
        guard !projectDigests.isEmpty else { return "(none)" }
        let digestById = Dictionary(uniqueKeysWithValues: projectDigests.map { ($0.projectId, $0) })
        let ranked = projects.sorted { calculatePriority($0) > calculatePriority($1) }
        let activeCount = projectDigests.filter {
            $0.runtimeState.localizedCaseInsensitiveContains("进行")
                || $0.runtimeState.localizedCaseInsensitiveContains("running")
        }.count
        let infrastructureLines = supervisorInfrastructurePortfolioLines()
        let blocked = ranked.compactMap { project -> String? in
            guard let digest = digestById[project.projectId], digest.blocker != "(无)" else { return nil }
            return "- \(digest.displayName) blocker=\(digest.blocker) next=\(capped(digest.nextStep, maxChars: 80))"
        }
        let priorityOrder = ranked.prefix(6).enumerated().compactMap { index, project -> String? in
            guard let digest = digestById[project.projectId] else { return nil }
            return "\(index + 1). \(digest.displayName) runtime=\(digest.runtimeState) next=\(capped(digest.nextStep, maxChars: 80)) blocker=\(capped(digest.blocker, maxChars: 80))"
        }
        let focusCandidate = focusedSelection?.project.displayName ?? projectDigests.first?.displayName ?? "(none)"
        return """
managed_projects: \(projectDigests.count)
active_projects: \(activeCount)
blocked_projects: \(blocked.count)
focus_candidate_project: \(focusCandidate)
infrastructure:
\(infrastructureLines.isEmpty ? "(none)" : infrastructureLines.joined(separator: "\n"))
priority_order:
\(priorityOrder.isEmpty ? "(none)" : priorityOrder.joined(separator: "\n"))
top_blocked_projects:
\(blocked.prefix(4).joined(separator: "\n").isEmpty ? "(none)" : blocked.prefix(4).joined(separator: "\n"))
"""
    }

    func supervisorInfrastructurePortfolioLines() -> [String] {
        let status = supervisorOfficialSkillsChannelStatusLine.trimmingCharacters(in: .whitespacesAndNewlines)
        let transition = supervisorOfficialSkillsChannelTransitionLine.trimmingCharacters(in: .whitespacesAndNewlines)
        let topBlockers = supervisorOfficialSkillsChannelTopBlockersLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !status.isEmpty || !transition.isEmpty || !topBlockers.isEmpty else { return [] }

        var line = "official skills channel"
        if !status.isEmpty {
            line += ": \(capped(status, maxChars: 120))"
        }
        if !transition.isEmpty {
            line += " latest_transition=\(capped(transition, maxChars: 120))"
        }
        if !topBlockers.isEmpty {
            line += " \(capped(topBlockers, maxChars: 120))"
        }
        return ["- [infrastructure] \(line)"]
    }

    func supervisorInfrastructureObservationLines() -> [String] {
        let status = supervisorOfficialSkillsChannelStatusLine.trimmingCharacters(in: .whitespacesAndNewlines)
        let transition = supervisorOfficialSkillsChannelTransitionLine.trimmingCharacters(in: .whitespacesAndNewlines)
        let topBlockers = supervisorOfficialSkillsChannelTopBlockersLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !status.isEmpty || !transition.isEmpty || !topBlockers.isEmpty else { return [] }

        var parts: [String] = []
        if !status.isEmpty {
            parts.append("status=\(capped(status, maxChars: 140))")
        }
        if !transition.isEmpty {
            parts.append("latest_transition=\(capped(transition, maxChars: 140))")
        }
        if !topBlockers.isEmpty {
            parts.append("top_blockers=\(capped(topBlockers, maxChars: 140))")
        }
        return ["official_skills_channel: \(parts.joined(separator: " "))"]
    }

    func supervisorMemoryObservationsLayer(
        projectDigests: [SupervisorMemoryProjectDigest],
        focusedSelection: SupervisorFocusedProjectSelection?,
        infrastructureObservationLines: [String],
        executionBrief: SupervisorFocusedProjectExecutionBrief?,
        workflowSlice: SupervisorWorkflowMemorySlice?
    ) -> String {
        let localMemoryProjectCount = projectDigests.filter {
            $0.source.contains("local_project_memory")
        }.count
        return sanitizeSupervisorPromptIdentifiers(
            (supervisorObservationRecentEventLines(
                focusedSelection: focusedSelection
            ) + infrastructureObservationLines + [
                "managed_projects: \(projectDigests.count)",
                "projects_with_local_memory: \(localMemoryProjectCount)",
                executionBrief?.observation ?? "",
                workflowSlice?.observation ?? ""
            ]).joined(separator: "\n")
        )
    }

    func supervisorMemoryRawEvidenceLayer(
        availableModels: [HubModel],
        focusedSkillProject: AXProjectEntry?,
        skillRegistrySnapshot: SupervisorSkillRegistrySnapshot?
    ) -> String {
        let modelEvidence = sanitizeSupervisorPromptIdentifiers(
            capped(supervisorAvailableModelsEvidence(from: availableModels), maxChars: 1400)
        )
        let skillRegistryEvidence = sanitizeSupervisorPromptIdentifiers(
            capped(skillRegistrySnapshot?.memorySummary(maxItems: 6, maxChars: 2_400) ?? "", maxChars: 2_400)
        )
        let supervisorGlobalSkillRegistryEvidence = sanitizeSupervisorPromptIdentifiers(
            capped(
                focusedSkillProject == nil
                    ? ""
                    : AXSkillsLibrary.supervisorGlobalSkillRegistrySnapshot(
                        hubBaseDir: HubPaths.baseDir()
                    ).memorySummary(maxItems: 2, maxChars: 1_000),
                maxChars: 1_000
            )
        )
        return supervisorMemoryRawEvidence(
            modelEvidence: modelEvidence,
            skillRegistryEvidence: skillRegistryEvidence,
            supervisorGlobalSkillRegistryEvidence: supervisorGlobalSkillRegistryEvidence
        )
    }

    func supervisorMemoryWorkingSetLayer(
        actionWorkingSet: String,
        workflowWorkingSet: String,
        executionWorkingSet: String,
        heartbeatWorkingSet: String,
        projectTranscriptObservation: String,
        focusedProjectRetrieval: String,
        crossProjectDrillDownWorkingSet: String
    ) -> String {
        let sections = [
            actionWorkingSet.isEmpty ? "" : "[action_ledger]\n\(actionWorkingSet)",
            workflowWorkingSet.isEmpty ? "" : "[workflow]\n\(workflowWorkingSet)",
            executionWorkingSet.isEmpty ? "" : "[focused_project_execution]\n\(executionWorkingSet)",
            heartbeatWorkingSet.isEmpty ? "" : heartbeatWorkingSet,
            projectTranscriptObservation.isEmpty ? "" : projectTranscriptObservation,
            focusedProjectRetrieval.isEmpty ? "" : "[focused_project_retrieval]\n\(focusedProjectRetrieval)",
            crossProjectDrillDownWorkingSet.isEmpty ? "" : "[cross_project_drilldown]\n\(crossProjectDrillDownWorkingSet)"
        ].filter { !$0.isEmpty }

        return sections.isEmpty
            ? ""
            : sections.joined(separator: "\n\n")
    }

    func supervisorMemoryWorkingSetLayerForAssembly(
        focusedProjectSelection: SupervisorFocusedProjectSelection?,
        workflowSlice: SupervisorWorkflowMemorySlice?,
        executionBrief: SupervisorFocusedProjectExecutionBrief?,
        focusedProjectRetrieval: String
    ) -> String {
        let heartbeatWorkingSet = sanitizeSupervisorPromptIdentifiers(
            focusedProjectSelection.flatMap { selection in
                XTHeartbeatMemoryAssemblySupport.workingSetBlock(
                    from: XTHeartbeatMemoryAssemblySupport.loadProjection(
                        for: supervisorMemoryContext(for: selection.project)
                    )
                )
            } ?? ""
        )
        let projectTranscriptObservation = sanitizeSupervisorPromptIdentifiers(
            focusedProjectTranscriptObservationBlock(selection: focusedProjectSelection)
        )
        let actionWorkingSet = sanitizeSupervisorPromptIdentifiers(
            generateActionLedgerSummary(
                maxItems: 8,
                focusedSelection: focusedProjectSelection
            )
        )
        let workflowWorkingSet = sanitizeSupervisorPromptIdentifiers(
            workflowSlice?.workingSet ?? ""
        )
        let executionWorkingSet = sanitizeSupervisorPromptIdentifiers(
            executionBrief?.workingSet ?? ""
        )
        let crossProjectDrillDownWorkingSet = sanitizeSupervisorPromptIdentifiers(
            supervisorCrossProjectDrillDownWorkingSet(
                excludingProjectId: focusedProjectSelection?.project.projectId
            )
        )
        return supervisorMemoryWorkingSetLayer(
            actionWorkingSet: actionWorkingSet,
            workflowWorkingSet: workflowWorkingSet,
            executionWorkingSet: executionWorkingSet,
            heartbeatWorkingSet: heartbeatWorkingSet,
            projectTranscriptObservation: projectTranscriptObservation,
            focusedProjectRetrieval: focusedProjectRetrieval,
            crossProjectDrillDownWorkingSet: crossProjectDrillDownWorkingSet
        )
    }

    func supervisorMemoryRawEvidence(
        modelEvidence: String,
        skillRegistryEvidence: String,
        supervisorGlobalSkillRegistryEvidence: String
    ) -> String {
        """
models:
\(modelEvidence.isEmpty ? "(none)" : modelEvidence)
\(skillRegistryEvidence.isEmpty ? "" : "\nskills_registry:\n\(skillRegistryEvidence)")
\(supervisorGlobalSkillRegistryEvidence.isEmpty ? "" : "\nsupervisor_global_skills_registry:\n\(supervisorGlobalSkillRegistryEvidence)")
"""
    }

    func renderSupervisorLocalMemoryV1(
        servingProfile: XTMemoryServingProfile,
        servingGovernorSection: String,
        servingObjectContract: [String],
        constitution: String,
        canonicalLayer: String,
        observationsLayer: String,
        workingSetLayer: String,
        rawEvidence: String,
        latestUserMessage: String,
        dialogueWindow: String,
        portfolioBrief: String,
        focusedProjectAnchorPack: String,
        crossLinkRefs: String,
        longtermOutline: String,
        deltaFeed: String,
        conflictSet: String,
        contextRefs: String,
        evidencePack: String,
        contextRefsRender: SupervisorContextRefsRenderResult,
        evidencePackRender: SupervisorEvidencePackRenderResult
    ) -> SupervisorMemoryLocalPromptRender {
        let servingProfileSection = """
[SERVING_PROFILE]
profile_id: \(servingProfile.rawValue)
[/SERVING_PROFILE]
"""
        let allowedSections = Set(servingObjectContract)
        let localSections = [
            renderSupervisorMemorySection(
                id: "dialogue_window",
                tag: "DIALOGUE_WINDOW",
                body: dialogueWindow,
                allowedSections: allowedSections
            ),
            renderSupervisorMemorySection(
                id: "portfolio_brief",
                tag: "PORTFOLIO_BRIEF",
                body: portfolioBrief,
                allowedSections: allowedSections
            ),
            renderSupervisorMemorySection(
                id: "focused_project_anchor_pack",
                tag: "FOCUSED_PROJECT_ANCHOR_PACK",
                body: focusedProjectAnchorPack,
                allowedSections: allowedSections
            ),
            renderSupervisorMemorySection(
                id: "cross_link_refs",
                tag: "CROSS_LINK_REFS",
                body: crossLinkRefs,
                allowedSections: allowedSections,
                omitWhenEmpty: true
            ),
            renderSupervisorMemorySection(
                id: "longterm_outline",
                tag: "LONGTERM_OUTLINE",
                body: longtermOutline,
                allowedSections: allowedSections
            ),
            renderSupervisorMemorySection(
                id: "delta_feed",
                tag: "DELTA_FEED",
                body: deltaFeed,
                allowedSections: allowedSections
            ),
            renderSupervisorMemorySection(
                id: "conflict_set",
                tag: "CONFLICT_SET",
                body: conflictSet,
                allowedSections: allowedSections
            ),
            renderSupervisorMemorySection(
                id: "context_refs",
                tag: "CONTEXT_REFS",
                body: contextRefs,
                allowedSections: allowedSections
            ),
            renderSupervisorMemorySection(
                id: "evidence_pack",
                tag: "EVIDENCE_PACK",
                body: evidencePack,
                allowedSections: allowedSections
            )
        ].filter { !$0.isEmpty }

        let contextRefsSelectedCount = allowedSections.contains("context_refs")
            ? contextRefsRender.selectedCount
            : 0
        let contextRefsOmittedCount = allowedSections.contains("context_refs")
            ? contextRefsRender.omittedCount
            : (contextRefsRender.selectedCount + contextRefsRender.omittedCount)
        let evidenceItemsSelectedCount = allowedSections.contains("evidence_pack")
            ? evidencePackRender.selectedCount
            : 0
        let evidenceItemsOmittedCount = allowedSections.contains("evidence_pack")
            ? evidencePackRender.omittedCount
            : (evidencePackRender.selectedCount + evidencePackRender.omittedCount)

        let local = """
[MEMORY_V1]
\(servingProfileSection)
\(servingGovernorSection.isEmpty ? "" : "\n\(servingGovernorSection)")

\(localSections.joined(separator: "\n\n"))

[L0_CONSTITUTION]
\(constitution)
[/L0_CONSTITUTION]

[L1_CANONICAL]
\(canonicalLayer.isEmpty ? "(none)" : canonicalLayer)
[/L1_CANONICAL]

[L2_OBSERVATIONS]
\(observationsLayer.isEmpty ? "(none)" : observationsLayer)
[/L2_OBSERVATIONS]

[L3_WORKING_SET]
\(workingSetLayer.isEmpty ? "(none)" : workingSetLayer)
[/L3_WORKING_SET]

[L4_RAW_EVIDENCE]
\(rawEvidence.isEmpty ? "(none)" : rawEvidence)
latest_user:
\(capped(latestUserMessage, maxChars: 300))
[/L4_RAW_EVIDENCE]
[/MEMORY_V1]
"""
        let sectionSelection = supervisorActualSectionSelection(
            in: local,
            contract: servingObjectContract
        )

        return SupervisorMemoryLocalPromptRender(
            text: local,
            selectedSections: sectionSelection.selected,
            omittedSections: sectionSelection.omitted,
            contextRefsSelectedCount: contextRefsSelectedCount,
            contextRefsOmittedCount: contextRefsOmittedCount,
            evidenceItemsSelectedCount: evidenceItemsSelectedCount,
            evidenceItemsOmittedCount: evidenceItemsOmittedCount
        )
    }
}
