# X-Hub Memory 开源借鉴 Wave-1 执行包 v1

- version: v1.0
- updatedAt: 2026-03-19
- owner: Hub Memory / XT-L2 / Security / QA / Product
- status: proposed-active
- scope: 把 `xhub-memory-open-source-reference-adoption-checklist-v1.md` 中 `Wave-1` 的四项内容正式收敛成可执行包：`A3 bounded expansion grant`、`A4 large-file / large-blob sidecar`、`A5 session memory participation classes`、`A6 attachment visibility + blob ACL 分离`。本包只做“挂接、切片、边界、验收、回归、指标”收口，不引入第二套 memory architecture，不回改已冻结的 M2/M3 对外 contract。
- parent:
  - `docs/memory-new/xhub-memory-open-source-reference-adoption-checklist-v1.md`
  - `docs/memory-new/xhub-memory-open-source-reference-wave1-implementation-slices-v1.md`
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

## 0) One-Line Decision

冻结结论：

`Wave-1 的任务不是给 X-Hub 再增加一套“更自由”的记忆读取能力，而是把 deep recall、large blob、session writeback、attachment body 统一收进既有 grant / policy / audit / serving plane 主链。`

## 1) 固定边界（先看）

1. 本包不新增第二套长期真相源。
   - `Raw Vault / Observations / Longterm / Canonical / Working Set` 继续是唯一 durable truth source。
   - `sidecar`、`attachment body`、`selected chunks` 都只是受控旁路或受控投影，不升格为新的 canonical plane。

2. 本包不回改已冻结 M2/M3 外部 contract。
   - `search_index -> timeline -> get_details`
   - M3 lineage / XT-Ready / grant 主链
   - 本包允许冻结 child backlog 的 envelope、diagnostics、audit 字段，但不得平行改主协议语义。

3. 本包不允许 raw blob / attachment body 默认进 prompt。
   - 默认只能进：
     - compact refs
     - metadata
     - selected chunks
     - sanitized summary

4. 本包不允许 attachment/blob body 默认进 remote prompt bundle。
   - 任何 remote export 都必须继续服从现有 `prompt_bundle` gate 与 DLP fence。

5. 本包不允许 X-Terminal 或子 worker 直接绕过 Hub 读取 deep evidence。
   - deep read 必须走 Hub route、policy、grant、audit。

6. 本包不新增 cron 风暴。
   - sidecar cleanup、grant revoke、orphan reconcile、session-class 统计必须并入现有 worker / nightly maintenance / review cadence。

7. session participation 必须先于 promotion / writeback 生效。
   - 不允许 “先写 durable memory，再解释这轮本来不该写”。

## 2) 完成后应达到的状态

完成后，至少要满足 6 个事实：

1. `deep recall` 不再只是“多拿一点上下文”，而是一次有 TTL、可 revoke、可审计的 bounded expansion。
2. 超阈值 `file / blob / log / transcript / attachment body` 默认变成 sidecar + compact refs，而不是直接进 prompt。
3. session 是否读写 memory 不再靠调用方习惯，而是先经过统一的 participation class。
4. attachment metadata 与 attachment body 的权限语义彻底拆开，metadata 可见不等于 body 可读。
5. remote bundle、voice/channel brief、XT UI、Supervisor serving 对 blob/attachment/deep read 共享同一套 deny / downgrade 解释。
6. 上述四类借鉴全部挂在现有 parent docs 下推进，不形成新的 memory roadmap。

## 3) Wave-1 总览

| 波次项 | adoption 标签 | 主挂接轨道 | 当前类型 | 目标 |
| --- | --- | --- | --- | --- |
| bounded expansion grant | `A3` / `MRA-A3-*` | M3 Grant Chain + XT Memory Layer Usage + Supervisor Serving | child_backlog | 把 deep evidence read 收进 grant envelope |
| large-file / large-blob sidecar | `A4` / `MRA-A4-*` | XT/Hub Memory Layer Usage + Raw Evidence Fence | child_backlog | 超阈值 blob 改成 compact refs + selected chunks |
| session memory participation classes | `A5` / `MRA-A5-*` | XT Memory Governance + Supervisor Routing | child_backlog | 先分清哪些 session 能写、哪些只能读、哪些必须忽略 |
| attachment visibility + blob ACL | `A6` / `MRA-A6-*` | XT Memory Governance + Multimodal Control Plane | child_backlog | 把 metadata/body split 与 blob read grant binding 收口 |

