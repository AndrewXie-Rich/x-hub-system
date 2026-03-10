# X-Terminal Supervisor 多泳池执行工单包（Lane Delivery Pack v1）

- version: v1.9
- updatedAt: 2026-03-06
- owner: XT-L2（Primary）/ XT-L1 / Hub-L3 / Hub-L5 / QA / AI-COORD-PRIMARY
- status: active
- scope: `XT-W2-20..XT-W2-28`, `XT-W2-20-B`, `XT-W2-23-A/B/C`, `XT-W2-24-A/B/C/D/E/F`, `XT-W2-25-S1`, `XT-W2-25-B`, `XT-W2-27-A/B/C/D/E/F`, `XT-W2-28-A/B/C/D/E/F`, `XT-W3-18..XT-W3-24`, `XT-W3-18-S1`, `XT-W3-19-S1`
- parent:
  - `x-terminal/work-orders/xt-supervisor-multipool-adaptive-work-orders-v1.md`
  - `x-terminal/work-orders/xt-w2-23-w2-26-autocontinue-autonomy-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w2-24-token-optimal-context-capsule-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w2-27-anti-block-unblock-orchestration-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w2-28-jamless-anti-congestion-protocol-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-cbl-anti-block-context-governor-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-supervisor-autosplit-multilane-work-orders-v1.md`
  - `docs/memory-new/xhub-lane-command-board-v2.md`
  - `docs/memory-new/xhub-hub-to-xterminal-capability-gate-v1.md`

## 0) 使用目标（给泳道 AI 的执行方式）

- 本包是“可直接执行”的细化工单，不是概念说明。
- 每个任务均给出：`DoR -> 执行子步骤 -> DoD -> Gate/KPI -> 回归样例 -> 证据落盘`。
- 所有泳道统一按 Command Board 的 `claim + TTL + 7件套` 机制推进。
- 默认策略：`balanced + critical_touch`（兼容 `critical_only`）；只有通过风险与证据门槛后才允许提升到 `aggressive`。
- 默认创新策略：`innovation_level=L1_micro_reflect` + `suggestion_governance_mode=hybrid`（UI 可改）。
- 提示词统一三段式：`Stable Core + Task Delta + Context Refs`（Context Refs 仅引用 ID，不贴全文）。
- 阻塞治理统一走 `wait-for graph + dual-green + unblock router`，禁止靠人工口头“催单”推进。
- 跨泳道协同统一走 Command Board `I/J`：`Dependency Edge Registry + Directed @ Inbox`（waiter->blocker，禁广播，SLA 驱动）。
- 自托管场景（x-hub-system 自己推进）默认启用 `critical_path_mode`：先清 release blocker 依赖链，再恢复常规并发。
- 拥塞治理默认启用 `Jamless v1`：`Active-3 + 定向 baton + blocked 去重 + gate 冷却`，防止全泳道互等与 token 风暴。
- 默认启用 CBL 循环：`block-aware split + dynamic active seats + session rollover + block risk replan`。

## 0.1 产品化优先项（主线必含）

- `接案产品化`：`XT-W3-21 Project Intake Manifest` 作为 Supervisor 正式接案入口，负责把项目 `md/spec` 输入包转为可执行 manifest。
- `交付产品化`：`XT-W3-22 Acceptance Pack` 作为正式收口出口，统一输出结果、风险、证据、回滚点、下一步建议。
- `安全控制平面`：`SI-W1-01..SI-W1-05` 作为 Hub 安全强化主链，覆盖记忆、支付、授权、技能与最小可见策略。
- `自举可用线`：`XT-W3-18 + XT-W3-19 + XT-W3-20` 作为 Supervisor 自己接案、自拆、自派、自督导、自交付的最小闭环。
- `记忆产品化`：`XT-W3-23` 作为 XT 侧即插即用记忆 UX 适配层，补齐 `session continuity + user/project 双通道 + memory ops console + least-exposure injection + supervisor memory bus`，但 Hub 仍是唯一记忆真相源。
- `渠道产品化`：`XT-W3-24` 作为多渠道入口与流式体验产品化包，吸收 bot 产品外壳优势（多渠道、streaming、onboard、session/status 运维），但所有高风险能力仍收敛到 Hub。
- `生态兼容线`：`xt-openclaw-skills-compat-reliability-work-orders-v1.md` 作为外部 skill 兼容层，保持兼容但不让生态扩张破坏主线治理。

## 1) 阶段切分（强顺序，避免乱序并发）

### 阶段 S0：建模与策略（P0，先做）

1. `XT-W2-20` 多泳池复杂度规划器
2. `XT-W2-21` 二级子任务合成器
2a. `XT-W2-20-B` 防堵塞拆分器（Block-aware Splitter）
3. `XT-W2-22` 档位引擎（conservative/balanced/aggressive）
4. `XT-W2-23` 参与等级引擎（`zero_touch/critical_touch/guided_touch`，兼容旧值）
4a. `XT-W2-23-B` 创新分档引擎 + UI 选择器（`L0..L4`）
4b. `XT-W2-23-C` 建议治理路由器（`supervisor_only|hybrid|lane_open`）

### 阶段 S1：执行内核（P0）

5. `XT-W2-24` Prompt Pack 编译器与注册表
5a. `XT-W2-24-A` 三段式编译器与契约冻结
5b. `XT-W2-24-B` Context Capsule 预算器与装箱器
5c. `XT-W2-24-C` Context Refs 解析器与权限红线
5d. `XT-W2-24-D` 重试增量压缩器（Delta Retry）
5e. `XT-W2-24-E` Token-质量联合看板与发布证据
5f. `XT-W2-24-F` 会话滚动与上下文胶囊治理器（挂靠）
6. `XT-W2-25` Pool 调度器
6a. `XT-W2-25-S1` 激进档并发-成本治理器（挂靠）
6b. `XT-W2-25-B` 关键路径动态席位调度器（挂靠）
7. `XT-W2-26` 自治推进控制器
8. `XT-W2-27` 阻塞依赖图与即时解阻编排器
8a. `XT-W2-27-A` Wait-For Graph Arbiter（挂靠）
8b. `XT-W2-27-B` Dual-Green Dependency Gate（挂靠）
8c. `XT-W2-27-C` Dependency Escrow Package（挂靠）
8d. `XT-W2-27-D` Unblock Router & Guidance（挂靠）
8e. `XT-W2-27-E` Block SLA Escalator（挂靠）
8f. `XT-W2-27-F` Self-Host Critical Path Unblocker（挂靠）
8g. `XT-W2-28` 无拥塞推进协议（Jamless）
8g-1. `XT-W2-28-A` Critical Path Admission + WIP Governor（挂靠）
8g-2. `XT-W2-28-B` Directed Baton Router（挂靠）
8g-3. `XT-W2-28-C` Blocked Dedupe + Delta Reporter（挂靠）
8g-4. `XT-W2-28-D` Deadlock SCC Breaker（挂靠）
8g-5. `XT-W2-28-E` Gate Retry Cooldown + Evidence Delta Guard（挂靠）
8g-6. `XT-W2-28-F` Block Risk Predictor + Replan Guard（挂靠）

