import Foundation

struct SupervisorConversationQuickIntent: Identifiable, Equatable {
    enum Tone: String, Equatable {
        case resume
        case focus
        case caution
        case diagnostic
        case neutral
    }

    let id: String
    let title: String
    let systemImage: String
    let tone: Tone
    let prompt: String
    let helpText: String
}

struct SupervisorConversationQuickIntentContext: Equatable {
    struct ProjectReference: Equatable {
        let projectId: String
        let displayName: String
    }

    struct ResumeReference: Equatable {
        let projectId: String
        let projectDisplayName: String
        let reasonLabel: String
        let relativeText: String
    }

    struct TodayFocusReference: Equatable {
        let projectId: String
        let projectName: String
        let reasonSummary: String
        let recommendedNextAction: String
        let kindLabel: String
    }

    var workMode: XTSupervisorWorkMode
    var selectedProject: ProjectReference?
    var resumeProject: ResumeReference?
    var todayFocus: TodayFocusReference?
    var awaitingAuthorizationProject: ProjectReference?
    var awaitingAuthorizationCount: Int
    var hubInteractive: Bool
    var hubRemoteConnected: Bool
    var lastReplyExecutionMode: String
    var lastRemoteFailureReasonCode: String
}

@MainActor
enum SupervisorConversationQuickIntentSupport {
    private static let maxIntentCount = 5

    static func build(
        appModel: AppModel,
        supervisor: SupervisorManager
    ) -> [SupervisorConversationQuickIntent] {
        build(context: context(appModel: appModel, supervisor: supervisor))
    }

    static func context(
        appModel: AppModel,
        supervisor: SupervisorManager
    ) -> SupervisorConversationQuickIntentContext {
        let selectedProject = currentSelectedProject(from: appModel)
        let resumeProject = appModel.preferredResumeProject().map { presentation in
            SupervisorConversationQuickIntentContext.ResumeReference(
                projectId: presentation.projectId,
                projectDisplayName: presentation.projectDisplayName,
                reasonLabel: presentation.summary.reasonLabel,
                relativeText: presentation.summary.relativeText
            )
        }
        let actionability = supervisor.supervisorPortfolioSnapshot.actionabilitySnapshot()
        let todayFocus = actionability.recommendedActions.first.map { item in
            SupervisorConversationQuickIntentContext.TodayFocusReference(
                projectId: item.projectId,
                projectName: item.projectName,
                reasonSummary: item.reasonSummary,
                recommendedNextAction: item.recommendedNextAction,
                kindLabel: item.kindLabel
            )
        }
        let awaitingAuthorizationProject = supervisor.supervisorPortfolioSnapshot.projects.first { card in
            card.projectState == .awaitingAuthorization
        }.map { card in
            SupervisorConversationQuickIntentContext.ProjectReference(
                projectId: card.projectId,
                displayName: card.displayName
            )
        }

        return SupervisorConversationQuickIntentContext(
            workMode: supervisor.currentSupervisorWorkMode,
            selectedProject: selectedProject,
            resumeProject: resumeProject,
            todayFocus: todayFocus,
            awaitingAuthorizationProject: awaitingAuthorizationProject,
            awaitingAuthorizationCount: supervisor.supervisorPortfolioSnapshot.counts.awaitingAuthorization,
            hubInteractive: appModel.hubInteractive,
            hubRemoteConnected: appModel.hubRemoteConnected,
            lastReplyExecutionMode: supervisor.lastSupervisorReplyExecutionMode,
            lastRemoteFailureReasonCode: supervisor.lastSupervisorRemoteFailureReasonCode
        )
    }

    static func build(
        context: SupervisorConversationQuickIntentContext
    ) -> [SupervisorConversationQuickIntent] {
        var intents: [SupervisorConversationQuickIntent] = []

        if let resumeProject = context.resumeProject {
            intents.append(resumeIntent(resumeProject, workMode: context.workMode))
        }

        if let selectedProject = context.selectedProject {
            intents.append(currentProjectIntent(selectedProject, workMode: context.workMode))
        }

        if let todayFocus = context.todayFocus {
            intents.append(todayFocusIntent(todayFocus, workMode: context.workMode))
        }

        if context.awaitingAuthorizationCount > 0,
           let awaitingAuthorizationProject = context.awaitingAuthorizationProject {
            intents.append(
                awaitingAuthorizationIntent(
                    project: awaitingAuthorizationProject,
                    count: context.awaitingAuthorizationCount
                )
            )
        }

        intents.append(hubStatusIntent(context))
        return Array(intents.prefix(maxIntentCount))
    }

    private static func currentSelectedProject(
        from appModel: AppModel
    ) -> SupervisorConversationQuickIntentContext.ProjectReference? {
        guard let selectedProjectId = appModel.selectedProjectId,
              selectedProjectId != AXProjectRegistry.globalHomeId,
              let project = appModel.registry.project(for: selectedProjectId) else {
            return nil
        }
        return SupervisorConversationQuickIntentContext.ProjectReference(
            projectId: project.projectId,
            displayName: project.displayName
        )
    }

    private static func resumeIntent(
        _ resumeProject: SupervisorConversationQuickIntentContext.ResumeReference,
        workMode: XTSupervisorWorkMode
    ) -> SupervisorConversationQuickIntent {
        let prompt: String
        switch workMode {
        case .conversationOnly:
            prompt = "帮我接上次的进度，重点看项目 \(resumeProject.projectDisplayName)。先用一句话复盘当前状态，再说最近一步。"
        case .guidedProgress:
            prompt = "帮我接上次的进度，重点看项目 \(resumeProject.projectDisplayName)。先用一句话复盘当前状态，再给我最合适的下一步。"
        case .governedAutomation:
            prompt = "帮我接上次的进度，重点看项目 \(resumeProject.projectDisplayName)。先复盘当前状态和下一步；如果治理边界允许继续推进，也告诉我最短执行路径。"
        }

        return SupervisorConversationQuickIntent(
            id: "resume",
            title: "接上次进度",
            systemImage: "arrow.clockwise.circle",
            tone: .resume,
            prompt: prompt,
            helpText: "\(resumeProject.projectDisplayName) · 最近交接：\(resumeProject.reasonLabel) · \(resumeProject.relativeText)"
        )
    }

