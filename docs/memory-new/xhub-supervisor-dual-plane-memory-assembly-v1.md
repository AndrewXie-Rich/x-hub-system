# X-Hub Supervisor Dual-Plane Memory Assembly v1

- version: v1.0
- updatedAt: 2026-03-20
- owner: Hub Memory / X-Terminal Supervisor / Product / QA
- status: proposed-active
- scope: 冻结 `Supervisor` 同时做个人长期助手和项目 review / portfolio governor 时的记忆装配模型；明确单一 Supervisor 身份下的 `assistant plane + project plane + cross-link plane + continuity lane`。
- related:
  - `docs/memory-new/xhub-supervisor-memory-routing-and-assembly-protocol-v1.md`
  - `docs/memory-new/xhub-memory-model-preferences-and-routing-contract-v1.md`
  - `docs/memory-new/xhub-supervisor-recent-raw-context-policy-v1.md`
  - `docs/memory-new/xhub-project-ai-context-depth-policy-v1.md`
  - `docs/memory-new/xhub-supervisor-memory-serving-contract-v1.md`
  - `x-terminal/work-orders/xt-w3-38-i7-supervisor-continuity-floor-and-context-depth-implementation-pack-v1.md`

## 0) Why This Contract Exists

用户面对的是一个 `Supervisor`，而不是两个分裂的机器人。

它既要能：

- 正常闲聊
- 记住用户本人是谁、偏好什么、答应过什么
- review 项目、给执行方案、管 portfolio
- 在个人事务和项目交付之间做平衡

因此产品层面应当是“一个 Supervisor”，但内核层面不能把 personal / project / cross-link / recent chat 混成一坨 blob。

本合同冻结：

`一个 Supervisor 身份，多个记忆平面，按 turn routing 决定主域，再按固定顺序装配。`

## 1) One-Line Decision

冻结决策：

`Supervisor 采用 single-identity + dual-plane assembly：对用户表现为一个长期助手，但内部始终把 assistant memory plane 与 project memory plane 分域存储，并通过 continuity lane 与 cross-link plane 在每轮装配时自然合流。`

## 2) Fixed Decisions

1. `一个 Supervisor 身份` 保持不变。
   - 不拆成“个人助理 Supervisor”与“项目 Supervisor”两个对话入口
   - 不要求用户先声明“现在进入 personal 模式 / project 模式”

2. `记忆分域` 是硬边界。
   - `assistant plane` 不等于 `project plane`
   - durable truth 仍分别落在：
     - `user_scope`
     - `project_scope`
     - `cross_link_scope`
     - `portfolio_runtime_scope`

3. `continuity lane` 是共享底座。
   - 最近原始对话对 personal turn 和 project turn 都成立
   - recent raw dialogue 不是 personal memory 的附属物，也不是 project capsule 的附属物

4. `turn routing` 继续决定主域，不决定唯一域。
   - 每轮都有 dominant mode
   - 但 supporting plane 不会完全消失
   - `dominant mode` 只决定这轮 personal/project/cross-link 的装配重心，不是新的 memory model chooser。

5. `cross-link` 必须是一等对象。
   - “谁在等哪个项目”
   - “哪个承诺依赖哪个项目”
   - “今天安排和项目交付之间的冲突”
   这些都不能只藏在 prose 里

6. 摘要不能替代 recent raw dialogue。
   - rolling digest 是补充
   - personal/project capsule 是补充
   - recent raw dialogue 先在场

7. `project coder` 默认不读取完整 assistant plane。
   - 可以读取项目相关的 selected cross-link 或 user preference hint
   - 但不能默认拿到完整 personal memory / follow-up / personal review

## 2.1) Upstream Control-Plane Dependency

本合同固定消费上游已解析好的 control-plane truth：

- `memory_model_preferences`
- upstream mode profile（例如 `assistant_personal / project_code`）
- route truth / explain
- `session_participation_class`
- `write_permission_scope`

固定不做：

- 不重跑 `memory_model_router`
- 不本地替用户重选 memory maintenance model
- 不把 dual-plane assembly 变成第二套 profile parser

## 3) The Four Memory Lanes

### 3.1 `continuity_lane`

作用：

- 保证连续聊天不丢线
- 让 `他 / 这个 / 刚才那个 / 按这个继续` 有锚点
- 承接最近用户意图和最近 assistant 承诺

来源：

- recent raw dialogue window
- rolling dialogue digest
- focus pointers

### 3.2 `assistant_plane`

作用：

- 让 Supervisor 像真正的长期个人助手
- 记住用户是谁、习惯什么、哪些事没跟、谁在等回复

最少对象：

- `personal_capsule`
- `follow_up_queue`
- `personal_review_state`
- `assistant_commitment_digest`

默认 scope：

- `user_scope`
- `portfolio_runtime_scope`（仅个人助手运行态部分）

### 3.3 `project_plane`

作用：

- 让 Supervisor 能稳定 review 项目、做推进方案、判断是否跑偏