### 阶段 S2：集成与交付（P0）

9. `XT-W3-18` 池内/全局集成测试编排器
9a. `XT-W3-18-S1` 大规模拼装收敛器（挂靠）
10. `XT-W3-19` 交付通知与执行摘要
10a. `XT-W3-19-S1` 成本收益可视化摘要器（挂靠）
10b. `XT-W3-21` Project Intake Manifest（跨阶段接案入口）
10c. `XT-W3-22` Acceptance Pack（跨阶段收口入口）
10d. `XT-W3-23` XT 记忆 UX 适配层 / Supervisor Memory Bus（跨阶段记忆产品化入口）
10e. `XT-W3-24` 多渠道入口与流式体验产品化（跨阶段渠道产品化入口）

### 阶段 S3：动态重规划（P1）

11. `XT-W3-20` 动态重规划治理器

## 2) 泳道责任矩阵（Primary/Co-owner）

| task_id | primary_lane | co_owner | 输出重点 |
| --- | --- | --- | --- |
| `XT-W2-20` | `XT-L2` | `Hub-L3`, `QA` | 可复现 pool 规划 + 解释字段 + fail-closed |
| `XT-W2-20-B` | `XT-L2` | `Hub-L3`, `QA` | 防堵塞拆分（依赖约束 + contract-first 波次） |
| `XT-W2-21` | `XT-L2` | `Hub-L3` | lane DAG + 二级 DoD 模板 |
| `XT-W2-22` | `XT-L2` | `Hub-L3`, `QA` | 档位参数表 + 自动降档器 |
| `XT-W2-23` | `XT-L1` | `XT-L2`, `Hub-L3` | 参与等级策略 + 通知触点矩阵 |
| `XT-W2-23-B` | `XT-L1` | `XT-L2`, `QA` | 创新分档引擎 + UI 选择器（L0..L4） |
| `XT-W2-23-C` | `XT-L2` | `AI-COORD-PRIMARY`, `Hub-L5` | 建议治理路由 + Insight triage（三模式） |
| `XT-W2-24` | `XT-L2` | `XT-L1`, `Hub-L3` | Prompt Pack 编译器 + lint 阻断 |
| `XT-W2-24-A` | `XT-L1` | `XT-L2` | 三段式提示词编译（Stable Core + Task Delta + Context Refs） |
| `XT-W2-24-B` | `XT-L2` | `Hub-L5` | Context Capsule 预算装箱（最小充分上下文） |
| `XT-W2-24-C` | `Hub-L3` | `XT-L2` | Context Refs ACL/脱敏/跨项目红线 |
| `XT-W2-24-D` | `XT-L2` | `XT-L1` | 重试仅增量（Delta Retry）与 one-shot 扩容 |
| `XT-W2-24-E` | `QA` | `XT-L2`, `Hub-L5` | token-质量联合快照 + 发布证据 |
| `XT-W2-24-F` | `XT-L1` | `XT-L2`, `Hub-L3` | 会话滚动 + checkpoint 压缩 + Context Refs<=3 |
| `XT-W2-25` | `XT-L2` | `Hub-L5`, `QA` | pool/lane 并发调度 + anti-starvation |
| `XT-W2-25-S1` | `XT-L2` | `Hub-L5`, `QA` | 激进档收益门槛 + 运行中自动降档 |
| `XT-W2-25-B` | `XT-L2` | `Hub-L5`, `QA` | Active-3 动态席位 + 关键路径抢占 |
| `XT-W2-26` | `XT-L2` | `XT-L1`, `Hub-L3` | auto-advance 状态机 + 升级策略 |
| `XT-W2-27` | `XT-L2` | `XT-L1`, `Hub-L3`, `Hub-L5`, `QA` | wait-for 依赖图 + 双绿门控 + 即时解阻 |
| `XT-W2-27-A` | `XT-L2` | `Hub-L3` | 阻塞依赖边聚合、去重、环检测 |
| `XT-W2-27-B` | `XT-L2` | `Hub-L5`, `QA` | `contract_green+runtime_green` 双绿判定 |
| `XT-W2-27-C` | `XT-L1` | `XT-L2` | blocked 任务 dependency escrow 托管包 |
| `XT-W2-27-D` | `XT-L1` | `XT-L2`, `Hub-L3` | 解阻事件路由 + 自动续推指导 |
| `XT-W2-27-E` | `QA` | `XT-L2`, `Hub-L5` | 阻塞 SLA 监控、升级与机读证据 |
| `XT-W2-27-F` | `XT-L2` | `Hub-L5`, `QA`, `AI-COORD-PRIMARY` | 自托管关键路径模式 + 解阻接力棒派发 |
| `XT-W2-28` | `XT-L2` | `Hub-L5`, `QA` | Jamless 规则总装（R1..R10）+ Active-3 执行档 |
| `XT-W2-28-A` | `XT-L2` | `Hub-L5` | 关键路径准入 + WIP 限流（active<=3） |
| `XT-W2-28-B` | `XT-L1` | `XT-L2`, `Hub-L3` | blocker->waiter 定向 baton（禁广播） |
| `XT-W2-28-C` | `XT-L1` | `QA` | blocked 去重 + delta-only 汇报门禁 |
| `XT-W2-28-D` | `Hub-L3` | `XT-L2` | wait-for SCC 解环器（死锁 1 分钟内收敛） |
| `XT-W2-28-E` | `Hub-L5` | `QA`, `XT-L2` | gate 重试冷却 + evidence delta 守门 |
| `XT-W2-28-F` | `XT-L2` | `Hub-L5`, `QA`, `AI-COORD-PRIMARY` | 阻塞预测 + 20/40/60 分钟自动重排守门 |
| `XT-W3-18` | `QA` | `XT-L2`, `Hub-L5` | 池内先测后并 + 回滚校验 |
| `XT-W3-18-S1` | `QA` | `XT-L2`, `Hub-L5` | 100 lane 分波次拼装收敛 + contract freeze |
| `XT-W3-19` | `XT-L1` | `XT-L2`, `QA` | 交付通知模板 + 证据链接完整性 |
| `XT-W3-19-S1` | `XT-L1` | `XT-L2`, `QA` | 交付 ROI 摘要 + 样本充足性校验 |
| `XT-W3-21` | `XT-L2` | `Hub-L5`, `XT-L1`, `QA` | 项目 intake manifest + pool/lane/bootstrap 冻结 |
| `XT-W3-22` | `XT-L1` | `XT-L2`, `Hub-L5`, `QA` | Acceptance Pack + 证据完整性 + 回滚锚点 |
| `XT-W3-23` | `XT-L2` | `XT-L1`, `Hub-L5`, `QA` | XT 记忆 UX 适配层 + 双通道 + Memory Ops Console + Supervisor Memory Bus |
| `XT-W3-24` | `XT-L1` | `XT-L2`, `Hub-L5`, `QA` | 多渠道入口 + streaming UX + onboard/status + Hub boundary |
| `XT-W3-20` | `XT-L2` | `AI-COORD-PRIMARY`, `Hub-L5` | CR 裁决 + freeze window 执行 |

