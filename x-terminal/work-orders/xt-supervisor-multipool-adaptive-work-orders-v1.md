# X-Terminal Supervisor 多泳池自适应拆分与自治推进工单（Pool+Lane v1）

- version: v1.8
- updatedAt: 2026-03-03
- owner: X-Terminal Supervisor（Primary）/ Hub Runtime（Co-owner）/ Security / QA / Product
- status: active
- scope: `x-terminal/`（按复杂度自动分泳池 + 每池多泳道 + 任务自治推进）
- parent:
  - `x-terminal/work-orders/xt-supervisor-autosplit-multilane-work-orders-v1.md`
  - `x-terminal/work-orders/xterminal-parallel-work-orders-v1.md`
  - `x-terminal/work-orders/xt-supervisor-multipool-lane-execution-pack-v1.md`
  - `x-terminal/work-orders/xt-w2-23-w2-26-autocontinue-autonomy-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w2-24-token-optimal-context-capsule-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w2-27-anti-block-unblock-orchestration-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w2-28-jamless-anti-congestion-protocol-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-cbl-anti-block-context-governor-implementation-pack-v1.md`
  - `docs/memory-new/xhub-hub-to-xterminal-capability-gate-v1.md`
  - `docs/memory-new/xhub-lane-command-board-v2.md`
  - `docs/memory-new/xhub-internal-pass-lines-v1.md`

## 0) 成品目标（你关心的能力）

复杂项目进入 Supervisor 后，系统必须具备：

1. 自动基于复杂度与模块图拆成 **多个泳池（pool）**，不是固定 7 条泳道。
2. 每个泳池内再自动拆成 **多泳道（lane）** 作为二级子任务。
3. 支持策略档位：`conservative | balanced | aggressive`（激进档拆得更细、更多并发）。
4. Supervisor 自动为每个 AI 生成提示词包并下发执行。
5. 默认可自治推进到任务完成；用户可选择：
   - 全程不参与（仅高风险授权打断）
   - 仅重要提示和授权
   - 全流程确认
6. 各泳池先做池内集成测试，再做全局合并与回滚校验。
7. 结果自动通知用户（摘要 + 风险 + 证据 + 回滚点）。
8. Supervisor 持续维护阻塞依赖图（wait-for graph），通过 Command Board `I/J`（Dependency Edge Registry + Directed @ Inbox）在 blocker 转绿后秒级指导等待泳道续推。
9. 系统自托管（x-hub-system 自身推进）也必须复用同一解阻协议：关键路径模式 + 解阻接力棒 + 双绿门控，避免“全泳道互等”。
10. 默认启用无拥塞协议（Jamless v1）：`Active-3 + 定向 baton + blocked 去重 + gate 重试冷却`，优先“有效推进”而非“高频汇报”。
11. 默认启用 CBL 循环（Contract-Block-Context）：先做防堵塞拆分，再做关键路径席位治理，最后做会话滚动与上下文压缩。
12. UI 可选择创新分档（`L0..L4`）与建议治理模式（`supervisor_only|hybrid|lane_open`），并由 Supervisor 统一裁决对用户提案。

## 1) 核心模型（Pool + Lane 二级拆分）

### 1.1 定义

- `pool`：按模块边界、风险域、资源预算聚合的一组执行单元。
- `lane`：pool 内可并行执行的二级子任务（最小可验收工作单元）。

### 1.2 输入信号（最小集）

- `complexity_score`（0~100）
- `module_count`
- `dependency_density`
- `risk_surface`（T0~T3）
- `token_budget_total`
- `deadline_pressure`

### 1.3 输出结构

- `pool_plan_id`, `strategy_profile`, `user_participation_mode`
- `pools[]`：
  - `pool_id`, `goal`, `module_scope[]`, `risk_tier`, `budget_class`, `expected_artifacts[]`
  - `pool_concurrency_cap`
  - `lanes[]`：`lane_id`, `goal`, `depends_on[]`, `dod_checklist[]`, `assigned_ai_profile`
- `estimated_wall_time_ms`
- `required_user_touchpoints[]`

### 1.4 自动分池/分道规则（deterministic，便于机判）

为避免“同输入多次规划结果漂移”，默认采用可复现启发式：

- 归一化输入：
  - `c = complexity_score / 100`
  - `m = min(module_count / 20, 1.0)`
  - `d = clamp(dependency_density, 0, 1)`
  - `p = clamp(deadline_pressure, 0, 1)`
  - `r = risk_surface_weight`（`T0=0.0,T1=0.25,T2=0.55,T3=0.85`）
- 拆分压力：
  - `split_pressure = 0.40*c + 0.25*m + 0.20*d + 0.15*p`
- 档位系数：
  - `profile_factor = conservative:0.75 | balanced:1.00 | aggressive:1.35`
- 安全降档系数（风险越高越收敛）：
  - `safety_factor = 1 - 0.35*r`
