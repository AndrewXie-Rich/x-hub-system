import Foundation

extension SupervisorManager {
    struct SupervisorMemoryEvidenceLayers {
        var contextRefItems: [SupervisorContextRefItem]
        var contextRefsRender: SupervisorContextRefsRenderResult
        var conflictSet: String
        var contextRefs: String
        var evidencePackRender: SupervisorEvidencePackRenderResult
        var evidencePack: String
    }

    func supervisorMemoryEvidenceLayers(
        servingContext: SupervisorFocusedProjectServingContext?,
        projectDigests: [SupervisorMemoryProjectDigest],
        userMessage: String
    ) -> SupervisorMemoryEvidenceLayers {
        let contextRefItems = supervisorContextRefItems(
            servingContext: servingContext,
            projectDigests: projectDigests
        )
        let contextRefsRender = buildSupervisorContextRefs(
            contextRefItems,
            servingContext: servingContext
        )
        let conflictSet = sanitizeSupervisorPromptIdentifiers(
            buildSupervisorConflictSet(
                servingContext: servingContext,
                contextRefs: contextRefItems
            )
        )
        let contextRefs = sanitizeSupervisorPromptIdentifiers(
            contextRefsRender.text
        )
        let evidencePackRender = buildSupervisorEvidencePack(
            servingContext: servingContext,
            contextRefs: contextRefItems,
            userMessage: userMessage
        )
        let evidencePack = sanitizeSupervisorPromptIdentifiers(
            evidencePackRender.text
        )

        return SupervisorMemoryEvidenceLayers(
            contextRefItems: contextRefItems,
            contextRefsRender: contextRefsRender,
            conflictSet: conflictSet,
            contextRefs: contextRefs,
            evidencePackRender: evidencePackRender,
            evidencePack: evidencePack
        )
    }

