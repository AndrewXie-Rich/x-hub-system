# X-Terminal Supervisor 自动拆分与多泳道编排工单（专项版）

- version: v1.2
- updatedAt: 2026-03-02
- owner: X-Terminal Supervisor / Hub Runtime / Security / QA / Product
- status: active
- scope: `x-terminal/`（Supervisor 自动拆分 + 多泳道自动分配 + 全程托管）
- parent:
  - `x-terminal/work-orders/xterminal-parallel-work-orders-v1.md`
  - `x-terminal/work-orders/xt-supervisor-multipool-adaptive-work-orders-v1.md`
  - `docs/memory-new/xhub-hub-to-xterminal-capability-gate-v1.md`
  - `docs/memory-new/xhub-memory-v3-m3-work-orders-v1.md`
  - `docs/memory-new/xhub-memory-v3-m3-lineage-contract-freeze-v1.md`
  - `docs/memory-new/xhub-memory-v3-m3-lineage-contract-tests-v1.md`

## 0) 成品目标（用户体验定义）

用户提出一个复杂项目后，成品必须表现为：

1. Supervisor 自动评估复杂度并提出“拆分建议计划”（可视化 DAG + lane + 风险 +预算）。
2. 用户确认后，Supervisor 按策略执行拆分（可选是否创建子项目）。
3. Supervisor 按质量规范自动生成每个泳道的执行提示词（Prompt Contract）。
4. Supervisor 自动分配 AI 到各泳道并启动并行执行。
5. Supervisor 以 heartbeat 主动巡检每个泳道，发现异常立即接管。
6. 每个泳道出现“权限等待/下一步指示等待/失败阻塞”等状态时，Supervisor 秒级感知。
7. Supervisor 可按策略：
   - 自动处理（在策略允许范围内自动授权或自动重试）
   - 通知用户并请求确认（高风险默认）
8. Supervisor 维护阻塞依赖图（wait-for），blocker 转绿后可即时指导等待泳道续推。
9. 全过程可追溯（lineage + grant + audit + mergeback）。
10. 当项目复杂度升高时，Supervisor 可自动升级为“多泳池 + 每池多泳道”执行（见扩展工单）。

## 1) 关键设计建议：拆分是否创建子项目

建议采用 **Hybrid Materialization（混合落盘）**，默认不是“全建子项目”也不是“全不建子项目”。

### 1.1 建议规则（默认）

- `hard_split -> create_child_project=1`（创建子项目）
  - 满足任一条件即 hard split：
    - 高风险动作或权限域不同（不同 grant profile）
    - 需要不同模型/预算档位
    - 独立产物与独立回滚需求明显
    - 预计执行时长超阈值（如 > 45 分钟）
    - 预计与其他任务高并发执行
- `soft_split -> create_child_project=0`（仅 lane task，不创建子项目）
  - 低风险、短任务、与母项目强耦合、无独立回滚需求。

### 1.2 用户确认界面建议

在“拆分确认”弹窗中显示：
- 推荐拆分模式（系统建议：hard/soft）
- 每个 lane 的 `create_child_project` 开关（可逐项覆盖）
- 覆盖影响说明（权限、审计、回滚、token、延迟）

### 1.3 约束

- 任何 `hard_split` 若被用户强制降为 `soft_split`，必须给风险提示并写审计。
- 任何高风险 lane 禁止在 `soft_split` 下直接执行外部副作用动作。

## 2) Supervisor 控制面架构（执行主链）

主链：
`intake -> complexity score -> split proposal -> user confirm -> materialize -> prompt compile -> assign -> run -> heartbeat/watch -> triage -> mergeback`

组件划分：
- `SupervisorPlanner`：复杂度评估 + DAG 拆分。
- `SplitProposalEngine`：生成可审阅计划与差异说明。
- `ProjectMaterializer`：按 hard/soft 策略落盘（子项目或 lane task）。
- `PromptFactory`：按质量规范生成 lane prompt。
- `LaneAllocator`：AI profile/预算/风险匹配。
- `HeartbeatController`：主动巡检 + 超时探测。
- `IncidentArbiter`：权限等待/阻塞/失败分级处理。
- `UserDecisionBridge`：通知用户 + 收集确认 + 回写调度。
- `MergebackIntegrator`：lane 结果收口 + 质量门禁 + 回滚点。

