import Foundation

extension HubIPCClient {
    private static func normalizedMemoryRetrievalKind(
        explicitRefs: [String],
        requestedKinds: [String]
    ) -> String {
        if !explicitRefs.isEmpty {
            return "get_ref"
        }
        if requestedKinds.contains(where: { $0.lowercased().contains("drilldown") }) {
            return "drilldown"
        }
        return "search"
    }

    private static func allowedLayersForMemoryRetrieval(
        requestedKinds: [String],
        explicitRefs: [String]
    ) -> [String] {
        var layers = Set<String>()
        let normalizedKinds = requestedKinds.map { $0.lowercased() }

        if !explicitRefs.isEmpty {
            layers.insert(XTMemoryLayer.l1Canonical.rawValue)
            layers.insert(XTMemoryLayer.l2Observations.rawValue)
        }

        for kind in normalizedKinds {
            if kind.contains("spec")
                || kind.contains("decision")
                || kind.contains("canonical")
                || kind.contains("blocker")
                || kind.contains("checkpoint")
                || kind.contains("execution")
                || kind.contains("guidance")
                || kind.contains("plan")
                || kind.contains("skill") {
                layers.insert(XTMemoryLayer.l1Canonical.rawValue)
            }
            if kind.contains("background")
                || kind.contains("context")
                || kind.contains("recent")
                || kind.contains("observation")
                || kind.contains("retry")
                || kind.contains("heartbeat")
                || kind.contains("outline") {
                layers.insert(XTMemoryLayer.l2Observations.rawValue)
            }
            if kind.contains("automation") {
                layers.insert(XTMemoryLayer.l1Canonical.rawValue)
                layers.insert(XTMemoryLayer.l2Observations.rawValue)
            }
        }

        if layers.isEmpty {
            layers = [
                XTMemoryLayer.l1Canonical.rawValue,
                XTMemoryLayer.l2Observations.rawValue
            ]
        }

        return Array(layers).sorted()
    }

    private static func normalizedMemoryRetrievalStatus(
        _ response: MemoryRetrievalResponsePayload
    ) -> String {
        let denyCode = response.denyCode?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !denyCode.isEmpty {
            return "denied"
        }
        if response.truncatedItems > 0 {
            return "truncated"
        }
        return "ok"
    }

    private static func normalizedMemoryRetrievalResults(
        snippets: [MemoryRetrievalSnippet]
    ) -> [MemoryRetrievalResultItem] {
        snippets.map { snippet in
            MemoryRetrievalResultItem(
                ref: snippet.ref,
                sourceKind: snippet.sourceKind,
                summary: snippet.title,
                snippet: snippet.text,
                score: min(1.0, max(0.0, Double(snippet.score) / 100.0)),
                redacted: false
            )
        }
    }

    private static func synthesizedMemoryRetrievalSnippets(
        results: [MemoryRetrievalResultItem]
    ) -> [MemoryRetrievalSnippet] {
        results.enumerated().map { index, result in
            MemoryRetrievalSnippet(
                snippetId: "remote-snippet-\(index + 1)",
                sourceKind: result.sourceKind,
                title: result.summary,
                ref: result.ref,
                text: result.snippet,
                score: Int((min(1.0, max(0.0, result.score)) * 100.0).rounded()),
                truncated: false
            )
        }
    }

    private static func estimatedMemoryRetrievalBudgetUsedChars(
        snippets: [MemoryRetrievalSnippet]
    ) -> Int {
        snippets.reduce(into: 0) { total, snippet in
            total += snippet.title.count
            total += snippet.text.count
            total += snippet.ref.count
        }
    }

    private static func normalizedMemoryRetrievalResponse(
        _ response: MemoryRetrievalResponsePayload?,
        request: MemoryRetrievalPayload
    ) -> MemoryRetrievalResponsePayload? {
        guard var response else { return nil }
        response.schemaVersion = response.schemaVersion ?? "xt.memory_retrieval_result.v1"
        response.requestId = response.requestId ?? request.requestId
        response.status = response.status ?? normalizedMemoryRetrievalStatus(response)
        response.resolvedScope = response.resolvedScope ?? response.scope
        response.results = response.results ?? normalizedMemoryRetrievalResults(snippets: response.snippets)
        response.truncated = response.truncated ?? (response.truncatedItems > 0)
        response.budgetUsedChars = response.budgetUsedChars ?? estimatedMemoryRetrievalBudgetUsedChars(snippets: response.snippets)
        return response
    }