- pool 数量：
  - `pool_count = clamp(1, 12, round(module_count * (0.10 + 0.22 * split_pressure) * profile_factor * safety_factor))`
- 每池 lane 目标：
  - `lane_target = clamp(1, 9, ceil((pool_scope_module_count * 0.6 + split_pressure * 4) * profile_factor))`
- 并发上限：
  - `lane_concurrency_cap = min(lane_target, profile_cap, risk_cap, token_cap)`
  - `profile_cap`：`conservative=2 | balanced=4 | aggressive=6`
  - `risk_cap`：`T0=6 | T1=5 | T2=3 | T3=2`
  - `token_cap = floor(pool_token_budget / lane_expected_token_cost)`

硬约束：
- `lane_concurrency_cap` 绝不突破 `risk_cap`。
- 若发现 `cross_pool_cycle=true`，强制 `fail-closed` 并阻断运行。
- 若 `high_risk_without_grant=true`，强制降档到 `conservative` 且不启动外部副作用 lane。
- 每条 lane 默认依赖上限：`depends_on<=2`；扇入上限：`fan_in<=2`；扇出上限：`fan_out<=3`。
- 任何 `contract_freeze_state!=green` 的 lane 禁止进入 feature 执行波次。

## 2) 策略档位与参与等级

### 2.1 拆分策略档位（Split Profile）

`conservative`（保守）
- 更少泳池、更少泳道、更少重排
- 推荐：高风险、上线窗口紧张、证据不足阶段

`balanced`（默认）
- 平衡吞吐与稳定性
- 推荐：常规主线推进

`aggressive`（激进）
- 更多泳池、更细泳道、更积极重排
- 推荐：低风险模块并行冲刺、时间敏感交付

### 2.2 用户参与等级（Participation Mode）

`zero_touch`（全程不参与；兼容别名 `hands_off`）
- 除高风险授权/不可逆支付外不打断用户

`critical_touch`（仅关键点介入；兼容别名 `critical_only`，默认）
- 关键 checkpoint、异常升级、授权动作通知用户

`guided_touch`（频繁介入；兼容别名 `interactive`）
- 每阶段确认（提案/重排/合并）

### 2.2b 创新分档（Innovation Level）

- `L0_execute_only`：只执行工单，不做头脑风暴（最低 token）。
- `L1_micro_reflect`（默认）：关键步骤 3 问自检，最多 1 条微建议。
- `L2_optimize`：遇堵塞/重复失败时允许 1 个替代方案。
- `L3_strategic`：里程碑级竞品差异与优势强化评估。
- `L4_breakthrough`：创新冲刺档，允许多路径实验（必须有收敛门）。

硬约束：
- 发布冻结窗自动降档为 `L0/L1`。
- 高风险未授权时禁止 `L3/L4`。

### 2.2c 建议治理模式（Suggestion Governance）

- `supervisor_only`：仅 Supervisor 提建议，泳道不提（最低噪音）。
- `hybrid`（默认）：泳道触发式提交微建议卡，Supervisor 统一 triage。
- `lane_open`：泳道可主动提建议，Supervisor 仅收敛（仅创新冲刺阶段启用）。

触发式建议条件（hybrid/lane_open）：
- 连续失败 >=2；
- 阻塞链 >20 分钟；
- 预估 token 节省 >=15%；
- 预估质量提升 >=10%；
- 命中安全风险红线。

### 2.3 档位参数矩阵（效率/稳定性取舍）

- `conservative`：
  - lane 粒度：粗
  - 重排频率：低
  - 默认适用：高风险、证据链不足、发布前窗口
- `balanced`：
  - lane 粒度：中
  - 重排频率：中
  - 默认适用：主线持续交付
- `aggressive`：
  - lane 粒度：细
  - 重排频率：高
  - 默认适用：低风险并行冲刺、deadline 压力高
  - 约束：一旦 `risk_surface >= T2` 或授权不完整，自动降档到 `balanced/conservative`

### 2.4 安全约束（硬）

- 无论哪种参与等级：`high_risk_lane_without_grant = 0`
- 高风险动作永不静默自动授权
- 证据缺失时必须 fail-closed

### 2.5 激进档规模预估（预算与排程用）

为了回答“激进档会拆到多大”，这里给出统一口径（按 1.4 的硬上限）：

- 理论硬上限：`pool_count <= 12` 且 `lane_target <= 9`，因此 `total_lanes <= 108`（接近“100 来个泳道”）。
- 常见区间（经验带）：
  - `conservative`：`1~4 pools / 6~28 lanes`
  - `balanced`：`3~8 pools / 18~56 lanes`
  - `aggressive`：`6~12 pools / 48~108 lanes`
- 工单总量估算（用于资源评估）：
  - `estimated_work_orders = base_control_orders(12) + lane_orders(total_lanes) + pool_integration_orders(pool_count) + merge_chunks(ceil(total_lanes / 6))`
  - 对应 `aggressive` 常见区间：约 `74~150` 份执行工单（含 lane 执行、池内集成、全局拼装批次）。