## 3) 数据与契约字段（最小闭环）

### 3.1 Split Proposal

- `split_plan_id`
- `root_project_id`
- `plan_version`
- `complexity_score`
- `lanes[]`:
  - `lane_id`, `goal`, `depends_on[]`, `risk_tier`, `budget_class`, `create_child_project`, `expected_artifacts[]`, `dod_checklist[]`
- `recommended_concurrency`
- `token_budget_total`
- `estimated_wall_time_ms`

### 3.2 Lane Runtime

- `lane_id`, `project_id`, `agent_profile`, `status`
- `heartbeat_seq`, `last_heartbeat_at_ms`, `oldest_wait_ms`
- `blocked_reason`（`grant_pending|awaiting_instruction|dependency_blocked|runtime_error|quota_exceeded|authz_denied|webhook_unhealthy|auth_challenge_loop|queue_starvation|restart_drain|context_overflow|route_origin_unavailable|dispatch_idle_timeout|unknown`）
- `next_action_recommendation`

### 3.3 Incident

- `incident_id`, `lane_id`, `severity`, `category`
- `auto_resolvable`（bool）
- `requires_user_ack`（bool）
- `proposed_action`（`auto_retry|auto_grant|notify_user|pause_lane|replan`）

## 4) 质量门禁（XT-SUP-Gate）

- `XT-SUP-G0 / Proposal Correctness`：拆分提案结构完整，DAG 无环，DoD 完整。
- `XT-SUP-G1 / Assignment Safety`：分配结果满足 risk/profile/grant 约束。
- `XT-SUP-G2 / Heartbeat Reliability`：心跳丢失、延迟、重启场景可恢复且不失控；父会话上下文溢出必须 fail-closed 并可观测。
- `XT-SUP-G3 / Incident Control`：阻塞/权限/失败可被秒级感知并正确分流（自动处理 vs 通知用户）；origin-safe fallback 与完成清理必须可验证。
- `XT-SUP-G4 / Mergeback Quality`：lane 结果合并前通过质量门禁，支持回滚。

与现有门禁映射：
- `XT-SUP-G0 -> XT-G0/XT-G1`
- `XT-SUP-G1 -> XT-G2/XT-G3`
- `XT-SUP-G2 -> XT-G4`
- `XT-SUP-G3 -> XT-G2/XT-G4`
- `XT-SUP-G4 -> XT-G1/XT-G5`

## 5) KPI（专项）

效率：
- `proposal_ready_p95_ms <= 4000`
- `split_to_parallel_start_p95_ms <= 8000`
- `lane_stall_detect_p95_ms <= 2000`
- `replan_recovery_p95_ms <= 12000`
- `parent_fork_overflow_detect_p95_ms <= 1000`

安全：
- `high_risk_lane_without_grant = 0`
- `bypass_supervisor_resolution = 0`
- `unaudited_auto_resolution = 0`
- `cross_channel_fallback_blocked = 100%`

Token：
- `token_per_complex_project_delta <= -20%`
- `cross_lane_context_dedup_hit_rate >= 60%`
- `token_budget_overrun_rate <= 3%`
- `parent_fork_overflow_silent_fail = 0`

可靠性：
- `dispatch_idle_stuck_incidents = 0`
- `route_origin_fallback_violations = 0`

体验：
- `user_split_acceptance_rate >= 70%`
- `supervisor_action_latency_p95_ms <= 1500`
- `user_interrupt_handling_satisfaction >= 4.5/5`（内部评测口径）

## 6) 工单总览（P0/P1）

### P0（必须先落地）

1. `XT-W2-09` 拆分提案与用户确认流（Proposal + Confirm）
2. `XT-W2-10` Hybrid 拆分落盘器（hard/soft + 子项目策略）
3. `XT-W2-11` PromptFactory（质量规范化提示词编译）
4. `XT-W2-12` 多泳道 AI 自动分配与启动编排
5. `XT-W2-13` Heartbeat 主动巡检与泳道健康态
6. `XT-W2-14` 阻塞与权限事件秒级接管（自动处理/通知用户）
7. `XT-W3-11` 多泳道结果收口与质量门禁合并

### P1（增强与壁垒）