## 3) 任务级执行包（DoR/步骤/DoD/Gate/KPI/回归）

### 3.1 `XT-W2-20` 多泳池复杂度规划器

- 目标：输入项目复杂度与模块图，输出 `pool_count + pool_boundary + explain`，且同输入可复现。
- DoR：
  - 已冻结 `complexity_score/module_count/dependency_density/risk_surface/deadline_pressure` 输入字段。
  - 已确认 `XT-MP-G0/G1` 判定字段与报告路径。
- 实施子步骤：
  1. 落地 `PoolPlanner` 评分器与 deterministic 公式（与主工单 1.4 对齐）。
  2. 增加 `pool_plan.explain` 字段（至少包含 top3 影响因子）。
  3. 实现 `cross_pool_cycle` 检查，命中即 fail-closed。
  4. 写入审计事件：`supervisor.pool_plan.proposed`、`supervisor.pool_plan.blocked`。
  5. 产出机读证据：`build/reports/xt_w2_20_pool_planner_evidence.v1.json`。
- DoD：
  - 同输入 + 同 profile 输出 hash 一致（100 组样本，允许 0 漂移）。
  - 任一 `cross_pool_cycle=true` 必阻断执行并可审计追溯。
- Gate/KPI：
  - Gate: `XT-MP-G0`, `XT-MP-G1`
  - KPI: `pool_plan_ready_p95_ms <= 5000`, `profile_determinism = 100%`
- 回归样例：
  - `simple_project` 被误拆多池：自动收敛到单池。
  - 人工注入环依赖：必须 `blocked` 且附 `deny_code`。

### 3.1b `XT-W2-20-B` 防堵塞拆分器（挂靠）

- 目标：在拆分阶段降低阻塞概率，避免后续“多泳道互等”。
- 实现细化入口：`x-terminal/work-orders/xt-cbl-anti-block-context-governor-implementation-pack-v1.md`
- DoR：
  - `XT-W2-20/XT-W2-21` 已能输出 pool plan 与 lane DAG。
  - 可读取依赖密度、跨池边、风险等级字段。
- 实施子步骤：
  1. 计算 `block_risk_score` 并写入 lane metadata。
  2. 施加硬约束：`depends_on<=2`, `fan_in<=2`, `fan_out<=3`。
  3. 强制两波执行：`contract_freeze_wave -> feature_wave`。
  4. 命中 `cross_pool_cycle=true` 直接 fail-closed。
  5. 产出机读证据：`build/reports/xt_w2_20_b_block_aware_split_evidence.v1.json`。
- DoD：
  - 拆分结果满足依赖约束上限。
  - contract wave 未转绿时 feature wave 不可启动。
- Gate/KPI：
  - Gate: `XT-MP-G0`, `XT-MP-G1`, `XT-MP-G3`
  - KPI: `cross_pool_dependency_density <= 0.25`, `avg_lane_depends_on <= 2.0`
- 回归样例：
  - 生成计划包含跨池环路仍放行：判失败。
  - 高风险模块拆分后依赖扇入>2：判失败。

### 3.2 `XT-W2-21` 二级子任务合成器

- 目标：每个 pool 自动拆 lane DAG，并保证 `lane_dod_coverage=100%`。
- DoR：
  - `XT-W2-20` 已产出稳定 `pool_plan_id`。
  - lane 结构最小字段冻结（`lane_id/goal/depends_on/dod_checklist/assigned_ai_profile`）。
- 实施子步骤：
  1. 落地 `LaneSynthesizer`（按 pool scope 生成 lane DAG）。
  2. 生成 lane 级 DoD 模板（输入/输出/验收动作/证据项）。
  3. 增加边界校验：lane 不可跨 pool 直接写产物。
  4. 落盘审计：`supervisor.lane_plan.generated`。
  5. 产出机读证据：`build/reports/xt_w2_21_lane_synth_evidence.v1.json`。
- DoD：
  - 所有 lane 均含完整 DoD，且 lane DAG 无环。
  - 任一 lane 缺 DoD 时禁止进入启动态。
- Gate/KPI：
  - Gate: `XT-MP-G0`
  - KPI: `lane_dod_coverage = 100%`
- 回归样例：
  - `missing_dod` lane：阻断并提示修复字段。
  - `cross_pool_write_attempt`：阻断并审计。

### 3.3 `XT-W2-22` 档位引擎（保守/平衡/激进）

- 目标：档位驱动拆分粒度与并发上限，并在高风险场景自动降档。
- DoR：
  - `XT-W2-20/21` 已可输出稳定 pool+lane 结构。
  - `risk_surface` 与授权完整性输入可读。
- 实施子步骤：
  1. 落地 `SplitProfileEngine` 参数表（粒度、并发、重排频率）。
  2. 实现 `risk>=T2 or grant_incomplete -> auto_downgrade`。
  3. 记录 `profile_selected/profile_downgraded` 审计事件。
  4. 增加 deterministic 校验（同输入同档位同输出）。
  5. 产出机读证据：`build/reports/xt_w2_22_profile_engine_evidence.v1.json`。
- DoD：
  - `aggressive` 粒度 > `balanced` > `conservative`（统计上单调）。
  - 高风险无授权绝不以激进档执行外部副作用。
- Gate/KPI：
  - Gate: `XT-MP-G1`, `XT-MP-G3`
  - KPI: `profile_determinism = 100%`, `high_risk_lane_without_grant = 0`
- 回归样例：
  - 低风险项目：aggressive lane 数应显著增加。
  - 高风险无授权：必须自动降档并阻断副作用。

### 3.4 `XT-W2-23` 参与等级引擎

- 目标：把用户参与策略收敛为可执行策略树，减少不必要打断。
- 实现细化入口：`x-terminal/work-orders/xt-w2-23-w2-26-autocontinue-autonomy-implementation-pack-v1.md`
- DoR：
  - 已定义 `zero_touch/critical_touch/guided_touch` 三模式语义（兼容旧值 `hands_off/critical_only/interactive`）。
  - 已定义关键触点类型（授权、重排、失败升级、交付）。
- 实施子步骤：
  1. 落地 `ParticipationPolicyEngine` 策略表。
  2. 绑定通知策略（事件类型 -> 是否触达用户 -> 触达模板）。
  3. 实现 `zero_touch` 降噪：非关键事件不通知（兼容旧值 `hands_off`）。
  4. 增加关键事件漏发保护（漏发即 Gate fail）。
  5. 产出机读证据：`build/reports/xt_w2_23_participation_evidence.v1.json`。
