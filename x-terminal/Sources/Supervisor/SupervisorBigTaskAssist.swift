import Foundation

struct SupervisorBigTaskCandidate: Equatable {
    var goal: String
    var fingerprint: String
}

struct SupervisorBigTaskProjectBinding: Equatable {
    var projectID: String
    var projectName: String
}

struct SupervisorBigTaskSceneHint: Equatable {
    var template: AXProjectGovernanceTemplate
    var preferredSplitProfile: OneShotSplitProfile
    var participationMode: DeliveryParticipationMode
    var tokenBudgetClass: OneShotTokenBudgetClass
    var deliveryMode: OneShotDeliveryMode
    var reason: String

    var quickAccessLine: String {
        "默认 \(template.displayName) 场景，建 job + initial plan"
    }

    var promptBlock: String {
        """
scene_template: \(template.rawValue)
scene_template_label: \(template.displayName)
scene_template_mode_fit: \(template.selectableDescription)
scene_template_summary: \(template.shortDescription)
scene_template_reason: \(reason)
"""
    }
}

enum SupervisorBigTaskAssist {
    static func sceneHint(
        for candidate: SupervisorBigTaskCandidate,
        selectedProject: AXProjectEntry? = nil,
        selectedProjectTemplate: AXProjectGovernanceTemplatePreview? = nil
    ) -> SupervisorBigTaskSceneHint {
        let template: AXProjectGovernanceTemplate
        let reason: String

        if !isNewProjectCreationGoal(candidate.goal),
           let preferredTemplate = preferredTemplate(from: selectedProjectTemplate) {
            template = preferredTemplate
            let projectName = selectedProject?.displayName
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let label = (projectName?.isEmpty == false ? projectName : nil) ?? "当前项目"
            reason = "\(label) 已经有自己的治理场景；这次大任务 intake 先沿用它，再按需要单独微调 A-Tier / S-Tier / Heartbeat。"
        } else {
            template = inferredTemplate(for: candidate.goal)
            reason = inferredReason(for: template)
        }

        return SupervisorBigTaskSceneHint(
            template: template,
            preferredSplitProfile: preferredSplitProfile(for: template),
            participationMode: .guidedTouch,
            tokenBudgetClass: tokenBudgetClass(for: template),
            deliveryMode: deliveryMode(for: template),
            reason: reason
        )
    }

    static func projectBinding(
        for candidate: SupervisorBigTaskCandidate,
        selectedProject: AXProjectEntry?
    ) -> SupervisorBigTaskProjectBinding? {
        guard shouldBindSelectedProject(candidate: candidate, selectedProject: selectedProject) else {
            return nil
        }
        guard let selectedProject else { return nil }
        let projectID = selectedProject.projectId
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !projectID.isEmpty else { return nil }
        let displayName = selectedProject.displayName
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return SupervisorBigTaskProjectBinding(
            projectID: projectID,
            projectName: displayName.isEmpty ? projectID : displayName
        )
    }

    static func submission(
        for candidate: SupervisorBigTaskCandidate,
        selectedProject: AXProjectEntry? = nil,
        selectedProjectTemplate: AXProjectGovernanceTemplatePreview? = nil
    ) -> OneShotIntakeSubmission {
        let projectBinding = projectBinding(for: candidate, selectedProject: selectedProject)
        let sceneHint = sceneHint(
            for: candidate,
            selectedProject: selectedProject,
            selectedProjectTemplate: selectedProjectTemplate
        )
        let requestScope = projectBinding?.projectID ?? "unscoped"
        let requestID = oneShotDeterministicUUIDString(
            seed: "supervisor_big_task_request|\(requestScope)|\(candidate.fingerprint)"
        )
        let contextRefs = oneShotOrderedUniqueStrings(
            [
                "ui://supervisor/header_big_task",
                "audit://supervisor_big_task/\(requestID)"
            ] + boundProjectContextRefs(projectBinding)
        )
        return OneShotIntakeSubmission(
            projectID: projectBinding?.projectID,
            requestID: requestID,
            userGoal: candidate.goal,
            contextRefs: contextRefs,
            preferredSplitProfile: sceneHint.preferredSplitProfile,
            participationMode: sceneHint.participationMode,
            innovationLevel: .l2,
            tokenBudgetClass: sceneHint.tokenBudgetClass,
            deliveryMode: sceneHint.deliveryMode,
            allowAutoLaunch: false,
            requiresHumanAuthorizationTypes: [],
            auditRef: "supervisor_big_task_\(requestID)"
        )
    }

