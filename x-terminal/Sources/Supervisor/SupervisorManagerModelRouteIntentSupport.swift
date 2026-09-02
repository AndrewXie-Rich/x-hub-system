import Foundation

extension SupervisorManager {
    func resolvedRouteIntentProject(
        for userMessage: String,
        projects: [AXProjectEntry]
    ) -> AXProjectEntry? {
        let explicitRef = extractProjectReferenceForDirectAssignment(userMessage, projects: projects)
        let fallbackRef = defaultProjectReferenceForDirectAssignment(projects: projects)

        for candidate in [explicitRef, fallbackRef] {
            guard let candidate, !candidate.isEmpty else { continue }
            if case .matched(let project) = resolveProjectReference(candidate, in: projects) {
                return project
            }
        }
        return nil
    }

    func loadRouteIntentProjectConfig(for project: AXProjectEntry) -> AXProjectConfig? {
        let root = URL(fileURLWithPath: project.rootPath, isDirectory: true)
        let ctx = AXProjectContext(root: root)
        return try? AXProjectStore.loadOrCreateConfig(for: ctx)
    }

    func resolvedSupervisorModelRouteContext(
        userMessage: String,
        projects: [AXProjectEntry]
    ) -> SupervisorModelRouteContext? {
        let trimmed = userMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let routeProject = resolvedRouteIntentProject(for: trimmed, projects: projects)
        let projectConfig = routeProject.flatMap { loadRouteIntentProjectConfig(for: $0) }
        let routeDecision = inferredSupervisorRouteDecision(
            for: trimmed,
            project: routeProject,
            projectConfig: projectConfig
        )
        return SupervisorModelRouteContext(
            projectName: routeProject?.displayName,
            decision: routeDecision
        )
    }

    func inferredSupervisorRouteDecision(
        for userMessage: String,
        project: AXProjectEntry?,
        projectConfig: AXProjectConfig?
    ) -> SupervisorModelRouteDecision {
        let normalized = normalizedSupervisorIntentText(userMessage)
        let input = SupervisorTaskRoleClassifier.Input(
            taskTags: inferredSupervisorRouteTaskTags(from: normalized),
            risk: inferredSupervisorRouteRisk(from: normalized),
            sideEffect: inferredSupervisorRouteSideEffect(from: normalized),
            codeExecution: inferredSupervisorRouteCodeExecution(from: normalized)
        )
        let projectID = project?.projectId ?? "supervisor"
        return SupervisorModelRoutePolicy.default(projectID: projectID)
            .routeDecision(for: input, projectConfig: projectConfig)
    }

    func inferredSupervisorRouteTaskTags(from normalized: String) -> [String] {
        var tags: [String] = []

        func appendTag(_ tag: String) {
            guard !tag.isEmpty, !tags.contains(tag) else { return }
            tags.append(tag)
        }

        if containsAny(normalized, ["范围", "scope", "freeze", "冻结", "规格", "spec", "里程碑", "milestone"]) {
            appendTag("scope_freeze")
        }
        if containsAny(normalized, ["goal", "mvp", "non goal", "non-goal", "技术栈", "tech stack", "模块", "规格胶囊", "spec capsule"]) {
            appendTag("spec_capsule")
        }
        if containsAny(normalized, ["卡住", "卡在哪", "阻塞", "blocked", "决策", "decision", "选型"]) {
            appendTag("decision_blocker")
        }
        if containsAny(normalized, ["写代码", "代码", "编码", "编程", "实现", "开发", "feature", "patch"]) {
            appendTag("codegen")
        }
        if containsAny(normalized, ["重构", "重写", "refactor", "整理代码"]) {
            appendTag("refactor")
        }
        if containsAny(normalized, ["修复", "fix", "bug", "runtime", "编译错误", "build error", "报错"]) {
            appendTag("runtime_fix")
        }
        if containsAny(normalized, ["review", "审查", "审阅", "评审", "检查代码"]) {
            appendTag("review")
        }
        if containsAny(normalized, ["回归", "regression", "qa", "测试一下", "验收"]) {
            appendTag("regression")
        }
        if containsAny(normalized, ["gate", "checklist", "收口", "门禁"]) {
            appendTag("gate_review")
        }
        if containsAny(normalized, ["文档", "docs", "readme", "说明文档"]) {
            appendTag("docs")
        }
        if containsAny(normalized, ["release notes", "release note", "发版说明", "发布说明", "更新日志", "changelog"]) {
            appendTag("release_notes")
        }
        if containsAny(normalized, ["spec freeze writeup", "scope note", "冻结说明", "口径说明"]) {
            appendTag("spec_freeze_writeup")
        }
        if containsAny(normalized, ["runbook", "操作手册", "故障手册"]) {
            appendTag("runbook")
        }
        if containsAny(normalized, ["rollout", "上线", "部署", "发布到"]) {
            appendTag("rollout")
        }
        if containsAny(normalized, ["probe", "doctor", "诊断", "排查", "健康检查", "runtime probe"]) {
            appendTag("runtime_probe")
        }
        if containsAny(normalized, ["operator", "人工处理", "手工操作", "执行一下"]) {
            appendTag("operator_action")
        }

        if let explicitRole = firstExplicitRoleMention(in: normalized) {
            switch explicitRole {
            case .coder, .coarse, .refine:
                appendTag("codegen")
            case .reviewer:
                appendTag("review")
            case .advisor:
                appendTag("scope_freeze")
            case .supervisor:
                appendTag("operator_action")
            }
        }

        return tags
    }