- DoD：
  - `zero_touch` 仅高风险授权与关键升级打断用户。
  - `critical_touch` 下关键事件通知完整率 100%。
- Gate/KPI：
  - Gate: `XT-MP-G3`
  - KPI: `user_interrupt_rate(zero_touch) <= 0.15`, `critical_notify_latency_p95_ms <= 1500`
- 回归样例：
  - 普通日志事件被频繁通知：判失败。
  - 高风险授权缺通知：判失败。

### 3.4a `XT-W2-23-B` 创新分档引擎 + UI 选择器（挂靠）

- 目标：让用户在 UI 中直接选择创新档位 `L0..L4`，并驱动 Supervisor 执行策略。
- 实现细化入口：`x-terminal/work-orders/xt-w2-23-w2-26-autocontinue-autonomy-implementation-pack-v1.md`
- DoR：
  - `XT-W2-23` 参与等级引擎可用。
  - UI 可读取/写入 Supervisor 配置项。
- 实施子步骤：
  1. 落地 `InnovationLevel` 配置（L0/L1/L2/L3/L4）与默认值 `L1_micro_reflect`。
  2. 在 UI 增加档位选择器与档位说明文案。
  3. 建立档位->执行策略映射（建议频率、是否允许实验分支、冻结窗降档）。
  4. 审计事件：`supervisor.innovation_level.changed`。
  5. 产出机读证据：`build/reports/xt_w2_23_b_innovation_level_ui_evidence.v1.json`。
- DoD：
  - 五档可选、可持久化、可回放。
  - 冻结窗自动降档逻辑稳定生效。
- Gate/KPI：
  - Gate: `XT-MP-G3`, `XT-MP-G5`
  - KPI: `innovation_level_apply_success_rate = 100%`, `freeze_window_forced_downgrade_miss = 0`
- 回归样例：
  - 非法档位值被接受 -> 失败。
  - 冻结窗进入后仍停留 L3/L4 -> 失败。

### 3.4b `XT-W2-23-C` 建议治理路由器（挂靠）

- 目标：在创新与效率之间取得平衡，统一建议流（supervisor_only/hybrid/lane_open）。
- 实现细化入口：`x-terminal/work-orders/xt-w2-23-w2-26-autocontinue-autonomy-implementation-pack-v1.md`
- DoR：
  - 已定义建议卡契约（Lane Insight Card）。
  - Command Board 已具备 Insight Outbox/Inbox 字段契约。
- 实施子步骤：
  1. 落地 `SuggestionGovernanceEvaluator`（三模式路由）。
  2. 接入触发器（重复失败/长阻塞/token收益/质量收益/安全风险）。
  3. 实施建议限流（每 lane 每 4h 上限）与去重。
  4. 将 triage 输出写入 Supervisor Insight Inbox（adopt/reject/park + reason）。
  5. 产出机读证据：`build/reports/xt_w2_23_c_suggestion_governance_evidence.v1.json`。
- DoD：
  - `hybrid` 下仅触发式建议；`supervisor_only` 下泳道不可提建议。
  - `requires_user_decision=true` 建议自动升级到用户决策流。
- Gate/KPI：
  - Gate: `XT-MP-G3`, `XT-MP-G5`
  - KPI: `suggestion_noise_ratio <= 0.20`, `suggestion_token_overhead_ratio <= 0.08`, `high_value_suggestion_adoption_rate >= 0.60`
- 回归样例：
  - `supervisor_only` 仍出现泳道建议 -> 失败。
  - 无触发条件的建议未被限流 -> 失败。
  - 需要用户决策建议未升级 -> 失败。

### 3.5 `XT-W2-24` Prompt Pack 编译器与注册表

- 目标：每个 pool/lane AI 自动拿到角色化提示词包，并保证 lint 合规。
- 实现细化入口：`x-terminal/work-orders/xt-w2-24-token-optimal-context-capsule-implementation-pack-v1.md`
- DoR：
  - `XT-W2-21/23` 已输出 lane 与参与策略。
  - Prompt Pack 字段契约冻结（`goal/inputs/outputs/dod/risk_boundaries/prohibitions/rollback_points/gate_hooks`）。
  - 三段式契约冻结（`Stable Core + Task Delta + Context Refs`）。
- 实施子步骤：
  1. 落地 `PromptPackCompiler`（按 role 产包）。
  2. 落地 `PromptPackRegistry`（版本化、可追溯、可回滚）。
  3. 实现 lint 阻断（缺关键字段即禁止下发）。
  4. 强制三段式输出，`context_refs` 只允许 ID 引用，不贴全文上下文。
  5. 产出机读证据：`build/reports/xt_w2_24_prompt_pack_evidence.v1.json`。
- DoD：
  - `prompt_pack_coverage = 100%`。
  - `tri_prompt_coverage = 100%`。
  - 任一缺 `gate_hooks` 或 `rollback_points` 包均被阻断。
- Gate/KPI：
  - Gate: `XT-MP-G2`
  - KPI: `prompt_pack_coverage = 100%`, `tri_prompt_coverage = 100%`, `prompt_token_waste_ratio <= 0.12`
- 回归样例：
  - 构造缺字段包：必须 lint fail。
  - 版本回放：旧版本包可复现加载。
  - 拼贴全量聊天记录而不是 `context_refs`：必须阻断。

### 3.5f `XT-W2-24-F` 会话滚动与上下文胶囊治理器（挂靠）

- 目标：复杂任务中强制会话滚动，防止上下文越跑越长。
- 实现细化入口：`x-terminal/work-orders/xt-cbl-anti-block-context-governor-implementation-pack-v1.md`
- DoR：
  - `XT-W2-24-A/B/C/D` 已上线。
  - Command Board 支持 `delta_3line` 模式。
- 实施子步骤：
  1. 落地 rollover 触发器（`turn_count>=8` 或 `state_transition>=2`）。
  2. 旧会话压缩为 checkpoint JSON（保留 DoD/Gate hooks/ref ids）。
  3. 新会话仅加载 `Stable Core + Task Delta + Context Refs<=3`。
  4. token 预算硬阈值：`active<=450`、`standby<=120`。
  5. 产出机读证据：`build/reports/xt_w2_24_f_session_rollover_evidence.v1.json`。
- DoD：
  - rollover 后语义连续且可追溯。
  - 无增量状态禁止 full 7 件套长报。
- Gate/KPI：
  - Gate: `XT-MP-G2`, `XT-MP-G3`, `XT-MP-G5`
  - KPI: `prompt_token_waste_ratio <= 0.12`, `full_history_prompt_usage = 0`, `rollover_recovery_success_rate >= 0.99`
- 回归样例：
  - 超阈值未 rollover：判失败。
  - rollover 后 DoD/Gate hooks 丢失：判失败。

### 3.6 `XT-W2-25` Pool 调度器

