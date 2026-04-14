import Foundation
import RELFlowHubCore

enum HubMemoryRetrievalBuilder {
    private struct Candidate {
        var snippetId: String
        var sourceKind: String
        var title: String
        var ref: String
        var text: String
        var score: Int
        var truncated: Bool
    }

    private struct SanitizeResult {
        var text: String
        var redactedItems: Int
        var truncated: Bool
    }

    private enum RetrievalLayer: String {
        case l1Canonical = "l1_canonical"
        case l2Observations = "l2_observations"
    }

    private struct ProjectSpecCapsuleFile: Decodable {
        var goal: String
        var mvpDefinition: String
        var nonGoals: [String]
        var approvedTechStack: [String]
        var milestoneMap: [ProjectSpecMilestoneFile]

        enum CodingKeys: String, CodingKey {
            case goal
            case mvpDefinition = "mvp_definition"
            case nonGoals = "non_goals"
            case approvedTechStack = "approved_tech_stack"
            case milestoneMap = "milestone_map"
        }
    }

    private struct ProjectSpecMilestoneFile: Decodable {
        var title: String
        var status: String
    }

    private struct DecisionTrackSnapshotFile: Decodable {
        var events: [DecisionTrackEventFile]
    }

    private struct DecisionTrackEventFile: Decodable {
        var decisionId: String
        var category: String
        var status: String
        var statement: String
        var source: String
        var approvedBy: String
        var auditRef: String
        var updatedAtMs: Int64

        enum CodingKeys: String, CodingKey {
            case decisionId = "decision_id"
            case category
            case status
            case statement
            case source
            case approvedBy = "approved_by"
            case auditRef = "audit_ref"
            case updatedAtMs = "updated_at_ms"
        }
    }

    private struct BackgroundPreferenceSnapshotFile: Decodable {
        var notes: [BackgroundPreferenceNoteFile]
    }

    private struct BackgroundPreferenceNoteFile: Decodable {
        var noteId: String
        var domain: String
        var strength: String
        var statement: String
        var createdAtMs: Int64

        enum CodingKeys: String, CodingKey {
            case noteId = "note_id"
            case domain
            case strength
            case statement
            case createdAtMs = "created_at_ms"
        }
    }

    private struct RecentContextFile: Decodable {
        var messages: [RecentContextMessageFile]
    }

    private struct RecentContextMessageFile: Decodable {
        var role: String
        var content: String
        var createdAt: Double

        enum CodingKeys: String, CodingKey {
            case role
            case content
            case createdAt = "created_at"
        }
    }

    private struct AutomationCheckpointFile: Decodable {
        var runID: String
        var state: String
        var attempt: Int
        var retryAfterSeconds: Int
        var checkpointRef: String
        var stableIdentity: Bool
        var currentStepID: String?
        var currentStepTitle: String?
        var currentStepState: String?
        var currentStepSummary: String?
        var auditRef: String

        enum CodingKeys: String, CodingKey {
            case runID = "run_id"
            case state
            case attempt
            case retryAfterSeconds = "retry_after_seconds"
            case checkpointRef = "checkpoint_ref"
            case stableIdentity = "stable_identity"
            case currentStepID = "current_step_id"
            case currentStepTitle = "current_step_title"
            case currentStepState = "current_step_state"
            case currentStepSummary = "current_step_summary"
            case auditRef = "audit_ref"
        }
    }

    private struct AutomationVerificationReportFile: Decodable {
        var required: Bool
        var executed: Bool
        var commandCount: Int
        var passedCommandCount: Int
        var holdReason: String

        enum CodingKeys: String, CodingKey {
            case required
            case executed
            case commandCount = "command_count"
            case passedCommandCount = "passed_command_count"
            case holdReason = "hold_reason"
        }
    }

    private struct AutomationBlockerFile: Decodable {
        var code: String
        var summary: String
        var stage: String
        var currentStepID: String?
        var currentStepTitle: String?
        var currentStepState: String?
        var currentStepSummary: String?

        enum CodingKeys: String, CodingKey {
            case code
            case summary
            case stage
            case currentStepID = "current_step_id"
            case currentStepTitle = "current_step_title"
            case currentStepState = "current_step_state"
            case currentStepSummary = "current_step_summary"
        }
    }

    private struct AutomationRetryReasonDescriptorFile: Decodable {
        var code: String
        var summary: String
        var strategy: String
        var currentStepID: String?
        var currentStepTitle: String?
        var currentStepState: String?
        var currentStepSummary: String?

        enum CodingKeys: String, CodingKey {
            case code
            case summary
            case strategy
            case currentStepID = "current_step_id"
            case currentStepTitle = "current_step_title"
            case currentStepState = "current_step_state"
            case currentStepSummary = "current_step_summary"
        }
    }

    private struct AutomationRunHandoffFile: Decodable {
        var runID: String
        var recipeRef: String
        var deliveryRef: String?
        var finalState: String
        var holdReason: String
        var detail: String
        var verificationReport: AutomationVerificationReportFile?
        var structuredBlocker: AutomationBlockerFile?
        var suggestedNextActions: [String]
        var currentStepID: String?
        var currentStepTitle: String?
        var currentStepState: String?
        var currentStepSummary: String?

        enum CodingKeys: String, CodingKey {
            case runID = "run_id"
            case recipeRef = "recipe_ref"
            case deliveryRef = "delivery_ref"
            case finalState = "final_state"
            case holdReason = "hold_reason"
            case detail
            case verificationReport = "verification_report"
            case structuredBlocker = "structured_blocker"
            case suggestedNextActions = "suggested_next_actions"
            case currentStepID = "current_step_id"
            case currentStepTitle = "current_step_title"
            case currentStepState = "current_step_state"
            case currentStepSummary = "current_step_summary"
        }
    }

    private struct AutomationRetryPackageFile: Decodable {
        var deliveryRef: String?
        var sourceRunID: String
        var sourceFinalState: String
        var sourceHoldReason: String
        var sourceBlocker: AutomationBlockerFile?
        var retryStrategy: String
        var retryReason: String
        var retryReasonDescriptor: AutomationRetryReasonDescriptorFile?
        var planningMode: String?
        var planningSummary: String?
        var retryRunID: String

        enum CodingKeys: String, CodingKey {
            case deliveryRef = "delivery_ref"
            case sourceRunID = "source_run_id"
            case sourceFinalState = "source_final_state"
            case sourceHoldReason = "source_hold_reason"
            case sourceBlocker = "source_blocker"
            case retryStrategy = "retry_strategy"
            case retryReason = "retry_reason"
            case retryReasonDescriptor = "retry_reason_descriptor"
            case planningMode = "planning_mode"
            case planningSummary = "planning_summary"
            case retryRunID = "retry_run_id"
        }
    }

    private struct GuidanceInjectionSnapshotFile: Decodable {
        var items: [GuidanceInjectionRecordFile]
    }

    private struct GuidanceInjectionRecordFile: Decodable {
        var injectionId: String
        var reviewId: String
        var deliveryMode: String
        var interventionMode: String
        var safePointPolicy: String
        var guidanceText: String
        var ackStatus: String
        var ackRequired: Bool
        var effectiveSupervisorTier: String?
        var workOrderRef: String?
        var injectedAtMs: Int64
        var auditRef: String

