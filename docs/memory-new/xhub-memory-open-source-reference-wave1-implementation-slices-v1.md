# X-Hub Memory 开源借鉴 Wave-1 实现切片 v1

- version: v1.0
- updatedAt: 2026-03-19
- owner: Hub Memory / XT-L2 / Security / QA
- status: proposed-active
- scope: 将 `xhub-memory-open-source-reference-wave1-execution-pack-v1.md` 继续下沉为 ready-to-claim 的实现切片，供后续直接认领、排期、联测与收口。所有切片都必须挂在现有 parent doc 下推进，不形成平行主线。
- parent:
  - `docs/memory-new/xhub-memory-open-source-reference-wave1-execution-pack-v1.md`
  - `docs/memory-new/xhub-memory-open-source-reference-adoption-checklist-v1.md`
  - `docs/memory-new/xhub-memory-v3-m3-work-orders-v1.md`
  - `docs/memory-new/xhub-terminal-hub-memory-layer-usage-work-orders-v1.md`
  - `docs/memory-new/xhub-terminal-hub-memory-governance-work-orders-v1.md`
  - `docs/memory-new/xhub-supervisor-memory-serving-work-orders-v1.md`
  - `docs/memory-new/xhub-supervisor-memory-routing-and-assembly-protocol-v1.md`
  - `docs/memory-new/xhub-multimodal-supervisor-control-plane-work-orders-v1.md`
  - `x-terminal/work-orders/xt-w3-38-i6-supervisor-memory-routing-and-assembly-implementation-pack-v1.md`
