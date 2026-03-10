# X-Terminal 并行推进执行工单（高质量版）

- version: v1.0
- updatedAt: 2026-03-02
- owner: X-Terminal / Hub Runtime / Security / QA / Product
- status: active
- scope: `x-terminal/`（X-Terminal 模块）
- parent:
  - `X_MEMORY.md`
  - `docs/WORKING_INDEX.md`
  - `docs/memory-new/xhub-memory-v3-m3-work-orders-v1.md`
  - `docs/memory-new/xhub-hub-to-xterminal-capability-gate-v1.md`
  - `docs/memory-new/xhub-kiro-spec-gates-work-orders-v1.md`

## 0) 使用方式（先看）

- 本文是 **X-Terminal 模块专属工单源**；以后 X-Terminal 相关工单默认落在 `x-terminal/work-orders/`。
- 推进方式采用“并行泳道 + 统一门禁”：多个队列同时做，但合并发布必须过同一套 Gate。
- 目标不只“功能做完”，而是三维同时达标：`效率`、`安全`、`Token 经济性`。
- 所有高风险动作必须走主链：`ingress -> risk classify -> policy -> grant -> execute -> audit`。
- Supervisor 自动拆分与多泳道编排专项（详细工单）见：`x-terminal/work-orders/xt-supervisor-autosplit-multilane-work-orders-v1.md`。
- Supervisor 多泳池自适应扩展（复杂度驱动 `pool -> lane` 二级拆分）见：`x-terminal/work-orders/xt-supervisor-multipool-adaptive-work-orders-v1.md`。
- Hub 完成声明前，必须通过 `XT-Ready Gate`（`docs/memory-new/xhub-hub-to-xterminal-capability-gate-v1.md`）。

## 0.1 当前进展基线（来自 x-terminal 文档状态）

- `DOC_STATUS_DASHBOARD.md` 口径：Phase 1 `completed`、Phase 2 `completed`、Phase 3 `in_progress`。
- `PHASE3_PROGRESS.md` 口径：M1（记忆系统）和 M2（沙箱系统）已完成，M3/M4/M5/M6 待推进。
- 已有能力基线：已具备 TaskDecomposer / TaskAssigner / DependencyGraph，可在此基线升级“复杂母项目 -> 多子项目并行执行”能力。
- 本工单新增项默认建立在上述基线上推进，不重复拆旧历史任务。

## 1) 北极星目标（并行推进不牺牲质量）

### 1.1 效率目标

- X-Terminal 主流程一次通过率提升，减少返工与热修。
- 多项目并行下，排队与上下文切换开销稳定可控。
- 工具链与记忆链路默认“低摩擦可用”。
- 复杂母项目可自动拆分为多个子项目并并行执行，且子项目来源关系可视化可追溯。

### 1.2 安全目标

- `bypass_grant_execution = 0`
- `high_risk_unauthorized_exec = 0`
- `secret_remote_export_incidents = 0`

### 1.3 Token 经济性目标

- `token_per_task_delta <= -20%`（对当前 X-Terminal 基线）
- `index_to_details_ratio >= 3.0`
- `unexpected_remote_charge_incidents = 0`

## 2) 质量门禁（XT-Gate）

- `XT-G0 / Contract Freeze`：X-Terminal 与 Hub 接口、错误码、状态机冻结并版本化。
- `XT-G1 / Correctness`：单测/集成/E2E 全绿，且无关键链路旁路。
- `XT-G2 / Security`：grant、DLP、签名校验、kill-switch 回归全部通过。
- `XT-G3 / Performance`：排队、响应、UI 延迟与 token 开销达标。
- `XT-G4 / Reliability`：断网/重启/重放/并发冲突可恢复且 fail-closed。
- `XT-G5 / Release Ready`：灰度、回滚、值班手册、审计导出齐备。

## 3) DoR / DoD（必须满足）

Definition of Ready (DoR)
- 需求边界、输入输出、失败语义明确。
- 依赖关系已标注，是否并行可执行清晰。
- 验收指标可量化且可观测（metrics/audit/bench）。

