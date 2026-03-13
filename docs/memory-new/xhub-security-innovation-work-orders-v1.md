# X-Hub 安全创新专项工单（v1，规划冻结版）

- version: v1.0
- updatedAt: 2026-03-01
- owner: Hub Runtime / X-Terminal / Security / QA / Product
- status: planning_frozen_not_dispatched
- dispatchPolicy: hold（已冻结但暂不派发）
- scope: `x-hub-system/`（Hub 控制面 + X-Terminal 编排层 + Skills/Payment/Memory 高风险链路）
- parent:
  - `X_MEMORY.md`
  - `docs/WORKING_INDEX.md`
  - `docs/memory-new/xhub-lane-command-board-v2.md`
  - `docs/memory-new/xhub-memory-v3-execution-plan.md`
  - `docs/memory-new/xhub-hub-to-xterminal-capability-gate-v1.md`
  - `docs/memory-new/xhub-connector-reliability-kernel-work-orders-v1.md`
  - `docs/memory-new/xhub-spec-gates-work-orders-v1.md`
  - `x-terminal/work-orders/xterminal-parallel-work-orders-v1.md`
  - `x-terminal/work-orders/xt-supervisor-autosplit-multilane-work-orders-v1.md`
  - `x-terminal/work-orders/xt-skills-compat-reliability-work-orders-v1.md`

## 0) 使用方式（先看）

- 本文是“安全创新专项”的统一工单池，当前阶段只做 contract + gate + evidence 冻结，**不做派发执行**。
- 目标不是新增孤立安全功能，而是把“记忆、AI、支付、授权、技能”统一纳入可证明安全主链。
- 当进入派发阶段后，协作执行统一走 `docs/memory-new/xhub-lane-command-board-v2.md`（单文件分区 + CR 实时变更 + 7 件套）。
- 所有工单均遵循 fail-closed：任何异常、证据缺失、策略冲突一律 deny/downgrade，不允许静默放行。
- 当且仅当你批准进入执行阶段，才把本文件中的工单转入对应泳道并开启实施。

## 1) 北极星目标（安全可证明 + 可恢复 + 可降级）

### 1.1 安全目标

- 高风险动作 100% 绑定审批意图，不可复用、不可重放。
- 支付与外部副作用动作默认可预演、可撤销、可审计。
- secret/credential 从输入到外发全链 taint 可追踪，命中即阻断。

### 1.2 可靠性目标

- 审计链被篡改可秒级感知。
- 核心风控组件异常时自动进入安全降级模式（只读/本地）。
- 发布门禁必须基于 require-real 证据，不接受 synthetic 冒绿。

### 1.3 效率与成本目标

- 安全增强不显著拖慢主链延迟。
- 通过风险分层与缓存复用避免无谓 token 和审批开销。
- 对开发侧保持可操作性（错误可解释、修复路径明确）。

## 2) 专项 Gate（SI-Gate）

- `SI-G0 / Contract Freeze`：安全创新涉及的 contract、deny_code、审计字段全部冻结并版本化。
- `SI-G1 / Correctness`：核心状态机、签名校验、审批绑定、支付预演回归全绿。
- `SI-G2 / Security Invariants`：旁路执行、审批复用、secret 外发、revocation 绕过全部阻断。
- `SI-G3 / Efficiency + Token`：延迟、审批时延、token 开销达到阈值。
- `SI-G4 / Reliability`：重启/回放/时钟漂移/链路抖动下仍 fail-closed 且可恢复。
- `SI-G5 / Release Ready`：require-real 证据齐全、回滚演练通过、internal pass-lines 满足发布线。

与现有 Gate 映射：
- `SI-G0 -> XT-G0 + Gate-CM0 + KQ-G0`
- `SI-G1 -> XT-G1 + Gate-CM1 + KQ-G1`
- `SI-G2 -> XT-G2 + Gate-CM2 + KQ-G2`
- `SI-G3 -> XT-G3 + Gate-CM3 + KQ-G3`
- `SI-G4 -> XT-G4 + Gate-CM4 + CRK P0/P1`
- `SI-G5 -> XT-G5 + Gate-CM5 + KQ-G5 + XT-Ready + internal pass-lines`

## 3) DoR / DoD（强制）

Definition of Ready (DoR)
- 输入输出、失败语义、deny_code、审计字段、回滚策略定义完整。
- 与现有 Hub/X-Terminal contract 冲突点已列出并有处置策略。
- 指标可观测且能落到现有 report/gate 产物。

