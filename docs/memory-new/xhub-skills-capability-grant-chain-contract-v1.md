# X-Hub Hub-L3 Skills Capability -> Grant 主链收口契约（v1）

- version: v1.0
- updatedAt: 2026-03-01
- owner: Hub-L3
- scope: SKC-W1-04 / SKC-W2-05 / SKC-W2-06（policy + grant + audit only）
- machine-readable contract: `docs/memory-new/schema/xhub_skills_capability_grant_chain_contract.v1.json`

## 0) 目标与边界

目标：把 skills 的 `capabilities_required` 请求统一收敛到 Hub grant 主链，保证 deny_code、audit、审批绑定语义稳定且可机判。

边界：
- 不改签名算法。
- 不改 UI 样式。
- 默认 fail-closed，禁止“低风险伪装”绕过 grant。

统一执行链：`ingress -> risk classify -> policy -> grant -> execute -> audit`

## 1) Output-A：`capabilities_required` -> `required_grant_scope` 映射表

下表为 Hub-L3 冻结映射；若调用侧传入 scope 低于 floor，按 `request_tampered` 处理并拒绝执行。

| capability (canonical) | aliases (examples) | required_grant_scope | risk_tier_floor | grant_required |
| --- | --- | --- | --- | --- |
| `ai.generate.local` | `CAPABILITY_AI_GENERATE_LOCAL` | `readonly` | `low` | `false` |
| `ai.generate.paid` | `CAPABILITY_AI_GENERATE_PAID` | `privileged` | `high` | `true` |
| `web.fetch` | `CAPABILITY_WEB_FETCH`, `web_fetch` | `privileged` | `high` | `true` |
| `terminal.exec` | `terminal.exec.write`, `shell.exec` | `privileged` | `high` | `true` |
| `filesystem.read` | `fs.read`, `file.read` | `readonly` | `medium` | `false` |
| `filesystem.write` | `fs.write`, `file.write` | `privileged` | `high` | `true` |
| `filesystem.delete` | `fs.delete`, `file.delete` | `critical` | `critical` | `true` |
| `memory.longterm.writeback` | `memory.write` | `privileged` | `high` | `true` |
| `connector.webhook.send` | `connector.send` | `privileged` | `high` | `true` |
| `payment.intent.confirm` | `payment.execute` | `critical` | `critical` | `true` |

补充规则：
- unknown capability：`fail_closed`，`deny_code=policy_denied`。
- scope drift / replay drift：`deny_code=request_tampered`。

## 2) Output-B：`grant_pending / awaiting_instruction / runtime_error` 事件语义与审计模板

### 2.1 事件语义（冻结）

| incident_code | hub_event_type | supervisor_event_type | deny_code | 语义 |
| --- | --- | --- | --- | --- |
| `grant_pending` | `grant.pending` | `supervisor.incident.grant_pending.handled` | `grant_pending` | 需授权，未放行 |
| `awaiting_instruction` | `grant.denied` | `supervisor.incident.awaiting_instruction.handled` | `awaiting_instruction` | 用户/策略明确拒绝或要求进一步指示 |
| `runtime_error` | `agent.tool.executed` (`ok=false`) | `supervisor.incident.runtime_error.handled` | `runtime_error` | grant 链路运行异常，默认 fail-closed |

### 2.2 审计模板（最小字段）

```json
{
  "event_type": "grant.pending",
  "request_id": "req_...",
  "session_id": "sess_...",
  "error_code": null,
  "ext_json": {
    "op": "agent_tool_request",
    "incident_code": "grant_pending",
    "deny_code": "grant_pending",
    "chain": "ingress->risk_classify->policy->grant->execute->audit"
  }
}
```

```json
{
  "event_type": "grant.denied",
  "request_id": "req_...",
  "session_id": "sess_...",
  "error_code": "awaiting_instruction",
  "ext_json": {
    "op": "agent_tool_grant_decision",
    "incident_code": "awaiting_instruction",
    "deny_code": "awaiting_instruction",
    "chain": "ingress->risk_classify->policy->grant->execute->audit"
  }
}
```

```json
{
  "event_type": "agent.tool.executed",
  "request_id": "req_...",
  "session_id": "sess_...",
  "error_code": "runtime_error",
  "ext_json": {
    "op": "agent_tool_execute",
    "incident_code": "runtime_error",
    "deny_code": "runtime_error",
    "chain": "ingress->risk_classify->policy->grant->execute->audit"
  }
}
```

## 3) Output-C：Skill 执行前能力预检与审批绑定校验标准

### 3.1 预检顺序（必须按序）

1. 解析 `capabilities_required`。
2. 计算 `required_grant_scope` floor（取映射最高级）。
3. 应用 risk floor guard（禁止调用方风险下调绕过）。
4. 校验审批绑定输入（`exec_argv` + `exec_cwd`）。
5. 持久化审批绑定（identity hash 绑定 canonical session project scope）。
6. 执行 policy。
7. 进入 grant 决策。

### 3.2 审批绑定拒绝码（冻结）

- `approval_binding_invalid`：`exec_argv` 非字符串或污染。
- `approval_cwd_invalid`：`exec_cwd` 非绝对路径或非 canonical realpath。
- `approval_argv_mismatch`：执行参数与审批参数不一致。
- `approval_cwd_mismatch`：执行 cwd 与审批 cwd 不一致。
- `approval_identity_mismatch`：identity hash 漂移。
- `approval_binding_missing` / `approval_binding_corrupt`：审批绑定缺失或存储损坏。

### 3.3 grant fail-closed 拒绝码（冻结）

- `grant_missing`
- `grant_expired`
- `request_tampered`
- `policy_denied`

## 4) DoD / Gate / KPI

DoD 指标（Hub-L3）：
- `high_risk_lane_without_grant = 0`
- `approval_mismatch_execution = 0`
- grant deny_code 与审计字段 machine-readable

Gate / KPI：
- Gate: `SKC-G2`, `SKC-G4`
- `bypass_grant_execution = 0`
- `low_risk_false_block_rate < 3%`

## 5) Machine-check 命令

```bash
# 校验 Hub-L3 合同 JSON 完整性（映射/事件模板/预检标准）
node ./scripts/m3_check_skills_grant_chain_contract.js \
  --out-json ./build/hubl3_skills_grant_chain_contract_report.json

# 回归：grant 缺失/过期/漂移 + 审批绑定 + runtime_error
node ./x-hub/grpc-server/hub_grpc_server/src/memory_agent_grant_chain.test.js
```

## 6) 回滚点

- `RB-HUBL3-001`：回滚 `docs/memory-new/schema/xhub_skills_capability_grant_chain_contract.v1.json` 到上一个 `contract_version`。
- `RB-HUBL3-002`：`protocol/hub_protocol_v1.md` 与 deny_code 词典按同一版本原子回滚，禁止只回滚一半。
