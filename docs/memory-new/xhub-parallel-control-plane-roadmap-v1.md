# X-Hub Parallel Control-Plane Roadmap v1

- Status: Draft
- Updated: 2026-03-29
- Owner: Product / Hub Runtime / X-Terminal / Supervisor / Memory / QA
- Purpose: 把 X-Hub-System 下一阶段的“并行推进”从零散功能列表，收敛成一张正式的控制面地图。目标不是按页面拆，而是按真相源、治理边界、写入面、验收面来拆，让后续多 AI 可以低冲突并行推进。
- Related:
  - `README.md`
  - `X_MEMORY.md`
  - `docs/WORKING_INDEX.md`
  - `docs/memory-new/xhub-project-autonomy-tier-and-supervisor-review-protocol-v1.md`
  - `docs/memory-new/xhub-heartbeat-and-review-evolution-protocol-v1.md`
  - `docs/memory-new/xhub-a4-runtime-readiness-and-dual-loop-governed-agent-plan-v1.md`
  - `docs/memory-new/xhub-role-aware-memory-serving-and-tier-coupling-v1.md`
  - `docs/memory-new/xhub-lane-command-board-v2.md`
  - `x-terminal/work-orders/README.md`

## 0) Conclusion First

### 0.1 Current truth

你们已经拆开的主线是对的，而且已经抓住了系统的大骨架：

- Memory
- Pairing / Doctor / Self-Heal
- A-Tier & S-Tier
- Heartbeat / Review
- Supervisor & Coder 分工
- Skills workflow

这 6 条不是“枝节”，而是系统的核心控制面。

### 0.2 What is missing

下一阶段最值得继续拆的，不是更多页面，而是把下面 7 个控制面正式升成一等主线：

- Run Scheduler / Agent Runtime
- Capability / Grant / Runtime Readiness
- Portfolio / Attention Allocation
- Supervisor Personal Assistant Plane
- Model Route / Context Budget / Cost Governor
- User-Facing Governance UX
- Evidence / Release Truth Spine

说明：

- `Heartbeat / Review` 这条线已经存在，但需要升级为 `Heartbeat / Review / Recovery`，而不是原地停留在“报进度”。
- `Supervisor & Coder 分工` 这条线已经存在，但需要继续落到 `Run Scheduler / Agent Runtime` 上，不能只停留在角色定义。

### 0.3 Fixed decision

冻结决策：

后续并行推进默认按 `control plane` 拆，不按“页面 / 视图 / 单个按钮”拆。

原因：

- 页面会互相碰撞
- 真相源会漂移
- 多 AI 容易重复造状态
- release / doctor / docs-truth 会失真

## 1) Split Rules

并行拆分必须遵守这 6 条规则：

1. 一条线必须有自己的主要真相源。
2. 一条线必须有相对独立的主写入面。
3. 一条线必须能单独验收，而不是依赖“大家都差不多做完了”。
4. 一条线不能发明第二套真相 vocabulary。
5. 一条线不应以 UI 视图为主要边界，而应以 runtime / governance / memory / capability 边界为主。
6. `Doctor`、`digest`、`README claims` 属于解释层，不允许反向发明 runtime truth。

## 2) Full Control-Plane Map

### 2.1 Already split or frozen enough to continue

| ID | Control Plane | State | Why it exists |
| --- | --- | --- | --- |
| `CP-01` | Memory Core & Serving | active | 决定 AI 看到多少上下文、什么进入 durable truth、什么只留 working set |
| `CP-02` | Pairing / Discovery / Doctor / Self-Heal | active | 决定 XT 能否稳定发现、连上、解释、修复 Hub 路径 |
| `CP-03` | Governance Tiering (`A0..A4` / `S0..S4`) | active | 决定执行边界、监督深度、safe-point 和 intervention 语义 |
| `CP-04` | Heartbeat / Review / Recovery | active-expanding | 决定进度信号、review 节奏、异常升级、恢复触发 |
| `CP-05` | Dual-Loop Role Split (`Supervisor` / `Coder`) | active | 决定谁执行、谁治理、谁汇报、谁接管 |
| `CP-06` | Skills / Packages / Workflow | active | 决定 governed capability surface、preflight、compat、doctor 和 reuse |