8. `XT-W3-12` 自适应重排（Replan）与负载均衡
9. `XT-W3-13` 跨泳道 Token 优化器（上下文去重 + 预算再分配）
10. `XT-W3-14` 队列重启排空与反饥饿恢复（drain + backoff）
11. `XT-W3-15` skills ecosystem 稳定性三件套对齐（overflow + origin-safe fallback + cleanup）
12. `XT-W4-15` Supervisor 失效模式学习（故障模板/恢复策略）
13. `XT-W4-16` Supervisor Doctor + Secrets 发布前预检（防配置漂移）

## 6.1 多泳池与二级子任务扩展（详细入口）

- 详细工单池：`x-terminal/work-orders/xt-supervisor-multipool-adaptive-work-orders-v1.md`
- 执行工单包：`x-terminal/work-orders/xt-supervisor-multipool-lane-execution-pack-v1.md`
- 实现级子工单（自动推进 + 介入等级）：`x-terminal/work-orders/xt-w2-23-w2-26-autocontinue-autonomy-implementation-pack-v1.md`
- 实现级子工单（Token 最优上下文胶囊 + 三段式提示词）：`x-terminal/work-orders/xt-w2-24-token-optimal-context-capsule-implementation-pack-v1.md`
- 实现级子工单（阻塞依赖图 + 即时解阻编排）：`x-terminal/work-orders/xt-w2-27-anti-block-unblock-orchestration-implementation-pack-v1.md`
- 覆盖能力：
  - 自动按复杂度与模块图拆分 `pool -> lane` 二级结构（泳池数动态，不固定 7 条泳道）
  - 策略档位 `conservative|balanced|aggressive`（激进档拆得更细并行更多）
  - 用户参与等级 `zero_touch|critical_touch|guided_touch`（兼容 `hands_off|critical_only|interactive`）
  - 每个执行 AI 的 Prompt Pack 自动编译与版本化
  - 提示词强制三段式：`Stable Core + Task Delta + Context Refs`（Context Refs 仅引用 ID，不贴全文）
  - 阻塞治理统一走 `wait-for graph + dual-green dependency + unblock router`，依赖转绿后自动指导等待泳道续推
  - 池内集成 -> 全局合并 -> 自动通知用户交付摘要

## 7) 详细工单（含 DoD/Gate/KPI/回归样例）

### XT-W2-09（P0）拆分提案与用户确认流

- 目标：将“自动拆分”变成“可解释、可审阅、可覆盖”的提案流程。
- 依赖：`XT-W1-05`, `XT-W1-06`。
- 交付物：
  - `split proposal` 数据结构与 UI 卡片
  - 用户确认/拒绝/局部覆盖机制
  - 审计事件：`supervisor.split.proposed`, `supervisor.split.confirmed`, `supervisor.split.overridden`
- DoD：
  - 提案包含 DAG、lane、风险、预算、DoD
  - 覆盖操作可回放
- Gate：`XT-SUP-G0`
- KPI：`proposal_ready_p95_ms <= 4000`
- 回归样例：
  - DAG 有环 -> 阻断确认
  - 用户将 hard 改 soft -> 强提示 + 审计

### XT-W2-10（P0）Hybrid 拆分落盘器

- 目标：按 hard/soft 策略落盘，解决“要不要建子项目”的工程一致性。
- 依赖：`XT-W2-09`, `M3-W1-03`。
- 交付物：
  - `ProjectMaterializer`（hard=建子项目，soft=同项目 lane task）
  - 子项目 lineage 回写（Hub `UpsertProjectLineage/AttachDispatchContext`）
  - 子项目命名与来源可视化规则
- DoD：
  - hard split 子项目 lineage 完整
  - soft split 不污染 lineage 树
- Gate：`XT-SUP-G0`, `XT-SUP-G1`
- KPI：`lineage_visibility_coverage = 100%`
- 回归样例：
  - hard split 未创建子项目 -> 阻断
  - soft split 误写子项目 -> 阻断并回滚

### XT-W2-11（P0）PromptFactory 质量编译器

- 目标：Supervisor 严格按质量规范写 lane prompt，避免 AI 执行偏航。
- 依赖：`XT-W2-09`。
- 交付物：
  - Prompt 合同模板（目标/边界/输入/输出/DoD/风险/禁令）
  - prompt lint（缺 DoD、缺拒绝语义、缺回滚点时阻断）
  - 审计事件：`supervisor.prompt.compiled`, `supervisor.prompt.rejected`
