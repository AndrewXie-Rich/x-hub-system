# XT-W3-35 Supervisor Memory Retrieval + Progressive Disclosure 实施包

- owner: XT-L2（Primary）/ Hub-L5 / QA / Product / Security
- status: in_progress
- last_updated: 2026-03-21
- purpose: 在保持 `Hub truth-source + XT thin context + fail-closed` 主链不变的前提下，把 Supervisor / X-Terminal 的记忆系统从“固定注入摘要”升级到“固定注入摘要 + 受控按需检索 + 渐进展开 + turn 后生命周期维护”；本包只覆盖 retrieval / PD / drilldown / lifecycle consumption，不下放 memory model control-plane。
- depends_on:
  - `x-terminal/work-orders/xt-w3-23-memory-ux-adapter-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-31-supervisor-portfolio-awareness-and-project-action-feed-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-33-supervisor-decision-kernel-routing-and-memory-governance-implementation-pack-v1.md`
  - `docs/memory-new/xhub-terminal-hub-memory-governance-work-orders-v1.md`
  - `docs/memory-new/xhub-terminal-hub-memory-layer-usage-work-orders-v1.md`
  - `docs/xhub-memory-system-spec-v2.md`
  - `docs/xhub-multi-model-orchestration-and-supervisor-v1.md`
- external_reference:
  - `/Users/andrew.xie/Documents/AX/Opensource/openclaw-main/src/context-engine/types.ts`
  - `/Users/andrew.xie/Documents/AX/Opensource/openclaw-main/extensions/memory-core/index.ts`
  - `/Users/andrew.xie/Documents/AX/Opensource/openclaw-main/extensions/memory-lancedb/index.ts`
  - `/Users/andrew.xie/Documents/AX/Opensource/openclaw-main/src/hooks/bundled/session-memory/handler.ts`

## 0) 为什么单开这份包

当前 `XT-W3-33` 已经把以下基础打好了：

- 项目规格胶囊
- 正式决策轨 / 背景偏好轨
- Supervisor 角色化模型路由
- actionability dashboard
- rhythm v2
- decision-blocker assist
- 可解释 compaction / archive rollup

但真实使用里又出现了一层新的差距：

1. 当前项目 chat 默认近场上下文太短，连续追问时模型会丢刚聊过的细节。
2. 长期记忆默认只有 summary，模型无法在“摘要不够”时受控地请求更多相关片段。
3. Supervisor 对其它项目默认只有 digest，这适合组合层判断，但不适合做更深入的跨项目协同。
4. turn 结束后还缺统一的记忆 ingest / recall / compaction lifecycle，很多“该沉淀的东西”还只是散落在现有 stores 里。

所以 `XT-W3-35` 不再讨论“要不要继续做更多 memory layer”，而是只解决下面四件事：

- A: 记忆检索平面
- B: progressive disclosure
- C: supervisor cross-project drilldown
- D: after-turn memory lifecycle

## 1) OpenClaw 可借鉴经验

OpenClaw 当前做得对的，不是“把所有历史都塞给模型”，而是以下四点：

1. 上下文是 lifecycle，不是静态 prompt 文本。
   - `bootstrap`
   - `ingest`
   - `afterTurn`
   - `assemble`
   - `compact`
   - `prepareSubagentSpawn`
   - `onSubagentEnded`

2. 记忆检索和全文读取是独立能力面。
   - `memory_search`
   - `memory_get`

3. recall 和 capture 都是按 turn 驱动的，而不是只靠人工总结。

4. 注入有预算、有裁剪、有来源多样化控制，不是全文灌 prompt。

### 1.1 可以借

- `context engine` 生命周期思路
- `memory_search / memory_get` 这种按需拉取模式
- `before_agent_start` recall + `agent_end` capture 的 turn 驱动
- recall 结果预算裁剪和多来源混合策略
- `/new` / `/reset` 时把 session 近场落成一份可读摘要的 hook 思路

### 1.2 不能直接照搬

- 不能给 XT 主会话默认开放完整长期记忆全文
- 不能让模型自己在没有 policy context 的情况下遍历别的项目完整记忆
- 不能绕开 Hub 直接让 XT 本地形成第二套长期事实源
- 不能把“可检索”误做成“默认跨项目全文可见”