- related:
  - `protocol/hub_protocol_v1.proto`
  - `x-hub/grpc-server/hub_grpc_server/src/services.js`
  - `x-hub/grpc-server/hub_grpc_server/src/db.js`
  - `x-hub/grpc-server/hub_grpc_server/src/memory_remote_export_gate.js`
  - `x-hub/grpc-server/hub_grpc_server/src/memory_metrics_schema.js`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/HubMemoryContextBuilder.swift`
  - `x-terminal/Sources/Hub/HubIPCClient.swift`
  - `x-terminal/Sources/Supervisor/SupervisorManager.swift`

## 0) 使用方式

- 本文不是新的主设计文档，而是 `Wave-1` 的认领面。
- 每个切片都回答 7 个问题：
  - 做什么
  - 挂到哪份父文档
  - 主要改哪些文件
  - 完成标准是什么
  - 哪些测试必须补
  - 是否触碰 frozen contract
  - 建议谁认领
- 默认执行顺序：
  - 先 `A5`
  - 再 `A3`
  - 再 `A4`
  - 最后 `A6`

## 1) 全局约束

1. 不改 `search_index -> timeline -> get_details` 已冻结对外 contract。
2. 不改 `M3` lineage / XT-Ready / grant 主线的外部语义。
3. 不新增第二套 memory truth source。
4. 不把 `sidecar / attachment body / selected chunks` 变成默认 prompt 注入。
5. 不允许绕过 Hub policy / grant / audit 直接读 raw evidence。
6. 每个切片完成后都必须补可追溯证据：
   - 文档变更
   - 测试
   - metrics / explain / doctor evidence

## 2) Ready-to-Claim 切片总览

| Slice ID | 对应条目 | 目标 | 父轨 | 建议 owner | 预计粒度 |
| --- | --- | --- | --- | --- | --- |
| `W1-A5-S1` | `MRA-A5-01` | 冻结 session participation taxonomy | XT Memory Governance / Supervisor Routing | XT-L2 + Hub Policy | 0.5d |
| `W1-A5-S2` | `MRA-A5-02` | 固定高噪声 session 默认 class | XT Memory Governance / Runtime | XT-L2 | 0.5-1d |
| `W1-A5-S3` | `MRA-A5-03` | 暴露 session-class explainability | XT Explain / Audit | XT-L2 + QA | 0.5d |
| `W1-A3-S1` | `MRA-A3-01` | 冻结 expansion grant envelope | M3 Grant Chain / XT-HM | Hub Memory + Security | 0.5-1d |
| `W1-A3-S2` | `MRA-A3-02` | deep-read enforcement 接到 `get_details` | M3 Grant Chain / Retrieval Use | Hub Memory | 1d |
| `W1-A3-S3` | `MRA-A3-03` | revoke + telemetry 收口 | M3 Metrics / Audit | Hub Memory + QA | 0.5-1d |
| `W1-A4-S1` | `MRA-A4-01` | sidecar threshold + metadata schema | XT/Hub Layer Usage | Hub Memory + XT-L2 | 1d |
| `W1-A4-S2` | `MRA-A4-02` | selected-chunk retrieval path | XT/Hub Layer Usage | Hub Memory | 1d |
| `W1-A4-S3` | `MRA-A4-03` | sidecar integrity / retention | Reliability / Governance | Hub Memory + Security | 0.5-1d |
| `W1-A6-S1` | `MRA-A6-01` | metadata/body split contract | XT Memory Governance / MMS | Security + Hub Memory | 0.5-1d |
| `W1-A6-S2` | `MRA-A6-02` | remote export fence 扩到 attachment/blob body | Security / Multimodal | Security | 0.5-1d |
| `W1-A6-S3` | `MRA-A6-03` | blob read grant binding | M3 Grant + Attachment ACL | Security + Hub Memory | 0.5-1d |

## 3) `A5` 切片

### `W1-A5-S1` Freeze Session Participation Taxonomy

- 目标：
  - 把 session participation class 从口头经验升级为固定 taxonomy。
- 父轨：
  - `docs/memory-new/xhub-terminal-hub-memory-layer-usage-work-orders-v1.md`
  - `docs/memory-new/xhub-supervisor-memory-routing-and-assembly-protocol-v1.md`
- 主要文件：
  - `x-terminal/Sources/Supervisor/SupervisorManager.swift`
  - `x-terminal/Sources/Hub/HubIPCClient.swift`
- 最低交付：
  - 冻结 `ignore / read_only / scoped_write`
  - 解释每类 class 的 read / write / promote 边界
  - 非法 class fail-closed
- DoD：
  - 任一 session 都能归到一类
  - class 先于 writeback / promotion 判断
  - 无 undocumented class
- 必补测试：
  - taxonomy enum 正向/非法值
  - class precedence tests
- frozen contract 风险：
  - `none`
- 建议认领：
  - XT-L2 + Hub Policy

### `W1-A5-S2` Default Class Assignment

- 目标：
  - 给高噪声 session 固定默认 class。
- 父轨：
  - `docs/memory-new/xhub-terminal-hub-memory-layer-usage-work-orders-v1.md`
  - `x-terminal/work-orders/xt-w3-38-i6-supervisor-memory-routing-and-assembly-implementation-pack-v1.md`
- 主要文件：
  - `x-terminal/Sources/Supervisor/SupervisorManager.swift`
  - `x-terminal/Sources/Chat/ChatSessionModel.swift`
- 最低交付：
  - 默认覆盖：
    - `cron`
    - `replay`
    - `test`
    - `synthetic`
    - `subagent`
    - `lane_worker`
    - `operator_probe`
  - 默认 assignment matrix
- DoD：
  - cron / replay / test / synthetic 默认不得写 personal canonical
  - subagent 默认只能提 candidate
  - lane worker 默认不直接写 user canonical
- 必补测试：
  - default assignment matrix
  - negative case：误把 high-noise session 归为 `scoped_write`
- frozen contract 风险：
  - `none`
- 建议认领：
  - XT-L2

### `W1-A5-S3` Session-Class Explainability

- 目标：
  - 让 session class 成为可解释信号。
- 父轨：
  - `docs/memory-new/xhub-terminal-hub-memory-layer-usage-work-orders-v1.md`
  - `x-terminal/work-orders/xt-w3-38-i6-supervisor-memory-routing-and-assembly-implementation-pack-v1.md`
- 主要文件：
  - `x-terminal/Sources/Supervisor/SupervisorManager.swift`
  - explain / board / audit 相关状态面
- 最低交付：
  - 输出：
    - `session_participation_class`
    - `write_permission_scope`
    - `writeback_block_reason`
- DoD：
  - write 被 clamp 时可解释
  - doctor / UI / audit 对同一 session class 结果一致
- 必补测试：
  - explain payload
  - blocked write explain
- frozen contract 风险：
  - `none`
- 建议认领：
  - XT-L2 + QA

## 4) `A3` 切片

### `W1-A3-S1` Freeze Expansion Grant Envelope

- 目标：
  - 固定 deep-read grant 最小 envelope。
- 父轨：
  - `docs/memory-new/xhub-memory-v3-m3-work-orders-v1.md`
  - `docs/memory-new/xhub-terminal-hub-memory-layer-usage-work-orders-v1.md`
- 主要文件：
  - `protocol/hub_protocol_v1.proto`
  - `x-hub/grpc-server/hub_grpc_server/src/services.js`
- 最低交付：
  - 冻结字段：
    - `scope`
    - `granted_layers`
    - `max_tokens`
    - `expires_at`
    - `request_id`
  - 非法组合 fail-closed
- DoD：
  - deep-read 请求统一归入同一 envelope
  - delegated expansion 不能无限递归申请新 grant
- 必补测试：
  - envelope schema validation
  - TTL / scope / layer negative cases
- frozen contract 风险：
  - `low`
- 建议认领：
  - Hub Memory + Security

### `W1-A3-S2` `get_details` Deep-Read Enforcement

- 目标：
  - 把 grant enforcement 真正接到 deep-read path。
- 父轨：
  - `docs/memory-new/xhub-memory-v3-m3-work-orders-v1.md`
  - `docs/memory-new/xhub-terminal-hub-memory-layer-usage-work-orders-v1.md`
  - `docs/memory-new/xhub-supervisor-memory-serving-work-orders-v1.md`
- 主要文件：
  - `x-hub/grpc-server/hub_grpc_server/src/services.js`
  - `x-terminal/Sources/Hub/HubIPCClient.swift`
- 最低交付：
  - 无 grant deny
  - scope mismatch deny
  - expired grant deny
- DoD：
  - metadata / refs 与 body / selected chunks 读取彻底分开
  - deep-read deny_code 稳定
  - 不存在先读后补 grant
- 必补测试：
  - no grant deny
  - wrong scope deny
  - expired grant deny
  - layer mismatch deny
- frozen contract 风险：
  - `low`
- 建议认领：
  - Hub Memory

### `W1-A3-S3` Revoke + Telemetry

- 目标：
  - 让 expansion grant 生命周期可观测。
- 父轨：
  - `docs/memory-new/xhub-memory-v3-m3-work-orders-v1.md`
- 主要文件：
  - `x-hub/grpc-server/hub_grpc_server/src/memory_metrics_schema.js`
  - `x-hub/grpc-server/hub_grpc_server/src/services.js`
- 最低交付：
  - telemetry：
    - `expanded_ref_count`
    - `source_tokens`
    - `truncated`
    - `revoke_reason`
- DoD：
  - timeout / cancel / explicit revoke 都有审计
  - usage 进入 metrics / weekly report
- 必补测试：
  - timeout revoke
  - cancel revoke
  - telemetry schema validation
- frozen contract 风险：
  - `none`
- 建议认领：
  - Hub Memory + QA

## 5) `A4` 切片

### `W1-A4-S1` Sidecar Threshold + Metadata Schema

- 目标：
  - 冻结 file/blob 进入 sidecar 的阈值与 metadata。
- 父轨：
  - `docs/memory-new/xhub-terminal-hub-memory-layer-usage-work-orders-v1.md`
  - `docs/memory-new/xhub-terminal-hub-memory-governance-work-orders-v1.md`
- 主要文件：
  - `x-hub/grpc-server/hub_grpc_server/src/db.js`
  - `x-hub/grpc-server/hub_grpc_server/src/services.js`
- 最低交付：
  - threshold policy
  - metadata schema
  - provenance back-link
- DoD：
  - 超阈值 blob 默认不再直进 prompt
  - metadata 足以追到原始 blob
- 必补测试：
  - threshold positive/negative cases
  - metadata validation
- frozen contract 风险：
  - `low`
- 建议认领：
  - Hub Memory + XT-L2

### `W1-A4-S2` Selected-Chunk Retrieval Path

- 目标：
  - 用 selected chunks 替代 full-body fetch。
- 父轨：
  - `docs/memory-new/xhub-terminal-hub-memory-layer-usage-work-orders-v1.md`
- 主要文件：
  - `x-hub/grpc-server/hub_grpc_server/src/services.js`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/HubMemoryContextBuilder.swift`