    private static func requestMemoryRetrievalViaRustProjectCanonicalObjects(
        payload: MemoryRetrievalPayload,
        routeDecision: HubRouteDecision,
        timeoutSec: Double
    ) async -> MemoryRetrievalResponsePayload? {
        guard routeDecision.mode != .fileIPC,
              let useMode = XTMemoryUseMode.parse(payload.mode),
              rustProjectCanonicalMemoryRetrievalAllowed(for: useMode),
              let projectId = normalized(payload.projectId),
              hasSuccessfulRustProjectCanonicalSync(projectId: projectId),
              let snapshot = await fetchRustProjectCanonicalMemorySnapshot(
                projectId: projectId,
                limit: max(16, min(128, payload.maxResults * 8)),
                timeoutSec: timeoutSec
              ) else {
            return nil
        }

        let ranked = snapshot.objects.compactMap { object -> (RustProjectCanonicalMemoryObject, Double)? in
            guard rustProjectCanonicalMemoryRetrievalObjectAllowed(object, payload: payload),
                  let score = rustProjectCanonicalMemoryRetrievalScore(object, payload: payload) else {
                return nil
            }
            return (object, score)
        }
        .sorted { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
            let lhsRank = rustProjectCanonicalMemorySourceRank(lhs.0.sourceKind)
            let rhsRank = rustProjectCanonicalMemorySourceRank(rhs.0.sourceKind)
            if lhsRank != rhsRank { return lhsRank < rhsRank }
            return lhs.0.memoryId.localizedCaseInsensitiveCompare(rhs.0.memoryId) == .orderedAscending
        }

        let selected = Array(ranked.prefix(max(1, min(6, payload.maxResults))))
        guard !selected.isEmpty else { return nil }

        let snippets = selected.enumerated().map { index, rankedObject in
            let object = rankedObject.0
            let score = rankedObject.1
            let snippet = clippedMemorySnippetText(
                object.text,
                maxChars: payload.maxSnippetChars
            )
            return MemoryRetrievalSnippet(
                snippetId: "rust_object_\(index + 1)",
                sourceKind: object.sourceKind,
                title: normalized(object.title) ?? normalized(object.summary) ?? object.memoryId,
                ref: rustProjectCanonicalMemoryRef(object),
                text: snippet.text,
                score: Int((max(0.0, min(1.0, score)) * 100.0).rounded()),
                truncated: snippet.truncated
            )
        }
        let results = zip(selected, snippets).map { rankedObject, snippet in
            MemoryRetrievalResultItem(
                ref: snippet.ref,
                sourceKind: snippet.sourceKind,
                summary: snippet.title,
                snippet: snippet.text,
                score: max(0.0, min(1.0, rankedObject.1)),
                redacted: snippet.text.lowercased().contains("redacted by rust memory policy")
            )
        }
        let truncatedItems = max(0, ranked.count - selected.count)
        return MemoryRetrievalResponsePayload(
            schemaVersion: "xt.memory_retrieval_result.v1",
            requestId: payload.requestId,
            status: "ok",
            resolvedScope: payload.scope,
            source: "rust_memory_objects",
            scope: payload.scope,
            auditRef: payload.auditRef,
            results: results,
            snippets: snippets,
            truncated: truncatedItems > 0,
            budgetUsedChars: estimatedMemoryRetrievalBudgetUsedChars(snippets: snippets),
            truncatedItems: truncatedItems,
            redactedItems: results.filter(\.redacted).count
        )
    }

    private static func rustProjectCanonicalMemoryRetrievalAllowed(
        for useMode: XTMemoryUseMode
    ) -> Bool {
        switch useMode {
        case .projectChat, .supervisorOrchestration, .toolPlan:
            return true
        default:
            return false
        }
    }

    private static func rustProjectCanonicalMemoryRetrievalObjectAllowed(
        _ object: RustProjectCanonicalMemoryObject,
        payload: MemoryRetrievalPayload
    ) -> Bool {
        let layer = normalized(object.layer)?.lowercased() ?? ""
        let sourceKind = normalized(object.sourceKind)?.lowercased() ?? ""
        let allowedLayers = Set(payload.allowedLayers.compactMap { normalized($0)?.lowercased() })
        let requestedKinds = Set(payload.requestedKinds.compactMap { normalized($0)?.lowercased() })
        guard allowedLayers.isEmpty || allowedLayers.contains(layer) else { return false }
        guard requestedKinds.isEmpty || requestedKinds.contains(sourceKind) else { return false }

        let explicitRefs = payload.explicitRefs.compactMap { normalized($0)?.lowercased() }
        guard !explicitRefs.isEmpty else { return true }
        let memoryId = object.memoryId.lowercased()
        let objectRef = rustProjectCanonicalMemoryRef(object).lowercased()
        return explicitRefs.contains { ref in
            ref == memoryId || ref == objectRef || ref.hasSuffix("/\(memoryId)")
        }
    }

