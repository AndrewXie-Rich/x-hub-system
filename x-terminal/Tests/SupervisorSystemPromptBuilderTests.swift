import Foundation
import Testing
@testable import XTerminal

struct SupervisorSystemPromptBuilderTests {

    @Test
    func identityProfileCanApplyConfiguredPromptPreferences() {
        let configured = SupervisorIdentityProfile.default().applying(
            SupervisorPromptPreferences(
                identityName: "Atlas Supervisor",
                roleSummary: "Project control AI for delivery orchestration.",
                toneDirectives: "Answer directly\nDo not hide uncertainty.",
                extraSystemPrompt: "Prefer concrete language."
            )
        )

        #expect(configured.name == "Atlas Supervisor")
        #expect(configured.roleSummary == "Project control AI for delivery orchestration.")
        #expect(configured.toneGuidance.contains("Answer directly"))
        #expect(configured.toneGuidance.contains("Do not hide uncertainty."))
    }

    @Test
    func fullModeIncludesOpenClawStyleSectionsAndExtraContext() {
        let params = SupervisorSystemPromptParamsBuilder.build(
            preferredSupervisorModelId: "openai/gpt-5.3-codex",
            supervisorModelRouteSummary: "openai/gpt-5.3-codex（已加载，名称：GPT 5.3 Codex）",
            memorySource: "memory_v1",
            projectCount: 3,
            userMessage: "把我的世界这个项目的模型换成5.3",
            memoryV1: "project=myworld\nstatus=running",
            promptMode: .full,
            extraSystemPrompt: "Always preserve execution safety.",
            now: Date(timeIntervalSince1970: 1_773_196_800),
            timeZone: TimeZone(identifier: "Asia/Shanghai") ?? .current,
            locale: Locale(identifier: "en_US_POSIX"),
            hubConnected: true,
            hubRemoteConnected: true
        )

        let prompt = SupervisorSystemPromptBuilder().build(params)

        #expect(prompt.contains("You are Supervisor, a Supervisor AI for project orchestration, model routing, and execution coordination."))
        #expect(prompt.contains("## Current Date & Time"))
        #expect(prompt.contains("Time zone: Asia/Shanghai"))
        #expect(prompt.contains("## Runtime"))
        #expect(prompt.contains("Hub route: remote_hub"))
        #expect(prompt.contains("Managed project count: 3"))
        #expect(prompt.contains("Preferred supervisor model id: openai/gpt-5.3-codex"))
        #expect(prompt.contains("Supervisor model route summary: openai/gpt-5.3-codex（已加载，名称：GPT 5.3 Codex）"))
        #expect(prompt.contains("## Conversation Style"))
        #expect(prompt.contains("Never invent runtime restrictions."))
        #expect(prompt.contains("For build requests such as making a game, app, tool, or feature"))
        #expect(prompt.contains("## Memory Context"))
        #expect(prompt.contains("If Memory Context contains [PORTFOLIO_BRIEF], inspect it first"))
        #expect(prompt.contains("If Memory Context contains [FOCUSED_PROJECT_ANCHOR_PACK], inspect that section first"))
        #expect(prompt.contains("If Memory Context contains [LONGTERM_OUTLINE], use it as the focused project's durable background"))
        #expect(prompt.contains("If the focused project anchor includes decision_lineage or blocker_lineage"))
        #expect(prompt.contains("If Memory Context contains [DELTA_FEED], treat it as the shortest path"))
        #expect(prompt.contains("If [DELTA_FEED] says no_material_change or shows unchanged state hashes"))
        #expect(prompt.contains("If Memory Context contains [CONFLICT_SET], treat it as explicit unresolved disagreements"))
        #expect(prompt.contains("If Memory Context contains [CONTEXT_REFS], use it as a grounding and provenance index"))
        #expect(prompt.contains("If Memory Context contains [EVIDENCE_PACK], treat it as selected high-signal evidence"))
        #expect(prompt.contains("Treat the focused project's goal, done_definition, constraints, approved_decisions, longterm outline, and governance lines as the review anchor"))
        #expect(prompt.contains("If governance lines distinguish configured, recommended, and effective supervision"))
        #expect(prompt.contains("Treat effective_work_order_depth as a minimum specificity floor, not a rigid response template"))
        #expect(prompt.contains("If governance lines expose project_ai_strength_band or project_ai_strength_reasons"))
        #expect(prompt.contains("If Memory Context contains [cross_project_drilldown], treat it as an explicitly opened structured drill-down"))
        #expect(prompt.contains("Ground concrete planning in the focused project's goal, current state, next step, blocker"))
        #expect(prompt.contains("project=myworld\nstatus=running"))
        #expect(prompt.contains("## Project Review Discipline"))
        #expect(prompt.contains("re-anchor on the project's goal, done/acceptance definition, constraints, and approved decisions"))
        #expect(prompt.contains("Judge progress by distance to goal, not by activity volume"))
        #expect(prompt.contains("Prefer low-churn guidance. If the current path is evidence-backed and still aligned, keep it"))
        #expect(prompt.contains("If effective_work_order_depth is execution_ready"))
        #expect(prompt.contains("enough execution detail to run safely"))
        #expect(prompt.contains("You may satisfy that execution_ready floor with concise but specific step titles"))
        #expect(prompt.contains("Do not turn a strong, already coherent plan into a rigid checklist"))
        #expect(prompt.contains("If effective_work_order_depth is step_locked_rescue"))
        #expect(prompt.contains("## User Turn"))
        #expect(prompt.contains("把我的世界这个项目的模型换成5.3"))
        #expect(prompt.contains("## Responsibilities"))
        #expect(prompt.contains("## Action Protocol"))
        #expect(prompt.contains("[CREATE_PROJECT]Project Name[/CREATE_PROJECT]"))
        #expect(prompt.contains("[ASSIGN_MODEL]project_ref|role|model_id[/ASSIGN_MODEL]"))
        #expect(prompt.contains(#"[CREATE_JOB]{"project_ref":"project_ref_or_empty","goal":"clear executable goal","priority":"critical|high|normal|low","source":"user|supervisor|heartbeat|incident|external_trigger|skill_callback|grant_resolution","current_owner":"supervisor"}[/CREATE_JOB]"#))
        #expect(prompt.contains(#"[UPSERT_PLAN]{"project_ref":"project_ref_or_empty","job_id":"job-id","plan_id":"plan-id","steps":[{"step_id":"step-001","title":"step title"}]}[/UPSERT_PLAN]"#))
        #expect(prompt.contains(#"[CALL_SKILL]{"project_ref":"project_ref_or_empty","job_id":"job-id","step_id":"step-001","skill_id":"skill.id","payload":{"key":"value"}}[/CALL_SKILL]"#))
        #expect(prompt.contains(#"[CANCEL_SKILL]{"project_ref":"project_ref_or_empty","request_id":"call-id","reason":"brief reason"}[/CANCEL_SKILL]"#))
        #expect(prompt.contains("If the user asks you to continue, advance, or push a focused project forward"))
        #expect(prompt.contains("If the user asks you to review project memory/context and give an execution plan"))
        #expect(prompt.contains("For review or planning requests that do not clearly ask for immediate execution, do not emit action tags"))
        #expect(prompt.contains("If Memory Context contains skills_registry, only CALL_SKILL skill_ids that appear in that focused-project registry snapshot."))
        #expect(prompt.contains("Use each skills_registry item's risk, grant, caps, dispatch, variant, dispatch_note, and payload hints to shape CALL_SKILL payloads"))
        #expect(prompt.contains("If a skills_registry item says grant=yes or has high/critical risk, expect an approval or awaiting-authorization transition"))
        #expect(prompt.contains("If you emit UPSERT_PLAN for a focused project, match the effective_work_order_depth shown in Memory Context as a minimum detail floor"))
        #expect(prompt.contains("For strong or capable focused projects, execution_ready can stay concise"))
        #expect(prompt.contains("Constraint: CREATE_JOB / UPSERT_PLAN / CALL_SKILL / CANCEL_SKILL must use a single JSON object body."))
        #expect(prompt.contains("## Output Rules"))
        #expect(prompt.contains("Do not ask the user to reply with a trigger phrase like '开始生成'"))
        #expect(prompt.contains("## Extra System Context"))
        #expect(prompt.contains("Always preserve execution safety."))
    }