### 2.6 激进档效能/成本门槛（是否“划算”）

激进档不是默认最优，必须过经济性门槛后才能启用：

- `predicted_parallel_speedup >= 1.8x`
- `predicted_merge_tax_ratio <= 0.30`（拼装与回归耗时占比）
- `token_budget_headroom >= 0.30`
- `risk_surface` 以 `T0/T1` 为主（`>= 70%` lane）

运行中动态复核（每 15 分钟或每 20 个 lane 完成触发）：

- 若 `parallel_efficiency_ratio < 0.35` 连续 2 个窗口，自动降档 `aggressive -> balanced`。
- 若 `merge_tax_ratio > 0.35` 或 `wrong_autoclaim_incidents > 0`，强制降档并进入修复窗口。
- 若 `high_risk_lane_without_grant > 0`，直接 `fail-closed` 停止自治推进。

### 2.7 大规模拼装挑战与治理（100 lane 场景）

多泳道最终拼成成品的主要挑战与对应治理：

- 接口漂移：通过 `contract freeze + schema hash` 阻断跨池接口漂移。
- 合并风暴：采用 `pool-first integration -> global mergeback`，且每波次 `merge_chunk <= 6 lanes`。
- 测试雪崩：按 `pool smoke -> pool regression -> global regression` 三段门控，失败不外溢。
- 上下文碎片：启用 cross-pool context dedup 与 lineage 引用，禁止复制全量上下文。
- 责任不清：交付必须回填 7 件套 + claim TTL + evidence refs，缺任一项不得标记 `closed`。

## 3) Supervisor 自动提示词包（Prompt Pack）

每个执行 AI 必须收到 machine-readable 提示词包：

- `prompt_pack_id`, `prompt_pack_version`
- `role`：`pool_planner | lane_executor | lane_verifier | pool_integrator | release_reporter`
- `goal`, `inputs`, `outputs`, `dod`, `risk_boundaries`, `prohibitions`, `rollback_points`
- `gate_hooks`（需回填哪些 Gate/KPI/evidence）
- `escalation_policy`（何时自动推进、何时必须通知用户）

三段式强制约束（本轮新增，默认启用）：

- `Stable Core`（固定）：角色基线、禁止项、Gate 钩子、回滚点（带 `stable_core_sha256`）。
- `Task Delta`（仅增量）：本轮目标变化、依赖变化、验收变化、风险变化。
- `Context Refs`（引用 ID，不贴全文）：只允许 `ref_id + priority + max_tokens`，运行时按预算解析。

实现入口（详细可执行工单）：
- `x-terminal/work-orders/xt-w2-24-token-optimal-context-capsule-implementation-pack-v1.md`
- `x-terminal/work-orders/xt-cbl-anti-block-context-governor-implementation-pack-v1.md`

lint 阻断：
- 缺 `dod/risk_boundaries/prohibitions/rollback_points/gate_hooks` 任一即阻断下发。
- 缺任一三段式字段（`stable_core/task_delta/context_refs`）即阻断下发。

## 4) 执行主链（多泳池自治）

`intake -> complexity analyze -> block-aware split -> pool plan -> lane plan -> prompt-pack compile -> assign -> run -> heartbeat -> block graph arbiter -> jamless governor -> context rollover governor -> incident triage -> unblock dispatch -> pool integration test -> global mergeback -> quality report -> user notify`

说明：
- 先池内合并再全局合并，降低大规模冲突。
- 每池必须有独立回滚点。
- 自托管模式（dogfood）下启用 `critical_path_mode`：优先清空 release blocker 依赖链，再切入新功能并行。

## 5) 专项 Gate（XT-MP-Gate）

- `XT-MP-G0 / Plan Correctness`：pool/lane 结构完整、依赖无环、二级 DoD 完整。
- `XT-MP-G1 / Profile Determinism`：同输入 + 同档位输出稳定可复现。
- `XT-MP-G2 / Prompt Pack Integrity`：提示词包完整、lint 全绿、版本可追溯。
- `XT-MP-G3 / Autonomous Safety`：自治推进不越权，关键节点正确通知用户。
- `XT-MP-G4 / Integration Quality`：池内与全局集成测试通过，失败可回滚。
- `XT-MP-G5 / Delivery Readiness`：通知报告完整、证据齐备、release 门禁通过。

映射：
- `XT-MP-G0/G1 -> XT-SUP-G0/G1 + XT-Ready-G0/G1/G2`
- `XT-MP-G2/G3 -> XT-SUP-G1/G3 + XT-Ready-G3/G4`
- `XT-MP-G4/G5 -> XT-SUP-G4 + XT-Ready-G5 + XT-G5`

## 6) KPI（专项）

