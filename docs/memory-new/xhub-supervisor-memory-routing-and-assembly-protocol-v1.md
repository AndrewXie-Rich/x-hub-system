# X-Hub Supervisor Memory Routing And Assembly Protocol v1

- version: v1.0
- updatedAt: 2026-03-19
- owner: X-Terminal Supervisor / Hub Memory / Hub Policy / QA
- status: proposed-active
- scope: 冻结 `Supervisor` 如何在同一轮里联合使用 `个人助理记忆` 与 `项目治理记忆`，以及如何完成 turn routing、slot-based assembly、after-turn writeback 与 explainability。
- related:
  - `docs/memory-new/xhub-supervisor-memory-serving-contract-v1.md`
  - `docs/memory-new/xhub-memory-serving-profiles-and-adaptive-context-v1.md`
  - `docs/memory-new/xhub-memory-model-preferences-and-routing-contract-v1.md`
  - `docs/memory-new/xhub-memory-scheduler-and-memory-core-runtime-architecture-v1.md`
  - `docs/memory-new/xhub-project-autonomy-tier-and-supervisor-review-protocol-v1.md`
  - `x-terminal/work-orders/xt-w3-35-supervisor-memory-retrieval-progressive-disclosure-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-38-supervisor-personal-longterm-assistant-implementation-pack-v1.md`
  - `x-terminal/Sources/Supervisor/SupervisorManager.swift`
  - `x-terminal/Sources/Supervisor/SupervisorPersonalMemoryStore.swift`
  - `x-terminal/Sources/Supervisor/SupervisorPersonalReviewNoteStore.swift`
  - `x-terminal/Sources/Supervisor/SupervisorFollowUpLedger.swift`

## 0) Why This Protocol Exists

当前系统已经分别在推进两条线：

- `Supervisor` 作为长期个人助手，需要稳定理解：
  - 用户是谁
  - 用户偏好什么
  - 谁在等用户
  - 哪些承诺和周期事务正在逼近
- `Supervisor` 作为项目总控，需要稳定理解：
  - 项目目标是什么
  - 当前做到哪
  - 哪些 blocker / review / guidance 正在生效
  - 哪个 project 值得现在优先介入

如果把这两类记忆直接拼成一大段 prompt，会很快出现 4 个问题：

1. 个人记忆和项目记忆互相污染，`truth scope` 变模糊。
2. 普通闲聊会被大段项目噪声拖慢，项目 review 又会被个人细节稀释。
3. after-turn 很难知道这轮到底该把新信息写回哪里。
4. 用户无法理解“这轮为什么答成这样”，只能看到黑盒结果。

因此本协议冻结一条明确路线：

`Supervisor 可以在同一轮同时使用个人记忆和项目记忆，但必须通过 turn routing + slot-based assembly + scope-aware writeback 来完成，而不是 full dump。`

## 1) One-Line Decision

冻结决策：

`Supervisor 每轮都可以同时消费 personal memory 与 project memory，但必须先判定主域，再以固定 slot 装配 supporting memory，并在 after-turn 时按 scope 正确写回。`

换句话说：

- 可以同时喂
- 但不能混成一个 blob
- 必须有主次
- 必须可解释
- 必须能把新事实写回对的仓

## 2) Fixed Decisions

1. `5-layer memory` 继续是统一 truth source。
   - 本协议不新增第二套 Supervisor 私有真相源。
   - 个人和项目的 durable truth 仍然属于 Hub-first memory plane。

2. `storage plane` 与 `serving plane` 继续分离。
   - durable truth 存什么
   - 这一轮给 Supervisor 看什么
   - 这是两个不同问题

3. 每轮必须先产出一个 `dominant mode`。
   - `personal_first`
   - `project_first`
   - `hybrid`
   - `portfolio_review`

4. `dialogue window` 是 continuity floor，不可被任何模式省略。
   - 用户最近说了什么
   - Supervisor 刚刚承诺了什么
   - 这必须永远在场

5. 个人记忆与项目记忆必须分 scope 存储。
   - `user_scope`
   - `project_scope`
   - `cross_link_scope`
   - `portfolio_runtime_scope`

