# X-Hub Memory v3 M3-W1-03 Contract Freeze（Gate-M3-0）

- version: v1.0
- frozenAt: 2026-02-28
- owner: Hub Memory / Runtime / Security / X-Terminal
- status: frozen
- scope: `M3-W1-03`（Project Lineage Contract + Dispatch Context）
- related:
  - `docs/memory-new/xhub-memory-v3-m3-work-orders-v1.md`
  - `docs/memory-new/xhub-memory-v3-execution-plan.md`
  - `protocol/hub_protocol_v1.proto`
  - `protocol/hub_protocol_v1.md`
  - `x-hub/grpc-server/hub_grpc_server/src/db.js`
  - `x-hub/grpc-server/hub_grpc_server/src/services.js`
  - `x-hub/grpc-server/hub_grpc_server/src/memory_project_lineage.test.js`
  - `docs/memory-new/xhub-memory-v3-m3-lineage-contract-tests-v1.md`
  - `scripts/m3_check_lineage_contract_tests.js`
  - `x-terminal/work-orders/xterminal-parallel-work-orders-v1.md`

## 1) 冻结范围

本冻结仅覆盖 M3-W1-03 的 contract/语义/边界行为，不覆盖 UI 样式与调度策略参数。

冻结对象：
- gRPC RPC：
  - `UpsertProjectLineage`
  - `GetProjectLineageTree`
  - `AttachDispatchContext`
- Message 字段语义（root/parent/project/lineage_path/split_round/split_reason/child_index + dispatch context）。
- `deny_code` 字典与 fail-closed 行为。
- 谱系边界规则（无环、无孤儿、无跨 root 串联、parent inactive 阻断、跨作用域隔离）。

非冻结对象（可演进）：
- `queue_priority` 的具体策略值与权重。
- `assigned_agent_profile` 的枚举集合。
- `expected_artifacts` 的业务枚举扩展。

## 2) 字段语义冻结（Lineage + Dispatch）

### 2.1 Lineage 关键字段

- `root_project_id`：整棵母子树的根项目 ID（必须稳定且一致）。
- `parent_project_id`：直接父项目；root 节点必须为空。
- `project_id`：当前项目 ID（在 Hub 中唯一）。
- `lineage_path`：规范路径（Hub 端 canonical），格式为 `root/.../project`。
- `parent_task_id`：从母项目拆分出的来源任务 ID（可选）。
- `split_round`：拆分轮次（`>= 0`）。
- `split_reason`：拆分原因（可选）。
- `child_index`：同父节点下的子序号（`>= 0`）。
- `status`：`active|archived`。

### 2.2 Dispatch 关键字段

- `assigned_agent_profile`：该子项目分配的 agent profile。
- `parallel_lane_id`：并行执行 lane。
- `budget_class`：预算等级标签。
- `queue_priority`：调度优先级（整数）。
- `expected_artifacts[]`：期望交付物列表。
- `attach_source`：`x_terminal|scheduler|manual`。

## 3) deny_code 字典（冻结）

| deny_code | 触发条件（冻结语义） | 动作 | retryable |
|---|---|---|---|
| `invalid_request` | 缺少必填字段或字段非法（例如 root/project/profile 为空） | `deny` | 视请求修正而定 |
| `permission_denied` | 同 `project_id` 在其他作用域已存在，或跨作用域写入 | `deny` | 否（需身份/作用域修正） |
| `lineage_parent_missing` | child 引用的 `parent_project_id` 不存在 | `deny` | 是（先补 parent） |
| `lineage_cycle_detected` | 写入后会形成环（含直接/间接环） | `deny` | 否（需调整拓扑） |
| `lineage_root_mismatch` | parent/root 不一致、跨 root 串联、lineage_path 非 canonical | `deny` | 否（需重建正确 root/路径） |
| `parent_inactive` | parent（或当前 lineage 依赖节点）已归档/不可写 | `deny` | 视 parent 恢复而定 |
| `dispatch_rejected` | dispatch 挂载未通过，但没有更细粒度 code（保底） | `deny` | 视具体原因 |