Definition of Done (DoD)
- 代码 + 文档 + 测试 + 可观测 + 回滚方案同时完成。
- 通过对应 `XT-Gate`，不得口头豁免。
- 合并请求必须附带回归样例结果或报告链接。

## 4) 并行泳道（Parallel Lanes）

### Lane-A：会话与传输主链（Core Transport）
- 目标：统一 `auto|grpc|file` 路由策略，减少分叉行为。
- 产出重点：会话一致性、错误语义统一、断线恢复。

### Lane-B：记忆与 Token 效率（Memory+Token）
- 目标：默认 index-first，控制上下文注入成本。
- 产出重点：Context Explain、Token Guard、跨会话复用。

### Lane-C：安全与信任域（Security）
- 目标：高风险动作零旁路，技能/工具执行可验签可审计。
- 产出重点：grant 强制、签名校验、Fail-Closed 回归。

### Lane-D：Supervisor 与审批体验（UX）
- 目标：并行项目状态可解释，审批路径快速且不降级。
- 产出重点：pending grants 真相源、优先级建议、一键跳转。

### Lane-E：质量与发布工程（QA/Release）
- 目标：门禁自动化，发布可回滚，报表可追责。
- 产出重点：CI gate、周报、异常归因、发布检查单。

## 5) KPI（模块级）

### 5.1 效率 KPI
- `queue_wait_p90_ms <= 3200`
- `first_pass_acceptance_rate >= 70%`
- `mean_time_to_root_cause <= 30min`
- `split_to_parallel_start_p95_ms <= 8000`
- `child_project_assignment_success_rate >= 98%`

### 5.2 安全 KPI
- `bypass_grant_execution = 0`
- `unsigned_high_risk_skill_exec = 0`
- `credential_finding_block_rate = 100%`

### 5.3 Token KPI
- `token_per_task_delta <= -20%`
- `token_budget_overrun_rate <= 3%`
- `cross_session_dedup_hit_rate >= 60%`
- `lineage_visibility_coverage = 100%`

## 6) 工单总览（P0/P1）

### P0（阻断型，允许并行开发但必须先收口）

1. `XT-W1-01` X-Terminal 工单与契约源统一（落盘规范 + 索引）
2. `XT-W1-02` Hub 路由状态机收敛（auto/grpc/file 语义一致）
3. `XT-W1-03` Pending Grants 真相源接入 Supervisor
4. `XT-W1-04` 高风险动作 grant 强制与旁路扫描
5. `XT-W1-05` 母子项目谱系模型（root/parent/lineage_path）+ UI 可视化
6. `XT-W1-06` 复杂项目自动拆分器 v2（DAG 子项目边界 + 可执行 DoD）
7. `XT-W2-05` Context Explain 面板标准化（来源/成本/原因）
8. `XT-W2-06` Token Guard（预算上限 + 降级策略）
9. `XT-W2-07` Skills Preflight + 三层信任域最小闭环
10. `XT-W2-08` 子项目 AI 并行分配器（按任务类型/风险/预算）
11. `XT-W2-15` 队列排空与重启窗口保护（drain window）
12. `XT-W2-16` 重试反饥饿调度（lastAttemptAt + backoff）
13. `XT-W2-17` 父会话上下文溢出保护（parent fork token guard）
14. `XT-W2-18` 同通道回退 + 跨通道硬阻断（origin-safe fallback）
15. `XT-W2-19` 运行完成清理安全网（dispatch idle/typing cleanup）
16. `XT-W3-08` X-Terminal 发布门禁（XT-G0..G5）

### P1（增强收益，提升体验壁垒）

17. `XT-W3-09` Supervisor 优先级建议与一键跳转
18. `XT-W3-10` 多项目并行车道调度（1/2/4 动态）
19. `XT-W4-11` 跨会话记忆去重复用（省 token）
20. `XT-W4-12` Skill 热更新一致性（watcher + snapshot）
21. `XT-W5-13` 回归日报自动化（效率/安全/token 三轴）
22. `XT-W5-14` 灰度与回滚演练产品化

