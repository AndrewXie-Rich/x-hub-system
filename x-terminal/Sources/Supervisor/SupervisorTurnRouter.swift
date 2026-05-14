import Foundation

enum SupervisorProjectMemoryBindingStrength: String, Codable, CaseIterable, Equatable, Sendable {
    case none
    case weak
    case strong

    var requiresProjectTruth: Bool {
        self == .strong
    }
}

enum SupervisorTurnMode: String, Codable, CaseIterable, Equatable, Sendable {
    case personalFirst = "personal_first"
    case projectFirst = "project_first"
    case hybrid
    case portfolioReview = "portfolio_review"
}

struct SupervisorTurnRoutingInput: Equatable, Sendable {
    var userMessage: String
    var projects: [AXProjectEntry]
    var personalMemory: SupervisorPersonalMemorySnapshot
    var crossLinks: SupervisorCrossLinkSnapshot
    var currentProjectId: String?
    var currentPersonName: String?
    var currentCommitmentId: String?

    init(
        userMessage: String,
        projects: [AXProjectEntry],
        personalMemory: SupervisorPersonalMemorySnapshot = .empty,
        crossLinks: SupervisorCrossLinkSnapshot = .empty,
        currentProjectId: String? = nil,
        currentPersonName: String? = nil,
        currentCommitmentId: String? = nil
    ) {
        self.userMessage = userMessage
        self.projects = projects
        self.personalMemory = personalMemory
        self.crossLinks = crossLinks
        self.currentProjectId = currentProjectId
        self.currentPersonName = currentPersonName
        self.currentCommitmentId = currentCommitmentId
    }
}

struct SupervisorTurnRoutingDecision: Equatable, Sendable {
    var mode: SupervisorTurnMode
    var focusedProjectId: String?
    var focusedProjectName: String?
    var focusedPersonName: String?
    var focusedCommitmentId: String?
    var confidence: Double
    var routingReasons: [String]
    var projectMemoryBindingStrength: SupervisorProjectMemoryBindingStrength = .none
    var projectMemoryBindingReason: String? = nil

    var requiresProjectTruth: Bool {
        projectMemoryBindingStrength.requiresProjectTruth
    }

    var primaryMemoryDomain: String {
        switch mode {
        case .personalFirst:
            return "personal_memory"
        case .projectFirst:
            return "project_memory"
        case .hybrid:
            return "personal_memory + project_memory"
        case .portfolioReview:
            return "portfolio_brief"
        }
    }

    var supportingMemoryDomains: [String] {
        switch mode {
        case .personalFirst:
            return ["portfolio_brief", "project_memory_if_relevant"]
        case .projectFirst:
            return ["personal_memory", "portfolio_brief"]
        case .hybrid:
            return ["cross_link_refs", "portfolio_brief"]
        case .portfolioReview:
            return ["personal_memory", "focused_project_capsule_if_needed"]
        }
    }
}

