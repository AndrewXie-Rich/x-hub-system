# X-Hub Project Governance Three-Axis Overview v1

status: active
owner: Codex
updated: 2026-04-09

## 1. 一句话总览

这套治理不是一个拨盘，而是三根独立拨盘：

- `A0..A4`：Project AI 能做到哪一步
- `S0..S4`：Supervisor 会介入多深
- `Heartbeat / Review`：多久看进度、多久做复盘、什么事件会触发 review

它们三者要分开理解。

## 2. A0..A4 是什么

| 档位 | 名称 | 核心含义 |
| --- | --- | --- |
| `A0` | Observe | 只读项目状态和记忆，给建议，不自动推进 |
| `A1` | Plan | 可以整理计划、生成工单、回写记忆，但不直接动 repo / device |
| `A2` | Repo Auto | 可在项目根目录内改文件、跑 build/test、做 patch |
| `A3` | Deliver Auto | 可连续推进到交付收口，自动总结与阶段收尾 |
| `A4` | Agent | 在受治理前提下使用完整代理执行面，包括 browser / device / connector / extension |

记忆点：

- `A` 只管执行边界，不管 Supervisor 管多深。
- `A4` 不是无限权限。
- `A4` 也不是“去掉 Supervisor”。

## 3. S0..S4 是什么

| 档位 | 名称 | 核心含义 |
| --- | --- | --- |
| `S0` | Silent Audit | 只看心跳和审计，不主动插手 |
| `S1` | Milestone Review | 只在里程碑 / 完成前 / 阻塞点看 |
| `S2` | Periodic Review | 按固定节奏周期 review |
| `S3` | Strategic Coach | 周期 + 事件驱动 review，必要时要求重规划 |
| `S4` | Tight Supervision | 高频 review、强确认、细粒度救援 |

记忆点：

- `S` 只管监督强度，不放行 repo / browser / device 权限。
- `S` 越高，不代表权限越大，而是代表纠偏越积极、review 越深入。

## 4. Heartbeat / Review 是什么

这组是第三根拨盘，不属于 `A` 也不属于 `S`。

- `progress heartbeat`：多久看一次进度，只看进度，不做战略纠偏
- `review pulse`：多久做一次轻量周期复盘
- `brainstorm review`：长时间无进展时，做更深的方向复盘
- `event-driven review`：在 blocker / drift / pre-high-risk action / pre-done 等事件触发时起 review

记忆点：

- 心跳不等于 review。
- review 不等于 brainstorm。
- 事件触发不等于每一步审批。

## 5. 三者怎么组合

推荐主档：

- `A4 + S3`
  - 含义：高自治执行 + 旁路战略监督
  - 适合：你希望项目 AI 主动推进，但仍要有 Supervisor 做方向纠偏

更保守的推荐：

- `A0 + S0`
- `A1 + S1`
- `A2 + S2`
- `A3 + S3`

更强监督但仍常见：

- `A1 + S2`
- `A2 + S3`
- `A3 + S4`
- `A4 + S4`

高风险但允许用户选择：

- `A2 + S0`
- `A3 + S0`
- `A4 + S0`
- `A4 + S1`

这里的“高风险”不是说系统做不到，而是说：

- 执行自治已经比较强
- 但 Supervisor 盯得太松
- drift、误操作、高风险动作前的纠偏更可能来不及

所以它应当是：

- 允许保存
- 明确标红或高亮提示
- 写入审计
- 让用户自己决定是否接受这个 tradeoff

不是：

- 因为 `A/S` 组合本身就一律 fail-closed

## 6. 什么才会真正 fail-closed

真正应该继续 fail-closed 的，不是 `A/S` 组合本身，而是这些执行边界：

- trusted automation 未就绪
- device / browser / connector grant 不满足
- runtime surface 没放开
- project binding / scope / allowlist 不满足
- TTL 过期
- Hub clamp / kill-switch 生效
- tool policy 明确拒绝

也就是说：

- `A/S` 是治理偏好
- grant / runtime / clamp / TTL / policy 才是动作放行边界

## 7. 最短记忆版

如果只记一版，就记这五句：

1. `A` 决定 Project AI 最多能做到哪一步。
2. `S` 决定 Supervisor 会盯多深。
3. `Heartbeat / Review` 决定多久看一次、什么事件起 review。
4. `A4` 不是去掉 Supervisor，而是高自治执行下的旁路监督。
5. 高风险组合允许用户选；真正 fail-closed 的是 grant、权限、runtime、TTL、kill-switch 这些边界。
