# XT-W3-21 / XT-W3-22 Supervisor 接案与验收实现子工单包

- version: v1.0
- updatedAt: 2026-03-06
- owner: XT-L2（Primary）/ Hub-L5 / XT-L1 / QA / AI-COORD-PRIMARY
- status: active
- scope: `XT-W3-21`（Project Intake Manifest）+ `XT-W3-22`（Acceptance Pack）+ `XT-W3-21-A/B/C` + `XT-W3-22-A/B/C`
- parent:
  - `x-terminal/work-orders/xt-supervisor-multipool-adaptive-work-orders-v1.md`
  - `x-terminal/work-orders/xt-supervisor-multipool-lane-execution-pack-v1.md`
  - `x-terminal/work-orders/xt-w2-24-token-optimal-context-capsule-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w2-27-anti-block-unblock-orchestration-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w2-28-jamless-anti-congestion-protocol-implementation-pack-v1.md`
  - `docs/memory-new/xhub-lane-command-board-v2.md`
  - `docs/memory-new/xhub-hub-to-xterminal-capability-gate-v1.md`

## 0) 目标与边界

- 目标：让 Supervisor 接到一组项目 `md/spec/work-order` 文件后，先生成可机判的 `Project Intake Manifest`，再据此自动拆分 `pool -> lane -> AI`。
- 目标：把“接案能不能开工”与“最终能不能宣告交付”都变成 machine-readable 契约，而不是靠人工口头判断。
- 目标：让用户可以选择 `zero_touch / critical_touch / guided_touch` 介入等级，但即使 `zero_touch` 也必须保留高风险授权与回滚边界。
- 目标：最终交付时输出 `Acceptance Pack`，统一收敛结果、风险、证据、回滚点、后续建议。
- 硬边界：
  - Intake 信息不完整且影响授权/范围/验收时，必须 `fail-closed`，不得擅自开工。
  - Acceptance 证据不完整时，禁止输出“完成/closed”。
  - `Context Refs` 只传引用，不贴原文全文；原始文档应沉淀在 Hub/Board 可引用层。

## 1) 机读契约

### 1.1 Project Intake Manifest

```json
{
  "schema_version": "xt.project_intake_manifest.v1",
  "project_id": "uuid",
  "source_bundle_refs": [
    "docs/spec-a.md",
    "docs/spec-b.md"
  ],
  "project_goal": "string",
  "in_scope": ["string"],
  "out_of_scope": ["string"],
  "constraints": ["security", "timeline", "compat"],
  "touch_policy": "zero_touch|critical_touch|guided_touch",
  "innovation_level": "L0|L1|L2|L3|L4",
  "suggestion_governance": "supervisor_only|hybrid|lane_open",
  "risk_level": "low|medium|high",
  "requires_user_authorization": true,
  "acceptance_mode": "internal_beta|release_candidate|production",
  "budget_policy": {
    "token_budget_tier": "tight|balanced|aggressive",
    "paid_ai_allowed": true
  },
  "pool_plan": [
    {
      "pool_id": "hub",
      "pool_goal": "string",
      "recommended_lane_count": 1,
      "lane_split_reason": "string"
    }
  ],
  "acceptance_targets": [
    "gate_green",
    "rollback_ready",
    "evidence_complete"
  ],
  "audit_ref": "audit-xxxx"
}
```

### 1.2 Acceptance Pack

```json
{
  "schema_version": "xt.acceptance_pack.v1",
  "project_id": "uuid",
  "delivery_status": "candidate|accepted|rejected|insufficient_evidence",
  "completed_tasks": ["XT-W2-28", "XT-W3-18"],
  "gate_vector": "XT-MP-G4:PASS,XT-MP-G5:PASS",
  "risk_summary": [
    {
      "risk_id": "risk-1",
      "severity": "medium",
      "mitigation": "string"
    }
  ],
  "rollback_points": [
    {
      "component": "supervisor-orchestrator",
      "rollback_ref": "board://rollback/point-1"
    }
  ],
  "evidence_refs": [
    "build/reports/xt_w3_18_integration_evidence.v1.json"
  ],
  "user_summary_ref": "board://delivery/summary/20260306-001",
  "audit_ref": "audit-xxxx"
}
```

### 1.3 Intake Freeze Gate

