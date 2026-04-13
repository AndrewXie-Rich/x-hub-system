# X-Hub Heartbeat System Overview v1

- Status: Draft
- Updated: 2026-03-29
- Owner: Product / XT-L2 / Hub-L5 / Supervisor
- Purpose: 给后续 AI 和人一个 5 分钟读懂入口，先快速理解 X-Hub 最新 heartbeat 体系怎么分层、怎么配合、异常时怎么流转，再决定是否进入完整协议文档。
- Read this before:
  - `docs/memory-new/xhub-heartbeat-and-review-evolution-protocol-v1.md`
  - `docs/memory-new/xhub-project-autonomy-tier-and-supervisor-review-protocol-v1.md`
  - `x-terminal/Sources/Supervisor/SupervisorReviewPolicyEngine.swift`
  - `x-terminal/Sources/Supervisor/SupervisorReviewScheduleStore.swift`

## 1) 一句话总览

这套系统里不是“一个 heartbeat”。

而是四层协作：

- `Project Execution Heartbeat`
  - project coder / automation runtime 告诉系统“项目现在推进得怎么样”
- `Supervisor Governance Heartbeat`
  - Supervisor 判断“现在该不该 review、该看多深、要不要纠偏”
- `Lane Vitality Signal`
  - XT 内部看运行链路有没有 stall、freeze、route 抖动
- `User Digest Beat`
  - 最终给用户看的、人话版项目变化摘要

一句话记忆：

`Coder 负责做，Supervisor 负责盯，Hub 负责管，用户负责定目标和关键裁决。`

## 2) 四类 Heartbeat 各自做什么

### 2.1 `Project Execution Heartbeat`

它是项目执行真相，不是聊天文案。

它回答：

- 现在 active 还是 blocked
- queue 深度多少
- blocker 是什么
- next action 是什么
- 当前风险大不大
- 最近有没有真正进展

它的真相默认由 Hub 持有。

### 2.2 `Supervisor Governance Heartbeat`

它不是 project 自己发的心跳，而是 Supervisor 的治理节奏。

它回答：

- 现在该不该 review
- 这次是 pulse / brainstorm / event-driven
- 是 observe、suggest、replan，还是 stop
- 建议是不是需要 ack

### 2.3 `Lane Vitality Signal`

它不是项目业务进度，而是 XT 内部运行健康度。

它回答：

- lane 有没有卡住
- tool loop 有没有 freeze
- callback 有没有丢
- route 是否抖动
- runtime 是否 still healthy

### 2.4 `User Digest Beat`

它是用户可见投影，不是内部原始状态。

它只说三件事：

- 发生了什么变化
- 为什么这件事值得你知道
- 系统接下来准备怎么处理

它不该直接展示：

- `grant_pending`
- `lane=...`
- `event_loop_tick`
- 其它工程噪音

## 3) 图一：系统总图

```mermaid
flowchart TD
    U[User<br/>目标 / 边界 / A-tier / S-tier / Heartbeat-Review Policy]

    PA[Project AI / Coder Loop<br/>持续执行项目]
    PEH[Project Execution Heartbeat<br/>进度 / blocker / next action / risk / evidence]
    H[Hub Project Heartbeat Truth<br/>项目唯一权威真相]

    LV[Lane Vitality Signal<br/>stall / route / callback / runtime health]

    SCH[Supervisor Schedule + Policy<br/>configured / recommended / effective cadence<br/>A-tier / S-tier / triggers]
    SGH[Supervisor Governance Heartbeat<br/>决定现在是否该 review]
    REV[Review Engine<br/>pulse / brainstorm / event-driven]
    GI[Guidance Injection<br/>observe / suggest / replan / stop]
    SP[Safe Point<br/>tool boundary / step boundary / checkpoint / immediate]

    DIGEST[User Digest Beat<br/>发生了什么 / 为什么重要 / 系统下一步]
    REC[Recovery Beat<br/>resume / repair route / rehydrate / hold]
    MEM[Memory Writeback<br/>Raw Vault / Observations / Canonical / Working Set / Longterm patterns]

    U --> PA
    U --> SCH

    PA --> PEH
    PEH --> H

    LV --> SGH
    H --> SGH
    SCH --> SGH

    SGH --> REV
    REV --> GI
    GI --> SP
    SP --> PA

    H --> DIGEST
    SGH --> DIGEST
    REV --> DIGEST

    H --> REC
    LV --> REC
    SGH --> REC
    REC --> PA

    PEH --> MEM
    REV --> MEM
    DIGEST --> MEM
    REC --> MEM
```

