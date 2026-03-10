# X-Hub Memory v3 M3-W1-03 Contract Test 清单（按 deny_code 分组）

- version: v1.0
- updatedAt: 2026-02-28
- owner: Hub Memory / QA / Security / X-Terminal
- status: active
- scope: `M3-W1-03`（Project Lineage Contract + Dispatch Context）
- related:
  - `docs/memory-new/xhub-memory-v3-m3-lineage-contract-freeze-v1.md`
  - `docs/memory-new/xhub-memory-v3-m3-work-orders-v1.md`
  - `x-hub/grpc-server/hub_grpc_server/src/memory_project_lineage.test.js`
  - `scripts/m3_check_lineage_contract_tests.js`
  - `docs/memory-new/xhub-memory-v3-m3-lineage-collab-handoff-v1.md`
  - `.github/workflows/m2-memory-bench.yml`

## 1) 用途（给并行开发直接执行）

本清单用于把 `M3-W1-03` 的 contract gate 固化为“可直接执行”的测试门禁：
- 按 `deny_code` 分组列出必须覆盖的场景；
- 明确每个场景的期望 RPC 响应与审计行为；
- 作为并行开发（Hub / X-Terminal / QA）统一验收口径。

## 2) Gate 定义

- Gate 名称：`Gate-M3-0-CT`（Contract Test Gate，M3-W1-03 子门禁）
- 通过条件（必须全部满足）：
  1. 所有 `P0 deny_code` 分组用例通过；
  2. 每个 `deny_code` 至少 1 条 fail-closed 用例；
  3. 拒绝路径必须返回 machine-readable `deny_code`（不能只报自然语言）；
  4. 拒绝路径必须写审计事件 `project.lineage.rejected`，且 `error_code == deny_code`；
  5. 成功路径必须写审计事件 `project.lineage.upserted` 或 `project.dispatch.lineage_attached`；
  6. deny_code 分组与 `CT-*` 测试 ID 映射必须通过覆盖校验脚本（防文档/测试漂移）；
  7. deny 分组中的 `CT-*` 必须为 `*-Dxxx`，并在 test-source 中具备唯一 `CT-ID` 代码块，且代码块内同时断言响应 `deny_code` 与审计 `error_code`。
  8. test-source 不得出现未在本清单登记的 `deny_code` 或 `CT-*`（source -> contract 反向一致性）。
  9. freeze 字典 deny_code 行、contract deny_code 分组标题都必须唯一；每个 deny `CT-ID` 代码块仅允许 1 组响应 `deny_code` + 1 组审计 `error_code` 断言（禁止多重映射）。

## 3) 执行命令（本地/CI）

```bash
node ./x-hub/grpc-server/hub_grpc_server/src/memory_project_lineage.test.js
node ./scripts/m3_check_lineage_contract_tests.js
```

CI 已接入：
- `.github/workflows/m2-memory-bench.yml` 中步骤
  - `Run M3-W1-03 project lineage + dispatch fail-closed regression`
  - `Run Gate-M3-0-CT deny_code coverage checker`

## 4) Contract Test Matrix（按 deny_code 分组）

> 说明：`Test ID` 为长期稳定 ID；实现当前在 `memory_project_lineage.test.js` 中。

### 4.1 `lineage_parent_missing`

| Test ID | RPC | 输入摘要 | 期望响应 | 期望审计 |
|---|---|---|---|---|
| `CT-LIN-D001` | `UpsertProjectLineage` | child 引用不存在 parent | `accepted=false`, `deny_code=lineage_parent_missing` | `project.lineage.rejected` + `error_code=lineage_parent_missing` |

### 4.2 `lineage_cycle_detected`

| Test ID | RPC | 输入摘要 | 期望响应 | 期望审计 |
|---|---|---|---|---|
| `CT-LIN-D002` | `UpsertProjectLineage` | 回写导致 A->B->...->A 环路 | `accepted=false`, `deny_code=lineage_cycle_detected` | `project.lineage.rejected` + `error_code=lineage_cycle_detected` |

### 4.3 `lineage_root_mismatch`

| Test ID | RPC | 输入摘要 | 期望响应 | 期望审计 |
|---|---|---|---|---|
| `CT-LIN-D003` | `UpsertProjectLineage` | parent/root 不一致或跨 root 串联 | `accepted=false`, `deny_code=lineage_root_mismatch` | `project.lineage.rejected` + `error_code=lineage_root_mismatch` |
| `CT-DIS-D003` | `AttachDispatchContext` | dispatch.root 与 lineage.root 不一致 | `attached=false`, `deny_code=lineage_root_mismatch` | `project.lineage.rejected` + `error_code=lineage_root_mismatch` |