enum SupervisorTurnRouter {
    static func route(_ input: SupervisorTurnRoutingInput) -> SupervisorTurnRoutingDecision {
        let trimmed = input.userMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
        let normalizedKey = normalizedLookupKey(trimmed)

        let explicitProject = matchedProject(in: trimmed, projects: input.projects)
        let explicitPerson = matchedPerson(
            in: trimmed,
            personalMemory: input.personalMemory,
            crossLinks: input.crossLinks
        )
        let explicitCommitment = matchedCommitment(in: trimmed, personalMemory: input.personalMemory)

        let usesProjectPointer = explicitProject == nil &&
            projectPointerTriggered(
                normalized: normalized,
                currentProjectId: input.currentProjectId
            )
        let usesPersonPointer = explicitPerson == nil &&
            personPointerTriggered(
                normalized: normalized,
                currentPersonName: input.currentPersonName
            )
        let usesCommitmentPointer = explicitCommitment == nil &&
            commitmentPointerTriggered(
                normalized: normalized,
                currentCommitmentId: input.currentCommitmentId
            )

        let focusedProject = explicitProject ?? pointerProject(
            currentProjectId: input.currentProjectId,
            projects: input.projects,
            enabled: usesProjectPointer
        )
        let focusedCommitment = explicitCommitment ?? pointerCommitment(
            currentCommitmentId: input.currentCommitmentId,
            personalMemory: input.personalMemory,
            enabled: usesCommitmentPointer
        )
        let focusedPerson = explicitPerson ?? pointerPerson(
            currentPersonName: input.currentPersonName,
            enabled: usesPersonPointer
        ) ?? focusedCommitment?.personName

        let portfolioIntent = containsAny(normalized, portfolioReviewTokens)
        let personalIntent = containsAny(normalized, personalPlanningTokens)
            || normalizedContainsAny(normalizedKey, personalPlanningTokens)
        let projectIntent = containsAny(normalized, projectTruthDemandTokens)
            || normalizedContainsAny(normalizedKey, projectTruthDemandTokens)
        let hybridSchedulingIntent = containsAny(normalized, hybridSchedulingTokens)
        let projectMemoryBindingStrength = resolvedProjectMemoryBindingStrength(
            hasProjectFocus: focusedProject != nil,
            projectTruthIntent: projectIntent
        )
        let projectMemoryBindingReason = projectMemoryBindingReason(
            strength: projectMemoryBindingStrength
        )

        var reasons: [String] = []
        if let focusedProject {
            reasons.append(
                explicitProject != nil
                    ? "explicit_project_mention:\(focusedProject.displayName)"
                    : "current_project_pointer:\(focusedProject.displayName)"
            )
        }
        if let focusedPerson, !focusedPerson.isEmpty {
            reasons.append(
                explicitPerson != nil
                    ? "explicit_person_mention:\(focusedPerson)"
                    : "current_person_pointer:\(focusedPerson)"
            )
        }
        if let focusedCommitment {
            reasons.append(
                explicitCommitment != nil
                    ? "commitment_mention:\(focusedCommitment.title)"
                    : "current_commitment_pointer:\(focusedCommitment.title)"
            )
        }
        if portfolioIntent {
            reasons.append("portfolio_review_language")
        }
        if personalIntent {
            reasons.append("personal_planning_language")
        }
        if projectIntent {
            reasons.append("project_planning_language")
        }
        if hybridSchedulingIntent {
            reasons.append("hybrid_scheduling_language")
        }

        let hasProjectFocus = focusedProject != nil
        let hasPersonalFocus = focusedPerson != nil || focusedCommitment != nil

        if portfolioIntent && !personalIntent && !hasProjectFocus && !hasPersonalFocus {
            return SupervisorTurnRoutingDecision(
                mode: .portfolioReview,
                focusedProjectId: nil,
                focusedProjectName: nil,
                focusedPersonName: nil,
                focusedCommitmentId: nil,
                confidence: 0.94,
                routingReasons: reasons,
                projectMemoryBindingStrength: projectMemoryBindingStrength,
                projectMemoryBindingReason: projectMemoryBindingReason
            )
        }

        if hasProjectFocus && (hasPersonalFocus || (personalIntent && hybridSchedulingIntent)) {
            return SupervisorTurnRoutingDecision(
                mode: .hybrid,
                focusedProjectId: focusedProject?.projectId,
                focusedProjectName: focusedProject?.displayName,
                focusedPersonName: focusedPerson,
                focusedCommitmentId: focusedCommitment?.memoryId,
                confidence: explicitProject != nil && (explicitPerson != nil || explicitCommitment != nil) ? 0.98 : 0.9,
                routingReasons: reasons,
                projectMemoryBindingStrength: projectMemoryBindingStrength,
                projectMemoryBindingReason: projectMemoryBindingReason
            )
        }

        if hasProjectFocus && projectMemoryBindingStrength.requiresProjectTruth {
            return SupervisorTurnRoutingDecision(
                mode: .projectFirst,
                focusedProjectId: focusedProject?.projectId,
                focusedProjectName: focusedProject?.displayName,
                focusedPersonName: nil,
                focusedCommitmentId: nil,
                confidence: explicitProject != nil ? 0.97 : 0.8,
                routingReasons: reasons,
                projectMemoryBindingStrength: projectMemoryBindingStrength,
                projectMemoryBindingReason: projectMemoryBindingReason
            )
        }

        if hasPersonalFocus || personalIntent || usesPersonPointer || hasProjectFocus {
            return SupervisorTurnRoutingDecision(
                mode: .personalFirst,
                focusedProjectId: nil,
                focusedProjectName: nil,
                focusedPersonName: focusedPerson,
                focusedCommitmentId: focusedCommitment?.memoryId,
                confidence: hasPersonalFocus ? 0.94 : 0.76,
                routingReasons: reasons,
                projectMemoryBindingStrength: projectMemoryBindingStrength,
                projectMemoryBindingReason: projectMemoryBindingReason
            )
        }

        if portfolioIntent {
            return SupervisorTurnRoutingDecision(
                mode: .portfolioReview,
                focusedProjectId: nil,
                focusedProjectName: nil,
                focusedPersonName: nil,
                focusedCommitmentId: nil,
                confidence: 0.86,
                routingReasons: reasons,
                projectMemoryBindingStrength: projectMemoryBindingStrength,
                projectMemoryBindingReason: projectMemoryBindingReason
            )
        }

        return SupervisorTurnRoutingDecision(
            mode: input.projects.isEmpty ? .personalFirst : .personalFirst,
            focusedProjectId: nil,
            focusedProjectName: nil,
            focusedPersonName: nil,
            focusedCommitmentId: nil,
            confidence: 0.55,
            routingReasons: reasons.isEmpty ? ["default_personal_fallback"] : reasons,
            projectMemoryBindingStrength: projectMemoryBindingStrength,
            projectMemoryBindingReason: projectMemoryBindingReason
        )
    }

