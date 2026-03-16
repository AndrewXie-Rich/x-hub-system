import Foundation

enum AXMemoryLifecyclePhase: String, Codable, Sendable {
    case afterTurn = "after_turn"
    case sessionResetOrSwitch = "session_reset_or_switch"
}

enum AXMemoryLifecycleChangeKind: String, Codable, Sendable {
    case unchanged
    case added
    case updated
    case cleared
}

struct AXMemoryLifecycleScalarDelta: Equatable, Codable {
    var before: String
    var after: String
    var change: AXMemoryLifecycleChangeKind
}

struct AXMemoryLifecycleMemorySummary: Equatable, Codable {
    var goal: String
    var currentState: String
    var blocker: String
    var nextStep: String
}

struct AXMemoryLifecycleWorkingSetSummary: Equatable, Codable {
    var recentMessageCount: Int
    var recentUserTurnCount: Int
    var latestUserMessage: String
    var latestAssistantMessage: String
    var resumeSummary: String
    var refs: [String]

    enum CodingKeys: String, CodingKey {
        case recentMessageCount = "recent_message_count"
        case recentUserTurnCount = "recent_user_turn_count"
        case latestUserMessage = "latest_user_message"
        case latestAssistantMessage = "latest_assistant_message"
        case resumeSummary = "resume_summary"
        case refs
    }
}

struct AXMemoryLifecycleCompactionHint: Equatable, Codable {
    var projectState: SupervisorProjectCapsuleState
    var sourceNodeCount: Int
    var keepNodeIds: [String]
    var rollupNodeIds: [String]
    var archiveNodeIds: [String]
    var protectedNodeIds: [String]
    var archiveCandidate: Bool
    var policyReasons: [String]
    var requiredSurvivingRefs: [String]

    enum CodingKeys: String, CodingKey {
        case projectState = "project_state"
        case sourceNodeCount = "source_node_count"
        case keepNodeIds = "keep_node_ids"
        case rollupNodeIds = "rollup_node_ids"
        case archiveNodeIds = "archive_node_ids"
        case protectedNodeIds = "protected_node_ids"
        case archiveCandidate = "archive_candidate"
        case policyReasons = "policy_reasons"
        case requiredSurvivingRefs = "required_surviving_refs"
    }
}

struct AXAfterTurnMemoryLifecycleArtifact: Equatable, Codable {
    static let schemaVersion = "xt.after_turn_memory_lifecycle.v1"

    var schemaVersion: String
    var phase: AXMemoryLifecyclePhase
    var turnId: String
    var projectId: String
    var projectRoot: String
    var createdAtMs: Int64
    var pipelineSource: String
    var turn: AXConversationTurn
    var observationDelta: AXMemoryDelta
    var beforeSummary: AXMemoryLifecycleMemorySummary
    var afterSummary: AXMemoryLifecycleMemorySummary
    var blockerDelta: AXMemoryLifecycleScalarDelta
    var nextStepDelta: AXMemoryLifecycleScalarDelta
    var workingSetSummary: AXMemoryLifecycleWorkingSetSummary
    var decisionCandidates: [SupervisorDecisionTrackEvent]
    var backgroundPreferenceCandidates: [SupervisorBackgroundPreferenceNote]
    var compactionHint: AXMemoryLifecycleCompactionHint
    var refs: [String]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case phase
        case turnId = "turn_id"
        case projectId = "project_id"
        case projectRoot = "project_root"
        case createdAtMs = "created_at_ms"
        case pipelineSource = "pipeline_source"
        case turn
        case observationDelta = "observation_delta"
        case beforeSummary = "before_summary"
        case afterSummary = "after_summary"
        case blockerDelta = "blocker_delta"
        case nextStepDelta = "next_step_delta"
        case workingSetSummary = "working_set_summary"
        case decisionCandidates = "decision_candidates"
        case backgroundPreferenceCandidates = "background_preference_candidates"
        case compactionHint = "compaction_hint"
        case refs
    }
}

struct AXSessionSummaryCapsule: Equatable, Codable {
    static let schemaVersion = "xt.session_summary_capsule.v1"

    var schemaVersion: String
    var phase: AXMemoryLifecyclePhase
    var projectId: String
    var projectRoot: String
    var reason: String
    var createdAtMs: Int64
    var memorySummary: AXMemoryLifecycleMemorySummary
    var workingSetSummary: AXMemoryLifecycleWorkingSetSummary
    var refs: [String]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case phase
        case projectId = "project_id"
        case projectRoot = "project_root"
        case reason
        case createdAtMs = "created_at_ms"
        case memorySummary = "memory_summary"
        case workingSetSummary = "working_set_summary"
        case refs
    }
}

