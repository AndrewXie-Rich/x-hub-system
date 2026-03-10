# XT-W2-09 + XT-W2-11：Split Proposal / Confirm / Override + Prompt Contract Lint

- workOrder: `XT-W2-09`, `XT-W2-11`
- priority: `P0`
- gate: `XT-SUP-G0`, `XT-SUP-G1`, `XT-Ready-G0`, `XT-Ready-G2`
- status: `in_progress`
- owner: `Lane-D (Supervisor/UX)`
- updatedAt: `2026-03-01`

## 1) 目标与边界

目标：把 Supervisor 拆分流程做成“可提案、可确认、可覆盖、可阻断”的稳定控制面，并提供 AI-XT-2 可直接消费的机读契约（状态机 + 审计 + 快照 + fixture）。

本轮边界（代码落点）：

- `Sources/Supervisor/TaskDecomposition/Task.swift`
- `Sources/Supervisor/SplitProposalEngine.swift`
- `Sources/Supervisor/PromptContract.swift`
- `Sources/Supervisor/PromptFactory.swift`
- `Sources/Supervisor/SplitFlowSnapshotContract.swift`
- `Sources/Supervisor/SplitAuditPayloadContract.swift`
- `Sources/Supervisor/SupervisorOrchestrator.swift`
- `Sources/Supervisor/SupervisorView.swift`
- `Sources/XTerminalApp.swift`
- `scripts/check_split_flow_contract.js`
- `scripts/check_split_flow_snapshot_fixture_contract.js`
- `scripts/check_split_flow_snapshot_generation_regression.js`
- `scripts/generate_split_flow_snapshot_fixture.js`
- `scripts/ci/xt_release_gate.sh`

## 2) Split Proposal 状态机契约（AI-XT-2 对齐口径）

- 状态机版本：`xterminal.split_flow_state_machine.v1`
- 状态集合：`idle -> proposing -> proposed -> overridden/confirmed/rejected/blocked`
- 关键转移：
  - `idle -> proposing`
  - `proposing -> proposed | blocked`
  - `proposed -> overridden | confirmed | rejected | blocked | idle`
  - `overridden -> overridden | proposed | confirmed | rejected | blocked | idle`
  - `confirmed -> idle`
  - `rejected -> idle`
  - `blocked -> blocked | proposed | overridden | confirmed | rejected | idle`
- 合约检查脚本：`node ./scripts/check_split_flow_contract.js`

说明：`blocked` 允许回到 `proposed/overridden/confirmed`，用于“先阻断再修复再确认”的可恢复流程；AI-XT-2 侧不要把 `blocked` 当成终态。

## 3) Confirm / Reject / Override 行为语义

- `proposeSplit(...)`
  - 生成 `SplitProposal`（含 DAG lane 依赖、风险、预算、DoD）
  - 写审计：`supervisor.split.proposed`
- `confirmActiveSplitProposal(...)`
  - 先验证 split proposal，再编译 Prompt Contract 并 lint
  - lint 有阻断项 -> `supervisor.prompt.rejected` + 状态 `blocked`
  - lint 通过 -> `supervisor.prompt.compiled` + `supervisor.split.confirmed` + 状态 `confirmed`
- `rejectActiveSplitProposal(...)`
  - 写审计：`supervisor.split.rejected` + 状态 `rejected`
- `overrideActiveSplitProposal(...)`
  - 支持 lane 级覆盖：`createChildProject/risk/budget/dod/note`
  - 高风险 `hard -> soft` 需要显式确认标记 `confirmHighRiskHardToSoft=true`
  - 写审计：`supervisor.split.overridden`（含覆盖数量、阻断码、replay 信息）

## 4) Prompt Contract + Lint 阻断项

PromptContract 字段（每条 lane 必备）：

- `goal`
- `boundaries`
- `inputs`
- `outputs`
- `dodChecklist`
- `riskBoundaries`
- `prohibitions`
- `rollbackPoints`
- `refusalSemantics`
- `compiledPrompt`
- `tokenBudget`

Lint 阻断项（error）：

- `missing_goal`
- `missing_dod`
- `missing_risk_boundary`
- `missing_prohibitions`
- `missing_refusal_semantics`
- `missing_rollback_points`
- `prompt_coverage_gap`
- `high_risk_missing_grant_boundary`

## 5) AI-XT-2 消费接口（字段/状态机）

### 5.1 当前态快照（建议主入口）

- API：`SupervisorOrchestrator.splitFlowSnapshot()`
- schema：`xterminal.split_flow_snapshot`
- version：`1`
- state machine version：`xterminal.split_flow_state_machine.v1`