Definition of Done (DoD)
- 代码 + 文档 + 测试 + 证据 + 回滚方案同步完成。
- 通过对应 SI-Gate，不得人工豁免。
- 关键链路必须提供 machine-readable 证据文件。

## 4) KPI（专项）

### 4.1 安全 KPI
- `approval_replay_block_rate = 100%`
- `high_risk_action_without_intent_binding = 0`
- `secret_taint_egress_block_rate = 100%`
- `revoked_skill_execution_attempt_success = 0`
- `payment_mismatch_execution = 0`

### 4.2 可靠性 KPI
- `audit_tamper_detect_time_p95_ms <= 60000`
- `emergency_downgrade_activation_success_rate >= 99%`
- `require_real_evidence_pass_rate = 100%`（release 口径）
- `state_corrupt_incidents_unhandled = 0`

### 4.3 效率/成本 KPI
- `high_risk_gate_added_latency_p95_ms <= 80`
- `approval_time_p95_ms <= 2500`
- `token_per_high_risk_task_delta <= -10%`（相对当前 M3 基线）
- `policy_shadow_divergence_untriaged = 0`

## 5) 工单总览（P0/P1）

### P0（阻断型，先冻结）

1. `SI-W1-01` 审批意图绑定 2.0（argv/cwd/identity/risk_floor/project_scope）
2. `SI-W1-02` 一次性能力票据（one-time capability token）
3. `SI-W1-03` 支付双阶段提交 + Undo Window
4. `SI-W1-04` Memory 微分区加密 + 临时解密会话
5. `SI-W1-05` Taint 传播图与外发硬阻断
6. `SI-W2-06` Skill 供应链证明执行（签名+hash+SBOM+capability）
7. `SI-W2-07` Policy Shadow 决策并行核对
8. `SI-W2-08` 审计哈希链 + Witness 锚定
9. `SI-W3-09` 蜜罐凭证/蜜罐指令防渗透探针
10. `SI-W3-10` 紧急自愈降级（只读/本地模式）
11. `SI-W3-11` require-real 安全证据联动门禁

### P1（增强型，执行阶段再开）

12. `SI-W4-12` 风险自适应审批摩擦控制（低风险降摩擦，高风险强确认）
13. `SI-W4-13` 反内鬼双人规则（支付/密钥操作）
14. `SI-W5-14` 安全混沌演练产品化（供应链/重放/证据污染）
15. `SI-W5-15` 安全周报自动归因（Top root cause + owner 路由）

## 6) 详细工单（含 DoD/Gate/KPI/回归样例）

### SI-W1-01（P0）审批意图绑定 2.0

- 目标：把审批绑定到不可变执行身份，彻底阻断审批复用与路径替换。
- 依赖：`M3-W1-02` 现有 approval binding、`CM-W3-19`。
- 交付物：
  - 绑定字段升级：`tool_args_hash + exec_argv + exec_cwd + identity_hash + risk_floor + project_scope`。
  - 执行前二次校验器（任何漂移 fail-closed）。
  - machine-readable deny_code：`approval_binding_invalid|approval_identity_mismatch|request_tampered`。
- DoD：
  - 审批复用攻击路径全部可检测并拒绝。
  - 相关拒绝均有完整审计记录。
- Gate：`SI-G1/SI-G2/SI-G4`
- KPI：
  - `approval_replay_block_rate = 100%`
  - `approval_mismatch_execution = 0`
- 回归样例：
  - trailing-space argv 漂移 -> deny。
  - cwd symlink 重定向 -> deny。
  - risk_tier 降级重放 -> deny。
- 估时：1.5 天。

### SI-W1-02（P0）一次性能力票据

- 目标：高风险执行使用一次性 capability token，执行成功即失效。
- 依赖：`SI-W1-01`。
- 交付物：
  - capability token 发行/消费/吊销状态机。
  - TTL + nonce + request_id 绑定。
  - 重放检测与拒绝审计。
- DoD：
  - 同一 token 二次使用必拒绝。
  - token 过期/吊销后不可执行。
- Gate：`SI-G1/SI-G2/SI-G4`
- KPI：
  - `capability_token_replay_success = 0`
  - `high_risk_action_without_intent_binding = 0`
- 回归样例：
  - 并发双击执行 -> 仅一次成功。
  - 过期 token 执行 -> deny(token_expired)。
- 估时：1.5 天。