6. `cross-link` 必须 first-class。
   - “Alex 在等亮亮 demo”
   - “这次会议是为了项目亮亮”
   - 这类连接事实不能只躲在 prose 里

7. `after-turn writeback` 是协议必需步骤，不是可选优化。
   - 每轮结束必须判断：
     - 该不该写
     - 写到哪
     - 写成什么类型

8. `Project coder` 默认不能直接读完整个人长期记忆。
   - project execution 默认只消费项目上下文
   - 仅允许读取最小必要的 user execution preferences

9. `Project coder` 默认不能直接写用户 canonical personal memory。
   - 可以提出 candidate
   - 最终 durable promotion 由 Supervisor / Hub policy 决定

10. 任何混合记忆装配都不能绕过 `X-Constitution`、Hub policy、grant、kill-switch 与 audit。

11. `session participation class` 必须先于 durable writeback / promotion 生效。
   - 未解析 class 的 session 默认不得做 durable writeback。

12. 本协议是 serving / assembly 协议，不是第二个 memory model chooser。
   - `dominant mode` 只回答“这一轮怎么装配 personal/project/portfolio memory”。
   - 用户选哪个 AI 维护 memory，仍由上游 `memory_model_preferences -> Scheduler -> Worker -> Writer + Gate` 决定。

## 2.1) Upstream Control-Plane Dependency

本协议固定消费上游 Hub 已解析好的控制面 truth：

- 用户配置的 `memory_model_preferences`
- 上游命中的 memory mode profile（例如 `assistant_personal` / `project_code`）
- route diagnostics
  - `route_source`
  - `route_reason_code`
  - `fallback_applied`
  - `fallback_reason`
  - `model_id`
- `session_participation_class`
- `write_permission_scope`

本协议固定不做：

- 不本地重跑 `memory_model_router`
- 不本地覆盖用户选择的 memory maintenance model
- 不把 `dominant mode` 误当成“重新选这轮 memory model”

关系必须明确：

- upstream memory mode profile 解决“这条 memory 控制面按哪种模式 bucket 执行”
- `dominant mode` 解决“这一轮 Supervisor 回答时 personal/project/portfolio 哪个是主域”

两者可以相关，但不是同一层概念。

## 2.2) Wave-1 A5 承接：Session Participation Clamp

来自 `docs/memory-new/xhub-memory-open-source-reference-wave1-execution-pack-v1.md` 的 `session memory participation classes`，在本协议下的正式承接范围如下：

- 本协议只冻结 Supervisor 与 downstream worker 的 routing、assembly、writeback 参与语义；不新增平行 memory core，也不把 participation class 扩成新的产品档位系统。
- 每轮或每个派生 session 至少要先解析出 3 个字段：
  - `session_participation_class`
  - `write_permission_scope`
  - `participation_resolve_reason`
- `session_participation_class` 必须在 `turn routing` 之前可得，最迟也必须在 slot assembly 请求 deep recall 之前、after-turn writeback 之前完成；解析失败默认 fail-closed 为不可 durable writeback。

### 2.1.1 Frozen Taxonomy

- `ignore`
  - 不参与 personal/project/cross-link durable memory 循环。
  - 允许使用的输入仅限显式测试夹具、replay 材料或当前回放上下文。
  - 不得请求 deep recall，不得产生日志之外的 durable writeback。
- `read_only`
  - 可消费 Supervisor serving objects 与 PD refs。
  - 可做 reasoning、review、candidate 生成。
  - 不得把结果 durable promote 到 `user_scope / project_scope / cross_link_scope`。
- `scoped_write`
  - 可消费 serving objects，并在 `write_permission_scope` 明确允许的 scope 内执行 durable writeback。
  - 任何 scope 缺失、scope mismatch、policy deny 都必须阻断 durable promotion。

### 2.1.2 Default Assignments

- 默认 `scoped_write`：
  - `interactive_user_turn`
  - `supervisor_direct_review`
  - `supervisor_follow_up`
- 默认 `read_only`：
  - `subagent`
  - `lane_worker`
  - `scheduled_heartbeat`
  - `portfolio_watchdog`
  - `nightly_review`