- 最低交付：
  - compact refs
  - selected chunk retrieval
  - no full-body default
- DoD：
  - 编程项目类 log / diff / code file 查询默认走 selected chunks
  - grant / budget 不满足时回落到 refs / summary
- 必补测试：
  - selected chunk happy path
  - full-body default deny
  - over-budget fallback
- frozen contract 风险：
  - `low`
- 建议认领：
  - Hub Memory

### `W1-A4-S3` Sidecar Integrity / Retention

- 目标：
  - 补齐 sidecar cleanup、orphan detection、retention 对齐。
- 父轨：
  - `docs/memory-new/xhub-terminal-hub-memory-governance-work-orders-v1.md`
  - `docs/memory-new/xhub-memory-v3-m3-work-orders-v1.md`
- 主要文件：
  - `x-hub/grpc-server/hub_grpc_server/src/db.js`
  - `x-hub/grpc-server/hub_grpc_server/src/memory_metrics_schema.js`
- 最低交付：
  - orphan detection
  - cleanup
  - provenance integrity
  - retention / restore 联动
- DoD：
  - retention delete / restore 后 sidecar 状态一致
  - orphan sidecar 有可观测信号
- 必补测试：
  - orphan detection
  - retention delete cleanup
  - restore consistency
- frozen contract 风险：
  - `low`
