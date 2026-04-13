# X-Hub A-Tier Execution Graduation Work Orders v1

- Status: Active
- Updated: 2026-03-29
- Owner: Product / XT-L2 / Hub-L5 / Supervisor / Memory / Security / QA
- Purpose: 把 `A0..A4` A-Tier 的真正落地顺序、共享底座、最小完成定义、当前缺口、以及可直接开工的详细工单，冻结成一份可 handoff、可并行拆分、可持续推进的执行包。
- Depends on:
  - `docs/memory-new/xhub-a4-runtime-readiness-and-dual-loop-governed-agent-plan-v1.md`
  - `docs/memory-new/xhub-project-autonomy-tier-and-supervisor-review-protocol-v1.md`
  - `docs/memory-new/xhub-project-governance-three-axis-overview-v1.md`
  - `docs/memory-new/xhub-role-aware-memory-serving-and-tier-coupling-v1.md`
  - `docs/memory-new/xhub-supervisor-dual-plane-memory-assembly-v1.md`
  - `docs/memory-new/xhub-supervisor-memory-routing-and-assembly-protocol-v1.md`
  - `docs/memory-new/xhub-supervisor-recent-raw-context-policy-v1.md`
  - `docs/memory-new/xhub-project-ai-context-depth-policy-v1.md`
  - `docs/open-source/XHUB_CAPABILITY_MATRIX_v1.md`
  - `x-terminal/work-orders/xt-w3-25-governed-automation-recipe-runtime-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-30-openclaw-mode-capability-gap-closure-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-32-supervisor-skill-orchestration-and-governed-event-loop-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-34-openclaw-skill-reuse-and-execution-surface-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-36-project-autonomy-tier-and-supervisor-intervention-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-38-i7-supervisor-continuity-floor-and-context-depth-implementation-pack-v1.md`

## 0) How To Use This Pack

如果你是新接手的 AI 或维护者，按这个顺序进入：

1. 先读 `docs/memory-new/xhub-a4-runtime-readiness-and-dual-loop-governed-agent-plan-v1.md`
2. 再读 `docs/memory-new/xhub-role-aware-memory-serving-and-tier-coupling-v1.md`
3. 再读本文件
4. 再根据你拿的工单，回到对应现有主包：
   - `XT-W3-25`
   - `XT-W3-30`
   - `XT-W3-32`
   - `XT-W3-34`
   - `XT-W3-36`
   - `XT-W3-38-i7`

固定规则：

- 不要把 `A4` 当成一块独立大功能，脱离 `A2/A3` 单独冲。
- 默认按 `A2 -> A3 -> A4` 主链推进。
- `A1/A0` 不作为最后才补的尾巴，而作为降级语义、explainability、fail-closed 的并行护栏。
- 每项工单都要说明：
  - 改哪个 truth surface
  - 改哪个 runtime
  - 哪条治理边界不能被破坏
  - 什么证据算完成

## 1) Frozen Decisions

### 1.1 `A4 Agent` 就是 `A0..A4` 里的最高档

冻结：

- 本文件里的 `A4 Agent`，就是现有 `A-Tier = A4`
- 不是新的第二套自治模式
- 不是新的 marketing alias

### 1.2 Engineering order

冻结工程顺序：

- `A4` 是北极星目标
- 真实实现顺序按 `A2 -> A3 -> A4`
- `A1/A0` 作为并行护栏和降级面收口，不应被拖到最后

原因：

1. `A4` 建立在 `A2/A3` 之上
2. 如果 `A2` 的 repo execution / verify / retry 不稳，`A4` 只会把复杂度放大
3. 如果 `A3` 的 delivery / summary / review trigger 不稳，`A4` 就算接上 browser / device 也只是更贵的半成品
4. `A1/A0` 是 fail-closed 和 explainability 的降级面，不是“可有可无的低档位”

### 1.3 Dual-loop is fixed

冻结：

- `Project Coder Loop` 负责执行
- `Supervisor Governance Loop` 负责 review / reprioritize / intervene / summarize
- `Hub Run Scheduler` 负责 run truth / grant / audit / wake / clamp

