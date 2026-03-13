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

    static func build(from req: IPCMemoryRetrievalRequestPayload) -> IPCMemoryRetrievalResponsePayload {
        let scope = normalized(req.scope).isEmpty ? "current_project" : normalized(req.scope)
        let auditRef = firstNonEmpty(req.auditRef, "audit-hub-memory-retrieval")
        guard scope == "current_project" else {
            return IPCMemoryRetrievalResponsePayload(
                source: "hub_memory_retrieval_v1",
                scope: scope,
                auditRef: auditRef,
                reasonCode: "unsupported_scope",
                denyCode: "cross_scope_memory_denied",
                snippets: [],
                truncatedItems: 0,
                redactedItems: 0
            )
        }

        let projectId = normalized(req.projectId)
        let projectRoot = normalized(req.projectRoot)
        let displayName = normalized(req.displayName)
        guard !projectId.isEmpty || !projectRoot.isEmpty || !displayName.isEmpty else {
            return IPCMemoryRetrievalResponsePayload(
                source: "hub_memory_retrieval_v1",
                scope: scope,
                auditRef: auditRef,
                reasonCode: "project_context_missing",
                denyCode: "cross_scope_memory_denied",
                snippets: [],
                truncatedItems: 0,
                redactedItems: 0
            )
        }

        let query = normalized(req.latestUser)
        let queryTokens = retrievalTokens(query)
        let kinds = normalizedKinds(req.requestedKinds)
        let explicitRefs = orderedUnique(req.explicitRefs.map(normalized).filter { !$0.isEmpty })
        let maxSnippets = clamp(req.maxSnippets, min: 1, max: 6)
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

        if shouldInclude(kind: "canonical_memory", requestedKinds: kinds) {
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

        if shouldInclude(kind: "project_spec_capsule", requestedKinds: kinds) {
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

        if shouldInclude(kind: "decision_track", requestedKinds: kinds) {
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

        if shouldInclude(kind: "background_preferences", requestedKinds: kinds) {
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

        if shouldInclude(kind: "recent_context", requestedKinds: kinds) {
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

        let ranked = deduped(candidates)
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                return lhs.snippetId < rhs.snippetId
            }
        let selected = Array(ranked.prefix(maxSnippets))

        let reasonCode = selected.isEmpty ? "no_relevant_snippets" : nil
        let summary = selected.isEmpty ? "none" : selected.map(\.sourceKind).joined(separator: ",")
        HubDiagnostics.log(
            "memory_retrieval.build scope=\(scope) requester=\(normalized(req.requesterRole)) " +
            "snippets=\(selected.count) sources=\(summary) redacted=\(redactedItems) truncated=\(truncatedItems)"
        )

        return IPCMemoryRetrievalResponsePayload(
            source: "hub_memory_retrieval_v1",
            scope: scope,
            auditRef: auditRef,
            reasonCode: reasonCode,
            denyCode: nil,
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
            truncatedItems: truncatedItems,
            redactedItems: redactedItems
        )
    }

    private static func shouldInclude(kind: String, requestedKinds: [String]) -> Bool {
        requestedKinds.isEmpty || requestedKinds.contains(kind)
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

        let url = URL(fileURLWithPath: ref)
        switch url.lastPathComponent {
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
        default:
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

        if containsAny(query, needles: ["之前", "上次", "刚才", "历史", "上下文", "记忆", "earlier", "previous", "history", "context"]) &&
            sourceKind == "recent_context" {
            score += 60
        }
        if containsAny(query, needles: ["决策", "决定", "why", "decision", "approved", "approval", "scope", "技术栈", "tech", "stack"]) &&
            (sourceKind == "decision_track" || sourceKind == "project_spec_capsule") {
            score += 55
        }
        if containsAny(query, needles: ["偏好", "风格", "preference", "style", "ux"]) &&
            sourceKind == "background_preferences" {
            score += 45
        }

        return score
    }

    private static func retrievalTokens(_ raw: String) -> [String] {
        let lower = raw.lowercased()
        let parts = lower.components(separatedBy: CharacterSet.alphanumerics.inverted)
        var out = parts.filter { $0.count >= 3 }
        for needle in ["之前", "上次", "刚才", "历史", "上下文", "记忆", "决策", "技术栈", "规格", "里程碑", "阻塞"] where raw.contains(needle) {
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
