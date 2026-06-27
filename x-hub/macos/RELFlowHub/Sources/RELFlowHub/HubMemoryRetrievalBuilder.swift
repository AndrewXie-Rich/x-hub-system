import Foundation
import RELFlowHubCore

enum HubMemoryRetrievalBuilder {
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

}