    private static let portfolioReviewTokens = [
        "整体",
        "全局",
        "总览",
        "portfolio",
        "overview",
        "优先级",
        "priority",
        "先抓什么",
        "最重要",
        "哪些项目",
        "所有项目",
        "全部项目"
    ]

    private static let personalPlanningTokens = [
        "我今天",
        "今天最重要",
        "今天重点",
        "今天先",
        "今天先做什么",
        "先做什么",
        "怎么安排",
        "谁在等我",
        "该先回谁",
        "提醒我",
        "morning brief",
        "evening wrap",
        "weekly review",
        "我叫什么",
        "正常聊天",
        "闲聊",
        "聊聊天"
    ]

    private static let projectTruthDemandTokens = [
        "当前状态",
        "现在状态",
        "最近进展",
        "进度",
        "下一步",
        "怎么推进",
        "推进",
        "继续",
        "接着做",
        "继续做",
        "继续推进",
        "blocker",
        "卡点",
        "阻塞",
        "review",
        "审查",
        "审阅",
        "评审",
        "纠偏",
        "工单",
        "交付",
        "done",
        "build",
        "test",
        "repo",
        "代码",
        "文件",
        "编译",
        "修复",
        "fix",
        "patch",
        "日志",
        "报错",
        "错误",
        "执行",
        "验证",
        "verify",
        "证据",
        "evidence",
        "spec",
        "decision",
        "上下文记忆",
        "项目记忆",
        "完整上下文",
        "背景信息",
        "历史决策",
        "架构",
        "tech stack",
        "history",
        "context",
        "demo"
    ]

    private static let hybridSchedulingTokens = [
        "今天怎么安排",
        "怎么安排",
        "怎么平衡",
        "平衡一下",
        "先回谁",
        "先做什么"
    ]

    private static let projectPointerTokens = [
        "这个项目",
        "当前项目",
        "这个任务",
        "当前任务",
        "按这个继续",
        "继续这个",
        "它"
    ]