- 目标：池间/池内并发稳定，既可抢占又不饥饿。
- DoR：
  - `XT-W2-22` 已提供 profile 与 cap。
  - `XT-W2-24` 已保证所有 lane 有有效 prompt。
- 实施子步骤：
  1. 落地 `PoolScheduler`（pool cap + lane cap + fairness）。
  2. 增加高优先 pool 抢占策略与回退策略。
  3. 增加 anti-starvation（等待时长阈值 + boost）。
  4. 增加队列稳定性审计事件。
  5. 产出机读证据：`build/reports/xt_w2_25_scheduler_evidence.v1.json`。
- DoD：
  - 高优先可抢占，低优先不长期饿死。
  - 并发上限受 `risk_cap` 和 `token_cap` 双约束。
- Gate/KPI：
  - Gate: `XT-MP-G1`, `XT-MP-G3`, `XT-MP-G4`
  - KPI: `queue_starvation_incidents = 0`
- 回归样例：
  - 激进档压测出现饥饿：应被修复后归零。
  - cap 越界执行：应 fail-closed。

### 3.6b `XT-W2-25-B` 关键路径动态席位调度器（挂靠）

- 目标：把 Active-3 升级为关键路径动态席位，提升解阻吞吐。
- 实现细化入口：`x-terminal/work-orders/xt-cbl-anti-block-context-governor-implementation-pack-v1.md`
- DoR：
  - `XT-W2-25` 基础调度可运行。
  - `XT-W2-27` wait-for 图可用。
- 实施子步骤：
  1. 落地 `CriticalPathSeatAllocator`（按 critical_path_rank + block_risk_score 排序）。
  2. 非关键 lane 自动降级到 standby。
  3. 连续 2 窗口无增量自动释放 active 席位。
  4. 记录席位变更审计（before/after/preempt_reason）。
  5. 产出机读证据：`build/reports/xt_w2_25_b_active3_dynamic_seat_evidence.v1.json`。
- DoD：
  - active 席位永远 `<=3`。
  - release blocker 任务不会被低优先 lane 抢占。
- Gate/KPI：
  - Gate: `XT-MP-G3`, `XT-MP-G4`
  - KPI: `active_lane_count_violations = 0`, `critical_path_preempt_success_rate >= 0.98`, `queue_starvation_incidents = 0`
- 回归样例：
  - non-critical lane 长时间占用 active：判失败。
  - active 溢出不回收：判失败。

### 3.7 `XT-W2-26` 自治推进控制器

- 目标：lane -> pool -> global 自动推进，异常自动升级，不越权。
- 实现细化入口：`x-terminal/work-orders/xt-w2-23-w2-26-autocontinue-autonomy-implementation-pack-v1.md`
- DoR：
  - `XT-W2-25` 调度器可稳定输出运行序列。
  - 事件分类（grant_pending/awaiting_instruction/runtime_error）可观测。
- 实施子步骤：
  1. 落地 auto-advance 状态机与暂停/恢复点。
  2. 绑定 incident triage（自动处理 vs 通知用户）。
  3. 增加越权保护（高风险无授权不可自动推进）。
  4. 增加 stuck 检测和升级路径。
  5. 产出机读证据：`build/reports/xt_w2_26_autonomy_evidence.v1.json`。
- DoD：
  - non-high-risk 任务可自动推进到 delivered。
  - high-risk 任务仅授权后推进。
- Gate/KPI：
  - Gate: `XT-MP-G3`, `XT-MP-G4`
  - KPI: `autonomous_progression_rate >= 80%`
- 回归样例：
  - 无授权推进高风险 lane：判失败。
  - blocked 长时间不升级：判失败。

### 3.8 `XT-W2-27` 阻塞依赖图与即时解阻编排器

- 目标：实时识别“谁在等谁”，在 blocker 转绿后秒级引导等待泳道续推。
- 实现细化入口：`x-terminal/work-orders/xt-w2-27-anti-block-unblock-orchestration-implementation-pack-v1.md`
- DoR：
  - `XT-W2-26` completion 与 auto-continue 事件可用。
  - `XT-W2-24` 三段式 prompt 与 `context_refs` 引用策略可用。
- 实施子步骤：
  1. 落地 `WaitGraphArbiter`（阻塞边收集、去重、环检测）。
  2. 落地 `DependencyDualGreenGate`（`contract_green + runtime_green` 双绿判定）。
  3. 落地 `DependencyEscrow`（blocked 任务预托管执行包）。
  4. 落地 `UnblockRouter`（解阻即分发 guidance + 续推建议）。
  5. 落地 `BlockSLAEscalator`（超时升级与证据落盘）。
  6. 产出机读证据：`build/reports/xt_w2_27_unblock_orchestration_evidence.v1.json`。
- DoD：
  - wait-for 图可追溯且无环（命中环即 fail-closed）。
  - blocker 双绿后等待泳道可在 SLA 内收到继续指导并恢复执行。
- Gate/KPI：
  - Gate: `XT-MP-G3`, `XT-MP-G4`, `XT-MP-G5`
  - KPI: `false_unblock_due_to_single_green = 0`, `unblock_notify_latency_p95_ms <= 1200`, `unresolved_block_over_sla_rate <= 0.05`
- 回归样例：
  - 单绿误放行 -> 失败。
  - blocker 已绿但 waiter 未收到 guidance -> 失败。
  - 超 SLA 未升级 -> 失败。

### 3.8a `XT-W2-27-F` 自托管关键路径解阻器（挂靠）

- 目标：当 x-hub-system 自己推进时，自动切换 `critical_path_mode`，优先消解 release blocker 依赖链。
- DoR：
  - `XT-W2-27-B` 双绿判定可用。
  - Command Board 可读取 `release_blocker/depends_on/status/gate_vector` 字段。
- 实施子步骤：
  1. 落地 `CriticalPathArbiter`（提取 release blocker DAG + 关键边排序）。
  2. 落地 `UnblockBatonDispatcher`（转绿后写入 `next_owner_lane/unblock_owner/next_step`）。
  3. 启用 `critical_path_mode` 时下调非关键任务优先级，防止解阻资源被抢占。
  4. 增加超时升级：关键链边超过 SLA 自动升级 `AI-COORD-PRIMARY`。
  5. 产出机读证据：`build/reports/xt_w2_27_f_self_host_unblock_evidence.v1.json`。
- DoD：
  - 关键链可观测、可解释、可回放。
  - blocker 双绿后可在 1 跳内触发 waiter lane 续推。
- Gate/KPI：
  - Gate: `XT-MP-G3`, `XT-MP-G4`, `XT-MP-G5`
  - KPI: `self_host_unblock_mtta_p95_ms <= 1800`, `critical_path_blocked_chain_age_p95_ms <= 7200000`
- 回归样例：
  - 关键边转绿但 baton 未派发 -> 失败。
  - critical_path_mode 启用仍被非关键任务抢占 -> 失败。

