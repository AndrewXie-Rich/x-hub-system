# XT-W2-24 Token-Optimal Context Capsule 实现子工单包（Implementation Pack v1）

- version: v1.1
- updatedAt: 2026-03-03
- owner: XT-L2（Primary）/ XT-L1 / Hub-L3 / Hub-L5 / QA / AI-COORD-PRIMARY
- status: active
- scope: `XT-W2-24`（提示词最小化与质量保持）+ `XT-W2-24-A/B/C/D/E/F`
- parent:
  - `x-terminal/work-orders/xt-supervisor-multipool-adaptive-work-orders-v1.md`
  - `x-terminal/work-orders/xt-supervisor-multipool-lane-execution-pack-v1.md`
  - `x-terminal/work-orders/xt-w2-23-w2-26-autocontinue-autonomy-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-cbl-anti-block-context-governor-implementation-pack-v1.md`
  - `docs/memory-new/xhub-lane-command-board-v2.md`
  - `docs/memory-new/xhub-hub-to-xterminal-capability-gate-v1.md`

## 0) 目标与边界

- 目标：在不降低 Gate 通过率和安全性的前提下，把 lane 执行提示词收敛为最小充分上下文。
- 强制策略：所有泳道提示词统一改为三段式：
  - `Stable Core`（固定）
  - `Task Delta`（仅增量）
  - `Context Refs`（引用 ID，不贴全文）
- 硬边界：
  - 严禁在 prompt 里拼贴项目全量聊天历史。
  - 严禁跨项目原文泄漏（Supervisor 只能读脱敏聚合视图）。
  - 高风险授权、不可逆动作、契约变更仍优先服从安全门禁，不可为省 token 绕过。

## 1) 三段式提示词契约（Prompt Envelope v2）

### 1.1 machine-readable 合同

```json
{
  "prompt_envelope_version": "v2",
  "prompt_pack_id": "pp-uuid",
  "role": "lane_executor",
  "tri_prompt": {
    "stable_core_ref": "hub://prompt-core/xt-lane-executor.v2",
    "stable_core_sha256": "sha256-xxx",
    "task_delta_ref": "board://XT-W2-24-A",
    "task_delta_hash": "sha256-yyy",
    "context_refs": [
      {
        "ref_id": "mem://project/<project_id>/<memory_id>",
        "kind": "fact|decision|evidence|risk|rollback",
        "priority": "must|high|optional",
        "max_tokens": 120
      }
    ]
  },
  "token_policy": {
    "input_budget_tokens": 1400,
    "soft_cap_tokens": 1600,
    "hard_cap_tokens": 2200,
    "max_context_refs": 8,
    "expansion_policy": "one_shot_on_gate_fail"
  },
  "safety_policy": {
    "forbid_full_context_dump": true,
    "forbid_cross_project_raw_memory": true,
    "forbid_missing_evidence_for_key_claim": true
  }
}
```

### 1.2 三段式语义约束

- `Stable Core`：角色职责、禁止项、Gate 钩子、回滚策略；默认不随任务轮次变化。
- `Task Delta`：仅包含本轮变更（目标变化、依赖变化、验收变化、风险变化）。
- `Context Refs`：只传引用 ID 与预算，不拼贴全文；运行时按优先级和 token 预算解析。

### 1.3 fail-closed 规则

- 任一段缺失：阻断下发（`deny_code=prompt_tri_section_missing`）。
- `stable_core_sha256` 不匹配：阻断（`deny_code=stable_core_hash_mismatch`）。
- `context_refs` 解析后超出 `hard_cap_tokens`：先裁剪 optional，再裁剪 high；若 must 仍超限则阻断（`deny_code=context_budget_exceeded`）。

## 2) Context Capsule 选取策略（最小充分上下文）

### 2.1 检索分层

- `must`：DoD/Gate/风险红线/回滚点直接相关事实。
- `high`：最近一次失败根因、直接依赖产物、关键审计事件。
- `optional`：历史背景、经验卡、参考实现。

### 2.2 价值密度评分