关键字段：

- `flowState`: 当前流程状态（按状态机解释）
- `splitPlanId`: 当前提案 ID
- `laneCount/recommendedConcurrency/tokenBudgetTotal`
- `splitBlockingIssueCodes`
- `promptStatus/promptCoverage/promptBlockingLintCodes`
- `overrideCount/overrideLaneIDs/replayConsistent`
- `lastAuditEventType/lastAuditAt`

### 5.2 审计解码（建议故障排查入口）

- API：
  - `latestDecodedSplitAuditResult() -> Result<SplitAuditDecodedPayload, SplitAuditPayloadDecodeError>?`
  - `latestDecodedSplitAuditPayload() -> SplitAuditDecodedPayload?`（兼容）
- 错误类型：
  - `schemaMismatch`
  - `versionMismatch`
  - `eventTypeMismatch`
  - `missingField`
  - `invalidFieldValue`

建议：AI-XT-2 自动化链路默认按 `decodeResult` fail-closed，避免静默吞掉字段漂移。

## 6) Runtime Fixture 与回归流水线

### 6.1 运行时生成（真实 orchestrator）

CLI：

```bash
swift run XTerminal --xt-split-flow-fixture-smoke --project-root . --out-json ./.axcoder/reports/split_flow_snapshot.runtime.json
```

输出包含 4 个基线案例：

- `proposed_clean`
- `overridden_with_replay`
- `blocked_by_prompt_lint`
- `confirmed_ready`

### 6.2 脚本化生成与回归

```bash
node ./scripts/generate_split_flow_snapshot_fixture.js --out-json ./.axcoder/reports/split_flow_snapshot.runtime.json
node ./scripts/check_split_flow_snapshot_fixture_contract.js --fixture ./.axcoder/reports/split_flow_snapshot.runtime.json
node ./scripts/check_split_flow_snapshot_generation_regression.js --generated ./.axcoder/reports/split_flow_snapshot.runtime.json --sample ./scripts/fixtures/split_flow_snapshot.sample.json
```

### 6.3 一键刷新（推荐）

```bash
bash ./scripts/ci/xt_split_flow_fixture_refresh.sh --run-gate-baseline
bash ./scripts/ci/xt_split_flow_fixture_refresh.sh --run-gate-strict
```

可选参数：

- `--copy-to-sample`: 用 runtime fixture 规范化后覆盖 sample
- `--skip-build`: 跳过 `swift build`
- `--xterminal-bin <path>`: 使用预编译 XTerminal 二进制

## 7) Gate 开关与证据字段（AI-XT-2 联调重点）

`scripts/ci/xt_release_gate.sh` 支持：

- `XT_GATE_SPLIT_FLOW_RUNTIME_REGRESSION=1`
- `XT_GATE_SPLIT_FLOW_GENERATE_RUNTIME_FIXTURE=1|0`
- `XT_SPLIT_FLOW_RUNTIME_FIXTURE=<path>`
- `XT_GATE_VALIDATE_SPLIT_FLOW_RUNTIME_POLICY=1`（可选：执行策略回归脚本）

默认策略（2026-03-01）：

- `XT_GATE_MODE=baseline`：runtime regression 默认关闭
- `XT_GATE_MODE=strict`：runtime regression 默认开启
- `XT_GATE_RELEASE_PRESET=1`：runtime regression 强制开启（关闭会 fail）
- `XT_GATE_RELEASE_PRESET=1`：`XT_GATE_VALIDATE_SPLIT_FLOW_RUNTIME_POLICY` 默认开启（除非显式设为 0）

策略回归脚本：

```bash
bash ./scripts/ci/xt_split_flow_runtime_policy_regression.sh
```

报告证据字段：

- `evidence.split_flow_contract_report`
- `evidence.split_flow_fixture_contract_report`
- `evidence.split_flow_fixture.snapshot_count`
- `evidence.split_flow_runtime_fixture`
- `evidence.split_flow_runtime_regression`
- `evidence.split_flow_runtime_policy_regression`
- `evidence.split_flow_runtime_policy_regression_log`

索引字段（`xt-report-index.json`）：

- `split_flow_contract_summary.snapshot_schema`
- `split_flow_contract_summary.snapshot_version`
- `split_flow_contract_summary.state_machine_version`
- `split_flow_fixture_summary.snapshot_count`
- `split_flow_runtime_regression.status`
- `split_flow_runtime_policy_regression.status`
