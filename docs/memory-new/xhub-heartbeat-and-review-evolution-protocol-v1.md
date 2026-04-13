# X-Hub Heartbeat + Review Evolution Protocol v1

- Status: Draft
- Updated: 2026-03-30
- Owner: Product / XT-L2 / Hub-L5 / Supervisor / Memory / QA
- Purpose: 把当前 `heartbeat != review != intervention` 的正确骨架，升级成一套正式的“证据驱动治理信号”协议，冻结 `Project AI heartbeat`、`Supervisor governance heartbeat`、`lane vitality signal`、`user digest beat`、质量评分、异常升级、恢复触发、记忆写回和解释性输出的统一模型。
- Depends on:
  - `docs/memory-new/xhub-project-autonomy-tier-and-supervisor-review-protocol-v1.md`
  - `docs/memory-new/xhub-project-governance-three-axis-overview-v1.md`
  - `docs/memory-new/xhub-role-aware-memory-serving-and-tier-coupling-v1.md`
  - `docs/memory-new/xhub-supervisor-memory-routing-and-assembly-protocol-v1.md`
  - `docs/memory-new/xhub-supervisor-dual-plane-memory-assembly-v1.md`
  - `docs/memory-new/xhub-a4-runtime-readiness-and-dual-loop-governed-agent-plan-v1.md`
  - `docs/memory-new/xhub-supervisor-event-loop-stability-work-orders-v1.md`
  - `x-terminal/Sources/Supervisor/SupervisorReviewPolicyEngine.swift`
  - `x-terminal/Sources/Supervisor/SupervisorReviewScheduleStore.swift`
  - `x-terminal/Sources/Supervisor/SupervisorManager.swift`
  - `x-terminal/Sources/Supervisor/LaneHeartbeatController.swift`
  - `x-terminal/Sources/Supervisor/TaskDecomposition/ExecutionMonitor.swift`
  - `x-terminal/Sources/UI/ProjectHeartbeatReviewView.swift`
  - `x-terminal/Sources/UI/Supervisor/SupervisorHeartbeatFeedView.swift`
  - `x-hub/grpc-server/hub_grpc_server/src/services.js`

## 0) Conclusion First

### 0.1 Current truth

截至 2026-03-30，X-Hub/X-Terminal 这套系统已经做对了三件核心事：

1. `heartbeat`、`review`、`intervention` 已经被分开，而不是混成一个“自动模式”。
2. Hub 侧已经有 durable 的 project heartbeat 真相，不只是 XT 本地 UI 状态。
3. Supervisor 侧已经有 `blocker > no-progress brainstorm > pulse` 的 review 候选优先级，而不是纯定时轮询。

这意味着：

- 当前系统并不是“没有 heartbeat 设计”。
- 当前系统真正缺的，不是再多几个时间按钮。
- 当前系统真正缺的是：让 heartbeat 从“报平安”升级成“证据驱动的治理信号”。

### 0.2 Fixed strategic direction

冻结方向：

`heartbeat` 不再只是“多久 ping 一次”，而是项目执行、治理审查、用户摘要、异常恢复、跨项目优先级分配的共同输入层。

一句话版本：

`Heartbeat should become the governed nervous system of X-Hub, not a timer.`

### 0.3 What this protocol does not do

本协议不做以下事情：

- 不把 heartbeat 变成 review 的别名。
- 不把 heartbeat 变成强制同步审批。
- 不把 heartbeat 变成海量用户噪音通知。
- 不让 XT 本地 heartbeat 绕过 Hub truth、X-Constitution、Writer + Gate、grant、kill-switch。
- 不要求 `Supervisor` 与 `Project AI` 共用同一条 heartbeat loop。

## 1) Goals And Non-Goals

### 1.1 Goals

- 冻结四类 heartbeat 产品：
  - `Project Execution Heartbeat`
  - `Supervisor Governance Heartbeat`
  - `Lane Vitality Signal`
  - `User Digest Beat`
- 冻结 `heartbeat quality` 与 `heartbeat anomaly` 结构。
- 让 cadence 变成 `configured / recommended / effective` 三层，而不是死间隔。
- 让 heartbeat 可以驱动：
  - review 候选
  - guidance 节流
  - recovery/kickstart
  - portfolio priority
  - user digest
- 明确 heartbeat 如何进入现有 5-layer memory 架构，而不是另起炉灶。
- 明确 heartbeat 与 `A-Tier / S-Tier / Memory Serving` 的耦合边界。

### 1.2 Non-goals