### 1.4 Governance stays above capability

任何工单都不得破坏：

- Hub-first trust
- Hub-first memory truth
- X-Constitution
- grant / audit / kill-switch
- safe-point guidance
- `A0..A4 + S0..S4 + Heartbeat/Review` 三轴分离

## 2) Minimal Completion Definition By Tier

### 2.1 `A0 Observe`

最小完成定义：

- 只读项目状态、记忆、workflow、evidence
- 能输出结构化建议
- 不创建 side effect
- UI / doctor / audit 能明确说明当前为什么是 observe-only

当前价值：

- fail-closed 默认落点
- 高不确定性探索模式
- readiness 不足时的自然降级档

### 2.2 `A1 Plan`

最小完成定义：

- 能创建 governed `job`
- 能 upsert `plan`
- 能回写项目记忆
- 能生成 executable plan skeleton
- 不能直接动 repo / browser / connector / device

当前价值：

- 把模糊任务稳定压成结构化执行骨架
- 作为 `A2/A3/A4` 无法放开时的安全退路

### 2.3 `A2 Repo Auto`

最小完成定义：

- 在 project root 内自主执行 repo 读写
- 支持 build/test/verify
- 支持 checkpoint / restart / bounded retry
- 支持 blocker capture 和 evidence writeback
- 不需要用户每步说“继续”
- 完整保留 Hub grant / audit / clamp

这是第一条真正意义上的“持续执行”档位。

### 2.4 `A3 Deliver Auto`

最小完成定义：

- 在 `A2` 基础上持续推进直到交付收口
- 有 pre-done review
- 有 delivery summary
- 有 result notification
- supervisor 不用每步同步介入，只在 review/incident/drift/pre-done 插入

这是第一条真正意义上的“自动交付”档位。

### 2.5 `A4 Agent`

最小完成定义：

- 在 `A3` 基础上接入受治理 device/browser/connector/extension execution surfaces
- 可通过外部 trigger / connector event / schedule 持续唤醒
- 可在 Hub 统一 run scheduler 下持续推进
- 仍然保留 supervisor 旁路监督、grant、TTL、kill-switch、audit

冻结：

`A4` 不是 unsupervised mode，而是 highest governed execution mode。

## 3) Shared Foundations Before Graduation

以下底座不是单独属于某一档，而是 `A2/A3/A4` 共同前提：

### 3.1 `Shared-F0` A-tier runtime truth surface

必须有：

- `configured_execution_tier`
- `effective_execution_tier`
- `runtime_ready`
- `missing_readiness_reasons`
- `required_next_step`

否则 UI 只会显示“档位设置了”，但用户和 doctor 不知道为什么还跑不起来。

### 3.2 `Shared-F1` Hub-first run truth

必须有：

- current run
- current checkpoint
- retry lineage
- pending grant dependency
- latest blocker
- latest guidance

否则 run 会停在 XT 局部状态里，不利于跨设备、重启和 supervisor 接管。

### 3.3 `Shared-F2` Continuity floor

必须有：

- Supervisor recent raw dialogue floor
- project recent project dialogue floor
- 不被 serving profile 压掉
- Hub-first durable carrier

否则“持续执行”会退化成“上下文经常断线”。

### 3.4 `Shared-F3` Verification-first contract

必须有：

- expected state
- verify command or predicate
- failure policy
- retry budget

否则自动化只是在连续跑工具，不是在稳定达成目标。

### 3.5 `Shared-F4` Structured blocker / guidance / ack

必须有：

- blocker record
- review note
- guidance injection
- ack status
- safe point policy

否则 supervisor 介入会重新退回非结构化聊天。

### 3.6 `Shared-F5` Explainability and doctor

必须有：

- 这轮为什么没跑
- 缺什么 readiness
- guidance 是否 pending
- recent raw continuity 是否满足 floor
- 实际 route / fallback / grant posture 是什么

## 4) Current Gap Snapshot

### 4.1 What is already true

当前已成立：