### 3.8b `XT-W2-28` 无拥塞推进协议（Jamless，挂靠）

- 目标：把“多泳道互等 + 重复 blocked 长报 + 无增量 gate 重试”收敛为机判规则，持续降低阻塞年龄与 token 消耗。
- 实现细化入口：`x-terminal/work-orders/xt-w2-28-jamless-anti-congestion-protocol-implementation-pack-v1.md`
- DoR：
  - `XT-W2-27-F` 关键路径模式可用。
  - Command Board 支持 `blocked_reason_hash/evidence_delta_hash/retry_after_utc` 字段。
- 实施子步骤：
  1. 落地 `Active-3 WIP Governor`（7 泳道模式 active<=3）。
  2. 落地 `Directed Baton Router`（禁止全泳道广播）。
  3. 落地 `Blocked Dedupe + Delta Reporter`（同 hash 仅首条 full 7 件套）。
  4. 落地 `Deadlock SCC Breaker`（5 分钟窗口解环）。
  5. 落地 `Gate Retry Cooldown`（无增量证据禁止重跑）。
  6. 产出机读证据：`build/reports/xt_w2_28_jamless_evidence.v1.json`。
- DoD：
  - `duplicate_blocked_report_count = 0`。
  - `invalid_gate_retry_count = 0`。
  - `baton_dispatch_latency_p95_ms <= 1200`。
- Gate/KPI：
  - Gate: `XT-MP-G3`, `XT-MP-G4`, `XT-MP-G5`
  - KPI: `token_per_notification_p95_delta <= -35%`, `deadlock_break_time_p95_ms <= 60000`
- 回归样例：
  - blocker 转绿仍全泳道广播 -> 失败。
  - 同阻塞原因反复 full 7 件套 -> 失败。
  - 无证据增量仍重跑 release gate -> 失败。

### 3.8c `XT-W2-28-F` 阻塞预测 + 自动重排守门（挂靠）

- 目标：在“完全堵死”前触发自动处置，缩短阻塞链年龄。
- 实现细化入口：`x-terminal/work-orders/xt-cbl-anti-block-context-governor-implementation-pack-v1.md`
- DoR：
  - `XT-W2-28` Jamless v1 已启用。
  - Command Board `CR Inbox` 可机判接入重排动作。
- 实施子步骤：
  1. 落地 `BlockRiskPredictor`（预测未来 30 分钟堵塞概率）。
  2. 落地触发器：`20min 无增量 -> checkpoint`，`40min -> 换 breaker`，`60min -> 自动 CR 重排`。
  3. 增加收益守门：不满足并发收益阈值自动 `aggressive -> balanced`。
  4. 重排审计输出 `trigger_reason/old_plan/new_plan/rollback_point`。
  5. 产出机读证据：`build/reports/xt_w2_28_f_block_predict_replan_guard_evidence.v1.json`。
- DoD：
  - 长阻塞链可被提前识别并触发可解释处置。
  - 自动重排不破坏 release blocker 优先级。
- Gate/KPI：
  - Gate: `XT-MP-G3`, `XT-MP-G4`, `XT-MP-G5`
  - KPI: `blocked_chain_age_p95_ms <= 7200000`, `deadlock_break_time_p95_ms <= 60000`, `replan_latency_p95_ms <= 3000`
- 回归样例：
  - 60 分钟无增量却未重排 -> 失败。
  - 普通任务抢占 release blocker -> 失败。
  - 收益不足仍停留 aggressive -> 失败。

### 3.9 `XT-W3-18` 池内/全局集成测试编排器

- 目标：先池内后全局，失败可回滚并给修复建议。
- DoR：
  - `XT-W2-27` 解阻编排链路可运行。
  - 测试矩阵（pool-level/global-level）定义完成。
- 实施子步骤：
  1. 落地 `PoolIntegrationOrchestrator`。
  2. 阻断策略：池内失败不得进入全局合并。
  3. 回滚到 pool 稳定点并记录回滚证据。
  4. 输出失败归因报告（修复建议）。
  5. 产出机读证据：`build/reports/xt_w3_18_integration_evidence.v1.json`。
- DoD：
  - 池内失败不能误放行全局。
  - 回滚后状态一致性可校验。
- Gate/KPI：
  - Gate: `XT-MP-G4`, `XT-MP-G5`
  - KPI: `pool_integration_first_pass_rate >= 75%`
- 回归样例：
  - 强制注入 pool 失败仍触发全局：判失败。
  - 回滚后引用断链：判失败。

### 3.10 `XT-W3-19` 交付通知与执行摘要

- 目标：自动通知用户“结果 + 风险 + 证据 + 回滚点 + 下一步建议”。
- DoR：
  - `XT-W3-18` 输出可用。
  - `XT-W2-23` 用户参与等级可读。
- 实施子步骤：
  1. 落地 `DeliveryNotifier` 与三档模板（静默/摘要/完整）。
  2. 绑定 evidence 链接完整性校验（缺链则阻断“完成”通知）。
  3. 适配参与等级（`zero_touch` 仅关键通知，兼容 `hands_off`）。
  4. 记录通知发送审计。
  5. 产出机读证据：`build/reports/xt_w3_19_delivery_notify_evidence.v1.json`。
- DoD：
  - 通知完整度 100%，引用可点击可追溯。
  - 非关键噪音通知受 participation policy 约束。
- Gate/KPI：
  - Gate: `XT-MP-G5`
  - KPI: `delivery_notification_completeness = 100%`
- 回归样例：
  - 缺 evidence 仍发送“完成”：判失败。
  - zero_touch 下普通事件频繁通知：判失败。

### 3.11 `XT-W3-20` 动态重规划治理器（P1）

- 目标：用户临时改需求时，自动 CR 裁决与任务重排，不冲掉 release blocker。
- DoR：
  - Command Board 的 `CR Inbox` 和 `Task Catalog` 可机判。
  - freeze window 规则冻结。
- 实施子步骤：
  1. 落地 `ReplanGovernor`（优先级、影响面、抢占策略）。
  2. 落地 `CRArbiter`（accepted/queued/rejected 的判定逻辑）。
  3. 增加 release blocker 保护（不可被普通 CR 抢占）。
  4. 落地重排审计与回放能力。
  5. 产出机读证据：`build/reports/xt_w3_20_replan_evidence.v1.json`。
- DoD：
  - CR 处理可解释且可回放。
  - 重排不破坏高优先 release blocker 链路。
- Gate/KPI：
  - Gate: `XT-MP-G1`, `XT-MP-G3`, `XT-MP-G5`
  - KPI: `replan_latency_p95_ms <= 3000`
- 回归样例：
  - P1 CR 抢占 P0 release blocker：判失败。
  - freeze window 内未按策略排队：判失败。

### 3.12 `XT-W2-25-S1` 激进档并发-成本治理器（挂靠 `XT-W2-25`）