    func inferredSupervisorRouteRisk(from normalized: String) -> SupervisorTaskRisk {
        if containsAny(normalized, ["delete", "删除", "wipe", "drop db", "销毁", "不可逆", "irreversible"]) {
            return .critical
        }
        if containsAny(normalized, ["授权", "grant", "权限", "安全", "security", "付费", "paid", "上线", "部署", "rollout", "production", "prod", "迁移", "connector", "联网"]) {
            return .high
        }
        if containsAny(normalized, ["review", "审查", "审阅", "回归", "regression", "qa", "probe", "doctor", "诊断"]) {
            return .medium
        }
        return .low
    }

    func inferredSupervisorRouteSideEffect(from normalized: String) -> SupervisorTaskSideEffect {
        if containsAny(normalized, ["delete", "删除", "wipe", "drop db", "销毁", "不可逆", "irreversible"]) {
            return .irreversible
        }
        if containsAny(normalized, ["上线", "部署", "rollout", "发布到", "connector", "联网", "browser", "web fetch"]) {
            return .externalWrite
        }
        if containsAny(normalized, ["probe", "doctor", "诊断", "排查", "日志", "log", "health", "审计", "audit"]) {
            return .externalRead
        }
        if containsAny(normalized, ["写代码", "代码", "编码", "编程", "实现", "开发", "修复", "fix", "bug", "重构", "refactor", "patch", "编译"]) {
            return .localMutation
        }
        return .none
    }

    func inferredSupervisorRouteCodeExecution(from normalized: String) -> Bool {
        containsAny(
            normalized,
            ["写代码", "代码", "编码", "编程", "实现", "开发", "修复", "fix", "bug", "重构", "refactor", "patch", "编译", "build"]
        )
    }

    func currentSupervisorTaskIntentSummary(
        for context: SupervisorModelRouteContext
    ) -> String {
        let decision = context.decision
        let preferredClasses = decision.preferredModelClasses.map(\.rawValue).joined(separator: ", ")
        let matchedSignals = decision.explainability.matchedSignals.isEmpty
            ? ["fail_closed_default:\(decision.role.rawValue)"]
            : decision.explainability.matchedSignals
        var parts = [
            "task-intent role=\(decision.role.rawValue)",
            "signals=[\(matchedSignals.joined(separator: ", "))]",
            "preferred_classes=[\(preferredClasses)]",
            "grant=\(decision.grantPolicy.rawValue)",
            "hub_gate=\(decision.hubPolicyRequired ? "required" : "not_required")",
            "why_role=\(capped(decision.explainability.whyRole, maxChars: 120))",
            "why_classes=\(capped(decision.explainability.whyPreferredModelClasses, maxChars: 140))"
        ]

        let projectName = context.projectName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !projectName.isEmpty {
            parts.append("project=\(projectName)")
        }
        if !decision.projectModelHints.isEmpty {
            parts.append("project_hints=[\(decision.projectModelHints.joined(separator: ", "))]")
        }
        parts.append("hub_resolves_concrete_model=true")
        return parts.joined(separator: "; ")
    }