- `A0..A4` / `S0..S4` 协议已冻结
- safe-point guidance / guidance ack 已入主链
- governed automation runtime skeleton 已成立
- Supervisor 已支持 `CREATE_JOB / UPSERT_PLAN / CALL_SKILL`
- 部分 repo mutation skills 已落地

### 4.2 What is still missing

当前最关键缺口：

1. `A4 runtime ready` 还没有独立 truth surface
2. project coder continuous loop 还未完全从“等继续”进化成“稳定持续推进”
3. verification-first 合同还没贯穿 repo/browser/connector
4. Supervisor durable recent raw continuity 还没完全转成 Hub-first durable thread
5. managed browser runtime 仍未毕业
6. external trigger / connector action 还未彻底闭环
7. extension / MCP governed bridge 还未落成主链

## 5) Detailed Work Orders

下面的工单已经按建议顺序排好。默认前 1-8 项优先于后面的扩展项。

## 5.1 `ATG-W1` A-Tier Runtime Truth Surface

- priority: `P0`
- owner_default: `XT UI + Hub Doctor + Governance`
- why now:
  - 不先把 `A4 configured` 和 `A4 runtime ready` 区分开，后面所有执行面完成度都会继续被误读
- blocked_by:
  - 无
- parallel_with:
  - `ATG-W2`
  - `ATG-W3`
- primary refs:
  - `docs/memory-new/xhub-a4-runtime-readiness-and-dual-loop-governed-agent-plan-v1.md`
  - `docs/memory-new/xhub-project-autonomy-tier-and-supervisor-review-protocol-v1.md`
  - `docs/open-source/XHUB_CAPABILITY_MATRIX_v1.md`