## 6.1 Supervisor 自动拆分专项（详细入口）

- 详细工单池：`x-terminal/work-orders/xt-supervisor-autosplit-multilane-work-orders-v1.md`
- 覆盖范围：
  - 自动拆分提案 -> 用户确认 -> hard/soft 落盘（是否建子项目）
  - PromptFactory 质量编译 -> 多泳道 AI 自动分配
  - Heartbeat 主动巡检 -> 阻塞/权限事件秒级接管（自动处理或通知用户）
  - 多泳道结果收口与质量门禁

## 6.2 Supervisor 多泳池自适应专项（详细入口）

- 详细工单池：`x-terminal/work-orders/xt-supervisor-multipool-adaptive-work-orders-v1.md`
- 执行工单包：`x-terminal/work-orders/xt-supervisor-multipool-lane-execution-pack-v1.md`
- 实现级子工单（自动推进 + 介入等级）：`x-terminal/work-orders/xt-w2-23-w2-26-autocontinue-autonomy-implementation-pack-v1.md`
- 实现级子工单（Token 最优上下文胶囊 + 三段式提示词）：`x-terminal/work-orders/xt-w2-24-token-optimal-context-capsule-implementation-pack-v1.md`
- 实现级子工单（阻塞依赖图 + 即时解阻编排）：`x-terminal/work-orders/xt-w2-27-anti-block-unblock-orchestration-implementation-pack-v1.md`
- 覆盖范围：
  - 按复杂度与模块图动态拆分泳池（pool 数与 lane 数均可变）
  - 策略档位：`conservative|balanced|aggressive`
  - 用户参与等级：`zero_touch|critical_touch|guided_touch`（兼容 `hands_off|critical_only|interactive`）
  - 提示词包自动编译（每个执行 AI 一套 Prompt Pack）
  - 提示词强制三段式：`Stable Core + Task Delta + Context Refs`（Context Refs 仅引用 ID，不贴全文）
  - 阻塞治理强制走 `wait-for graph + dual-green dependency + unblock router`（依赖转绿后秒级唤醒等待泳道）
  - 池内集成测试 -> 全局合并 -> 自动交付通知

## 7) 详细工单（可直接执行）

### XT-W1-01（P0）工单与契约源统一

- 目标：X-Terminal 工单统一落盘到 `x-terminal/work-orders/`，避免跨目录分散。
- 依赖：无。
- 交付物：本工单文档 + index + 主索引挂载。
- 验收指标：X-Terminal 新工单落盘合规率 100%。
- 回归样例：
  - 在非 `x-terminal/work-orders/` 新增 X-Terminal 工单 -> CI/审查阻断。
- Gate：`XT-G0`
- 估时：0.5 天

### XT-W1-02（P0）Hub 路由状态机收敛

- 目标：`auto|grpc|file` 三种路由在成功/失败/回退行为上可预测。
- 依赖：`XT-W1-01`。
- 交付物：状态机文档、错误码映射、回退规则测试。
- 实施记录：见 `work-orders/xt-w1-02-route-state-machine.md`（Lane-A）。
- 验收指标：路由分歧缺陷下降 >= 80%。
- 回归样例：
  - grpc 不可用 + auto 模式 -> 正确回退 file。
  - grpc 模式失败 -> 不允许 silent fallback。
- Gate：`XT-G1/XT-G4`
- 估时：1 天

### XT-W1-03（P0）Pending Grants 真相源接入

- 目标：Supervisor 的授权状态来自 Hub 真相源，不再依赖日志推断。
- 依赖：`XT-W1-02`。
- 交付物：pending grants API 对接、UI 卡片、排序策略。
- 实施记录：见 `work-orders/xt-w1-03-pending-grants-source-of-truth.md`（Lane-D）。
- 验收指标：待处理授权识别准确率 >= 99%。
- 回归样例：
  - 授权撤销后 UI 状态 2 秒内收敛。
  - 重复 request 不重复显示。