enum AXMemoryLifecycleStore {
    @discardableResult
    static func recordAfterTurn(
        ctx: AXProjectContext,
        turn: AXConversationTurn,
        beforeMemory: AXMemory,
        observationDelta: AXMemoryDelta,
        afterMemory: AXMemory,
        pipelineSource: String
    ) -> AXAfterTurnMemoryLifecycleArtifact? {
        do {
            let artifact = try buildAfterTurnArtifact(
                ctx: ctx,
                turn: turn,
                beforeMemory: beforeMemory,
                observationDelta: observationDelta,
                afterMemory: afterMemory,
                pipelineSource: pipelineSource
            )
            try save(artifact, to: artifactURL(for: ctx, createdAtMs: artifact.createdAtMs), latestURL: ctx.latestMemoryLifecycleURL)
            return artifact
        } catch {
            AXProjectStore.appendRawLog(
                [
                    "type": "memory_lifecycle",
                    "phase": "after_turn_failed",
                    "created_at": Date().timeIntervalSince1970,
                    "error": String(describing: error)
                ],
                for: ctx
            )
            return nil
        }
    }

    @discardableResult
    static func writeSessionSummaryCapsule(
        ctx: AXProjectContext,
        reason: String,
        excludingTrailingUserText: String? = nil,
        now: Double = Date().timeIntervalSince1970
    ) -> AXSessionSummaryCapsule? {
        do {
            let recent = filteredRecentContext(
                AXRecentContextStore.load(for: ctx),
                excludingTrailingUserText: excludingTrailingUserText
            )
            let memory = try AXProjectStore.loadOrCreateMemory(for: ctx)
            let projectId = AXProjectRegistryStore.projectId(forRoot: ctx.root)
            let summary = AXSessionSummaryCapsule(
                schemaVersion: AXSessionSummaryCapsule.schemaVersion,
                phase: .sessionResetOrSwitch,
                projectId: projectId,
                projectRoot: ctx.root.path,
                reason: normalizedReason(reason),
                createdAtMs: max(0, Int64((now * 1_000.0).rounded())),
                memorySummary: memorySummary(for: memory),
                workingSetSummary: workingSetSummary(
                    recent: recent,
                    memory: memory,
                    ctx: ctx
                ),
                refs: dedupe([
                    ctx.memoryJSONURL.path,
                    ctx.memoryMarkdownURL.path,
                    AXRecentContextStore.jsonURL(for: ctx).path,
                    AXRecentContextStore.markdownURL(for: ctx).path
                ])
            )
            try save(summary, to: sessionSummaryURL(for: ctx, createdAtMs: summary.createdAtMs), latestURL: ctx.latestSessionSummaryURL)
            return summary
        } catch {
            AXProjectStore.appendRawLog(
                [
                    "type": "memory_lifecycle",
                    "phase": "session_summary_failed",
                    "created_at": Date().timeIntervalSince1970,
                    "reason": normalizedReason(reason),
                    "error": String(describing: error)
                ],
                for: ctx
            )
            return nil
        }
    }