一句话：借机制，不借默认权限。

## 2) 固定决策

### 2.1 真相源不变

- Hub 继续是 canonical truth-source。
- XT 只保留：
  - prompt assembly
  - short TTL cache
  - request-time retrieval
  - UI explainability
- 不新增 XT 侧独立长期记忆数据库作为真相源。
- XT / Supervisor 只消费 Hub 已解析完成的 memory route / mode / profile truth。
- XT / Supervisor 不得在 retrieval / drilldown / after-turn 流程里二次解析 `memory_model_preferences`，也不得自己选择 memory AI。

### 2.2 默认策略仍然是 summary-first

- 默认注入仍是：
  - `L0 constitution`
  - `L1 canonical`
  - `L2 observation summary`
  - `L3 working set`
  - `L4 compact raw evidence`
- 长期记忆默认不是 fulltext，而是：
  - `summary_only` 或
  - `progressive_disclosure_required`

### 2.3 检索必须是受治理动作，不是隐式副作用

- 模型若需要更多上下文，必须通过明确 retrieval request。
- 所有 retrieval 必须带：
  - requester role
  - project scope
  - requested layers / fields
  - reason / explainability
  - audit ref
- retrieval / progressive disclosure / drilldown 属于 serving / consumption plane，不重新定义 `Memory-Core -> Scheduler -> Worker -> Writer + Gate` 控制面。

### 2.4 Cross-project 默认仍是 digest-only

- Supervisor 默认只看跨项目 digest。
- 若 digest 不足，才允许 drilldown。
- drilldown 只展开结构化 capsule / decision / blocker evidence，不展开整段历史全文。

### 2.5 用户记忆和敏感记忆仍然收紧

- `user memory` 默认 `default_off` 或 `explicit_grant_required`
- `longterm fulltext` 默认不直接下发
- 包含 secret / credential / payment / private preference 的全文片段默认不参与 remote prompt bundle

### 2.6 不扩对外 release scope

`XT-W3-35` 是内部控制面增强，不改变当前 GitHub validated-mainline-only 对外口径。

## 3) 当前基线快照

当前已经存在、应直接复用的资产：

- `MEMORY_V1` 五层注入
- `XTMemoryUsePolicy` 中的 `summary_only / progressive_disclosure_required / denied`
- `MemoryUXAdapter` 的 canonical / working_set / longterm_outline refs
- `SupervisorProjectSpecCapsule`
- `SupervisorDecisionTrack`
- `SupervisorBackgroundPreferenceTrack`
- `SupervisorDecisionBlockerAssist`
- `SupervisorMemoryCompactionPolicy`
- `SupervisorArchiveRollup`

`XT-W3-35` 的目标不是重写这些，而是把它们接成“可按需展开”的运行面。

## 4) 机读契约冻结

### 4.1 `xt.memory_retrieval_request.v1`

```json
{
  "schema_version": "xt.memory_retrieval_request.v1",
  "request_id": "memreq_001",
  "requester_role": "chat|supervisor|tool",
  "mode": "project_chat|supervisor_orchestration|tool_plan|tool_act_high_risk",
  "project_id": "proj_demo",
  "cross_project_target_ids": [],
  "query": "formal tech stack decision",
  "allowed_layers": ["l1_canonical", "l2_observations"],
  "retrieval_kind": "search|get_ref|drilldown",
  "max_results": 3,
  "reason": "summary_insufficient_for_current_turn",
  "require_explainability": true,
  "audit_ref": "audit_memreq_001"
}
```

### 4.2 `xt.memory_retrieval_result.v1`

```json
{
  "schema_version": "xt.memory_retrieval_result.v1",
  "request_id": "memreq_001",
  "status": "ok|denied|truncated",
  "deny_code": "",
  "resolved_scope": "current_project",
  "results": [
    {
      "ref": "memory://canonical/project/proj_demo/decision_track/dec_001",
      "source_kind": "decision_track",
      "summary": "Approved tech stack uses SwiftUI + governed Hub memory.",
      "snippet": "status=approved statement=Use SwiftUI + governed Hub memory.",
      "score": 0.93,
      "redacted": false
    }
  ],
  "truncated": false,
  "budget_used_chars": 420,
  "audit_ref": "audit_memreq_001"
}
```