- 目标：在“可并发很多 lane”时，动态判断是否真的划算，避免 100 lane 并发导致成本失控或收益递减。
- DoR：
  - `XT-W2-22` 已输出 profile 与风险分布。
  - `XT-W2-25` 已具备基础调度能力与队列观测。
- 实施子步骤：
  1. 新增 `AggressiveEconomicsEvaluator`，计算 `predicted_parallel_speedup`、`predicted_merge_tax_ratio`、`predicted_token_spend`。
  2. 在调度入口增加 `aggressive_admission_gate`：不达标自动回落 `balanced`。
  3. 实现运行时复核（每 15 分钟 / 每 20 lane 完成触发）与自动降档。
  4. 增加预算护栏：`max_active_paid_lanes` 与 `token_burn_rate_per_hour` 双闸。
  5. 输出机读证据：`build/reports/xt_w2_25_s1_aggressive_economics_evidence.v1.json`。
- DoD：
  - 激进档仅在收益达标时启动；不达标自动降档且可审计。
  - 不出现“预算超限仍继续扩并发”的越界行为。
- Gate/KPI：
  - Gate: `XT-MP-G1`, `XT-MP-G3`, `XT-MP-G4`
  - KPI: `parallel_efficiency_ratio >= 0.35`, `aggressive_cost_delta_vs_balanced <= +15%`
- 回归样例：
  - 低收益场景仍保持 aggressive -> 失败。
  - token burn 超阈值未降档 -> 失败。

### 3.13 `XT-W3-18-S1` 大规模拼装收敛器（挂靠 `XT-W3-18`）

- 目标：应对 50~108 lane 输出拼装挑战，保证“可并行、可收敛、可回滚”。
- DoR：
  - pool/lane 产物都带 schema hash 与 lineage 引用。
  - `XT-W3-18` 池内测试流水线已可运行。
- 实施子步骤：
  1. 落地 `AssemblyWavePlanner`（按 `merge_chunk <= 6 lanes` 波次合并）。
  2. 增加 `ContractFreezeGate`（跨池接口 hash 漂移即阻断）。
  3. 落地冲突分流：语义冲突 -> 回 lane 修复，结构冲突 -> 回 pool 修复。
  4. 为每个波次写稳定点与回滚锚点（`stable_point_id`）。
  5. 输出机读证据：`build/reports/xt_w3_18_s1_assembly_convergence_evidence.v1.json`。
- DoD：
  - 100 lane 级别下仍能分波次收敛，不出现全局雪崩回滚。
  - 任一接口漂移都可被 gate 阻断并定位责任 lane。
- Gate/KPI：
  - Gate: `XT-MP-G4`, `XT-MP-G5`
  - KPI: `merge_tax_ratio <= 0.30`, `cross_pool_conflict_reopen_rate <= 0.08`
- 回归样例：
  - 跳过 pool 集成直接全局合并 -> 失败。
  - contract hash 漂移未被阻断 -> 失败。

### 3.14 `XT-W3-19-S1` 成本收益可视化摘要器（挂靠 `XT-W3-19`）

- 目标：交付时让用户看清“快了多少、贵了多少、值不值”，支持继续用激进档或回落决策。
- DoR：
  - 已有真实运行样本（非 synthetic）可计算 speedup/token/cost。
  - `XT-W3-19` 通知链路可带附件证据。
- 实施子步骤：
  1. 新增 `DeliveryEconomicsSnapshot`（`baseline_vs_actual`：wall-time、token、cost、merge tax）。
  2. 在通知模板中增加“激进档 ROI 结论”：`recommend_keep|recommend_downgrade`。
  3. 增加样本充足性校验（样本不足时输出 `INSUFFICIENT_EVIDENCE`）。
  4. 回填 Command Board evidence refs（仅追加，不改跨泳道行）。
  5. 输出机读证据：`build/reports/xt_w3_19_s1_delivery_economics_evidence.v1.json`。
- DoD：
  - 每次交付都给出可追溯 ROI 摘要，不再凭主观判断“激进是否划算”。
  - 样本不足不会输出乐观结论，严格 fail-closed。
- Gate/KPI：
  - Gate: `XT-MP-G5`
  - KPI: `delivery_economics_snapshot_coverage = 100%`, `insufficient_sample_false_green = 0`
- 回归样例：
  - 无真实样本却输出“激进更优” -> 失败。
  - 通知缺 ROI 字段仍标记完成 -> 失败。

### 3.15 `XT-W3-21` Project Intake Manifest（跨阶段能力）

- 目标：让 Supervisor 能直接读取项目 `md/spec/work-order` 输入包，自动生成可执行 intake manifest，再驱动 `pool -> lane -> AI`。
- 实现细化入口：`x-terminal/work-orders/xt-w3-21-w3-22-supervisor-intake-acceptance-implementation-pack-v1.md`
- DoR：
  - `XT-W2-20..XT-W2-25` 基础拆分、档位、参与等级、Prompt Pack 已可用。
  - Command Board 支持 `Context Refs` 引用与 `CR/Decision` 绑定。
- 实施子步骤：
  1. 落地 `ProjectIntakeExtractor` 与 `IntakeConflictArbiter`。
  2. 落地 `ProjectIntakeManifestBuilder` 与 `IntakeFreezeGate`。
  3. 将 `pool_plan + lane_plan + prompt_pack_refs + touch_policy` 绑定为启动包。
  4. 产出机读证据：`build/reports/xt_w3_21_project_intake_manifest.v1.json`。
- DoD：
  - 一组项目文档可自动转为 machine-readable intake manifest。
  - intake 不完整时 fail-closed，不直接开工。
- Gate/KPI：
  - Gate: `XT-MP-G0`, `XT-MP-G1`, `XT-MP-G3`
  - KPI: `intake_required_field_coverage = 100%`, `intake_to_pool_plan_p95_ms <= 3000`
- 回归样例：
  - scope 不完整仍开工 -> 失败。
  - 高风险授权边界不清却继续自动拆分 -> 失败。

### 3.16 `XT-W3-22` Acceptance Pack（跨阶段能力）

- 目标：把“能跑”变成“可交付”，自动汇总结果、风险、证据、回滚点与下一步建议。
- 实现细化入口：`x-terminal/work-orders/xt-w3-21-w3-22-supervisor-intake-acceptance-implementation-pack-v1.md`
- DoR：
  - `XT-W3-18` 集成输出可用。
  - `XT-W3-19` 通知模板与 evidence refs 可用。
- 实施子步骤：
  1. 落地 `AcceptanceEvidenceAggregator`。
  2. 落地 `AcceptanceLinkValidator` 与 `AcceptanceDecisionCompiler`。
  3. 输出 `xt.acceptance_pack.v1` 与用户摘要。
  4. 产出机读证据：`build/reports/xt_w3_22_acceptance_pack.v1.json`。