    static func buildAfterTurnArtifact(
        ctx: AXProjectContext,
        turn: AXConversationTurn,
        beforeMemory: AXMemory,
        observationDelta: AXMemoryDelta,
        afterMemory: AXMemory,
        pipelineSource: String
    ) throws -> AXAfterTurnMemoryLifecycleArtifact {
        try ctx.ensureDirs()
        try FileManager.default.createDirectory(at: ctx.memoryLifecycleDir, withIntermediateDirectories: true)

        let projectId = AXProjectRegistryStore.projectId(forRoot: ctx.root)
        let createdAtMs = max(0, Int64((turn.createdAt * 1_000.0).rounded()))
        let recent = AXRecentContextStore.load(for: ctx)
        let decisionSnapshot = SupervisorDecisionTrackStore.load(for: ctx)
        let backgroundSnapshot = SupervisorBackgroundPreferenceTrackStore.load(for: ctx)
        let beforeSummary = memorySummary(for: beforeMemory)
        let afterSummary = memorySummary(for: afterMemory)
        let workingSet = workingSetSummary(recent: recent, memory: afterMemory, ctx: ctx)
        let refs = buildRefs(
            ctx: ctx,
            decisionSnapshot: decisionSnapshot,
            backgroundSnapshot: backgroundSnapshot
        )

        return AXAfterTurnMemoryLifecycleArtifact(
            schemaVersion: AXAfterTurnMemoryLifecycleArtifact.schemaVersion,
            phase: .afterTurn,
            turnId: turnID(createdAtMs: createdAtMs),
            projectId: projectId,
            projectRoot: ctx.root.path,
            createdAtMs: createdAtMs,
            pipelineSource: normalizedReason(pipelineSource),
            turn: turn,
            observationDelta: observationDelta,
            beforeSummary: beforeSummary,
            afterSummary: afterSummary,
            blockerDelta: scalarDelta(before: beforeSummary.blocker, after: afterSummary.blocker),
            nextStepDelta: scalarDelta(before: beforeSummary.nextStep, after: afterSummary.nextStep),
            workingSetSummary: workingSet,
            decisionCandidates: decisionCandidates(
                projectId: projectId,
                turn: turn,
                createdAtMs: createdAtMs,
                existing: decisionSnapshot.events
            ),
            backgroundPreferenceCandidates: backgroundCandidates(
                projectId: projectId,
                turn: turn,
                createdAtMs: createdAtMs,
                existing: backgroundSnapshot.notes
            ),
            compactionHint: compactionHint(
                ctx: ctx,
                turn: turn,
                memory: afterMemory,
                recent: recent,
                decisionSnapshot: decisionSnapshot
            ),
            refs: refs
        )
    }

    private static func compactionHint(
        ctx: AXProjectContext,
        turn: AXConversationTurn,
        memory: AXMemory,
        recent: AXRecentContext,
        decisionSnapshot: SupervisorDecisionTrackSnapshot
    ) -> AXMemoryLifecycleCompactionHint {
        let nowMs = max(0, Int64((turn.createdAt * 1_000.0).rounded()))
        let nodes = compactionNodes(
            ctx: ctx,
            turn: turn,
            recent: recent,
            decisionSnapshot: decisionSnapshot
        )
        let state = projectState(for: memory)
        let plan = SupervisorMemoryCompactionPolicy.makePlan(
            SupervisorMemoryCompactionPolicyInput(
                projectId: AXProjectRegistryStore.projectId(forRoot: ctx.root),
                projectState: state,
                nowMs: nowMs,
                nodes: nodes
            )
        )
        return AXMemoryLifecycleCompactionHint(
            projectState: state,
            sourceNodeCount: nodes.count,
            keepNodeIds: plan.keepNodes.map(\.id),
            rollupNodeIds: plan.rollupNodes.map(\.id),
            archiveNodeIds: plan.archiveNodes.map(\.id),
            protectedNodeIds: plan.protectedNodes.map(\.id),
            archiveCandidate: plan.archiveCandidate,
            policyReasons: plan.policyReasons,
            requiredSurvivingRefs: SupervisorMemoryCompactionPolicy.requiredSurvivingRefs(in: plan.keepNodes)
        )
    }

    private static func compactionNodes(
        ctx: AXProjectContext,
        turn: AXConversationTurn,
        recent: AXRecentContext,
        decisionSnapshot: SupervisorDecisionTrackSnapshot
    ) -> [SupervisorMemoryNode] {
        let recentMessages = recent.messages.sorted { $0.createdAt < $1.createdAt }
        let activeStartIndex = max(recentMessages.count - 8, 0)
        var nodes: [SupervisorMemoryNode] = []

        for (index, message) in recentMessages.enumerated() {
            let createdAtMs = max(0, Int64((message.createdAt * 1_000.0).rounded()))
            let isWorkingSet = index >= activeStartIndex
            let ref = "\(AXRecentContextStore.jsonURL(for: ctx).path)#message:\(index)"
            nodes.append(
                SupervisorMemoryNode(
                    id: "recent-\(index)",
                    kind: isWorkingSet ? .workingSet : .observation,
                    createdAtMs: createdAtMs,
                    lastTouchedAtMs: createdAtMs,
                    summary: "\(message.role): \(truncate(message.content, max: 160))",
                    refs: [ref],
                    pinned: false,
                    active: isWorkingSet
                )
            )
        }

        let turnMs = max(0, Int64((turn.createdAt * 1_000.0).rounded()))
        nodes.append(
            SupervisorMemoryNode(
                id: "turn-\(turnMs)",
                kind: .actionLog,
                createdAtMs: turnMs,
                lastTouchedAtMs: turnMs,
                summary: "turn: \(truncate(turn.user, max: 120))",
                refs: [ctx.rawLogURL.path],
                pinned: false,
                active: true
            )
        )

        for event in decisionSnapshot.events {
            let normalized = event.sanitizedForStorage
            guard !normalized.decisionId.isEmpty else { continue }
            nodes.append(
                SupervisorMemoryNode(
                    id: "decision-\(normalized.decisionId)",
                    kind: .decision,
                    createdAtMs: normalized.createdAtMs,
                    lastTouchedAtMs: normalized.updatedAtMs,
                    summary: normalized.statement,
                    refs: dedupe([normalized.auditRef] + normalized.evidenceRefs),
                    decisionId: normalized.decisionId,
                    pinned: normalized.status == .approved,
                    active: normalized.updatedAtMs + (24 * 60 * 60 * 1_000) >= turnMs
                )
            )
        }

        return nodes.sorted { lhs, rhs in
            if lhs.lastTouchedAtMs == rhs.lastTouchedAtMs {
                return lhs.id < rhs.id
            }
            return lhs.lastTouchedAtMs < rhs.lastTouchedAtMs
        }
    }