    func supervisorMemorySectionBody(
        in text: String,
        tag: String
    ) -> String? {
        let startTag = "[\(tag)]"
        let endTag = "[/\(tag)]"
        guard let startRange = text.range(of: startTag) else { return nil }
        guard let endRange = text.range(
            of: endTag,
            range: startRange.upperBound..<text.endIndex
        ) else {
            return nil
        }
        return String(text[startRange.upperBound..<endRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func supervisorReviewCursor(
        reviewId: String,
        createdAtMs: Int64
    ) -> String {
        let normalizedReviewID = reviewId.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizedReviewID.isEmpty {
            return "review:none@\(max(0, createdAtMs))"
        }
        return "review:\(normalizedReviewID)@\(max(0, createdAtMs))"
    }

    func focusedSupervisorLineageInlineDigest(
        _ body: String
    ) -> String {
        let lines = body
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasSuffix(":") }
        guard !lines.isEmpty else { return "(none)" }
        return capped(lines.prefix(4).joined(separator: " | "), maxChars: 260)
    }

    func focusedSupervisorInlineDecisionDigest(
        _ hardDecisions: [SupervisorDecisionCategory: SupervisorDecisionTrackEvent]
    ) -> String {
        let items = hardDecisions.values
            .sorted { lhs, rhs in
                if lhs.updatedAtMs != rhs.updatedAtMs {
                    return lhs.updatedAtMs > rhs.updatedAtMs
                }
                return lhs.category.rawValue < rhs.category.rawValue
            }
            .prefix(3)
            .map { decision in
                "\(decision.category.rawValue)=\(capped(firstNonEmptyLine(in: decision.statement), maxChars: 64))"
            }
        return items.isEmpty ? "(none)" : items.joined(separator: " | ")
    }

    func focusedSupervisorJoinedValueList(
        _ values: [String],
        maxItems: Int,
        maxChars: Int
    ) -> String {
        let normalized = values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(maxItems)
            .map { capped($0, maxChars: maxChars) }
        return normalized.isEmpty ? "(none)" : normalized.joined(separator: " | ")
    }

    func supervisorContextRefItems(
        servingContext: SupervisorFocusedProjectServingContext?,
        projectDigests: [SupervisorMemoryProjectDigest]
    ) -> [SupervisorContextRefItem] {
        var items: [SupervisorContextRefItem] = []
        var seen = Set<String>()
        let now = Date().timeIntervalSince1970

        func append(
            refId rawRefId: String?,
            refKind: String,
            title: String,
            sourceScope: String,
            tokenCostHint: String,
            updatedAtMs: Int64
        ) {
            let refId = rawRefId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !refId.isEmpty else { return }
            guard seen.insert(refId).inserted else { return }
            let freshness = SupervisorProjectCapsuleBuilder.memoryFreshness(
                updatedAt: Double(max(0, updatedAtMs)) / 1000.0,
                now: now
            ).rawValue
            items.append(
                SupervisorContextRefItem(
                    refId: refId,
                    refKind: refKind,
                    title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                    sourceScope: sourceScope.trimmingCharacters(in: .whitespacesAndNewlines),
                    tokenCostHint: tokenCostHint.trimmingCharacters(in: .whitespacesAndNewlines),
                    freshnessHint: freshness
                )
            )
        }

        if !projectDigests.isEmpty {
            append(
                refId: "portfolio_brief://supervisor",
                refKind: "canonical_ref",
                title: "portfolio brief / managed projects \(projectDigests.count)",
                sourceScope: "portfolio_brief",
                tokenCostHint: "low",
                updatedAtMs: Int64((now * 1000.0).rounded())
            )
        }

        guard let servingContext else { return items }
        let heartbeatProjection = XTHeartbeatMemoryAssemblySupport.loadProjection(for: servingContext.ctx)

        append(
            refId: "delta_feed:\(servingContext.project.projectId)",
            refKind: "observation_ref",
            title: "delta feed / \(servingContext.project.displayName)",
            sourceScope: "delta_feed",
            tokenCostHint: "low",
            updatedAtMs: Int64((now * 1000.0).rounded())
        )

        if let specCapsule = servingContext.governance.specCapsule {
            append(
                refId: specCapsule.sourceRefs.first ?? "spec_capsule:\(servingContext.project.projectId)",
                refKind: "canonical_ref",
                title: "spec capsule / \(servingContext.project.displayName)",
                sourceScope: "spec_capsule",
                tokenCostHint: "medium",
                updatedAtMs: specCapsule.updatedAtMs
            )
        }

        if !servingContext.longtermOutlineBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            append(
                refId: "longterm_outline:\(servingContext.project.projectId)",
                refKind: "longterm_ref",
                title: "longterm outline / \(servingContext.project.displayName)",
                sourceScope: "longterm_outline",
                tokenCostHint: "medium",
                updatedAtMs: Int64((servingContext.digest.updatedAt * 1000.0).rounded())
            )
        }

        for heartbeatRef in XTHeartbeatMemoryAssemblySupport.contextRefs(from: heartbeatProjection) {
            let refId = heartbeatRef.refId.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !refId.isEmpty, seen.insert(refId).inserted else { continue }
            items.append(
                SupervisorContextRefItem(
                    refId: refId,
                    refKind: heartbeatRef.refKind,
                    title: heartbeatRef.title.trimmingCharacters(in: .whitespacesAndNewlines),
                    sourceScope: heartbeatRef.sourceScope.trimmingCharacters(in: .whitespacesAndNewlines),
                    tokenCostHint: heartbeatRef.tokenCostHint.trimmingCharacters(in: .whitespacesAndNewlines),
                    freshnessHint: heartbeatRef.freshnessHint.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            )
        }

        let decisionEvents = servingContext.governance.hardDecisions.values.sorted { lhs, rhs in
            if lhs.updatedAtMs != rhs.updatedAtMs {
                return lhs.updatedAtMs > rhs.updatedAtMs
            }
            return lhs.category.rawValue < rhs.category.rawValue
        }
        for decision in decisionEvents.prefix(4) {
            append(
                refId: decision.evidenceRefs.first ?? decision.auditRef,
                refKind: "canonical_ref",
                title: "approved decision / \(decision.category.rawValue)",
                sourceScope: "decision_track",
                tokenCostHint: "medium",
                updatedAtMs: decision.updatedAtMs
            )
        }

        for pin in servingContext.governance.selectedEvidencePins.prefix(4) {
            append(
                refId: pin.auditRef.isEmpty ? "selected_evidence:\(pin.pinId)" : pin.auditRef,
                refKind: "evidence_ref",
                title: "selected evidence / \(capped(pin.summary, maxChars: 44))",
                sourceScope: "selected_evidence",
                tokenCostHint: "low",
                updatedAtMs: pin.createdAtMs
            )
        }

        if let latestReview = servingContext.latestReview {
            append(
                refId: latestReview.memoryCursor ?? supervisorReviewCursor(
                    reviewId: latestReview.reviewId,
                    createdAtMs: latestReview.createdAtMs
                ),
                refKind: "observation_ref",
                title: "latest review / \(servingContext.project.displayName)",
                sourceScope: "review_note",
                tokenCostHint: "medium",
                updatedAtMs: latestReview.createdAtMs
            )
        }

        if let latestGuidance = servingContext.pendingAckGuidance ?? servingContext.latestGuidance {
            append(
                refId: latestGuidance.auditRef.isEmpty ? "guidance:\(latestGuidance.injectionId)" : latestGuidance.auditRef,
                refKind: "workflow_ref",
                title: "latest guidance / \(servingContext.project.displayName)",
                sourceScope: "guidance_injection",
                tokenCostHint: "medium",
                updatedAtMs: max(latestGuidance.injectedAtMs, latestGuidance.ackUpdatedAtMs)
            )
        }

        if let activeJob = servingContext.activeJob {
            append(
                refId: activeJob.auditRef.isEmpty ? "job:\(activeJob.jobId)" : activeJob.auditRef,
                refKind: "workflow_ref",
                title: "active job / \(activeJob.jobId)",
                sourceScope: "workflow_job",
                tokenCostHint: "low",
                updatedAtMs: activeJob.updatedAtMs
            )
        }

        if let activePlan = servingContext.activePlan {
            append(
                refId: activePlan.auditRef.isEmpty ? "plan:\(activePlan.planId)" : activePlan.auditRef,
                refKind: "workflow_ref",
                title: "active plan / \(activePlan.planId)",
                sourceScope: "workflow_plan",
                tokenCostHint: "medium",
                updatedAtMs: activePlan.updatedAtMs
            )
        }

        if let activeSkillCall = servingContext.activeSkillCall {
            append(
                refId: activeSkillCall.auditRef.isEmpty ? "skill_call:\(activeSkillCall.requestId)" : activeSkillCall.auditRef,
                refKind: "workflow_ref",
                title: "active skill call / \(supervisorSkillDisplaySummary(activeSkillCall))",
                sourceScope: "workflow_skill_call",
                tokenCostHint: "medium",
                updatedAtMs: activeSkillCall.updatedAtMs
            )
        }

        if let latestUIReviewEvidence = XTUIReviewAgentEvidenceStore.loadLatestBrowserPage(for: servingContext.ctx) {
            append(
                refId: XTUIReviewAgentEvidenceStore.reviewRef(reviewID: latestUIReviewEvidence.reviewID),
                refKind: "evidence_ref",
                title: "latest ui review agent evidence / \(servingContext.project.displayName)",
                sourceScope: "ui_review_agent_evidence",
                tokenCostHint: "medium",
                updatedAtMs: latestUIReviewEvidence.updatedAtMs
            )
        }

        if !servingContext.recent.messages.isEmpty {
            append(
                refId: AXRecentContextStore.jsonURL(for: servingContext.ctx).path,
                refKind: "observation_ref",
                title: "recent context / \(servingContext.project.displayName)",
                sourceScope: "recent_context",
                tokenCostHint: "medium",
                updatedAtMs: Int64((servingContext.recent.updatedAt * 1000.0).rounded())
            )
        }

        return items
    }

    func buildSupervisorContextRefs(
        _ items: [SupervisorContextRefItem],
        servingContext: SupervisorFocusedProjectServingContext?
    ) -> SupervisorContextRefsRenderResult {
        guard !items.isEmpty else {
            return SupervisorContextRefsRenderResult(
                text: "(none)",
                selectedCount: 0,
                omittedCount: 0
            )
        }
        let maxItems: Int
        switch servingContext?.servingProfile {
        case .m4FullScan:
            maxItems = 14
        case .m3DeepDive:
            maxItems = 12
        default:
            maxItems = 10
        }
        let selectedItems = Array(items.prefix(maxItems))
        let text = selectedItems
            .map { item in
                "- ref_id=\(item.refId) ref_kind=\(item.refKind) title=\(capped(item.title, maxChars: 72)) source_scope=\(item.sourceScope) token_cost_hint=\(item.tokenCostHint) freshness_hint=\(item.freshnessHint)"
            }
            .joined(separator: "\n")
        return SupervisorContextRefsRenderResult(
            text: text.isEmpty ? "(none)" : text,
            selectedCount: selectedItems.count,
            omittedCount: max(0, items.count - selectedItems.count)
        )
    }

    func buildSupervisorConflictSet(
        servingContext: SupervisorFocusedProjectServingContext?,
        contextRefs: [SupervisorContextRefItem]
    ) -> String {
        guard let servingContext else { return "(none)" }

        let specRef = contextRefs.first(where: { $0.sourceScope == "spec_capsule" })?.refId
        let longtermRef = contextRefs.first(where: { $0.sourceScope == "longterm_outline" })?.refId
        let decisionRefs = contextRefs
            .filter { $0.sourceScope == "decision_track" }
            .map(\.refId)
        let guidanceRef = contextRefs.first(where: { $0.sourceScope == "guidance_injection" })?.refId
        let jobRef = contextRefs.first(where: { $0.sourceScope == "workflow_job" })?.refId
        let planRef = contextRefs.first(where: { $0.sourceScope == "workflow_plan" })?.refId
        let reviewRef = contextRefs.first(where: { $0.sourceScope == "review_note" })?.refId

        var conflicts: [SupervisorConflictItem] = []

        if !servingContext.governance.missingSpecFields.isEmpty,
           servingContext.activeJob != nil || servingContext.activePlan != nil {
            conflicts.append(
                SupervisorConflictItem(
                    conflictId: "conflict-spec-vs-execution-\(servingContext.project.projectId)",
                    conflictKind: "canonical_vs_observation",
                    summary: "formal spec 仍有关键锚点缺失，但项目已经进入受治理执行态",
                    sideA: "spec_capsule missing_fields=\(servingContext.governance.missingSpecFields.map(\.rawValue).joined(separator: ", "))",
                    sideB: "workflow active_job=\(servingContext.activeJob?.jobId ?? "(none)") active_plan=\(servingContext.activePlan?.planId ?? "(none)")",
                    resolutionStatus: "open",
                    refs: orderedUniqueSupervisorRefs([specRef, jobRef, planRef].compactMap { $0 })
                )
            )
        }

        if let guidance = servingContext.pendingAckGuidance ?? servingContext.latestGuidance,
           guidance.deliveryMode == .replanRequest,
           !servingContext.governance.hardDecisions.isEmpty {
            conflicts.append(
                SupervisorConflictItem(
                    conflictId: "conflict-decision-vs-guidance-\(guidance.injectionId)",
                    conflictKind: "decision_vs_guidance",
                    summary: "已批准决策仍在当前 anchor 中，但最新 supervisor guidance 请求 replan",
                    sideA: focusedSupervisorInlineDecisionDigest(servingContext.governance.hardDecisions),
                    sideB: "guidance=\(SupervisorGuidanceTextPresentation.summary(guidance.guidanceText, maxChars: 120))",
                    resolutionStatus: guidance.ackRequired && guidance.ackStatus == .pending ? "pending_guidance_ack" : "open",
                    refs: orderedUniqueSupervisorRefs(decisionRefs + [guidanceRef].compactMap { $0 })
                )
            )
        }

        if !isDigestPlaceholder(servingContext.digest.blocker, treatNoValueAsPlaceholder: true),
           containsAny(
                normalizedSupervisorIntentText(servingContext.digest.runtimeState),
                ["进行中", "running", "active", "推进", "working"]
           ) {
            conflicts.append(
                SupervisorConflictItem(
                    conflictId: "conflict-runtime-vs-memory-\(servingContext.project.projectId)",
                    conflictKind: "runtime_vs_memory",
                    summary: "runtime_state 仍显示推进中，但当前记忆已经显式记录 blocker",
                    sideA: "runtime_state=\(servingContext.digest.runtimeState)",
                    sideB: "blocker=\(capped(servingContext.digest.blocker, maxChars: 120))",
                    resolutionStatus: "open",
                    refs: orderedUniqueSupervisorRefs([jobRef, planRef, reviewRef].compactMap { $0 })
                )
            )
        }

        if let latestReview = servingContext.latestReview,
           !latestReview.anchorDoneDefinition.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !servingContext.doneDefinition.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           latestReview.anchorDoneDefinition != servingContext.doneDefinition {
            conflicts.append(
                SupervisorConflictItem(
                    conflictId: "conflict-done-definition-drift-\(latestReview.reviewId)",
                    conflictKind: "longterm_vs_recent_execution",
                    summary: "当前 done_definition 与最近一次 strategic review 的 anchor 已发生漂移",
                    sideA: "latest_review_done_definition=\(capped(latestReview.anchorDoneDefinition, maxChars: 120))",
                    sideB: "current_done_definition=\(capped(servingContext.doneDefinition, maxChars: 120))",
                    resolutionStatus: "watch",
                    refs: orderedUniqueSupervisorRefs([reviewRef, specRef, longtermRef].compactMap { $0 })
                )
            )
        }

        guard !conflicts.isEmpty else { return "(none)" }
        return conflicts
            .prefix(4)
            .map { item in
                """
                - conflict_id: \(item.conflictId)
                  conflict_kind: \(item.conflictKind)
                  summary: \(item.summary)
                  side_a: \(item.sideA)
                  side_b: \(item.sideB)
                  resolution_status: \(item.resolutionStatus)
                  refs: \(item.refs.isEmpty ? "(none)" : item.refs.joined(separator: " | "))
                """
            }
            .joined(separator: "\n")
    }

    func buildSupervisorEvidencePack(
        servingContext: SupervisorFocusedProjectServingContext?,
        contextRefs: [SupervisorContextRefItem],
        userMessage: String
    ) -> SupervisorEvidencePackRenderResult {
        guard let servingContext else {
            return SupervisorEvidencePackRenderResult(
                text: "(none)",
                selectedCount: 0,
                omittedCount: 0
            )
        }
        let expandedEvidence = servingContext.servingProfile.rank >= XTMemoryServingProfile.m3DeepDive.rank
        let maxSelectedItems: Int
        switch servingContext.servingProfile {
        case .m4FullScan:
            maxSelectedItems = 8
        case .m3DeepDive:
            maxSelectedItems = 6
        default:
            maxSelectedItems = 4
        }

        func ref(for sourceScope: String) -> SupervisorContextRefItem? {
            contextRefs.first(where: { $0.sourceScope == sourceScope })
        }

        func refs(for sourceScope: String) -> [SupervisorContextRefItem] {
            contextRefs.filter { $0.sourceScope == sourceScope }
        }

        var items: [SupervisorEvidenceItem] = []

        if let specCapsule = servingContext.governance.specCapsule,
           let specRef = ref(for: "spec_capsule") {
            let excerpt = [
                "goal=\(specCapsule.goal)",
                "done_definition=\(specCapsule.mvpDefinition)",
                "non_goals=\(focusedSupervisorJoinedValueList(specCapsule.nonGoals, maxItems: 2, maxChars: 60))"
            ].joined(separator: " | ")
            items.append(
                SupervisorEvidenceItem(
                    refId: specRef.refId,
                    title: specRef.title,
                    excerpt: excerpt,
                    whyIncluded: "stable_goal_and_done_definition",
                    sourceScope: specRef.sourceScope,
                    freshnessHint: specRef.freshnessHint
                )
            )
        }

        if items.isEmpty,
           let longtermRef = ref(for: "longterm_outline") {
            items.append(
                SupervisorEvidenceItem(
                    refId: longtermRef.refId,
                    title: longtermRef.title,
                    excerpt: servingContext.longtermOutlineBody,
                    whyIncluded: "durable_background_outline",
                    sourceScope: longtermRef.sourceScope,
                    freshnessHint: longtermRef.freshnessHint
                )
            )
        }

        if expandedEvidence,
           let longtermRef = ref(for: "longterm_outline"),
           !servingContext.longtermOutlineBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            items.append(
                SupervisorEvidenceItem(
                    refId: longtermRef.refId,
                    title: longtermRef.title,
                    excerpt: focusedSupervisorLineageInlineDigest(servingContext.longtermOutlineBody),
                    whyIncluded: "durable_background_outline",
                    sourceScope: longtermRef.sourceScope,
                    freshnessHint: longtermRef.freshnessHint
                )
            )
        }

        if let latestReview = servingContext.latestReview,
           let reviewRef = ref(for: "review_note") {
            let excerpt = [
                "verdict=\(latestReview.verdict.rawValue)",
                "summary=\(capped(latestReview.summary, maxChars: 120))",
                "next_action=\(capped(latestReview.recommendedActions.first ?? "(none)", maxChars: 80))"
            ].joined(separator: " | ")
            items.append(
                SupervisorEvidenceItem(
                    refId: reviewRef.refId,
                    title: reviewRef.title,
                    excerpt: excerpt,
                    whyIncluded: "latest_supervisor_verdict",
                    sourceScope: reviewRef.sourceScope,
                    freshnessHint: reviewRef.freshnessHint
                )
            )
        }

        if let latestUIReviewEvidence = XTUIReviewAgentEvidenceStore.loadLatestBrowserPage(for: servingContext.ctx),
           let uiReviewRef = ref(for: "ui_review_agent_evidence") {
            let trend = latestUIReviewEvidence.trend.first ?? "(none)"
            let issues = latestUIReviewEvidence.issueCodes.isEmpty
                ? "(none)"
                : latestUIReviewEvidence.issueCodes.joined(separator: ", ")
            let excerpt = [
                "verdict=\(latestUIReviewEvidence.verdict.rawValue)",
                "issues=\(issues)",
                "trend=\(trend)",
                "summary=\(capped(latestUIReviewEvidence.summary, maxChars: 120))"
            ].joined(separator: " | ")
            items.append(
                SupervisorEvidenceItem(
                    refId: uiReviewRef.refId,
                    title: uiReviewRef.title,
                    excerpt: excerpt,
                    whyIncluded: "latest_ui_review_agent_evidence",
                    sourceScope: uiReviewRef.sourceScope,
                    freshnessHint: uiReviewRef.freshnessHint
                )
            )
        }

        let selectedEvidenceLimit = expandedEvidence ? 2 : 1
        let selectedEvidenceRefs = refs(for: "selected_evidence")
        for (index, pin) in servingContext.governance.selectedEvidencePins.prefix(selectedEvidenceLimit).enumerated() {
            guard index < selectedEvidenceRefs.count else { break }
            let evidenceRef = selectedEvidenceRefs[index]
            let excerpt = [
                "summary=\(capped(pin.summary, maxChars: 120))",
                "source=\(capped(pin.sourceNote, maxChars: 60))",
                "why=\(capped(pin.whyItMatters, maxChars: 80))"
            ].joined(separator: " | ")
            items.append(
                SupervisorEvidenceItem(
                    refId: evidenceRef.refId,
                    title: evidenceRef.title,
                    excerpt: excerpt,
                    whyIncluded: "user_selected_evidence",
                    sourceScope: evidenceRef.sourceScope,
                    freshnessHint: evidenceRef.freshnessHint
                )
            )
        }

        if let guidance = servingContext.pendingAckGuidance ?? servingContext.latestGuidance,
           let guidanceRef = ref(for: "guidance_injection") {
            let excerpt = [
                "ack_status=\(guidance.ackStatus.rawValue)",
                "delivery=\(guidance.deliveryMode.rawValue)",
                "guidance=\(SupervisorGuidanceTextPresentation.summary(guidance.guidanceText, maxChars: 120))"
            ].joined(separator: " | ")
            items.append(
                SupervisorEvidenceItem(
                    refId: guidanceRef.refId,
                    title: guidanceRef.title,
                    excerpt: excerpt,
                    whyIncluded: guidance.ackRequired && guidance.ackStatus == .pending
                        ? "active_guidance_guardrail_pending_ack"
                        : "active_guidance_guardrail",
                    sourceScope: guidanceRef.sourceScope,
                    freshnessHint: guidanceRef.freshnessHint
                )
            )
        }

        let decisionEvents = servingContext.governance.hardDecisions.values.sorted { lhs, rhs in
            if lhs.updatedAtMs != rhs.updatedAtMs {
                return lhs.updatedAtMs > rhs.updatedAtMs
            }
            return lhs.category.rawValue < rhs.category.rawValue
        }
        let decisionItemLimit = expandedEvidence ? 2 : 1
        for decision in decisionEvents.prefix(decisionItemLimit) {
            let preferredDecisionRefId = decision.evidenceRefs.first ?? decision.auditRef
            guard let decisionRef = contextRefs.first(where: {
                $0.sourceScope == "decision_track" && $0.refId == preferredDecisionRefId
            }) else {
                continue
            }
            let excerpt = expandedEvidence
                ? "category=\(decision.category.rawValue) | statement=\(capped(firstNonEmptyLine(in: decision.statement), maxChars: 120)) | source=\(capped(decision.source, maxChars: 60))"
                : "\(decision.category.rawValue)=\(capped(firstNonEmptyLine(in: decision.statement), maxChars: 140))"
            items.append(
                SupervisorEvidenceItem(
                    refId: decisionRef.refId,
                    title: decisionRef.title,
                    excerpt: excerpt,
                    whyIncluded: expandedEvidence ? "decision_lineage_anchor" : "approved_decision_anchor",
                    sourceScope: decisionRef.sourceScope,
                    freshnessHint: decisionRef.freshnessHint
                )
            )
        }

        if let activeJob = servingContext.activeJob,
           let workflowRef = ref(for: "workflow_plan") ?? ref(for: "workflow_job") {
            let excerpt = [
                "job=\(activeJob.jobId)",
                "goal=\(capped(activeJob.goal, maxChars: 100))",
                "next_pending=\(capped(servingContext.nextPendingStepsDigest, maxChars: 120))",
                "attention=\(capped(servingContext.attentionStepsDigest, maxChars: 120))"
            ].joined(separator: " | ")
            items.append(
                SupervisorEvidenceItem(
                    refId: workflowRef.refId,
                    title: workflowRef.title,
                    excerpt: excerpt,
                    whyIncluded: "active_workflow_state",
                    sourceScope: workflowRef.sourceScope,
                    freshnessHint: workflowRef.freshnessHint
                )
            )
        } else if let recentRef = ref(for: "recent_context") {
            items.append(
                SupervisorEvidenceItem(
                    refId: recentRef.refId,
                    title: recentRef.title,
                    excerpt: servingContext.recentMessagesDigest,
                    whyIncluded: "recent_project_messages",
                    sourceScope: recentRef.sourceScope,
                    freshnessHint: recentRef.freshnessHint
                )
            )
        }

        if expandedEvidence {
            let blockerRef = ref(for: "guidance_injection")
                ?? ref(for: "review_note")
                ?? ref(for: "workflow_plan")
                ?? ref(for: "workflow_job")
                ?? ref(for: "recent_context")
            if let blockerRef {
                items.append(
                    SupervisorEvidenceItem(
                        refId: blockerRef.refId,
                        title: blockerRef.title,
                        excerpt: focusedSupervisorLineageInlineDigest(servingContext.blockerLineageDigest),
                        whyIncluded: "active_blocker_lineage",
                        sourceScope: blockerRef.sourceScope,
                        freshnessHint: blockerRef.freshnessHint
                    )
                )
            }

            if let recentRef = ref(for: "recent_context"),
               servingContext.recentMessagesDigest != "(none)" {
                items.append(
                    SupervisorEvidenceItem(
                        refId: recentRef.refId,
                        title: recentRef.title,
                        excerpt: capped(servingContext.recentMessagesDigest, maxChars: 220),
                        whyIncluded: "live_recent_context",
                        sourceScope: recentRef.sourceScope,
                        freshnessHint: recentRef.freshnessHint
                    )
                )
            }
        }

        guard !items.isEmpty else {
            return SupervisorEvidencePackRenderResult(
                text: "(none)",
                selectedCount: 0,
                omittedCount: 0
            )
        }

        let selectedItems = Array(items.prefix(maxSelectedItems))
        let truncatedItems = max(0, items.count - selectedItems.count)
        let auditRef = servingContext.pendingAckGuidance?.auditRef
            ?? servingContext.latestGuidance?.auditRef
            ?? servingContext.latestReview?.auditRef
            ?? servingContext.governance.selectedEvidencePins.first?.auditRef
            ?? "audit-supervisor-evidence-\(servingContext.project.projectId)"

        return SupervisorEvidencePackRenderResult(
            text: """
evidence_goal: verify focused project anchors, latest review corrections, and live workflow before changing strategy for "\(capped(userMessage, maxChars: 72))"
selected_items:
\(selectedItems.map {
    "- ref_id=\($0.refId) title=\(capped($0.title, maxChars: 64)) source_scope=\($0.sourceScope) freshness=\($0.freshnessHint) why_included=\($0.whyIncluded) excerpt=\(capped($0.excerpt, maxChars: 220))"
}.joined(separator: "\n"))
truncated_items: \(truncatedItems)
redacted_items: 0
audit_ref: \(auditRef.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "audit-supervisor-evidence-\(servingContext.project.projectId)" : auditRef)
""",
            selectedCount: selectedItems.count,
            omittedCount: truncatedItems
        )
    }

    func supervisorAssemblyHasMeaningfulContent(
        _ text: String
    ) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return trimmed != "(none)" && trimmed != "(not_loaded)"
    }