- 不重新发明第二套 project state 存储。
- 不要求所有 heartbeat 字段先升级 proto 才能落地。
- 不把内部 lane/infrastructure 噪音直接暴露给用户。
- 不把所有 heartbeat 都自动晋升为 longterm memory。

## 2) Fixed Decisions

### 2.1 One project truth, many projections

冻结：

- 每个 project 只有一份 authoritative `Project Heartbeat Truth`。
- 这份真相默认由 Hub 持有。
- 其它视图都从这份真相派生，而不是各自发明新状态。

派生视图最少包括：

- runtime truth projection
- supervisor governance projection
- user digest projection
- doctor/explainability projection

### 2.2 Heartbeat is not shared as one loop

冻结：

- `Project AI / coder heartbeat` 是执行活性和项目真相输入。
- `Supervisor heartbeat` 是治理观察节奏和 review 调度输入。
- `Lane heartbeat` 是 XT 内部运行健康与 stall 检测输入。
- 三者共享部分 project truth，但不是同一循环，不应混成一个定时器。

### 2.3 Quality matters more than cadence

冻结：

一个 heartbeat 是否“有价值”，不能只看它是否按时发出，还要看：

- 是否真的有新 delta
- 是否带证据
- blocker 是否说清楚
- next action 是否具体
- 是否能支撑“快完成了”这种声明

### 2.4 Silence and noise are both anomalies

冻结：

以下两种情况都应被视为异常，而不是简单归类为“还活着”：

- 长时间无 heartbeat
- 高频 heartbeat 但内容无意义、无新 delta、无证据、无方向变化

### 2.5 Heartbeat must remain governed

冻结：

- heartbeat 不能绕过 Hub-first truth
- 不能绕过 grant / policy / clamp / TTL / kill-switch
- 不能把未审计 side effect 伪装成 progress
- 不能直接把 raw internal noise 当作用户提醒

## 3) Role Split And Heartbeat Products

### 3.1 `Project Execution Heartbeat`

定义：

由 project coder / governed automation runtime 发出的项目执行真相信号。

职责：

- 告诉系统项目现在是否活跃、阻塞、空转或接近完成。
- 提供当前 queue / blocker / next action / risk / progress delta。
- 为 Supervisor review 提供输入。
- 为 recovery/resume 提供断点附近的状态真相。

不是它的职责：

- 不直接决定是否起 review。
- 不直接向用户输出最终摘要文案。
- 不直接决定是否 stop/clamp。

### 3.2 `Supervisor Governance Heartbeat`

定义：

由 Supervisor review scheduler 派生出的治理观察节奏，不等于 project 自己发心跳。

职责：

- 判断 pulse / brainstorm / event-driven review 是否到时。
- 根据质量、异常、风险、A/S 档位决定 review 深度。
- 决定是否仅观察、建议、重规划或救援。

不是它的职责：

- 不替代 project heartbeat truth。
- 不替代 user digest。
- 不直接用来表示 coder 是否真的在推进。

### 3.3 `Lane Vitality Signal`

定义：

XT 内部 lane、tool loop、automation executor、event loop 的运行健康信号。

职责：

- 检测 stall、loop freeze、callback 丢失、恢复失败、route 抖动。
- 为 recovery beat 提供输入。
- 为 doctor 和 runtime diagnostics 提供输入。

不是它的职责：

- 不作为项目进度真相直接展示给用户。
- 不应直接覆盖 project heartbeat truth。

### 3.4 `User Digest Beat`

定义：

面向用户的 heartbeat 投影，只说对用户有意义的变化。

职责：

- 告诉用户“发生了什么变化”
- 告诉用户“为什么这次变化值得知道”
- 告诉用户“系统接下来准备怎么处理”

不是它的职责：

- 不展示 `lane=...`, `grant_pending`, `dedupe`, `review_window`, `event_loop_tick` 这类内部字段
- 不要求用户理解系统内部调度术语

## 4) Protocol Objects

### 4.1 `ProjectHeartbeatTruth`

这是 authoritative project heartbeat 对象。

现有 core wire fields 继续保留：

- `root_project_id`
- `parent_project_id`
- `project_id`
- `queue_depth`
- `oldest_wait_ms`
- `blocked_reason[]`
- `next_actions[]`
- `risk_tier`
- `heartbeat_seq`
- `sent_at_ms`
- `received_at_ms`
- `expires_at_ms`

本协议新增的 v1 evolution fields，可以先以 store extension / projection 形式落地，再视需要升级 proto：

- `project_phase`
  - `explore | plan | build | verify | release | idle`
- `execution_status`
  - `active | blocked | stalled | recovering | idle | done_candidate`