- 默认 `ignore`：
  - `replay`
  - `test`
  - `synthetic`
  - `operator_probe`
- `scheduled_heartbeat / portfolio_watchdog / nightly_review` 只有在 workflow 显式要求结构化 review writeback，且携带 `audit_ref + focused scope + promotion reason` 时，才允许临时提升为 `scoped_write`。

### 2.1.3 Clamp Rules

- `ignore` session 允许走诊断或回放，但不得装配 durable serving objects 进入正常 writeback 链。
- `read_only` session 可参与 route / assemble / answer，但 after-turn 最多只能落 `working_set_only` 或显式 candidate。
- `scoped_write` session 才允许进入 `user_scope / project_scope / cross_link_scope` promotion；且只能写入 `write_permission_scope` 覆盖的 scope。
- 下游 worker 的 authority 永远不能因为拿到了更多上下文而自动升格；authority 只能来自上游已解析的 participation class 与 Hub policy。

## 3) Scope Model

### 3.1 `user_scope`

用于长期个人助手真相。

最少承载：

- preferred name
- communication preferences
- work style / habit
- stable preference
- relationship facts
- commitments
- recurring obligations
- personal review state
- follow-up state

### 3.2 `project_scope`

用于项目治理真相。

最少承载：

- project goal
- done definition
- constraints
- approved decisions
- current state
- next step
- blockers
- plan / job / review / guidance / ack
- project evidence / risk / verification

### 3.3 `cross_link_scope`

用于“人、承诺、项目”之间的连接事实。

最少承载：

- person linked to project
- commitment backed by project
- meeting / deliverable linked to project
- stakeholder waiting on project output
- personal reminder caused by project state

### 3.4 `portfolio_runtime_scope`

用于 Supervisor 全局盘面。

最少承载：

- portfolio brief
- project ordering
- queue pressure
- heartbeat snapshots
- project notification state
- pending grants / runtime incidents

## 4) Canonical Serving Objects

本协议冻结 5 个核心 serving objects。

### 4.1 `dialogue_window`

作用：

- 保证连续对话不丢线
- 承接“他 / 这个 / 刚才那个 / 就按这个继续”

最少字段：

- `messages`
- `recent_user_intent`
- `recent_assistant_commitments`
- `current_turn_refs`
- `window_profile`

固定要求：

- 不允许以“只有摘要、没有最近对话”代替 dialogue continuity
- user / assistant 各自发言都算 continuity 真相

### 4.2 `personal_capsule`

作用：

- 提供长期个人助手背景
- 让 Supervisor 不是只会项目调度

最少字段：

- `preferred_name`
- `identity_digest`
- `stable_preferences`
- `habit_digest`
- `relationship_digest`
- `open_commitments`
- `due_personal_reviews`
- `follow_up_queue`
- `today_personal_constraints`

固定要求：

- `preferred_name` 不得因为 project focus 被挤掉
- `follow_up_queue` 与 `due_personal_reviews` 默认属于一等对象

### 4.3 `focused_project_capsule`

作用：

- 让 Supervisor 能对当前项目形成稳定锚点

最少字段：

- `project_id`
- `display_name`
- `goal`
- `done_definition`
- `constraints_hard_lines`
- `approved_decisions`
- `current_state`
- `next_step`
- `top_blocker`
- `active_plan_summary`
- `latest_review_note`
- `latest_guidance`
- `pending_ack_guidance`
- `risk_digest`

固定要求：

- `done_definition` 不能退化成“最近一步做什么”
- `latest_guidance` 不能覆盖更高等级 approved decisions

### 4.4 `portfolio_brief`

作用：

- 给 Supervisor 一个默认全局入口
- 避免一上来就陷进单项目 tunnel vision

最少字段：

- `portfolio_summary`
- `recommended_priority_order`
- `active_projects_top_n`
- `blocked_projects_top_n`
- `focus_candidate_project_id`
- `last_global_change_cursor`

### 4.5 `cross_link_refs`

作用：

- 显式承载个人与项目的连接事实

最少字段：