- `value_density = gate_impact * freshness * confidence / token_cost`
- 装箱顺序：`must -> high -> optional`，同层按 `value_density` 降序。
- 去重规则：同 `lineage_hash` 仅保留最新且置信度更高条目。

### 2.3 重试策略

- 默认重试只发送 `Task Delta` + 上次失败差异，不重发大上下文。
- 仅允许一次 `one_shot_on_gate_fail` 上下文扩容；二次失败必须触发人工/总控裁决。

## 3) 实现子工单（可直接派发）

### 3.1 `XT-W2-24-A` 三段式编译器与契约冻结

- owner: `XT-L1`（Primary）+ `XT-L2`
- 目标：将三段式合同固化到 PromptPack 编译链路，成为默认下发格式。
- 代码落点：
  - `x-terminal/Sources/Supervisor/PromptFactory.swift`
  - `x-terminal/Sources/Supervisor/SupervisorManager.swift`
  - `x-terminal/Sources/Supervisor/TaskDecomposition/Task.swift`（必要时补 metadata）
- 步骤：
  1. 定义 `PromptEnvelopeV2` 与 schema 校验器。
  2. 落地 `StableCoreRegistry`（版本 + hash + rollback pointer）。
  3. 新增 `TaskDeltaBuilder`（从 command board/state 生成 delta）。
  4. Lint 强制三段齐全，不合规阻断发包。
  5. 产出证据：`build/reports/xt_w2_24_a_tri_prompt_compiler_evidence.v1.json`。
- DoD：
  - `tri_prompt_coverage = 100%`。
  - 所有 lane prompt 均可生成 `stable_core_ref + task_delta + context_refs`。
- Gate/KPI：
  - Gate: `XT-MP-G2`
  - KPI: `tri_prompt_coverage = 100%`, `prompt_contract_lint_block_rate > 0`（非法输入可拦截）
- 回归：
  - 缺少 `task_delta` 仍下发 -> 失败。
  - `stable_core_hash` 不匹配未阻断 -> 失败。

### 3.2 `XT-W2-24-B` Context Capsule 预算器与装箱器

- owner: `XT-L2`（Primary）+ `Hub-L5`
- 目标：按 token 预算做“最小充分上下文”装箱，而非全文拼贴。
- 代码落点：
  - `x-terminal/Sources/Supervisor/SupervisorOrchestrator.swift`
  - `x-terminal/Sources/Supervisor/TaskDecomposition/ExecutionMonitor.swift`
  - `x-hub/python-runtime/python_service/relflowhub_mlx_runtime.py`（只加 contract hook，不改安全红线）
- 步骤：
  1. 落地 `ContextCapsuleSelector`（must/high/optional + value_density）。
  2. 统一预算配置（按 role 分级：executor/verifier/integrator）。
  3. 支持 `soft_cap/hard_cap` 双阈值与超预算裁剪。
  4. 增加 one-shot 扩容策略（仅 Gate fail 可触发一次）。
  5. 产出证据：`build/reports/xt_w2_24_b_context_capsule_evidence.v1.json`。
- DoD：
  - 上下文装箱结果可解释（为何入选/被裁剪）。
  - 超预算不崩溃、不静默截断关键 must 项。
- Gate/KPI：
  - Gate: `XT-MP-G2`, `XT-MP-G3`
  - KPI: `prompt_token_waste_ratio <= 0.12`, `context_budget_overrun_incidents = 0`
- 回归：
  - optional 挤掉 must 项 -> 失败。
  - 超 `hard_cap` 仍发送 -> 失败。

### 3.3 `XT-W2-24-C` Context Refs 解析器与权限红线

- owner: `Hub-L3`（Primary）+ `XT-L2`
- 目标：保证“项目 AI 只读本项目，Supervisor 跨项目仅可读脱敏聚合视图”。
- 代码落点：
  - `x-hub/grpc-server/hub_grpc_server/src/services.js`
  - `x-hub/grpc-server/hub_grpc_server/src/skills_store.js`（仅审计字段复用，不改既有 fail-closed）
  - `x-terminal/Sources/Supervisor/SupervisorManager.swift`