- `meaningful_progress_at_ms`
- `progress_delta_kind`
  - `none | planning_delta | code_delta | evidence_delta | blocker_delta | delivery_delta`
- `evidence_refs[]`
- `checkpoint_ref`
- `active_run_id`
- `quality_snapshot`
- `open_anomalies[]`
- `portfolio_priority_snapshot`

### 4.2 `HeartbeatQualitySnapshot`

每次有效 heartbeat 都应能派生一个质量快照。

最少包含：

- `overall_score`
  - 0..100
- `overall_band`
  - `strong | usable | weak | hollow`
- `freshness_score`
- `delta_significance_score`
- `evidence_strength_score`
- `blocker_clarity_score`
- `next_action_specificity_score`
- `execution_vitality_score`
- `completion_confidence_score`
- `weak_reasons[]`
- `computed_at_ms`

### 4.3 `HeartbeatAnomalyNote`

用于表示“这次 heartbeat 或 heartbeat 缺失”已经进入异常态。

最少包含：

- `anomaly_id`
- `project_id`
- `anomaly_type`
- `severity`
  - `watch | concern | high | critical`
- `confidence`
- `reason`
- `evidence_refs[]`
- `detected_at_ms`
- `recommended_escalation`
  - `observe | pulse_review | strategic_review | rescue_review | replan | stop`

冻结的 anomaly type 最少包括：

- `missing_heartbeat`
- `stale_repeat`
- `hollow_progress`
- `queue_stall`
- `weak_blocker`
- `weak_done_claim`
- `route_flaky`
- `silent_lane`
- `drift_suspected`

### 4.4 `HeartbeatDigest`

面向用户的 digest 对象。

最少包含：

- `digest_id`
- `project_id`
- `headline`
- `change_summary`
- `why_it_matters`
- `system_next_step`
- `attention_required`
- `attention_reason`
- `open_target`
- `created_at_ms`

### 4.5 `HeartbeatRecoveryDecision`

当 heartbeat 指向恢复/续跑机会时，使用这个对象描述恢复动作。

最少包含：

- `project_id`
- `reason`
- `recovery_action`
  - `resume_run | repair_route | await_grant | request_review | rehydrate_context | hold`
- `requires_grant`
- `requires_user_attention`
- `audit_ref`

补充冻结：

- `recovery_action=resume_run` 只适用于 latest checkpoint 仍可恢复，且 checkpoint `retry_after` 已到期。
- 若 checkpoint 仍在 cooldown/backoff 窗口内，heartbeat recovery beat 必须输出 `hold`，并保留 machine-readable reason，例如 `retry_after_not_elapsed`。
- operator/manual recover 属于另一条人工 override 通道，不属于 heartbeat 默认自动恢复。

### 4.6 `PortfolioPrioritySnapshot`

用于跨项目分配 Supervisor 注意力。

最少包含：

- `project_id`
- `priority_score`
- `priority_band`
  - `critical | high | normal | low`
- `factors`
  - `risk`
  - `user_value`
  - `staleness`
  - `blocker_severity`
  - `deadline_pressure`
  - `evidence_weakness`
- `computed_at_ms`

## 5) Heartbeat Quality Model

### 5.1 Quality dimensions

冻结 7 个核心维度：

1. `freshness`
   - heartbeat 是否在合理窗口内到达
2. `delta_significance`
   - 这次是否带来了新的项目变化
3. `evidence_strength`
   - 是否附带 build/test/log/diff/review/evidence refs
4. `blocker_clarity`
   - 若阻塞，是否能说清楚“卡在哪、缺什么、下一步是什么”
5. `next_action_specificity`
   - 下一步是否具体，而不是“继续推进”
6. `execution_vitality`
   - 项目是否真的在前进，而不是假活跃
7. `completion_confidence`
   - 如果说“快做完 / 已做完”，证据是否匹配

### 5.2 Quality bands

默认 band：

- `strong`
  - heartbeat 新鲜、有新 delta、有证据、next action 明确
- `usable`
  - heartbeat 可用，但证据或 delta 强度一般
- `weak`
  - heartbeat 勉强可用，但描述模糊、证据弱或 next action 含糊
- `hollow`
  - heartbeat 基本只是在证明“进程还活着”，无法支撑治理或用户判断

### 5.3 Hard downgrade rules

即使总分不低，也要在以下情况下降级：

- 连续多次 heartbeat 文案高度相似
- 多次 `next_action` 基本不变
- 说 active，但 evidence 没增加
- 说 blocked，但 blocker 不具体
- 说 done_candidate，但没有验证证据

## 6) Anomaly Detection Model

### 6.1 Detection principles