    static func detect(
        inputText: String,
        latestUserMessage: String?,
        dismissedFingerprint: String?
    ) -> SupervisorBigTaskCandidate? {
        let candidate = candidate(from: inputText)
            ?? candidate(from: latestUserMessage ?? "")
        guard let candidate else { return nil }
        if dismissedFingerprint == candidate.fingerprint {
            return nil
        }
        return candidate
    }

    static func candidate(from raw: String) -> SupervisorBigTaskCandidate? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 16, !trimmed.hasPrefix("/") else { return nil }
        guard !trimmed.contains("job + initial plan"),
              !trimmed.contains("建成一个大任务") else { return nil }

        let normalized = trimmed.lowercased()
        let taskKeywords = [
            "做", "开发", "构建", "实现", "设计", "重构", "建立", "搭建",
            "系统", "平台", "网站", "应用", "app", "agent", "workflow",
            "自动化", "机器人", "功能", "项目", "架构"
        ]
        guard taskKeywords.contains(where: { keyword in
            trimmed.contains(keyword) || normalized.contains(keyword)
        }) else {
            return nil
        }

        let intentSignals = ["帮我", "请", "需要", "想要", "希望", "做一个", "实现一个", "搭一个", "做个"]
        guard intentSignals.contains(where: { signal in
            trimmed.contains(signal) || normalized.contains(signal)
        }) || trimmed.count >= 28 else {
            return nil
        }