    private static func decisionCandidates(
        projectId: String,
        turn: AXConversationTurn,
        createdAtMs: Int64,
        existing: [SupervisorDecisionTrackEvent]
    ) -> [SupervisorDecisionTrackEvent] {
        let text = normalizedText(turn.user)
        guard !text.isEmpty else { return [] }
        guard let category = decisionCategory(for: text), containsDecisionMarker(text) else {
            return []
        }

        let statement = truncate(turn.user.trimmingCharacters(in: .whitespacesAndNewlines), max: 240)
        let statementKey = normalizedText(statement)
        let duplicate = existing.map(\.sanitizedForStorage).contains {
            $0.category == category && normalizedText($0.statement) == statementKey
        }
        guard !duplicate else {
            return []
        }

        let source = "after_turn_candidate_user_explicit"
        return [
            SupervisorDecisionTrackBuilder.build(
                decisionId: "candidate_\(category.rawValue)_\(createdAtMs)",
                projectId: projectId,
                category: category,
                status: .proposed,
                statement: statement,
                source: source,
                reversible: category != .approvalResult,
                approvalRequired: category == .approvalResult || category == .riskPosture,
                auditRef: "after_turn_candidate:\(projectId):\(category.rawValue):\(createdAtMs)",
                evidenceRefs: [],
                createdAtMs: createdAtMs,
                updatedAtMs: createdAtMs
            )
        ]
    }

    private static func backgroundCandidates(
        projectId: String,
        turn: AXConversationTurn,
        createdAtMs: Int64,
        existing: [SupervisorBackgroundPreferenceNote]
    ) -> [SupervisorBackgroundPreferenceNote] {
        let text = normalizedText(turn.user)
        guard !text.isEmpty else { return [] }
        guard let domain = backgroundDomain(for: text), containsBackgroundMarker(text) else {
            return []
        }

        let statement = truncate(turn.user.trimmingCharacters(in: .whitespacesAndNewlines), max: 240)
        let statementKey = normalizedText(statement)
        let duplicate = existing.map(\.sanitizedForStorage).contains {
            $0.domain == domain && normalizedText($0.statement) == statementKey
        }
        guard !duplicate else {
            return []
        }

        let strength: SupervisorBackgroundPreferenceStrength = text.contains("必须") ? .strong : .medium
        return [
            SupervisorBackgroundPreferenceTrackBuilder.build(
                noteId: "candidate_\(domain.rawValue)_\(createdAtMs)",
                projectId: projectId,
                domain: domain,
                strength: strength,
                statement: statement,
                mustNotPromoteWithoutDecision: true,
                createdAtMs: createdAtMs
            )
        ]
    }