## 4) 详细执行切片

### 4.1 `MRA-A5` Session Memory Participation Classes

目标：

- 把 “不是所有 session 都应该写入 memory” 从经验规则升级为统一 participation policy。

主挂接：

- `docs/memory-new/xhub-terminal-hub-memory-layer-usage-work-orders-v1.md`
- `docs/memory-new/xhub-supervisor-memory-routing-and-assembly-protocol-v1.md`
- `x-terminal/work-orders/xt-w3-38-i6-supervisor-memory-routing-and-assembly-implementation-pack-v1.md`

建议 touchpoints：

- `x-terminal/Sources/Supervisor/SupervisorManager.swift`
- `x-terminal/Sources/Hub/HubIPCClient.swift`
- `x-terminal/Sources/Chat/ChatSessionModel.swift`
- writeback / explainability / audit 相关状态面

#### `MRA-A5-01` Session Class Taxonomy

- 目标：
  - 冻结 `ignore / read_only / scoped_write` 三类 participation class。
- 最低冻结集：
  - `ignore`
  - `read_only`
  - `scoped_write`
- DoD：
  - 每类 session 都能先归到一个 class
  - class 先于 writeback classifier 生效
  - 不出现“无 class 也默认可写”的灰区

#### `MRA-A5-02` Default Class Assignment

- 目标：
  - 给高噪声 session 类型固定默认 class。
- 最低覆盖：
  - `cron`
  - `replay`
  - `test`
  - `synthetic`
  - `subagent`
  - `lane_worker`
  - `operator_probe`
- DoD：
  - cron / replay / test / synthetic 默认不得写 personal canonical
  - subagent 默认只能提 candidate，不得直接 durable promote
  - lane handoff 默认只走 refs / summary，不得偷偷写 user canonical

#### `MRA-A5-03` Session-Class Explainability

- 目标：
  - 让用户、QA、doctor 能看见“这轮为什么能写 / 不能写”。
- 最低输出：
  - `session_participation_class`
  - `write_permission_scope`
  - `writeback_block_reason`
- DoD：
  - explain / audit / diagnostics 对同一轮 session class 结论一致
  - 被 clamp 的 session 不会只在代码里默默吞掉

Gate 对齐：

- `XT-HM-14`
- `XT-HM-15`
- `XT-W3-38-I6`

非目标：

- 本轮不把 session class 扩成新的产品档位 UI
- 本轮不让 session class 直接改写 promotion gate 语义

### 4.2 `MRA-A3` Bounded Expansion Grant

目标：

- 把 raw evidence / selected chunk / deep traversal 的读取变成显式、可撤销、可审计的 grant 行为。

主挂接：

- `docs/memory-new/xhub-memory-v3-m3-work-orders-v1.md`
- `docs/memory-new/xhub-terminal-hub-memory-layer-usage-work-orders-v1.md`
- `docs/memory-new/xhub-supervisor-memory-serving-work-orders-v1.md`

建议 touchpoints：

- `protocol/hub_protocol_v1.proto`
- `x-hub/grpc-server/hub_grpc_server/src/services.js`
- `x-hub/grpc-server/hub_grpc_server/src/memory_metrics_schema.js`
- `x-terminal/Sources/Hub/HubIPCClient.swift`

#### `MRA-A3-01` Expansion Grant Envelope

- 目标：
  - 冻结 deep read 的最小 grant envelope。
- 最低字段：
  - `scope`
  - `granted_layers`
  - `max_tokens`
  - `expires_at`
  - `request_id`
- 建议附带：
  - `grant_ref`
  - `caller_surface`
  - `delegation_depth`
- DoD：
  - 所有 deep expand request 都能落到同一 envelope
  - 非法 layer 组合、scope 组合、TTL 组合默认 fail-closed
  - delegated expansion 默认不能再递归申请新的 expansion grant

#### `MRA-A3-02` `get_details` Deep-Read Enforcement

- 目标：
  - 无 grant 时 deny deep raw evidence / selected chunks。
- 最低行为：
  - `get_details` 或等价 deep-read path 无 grant 时 fail-closed
  - grant scope 不匹配时 fail-closed
  - grant 过期后 fail-closed
- DoD：
  - metadata / refs 列举与 body / selected chunks 读取被明确拆开
  - deep read 失败时返回稳定 deny_code
  - 不出现“先读到再补 grant”的逆序行为