- `link_id`
- `link_kind`
- `summary`
- `person_name`
- `project_id`
- `backing_record_refs`
- `freshness_hint`

`link_kind` 最少支持：

- `person_waiting_on_project`
- `commitment_depends_on_project`
- `meeting_about_project`
- `follow_up_triggered_by_project`
- `user_priority_constrained_by_project`

## 5) Turn Modes

固定边界：

- 本节定义的是 Supervisor serving modes，不是 Hub memory maintenance modes。
- `personal_first / project_first / hybrid / portfolio_review` 不能替代上游 `assistant_personal / project_code` 等 control-plane profile。
- Supervisor 只能消费上游 mode/profile/route truth，再决定这一轮怎么装配 slots。

### 5.1 `personal_first`

适用：

- 用户在问今天怎么安排
- 用户在问谁在等我
- 用户在问我自己偏好、习惯、承诺
- 普通聊天主要在谈用户本人，而不是某个项目

默认装配：

- `dialogue_window`: full
- `personal_capsule`: full
- `portfolio_brief`: light
- `focused_project_capsule`: light or omitted
- `cross_link_refs`: on demand

### 5.2 `project_first`

适用：

- 用户明确在谈某个 project
- 当前问题是计划、blocker、review、执行方案
- 当前意图是推进项目，不是安排个人生活

默认装配：

- `dialogue_window`: full
- `personal_capsule`: light
- `portfolio_brief`: light
- `focused_project_capsule`: full
- `cross_link_refs`: on demand

### 5.3 `hybrid`

适用：

- 问题同时涉及人和项目
- 问题同时涉及今天安排和项目交付
- 需要在“项目推进”和“谁在等结果”之间做平衡

默认装配：

- `dialogue_window`: full
- `personal_capsule`: medium
- `portfolio_brief`: light
- `focused_project_capsule`: medium
- `cross_link_refs`: full

### 5.4 `portfolio_review`

适用：

- 用户在问现在整体应该先抓什么
- Supervisor 在做 heartbeat / review / overview
- 用户没锁定单个项目，但在问全局优先级

默认装配：

- `dialogue_window`: full
- `personal_capsule`: light
- `portfolio_brief`: full
- `focused_project_capsule`: only focused candidate
- `cross_link_refs`: selected

## 6) Turn Routing Rules

每轮先做 `turn routing`，输出：

- `mode`
- `focused_project_id`
- `focused_person_name`
- `focused_commitment_id`
- `routing_confidence`

补充要求：

- `turn routing` 只决定本轮回答的装配重心。
- 若上游已给出 memory route truth，Supervisor 应在 explainability / writeback classification 中原样消费，不得本地改写其 machine-readable 语义。

### 6.1 Resolution Order

固定顺序：

1. 先看显式项目提及
2. 再看显式人物 / 承诺提及
3. 再看当前焦点寄存器
4. 再看 portfolio 推荐焦点
5. 若仍不明确，回落到 `personal_first` 或 `portfolio_review`

### 6.2 Routing Signals

最少信号集：

- explicit project name / alias
- explicit person name
- phrases like `这个项目 / 刚才那个 / 亮亮 / Alex`
- verbs like `推进 / 交付 / review / 安排 / 回复 / 提醒`
- current blocker state
- due follow-up state
- due review state
- last focused project / person pointer

### 6.3 Ambiguity Rule

如果项目和个人信号都很强，但主语不清晰：

- 默认进入 `hybrid`
- 不要武断只走单项目或只走个人摘要

如果连 `hybrid` 都无法给出可靠答复：

- 允许补 1 个短 follow-up 问题
- 不允许为了省事 fabricated focus

## 7) Focus Pointers

为了让对话丝滑，Supervisor 必须维护短期焦点寄存器。

最少字段：

- `current_project_id`
- `current_project_aliases`
- `current_person_name`
- `current_commitment_id`
- `current_topic_digest`
- `last_turn_mode`
- `last_seen_delta_cursor`

作用：

- 解析“他 / 这个 / 按刚才那个继续”
- 减少用户反复重述
- 为 portfolio -> project drill-down 提供连续性

固定边界：

