# X-Hub Project AI Context Depth Policy v1

- version: v1.0
- updatedAt: 2026-03-20
- owner: Hub Memory / X-Terminal Project Runtime / Product / QA
- status: proposed-active
- scope: 冻结 `project AI / coder` 的上下文深度模型；明确它既需要 recent project dialogue continuity，也需要独立于 Supervisor 的 project context depth 档位。
- related:
  - `docs/memory-new/xhub-supervisor-recent-raw-context-policy-v1.md`
  - `docs/memory-new/xhub-supervisor-dual-plane-memory-assembly-v1.md`
  - `docs/memory-new/xhub-project-autonomy-tier-and-supervisor-review-protocol-v1.md`
  - `docs/memory-new/xhub-supervisor-memory-serving-contract-v1.md`
  - `x-terminal/work-orders/xt-w3-38-i7-supervisor-continuity-floor-and-context-depth-implementation-pack-v1.md`

## 0) Why This Policy Exists

`project AI` 和 `Supervisor` 都需要 continuity，但它们需要的不是同一种上下文。

`Supervisor` 更像长期聊天助手，重点是：

- 最近在聊什么
- 用户刚刚说了什么
- assistant 刚刚承诺了什么

`project AI` 更像持续执行体，重点是：

- 项目目标和 done definition
- 当前 workflow / active plan
- 最近代码、build、test、log、review、guidance
- 最近 project-relevant 对话

因此不能只给 `project AI` 一个模糊的“多喂点上下文”滑条。

本策略冻结：

`project AI 使用两个独立上下文调节面：recent project dialogue window + project context depth。`

## 1) One-Line Decision

冻结决策：

`Project AI 必须同时拥有 recent project dialogue continuity floor 与独立 project context depth 档位；A-tier 是治理 ceiling，不等于唯一的上下文大小旋钮。`

## 2) Fixed Decisions

1. `project AI` 也需要 recent dialogue continuity。
   - 默认 floor：最近 `16` 条 project-relevant `user/assistant/system execution` 有效消息
   - 这条 floor 解决“继续刚才那步”“这个 blocker 还是那个吗”“按刚才那个方向改”

2. `project AI` 不能只靠 recent chat 工作。
   - 它还必须稳定拿到 project capsule、workflow、review/guidance、execution evidence

3. `Recent Project Dialogue` 与 `Project Context Depth` 分离。
   - 前者解决 continuity
   - 后者解决背景厚度

4. `A-tier` 只定义权限 / 自治 ceiling，不单独决定 memory depth。
   - 高 A-tier 可以允许更深上下文 ceiling
   - 但不能让 `A-tier = context depth`

5. `project AI` 默认不读取完整 personal memory。
   - 只允许 project-relevant selected hints
   - personal review / follow-up / relationship 全量不能默认透传

6. execution artifacts 是一等上下文对象。
   - `diff / changed files / build result / test result / logs / reviewer guidance / pending ack` 必须先于泛泛摘要进入 project AI 装配

## 3) Two Control Surfaces

### 3.1 `Recent Project Dialogue`

推荐用户面：

- 控件名：`Recent Project Dialogue`
- 默认值：`12 pairs`
- 最低值：`8 pairs`
- 高档：`20 pairs`
- 更高：`40 pairs`
- 顶档：`Auto Max`

对象范围：

- 当前项目相关 user/assistant turns
- 当前项目相关 Supervisor guidance / review notes 的投影
- 当前项目相关 execution summaries

固定要求：

- project-relevant continuity floor 不得被 summary 替代
- 低信号过滤应复用 Supervisor 同一套 strict classifier
- 非当前项目噪声不得挤占 project dialogue window

### 3.2 `Project Context Depth`

推荐档位：

1. `Lean`
   - focused project anchor pack
   - current workflow summary
   - latest blocker / next step
   - recent project dialogue floor

2. `Balanced`
   - `Lean` 全量
   - latest review note
   - latest guidance / pending ack guidance
   - selected build/test result digest
   - selected cross-link hints

3. `Deep`
   - `Balanced` 全量
   - expanded active plan / pending steps
   - selected execution evidence refs
   - selected longterm outline
   - drift / conflict summary

4. `Full`
   - `Deep` 全量
   - larger retrieval pack
   - more execution evidence snippets
   - broader decision lineage / blocker lineage

5. `Auto`
   - 根据模型窗口、任务风险、project AI strength、latency budget 自适应选择

## 4) Default Assembly Order For Project AI

每轮推荐装配顺序：

1. `recent_project_dialogue_window`
2. `focused_project_anchor_pack`
3. `active workflow / active plan / pending steps`
4. `latest execution evidence`
   - build/test/logs/diff
5. `latest review note / guidance / pending ack`
6. `selected longterm outline / decision lineage`
7. `selected evidence refs / retrieval snippets`
8. `selected cross-link hints`

固定原则：

- 先 continuity，再 stable anchor，再 execution evidence
- 先当前项目，再更广背景
- 先 project truth，再 selected user preference hints

## 5) What May Enter From Personal Side

默认允许进入 project AI 的 only-if-relevant hints：

- `the user wants a minimal shippable version first`
- `the user prefers concise status updates`
- `Alex is waiting on this deliverable`
- `today's priority is to unblock this project before other work`

默认不允许进入：

- 完整 personal memory items
- 全量 follow-up queue
- 全量 relationship history
- 与项目无关的 personal review state

## 6) Relationship To Governance

Project settings 应至少拆成三条轴：

- `Autonomy Tier` (`A0..A4`)
- `Recent Project Dialogue`
- `Project Context Depth`

推荐约束：

- 低档 A-tier 可以限制 `Full / Auto` ceiling
- 高档 A-tier 可以允许更深 depth ceiling
- 但 depth 不应被 A-tier 偷偷绑定死

S-Tier (`S0..S4`) 不应直接替代 Project Context Depth。

## 7) Diagnostics And Doctor

每轮至少要暴露：

- `recent_project_dialogue_profile`
- `recent_project_dialogue_selected_pairs`
- `project_context_depth`
- `workflow_present`
- `execution_evidence_present`
- `review_guidance_present`
- `cross_link_hints_selected`
- `personal_memory_excluded_reason`

Doctor 至少能回答：

- 这轮 coder 为什么像“只看了几句聊天”
- 这轮 coder 为什么没拿到更全的 project plan
- personal hints 为什么进来了 / 为什么没进来

## 8) Non-Goals

本策略不负责：

- Supervisor 个人助手完整装配
- 用户级 personal memory durable writeback
- `A-tier / S-tier / Heartbeat` UI 细节实现

这些由相邻协议和实现包处理。
