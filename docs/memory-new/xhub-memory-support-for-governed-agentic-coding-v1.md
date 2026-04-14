# X-Hub Memory Support For Governed Agentic Coding v1

- version: v1.0
- updatedAt: 2026-04-01
- owner: Product / XT Runtime / Supervisor / Hub Runtime / QA
- status: active
- purpose:
  - 冻结“X-Hub 当前这套 Memory 为什么是在支撑 governed coding，而不是只是在加厚 prompt”这件事
  - 明确哪些 Memory 能力已经成为 `Supervisor + Project Coder + Hub` 双环架构的底座，哪些还只是协议方向或半收口状态
  - 给后续 AI 一份不需要再翻长聊天记录的说明：Memory 已经支撑到了哪一层、还不能替代哪些 runtime 闭环、下一步该往哪接
- related:
  - `README.md`
  - `X_MEMORY.md`
  - `docs/WORKING_INDEX.md`
  - `docs/memory-new/xhub-coding-mode-fit-and-governed-engineering-strategy-v1.md`
  - `docs/memory-new/xhub-memory-support-for-governed-agentic-coding-work-orders-v1.md`
  - `docs/memory-new/xhub-a4-runtime-readiness-and-dual-loop-governed-agent-plan-v1.md`
  - `docs/memory-new/xhub-project-autonomy-tier-and-supervisor-review-protocol-v1.md`
  - `docs/memory-new/xhub-role-aware-memory-serving-and-tier-coupling-v1.md`
  - `docs/memory-new/xhub-heartbeat-system-overview-v1.md`
  - `docs/memory-new/xhub-heartbeat-and-review-evolution-protocol-v1.md`
  - `docs/memory-new/xhub-supervisor-dual-plane-memory-assembly-v1.md`
  - `docs/memory-new/xhub-supervisor-memory-routing-and-assembly-protocol-v1.md`
  - `docs/memory-new/xhub-supervisor-recent-raw-context-policy-v1.md`
  - `docs/memory-new/xhub-project-ai-context-depth-policy-v1.md`
  - `docs/memory-new/xhub-memory-serving-profiles-and-adaptive-context-v1.md`
  - `docs/xhub-memory-remote-export-and-prompt-gate-v1.md`

## 0) Conclusion First

### 0.1 One-line judgment

X-Hub 当前的 Memory 设计，已经明显是在为 `Governed Agentic Coding System` 打底，而不是在为“更厚的单会话 coding prompt”打底。

更准确地说：

- 它已经在支撑 `连续推进`
- 已经在支撑 `Supervisor / Project Coder` 的角色分工
- 已经在支撑 `review / recovery / audit`
- 已经在支撑 `Hub-first truth`

但它还没有单独替代：

- `Project Coder` 的强执行内循环
- `Hub Run Scheduler` 的全局 run truth
- `checkpoint / resume / retry / recovery` 的完整 runtime 闭环
- `verification-first done contract`

### 0.2 Frozen interpretation

后续默认口径冻结为：

1. `Memory` 不是“多塞一点上下文”的优化项，而是 governed coding 的基础设施之一。
2. `Supervisor memory` 和 `Project Coder memory` 必须分治，但要能在治理链下丝滑协作。
3. `Hub` 继续是 memory truth、grant、export gate、audit、kill authority 的主入口。
4. `XT local memory` 只能是 cache / fallback / edit buffer，不得重新长成 durable truth。
5. `Heartbeat / Review / Guidance / Ack / Recovery` 已经属于 memory 闭环的一部分，不再只是外围状态机。

### 0.3 What this document is not

本文件不做三件事：

1. 不把 Memory 吹成“已经独立完成 governed coding runtime”。
2. 不把现有 Memory 主线改写成另一套新架构。
3. 不把 runtime、capability、grant、checkpoint、verification 的问题偷换成“再多给一点记忆就好了”。

## 1) Why Governed Coding Needs A Dedicated Memory Design

### 1.1 Governed coding is not a single long chat

如果目标只是“一轮吐一段能跑代码”，那一坨会话历史加上一点 repo context 通常就够了。

但你们冻结的目标不是这个，而是：

- 项目能持续推进
- 中途能被 review
- 跑偏能纠正
- 卡住能恢复
- crash / restart / cross-device 后还能继续
- 每个关键判断都能追溯证据

这就决定了 Memory 不能只是“聊天记录”，而必须承担：