- Gate：`XT-G1/XT-G3`
- 估时：1 天

### XT-W1-04（P0）高风险动作 grant 强制与旁路扫描

- 目标：任何高风险动作必须携带有效 `grant_id`。
- 依赖：`XT-W1-02`。
- 交付物：统一 gate hook、旁路扫描器、拒绝码标准化。
- OpenClaw 经验回灌：非消息入口（reaction/pin/member/webhook）同样纳入授权主链，禁止“消息以外”的旁路。
- 实施记录：见 `work-orders/xt-w1-04-high-risk-grant-enforcement.md`（Lane-C）。
- 验收指标：`bypass_grant_execution = 0`。
- 回归样例：
  - 无 grant_id 执行高风险动作 -> 必须 deny。
  - 过期 grant 重放 -> 必须 deny + 审计。
  - 未授权 sender 触发 reaction/pin/member 事件 -> 必须 deny + 审计。
- Gate：`XT-G2/XT-G4`
- 估时：1.5 天

### XT-W1-05（P0）母子项目谱系模型 + 可视化

- 目标：让每个子项目都能明显看出来自哪个母项目，并可在 UI 与审计中追溯。
- 依赖：`XT-W1-02`、`docs/memory-new/xhub-memory-v3-m3-work-orders-v1.md` 的 `M3-W1-03`。
- 交付物：
  - `ProjectModel` 扩展字段：`rootProjectId`、`parentProjectId`、`lineagePath`、`parentTaskId`、`splitRound`、`childIndex`。
  - 项目卡片/详情页谱系显示（母->子树、深度、来源任务）。
  - 谱系一致性校验器（禁止孤儿、禁止环、禁止跨 root 串联）。
- 验收指标：
  - `lineage_visibility_coverage = 100%`
  - `parent_link_accuracy >= 99.9%`
  - `lineage_cycle_incidents = 0`
- 回归样例：
  - 子项目缺 `parentProjectId` -> 阻断进入运行态。
  - A->B->A 谱系环路 -> 阻断并提示 `lineage_cycle_detected`。
  - 母项目归档后新建子项目 -> 默认拒绝。
- Gate：`XT-G0/XT-G1/XT-G4`
- 估时：1.5 天

### XT-W1-06（P0）复杂项目自动拆分器 v2

- 目标：把复杂母项目自动拆分为可并行执行的多个子项目（基于 DAG），最大化编程吞吐。
- 依赖：`XT-W1-05`。
- 交付物：
  - split policy v2（复杂度阈值、拆分粒度、禁止过度拆分规则）。
  - 子项目 DAG 生成器（依赖、关键路径、并行组）。
  - 拆分预览与确认面板（子项目目标/输入/输出/DoD）。
- 验收指标：
  - `auto_split_precision >= 90%`
  - `parallelizable_task_ratio >= 60%`
  - `split_plan_conflict_rate <= 5%`
- 回归样例：
  - 简单任务误拆分 -> 必须回退单项目执行。
  - 拆分结果存在循环依赖 -> 阻断并提示修正建议。
  - 子项目 DoD 缺失 -> 不允许分配执行。
- Gate：`XT-G1/XT-G3/XT-G4`
- 估时：2 天

### XT-W2-05（P0）Context Explain 面板标准化

- 目标：每次回答可解释“用了哪些上下文、为什么、花了多少 token”。
- 依赖：`XT-W1-03`。
- 交付物：Explain API 适配层、UI 面板、审计字段。
- 验收指标：`context_explain_coverage = 100%`。
- 回归样例：
  - 空注入场景 -> 显示无命中原因。
  - DLP 阻断片段 -> 显示阻断原因但不泄露内容。
- Gate：`XT-G1/XT-G2/XT-G3`
- 估时：1 天

### XT-W2-06（P0）Token Guard