    private static let personPointerTokens = [
        "他",
        "她",
        "回他",
        "回她",
        "跟进他",
        "跟进她",
        "那个人"
    ]

    private static let commitmentPointerTokens = [
        "这个承诺",
        "这个跟进",
        "这个提醒",
        "这件事",
        "这个事情"
    ]

    private static func matchedProject(
        in userMessage: String,
        projects: [AXProjectEntry]
    ) -> AXProjectEntry? {
        guard !projects.isEmpty else { return nil }

        let foldedMessage = userMessage
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
        let normalizedMessage = normalizedLookupKey(userMessage)

        let scored: [(entry: AXProjectEntry, score: Int)] = projects.compactMap { project in
            var score = 0
            let displayName = project.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            let projectId = project.projectId.trimmingCharacters(in: .whitespacesAndNewlines)
            let foldedName = displayName
                .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
                .lowercased()
            let normalizedName = normalizedLookupKey(displayName)
            let normalizedProjectID = normalizedLookupKey(projectId)
            let projectIdPrefix = String(projectId.prefix(8)).lowercased()

            if isReliableMentionToken(displayName),
               !foldedName.isEmpty,
               foldedMessage.contains(foldedName) {
                score = max(score, 180)
            }
            if !projectId.isEmpty,
               foldedMessage.contains(projectId.lowercased()) {
                score = max(score, 170)
            }
            if !projectIdPrefix.isEmpty,
               (foldedMessage.contains("hex:\(projectIdPrefix)") ||
                    foldedMessage.contains("id:\(projectIdPrefix)")) {
                score = max(score, 165)
            }
            if isReliableMentionToken(displayName),
               !normalizedName.isEmpty,
               normalizedMessage.contains(normalizedName) {
                score = max(score, 160)
            }
            if !normalizedProjectID.isEmpty,
               normalizedMessage.contains(normalizedProjectID) {
                score = max(score, 150)
            }

            guard score > 0 else { return nil }
            return (project, score)
        }
        .sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            if lhs.entry.lastOpenedAt != rhs.entry.lastOpenedAt { return lhs.entry.lastOpenedAt > rhs.entry.lastOpenedAt }
            return lhs.entry.displayName.localizedCaseInsensitiveCompare(rhs.entry.displayName) == .orderedAscending
        }