    @Test
    func fullModeIncludesFailClosedMemoryGuidanceWhenStrategicMemoryIsUnderfed() {
        let readiness = SupervisorMemoryAssemblyReadiness(
            ready: false,
            statusLine: "underfed:memory_review_floor_not_met,memory_focus_evidence_missing",
            issues: [
                SupervisorMemoryAssemblyIssue(
                    code: "memory_review_floor_not_met",
                    severity: .blocking,
                    summary: "Supervisor memory 供给没有达到 review floor",
                    detail: "resolved=m2_plan_review floor=m3_deep_dive"
                ),
                SupervisorMemoryAssemblyIssue(
                    code: "memory_focus_evidence_missing",
                    severity: .warning,
                    summary: "Focused strategic review 缺少可追溯证据",
                    detail: "context_refs=0 evidence_items=0"
                ),
            ]
        )
        let params = SupervisorSystemPromptParamsBuilder.build(
            preferredSupervisorModelId: "openai/gpt-5.3-codex",
            supervisorModelRouteSummary: "route-summary",
            memorySource: "memory_v1",
            projectCount: 1,
            userMessage: "审查亮亮项目的上下文记忆并做战略纠偏",
            memoryV1: "memory-line",
            promptMode: .full,
            extraSystemPrompt: nil,
            memoryReadiness: readiness,
            now: Date(timeIntervalSince1970: 1_773_196_800),
            timeZone: TimeZone(identifier: "Asia/Shanghai") ?? .current,
            locale: Locale(identifier: "en_US_POSIX"),
            hubConnected: true,
            hubRemoteConnected: true
        )

        let prompt = SupervisorSystemPromptBuilder().build(params)

        #expect(prompt.contains("Current assembly readiness: underfed:memory_review_floor_not_met,memory_focus_evidence_missing"))
        #expect(prompt.contains("Strategic memory is currently underfed."))
        #expect(prompt.contains("Do not present a confident strategic correction"))
        #expect(prompt.contains("First state that the current memory supply is insufficient for strategic correction"))
        #expect(prompt.contains("Until that gap is repaired, you may still help with immediate blocker, grant, and next-step handling"))
        #expect(prompt.contains("Current memory risks: Supervisor memory 供给没有达到 review floor | Focused strategic review 缺少可追溯证据"))
    }