- 目标：单次任务 token 成本可控，超预算自动降级。
- 依赖：`XT-W2-05`。
- 交付物：预算策略、超限处理器、成本报表字段。
- 验收指标：`token_budget_overrun_rate <= 3%`。
- 回归样例：
  - 超预算 -> 切本地链路并写审计。
  - 远程计费未确认 -> 拒绝执行。
- Gate：`XT-G3/XT-G5`
- 估时：1 天

### XT-W2-07（P0）Skills Preflight + 三层信任域最小闭环

- 目标：技能首次运行失败前置发现，未签名高风险默认拒绝。
- 依赖：`XT-W1-04`。
- 交付物：preflight 检查、trusted/restricted/untrusted 路由、拒绝码。
- 验收指标：`skill_first_run_success_rate >= 95%`；`unsigned_high_risk_skill_exec = 0`。
- 回归样例：
  - 缺 bin/env/config -> 返回可执行修复建议。
  - untrusted skill 请求高风险动作 -> deny + 审计。
- Gate：`XT-G2/XT-G4`
- 估时：1.5 天

### XT-W2-08（P0）子项目 AI 并行分配器

- 目标：按任务类型/风险等级/预算为每个子项目分配最合适 AI，并稳定并行执行。
- 依赖：`XT-W1-06`、`XT-W2-06`。
- 交付物：
  - assignment engine（任务类型 -> 模型 profile -> 执行 lane）。
  - 子项目级 token budget + 降级策略（超限自动回退）。
  - 并行调度器（1/2/4 动态并发 + 防 starvation）。
- 验收指标：
  - `child_project_assignment_success_rate >= 98%`
  - `split_to_parallel_start_p95_ms <= 8000`
  - `token_budget_overrun_rate <= 3%`
- 回归样例：
  - 高风险子项目分配到不合规 profile -> 阻断。
  - 单子项目长尾卡住 -> 其余子项目可继续推进且有告警。
  - 预算耗尽 -> 自动降级并记录审计。
- Gate：`XT-G2/XT-G3/XT-G4`
- 估时：1.5 天

### XT-W2-15（P0）队列排空与重启窗口保护

- 目标：在 Supervisor/调度器重启或发布窗口中，防止“已接收但被静默丢弃”的任务。
- 依赖：`XT-W2-08`。
- 交付物：
  - `restart_drain` 状态机（draining/rejecting/recovering）
  - 重启窗口内 enqueue 拒绝策略（返回可解释错误码，不吞任务）
  - 重启后队列恢复与一致性检查
- 验收指标：
  - `enqueue_during_drain_silent_drop = 0`
  - `restart_recovery_success_rate >= 99%`
- 回归样例：
  - 重启排空窗口收到新任务 -> 明确拒绝并给重试建议
  - 重启后遗留队列 -> 可恢复且顺序不乱
- Gate：`XT-G1/XT-G4`
- 估时：1 天

### XT-W2-16（P0）重试反饥饿调度（lastAttemptAt + backoff）

- 目标：避免某些 lane 因持续失败重试而饿死其它可执行任务。
- 依赖：`XT-W2-15`。
- 交付物：
  - `lastAttemptAt` 持久化
  - 可执行时间窗判定（`lastAttemptAt + backoff`）
  - 延迟任务不阻塞后续 ready 任务
- 验收指标：
  - `retry_starvation_incidents = 0`
  - `ready_task_bypass_rate = 100%`（ready 任务可越过未到重试窗的任务）
- 回归样例：
  - 头部任务持续失败 -> 后续 ready 任务仍可推进
  - 进程重启后 backoff 窗口保持一致，不重复风暴重试
- Gate：`XT-G3/XT-G4`
- 估时：1 天

### XT-W2-17（P0）父会话上下文溢出保护（parent fork token guard）

- 目标：防止子项目/子线程继承过大的父会话上下文导致“新会话被上下文压垮”。
- 依赖：`XT-W2-08`。
- 交付物：
  - `parent_fork_max_tokens` 配置项（默认安全值）
  - 溢出可见错误（非静默失败）与自动裁剪策略
  - Supervisor 提示“建议拆分/建议降并发/建议精简上下文”