效率：
- `pool_plan_ready_p95_ms <= 5000`
- `pool_to_run_start_p95_ms <= 9000`
- `autonomous_progression_rate >= 80%`（non-high-risk）
- `block_detect_latency_p95_ms <= 1500`

质量：
- `pool_integration_first_pass_rate >= 75%`
- `global_mergeback_first_pass_rate >= 70%`
- `delivery_reopen_rate <= 5%`
- `unresolved_block_over_sla_rate <= 5%`

安全：
- `high_risk_lane_without_grant = 0`
- `unaudited_auto_resolution = 0`
- `autonomous_bypass_incidents = 0`
- `false_unblock_due_to_single_green = 0`

体验：
- `user_interrupt_rate(zero_touch) <= 0.15`
- `critical_notify_latency_p95_ms <= 1500`
- `unblock_notify_latency_p95_ms <= 1200`

自托管解阻：
- `self_host_unblock_mtta_p95_ms <= 1800`
- `critical_path_blocked_chain_age_p95_ms <= 7200000`
- `dependency_wait_without_checkpoint_over_2h = 0`

Token：
- `token_per_complex_project_delta <= -20%`
- `cross_pool_context_dedup_hit_rate >= 60%`

规模与经济性：
- `parallel_efficiency_ratio >= 0.35`
- `merge_tax_ratio <= 0.30`
- `aggressive_cost_delta_vs_balanced <= +15%`

提示词精准度：
- `tri_prompt_coverage = 100%`
- `prompt_token_waste_ratio <= 0.12`
- `rework_token_ratio <= 0.25`

## 7) 工单总览（P0/P1）

### P0（必须先落地）

1. `XT-W2-20` 多泳池复杂度规划器（Complexity -> Pool Plan）
2. `XT-W2-21` 二级子任务合成器（Pool 内 Lane 自动拆分）
2a. `XT-W2-20-B` 防堵塞拆分器（Block-aware Splitter）
3. `XT-W2-22` 档位引擎（conservative/balanced/aggressive）
4. `XT-W2-23` 参与等级引擎（`zero_touch/critical_touch/guided_touch`，兼容旧值）
4a. `XT-W2-23-B` 创新分档引擎 + UI 选择器（`L0..L4`）
4b. `XT-W2-23-C` 建议治理路由器（`supervisor_only|hybrid|lane_open`）
5. `XT-W2-24` Prompt Pack 编译器与注册表
5a. `XT-W2-24-A` 三段式编译器与契约冻结
5b. `XT-W2-24-B` Context Capsule 预算器与装箱器
5c. `XT-W2-24-C` Context Refs 解析器与权限红线
5d. `XT-W2-24-D` 重试增量压缩器（Delta Retry）
5e. `XT-W2-24-E` Token-质量联合看板与发布证据
5f. `XT-W2-24-F` 会话滚动与上下文胶囊治理器（Session Rollover）
6. `XT-W2-25` Pool 调度器（池间并发 + 池内并发上限）
6b. `XT-W2-25-B` 关键路径动态席位调度器（Active-3 Dynamic Seats）
7. `XT-W2-26` 自治推进控制器（auto-advance + incident 升级）
8. `XT-W2-27` 阻塞依赖图与即时解阻编排器（wait-for graph + dual-green + unblock routing）
8a. `XT-W2-27-F` 自托管关键路径解阻器（x-hub-system dogfood）
8b. `XT-W2-28` 无拥塞推进协议（Jamless：Active-3 + 定向 baton + 去重 + 冷却）
8c. `XT-W2-28-F` 阻塞预测 + 自动重排守门（Block Risk Predictor + Replan Guard）
9. `XT-W3-18` 池内/全局集成测试编排器
10. `XT-W3-19` 交付通知与执行摘要（自动通知用户）

### P1（增强壁垒）

11. `XT-W3-20` 动态重规划治理器（replan governor + CR arbitration）
12. `XT-W4-17` 档位自调优（按历史成功率/风险自动推荐档位）
13. `XT-W4-18` 泳池回放模拟器（what-if + incident replay）

## 8) 详细工单（DoD/Gate/KPI/回归样例）

### XT-W2-20（P0）多泳池复杂度规划器

- 目标：根据复杂度与模块图动态决定 pool 数量与边界。
- 依赖：`XT-W1-06`, `XT-W2-09`。
- 交付物：`PoolPlanner`、pool 规划解释字段、审计事件 `supervisor.pool_plan.proposed`。
- DoD：
  - 规划结果可解释（为什么是 N 个 pool）。
  - pool 间依赖无环。
- Gate：`XT-MP-G0/G1`
- KPI：`pool_plan_ready_p95_ms <= 5000`
- 回归样例：
  - 简单项目误分多池 -> 自动回退单池。
  - 依赖环路 -> 阻断并提示修复。

### XT-W2-20-B（P0）防堵塞拆分器（Block-aware Splitter）