- DoD：
  - 每个 lane 均有可验收 Prompt Contract
- Gate：`XT-SUP-G1`
- KPI：`lane_prompt_contract_coverage = 100%`
- 回归样例：
  - 无 DoD prompt -> 阻断启动
  - 高风险 lane 缺 grant 说明 -> 阻断

### XT-W2-12（P0）多泳道 AI 自动分配与启动编排

- 目标：按任务类型/风险/预算/负载自动分配 AI 并并行启动。
- 依赖：`XT-W2-10`, `XT-W2-11`, `XT-W2-06`。
- 交付物：
  - `LaneAllocator` 评分器（skill_match/risk_fit/token_efficiency/load）
  - `LaneLauncher`（并发上限 + 启动顺序 + 依赖门控）
  - 分配解释字段（为什么给该 AI）
- DoD：
  - 分配结果可解释可复现
  - 依赖未就绪 lane 不得启动
- Gate：`XT-SUP-G1`, `XT-G3`
- KPI：`child_project_assignment_success_rate >= 98%`
- 回归样例：
  - 高风险 lane 分配低信任 profile -> 阻断
  - 依赖未完成被提前启动 -> 阻断

### XT-W2-13（P0）Heartbeat 主动巡检与泳道健康态

- 目标：Supervisor 主动检查每条 lane，不依赖被动日志。
- 依赖：`XT-W2-12`。
- 交付物：
  - heartbeat 采集/聚合
  - lane 健康状态机（running/blocked/waiting/stalled/failed/recovering）
  - 超时探测与恢复钩子
- DoD：
  - stalled lane 在 2s 内被识别
- Gate：`XT-SUP-G2`
- KPI：`lane_stall_detect_p95_ms <= 2000`
- 回归样例：
  - 心跳中断 -> 标记 stalled 并触发处理
  - Supervisor 重启 -> 恢复 lane 健康态

### XT-W2-14（P0）阻塞与权限事件秒级接管

- 目标：泳道出现权限等待/下一步指示等待/异常时，Supervisor 秒级知道并可自动或通知用户处理。
- 依赖：`XT-W1-03`, `XT-W1-04`, `XT-W2-13`。
- 交付物：
  - `IncidentArbiter` 分级器
  - 策略：`auto_resolve | notify_user | pause_lane | replan`
  - 用户通知卡片与“一键授权/拒绝/继续等待”动作
- DoD：
  - 所有 blocked_reason 均进入统一事件流
  - 高风险权限默认 notify_user，不可静默自动授权
  - 非消息入口风险事件（reaction/pin/member/webhook）必须可被接管并保留 deny_code
- Gate：`XT-SUP-G3`, `XT-G2`
- KPI：`supervisor_action_latency_p95_ms <= 1500`
- 回归样例：
  - grant_pending -> 通知用户并可追踪
  - awaiting_instruction 超时 -> 触发 replan 建议
  - 未授权 reaction/pin/member 事件 -> 进入 incident 流并建议用户动作

### XT-W3-11（P0）多泳道结果收口与质量门禁合并

- 目标：lane 结果收口时保证质量，不因并行吞吐牺牲交付稳定性。
- 依赖：`XT-W2-12`, `XT-W2-14`。
- 交付物：
  - Mergeback 流程（预检 -> 合并 -> 验证 -> 提交）
  - lane 级回滚点
  - 冲突检测与自动分流（可自动/需人工）
- DoD：
  - 合并失败可一键回滚到 lane 稳定点
- Gate：`XT-SUP-G4`, `XT-G5`
- KPI：`mergeback_first_pass_rate >= 70%`
- 回归样例：
  - lane 冲突 -> 自动生成修复建议
  - 合并后质量门禁失败 -> 自动回滚

### XT-W3-12（P1）自适应重排（Replan）

- 目标：执行中根据阻塞和负载动态重排 lane。
- 依赖：`XT-W2-13`, `XT-W2-14`。
- 交付物：重排触发器、重排建议、安全重排执行器。
- Gate：`XT-SUP-G2`, `XT-SUP-G3`
- KPI：`replan_recovery_p95_ms <= 12000`

### XT-W3-13（P1）跨泳道 Token 优化器