    private static func rustProjectCanonicalMemoryRetrievalScore(
        _ object: RustProjectCanonicalMemoryObject,
        payload: MemoryRetrievalPayload
    ) -> Double? {
        let sourceKind = normalized(object.sourceKind)?.lowercased() ?? ""
        let requestedKinds = Set(payload.requestedKinds.compactMap { normalized($0)?.lowercased() })
        let explicitRefs = payload.explicitRefs.compactMap { normalized($0)?.lowercased() }
        if !explicitRefs.isEmpty {
            return 1.0
        }

        let queryTokens = memoryRetrievalQueryTokens(payload.query)
        let haystack = [
            object.title,
            object.summary ?? "",
            object.sourceKind,
            object.text
        ]
        .joined(separator: " ")
        .lowercased()
        let hitCount = queryTokens.filter { haystack.contains($0) }.count
        if !queryTokens.isEmpty, hitCount == 0, requestedKinds.isEmpty {
            return nil
        }

        var score = 0.70
        if requestedKinds.contains(sourceKind) {
            score += 0.10
        }
        if !queryTokens.isEmpty {
            score += min(0.18, (Double(hitCount) / Double(queryTokens.count)) * 0.18)
        }
        score += max(0.0, 0.02 - (Double(rustProjectCanonicalMemorySourceRank(object.sourceKind)) * 0.001))
        return max(0.0, min(1.0, score))
    }

    private static func memoryRetrievalQueryTokens(_ query: String) -> [String] {
        let separators = CharacterSet.alphanumerics.inverted
        return query
            .lowercased()
            .components(separatedBy: separators)
            .compactMap { token in
                let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.count >= 2 ? trimmed : nil
            }
    }

    private static func clippedMemorySnippetText(
        _ text: String,
        maxChars: Int
    ) -> (text: String, truncated: Bool) {
        let normalizedText = normalized(text) ?? ""
        let boundedMax = max(80, min(1_200, maxChars))
        guard normalizedText.count > boundedMax else {
            return (normalizedText, false)
        }
        return (String(normalizedText.prefix(boundedMax)), true)
    }

    private static func rustProjectCanonicalMemoryRef(
        _ object: RustProjectCanonicalMemoryObject
    ) -> String {
        "memory://rust/\(object.memoryId)"
    }

    private static func requestMemoryRetrievalViaPreferredRemote(
        payload: MemoryRetrievalPayload,
        timeoutSec: Double
    ) async -> MemoryRetrievalResponsePayload? {
        if let override = remoteMemoryRetrievalOverride() {
            return await override(payload, timeoutSec)
        }

        let remote = await HubPairingCoordinator.shared.fetchRemoteMemoryRetrieval(
            options: HubAIClient.remoteConnectOptionsFromDefaults(stateDir: nil),
            payload: payload,
            timeoutSec: timeoutSec,
            allowClientKitInstallRetry: false
        )
        guard remote.ok else { return nil }

        let results = remote.results.map { item in
            MemoryRetrievalResultItem(
                ref: item.ref,
                sourceKind: item.sourceKind,
                summary: item.summary,
                snippet: item.snippet,
                score: min(1.0, max(0.0, item.score)),
                redacted: item.redacted
            )
        }

        return MemoryRetrievalResponsePayload(
            schemaVersion: remote.schemaVersion,
            requestId: remote.requestId ?? payload.requestId,
            status: remote.status,
            resolvedScope: remote.resolvedScope,
            source: remote.source,
            scope: remote.scope,
            auditRef: remote.auditRef,
            reasonCode: remote.reasonCode,
            denyCode: remote.denyCode,
            results: results,
            snippets: synthesizedMemoryRetrievalSnippets(results: results),
            truncated: remote.truncated,
            budgetUsedChars: remote.budgetUsedChars,
            truncatedItems: remote.truncatedItems,
            redactedItems: remote.redactedItems
        )
    }

