import Foundation

extension SupervisorManager {
    func assignModelToProject(projectRef: String, role: AXRole, modelId: String) -> ModelAssignmentResult {
        let normalizedRef = sanitizeProjectReference(projectRef)
        guard let appModel = appModel else {
            let message = "❌ 分配失败：Supervisor 未初始化（app_model_unavailable）"
            addSystemMessage(message)
            _ = appendActionLedger(
                action: "assign_model",
                targetRef: normalizedRef,
                projectId: nil,
                projectName: nil,
                role: role.rawValue,
                modelId: modelId,
                status: "failed",
                reasonCode: "app_model_unavailable",
                detail: "AppModel is nil",
                verifiedAt: nil
            )
            return ModelAssignmentResult(ok: false, reasonCode: "app_model_unavailable", message: message)
        }

        if let blocked = interactiveRoutingAssignmentBlock(modelId: modelId) {
            let message = "❌ 分配失败：\(blocked)"
            addSystemMessage(message)
            _ = appendActionLedger(
                action: "assign_model",
                targetRef: normalizedRef,
                projectId: nil,
                projectName: nil,
                role: role.rawValue,
                modelId: modelId,
                status: "failed",
                reasonCode: "retrieval_only_model_not_assignable",
                detail: blocked,
                verifiedAt: nil
            )
            return ModelAssignmentResult(
                ok: false,
                reasonCode: "retrieval_only_model_not_assignable",
                message: message
            )
        }

        let resolved = resolveProjectReference(normalizedRef, in: knownProjects())
        switch resolved {
        case .notFound:
            let hints = allProjects().prefix(4).map { $0.displayName }.joined(separator: "、")
            let suffix = hints.isEmpty ? "" : "。可用项目：\(hints)"
            let message = "❌ 找不到项目引用：\(normalizedRef) (project_not_found)\(suffix)"
            addSystemMessage(message)
            _ = appendActionLedger(
                action: "assign_model",
                targetRef: normalizedRef,
                projectId: nil,
                projectName: nil,
                role: role.rawValue,
                modelId: modelId,
                status: "failed",
                reasonCode: "project_not_found",
                detail: "No project matched for reference",
                verifiedAt: nil
            )
            return ModelAssignmentResult(ok: false, reasonCode: "project_not_found", message: message)

        case .ambiguous(let candidates):
            let list = candidates.prefix(4).map { "\($0.displayName)(\($0.projectId))" }.joined(separator: "、")
            let message = "⚠️ 项目引用不唯一：\(normalizedRef) (project_ambiguous)。候选：\(list)"
            addSystemMessage(message)
            _ = appendActionLedger(
                action: "assign_model",
                targetRef: normalizedRef,
                projectId: nil,
                projectName: nil,
                role: role.rawValue,
                modelId: modelId,
                status: "failed",
                reasonCode: "project_ambiguous",
                detail: "Candidates: \(list)",
                verifiedAt: nil
            )
            return ModelAssignmentResult(ok: false, reasonCode: "project_ambiguous", message: message)

        case .matched(let project):
            guard let ctx = appModel.projectContext(for: project.projectId) else {
                let message = "❌ 项目上下文不可用：\(project.displayName) (project_context_missing)"
                addProjectScopedSystemMessageIfVisible(message, project: project)
                _ = appendActionLedger(
                    action: "assign_model",
                    targetRef: normalizedRef,
                    projectId: project.projectId,
                    projectName: project.displayName,
                    role: role.rawValue,
                    modelId: modelId,
                    status: "failed",
                    reasonCode: "project_context_missing",
                    detail: "Project context lookup failed",
                    verifiedAt: nil
                )
                return ModelAssignmentResult(ok: false, reasonCode: "project_context_missing", message: message)
            }

            guard var cfg = try? AXProjectStore.loadOrCreateConfig(for: ctx) else {
                let message = "❌ 无法加载项目配置：\(project.displayName) (config_load_failed)"
                addProjectScopedSystemMessageIfVisible(message, project: project)
                _ = appendActionLedger(
                    action: "assign_model",
                    targetRef: normalizedRef,
                    projectId: project.projectId,
                    projectName: project.displayName,
                    role: role.rawValue,
                    modelId: modelId,
                    status: "failed",
                    reasonCode: "config_load_failed",
                    detail: "Load config failed",
                    verifiedAt: nil
                )
                return ModelAssignmentResult(ok: false, reasonCode: "config_load_failed", message: message)
            }

            let expectedModelId = normalizedModelId(modelId)
            cfg.setModelOverride(role: role, modelId: expectedModelId)

            do {
                try AXProjectStore.saveConfig(cfg, for: ctx)
            } catch {
                let message = "❌ 保存配置失败：\(project.displayName) (config_save_failed: \(error.localizedDescription))"
                addProjectScopedSystemMessageIfVisible(message, project: project)
                _ = appendActionLedger(
                    action: "assign_model",
                    targetRef: normalizedRef,
                    projectId: project.projectId,
                    projectName: project.displayName,
                    role: role.rawValue,
                    modelId: modelId,
                    status: "failed",
                    reasonCode: "config_save_failed",
                    detail: error.localizedDescription,
                    verifiedAt: nil
                )
                return ModelAssignmentResult(ok: false, reasonCode: "config_save_failed", message: message)
            }

            guard let verify = try? AXProjectStore.loadOrCreateConfig(for: ctx) else {
                let message = "❌ 写入后复检失败：\(project.displayName) (verify_load_failed)"
                addProjectScopedSystemMessageIfVisible(message, project: project)
                _ = appendActionLedger(
                    action: "assign_model",
                    targetRef: normalizedRef,
                    projectId: project.projectId,
                    projectName: project.displayName,
                    role: role.rawValue,
                    modelId: modelId,
                    status: "failed",
                    reasonCode: "verify_load_failed",
                    detail: "Failed to reload config for verification",
                    verifiedAt: nil
                )
                return ModelAssignmentResult(ok: false, reasonCode: "verify_load_failed", message: message)
            }

            let actualModelId = verify.modelOverride(for: role)
            guard actualModelId == expectedModelId else {
                let expected = expectedModelId ?? "auto"
                let actual = actualModelId ?? "auto"
                let message = "❌ 复检不一致：\(project.displayName) (verify_mismatch, expected=\(expected), actual=\(actual))"
                addProjectScopedSystemMessageIfVisible(message, project: project)
                _ = appendActionLedger(
                    action: "assign_model",
                    targetRef: normalizedRef,
                    projectId: project.projectId,
                    projectName: project.displayName,
                    role: role.rawValue,
                    modelId: modelId,
                    status: "failed",
                    reasonCode: "verify_mismatch",
                    detail: "expected=\(expected), actual=\(actual)",
                    verifiedAt: nil
                )
                return ModelAssignmentResult(ok: false, reasonCode: "verify_mismatch", message: message)
            }

            let label = expectedModelId ?? "auto"
            let message = "✅ 已为项目 \(project.displayName) 设置 \(role.displayName) 模型：\(label) (id: \(project.projectId))"
            addProjectScopedSystemMessageIfVisible(message, project: project)
            _ = appendActionLedger(
                action: "assign_model",
                targetRef: normalizedRef,
                projectId: project.projectId,
                projectName: project.displayName,
                role: role.rawValue,
                modelId: label,
                status: "ok",
                reasonCode: "ok",
                detail: "Model assignment verified",
                verifiedAt: Date().timeIntervalSince1970
            )
            return ModelAssignmentResult(ok: true, reasonCode: "ok", message: message)
        }
    }