- continuity substrate
- role split substrate
- recovery substrate
- governance substrate
- audit substrate

### 1.2 Mapping: governed coding requirement -> memory responsibility

| Governed coding requirement | Memory must support | Current main mechanism |
| --- | --- | --- |
| `不中断连续推进` | 保留近期原文 continuity，而不是每轮重新开局 | `Recent Raw Context` + `Recent Project Dialogue` hard floor |
| `战略脑 / 执行脑分工` | Supervisor 和 Project Coder 不能吃同一坨上下文 | role-aware assembly + dual-plane memory |
| `review / 纠偏` | review 不能只凭感觉，要有当前 focus、证据、冲突、最近 guidance | review-memory depth + heartbeat / evidence packs |
| `可恢复` | crash / resume / reconnect 后不能完全依赖旧会话还活着 | Hub-first durable thread / snapshot recovery direction + XT cache provenance |
| `可审计` | 为什么这轮这样装配、这样降级、这样 review，必须可回放 | doctor/export projections + assembly resolution |
| `fail-closed` | 远端导出、跨 scope、来源不明时默认拒绝 | Hub retrieval deny + remote export gate |

## 2) The Memory Decisions That Matter For Governed Coding

### 2.1 Not “dump all history”

这套 Memory 的首要设计决策就是：

`不要把所有历史直接塞给模型。`

正式做法是：

- 保留近期原始对话底线
- 把长期信息压成稳定事实
- 按任务、角色、风险、预算动态装配

这和 governed coding 的诉求是一致的，因为 governed coding 要的是：

- 稳定 continuity
- 可控扩容
- 可解释装配
- 可恢复的真相层

而不是一次性塞满一个超长窗口。

### 2.2 Keep the 5-layer memory core

当前 Memory 主体仍然是 5-layer：

- `Raw Vault`
- `Observations`
- `Longterm`
- `Canonical`
- `Working Set`

外加 pinned `X-Constitution` 内核。

这件事对 governed coding 很关键，因为它意味着：

- 原始执行证据有地方放
- 结构化 observations 有地方归纳
- 长期项目 / 用户事实有地方稳定存
- 当前执行 working set 有地方短期承接
- 宪章不会在“为了多装一点执行上下文”时被悄悄挤掉

### 2.3 Serving Plane is a controlled projector, not a second truth source

`Memory Serving Plane` 的职责是：

- 从 5-layer truth 中选东西
- 按 `M0..M4` 做对象化装配
- 在 budget / risk / role 下扩容或收口

它不负责：

- 伪造新的真相源
- 私自改写 `Canonical / Longterm`
- 让 XT 本地缓存冒充 durable truth

这对 governed coding 非常重要，因为 runtime 要能恢复，就必须知道：

- 什么是 truth
- 什么只是 projection
- 什么只是 cache

### 2.4 Constitution stays pinned

你们明确冻结了：

- `X-Constitution` 是固定内核
- 它不是普通 working-set 片段
- 不会因为 coder 需要更多 repo context 就被降级成“可有可无”

这意味着 governed coding 永远不能靠“窗口不够了所以先把宪章压掉”来换执行能力。

### 2.5 Policy > Prompt

对 governed coding 真正重要的不是 prompt 里写了什么，而是：

- grant
- policy
- runtime surface deny
- export gate
- audit
- kill-switch

Memory 这里的设计也是按这个原则来的：

- Memory 可以增强 continuity 和判断质量
- 但不能绕开 Hub 的硬治理链

### 2.6 XT local remains cache / fallback / edit buffer

这条边界本质上是在保护 governed coding：

- Hub 持有 durable truth
- XT local 只做 cache / fallback / edit buffer

否则一旦 runtime 长任务、跨设备、重启恢复变多，系统会很快退化成：

- 每个终端各有一套“差不多的真相”
- 恢复时不知道该信谁
- audit replay 也失真

## 3) Role-Aware Memory For The Dual-Loop Runtime

### 3.1 Supervisor memory: governance-first and cross-domain capable

Supervisor 不是普通 chat memory，而是治理环 memory。

它当前的核心平面是：

- `continuity_lane`
- `assistant_plane`
- `project_plane`
- `cross_link_plane`

当前主要模式是：

- `personal_first`
- `project_first`
- `hybrid`
- `portfolio_review`

这使它能承担 governed coding 里的这些职责：

- 理解用户高层目标和约束
- 看到当前项目的执行状态和证据
- 在需要时把个人安排和项目状态通过 `cross_link` 联起来
- 在 review / rescue / reprioritize 时看得更广更深