- 目标：在拆分阶段把“高阻塞风险边”降到可控阈值，减少后续多泳道互等。
- 依赖：`XT-W2-20`, `XT-W2-21`。
- 交付物：`BlockAwareSplitAnalyzer`、`block_risk_score` 字段、contract-first 波次策略。
- 实现细化入口：`x-terminal/work-orders/xt-cbl-anti-block-context-governor-implementation-pack-v1.md`
- DoD：
  - lane 拆分满足 `depends_on<=2`, `fan_in<=2`, `fan_out<=3`。
  - `contract_freeze_state!=green` 时 feature wave 不启动。
- Gate：`XT-MP-G0/G1/G3`
- KPI：`cross_pool_dependency_density <= 0.25`, `avg_lane_depends_on <= 2.0`
- 回归样例：
  - cross-pool 环依赖未阻断 -> 失败。
  - 高风险模块仍被拆成高耦合串行链 -> 失败。

### XT-W2-21（P0）二级子任务合成器

- 目标：每个 pool 自动拆分二级 lane 子任务，并保证 DoD 完整。
- 依赖：`XT-W2-20`。
- 交付物：`LaneSynthesizer`、lane DAG、二级 DoD 模板。
- DoD：
  - 每个 lane 有输入/输出/DoD。
  - lane 与 pool 边界一致且可追溯。
- Gate：`XT-MP-G0`
- KPI：`lane_dod_coverage = 100%`
- 回归样例：
  - lane 无 DoD -> 阻断启动。
  - lane 跨 pool 越界写 -> 阻断并审计。

### XT-W2-22（P0）档位引擎（保守/平衡/激进）

- 目标：按档位控制拆分粒度、并发度、重排敏感度。
- 依赖：`XT-W2-20`, `XT-W2-21`。
- 交付物：`SplitProfileEngine` + 档位参数表 + 推荐器。
- DoD：
  - 同输入同档位输出可复现。
  - 激进档确实更细拆分且不越安全边界。
- Gate：`XT-MP-G1/G3`
- KPI：`profile_determinism = 100%`
- 回归样例：
  - conservative 输出比 aggressive 更细 -> 判失败。
  - aggressive 在高风险无授权仍自动执行 -> 判失败。

### XT-W2-23（P0）参与等级引擎

- 目标：支持“全程不参与/仅重要提示授权/全流程确认”三模式。
- 依赖：`XT-W2-22`, `XT-W2-14`。
- 交付物：`ParticipationPolicyEngine`、用户触点策略、通知模板。
- DoD：
  - `zero_touch` 下仅关键授权打断（兼容 `hands_off`）。
  - `critical_touch` 下关键提示与授权完整触达（兼容 `critical_only`）。
- Gate：`XT-MP-G3`
- KPI：`user_interrupt_rate(zero_touch) <= 0.15`
- 回归样例：
  - `zero_touch` 普通事件频繁打断 -> 失败。
  - `critical_touch` 高风险未通知 -> 失败。

### XT-W2-23-B（P0）创新分档引擎 + UI 选择器

- 目标：让用户可在 UI 选择 `L0..L4` 创新档位，并把档位映射到执行策略。
- 依赖：`XT-W2-23`。
- 交付物：`InnovationLevelEngine`、UI 档位选择器、冻结窗自动降档器。
- 实现细化入口：`x-terminal/work-orders/xt-w2-23-w2-26-autocontinue-autonomy-implementation-pack-v1.md`
- DoD：
  - UI 可选 `L0..L4`，并持久化到运行配置。
  - 冻结窗触发时自动降档到 `L0/L1` 并有审计证据。
- Gate：`XT-MP-G3/G5`
- KPI：`innovation_level_apply_success_rate = 100%`, `freeze_window_forced_downgrade_miss = 0`
- 回归样例：
  - 非法档位值未被阻断 -> 失败。
  - 冻结窗未降档 -> 失败。

### XT-W2-23-C（P0）建议治理路由器（Supervisor-only/Hybrid/Lane-open）

- 目标：在保证创新密度的同时控制 token 噪音，由 Supervisor 统一对用户提案。
- 依赖：`XT-W2-23-B`, `docs/memory-new/xhub-lane-command-board-v2.md`。
- 交付物：`SuggestionGovernanceRouter`、触发器引擎、Insight Inbox triage 输出。
- 实现细化入口：`x-terminal/work-orders/xt-w2-23-w2-26-autocontinue-autonomy-implementation-pack-v1.md`
- DoD：
  - `hybrid` 模式仅在触发条件命中时提交建议卡。
  - 需要用户决策的建议必须升级到 Supervisor 对用户提案流。
- Gate：`XT-MP-G3/G5`
- KPI：`suggestion_noise_ratio <= 0.20`, `suggestion_token_overhead_ratio <= 0.08`, `high_value_suggestion_adoption_rate >= 0.60`
- 回归样例：
  - `supervisor_only` 下泳道仍可提建议 -> 失败。
  - `hybrid` 下无触发条件出现大量建议 -> 失败。
  - `requires_user_decision=true` 未升级 -> 失败。