- 目标：减少跨泳道重复上下文注入。
- 依赖：`XT-W2-12`。
- 交付物：lane 间上下文去重缓存、预算再分配策略。
- Gate：`XT-G3`
- KPI：`cross_lane_context_dedup_hit_rate >= 60%`

### XT-W3-14（P1）队列重启排空与反饥饿恢复

- 目标：在重启/发布窗口中保持队列一致性，避免静默丢单与重试饥饿。
- 依赖：`XT-W2-13`, `XT-W2-14`。
- 交付物：
  - `restart_drain` 生命周期（draining/rejecting/recovering）
  - enqueue during drain 的显式拒绝语义（含重试建议）
  - `last_attempt_at + backoff` 调度公平器（ready 任务可越过未到窗口任务）
- Gate：`XT-SUP-G2`, `XT-SUP-G3`, `XT-G4`
- KPI：
  - `enqueue_during_drain_silent_drop = 0`
  - `retry_starvation_incidents = 0`
  - `restart_recovery_success_rate >= 99%`
- 回归样例：
  - Supervisor 重启期间新 lane 入队 -> 显式拒绝，恢复后可重提
  - 头部 lane 连续失败重试 -> 后续 ready lane 不被饿死

### XT-W3-15（P1）skills ecosystem 稳定性三件套对齐（overflow + origin-safe fallback + cleanup）

- 目标：把 `XT-W2-17/18/19` 的关键行为并入 Supervisor 事件主链，避免多泳道并发下出现“静默失败/错误回退/状态残留”。
- 依赖：`XT-W2-13`, `XT-W2-14`, `XT-W2-17`, `XT-W2-18`, `XT-W2-19`。
- 交付物：
  - 父会话分叉前 `token guard` 预检与拒绝语义（`context_overflow`）事件化。
  - 路由回退策略固化：origin 不可用仅允许同通道回退，跨通道硬阻断并写审计。
  - run 完成最终清理器：统一触发 dispatch idle/typing cleanup，避免“执行完成但 UI/调度仍占用”。
  - 指标落盘：`parent_fork_overflow_*`、`route_origin_fallback_*`、`dispatch_idle_stuck_incidents`。
- DoD：
  - 无上下文溢出静默失败。
  - 无跨通道偷跑回退。
  - run 完成后状态机必收敛到 idle。
- Gate：`XT-SUP-G2`, `XT-SUP-G3`, `XT-G4`
- KPI：
  - `parent_fork_overflow_silent_fail = 0`
  - `route_origin_fallback_violations = 0`
  - `dispatch_idle_stuck_incidents = 0`
- 回归样例：
  - 父会话注入超预算 -> 返回 `context_overflow`，lane 进入 blocked 并提示降级。
  - origin=grpc 且 grpc 不可用 -> 允许 grpc 内部降级；禁止落到 file 通道。
  - run 成功/失败/取消三路径 -> 均触发 cleanup，lane 状态最终 idle。

### XT-W4-15（P1）Supervisor 失效模式学习

- 目标：常见故障自动匹配恢复策略，减少人工介入。
- 依赖：`XT-W2-14`, `XT-W3-12`。
- 交付物：故障模板库、恢复策略库、建议解释层。
- Gate：`XT-G4`, `XT-G5`
- KPI：`incident_auto_recovery_rate >= 65%`

### XT-W4-16（P1）Supervisor Doctor + Secrets 发布前预检

- 目标：在进入多泳道执行前，自动发现并阻断高风险配置漂移与 secrets 失配。
- 依赖：`XT-W2-14`, `XT-W3-11`。
- 实施进度（2026-02-28）：已落地 Supervisor Doctor 风险检查（dm/group allowlist、ws origin/shared-token auth、pre-auth flood breaker），并新增 secrets dry-run 摘要（目标路径越界/缺失变量/权限边界错误）与可执行修复建议卡片；预检结果会同时落盘 `supervisor_doctor_report.json`、`doctor-report.json` 与 `secrets-dry-run-report.json`（兼容发布门禁读取）；无报告或存在阻断项均 fail-closed。
- 交付物：
  - `supervisor doctor`（dm/group allowlist、ws origin、shared-token auth、pre-auth flood breaker 配置）
  - `secrets apply --dry-run` 检查摘要（目标路径、缺失变量、权限边界）
  - 用户可执行修复建议卡片