```json
{
  "schema_version": "xt.intake_freeze_gate.v1",
  "project_id": "uuid",
  "intake_manifest_ref": "build/reports/xt_w3_21_project_intake_manifest.v1.json",
  "required_fields_complete": true,
  "scope_conflict_detected": false,
  "authorization_boundary_clear": true,
  "decision": "pass|fail_closed",
  "deny_code": "none|intake_missing_required_field|scope_conflict|authorization_boundary_unclear"
}
```

## 2) 状态机

`received -> normalized -> intake_frozen -> pool_plan_generated -> lane_plan_generated -> execution_active -> acceptance_collecting -> accepted`

异常分支：

- `normalized -> fail_closed_needs_user_decision`
- `execution_active -> acceptance_collecting -> insufficient_evidence`
- `acceptance_collecting -> rollback_required`

## 3) 子工单分解

### 3.1 `XT-W3-21-A` Intake Extractor

- 目标：从一组 `md/spec/work-order` 文档提取目标、范围、约束、验收条件、授权边界。
- 交付物：`build/reports/xt_w3_21_a_intake_extractor_evidence.v1.json`

### 3.2 `XT-W3-21-B` Intake Freeze + Conflict Arbiter

- 目标：冻结 Intake Manifest，并对冲突范围、缺失字段、授权边界不清做 fail-closed 裁决。
- 交付物：`build/reports/xt_w3_21_b_intake_freeze_evidence.v1.json`

### 3.3 `XT-W3-21-C` Pool/Lane Bootstrap Binder

- 目标：把 Intake Manifest 绑定到 `pool_plan + lane_plan + prompt_pack_refs + touch_policy`。
- 交付物：`build/reports/xt_w3_21_c_bootstrap_binding_evidence.v1.json`

### 3.4 `XT-W3-22-A` Acceptance Evidence Aggregator

- 目标：自动聚合 Gate/KPI/风险/回滚/证据，生成可机读 Acceptance Pack 草案。
- 交付物：`build/reports/xt_w3_22_a_acceptance_aggregator_evidence.v1.json`

### 3.5 `XT-W3-22-B` Rollback + Link Completeness Validator

- 目标：校验回滚点、证据引用、用户摘要引用是否完整，不完整则 fail-closed。
- 交付物：`build/reports/xt_w3_22_b_acceptance_validation_evidence.v1.json`

### 3.6 `XT-W3-22-C` Delivery Package Emitter

- 目标：输出用户可读交付摘要与机读 Acceptance Pack，并记录通知审计。
- 交付物：`build/reports/xt_w3_22_c_delivery_package_evidence.v1.json`

## 4) 任务级执行包

### 4.1 `XT-W3-21` Project Intake Manifest

- 目标：让 Supervisor 能把项目文档包转换为可执行 intake 决策，而不是直接把原文长贴给各 lane。
- 代码落点：
  - `x-terminal/Sources/Supervisor/SupervisorManager.swift`
  - `x-terminal/Sources/Supervisor/SupervisorOrchestrator.swift`
  - `x-terminal/Sources/Supervisor/PromptFactory.swift`
  - `x-terminal/Sources/Supervisor/TaskDecomposition/ExecutionMonitor.swift`
- DoR：
  - `XT-W2-20/21/22/23/24/25` 已可提供 pool/lane/touch/prompt 基础能力。
  - Command Board 支持 `Context Refs` 与 `CR/Decision` 引用。
- 实施子步骤：
  1. 落地 `ProjectIntakeExtractor`，从项目 `md` 文件抽取 `goal/in_scope/out_of_scope/constraints/acceptance_targets`。
  2. 落地 `IntakeConflictArbiter`，对冲突字段执行 `fail_closed`。
  3. 落地 `ProjectIntakeManifestBuilder`，输出 `xt.project_intake_manifest.v1`。
  4. 落地 `IntakeFreezeGate`，开工前强制校验必要字段、授权边界、验收模式。
  5. 将 `pool_plan + lane_plan + prompt_pack_refs + touch_policy` 回填为启动包。
  6. 产出机读证据：`build/reports/xt_w3_21_project_intake_manifest.v1.json`。