### SI-W1-03（P0）支付双阶段提交 + Undo Window

- 目标：支付动作“先预演、再确认、后执行、可撤销”，避免不可逆误操作。
- 依赖：`SI-W1-02`、Connector Outbox（`CRK-W1-03`）。
- 交付物：
  - Payment Preview Card（金额/对手方/手续费/风险/撤销窗口）。
  - 两阶段状态机：`prepared -> approved -> dispatched -> acked|compensated`。
  - undo window worker（幂等补偿）。
- DoD：
  - 无 preview 无法直接支付。
  - undo window 内可执行补偿且可追溯。
- Gate：`SI-G1/SI-G2/SI-G4`
- KPI：
  - `payment_preview_coverage = 100%`
  - `payment_undo_window_coverage = 100%`
  - `payment_mismatch_execution = 0`
- 回归样例：
  - preview 与执行参数不一致 -> deny(request_tampered)。
  - dispatch 后回执丢失 -> compensation 幂等执行。
- 估时：2 天。

### SI-W1-04（P0）Memory 微分区加密 + 临时解密会话

- 目标：把高敏记忆从“全量可读”改为“按需最小可见”，降低集中存储爆炸半径。
- 依赖：`CM-W1-03` Progressive Disclosure、现有 vault/keymgmt 规范。
- 交付物：
  - 分区密钥模型（`project/sensitivity/trust`）。
  - 短生命周期解密令牌（run 结束自动清理）。
  - 明文暴露审计与越界阻断策略。
- DoD：
  - 高敏内容默认不出明文。
  - 解密令牌过期后无法复用。
- Gate：`SI-G2/SI-G3/SI-G4`
- KPI：
  - `sensitive_memory_plaintext_exposure = 0`（未授权场景）
  - `memory_decrypt_token_reuse_success = 0`
- 回归样例：
  - 跨 project 解密请求 -> deny(scope_violation)。
  - 过期解密令牌读取 -> deny(token_expired)。
- 估时：2 天。

### SI-W1-05（P0）Taint 传播图与外发硬阻断

- 目标：把 secret/credential/payment taint 从输入到输出全链追踪，命中外发路径即阻断。
- 依赖：`SI-W1-04`、`CRK-W1-04` 内联 Gate。
- 交付物：
  - taint 标签体系与传播规则。
  - egress gate（web/email/payment/remote model）统一阻断 hook。
  - 阻断 explain（不泄露内容）。
- DoD：
  - taint 命中外发无旁路。
  - 阻断日志可追溯并可统计。
- Gate：`SI-G2/SI-G4`
- KPI：
  - `secret_taint_egress_block_rate = 100%`
  - `credential_finding_block_rate = 100%`
- 回归样例：
  - prompt 包含 API key 诱导外发 -> deny。
  - base64 混淆凭证 -> 仍识别并阻断。
- 估时：2 天。

### SI-W2-06（P0）Skill 供应链证明执行

- 目标：Skill 执行前强制验证签名+hash+SBOM+capabilities，防供应链投毒。
- 依赖：`SKC-W1-03/04`、`CM-W3-08`。
- 交付物：
  - proof bundle 验证器。
  - trusted publisher 与 revocation 联动。
  - 失败拒绝码统一化。
- DoD：
  - 未签名高风险 skill 一律拒绝。
  - revoked skill 在 Hub 与 Runner 双拒绝。
- Gate：`SI-G2/SI-G4`
- KPI：
  - `unsigned_high_risk_skill_exec = 0`
  - `revoked_skill_execution_attempt_success = 0`
- 回归样例：
  - SBOM 缺失/损坏 -> deny(sbom_invalid)。
  - skill hash 漂移 -> deny(hash_mismatch)。
- 估时：1.5 天。

### SI-W2-07（P0）Policy Shadow 决策并行核对

- 目标：真实策略之外再跑影子策略，对比结果差异，提前发现策略漂移和旁路风险。
- 依赖：`SI-W1-05`。
- 交付物：
  - shadow evaluator（只评估不执行）。
  - divergence 报警与 triage 路由。
  - 策略差异审计模型。
- DoD：
  - 高风险策略差异可在单次 run 内被捕捉。
  - 差异事件有 owner 与处置状态。
- Gate：`SI-G1/SI-G3/SI-G4`
- KPI：
  - `policy_shadow_divergence_untriaged = 0`
  - `policy_divergence_detect_time_p95_ms <= 3000`