#### `MRA-A3-03` Revoke + Telemetry

- 目标：
  - grant 生命周期可回放、可统计、可清理。
- 最低 telemetry：
  - `expanded_ref_count`
  - `source_tokens`
  - `truncated`
  - `revoke_reason`
- DoD：
  - timeout / cancel / explicit revoke 都有 machine-readable 记录
  - usage 统计能进入 metrics / weekly report
  - revoke 后旧 grant replay 继续 fail-closed

Gate 对齐：

- `M3-W1-02`
- `XT-HM-11`
- `SMS-W6`

非目标：

- 本轮不扩成新的 grant 产品页
- 本轮不新增独立 recall permission system

### 4.3 `MRA-A4` Large-File / Large-Blob Sidecar

目标：

- 把超长 `code/log/diff/transcript/blob` 从默认 prompt 路径移出，改成 compact refs + selected chunk retrieval。

主挂接：

- `docs/memory-new/xhub-terminal-hub-memory-layer-usage-work-orders-v1.md`
- `docs/memory-new/xhub-terminal-hub-memory-governance-work-orders-v1.md`

建议 touchpoints：

- `x-hub/grpc-server/hub_grpc_server/src/db.js`
- `x-hub/grpc-server/hub_grpc_server/src/services.js`
- `x-hub/grpc-server/hub_grpc_server/src/memory_remote_export_gate.js`
- `x-hub/macos/RELFlowHub/Sources/RELFlowHub/HubMemoryContextBuilder.swift`

#### `MRA-A4-01` Sidecar Threshold + Metadata Schema

- 目标：
  - 冻结哪些 file/blob 必须旁路进入 sidecar。
- 最低 metadata：
  - `blob_ref`
  - `blob_kind`
  - `byte_size`
  - `token_size_hint`
  - `sensitivity`
  - `trust_level`
  - `redaction_state`
  - `provenance_ref`
- DoD：
  - 超阈值 blob 默认不再直接塞进 turn content / prompt
  - metadata 足以回挂原始 blob
  - 阈值策略 deterministic，可回归

#### `MRA-A4-02` Selected-Chunk Retrieval Path

- 目标：
  - 把 “按 ref 取 selected chunks” 做成默认 deep-read 路径。
- 最低行为：
  - 主上下文只带 compact refs
  - `selected_chunks` 按 grant / budget / scope 受控读取
  - 默认无 full-body fetch
- DoD：
  - 编程项目的 log / diff / source file 查询优先走 selected chunks
  - route explain 能看见 chunk retrieval 是如何被触发的
  - 无 grant 或超预算时回落到 summary / refs

#### `MRA-A4-03` Sidecar Integrity / Retention

- 目标：
  - sidecar 不能成为长期 orphan blob 垃圾堆。
- 最低要求：
  - cleanup
  - orphan detection
  - provenance 校验
  - retention / restore 联动
- DoD：
  - retention delete / restore 后 sidecar 状态一致
  - sidecar orphan 可被 metrics / doctor 发现
  - provenance hash / ref mismatch 默认 fail-closed

Gate 对齐：

- `XT-HM-11`
- `XT-HM-13`
- `M2-W3-05`

非目标：

- 本轮不把 sidecar 升格成第二套 storage plane
- 本轮不做新的 blob search 产品层

### 4.4 `MRA-A6` Attachment Visibility + Blob ACL

目标：

- 把 “attachment metadata 可见” 和 “attachment body 可读” 明确拆成两层权限。

主挂接：

- `docs/memory-new/xhub-terminal-hub-memory-layer-usage-work-orders-v1.md`
- `docs/memory-new/xhub-terminal-hub-memory-governance-work-orders-v1.md`
- `docs/memory-new/xhub-multimodal-supervisor-control-plane-work-orders-v1.md`

建议 touchpoints：

- `protocol/hub_protocol_v1.proto`
- `x-hub/grpc-server/hub_grpc_server/src/services.js`
- `x-hub/grpc-server/hub_grpc_server/src/memory_remote_export_gate.js`
- multimodal / channel ingress 相关附件入口

#### `MRA-A6-01` Metadata / Body Split Contract

- 目标：
  - 冻结 attachment metadata 与 body 的分层读取语义。
- 最低 metadata：
  - `attachment_ref`
  - `mime_type`
  - `size`
  - `visibility`
  - `redaction_state`