        enum CodingKeys: String, CodingKey {
            case injectionId = "injection_id"
            case reviewId = "review_id"
            case deliveryMode = "delivery_mode"
            case interventionMode = "intervention_mode"
            case safePointPolicy = "safe_point_policy"
            case guidanceText = "guidance_text"
            case ackStatus = "ack_status"
            case ackRequired = "ack_required"
            case effectiveSupervisorTier = "effective_supervisor_tier"
            case workOrderRef = "work_order_ref"
            case injectedAtMs = "injected_at_ms"
            case auditRef = "audit_ref"
        }
    }

    private struct HeartbeatProjectionFile: Decodable {
        var createdAtMs: Int64
        var rawPayload: HeartbeatRawPayloadFile
        var canonicalProjection: HeartbeatCanonicalProjectionFile?

        enum CodingKeys: String, CodingKey {
            case createdAtMs = "created_at_ms"
            case rawPayload = "raw_payload"
            case canonicalProjection = "canonical_projection"
        }
    }

    private struct HeartbeatCanonicalProjectionFile: Decodable {
        var auditRef: String?

        enum CodingKeys: String, CodingKey {
            case auditRef = "audit_ref"
        }
    }

    private struct HeartbeatRawPayloadFile: Decodable {
        var statusDigest: String
        var currentStateSummary: String
        var nextStepSummary: String
        var blockerSummary: String
        var latestQualityBand: String?
        var latestQualityScore: Int?
        var executionStatus: String?
        var riskTier: String?
        var recoveryDecision: HeartbeatRecoveryDecisionFile?

        enum CodingKeys: String, CodingKey {
            case statusDigest = "status_digest"
            case currentStateSummary = "current_state_summary"
            case nextStepSummary = "next_step_summary"
            case blockerSummary = "blocker_summary"
            case latestQualityBand = "latest_quality_band"
            case latestQualityScore = "latest_quality_score"
            case executionStatus = "execution_status"
            case riskTier = "risk_tier"
            case recoveryDecision = "recovery_decision"
        }
    }

    private struct HeartbeatRecoveryDecisionFile: Decodable {
        var action: String
        var urgency: String
        var reasonCode: String
        var summary: String
        var queuedReviewTrigger: String?
        var queuedReviewLevel: String?
        var queuedReviewRunKind: String?

        enum CodingKeys: String, CodingKey {
            case action
            case urgency
            case reasonCode = "reason_code"
            case summary
            case queuedReviewTrigger = "queued_review_trigger"
            case queuedReviewLevel = "queued_review_level"
            case queuedReviewRunKind = "queued_review_run_kind"
        }
    }

    static func build(from req: IPCMemoryRetrievalRequestPayload) -> IPCMemoryRetrievalResponsePayload {
        let scope = normalized(req.scope).isEmpty ? "current_project" : normalized(req.scope)
        let auditRef = firstNonEmpty(req.auditRef, "audit-hub-memory-retrieval")
        let requestId = firstNonEmpty(req.requestId, "memreq-hub-memory-retrieval")
        guard scope == "current_project" else {
            return IPCMemoryRetrievalResponsePayload(
                schemaVersion: "xt.memory_retrieval_result.v1",
                requestId: requestId,
                status: "denied",
                resolvedScope: scope,
                source: "hub_memory_retrieval_v1",
                scope: scope,
                auditRef: auditRef,
                reasonCode: "unsupported_scope",
                denyCode: "cross_scope_memory_denied",
                results: [],
                snippets: [],
                truncated: false,
                budgetUsedChars: 0,
                truncatedItems: 0,
                redactedItems: 0
            )
        }

        let projectId = normalized(req.projectId)
        let projectRoot = normalized(req.projectRoot)
        let displayName = normalized(req.displayName)
        guard !projectId.isEmpty || !projectRoot.isEmpty || !displayName.isEmpty else {
            return IPCMemoryRetrievalResponsePayload(
                schemaVersion: "xt.memory_retrieval_result.v1",
                requestId: requestId,
                status: "denied",
                resolvedScope: scope,
                source: "hub_memory_retrieval_v1",
                scope: scope,
                auditRef: auditRef,
                reasonCode: "project_context_missing",
                denyCode: "cross_scope_memory_denied",
                results: [],
                snippets: [],
                truncated: false,
                budgetUsedChars: 0,
                truncatedItems: 0,
                redactedItems: 0
            )
        }

        let query = firstNonEmpty(req.query, normalized(req.latestUser))
        let queryTokens = retrievalTokens(query)
        let kinds = normalizedKinds(req.requestedKinds)
        let explicitRefs = orderedUnique(req.explicitRefs.map(normalized).filter { !$0.isEmpty })
        let retrievalKind = normalizedRetrievalKind(req.retrievalKind, explicitRefs: explicitRefs)
        let allowedLayers = normalizedAllowedLayers(req.allowedLayers)
        let maxSnippets = clamp(req.maxResults ?? req.maxSnippets, min: 1, max: 6)
        let maxSnippetChars = clamp(req.maxSnippetChars, min: 120, max: 1_200)

        var candidates: [Candidate] = []
        var redactedItems = 0
        var truncatedItems = 0

        if !explicitRefs.isEmpty {
            for ref in explicitRefs {
                let resolved = explicitRefCandidates(
                    ref: ref,
                    projectId: projectId,
                    projectRoot: projectRoot,
                    displayName: displayName,
                    query: query,
                    queryTokens: queryTokens,
                    maxSnippetChars: maxSnippetChars
                )
                redactedItems += resolved.redactedItems
                truncatedItems += resolved.truncatedItems
                candidates.append(contentsOf: resolved.candidates)
            }
        }

        if retrievalKind != "get_ref",
           shouldInclude(kind: "canonical_memory", requestedKinds: kinds) {
            let resolved = canonicalCandidates(
                projectId: projectId,
                projectRoot: projectRoot,
                displayName: displayName,
                query: query,
                queryTokens: queryTokens,
                maxSnippetChars: maxSnippetChars
            )
            redactedItems += resolved.redactedItems
            truncatedItems += resolved.truncatedItems
            candidates.append(contentsOf: resolved.candidates)
        }

        if retrievalKind != "get_ref",
           shouldInclude(kind: "project_spec_capsule", requestedKinds: kinds) {
            let resolved = projectSpecCandidates(
                projectRoot: projectRoot,
                query: query,
                queryTokens: queryTokens,
                maxSnippetChars: maxSnippetChars
            )
            redactedItems += resolved.redactedItems
            truncatedItems += resolved.truncatedItems
            candidates.append(contentsOf: resolved.candidates)
        }

        if retrievalKind != "get_ref",
           shouldInclude(kind: "decision_track", requestedKinds: kinds) {
            let resolved = decisionTrackCandidates(
                projectRoot: projectRoot,
                query: query,
                queryTokens: queryTokens,
                maxSnippetChars: maxSnippetChars
            )
            redactedItems += resolved.redactedItems
            truncatedItems += resolved.truncatedItems
            candidates.append(contentsOf: resolved.candidates)
        }

        if retrievalKind != "get_ref",
           shouldInclude(kind: "background_preferences", requestedKinds: kinds) {
            let resolved = backgroundPreferenceCandidates(
                projectRoot: projectRoot,
                query: query,
                queryTokens: queryTokens,
                maxSnippetChars: maxSnippetChars
            )
            redactedItems += resolved.redactedItems
            truncatedItems += resolved.truncatedItems
            candidates.append(contentsOf: resolved.candidates)
        }

        if retrievalKind != "get_ref",
           shouldInclude(kind: "recent_context", requestedKinds: kinds) {
            let resolved = recentContextCandidates(
                projectRoot: projectRoot,
                query: query,
                queryTokens: queryTokens,
                maxSnippetChars: maxSnippetChars
            )
            redactedItems += resolved.redactedItems
            truncatedItems += resolved.truncatedItems
            candidates.append(contentsOf: resolved.candidates)
        }

        if retrievalKind != "get_ref",
           shouldInclude(kind: "automation_checkpoint", requestedKinds: kinds) {
            let resolved = automationCheckpointCandidates(
                projectRoot: projectRoot,
                query: query,
                queryTokens: queryTokens,
                maxSnippetChars: maxSnippetChars
            )
            redactedItems += resolved.redactedItems
            truncatedItems += resolved.truncatedItems
            candidates.append(contentsOf: resolved.candidates)
        }

        if retrievalKind != "get_ref",
           shouldInclude(kind: "automation_execution_report", requestedKinds: kinds) {
            let resolved = automationExecutionReportCandidates(
                projectRoot: projectRoot,
                query: query,
                queryTokens: queryTokens,
                maxSnippetChars: maxSnippetChars
            )
            redactedItems += resolved.redactedItems
            truncatedItems += resolved.truncatedItems
            candidates.append(contentsOf: resolved.candidates)
        }

        if retrievalKind != "get_ref",
           shouldInclude(kind: "automation_retry_package", requestedKinds: kinds) {
            let resolved = automationRetryPackageCandidates(
                projectRoot: projectRoot,
                query: query,
                queryTokens: queryTokens,
                maxSnippetChars: maxSnippetChars
            )
            redactedItems += resolved.redactedItems
            truncatedItems += resolved.truncatedItems
            candidates.append(contentsOf: resolved.candidates)
        }

        if retrievalKind != "get_ref",
           shouldInclude(kind: "guidance_injection", requestedKinds: kinds) {
            let resolved = guidanceInjectionCandidates(
                projectRoot: projectRoot,
                query: query,
                queryTokens: queryTokens,
                maxSnippetChars: maxSnippetChars
            )
            redactedItems += resolved.redactedItems
            truncatedItems += resolved.truncatedItems
            candidates.append(contentsOf: resolved.candidates)
        }

        if retrievalKind != "get_ref",
           shouldInclude(kind: "heartbeat_projection", requestedKinds: kinds) {
            let resolved = heartbeatProjectionCandidates(
                projectRoot: projectRoot,
                query: query,
                queryTokens: queryTokens,
                maxSnippetChars: maxSnippetChars
            )
            redactedItems += resolved.redactedItems
            truncatedItems += resolved.truncatedItems
            candidates.append(contentsOf: resolved.candidates)
        }

        let ranked = deduped(
            candidates.filter { candidate in
                sourceKind(candidate.sourceKind, matchesAllowedLayers: allowedLayers)
            }
        )
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                return lhs.snippetId < rhs.snippetId
            }
        let selected = Array(ranked.prefix(maxSnippets))