约束（冻结）：
- 未识别或未覆盖的异常必须 fail-closed，不得隐式放行。
- `deny_code` 必须 machine-readable，禁止只返回自然语言。
- `project.lineage.rejected` 审计必须写入 `deny_code`。
- `Gate-M3-0-CT` 必须对 freeze / contract-tests / test-source 做零漂移校验（包含 `dispatch_rejected`）。
- deny 分组 `CT-*` 必须是 `*-Dxxx`，且每个 deny `CT-ID` 在 test-source 中仅允许一个代码块映射。
- test-source 中出现的 `deny_code` / `CT-ID` 必须在 contract-tests 文档有且仅有一个映射来源（禁止 source 侧“超前新增”）。
- freeze 字典中的 `deny_code` 行必须唯一（禁止重复键覆盖语义）。
- contract-tests 中 deny_code 分组标题必须唯一（禁止重复分组造成映射歧义）。

## 4) 边界行为冻结（Fail-Closed）

### 4.1 拓扑边界

- root 节点规则：
  - `parent_project_id` 为空；
  - `project_id == root_project_id`；
  - 否则 `lineage_root_mismatch` 或 `lineage_parent_missing`。
- child 节点规则：
  - `parent_project_id` 必填；
  - parent 必须存在且 `status=active`；
  - parent 的 `root_project_id` 必须与 child 一致。
- 环检测规则：
  - 以 `parent -> ... -> root` 逐级回溯；
  - 遇到已访问项目即 `lineage_cycle_detected`；
  - 任一父链缺失即 `lineage_parent_missing`。

### 4.2 路径边界

- `lineage_path` 由 Hub 按 canonical 规则计算：
  - root：`project_id`
  - child：`parent.lineage_path + '/' + project_id`
- 当客户端提交 `lineage_path` 时，仅允许与 canonical 完全一致；否则 `lineage_root_mismatch`。

### 4.3 作用域与隔离边界

- `project_id` 在 Hub 侧采用全局唯一主键；若已有记录属于其他 `(device_id,user_id,app_id)`，新写入一律 `permission_denied`。
- dispatch attach 必须依赖已存在且可写的 lineage 节点。
- dispatch 的 `root_project_id/parent_project_id` 必须与 lineage 真相源一致，否则 `lineage_root_mismatch`。

### 4.4 查询边界

- `GetProjectLineageTree`：
  - `root_project_id` 必填；
  - `project_id` 可选（用于 subtree）；
  - `max_depth <= 0` 视为默认不截断；
  - `include_archived=false` 时过滤 archived 节点。

### 4.5 幂等边界

- v1 幂等语义按 `project_id` upsert（重复写入同一项目不会产生重复节点）。
- `request_id` 作为审计/追踪字段冻结保留，不作为独立幂等表主键。

## 5) 审计事件冻结

- 成功：
  - `project.lineage.upserted`
  - `project.dispatch.lineage_attached`
- 失败：
  - `project.lineage.rejected`（必须包含 `deny_code`）

审计最小字段（冻结）：
- `request_id`
- `project_id`
- `root_project_id`
- `parent_project_id`
- `deny_code`（失败必填）

## 6) Gate-M3-0 冻结验收（执行记录）

- [x] proto 与 md contract 已同步（M3-W1-03 RPC/消息）。
- [x] DB 持久化表与索引已落地（lineage/dispatch）。
- [x] fail-closed 规则已落地（deny_code 语义冻结）。
- [x] 回归样例已落地并纳入 CI（`x-hub/grpc-server/hub_grpc_server/src/memory_project_lineage.test.js` + `.github/workflows/m2-memory-bench.yml`）。
- [x] deny_code 分组覆盖检查器已落地并纳入 CI（`scripts/m3_check_lineage_contract_tests.js` + `.github/workflows/m2-memory-bench.yml`）。

## 7) 变更控制

- 本文件是 M3-W1-03 的唯一冻结记录。
- 以下变更必须 `v1 -> v2`：
  - 删除/重命名冻结字段；
  - 改变 deny_code 语义；
  - 放宽 fail-closed 约束为 fail-open。
- 仅新增可选字段时，可在 v1.x 追加，但需补齐回归与迁移说明。