    func parseDirectModelAssignmentIntent(
        _ userMessage: String,
        projects: [AXProjectEntry],
        role: AXRole,
        usedDefaultRole: Bool,
        resolvedModelId: String,
        sourceModelToken: String
    ) -> DirectModelAssignmentIntent? {
        let normalized = normalizedSupervisorIntentText(userMessage)
        let appliesToAllProjects = normalized.contains("所有项目") || normalized.contains("全部项目")

        let projectRef = appliesToAllProjects
            ? nil
            : extractProjectReferenceForDirectAssignment(userMessage, projects: projects)
        return DirectModelAssignmentIntent(
            appliesToAllProjects: appliesToAllProjects,
            projectRef: projectRef,
            role: role,
            usedDefaultRole: usedDefaultRole,
            modelId: resolvedModelId,
            sourceModelToken: sourceModelToken
        )
    }

    func firstExplicitRoleMention(in normalized: String) -> AXRole? {
        let aliases: [(String, AXRole)] = [
            ("reviewer", .reviewer), ("advisor", .advisor), ("coarse", .coarse), ("refine", .refine), ("coder", .coder),
            ("开发者", .coder), ("开发", .coder), ("编程", .coder), ("编码", .coder),
            ("粗编", .coarse), ("粗稿", .coarse), ("初稿", .coarse),
            ("精编", .refine), ("精修", .refine), ("润色", .refine),
            ("审查", .reviewer), ("审阅", .reviewer), ("评审", .reviewer),
            ("顾问", .advisor)
        ]
        for (token, role) in aliases.sorted(by: { $0.0.count > $1.0.count }) where normalized.contains(token) {
            return role
        }
        return nil
    }

    func extractRequestedModelToken(from userMessage: String) -> String? {
        let patterns = [
            #"(?:改成|改为|换成|换为|换到|切到|切换到|设为|设置为|指定为|调整为)\s*[“"']?([^“"'\n。！!？?]+)"#,
            #"(?:用|使用)\s*[“"']?([^“"'\n。！!？?]+)"#
        ]
        for pattern in patterns {
            if let captured = firstRegexCapture(in: userMessage, pattern: pattern) {
                let cleaned = sanitizeRequestedModelToken(captured)
                if !cleaned.isEmpty {
                    return cleaned
                }
            }
        }
        return nil
    }