- 回归样例：
  - 主策略 allow，影子策略 deny -> 触发告警 + fail-closed 建议。
  - 影子策略组件异常 -> 主链不放宽。
- 估时：1 天。

### SI-W2-08（P0）审计哈希链 + Witness 锚定

- 目标：让关键审计不可静默篡改，支持完整性验证与快速定位破坏点。
- 依赖：`SI-W2-07`。
- 交付物：
  - 审计 hash-chain（前后指针）。
  - witness 锚定（周期写入只写存储/外部锚点）。
  - 篡改扫描与告警。
- DoD：
  - 审计破坏可自动检出。
  - 检测结果可追溯到具体事件区段。
- Gate：`SI-G2/SI-G4/SI-G5`
- KPI：
  - `audit_tamper_detect_time_p95_ms <= 60000`
  - `audit_chain_break_unnoticed = 0`
- 回归样例：
  - 中间事件被删改 -> 链断裂告警。
  - witness 不可达 -> 进入降级并阻断 release。
- 估时：1.5 天。

### SI-W3-09（P0）蜜罐凭证/蜜罐指令防渗透探针

- 目标：主动捕捉“越权读取/外发”行为，提升未知攻击检测能力。
- 依赖：`SI-W1-05`。
- 交付物：
  - honey credential/honey command 注入策略。
  - 命中后的自动隔离策略（降级 + 提升审计级别）。
  - 安全事件上报模板。
- DoD：
  - 蜜罐命中可触发自动防护动作。
  - 无业务真实数据误伤。
- Gate：`SI-G2/SI-G4`
- KPI：
  - `honeypot_trigger_response_time_p95_ms <= 2000`
  - `honeypot_false_positive_rate < 1%`
- 回归样例：
  - 模拟 exfiltration 命中蜜罐 -> 自动切只读 + 告警。
- 估时：1 天。

### SI-W3-10（P0）紧急自愈降级（只读/本地模式）

- 目标：当审计、策略、证据链异常时自动进入安全模式，防止风险扩散。
- 依赖：`SI-W2-08`。
- 交付物：
  - emergency mode 状态机（normal -> restricted_local -> read_only）。
  - 自动触发器（审计链断、证据污染、未授权洪泛）。
  - 恢复流程（人工确认 + 证据修复）。
- DoD：
  - 触发后高风险外发默认关闭。
  - 恢复前不得自动回到 normal。
- Gate：`SI-G2/SI-G4/SI-G5`
- KPI：
  - `emergency_downgrade_activation_success_rate >= 99%`
  - `unsafe_recovery_without_ack = 0`
- 回归样例：
  - 审计 hash-chain 断裂 -> 自动 restricted_local。
  - 未授权洪泛 -> 自动 read_only 并保留证据。
- 估时：1.5 天。

### SI-W3-11（P0）require-real 安全证据联动门禁

- 目标：把 SI 专项证据接入 XT-Ready + internal pass-lines，防“文档绿灯、真实红灯”。
- 依赖：`SI-W3-10`、`SKC-W3-08/09/10`。
- 交付物：
  - SI 证据 schema（machine-readable）
  - strict-e2e + require-real 校验脚本接线
  - SI 失败归因报告模板
- DoD：
  - release 路径必须 require-real 才可通过。
  - sample/synthetic 证据在 release 路径一律 fail。
- Gate：`SI-G5`
- KPI：
  - `require_real_evidence_pass_rate = 100%`（release）
  - `synthetic_evidence_false_pass = 0`
- 回归样例：
  - `audit-smoke-*` 证据输入 -> fail。
  - 缺关键 SI 证据项 -> internal pass-lines NO-GO。
- 估时：1 天。

## 7) 里程碑建议（冻结版，不派发）

- M1（设计冻结）：完成 `SI-W1-01..SI-W1-05` contract 与 gate 评审。
- M2（证据冻结）：完成 `SI-W2-06..SI-W2-08` 的证据 schema 与回归清单。
- M3（发布冻结）：完成 `SI-W3-09..SI-W3-11` 的 require-real 收口设计。

说明：以上仅作为执行顺序建议，当前不下发 owner，不启动开发排程。

## 8) 暂不派发规则（本轮必须遵守）

- 所有工单状态保持 `planned`，不得改为 `in_progress`。
- 不创建 lane 级执行子工单、不分配负责人、不计入燃尽。
- 若需要启动执行，必须先由你确认“进入派发阶段”，再生成 lane 派发单。