- Gate：`XT-G2`, `XT-G5`
- KPI：`config_risk_detect_recall >= 95%`，`release_blocked_by_doctor_without_report = 0`
- 回归样例：
  - `dmPolicy=allowlist` 且空 allowFrom -> 阻断并生成修复建议
  - secrets 目标路径越界 -> 阻断并提示最小修复步骤
- 审计发布说明（2026-02-28）：
  - 变更范围：`SupervisorDoctor.swift`、`SupervisorManager.swift`、`SupervisorView.swift`、`xt_release_gate.sh`、`SupervisorDoctorTests.swift`
  - 测试结果：`swift test --filter SupervisorDoctorTests` 4/4 通过
  - 门禁结果：`XT_GATE_MODE=strict ... xt_release_gate.sh` 全绿（`fail=0`、`warn=0`）
  - 证据：`.axcoder/reports/xt-gate-report.md`、`.axcoder/reports/xt-report-index.json`、`.axcoder/reports/supervisor_doctor_report.json`、`.axcoder/reports/secrets-dry-run-report.json`
  - 增量说明（2026-03-01）：发布预设演练新增 `XT_GATE_RELEASE_PRESET=1 + XT_GATE_AUTO_PREPARE_RELEASE_EVIDENCE=1` 路径；四象限回归可通过 `XT_GATE_VALIDATE_RELEASE_EVIDENCE_MATRIX=1` 启动，日志归档 `.axcoder/reports/xt-gate-release-evidence-matrix.log`，并生成结构化校验产物 `.axcoder/reports/xt-gate-release-evidence-matrix.summary.json`（schema=`xt_release_evidence_matrix.v1`）；同时执行 validator 回归并归档 `.axcoder/reports/xt-gate-release-evidence-matrix.validator-regression.log`。
  - CI 兜底（2026-03-01）：`xt-gates.yml` 新增独立单元 `Matrix Validator Regression Unit`，在 gate 主流程前直接执行 validator 回归脚本，确保证据校验器异常可尽早暴露。
  - 本地快检（2026-03-01）：可执行 `bash scripts/ci/xt_gate_fast_checks.sh` 一键跑提交前最快校验（validator：matrix + fast-check trend）；如需全量快检可叠加 `XT_FAST_CHECK_RUN_BUILD=1 XT_FAST_CHECK_RUN_MATRIX=1`，并会落盘 `.axcoder/reports/xt-fast-check-summary.json` 与 `.axcoder/reports/xt-fast-check-history.json`（默认仅保留最近 20 条，且包含窗口 pass/fail/warn 聚合与步骤状态分布）。

## 8) 端到端验收场景（必须通过）

场景：
- 用户提交“复杂项目（多模块+高风险外部动作+严格交付）”。

验收步骤：
1. Supervisor 生成拆分提案（含 hard/soft 建议）。
2. 用户同意并局部覆盖 1 条 lane 的建子项目选项。
3. Supervisor 落盘拆分并自动分配 4 条 lane 给 3 种 profile。
4. 运行中出现：
   - lane-2 `grant_pending`
   - lane-3 `awaiting_instruction`
   - lane-4 `runtime_error`
5. Supervisor 在 2 秒内全部感知，执行：
   - lane-2 通知用户授权
   - lane-3 自动给下一步建议并等待用户确认
   - lane-4 自动重试一次，失败后暂停并上报
6. 全部 lane 收口，质量门禁通过后合并。

通过标准：
- 以上每一步均有审计记录与可追溯状态。
- 无旁路高风险执行。
- token 预算未超限或超限后按策略降级且留痕。

## 9) 与主线工单对齐（防漂移）

- 与 Hub `M3-W1-03` 对齐：lineage 字段和 deny_code 语义完全一致。
- 与 `xterminal-parallel-work-orders-v1.md` 对齐：本文件是 Supervisor 自动拆分专项细化，不替代全局工单。
- 与 Spec Gate gate 方法对齐：每个子工单必须具备 DoD/Gate/KPI/回归样例。
- 与 `XT-Ready Gate` 对齐：本文件 `P0` 工单（`XT-W2-09..XT-W3-11`）是 `XT-Ready-G0..G5` 的主要落地来源。
- 与 skills ecosystem 回灌工单对齐：`XT-W2-17/18/19` 的边界语义在本文件通过 `blocked_reason + XT-W3-15 + XT-SUP-G2/G3` 固化。