    func injectedSupervisorCrossLinkRefsSection(
        into text: String,
        crossLinkRefs: String
    ) -> String {
        guard supervisorAssemblyHasMeaningfulContent(crossLinkRefs) else { return text }
        let section = """
[CROSS_LINK_REFS]
\(crossLinkRefs)
[/CROSS_LINK_REFS]
"""

        if let start = text.range(of: "[CROSS_LINK_REFS]"),
           let end = text.range(of: "[/CROSS_LINK_REFS]"),
           start.lowerBound <= end.lowerBound {
            return String(text[..<start.lowerBound]) + section + String(text[end.upperBound...])
        }
        if let range = text.range(of: "[/FOCUSED_PROJECT_ANCHOR_PACK]\n") {
            return String(text[..<range.upperBound]) + "\n" + section + "\n" + String(text[range.upperBound...])
        }
        if let range = text.range(of: "[/PORTFOLIO_BRIEF]\n") {
            return String(text[..<range.upperBound]) + "\n" + section + "\n" + String(text[range.upperBound...])
        }
        if let range = text.range(of: "[MEMORY_V1]\n") {
            return String(text[..<range.upperBound]) + section + "\n" + String(text[range.upperBound...])
        }
        return section + "\n" + text
    }

    func supervisorServingSectionIdentifier(
        for servingObject: String
    ) -> String? {
        switch servingObject {
        case "recent_raw_dialogue_window":
            return "dialogue_window"
        case "portfolio_brief",
             "focused_project_anchor_pack",
             "cross_link_refs",
             "longterm_outline",
             "delta_feed",
             "conflict_set",
             "context_refs",
             "evidence_pack":
            return servingObject
        case "selected_cross_link_hints":
            return "cross_link_refs"
        default:
            return nil
        }
    }