    func assignModelToAllProjects(role: AXRole, modelId: String) -> ModelAssignmentResult {
        guard let appModel = appModel else {
            let message = "❌ 批量分配失败：Supervisor 未初始化（app_model_unavailable）"
            addSystemMessage(message)
            _ = appendActionLedger(
                action: "assign_model_all",
                targetRef: "*",
                projectId: nil,
                projectName: nil,
                role: role.rawValue,
                modelId: modelId,
                status: "failed",
                reasonCode: "app_model_unavailable",
                detail: "AppModel is nil",
                verifiedAt: nil
            )
            return ModelAssignmentResult(ok: false, reasonCode: "app_model_unavailable", message: message)
        }

        if let blocked = interactiveRoutingAssignmentBlock(modelId: modelId) {
            let message = "❌ 批量分配失败：\(blocked)"
            addSystemMessage(message)
            _ = appendActionLedger(
                action: "assign_model_all",
                targetRef: "*",
                projectId: nil,
                projectName: nil,
                role: role.rawValue,
                modelId: modelId,
                status: "failed",
                reasonCode: "retrieval_only_model_not_assignable",
                detail: blocked,
                verifiedAt: nil
            )
            return ModelAssignmentResult(
                ok: false,
                reasonCode: "retrieval_only_model_not_assignable",
                message: message
            )
        }

        let projects = allProjects()
        if projects.isEmpty {
            let message = "⚠️ 当前没有可分配的项目"
            addSystemMessage(message)
            _ = appendActionLedger(
                action: "assign_model_all",
                targetRef: "*",
                projectId: nil,
                projectName: nil,
                role: role.rawValue,
                modelId: modelId,
                status: "failed",
                reasonCode: "no_projects",
                detail: "No projects in registry",
                verifiedAt: nil
            )
            return ModelAssignmentResult(ok: false, reasonCode: "no_projects", message: message)
        }

        let expectedModelId = normalizedModelId(modelId)
        let label = expectedModelId ?? "auto"
        var success = 0
        var failed: [String] = []

        for project in projects {
            guard let ctx = appModel.projectContext(for: project.projectId) else {
                failed.append("\(project.displayName)(project_context_missing)")
                continue
            }
            guard var cfg = try? AXProjectStore.loadOrCreateConfig(for: ctx) else {
                failed.append("\(project.displayName)(config_load_failed)")
                continue
            }
            cfg.setModelOverride(role: role, modelId: expectedModelId)
            do {
                try AXProjectStore.saveConfig(cfg, for: ctx)
                guard let verify = try? AXProjectStore.loadOrCreateConfig(for: ctx),
                      verify.modelOverride(for: role) == expectedModelId else {
                    failed.append("\(project.displayName)(verify_mismatch)")
                    continue
                }
                success += 1
            } catch {
                failed.append("\(project.displayName)(config_save_failed)")
            }
        }

        let result: ModelAssignmentResult
        if failed.isEmpty {
            let message = "✅ 已为全部 \(success) 个项目设置 \(role.displayName) 模型：\(label)"
            result = ModelAssignmentResult(ok: true, reasonCode: "ok", message: message)
        } else if success > 0 {
            let message = "⚠️ 批量分配部分成功：成功 \(success) 个，失败 \(failed.count) 个：\(failed.joined(separator: ", "))"
            result = ModelAssignmentResult(ok: false, reasonCode: "partial_failure", message: message)
        } else {
            let message = "❌ 批量分配失败：\(failed.joined(separator: ", "))"
            result = ModelAssignmentResult(ok: false, reasonCode: "all_failed", message: message)
        }

        addSystemMessage(result.message)
        _ = appendActionLedger(
            action: "assign_model_all",
            targetRef: "*",
            projectId: nil,
            projectName: nil,
            role: role.rawValue,
            modelId: label,
            status: result.ok ? "ok" : "failed",
            reasonCode: result.reasonCode,
            detail: failed.isEmpty ? "Applied to all projects" : failed.joined(separator: "; "),
            verifiedAt: Date().timeIntervalSince1970
        )
        return result
    }