### 2.2 Must be promoted to first-class next

| ID | Control Plane | Priority | Why it must be split |
| --- | --- | --- | --- |
| `CP-07` | Run Scheduler / Agent Runtime | `P0` | A4 要真正跑通，必须有 run truth、checkpoint、resume、retry、prepared run lifecycle |
| `CP-08` | Capability / Grant / Runtime Readiness | `P0` | 必须把“能不能做”和“配置想让它做”分开，形成一等真相源 |
| `CP-09` | Portfolio / Attention Allocation | `P1` | Supervisor 不是单项目聊天体，要能跨项目分配注意力和 review 预算 |
| `CP-10` | Supervisor Personal Assistant Plane | `P1` | 项目记忆和个人助理记忆要分平面，但能自然桥接 |
| `CP-11` | Model Route / Context Budget / Cost Governor | `P1` | 必须把记忆深度、模型窗口、预算、fallback、downgrade 一起治理 |
| `CP-12` | User-Facing Governance UX | `P1` | 底层治理再强，如果用户看到的是噪音和死按钮，产品体验仍然失败 |
| `CP-13` | Evidence / Release Truth Spine | `P1` | 多协议、多工单、多实现下，必须有一条单独的证据和发布真相主线防漂移 |

## 3) What Should Not Be Split Further

以下部分不适合再拆成互不沟通的大主线：

### 3.1 Governance family

不要把下面这组彻底拆散：

- `A-Tier`
- `S-Tier`
- `Review Policy`
- `Safe Point`
- `Guidance Ack`

原因：

它们在概念上可区分，但 runtime 上是一个完整治理闭环。

### 3.2 Heartbeat family

不要把下面这组拆成完全独立的三条工程线：

- `Heartbeat`
- `Review`
- `Intervention`

原因：

- 它们必须分开理解
- 但不能分开维护 vocabulary 和状态机

### 3.3 Memory family

不要把下面两类记忆做成完全互不相认的系统：

- project memory
- personal assistant memory

原因：

最终 `Supervisor` 必须能丝滑地同时使用两类记忆。

### 3.4 Doctor

`Doctor` 必须继续当 explainability / evidence layer，不允许变成新的 truth source。

## 4) Practical Parallel Execution Topology

为了给后续多 AI 一个低冲突执行面，本路线图冻结成 6 条实际执行线。

注意：

- 这是“执行线”，不是“全部控制面数量”。
- 一条执行线可以覆盖 1 到 3 个相近控制面。

### Line A `Runtime`

负责：

- `CP-05` Dual-Loop execution seam
- `CP-07` Run Scheduler / Agent Runtime

它回答的问题：

- project coder 如何持续执行
- run 如何 checkpoint / resume / retry / recover
- prepared run 如何变成 active run，再走到 blocked / completed

### Line B `Governance`

负责：

- `CP-03` Governance Tiering
- `CP-04` 中的 review / guidance / safe-point / ack 语义

它回答的问题：

- A/S 档位怎么真正落成 runtime clamp
- review 何时触发、触发多深
- guidance 怎么注入、何时需要 ack、何时 stop

### Line C `Heartbeat`

负责：

- `CP-04` 中的 heartbeat truth / quality / anomaly / recovery
- `CP-09` Portfolio / Attention Allocation

它回答的问题：

- 什么叫有效进展
- 什么叫空转、无进展、弱完成声明
- 什么时候该起 pulse / brainstorm / strategic / rescue
- 哪个项目更值得优先关注
- heartbeat 触发的 governance review 应该带什么 vocabulary，并如何进入 doctor / explainability
- 如何把 heartbeat 窄接到 memory explainability，而不把它升级成 normal chat / project memory 的总拨盘

当前落点补充：