    func sanitizeRequestedModelToken(_ raw: String) -> String {
        var out = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while out.hasPrefix("模型") || out.hasPrefix("model") || out.hasPrefix("为") {
            if out.hasPrefix("模型") {
                out.removeFirst("模型".count)
            } else if out.hasPrefix("model") {
                out.removeFirst("model".count)
            } else if out.hasPrefix("为") {
                out.removeFirst("为".count)
            }
            out = out.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let suffixes = ["吧", "一下", "试试", "看看", "谢谢"]
        for suffix in suffixes where out.hasSuffix(suffix) {
            out = String(out.dropLast(suffix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return out.trimmingCharacters(in: CharacterSet(charactersIn: "\"'“”‘’.,，。!！?？"))
    }

    func resolveRequestedModelToken(_ token: String) -> ModelTokenResolution {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = trimmed.lowercased()
        if ["auto", "default", "none", "clear", "自动"].contains(lowered) {
            return .auto
        }

        let inventory = supervisorModelInventory()
        guard !inventory.isEmpty else {
            if lowered.contains("/") || lowered.contains("gpt") || lowered.contains("claude") || lowered.contains("gemini") {
                return .resolved(trimmed)
            }
            return .inventoryUnavailable
        }

        let compactQuery = compactModelLookupKey(trimmed)
        let versionFragments = versionLikeFragments(in: trimmed.lowercased())
        let scored: [(model: HubModel, score: Int)] = inventory.compactMap { model in
            let idLower = model.id.lowercased()
            let nameLower = model.name.lowercased()
            let compactID = compactModelLookupKey(model.id)
            let compactName = compactModelLookupKey(model.name)
            var score = 0

            if idLower == lowered { score = max(score, 300) }
            if nameLower == lowered { score = max(score, 290) }
            if !compactQuery.isEmpty && compactID == compactQuery { score = max(score, 270) }
            if !compactQuery.isEmpty && compactName == compactQuery { score = max(score, 260) }
            if idLower.contains(lowered) { score = max(score, 230) }
            if nameLower.contains(lowered) { score = max(score, 220) }
            if !compactQuery.isEmpty && compactID.contains(compactQuery) { score = max(score, 210) }
            if !compactQuery.isEmpty && compactName.contains(compactQuery) { score = max(score, 200) }
            if versionFragments.contains(where: { fragment in
                idLower.contains(fragment) || nameLower.contains(fragment)
            }) {
                score = max(score, 240)
            }
            if score == 0 { return nil }
            return (model, score)
        }
        .sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            if lhs.model.state != rhs.model.state { return lhs.model.state == .loaded }
            return lhs.model.id.localizedCaseInsensitiveCompare(rhs.model.id) == .orderedAscending
        }

        guard let best = scored.first else { return .notFound }
        if scored.count == 1 {
            return .resolved(best.model.id)
        }
        let second = scored[1]
        if best.score - second.score >= 20 {
            return .resolved(best.model.id)
        }
        return .ambiguous(Array(scored.prefix(4).map(\.model)))
    }

    func compactModelLookupKey(_ text: String) -> String {
        text
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init)
            .joined()
    }

    func versionLikeFragments(in text: String) -> [String] {
        let pattern = #"[0-9]+(?:\.[0-9]+)+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, options: [], range: range).compactMap { match in
            guard let range = Range(match.range, in: text) else { return nil }
            return String(text[range])
        }
    }

    func extractProjectReferenceForDirectAssignment(
        _ userMessage: String,
        projects: [AXProjectEntry]
    ) -> String? {
        let normalized = normalizedSupervisorIntentText(userMessage)
        if normalized.contains("当前项目") || normalized.contains("这个项目") || normalized.contains("该项目") {
            return defaultProjectReferenceForDirectAssignment(projects: projects)
        }

        let patterns = [
            #"(?:把|给|将)\s*(.+?)(?:这个项目|该项目|项目)"#,
            #"(?:把|给|将)\s*(.+?)\s*的\s*(?:开发者|开发|coder|coarse|refine|reviewer|advisor|审查|审阅|评审|顾问|粗编|精修)?\s*模型"#
        ]
        for pattern in patterns {
            if let captured = firstRegexCapture(in: userMessage, pattern: pattern) {
                let cleaned = sanitizeDirectProjectHint(captured)
                if !cleaned.isEmpty {
                    return cleaned
                }
            }
        }
        return nil
    }

    func sanitizeDirectProjectHint(_ raw: String) -> String {
        var out = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefixes = ["把", "给", "将"]
        for prefix in prefixes where out.hasPrefix(prefix) {
            out.removeFirst(prefix.count)
            out = out.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let fillers = ["这个", "该", "当前", "一下"]
        for filler in fillers {
            out = out.replacingOccurrences(of: filler, with: "")
        }
        return sanitizeProjectReference(out)
    }

    func defaultProjectReferenceForDirectAssignment(projects: [AXProjectEntry]) -> String? {
        if let selectedProjectID = appModel?.selectedProjectId,
           selectedProjectID != AXProjectRegistry.globalHomeId,
           let selected = projects.first(where: { $0.projectId == selectedProjectID }) {
            return selected.displayName
        }
        if projects.count == 1 {
            return projects[0].displayName
        }
        return nil
    }

    func firstRegexCapture(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[captureRange])
    }

    func regexMatches(in text: String, pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, options: [], range: range).compactMap { match in
            guard let matchRange = Range(match.range, in: text) else { return nil }
            return String(text[matchRange])
        }
    }
}
