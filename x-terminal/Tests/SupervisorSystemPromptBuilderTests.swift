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
        #expect(prompt.contains("## Supervisor Operating Mode"))
        #expect(prompt.contains("Configured work mode: guided_progress"))
        #expect(prompt.contains("## Privacy Mode"))
        #expect(prompt.contains("Configured privacy mode: balanced"))
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
        #expect(prompt.contains("Treat `routing: prefers_builtin=...` and `routing: entrypoints=...` as skill-family metadata."))
        #expect(prompt.contains("If the user explicitly names a registered wrapper or entrypoint skill_id, preserve that exact registered skill_id in CALL_SKILL"))
        #expect(prompt.contains("If the user asks for a capability without naming a specific skill_id, and the relevant skills_registry family advertises `routing: prefers_builtin=...`, choose that preferred builtin"))
        #expect(prompt.contains("Do not emit duplicate CALL_SKILL actions across sibling entrypoints in the same routed family for one intent."))
        #expect(prompt.contains("If a skills_registry item says grant=yes or has high/critical risk, expect an approval or awaiting-authorization transition"))
        #expect(prompt.contains("If a skills_registry item says scope=xt_builtin, treat it as an XT native governed skill that is already available locally"))
        #expect(prompt.contains("If the user does not name a different installed wrapper/entrypoint and skills_registry contains guarded-automation, prefer it for trusted automation readiness checks and governed browser actions"))
        #expect(prompt.contains("If skills_registry contains supervisor-voice, prefer it for local Supervisor playback status / preview / speak / stop requests"))
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
    func fullModeIncludesPersonalAssistantContextWhenConfigured() {
        let params = SupervisorSystemPromptParamsBuilder.build(
            identity: .default(),
            personalProfile: SupervisorPersonalProfile(
                preferredName: "Andrew",
                goalsSummary: "Keep X-Hub shipping while reducing personal admin drag.",
                workStyle: "Prefer clear priorities, direct feedback, and a strong next-step recommendation.",
                communicationPreferences: "Lead with the answer, then explain tradeoffs.",
                dailyRhythm: "Mornings are best for deep work. Late afternoons are better for inbox and follow-up cleanup.",
                reviewPreferences: "Morning brief should stay short. Weekly review should surface overdue follow-ups."
            ),
            personalPolicy: SupervisorPersonalPolicy(
                relationshipMode: .chiefOfStaff,
                briefingStyle: .proactive,
                riskTolerance: .balanced,
                interruptionTolerance: .high,
                reminderAggressiveness: .assertive,
                preferredMorningBriefTime: "08:30",
                preferredEveningWrapUpTime: "18:30",
                weeklyReviewDay: "Friday"
            ),
            preferredSupervisorModelId: "openai/gpt-5.3-codex",
            supervisorModelRouteSummary: "route-summary",
            memorySource: "memory_v1",
            projectCount: 2,
            userMessage: "帮我看下今天最重要的事",
            memoryV1: "memory-line",
            promptMode: .full,
            extraSystemPrompt: nil,
            now: Date(timeIntervalSince1970: 1_773_196_800),
            timeZone: TimeZone(identifier: "Asia/Shanghai") ?? .current,
            locale: Locale(identifier: "en_US_POSIX"),
            hubConnected: true,
            hubRemoteConnected: true
        )

        let prompt = SupervisorSystemPromptBuilder().build(params)

        #expect(prompt.contains("## Personal Assistant Context"))
        #expect(prompt.contains("Preferred user name: Andrew"))
        #expect(prompt.contains("Long-term goals: Keep X-Hub shipping while reducing personal admin drag."))
        #expect(prompt.contains("Work style: Prefer clear priorities, direct feedback, and a strong next-step recommendation."))
        #expect(prompt.contains("Communication preferences: Lead with the answer, then explain tradeoffs."))
        #expect(prompt.contains("Daily rhythm: Mornings are best for deep work. Late afternoons are better for inbox and follow-up cleanup."))
        #expect(prompt.contains("Review preferences: Morning brief should stay short. Weekly review should surface overdue follow-ups."))
        #expect(prompt.contains("Relationship mode: Chief of Staff."))
        #expect(prompt.contains("Briefing style: Proactive."))
        #expect(prompt.contains("Interruption tolerance: High."))
        #expect(prompt.contains("Reminder aggressiveness: Assertive."))
        #expect(prompt.contains("Preferred morning brief time: 08:30"))
        #expect(prompt.contains("Preferred evening wrap-up time: 18:30"))
        #expect(prompt.contains("Preferred weekly review day: Friday"))
    }

    @Test
    func fullModeIncludesRetrievalHelperRuntimeHint() {
        let params = SupervisorSystemPromptParamsBuilder.build(
            preferredSupervisorModelId: "openai/gpt-5.3-codex",
            supervisorModelRouteSummary: "route-summary",
            memorySource: "memory_v1",
            projectCount: 2,
            userMessage: "帮我继续推进",
            memoryV1: "memory-line",
            promptMode: .full,
            extraSystemPrompt: nil,
            retrievalModelSummary: "mlx-community/qwen3-embedding-0.6b-4bit (loaded)",
            now: Date(timeIntervalSince1970: 1_773_196_800),
            timeZone: TimeZone(identifier: "Asia/Shanghai") ?? .current,
            locale: Locale(identifier: "en_US_POSIX"),
            hubConnected: true,
            hubRemoteConnected: true
        )

        let prompt = SupervisorSystemPromptBuilder().build(params)

        #expect(prompt.contains("Retrieval helper models: mlx-community/qwen3-embedding-0.6b-4bit (loaded)"))
        #expect(prompt.contains("Embedding/retrieval helper models are reserved for retrieval and memory lookup."))
    }

    @Test
    func fullModeIncludesStructuredPersonalMemoryContextWhenPresent() {
        let params = SupervisorSystemPromptParamsBuilder.build(
            identity: .default(),
            personalMemorySummary: """
- Structured personal memory items: 4
- Key people: Alex, Taylor
- Open commitments: Reply to Alex · due 2026-03-16 18:00
- Overdue commitments: Reply to Alex · due 2026-03-16 18:00
""",
            preferredSupervisorModelId: "openai/gpt-5.3-codex",
            supervisorModelRouteSummary: "route-summary",
            memorySource: "memory_v1",
            projectCount: 1,
            userMessage: "今天我最容易漏掉什么？",
            memoryV1: "memory-line",
            promptMode: .full,
            extraSystemPrompt: nil,
            now: Date(timeIntervalSince1970: 1_773_196_800),
            timeZone: TimeZone(identifier: "Asia/Shanghai") ?? .current,
            locale: Locale(identifier: "en_US_POSIX"),
            hubConnected: true,
            hubRemoteConnected: true
        )

        let prompt = SupervisorSystemPromptBuilder().build(params)

        #expect(prompt.contains("## Personal Memory Context"))
        #expect(prompt.contains("Treat this as structured long-term memory for the user"))
        #expect(prompt.contains("Key people: Alex, Taylor"))
        #expect(prompt.contains("Overdue commitments: Reply to Alex"))
    }

    @Test
    func fullModeIncludesPersonalFollowUpQueueWhenPresent() {
        let params = SupervisorSystemPromptParamsBuilder.build(
            identity: .default(),
            personalFollowUpSummary: """
- Follow-up queue: 3 open follow-ups | 1 overdue | 1 due soon | 2 people waiting
- People waiting on the user: Alex, Taylor
- Highest-priority follow-ups: Reply to Alex (overdue due 2026-03-16 18:00) | Send agenda to Taylor (due soon due 2026-03-16 20:00)
- Reminder queue: Reply to Alex (overdue) | Send agenda to Taylor (due soon)
""",
            preferredSupervisorModelId: "openai/gpt-5.3-codex",
            supervisorModelRouteSummary: "route-summary",
            memorySource: "memory_v1",
            projectCount: 1,
            userMessage: "我今天最该先回谁？",
            memoryV1: "memory-line",
            promptMode: .full,
            extraSystemPrompt: nil,
            now: Date(timeIntervalSince1970: 1_773_196_800),
            timeZone: TimeZone(identifier: "Asia/Shanghai") ?? .current,
            locale: Locale(identifier: "en_US_POSIX"),
            hubConnected: true,
            hubRemoteConnected: true
        )

        let prompt = SupervisorSystemPromptBuilder().build(params)

        #expect(prompt.contains("## Follow-Up Queue Context"))
        #expect(prompt.contains("People waiting on the user: Alex, Taylor"))
        #expect(prompt.contains("Reminder queue: Reply to Alex (overdue)"))
    }

    @Test
    func fullModeIncludesPersonalReviewContextWhenPresent() {
        let params = SupervisorSystemPromptParamsBuilder.build(
            identity: .default(),
            personalReviewSummary: """
- Personal review schedule: morning 08:30 · evening 18:30 · weekly Friday 18:30
- Due personal reviews: Morning Brief (overdue): Start the day with 1 overdue follow-up, 1 open commitment. Actions: Reply to Alex today | Protect the first focused block
- Recent personal review notes: Weekly Review: Reset the coming week around 2 people waiting.
""",
            preferredSupervisorModelId: "openai/gpt-5.3-codex",
            supervisorModelRouteSummary: "route-summary",
            memorySource: "memory_v1",
            projectCount: 1,
            userMessage: "给我一个 morning brief",
            memoryV1: "memory-line",
            promptMode: .full,
            extraSystemPrompt: nil,
            now: Date(timeIntervalSince1970: 1_773_196_800),
            timeZone: TimeZone(identifier: "Asia/Shanghai") ?? .current,
            locale: Locale(identifier: "en_US_POSIX"),
            hubConnected: true,
            hubRemoteConnected: true
        )

        let prompt = SupervisorSystemPromptBuilder().build(params)

        #expect(prompt.contains("## Personal Review Context"))
        #expect(prompt.contains("Treat this as the user's current daily and weekly personal review loop state."))
        #expect(prompt.contains("Personal review schedule: morning 08:30"))
        #expect(prompt.contains("Due personal reviews: Morning Brief (overdue)"))
        #expect(prompt.contains("Recent personal review notes: Weekly Review"))
    }

    @Test
    func fullModeIncludesTurnRoutingHintWhenPresent() {
        let params = SupervisorSystemPromptParamsBuilder.build(
            identity: .default(),
            turnRoutingDecision: SupervisorTurnRoutingDecision(
                mode: .projectFirst,
                focusedProjectId: "proj-liangliang",
                focusedProjectName: "亮亮",
                focusedPersonName: nil,
                focusedCommitmentId: nil,
                confidence: 0.97,
                routingReasons: [
                    "explicit_project_mention:亮亮",
                    "project_planning_language"
                ]
            ),
            preferredSupervisorModelId: "openai/gpt-5.3-codex",
            supervisorModelRouteSummary: "route-summary",
            memorySource: "memory_v1",
            projectCount: 1,
            userMessage: "亮亮下一步怎么推进",
            memoryV1: "memory-line",
            promptMode: .full,
            extraSystemPrompt: nil,
            now: Date(timeIntervalSince1970: 1_773_196_800),
            timeZone: TimeZone(identifier: "Asia/Shanghai") ?? .current,
            locale: Locale(identifier: "en_US_POSIX"),
            hubConnected: true,
            hubRemoteConnected: true
        )

        let prompt = SupervisorSystemPromptBuilder().build(params)

        #expect(prompt.contains("## Turn Routing Hint"))
        #expect(prompt.contains("Dominant turn mode: project_first"))
        #expect(prompt.contains("Primary memory domain: project_memory"))
        #expect(prompt.contains("Focused project: 亮亮"))
        #expect(prompt.contains("Routing reasons: explicit_project_mention:亮亮 | project_planning_language"))
        #expect(prompt.contains("Answer from project memory first."))
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

    @Test
    func workModeSectionChangesExecutionContract() {
        let conversationPrompt = SupervisorSystemPromptBuilder().build(
            SupervisorSystemPromptParamsBuilder.build(
                workMode: .conversationOnly,
                preferredSupervisorModelId: "openai/gpt-5.3-codex",
                supervisorModelRouteSummary: "route-summary",
                memorySource: "memory_v1",
                projectCount: 1,
                userMessage: "继续推进",
                memoryV1: "memory-line",
                promptMode: .full,
                extraSystemPrompt: nil,
                now: Date(timeIntervalSince1970: 1_773_196_800),
                timeZone: TimeZone(identifier: "Asia/Shanghai") ?? .current,
                locale: Locale(identifier: "en_US_POSIX"),
                hubConnected: true,
                hubRemoteConnected: true
            )
        )
        let guidedPrompt = SupervisorSystemPromptBuilder().build(
            SupervisorSystemPromptParamsBuilder.build(
                workMode: .guidedProgress,
                preferredSupervisorModelId: "openai/gpt-5.3-codex",
                supervisorModelRouteSummary: "route-summary",
                memorySource: "memory_v1",
                projectCount: 1,
                userMessage: "继续推进",
                memoryV1: "memory-line",
                promptMode: .full,
                extraSystemPrompt: nil,
                now: Date(timeIntervalSince1970: 1_773_196_800),
                timeZone: TimeZone(identifier: "Asia/Shanghai") ?? .current,
                locale: Locale(identifier: "en_US_POSIX"),
                hubConnected: true,
                hubRemoteConnected: true
            )
        )
        let automationPrompt = SupervisorSystemPromptBuilder().build(
            SupervisorSystemPromptParamsBuilder.build(
                workMode: .governedAutomation,
                preferredSupervisorModelId: "openai/gpt-5.3-codex",
                supervisorModelRouteSummary: "route-summary",
                memorySource: "memory_v1",
                projectCount: 1,
                userMessage: "继续推进",
                memoryV1: "memory-line",
                promptMode: .full,
                extraSystemPrompt: nil,
                now: Date(timeIntervalSince1970: 1_773_196_800),
                timeZone: TimeZone(identifier: "Asia/Shanghai") ?? .current,
                locale: Locale(identifier: "en_US_POSIX"),
                hubConnected: true,
                hubRemoteConnected: true
            )
        )

        #expect(conversationPrompt.contains("Configured work mode: conversation_only"))
        #expect(conversationPrompt.contains("Only answer direct user requests."))
        #expect(guidedPrompt.contains("Configured work mode: guided_progress"))
        #expect(guidedPrompt.contains("Do not autonomously launch governed coder/skill/tool execution."))
        #expect(automationPrompt.contains("Configured work mode: governed_automation"))
        #expect(automationPrompt.contains("initiate governed coder/skill/tool execution"))
    }

    @Test
    func tightenedPrivacyModeAddsSummaryFirstContract() {
        let prompt = SupervisorSystemPromptBuilder().build(
            SupervisorSystemPromptParamsBuilder.build(
                privacyMode: .tightenedContext,
                preferredSupervisorModelId: "openai/gpt-5.3-codex",
                supervisorModelRouteSummary: "route-summary",
                memorySource: "memory_v1",
                projectCount: 1,
                userMessage: "帮我接上次的进度",
                memoryV1: "memory-line",
                promptMode: .full,
                extraSystemPrompt: nil,
                now: Date(timeIntervalSince1970: 1_773_196_800),
                timeZone: TimeZone(identifier: "Asia/Shanghai") ?? .current,
                locale: Locale(identifier: "en_US_POSIX"),
                hubConnected: true,
                hubRemoteConnected: true
            )
        )

        #expect(prompt.contains("Configured privacy mode: tightened_context"))
        #expect(prompt.contains("prefer concise summaries over replaying verbatim recent dialogue"))
        #expect(prompt.contains("Long-term memory, session handoff capsules, and project state reconstruction remain available"))
        #expect(prompt.contains("Prefer concise summaries over verbatim replay of recent dialogue unless the exact wording is necessary"))
    }
}