### 3.2 Supervisor has two independent memory dials

Supervisor 不是一个“深/浅”开关，而是至少两根独立拨盘：

1. `Recent Raw Context`
   - 负责 continuity floor
   - 默认不能被 summary 替代
   - 当前硬底线是 `8 pairs`
2. `Review Memory Depth`
   - 负责治理 review 时看多深
   - 当前档位是 `compact / plan_review / deep_dive / full_scan / auto`

这对 governed coding 的意义是：

- 不会为了深 review 把 continuity 弄丢
- 也不会为了保 continuity 就永远只做浅 review

### 3.3 Project Coder memory: execution-first and project-scoped

Project Coder 的 memory 默认不是“看全世界”，而是：

- project-domain-first
- execution-oriented
- evidence-aware

当前主要对象是：

- `recent_project_dialogue`
- `focused_project_anchor`
- `workflow`
- `execution_evidence`
- `latest_review / guidance`
- `selected_cross_link_hints`

这非常符合 governed coding 里的 coder 角色：

- 它要的是“继续推进当前项目”
- 不是“顺手变成一个全局个人助理”

### 3.4 Project Coder also has two independent memory dials

Project Coder 现在也至少有两根独立拨盘：

1. `Recent Project Dialogue`
   - 当前硬底线也是 `8 pairs`
   - 默认 `12 pairs`
2. `Project Context Depth`
   - `lean / balanced / deep / full / auto`

这使 coder 能在以下两件事之间保持平衡：

- 继续记住刚才执行链路上的近距离上下文
- 按风险和任务深度逐步扩到 workflow、evidence、review lineage、selected longterm outline

### 3.5 Cross-link is a first-class bridge

在 governed coding 里，很多真正重要的约束都不是纯项目内的：

- 用户说今天必须先交付 A 项
- 某个项目延迟会影响另一个项目
- 某个执行方式受个人偏好或设备环境限制

如果没有 `cross_link`，系统会退化成：

- personal / project 完全割裂
- 或者 project context 被 personal memory 污染

你们现在把 `cross_link` 作为一等对象，是正确方向。

### 3.6 configured / recommended / effective is essential

governed coding 不能把“用户想看多深”直接当成“runtime 实际就这么做”。

所以 Memory 当前正式采用：

- `configured`
- `recommended`
- `effective`

三值 resolver。

这使系统能在以下情况里仍然可治理：

- tier ceiling 生效
- privacy mode 收紧
- budget 不够
- risk / anomaly 上升
- 当前 review purpose 要求不同深度

## 4) How Memory Supports The Runtime Loops

### 4.1 Project Coder Loop

Memory 对 `Project Coder Loop` 当前主要提供 6 类支撑：

1. `continuity`
   - recent project dialogue 让 coder 不会每轮失忆
2. `execution focus`
   - focused project anchor、workflow、latest blocker / next step 让它知道当前在推什么
3. `evidence grounding`
   - build/test/verify/review evidence 成为一等上下文对象
4. `guidance carry-forward`
   - 最新 review note 和未 ack guidance 不会在下一轮消失
5. `blocked / recovery context`
   - heartbeat / anomaly / recovery projection 能反馈给后续决策
6. `writeback discipline`
   - 不是所有东西都升格为 durable truth，避免临时执行噪音污染长期记忆

### 4.2 Supervisor Governance Loop

Memory 对 `Supervisor Governance Loop` 当前主要提供 6 类支撑：

1. `recent raw continuity`
   - 让 Supervisor 真知道“刚才用户和系统在聊什么”
2. `multi-plane understanding`
   - 能同时看到 personal / project / cross-link 的相关部分
3. `review depth control`
   - 不同 review purpose 对应不同 memory depth
4. `heartbeat-backed review`
   - quality / anomaly / next review / recovery decision 已经进入 explainability 和治理链
5. `guidance grounding`
   - guidance 不再只是抽象建议，而是能挂到当前 focus、evidence、memory resolution
6. `audit replay`
   - 之后能追溯这轮为什么是 observe / suggest / replan / stop

### 4.3 Hub Run Scheduler / Governance Spine

Memory 对 `Hub Run Scheduler` 方向的支撑，不是“替代 scheduler”，而是给 scheduler 一个可治理的真相底座：

