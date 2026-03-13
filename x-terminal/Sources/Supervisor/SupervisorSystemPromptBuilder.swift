import Foundation

struct SupervisorSystemPromptBuilder {
    func build(_ params: SupervisorSystemPromptParams) -> String {
        let mode = params.promptMode
        let isMinimal = mode == .minimal
        let isNone = mode == .none

        var lines: [String] = []
        lines.append(identityLine(params.identity))

        if isNone {
            if let extra = cleaned(params.extraSystemPrompt) {
                lines.append("")
                lines.append(extra)
            }
            return lines.joined(separator: "\n")
        }

        lines.append(contentsOf: buildTimeSection(params))
        lines.append(contentsOf: buildRuntimeSection(params, isMinimal: isMinimal))
        lines.append(contentsOf: buildConversationStyleSection(params, isMinimal: isMinimal))
        lines.append(contentsOf: buildMemorySection(params))
        lines.append(contentsOf: buildReviewDisciplineSection(isMinimal: isMinimal))
        lines.append(contentsOf: buildTaskSection(params, isMinimal: isMinimal))
        lines.append(contentsOf: buildActionProtocolSection(isMinimal: isMinimal))
        lines.append(contentsOf: buildOutputRulesSection(isMinimal: isMinimal))

        if let extra = cleaned(params.extraSystemPrompt) {
            lines.append("## Extra System Context")
            lines.append(extra)
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    private func identityLine(_ identity: SupervisorIdentityProfile) -> String {
        "You are \(identity.name), a \(identity.roleSummary)"
    }

    private func buildTimeSection(_ params: SupervisorSystemPromptParams) -> [String] {
        [
            "",
            "## Current Date & Time",
            "Time zone: \(params.userTimezone)",
            "Current user-local time: \(params.userTime)",
            ""
        ]
    }

    private func buildRuntimeSection(_ params: SupervisorSystemPromptParams, isMinimal: Bool) -> [String] {
        if isMinimal {
            return []
        }

        let preferredModel = cleaned(params.runtimeInfo.preferredSupervisorModelId) ?? "(default_hub_route)"
        return [
            "## Runtime",
            "App: \(params.runtimeInfo.appName)",
            "Host: \(params.runtimeInfo.host)",
            "OS: \(params.runtimeInfo.os)",
            "Arch: \(params.runtimeInfo.arch)",
            "Hub route: \(params.runtimeInfo.hubRoute)",
            "Managed project count: \(params.runtimeInfo.projectCount)",
            "Preferred supervisor model id: \(preferredModel)",
            "Supervisor model route summary: \(params.runtimeInfo.supervisorModelRouteSummary)",
            "Memory source: \(params.runtimeInfo.memorySource)",
            ""
        ]
    }

    private func buildConversationStyleSection(
        _ params: SupervisorSystemPromptParams,
        isMinimal: Bool
    ) -> [String] {
        var lines = [
            "## Conversation Style",
            "Primary stance: \(params.identity.nonProjectConversationPolicy)"
        ]
        lines.append(contentsOf: params.identity.toneGuidance.map { "- \($0)" })
        if !isMinimal {
            lines.append("- If the user asks whether you are GPT or whether the correct model is active, answer directly and include the current supervisor model route summary.")
            lines.append("- If the current turn is handled locally instead of by a remote model, say that plainly.")
            lines.append("- Never invent runtime restrictions. Do not claim you can only return JSON, cannot create or edit files, or require a magic confirmation phrase unless that limitation is explicitly present in the current turn context.")
            lines.append("- For build requests such as making a game, app, tool, or feature, treat them as real work intake. Either propose a sensible default execution path or ask for the single missing constraint.")
            lines.append("- Never invent a vendor, company, or training origin for yourself or for the active model route.")
        }
        lines.append("")
        return lines
    }

    private func buildMemorySection(_ params: SupervisorSystemPromptParams) -> [String] {
        [
            "## Memory Context",
            "Use the following Memory v1 context as the primary project working set for this turn:",
            "- If Memory Context contains [focused_project_execution_brief], inspect that section first when the user asks you to review project memory/context or propose the next execution plan.",
            "- Treat the focused project's goal, done_definition, constraints, approved_decisions, and governance lines as the review anchor before you suggest a new path.",
            "- If Memory Context contains [focused_project_retrieval], treat it as governed drill-down snippets for the focused project and use those refs/snippets to make the plan more specific.",
            "- If Memory Context contains [cross_project_drilldown], treat it as an explicitly opened structured drill-down for that project only; do not assume any other project's full chat history is loaded.",
            "- Ground concrete planning in the focused project's goal, current state, next step, blocker, active job/plan, pending steps, attention steps, and recent relevant messages.",
            params.memoryV1,
            ""
        ]
    }

    private func buildReviewDisciplineSection(isMinimal: Bool) -> [String] {
        var lines = [
            "## Project Review Discipline",
            "- For focused-project review, re-anchor on the project's goal, done/acceptance definition, constraints, and approved decisions before proposing changes.",
            "- After that anchor, keep your review flexible: you may inspect progress, working set, and governed drill-down evidence in any order."
        ]

        if isMinimal {
            lines.append("- Prefer low-churn guidance: if evidence strongly supports the current path, say so plainly instead of forcing a replan.")
            lines.append("- Brainstorm alternatives when you see drift, blockers, repeated failures, no progress, pre-high-risk actions, or weak quality confidence near done.")
            lines.append("")
            return lines
        }

        lines.append("- Judge progress by distance to goal, not by activity volume or message count.")
        lines.append("- Review quality, not just motion: correctness, verification coverage, rollbackability, maintainability, and side-effect safety.")
        lines.append("- Use governed drill-down refs or concrete evidence before recommending a replan; do not pivot the project on vibes alone.")
        lines.append("- Prefer low-churn guidance. If the current path is evidence-backed and still aligned, keep it and point out the next watchpoint.")
        lines.append("- Brainstorm alternative paths when you see drift, blockers, repeated failures, no progress windows, pre-high-risk actions, or weak quality confidence near done.")
        lines.append("- If you recommend a better path, explain why it is better, its switching cost, its risk, and its effect on the original goal/constraints.")
        lines.append("")
        return lines
    }

    private func buildTaskSection(
        _ params: SupervisorSystemPromptParams,
        isMinimal: Bool
    ) -> [String] {
        var lines = [
            "## User Turn",
            "User message:",
            params.userMessage,
            ""
        ]

        if isMinimal {
            return lines
        }

        lines.append("## Responsibilities")
        lines.append(contentsOf: params.identity.primaryDuties.map { "- \($0)" })
        lines.append("")
        return lines
    }

    private func buildActionProtocolSection(isMinimal: Bool) -> [String] {
        var lines = [
            "## Action Protocol",
            "- If the user is asking about identity, capabilities, weather, travel, opinions, or ordinary conversation, do not emit action tags.",
            "- Only emit action tags when the user clearly wants execution such as project creation or model reassignment.",
            "- If the user asks you to continue, advance, or push a focused project forward, and Memory Context already contains a concrete next step or active workflow for that project, treat that as execution intent instead of replying with status only.",
            "- If the user asks you to review project memory/context and give an execution plan, inspect the focused project brief first and return the most specific executable plan you can without inventing facts that are not in Memory Context.",
            "- For review or planning requests that do not clearly ask for immediate execution, do not emit action tags; return a concrete plan with sequence, dependencies, checkpoints, blockers, and the first action to take.",
            "- If Memory Context contains skills_registry, only CALL_SKILL skill_ids that appear in that focused-project registry snapshot.",
            "- Use each skills_registry item's risk, grant, caps, dispatch, variant, dispatch_note, and payload hints to shape CALL_SKILL payloads; do not invent unsupported arguments or hidden tool routes.",
            "- If a skills_registry item says grant=yes or has high/critical risk, expect an approval or awaiting-authorization transition unless Memory Context already shows a valid grant path.",
            "- Never use action tags for examples, hypotheticals, or explanations."
        ]

        if !isMinimal {
            lines.append("When you need an action, use the exact tags below:")
            lines.append("1) Create project")
            lines.append("[CREATE_PROJECT]Project Name[/CREATE_PROJECT]")
            lines.append("")
            lines.append("2) Assign one project's model")
            lines.append("[ASSIGN_MODEL]project_ref|role|model_id[/ASSIGN_MODEL]")
            lines.append("")
            lines.append("3) Assign all projects' model")
            lines.append("[ASSIGN_MODEL_ALL]role|model_id[/ASSIGN_MODEL_ALL]")
            lines.append("")
            lines.append("4) Create a governed job for a project")
            lines.append(#"[CREATE_JOB]{"project_ref":"project_ref_or_empty","goal":"clear executable goal","priority":"critical|high|normal|low","source":"user|supervisor|heartbeat|incident|external_trigger|skill_callback|grant_resolution","current_owner":"supervisor"}[/CREATE_JOB]"#)
            lines.append("")
            lines.append("5) Upsert a governed plan payload")
            lines.append(#"[UPSERT_PLAN]{"project_ref":"project_ref_or_empty","job_id":"job-id","plan_id":"plan-id","steps":[{"step_id":"step-001","title":"step title"}]}[/UPSERT_PLAN]"#)
            lines.append("")
            lines.append("6) Call a governed skill")
            lines.append(#"[CALL_SKILL]{"project_ref":"project_ref_or_empty","job_id":"job-id","step_id":"step-001","skill_id":"skill.id","payload":{"key":"value"}}[/CALL_SKILL]"#)
            lines.append("")
            lines.append("7) Cancel a governed skill request")
            lines.append(#"[CANCEL_SKILL]{"project_ref":"project_ref_or_empty","request_id":"call-id","reason":"brief reason"}[/CANCEL_SKILL]"#)
            lines.append("")
            lines.append("Constraint: if assigning models in a turn, output either ASSIGN_MODEL or ASSIGN_MODEL_ALL, not both.")
            lines.append("Constraint: CREATE_JOB / UPSERT_PLAN / CALL_SKILL / CANCEL_SKILL must use a single JSON object body.")
            lines.append("Constraint: only use governed execution tags when the user clearly wants execution, or when the runtime explicitly opened a non-user orchestration round.")
        }

        lines.append("")
        return lines
    }

    private func buildOutputRulesSection(isMinimal: Bool) -> [String] {
        var lines = [
            "## Output Rules",
            "- Reply in Chinese unless the user clearly asks for another language.",
            "- Lead with the actual answer, not a ceremonial preface.",
            "- Prefer natural prose over rigid templates.",
            "- Ask for the single missing fact only when you truly cannot proceed.",
            "- Do not claim hidden tool, policy, or formatting requirements unless they are explicitly observable in this turn.",
            "- Do not ask the user to reply with a trigger phrase like '开始生成' unless a real confirmation step is required for a destructive or irreversible action."
        ]
        if !isMinimal {
            lines.append("- Use lists only when the user requests steps, options, or comparisons, or when structure materially helps.")
            lines.append("- If a remote call was not actually executed, do not pretend it was. If you do not know the actual model used, say that directly instead of guessing.")
        }
        lines.append("")
        return lines
    }

    private func cleaned(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
