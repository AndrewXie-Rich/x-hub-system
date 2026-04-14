# X-Hub Supervisor Recent Raw Context Policy v1

- version: v1.0
- updatedAt: 2026-03-20
- owner: Hub Memory / X-Terminal Supervisor / Product / QA
- status: proposed-active
- scope: 冻结 `Supervisor` 最近原始对话窗口的硬底线、用户可调档位、低信号过滤规则、滚动摘要接力方式，以及它与现有 memory serving plane 的关系。
- related:
  - `docs/memory-new/xhub-supervisor-memory-routing-and-assembly-protocol-v1.md`
  - `docs/memory-new/xhub-supervisor-memory-serving-contract-v1.md`
  - `docs/memory-new/xhub-memory-serving-profiles-and-adaptive-context-v1.md`
  - `docs/memory-new/xhub-supervisor-dual-plane-memory-assembly-v1.md`
  - `x-terminal/work-orders/xt-w3-38-i7-supervisor-continuity-floor-and-context-depth-implementation-pack-v1.md`

## 0) Why This Policy Exists

当前协议已经写明：`dialogue_window` 是 continuity floor，不能被省略，也不能被“只有摘要、没有最近对话”代替。

但 runtime 还没有把这件事做成真正的硬规则：

- 最近对话更多来自 XT 本地 `messages` 缓存，而不是 Hub-first durable thread
- `dialogue_window` 会继续被 `m1_execute` 的 budget、`workingSetMaxChars`、`lineCap`、`preferTail` 二次压缩
- 用户感知到的是“Supervisor 好像马上就忘了刚才说过什么”

所以本策略冻结的不是新 memory 内核，而是：

`Supervisor 最近原始上下文必须怎样保真、怎样可调、怎样在预算压力下仍然留在 prompt 里。`

## 1) One-Line Decision

冻结决策：

`Supervisor 必须始终带入一段不可被 serving-profile 压掉的 recent raw dialogue window；该窗口保留 hard floor，并允许用户在 floor 之上调高 ceiling。`

换句话说：

- continuity floor 继续存在
- 但不再固定死成一个隐藏常数
- 用户可以调高最近原始上下文
- 系统仍然要防止“无限制 full dump”

## 2) Fixed Decisions

1. `Conversation Continuity Floor` 冻结为不可降的 runtime contract。
   - 默认口径：最近 `16` 条 `user/assistant` 有效消息（约 `8` 个来回）
   - 这条 floor 不得被任何 `m0..m4` serving profile 继续裁掉
   - 这条 floor 必须先于摘要、capsule、evidence 被保护

2. `Recent Raw Context` 与 `Serving Profile` 分离。
   - `Serving Profile` 解决“看多深、证据多厚、预算多大”
   - `Recent Raw Context` 解决“最近原始对话保留多少”
   - 不允许再把这两个问题混成一个默认 `m1_execute`

3. 用户面显示一个滑条，但 runtime 必须映射为离散策略包。
   - 推荐用户可见名：`Recent Raw Context`
   - 推荐档位：`8 pairs` / `12 pairs` / `20 pairs` / `40 pairs` / `Auto Max`
   - 不推荐用户面暴露“无限 full dump”

4. 最近原始上下文必须尽量原样保留。
   - 允许：脱敏、极长消息截断、最小规范化
   - 不允许：先摘要，再把摘要当成 recent raw context
   - recent raw context 与 rolling digest 必须并存，而不是互相替代

5. `低信号过滤` 必须极窄。
   - 只有纯寒暄、纯 ACK、纯填充词才允许从 raw window 排除
   - 只要一句话里带了新事实、代词锚点、任务变更、承诺、否定、偏好、人名、项目名，就仍算有效消息

6. raw window 之外的对话不能直接消失。
   - floor 之外更早的对话，进入 `rolling_dialogue_digest`
   - digest 必须至少保留：最近用户意图、最近 assistant 承诺、当前话题延续点、最近 focus pointer 变化

7. explainability 必须告诉用户和开发者“这轮到底喂了多少 recent raw dialogue”。
   - 至少暴露：raw turns selected、low-signal dropped、chars/tokens used、是否命中 floor、是否命中用户上调 ceiling

## 3) User-Facing Dial

推荐 UI：

- 控件名：`Recent Raw Context`
- 位置：Supervisor 聊天框顶部设置 / Supervisor settings advanced
- 默认值：`12 pairs`

推荐档位映射：

1. `Floor`
   - `8` 个来回
   - 用于最省预算但仍不丢线的默认底线

2. `Standard`
   - `12` 个来回
   - 推荐默认值

3. `Deep`
   - `20` 个来回
   - 适合持续策划、长讨论、多代词引用

4. `Extended`
   - `40` 个来回
   - 适合长链条 personal assistant 对话、复杂 brainstorm、长项目纠偏

