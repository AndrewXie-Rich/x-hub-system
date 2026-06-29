import Foundation

extension ChatSessionModel {
    func isProjectIdentityQuestion(_ normalized: String) -> Bool {
        let tokens = [
            "你是谁",
            "你是啥",
            "你是不是gpt",
            "你是gpt吗",
            "你是不是chatgpt",
            "你是chatgpt吗",
            "who are you",
            "are you gpt",
            "are you chatgpt"
        ]
        return tokens.contains { normalized.contains($0) }
    }

    func isProjectResumeQuestion(_ normalized: String) -> Bool {
        let tokens = [
            "接上次的进度",
            "接上次进度",
            "帮我接上次",
            "帮我续上次",
            "项目交接摘要",
            "交接摘要",
            "resume this project",
            "resume summary",
            "project handoff",
            "handoff summary",
            "pick up where we left off"
        ]
        return tokens.contains { normalized.contains($0) }
    }

    func isProjectLastActualModelQuestion(_ normalized: String) -> Bool {
        let tokens = [
            "上一轮实际调用了什么模型",
            "上一轮用了什么模型",
            "刚刚上一轮实际调用了什么模型",
            "刚刚那轮实际调用了什么模型",
            "上一次实际调用了什么模型",
            "最近一次实际调用了什么模型",
            "最近一次调用了什么模型",
            "last actual model",
            "last model used",
            "previous model used"
        ]
        return tokens.contains { normalized.contains($0) }
    }

    func isProjectModelRouteQuestion(_ normalized: String) -> Bool {
        let tokens = [
            "什么模型",
            "哪个模型",
            "当前模型",
            "现在是什么模型",
            "现在什么模型",
            "现在用的什么模型",
            "用了什么模型",
            "实际是什么模型",
            "实际走的什么模型",
            "当前走的是什么模型",
            "是不是gpt模型",
            "what model",
            "which model",
            "current model",
            "model route"
        ]
        return tokens.contains { normalized.contains($0) }
    }

    func directProjectReplyIfApplicable(
        userText: String,
        ctx: AXProjectContext,
        config: AXProjectConfig?,
        router: LLMRouter
    ) -> String? {
        let normalized = normalizedProjectDirectReplyQuestion(userText)
        guard isProjectResumeQuestion(normalized)
                || isProjectIdentityQuestion(normalized)
                || isProjectLastActualModelQuestion(normalized)
                || isProjectModelRouteQuestion(normalized) else {
            return nil
        }

        if isProjectResumeQuestion(normalized) {
            return renderProjectResumeBrief(ctx: ctx, excludingTrailingUserText: userText)
        }

        let configuredModelId = configuredProjectModelID(for: .coder, config: config, router: router)
        let snapshot = currentProjectExecutionSnapshot(ctx: ctx, role: .coder)
        let routeSummary = projectRouteSummary(configuredModelId: configuredModelId)
        let invocationSummary = projectLastActualInvocationSummary(
            configuredModelId: configuredModelId,
            snapshot: snapshot
        )
        let verificationSummary = projectVerificationSummary(
            configuredModelId: configuredModelId,
            snapshot: snapshot
        )
        let scopeLine = "以下记录只针对当前项目的 coder 角色；Supervisor / reviewer / 其他项目的模型路由彼此独立，不能混读。"

        if isProjectIdentityQuestion(normalized) {
            return [
                "如果你是在问这个项目聊天窗口：我是 X-Terminal 里的 Project AI，走的是当前项目的 coder 角色，不是 Supervisor。",
                "至于是不是 GPT，不能看我怎么自称，要看真实执行记录。",
                "这条回复本身是本地直答，不会为了回答这个问题再额外触发远端模型。",
                routeSummary,
                "最近一次真实调用记录：",
                invocationSummary,
                scopeLine
            ].joined(separator: "\n\n")
        }

        if isProjectLastActualModelQuestion(normalized) {
            return [
                "如果你问的是这个项目聊天窗口刚刚上一轮真正触发到的模型，结论先说：",
                invocationSummary,
                "补充一点：这条回复本身仍然是本地直答，用来读取运行记录，不会为了回答这个问题再额外打一次远端模型。",
                routeSummary,
                "当前验证状态：",
                verificationSummary,
                scopeLine
            ].joined(separator: "\n\n")
        }

        return [
            "这条回复本身是本地直答，不会为了回答模型状态再额外触发远端模型。",
            routeSummary,
            "当前验证状态：",
            verificationSummary,
            "最近一次真实调用记录：",
            invocationSummary,
            scopeLine
        ].joined(separator: "\n\n")
    }
}