    private static func currentProjectIntent(
        _ project: SupervisorConversationQuickIntentContext.ProjectReference,
        workMode: XTSupervisorWorkMode
    ) -> SupervisorConversationQuickIntent {
        let title: String
        let prompt: String

        switch workMode {
        case .conversationOnly:
            title = "看当前项目"
            prompt = "看一下当前项目 \(project.displayName) 的状态，直接告诉我现在做到哪、卡点和最近一步。"
        case .guidedProgress:
            title = "继续当前项目"
            prompt = "继续推进当前项目 \(project.displayName)。先给我一句当前状态，再给出下一步和风险。"
        case .governedAutomation:
            title = "推进当前项目"
            prompt = "继续推进当前项目 \(project.displayName)。如果治理边界、授权和运行时都允许，就继续往前做；否则先告诉我最短计划和阻塞点。"
        }

        return SupervisorConversationQuickIntent(
            id: "current_project:\(project.projectId)",
            title: title,
            systemImage: "scope",
            tone: .focus,
            prompt: prompt,
            helpText: "围绕当前项目 \(project.displayName) 发起一轮 focused supervisor turn。"
        )
    }

    private static func todayFocusIntent(
        _ focus: SupervisorConversationQuickIntentContext.TodayFocusReference,
        workMode: XTSupervisorWorkMode
    ) -> SupervisorConversationQuickIntent {
        let prompt: String
        switch workMode {
        case .conversationOnly:
            prompt = "帮我看今天最该先处理什么。按优先级说 1 到 3 个项目，并说明为什么先看它们。"
        case .guidedProgress:
            prompt = "帮我看今天最该先处理什么，按优先级给我建议；每个项目都带一句下一步。"
        case .governedAutomation:
            prompt = "帮我看今天最该先处理什么，按优先级给我建议；如果有可以在治理边界内直接推进的项目，也标出来。"
        }

        return SupervisorConversationQuickIntent(
            id: "today_focus",
            title: "看今日重点",
            systemImage: "list.bullet.clipboard",
            tone: .focus,
            prompt: prompt,
            helpText: "当前优先建议：\(focus.projectName) · \(nonEmpty(focus.reasonSummary, fallback: focus.kindLabel))"
        )
    }

    private static func awaitingAuthorizationIntent(
        project: SupervisorConversationQuickIntentContext.ProjectReference,
        count: Int
    ) -> SupervisorConversationQuickIntent {
        SupervisorConversationQuickIntent(
            id: "awaiting_authorization",
            title: "看待授权",
            systemImage: "checklist.unchecked",
            tone: .caution,
            prompt: "帮我看当前哪些项目在等授权。先说最卡住的一个、为什么需要我确认，以及我现在该怎么决定。",
            helpText: "\(count) 个项目处于 awaiting authorization；先看 \(project.displayName)。"
        )
    }

    private static func hubStatusIntent(
        _ context: SupervisorConversationQuickIntentContext
    ) -> SupervisorConversationQuickIntent {
        let executionMode = normalizedToken(context.lastReplyExecutionMode)
        let failureReason = normalizedToken(context.lastRemoteFailureReasonCode)
        let hasFallbackSignal = executionMode == "local_fallback_after_remote_error"
            || executionMode == "hub_downgraded_to_local"
            || !failureReason.isEmpty
        let prompt: String
        let tone: SupervisorConversationQuickIntent.Tone
        let helpText: String

        if !context.hubInteractive {
            prompt = "检查一下当前 Hub / 模型 / 路由状态，告诉我为什么现在只能走本地，以及先修哪一步。"
            tone = .diagnostic
            helpText = "当前 Hub 不可交互；Supervisor 很可能只能走本地路径。"
        } else if hasFallbackSignal {
            prompt = "检查一下当前 Hub / 模型 / 路由状态，重点看为什么最近会掉到本地；请直接告诉我现状、最可能原因和最短修复路径。"
            tone = .diagnostic
            helpText = failureReason.isEmpty
                ? "最近出现过远端失败后本地兜底。"
                : "最近出现过远端失败后本地兜底：\(failureReason)"
        } else if context.hubRemoteConnected {
            prompt = "检查一下当前 Hub / 模型 / 路由状态，告诉我现在远端是否正常、有没有明显风险。"
            tone = .neutral
            helpText = "Hub 已连接，远端路由当前可见。"
        } else {
            prompt = "检查一下当前 Hub / 模型 / 路由状态，告诉我现在是否可用、有没有明显问题。"
            tone = .neutral
            helpText = "Hub 已连接；当前没有明显的远端降级信号。"
        }

        return SupervisorConversationQuickIntent(
            id: "hub_status",
            title: "检查 Hub 状态",
            systemImage: "waveform.path.ecg.rectangle",
            tone: tone,
            prompt: prompt,
            helpText: helpText
        )
    }

    private static func nonEmpty(_ preferred: String, fallback: String) -> String {
        let trimmedPreferred = preferred.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedPreferred.isEmpty {
            return trimmedPreferred
        }
        let trimmedFallback = fallback.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedFallback.isEmpty ? "需要你先看的项目" : trimmedFallback
    }

    private static func normalizedToken(_ raw: String) -> String {
        raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: " ")
    }
}