怎么读：

- 左侧是执行环
- 中间是治理环
- 右侧是用户摘要和恢复
- 底部是记忆闭环

## 4) 图二：产品视角

```mermaid
flowchart LR
    U[User<br/>给目标 / 看进度 / 必要时裁决]

    S[Supervisor<br/>看全局 / 做 review / 纠偏 / 汇报]
    C[Project AI / Coder<br/>持续执行 / 验证 / 收口]

    H[Hub<br/>记忆真相 / heartbeat 真相 / grant / clamp / audit / kill-switch]

    V1[用户看到的<br/>项目摘要 / 关键变化 / 需要你决定什么]
    V2[Supervisor 在做的<br/>周期看进度 / 发现跑偏 / 在安全点插建议]
    V3[Coder 在做的<br/>写代码 / 跑测试 / 修 blocker / 推进交付]
    V4[Hub 在保证的<br/>权限边界 / 审计 / 不越权 / 可暂停 / 可恢复]

    U --> S
    U --> C

    C --> H
    S --> H

    H --> S
    H --> C

    S --> V1
    S --> V2
    C --> V3
    H --> V4
```

怎么读：

- 用户不用盯每一步
- coder 负责推进
- supervisor 负责纠偏
- Hub 负责做最终治理底座

## 5) 图三：异常流转

```mermaid
flowchart TD
    A[Project AI / Runtime 持续执行]

    B[Heartbeat Truth<br/>active / blocked / stalled / done_candidate]
    C[Quality + Anomaly Check<br/>有没有新进展 / 是否空转 / 是否弱证据]
    D{异常类型}

    E1[正常推进<br/>继续执行]
    E2[轻微异常<br/>watch]
    E3[无进展 / 空转<br/>pulse 或 brainstorm review]
    E4[blocker / drift<br/>strategic review]
    E5[高风险 / 弱完成声明<br/>rescue review]
    E6[route / lane 问题<br/>recovery beat]
    E7[越权 / kill-switch / 明显错误方向<br/>stop or clamp]

    F[Supervisor Review]
    G[Guidance Injection<br/>observe / suggest / replan / stop]
    H[Safe Point 注入给 Coder]

    I[Recovery Action<br/>resume / repair route / rehydrate / hold]
    J[User Digest<br/>只讲关键变化]
    K[Memory + Audit Writeback]

    A --> B
    B --> C
    C --> D

    D -->|无异常| E1
    D -->|轻微异常| E2
    D -->|空转/长时间无进展| E3
    D -->|blocker/plan drift| E4
    D -->|高风险/快完成但证据弱| E5
    D -->|lane/route/runtime 故障| E6
    D -->|越权/kill-switch/明显跑偏| E7

    E1 --> K
    E2 --> K

    E3 --> F
    E4 --> F
    E5 --> F

    F --> G
    G --> H
    H --> A
    G --> J
    F --> K

    E6 --> I
    I --> A
    I --> J
    I --> K

    E7 --> G
    E7 --> J
    E7 --> K
```

怎么读：

- 不是所有异常都去打扰用户
- 轻的先观察
- 中等的起 review
- 能修的走 recovery
- 高风险或越权才 stop / clamp

## 6) 最短记忆版

如果只记这 7 句，就够了：

1. 系统里不是一个 heartbeat，而是四层。
2. `Project Execution Heartbeat` 是项目真相，不是聊天话术。
3. `Supervisor Governance Heartbeat` 决定什么时候该 review，不等于 project 自己发的 beat。
4. `Lane Vitality Signal` 负责看链路健康，不负责对用户讲项目进度。
5. `User Digest Beat` 只讲用户需要知道的变化，不讲工程噪音。
6. `heartbeat != review != intervention`，三者必须分开。
7. 默认在 safe point 注入 guidance，只有高风险、越权、kill-switch、明显错误方向才立即打断。

## 7) Next Read

如果要继续深入，按这个顺序读：

1. `docs/memory-new/xhub-heartbeat-and-review-evolution-protocol-v1.md`
2. `docs/memory-new/xhub-project-autonomy-tier-and-supervisor-review-protocol-v1.md`
3. `x-terminal/Sources/Supervisor/SupervisorReviewPolicyEngine.swift`
4. `x-terminal/Sources/Supervisor/SupervisorReviewScheduleStore.swift`
5. `x-terminal/Sources/Supervisor/SupervisorManager.swift`
