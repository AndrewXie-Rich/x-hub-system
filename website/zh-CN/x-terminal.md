# X-Terminal

<p class="lead">
X-Terminal 是 X-Hub-System 的操作者工作台。它不是最终控制中心，而是把项目执行、Supervisor review、模型路由、记忆视野、授权状态和用户摘要组织成一个可操作界面。
</p>

<div class="preview-note">
  <strong>核心定位</strong>
  Coder 负责做，Supervisor 负责看方向和质量，Hub 负责管权限、记忆、审计和停止权，用户负责定目标和关键裁决。
</div>

## 四个角色

| 角色 | 负责什么 | 不负责什么 |
| --- | --- | --- |
| User | 给目标、设边界、做关键裁决 | 不需要盯每个工具调用 |
| Project AI / Coder | 持续执行、写代码、跑测试、修 blocker、产出证据 | 不拥有最终授权和长期记忆真相 |
| Supervisor | 看全局、做 review、发现偏航、提出纠偏、汇报关键变化 | 不直接替代 Coder 写每一步 |
| Hub | 管 grant、policy、memory truth、quota、audit、runtime truth、kill-switch | 不把信任交给单个终端 |

## 三根拨盘

X-Terminal 的治理模型不把所有东西揉成一个“自动化程度”滑杆，而是拆成三根拨盘。

### A-Tier：Project AI 最多能做到哪一步

| 档位 | 含义 |
| --- | --- |
| A0 Observe | 只读项目状态和记忆，给建议，不自动推进 |
| A1 Plan | 能建计划、写工单、回写项目记忆，但不直接动 repo 或设备 |
| A2 Repo Auto | 能在项目根目录内改文件、跑 build/test、做 patch、写证据 |
| A3 Deliver Auto | 能持续推进到交付收口，自动做阶段总结和完成汇报 |
| A4 Agent | 在受治理前提下使用更完整的执行面，如 browser、device、connector、extension |

### S-Tier：Supervisor 盯多深、纠偏多积极

| 档位 | 含义 |
| --- | --- |
| S0 Silent Audit | 只看心跳和审计，不主动插手 |
| S1 Milestone Review | 在里程碑、完成前、阻塞点看 |
| S2 Periodic Review | 按固定节奏周期 review |
| S3 Strategic Coach | 周期 review 加事件触发 review，发现偏航时给纠偏建议 |
| S4 Tight Supervision | 高频 review、强确认、细粒度救援 |

### Heartbeat / Review：多久看一次、什么时候插手

| 信号 | 作用 |
| --- | --- |
| Project Execution Heartbeat | 项目是否活跃、是否阻塞、下一步是什么、证据是否足够 |
| Supervisor Governance Heartbeat | Supervisor 该不该 review、review 多深、是否需要纠偏 |
| Lane Vitality Signal | XT 内部运行链路是否卡死、route 是否抖动、callback 是否丢失 |
| User Digest Beat | 给用户看的摘要：发生了什么、为什么重要、下一步是什么 |

最短记忆版：

- A 决定 Coder 能做多大
- S 决定 Supervisor 管多深
- Heartbeat / Review 决定多久看一次、什么事件触发 review

## A4 不是无监督全自动

A4 的目标不是“把所有控制交给一个 Agent”。更准确的说法是：高自治执行 + 旁路治理。

运行时是双环结构：

1. Project Coder Loop 持续推进项目。
2. Supervisor Governance Loop 周期或事件触发 review。
3. Hub Run Scheduler 维护运行真相、授权、审计、唤醒、收紧策略和停止权。
4. 高风险动作仍然受 capability、scope、TTL、policy、grant 和 runtime readiness 约束。

所以 A4 不是最大权限，而是最高治理级自治。

## Safe-Point Guidance + Ack

Supervisor 不应该每一步都打断 Coder。更好的路径是：

1. Coder 完成当前 tool call、step 或 checkpoint。
2. Supervisor 形成结构化 Review Note。
3. 系统把建议变成 Guidance Injection。
4. Guidance 在 safe point 注入，除非命中高风险或 kill-switch。
5. Coder 必须 ack、defer 或 reject，并说明理由。

这让系统既不会放飞，也不会变成同步审批机器。

## 对用户来说是什么体验

理想状态下，用户不需要看内部 lane、tick、grant_pending 之类工程噪音。用户应该看到：

- 哪个项目有实质进展
- 哪个项目卡住了，为什么
- Supervisor 做了什么纠偏
- 哪些动作需要你裁决或授权
- 系统下一步准备怎么处理

X-Terminal 的价值，是把多项目 AI 工作从“聊天窗口里的混乱连续剧”，变成一个有状态、有角色分工、有证据、有停止权的执行工作台。

继续看：
[Coding Runtime](/zh-CN/coding-runtime)、[治理模型](/zh-CN/governed-autonomy)、[记忆控制面](/zh-CN/memory)、[使用场景](/zh-CN/scenarios)。