### 4.4 `parent_inactive`

| Test ID | RPC | 输入摘要 | 期望响应 | 期望审计 |
|---|---|---|---|---|
| `CT-LIN-D004` | `UpsertProjectLineage` | parent 已归档后继续新增 child | `accepted=false`, `deny_code=parent_inactive` | `project.lineage.rejected` + `error_code=parent_inactive` |

### 4.5 `invalid_request`

| Test ID | RPC | 输入摘要 | 期望响应 | 期望审计 |
|---|---|---|---|---|
| `CT-LIN-D005` | `UpsertProjectLineage` | 缺 `lineage.root_project_id/project_id` | `accepted=false`, `deny_code=invalid_request` | `project.lineage.rejected` + `error_code=invalid_request` |
| `CT-DIS-D005` | `AttachDispatchContext` | 缺 `dispatch.assigned_agent_profile` | `attached=false`, `deny_code=invalid_request` | `project.lineage.rejected` + `error_code=invalid_request` |

### 4.6 `permission_denied`

| Test ID | RPC | 输入摘要 | 期望响应 | 期望审计 |
|---|---|---|---|---|
| `CT-LIN-D006` | `UpsertProjectLineage` | 同 `project_id` 跨作用域写入（不同 device/user/app） | `accepted=false`, `deny_code=permission_denied` | `project.lineage.rejected` + `error_code=permission_denied` |

### 4.7 `dispatch_rejected`

| Test ID | RPC | 输入摘要 | 期望响应 | 期望审计 |
|---|---|---|---|---|
| `CT-DIS-D007` | `AttachDispatchContext` | dispatch 写入返回 rejected 且未提供更细粒度 deny_code（fallback） | `attached=false`, `deny_code=dispatch_rejected` | `project.lineage.rejected` + `error_code=dispatch_rejected` |

## 5) 成功路径最小集合（防“只测拒绝不测放行”）

| Test ID | RPC | 输入摘要 | 期望响应 | 期望审计 |
|---|---|---|---|---|
| `CT-LIN-S001` | `UpsertProjectLineage` | root 节点首次写入 | `accepted=true`, `created=true` | `project.lineage.upserted` |
| `CT-LIN-S002` | `UpsertProjectLineage` | child 幂等重复 upsert | 第一次 `created=true`，第二次 `created=false` | `project.lineage.upserted` |
| `CT-LIN-S003` | `GetProjectLineageTree` | root 全树查询 | 返回 root + child 节点 | （查询可不强制审计） |
| `CT-DIS-S001` | `AttachDispatchContext` | lineage 存在且 root 一致 | `attached=true`, `deny_code=''` | `project.dispatch.lineage_attached` |

## 6) 并行开发执行规则

- 任何分支若修改以下任一项，必须跑 `Gate-M3-0-CT`：
  - `protocol/hub_protocol_v1.proto` 中 M3-W1-03 相关 message/RPC；
  - `db.js` 中 `project_lineage` / `project_dispatch_context` 相关逻辑；
  - `services.js` 中 `UpsertProjectLineage/GetProjectLineageTree/AttachDispatchContext`。
- 任何分支若修改以下任一项，必须额外跑 deny_code 覆盖校验脚本：
  - `docs/memory-new/xhub-memory-v3-m3-lineage-contract-freeze-v1.md`
  - `docs/memory-new/xhub-memory-v3-m3-lineage-contract-tests-v1.md`
  - `x-hub/grpc-server/hub_grpc_server/src/memory_project_lineage.test.js`
  - `scripts/m3_check_lineage_contract_tests.js`
- 若新增 `deny_code`：
  1. 先更新 `xhub-memory-v3-m3-lineage-contract-freeze-v1.md` 字典；
  2. 再在本文件新增一组测试条目；
  3. 最后补充测试实现并接入 CI。
- 未通过 `Gate-M3-0-CT` 的分支不得合并主线。

## 7) 当前实现映射（2026-02-28）

- 测试实现文件：`x-hub/grpc-server/hub_grpc_server/src/memory_project_lineage.test.js`
- 已覆盖分组：
  - `lineage_parent_missing`
  - `lineage_cycle_detected`
  - `lineage_root_mismatch`
  - `parent_inactive`
  - `invalid_request`
  - `permission_denied`
  - `dispatch_rejected`
- CI 接入：`.github/workflows/m2-memory-bench.yml`