- pointer 只是 continuity helper，不是 durable truth
- pointer 过期后必须允许回落重判

## 8) Slot-Based Assembly

本协议冻结：

`Supervisor` 每轮拿到的上下文，不是自由拼接，而是固定 slot 装配。

### 8.1 Required Slots

每轮至少有：

- `slot.dialogue_window`
- `slot.personal_capsule_light_or_full`
- `slot.portfolio_brief_light_or_full`

### 8.2 Conditional Slots

按 routing 决定是否装配：

- `slot.focused_project_capsule`
- `slot.cross_link_refs`
- `slot.evidence_pack`

### 8.3 Fixed Assembly Output

最少输出对象：

- `turn_mode`
- `focus_pointers`
- `selected_slots`
- `selected_refs`
- `omitted_slots`
- `assembly_reason`

### 8.4 Assembly Guardrails

1. 不允许 personal/project memory 直接原文并排全量注入。
2. 不允许 `focused_project_capsule` 缺少 `goal + done_definition`。
3. 不允许 `personal_capsule` 缺少 `preferred_name / due reviews / follow-up queue` 的 visibility。
4. `cross_link_refs` 必须优先于“让模型自己猜人和项目关系”。

## 9) After-Turn Writeback

每轮收尾后，必须做 `after-turn writeback classification`。

输出类型最少包含：

- `write_user_scope`
- `write_project_scope`
- `write_cross_link_scope`
- `working_set_only`
- `drop_as_noise`

### 9.0 Participation Clamp

在进入 `9.1 ~ 9.5` 前，必须先应用 `session_participation_class`：

- 未解析 class：默认不做 durable writeback，并返回 `writeback_block_reason=session_participation_unresolved`
- `ignore`：强制 `drop_as_noise`
- `read_only`：最多只能 `working_set_only`；`user_scope / project_scope / cross_link_scope` promotion 一律阻断
- `scoped_write`：只允许写入 `write_permission_scope` 显式覆盖的 scope；缺 scope、scope mismatch、policy deny 均返回 `writeback_block_reason=session_write_scope_blocked`

### 9.1 Promote To `user_scope`

满足任一条件时允许晋升：

- 用户显式要求“记住”
- 属于稳定偏好 / 习惯 / 关系事实
- 形成长期承诺
- 形成 recurring obligation
- 对后续 personal assistant 行为高度重要

### 9.2 Promote To `project_scope`

满足任一条件时允许晋升：

- 项目 goal / done / hard constraint
- approved decision
- verified blocker
- active plan change
- review note / guidance / ack
- evidence-backed result

### 9.3 Promote To `cross_link_scope`

满足任一条件时允许晋升：

- 某人明确在等某项目结果
- 某个 personal commitment 明确依赖某项目状态
- 某个 meeting / reminder / deliverable 明确绑定项目

### 9.4 Keep In `working_set_only`

适用于：

- 仅本轮有效的细碎描述
- 还没验证的临时猜测
- 不足以 durable promotion 的一次性语句

### 9.5 Drop

适用于：

- assistant 自己的无证据猜测
- 不稳定寒暄
- 与 durable continuity 无关的噪声

## 10) Promotion Metadata

所有 durable writeback 建议至少带：

- `scope`
- `record_type`
- `confidence`
- `source_ref`
- `why_promoted`
- `last_verified_at`
- `review_or_expiry_at`
- `audit_ref`

固定要求：

- 没有 `why_promoted` 的 durable promotion 视为不完整
- 没有 `source_ref` 的跨域连接事实不应晋升

## 11) Access And Authority Boundaries

### 11.1 `Supervisor`

默认可读：

- `user_scope`
- `project_scope`
- `cross_link_scope`
- `portfolio_runtime_scope`

默认可写：

- user/project/cross-link 的 candidate
- durable writeback（仅当该轮 `session_participation_class = scoped_write`）

但仍受：

- Hub policy
- Constitution
- audit
- grant / kill-switch

### 11.2 `Project Coder`

默认参与 class：

- `read_only`

默认可读：

- `project_scope`
- 最小必要的 execution preferences

默认不可读：