- DoD：
  - 给 Supervisor 一组 `md` 文档后，可稳定生成 machine-readable intake manifest。
  - Intake 不完整时，不会直接开工，而是 `fail_closed` 或请求最小必要用户裁决。
  - Intake 结果可直接驱动 `pool -> lane -> AI` 启动，不再依赖人工二次整理。
- Gate/KPI：
  - Gate: `XT-MP-G0`, `XT-MP-G1`, `XT-MP-G3`
  - KPI: `intake_required_field_coverage = 100%`, `intake_to_pool_plan_p95_ms <= 3000`, `post_start_replan_due_to_intake_ambiguity_rate <= 0.10`
- 回归样例：
  - 缺 `in_scope/out_of_scope` 仍开工 -> 失败。
  - 高风险授权边界不清却自动进入执行 -> 失败。
  - Intake manifest 与 lane_plan 脱节 -> 失败。

### 4.2 `XT-W3-22` Acceptance Pack

- 目标：让 Supervisor 在任务完成后自动输出“是否可以交付”的正式裁决包，而不是只说“做完了”。
- 代码落点：
  - `x-terminal/Sources/Supervisor/SupervisorManager.swift`
  - `x-terminal/Sources/Supervisor/PromptFactory.swift`
  - `x-terminal/Sources/Event/AXEventBus.swift`
  - `x-terminal/Sources/Supervisor/TaskDecomposition/ExecutionMonitor.swift`
- DoR：
  - `XT-W3-18` 集成测试输出可用。
  - `XT-W3-19` 通知摘要链路可用。
  - Command Board 可读取 `gate_vector/evidence_refs/rollback`。
- 实施子步骤：
  1. 落地 `AcceptanceEvidenceAggregator`，聚合 `completed_tasks/gate_vector/kpi/risks/rollback_points/evidence_refs`。
  2. 落地 `AcceptanceLinkValidator`，校验证据引用与回滚点完整性。
  3. 落地 `AcceptanceDecisionCompiler`，输出 `candidate|accepted|rejected|insufficient_evidence`。
  4. 落地 `DeliveryPackageEmitter`，生成用户摘要与机读 Acceptance Pack。
  5. 将 Acceptance Pack 与通知审计回填 Command Board evidence refs。
  6. 产出机读证据：`build/reports/xt_w3_22_acceptance_pack.v1.json`。
- DoD：
  - 任一关键证据或回滚点缺失时，不会误发“已完成”。
  - 用户可一眼看到 `结果 + 风险 + 证据 + 回滚点 + 下一步建议`。
  - Acceptance 结果可被机器再次校验，支持复盘与回放。
- Gate/KPI：
  - Gate: `XT-MP-G5`
  - KPI: `acceptance_evidence_link_completeness = 100%`, `completion_without_rollback_ref = 0`, `acceptance_compile_latency_p95_ms <= 1500`
- 回归样例：
  - 缺 evidence 仍输出 accepted -> 失败。
  - rollback_ref 缺失仍输出 delivery -> 失败。
  - 用户摘要与机读 Acceptance Pack 结论不一致 -> 失败。

## 5) 接案输入规范（给 Supervisor 的最小输入）

- 最小输入包：`目标说明 + 范围说明 + 约束/红线 + 关键工单/规格文件 refs + 用户介入等级 + 验收模式`。
- 推荐输入格式：`Stable Intake Header + Source Bundle Refs + Acceptance Targets`。
- 文档很多时，不贴全文，只给 `Context Refs`；Supervisor 负责先生成 `Project Intake Manifest`，再给 lane 下发 `Task Delta`。

## 6) 与现有主链的接线方式

- 开工前：`XT-W3-21` 先于 `XT-W2-20` 逻辑执行，但可作为跨阶段能力独立开发。
- 执行中：`XT-W3-21` 输出的 manifest 作为 `XT-W2-20..XT-W2-28` 的统一输入层。
- 收口时：`XT-W3-22` 消费 `XT-W3-18/19/20` 与各主任务 evidence，输出最终交付包。

## 7) 7件套要求

- `XT-W3-21` 与 `XT-W3-22` 的交付同样必须遵守 `Scope / Changes / DoD / Gate / KPI Snapshot / Risks & Rollback / Handoff` 七件套。
- 证据默认落盘到 `build/reports/`，并在 Command Board 仅追加本任务 evidence refs，不跨泳道改写他人状态。