异常不只来自“没有 heartbeat”，也来自“heartbeat 看起来像在说话，但没有价值”。

### 6.2 Mandatory anomaly rules

以下情况至少应进入 `watch`：

- 超过 effective heartbeat window 无新 beat
- 两到三次连续 `stale_repeat`
- `queue_depth` 不降但 `oldest_wait_ms` 持续上升
- blocker 持续存在但解释不变
- done_candidate 无 evidence
- lane vitality 显示 stalled，但项目仍报 active

### 6.3 Anomaly suppression rules

以下情况可以抑制部分异常：

- 项目显式进入人工等待态
- grant 正在排队且 TTL 仍健康
- 用户或 Supervisor 已明确下达 hold
- 进入 deliberate quiet window

## 7) Adaptive Cadence

### 7.1 Cadence layers

所有 cadence 都分三层：

- `configured`
  - 用户/项目配置的静态值
- `recommended`
  - 协议按 phase/risk/A/S 给出的建议值
- `effective`
  - 运行时真正采用的值，考虑 route、latency、risk、quality、anomaly、cooldown、budget 后得出

### 7.2 Inputs to effective cadence

effective cadence 至少考虑：

- `project_phase`
- `execution_status`
- `risk_tier`
- `quality_band`
- `open_anomaly_count`
- `A-Tier`
- `S-Tier`
- route/readiness health
- model window / latency / cost pressure

### 7.3 Phase recommendations

推荐节奏应类似：

| Phase | Progress heartbeat | Pulse review | Brainstorm review |
| --- | --- | --- | --- |
| `explore` | 15-30 min | 45-90 min | 90-180 min |
| `plan` | 10-20 min | 30-60 min | 60-120 min |
| `build` | 5-15 min | 20-40 min | 45-90 min |
| `verify` | 5-10 min | 15-30 min | 30-60 min |
| `release` | 2-5 min | 10-20 min | 20-40 min |
| `idle` | 30-120 min | off or milestone | off |

说明：

- 这张表是 `recommended`，不是硬编码。
- `effective` 仍要经过质量、异常和 cooldown 调整。

## 8) Escalation Ladder

### 8.1 Ladder levels

冻结默认升级梯子：

1. `observe`
   - 只记录，不起 review
2. `watch`
   - 标记关注，等待下一次有效 beat
3. `pulse_review`
   - 轻量复盘
4. `strategic_review`
   - 判断方法、方向、是否该 replan
5. `rescue_review`
   - 高风险、pre-done、反复无效、强纠偏
6. `replan_or_stop`
   - 进入强干预或 clamp/stop

### 8.2 Mapping rules

默认映射：

- `weak` 但无异常
  - `watch`
- `hollow_progress`
  - `pulse_review`
- `queue_stall / drift_suspected`
  - `strategic_review`
- `weak_done_claim / repeated_wrong_direction / high-risk before action`
  - `rescue_review`
- `critical anomaly + policy boundary`
  - `stop / clamp / hold`

### 8.3 Safe-point rule

冻结：

- heartbeat 可以触发 review
- review 可以产生 guidance
- guidance 默认仍然只在 safe point 注入
- 只有命中 `high_risk / policy_violation / kill-switch / clear_wrong_direction` 才允许立即中断

## 9) Memory Integration

### 9.1 Heartbeat enters the existing 5-layer memory core

heartbeat 必须接入现有记忆内核，而不是另起一套 memory 子系统。

### 9.2 Layer mapping

`Raw Vault`

- 保存原始 heartbeat payload
- 保存 quality/anomaly 计算引用
- 保存 recovery decision refs
- 用于审计、回放、诊断

`Observations`

- 提升结构化事实：
  - 项目进入新 phase
  - 新 blocker 出现/解除
  - quality 从 strong 降到 hollow
  - 某类异常持续出现

`Longterm Memory`

- 只保存 recurring pattern：
  - 某项目常在 verify 阶段卡住
  - 某类 route 常抖动
  - 某用户对 heartbeat 通知偏好
- 禁止把每次 beat 都写进 longterm

`Canonical Memory`

- 保存项目当前 heartbeat authoritative projection：
  - latest status
  - latest quality band
  - latest meaningful progress time
  - latest blockers
  - latest next actions
  - latest open anomalies
  - next review due

`Working Set`

- 给当前 turn / current review 注入最近高信号 heartbeat digests
- 只注入有限窗口，不搬全量 heartbeat history

### 9.3 Personal assistant bridge rule

heartbeat 可以桥接进 personal assistant 侧，但必须满足至少一条：