    private func normalizedModelId(_ modelId: String) -> String? {
        let cleaned = modelId.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty { return nil }
        if cleaned.lowercased() == "auto" { return nil }
        return cleaned
    }

    private func interactiveRoutingAssignmentBlock(modelId: String) -> String? {
        guard let normalized = normalizedModelId(modelId) else { return nil }
        let snapshot = ModelStateSnapshot(
            models: supervisorModelInventory(),
            updatedAt: appModel?.modelsState.updatedAt ?? Date().timeIntervalSince1970
        )
        guard let assessment = HubModelSelectionAdvisor.assess(
            requestedId: normalized,
            snapshot: snapshot
        ),
        let blocked = assessment.nonInteractiveExactMatch else {
            return nil
        }

        if let fallback = assessment.loadedCandidates.first?.id.trimmingCharacters(in: .whitespacesAndNewlines),
           !fallback.isEmpty {
            let reason = blocked.interactiveRoutingDisabledReason ?? ""
            return "`\(blocked.id)` 是非对话模型，不能作为角色对话模型分配。\(reason) 可先改用 `\(fallback)`。"
        }
        return "`\(blocked.id)` 是非对话模型，不能作为角色对话模型分配。\(blocked.interactiveRoutingDisabledReason ?? "")"
    }