- `Line C` 已经把 `heartbeat_governance_support` 接到 doctor/export/source-gate/release evidence seam。
- 这不是 memory core 扩权；normal chat、project memory、grant/policy truth 仍由原主链负责。
- 下一位 AI 默认应从 recovery beat、portfolio priority、Hub truth seam 继续，而不是回头重做已冻结的 explainability carrier。

### Line D `Trust / Capability / Route`

负责：

- `CP-02` Pairing / Doctor / Self-Heal
- `CP-06` Skills / Packages / Workflow
- `CP-08` Capability / Grant / Runtime Readiness
- `CP-11` Model Route / Context Budget / Cost Governor

它回答的问题：

- 这次动作能不能做
- 缺什么 grant / readiness 才能做
- 模型到底走哪条路
- 上下文预算、token 预算、fallback 是怎么选的
- skills 执行面是否 ready

如果团队容量更大，这条线可进一步拆成：

- `Line D1 Trust / Pairing / Doctor`
- `Line D2 Capability / Route / Skills`

### Line E `Memory`

负责：

- `CP-01` Memory Core & Serving
- `CP-10` Supervisor Personal Assistant Plane

它回答的问题：

- Supervisor 看哪些记忆
- project AI 看哪些记忆
- 两类记忆怎么桥接
- durable truth 怎么继续走 Hub-first、Writer + Gate

### Line F `UX / Release`

负责：

- `CP-12` User-Facing Governance UX
- `CP-13` Evidence / Release Truth Spine

它回答的问题：

- 用户看到的治理表面是否丝滑
- 通知、digest、Open 行为是否有用
- doctor / release / docs-truth / capability matrix 是否继续说真话

当前落点补充：

- `Line F` 已可直接消费 `heartbeat_governance_support` 这类 machine-readable seam。
- `Line F` 的责任是把既有 runtime/governance truth 讲清楚，不是重新定义 heartbeat 或 memory 的核心 semantics。

## 5) Recommended Priority

### 5.1 Hot `P0`

这三条应优先高强度推进：

- `Line A Runtime`
- `Line C Heartbeat`
- `Line D Trust / Capability / Route`

原因：

- 没有 Runtime，A4 只是壳
- 没有 Heartbeat quality/recovery，系统只会“看起来在动”
- 没有 Capability/Readiness，系统无法稳定解释“为什么现在不能做”

### 5.2 Warm `P0/P1`

- `Line B Governance`

原因：

治理主线已经成形，但还需要继续收口到 runtime clamp、guidance ack、effective policy truth。

### 5.3 Warm `P1`

- `Line E Memory`
- `Line F UX / Release`

原因：

这两条对长期体验和可发布性非常重要，但不应压过主执行闭环和 readiness 问题。

## 6) Read Order For Another AI

如果另一位 AI 要接手本路线图，建议读序：

1. `docs/memory-new/xhub-parallel-control-plane-roadmap-v1.md`
2. `docs/memory-new/xhub-parallel-control-plane-lane-work-orders-v1.md`
3. `docs/memory-new/xhub-a4-runtime-readiness-and-dual-loop-governed-agent-plan-v1.md`
4. `docs/memory-new/xhub-heartbeat-and-review-evolution-protocol-v1.md`
5. `docs/memory-new/xhub-project-autonomy-tier-and-supervisor-review-protocol-v1.md`
6. `docs/memory-new/xhub-role-aware-memory-serving-and-tier-coupling-v1.md`
7. `docs/WORKING_INDEX.md`

## 7) Final Summary

一句话结论：

下一阶段不要继续按零散功能堆工单，而要按 6 条执行线并行推进：

- `Runtime`
- `Governance`
- `Heartbeat`
- `Trust / Capability / Route`
- `Memory`
- `UX / Release`

这 6 条执行线背后，对应 13 个控制面。
已有的 6 个控制面继续推进；
缺的 7 个控制面必须补成一等主线；
否则系统会一直停留在“概念和协议都很强，但 runtime 还不够成闭环”的状态。