- Hub retrieval 有 scope deny
- remote export 有 gate
- constitution injection 有固定位置
- durable truth 仍在 Hub 一侧
- XT remote snapshot cache 明确只有 TTL cache 语义

这让 future scheduler 可以站在更稳的 memory truth 上，而不是和 XT 本地历史纠缠。

## 5) What Is Already Landed Enough To Rely On

### 5.1 Continuity floor is real, not just protocol text

当前已落地并可依赖的事实：

- Supervisor recent raw context 有 `8 pairs` 硬底线
- Project Coder recent project dialogue 也有 `8 pairs` 硬底线
- diagnostics 会明确告诉你 floor 是否满足、实际选了多少、丢了多少 low-signal

这意味着 governed coding 的最基本连续性，不再只靠“希望模型别忘”。

### 5.2 Role-aware policy and assembly resolution are real

当前 runtime 已经有：

- `project_memory_policy`
- `supervisor_memory_policy`
- `memory_assembly_resolution`

它们会明确告诉你：

- configured / recommended / effective
- ceiling from tier
- ceiling hit
- selected slots / planes / serving objects

这已经不是黑箱 prompt 组装。

### 5.3 Supervisor dual-plane assembly is real

Supervisor 现在不是只看一份统一摘要，而是已经按：

- continuity lane
- assistant plane
- project plane
- cross-link plane

去做 role-aware 装配。

这对 governed coding 是关键，因为它允许：

- supervisor 看全局
- coder 继续专注执行
- 两边联动时边界仍清晰

### 5.4 Heartbeat already enters the memory loop

当前 heartbeat 已经不再只是 runtime 噪音：

- latest quality band
- quality score
- weak reasons
- anomaly types
- recovery decision
- project memory readiness

都已经进入 heartbeat memory projection / doctor explainability。

这让 recovery、review、memory 三条线真正开始闭环。

### 5.5 Doctor / export are already first-class acceptance surfaces

当前已落地的一等 explainability 包括：

- `project_context_summary`
- `project_memory_assembly_resolution`
- `supervisor_memory_policy`
- `supervisor_memory_assembly_resolution`
- `project_remote_snapshot_cache_snapshot`
- `supervisor_remote_snapshot_cache_snapshot`
- `heartbeat_governance_snapshot`
- `durable_candidate_mirror_snapshot`
- `local_store_write_snapshot`
- `memory_route_truth_snapshot`

这对 governed coding 很重要，因为：

- 你可以知道当前系统“为什么这样继续推进”
- 也可以知道“为什么它没继续、为什么它降级、为什么它要 review”

### 5.6 XT local boundary is explicit

当前已经明确对外暴露：

- XT local store 只是 `cache / fallback / edit buffer`
- remote snapshot cache 只是短 TTL cache
- local store write projection 只是 provenance，不是 durable writer 主权

这保护了 Hub-first governed runtime 的方向。

## 6) What Memory Intentionally Does Not Replace

为了避免后续 AI 再把一堆 runtime 问题错压到 Memory，这里明确写死。

### 6.1 Memory does not replace the Project Coder execution kernel

Memory 可以让 coder：

- 记得住
- 看得到
- 承接 guidance
- 结合证据判断

但它不能替代：

- step list discipline
- per-step verify
- bounded retry policy
- blocked contract
- continue-until-done execution kernel

也就是说，`Ralph Loop` 的强实现仍然是 runtime 任务，不是 memory 任务。

### 6.2 Memory does not replace checkpoint / recovery runtime

Memory 为恢复提供真相和投影基础，但它不能独立替代：

- checkpoint boundary
- retry_after discipline
- restart recovery state machine
- takeover / resume control

### 6.3 Memory does not replace verification-first delivery

有更多 memory，不等于：

- build 真的过了
- test 真的过了
- evidence 真的足够
- done contract 真的满足

所以 verification chain 仍然必须独立做厚。

### 6.4 Memory does not replace capability / grant / export policy

就算某轮 memory 装得再全，也不能推出：

- 可以多用工具
- 可以跨 scope 取数
- 可以发到远端模型
- 可以绕过 kill-switch

这些仍然是 Hub 治理链的硬边界。

## 7) Current Gaps If The Goal Is Stronger Governed Coding

### 7.1 Strengthen the Project Coder loop

下一步最重要的，不是再发明一层 Memory 名词，而是把 coder loop 继续做实：

- stronger step list
- per-step verify
- bounded retry
- structured blocked capture
- continue-until-done discipline