- 建议认领：
  - Hub Memory + Security

## 6) `A6` 切片

### `W1-A6-S1` Metadata / Body Split Contract

- 目标：
  - 固定 attachment metadata 与 body 的分层语义。
- 父轨：
  - `docs/memory-new/xhub-terminal-hub-memory-layer-usage-work-orders-v1.md`
  - `docs/memory-new/xhub-multimodal-supervisor-control-plane-work-orders-v1.md`
- 主要文件：
  - `protocol/hub_protocol_v1.proto`
  - `x-hub/grpc-server/hub_grpc_server/src/services.js`
- 最低交付：
  - metadata 默认返回
  - body 默认不返回
  - visibility / redaction / size 解释一致
- DoD：
  - metadata 可见不等于 body 可读
  - 多 surface 语义一致
- 必补测试：
  - metadata-only path
  - body omitted by default
- frozen contract 风险：
  - `low`
- 建议认领：
  - Security + Hub Memory

### `W1-A6-S2` Remote Export Fence

- 目标：
  - attachment/blob body 默认不得外发到 remote bundle。
- 父轨：
  - `docs/memory-new/xhub-terminal-hub-memory-governance-work-orders-v1.md`
  - `docs/memory-new/xhub-multimodal-supervisor-control-plane-work-orders-v1.md`
- 主要文件：
  - `x-hub/grpc-server/hub_grpc_server/src/memory_remote_export_gate.js`
  - `x-hub/grpc-server/hub_grpc_server/src/services.js`
- 最低交付：
  - metadata / summary allowed
  - body default deny
  - block -> stable deny / downgrade
- DoD：
  - remote surface 不能因为多模态而绕过 body fence
  - local/remote 语义可回放
- 必补测试：
  - metadata allowed remote
  - body blocked remote
  - explicit allow path negative/positive matrix
- frozen contract 风险：
  - `low`
- 建议认领：
  - Security

### `W1-A6-S3` Blob Read Grant Binding

- 目标：
  - 把 attachment/blob body 读取绑定到统一 grant 语义。
- 父轨：
  - `docs/memory-new/xhub-memory-v3-m3-work-orders-v1.md`
  - `docs/memory-new/xhub-terminal-hub-memory-layer-usage-work-orders-v1.md`
- 主要文件：
  - `x-hub/grpc-server/hub_grpc_server/src/services.js`
  - `x-hub/grpc-server/hub_grpc_server/src/memory_metrics_schema.js`
- 最低交付：
  - `grant_id`
  - `scope`
  - `audit_ref`
  - `body_read_reason`
- DoD：
  - metadata route 不继承 body read 权限
  - replay / grant drift / cross-surface reuse fail-closed
- 必补测试：
  - missing grant deny
  - wrong grant deny
  - replay tamper deny
- frozen contract 风险：
  - `low`
- 建议认领：
  - Security + Hub Memory

## 7) 认领顺序建议

### 第一组：先冻结词典和默认边界

- `W1-A5-S1`
- `W1-A5-S2`
- `W1-A3-S1`
- `W1-A4-S1`
- `W1-A6-S1`

原因：

- 没有 taxonomy / envelope / metadata split，后面的 enforcement 容易漂。

### 第二组：再做主路径 enforcement

- `W1-A3-S2`
- `W1-A4-S2`
- `W1-A6-S2`

原因：

- 这组最直接决定 deep-read、selected chunk、remote attachment body 是否越界。

### 第三组：最后做 explain / cleanup / telemetry

- `W1-A3-S3`
- `W1-A4-S3`
- `W1-A5-S3`
- `W1-A6-S3`

原因：

- 先把权限和路径收紧，再补可观测性与长期运维面。

## 8) 本文完成定义

本文只有在以下条件都满足时才算完成：

1. `A3/A4/A5/A6` 每项至少有 3 个 ready-to-claim slices。
2. 每个 slice 都明确 parent host、DoD、tests、owner。
3. 默认执行顺序体现“低冲突先做、安全主路径优先”。
4. 不需要再回头讨论 “A3 那个 grant 到底指什么 / A6 的 ACL 是什么意思”。