- 完整 `user_scope`
- 完整 relationship / private follow-up / personal commitments

默认可写：

- project candidate
- structured execution refs
- `working_set_only`

默认不可直接写：

- user scope durable truth
- cross-link durable truth
- project scope durable truth

只有当上游 `Supervisor + Hub policy` 把该轮显式提升为 `scoped_write`，且 scope 绑定仍落在 `project_scope` 内时，`Project Coder` 才允许执行 project durable writeback。

### 11.3 User Privacy Clamp

即使 `Supervisor` 可同时联合两类记忆，也不意味着任何下游执行体都可见。

因此协议冻结：

- `assembly visibility != downstream authority`

## 12) Explainability Surface

为了让用户知道系统“为什么这样回答”，每轮至少应有轻量 explainability。

最少字段：

- `primary_memory_domain`
- `supporting_memory_domains`
- `focused_project_label`
- `focused_person_label`
- `session_participation_class`
- `write_permission_scope`
- `writeback_block_reason`
- `writeback_summary`

推荐 UI 文案：

- `本轮主用：个人记忆；辅助：项目记忆`
- `本轮主用：项目记忆（亮亮）；辅助：个人 follow-up`
- `本轮主用：混合记忆；连接：Alex -> 亮亮 demo`
- `本轮会话级别：read_only；只读消费项目记忆，durable 写回已阻断`

## 13) Failure Modes And Guardrails

### 13.1 Do Not Fabricate Focus

如果没有可靠项目锚点：

- 不允许伪装成“已经知道你指哪个项目”
- 可以回落 `portfolio_review`
- 或追问 1 个短问题

### 13.2 Do Not Cross-Contaminate

不允许：

- 把项目 blocker 写成个人承诺
- 把私人偏好写成项目 hard constraint
- 把暂时跟进事项提升为长期关系事实

### 13.3 Do Not Overfeed

即使模型窗口变大，也不允许默认 full dump。

优先级仍然是：

- route
- assemble
- expand only if needed

### 13.4 Do Not Lose Supporting Domain

即使 `project_first`，也不应完全丢掉与执行相关的 personal constraints。

即使 `personal_first`，也不应完全丢掉当下最重要的 project pressure。

## 14) Serving Matrix

| Turn Mode | Dialogue Window | Personal Capsule | Focused Project Capsule | Portfolio Brief | Cross-Link Refs |
| --- | --- | --- | --- | --- | --- |
| `personal_first` | full | full | light / omitted | light | on demand |
| `project_first` | full | light | full | light | on demand |
| `hybrid` | full | medium | medium | light | full |
| `portfolio_review` | full | light | selected | full | selected |

固定说明：

- `light` 不等于无；表示只注入最小必要字段
- `medium` 表示 capsule 级摘要
- `full` 表示当前档位允许的完整 serving object

## 15) Implementation Alignment

当前实现最接近的已有部件：

- `SupervisorPersonalMemoryStore`
- `SupervisorPersonalReviewNoteStore`
- `SupervisorFollowUpLedger`
- `SupervisorPortfolioSnapshot`
- `SupervisorManager` 的 working set / after-turn lifecycle / memory board explainability

下一阶段推荐直接收口成 4 个实现点：

1. `SupervisorTurnRouter`
   - 负责产出 `personal_first / project_first / hybrid / portfolio_review`
   - 消费上游 Hub route/mode truth，但不重跑 `memory_model_router`
2. `SupervisorTurnContextAssembler`
   - 负责固定 slot 装配
   - 消费 `assistant_personal / project_code` 等上游 mode bucket，只做 assembly，不做模型重选
3. `SupervisorAfterTurnWritebackClassifier`
   - 负责 `user / project / cross-link / working-set-only`
4. `SupervisorCrossLinkStore`
   - 负责 durable person-project links

## 16) One-Sentence Conclusion

`Supervisor` 要丝滑地同时使用个人助理记忆和项目管理记忆，正确答案不是“把两边记忆全塞进去”，而是：

`每轮先判主域，再按固定 slots 装配 supporting memory，并在 after-turn 把新事实写回正确 scope。`