Memory 已经能给这条线提供 continuity、evidence、guidance carry-forward，但执行内核本身还要继续强化。

### 7.2 Make Hub Run Scheduler more fully authoritative

当前方向已经对，但还应继续收口：

- run truth
- retry lineage
- recovery authority
- checkpoint truth
- wake / clamp / resume authority

这样 Memory 的 durable truth 才能和 runtime truth 更完整对齐。

### 7.3 Keep extending recovery-aware memory seams

仍建议继续补：

- Hub-first durable snapshot recovery
- restart / reconnect / handoff 的 memory carry-forward
- recovery beat 与 coder working set 的更紧连接

### 7.4 Grow Observations / Longterm into a stronger coding substrate

当前最稳的主线仍主要是：

- Working Set
- Canonical
- focused anchor packs
- heartbeat projections

后续如果要更强支撑中大型项目，还应继续增强：

- structured observations
- longterm outline retrieval
- decision lineage drilldown
- multi-module / multi-phase evidence retrieval

### 7.5 Tighten guidance ack closure

guidance / ack 方向已经成立，但还应继续强化：

- ack visibility
- deferred / rejected rationale carry-forward
- doctor replay closure
- review note -> injection -> ack -> next action continuity

## 8) Frozen Working Judgment

当前可以对后续 AI 直接冻结成这 7 句话：

1. X-Hub 的 Memory 已经明显是 governed coding 底座，而不是普通 prompt 增强。
2. 它当前最成熟的价值，不是“更多知识”，而是 continuity、role split、recovery-ready truth 和 auditability。
3. Supervisor memory 和 Project Coder memory 必须继续分治，但联用要更顺。
4. Hub-first durable truth 不能退；XT local memory 不能重新长成第二真相源。
5. Heartbeat / Review / Recovery 继续视为 memory 闭环的一部分，不要再拆成互相孤立的子系统。
6. Memory 可以显著增强 governed coding，但不能替代 coder execution kernel、scheduler truth、checkpoint runtime、verification chain。
7. 后续正确方向不是“再造一套记忆概念”，而是把现有 Memory 更深地接进 Project Coder Loop、Supervisor Governance Loop 和 Hub Run Scheduler。

## 9) Recommended Read Order For The Next AI

如果下一位 AI 的问题是“Memory 到底是不是在支撑 governed coding”，按这个顺序读：

1. `docs/memory-new/xhub-coding-mode-fit-and-governed-engineering-strategy-v1.md`
2. `docs/memory-new/xhub-memory-support-for-governed-agentic-coding-v1.md`
3. `docs/memory-new/xhub-a4-runtime-readiness-and-dual-loop-governed-agent-plan-v1.md`
4. `docs/memory-new/xhub-project-autonomy-tier-and-supervisor-review-protocol-v1.md`
5. `docs/memory-new/xhub-role-aware-memory-serving-and-tier-coupling-v1.md`
6. `docs/memory-new/xhub-heartbeat-system-overview-v1.md`
7. `docs/memory-new/xhub-heartbeat-and-review-evolution-protocol-v1.md`
8. `docs/memory-new/xhub-supervisor-dual-plane-memory-assembly-v1.md`
9. `docs/memory-new/xhub-supervisor-recent-raw-context-policy-v1.md`
10. `docs/memory-new/xhub-project-ai-context-depth-policy-v1.md`
11. `x-terminal/Sources/Project/XTRoleAwareMemoryPolicy.swift`
12. `x-terminal/Sources/Supervisor/SupervisorTurnContextAssembler.swift`
13. `x-terminal/Sources/Supervisor/SupervisorReviewPolicyEngine.swift`
14. `x-terminal/Sources/Supervisor/XTHeartbeatMemoryProjectionStore.swift`
15. `x-terminal/Sources/UI/XTUnifiedDoctor.swift`

如果问题已经变成“下一步该补哪条实现线”，默认优先顺序是：

1. `Project Coder Loop` 的强执行内循环
2. `Hub Run Scheduler` 的一等真相源收口
3. `checkpoint / resume / recovery` 与 memory carry-forward 的更深接合
4. `Observations / Longterm` 对中大型 coding 项目的 retrieval 强化
5. `guidance ack` 的闭环与 replay explainability

如果问题已经变成“把上面这些方向拆成可以直接接手的工单”，下一步直接读：

- `docs/memory-new/xhub-memory-support-for-governed-agentic-coding-work-orders-v1.md`