- 步骤：
  1. 实现 `ContextRefResolver`（按 `ref_id` 获取最小片段 + 元数据）。
  2. 增加 ACL：`project_scope`、`supervisor_portfolio_scope`、`redacted_global_scope`。
  3. 增加脱敏规则（账号、支付、授权密钥一律不可出现在 prompt body）。
  4. 审计扩展字段：`context_ref_count`、`cross_project_redaction_applied`。
  5. 产出证据：`build/reports/xt_w2_24_c_context_acl_evidence.v1.json`。
- DoD：
  - `cross_project_raw_memory_leak = 0`。
  - 所有解析结果可追溯到 `ref_id` 和 `audit_ref`。
- Gate/KPI：
  - Gate: `XT-MP-G3`
  - KPI: `cross_project_raw_memory_leak = 0`, `context_ref_resolve_success_rate >= 99%`
- 回归：
  - 项目 AI 读取到他项目原文记忆 -> 失败。
  - 缺 `audit_ref` 仍放行 -> 失败。

### 3.4 `XT-W2-24-D` 重试增量压缩器（Delta Retry）

- owner: `XT-L2`（Primary）+ `XT-L1`
- 目标：失败重试时只传差异，不重复燃烧 token。
- 代码落点：
  - `x-terminal/Sources/Supervisor/TaskDecomposition/ExecutionMonitor.swift`
  - `x-terminal/Sources/Supervisor/PromptFactory.swift`
- 步骤：
  1. 记录每轮 prompt 指纹与失败类型。
  2. 生成 `RetryDelta`（上次失败原因 + 本轮修复点 + 必要 refs）。
  3. 接入 one-shot 扩容，二次失败触发 `notify_user|replan`。
  4. 输出机读证据：`build/reports/xt_w2_24_d_retry_delta_evidence.v1.json`。
- DoD：
  - 重试 input token 显著低于首轮（同类任务）。
  - 二次失败不会无限扩容。
- Gate/KPI：
  - Gate: `XT-MP-G3`, `XT-MP-G4`
  - KPI: `rework_token_ratio <= 0.25`, `second_retry_unbounded_expansion = 0`
- 回归：
  - 重试仍发送全量上下文 -> 失败。
  - Gate fail 后无限增大 prompt -> 失败。

### 3.5 `XT-W2-24-E` Token-质量联合看板与发布证据

- owner: `QA`（Primary）+ `XT-L2` + `Hub-L5`
- 目标：把“省 token 是否伤质量”变成可机判事实。
- 代码落点：
  - `scripts/m3_check_internal_pass_lines.js`
  - `scripts/m3_check_xt_ready_gate.js`
  - `x-terminal/work-orders/xt-supervisor-multipool-lane-execution-pack-v1.md`（仅证据引用区）
- 步骤：
  1. 统一采集 token/质量联合指标（lane/pool/global 三层）。
  2. 输出 `DeliveryEconomicsSnapshot` 并入 7 件套。
  3. 样本不足时标记 `INSUFFICIENT_EVIDENCE`，禁止冒绿。
  4. 产出证据：`build/reports/xt_w2_24_e_token_quality_evidence.v1.json`。
- DoD：
  - 每次交付均含 token-质量联合快照。
  - 指标可回放，可追溯到实际任务和证据文件。
- Gate/KPI：
  - Gate: `XT-MP-G4`, `XT-MP-G5`
  - KPI: `first_pass_gate_pass_rate >= 0.85`, `false_green_due_to_context_missing = 0`
- 回归：
  - 样本不足仍输出 GO -> 失败。
  - 仅有 token 优化无质量指标 -> 失败。

### 3.6 `XT-W2-24-F` 会话滚动与上下文胶囊治理器（Session Rollover）

- owner: `XT-L1`（Primary）+ `XT-L2` + `Hub-L3`
- 目标：在复杂任务中强制会话滚动，防止上下文无限增大。
- 代码落点：
  - `x-terminal/Sources/Supervisor/PromptFactory.swift`
  - `x-terminal/Sources/Supervisor/SupervisorManager.swift`
  - `x-hub/grpc-server/hub_grpc_server/src/services.js`