        guard let best = scored.first else { return nil }
        if scored.count == 1 {
            return best.entry
        }
        let second = scored[1]
        if best.score - second.score >= 20 {
            return best.entry
        }
        return nil
    }

    private static func matchedPerson(
        in userMessage: String,
        personalMemory: SupervisorPersonalMemorySnapshot,
        crossLinks: SupervisorCrossLinkSnapshot
    ) -> String? {
        let foldedMessage = userMessage
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
        let normalizedMessage = normalizedLookupKey(userMessage)

        let candidates = Array(
            Set(
                (
                    personalMemory.normalized().items
                        .filter(\.isActiveLike)
                        .map(\.personName)
                    +
                    crossLinks.normalized().items
                        .filter(\.isActiveLike)
                        .map(\.personName)
                )
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            )
        )

        let scored = candidates.compactMap { personName -> (String, Int)? in
            let folded = personName
                .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
                .lowercased()
            let normalized = normalizedLookupKey(personName)
            var score = 0
            if isReliableMentionToken(personName), !folded.isEmpty, foldedMessage.contains(folded) {
                score = max(score, 180)
            }
            if isReliableMentionToken(personName), !normalized.isEmpty, normalizedMessage.contains(normalized) {
                score = max(score, 160)
            }
            guard score > 0 else { return nil }
            return (personName, score)
        }
        .sorted { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
            return lhs.0.localizedCaseInsensitiveCompare(rhs.0) == .orderedAscending
        }

        guard let best = scored.first else { return nil }
        if scored.count == 1 {
            return best.0
        }
        let second = scored[1]
        return best.1 - second.1 >= 20 ? best.0 : nil
    }

    private static func matchedCommitment(
        in userMessage: String,
        personalMemory: SupervisorPersonalMemorySnapshot
    ) -> SupervisorPersonalMemoryRecord? {
        let normalizedMessage = normalizedLookupKey(userMessage)
        guard !normalizedMessage.isEmpty else { return nil }

        let scored = personalMemory.normalized().items.compactMap { record -> (SupervisorPersonalMemoryRecord, Int)? in
            guard record.isActiveLike,
                  record.category == .commitment || record.category == .recurringObligation else {
                return nil
            }
            let normalizedTitle = normalizedLookupKey(record.title)
            guard normalizedTitle.count >= 6, normalizedMessage.contains(normalizedTitle) else {
                return nil
            }
            return (record, normalizedTitle.count)
        }
        .sorted { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
            return lhs.0.updatedAtMs > rhs.0.updatedAtMs
        }

        return scored.first?.0
    }

    private static func pointerProject(
        currentProjectId: String?,
        projects: [AXProjectEntry],
        enabled: Bool
    ) -> AXProjectEntry? {
        guard enabled,
              let currentProjectId,
              !currentProjectId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return projects.first { $0.projectId == currentProjectId }
    }

    private static func pointerPerson(
        currentPersonName: String?,
        enabled: Bool
    ) -> String? {
        guard enabled,
              let currentPersonName else { return nil }
        let trimmed = currentPersonName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func pointerCommitment(
        currentCommitmentId: String?,
        personalMemory: SupervisorPersonalMemorySnapshot,
        enabled: Bool
    ) -> SupervisorPersonalMemoryRecord? {
        guard enabled,
              let currentCommitmentId,
              let record = personalMemory.item(for: currentCommitmentId),
              record.isActiveLike,
              record.category == .commitment || record.category == .recurringObligation else {
            return nil
        }
        return record
    }

    private static func projectPointerTriggered(
        normalized: String,
        currentProjectId: String?
    ) -> Bool {
        guard let currentProjectId,
              !currentProjectId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        return containsAny(normalized, projectPointerTokens)
    }

    private static func personPointerTriggered(
        normalized: String,
        currentPersonName: String?
    ) -> Bool {
        guard let currentPersonName,
              !currentPersonName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        return containsAny(normalized, personPointerTokens)
    }

    private static func commitmentPointerTriggered(
        normalized: String,
        currentCommitmentId: String?
    ) -> Bool {
        guard let currentCommitmentId,
              !currentCommitmentId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        return containsAny(normalized, commitmentPointerTokens)
    }

    private static func resolvedProjectMemoryBindingStrength(
        hasProjectFocus: Bool,
        projectTruthIntent: Bool
    ) -> SupervisorProjectMemoryBindingStrength {
        guard hasProjectFocus else { return .none }
        return projectTruthIntent ? .strong : .weak
    }

    private static func projectMemoryBindingReason(
        strength: SupervisorProjectMemoryBindingStrength
    ) -> String? {
        switch strength {
        case .none:
            return nil
        case .weak:
            return "project_reference_without_truth_need"
        case .strong:
            return "project_truth_required"
        }
    }

    private static func containsAny(_ text: String, _ needles: [String]) -> Bool {
        needles.contains { text.contains($0) }
    }

    private static func normalizedContainsAny(_ normalized: String, _ needles: [String]) -> Bool {
        needles.contains { needle in
            normalized.contains(normalizedLookupKey(needle))
        }
    }

    private static func normalizedLookupKey(_ text: String) -> String {
        let folded = text
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let scalars = folded.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
        return String(String.UnicodeScalarView(scalars))
    }

    private static func isReliableMentionToken(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let normalized = normalizedLookupKey(trimmed)
        if normalized.count >= 4 {
            return true
        }
        let hasNonASCII = trimmed.unicodeScalars.contains { !$0.isASCII }
        return hasNonASCII && trimmed.count >= 2
    }
}