- DoD：
  - metadata-only 成为默认返回
  - body 默认不随 metadata 自动放行
  - 不同 surface 对同一 attachment ref 的可见性解释一致

#### `MRA-A6-02` Remote Export Fence

- 目标：
  - attachment body 默认不得进 remote prompt bundle。
- 最低行为：
  - remote export 默认只带 metadata / summary / selected refs
  - 未明确授权的 attachment body 一律 deny
  - block 时给出稳定 deny / downgrade 语义
- DoD：
  - voice / channel / XT / mobile companion 对 remote export 语义一致
  - 不能因为是多模态 surface 就绕过正文门禁

#### `MRA-A6-03` Blob Read Grant Binding

- 目标：
  - attachment/blob body 的读取统一绑定到 scope / policy / grant / audit。
- 最低要求：
  - `grant_id`
  - `scope`
  - `audit_ref`
  - `body_read_reason`
- DoD：
  - blob body 读取与 `A3` expansion grant 语义一致
  - metadata route 不会误继承 body read 权限
  - replay / cross-surface reuse / grant drift 全部 fail-closed

Gate 对齐：

- `XT-HM-13`
- `MMS-W2`
- `MMS-W4`

非目标：

- 本轮不做新的附件产品库 UI
- 本轮不做附件 body 的开放式跨项目搜索

## 5) 建议执行顺序

### 5.1 第一组：先冻结低冲突边界

1. `MRA-A5-01`
2. `MRA-A5-02`
3. `MRA-A3-01`
4. `MRA-A4-01`
5. `MRA-A6-01`

原因：

- 先把 session / grant / blob / attachment 的词典定住，后面的 enforcement 才不会返工。

### 5.2 第二组：再上 enforcement

6. `MRA-A3-02`
7. `MRA-A4-02`
8. `MRA-A6-02`

原因：

- 这三项直接决定 raw evidence、selected chunks、attachment body 能不能越界读取或外发。

### 5.3 第三组：最后做 explainability / integrity / telemetry

9. `MRA-A3-03`
10. `MRA-A4-03`
11. `MRA-A5-03`
12. `MRA-A6-03`

原因：

- 先把主路径 clamp 住，再把 revoke、cleanup、audit、doctor、weekly report 补齐。

## 6) 建议归属与验收方式

### 6.1 Hub Memory

负责：

- `MRA-A3-*`
- `MRA-A4-*`

必须交付：

- grant / sidecar 主路径
- tests
- metrics
- integrity / retention evidence

### 6.2 XT-L2

负责：

- `MRA-A5-*`
- Supervisor / XT diagnostics / writeback explain 接线

必须交付：

- session class route
- writeback clamp
- explainability surface

### 6.3 Security

负责：

- `MRA-A3-*`
- `MRA-A6-*`

必须交付：

- grant fence
- attachment/blob body remote fence
- deny / downgrade consistency review

### 6.4 QA

负责：

- selected chunk / blob / grant / session pollution 回归
- require-real evidence
- 验证“不碰 frozen contract”

## 7) 本包完成定义（Pack DoD）

本包只有在以下条件都满足时才算完成：

1. `A3/A4/A5/A6` 都已有固定 parent host，不再是悬空借鉴点。
2. 每个 adoption 标签都已有：
   - owner
   - touchpoints
   - DoD
   - tests
   - gate / parent host
3. Wave-1 没有引入新的 memory architecture 名词体系。
4. Wave-1 没有把 sidecar / attachment body 升格为新的 truth source。
5. 至少有一份 ready-to-claim 切片文档可供直接认领。

## 8) 下一拍建议

本包落下后，最自然的下一拍是：

1. 直接按 `docs/memory-new/xhub-memory-open-source-reference-wave1-implementation-slices-v1.md` 认领 `W1-A5-S1 .. W1-A6-S3`
2. 先把 `A5` 挂到 XT/Supervisor writeback 与 explainability 主线
3. 再把 `A3/A4/A6` 分别并入 M3 grant、XT memory layer usage、multimodal attachment fence
4. 最后再考虑 `Wave-2`：
   - `A7` cross-link relation edges
   - `A10` async maintenance + degraded surfacing

一句话：

`Wave-1 的目标不是增加更多“能读到什么”，而是先把“谁能读、读多少、什么时候能读、读完如何回收”收紧。`