### 4.3 `xt.supervisor_project_drilldown_request.v1`

```json
{
  "schema_version": "xt.supervisor_project_drilldown_request.v1",
  "request_id": "drill_001",
  "requester_role": "supervisor",
  "target_project_id": "proj_other",
  "fields": [
    "project_spec_capsule",
    "decision_track_latest",
    "background_shadow_summary",
    "blocker_evidence_refs",
    "active_plan_summary"
  ],
  "reason": "cross_project_coordination_needed",
  "audit_ref": "audit_drill_001"
}
```

### 4.4 `xt.memory_after_turn_delta.v1`

```json
{
  "schema_version": "xt.memory_after_turn_delta.v1",
  "session_id": "session_001",
  "project_id": "proj_demo",
  "turn_id": "turn_001",
  "captures": {
    "decision_candidates": [],
    "background_notes": [],
    "observation_rollup_lines": [],
    "working_set_resume_summary": "Continue with tech stack decision follow-up."
  },
  "compaction_hint": "none|rollup_candidate|archive_candidate",
  "audit_ref": "audit_after_turn_001"
}
```

## 5) A/B/C/D 可执行工单

### 5.1 `XT-W3-35-A` memory retrieval plane

- priority: `P0`
- goal: 给当前项目 chat、Supervisor、governed tool plan 引入统一的受治理记忆检索平面。

#### 范围

- 新增 retrieval request / result contract
- Hub 侧新增 retrieval service surface
- XT 侧新增 request builder + result formatter
- 先只支持：
  - current project search
  - ref read
  - structured drilldown request passthrough

#### 第一阶段只允许的 retrieval source

- current project canonical refs
- current project decision track
- current project project-spec capsule
- current project observation rollup / outline
- current project blocker / plan / skill evidence refs

#### 明确不做

- 不做“全项目全文搜索”
- 不做 remote provider 自己发起任意 retrieval
- 不做用户记忆全文开放

#### 代码目标

- XT:
  - `HubIPCClient` 补 retrieval request / result
  - `ChatSessionModel` 可在上下文不足时请求 retrieval
  - `SupervisorManager` 可发 retrieval 请求但不直接越权
  - XT 只负责发请求、消费结果、展示 explainability，不在本包内解析 `memory_model_preferences`
- Hub:
  - retrieval router
  - scope gate
  - deny code / truncation / redaction
  - audit event
  - retrieval router 只消费上游已决 route / mode / sensitivity truth，不在检索层临时重选 memory AI

#### DoD

- current project chat 能用 retrieval 拿到 1~3 条相关 snippet
- retrieval 失败时明确返回 deny / truncated，不静默失败
- 所有 retrieval 都有 `audit_ref`

#### 当前落地（2026-03-15）

- 已完成 `xt.memory_retrieval_request.v1 / xt.memory_retrieval_result.v1` 契约落地。
- 已完成 Hub `RetrieveMemory(...)` RPC、`current_project` scope gate、`search/get_ref`、truncation/redaction 和 deny audit。
- 已完成 XT `HubIPCClient` remote-first retrieval 路由；`auto` 模式 remote 优先并允许 local IPC fallback，`grpc` 模式 fail-closed。
- 上述 `remote-first / local IPC fallback` 仅是 transport / serving fallback，不代表 XT 在本地重选 memory AI；effective memory route / mode 继续以上游控制面解析结果为准。
- 已完成 chat / supervisor / tool 的统一 retrieval request builder 和结果标准化为 `xt.memory_retrieval_result.v1`。
- 已补测试与验证：
  - `node src/memory_retrieval_result_contract.test.js`
  - `node src/memory_retrieval_rpc.test.js`
  - `node src/paired_terminal_policy_usage.test.js`
  - `swift build`
  - `swift test --filter HubIPCClientMemoryRetrievalContractTests`

### 5.2 `XT-W3-35-B` progressive disclosure

- priority: `P0`
- goal: 把长期记忆从“只有 summary”升级成“summary-first + snippet-on-demand + ref-based escalation”。

#### 范围

- 激活 `progressive_disclosure_required`
- 定义 PD 三阶段：
  - stage 0: outline / summary
  - stage 1: related snippets
  - stage 2: explicit ref read

#### 规则