- 步骤：
  1. 增加 rollover 触发规则（`turn_count>=8` 或 `state_transition>=2`）。
  2. 实现会话压缩：旧会话写 checkpoint JSON（保留 DoD/Gate hooks/context refs）。
  3. 新会话仅加载三段式最小上下文（`refs<=3`）。
  4. 预算约束：`active<=450 tokens`, `standby<=120 tokens`。
  5. 产出证据：`build/reports/xt_w2_24_f_session_rollover_evidence.v1.json`。
- DoD：
  - 会话滚动可恢复语义连续性且可追溯。
  - 无增量时只允许 `delta_3line`，禁止 full 长报。
- Gate/KPI：
  - Gate: `XT-MP-G2`, `XT-MP-G3`, `XT-MP-G5`
  - KPI: `full_history_prompt_usage = 0`, `rollover_recovery_success_rate >= 0.99`, `prompt_token_waste_ratio <= 0.12`
- 回归：
  - 达阈值未 rollover -> 失败。
  - rollover 后丢失 Gate hooks -> 失败。
  - standby 报文超预算 -> 失败。

## 4) 测试计划（实现级）

### 4.1 单测

- `swift test --filter PromptEnvelopeV2Tests`
- `swift test --filter ContextCapsuleSelectorTests`
- `swift test --filter ContextRefACLTests`
- `swift test --filter RetryDeltaCompressorTests`
- `swift test --filter SessionRolloverPolicyTests`

### 4.2 集成

- `swift test --filter SupervisorDoctorTests`
- `swift test --filter HighRiskGrantGateTests`
- `swift test --filter SupervisorIncidentExportTests`

### 4.3 最小回归集

1. 三段式完整性：
   - 缺任一段必须阻断。
2. 预算裁剪：
   - must 项不得被 optional 挤出。
3. 权限隔离：
   - 项目 AI 不得读到跨项目原文记忆。
4. 重试压缩：
   - 二次重试不得无限扩容。
5. 质量守恒：
   - token 降低时 Gate 通过率不可显著下降。

## 5) 发布条件（Token 优化必须同时保质）

- `tri_prompt_coverage = 100%`
- `prompt_token_waste_ratio <= 0.12`
- `rework_token_ratio <= 0.25`
- `first_pass_gate_pass_rate >= 0.85`
- `cross_project_raw_memory_leak = 0`
- `false_green_due_to_context_missing = 0`
- `full_history_prompt_usage = 0`

## 6) 回滚点与开关

- feature flags:
  - `XT_PROMPT_TRI_SECTION_V2`
  - `XT_CONTEXT_CAPSULE_SELECTOR_V1`
  - `XT_CONTEXT_REFS_ACL_V1`
  - `XT_RETRY_DELTA_COMPRESSOR_V1`
  - `XT_TOKEN_QUALITY_SNAPSHOT_V1`
  - `XT_SESSION_ROLLOVER_V1`
- rollback:
  - 任一泄漏或 Gate 大幅退化，立即关闭 `XT_CONTEXT_REFS_ACL_V1` 与 `XT_CONTEXT_CAPSULE_SELECTOR_V1`，回退到 `critical_touch + strict_prompt_pack_v1`。
  - 任一 contract 异常，回退 `XT_PROMPT_TRI_SECTION_V2` 到旧版 PromptPack（保留审计）。

## 7) 泳道 AI 派发模板（可直接复制）

```text
任务：<XT-W2-24-A | XT-W2-24-B | XT-W2-24-C | XT-W2-24-D | XT-W2-24-E>
读序：
1) docs/memory-new/xhub-lane-command-board-v2.md
2) x-terminal/work-orders/xt-supervisor-multipool-lane-execution-pack-v1.md
3) x-terminal/work-orders/xt-w2-24-token-optimal-context-capsule-implementation-pack-v1.md

执行规则：
- 先 claim_id + claim_ttl_until（4h）
- 提示词必须三段式：Stable Core + Task Delta + Context Refs
- Context Refs 仅引用 ID，不贴全文
- delivered 必交 7件套（含 Gate 证据路径 + KPI 报告路径）
- 依赖不满足时 fail-closed 落盘 blocked_reason + unblock_owner
```