- 验收指标：
  - `parent_fork_overflow_brick_incidents = 0`
  - `context_overflow_visible_error_rate = 100%`
- 回归样例：
  - 父上下文超阈值启动子 lane -> 不得静默失败，需可解释提示
  - 配置值=0（禁限流）时行为可控且有风险审计
- Gate：`XT-G1/XT-G3/XT-G4`
- 估时：1 天

### XT-W2-18（P0）同通道回退 + 跨通道硬阻断（origin-safe fallback）

- 目标：origin 路由失败时允许“同通道回退”，但严格禁止跨通道回退，防止误投递/越权。
- 依赖：`XT-W1-02`, `XT-W1-05`。
- 交付物：
  - fallback policy：`same_channel_allowed / cross_channel_denied`
  - 失败语义标准化（route_origin_unavailable / cross_channel_blocked）
  - 审计事件：`route.fallback.applied` / `route.fallback.blocked`
- 验收指标：
  - `cross_channel_fallback_count = 0`
  - `same_channel_fallback_success_rate >= 95%`
- 回归样例：
  - origin adapter 临时失败 -> 同通道 fallback 成功
  - 试图跨通道 fallback -> 必须阻断并审计
- Gate：`XT-G2/XT-G4`
- 估时：1 天

### XT-W2-19（P0）运行完成清理安全网（dispatch idle/typing cleanup）

- 目标：保证 run 完成后 dispatch idle、typing cleanup 等收口信号一定触发，避免“卡住中”假象。
- 依赖：`XT-W2-16`。
- 交付物：
  - run completion 最终化钩子（失败路径也执行）
  - cleanup TTL 安全网（丢信号时自动清理）
  - 监控指标：`stuck_dispatch_incidents`、`stuck_typing_incidents`
- 验收指标：
  - `stuck_dispatch_incidents = 0`
  - `stuck_typing_incidents = 0`
- 回归样例：
  - onIdle 未触发 -> TTL 安全网应清理状态
  - 工具报错结束 -> dispatch 状态仍能归零
- Gate：`XT-G3/XT-G4`
- 估时：1 天

### XT-W3-08（P0）发布门禁自动化（XT-G0..G5）

- 目标：发布规则脚本化，门禁失败即阻断。
- 依赖：`XT-W1-04`, `XT-W2-06`, `XT-W2-07`。
- 交付物：workflow、门禁报告模板、回滚脚本、`doctor` 风险检查（dm/group allowlist、ws origin、shared-token auth）与 `secrets apply --dry-run` 报告。
- 实施记录：见 `work-orders/xt-w3-08-release-gate-skeleton.md`（Lane-E skeleton）。
- 进展（2026-02-28）：发布门禁已接入 `supervisor_doctor_report.json` 硬检查；无报告、`release_blocked_by_doctor_without_report != 0`、或 Doctor 存在 blocking findings 均直接阻断（fail-closed）；Doctor 预检会同步产出 `doctor-report.json` 与 `secrets-dry-run-report.json` 供 XT-G5 读取证据，并新增结构化字段校验 + CM-W5-20 回归样例（strict 缺 secrets 报告必失败、字段非法必失败）。
- 进展（2026-03-01）：新增 `XT_GATE_VALIDATE_RELEASE_EVIDENCE_MATRIX=1` 四象限回归（`release_preset × auto_prepare`），并在 strict 发布预设演练中固化 `XT_GATE_RELEASE_PRESET=1 + XT_GATE_AUTO_PREPARE_RELEASE_EVIDENCE=1`；矩阵日志归档为 `.axcoder/reports/xt-gate-release-evidence-matrix.log`，并由 `xt_release_evidence_matrix_log_validator.js` 生成 `.axcoder/reports/xt-gate-release-evidence-matrix.summary.json`（schema=`xt_release_evidence_matrix.v1`）；同时 `xt_release_evidence_matrix_validator_regression.js` 会执行 validator 正/负例回归并归档 `.axcoder/reports/xt-gate-release-evidence-matrix.validator-regression.log`，三者均写入 `xt-gate-report.md` / `xt-report-index.json`。
- CI 附加保障（2026-03-01）：`xt-gates.yml` 新增独立步骤 `Matrix Validator Regression Unit`，直接执行 `node scripts/ci/xt_release_evidence_matrix_validator_regression.js`，在 gate 主流程前快速失败。
- 本地提交流程（2026-03-01）：新增 `scripts/ci/xt_gate_fast_checks.sh`，默认执行最快路径（validator 回归：matrix + fast-check trend）；可通过 `XT_FAST_CHECK_RUN_BUILD=1 XT_FAST_CHECK_RUN_MATRIX=1` 升级为 `swift build + baseline matrix gate` 的全量快检，并自动输出 `.axcoder/reports/xt-fast-check-summary.json` 与 `.axcoder/reports/xt-fast-check-history.json` 供本地审计留痕（history 默认保留最近 20 条，可由 `XT_FAST_CHECK_HISTORY_LIMIT` 覆盖；含 pass/fail/warn 聚合与 per-step 状态分布）。
- 验收指标：手工放行项 = 0（紧急例外需审计）。
- 回归样例：
  - 缺关键指标输入 -> 发布失败。
  - 回滚失败 -> 阻断继续发布。
  - `dmPolicy=allowlist` 且 `allowFrom=[]` -> 发布失败并输出修复建议。