- Stage 0 默认存在
- Stage 1 需要模型明确说明“当前摘要不足”
- Stage 2 需要显式 ref 或 structured drilldown，不允许自由全文 browse

#### 拒绝条件

- 请求跨项目全文
- 请求用户敏感记忆全文
- 请求无 policy context 的 raw evidence 全量展开
- high-risk action 模式下使用 stale longterm snapshot

#### DoD

- prompt 内能标明：
  - `longterm_mode=summary_only|progressive_disclosure`
  - `retrieval_available=true|false`
  - `fulltext_not_loaded=true|false`
- retrieval 结果可把相关片段追加到本轮 working set，而不是污染 canonical

#### 当前落地（2026-03-15）

- 已完成 `project_chat` 路径的 `LONGTERM_MEMORY` 元数据注入，并把 `project_chat` 的长期记忆策略对齐到 `summary-first + progressive disclosure`。
- 已完成 stage 1:
  - 根据“历史 / spec / decision / context”类问题触发相关 snippets 检索。
  - retrieval 结果继续只追加到当前轮 working set，不回写 canonical。
- 已完成 stage 2:
  - 当用户或模型明确引用 `memory://...` ref 时，XT 改走显式 `get_ref` 路径，不再把它当自由搜索。
  - prompt 中会标明 `retrieval_stage=stage2_explicit_ref_read` 与 `explicit_refs=...`。
- 已补 progressive disclosure 规则提示：
  - stage 0: `outline_summary`
  - stage 1: `related_snippets`
  - stage 2: `explicit_ref_read_only`
- 已补 focused 测试覆盖：
  - `ChatSessionModelRecentContextTests`
  - `HubIPCClientMemoryProgressiveDisclosureTests`

### 5.3 `XT-W3-35-C` supervisor cross-project drilldown

- priority: `P1`
- goal: 保留 cross-project digest-only 默认，同时允许 Supervisor 在确有必要时受控下钻别的项目。

#### 默认边界

- Supervisor 默认跨项目只看 digest：
  - goal
  - current state
  - next step
  - blocker
  - updatedAt
  - recent count

#### drilldown 允许读的结构化面

- project spec capsule
- latest approved decision(s)
- shadowed background summary
- active blocker evidence refs
- active plan / active job summary
- latest project capsule snapshot

#### drilldown 明确禁止

- 其它项目完整聊天全文
- 用户偏好全文
- 未经 redaction 的 raw evidence 全部下发

#### UI / explainability

- Supervisor 要明确显示：
  - 现在看到的是 digest 还是 drilldown
  - drilldown 为什么被打开
  - drilldown 用到哪些 refs

#### DoD

- Supervisor 在跨项目协同时能从 digest 升级到结构化下钻
- 结果仍保持 scope-safe，不把别的项目完整历史混进当前项目 prompt

#### 当前落地（2026-03-15）

- 已完成 cross-project 默认 `digest-only`，并通过显式 `buildSupervisorProjectDrillDown(...)` 打开结构化 drilldown。
- 已完成可读结构化面聚合：
  - `project spec capsule`
  - `approved decision rails`
  - `background shadow summary`
  - `active job / active plan / active skill`
  - `capsule_plus_recent` 下的 recent short context
- 已完成 scope-safe working-set 注入：
  - prompt 中显式标记 `view=drilldown`
  - 标记 `mode=explicit_structured_drilldown`
  - 标记 `reason=...`
  - 标记 `requested_scope / granted_scope / refs_count`
  - 仅注入 `scope_safe_refs`，不混入别的项目完整历史聊天
- 已完成 Supervisor UI explainability：
  - 明示当前是 drilldown 视图
  - 明示 granted scope、opened reason、refs 数量
- 已有 focused 测试覆盖：
  - `SupervisorProjectDrillDownTests`
  - `SupervisorMemoryWorkingSetWindowTests`

### 5.4 `XT-W3-35-D` after-turn memory lifecycle

- priority: `P1`
- goal: 把 recall / ingest / rollup 变成 turn 级生命周期，而不是被动等人工刷新。

#### 生命周期

- `before_turn`:
  - 根据 user message + project digest 判断是否需要 recall
- `after_turn`:
  - 写 decision/background candidates
  - 写 observation delta
  - 生成 working set resume summary
  - 触发 compaction hint