    func supervisorServingObjectContract(
        memoryPolicy: XTSupervisorMemoryPolicy,
        minimumPack: [String],
        crossLinkRefs: String
    ) -> [String] {
        var ordered: [String] = []
        var seen = Set<String>()

        func append(_ sectionId: String?) {
            guard let sectionId,
                  seen.insert(sectionId).inserted else { return }
            ordered.append(sectionId)
        }

        append("dialogue_window")

        for servingObject in memoryPolicy.resolution.selectedServingObjects {
            append(supervisorServingSectionIdentifier(for: servingObject))
        }

        switch memoryPolicy.assemblyPurpose {
        case .governanceReview, .portfolioReview:
            for sectionId in minimumPack {
                append(sectionId)
            }
        case .conversation, .projectAssist:
            break
        }

        if supervisorAssemblyHasMeaningfulContent(crossLinkRefs) {
            append("cross_link_refs")
        }

        return ordered
    }

    func supervisorActualSectionSelection(
        in text: String,
        contract: [String]
    ) -> (selected: [String], omitted: [String]) {
        let sectionTags: [(id: String, tag: String)] = [
            ("dialogue_window", "DIALOGUE_WINDOW"),
            ("portfolio_brief", "PORTFOLIO_BRIEF"),
            ("focused_project_anchor_pack", "FOCUSED_PROJECT_ANCHOR_PACK"),
            ("cross_link_refs", "CROSS_LINK_REFS"),
            ("longterm_outline", "LONGTERM_OUTLINE"),
            ("delta_feed", "DELTA_FEED"),
            ("conflict_set", "CONFLICT_SET"),
            ("context_refs", "CONTEXT_REFS"),
            ("evidence_pack", "EVIDENCE_PACK"),
        ]

        let selected = sectionTags.compactMap { section -> String? in
            guard let body = supervisorMemorySectionBody(in: text, tag: section.tag),
                  supervisorAssemblyHasMeaningfulContent(body) else {
                return nil
            }
            return section.id
        }
        let selectedSet = Set(selected)
        let omitted = contract.filter { !selectedSet.contains($0) }
        return (selected, omitted)
    }

    func renderSupervisorMemorySection(
        id: String,
        tag: String,
        body: String,
        allowedSections: Set<String>,
        omitWhenEmpty: Bool = false
    ) -> String {
        guard allowedSections.contains(id) else { return "" }
        if omitWhenEmpty && !supervisorAssemblyHasMeaningfulContent(body) {
            return ""
        }
        let content = supervisorAssemblyHasMeaningfulContent(body) ? body : "(none)"
        return """
[\(tag)]
\(content)
[/\(tag)]
"""
    }
}
