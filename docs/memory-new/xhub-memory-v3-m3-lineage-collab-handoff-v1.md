# X-Hub Memory v3 M3-W1-03 协作交接手册（并行 AI 执行版）

- version: v1.0
- updatedAt: 2026-02-28
- owner: Hub Memory / QA / Security / X-Terminal
- status: active
- scope: `M3-W1-03`（Project Lineage + Dispatch Context）
- related:
  - `docs/memory-new/xhub-memory-v3-m3-lineage-contract-freeze-v1.md`
  - `docs/memory-new/xhub-memory-v3-m3-lineage-contract-tests-v1.md`
  - `scripts/m3_check_lineage_contract_tests.js`
  - `x-hub/grpc-server/hub_grpc_server/src/memory_project_lineage.test.js`
  - `x-hub/grpc-server/hub_grpc_server/src/services.js`
  - `x-hub/grpc-server/hub_grpc_server/src/db.js`

## 0) 用法（给协作 AI）

- 本手册目标：让任意协作 AI 可以在 10 分钟内理解 M3-W1-03 当前边界、执行门禁与交付格式。
- 执行原则：先读 contract freeze，再读 contract tests，再改代码；未过 Gate 不得合并。
- 变更默认 fail-closed：任何不确定情况返回 deny/downgrade，不允许隐式放行。

## 1) 最小阅读顺序（强制）

1. `docs/memory-new/xhub-memory-v3-m3-lineage-contract-freeze-v1.md`
2. `docs/memory-new/xhub-memory-v3-m3-lineage-contract-tests-v1.md`
3. `x-hub/grpc-server/hub_grpc_server/src/db.js`（lineage/dispatch 持久化真相源）
4. `x-hub/grpc-server/hub_grpc_server/src/services.js`（gRPC fail-closed 边界）
5. `x-hub/grpc-server/hub_grpc_server/src/memory_project_lineage.test.js`
6. `scripts/m3_check_lineage_contract_tests.js`

## 2) 不可破坏约束（Red Lines）

- 不允许删除或弱化以下 deny_code 语义：
  - `invalid_request`
  - `permission_denied`
  - `lineage_parent_missing`
  - `lineage_cycle_detected`
  - `lineage_root_mismatch`
  - `parent_inactive`
- 所有拒绝路径必须满足：
  - RPC 响应含 machine-readable `deny_code`
  - 审计写入 `project.lineage.rejected`
  - `error_code == deny_code`
- 不允许将 `lineage_path` 真相源下放到客户端；canonical 规则仅 Hub 可计算。
- 不允许把“contract 未冻结字段”作为放行前提。

## 3) 本地执行门禁命令（必须全绿）

```bash
node ./x-hub/grpc-server/hub_grpc_server/src/memory_project_lineage.test.js
node ./scripts/m3_check_lineage_contract_tests.js
```

补充（改了覆盖脚本本身时必须执行）：

```bash
node ./scripts/m3_check_lineage_contract_tests.test.js
```

## 4) 变更类型 -> 必跑项

- 修改 `db.js` 的 lineage/dispatch 写链路：
  - 必跑：`memory_project_lineage.test.js` + `m3_check_lineage_contract_tests.js`
- 修改 `services.js` 的 3 个 RPC：
  - 必跑：同上，并核对审计事件字段
- 修改 freeze/contract 文档：
  - 必跑：`m3_check_lineage_contract_tests.js`
  - 必做：同步测试 ID 映射到 `memory_project_lineage.test.js`
- 新增 deny_code：
  1. 先改 freeze 字典
  2. 再改 contract test 分组
  3. 再补测试实现
  4. 最后跑 Gate-M3-0-CT

## 5) 协作 AI 交付模板（提交说明最小集）

- 变更范围：`file@line` 列表（只列关键入口）
- 契约影响：`deny_code / 字段 / 状态机` 是否变更（若变更需指出冻结版本升级）
- 门禁结果：
  - `memory_project_lineage.test.js`: pass/fail
  - `m3_check_lineage_contract_tests.js`: pass/fail
  - （如适用）`m3_check_lineage_contract_tests.test.js`: pass/fail
- 风险与回滚：失败时回滚点、是否影响已有 deny_code 语义

## 6) X-Terminal 协作边界（并行不冲突）

- X-Terminal 只能消费 Hub 暴露的 lineage contract，不得自定义“平行 contract”。
- X-Terminal 若新增拆分字段，先提议到 Hub freeze 文档，冻结后再接入。
- UI 可视化字段应来自 `GetProjectLineageTree`，不从本地推断 parent/root。

## 7) Gate-M3-0-CT 通过定义（冻结）

- contract freeze、contract tests、测试实现三者映射一致。
- `CT-*` ID 在文档与测试文件中可双向追踪。
- 拒绝与成功路径审计行为均可被回归验证。
- CI 步骤通过：
  - `Run M3-W1-03 project lineage + dispatch fail-closed regression`
  - `Run Gate-M3-0-CT deny_code coverage checker`