        let reasonCode = selected.isEmpty ? "no_relevant_snippets" : nil
        let status = selected.isEmpty
            ? (truncatedItems > 0 ? "truncated" : "ok")
            : (truncatedItems > 0 ? "truncated" : "ok")
        let summary = selected.isEmpty ? "none" : selected.map(\.sourceKind).joined(separator: ",")
        HubDiagnostics.log(
            "memory_retrieval.build scope=\(scope) requester=\(normalized(req.requesterRole)) " +
            "mode=\(normalized(req.mode).isEmpty ? "project_chat" : normalized(req.mode)) retrieval_kind=\(retrievalKind) " +
            "snippets=\(selected.count) sources=\(summary) redacted=\(redactedItems) truncated=\(truncatedItems)"
        )

        return IPCMemoryRetrievalResponsePayload(
            schemaVersion: "xt.memory_retrieval_result.v1",
            requestId: requestId,
            status: status,
            resolvedScope: scope,
            source: "hub_memory_retrieval_v1",
            scope: scope,
            auditRef: auditRef,
            reasonCode: reasonCode,
            denyCode: nil,
            results: selected.map(resultItem(from:)),
            snippets: selected.map {
                IPCMemoryRetrievalSnippet(
                    snippetId: $0.snippetId,
                    sourceKind: $0.sourceKind,
                    title: $0.title,
                    ref: $0.ref,
                    text: $0.text,
                    score: $0.score,
                    truncated: $0.truncated
                )
            },
            truncated: truncatedItems > 0,
            budgetUsedChars: retrievalBudgetUsedChars(for: selected),
            truncatedItems: truncatedItems,
            redactedItems: redactedItems
        )
    }

    private static func shouldInclude(kind: String, requestedKinds: [String]) -> Bool {
        requestedKinds.isEmpty || requestedKinds.contains(kind)
    }

    private static func normalizedRetrievalKind(
        _ raw: String?,
        explicitRefs: [String]
    ) -> String {
        let kind = normalized(raw).lowercased()
        if !kind.isEmpty { return kind }
        return explicitRefs.isEmpty ? "search" : "get_ref"
    }

    private static func normalizedAllowedLayers(_ raw: [String]) -> Set<String> {
        Set(raw.map { normalized($0).lowercased() }.filter { !$0.isEmpty })
    }

    private static func sourceKindMaps(_ sourceKind: String, to layer: RetrievalLayer) -> Bool {
        switch layer {
        case .l1Canonical:
            return [
                "canonical_memory",
                "project_spec_capsule",
                "decision_track",
                "automation_checkpoint",
                "automation_execution_report",
                "guidance_injection"
            ].contains(sourceKind)
        case .l2Observations:
            return [
                "background_preferences",
                "recent_context",
                "automation_retry_package",
                "heartbeat_projection"
            ].contains(sourceKind)
        }
    }

    private static func sourceKind(
        _ kind: String,
        matchesAllowedLayers allowedLayers: Set<String>
    ) -> Bool {
        guard !allowedLayers.isEmpty else { return true }
        return allowedLayers.contains { rawLayer in
            guard let layer = RetrievalLayer(rawValue: rawLayer) else { return false }
            return sourceKindMaps(kind, to: layer)
        }
    }

    private static func resultItem(from candidate: Candidate) -> IPCMemoryRetrievalResultItem {
        IPCMemoryRetrievalResultItem(
            ref: candidate.ref,
            sourceKind: candidate.sourceKind,
            summary: candidate.title,
            snippet: candidate.text,
            score: min(1.0, max(0.0, Double(candidate.score) / 100.0)),
            redacted: false
        )
    }

    private static func retrievalBudgetUsedChars(for candidates: [Candidate]) -> Int {
        candidates.reduce(into: 0) { total, candidate in
            total += candidate.title.count
            total += candidate.ref.count
            total += candidate.text.count
        }
    }

    private static func canonicalCandidates(
        projectId: String,
        projectRoot: String,
        displayName: String,
        query: String,
        queryTokens: [String],
        maxSnippetChars: Int
    ) -> (candidates: [Candidate], redactedItems: Int, truncatedItems: Int) {
        guard let snapshot = HubProjectCanonicalMemoryStorage.lookup(
            projectId: projectId,
            projectRoot: projectRoot,
            displayName: displayName
        ) else {
            return ([], 0, 0)
        }

        let lines = snapshot.items
            .prefix(18)
            .map { item in "\(normalized(item.key)): \(normalized(item.value))" }
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !lines.isEmpty else { return ([], 0, 0) }

        let built = buildCandidate(
            sourceKind: "canonical_memory",
            title: "Canonical memory",
            ref: "hub://project/\(firstNonEmpty(snapshot.projectId, projectId))/canonical",
            rawText: lines.joined(separator: "\n"),
            query: query,
            queryTokens: queryTokens,
            maxSnippetChars: maxSnippetChars,
            baseScore: 24
        )
        guard let built else { return ([], 0, 0) }
        return ([built.candidate], built.redactedItems, built.truncated ? 1 : 0)
    }

    private static func projectSpecCandidates(
        projectRoot: String,
        query: String,
        queryTokens: [String],
        maxSnippetChars: Int
    ) -> (candidates: [Candidate], redactedItems: Int, truncatedItems: Int) {
        guard let file = decode(
            ProjectSpecCapsuleFile.self,
            from: projectStateDir(projectRoot).appendingPathComponent("supervisor_project_spec_capsule.json")
        ) else {
            return ([], 0, 0)
        }

        var blocks: [String] = []
        if !normalized(file.goal).isEmpty { blocks.append("goal: \(normalized(file.goal))") }
        if !normalized(file.mvpDefinition).isEmpty { blocks.append("mvp: \(normalized(file.mvpDefinition))") }
        if !file.approvedTechStack.isEmpty {
            blocks.append("approved_tech_stack: \(orderedUnique(file.approvedTechStack.map(normalized)).joined(separator: ", "))")
        }
        if !file.nonGoals.isEmpty {
            blocks.append("non_goals: \(orderedUnique(file.nonGoals.map(normalized)).joined(separator: ", "))")
        }
        if !file.milestoneMap.isEmpty {
            let milestoneSummary = file.milestoneMap
                .prefix(5)
                .map { milestone in
                    let title = normalized(milestone.title)
                    let status = normalized(milestone.status)
                    return status.isEmpty ? title : "\(title) [\(status)]"
                }
                .filter { !$0.isEmpty }
                .joined(separator: "; ")
            if !milestoneSummary.isEmpty {
                blocks.append("milestones: \(milestoneSummary)")
            }
        }
        guard !blocks.isEmpty else { return ([], 0, 0) }

        let built = buildCandidate(
            sourceKind: "project_spec_capsule",
            title: "Project spec capsule",
            ref: projectStateDir(projectRoot).appendingPathComponent("supervisor_project_spec_capsule.json").path,
            rawText: blocks.joined(separator: "\n"),
            query: query,
            queryTokens: queryTokens,
            maxSnippetChars: maxSnippetChars,
            baseScore: 30
        )
        guard let built else { return ([], 0, 0) }
        return ([built.candidate], built.redactedItems, built.truncated ? 1 : 0)
    }

    private static func decisionTrackCandidates(
        projectRoot: String,
        query: String,
        queryTokens: [String],
        maxSnippetChars: Int
    ) -> (candidates: [Candidate], redactedItems: Int, truncatedItems: Int) {
        guard let snapshot = decode(
            DecisionTrackSnapshotFile.self,
            from: projectStateDir(projectRoot).appendingPathComponent("supervisor_decision_track.json")
        ) else {
            return ([], 0, 0)
        }

        let approved = snapshot.events
            .filter { normalized($0.status) == "approved" && !normalized($0.statement).isEmpty }
            .sorted { lhs, rhs in lhs.updatedAtMs > rhs.updatedAtMs }
        let selected = approved.isEmpty ? snapshot.events.prefix(3) : approved.prefix(4)

        var candidates: [Candidate] = []
        var redactedItems = 0
        var truncatedItems = 0
        for event in selected {
            let rawText = """
category: \(normalized(event.category))
statement: \(normalized(event.statement))
source: \(normalized(event.source))
\(normalized(event.approvedBy).isEmpty ? "" : "approved_by: \(normalized(event.approvedBy))")
\(normalized(event.auditRef).isEmpty ? "" : "audit_ref: \(normalized(event.auditRef))")
"""
            guard let built = buildCandidate(
                sourceKind: "decision_track",
                title: "Decision \(normalized(event.category))",
                ref: projectStateDir(projectRoot).appendingPathComponent("supervisor_decision_track.json").path + "#decision:\(normalized(event.decisionId))",
                rawText: rawText,
                query: query,
                queryTokens: queryTokens,
                maxSnippetChars: maxSnippetChars,
                baseScore: 34
            ) else {
                continue
            }
            candidates.append(built.candidate)
            redactedItems += built.redactedItems
            if built.truncated { truncatedItems += 1 }
        }
        return (candidates, redactedItems, truncatedItems)
    }

    private static func backgroundPreferenceCandidates(
        projectRoot: String,
        query: String,
        queryTokens: [String],
        maxSnippetChars: Int
    ) -> (candidates: [Candidate], redactedItems: Int, truncatedItems: Int) {
        guard let snapshot = decode(
            BackgroundPreferenceSnapshotFile.self,
            from: projectStateDir(projectRoot).appendingPathComponent("supervisor_background_preference_track.json")
        ) else {
            return ([], 0, 0)
        }

        let notes = snapshot.notes.sorted { lhs, rhs in lhs.createdAtMs > rhs.createdAtMs }.prefix(4)
        var candidates: [Candidate] = []
        var redactedItems = 0
        var truncatedItems = 0
        for note in notes {
            let rawText = """
domain: \(normalized(note.domain))
strength: \(normalized(note.strength))
statement: \(normalized(note.statement))
"""
            guard let built = buildCandidate(
                sourceKind: "background_preferences",
                title: "Background \(normalized(note.domain))",
                ref: projectStateDir(projectRoot).appendingPathComponent("supervisor_background_preference_track.json").path + "#note:\(normalized(note.noteId))",
                rawText: rawText,
                query: query,
                queryTokens: queryTokens,
                maxSnippetChars: maxSnippetChars,
                baseScore: 20
            ) else {
                continue
            }
            candidates.append(built.candidate)
            redactedItems += built.redactedItems
            if built.truncated { truncatedItems += 1 }
        }
        return (candidates, redactedItems, truncatedItems)
    }

    private static func recentContextCandidates(
        projectRoot: String,
        query: String,
        queryTokens: [String],
        maxSnippetChars: Int
    ) -> (candidates: [Candidate], redactedItems: Int, truncatedItems: Int) {
        guard let recent = decode(
            RecentContextFile.self,
            from: projectStateDir(projectRoot).appendingPathComponent("recent_context.json")
        ) else {
            return ([], 0, 0)
        }

        let messages = recent.messages
        let historical = messages.count > 16 ? Array(messages.dropLast(16)) : messages
        let selected = historical.isEmpty ? Array(messages.prefix(8)) : Array(historical.suffix(12))

        var candidates: [Candidate] = []
        var redactedItems = 0
        var truncatedItems = 0
        for (index, message) in selected.enumerated() {
            let rawText = "\(normalized(message.role)): \(normalized(message.content))"
            guard let built = buildCandidate(
                sourceKind: "recent_context",
                title: "Recent context \(normalized(message.role))",
                ref: projectStateDir(projectRoot).appendingPathComponent("recent_context.json").path + "#message:\(index)",
                rawText: rawText,
                query: query,
                queryTokens: queryTokens,
                maxSnippetChars: maxSnippetChars,
                baseScore: 28
            ) else {
                continue
            }
            candidates.append(built.candidate)
            redactedItems += built.redactedItems
            if built.truncated { truncatedItems += 1 }
        }
        return (candidates, redactedItems, truncatedItems)
    }

    private static func automationCheckpointCandidates(
        projectRoot: String,
        query: String,
        queryTokens: [String],
        maxSnippetChars: Int,
        specificURL: URL? = nil
    ) -> (candidates: [Candidate], redactedItems: Int, truncatedItems: Int) {
        let urls = artifactSelection(
            in: projectReportsDir(projectRoot),
            prefix: "xt_w3_25_run_checkpoint_",
            suffix: ".v1.json",
            specificURL: specificURL,
            maxCount: 2
        )
        var candidates: [Candidate] = []
        var redactedItems = 0
        var truncatedItems = 0
        for url in urls {
            guard let file = decode(AutomationCheckpointFile.self, from: url) else { continue }
            var lines = [
                "run_id: \(normalized(file.runID))",
                "state: \(normalized(file.state))",
                "attempt: \(file.attempt)",
                "retry_after_seconds: \(file.retryAfterSeconds)",
                "stable_identity: \(file.stableIdentity)",
                "checkpoint_ref: \(normalized(file.checkpointRef))",
            ]
            if let currentStepID = normalizedOptional(file.currentStepID) {
                lines.append("current_step_id: \(currentStepID)")
            }
            if let currentStepTitle = normalizedOptional(file.currentStepTitle) {
                lines.append("current_step_title: \(currentStepTitle)")
            }
            if let currentStepState = normalizedOptional(file.currentStepState) {
                lines.append("current_step_state: \(currentStepState)")
            }
            if let currentStepSummary = normalizedOptional(file.currentStepSummary) {
                lines.append("current_step_summary: \(currentStepSummary)")
            }
            if !normalized(file.auditRef).isEmpty {
                lines.append("audit_ref: \(normalized(file.auditRef))")
            }
            guard let built = buildCandidate(
                sourceKind: "automation_checkpoint",
                title: "Automation checkpoint \(normalized(file.state))",
                ref: url.path + "#run:\(normalized(file.runID))",
                rawText: lines.joined(separator: "\n"),
                query: query,
                queryTokens: queryTokens,
                maxSnippetChars: maxSnippetChars,
                baseScore: 38
            ) else {
                continue
            }
            candidates.append(built.candidate)
            redactedItems += built.redactedItems
            if built.truncated { truncatedItems += 1 }
        }
        return (candidates, redactedItems, truncatedItems)
    }

    private static func automationExecutionReportCandidates(
        projectRoot: String,
        query: String,
        queryTokens: [String],
        maxSnippetChars: Int,
        specificURL: URL? = nil
    ) -> (candidates: [Candidate], redactedItems: Int, truncatedItems: Int) {
        let urls = artifactSelection(
            in: projectReportsDir(projectRoot),
            prefix: "xt_automation_run_handoff_",
            suffix: ".v1.json",
            specificURL: specificURL,
            maxCount: 2
        )
        var candidates: [Candidate] = []
        var redactedItems = 0
        var truncatedItems = 0
        for url in urls {
            guard let file = decode(AutomationRunHandoffFile.self, from: url) else { continue }
            var lines = [
                "run_id: \(normalized(file.runID))",
                "final_state: \(normalized(file.finalState))",
                "hold_reason: \(normalized(file.holdReason))",
                "recipe_ref: \(normalized(file.recipeRef))",
            ]
            if let deliveryRef = normalizedOptional(file.deliveryRef) {
                lines.append("delivery_ref: \(deliveryRef)")
            }
            if let currentStepID = normalizedOptional(file.currentStepID) {
                lines.append("current_step_id: \(currentStepID)")
            }
            if let currentStepTitle = normalizedOptional(file.currentStepTitle) {
                lines.append("current_step_title: \(currentStepTitle)")
            }
            if let currentStepState = normalizedOptional(file.currentStepState) {
                lines.append("current_step_state: \(currentStepState)")
            }
            if let currentStepSummary = normalizedOptional(file.currentStepSummary) {
                lines.append("current_step_summary: \(currentStepSummary)")
            }
            if let verification = file.verificationReport {
                lines.append("verification_required: \(verification.required)")
                lines.append("verification_executed: \(verification.executed)")
                lines.append("verification_command_count: \(verification.commandCount)")
                lines.append("verification_passed_command_count: \(verification.passedCommandCount)")
                if !normalized(verification.holdReason).isEmpty {
                    lines.append("verification_hold_reason: \(normalized(verification.holdReason))")
                }
            }
            if let blocker = file.structuredBlocker {
                lines.append("blocker_code: \(normalized(blocker.code))")
                lines.append("blocker_summary: \(normalized(blocker.summary))")
                lines.append("blocker_stage: \(normalized(blocker.stage))")
            }
            if !normalized(file.detail).isEmpty {
                lines.append("detail: \(normalized(file.detail))")
            }
            if !file.suggestedNextActions.isEmpty {
                lines.append(
                    "suggested_next_actions: \(orderedUnique(file.suggestedNextActions.map(normalized)).joined(separator: ", "))"
                )
            }
            guard let built = buildCandidate(
                sourceKind: "automation_execution_report",
                title: "Automation execution \(normalized(file.finalState))",
                ref: url.path + "#run:\(normalized(file.runID))",
                rawText: lines.joined(separator: "\n"),
                query: query,
                queryTokens: queryTokens,
                maxSnippetChars: maxSnippetChars,
                baseScore: 42
            ) else {
                continue
            }
            candidates.append(built.candidate)
            redactedItems += built.redactedItems
            if built.truncated { truncatedItems += 1 }
        }
        return (candidates, redactedItems, truncatedItems)
    }

    private static func automationRetryPackageCandidates(
        projectRoot: String,
        query: String,
        queryTokens: [String],
        maxSnippetChars: Int,
        specificURL: URL? = nil
    ) -> (candidates: [Candidate], redactedItems: Int, truncatedItems: Int) {
        let urls = artifactSelection(
            in: projectReportsDir(projectRoot),
            prefix: "xt_automation_retry_package_",
            suffix: ".v1.json",
            specificURL: specificURL,
            maxCount: 2
        )
        var candidates: [Candidate] = []
        var redactedItems = 0
        var truncatedItems = 0
        for url in urls {
            guard let file = decode(AutomationRetryPackageFile.self, from: url) else { continue }
            var lines = [
                "source_run_id: \(normalized(file.sourceRunID))",
                "source_final_state: \(normalized(file.sourceFinalState))",
                "source_hold_reason: \(normalized(file.sourceHoldReason))",
                "retry_run_id: \(normalized(file.retryRunID))",
                "retry_strategy: \(normalized(file.retryStrategy))",
                "retry_reason: \(normalized(file.retryReason))",
            ]
            if let deliveryRef = normalizedOptional(file.deliveryRef) {
                lines.append("delivery_ref: \(deliveryRef)")
            }
            if let planningMode = normalizedOptional(file.planningMode) {
                lines.append("planning_mode: \(planningMode)")
            }
            if let planningSummary = normalizedOptional(file.planningSummary) {
                lines.append("planning_summary: \(planningSummary)")
            }
            if let blocker = file.sourceBlocker {
                lines.append("source_blocker_code: \(normalized(blocker.code))")
                lines.append("source_blocker_summary: \(normalized(blocker.summary))")
                lines.append("source_blocker_stage: \(normalized(blocker.stage))")
            }
            if let retryReason = file.retryReasonDescriptor {
                lines.append("retry_reason_code: \(normalized(retryReason.code))")
                lines.append("retry_reason_summary: \(normalized(retryReason.summary))")
                lines.append("retry_reason_strategy: \(normalized(retryReason.strategy))")
                if let currentStepID = normalizedOptional(retryReason.currentStepID) {
                    lines.append("current_step_id: \(currentStepID)")
                }
                if let currentStepTitle = normalizedOptional(retryReason.currentStepTitle) {
                    lines.append("current_step_title: \(currentStepTitle)")
                }
                if let currentStepState = normalizedOptional(retryReason.currentStepState) {
                    lines.append("current_step_state: \(currentStepState)")
                }
                if let currentStepSummary = normalizedOptional(retryReason.currentStepSummary) {
                    lines.append("current_step_summary: \(currentStepSummary)")
                }
            }
            guard let built = buildCandidate(
                sourceKind: "automation_retry_package",
                title: "Automation retry \(normalized(file.retryStrategy))",
                ref: url.path + "#retry_run:\(normalized(file.retryRunID))",
                rawText: lines.joined(separator: "\n"),
                query: query,
                queryTokens: queryTokens,
                maxSnippetChars: maxSnippetChars,
                baseScore: 36
            ) else {
                continue
            }
            candidates.append(built.candidate)
            redactedItems += built.redactedItems
            if built.truncated { truncatedItems += 1 }
        }
        return (candidates, redactedItems, truncatedItems)
    }

    private static func guidanceInjectionCandidates(
        projectRoot: String,
        query: String,
        queryTokens: [String],
        maxSnippetChars: Int,
        specificURL: URL? = nil
    ) -> (candidates: [Candidate], redactedItems: Int, truncatedItems: Int) {
        let url = specificURL
            ?? projectStateDir(projectRoot).appendingPathComponent("supervisor_guidance_injections.json")
        guard let snapshot = decode(GuidanceInjectionSnapshotFile.self, from: url) else {
            return ([], 0, 0)
        }

        let selected = snapshot.items
            .sorted { lhs, rhs in lhs.injectedAtMs > rhs.injectedAtMs }
            .prefix(3)
        var candidates: [Candidate] = []
        var redactedItems = 0
        var truncatedItems = 0
        for item in selected {
            var lines = [
                "review_id: \(normalized(item.reviewId))",
                "ack_status: \(normalized(item.ackStatus))",
                "ack_required: \(item.ackRequired)",
                "delivery_mode: \(normalized(item.deliveryMode))",
                "intervention_mode: \(normalized(item.interventionMode))",
                "safe_point_policy: \(normalized(item.safePointPolicy))",
                "injected_at_ms: \(item.injectedAtMs)",
            ]
            if let effectiveTier = normalizedOptional(item.effectiveSupervisorTier) {
                lines.append("effective_supervisor_tier: \(effectiveTier)")
            }
            if let workOrderRef = normalizedOptional(item.workOrderRef) {
                lines.append("work_order_ref: \(workOrderRef)")
            }
            if !normalized(item.auditRef).isEmpty {
                lines.append("audit_ref: \(normalized(item.auditRef))")
            }
            lines.append("guidance_summary: \(capped(normalized(item.guidanceText), maxChars: 220))")
            guard let built = buildCandidate(
                sourceKind: "guidance_injection",
                title: "Guidance \(normalized(item.ackStatus))",
                ref: url.path + "#guidance:\(normalized(item.injectionId))",
                rawText: lines.joined(separator: "\n"),
                query: query,
                queryTokens: queryTokens,
                maxSnippetChars: maxSnippetChars,
                baseScore: 40
            ) else {
                continue
            }
            candidates.append(built.candidate)
            redactedItems += built.redactedItems
            if built.truncated { truncatedItems += 1 }
        }
        return (candidates, redactedItems, truncatedItems)
    }

    private static func heartbeatProjectionCandidates(
        projectRoot: String,
        query: String,
        queryTokens: [String],
        maxSnippetChars: Int,
        specificURL: URL? = nil
    ) -> (candidates: [Candidate], redactedItems: Int, truncatedItems: Int) {
        let url = specificURL
            ?? projectStateDir(projectRoot).appendingPathComponent("heartbeat_memory_projection.json")
        guard let projection = decode(HeartbeatProjectionFile.self, from: url) else {
            return ([], 0, 0)
        }

        var lines = [
            "status_digest: \(normalized(projection.rawPayload.statusDigest))",
            "current_state_summary: \(normalized(projection.rawPayload.currentStateSummary))",
            "next_step_summary: \(normalized(projection.rawPayload.nextStepSummary))",
            "blocker_summary: \(normalized(projection.rawPayload.blockerSummary))",
            "created_at_ms: \(projection.createdAtMs)",
        ]
        if let latestQualityBand = normalizedOptional(projection.rawPayload.latestQualityBand) {
            lines.append("latest_quality_band: \(latestQualityBand)")
        }
        if let latestQualityScore = projection.rawPayload.latestQualityScore {
            lines.append("latest_quality_score: \(latestQualityScore)")
        }
        if let executionStatus = normalizedOptional(projection.rawPayload.executionStatus) {
            lines.append("execution_status: \(executionStatus)")
        }
        if let riskTier = normalizedOptional(projection.rawPayload.riskTier) {
            lines.append("risk_tier: \(riskTier)")
        }
        if let recoveryDecision = projection.rawPayload.recoveryDecision {
            lines.append("recovery_action: \(normalized(recoveryDecision.action))")
            lines.append("recovery_urgency: \(normalized(recoveryDecision.urgency))")
            lines.append("recovery_reason_code: \(normalized(recoveryDecision.reasonCode))")
            lines.append("recovery_summary: \(normalized(recoveryDecision.summary))")
            if let queuedReviewTrigger = normalizedOptional(recoveryDecision.queuedReviewTrigger) {
                lines.append("queued_review_trigger: \(queuedReviewTrigger)")
            }
            if let queuedReviewLevel = normalizedOptional(recoveryDecision.queuedReviewLevel) {
                lines.append("queued_review_level: \(queuedReviewLevel)")
            }
            if let queuedReviewRunKind = normalizedOptional(recoveryDecision.queuedReviewRunKind) {
                lines.append("queued_review_run_kind: \(queuedReviewRunKind)")
            }
        }
        if let canonicalAuditRef = normalizedOptional(projection.canonicalProjection?.auditRef) {
            lines.append("canonical_audit_ref: \(canonicalAuditRef)")
        }
        guard let built = buildCandidate(
            sourceKind: "heartbeat_projection",
            title: "Heartbeat projection \(normalized(projection.rawPayload.executionStatus))",
            ref: url.path + "#heartbeat:\(projection.createdAtMs)",
            rawText: lines.joined(separator: "\n"),
            query: query,
            queryTokens: queryTokens,
            maxSnippetChars: maxSnippetChars,
            baseScore: 34
        ) else {
            return ([], 0, 0)
        }
        return ([built.candidate], built.redactedItems, built.truncated ? 1 : 0)
    }

    private static func explicitRefCandidates(
        ref: String,
        projectId: String,
        projectRoot: String,
        displayName: String,
        query: String,
        queryTokens: [String],
        maxSnippetChars: Int
    ) -> (candidates: [Candidate], redactedItems: Int, truncatedItems: Int) {
        if ref.hasPrefix("hub://project/"), ref.contains("/canonical") {
            let resolved = canonicalCandidates(
                projectId: projectId,
                projectRoot: projectRoot,
                displayName: displayName,
                query: query,
                queryTokens: queryTokens,
                maxSnippetChars: maxSnippetChars
            )
            return boostExplicitCandidates(resolved)
        }

        let resolvedRef = refBasePath(ref)
        let url = URL(fileURLWithPath: resolvedRef)
        let lastPathComponent = url.lastPathComponent
        switch lastPathComponent {
        case "supervisor_project_spec_capsule.json":
            return boostExplicitCandidates(
                projectSpecCandidates(
                    projectRoot: projectRoot,
                    query: query,
                    queryTokens: queryTokens,
                    maxSnippetChars: maxSnippetChars
                )
            )
        case "supervisor_decision_track.json":
            return boostExplicitCandidates(
                decisionTrackCandidates(
                    projectRoot: projectRoot,
                    query: query,
                    queryTokens: queryTokens,
                    maxSnippetChars: maxSnippetChars
                )
            )
        case "supervisor_background_preference_track.json":
            return boostExplicitCandidates(
                backgroundPreferenceCandidates(
                    projectRoot: projectRoot,
                    query: query,
                    queryTokens: queryTokens,
                    maxSnippetChars: maxSnippetChars
                )
            )
        case "recent_context.json":
            return boostExplicitCandidates(
                recentContextCandidates(
                    projectRoot: projectRoot,
                    query: query,
                    queryTokens: queryTokens,
                    maxSnippetChars: maxSnippetChars
                )
            )
        case "supervisor_guidance_injections.json":
            return boostExplicitCandidates(
                guidanceInjectionCandidates(
                    projectRoot: projectRoot,
                    query: query,
                    queryTokens: queryTokens,
                    maxSnippetChars: maxSnippetChars,
                    specificURL: url
                )
            )
        case "heartbeat_memory_projection.json":
            return boostExplicitCandidates(
                heartbeatProjectionCandidates(
                    projectRoot: projectRoot,
                    query: query,
                    queryTokens: queryTokens,
                    maxSnippetChars: maxSnippetChars,
                    specificURL: url
                )
            )
        default:
            if lastPathComponent.hasPrefix("xt_w3_25_run_checkpoint_"),
               lastPathComponent.hasSuffix(".v1.json") {
                return boostExplicitCandidates(
                    automationCheckpointCandidates(
                        projectRoot: projectRoot,
                        query: query,
                        queryTokens: queryTokens,
                        maxSnippetChars: maxSnippetChars,
                        specificURL: url
                    )
                )
            }
            if lastPathComponent.hasPrefix("xt_automation_run_handoff_"),
               lastPathComponent.hasSuffix(".v1.json") {
                return boostExplicitCandidates(
                    automationExecutionReportCandidates(
                        projectRoot: projectRoot,
                        query: query,
                        queryTokens: queryTokens,
                        maxSnippetChars: maxSnippetChars,
                        specificURL: url
                    )
                )
            }
            if lastPathComponent.hasPrefix("xt_automation_retry_package_"),
               lastPathComponent.hasSuffix(".v1.json") {
                return boostExplicitCandidates(
                    automationRetryPackageCandidates(
                        projectRoot: projectRoot,
                        query: query,
                        queryTokens: queryTokens,
                        maxSnippetChars: maxSnippetChars,
                        specificURL: url
                    )
                )
            }
            return ([], 0, 0)
        }
    }

    private static func boostExplicitCandidates(
        _ raw: (candidates: [Candidate], redactedItems: Int, truncatedItems: Int)
    ) -> (candidates: [Candidate], redactedItems: Int, truncatedItems: Int) {
        let boosted = raw.candidates.map { candidate in
            var updated = candidate
            updated.score += 500
            return updated
        }
        return (boosted, raw.redactedItems, raw.truncatedItems)
    }

    private static func buildCandidate(
        sourceKind: String,
        title: String,
        ref: String,
        rawText: String,
        query: String,
        queryTokens: [String],
        maxSnippetChars: Int,
        baseScore: Int
    ) -> (candidate: Candidate, redactedItems: Int, truncated: Bool)? {
        let sanitized = sanitize(rawText, maxChars: maxSnippetChars)
        let text = sanitized.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        let score = baseScore + queryMatchScore(
            query: query,
            tokens: queryTokens,
            title: title,
            text: text,
            sourceKind: sourceKind
        )
        let candidate = Candidate(
            snippetId: stableSnippetID(sourceKind: sourceKind, ref: ref, text: text),
            sourceKind: sourceKind,
            title: title,
            ref: ref,
            text: text,
            score: score,
            truncated: sanitized.truncated
        )
        return (candidate, sanitized.redactedItems, sanitized.truncated)
    }

    private static func sanitize(_ raw: String, maxChars: Int) -> SanitizeResult {
        var text = normalized(raw)
        var redactedItems = 0

        let replacements: [(String, String)] = [
            ("(?is)<private>.*?</private>", "[private omitted]"),
            ("(?is)-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----.*?-----END [A-Z0-9 ]*PRIVATE KEY-----", "[redacted_private_key]"),
            ("sk-[A-Za-z0-9]{20,}", "[redacted_api_key]"),
            ("sk-ant-[A-Za-z0-9_-]{20,}", "[redacted_api_key]"),
            ("gh[pousr]_[A-Za-z0-9]{20,}", "[redacted_token]"),
            ("(?i)bearer\\s+[A-Za-z0-9._-]{16,}", "Bearer [redacted_token]"),
            ("eyJ[A-Za-z0-9_-]{6,}\\.[A-Za-z0-9_-]{6,}\\.[A-Za-z0-9_-]{6,}", "[redacted_jwt]")
        ]
        for (pattern, replacement) in replacements {
            let result = regexReplace(text, pattern: pattern, template: replacement)
            text = result.text
            redactedItems += result.count
        }

        text = text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

        var truncated = false
        if text.count > maxChars {
            let idx = text.index(text.startIndex, offsetBy: maxChars)
            text = String(text[..<idx]).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
            truncated = true
        }

        return SanitizeResult(text: text, redactedItems: redactedItems, truncated: truncated)
    }

    private static func regexReplace(
        _ input: String,
        pattern: String,
        template: String
    ) -> (text: String, count: Int) {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return (input, 0)
        }
        let range = NSRange(input.startIndex..., in: input)
        let count = regex.numberOfMatches(in: input, range: range)
        guard count > 0 else { return (input, 0) }
        let replaced = regex.stringByReplacingMatches(in: input, range: range, withTemplate: template)
        return (replaced, count)
    }

    private static func queryMatchScore(
        query: String,
        tokens: [String],
        title: String,
        text: String,
        sourceKind: String
    ) -> Int {
        let haystack = "\(title)\n\(text)".lowercased()
        var score = 0
        for token in tokens {
            if haystack.contains(token) { score += 12 }
        }

        if containsAny(query, needles: HubUIStrings.Memory.Retrieval.recentContextNeedles) &&
            sourceKind == "recent_context" {
            score += 60
        }
        if containsAny(query, needles: HubUIStrings.Memory.Retrieval.decisionNeedles) &&
            (sourceKind == "decision_track" || sourceKind == "project_spec_capsule") {
            score += 55
        }
        if containsAny(query, needles: HubUIStrings.Memory.Retrieval.preferenceNeedles) &&
            sourceKind == "background_preferences" {
            score += 45
        }
        if containsAny(query, needles: HubUIStrings.Memory.Retrieval.runtimeNeedles) &&
            ["automation_checkpoint", "automation_execution_report", "automation_retry_package"].contains(sourceKind) {
            score += 58
        }
        if containsAny(query, needles: HubUIStrings.Memory.Retrieval.guidanceNeedles) &&
            sourceKind == "guidance_injection" {
            score += 56
        }
        if containsAny(query, needles: HubUIStrings.Memory.Retrieval.heartbeatNeedles) &&
            sourceKind == "heartbeat_projection" {
            score += 52
        }

        return score
    }

    private static func retrievalTokens(_ raw: String) -> [String] {
        let lower = raw.lowercased()
        let parts = lower.components(separatedBy: CharacterSet.alphanumerics.inverted)
        var out = parts.filter { $0.count >= 3 }
        for needle in HubUIStrings.Memory.Retrieval.tokenBoostNeedles where raw.contains(needle) {
            out.append(needle)
        }
        return orderedUnique(out)
    }

    private static func normalizedKinds(_ raw: [String]) -> [String] {
        orderedUnique(raw.map { normalized($0).lowercased() })
    }

    private static func deduped(_ raw: [Candidate]) -> [Candidate] {
        var seen = Set<String>()
        return raw.filter { candidate in
            let key = "\(candidate.sourceKind)|\(candidate.ref)|\(candidate.text)"
            guard seen.insert(key).inserted else { return false }
            return true
        }
    }

    private static func stableSnippetID(sourceKind: String, ref: String, text: String) -> String {
        let seed = "\(sourceKind)|\(ref)|\(text)"
        let hex = Array(seed.utf8).prefix(12).map { String(format: "%02x", $0) }.joined()
        return "retrieval-\(hex)"
    }

    private static func projectReportsDir(_ projectRoot: String) -> URL {
        URL(fileURLWithPath: projectRoot, isDirectory: true)
            .appendingPathComponent("build", isDirectory: true)
            .appendingPathComponent("reports", isDirectory: true)
    }

    private static func artifactSelection(
        in directory: URL,
        prefix: String,
        suffix: String,
        specificURL: URL?,
        maxCount: Int
    ) -> [URL] {
        if let specificURL {
            return FileManager.default.fileExists(atPath: specificURL.path) ? [specificURL] : []
        }
        return latestArtifactFiles(
            in: directory,
            prefix: prefix,
            suffix: suffix,
            maxCount: maxCount
        )
    }

    private static func latestArtifactFiles(
        in directory: URL,
        prefix: String,
        suffix: String,
        maxCount: Int
    ) -> [URL] {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return urls
            .filter { url in
                let name = url.lastPathComponent
                return name.hasPrefix(prefix) && name.hasSuffix(suffix)
            }
            .sorted { lhs, rhs in
                let lhsDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let rhsDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                if lhsDate != rhsDate {
                    return lhsDate > rhsDate
                }
                return lhs.lastPathComponent > rhs.lastPathComponent
            }
            .prefix(maxCount)
            .map { $0 }
    }

    private static func projectStateDir(_ projectRoot: String) -> URL {
        URL(fileURLWithPath: projectRoot, isDirectory: true)
            .appendingPathComponent(".xterminal", isDirectory: true)
    }

    private static func decode<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func orderedUnique(_ raw: [String]) -> [String] {
        var seen = Set<String>()
        return raw.compactMap { item in
            let token = item.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !token.isEmpty else { return nil }
            guard seen.insert(token).inserted else { return nil }
            return token
        }
    }

    private static func containsAny(_ query: String, needles: [String]) -> Bool {
        let lower = query.lowercased()
        return needles.contains { lower.contains($0.lowercased()) }
    }

    private static func refBasePath(_ ref: String) -> String {
        let trimmed = normalized(ref)
        guard let hashIndex = trimmed.firstIndex(of: "#") else { return trimmed }
        return String(trimmed[..<hashIndex])
    }

    private static func normalizedOptional(_ raw: String?) -> String? {
        let trimmed = normalized(raw)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func capped(_ raw: String, maxChars: Int) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxChars else { return trimmed }
        let index = trimmed.index(trimmed.startIndex, offsetBy: maxChars)
        return String(trimmed[..<index]).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }

    private static func normalized(_ raw: String?) -> String {
        (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func firstNonEmpty(_ raw: String?, _ fallback: String) -> String {
        let token = normalized(raw)
        return token.isEmpty ? fallback : token
    }

    private static func clamp(_ value: Int, min lower: Int, max upper: Int) -> Int {
        Swift.max(lower, Swift.min(upper, value))
    }
}