- 审计发布说明（2026-02-28）：
  - baseline 与 strict 门禁均通过，`XT-W3-08` / `CRK-W1-08` / `CM-W5-20` 三项均为 PASS。
  - 发布决策报告：`.axcoder/reports/xt-gate-report.md`（`decision: GO`）。
  - 关键证据：`.axcoder/reports/doctor-report.json`、`.axcoder/reports/secrets-dry-run-report.json`、`.axcoder/reports/xt-rollback-verify.json`。
- Gate：`XT-G5`
- 估时：1.5 天

### XT-W3-09（P1）Supervisor 优先级建议与一键跳转

- 目标：把“先处理哪个授权/项目”做成可执行建议。
- 依赖：`XT-W1-03`。
- 交付物：优先级引擎、动作按钮、上下文跳转。
- 进展（2026-02-28）：已补“优先级解释 + 可操作建议”输出路径：Doctor/Secrets 预检结果按 P0/P1 卡片展示，包含风险解释、最小修复步骤与验证提示，支持从 Supervisor 直接触发重跑预检。
- 验收指标：审批等待 p95 降低 >= 30%。
- 回归样例：
  - 多 pending grants 并发时顺序稳定。
- Gate：`XT-G3`
- 估时：1 天

### XT-W3-10（P1）多项目并行车道调度

- 目标：根据负载动态切换 1/2/4 路，减少拥塞和长尾。
- 依赖：`XT-W2-06`。
- 交付物：lane planner、降级策略、可观测指标。
- 验收指标：`queue_wait_p90_ms <= 3200`。
- 回归样例：
  - 资源紧张 -> 自动降级不丢审计。
- Gate：`XT-G3/XT-G4`
- 估时：1.5 天

### XT-W4-11（P1）跨会话记忆去重复用

- 目标：减少重复注入与重复检索成本。
- 依赖：`XT-W2-05`。
- 交付物：dedup 索引、reuse policy、命中审计。
- 验收指标：`cross_session_dedup_hit_rate >= 60%`。
- 回归样例：
  - 冲突证据不可误去重。
- Gate：`XT-G1/XT-G3`
- 估时：1.5 天

### XT-W4-12（P1）Skill 热更新一致性