最少对象：

- `portfolio_brief`
- `focused_project_capsule`
- `workflow_slice`
- `latest_review_note`
- `latest_guidance`
- `selected_evidence_refs`

默认 scope：

- `project_scope`
- `portfolio_runtime_scope`

### 3.4 `cross_link_plane`

作用：

- 把 personal 与 project 连起来，而不是简单拼接

最少对象：

- `person_waiting_on_project`
- `commitment_depends_on_project`
- `today_plan_conflicts_with_project`
- `project_outcome_blocks_personal_commitment`

默认 scope：

- `cross_link_scope`

## 4) Turn Modes And Default Assembly

### 4.1 `personal_first`

适用：

- 用户在聊自己
- 用户在问今天安排、谁在等我、我最近漏了什么
- 问题主要不是某个项目的执行方案

默认装配：

- `continuity_lane`: full
- `assistant_plane`: full
- `project_plane`: light
- `cross_link_plane`: on demand

### 4.2 `project_first`

适用：

- 用户明确在谈某个项目
- 当前问题是 plan、blocker、review、交付方案、执行纠偏

默认装配：

- `continuity_lane`: full
- `assistant_plane`: light
- `project_plane`: full
- `cross_link_plane`: selected

### 4.3 `hybrid`

适用：

- 用户在问“今天怎么安排，但项目也得交付”
- 问题同时涉及 personal commitments 和 project delivery
- 需要权衡谁在等、什么最急、哪个项目影响最大

默认装配：

- `continuity_lane`: full
- `assistant_plane`: medium
- `project_plane`: medium
- `cross_link_plane`: full

### 4.4 `portfolio_review`

适用：

- 用户在问现在全局先抓什么
- Supervisor 在做 heartbeat / review / overview
- 尚未锁定单个项目

默认装配：

- `continuity_lane`: full
- `assistant_plane`: light
- `project_plane`: portfolio-first
- `cross_link_plane`: selected

## 5) Assembly Order

每轮都按以下顺序装配：

1. `recent raw dialogue window`
2. `focus pointers`
   - 当前项目
   - 当前人
   - 当前承诺
   - 当前主题摘要
3. `dominant plane`
4. `supporting plane`
5. `cross_link_plane`
6. `rolling_dialogue_digest`
7. `selected evidence refs / retrieval snippets`

固定原则：

- recent raw dialogue 优先于所有摘要
- focus pointers 优先于启发式猜测
- cross-link 负责“连起来”，不是负责“代替主域”
- evidence refs 用于 grounding，不是用来重播整段历史

## 6) Writeback Rules

after-turn writeback 继续走 scope-aware classification。

### 6.1 Promote To `user_scope`

只允许提升：

- 稳定偏好
- 稳定习惯
- 关系事实
- 持续承诺
- 明确要求记住的个人信息

不允许提升：

- 一次性寒暄
- 模糊推测
- 未确认的临时安排

### 6.2 Promote To `project_scope`

只允许提升：

- 项目 goal / done / non-goal
- blocker / next-step / approved decision
- stable workflow facts
- 被确认的新约束

不允许提升：

- 普通泛聊里的猜测
- 没聚焦项目时的模糊项目结论

### 6.3 Promote To `cross_link_scope`

只允许提升：

- 人与项目的明确依赖
- 承诺与项目的明确依赖
- 项目变化对个人 follow-up 的明确影响

### 6.4 Keep In `working_set_only`

用于：

- 仍在发酵中的普通聊天
- 最近连续讨论但尚不稳定的判断
- 只该服务 continuity、不该立即 durable promote 的内容

## 7) Project Coder Boundary

`project coder` 与 `Supervisor` 不应拿到同一份上下文。

冻结边界：

1. `project coder` 默认拿：
   - `project_plane`
   - 受限 `continuity_lane`（仅 project-relevant）
   - selected `cross_link hints`

2. `project coder` 默认不拿：
   - 完整 `assistant_plane`
   - personal review 全量
   - personal follow-up 全量
   - 非项目相关的人际关系与个人偏好

3. 只有当 cross-link / policy 显式允许时，`project coder` 才能拿到：
   - `user prefers async updates`
   - `Alex is waiting on this demo`
   - `the user wants a minimal web prototype first`

## 8) Explainability

Supervisor Memory Board / Doctor / debug trace 至少要说明：

- `dominant_mode`
- `continuity_lane_status`
- `assistant_plane_depth`
- `project_plane_depth`
- `cross_link_refs_selected`
- `writeback_scope_summary`
- `why_this_plane_won`

这样才能回答：

- 这轮为什么像 personal assistant
- 这轮为什么像项目 review
- 这轮为什么同时看了两边
- 为什么某条信息被写进了 personal / project / cross-link

## 9) Non-Goals

本合同不负责：

- project AI 的 context depth 细节档位
- A-Tier / S-Tier / Heartbeat / Review 的治理表面
- full-thread export 或 remote prompt full dump

这些由相邻协议单独冻结。