- `session_reset_or_switch`:
  - 写 session summary capsule

#### 默认 capture 范围

- 明确的新正式决策
- 背景偏好变化
- blocker 解锁 / 新 blocker
- next-step 变化
- 需要延续到下一轮的 working set summary

#### 默认不 capture

- 重复闲聊
- 未经确认的 speculative conclusion
- 无结构的长段 assistant 自述全文

#### DoD

- turn 结束后能自动产出 machine-readable delta
- 不会把 assistant 幻觉内容静默提升成 canonical fact
- compaction hint 与现有 `SupervisorMemoryCompactionPolicy` 兼容，不另造状态机

#### 当前落地（2026-03-15）

- 已完成 `AXMemoryLifecycleStore` 与 `xt.after_turn_memory_lifecycle.v1` 工件写盘。
- 已完成 `after_turn` 主链：
  - machine-readable delta
  - decision / background candidates
  - working set resume summary
  - compaction hint
- 已完成 `session_reset_or_switch` 主链：
  - 项目切换和 clear 前写 `session summary capsule`
- 已完成安全边界：
  - assistant-only speculation 不会静默提升成 canonical decision
  - compaction hint 继续兼容现有 `SupervisorMemoryCompactionPolicy`
- `after_turn delta` 当前只作为 lifecycle signal / candidate feed；真正的记忆维护执行仍走上游 `Scheduler -> Worker -> Writer + Gate`，不在 XT 内部直接形成 durable truth 写入。
- 已有 focused 测试覆盖：
  - `AXMemoryLifecycleTests`
  - `AppModelSessionSummaryLifecycleTests`

## 6) 实施顺序

### 阶段 1

- `XT-W3-35-A`
- `XT-W3-35-B`
- 同步把默认近场窗口升级：
  - project chat 默认 `4 -> 8`
  - project chat 扩展 `12 -> 16`
  - supervisor working set 默认改成稳定 `dialogue message floor`
    - 当前实现口径：默认 `16` 条 dialogue messages，plan review `24`，deep dive `32`

### 阶段 2

- `XT-W3-35-C`

### 阶段 3

- `XT-W3-35-D`

## 7) QA / 验收口径

### 7.1 A 的验收

- 当前项目 chat 在摘要不足时能拿到相关 snippet
- retrieval result 有 deny / truncated / audit 明细
- 没有 retrieval 时行为不回退

### 7.2 B 的验收

- prompt coverage 明确显示当前只加载了多少近场和什么 longterm policy
- PD stage 1 / 2 不能无授权跳级
- 无 retrieval 时仍保持 summary-first

### 7.3 C 的验收

- Supervisor 默认跨项目仍然是 digest-only
- 只有显式 drilldown 才能看更多结构化字段
- drilldown 后的 prompt 不出现其它项目完整聊天历史

### 7.4 D 的验收

- after-turn delta 真实落盘
- decision/background/observation 捕获不串轨
- compaction hint 能正确交给现有 compaction policy 消费

## 8) 风险与硬线

### 风险

- retrieval 做得太宽会冲掉 Hub truth-source 和 scope-safe 边界
- progressive disclosure 若没有 explainability，模型会误以为自己看到了“全部记忆”
- cross-project drilldown 若直接给全文，很快会导致项目污染和错误决策
- after-turn lifecycle 若直接写 canonical，容易把未确认内容升级成正式事实

### 硬线

- 不允许任何“全项目全文默认可见”
- 不允许把 retrieval 结果直接写回 canonical
- 不允许把 assistant 生成内容直接自动升格为 approved decision
- 不允许绕过 Hub 做记忆授权 / redaction / audit
- 不允许 XT / Supervisor 在 retrieval / drilldown / after-turn 流程里二次选择 memory AI 或重解 `memory_model_preferences`

## 9) 本包完成后的结果

`XT-W3-35` 完成后，X-Terminal / Supervisor 的记忆能力应当变成：

- 默认仍简洁
- 当前项目更连续
- 长期记忆能按需展开
- 跨项目默认仍隔离
- 需要时可以结构化下钻
- turn 结束后能自动沉淀有用事实

也就是说，它不会让模型“随便看所有东西”，但会让模型在真正需要时，用受治理的方式看到“足够做对决策的那部分东西”。