    static func requestMemoryRetrieval(
        _ request: MemoryRetrievalRequest,
        timeoutSec: Double = 1.0
    ) async -> MemoryRetrievalResponsePayload? {
        let requestId = "memreq_\(String(UUID().uuidString.lowercased().prefix(12)))"
        let normalizedRequestedKinds = HubIPCClient.orderedUniqueStringTokens(request.requestedKinds)
        let normalizedExplicitRefs = HubIPCClient.orderedUniqueStringTokens(request.explicitRefs)
        let explicitRetrievalKind = normalized(request.retrievalKind) ?? ""
        let normalizedScope = normalized(request.scope) ?? "current_project"
        let payload = MemoryRetrievalPayload(
            requestId: requestId,
            scope: normalizedScope,
            requesterRole: request.requesterRole.rawValue,
            mode: request.useMode.rawValue,
            projectId: normalized(request.projectId),
            crossProjectTargetIds: orderedUniqueStringTokens(request.crossProjectTargetIds),
            projectRoot: normalized(request.projectRoot),
            displayName: normalized(request.displayName),
            query: request.query,
            latestUser: request.query,
            allowedLayers: request.allowedLayers.isEmpty
                ? allowedLayersForMemoryRetrieval(
                    requestedKinds: normalizedRequestedKinds,
                    explicitRefs: normalizedExplicitRefs
                )
                : orderedUniqueStringTokens(request.allowedLayers.map(\.rawValue)),
            retrievalKind: explicitRetrievalKind.isEmpty
                ? normalizedMemoryRetrievalKind(
                    explicitRefs: normalizedExplicitRefs,
                    requestedKinds: normalizedRequestedKinds
                )
                : explicitRetrievalKind,
            maxResults: max(1, min(6, request.maxResults)),
            reason: normalized(request.reason),
            requireExplainability: request.requireExplainability,
            requestedKinds: normalizedRequestedKinds,
            explicitRefs: normalizedExplicitRefs,
            maxSnippets: max(1, min(6, request.maxResults)),
            maxSnippetChars: max(120, min(1_200, request.maxSnippetChars)),
            auditRef: "audit-xt-memory-retrieval-\(String(UUID().uuidString.lowercased().prefix(12)))"
        )
        if let override = memoryRetrievalOverride() {
            let response = await override(payload, timeoutSec)
            return normalizedMemoryRetrievalResponse(response, request: payload)
        }
        let routeDecision = await currentRouteDecision()
        if let rust = await requestMemoryRetrievalViaRustProjectCanonicalObjects(
            payload: payload,
            routeDecision: routeDecision,
            timeoutSec: timeoutSec
        ) {
            return normalizedMemoryRetrievalResponse(rust, request: payload)
        }
        if routeDecision.preferRemote {
            let remote = await requestMemoryRetrievalViaPreferredRemote(
                payload: payload,
                timeoutSec: timeoutSec
            )
            if remote != nil {
                return normalizedMemoryRetrievalResponse(remote, request: payload)
            }
            if !routeDecision.allowFileFallback {
                return nil
            }
        }
        if routeDecision.requiresRemote {
            return nil
        }
        let response = await requestMemoryRetrievalViaLocalIPC(payload: payload, timeoutSec: timeoutSec)
        return normalizedMemoryRetrievalResponse(response, request: payload)
    }

    static func requestProjectMemoryRetrieval(
        requesterRole: XTMemoryRequesterRole,
        useMode: XTMemoryUseMode = .projectChat,
        projectId: String?,
        projectRoot: String?,
        displayName: String?,
        latestUser: String,
        reason: String?,
        requestedKinds: [String] = [],
        explicitRefs: [String] = [],
        maxSnippets: Int = 3,
        maxSnippetChars: Int = 420,
        timeoutSec: Double = 1.0
    ) async -> MemoryRetrievalResponsePayload? {
        await requestMemoryRetrieval(
            MemoryRetrievalRequest(
                requesterRole: requesterRole,
                useMode: useMode,
                projectId: projectId,
                projectRoot: projectRoot,
                displayName: displayName,
                query: latestUser,
                reason: reason,
                requestedKinds: requestedKinds,
                explicitRefs: explicitRefs,
                maxResults: maxSnippets,
                maxSnippetChars: maxSnippetChars
            ),
            timeoutSec: timeoutSec
        )
    }
}