### XT-W2-24（P0）Prompt Pack 编译器与注册表

- 目标：为每个 AI 自动生成角色化提示词包并版本化。
- 依赖：`XT-W2-21`, `XT-W2-23`。
- 交付物：`PromptPackCompiler`、`PromptPackRegistry`、lint 阻断。
- 实现细化入口：`x-terminal/work-orders/xt-w2-24-token-optimal-context-capsule-implementation-pack-v1.md`
- DoD：
  - 每个 pool/lane AI 都有提示词包，且为三段式（`Stable Core + Task Delta + Context Refs`）。
  - 包含 Gate hooks 与回滚点。
- Gate：`XT-MP-G2`
- KPI：`prompt_pack_coverage = 100%`, `tri_prompt_coverage = 100%`
- 回归样例：
  - 缺 gate_hooks -> 阻断。
  - 缺 rollback_points -> 阻断。
  - 拼贴全文上下文而非 `context_refs` -> 阻断。

### XT-W2-24-F（P0）会话滚动与上下文胶囊治理器（Session Rollover）

- 目标：复杂案子中强制会话滚动，防止 lane 上下文持续膨胀。
- 依赖：`XT-W2-24-A/B/C/D`。
- 交付物：`SessionRolloverPolicy`、`ContextCompactor`、rollover checkpoint。
- 实现细化入口：`x-terminal/work-orders/xt-cbl-anti-block-context-governor-implementation-pack-v1.md`
- DoD：
  - 满足阈值（`turn_count>=8` 或 `state_transition>=2`）时自动 rollover。
  - 新会话仅加载 `Stable Core + Task Delta + Context Refs<=3`。
- Gate：`XT-MP-G2/G3/G5`
- KPI：`prompt_token_waste_ratio <= 0.12`, `full_history_prompt_usage = 0`, `rollover_recovery_success_rate >= 0.99`
- 回归样例：
  - 达到阈值不 rollover -> 失败。
  - rollover 后丢失 DoD/Gate hooks -> 失败。

### XT-W2-25（P0）Pool 调度器

- 目标：池间/池内并发可控，避免抢占失衡与资源饥饿。
- 依赖：`XT-W2-22`, `XT-W2-24`。
- 交付物：`PoolScheduler`（pool cap + lane cap + fairness）。
- DoD：
  - 高优先 pool 可抢占低优先 pool。
  - 低优先任务不被长期饿死。
- Gate：`XT-MP-G1/G3/G4`
- KPI：`queue_starvation_incidents = 0`
- 回归样例：
  - 激进档高并发导致饥饿 -> 失败。
  - pool cap 失效 -> 失败。

### XT-W2-25-B（P0）关键路径动态席位调度器（Active-3 Dynamic Seats）

- 目标：把 Active-3 从固定泳道升级为关键路径动态席位，保证关键任务吞吐。
- 依赖：`XT-W2-25`, `XT-W2-27`。
- 交付物：`CriticalPathSeatAllocator`、席位抢占审计事件。
- 实现细化入口：`x-terminal/work-orders/xt-cbl-anti-block-context-governor-implementation-pack-v1.md`
- DoD：
  - 任一时刻 active lane 数 `<=3`。
  - 非关键 lane 不可长期占用 active 席位。
- Gate：`XT-MP-G3/G4`
- KPI：`active_lane_count_violations = 0`, `critical_path_preempt_success_rate >= 0.98`, `queue_starvation_incidents = 0`
- 回归样例：
  - non-critical lane 抢占关键席位成功 -> 失败。
  - active>3 未回收 -> 失败。

### XT-W2-26（P0）自治推进控制器

- 目标：Supervisor 自动推进 lane->pool->global 流程，异常时自动分流处理。
- 依赖：`XT-W2-25`, `XT-W2-13`, `XT-W2-14`。
- 交付物：auto-advance 状态机、升级策略、暂停/继续点。
- DoD：
  - non-high-risk 流程可自动推进到 delivered。
  - 高风险流程只在授权后推进。
- Gate：`XT-MP-G3/G4`
- KPI：`autonomous_progression_rate >= 80%`
- 回归样例：
  - 无授权推进高风险 lane -> 失败。
  - blocked 未升级卡死 -> 失败。

### XT-W2-27（P0）阻塞依赖图与即时解阻编排器

- 目标：自动识别“谁在等谁”，并在 blocker 转绿后秒级指导等待泳道继续执行。
- 依赖：`XT-W2-26`, `XT-W2-24`, `XT-W2-23`。
- 交付物：`WaitGraphArbiter`、`DependencyDualGreenGate`、`UnblockRouter`、`BlockSLAEscalator`。
- 实现细化入口：`x-terminal/work-orders/xt-w2-27-anti-block-unblock-orchestration-implementation-pack-v1.md`
- DoD：
  - wait-for 依赖图实时可追溯（边去重、无环、可清理）。
  - blocker 满足 `contract_green + runtime_green` 后，等待泳道在 SLA 内收到继续指导。