- 目标：热更新后运行态与配置态一致，避免“看起来更新了但实际没生效”。
- 依赖：`XT-W2-07`。
- 交付物：watcher、snapshot 校验、回滚开关。
- 验收指标：热更新后异常回滚成功率 >= 99%。
- 回归样例：
  - 更新中断 -> 自动回到上个稳定版本。
- Gate：`XT-G4/XT-G5`
- 估时：1 天

### XT-W5-13（P1）回归日报自动化

- 目标：每日自动输出效率/安全/token 三轴偏差与根因聚类。
- 依赖：`XT-W3-08`。
- 交付物：日报脚本、Top root cause 视图、owner 路由。
- 验收指标：`mean_time_to_root_cause <= 30min`。
- 回归样例：
  - 同类异常跨模块爆发 -> 自动聚类同源。
- Gate：`XT-G5`
- 估时：1 天

### XT-W5-14（P1）灰度与回滚演练产品化

- 目标：例行灰度、快速回滚、审计留痕形成标准流程。
- 依赖：`XT-W3-08`。
- 交付物：灰度模板、回滚演练脚本、值班手册。
- 验收指标：回滚成功率 >= 99%；MTTR <= 15min。
- 回归样例：
  - Gate 失败仍尝试发布 -> 必须阻断并记录。
- Gate：`XT-G5`
- 估时：1 天

## 8) 并行排程建议（两周启动版）

- D1-D2：Lane-A 做 `XT-W1-02`；Lane-E 做 `XT-W1-01`。
- D3-D4：Lane-D 做 `XT-W1-03`；Lane-C 做 `XT-W1-04`。
- D5-D6：Lane-A + Lane-D 做 `XT-W1-05/06`（谱系 + 自动拆分）。
- D7-D8：Lane-B 做 `XT-W2-06/08`；Lane-C 做 `XT-W2-07`。
- D9：Lane-A + Lane-D 做 `XT-W2-15`（排空/重启窗口保护）。
- D10：Lane-A 做 `XT-W2-16`（重试反饥饿），Lane-E 收口 `XT-W3-08`（门禁接入 CI）。
- D11：Lane-A + Lane-D 做 `XT-W2-17`（父会话溢出保护）。
- D12：Lane-A + Lane-C 做 `XT-W2-18/19`（origin-safe fallback + 清理安全网）。
- D13-D14：并行启动 `XT-W3-09/10`。

## 9) 与现有计划对齐（避免双写漂移）

- 与 `docs/memory-new/xhub-memory-v3-m3-work-orders-v1.md` 对齐：X-Terminal 侧只保留模块级执行细则与接口落点。
- 与 `M3-W1-03` 对齐：谱系字段与拒绝码保持一致（`lineage_parent_missing` / `lineage_cycle_detected` / `lineage_root_mismatch`）。
- 与 `docs/memory-new/xhub-kiro-spec-gates-work-orders-v1.md` 对齐：共用 spec-driven 与门禁方法，不重复定义规则。
- 与 `X_MEMORY.md` 对齐：主记忆只记入口与状态，详细变更在本工单维护。

## 9.1 OpenClaw 经验回灌（2026-02-24 ~ 2026-02-27）

- 入口一致性：授权与风控不要只盯 message，reaction/pin/member/webhook 等“非消息入口”必须同策略。
- 预鉴权防护：发布门禁新增 pre-auth body/key cap 与 WS unauthorized flood breaker 检查项。
- 运维前置：发布前必须跑 `doctor + secrets dry-run`，把“可修复配置错误”挡在上线前。
- 重启可靠性：调度器进入 restart drain 窗口时，禁止静默接单；必须显式拒绝并可恢复。
- 重试公平性：失败重试要持久化 `lastAttemptAt` 并按 backoff 窗口调度，防止队列饥饿。
- 上下文溢出保护：子项目继承父会话时必须有 token 上限与可见错误，禁止静默“新会话卡死”。
- 路由边界保护：origin 失败仅允许同通道回退，跨通道必须硬阻断并审计。
- 清理安全网：run 完成路径必须强制 dispatch idle/typing cleanup，避免状态残留导致误判。