- DoD：
  - 缺证据或缺回滚点时不会误发 accepted。
  - 用户可直接看到结果、风险、证据、回滚点、下一步建议。
- Gate/KPI：
  - Gate: `XT-MP-G5`
  - KPI: `acceptance_evidence_link_completeness = 100%`, `completion_without_rollback_ref = 0`
- 回归样例：
  - evidence 缺失仍 accepted -> 失败。
  - rollback_ref 缺失仍发送完成通知 -> 失败。


### 3.17 `XT-W3-23` XT 记忆 UX 适配层 / Supervisor Memory Bus（跨阶段能力）

- 目标：让 XT 拥有即插即用 `session continuity` 体验、显式 `user/project` 记忆双通道、记忆操作台、最小暴露注入守门，以及供 Supervisor 使用的记忆总线。
- 实现细化入口：`x-terminal/work-orders/xt-w3-23-memory-ux-adapter-implementation-pack-v1.md`
- DoR：
  - Hub Memory v3 五层模型、remote export gate、Longterm Markdown 操作链已冻结。
  - `XT-W2-24`、`XT-W2-27`、`XT-W3-21`、`XT-W3-22` 已提供 token 胶囊、定向解阻、接案与验收入口。
- 实施子步骤：
  1. 冻结 `xt.memory_context_capsule/channel_selector/operation_request/injection_policy/supervisor_memory_bus_event` 五类契约。
  2. 落地 `session continuity` 胶囊拉取与 `/memory refresh`。
  3. 落地 `user/project` 双通道 selector 与预算切分。
  4. 落地 `Memory Operations Console`，把 `view/edit/review/writeback/rollback` 全部路由到 Hub 审计链。
  5. 落地最小暴露注入守门与 Supervisor memory bus。
  6. 产出机读证据：`build/reports/xt_w3_23_memory_ux_adapter.v1.json`。
- DoD：
  - XT 仍是 Hub 记忆的 UX 层，不形成第二真相源。
  - 会话启动、blocked 续推、acceptance 收口均可消费 scope-safe 记忆胶囊。
  - 记忆编辑、回写、回滚与远程外发都具备 fail-closed 守门。
- Gate/KPI：
  - Gate: `XT-MEM-G0..G5` + `XT-MP-G4/G5`
  - KPI: `duplicate_memory_store_count = 0`, `session_continuity_relevance_pass_rate >= 0.90`, `supervisor_memory_resume_success_rate >= 0.95`
- 回归样例：
  - XT 本地写入第二套 canonical memory -> 失败。
  - 用户记忆跨项目误注入 -> 失败。
  - secret 记忆被远程 prompt bundle 外发 -> 失败。


### 3.18 `XT-W3-24` 多渠道入口与流式体验产品化（跨阶段能力）

- 目标：吸收成熟 bot 产品在“多渠道接入、快速上手、流式输出、会话运维”上的优势，但底层继续走 Hub-first 的记忆、授权、审计与 connectors 主链。
- 实现细化入口：`x-terminal/work-orders/xt-w3-24-multichannel-gateway-productization-implementation-pack-v1.md`
- DoR：
  - `docs/xhub-client-modes-and-connectors-v1.md` 已冻结 Mode 2（AI + Connectors）与 kill-switch 基线。
  - `XT-W3-21/22/23` 已提供接案、验收、记忆 UX 适配层。
  - Hub 已具备 connector ingress / webhook replay / scope gate / audit fail-closed 的基线实现。
- 实施子步骤：
  1. 冻结 gateway/session/streaming/operator/onboard/boundary 六类契约。
  2. 落地首版 `Telegram + Slack + Feishu` 三渠道 gateway。
  3. 落地 streaming UX 与 fallback，不暴露 raw CoT。
  4. 落地 operator console（sessions/status/restart/logs/heartbeat）。
  5. 落地最小可运行 onboarding / bootstrap / smoke 路径。
  6. 把渠道 token / webhook / side effect / prompt export 全部挂到 Hub 边界与审计主链。
- DoD：
  - 多渠道入口具备“像 bot 一样好上手”的产品面，但不形成第二安全/记忆后端。
  - 新用户可按最短路径启动首版 gateway，并通过 smoke 验证。
  - 渠道层失败、降级、重启、恢复与回滚都有证据与解释。
- Gate/KPI：
  - Gate: `XT-CHAN-G0..G5` + `XT-MP-G4/G5`
  - KPI: `first_wave_channel_coverage = 3/3`, `channel_delivery_success_rate >= 0.98`, `cross_channel_session_leak = 0`
- 回归样例：
  - 渠道层绕过 Hub 直接执行高风险 side effect -> 失败。
  - streaming 通道掉线后无 fallback/final answer -> 失败。
  - onboarding 成功但首条消息无法投递 -> 失败。

## 4) 泳道 AI 统一开工清单（每次任务前都执行）

1. 读取：`docs/memory-new/xhub-lane-command-board-v2.md`
2. 确认本 lane 当前 `active_task/queue_head/backlog_next`。
3. 校验依赖任务 Gate 状态；未满足则保持 `ready/planned` 不冒进。
4. 写入 `claim_id + claim_ttl_until`（默认 4h）。
5. 仅在自己泳道分区更新 7 件套，不越权改别的 lane。
6. 若启用 `critical_path_mode`，先确认自己是否在关键链；不在关键链则避免抢占执行资源。

## 5) “继续”自动推进协议（No-stop 推进）

当泳道 AI 收到用户或总控消息“继续”时，执行以下逻辑：

1. 若本泳道存在 `claimed|in_progress` 任务：继续当前任务，不换题。
2. 若当前任务 `delivered` 且依赖满足：自动 claim `backlog_next` 的下一项并进入执行。
3. 若无可执行任务：在本泳道分区写明 `blocked_reason + 需要谁解锁`，再等待外部输入。
4. 仅在以下场景打断用户：高风险授权、不可逆动作、跨泳道契约变更（Yellow/Red）。

禁止动作：
- 口头“完成”但未更新 7件套；
- Gate 未过却将状态写成 `closed`；
- 用 synthetic 证据冒充 require-real。

## 6) 交付 7件套最小模板（必须原样包含）

1) Scope  
2) Changes（文件 + 行号 + 关键行为）  
3) DoD（checkbox）  
4) Gate（PASS/FAIL/INSUFFICIENT_EVIDENCE + 证据路径）  
5) KPI Snapshot（数字 + 报告路径）  
6) Risks & Rollback（风险 + 开关/回滚点）  
7) Handoff（next_owner_lane + depends_on + unblock 条件）

## 7) 发布约束（防“快但不稳”）

- 即使开发完成，若 `XT-MP-G4/G5` 证据不足，也只能 `delivered` 不可 `closed`。
- 默认不允许跨泳道并发改 contract；如需变更必须走 `CR Inbox + Coordinator Decision`。
- 所有任务必须保留回滚点；无回滚点视为 DoD 不完整。