- Gate：`XT-MP-G3/G4/G5`
- KPI：`block_detect_latency_p95_ms <= 1500`, `unblock_notify_latency_p95_ms <= 1200`, `false_unblock_due_to_single_green = 0`
- 回归样例：
  - 单绿误放行 -> 失败。
  - blocker 已绿但等待泳道未被唤醒 -> 失败。
  - 阻塞超 SLA 未升级 -> 失败。

### XT-W2-27-F（P0）自托管关键路径解阻器（x-hub-system Dogfood）

- 目标：当 x-hub-system 自身出现“多泳道相互等待”时，Supervisor 自动切换 `critical_path_mode`，先打通 release blocker 依赖链。
- 依赖：`XT-W2-27-A/B/D/E`，`docs/memory-new/xhub-lane-command-board-v2.md`。
- 交付物：`CriticalPathArbiter`、`UnblockBatonDispatcher`、关键链健康快照报告。
- DoD：
  - 自动识别 release blocker DAG，并输出唯一优先解阻顺序（top-N 关键边）。
  - blocker 双绿后 1 跳内完成 baton 交接（`next_owner_lane + next_step + unblock_owner`）。
  - 处于 `critical_path_mode` 时，非关键并发任务默认降权，不再抢占解阻资源。
- Gate：`XT-MP-G3/G4/G5`
- KPI：`self_host_unblock_mtta_p95_ms <= 1800`, `critical_path_blocked_chain_age_p95_ms <= 7200000`, `dependency_wait_without_checkpoint_over_2h = 0`
- 回归样例：
  - blocker 已绿但未触发下一泳道 claim -> 失败。
  - critical_path_mode 启用后仍被非关键任务抢占 -> 失败。
  - 无 checkpoint 的长阻塞（>2h）未升级 -> 失败。

### XT-W2-28（P0）无拥塞推进协议（Jamless v1）

- 目标：把“多泳道互等 + 重复 blocked 长报 + 无增量 gate 重试”收敛为机判协议，优先保障关键路径吞吐并抑制 token 风暴。
- 依赖：`XT-W2-27-F`, `XT-W2-24`, `XT-W2-25`, `docs/memory-new/xhub-lane-command-board-v2.md`。
- 交付物：`JamlessGovernor`（R1..R10 规则执行）、`DirectedBatonRouter`、`BlockedDedupeReporter`、`GateRetryCooldownGuard`。
- 实现细化入口：`x-terminal/work-orders/xt-w2-28-jamless-anti-congestion-protocol-implementation-pack-v1.md`
- DoD：
  - 7 泳道默认运行档生效：`Active-3 + Standby-4`，并支持 blocker 转绿后的定向升档。
  - 阻断重复 full 7 件套：同 `blocked_reason_hash` 在 dedupe window 内仅首条 full，其余仅 delta 心跳。
  - 阻断无增量 gate 重试：无 `evidence_delta_hash` 变化不得重跑 release 级 gate。
- Gate：`XT-MP-G3/G4/G5`
- KPI：`token_per_notification_p95_delta <= -35%`, `deadlock_break_time_p95_ms <= 60000`, `invalid_gate_retry_count = 0`
- 回归样例：
  - blocker 转绿后仍触发全泳道广播 -> 失败。
  - 同阻塞原因连续 3 次都发 full 7 件套 -> 失败。
  - 无证据增量仍重跑 SKC-G5 -> 失败。
  - 7 泳道 active 同时 >3 且未降档 -> 失败。

### XT-W2-28-F（P0）阻塞预测 + 自动重排守门（Block Risk Predictor + Replan Guard）

- 目标：在堵塞发生前触发重排和降档，避免“互相等待”演化成停滞。
- 依赖：`XT-W2-28`, `docs/memory-new/xhub-lane-command-board-v2.md`。
- 交付物：`BlockRiskPredictor`、`ReplanTriggerGuard`、重排审计回放。
- 实现细化入口：`x-terminal/work-orders/xt-cbl-anti-block-context-governor-implementation-pack-v1.md`
- DoD：
  - 触发器生效：`20min 无增量->checkpoint`, `40min->换 breaker`, `60min->CR 重排`。
  - 收益不足时自动降档 `aggressive -> balanced`。
- Gate：`XT-MP-G3/G4/G5`
- KPI：`blocked_chain_age_p95_ms <= 7200000`, `deadlock_break_time_p95_ms <= 60000`, `replan_latency_p95_ms <= 3000`
- 回归样例：
  - 60 分钟无增量仍不重排 -> 失败。
  - 普通 CR 抢占 release blocker -> 失败。