        let fingerprint = normalized
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return SupervisorBigTaskCandidate(goal: trimmed, fingerprint: fingerprint)
    }

    static func prompt(
        for candidate: SupervisorBigTaskCandidate,
        selectedProject: AXProjectEntry? = nil,
        selectedProjectTemplate: AXProjectGovernanceTemplatePreview? = nil,
        controlPlane: OneShotControlPlaneSnapshot? = nil
    ) -> String {
        let projectBinding = projectBinding(for: candidate, selectedProject: selectedProject)
        let boundProjectLines = promptBoundProjectLines(projectBinding)
        let sceneHint = sceneHint(
            for: candidate,
            selectedProject: selectedProject,
            selectedProjectTemplate: selectedProjectTemplate
        )
        if let controlPlane {
            let request = controlPlane.normalization.request
            let contextRefs = request.contextRefs.isEmpty
                ? "(none)"
                : request.contextRefs.joined(separator: ", ")
            return """
请基于下面已经预热好的大任务 intake，先给出 job + initial plan；如果还缺关键约束，只问我一个最关键的问题。

user_goal: \(request.userGoal)
request_id: \(request.requestID)
audit_ref: \(request.auditRef)
\(boundProjectLines)preferred_split_profile: \(request.preferredSplitProfile.rawValue)
delivery_mode: \(request.deliveryMode.rawValue)
participation_mode: \(request.participationMode.rawValue)
\(sceneHint.promptBlock)run_state: \(controlPlane.runState.state.rawValue)
next_target: \(controlPlane.runState.nextDirectedTarget)
top_blocker: \(controlPlane.runState.topBlocker)
context_refs: \(contextRefs)
"""
        }

        let boundProjectBlock: String
        if boundProjectLines.isEmpty {
            boundProjectBlock = ""
        } else {
            boundProjectBlock = boundProjectLines
        }

        return """
请把下面这件事建成一个大任务，并先给出 job + initial plan；如果还缺关键约束，只问我一个最关键的问题。

\(boundProjectBlock)\(sceneHint.promptBlock)\(candidate.goal)
"""
    }

    private static func boundProjectContextRefs(
        _ projectBinding: SupervisorBigTaskProjectBinding?
    ) -> [String] {
        guard let projectBinding else { return [] }
        return [
            "memory://canonical/project/\(projectBinding.projectID)",
            "memory://canonical/project/\(projectBinding.projectID)/spec_freeze"
        ]
    }

    private static func promptBoundProjectLines(
        _ projectBinding: SupervisorBigTaskProjectBinding?
    ) -> String {
        guard let projectBinding else { return "" }
        return """
bound_project_name: \(projectBinding.projectName)
bound_project_id: \(projectBinding.projectID)
"""
    }

    private static func shouldBindSelectedProject(
        candidate: SupervisorBigTaskCandidate,
        selectedProject: AXProjectEntry?
    ) -> Bool {
        guard selectedProject != nil else { return false }
        return !isNewProjectCreationGoal(candidate.goal)
    }

    private static func preferredTemplate(
        from preview: AXProjectGovernanceTemplatePreview?
    ) -> AXProjectGovernanceTemplate? {
        guard let preview else { return nil }
        if AXProjectGovernanceTemplate.selectableTemplates.contains(preview.configuredProfile) {
            return preview.configuredProfile
        }
        if AXProjectGovernanceTemplate.selectableTemplates.contains(preview.effectiveProfile) {
            return preview.effectiveProfile
        }
        return nil
    }

    private static func inferredTemplate(for raw: String) -> AXProjectGovernanceTemplate {
        if isNewProjectCreationGoal(raw) {
            return .inception
        }

        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let prototypeSignals = [
            "原型", "demo", "spike", "小游戏", "草图", "proof of concept", "poc", "mvp"
        ]
        if prototypeSignals.contains(where: normalized.contains) {
            return .prototype
        }

        let largeProjectSignals = [
            "重构", "大版本", "长期", "持续", "平台", "系统", "架构", "交付", "上线", "发布", "多项目"
        ]
        if largeProjectSignals.contains(where: normalized.contains) {
            return .largeProject
        }

        return .feature
    }

    private static func inferredReason(for template: AXProjectGovernanceTemplate) -> String {
        switch template {
        case .prototype:
            return "这类请求更像 demo、spike 或 MVP 起步；先用低摩擦原型场景快速出第一版，再决定要不要升到更重的交付档。"
        case .feature:
            return "这类请求默认按功能开发主力场景起步：先把 job、initial plan、repo 动作和 verify 走稳，再看是否需要扩成更重治理。"
        case .largeProject:
            return "这类请求已经像持续交付或较大改造；默认先走大型项目场景，让 continuity、checkpoint 和 delivery 收口更明确。"
        case .highGovernance:
            return "高治理场景只应在项目本身已经明确处于 A4 Agent lane 时沿用，不会对新任务静默自动升档。"
        case .inception:
            return "这是新项目或开局型请求；默认先走产品开局场景，把 scope、约束、第一版工单和架构框架先收敛清楚。"
        case .legacyObserve:
            return "旧 Observe 基线只保留给兼容项目，不作为新的大任务默认场景。"
        case .custom:
            return "当前任务会先收敛到最接近的标准场景，再按需要单独微调。"
        }
    }

    private static func preferredSplitProfile(
        for template: AXProjectGovernanceTemplate
    ) -> OneShotSplitProfile {
        switch template {
        case .prototype, .inception, .legacyObserve, .custom:
            return .conservative
        case .feature, .largeProject:
            return .balanced
        case .highGovernance:
            return .aggressive
        }
    }

    private static func tokenBudgetClass(
        for template: AXProjectGovernanceTemplate
    ) -> OneShotTokenBudgetClass {
        switch template {
        case .largeProject, .highGovernance:
            return .priorityDelivery
        case .prototype, .feature, .inception, .legacyObserve, .custom:
            return .standard
        }
    }

    private static func deliveryMode(
        for template: AXProjectGovernanceTemplate
    ) -> OneShotDeliveryMode {
        switch template {
        case .prototype:
            return .implementationFirst
        case .feature, .largeProject, .highGovernance, .inception, .legacyObserve, .custom:
            return .specFirst
        }
    }

    private static func isNewProjectCreationGoal(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return false }
        let compact = trimmed
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.symbols))
        let createTokens = [
            "创建项目",
            "创建一个项目",
            "新建项目",
            "新建独立项目",
            "建个项目",
            "建项目",
            "建一个项目",
            "建独立项目",
            "建立项目",
            "建立一个项目",
            "建立独立项目",
            "创立项目",
            "创立一个项目",
            "创建独立项目",
            "创建一个project",
            "建立一个project",
            "创立一个project",
            "开个项目",
            "开一个项目",
            "开独立项目",
            "起项目",
            "起一个项目",
            "立项",
            "按默认方案建项目",
            "按默认方案创建项目",
            "直接建项目",
            "直接创建项目",
            "createproject",
            "newproject"
        ]
        return createTokens.contains(where: { compact.contains($0) })
    }
}