- target surfaces:
  - `x-terminal/Sources/UI/ProjectGovernanceBadge.swift`
  - `x-terminal/Sources/UI/XTUnifiedDoctor.swift`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/XHubDoctorOutputHub.swift`
  - project detail / governance summary / heartbeat brief
- definition of done:
  - 项目 UI 明确区分：
    - `A-tier configured`
    - `runtime ready`
    - `missing readiness`
  - doctor / brief / project badge 用同一套 reason codes
  - `A4` 未 ready 时不给误导性成功表述
- evidence:
  - doctor snapshot
  - governance badge snapshot
  - one machine-readable readiness contract

## 5.2 `ATG-W2` Hub Run Registry + Scheduler Skeleton

- priority: `P0`
- owner_default: `Hub Runtime + Supervisor`
- why now:
  - dual-loop 架构如果没有 Hub 统一 run truth，会继续被 XT 局部状态割裂
- blocked_by:
  - 无
- parallel_with:
  - `ATG-W1`
  - `ATG-W4`
- primary refs:
  - `docs/memory-new/xhub-a4-runtime-readiness-and-dual-loop-governed-agent-plan-v1.md`
  - `x-terminal/work-orders/xt-w3-25-governed-automation-recipe-runtime-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-32-supervisor-skill-orchestration-and-governed-event-loop-implementation-pack-v1.md`
- target surfaces:
  - Hub-side scheduler snapshot / registry
  - grant dependency tracking
  - trigger ingress tracking
  - run brief projection
- definition of done:
  - Hub 能回答任一项目：
    - current run
    - latest checkpoint
    - latest blocker
    - latest pending guidance
    - pending grant dependency
  - XT 重启或跨设备后能恢复 run truth
- evidence:
  - machine-readable scheduler snapshot
  - run recovery smoke

## 5.3 `ATG-W3` A1/A0 Downgrade + Explainability Guardrails

- priority: `P0`
- owner_default: `Governance + XT UI`
- why now:
  - `A1/A0` 不是以后再补的低档位，而是系统的 fail-closed 和 explainability 面
- blocked_by:
  - 无
- parallel_with:
  - `ATG-W1`
  - `ATG-W4`
- primary refs:
  - `docs/memory-new/xhub-project-autonomy-tier-and-supervisor-review-protocol-v1.md`
  - `docs/memory-new/xhub-project-governance-three-axis-overview-v1.md`
- target surfaces:
  - project settings
  - project summary
  - deny / clamp explainability
- definition of done:
  - `A0` 的 only-read / suggest-only 语义不可漂移
  - `A1` 的 create job / upsert plan / write memory 语义稳定
  - 所有 downgrade/clamp 都能明确告诉用户“为什么没放开到 A2/A3/A4”
- evidence:
  - governance resolver tests
  - UI explanation snapshots

## 5.4 `ATG-W4` Supervisor Durable Thread + Recent Raw Continuity

- priority: `P0`
- owner_default: `Memory + Supervisor`
- why now:
  - 如果 continuity floor 还主要靠 XT 本地 `messages` 缓存，Supervisor 就不够像长期助手，也不够像稳定治理体
- blocked_by:
  - 无
- parallel_with:
  - `ATG-W2`
  - `ATG-W5`
- primary refs:
  - `docs/memory-new/xhub-supervisor-recent-raw-context-policy-v1.md`
  - `docs/memory-new/xhub-supervisor-memory-routing-and-assembly-protocol-v1.md`
  - `docs/memory-new/xhub-supervisor-dual-plane-memory-assembly-v1.md`
- target surfaces:
  - Supervisor thread persistence
  - Hub-first recent raw fetch
  - continuity explainability
- definition of done:
  - Supervisor recent raw context 至少能跨重启恢复
  - explainability 能区分 `hub_thread / xt_cache / mixed`
  - `floor` 不再被 serving profile 吞掉
- evidence:
  - restart continuity smoke
  - raw-window explainability snapshot

## 5.5 `ATG-W5` Project Coder Context Graduation

- priority: `P0`
- owner_default: `Project Runtime + Memory`
- why now:
  - project coder 不稳，A2/A3/A4 都只是表面自治
- blocked_by:
  - `ATG-W4` 最佳，但可并行推进
- parallel_with:
  - `ATG-W6`
- primary refs:
  - `docs/memory-new/xhub-project-ai-context-depth-policy-v1.md`
  - `docs/memory-new/xhub-supervisor-dual-plane-memory-assembly-v1.md`
- target surfaces:
  - project prompt assembly
  - project doctor / explainability
  - execution evidence prioritization
- definition of done:
  - coder 稳定拿到 recent project dialogue floor
  - `project context depth` 真正影响装配，而不是只停在协议
  - execution evidence / pending guidance / pending ack 优先级固定
- evidence:
  - project context summary export
  - coder continuity regression tests

## 5.6 `ATG-W6` A2 Repo Auto Mainline Closure

- priority: `P0`
- owner_default: `XT Automation + Skills`
- why now:
  - `A2` 是第一条真正持续执行主链，必须先稳
- blocked_by:
  - `ATG-W5`
- parallel_with:
  - `ATG-W7`
- primary refs:
  - `x-terminal/work-orders/xt-w3-25-governed-automation-recipe-runtime-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-34-openclaw-skill-reuse-and-execution-surface-implementation-pack-v1.md`
- target surfaces:
  - repo mutation full chain
  - build/test/verify
  - checkpoint / resume / bounded retry
- definition of done:
  - repo.write / git.apply / build.run / test.run 全部在 governed runtime 下成立
  - 当前 step 完成后能继续到下一 step
  - block 时能自动形成 blocker
  - evidence / result writeback 完整
- evidence:
  - one end-to-end repo automation real run
  - checkpoint recovery evidence

## 5.7 `ATG-W7` Verification-First Step Contract

- priority: `P0`
- owner_default: `Automation Runtime + QA`
- why now:
  - 不解决 verification，自动推进只是连续调用工具
- blocked_by:
  - `ATG-W6` 部分能力 ready
- parallel_with:
  - `ATG-W8`
- primary refs:
  - `x-terminal/work-orders/xt-w3-25-governed-automation-recipe-runtime-implementation-pack-v1.md`
  - `docs/memory-new/xhub-a4-runtime-readiness-and-dual-loop-governed-agent-plan-v1.md`
- target surfaces:
  - step schema
  - verification report
  - failure policy / retry budget
- definition of done:
  - 每个关键 step 至少具备：
    - expected state
    - verify command or predicate
    - failure policy
    - retry budget
  - repo/browser/connector 三类执行面逐步复用同一语义
- evidence:
  - verification contract sample
  - failure-policy regression tests

## 5.8 `ATG-W8` A3 Deliver Auto Closure

- priority: `P0`
- owner_default: `Supervisor + Automation Runtime`
- why now:
  - `A3` 才是“持续执行到交付”的真正闭环
- blocked_by:
  - `ATG-W6`
  - `ATG-W7`
- parallel_with:
  - `ATG-W9`
- primary refs:
  - `docs/memory-new/xhub-project-autonomy-tier-and-supervisor-review-protocol-v1.md`
  - `x-terminal/work-orders/xt-w3-32-supervisor-skill-orchestration-and-governed-event-loop-implementation-pack-v1.md`
- target surfaces:
  - pre-done review
  - delivery summary
  - result notification
  - user-facing project summary
- definition of done:
  - run 能在交付前自动触发 pre-done review
  - 交付时能输出 structured summary
  - 完成后能自动通知用户或更新 project history
- evidence:
  - one real A3 delivery run
  - pre-done review trace

## 5.9 `ATG-W9` Supervisor Review Trigger Engine

- priority: `P0`
- owner_default: `Supervisor + Governance`
- why now:
  - heartbeat 不能继续兼任 review engine
- blocked_by:
  - `ATG-W2`
  - `ATG-W8`
- parallel_with:
  - `ATG-W10`
- primary refs:
  - `docs/memory-new/xhub-project-autonomy-tier-and-supervisor-review-protocol-v1.md`
  - `x-terminal/work-orders/xt-w3-32-supervisor-skill-orchestration-and-governed-event-loop-implementation-pack-v1.md`
- target surfaces:
  - review scheduler
  - event-driven review
  - review note store
  - guidance injection queue
- definition of done:
  - 支持这些 trigger：
    - periodic
    - blocker
    - plan drift
    - high-risk pre-act
    - pre-done
    - grant resolution
    - skill callback
  - review 结构化落盘
  - guidance 自动进入 pending queue
- evidence:
  - review trigger matrix
  - structured review note export

## 5.10 `ATG-W10` Safe-Point Timeline Projection

- priority: `P1`
- owner_default: `XT UI + Supervisor`
- why now:
  - 用户要看到 supervisor 介入，但不能反向污染内部高效主链
- blocked_by:
  - `ATG-W9`
- parallel_with:
  - `ATG-W11`
- primary refs:
  - `docs/memory-new/xhub-project-autonomy-tier-and-supervisor-review-protocol-v1.md`
  - project governance activity UI
- target surfaces:
  - project history
  - governance activity timeline
- definition of done:
  - 项目历史能同时展示：
    - coder 推进内容
    - supervisor review/guidance/ack 投影
  - 展示层读取结构化对象，不要求 AI-to-AI 对话改成 prose
- evidence:
  - timeline snapshots
  - projection tests

## 5.11 `ATG-W11` A4 Managed Browser Runtime Graduation

- priority: `P1`
- owner_default: `XT Browser Runtime + Hub Governance`
- why now:
  - 这是 `A4` 和 `A3` 拉开本质差距的第一条执行面
- blocked_by:
  - `ATG-W1`
  - `ATG-W2`
  - `ATG-W7`
- parallel_with:
  - `ATG-W12`
- primary refs:
  - `x-terminal/work-orders/xt-w3-30-openclaw-mode-capability-gap-closure-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-34-openclaw-skill-reuse-and-execution-surface-implementation-pack-v1.md`
- target surfaces:
  - browser session
  - profile isolation
  - role snapshot
  - navigation guard
  - audit
  - verification
- definition of done:
  - 不再停留在 `browser_read + open_url` 混合态
  - browser runtime 有独立 session/profile/truth surface
  - project governance / trusted automation / grant 能共同约束 browser execution
- evidence:
  - managed browser runtime require-real sample

## 5.12 `ATG-W12` A4 External Trigger + Connector Action Closure

- priority: `P1`
- owner_default: `Hub Scheduler + Channels + XT Automation`
- why now:
  - 没有稳定唤醒和外部动作，A4 仍然只是本地连续执行体
- blocked_by:
  - `ATG-W2`
  - `ATG-W8`
  - `ATG-W11` 最佳
- parallel_with:
  - `ATG-W13`
- primary refs:
  - `x-terminal/work-orders/xt-w3-30-openclaw-mode-capability-gap-closure-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-24-supervisor-operator-channels-implementation-pack-v1.md`
- target surfaces:
  - trigger ingress registry
  - webhook/schedule/connector_event
  - connector action plane
- definition of done:
  - 至少两类 external trigger 真正能唤醒 run
  - connector send/reply 有 grant/audit/undo/verify
  - grant resolution 后能恢复 blocked run
- evidence:
  - trigger-to-run smoke
  - connector action evidence pack

## 5.13 `ATG-W13` Governed Extension / MCP Bridge

- priority: `P2`
- owner_default: `Hub Skills + XT Runtime`
- why now:
  - 这是 A4 扩面，不应早于主链稳定
- blocked_by:
  - `ATG-W11`
  - `ATG-W12`
- parallel_with:
  - 无
- primary refs:
  - `x-terminal/work-orders/xt-w3-30-openclaw-mode-capability-gap-closure-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-34-openclaw-skill-reuse-and-execution-surface-implementation-pack-v1.md`
- target surfaces:
  - extension manifest
  - MCP bridge
  - governed runtime binding
  - revoke/quarantine
- definition of done:
  - extension/MCP 不形成第二套控制平面
  - 继续走 Hub-first manifest / grant / audit / revoke 主链
- evidence:
  - governed extension install/execute/revoke smoke

## 5.14 `ATG-W14` A4 Graduation Gate

- priority: `P1`
- owner_default: `QA + Product + Doctor`
- why now:
  - 不建立 graduation gate，A4 会长期停留在“感觉差不多了”
- blocked_by:
  - `ATG-W1`
  - `ATG-W8`
  - `ATG-W11`
  - `ATG-W12`
- parallel_with:
  - 无
- primary refs:
  - `docs/open-source/XHUB_CAPABILITY_MATRIX_v1.md`
  - `docs/memory-new/xhub-a4-runtime-readiness-and-dual-loop-governed-agent-plan-v1.md`
- target surfaces:
  - release gate
  - doctor readiness
  - internal demo gate
- definition of done:
  - `A4 runtime ready` 有 machine-readable gate
  - README / doctor / demo / release 统一使用同一 readiness truth
  - 不能再把 implementation-in-progress 的执行面写成 ready
- evidence:
  - A4 graduation checklist report

## 6) Suggested Parallel Split

如果有多个 AI 协作者同时推进，建议这样拆：

### 线 A - Truth / Doctor / Governance

- `ATG-W1`
- `ATG-W3`
- `ATG-W14`

### 线 B - Memory / Continuity

- `ATG-W4`
- `ATG-W5`

### 线 C - Automation Mainline

- `ATG-W6`
- `ATG-W7`
- `ATG-W8`

### 线 D - Supervisor Governance Loop

- `ATG-W2`
- `ATG-W9`
- `ATG-W10`

### 线 E - A4 Execution Surfaces

- `ATG-W11`
- `ATG-W12`
- `ATG-W13`

默认规则：

- 先稳住 A/B/C/D，再拉满 E
- 不建议一开始就把主力资源砸在 `ATG-W13`

## 7) Practical Start Recommendation

如果下一位 AI 只能先拿一个任务，默认顺序是：

1. `ATG-W1`
2. `ATG-W4`
3. `ATG-W6`
4. `ATG-W8`
5. `ATG-W9`
6. `ATG-W11`

一句话总结：

`先让系统知道自己到底 ready 到哪，再让 continuity 稳住，再把 A2 跑稳，再把 A3 收口，再把 A4 扩面。`