    @Test
    func minimalModeKeepsIdentityMemoryAndTurnButOmitsHeavyRuntimeSections() {
        let params = SupervisorSystemPromptParams(
            identity: .default(),
            runtimeInfo: SupervisorSystemPromptRuntimeInfo(
                appName: "X-Terminal",
                host: "host",
                os: "macOS",
                arch: "arm64",
                hubRoute: "local_hub",
                projectCount: 1,
                preferredSupervisorModelId: "openai/gpt-5.3-codex",
                supervisorModelRouteSummary: "route-summary",
                memorySource: "memory_v1"
            ),
            userTimezone: "Asia/Shanghai",
            userTime: "Mar 11, 2026 at 8:00:00 PM",
            userMessage: "最近上海天气怎么样",
            memoryV1: "memory-line",
            promptMode: .minimal,
            extraSystemPrompt: nil
        )

        let prompt = SupervisorSystemPromptBuilder().build(params)

        #expect(prompt.contains("You are Supervisor"))
        #expect(prompt.contains("## Current Date & Time"))
        #expect(prompt.contains("## Conversation Style"))
        #expect(prompt.contains("## Memory Context"))
        #expect(prompt.contains("[FOCUSED_PROJECT_ANCHOR_PACK]"))
        #expect(prompt.contains("[LONGTERM_OUTLINE]"))
        #expect(prompt.contains("[CONFLICT_SET]"))
        #expect(prompt.contains("[CONTEXT_REFS]"))
        #expect(prompt.contains("[EVIDENCE_PACK]"))
        #expect(prompt.contains("## Project Review Discipline"))
        #expect(prompt.contains("Prefer low-churn guidance"))
        #expect(prompt.contains("## User Turn"))
        #expect(!prompt.contains("## Runtime"))
        #expect(!prompt.contains("## Responsibilities"))
        #expect(!prompt.contains("[CREATE_PROJECT]Project Name[/CREATE_PROJECT]"))
        #expect(!prompt.contains("[CREATE_JOB]"))
        #expect(!prompt.contains("[UPSERT_PLAN]"))
        #expect(!prompt.contains("[CALL_SKILL]"))
        #expect(!prompt.contains("[CANCEL_SKILL]"))
        #expect(prompt.contains("## Action Protocol"))
        #expect(prompt.contains("Only emit action tags when the user clearly wants execution"))
        #expect(prompt.contains("continue, advance, or push a focused project forward"))
        #expect(prompt.contains("review project memory/context and give an execution plan"))
    }

    @Test
    func noneModeReturnsIdentityLineAndExtraOnly() {
        let params = SupervisorSystemPromptParams(
            identity: .default(),
            runtimeInfo: SupervisorSystemPromptRuntimeInfo(
                appName: "X-Terminal",
                host: "host",
                os: "macOS",
                arch: "arm64",
                hubRoute: "hub_disconnected",
                projectCount: 0,
                preferredSupervisorModelId: nil,
                supervisorModelRouteSummary: "default route",
                memorySource: "memory_v1"
            ),
            userTimezone: "Asia/Shanghai",
            userTime: "Mar 11, 2026 at 8:00:00 PM",
            userMessage: "你好",
            memoryV1: "",
            promptMode: .none,
            extraSystemPrompt: "Extra override"
        )

        let prompt = SupervisorSystemPromptBuilder().build(params)

        #expect(prompt.contains("You are Supervisor, a Supervisor AI for project orchestration, model routing, and execution coordination."))
        #expect(prompt.contains("Extra override"))
        #expect(!prompt.contains("## Current Date & Time"))
        #expect(!prompt.contains("## Runtime"))
        #expect(!prompt.contains("## Memory Context"))
        #expect(!prompt.contains("## Action Protocol"))
    }

    @Test
    func paramsBuilderFallsBackToLocalHubWhenOnlyLocalConnectivityExists() {
        let params = SupervisorSystemPromptParamsBuilder.build(
            preferredSupervisorModelId: nil,
            supervisorModelRouteSummary: "default route",
            memorySource: "memory_v1",
            projectCount: 2,
            userMessage: "看下进度",
            memoryV1: "memory",
            promptMode: .full,
            extraSystemPrompt: nil,
            now: Date(timeIntervalSince1970: 1_773_196_800),
            timeZone: TimeZone(identifier: "Asia/Shanghai") ?? .current,
            locale: Locale(identifier: "en_US_POSIX"),
            hubConnected: true,
            hubRemoteConnected: false
        )

        #expect(params.runtimeInfo.hubRoute == "local_hub")
        #expect(params.runtimeInfo.projectCount == 2)
        #expect(params.runtimeInfo.memorySource == "memory_v1")
    }
}