### XT-W3-18（P0）池内/全局集成测试编排器

- 目标：先池内集成，再全局集成，失败自动回滚并给修复建议。
- 依赖：`XT-W2-27`, `XT-W3-11`。
- 交付物：`PoolIntegrationOrchestrator`、测试矩阵、失败归因报告。
- DoD：
  - 池内测试失败不进入全局合并。
  - 全局失败可回滚到 pool 稳定点。
- Gate：`XT-MP-G4/G5`
- KPI：`pool_integration_first_pass_rate >= 75%`
- 回归样例：
  - pool 测试失败仍全局合并 -> 失败。
  - 回滚后状态不一致 -> 失败。

### XT-W3-19（P0）交付通知与执行摘要

- 目标：任务收口后自动向用户发送高质量交付通知（可静默/摘要/完整）。
- 依赖：`XT-W3-18`, `XT-W2-23`。
- 交付物：`DeliveryNotifier`、摘要模板、证据引用链接。
- DoD：
  - 通知包含结果、风险、证据、回滚点、下一步建议。
  - 用户参与等级决定通知粒度。
- Gate：`XT-MP-G5`
- KPI：`delivery_notification_completeness = 100%`
- 回归样例：
  - 缺证据链接仍发送“完成” -> 失败。
  - `zero_touch` 模式仍频繁发送非关键通知 -> 失败。

### XT-W3-20（P1）动态重规划治理器

- 目标：用户实时变更需求时，自动做 CR 裁决与任务重排。
- 依赖：`XT-W2-26`, `docs/memory-new/xhub-lane-command-board-v2.md`。
- 交付物：replan governor、CR arbitration、freeze-window 约束。
- Gate：`XT-MP-G1/G3/G5`
- KPI：`replan_latency_p95_ms <= 3000`

## 9) 与现有工单对齐（防漂移）

- 与 `xt-supervisor-autosplit-multilane-work-orders-v1.md` 对齐：本文件是“多泳池 + 二级子任务 + 自治推进”扩展，不替代原主链。
- 与 `xhub-hub-to-xterminal-capability-gate-v1.md` 对齐：release 仍必须满足 XT-Ready-G0..G5。
- 与 `xhub-lane-command-board-v2.md` 对齐：所有推进与交付采用 claim + 7件套。
- 与 SKC/SI 对齐：skills 与安全创新不改变高风险授权红线。

## 10) 当前建议启用策略（默认值）

- 默认档位：`balanced`
- 默认参与等级：`critical_touch`（兼容 `critical_only`）
- 默认创新分档：`L1_micro_reflect`
- 默认建议治理模式：`hybrid`（泳道触发式建议 + Supervisor 统筹）
- `zero_touch`（兼容 `hands_off`）仅在以下前提可开启：
  - 近 7 天 `high_risk_lane_without_grant = 0`
  - require-real 证据链稳定
  - release blockers 清零
- `L0_execute_only` 建议用于发布冻结窗或热修复窗口；`L3/L4` 仅建议在里程碑评审或创新冲刺窗口启用
- `aggressive` 仅在以下前提可开启（否则自动回落 `balanced`）：
  - 预测 `total_lanes <= 108` 且 `predicted_parallel_speedup >= 1.8x`
  - `predicted_merge_tax_ratio <= 0.30`
  - `token_budget_headroom >= 0.30`
  - 高风险 lane 占比不过阈（`T2/T3 < 30%`）

## 11) 执行工单包入口（Lane-ready）

- 可直接派发的细化执行包：
  - `x-terminal/work-orders/xt-supervisor-multipool-lane-execution-pack-v1.md`
  - `x-terminal/work-orders/xt-w2-23-w2-26-autocontinue-autonomy-implementation-pack-v1.md`（自治推进 + 介入等级实现子工单）
  - `x-terminal/work-orders/xt-w2-24-token-optimal-context-capsule-implementation-pack-v1.md`（三段式提示词 + Token 最优上下文胶囊实现子工单）
  - `x-terminal/work-orders/xt-w2-27-anti-block-unblock-orchestration-implementation-pack-v1.md`（阻塞依赖图 + 双绿门控 + 即时解阻路由）
  - `x-terminal/work-orders/xt-w2-28-jamless-anti-congestion-protocol-implementation-pack-v1.md`（无拥塞协议：Active-3 + 定向接力 + 去重 + 冷却）
  - `x-terminal/work-orders/xt-cbl-anti-block-context-governor-implementation-pack-v1.md`（防堵塞拆分 + 会话滚动 + 动态席位 + 阻塞预测重排）
- 用法：
  - XT-L2/XT-L1/Hub-L3/Hub-L5/QA 领取任务时，优先按执行包中的 `DoR -> 子步骤 -> DoD -> Gate/KPI -> 回归 -> 证据` 推进。
  - 与 Command Board 联动时，保持 `claim + TTL + 7件套` 不变。