5. `Auto Max`
   - 在当前模型窗口、预算、device state 允许范围内尽量保留更多 recent raw dialogue
   - 不是无上限 full dump
   - 仍受 secret / export / scope / latency governor 约束

补充规则：

- 用户可调的是 `ceiling`
- 系统固定的是 `floor`
- `ceiling < floor` 不合法

## 4) Dialogue Eligibility Policy

`Recent Raw Context` 统计对象应当是 `eligible dialogue messages`，而不是所有字符串。

允许被视为 `drop_as_low_signal` 的 turn，必须同时满足：

- 内容极短
- 没有新实体
- 没有新意图
- 没有承诺/否定/约束
- 没有承接意义

典型可丢例子：

- `你好`
- `hi`
- `hello`
- `嗯`
- `收到`
- `好`

典型不可丢例子：

- `你好，我叫 Andrew`
- `好的，按网页版本做`
- `先别动这个项目，改做亮亮`
- `他那边还在等我回复`
- `这个 done definition 不是这个意思`

冻结规则：

- `低信号过滤` 只能在 explicit classifier 通过时触发
- 不允许用简单长度阈值粗暴丢消息
- 被过滤的消息仍可进入 debug/doctor trace，不应完全无痕消失

## 5) Runtime Contract

`dialogue_window` 最少字段：

- `raw_messages`
- `recent_user_intent`
- `recent_assistant_commitments`
- `current_turn_refs`
- `window_profile`
- `eligible_message_count`
- `low_signal_dropped_count`

冻结要求：

1. `raw_messages` 先装配，再进入其他 memory slot。
2. `raw_messages` 不可被 `workingSetMaxChars` 二次吃掉。
3. XT 侧 recent raw composer 必须按 downstream `dialogue_window` lane 的真实预算预先收口，不能先按更宽的本地预算宣称 `floor_ok=true`，再在 Hub 组装时把 raw floor 压坏。
4. 如果 budget 紧张，优先缩减：
   - evidence pack
   - portfolio brief 冗余项
   - longterm outline 冗余项
   - project retrieval 冗余 snippet
   - rolling digest
   - focused project dialogue recovery / recent summary blocks
   但不先缩 `dialogue floor`。
5. 只有在 supporting block 已退尽后，才允许把 `raw_messages` 从 ceiling 缩回 floor；`floor` 本身仍然是最后一道底线。
6. 只有在 `Auto Max` 档位下，window ceiling 才允许随模型窗口放大。

## 6) Relationship To Other Memory

除了 recent raw dialogue，本轮还应继续消费：

- `rolling_dialogue_digest`
  - raw window 之前更早的对话承接摘要
- `personal_capsule`
  - 偏好、习惯、关系、承诺、follow-up、review
- `focused_project_capsule`
  - goal、done、workflow、blocker、review、guidance
- `cross_link_refs`
  - 人与项目、承诺与项目的连接事实
- `portfolio_brief`
  - 全局盘面

固定原则：

- recent raw dialogue 解决“刚才在说什么”
- digest 解决“更早几轮的延续点是什么”
- capsule 解决“长期稳定背景是什么”
- cross-link 解决“这件事和谁/哪个项目有关”

## 7) Persistence And Truth Source

本策略不新增第二套长期真相源。

但必须补一条 `Hub-first supervisor assistant thread`：

- XT 本地 `messages` 只是交互层缓存，不再是唯一 continuity source
- Hub 需要能持久化 Supervisor assistant turns
- Supervisor 重启、fallback、跨设备续接时，应能恢复 recent raw dialogue window

冻结边界：

- durable truth 仍在 5-layer memory plane 内
- recent raw thread 可以是 working-set-first / session-thread-first 的 durable carrier
- 但不能继续只靠 XT 本地数组撑 continuity

## 8) Diagnostics And Doctor

每次组装 Supervisor prompt 时，至少输出这些 explainability 字段：

- `raw_window_profile`
- `raw_window_floor_pairs`
- `raw_window_selected_pairs`
- `eligible_messages`
- `low_signal_dropped_messages`
- `raw_window_source`
  - `hub_thread`
  - `xt_cache`
  - `mixed`
- `rolling_digest_present`
- `continuity_floor_satisfied`
- `truncation_after_floor`

Doctor 页面至少要能回答：

- 这轮到底喂了几条 recent raw dialogue
- 哪几条被当成 low-signal 丢了
- continuity floor 有没有被压坏
- raw window 来自本地缓存还是 Hub 线程

## 9) Non-Goals

本策略不解决：

- project AI 的完整 context depth 装配
- personal/project durable writeback 的全部分类细节
- `A-tier / S-tier / Heartbeat` 治理 UI

这些由相邻协议处理。