    func parseAssignCommand(tag: String, payload: String) -> (command: ParsedAssignCommand?, error: String?) {
        let trimmedPayload = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        if tag == "ASSIGN_MODEL_ALL" {
            let parts = trimmedPayload.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            guard parts.count == 2 else {
                return (nil, "应为 2 段：角色|模型ID")
            }
            guard let role = AXRole.resolveModelAssignmentToken(parts[0]) else {
                return (nil, "未知角色：\(parts[0])")
            }
            return (ParsedAssignCommand(projectRef: nil, role: role, modelId: parts[1], tag: tag), nil)
        }

        if tag == "ASSIGN_MODEL" {
            let parts = trimmedPayload.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false)
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            guard parts.count == 3 else {
                return (nil, "应为 3 段：项目引用|角色|模型ID")
            }
            guard let role = AXRole.resolveModelAssignmentToken(parts[1]) else {
                return (nil, "未知角色：\(parts[1])")
            }
            let ref = sanitizeProjectReference(parts[0])
            let normalizedRef: String? = (ref == "*" || ref.lowercased() == "all") ? nil : ref
            return (ParsedAssignCommand(projectRef: normalizedRef, role: role, modelId: parts[2], tag: tag), nil)
        }

        return (nil, "unsupported tag: \(tag)")
    }

    func sanitizeProjectReference(_ raw: String) -> String {
        var out = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if out.isEmpty { return out }

        let wrappers: [(String, String)] = [
            ("**", "**"),
            ("《", "》"),
            ("[", "]"), ("【", "】"),
            ("(", ")"), ("（", "）"),
            ("“", "”"), ("\"", "\""),
            ("'", "'"), ("`", "`")
        ]
        var changed = true
        while changed {
            changed = false
            for (head, tail) in wrappers {
                if out.hasPrefix(head), out.hasSuffix(tail), out.count > (head.count + tail.count) {
                    out.removeFirst(head.count)
                    out.removeLast(tail.count)
                    out = out.trimmingCharacters(in: .whitespacesAndNewlines)
                    changed = true
                }
            }
        }

        let lower = out.lowercased()
        let prefixes = [
            "project_ref:", "project_ref：",
            "project ref:", "project ref：",
            "project_id:", "project_id：",
            "project id:", "project id：",
            "项目ref:", "项目ref：",
            "项目引用:", "项目引用：",
            "项目id:", "项目id：",
            "项目:", "项目："
        ]
        for prefix in prefixes where lower.hasPrefix(prefix) {
            out = String(out.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            break
        }
        return out
    }

    private func syntheticProjectIdentifierKey(_ projectRef: String) -> String? {
        let trimmed = projectRef.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let lowered = trimmed.lowercased()
        for prefix in ["hex:", "id:"] where lowered.hasPrefix(prefix) {
            let suffix = String(trimmed.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            let key = normalizedLookupKey(suffix)
            if key.count >= 4 {
                return key
            }
        }
        return nil
    }

    func supervisorTriggerContextValue(_ key: String, userMessage: String?) -> String? {
        guard let userMessage else { return nil }
        let normalizedKey = key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedKey.isEmpty else { return nil }

        for rawLine in userMessage.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            let prefix = "\(normalizedKey)="
            guard line.lowercased().hasPrefix(prefix) else { continue }
            let value = String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        }
        return nil
    }

    func supervisorFallbackProjectReference(
        userMessage: String?,
        triggerSource: SupervisorCommandTriggerSource
    ) -> String? {
        guard triggerSource != .userTurn else { return nil }
        if let projectId = supervisorTriggerContextValue("project_id", userMessage: userMessage) {
            let sanitized = sanitizeProjectReference(projectId)
            if !sanitized.isEmpty {
                return sanitized
            }
        }
        if let projectRef = supervisorTriggerContextValue("project_ref", userMessage: userMessage) {
            let sanitized = sanitizeProjectReference(projectRef)
            if !sanitized.isEmpty {
                return sanitized
            }
        }
        return nil
    }

    func resolvedSupervisorProjectLookup(
        projectRef: String?,
        projects: [AXProjectEntry],
        resolutionProjects: [AXProjectEntry]? = nil,
        userMessage: String?,
        triggerSource: SupervisorCommandTriggerSource
    ) -> (requestedRef: String, resolution: ProjectReferenceResolution?, projectScopeMissing: Bool) {
        let rawProjectRef = sanitizeProjectReference(projectRef ?? "")
        let fallbackRef = supervisorFallbackProjectReference(
            userMessage: userMessage,
            triggerSource: triggerSource
        )
        let lookupProjects = resolutionProjects ?? projects

        let primaryRef: String = {
            if !rawProjectRef.isEmpty {
                return rawProjectRef
            }
            if let defaultRef = defaultProjectReferenceForDirectAssignment(projects: projects) {
                return defaultRef
            }
            return ""
        }()

        if !primaryRef.isEmpty {
            let primaryResolution = resolveProjectReference(primaryRef, in: lookupProjects)
            if case .matched = primaryResolution {
                return (primaryRef, primaryResolution, false)
            }
            if let fallbackRef,
               !fallbackRef.isEmpty,
               fallbackRef.compare(primaryRef, options: .caseInsensitive) != .orderedSame {
                let fallbackResolution = resolveProjectReference(fallbackRef, in: lookupProjects)
                if case .matched = fallbackResolution {
                    return (fallbackRef, fallbackResolution, false)
                }
            }
            return (primaryRef, primaryResolution, false)
        }

        if let fallbackRef, !fallbackRef.isEmpty {
            return (fallbackRef, resolveProjectReference(fallbackRef, in: lookupProjects), false)
        }

        return ("", nil, true)
    }

    func resolveProjectReference(_ projectRef: String) -> ProjectReferenceResolution {
        resolveProjectReference(projectRef, in: allProjects())
    }

    func resolveProjectReference(
        _ projectRef: String,
        in projects: [AXProjectEntry]
    ) -> ProjectReferenceResolution {
        guard !projects.isEmpty else { return .notFound }

        if let exactId = projects.first(where: { $0.projectId.compare(projectRef, options: .caseInsensitive) == .orderedSame }) {
            return .matched(exactId)
        }
        if let exactName = projects.first(where: { $0.displayName.compare(projectRef, options: .caseInsensitive) == .orderedSame }) {
            return .matched(exactName)
        }

        let key = normalizedLookupKey(projectRef)
        let syntheticIDKey = syntheticProjectIdentifierKey(projectRef)
        guard !key.isEmpty || syntheticIDKey != nil else { return .notFound }

        let scored: [(entry: AXProjectEntry, score: Int)] = projects.compactMap { entry in
            let nameKey = normalizedLookupKey(entry.displayName)
            let idKey = normalizedLookupKey(entry.projectId)
            var score = 0
            if let syntheticIDKey {
                if syntheticIDKey == idKey { score = max(score, 130) }
                if !idKey.isEmpty && idKey.hasPrefix(syntheticIDKey) { score = max(score, 125) }
            }
            if key == idKey { score = max(score, 120) }
            if key == nameKey { score = max(score, 110) }
            if !nameKey.isEmpty && nameKey.hasPrefix(key) { score = max(score, 95) }
            if !nameKey.isEmpty && nameKey.contains(key) { score = max(score, 85) }
            if !idKey.isEmpty && idKey.hasPrefix(key) { score = max(score, 80) }
            if !idKey.isEmpty && idKey.contains(key) { score = max(score, 70) }
            if score == 0 { return nil }
            return (entry, score)
        }
        .sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            if lhs.entry.lastOpenedAt != rhs.entry.lastOpenedAt { return lhs.entry.lastOpenedAt > rhs.entry.lastOpenedAt }
            return lhs.entry.displayName.localizedCaseInsensitiveCompare(rhs.entry.displayName) == .orderedAscending
        }

        guard let best = scored.first else { return .notFound }
        if scored.count == 1 {
            return .matched(best.entry)
        }
        let second = scored[1]
        if best.score - second.score >= 20 {
            return .matched(best.entry)
        }
        return .ambiguous(Array(scored.prefix(4).map { $0.entry }))
    }

    func normalizedLookupKey(_ text: String) -> String {
        let folded = text
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let scalars = folded.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
        return String(String.UnicodeScalarView(scalars))
    }
}