    private static func decisionCategory(for normalizedLowercaseText: String) -> SupervisorDecisionCategory? {
        if containsAny(normalizedLowercaseText, tokens: ["批准", "approval", "approve", "拒绝", "deny", "通过", "不通过"]) {
            return .approvalResult
        }
        if containsAny(normalizedLowercaseText, tokens: ["技术栈", "tech stack", "framework", "框架", "语言", "swiftui", "swift package", "react", "vue", "unity", "typescript", "c#"]) {
            return .techStack
        }
        if containsAny(normalizedLowercaseText, tokens: ["scope", "范围", "只做", "不做", "mvp", "non goal", "non-goal", "freeze", "冻结", "锁定"]) {
            return .scopeFreeze
        }
        if containsAny(normalizedLowercaseText, tokens: ["风险", "risk", "安全", "security", "联网", "network", "grant", "授权", "budget", "额度", "paid model", "付费模型"]) {
            return .riskPosture
        }
        if containsAny(normalizedLowercaseText, tokens: ["ui", "界面", "视觉", "布局", "风格", "typography", "颜色", "配色", "design"]) {
            return .uiStyle
        }
        return nil
    }

    private static func backgroundDomain(for normalizedLowercaseText: String) -> SupervisorBackgroundPreferenceDomain? {
        if containsAny(normalizedLowercaseText, tokens: ["ui", "界面", "视觉", "布局", "风格", "typography", "颜色", "配色", "design", "原汁原味"]) {
            return .uxStyle
        }
        if containsAny(normalizedLowercaseText, tokens: ["技术栈", "tech stack", "framework", "框架", "语言", "swiftui", "swift package", "react", "vue", "unity", "typescript", "c#"]) {
            return .techStack
        }
        return nil
    }

    private static func containsDecisionMarker(_ normalizedLowercaseText: String) -> Bool {
        containsAny(
            normalizedLowercaseText,
            tokens: ["决定", "定为", "确定", "采用", "锁定", "freeze", "批准", "approve", "拒绝", "deny", "只做", "不做", "必须", "改成", "就用"]
        )
    }

    private static func containsBackgroundMarker(_ normalizedLowercaseText: String) -> Bool {
        containsAny(
            normalizedLowercaseText,
            tokens: ["prefer", "更喜欢", "偏好", "倾向", "希望", "想要", "最好", "尽量", "不要太", "更自然", "action-first", "原汁原味"]
        )
    }

    private static func workingSetSummary(
        recent: AXRecentContext,
        memory: AXMemory,
        ctx: AXProjectContext
    ) -> AXMemoryLifecycleWorkingSetSummary {
        let recentMessages = recent.messages.sorted { $0.createdAt < $1.createdAt }
        let latestUser = recentMessages.last(where: { $0.role == "user" })?.content ?? ""
        let latestAssistant = recentMessages.last(where: { $0.role == "assistant" })?.content ?? ""
        let summary = [
            latestUser.isEmpty ? nil : "latest_user=\(truncate(latestUser, max: 120))",
            latestAssistant.isEmpty ? nil : "latest_assistant=\(truncate(latestAssistant, max: 120))",
            firstNonEmpty(memory.nextSteps).isEmpty ? nil : "carry_next=\(truncate(firstNonEmpty(memory.nextSteps), max: 120))",
            blockerSummary(for: memory).isEmpty ? nil : "carry_blocker=\(truncate(blockerSummary(for: memory), max: 120))"
        ]
        .compactMap { $0 }
        .joined(separator: " | ")

        return AXMemoryLifecycleWorkingSetSummary(
            recentMessageCount: recentMessages.count,
            recentUserTurnCount: recentMessages.filter { $0.role == "user" }.count,
            latestUserMessage: truncate(latestUser, max: 240),
            latestAssistantMessage: truncate(latestAssistant, max: 240),
            resumeSummary: summary,
            refs: [
                AXRecentContextStore.jsonURL(for: ctx).path,
                AXRecentContextStore.markdownURL(for: ctx).path
            ]
        )
    }

    private static func filteredRecentContext(
        _ recent: AXRecentContext,
        excludingTrailingUserText: String?
    ) -> AXRecentContext {
        let excluded = normalizedComparableText(excludingTrailingUserText ?? "")
        guard !excluded.isEmpty else {
            return recent
        }

        var filtered = recent
        if let last = filtered.messages.last,
           last.role == "user",
           normalizedComparableText(last.content) == excluded {
            filtered.messages.removeLast()
        }
        return filtered
    }

    private static func memorySummary(for memory: AXMemory) -> AXMemoryLifecycleMemorySummary {
        AXMemoryLifecycleMemorySummary(
            goal: memory.goal.trimmingCharacters(in: .whitespacesAndNewlines),
            currentState: firstNonEmpty(memory.currentState),
            blocker: blockerSummary(for: memory),
            nextStep: firstNonEmpty(memory.nextSteps)
        )
    }