- 直接影响用户今天要做的决策
- 触发用户承诺、截止时间、follow-up
- 需要用户授权/裁决
- 和用户长期偏好或复盘节奏有关

禁止：

- 把每个 project 的 routine beat 都塞进个人长期记忆

## 10) User Digest Contract

### 10.1 Required three-line structure

每条用户可见 heartbeat digest 至少应能回答三件事：

1. 发生了什么变化
2. 为什么这件事值得你知道
3. 系统接下来准备怎么处理

### 10.2 User-facing examples

好例子：

- `贪食蛇项目进入验证阶段，首次跑通本地构建。`
- `这说明项目已经从实现问题切到质量问题，接下来更需要检查测试和收口标准。`
- `Supervisor 会在下一个 safe point 做一次 pre-done review。`

坏例子：

- `lane=lane-gate-downstream action=notify_user`
- `grant_pending`
- `review_window=periodic_pulse dedupe_key=...`

### 10.3 Notification policy

冻结：

- 用户通知默认只展示 digest beat
- runtime noise 仅在 debug/doctor/operator 视图可见
- heartbeat 通知的 `Open` 必须打开有意义的目标视图，而不是把用户丢回一个工程噪音面板

## 11) Portfolio Priority And Attention Allocation

### 11.1 Why portfolio heartbeat exists

Supervisor 不是只看单项目状态，还要决定“先关注谁”。

### 11.2 Priority factors

默认优先级至少考虑：

- 风险等级
- 用户价值
- 项目陈旧度
- blocker 严重度
- deadline pressure
- evidence weakness
- recovery opportunity

### 11.3 Priority usage

portfolio priority 可以驱动：

- 下一个要 review 的项目
- 哪个项目先生成 digest
- 哪个 stalled 项目先尝试 recover
- 哪个项目先要用户 attention

## 12) Recovery Beat

### 12.1 Purpose

heartbeat 不应只报告“坏了”，还应能触发“怎么救”。

### 12.2 Recovery candidates

默认恢复动作：

- `resume_run`
- `replay_follow_up`
- `repair_route`
- `rehydrate_context`
- `request_grant_follow_up`
- `queue_strategic_review`
- `hold_for_user`

其中：

- heartbeat 自动恢复默认等价于 `automatic recovery mode`，不能越过 runtime checkpoint backoff。
- 若 blocked run 仍处于 `retry_after` 窗口，默认动作应从 `resume_run` 收敛为 `hold_for_user` 或 `hold`，而不是抢跑。

### 12.3 Recovery boundaries

恢复动作仍受以下边界约束：

- `A-Tier`
- `S-Tier`
- runtime readiness
- grant posture
- checkpoint retry-after / restart recovery mode
- trusted automation
- kill-switch / clamp / TTL

## 13) Explainability And Doctor

### 13.1 Required explainability outputs

系统至少应能解释：

1. 为什么这次 heartbeat 被视为 strong / weak / hollow
2. 为什么这次起了 review 或没起
3. 为什么 digest 被显示或被压制
4. 为什么恢复动作被执行、被推迟或被拒绝

### 13.2 Doctor surfaces

doctor / runtime explainability 至少应增加：

- latest project heartbeat truth
- latest quality band
- open anomalies
- effective cadence with reason
- next review due with reason
- last recovery decision

## 14) Compatibility And Rollout Guardrails

### 14.1 Backward-compatible rollout

冻结落地顺序：

1. 先增强 projection/store，不强行先改 proto
2. 先做 quality/anomaly
3. 再做 adaptive cadence 和 explainability
4. 再做 user digest / recovery / portfolio

### 14.2 Forbidden shortcuts

禁止以下偷懒方式：

- 用“是否按时发心跳”替代质量判断
- 用“消息变多了”伪装成进展
- 把 lane noise 直接给用户看
- 让 Supervisor 和 coder 共用一个 cadence 旋钮
- 把 heartbeat 直接写进 longterm 而不经过筛选
- 让 XT 本地 heartbeat 投影反过来覆盖 Hub authoritative truth

## 15) Acceptance Standard

本协议落地后，系统至少应具备以下能力：

1. 能区分 `活着` 和 `有价值地推进`。
2. 能区分 `静默` 和 `空转噪音` 两种异常。
3. 能把异常升级成 review / replan / rescue，而不是只记日志。
4. 能把 heartbeat 写进现有 5-layer memory，而不是发明新内核。
5. 能向用户输出“看得懂”的 digest，而不是内部术语。
6. 能根据风险、阶段、质量、A/S 档位算出 effective cadence。
7. 能把 heartbeat 用到 recovery 和 portfolio priority，而不是只做状态展示。