    private static func projectState(for memory: AXMemory) -> SupervisorProjectCapsuleState {
        let current = firstNonEmpty(memory.currentState)
        let blocker = blockerSummary(for: memory)
        let next = firstNonEmpty(memory.nextSteps)
        let state = SupervisorProjectCapsuleBuilder.projectState(
            runtimeState: current,
            currentAction: current,
            blocker: blocker,
            nextStep: next
        )
        switch state {
        case .idle:
            return .idle
        case .active:
            return .active
        case .blocked:
            return .blocked
        case .awaitingAuthorization:
            return .awaitingAuthorization
        case .completed:
            return .completed
        }
    }

    private static func blockerSummary(for memory: AXMemory) -> String {
        let openQuestion = firstNonEmpty(memory.openQuestions)
        if !openQuestion.isEmpty {
            return openQuestion
        }
        return firstNonEmpty(memory.risks)
    }

    private static func scalarDelta(before: String, after: String) -> AXMemoryLifecycleScalarDelta {
        let normalizedBefore = before.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedAfter = after.trimmingCharacters(in: .whitespacesAndNewlines)
        let change: AXMemoryLifecycleChangeKind
        switch (normalizedBefore.isEmpty, normalizedAfter.isEmpty) {
        case (true, true):
            change = .unchanged
        case (true, false):
            change = .added
        case (false, true):
            change = .cleared
        default:
            change = normalizedBefore == normalizedAfter ? .unchanged : .updated
        }
        return AXMemoryLifecycleScalarDelta(before: normalizedBefore, after: normalizedAfter, change: change)
    }

    private static func buildRefs(
        ctx: AXProjectContext,
        decisionSnapshot: SupervisorDecisionTrackSnapshot,
        backgroundSnapshot: SupervisorBackgroundPreferenceTrackSnapshot
    ) -> [String] {
        dedupe(
            [
                ctx.memoryJSONURL.path,
                ctx.memoryMarkdownURL.path,
                ctx.rawLogURL.path,
                AXRecentContextStore.jsonURL(for: ctx).path,
                AXRecentContextStore.markdownURL(for: ctx).path,
                ctx.supervisorDecisionTrackURL.path,
                ctx.supervisorBackgroundPreferenceTrackURL.path
            ]
            + decisionSnapshot.events.flatMap { [$0.auditRef] + $0.evidenceRefs }
            + backgroundSnapshot.notes.map(\.statement).filter { !$0.isEmpty }.map { _ in ctx.supervisorBackgroundPreferenceTrackURL.path }
        )
    }

    private static func artifactURL(for ctx: AXProjectContext, createdAtMs: Int64) -> URL {
        ctx.memoryLifecycleDir.appendingPathComponent("after_turn_\(createdAtMs)_\(UUID().uuidString.lowercased()).json")
    }

    private static func sessionSummaryURL(for ctx: AXProjectContext, createdAtMs: Int64) -> URL {
        ctx.sessionSummariesDir.appendingPathComponent("session_summary_\(createdAtMs)_\(UUID().uuidString.lowercased()).json")
    }

    private static func save<T: Encodable>(_ value: T, to target: URL, latestURL: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try writeAtomic(data: data, to: target)
        try FileManager.default.createDirectory(at: latestURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try writeAtomic(data: data, to: latestURL)
    }

    private static func writeAtomic(data: Data, to url: URL) throws {
        let temp = url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).tmp-\(UUID().uuidString)")
        try data.write(to: temp, options: .atomic)
        if FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: url)
        }
        try FileManager.default.moveItem(at: temp, to: url)
    }

    private static func turnID(createdAtMs: Int64) -> String {
        "turn_\(createdAtMs)"
    }

    private static func firstNonEmpty(_ items: [String]) -> String {
        for item in items {
            let trimmed = item.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return ""
    }

    private static func containsAny(_ text: String, tokens: [String]) -> Bool {
        tokens.contains { token in
            text.contains(token.lowercased())
        }
    }

    private static func normalizedText(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "\n", with: " ")
    }

    private static func normalizedReason(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "_")
            .lowercased()
    }

    private static func normalizedComparableText(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\r\n", with: "\n")
            .lowercased()
    }

    private static func truncate(_ text: String, max: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > max else {
            return trimmed
        }
        let end = trimmed.index(trimmed.startIndex, offsetBy: max)
        return String(trimmed[..<end]) + "..."
    }

    private static func dedupe(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else {
                continue
            }
            ordered.append(trimmed)
        }
        return ordered
    }
}
